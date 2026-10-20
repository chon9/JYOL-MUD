extends "res://tests/unit/test_world_sect_fixture.gd"
## M3a 審查修正（主機部分）的回歸測試：
## - 門規名單依 sect_violation_mode 分開（JAIL／BAN = 2001-11-15 坐牢名單；EXPEL = 2001-08 叛派名單）、on_npc 交談觸發；
## - 叛徒記號：公敵坐完牢改過自新，但永遠不能再拜入；
## - 戰後持續中毒：打一場不會重新計時；
## - 試煉（TRIAL）不能中途加入；
## - 門派技能消點的額外消耗看 sect_skill_train_cost（不是戰鬥觸發的 sect_skill_cost）。

func before_each() -> void:
	world_name = "w_m3a_review"
	super.before_each()

## 兩條同一門檻的門規：JAIL／BAN 用 −299、EXPEL 用 −99；外加一條只在跟掌門交談時檢查的 EXPEL 規則（−50）
func _mode_rules() -> Array:
	return [
		{ "id": "ts_r_jail", "sect": SID, "tier": "BREACH", "kind": "STATE", "modes": ["JAIL", "BAN"],
			"ok_if": [ { "type": "morality_min", "value": -299 } ], "text": "rule_ts_morality", "era": "1.0A", "src": "proposal" },
		{ "id": "ts_r_expel", "sect": SID, "tier": "BREACH", "kind": "STATE", "modes": ["EXPEL"],
			"ok_if": [ { "type": "morality_min", "value": -99 } ], "text": "rule_ts_morality", "era": "1.0A", "src": "proposal" },
		{ "id": "ts_r_talk", "sect": SID, "tier": "BREACH", "kind": "STATE", "modes": ["EXPEL"], "on_npc": [HEAD],
			"ok_if": [ { "type": "morality_min", "value": -50 } ], "text": "rule_ts_morality", "era": "1.0A", "src": "proposal" },
	]

func test_rules_follow_violation_mode() -> void:
	if not game_ok():
		return
	install_sect({}, _mode_rules())
	var c = member("門規俠")
	c.sect = SID
	# 預設 classic_standard（JAIL）：−150 不違規（2001-08 的 −99 不適用），−350 才坐牢
	var ids: Array = sects().rules_of(SID, "STATE").map(func(r): return str(r["id"]))
	assert_eq(ids, ["ts_r_jail"], "JAIL 模式只看坐牢名單；on_npc 列不在一般檢查裡")
	c.morality = -150
	sects().check_state(s(), "TICK")
	assert_false(c.is_jailed(), "−150 不違反 JAIL 名單")
	assert_eq(str(c.sect), SID)
	c.morality = -350
	sects().check_state(s(), "TICK")
	assert_true(c.is_jailed(), "−350 違反 −299 → 坐牢")
	# classic_strict（EXPEL，2001-08）：−150 就開除
	c.jail = {}
	use_preset("classic_strict")
	install_sect({}, _mode_rules())
	c.sect = SID
	c.sect_record["breached"] = {}
	c.morality = -150
	ids = sects().rules_of(SID, "STATE").map(func(r): return str(r["id"]))
	assert_eq(ids, ["ts_r_expel"])
	sects().check_state(s(), "TICK")
	assert_eq(str(c.sect), "", "EXPEL 模式：2001-08 叛派線 −99 → 開除")
	assert_true(c.sect_traitor.has(SID))

func test_on_npc_rule_triggers_on_talk_only() -> void:
	if not game_ok():
		return
	use_preset("classic_strict")
	install_sect({}, _mode_rules())
	var c = member("交談俠")
	c.sect = SID
	c.morality = -60
	goto(GATE)
	goto(HALL)
	assert_eq(str(c.sect), SID, "走路、TICK 不檢查 on_npc 規則")
	sects().check_state(s(), "TICK")
	assert_eq(str(c.sect), SID)
	ok("talk", { "npc": HEAD })
	assert_eq(str(c.sect), "", "善惡 −60 跟掌門交談 → 2001-08 叛派")

