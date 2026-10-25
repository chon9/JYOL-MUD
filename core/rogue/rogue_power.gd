class_name RoguePower
extends RefCounted
## 江湖試煉的戰力分數與對手縮放（ROGUE_PLAN §3.6、§3.7.3）【設計提案・非原作】。
## 純函式：只讀 BattleFormulas（凍結）與 BattleAI.usable_moves，不建立戰鬥。
## P = √(輸出 × 存活)：輸出 = 時間棒速度 × 對參考靶子的期望傷害；存活 = 氣上限 ÷（參考攻擊者的期望傷害 × 時間棒速度）。

## 參考靶子／參考攻擊者：七項屬性 18、氣 300、閃躲與拆招 20、護甲 10、空手
const REF_SPEC := {
	"kind": "MONSTER", "ref": "rg_ref", "name": "參考", "side": 1, "peer": 0, "ai": "melee_basic",
	"attrs": { "str": 18, "guts": 18, "wit": 18, "luck": 18, "cal": 18, "agi": 18, "con": 18 },
	"qi": 300, "qi_max": 300, "neili": 0, "neili_max": 0, "jing": 100, "jing_max": 100, "shen": 100, "shen_max": 100,
	"skills": { "basic_dodge": 20, "basic_parry": 20 }, "arts": [],
	"weapon": { "uid": "", "item_id": "", "weapon_type": "FIST", "atk": 0, "name": "" },
	"armor_power": 10, "effective_inner": 0, "lightness": 0, "killing_intent": 0, "carry_ratio": 0.0,
}
const REF_ATK := 60.0
## 參考新角色（§3.7.1 的 P0）：七項 17、木刀、布衣、沒有武功
const REF_NEW_ATTR := 17
const REF_NEW_WEAPON := "w_mudao"
const REF_NEW_ARMOR := "a_bupao"
const SCALE_ITERS := 12
const SCALE_TOL := 0.03

## 對手參考（ROGUE_PLAN 缺漏的補充，見檔頭）：空字典＝固定的 REF_SPEC／REF_ATK（§3.6 原式）。
## 主機開戰與 balance_sim 在「這一場」設成玩家自己的戰鬥規格：輸出用「對玩家」的期望傷害、存活用「玩家打我」的期望傷害，
## P² 的比值就是「誰先把誰打倒」的速度比（P_玩家 = √氣上限）。固定的參考靶子對弱怪（護甲高、攻擊低）與強者都會失真
## （max(1, …) 把弱攻擊壓成 1、把高防禦的挨打壓成 1），balance_sim rogue_power_fair 量得到。用完一定要 clear_reference()。
static var _ref: Dictionary = {}

static func set_reference(spec: Dictionary) -> void:
	_ref = spec.duplicate(true) if not spec.is_empty() else {}

static func clear_reference() -> void:
	_ref = {}

## 目前的參考（副本；暫時換參考的呼叫端用它還原）
static func get_reference() -> Dictionary:
	return _ref.duplicate(true)

static func has_reference() -> bool:
	return not _ref.is_empty()

static func unit_power(spec: Dictionary, tables: Dictionary) -> float:
	if spec.is_empty():
		return 0.0
	var u := BattleUnit.new(1, spec)
	u.neili = u.neili_max()   # 以滿內力估最佳招式
	u.statuses = {}
	var ref := BattleUnit.new(2, _ref if not _ref.is_empty() else REF_SPEC)
	ref.neili = ref.neili_max()
	ref.statuses = {}
	var off := BattleFormulas.atb_gain(u, tables) * best_damage(u, ref, tables)
	var dmg_in := 0.0
	if _ref.is_empty():
		dmg_in = maxf(1.0, REF_ATK - BattleFormulas.DEF_MULT_DAMAGE * BattleFormulas.defense_power(u, "FIST", tables)) 			* BattleFormulas.hit_chance(ref, u, 30)
	else:
		dmg_in = best_damage(ref, u, tables)
	var life := float(u.qi_max()) / maxf(0.001, dmg_in * BattleFormulas.atb_gain(ref, tables))
	return sqrt(maxf(0.0, off * life))

## att 打 def 一次的期望傷害（普通攻擊與每個可用招式取最大）：max(1, 攻 − 0.6 防) × 命中 × 爆擊期望 + 內功加成/2
static func best_damage(att: BattleUnit, def: BattleUnit, tables: Dictionary) -> float:
	var crit_f := 1.0 + BattleFormulas.crit_chance(att) * (BattleFormulas.crit_mult(att) - 1.0)
	var inner_b := BattleFormulas.inner_bonus_max(att) / 2.0
	var cat0 := att.weapon_type()
	var base0 := BattleFormulas.base_level(att, BattleFormulas.basic_for_category(cat0), "", tables)
	var best := _dmg(BattleFormulas.attack_power(att, {}, {}, 0, tables), BattleFormulas.defense_power(def, cat0, tables),
		BattleFormulas.hit_chance(att, def, base0), crit_f, inner_b)
	for m in BattleAI.usable_moves(att, tables):
		var row := BattleRules.art_row_for(att, str(m.art), tables)
		if row.is_empty():
			continue
		var cat := BattleFormulas.attack_category(att, row)
		var atk := BattleFormulas.attack_power(att, row, m.move, BattleAI.AI_TENTHS, tables)
		best = maxf(best, _dmg(atk, BattleFormulas.defense_power(def, cat, tables),
			BattleFormulas.hit_chance(att, def, att.skill(str(m.art))), crit_f, inner_b))
	return best

