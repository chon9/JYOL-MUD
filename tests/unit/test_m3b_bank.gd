extends "res://tests/unit/test_world_fixture.gd"
## WP-ECON：錢莊（M3B_PLAN §5.2.1、§11.1 test_m3b_bank）。
## 存取物品（部分堆疊）、存領錢、容量、存款上限、任務物品與裝備拒存、角色檔往返、三城共用、腐壞凍結。
## 資料（錢莊 NPC）由 WP-MERGE 之後才進 data/ → 這裡用本機假資料（M3B_PLAN 9.1：local fakes）。

const NPC_XX := "n_test_bank_xx"
const NPC_DL := "n_test_bank_dl"

var bk = null   # BankSystem

func before_each() -> void:
	world_name = "w_m3b_bank"
	super.before_each()
	if ws.game != null:
		_install_fakes()

## 假的錢莊 NPC（xx_square、dl_square），GameData.tables 在 after_each 由 _restore_rules 重建
func _install_fakes() -> void:
	_fake_npc(NPC_XX, "xixia", "xx_square", ["BANK"])
	_fake_npc(NPC_DL, "dali", "dl_square", ["BANK"])
	bk = host().get("bank")
	if bk == null:
		bk = BankSystem.new(host())

func _fake_npc(id: String, region: String, room: String, services: Array) -> void:
	tables()["npcs"][id] = { "id": id, "name": "錢莊掌櫃", "kind": "FUNC", "region": region, "room": room,
		"alignment": "NEUTRAL", "talk": "", "services": services, "night_closed": false, "era": "1.0A", "src": "proposal" }
	host().index.npc_room[id] = room

func _bank() -> Dictionary:
	return BankStore.bank_of(ch())

func _setup() -> bool:
	if not game_ok():
		return false
	if make_char("存錢的人") == null:
		return false
	goto("xx_square")
	clear_events()
	return true

# ---------- 物品 ----------
func test_put_take_partial_stack() -> void:
	if not _setup():
		return
	var uid := give("r_wood", 10)
	var r: Dictionary = bk.put(s(), NPC_XX, uid, 4)
	ws.flush()
	assert_true(r.get("ok", false), "put 4: %s" % str(r))
	assert_eq(item_count("r_wood"), 6, "身上剩 6")
	assert_eq(BankStore.count(_bank(), "r_wood"), 4, "錢莊 4")
	assert_false(last("bank_put").is_empty(), "bank_put 訊息")
	assert_eq(int(lastp("bank_put").get("n", 0)), 4)
	var view := last("bank_view")
	assert_false(view.is_empty(), "bank_view")
	assert_true(bool(view.get("ui", false)), "bank_view 走 ui")
	var vp: Dictionary = view.get("p", {})
	for k in ["money", "items", "used", "capacity", "money_cap"]:
		assert_has(vp, k, "bank_view." + k)
	assert_eq(int(vp["used"]), 4)
	var row: Dictionary = (vp["items"] as Array)[0]
	for k in ["uid", "item_id", "name", "n", "weight"]:
		assert_has(row, k, "bank_view.items[]." + k)
	assert_eq(row["item_id"], "r_wood")
	# 再存剩下的整疊（n = 0 = 整疊）→ 錢莊仍只有一列
	assert_true(bk.put(s(), NPC_XX, first_uid("r_wood"), 0).get("ok", false), "put rest")
	assert_eq(item_count("r_wood"), 0)
	assert_eq((_bank()["items"] as Array).size(), 1, "同物品併一列")
	assert_eq(BankStore.count(_bank(), "r_wood"), 10)
	var buid := str(BankStore.find_id(_bank(), "r_wood")["uid"])
	assert_eq(str(bk.take(s(), NPC_XX, buid, 11).get("reason", "")), "no_such_item", "取超過存量")
	assert_true(bk.take(s(), NPC_XX, buid, 3).get("ok", false), "take 3")
	ws.flush()
	assert_eq(item_count("r_wood"), 3)
	assert_eq(BankStore.count(_bank(), "r_wood"), 7)
	assert_false(last("bank_take").is_empty(), "bank_take 訊息")
	assert_true(bk.take(s(), NPC_XX, buid, 0).get("ok", false), "take all")
	assert_eq(item_count("r_wood"), 10)
	assert_true((_bank()["items"] as Array).is_empty(), "取光後列刪除")
	assert_eq(str(bk.take(s(), NPC_XX, buid, 1).get("reason", "")), "no_such_item")

