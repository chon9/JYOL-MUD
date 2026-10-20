class_name Learning
extends RefCounted
## 學武、自修、生活技能學習（M1_PLAN 3.2.6、4.3–4.5、4.12）。

const LP_PER_TIME := 1
const SECT_NEILI_COST := 1
const SECT_SHEN_COST := 2
const LIFE_PROF_OK := 5
const LIFE_PROF_FAIL := 2
const ABSOLUTE_MAX_LEVEL := 250

## 4.5 悟性效率表（分段線性，四捨五入）
static func wit_cost(wit: int) -> Dictionary:
	var w := float(wit)
	var jing: float
	var prof: float
	if wit <= 21:
		jing = clampf(10.0 + (21.0 - w) * 5.0 / 9.0, 1.0, 15.0)
		prof = maxf(5.0, 11.0 - (21.0 - w) * 4.0 / 9.0)
	elif wit <= 30:
		jing = 10.0 - (w - 21.0) * 5.0 / 9.0
		prof = 11.0 + (w - 21.0) * 4.0 / 9.0
	elif wit <= 40:
		jing = 5.0 - (w - 30.0) * 0.3
		prof = 15.0 + (w - 30.0) * 0.5
	else:
		jing = maxf(1.0, 2.0 - (w - 40.0) * 0.1)
		prof = 20.0 + (w - 40.0) * 0.5
	return { "jing": roundi(jing), "prof": roundi(prof) }

## 武功（ART）本身的 requires；其他種類沒有
static func _skill_requires(skill_id: String, tables: Dictionary) -> Array:
	var r := CharData.row(tables, "martial_arts", skill_id)
	var req: Variant = r.get("requires", [])
	return req if typeof(req) == TYPE_ARRAY else []

static func _self_study_until(skill_id: String, tables: Dictionary) -> int:
	return CharData.to_int(CharData.row(tables, "martial_arts", skill_id).get("self_study_until", 0))

static func _is_new_art_blocked(ch: Character, skill_id: String, tables: Dictionary) -> bool:
	if SkillBook.kind_of(skill_id, tables) != SkillBook.KIND_ART or ch.skills.has(skill_id):
		return false
	return ch.skills.special_arts(tables).size() >= Character.SPECIAL_ARTS_MAX

## 師父可教到的等級（師父 cap、技能資料上限、門派技能上限取最小）
static func _master_cap(m: Dictionary, skill_id: String, tables: Dictionary) -> int:
	return mini(CharData.to_int(m.get("cap", 0)), SkillBook.max_level_of(skill_id, tables))

## 實戰上限（生活技能不受限制，4.12）
static func _xp_cap(ch: Character, skill_id: String, tables: Dictionary) -> int:
	if SkillBook.kind_of(skill_id, tables) == SkillBook.KIND_LIFE:
		return ABSOLUTE_MAX_LEVEL
	return DerivedStats.art_level_cap(ch.combat_xp)

## 門派技能上限（少林：佛法等級限制本門武功能練到幾級）。不受限制時回 ABSOLUTE_MAX_LEVEL。
## 只限本門的特殊武功（ART 且 sect_id == 角色門派），門派技能本身不受限。
## 公式 cap = 門派技能等級 + sect_art_cap_bonus（原作公式不明【設計提案】，見 sects.json src_note）
static func sect_skill_cap(ch: Character, skill_id: String, tables: Dictionary) -> int:
	if SkillBook.kind_of(skill_id, tables) != SkillBook.KIND_ART:
		return ABSOLUTE_MAX_LEVEL
	var sect_id := String(CharData.row(tables, "martial_arts", skill_id).get("sect_id", ""))
	if sect_id == "" or sect_id != ch.sect:
		return ABSOLUTE_MAX_LEVEL
	var srow := CharData.row(tables, "sects", sect_id)
	if not bool(srow.get("sect_skill_limits_arts", false)):
		return ABSOLUTE_MAX_LEVEL
	var sk := String(srow.get("sect_skill", ""))
	return ch.skills.level(sk) + CharData.to_int(srow.get("sect_art_cap_bonus", 0))

