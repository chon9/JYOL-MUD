class_name BattleCmds
extends RefCounted
## M3a 戰鬥指令：毒 POISON、醫 MEDIC、暗 HIDDEN、陣 FORMATION、內 INNER、穴 ACUPOINT、用藥 ITEM（M3A_PLAN 5.1–5.4）。
## 驗證順序與原因碼照 5.2；公式照 5.4（全部【設計提案】，除非另註）。core/battle 不呼叫 Character／Survival。

const NEW_CMDS := ["POISON", "MEDIC", "HIDDEN", "FORMATION", "INNER", "ACUPOINT", "ITEM"]
const INNER_MODES := ["HEAL", "EXPEL", "UNSEAL", "TRANSFER"]
const MEDIC_JING := 10
const MEDIC_SHEN := 5
const HENGSHAN_MEDIC_MULT := 1.3      # 恆山醫療較強【已證實早期文；倍數設計提案】
const QUANZHEN_HEAL_MULT := 1.3       # 全真內力療傷較強【已證實 2002；倍數設計提案】
const EXPEL_COST := 20
const UNSEAL_COST := 15
const ACUPOINT_COST := 15
const HIDDEN_MAX_RANGE := 6
const NON_SECT_POISON_MULT := 0.5     # 非本派（叛派者）施毒成功率 ×0.5【已證實「低很多」；倍數設計提案】

## 主機規則 later_battle_cmds（Battle.opts；缺省 true，與 RULE_DEFAULTS 相同）
static func later_cmds(b: Battle) -> bool:
	return bool(b.opts.get("later_battle_cmds", true))

static func art_row(art_id: String, tables: Dictionary) -> Dictionary:
	var r: Dictionary = tables.get("martial_arts", {}).get(art_id, {})
	if r.is_empty():
		return {}
	var out := r.duplicate()
	out["id"] = art_id
	return out

static func first_move(arow: Dictionary) -> Dictionary:
	var m: Array = arow.get("moves", [])
	return m[0] if not m.is_empty() and m[0] is Dictionary else {}

## 指令武功（毒、醫、暗、穴）用的招式：已解鎖（unlock_level ≤ 武功等級）的最後一招；都沒解鎖時用第一招。
## M3a 審查 B3：以前一律用第一招，放毒術第二招（60 級，射程 2）永遠用不到
static func cmd_move(u: BattleUnit, arow: Dictionary) -> Dictionary:
	if arow.is_empty():
		return {}
	var lv := u.skill(str(arow.get("id", "")))
	var best := first_move(arow)
	for m in arow.get("moves", []):
		if m is Dictionary and int(m.get("unlock_level", 1)) <= lv:
			best = m
	return best

## 招式附帶的狀態在這場戰鬥能不能施加（M3a 審查 A1）：玩家武功的「特」（以及暗器武功）附帶中毒是後期版才有——
## news 316（2001-08-09）「有毒的武功用『特』只造成兵器傷害，只有『毒』才會中毒」→ 規則 later_battle_cmds 關時不施加。
## 流血：狀態本身是 2001 的（news 316），但原作的觸發來源【待考證】（研究：有記載的流血武功 血魔刀法 是 1.0B），
## 玩家武功招式附帶流血（血刀刀法、萬花劍法第 3 招）是【設計提案】→ 同樣只在 later_battle_cmds 開時施加，
## 2001 規則（classic_strict）不跑這個自創的觸發（M3a 審查 #4）。
## 怪物專用武功（毒蛇、玉蜂…）不受影響。其他狀態由 status_effects.since 控制（BattleStatus.available）。
const PLAYER_MOVE_LATER_STATUSES := ["poison", "bleed"]

static func move_status_ok(b: Battle, arow: Dictionary, status_id: String) -> bool:
	if status_id == "":
		return false
	if status_id in PLAYER_MOVE_LATER_STATUSES and not bool(arow.get("monster_only", false)) and not later_cmds(b):
		return false
	return true

## 「醫」治得好的狀態（status_effects.cure_by 含 MEDIC）；依 id 排序。
## 中毒：醫術治毒傷是 2002【後期版】→ 只在 later_battle_cmds 開、且 基本醫術 + 醫術武功 ≥ 10 × 中毒等級 時才算（M3a 審查 B2）
static func medic_cures(b: Battle, u: BattleUnit, tu: BattleUnit, a_medic: int, tables: Dictionary) -> Array:
	var out: Array = []
	var ids := tu.statuses.keys()
	ids.sort()
	for sid in ids:
		var srow := BattleStatus.row(str(sid), tables)
		if not (srow.get("cure_by", []) as Array).has("MEDIC"):
			continue
		if str(sid) == "poison" and not (later_cmds(b) \
				and u.skill("basic_medic") + a_medic >= 10 * tu.status_level("poison")):
			continue
		out.append(str(sid))
	return out

