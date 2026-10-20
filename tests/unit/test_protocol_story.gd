extends "res://tests/unit/test_world_fixture.gd"
## STORY_PLAN §9.1 test_protocol_story：VERSION == 5；新 intent 的 schema；角色表／view 新欄位形狀；原因碼都有 fail_ 模板（_engine 碎片）。
## 方法名 test_story_*。

func before_each() -> void:
	world_name = "w_story_proto"
	super.before_each()

func _v(kind: String, args: Dictionary) -> String:
	return Protocol.validate_args(kind, args)

func test_story_version_and_constants() -> void:
	assert_eq(Protocol.VERSION, 5)
	assert_eq(Protocol.CH_JIANGHU, "JIANGHU")
	assert_eq(Protocol.I_QUEST_TALK, "quest_talk")
	assert_eq(Protocol.I_DIALOGUE_CHOOSE, "dialogue_choose")
	assert_eq(Protocol.I_DIALOGUE_CLOSE, "dialogue_close")
	assert_eq(Protocol.I_STORY_ACT, "story_act")
	assert_eq(Protocol.I_VILLAIN_REPLY, "villain_reply")
	assert_eq(Protocol.I_RUMOR_LIST, "rumor_list")
	for k in [Protocol.E_DIALOGUE, Protocol.E_DIALOGUE_CLOSE, Protocol.E_QUEST_STAGE, Protocol.E_QUEST_FAIL,
			Protocol.E_RUMOR, Protocol.E_RUMOR_LIST, Protocol.E_VILLAIN_PROMPT, Protocol.E_VILLAIN_CLEAR]:
		assert_true(k != "", k)
	assert_eq(Protocol.E_RUMOR, "jianghu_rumor")
	assert_eq(Protocol.STORY_REASONS, ["dialogue_none", "dialogue_stale", "choice_locked", "quest_cooldown", "quest_not_now",
		"act_unknown", "act_not_here", "villain_none", "npc_refuse", "escort_lost"])

func test_story_intent_schema() -> void:
	assert_eq(_v("quest_talk", { "npc": "n_a", "quest": "q_a" }), "")
	assert_eq(_v("quest_talk", { "npc": "n_a" }), "missing_arg:quest")
	assert_eq(_v("dialogue_choose", { "npc": "n", "quest": "q", "node": "n0", "choice": "c" }), "")
	assert_eq(_v("dialogue_choose", { "npc": "n", "quest": "q", "node": "n0" }), "missing_arg:choice")
	assert_eq(_v("dialogue_choose", { "npc": "n", "quest": "q", "node": 1, "choice": "c" }), "bad_type:node")
	assert_eq(_v("dialogue_close", {}), "")
	assert_eq(_v("dialogue_close", { "x": 1 }), "unexpected_arg")
	assert_eq(_v("story_act", { "act": "q_a:a_1" }), "")
	assert_eq(_v("villain_reply", { "wid": "w_nanhai", "choice": "FIGHT" }), "")
	assert_eq(_v("villain_reply", { "wid": "w_nanhai", "choice": "CALL" }), "")
	assert_eq(_v("villain_reply", { "wid": "w_nanhai", "choice": "RUN" }), "bad_value:choice")
	assert_eq(_v("rumor_list", {}), "")

func test_story_handlers_registered() -> void:
	if not game_ok():
		return
	for k in ["quest_talk", "dialogue_choose", "dialogue_close", "story_act"]:
		assert_true(ws.has_intent_handler(k), k)

func test_story_sheet_and_view_shape() -> void:
	if not game_ok():
		return
	make_char()
	var sh := sheet()
	assert_has(sh, "lilian")
	assert_has(sh, "quest_cd")
	assert_eq(sh["quests_done"], [])
	ok("quest_accept", { "npc": "n_wujieshan", "quest": "q_rabbit" })
	var q: Dictionary = sheet()["quests"][0]
	for k in ["id", "name", "chapter", "stage", "stage_title", "log", "objectives", "hint_room", "escort"]:
		assert_has(q, k, "quests 列欄位")
	for k in ["text", "have", "need", "done"]:
		assert_has(q["objectives"][0], k)
	var v := view()
	for k in ["story_actions", "escort", "wanderers"]:
		assert_has(v, k, "view 欄位")
	assert_eq(v["story_actions"], [])
	assert_eq(v["escort"], [])
	assert_true(v["wanderers"] is Array)

