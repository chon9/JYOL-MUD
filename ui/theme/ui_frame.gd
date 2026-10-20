class_name UiFrame
extends RefCounted
## 程式產生的九宮格外框（AUTHENTIC_UI_SPEC §4）。不使用任何原作美術：每一種框都在第一次使用時逐像素畫出，
## 轉成 ImageTexture 包成 StyleBoxTexture，依種類快取。所有雜訊都用固定 seed，每次執行外觀一致。
##
## 種類：JADE（玉石框＋編繩，裝備／武功／指令／系統）、AMBER（琥珀框，屬性）、SCROLL（竹軸捲軸，商店／地圖）、
## SCROLL_SMALL（場景卷軸）、JADE_SMALL（小地圖）、HUD（底部雕木）、INK（近黑文字框＋金邊如意角）、
## SLOT（栗色凹格）、PLATE（灰褐名牌）、BTN／BTN_HOVER／BTN_PRESSED／BTN_DISABLED（骨色文字鈕）。

enum Kind { JADE, AMBER, SCROLL, SCROLL_SMALL, JADE_SMALL, HUD, INK, SLOT, PLATE, BTN, BTN_HOVER, BTN_PRESSED, BTN_DISABLED, CHOICE_HOVER, INKWASH }

const SIZE := 96
const SEED_MARBLE := 1729
const SEED_FIELD := 4104
const OUTLINE := Color("14140c")
const ROPE_EDGE := Color("2a140a")

static var _styles: Dictionary = {}     # Kind -> StyleBox
static var _textures: Dictionary = {}   # Kind -> ImageTexture

## 依種類取得（快取）外框；回傳的是共用實例，要改邊距時請 duplicate()
static func style(kind: int) -> StyleBox:
	if not _styles.has(kind):
		_styles[kind] = _make_style(kind)
	return _styles[kind]

## 產生（快取）的原始貼圖；PLATE 等用 StyleBoxFlat 的種類回 null
static func texture(kind: int) -> Texture2D:
	if not _textures.has(kind):
		var img := _make_image(kind)
		_textures[kind] = ImageTexture.create_from_image(img) if img != null else null
	return _textures[kind]

static func clear_cache() -> void:
	_styles.clear()
	_textures.clear()

static func _make_style(kind: int) -> StyleBox:
	match kind:
		Kind.PLATE:
			var p := StyleBoxFlat.new()
			p.bg_color = Color("4a4038")
			p.border_color = UiTheme.JY_GOLD
			p.set_border_width_all(1)
			p.set_corner_radius_all(4)
			p.content_margin_left = 8
			p.content_margin_right = 8
			p.content_margin_top = 2
			p.content_margin_bottom = 2
			return p
		Kind.CHOICE_HOVER:
			var c := StyleBoxFlat.new()
			c.bg_color = Color(1.0, 0.85, 0.3, 0.12)
			c.set_content_margin_all(2)
			return c
	var tex := texture(kind)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	var m := _margins(kind)   # [texture margin, content margin h, content margin v]
	sb.texture_margin_left = m[0]
	sb.texture_margin_right = m[0]
	sb.texture_margin_top = m[0]
	sb.texture_margin_bottom = m[0]
	sb.content_margin_left = m[1]
	sb.content_margin_right = m[1]
	sb.content_margin_top = m[2]
	sb.content_margin_bottom = m[2]
	match kind:
		Kind.SCROLL, Kind.SCROLL_SMALL:
			var rod := 16 if kind == Kind.SCROLL else 10
			sb.texture_margin_top = rod
			sb.texture_margin_bottom = rod
			sb.texture_margin_left = 6
			sb.texture_margin_right = 6
			sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
			sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		Kind.HUD:
			sb.texture_margin_top = 12
			sb.texture_margin_bottom = 4
			sb.texture_margin_left = 4
			sb.texture_margin_right = 4
			sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
			sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		Kind.INKWASH:
			sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
			sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		Kind.JADE, Kind.AMBER, Kind.JADE_SMALL:
			sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
			sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	if kind == Kind.HUD:
		sb.content_margin_top = 10
		sb.content_margin_bottom = 4
	if kind == Kind.BTN_PRESSED:
		sb.content_margin_top += 1   # 按下：字往下 1 px
		sb.content_margin_bottom -= 1
	return sb

