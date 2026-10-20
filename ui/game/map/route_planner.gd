class_name RoutePlanner
extends RefCounted
## 跨區域路徑規劃（M3C_PLAN §4.1、§4.3）：純靜態、不依賴場景樹，可在 --script 跑（驗收工具直接用）。
## - graph(tables)：全世界房間圖（目前生效的 tables 的 maps 與 exits；U/D/IN/OUT 也算，全部方向都走）。
## - find_path：只走 known（已探索）裡的房間，回 [from, …, to]；起點一定算 known。
## - nearest_known_toward：目標沒探索 → 從目標在全圖（含未探索）上做 BFS，由近到遠找第一個「已探索且從 from 走得到」的房間。
##   迷霧：未探索的房間只當 BFS 的距離參考，絕不放進路徑。
## - region_target：地區目標（江湖全圖點地區）。
## - quick_destinations：快捷目的地（記錄點、最近的客棧／茶棚／綠洲、本派山門、出生城、任務目標）。
## exits[].locked 只在主機的 view 裡有；規劃不看，執行時遇到才停（AutoWalkCore §4.4 #6）。

## room_id -> [{ "dir", "to" }]（區域依 id 排序、房間與出口依檔案順序，結果可重現；指向不存在房間的出口略過）
static func graph(tables: Dictionary) -> Dictionary:
	var g := {}
	var maps: Variant = tables.get("maps", {})
	if not (maps is Dictionary):
		return g
	var rids: Array = (maps as Dictionary).keys()
	rids.sort()
	var all_rooms: Array = []
	for rid in rids:
		var m: Variant = maps[rid]
		var rooms: Variant = (m as Dictionary).get("rooms", []) if m is Dictionary else []
		if not (rooms is Array):
			continue
		for room in rooms:
			if room is Dictionary and str(room.get("id", "")) != "" and not g.has(str(room["id"])):
				g[str(room["id"])] = []
				all_rooms.append(room)
	for room in all_rooms:
		var out: Array = g[str(room["id"])]
		var exits: Variant = room.get("exits", [])
		if not (exits is Array):
			continue
		for ex in exits:
			if not (ex is Dictionary):
				continue
			var to := str(ex.get("to", ""))
			if to == "" or not g.has(to):
				continue
			out.append({ "dir": str(ex.get("dir", "")), "to": to })
	return g

## 只走 known 裡的房間（起點一定算 known）；回 [from, …, to]（from == to 回 [from]）或 []
static func find_path(g: Dictionary, from: String, to: String, known: Dictionary) -> Array:
	if not g.has(from) or not g.has(to):
		return []
	if from == to:
		return [from]
	if not known.has(to):
		return []
	var prev := _bfs_known(g, from, known, to)
	if not prev.has(to):
		return []
	return _rebuild(prev, from, to)

## 目標沒探索（或走不到）：{ "room", "path", "exact": bool }；完全找不到回 { "room": "", "path": [], "exact": false }
static func nearest_known_toward(g: Dictionary, from: String, target: String, known: Dictionary) -> Dictionary:
	var none := { "room": "", "path": [], "exact": false }
	if not g.has(from) or not g.has(target):
		return none
	# 1. 從 from 只走已探索房間能到的地方（含 from）
	var prev := _bfs_known(g, from, known, "")
	if prev.has(target):
		return { "room": target, "path": _rebuild(prev, from, target), "exact": true }
	# 2. 從 target 在全圖（不分方向、含未探索）由近到遠找第一個走得到的已探索房間
	var und := _undirected(g)
	var seen := { target: true }
	var q: Array = [target]
	var head := 0
	while head < q.size():
		var cur: String = q[head]
		head += 1
		if prev.has(cur):
			return { "room": cur, "path": _rebuild(prev, from, cur), "exact": false }
		for nx in und.get(cur, []):
			if not seen.has(nx):
				seen[nx] = true
				q.append(nx)
	return none

## 地區目標：該地區已探索、走得到的房間中離 from 最近的；沒有 → nearest_known_toward(地區的 birth_room 或第一間)
## 回 { "room", "path", "exact" }（exact＝走得到該地區裡面）
static func region_target(tables: Dictionary, g: Dictionary, from: String, region_id: String, known: Dictionary) -> Dictionary:
	var none := { "room": "", "path": [], "exact": false }
	var rooms := _region_room_ids(tables, region_id)
	if rooms.is_empty() or not g.has(from):
		return none
	var in_region := {}
	for id in rooms:
		in_region[id] = true
	if in_region.has(from):
		return { "room": from, "path": [from], "exact": true }
	# BFS 依距離由近到遠：第一個落在該地區的已探索房間就是最近的
	var prev := _bfs_known(g, from, known, "")
	var order: Array = prev.get("__order", [])
	for id in order:
		if in_region.has(id):
			return { "room": id, "path": _rebuild(prev, from, id), "exact": true }
	var anchor := str(tables.get("regions", {}).get(region_id, {}).get("birth_room", "")) if tables.get("regions", {}) is Dictionary else ""
	if anchor == "" or not g.has(anchor):
		anchor = rooms[0]
	var r := nearest_known_toward(g, from, anchor, known)
	r["exact"] = false
	return r

