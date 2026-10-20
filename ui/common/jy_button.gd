class_name JyButton
extends Button
## 程式繪製的原作風格按鈕（AUTHENTIC_UI_SPEC §4.4、§8.1、§8.5、§12.2）。Button.text 是完整的可讀名稱
## （提示框、無障礙、UI driver 用），畫面上畫的是 glyph（預設 = text 的前幾個字）。
## 樣式：
## - DISC：戰鬥指令圓盤（徑向漸層、深色邊、黑色毛筆字）
## - BRONZE：指令窗青銅方鈕（浮雕字）
## - LANTERN：右緣燈籠（橘紅橢圓本體、上下深色蓋、直排兩字；hover 變亮並輕微擺動）
## - CLOSE：⊠ 關閉鈕（羊皮紙底、暗邊、✕）
## - SEAL：單字圓章（HUD 狀態圖示、飛鴿傳書），tint 可依程度變色
## - CONFIRM／CANCEL：青銅方鈕，✔／✘
## - SLOT：栗色凹格（物品格），glyph 是物品名前兩字，count 疊在右下
## drag_payload 不為空時可以拖曳（左鍵或右鍵，原作是右鍵拖到熱鍵列），資料是 { "jy_hotbar": payload }。

enum Style { DISC, BRONZE, LANTERN, CLOSE, SEAL, CONFIRM, CANCEL, SLOT }

const DRAG_THRESHOLD := 6.0

var style := Style.DISC
var glyph := ""                      # 畫在鈕面上的字；空 = 依 text 推
var tint := Color(0, 0, 0, 0)        # SEAL：圓章底色（透明 = 預設金）
var count := 0                       # SLOT：右下數量（0 = 不畫）
var marked := false                  # SLOT：紅框（例如已裝備）；BRONZE：選取中
var cooldown_text := ""              # 冷卻中的倒數「（7 秒）」：鈕面變暗，名稱上移，下一行畫倒數（鈕面讀起來 =「修煉（7 秒）」）
var drag_payload := ""
var hotkey_text := ""                # 左上角小字（F1…）

var _rpress := Vector2(-1, -1)
var _swing := 0.0
var _hide_face := false              # 冷卻中：各樣式先不畫名稱，由冷卻層統一畫兩行

func _init(p_style: int = Style.DISC, p_text: String = "", p_glyph: String = "") -> void:
	style = p_style
	text = p_text
	glyph = p_glyph
	clip_text = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(c, Color(0, 0, 0, 0))
	custom_minimum_size = default_size(p_style)
	if tooltip_text == "":
		tooltip_text = p_text
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

static func default_size(s: int) -> Vector2:
	match s:
		Style.DISC:
			return Vector2(40, 40)
		Style.BRONZE:
			return Vector2(44, 44)
		Style.LANTERN:
			return Vector2(52, 60)
		Style.CLOSE:
			return Vector2(18, 18)
		Style.SEAL:
			return Vector2(28, 28)
		Style.CONFIRM, Style.CANCEL:
			return Vector2(32, 32)
		Style.SLOT:
			return Vector2(44, 44)
	return Vector2(40, 40)

## 鈕面上要畫的字
func face() -> String:
	if glyph != "":
		return glyph
	match style:
		Style.CLOSE:
			return "✕"
		Style.CONFIRM:
			return "✔"
		Style.CANCEL:
			return "✘"
		Style.LANTERN:
			return text.get_slice("(", 0).left(2)
		Style.SLOT:
			return text.left(2)
	return text.get_slice("(", 0).left(2)

## 鈕面上實際畫出來的字（冷卻中 = 名稱 + 倒數，例如「修煉（7 秒）」）；測試、UI driver 用它核對畫面
func visible_text() -> String:
	return face() + cooldown_text

func set_cooldown_text(t: String) -> void:
	if cooldown_text != t:
		cooldown_text = t
		queue_redraw()

func set_glyph(g: String) -> void:
	if glyph != g:
		glyph = g
		queue_redraw()

func _process(delta: float) -> void:
	if style == Style.LANTERN:
		var want := 1.0 if is_hovered() and not disabled else 0.0
		if not is_equal_approx(_swing, want) or want > 0.0:
			_swing = move_toward(_swing, want, delta * 3.0)
			queue_redraw()

# ---------------------------------------------------------------- 拖曳

func _get_drag_data(_at: Vector2) -> Variant:
	if drag_payload == "":
		return null
	set_drag_preview(_preview())
	return { "jy_hotbar": drag_payload, "source": self }

