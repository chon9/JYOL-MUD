extends "res://tests/unit/test_world_fixture.gd"
## WP-ECON：鏢局托鏢與取貨（M3B_PLAN §5.2.2、§11.1 test_m3b_consign）。
## 運費計算、送達時間、到站通知（在線／登入）、取貨、超重不拿、過期退回、沒有路線、寄給自己、不存在的人。
## 鏢頭 NPC 與 escort_routes 由 WP-MERGE 之後才進 data/ → 本機假資料。

const NPC_XX := "n_test_bt_xx"
const NPC_DL := "n_test_bt_dl"

var esc = null   # EscortSystem

func before_each() -> void:
	world_name = "w_m3b_consign"
	super.before_each()
	if ws.game != null:
		_install_fakes()

func _install_fakes() -> void:
	_fake_npc(NPC_XX, "xixia", "xx_square", "xixia")
	_fake_npc(NPC_DL, "dali", "dl_square", "dali")
	if not (tables().get("escort_routes") is Dictionary):
		tables()["escort_routes"] = {}
	tables()["escort_routes"]["er_test_xx_dl"] = { "id": "er_test_xx_dl", "from_city": "xixia", "to_city": "dali",
		"consign_delay_shichen": 4, "job_quest": "", "era": "1.0A", "src": "proposal" }
	tables()["escort_routes"]["er_test_dl_xx"] = { "id": "er_test_dl_xx", "from_city": "dali", "to_city": "xixia",
		"consign_delay_shichen": 4, "job_quest": "", "era": "1.0A", "src": "proposal" }
	esc = host().get("escort")
	if esc == null:
		esc = EscortSystem.new(host())

func _fake_npc(id: String, region: String, room: String, city: String) -> void:
	tables()["npcs"][id] = { "id": id, "name": "鏢頭", "kind": "FUNC", "region": region, "room": room,
		"alignment": "NEUTRAL", "talk": "", "services": ["ESCORT", "QUEST"], "escort": { "city": city },
		"night_closed": false, "era": "1.0A", "src": "proposal" }
	host().index.npc_room[id] = room

func _setup() -> int:
	if not game_ok():
		return 0
	if make_char("寄件人") == null:
		return 0
	goto("xx_square")
	var b := add_player("收件人")
	clear_events()
	return b

func _shichen() -> float:
	return host().day_s() / 12.0

## 把世界時間往前撥（不跑 tick），再手動 tick 鏢局
func _jump(world_s: float) -> void:
	ws.world["world_time_s"] = ws.world_time() + world_s
	esc.tick(ws.world_time())
	ws.flush()

func _only_consignment() -> Dictionary:
	var all: Array = esc.all()
	assert_eq(all.size(), 1, "一筆托鏢")
	return all[0] if not all.is_empty() else {}

# ---------- 純計算 ----------
func test_calc_pure() -> void:
	assert_eq(ConsignCalc.fee(0), 20)
	assert_eq(ConsignCalc.fee(7), 34)
	assert_eq(ConsignCalc.fee(7, 10, 3), 31)
	assert_eq(ConsignCalc.fee(-5), 20)
	assert_eq(ConsignCalc.arrive_s(100.0, 4, 1200.0), 500.0, "4 時辰 = 1/3 天")
	assert_eq(ConsignCalc.expire_s(0.0, 30, 10.0), 300.0)
	var t := { "escort_routes": {
		"a": { "from_city": "xixia", "to_city": "dali", "consign_delay_shichen": 4 },
		"b": { "from_city": "xixia", "to_city": "jingcheng", "consign_delay_shichen": 3 } } }
	assert_eq(int(ConsignCalc.route(t, "xixia", "dali").get("consign_delay_shichen", 0)), 4)
	assert_true(ConsignCalc.route(t, "dali", "xixia").is_empty(), "單向列")
	assert_true(ConsignCalc.route(t, "xixia", "xixia").is_empty())
	var rs := ConsignCalc.routes_from(t, "xixia")
	assert_eq(rs.size(), 2)
	assert_eq(rs[0]["to_city"], "dali", "依目的城排序")
	var c := { "status": "TRANSIT", "arrive_s": 50.0 }
	assert_eq(ConsignCalc.next_status(c, 49.0, 30, 10.0), "TRANSIT")
	assert_eq(ConsignCalc.next_status(c, 50.0, 30, 10.0), "READY")
	c = { "status": "READY", "arrive_s": 50.0, "ready_s": 50.0 }
	assert_eq(ConsignCalc.next_status(c, 349.0, 30, 10.0), "READY")
	assert_eq(ConsignCalc.next_status(c, 350.0, 30, 10.0), "RETURNED")

