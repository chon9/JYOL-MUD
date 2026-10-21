extends "res://tests/unit/test_m3d_arts_base.gd"
## M3D_PLAN §4.2（C2，WP-ARTS）：全真 空明拳——王志謹給 1 級（任務 q_ar_qz_kongming）、自修 1–40、王志謹教 41–70、之上不能升。

const Q := "q_ar_qz_kongming"
const ART := "qz_kongming"
const NPC := "n_ar_qz_wangzhijin"

func _qz(full := true) -> bool:
	if join_char("quanzhen") == null:
		return false
	if full:
		set_skills({ "qz_haotian": 70, "basic_fist": 80, "qz_xinfa": 80, "yangsheng": 90 })
		ch().attrs["luck"] = 32
		ch().morality = 1000
	return true

func _check() -> String:
	return Learning.check_master(ch(), NPC, ART, tables(), ws.options, host().rules)

func test_requires_refused() -> void:
	if not _qz():
		return
	assert_eq(host().quests._can_accept(s(), Q), "")
	ch().morality = 999
	assert_eq(host().quests._can_accept(s(), Q), "req_morality_min", "善惡 1000")
	ch().morality = 1000
	ch().attrs["luck"] = 31
	assert_eq(host().quests._can_accept(s(), Q), "req_attr_min", "福緣 32")
	ch().attrs["luck"] = 32
	set_skills({ "yangsheng": 89 })
	assert_eq(host().quests._can_accept(s(), Q), "req_skill_min", "養生 90")

func test_flow_gives_level_1() -> void:
	if not _qz():
		return
	goto("qz_square")
	ok("quest_accept", { "npc": NPC, "quest": Q })
	ok("quest_talk", { "npc": NPC, "quest": Q })
	ok("dialogue_choose", { "npc": NPC, "quest": Q, "node": "n0", "choice": "c_ask" })
	assert_eq(str(qdone(Q).get("outcome", "")), "default")
	assert_true(bool(ch().flags.get("qz_kongming", false)), "旗標 qz_kongming")
	assert_eq(lv(ART), 1, "王志謹給 1 級")
	assert_eq(str(host().quests._can_accept(s(), Q)), "quest_done", "一次性")

func test_self_study_then_master() -> void:
	if not _qz():
		return
	ch().flags["qz_kongming"] = true
	set_skills({ ART: 1 })
	assert_eq(_check(), "need_self_study", "1–40 要自修，王志謹不教")
	ch().learn_points = 5000
	var r := Learning.self_study(ch(), ART, 1, tables(), ws.options, host().rules)
	assert_true(bool(r["ok"]), "自修 1→ %s" % str(r))
	set_skills({ ART: 40 })
	assert_eq(_check(), "", "40 級起王志謹教")
	set_skills({ ART: 70 })
	assert_eq(_check(), "cap_master", "王志謹教到 70")
	assert_eq(Learning.self_study_cap(ch(), ART, tables(), host().rules), 70, "之上不能升（讀寶典是後期）")

func test_era_1_0a() -> void:
	if not game_ok():
		return
	use_eras(["1.0A"])
	assert_false(tables()["martial_arts"].has(ART))
	assert_false(tables()["quests"].has(Q))
	assert_false(tables()["npcs"].has(NPC))
