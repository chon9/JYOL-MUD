extends "res://tests/unit/test_world_fixture.gd"
## ROGUE_PLAN §2、§3、§9.1（WP-RUN）整合測試：真的 WorldServer.start_rogue＋GameHost（記憶體內的試煉世界）。
## open → start → pick → fight → 勝 → 再選 → 敗 → OVER；profile 寫在測試根目錄；gate 擋 MUD intent；不能逃；沒有獎勵與死亡懲罰。

var _old_debug := false

func before_each() -> void:
	ws = tree.root.get_node("WorldServer")
	cs = tree.root.get_node("ClientState")
	sm = tree.root.get_node("SaveManager")
	tree.root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_restore_rules()
	dir = temp_dir("rogue")
	_old_root = sm.root_dir
	sm.root_dir = dir
	events.clear()
	results.clear()
	my_uid = 0
	_await_me = false
	_old_debug = ws.debug_intents
	ws.debug_intents = true
	assert_eq(ws.start_rogue(0), OK, "start_rogue")
	ws.rng.seed = 20261022
	cs.begin_local_session()
	if ws.sessions.has(1):
		ws.sessions[1].rate_limiter = TokenBucket.new(1000000.0, 1000000.0)
	ws.flush()
	cs.events_received.connect(_on_events)
	cs.intent_result.connect(_on_result)
	cs.battle_opened.connect(_on_battle_opened)

func after_each() -> void:
	super.after_each()
	ws.debug_intents = _old_debug

func _state() -> Dictionary:
	return lastp("rogue_state")

func _start(points := 0) -> void:
	ok("rogue_open", { "seed": 12345 })
	var st := _state()
	var alloc := { "str": 0 }
	var left: int = int(st.alloc_points)
	for a in ["str", "con", "agi", "guts", "cal", "wit", "luck"]:
		var room: int = 45 - int(st.roll[a])
		var put := mini(room, left)
		alloc[a] = put
		left -= put
	ok("rogue_start", { "alloc": alloc, "name": "試煉甲" })

func _strong() -> void:
	var c = ch()
	for a in ["str", "agi", "con", "guts", "cal"]:
		c.attrs[a] = 45
	c.skills.set_level("basic_blade", 80, tables())
	c.skills.set_level("basic_dodge", 80, tables())
	c.skills.set_level("basic_parry", 80, tables())
	c.clamp_vitals(tables(), ws.options)
	Survival.rest_full(c, tables(), ws.options)

func test_world_is_ephemeral_rogue() -> void:
	assert_true(bool(ws.ephemeral), "ephemeral")
	assert_true(GameData.enabled_eras.has("rogue"))
	assert_eq(str(ws.world_info().get("mode", "")), "ROGUE")
	assert_true(host().rogue != null and host().rogue.enabled(), "RogueSystem enabled")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(sm.world_dir("_rogue"))), "不寫世界檔")

func test_open_start_alloc_errors() -> void:
	ok("rogue_open", { "seed": 12345 })
	var st := _state()
	assert_eq(str(st.phase), "ALLOC")
	assert_eq(int(st.seed), 12345)
	for a in Character.ATTR_IDS:
		assert_true(int(st.roll[a]) >= 13 and int(st.roll[a]) <= 25, "擲骰 13–25")
	assert_eq(int(st.alloc_points), 5, "5 點＋永久 0")
	assert_eq(reason("rogue_start", { "alloc": { "str": 4 } }), "rogue_bad_alloc", "少 1 點")
	assert_eq(reason("rogue_start", { "alloc": { "str": 6 } }), "rogue_bad_alloc", "多 1 點")
	# 同一個種子＝同一組擲骰（重擲＝新 run，不算一局）
	var roll1: Dictionary = st.roll
	ok("rogue_open", { "seed": 12345 })
	assert_eq(_state().roll, roll1, "同種子同擲骰")
	# 單項上限 45：先給 40 點永久點數
	ok("rogue_debug", { "op": "points", "n": 40 })
	ok("rogue_open", { "seed": 12345 })
	assert_eq(int(_state().alloc_points), 45)
	assert_eq(reason("rogue_start", { "alloc": { "str": 45 } }), "rogue_attr_cap")
	ok("rogue_debug", { "op": "points", "n": 0 })

