class_name ComboRules
extends RefCounted
## 合體技（M3D_PLAN §3.3；1.0B，R10）。純邏輯：不碰主機、場景樹、網路。
## - 戰鬥中：BattleRules.execute 的 ART 分支在一般招式結算之後呼叫 after_art()。
##   同一邊、角色 id 等於自己 spec.combo.partner_char 的夥伴，3 秒（戰鬥時間）內也出過同一組（combo.group）的合體武功
##   → 依默契擲骰 → 成功時對目標追加一擊 round((自己這招傷害 + 夥伴那招傷害) × COMBO_BONUS)，不反擊、不爆擊。
## - 修練條件（requirement combo_ready）：ready_reason() 依 ctx 的 combo 字典逐條判定（Requirements 的 WP-COMBAT 區塊呼叫）。
## 數字全部【設計提案】，只有「3 秒內」【已證實：官方 jy1-2-6-2】。

const COMBO_WINDOW_S := 3.0        # 【已證實】兩人 3 秒內都出同一組合體武功
const COMBO_BONUS := 0.4           # 【設計提案】合體一擊 = 兩招傷害和 × 0.4（M3D_PLAN 寫 0.5；balance_sim combo_suxin 校準：0.5 → +25.1% 超出 10–25% 帶）
const P_BASE := 0.20               # 【設計提案】成功率 = clamp(0.20 + 默契 × 0.0035, 0.20, 0.55)
const P_PER_MOQI := 0.0035         # M3d 審查：原 0.006／上限 0.80 → 默契 100 估 +33% 超出 10–25% 帶；balance_sim combo_suxin 量默契 50 與 100
const P_MAX := 0.55
const MOQI_MAX := 100
const PEIHE_MAX := 100

## 主機（ComboSystem）每 tick 填的「現在這位角色的合體 ctx」：char_id -> ctx 的 combo 字典（見 ready_reason）。
## M3D_PLAN 缺漏：師父列的 requires 由 Learning.check_master（凍結檔）判定，它不傳 ctx；
## 所以 Requirements 在 ctx 沒有 combo 鍵時改讀這張表（同一個主機程序內才有；core 不碰主機，只讀這個靜態字典）。
static var live_ctx: Dictionary = {}
## 只給 balance_sim：≥ 0 時取代 chance()（量「同一對夥伴、合體一擊不發生」的基準）
static var chance_override := -1.0

## 武功列的合體設定 { group, pair, moqi_min }；不是合體武功回 {}（舊資料的 combo: true 也不算）
static func combo_of(art_row: Dictionary) -> Dictionary:
	var c: Variant = art_row.get("combo", null)
	if c is Dictionary and str((c as Dictionary).get("group", "")) != "":
		return c
	return {}

static func chance(moqi: int) -> float:
	if chance_override >= 0.0:
		return chance_override
	return clampf(P_BASE + moqi * P_PER_MOQI, P_BASE, P_MAX)

## 合體武功「兩人同使」【已證實：官方 jy1-2-6-1「雙方都學合體武功」、jy1-2-6-2】：同一場、同一邊要有活著的合體夥伴，
## 而且夥伴**也會這門武功**、兩人配得上 pair 的兩邊（素心劍：一男一女）才能出招。
## M3d 審查（第 3 輪）：原本只看夥伴在不在場 → 學會的人取消默契、跟任何朋友重新建立，朋友只要站在場上就能一直用（等於單人武功）。
## 不是合體武功一律 true。
static func usable(b: Battle, u: BattleUnit, art_row: Dictionary) -> bool:
	if combo_of(art_row).is_empty():
		return true
	return partner_for_art(b, u, art_row) != null

## 同一邊、活著、是自己的合體夥伴、也會這門合體武功、兩人的性別配得上 combo.pair 的兩邊（沒寫性別的那一邊不限）
static func partner_for_art(b: Battle, u: BattleUnit, art_row: Dictionary) -> BattleUnit:
	var p := partner_unit(b, u)
	if p == null:
		return null
	var art_id := str(art_row.get("id", ""))
	if art_id != "" and int((p.spec.get("skills", {}) as Dictionary).get(art_id, 0)) < 1:
		return null
	var pair: Array = combo_of(art_row).get("pair", []) if combo_of(art_row).get("pair", []) is Array else []
	if pair.size() >= 2:
		var gu := str(u.spec.get("gender", ""))
		var gp := str(p.spec.get("gender", ""))
		if not (_gender_fits(pair[0], gu) and _gender_fits(pair[1], gp)) and not (_gender_fits(pair[1], gu) and _gender_fits(pair[0], gp)):
			return null
	return p

static func _gender_fits(side: Variant, g: String) -> bool:
	if not (side is Dictionary):
		return false
	var want := str(side.get("gender", ""))
	return want == "" or want == g

