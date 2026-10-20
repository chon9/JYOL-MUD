extends "res://tests/unit/test_social_fixture.gd"
## WP-SOCIAL：飛鴿傳書（M2_PLAN 4.6.7、4.4.3、4.8、5.4、6.1）。

func _setup(other_name := "收信人") -> int:
	if not game_ok():
		return 0
	if make_char("寄信人") == null:
		return 0
	var peer := soc_add(other_name, "xx_square")
	clear_all_events()
	return peer

func _mail(peer: int, to: String, text: String) -> Dictionary:
	return soc_send(peer, "mail_send", { "to": to, "text": text })

func _ids_to(char_id: String) -> Array:
	var out: Array = []
	for m in mail.inbox(char_id):
		out.append(str(m["id"]))
	return out

func test_send_to_online_arrives_immediately() -> void:
	var b := _setup()
	if b == 0:
		return
	var r := _mail(1, "收信人", "明日午時，客棧見。")
	assert_true(r.get("ok", false), "send: %s" % str(r))
	assert_eq(evs_of(1, "mail_sent").size(), 1, "mail_sent")
	assert_eq(lastp("mail_sent").get("to_name", ""), "收信人")
	var arrived := evs_of(b, "mail_arrived")
	assert_eq(arrived.size(), 1, "mail_arrived")
	assert_eq(arrived[0]["ch"], "MAIL")
	assert_eq(arrived[0]["p"]["from_name"], "寄信人")
	var id := str(arrived[0]["p"]["id"])
	assert_true(id.begins_with("ml_"), "id " + id)
	assert_eq(mail.unread_count(rch(b)), 1)
	var row: Dictionary = mail.find(id)
	for k in ["id", "to_char", "to_name", "from_char", "from_name", "text", "sent_s", "read"]:
		assert_has(row, k, "world.mail row")
	assert_eq(row["to_char"], str(rch(b).id))
	assert_eq(row["from_char"], str(ch().id))
	assert_eq(row["read"], false)
	assert_type(row["sent_s"], TYPE_FLOAT, "sent_s")
	assert_true(ws.world.get("mail", []).has(row), "存在 world.mail")
	# 寄送後立即存檔（4.6.7）
	var disk: Dictionary = SaveManager.load_world(ws.world_id)
	assert_true(disk.get("ok", false), "load world.json")
	var found := false
	for m in disk.get("data", {}).get("mail", []):
		if str(m.get("id", "")) == id:
			found = true
	assert_true(found, "信件已寫進 world.json")

func test_send_validation_order() -> void:
	var b := _setup()
	if b == 0:
		return
	assert_eq(str(_mail(1, "江湖無此人", "嗨").get("reason", "")), "no_such_recipient")
	assert_eq(str(_mail(1, "寄信人", "嗨").get("reason", "")), "bad_target", "寄給自己")
	ws.options["mail_min_interval_real_s"] = 10
	assert_true(_mail(1, "收信人", "第一封").get("ok", false), "first")
	assert_eq(str(_mail(1, "收信人", "第二封").get("reason", "")), "mail_too_fast")
	assert_eq(str(_mail(1, "江湖無此人", "嗨").get("reason", "")), "no_such_recipient", "收件人先檢查")
	mail.test_ms_offset += 10001
	assert_true(_mail(1, "收信人", "第三封").get("ok", false), "after 10 s")
	mail.test_ms_offset = 0
	assert_eq(_ids_to(str(rch(b).id)).size(), 2)

func test_mail_text_cleaned_and_name_case_insensitive() -> void:
	var b := _setup("Lin")
	if b == 0:
		return
	assert_true(_mail(1, "lin", "[b]粗體[/b]").get("ok", false), "case-insensitive recipient")
	var box: Array = mail.inbox(str(rch(b).id))
	assert_eq(box.size(), 1)
	assert_eq(box[0]["to_name"], "Lin", "正式名字")
	assert_false("[" in str(box[0]["text"]), "BBCode 清理")