func test_put_refusals_order() -> void:
	if not _setup():
		return
	assert_eq(str(bk.put(s(), NPC_XX, "it_nothing", 1).get("reason", "")), "no_such_item")
	var wuid := give("w_mudao", 1)
	assert_true(send("equip", { "item_uid": wuid }).get("ok", false), "equip")
	assert_eq(str(bk.put(s(), NPC_XX, wuid, 1).get("reason", "")), "equipped_item")
	var quid := give("i_letter", 1)
	assert_eq(str(bk.put(s(), NPC_XX, quid, 1).get("reason", "")), "not_bankable", "任務物品")
	tables()["items"]["r_wood"]["bankable"] = false
	var nuid := give("r_wood", 2)
	assert_eq(str(bk.put(s(), NPC_XX, nuid, 1).get("reason", "")), "not_bankable", "bankable: false")
	tables()["items"]["r_wood"].erase("bankable")
	# 容量
	ws.options["bank_capacity"] = 5
	var ruid := give("r_rice", 6)
	assert_eq(str(bk.put(s(), NPC_XX, ruid, 6).get("reason", "")), "bank_full")
	assert_true(bk.put(s(), NPC_XX, ruid, 5).get("ok", false), "剛好 5 件")
	assert_eq(str(bk.put(s(), NPC_XX, nuid, 1).get("reason", "")), "bank_full")
	assert_eq(int(bk.view(ch())["used"]), 5)
	assert_eq(int(bk.view(ch())["capacity"]), 5)

func test_take_too_heavy_or_too_many() -> void:
	if not _setup():
		return
	var uid := give("r_wood", 20)
	assert_true(bk.put(s(), NPC_XX, uid, 20).get("ok", false))
	var buid := str(BankStore.find_id(_bank(), "r_wood")["uid"])
	# 取出會超重：把木材改成極重（本機假資料，after_each 重建）
	tables()["items"]["r_wood"]["weight"] = 1000000
	assert_eq(str(bk.take(s(), NPC_XX, buid, 1).get("reason", "")), "too_heavy", "超重")
	assert_eq(BankStore.count(_bank(), "r_wood"), 20, "失敗不動錢莊")
	# 件數（純邏輯）：背包已有 300 件
	var inv := Inventory.new()
	var mk := func() -> String: return "u%d" % randi()
	inv.add("r_rice", 99, tables(), 0.0, -1, mk)
	inv.add("r_rice", 99, tables(), 0.0, -1, mk)
	inv.add("r_rice", 99, tables(), 0.0, -1, mk)
	inv.add("r_rice", 3, tables(), 0.0, -1, mk)
	assert_eq(inv.pieces(), 300)
	var b := BankStore.empty()
	BankStore.add_lots(b, "r_wood", [{ "born_s": 0.0, "n": 2, "stored_s": 0.0 }], "", mk)
	var t := BankStore.take(b, inv, str(b["items"][0]["uid"]), 1, tables(), -1, 0.0, mk)
	assert_eq(str(t.get("reason", "")), "too_many")

# ---------- 銀兩 ----------
func test_money_deposit_withdraw_caps() -> void:
	if not _setup():
		return
	ch().money = 1000
	assert_eq(str(bk.money(s(), NPC_XX, 0).get("reason", "")), "bad_amount")
	assert_eq(str(bk.money(s(), NPC_XX, 1001).get("reason", "")), "not_enough_money")
	assert_true(bk.money(s(), NPC_XX, 600).get("ok", false), "存 600")
	ws.flush()
	assert_eq(int(ch().money), 400)
	assert_eq(int(_bank()["money"]), 600)
	assert_eq(int(lastp("bank_money").get("bank_money", 0)), 600)
	assert_eq(str(lastp("bank_money").get("verb", "")), "存入")
	ws.options["bank_money_cap"] = 700
	assert_eq(str(bk.money(s(), NPC_XX, 200).get("reason", "")), "bank_money_cap")
	assert_true(bk.money(s(), NPC_XX, 100).get("ok", false), "剛好到上限")
	assert_eq(str(bk.money(s(), NPC_XX, -701).get("reason", "")), "not_enough_bank_money")
	ch().money = Character.MONEY_CAP - 100
	assert_eq(str(bk.money(s(), NPC_XX, -200).get("reason", "")), "money_cap")
	assert_true(bk.money(s(), NPC_XX, -100).get("ok", false), "領 100")
	assert_eq(int(ch().money), Character.MONEY_CAP)
	assert_eq(int(_bank()["money"]), 600)
	ws.flush()
	assert_eq(str(lastp("bank_money").get("verb", "")), "領出")

