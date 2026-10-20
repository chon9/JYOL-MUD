class_name UiTheme
extends RefCounted
## 執行期建立主題（docs/AUTHENTIC_UI_SPEC.md：仿 2001《金庸群俠傳 Online》客戶端，暗色雕木／玉石框、亮字）。
## 全域主題是暗底亮字（build()）；淺色的場景卷軸、商店卷軸、大地圖用 build_paper()（墨字）掛在該節點的 theme 上。
## 字型在 res://assets/fonts/ 存在時才載入，所以字型還沒放進來時也能執行。
## 不使用任何原作美術：框、按鈕、圖示一律程式繪製（UiFrame、JyButton）。

const FONT_DIR := "res://assets/fonts"

# ---------- 原作色票（§3，前綴 JY_）----------
const JY_WOOD_DARK := Color("2a1c10")
const JY_WOOD := Color("543424")
const JY_BRONZE := Color("7a5a2e")
const JY_GOLD := Color("c89a50")
const JY_GOLD_LIGHT := Color("e6c77a")
const JY_ROPE := Color("c8642a")
const JY_ROPE_DARK := Color("7e3412")
const JY_JADE := Color("8a9a70")
const JY_JADE_LIGHT := Color("b0b890")
const JY_JADE_DARK := Color("4e5e3e")
const JY_AMBER := Color("b8862e")
const JY_OLIVE := Color("5a5a30")
const JY_OLIVE_DARK := Color("3a3a1c")
const JY_PARCHMENT := Color("e8d8b0")
const JY_PARCHMENT_DARK := Color("d3bf90")
const JY_SLOT := Color("3a1e1e")
const JY_SLOT_EDGE := Color("6e4a3a")
const JY_TEXT_PANEL := Color("080408")
const JY_TEXT := Color("f4f0e6")
const JY_LABEL := Color("f0d060")
const JY_SYS_YELLOW := Color("ffff00")
const JY_RED := Color("e02020")
const JY_BAR_WELL := Color("3e4652")
const JY_BAR_FRAME := Color("6a7380")
const JY_VOID := Color("000000")
const JY_BTN_TEXT := Color("2b1a0e")
const JY_MUTED_LIGHT := Color("c8bc9c")       # 暗底上的次要字
const JY_ERROR_LIGHT := Color("ff7a5c")       # 暗底上的失敗原因
const JY_TOOLTIP_BG := Color("f8e878")
const JY_TOOLTIP_EDGE := Color("5a4a10")

# ---------- 淺底（卷軸）用的墨色 ----------
const PAPER := Color("f3ead8")
const INK := Color("2b2622")
const CINNABAR := Color("b03a2e")
const MUTED := Color("6b6156")
const DISABLED_TEXT := Color("9a9184")
## 卷軸上的名字（§11：原作頭頂名字黃／橘，卷軸是淺底所以取較暗的色）
const NAME_NPC := Color("8a6400")
const NAME_MONSTER := Color("b0521a")
const NAME_TITLE := Color("b030b0")

const FONT_SIZE := 16
const TITLE_SIZE := 26

# ---------- 能量條（§7：精綠、氣紅、神黃、內力藍；起色→終色）----------
const JING_COLOR := Color("22b020")
const QI_COLOR := Color("c83030")
const SHEN_COLOR := Color("c8a030")
const NEILI_COLOR := Color("2238c0")
const VITAL_GRADIENTS := {
	"jing": [Color("22b020"), Color("6e8a1e")],
	"qi": [Color("c83030"), Color("d57c7c")],
	"shen": [Color("c8a030"), Color("e1d890")],
	"neili": [Color("2238c0"), Color("8686d8")],
}
const FOOD_COLOR := Color("8c6d3f")
const WATER_COLOR := Color("3e8e9e")
const VITAL_COLORS := { "jing": JING_COLOR, "qi": QI_COLOR, "shen": SHEN_COLOR, "neili": NEILI_COLOR,
	"food": FOOD_COLOR, "water": WATER_COLOR }
## 飽食、飲水圖示三段色（>50% 正常、20–50% 橘、<20% 紅）
const LEVEL_WARN := Color("e0a030")
const LEVEL_LOW := Color("e02020")