## 出合體武功之後（一般結算已完成）。dmg = 這一招實際打出的傷害（沒打中 0）；target_uid = 這招的目標單位。
## 回傳要追加的事件（可能是空的）。
static func after_art(b: Battle, u: BattleUnit, art_row: Dictionary, dmg: int, rng: RandomNumberGenerator,
		target_uid: int = 0) -> Array:
	var ev: Array = []
	var cb := combo_of(art_row)
	if cb.is_empty() or not u.is_active():
		return ev
	var group := str(cb.get("group", ""))
	var now := b.time_s()
	u.combo_mark = { "group": group, "t": now, "dmg": maxi(0, dmg), "def_uid": target_uid }
	var p := partner_for_art(b, u, art_row)
	if p == null or p.combo_mark.is_empty() or str(p.combo_mark.get("group", "")) != group:
		return ev
	if now - float(p.combo_mark.get("t", -999.0)) > COMBO_WINDOW_S + 0.0001:
		return ev
	var moqi := int(u.combo_spec().get("moqi", 0))
	if rng.randf() >= chance(moqi):
		p.combo_mark = {}   # 失敗：只清夥伴的；自己的留著給夥伴下一招機會
		return ev
	var tgt: BattleUnit = b.unit(target_uid) if target_uid > 0 else null
	if tgt == null or not tgt.is_active() or tgt.side == u.side:
		tgt = nearest_enemy(b, u)
	var total := int(u.combo_mark.get("dmg", 0)) + int(p.combo_mark.get("dmg", 0))
	u.combo_mark = {}
	p.combo_mark = {}
	if tgt == null:
		return ev
	var hit := maxi(1, roundi(total * COMBO_BONUS))
	tgt.qi = maxi(1, tgt.qi - hit)
	tgt.last_hitter = u.uid
	u.dmg_dealt += hit
	u.hits_landed += 1
	u.combo_hits += 1
	p.combo_hits += 1
	u.combo_with.append(p.char_id())
	p.combo_with.append(u.char_id())
	ev.append(b.make_event("battle_combo", {
		"a": u.unit_name(), "b": p.unit_name(), "a_uid": u.uid, "b_uid": p.uid, "a_peer": u.peer, "b_peer": p.peer,
		"art_name": str(art_row.get("name", "")), "group": group, "dmg": hit,
		"atk_uid": u.uid, "atk": u.unit_name(), "atk_peer": u.peer,
		"def_uid": tgt.uid, "def": tgt.unit_name(), "def_peer": tgt.peer, "def_qi": tgt.qi,
		"cat": str(art_row.get("category", "")) }))
	if tgt.qi <= 1:
		ev.append_array(BattleRules.kill(b, tgt, u))
	return ev

## 同一邊、活著、角色 id 等於自己 spec.combo.partner_char 的單位
static func partner_unit(b: Battle, u: BattleUnit) -> BattleUnit:
	var pc := str(u.combo_spec().get("partner_char", ""))
	if pc == "":
		return null
	for o in b.units:
		if o != u and o.side == u.side and o.is_active() and o.is_player() and o.char_id() == pc:
			return o
	return null

## 最近的敵人（曼哈頓距離，同距離比 uid）
static func nearest_enemy(b: Battle, u: BattleUnit) -> BattleUnit:
	var best: BattleUnit = null
	var bd := 1 << 30
	for o in b.units:
		if o.side == u.side or not o.is_active():
			continue
		var d := BattleGrid.manhattan(u.pos, o.pos)
		if d < bd or (d == bd and best != null and o.uid < best.uid):
			best = o
			bd = d
	return best

## ---------------------------------------------------------------- 修練條件（requirement combo_ready）

## me = { gender, skills: {art: lv}, sect_skill: int }；cc = ctx 的 combo 字典：
## { partner: char_id（空＝沒有夥伴）, partner_here: bool, same_party: bool, partner_gender, partner_skills: {art: lv},
##   partner_sect_skill: int, moqi: int }。
## 回傳 ""（成立）或原因碼 combo_need_partner／combo_need_party／combo_pair_mismatch／combo_moqi_low。
static func ready_reason(art_row: Dictionary, me: Dictionary, cc: Dictionary) -> String:
	var cb := combo_of(art_row)
	if cb.is_empty():
		return "combo_pair_mismatch"
	if cc.is_empty() or (cc.has("partner") and str(cc.get("partner", "")) == ""):
		return "combo_need_partner"
	if not bool(cc.get("partner_here", false)) or not bool(cc.get("same_party", false)):
		return "combo_need_party"
	var pair: Array = cb.get("pair", []) if cb.get("pair", []) is Array else []
	if pair.size() < 2:
		return "combo_pair_mismatch"
	var mine := { "gender": str(me.get("gender", "")), "skills": me.get("skills", {}), "sect_skill": int(me.get("sect_skill", 0)) }
	var his := { "gender": str(cc.get("partner_gender", "")), "skills": cc.get("partner_skills", {}),
		"sect_skill": int(cc.get("partner_sect_skill", 0)) }
	var ok := (side_ok(pair[0], mine) and side_ok(pair[1], his)) or (side_ok(pair[1], mine) and side_ok(pair[0], his))
	if not ok:
		return "combo_pair_mismatch"
	if int(cc.get("moqi", 0)) < int(cb.get("moqi_min", 0)):
		return "combo_moqi_low"
	return ""

## pair 的一邊 { gender, art, min, sect_skill_min } 對 who = { gender, skills, sect_skill }
static func side_ok(side: Variant, who: Dictionary) -> bool:
	if not (side is Dictionary):
		return false
	var g := str(side.get("gender", ""))
	if g != "" and g != str(who.get("gender", "")):
		return false
	var art := str(side.get("art", ""))
	var sk: Variant = who.get("skills", {})
	var lv := int((sk as Dictionary).get(art, 0)) if sk is Dictionary else 0
	if art != "" and lv < int(side.get("min", 1)):
		return false
	return int(who.get("sect_skill", 0)) >= int(side.get("sect_skill_min", 0))
