extends "res://tests/unit/test_world_sect_fixture.gd"
## 戰後持續狀態（M3A_PLAN 6.10、K4）：中毒發作與到期、不致死、解毒藥（戰鬥外）、選項關閉、角色表 conditions、
## 上線秒數不隨 --time-scale 縮放。

func before_each() -> void:
	world_name = "w_cond"
	super.before_each()

func after_each() -> void:
	ws.set_time_scale(1.0)
	super.after_each()

func _poisoned(level := 2):
	install_sect()
	var c = member("中毒俠")
	c.add_condition("poison", level, level * 2, c.online_s + 120.0)
	return c

func test_flare_and_expire() -> void:
	if not game_ok():
		return
	var c = _poisoned(2)
	var qi0 := int(c.vitals["qi"])
	var qmax := int(c.derived(tables(), ws.options)["qi_max"])
	clear_events()
	fast_forward(60.0)
	assert_eq(evs(Protocol.E_POISON_FLARE).size(), 0, "還沒到 120 秒")
	fast_forward(61.0)
	assert_eq(evs(Protocol.E_POISON_FLARE).size(), 1, "第一次發作")
	var p := lastp(Protocol.E_POISON_FLARE)
	var dmg := maxi(1, roundi(qmax * 0.03))
	assert_eq(int(p.get("dmg", 0)), mini(dmg, qi0 - 1))
	assert_eq(int(c.vitals["qi"]), qi0 - mini(dmg, qi0 - 1))
	assert_eq(int(c.conditions["poison"]["ticks_left"]), 3)
	refresh_sheet()
	var conds: Array = sheet().get("conditions", [])
	assert_eq(conds.size(), 1, "角色表 conditions")
	assert_eq(str(conds[0]["id"]), "poison")
	assert_eq(int(conds[0]["level"]), 2)
	assert_true(float(conds[0]["left_s"]) > 300.0, "剩 3 次 × 120 秒")
	fast_forward(400.0)
	assert_eq(evs(Protocol.E_POISON_FLARE).size(), 4, "共 等級×2 = 4 次")
	assert_false(c.conditions.has("poison"), "到期移除")
	assert_eq(evs(Protocol.E_CONDITION_OFF).size(), 1)

func test_flare_never_kills() -> void:
	if not game_ok():
		return
	var c = _poisoned(10)
	c.vitals["qi"] = 2
	fast_forward(121.0)
	assert_eq(int(c.vitals["qi"]), 1, "扣到 1 為止")
	fast_forward(240.0)
	assert_eq(int(c.vitals["qi"]), 1, "不致死")

func test_antidote_outside_battle() -> void:
	if not game_ok():
		return
	var c = _poisoned(3)
	var uid := give(ANTIDOTE, 2)
	clear_events()
	ok("use_item", { "item_uid": uid })
	assert_false(c.conditions.has("poison"), "解毒")
	assert_eq(evs(Protocol.E_CONDITION_OFF).size(), 1)
	# 等級超過 max_level 解不掉
	c.add_condition("poison", 8, 16, c.online_s + 120.0)
	ok("use_item", { "item_uid": first_uid(ANTIDOTE) })
	assert_eq(c.condition_level("poison"), 8, "等級 8 > 5 解不掉")

func test_option_off_removes() -> void:
	if not game_ok():
		return
	var c = _poisoned(2)
	ws.options["poison_flare_enabled"] = false
	var qi0 := int(c.vitals["qi"])
	clear_events()
	fast_forward(1.0)
	assert_false(c.conditions.has("poison"), "不發作、直接移除")
	assert_eq(evs(Protocol.E_POISON_FLARE).size(), 0)
	assert_eq(int(c.vitals["qi"]), qi0)

func test_online_seconds_ignore_time_scale() -> void:
	if not game_ok():
		return
	install_sect()
	var c = member("時間俠")
	var t0: float = c.online_s
	ws.set_time_scale(10.0)
	ws.advance(10.0)   # 世界時間 10 秒 = 真實 1 秒
	assert_true(absf(c.online_s - t0 - 1.0) < 0.05, "上線秒 = 真實秒（K4）：%f" % (c.online_s - t0))

func test_conditions_carry_into_combatant() -> void:
	if not game_ok():
		return
	var c = _poisoned(3)
	var spec: Dictionary = c.to_combatant(tables(), ws.options, 0, 1)
	assert_eq(spec.get("statuses", {}).get("poison", {}).get("level", 0), 3)
	assert_eq(int(spec["statuses"]["poison"]["n"]), 6, "次數 = duration_actions")
