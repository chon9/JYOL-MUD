class_name RogueSystem
extends RefCounted
## 江湖試煉的主機端（ROGUE_PLAN §2、§3）【設計提案・非原作】。host.rogue。
## 只在試煉世界（WorldServer.start_rogue：記憶體內、ephemeral、enabled_eras 含 rogue）生效；MUD 世界也會載入，
## 但 enabled() 為 false：gate 一律放行、所有 rogue intent 回 rogue_off（U10）。
## 一局 = RogueRun（core/rogue/）；角色永遠不存檔（GameHost.save_char 守衛）；永久點數只寫 <資料根目錄>/rogue/profile.json。

const ALLOWED_INTENTS := ["ping", "chat", "battle_cmd", "equip", "unequip", "char_list", "passport_request"]
const ALLY_SCRIPT := "res://core/rogue/rogue_ally.gd"
const START_ARMOR := "a_bupao"
const START_WEAPON := "w_mudao"
const ROOM := "rg_hall"
const REGION := "rg_trial"
const DEFAULT_NAME := "試煉者"
const VITAL_KEYS := ["qi", "jing", "shen", "neili"]

## GameHost 持有 RogueSystem；這裡只留弱參照，GameHost.dispose() 不必另外切斷循環引用
var _host_ref: WeakRef = null
var host: GameHost:
	get:
		return _host_ref.get_ref() as GameHost if _host_ref != null else null
	set(v):
		_host_ref = weakref(v) if v != null else null

## peer_id -> RogueRun
var runs: Dictionary = {}
## peer_id -> 試煉者檔案（rogue_open 時讀一次；點數不在局中改變）
var profiles: Dictionary = {}
var _world_seed_used := false

func _init(h: GameHost) -> void:
	host = h

func enabled() -> bool:
	var h := host
	if h == null or h.ws == null:
		return false
	return GameData.enabled_eras.has(DataSchema.ROGUE_ERA) and h.ws.get("ephemeral") == true

## §2.4：試煉世界只放行少數 intent；MUD 世界一律 ""
func gate(_s: Session, kind: String) -> String:
	if not enabled():
		return ""
	if kind in ALLOWED_INTENTS or kind.begins_with("rogue_"):
		return ""
	return Protocol.R_ROGUE_OFF

func rules() -> Dictionary:
	return RogueRules.rules(host.tables)

func run_of(s: Session) -> RogueRun:
	if s == null:
		return null
	return runs.get(s.peer_id)

func profile_path() -> String:
	return RogueProfile.path(SaveManager.root_dir)

func profile_of(s: Session) -> Dictionary:
	if s != null and profiles.has(s.peer_id):
		return profiles[s.peer_id]
	return RogueProfile.settle_pending(RogueProfile.read(SaveManager.root_dir), rules())["profile"]

# ---------------------------------------------------------------- intent

## rogue_open：建新的一局（ALLOC）；ALLOC 中再送＝重擲（新 run，不算一局）；OVER 之後＝再戰一場
func open(s: Session, seed: int) -> Dictionary:
	if not s.is_local:
		return GameHost.fail(Protocol.R_ROGUE_SOLO_ONLY)   # O2：v1 只接受本機 peer
	var old := run_of(s)
	if old != null and not (old.phase in ["ALLOC", "OVER"]):
		return GameHost.fail(Protocol.R_ROGUE_PHASE)
	if s.battle_id != 0:
		return GameHost.fail(Protocol.R_ROGUE_PHASE)
	if s.character != null:
		host.leave_character(s, true)   # 舊角色離開房間（save_char 被 ephemeral 守衛，不寫檔）
	var r := rules()
	var p := _read_settled()
	profiles[s.peer_id] = p
	var run := RogueRun.new()
	# 沒指定種子：試煉世界開服時給的種子（NetworkManager.start_rogue(seed)／world.rogue_seed）只用在第一局，之後隨機
	var ws_seed := int(host.ws.world.get("rogue_seed", 0))
	if seed <= 0 and ws_seed > 0 and not _world_seed_used:
		seed = ws_seed
		_world_seed_used = true
	run.seed = seed if seed > 0 else (host.rng.randi() & 0x7FFFFFFF)
	if run.seed == 0:
		run.seed = 1
	run.run_id = host.new_id("rr")
	run.phase = "ALLOC"
	run.roll = CharacterFactory.roll(run.rng_for("roll"))
	run.alloc_points = CharacterFactory.FREE_POINTS + int(p.get("points_total", 0))
	runs[s.peer_id] = run
	_send_state(s)
	return GameHost.ok({ "run_id": run.run_id })

