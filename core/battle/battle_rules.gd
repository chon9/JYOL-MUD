class_name BattleRules
extends RefCounted
## 指令驗證與結算（M1_PLAN 3.4.3、4.7）、等待模式逾時（TECH_ARCH 10.7）。

## M3A_PLAN 5.1：Protocol.BATTLE_CMDS 與此相同（WP-RULES Day-0）
const CMDS := ["MOVE", "ATTACK", "ART", "DEFEND", "REST", "EQUIP", "FLEE",
	"POISON", "MEDIC", "HIDDEN", "FORMATION", "INNER", "ACUPOINT", "ITEM",
	"DODGE", "QING"]   # M3D_PLAN §3.1、§3.2（WP-COMBAT）
const PARTS := ["胸口", "左肩", "右臂", "小腹", "後背", "頭頂", "左腿", "右腿"]   # 【設計提案】3.8.4
const AFK_TIMEOUT_S := 3.0
const BARE_HANDS := "拳腳"
const NO_WEAPON := "空手"
## status_effects 表缺列時的後備值（3.11.14：內傷）
const STATUS_DEFAULTS := {
	"inner_wound": { "id": "inner_wound", "name": "內傷", "duration_actions": 5, "blocks": ["REST"],
		"qi_pct_per_action": 0.02 },
}

## ---------------------------------------------------------------- M3d（M3D_PLAN §3；WP-COMBAT）
## 數字全部【設計提案】（研究：閃「可減低中招機率」、輕「功能和使用與烙跑鞋一樣」，量沒有公布）
const DODGE_BASE := 0.15               # 閃：命中率 −(0.15 + 基本閃躲/1000)，最多 −0.30
const DODGE_MAX := 0.30
const QING_MODES := ["JUMP", "ESCAPE"]
const QING_JUMP_BASE := 10             # 飛身越敵：內力 10 + 2 × 移動範圍
const QING_JUMP_PER_RANGE := 2
const QING_ESCAPE_COST := 30           # 輕功脫身：內力 30
const QING_ESCAPE_MIN := 20.0          # 成功率 clamp(20 + 輕功 × 0.4 + 基本輕功 × 0.2, 20, 80)%
const QING_ESCAPE_MAX := 80.0
## 烙跑鞋與輕功脫身都不能用的戰鬥（§3.4）：任務戰、試煉、江湖試煉（ROGUE：脫身＝玩家方全倒判負，審查）；另外劫鏢方（ROB 的 side 0）也不行
const FLEE_SHOE_BLOCKED := ["QUEST", "TRIAL", "ROGUE"]
const EQUIP_CD_DEFAULT_MS := 0         # spec 與 opts 都沒帶冷卻時不限制（舊戰鬥規格、測試；主機的 spec 一律帶 equip_cd_ms）

## 閃的人這一下命中率要減多少
static func dodge_hit_drop(def: BattleUnit) -> float:
	return minf(DODGE_MAX, DODGE_BASE + def.skill("basic_dodge") / 1000.0)

static func qing_jump_cost(u: BattleUnit) -> int:
	return QING_JUMP_BASE + QING_JUMP_PER_RANGE * BattleFormulas.move_range(u)

## 輕功脫身成功率（0–1）
static func qing_escape_chance(u: BattleUnit) -> float:
	return clampf(QING_ESCAPE_MIN + u.lightness() * 0.4 + u.skill("basic_body") * 0.2, QING_ESCAPE_MIN, QING_ESCAPE_MAX) / 100.0

## 這場戰鬥不讓「特殊脫身」（烙跑鞋、輕功脫身）：任務戰、試煉、劫鏢方
static func special_flee_blocked(b: Battle, u: BattleUnit) -> bool:
	var kind := str(b.opts.get("kind", ""))
	return kind in FLEE_SHOE_BLOCKED or (kind == "ROB" and u.side == 0)

## 換裝冷卻（秒）：spec.equip_cd_ms（主機依伺服器選項 equip_cooldown_ms 帶入）→ opts.equip_cooldown_ms → 0
static func equip_cd_s(b: Battle, u: BattleUnit) -> float:
	var ms := u.equip_cd_ms()
	if ms < 0:
		ms = int(b.opts.get("equip_cooldown_ms", EQUIP_CD_DEFAULT_MS))
	return maxf(0.0, ms / 1000.0)

static func dodge_enabled(b: Battle) -> bool:
	return bool(b.opts.get("dodge_cmd", true))

## ---------------------------------------------------------------- 指令正規化