## 醫用的武功列：指定的（cmd_arts 裡）→ 沒指定時等級最高的一套
static func medic_art(u: BattleUnit, c: Dictionary, tables: Dictionary) -> Dictionary:
	var arow := {}
	if str(c.get("art", "")) != "":
		arow = cmd_art(u, "MEDIC", str(c.art), tables)
	if arow.is_empty():
		arow = best_cmd_art(u, "MEDIC", tables)
	return arow

## cmd_arts[cat] 中的 art（且等級 ≥ 1）；不符回 {}
static func cmd_art(u: BattleUnit, cat: String, art_id: String, tables: Dictionary) -> Dictionary:
	if art_id == "" or not u.cmd_arts(cat).has(art_id) or u.skill(art_id) < 1:
		return {}
	return art_row(art_id, tables)

## cmd_arts[cat] 中等級最高的一套（同級取清單順序）；沒有回 {}
static func best_cmd_art(u: BattleUnit, cat: String, tables: Dictionary) -> Dictionary:
	var best := {}
	var best_lv := 0
	for a in u.cmd_arts(cat):
		var lv := u.skill(str(a))
		if lv > best_lv:
			var r := art_row(str(a), tables)
			if not r.is_empty():
				best = r
				best_lv = lv
	return best

## ---------------------------------------------------------------- 開放條件（5.1；快照 cmd_avail 也用）

static func avail(b: Battle, u: BattleUnit) -> Dictionary:
	var inner_ok := not u.cmd_arts("INNER").is_empty() and later_cmds(b)
	return {
		"POISON": not u.cmd_arts("POISON").is_empty(),
		"MEDIC": u.skill("basic_medic") >= 1 or not u.cmd_arts("MEDIC").is_empty(),
		"HIDDEN": u.skill("basic_hidden") >= 1 and not u.hidden_items().is_empty(),
		"FORMATION": not u.cmd_arts("FORMATION").is_empty(),
		"INNER": INNER_MODES.duplicate() if inner_ok else [],
		"ACUPOINT": (not u.cmd_arts("ACUPOINT").is_empty() or u.skill("basic_stab") >= 10) and later_cmds(b),
		"ITEM": not u.battle_items().is_empty(),
		# M3D_PLAN §7（WP-COMBAT）：閃（規則 dodge_cmd）、輕（later_battle_cmds；可用的 mode 清單，內力夠才列）
		"DODGE": BattleRules.dodge_enabled(b),
		"QING": qing_modes(b, u),
	}

## 「輕」現在可用的 mode（M3D_PLAN §3.2）：JUMP 要內力 ≥ 10 + 2 × 移動範圍；ESCAPE 要內力 ≥ 30、這場戰鬥允許脫身
static func qing_modes(b: Battle, u: BattleUnit) -> Array:
	if not later_cmds(b):
		return []
	var out: Array = []
	if u.neili >= BattleRules.qing_jump_cost(u):
		out.append("JUMP")
	if u.neili >= BattleRules.QING_ESCAPE_COST and not BattleRules.special_flee_blocked(b, u):
		out.append("ESCAPE")
	return out

## ---------------------------------------------------------------- 驗證（5.2）

static func validate(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary) -> String:
	match str(c.cmd):
		"POISON": return _v_poison(b, u, c, tables)
		"MEDIC": return _v_medic(b, u, c, tables)
		"HIDDEN": return _v_hidden(b, u, c, tables)
		"FORMATION": return _v_formation(b, u, c, tables)
		"INNER": return _v_inner(b, u, c, tables)
		"ACUPOINT": return _v_acupoint(b, u, c, tables)
		"ITEM": return _v_item(b, u, c, tables)
	return "bad_cmd"

static func _target(c: Dictionary) -> Variant:
	return c.get("target", null) if c.get("target", null) is Vector2i else null

static func _enemy(b: Battle, u: BattleUnit, c: Dictionary) -> BattleUnit:
	var t: Variant = _target(c)
	if t == null:
		return null
	var tu: BattleUnit = b.unit_at(t)
	if tu == null or tu.side == u.side or not tu.is_active():
		return null
	return tu