## rogue_start：分配點數、建角色、進 rg_hall → PICK
func start(s: Session, a: Dictionary) -> Dictionary:
	var run := run_of(s)
	if run == null or run.phase != "ALLOC":
		return GameHost.fail(Protocol.R_ROGUE_PHASE)
	var r := rules()
	var alloc: Dictionary = (a.get("alloc", {}) as Dictionary).duplicate()
	var why := RogueRun.check_alloc(run.roll, alloc, run.alloc_points, int(r.get("attr_cap", 45)))
	if why != "":
		return _fail_cap(why, r)
	var nm := Protocol.clean_text(str(a.get("name", "")), CharacterFactory.NAME_MAX)
	if nm == "":
		nm = DEFAULT_NAME
	if CharacterFactory.validate_name(nm) != "":
		return GameHost.fail("bad_name")
	var gender := str(a.get("gender", "M"))
	if not (gender in Protocol.GENDERS):
		gender = "M"
	var ch := CharacterFactory.create({ "id": host.new_id("rg"), "identity": s.identity, "name": nm, "gender": gender,
		"birth_month": 1, "birth_city": "xixia", "alloc": alloc, "look": int(a.get("look", 0)) },
		run.roll, host.tables, host.options, run.rng_for("create"), host.now_s())
	for k in Character.ATTR_IDS:
		ch.attrs[k] = int(run.roll.get(k, 0)) + int(alloc.get(k, 0))
	ch.inventory = Inventory.new()
	for id in [START_ARMOR, START_WEAPON]:
		var add: Dictionary = ch.inventory.add(id, 1, host.tables, host.now_s(), -1, host.make_uid_callable())
		if bool(add.get("ok", false)):
			ch.inventory.equip(str(add["uid"]), host.tables)
	ch.money = 0
	ch.learn_points = 0
	ch.location = { "region": REGION, "room": ROOM }
	ch.respawn = { "region": REGION, "room": ROOM }
	ch.ext["rogue"] = { "run_id": run.run_id }
	Survival.rest_full(ch, host.tables, host.options)
	ch.vitals["neili"] = 0
	ch.vitals["food"] = Character.FOOD_MAX
	ch.vitals["water"] = Character.WATER_MAX
	host.enter_character(s, ch)
	run.members = [str(ch.id)]
	_pin(run, ch)
	_enter_pick(s, run, "")
	return GameHost.ok()

## rogue_pick：選一張卡（ATTR 帶 alloc）；首領獎勵還有一次 → 再抽一般的三張，否則 READY
func pick(s: Session, idx: int, alloc: Dictionary) -> Dictionary:
	var run := run_of(s)
	if run == null or run.phase != "PICK" or s.character == null:
		return GameHost.fail(Protocol.R_ROGUE_PHASE)
	var card: Dictionary = {}
	for c in run.cards:
		if c is Dictionary and int(c.get("idx", -1)) == idx:
			card = c
	if card.is_empty():
		return GameHost.fail(Protocol.R_ROGUE_BAD_CARD)
	var r := rules()
	var ch = s.character
	var why := run.apply_card(ch, card, alloc.duplicate(), host.tables, host.options, r)
	if why != "":
		return _fail_cap(why, r)
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_ROGUE_CARD_TAKEN,
		{ "title": str(card.get("title", "")), "rarity_name": RogueRules.rarity_name(str(card.get("rarity", ""))) })
	if str(card.get("kind", "")) == "ALLY":
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_ROGUE_ALLY_JOINED, { "name": str(card.get("title", "")) })
	s.sheet_dirty = true
	if run.extra_picks > 0:
		run.extra_picks -= 1
		_enter_pick(s, run, "")
	else:
		run.cards = []
		run.min_rarity = ""
		run.phase = "READY"
		_send_state(s)
	return GameHost.ok()

