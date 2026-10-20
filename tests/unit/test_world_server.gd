extends "res://tests/test_case.gd"
## WorldServer：intent 驗證、序號、速率限制、無 session 丟棄、握手驗證、事件佇列（TECH_ARCH 6.2、6.3、6.4）
## 使用真正的 Autoload（--script 模式下 Autoload 會初始化，17 #18 已驗證）。離線 peer：unique id 1。

var ws: Node
var cs: Node
var sm: Node
var dir := ""
var _old_root := ""
var _results: Array = []
var seq := 100

func before_each() -> void:
	ws = tree.root.get_node("WorldServer")
	cs = tree.root.get_node("ClientState")
	sm = tree.root.get_node("SaveManager")
	tree.root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	dir = temp_dir("ws")
	_old_root = sm.root_dir
	sm.root_dir = dir
	_results.clear()
	assert_eq(ws.start("unit_world"), OK, "start")
	cs.begin_local_session()
	ws.flush()
	cs.intent_result.connect(_on_result)

func after_each() -> void:
	cs.intent_result.disconnect(_on_result)
	ws.stop()
	cs.reset()
	sm.root_dir = _old_root
	remove_dir_recursive(dir)

func _on_result(s: int, ok: bool, reason: String) -> void:
	_results.append([s, ok, reason])

func _send(kind: String, args: Dictionary) -> Dictionary:
	seq += 1
	return ws.handle_intent(1, seq, kind, args)

func _reason(kind: String, args: Dictionary) -> String:
	return str(_send(kind, args).get("reason", ""))

func test_local_session_registered() -> void:
	assert_has(ws.sessions, 1)
	assert_true(cs.in_world, "welcomed locally")
	assert_eq(cs.my_peer_id, 1)

func test_valid_chat_is_broadcast() -> void:
	var r: Dictionary = _send("chat", { "text": "  各位好  " })
	assert_true(r.get("ok", false), "chat ok: %s" % str(r))
	var evs: Array = ws.pending_events(1)
	assert_eq(evs.size(), 1)
	if evs.size() == 1:
		assert_eq(evs[0]["key"], "chat")
		assert_eq(evs[0]["ch"], "CHAT_WORLD")
		assert_eq(evs[0]["p"]["text"], "各位好", "trimmed")
		assert_type(evs[0]["seq"], TYPE_INT)
	assert_eq(_results.size(), 1)
	assert_eq(_results[0], [seq, true, ""])

func test_flush_delivers_to_local_client_state() -> void:
	# 環狀緩衝區（2000 則）可能已被前面的測試塞滿：先清空，大小才看得出多了一則
	cs.event_log.clear()
	_send("chat", { "text": "hi" })
	ws.flush()
	assert_eq(cs.event_log.size(), 1)
	assert_eq(str(cs.event_log.last(1)[0].get("p", {}).get("text", "")), "hi")
	assert_eq(ws.pending_events(1).size(), 0)

func test_ping_queues_pong_for_sender() -> void:
	assert_true(_send("ping", { "nonce": 42 }).get("ok", false))
	var evs: Array = ws.pending_events(1)
	assert_eq(evs.size(), 1)
	if evs.size() == 1:
		assert_eq(evs[0]["key"], "pong")
		assert_eq(evs[0]["p"]["nonce"], 42)

func test_invalid_args_are_rejected() -> void:
	assert_eq(_reason("chat", {}), "missing_arg:text")
	assert_eq(_reason("chat", { "text": "   " }), "empty_text")
	assert_eq(_reason("chat", { "text": "x".repeat(Protocol.CHAT_MAX_LEN + 1) }), "text_too_long")
	assert_eq(_reason("chat", { "text": 5 }), "bad_type:text")
	assert_eq(_reason("chat", { "text": "a", "evil": 1 }), "unexpected_arg")
	assert_eq(_reason("chat", { "text": "a", "ch": "CHAT_NOPE" }), "bad_channel")
	assert_eq(_reason("ping", { "nonce": "x" }), "bad_type:nonce")
	assert_eq(_reason("teleport", {}), "unknown_intent")
	assert_eq(ws.pending_events(1).size(), 0, "no events from rejected intents")
	assert_eq(_results.size(), 8, "every validated intent gets a result")
	for r in _results:
		assert_false(r[1])

