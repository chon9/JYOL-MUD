class_name MapLayout
extends RefCounted
## 大地圖的純計算部分（不碰節點、不碰網路，方便單元測試）：
## 1. 區域房間自動排版：從根房間 BFS，依出口方向給格子座標；撞格時以固定順序找最近空格（結果可重現）。
## 2. 客戶端尋路：只走「已知」房間之間的出口，回傳逐步的 { dir, to }。
## 房間資料格式同 data/maps/*.json 的 rooms[]：{ id, exits: [{ dir, to }] }。

## 出口方向 → 格子位移。U／D／IN／OUT 不是平面方向，給一個斜向位移讓它們不疊在同一格，
## 畫線時另外標字（見 is_planar）。
const DIR_VEC := {
	"N": Vector2i(0, -1), "S": Vector2i(0, 1), "E": Vector2i(1, 0), "W": Vector2i(-1, 0),
	"NE": Vector2i(1, -1), "NW": Vector2i(-1, -1), "SE": Vector2i(1, 1), "SW": Vector2i(-1, 1),
	"U": Vector2i(1, -1), "D": Vector2i(-1, 1), "IN": Vector2i(1, -1), "OUT": Vector2i(-1, 1),
}
const PLANAR := ["N", "S", "E", "W", "NE", "NW", "SE", "SW"]
const MAX_RING := 12

static func dir_vec(dir: String) -> Vector2i:
	return DIR_VEC.get(dir, Vector2i(1, 0))

static func is_planar(dir: String) -> bool:
	return PLANAR.has(dir)

## rooms: Array[Dictionary]（區域內全部房間，依檔案順序）；root: 根房間 id（空字串＝第一個房間）。
## 回傳 { room_id: Vector2i }，座標已平移到最小 (0,0)。區域內不連通的房間另起一團，放在右邊。
static func layout(rooms: Array, root: String = "") -> Dictionary:
	var by_id := {}
	var order: Array = []
	for r in rooms:
		if r is Dictionary and str(r.get("id", "")) != "" and not by_id.has(str(r["id"])):
			by_id[str(r["id"])] = r
			order.append(str(r["id"]))
	var pos := {}        # room_id -> Vector2i
	var taken := {}      # Vector2i -> room_id
	if order.is_empty():
		return pos
	var starts: Array = []
	if root != "" and by_id.has(root):
		starts.append(root)
	starts.append_array(order)
	for start in starts:
		if pos.has(start):
			continue
		var origin := Vector2i.ZERO
		if not pos.is_empty():
			var bb := _bounds(pos)
			origin = Vector2i(bb.end.x + 1, bb.position.y)   # bb.end 是 max+1，再空一格
		origin = _free_near(origin, Vector2i(1, 0), taken)
		_place(start, origin, pos, taken)
		var q: Array = [start]
		while not q.is_empty():
			var cur: String = q.pop_front()
			for ex in by_id[cur].get("exits", []):
				if not (ex is Dictionary):
					continue
				var to := str(ex.get("to", ""))
				if not by_id.has(to) or pos.has(to):
					continue
				var v := dir_vec(str(ex.get("dir", "")))
				_place(to, _free_near(pos[cur] + v, v, taken), pos, taken)
				q.append(to)
	# 平移到 (0,0)
	var b := _bounds(pos)
	var out := {}
	for id in pos:
		out[id] = pos[id] - b.position
	return out

static func _place(id: String, at: Vector2i, pos: Dictionary, taken: Dictionary) -> void:
	pos[id] = at
	taken[at] = id

## 目標格空著就用；否則先沿方向再延伸 1~2 格，再以環狀距離由近到遠找（同距離依 y、x 排序）。
static func _free_near(target: Vector2i, v: Vector2i, taken: Dictionary) -> Vector2i:
	if not taken.has(target):
		return target
	for k in [1, 2]:
		var c: Vector2i = target + v * k
		if not taken.has(c):
			return c
	for ring in range(1, MAX_RING + 1):
		var cands: Array = []
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var c := target + Vector2i(dx, dy)
				if not taken.has(c):
					cands.append(c)
		if cands.is_empty():
			continue
		cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := (a - target).length_squared()
			var db := (b - target).length_squared()
			if da != db:
				return da < db
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x)
		return cands[0]
	# 理論上到不了：往右找第一個空格
	var c2 := target
	while taken.has(c2):
		c2.x += 1
	return c2

## 所有座標的外框（position = 最小值，end = 最大值 + 1）
static func _bounds(pos: Dictionary) -> Rect2i:
	var first := true
	var mn := Vector2i.ZERO
	var mx := Vector2i.ZERO
	for id in pos:
		var p: Vector2i = pos[id]
		if first:
			mn = p
			mx = p
			first = false
		else:
			mn = Vector2i(mini(mn.x, p.x), mini(mn.y, p.y))
			mx = Vector2i(maxi(mx.x, p.x), maxi(mx.y, p.y))
	return Rect2i(mn, mx - mn + Vector2i.ONE)