# ---------- 戰鬥（§12）----------
const GRID_BG := Color("efe4cc")
const GRID_LINE := Color("8c7a5b")
const HIGHLIGHT_MOVE := Color(0x3c / 255.0, 0xc8 / 255.0, 0x3c / 255.0, 0.45)     # 移動範圍：綠
const HIGHLIGHT_RANGE := Color(0x30 / 255.0, 0x60 / 255.0, 0xe0 / 255.0, 0.45)    # 攻擊範圍：藍
const HIGHLIGHT_TARGET := Color(0xe0 / 255.0, 0x30 / 255.0, 0x30 / 255.0, 0.50)   # 殺傷／目標：紅
# M3a（M3A_PLAN §7.2）：醫、用藥、傳力選自己或隊友 → 綠框；陣法站位 → 金框（缺人的格閃爍）；範圍招式預覽 → 半透明橘
const HIGHLIGHT_ALLY := Color(0x40 / 255.0, 0xd0 / 255.0, 0x70 / 255.0, 0.50)
const HIGHLIGHT_STATION := Color(0xe0 / 255.0, 0xb0 / 255.0, 0x40 / 255.0, 0.45)
const HIGHLIGHT_AOE := Color(1.0, 0.55, 0.15, 0.35)
const HOVER_CURSOR := Color("ffe040")
const ESCAPE_TILE := Color("ffffff")
const NAME_ENEMY := Color("e08a30")
const NAME_ALLY := Color("ffe85a")
const NAME_TITLE_BATTLE := Color("e040e0")
const TIME_BAR := Color("30d040")
const TIME_BAR_BG := Color("103018")
const QI_BAR := Color("d03030")
const QI_TEXT := Color("ff4040")
const ALLY_COLOR := NAME_ALLY
const ENEMY_COLOR := NAME_ENEMY
const DIM_OVERLAY := Color(0.1, 0.08, 0.05, 0.55)

## 頻道色（§9.3）：浮層沒有底色，所有字加描邊
const OVERLAY_OUTLINE := Color(0, 0, 0, 0.75)

static var _font: Font = null
static var _font_done := false

static func find_font() -> Font:
	if _font_done:
		return _font
	_font_done = true
	if not DirAccess.dir_exists_absolute(FONT_DIR):
		return null
	var names: Array = []
	for f in DirAccess.get_files_at(FONT_DIR):
		var n := f.trim_suffix(".import").trim_suffix(".remap")
		if n.get_extension().to_lower() in ["ttf", "otf", "woff", "woff2"] and not (n in names):
			names.append(n)
	names.sort()
	# 優先使用 LXGW WenKai（霞鶩文楷），其次 Noto
	names.sort_custom(func(a, b): return _rank(a) < _rank(b))
	for n in names:
		var path := FONT_DIR.path_join(n)
		if ResourceLoader.exists(path):
			var font := load(path) as Font
			if font:
				_font = font
				return font
	return null

static func _rank(n: String) -> int:
	var l := n.to_lower()
	if "wenkai" in l or "lxgw" in l:
		return 0
	if "noto" in l and "sans" in l:
		return 1
	return 2

## 毛筆粗筆（視窗標題、燈籠字、戰鬥圓鈕字）：FontVariation.variation_embolden
static var _brush: Dictionary = {}

static func brush_font(embolden: float = 0.4) -> Font:
	if _brush.has(embolden):
		return _brush[embolden]
	var base := find_font()
	if base == null:
		base = ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_embolden = embolden
	_brush[embolden] = fv
	return fv

