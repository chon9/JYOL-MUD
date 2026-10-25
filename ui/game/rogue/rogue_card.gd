class_name RogueCard
extends Control
## 江湖試煉的一張卡（ROGUE_PLAN §5.3；WP-UI）。仿原作客戶端的窗框：
## 武功＝玉框（JADE）、兵器＝卷軸（SCROLL，墨字）、屬性＝琥珀框（AMBER）、隊友＝近黑金邊框（INK）。
## 卡頭：名牌（PLATE）寫 title、右上稀有度印（凡良稀珍神，顏色同 LootUi）、種類大字印（武兵屬友，毛筆字）。
## 卡身：sub、lines；武功精進時加「精進」小印；隊友顯示立繪縮圖（沒有圖 → 程式畫的剪影）。
## 互動：滑過 → 金描邊；點一下 → 選取（下沉）；已選取再點一下 → activated（送出由 RogueScreen 決定）。
## 文字一律來自主機的卡片快照（§3.4.4），這裡只排版。

signal clicked(idx: int)
signal activated(idx: int)

const CARD_SIZE := Vector2(260, 340)
const SINK := 8.0
const HOVER_EDGE := Color("ffd860")
const SELECT_EDGE := Color("ffe9a0")
const PORTRAIT := Vector2(96, 96)

var data: Dictionary = {}
var idx := 0
var kind := ""
var rarity := "COMMON"
var frame_kind := UiFrame.Kind.JADE
var hovered := false
var selected := false

var frame: PanelContainer
var title_label: Label
var rarity_seal: Label
var kind_glyph: Label
var sub_label: Label
var lines_box: VBoxContainer
var upgrade_seal: Label
var power_label: Label         # 戰力 ▲n%／▼n%／持平（主機的 power_pct；隊友卡沒有）
var portrait: Control          # TextureRect（有立繪）或 Silhouette
var edge: Control              # 金描邊（滑過／選取）

## 卡片種類 → 外框
static func frame_kind_for(k: String) -> int:
	match k:
		"WEAPON": return UiFrame.Kind.SCROLL
		"ATTR": return UiFrame.Kind.AMBER
		"ALLY": return UiFrame.Kind.INK
	return UiFrame.Kind.JADE

static func rarity_name(r: String) -> String:
	return str(UiKeys.ROGUE_RARITY_NAMES.get(r, UiKeys.ROGUE_RARITY_NAMES["COMMON"]))

static func rarity_color(r: String) -> Color:
	return LootUi.rarity_color(r)

static func glyph_for(k: String) -> String:
	return str(UiKeys.ROGUE_KIND_GLYPH.get(k, "？"))

## 顯示用的種類：護具卡（WEAPON、item.slot 不是 WEAPON）→ ARMOR
static func display_kind(card: Dictionary) -> String:
	var k := str(card.get("kind", ""))
	if k != "WEAPON":
		return k
	var it: Variant = card.get("item", {})
	var slot := str((it as Dictionary).get("slot", "")) if it is Dictionary else ""
	if (slot != "" and slot != "WEAPON") or (slot == "" and str(card.get("sub", "")).begins_with("護具")):
		return "ARMOR"
	return k

## 卡面的戰力文字（沒有 power_pct → ""）
static func power_text(card: Dictionary) -> String:
	if not card.has("power_pct"):
		return ""
	var p := UiBuild.num(card.get("power_pct", 0))
	if p > 0:
		return "戰力 ▲%d%%" % p
	if p < 0:
		return "戰力 ▼%d%%" % -p
	return "戰力 持平"

func _init(card: Dictionary = {}) -> void:
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not card.is_empty():
		set_card(card)

