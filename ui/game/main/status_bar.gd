class_name StatusBar
extends VBoxContainer
## 底部 HUD 左區（AUTHENTIC_UI_SPEC §6.1、§6.2、§7）：
## - 上方（帶 A）7 個單字圓章：食、水、錢、狀、善、學、戰。滑鼠移上去才顯示數值（黃底黑字提示框）；
##   飽食、飲水依程度變色（>50% 正常、20–50% 橘、<20% 紅）。
## - 下方（帶 B）4 條能量條：精（綠）、氣（紅）、神（黃）、內力（藍），條內置中「cur/max」。
## 七項屬性不再常駐（移到屬性窗）。戰鬥中由主畫面用 apply_battle_unit() 即時更新氣／內力／精，殘量低於 25% 時閃爍。
## M3a（M3A_PLAN §7.5、§7.9）：「狀」圖示顯示戰後持續狀態（sheet.conditions：中毒等）與剩餘時間，圓章染成第一個狀態的顏色；
## 「善」圖示在善惡接近門規底線（sect_info.warnings 含 morality）時染紅。

const BARS := ["jing", "qi", "shen", "neili"]
const BAR_LABELS := { "jing": "精", "qi": "氣", "shen": "神", "neili": "內力" }
const ICONS := ["food", "water", "money", "status", "morality", "learn", "combat"]
const ICON_GLYPHS := { "food": "食", "water": "水", "money": "錢", "status": "狀", "morality": "善", "learn": "學", "combat": "戰" }
const ICON_NAMES := { "food": "飲食", "water": "飲水", "money": "金錢", "status": "狀態", "morality": "善惡", "learn": "學點", "combat": "實戰" }
const BAR_W := 236.0
const BAR_H := 22.0
const LOW_FRAC := 0.25
const BLINK_PERIOD := 0.6

var bars: Dictionary = {}        # vital -> ProgressBar
var bar_texts: Dictionary = {}   # vital -> Label（"cur/max"）
var icons: Dictionary = {}       # icon id -> JyButton（SEAL）
var icon_values: Dictionary = {} # icon id -> 提示文字
var in_battle := false
var _base_status := "正常"        # sheet.status 的文字（沒有戰後持續狀態時顯示）
var _conds: Array = []            # sheet.conditions
var _conds_rx := 0                # 收到角色表的本機時刻（倒數用）
var _conds_shown_s := -1
var _built := false

func _ready() -> void:
	ensure_built()

func ensure_built() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 5)
	var row := UiBuild.hbox(self, 4)
	row.custom_minimum_size = Vector2(0, 28)
	for id in ICONS:
		var b := UiBuild.jy_button(row, JyButton.Style.SEAL, ICON_NAMES[id], Callable(), ICON_GLYPHS[id])
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_HELP
		icons[id] = b
	for v in BARS:
		var cell := UiBuild.hbox(self, 4)
		var l := UiBuild.label(cell, BAR_LABELS[v], 15 if v != "neili" else 13)
		l.custom_minimum_size = Vector2(30, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", UiTheme.brush_font(0.4))
		var b := ProgressBar.new()
		b.show_percentage = false
		b.custom_minimum_size = Vector2(BAR_W - 34.0, BAR_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var grad: Array = UiTheme.VITAL_GRADIENTS[v]
		UiTheme.vital_bar(b, grad[0], grad[1])
		cell.add_child(b)
		var t := Label.new()
		t.text = "0/0"
		t.add_theme_font_size_override("font_size", 13)
		t.add_theme_constant_override("outline_size", 3)
		t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		if v == "shen":
			# 神是淺黃條：近白字加 3 px 半透明描邊看不清（審查 round 4），改純白字＋6 px 實心黑描邊
			t.add_theme_color_override("font_color", Color.WHITE)
			t.add_theme_constant_override("outline_size", 6)
			t.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.0, 1.0))
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(t)
		bars[v] = b
		bar_texts[v] = t

