class_name BattleGrid
extends RefCounted
## 12×8 戰鬥格子（M1_PLAN 3.4.2、3.4.4）。只有存活且未逃走的單位會占格。

const W := 12
const H := 8
const PLAYER_X := 1
const ENEMY_X := 10
const Y_ORDER := [3, 4, 2, 5, 1, 6, 0, 7]
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var escape: Array[Vector2i] = []
var units: Array = []          # Array[BattleUnit]，由 place_units 設定

static func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < W and p.y >= 0 and p.y < H

static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func place_units(p_units: Array, _rng: RandomNumberGenerator) -> void:
	units = p_units
	var taken := {}
	for u in units:
		var col: int = PLAYER_X if u.side == 0 else ENEMY_X
		var placed := false
		# 先用該方的欄位；滿了再往外側欄位放（M1 一方最多 4 個，不會用到）
		for x in [col, col - 1 if u.side == 0 else col + 1, col + 1 if u.side == 0 else col - 1]:
			for y in Y_ORDER:
				var p := Vector2i(x, y)
				if in_bounds(p) and not taken.has(p):
					u.pos = p
					u.start_pos = p
					taken[p] = true
					placed = true
					break
			if placed:
				break

func unit_at(p: Vector2i) -> Variant:
	for u in units:
		if u.is_active() and u.pos == p:
			return u
	return null

func is_free(p: Vector2i) -> bool:
	return in_bounds(p) and unit_at(p) == null

func is_escape(p: Vector2i) -> bool:
	return escape.has(p)

## BFS（4 方向），不能穿越單位；不含起點。回傳順序為 BFS 順序（決定性）。
func reachable(from: Vector2i, steps: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if steps <= 0:
		return out
	var dist := { from: 0 }
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var d: int = dist[cur]
		if d >= steps:
			continue
		for dv in DIRS:
			var n: Vector2i = cur + dv
			if dist.has(n) or not is_free(n):
				continue
			dist[n] = d + 1
			queue.append(n)
			out.append(n)
	return out

## 從「空格且與每個玩家方起始格曼哈頓距離 ≥ 3」的格子中均勻抽 n 個（3.4.4）。
func place_escape_tiles(n: int, p_units: Array, rng: RandomNumberGenerator) -> void:
	escape.clear()
	var starts: Array[Vector2i] = []
	for u in p_units:
		if u.side == 0:
			starts.append(u.pos)
	var cands: Array[Vector2i] = []
	for y in H:
		for x in W:
			var p := Vector2i(x, y)
			var ok := true
			for u in p_units:
				if u.pos == p:
					ok = false
					break
			if not ok:
				continue
			for s in starts:
				if manhattan(p, s) < 3:
					ok = false
					break
			if ok:
				cands.append(p)
	for i in mini(n, cands.size()):
		var idx := rng.randi_range(0, cands.size() - 1)
		escape.append(cands[idx])
		cands.remove_at(idx)
