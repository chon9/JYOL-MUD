extends "res://tests/unit/test_m3d_arts_base.gd"
## M3D_PLAN §4.6（C6，WP-ARTS）：峨嵋 四象掌（羅煞劍任務 q_ar_em_luosha）——雁門關守衛「幫忙」打三波蠻兵 →
## 收 50000 兩（結束）或拒收拿推薦信 → 終南山破廟郭襄：合格的峨嵋弟子學四象掌、不合格的峨嵋弟子拿羅煞劍、
## 非峨嵋拼酒（根骨 ≥ 20 贏羅煞劍、認輸拿 10 顆黃藥丸）；郭襄教 2–10、之後自修到 70。

const Q := "q_ar_em_luosha"
const ART := "em_sixiang"
const GUARD := "n_ar_ym_shouwei"
const GX := "n_ar_guoxiang"

func _char(sect_id: String, gender := "F", xp := 300000) -> bool:
	if join_char(sect_id, "羅煞俠", gender) == null:
		return false
	ch().combat_xp = xp
	set_skills({ "basic_inner": 60 })
	return true

## 接任務、打完三波蠻兵（回 false＝途中失敗）
func _help() -> bool:
	goto("ym_gate")
	if not ok("quest_accept", { "npc": GUARD, "quest": Q }).get("ok", false):
		return false
	ok("quest_talk", { "npc": GUARD, "quest": Q })
	if not ok("dialogue_choose", { "npc": GUARD, "quest": Q, "node": "n0", "choice": "c_help" }).get("ok", false):
		return false
	assert_true(s().battle_id != 0, "開打")
	win_battle()
	return assert_eq(qstage(Q), "s_reward", "打完三波 → 回去見守衛")

func _refuse() -> void:
	ok("quest_talk", { "npc": GUARD, "quest": Q })
	ok("dialogue_choose", { "npc": GUARD, "quest": Q, "node": "n0", "choice": "c_refuse" })

func test_data_rows() -> void:
	if not game_ok():
		return
	var a: Dictionary = tables()["martial_arts"][ART]
	assert_eq(str(a["era"]), "1.0B")
	assert_eq(str(a["category"]), "FIST")
	var fan := false
	for m in a["moves"]:
		if str(m["aoe"]) == "FAN":
			fan = true
	assert_true(fan, "半米字 = FAN")
	assert_eq(int(tables()["masters"]["ms_ar_guoxiang_sixiang"]["cap"]), 10)
	assert_eq(int(tables()["monsters"]["m_ar_manbing"]["stats"]["qi"]), 2500)
	assert_eq(str(tables()["items"]["i_ar_luoshajian"]["weapon_type"]), "SWORD")
	assert_eq(str(tables()["npcs"][GX]["room"]), "zn_pomiao")

func test_requires_refused() -> void:
	if not _char("emei", "F", 99999):
		return
	assert_eq(host().quests._can_accept(s(), Q), "req_combat_xp_min", "實戰 10 萬（R12）")
	ch().combat_xp = 100000
	set_skills({ "basic_inner": 59 })
	assert_eq(host().quests._can_accept(s(), Q), "req_skill_min", "最大內力 300 ＝ 基本內功 60")

func test_solo_needs_party_or_300k() -> void:
	if not _char("huashan", "M", 100000):
		return
	goto("ym_gate")
	ok("quest_accept", { "npc": GUARD, "quest": Q })
	ok("quest_talk", { "npc": GUARD, "quest": Q })
	var r := send("dialogue_choose", { "npc": GUARD, "quest": Q, "node": "n0", "choice": "c_help" })
	assert_false(bool(r.get("ok", false)), "實戰 10 萬一個人：要三人以上的隊伍")
	assert_eq(s().battle_id, 0)
	ch().combat_xp = 300000
	ok("quest_talk", { "npc": GUARD, "quest": Q })
	ok("dialogue_choose", { "npc": GUARD, "quest": Q, "node": "n0", "choice": "c_help" })
	assert_true(s().battle_id != 0, "實戰 30 萬可以單槍匹馬【設計提案】")

func test_take_money_ends() -> void:
	if not _char("huashan", "M"):
		return
	if not _help():
		return
	var m0: int = ch().money
	ok("quest_talk", { "npc": GUARD, "quest": Q })
	ok("dialogue_choose", { "npc": GUARD, "quest": Q, "node": "n0", "choice": "c_take" })
	assert_eq(str(qdone(Q).get("outcome", "")), "money")
	assert_eq(int(ch().money) - m0, 50000)
	assert_eq(item_count("i_ar_ym_tuijianxin"), 0, "收了錢就沒有推薦信")
	assert_eq(host().quests._can_accept(s(), Q), "quest_done", "一次性")