static func _dmg(atk: float, def: float, hit: float, crit_f: float, inner_b: float) -> float:
	return maxf(1.0, atk - BattleFormulas.DEF_MULT_DAMAGE * def) * hit * crit_f + inner_b

static func side_power(specs: Array, tables: Dictionary) -> float:
	var total := 0.0
	for s in specs:
		if s is Dictionary:
			total += unit_power(s, tables)
	return total

## §3.7.3：氣、內力 × s；力、根、身 + round(6(s−1))（夾 5..60）；技能 × (0.6+0.4s)（至少 1）；護甲、兵器攻擊 × (0.7+0.3s)
static func scale_spec(spec: Dictionary, s: float) -> Dictionary:
	var out: Dictionary = spec.duplicate(true)
	for k in ["qi", "qi_max", "neili", "neili_max"]:
		if out.has(k):
			out[k] = maxi(1 if k.begins_with("qi") else 0, roundi(float(out[k]) * s))
	var attrs: Dictionary = out.get("attrs", {})
	var da := roundi(6.0 * (s - 1.0))
	for a in ["str", "con", "agi"]:
		if attrs.has(a):
			attrs[a] = clampi(int(attrs[a]) + da, 5, 60)
	out["attrs"] = attrs
	var sk: Dictionary = out.get("skills", {})
	var sm := 0.6 + 0.4 * s
	for k in sk.keys():
		sk[k] = maxi(1, roundi(float(sk[k]) * sm))
	out["skills"] = sk
	var em := 0.7 + 0.3 * s
	out["armor_power"] = roundi(float(out.get("armor_power", 0)) * em)
	if out.get("weapon") is Dictionary:
		var w: Dictionary = out["weapon"]
		w["atk"] = roundi(float(w.get("atk", 0)) * em)
	if out.has("effective_inner"):
		out["effective_inner"] = roundi(float(out["effective_inner"]) * sm)
	out["rg_scale"] = s
	return out

## 二分搜尋（12 次）讓 unit_power 落在目標 ±3%；回 { spec, s, power, ok }。到不了（s 夾在邊界）時 ok = false
static func scale_to(spec: Dictionary, target: float, tables: Dictionary, s_min := 0.5, s_max := 2.5) -> Dictionary:
	var lo := s_min
	var hi := s_max
	var p_lo := unit_power(scale_spec(spec, lo), tables)
	var p_hi := unit_power(scale_spec(spec, hi), tables)
	if target <= p_lo:
		var sp := scale_spec(spec, lo)
		return { "spec": sp, "s": lo, "power": p_lo, "ok": absf(p_lo - target) <= target * SCALE_TOL }
	if target >= p_hi:
		var sp2 := scale_spec(spec, hi)
		return { "spec": sp2, "s": hi, "power": p_hi, "ok": absf(p_hi - target) <= target * SCALE_TOL }
	var best_s := lo
	var best_p := p_lo
	var best_err := absf(p_lo - target)
	for i in SCALE_ITERS:
		var mid := (lo + hi) / 2.0
		var p := unit_power(scale_spec(spec, mid), tables)
		var err := absf(p - target)
		if err < best_err:
			best_err = err
			best_s = mid
			best_p = p
		if p < target:
			lo = mid
		else:
			hi = mid
	return { "spec": scale_spec(spec, best_s), "s": best_s, "power": best_p, "ok": best_err <= target * SCALE_TOL }

## 參考新角色的規格（§3.7.1）：七項 17、木刀、布衣、沒有武功；氣 60＋根骨×6。
## renown_pts（0.7.x 試煉審查【設計提案】）：江湖名聲——永久點數的一部分平均加到臂力、根骨、機敏
const RENOWN_ATTRS := ["str", "con", "agi"]
static func reference_spec(tables: Dictionary, renown_pts: int = 0) -> Dictionary:
	var attrs := {}
	for a in Character.ATTR_IDS:
		attrs[a] = REF_NEW_ATTR
	for i in maxi(0, renown_pts):
		var k: String = RENOWN_ATTRS[i % RENOWN_ATTRS.size()]
		attrs[k] = int(attrs[k]) + 1
	var w: Dictionary = tables.get("items", {}).get(REF_NEW_WEAPON, {})
	var arm: Dictionary = tables.get("items", {}).get(REF_NEW_ARMOR, {})
	var qi := DerivedStats.QI_BASE + int(attrs["con"]) * DerivedStats.QI_PER_CON
	return {
		"kind": "PLAYER", "ref": "rg_ref_new", "name": "參考新角色", "side": 0, "peer": 0, "ai": "melee_basic",
		"attrs": attrs, "qi": qi, "qi_max": qi, "neili": 0, "neili_max": 0, "jing": 84, "jing_max": 84, "shen": 84, "shen_max": 84,
		"skills": {}, "arts": [],
		"weapon": { "uid": "rg_ref_w", "item_id": REF_NEW_WEAPON, "weapon_type": str(w.get("weapon_type", "BLADE")),
			"atk": int(w.get("atk", 4)), "name": str(w.get("name", "")) },
		"armor_power": int(arm.get("def", 2)), "effective_inner": 0, "lightness": 0, "killing_intent": 0, "carry_ratio": 0.1,
	}

static func reference_power(tables: Dictionary, renown_pts: int = 0) -> float:
	return unit_power(reference_spec(tables, renown_pts), tables)
