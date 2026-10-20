extends "res://tests/unit/test_world_fixture.gd"
## 4 種生活技能：學習（拿到工具）、no_feature、no_tool、冷卻、產出、廚師食譜（M1_PLAN 6.1 test_world_life）

func before_each() -> void:
	world_name = "w_life"
	super.before_each()

## 反覆工作直到拿到 n 個 item（每次等冷卻）；回傳成功次數
func _work_until(skill: String, item: String, n: int, recipe := "", max_tries := 60) -> int:
	var tries := 0
	while item_count(item) < n and tries < max_tries:
		tries += 1
		Survival.rest_full(ch(), tables(), ws.options)
		var r := send("work", { "skill": skill, "recipe": recipe })
		assert_true(r.get("ok", false), "work %s: %s" % [skill, str(r)])
		ws.advance(5.1)
	return tries

func test_fishing() -> void:
	if not game_ok():
		return
	make_char()
	goto("xw_creek")
	assert_eq(reason("work", { "skill": "life_fishing" }), "not_known")
	var money := int(ch().money)
	ok("learn", { "npc": "n_xw_fisher", "skill": "life_fishing" })
	assert_eq(int(ch().money), money - 50)
	assert_eq(item_count("t_yugan"), 1, "tool given")
	assert_eq(int(ch().skills.level("life_fishing")), 1)
	assert_false(last("life_learn").is_empty())
	assert_eq(reason("learn", { "npc": "n_xw_fisher", "skill": "life_fishing" }), "already_known")
	var prof := int(ch().skills.prof("life_fishing"))
	ok("work", { "skill": "life_fishing" })
	assert_true(int(ch().skills.prof("life_fishing")) > prof, "prof on success or failure")
	assert_true(not last("work_ok_life_fishing").is_empty() or not last("work_fail_life_fishing").is_empty())
	assert_eq(reason("work", { "skill": "life_fishing" }), "busy")
	_work_until("life_fishing", "r_fish", 1)
	assert_true(item_count("r_fish") >= 1)
	# 沒有工具
	ch().inventory.remove(first_uid("t_yugan"), 1)
	ws.advance(5.1)
	assert_eq(reason("work", { "skill": "life_fishing" }), "no_tool")
	# 沒有水
	goto("xw_road")
	assert_eq(reason("work", { "skill": "life_fishing" }), "no_feature")

func test_woodcut() -> void:
	if not game_ok():
		return
	make_char()
	goto("xw_wood")
	ok("learn", { "npc": "n_xw_woodcutter", "skill": "life_woodcut" })
	assert_true(item_count("w_chaidao") >= 1, "柴刀")
	_work_until("life_woodcut", "r_wood", 1)
	assert_true(item_count("r_wood") >= 1)
	ch().vitals["jing"] = 2
	ws.advance(5.1)
	ch().vitals["jing"] = 2
	assert_eq(reason("work", { "skill": "life_woodcut" }), "not_enough_jing")

func test_farming_in_shaolin_garden() -> void:
	if not game_ok():
		return
	make_char("農夫", "dali")
	goto("dlw_paddy")
	ok("learn", { "npc": "n_taoyun", "skill": "life_farming" })
	assert_eq(item_count("t_chutou"), 1)
	_work_until("life_farming", "r_rice", 2)
	assert_true(item_count("r_rice") >= 2)
	goto("sl_caiyuan")
	var before := item_count("r_rice")
	_work_until("life_farming", "r_rice", before + 1)
	assert_true(item_count("r_rice") > before, "菜園也可以耕作")

func test_cooking_recipes() -> void:
	if not game_ok():
		return
	make_char()
	goto("xx_inn")
	ok("learn", { "npc": "n_xx_cook", "skill": "life_cooking" })
	assert_eq(reason("work", { "skill": "life_cooking" }), "no_recipe")
	assert_eq(reason("work", { "skill": "life_cooking", "recipe": "rc_nothing" }), "no_recipe")
	assert_eq(reason("work", { "skill": "life_cooking", "recipe": "rc_baifan" }), "no_ingredients")
	assert_eq(reason("work", { "skill": "life_cooking", "recipe": "rc_kaoyu" }), "recipe_level")
	give("r_rice", 10)
	_work_until("life_cooking", "c_baifan", 1, "rc_baifan")
	assert_true(item_count("c_baifan") >= 1)
	assert_true(item_count("r_rice") < 10, "ingredients consumed")
	ch().vitals["food"] = 10
	ok("use_item", { "item_uid": first_uid("c_baifan") })
	assert_true(int(ch().vitals["food"]) > 10)
	goto("xx_square")
	assert_eq(reason("work", { "skill": "life_cooking", "recipe": "rc_baifan" }), "no_feature")