func test_stale_seq_is_dropped() -> void:
	assert_true(ws.handle_intent(1, 500, "ping", {}).get("ok", false))
	assert_eq(ws.handle_intent(1, 500, "ping", {})["reason"], "drop:stale_seq")
	assert_eq(ws.handle_intent(1, 499, "ping", {})["reason"], "drop:stale_seq")
	assert_eq(_results.size(), 1, "dropped intents get no result")

func test_unknown_sender_is_dropped() -> void:
	assert_eq(ws.handle_intent(77, 1, "chat", { "text": "hi" })["reason"], "drop:no_session")
	assert_eq(_results.size(), 0)

func test_rate_limit() -> void:
	var ok := 0
	var limited := 0
	for i in 40:
		var r: Dictionary = _send("ping", {})
		if r.get("ok", false):
			ok += 1
		elif r.get("reason", "") == "drop:rate_limited":
			limited += 1
	assert_true(ok >= 20 and ok <= 22, "ok=%d" % ok)
	assert_true(limited >= 18, "limited=%d" % limited)

const GUEST_ID := "local_0123456789abcdef0123456789abcdef"

func _good_hello() -> Dictionary:
	return {
		"protocol": Protocol.VERSION, "game_version": Protocol.GAME_VERSION,
		"content_hash": GameData.content_hash, "identity": GUEST_ID, "display_name": "客人",
	}

func test_hello_validation() -> void:
	var good := _good_hello()
	assert_eq(ws.validate_hello(5, good), "")
	var h := good.duplicate()
	h["protocol"] = Protocol.VERSION + 1
	assert_eq(ws.validate_hello(5, h), "protocol_mismatch")
	h = good.duplicate()
	h["game_version"] = "9.9.9"
	assert_eq(ws.validate_hello(5, h), "version_mismatch")
	h = good.duplicate()
	h["content_hash"] = "sha256:bad"
	assert_eq(ws.validate_hello(5, h), "content_mismatch")
	h = good.duplicate()
	for bad in ["admin", "local_abc", "steam_76561198000000000", "local_" + "a".repeat(200),
			"LOCAL_0123456789abcdef0123456789abcdef", GUEST_ID + "x"]:
		h["identity"] = bad
		assert_eq(ws.validate_hello(5, h), "bad_identity", bad.left(40))
	h = good.duplicate()
	h["identity"] = cs.identity
	assert_eq(ws.validate_hello(5, h), "already_connected")
	assert_eq(ws.validate_hello(1, good), "already_joined")
	ws.world["known_identities"][GUEST_ID] = { "banned": true }
	assert_eq(ws.validate_hello(5, good), "banned")
	ws.world["known_identities"].erase(GUEST_ID)
	ws.options["max_players"] = 1
	assert_eq(ws.validate_hello(5, good), "server_full")

func test_world_saved_on_stop() -> void:
	ws.stop()
	assert_true(sm.world_exists("unit_world"), "world.json written")
	var r: Dictionary = sm.load_world("unit_world")
	assert_eq(r["data"]["enabled_eras"], ["1.0A", "1.0B"], "新世界預設 1.0A＋1.0B（M3B_PLAN O1）")
	assert_eq(ws.start("unit_world"), OK, "restart loads existing world")
	cs.begin_local_session()

func test_steam_identity_format() -> void:
	assert_true(ws.is_valid_identity("steam_76561198000000000", true))
	assert_false(ws.is_valid_identity("steam_0", true), "failed SteamID lookup")
	assert_false(ws.is_valid_identity("", true))
	assert_false(ws.is_valid_identity(GUEST_ID, true), "local id on Steam host")

func test_hello_only_from_pending_peer() -> void:
	assert_eq(ws.handle_hello(9, _good_hello()), "drop:not_pending", "never connected")
	assert_eq(ws.handle_hello(1, _good_hello()), "drop:not_pending", "already joined: ignored, no disconnect")
	assert_has(ws.sessions, 1)
	ws.on_peer_connected(9)
	var bad := _good_hello()
	bad["protocol"] = -1
	assert_eq(ws.handle_hello(9, bad), "protocol_mismatch")
	assert_eq(ws.handle_hello(9, _good_hello()), "drop:not_pending", "retry after reject is dropped")
	assert_not_has(ws.sessions, 9)