static func check_master(ch: Character, npc_id: String, skill_id: String, tables: Dictionary,
		options: Dictionary, rules: Dictionary) -> String:
	var m := CharData.master_row(tables, npc_id, skill_id)
	if m.is_empty() or SkillBook.kind_of(skill_id, tables) == "":
		return "not_taught"
	var req: Variant = m.get("requires", [])
	var r := Requirements.check(req if typeof(req) == TYPE_ARRAY else [], ch, tables, options, rules)
	if r != "":
		return r
	r = Requirements.check(_skill_requires(skill_id, tables), ch, tables, options, rules)
	if r != "":
		return r
	if _is_new_art_blocked(ch, skill_id, tables):
		return "cap_arts16"
	var lv := ch.skills.level(skill_id)
	var ssu := _self_study_until(skill_id, tables)
	if ssu > 0 and lv < ssu:
		return "need_self_study"
	if lv >= _master_cap(m, skill_id, tables):
		return "cap_master"
	if lv >= sect_skill_cap(ch, skill_id, tables):
		return "cap_sect_skill"
	if lv >= _xp_cap(ch, skill_id, tables):
		return "cap_xp"
	return ""

static func _result() -> Dictionary:
	return {
		"ok": false, "reason": "", "times_done": 0, "prof_gain": 0, "lp_cost": 0, "jing_cost": 0,
		"neili_cost": 0, "shen_cost": 0, "money_cost": 0, "level_before": 0, "level_after": 0,
		"stopped_reason": "",
	}

static func _finish(res: Dictionary, reason: String) -> Dictionary:
	if res["times_done"] >= 1:
		res["ok"] = true
		res["reason"] = ""
		res["stopped_reason"] = reason
	else:
		res["ok"] = false
		res["reason"] = reason
	return res

## 消點（向師父學）
static func learn(ch: Character, npc_id: String, skill_id: String, times: int, tables: Dictionary,
		options: Dictionary, rules: Dictionary) -> Dictionary:
	var res := _result()
	res["level_before"] = ch.skills.level(skill_id)
	res["level_after"] = res["level_before"]
	var first := check_master(ch, npc_id, skill_id, tables, options, rules)
	if first != "":
		return _finish(res, first)
	var m := CharData.master_row(tables, npc_id, skill_id)
	var kind := SkillBook.kind_of(skill_id, tables)
	var price := CharData.to_int(m.get("price", 0))
	var neili_cost := 0
	var shen_cost := 0
	if kind == SkillBook.KIND_SECT:
		# 消點門派技能的額外消耗：sects.sect_skill_train_cost（各派修練方式，研究）。
		# sect_skill_cost 是戰鬥觸發的消耗（官方表「會耗精與內力」），不是學習消耗；只有舊資料沒寫 train_cost 時才退回用它（M1 相容）。
		var srow := CharData.sect_of_skill(tables, skill_id)
		var cost: Variant = srow.get("sect_skill_train_cost", srow.get("sect_skill_cost", []))
		if typeof(cost) == TYPE_ARRAY:
			if cost.has("neili"):
				neili_cost = SECT_NEILI_COST
			if cost.has("shen"):
				shen_cost = SECT_SHEN_COST
	var cap: int = mini(mini(_master_cap(m, skill_id, tables), _xp_cap(ch, skill_id, tables)),
		sect_skill_cap(ch, skill_id, tables))
	var stop := ""
	for i in max(1, times):
		var lv := ch.skills.level(skill_id)
		if lv >= _master_cap(m, skill_id, tables):
			stop = "cap_master"
			break
		if lv >= sect_skill_cap(ch, skill_id, tables):
			stop = "cap_sect_skill"
			break
		if lv >= _xp_cap(ch, skill_id, tables):
			stop = "cap_xp"
			break
		var wc := wit_cost(int(ch.effective_attrs(tables, options)["wit"]))
		if ch.learn_points < LP_PER_TIME:
			stop = "not_enough_lp"
			break
		if int(ch.vitals["jing"]) < wc["jing"]:
			stop = "not_enough_jing"
			break
		if int(ch.vitals["neili"]) < neili_cost:
			stop = "not_enough_neili"
			break
		if int(ch.vitals["shen"]) < shen_cost:
			stop = "not_enough_shen"
			break
		if ch.money < price:
			stop = "not_enough_money"
			break
		ch.learn_points -= LP_PER_TIME
		ch.vitals["jing"] = int(ch.vitals["jing"]) - wc["jing"]
		ch.vitals["neili"] = int(ch.vitals["neili"]) - neili_cost
		ch.vitals["shen"] = int(ch.vitals["shen"]) - shen_cost
		ch.money -= price
		ch.skills.add_prof(skill_id, wc["prof"], tables, cap)
		res["times_done"] += 1
		res["prof_gain"] += wc["prof"]
		res["lp_cost"] += LP_PER_TIME
		res["jing_cost"] += wc["jing"]
		res["neili_cost"] += neili_cost
		res["shen_cost"] += shen_cost
		res["money_cost"] += price
	res["level_after"] = ch.skills.level(skill_id)
	return _finish(res, stop)

