extends "res://tests/test_case.gd"
## M3C_PLAN §8 協定增量（WP-NPCPK Day-0）：新 intent、可選參數、範圍、列舉、事件與原因碼常數；UiKeys 照抄同值；
## §9.2 規則、§9.3 伺服器選項、§9.4 Schema 常數。VERSION 維持 5（N1）。

func _v(kind: String, args: Dictionary) -> String:
	return Protocol.validate_args(kind, args)

func test_version_unchanged() -> void:
	assert_eq(Protocol.VERSION, 5, "N1：M3c 純新增，VERSION 維持 5")

func test_new_intents_known() -> void:
	for k in ["set_look", "npc_attack", "manual_read"]:
		assert_true(Protocol.is_known(k), k)
	assert_eq(Protocol.I_SET_LOOK, "set_look")
	assert_eq(Protocol.I_NPC_ATTACK, "npc_attack")
	assert_eq(Protocol.I_MANUAL_READ, "manual_read")
	assert_eq(Protocol.LOOK_MAX, 8)
	assert_eq(Protocol.NPC_ATTACK_MODES, ["ATTACK", "MIEPAI"])

func test_char_create_look_optional_and_ranged() -> void:
	var good := { "name": "測試俠客", "gender": "M", "birth_month": 3, "birth_city": "xixia", "alloc": { "wit": 5 } }
	assert_eq(_v("char_create", good), "", "舊客戶端不帶 look")
	for lk in [0, 5, 8]:
		var a := good.duplicate()
		a["look"] = lk
		assert_eq(_v("char_create", a), "", "look %d" % lk)
	for lk in [-1, 9]:
		var b := good.duplicate()
		b["look"] = lk
		assert_eq(_v("char_create", b), "bad_value:look", "look %d" % lk)
	var c := good.duplicate()
	c["look"] = "3"
	assert_eq(_v("char_create", c), "bad_type:look")

func test_set_look() -> void:
	assert_eq(_v("set_look", { "look": 0 }), "")
	assert_eq(_v("set_look", { "look": 8 }), "")
	assert_eq(_v("set_look", { "look": 9 }), "bad_value:look")
	assert_eq(_v("set_look", {}), "missing_arg:look")
	assert_eq(_v("set_look", { "look": 1, "x": 1 }), "unexpected_arg")

func test_npc_attack() -> void:
	assert_eq(_v("npc_attack", { "npc": "n_dl_cunmin" }), "", "mode 可省")
	assert_eq(_v("npc_attack", { "npc": "n_dl_cunmin", "mode": "ATTACK" }), "")
	assert_eq(_v("npc_attack", { "npc": "n_wd_zhike", "mode": "MIEPAI" }), "")
	assert_eq(_v("npc_attack", { "npc": "n_wd_zhike", "mode": "KILL" }), "bad_value:mode")
	assert_eq(_v("npc_attack", {}), "missing_arg:npc")
	assert_eq(_v("npc_attack", { "npc": 3 }), "bad_type:npc")
	assert_eq(_v("npc_attack", { "npc": "x".repeat(65) }), "bad_value:npc")

func test_manual_read() -> void:
	assert_eq(_v("manual_read", { "item_uid": "it_1" }), "")
	assert_eq(_v("manual_read", { "item_uid": "it_1", "times": 10 }), "")
	assert_eq(_v("manual_read", { "item_uid": "it_1", "times": 0 }), "bad_value:times")
	assert_eq(_v("manual_read", { "item_uid": "it_1", "times": 11 }), "bad_value:times")

func test_unequip_eight_slots() -> void:
	assert_eq(Protocol.SLOTS, ["WEAPON", "ARMOR", "HEAD", "NECK", "WRIST", "CLOAK", "RING", "BOOTS"])
	for sl in Protocol.SLOTS:
		assert_eq(_v("unequip", { "slot": sl }), "", sl)
	assert_eq(_v("unequip", { "slot": "HAT" }), "bad_value:slot")

func test_event_and_reason_constants() -> void:
	for k in ["look_changed", "na_attack_start", "na_npc_killed", "na_npc_routed", "na_npc_back", "na_guard_alarm",
			"na_sect_enemy", "na_master_betray", "na_miepai", "lt_rare_drop", "lt_divine_transfer", "lt_manual_read"]:
		assert_true(k in [Protocol.E_LOOK_CHANGED, Protocol.E_NA_ATTACK_START, Protocol.E_NA_NPC_KILLED,
			Protocol.E_NA_NPC_ROUTED, Protocol.E_NA_NPC_BACK, Protocol.E_NA_GUARD_ALARM, Protocol.E_NA_SECT_ENEMY,
			Protocol.E_NA_MASTER_BETRAY, Protocol.E_NA_MIEPAI, Protocol.E_LT_RARE_DROP, Protocol.E_LT_DIVINE_TRANSFER,
			Protocol.E_LT_MANUAL_READ], k)
	assert_eq(Protocol.M3C_REASONS, ["bad_look", "npc_attack_off", "npc_not_attackable", "npc_safe_room", "npc_busy",
		"manuals_off", "not_manual", "manual_illiterate", "manual_cap", "divine_locked", "npc_routed"])
	assert_eq(Protocol.M3C_UI_EVENTS, ["look_changed"])