## 回傳正規化後的指令（target 轉成 Vector2i）；cmd 不認得回 {}。
static func normalize_cmd(cmd: Dictionary) -> Dictionary:
	var c := str(cmd.get("cmd", ""))
	if not CMDS.has(c):
		return {}
	var out := { "cmd": c }
	if cmd.has("target"):
		var t: Variant = cmd["target"]
		if t is Vector2i:
			out["target"] = t
		elif (t is Array or t is PackedInt32Array) and t.size() == 2 \
				and _is_num(t[0]) and _is_num(t[1]):
			out["target"] = Vector2i(int(t[0]), int(t[1]))
		else:
			out["target"] = null   # 形狀錯誤 → validate 時回 bad_cmd
	if cmd.has("art"):
		out["art"] = str(cmd["art"])
	if cmd.has("move"):
		out["move"] = str(cmd["move"])
	if cmd.has("power_tenths"):
		out["power_tenths"] = int(cmd["power_tenths"]) if _is_num(cmd["power_tenths"]) else -1
	if cmd.has("item_uid"):
		out["item_uid"] = str(cmd["item_uid"])
	if cmd.has("mode"):
		out["mode"] = str(cmd["mode"])
	if cmd.get("auto", false):
		out["auto"] = true
	return out

static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

## ---------------------------------------------------------------- 驗證

static func validate_cmd(b: Battle, u: BattleUnit, cmd: Dictionary, tables: Dictionary) -> String:
	if b.state == Battle.State.ENDED:
		return "battle_over"
	if u == null or u.state != BattleUnit.READY:
		return "not_ready"
	var c := normalize_cmd(cmd)
	if c.is_empty():
		return "bad_cmd"
	# M3A_PLAN 5.2：狀態封鎖（blocks 含此指令）在各指令的檢查之前
	if is_blocked(u, str(c.cmd), tables):
		return "status_blocked"
	if BattleCmds.NEW_CMDS.has(c.cmd):
		return BattleCmds.validate(b, u, c, tables)
	match c.cmd:
		"MOVE":
			if not c.has("target") or c.target == null:
				return "bad_cmd"
			var t: Vector2i = c.target
			if not BattleGrid.in_bounds(t):
				return "out_of_range"
			var occ: BattleUnit = b.unit_at(t)
			if occ != null:
				return "occupied"
			if not b.grid.reachable(u.pos, BattleFormulas.move_range(u)).has(t):
				return "out_of_range"
		"ATTACK":
			if not c.has("target") or c.target == null:
				return "bad_cmd"
			var tu := _enemy_at(b, u, c.target)
			if tu == null:
				return "no_target"
			if BattleGrid.manhattan(u.pos, tu.pos) > 1:
				return "out_of_range"
		"ART":
			if not c.has("art") or not c.has("move") or not c.has("target") or c.target == null:
				return "bad_cmd"
			var tenths: int = c.get("power_tenths", 10)
			if tenths < 1 or tenths > 10:
				return "bad_cmd"
			var art_row := art_row_for(u, c.art, tables)
			if art_row.is_empty():
				return "art_unknown"
			var move_row := move_row_for(art_row, c.move)
			if move_row.is_empty() or int(move_row.get("unlock_level", 1)) > u.skill(c.art):
				return "move_locked"
			var cat := str(art_row.get("category", "FIST"))
			if cat != "FIST" and u.weapon_type() != cat:
				return "need_weapon"
			if not ComboRules.usable(b, u, art_row):
				return "combo_partner_absent"   # M3d 審查：合體武功要夥伴同場（兩人同使）
			# M3A_PLAN 5.2：範圍招式的 target 是中心格（AROUND 以自己為中心）
			if BattleAoe.is_aoe(str(move_row.get("aoe", "SINGLE"))):
				var aerr := BattleAoe.check(b, u, move_row, c.target)
				if aerr != "":
					return aerr
			else:
				var tu := _enemy_at(b, u, c.target)
				if tu == null:
					return "no_target"
				if BattleGrid.manhattan(u.pos, tu.pos) > int(move_row.get("range", 1)):
					return "out_of_range"
			if u.neili < BattleFormulas.inner_cost(move_row, tenths):
				return "not_enough_neili"
			if u.jing < int(move_row.get("cost_jing", 0)):
				return "not_enough_jing"
		"DEFEND":
			pass
		"REST":
			pass
		"EQUIP":
			if not c.has("item_uid"):
				return "bad_cmd"
			if c.item_uid != "" and weapon_option(u, c.item_uid).is_empty():
				return "no_item"
			# M3D_PLAN §3.6：換裝兩秒（戰鬥時間；開戰前在地圖上換過不算）
			if b.time_s() - u.last_equip_t < equip_cd_s(b, u) - 0.0001:
				return "equip_cooldown"
		"FLEE":
			# M3D_PLAN §3.4：無敵烙跑鞋 → 任何格子、追擊戰都能逃（任務戰、試煉、劫鏢方除外）
			if u.flee_anywhere() and not special_flee_blocked(b, u):
				return ""
			if bool(b.opts.get("no_flee", false)):
				return "no_flee"   # 追擊戰、試煉不能逃（M3A_PLAN 5.9）
			if not b.grid.is_escape(u.pos):
				return "not_on_escape"
		"DODGE":
			if not dodge_enabled(b):
				return "dodge_off"
		"QING":
			return _validate_qing(b, u, c, tables)
	return ""

