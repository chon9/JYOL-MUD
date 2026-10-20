class_name LearnDialog
extends UiDialog
## 學武對話框（M1_PLAN 3.12）：收到 teach_list 開啟：每列技能名、目前等級／師父上限；
## ok == false 時顯示 reason 的中文並灰色；「請教 ×1／×5／×10」→ learn；成功後重新送 learn_list。
## M3a（M3A_PLAN §7.8）：teach_blocked（npc_menu 帶來，或 teach_list 自己帶）不是空字串時，整個視窗上方顯示原因
## （停止傳功、禁止學武、思過中），全部學習鈕灰掉。

const TIMES := [1, 5, 10]

var data: Dictionary = {}
var info_label: Label
var list: VBoxContainer
var portrait: TextureRect
var block_label: Label
var blocked := ""
var novice_label: Label   # M3c2 審查：新手學藝加速只在視窗上方寫一行（原本每列一個紅字標籤，像錯誤訊息）

func dialog_size() -> Vector2:
	return Vector2(860, 460)

## AUTHENTIC_UI_SPEC §8.9：玉石框，內容是武功窗的書頁樣式：左頁師父立繪（墨色），右頁可學清單
func _build_body() -> void:
	block_label = UiBuild.error(UiBuild.label(body, "", 17, true))
	block_label.name = "TeachBlocked"
	block_label.visible = false
	info_label = UiBuild.muted(UiBuild.label(body, "", 15, true))
	novice_label = UiBuild.label(body, "", 14, true)
	novice_label.name = "LearnNoviceHeader"
	novice_label.add_theme_color_override("font_color", UiTheme.JY_GOLD_LIGHT)
	novice_label.mouse_filter = Control.MOUSE_FILTER_PASS
	novice_label.visible = false
	var book := PanelContainer.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = UiTheme.JY_PARCHMENT
	paper.border_color = Color("6e5a3a")
	paper.set_border_width_all(2)
	paper.set_content_margin_all(8)
	book.add_theme_stylebox_override("panel", paper)
	book.theme = UiTheme.paper()
	book.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(book)
	var pages := UiBuild.hbox(book, 0)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(150, 300)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.modulate = SkillsPanel.INK_SILHOUETTE
	pages.add_child(portrait)
	pages.add_child(SkillsPanel.Spine.new())
	list = UiBuild.vbox(UiBuild.scroll(pages, 300), 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func npc_id() -> String:
	return str(data.get("npc", ""))

## p = teach_list payload（3.8.2）；p.teach_blocked（M3a）＝學藝被拒的原因碼
func open_list(p: Dictionary) -> void:
	ensure_built()
	if str(p.get("npc", "")) != npc_id():
		status_label.text = ""   # 換了師父：清掉上一位師父那邊的錯誤（擁有者截圖：玄淨窗底留著知客僧的「內力不夠」）
	data = p
	blocked = str(p.get("teach_blocked", ""))
	block_label.visible = blocked != ""
	block_label.text = SectUi.block_text(blocked, float(SectUi.sect_info(UiClient.sheet()).get("ban_left_s", 0))) if blocked != "" else ""
	title_label.text = "向%s請教" % str(p.get("npc_name", ""))
	var tex := ArtRegistry.unit_texture(str(p.get("npc", "")), "NPC", "idle")
	# M3c：沒有師父立繪時用自己的外觀（sheet.look；取不到用 player_m）
	portrait.texture = tex if tex != null else LookPicker.sheet_look_texture(UiClient.sheet())
	var sh := UiClient.sheet()
	info_label.text = "學點 %d　　精 %d　　銀兩 %d　　（每次請教花 1 學點與一些精）" % [
		UiBuild.num(sh.get("learn_points", 0)), UiBuild.num((sh.get("vitals", {}) as Dictionary).get("jing", 0)),
		UiBuild.num(sh.get("money", 0))]
	UiBuild.clear(list)
	var any_novice := false
	for e in p.get("entries", []):
		if e is Dictionary:
			_row(e)
			any_novice = any_novice or novice_applies(str(e.get("kind", "")), int(UiBuild.num(e.get("level", 0))), {},
				UiBuild.num(sh.get("combat_xp", 0)))
	novice_label.visible = any_novice
	novice_label.text = novice_header() if any_novice else ""
	novice_label.tooltip_text = novice_tip() if any_novice else ""
	if list.get_child_count() == 0:
		UiBuild.muted(UiBuild.label(list, "（沒有可以請教的武學）", 15))
	visible = true

func _row(e: Dictionary) -> void:
	var row := UiBuild.hbox(list, 8)
	var kind := str(e.get("kind", ""))
	var ok := bool(e.get("ok", false))
	var name_l := UiBuild.label(row, str(e.get("name", e.get("skill", ""))), 16)
	name_l.custom_minimum_size = Vector2(130, 0)
	UiBuild.muted(UiBuild.label(row, UiKeys.SKILL_KIND_LABELS.get(kind, kind), 14)).custom_minimum_size = Vector2(70, 0)
	UiBuild.label(row, "%d / %d 級" % [UiBuild.num(e.get("level", 0)), UiBuild.num(e.get("cap", 0))], 15).custom_minimum_size = Vector2(90, 0)
	var price := UiBuild.num(e.get("price", 0))
	UiBuild.muted(UiBuild.label(row, ("%d 兩" % price) if price > 0 else "", 14)).custom_minimum_size = Vector2(56, 0)
	var skill := str(e.get("skill", ""))
	if blocked != "":
		ok = false
	if not ok and str(e.get("reason", "")) != "":
		# 不能學的那一行：原因佔掉按鈕的位置（灰掉的請教鈕本來就按不了）。
		# 原因和三顆按鈕擠在同一行時，原因被壓到一個字寬、逐字換行，整行被撐高、按鈕跟著拉長（擁有者截圖）。
		name_l.add_theme_color_override("font_color", UiTheme.DISABLED_TEXT)
		var why := UiBuild.label(row, UiClient.reason_inline(str(e.get("reason", ""))), 14, true)
		why.name = "LearnWhy_" + str(e.get("skill", ""))
		why.add_theme_color_override("font_color", UiTheme.DISABLED_TEXT)
		why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		why.custom_minimum_size = Vector2(260, 0)
		why.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		why.tooltip_text = why.text
		why.mouse_filter = Control.MOUSE_FILTER_PASS
		return
	else:
		if not ok:
			name_l.add_theme_color_override("font_color", UiTheme.DISABLED_TEXT)
		row.add_child(Control.new())
		row.get_child(row.get_child_count() - 1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if kind == "LIFE":
		var b := UiBuild.button(row, "學習")
		b.disabled = not ok
		b.pressed.connect(func(): send(UiKeys.I_LEARN, { "npc": npc_id(), "skill": skill, "times": 1 }, [b], refresh_list))
		return
	for t in TIMES:
		var b2 := UiBuild.button(row, "請教 ×%d" % t)
		b2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b2.disabled = not ok
		b2.pressed.connect(func(): send(UiKeys.I_LEARN, { "npc": npc_id(), "skill": skill, "times": t }, [b2], refresh_list))

func refresh_list() -> void:
	_gate().send(UiKeys.I_LEARN_LIST, { "npc": npc_id() })

# ---------------------------------------------------------------- M3c2 WP-PACE（M3C2_PLAN §2.4）
## 主機規則（world_info 展開後的 rule_profile）：novice_learn_pct／novice_jing_pct／novice_learn_below
static func novice_rules() -> Dictionary:
	var rp: Variant = UiClient.world_info().get("rule_profile", {})
	return rp if rp is Dictionary else {}

## 這一列（向師父學、非生活技能、目前等級 < 門檻、而且倍率真的有加速）會不會吃到新手加速。
## combat_xp ≥ 0 時另外要實戰 < novice_xp_below（M3c2 審查：老手學新武功不算新手；同 Learning.novice_mults）
static func novice_applies(kind: String, level: int, rules: Dictionary = {}, combat_xp: int = -1) -> bool:
	if kind == "LIFE" or kind == "":
		return false
	var r := rules if not rules.is_empty() else novice_rules()
	var lp := int(r.get("novice_learn_pct", 100))
	var jp := int(r.get("novice_jing_pct", 100))
	if lp <= 100 and jp >= 100:
		return false
	if combat_xp >= 0 and r.has("novice_xp_below") and combat_xp >= int(r.get("novice_xp_below", 0)):
		return false
	return level < int(r.get("novice_learn_below", 40))

## 視窗上方那一行（玩家看的字：不帶【設計提案】之類的內部標記）
static func novice_header(rules: Dictionary = {}) -> String:
	var r := rules if not rules.is_empty() else novice_rules()
	return "新手期：%d 級以前向師父請教會加速。" % int(r.get("novice_learn_below", 40))

static func novice_tip(rules: Dictionary = {}) -> String:
	var r := rules if not rules.is_empty() else novice_rules()
	var t := "新手學藝加速（本伺服器規則）：%d 級以前每次請教熟練度 ×%s、精 ×%s" % [
		int(r.get("novice_learn_below", 40)), str(snappedf(int(r.get("novice_learn_pct", 100)) / 100.0, 0.01)),
		str(snappedf(int(r.get("novice_jing_pct", 100)) / 100.0, 0.01))]
	if r.has("novice_xp_below"):
		t += "；實戰 %d 以上就不算新手" % int(r.get("novice_xp_below", 0))
	return t