func _preview() -> Control:
	var p := JyButton.new(Style.SLOT if style == Style.SLOT else Style.BRONZE, text, face())
	p.modulate = Color(1, 1, 1, 0.8)
	return p

func _gui_input(event: InputEvent) -> void:
	if drag_payload == "":
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_RIGHT:
		_rpress = mb.position if mb.pressed else Vector2(-1, -1)
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _rpress.x >= 0.0 and (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		if mm.position.distance_to(_rpress) > DRAG_THRESHOLD:
			_rpress = Vector2(-1, -1)
			force_drag({ "jy_hotbar": drag_payload, "source": self }, _preview())
			accept_event()

# ---------------------------------------------------------------- 繪製

func _draw() -> void:
	var font := UiTheme.brush_font(0.6) if style in [Style.DISC, Style.LANTERN, Style.BRONZE] else UiTheme.find_font()
	if font == null:
		font = ThemeDB.fallback_font
	var hot := is_hovered() and not disabled
	var down := is_pressed() and not disabled
	_hide_face = cooldown_text != ""
	match style:
		Style.DISC:
			_draw_disc(font, hot, down)
		Style.BRONZE, Style.CONFIRM, Style.CANCEL:
			_draw_bronze(font, hot, down)
		Style.LANTERN:
			_draw_lantern(font, hot)
		Style.CLOSE:
			_draw_close(font, hot, down)
		Style.SEAL:
			_draw_seal(font, hot)
		Style.SLOT:
			_draw_slot(font, hot)
	_hide_face = false
	if cooldown_text != "":
		_draw_cooldown(font)
	if hotkey_text != "":
		var f2 := UiTheme.find_font() if UiTheme.find_font() != null else ThemeDB.fallback_font
		draw_string_outline(f2, Vector2(3, 11), hotkey_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.8))
		draw_string(f2, Vector2(3, 11), hotkey_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiTheme.JY_GOLD_LIGHT)

const JY_COOL := Color("ffe080")
const JY_COOL_NAME := Color("f0e2c0")
## 不能用（例如戰鬥中的熱鍵列）時冷卻層的字改用暗色，跟其他灰掉的格子一致（M3a 審查：「查看（2 秒）」在戰鬥中看起來像能按）
const JY_COOL_NAME_OFF := Color("8a7a5c")
const JY_COOL_OFF := Color("9a8a60")

## 冷卻層：整格變暗；名稱（亮米色）在上、倒數「（7 秒）」（亮黃、黑描邊）在下，兩行都依格寬縮放到放得下。
## 兩行連起來就是按鈕文字「修煉（7 秒）」；左上角的 F1 小字照畫（在這之後）。
func _draw_cooldown(font: Font) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
	var avail := size.x - 4.0
	var nm := face()
	if nm != "":
		var fs1 := _fit_size(font, nm, avail, size.y * 0.32)
		_draw_centered_at(font, nm, fs1, size.y * 0.42, JY_COOL_NAME_OFF if disabled else JY_COOL_NAME)
	var fs2 := _fit_size(font, cooldown_text, avail, size.y * 0.3)
	_draw_centered_at(font, cooldown_text, fs2, size.y * 0.8 if nm != "" else size.y * 0.5, JY_COOL_OFF if disabled else JY_COOL)

## 字級：不超過 max_fs，寬度放得進 avail（最小 8）
static func _fit_size(font: Font, s: String, avail: float, max_fs: float) -> int:
	var fs := maxi(8, int(max_fs))
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if w > avail and w > 0.0:
		fs = maxi(8, int(floor(fs * avail / w)))
	return fs

## 以 cy 為垂直中心、水平置中畫一行字（黑描邊）
func _draw_centered_at(font: Font, s: String, fs: int, cy: float, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2((size.x - w) / 2.0, cy + fs * 0.36)
	draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.9))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _center_text(font: Font, s: String, fs: int, col: Color, off := Vector2.ZERO, outline := 0, outline_col := Color(0, 0, 0, 0.8)) -> void:
	if s == "" or _hide_face:
		return
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := size / 2.0 + off + Vector2(-w / 2.0, fs * 0.36)
	if outline > 0:
		draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, outline_col)
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