## 輕（M3D_PLAN §3.2）：later_battle_cmds 關 → qing_off；JUMP 照移動的封鎖、ESCAPE 照逃跑的封鎖
static func _validate_qing(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary) -> String:
	if not BattleCmds.later_cmds(b):
		return "qing_off"
	var mode := str(c.get("mode", ""))
	match mode:
		"JUMP":
			if is_blocked(u, "MOVE", tables):
				return "status_blocked"
			if not c.has("target") or c.target == null:
				return "bad_cmd"
			var t: Vector2i = c.target
			if not BattleGrid.in_bounds(t):
				return "out_of_range"
			if b.unit_at(t) != null:
				return "occupied"
			if not b.grid.jump_targets(u.pos, BattleFormulas.move_range(u) + 1).has(t):
				return "out_of_range"
			if u.neili < qing_jump_cost(u):
				return "not_enough_neili"
		"ESCAPE":
			if is_blocked(u, "FLEE", tables):
				return "status_blocked"
			if special_flee_blocked(b, u):
				return "no_flee"
			if u.neili < QING_ESCAPE_COST:
				return "not_enough_neili"
		_:
			return "bad_cmd"
	return ""

## 可在戰鬥中使用的武功列（會此武功、在 spec.arts 內、類別 FIST..SPEAR）；否則 {}
static func art_row_for(u: BattleUnit, art_id: String, tables: Dictionary) -> Dictionary:
	if art_id == "" or not u.arts().has(art_id) or u.skill(art_id) < 1:
		return {}
	var row: Dictionary = tables.get("martial_arts", {}).get(art_id, {})
	if row.is_empty() or not BattleFormulas.BATTLE_CATEGORIES.has(str(row.get("category", ""))):
		return {}
	var r := row.duplicate()
	r["id"] = art_id
	return r

static func move_row_for(art_row: Dictionary, move_id: String) -> Dictionary:
	for m in art_row.get("moves", []):
		if str(m.get("id", "")) == move_id:
			return m
	return {}

static func weapon_option(u: BattleUnit, item_uid: String) -> Dictionary:
	for w in u.weapon_options():
		if str(w.get("uid", "")) == item_uid:
			return w
	return {}

static func status_row(status_id: String, tables: Dictionary) -> Dictionary:
	var row: Dictionary = tables.get("status_effects", {}).get(status_id, {})
	if row.is_empty():
		return STATUS_DEFAULTS.get(status_id, { "id": status_id, "name": status_id, "duration_actions": 1,
			"blocks": [], "qi_pct_per_action": 0.0 })
	return row

static func is_blocked(u: BattleUnit, cmd: String, tables: Dictionary) -> bool:
	for sid in u.statuses:
		if status_row(str(sid), tables).get("blocks", []).has(cmd):
			return true
	return false

static func _enemy_at(b: Battle, u: BattleUnit, t: Variant) -> BattleUnit:
	if not (t is Vector2i):
		return null
	var tu: BattleUnit = b.unit_at(t)
	if tu == null or tu.side == u.side or not tu.is_active():
		return null
	return tu

## ---------------------------------------------------------------- 等待模式（10.7）

## 一般（非 afk）逾時秒數：依參戰真人數縮短；本輪累計等待超過預算 → 最小值
static func normal_timeout(b: Battle, opts: Dictionary) -> float:
	var base := float(opts.get("wait_mode_timeout_s", 20))
	var mn := float(opts.get("wait_mode_timeout_min_s", 8))
	var budget := float(opts.get("wait_mode_round_budget_s", 45))
	var humans := maxi(1, b.active_humans().size())
	var t := maxf(mn, base - 2.0 * (humans - 1))
	if b.round_wait_s() >= budget:
		t = mn
	return t

static func unit_timeout(b: Battle, u: BattleUnit, opts: Dictionary) -> float:
	if u.afk:
		return AFK_TIMEOUT_S
	return normal_timeout(b, opts)

## 本次等待的逾時秒數（全部等待者都是 afk 時為 3 秒）
static func await_timeout(b: Battle, pending: Array, opts: Dictionary) -> float:
	var t := 0.0
	var any := false
	for u in pending:
		if u.is_ai():
			continue
		any = true
		t = maxf(t, unit_timeout(b, u, opts))
	return t if any else normal_timeout(b, opts)

