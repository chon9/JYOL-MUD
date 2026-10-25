extends "res://tests/unit/test_world_fixture.gd"
## 江湖試煉驗收劇本（ROGUE_PLAN §9.3）【設計提案・非原作】。由 tools/rogue_acceptance.gd 的 worker 建立（不是單元測試：
## 檔名不以 test_ 開頭，執行器不會撿到）。沿用整合測試的世界夾具，但開的是真的 WorldServer.start_rogue（記憶體內的試煉世界）
## ＋GameHost＋--debug-intents 的 intent 路徑；每個劇本一個全新的測試根目錄子資料夾（test_tmp/），結束時 after_each 收掉。
## 測試捷徑（不是受測物）：rogue_debug 固定卡與對手、直接把角色調強或調弱、把隊友直接打倒（勝負不是受測物，結算才是）。
## 每個劇本回傳一行摘要（info）；失敗以 failures 陣列回報（assert_*）。

const RG_ATTRS := ["str", "con", "agi", "guts", "cal", "wit", "luck"]

var info := ""
var _old_debug := false
var _mud_first := false   # mud_unaffected：先開 MUD 世界

func note(t: String) -> void:
	info += ("；" if info != "" else "") + t

# ======================================================================== 夾具
func before_each() -> void:
	ws = tree.root.get_node("WorldServer")
	cs = tree.root.get_node("ClientState")
	sm = tree.root.get_node("SaveManager")
	tree.root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_restore_rules()
	dir = temp_dir("rogue_acc")
	_old_root = sm.root_dir
	sm.root_dir = dir
	events.clear()
	results.clear()
	my_uid = 0
	_await_me = false
	_old_debug = ws.debug_intents
	ws.debug_intents = true
	if current_test == "mud_unaffected":
		world_name = "w_rg_mud"
		assert_eq(ws.start(world_name), OK, "start MUD")
	else:
		assert_eq(ws.start_rogue(0), OK, "start_rogue")
	ws.rng.seed = 20261022
	_begin()
	cs.events_received.connect(_on_events)
	cs.intent_result.connect(_on_result)
	cs.battle_opened.connect(_on_battle_opened)

func _begin() -> void:
	cs.begin_local_session()
	if ws.sessions.has(1):
		ws.sessions[1].rate_limiter = TokenBucket.new(1000000.0, 1000000.0)
	ws.flush()

func after_each() -> void:
	super.after_each()
	ws.debug_intents = _old_debug

func _state() -> Dictionary:
	return lastp("rogue_state")

func _rules() -> Dictionary:
	return RogueRules.rules(tables())

## 開局：分配 alloc_points（輪流加到七項，單項不超過 45）
func _alloc_for(st: Dictionary) -> Dictionary:
	var alloc := {}
	var left := int(st.get("alloc_points", 0))
	while left > 0:
		var moved := false
		for a in RG_ATTRS:
			if left > 0 and int(st.roll[a]) + int(alloc.get(a, 0)) < 45:
				alloc[a] = int(alloc.get(a, 0)) + 1
				left -= 1
				moved = true
		if not moved:
			break
	return alloc

func _start(seed_v := 12345) -> Dictionary:
	ok("rogue_open", { "seed": seed_v })
	var st := _state()
	ok("rogue_start", { "alloc": _alloc_for(st), "name": "驗收試煉" })
	return _state()

## 固定三張卡，選第 idx 張
func _take(ids: Array, idx: int, alloc: Dictionary = {}) -> void:
	ok("rogue_debug", { "op": "cards", "ids": ids })
	var args := { "idx": idx }
	if not alloc.is_empty():
		args["alloc"] = alloc
	ok("rogue_pick", args)

func _strong(lv := 80) -> void:
	var c = ch()
	for a in ["str", "agi", "con", "guts", "cal"]:
		c.attrs[a] = 45
	for k in ["basic_blade", "basic_sword", "basic_fist", "basic_dodge", "basic_parry"]:
		c.skills.set_level(k, lv, tables())
	c.clamp_vitals(tables(), ws.options)
	Survival.rest_full(c, tables(), ws.options)