# ---------- 驗證 ----------
func test_send_validation() -> void:
	var b := _setup()
	if b == 0:
		return
	ch().money = 100
	var uid := give("r_wood", 3)
	var it := [{ "uid": uid, "n": 3 }]
	assert_eq(str(esc.send(s(), NPC_DL, "收件人", "dali", it, 0).get("reason", "")), "not_here", "鏢頭不在這裡")
	assert_eq(str(esc.send(s(), NPC_XX, "收件人", "nowhere", it, 0).get("reason", "")), "no_route")
	assert_eq(str(esc.send(s(), NPC_XX, "收件人", "xixia", it, 0).get("reason", "")), "no_route", "同城")
	assert_eq(str(esc.send(s(), NPC_XX, "江湖無此人", "dali", it, 0).get("reason", "")), "no_such_char")
	assert_eq(str(esc.send(s(), NPC_XX, "寄件人", "dali", it, 0).get("reason", "")), "self_target")
	var many: Array = []
	for i in 11:
		many.append({ "uid": "it_fake%d" % i, "n": 1 })
	assert_eq(str(esc.send(s(), NPC_XX, "收件人", "dali", many, 0).get("reason", "")), "too_many", "最多 10 個 uid")
	assert_eq(str(esc.send(s(), NPC_XX, "收件人", "dali", [{ "uid": "it_none", "n": 1 }], 0).get("reason", "")), "no_such_item")
	assert_eq(str(esc.send(s(), NPC_XX, "收件人", "dali", [{ "uid": uid, "n": 4 }], 0).get("reason", "")), "no_such_item", "數量不夠")
	var wuid := give("w_mudao", 1)
	assert_true(send("equip", { "item_uid": wuid }).get("ok", false))
	assert_eq(str(esc.send(s(), NPC_XX, "收件人", "dali", [{ "uid": wuid, "n": 1 }], 0).get("reason", "")), "equipped_item")
	var quid := give("i_letter", 1)
	assert_eq(str(esc.send(s(), NPC_XX, "收件人", "dali", [quid], 0).get("reason", "")), "not_bankable", "任務物品")
	assert_eq(str(esc.send(s(), NPC_XX, "收件人", "dali", [], -1).get("reason", "")), "bad_amount")
	# M3b 審查 4：直接呼叫也擋溢位（money + fee 超過 int64 以前會讓身上的錢變成天文數字）
	assert_eq(str(esc.send(s(), NPC_XX, "收件人", "dali", it, 9223372036854775807).get("reason", "")), "bad_amount", "money 超過身上上限")
	assert_eq(str(esc.send(s(), NPC_XX, "收件人", "dali", [], BankStore.CARRY_MONEY_CAP + 1).get("reason", "")), "bad_amount")
	assert_eq(str(esc.send(s(), NPC_XX, "收件人", "dali", [], 0).get("reason", "")), "no_such_item", "什麼都沒寄")
	# 運費 20 + 2 × 6（木材 3 × 重 2）= 32；加上寄的 70 兩 > 100
	assert_eq(str(esc.send(s(), NPC_XX, "收件人", "dali", it, 70).get("reason", "")), "not_enough_money")
	assert_eq(int(ch().money), 100, "失敗不扣錢")
	assert_eq(item_count("r_wood"), 3, "失敗不扣物品")
	assert_true(esc.all().is_empty())