## rogue_fight：組對手與隊友 → BattleSystem.start_ex(kind ROGUE)
func fight(s: Session) -> Dictionary:
	var run := run_of(s)
	if run == null or run.phase != "READY" or s.character == null or s.battle_id != 0:
		return GameHost.fail(Protocol.R_ROGUE_PHASE)
	var ch = s.character
	var r := rules()
	# 開戰失敗要能完全還原（審查：首領記成見過、run.fight 的 pin 被換掉 → 同種子重試不再是同一場、不回復規則被繞過）
	var prev_fight: Dictionary = run.fight.duplicate(true)
	var prev_seen: Array = run.bosses_seen.duplicate()
	var prev_debug_foes: Array = run.debug_foes.duplicate()
	_unpin(run, ch)   # 試煉沒有自然回復：等待期間回的氣血不算（O13 之外的回復；冪等，失敗重試再做一次也一樣）
	var me: Dictionary = ch.to_combatant(host.tables, host.options, 0, s.peer_id)
	var prep := RogueFoes.prepare_fight(run, me, host.tables, r)
	var ally_specs: Array = prep["ally_specs"]
	var my_power := float(prep["my_power"])
	var tgt := float(prep["target"])
	var boss := RogueRules.is_boss_round(run.round, r)
	var gen: Dictionary = prep["gen"]
	var foe_specs: Array = gen.get("specs", [])
	if foe_specs.is_empty():
		run.debug_foes = prev_debug_foes
		return GameHost.fail(Protocol.R_ROGUE_PHASE)
	var boss_id := str(gen.get("boss_id", ""))
	if boss_id != "" and not run.bosses_seen.has(boss_id):
		run.bosses_seen.append(boss_id)
	run.fight = { "boss": boss_id != "", "boss_round": boss, "boss_id": boss_id, "boss_name": str(gen.get("boss_name", "")),
		"foes": (gen.get("foes", []) as Array).duplicate(), "power": float(gen.get("power", 0.0)), "target": tgt,
		"my_power": my_power }
	var opts := { "foe_specs": foe_specs, "ally_specs": ally_specs, "seed": battle_seed(run), "no_flee": true,
		"pull_party": false, "party_only": true }
	if boss_id != "":
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_ROGUE_BOSS, { "name": str(gen.get("boss_name", "")) })
	run.phase = "BATTLE"
	run.last_result = {}
	_send_state(s)
	var bid: int = host.battles.start_ex(s, [], BattleSystem.KIND_ROGUE, opts)
	if bid == 0:
		run.phase = "READY"
		run.fight = prev_fight
		run.bosses_seen = prev_seen
		run.debug_foes = prev_debug_foes
		_send_state(s)
		return GameHost.fail(Protocol.R_ROGUE_PHASE)
	return GameHost.ok({ "battle_id": bid })

## §3.7.5：戰鬥種子 = hash([run.seed, "battle", round])
static func battle_seed(run: RogueRun) -> int:
	return run.battle_seed()

## rogue_abandon：兩場之間才能放棄（O7）；confirm false → rogue_confirm
func abandon(s: Session, confirm: bool) -> Dictionary:
	var run := run_of(s)
	if run == null or not (run.phase in ["PICK", "READY"]):
		return GameHost.fail(Protocol.R_ROGUE_PHASE)
	if not confirm:
		return GameHost.fail(Protocol.R_ROGUE_CONFIRM)
	_end_run(s, run, "ABANDON")
	return GameHost.ok()

