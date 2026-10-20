extends "res://tests/test_case.gd"
## M3C_PLAN §4.1、§4.3（WP-NAV）：RoutePlanner——跨區最短路、迷霧（只走已探索房間）、目標沒探索、地區目標、快捷目的地挑選。
## 真資料（1.0A）＋小型假地圖（精確的邊界情況）。

var loader: DataLoader
var view: Dictionary
var g: Dictionary

## 西夏廣場 → 華山山門（跨 6 個地區、14 間）
const XX_TO_HS := ["xx_square", "xx_gate_e", "xw_road", "xe_road", "xe_mine", "xe_heilong", "xe_river",
	"hf_paddy", "hf_teahouse", "hf_shore", "hf_fork", "hy_road", "hy_foot", "hs_gate"]

func before_each() -> void:
	if loader == null:
		loader = DataLoader.new()
		loader.load_all("res://data")
		view = loader.activate(["1.0A"])
		g = RoutePlanner.graph(view)

func _known(ids: Array) -> Dictionary:
	var k := {}
	for id in ids:
		k[id] = true
	return k

## 假地圖：區域 ra：a1–a2–a3（a2 往北 a4）；區域 rb：b1–b2–b3；a3 東接 b1；另有 a4 往東直通 b3（捷徑，沒探索）
##   a1 ─ a2 ─ a3 ═ b1 ─ b2 ─ b3
##        │                    │
##        a4 ──────────────────┘
func _fake() -> Dictionary:
	var room := func(id: String, exits: Array) -> Dictionary:
		var ex: Array = []
		for e in exits:
			ex.append({ "dir": e[0], "to": e[1] })
		return { "id": id, "name": "房" + id, "exits": ex, "npcs": [], "requires": [] }
	return {
		"maps": {
			"ra": { "rooms": [room.call("a1", [["E", "a2"]]), room.call("a2", [["W", "a1"], ["E", "a3"], ["N", "a4"]]),
				room.call("a3", [["W", "a2"], ["E", "b1"]]), room.call("a4", [["S", "a2"], ["E", "b3"]])] },
			"rb": { "rooms": [room.call("b1", [["W", "a3"], ["E", "b2"]]), room.call("b2", [["W", "b1"], ["E", "b3"]]),
				room.call("b3", [["W", "b2"], ["W", "a4"]])] },
		},
		"regions": { "ra": { "name": "甲區", "birth_room": "a1" }, "rb": { "name": "乙區", "birth_room": "b3" } },
		"npcs": {},
	}

# ---------------------------------------------------------------- graph / find_path

func test_graph_covers_every_room_and_exit() -> void:
	assert_true(g.has("xx_square") and g.has("hs_gate") and g.has("dl_square"))
	var found := false
	for e in g["xx_gate_e"]:
		if e["to"] == "xw_road" and e["dir"] == "E":
			found = true
	assert_true(found, "xx_gate_e E → xw_road (cross-region exit)")
	# 出口指向不存在的房間不收
	var t := _fake()
	t["maps"]["ra"]["rooms"][0]["exits"].append({ "dir": "S", "to": "nowhere" })
	var fg := RoutePlanner.graph(t)
	assert_eq((fg["a1"] as Array).size(), 1, "dangling exit dropped")

func test_cross_region_shortest_path() -> void:
	var known := _known(XX_TO_HS)
	var p := RoutePlanner.find_path(g, "xx_square", "hs_gate", known)
	assert_eq(p, XX_TO_HS, "shortest explored route")
	var regions := {}
	for id in p:
		regions[RoutePlanner.room_region(view, id)] = true
	assert_true(regions.size() >= 2, "path crosses regions: %s" % str(regions.keys()))
	var st := RoutePlanner.steps(g, p)
	assert_eq(st.size(), p.size() - 1)
	assert_eq(st[0], { "dir": "E", "to": "xx_gate_e" })
	assert_eq(st[1], { "dir": "E", "to": "xw_road" })
	assert_eq(RoutePlanner.find_path(g, "xx_square", "xx_square", {}), ["xx_square"], "from == to")
	assert_eq(RoutePlanner.find_path(g, "xx_square", "nope", known), [])

