extends "res://tests/unit/test_world_fixture.gd"
## 6.2 死亡規則矩陣（整合）：classic_strict／classic_standard／later_official／friends_casual × 老手／新手
## 角色氣設為 2，與鬼王（fight）開戰並以 DEFEND 撐到死亡。

func before_each() -> void:
	world_name = "w_death"
	super.before_each()

## 6.2 的固定角色。veteran：實戰 2000；否則 300
func _setup(veteran: bool, respawn_room := "") -> void:
	make_char("死亡測試")
	var c = ch()
	c.combat_xp = 2000 if veteran else 300
	c.sect = "shaolin"
	c.skills.set_level("sl_changquan", 20, tables())
	c.skills.set_level("sl_luohanquan", 15, tables())
	c.skills.set_level("basic_inner", 10, tables())
	c.skills.set_level("foxa", 12, tables())
	c.skills.set_level("life_farming", 5, tables())
	# 背包：精藥水 ×3（初始 5 → 3）、大兔皮 ×1；裝備木刀、布衣（初始）
	c.inventory.remove_item_id("c_jingyao", 2)
	give("r_bigrabbitskin")
	c.money = 1000
	if respawn_room != "":
		c.respawn = { "region": host().index.region_of(respawn_room), "room": respawn_room }
	goto("gw_throne")

func _die() -> Dictionary:
	ch().vitals["qi"] = 2
	ok("fight", { "npc": "n_guiwang" })
	var res := drive_battle("defend", 600.0)
	assert_eq(res.get("you_died", false), true, "died: %s" % str(res))
	return res

func _corpses() -> Array:
	return ws.world.get("corpses", [])

func _common_after_death(res: Dictionary, expect_room: String) -> void:
	assert_eq(str(ch().location["room"]), expect_room, "respawn room")
	var d: Dictionary = ch().derived(tables(), ws.options)
	assert_eq(int(ch().vitals["neili"]), 0)
	assert_eq(int(ch().vitals["qi"]), maxi(1, floori(int(d["qi_max"]) * 0.5)))
	assert_eq(int(ch().vitals["jing"]), maxi(1, floori(int(d["jing_max"]) * 0.5)))
	assert_eq(int(ch().dead_count), 1)
	assert_eq(lastp("respawn").get("room_name", ""), host().room_name(expect_room))
	assert_eq(res.get("result", ""), "DEFEAT")
	assert_eq(str(res["death"].get("respawn_room_name", "")), host().room_name(expect_room))
	assert_eq(view()["room"], expect_room)

func test_strict_veteran() -> void:
	if not game_ok():
		return
	use_preset("classic_strict")
	_setup(true, "xx_gate_e")
	var res := _die()
	var c = ch()
	assert_eq(int(c.skills.level("sl_changquan")), 19)
	assert_eq(int(c.skills.level("sl_luohanquan")), 14)
	assert_eq(int(c.skills.level("basic_inner")), 9)
	assert_eq(int(c.skills.level("foxa")), 11)
	assert_eq(int(c.skills.level("life_farming")), 5)
	assert_eq(c.inventory.items.size(), 0, "everything on the corpse")
	assert_eq(int(c.money), 1000)
	assert_eq(_corpses().size(), 1)
	assert_eq(str(_corpses()[0]["room"]), "gw_throne")
	assert_false(last("death_strict").is_empty())
	_common_after_death(res, "xx_gate_e")

func test_strict_newbie_has_no_protection() -> void:
	if not game_ok():
		return
	use_preset("classic_strict")
	_setup(false)
	var res := _die()
	assert_eq(int(ch().skills.level("sl_changquan")), 19)
	assert_eq(ch().inventory.items.size(), 0)
	assert_false(last("death_strict").is_empty())
	_common_after_death(res, "xx_square")   # 沒設記錄點 → 出生房間

func test_standard_veteran_and_loot_back() -> void:
	if not game_ok():
		return
	use_preset("classic_standard")
	_setup(true, "xx_gate_e")
	var res := _die()
	var c = ch()
	assert_eq(int(c.skills.level("sl_changquan")), 19)
	assert_eq(int(c.skills.level("sl_luohanquan")), 15)
	assert_eq(int(c.skills.level("basic_inner")), 10)
	assert_eq(int(c.skills.level("foxa")), 12)
	assert_eq(item_count("w_mudao"), 0)
	assert_eq(item_count("a_bupao"), 0)
	assert_eq(item_count("c_jingyao"), 3, "backpack kept")
	assert_eq(item_count("r_bigrabbitskin"), 1)
	assert_eq(int(c.money), 1000)
	assert_eq(_corpses().size(), 1)
	assert_eq(str(_corpses()[0]["window"]), "CLASSIC_30")
	assert_false(last("death_standard").is_empty())
	_common_after_death(res, "xx_gate_e")
	# 本人回去撿
	var cid := str(_corpses()[0]["id"])
	assert_eq(reason("loot_corpse", { "corpse_id": cid }), "corpse_not_found", "not in this room")
	goto("gw_throne")
	var mine := false
	for cp in view()["corpses"]:
		if cp["id"] == cid:
			mine = cp["mine"]
	assert_true(mine, "view lists my corpse")
	ok("loot_corpse", { "corpse_id": cid })
	assert_eq(item_count("w_mudao"), 1)
	assert_eq(item_count("a_bupao"), 1)
	assert_eq(int(lastp("corpse_looted").get("n_items", 0)), 2)
	assert_eq(_corpses().size(), 0, "empty corpse removed")

