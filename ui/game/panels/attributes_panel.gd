class_name AttributesPanel
extends VBoxContainer
## 屬性窗（Ctrl+2，AUTHENTIC_UI_SPEC §8.2：琥珀框，由主畫面套）：兩欄排列，欄位名黃字（AccentLabel）、數值白字。
## 精／氣／神／內力（cur/max）、負重，七項屬性（有效／基礎）、衍生數值、江湖閱歷、門派、記錄點。
## 戰鬥中圓盤「屬」也開這個窗（唯讀）。
## M2：善惡旁標出名字顏色的陣營（善／中立／惡）；最下面列出自己的屍體（sheet.my_corpses：地點、件數、保護期或消失倒數）。
## M3a（M3A_PLAN §7.9）：sect_info.warnings 裡的屬性（善惡、PK值、殺氣）數字改紅色並加提示「接近門規底線」；
## 門派一列附門派技能等級、師父、停止傳功／禁止學武；公敵列出門派。
## M3c（M3C_PLAN §3.4 第 3 點）：左邊頭像區顯示目前 sheet.look 的立繪與「造型：X」；「更換造型」→ look_change_requested
## （主畫面開 LookDialog，送 set_look）。戰鬥中（唯讀）按鈕停用。

signal look_change_requested

const PORTRAIT_SIZE := Vector2(132, 168)

var gate: IntentGate
var header: Label
var vital_grid: GridContainer
var attr_grid: GridContainer
var derived_grid: GridContainer
var progress_grid: GridContainer
var misc_label: Label
var value_labels: Dictionary = {}   # 欄位名 -> 數值 Label（門規警示改色用）
var portrait: TextureRect
var look_label: Label
var btn_look: Button
var _built := false

func _ready() -> void:
	if not _built:
		_build()

func _build() -> void:
	_built = true
	add_theme_constant_override("separation", 8)
	header = UiBuild.label(self, "", 17)
	var row := UiBuild.hbox(self, 28)
	# M3c：頭像區（立繪、造型名、更換造型）
	var c0 := UiBuild.vbox(row, 6)
	var pf := PanelContainer.new()
	pf.add_theme_stylebox_override("panel", UiFrame.style(UiFrame.Kind.SLOT))
	c0.add_child(pf)
	portrait = TextureRect.new()
	portrait.name = "LookPortrait"
	portrait.custom_minimum_size = PORTRAIT_SIZE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pf.add_child(portrait)
	look_label = UiBuild.label(c0, "", 15, true)
	look_label.custom_minimum_size = Vector2(PORTRAIT_SIZE.x, 0)
	look_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn_look = UiBuild.button(c0, "更換造型", func(): look_change_requested.emit(), PORTRAIT_SIZE.x)
	btn_look.tooltip_text = "純外觀、免費；拜入門派期間一律穿門派服裝"
	var c1 := UiBuild.vbox(row, 6)
	vital_grid = _grid(c1)
	c1.add_child(HSeparator.new())
	attr_grid = _grid(c1, 3)
	var c2 := UiBuild.vbox(row, 6)
	derived_grid = _grid(c2)
	c2.add_child(HSeparator.new())
	progress_grid = _grid(c2)
	add_child(HSeparator.new())
	misc_label = UiBuild.label(self, "", 15, true)

func _grid(parent: Node, cols: int = 2) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 3)
	parent.add_child(g)
	return g

## 一列：黃色欄位名＋白色數值（＋第三欄）
func _cells(g: GridContainer, values: Array) -> void:
	for i in values.size():
		var l := UiBuild.label(g, str(values[i]), 16)
		if i == 0:
			UiBuild.accent(l)
		elif i >= 2:
			UiBuild.muted(l)
		elif i == 1:
			value_labels[str(values[0])] = l