# ---------- 驗證順序的前段 ----------
func test_gates() -> void:
	if not _setup():
		return
	_fake_npc("n_test_not_bank", "xixia", "xx_square", ["SHOP"])
	assert_eq(str(bk.open(s(), "n_test_not_bank").get("reason", "")), "not_at_bank", "沒有 BANK 服務")
	assert_eq(str(bk.open(s(), NPC_DL).get("reason", "")), "not_at_bank", "NPC 不在這裡")
	assert_eq(str(bk.open(s(), "n_nobody").get("reason", "")), "not_at_bank")
	assert_true(bk.open(s(), NPC_XX).get("ok", false), "open")
	s().battle_id = 999
	assert_eq(str(bk.open(s(), NPC_XX).get("reason", "")), "in_battle")
	s().battle_id = 0
	var fake := Session.new(77, "nobody", "nobody")
	assert_eq(str(bk.money(fake, NPC_XX, 1).get("reason", "")), "no_character")
	# npc_menu 欄位
	assert_eq(bk.menu_fields(s(), NPC_XX), { "bank": true })
	assert_eq(bk.menu_fields(s(), "n_test_not_bank"), { "bank": false })

# ---------- 三城共用、存檔往返 ----------
func test_shared_between_cities_and_roundtrip() -> void:
	if not _setup():
		return
	ch().money = 800
	var uid := give("r_wood", 3)
	assert_true(bk.money(s(), NPC_XX, 500).get("ok", false))
	assert_true(bk.put(s(), NPC_XX, uid, 3).get("ok", false))
	# 角色檔往返
	var d: Dictionary = ch().to_dict()
	var c2 = Character.from_dict(JSON.parse_string(JSON.stringify(d)))
	var b2 := BankStore.bank_of(c2)
	assert_eq(int(b2["money"]), 500, "存款隨角色檔")
	assert_eq(BankStore.count(b2, "r_wood"), 3, "物品隨角色檔")
	if "bank" in ch():
		assert_eq(int(c2.bank["money"]), 500, "ch.bank 欄位（§4.12）")
	# 大理錢莊取出
	goto("dl_square")
	assert_eq(str(bk.open(s(), NPC_XX).get("reason", "")), "not_at_bank", "西夏掌櫃不在大理")
	var buid := str(BankStore.find_id(_bank(), "r_wood")["uid"])
	assert_true(bk.take(s(), NPC_DL, buid, 3).get("ok", false), "大理取物")
	assert_true(bk.money(s(), NPC_DL, -500).get("ok", false), "大理領錢")
	assert_eq(item_count("r_wood"), 3)
	assert_eq(int(ch().money), 800)

func test_persists_across_restart() -> void:
	if not _setup():
		return
	ch().money = 300
	assert_true(bk.money(s(), NPC_XX, 300).get("ok", false))
	var cid := str(ch().id)
	host().save_char(ch())
	restart_world()
	if not game_ok():
		return
	_install_fakes()
	assert_true(send("char_select", { "char_id": cid }).get("ok", false), "char_select")
	assert_eq(int(_bank()["money"]), 300, "重開後錢莊仍在")

