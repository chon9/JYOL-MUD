extends "res://tests/test_case.gd"
## ROGUE_PLAN §5.1、§9.1（WP-UI）：標題畫面「江湖試煉」按鈕在「單機遊玩」同一列右邊，按下切到 rogue 場景；
## SceneRouter.SCENES 有 rogue；rogue 場景能載入並顯示大廳（沒有主機）。

var _nodes: Array = []
var _old_root := ""
var _dir := ""

func before_each() -> void:
	UiSettings.reset_for_tests(true)
	var smn: Node = tree.root.get_node("SaveManager")
	_old_root = smn.root_dir
	_dir = temp_dir("ui_rogue_title")
	smn.root_dir = _dir

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame
	tree.root.get_node("SaveManager").root_dir = _old_root
	remove_dir_recursive(_dir)

func _title() -> Node:
	var t: Node = (load("res://ui/game/title/title_screen.tscn") as PackedScene).instantiate()
	tree.root.add_child(t)
	_nodes.append(t)
	return t

func test_button_next_to_offline() -> void:
	var t := _title()
	await tree.process_frame
	var b: Button = t.btn_rogue
	assert_true(b != null, "button exists")
	assert_eq(b.text, "江湖試煉")
	assert_eq(str(b.name), "RogueButton")
	var off: Button = t.btn_offline
	assert_eq(off.text, "單機遊玩")
	assert_true(b.get_parent() == off.get_parent(), "same row")
	assert_true(b.get_parent() is HBoxContainer, "row is horizontal")
	assert_eq(b.get_index(), off.get_index() + 1, "right of 單機遊玩")
	await tree.process_frame
	assert_true(b.get_global_rect().position.x > off.get_global_rect().position.x, "to the right on screen")
	assert_true(absf(b.get_global_rect().position.y - off.get_global_rect().position.y) < 1.0, "same line")
	assert_true(b.pressed.is_connected(t._on_rogue), "wired")
	assert_true(b.tooltip_text.contains("非原作"), "tooltip marks the proposal")

func test_router_has_rogue_scene() -> void:
	var sr = tree.root.get_node("SceneRouter")
	assert_has(sr.SCENES, "rogue")
	assert_eq(sr.SCENES["rogue"], "res://ui/game/rogue/rogue_screen.tscn")
	assert_true(ResourceLoader.exists(sr.SCENES["rogue"]), "scene file")
	var n := (load(sr.SCENES["rogue"]) as PackedScene).instantiate()
	assert_true(n is RogueScreen, "root is RogueScreen")
	tree.root.add_child(n)
	_nodes.append(n)
	await tree.process_frame
	await tree.process_frame
	assert_eq(n.view, UiKeys.ROGUE_VIEW_LOBBY, "lobby without host")
	assert_true(n.lobby.visible, "lobby shown")
	assert_false(n.hud.visible, "no hud in lobby")
	assert_eq(n.lobby.points_label.text, "永久點數 0 / 60", "fresh profile")

func test_pressing_switches_to_rogue_scene() -> void:
	var sr = tree.root.get_node("SceneRouter")
	var old_current: String = sr.current
	var t := _title()
	await tree.process_frame
	t.btn_rogue.pressed.emit()
	for i in 4:
		await tree.process_frame
	assert_eq(sr.current, "rogue", "router")
	var cur := tree.current_scene
	assert_true(cur != null and cur is RogueScreen, "rogue screen is the current scene")
	if cur != null and cur != t:
		_nodes.append(cur)
	sr.current = old_current