func _weak() -> void:
	var c = ch()
	for a in ["str", "agi", "con", "guts", "cal"]:
		c.attrs[a] = 13
	c.skills = SkillBook.new()
	c.clamp_vitals(tables(), ws.options)
	c.vitals["qi"] = 20

func _entry() -> Dictionary:
	return host().battles.active.get(s().battle_id, {}) if s().battle_id != 0 else {}

func _safe_pick_idx(st: Dictionary) -> int:
	for c in st.get("cards", []):
		if str(c.kind) != "ATTR":
			return int(c.idx)
	return 0

func _pick_any(st: Dictionary) -> void:
	var idx := _safe_pick_idx(st)
	var card: Dictionary = {}
	for c in st.cards:
		if int(c.idx) == idx:
			card = c
	var args := { "idx": idx }
	if str(card.get("kind", "")) == "ATTR":
		args["alloc"] = { "str": int(card.points) }
	ok("rogue_pick", args)

# ======================================================================== 劇本
## start_run：ALLOC（擲骰 13–25、alloc_points = 5＋profile）→ 少 1 點、超 45 → 錯誤；正確 → PICK、三張卡、兩種以上；只有布衣木刀、沒有武功
func sc_start_run() -> void:
	ok("rogue_open", { "seed": 12345 })
	var st := _state()
	assert_eq(str(st.phase), "ALLOC", "phase ALLOC")
	for a in Character.ATTR_IDS:
		assert_true(int(st.roll[a]) >= 13 and int(st.roll[a]) <= 25, "擲骰 %s=%d 在 13–25" % [a, int(st.roll[a])])
	var p := RogueProfile.read(sm.root_dir)
	assert_eq(int(st.alloc_points), CharacterFactory.FREE_POINTS + int(p.points_total), "alloc_points = 5＋永久點數")
	var short := _alloc_for(st)
	for a in short:
		if int(short[a]) > 0:
			short[a] = int(short[a]) - 1
			break
	assert_eq(reason("rogue_start", { "alloc": short }), "rogue_bad_alloc", "少 1 點")
	# 單項超 45：先給 30 點永久點數再重開
	ok("rogue_debug", { "op": "points", "n": 30 })
	ok("rogue_open", { "seed": 12345 })
	st = _state()
	assert_eq(int(st.alloc_points), 35)
	var over := { "str": int(st.alloc_points) }
	assert_eq(reason("rogue_start", { "alloc": over }), "rogue_attr_cap", "單項超 45")
	ok("rogue_start", { "alloc": _alloc_for(st), "name": "驗收試煉" })
	st = _state()
	assert_eq(str(st.phase), "PICK", "PICK")
	assert_eq((st.cards as Array).size(), 3, "三張卡")
	var kinds := {}
	for c in st.cards:
		kinds[str(c.kind)] = true
	assert_true(kinds.size() >= 2, "至少兩種種類：%s" % str(kinds.keys()))
	var c = ch()
	assert_eq(c.inventory.items.size(), 2, "只有兩件物品")
	assert_eq(c.inventory.count("a_bupao"), 1, "布衣")
	assert_eq(c.inventory.count("w_mudao"), 1, "木刀")
	assert_true(c.skills.special_arts(tables()).is_empty(), "沒有武功")
	assert_eq(s().room_id(), "rg_hall", "在江湖試煉場")
	note("roll=%s alloc=%d cards=%s" % [str(st.roll.values()), int(_state().alloc_points), ",".join((st.cards as Array).map(func(x): return str(x.id)))])

