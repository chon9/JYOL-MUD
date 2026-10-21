extends "res://tests/unit/test_m3d_arts_base.gd"
## M3D_PLAN §4.5（C5，WP-ARTS）：峨嵋 滅絕師太只教 1 級、其餘自修（M3a 已做，這裡用測試鎖住）：
## 滅絕教到 1 後再學 → cap_master（M3D_PLAN 寫 cap_reached；本作的原因碼是 cap_master）、自修 1 → 上限（滅劍 90、九陽 80、佛光 80）可以、
## 規則 self_study_cap 是 NONE（照武功列，不放寬）。

const NPC := "n_em_miejue"

func _em() -> bool:
	if join_char("emei", "峨嵋女弟子", "F") == null:
		return false
	ch().morality = 500
	return true

func test_miejue_caps_are_1() -> void:
	if not game_ok():
		return
	for mid in ["ms_em_miejue_miejian", "ms_em_miejue_jiuyang", "ms_em_miejue_foguang", "ms_em_miejue_juejian"]:
		assert_eq(int(tables()["masters"][mid]["cap"]), 1, mid)
	assert_eq(int(tables()["martial_arts"]["em_miejian"]["self_study_cap"]), 90)
	assert_eq(int(tables()["martial_arts"]["em_jiuyang"]["self_study_cap"]), 80)
	assert_eq(int(tables()["martial_arts"]["em_foguang"]["self_study_cap"]), 80)
	assert_eq(str(host().rules.get("self_study_cap", "NONE")), "NONE", "預設規則不放寬自修上限")

func test_learn_1_then_self_study() -> void:
	if not _em():
		return
	ch().flags["em_miejian_ok"] = true
	set_skills({ "em_huifeng": 30, "em_jiuyang": 1 })
	var art := "em_miejian"
	var r := Learning.learn(ch(), NPC, art, 50, tables(), ws.options, host().rules)
	assert_true(bool(r["ok"]), "滅絕教 %s" % str(r))
	assert_eq(lv(art), 1, "滅絕只教到 1 級")
	r = Learning.learn(ch(), NPC, art, 1, tables(), ws.options, host().rules)
	assert_false(bool(r["ok"]))
	assert_eq(str(r["reason"]), "cap_master", "教到 1 後再學被拒")
	assert_eq(Learning.self_study_cap(ch(), art, tables(), host().rules), 90, "自修上限 90")
	ch().learn_points = 5000
	var s1 := Learning.self_study(ch(), art, 3, tables(), ws.options, host().rules)
	assert_true(bool(s1["ok"]), "1 級之後自修 %s" % str(s1))
	set_skills({ art: 89 })
	Survival.rest_full(ch(), tables(), ws.options)
	assert_true(bool(Learning.self_study(ch(), art, 1, tables(), ws.options, host().rules)["ok"]), "89 還能自修")
	set_skills({ art: 90 })
	var s2 := Learning.self_study(ch(), art, 1, tables(), ws.options, host().rules)
	assert_eq(str(s2["reason"]), "cap_master", "90 到頂")

func test_jiuyang_foguang_caps() -> void:
	if not _em():
		return
	assert_eq(Learning.self_study_cap(ch(), "em_jiuyang", tables(), host().rules), 80)
	assert_eq(Learning.self_study_cap(ch(), "em_foguang", tables(), host().rules), 80)