func test_traitor_cannot_rejoin_after_enemy_jail() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("叛徒俠")
	goto(HALL)
	ok("join_sect", { "npc": HEAD })
	assert_eq(str(c.sect), SID)
	ok("sect_betray", { "npc": HEAD, "confirm": true })
	assert_true(c.sect_enemies.has(SID))
	assert_true(c.sect_traitor.has(SID))
	# 被本派守衛殺死 → 公敵坐牢 3 遊戲日 → 期滿改過自新（移出公敵）
	var cap: Dictionary = sects().capture_on_death(s(), c, { "kind": "MONSTER", "killed_by": { "kind": "MONSTER", "ref": GUARD } })
	assert_true(bool(cap.get("jail", false)))
	fast_forward(1.0)
	fast_forward(3 * 7200.0 + 5.0)
	assert_false(c.is_jailed(), "期滿出獄")
	assert_false(c.sect_enemies.has(SID), "改過自新：不再是公敵（敵對入山不再觸發）")
	assert_true(c.sect_traitor.has(SID), "叛徒記號還在")
	goto(HALL)
	assert_eq(reason("join_sect", { "npc": HEAD }), "req_not_enemy_of", "叛徒永遠不能再拜入")
	# 存檔還原後一樣
	var c2 := Character.from_dict(c.to_dict())
	assert_true(c2.sect_traitor.has(SID))

func test_lingering_poison_not_reset_by_short_fights() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("中毒俠")
	make_strong()
	c.add_condition("poison", 10, 20, c.online_s + 120.0)
	var next0 := float(c.conditions["poison"]["next_online_s"])
	# 打一場：戰鬥中照樣帶著中毒，但角色身上的持續狀態不會被拿掉再用滿額重設
	start_battle(["m_rabbit"])
	assert_true(s().battle_id != 0)
	assert_true(c.conditions.has("poison"), "進戰鬥不清掉戰後持續狀態")
	drive_battle("fight")
	assert_true(c.conditions.has("poison"), "還沒結束")
	var e: Dictionary = c.conditions["poison"]
	assert_eq(int(e["ticks_left"]), 20, "發作次數沒有被重設成滿額（10 級 × 2 = 20 才是原本的值；也沒有增加）")
	assert_true(float(e["next_online_s"]) <= maxf(next0, c.online_s) + 0.001, "下次發作時刻沒有往後延")
	assert_true(e.has("actions_left"), "記下戰鬥中剩下的行動次數")
	var left := int(e["actions_left"])
	assert_true(left < 6, "戰鬥中用掉了行動次數（剩 %d）" % left)
	# 下一場帶進去的是剩下的次數
	var spec: Dictionary = c.to_combatant(tables(), ws.options, 0, 1)
	if left > 0:
		assert_eq(int(spec["statuses"]["poison"]["n"]), left)
	else:
		assert_false(spec["statuses"].has("poison"), "戰鬥中的次數用完就不再帶進戰鬥")
	# 戰後照樣每 2 分鐘發作
	clear_events()
	fast_forward(121.0)
	assert_true(evs(Protocol.E_POISON_FLARE).size() >= 1)
	assert_eq(int(c.conditions["poison"]["ticks_left"]), 19)

func test_trial_cannot_be_joined_mid_fight() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("試煉俠")
	c.sect = SID
	make_strong()
	var p2 := add_player("路過的隊友")
	session_of(p2).character.sect = SID
	ok("party_invite", { "target": str(session_of(p2).character.id) })
	assert_true(send_as(p2, "party_reply", { "from": str(c.id), "accept": true }).get("ok", false))
	goto_as(p2, GATE)
	goto(HALL)
	var r := send("sect_trial", { "npc": TRIAL })
	assert_true(r.get("ok", false), str(r))
	var bid := s().battle_id
	assert_true(bid != 0)
	goto_as(p2, HALL)
	assert_eq(session_of(p2).battle_id, 0, "沒被拉進去（開陣時不在場）")
	assert_eq(reason_as(p2, "battle_join", { "battle_id": bid }), "join_not_allowed", "試煉不能中途加入")

func test_sect_skill_learning_uses_train_cost() -> void:
	if not game_ok():
		return
	# 觸發消耗（精＋內力）≠ 學習消耗：train_cost 只有神
	install_sect({ "sect_skill_cost": ["jing", "neili"], "sect_skill_train_cost": ["shen"] })
	var c = member("學藝俠")
	c.sect = SID
	c.learn_points = 50
	c.vitals["neili"] = 0
	goto(HALL)
	var res := Learning.learn(c, HEAD, SKILL, 1, tables(), ws.options, host().rules)
	assert_true(bool(res["ok"]), "內力 0 也學得了（不再要求先練基本內功、打坐）：%s" % str(res))
	assert_eq(int(res["neili_cost"]), 0)
	assert_eq(int(res["shen_cost"]), 2)
