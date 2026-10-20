extends "res://tests/unit/test_world_sect_fixture.gd"
## SectSystem（M3A_PLAN 6.2–6.5）：停止傳功、STATE 轉換只觸發一次（含剛拜入時已違規不觸發）、三種後果模式、
## 無執法者轉 BAN、叛派減半（預設與 betrayal_halves_basics）、沒收門派物品、公敵不能再拜、personal_master。

func before_each() -> void:
	world_name = "w_sectsys"
	super.before_each()

func _joined(n := "門規俠"):
	install_sect()
	var c = member(n)
	var r := join_via_npc()
	assert_true(r.get("ok", false), str(r))
	clear_events()
	return c

func test_stop_teach() -> void:
	if not game_ok():
		return
	var c = _joined()
	assert_eq(sects().can_teach(s(), HEAD), "")
	c.morality = -1
	assert_eq(sects().can_teach(s(), HEAD), "sect_stop_teach")
	assert_eq(sects().can_teach(s(), "n_yuebuqun"), "", "別派師父不受本派停止傳功影響")
	c.morality = 0
	c.jail = { "sect": SID, "room": JAIL, "until_online_s": c.online_s + 10.0, "reason": "BREACH", "rule": "" }
	assert_eq(sects().can_teach(s(), HEAD), "jailed")

func test_state_rule_fires_once_and_resets() -> void:
	if not game_ok():
		return
	use_preset("classic_standard")
	var c = _joined()
	ws.options["ban_days"] = 1
	# 改成 BAN 模式方便反覆觸發（不會被關）
	GameData.rules["sect_violation_mode"] = "BAN"
	install_sect()
	c.morality = -200
	sects().check_state(s(), "TICK")
	sects().check_state(s(), "TICK")
	ws.flush()
	assert_eq(evs(Protocol.E_SECT_BREACH).size(), 1, "只在 成立→不成立 時觸發一次")
	assert_true(c.sect_record["breached"].has("ts_r_morality"))
	c.morality = 0
	sects().check_state(s(), "TICK")
	assert_false(c.sect_record["breached"].has("ts_r_morality"), "恢復成立時清掉")
	c.morality = -200
	sects().check_state(s(), "ENTER")
	ws.flush()
	assert_eq(evs(Protocol.E_SECT_BREACH).size(), 2, "再次越線再觸發")

func test_join_while_already_breaching_does_not_fire() -> void:
	if not game_ok():
		return
	install_sect({ "join_requires": [ { "type": "no_sect" } ] })
	var c = member("帶罪俠")
	c.killing_intent = 3000
	clear_events()
	join_via_npc()
	assert_eq(str(c.sect), SID)
	assert_true(c.sect_record["breached"].has("ts_r_killing"), "剛拜入已違規：記為 breached")
	sects().check_state(s(), "TICK")
	ws.flush()
	assert_eq(evs(Protocol.E_SECT_BREACH).size(), 0, "不會一入門就坐牢")
	assert_false(c.is_jailed())

func test_three_modes() -> void:
	if not game_ok():
		return
	# JAIL（classic_standard）
	var c = _joined("模式俠")
	assert_eq(sects().effective_mode(SID), "JAIL")
	# EXPEL（classic_strict）
	use_preset("classic_strict")
	install_sect()
	assert_eq(sects().effective_mode(SID), "EXPEL")
	c.skills.set_level(ART, 9, tables())
	c.morality = -500
	sects().check_state(s(), "TICK")
	ws.flush()
	assert_eq(str(c.sect), "", "EXPEL：逐出")
	assert_eq(c.skills.level(ART), 4, "叛派懲罰：本門武功減半")
	assert_true(c.sect_enemies.has(SID))
	assert_eq(evs(Protocol.E_SECT_EXPEL).size(), 1)
	# BAN（friends_casual；jail_enabled 也是 false）
	use_preset("friends_casual")
	install_sect()
	assert_eq(sects().effective_mode(SID), "BAN")
	# later_official：JAIL；jail_enabled 關掉 → BAN
	use_preset("later_official")
	install_sect()
	assert_eq(sects().effective_mode(SID), "JAIL")
	GameData.rules["jail_enabled"] = false
	assert_eq(sects().effective_mode(SID), "BAN", "jail_enabled false → JAIL 視同 BAN")

func test_no_enforcer_turns_jail_into_ban() -> void:
	if not game_ok():
		return
	install_sect({ "enforcer": false, "jail_room": "" })
	assert_eq(sects().effective_mode(SID), "BAN")
	install_sect({ "enforcer": true, "jail_room": "no_such_room" })
	assert_eq(sects().effective_mode(SID), "BAN", "思過處不存在也轉 BAN")

