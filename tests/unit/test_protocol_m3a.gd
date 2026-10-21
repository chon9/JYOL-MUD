extends "res://tests/unit/test_world_fixture.gd"
## M3A_PLAN K1、5.1、6.11、6.12：VERSION 4、新 intent 的 schema 與列舉、debug_set 只在 --debug-intents 時註冊、
## world_info.later_battle_cmds。

func before_each() -> void:
	world_name = "w_proto3a"
	super.before_each()

func after_each() -> void:
	ws.debug_intents = false
	super.after_each()

func _v(kind: String, args: Dictionary) -> String:
	return Protocol.validate_args(kind, args)

func test_version_and_battle_cmds() -> void:
	assert_true(Protocol.VERSION >= 4, "M3a（K1）升到 4；故事包（S1）升到 5")
	assert_eq(Protocol.BATTLE_CMDS, ["MOVE", "ATTACK", "ART", "DEFEND", "REST", "EQUIP", "FLEE",
		"POISON", "MEDIC", "HIDDEN", "FORMATION", "INNER", "ACUPOINT", "ITEM",
		"DODGE", "QING"])   # M3d（M3D_PLAN §7）：閃、輕（WP-LAW Day-0）
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "INNER", "mode": "HEAL" }), "")
	for m in ["HEAL", "EXPEL", "UNSEAL", "TRANSFER"]:
		assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "INNER", "mode": m }), "", m)
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "INNER", "mode": "NAP" }), "bad_value:mode")
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "INNER", "mode": 1 }), "bad_type:mode")
	assert_eq(_v("battle_cmd", { "battle_id": 1, "cmd": "ITEM", "item_uid": "it_1", "target": [0, 0] }), "")

func test_new_intent_schemas() -> void:
	assert_eq(_v("sect_betray", { "npc": "n_x" }), "", "confirm 選填")
	assert_eq(_v("sect_betray", { "npc": "n_x", "confirm": true }), "")
	assert_eq(_v("sect_betray", { "npc": "n_x", "confirm": "yes" }), "bad_type:confirm")
	assert_eq(_v("sect_betray", {}), "missing_arg:npc")
	assert_eq(_v("jail_ransom", { "npc": "n_x", "name": "甲" }), "")
	assert_eq(_v("jail_ransom", { "npc": "n_x" }), "missing_arg:name")
	assert_eq(_v("sect_trial", { "npc": "n_x" }), "")
	assert_eq(_v("npc_guide", { "npc": "n_x" }), "")
	assert_eq(_v("npc_guide", { "npc": "n_x", "to": "r" }), "unexpected_arg")
	# debug_set 的 value 不檢查型別
	for v in [1, 2.5, "x", true, [1], { "a": 1 }, null]:
		assert_eq(_v("debug_set", { "key": "morality", "value": v }), "", str(v))
	assert_eq(_v("debug_set", { "key": "morality" }), "missing_arg:value")
	assert_eq(_v("debug_set", { "key": 1, "value": 1 }), "bad_type:key")
	for k in ["sect_breach", "sect_expel", "sect_betray", "sect_stop_teach", "sect_skill_decay", "sect_hostile", "jail_in",
			"jail_out", "jail_ransom_paid", "poison_flare", "condition_off", "npc_guide", "trial_passed", "debug_set"]:
		assert_true(k in [Protocol.E_SECT_BREACH, Protocol.E_SECT_EXPEL, Protocol.E_SECT_BETRAY, Protocol.E_SECT_STOP_TEACH,
			Protocol.E_SECT_SKILL_DECAY, Protocol.E_SECT_HOSTILE, Protocol.E_JAIL_IN, Protocol.E_JAIL_OUT,
			Protocol.E_JAIL_RANSOM_PAID, Protocol.E_POISON_FLARE, Protocol.E_CONDITION_OFF, Protocol.E_NPC_GUIDE,
			Protocol.E_TRIAL_PASSED, Protocol.E_DEBUG_SET], k)
	for svc in ["BETRAY", "JAIL", "TRIAL", "GUIDE"]:
		assert_has(Protocol.NPC_SERVICES, svc)

func test_debug_set_needs_flag() -> void:
	if not game_ok():
		return
	assert_false(host().debug_enabled)
	make_char("除錯俠")
	assert_eq(reason("debug_set", { "key": "money", "value": 5 }), "unknown_intent", "沒有 --debug-intents 時不註冊")
	ws.stop()
	ws.debug_intents = true
	restart_world()
	assert_true(host().debug_enabled)
	ok("char_select", { "char_id": str(host().char_store.ids(s().identity)[0]) })
	ok("debug_set", { "key": "money", "value": 5000 })
	assert_eq(int(ch().money), 5000)
	ok("debug_set", { "key": "morality", "value": -200 })
	assert_eq(int(ch().morality), -200)
	ok("debug_set", { "key": "skill:basic_fist", "value": 12 })
	assert_eq(ch().skills.level("basic_fist"), 12)
	ok("debug_set", { "key": "attr:wit", "value": 30 })
	assert_eq(int(ch().attrs["wit"]), 30)
	ok("debug_set", { "key": "flag:wd_recommended", "value": true })
	assert_true(bool(ch().flags.get("wd_recommended", false)))
	ok("debug_set", { "key": "flag:wd_recommended", "value": false })
	assert_false(ch().flags.has("wd_recommended"))
	var t0: float = ch().online_s
	ok("debug_set", { "key": "online_s_add", "value": 100 })
	assert_true(ch().online_s >= t0 + 100.0)
	ok("debug_set", { "key": "teleport", "value": "dl_square" })
	assert_eq(s().room_id(), "dl_square")
	assert_eq(reason("debug_set", { "key": "teleport", "value": "nowhere" }), "bad_value:value")
	assert_eq(reason("debug_set", { "key": "nonsense", "value": 1 }), "bad_value:key")
	assert_eq(evs(Protocol.E_DEBUG_SET).size() >= 1, true)

func test_world_info_later_battle_cmds() -> void:
	if not game_ok():
		return
	assert_eq(ws.world_info().get("later_battle_cmds"), true)
	use_preset("classic_strict")
	assert_eq(ws.world_info().get("later_battle_cmds"), false, "classic_strict 關「內」「穴」")
