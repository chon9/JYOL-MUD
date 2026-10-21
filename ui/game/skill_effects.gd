class_name SkillEffects
extends RefCounted
## 武功說明（擁有者回報：學武功沒說明加什麼，例如基本劍法）。
## 每一門基本功／武功「學了有什麼用」，文字照戰鬥與角色公式寫（BattleFormulas、BattleCmds、BattleRules、DerivedStats、
## Character.effective_attrs、Learning）；公式改了這裡要跟著改（test_skill_effects 會對照常數）。
## lines() 給完整說明（武功窗選取時、滑鼠提示），summary() 給學武視窗每列底下的一行。

const WEAPON_WORD := {
	"basic_fist": "空手（拳、掌、指）", "basic_blade": "刀", "basic_sword": "劍", "basic_whip": "鞭",
	"basic_staff": "棍", "basic_spear": "槍", "basic_stab": "筆、刺類兵器",
}
const CATEGORY_WORD := {
	"FIST": "空手", "BLADE": "刀", "SWORD": "劍", "WHIP": "鞭", "STAFF": "棍", "SPEAR": "槍", "STAB": "筆、刺",
}
## 指令武功：類別 → 指令（Character.cmd_arts 依「類別」分，不是依欄位；點穴另看 acupoint: true）
const CMD_CATEGORY := { "POISON": "poison", "MEDIC": "medic", "HIDDEN": "hidden", "FORMATION": "formation", "INNER": "inner" }
## 規則 later_battle_cmds 關時沒有的東西（內、穴、輕、封穴、醫治中毒…；與 UiKeys.LATER_CMDS_TIP 同義）
const LATER := "（原作 2002 年才有，伺服器規則關閉時沒有）"

static func _row(tables: Dictionary, table: String, id: String) -> Dictionary:
	var t: Variant = tables.get(table, {})
	if t is Dictionary:
		var r: Variant = t.get(id, {})
		if r is Dictionary:
			return r
	return {}

static func _name(tables: Dictionary, id: String) -> String:
	for t in ["basic_skills", "martial_arts"]:
		var r := _row(tables, t, id)
		if not r.is_empty():
			return str(r.get("name", id))
	return id

## 學武視窗每列底下的一行（第一條效果）
static func summary(skill_id: String, tables: Dictionary) -> String:
	var ls := lines(skill_id, tables)
	return ls[0] if not ls.is_empty() else ""

## 完整說明（一條一行）
static func lines(skill_id: String, tables: Dictionary) -> PackedStringArray:
	var b := _row(tables, "basic_skills", skill_id)
	if not b.is_empty():
		return _basic(skill_id, tables)
	var a := _row(tables, "martial_arts", skill_id)
	if not a.is_empty():
		return _art(a, tables)
	return PackedStringArray()

static func text(skill_id: String, tables: Dictionary) -> String:
	return "\n".join(lines(skill_id, tables))

