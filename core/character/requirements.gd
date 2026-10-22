class_name Requirements
extends RefCounted
## 條件判定（M1_PLAN 3.2.8、3.11.1）。

const GENDER_NAMES := { "M": "男性", "F": "女性" }

## ctx（主機端才有，M3A_PLAN 3.7）：{ "party_size": int（同隊、同房間、不在戰鬥中的隊員數，含自己）, "shichen": String（現在的時辰） }。
## 純角色判定（沒有 ctx）時 party_size_min 視為不成立、hour_in 視為成立。
const CTX_PARTY_SIZE := "party_size"
const CTX_SHICHEN := "shichen"

## 依序判定，第一個不符合的回 "req_<type>"；全部符合回 ""
static func check(conds: Array, ch: Character, tables: Dictionary, options: Dictionary, rules: Dictionary,
		ctx: Dictionary = {}) -> String:
	var eff: Dictionary = {}
	for c in conds:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var t := String(c.get("type", ""))
		if (t == "attr_min" or t == "attr_max") and eff.is_empty():
			eff = ch.effective_attrs(tables, options)
		if not _ok(t, c, ch, tables, options, rules, eff, ctx):
			return "req_" + t
	return ""

## 全部成立（ok() 給 any_of 與門規判定用）
static func ok(conds: Array, ch: Character, tables: Dictionary, options: Dictionary, rules: Dictionary,
		ctx: Dictionary = {}) -> bool:
	return check(conds, ch, tables, options, rules, ctx) == ""