## §3.11：rogue_debug { op, ids?, n? }（只在 --debug-intents 註冊）
func debug(s: Session, a: Dictionary) -> Dictionary:
	if not host.debug_enabled:
		return GameHost.fail("unknown_intent")
	var op := str(a.get("op", ""))
	var ids: Array = a.get("ids", []) if a.get("ids") is Array else []
	var n := int(a.get("n", 0))
	var run := run_of(s)
	match op:
		"points":
			var r := rules()
			var p := RogueProfile.normalize(profile_of(s), int(r.get("points_cap", 60)))
			p["points_total"] = clampi(n, 0, int(r.get("points_cap", 60)))
			_write_profile(p)
			profiles[s.peer_id] = p
			if run != null and run.phase == "ALLOC":
				run.alloc_points = CharacterFactory.FREE_POINTS + int(p["points_total"])
			_send_state(s)
			return GameHost.ok()
		"cards":
			if run == null:
				return GameHost.fail(Protocol.R_ROGUE_PHASE)
			for id in ids:
				if not host.tables.get("rogue_cards", {}).has(str(id)):
					return GameHost.fail(Protocol.R_ROGUE_BAD_CARD)
			run.debug_cards = ids.duplicate()
			if run.phase == "PICK" and s.character != null:
				run.cards = RogueDraw.draw(run, s.character, host.tables, run.rng_for("draw"), run.min_rarity)
				RogueDraw.annotate_power(run.cards, run, s.character, host.tables, rules(), host.options)
				_send_state(s)
			return GameHost.ok()
		"foes":
			if run == null:
				return GameHost.fail(Protocol.R_ROGUE_PHASE)
			for id in ids:
				if not host.tables.get("rogue_foes", {}).has(str(id)):
					return GameHost.fail("bad_value:ids")
			run.debug_foes = ids.duplicate()
			return GameHost.ok()
		"round":
			if run == null or run.phase == "BATTLE":
				return GameHost.fail(Protocol.R_ROGUE_PHASE)
			run.round = maxi(1, n)
			_send_state(s)
			return GameHost.ok()
	return GameHost.fail("bad_value:op")

# ---------------------------------------------------------------- 戰鬥結算（BattleSystem 的 ROGUE 鉤子）

## BattleSystem._finish：逐一結算玩家之前。隊友的傷勢與倒下、勝場、擊敗數；判負 → 結算這一局（寫 profile）
func on_battle_finished(entry: Dictionary, out: Dictionary) -> void:
	var b: Battle = entry.get("battle")
	if b == null:
		return
	for peer in (entry.get("chars", {}) as Dictionary).keys():
		var run: RogueRun = runs.get(int(peer))
		if run == null or run.phase != "BATTLE":
			continue
		var s: Session = host.session_for_peer(int(peer))
		var silent := (entry.get("silent_peers", []) as Array).has(int(peer))
		var result := BattleSystem.relative_result(out, 0)
		var units: Dictionary = out.get("units", {})
		# 隊友：倒下 → 這局沒了；活著 → 記住剩下的氣（§4.5）
		var fallen: Array = []
		for u in b.units:
			var slot := str(u.spec.get("rg_ally", ""))
			if slot == "":
				continue
			var uo: Dictionary = units.get(u.uid, units.get(str(u.uid), {}))
			if uo.is_empty():
				uo = { "died": u.is_dead(), "qi": u.qi, "qi_max": u.qi_max() }
			if not uo.has("qi_max"):
				uo["qi_max"] = u.qi_max()
			for i in run.allies.size():
				var a: Dictionary = run.allies[i]
				if str(a.get("slot", "")) != slot:
					continue
				var na := ally_outcome(a, uo)
				if bool(a.get("alive", false)) and not bool(na.get("alive", false)):
					fallen.append(str(a.get("name", "")))
				run.allies[i] = na
		var killed := 0
		for u in b.units:
			if u.side == 1 and u.is_dead():
				killed += 1
		var boss := bool(run.fight.get("boss", false))
		var won := result == "VICTORY" and not silent
		var standing := 0
		for a in run.allies:
			if bool(a.get("alive", false)):
				standing += 1
		run.last_result = { "round": run.round, "won": won, "boss": boss, "allies_fallen": fallen, "over": not won,
			"allies_standing": standing }
		if s != null and not silent:
			for nm in fallen:
				host.tell(s, Protocol.CH_SYSTEM, Protocol.E_ROGUE_ALLY_FALLEN, { "name": nm })
		if won:
			run.on_won(killed, boss, str(run.fight.get("boss_id", "")) if boss else "")
			run.phase = "PICK"   # settle_player 補回復、抽卡、送狀態
			_save_progress(int(peer), run)
		else:
			var cause := "DEATH"
			if silent:
				cause = "LEAVE"
			elif result == "ABORTED":
				cause = "TIMEOUT"
			_end_run(s if not silent else null, run, cause)