func test_emei_qualified_learns() -> void:
	if not _char("emei"):
		return
	set_skills({ "em_foguang": 50, "duane": 60, "em_jiuyang": 1, "em_jinding": 50 })
	ch().attrs["luck"] = 20
	if not _help():
		return
	_refuse()
	assert_eq(item_count("i_ar_ym_tuijianxin"), 1)
	assert_eq(qstage(Q), "s_guoxiang")
	goto("zn_pomiao")
	ok("quest_talk", { "npc": GX, "quest": Q })
	ok("dialogue_choose", { "npc": GX, "quest": Q, "node": "n0", "choice": "c_learn" })
	assert_eq(str(qdone(Q).get("outcome", "")), "sixiang")
	assert_true(bool(ch().flags.get("em_sixiang_ok", false)))
	assert_eq(lv(ART), 1, "郭襄給 1 級")
	assert_eq(item_count("i_ar_ym_tuijianxin"), 0, "信收回")
	# 郭襄教 2–10，之後自修到 70
	var chk := Learning.check_master(ch(), GX, ART, tables(), ws.options, host().rules)
	assert_eq(chk, "", "郭襄教")
	set_skills({ ART: 10 })
	assert_eq(Learning.check_master(ch(), GX, ART, tables(), ws.options, host().rules), "cap_master", "郭襄教到 10")
	assert_eq(Learning.self_study_cap(ch(), ART, tables(), host().rules), 70, "之後自修到 70")

func test_emei_unqualified_gets_sword() -> void:
	if not _char("emei"):
		return
	set_skills({ "em_foguang": 10, "duane": 10 })
	if not _help():
		return
	_refuse()
	goto("zn_pomiao")
	ok("quest_talk", { "npc": GX, "quest": Q })
	var r := send("dialogue_choose", { "npc": GX, "quest": Q, "node": "n0", "choice": "c_learn" })
	assert_false(bool(r.get("ok", false)), "不合格選不了學四象掌")
	ok("dialogue_choose", { "npc": GX, "quest": Q, "node": "n0", "choice": "c_sword" })
	assert_eq(str(qdone(Q).get("outcome", "")), "sword")
	assert_eq(item_count("i_ar_luoshajian"), 1)
	assert_eq(lv(ART), 0)

func test_outsider_drinks() -> void:
	if not _char("huashan", "M"):
		return
	ch().attrs["con"] = 19
	if not _help():
		return
	_refuse()
	goto("zn_pomiao")
	ok("quest_talk", { "npc": GX, "quest": Q })
	assert_false(bool(send("dialogue_choose", { "npc": GX, "quest": Q, "node": "n0", "choice": "c_sword" }).get("ok", false)),
		"非峨嵋不能直接拿劍")
	ok("dialogue_choose", { "npc": GX, "quest": Q, "node": "n0", "choice": "c_drink" })
	var r := send("dialogue_choose", { "npc": GX, "quest": Q, "node": "n_drink", "choice": "c_win" })
	assert_false(bool(r.get("ok", false)), "根骨 19 喝不贏")
	ok("dialogue_choose", { "npc": GX, "quest": Q, "node": "n_drink", "choice": "c_lose" })
	assert_eq(str(qdone(Q).get("outcome", "")), "pills")
	assert_eq(item_count("i_ar_huangyaowan"), 10, "10 顆黃藥丸")

func test_outsider_drink_win() -> void:
	if not _char("wudang", "M"):
		return
	ch().attrs["con"] = 20
	if not _help():
		return
	_refuse()
	goto("zn_pomiao")
	ok("quest_talk", { "npc": GX, "quest": Q })
	ok("dialogue_choose", { "npc": GX, "quest": Q, "node": "n0", "choice": "c_drink" })
	ok("dialogue_choose", { "npc": GX, "quest": Q, "node": "n_drink", "choice": "c_win" })
	assert_eq(str(qdone(Q).get("outcome", "")), "sword")
	assert_eq(item_count("i_ar_luoshajian"), 1)

func test_era_1_0a() -> void:
	if not game_ok():
		return
	use_eras(["1.0A"])
	for t in [["martial_arts", ART], ["quests", Q], ["npcs", GX], ["npcs", GUARD], ["monsters", "m_ar_manbing"]]:
		assert_false(tables()[t[0]].has(t[1]), "%s.%s 是 1.0B" % t)