static func _margins(kind: int) -> Array:
	match kind:
		Kind.JADE, Kind.AMBER:
			return [24, 26, 26]
		Kind.JADE_SMALL:
			return [12, 12, 12]
		Kind.SCROLL:
			return [16, 22, 20]
		Kind.SCROLL_SMALL:
			return [10, 14, 12]
		Kind.HUD:
			return [12, 6, 6]
		Kind.INK:
			return [8, 8, 6]
		Kind.INKWASH:
			return [16, 16, 14]
		Kind.SLOT:
			return [3, 3, 3]
		Kind.BTN, Kind.BTN_HOVER, Kind.BTN_PRESSED, Kind.BTN_DISABLED:
			return [4, 10, 4]
	return [8, 8, 8]

static func _make_image(kind: int) -> Image:
	match kind:
		Kind.JADE:
			return _framed(SIZE, 1.0, [UiTheme.JY_JADE_DARK, UiTheme.JY_JADE, UiTheme.JY_JADE_LIGHT])
		Kind.AMBER:
			return _framed(SIZE, 1.0, [Color("7a4e18"), UiTheme.JY_AMBER, Color("d8b060")])
		Kind.JADE_SMALL:
			return _framed(48, 0.5, [UiTheme.JY_JADE_DARK, UiTheme.JY_JADE, UiTheme.JY_JADE_LIGHT])
		Kind.SCROLL:
			return _scroll(SIZE, 14)
		Kind.SCROLL_SMALL:
			return _scroll(64, 8)
		Kind.HUD:
			return _hud(64)
		Kind.INK:
			return _ink(32)
		Kind.INKWASH:
			return _inkwash(128)
		Kind.SLOT:
			return _slot(12)
		Kind.BTN:
			return _button(16, UiTheme.JY_PARCHMENT, Color("f6ecd2"), Color("9c8658"), Color("4a3a24"))
		Kind.BTN_HOVER:
			return _button(16, Color("f0e2bc"), Color("f6ecd2"), Color("9c8658"), UiTheme.JY_GOLD)
		Kind.BTN_PRESSED:
			return _button(16, UiTheme.JY_PARCHMENT_DARK, Color("9c8658"), Color("f6ecd2"), Color("4a3a24"))
		Kind.BTN_DISABLED:
			return _button(16, Color("8a7a5c"), Color("a09070"), Color("6a5c44"), Color("3a3020"))
	return null

# ---------------------------------------------------------------- 像素工具

static func _img(w: int, h: int) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)

