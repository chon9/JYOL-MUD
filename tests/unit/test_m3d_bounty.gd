extends "res://tests/unit/test_pk_world_base.gd"
## M3D_PLAN §2.2–§2.4（WP-LAW）：上名單（PK 4、PK 1＋惡、新手不上、統計時點）、合法緝拿（PK值不加、善惡不變、殺氣 +20、
## 傳聞、目標 PK −1）、非法照惡意 PK、懸賞金從目標身上與錢莊扣、加碼與上限、同隊／同組織不給、同日重複不給、領賞。

func before_each() -> void:
	world_name = "w_m3d_bounty"
	super.before_each()
	if host() != null and host().get("law") != null:
		host().law.hunter_chance_pct = 0   # 這個檔不測 NPC 獵人（走進野外不要被打擾）

func law():
	return host().get("law")

func _deps() -> bool:
	if not deps_ok(true):
		return false
	if law() == null or not ws.has_intent_handler("bounty_license"):
		fail("LawSystem／intents_law 沒有載入")
		return false
	return true

## 把 peer 弄成 PK值 pk、善惡 mo 的「老江湖」（實戰 5000，不是新手）
func _villain(peer: int, pk: int, mo := 0) -> void:
	var c = chr(peer)
	c.combat_xp = maxi(int(c.combat_xp), 5000)
	c.pk = pk
	c.pk_stamp_s = c.online_s
	c.morality = mo

func _license(peer: int) -> void:
	chr(peer).money = maxi(int(chr(peer).money), 1000)
	ok_p(peer, "bounty_license", { "npc": "n_law_guanye_xx_a" })

## 持照的 hunter 在 xw_road 合法緝拿 target，打到 target 死；回 bid
func _lawful_kill(hunter: int, target: int) -> int:
	goto_p(hunter, "xw_road")
	goto_p(target, "xw_road")
	make_strong_p(hunter)
	make_weak_p(target)
	var r := ok_p(hunter, "force_pk", { "target": cid(target) })
	var bid := int(r.get("battle_id", 0))
	assert_true(law().is_lawful_bid(bid), "lawful battle recorded")
	drive_bid(bid, { hunter: "fight", target: "defend" })
	return bid

# ------------------------------------------------------------------ 純規則
func test_listed_rules() -> void:
	assert_true(BountyRules.listed(4, 0, 5000, 500), "PK 4 → listed")
	assert_false(BountyRules.listed(3, 0, 5000, 500), "PK 3 neutral → not listed")
	assert_true(BountyRules.listed(1, -101, 5000, 500), "PK 1 + evil → listed")
	assert_false(BountyRules.listed(1, -100, 5000, 500), "PK 1, morality -100 → not evil")
	assert_false(BountyRules.listed(0, -900, 5000, 500), "PK 0 never listed")
	assert_false(BountyRules.listed(9, -900, 499, 500), "newbie never listed")
	assert_eq(BountyRules.fine(4, 0), 4000)
	assert_eq(BountyRules.fine(1, -200), 1500)
	assert_eq(BountyRules.fine(30, -200), BountyRules.FINE_CAP)
	assert_eq(BountyRules.fine(0, -500), 0)
	assert_eq(BountyRules.collect(4000, 2500, 10000), { "from_money": 2500, "from_bank": 1500, "total": 4000 })
	assert_eq(BountyRules.collect(4000, 100, 200), { "from_money": 100, "from_bank": 200, "total": 300 })
	assert_eq(BountyRules.collect(4000, -5, 0)["total"], 0)
	assert_true(BountyRules.lawful(true, 0, true))
	assert_false(BountyRules.lawful(false, 0, true), "no license")
	assert_false(BountyRules.lawful(true, 1, true), "hunter has PK")
	assert_false(BountyRules.lawful(true, 0, false), "target not listed")