func test_roster_delivered_locally() -> void:
	assert_eq(cs.roster.size(), 1)
	if cs.roster.size() == 1:
		assert_eq(int(cs.roster[0]["peer"]), 1)

func test_unreadable_world_is_not_replaced() -> void:
	ws.stop()
	var path := ProjectSettings.globalize_path(sm.world_path("unit_world"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ broken")
	f.close()
	var b := FileAccess.open(path + ".bak1", FileAccess.WRITE)
	b.store_string(JSON.stringify({ "schema_version": 999 }))
	b.close()
	var warnings: Array = []
	var cb := func(t: String): warnings.append(t)
	ws.warning.connect(cb)
	assert_eq(ws.start("unit_world"), ERR_FILE_CORRUPT)
	ws.warning.disconnect(cb)
	assert_false(ws.running)
	assert_eq(FileAccess.get_file_as_string(path), "{ broken", "original kept")
	assert_false(FileAccess.file_exists(path + ".bak2"), "no rotation happened")
	assert_eq(warnings.size(), 1)
	assert_true(ws.last_error != "")

func test_backup_load_is_reported() -> void:
	ws.stop()   # world.json 寫入；再 stop 一次前先做出 bak1
	assert_eq(ws.start("unit_world"), OK)
	ws.stop()
	var path := ProjectSettings.globalize_path(sm.world_path("unit_world"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	assert_eq(ws.start("unit_world"), OK)
	assert_true("bak1" in ws.last_warning, "warning names the backup: " + ws.last_warning)

# ---------- M1 擴充（M1_PLAN 3.5.1） ----------
func test_time_scale_is_clamped() -> void:
	var old: float = ws.time_scale
	ws.set_time_scale(1000.0)
	assert_eq(ws.time_scale, 100.0)
	ws.set_time_scale(0.01)
	assert_eq(ws.time_scale, 0.1)
	ws.set_time_scale(0.0)
	assert_eq(ws.time_scale, 1.0, "invalid → 1")
	ws.set_time_scale(50.0)
	var t0: float = ws.world_time()
	ws._process(0.1)
	assert_true(absf(ws.world_time() - t0 - 5.0) < 0.001, "delta × time_scale")
	ws.time_scale = old

func test_register_intent_and_events() -> void:
	ws.register_intent("ping", func(s: Session, args: Dictionary) -> Dictionary:
		ws.queue_event(s.peer_id, Protocol.CH_SYSTEM, "custom", { "a": 1 }, true)
		return { "ok": true, "reason": "" })
	assert_true(_send("ping", {}).get("ok", false))
	var evs: Array = ws.pending_events(1)
	assert_eq(evs.size(), 1)
	if evs.size() == 1:
		assert_eq(evs[0]["key"], "custom")
		assert_eq(evs[0].get("ui", false), true, "ui flag at top level")
		assert_type(evs[0]["seq"], TYPE_INT)
		assert_type(evs[0]["t"], TYPE_FLOAT)
	ws.broadcast_event(Protocol.CH_SYSTEM, "b", {})
	assert_false(ws.pending_events(1)[-1].has("ui"), "no ui flag by default")

func test_forward_event_adds_seq_and_time() -> void:
	ws.forward_event(1, { "ch": "BATTLE", "key": "battle_move", "p": { "uid": 1 }, "bid": 3 })
	var e: Dictionary = ws.pending_events(1)[-1]
	assert_eq(e["bid"], 3)
	assert_true(e.has("seq") and e.has("t"))
	ws.forward_event(99, { "ch": "BATTLE", "key": "x", "p": {} })
	assert_eq(ws.pending_events(99).size(), 0, "unknown peer ignored")

func test_game_host_created_with_handlers() -> void:
	assert_true(ws.game != null, "GameHost: " + ws.game_error)
	if ws.game == null:
		return
	assert_true(ws.has_intent_handler("char_create"))
	assert_true(ws.has_intent_handler("battle_cmd"))
	assert_eq(_reason("look", {}), "no_character")
	ws.stop()
	assert_eq(ws.game, null, "stop clears game")
	assert_false(ws.has_intent_handler("char_create"), "handlers reset on stop")
	assert_eq(ws.start("unit_world"), OK)
	cs.begin_local_session()