static func _ok(t: String, c: Dictionary, ch: Character, tables: Dictionary, options: Dictionary,
		rules: Dictionary, eff: Dictionary, ctx: Dictionary = {}) -> bool:
	var value: Variant = c.get("value", 0)
	match t:
		# ---- M3A_PLAN 3.7 ----
		"has_item":
			return ch.inventory.count(String(c.get("item", ""))) >= maxi(1, CharData.to_int(c.get("n", 1), 1))
		"any_of":
			var opts: Variant = c.get("options", [])
			if typeof(opts) != TYPE_ARRAY:
				return false
			for group in opts:
				if typeof(group) == TYPE_ARRAY and check(group, ch, tables, options, rules, ctx) == "":
					return true
			return false
		"enemy_of":
			return ch.sect_enemies.has(String(c.get("sect", "")))
		"not_flag":
			return ch.flags.get(String(c.get("flag", "")), false) != true
		"pk_min":
			return ch.pk_value() >= CharData.to_int(value)
		"killing_intent_min":
			return ch.killing_intent >= CharData.to_int(value)
		"sect_master":
			return ch.sect_master != "" and ch.sect_master == String(c.get("npc", ""))
		"party_size_min":
			if not ctx.has(CTX_PARTY_SIZE):
				return false
			return CharData.to_int(ctx[CTX_PARTY_SIZE]) >= CharData.to_int(value)
		"hour_in":
			if not ctx.has(CTX_SHICHEN):
				return true
			var hours: Variant = c.get("hours", [])
			return typeof(hours) == TYPE_ARRAY and hours.has(String(ctx[CTX_SHICHEN]))
		"morality_min":
			return ch.morality >= CharData.to_int(value)
		"morality_max":
			return ch.morality <= CharData.to_int(value)
		"sect":
			return ch.sect != "" and ch.sect == String(c.get("sect", ""))
		"no_sect":
			return ch.sect == ""
		"not_enemy_of":
			# 公敵坐完牢會改過自新（移出 sect_enemies），但叛徒記號永遠不能再拜入
			var es := String(c.get("sect", ""))
			return not ch.sect_enemies.has(es) and not ch.sect_traitor.has(es)
		"gender":
			return ch.gender == String(value)
		"attr_min":
			return int(eff.get(String(c.get("attr", "")), 0)) >= CharData.to_int(value)
		# 0.7.0.1 審查：上限型屬性門檻（郭襄：福緣不到 20 的峨嵋弟子才拿羅煞劍）；看有效屬性（含裝備）
		"attr_max":
			return int(eff.get(String(c.get("attr", "")), 0)) <= CharData.to_int(value)
		"skill_min":
			return ch.skills.level(String(c.get("skill", ""))) >= CharData.to_int(value)
		# 審查修正：藍鳳凰台免攻略「基本毒術 < 30」才接得了（上限型門檻）
		"skill_max":
			return ch.skills.level(String(c.get("skill", ""))) <= CharData.to_int(value)
		"combat_xp_min":
			return ch.combat_xp >= CharData.to_int(value)
		"pk_max":
			return ch.pk_value() <= CharData.to_int(value)
		"quest_flag":
			return ch.flags.get(String(c.get("flag", "")), false) == true
		"quest_done":
			return QuestState.done_count(ch.quests, String(c.get("quest", ""))) > 0
		# ---- STORY_PLAN §4.6 ----
		"quest_active":
			return QuestState.is_active(ch.quests, String(c.get("quest", "")))
		"quest_stage":
			var st := QuestState.active_entry(ch.quests, String(c.get("quest", "")))
			if st.is_empty():
				return false
			var want: Variant = c.get("stage", "")
			var cur := String(st.get("stage", ""))
			if typeof(want) == TYPE_ARRAY:
				for w in want:
					if String(w) == cur:
						return true
				return false
			return String(want) == cur
		"quest_var":
			var qv := String(c.get("quest", ""))
			if not QuestState.is_active(ch.quests, qv):
				return false
			var vars: Dictionary = QuestState.active_entry(ch.quests, qv).get("vars", {})
			var vn := String(c.get("var", ""))
			return vars.has(vn) and QuestState.value_eq(vars[vn], value)
		"quest_not_done":
			return QuestState.done_count(ch.quests, String(c.get("quest", ""))) <= 0
		"quest_not_active":
			return not QuestState.is_active(ch.quests, String(c.get("quest", "")))
		"quest_outcome":
			var qo := String(c.get("quest", ""))
			return QuestState.done_count(ch.quests, qo) > 0 and QuestState.last_outcome(ch.quests, qo) == String(c.get("outcome", ""))
		"lilian_min":
			return ch.lilian >= CharData.to_int(value)
		"fame_min":
			return ch.fame >= CharData.to_int(value)
		"combat_xp_max":
			return ch.combat_xp <= CharData.to_int(value)
		"killing_intent_max":
			return ch.killing_intent <= CharData.to_int(value)
		"era_enabled":
			var era := String(c.get("era", ""))
			var enabled: Variant = options.get("enabled_eras", null)
			if typeof(enabled) == TYPE_ARRAY:
				return enabled.has(era)
			# M1_PLAN 缺漏：options 沒有 enabled_eras 時，以 tables.eras 是否含此 era 判定
			return not CharData.row(tables, "eras", era).is_empty()
		"sect_enabled":
			# M1_PLAN 缺漏：server_options.sects_enabled 預設為 []；空清單視為「全部門派啟用」
			var s := String(c.get("sect", ""))
			var list: Variant = options.get("sects_enabled", [])
			if typeof(list) != TYPE_ARRAY or list.is_empty():
				return true
			return list.has(s)
		"rule":
			var key := String(c.get("key", ""))
			if not rules.has(key):
				return false
			var rv: Variant = rules[key]
			if typeof(rv) in [TYPE_INT, TYPE_FLOAT] and typeof(value) in [TYPE_INT, TYPE_FLOAT]:
				return is_equal_approx(float(rv), float(value))
			return typeof(rv) == typeof(value) and rv == value
		"unmarried":
			return true
		# ---- M3B_PLAN §4.3 ----
		"sect_not":
			return ch.sect != String(c.get("sect", ""))
		"sect_rank_min":
			return ch.sect != "" and ch.sect == String(c.get("sect", "")) and ch.sect_rank >= CharData.to_int(value)
		"org_member":
			# 純角色判定讀 ch.guild（快取值，OrgSystem 登入時校正）；org 空 = 任何組織
			var og := String(c.get("org", ""))
			return ch.guild != "" and (og == "" or ch.guild == og)
		"no_org":
			return ch.guild == ""
		"life_min":
			return ch.skills.level(String(c.get("skill", ""))) >= CharData.to_int(value)
		# ---- M3C2_PLAN §2.3.1（WP-PACE）：化緣「身上銀兩 ≤ value」 ----
		"money_max":
			return ch.money <= CharData.to_int(value)
	# ---- M3D_PLAN §9.2：各 WP 的 requirement 型別（各回 "?" 表示不認得） ----
	for r in [_m3d_law(c, ch, tables, options, rules, ctx), _m3d_combat(c, ch, tables, options, rules, ctx),
			_m3d_arts(c, ch, tables, options, rules, ctx), _m3d_events(c, ch, tables, options, rules, ctx)]:
		var v: Variant = _m3d_result(r)
		if v != null:
			return bool(v)
	return false

