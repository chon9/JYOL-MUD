class_name MailSystem
extends RefCounted
## 飛鴿傳書（M2_PLAN 4.6.7、4.4.3、4.8、5.4）：寄給任何角色名（離線也收得到），存在主機 world.json 的 mail。
## world.mail = [ { id, to_char, to_name, from_char, from_name, text, sent_s, read } ]（寄出順序＝舊到新）

const CH_MAIL := Protocol.CH_MAIL
const E_MAIL_SENT := Protocol.E_MAIL_SENT
const E_MAIL_ARRIVED := Protocol.E_MAIL_ARRIVED
const E_MAIL_WAITING := Protocol.E_MAIL_WAITING
const E_MAIL_LIST := Protocol.E_MAIL_LIST
const MAIL_MAX_LEN := Protocol.MAIL_MAX_LEN
const NAME_MAX_LEN := 64

# 4.7.1 選項預設
const DEFAULT_INBOX_MAX := 50
const DEFAULT_MIN_INTERVAL_REAL_S := 10
const META_LAST_MAIL := "mail_last_send_ms"   # 舊版記在 Session meta；改記在 _last_send_ms（依身分，跨重連）
## 同一個寄件人在同一個收件匣裡最多幾封未讀信【設計提案】（M2 審查：一個人寄滿 50 封未讀，其他人就都寄不進去）
const MAX_UNREAD_PER_SENDER := 10

var host: GameHost
## 測試用：真實時間的位移（毫秒）
var test_ms_offset := 0
## 寄件人身分 → 上次寄信的真實毫秒（記在 Session 上的話，重連就能繞過 mail_min_interval_real_s）
var _last_send_ms: Dictionary = {}

func _init(p_host: GameHost) -> void:
	host = p_host

func all() -> Array:
	var m: Variant = host.ws.world.get("mail")
	if not (m is Array):
		m = []
		host.ws.world["mail"] = m
	return m

func find(id: String) -> Dictionary:
	for m in all():
		if m is Dictionary and str(m.get("id", "")) == id:
			return m
	return {}

## 寄給某角色的全部信（舊到新）
func inbox(char_id: String) -> Array:
	var out: Array = []
	for m in all():
		if m is Dictionary and str(m.get("to_char", "")) == char_id:
			out.append(m)
	return out

# ---------- intent ----------
## 驗證順序：no_such_recipient → bad_target → mail_too_fast → mailbox_full（同一寄件人未讀太多，或收件匣滿了且全未讀）
func send(s: Session, to_name: String, text: String) -> Dictionary:
	var me = s.character
	if me == null:
		return GameHost.fail("no_character")
	var body := _clean(text, MAIL_MAX_LEN)
	if body.strip_edges().is_empty():
		return GameHost.fail("empty_text")
	var ref := _char_ref(to_name)
	var to_char := str(ref.get("char_id", ""))
	if to_char == "":
		return GameHost.fail("no_such_recipient")
	if to_char == str(me.id):
		return GameHost.fail("bad_target")
	var now_ms := real_ms()
	var min_ms := int(host.options.get("mail_min_interval_real_s", DEFAULT_MIN_INTERVAL_REAL_S)) * 1000
	var rate_key := SocialSystem.rate_key(s)
	if _last_send_ms.has(rate_key) and now_ms - int(_last_send_ms[rate_key]) < min_ms:
		return GameHost.fail("mail_too_fast")
	var cap := maxi(1, int(host.options.get("mail_inbox_max", DEFAULT_INBOX_MAX)))
	var box := inbox(to_char)
	if unread_from(box, str(me.id)) >= mini(MAX_UNREAD_PER_SENDER, cap):
		return GameHost.fail("mailbox_full")
	if box.size() >= cap:
		# 5.4：滿時先刪最舊的已讀信；全是未讀 → mailbox_full
		var removable: Array = []
		for m in box:
			if bool(m.get("read", false)):
				removable.append(m)
		var need := box.size() - cap + 1
		if removable.size() < need:
			return GameHost.fail("mailbox_full")
		for i in need:
			all().erase(removable[i])
	var recipient: Session = host.session_for_char(to_char)
	var real_to_name := _display_name(to_char, to_name, recipient)
	var mail := {
		"id": host.new_id("ml_"), "to_char": to_char, "to_name": real_to_name,
		"from_char": str(me.id), "from_name": str(me.name), "text": body,
		"sent_s": host.now_s(), "read": false,
	}
	all().append(mail)
	_last_send_ms[rate_key] = now_ms
	host.tell(s, CH_MAIL, E_MAIL_SENT, { "to_name": real_to_name })
	if recipient != null:
		host.tell(recipient, CH_MAIL, E_MAIL_ARRIVED, { "from_name": str(me.name), "id": str(mail["id"]) })
		recipient.sheet_dirty = true
	host.ws.save_now()   # 4.6.7：信件不可因當機遺失
	return GameHost.ok({ "id": str(mail["id"]) })

