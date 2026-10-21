class_name MapData
extends RefCounted
## 大地圖的資料整理（唯讀，只讀客戶端本地的 GameData 資料表；不碰主機狀態）。
## tables 的格式同 GameData.tables：{ "maps": { region_id: map }, "regions": {...}, "npcs": {...}, "monsters": {...} }。

## 區域類型 → 顏色與短字（GDD：城／郊／派／洞）
const TYPE_LABELS := { "CITY": "城", "WILD": "郊", "SECT": "派", "DUNGEON": "洞" }
const TYPE_COLORS := {
	"CITY": Color("c9a66b"), "WILD": Color("8fb37a"), "SECT": Color("b58ac0"), "DUNGEON": Color("7d6e66"),
}
## 房間 feature → 小字標記
const FEATURE_BADGES := { "FIELD": "田", "WOOD": "林", "WATER": "水", "STOVE": "灶" }
## NPC 服務 → 小字標記（依此順序檢查；客棧老闆同時賣東西時只標「客棧」）
const BADGE_ORDER := ["驛站", "客棧", "商店", "師父", "查小鏞"]

## room_id -> { "room": Dictionary, "region": String }（區域依 id 排序，房間依檔案順序）
static func room_index(tables: Dictionary) -> Dictionary:
	var idx := {}
	var maps: Dictionary = tables.get("maps", {})
	var rids: Array = maps.keys()
	rids.sort()
	for rid in rids:
		var rooms: Variant = (maps[rid] as Dictionary).get("rooms", []) if maps[rid] is Dictionary else []
		if not (rooms is Array):
			continue
		for room in rooms:
			if room is Dictionary and str(room.get("id", "")) != "" and not idx.has(str(room["id"])):
				idx[str(room["id"])] = { "room": room, "region": str(rid) }
	return idx

static func region_rooms(tables: Dictionary, region_id: String) -> Array:
	var m: Variant = tables.get("maps", {}).get(region_id, {})
	if not (m is Dictionary):
		return []
	var rooms: Variant = m.get("rooms", [])
	return (rooms as Array).filter(func(r): return r is Dictionary) if rooms is Array else []

static func region_name(tables: Dictionary, region_id: String) -> String:
	return str(tables.get("regions", {}).get(region_id, {}).get("name", region_id))

## 房間上的 NPC／地形小字標記，例如 ["驛站", "灶"]
static func room_badges(tables: Dictionary, room: Dictionary) -> PackedStringArray:
	var found := {}
	var npcs: Dictionary = tables.get("npcs", {})
	for nid in room.get("npcs", []):
		var n: Variant = npcs.get(str(nid), {})
		if not (n is Dictionary):
			continue
		var svc: Array = n.get("services", [])
		if svc.has("TRAVEL"):
			found["驛站"] = true
		if svc.has("INN"):
			found["客棧"] = true
		elif svc.has("SHOP"):
			found["商店"] = true
		if svc.has("TEACH") or svc.has("JOIN") or str(n.get("kind", "")) == "MASTER":
			found["師父"] = true
		if svc.has("RESPAWN"):
			found["查小鏞"] = true
	var out: PackedStringArray = []
	for b in BADGE_ORDER:
		if found.has(b):
			out.append(b)
	for f in room.get("features", []):
		var fb: String = FEATURE_BADGES.get(str(f), "")
		if fb != "" and not out.has(fb):
			out.append(fb)
	return out