## 自己或同側活著的單位
static func _ally(b: Battle, u: BattleUnit, c: Dictionary) -> BattleUnit:
	var t: Variant = _target(c)
	if t == null:
		return null
	var tu: BattleUnit = b.unit_at(t)
	if tu == null or tu.side != u.side or not tu.is_active():
		return null
	return tu

static func _v_poison(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary) -> String:
	if u.cmd_arts("POISON").is_empty():
		return "cmd_disabled"
	var arow := cmd_art(u, "POISON", str(c.get("art", "")), tables)
	if arow.is_empty():
		return "no_poison_art"
	var tu := _enemy(b, u, c)
	if tu == null:
		return "no_target"
	var m := cmd_move(u, arow)
	if BattleGrid.manhattan(u.pos, tu.pos) > int(m.get("range", 1)):
		return "out_of_range"
	if u.neili < int(m.get("cost_inner", 0)):
		return "not_enough_neili"
	return ""

static func _v_medic(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary) -> String:
	if not bool(avail(b, u).MEDIC):
		return "no_medic"
	var arow := {}
	if str(c.get("art", "")) != "":
		arow = cmd_art(u, "MEDIC", str(c.art), tables)
		if arow.is_empty():
			return "no_medic"
	var tu := _ally(b, u, c)
	if tu == null:
		return "not_ally"
	if arow.is_empty():
		arow = best_cmd_art(u, "MEDIC", tables)
	var r := 1
	if not arow.is_empty():
		r = maxi(1, int(cmd_move(u, arow).get("range", 1)))
	if BattleGrid.manhattan(u.pos, tu.pos) > r:
		return "out_of_range"
	# 氣全滿又沒有醫得好的狀態：不接受（以前只在介面變灰，主機照扣精神；M3a 審查 B5）
	var a_medic := u.skill(str(arow.get("id", ""))) if not arow.is_empty() else 0
	if tu.qi >= tu.qi_max() and medic_cures(b, u, tu, a_medic, tables).is_empty():
		return "nothing_to_heal"
	if u.jing < MEDIC_JING:
		return "not_enough_jing"
	if u.shen < MEDIC_SHEN:
		return "not_enough_shen"
	if not arow.is_empty() and u.neili < int(cmd_move(u, arow).get("cost_inner", 0)):
		return "not_enough_neili"
	return ""

static func _v_hidden(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary) -> String:
	if not bool(avail(b, u).HIDDEN):
		return "no_hidden"
	if str(c.get("art", "")) != "" and cmd_art(u, "HIDDEN", str(c.art), tables).is_empty():
		return "no_hidden"
	var it := BattleUnit.stack_of(u.hidden_items(), str(c.get("item_uid", "")))
	if u.stack_left(it) <= 0:
		return "no_ammo"
	var tu := _enemy(b, u, c)
	if tu == null:
		return "no_target"
	if BattleGrid.manhattan(u.pos, tu.pos) > hidden_range(u, str(c.get("art", "")), tables):
		return "out_of_range"
	# 暗器武功的招式內力（M3a 審查 B3：以前只加威力、不扣內力）
	if str(c.get("art", "")) != "":
		var harow := cmd_art(u, "HIDDEN", str(c.art), tables)
		if u.neili < int(cmd_move(u, harow).get("cost_inner", 0)):
			return "not_enough_neili"
	return ""

static func _v_formation(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary) -> String:
	var arow := cmd_art(u, "FORMATION", str(c.get("art", "")), tables)
	if arow.is_empty() or not (arow.get("formation", null) is Dictionary):
		return "no_formation_art"
	var f: Dictionary = arow.formation
	var cands := formation_candidates(b, u, arow)
	if cands.size() < int(f.get("party_size", 1)):
		return "formation_party"
	if formation_members(b, u, arow).is_empty():
		return "formation_stations"
	if u.neili < int(first_move(arow).get("cost_inner", 0)):
		return "not_enough_neili"
	return ""

static func _v_inner(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary) -> String:
	if not later_cmds(b):
		return "cmd_disabled"
	var arow := best_cmd_art(u, "INNER", tables)
	if arow.is_empty():
		return "no_inner_art"
	var mode := str(c.get("mode", ""))
	match mode:
		"HEAL":
			# 氣全滿：不接受（以前只在介面變灰，主機照扣 10% 內力；M3a 審查 B5）
			if u.qi >= u.qi_max():
				return "full_qi"
			if u.neili < heal_cost(u):
				return "not_enough_neili"
		"EXPEL":
			if not u.statuses.has("poison"):
				return "nothing_to_expel"
			if u.neili < EXPEL_COST:
				return "not_enough_neili"
		"UNSEAL":
			if not u.statuses.has("acupoint"):
				return "not_sealed"
			if u.neili < UNSEAL_COST:
				return "not_enough_neili"
		"TRANSFER":
			var tu := _ally(b, u, c)
			if tu == null or tu == u:
				return "not_ally"
			if BattleGrid.manhattan(u.pos, tu.pos) > 1:
				return "out_of_range"
			if transfer_amount(u, tu) <= 0:
				return "not_enough_neili"
		_:
			return "bad_cmd"
	return ""

