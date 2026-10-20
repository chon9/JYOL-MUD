extends "res://tests/test_case.gd"
## Protocol（M1_PLAN 3.5.5、3.6）：每個 intent 的型別與範圍驗證。純邏輯，不需要其他 WP。

func _v(kind: String, args: Dictionary) -> String:
	return Protocol.validate_args(kind, args)

func test_every_contract_intent_is_known() -> void:
	for kind in ["ping", "chat", "char_list", "char_roll", "char_create", "char_select", "char_delete", "look",
			"move", "travel", "talk", "shop_list", "buy", "sell", "learn_list", "learn", "self_study", "join_sect",
			"inn_rest", "set_respawn", "meal", "fight", "use_item", "equip", "unequip", "drop_item", "meditate",
			"exert", "work", "quest_accept", "quest_turn_in", "quest_abandon", "loot_corpse", "battle_cmd"]:
		assert_true(Protocol.is_known(kind), kind)
	assert_eq(Protocol.INTENT_SCHEMA.size(), 34 + 21 + 2 + 5 + 6 + 21 + 3,
		"M1 的 34 個 + M2_PLAN 4.1 的 21 個 + 查看偵察的 2 個 + M3A_PLAN 6.12 的 5 個 + STORY_PLAN §4.14 的 6 個 + M3B_PLAN §6 的 21 個 + M3C_PLAN §8 的 3 個，沒有多的")
	assert_eq(Protocol.I_CHAR_CREATE, "char_create")
	assert_eq(Protocol.I_BATTLE_CMD, "battle_cmd")
	assert_eq(Protocol.I_QUEST_TURN_IN, "quest_turn_in")

func test_no_arg_intents() -> void:
	for kind in ["char_list", "char_roll", "look", "meditate"]:
		assert_eq(_v(kind, {}), "", kind)
		assert_eq(_v(kind, { "x": 1 }), "unexpected_arg", kind)

func test_char_create() -> void:
	var good := { "name": "測試俠客", "gender": "M", "birth_month": 3, "birth_city": "xixia", "alloc": { "wit": 5 } }
	assert_eq(_v("char_create", good), "")
	var a := good.duplicate()
	a["gender"] = "X"
	assert_eq(_v("char_create", a), "bad_value:gender")
	for m in [0, 13, -1]:
		a = good.duplicate()
		a["birth_month"] = m
		assert_eq(_v("char_create", a), "bad_value:birth_month", str(m))
	for m in [1, 12]:
		a = good.duplicate()
		a["birth_month"] = m
		assert_eq(_v("char_create", a), "", str(m))
	a = good.duplicate()
	a["birth_month"] = 3.0
	assert_eq(_v("char_create", a), "bad_type:birth_month")
	a = good.duplicate()
	a["alloc"] = [5]
	assert_eq(_v("char_create", a), "bad_type:alloc")
	a = good.duplicate()
	a.erase("birth_city")
	assert_eq(_v("char_create", a), "missing_arg:birth_city")
	a = good.duplicate()
	a["birth_city"] = "jingcheng"
	assert_eq(_v("char_create", a), "", "birth_city is checked by the handler, not Protocol")
	a = good.duplicate()
	a["name"] = "x".repeat(65)
	assert_eq(_v("char_create", a), "bad_value:name")

func test_string_length_limit() -> void:
	assert_eq(_v("talk", { "npc": "n".repeat(64) }), "")
	assert_eq(_v("talk", { "npc": "n".repeat(65) }), "bad_value:npc")
	assert_eq(_v("char_delete", { "char_id": "ch_1", "confirm_name": "x".repeat(65) }), "bad_value:confirm_name")
	# 千里傳音的內文沿用 M0 的 200 字上限
	assert_eq(_v("chat", { "text": "x".repeat(150) }), "")

func test_move_dirs() -> void:
	for d in ["N", "S", "E", "W", "NE", "NW", "SE", "SW", "U", "D", "IN", "OUT"]:
		assert_eq(_v("move", { "dir": d }), "", d)
	assert_eq(_v("move", { "dir": "north" }), "bad_value:dir")
	assert_eq(_v("move", { "dir": "n" }), "bad_value:dir")
	assert_eq(_v("move", {}), "missing_arg:dir")

func test_counts_and_times() -> void:
	assert_eq(_v("buy", { "npc": "a", "item": "b" }), "")
	assert_eq(_v("buy", { "npc": "a", "item": "b", "n": 99 }), "")
	assert_eq(_v("buy", { "npc": "a", "item": "b", "n": 100 }), "bad_value:n")
	assert_eq(_v("buy", { "npc": "a", "item": "b", "n": 0 }), "bad_value:n")
	assert_eq(_v("sell", { "npc": "a", "item_uid": "it_1", "n": 99 }), "")
	assert_eq(_v("sell", { "npc": "a", "item_uid": "it_1", "n": 100 }), "bad_value:n")
	assert_eq(_v("learn", { "npc": "a", "skill": "b", "times": 10 }), "")
	assert_eq(_v("learn", { "npc": "a", "skill": "b", "times": 11 }), "bad_value:times")
	assert_eq(_v("learn", { "npc": "a", "skill": "b", "times": 0 }), "bad_value:times")
	assert_eq(_v("self_study", { "skill": "b", "times": 11 }), "bad_value:times")
	assert_eq(_v("self_study", { "skill": "b" }), "")
	assert_eq(_v("drop_item", { "item_uid": "it_1", "n": 999 }), "")
	assert_eq(_v("drop_item", { "item_uid": "it_1", "n": 1000 }), "bad_value:n")
	assert_eq(_v("drop_item", { "item_uid": "it_1", "n": "1" }), "bad_type:n")