static func _flat(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 0, margin: float = -1.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	if margin >= 0.0:
		s.set_content_margin_all(margin)
	return s

## 全域主題：暗底亮字
static func build() -> Theme:
	var t := Theme.new()
	var font := find_font()
	if font:
		t.default_font = font
	t.default_font_size = FONT_SIZE
	var panel := _flat(JY_WOOD_DARK)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	for cls in ["Label", "LineEdit", "RichTextLabel", "CheckBox", "CheckButton", "ItemList", "TabBar", "SpinBox"]:
		t.set_color("font_color", cls, JY_TEXT)
	t.set_color("default_color", "RichTextLabel", JY_TEXT)
	t.set_color("font_outline_color", "RichTextLabel", OVERLAY_OUTLINE)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())
	_buttons(t, "Button")
	_buttons(t, "OptionButton")
	_buttons(t, "MenuButton")
	# 文字輸入：近黑底、金邊
	var field := _flat(Color("1a120c"), JY_BRONZE, 1, 2, 5.0)
	var field_focus := _flat(Color("1a120c"), JY_GOLD, 1, 2, 5.0)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_placeholder_color", "LineEdit", Color(JY_MUTED_LIGHT, 0.7))
	t.set_color("caret_color", "LineEdit", JY_GOLD_LIGHT)
	t.set_color("selection_color", "LineEdit", Color(JY_GOLD, 0.4))
	t.set_stylebox("panel", "ItemList", field)
	# 能量條預設
	t.set_stylebox("background", "ProgressBar", _flat(JY_BAR_WELL, JY_BAR_FRAME, 1, 4))
	t.set_stylebox("fill", "ProgressBar", bar_fill(JY_GOLD))
	t.set_color("font_color", "ProgressBar", JY_TEXT)
	# 分頁：深褐底、棕黃毛筆字
	var tab_sel := _flat(Color("4a2e18"), JY_GOLD, 0, 3, 6.0)
	tab_sel.border_width_top = 2
	tab_sel.corner_radius_bottom_left = 0
	tab_sel.corner_radius_bottom_right = 0
	var tab_un := _flat(Color("2a1c10"), JY_BRONZE, 0, 3, 6.0)
	tab_un.border_width_top = 1
	tab_un.corner_radius_bottom_left = 0
	tab_un.corner_radius_bottom_right = 0
	var tab_hover := tab_un.duplicate() as StyleBoxFlat
	tab_hover.bg_color = Color("3a2414")
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_unselected", "TabBar", tab_un)
	t.set_stylebox("tab_hovered", "TabBar", tab_hover)
	t.set_stylebox("tab_disabled", "TabBar", tab_un)
	t.set_stylebox("tab_focus", "TabBar", StyleBoxEmpty.new())
	t.set_color("font_selected_color", "TabBar", JY_GOLD_LIGHT)
	t.set_color("font_unselected_color", "TabBar", Color("d8b060"))
	t.set_color("font_hovered_color", "TabBar", JY_GOLD_LIGHT)
	t.set_color("font_disabled_color", "TabBar", Color("7a6a4a"))
	# 提示框：黃底黑字（§4.4）
	var tip := _flat(JY_TOOLTIP_BG, JY_TOOLTIP_EDGE, 1, 0, 4.0)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", Color.BLACK)
	t.set_font_size("font_size", "TooltipLabel", 14)
	# 選單（OptionButton 的下拉）
	t.set_stylebox("panel", "PopupMenu", _flat(JY_WOOD_DARK, JY_GOLD, 1, 2, 4.0))
	t.set_stylebox("hover", "PopupMenu", _flat(Color("5a3a20")))
	t.set_color("font_color", "PopupMenu", JY_TEXT)
	t.set_color("font_hover_color", "PopupMenu", JY_GOLD_LIGHT)
	t.set_color("font_disabled_color", "PopupMenu", Color("7a6a4a"))
	t.set_stylebox("panel", "PopupPanel", _flat(JY_WOOD_DARK, JY_GOLD, 1, 2, 4.0))
	# 單選圓點：預設是深灰圖示，在深木底上看不見，8 個頻道只剩選中的那個有記號（M2 第三輪審查）→ 金色圓圈／實心金點
	t.set_icon("radio_unchecked", "PopupMenu", radio_icon(false))
	t.set_icon("radio_checked", "PopupMenu", radio_icon(true))
	t.set_icon("radio_unchecked_disabled", "PopupMenu", radio_icon(false, Color("7a6a4a")))
	t.set_icon("radio_checked_disabled", "PopupMenu", radio_icon(true, Color("7a6a4a")))
	# 分隔線：金色細線
	var sep := StyleBoxLine.new()
	sep.color = Color(JY_GOLD, 0.7)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = Color(JY_GOLD, 0.7)
	vsep.thickness = 1
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	# 捲軸：細青銅
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, _flat(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 3, 2.0))
		t.set_stylebox("grabber", sb, _flat(JY_BRONZE, Color(0, 0, 0, 0), 0, 3))
		t.set_stylebox("grabber_highlight", sb, _flat(JY_GOLD, Color(0, 0, 0, 0), 0, 3))
		t.set_stylebox("grabber_pressed", sb, _flat(JY_GOLD_LIGHT, Color(0, 0, 0, 0), 0, 3))
	# 滑桿
	t.set_stylebox("slider", "HSlider", _flat(JY_BAR_WELL, JY_BAR_FRAME, 1, 3, 2.0))
	t.set_stylebox("grabber_area", "HSlider", _flat(JY_GOLD, Color(0, 0, 0, 0), 0, 3, 2.0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _flat(JY_GOLD_LIGHT, Color(0, 0, 0, 0), 0, 3, 2.0))
	_variations(t, false)
	return t

## 卷軸（淺底）用：墨字。只定義與暗底不同的項目，其餘沿用全域主題
static func build_paper() -> Theme:
	var t := Theme.new()
	var font := find_font()
	if font:
		t.default_font = font
	t.default_font_size = FONT_SIZE
	for cls in ["Label", "CheckBox", "RichTextLabel", "TabBar"]:
		t.set_color("font_color", cls, INK)
	t.set_color("default_color", "RichTextLabel", INK)
	var field := _flat(Color("fbf6ea"), Color("8c7a5b"), 1, 2, 5.0)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_color", "SpinBox", INK)
	t.set_color("font_selected_color", "TabBar", INK)
	t.set_color("font_unselected_color", "TabBar", MUTED)
	t.set_color("font_hovered_color", "TabBar", INK)
	# 分頁：卷軸上選中＝亮紙＋朱紅上緣，沒選＝暗一階的紙（M2 審查：沿用暗底主題的深褐分頁，墨字壓在深褐上看不見）
	var tab_sel := _flat(Color("fbf6ea"), Color("8c7a5b"), 1, 3, 6.0)
	tab_sel.border_color = CINNABAR
	tab_sel.border_width_top = 2
	tab_sel.border_width_bottom = 0
	tab_sel.corner_radius_bottom_left = 0
	tab_sel.corner_radius_bottom_right = 0
	var tab_un := _flat(Color("e2d3b0"), Color("a8987a"), 1, 3, 6.0)
	tab_un.border_width_bottom = 0
	tab_un.corner_radius_bottom_left = 0
	tab_un.corner_radius_bottom_right = 0
	var tab_hover := tab_un.duplicate() as StyleBoxFlat
	tab_hover.bg_color = Color("efe4c8")
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_unselected", "TabBar", tab_un)
	t.set_stylebox("tab_hovered", "TabBar", tab_hover)
	t.set_stylebox("tab_disabled", "TabBar", tab_un)
	# 輸入框：LineEdit 與多行 TextEdit 一樣是淺紙底、墨字（審查：信件內文是 Godot 預設的灰色 TextEdit）
	var field_focus := _flat(Color("fffbf0"), CINNABAR, 1, 2, 5.0)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.8))
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("selection_color", "LineEdit", Color(CINNABAR, 0.25))
	t.set_stylebox("normal", "TextEdit", field)
	t.set_stylebox("focus", "TextEdit", field_focus)
	t.set_stylebox("read_only", "TextEdit", field)
	t.set_color("font_color", "TextEdit", INK)
	t.set_color("font_placeholder_color", "TextEdit", Color(MUTED, 0.8))
	t.set_color("caret_color", "TextEdit", INK)
	t.set_color("selection_color", "TextEdit", Color(CINNABAR, 0.25))
	t.set_color("background_color", "TextEdit", Color(0, 0, 0, 0))
	_variations(t, true)
	return t

