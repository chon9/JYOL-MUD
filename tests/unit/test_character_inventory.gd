extends "res://tests/test_case.gd"
## WP-CHAR：背包疊加、300 件、超重、裝備、腐壞、take_all／take_equipped、往返。

const F := preload("res://tests/unit/test_character_fixtures.gd")

var t: Dictionary

func before_each() -> void:
	t = F.tables()

func test_stacking() -> void:
	var inv := Inventory.new()
	var mk := F.uid_maker()
	var r1 := inv.add("c_mantou", 15, t, 1.0, -1, mk)
	assert_eq(r1["ok"], true)
	var r2 := inv.add("c_mantou", 10, t, 2.0, -1, mk)
	assert_eq(r2["ok"], true)
	assert_eq(inv.items.size(), 2, "stack 20 → 20 + 5")
	assert_eq(inv.items[0]["n"], 20)
	assert_eq(inv.items[1]["n"], 5)
	assert_eq(inv.items[1]["born_s"], 2.0)
	assert_eq(inv.count("c_mantou"), 25)
	assert_eq(inv.pieces(), 25)
	inv.add("w_mudao", 2, t, 0.0, -1, mk)
	assert_eq(inv.items.size(), 4, "non-stackable: one instance each")
	assert_eq(inv.weight(t), 25 + 4)

func test_perishable_merges_and_spoils_only_old_lot() -> void:
	var inv := Inventory.new()
	var mk := F.uid_maker()
	inv.add("c_mantou", 1, t, 0.0, -1, mk)
	inv.add("c_mantou", 19, t, 5000.0, -1, mk)
	assert_eq(inv.items.size(), 1, "同一種物品一律疊在一起（堆疊上限 20）")
	assert_eq(inv.items[0]["n"], 20)
	assert_eq(inv.items[0]["lots"], [{ "born_s": 0.0, "n": 1 }, { "born_s": 5000.0, "n": 19 }])
	assert_eq(inv.items[0]["born_s"], 0.0, "born_s = 最舊一批")
	var gone := inv.spoil(3.0 * 7200.0 + 1.0, 7200.0, t)
	assert_eq(gone, [{ "id": "c_mantou", "n": 1 }], "只有舊的那一個壞掉")
	assert_eq(inv.count("c_mantou"), 19)
	assert_eq(inv.items[0]["lots"], [{ "born_s": 5000.0, "n": 19 }])
	assert_eq(inv.items[0]["born_s"], 5000.0)
	# 滿了才開新格
	inv.add("c_mantou", 3, t, 6000.0, -1, mk)
	assert_eq(inv.items.size(), 2)
	assert_eq(inv.items[0]["n"], 20)
	assert_eq(inv.items[1]["n"], 2)
	assert_eq(inv.items[0]["lots"], [{ "born_s": 5000.0, "n": 19 }, { "born_s": 6000.0, "n": 1 }])
	# 非腐壞物品照常合併，而且只留一批
	inv.add("c_jingyao", 1, t, 0.0, -1, mk)
	inv.add("c_jingyao", 1, t, 99999.0, -1, mk)
	var jy := inv.items.filter(func(it): return it["id"] == "c_jingyao")
	assert_eq(jy.size(), 1)
	assert_eq(jy[0]["lots"], [{ "born_s": 0.0, "n": 2 }])

func test_pelts_from_many_battles_one_slot() -> void:
	var inv := Inventory.new()
	var mk := F.uid_maker()
	for k in 5:
		inv.add("r_bigrabbitskin", 1, t, 1000.0 * k, -1, mk)
	assert_eq(inv.items.size(), 1, "5 場戰鬥的大兔皮在同一格")
	assert_eq(inv.count("r_bigrabbitskin"), 5)
	assert_eq(inv.items[0]["lots"].size(), 5)
	# 30 天 × 7200 秒；第 0、1000 秒那兩批先壞
	var gone := inv.spoil(30.0 * 7200.0 + 1500.0, 7200.0, t)
	assert_eq(gone, [{ "id": "r_bigrabbitskin", "n": 2 }])
	assert_eq(inv.count("r_bigrabbitskin"), 3)
	assert_eq(inv.items.size(), 1)

