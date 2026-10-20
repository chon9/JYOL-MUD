class_name BattleAoe
extends RefCounted
## 範圍招式的形狀（M3A_PLAN 5.3）。純幾何：座標系同戰場 12×8，回傳的格子都在場內、不含施招者自己。
## SINGLE 單體、CROSS 小十字（5 格）、CROSS_L 大十字（上下左右各 3，13 格）、LINE 直線、FAN 半米字、AROUND 周身 8 格。

const SHAPES := ["SINGLE", "CROSS", "CROSS_L", "LINE", "FAN", "AROUND"]
## 8 方向（逆時針排列；FAN 用相鄰兩個方向）
const DIR8 := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
const CROSS_L_ARM := 3      # 大十字每邊 3 格【待考證：13 格 vs 10 格】

static func is_aoe(aoe: String) -> bool:
	return aoe != "" and aoe != "SINGLE"

## 方向型（LINE／FAN）：中心格只代表方向
static func is_directional(aoe: String) -> bool:
	return aoe == "LINE" or aoe == "FAN"

## 從 origin 看 c 的 8 方向單位向量；不在同列、同行或同斜線（或 c == origin）回 Vector2i.ZERO
static func direction(origin: Vector2i, c: Vector2i) -> Vector2i:
	var d := c - origin
	if d == Vector2i.ZERO:
		return Vector2i.ZERO
	if d.x != 0 and d.y != 0 and absi(d.x) != absi(d.y):
		return Vector2i.ZERO
	return Vector2i(signi(d.x), signi(d.y))

## 中心格到施招者的距離（射程檢查用）。
## M3A_PLAN 缺漏：5.3 寫「中心格必須在 range 內（曼哈頓）」，但 LINE／FAN 的斜方向在曼哈頓下永遠超出射程 1，
## 所以方向型招式用切比雪夫距離（斜走一格算一步），其餘照曼哈頓；AROUND 以自己為中心（距離 0）。
static func center_distance(aoe: String, origin: Vector2i, c: Vector2i) -> int:
	if is_directional(aoe):
		return maxi(absi(c.x - origin.x), absi(c.y - origin.y))
	if aoe == "AROUND":
		return 0
	return BattleGrid.manhattan(origin, c)

## 打到的格（不含 origin；只留場內格子）。length = 招式 range（LINE／FAN 的長度）。
static func cells(aoe: String, origin: Vector2i, center: Vector2i, length: int) -> Array:
	var out: Array = []
	match aoe:
		"SINGLE":
			out.append(center)
		"CROSS":
			out.append(center)
			for d in BattleGrid.DIRS:
				out.append(center + d)
		"CROSS_L":
			out.append(center)
			for d in BattleGrid.DIRS:
				for k in range(1, CROSS_L_ARM + 1):
					out.append(center + d * k)
		"LINE":
			var d := direction(origin, center)
			if d != Vector2i.ZERO:
				for k in range(1, maxi(1, length) + 1):
					out.append(origin + d * k)
		"FAN":
			var d := direction(origin, center)
			if d != Vector2i.ZERO:
				var i := DIR8.find(d)
				for dd in [DIR8[(i + 7) % 8], d, DIR8[(i + 1) % 8]]:
					for k in range(1, maxi(1, length) + 1):
						out.append(origin + dd * k)
		"AROUND":
			for d in DIR8:
				out.append(origin + d)
	var res: Array = []
	for p in out:
		if BattleGrid.in_bounds(p) and p != origin and not res.has(p):
			res.append(p)
	return res

## 範圍內的敵方活人（依 uid 排序，決定性）
static func enemies_in(b: Battle, u: BattleUnit, area: Array) -> Array:
	var out: Array = []
	for p in area:
		var t: BattleUnit = b.unit_at(p)
		if t != null and t.side != u.side and t.is_active():
			out.append(t)
	out.sort_custom(func(a, c): return a.uid < c.uid)
	return out

## 範圍招式的目標檢查（ART 驗證與 AI 共用）：回傳原因碼或 ""。
## bad_direction（LINE／FAN 的中心格不在 8 方向上）→ out_of_range → no_target（範圍內沒有敵人）
static func check(b: Battle, u: BattleUnit, move_row: Dictionary, center: Vector2i) -> String:
	var aoe := str(move_row.get("aoe", "SINGLE"))
	var rng_len := int(move_row.get("range", 1))
	if is_directional(aoe) and direction(u.pos, center) == Vector2i.ZERO:
		return "bad_direction"
	if aoe != "AROUND" and not BattleGrid.in_bounds(center):
		return "out_of_range"
	if center_distance(aoe, u.pos, center) > rng_len:
		return "out_of_range"
	if enemies_in(b, u, cells(aoe, u.pos, center, rng_len)).is_empty():
		return "no_target"
	return ""

## 給畫面標格子用的 [[x,y]…]
static func cells_json(area: Array) -> Array:
	var out: Array = []
	for p in area:
		out.append([p.x, p.y])
	return out