func set_card(card: Dictionary) -> void:
	data = card.duplicate(true)
	idx = int(card.get("idx", 0))
	kind = str(card.get("kind", "ART"))
	rarity = LootUi.norm(card.get("rarity", "COMMON"))
	frame_kind = frame_kind_for(kind)
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	frame = UiBuild.framed(self, frame_kind)
	frame.name = "Frame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if frame_kind == UiFrame.Kind.SCROLL:
		frame.theme = UiTheme.paper()   # 卷軸是淺底：墨字
	var v := UiBuild.vbox(frame, 6)
	var dk := display_kind(data)
	# 卡頭：種類大字印＋名牌＋稀有度印
	var head := UiBuild.hbox(v, 6)
	kind_glyph = UiBuild.label(head, glyph_for(dk), 34)
	kind_glyph.name = "KindGlyph"
	kind_glyph.add_theme_font_override("font", UiTheme.brush_font(0.5))
	kind_glyph.add_theme_color_override("font_color", UiTheme.CINNABAR if frame_kind == UiFrame.Kind.SCROLL else UiTheme.JY_GOLD_LIGHT)
	kind_glyph.add_theme_constant_override("outline_size", 3)
	kind_glyph.add_theme_color_override("font_outline_color", UiTheme.JY_WOOD_DARK)
	kind_glyph.tooltip_text = str(UiKeys.ROGUE_KIND_NAMES.get(dk, ""))
	kind_glyph.mouse_filter = Control.MOUSE_FILTER_PASS
	title_label = UiBuild.plate(head, str(data.get("title", "")), 16)
	title_label.name = "Title"
	title_label.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.get_parent().size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rarity_seal = _seal(head, rarity_name(rarity), rarity_color(rarity), 20)
	rarity_seal.name = "RaritySeal"
	# 種類與精進印
	var srow := UiBuild.hbox(v, 6)
	var kname := UiBuild.label(srow, str(UiKeys.ROGUE_KIND_NAMES.get(dk, "")), 14)
	kname.name = "KindName"
	UiBuild.accent(kname)
	upgrade_seal = _seal(srow, UiKeys.ROGUE_UPGRADE_SEAL, UiTheme.CINNABAR, 14)
	upgrade_seal.name = "UpgradeSeal"
	upgrade_seal.visible = kind == "ART" and bool(data.get("upgrade", false))
	# 戰力變化（審查：選卡的好壞要看得出來）：同一行靠右，不加高卡片
	power_label = UiBuild.label(srow, power_text(data), 14)
	power_label.name = "Power"
	power_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var pp := UiBuild.num(data.get("power_pct", 0))
	if pp > 0:
		power_label.add_theme_color_override("font_color", UiTheme.JY_GOLD_LIGHT if frame_kind != UiFrame.Kind.SCROLL else Color("2f6b2a"))
	elif pp < 0:
		power_label.add_theme_color_override("font_color", UiTheme.JY_ERROR_LIGHT if frame_kind != UiFrame.Kind.SCROLL else UiTheme.CINNABAR)
	else:
		UiBuild.muted(power_label)
	power_label.visible = power_label.text != ""
	# 隊友立繪
	portrait = null
	if kind == "ALLY":
		var ally: Dictionary = data.get("ally", {}) if data.get("ally") is Dictionary else {}
		portrait = make_portrait(str(ally.get("ref", "")), PORTRAIT)
		var pc := CenterContainer.new()
		pc.add_child(portrait)
		v.add_child(pc)
	sub_label = UiBuild.label(v, str(data.get("sub", "")), 15, true)
	sub_label.name = "Sub"
	UiBuild.muted(sub_label)
	lines_box = UiBuild.vbox(v, 2)
	lines_box.name = "Lines"
	var lines: Variant = data.get("lines", [])
	if lines is Array:
		for t in lines:
			UiBuild.label(lines_box, str(t), 14, true)
	_ignore_mouse(frame)
	edge = CardEdge.new()
	edge.name = "Edge"
	edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(edge)
	tooltip_text = tooltip_for(data, UiClient.tables())
	_apply_look()