# ---------- 寄送、到站、取貨 ----------
func test_send_arrive_online_take() -> void:
	var b := _setup()
	if b == 0:
		return
	ch().money = 200
	var uid := give("r_wood", 3)
	var r: Dictionary = esc.send(s(), NPC_XX, "收件人", "dali", [{ "uid": uid, "n": 2 }], 50)
	ws.flush()
	assert_true(r.get("ok", false), "send: %s" % str(r))
	assert_eq(int(r.get("fee", 0)), 28, "20 + 2 × 4（木材 2 件 × 重 2）")
	assert_eq(int(ch().money), 200 - 50 - 28)
	assert_eq(item_count("r_wood"), 1, "寄走 2 件")
	assert_false(last("consign_sent").is_empty(), "consign_sent")
	assert_eq(str(lastp("consign_sent").get("to_name", "")), "收件人")
	var c := _only_consignment()
	for k in ["id", "from_char", "from_name", "to_char", "to_name", "from_city", "to_city", "items", "money", "sent_s", "arrive_s", "status"]:
		assert_has(c, k, "world.consignments[]." + k)
	assert_eq(c["status"], "TRANSIT")
	assert_eq(c["to_city"], "dali")
	assert_true(absf(float(c["arrive_s"]) - float(c["sent_s"]) - 4.0 * _shichen()) < 0.01, "4 時辰")
	# 寫進 world.json（當機不丟）
	var disk: Dictionary = SaveManager.load_world(ws.world_id)
	assert_eq((disk.get("data", {}).get("consignments", []) as Array).size(), 1, "已存檔")
	# 還沒到
	_jump(3.9 * _shichen())
	assert_eq(str(_only_consignment()["status"]), "TRANSIT")
	assert_true(evs_for(b, "consign_arrived").is_empty())
	_jump(0.2 * _shichen())
	assert_eq(str(_only_consignment()["status"]), "READY")
	var arr := evs_for(b, "consign_arrived")
	assert_eq(arr.size(), 1, "在線收件人收到通知")
	assert_eq(str(arr[0]["p"].get("from_name", "")), "寄件人")
	assert_false(str(arr[0]["p"].get("city_name", "")).is_empty())
	# 收件人在西夏領不到（貨在大理）
	var bs := session_of(b)
	var cid := str(c["id"])
	goto_as(b, "xx_square")
	assert_eq(str(esc.take(bs, NPC_XX, cid).get("reason", "")), "no_such_item", "不在目的城")
	# 寄件人不能領
	goto("dl_square")
	assert_eq(str(esc.take(s(), NPC_DL, cid).get("reason", "")), "no_such_item", "不是給你的")
	# 收件人到大理領
	goto_as(b, "dl_square")
	var money_before := int(bs.character.money)
	var menu: Dictionary = esc.menu_fields(bs, NPC_DL)
	assert_eq(int(menu["escort"]["ready"]), 1, "npc_menu.escort.ready")
	assert_true(esc.list(bs, NPC_DL).get("ok", false))
	ws.flush()
	var lst := evs_for(b, "consign_list")
	assert_false(lst.is_empty(), "consign_list")
	assert_true(bool(lst[lst.size() - 1].get("ui", false)), "consign_list 走 ui")
	assert_eq((lst[lst.size() - 1]["p"]["ready"] as Array).size(), 1)
	var tr: Dictionary = esc.take(bs, NPC_DL, cid)
	ws.flush()
	assert_true(tr.get("ok", false), "take: %s" % str(tr))
	assert_eq(int(bs.character.inventory.count("r_wood")), 2)
	assert_eq(int(bs.character.money), money_before + 50)
	assert_true(esc.all().is_empty(), "領走後刪除")
	assert_false(evs_for(b, "consign_taken").is_empty(), "consign_taken")
	assert_eq(str(esc.take(bs, NPC_DL, cid).get("reason", "")), "no_such_item", "不能領兩次")

func test_take_too_heavy_takes_nothing() -> void:
	var b := _setup()
	if b == 0:
		return
	ch().money = 100
	var uid := give("r_wood", 2)
	assert_true(esc.send(s(), NPC_XX, "收件人", "dali", [uid], 10).get("ok", false))
	_jump(4.0 * _shichen() + 1.0)
	var bs := session_of(b)
	goto_as(b, "dl_square")
	tables()["items"]["r_wood"]["weight"] = 1000000   # 本機假資料（after_each 重建）
	var money_before := int(bs.character.money)
	var cid := str(_only_consignment()["id"])
	assert_eq(str(esc.take(bs, NPC_DL, cid).get("reason", "")), "too_heavy")
	assert_eq(int(bs.character.inventory.count("r_wood")), 0, "超重不拿任何東西")
	assert_eq(int(bs.character.money), money_before, "銀兩也不拿")
	assert_eq(str(_only_consignment()["status"]), "READY", "貨還在")