## 路徑 [from, …, to] → 走法 [{ "dir", "to" }]（不含起點；AutoWalker 用）
static func steps(g: Dictionary, path: Array) -> Array:
	var out: Array = []
	for i in range(1, path.size()):
		var a := str(path[i - 1])
		var b := str(path[i])
		var dir := ""
		for e in g.get(a, []):
			if str(e.get("to", "")) == b:
				dir = str(e.get("dir", ""))
				break
		if dir == "":
			return []
		out.append({ "dir": dir, "to": b })
	return out

# ---------------------------------------------------------------- 快捷目的地（§4.3）

const QD_RECORD := "record"
const QD_INN := "inn"
const QD_SECT := "sect_gate"
const QD_BIRTH := "birth_city"
const QD_QUEST := "quest"
const QUICK_IDS := [QD_RECORD, QD_INN, QD_SECT, QD_BIRTH, QD_QUEST]
const QUICK_LABELS := {
	QD_RECORD: "記錄點", QD_INN: "最近的客棧", QD_SECT: "本派山門", QD_BIRTH: "出生城", QD_QUEST: "任務目標",
}
const WHY_NO_RECORD := "還沒設記錄點"
const WHY_NO_INN := "附近沒有探索過的客棧"
const WHY_NO_SECT := "你沒有門派"
const WHY_NO_BIRTH := "沒有出生城的資料"
const WHY_NO_QUEST := "沒有標記任務地點"
const WHY_HERE := "你就在這裡"
const WHY_NO_ROUTE := "找不到已知的路"

## 回 [{ id, label, room, name, ok, reason, path: [from…dest], exact, dest }]，依 QUICK_IDS 順序。
## exact = false：目標沒探索，只能走到 dest（最接近目標的已探索房間）；ok = false 時 reason 寫原因（灰掉）。
static func quick_destinations(tables: Dictionary, g: Dictionary, from: String, known: Dictionary, sheet: Dictionary, quest_mark: String) -> Array:
	var out: Array = []
	var resp: Variant = sheet.get("respawn", {})
	var resp_room := str((resp as Dictionary).get("room", "")) if resp is Dictionary else ""
	out.append(_quick(tables, g, from, known, QD_RECORD, resp_room, WHY_NO_RECORD))
	out.append(_quick_inn(tables, g, from, known))
	var sect := str(sheet.get("sect", ""))
	var gate := ""
	if sect != "":
		gate = str(_sect_row(tables, sect).get("gate_room", ""))
	var sq := _quick(tables, g, from, known, QD_SECT, gate, WHY_NO_SECT)
	if sect != "" and gate == "":
		sq["reason"] = "找不到本派山門"
	out.append(sq)
	var city := str(sheet.get("birth_city", ""))
	var regs: Variant = tables.get("regions", {})
	var birth_room := str((regs as Dictionary).get(city, {}).get("birth_room", "")) if regs is Dictionary and city != "" else ""
	out.append(_quick(tables, g, from, known, QD_BIRTH, birth_room, WHY_NO_BIRTH))
	out.append(_quick(tables, g, from, known, QD_QUEST, quest_mark, WHY_NO_QUEST))
	return out

static func _quick(tables: Dictionary, g: Dictionary, from: String, known: Dictionary, id: String, room: String, why_missing: String) -> Dictionary:
	var q := { "id": id, "label": str(QUICK_LABELS[id]), "room": room, "name": room_name(tables, room),
		"ok": false, "reason": "", "path": [], "exact": false, "dest": "" }
	if room == "" or not g.has(room):
		q["reason"] = why_missing
		return q
	if room == from:
		q["reason"] = WHY_HERE
		return q
	var r := nearest_known_toward(g, from, room, known)
	if str(r["room"]) == "" or str(r["room"]) == from:
		q["reason"] = WHY_NO_ROUTE if str(r["room"]) == "" else "再往前沒去過"
		return q
	q["ok"] = true
	q["path"] = r["path"]
	q["exact"] = bool(r["exact"])
	q["dest"] = str(r["room"])
	return q

