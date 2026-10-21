extends "res://tests/test_case.gd"
## 擁有者回報：學武功沒說明加什麼（例如基本劍法）。SkillEffects 依公式產生說明；學武視窗每列底下一行、武功窗選取時整段。

var _nodes: Array = []

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame

func _t() -> Dictionary:
	return UiClient.tables()

func test_every_basic_skill_and_art_has_an_explanation() -> void:
	var t := _t()
	assert_true(not t.is_empty(), "GameData tables loaded")
	for id in t.get("basic_skills", {}):
		assert_true(SkillEffects.lines(id, t).size() > 0, "basic skill %s explained" % id)
	for id in t.get("martial_arts", {}):
		assert_true(SkillEffects.lines(id, t).size() > 0, "art %s explained" % id)

func test_basic_sword_says_what_it_adds() -> void:
	var s := SkillEffects.text("basic_sword", _t())
	assert_true(s.contains("攻擊力每 4 級 +1"), s)
	assert_true(s.contains("每級 +0.3%"), s)
	assert_true(s.contains("%d 級" % BattleFormulas.MASTERY_LEVEL), s)
	assert_true(SkillEffects.summary("basic_sword", _t()).contains("劍"))

func test_numbers_follow_the_formula_constants() -> void:
	var t := _t()
	assert_true(SkillEffects.text("basic_inner", t).contains("× %d" % DerivedStats.NEILI_PER_INNER))
	assert_true(SkillEffects.text("basic_dodge", t).contains("最多減 %d%%" % roundi(BattleRules.DODGE_MAX * 100)))
	assert_true(SkillEffects.text("basic_hidden", t).contains("最多 %d" % BattleCmds.HIDDEN_MAX_RANGE))
	assert_true(SkillEffects.text("basic_poison", t).contains("%d" % ArtsRules.LIANDU_JING))
	# 公式本身：攻擊力每 4 級基本功 +1（battle_formulas attack_power 的 base_lv / 4.0）
	var src := FileAccess.get_file_as_string("res://core/battle/battle_formulas.gd")
	assert_true(src.contains("base_lv / 4.0"), "attack formula still adds base level / 4")
	assert_true(src.contains("* 0.3"), "hit chance still 0.3 per level")

func test_art_lists_moves_and_basic() -> void:
	var t := _t()
	var a: Dictionary = t["martial_arts"].get("sl_changquan", {})
	if a.is_empty():
		return
	var s := SkillEffects.text("sl_changquan", t)
	assert_true(s.contains("招式："), s)
	assert_true(s.contains(SkillEffects._name(t, str(a["base_skill"]))), s)

func test_learn_dialog_shows_effect_line() -> void:
	var d := LearnDialog.new()
	tree.root.add_child(d)
	_nodes.append(d)
	d.open_list({ "npc": "n_test", "npc_name": "教頭", "entries": [
		{ "skill": "basic_sword", "name": "基本劍法", "kind": "BASIC", "level": 0, "cap": 30, "ok": true },
		{ "skill": "basic_dodge", "name": "閃躲縱躍", "kind": "BASIC", "level": 0, "cap": 30, "ok": false, "reason": "learn_need_neili" }] })
	await tree.process_frame
	var l := d.find_child("LearnEffect_basic_sword", true, false) as Label
	assert_true(l != null and l.text.contains("攻擊力每 4 級 +1"), "effect line under the row")
	assert_true(d.find_child("LearnEffect_basic_dodge", true, false) != null, "also on rows you cannot learn yet")

func test_skills_panel_explains_selected_skill() -> void:
	var p := SkillsPanel.new()
	tree.root.add_child(p)
	_nodes.append(p)
	p.apply_sheet({ "skills": [{ "id": "basic_sword", "name": "基本劍法", "kind": "BASIC", "level": 5, "prof": 1, "next_prof": 10 }] })
	await tree.process_frame
	var l := p.find_child("SkillEffect", true, false) as Label
	assert_true(l != null and l.text.contains("攻擊力每 4 級 +1"), "selected skill explained: %s" % (l.text if l else "none"))
