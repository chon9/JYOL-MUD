extends "res://tests/unit/test_pk_world_base.gd"
## M3D_PLAN §2.7、A6、A7（WP-LAW）：天師消殺氣（每 10 點 100 兩【已證實】，次數截到付得起與殺氣夠扣）、
## 京城半仙消 PK值（1.0B；每點 10,000 兩、每遊戲日 1 點）。

func before_each() -> void:
	world_name = "w_m3d_cleanse"
	super.before_each()
	if host() != null and host().get("law") != null:
		host().law.hunter_chance_pct = 0

func _deps() -> bool:
	if not deps_ok():
		return false
	if host().get("law") == null or not ws.has_intent_handler("cleanse"):
		fail("LawSystem／intents_law 沒有載入")
		return false
	return true

func test_tianshi_pure() -> void:
	assert_eq(BountyRules.tianshi(95, 10, 99999), { "times": 9, "cost": 900, "drop": 90 }, "only 9 full tens")
	assert_eq(BountyRules.tianshi(200, 5, 99999), { "times": 5, "cost": 500, "drop": 50 })
	assert_eq(BountyRules.tianshi(200, 10, 350), { "times": 3, "cost": 300, "drop": 30 }, "money limits")
	assert_eq(BountyRules.tianshi(9, 10, 99999)["times"], 0, "less than 10 intent")
	assert_eq(BountyRules.tianshi(5000, 500, 99999999)["times"], BountyRules.TIANSHI_MAX_TIMES)
	assert_eq(BountyRules.banxian(0, 99999, 0)["reason"], "cleanse_nothing")
	assert_eq(BountyRules.banxian(2, 99999, 1)["reason"], "cleanse_daily")
	assert_eq(BountyRules.banxian(2, 9999, 0)["reason"], "not_enough_money")
	assert_eq(BountyRules.banxian(2, 10000, 0), { "ok": true, "reason": "", "cost": 10000 })

func test_tianshi_flow() -> void:
	if not _deps():
		return
	var a := add("殺星甲")
	goto_p(a, "xw_road")
	var c = chr(a)
	c.killing_intent = 95
	c.money = 5000
	var r := ok_p(a, "cleanse", { "npc": "n_law_tianshi_xx", "what": "KILLING", "times": 10 })
	assert_eq(int(r.get("times", 0)), 9)
	assert_eq(int(c.killing_intent), 5)
	assert_eq(int(c.money), 4100, "900 taken")
	var p := lastp_p(a, "law_cleansed")
	assert_eq(int(p.get("cost", 0)), 900)
	assert_eq(int(p.get("killing_intent", -1)), 5)
	assert_eq(reason_p(a, "cleanse", { "npc": "n_law_tianshi_xx", "what": "KILLING", "times": 1 }), "cleanse_nothing")
	c.killing_intent = 300
	c.money = 50
	assert_eq(reason_p(a, "cleanse", { "npc": "n_law_tianshi_xx", "what": "KILLING", "times": 1 }), "not_enough_money")
	assert_eq(reason_p(a, "cleanse", { "npc": "n_law_tianshi_xx", "what": "PK" }), "not_cleanse_npc", "天師 does not remove PK")
	assert_eq(reason_p(a, "cleanse", { "npc": "n_law_tianshi_xx", "what": "BOGUS" }), "bad_value:what")
	goto_p(a, "dlw_road")
	c.money = 1000
	ok_p(a, "cleanse", { "npc": "n_law_tianshi_dl", "what": "KILLING" })
	assert_eq(int(c.killing_intent), 290, "times defaults to 1")
	goto_p(a, "xx_square")
	assert_eq(reason_p(a, "cleanse", { "npc": "n_law_tianshi_xx", "what": "KILLING" }), "not_here")
	assert_eq(reason_p(a, "cleanse", { "npc": "n_law_board_xx", "what": "KILLING" }), "not_cleanse_npc")

func test_banxian_daily_1_0b() -> void:
	if not _deps():
		return
	if not tables().get("npcs", {}).has("n_law_banxian_jc"):
		fail("n_law_banxian_jc missing in the 1.0A+1.0B view")
		return
	var a := add("惡甲")
	goto_p(a, "jc_square")
	var c = chr(a)
	c.pk = 2
	c.pk_stamp_s = c.online_s
	c.money = 25000
	ok_p(a, "cleanse", { "npc": "n_law_banxian_jc", "what": "PK" })
	assert_eq(int(c.pk_value()), 1)
	assert_eq(int(c.money), 15000)
	assert_eq(int(c.counters.get("banxian_day", -1)), int(host().clock()["day"]))
	assert_eq(reason_p(a, "cleanse", { "npc": "n_law_banxian_jc", "what": "PK" }), "cleanse_daily")
	assert_eq(reason_p(a, "cleanse", { "npc": "n_law_banxian_jc", "what": "KILLING" }), "not_cleanse_npc")
	# 隔天
	var day := float(ws.options.get("game_day_real_s", 7200))
	ws.world["world_time_s"] = ws.world_time() + day
	ws.advance(0.1)
	ok_p(a, "cleanse", { "npc": "n_law_banxian_jc", "what": "PK" })
	assert_eq(int(c.pk_value()), 0)
	assert_eq(reason_p(a, "cleanse", { "npc": "n_law_banxian_jc", "what": "PK" }), "cleanse_nothing")

func test_banxian_absent_in_1_0a() -> void:
	if not _deps():
		return
	use_eras(["1.0A"])
	assert_false(tables().get("npcs", {}).has("n_law_banxian_jc"), "1.0A world: no 京城半仙")
	assert_false(tables().get("npcs", {}).has("n_law_board_jc"))
	assert_true(tables().get("npcs", {}).has("n_law_tianshi_xx"), "天師 is 1.0A")
	assert_true(tables().get("npcs", {}).has("n_law_guanye_dl_b"))
