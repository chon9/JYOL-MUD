extends "res://tests/unit/test_world_sect_fixture.gd"
## M3a 第三輪審查修正（主機部分）的回歸測試：
## - B1：戰後持續中毒——戰鬥中的行動次數用完不等於治好，戰後的發作原封不動保留（以前打一隻野兔就解毒）；
## - A4：全真「不能飲酒 → 減低養生」（sect_skill_penalties DRINK、items.alcohol）；
## - A3：師父只教 1 級的武功，可以靠武功列的 self_study_cap 自修上去；
## - C3、C4：違規訊息不露出代碼、刑期同時寫遊戲日與上線時間。

const WINE := "c_ts_wine"

func before_each() -> void:
	world_name = "w_m3a_review3"
	super.before_each()

func test_lingering_poison_survives_when_battle_actions_run_out() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("餘毒俠")
	make_strong()
	c.add_condition("poison", 10, 20, c.online_s + 120.0)
	c.conditions["poison"]["actions_left"] = 1   # 戰鬥中只剩 1 次，第一次行動就用完
	start_battle(["m_rabbit"])
	assert_true(s().battle_id != 0)
	drive_battle("fight")
	assert_eq(s().battle_id, 0, "打完了")
	assert_true(c.conditions.has("poison"), "行動次數用完不是治好：戰後的發作還在（M3a 審查 B1）")
	var e: Dictionary = c.conditions["poison"]
	assert_eq(int(e["ticks_left"]), 20, "戰後發作次數原封不動")
	assert_eq(int(e["level"]), 10)
	assert_eq(int(e.get("actions_left", -1)), 0, "之後不再帶進戰鬥")
	var spec: Dictionary = c.to_combatant(tables(), ws.options, 0, 1)
	assert_false((spec.get("statuses", {}) as Dictionary).has("poison"))
	clear_events()
	fast_forward(121.0)
	assert_true(evs(Protocol.E_POISON_FLARE).size() >= 1, "戰後照樣發作")

func test_settle_conditions_clears_only_cured() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("解毒俠")
	c.add_condition("poison", 4, 8, c.online_s + 120.0)
	var bs = host().battles
	# 帶進戰鬥、戰鬥中被治好 → 清掉
	bs._settle_conditions(c, { "statuses": {}, "status_left": {}, "start_statuses": { "poison": 4 },
		"cured_statuses": { "poison": true } })
	assert_false(c.conditions.has("poison"), "戰鬥中被治好 → 角色身上的也解除")
	# 帶進戰鬥、只是次數用完 → 保留
	c.add_condition("poison", 4, 8, c.online_s + 120.0)
	bs._settle_conditions(c, { "statuses": {}, "status_left": {}, "start_statuses": { "poison": 4 }, "cured_statuses": {} })
	assert_true(c.conditions.has("poison"))
	assert_eq(int(c.conditions["poison"]["actions_left"]), 0)
	# 戰鬥中被逼毒降到 2 級（沒解完）→ 角色身上的等級跟著降
	c.conditions["poison"].erase("actions_left")
	bs._settle_conditions(c, { "statuses": { "poison": 2 }, "status_left": { "poison": 3 }, "start_statuses": { "poison": 4 },
		"cured_statuses": {} })
	assert_eq(int(c.conditions["poison"]["level"]), 2)
	assert_eq(int(c.conditions["poison"]["ticks_left"]), 8, "發作次數不變")
	assert_eq(int(c.conditions["poison"]["actions_left"]), 3)

func _install_wine() -> void:
	t()["items"][WINE] = { "id": WINE, "name": "測酒", "tab": "OTHER", "slot": "", "atk": 0, "def": 0, "weight": 1,
		"price": 1, "stack": 20, "spoil_days": 0, "effects": [ { "type": "restore", "stat": "water", "value": 10 } ],
		"alcohol": true, "usable": true, "usable_in_battle": false, "no_sell": false, "quest_item": false,
		"era": "1.0A", "src": "proposal" }

func test_drinking_lowers_sect_skill_when_forbidden() -> void:
	if not game_ok():
		return
	install_sect({ "sect_skill_penalties": [ { "trigger": "DRINK", "levels": 1 } ] })
	_install_wine()
	var c = member("酒戒俠")
	c.sect = SID
	c.skills.set_level(SKILL, 5, tables())
	give(WINE, 2)
	clear_events()
	ok("use_item", { "item_uid": first_uid(WINE) })
	assert_eq(c.skills.level(SKILL), 4, "飲酒 → 養生降 1 級")
	assert_eq(evs(Protocol.E_WINE_VOW).size(), 1, "wine_vow_broken")
	assert_eq(evs(Protocol.E_MEAT_VOW).size(), 0)