func test_fog_only_explored_rooms() -> void:
	var t := _fake()
	var fg := RoutePlanner.graph(t)
	# a4–b3 捷徑沒探索：只能走 a2–a3–b1–b2–b3
	var known := _known(["a1", "a2", "a3", "b1", "b2", "b3"])
	assert_eq(RoutePlanner.find_path(fg, "a1", "b3", known), ["a1", "a2", "a3", "b1", "b2", "b3"])
	# 探索了 a4 → 捷徑最短
	known["a4"] = true
	assert_eq(RoutePlanner.find_path(fg, "a1", "b3", known), ["a1", "a2", "a4", "b3"])
	# 中間一間（b1）沒探索、也沒有捷徑：走不到
	assert_eq(RoutePlanner.find_path(fg, "a1", "b3", _known(["a2", "a3", "b2", "b3"])), [])
	# 目標沒探索：find_path 一律不走
	assert_eq(RoutePlanner.find_path(fg, "a1", "b3", _known(["a2", "a3", "b1", "b2"])), [])
	# 起點一定算 known
	assert_eq(RoutePlanner.find_path(fg, "a1", "a2", _known(["a2"])), ["a1", "a2"])
	# 真資料：路徑只含已探索房間
	var half := _known(XX_TO_HS.slice(0, 7))
	var p := RoutePlanner.find_path(g, "xx_square", "xe_river", half)
	assert_true(p.size() >= 2)
	for id in p:
		assert_true(half.has(id), "%s explored" % id)

func test_target_unexplored_goes_to_nearest_known() -> void:
	var t := _fake()
	var fg := RoutePlanner.graph(t)
	# 只探索到 a3：目標 b3（沒去過）→ 從 b3 由近到遠：b2、a4（距 1）沒探索；a3（經 b1 距 3）、a2（經 a4 距 2）→ a2 最近
	var r := RoutePlanner.nearest_known_toward(fg, "a1", "b3", _known(["a1", "a2", "a3"]))
	assert_eq(r["room"], "a2", "nearest explored room to b3 (via the unexplored shortcut)")
	assert_eq(r["path"], ["a1", "a2"])
	assert_false(r["exact"])
	# 未探索房間絕不放進路徑
	r = RoutePlanner.nearest_known_toward(fg, "a1", "b2", _known(["a2", "a3"]))
	assert_eq(r["room"], "a3")
	assert_eq(r["path"], ["a1", "a2", "a3"])
	# 目標已探索且走得到 → exact
	r = RoutePlanner.nearest_known_toward(fg, "a1", "a3", _known(["a2", "a3"]))
	assert_true(r["exact"])
	assert_eq(r["path"], ["a1", "a2", "a3"])
	# 什麼都沒探索：最近的就是起點自己
	r = RoutePlanner.nearest_known_toward(fg, "a1", "b3", {})
	assert_eq(r["room"], "a1")
	assert_eq(r["path"], ["a1"])
	# 真資料：只走到黑龍潭外的河邊，華山山門沒去過
	var known := _known(XX_TO_HS.slice(0, 7))
	r = RoutePlanner.nearest_known_toward(g, "xx_square", "hs_gate", known)
	assert_eq(r["room"], "xe_river", "closest explored room toward 華山")
	assert_false(r["exact"])
	for id in r["path"]:
		assert_true(known.has(id) or id == "xx_square")

func test_region_target() -> void:
	var t := _fake()
	var fg := RoutePlanner.graph(t)
	# 乙區探索過 b1、b2：取離起點最近的 b1
	var r := RoutePlanner.region_target(t, fg, "a1", "rb", _known(["a2", "a3", "b1", "b2"]))
	assert_eq(r["room"], "b1")
	assert_eq(r["path"], ["a1", "a2", "a3", "b1"])
	assert_true(r["exact"])
	# 乙區一間都沒去過：往 birth_room（b3）的最近已探索房間
	r = RoutePlanner.region_target(t, fg, "a1", "rb", _known(["a2", "a3"]))
	assert_false(r["exact"])
	assert_eq(r["room"], "a2", "nearest explored room toward b3 (via the unexplored a4 shortcut)")
	# 已在該區
	r = RoutePlanner.region_target(t, fg, "b2", "rb", {})
	assert_eq(r["room"], "b2")
	assert_eq(r["path"], ["b2"])
	# 真資料：西夏 → 華山（只探索了路上）
	r = RoutePlanner.region_target(view, g, "xx_square", "huashan", _known(XX_TO_HS))
	assert_eq(r["room"], "hs_gate")
	assert_true(r["exact"])
	assert_eq((r["path"] as Array).size(), XX_TO_HS.size())