## pick_each_kind：ART／WEAPON／ATTR（含不給 alloc）／ALLY；第三位隊友 → rogue_ally_full
func sc_pick_each_kind() -> void:
	_start()
	var c = ch()
	# ART
	_take(["rg_c_art_hs_jianfa", "rg_c_attr_fine", "rg_c_wpn_w_qingfeng"], 0)
	var lv: int = c.skills.level("hs_jianfa")
	assert_true(lv >= 25, "華山劍法 %d ≥ 25" % lv)
	assert_true(c.skills.level("basic_sword") >= lv, "基本劍法跟上 %d" % c.skills.level("basic_sword"))
	_next_pick()
	# WEAPON
	_take(["rg_c_wpn_w_qingfeng", "rg_c_attr_fine", "rg_c_art_hs_jianfa"], 0)
	assert_eq(str(c.inventory.equipped_row("WEAPON", tables()).get("id", "")), "w_qingfeng", "已裝備青鋒劍")
	_next_pick()
	# ATTR：不給 alloc → rogue_bad_alloc；給 str 4 → +4
	ok("rogue_debug", { "op": "cards", "ids": ["rg_c_attr_fine", "rg_c_wpn_w_qingfeng", "rg_c_art_hs_jianfa"] })
	assert_eq(reason("rogue_pick", { "idx": 0 }), "rogue_bad_alloc", "ATTR 不給 alloc")
	var pts := int((_state().cards as Array)[0].points)
	var str0 := int(c.attrs.str)
	ok("rogue_pick", { "idx": 0, "alloc": { "str": pts } })
	assert_eq(int(c.attrs.str), str0 + pts, "str +%d" % pts)
	_next_pick()
	# ALLY ×2，第三位 → rogue_ally_full
	_take(["rg_c_ally_zhouzhiruo", "rg_c_attr_fine", "rg_c_wpn_w_qingfeng"], 0)
	assert_eq((_state().allies as Array).size(), 1, "一位隊友")
	assert_eq(str(_state().allies[0].name), "周芷若")
	_next_pick()
	_take(["rg_c_ally_hufei", "rg_c_attr_fine", "rg_c_wpn_w_qingfeng"], 0)
	_next_pick()
	ok("rogue_debug", { "op": "cards", "ids": ["rg_c_ally_zhangsongxi", "rg_c_attr_fine", "rg_c_wpn_w_qingfeng"] })
	assert_eq(reason("rogue_pick", { "idx": 0 }), "rogue_ally_full", "第三位隊友")
	note("hs_jianfa=%d basic_sword=%d str+%d allies=%d" % [lv, c.skills.level("basic_sword"), pts, (_state().allies as Array).size()])

## 測試捷徑：READY → 回到 PICK（用 round 除錯不改 phase；直接改 run 的 phase 並重抽）
func _next_pick() -> void:
	var run: RogueRun = host().rogue.run_of(s())
	run.phase = "PICK"
	run.cards = RogueDraw.draw(run, ch(), tables(), run.rng_for("draw"), "")

## 跑一場到結束（自己的驅動：記錄全部事件）
func _fight_to_end(policy := "fight", max_s := 900.0) -> Dictionary:
	return drive_battle(policy, max_s)