## BattleSystem._settle_player（ROGUE）：close.rogue；勝 → 回復、抽下一回合的卡；回 true＝已處理（不呼叫 handle_death）
func settle_player(s: Session, ch, u: Dictionary, per: String, close: Dictionary) -> bool:
	var run: RogueRun = null
	if s != null:
		run = run_of(s)
	if run == null and ch != null:
		for peer in runs:
			if (runs[peer] as RogueRun).members.has(str(ch.id)):
				run = runs[peer]
	if run == null:
		return true
	close["rogue"] = run.last_result.duplicate(true) if not run.last_result.is_empty() else \
		{ "round": run.round, "won": false, "boss": false, "allies_fallen": [], "over": run.phase == "OVER" }
	if run.phase == "PICK" and bool(run.last_result.get("won", false)) and ch != null:
		var r := rules()
		var boss := bool(run.last_result.get("boss", false))
		var got := RogueRules.restore(ch, host.tables, host.options, boss, r)
		var pct := float(r.get("restore_pct", 0.35))
		for i in run.allies.size():
			var a: Dictionary = run.allies[i]
			if bool(a.get("alive", false)):
				a["qi_pct"] = 1.0 if boss else minf(1.0, float(a.get("qi_pct", 1.0)) + pct)
		_pin(run, ch)
		if s != null:
			host.tell(s, Protocol.CH_SYSTEM, Protocol.E_ROGUE_ROUND_WON, { "round": int(run.last_result.get("round", run.round - 1)),
				"qi": int(got.get("qi", 0)), "jing": int(got.get("jing", 0)), "neili": int(got.get("neili", 0)) })
			s.sheet_dirty = true
			_enter_pick(s, run, "RARE" if run.extra_picks > 0 else "")
		else:
			run.cards = RogueDraw.draw(run, ch, host.tables, _draw_rng(run), "RARE" if run.extra_picks > 0 else "")
	return true

## 局中離開（離線、關遊戲、換到別的模式、主機關閉）＝以 LEAVE 結算並寫 profile（§3.9.4）；ALLOC 中只丟掉 run
func on_leave(s: Session) -> void:
	var run := run_of(s)
	if run == null:
		return
	if run.phase in ["PICK", "READY", "BATTLE"]:
		_end_run(s, run, "LEAVE")
	if run.phase in ["ALLOC", "OVER"]:
		runs.erase(s.peer_id)
		profiles.erase(s.peer_id)

# ---------------------------------------------------------------- 隊友（WP-ALLY 的 RogueAlly；還沒有時用最小的後備）

func _ally_script() -> Script:
	if ResourceLoader.exists(ALLY_SCRIPT):
		var sc := load(ALLY_SCRIPT) as Script
		if sc != null and sc.can_instantiate():
			return sc
	return null

func ally_spec(ally: Dictionary, my_unit_power: float) -> Dictionary:
	return RogueFoes.ally_spec(ally, my_unit_power, host.tables)

func ally_outcome(ally: Dictionary, unit_out: Dictionary) -> Dictionary:
	var sc := _ally_script()
	if sc != null and sc.has_method("apply_outcome"):
		var r: Variant = sc.call("apply_outcome", ally, unit_out)
		if r is Dictionary:
			return r
	var na := ally.duplicate(true)
	if bool(unit_out.get("died", false)):
		na["alive"] = false
		na["qi_pct"] = 0.0
	else:
		na["qi_pct"] = clampf(float(unit_out.get("qi", 0)) / maxf(1.0, float(unit_out.get("qi_max", 1))), 0.0, 1.0)
	return na

# ---------------------------------------------------------------- 內部

