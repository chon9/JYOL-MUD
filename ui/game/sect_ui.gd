class_name SectUi
extends RefCounted
## 門派相關介面的純函式（M3A_PLAN §7.6–7.9）：拜師確認的條件與門規摘要、叛教會減半的武功、思過處倒數、
## 贖金金額、屬性燈籠的門規警示、戰後持續狀態的提示。只讀本地資料表（UiClient）與角色表，不做任何判定。

const DAY_S := 86400

# ---------- 時間與金額 ----------
## 上線秒數 → 「1 小時 32 分」「5 分 20 秒」「40 秒」
static func duration_text(secs: float) -> String:
	var s := maxi(0, ceili(secs))
	var h := s / 3600
	var m := (s % 3600) / 60
	var sec := s % 60
	if h > 0:
		return "%d 小時 %d 分" % [h, m]
	if m > 0:
		return "%d 分 %d 秒" % [m, sec] if sec > 0 else "%d 分" % m
	return "%d 秒" % sec

## 兩 → 「十萬兩」「五千兩」「1234 兩」（整萬、整千用中文數字）
static func money_text(n: int) -> String:
	if n > 0 and n % 10000 == 0 and n / 10000 <= 99:
		return "%s萬兩" % BottomHud.cn_num(n / 10000)
	if n > 0 and n < 10000 and n % 1000 == 0:
		return "%s千兩" % BottomHud.cn_num(n / 1000)
	return "%d 兩" % n

## 坐牢提示列：「思過處：剩 1 小時 32 分（上線時間）」（§7.7）
static func jail_banner(jail: Dictionary, left_s: float) -> String:
	if jail.is_empty():
		return ""
	# M3b（M3B_PLAN §7.7）：京城監獄
	if str(jail.get("scope", "")) == UiKeys.JAIL_SCOPE_CAPITAL:
		return "%s：剩 %s（上線時間）" % [UiKeys.CAPITAL_JAIL_NAME, SectUi.duration_text(left_s)]
	var place := str(jail.get("room_name", ""))
	# 房名已經帶「思過處」（少林思過處）就不再包一層「思過處（少林思過處）」（M3a UI 審查 #2）
	var head := "思過處" if place == "" else (place if place.contains("思過") else "思過處（%s）" % place)
	return "%s：剩 %s（上線時間）" % [head, SectUi.duration_text(left_s)]

## 角色表收到時的剩餘秒數，扣掉收到之後經過的真實時間（坐牢、禁止學武以上線秒數計，在線時就是真實秒數）
static func left_now(left_s: float, rx_ms: int, now_ms: int = -1) -> float:
	var now := Time.get_ticks_msec() if now_ms < 0 else now_ms
	if rx_ms <= 0:
		return maxf(0.0, left_s)
	return maxf(0.0, left_s - (now - rx_ms) / 1000.0)

# ---------- 拜師確認（§7.6） ----------
## 門派列（本地 sects 表）
static func sect_row(sect_id: String) -> Dictionary:
	return UiClient.row("sects", sect_id)

