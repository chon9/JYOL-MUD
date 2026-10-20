class_name LookPicker
extends Control
## 初始造型選擇器（M3C_PLAN §3.4 第 1 點；ART_REQUEST §9）：3×3 大格，每格是該造型的 idle 全身立繪（≥ 150×150）＋名稱；
## 依性別過濾（0＝布衣 player_m／player_f，1–8＝Looks.NAMES_M／NAMES_F）。選中框朱紅；
## 滑鼠點選或鍵盤（選擇器有焦點時）1–9 直接選、方向鍵移動。造型純外觀，不影響任何數值。

signal look_selected(look: int)

const COLS := 3   # 預設 3×3；主畫面「更換造型」視窗高度只有 552（HUD 上方），用 5 欄×2 列（set_columns）
const PORTRAIT_MIN := 150.0
const NAME_H := 26.0
const GAP := 8

var gender := "M"
var selected := 0
var cell_size := Vector2(196, 190)
var columns := COLS
var cells: Array = []        # LookCell（look 0..LOOK_MAX）
var grid: GridContainer
var _built := false

func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_PASS

func _ready() -> void:
	_ensure_built()

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	grid = GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(grid)
	for i in Looks.LOOK_MAX + 1:
		var c := LookCell.new()
		c.look = i
		c.custom_minimum_size = cell_size
		c.pressed.connect(_on_cell_pressed)
		grid.add_child(c)
		cells.append(c)
	_refresh()
	_fit()

## 格子大小（立繪區至少 150×150）；在加入場景樹之前或之後設定都可以
func set_cell_size(v: Vector2) -> void:
	cell_size = Vector2(maxf(v.x, PORTRAIT_MIN + 12.0), maxf(v.y, PORTRAIT_MIN + NAME_H + 12.0))
	if _built:
		for c in cells:
			(c as Control).custom_minimum_size = cell_size
		_fit()

func set_columns(n: int) -> void:
	columns = clampi(n, 1, Looks.LOOK_MAX + 1)
	if _built:
		grid.columns = columns
		_fit()

func _fit() -> void:
	var rows := ceili(float(cells.size()) / float(columns))
	custom_minimum_size = Vector2(cell_size.x * columns + GAP * (columns - 1), cell_size.y * rows + GAP * (rows - 1))

func set_gender(g: String) -> void:
	_ensure_built()
	gender = "F" if g == "F" else "M"
	_refresh()

func set_selected(i: int) -> void:
	_ensure_built()
	selected = i if Looks.valid(i) else 0
	_refresh()

## 目前顯示的 9 個選項：[{ look, name, art }]
func options() -> Array:
	return Looks.catalog(gender)

func _refresh() -> void:
	var cat := Looks.catalog(gender)
	for i in cells.size():
		var c: LookCell = cells[i]
		var e: Dictionary = cat[i]
		c.look = int(e["look"])
		c.look_name = str(e["name"])
		c.art = str(e["art"])
		c.texture = ArtRegistry.unit_texture(c.art, "PLAYER", "idle")
		c.is_selected = c.look == selected
		c.tooltip_text = "%d．%s" % [c.look + 1, c.look_name]
		c.queue_redraw()

func _on_cell_pressed(look: int) -> void:
	pick(look)
	grab_focus()

## 使用者選取（點選、鍵盤）：更新並發出 look_selected
func pick(look: int) -> void:
	if not Looks.valid(look):
		return
	set_selected(look)
	look_selected.emit(look)

func _gui_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var handled := handle_key(k.keycode)
	if handled:
		accept_event()

## 1–9 直接選第 N 格；方向鍵在格子內移動（上下跨列）。回傳是否處理
func handle_key(code: int) -> bool:
	if code >= KEY_1 and code <= KEY_9:
		var i := int(code - KEY_1)
		if i <= Looks.LOOK_MAX:
			pick(i)
			return true
		return false
	if code >= KEY_KP_1 and code <= KEY_KP_9:
		pick(int(code - KEY_KP_1))
		return true
	var n := Looks.LOOK_MAX + 1
	match code:
		KEY_LEFT:
			pick((selected + n - 1) % n)
		KEY_RIGHT:
			pick((selected + 1) % n)
		KEY_UP:
			pick(selected - columns if selected - columns >= 0 else selected)
		KEY_DOWN:
			pick(selected + columns if selected + columns < n else selected)
		_:
			return false
	return true