func test_offline_recipient_notified_on_login() -> void:
	var b := _setup()
	if b == 0:
		return
	ch().money = 100
	var bid := str(session_of(b).character.id)
	var ident := identity_of(b)
	drop_player(b)
	var uid := give("r_wood", 1)
	assert_true(esc.send(s(), NPC_XX, "收件人", "dali", [uid], 0).get("ok", false), "離線也能寄")
	_jump(5.0 * _shichen())
	assert_eq(str(_only_consignment()["status"]), "READY")
	var p2 := connect_player("收件人", ident)
	var r := send_as(p2, "char_select", { "char_id": bid })
	assert_true(r.get("ok", false), "char_select: %s" % str(r))
	if evs_for(p2, "consign_arrived").is_empty():
		# GameHost 登入流程還沒呼叫 escort.on_login（WP-SECT Day-0）：這裡直接呼叫，只驗本 WP 的行為
		esc.on_login(session_of(p2))
		ws.flush()
	assert_eq(evs_for(p2, "consign_arrived").size(), 1, "登入時收到")

func test_expire_returns_to_sender() -> void:
	var b := _setup()
	if b == 0:
		return
	ch().money = 100
	ws.options["consign_hold_days"] = 2
	var uid := give("r_wood", 2)
	assert_true(esc.send(s(), NPC_XX, "收件人", "dali", [uid], 30).get("ok", false))
	var money_after_send := int(ch().money)
	_jump(4.0 * _shichen() + 1.0)
	assert_eq(str(_only_consignment()["status"]), "READY")
	_jump(2.0 * host().day_s() + 1.0)
	var c := _only_consignment()
	assert_eq(str(c["status"]), "RETURNED", "過期退回")
	assert_eq(last("consign_returned").size() > 0, true, "寄件人收到退回通知")
	# 收件人領不到了
	goto_as(b, "dl_square")
	assert_eq(str(esc.take(session_of(b), NPC_DL, str(c["id"])).get("reason", "")), "no_such_item")
	# 寄件人在大理領不到（退回西夏）
	goto("dl_square")
	assert_eq(str(esc.take(s(), NPC_DL, str(c["id"])).get("reason", "")), "no_such_item")
	goto("xx_square")
	assert_eq(int(esc.menu_fields(s(), NPC_XX)["escort"]["ready"]), 1, "西夏鏢局有退回的貨")
	assert_true(esc.take(s(), NPC_XX, str(c["id"])).get("ok", false), "寄件人在西夏領回")
	assert_eq(item_count("r_wood"), 2)
	assert_eq(int(ch().money), money_after_send + 30, "寄的銀兩也退回（運費不退）")
	# 登入時也會提醒退回（另一筆）
	ch().money = 100
	var uid2 := give("r_wood", 1)
	assert_true(esc.send(s(), NPC_XX, "收件人", "dali", [uid2], 0).get("ok", false))
	_jump(4.0 * _shichen() + 1.0)
	_jump(2.0 * host().day_s() + 1.0)
	clear_events()
	esc.on_login(s())
	ws.flush()
	assert_false(last("consign_returned").is_empty(), "on_login 的退回提醒")

func test_menu_fields_shape() -> void:
	var b := _setup()
	if b == 0:
		return
	var m: Dictionary = esc.menu_fields(s(), NPC_XX)
	var e: Dictionary = m["escort"]
	for k in ["city", "city_name", "ready", "routes"]:
		assert_has(e, k, "npc_menu.escort." + k)
	assert_eq(e["city"], "xixia")
	var found := false
	for rt in e["routes"]:
		for k in ["city", "city_name", "delay_text"]:
			assert_has(rt, k, "routes[]." + k)
		if rt["city"] == "dali":
			found = true
	assert_true(found, "西夏 → 大理")
	tables()["npcs"]["n_test_plain"] = { "id": "n_test_plain", "name": "路人", "region": "xixia", "room": "xx_square",
		"services": ["SHOP"], "era": "1.0A" }
	assert_eq(esc.menu_fields(s(), "n_test_plain"), { "escort": null })

