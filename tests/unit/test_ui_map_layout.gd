extends "res://tests/test_case.gd"
## 大地圖（ui/game/map）：排版演算法（可重現、不重疊、每張地圖每間房都有位置）、客戶端尋路、
## 小字標記、跨區出口、迷霧、江湖全圖模型、world_pos 資料檢查、本機到過房間紀錄。

const DataLint := preload("res://tools/data_lint.gd")

var loader: DataLoader
var view: Dictionary

func before_each() -> void:
	if loader == null:
		loader = DataLoader.new()
		loader.load_all("res://data")
		view = loader.activate(["1.0A"])

static func _room(id: String, exits: Array) -> Dictionary:
	var ex: Array = []
	for e in exits:
		ex.append({ "dir": e[0], "to": e[1] })
	return { "id": id, "name": id, "exits": ex }

func _assert_valid_layout(rooms: Array, pos: Dictionary, label: String) -> void:
	var seen := {}
	var mn := Vector2i(1 << 20, 1 << 20)
	for r in rooms:
		var id := str(r["id"])
		if not assert_true(pos.has(id), "%s: room %s not placed" % [label, id]):
			continue
		var p: Vector2i = pos[id]
		assert_false(seen.has(p), "%s: %s overlaps %s at %s" % [label, id, seen.get(p, ""), str(p)])
		seen[p] = id
		mn = Vector2i(mini(mn.x, p.x), mini(mn.y, p.y))
	assert_eq(pos.size(), rooms.size(), "%s: placed count" % label)
	assert_eq(mn, Vector2i.ZERO, "%s: normalized to (0,0)" % label)

# ---------------------------------------------------------------- 排版

func test_every_map_file_lays_out_without_overlap() -> void:
	assert_true(loader.all_maps.size() >= 9, "map files loaded")
	for rid in loader.all_maps:
		var rooms: Array = loader.all_maps[rid]["rooms"]
		var pos := MapLayout.layout(rooms)
		_assert_valid_layout(rooms, pos, "maps/%s" % rid)

func test_layout_is_deterministic() -> void:
	for rid in loader.all_maps:
		var rooms: Array = loader.all_maps[rid]["rooms"]
		var a := MapLayout.layout(rooms)
		var b := MapLayout.layout(rooms.duplicate(true))
		assert_eq(a, b, "maps/%s twice" % rid)

func test_layout_follows_exit_directions() -> void:
	var pos := MapLayout.layout(loader.all_maps["dali"]["rooms"])
	var sq: Vector2i = pos["dl_square"]
	assert_eq(pos["dl_station"] - sq, Vector2i(-1, 0), "W")
	assert_eq(pos["dl_gate_n"] - sq, Vector2i(0, -1), "N")
	assert_eq(pos["dl_inn"] - sq, Vector2i(1, 0), "E")
	assert_eq(pos["dl_yamen"] - sq, Vector2i(0, 1), "S")
	assert_eq(pos["dl_wuguan"] - sq, Vector2i(-1, 1), "SW")
	assert_eq(pos["dl_shop"] - sq, Vector2i(1, 1), "SE")
	var xx := MapLayout.layout(loader.all_maps["xixia"]["rooms"])
	assert_eq(xx["xx_wuguan"] - xx["xx_square"], Vector2i(-2, 0), "two steps west")
	assert_eq(xx["xx_inn_2f"] - xx["xx_inn"], MapLayout.DIR_VEC["U"], "U uses its offset")

func test_layout_resolves_collisions_deterministically() -> void:
	# a 東邊是 b，a 北邊是 c，c 東邊是 d，b 北邊又是 e：d 與 e 搶同一格
	var rooms := [
		_room("a", [["E", "b"], ["N", "c"]]),
		_room("b", [["W", "a"], ["N", "e"]]),
		_room("c", [["S", "a"], ["E", "d"]]),
		_room("d", [["W", "c"]]),
		_room("e", [["S", "b"]]),
	]
	var pos := MapLayout.layout(rooms)
	_assert_valid_layout(rooms, pos, "collide")
	assert_eq(pos, MapLayout.layout(rooms), "same result twice")
	# e 先排（BFS 順序 a→b→c→e→d），d 被推開
	assert_eq(pos["e"] - pos["b"], Vector2i(0, -1))
	assert_true(pos["d"] != pos["e"])

func test_layout_handles_disconnected_and_bad_rooms() -> void:
	var rooms := [
		_room("a", [["E", "b"], ["N", "ghost"]]),
		_room("b", [["W", "a"]]),
		_room("x", [["S", "y"]]),
		_room("y", [["N", "x"]]),
		"not a room",
		{ "id": "" },
	]
	var pos := MapLayout.layout(rooms)
	assert_eq(pos.size(), 4)
	_assert_valid_layout(rooms.slice(0, 4), pos, "disconnected")
	assert_true(pos["x"].x > pos["b"].x, "second cluster to the right")
	assert_eq(MapLayout.layout([]), {})