## ---------------------------------------------------------------- 結算

static func execute(b: Battle, u: BattleUnit, cmd: Dictionary, tables: Dictionary, rng: RandomNumberGenerator) -> Array:
	var ev: Array = []
	var c := normalize_cmd(cmd)
	if c.is_empty():
		c = { "cmd": "DEFEND" }
	u.defending = false          # 防禦姿態只維持到自己下次行動前
	u.dodging = false            # M3d「閃」也一樣（M3D_PLAN §3.1）
	u.state = BattleUnit.ACTING
	u.actions += 1
	# M3A_PLAN 5.7：行動開始前先看有沒有「跳過」「亂打」的狀態（次數在 _status_tick 遞減）
	var skip_sid := ""
	var confused := false
	if not u.statuses.is_empty():
		skip_sid = BattleStatus.has_flag(u, "skip_actions", tables)
		confused = BattleStatus.has_flag(u, "random_action", tables) != ""
	ev.append_array(_status_tick(b, u, tables))
	if not u.is_active():
		return ev
	var who := { "uid": u.uid, "name": u.unit_name(), "peer": u.peer }
	if not u.formation.is_empty():
		ev.append_array(BattleCmds.formation_upkeep(b, u, tables))
	if skip_sid != "":
		ev.append(b.make_event("battle_status_skip", _merge(who, { "status": skip_sid,
			"status_name": str(status_row(skip_sid, tables).get("name", skip_sid)) })))
		c = { "cmd": "SKIP" }
	elif confused:
		ev.append_array(_confused_action(b, u, tables, rng))
		c = { "cmd": "SKIP" }
	match c.cmd:
		"MOVE":
			var from := u.pos
			u.pos = c.target
			ev.append(b.make_event("battle_move", _merge(who, { "from": [from.x, from.y], "to": [u.pos.x, u.pos.y] })))
			ev.append_array(_on_move(b, u, tables))
		"ATTACK":
			var tu := _enemy_at(b, u, c.target)
			if tu != null:
				ev.append_array(resolve_strike(b, u, tu, {}, {}, 0, tables, rng, false))
			ev.append_array(_recover_proc(b, u, tables, rng))
		"ART":
			var art_row := art_row_for(u, c.art, tables)
			var move_row := move_row_for(art_row, c.move)
			var tenths: int = c.get("power_tenths", 10)
			u.neili = maxi(0, u.neili - BattleFormulas.inner_cost(move_row, tenths))
			u.jing = maxi(0, u.jing - int(move_row.get("cost_jing", 0)))
			if BattleAoe.is_aoe(str(move_row.get("aoe", "SINGLE"))):
				ev.append_array(_resolve_aoe(b, u, art_row, move_row, tenths, c.target, tables, rng))
			else:
				var tu := _enemy_at(b, u, c.target)
				if tu != null:
					var dealt0 := u.dmg_dealt
					ev.append_array(resolve_strike(b, u, tu, art_row, move_row, tenths, tables, rng, false))
					# M3D_PLAN §3.3.3：合體武功 → 記號、3 秒窗、依默契擲合體一擊
					if not ComboRules.combo_of(art_row).is_empty():
						ev.append_array(ComboRules.after_art(b, u, art_row, u.dmg_dealt - dealt0, rng, tu.uid))
			ev.append_array(_recover_proc(b, u, tables, rng))
		"DEFEND":
			u.defending = true
			ev.append(b.make_event("battle_defend", who))
		"REST":
			var qg := mini(maxi(0, u.qi_max() - u.qi), roundi(u.qi_max() * 0.05))
			var ng := mini(maxi(0, u.neili_max() - u.neili), roundi(u.neili_max() * 0.10))
			u.qi += qg
			u.neili += ng
			ev.append(b.make_event("battle_rest", _merge(who, { "qi_gain": qg, "neili_gain": ng, "qi": u.qi, "neili": u.neili })))
			# 全真 養生（REST）：氣、內力各再回 10%（M3A_PLAN 5.6）
			if BattleStatus.try_proc(b, u, "REST", tables):
				var qg2 := mini(maxi(0, u.qi_max() - u.qi), roundi(u.qi_max() * BattleStatus.REST_PROC_PCT))
				var ng2 := mini(maxi(0, u.neili_max() - u.neili), roundi(u.neili_max() * BattleStatus.REST_PROC_PCT))
				u.qi += qg2
				u.neili += ng2
				ev.append(BattleStatus.proc_event(b, u, "REST", tables, { "qi_gain": qg2, "neili_gain": ng2 }))
		"EQUIP":
			var item_name := NO_WEAPON
			if c.item_uid == "":
				u.weapon = BattleUnit._norm_weapon({})
			else:
				u.weapon = BattleUnit._norm_weapon(weapon_option(u, c.item_uid))
				item_name = str(u.weapon.name)
			u.last_equip_t = b.time_s()   # M3D_PLAN §3.6
			# M3C_PLAN §7.2（WP-FX）純表現：換兵器後的 wtype／wfx（別人的畫面也換武器特效與名牌圖示）
			ev.append(b.make_event("battle_equip", _merge(who, { "item_name": item_name, "item_uid": str(u.weapon.uid),
				"wtype": u.weapon_type(), "wfx": Battle.weapon_fx_of(u, tables) })))
		"FLEE":
			if not u.formation.is_empty():
				ev.append_array(BattleCmds.break_formation(b, u, tables))
			u.state = BattleUnit.FLED
			ev.append(b.make_event("battle_flee", who))
		"POISON", "MEDIC", "HIDDEN", "FORMATION", "INNER", "ACUPOINT", "ITEM":
			ev.append_array(BattleCmds.execute(b, u, c, tables, rng))
		"DODGE":
			u.dodging = true
			ev.append(b.make_event("battle_dodge", who))
		"QING":
			ev.append_array(_execute_qing(b, u, c, tables, rng, who))
	if u.state == BattleUnit.ACTING:
		u.state = BattleUnit.CHARGING
		var moved: bool = c.cmd == "MOVE" or (c.cmd == "QING" and str(c.get("mode", "")) == "JUMP")
		u.gauge = Battle.MOVE_GAUGE if moved else 0.0
	return ev