## 門規警示：數字改紅、加提示（§7.9）
func _warn(field: String, on: bool) -> void:
	var l: Label = value_labels.get(field, null)
	if l == null:
		return
	if on:
		l.add_theme_color_override("font_color", UiTheme.JY_RED)
		l.tooltip_text = UiKeys.SECT_WARN_TIP
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	else:
		l.remove_theme_color_override("font_color")
		l.tooltip_text = ""

func is_warned(field: String) -> bool:
	var l: Label = value_labels.get(field, null)
	return l != null and l.has_theme_color_override("font_color")

func apply_sheet(s: Dictionary) -> void:
	if not _built:
		_build()
	header.text = "%s%s（%s）　生日 %d 月　出生於%s" % [str(s.get("name", "")), foreign_mark(s),   # M3c2 WP-CARRY：外來角色
		UiKeys.GENDER_LABELS.get(str(s.get("gender", "")), ""), UiBuild.num(s.get("birth_month", 0)),
		UiClient.name_of("regions", str(s.get("birth_city", "")))]
	apply_look(s)
	var vit: Dictionary = s.get("vitals", {})
	UiBuild.clear(vital_grid)
	for v in ["jing", "qi", "shen", "neili"]:
		_cells(vital_grid, ["%s／%sMax" % [UiKeys.VITAL_NAMES[v], UiKeys.VITAL_NAMES[v]],
			"%d / %d" % [UiBuild.num(vit.get(v, 0)), UiBuild.num(vit.get(v + "_max", 0))]])
	_cells(vital_grid, ["負重／負重Max", "%d / %d" % [UiBuild.num(s.get("carry", 0)), UiBuild.num(s.get("carry_max", 0))]])
	UiBuild.clear(attr_grid)
	var attrs: Dictionary = s.get("attrs", {})
	var base: Dictionary = s.get("attrs_base", {})
	for a in UiKeys.ATTR_IDS:
		var eff := UiBuild.num(attrs.get(a, 0))
		var b := UiBuild.num(base.get(a, eff))
		_cells(attr_grid, [UiClient.attr_name(a), eff, "（基礎 %d）" % b if b != eff else ""])
	UiBuild.clear(derived_grid)
	_cells(derived_grid, ["武器強度", UiBuild.num(s.get("weapon_power", 0))])
	_cells(derived_grid, ["防具強度", UiBuild.num(s.get("armor_power", 0))])
	_cells(derived_grid, ["武功等級上限", UiBuild.num(s.get("art_level_cap", 0))])
	UiBuild.clear(progress_grid)
	value_labels.clear()
	_cells(progress_grid, ["實戰經驗", UiBuild.num(s.get("combat_xp", 0))])
	var cap := UiBuild.num(s.get("learn_points_cap", 0))
	_cells(progress_grid, ["學習點數", "%d%s" % [UiBuild.num(s.get("learn_points", 0)), " / %d" % cap if cap > 0 else ""]])
	# 江湖歷練（STORY_PLAN §6.7、D18：角色表 lilian；舊主機是 lili），放在名聲旁邊
	_cells(progress_grid, ["江湖歷練", AttributesPanel.lilian(s)])
	_cells(progress_grid, ["名聲", UiBuild.num(s.get("fame", 0))])
	var align := str(s.get("align", ""))
	_cells(progress_grid, ["善惡", "%d%s" % [UiBuild.num(s.get("morality", 0)), "（%s）" % UiKeys.ALIGN_LABELS[align] if UiKeys.ALIGN_LABELS.has(align) else ""]])
	_cells(progress_grid, ["殺氣", UiBuild.num(s.get("killing_intent", 0))])
	_cells(progress_grid, ["PK值", UiBuild.num(s.get("pk", 0))])
	_cells(progress_grid, ["銀兩", UiBuild.num(s.get("money", 0))])
	for k in UiKeys.SECT_WARN_LABELS:
		_warn(UiKeys.SECT_WARN_LABELS[k], SectUi.warned(s, k))
	var sect := str(s.get("sect_name", ""))
	var resp: Dictionary = s.get("respawn", {})
	var loc: Dictionary = s.get("location", {})
	# 記錄點另起一行：同一行太長時「…死亡時回出生 / 地）」會斷成孤字（審查 round 3）
	misc_label.text = "門派：%s　　位置：%s・%s\n記錄點：%s" % [sect if sect != "" else "無",
		str(loc.get("region_name", "")), str(loc.get("room_name", "")),
		str(resp.get("room_name", "")) if str(resp.get("room_name", "")) != "" else "未設定（死亡時回出生地）"]
	var sect_lines := SectUi.sect_lines(s)
	if not sect_lines.is_empty():
		misc_label.text += "