func test_layout_many_rooms_same_cell() -> void:
	var exits: Array = []
	var rooms: Array = []
	for i in 12:
		exits.append(["N", "r%d" % i])
		rooms.append(_room("r%d" % i, [["S", "hub"]]))
	rooms.push_front(_room("hub", exits))
	var pos := MapLayout.layout(rooms)
	_assert_valid_layout(rooms, pos, "fan-out")

# ---------------------------------------------------------------- 尋路

func _by_id(rid: String) -> Dictionary:
	var d := {}
	for r in loader.all_maps[rid]["rooms"]:
		d[r["id"]] = r
	return d

func test_find_path_shortest() -> void:
	var by_id := _by_id("xixia")
	var path := MapLayout.find_path(by_id, "xx_inn_2f", "xx_wuguan")
	var dirs: Array = path.map(func(s): return s["dir"])
	assert_eq(dirs, ["D", "S", "W", "W"])
	assert_eq(path[path.size() - 1]["to"], "xx_wuguan")
	assert_eq(MapLayout.find_path(by_id, "xx_square", "xx_square"), [], "same room")
	assert_eq(MapLayout.find_path(by_id, "xx_square", "nowhere"), [], "unknown room")

func test_find_path_only_known_rooms() -> void:
	var by_id := _by_id("xixia")
	var known := { "xx_square": true, "xx_station": true, "xx_wuguan": true }
	assert_eq(MapLayout.find_path(by_id, "xx_square", "xx_wuguan", known), [], "street unknown")
	known["xx_street"] = true
	assert_eq(MapLayout.find_path(by_id, "xx_station", "xx_wuguan", known).size(), 3)
	assert_eq(MapLayout.find_path(by_id, "xx_square", "xx_inn", known), [], "target unknown")

# ---------------------------------------------------------------- MapData

func test_room_badges() -> void:
	var idx := MapData.room_index(view)
	assert_has(MapData.room_badges(view, idx["dl_station"]["room"]), "驛站")
	var inn := MapData.room_badges(view, idx["dl_inn"]["room"])
	assert_has(inn, "客棧")
	assert_has(inn, "灶")
	assert_not_has(inn, "商店", "inn covers shop")
	assert_has(MapData.room_badges(view, idx["dl_shop"]["room"]), "商店")
	assert_has(MapData.room_badges(view, idx["sl_wuchang"]["room"]), "師父")
	assert_has(MapData.room_badges(view, idx["xx_gate_e"]["room"]), "查小鏞")
	assert_eq(MapData.room_badges(view, idx["xw_wood"]["room"]), PackedStringArray(["師父", "林"]))
	assert_has(MapData.room_badges(view, idx["dlw_paddy"]["room"]), "田")
	assert_has(MapData.room_badges(view, idx["xw_creek"]["room"]), "水")

func test_room_danger() -> void:
	var idx := MapData.room_index(view)
	assert_eq(MapData.room_danger(view, idx["xx_square"]["room"]).size(), 0)
	var d := MapData.room_danger(view, idx["dlw_forest"]["room"])
	assert_eq(d.size(), 3)
	assert_eq(d[0], str(view["monsters"]["m_boar"]["name"]), "highest weight first")

func test_region_model_out_exits() -> void:
	var m := MapData.region_model(view, "xixia")
	# 9 間 + 故事包 4 間（民房、衙門、皇宮門口、皇宮密道；STORY_PLAN §2.2）+ M3b 4 間（錢莊、鏢局、打鐵舖、布莊）
	assert_eq((m["by_id"] as Dictionary).size(), 17)
	assert_eq((m["pos"] as Dictionary).size(), 17)
	var found := false
	for oe in m["out_exits"]:
		if oe["from"] == "xx_gate_e" and oe["dir"] == "E":
			found = true
			assert_eq(oe["to_region"], "xixia_wild")
			assert_eq(oe["to_region_name"], "西夏郊外")
	assert_true(found, "east gate leads out")
	var dw := MapData.region_model(view, "dali_wild")
	var dirs: Array = dw["out_exits"].map(func(o): return "%s>%s" % [o["dir"], o["to_region"]])
	assert_has(dirs, "NW>river_road")
	assert_has(dirs, "S>dali")
	# 鬼王在血刀洞迷宮（西夏東郊的血刀洞口進去），不在大理郊外（WORLD_2001）
	assert_not_has(dirs, "IN>guiwang")
	var xe := MapData.region_model(view, "xixia_east")
	var xdirs: Array = xe["out_exits"].map(func(o): return "%s>%s" % [o["dir"], o["to_region"]])
	assert_has(xdirs, "IN>guiwang")

