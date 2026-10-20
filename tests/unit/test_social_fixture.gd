extends "res://tests/unit/test_world_fixture.gd"
## WP-SOCIAL 整合測試的共用基底（本檔沒有 test_ 方法）。
## 多玩家輔助用 soc_ 前綴，避免與 WP-HOST 之後加進 test_world_fixture 的 add_player／send_as 等同名衝突（4.6.10）。
## 遠端玩家是直接放進 WorldServer.sessions 的假 session（peer 100 起）；他們的事件在 flush 之前從 outbox 取走，
## ClientState.capture_remote 存在時（WP-HOST Day-0）也一併接住，所以不會真的發 RPC。
## Day-0 的 Protocol 尚未合併時（沒有 mail_* intent、只有千里傳音頻道），intent 直接交給已註冊的處理器（跳過 validate_args）。

var social                      # 實際處理 chat 的 SocialSystem
var mail                        # 實際處理 mail_* 的 MailSystem
var host_wired := false         # GameHost 自己載入了 social／mail（4.6.1）
var _remote := {}               # peer -> Session
var _ident := {}                # peer -> identity（重開世界後重新加入用）
var _cap := {}                  # peer -> Array（收到的事件）
var _rseq := {}                 # peer -> 最後的 intent 序號
var _next_peer := 100

func before_each() -> void:
	super.before_each()
	_remote.clear()
	_ident.clear()
	_cap.clear()
	_rseq.clear()
	_next_peer = 100
	_wire()

func after_each() -> void:
	_drop_all_remote()
	if "capture_remote" in cs:
		cs.capture_remote = Callable()
	super.after_each()

func _wire() -> void:
	var h = host()
	if h == null:
		return
	host_wired = h.get("social") != null and h.get("mail") != null
	if host_wired:
		social = h.social
		mail = h.mail
	else:
		var d: Dictionary = IntentsSocial.install(h)
		social = d["social"]
		mail = d["mail"]
	ws.options["chat_min_interval_ms"] = 0
	ws.options["mail_min_interval_real_s"] = 0
	if "capture_remote" in cs:
		cs.capture_remote = Callable(self, "_on_capture")

func _on_capture(peer_id: int, what: String, payload: Variant) -> void:
	if what == "events" and payload is Array:
		_cap.get_or_add(peer_id, []).append_array(payload)

static func day0() -> bool:
	return Protocol.is_known("mail_send") and Protocol.CHAT_CHANNELS.size() > 1

## 遠端玩家的事件從 outbox 取走，再 flush（本機 peer 1 經 ClientState 收到）
func pump() -> void:
	for peer_id in _remote:
		var box: Array = ws.pending_events(peer_id)
		if not box.is_empty():
			_cap.get_or_add(peer_id, []).append_array(box.duplicate())
			ws._outbox.erase(peer_id)
	ws.flush()

# ---------- 遠端玩家 ----------
func _new_remote_session(identity: String, disp: String) -> int:
	var peer := _next_peer
	_next_peer += 1
	var sess := Session.new(peer, identity, disp)
	sess.rate_limiter = TokenBucket.new(1000000.0, 1000000.0)
	ws.sessions[peer] = sess
	_remote[peer] = sess
	_ident[peer] = identity
	_cap[peer] = []
	return peer

## 建一個在線的遠端角色（沒有 char_name 就只連線不選角）；回傳 peer
func soc_add(char_name: String, room := "", sect := "") -> int:
	var peer := _new_remote_session("local_%s" % ("%08x" % (0x5000 + _next_peer)).repeat(4), char_name if char_name != "" else "旁觀者")
	if char_name == "":
		pump()
		return peer
	var h = host()
	var p := { "id": h.new_id("ch_"), "identity": _ident[peer], "name": char_name, "gender": "M",
		"birth_month": 3, "birth_city": "xixia", "alloc": { "wit": 5 } }
	var c = CharacterFactory.create(p, CharacterFactory.roll(ws.rng), GameData.tables, ws.options, ws.rng, ws.world_time())
	assert_true(c != null, "create remote char " + char_name)
	h.save_char(c)
	h.char_store.register_name(c)
	h.enter_character(_remote[peer], c)
	c.sect = sect
	if room != "":
		h.regions.teleport(_remote[peer], room)
	pump()
	return peer

## 讓遠端玩家離線（存檔、離開房間、移除 session）
func soc_drop(peer: int) -> void:
	var sess: Session = _remote.get(peer)
	if sess == null:
		return
	host().on_session_removed(sess)
	ws.sessions.erase(peer)
	ws._outbox.erase(peer)
	_remote.erase(peer)