## 各 WP 函式的回傳：bool＝成立與否；String "?"＝不認得（往下一個）；
## 為了容忍寫法差異，String "" 視為成立、其他字串（原因碼）視為不成立。
static func _m3d_result(r: Variant) -> Variant:
	match typeof(r):
		TYPE_BOOL:
			return r
		TYPE_STRING, TYPE_STRING_NAME:
			if String(r) == "?":
				return null
			return String(r) == ""
		TYPE_INT:
			return int(r) != 0
	return null

## 中文說明，例：「佛法 10 級以上」
static func describe(cond: Dictionary, tables: Dictionary) -> String:
	var t := String(cond.get("type", ""))
	var value: Variant = cond.get("value", 0)
	match t:
		"morality_min":
			return "善惡 %d 以上" % CharData.to_int(value)
		"morality_max":
			return "善惡 %d 以下" % CharData.to_int(value)
		"sect":
			return "%s弟子" % CharData.sect_name(tables, String(cond.get("sect", "")))
		"no_sect":
			return "尚未拜入任何門派"
		"not_enemy_of":
			return "不是%s的公敵或叛徒" % CharData.sect_name(tables, String(cond.get("sect", "")))
		"gender":
			return "限%s" % GENDER_NAMES.get(String(value), String(value))
		"attr_min":
			return "%s %d 以上" % [CharData.attr_name(tables, String(cond.get("attr", ""))), CharData.to_int(value)]
		"attr_max":
			return "%s %d 以下" % [CharData.attr_name(tables, String(cond.get("attr", ""))), CharData.to_int(value)]
		"skill_min":
			return "%s %d 級以上" % [SkillBook.skill_name(String(cond.get("skill", "")), tables), CharData.to_int(value)]
		"skill_max":
			return "%s %d 級以下" % [SkillBook.skill_name(String(cond.get("skill", "")), tables), CharData.to_int(value)]
		"combat_xp_min":
			return "實戰經驗 %d 以上" % CharData.to_int(value)
		"pk_max":
			return "PK值 %d 以下" % CharData.to_int(value)
		"quest_flag":
			return "需要完成特定任務"
		"quest_done":
			var q := String(cond.get("quest", ""))
			return "完成任務「%s」" % String(CharData.row(tables, "quests", q).get("name", q))
		"killing_intent_max":
			return "殺氣 %d 以下" % CharData.to_int(value)
		"era_enabled":
			var era := String(cond.get("era", ""))
			return "需要開放資料片「%s」" % String(CharData.row(tables, "eras", era).get("name", era))
		"sect_enabled":
			return "需要開放%s" % CharData.sect_name(tables, String(cond.get("sect", "")))
		"rule":
			var rd := String(cond.get("desc", ""))
			return rd if rd != "" else "需要特定伺服器規則"
		"unmarried":
			return "未婚"
		"has_item":
			var n := maxi(1, CharData.to_int(cond.get("n", 1), 1))
			var nm := CharData.item_name(tables, String(cond.get("item", "")))
			return "身上帶著%s" % nm if n <= 1 else "身上帶著%s %d 個" % [nm, n]
		"any_of":
			var parts: PackedStringArray = []
			for group in cond.get("options", []):
				if typeof(group) != TYPE_ARRAY:
					continue
				var sub: PackedStringArray = []
				for g in group:
					if typeof(g) == TYPE_DICTIONARY:
						sub.append(describe(g, tables))
				parts.append("、".join(sub))
			return "符合其中一項：" + "；或 ".join(parts)
		"enemy_of":
			return "是%s的公敵" % CharData.sect_name(tables, String(cond.get("sect", "")))
		"not_flag":
			var d := String(cond.get("desc", ""))
			return d if d != "" else "沒有特定記號"
		"pk_min":
			return "PK值 %d 以上" % CharData.to_int(value)
		"killing_intent_min":
			return "殺氣 %d 以上" % CharData.to_int(value)
		"sect_master":
			return "%s的徒弟" % CharData.npc_name(tables, String(cond.get("npc", "")))
		"party_size_min":
			return "同隊同在此地的隊員 %d 人以上" % CharData.to_int(value)
		"quest_active":
			return "正在進行任務「%s」" % _quest_name(tables, String(cond.get("quest", "")))
		"quest_stage":
			return "任務「%s」進行到特定的階段" % _quest_name(tables, String(cond.get("quest", "")))
		"quest_var":
			return "任務「%s」有特定的進展" % _quest_name(tables, String(cond.get("quest", "")))
		"quest_outcome":
			var qq := String(cond.get("quest", ""))
			var oc := String(cond.get("outcome", ""))
			var label := String(CharData.row(tables, "quests", qq).get("outcomes", {}).get(oc, {}).get("label", "")) 				if typeof(CharData.row(tables, "quests", qq).get("outcomes", {})) == TYPE_DICTIONARY else ""
			return "任務「%s」的結局是「%s」" % [_quest_name(tables, qq), label] if label != "" 				else "任務「%s」有特定的結局" % _quest_name(tables, qq)
		"lilian_min":
			return "江湖歷練 %d 以上" % CharData.to_int(value)
		"fame_min":
			return "名聲 %d 以上" % CharData.to_int(value)
		"combat_xp_max":
			return "實戰經驗 %d 以下" % CharData.to_int(value)
		"hour_in":
			var hs: PackedStringArray = []
			for h in cond.get("hours", []):
				hs.append(str(h) + "時")
			return "只在%s" % "、".join(hs)
		# ---- M3B_PLAN §4.3 ----
		"sect_not":
			return "不是%s弟子" % CharData.sect_name(tables, String(cond.get("sect", "")))
		"sect_rank_min":
			var sid := String(cond.get("sect", ""))
			var rn := rank_name(tables, sid, CharData.to_int(value))
			return "%s%s以上" % [CharData.sect_name(tables, sid), rn] if rn != "" 				else "%s位階 %d 以上" % [CharData.sect_name(tables, sid), CharData.to_int(value)]
		"org_member":
			return "組織成員"
		"no_org":
			return "沒有加入任何組織"
		"life_min":
			return "生活技能%s %d 級以上" % [SkillBook.skill_name(String(cond.get("skill", "")), tables), CharData.to_int(value)]
		# ---- M3C2_PLAN §2.3.1 ----
		"money_max":
			return "身上沒有銀兩" if CharData.to_int(value) <= 0 else "身上銀兩 %d 兩以下" % CharData.to_int(value)
		# ---- M3D_PLAN §8.4 ----
		"counter_max":
			return "%s不超過 %d" % [COUNTER_NAMES.get(String(cond.get("key", "")), "特定紀錄"), CharData.to_int(value)]
		"bounty_listed":
			return "在衙門懸賞名單上"
		"has_license":
			return "持有賞金獵人執照"
		"combo_ready":
			return "與默契夥伴一同修練"
		"jb_active":
			return "沒有進行中的危險鏢" if cond.get("value", true) == false else "正在押鏢"   # M3d 整合
	return "特殊條件"

