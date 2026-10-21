extends "res://tests/unit/test_world_fixture.gd"
## M3D_PLAN §3.6、§10.1（WP-COMBAT）：換裝兩秒間隔（2001-10-09；R9 全域）——
## 地圖上 equip／unequip 2 秒、戰鬥中 EQUIP 2 秒（戰鬥時間、開戰前換過不算）、選項 0 關。

const H := preload("res://tests/unit/test_battle_helpers.gd")

func _setup() -> bool:
	if not game_ok():
		return false
	if make_char("換裝俠客", "xixia") == null:
		return false
	return true

func test_map_equip_cooldown() -> void:
	if not _setup():
		return
	var a := give("w_mujian")
	var b := give("w_dandao")
	s().last_equip_ms = -100000
	ok("equip", { "item_uid": a })
	assert_eq(reason("equip", { "item_uid": b }), "equip_cooldown", "1 秒內再換 → equip_cooldown")
	assert_eq(reason("unequip", { "slot": "WEAPON" }), "equip_cooldown", "卸下也算")
	s().last_equip_ms = Time.get_ticks_msec() - 1000
	assert_eq(reason("equip", { "item_uid": b }), "equip_cooldown", "1 秒前換過")
	s().last_equip_ms = Time.get_ticks_msec() - 2100
	ok("equip", { "item_uid": b })
	assert_eq(str(ch().inventory.equipped.get("WEAPON", "")), b, "2.1 秒後成功")
	# 失敗的換裝不重設計時
	s().last_equip_ms = Time.get_ticks_msec() - 2100
	assert_true(reason("equip", { "item_uid": "no_such" }) != "equip_cooldown")
	ok("equip", { "item_uid": a })

func test_map_option_zero() -> void:
	if not _setup():
		return
	ws.options["equip_cooldown_ms"] = 0
	var a := give("w_mujian")
	var b := give("w_dandao")
	ok("equip", { "item_uid": a })
	ok("equip", { "item_uid": b })
	ok("unequip", { "slot": "WEAPON" })
	assert_eq(IntentsItem.equip_cooldown_ms(host()), 0)
	ws.options["equip_cooldown_ms"] = 99999
	assert_eq(IntentsItem.equip_cooldown_ms(host()), 5000, "上限 5000")

func test_combatant_carries_option() -> void:
	if not _setup():
		return
	assert_eq(int(ch().to_combatant(tables(), ws.options, 0, 1).get("equip_cd_ms", -1)), 2000, "預設 2000")
	ws.options["equip_cooldown_ms"] = 0
	assert_eq(int(ch().to_combatant(tables(), ws.options, 0, 1).get("equip_cd_ms", -1)), 0)

## 戰鬥：戰鬥時間 2 秒內第二次 EQUIP → equip_cooldown；開戰前在地圖上換過不影響
func test_battle_equip_cooldown() -> void:
	var b := H.make_battle([H.player_spec({ "equip_cd_ms": 2000 }), H.monster("m_dummy")], 5)
	b.tick_no = 30
	assert_eq(H.do_cmd(b, 1, { "cmd": "EQUIP", "item_uid": "it_0002" }).err, "", "開戰後第一次換裝沒問題")
	assert_true(approx(b.unit(1).last_equip_t, 3.0))
	b.tick_no = 49
	assert_eq(H.do_cmd(b, 1, { "cmd": "EQUIP", "item_uid": "it_0001" }).err, "equip_cooldown", "1.9 秒")
	b.tick_no = 50
	assert_eq(H.do_cmd(b, 1, { "cmd": "EQUIP", "item_uid": "it_0001" }).err, "", "2.0 秒")
	# 選項 0（spec.equip_cd_ms 0）→ 不限制
	var b0 := H.make_battle([H.player_spec({ "equip_cd_ms": 0 }), H.monster("m_dummy")], 5)
	assert_eq(H.do_cmd(b0, 1, { "cmd": "EQUIP", "item_uid": "it_0002" }).err, "")
	assert_eq(H.do_cmd(b0, 1, { "cmd": "EQUIP", "item_uid": "it_0001" }).err, "")
	# 舊規格沒有 equip_cd_ms：看 opts.equip_cooldown_ms，都沒有 → 不限制（金檔不變）
	var b1 := H.make_battle([H.player_spec(), H.monster("m_dummy")], 5, { "equip_cooldown_ms": 2000 })
	assert_eq(H.do_cmd(b1, 1, { "cmd": "EQUIP", "item_uid": "it_0002" }).err, "")
	assert_eq(H.do_cmd(b1, 1, { "cmd": "EQUIP", "item_uid": "it_0001" }).err, "equip_cooldown")
	var b2 := H.make_battle([H.player_spec(), H.monster("m_dummy")], 5)
	assert_eq(H.do_cmd(b2, 1, { "cmd": "EQUIP", "item_uid": "it_0002" }).err, "")
	assert_eq(H.do_cmd(b2, 1, { "cmd": "EQUIP", "item_uid": "it_0001" }).err, "")

static func approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

## M3d 審查（第 3 輪）：兩秒間隔是 2001-10-09（1.0B 之後）的更新 → 1.0A-only 世界不限制（地圖與戰鬥都是）
func test_1_0a_world_no_cooldown() -> void:
	if not _setup():
		return
	use_eras(["1.0A"])
	assert_eq(IntentsItem.equip_cooldown_ms(host()), 0, "1.0A-only：不限制")
	var a := give("w_mujian")
	var b := give("w_dandao")
	ok("equip", { "item_uid": a })
	ok("equip", { "item_uid": b })
	assert_eq(str(ch().inventory.equipped.get("WEAPON", "")), b, "1.0A 連換兩次")
	var bid := start_battle(["m_rabbit"])
	assert_true(bid != 0)
	var bt = host().battles.active[bid]["battle"]
	for u in bt.units:
		if u.is_player():
			assert_eq(u.equip_cd_ms(), 0, "1.0A 戰鬥中也不限制")
	use_eras(["1.0A", "1.0B"])
	assert_eq(IntentsItem.equip_cooldown_ms(host()), 2000, "1.0B 世界照選項")