## 輕（M3D_PLAN §3.2）：JUMP 越過有人的格子落到移動範圍 +1 的空格（時間棒照移動）；ESCAPE 依機率原地脫身
static func _execute_qing(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary, rng: RandomNumberGenerator,
		who: Dictionary) -> Array:
	var ev: Array = []
	match str(c.get("mode", "")):
		"JUMP":
			u.neili = maxi(0, u.neili - qing_jump_cost(u))
			var from := u.pos
			u.pos = c.target
			ev.append(b.make_event("battle_qing_jump", _merge(who, { "from": [from.x, from.y], "to": [u.pos.x, u.pos.y],
				"neili": u.neili })))
			ev.append_array(_on_move(b, u, tables))
		"ESCAPE":
			u.neili = maxi(0, u.neili - QING_ESCAPE_COST)
			var p := qing_escape_chance(u)
			if rng.randf() < p:
				if not u.formation.is_empty():
					ev.append_array(BattleCmds.break_formation(b, u, tables))
				u.state = BattleUnit.FLED
				ev.append(b.make_event("battle_qing_escape", _merge(who, { "neili": u.neili })))
			else:
				ev.append(b.make_event("battle_qing_fail", _merge(who, { "neili": u.neili })))
	return ev

## 一次普通攻擊或出招（含反擊）。結算順序見 4.7。
## no_counter：範圍招式的每個目標各自結算，但不引發反擊（M3A_PLAN 5.3）
static func resolve_strike(b: Battle, att: BattleUnit, def: BattleUnit, art_row: Dictionary, move_row: Dictionary,
		tenths: int, tables: Dictionary, rng: RandomNumberGenerator, is_counter: bool, no_counter: bool = false) -> Array:
	var ev: Array = []
	var is_art := not art_row.is_empty()
	var category := BattleFormulas.attack_category(att, art_row)
	var art_level: int
	var move_name: String
	if is_art:
		art_level = att.skill(str(art_row.id))
		move_name = str(move_row.get("name", ""))
	else:
		art_level = BattleFormulas.base_level(att, BattleFormulas.basic_for_category(category), "", tables)
		move_name = weapon_label(att)
	var common := { "atk_uid": att.uid, "def_uid": def.uid, "atk": att.unit_name(), "def": def.unit_name(),
		"atk_peer": att.peer, "def_peer": def.peer, "counter": is_counter,
		"cat": str(art_row.get("category", "")) if is_art else "" }   # M3C_PLAN §7.2（WP-FX）純表現：武功類別，普攻 ""
	# 命中（峨嵋 斷惡 EVADE：命中判定之前擲，觸發時這一下命中率 −15 個百分點）
	var hit_p := BattleFormulas.hit_chance(att, def, art_level)
	if BattleStatus.try_proc(b, def, "EVADE", tables):
		hit_p = maxf(0.0, hit_p - BattleStatus.EVADE_HIT_DROP)
		ev.append(BattleStatus.proc_event(b, def, "EVADE", tables, { "def_uid": att.uid }))
	# M3D_PLAN §3.1：守方「閃」中 → 命中率再減 dodge_hit_drop（純表現：沒打中時 battle_miss 帶 dodged）
	var dodged := def.dodging
	if dodged:
		hit_p = maxf(0.0, hit_p - dodge_hit_drop(def))
	if rng.randf() >= hit_p:
		var mp := _merge(common, { "move": move_name })
		if dodged:
			mp["dodged"] = true
		ev.append(b.make_event("battle_miss", mp))
		return ev
	# 爆擊
	var crit := rng.randf() < BattleFormulas.crit_chance(att)
	if crit:
		ev.append(b.make_event("battle_crit", common))
	# 傷害
	var ap := BattleFormulas.attack_power(att, art_row, move_row, tenths, tables)
	var dp := BattleFormulas.defense_power(def, category, tables)
	if not att.statuses.is_empty():
		ap *= BattleStatus.atk_mult(att, tables)     # 分心、陣法加持（M3A_PLAN 5.7）
	if not def.statuses.is_empty():
		dp *= BattleStatus.def_mult(def, tables)
	var fr := BattleFormulas.float_range(att)
	var fm := rng.randf_range(fr.x, fr.y)
	var ib := rng.randf_range(0.0, BattleFormulas.inner_bonus_max(att))
	var dmg := BattleFormulas.base_damage(ap, dp, fm, ib)
	if crit:
		dmg = BattleFormulas.apply_crit(dmg, BattleFormulas.crit_mult(att))
	if is_counter:
		dmg = maxi(1, roundi(dmg * BattleFormulas.COUNTER_MULT))
	# 血刀 威嚇（HEAVY）：傷害 × 1.5
	if BattleStatus.try_proc(b, att, "HEAVY", tables):
		dmg = maxi(1, roundi(dmg * BattleStatus.HEAVY_MULT))
		ev.append(BattleStatus.proc_event(b, att, "HEAVY", tables, { "def_uid": def.uid }))
	# 守方門派技能 DEFENSE
	# 門派技能的戰鬥觸發是 2002-01-25 才開（news 399 第 6 條）：規則 later_battle_cmds 關時不觸發（M3a 審查修正）
	# M3B_PLAN §5.1.7、O20（D12）：與新 8 種同一套觸發——付得起 sect_skill_cost 才擲、觸發時各扣 PROC_COST
	var ss := def.sect_skill()
	if BattleStatus.try_proc(b, def, "DEFENSE", tables):
		dmg = maxi(1, roundi(dmg * BattleFormulas.defense_proc_mult(int(ss.level))))
		ev.append(b.make_event("battle_proc_DEFENSE", { "uid": def.uid, "name": def.unit_name(), "peer": def.peer,
			"skill_name": sect_skill_name(ss, tables) }))
	# 扣氣
	def.qi = maxi(1, def.qi - dmg)
	def.last_hitter = att.uid
	att.dmg_dealt += dmg      # M3D_PLAN §9.2：比武判定用（含反擊）
	att.hits_landed += 1
	var part: String = PARTS[rng.randi_range(0, PARTS.size() - 1)]
	var hit := _merge(common, { "dmg": dmg, "part": part, "crit": crit, "def_qi": def.qi })
	var key: String
	if is_art:
		key = str(move_row.get("flavor", "move_fist_basic"))
		hit["art"] = str(art_row.get("name", ""))
		hit["move"] = move_name
		hit["tenths"] = tenths
		hit["atk_neili"] = att.neili
	else:
		key = "atk_" + category.to_lower()
		hit["weapon"] = move_name
	ev.append(b.make_event(key, hit))
	if def.qi <= 1:
		ev.append_array(kill(b, def, att))
		return ev
	# 招式附帶狀態（玩家武功「特」附帶中毒限後期版：BattleCmds.move_status_ok；M3a 審查 A1）
	if is_art and BattleCmds.move_status_ok(b, art_row, str(move_row.get("status", ""))):
		if rng.randf() < float(move_row.get("status_chance", 0.0)):
			ev.append_array(apply_status(b, def, str(move_row.status), tables))
	# 點穴武功（acupoint: true）的一般招式命中：另有 0.05 + 等級 × 0.001 的機率附帶封穴【後期版】
	if is_art and bool(art_row.get("acupoint", false)) and def.is_active():
		if rng.randf() < 0.05 + art_level * 0.001:
			ev.append_array(apply_status(b, def, "acupoint", tables))
	# 古墓 清心／靈鷲 定性／星宿 諂媚：命中後擲觸發
	ev.append_array(BattleStatus.on_hit_procs(b, att, def, tables))
	# 反擊（反擊不會再引發反擊；需相鄰；範圍招式不引發反擊）
	if not is_counter and not no_counter and def.is_active() and att.is_active() and not def.dodging \
			and BattleGrid.manhattan(att.pos, def.pos) <= 1:   # M3d：「閃」的人不反擊
		# 恆山 慈悲（COUNTER）先判；觸發就不再擲 M1 的定力反擊（不疊加）
		if BattleStatus.try_proc(b, def, "COUNTER", tables):
			ev.append(BattleStatus.proc_event(b, def, "COUNTER", tables, { "def_uid": att.uid }))
			ev.append(b.make_event("battle_counter", { "atk_uid": def.uid, "def_uid": att.uid, "atk": def.unit_name(),
				"def": att.unit_name(), "atk_peer": def.peer, "def_peer": att.peer }))
			ev.append_array(resolve_strike(b, def, att, {}, {}, 0, tables, rng, true))
		elif rng.randf() < BattleFormulas.counter_chance(def):
			ev.append(b.make_event("battle_counter", { "atk_uid": def.uid, "def_uid": att.uid, "atk": def.unit_name(),
				"def": att.unit_name(), "atk_peer": def.peer, "def_peer": att.peer }))
			ev.append_array(resolve_strike(b, def, att, {}, {}, 0, tables, rng, true))
	return ev