func test_enums() -> void:
	assert_eq(_v("unequip", { "slot": "WEAPON" }), "")
	assert_eq(_v("unequip", { "slot": "ARMOR" }), "")
	assert_eq(_v("unequip", { "slot": "HAT" }), "bad_value:slot")
	for st in ["jing", "qi", "shen"]:
		assert_eq(_v("exert", { "stat": st }), "", st)
	assert_eq(_v("exert", { "stat": "neili" }), "bad_value:stat")
	for sk in ["life_farming", "life_woodcut", "life_fishing", "life_cooking"]:
		assert_eq(_v("work", { "skill": sk }), "", sk)
	assert_eq(_v("work", { "skill": "life_cooking", "recipe": "rc_baifan" }), "")
	assert_eq(_v("work", { "skill": "basic_fist" }), "bad_value:skill")

func test_npc_intents_need_npc() -> void:
	for kind in ["talk", "shop_list", "learn_list", "join_sect", "inn_rest", "set_respawn", "meal", "fight"]:
		assert_eq(_v(kind, { "npc": "n_x" }), "", kind)
		assert_eq(_v(kind, {}), "missing_arg:npc", kind)
		assert_eq(_v(kind, { "npc": 3 }), "bad_type:npc", kind)
	assert_eq(_v("travel", { "npc": "n", "dest": "jc_station" }), "")
	assert_eq(_v("travel", { "npc": "n" }), "missing_arg:dest")
	assert_eq(_v("quest_accept", { "npc": "n", "quest": "q" }), "")
	assert_eq(_v("quest_turn_in", { "npc": "n" }), "missing_arg:quest")
	assert_eq(_v("quest_abandon", { "quest": "q" }), "")
	assert_eq(_v("loot_corpse", { "corpse_id": "cp_00000000" }), "")
	assert_eq(_v("use_item", { "item_uid": "it_1" }), "")
	assert_eq(_v("equip", {}), "missing_arg:item_uid")

func test_battle_cmd() -> void:
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "DEFEND" }), "")
	for c in ["MOVE", "ATTACK", "ART", "DEFEND", "REST", "EQUIP", "FLEE"]:
		assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": c }), "", c)
	# M3A_PLAN 5.1：毒醫暗陣內穴＋用藥加入指令集合
	for c in ["POISON", "MEDIC", "HIDDEN", "FORMATION", "INNER", "ACUPOINT", "ITEM"]:
		assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": c }), "", c)
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "LIGHTNESS" }), "bad_value:cmd")
	assert_eq(_v("battle_cmd", { "cmd": "DEFEND" }), "missing_arg:battle_id")
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "MOVE", "target": [0, 0] }), "")
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "MOVE", "target": [11, 7] }), "")
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "MOVE", "target": [12, 0] }), "bad_value:target")
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "MOVE", "target": [0, 8] }), "bad_value:target")
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "MOVE", "target": [-1, 0] }), "bad_value:target")
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "MOVE", "target": [1] }), "bad_value:target")
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "MOVE", "target": [1.0, 2.0] }), "bad_value:target")
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "MOVE", "target": "1,2" }), "bad_type:target")
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "ART", "art": "a", "move": "m", "power_tenths": 10,
		"target": [2, 3] }), "")
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "ART", "power_tenths": 0 }), "bad_value:power_tenths")
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "ART", "power_tenths": 11 }), "bad_value:power_tenths")
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "EQUIP", "item_uid": "" }), "")

func test_m0_chat_behaviour_kept() -> void:
	assert_eq(_v("chat", { "text": "   " }), "empty_text")
	assert_eq(_v("chat", { "text": "x".repeat(Protocol.CHAT_MAX_LEN + 1) }), "text_too_long")
	assert_eq(_v("chat", { "text": "a", "ch": "CHAT_NOPE" }), "bad_channel")   # M2：GM 成為合法頻道
	assert_eq(_v("teleport", {}), "unknown_intent")

func test_event_key_constants() -> void:
	assert_eq(Protocol.E_CHAR_ROLLED, "char_rolled")
	assert_eq(Protocol.E_NPC_MENU, "npc_menu")
	assert_eq(Protocol.E_BATTLE_PROC_DEFENSE, "battle_proc_DEFENSE")
	assert_eq(Protocol.E_DEATH_STANDARD_SAFE, "death_standard_safe")
	assert_eq(Protocol.E_CORPSE_EXPIRED, "corpse_expired")
	assert_eq(Protocol.CH_SCENE, "SCENE")
	assert_eq(Protocol.CH_BATTLE, "BATTLE")