func test_start_pick_gate_and_card_effects() -> void:
	_start()
	var st := _state()
	assert_eq(str(st.phase), "PICK")
	assert_eq((st.cards as Array).size(), 3, "三張卡")
	var kinds := {}
	for c in st.cards:
		kinds[c.kind] = true
	assert_true(kinds.size() >= 2, "至少兩種種類")
	var c = ch()
	assert_eq(str(c.name), "試煉甲")
	assert_eq(s().room_id(), "rg_hall")
	assert_eq(c.inventory.items.size(), 2, "只有布衣與木刀")
	assert_eq(c.inventory.count("a_bupao") + c.inventory.count("w_mudao"), 2)
	assert_true(c.skills.special_arts(tables()).is_empty(), "沒有武功")
	assert_eq(int(c.money), 0)
	# gate：MUD intent 一律 rogue_off
	assert_eq(reason("move", { "dir": "N" }), "rogue_off")
	assert_eq(reason("meditate"), "rogue_off")
	assert_eq(reason("rogue_fight"), "rogue_phase", "PICK 不能出戰")
	# 固定三張卡
	ok("rogue_debug", { "op": "cards", "ids": ["rg_c_art_hs_jianfa", "rg_c_attr_fine", "rg_c_ally_zhouzhiruo"] })
	assert_eq((_state().cards as Array).map(func(x): return str(x.id)), ["rg_c_art_hs_jianfa", "rg_c_attr_fine", "rg_c_ally_zhouzhiruo"])
	assert_eq(reason("rogue_pick", { "idx": 1 }), "rogue_bad_alloc", "ATTR 不給 alloc")
	clear_events()
	ok("rogue_pick", { "idx": 0 })
	assert_eq(c.skills.level("hs_jianfa"), 25)
	assert_true(c.skills.level("basic_sword") >= 25)
	assert_eq(str(_state().phase), "READY")
	assert_false(evs("rogue_card_taken").is_empty(), "rogue_card_taken")
	assert_eq(reason("rogue_pick", { "idx": 0 }), "rogue_phase", "READY 不能再選")
	# 換裝在 READY 可以
	ok("unequip", { "slot": "WEAPON" })

func test_win_then_lose_writes_profile() -> void:
	_start()
	ws.options["wait_mode"] = false
	ok("rogue_debug", { "op": "cards", "ids": ["rg_c_art_xd_daofa", "rg_c_attr_common", "rg_c_wpn_w_gangdao"] })
	ok("rogue_pick", { "idx": 0 })
	_strong()
	var xp0 := int(ch().combat_xp)
	var lp0 := int(ch().learn_points)
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_wolf"] })
	clear_events()
	var r := ok("rogue_fight")
	assert_true(s().battle_id != 0, "開戰")
	var entry: Dictionary = host().battles.active.get(s().battle_id, {})
	assert_eq(str(entry.get("kind", "")), "ROGUE")
	var b = entry["battle"]
	assert_true(bool(b.opts.get("no_flee", false)), "不能逃")
	assert_true(bool(b.opts.get("end_on_players_down", false)))
	assert_eq(reason("battle_cmd", { "battle_id": s().battle_id, "cmd": "FLEE" }) in ["no_flee", "not_ready", "not_on_escape"], true)
	var res := drive_battle("fight", 600.0)
	assert_eq(str(res.get("result", "")), "VICTORY")
	assert_eq(str(res.get("kind", "")), "ROGUE")
	assert_true(res.get("rogue") is Dictionary and bool(res.rogue.won), "close.rogue.won")
	assert_false(bool(res.rogue.over))
	assert_false(evs("rogue_round_won").is_empty(), "rogue_round_won")
	var st := _state()
	assert_eq(int(st.round), 2)
	assert_eq(int(st.wins), 1)
	assert_eq(str(st.phase), "PICK")
	assert_eq(int(ch().combat_xp), xp0, "沒有實戰")
	assert_eq(int(ch().learn_points), lp0, "沒有學點")
	assert_eq(int(ch().money), 0, "沒有錢")
	assert_true((ws.world.get("corpses", []) as Array).is_empty(), "沒有屍體")
	# 回合回復：35% 規則
	var d: Dictionary = ch().derived(tables(), ws.options)
	var won: Dictionary = lastp("rogue_round_won")
	assert_true(int(won.qi) <= int(floor(int(d.qi_max) * 0.35)), "氣回復 ≤ 35%")
	# 輸：固定極強對手；防守挨打
	ok("rogue_debug", { "op": "cards", "ids": ["rg_c_attr_common", "rg_c_art_basic_parry", "rg_c_wpn_w_mujian"] })
	ok("rogue_pick", { "idx": 1 })
	var c = ch()
	for a in ["str", "agi", "con", "guts", "cal"]:
		c.attrs[a] = 13
	c.skills = SkillBook.new()
	c.vitals["qi"] = 20
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_zhangsanfeng"] })
	clear_events()
	ok("rogue_fight")
	var dead0 := int(c.dead_count)
	var res2 := drive_battle("defend", 900.0)
	assert_eq(str(res2.get("result", "")), "DEFEAT")
	assert_true(bool(res2.rogue.over), "close.rogue.over")
	assert_eq(int(c.dead_count), dead0, "不呼叫 handle_death")
	var over := lastp("rogue_over")
	for k in ["run_id", "seed", "cause", "rounds", "wins", "foes_beaten", "bosses_beaten", "best_card", "allies_recruited",
			"points_gained", "points_total", "new_best"]:
		assert_true(over.has(k), "summary 有 %s" % k)
	assert_eq(str(over.cause), "DEATH")
	assert_eq(int(over.wins), 1)
	assert_eq(int(over.rounds), 2)
	var p := RogueProfile.read(sm.root_dir)
	assert_eq(int(p.runs), 1, "profile.runs")
	assert_eq(int(p.points_total), RogueRules.award(1, 0, 0, true, RogueRules.rules(tables())), "點數 = award")
	assert_eq(int(p.points_total), int(over.points_gained))
	assert_eq(int(p.history[0].wins), 1)
	assert_true(FileAccess.file_exists(RogueProfile.path(sm.root_dir)), "profile 寫在測試根目錄")
	assert_eq(str(_state().phase), "OVER")
	assert_eq(reason("rogue_fight"), "rogue_phase", "OVER 之後不能出戰")
	# 再戰一場：alloc_points 加上新的點數
	ok("rogue_open", {})
	assert_eq(int(_state().alloc_points), 5 + int(p.points_total))