## M3B_PLAN §5.1.7、O20（D12）：RECOVER 也走 BattleStatus.try_proc（付得起消耗才擲、觸發扣 sect_skill_cost 各 PROC_COST）。
## rng 參數保留給舊呼叫端（Battle.rng 與 b.rng 是同一個物件）
static func _recover_proc(b: Battle, u: BattleUnit, tables: Dictionary, _rng: RandomNumberGenerator) -> Array:
	var ss := u.sect_skill()
	if not BattleStatus.try_proc(b, u, "RECOVER", tables):
		return []
	var lv := int(ss.level)
	var pct := BattleFormulas.recover_pct(lv)
	var qg := mini(maxi(0, u.qi_max() - u.qi), roundi(u.qi_max() * pct))
	var sg := mini(maxi(0, u.shen_max() - u.shen), roundi(u.shen_max() * pct))
	u.qi += qg
	u.shen += sg
	return [b.make_event("battle_proc_RECOVER", { "uid": u.uid, "name": u.unit_name(), "peer": u.peer,
		"skill_name": sect_skill_name(ss, tables), "qi_gain": qg, "shen_gain": sg })]

## 行動開始：狀態效果（內傷扣氣、可致死）與次數遞減
## 每次行動扣 qi_max × (qi_pct_per_action + qi_pct_per_level × 等級)；中毒用 battle_poison_tick，其他（內傷）沿用 battle_wound_tick
static func _status_tick(b: Battle, u: BattleUnit, tables: Dictionary) -> Array:
	var ev: Array = []
	for sid in u.statuses.keys():
		if not u.statuses.has(sid):
			continue
		var row := status_row(str(sid), tables)
		# 流血：氣上限一直往下掉（研究 gaoshou/28；每次行動比例【設計提案】）
		var mpct := float(row.get("qi_max_pct_per_action", 0.0))
		if mpct > 0.0:
			var cut := maxi(1, roundi(u.qi_max() * mpct))
			u.spec["qi_max"] = maxi(1, u.qi_max() - cut)
			u.qi = mini(u.qi, u.qi_max())
			ev.append(b.make_event("battle_bleed_tick", { "uid": u.uid, "name": u.unit_name(), "peer": u.peer,
				"dmg": cut, "qi": u.qi, "qi_max": u.qi_max(), "status": str(sid) }))
		var pct := BattleStatus.action_pct(u, str(sid), row)
		if pct > 0.0:
			var dmg := maxi(1, roundi(u.qi_max() * pct))
			u.qi = maxi(1, u.qi - dmg)
			var key := "battle_poison_tick" if str(sid) == "poison" else "battle_wound_tick"
			ev.append(b.make_event(key, { "uid": u.uid, "name": u.unit_name(), "peer": u.peer,
				"dmg": dmg, "qi": u.qi }))
			if u.qi <= 1:
				ev.append_array(kill(b, u, b.unit(u.last_hitter)))
				return ev
		u.statuses[sid] = int(u.statuses[sid]) - 1
		if int(u.statuses[sid]) <= 0:
			u.statuses.erase(sid)
			u.status_levels.erase(sid)
			if str(sid) == "formation" and not u.formation.is_empty():
				u.formation = {}   # 陣法加持到期：只有自己退出
			ev.append(b.make_event("battle_status_off", { "uid": u.uid, "name": u.unit_name(), "peer": u.peer,
				"status": str(sid), "status_name": str(row.get("name", sid)) }))
	return ev