## 最近的客棧／茶棚／綠洲：已探索、房內有 INN 服務 NPC、從 from 走得到且路徑最短的一間；名稱寫該房間名
static func _quick_inn(tables: Dictionary, g: Dictionary, from: String, known: Dictionary) -> Dictionary:
	var q := { "id": QD_INN, "label": str(QUICK_LABELS[QD_INN]), "room": "", "name": "",
		"ok": false, "reason": WHY_NO_INN, "path": [], "exact": false, "dest": "" }
	var inns := inn_rooms(tables)
	if inns.is_empty() or not g.has(from):
		return q
	if inns.has(from):
		q["room"] = from
		q["name"] = room_name(tables, from)
		q["reason"] = WHY_HERE
		return q
	var prev := _bfs_known(g, from, known, "")
	for id in prev.get("__order", []):
		if inns.has(id) and id != from:
			q["room"] = id
			q["name"] = room_name(tables, id)
			q["ok"] = true
			q["reason"] = ""
			q["path"] = _rebuild(prev, from, id)
			q["exact"] = true
			q["dest"] = id
			return q
	return q

## 房內有 INN 服務 NPC 的房間（房間的 npcs 清單，或 NPC 自己的 room 欄）
static func inn_rooms(tables: Dictionary) -> Dictionary:
	var out := {}
	var npcs: Variant = tables.get("npcs", {})
	if not (npcs is Dictionary):
		return out
	var maps: Variant = tables.get("maps", {})
	if maps is Dictionary:
		for rid in maps:
			var m: Variant = maps[rid]
			if not (m is Dictionary) or not (m.get("rooms", []) is Array):
				continue
			for room in m["rooms"]:
				if not (room is Dictionary):
					continue
				for nid in room.get("npcs", []):
					if _is_inn(npcs.get(str(nid), {})):
						out[str(room.get("id", ""))] = true
	for nid in npcs:
		var n: Variant = npcs[nid]
		if _is_inn(n) and str(n.get("room", "")) != "":
			out[str(n["room"])] = true
	out.erase("")
	return out

static func _is_inn(n: Variant) -> bool:
	return n is Dictionary and n.get("services", []) is Array and (n["services"] as Array).has("INN")

static func _sect_row(tables: Dictionary, sect: String) -> Dictionary:
	var sects: Variant = tables.get("sects", {})
	if sects is Dictionary:
		var row: Variant = (sects as Dictionary).get(sect, {})
		return row if row is Dictionary else {}
	if sects is Array:
		for row in sects:
			if row is Dictionary and str(row.get("id", "")) == sect:
				return row
	return {}

static func room_name(tables: Dictionary, room_id: String) -> String:
	if room_id == "":
		return ""
	var maps: Variant = tables.get("maps", {})
	if maps is Dictionary:
		for rid in maps:
			var m: Variant = maps[rid]
			if not (m is Dictionary) or not (m.get("rooms", []) is Array):
				continue
			for room in m["rooms"]:
				if room is Dictionary and str(room.get("id", "")) == room_id:
					return str(room.get("name", room_id))
	return room_id

static func room_region(tables: Dictionary, room_id: String) -> String:
	var maps: Variant = tables.get("maps", {})
	if maps is Dictionary:
		for rid in maps:
			var m: Variant = maps[rid]
			if not (m is Dictionary) or not (m.get("rooms", []) is Array):
				continue
			for room in m["rooms"]:
				if room is Dictionary and str(room.get("id", "")) == room_id:
					return str(rid)
	return ""

# ---------------------------------------------------------------- 內部

## 從 from 只走 known（起點一定算）做 BFS；回 prev { room: prev_room }，另有 "__order"：依距離的房間順序（含 from）。
## stop_at 非空時找到就提早結束。
static func _bfs_known(g: Dictionary, from: String, known: Dictionary, stop_at: String) -> Dictionary:
	var prev := { from: "" }
	var order: Array = [from]
	var head := 0
	while head < order.size():
		var cur: String = order[head]
		head += 1
		if cur == stop_at:
			break
		for e in g.get(cur, []):
			var nx := str(e.get("to", ""))
			if prev.has(nx) or not known.has(nx):
				continue
			prev[nx] = cur
			order.append(nx)
	prev["__order"] = order
	return prev

static func _rebuild(prev: Dictionary, from: String, to: String) -> Array:
	var path: Array = [to]
	var c := to
	var guard := 0
	while c != from and guard < 100000:
		c = str(prev.get(c, from))
		path.push_front(c)
		guard += 1
	return path

static func _undirected(g: Dictionary) -> Dictionary:
	var u := {}
	for a in g:
		if not u.has(a):
			u[a] = []
		for e in g[a]:
			var b := str(e.get("to", ""))
			if not (u[a] as Array).has(b):
				u[a].append(b)
			if not u.has(b):
				u[b] = []
			if not (u[b] as Array).has(a):
				u[b].append(a)
	return u

static func _region_room_ids(tables: Dictionary, region_id: String) -> Array:
	var out: Array = []
	var m: Variant = tables.get("maps", {}).get(region_id, {}) if tables.get("maps", {}) is Dictionary else {}
	if not (m is Dictionary) or not (m.get("rooms", []) is Array):
		return out
	for room in m["rooms"]:
		if room is Dictionary and str(room.get("id", "")) != "":
			out.append(str(room["id"]))
	return out
