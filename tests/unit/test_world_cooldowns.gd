extends "res://tests/unit/test_world_fixture.gd"
## 動作冷卻（修煉內力、生活技能）由主機決定：角色表 sheet.cooldowns 帶剩餘真實秒數（尊重 time_scale），
## busy 的失敗結果帶 cooldown 與 left_s，並經 intent_result 的附加欄位送到客戶端，「你正忙著，還要 N 秒。」；
## 精不足的提示：戰鬥外叫人去客棧住宿或稍等，戰鬥中出招用另一句（M1_PLAN 3.5.3 第 7 點、3.7、3.9.1）。

func before_each() -> void:
	world_name = "w_cooldowns"
	super.before_each()

func after_each() -> void:
	ws.set_time_scale(1.0)
	super.after_each()

func _cd(key: String) -> float:
	return float(sheet().get("cooldowns", {}).get(key, -1.0))

func _inner() -> void:
	ch().skills.set_level("basic_inner", 5, tables())
	ch().vitals["neili"] = 0

func test_sheet_cooldowns_start_right_after_meditate() -> void:
	if not game_ok():
		return
	make_char()
	_inner()
	assert_eq(_cd("meditate"), 0.0, "ready before")
	assert_eq(_cd("life"), 0.0, "life key present")
	ok("meditate")
	# 成功的 intent 之後已經強制送出角色表：倒數立刻開始
	assert_true(absf(_cd("meditate") - Survival.MEDITATE_COOLDOWN_S) < 0.01, "meditate cooldown %f" % _cd("meditate"))
	ws.advance(4.0)
	s().sheet_dirty = true
	host().flush_session(s(), true)
	ws.flush()
	assert_true(absf(_cd("meditate") - 6.0) < 0.01, "computed at send time: %f" % _cd("meditate"))

func test_meditate_busy_payload_and_text() -> void:
	if not game_ok():
		return
	make_char()
	_inner()
	ok("meditate")
	ws.advance(2.5)
	var r := send("meditate")
	assert_eq(str(r.get("reason", "")), "busy")
	assert_eq(str(r.get("cooldown", "")), "meditate")
	assert_eq(int(r.get("left_s", 0)), 8, "ceil(7.5)")
	# 客戶端：結果的附加欄位與角色表都帶到了
	assert_eq(int(cs.last_result_extra.get("left_s", 0)), 8)
	assert_true(absf(_cd("meditate") - 7.5) < 0.01, "sheet re-sent with the busy failure: %f" % _cd("meditate"))
	assert_eq(UiClient.reason_text("busy"), "【系統】你正忙著，還要 8 秒。")
	assert_eq(UiClient.reason_inline("busy"), "你正忙著，還要 8 秒。")
	# 其他結果清掉附加欄位
	ok("look")
	assert_true(cs.last_result_extra.is_empty())

func test_time_scale_converts_to_real_seconds() -> void:
	if not game_ok():
		return
	make_char()
	_inner()
	ws.set_time_scale(2.0)
	ok("meditate")
	assert_true(absf(_cd("meditate") - Survival.MEDITATE_COOLDOWN_S / 2.0) < 0.01, "real seconds at ×2: %f" % _cd("meditate"))
	var r := send("meditate")
	assert_eq(int(r.get("left_s", 0)), 5)

func test_life_cooldown_and_busy() -> void:
	if not game_ok():
		return
	make_char()
	goto("xw_wood")
	ok("learn", { "npc": "n_xw_woodcutter", "skill": "life_woodcut" })
	Survival.rest_full(ch(), tables(), ws.options)
	ok("work", { "skill": "life_woodcut" })
	var cd_s := float(tables()["life_skills"]["life_woodcut"].get("cooldown_s", 5))
	assert_true(absf(_cd("life") - cd_s) < 0.01, "life cooldown %f" % _cd("life"))
	assert_eq(_cd("meditate"), 0.0)
	var r := send("work", { "skill": "life_woodcut" })
	assert_eq(str(r.get("reason", "")), "busy")
	assert_eq(str(r.get("cooldown", "")), "life")
	assert_eq(int(r.get("left_s", 0)), int(ceil(cd_s)))
	assert_eq(UiClient.reason_text("busy"), "【系統】你正忙著，還要 %d 秒。" % int(ceil(cd_s)))
	ws.advance(cd_s + 0.1)
	ok("work", { "skill": "life_woodcut" })

func test_not_enough_jing_text_outside_battle() -> void:
	if not game_ok():
		return
	make_char()
	_inner()
	ch().vitals["jing"] = 0
	assert_eq(reason("meditate"), "not_enough_jing")
	assert_eq(UiClient.reason_text("not_enough_jing"), "【系統】精不足：到客棧住宿或稍等片刻。")
	assert_eq(UiClient.reason_inline("not_enough_jing"), "精不足：到客棧住宿或稍等片刻。")

func test_not_enough_jing_in_battle_uses_battle_text() -> void:
	if not game_ok():
		return
	make_char()
	make_strong()
	ch().skills.set_level("sl_changquan", 1, tables())
	var mv: Dictionary = tables()["martial_arts"]["sl_changquan"]["moves"][0]
	var saved := [mv["cost_jing"], mv["range"]]
	mv["cost_jing"] = 99999   # 真資料沒有耗精的招式：暫時改表
	mv["range"] = 99
	start_battle(["m_rabbit"])
	var bid: int = s().battle_id
	assert_true(bid != 0, "battle started")
	var b = host().battles.active[bid]["battle"]
	var me = _my_unit_by_peer(b)
	var waited := 0
	while me != null and not b._pending.has(me) and waited < 4000:
		ws.advance(0.05)
		waited += 1
	assert_true(me != null and b._pending.has(me), "my turn")
	var foe = null
	for u in b.units:
		if int(u.side) != int(me.side) and u.is_active():
			foe = u
	assert_true(foe != null, "an enemy")
	if foe != null:
		var r := send("battle_cmd", { "battle_id": bid, "cmd": "ART", "art": "sl_changquan", "move": "sl_cq_1",
			"power_tenths": 10, "target": [foe.pos.x, foe.pos.y] })
		assert_eq(str(r.get("reason", "")), "battle_not_enough_jing")
		assert_eq(UiClient.reason_inline("battle_not_enough_jing"), "精不足，使不出這一招。")
	mv["cost_jing"] = saved[0]
	mv["range"] = saved[1]

func _my_unit_by_peer(b):
	for u in b.units:
		if int(u.peer) == 1:
			return u
	return null