static func _buttons(t: Theme, cls: String) -> void:
	t.set_stylebox("normal", cls, UiFrame.style(UiFrame.Kind.BTN))
	t.set_stylebox("hover", cls, UiFrame.style(UiFrame.Kind.BTN_HOVER))
	t.set_stylebox("pressed", cls, UiFrame.style(UiFrame.Kind.BTN_PRESSED))
	t.set_stylebox("hover_pressed", cls, UiFrame.style(UiFrame.Kind.BTN_PRESSED))
	t.set_stylebox("disabled", cls, UiFrame.style(UiFrame.Kind.BTN_DISABLED))
	t.set_stylebox("focus", cls, StyleBoxEmpty.new())
	t.set_color("font_color", cls, JY_BTN_TEXT)
	t.set_color("font_hover_color", cls, Color("5a2a0e"))
	t.set_color("font_pressed_color", cls, JY_BTN_TEXT)
	t.set_color("font_hover_pressed_color", cls, JY_BTN_TEXT)
	t.set_color("font_focus_color", cls, JY_BTN_TEXT)
	t.set_color("font_disabled_color", cls, Color("3a3020"))

## 主題型別變體：MutedLabel（次要字）、AccentLabel（欄位標籤／小標題）、ErrorLabel、TitleLabel（金色毛筆標題）、
## ValueLabel（白字數值）、ChoiceButton（NPC 編號選項：透明底、滑過變黃）、NameButton（卷軸上的名字）
static func _variations(t: Theme, paper: bool) -> void:
	t.set_type_variation("MutedLabel", "Label")
	t.set_type_variation("AccentLabel", "Label")
	t.set_type_variation("ErrorLabel", "Label")
	t.set_type_variation("TitleLabel", "Label")
	t.set_type_variation("ValueLabel", "Label")
	t.set_color("font_color", "MutedLabel", MUTED if paper else JY_MUTED_LIGHT)
	t.set_color("font_color", "AccentLabel", CINNABAR if paper else JY_LABEL)
	t.set_color("font_color", "ErrorLabel", CINNABAR if paper else JY_ERROR_LIGHT)
	t.set_color("font_color", "ValueLabel", INK if paper else JY_TEXT)
	t.set_color("font_color", "TitleLabel", INK if paper else JY_GOLD_LIGHT)
	t.set_color("font_outline_color", "TitleLabel", Color(0, 0, 0, 0) if paper else JY_WOOD_DARK)
	t.set_constant("outline_size", "TitleLabel", 0 if paper else 3)
	t.set_font_size("font_size", "TitleLabel", TITLE_SIZE)
	t.set_font("font", "TitleLabel", brush_font(0.4))
	for v in ["ChoiceButton", "NameButton"]:
		t.set_type_variation(v, "Button")
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(2)
		t.set_stylebox("normal", v, empty)
		t.set_stylebox("hover", v, UiFrame.style(UiFrame.Kind.CHOICE_HOVER))
		t.set_stylebox("pressed", v, UiFrame.style(UiFrame.Kind.CHOICE_HOVER))
		t.set_stylebox("hover_pressed", v, UiFrame.style(UiFrame.Kind.CHOICE_HOVER))
		t.set_stylebox("disabled", v, empty)
		t.set_stylebox("focus", v, StyleBoxEmpty.new())
	var choice := INK if paper else JY_TEXT
	t.set_color("font_color", "ChoiceButton", choice)
	t.set_color("font_hover_color", "ChoiceButton", CINNABAR if paper else JY_LABEL)
	t.set_color("font_pressed_color", "ChoiceButton", CINNABAR if paper else JY_LABEL)
	t.set_color("font_hover_pressed_color", "ChoiceButton", CINNABAR if paper else JY_LABEL)
	t.set_color("font_focus_color", "ChoiceButton", choice)
	t.set_color("font_disabled_color", "ChoiceButton", DISABLED_TEXT if paper else Color("8a8070"))
	t.set_font_size("font_size", "ChoiceButton", 18)
	t.set_color("font_color", "NameButton", NAME_NPC)
	t.set_color("font_hover_color", "NameButton", CINNABAR)
	t.set_color("font_pressed_color", "NameButton", CINNABAR)
	t.set_color("font_hover_pressed_color", "NameButton", CINNABAR)
	t.set_color("font_focus_color", "NameButton", NAME_NPC)
	t.set_color("font_disabled_color", "NameButton", DISABLED_TEXT)