func test_ui_keys_mirror_protocol() -> void:
	assert_eq(UiKeys.I_SET_LOOK, Protocol.I_SET_LOOK)
	assert_eq(UiKeys.I_NPC_ATTACK, Protocol.I_NPC_ATTACK)
	assert_eq(UiKeys.I_MANUAL_READ, Protocol.I_MANUAL_READ)
	assert_eq(UiKeys.LOOK_MAX, Protocol.LOOK_MAX)
	assert_eq(UiKeys.NPC_ATTACK_MODES, Protocol.NPC_ATTACK_MODES)
	assert_eq(UiKeys.SLOTS, Protocol.SLOTS)
	assert_eq(UiKeys.M3C_REASONS, Protocol.M3C_REASONS)
	assert_eq(UiKeys.M3C_UI_KEYS, Protocol.M3C_UI_EVENTS)
	for k in UiKeys.M3C_INTENTS:
		assert_true(Protocol.is_known(k), k)
	for sl in UiKeys.SLOTS:
		assert_true(UiKeys.SLOT_LABELS_ALL.has(sl), sl)
	assert_eq(UiKeys.E_NA_GUARD_ALARM, Protocol.E_NA_GUARD_ALARM)
	assert_eq(UiKeys.E_LT_RARE_DROP, Protocol.E_LT_RARE_DROP)

func test_rules_options_schema() -> void:
	for k in ["npc_attack", "divine_source", "manuals", "loot_broadcast", "later_loot"]:
		assert_true(DataSchema.RULE_DEFAULTS.has(k), k)
	assert_eq(DataSchema.RULE_ENUMS["divine_source"], ["NONE", "BOSS_DROP"])
	assert_true("loot_tables" in DataLoader.FILES)
	assert_true("loot_tables" in DataLoader.OPTIONAL_FILES)
	for e in ["ATTACK_SECT_NPC", "KILL_GOOD_NPC", "ATTACK_MASTER"]:
		assert_true(e in DataSchema.SECT_RULE_EVENTS, e)
	assert_eq(DataSchema.ITEM_SLOTS, Protocol.SLOTS)
	assert_eq(DataSchema.ITEM_RARITIES, ["COMMON", "FINE", "RARE", "TREASURE", "DIVINE"])
	assert_eq(DataSchema.NPC_ATTACK_MODES_DATA, ["KILL", "CHALLENGE"])
	assert_eq(DataSchema.NPC_ATTACK_VIA, ["CTRL", "MENU", "BOTH"])
	assert_eq(DataSchema.NPC_ATTACK_CATEGORIES.size(), 10)
	assert_true("npc_respawn_pct" in DataSchema.INT_FIELDS["server_options"])
	assert_true("loot_drop_pct" in DataSchema.INT_FIELDS["server_options"])
	var f := FileAccess.open("res://data/server_options.default.json", FileAccess.READ)
	var so: Dictionary = JSON.parse_string(f.get_as_text())
	assert_eq(int(so.get("npc_respawn_pct", 0)), 100)
	assert_eq(int(so.get("loot_drop_pct", 0)), 100)
	var f2 := FileAccess.open("res://data/rule_profiles.json", FileAccess.READ)
	var rp: Dictionary = JSON.parse_string(f2.get_as_text())
	var want := {
		"classic_strict": [true, "NONE", false, false], "classic_standard": [true, "BOSS_DROP", true, true],
		"later_official": [true, "NONE", true, false], "friends_casual": [true, "BOSS_DROP", true, true],
	}
	for row in rp["rows"]:
		var w: Array = want[str(row["id"])]
		var r: Dictionary = row["rules"]
		assert_eq([r["npc_attack"], r["divine_source"], r["manuals"], r["loot_broadcast"]], w, str(row["id"]))
		# M3c 審查：later_loot 只有 classic_strict 關
		assert_eq(bool(r.get("later_loot", true)), str(row["id"]) != "classic_strict", "later_loot " + str(row["id"]))