func test_story_dialogue_none_and_close() -> void:
	if not game_ok():
		return
	make_char()
	assert_eq(reason("dialogue_choose", { "npc": "n_wujieshan", "quest": "q_rabbit", "node": "n0", "choice": "c" }), "dialogue_none")
	ok("dialogue_close")
	assert_eq(reason("quest_talk", { "npc": "n_wujieshan", "quest": "q_nope" }), "quest_unknown")
	assert_eq(reason("quest_talk", { "npc": "n_xx_station", "quest": "q_rabbit" }), "not_here")
	assert_eq(reason("story_act", { "act": "q_rabbit:x" }), "act_unknown")

func test_story_engine_fragment_templates() -> void:
	var path := "res://docs/story_staging/_engine.json"
	assert_true(FileAccess.file_exists(path), "_engine 碎片")
	var frag: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(frag is Dictionary)
	var ids := {}
	for t in frag.get("text_templates", []):
		ids[str(t.get("id", ""))] = t
		assert_eq(str(t.get("era", "")), "1.0A", str(t.get("id", "")))
		assert_true(str(t.get("self", "")) != "", str(t.get("id", "")))
	for code in Protocol.STORY_REASONS:
		assert_true(ids.has("fail_" + code), "fail_" + code)
		assert_true(ids.has("err_" + code), "err_" + code)
	for k in ["quest_stage", "quest_fail", "e_quest_stage", "e_quest_fail", "e_dialogue_close"]:
		assert_true(ids.has(k), k)

func test_story_server_options_and_cli() -> void:
	var d := GameData.default_server_options()
	assert_eq(d.get("rumors_enabled"), true)
	assert_eq(d.get("rumor_min_gap_s"), 120)
	assert_type(d.get("rumor_min_gap_s"), TYPE_INT)
	assert_eq(d.get("rumor_chat_inner_min"), 80, "審查修正：預設照原作 80")
	assert_eq(d.get("wanderers_enabled"), true)
	assert_eq(d.get("villain_warn_s"), 3)
	assert_eq(d.get("chase_npcs"), true)
	assert_eq(d.get("ambient_lines"), true)
	assert_eq(d.get("npc_reactions"), "FULL")
	var p: Dictionary = ws.parse_cli_opts("npc_reactions=FLAVOR,rumors_enabled=false,villain_warn_s=5", d)
	assert_eq(p["error"], "")
	assert_eq(p["values"], { "npc_reactions": "FLAVOR", "rumors_enabled": false, "villain_warn_s": 5 })
	assert_true(str(ws.parse_cli_opts("npc_reactions=MAYBE", d)["error"]) != "")
	if game_ok():
		assert_eq(ws.world_info().get("rumors_enabled"), true)
		assert_eq(ws.world_info().get("wanderers_enabled"), true)

func test_story_client_state_mirrors() -> void:
	cs._apply_events([{ "ch": "SYSTEM", "key": "dialogue", "p": { "npc": "n_a", "node": "n0", "choices": [] } }])
	assert_eq(cs.dialogue.get("npc", ""), "n_a")
	cs._apply_events([{ "ch": "SYSTEM", "key": "dialogue_close", "p": { "npc": "n_a" } }])
	assert_eq(cs.dialogue, {})
	cs._apply_events([{ "ch": "SYSTEM", "key": "rumor_list", "p": { "items": [{ "text_key": "x", "params": {}, "kind": "QUEST", "world_s": 1.0 }] } }])
	assert_eq(cs.rumors.size(), 1)
	cs._apply_events([{ "ch": "SYSTEM", "key": "villain_prompt", "p": { "wid": "w_nanhai", "npc_name": "南海鱷神", "countdown_s": 3, "can_call": true } }])
	assert_true(cs.villain_prompts.has("w_nanhai"))
	cs._apply_events([{ "ch": "SYSTEM", "key": "villain_clear", "p": { "wid": "w_nanhai", "why": "ESCAPED" } }])
	assert_false(cs.villain_prompts.has("w_nanhai"))