# ------------------------------------------------------------------ 名單與統計時點
func test_board_refreshes_each_shichen_only() -> void:
	if not _deps():
		return
	var a := add("惡甲")
	var n := add("新手乙")
	var e := add("惡丙")
	ws.advance(0.2)
	_villain(a, 4)
	_villain(e, 1, -150)
	chr(n).pk = 9
	chr(n).pk_stamp_s = chr(n).online_s
	chr(n).combat_xp = 100   # 新手：不上榜
	ws.advance(0.2)
	assert_false(law().is_listed(cid(a)), "not instant: waits for the next shichen")
	var idx := (int(host().clock()["shichen_idx"]) + 1) % 12
	set_shichen(idx)
	assert_true(law().is_listed(cid(a)), "PK 4 listed after the shichen")
	assert_true(law().is_listed(cid(e)), "PK 1 + evil listed")
	assert_false(law().is_listed(cid(n)), "newbie never listed")
	assert_false(evs_p(a, "law_listed").is_empty(), "listed player told")
	goto_p(a, "xx_square")
	goto_p(e, "xx_square")
	ok_p(e, "bounty_board", { "npc": "n_law_board_xx" })
	var p := lastp_p(e, "bounty_board")
	var rows: Array = p.get("rows", [])
	assert_eq(rows.size(), 2, "two rows")
	var found := {}
	for r in rows:
		found[str(r.get("name", ""))] = r
	assert_eq(int(found.get("惡甲", {}).get("amount", 0)), 4000, "amount = fine 1000 × 4")
	assert_eq(int(found.get("惡丙", {}).get("amount", 0)), 1500, "evil bonus")
	assert_eq(str(found.get("惡甲", {}).get("sect_name", "")), "無門無派")
	assert_true(str(p.get("refreshed_text", "")) != "", "refreshed time shown")
	# 視圖標籤「懸賞」與角色表 law.listed
	settle()
	var tagged := false
	for pl in view_p(e).get("players", []):
		if str(pl.get("name", "")) == "惡甲" and "懸賞" in (pl.get("tags", []) as Array):
			tagged = true
	assert_true(tagged, "room tag 懸賞")
	assert_true(sheet_p(a).get("law", {}).get("listed", false) == true, "sheet.law.listed")
	# 下榜也要等下一次統計
	chr(a).pk = 0
	ws.advance(0.2)
	assert_true(law().is_listed(cid(a)), "still listed until next refresh")
	set_shichen((idx + 1) % 12)
	assert_false(law().is_listed(cid(a)), "off the board after refresh")

func test_bounty_off_option() -> void:
	if not _deps():
		return
	var a := add("惡甲")
	var b := add("看榜乙")
	_villain(a, 5)
	law().refresh_board()
	assert_true(law().is_listed(cid(a)))
	ws.options["bounty_enabled"] = false
	law().refresh_board()
	assert_false(law().is_listed(cid(a)), "disabled: no list")
	goto_p(b, "xx_square")
	ok_p(b, "bounty_board", { "npc": "n_law_board_xx" })
	assert_true(lastp_p(b, "bounty_board").get("enabled", true) == false, "board says paused")
	assert_eq(reason_p(b, "bounty_add", { "npc": "n_law_board_xx", "target_name": "惡甲", "money": 500 }), "bounty_off")
	ws.options["bounty_enabled"] = true

# ------------------------------------------------------------------ 合法與非法緝拿
func test_lawful_kill_no_pk_and_bounty_from_target_money() -> void:
	if not _deps():
		return
	var a := add("惡甲")
	var b := add("獵人乙")
	var watcher := add("看客")
	goto_p(watcher, "xx_square")
	goto_p(b, "xx_square")
	_license(b)
	_villain(a, 4)
	law().refresh_board()
	chr(a).money = 2500
	BankStore.bank_of(chr(a))["money"] = 10000
	var mo_b := int(chr(b).morality)
	var ki_b := int(chr(b).killing_intent)
	_lawful_kill(b, a)
	assert_true(chr(a).vitals.get("qi", 1) <= 0 or bool(chr(a).dead_count > 0), "target died")
	assert_eq(int(chr(b).pk_value()), 0, "lawful: hunter PK unchanged")
	assert_eq(int(chr(b).morality), mo_b, "lawful: morality unchanged")
	assert_eq(int(chr(b).killing_intent), ki_b + BountyRules.LAWFUL_KILLING_INTENT, "lawful: killing intent +20")
	assert_eq(int(chr(a).pk_value()), 3, "target PK −1")
	assert_eq(int(chr(a).money), 0, "fine taken from carried money first")
	assert_eq(int(BankStore.bank_of(chr(a))["money"]), 8500, "then from the bank")
	assert_true(lastp_p(watcher, "pk_kill").is_empty(), "no world pk_kill broadcast")
	assert_eq(int(lastp_p(b, "law_bounty_earned").get("amount", 0)), 4000)
	assert_eq(law().claims_total(cid(b)), 4000)
	var rumors := false
	if host().get("rumor") != null:
		for e in host().rumor.recent(10):
			if str(e.get("text_key", "")) == "rmr_law_caught":
				rumors = true
		assert_true(rumors, "rumor rmr_law_caught posted")
	# 領賞
	goto_p(b, "xx_square")
	var before := int(chr(b).money)
	ok_p(b, "bounty_claim", { "npc": "n_law_guanye_xx_a" })
	assert_eq(int(chr(b).money), before + 4000, "claimed")
	assert_eq(law().claims_total(cid(b)), 0)
	assert_eq(reason_p(b, "bounty_claim", { "npc": "n_law_guanye_xx_a" }), "bounty_no_claims")
	# M3d 審查：PK 4 → 3 不再夠格 → 立刻下榜（不等下個時辰），不能再「合法」緝拿
	assert_false(law().is_listed(cid(a)), "PK 3 → off the board at once")
	Survival.rest_full(chr(a), tables(), ws.options)
	goto_p(b, "xw_road")
	goto_p(a, "xw_road")
	assert_false(law().lawful_hunt(sess(b), chr(a)), "stale listing cannot be hunted again")