## 收徒條件的一句話：「只收男弟子」「善惡 50 以上」「需要引薦書」…
static func requirement_text(c: Dictionary) -> String:
	var t := str(c.get("type", ""))
	var v := int(c.get("value", 0))
	match t:
		"morality_min":
			return "善惡 %d 以上" % v
		"morality_max":
			return "善惡 %d 以下" % v
		"pk_max":
			return "PK值 0" if v == 0 else "PK值不超過 %d" % v
		"pk_min":
			return "PK值至少 %d" % v
		"killing_intent_max":
			return "殺氣不超過 %d" % v
		"killing_intent_min":
			return "殺氣至少 %d" % v
		"no_sect":
			return "尚未拜入任何門派"
		"not_enemy_of":
			return "不是%s的公敵或叛徒" % UiClient.name_of("sects", str(c.get("sect", "")))
		"unmarried":
			return "未婚"
		"not_flag":
			return str(c.get("desc", ""))
		"enemy_of":
			return "是%s的公敵" % UiClient.name_of("sects", str(c.get("sect", "")))
		"gender":
			return "只收%s弟子" % UiKeys.GENDER_LABELS.get(str(c.get("value", "")), str(c.get("value", "")))
		"has_item":
			return "身上帶著%s" % UiClient.name_of("items", str(c.get("item", "")))
		"quest_flag":
			var flag := str(c.get("flag", ""))
			if flag.ends_with("recommended"):
				return "需要引薦"
			var qn := SectUi.quest_setting_flag(flag)
			return "完成任務「%s」" % qn if qn != "" else "完成指定任務"
		"combat_xp_min":
			return "實戰經驗 %d 以上" % v
		"sect":
			return "%s弟子" % UiClient.name_of("sects", str(c.get("sect", "")))
		# M3b（M3B_PLAN §4.3）
		"fame_min":
			return "名聲 %d 以上" % v
		"lilian_min":
			return "江湖歷練 %d 以上" % v
		"skill_min":
			return "%s %d 級以上" % [SectUi.skill_name(str(c.get("skill", ""))), v]
		"life_min":
			return "生活技能%s %d 級以上" % [UiClient.name_of("life_skills", str(c.get("skill", ""))), v]
		"sect_rank_min":
			var sid := str(c.get("sect", ""))
			var rn := SectUi.rank_name(sid, v)
			return "%s%s以上" % [UiClient.name_of("sects", sid), rn if rn != "" else "位階 %d" % v]
		"sect_not":
			return "不是%s弟子" % UiClient.name_of("sects", str(c.get("sect", "")))
		"org_member":
			var oid := str(c.get("org", ""))
			return "組織成員" if oid == "" else "組織「%s」的成員" % oid
		"no_org":
			return "不在任何組織裡"
		"any_of":
			var opts: PackedStringArray = []
			for grp in c.get("options", []):
				if grp is Array:
					var parts: PackedStringArray = []
					for cc in grp:
						if cc is Dictionary:
							parts.append(SectUi.requirement_text(cc))
					opts.append("、".join(parts))
			return "（%s）" % "）或（".join(opts)
	return ""

## 性別條件：「男」「女」「男女皆收」
static func gender_text(sect: Dictionary) -> String:
	var g: Variant = sect.get("gender", [])
	if not (g is Array) or (g as Array).is_empty() or (g as Array).size() >= 2:
		return "男女皆收"
	return "只收%s弟子" % UiKeys.GENDER_LABELS.get(str(g[0]), str(g[0]))

## 伺服器的 sect_violation_mode（world_info 展開後的 rule_profile；沒有時 JAIL）
static func violation_mode() -> String:
	var rp: Variant = UiClient.world_info().get("rule_profile", {})
	var m := str((rp as Dictionary).get("sect_violation_mode", "JAIL")) if rp is Dictionary else "JAIL"
	return m if m in ["JAIL", "EXPEL", "BAN"] else "JAIL"

