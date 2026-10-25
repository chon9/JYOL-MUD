extends "res://tests/unit/test_world_fixture.gd"
## ROGUE_PLAN U10、O1、O5、§9.1（WP-RUN）：江湖試煉不影響 MUD。
## 試煉世界不寫 worlds/、passports/；MUD 世界的視圖沒有任何 era rogue 的列；MUD 世界拒絕啟用 rogue；
## MUD 世界送 rogue intent → rogue_off；MUD 的 gate 不擋任何既有 intent。

func before_each() -> void:
	world_name = "w_rg_mud"
	super.before_each()

func _files_under(rel: String) -> Dictionary:
	var out := {}
	var root := ProjectSettings.globalize_path(sm.root_dir.path_join(rel))
	_walk(root, out)
	return out

func _walk(p: String, out: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(p):
		return
	for f in DirAccess.get_files_at(p):
		out[p.path_join(f)] = FileAccess.get_md5(p.path_join(f))
	for d in DirAccess.get_directories_at(p):
		_walk(p.path_join(d), out)

func test_mud_view_has_no_rogue_rows() -> void:
	assert_false(GameData.enabled_eras.has("rogue"))
	for t in GameData.tables:
		if not (GameData.tables[t] is Dictionary):
			continue
		for id in GameData.tables[t]:
			var row: Variant = GameData.tables[t][id]
			if row is Dictionary and t != "eras":
				assert_true(str(row.get("era", "")) != "rogue", "MUD 視圖有 rogue 列：%s.%s" % [t, id])
	assert_false(GameData.tables.get("maps", {}).has("rg_trial"), "沒有試煉場地圖")
	assert_true(GameData.tables.get("rogue_cards", {}).is_empty())
	assert_eq(str(ws.world_info().get("mode", "")), "MUD")
	assert_false(bool(ws.ephemeral))

func test_mud_rejects_rogue_era() -> void:
	var d := WorldServer.decide_new_world_eras("1.0A,rogue", GameData.default_server_options())
	assert_true(str(d.error) != "", "--eras=1.0A,rogue 失敗")
	assert_true(str(d.error).contains("江湖試煉"), "錯誤訊息：%s" % str(d.error))
	var d2 := WorldServer.decide_new_world_eras("1.0A,1.0B,rogue", GameData.default_server_options())
	assert_true(str(d2.error) != "")
	ws.options["pending_eras"] = ["1.0A", "1.0B", "rogue"]
	assert_false(ws.apply_pending_eras(), "pending_eras 含 rogue → 不套用")
	assert_false((ws.world.get("enabled_eras", []) as Array).has("rogue"))
	ws.options["pending_eras"] = []

func test_mud_rogue_intents_off_and_gate_passthrough() -> void:
	if make_char("試煉旁觀") == null:
		return
	assert_eq(reason("rogue_open", {}), "rogue_off")
	assert_eq(reason("rogue_start", { "alloc": {} }), "rogue_off")
	assert_eq(reason("rogue_pick", { "idx": 0 }), "rogue_off")
	assert_eq(reason("rogue_fight"), "rogue_off")
	assert_eq(reason("rogue_abandon", { "confirm": true }), "rogue_off")
	assert_eq(host().rogue.gate(s(), "move"), "", "MUD 的 gate 一律放行")
	assert_false(host().rogue.enabled())
	ok("look")

func test_rogue_run_leaves_mud_files_untouched() -> void:
	if make_char("試煉旁觀") == null:
		return
	var c = ch()
	var attrs0: Dictionary = c.attrs.duplicate()
	var cid := str(c.id)
	host().send_passport(s(), c)
	ws.flush()
	ws.stop()   # MUD 關服時照常存檔；快照取在關服之後
	var before := _files_under("worlds")
	before.merge(_files_under("passports"))
	assert_false(before.is_empty(), "MUD 有存檔")
	# 跑一局試煉（開局 → 放棄），再關掉
	assert_eq(ws.start_rogue(777), OK)
	cs.begin_local_session()
	ws.flush()
	ok("rogue_open", { "seed": 777 })
	var st := lastp("rogue_state")
	ok("rogue_start", { "alloc": { "str": int(st.alloc_points) } })
	ok("rogue_abandon", { "confirm": true })
	ws.advance(5.0)
	ws.stop()
	var after := _files_under("worlds")
	after.merge(_files_under("passports"))
	assert_eq(after, before, "worlds/、passports/ 完全相同、沒有新檔")
	assert_true(FileAccess.file_exists(RogueProfile.path(sm.root_dir)), "只多了 rogue/profile.json")
	# 重開 MUD 世界：沒有 rogue、角色屬性不變
	assert_eq(ws.start(world_name), OK)
	cs.begin_local_session()
	ws.flush()
	assert_false(GameData.enabled_eras.has("rogue"))
	var r := send("char_select", { "char_id": cid })
	assert_true(r.get("ok", false), "選回 MUD 角色：%s" % str(r))
	if ch() != null:
		assert_eq(ch().attrs, attrs0, "MUD 角色屬性不變")
