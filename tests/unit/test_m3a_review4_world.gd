extends "res://tests/unit/test_world_sect_fixture.gd"
## M3a 審查（第 4 輪，原作忠實度）主機部分的回歸測試：
## - #1 恆山犯戒（breach_outcome LOCKOUT）：JAIL／BAN 模式違規 → 不坐牢、不是 1 天禁武，而是山門以外進不去、本派師父不教，
##   直到向山門的 repent_npc 悔過（狀態門規都已符合）；EXPEL 模式照樣開除；
## - #2 古墓迷宮遇敵不能逃（encounter.no_flee，踩地雷與查看偵察迎戰都一樣）；
## - #3 全真看門的不讓邪惡的人上山（同隊同房 2 人以上、或全真弟子可以）；
## - #5 classic_strict（2001-08）沒有思過處。

func before_each() -> void:
	world_name = "w_m3a_review4"
	super.before_each()

## 恆山型的測試門派：沒有執法者、沒有思過處、違規＝犯戒，山門的引路人當悔過對象
func _install_lockout_sect() -> void:
	install_sect({ "enforcer": false, "enforcers": [], "jail_room": "", "hostile_entry": [],
		"breach_outcome": "LOCKOUT", "repent_npc": GUIDE })

func test_lockout_instead_of_jail_or_ban() -> void:
	if not game_ok():
		return
	_install_lockout_sect()
	assert_eq(sects().effective_mode(SID), "LOCKOUT", "預設規則（JAIL）：恆山型門派違規＝犯戒")
	var c = member("犯戒俠", "F")
	c.sect = SID
	goto(HALL)
	clear_events()
	c.morality = -150
	sects().check_state(s(), "TICK")
	ws.flush()
	assert_false(c.is_jailed(), "沒有思過處：不坐牢")
	assert_eq(str(c.sect), SID, "不是開除")
	assert_true(c.is_locked_out())
	assert_eq(c.ban_left_s(), 0.0, "不是 1 天的禁止學武（研究沒有期限：直到悔過）")
	assert_eq(str(lastp("sect_breach").get("outcome", "")), "LOCKOUT")
	assert_eq(s().room_id(), GATE, "人在山門以內 → 送到山門")
	# 山門以外進不去、本派師父不教
	assert_eq(reason("move", { "dir": "N" }), "room_locked")
	assert_eq(host().regions.lock_reason(c, HALL), "req_sect_lockout")
	assert_eq(host().regions.lock_reason(c, GATE), "", "山門本身可以站")
	assert_eq(sects().can_teach(s(), HEAD), "sect_lockout")
	# 一天後還是進不去（沒有期限）
	fast_forward(host().day_s() * 2.0)
	assert_true(c.is_locked_out(), "犯戒沒有期限")
	# 還沒改過：悔過不成
	clear_events()
	ok("talk", { "npc": GUIDE })
	assert_false(evs("sect_repent_refused").is_empty(), "善惡還是 −150：悔過不成")
	assert_true(c.is_locked_out())
	# 改過之後悔過 → 解除
	c.morality = 10
	clear_events()
	ok("talk", { "npc": GUIDE })
	assert_false(evs("sect_repent").is_empty())
	assert_false(c.is_locked_out())
	ok("move", { "dir": "N" })
	assert_eq(s().room_id(), HALL)
	assert_eq(sects().can_teach(s(), HEAD), "")

func test_lockout_teleports_after_battle_and_on_tick() -> void:
	if not game_ok():
		return
	_install_lockout_sect()
	var c = member("戰後犯戒俠", "F")
	c.sect = SID
	goto(INNER)
	c.sect_record["lockout"] = "ts_r_morality"   # 例：戰鬥中犯戒，戰後由 ConditionSystem 送出去
	fast_forward(1.0)
	assert_eq(s().room_id(), GATE)

func test_lockout_modes() -> void:
	if not game_ok():
		return
	# BAN 模式（friends_casual）：一樣是犯戒
	use_preset("friends_casual")
	_install_lockout_sect()
	assert_eq(sects().effective_mode(SID), "LOCKOUT")
	# EXPEL（classic_strict，2001-08 叛派名單）：照樣開除
	use_preset("classic_strict")
	_install_lockout_sect()
	assert_eq(sects().effective_mode(SID), "EXPEL")
	var c = member("開除俠", "F")
	c.sect = SID
	c.morality = -150
	sects().check_state(s(), "TICK")
	assert_eq(str(c.sect), "")
	assert_false(c.is_locked_out(), "離開門派就沒有犯戒")

func test_real_hengshan_uses_lockout() -> void:
	if not game_ok():
		return
	assert_eq(str(t()["sects"]["hengshan"].get("breach_outcome", "")), "LOCKOUT")
	assert_eq(sects().effective_mode("hengshan"), "LOCKOUT")
	assert_eq(str(t()["npcs"][str(t()["sects"]["hengshan"]["repent_npc"])]["room"]), "hg_gate")
	var c = member("恆山犯戒", "F")
	c.sect = "hengshan"
	c.sect_record["lockout"] = "hg_r_pk"
	assert_eq(host().regions.lock_reason(c, "hg_square"), "req_sect_lockout")
	assert_eq(host().regions.lock_reason(c, "hg_gate"), "")
	assert_eq(host().regions.lock_reason(c, "hf_paddy"), "", "山下不受影響")
	# 存檔來回：犯戒記號保留
	var back = Character.from_dict(c.to_dict())
	assert_true(back.is_locked_out())

func test_gumu_maze_encounters_cannot_flee() -> void:
	if not game_ok():
		return
	member("硬闖俠", "F")
	for rid in ["gm_mz_1", "gm_mz_2", "gm_mz_dead", "gm_mz_3", "gm_mz_4"]:
		assert_true(bool(host().index.room(rid).get("encounter", {}).get("no_flee", false)), rid + " no_flee")
	goto("gm_mz_2")
	var bid: int = host().regions.start_encounter(s(), ["m_gm_bianfu"])
	assert_true(bid > 0)
	var b: Battle = host().battles.active[bid]["battle"]
	assert_true(bool(b.opts.get("no_flee", false)), "迷宮遇敵不能逃（17173 2001-07-05）")
	# 野外一般遇敵仍然可以逃
	assert_false(bool(host().index.room("xw_road").get("encounter", {}).get("no_flee", false)))

func test_quanzhen_gatekeeper_refuses_evil() -> void:
	if not game_ok():
		return
	host().options["sect_hostile_entry"] = false
	var c = member("邪惡俠")
	goto("qz_gate")
	c.morality = -400
	assert_eq(reason("move", { "dir": "N" }), "room_locked", "邪惡的人自己上不了山")
	assert_eq(host().regions.lock_reason(c, "qz_road", host().sects.req_ctx(s())), "req_any_of")
	# 有同隊、同在山門的隊友（2 人以上）＝隊友帶上山
	assert_eq(host().regions.lock_reason(c, "qz_road", { Requirements.CTX_PARTY_SIZE: 2 }), "")
	c.morality = 0
	ok("move", { "dir": "N" })
	assert_eq(s().room_id(), "qz_road")

func test_classic_strict_has_no_jail() -> void:
	if not game_ok():
		return
	use_preset("classic_strict")
	assert_eq(GameData.rules.get("jail_enabled"), false, "門派監獄 2001-10-05（1.0B）才有")
	assert_false(sects().can_jail_in("shaolin"))
	use_preset("classic_standard")
	assert_true(sects().can_jail_in("shaolin"), "預設規則照 GDD 保留坐牢")