## 戰鬥圓盤：徑向漸層 #F2E8D0→#C8B48C、2 px 深邊、黑色毛筆字；hover 金邊；按下下移 1 px 變暗；不能用：#8A7A5C 底
func _draw_disc(font: Font, hot: bool, down: bool) -> void:
	var r := minf(size.x, size.y) / 2.0 - 1.0
	var c := size / 2.0 + (Vector2(0, 1) if down else Vector2.ZERO)
	var inner := Color("f2e8d0")
	var outer := Color("c8b48c")
	var ink := Color("111111")
	if disabled:
		# 不能用：更暗、去色的底＋淡掉的字＋一道斜線，小視窗也分得出來（M3a 審查 C7：以前只比可用的深一點）
		inner = Color("6e665a")
		outer = Color("4e483f")
		ink = Color(0.78, 0.74, 0.66, 0.45)
	if down:
		inner = inner.darkened(0.1)
		outer = outer.darkened(0.1)
	draw_circle(c + Vector2(1, 2), r, Color(0, 0, 0, 0.35))
	for i in 8:
		var k := float(i) / 8.0
		draw_circle(c, r * (1.0 - k), outer.lerp(inner, k))
	draw_arc(c, r, 0.0, TAU, 40, UiTheme.JY_GOLD if hot else Color("4a3a24"), 2.0, true)
	if not disabled:
		draw_arc(c, r - 3.0, PI * 1.1, PI * 1.7, 12, Color(1, 1, 1, 0.35), 1.5, true)
	_center_text(font, face(), int(r * 1.1), ink, c - size / 2.0)
	if disabled:
		var d := Vector2(r, r) * 0.62
		draw_line(c + Vector2(d.x, -d.y), c + Vector2(-d.x, d.y), Color(0.12, 0.09, 0.06, 0.55), 2.0, true)

## 青銅方鈕：青銅底、金斜面、浮雕字
func _draw_bronze(font: Font, hot: bool, down: bool) -> void:
	var r := Rect2(Vector2.ZERO, size)
	var base := UiTheme.JY_BRONZE
	if disabled:
		base = Color("5a4a34")
	elif marked:
		base = UiTheme.JY_BRONZE.lightened(0.15)
	draw_rect(r, base.darkened(0.1) if down else base)
	var light := UiTheme.JY_GOLD_LIGHT if not disabled else Color("8a7a5c")
	var dark := Color("3a2a14")
	var tl := dark if down else light
	var br := light if down else dark
	draw_line(Vector2(1, 1), Vector2(size.x - 1, 1), tl, 2.0)
	draw_line(Vector2(1, 1), Vector2(1, size.y - 1), tl, 2.0)
	draw_line(Vector2(1, size.y - 1), Vector2(size.x - 1, size.y - 1), br, 2.0)
	draw_line(Vector2(size.x - 1, 1), Vector2(size.x - 1, size.y - 1), br, 2.0)
	if hot or marked:
		draw_rect(r.grow(-0.5), UiTheme.JY_GOLD, false, 1.0)
	var s := face()
	var fs := int(size.y * (0.56 if s.length() <= 1 else 0.36))
	if style != Style.BRONZE:
		fs = int(size.y * 0.62)
	var off := Vector2(0, 1) if down else Vector2.ZERO
	var ink := UiTheme.JY_TEXT if not disabled else Color("8a7a5c")
	if style == Style.CONFIRM or style == Style.CANCEL:
		# ✔／✘ 用線畫（字型的 ✔ 常被換成彩色 emoji）
		var c := size / 2.0 + off
		var k := size.x * 0.28
		var w := maxf(2.0, size.x * 0.09)
		if style == Style.CONFIRM:
			draw_polyline(PackedVector2Array([c + Vector2(-k, 0), c + Vector2(-k * 0.3, k * 0.7), c + Vector2(k, -k * 0.7)]), ink, w, true)
		else:
			draw_line(c + Vector2(-k, -k), c + Vector2(k, k), ink, w, true)
			draw_line(c + Vector2(k, -k), c + Vector2(-k, k), ink, w, true)
		return
	if style == Style.BRONZE:
		# 浮雕：深色字往右下錯 1 px、亮字在上
		_center_text(font, s, fs, Color(0, 0, 0, 0.6), off + Vector2(1, 1))
		ink = Color("f0dca8") if not disabled else Color("8a7a5c")
	_center_text(font, s, fs, ink, off)