## 施加狀態（M3A_PLAN 5.7）：RESIST 抵抗、定力縮短、LEVEL_MAX 疊加，見 BattleStatus.apply
static func apply_status(b: Battle, u: BattleUnit, status_id: String, tables: Dictionary, level: int = 1) -> Array:
	return BattleStatus.apply(b, u, status_id, tables, level)

## 「移」之後：流血等 qi_pct_per_move 扣氣；陣法成員移動 → 破陣
static func _on_move(b: Battle, u: BattleUnit, tables: Dictionary) -> Array:
	var ev: Array = []
	if not u.formation.is_empty():
		ev.append_array(BattleCmds.break_formation(b, u, tables))
	for sid in u.statuses.keys():
		var pct := float(status_row(str(sid), tables).get("qi_pct_per_move", 0.0))
		if pct <= 0.0:
			continue
		var dmg := maxi(1, roundi(u.qi_max() * pct))
		u.qi = maxi(1, u.qi - dmg)
		ev.append(b.make_event("battle_bleed_tick", { "uid": u.uid, "name": u.unit_name(), "peer": u.peer,
			"dmg": dmg, "qi": u.qi, "status": str(sid) }))
		if u.qi <= 1:
			ev.append_array(kill(b, u, b.unit(u.last_hitter)))
			return ev
	return ev