## win_round：固定弱對手 → ROGUE、no_flee → 勝 → rogue_round_won、round 2、PICK、35% 規則；沒有實戰學點錢、沒有屍體
func sc_win_round() -> void:
	_start()
	ws.options["wait_mode"] = false
	_take(["rg_c_art_xd_daofa", "rg_c_attr_common", "rg_c_wpn_w_gangdao"], 0)
	_strong()
	var xp0 := int(ch().combat_xp)
	var lp0 := int(ch().learn_points)
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_wolf"] })
	clear_events()
	ok("rogue_fight")
	var ent := _entry()
	assert_eq(str(ent.get("kind", "")), "ROGUE", "battle kind ROGUE")
	if not ent.is_empty():
		assert_true(bool(ent.battle.opts.get("no_flee", false)), "no_flee")
	var res := _fight_to_end()
	assert_eq(str(res.get("result", "")), "VICTORY", "勝")
	assert_eq(str(res.get("kind", "")), "ROGUE", "result.kind")
	var won := lastp("rogue_round_won")
	assert_false(won.is_empty(), "rogue_round_won")
	var st := _state()
	assert_eq(int(st.round), 2, "round 2")
	assert_eq(str(st.phase), "PICK", "PICK")
	var d: Dictionary = ch().derived(tables(), ws.options)
	var cap := int(floor(int(d.qi_max) * float(_rules().get("restore_pct", 0.35))))
	var qi_now := int(ch().vitals.qi)
	assert_true(int(won.qi) <= cap, "氣回復 %d ≤ 35%% (%d)" % [int(won.qi), cap])
	assert_true(int(won.qi) == cap or qi_now == int(d.qi_max), "氣回復 = min(35%%, 缺的) (%d, now %d/%d)" % [int(won.qi), qi_now, int(d.qi_max)])
	assert_eq(int(ch().combat_xp), xp0, "沒有實戰")
	assert_eq(int(ch().learn_points), lp0, "沒有學點")
	assert_eq(int(ch().money), 0, "沒有錢")
	assert_true((ws.world.get("corpses", []) as Array).is_empty(), "沒有屍體")
	note("qi+%d (cap %d, now %d/%d) round=%d" % [int(won.qi), cap, qi_now, int(d.qi_max), int(st.round)])

func _ally_unit(b: Battle) -> BattleUnit:
	for u in b.units:
		if str(u.spec.get("rg_ally", "")) != "":
			return u
	return null

## ally_acts：隊友至少行動 2 次、目標全是 side 1；隊友倒下但玩家贏 → rogue_ally_fallen、alive false、之後抽卡不出同一位
func sc_ally_acts() -> void:
	_start()
	ws.options["wait_mode"] = false
	_take(["rg_c_ally_zhouzhiruo", "rg_c_attr_common", "rg_c_wpn_w_gangdao"], 0)
	_strong()
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_heixiong", "rg_f_menghu"] })
	clear_events()
	ok("rogue_fight")
	var ent := _entry()
	var b: Battle = ent.get("battle")
	var au := _ally_unit(b) if b != null else null
	if not assert_true(au != null, "戰場上有隊友單位"):
		return
	assert_eq(au.kind(), "ALLY", "kind ALLY")
	assert_eq(int(au.side), 0, "隊友在 side 0")
	var auid := int(au.uid)
	# 玩家先只防守，讓隊友出手（最多 120 秒），之後一起打完
	var acts := 0
	var bad := 0
	var t := 0.0
	var bid := s().battle_id
	var seen := 0
	while s().battle_id == bid and t < 900.0:
		var me = _my_unit(b)
		if me != null and str(me.state) == "READY":
			var cmd := _choose(b, "defend" if acts < 2 and t < 120.0 else "fight")
			cmd["battle_id"] = bid
			var r := send("battle_cmd", cmd)
			if not r.get("ok", false):
				send("battle_cmd", { "battle_id": bid, "cmd": "DEFEND" })
		ws.advance(0.1)
		t += 0.1
		while seen < events.size():
			var e: Dictionary = events[seen]
			seen += 1
			var p: Dictionary = e.get("p", {}) if e.get("p") is Dictionary else {}
			if int(p.get("atk_uid", 0)) == auid and not bool(p.get("counter", false)):
				acts += 1
				var def := b.unit(int(p.get("def_uid", 0)))
				if def != null and int(def.side) != 1:
					bad += 1
			elif str(e.get("key", "")) == "battle_move" and int(p.get("uid", 0)) == auid:
				acts += 1
	assert_eq(s().battle_id, 0, "第一場結束")
	assert_true(acts >= 2, "隊友行動 %d 次 ≥ 2" % acts)
	assert_eq(bad, 0, "隊友只打 side 1")
	var res1: Dictionary = cs.last_battle_result
	assert_eq(str(res1.get("result", "")), "VICTORY", "第一場勝")
	# 第二場：開戰後隊友被打倒（捷徑），玩家照樣打贏（第一場隊友若已倒下，先再招一位）
	_next_pick()
	if host().rogue.run_of(s()).alive_allies().is_empty():
		_take(["rg_c_ally_hufei", "rg_c_attr_common", "rg_c_wpn_w_mujian"], 0)
	else:
		_take(["rg_c_attr_common", "rg_c_art_basic_parry", "rg_c_wpn_w_mujian"], 1)
	var alive: Array = host().rogue.run_of(s()).alive_allies()
	var want_name := str(alive[0].name) if not alive.is_empty() else ""
	var want_card := str(alive[0].card_id) if not alive.is_empty() else ""
	_strong()
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_wolf"] })
	clear_events()
	ok("rogue_fight")
	b = _entry().get("battle")
	au = _ally_unit(b) if b != null else null
	if not assert_true(au != null, "第二場有隊友"):
		return
	var foe: BattleUnit = null
	for u in b.units:
		if int(u.side) == 1:
			foe = u
	BattleRules.kill(b, au, foe)
	var res2 := drive_battle("fight", 600.0)
	assert_eq(str(res2.get("result", "")), "VICTORY", "隊友倒下、玩家贏")
	assert_false(evs("rogue_ally_fallen").is_empty(), "rogue_ally_fallen")
	assert_eq(str(lastp("rogue_ally_fallen").get("name", "")), want_name)
	var st := _state()
	for a in st.allies:
		if str(a.name) == want_name:
			assert_false(bool(a.alive), "%s alive == false" % want_name)
	assert_true((res2.get("rogue", {}).get("allies_fallen", []) as Array).has(want_name), "close.rogue.allies_fallen")
	# 之後的抽卡不出同一位（30 次不同亂數）
	var run: RogueRun = host().rogue.run_of(s())
	var hit := 0
	for i in 30:
		var g := RandomNumberGenerator.new()
		g.seed = 9000 + i
		for card in RogueDraw.draw(run, ch(), tables(), g, "RARE"):
			if str(card.id) == want_card:
				hit += 1
	assert_eq(hit, 0, "倒下的隊友不再出現")
	note("ally acts=%d fallen=%s" % [acts, str(res2.get("rogue", {}).get("allies_fallen", []))])