## 燈籠：橢圓本體徑向漸層、上下深色蓋、金邊、直排兩字；hover 變亮並擺動
func _draw_lantern(font: Font, hot: bool) -> void:
	var c := size / 2.0
	var rot := sin(Time.get_ticks_msec() / 1000.0 * TAU / 0.4 * 0.5) * deg_to_rad(3.0) * _swing
	draw_set_transform(Vector2(c.x, 0), rot, Vector2.ONE)
	var cx := 0.0
	var cap := 6.0
	draw_line(Vector2(cx, 0), Vector2(cx, cap), Color("1a1008"), 2.0)
	var body := Rect2(Vector2(cx - size.x * 0.46, cap), Vector2(size.x * 0.92, size.y - cap * 2.0))
	var bc := body.get_center()
	var rx := body.size.x / 2.0
	var ry := body.size.y / 2.0
	var lit := 1.15 if hot else 1.0
	for i in 10:
		var k := 1.0 - float(i) / 10.0
		var col := Color("e06a20").lerp(Color("a02810"), k)
		col = Color(col.r * lit, col.g * lit, col.b * lit)
		_ellipse(bc, Vector2(rx * k, ry * k), col)
	_ellipse_outline(bc, Vector2(rx, ry), UiTheme.JY_GOLD)
	# 骨架細線
	for dx in [-0.5, 0.0, 0.5]:
		draw_line(bc + Vector2(rx * dx * 0.9, -ry * 0.92), bc + Vector2(rx * dx * 0.9, ry * 0.92), Color(0.4, 0.1, 0.0, 0.35), 1.0)
	draw_rect(Rect2(Vector2(cx - rx * 0.55, cap - 1.0), Vector2(rx * 1.1, 5.0)), UiTheme.JY_WOOD_DARK)
	draw_rect(Rect2(Vector2(cx - rx * 0.55, size.y - cap - 4.0), Vector2(rx * 1.1, 5.0)), UiTheme.JY_WOOD_DARK)
	var s := face()
	var fs := 20
	for i in s.length():
		var ch := s.substr(i, 1)
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y := bc.y + (float(i) - (s.length() - 1) / 2.0) * fs * 0.95 + fs * 0.36
		draw_string(font, Vector2(cx - w / 2.0, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("111111"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)

func _ellipse_outline(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_polyline(pts, col, 1.0, true)

## ⊠：羊皮紙底、1 px 暗邊、✕
func _draw_close(font: Font, hot: bool, down: bool) -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, UiTheme.JY_PARCHMENT_DARK if down else UiTheme.JY_PARCHMENT)
	draw_rect(r.grow(-0.5), UiTheme.JY_GOLD if hot else Color("4a3a24"), false, 1.0)
	var m := size.x * 0.28
	var col := Color("2b1a0e")
	draw_line(Vector2(m, m), size - Vector2(m, m), col, 2.0, true)
	draw_line(Vector2(size.x - m, m), Vector2(m, size.y - m), col, 2.0, true)

## 單字圓章：底色 tint（預設金褐）、深色字、細金邊
func _draw_seal(font: Font, hot: bool) -> void:
	var r := minf(size.x, size.y) / 2.0 - 1.0
	var c := size / 2.0
	var base := tint if tint.a > 0.0 else Color("a07838")
	draw_circle(c, r, Color("1a1008"))
	draw_circle(c, r - 1.5, base.lightened(0.12) if hot else base)
	draw_arc(c, r - 1.0, 0.0, TAU, 32, UiTheme.JY_GOLD_LIGHT if hot else UiTheme.JY_GOLD, 1.0, true)
	_center_text(font, face(), int(r * 1.15), Color("1a0e06"))

## 物品格：栗色凹格；前兩字；數量；選取／紅框
func _draw_slot(font: Font, hot: bool) -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(UiFrame.style(UiFrame.Kind.SLOT), r)
	if disabled and text == "":
		draw_rect(r.grow(-2), Color(0, 0, 0, 0.3))
	if hot:
		draw_rect(r.grow(-1.5), UiTheme.JY_GOLD, false, 1.0)
	if marked:
		draw_rect(r.grow(-1.0), JY_MARK, false, 2.0)
	var s := face()
	if s != "":
		var fs := int(clampf(size.y * 0.3, 11.0, 18.0))
		_center_text(font, s, fs, UiTheme.JY_TEXT if not disabled else Color("8a8070"), Vector2(0, -1), 2)
	if count > 1:
		var cs := str(count)
		var fs2 := 11
		var w := font.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		var p := Vector2(size.x - w - 3.0, size.y - 3.0)
		draw_string_outline(font, p, cs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 3, Color(0, 0, 0, 0.85))
		draw_string(font, p, cs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, UiTheme.JY_LABEL)

const JY_MARK := Color("e02020")