static func _v_acupoint(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary) -> String:
	if not later_cmds(b):
		return "cmd_disabled"
	if not bool(avail(b, u).ACUPOINT):
		return "no_acupoint"
	var arow := {}
	if str(c.get("art", "")) != "":
		arow = cmd_art(u, "ACUPOINT", str(c.art), tables)
		if arow.is_empty():
			return "no_acupoint"
	var tu := _enemy(b, u, c)
	if tu == null:
		return "no_target"
	var r := 1
	if not arow.is_empty():
		r = maxi(1, int(cmd_move(u, arow).get("range", 1)))
	if BattleGrid.manhattan(u.pos, tu.pos) > r:
		return "out_of_range"
	if u.neili < ACUPOINT_COST:
		return "not_enough_neili"
	return ""

static func _v_item(b: Battle, u: BattleUnit, c: Dictionary, _tables: Dictionary) -> String:
	var it := BattleUnit.stack_of(u.battle_items(), str(c.get("item_uid", "")))
	if u.stack_left(it) <= 0:
		return "no_item"
	var tu := _ally(b, u, c)
	if tu == null:
		return "not_ally"
	if BattleGrid.manhattan(u.pos, tu.pos) > 1:
		return "out_of_range"
	return ""

## ---------------------------------------------------------------- 公式輔助

## 暗器射程：3 + floor(基本暗器 / 40) + 暗器武功 range_bonus，最多 6
static func hidden_range(u: BattleUnit, art_id: String, tables: Dictionary) -> int:
	var r := 3 + floori(u.skill("basic_hidden") / 40.0)
	if art_id != "":
		var arow := cmd_art(u, "HIDDEN", art_id, tables)
		var h: Variant = arow.get("hidden", null)
		if h is Dictionary:
			r += int(h.get("range_bonus", 0))
	return mini(HIDDEN_MAX_RANGE, r)

static func heal_cost(u: BattleUnit) -> int:
	return maxi(1, roundi(u.neili_max() * 0.10))

static func transfer_amount(u: BattleUnit, t: BattleUnit) -> int:
	return mini(floori(u.neili * 0.5), maxi(0, t.neili_max() - t.neili))

## 內功值 I = 內功等級 + 基本內功 / 2
static func inner_value(u: BattleUnit, arow: Dictionary) -> float:
	return u.skill(str(arow.get("id", ""))) + u.skill("basic_inner") / 2.0

static func _who(u: BattleUnit) -> Dictionary:
	return { "uid": u.uid, "name": u.unit_name(), "peer": u.peer }

static func _pair(u: BattleUnit, t: BattleUnit) -> Dictionary:
	return { "atk_uid": u.uid, "def_uid": t.uid, "atk": u.unit_name(), "def": t.unit_name(),
		"atk_peer": u.peer, "def_peer": t.peer }

## M3C_PLAN §7.2（WP-FX）命中事件的純表現欄位 cat：用了武功＝martial_arts.category；指令沒有指定武功時用指令本身的類別
## M3C_PLAN 缺漏：§7.2 只寫「用武功時＝category」，暗器／毒／醫／點穴不帶武功時照「最不意外」給指令類別（點穴＝STAB）
static func fx_cat(arow: Dictionary, dflt: String) -> String:
	var c := str(arow.get("category", "")) if not arow.is_empty() else ""
	return c if c != "" else dflt

static func _heal(t: BattleUnit, n: int) -> int:
	var g := mini(maxi(0, t.qi_max() - t.qi), maxi(0, n))
	t.qi += g
	return g

## ---------------------------------------------------------------- 結算（5.4）

static func execute(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary, rng: RandomNumberGenerator) -> Array:
	match str(c.cmd):
		"POISON": return _x_poison(b, u, c, tables, rng)
		"MEDIC": return _x_medic(b, u, c, tables)
		"HIDDEN": return _x_hidden(b, u, c, tables, rng)
		"FORMATION": return _x_formation(b, u, c, tables)
		"INNER": return _x_inner(b, u, c, tables, rng)
		"ACUPOINT": return _x_acupoint(b, u, c, tables, rng)
		"ITEM": return _x_item(b, u, c, tables)
	return []

