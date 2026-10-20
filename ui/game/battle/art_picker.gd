class_name ArtPicker
extends PanelContainer
## 招式選擇器（M1_PLAN 3.12）：選武功 → 招式（未解鎖灰色）→ 成數滑桿 1–10（預設 10；
## 顯示內力消耗 = ceil(cost_inner × 成數 / 5)）→「選擇目標」。範圍招式（M3a §5.3）在射程後面標形狀（小十字、直線…）。

signal picked(art_id: String, move_id: String, tenths: int, move_range: int)
signal cancelled

var arts: Array = []
var neili := 0
var jing := 0
var art_box: VBoxContainer
var move_box: VBoxContainer
var slider: HSlider
var tenths_label: Label
var cost_label: Label
var btn_ok: Button
var sel_art: Dictionary = {}
var sel_move: Dictionary = {}
var _built := false

func _ready() -> void:
	if not _built:
		_build()

func _build() -> void:
	_built = true
	add_theme_stylebox_override("panel", UiTheme.popup_panel_style())
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(520, 0)
	var v := UiBuild.vbox(self, 6)
	UiBuild.label(v, "出招", 20)
	var cols := UiBuild.hbox(v, 12)
	var c1 := UiBuild.vbox(cols, 4)
	UiBuild.muted(UiBuild.label(c1, "武功", 15))
	art_box = UiBuild.vbox(c1, 4)
	c1.custom_minimum_size = Vector2(170, 0)
	var c2 := UiBuild.vbox(cols, 4)
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiBuild.muted(UiBuild.label(c2, "招式", 15))
	move_box = UiBuild.vbox(c2, 4)
	var srow := UiBuild.hbox(v, 8)
	UiBuild.label(srow, "成數")
	slider = HSlider.new()
	slider.min_value = 1
	slider.max_value = 10
	slider.step = 1
	slider.value = 10
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(200, 0)
	slider.value_changed.connect(func(_v): _update_cost())
	srow.add_child(slider)
	tenths_label = UiBuild.label(srow, "10 成")
	cost_label = UiBuild.label(v, "", 15)
	var brow := UiBuild.hbox(v, 8)
	btn_ok = UiBuild.button(brow, "選擇目標", _on_ok)
	UiBuild.button(brow, "取消", func():
		visible = false
		cancelled.emit())

## arts = 3.9.3 我的單位 arts；neili／jing 用來提示資源不足
func open(p_arts: Array, p_neili: int, p_jing: int) -> void:
	if not _built:
		_build()
	arts = p_arts
	neili = p_neili
	jing = p_jing
	sel_art = {}
	sel_move = {}
	slider.value = 10
	UiBuild.clear(art_box)
	for a in arts:
		if not (a is Dictionary):
			continue
		var b := UiBuild.button(art_box, "%s（%d 級）" % [str(a.get("name", a.get("id", ""))), UiBuild.num(a.get("level", 0))])
		b.pressed.connect(select_art.bind(a))
	if not arts.is_empty() and arts[0] is Dictionary:
		select_art(arts[0])
	else:
		UiBuild.clear(move_box)
	_update_cost()
	visible = true

static func move_usable(a: Dictionary, m: Dictionary) -> bool:
	return UiBuild.num(m.get("unlock_level", 1)) <= UiBuild.num(a.get("level", 0)) and bool(m.get("usable", true))

func select_art(a: Dictionary) -> void:
	sel_art = a
	sel_move = {}
	UiBuild.clear(move_box)
	var best: Dictionary = {}
	for m in a.get("moves", []):
		if not (m is Dictionary):
			continue
		var usable := move_usable(a, m)
		var shape := BattleScreen.move_aoe(a, str(a.get("id", "")), str(m.get("id", "")))
		var t := "%s　射程 %d%s　內力 %d%s" % [str(m.get("name", m.get("id", ""))), UiBuild.num(m.get("range", 1)),
			"　" + str(UiKeys.AOE_LABELS.get(shape, shape)) if shape != "SINGLE" else "",
			UiBuild.num(m.get("cost_inner", 0)), "" if usable else "（%d 級解鎖）" % UiBuild.num(m.get("unlock_level", 1))]
		var b := UiBuild.button(move_box, t)
		b.disabled = not usable
		b.toggle_mode = true
		b.set_meta("move_id", str(m.get("id", "")))
		b.pressed.connect(select_move.bind(m))
		if usable:
			best = m   # 預設選最後一個（最高階）可用招式
	if not best.is_empty():
		select_move(best)
	_update_cost()

func select_move(m: Dictionary) -> void:
	sel_move = m
	for b in move_box.get_children():
		if b is Button:
			b.set_pressed_no_signal(str(b.get_meta("move_id", "")) == str(m.get("id", "")))
	_update_cost()

func tenths() -> int:
	return int(slider.value)

func current_cost() -> int:
	return UiKeys.inner_cost(UiBuild.num(sel_move.get("cost_inner", 0)), tenths())

func _update_cost() -> void:
	if not _built:
		return
	tenths_label.text = "%d 成" % tenths()
	if sel_move.is_empty():
		cost_label.text = "請選擇招式"
		btn_ok.disabled = true
		return
	var cost := current_cost()
	var cj := UiBuild.num(sel_move.get("cost_jing", 0))
	var lack := cost > neili or cj > jing
	cost_label.text = "內力消耗 %d（目前 %d）%s%s" % [cost, neili, "　精 %d" % cj if cj > 0 else "", "　資源不足" if lack else ""]
	btn_ok.disabled = lack

func _on_ok() -> void:
	if sel_art.is_empty() or sel_move.is_empty():
		return
	visible = false
	picked.emit(str(sel_art.get("id", "")), str(sel_move.get("id", "")), tenths(), UiBuild.num(sel_move.get("range", 1)))