## lose_run：固定極強對手 → 玩家倒下（隊友還活著也一樣）→ over、summary 齊全、DEATH → profile 點數＝award、runs +1、history[0]
func sc_lose_run() -> void:
	_start()
	ws.options["wait_mode"] = false
	_take(["rg_c_ally_hs_dizi", "rg_c_attr_common", "rg_c_wpn_w_gangdao"], 0)
	_weak()
	var p0 := RogueProfile.read(sm.root_dir)
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_zhangsanfeng"] })
	clear_events()
	ok("rogue_fight")
	var b: Battle = _entry().get("battle")
	var au := _ally_unit(b) if b != null else null
	if not assert_true(au != null, "有隊友"):
		return
	# 測試捷徑：讓隊友扛得住（氣很多）；玩家防守挨打，60 秒內沒倒就直接打倒（勝負不是受測物）→ 隊友還活著也判負（O6）
	au.spec["qi_max"] = 999999
	au.qi = 999999
	var bid := s().battle_id
	var t := 0.0
	while s().battle_id == bid and t < 60.0:
		var me = _my_unit(b)
		if me != null and str(me.state) == "READY":
			send("battle_cmd", { "battle_id": bid, "cmd": "DEFEND" })
		ws.advance(0.1)
		t += 0.1
	if s().battle_id == bid:
		var foe: BattleUnit = null
		for u in b.units:
			if int(u.side) == 1 and u.is_active():
				foe = u
		BattleRules.kill(b, _my_unit(b), foe)
		b._check_end(tables())
		var n := 0
		while s().battle_id == bid and n < 200:
			ws.advance(0.1)
			n += 1
		note("player felled by shortcut after 60 s")
	var res: Dictionary = cs.last_battle_result
	assert_eq(str(res.get("result", "")), "DEFEAT", "判負")
	assert_false(au.is_dead(), "隊友還活著")
	assert_true(bool(res.get("rogue", {}).get("over", false)), "close.rogue.over")
	var ally_alive := not au.is_dead()
	var over := lastp("rogue_over")
	for k in ["run_id", "seed", "cause", "rounds", "wins", "foes_beaten", "bosses_beaten", "best_card", "allies_recruited",
			"points_gained", "points_total", "new_best"]:
		assert_true(over.has(k), "summary 有 %s" % k)
	assert_eq(str(over.get("cause", "")), "DEATH", "cause DEATH")
	var p := RogueProfile.read(sm.root_dir)
	var want := RogueRules.award(int(over.wins), int(over.bosses_beaten), int(p0.points_total), bool(over.new_best), _rules())
	assert_eq(int(p.points_total) - int(p0.points_total), want, "點數增加＝award")
	assert_eq(int(p.runs), int(p0.runs) + 1, "runs +1")
	assert_eq(str(p.history[0].cause), "DEATH", "history[0].cause")
	assert_eq(int(p.history[0].wins), int(over.wins), "history[0].wins")
	assert_eq(str(_state().phase), "OVER")
	assert_eq(reason("rogue_fight"), "rogue_phase", "OVER 之後 rogue_fight → rogue_phase")
	note("over wins=%d points+%d ally_alive_at_end=%s" % [int(over.wins), want, str(ally_alive)])