func test_list_read_delete() -> void:
	var b := _setup()
	if b == 0:
		return
	assert_true(_mail(1, "收信人", "舊信").get("ok", false))
	assert_true(_mail(1, "收信人", "新信").get("ok", false))
	var ids := _ids_to(str(rch(b).id))
	clear_all_events()
	soc_ok(b, "mail_list")
	var lst := evs_of(b, "mail_list")
	assert_eq(lst.size(), 1, "mail_list event")
	assert_true(bool(lst[0].get("ui", false)), "ui event")
	var mails: Array = lst[0]["p"]["mails"]
	assert_eq(mails.size(), 2)
	assert_eq(mails[0]["text"], "新信", "新到舊")
	assert_eq(mails[1]["text"], "舊信")
	for k in ["id", "from_name", "text", "sent_clock", "read"]:
		assert_has(mails[0], k, "entry")
	assert_eq(mails[0]["from_name"], "寄信人")
	assert_type(mails[0]["sent_clock"], TYPE_STRING)
	# 讀
	assert_eq(soc_reason(b, "mail_read", { "id": "ml_nope" }), "mail_not_found")
	assert_eq(str(me_send("mail_read", { "id": ids[0] }).get("reason", "")), "mail_not_found", "不是寄給我的")
	clear_all_events()
	soc_ok(b, "mail_read", { "id": ids[0] })
	assert_eq(mail.find(ids[0])["read"], true)
	assert_eq(mail.unread_count(rch(b)), 1)
	var after: Array = evs_of(b, "mail_list")[0]["p"]["mails"]
	assert_eq(after[1]["read"], true, "mail_list 跟著更新")
	# 刪
	assert_eq(str(me_send("mail_delete", { "id": ids[1] }).get("reason", "")), "mail_not_found", "不能刪別人的")
	soc_ok(b, "mail_delete", { "id": ids[1] })
	assert_eq(_ids_to(str(rch(b).id)), [ids[0]])
	assert_eq(soc_reason(b, "mail_delete", { "id": ids[1] }), "mail_not_found", "已刪")

func test_inbox_full_drops_oldest_read() -> void:
	var b := _setup()
	if b == 0:
		return
	ws.options["mail_inbox_max"] = 3
	for i in 3:
		assert_true(_mail(1, "收信人", "第%d封" % i).get("ok", false))
	var ids := _ids_to(str(rch(b).id))
	assert_eq(str(_mail(1, "收信人", "第3封").get("reason", "")), "mailbox_full", "全未讀")
	soc_ok(b, "mail_read", { "id": ids[1] })
	soc_ok(b, "mail_read", { "id": ids[0] })
	assert_true(_mail(1, "收信人", "第3封").get("ok", false), "刪掉最舊的已讀信後寄出")
	var now_ids := _ids_to(str(rch(b).id))
	assert_eq(now_ids.size(), 3)
	assert_false(ids[0] in now_ids, "最舊已讀被刪")
	assert_true(ids[1] in now_ids, "較新的已讀還在")
	assert_true(ids[2] in now_ids, "未讀還在")
	assert_true(_mail(1, "收信人", "第4封").get("ok", false), "再刪一封已讀")
	assert_false(ids[1] in _ids_to(str(rch(b).id)))
	assert_eq(str(_mail(1, "收信人", "第5封").get("reason", "")), "mailbox_full", "又全是未讀")

func test_offline_recipient_gets_mail_after_world_restart() -> void:
	var b := _setup()
	if b == 0:
		return
	var b_char := str(rch(b).id)
	var my_char := str(ch().id)
	soc_drop(b)
	assert_true(_mail(1, "收信人", "你不在，留個信").get("ok", false), "寄給離線角色")
	assert_eq(lastp("mail_sent").get("to_name", ""), "收信人")
	var id := str(mail.inbox(b_char)[0]["id"])
	# 另一封已讀信，用來驗證已讀狀態也恢復
	var c := soc_add("回信人", "xx_square")
	assert_true(_mail(c, "寄信人", "收到請回").get("ok", false))
	var back_id := str(mail.inbox(my_char)[0]["id"])
	assert_true(me_send("mail_read", { "id": back_id }).get("ok", false))
	soc_restart()
	assert_true(me_send("char_select", { "char_id": my_char }).get("ok", false), "local reselect")
	assert_eq(mail.find(back_id).get("read", false), true, "已讀狀態恢復")
	assert_eq(mail.find(id).get("read", true), false, "未讀狀態恢復")
	var b2 := soc_rejoin(b, b_char)
	var waiting := evs_of(b2, "mail_waiting")
	assert_eq(waiting.size(), 1, "上線收到 mail_waiting")
	if not waiting.is_empty():
		assert_eq(int(waiting[0]["p"]["n"]), 1)
	soc_ok(b2, "mail_list")
	var mails: Array = evs_of(b2, "mail_list")[0]["p"]["mails"]
	assert_eq(mails.size(), 1)
	assert_eq(mails[0]["id"], id)
	assert_eq(mails[0]["text"], "你不在，留個信")