## 失敗結果；rogue_attr_cap 附上 cap（客戶端的「單項屬性最多 {n}」讀這個，不寫死 45）
static func _fail_cap(why: String, r: Dictionary) -> Dictionary:
	var out := GameHost.fail(why)
	if why == Protocol.R_ROGUE_ATTR_CAP:
		out["cap"] = int(r.get("attr_cap", 45))
	return out

func _draw_rng(run: RogueRun) -> RandomNumberGenerator:
	var g := run.rng_for("draw")
	run.draws += 1
	return g

func _enter_pick(s: Session, run: RogueRun, min_rarity: String) -> void:
	run.phase = "PICK"
	run.min_rarity = min_rarity
	run.cards = RogueDraw.draw(run, s.character, host.tables, _draw_rng(run), min_rarity)
	RogueDraw.annotate_power(run.cards, run, s.character, host.tables, rules(), host.options)
	_send_state(s)

## 試煉沒有自然回復：記住目前的氣血精神內力；出戰前把超過的部分拿掉
func _pin(run: RogueRun, ch) -> void:
	var pin := {}
	for k in VITAL_KEYS:
		pin[k] = int(ch.vitals.get(k, 0))
	run.fight["pin"] = pin

func _unpin(run: RogueRun, ch) -> void:
	var pin: Variant = run.fight.get("pin", {})
	if not (pin is Dictionary):
		return
	for k in VITAL_KEYS:
		if (pin as Dictionary).has(k):
			ch.vitals[k] = mini(int(ch.vitals.get(k, 0)), int(pin[k]))
	ch.clamp_vitals(host.tables, host.options)

## 讀 profile；有上次沒結算的一局（當機、強制關閉）→ 以 LEAVE 結算並寫回（審查：點數不能因當機歸零）
func _read_settled() -> Dictionary:
	var res := RogueProfile.settle_pending(RogueProfile.read(SaveManager.root_dir), rules())
	if bool(res.get("settled", false)):
		_write_profile(res["profile"])
	return res["profile"]

## 每打贏一場：把進行中的這一局寫進 profile.in_progress（不動點數；下一次 rogue_open 才結算）
func _save_progress(peer: int, run: RogueRun) -> void:
	var p: Dictionary = profiles.get(peer, {})
	if p.is_empty():
		p = _read_settled()
	var np := RogueProfile.normalize(p, int(rules().get("points_cap", 60)))
	np["in_progress"] = RogueProfile.progress_of(run.summary(), int(Time.get_unix_time_from_system()))
	_write_profile(np)
	profiles[peer] = np

func _write_profile(p: Dictionary) -> void:
	var err: Error = SaveManager.write_json_atomic(profile_path(), p)
	if err != OK:
		push_warning("[RogueSystem] profile write failed: " + SaveManager.last_error)

## 結算一局：summary → profile（點數、戰績、名人錄、歷史）→ 寫檔 → rogue_over、rogue_points → OVER
func _end_run(s: Session, run: RogueRun, cause: String) -> void:
	if run.phase == "OVER":
		return
	run.cause = cause if cause in RogueRules.CAUSES else "DEATH"
	var r := rules()
	var summary := run.summary()
	var peer := s.peer_id if s != null else _peer_of(run)
	var p: Dictionary = profiles.get(peer, RogueProfile.read(SaveManager.root_dir))
	if s != null:
		p["identity"] = s.identity
		if s.character != null:
			p["name"] = str(s.character.name)
	var np := RogueProfile.apply_run(p, summary, r)
	_write_profile(np)
	if peer != 0:
		profiles[peer] = np
	run.phase = "OVER"
	run.cards = []
	run.extra_picks = 0
	var live: Session = s if s != null else null
	if live != null:
		host.tell(live, Protocol.CH_SYSTEM, Protocol.E_ROGUE_OVER, summary.duplicate(true), true)
		if int(summary.get("points_gained", 0)) > 0:
			host.tell(live, Protocol.CH_SYSTEM, Protocol.E_ROGUE_POINTS,
				{ "gained": int(summary["points_gained"]), "total": int(summary["points_total"]) })
		run.fight["summary"] = summary
		_send_state(live)
	else:
		run.fight["summary"] = summary