static func _x_poison(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary, rng: RandomNumberGenerator) -> Array:
	var ev: Array = []
	var arow := cmd_art(u, "POISON", str(c.get("art", "")), tables)
	var m := cmd_move(u, arow)
	u.neili = maxi(0, u.neili - int(m.get("cost_inner", 0)))
	var tu := _enemy(b, u, c)
	if tu == null or arow.is_empty():
		return ev
	var a := u.skill(str(arow.id))
	var pz: Variant = arow.get("poison", null)
	var bonus := int(pz.get("level_bonus", 0)) if pz is Dictionary else 0
	var status_id := str(pz.get("status", "poison")) if pz is Dictionary else "poison"
	var P := u.skill("basic_poison") + a + bonus
	var R := tu.skill("basic_inner") + 2 * tu.attr("cal")
	var p := clampf(0.40 + (P - R) * 0.005, 0.10, 0.90)
	var art_sect := str(arow.get("sect_id", ""))
	if u.is_player() and art_sect != "" and u.sect() != art_sect:
		p *= NON_SECT_POISON_MULT
	var pair := _pair(u, tu)
	pair["cat"] = fx_cat(arow, "POISON")   # M3C_PLAN §7.2（WP-FX）純表現
	# 目標有 RESIST 門派技能：先擲觸發（5.4）
	if BattleStatus.try_proc(b, tu, "RESIST", tables):
		ev.append(BattleStatus.proc_event(b, tu, "RESIST", tables))
		ev.append(b.make_event("battle_poison_fail", pair))
		return ev
	if rng.randf() >= p:
		ev.append(b.make_event("battle_poison_fail", pair))
		return ev
	var dmg := maxi(1, roundi(float(m.get("power", 0)) * 0.5 * (1.0 + a / 60.0)))
	var lv := clampi(1 + floori(P / 25.0), 1, 10)
	tu.qi = maxi(1, tu.qi - dmg)
	tu.last_hitter = u.uid
	var okp := pair.duplicate()
	okp.merge({ "dmg": dmg, "level": lv, "def_qi": tu.qi }, true)
	ev.append(b.make_event("battle_poison_ok", okp))
	if tu.qi <= 1:
		ev.append_array(BattleRules.kill(b, tu, u))
		return ev
	ev.append_array(BattleStatus.apply(b, tu, status_id, tables, lv, false))
	return ev

static func _x_medic(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary) -> Array:
	var tu := _ally(b, u, c)
	if tu == null:
		return []
	var arow := medic_art(u, c, tables)
	var a_medic := u.skill(str(arow.get("id", ""))) if not arow.is_empty() else 0
	var md: Variant = arow.get("medic", null)
	var mult := float(md.get("heal_mult", 1.0)) if md is Dictionary else 1.0
	if u.sect() == "hengshan":
		mult *= HENGSHAN_MEDIC_MULT
	u.jing = maxi(0, u.jing - MEDIC_JING)
	u.shen = maxi(0, u.shen - MEDIC_SHEN)
	if not arow.is_empty():
		u.neili = maxi(0, u.neili - int(cmd_move(u, arow).get("cost_inner", 0)))   # 醫術武功的招式內力（M3a 審查 B3）
	var cures := medic_cures(b, u, tu, a_medic, tables)
	var heal := _heal(tu, roundi((20 + 2 * u.skill("basic_medic") + 3 * a_medic) * mult))
	var ev: Array = []
	var p := _pair(u, tu)
	p.merge({ "heal": heal, "cured": not cures.is_empty(), "def_qi": tu.qi, "cat": fx_cat(arow, "MEDIC") }, true)   # cat：M3C_PLAN §7.2（WP-FX）
	ev.append(b.make_event("battle_medic", p))
	# status_effects.cure_by 含 MEDIC 的狀態：流血止血；中毒限後期版（見 medic_cures；M3a 審查 B2）
	for sid in cures:
		ev.append_array(BattleStatus.remove(b, tu, str(sid), tables))
	return ev