## sheet = 3.9.1
func apply_sheet(sheet: Dictionary) -> void:
	ensure_built()
	var vit: Dictionary = sheet.get("vitals", {})
	for v in BARS:
		_set_vital(v, UiBuild.num(vit.get(v, 0)), UiBuild.num(vit.get(v + "_max", 0)))
	var food := UiBuild.num(vit.get("food", 0))
	var food_max := maxi(1, UiBuild.num(vit.get("food_max", 100)))
	var water := UiBuild.num(vit.get("water", 0))
	var water_max := maxi(1, UiBuild.num(vit.get("water_max", 100)))
	_set_icon("food", "飽食 %d / %d" % [food, food_max], StatusBar.level_tint(float(food) / food_max))
	_set_icon("water", "飲水 %d / %d" % [water, water_max], StatusBar.level_tint(float(water) / water_max))
	_set_icon("money", "銀兩 %d 兩" % UiBuild.num(sheet.get("money", 0)))
	var st: Variant = sheet.get("status", sheet.get("statuses", []))
	var st_text := "正常"
	if st is Array and not (st as Array).is_empty():
		st_text = "、".join(PackedStringArray((st as Array).map(func(x): return str(x.get("name", x)) if x is Dictionary else str(x))))
	elif st is String and st != "":
		st_text = st
	_base_status = st_text
	_conds = SectUi.conditions(sheet)
	_conds_rx = int(sheet.get(CooldownTracker.RX_KEY, Time.get_ticks_msec()))
	_conds_shown_s = -1
	_update_conditions()
	var mwarn := SectUi.warned(sheet, "morality")
	_set_icon("morality", "善惡 %d%s" % [UiBuild.num(sheet.get("morality", 0)), "（%s）" % UiKeys.SECT_WARN_TIP if mwarn else ""],
		UiTheme.LEVEL_LOW if mwarn else Color(0, 0, 0, 0))
	var cap := UiBuild.num(sheet.get("learn_points_cap", 0))
	_set_icon("learn", "學點 %d%s" % [UiBuild.num(sheet.get("learn_points", 0)), " / %d" % cap if cap > 0 else ""])
	_set_icon("combat", "實戰 %d" % UiBuild.num(sheet.get("combat_xp", 0)))

## 戰鬥快照的我（精、氣、內力即時更新；神沿用 sheet）
func apply_battle_unit(u: Dictionary) -> void:
	ensure_built()
	for v in ["jing", "qi", "neili"]:
		if u.has(v) and u.has(v + "_max"):
			_set_vital(v, UiBuild.num(u[v]), UiBuild.num(u[v + "_max"]))

func _set_vital(v: String, cur: int, mx: int) -> void:
	UiBuild.set_bar(bars[v], cur, mx)
	(bar_texts[v] as Label).text = "%d/%d" % [cur, mx]

func _set_icon(id: String, tip: String, tint: Color = Color(0, 0, 0, 0)) -> void:
	icon_values[id] = tip
	var b: JyButton = icons[id]
	b.tooltip_text = "%s：%s" % [ICON_NAMES[id], tip] if not tip.begins_with(ICON_NAMES[id]) else tip
	if b.tint != tint:
		b.tint = tint
		b.queue_redraw()

## 飽食、飲水圖示色：>50% 預設、20–50% 橘、<20% 紅
static func level_tint(frac: float) -> Color:
	if frac < 0.2:
		return UiTheme.LEVEL_LOW
	if frac <= 0.5:
		return UiTheme.LEVEL_WARN
	return Color(0, 0, 0, 0)

func icon_text(id: String) -> String:
	return str(icon_values.get(id, ""))

## 「狀」：戰後持續狀態與剩餘時間（每秒更新一次）
func _update_conditions(now_ms: int = -1) -> void:
	if _conds.is_empty():
		_set_icon("status", "狀態：%s" % _base_status)
		return
	var parts: PackedStringArray = []
	var longest := 0
	for c in _conds:
		if not (c is Dictionary):
			continue
		var left := SectUi.left_now(float(c.get("left_s", 0)), _conds_rx, now_ms)
		longest = maxi(longest, ceili(left))
		parts.append(SectUi.condition_text(c, left))
	_conds_shown_s = longest
	var first: Dictionary = _conds[0] if _conds[0] is Dictionary else {}
	_set_icon("status", "狀態：%s" % "、".join(parts), Color.from_string(str(first.get("color", "#3c9a3c")), Color("3c9a3c")))

## 戰鬥中殘量 < 25% 閃爍
func _process(_delta: float) -> void:
	if not _built:
		return
	if not _conds.is_empty():
		var longest := 0
		for c in _conds:
			if c is Dictionary:
				longest = maxi(longest, ceili(SectUi.left_now(float(c.get("left_s", 0)), _conds_rx)))
		if longest != _conds_shown_s:
			_update_conditions()
	var on := in_battle and fmod(Time.get_ticks_msec() / 1000.0, BLINK_PERIOD) < BLINK_PERIOD / 2.0
	for v in BARS:
		var b: ProgressBar = bars[v]
		var low := b.max_value > 1.0 and b.value / b.max_value < LOW_FRAC
		var a := 0.45 if (low and on) else 1.0
		if not is_equal_approx(b.self_modulate.a, a):
			b.self_modulate.a = a
