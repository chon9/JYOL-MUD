extends "res://tests/test_case.gd"
## M3C2_PLAN §6.2、§5.3（WP-CARRY）：標題畫面右下角版本列、「允許外來角色」勾選、大廳不相容列附主機的值。

var _nodes: Array = []
var _old_root := ""
var _dir := ""

func before_each() -> void:
	UiSettings.reset_for_tests(true)
	var smn: Node = tree.root.get_node("SaveManager")
	_old_root = smn.root_dir
	_dir = temp_dir("ui_title")
	smn.root_dir = _dir

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame
	tree.root.get_node("SaveManager").root_dir = _old_root
	var w: Node = tree.root.get_node("WorldServer")
	w.host_foreign_choice = -1
	remove_dir_recursive(_dir)

func _title() -> Node:
	var t: Node = (load("res://ui/game/title/title_screen.tscn") as PackedScene).instantiate()
	tree.root.add_child(t)
	_nodes.append(t)
	return t

func test_build_line_bottom_right() -> void:
	var t := _title()
	await tree.process_frame
	await tree.process_frame
	var l: Label = t.build_label
	assert_true(l != null, "label")
	assert_eq(str(l.name), "BuildInfoLine")
	assert_eq(l.text, BuildInfo.line(GameData.content_hash))
	assert_true(l.text.begins_with("v0.7.0.0　協定 5　資料 "), l.text)
	assert_eq(l.text.length(), ("v0.7.0.0　協定 5　資料 ").length() + 12, "12-char fingerprint")
	assert_eq(l.tooltip_text, "跟朋友連線前互相對照：協定與資料指紋都一樣才能連線。")
	assert_eq(str(l.theme_type_variation), "MutedLabel", "muted")
	# 右下角：右緣、下緣貼齊畫面（留 12 px 邊）
	var vp: Vector2 = t.get_viewport_rect().size
	var r: Rect2 = l.get_global_rect()
	assert_true(absf(r.end.x - (vp.x - 12.0)) <= 1.5, "right edge %s vs %s" % [str(r.end.x), str(vp.x)])
	assert_true(absf(r.end.y - (vp.y - 12.0)) <= 1.5, "bottom edge %s vs %s" % [str(r.end.y), str(vp.y)])

func test_foreign_checkbox_follows_world_options_and_sets_host_choice() -> void:
	var smn: Node = tree.root.get_node("SaveManager")
	assert_eq(smn.save_options("w_has_foreign", { "allow_foreign_characters": true }), OK)
	var t := _title()
	await tree.process_frame
	var cb: CheckBox = t.foreign_check
	assert_true(cb != null)
	assert_eq(cb.text, "允許外來角色")
	assert_false(cb.button_pressed, "default world: unchecked")
	t.world_edit.text = "w_has_foreign"
	t.world_edit.text_changed.emit("w_has_foreign")
	assert_true(cb.button_pressed, "existing world with option on")
	t.world_edit.text = "w_new_world"
	t.world_edit.text_changed.emit("w_new_world")
	assert_false(cb.button_pressed, "new world off")
	cb.button_pressed = true
	t._apply_foreign_choice()
	assert_eq(int(tree.root.get_node("WorldServer").host_foreign_choice), 1, "passed to WorldServer")

func test_lobby_host_values() -> void:
	var TL = (load("res://ui/game/title/title_screen.gd") as GDScript).TitleLobby
	assert_eq(TL.host_values({ "proto": "4" }), "（主機 協定 4）")
	assert_eq(TL.host_values({ "proto": "6", "version": "0.7.0.0", "fp": "sha256:abcdefabcdef0000" }), "（主機 v0.7.0.0　協定 6　資料 abcdefabcdef）")
	assert_eq(TL.host_values({}), "")
	assert_true(TL.label({ "name": "房", "members": 2, "proto": "4" }).ends_with("版本不符（主機 協定 4）"))
	assert_false(TL.label({ "name": "房", "members": 2, "proto": str(Protocol.VERSION) }).contains("版本不符"))

## M3c2 第二輪審查 #5：同協定、不同資料指紋的大廳灰掉（大廳公布 fp；舊主機沒有 fp → 只看協定）
func test_lobby_fingerprint_must_match() -> void:
	var TL = (load("res://ui/game/title/title_screen.gd") as GDScript).TitleLobby
	var p := str(Protocol.VERSION)
	assert_true(TL.compatible({ "proto": p, "fp": "9d24a2e10ccc" }, "9d24a2e10ccc"))
	assert_false(TL.compatible({ "proto": p, "fp": "9d24a2e10ccc" }, "96cdbf897d9b"), "same proto, other data")
	assert_true(TL.compatible({ "proto": p, "fp": "sha256:9d24a2e10ccc0000" }, "sha256:9d24a2e10ccc1111"), "first 12 chars")
	assert_true(TL.compatible({ "proto": p }, "96cdbf897d9b"), "old host without fp")
	assert_false(TL.compatible({ "proto": "4", "fp": "96cdbf897d9b" }, "96cdbf897d9b"), "proto still checked")
	assert_true(TL.label({ "name": "房", "members": 1, "proto": p, "ver": "0.6.0.0", "fp": "000000000000" }).contains("版本不符（主機 v0.6.0.0"),
		"label shows host values")