## 斷線不能逃過死亡：戰鬥不中止，自動防守打到分出勝負，照樣降級、掉屍體、回記錄點，且屍體立即存進 world
func test_disconnect_mid_battle_still_dies() -> void:
	if not game_ok():
		return
	use_preset("classic_standard")
	_setup(true, "xx_gate_e")
	var c = ch()
	c.vitals["qi"] = 2
	ok("fight", { "npc": "n_guiwang" })
	assert_true(s().battle_id != 0)
	host().on_session_removed(s())
	assert_true(host().battles.active.is_empty(), "battle resolved, not left hanging")
	assert_eq(int(c.dead_count), 1, "died despite disconnect")
	assert_eq(int(c.skills.level("sl_changquan")), 19)
	assert_eq(str(c.location["room"]), "xx_gate_e", "moved to respawn room")
	assert_eq(_corpses().size(), 1)
	var saved: Dictionary = sm.load_world(ws.world_id).get("data", {})
	if not saved.is_empty():
		assert_eq((saved.get("corpses", []) as Array).size(), 1, "corpse persisted to world.json immediately")

## M2 審查：死者不在 sessions()（斷線、自動防）時，handle_death 要在寫 world.json（屍體）之前先寫死者的角色檔；
## 否則兩次寫入之間當機，物品會同時在屍體和舊角色檔裡
func test_death_writes_char_file_before_world_for_detached_char() -> void:
	if not game_ok():
		return
	use_preset("classic_standard")
	_setup(true, "xx_gate_e")
	var cid := str(ch().id)
	make_char("旁觀者")   # 換角：死亡測試存檔、離開 sessions()
	var c = host().char_store.load_char(s().identity, cid)
	assert_true(c != null and host().session_for_char(cid) == null, "detached char")
	var before_items := int(c.inventory.count("w_mudao"))
	assert_true(before_items > 0, "has item to drop")
	host().battles.handle_death(null, c, "gw_throne")
	assert_eq(_corpses().size(), 1, "corpse created")
	var r: Dictionary = sm.load_character(ws.world_id, s().identity, cid)
	assert_true(r.get("ok", false), "char file readable")
	var on_disk = Character.from_dict(r["data"])
	assert_eq(int(on_disk.inventory.count("w_mudao")), 0, "dropped weapon already gone from char file")
	assert_eq(int(on_disk.inventory.count("r_bigrabbitskin")), 1, "backpack kept")
	assert_eq(int(on_disk.dead_count), 1, "death written")

func test_standard_newbie_safe() -> void:
	if not game_ok():
		return
	use_preset("classic_standard")
	_setup(false)
	var res := _die()
	assert_eq(int(ch().skills.level("sl_changquan")), 20)
	assert_eq(item_count("w_mudao"), 1)
	assert_eq(item_count("c_jingyao"), 3)
	assert_eq(_corpses().size(), 0)
	assert_false(last("death_standard_safe").is_empty())
	_common_after_death(res, "xx_square")

func test_later_official_veteran() -> void:
	if not game_ok():
		return
	use_preset("later_official")
	_setup(true)
	var res := _die()
	assert_eq(int(ch().skills.level("sl_changquan")), 19)
	assert_eq(int(ch().skills.level("sl_luohanquan")), 15)
	assert_eq(item_count("w_mudao"), 0)
	assert_eq(item_count("c_jingyao"), 3)
	assert_eq(_corpses().size(), 1)
	assert_eq(str(_corpses()[0]["window"]), "LATER_10")
	_common_after_death(res, "xx_square")

func test_casual_veteran() -> void:
	if not game_ok():
		return
	use_preset("friends_casual")
	_setup(true)
	var res := _die()
	assert_eq(int(ch().skills.level("sl_changquan")), 20)
	assert_eq(item_count("w_mudao"), 1)
	assert_eq(int(ch().money), 900)
	assert_eq(_corpses().size(), 0)
	assert_eq(int(lastp("death_casual").get("money_lost", 0)), 100)
	assert_eq(int(res["death"].get("money_lost", 0)), 100)
	_common_after_death(res, "xx_square")

func test_corpse_expires_after_1800s() -> void:
	if not game_ok():
		return
	use_preset("classic_strict")
	_setup(true)
	_die()
	assert_eq(_corpses().size(), 1)
	var other := "ch_someone1"
	assert_true(str(_corpses()[0]["char_id"]) != other)
	clear_events()
	ws.advance(1700.0)
	assert_eq(_corpses().size(), 1, "still there at ~1700 s")
	ws.advance(200.0)
	assert_eq(_corpses().size(), 0, "gone after 1800 s")
	assert_false(last("corpse_expired").is_empty())

## M2：保護期（600 秒）內只有本人與授權者可撿（corpse_protected）；之後公開，誰都能撿（M2_PLAN 5.3）
func test_only_owner_can_loot_while_protected() -> void:
	if not game_ok():
		return
	use_preset("classic_strict")
	_setup(true)
	_die()
	var cid := str(_corpses()[0]["id"])
	_corpses()[0]["char_id"] = "ch_otherone"
	goto("gw_throne")
	assert_eq(reason("loot_corpse", { "corpse_id": cid }), "corpse_protected")
	assert_eq(reason("loot_corpse", { "corpse_id": "cp_nothing" }), "corpse_not_found")
	var mine := true
	for cp in view()["corpses"]:
		if cp["id"] == cid:
			mine = cp["mine"]
			assert_eq(cp.get("can_loot", true), false, "view: cannot loot yet")
	assert_false(mine, "not mine any more")
	_corpses()[0]["created_s"] = ws.world_time() - 600.0   # 撥到公開期
	ok("loot_corpse", { "corpse_id": cid })
	assert_eq(item_count("w_mudao"), 1, "public corpse: anyone can loot")