func _drop_all_remote() -> void:
	for peer in _remote.keys():
		soc_drop(peer)

## 以同一 identity 重新連線並選角（重開世界後）；回傳新 peer
func soc_rejoin(old_peer: int, char_id: String) -> int:
	var peer := _new_remote_session(str(_ident[old_peer]), "重連")
	var r := soc_send(peer, "char_select", { "char_id": char_id })
	assert_true(r.get("ok", false), "rejoin char_select: %s" % str(r))
	if evs_of(peer, Protocol.E_MAIL_WAITING).is_empty() and mail.unread_count(rch(peer)) > 0:
		# GameHost 尚未在選角後呼叫 mail.on_enter（4.6.1 由 WP-HOST 接線）：這裡補上，只驗本 WP 的行為
		print("[test_social] note: GameHost did not call mail.on_enter after char_select; calling it directly")
		mail.on_enter(_remote[peer])
		pump()
	return peer

func rs(peer: int) -> Session:
	return ws.sessions.get(peer)

func rch(peer: int):
	var sess := rs(peer)
	return sess.character if sess != null else null

# ---------- intent ----------
func soc_send(peer: int, kind: String, args: Dictionary = {}) -> Dictionary:
	var sess: Session = ws.sessions.get(peer)
	if sess == null:
		return { "ok": false, "reason": "drop:no_session" }
	var r: Dictionary
	# 遠端 peer 只在 capture_remote 存在時走 handle_intent（否則結果與角色表會真的發 RPC 給不存在的 peer）
	var can_route: bool = peer == 1 or "capture_remote" in cs
	var known: bool = day0() or (Protocol.is_known(kind) and Protocol.validate_args(kind, args) == "")
	if can_route and known:
		seq += 1
		_rseq[peer] = seq
		r = ws.handle_intent(peer, seq, kind, args)
	elif peer == 1 and ws._handlers.has(kind):
		r = ws._handlers[kind].call(sess, args)   # Day-0 的 Protocol 尚未合併：跳過 validate_args
	else:
		r = _direct(sess, kind, args)
	pump()
	return r

## 遠端 peer 在 capture_remote 之前：直接呼叫系統（GameHost._run_intent 會對遠端 push_sheet，發出 RPC）
func _direct(sess: Session, kind: String, args: Dictionary) -> Dictionary:
	var needs_char := kind.begins_with("mail_")
	if needs_char and sess.character == null:
		return GameHost.fail("no_character")
	var r: Dictionary
	match kind:
		"chat":
			r = social.chat(sess, args)
		"mail_send":
			r = mail.send(sess, str(args.get("to", "")), str(args.get("text", "")))
		"mail_list":
			r = mail.list(sess)
		"mail_read":
			r = mail.read(sess, str(args.get("id", "")))
		"mail_delete":
			r = mail.delete(sess, str(args.get("id", "")))
		"char_select":
			r = IntentsChar.char_select(host(), sess, args)
		_:
			r = { "ok": false, "reason": "unknown_intent" }
	sess.sheet_dirty = false
	sess.view_dirty = false
	return r

func soc_reason(peer: int, kind: String, args: Dictionary = {}) -> String:
	return str(soc_send(peer, kind, args).get("reason", ""))

func soc_ok(peer: int, kind: String, args: Dictionary = {}) -> Dictionary:
	var r := soc_send(peer, kind, args)
	assert_true(r.get("ok", false), "peer %d %s %s -> %s" % [peer, kind, str(args), str(r.get("reason", ""))])
	return r

## 本機（peer 1）送 intent
func me_send(kind: String, args: Dictionary = {}) -> Dictionary:
	return soc_send(1, kind, args)

# ---------- 事件 ----------
func evs_of(peer: int, key: String) -> Array:
	var src: Array = events if peer == 1 else _cap.get(peer, [])
	var out: Array = []
	for e in src:
		if e.get("key", "") == key:
			out.append(e)
	return out

func clear_all_events() -> void:
	events.clear()
	for peer in _cap:
		_cap[peer] = []

## 重開世界（同一 world_id），遠端玩家全部消失；回傳後重新接好 social／mail
func soc_restart() -> void:
	_drop_all_remote()
	ws.stop()
	cs.reset()
	assert_eq(ws.start(world_name), OK, "restart")
	cs.begin_local_session()
	if ws.sessions.has(1):
		ws.sessions[1].rate_limiter = TokenBucket.new(1000000.0, 1000000.0)
	ws.flush()
	_cap.clear()
	_wire()