## M3d 審查：同一天重複緝拿、或朋友緝拿 → 不發賞金也不減 PK值（朋友互殺不能洗 PK）
func test_repeat_or_friend_kill_keeps_pk() -> void:
	if not _deps():
		return
	var a := add("惡甲")
	var b := add("獵人乙")
	goto_p(b, "xx_square")
	_license(b)
	_villain(a, 8)
	law().refresh_board()
	chr(a).money = 50000
	_lawful_kill(b, a)
	assert_eq(int(chr(a).pk_value()), 7, "first catch: PK −1")
	assert_true(law().is_listed(cid(a)), "PK 7 stays listed")
	assert_eq(int(law().board_row(cid(a)).get("pk", 0)), 7, "board row refreshed to live PK")
	var claims: int = law().claims_total(cid(b))
	Survival.rest_full(chr(a), tables(), ws.options)
	_lawful_kill(b, a)
	assert_false(lastp_p(b, "law_no_bounty_daily").is_empty(), "same day: no bounty")
	assert_eq(law().claims_total(cid(b)), claims, "no second payout")
	assert_eq(int(chr(a).pk_value()), 7, "same day repeat: PK unchanged")
	# 同組織／同隊的朋友：不發也不減
	law().data()["paid_log"].clear()
	if host().get("party") != null and ws.has_intent_handler("party_invite"):
		Survival.rest_full(chr(a), tables(), ws.options)
		goto_p(a, "xw_road")
		goto_p(b, "xw_road")
		ok_p(b, "party_invite", { "target": cid(a) })
		ok_p(a, "party_reply", { "from": cid(b), "accept": true })
		ws.advance(0.2)
		assert_eq(law()._friend_reason(cid(b), cid(a), sess(b), sess(a)), "law_no_bounty_friend")
		law()._caught(cid(b), cid(a), "xw_road")
		assert_eq(int(chr(a).pk_value()), 7, "friend catch: PK unchanged")
		assert_eq(law().claims_total(cid(b)), claims, "friend catch: no payout")

## M3d 審查：半仙消到不夠格 → 立刻下榜；paid_log 換時辰只留今天；刪角色清掉 claims 與 paid_log
func test_cleanse_delists_and_log_pruned() -> void:
	if not _deps():
		return
	var a := add("惡甲")
	var b := add("獵人乙")
	_villain(a, 4)
	law().refresh_board()
	assert_true(law().is_listed(cid(a)))
	chr(a).pk = 3
	chr(a).pk_stamp_s = chr(a).online_s
	assert_false(law().listed_live(chr(a)), "live check: PK 3 not huntable even if the snapshot says listed")
	assert_false(law().recheck_listing(chr(a)), "recheck drops the row")
	assert_false(law().is_listed(cid(a)))
	var pl: Dictionary = law().data()["paid_log"]
	pl["%s|%s" % [cid(b), cid(a)]] = law().today() - 1
	pl["x|y"] = law().today()
	law().refresh_board()
	assert_false(pl.has("%s|%s" % [cid(b), cid(a)]), "old paid_log pruned")
	assert_true(pl.has("x|y"), "today's kept")
	law().data()["claims"][cid(b)] = [{ "target_name": "惡甲", "amount": 100, "s": 0.0 }]
	pl["%s|%s" % [cid(b), cid(a)]] = law().today()
	law().on_char_deleted(cid(b))
	assert_false(law().data()["claims"].has(cid(b)), "claims removed")
	assert_false(pl.has("%s|%s" % [cid(b), cid(a)]), "paid_log removed")