## 自修上限（4.4）
static func self_study_cap(ch: Character, skill_id: String, tables: Dictionary, rules: Dictionary) -> int:
	var base := -1
	for m in CharData.masters_for_skill(tables, skill_id):
		base = max(base, CharData.to_int(m.get("cap", 0)))
	# 武功列自己的自修上限：沒有師父時就是它；有師父時取較大者（M3a 審查 A3：峨嵋滅絕只教 1 級、其餘自修）
	base = max(base, CharData.to_int(CharData.row(tables, "martial_arts", skill_id).get("self_study_cap", 0)))
	# M1_PLAN 缺漏：HJ_1_5X 的文字有兩種讀法；這裡解讀為「上限放寬為 1.5 倍師父上限，但不超過 250」
	if String(rules.get("self_study_cap", "NONE")) == "HJ_1_5X":
		base = mini(ABSOLUTE_MAX_LEVEL, floori(1.5 * base))
	base = max(base, _self_study_until(skill_id, tables))
	return mini(base, SkillBook.max_level_of(skill_id, tables))

static func self_study(ch: Character, skill_id: String, times: int, tables: Dictionary,
		options: Dictionary, rules: Dictionary) -> Dictionary:
	var res := _result()
	res["level_before"] = ch.skills.level(skill_id)
	res["level_after"] = res["level_before"]
	var kind := SkillBook.kind_of(skill_id, tables)
	# 生活技能只能靠 work 練（4.12）
	if kind == "" or kind == SkillBook.KIND_LIFE:
		return _finish(res, "not_known")
	if not ch.skills.has(skill_id) and _self_study_until(skill_id, tables) <= 0:
		return _finish(res, "not_known")
	var r := Requirements.check(_skill_requires(skill_id, tables), ch, tables, options, rules)
	if r != "":
		return _finish(res, r)
	if _is_new_art_blocked(ch, skill_id, tables):
		return _finish(res, "cap_arts16")
	var ss_cap := self_study_cap(ch, skill_id, tables, rules)
	var sect_cap := sect_skill_cap(ch, skill_id, tables)
	var stop := ""
	for i in max(1, times):
		var lv := ch.skills.level(skill_id)
		var xp_cap := _xp_cap(ch, skill_id, tables)
		if lv >= xp_cap:
			stop = "cap_xp"
			break
		if lv >= ss_cap:
			stop = "cap_master"
			break
		if lv >= sect_cap:
			stop = "cap_sect_skill"
			break
		var eff := ch.effective_attrs(tables, options)
		var wc := wit_cost(int(eff["wit"]))
		var gain := floori(int(eff["wit"]) / 4.0)
		if ch.learn_points < LP_PER_TIME:
			stop = "not_enough_lp"
			break
		if int(ch.vitals["jing"]) < wc["jing"]:
			stop = "not_enough_jing"
			break
		ch.learn_points -= LP_PER_TIME
		ch.vitals["jing"] = int(ch.vitals["jing"]) - wc["jing"]
		ch.skills.add_prof(skill_id, gain, tables, mini(mini(xp_cap, ss_cap), sect_cap))
		res["times_done"] += 1
		res["prof_gain"] += gain
		res["lp_cost"] += LP_PER_TIME
		res["jing_cost"] += wc["jing"]
	res["level_after"] = ch.skills.level(skill_id)
	return _finish(res, stop)