## 角色表 → 立繪用的 art ref：sheet.look（M3c）；舊主機沒有 → player_<性別>；都沒有 → player_m
static func sheet_look_ref(sheet: Dictionary) -> String:
	var look := str(sheet.get("look", ""))
	if look != "":
		return look
	var g := str(sheet.get("gender", ""))
	return "player_f" if g == "F" else "player_m"

## 角色表 → 立繪貼圖（找不到用 player_m）
static func sheet_look_texture(sheet: Dictionary) -> Texture2D:
	var tex := ArtRegistry.unit_texture(sheet_look_ref(sheet), "PLAYER", "idle")
	if tex == null:
		tex = ArtRegistry.unit_texture("player_m", "PLAYER", "idle")
	return tex


## 一格：暗底、idle 立繪（保持比例、底部對齊）、名稱牌、左上角快捷鍵數字；選中朱紅框、滑過金框
class LookCell extends Control:
	signal pressed(look: int)
	var look := 0
	var look_name := ""
	var art := ""
	var texture: Texture2D
	var is_selected := false
	var _hover := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func():
			_hover = true
			queue_redraw())
		mouse_exited.connect(func():
			_hover = false
			queue_redraw())

	func _gui_input(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit(look)
			accept_event()

	## 立繪區（名稱牌上方）
	func portrait_rect() -> Rect2:
		return Rect2(Vector2(6, 6), Vector2(size.x - 12, size.y - 12 - LookPicker.NAME_H))

	## 貼圖實際畫的位置（保持比例縮放、水平置中、底部對齊）
	func texture_rect() -> Rect2:
		var pr := portrait_rect()
		if texture == null:
			return Rect2(pr.position, Vector2.ZERO)
		var ts := texture.get_size()
		var k := minf(pr.size.x / maxf(ts.x, 1.0), pr.size.y / maxf(ts.y, 1.0))
		var ds := ts * k
		return Rect2(Vector2(pr.position.x + (pr.size.x - ds.x) / 2.0, pr.end.y - ds.y), ds)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, UiTheme.JY_SLOT.darkened(0.25) if not is_selected else Color("4a2018"))
		# 地面淡光：讓人物腳下有個落點
		var pr := portrait_rect()
		var floor_c := Vector2(pr.get_center().x, pr.end.y - 4.0)
		draw_set_transform(floor_c, 0.0, Vector2(1.0, 0.28))
		draw_circle(Vector2.ZERO, pr.size.x * 0.32, Color(0.95, 0.85, 0.6, 0.10 if not is_selected else 0.20))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if texture != null:
			draw_texture_rect(texture, texture_rect(), false)
		# 名稱牌
		var plate := Rect2(Vector2(6, size.y - 6 - LookPicker.NAME_H), Vector2(size.x - 12, LookPicker.NAME_H))
		draw_rect(plate, UiTheme.CINNABAR if is_selected else UiTheme.JY_WOOD)
		var font := UiTheme.find_font()
		if font == null:
			font = ThemeDB.fallback_font
		var fs := 17
		var tw := font.get_string_size(look_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(plate.get_center().x - tw / 2.0, plate.position.y + plate.size.y * 0.5 + fs * 0.36),
			look_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.JY_PARCHMENT if is_selected else UiTheme.JY_TEXT)
		# 快捷鍵數字
		draw_string(font, Vector2(10, 24), str(look + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			UiTheme.JY_GOLD_LIGHT if is_selected else UiTheme.JY_MUTED_LIGHT)
		# 外框
		if is_selected:
			draw_rect(r.grow(-1.5), UiTheme.CINNABAR, false, 3.0)
			draw_rect(r.grow(-5.0), Color(UiTheme.JY_GOLD_LIGHT, 0.55), false, 1.0)
		elif _hover:
			draw_rect(r.grow(-1.0), UiTheme.JY_GOLD, false, 2.0)
		else:
			draw_rect(r.grow(-0.5), UiTheme.JY_SLOT_EDGE, false, 1.0)