## 滑鼠提示：種類〔稀有度〕名稱＋卡面文字；武功卡另附這門武功的完整說明（SkillEffects，同武功窗、學武視窗）
static func tooltip_for(card: Dictionary, tables: Dictionary) -> String:
	var k := str(card.get("kind", ""))
	var out: PackedStringArray = ["%s〔%s〕%s" % [str(UiKeys.ROGUE_KIND_NAMES.get(display_kind(card), "")),
		rarity_name(LootUi.norm(card.get("rarity", "COMMON"))), str(card.get("title", ""))]]
	var lines: Variant = card.get("lines", [])
	if lines is Array:
		for t in lines:
			out.append(str(t))
	var pt := power_text(card)
	if pt != "":
		out.append("選了之後%s%s" % [pt, str(card.get("power_note", ""))])
		out.append(UiKeys.ROGUE_POWER_HINT)
	if k == "ART" and card.get("art") is Dictionary:
		var fx := trial_effect_lines(SkillEffects.lines(str((card["art"] as Dictionary).get("id", "")), tables))
		if not fx.is_empty():
			out.append("")
			out.append("【武功說明】")
			out.append_array(fx)
	return "\n".join(out)

## 武功說明裡只在江湖裡用得到的行拿掉（試煉中沒有頻道、修煉、拜師、秘笈；審查）
static func trial_effect_lines(fx: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for l in fx:
		var skip := false
		for w in UiKeys.ROGUE_TOOLTIP_SKIP:
			if str(w) in l:
				skip = true
				break
		if not skip:
			out.append(l)
	return out

## 小方印（實心底＋白字）
static func _seal(parent: Node, text: String, color: Color, font_size: int) -> Label:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.15)
	sb.border_color = color.lightened(0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(p)
	var l := UiBuild.label(p, text, font_size)
	l.add_theme_font_override("font", UiTheme.brush_font(0.4))
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

## 立繪縮圖：ArtRegistry 的 NPC idle 圖；沒有 → 剪影
static func make_portrait(ref: String, size: Vector2) -> Control:
	var tex: Texture2D = ArtRegistry.unit_texture(ref, "NPC", "idle") if ref != "" else null
	if tex != null:
		var tr := TextureRect.new()
		tr.name = "Portrait"
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = size
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var s := Silhouette.new()
	s.name = "Silhouette"
	s.custom_minimum_size = size
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

static func _ignore_mouse(n: Node) -> void:
	if n is Control and not (n.name == "KindGlyph"):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)

func set_selected(on: bool) -> void:
	selected = on
	_apply_look()

func _apply_look() -> void:
	if frame == null:
		return
	frame.offset_top = SINK if selected else 0.0
	frame.offset_bottom = SINK if selected else 0.0
	if edge != null:
		edge.offset_top = frame.offset_top
		edge.offset_bottom = frame.offset_bottom
		(edge as CardEdge).color = SELECT_EDGE if selected else HOVER_EDGE
		(edge as CardEdge).width = 4.0 if selected else 3.0
		edge.visible = hovered or selected
		edge.queue_redraw()

## 現在是否顯示金描邊（測試用）
func edge_visible() -> bool:
	return edge != null and edge.visible

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			hovered = true
			_apply_look()
		NOTIFICATION_MOUSE_EXIT:
			hovered = false
			_apply_look()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		press()

## 點一下：沒選 → 選取；已選 → 確認
func press() -> void:
	if selected:
		activated.emit(idx)
	else:
		clicked.emit(idx)

## 金描邊（滑過、選取）
class CardEdge extends Control:
	var color := Color("ffd860")
	var width := 3.0
	func _draw() -> void:
		draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), color, false, width)

## 沒有立繪時的程序化剪影（頭、肩、身，墨色）
class Silhouette extends Control:
	var ink := Color(0.12, 0.09, 0.07, 0.85)
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var c := Vector2(w / 2.0, h * 0.28)
		draw_circle(c, h * 0.15, ink)
		var body := PackedVector2Array([
			Vector2(w * 0.5 - h * 0.10, h * 0.42), Vector2(w * 0.5 + h * 0.10, h * 0.42),
			Vector2(w * 0.5 + h * 0.32, h * 0.98), Vector2(w * 0.5 - h * 0.32, h * 0.98)])
		draw_colored_polygon(body, ink)