func test_abandon_and_leave() -> void:
	_start()
	ok("rogue_debug", { "op": "cards", "ids": ["rg_c_attr_common", "rg_c_art_basic_parry", "rg_c_wpn_w_mujian"] })
	ok("rogue_pick", { "idx": 1 })
	assert_eq(reason("rogue_abandon", { "confirm": false }), "rogue_confirm")
	ok("rogue_abandon", { "confirm": true })
	assert_eq(str(lastp("rogue_over").cause), "ABANDON")
	assert_eq(int(RogueProfile.read(sm.root_dir).runs), 1)
	# 局中離開（換角／關遊戲）→ LEAVE、profile 已寫
	ok("rogue_open", {})
	_start()
	host().leave_character(s(), true)
	var p := RogueProfile.read(sm.root_dir)
	assert_eq(int(p.runs), 2)
	assert_eq(str(p.history[0].cause), "LEAVE")

func test_boss_round_extra_pick() -> void:
	_start()
	ws.options["wait_mode"] = false
	ok("rogue_debug", { "op": "cards", "ids": ["rg_c_art_xd_daofa", "rg_c_attr_common", "rg_c_wpn_w_gangdao"] })
	ok("rogue_pick", { "idx": 0 })
	ok("rogue_debug", { "op": "round", "n": 5 })
	assert_true(bool(_state().next_round_is_boss), "next_round_is_boss")
	_strong()
	var c = ch()
	c.skills.set_level("xd_daofa", 140, tables())
	c.skills.set_level("basic_blade", 140, tables())
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_wolf"] })   # 固定弱對手（非首領列）：只驗首領回合的狀態流程
	ok("rogue_fight")
	drive_battle("fight", 600.0)
	var st := _state()
	assert_eq(int(st.round), 6)
	assert_eq(int(st.extra_picks), 0, "不是首領列 → 沒有首領獎勵")
	# 真的首領：周芷若（第 10 回合打）
	ok("rogue_debug", { "op": "cards", "ids": ["rg_c_attr_common", "rg_c_art_basic_parry", "rg_c_wpn_w_mujian"] })
	ok("rogue_pick", { "idx": 1 })
	ok("rogue_debug", { "op": "round", "n": 10 })
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_zhouzhiruo"] })
	clear_events()
	ok("rogue_fight")
	assert_false(evs("rogue_boss").is_empty(), "rogue_boss 事件")
	var res := drive_battle("fight", 900.0)
	assert_eq(str(res.get("result", "")), "VICTORY", "很強的角色打得贏周芷若")
	st = _state()
	assert_eq(int(st.bosses_beaten), 1)
	assert_eq(int(st.extra_picks), 1, "首領獎勵 → 多一次選卡")
	assert_eq(str(st.min_rarity), "RARE")
	for card in st.cards:
		assert_true(RogueRules.rarity_index(str(card.rarity)) >= 2, "三張都 ≥ 稀")
	var idx := 0
	for card in st.cards:
		if str(card.kind) != "ATTR":
			idx = int(card.idx)
			break
	ok("rogue_pick", { "idx": idx })
	st = _state()
	assert_eq(str(st.phase), "PICK", "選完再一次一般 PICK")
	assert_eq(int(st.extra_picks), 0)
	assert_eq(str(st.min_rarity), "")

# ---------------------------------------------------------------- 第二輪審查