static func _x_hidden(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary, rng: RandomNumberGenerator) -> Array:
	var ev: Array = []
	var it := BattleUnit.stack_of(u.hidden_items(), str(c.get("item_uid", "")))
	var tu := _enemy(b, u, c)
	if it.is_empty() or tu == null:
		return ev
	var iu := str(it.get("uid", ""))
	u.used_items[iu] = int(u.used_items.get(iu, 0)) + 1   # 命中與否都消耗【待考證】
	# 暗器武功：用已解鎖的最高招；招式內力命中與否都扣（M3a 審查 B3）
	var arow := cmd_art(u, "HIDDEN", str(c.get("art", "")), tables)
	var hm := cmd_move(u, arow)
	if not arow.is_empty():
		u.neili = maxi(0, u.neili - int(hm.get("cost_inner", 0)))
	var item_name := str(it.get("name", ""))
	var bh := u.skill("basic_hidden")
	var pair := _pair(u, tu)
	pair["item_name"] = item_name
	pair["item_uid"] = iu
	pair["left"] = u.stack_left(it)
	pair["cat"] = fx_cat(arow, "HIDDEN")   # M3C_PLAN §7.2（WP-FX）純表現
	if rng.randf() >= BattleFormulas.hit_chance(u, tu, bh):
		ev.append(b.make_event("battle_hidden_miss", pair))
		return ev
	var move_part := 0.0
	if not arow.is_empty():
		move_part = float(hm.get("power", 0)) * (1.0 + u.skill(str(arow.id)) / 60.0)
	var fr := BattleFormulas.float_range(u)
	var fm := rng.randf_range(fr.x, fr.y)
	var dp := BattleFormulas.defense_power(tu, "HIDDEN", tables) * BattleStatus.def_mult(tu, tables)
	var raw := (float(it.get("dmg", 0)) * (1.0 + bh / 50.0) + move_part - dp * 0.3) * fm
	var dmg := maxi(1, roundi(raw))
	tu.qi = maxi(1, tu.qi - dmg)
	tu.last_hitter = u.uid
	var part: String = BattleRules.PARTS[rng.randi_range(0, BattleRules.PARTS.size() - 1)]
	pair.merge({ "dmg": dmg, "part": part, "def_qi": tu.qi }, true)
	ev.append(b.make_event("battle_hidden_hit", pair))
	if tu.qi <= 1:
		ev.append_array(BattleRules.kill(b, tu, u))
		return ev
	# 暗器武功招式附帶的狀態（飛星術的中毒；中毒限後期版，見 move_status_ok；M3a 審查 B3）
	var hst := str(hm.get("status", ""))
	if not arow.is_empty() and move_status_ok(b, arow, hst):
		if rng.randf() < float(hm.get("status_chance", 0.0)):
			ev.append_array(BattleStatus.apply(b, tu, hst, tables))
	return ev

static func _x_inner(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary, rng: RandomNumberGenerator) -> Array:
	var ev: Array = []
	var arow := best_cmd_art(u, "INNER", tables)
	var I := inner_value(u, arow)
	var who := _who(u)
	match str(c.get("mode", "")):
		"HEAL":
			var n := heal_cost(u)
			u.neili = maxi(0, u.neili - n)
			var inr: Variant = arow.get("inner", null)
			var mult := float(inr.get("heal_mult", 1.0)) if inr is Dictionary else 1.0
			if u.sect() == "quanzhen":
				mult *= QUANZHEN_HEAL_MULT
			var heal := _heal(u, roundi(n * (1.0 + I / 100.0) * mult))
			who.merge({ "heal": heal, "neili": u.neili, "qi": u.qi }, true)
			ev.append(b.make_event("battle_inner_heal", who))
		"EXPEL":
			u.neili = maxi(0, u.neili - EXPEL_COST)
			var inr2: Variant = arow.get("inner", null)
			var em := float(inr2.get("expel_mult", 1.0)) if inr2 is Dictionary else 1.0
			var cut := maxi(1, roundi((1 + floori(I / 25.0)) * em))
			var left := maxi(0, u.status_level("poison") - cut)
			who["level_left"] = left
			ev.append(b.make_event("battle_inner_expel", who))
			if left <= 0:
				ev.append_array(BattleStatus.remove(b, u, "poison", tables))
			else:
				u.status_levels["poison"] = left
		"UNSEAL":
			u.neili = maxi(0, u.neili - UNSEAL_COST)
			var p := clampf(0.30 + I * 0.005 + (u.attr("cal") - 20) * 0.01, 0.10, 0.95)
			if rng.randf() < p:
				ev.append(b.make_event("battle_inner_unseal_ok", who))
				ev.append_array(BattleStatus.remove(b, u, "acupoint", tables))
			else:
				ev.append(b.make_event("battle_inner_unseal_fail", who))
		"TRANSFER":
			var tu := _ally(b, u, c)
			if tu == null or tu == u:
				return ev
			var n2 := transfer_amount(u, tu)
			u.neili -= n2
			tu.neili += n2
			var p2 := _pair(u, tu)
			p2["n"] = n2
			ev.append(b.make_event("battle_inner_transfer", p2))
	return ev