func test_kill_same_sect_event() -> void:
	if not game_ok():
		return
	var c = _joined("同門俠")
	var victim := Character.new()
	victim.id = "ch_victim"
	victim.sect = SID
	sects().on_pvp_kill(s(), victim, false)
	ws.flush()
	assert_false(c.is_jailed(), "叫戰／反殺不算")
	sects().on_pvp_kill(s(), victim, true)
	ws.flush()
	assert_true(c.is_jailed(), "強制 PK 殺同門 → 違反門規")
	assert_eq(str(c.jail.get("rule", "")), "ts_r_kill_same")

func test_betray_penalty_default_and_halves_basics() -> void:
	if not game_ok():
		return
	install_sect()
	var c := Character.new()
	c.sect = SID
	c.skills.set_level(SKILL, 30, tables())
	c.skills.set_level(ART, 1, tables())
	c.skills.set_level(OTHER_ART, 40, tables())
	c.skills.set_level("basic_fist", 41, tables())
	c.inventory.items.append({ "uid": "it_1", "id": TOKEN, "n": 3, "born_s": 0.0 })
	c.inventory.items.append({ "uid": "it_2", "id": "c_jingyao", "n": 1, "born_s": 0.0 })
	var res: Dictionary = c.betray_penalty(tables(), { "betrayal_halves_basics": false })
	assert_eq(res["arts"], { ART: [1, 0] }, "1 級減半為 0 → 移除")
	assert_false(c.skills.entries.has(ART))
	assert_eq(res["sect_skill"], [30, 30], "2001（jb170）只減半本門武功；門派技能歸零屬後期官方規則")
	assert_eq(c.skills.level(SKILL), 30)
	assert_eq(c.skills.level(OTHER_ART), 40)
	assert_eq(c.skills.level("basic_fist"), 41)
	assert_eq(res["items_removed"], [ { "id": TOKEN, "n": 3 } ])
	assert_eq(c.inventory.count("c_jingyao"), 1)
	assert_eq(c.sect, "")
	assert_eq(c.sect_enemies, [SID])
	assert_eq(c.sect_traitor, [SID], "叛徒記號")
	assert_eq(str((c.sect_record["history"] as Array).back()["what"]), "BETRAY")
	# 叛徒記號存檔還原；公敵被移除（坐完牢）後仍然不能再拜入
	var c2 := Character.from_dict(c.to_dict())
	assert_eq(c2.sect_traitor, [SID])
	c2.sect_enemies = []
	assert_eq(Requirements.check([{ "type": "not_enemy_of", "sect": SID }], c2, tables(), {}, {}), "req_not_enemy_of")
	assert_eq(Requirements.check([{ "type": "enemy_of", "sect": SID }], c2, tables(), {}, {}), "req_enemy_of", "不再是公敵")
	# 後期官方：全部武功與基本武學都減半
	var d := Character.new()
	d.sect = SID
	d.skills.set_level(SKILL, 30, tables())
	d.skills.set_level(OTHER_ART, 40, tables())
	d.skills.set_level("basic_fist", 41, tables())
	var r2: Dictionary = d.betray_penalty(tables(), { "betrayal_halves_basics": true }, "EXPEL")
	assert_eq(d.skills.level(OTHER_ART), 20)
	assert_eq(d.skills.level("basic_fist"), 20)
	assert_eq(r2["arts"]["basic_fist"], [41, 20])
	assert_eq(d.skills.level(SKILL), 0, "後期官方：門派技能歸零")
	assert_eq(r2["sect_skill"], [30, 0])
	assert_eq(str((d.sect_record["history"] as Array).back()["what"]), "EXPEL")

func test_personal_master() -> void:
	if not game_ok():
		return
	install_sect({ "personal_master": true })
	var c = member("全真徒")
	join_via_npc()
	assert_eq(str(c.sect_master), HEAD, "拜入時記下師父")
	assert_eq(Requirements.check([ { "type": "sect_master", "npc": HEAD } ], c, tables(), ws.options, GameData.rules), "")
	assert_eq(Requirements.check([ { "type": "sect_master", "npc": "n_other" } ], c, tables(), ws.options, GameData.rules), "req_sect_master")
	install_sect({ "personal_master": false })
	var d := Character.new()
	assert_eq(d.sect_master, "")

func test_jail_allowed_list_shape() -> void:
	for k in ["look", "talk", "chat", "use_item", "quest_abandon", "mail_list", "mail_read"]:
		assert_has(SectSystem.JAIL_ALLOWED, k, "§6.6 允許 " + k)
	# 研究 jy1-2-5-4：囚犯只剩傳音入密與輕聲細語 → 不能練功、打坐、運功、換裝（M3a 審查 A8）
	for k in ["move", "fight", "learn", "join_sect", "buy", "challenge", "force_pk", "travel", "work",
			"self_study", "meditate", "exert", "equip", "unequip"]:
		assert_not_has(SectSystem.JAIL_ALLOWED, k)
