class_name LanternMenu
extends VBoxContainer
## 右緣燈籠選單（AUTHENTIC_UI_SPEC §8.1）：武功（Ctrl+1）、屬性（Ctrl+2）、裝備（Ctrl+3）、指令（Ctrl+4）、系統（Ctrl+5），
## 由上而下直排；下方紅色中國結是「燈籠縮放開關」，點一下收合或展開燈籠（Esc 最後也會收合）。
## 燈籠是 JyButton（LANTERN）：可讀名稱「武功(Ctrl+1)」，畫面上直排兩個黑色毛筆字。

signal panel_requested(pid: String)

const LANTERN_SIZE := Vector2(52, 60)

var lanterns: Dictionary = {}     # pid -> JyButton
var lantern_box: VBoxContainer
var knot: ChineseKnot
var collapsed := false
var _built := false

func _ready() -> void:
	ensure_built()

func ensure_built() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	lantern_box = UiBuild.vbox(self, 8)
	lantern_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in UiKeys.PANELS.size():
		var pid: String = UiKeys.PANELS[i]
		var b := UiBuild.lantern(lantern_box, "%s(Ctrl+%d)" % [UiKeys.PANEL_LABELS[pid], i + 1], func(): panel_requested.emit(pid))
		b.custom_minimum_size = LANTERN_SIZE
		b.tooltip_text = "查看%s（快捷鍵：Ctrl+%d）" % [UiKeys.PANEL_LABELS[pid], i + 1]
		lanterns[pid] = b
	knot = ChineseKnot.new()
	knot.tooltip_text = "燈籠縮放開關"
	knot.pressed.connect(toggle_collapsed)
	add_child(knot)
	set_collapsed(UiSettings.get_bool("ui.lanterns_collapsed"), false)

func toggle_collapsed() -> void:
	set_collapsed(not collapsed)

func set_collapsed(on: bool, persist := true) -> void:
	collapsed = on
	lantern_box.visible = not on
	if persist:
		UiSettings.set_value("ui.lanterns_collapsed", on)

## 中國結：紅色菱形結＋5 條流蘇（程式繪製）
class ChineseKnot extends Button:
	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(52, 64)
		text = "燈籠縮放開關"
		clip_text = true
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			add_theme_color_override(c, Color(0, 0, 0, 0))
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var cx := size.x / 2.0
		var red := Color("c81e1e").lightened(0.15 if is_hovered() else 0.0)
		draw_line(Vector2(cx, 0), Vector2(cx, 10), Color("1a1008"), 2.0)
		# 圓珠
		draw_circle(Vector2(cx, 14), 5.0, UiTheme.JY_GOLD)
		draw_circle(Vector2(cx, 14), 3.0, Color("2a8a5a"))
		# 菱形結
		var c := Vector2(cx, 30)
		var r := 11.0
		var dia := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(dia, red)
		var closed := dia.duplicate()
		closed.append(dia[0])
		draw_polyline(closed, Color("6a0a0a"), 1.5, true)
		draw_line(c + Vector2(-r * 0.5, -r * 0.5), c + Vector2(r * 0.5, r * 0.5), Color("6a0a0a"), 1.0, true)
		draw_line(c + Vector2(r * 0.5, -r * 0.5), c + Vector2(-r * 0.5, r * 0.5), Color("6a0a0a"), 1.0, true)
		# 流蘇 5 條
		for i in 5:
			var x := cx + (i - 2) * 2.5
			draw_line(Vector2(x, c.y + r), Vector2(x + (i - 2) * 0.8, size.y - 2.0), red, 1.5, true)
