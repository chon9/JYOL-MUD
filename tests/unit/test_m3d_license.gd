extends "res://tests/unit/test_pk_world_base.gd"
## M3D_PLAN §2.3（WP-LAW）：賞金獵人執照——PK值 > 0 不能領、上榜不能領、錢不夠、耳聾官爺（不收錢、輪流聽錯）、
## PK值 > 0 自動失效（緝拿與領賞時檢查）、重複領不再收錢、角色表 law.licensed。

func before_each() -> void:
	world_name = "w_m3d_license"
	super.before_each()
	if host() != null and host().get("law") != null:
		host().law.hunter_chance_pct = 0

func law():
	return host().get("law")

func _deps() -> bool:
	if not deps_ok():
		return false
	if law() == null or not ws.has_intent_handler("bounty_license"):
		fail("LawSystem／intents_law 沒有載入")
		return false
	return true

func test_license_reason_order_pure() -> void:
	assert_eq(BountyRules.license_reason(1, false, 9999), "license_pk")
	assert_eq(BountyRules.license_reason(0, true, 9999), "license_listed")
	assert_eq(BountyRules.license_reason(0, false, 99), "not_enough_money")
	assert_eq(BountyRules.license_reason(0, false, 100), "")

func test_license_flow() -> void:
	if not _deps():
		return
	var a := add("獵人甲")
	goto_p(a, "xx_square")
	var c = chr(a)
	c.money = 50
	assert_eq(reason_p(a, "bounty_license", { "npc": "n_law_guanye_xx_a" }), "not_enough_money")
	c.money = 500
	c.pk = 1
	c.pk_stamp_s = c.online_s
	assert_eq(reason_p(a, "bounty_license", { "npc": "n_law_guanye_xx_a" }), "license_pk")
	c.pk = 0
	ok_p(a, "bounty_license", { "npc": "n_law_guanye_xx_a" })
	assert_eq(int(c.money), 500 - BountyRules.LICENSE_FEE, "fee paid")
	assert_true(LawSystem.has_license(c))
	assert_true(c.ext.get("law", {}).get("license_s", -1.0) >= 0.0, "ext.law.license_s")
	assert_false(lastp_p(a, "law_license_ok").is_empty())
	settle()
	assert_true(sheet_p(a).get("law", {}).get("licensed", false) == true, "sheet.law.licensed")
	# 再領一次：不再收錢
	ok_p(a, "bounty_license", { "npc": "n_law_guanye_xx_a" })
	assert_eq(int(c.money), 400, "no second fee")
	# 錯的 NPC
	assert_eq(reason_p(a, "bounty_license", { "npc": "n_law_board_xx" }), "no_service")
	goto_p(a, "xw_road")
	assert_eq(reason_p(a, "bounty_license", { "npc": "n_law_guanye_xx_a" }), "not_here")

func test_listed_cannot_license() -> void:
	if not _deps():
		return
	var a := add("惡甲")
	goto_p(a, "xx_square")
	var c = chr(a)
	c.combat_xp = 5000
	c.money = 500
	c.pk = 1
	c.morality = -300
	c.pk_stamp_s = c.online_s
	law().refresh_board()
	assert_true(law().is_listed(str(c.id)))
	# PK 先擋（PK > 0）；PK 降到 0 但名單還沒重算 → license_listed
	c.pk = 0
	assert_eq(reason_p(a, "bounty_license", { "npc": "n_law_guanye_xx_a" }), "license_listed")

func test_deaf_officer_never_hears() -> void:
	if not _deps():
		return
	var a := add("獵人甲")
	goto_p(a, "xx_square")
	chr(a).money = 1000
	var seen := {}
	for i in 3:
		assert_eq(reason_p(a, "bounty_license", { "npc": "n_law_guanye_xx_b" }), "license_deaf")
	for k in ["law_deaf_1", "law_deaf_2", "law_deaf_3"]:
		seen[k] = not evs_p(a, k).is_empty()
	assert_eq(seen, { "law_deaf_1": true, "law_deaf_2": true, "law_deaf_3": true }, "three different misheard lines")
	assert_eq(int(chr(a).money), 1000, "deaf officer takes no money")
	assert_false(LawSystem.has_license(chr(a)))
	assert_eq(reason_p(a, "bounty_claim", { "npc": "n_law_guanye_xx_b" }), "license_deaf")
	assert_true(host().npc_row("n_law_guanye_dl_b").get("deaf", false) == true, "大理 _b deaf too")

func test_license_void_on_claim() -> void:
	if not _deps():
		return
	var a := add("獵人甲")
	goto_p(a, "xx_square")
	chr(a).money = 1000
	ok_p(a, "bounty_license", { "npc": "n_law_guanye_xx_a" })
	law().data()["claims"][cid(a)] = [{ "target_name": "某人", "amount": 300, "s": 0.0 }]
	chr(a).pk = 2
	chr(a).pk_stamp_s = chr(a).online_s
	assert_eq(reason_p(a, "bounty_claim", { "npc": "n_law_guanye_xx_a" }), "license_none", "PK > 0 → license void")
	assert_false(LawSystem.has_license(chr(a)))
	assert_false(evs_p(a, "law_license_void").is_empty())
	assert_eq(law().claims_total(cid(a)), 300, "claims kept for later")
	# PK 0 重新領照 → 可以領
	chr(a).pk = 0
	ok_p(a, "bounty_license", { "npc": "n_law_guanye_xx_a" })
	var before := int(chr(a).money)
	ok_p(a, "bounty_claim", { "npc": "n_law_guanye_xx_a" })
	assert_eq(int(chr(a).money), before + 300)

func test_claim_respects_money_cap() -> void:
	if not _deps():
		return
	var a := add("獵人甲")
	goto_p(a, "xx_square")
	chr(a).money = 1000
	ok_p(a, "bounty_license", { "npc": "n_law_guanye_xx_a" })
	chr(a).money = Character.MONEY_CAP - 100
	law().data()["claims"][cid(a)] = [{ "target_name": "某人", "amount": 300, "s": 0.0 }]
	ok_p(a, "bounty_claim", { "npc": "n_law_guanye_xx_a" })
	assert_eq(int(chr(a).money), Character.MONEY_CAP)
	assert_eq(law().claims_total(cid(a)), 200, "the rest stays")
	assert_eq(reason_p(a, "bounty_claim", { "npc": "n_law_guanye_xx_a" }), "money_cap")