## 生活技能 0 → 1 級（4.12）
static func learn_life(ch: Character, npc_id: String, skill_id: String, tables: Dictionary) -> Dictionary:
	var out := { "ok": false, "reason": "", "money_cost": 0, "tool_item": "" }
	var m := CharData.master_row(tables, npc_id, skill_id)
	if m.is_empty() or SkillBook.kind_of(skill_id, tables) != SkillBook.KIND_LIFE:
		out["reason"] = "not_taught"
		return out
	var req: Variant = m.get("requires", [])
	var r := Requirements.check(req if typeof(req) == TYPE_ARRAY else [], ch, tables, {}, {})
	if r != "":
		out["reason"] = r
		return out
	if ch.skills.has(skill_id):
		out["reason"] = "already_known"
		return out
	var price := CharData.to_int(m.get("price", 0))
	if ch.money < price:
		out["reason"] = "not_enough_money"
		return out
	ch.money -= price
	ch.skills.set_level(skill_id, 1, tables)
	var tool := String(m.get("tool", ""))
	if tool != "" and ch.inventory.count(tool) > 0:
		tool = ""
	out["ok"] = true
	out["money_cost"] = price
	out["tool_item"] = tool
	return out

## 生活技能成功率（4.12）
static func life_success_chance(level: int) -> float:
	return minf(0.95, 0.5 + level * 0.005)

## 生活技能練習：成功 +5、失敗 +2（4.12）；回傳 { before, after, prof(累計), gain }
static func practice_life(ch: Character, skill_id: String, success: bool, tables: Dictionary) -> Dictionary:
	var gain := LIFE_PROF_OK if success else LIFE_PROF_FAIL
	var r := ch.skills.add_prof(skill_id, gain, tables, SkillBook.max_level_of(skill_id, tables))
	r["gain"] = gain
	return r

## 3.8 teach_list.entries
static func teach_entries(ch: Character, npc_id: String, tables: Dictionary, options: Dictionary,
		rules: Dictionary) -> Array:
	var out: Array = []
	for m in CharData.masters_of_npc(tables, npc_id):
		var sid := String(m.get("skill_id", ""))
		var kind := SkillBook.kind_of(sid, tables)
		var reason := ""
		if kind == SkillBook.KIND_LIFE:
			if ch.skills.has(sid):
				reason = "already_known"
			else:
				var req: Variant = m.get("requires", [])
				reason = Requirements.check(req if typeof(req) == TYPE_ARRAY else [], ch, tables, options, rules)
		else:
			reason = check_master(ch, npc_id, sid, tables, options, rules)
		out.append({
			"skill": sid, "name": SkillBook.skill_name(sid, tables), "kind": kind,
			"cap": CharData.to_int(m.get("cap", 0)), "level": ch.skills.level(sid),
			"ok": reason == "", "reason": reason, "price": CharData.to_int(m.get("price", 0)),
		})
	return out