static func _noise(seed_v: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.seed = seed_v
	n.frequency = freq
	return n

## 三段漸層：t 0..1
static func _ramp(stops: Array, t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	if t < 0.5:
		return (stops[0] as Color).lerp(stops[1], t * 2.0)
	return (stops[1] as Color).lerp(stops[2], (t - 0.5) * 2.0)

## 外框距離（離最近的邊幾 px）
static func edge_dist(x: int, y: int, w: int, h: int) -> int:
	return mini(mini(x, y), mini(w - 1 - x, h - 1 - y))

## 玉石／琥珀框：外描邊、大理石框（1–8）、角釘、編繩（9–14）、斑駁內場（15 以內）。scale 0.5 = 小號（各層減半）
static func _framed(n: int, scale: float, marble: Array) -> Image:
	var img := _img(n, n)
	var nm := _noise(SEED_MARBLE, 0.18 / maxf(scale, 0.25))
	var nf := _noise(SEED_FIELD, 0.07)
	var m_end := int(round(8 * scale))           # 大理石最後一 px
	var r0 := m_end + 1                          # 編繩開始
	var r1 := r0 + int(round(5 * scale))         # 編繩最後一 px
	var stud := int(round(13 * scale))
	for y in n:
		for x in n:
			var d := edge_dist(x, y, n, n)
			var c: Color
			if d == 0:
				c = OUTLINE
			elif d <= m_end:
				c = _ramp(marble, (nm.get_noise_2d(x, y) + 1.0) * 0.5)
				if d == 1 and (x == 1 or y == 1):
					c = c.lerp(Color.WHITE, 0.25)
				if d == m_end and (x == n - 1 - m_end or y == n - 1 - m_end):
					c = c.lerp(Color.BLACK, 0.3)
			elif d <= r1:
				if d == r0 or d == r1:
					c = ROPE_EDGE
				else:
					var k := posmod(x + y, 6)
					c = UiTheme.JY_ROPE if k < 3 else (UiTheme.JY_ROPE_DARK if k < 5 else UiTheme.JY_GOLD)
			else:
				var v := nf.get_noise_2d(x, y) * 0.1
				c = UiTheme.JY_OLIVE.lightened(v) if v > 0.0 else UiTheme.JY_OLIVE.darkened(-v)
				var inner := d - r1
				if inner <= 6:
					c = c.lerp(UiTheme.JY_OLIVE_DARK, float(7 - inner) / 7.0 * 0.85)
			img.set_pixel(x, y, c)
	# 角釘
	for cx in [0, n - 1 - stud]:
		for cy in [0, n - 1 - stud]:
			_stud(img, cx, cy, stud + 1)
	return img

static func _stud(img: Image, x0: int, y0: int, s: int) -> void:
	var core := maxi(2, s * 4 / 14)
	var c0 := (s - core) / 2
	for y in s:
		for x in s:
			var c := UiTheme.JY_GOLD
			if x == 0 or y == 0:
				c = UiTheme.JY_GOLD_LIGHT
			elif x == s - 1 or y == s - 1:
				c = UiTheme.JY_BRONZE
			if x >= c0 and x < c0 + core and y >= c0 and y < c0 + core:
				c = UiTheme.JY_WOOD_DARK
			img.set_pixel(x0 + x, y0 + y, c)

## 捲軸：上下竹／骨色軸桿（垂直漸層，每 48 px 一道竹節暗線）；左右 3 px 細邊；羊皮紙內場疊 6% 雲狀墨暈
static func _scroll(n: int, rod: int) -> Image:
	var img := _img(n, n)
	var ink := _noise(SEED_FIELD + 3, 0.05)
	var top_c := Color("f0e6cc")
	var bot_c := Color("b8a47c")
	for y in n:
		for x in n:
			var c: Color
			var in_rod := y < rod or y >= n - rod
			if in_rod:
				var ry := y if y < rod else y - (n - rod)
				c = top_c.lerp(bot_c, float(ry) / float(maxi(1, rod - 1)))
				if ry == 0 or ry == rod - 1:
					c = Color("6e5a3a")
				if posmod(x, 48) == 24:
					c = c.darkened(0.35)
			elif x < 3 or x >= n - 3:
				c = Color("8c7a5b") if (x == 0 or x == n - 1) else Color("c8b68c")
			else:
				var v := (ink.get_noise_2d(x, y) + 1.0) * 0.5
				c = UiTheme.JY_PARCHMENT.lerp(Color("5a4630"), 0.06 * v)
				if y == rod or y == n - rod - 1:
					c = c.darkened(0.25)   # 軸桿陰影
			img.set_pixel(x, y, c)
	return img

## 底部 HUD：雕木垂直漸層、上緣兩條金線（相隔 3 px）、每 16 px 一顆 2×2 金點
static func _hud(n: int) -> Image:
	var img := _img(n, n)
	for y in n:
		for x in n:
			var c := UiTheme.JY_WOOD_DARK.lerp(UiTheme.JY_WOOD, float(y) / float(n - 1))
			if y == 0:
				c = Color("100a06")
			elif y == 2 or y == 6:
				c = UiTheme.JY_GOLD
			elif (y == 9 or y == 10) and (posmod(x, 16) == 7 or posmod(x, 16) == 8):
				c = UiTheme.JY_GOLD.darkened(0.15)
			img.set_pixel(x, y, c)
	return img

## 內嵌文字框：近黑底、1 px 金邊、四角三瓣弧（如意角）
static func _ink(n: int) -> Image:
	var img := _img(n, n)
	img.fill(UiTheme.JY_TEXT_PANEL)
	for i in n:
		for p in [Vector2i(i, 0), Vector2i(i, n - 1), Vector2i(0, i), Vector2i(n - 1, i)]:
			img.set_pixelv(p, UiTheme.JY_GOLD)
	# 如意角：在每個角內側畫三個小弧（半徑 2 的圓點排成 L）
	for corner in [Vector2i(2, 2), Vector2i(n - 3, 2), Vector2i(2, n - 3), Vector2i(n - 3, n - 3)]:
		var sx := 1 if corner.x < n / 2 else -1
		var sy := 1 if corner.y < n / 2 else -1
		for off in [Vector2i(0, 0), Vector2i(2 * sx, 0), Vector2i(0, 2 * sy), Vector2i(sx, sy)]:
			var p: Vector2i = corner + off
			if p.x > 0 and p.y > 0 and p.x < n - 1 and p.y < n - 1:
				img.set_pixelv(p, UiTheme.JY_GOLD.darkened(0.1))
	return img

## NPC 對話框底（§8.7）：#2A1E14→#4A3424 漸層、兩層低頻雜訊墨暈、左上一道淡書法捲軸條、細金邊（不畫原作牡丹）
static func _inkwash(n: int) -> Image:
	var img := _img(n, n)
	var a := _noise(SEED_FIELD + 11, 0.03)
	var b := _noise(SEED_FIELD + 12, 0.08)
	for y in n:
		for x in n:
			var c := Color("2a1e14").lerp(Color("4a3424"), float(x + y) / float(2 * n))
			var v := a.get_noise_2d(x, y) * 0.18 + b.get_noise_2d(x, y) * 0.08
			c = c.darkened(-v) if v < 0.0 else c.darkened(v)
			# （原本 x 10–22 有一道淡色筆刷：一半落在可拉伸的中央區，視窗一放大就被拉成一條亮帶——審查 round 3，拿掉）
			var d := edge_dist(x, y, n, n)
			if d == 0:
				c = OUTLINE
			elif d == 2:
				c = UiTheme.JY_GOLD.darkened(0.2)
			img.set_pixel(x, y, c)
	return img

## 物品格：栗色、內凹斜面（左上暗、右下亮）
static func _slot(n: int) -> Image:
	var img := _img(n, n)
	img.fill(UiTheme.JY_SLOT)
	for i in n:
		img.set_pixel(i, 0, Color("1e0e0e"))
		img.set_pixel(0, i, Color("1e0e0e"))
		img.set_pixel(i, n - 1, UiTheme.JY_SLOT_EDGE)
		img.set_pixel(n - 1, i, UiTheme.JY_SLOT_EDGE)
	return img

## 骨色文字鈕：2 px 斜面＋1 px 外框
static func _button(n: int, fill: Color, light: Color, dark: Color, edge: Color) -> Image:
	var img := _img(n, n)
	for y in n:
		for x in n:
			var d := edge_dist(x, y, n, n)
			var c := fill
			if d == 0:
				c = edge
			elif d <= 2:
				var tl := x <= 2 or y <= 2
				var br := x >= n - 3 or y >= n - 3
				c = light if tl and not br else (dark if br and not tl else fill.lerp(dark, 0.5))
			img.set_pixel(x, y, c)
	return img
