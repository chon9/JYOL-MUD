extends "res://tests/unit/test_m3d_arts_base.gd"
## M3D_PLAN §4.4（C4，WP-ARTS）：星宿 煉毒——小木鼎（出塵子「邪惡的練毒」）＋ liandu → 基本毒術熟練 20 × 倍率；
## 倍率三種（夜 ×1.5、星宿地區 ×1.5、中毒 ×2，相乘）、精不足、沒鼎、非星宿；背包裡小木鼎的「使用」＝煉毒。

const Q := "q_ar_xh_muding"
const SK := "basic_poison"

func _xh(with_tool := true) -> bool:
	if join_char("xingxiu") == null:
		return false
	if with_tool:
		give(ArtsRules.MUDING)
	ch().conditions.erase("poison")
	return true

func _prof() -> int:
	return int(ch().skills.prof(SK))

func _day() -> void:
	set_shichen(6)   # 午時（白天）

func test_mult_rules() -> void:
	assert_near(ArtsRules.liandu_mult(false, "xixia", false), 1.0, 0.0001)
	assert_near(ArtsRules.liandu_mult(true, "xixia", false), 1.5, 0.0001)
	assert_near(ArtsRules.liandu_mult(false, "xingxiu_road", false), 1.5, 0.0001)
	assert_near(ArtsRules.liandu_mult(false, "xixia", true), 2.0, 0.0001)
	assert_near(ArtsRules.liandu_mult(true, "xingxiu", true), 4.5, 0.0001, "三種相乘")
	assert_eq(ArtsRules.liandu_gain(1.0), 20)
	assert_eq(ArtsRules.liandu_gain(4.5), 90)
	assert_eq(ArtsRules.liandu_reason("xingxiu", true, 15), "")
	assert_eq(ArtsRules.liandu_reason("xingxiu", true, 14), "not_enough_jing")
	assert_eq(ArtsRules.liandu_reason("xingxiu", false, 99), "liandu_no_tool")
	assert_eq(ArtsRules.liandu_reason("xuedao", true, 99), "liandu_not_xh")

func test_liandu_town_day() -> void:
	if not _xh():
		return
	_day()
	goto("xx_square")
	var p0 := _prof()
	var j0 := int(ch().vitals["jing"])
	ok("liandu")
	assert_eq(_prof() - p0, 20, "白天、城裡、沒中毒：×1")
	assert_eq(j0 - int(ch().vitals["jing"]), ArtsRules.LIANDU_JING, "扣精 15")
	assert_eq(int(lastp(Protocol.E_AR_LIANDU).get("gain", 0)), 20)

func test_liandu_all_conditions() -> void:
	if not _xh():
		return
	set_shichen(0)   # 子時（夜）
	goto("xh_right")
	ch().add_condition("poison", 1, 5, ch().online_s + 999.0)
	var p0 := _prof()
	ok("liandu")
	assert_eq(_prof() - p0, 90, "夜 × 星宿 × 中毒 = 4.5 倍")
	assert_near(float(lastp(Protocol.E_AR_LIANDU).get("mult", 0.0)), 4.5, 0.0001)

func test_refusals() -> void:
	if not _xh(false):
		return
	assert_eq(reason("liandu"), "liandu_no_tool")
	give(ArtsRules.MUDING)
	ch().vitals["jing"] = 14
	assert_eq(reason("liandu"), "not_enough_jing")
	ch().vitals["jing"] = 100
	ch().sect = "xuedao"
	assert_eq(reason("liandu"), "liandu_not_xh")

func test_use_item_is_liandu() -> void:
	if not _xh():
		return
	_day()
	goto("xx_square")
	var p0 := _prof()
	ok("use_item", { "item_uid": first_uid(ArtsRules.MUDING) })
	assert_eq(_prof() - p0, 20, "背包裡小木鼎的「使用」＝煉毒")
	assert_eq(item_count(ArtsRules.MUDING), 1, "鼎不會用掉")
	ch().sect = "huashan"
	assert_eq(reason("use_item", { "item_uid": first_uid(ArtsRules.MUDING) }), "liandu_not_xh")

func test_quest_gives_muding() -> void:
	if not _xh(false):
		return
	ensure_giver("n_xh_chuchenzi", Q)
	goto("xh_right")
	ok("quest_accept", { "npc": "n_xh_chuchenzi", "quest": Q })
	give("r_xh_shedan", 2)
	give("r_xh_xiewei", 1)
	ok("quest_talk", { "npc": "n_xh_chuchenzi", "quest": Q })
	assert_eq(qstage(Q), "s_xiewei", "交了蛇膽")
	assert_eq(item_count("r_xh_shedan"), 0)
	ok("quest_talk", { "npc": "n_xh_chuchenzi", "quest": Q })
	assert_eq(str(qdone(Q).get("outcome", "")), "default")
	assert_eq(item_count(ArtsRules.MUDING), 1, "拿到小木鼎")
	assert_eq(item_count("r_xh_shedan"), 0)
	assert_eq(item_count("r_xh_xiewei"), 0)
	assert_true(bool(tables()["items"][ArtsRules.MUDING].get("keep_on_death", false)), "死了不掉")

## M3d 審查：煉毒每遊戲日熟練上限 200（截斷最後一次；滿了 liandu_daily、不扣精；換日重來）
func test_liandu_daily_cap() -> void:
	if not _xh():
		return
	_day()
	goto("xx_square")
	var today := int(host().clock()["day"])
	ch().counters[ArtsRules.COUNTER_LIANDU_GAIN] = { "day": today, "n": ArtsRules.LIANDU_DAILY_CAP - 10 }
	var p0 := _prof()
	ok("liandu")
	assert_eq(_prof() - p0, 10, "截到上限")
	var j0 := int(ch().vitals["jing"])
	assert_eq(reason("liandu"), "liandu_daily", "今天滿了")
	assert_eq(int(ch().vitals["jing"]), j0, "不扣精")
	ch().counters[ArtsRules.COUNTER_LIANDU_GAIN] = { "day": today - 1, "n": ArtsRules.LIANDU_DAILY_CAP }
	ok("liandu")
	assert_eq(int(ch().counters[ArtsRules.COUNTER_LIANDU_GAIN].get("n", 0)), 20, "換日重算")