static func bounds(pos: Dictionary) -> Rect2i:
	return Rect2i() if pos.is_empty() else _bounds(pos)

## 最短路徑（BFS，依出口在資料中的順序展開，結果可重現）。
## rooms_by_id: { room_id: room dict }；known: { room_id: true }（只走已知房間；空字典＝不限制）。
## 回傳 [{ "dir": "N", "to": "room_id" }, ...]（不含起點）；起點＝終點或到不了回 []。
static func find_path(rooms_by_id: Dictionary, from: String, to: String, known: Dictionary = {}) -> Array:
	if from == to or not rooms_by_id.has(from) or not rooms_by_id.has(to):
		return []
	if not known.is_empty() and not known.has(to):
		return []
	var prev := {}   # room -> [prev_room, dir]
	var seen := { from: true }
	var q: Array = [from]
	while not q.is_empty():
		var cur: String = q.pop_front()
		if cur == to:
			break
		var room: Variant = rooms_by_id.get(cur, {})
		if not (room is Dictionary):
			continue
		for ex in room.get("exits", []):
			if not (ex is Dictionary):
				continue
			var nxt := str(ex.get("to", ""))
			if seen.has(nxt) or not rooms_by_id.has(nxt):
				continue
			if not known.is_empty() and not known.has(nxt):
				continue
			seen[nxt] = true
			prev[nxt] = [cur, str(ex.get("dir", ""))]
			q.append(nxt)
	if not seen.has(to):
		return []
	var steps: Array = []
	var c := to
	while c != from:
		var pv: Array = prev[c]
		steps.push_front({ "dir": pv[1], "to": c })
		c = pv[0]
	return steps

# ---------- 繪圖用幾何（區域圖／江湖全圖共用） ----------
## 從方框中心往 dir 方向射出，回傳打到方框邊緣的點（連線從框邊開始，不穿過框內的字）
static func box_edge_point(center: Vector2, half: Vector2, dir: Vector2) -> Vector2:
	if dir.length_squared() < 0.0001:
		return center
	var tx := INF if absf(dir.x) < 0.0001 else half.x / absf(dir.x)
	var ty := INF if absf(dir.y) < 0.0001 else half.y / absf(dir.y)
	return center + dir * minf(tx, ty)

## 線段 p–q 是否碰到矩形（含端點在矩形內）
static func segment_hits_rect(p: Vector2, q: Vector2, r: Rect2) -> bool:
	if r.has_point(p) or r.has_point(q):
		return true
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(p, q, c[i], c[(i + 1) % 4]) != null:
			return true
	return false

static func polyline_hits_rect(pts: PackedVector2Array, r: Rect2) -> bool:
	for i in pts.size() - 1:
		if segment_hits_rect(pts[i], pts[i + 1], r):
			return true
	return false

## 二次貝茲曲線取樣（含兩端點）
static func bezier(a: Vector2, ctrl: Vector2, b: Vector2, samples: int = 24) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in samples + 1:
		var t := float(i) / float(samples)
		out.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return out

## a→b 的路線：先試直線，再依序試左右彎曲越來越大的曲線，回傳第一條不碰任何障礙矩形的折線；
## 都不行（障礙夾在中間、要繞 S 形）且給了 bounds 時，在 bounds 內用格子 A* 找路再拉直、圓角；
## 全部失敗時回傳碰撞最少的那條。
const ROUTE_BENDS := [0.0, 0.08, -0.08, 0.16, -0.16, 0.26, -0.26, 0.38, -0.38, 0.5, -0.5]
const ROUTE_GRID := 5.0

static func route_around(a: Vector2, b: Vector2, obstacles: Array, bounds: Rect2 = Rect2(), clear: float = ROUTE_CLEAR) -> PackedVector2Array:
	var mid := (a + b) / 2.0
	var perp := (b - a).orthogonal()
	var best := PackedVector2Array([a, b])
	var best_hits := 1 << 30
	for k in ROUTE_BENDS:
		var pts := PackedVector2Array([a, b]) if k == 0.0 else bezier(a, mid + perp * float(k), b)
		var hits := count_hits(pts, obstacles)
		if hits == 0:
			return pts
		if hits < best_hits:
			best_hits = hits
			best = pts
	if bounds.has_area():
		var g := grid_route(a, b, obstacles, bounds, clear)
		if not g.is_empty() and count_hits(g, obstacles) == 0:
			return g
	return best

static func count_hits(pts: PackedVector2Array, obstacles: Array) -> int:
	var hits := 0
	for r in obstacles:
		if polyline_hits_rect(pts, r):
			hits += 1
	return hits

