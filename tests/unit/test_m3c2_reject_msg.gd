extends "res://tests/test_case.gd"
## M3C2_PLAN §6.3、E3（WP-CARRY）：拒絕訊息 —— 三種原因的字串格式、客戶端解析、舊格式相容。

func test_host_wire_format() -> void:
	var ws: Node = tree.root.get_node("WorldServer")
	var fp := BuildInfo.fingerprint12(GameData.content_hash)
	for code in ["protocol_mismatch", "version_mismatch", "content_mismatch"]:
		assert_eq(ws.reject_wire(code), "%s|%s|%d|%s" % [code, BuildInfo.version(), Protocol.VERSION, fp], code)
	# 其他原因照舊只有代碼
	for code in ["banned", "server_full", "bad_identity", "already_connected"]:
		assert_eq(ws.reject_wire(code), code, code)
	assert_eq(BuildInfo.reject_reason("content_mismatch", "sha256:9d24a2e10ccc99"), "content_mismatch|%s|5|9d24a2e10ccc" % BuildInfo.version())

func test_parse() -> void:
	var p := BuildInfo.parse_reject("content_mismatch|0.6.1.0|5|9d24a2e10ccc")
	assert_eq(str(p["code"]), "content_mismatch")
	assert_eq(p["host"], { "version": "0.6.1.0", "protocol": 5, "fp": "9d24a2e10ccc" })
	var old := BuildInfo.parse_reject("content_mismatch")
	assert_eq(str(old["code"]), "content_mismatch")
	assert_eq(old["host"], {})

func test_client_text_shows_both_sides() -> void:
	var mine := BuildInfo.line(GameData.content_hash)
	var t := UiSocial.reject_text("content_mismatch|0.6.0.0|5|1a2b3c4d5e6f")
	assert_true(t.begins_with(UiSocial.REJECT_TEXT["content_mismatch"]), t)
	assert_true(t.contains("主機：v0.6.0.0　協定 5　資料 1a2b3c4d5e6f"), t)
	assert_true(t.contains("你：" + mine), t)
	var t2 := UiSocial.reject_text("protocol_mismatch|0.7.0.1|6|abcdefabcdef")
	assert_true(t2.begins_with(UiSocial.REJECT_TEXT["protocol_mismatch"]), t2)
	assert_true(t2.contains("主機：v0.7.0.1　協定 6　資料 abcdefabcdef／你："), t2)
	# 舊主機（沒有 |）：原文字＋自己的值
	var t3 := UiSocial.reject_text("version_mismatch")
	assert_eq(t3, UiSocial.REJECT_TEXT["version_mismatch"] + "\n你：" + mine)
	# 其他原因不加
	assert_eq(UiSocial.reject_text("banned"), "你被主機禁止進入這個江湖。")
	assert_eq(UiSocial.reject_text("weird"), "主機拒絕連線：weird")

func test_handshake_reject_delivers_build_info() -> void:
	var ws: Node = tree.root.get_node("WorldServer")
	var cs: Node = tree.root.get_node("ClientState")
	var smn: Node = tree.root.get_node("SaveManager")
	tree.root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var dir := temp_dir("rejmsg")
	var old_root: String = smn.root_dir
	smn.root_dir = dir
	assert_eq(ws.start("w_m3c2_rej"), OK)
	var got := {}
	cs.capture_remote = func(peer: int, what: String, payload: Variant) -> void:
		if what == "rejected":
			got[peer] = payload
	ws.on_peer_connected(77)
	var why: String = ws.handle_hello(77, { "protocol": Protocol.VERSION, "game_version": Protocol.GAME_VERSION,
		"content_hash": "sha256:000000000000ffff", "identity": "local_" + "ab".repeat(16), "display_name": "x" })
	assert_eq(why, "content_mismatch", "code returned to caller")
	assert_eq(str(got.get(77, "")), "content_mismatch|%s|%d|%s" % [BuildInfo.version(), Protocol.VERSION,
		BuildInfo.fingerprint12(GameData.content_hash)], "wire string")
	var text := UiSocial.reject_text(str(got.get(77, "")))
	assert_true(text.contains("主機：v" + BuildInfo.version()), text)
	ws.stop()
	cs.capture_remote = Callable()
	cs.reset()
	smn.root_dir = old_root
	remove_dir_recursive(dir)