## 混亂：對射程 1 內隨機一個活人（不分敵我）普通攻擊；沒有就防（M3A_PLAN 5.7）
static func _confused_action(b: Battle, u: BattleUnit, tables: Dictionary, rng: RandomNumberGenerator) -> Array:
	var ev: Array = [b.make_event("battle_confused", { "uid": u.uid, "name": u.unit_name(), "peer": u.peer })]
	var near: Array = b.units.filter(func(o): return o != u and o.is_active() and BattleGrid.manhattan(u.pos, o.pos) <= 1)
	near.sort_custom(func(a, c): return a.uid < c.uid)
	if near.is_empty():
		u.defending = true
		ev.append(b.make_event("battle_defend", { "uid": u.uid, "name": u.unit_name(), "peer": u.peer }))
		return ev
	var t: BattleUnit = near[rng.randi_range(0, near.size() - 1)]
	ev.append_array(resolve_strike(b, u, t, {}, {}, 0, tables, rng, false))
	return ev

## 範圍招式：內力已在呼叫端扣一次；每個目標各自 resolve_strike（不反擊），前面加 battle_aoe（ui）
static func _resolve_aoe(b: Battle, u: BattleUnit, art_row: Dictionary, move_row: Dictionary, tenths: int,
		center: Vector2i, tables: Dictionary, rng: RandomNumberGenerator) -> Array:
	var aoe := str(move_row.get("aoe", "SINGLE"))
	var area := BattleAoe.cells(aoe, u.pos, center, int(move_row.get("range", 1)))
	var targets := BattleAoe.enemies_in(b, u, area)
	var ev: Array = [b.make_event("battle_aoe", { "uid": u.uid, "name": u.unit_name(), "peer": u.peer,
		"move": str(move_row.get("name", "")), "aoe": aoe, "cells": BattleAoe.cells_json(area),
		"targets": targets.map(func(t): return t.uid) }, true)]
	for t in targets:
		if not u.is_active():
			break
		if t.is_active():
			ev.append_array(resolve_strike(b, u, t, art_row, move_row, tenths, tables, rng, false, true))
	return ev

## 氣降到 1 → 死亡（GDD 2.3）
static func kill(b: Battle, victim: BattleUnit, killer: BattleUnit) -> Array:
	var pre: Array = []
	if not victim.formation.is_empty():
		pre = BattleCmds.break_formation(b, victim)   # 一人倒下陣就破【已證實】
	victim.state = BattleUnit.DEAD
	victim.qi = 1
	victim.queued_cmd = {}
	victim.defending = false
	var by_name := ""
	if killer != null:
		victim.killed_by = killer.uid
		by_name = killer.unit_name()
		if not victim.is_player():
			killer.kills.append(str(victim.spec.get("ref", "")))
	var p := { "uid": victim.uid, "name": victim.unit_name(), "peer": victim.peer, "by": by_name,
		"by_uid": victim.killed_by }
	if victim.is_player():
		pre.append(b.make_event("battle_death", p))
		return pre
	p["peer"] = 0
	pre.append(b.make_event("battle_kill", p))
	return pre

static func weapon_label(u: BattleUnit) -> String:
	var n := str(u.weapon.get("name", ""))
	if n == "" or u.weapon_type() == "FIST":
		return BARE_HANDS if n == "" else n
	return n

static func sect_skill_name(ss: Dictionary, tables: Dictionary) -> String:
	if ss.has("name"):
		return str(ss.name)
	var sid := str(ss.get("id", ""))
	for row in tables.get("sects", {}).values():
		if str(row.get("sect_skill", "")) == sid:
			return str(row.get("sect_skill_name", sid))
	return sid

static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	out.merge(b, true)
	return out