## sect_ranks 列的名稱（找不到回 ""）；生效視圖裡同一派同一 rank 只會有一列
static func rank_name(tables: Dictionary, sect_id: String, rank: int) -> String:
	var t: Variant = tables.get("sect_ranks", {})
	if not (t is Dictionary):
		return ""
	for id in t:
		var r: Variant = t[id]
		if r is Dictionary and String(r.get("sect", "")) == sect_id and CharData.to_int(r.get("rank", -1), -1) == rank:
			return String(r.get("name", ""))
	return ""

static func _quest_name(tables: Dictionary, qid: String) -> String:
	return String(CharData.row(tables, "quests", qid).get("name", qid))

## counter_max 的中文名（M3D_PLAN §4.9）
const COUNTER_NAMES := { "qz_gumu_kills": "殺死古墓弟子的人數" }

# ==== M3d WP-LAW ====
## bounty_listed、has_license（M3D_PLAN §8.4）；只讀 ctx（core 不碰主機）。不認得回 "?"
static func _m3d_law(c: Dictionary, ch: Character, tables: Dictionary, options: Dictionary, rules: Dictionary,
		ctx: Dictionary) -> Variant:
	match String(c.get("type", "")):
		"bounty_listed":
			return ctx.get("bounty_listed", false) == true   # LawSystem.req_ctx；沒有這個鍵 → 不成立
		"has_license":
			return ctx.get("has_license", false) == true
	return "?"