## points_persist：lose 之後 stop → 再 start_rogue → alloc_points = 5＋新的總點數；points 59 → 再輸一局 → 60（上限）
func sc_points_persist() -> void:
	_start()
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_wolf"] })
	_take(["rg_c_art_xd_daofa", "rg_c_attr_common", "rg_c_wpn_w_gangdao"], 0)
	ws.options["wait_mode"] = false
	_strong()
	ok("rogue_fight")
	drive_battle("fight", 600.0)
	_pick_any(_state())
	_weak()
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_zhangsanfeng"] })
	ok("rogue_fight")
	drive_battle("defend", 900.0)
	assert_eq(str(_state().phase), "OVER", "第一局結束")
	var total := int(RogueProfile.read(sm.root_dir).points_total)
	assert_true(total >= 1, "拿到點數 %d" % total)
	# 關掉試煉世界再開
	_reopen()
	ok("rogue_open", {})
	assert_eq(int(_state().alloc_points), CharacterFactory.FREE_POINTS + total, "alloc_points = 5＋%d" % total)
	# 上限：points 59 → 再贏兩場輸一局
	ok("rogue_debug", { "op": "points", "n": 59 })
	ok("rogue_open", {})
	_start()
	ws.options["wait_mode"] = false
	for i in 3:
		_pick_any(_state())
		_strong(120)
		ok("rogue_debug", { "op": "foes", "ids": ["rg_f_wolf"] })
		ok("rogue_fight")
		drive_battle("fight", 600.0)
	_pick_any(_state())
	_weak()
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_zhangsanfeng"] })
	ok("rogue_fight")
	drive_battle("defend", 900.0)
	var over := lastp("rogue_over")
	var p := RogueProfile.read(sm.root_dir)
	assert_eq(int(p.points_total), int(_rules().get("points_cap", 60)), "總數到上限 60")
	assert_eq(int(over.get("points_gained", 0)), 1, "只加到上限")
	note("first total=%d; cap run wins=%d gained=%d total=%d" % [total, int(over.wins), int(over.points_gained), int(p.points_total)])

func _reopen() -> void:
	cs.events_received.disconnect(_on_events)
	cs.intent_result.disconnect(_on_result)
	cs.battle_opened.disconnect(_on_battle_opened)
	ws.stop()
	cs.reset()
	assert_eq(ws.start_rogue(0), OK, "再 start_rogue")
	_begin()
	cs.events_received.connect(_on_events)
	cs.intent_result.connect(_on_result)
	cs.battle_opened.connect(_on_battle_opened)