# ---------------------------------------------------------------- 快捷目的地

func test_quick_destinations() -> void:
	var known := _known(XX_TO_HS + ["xx_inn", "xx_station"])
	var sheet := { "respawn": { "room": "xx_station" }, "sect": "huashan", "birth_city": "xixia" }
	var items := RoutePlanner.quick_destinations(view, g, "xw_road", known, sheet, "hf_teahouse")
	assert_eq(items.size(), 5)
	var by := {}
	for q in items:
		by[q["id"]] = q
	assert_eq(items.map(func(q): return q["id"]), RoutePlanner.QUICK_IDS, "fixed order")
	# 記錄點
	assert_true(by["record"]["ok"], str(by["record"]))
	assert_eq(by["record"]["dest"], "xx_station")
	assert_eq((by["record"]["path"] as Array)[0], "xw_road")
	# 最近的客棧：從西夏野外，西夏客棧（4 步）比衡山腳茶棚近
	var inns := RoutePlanner.inn_rooms(view)
	assert_true(inns.has("xx_inn") and inns.has("hf_teahouse"), str(inns.keys()))
	assert_true(by["inn"]["ok"], str(by["inn"]))
	assert_eq(by["inn"]["room"], "xx_inn")
	assert_eq(by["inn"]["name"], RoutePlanner.room_name(view, "xx_inn"))
	# 從衡山腳出發：茶棚最近
	var from_hf := RoutePlanner.quick_destinations(view, g, "hf_shore", known, sheet, "")
	assert_eq(from_hf[1]["room"], "hf_teahouse")
	# 本派山門
	assert_true(by["sect_gate"]["ok"])
	assert_eq(by["sect_gate"]["dest"], "hs_gate")
	assert_true(by["sect_gate"]["exact"])
	# 出生城
	assert_eq(by["birth_city"]["room"], "xx_square")
	assert_true(by["birth_city"]["ok"])
	# 任務目標
	assert_true(by["quest"]["ok"])
	assert_eq(by["quest"]["dest"], "hf_teahouse")

func test_quick_destinations_disabled_reasons() -> void:
	var items := RoutePlanner.quick_destinations(view, g, "xx_square", _known(["xx_square"]), {}, "")
	var by := {}
	for q in items:
		by[q["id"]] = q
	assert_false(by["record"]["ok"])
	assert_eq(by["record"]["reason"], RoutePlanner.WHY_NO_RECORD)
	assert_eq(by["inn"]["reason"], RoutePlanner.WHY_NO_INN)
	assert_eq(by["sect_gate"]["reason"], RoutePlanner.WHY_NO_SECT)
	assert_eq(by["quest"]["reason"], RoutePlanner.WHY_NO_QUEST)
	assert_false(by["birth_city"]["ok"])
	# 就在那裡
	var here := RoutePlanner.quick_destinations(view, g, "xx_square", {}, { "birth_city": "xixia" }, "")
	assert_eq(here[3]["reason"], RoutePlanner.WHY_HERE)
	# 目標沒探索：只能走到附近（exact = false）
	var part := RoutePlanner.quick_destinations(view, g, "xx_square", _known(XX_TO_HS.slice(0, 7)), { "sect": "huashan" }, "")
	assert_true(part[2]["ok"])
	assert_false(part[2]["exact"])
	assert_eq(part[2]["dest"], "xe_river")
	assert_eq(MapPanel.quick_label(part[2]), "本派山門：%s（只能走到附近）" % RoutePlanner.room_name(view, "hs_gate"))
	assert_eq(MapPanel.quick_label(by["sect_gate"]), "本派山門（你沒有門派）")