func test_oldest_lot_consumed_first() -> void:
	var inv := Inventory.new()
	var mk := F.uid_maker()
	var uid := String(inv.add("c_mantou", 2, t, 100.0, -1, mk)["uid"])
	inv.add("c_mantou", 3, t, 900.0, -1, mk)
	inv.add("c_mantou", 1, t, 500.0, -1, mk)   # 撿回較舊的一批：照時間排
	assert_eq(inv.items[0]["lots"], [{ "born_s": 100.0, "n": 2 }, { "born_s": 500.0, "n": 1 }, { "born_s": 900.0, "n": 3 }])
	inv.remove(uid, 1)   # 使用／賣出：從最舊的扣
	assert_eq(inv.items[0]["lots"], [{ "born_s": 100.0, "n": 1 }, { "born_s": 500.0, "n": 1 }, { "born_s": 900.0, "n": 3 }])
	inv.remove_item_id("c_mantou", 3)   # 交任務：從最舊的扣
	assert_eq(inv.items[0]["lots"], [{ "born_s": 900.0, "n": 2 }])
	assert_eq(inv.items[0]["born_s"], 900.0)
	assert_eq(inv.items[0]["n"], 2)
	# 外部直接改 n（舊程式）也保持一致：少了＝最舊的先用掉
	inv.items[0]["n"] = 1
	assert_eq(inv.spoil_left_s(inv.items[0], 1000.0, 7200.0, t), 900.0 + 3 * 7200.0 - 1000.0)
	assert_eq(inv.items[0]["lots"], [{ "born_s": 900.0, "n": 1 }])
	assert_eq(inv.spoil_left_s({ "uid": "x", "id": "c_jingyao", "n": 1, "born_s": 0.0 }, 1.0, 7200.0, t), -1.0, "不會腐壞")

func test_add_lots_keeps_freshness() -> void:
	# 屍體撿回：每一批的時間原樣保留
	var inv := Inventory.new()
	var mk := F.uid_maker()
	inv.add("r_bigrabbitskin", 1, t, 50.0, -1, mk)
	var r := inv.add_lots("r_bigrabbitskin", [{ "born_s": 300.0, "n": 2 }, { "born_s": 10.0, "n": 1 }], t, -1, mk)
	assert_eq(r["ok"], true)
	assert_eq(inv.items.size(), 1)
	assert_eq(inv.items[0]["lots"], [{ "born_s": 10.0, "n": 1 }, { "born_s": 50.0, "n": 1 }, { "born_s": 300.0, "n": 2 }])
	assert_eq(inv.add_lots("r_bigrabbitskin", [], t, -1, mk)["reason"], "no_item")

func test_legacy_load_single_born_and_split_stacks() -> void:
	# 舊版存檔：沒有 lots，被 60 秒合併窗拆成好幾格
	var legacy := { "items": [
		{ "uid": "it_a", "id": "r_bigrabbitskin", "n": 2, "born_s": 500.0 },
		{ "uid": "it_w", "id": "w_mudao", "n": 1, "born_s": 0.0 },
		{ "uid": "it_b", "id": "r_bigrabbitskin", "n": 1, "born_s": 100.0 },
		{ "uid": "it_c", "id": "c_mantou", "n": 15, "born_s": 10.0 },
		{ "uid": "it_d", "id": "c_mantou", "n": 9, "born_s": 20.0 },
		{ "uid": "it_e", "id": "r_bigrabbitskin", "n": 4, "born_s": 900.0 },
	], "equipped": { "WEAPON": "it_w", "ARMOR": "" } }
	var inv := Inventory.from_dict(legacy)
	assert_eq(inv.items.size(), 6, "from_dict 不需要物品表：先原樣載入")
	assert_eq(inv.items[0]["lots"], [{ "born_s": 500.0, "n": 2 }], "單一 born_s → 一批")
	assert_true(inv.consolidate(t), "有合併")
	var skins := inv.items.filter(func(it): return it["id"] == "r_bigrabbitskin")
	assert_eq(skins.size(), 1, "兔皮併成一格")
	assert_eq(skins[0]["uid"], "it_a", "留第一格的 uid")
	assert_eq(skins[0]["n"], 7)
	assert_eq(skins[0]["lots"], [{ "born_s": 100.0, "n": 1 }, { "born_s": 500.0, "n": 2 }, { "born_s": 900.0, "n": 4 }])
	var mt := inv.items.filter(func(it): return it["id"] == "c_mantou")
	assert_eq(mt.size(), 2, "24 個饅頭（上限 20）→ 20 + 4")
	assert_eq(mt[0]["lots"], [{ "born_s": 10.0, "n": 15 }, { "born_s": 20.0, "n": 5 }], "最舊的在前一格")
	assert_eq(mt[1]["lots"], [{ "born_s": 20.0, "n": 4 }])
	assert_eq(inv.equipped["WEAPON"], "it_w")
	assert_false(inv.consolidate(t), "第二次不再變動")
	# 存讀往返（含 lots）
	var d := inv.to_dict()
	var back := Inventory.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(back.to_dict(), d)
	assert_false(back.to_dict(true)["items"][0].has("lots"), "legacy 格式不含 lots")

