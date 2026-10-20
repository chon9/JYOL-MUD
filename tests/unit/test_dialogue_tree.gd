extends "res://tests/test_case.gd"
## STORY_PLAN §9.1 test_dialogue_tree：節點檢視、上鎖選項與 why、hide_if_locked、goto END、resume、合成的「繼續」。方法名 test_story_*。

const F := preload("res://tests/unit/test_character_fixtures.gd")
const V2 := preload("res://tests/unit/test_world_quest_v2.gd")

var def: Dictionary
var c

func before_each() -> void:
	def = QuestDef.normalize(V2.fixture_quest())
	c = F.new_char()

func _view(dlg: String, node: String, ctx := {}) -> Dictionary:
	return DialogueTree.node_view(def, dlg, node, c, GameData.tables, F.options(), F.rules(), ctx)

func test_story_node_view_choices_and_locks() -> void:
	var v := _view("d_zhang", "n_pick")
	assert_eq(v["speaker"], "player")
	assert_eq(v["text"], "我來……")
	assert_false(bool(v["end"]))
	var ids: Array = []
	for ch in v["choices"]:
		ids.append(ch["id"])
	assert_eq(ids, ["c_a", "c_b", "c_lock", "c_take", "c_fail"], "c_hide 上鎖時不顯示")
	var lock: Dictionary = v["choices"][2]
	assert_true(bool(lock["locked"]))
	assert_eq(lock["why"], Requirements.describe({ "type": "skill_min", "skill": "basic_fist", "value": 200 }, GameData.tables))
	assert_false(bool(v["choices"][0]["locked"]))
	assert_eq(v["choices"][0]["why"], "")
	# 條件成立後解鎖、隱藏的也出現
	c.skills.set_level("basic_fist", 200, GameData.tables)
	c.fame = 99999
	v = _view("d_zhang", "n_pick")
	ids.clear()
	for ch in v["choices"]:
		ids.append(ch["id"])
	assert_has(ids, "c_hide")
	assert_false(bool(v["choices"][2]["locked"]))

func test_story_desc_overrides_why() -> void:
	def["dialogues"]["d_zhang"]["nodes"]["n_pick"]["choices"][2]["requires"][0]["desc"] = "要先練好拳腳"
	assert_eq(_view("d_zhang", "n_pick")["choices"][2]["why"], "要先練好拳腳")

func test_story_goto_next_and_end() -> void:
	var v := _view("d_zhang", "n0")
	assert_eq(v["choices"], [{ "id": DialogueTree.NEXT_CHOICE, "label": DialogueTree.NEXT_LABEL, "locked": false, "why": "" }])
	assert_false(bool(v["end"]))
	assert_eq(v["goto"], "n_pick")
	var nx := DialogueTree.choice(def, "d_zhang", "n0", DialogueTree.NEXT_CHOICE)
	assert_eq(nx["goto"], "n_pick")
	v = _view("d_zhang", "n_end")
	assert_true(bool(v["end"]), "goto END → 結束")
	assert_eq(v["choices"], [])
	assert_eq(DialogueTree.choice(def, "d_zhang", "n_end", DialogueTree.NEXT_CHOICE), {})
	assert_eq(_view("d_zhang", "nope"), {})
	assert_eq(_view("d_nope", "n0"), {})

func test_story_choice_lookup() -> void:
	var a := DialogueTree.choice(def, "d_zhang", "n_pick", "c_a")
	assert_eq(a["label"], "選甲")
	assert_eq((a["do"] as Array).size(), 3)
	assert_eq(a["goto"], "n_end")
	assert_eq(DialogueTree.choice(def, "d_zhang", "n_pick", "c_none"), {})
	assert_eq(DialogueTree.choice(def, "d_offer", "n0", "c_no")["goto"], "END")

func test_story_entry_node_resume() -> void:
	assert_eq(DialogueTree.entry_node(def, "d_zhang", true), "n0")
	assert_eq(DialogueTree.entry_node(def, "d_zhang", false), "n_back")
	assert_eq(DialogueTree.entry_node(def, "d_offer", false), "n0", "沒寫 resume → start")

func test_story_hour_condition_uses_ctx() -> void:
	def["dialogues"]["d_zhang"]["nodes"]["n_pick"]["choices"][0]["requires"] = [{ "type": "hour_in", "hours": ["申"] }]
	assert_true(bool(_view("d_zhang", "n_pick", { "shichen": "子" })["choices"][0]["locked"]))
	assert_false(bool(_view("d_zhang", "n_pick", { "shichen": "申" })["choices"][0]["locked"]))