static func _basic(id: String, tables: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if WEAPON_WORD.has(id):
		var w: String = WEAPON_WORD[id]
		out.append("用%s打人的根本：攻擊力每 4 級 +1（普通攻擊與所有%s類武功都算）。" % [w, w])
		out.append("用%s普通攻擊時，命中以它的等級計算：每級 +0.3%%（對方的閃躲縱躍會抵消）。" % w)
		out.append("練到 %d 級：出招不論用幾成，都以 1.05 倍出力（未滿時要 10 成才有 1.05 倍）。" % BattleFormulas.MASTERY_LEVEL)
		if id == "basic_stab":
			out.append("10 級起戰鬥中可以用「穴」點穴（花內力 %d）%s：點中的機會看 基本刺術＋點穴武功，對方以 基本內功＋閃躲縱躍/2 抵抗；點中的人不能移動、逃跑。" % [BattleCmds.ACUPOINT_COST, LATER])
		out.append_array(_attr_lines(id, tables))
		return out
	match id:
		"basic_inner":
			out.append("內力上限 ＝ 基本內功 × %d；精上限每 10 級 +%d。" % [DerivedStats.NEILI_PER_INNER, DerivedStats.PER10_BONUS])
			out.append("有效內功 ＝ 基本內功 ＋ 最高內功心法等級/2：按「防」時防禦力 ×(1.5＋有效內功/400)；普通攻擊、出招（含反擊）打中時另加 0～有效內功/10 的內力傷害（暗器、下毒不算）。")
			out.append("1 級起可以「修煉內力」（預設熱鍵 F1，花精 %d）補內力；內力滿了再修煉會用光內力、氣上限 +%d（最多 基本內功×%d 次）。" % [Survival.MEDITATE_JING, Survival.CULTIVATE_QI, Survival.CULTIVATE_PER_INNER])
			out.append("施展內功回氣、回精、回神：花內力 %d，回復上限的 %d%%。" % [Survival.EXERT_NEILI, roundi(Survival.EXERT_PCT * 100)])
			out.append("抵抗毒（看 基本內功＋定力×2）、抵抗點穴（看 基本內功＋閃躲縱躍/2）；「內」指令的內功值也加 基本內功/2。")
			out.append("在「江湖謠言」頻道說話要基本內功 80 級（伺服器可改）。")
		"basic_parry":
			out.append("防禦力 ＋ 等級/3（被刀砍時效果少一成，被空手打時多一成）。")
		"basic_dodge":
			out.append("對方打你的命中率每級 −0.3%（和對方的武功等級相抵，暗器也算）。")
			out.append("戰鬥中按「閃」：到你下次行動前，對方命中再減 %d%%＋等級/10%%，最多減 %d%%；閃的時候不會反擊（有些伺服器規則沒有「閃」）。" % [roundi(BattleRules.DODGE_BASE * 100), roundi(BattleRules.DODGE_MAX * 100)])
			out.append("也幫忙抵抗點穴（算一半）。")
		"basic_body":
			out.append("時間棒累積得更快：每級 +0.03（基礎 4＋機敏×0.15）。")
			out.append("戰鬥中用「輕」原地脫身（花內力 %d）%s：成功率每級 +0.2%%（%d%%～%d%%）；任務戰、試煉、劫鏢的一方不能用。" % [BattleRules.QING_ESCAPE_COST, LATER, roundi(BattleRules.QING_ESCAPE_MIN), roundi(BattleRules.QING_ESCAPE_MAX)])
		"basic_formation":
			out.append("布陣的陣法等級 ＝ 每位成員（陣法武功＋基本陣法）/2 的平均，等級越高陣越強；要會陣法武功才能布陣。")
		"basic_poison":
			out.append("「毒」指令的毒力 ＝ 基本毒術＋毒術武功（另有加成），對方以 基本內功＋定力×2 抵抗；毒力越高越容易毒中、毒也越重（每 25 點一級，最多 10 級）。要會毒術武功才能用「毒」。")
			out.append("星宿弟子可以用小木鼎煉毒來練它（每次花精 %d）。" % ArtsRules.LIANDU_JING)
		"basic_medic":
			out.append("1 級起戰鬥中可以用「醫」（花精 %d、神 %d，治自己或身邊的隊友）：治療量 ＝ 20＋基本醫術×2＋醫術武功×3。" % [BattleCmds.MEDIC_JING, BattleCmds.MEDIC_SHEN])
			out.append("「醫」也能止血；基本醫術＋醫術武功 ≥ 毒的等級×10 時還能解毒%s。" % LATER)
		"basic_hidden":
			out.append("1 級起、身上有暗器時，戰鬥中可以用「暗」。")
			out.append("暗器傷害 ×(1＋等級/50)，命中以它的等級計算；射程 3＋等級/40 格（最多 %d）。" % BattleCmds.HIDDEN_MAX_RANGE)
		"basic_literacy":
			var cap := CharData.to_int((_row(tables, "basic_skills", id).get("attr_bonus_cap", {}) as Dictionary).get("wit", 10), 10)
			out.append("悟性每 10 級 +1（最多 +%d）：向師父學、自己練功時花的精更少、得到的熟練更多；悟性每 1 點精上限也 +%d。" % [cap, DerivedStats.JING_PER_WIT])
			out.append("神上限每 10 級 +%d。" % DerivedStats.PER10_BONUS)
			out.append("研讀秘笈（伺服器有開秘笈時）：秘笈能讀到的等級不超過讀書識字的等級，有些秘笈要先識字到一定程度。")
		"basic_trade":
			out.append("目前的版本還沒有效果（日後用在買賣價格）。")
	out.append_array(_attr_lines(id, tables))
	return out

## 伺服器選項 attr_from_basic_skills（預設關）開時的屬性成長（Character.effective_attrs；讀書識字的悟性固定生效，上面已寫）
static func _attr_lines(id: String, tables: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if id == "basic_literacy":
		return out
	var r := _row(tables, "basic_skills", id)
	var per10: Variant = r.get("attr_bonus_per10", {})
	var caps: Variant = r.get("attr_bonus_cap", {})
	if not (per10 is Dictionary):
		return out
	for attr in per10:
		var n := CharData.to_int(per10[attr])
		if n <= 0:
			continue
		var cap_txt := ""
		if caps is Dictionary and (caps as Dictionary).has(attr):
			cap_txt = "（最多 +%d）" % CharData.to_int(caps[attr])
		out.append("伺服器開了「基本武學加屬性」（預設關）時：每 10 級%s +%d%s。" % [str(UiKeys.ATTR_NAMES.get(str(attr), attr)), n, cap_txt])
	return out

static func _art(a: Dictionary, tables: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var cat := str(a.get("category", ""))
	var base := str(a.get("base_skill", ""))
	if CATEGORY_WORD.has(cat):
		out.append("%s類出招武功：戰鬥中按「武」出招，等級越高招式威力越大（×(1＋等級/60)），命中每級 +0.3%%。" % CATEGORY_WORD[cat])
		if cat != "FIST":
			out.append("手上要拿%s才能出招。" % CATEGORY_WORD[cat])
		if base != "":
			out.append("搭配%s：每 4 級攻擊 +1，%d 級起出招固定 1.05 倍出力。" % [_name(tables, base), BattleFormulas.MASTERY_LEVEL])
	elif cat == "INNER":
		out.append("內功心法：只算你等級最高的一門，有效內功 ＝ 基本內功＋它的等級/2；「防」時防禦更高，普通攻擊、出招打中時另加內力傷害。")
	elif cat == "LIGHTNESS":
		out.append("輕功（只算你等級最高的一門）：每 25 級移動多 1 格，時間棒每級 +0.02，「輕」脫身成功率每級 +0.4%。")
	var keys: Array = []
	if CMD_CATEGORY.has(cat):
		keys.append(CMD_CATEGORY[cat])
	if bool(a.get("acupoint", false)):
		keys.append("acupoint")
	if a.get("combo", null) is Dictionary and not (a.get("combo") as Dictionary).is_empty():
		keys.append("combo")
	for k in keys:
		out.append(_cmd_line(k, a))
	var moves: Array = a.get("moves", []) if a.get("moves", []) is Array else []
	if not moves.is_empty():
		var ms := PackedStringArray()
		for m in moves:
			if m is Dictionary:
				ms.append("%s（%d級）" % [str(m.get("name", "")), int(m.get("unlock_level", 1))])
		out.append("招式：" + "、".join(ms))
	var desc := str(a.get("desc", ""))
	if desc != "":
		out.append(desc)
	return out

## 指令武功的說明（a：武功列，讀 hidden.range_bonus、formation.party_size 等）
static func _cmd_line(k: String, a: Dictionary = {}) -> String:
	match k:
		"poison": return "可用在「毒」指令：毒力加上本武功等級，毒中時的傷害也隨等級變大（不是本門弟子用，成功率減半）。"
		"medic": return "可用在「醫」指令（治療量每級 +3）。"
		"hidden":
			var h: Variant = a.get("hidden", {})
			var rb: int = int((h as Dictionary).get("range_bonus", 0)) if h is Dictionary else 0
			return "可用在「暗」指令：另加招式威力%s。" % ("，射程 +%d 格" % rb if rb > 0 else "")
		"formation":
			var f: Variant = a.get("formation", {})
			var n: int = int((f as Dictionary).get("party_size", 1)) if f is Dictionary else 1
			var g: String = str((f as Dictionary).get("gender", "")) if f is Dictionary else ""
			return "可用在「陣」指令（布陣）：要 %d 位同隊伍、會這套陣法的%s站好位置。" % [n, "男性" if g == "M" else ("女性" if g == "F" else "人")]
		"acupoint": return "可用在「穴」指令（點穴）%s；一般出招打中時也有 5%%＋等級×0.1%% 的機會封住對方穴道。" % LATER
		"inner": return "可用在「內」指令%s（用你等級最高的內功心法）：內功值 ＝ 本武功等級＋基本內功/2。" % LATER
		"combo": return "合體武功：要和搭檔一起使用。"
	return ""