func test_sheet_freshness() -> void:
	var c := F.new_char()
	c.inventory.add("c_mantou", 2, t, 0.0, -1, F.uid_maker("it_s"))
	var sh := c.to_sheet(t, { "game_day_real_s": 7200.0 }, {}, 7200.0 * 1.5)
	var got := {}
	for it in sh["inventory"]:
		got[it["id"]] = it
	assert_eq(got["c_mantou"]["spoil_left_days"], 1.5)
	assert_eq(got["c_mantou"]["perishable"], true)
	assert_eq(got["c_jingyao"]["spoil_left_days"], -1.0)
	assert_eq(InventoryPanel.freshness_text(got["c_mantou"]), "最早一批剩 1 天會腐壞")
	assert_eq(InventoryPanel.freshness_corner(got["c_mantou"]), "1天")
	assert_eq(InventoryPanel.freshness_text(got["c_jingyao"]), "不會腐壞")
	assert_eq(InventoryPanel.freshness_corner(got["c_jingyao"]), "")
	assert_eq(InventoryPanel.freshness_text({ "spoil_left_days": 5.2 }), "最早一批剩 5 天會腐壞")
	assert_eq(InventoryPanel.freshness_corner({ "spoil_left_days": 5.2 }), "")
	assert_eq(InventoryPanel.freshness_text({ "spoil_left_days": 0.3 }), "最早一批剩不到 1 天會腐壞")

func test_unknown_item() -> void:
	var inv := Inventory.new()
	assert_eq(inv.add("nope", 1, t, 0.0, -1, F.uid_maker())["reason"], "no_item")

func test_inventory_full_300() -> void:
	var inv := Inventory.new()
	var mk := F.uid_maker()
	assert_eq(inv.add("c_jingyao", 297, t, 0.0, -1, mk)["ok"], true)
	assert_eq(inv.add("c_jingyao", 3, t, 0.0, -1, mk)["ok"], true)
	assert_eq(inv.pieces(), 300)
	var r := inv.add("c_jingyao", 1, t, 0.0, -1, mk)
	assert_eq(r["ok"], false)
	assert_eq(r["reason"], "inventory_full")
	assert_eq(inv.pieces(), 300)

func test_overweight() -> void:
	var inv := Inventory.new()
	var mk := F.uid_maker()
	assert_eq(inv.add("r_stone", 3, t, 0.0, 160, mk)["ok"], true)
	var r := inv.add("r_stone", 1, t, 0.0, 160, mk)
	assert_eq(r["reason"], "overweight", "150 + 50 > 160")
	assert_eq(inv.count("r_stone"), 3)