## boss_round：round 5 → next_round_is_boss → 打首領（固定周芷若）→ rogue_boss → 贏 → extra_picks 1、三張都 ≥ 稀 → 選完再一次一般 PICK
func sc_boss_round() -> void:
	_start()
	ws.options["wait_mode"] = false
	_take(["rg_c_art_xd_daofa", "rg_c_attr_common", "rg_c_wpn_w_gangdao"], 0)
	ok("rogue_debug", { "op": "round", "n": 5 })
	assert_true(bool(_state().next_round_is_boss), "next_round_is_boss")
	_strong(120)
	ch().skills.set_level("xd_daofa", 140, tables())
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_zhouzhiruo"] })
	clear_events()
	ok("rogue_fight")
	assert_false(evs("rogue_boss").is_empty(), "rogue_boss 事件")
	var res := drive_battle("fight", 900.0)
	assert_eq(str(res.get("result", "")), "VICTORY", "打贏周芷若")
	var st := _state()
	assert_eq(int(st.bosses_beaten), 1, "bosses_beaten 1")
	assert_eq(int(st.extra_picks), 1, "extra_picks 1")
	var rar: Array = []
	for card in st.cards:
		rar.append(str(card.rarity))
		assert_true(RogueRules.rarity_index(str(card.rarity)) >= 2, "首領獎勵 ≥ 稀：%s" % str(card.rarity))
	_pick_any(st)
	st = _state()
	assert_eq(str(st.phase), "PICK", "再一次一般 PICK")
	assert_eq(int(st.extra_picks), 0)
	assert_eq(str(st.min_rarity), "")
	note("boss reward rarities=%s" % ",".join(rar))

## abandon：confirm false → rogue_confirm；true → OVER、ABANDON；局中 on_leave（移除 session）→ LEAVE、profile 已寫
func sc_abandon() -> void:
	_start()
	_take(["rg_c_attr_common", "rg_c_art_basic_parry", "rg_c_wpn_w_mujian"], 1)
	assert_eq(str(_state().phase), "READY")
	assert_eq(reason("rogue_abandon", { "confirm": false }), "rogue_confirm", "confirm false")
	ok("rogue_abandon", { "confirm": true })
	var over := lastp("rogue_over")
	assert_eq(str(over.get("cause", "")), "ABANDON", "ABANDON")
	var p := RogueProfile.read(sm.root_dir)
	assert_eq(int(p.runs), 1)
	assert_eq(int(over.points_gained), RogueRules.award(0, 0, 0, bool(over.new_best), _rules()), "點數照公式")
	# 局中離開：移除 session（斷線）
	ok("rogue_open", {})
	_start()
	ws.on_peer_disconnected(1)
	ws.flush()
	p = RogueProfile.read(sm.root_dir)
	assert_eq(int(p.runs), 2, "LEAVE 也算一局")
	assert_eq(str(p.history[0].cause), "LEAVE", "cause LEAVE")
	note("abandon points=%d; leave runs=%d" % [int(over.points_gained), int(p.runs)])

## determinism：同種子兩次各打三回合（固定挑卡序列）→ 每回合的卡 id 與對手組合完全相同
func sc_determinism() -> void:
	var a := _det_run()
	_reopen()
	var b := _det_run()
	assert_eq(a.size(), 7, "記錄了三回合（%d 行）" % a.size())
	assert_eq(a, b, "兩次完全相同")
	note("trace=%s" % " | ".join(a))

func _det_run() -> Array:
	var lines: Array = []
	_start(424242)
	ws.options["wait_mode"] = false
	for rnd in 3:
		var st := _state()
		lines.append("r%d cards:%s" % [rnd + 1, ",".join((st.cards as Array).map(func(c): return str(c.id)))])
		_pick_any(st)
		_strong(150)
		ok("rogue_fight")
		var run: RogueRun = host().rogue.run_of(s())
		lines.append("r%d foes:%s" % [rnd + 1, ",".join(run.fight.get("foes", []))])
		var res := drive_battle("fight", 900.0)
		if str(res.get("result", "")) != "VICTORY":
			lines.append("lost")
			return lines
	lines.append("end round=%d" % int(_state().round))
	return lines