## 房間的 NPC 名稱
static func room_npc_names(tables: Dictionary, room: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for nid in room.get("npcs", []):
		out.append(str(tables.get("npcs", {}).get(str(nid), {}).get("name", nid)))
	return out

## 遇敵怪物名稱（依權重由高到低）；安全地回 []
static func room_danger(tables: Dictionary, room: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var enc: Variant = room.get("encounter", {})
	if not (enc is Dictionary) or float(enc.get("rate", 0.0)) <= 0.0:
		return out
	var rows: Array = []
	for e in enc.get("table", []):
		if e is Dictionary and float(e.get("w", 0)) > 0.0:
			rows.append(e)
	rows.sort_custom(func(a, b): return float(a.get("w", 0)) > float(b.get("w", 0)))
	for e in rows:
		var nm := str(tables.get("monsters", {}).get(str(e.get("monster", "")), {}).get("name", e.get("monster", "")))
		if not out.has(nm):
			out.append(nm)
	return out

static func encounter_rate(room: Dictionary) -> float:
	var enc: Variant = room.get("encounter", {})
	return float(enc.get("rate", 0.0)) if enc is Dictionary else 0.0

## 區域模型：{ region, name, rooms: Array, by_id: {id: room}, pos: {id: Vector2i},
##   out_exits: [{ from, dir, to, to_name, to_region, to_region_name }] }
static func region_model(tables: Dictionary, region_id: String) -> Dictionary:
	var rooms := region_rooms(tables, region_id)
	var by_id := {}
	for r in rooms:
		by_id[str(r.get("id", ""))] = r
	var idx := room_index(tables)
	var out_exits: Array = []
	for r in rooms:
		for ex in r.get("exits", []):
			if not (ex is Dictionary):
				continue
			var to := str(ex.get("to", ""))
			if by_id.has(to) or not idx.has(to):
				continue
			var trg: String = idx[to]["region"]
			out_exits.append({
				"from": str(r.get("id", "")), "dir": str(ex.get("dir", "")), "to": to,
				"to_name": str(idx[to]["room"].get("name", to)),
				"to_region": trg, "to_region_name": region_name(tables, trg),
			})
	return {
		"region": region_id, "name": region_name(tables, region_id),
		"rooms": rooms, "by_id": by_id, "pos": MapLayout.layout(rooms), "out_exits": out_exits,
	}

## 依迷霧過濾：visible = 已到過的房間；unknown = 與已到過房間相鄰（同區）但沒去過的房間
static func fog(model: Dictionary, visited: Dictionary) -> Dictionary:
	var by_id: Dictionary = model.get("by_id", {})
	var vis := {}
	var unk := {}
	for id in by_id:
		if visited.has(id):
			vis[id] = true
	for id in vis:
		# M3d 審查：迷陣（房間列 hide_exit_names，八卦泥陣）不畫相鄰沒去過的「？」——
		# 「？」畫在真正的方向上（走錯的單向出口不畫）＝小地圖直接洩漏解法
		if bool(by_id[id].get("hide_exit_names", false)):
			continue
		for ex in by_id[id].get("exits", []):
			if ex is Dictionary:
				var to := str(ex.get("to", ""))
				if by_id.has(to) and not vis.has(to):
					unk[to] = true
	return { "visible": vis, "unknown": unk }

## 江湖全圖模型：
## { regions: [{ id, name, type, pos: Vector2, xp: [a,b] }],
##   walk: [[a, b]]（步行相連的區域，a < b），travel: [[a, b]]（驛站路線，a < b） }
## 沒有 world_pos 的區域不畫（但仍可出現在線條裡就略過那條線）。
## 驛站馬車是【設計提案・非原作】，伺服器選項 stagecoach_enabled 預設關：關著時 travel 一律為空，
## 全圖只畫步行路線（WORLD_2001 D5）。
static func world_model(tables: Dictionary, stagecoach_enabled: bool = false) -> Dictionary:
	var regions: Dictionary = tables.get("regions", {})
	var maps: Dictionary = tables.get("maps", {})
	var ids: Array = regions.keys()
	ids.sort()
	var out_regions: Array = []
	var placed := {}
	for rid in ids:
		var r: Variant = regions[rid]
		if not (r is Dictionary) or not maps.has(rid):
			continue
		var wp: Variant = r.get("world_pos", null)
		if not (wp is Array) or wp.size() != 2:
			continue
		var xp: Variant = r.get("suggested_xp", [0, 0])
		out_regions.append({
			"id": str(rid), "name": str(r.get("name", rid)), "type": str(r.get("type", "")),
			"pos": Vector2(float(wp[0]), float(wp[1])),
			"xp": xp if (xp is Array and xp.size() == 2) else [0, 0],
		})
		placed[str(rid)] = true
	var idx := room_index(tables)
	var walk := {}
	for room_id in idx:
		var a: String = idx[room_id]["region"]
		for ex in idx[room_id]["room"].get("exits", []):
			if not (ex is Dictionary) or not idx.has(str(ex.get("to", ""))):
				continue
			var b: String = idx[str(ex["to"])]["region"]
			if a != b and placed.has(a) and placed.has(b):
				walk[_pair_key(a, b)] = _pair(a, b)
	var travel := {}
	var npcs: Dictionary = tables.get("npcs", {}) if stagecoach_enabled else {}
	for nid in npcs:
		var n: Variant = npcs[nid]
		if not (n is Dictionary) or not (n.get("services", []) as Array).has("TRAVEL"):
			continue
		var from_room := str(n.get("room", ""))
		if not idx.has(from_room):
			continue
		var a: String = idx[from_room]["region"]
		for rt in n.get("travel", []):
			if not (rt is Dictionary) or not idx.has(str(rt.get("to_room", ""))):
				continue
			var b: String = idx[str(rt["to_room"])]["region"]
			if a != b and placed.has(a) and placed.has(b):
				travel[_pair_key(a, b)] = _pair(a, b)
	return { "regions": out_regions, "walk": _sorted_values(walk), "travel": _sorted_values(travel) }

static func _pair(a: String, b: String) -> Array:
	return [a, b] if a < b else [b, a]

static func _pair_key(a: String, b: String) -> String:
	var p := _pair(a, b)
	return "%s|%s" % [p[0], p[1]]

static func _sorted_values(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort()
	return keys.map(func(k): return d[k])

## 「建議實戰 a~b」；兩個都是 0（城市、門派）回空字串
static func xp_text(xp: Array) -> String:
	if xp.size() != 2 or (int(xp[0]) <= 0 and int(xp[1]) <= 0):
		return ""
	return "建議實戰 %d~%d" % [int(xp[0]), int(xp[1])]