# ---------------------------------------------------------------- 秘笈（M3C_PLAN §6.4；WP-LOOT）
## 【設計提案・非原作】秘笈系統是 2002-08-21 的；本作依擁有者要求提前。讀書識字是門檻（literacy_min）也是上限。
## item_row.manual = { skill, cap, literacy_min, prof, jing, shen, requires }；秘笈不消耗。
## cap_extra：主機給的一般上限（GameHost.skill_cap；< 0 = 不限）。
## 回傳 _result() 形狀＋ { skill, cap_eff, shen_cost }；原因碼依序：not_manual → manual_illiterate → req_* → manual_cap
## → not_enough_jing／not_enough_shen → not_enough_lp（讀了至少一次後中斷的原因放在 stopped_reason）。
## M3c 審查：每讀一次也扣學點 LP_PER_TIME（與自修、拜師同一個價）——研究：武功進步靠實戰＋學點；
## 秘笈不消耗又能存、賣、寄，不扣學點的話一本書能讓整隊人跳過學點
## M3c 第二輪審查：原本每次熟練 +6、精 15＋神 15，比自修（悟性 21：+5、精 10）慢 0.4 倍——珍品秘笈比什麼都不讀還差。
## 改成每次 +10、精 10＋神 10：精神花費每點熟練與自修相同、學點省一半（balance_sim manual_speed 0.9–2 倍）【設計提案】
const MANUAL_DEFAULT_PROF := 10
const MANUAL_DEFAULT_JING := 10
const MANUAL_DEFAULT_SHEN := 10

static func manual_of(item_row: Dictionary) -> Dictionary:
	var m: Variant = item_row.get("manual", {})
	return m if typeof(m) == TYPE_DICTIONARY and String((m as Dictionary).get("skill", "")) != "" else {}

## 這本秘笈對這個角色最多讀到幾級：min(cap, 讀書識字等級, cap_extra)
static func manual_cap(ch: Character, item_row: Dictionary, cap_extra: int) -> int:
	var m := manual_of(item_row)
	if m.is_empty():
		return 0
	var cap := mini(CharData.to_int(m.get("cap", 0)), ch.skills.level("basic_literacy"))
	if cap_extra >= 0:
		cap = mini(cap, cap_extra)
	return maxi(0, cap)

static func read_manual(ch: Character, item_row: Dictionary, times: int, tables: Dictionary, cap_extra: int,
		options: Dictionary = {}, rules: Dictionary = {}) -> Dictionary:
	var res := _result()
	var m := manual_of(item_row)
	var skill := String(m.get("skill", ""))
	res["skill"] = skill
	res["cap_eff"] = 0
	res["level_before"] = ch.skills.level(skill) if skill != "" else 0
	res["level_after"] = res["level_before"]
	if m.is_empty() or SkillBook.kind_of(skill, tables) == "":
		return _finish(res, "not_manual")
	if ch.skills.level("basic_literacy") < CharData.to_int(m.get("literacy_min", 0)):
		return _finish(res, "manual_illiterate")
	var req: Variant = m.get("requires", [])
	var r := Requirements.check(req if typeof(req) == TYPE_ARRAY else [], ch, tables, options, rules)
	if r != "":
		return _finish(res, r)
	var cap_eff := manual_cap(ch, item_row, cap_extra)
	res["cap_eff"] = cap_eff
	var prof := maxi(1, CharData.to_int(m.get("prof", MANUAL_DEFAULT_PROF), MANUAL_DEFAULT_PROF))
	var jing := maxi(0, CharData.to_int(m.get("jing", MANUAL_DEFAULT_JING), MANUAL_DEFAULT_JING))
	var shen := maxi(0, CharData.to_int(m.get("shen", MANUAL_DEFAULT_SHEN), MANUAL_DEFAULT_SHEN))
	var stop := ""
	for i in clampi(times, 1, 10):
		if ch.skills.level(skill) >= cap_eff:
			stop = "manual_cap"
			break
		if int(ch.vitals.get("jing", 0)) < jing:
			stop = "not_enough_jing"
			break
		if int(ch.vitals.get("shen", 0)) < shen:
			stop = "not_enough_shen"
			break
		if ch.learn_points < LP_PER_TIME:
			stop = "not_enough_lp"
			break
		ch.learn_points -= LP_PER_TIME
		res["lp_cost"] += LP_PER_TIME
		ch.vitals["jing"] = int(ch.vitals["jing"]) - jing
		ch.vitals["shen"] = int(ch.vitals["shen"]) - shen
		ch.skills.add_prof(skill, prof, tables, cap_eff)
		res["times_done"] += 1
		res["prof_gain"] += prof
		res["jing_cost"] += jing
		res["shen_cost"] += shen
	res["level_after"] = ch.skills.level(skill)
	return _finish(res, stop)