func test_equip_swap_unequip() -> void:
	var inv := Inventory.new()
	var mk := F.uid_maker()
	var a := String(inv.add("w_mudao", 1, t, 0.0, -1, mk)["uid"])
	var b := String(inv.add("w_mujian", 1, t, 0.0, -1, mk)["uid"])
	var p := String(inv.add("c_jingyao", 1, t, 0.0, -1, mk)["uid"])
	assert_eq(inv.equip(a, t), { "ok": true, "reason": "", "slot": "WEAPON", "prev_uid": "" })
	assert_eq(inv.equip(b, t), { "ok": true, "reason": "", "slot": "WEAPON", "prev_uid": a })
	assert_eq(inv.equipped_row("WEAPON", t)["id"], "w_mujian")
	assert_eq(inv.equip(p, t)["reason"], "not_equippable")
	assert_eq(inv.equip("it_x", t)["reason"], "no_item")
	assert_eq(inv.unequip("WEAPON"), { "ok": true, "reason": "", "uid": b })
	assert_eq(inv.unequip("WEAPON")["reason"], "no_item")
	assert_eq(inv.unequip("HAT")["reason"], "no_item")
	assert_eq(inv.equipped_row("WEAPON", t), {})
	var opts := inv.weapon_options(t)
	assert_eq(opts.size(), 2)
	assert_eq(opts[0], { "uid": a, "item_id": "w_mudao", "weapon_type": "BLADE", "atk": 4, "name": "木刀" })

func test_remove_and_remove_item_id() -> void:
	var inv := Inventory.new()
	var mk := F.uid_maker()
	var u1 := String(inv.add("c_jingyao", 3, t, 5.0, -1, mk)["uid"])
	var w := String(inv.add("w_mudao", 1, t, 0.0, -1, mk)["uid"])
	inv.equip(w, t)
	assert_eq(inv.remove(u1, 4)["reason"], "no_item", "not enough")
	assert_eq(inv.remove(u1, 2), { "ok": true, "reason": "", "removed": 2 })
	assert_eq(inv.count("c_jingyao"), 1)
	assert_eq(inv.remove(w, 1)["ok"], true)
	assert_eq(inv.equipped["WEAPON"], "", "removing equipped unequips")
	# 依 born_s 由舊到新扣
	var inv2 := Inventory.new()
	var mk2 := F.uid_maker("it_b")
	inv2.items = [
		{ "uid": "it_new", "id": "r_bigrabbitskin", "n": 2, "born_s": 50.0 },
		{ "uid": "it_old", "id": "r_bigrabbitskin", "n": 2, "born_s": 10.0 },
	]
	assert_eq(inv2.remove_item_id("r_bigrabbitskin", 3)["ok"], true)
	assert_eq(inv2.items, [{ "uid": "it_new", "id": "r_bigrabbitskin", "n": 1, "born_s": 50.0, "lots": [{ "born_s": 50.0, "n": 1 }] }])
	assert_eq(inv2.remove_item_id("r_bigrabbitskin", 2)["reason"], "no_item")
	assert_eq(mk2.call(), "it_b000001")

func test_spoil() -> void:
	var inv := Inventory.new()
	var mk := F.uid_maker()
	inv.add("c_mantou", 3, t, 0.0, -1, mk)
	inv.add("c_jingyao", 2, t, 0.0, -1, mk)
	assert_eq(inv.spoil(3 * 7200.0 - 1.0, 7200.0, t), [])
	assert_eq(inv.spoil(3 * 7200.0, 7200.0, t), [{ "id": "c_mantou", "n": 3 }])
	assert_eq(inv.count("c_mantou"), 0)
	assert_eq(inv.count("c_jingyao"), 2, "spoil_days 0 never spoils")

func test_take_all_and_take_equipped() -> void:
	var c := F.new_char()
	var eq_uids := [c.inventory.equipped["WEAPON"], c.inventory.equipped["ARMOR"]]
	var got := c.inventory.take_equipped()
	assert_eq(got.size(), 2)
	assert_true(eq_uids.has(got[0]["uid"]) and eq_uids.has(got[1]["uid"]))
	assert_eq(c.inventory.equipped, Inventory.empty_equipped())   # M3c：8 個裝備欄
	assert_eq(c.inventory.count("c_jingyao"), 5, "bag untouched")
	var all := c.inventory.take_all()
	assert_eq(all.size(), 1)
	assert_eq(c.inventory.items, [])

func test_roundtrip() -> void:
	var c := F.new_char()
	var d := c.inventory.to_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(d))
	var inv := Inventory.from_dict(parsed)
	assert_eq(inv.to_dict(), d)
	assert_type(inv.items[0]["n"], TYPE_INT)
