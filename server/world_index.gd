class_name WorldIndex
extends RefCounted
## 房間圖索引（M1_PLAN 3.5.2、3.11.8）：由 tables.maps 建 room_id -> room、room_id -> region_id、npc_id -> room_id。

const REVERSE := {
	"N": "S", "S": "N", "E": "W", "W": "E", "NE": "SW", "SW": "NE", "NW": "SE", "SE": "NW",
	"U": "D", "D": "U", "IN": "OUT", "OUT": "IN",
}
const LABELS := {
	"N": "北", "S": "南", "E": "東", "W": "西", "NE": "東北", "NW": "西北", "SE": "東南", "SW": "西南",
	"U": "上", "D": "下", "IN": "進", "OUT": "出",
}

var rooms: Dictionary = {}          # room_id -> room dict
var room_region: Dictionary = {}    # room_id -> region_id
var npc_room: Dictionary = {}       # npc_id -> room_id
var region_maps: Dictionary = {}    # region_id -> map dict（不含 rooms 以外的引用複製）

func _init(tables: Dictionary = {}) -> void:
	if not tables.is_empty():
		build(tables)

func build(tables: Dictionary) -> void:
	rooms.clear()
	room_region.clear()
	npc_room.clear()
	region_maps.clear()
	var maps: Dictionary = tables.get("maps", {})
	var ids: Array = maps.keys()
	ids.sort()
	for rid in ids:
		var m: Variant = maps[rid]
		if not (m is Dictionary):
			continue
		region_maps[rid] = m
		var rlist: Variant = m.get("rooms", [])
		if not (rlist is Array):
			continue
		for room in rlist:
			if not (room is Dictionary) or str(room.get("id", "")) == "":
				continue
			var room_id := str(room["id"])
			rooms[room_id] = room
			room_region[room_id] = rid
			for npc_id in room.get("npcs", []):
				npc_room[str(npc_id)] = room_id
	# npcs 表的 room 欄位為輔（房間清單沒有列到時）
	var npcs: Dictionary = tables.get("npcs", {})
	for npc_id in npcs:
		var r := str(npcs[npc_id].get("room", ""))
		if r != "" and not npc_room.has(npc_id) and rooms.has(r):
			npc_room[npc_id] = r

func has_room(room_id: String) -> bool:
	return rooms.has(room_id)

func room(room_id: String) -> Dictionary:
	return rooms.get(room_id, {})

func region_of(room_id: String) -> String:
	return room_region.get(room_id, "")

func room_of_npc(npc_id: String) -> String:
	return npc_room.get(npc_id, "")

## 房間內的 NPC id（房間清單 + npcs 表 room 欄位指向此房間者）
func npcs_in(room_id: String) -> Array:
	var out: Array = []
	for npc_id in room(room_id).get("npcs", []):
		out.append(str(npc_id))
	for npc_id in npc_room:
		if npc_room[npc_id] == room_id and not (npc_id in out):
			out.append(npc_id)
	return out

## 回傳此方向的出口 dict（找不到回 {}）
func exit_of(room_id: String, dir: String) -> Dictionary:
	for ex in room(room_id).get("exits", []):
		if ex is Dictionary and str(ex.get("dir", "")) == dir:
			return ex
	return {}

## 兩個房間之間最少要走幾步（沿出口 BFS）；超過 max_hops 或走不到回 -1（審查修正：新手歡迎風聲挑近的事件）
func hops(from_room: String, to_room: String, max_hops: int = 64) -> int:
	if not rooms.has(from_room) or not rooms.has(to_room):
		return -1
	if from_room == to_room:
		return 0
	var seen := { from_room: true }
	var frontier: Array = [from_room]
	for d in range(1, max_hops + 1):
		var nxt: Array = []
		for rid in frontier:
			for ex in room(str(rid)).get("exits", []):
				if not (ex is Dictionary):
					continue
				var to := str(ex.get("to", ""))
				if to == "" or seen.has(to) or not rooms.has(to):
					continue
				if to == to_room:
					return d
				seen[to] = true
				nxt.append(to)
		if nxt.is_empty():
			return -1
		frontier = nxt
	return -1

func escape_tiles_hint(region_id: String) -> int:
	return int(region_maps.get(region_id, {}).get("escape_tiles_hint", 2))

func encounter_rate(room_id: String) -> float:
	var enc: Variant = room(room_id).get("encounter", {})
	if enc is Dictionary:
		return float(enc.get("rate", 0.0))
	return 0.0

static func dir_label(dir: String) -> String:
	return LABELS.get(dir, dir)

static func reverse_dir(dir: String) -> String:
	return REVERSE.get(dir, "")