static func _x_acupoint(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary, rng: RandomNumberGenerator) -> Array:
	var ev: Array = []
	u.neili = maxi(0, u.neili - ACUPOINT_COST)
	var tu := _enemy(b, u, c)
	if tu == null:
		return ev
	var arow := {}
	if str(c.get("art", "")) != "":
		arow = cmd_art(u, "ACUPOINT", str(c.art), tables)
	if arow.is_empty():
		arow = best_cmd_art(u, "ACUPOINT", tables)
	var a := u.skill(str(arow.get("id", ""))) if not arow.is_empty() else 0
	var aac := u.skill("basic_stab") + a
	var d := tu.skill("basic_inner") + tu.skill("basic_dodge") / 2.0
	var p := clampf(0.30 + (aac - d) * 0.004, 0.05, 0.80)
	var pair := _pair(u, tu)
	pair["cat"] = fx_cat(arow, "STAB")   # M3C_PLAN §7.2（WP-FX）純表現：點穴沒有武功時算刺
	if rng.randf() < p:
		ev.append(b.make_event("battle_acupoint_ok", pair))
		ev.append_array(BattleStatus.apply(b, tu, "acupoint", tables))
	else:
		ev.append(b.make_event("battle_acupoint_fail", pair))
	return ev

static func _x_item(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary) -> Array:
	var ev: Array = []
	var it := BattleUnit.stack_of(u.battle_items(), str(c.get("item_uid", "")))
	var tu := _ally(b, u, c)
	if it.is_empty() or tu == null:
		return ev
	var iu := str(it.get("uid", ""))
	if not bool(it.get("keep_on_use", false)):   # M3b 審查 3：絕情丹用了不扣
		u.used_items[iu] = int(u.used_items.get(iu, 0)) + 1
	var pair := _pair(u, tu)
	pair["item_name"] = str(it.get("name", ""))
	pair["item_uid"] = iu
	var cured: Array = []
	var restores := false
	for e in it.get("effects", []):
		if not (e is Dictionary):
			continue
		match str(e.get("type", "")):
			"restore":
				restores = true
				var v := int(e.get("value", 0))
				match str(e.get("stat", "")):
					"qi":
						tu.qi = mini(tu.qi_max(), tu.qi + maxi(0, v))
					"neili":
						tu.neili = mini(tu.neili_max(), tu.neili + maxi(0, v))
					"jing":
						tu.jing = mini(tu.jing_max(), tu.jing + maxi(0, v))
					"shen":
						tu.shen = mini(tu.shen_max(), tu.shen + maxi(0, v))
			"cure":
				var sid := str(e.get("status", ""))
				if tu.statuses.has(sid) and tu.status_level(sid) <= int(e.get("max_level", 99)):
					cured.append(sid)
	pair.merge({ "qi": tu.qi, "neili": tu.neili }, true)
	ev.append(b.make_event("battle_item_use", pair))
	for sid in cured:
		ev.append_array(BattleStatus.remove(b, tu, str(sid), tables))
	if restores:
		ev.append_array(BattleStatus.on_medicine(b, tu, tables))
	return ev

## ---------------------------------------------------------------- 陣法（5.4）

## 站位的絕對格：己方在左側（side 0）時 y 往下為正；在右側（side 1）時左右鏡像
static func station_cell(u: BattleUnit, st: Variant) -> Vector2i:
	var dx := int(st[0]) if st is Array and st.size() > 0 else 0
	var dy := int(st[1]) if st is Array and st.size() > 1 else 0
	if u.side == 1:
		dx = -dx
	return u.pos + Vector2i(dx, dy)

## 可以參加此陣的單位：同側、同隊伍（party_id 非空且相同；施陣者本人一律算）、會此陣法、活著的玩家、性別相符
static func formation_candidates(b: Battle, u: BattleUnit, arow: Dictionary) -> Array:
	var f: Dictionary = arow.get("formation", {})
	var g := str(f.get("gender", ""))
	var aid := str(arow.get("id", ""))
	var out: Array = []
	for o in b.units:
		if not o.is_active() or not o.is_player() or o.side != u.side:
			continue
		if o != u and (u.party_id() == "" or o.party_id() != u.party_id()):
			continue
		if not o.cmd_arts("FORMATION").has(aid) or o.skill(aid) < 1:
			continue
		if g != "" and o.gender() != g:
			continue
		out.append(o)
	return out