func _files_under(rel: String) -> Dictionary:
	var out := {}
	_walk(ProjectSettings.globalize_path(sm.root_dir.path_join(rel)), out)
	return out

func _walk(p: String, out: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(p):
		return
	for f in DirAccess.get_files_at(p):
		out[p.path_join(f)] = FileAccess.get_md5(p.path_join(f))
	for d in DirAccess.get_directories_at(p):
		_walk(p.path_join(d), out)

## mud_unaffected：MUD 世界與角色的檔案在跑完整一局試煉後完全相同；MUD 視圖沒有 rogue；--eras=1.0A,rogue 失敗；試煉中 move → rogue_off
func sc_mud_unaffected() -> void:
	if make_char("試煉旁觀") == null:
		return
	var cid := str(ch().id)
	var attrs0: Dictionary = ch().attrs.duplicate()
	host().send_passport(s(), ch())
	ws.flush()
	ws.save_now()
	_detach()
	ws.stop()
	cs.reset()
	var before := _files_under("worlds")
	before.merge(_files_under("passports"))
	assert_false(before.is_empty(), "MUD 有存檔")
	# 完整一局試煉：開局 → 打贏一場 → 輸 → stop
	assert_eq(ws.start_rogue(0), OK, "start_rogue")
	_begin()
	_attach()
	_start()
	assert_eq(reason("move", { "dir": "N" }), "rogue_off", "試煉中 move → rogue_off")
	ws.options["wait_mode"] = false
	_take(["rg_c_art_xd_daofa", "rg_c_attr_common", "rg_c_wpn_w_gangdao"], 0)
	_strong()
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_wolf"] })
	ok("rogue_fight")
	drive_battle("fight", 600.0)
	_pick_any(_state())
	_weak()
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_zhangsanfeng"] })
	ok("rogue_fight")
	drive_battle("defend", 900.0)
	assert_eq(str(_state().phase), "OVER", "試煉結束")
	ws.advance(5.0)
	_detach()
	ws.stop()
	cs.reset()
	var after := _files_under("worlds")
	after.merge(_files_under("passports"))
	assert_eq(after, before, "worlds/、passports/ 雜湊完全相同、沒有新檔")
	assert_true(FileAccess.file_exists(RogueProfile.path(sm.root_dir)), "只多了 rogue/profile.json")
	# 重開 MUD
	assert_eq(ws.start(world_name), OK, "重開 MUD")
	_begin()
	_attach()
	assert_false(GameData.enabled_eras.has("rogue"), "MUD 沒有 rogue era")
	var rg_rows := 0
	for t in GameData.tables:
		if GameData.tables[t] is Dictionary:
			for id in GameData.tables[t]:
				if str(id).begins_with("rg_"):
					rg_rows += 1
	assert_eq(rg_rows, 0, "MUD 視圖沒有 rg_ 列")
	var r := send("char_select", { "char_id": cid })
	assert_true(r.get("ok", false), "選回 MUD 角色：%s" % str(r))
	if ch() != null:
		assert_eq(ch().attrs, attrs0, "角色屬性不變")
	var d := WorldServer.decide_new_world_eras("1.0A,rogue", GameData.default_server_options())
	assert_true(str(d.error).contains("江湖試煉"), "--eras=1.0A,rogue 失敗：%s" % str(d.error))
	note("files=%d unchanged; eras error=%s" % [before.size(), str(d.error)])

func _detach() -> void:
	if cs.events_received.is_connected(_on_events):
		cs.events_received.disconnect(_on_events)
		cs.intent_result.disconnect(_on_result)
		cs.battle_opened.disconnect(_on_battle_opened)

func _attach() -> void:
	if not cs.events_received.is_connected(_on_events):
		cs.events_received.connect(_on_events)
		cs.intent_result.connect(_on_result)
		cs.battle_opened.connect(_on_battle_opened)
