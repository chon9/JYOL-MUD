extends Node
## 無介面 bot（TECH_ARCH 15.3）：等名單到齊 → ping → 千里傳音 → 斷言收到 pong 與所有 bot 的聊天。
## 參數：--bot-expect=N（等到在線 N 人才開始，預設 2）、--bot-chats=N（要看到幾個不同 bot 的聊天，預設 1）。
## 結束碼：0 成功；1 逾時（由 --quit-after 觸發）；2 intent 被拒；3 握手被拒。

const CHAT_PREFIX := "bot:"

var _expect := 2
var _need_chats := 1
var _sent := false
var _got_pong := false
var _seen_from: Dictionary = {}
var _my_text := ""
var _done := false

func _ready() -> void:
	var args := CliArgs.current()
	_expect = int(str(args.get("bot-expect", "2")))
	_need_chats = int(str(args.get("bot-chats", "1")))
	SceneRouter.exit_code = 1
	ClientState.events_received.connect(_on_events)
	ClientState.rejected.connect(func(r: String): _finish(3, "rejected: " + r))
	ClientState.intent_result.connect(_on_result)
	ClientState.roster_changed.connect(func(players: Array): _maybe_start(players.size()))
	NetworkManager.session_ended.connect(func(r: String):
		if not _done and r != "left":
			_finish(4, "session ended: " + r))
	print("[Bot] ready, expect=%d chats=%d" % [_expect, _need_chats])
	_maybe_start(ClientState.roster.size())

func _maybe_start(count: int) -> void:
	if _sent or not ClientState.in_world or count < _expect:
		return
	_sent = true
	_my_text = "%s%s#%d" % [CHAT_PREFIX, ClientState.display_name, ClientState.my_peer_id]
	NetworkManager.send_intent(Protocol.I_PING, { "nonce": Time.get_ticks_msec() })
	NetworkManager.send_intent(Protocol.I_CHAT, { "text": _my_text })
	print("[Bot] sent ping + chat '%s'" % _my_text)

func _on_result(seq: int, ok: bool, reason: String) -> void:
	if not ok:
		_finish(2, "intent %d rejected: %s" % [seq, reason])

func _on_events(batch: Array) -> void:
	for e in batch:
		var p: Dictionary = e.get("p", {})
		match e.get("key", ""):
			Protocol.E_PONG:
				_got_pong = true
				print("[Bot] pong rtt=%sms" % str(p.get("rtt_ms", "?")))
			Protocol.E_CHAT:
				var text: String = p.get("text", "")
				if text.begins_with(CHAT_PREFIX):
					_seen_from[text] = true
					print("[Bot] chat from %s: %s" % [p.get("from", "?"), text])
	if _sent and _got_pong and _seen_from.has(_my_text) and _seen_from.size() >= _need_chats:
		_finish(0, "BOT_OK chats=%d" % _seen_from.size())

func _finish(code: int, msg: String) -> void:
	if _done:
		return
	_done = true
	print("[Bot] %s (exit %d)" % [msg, code])
	SceneRouter.exit_code = code
	# 稍等一下讓最後的 RPC 送出
	get_tree().create_timer(0.3, true, false, true).timeout.connect(func(): SceneRouter.quit(code))