func test_intents_when_wired() -> void:
	var b := _setup()
	if b == 0:
		return
	if host().get("escort") == null:
		print("[test_m3b_consign] note: GameHost.escort 尚未接線（WP-SECT Day-0），略過 intent 路徑")
		return
	ch().money = 100
	var uid := give("r_wood", 1)
	var r := send("consign_send", { "npc": NPC_XX, "to": "收件人", "city": "dali", "items": [{ "uid": uid, "n": 1 }], "money": 0 })
	assert_true(r.get("ok", false), "consign_send intent: %s" % str(r))
	assert_true(send("consign_list", { "npc": NPC_XX }).get("ok", false), "consign_list intent")
	_jump(4.0 * _shichen() + 1.0)
	goto_as(b, "dl_square")
	var cid := str(_only_consignment()["id"])
	assert_true(send_as(b, "consign_take", { "npc": NPC_DL, "id": cid }).get("ok", false), "consign_take intent")

# ---------- M3b 審查 3 ----------
## 取貨後：磁碟上的 world.json 已經沒有這筆貨、角色檔已有貨（save_now(true)：先寫 world 再寫角色）
func test_take_saves_world_and_char() -> void:
	var b := _setup()
	if b == 0:
		return
	ch().money = 200
	var uid := give("r_wood", 2)
	assert_true(esc.send(s(), NPC_XX, "收件人", "dali", [uid], 0).get("ok", false))
	_jump(4.0 * _shichen() + 1.0)
	var cid := str(_only_consignment()["id"])
	var bs := session_of(b)
	goto_as(b, "dl_square")
	assert_true(esc.take(bs, NPC_DL, cid).get("ok", false))
	var disk: Dictionary = SaveManager.load_world(ws.world_id)
	assert_true((disk.get("data", {}).get("consignments", []) as Array).is_empty(), "world.json 已存：託運單沒了")
	var cdisk: Dictionary = SaveManager.load_character(ws.world_id, identity_of(b), str(bs.character.id))
	var invd: Variant = cdisk.get("data", {}).get("inventory", {})
	var inv: Variant = (invd as Dictionary).get("items", []) if invd is Dictionary else invd
	var n := 0
	for it in (inv if inv is Array else []):
		if it is Dictionary and str(it.get("id", "")) == "r_wood":
			n += int(it.get("n", 0))
	assert_eq(n, 2, "角色檔已存：貨在身上")

## 寄件人刪除：還在路上的貨收件人照領；過期退回時（沒人能領）從 world.consignments 清掉
func test_deleted_sender_returned_is_dropped() -> void:
	var b := _setup()
	if b == 0:
		return
	ch().money = 200
	var uid := give("r_wood", 1)
	assert_true(esc.send(s(), NPC_XX, "收件人", "dali", [uid], 0).get("ok", false))
	var uid2 := give("r_wood", 1)
	assert_true(esc.send(s(), NPC_XX, "收件人", "dali", [uid2], 0).get("ok", false))
	assert_eq(esc.all().size(), 2)
	esc.on_char_deleted(str(ch().id))
	assert_eq(esc.all().size(), 2, "還在路上：保留給收件人")
	ws.options["consign_hold_days"] = 2
	_jump(4.0 * _shichen() + 1.0)
	# 收件人領走一筆
	var bs := session_of(b)
	goto_as(b, "dl_square")
	assert_true(esc.take(bs, NPC_DL, str(esc.all()[0]["id"])).get("ok", false), "寄件人刪了，收件人照領")
	assert_eq(esc.all().size(), 1)
	# 另一筆過期退回 → 寄件人已不在 → 清掉
	_jump(2.0 * host().day_s() + 1.0)
	assert_true(esc.all().is_empty(), "退回給已刪除的寄件人 → 清掉")