func test_drinking_is_free_without_drink_penalty() -> void:
	if not game_ok():
		return
	install_sect()
	_install_wine()
	var c = member("血刀酒客")
	c.sect = SID
	c.skills.set_level(SKILL, 5, tables())
	give(WINE, 1)
	ok("use_item", { "item_uid": first_uid(WINE) })
	assert_eq(c.skills.level(SKILL), 5, "沒有酒戒的門派喝酒沒事")

func test_quanzhen_data_has_drink_penalty() -> void:
	var sect: Dictionary = tables()["sects"]["quanzhen"]
	var drink := (sect["sect_skill_penalties"] as Array).filter(func(p): return str(p.get("trigger", "")) == "DRINK")
	assert_eq(drink.size(), 1, "全真：飲酒減低養生【已證實】")
	assert_true(bool(tables()["items"]["c_xd_jiu"].get("alcohol", false)))

func test_master_cap_one_then_self_study() -> void:
	if not game_ok():
		return
	install_sect()
	t()["masters"]["ms_ts_art"]["cap"] = 1
	t()["martial_arts"][ART]["self_study_cap"] = 80
	var c = member("苦修俠")
	c.sect = SID
	assert_eq(Learning.self_study_cap(c, ART, tables(), GameData.rules), 80,
		"師父只教 1 級，武功列的自修上限 80 才是上限（M3a 審查 A3）")
	t()["martial_arts"][ART]["self_study_cap"] = 0
	assert_eq(Learning.self_study_cap(c, ART, tables(), GameData.rules), 1, "沒有自修上限時跟師父一樣")

func test_emei_special_arts_trainable_past_one() -> void:
	for aid in ["em_jiuyang", "em_miejian", "em_juejian", "em_foguang"]:
		var row: Dictionary = tables()["martial_arts"][aid]
		assert_true(int(row.get("self_study_cap", 0)) > 1, aid + " 可以自修超過 1 級")

func test_breach_message_has_no_code_or_double_tag() -> void:
	if not game_ok():
		return
	install_sect()
	t()["text_templates"]["rule_ts_killing"] = { "id": "rule_ts_killing", "self": "【門規】測派弟子殺氣不得超過 2000。", "era": "1.0A" }
	var c = member("違規俠")
	c.sect = SID
	clear_events()
	c.killing_intent = 2500
	sects().check_state(s(), "TICK")
	ws.flush()
	var br := evs(Protocol.E_SECT_BREACH)
	assert_eq(br.size(), 1)
	var p: Dictionary = br[0].get("p", br[0].get("params", {}))
	assert_eq(str(p.get("outcome", "")), "JAIL", "程式用的代碼還在")
	assert_eq(str(p.get("outcome_text", "")), "押入思過處", "給玩家看的字（M3a 審查 C3）")
	assert_eq(str(p.get("rule_text", "")), "測派弟子殺氣不得超過 2000", "去掉【門規】標籤與句號")
	var tpl := str(tables()["text_templates"]["sect_breach"]["self"])
	assert_false(tpl.contains("{outcome}"), "模板用 outcome_text")
	var ji := evs(Protocol.E_JAIL_IN)
	assert_eq(ji.size(), 1)
	var jp: Dictionary = ji[0].get("p", ji[0].get("params", {}))
	assert_true(str(jp.get("online_text", "")) != "", "刑期附上線時間（M3a 審查 C4）")

func test_sect_rule_templates_are_bare_rules() -> void:
	var tpl: Dictionary = tables()["text_templates"]
	for k in tpl:
		if not str(k).begins_with("rule_"):
			continue
		var t := str(tpl[k].get("self", ""))
		assert_false(t.begins_with("【"), "%s 不帶頻道標籤" % k)
		assert_false(t.ends_with("。"), "%s 不帶句號（由 sect_breach／拜師確認接句）" % k)
		assert_false(t.contains("門規："), "%s 不重複「XX門規：」" % k)
		assert_false(t.begins_with("你"), "%s 只寫規則本身" % k)

func test_online_text_format() -> void:
	if not game_ok():
		return
	install_sect()
	var day := float(ws.options.get("game_day_real_s", 7200))
	var txt: String = sects().online_text(1)
	if is_equal_approx(day, 7200.0):
		assert_eq(txt, "2 小時")
	assert_true(txt.length() > 0)