func test_unlicensed_force_pk_is_malicious() -> void:
	if not _deps():
		return
	var a := add("惡甲")
	var c := add("莽夫丙")
	_villain(a, 4)
	law().refresh_board()
	goto_p(a, "xw_road")
	goto_p(c, "xw_road")
	make_strong_p(c)
	make_weak_p(a)
	var r := ok_p(c, "force_pk", { "target": cid(a) })
	var bid := int(r.get("battle_id", 0))
	assert_false(law().is_lawful_bid(bid), "no license → not lawful")
	drive_bid(bid, { c: "fight", a: "defend" })
	assert_eq(int(chr(c).pk_value()), 1, "malicious PK +1")
	assert_eq(int(chr(a).pk_value()), 4, "target PK unchanged by an unlawful kill")
	assert_eq(law().claims_total(cid(c)), 0, "no bounty")

func test_license_void_when_hunter_has_pk() -> void:
	if not _deps():
		return
	var a := add("惡甲")
	var b := add("獵人乙")
	goto_p(b, "xx_square")
	_license(b)
	_villain(a, 4)
	law().refresh_board()
	chr(b).pk = 1
	chr(b).pk_stamp_s = chr(b).online_s
	goto_p(a, "xw_road")
	goto_p(b, "xw_road")
	make_strong_p(b)
	make_weak_p(a)
	var r := ok_p(b, "force_pk", { "target": cid(a) })
	assert_false(law().is_lawful_bid(int(r.get("battle_id", 0))), "PK > 0 → not lawful")
	assert_false(LawSystem.has_license(chr(b)), "license voided")
	assert_false(evs_p(b, "law_license_void").is_empty(), "told")
	host().battles.abort_all()

# ------------------------------------------------------------------ 加碼與防刷
func test_pool_add_limits_and_payout() -> void:
	if not _deps():
		return
	var a := add("惡甲")
	var c := add("苦主丙")
	var d := add("獵人丁")
	_villain(a, 4)
	law().refresh_board()
	goto_p(c, "xx_square")
	chr(c).money = 200000
	assert_eq(reason_p(c, "bounty_add", { "npc": "n_law_board_xx", "target_name": "無名氏", "money": 500 }), "bounty_not_listed")
	assert_eq(reason_p(c, "bounty_add", { "npc": "n_law_board_xx", "target_name": "惡甲", "money": 99 }), "bounty_pool_min")
	ok_p(c, "bounty_add", { "npc": "n_law_board_xx", "target_name": "惡甲", "money": 5000 })
	assert_eq(int(chr(c).money), 195000, "pool paid from the contributor")
	assert_eq(law().pool_of(cid(a)), 5000)
	assert_eq(reason_p(c, "bounty_add", { "npc": "n_law_board_xx", "target_name": "惡甲", "money": 95001 }), "bounty_pool_cap")
	assert_eq(reason_p(a, "bounty_add", { "npc": "n_law_board_xx", "target_name": "惡甲", "money": 500 }), "self_target")
	chr(c).money = 50
	assert_eq(reason_p(c, "bounty_add", { "npc": "n_law_board_xx", "target_name": "惡甲", "money": 500 }), "not_enough_money")
	var board := lastp_p(c, "bounty_board")
	assert_false(board.is_empty(), "board re-sent after adding")
	# 官爺（耳聾）也收加碼？→ 聽錯
	assert_eq(reason_p(c, "bounty_add", { "npc": "n_law_guanye_xx_b", "target_name": "惡甲", "money": 500 }), "license_deaf")
	# 獵人丁緝殺 → 罰金（目標自己的錢）＋加碼 5000
	goto_p(d, "xx_square")
	_license(d)
	chr(a).money = 4000
	_lawful_kill(d, a)
	assert_eq(law().claims_total(cid(d)), 9000, "fine 4000 + pool 5000")
	assert_eq(law().pool_of(cid(a)), 0, "pool paid out")

