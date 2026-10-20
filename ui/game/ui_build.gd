class_name UiBuild
extends RefCounted
## 在程式裡組畫面用的小工具（M1_PLAN 3.12：畫面可以像 net_debug.gd 一樣在程式裡組）。

static func button(parent: Node, text: String, cb: Callable = Callable(), min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	if cb.is_valid():
		b.pressed.connect(cb)
	if min_w > 0.0:
		b.custom_minimum_size = Vector2(min_w, 0)
	if parent:
		parent.add_child(b)
	return b

static func label(parent: Node, text: String = "", font_size: int = 0, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if font_size > 0:
		l.add_theme_font_size_override("font_size", font_size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if parent:
		parent.add_child(l)
	return l

## 次要字（暗底淺褐、卷軸上灰褐）：用主題型別變體，深淺兩種底都對
static func muted(l: Label) -> Label:
	l.theme_type_variation = "MutedLabel"
	return l

## 欄位標籤／小標題（暗底黃字、卷軸上朱紅）
static func accent(l: Label) -> Label:
	l.theme_type_variation = "AccentLabel"
	return l

## 失敗原因（暗底橘紅、卷軸上朱紅）
static func error(l: Label) -> Label:
	l.theme_type_variation = "ErrorLabel"
	return l

## 視窗標題：金色毛筆字 26
static func title(parent: Node, text: String) -> Label:
	var l := label(parent, text)
	l.theme_type_variation = "TitleLabel"
	return l

## 套原作外框的 PanelContainer（UiFrame.Kind）
static func framed(parent: Node, kind: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiFrame.style(kind))
	if parent:
		parent.add_child(p)
	return p

## 地點／曆法名牌（PLATE）裡放一個置中的 Label；回傳 Label
static func plate(parent: Node, text: String = "", font_size: int = 15, min_w: float = 0.0) -> Label:
	var p := framed(parent, UiFrame.Kind.PLATE)
	if min_w > 0.0:
		p.custom_minimum_size = Vector2(min_w, 0)
	var l := label(p, text, font_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	return l

## 程式繪製的按鈕（JyButton.Style）
static func jy_button(parent: Node, style: int, text: String, cb: Callable = Callable(), glyph: String = "") -> JyButton:
	var b := JyButton.new(style, text, glyph)
	if cb.is_valid():
		b.pressed.connect(cb)
	if parent:
		parent.add_child(b)
	return b

## 戰鬥圓盤
static func disc_button(parent: Node, text: String, cb: Callable = Callable()) -> JyButton:
	return jy_button(parent, JyButton.Style.DISC, text, cb)

## 燈籠（text 例「武功(Ctrl+1)」，畫面上直排「武功」）
static func lantern(parent: Node, text: String, cb: Callable = Callable()) -> JyButton:
	return jy_button(parent, JyButton.Style.LANTERN, text, cb)

## 物品格
static func slot(parent: Node, text: String = "", cb: Callable = Callable()) -> JyButton:
	return jy_button(parent, JyButton.Style.SLOT, text, cb)

## ⊠ 關閉鈕（text 是可讀名稱，例「關閉(Esc)」）
static func close_button(parent: Node, text: String, cb: Callable = Callable()) -> JyButton:
	var b := jy_button(parent, JyButton.Style.CLOSE, text, cb)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return b

static func hbox(parent: Node, sep: int = 6) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	if parent:
		parent.add_child(b)
	return b

static func vbox(parent: Node, sep: int = 6) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	if parent:
		parent.add_child(b)
	return b

static func margin(parent: Node, m: int = 12) -> MarginContainer:
	var c := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		c.add_theme_constant_override("margin_" + side, m)
	if parent:
		parent.add_child(c)
	return c

static func scroll(parent: Node, min_h: float = 0.0) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if min_h > 0.0:
		s.custom_minimum_size = Vector2(0, min_h)
	if parent:
		parent.add_child(s)
	return s

static func line_edit(parent: Node, text: String = "", placeholder: String = "", max_len: int = 0) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	if max_len > 0:
		e.max_length = max_len
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if parent:
		parent.add_child(e)
	return e

static func bar(parent: Node, color: Color, min_w: float = 120.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(min_w, 12)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiTheme.vital_bar(b, color, color.lightened(0.35))
	if parent:
		parent.add_child(b)
	return b

static func set_bar(b: ProgressBar, value: float, max_value: float) -> void:
	b.max_value = maxf(1.0, max_value)
	b.value = clampf(value, 0.0, b.max_value)

## 浮動面板：玉石框 PanelContainer + 標題列（金色毛筆標題、⊠ 關閉鈕）+ 內容 VBox。回傳 { panel, body, title, close }
static func popup_frame(title_text: String, min_size: Vector2, kind: int = UiFrame.Kind.JADE) -> Dictionary:
	var panel := framed(null, kind)
	panel.custom_minimum_size = min_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := vbox(panel, 8)
	var head := hbox(v, 8)
	var title_l := title(head, title_text)
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := close_button(head, "關閉")
	var body := vbox(v, 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return { "panel": panel, "body": body, "title": title_l, "close": close }

static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

static func num(v: Variant) -> int:
	return int(v) if (v is int or v is float) else 0

## 浮層文字（聊天、戰報）的細捲軸放在左緣（AUTHENTIC_UI_SPEC §9.1「左緣有一條 6 px 細捲軸」）：
## RichTextLabel 內建的捲軸在右緣，戰報一長就是一根貫穿戰場的長條（審查），所以把它藏起來（透明、0 寬、不吃滑鼠），
## 在 host 裡 x = left_x 處另放一條 6 px 細捲軸，和內建捲軸 share() 同一個值；內容沒有超出時不顯示。
## interactive = false 時只當位置指示（不吃滑鼠，戰場格子點得到）。
static func left_scrollbar(rtl: RichTextLabel, host: Control, left_x: float, interactive: bool) -> VScrollBar:
	var inner := rtl.get_v_scroll_bar()
	var empty := StyleBoxEmpty.new()
	for st in ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed"]:
		inner.add_theme_stylebox_override(st, empty)
	for ic in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
		inner.add_theme_icon_override(ic, ImageTexture.new())
	inner.custom_minimum_size = Vector2.ZERO
	inner.modulate = Color(1, 1, 1, 0)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := VScrollBar.new()
	bar.name = "LeftScroll"
	bar.share(inner)
	bar.custom_minimum_size = Vector2(6, 0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.28)
	track.set_corner_radius_all(3)
	track.content_margin_left = 0
	track.content_margin_right = 0
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.86, 0.74, 0.5, 0.75)
	grab.set_corner_radius_all(3)
	var grab_hi := grab.duplicate() as StyleBoxFlat
	grab_hi.bg_color = Color(0.95, 0.85, 0.6, 0.9)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", grab_hi)
	bar.add_theme_stylebox_override("grabber_pressed", grab_hi)
	for ic in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
		bar.add_theme_icon_override(ic, ImageTexture.new())
	bar.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	bar.focus_mode = Control.FOCUS_NONE
	host.add_child(bar)
	var sync := func() -> void:
		if not is_instance_valid(bar) or not is_instance_valid(rtl):
			return
		bar.position = Vector2(left_x, rtl.position.y + 18.0)
		bar.size = Vector2(6, maxf(0.0, rtl.size.y - 18.0))
		bar.visible = rtl.is_visible_in_tree() and inner.max_value - inner.min_value > inner.page + 0.5
	inner.changed.connect(sync)
	rtl.resized.connect(sync)
	rtl.visibility_changed.connect(sync)
	sync.call()
	return bar

## 捲到最新一行，而且只露出整行（審查 round 4：戰報最下一行、系統訊息框最上一行被框切成半行）。
## 內容比可視高度高時，把多出來不到一行的高度墊在下緣（"normal" 樣式的下內距）：可視區剛好是整數行，
## 最上一行貼齊上緣（再上面一行在控制項外、被裁掉），最新一行在最下面。墊在上緣不行：上一行的下半截會畫進墊出來的空白。
## 每次內容或大小改變後呼叫（建議 call_deferred，讓 RichTextLabel 先排好版）。
static func stick_whole_lines(rtl: RichTextLabel) -> void:
	if not is_instance_valid(rtl) or not rtl.is_inside_tree():
		return
	var sb: StyleBox = rtl.get_meta("_whole_sb") if rtl.has_meta("_whole_sb") else null
	if sb == null:
		var base := rtl.get_theme_stylebox("normal")
		sb = base.duplicate() as StyleBox if base != null else StyleBoxEmpty.new()
		sb.content_margin_top = maxf(0.0, sb.get_margin(SIDE_TOP))
		rtl.set_meta("_whole_bottom", maxf(0.0, sb.get_margin(SIDE_BOTTOM)))
		sb.content_margin_bottom = float(rtl.get_meta("_whole_bottom"))
		rtl.add_theme_stylebox_override("normal", sb)
		rtl.set_meta("_whole_sb", sb)
	var bottom0 := float(rtl.get_meta("_whole_bottom", 0.0))
	var avail := rtl.size.y - sb.content_margin_top - bottom0
	var h := float(rtl.get_content_height())
	var pad := 0.0
	if avail > 0.0 and h > avail + 0.5:
		for i in rtl.get_line_count():
			var off := float(rtl.get_line_offset(i))
			if h - off <= avail + 0.5:
				pad = maxf(0.0, avail - (h - off))
				break
	if absf(sb.content_margin_bottom - (bottom0 + pad)) > 0.25:
		sb.content_margin_bottom = bottom0 + pad
	var bar := rtl.get_v_scroll_bar()
	bar.value = bar.max_value
	# 內距改了之後 RichTextLabel 下一幀才更新捲動頁長：再捲一次到底
	var again := func() -> void:
		if is_instance_valid(rtl):
			rtl.get_v_scroll_bar().value = rtl.get_v_scroll_bar().max_value
	again.call_deferred()
