extends "res://tests/unit/test_pk_world_base.gd"
## M3D_PLAN §2.6、R6、A8（WP-LAW）：PK值 被動遞減由規則 pk_decay 控制（classic_strict 關＝2001 沒有被動遞減；其他保留 30 分鐘）；
## add_pk 可以是負數、最低 0；GameHost 依規則設 Character.pk_decay_on（不存檔）；守城官兵殺死 PK值 −1。

func before_each() -> void:
	world_name = "w_m3d_pkdecay"
	super.before_each()

func test_pure_decay_switch() -> void:
	assert_eq(MoralityPk.pk_value(3, 0.0, 3600.0), 1, "decay on: −1 per 1800 s")
	assert_eq(MoralityPk.pk_value(3, 0.0, 3600.0, true), 1)
	assert_eq(MoralityPk.pk_value(3, 0.0, 3600.0, false), 3, "decay off: unchanged")
	assert_eq(MoralityPk.pk_value(0, 0.0, 99999.0, false), 0)

func test_character_flag_and_negative_add() -> void:
	var c := Character.new()
	c.pk = 2
	c.pk_stamp_s = 0.0
	c.online_s = 7200.0
	c.pk_decay_on = false
	assert_eq(c.pk_value(), 2, "classic_strict: 2 hours online, still 2")
	c.pk_decay_on = true
	assert_eq(c.pk_value(), 0, "decay on: 2 hours → 0")
	c.pk = 3
	c.pk_stamp_s = c.online_s
	assert_eq(c.add_pk(-1), 2)
	assert_eq(c.add_pk(-5), 0, "floor 0")
	assert_false(c.to_dict().has("pk_decay_on"), "runtime field is not saved")

func test_rule_profiles_values() -> void:
	var l := DataLoader.new()
	l.load_all("res://data")
	var rp: Dictionary = l.all_tables.get("rule_profiles", {})
	assert_eq(rp["classic_strict"]["rules"]["pk_decay"], false, "classic_strict: no passive decay (2001)")
	assert_eq(rp["classic_standard"]["rules"]["pk_decay"], true)
	assert_eq(rp["later_official"]["rules"]["pk_decay"], true)
	assert_eq(rp["friends_casual"]["rules"]["pk_decay"], true)
	assert_eq(DataSchema.RULE_DEFAULTS["pk_decay"], true, "custom profiles keep the old behaviour")
	assert_eq(rp["later_official"]["rules"]["dodge_cmd"], false, "閃 removed 2002-01-25")
	assert_eq(DataSchema.RULE_DEFAULTS["trade_sell_bonus"], false)

func test_host_sets_flag_from_rules() -> void:
	if not deps_ok():
		return
	var a := add("甲俠")
	ws.advance(0.1)
	assert_true(chr(a).pk_decay_on, "classic_standard (default) → decay on")
	use_preset("classic_strict")
	ws.advance(0.1)
	assert_false(chr(a).pk_decay_on, "classic_strict → decay off")
	var c = chr(a)
	c.pk = 2
	c.pk_stamp_s = c.online_s
	c.online_s += 7200.0
	assert_eq(int(c.pk_value()), 2, "strict: 2 hours online, still 2")
	use_preset("classic_standard")
	ws.advance(0.1)
	assert_true(chr(a).pk_decay_on)
	assert_eq(int(c.pk_value()), 0, "standard: 2 hours → 0")

func test_guard_kill_lowers_pk() -> void:
	if not deps_ok():
		return
	var law = host().get("law")
	if law == null:
		fail("LawSystem 沒有載入")
		return
	var a := add("甲俠")
	var c = chr(a)
	c.pk = 5
	c.pk_stamp_s = c.online_s
	c.combat_xp = 5000
	goto_p(a, "xw_road")
	make_weak_p(a)
	var settled := FileAccess.get_file_as_string("res://server/battle_system.gd").contains("m3d_battle_settled")
	# 進城 → 官兵（PK > 3 → 2 名）
	goto_p(a, "xx_gate_e")
	var bid := sess(a).battle_id
	if bid == 0:
		host().pk.on_move(sess(a), "xw_road", "xx_gate_e")
		bid = sess(a).battle_id
	assert_true(bid != 0, "guards attack")
	assert_eq(active_kind(a), "GUARD")
	drive_bid(bid, { a: "defend" })
	if not settled:
		law.on_battle_settled(sess(a), c, { "kind": "GUARD", "bid": bid, "died": true })
	assert_eq(int(c.pk_value()), 4, "killed by city guards: PK −1【已證實 xinshou/21】")
