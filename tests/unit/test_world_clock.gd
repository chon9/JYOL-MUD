extends "res://tests/test_case.gd"
## WorldClock（M1_PLAN 4.15）與 WorldIndex（3.11.8）：純邏輯，用測試內自建的 maps fixture。

const DAY := 7200.0
const SC := 600.0

func test_new_world_starts_at_chen() -> void:
	var c := WorldClock.clock(0.0, DAY)
	assert_eq(c["shichen_idx"], 4)
	assert_eq(c["shichen_name"], "辰")
	assert_eq(c["ke"], 0)
	assert_eq(c["text"], "辰時初刻")
	assert_eq(c["night"], false)
	assert_eq(c["day"], 1)
	assert_eq(c["month"], 1)
	assert_eq(c["year"], 1)

func test_ke_and_shichen_progress() -> void:
	assert_eq(WorldClock.clock(SC * 3.0 / 8.0 + 1.0, DAY)["text"], "辰時三刻")
	assert_eq(WorldClock.clock(SC * 7.0 / 8.0 + 1.0, DAY)["ke"], 7)
	assert_eq(WorldClock.clock(SC, DAY)["shichen_name"], "巳")
	assert_eq(WorldClock.clock(SC * 2.0, DAY)["shichen_name"], "午")

func test_night_hours() -> void:
	# 辰(4) → 戌(10) 要 6 個時辰
	var names := []
	var nights := []
	for i in 12:
		var c := WorldClock.clock(SC * i + 1.0, DAY)
		names.append(c["shichen_name"])
		nights.append(c["night"])
	assert_eq(names, ["辰", "巳", "午", "未", "申", "酉", "戌", "亥", "子", "丑", "寅", "卯"])
	assert_eq(nights, [false, false, false, false, false, false, true, true, true, true, true, false])

func test_calendar() -> void:
	# clock_s = world + 4×600；第 2 天從 clock_s = 7200 開始
	assert_eq(WorldClock.clock(DAY - 4.0 * SC - 1.0, DAY)["day"], 1)
	assert_eq(WorldClock.clock(DAY - 4.0 * SC, DAY)["day"], 2)
	var c := WorldClock.clock(DAY * 30.0, DAY)   # day 31
	assert_eq(c["day"], 31)
	assert_eq(c["month"], 2)
	var c2 := WorldClock.clock(DAY * 360.0, DAY)  # day 361
	assert_eq(c2["month"], 1)
	assert_eq(c2["year"], 2)

func test_custom_day_length() -> void:
	var c := WorldClock.clock(0.0, 1200.0)       # 1 時辰 = 100 秒
	assert_eq(c["shichen_name"], "辰")
	assert_eq(WorldClock.clock(600.0, 1200.0)["shichen_name"], "戌")
	assert_true(WorldClock.clock(600.0, 1200.0)["night"])

func test_seconds_until_shichen() -> void:
	var d := WorldClock.seconds_until_shichen(0.0, 10, DAY)
	assert_eq(d, SC * 6.0)
	assert_eq(WorldClock.clock(d, DAY)["shichen_name"], "戌")
	var d2 := WorldClock.seconds_until_shichen(SC * 7.0, 3, DAY)   # 亥 → 卯
	assert_eq(WorldClock.clock(SC * 7.0 + d2, DAY)["shichen_name"], "卯")
	assert_eq(WorldClock.seconds_until_shichen(0.0, 4, DAY), 0.0)

func _maps() -> Dictionary:
	return {
		"maps": {
			"r_a": { "region_id": "r_a", "escape_tiles_hint": 3, "rooms": [
				{ "id": "a1", "name": "甲一", "exits": [ { "dir": "E", "to": "a2" } ], "npcs": ["n_1"] },
				{ "id": "a2", "name": "甲二", "exits": [ { "dir": "W", "to": "a1" }, { "dir": "IN", "to": "b1" } ],
				  "encounter": { "rate": 0.25, "table": [] } },
			] },
			"r_b": { "region_id": "r_b", "rooms": [
				{ "id": "b1", "name": "乙一", "exits": [ { "dir": "OUT", "to": "a2" } ] },
			] },
		},
		"npcs": { "n_1": { "id": "n_1", "room": "a1" }, "n_2": { "id": "n_2", "room": "b1" } },
	}

func test_index_rooms_and_regions() -> void:
	var idx := WorldIndex.new(_maps())
	assert_eq(idx.rooms.size(), 3)
	assert_eq(idx.region_of("a2"), "r_a")
	assert_eq(idx.region_of("b1"), "r_b")
	assert_eq(idx.region_of("zz"), "")
	assert_true(idx.has_room("b1"))
	assert_eq(idx.room("a1")["name"], "甲一")

func test_index_npcs_and_exits() -> void:
	var idx := WorldIndex.new(_maps())
	assert_eq(idx.room_of_npc("n_1"), "a1")
	assert_eq(idx.room_of_npc("n_2"), "b1", "from npcs.room when the room list omits it")
	assert_eq(idx.npcs_in("b1"), ["n_2"])
	assert_eq(idx.exit_of("a2", "IN")["to"], "b1")
	assert_true(idx.exit_of("a2", "N").is_empty())
	assert_eq(idx.encounter_rate("a2"), 0.25)
	assert_eq(idx.encounter_rate("a1"), 0.0)
	assert_eq(idx.escape_tiles_hint("r_a"), 3)
	assert_eq(idx.escape_tiles_hint("r_b"), 2, "default 2")

func test_dir_helpers() -> void:
	assert_eq(WorldIndex.reverse_dir("NE"), "SW")
	assert_eq(WorldIndex.reverse_dir("IN"), "OUT")
	assert_eq(WorldIndex.reverse_dir("U"), "D")
	assert_eq(WorldIndex.dir_label("SE"), "東南")
	assert_eq(WorldIndex.dir_label("OUT"), "出")
	for d in Protocol.DIRS:
		assert_eq(WorldIndex.reverse_dir(WorldIndex.reverse_dir(d)), d, d)
		assert_true(WorldIndex.dir_label(d) != d, d)