static var _paper: Theme = null

## 共用的卷軸主題實例
static func paper() -> Theme:
	if _paper == null:
		_paper = build_paper()
	return _paper

## 單色填色（舊介面相容）
static func bar_fill(color: Color) -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.bg_color = color
	f.set_corner_radius_all(3)
	return f

## 給 ProgressBar 套上指定顏色
static func color_bar(bar: ProgressBar, color: Color) -> void:
	bar.add_theme_stylebox_override("fill", bar_fill(color))

static var _vital_cache: Dictionary = {}

## 原作能量條（§7）：水平漸層 fill（from→to），上半部 40% 疊 18% 白光澤；凹槽石板灰藍、1 px 外框、圓端
static func vital_bar(bar: ProgressBar, from: Color, to: Color) -> void:
	var key := from.to_html() + to.to_html()
	if not _vital_cache.has(key):
		var w := 64
		var h := 16
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var c := from.lerp(to, float(x) / float(w - 1))
				if y < int(h * 0.4):
					c = c.lerp(Color.WHITE, 0.18 * (1.0 - float(y) / (h * 0.4)))
				img.set_pixel(x, y, c)
		var sb := StyleBoxTexture.new()
		sb.texture = ImageTexture.create_from_image(img)
		sb.texture_margin_left = 3
		sb.texture_margin_right = 3
		_vital_cache[key] = sb
	bar.add_theme_stylebox_override("fill", _vital_cache[key])
	bar.add_theme_stylebox_override("background", _flat(JY_BAR_WELL, JY_BAR_FRAME, 1, 4))

## 浮在畫面上的面板（舊介面相容：改成玉石框）
static func popup_panel_style() -> StyleBox:
	return UiFrame.style(UiFrame.Kind.JADE)

## 16×16 單選圖示：金色圓圈；checked 時中間加實心點
static func radio_icon(checked: bool, col: Color = JY_GOLD_LIGHT) -> ImageTexture:
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(7.5, 7.5)
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(c)
			var a := 0.0
			if d >= 5.0 and d <= 6.6:
				a = 1.0   # 外圈
			elif checked and d <= 3.2:
				a = 1.0   # 中心點
			if a > 0.0:
				img.set_pixel(x, y, Color(col, a))
	return ImageTexture.create_from_image(img)