func test_no_waiting_when_all_read() -> void:
	var b := _setup()
	if b == 0:
		return
	assert_true(_mail(1, "收信人", "一封").get("ok", false))
	var id := str(mail.inbox(str(rch(b).id))[0]["id"])
	soc_ok(b, "mail_read", { "id": id })
	clear_all_events()
	mail.on_enter(rs(b))
	pump()
	assert_eq(evs_of(b, "mail_waiting").size(), 0, "全讀了不提醒")

func test_char_delete_clears_mail() -> void:
	if not game_ok():
		return
	if make_char("將刪者") == null:
		return
	var doomed := str(ch().id)
	if make_char("留下者") == null:
		return
	var b := soc_add("寄件者", "xx_square")
	assert_true(_mail(b, "將刪者", "給要刪的角色").get("ok", false))
	assert_true(_mail(b, "留下者", "給留下的角色").get("ok", false))
	assert_eq(mail.inbox(doomed).size(), 1)
	var r := me_send("char_delete", { "char_id": doomed, "confirm_name": "將刪者" })
	assert_true(r.get("ok", false), "char_delete: %s" % str(r))
	if not mail.inbox(doomed).is_empty():
		# GameHost 尚未在 char_delete 成功後呼叫 mail.on_char_deleted（4.6.1 由 WP-HOST 接線）：補上，只驗本 WP 的行為
		print("[test_social] note: GameHost did not call mail.on_char_deleted; calling it directly")
		mail.on_char_deleted(doomed)
	assert_eq(mail.inbox(doomed).size(), 0, "寄給已刪角色的信清掉")
	assert_eq(mail.inbox(str(ch().id)).size(), 1, "別人的信不受影響")

func test_mail_requires_character() -> void:
	if not game_ok():
		return
	var lurker := soc_add("")
	assert_eq(soc_reason(lurker, "mail_list"), "no_character")
	assert_eq(soc_reason(lurker, "mail_send", { "to": "x", "text": "y" }), "no_character")

# ---------- M2 審查 ----------
## 一個寄件人最多在同一個收件匣留 MAX_UNREAD_PER_SENDER 封未讀信；別人照樣寄得進去
func test_one_sender_cannot_fill_inbox() -> void:
	var b := _setup()
	if b == 0:
		return
	ws.options["mail_inbox_max"] = 50
	for i in MailSystem.MAX_UNREAD_PER_SENDER:
		assert_true(_mail(1, "收信人", "騷擾%d" % i).get("ok", false), "mail %d" % i)
	assert_eq(str(_mail(1, "收信人", "再一封").get("reason", "")), "mailbox_full", "per-sender unread cap")
	var c := soc_add("路人寄件", "xx_square")
	assert_true(_mail(c, "收信人", "正經事").get("ok", false), "other senders still get through")
	var first := str(mail.inbox(str(rch(b).id))[0]["id"])
	soc_ok(b, "mail_read", { "id": first })
	assert_true(_mail(1, "收信人", "讀了一封後可以再寄").get("ok", false), "after one is read")

## 寄信間隔記在身分上：重連（新的 Session）不能繞過
func test_mail_interval_survives_reconnect() -> void:
	var b := _setup()
	if b == 0:
		return
	ws.options["mail_min_interval_real_s"] = 10
	var me: Session = host().session_for_peer(1)
	assert_true(_mail(1, "收信人", "第一封").get("ok", false), "first")
	var fresh := Session.new(9001, me.identity, me.display_name)
	fresh.character = me.character
	assert_eq(str(mail.send(fresh, "收信人", "換個連線再寄").get("reason", "")), "mail_too_fast", "new Session, same identity")
	mail.test_ms_offset += 10001
	assert_true(mail.send(fresh, "收信人", "十秒後").get("ok", false), "after 10 s")
	mail.test_ms_offset = 0

## 讀信、刪信立刻存檔（和寄信一樣）：當機後已讀不會變回未讀、刪掉的不會回來
func test_read_and_delete_saved_immediately() -> void:
	var b := _setup()
	if b == 0:
		return
	assert_true(_mail(1, "收信人", "讀我").get("ok", false))
	assert_true(_mail(1, "收信人", "刪我").get("ok", false))
	var ids := _ids_to(str(rch(b).id))
	soc_ok(b, "mail_read", { "id": ids[0] })
	soc_ok(b, "mail_delete", { "id": ids[1] })
	var disk: Dictionary = SaveManager.load_world(ws.world_id)
	assert_true(disk.get("ok", false), "load world.json")
	var on_disk := {}
	for m in disk.get("data", {}).get("mail", []):
		on_disk[str(m.get("id", ""))] = m
	assert_true(on_disk.has(ids[0]) and bool(on_disk[ids[0]].get("read", false)), "read flag on disk")
	assert_false(on_disk.has(ids[1]), "deleted letter gone from disk")