## 門規文字：sect_rules 裡本派各列的 text 模板（self 變體），拿掉頻道標籤。
## 只列這台主機的規則（sect_violation_mode）適用的列：坐牢名單（JAIL／BAN）與 2001-08 叛派名單（EXPEL）不同（M3a 審查）
static func rule_texts(sect_id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var rules := UiClient.table("sect_rules")
	var tpls := UiClient.templates()
	var ids: Array = rules.keys()
	ids.sort()
	var mode := SectUi.violation_mode()
	for rid in ids:
		var r: Variant = rules[rid]
		if not (r is Dictionary) or str(r.get("sect", "")) != sect_id:
			continue
		var modes: Variant = (r as Dictionary).get("modes", [])
		if modes is Array and not (modes as Array).is_empty() and not (modes as Array).has(mode):
			continue
		var tpl: Variant = tpls.get(str(r.get("text", "")), {})
		var t := ""
		if tpl is Dictionary:
			t = str((tpl as Dictionary).get("self", (tpl as Dictionary).get("other", "")))
		if t == "":
			continue
		var line := TextRenderer.strip_channel_tag(TextRenderer.fill(t, {})).strip_edges()
		while line.ends_with("。"):
			line = line.substr(0, line.length() - 1)
		if line != "" and not out.has(line):
			out.append(line)
	return out

## 拜師確認窗的內容：{ name, gender, conditions: [..], rules: [..] }
static func join_summary(sect_id: String, fallback_name: String = "") -> Dictionary:
	var sect := SectUi.sect_row(sect_id)
	var conds: PackedStringArray = []
	for c in sect.get("join_requires", []):
		if c is Dictionary:
			var t := SectUi.requirement_text(c)
			if t != "" and not conds.has(t):
				conds.append(t)
	return {
		"name": str(sect.get("name", fallback_name if fallback_name != "" else sect_id)),
		"gender": SectUi.gender_text(sect),
		"conditions": conds,
		"rules": SectUi.rule_texts(sect_id),
	}

## 拜師確認窗：依角色表看得出來「現在不符合」的條件（性別、善惡、PK、殺氣、已有門派、公敵／叛徒）。
## 只是提示（主機才是判定者）；看不出來的條件（任務、物品…）不列。
static func unmet_conditions(sect_id: String, sheet: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	if sheet.is_empty():
		return out
	var sect := SectUi.sect_row(sect_id)
	var g: Variant = sect.get("gender", [])
	var gender := str(sheet.get("gender", ""))
	if g is Array and not (g as Array).is_empty() and gender != "" and not (g as Array).has(gender):
		out.append(SectUi.gender_text(sect))
	for c in sect.get("join_requires", []):
		if not (c is Dictionary):
			continue
		var v := int(c.get("value", 0))
		var bad := false
		match str(c.get("type", "")):
			"morality_min":
				bad = sheet.has("morality") and int(sheet["morality"]) < v
			"morality_max":
				bad = sheet.has("morality") and int(sheet["morality"]) > v
			"pk_max":
				bad = sheet.has("pk") and int(sheet["pk"]) > v
			"killing_intent_max":
				bad = sheet.has("killing_intent") and int(sheet["killing_intent"]) > v
			"no_sect":
				bad = str(sheet.get("sect", "")) != ""
			"gender":
				bad = gender != "" and gender != str(c.get("value", ""))
			"not_enemy_of":
				var nm := UiClient.name_of("sects", str(c.get("sect", "")))
				var en: Variant = sheet.get("enemy_of", [])
				var tr: Variant = sheet.get("traitor_of", [])
				bad = (en is Array and (en as Array).has(nm)) or (tr is Array and (tr as Array).has(nm))
		if bad and str(c.get("type", "")) == "no_sect":
			# 「不符合：尚未拜入任何門派」看不懂（擁有者截圖：少林弟子去找岳不群）→ 直接說已經是哪派弟子
			var mine := "你已經是%s弟子" % UiClient.name_of("sects", str(sheet.get("sect", "")))
			if not out.has(mine):
				out.append(mine)
			continue
		if bad:
			var t := SectUi.requirement_text(c)
			if t != "" and not out.has(t):
				out.append(t)
	return out

## 拜師確認窗的文字
static func join_text(sect_id: String, fallback_name: String = "") -> String:
	var s := SectUi.join_summary(sect_id, fallback_name)
	var lines: PackedStringArray = ["確定要拜入%s門下嗎？入門後不得再投他派。" % s["name"]]
	var conds: PackedStringArray = [str(s["gender"])]
	conds.append_array(s["conditions"])
	lines.append("入門條件：" + "；".join(conds))
	var rules: PackedStringArray = s["rules"]
	lines.append("門規：" + ("；".join(rules) if not rules.is_empty() else "（無特別門規）"))
	return "\n".join(lines)

# ---------- 叛教（§6.5、§7.6） ----------
## 伺服器規則 betrayal_halves_basics（world_info 展開後的 rule_profile）
static func halves_basics() -> bool:
	var rp: Variant = UiClient.world_info().get("rule_profile", {})
	return rp is Dictionary and (rp as Dictionary).get("betrayal_halves_basics", false) == true

## 叛教會減半的武功：[{ id, name, level, after }]。預設只有本門武功（martial_arts.sect_id == 本派）；
## halves_basics 時全部特殊武功與基本武學（門派技能另外歸零，不在這張表）
static func betray_halved(sheet: Dictionary, sect_id: String, all_arts: bool) -> Array:
	var out: Array = []
	for sk in sheet.get("skills", []):
		if not (sk is Dictionary):
			continue
		var kind := str(sk.get("kind", ""))
		var id := str(sk.get("id", ""))
		var lv := UiBuild.num(sk.get("level", 0))
		if lv <= 0:
			continue
		var hit := false
		if kind == "ART":
			hit = all_arts or str(UiClient.row("martial_arts", id).get("sect_id", "")) == sect_id
		elif kind == "BASIC":
			hit = all_arts
		if hit:
			out.append({ "id": id, "name": str(sk.get("name", UiClient.name_of("martial_arts", id))), "level": lv, "after": lv / 2 })
	return out

## 叛教第一段確認的說明
static func betray_text(sheet: Dictionary, sect_id: String, all_arts: bool) -> String:
	var sect := SectUi.sect_row(sect_id)
	var sname := str(sect.get("name", sheet.get("sect_name", sect_id)))
	var lines: PackedStringArray = ["叛出%s，後果如下：" % sname]
	var halved := SectUi.betray_halved(sheet, sect_id, all_arts)
	if halved.is_empty():
		lines.append("・%s：（目前沒有）" % ("所有武功減半" if all_arts else "本門武功減半"))
	else:
		var parts: PackedStringArray = []
		for h in halved:
			parts.append("%s %d → %d 級" % [h["name"], h["level"], h["after"]])
		lines.append("・%s：%s" % ["所有武功減半" if all_arts else "本門武功減半", "、".join(parts)])
	# 門派技能歸零只屬後期官方規則（betrayal_halves_basics 同一個開關）；2001 只減半本門武功
	var ss := str(sect.get("sect_skill_name", ""))
	if all_arts:
		lines.append("・門派技能%s歸零" % ("「%s」" % ss if ss != "" else ""))
	lines.append("・門派物品沒收")
	lines.append("・從此成為%s的公敵；就算日後坐牢改過，也是叛徒，永遠不能再拜入" % sname)
	return "\n".join(lines)

static func betray_word_ok(text: String) -> bool:
	return text.strip_edges() == UiKeys.BETRAY_WORD

# ---------- 屬性燈籠（§7.9） ----------
static func sect_info(sheet: Dictionary) -> Dictionary:
	var v: Variant = sheet.get("sect_info", {})
	return v if v is Dictionary else {}

## sect_info.warnings：接近本派門規底線的屬性 key（morality／pk／killing_intent）
static func warnings(sheet: Dictionary) -> Array:
	var w: Variant = SectUi.sect_info(sheet).get("warnings", [])
	return w if w is Array else []

static func warned(sheet: Dictionary, key: String) -> bool:
	return SectUi.warnings(sheet).has(key)

## 屬性窗門派那一列下面的補充：「門派技能：俠義 12 級　師父：丘處機」＋停止傳功、禁止學武、公敵
static func sect_lines(sheet: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var si := SectUi.sect_info(sheet)
	if not si.is_empty() and str(si.get("id", "")) != "":
		var parts: PackedStringArray = []
		if str(si.get("skill_name", "")) != "":
			parts.append("門派技能：%s %d 級" % [str(si["skill_name"]), UiBuild.num(si.get("skill_level", 0))])
		if str(si.get("master", "")) != "":
			parts.append("師父：%s" % str(si["master"]))
		if not parts.is_empty():
			out.append("　".join(parts))
		var rt := SectUi.rank_text(sheet)
		if rt != "":
			out.append(rt)
		var stop := str(si.get("stop_teach", ""))
		if stop != "":
			out.append("門派狀態：%s" % SectUi.block_text(stop, float(si.get("ban_left_s", 0))))
	var en: Variant = sheet.get("enemy_of", [])
	if en is Array and not (en as Array).is_empty():
		out.append("公敵：" + "、".join(PackedStringArray((en as Array).map(func(x): return str(x)))))
	return out

## 學藝被拒的說明（§7.8）：「停止傳功：…」「禁止學武：還要 1 小時 2 分」
static func block_text(reason: String, ban_left_s: float = 0.0) -> String:
	var title: String = UiKeys.TEACH_BLOCK_TITLES.get(reason, "")
	var why := UiClient.reason_inline(reason)
	if reason == "sect_banned" and ban_left_s > 0.0:
		why += "（還要 %s）" % SectUi.duration_text(ban_left_s)
	if title != "" and not why.begins_with(title):
		return "%s：%s" % [title, why]
	return why

# ---------- M3b 位階（袋位；M3B_PLAN §5.1.1、§7.5） ----------
## 技能名：武功表、生活技能表、門派技能（sects.sect_skill）都找
static func skill_name(id: String) -> String:
	# 基本武學（基本內功、讀書識字…）也要查：擁有者回報華山拜師條件顯示「basic_inner 5 級以上」
	var r := UiClient.row("basic_skills", id)
	if r.has("name"):
		return str(r["name"])
	r = UiClient.row("martial_arts", id)
	if r.has("name"):
		return str(r["name"])
	r = UiClient.row("life_skills", id)
	if r.has("name"):
		return str(r["name"])
	var sects := UiClient.table("sects")
	for sid in sects:
		var s: Variant = sects[sid]
		if s is Dictionary and str(s.get("sect_skill", "")) == id:
			return str(s.get("sect_skill_name", id))
	return id

## 會給這個任務記號的任務名稱（任務完成獎勵的 flags）；找不到回 ""
static func quest_setting_flag(flag: String) -> String:
	var t := UiClient.table("quests")
	for qid in t:
		var q: Variant = t[qid]
		if not (q is Dictionary):
			continue
		var rw: Variant = (q as Dictionary).get("rewards", {})
		if rw is Dictionary and ((rw as Dictionary).get("flags", []) as Array).has(flag):
			return str((q as Dictionary).get("name", ""))
	return ""

## 本地 sect_ranks 表中某派的列（依 rank 排序；客戶端資料已依 era 過濾，只有生效的列）
static func rank_rows(sect_id: String) -> Array:
	var out: Array = []
	var t := UiClient.table("sect_ranks")
	for id in t:
		var r: Variant = t[id]
		if r is Dictionary and str(r.get("sect", "")) == sect_id:
			out.append(r)
	out.sort_custom(func(a, b): return UiBuild.num(a.get("rank", 0)) < UiBuild.num(b.get("rank", 0)))
	return out

static func rank_name(sect_id: String, rank: int) -> String:
	for r in SectUi.rank_rows(sect_id):
		if UiBuild.num(r.get("rank", -1)) == rank:
			return str(r.get("name", ""))
	return ""

## 角色表 sect_info.rank：{ level, name, pending: { rank, name }|null, next: { name, requires_text }|null }
static func rank_info(sheet: Dictionary) -> Dictionary:
	var r: Variant = SectUi.sect_info(sheet).get("rank", null)
	return r if r is Dictionary else {}

## 屬性窗門派欄的「袋位：一袋弟子」，待升時加「（升二袋弟子，待聚會）」；沒有位階的門派回 ""
static func rank_text(sheet: Dictionary) -> String:
	var ri := SectUi.rank_info(sheet)
	if ri.is_empty() or str(ri.get("name", "")) == "":
		return ""
	var t := "袋位：%s" % str(ri.get("name", ""))
	var pend: Variant = ri.get("pending", null)
	if pend is Dictionary and not (pend as Dictionary).is_empty():
		var pn := str((pend as Dictionary).get("name", ""))
		t += "（%s待聚會）" % ("升%s，" % pn if pn != "" else "")
	return t

## 升袋方式的說明
const PROMOTE_TEXT := { "JOIN": "拜入即得", "QUEST": "完成任務後，等下一次聚會升袋", "AUTO": "條件達到後，下一次聚會自動升袋" }
const RANK_STATE_LABELS := { "DONE": "已達成", "PENDING": "待聚會", "NEXT": "下一袋", "LOCKED": "" }
const COST_LABELS := { "fame": "名聲", "lilian": "江湖歷練", "money": "銀兩" }

## 「袋位」頁（陳長老選單；npc_menu.rank）：[{ rank, name, conditions, quest_name, promote_text, cost_text, state }]
## 主機的 rank 選單有 rows 就照主機，沒有就用本地 sect_ranks 表與角色表自己排。
## # M3B_PLAN 缺漏：§6 npc_menu.rank 寫「…§5.1.1 rank_menu…」，形狀沒有展開；這裡接受 { sect, sect_name, level, rows: [...] }，
## rows 每列是 sect_ranks 的列（可另帶 requires_text、quest_name）
static func rank_page(menu_rank: Dictionary, sheet: Dictionary) -> Array:
	var level := UiBuild.num(menu_rank.get("level", SectUi.rank_info(sheet).get("level", 0)))
	var pend: Variant = menu_rank.get("pending", SectUi.rank_info(sheet).get("pending", null))
	var pend_rank := UiBuild.num((pend as Dictionary).get("rank", -1)) if pend is Dictionary else -1
	var rows: Array = []
	var given: Variant = menu_rank.get("rows", null)
	if given is Array and not (given as Array).is_empty():
		rows = given
	else:
		rows = SectUi.rank_rows(str(menu_rank.get("sect", sheet.get("sect", ""))))
	var out: Array = []
	for r in rows:
		if not (r is Dictionary):
			continue
		var rk := UiBuild.num(r.get("rank", 0))
		var conds: Array = []
		if r.get("requires_text", null) is Array:
			conds = (r["requires_text"] as Array).map(func(x): return str(x))
		else:
			for c in r.get("requires", []):
				if c is Dictionary:
					var t := SectUi.requirement_text(c)
					if t != "":
						conds.append(t)
		var qn := str(r.get("quest_name", ""))
		if qn == "" and str(r.get("quest", "")) != "":
			qn = UiClient.name_of("quests", str(r.get("quest", "")))
		var cost: PackedStringArray = []
		var cd: Variant = r.get("cost", {})
		if cd is Dictionary:
			for k in ["fame", "lilian", "money"]:
				if UiBuild.num((cd as Dictionary).get(k, 0)) > 0:
					cost.append("%s %d" % [COST_LABELS[k], UiBuild.num(cd[k])])
		var state := "LOCKED"
		if rk <= level:
			state = "DONE"
		elif rk == pend_rank:
			state = "PENDING"
		elif rk == level + 1:
			state = "NEXT"
		out.append({ "rank": rk, "name": str(r.get("name", "")), "conditions": conds, "quest_name": qn,
			"promote_text": str(PROMOTE_TEXT.get(str(r.get("promote", "")), "")),
			"cost_text": ("升袋時扣 " + "、".join(cost)) if not cost.is_empty() else "", "state": state })
	return out

## 袋位頁一列的文字（兩行：名稱與狀態；條件、任務、升法、扣點）
static func rank_page_line(row: Dictionary) -> String:
	var t := str(row.get("name", ""))
	var st := str(RANK_STATE_LABELS.get(str(row.get("state", "")), ""))
	if st != "":
		t += "　【%s】" % st
	var parts: PackedStringArray = []
	var conds: Array = row.get("conditions", [])
	if not conds.is_empty():
		parts.append("條件：" + "、".join(PackedStringArray(conds.map(func(x): return str(x)))))
	if str(row.get("quest_name", "")) != "":
		parts.append("任務：" + str(row["quest_name"]))
	if str(row.get("promote_text", "")) != "":
		parts.append(str(row["promote_text"]))
	if str(row.get("cost_text", "")) != "":
		parts.append(str(row["cost_text"]))
	if not parts.is_empty():
		t += "\n　　" + "；".join(parts)
	return t

# ---------- M3b 乞討（M3B_PLAN §5.1.2、§7.6） ----------
## npc_menu.beg：{ ok, reason, left_s? }（只有本派有 practice 的人看得到；沒有就是 {}）
static func beg_state(menu: Dictionary) -> Dictionary:
	var b: Variant = menu.get("beg", null)
	return b if b is Dictionary else {}

## 灰掉時的原因：冷卻剩幾分、精神不足……
static func beg_block_text(beg: Dictionary) -> String:
	if bool(beg.get("ok", false)):
		return ""
	var reason := str(beg.get("reason", ""))
	match reason:
		"beg_cooldown":
			var left := float(beg.get("left_s", 0))
			if left > 0.0:
				return "剛向他討過，冷卻還剩 %s" % SectUi.duration_text(left)
			return "剛向他討過，過一陣子再來"
		"not_enough_jing":
			return "精不足"
		"not_enough_shen":
			return "神不足"
	return UiClient.reason_inline(reason) if reason != "" else "現在不能乞討"

## 本派的行動練習設定（sects.practice）
static func practice(sect_id: String) -> Dictionary:
	var p: Variant = UiClient.row("sects", sect_id).get("practice", null)
	return p if p is Dictionary else {}

## 這位 NPC 可不可以乞討（本地資料表；只是指令窗的提示，主機才是判定者）
static func npc_beggable(npc_id: String, practice_row: Dictionary) -> bool:
	if practice_row.is_empty():
		return false
	var n := UiClient.row("npcs", npc_id)
	if n.is_empty() or bool(n.get("no_beg", false)):
		return false
	var kinds: Variant = practice_row.get("npc_kinds", [])
	return kinds is Array and (kinds as Array).has(str(n.get("kind", "")))

static func my_sect(sheet: Dictionary) -> String:
	var s := str(sheet.get("sect", ""))
	return s if s != "" else str(SectUi.sect_info(sheet).get("id", ""))

## 指令窗「行動 → 乞討」的對象：優先最近交談的那位（還在這間房），否則房間裡第一位可乞討的 NPC
static func beg_target(view: Dictionary, sheet: Dictionary, preferred: String = "") -> String:
	var pr := SectUi.practice(SectUi.my_sect(sheet))
	if pr.is_empty():
		return ""
	var ids: Array = []
	for n in view.get("npcs", []):
		if n is Dictionary:
			ids.append(str(n.get("id", "")))
	if preferred != "" and ids.has(preferred) and SectUi.npc_beggable(preferred, pr):
		return preferred
	for id in ids:
		if SectUi.npc_beggable(id, pr):
			return id
	return ""

# ---------- 戰後持續狀態（§7.5 HUD「狀」） ----------
static func conditions(sheet: Dictionary) -> Array:
	var c: Variant = sheet.get("conditions", [])
	return c if c is Array else []

## 「中毒（2 級，剩 3 分 20 秒）」
static func condition_text(c: Dictionary, left_s: float) -> String:
	var t := str(c.get("name", c.get("id", "")))
	var extra: PackedStringArray = []
	if UiBuild.num(c.get("level", 1)) > 1:
		extra.append("%d 級" % UiBuild.num(c.get("level", 1)))
	if left_s > 0.0:
		extra.append("剩 %s" % SectUi.duration_text(left_s))
	return t + ("（%s）" % "，".join(extra) if not extra.is_empty() else "")