func _peer_of(run: RogueRun) -> int:
	for peer in runs:
		if runs[peer] == run:
			return int(peer)
	return 0

func _send_state(s: Session) -> void:
	if s == null:
		return
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_ROGUE_STATE, state(s), true)

## §6.3：rogue_state payload
func state(s: Session) -> Dictionary:
	var run := run_of(s)
	var r := rules()
	var p := profile_of(s)
	var out := {
		"run_id": "", "seed": 0, "phase": "", "round": 0, "wins": 0, "foes_beaten": 0, "bosses_beaten": 0,
		"next_round_is_boss": false, "extra_picks": 0, "min_rarity": "", "cards": [],
		"roll": {}, "alloc_points": 0, "attr_cap": int(r.get("attr_cap", 45)),
		"attrs": {}, "allies": [], "arts": [], "gear": {}, "weapons": [], "best_card": {},
		"profile": { "points_total": int(p.get("points_total", 0)), "cap": int(r.get("points_cap", 60)),
			"runs": int(p.get("runs", 0)), "best_wins": int(p.get("best_wins", 0)) },
		"summary": {},
	}
	if run == null:
		return out
	out["run_id"] = run.run_id
	out["seed"] = run.seed
	out["phase"] = run.phase
	out["round"] = run.round
	out["wins"] = run.wins
	out["foes_beaten"] = run.foes_beaten
	out["bosses_beaten"] = run.bosses_beaten
	out["next_round_is_boss"] = RogueRules.is_boss_round(run.round, r) and run.phase != "OVER"
	out["extra_picks"] = run.extra_picks
	out["min_rarity"] = run.min_rarity
	out["cards"] = run.cards.duplicate(true)
	out["roll"] = run.roll.duplicate()
	out["alloc_points"] = run.alloc_points
	out["best_card"] = run.best_card.duplicate()
	for a in run.allies:
		out["allies"].append({ "slot": str(a.get("slot", "")), "name": str(a.get("name", "")), "ref": str(a.get("ref", "")),
			"rarity": str(a.get("rarity", "")), "qi_pct": float(a.get("qi_pct", 0.0)), "alive": bool(a.get("alive", false)) })
	if run.phase == "OVER":
		out["summary"] = (run.fight.get("summary", {}) as Dictionary).duplicate(true)
	var ch = s.character if s != null else null
	if ch == null:
		return out
	var t := host.tables
	out["attrs"] = (ch.attrs as Dictionary).duplicate()
	var arts: Array = []
	var keys: Array = ch.skills.entries.keys()
	keys.sort()
	for k in keys:
		var lv: int = ch.skills.level(str(k))
		if lv < 1:
			continue
		var kind := SkillBook.kind_of(str(k), t)
		if kind != SkillBook.KIND_ART and kind != SkillBook.KIND_BASIC:
			continue
		arts.append({ "id": str(k), "name": SkillBook.skill_name(str(k), t), "level": lv,
			"category": SkillBook.category_of(str(k), t) if kind == SkillBook.KIND_ART else "BASIC" })
	out["arts"] = arts
	var gear := {}
	for slot in Inventory.SLOTS:
		var uid := str(ch.inventory.equipped.get(slot, ""))
		if uid == "":
			continue
		var it: Dictionary = ch.inventory.find(uid)
		var row: Dictionary = t.get("items", {}).get(str(it.get("id", "")), {})
		gear[slot] = { "uid": uid, "item_id": str(it.get("id", "")), "name": str(row.get("name", it.get("id", ""))),
			"rarity": str(row.get("rarity", "COMMON")) }
	out["gear"] = gear
	var weapons: Array = []
	for w in ch.inventory.weapon_options(t):
		weapons.append({ "uid": str(w.uid), "item_id": str(w.item_id), "name": str(w.name), "weapon_type": str(w.weapon_type),
			"atk": int(w.atk), "equipped": ch.inventory.is_equipped(str(w.uid)) })
	out["weapons"] = weapons
	return out
