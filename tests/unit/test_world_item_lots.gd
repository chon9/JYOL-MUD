extends "res://tests/unit/test_world_fixture.gd"
## 物品堆疊（2026-10，lots 改版）整合：走真正的 intent 路徑檢查每一條物品進出——
## 跨天取得同一疊、只壞過期的批、賣出／交任務從最舊的批扣、死亡掉屍體保留 lots、撿回合併、
## 舊存檔（沒有 lots、被 60 秒合併窗拆開）進入世界時合併。

func before_each() -> void:
	world_name = "w_item_lots"
	super.before_each()

func _adv_days(d: float) -> void:
	ws.world["world_time_s"] = ws.world_time() + d * float(ws.options.get("game_day_real_s", 7200))

func _stacks(iid: String) -> Array:
	var out: Array = []
	for it in ch().inventory.items:
		if str(it["id"]) == iid:
			out.append(it)
	return out

func test_lots_through_every_path() -> void:
	if not game_ok():
		return
	make_char("堆疊測試")
	# 五天、五場戰鬥的掉落（give_item ＝ 戰鬥掉落入帳的同一個入口）
	for i in 5:
		give("r_bigrabbitskin", 1)
		give("r_rabbitskin", 2)
		_adv_days(1.0)
	assert_eq(_stacks("r_bigrabbitskin").size(), 1, "大兔皮一格")
	assert_eq(_stacks("r_rabbitskin").size(), 1, "兔皮一格")
	assert_eq(_stacks("r_rabbitskin")[0]["lots"].size(), 5, "五批")
	# sheet 的新鮮度＝最早一批
	host().push_sheet(s())
	ws.flush()
	var seen := false
	for it in sheet().get("inventory", []):
		if str(it.get("id", "")) == "r_rabbitskin":
			seen = true
			assert_true(bool(it.get("perishable", false)), "perishable")
			assert_true(absf(float(it.get("spoil_left_days", -1.0)) - 25.0) < 0.01, "最早一批剩 25 天: %s" % str(it))
	assert_true(seen, "sheet lists 兔皮")
	# 腐壞：只有第一天那批過期
	_adv_days(25.5)
	host()._minute_jobs()
	ws.flush()
	assert_eq(item_count("r_rabbitskin"), 8, "只壞最舊那批")
	assert_eq(item_count("r_bigrabbitskin"), 4)
	assert_eq(_stacks("r_rabbitskin").size(), 1)
	assert_false(lastp("item_spoiled").is_empty(), "spoil notice")
	# 賣 1：從最舊的批扣
	goto("xx_inn")
	var before: Array = _stacks("r_rabbitskin")[0]["lots"].duplicate(true)
	ok("sell", { "npc": "n_xx_innkeeper", "item_uid": first_uid("r_rabbitskin"), "n": 1 })
	var after: Array = _stacks("r_rabbitskin")[0]["lots"]
	assert_eq(item_count("r_rabbitskin"), 7)
	assert_eq(int(after[0]["n"]), int(before[0]["n"]) - 1, "賣最舊的")
	assert_eq(float(after[0]["born_s"]), float(before[0]["born_s"]))
	# 交任務：最舊的大兔皮
	goto("xx_square")
	ok("quest_accept", { "npc": "n_wujieshan", "quest": "q_rabbit" })
	var bl: Array = _stacks("r_bigrabbitskin")[0]["lots"].duplicate(true)
	ok("quest_turn_in", { "npc": "n_wujieshan", "quest": "q_rabbit" })
	assert_eq(item_count("r_bigrabbitskin"), 3)
	assert_eq(float(_stacks("r_bigrabbitskin")[0]["lots"][0]["born_s"]), float(bl[1]["born_s"]), "交出最舊的")
	# 很久之後拿到的新皮照樣併進同一格
	give("r_rabbitskin", 3)
	assert_eq(_stacks("r_rabbitskin").size(), 1)
	var lots_before_death: Array = _stacks("r_rabbitskin")[0]["lots"].duplicate(true)
	# 死亡（STRICT_2001 整個背包掉在屍體上）→ 屍體保留 lots → 撿回併進現有的那格
	use_preset("classic_strict")
	ch().inventory.remove_item_id("c_jingyao", item_count("c_jingyao"))
	goto("gw_throne")
	ch().vitals["qi"] = 2
	ok("fight", { "npc": "n_guiwang" })
	assert_eq(drive_battle("defend", 600.0).get("you_died", false), true, "died")
	assert_eq(item_count("r_rabbitskin"), 0, "dropped")
	var corpses: Array = ws.world.get("corpses", [])
	assert_eq(corpses.size(), 1)
	var on_corpse: Dictionary = {}
	for it in corpses[0]["items"]:
		if str(it["id"]) == "r_rabbitskin":
			on_corpse = it
	assert_eq(on_corpse.get("lots", []), lots_before_death, "屍體上保留每一批")
	give("r_rabbitskin", 1)
	goto("gw_throne")
	ok("loot_corpse", { "corpse_id": str(corpses[0]["id"]) })
	assert_eq(_stacks("r_rabbitskin").size(), 1, "撿回後併成一格")
	assert_eq(item_count("r_rabbitskin"), 11)
	assert_eq(float(_stacks("r_rabbitskin")[0]["lots"][0]["born_s"]), float(lots_before_death[0]["born_s"]), "腐壞時間不變")
	# 舊存檔：沒有 lots、同物品被拆成好幾格（含超過上限 50 的兔皮）
	var cid_ := str(ch().id)
	var d: Dictionary = ch().to_dict()
	var t: float = ws.world_time()
	d["inventory"]["items"] = [
		{ "uid": "it_old1", "id": "r_rabbitskin", "n": 30, "born_s": t - 100.0 },
		{ "uid": "it_old2", "id": "r_rabbitskin", "n": 30, "born_s": t - 50.0 },
		{ "uid": "it_old3", "id": "r_wood", "n": 4, "born_s": t - 10.0 },
		{ "uid": "it_old4", "id": "r_wood", "n": 5, "born_s": t - 5.0 },
		{ "uid": "it_old5", "id": "w_mudao", "n": 1, "born_s": t },
	]
	d["inventory"]["equipped"] = { "WEAPON": "it_old5", "ARMOR": "" }
	restart_world()
	assert_eq(SaveManager.save_character(host().char_store._world_id(), str(d["identity"]), d), OK, "write legacy")
	ok("char_select", { "char_id": cid_ })
	var rs := _stacks("r_rabbitskin")
	assert_eq(rs.size(), 2, "60 張 → 50 + 10")
	assert_eq(int(rs[0]["n"]), 50)
	assert_eq(int(rs[1]["n"]), 10)
	assert_true(absf(float(rs[0]["lots"][0]["born_s"]) - (t - 100.0)) < 0.01, "最舊的在前面那格")
	assert_true(absf(float(rs[1]["lots"][0]["born_s"]) - (t - 50.0)) < 0.01, "較新的在後面那格")
	assert_eq(_stacks("r_wood").size(), 1)
	assert_eq(_stacks("r_wood")[0]["lots"].size(), 1, "不會腐壞的只留一批")
	assert_eq(str(ch().inventory.equipped["WEAPON"]), "it_old5", "裝備不動")