# ==== M3d WP-COMBAT ====
## combo_ready { art }（M3D_PLAN §3.3.1、§8.4）：學的人有合體夥伴、夥伴同房同隊、兩人分別符合 pair 的兩邊、默契 ≥ moqi_min。
## 只讀 ctx 的 combo 鍵（SectSystem.req_ctx 合併 ComboSystem.req_ctx）；ctx 沒有 → 讀 ComboRules.live_ctx（同一主機程序內
## ComboSystem 每 tick 更新；師父列由凍結的 Learning.check_master 判定、不帶 ctx，見 battle_combo.gd 的 M3D_PLAN 缺漏）。
## 不認得回 "?"
static func _m3d_combat(c: Dictionary, ch: Character, tables: Dictionary, options: Dictionary, rules: Dictionary,
		ctx: Dictionary) -> Variant:
	if String(c.get("type", "")) != "combo_ready":
		return "?"
	return combo_ready_reason(c, ch, tables, ctx) == ""

## combo_ready 不成立的原因碼（"" = 成立）；介面與主機的提示用
static func combo_ready_reason(c: Dictionary, ch: Character, tables: Dictionary, ctx: Dictionary) -> String:
	var art_row := CharData.row(tables, "martial_arts", String(c.get("art", "")))
	var cc: Variant = ctx.get("combo", null)
	if not (cc is Dictionary):
		cc = ComboRules.live_ctx.get(ch.id, {})
	var ss := String(CharData.row(tables, "sects", ch.sect).get("sect_skill", "")) if ch.sect != "" else ""
	var mine_sk := {}
	for side in (ComboRules.combo_of(art_row).get("pair", []) as Array):
		if side is Dictionary:
			var a := String(side.get("art", ""))
			mine_sk[a] = ch.skills.level(a)
	var me := { "gender": ch.gender, "skills": mine_sk, "sect_skill": ch.skills.level(ss) if ss != "" else 0 }
	return ComboRules.ready_reason(art_row, me, cc as Dictionary)

# ==== M3d WP-ARTS ====
## counter_max { key, value }：角色 counters[key]（int）≤ value 才成立（M3D_PLAN §4.9）
static func _m3d_arts(c: Dictionary, ch: Character, tables: Dictionary, options: Dictionary, rules: Dictionary,
		ctx: Dictionary) -> Variant:
	match String(c.get("type", "")):
		"counter_max":
			var key := String(c.get("key", ""))
			var cur: Variant = ch.counters.get(key, 0)
			var n := CharData.to_int(cur) if typeof(cur) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING] else 0
			return n <= CharData.to_int(c.get("value", 0))
	return "?"

# ==== M3d WP-EVENTS ====
## jb_active（M3D_PLAN §8.4）。不認得回 "?"
## jb_active { value?: bool }：身上有進行中的危險鏢（ext.jiebiao.active）；value 給 false ＝沒有（接鏢條件「沒有進行中的危險鏢」）
static func _m3d_events(c: Dictionary, ch: Character, tables: Dictionary, options: Dictionary, rules: Dictionary,
		ctx: Dictionary) -> Variant:
	match String(c.get("type", "")):
		"jb_active":
			var e: Variant = ch.ext.get("jiebiao", null)
			var a: Variant = (e as Dictionary).get("active", null) if e is Dictionary else null
			var has := a is Dictionary and String((a as Dictionary).get("quest", "")) != ""
			return has == (c.get("value", true) != false)
	return "?"
