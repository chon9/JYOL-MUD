extends "res://tests/test_case.gd"
## M3C_PLAN §6.3（WP-LOOT）：8 個裝備欄、舊存檔 2 鍵相容、fix_slots、legacy 輸出不變、armor_power 加總、bonus、性別條件、
## 角色表的打寶欄位、keep_on_death。

const F := preload("res://tests/unit/test_character_fixtures.gd")

var t: Dictionary

static func loot_items() -> Array:
	return [
		{ "id": "a_hat", "name": "帽子", "tab": "ARMOR", "slot": "HEAD", "atk": 0, "def": 4, "weight": 2, "price": 180, "stack": 1,
		  "spoil_days": 0, "effects": [], "official": { "atk": 0, "def": 20, "weight": 4 } },
		{ "id": "a_hat2", "name": "斗笠", "tab": "ARMOR", "slot": "HEAD", "atk": 0, "def": 1, "weight": 21, "price": 30, "stack": 1,
		  "spoil_days": 0, "effects": [] },
		{ "id": "a_ring", "name": "紅石戒", "tab": "ARMOR", "slot": "RING", "atk": 0, "def": 3, "weight": 1, "price": 2400, "stack": 1,
		  "spoil_days": 0, "effects": [], "rarity": "TREASURE", "bonus": { "cal": 5, "bogus": 9 } },
		{ "id": "a_neck", "name": "金鍊子", "tab": "ARMOR", "slot": "NECK", "atk": 0, "def": 2, "weight": 5, "price": 80, "stack": 1,
		  "spoil_days": 0, "effects": [] },
		{ "id": "a_wrist", "name": "鐵項護手", "tab": "ARMOR", "slot": "WRIST", "atk": 0, "def": 4, "weight": 2, "price": 180, "stack": 1,
		  "spoil_days": 0, "effects": [] },
		{ "id": "a_cloak", "name": "綠石披風", "tab": "ARMOR", "slot": "CLOAK", "atk": 0, "def": 4, "weight": 8, "price": 280, "stack": 1,
		  "spoil_days": 0, "effects": [], "bonus": { "cal": 2 } },
		{ "id": "a_boots", "name": "皮靴", "tab": "ARMOR", "slot": "BOOTS", "atk": 0, "def": 1, "weight": 8, "price": 30, "stack": 1,
		  "spoil_days": 0, "effects": [] },
		{ "id": "a_yushang", "name": "羽裳", "tab": "ARMOR", "slot": "ARMOR", "atk": 0, "def": 3, "weight": 4, "price": 389, "stack": 1,
		  "spoil_days": 0, "effects": [], "requires": [{ "type": "gender", "value": "F" }] },
		{ "id": "w_sb_test", "name": "倚天劍", "tab": "WEAPON", "slot": "WEAPON", "weapon_type": "SWORD", "atk": 80, "def": 0, "weight": 23,
		  "price": 421053, "stack": 1, "spoil_days": 0, "effects": [], "rarity": "DIVINE", "divine": true, "unique_world": true,
		  "no_sell": true, "no_drop": true, "keep_on_death": true, "bankable": false },
		{ "id": "w_fem", "name": "女劍", "tab": "WEAPON", "slot": "WEAPON", "weapon_type": "SWORD", "atk": 9, "def": 0, "weight": 2,
		  "price": 1, "stack": 1, "spoil_days": 0, "effects": [], "requires": [{ "type": "gender", "value": "F" }] },
	]

func before_each() -> void:
	t = F.tables()
	for r in loot_items():
		t["items"][r["id"]] = r

func _add(c: Character, id: String) -> String:
	var r := c.inventory.add(id, 1, t, 0.0, -1, F.uid_maker("it_x" + id.substr(0, 3)))
	assert_true(r["ok"], "add " + id)
	return String(r["uid"])