" + "
".join(sect_lines)
	var org_line := AttributesPanel.org_line(s)
	if org_line != "":
		misc_label.text += "
" + org_line
	var corpses := AttributesPanel.corpse_lines(s)
	if corpses != "":
		misc_label.text += "
" + corpses

## M3c：頭像區。sheet.look＝目前實際顯示的外觀（入派中是門派服裝）；appearance＝自己選的造型
func apply_look(s: Dictionary) -> void:
	portrait.texture = LookPicker.sheet_look_texture(s)
	look_label.text = AttributesPanel.look_text(s)
	btn_look.disabled = bool(s.get("in_battle", false))
	btn_look.tooltip_text = "戰鬥中不能更換造型" if btn_look.disabled else "純外觀、免費；拜入門派期間一律穿門派服裝"

## 「造型：書生」；入派中加「（穿門派服裝）」
static func look_text(s: Dictionary) -> String:
	var ap := UiBuild.num(s.get("appearance", 0))
	var t := "造型：%s" % Looks.name_of(str(s.get("gender", "M")), ap if Looks.valid(ap) else 0)
	if str(s.get("sect", "")) != "":
		t += String.chr(10) + "（穿門派服裝）"
	return t

## M3b（M3B_PLAN §5.3、§6 角色表 org、societies）：「組織：江湖小築（堂主・鐵掌）　會籍：天地會」
static func org_line(s: Dictionary) -> String:
	var parts: PackedStringArray = []
	var o := OrgUi.sheet_org(s)
	if str(o.get("name", "")) != "":
		var extra: PackedStringArray = []
		if str(o.get("rank_name", "")) != "":
			extra.append(str(o["rank_name"]))
		if str(o.get("title", "")) != "":
			extra.append(str(o["title"]))
		parts.append("組織：%s%s" % [str(o["name"]), "（%s）" % "・".join(extra) if not extra.is_empty() else ""])
	var soc := OrgUi.societies(s)
	if not soc.is_empty():
		parts.append("會籍：" + "、".join(PackedStringArray(soc)))
	return "　".join(parts)

static func lilian(s: Dictionary) -> int:
	return UiBuild.num(s.get("lilian", s.get("lili", 0)))

## 自己的屍體（4.5.1 my_corpses）：「我的屍體：小溪邊 3 件（保護期還剩 5 分 0 秒…）」
static func corpse_lines(s: Dictionary) -> String:
	var out: PackedStringArray = []
	var mc: Variant = s.get("my_corpses", [])
	if not (mc is Array):
		return ""
	for c in mc:
		if c is Dictionary:
			out.append("我的屍體：%s %d 件，%s" % [str(c.get("room_name", "?")), UiBuild.num(c.get("n_items", 0)),
				UiSocial.corpse_status(c, UiBuild.num(c.get("left_s", 0)))])
	return "
".join(out)

## M3c2 WP-CARRY（M3C2_PLAN §5.6）：外來角色名字後加「（外來）」。角色表沒有這個欄位 → 查角色清單（summary.foreign）
static func foreign_mark(s: Dictionary) -> String:
	if bool(s.get("foreign", false)):
		return "（外來）"
	var cid := str(s.get("char_id", ""))
	for row in UiClient.char_list():
		if row is Dictionary and str(row.get("char_id", "")) == cid and cid != "":
			return "（外來）" if bool(row.get("foreign", false)) else ""
	return ""
