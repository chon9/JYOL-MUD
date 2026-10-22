extends "res://tests/test_case.gd"
## 擁有者：按了地圖後要有棋子或人物圖一格一格趕路。RegionMapView 換房間時棋子從上一間滑到這一間。

var _nodes: Array = []

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame

func test_pos_at_glides_and_hops() -> void:
	var a := Vector2(0, 100)
	var b := Vector2(100, 100)
	assert_eq(MapToken.pos_at(a, b, 0.0, 40.0), a)
	assert_eq(MapToken.pos_at(a, b, 1.0, 40.0), b)
	var mid := MapToken.pos_at(a, b, 0.5, 40.0)
	assert_true(is_equal_approx(mid.x, 50.0), str(mid))
	assert_true(mid.y < 100.0, "hops up mid-way")

func _model() -> Dictionary:
	var room := func(id: String) -> Dictionary: return { "id": id, "name": id, "exits": [] }
	return { "name": "測試", "by_id": { "r1": room.call("r1"), "r2": room.call("r2"), "r3": room.call("r3") },
		"pos": { "r1": Vector2i(0, 0), "r2": Vector2i(1, 0), "r3": Vector2i(2, 0) }, "out_exits": [] }

func test_region_view_token_slides_between_rooms() -> void:
	var v := RegionMapView.new()
	tree.root.add_child(v)
	_nodes.append(v)
	v.size = Vector2(800, 400)
	var m := _model()
	var seen := { "r1": true, "r2": true, "r3": true }
	v.setup({}, m, seen, "r1")
	await tree.process_frame
	var at_r1: Vector2 = v.token_foot()
	v.setup({}, m, seen, "r2")
	var start: Vector2 = v.token_foot()
	assert_true(start.distance_to(at_r1) < 1.0, "starts at the previous room")
	assert_true(v.is_processing(), "animating")
	await tree.create_timer(MapToken.MOVE_S + 0.2).timeout
	var end: Vector2 = v.token_foot()
	assert_true(end.x > at_r1.x + 50.0, "ended at the next room: %s -> %s" % [at_r1, end])
	assert_false(v.is_processing(), "animation stops")

func test_region_change_does_not_slide() -> void:
	var v := RegionMapView.new()
	tree.root.add_child(v)
	_nodes.append(v)
	v.size = Vector2(800, 400)
	var m := _model()
	v.setup({}, m, { "r1": true }, "r1")
	var other := { "name": "他區", "by_id": { "x1": { "id": "x1", "name": "x1", "exits": [] } }, "pos": { "x1": Vector2i(0, 0) }, "out_exits": [] }
	v.setup({}, other, { "x1": true }, "x1")
	assert_false(v.is_processing(), "entering another region: token just appears")