## 每個站位格上的成員（第一格是施陣者）；有任何站位沒人 → []
static func formation_members(b: Battle, u: BattleUnit, arow: Dictionary) -> Array:
	var f: Dictionary = arow.get("formation", {})
	var cands := formation_candidates(b, u, arow)
	if not cands.has(u):
		return []
	var out: Array = []
	for st in f.get("stations", [[0, 0]]):
		var cell := station_cell(u, st)
		var who: BattleUnit = b.unit_at(cell) if BattleGrid.in_bounds(cell) else null
		if who == null or not cands.has(who) or out.has(who):
			return []
		out.append(who)
	if out.is_empty() or out[0] != u:
		return []
	return out

## 平均陣法等級 = 成員（陣法武功等級 + 基本陣法）/ 2 的平均【已證實：用平均等級】
static func avg_formation_level(members: Array, aid: String) -> float:
	if members.is_empty():
		return 0.0
	var s := 0.0
	for m in members:
		s += (m.skill(aid) + m.skill("basic_formation")) / 2.0
	return s / members.size()

static func _x_formation(b: Battle, u: BattleUnit, c: Dictionary, tables: Dictionary) -> Array:
	var ev: Array = []
	var arow := cmd_art(u, "FORMATION", str(c.get("art", "")), tables)
	var members := formation_members(b, u, arow)
	if members.is_empty():
		return ev
	# 成員原本在別的陣裡 → 先破那個陣
	for m in members:
		if not m.formation.is_empty():
			ev.append_array(break_formation(b, m, tables))
	var f: Dictionary = arow.formation
	var cost := int(first_move(arow).get("cost_inner", 0))
	var avg := avg_formation_level(members, str(arow.id))
	var per := float(f.get("per_avg_level", 0.0))
	var atk := 1.0 + float(f.get("atk_bonus", 0.0)) + per * avg
	var def := 1.0 + float(f.get("def_bonus", 0.0)) + per * avg
	var uids: Array = members.map(func(m): return m.uid)
	var names: Array = members.map(func(m): return m.unit_name())
	u.neili = maxi(0, u.neili - cost)
	for m in members:
		m.formation = { "art": str(arow.id), "art_name": str(arow.get("name", arow.id)), "members": uids.duplicate(),
			"atk": atk, "def": def, "cost": cost, "paid": m == u }
		var srow := BattleStatus.row("formation", tables)
		m.statuses["formation"] = maxi(1, int(srow.get("duration_actions", 6)))
		m.status_levels["formation"] = 1
	var p := _who(u)
	p.merge({ "art": str(arow.id), "art_name": str(arow.get("name", arow.id)), "members": names, "member_uids": uids,
		"atk_mult": atk, "def_mult": def }, true)
	ev.append(b.make_event("battle_formation_on", p))
	return ev

## 破陣：此單位所在陣法的全員解除 formation（battle_formation_off）
static func break_formation(b: Battle, u: BattleUnit, tables: Dictionary = {}) -> Array:
	if u.formation.is_empty():
		return []
	var f := u.formation
	for uid in f.get("members", []):
		var m: BattleUnit = b.unit(int(uid))
		if m == null or m.formation.is_empty() or str(m.formation.get("art", "")) != str(f.get("art", "")):
			continue
		m.formation = {}
		m.statuses.erase("formation")
		m.status_levels.erase("formation")
	u.formation = {}
	u.statuses.erase("formation")
	u.status_levels.erase("formation")
	return [b.make_event("battle_formation_off", { "uid": u.uid, "name": u.unit_name(), "peer": u.peer,
		"art": str(f.get("art", "")), "art_name": str(f.get("art_name", "")), "member_uids": f.get("members", []) })]

## 成員自己行動時補扣陣法內力（施陣者在施陣時已扣）；不夠 → 破陣（M3A_PLAN 缺漏：「退出陣法」後站位缺人，視同破陣）
static func formation_upkeep(b: Battle, u: BattleUnit, tables: Dictionary) -> Array:
	if u.formation.is_empty() or bool(u.formation.get("paid", false)):
		return []
	var cost := int(u.formation.get("cost", 0))
	if u.neili < cost:
		return break_formation(b, u, tables)
	u.neili -= cost
	u.formation["paid"] = true
	return []