func list(s: Session) -> Dictionary:
	if s.character == null:
		return GameHost.fail("no_character")
	_push_list(s)
	return GameHost.ok()

func read(s: Session, id: String) -> Dictionary:
	var m := _mine(s, id)
	if m.is_empty():
		return GameHost.fail("mail_not_found")
	if not bool(m.get("read", false)):
		m["read"] = true
		host.ws.save_now()   # 和 send 一致（4.6.7）：當機後已讀的信不會又變未讀
	s.sheet_dirty = true
	_push_list(s)
	return GameHost.ok()

func delete(s: Session, id: String) -> Dictionary:
	var m := _mine(s, id)
	if m.is_empty():
		return GameHost.fail("mail_not_found")
	all().erase(m)
	host.ws.save_now()   # 和 send 一致（4.6.7）：當機後刪掉的信不會又回來
	s.sheet_dirty = true
	_push_list(s)
	return GameHost.ok()

## 收件匣裡某寄件人的未讀信數
static func unread_from(box: Array, from_char: String) -> int:
	var n := 0
	for m in box:
		if m is Dictionary and str(m.get("from_char", "")) == from_char and not bool(m.get("read", false)):
			n += 1
	return n

# ---------- 主機接線（4.6.1） ----------
func unread_count(ch) -> int:
	if ch == null:
		return 0
	var n := 0
	for m in inbox(str(ch.id)):
		if not bool(m.get("read", false)):
			n += 1
	return n

func on_enter(s: Session) -> void:
	var n := unread_count(s.character)
	if n > 0:
		host.tell(s, CH_MAIL, E_MAIL_WAITING, { "n": n })

func on_char_deleted(char_id: String) -> void:
	var keep: Array = []
	for m in all():
		if m is Dictionary and str(m.get("to_char", "")) != char_id:
			keep.append(m)
	var list_ref := all()
	list_ref.clear()
	list_ref.append_array(keep)

# ---------- 內部 ----------
## 4.4.3 mail_list：[ { id, from_name, text, sent_clock, read } ]（新到舊）
func entries_for(char_id: String) -> Array:
	var out: Array = []
	var box := inbox(char_id)
	for i in range(box.size() - 1, -1, -1):
		var m: Dictionary = box[i]
		out.append({
			"id": str(m.get("id", "")), "from_name": str(m.get("from_name", "")), "text": str(m.get("text", "")),
			"sent_clock": str(WorldClock.clock(float(m.get("sent_s", 0.0)), host.day_s()).get("text", "")),
			"read": bool(m.get("read", false)),
		})
	return out

func _push_list(s: Session) -> void:
	if s.character == null:
		return
	host.tell(s, CH_MAIL, E_MAIL_LIST, { "mails": entries_for(str(s.character.id)) }, true)

func _mine(s: Session, id: String) -> Dictionary:
	if s.character == null:
		return {}
	var m := find(id)
	if m.is_empty() or str(m.get("to_char", "")) != str(s.character.id):
		return {}
	return m

func _clean(text: String, max_len: int) -> String:
	if host.has_method("clean_text"):
		return str(host.call("clean_text", text, max_len))
	return SocialSystem.clean_text_local(text, max_len)

## world.char_names 查詢：{ identity, char_id } 或 {}
func _char_ref(char_name: String) -> Dictionary:
	var n := char_name.strip_edges()
	if n == "" or n.length() > NAME_MAX_LEN:
		return {}
	if host.has_method("char_ref_by_name"):
		var r: Variant = host.call("char_ref_by_name", n)
		return r if r is Dictionary else {}
	var e: Variant = host.char_store.names().get(CharacterStore.name_key(n))
	return e if e is Dictionary else {}

## 收件人的正式名字：在線用角色名；否則 GameHost.pvp_char_name；都沒有就用寄件者打的字（已清理）
func _display_name(char_id: String, typed: String, online: Session) -> String:
	if online != null and online.character != null:
		return str(online.character.name)
	if host.has_method("pvp_char_name"):
		var n := str(host.call("pvp_char_name", char_id))
		if n != "":
			return n
	return _clean(typed, NAME_MAX_LEN)

func real_ms() -> int:
	return Time.get_ticks_msec() + test_ms_offset