## 開戰失敗（start_ex 回 0）要完全還原：首領不記成見過、run.fight 的 pin 留著、同一回合重試＝同一場
class FailBattles extends BattleSystem:
	func start_ex(_s: Session, _ids: Array, _kind: String, _opts: Dictionary) -> int:
		return 0

func test_fight_failure_rolls_back() -> void:
	_start()
	ok("rogue_debug", { "op": "cards", "ids": ["rg_c_art_xd_daofa", "rg_c_attr_common", "rg_c_wpn_w_gangdao"] })
	ok("rogue_pick", { "idx": 0 })
	ok("rogue_debug", { "op": "round", "n": 5 })   # 首領回合
	var run: RogueRun = host().rogue.run_of(s())
	assert_true((run.fight.get("pin", {}) as Dictionary).size() > 0, "選完卡有 pin")
	var seen0 := run.bosses_seen.duplicate()
	var fight0 := run.fight.duplicate(true)
	var real: BattleSystem = host().battles
	host().battles = FailBattles.new(host())
	var why := reason("rogue_fight")
	host().battles = real
	assert_eq(why, "rogue_phase")
	assert_eq(str(_state().phase), "READY", "回到 READY")
	assert_eq(run.bosses_seen, seen0, "首領沒有記成見過")
	assert_eq(run.fight, fight0, "run.fight（含 pin）還原")
	# 重試：同一位首領
	ws.options["wait_mode"] = false
	ok("rogue_fight")
	assert_true(s().battle_id != 0, "重試開得了戰")
	assert_eq(run.bosses_seen.size(), seen0.size() + 1, "這次才記成見過")

## 真的斷線路徑：戰鬥中 WorldServer.on_peer_disconnected → detach_for（自動防守打完）→ on_battle_finished（silent）→ LEAVE
func test_disconnect_in_battle_settles_once_as_leave() -> void:
	_start()
	ws.options["wait_mode"] = false
	ok("rogue_debug", { "op": "cards", "ids": ["rg_c_art_xd_daofa", "rg_c_attr_common", "rg_c_wpn_w_gangdao"] })
	ok("rogue_pick", { "idx": 0 })
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_wolf"] })
	ok("rogue_fight")
	var bid := s().battle_id
	assert_true(bid != 0)
	var runs0 := int(RogueProfile.read(sm.root_dir).runs)
	var peer := s().peer_id
	ws.on_peer_disconnected(peer)
	var p := RogueProfile.read(sm.root_dir)
	assert_eq(int(p.runs), runs0 + 1, "只結算一次")
	assert_eq(str(p.history[0].cause), "LEAVE", "斷線＝LEAVE")
	assert_true((p.in_progress as Dictionary).is_empty())
	assert_true(host().rogue.runs.is_empty(), "runs 清空")
	assert_true(host().rogue.profiles.is_empty(), "profiles 清空")
	assert_false(host().battles.active.has(bid), "沒有留下戰鬥")

## 當機、強制關閉：打贏的場次寫進 profile.in_progress；下一次 rogue_open 以 LEAVE 結算（點數不歸零）
func test_crash_mid_run_settles_on_next_open() -> void:
	_start()
	ws.options["wait_mode"] = false
	ok("rogue_debug", { "op": "cards", "ids": ["rg_c_art_xd_daofa", "rg_c_attr_common", "rg_c_wpn_w_gangdao"] })
	ok("rogue_pick", { "idx": 0 })
	_strong()
	ok("rogue_debug", { "op": "foes", "ids": ["rg_f_wolf"] })
	ok("rogue_fight")
	assert_eq(str(drive_battle("fight", 600.0).get("result", "")), "VICTORY")
	var p := RogueProfile.read(sm.root_dir)
	assert_eq(int(p.runs), 0, "還沒結算")
	assert_eq(int(p.in_progress.wins), 1, "打贏一場就寫進 in_progress")
	# 模擬當機：主機的記憶體沒了（不經 on_leave）
	host().rogue.runs.clear()
	host().rogue.profiles.clear()
	ok("rogue_open", { "seed": 999 })
	var p2 := RogueProfile.read(sm.root_dir)
	assert_eq(int(p2.runs), 1, "上一局以 LEAVE 結算")
	assert_eq(str(p2.history[0].cause), "LEAVE")
	assert_eq(int(p2.history[0].wins), 1)
	assert_eq(int(p2.points_total), RogueRules.award(1, 0, 0, true, RogueRules.rules(tables())))
	assert_true((p2.in_progress as Dictionary).is_empty())
	assert_eq(int(_state().alloc_points), 5 + int(p2.points_total), "結算的點數這一局就能用")
	# 正常結束不會重複結算
	ok("rogue_open", { "seed": 999 })
	assert_eq(int(RogueProfile.read(sm.root_dir).runs), 1)
