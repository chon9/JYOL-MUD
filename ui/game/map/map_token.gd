class_name MapToken
extends RefCounted
## 地圖上的「你」（擁有者：按了地圖後要有棋子或人物圖一格一格趕路，才有沉浸感）。
## 有角色立繪就畫縮小的立繪，沒有就畫一顆寫「俠」的棋子；腳下一圈影子。
## 區域圖／小地圖（RegionMapView）在換房間時讓它從上一間滑到這一間，江湖全圖（WorldMapView）站在目前地點上。

const PIECE_FILL := Color("b8322a")
const PIECE_RIM := Color("f3e2b8")
const SHADOW := Color(0, 0, 0, 0.35)
## 一步的滑動時間（秒）：要看得到「走過去」，又不能比趕路一步慢太多（AutoWalker.STEP_DELAY_S）
const MOVE_S := 0.32
## 滑動時往上跳的高度（相對棋子高度）
const HOP := 0.18

## 棋子的位置：from→to 走了 t（0–1），中途微微跳起
static func pos_at(from: Vector2, to: Vector2, t: float, height: float) -> Vector2:
	var k := clampf(t, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)   # smoothstep
	var p := from.lerp(to, e)
	p.y -= sin(k * PI) * height * HOP
	return p

## 在 ci 上畫棋子：foot 是腳底（影子中心），height 是畫出來的高度（畫布座標）
static func draw(ci: CanvasItem, tex: Texture2D, foot: Vector2, height: float, font: Font) -> void:
	var sw := height * 0.55
	_ellipse(ci, foot, Vector2(sw * 0.5, sw * 0.16), SHADOW)
	if tex != null:
		var ts := tex.get_size()
		if ts.y > 0.0:
			var w := height * ts.x / ts.y
			ci.draw_texture_rect(tex, Rect2(Vector2(foot.x - w / 2.0, foot.y - height), Vector2(w, height)), false)
			return
	# 棋子：朱紅圓、米色邊、中間「俠」
	var r := height * 0.32
	var c := foot - Vector2(0, r * 1.1)
	ci.draw_circle(c, r, PIECE_RIM)
	ci.draw_circle(c, r * 0.84, PIECE_FILL)
	if font != null:
		var fs := maxi(8, int(r * 1.1))
		var s := font.get_string_size("俠", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		ci.draw_string(font, c + Vector2(-s.x / 2.0, font.get_ascent(fs) - s.y / 2.0), "俠", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PIECE_RIM)

static func _ellipse(ci: CanvasItem, c: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	ci.draw_colored_polygon(pts, col)