func test_eight_slots_default_and_protocol_match() -> void:
	var inv := Inventory.new()
	assert_eq(inv.equipped.keys(), Inventory.SLOTS)
	assert_eq(Inventory.SLOTS, ["WEAPON", "ARMOR", "HEAD", "NECK", "WRIST", "CLOAK", "RING", "BOOTS"])
	assert_eq(Inventory.SLOTS, Protocol.SLOTS, "core 與協定的裝備欄相同（§8）")
	for slot in Inventory.SLOTS:
		assert_eq(inv.equipped[slot], "")

func test_old_save_two_keys_loads_eight() -> void:
	var inv := Inventory.from_dict({ "items": [
		{ "uid": "it_w", "id": "w_mudao", "n": 1, "born_s": 0.0 },
		{ "uid": "it_a", "id": "a_bupao", "n": 1, "born_s": 0.0 },
	], "equipped": { "WEAPON": "it_w", "ARMOR": "it_a" } })
	assert_eq(inv.equipped.size(), 8)
	assert_eq(inv.equipped["WEAPON"], "it_w")
	assert_eq(inv.equipped["ARMOR"], "it_a")
	assert_eq(inv.equipped["HEAD"], "")
	var back := Inventory.from_dict(inv.to_dict())
	assert_eq(back.equipped, inv.equipped, "存讀往返")

func test_legacy_output_unchanged() -> void:
	var inv := Inventory.from_dict({ "items": [
		{ "uid": "it_w", "id": "w_mudao", "n": 1, "born_s": 3.0 },
		{ "uid": "it_h", "id": "a_hat", "n": 1, "born_s": 4.0 },
	], "equipped": { "WEAPON": "it_w", "HEAD": "it_h" } })
	var legacy := inv.to_dict(true)
	# 逐位元組與 M3c 以前相同：只有 WEAPON、ARMOR 兩格，物品沒有 lots
	assert_eq(JSON.stringify(legacy), JSON.stringify({ "items": [
		{ "uid": "it_w", "id": "w_mudao", "n": 1, "born_s": 3.0 },
		{ "uid": "it_h", "id": "a_hat", "n": 1, "born_s": 4.0 } ],
		"equipped": { "WEAPON": "it_w", "ARMOR": "" } }))
	var full := inv.to_dict()
	assert_eq(full["equipped"].keys(), Inventory.SLOTS, "legacy == false：8 個鍵")
	assert_eq(full["equipped"]["HEAD"], "it_h")

func test_fix_slots_moves_hat_from_armor() -> void:
	# 舊存檔：兔皮帽／斗笠以前只能放 ARMOR 欄
	var inv := Inventory.from_dict({ "items": [
		{ "uid": "it_h", "id": "a_hat", "n": 1, "born_s": 0.0 },
	], "equipped": { "ARMOR": "it_h" } })
	assert_true(inv.fix_slots(t), "有搬動")
	assert_eq(inv.equipped["ARMOR"], "")
	assert_eq(inv.equipped["HEAD"], "it_h")
	assert_false(inv.fix_slots(t), "第二次沒有變動")
	# 目的欄已有東西 → 放錯的那件卸下（留在背包）
	var inv2 := Inventory.from_dict({ "items": [
		{ "uid": "it_h", "id": "a_hat", "n": 1, "born_s": 0.0 },
		{ "uid": "it_d", "id": "a_hat2", "n": 1, "born_s": 0.0 },
	], "equipped": { "ARMOR": "it_d", "HEAD": "it_h" } })
	assert_true(inv2.consolidate(t), "consolidate 一併呼叫 fix_slots（與 consolidate 同一個呼叫點）")
	assert_eq(inv2.equipped["HEAD"], "it_h")
	assert_eq(inv2.equipped["ARMOR"], "")
	assert_false(inv2.find("it_d").is_empty(), "卸下的留在背包")

