extends "res://tests/test_case.gd"
## Protocol、TokenBucket、EventLogBuffer、CliArgs、TextRenderer

func test_protocol_validate_ok() -> void:
	assert_eq(Protocol.validate_args("chat", { "text": "你好" }), "")
	assert_eq(Protocol.validate_args("chat", { "text": "你好", "ch": "CHAT_WORLD" }), "")
	assert_eq(Protocol.validate_args("ping", {}), "")
	assert_eq(Protocol.validate_args("ping", { "nonce": 3 }), "")

func test_protocol_rejects_objects() -> void:
	var n := RefCounted.new()
	assert_eq(Protocol.validate_args("chat", { "text": n }), "bad_type:text")

func test_token_bucket_refills() -> void:
	var b := TokenBucket.new(3, 1)
	assert_true(b.allow(0.0))
	assert_true(b.allow(0.0))
	assert_true(b.allow(0.0))
	assert_false(b.allow(0.0), "empty")
	assert_false(b.allow(0.5), "half token")
	assert_true(b.allow(1.0), "refilled one")
	assert_false(b.allow(1.0))
	assert_true(b.allow(100.0))
	assert_true(b.tokens <= 3.0, "capped")

func test_event_log_ring_buffer() -> void:
	var buf := EventLogBuffer.new(3)
	for i in 5:
		buf.push(i)
	assert_eq(buf.size(), 3)
	assert_eq(buf.to_array(), [2, 3, 4])
	assert_eq(buf.last(2), [3, 4])

func test_cli_args_parse_and_aliases() -> void:
	var a := CliArgs.parse(PackedStringArray(["--no-steam", "--join-enet=127.0.0.1:30000", "--port=1", "x", "--host-enet"]))
	assert_eq(a["no-steam"], true)
	assert_eq(a["enet-join"], "127.0.0.1:30000")
	assert_eq(a["port"], "1")
	assert_eq(a["enet-host"], true)
	assert_eq(CliArgs.split_host_port("10.0.0.2:4000", 1), ["10.0.0.2", 4000])
	assert_eq(CliArgs.split_host_port("10.0.0.2", 24565), ["10.0.0.2", 24565])

func test_text_renderer_self_and_other() -> void:
	var tpl := { "chat": { "self": "你：{text}", "other": "{from}：{text}" } }
	var e := { "ch": "CHAT_WORLD", "key": "chat", "p": { "from": "阿朱", "from_peer": 2, "text": "[b]hi" } }
	assert_eq(TextRenderer.render_plain(e, 2, tpl), "你：[b]hi")
	assert_eq(TextRenderer.render_plain(e, 1, tpl), "阿朱：[b]hi")
	assert_true(TextRenderer.render(e, 1, tpl).find("[lb]b]") != -1, "bbcode escaped")
	assert_true(TextRenderer.render_plain({ "key": "nope", "p": {} }, 1, tpl).begins_with("nope"))