# ---------- 腐壞凍結 ----------
func test_spoil_frozen_in_bank() -> void:
	if not _setup():
		return
	var day: float = host().day_s()
	var uid := give("c_baifan", 2)   # 3 天腐壞
	ws.world["world_time_s"] = ws.world_time() + day * 2.0   # 放了 2 天
	assert_true(bk.put(s(), NPC_XX, uid, 2).get("ok", false))
	ws.world["world_time_s"] = ws.world_time() + day * 10.0  # 錢莊裡 10 天
	var buid := str(BankStore.find_id(_bank(), "c_baifan")["uid"])
	assert_true(bk.take(s(), NPC_XX, buid, 2).get("ok", false))
	assert_eq(item_count("c_baifan"), 2)
	var it: Dictionary = ch().inventory.find(first_uid("c_baifan"))
	var left: float = ch().inventory.spoil_left_s(it, ws.world_time(), day, tables())
	assert_true(absf(left - day) < 1.0, "還剩約 1 天（存入前用掉 2 天）：%f" % left)
	assert_true(ch().inventory.spoil(ws.world_time(), day, tables()).is_empty(), "取出時沒有壞")

# ---------- 純邏輯 ----------
func test_bank_store_pure() -> void:
	var b := { "money": "12", "items": [ { "uid": "a", "id": "r_wood", "n": 3, "born_s": 5.0 }, { "id": "bad" }, "x" ] }
	BankStore.normalize(b)
	assert_eq(int(b["money"]), 12)
	assert_eq((b["items"] as Array).size(), 1, "壞列丟掉")
	assert_eq(BankStore.pieces(b), 3)
	assert_eq(int((b["items"][0]["lots"] as Array)[0]["n"]), 3, "舊列沒有 lots 補一批")
	assert_eq(BankStore.find(b, "a")["id"], "r_wood")
	assert_true(BankStore.find(b, "").is_empty())
	assert_eq(BankStore.money_reason(0, 10, 5, 100), "")
	assert_eq(BankStore.money_reason(99, 10, 5, 100), "bank_money_cap")
	assert_eq(BankStore.money_reason(0, 10, 11, 100), "not_enough_money")
	assert_eq(BankStore.money_reason(5, 10, -6, 100), "not_enough_bank_money")
	assert_eq(BankStore.money_reason(5, 9, -5, 100, 10), "money_cap")
	assert_eq(BankStore.thaw_born(10.0, 100.0, 160.0), 70.0)
	assert_eq(BankStore.thaw_born(10.0, 100.0, 50.0), 10.0, "時間倒退不平移")
	assert_false(BankStore.bankable({}), "不存在的物品")
	assert_false(BankStore.bankable({ "quest_item": true }))
	assert_false(BankStore.bankable({ "bankable": false }))
	assert_true(BankStore.bankable({ "name": "x" }))
	# take_lots：最舊的先拿、平移
	var mk := func() -> String: return "u%d" % randi()
	var b3 := BankStore.empty()
	BankStore.add_lots(b3, "c_baifan", [{ "born_s": 0.0, "n": 1, "stored_s": 10.0 }, { "born_s": 5.0, "n": 2, "stored_s": 20.0 }], "", mk)
	var got := BankStore.take_lots(b3, str(b3["items"][0]["uid"]), 2, 100.0)
	assert_eq(got.size(), 2)
	assert_eq(float(got[0]["born_s"]), 90.0)
	assert_eq(float(got[1]["born_s"]), 85.0)
	assert_eq(BankStore.count(b3, "c_baifan"), 1)

# ---------- intent 路徑（GameHost 已接上 BankSystem 時；WP-SECT Day-0） ----------
func test_intents_when_wired() -> void:
	if not _setup():
		return
	if host().get("bank") == null:
		print("[test_m3b_bank] note: GameHost.bank 尚未接線（WP-SECT Day-0），略過 intent 路徑")
		return
	ch().money = 100
	var r := send("bank_money", { "npc": NPC_XX, "amount": 40 })
	assert_true(r.get("ok", false), "bank_money intent: %s" % str(r))
	assert_eq(int(ch().money), 60)
	var uid := give("r_wood", 2)
	assert_true(send("bank_put", { "npc": NPC_XX, "uid": uid, "n": 1 }).get("ok", false), "bank_put intent")
	assert_true(send("bank_open", { "npc": NPC_XX }).get("ok", false), "bank_open intent")
	var buid := str(BankStore.find_id(_bank(), "r_wood")["uid"])
	assert_true(send("bank_take", { "npc": NPC_XX, "uid": buid, "n": 1 }).get("ok", false), "bank_take intent")
	assert_eq(item_count("r_wood"), 2)