static func _blocked(p: Vector2, obstacles: Array) -> bool:
	for r in obstacles:
		if (r as Rect2).has_point(p):
			return true
	return false

## 格子 A*（8 方向、二元堆積）→ 拉直（看得到就直接連）→ Chaikin 圓角（圓角後碰到障礙就不圓）
## 格點要離障礙至少 ROUTE_CLEAR，相鄰格點之間的短線段才不會切到障礙的角。
const ROUTE_CLEAR := 4.0

static func grid_route(a: Vector2, b: Vector2, obstacles: Array, bounds: Rect2, clear: float = ROUTE_CLEAR) -> PackedVector2Array:
	var cols := int(ceil(bounds.size.x / ROUTE_GRID)) + 1
	var rows := int(ceil(bounds.size.y / ROUTE_GRID)) + 1
	var to_cell := func(p: Vector2) -> Vector2i:
		return Vector2i(clampi(roundi((p.x - bounds.position.x) / ROUTE_GRID), 0, cols - 1),
			clampi(roundi((p.y - bounds.position.y) / ROUTE_GRID), 0, rows - 1))
	var to_pt := func(c: Vector2i) -> Vector2:
		return bounds.position + Vector2(c) * ROUTE_GRID
	var fat: Array = []
	for r in obstacles:
		fat.append((r as Rect2).grow(clear))
	var start: Vector2i = to_cell.call(a)
	var goal: Vector2i = to_cell.call(b)
	var heap: Array = [[Vector2(start).distance_to(Vector2(goal)), start]]   # [f, cell]
	var came := {}
	var g := { start: 0.0 }
	var closed := {}
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	var found := false
	while not heap.is_empty():
		var cur: Vector2i = _heap_pop(heap)[1]
		if closed.has(cur):
			continue
		closed[cur] = true
		if cur == goal:
			found = true
			break
		for d in dirs:
			var n: Vector2i = cur + d
			if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows or closed.has(n):
				continue
			if n != goal and _blocked(to_pt.call(n), fat):
				continue
			var ng: float = float(g[cur]) + Vector2(d).length()
			if ng < float(g.get(n, INF)):
				g[n] = ng
				came[n] = cur
				_heap_push(heap, [ng + Vector2(n).distance_to(Vector2(goal)), n])
	if not found:
		return PackedVector2Array()
	var cells: Array = [goal]
	while cells[0] != start:
		cells.push_front(came[cells[0]])
	var raw := PackedVector2Array([a])
	for i in range(1, cells.size() - 1):
		raw.append(to_pt.call(cells[i]))
	raw.append(b)
	# 拉直：從目前點往後找最遠一個「直線看得到」的點
	var pulled := PackedVector2Array([raw[0]])
	var i0 := 0
	while i0 < raw.size() - 1:
		var j := raw.size() - 1
		while j > i0 + 1 and count_hits(PackedVector2Array([raw[i0], raw[j]]), obstacles) > 0:
			j -= 1
		pulled.append(raw[j])
		i0 = j
	var smooth := pulled
	for _it in 3:
		if smooth.size() < 3:
			break
		var nxt := PackedVector2Array([smooth[0]])
		for k in smooth.size() - 1:
			if k > 0:
				nxt.append(smooth[k].lerp(smooth[k + 1], 0.25))
			if k < smooth.size() - 2:
				nxt.append(smooth[k].lerp(smooth[k + 1], 0.75))
		nxt.append(smooth[smooth.size() - 1])
		if count_hits(nxt, obstacles) > 0:
			break
		smooth = nxt
	return smooth

## 從候選矩形中挑第一個不碰到任何線段（[p, q]）與障礙矩形的；全部都碰到時回傳 0（第一個候選）
static func pick_free_rect(candidates: Array, segments: Array, obstacles: Array, bounds: Rect2 = Rect2()) -> int:
	var best := 0
	var best_hits := 1 << 30
	for i in candidates.size():
		var c: Rect2 = candidates[i]
		var hits := 0
		if bounds.has_area() and not bounds.encloses(c):
			hits += 100
		for s in segments:
			if segment_hits_rect(s[0], s[1], c):
				hits += 1
		for o in obstacles:
			if (o as Rect2).intersects(c):
				hits += 1
		if hits == 0:
			return i
		if hits < best_hits:
			best_hits = hits
			best = i
	return best

static func _heap_push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if float(h[p][0]) <= float(item[0]):
			break
		h[i] = h[p]
		i = p
	h[i] = item

static func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if h.is_empty():
		return top
	var i := 0
	var n := h.size()
	while true:
		var l := i * 2 + 1
		if l >= n:
			break
		var c := l
		if l + 1 < n and float(h[l + 1][0]) < float(h[l][0]):
			c = l + 1
		if float(h[c][0]) >= float(last[0]):
			break
		h[i] = h[c]
		i = c
	h[i] = last
	return top