func test_fog() -> void:
	var m := MapData.region_model(view, "xixia")
	var f := MapData.fog(m, { "xx_square": true, "jc_inn": true })
	assert_eq(f["visible"].keys(), ["xx_square"])
	var unk: Array = f["unknown"].keys()
	unk.sort()
	# xx_yamen：故事包（廣場西北）；xx_bank、xx_biaoju：M3b（廣場旁）
	assert_eq(unk, ["xx_bank", "xx_biaoju", "xx_gate_e", "xx_inn", "xx_station", "xx_street", "xx_yamen"])

func test_world_model() -> void:
	var w := MapData.world_model(view)
	assert_eq(w["regions"].size(), view["regions"].size(), "every region has world_pos")
	assert_has(w["walk"], ["dali", "dali_wild"])
	assert_has(w["walk"], ["guiwang", "xixia_east"])
	assert_has(w["walk"], ["huashan", "huayin_road"])
	assert_not_has(w["walk"], ["dali", "xixia"])
	# 1.0A 沒有京城；驛站馬車預設關 → 全圖沒有驛站路線
	assert_false(view["regions"].has("jingcheng"), "1.0A has no 京城")
	assert_eq(w["travel"].size(), 0, "stagecoach off: no travel routes")
	var wc := MapData.world_model(view, true)
	assert_has(wc["travel"], ["dali", "xixia"])
	var pos := {}
	for r in w["regions"]:
		pos[r["id"]] = r["pos"]
	assert_true(pos["xixia"].y < pos["dali"].y, "西夏 north of 大理")
	assert_true(pos["xixia"].x < pos["shaolin"].x and pos["dali"].x < pos["shaolin"].x, "少林 east of both cities")
	# 1.0B 才有京城與京城驛站路線
	var vb := loader.activate(["1.0A", "1.0B"])
	var wb := MapData.world_model(vb, true)
	assert_has(wb["travel"], ["dali", "jingcheng"])
	assert_has(wb["travel"], ["jingcheng", "xixia"])
	assert_has(wb["walk"], ["huayin_road", "jingcheng_wild"])

func test_xp_text() -> void:
	assert_eq(MapData.xp_text([0, 0]), "")
	assert_eq(MapData.xp_text([0, 2000]), "建議實戰 0~2000")
	assert_eq(MapData.xp_text([10000, 20000]), "建議實戰 10000~20000")

# ---------------------------------------------------------------- data_lint world_pos

func test_world_pos_is_coerced_to_int() -> void:
	for rid in view["regions"]:
		var wp: Variant = view["regions"][rid].get("world_pos")
		assert_true(wp is Array and wp.size() == 2, "%s world_pos" % rid)
		assert_type(wp[0], TYPE_INT, rid)

func test_lint_world_pos_shape() -> void:
	assert_eq(DataLint.check_world_pos(view["regions"]).size(), 0, "real data clean")
	var bad := {
		"a": { "world_pos": [1] }, "b": { "world_pos": "1,2" }, "c": { "world_pos": [1, "x"] },
		"d": { "world_pos": [-1, 3] }, "e": { "world_pos": [5, 5] }, "f": { "world_pos": [5, 5] },
		"g": { "name": "no pos is fine" },
	}
	var errs := DataLint.check_world_pos(bad)
	assert_eq(errs.size(), 5, "\n".join(errs))
	var joined := "\n".join(errs)
	for id in ["regions.a", "regions.b", "regions.c", "regions.d", "regions.f"]:
		assert_true(joined.contains(id + ":"), id)

# ---------------------------------------------------------------- MapMemory

func test_map_memory_roundtrip() -> void:
	var dir := temp_dir("mapmem")
	var m := MapMemory.new(dir)
	m.mark("xx_square")           # 還沒選角：只在記憶體
	m.set_char("ch_abc")
	assert_true(m.has("xx_square"), "carried over")
	assert_true(m.mark("xx_street"))
	assert_false(m.mark("xx_street"), "already known")
	var m2 := MapMemory.new(dir)
	m2.set_char("ch_abc")
	assert_true(m2.has("xx_square") and m2.has("xx_street"))
	m2.set_char("ch_other")
	assert_false(m2.has("xx_square"), "per character")
	var m3 := MapMemory.new(dir)
	m3.set_char("../../evil")
	assert_eq(m3.char_id, "evil", "sanitized")
	remove_dir_recursive(dir)