func test_same_party_or_daily_no_bounty() -> void:
	if not _deps():
		return
	var a := add("惡甲")
	var b := add("獵人乙")
	goto_p(a, "xw_road")
	goto_p(b, "xw_road")
	assert_eq(law()._friend_reason(cid(b), cid(a), sess(b), sess(a)), "", "strangers")
	if host().get("party") != null and ws.has_intent_handler("party_invite"):
		ok_p(b, "party_invite", { "target": cid(a) })
		ok_p(a, "party_reply", { "from": cid(b), "accept": true })
		ws.advance(0.2)
		assert_eq(law()._friend_reason(cid(b), cid(a), sess(b), sess(a)), "law_no_bounty_friend", "same party")
		ok_p(a, "party_leave")
		ws.advance(0.2)
		assert_eq(law()._friend_reason(cid(b), cid(a), sess(b), sess(a)), "", "left the party")
	law().data()["paid_log"]["%s|%s" % [cid(b), cid(a)]] = law().today()
	assert_eq(law()._friend_reason(cid(b), cid(a), sess(b), sess(a)), "law_no_bounty_daily", "same day")
	law().data()["paid_log"]["%s|%s" % [cid(b), cid(a)]] = law().today() - 1
	assert_eq(law()._friend_reason(cid(b), cid(a), sess(b), sess(a)), "", "next day ok")

# ------------------------------------------------------------------ 存檔欄位
func test_world_bounty_shape() -> void:
	if not _deps():
		return
	var d: Dictionary = law().data()
	for k in ["board", "board_s", "pools", "claims", "paid_log"]:
		assert_true(d.has(k), "world.bounty." + k)
	assert_true(ws.world.has("bounty"), "stored in world.json")

## M3d 審查第三輪：目標身上與錢莊都沒錢、也沒有加碼 → 賞金 0 兩 → PK值 不減（朋友輪流緝殺不能免費洗 PK值）；
## 有錢付得出罰金時照樣 −1
func test_zero_bounty_keeps_pk() -> void:
	if not _deps():
		return
	var a := add("窮惡甲")
	var b := add("獵人乙")
	goto_p(b, "xx_square")
	_license(b)
	_villain(a, 2, -200)
	law().refresh_board()
	assert_true(law().is_listed(cid(a)), "PK 2＋惡 → 上榜")
	chr(a).money = 0
	BankStore.bank_of(chr(a))["money"] = 0
	law().data()["pools"].erase(cid(a))
	_lawful_kill(b, a)
	assert_eq(int(chr(a).pk_value()), 2, "賞金 0 兩 → PK值 不減")
	assert_true(law().is_listed(cid(a)), "還在名單上")
	# 換一天、身上有錢 → 照樣 −1
	law().data()["paid_log"].clear()
	Survival.rest_full(chr(a), tables(), ws.options)
	chr(a).money = 5000
	_lawful_kill(b, a)
	assert_eq(int(chr(a).pk_value()), 1, "付得出罰金 → PK值 −1")

## M3d 審查第三輪：離線讀檔的角色照目前規則設 pk_decay_on（pk_decay 關時不遞減）
func test_offline_load_respects_pk_decay_rule() -> void:
	if not _deps():
		return
	var a := add("離線甲")
	var id_a := cid(a)
	chr(a).pk = 2
	chr(a).pk_stamp_s = chr(a).online_s
	chr(a).online_s += 7200.0
	drop_player(a)
	ws.advance(0.2)
	GameData.rules["pk_decay"] = false
	var c = law()._load_any(id_a)
	assert_true(c != null, "讀得到角色檔")
	if c != null:
		assert_false(bool(c.pk_decay_on), "pk_decay 關 → 讀檔的角色不遞減")
		assert_eq(int(c.pk_value()), 2, "上線 2 小時仍 2")
	var pks = host().get("pk")
	if pks != null:
		var c2 = pks._char_any(id_a)
		assert_true(c2 != null and not bool(c2.pk_decay_on), "PkSystem 讀檔也一樣")
	GameData.rules["pk_decay"] = true