func test_armor_power_sums_seven_slots_and_bonus() -> void:
	var c := F.new_char()
	var before := int(c.derived(t, F.options())["armor_power"])
	assert_eq(before, 2, "新手布衣 2")
	for id in ["a_hat", "a_ring", "a_neck", "a_wrist", "a_cloak", "a_boots"]:
		var r := c.inventory.equip(_add(c, id), t, c)
		assert_true(r["ok"], "equip " + id)
	var d := c.derived(t, F.options())
	assert_eq(int(d["armor_power"]), 2 + 4 + 3 + 2 + 4 + 4 + 1, "7 個防具欄的 def 加總")
	assert_eq(int(d["attrs"]["cal"]), 19 + 5 + 2, "bonus 定力 +5 +2（不認得的鍵不加）")
	assert_eq(int(d["weapon_power"]), 4, "武器欄不算防禦")
	assert_eq(DerivedStats.armor_power(c.inventory, t), int(d["armor_power"]))

func test_gender_requirement() -> void:
	var c := F.new_char()   # 男
	var u := _add(c, "a_yushang")
	var r := c.inventory.equip(u, t, c, F.options(), F.rules())
	assert_eq(r["reason"], "req_gender", "男角不能穿羽裳")
	assert_eq(c.inventory.slot_of(u), "")
	# 沒給角色（舊呼叫點）時不檢查
	assert_true(c.inventory.equip(u, t)["ok"])
	c.inventory.unequip("ARMOR")
	c.gender = "F"
	assert_true(c.inventory.equip(u, t, c)["ok"], "女角可以")
	# 戰鬥中可換的兵器只列條件合格的
	c.gender = "M"
	_add(c, "w_fem")
	var opts: Array = c.to_combatant(t, F.options(), 0, 1)["weapon_options"]
	assert_false(opts.any(func(w): return w["item_id"] == "w_fem"), "限女的兵器不在男角的戰鬥換兵器清單")

func test_sheet_loot_fields() -> void:
	var c := F.new_char()
	var ur := _add(c, "a_ring")
	_add(c, "a_yushang")
	c.inventory.equip(ur, t, c)
	var sh := c.to_sheet(t, F.options(), F.rules())
	assert_eq(sh["equipped"].keys(), Inventory.SLOTS, "角色表 equipped 8 鍵")
	assert_eq(sh["equipped"]["RING"], ur)
	var by := {}
	for it in sh["inventory"]:
		by[it["id"]] = it
	assert_eq(by["a_ring"]["rarity"], "TREASURE")
	assert_eq(by["a_ring"]["slot"], "RING")
	assert_eq(by["a_ring"]["bonus"], { "cal": 5, "bogus": 9 })
	assert_true(by["a_ring"]["req_ok"])
	assert_false(by["a_yushang"]["req_ok"], "性別不合")
	assert_eq(by["a_yushang"]["req_text"], "限女性")
	assert_eq(by["w_mudao"]["rarity"], "COMMON", "沒有 rarity 欄＝凡品")
	assert_false(by["w_mudao"].has("official"))
	assert_true(by["a_bupao"]["equippable"])

func test_keep_on_death_items_stay() -> void:
	var c := F.new_char()
	c.combat_xp = 5000
	var u := _add(c, "w_sb_test")
	c.inventory.equip(u, t, c)
	var r := DeathPenalty.apply(c, F.rules(), t)
	assert_false(r["dropped"].any(func(it): return it["id"] == "w_sb_test"), "STANDARD：神兵不掉")
	assert_eq(c.inventory.equipped["WEAPON"], u, "仍裝備著")
	var r2 := DeathPenalty.apply(c, F.rules("classic_strict"), t)
	assert_false(r2["dropped"].any(func(it): return it["id"] == "w_sb_test"), "STRICT：全部掉，神兵除外")
	assert_eq(c.inventory.count("w_sb_test"), 1)
	assert_eq(c.inventory.items.size(), 1, "其他東西都掉了")
	# 沒給 tables（舊呼叫）＝照舊全部拿走
	assert_eq(c.inventory.take_all().size(), 1)
