extends "res://tests/test_case.gd"
## WP-PK：MoralityPk 純規則（M2_PLAN 4.6.4、5.2、6.1）。

func test_pk_value_decay_boundaries() -> void:
	assert_eq(MoralityPk.pk_value(3, 0.0, 0.0), 3)
	assert_eq(MoralityPk.pk_value(3, 0.0, 1799.0), 3, "1799 s: not yet")
	assert_eq(MoralityPk.pk_value(3, 0.0, 1800.0), 2, "1800 s: -1")
	assert_eq(MoralityPk.pk_value(3, 0.0, 3599.0), 2)
	assert_eq(MoralityPk.pk_value(3, 0.0, 3600.0), 1, "3600 s: -2")
	assert_eq(MoralityPk.pk_value(3, 0.0, 99999.0), 0, "never below 0")
	assert_eq(MoralityPk.pk_value(2, 500.0, 2299.0), 2, "stamp offset")
	assert_eq(MoralityPk.pk_value(2, 500.0, 2300.0), 1)
	assert_eq(MoralityPk.pk_value(0, 0.0, 5000.0), 0)
	assert_eq(MoralityPk.pk_value(-4, 0.0, 0.0), 0, "negative base clamps")
	assert_eq(MoralityPk.pk_value(2, 900.0, 100.0), 2, "online_s before stamp: no decay")

func test_guard_count() -> void:
	assert_eq(MoralityPk.guard_count(0, 0), 0)
	assert_eq(MoralityPk.guard_count(3, 0), 0, "pk 3 is not > 3")
	assert_eq(MoralityPk.guard_count(4, 0), 2)
	assert_eq(MoralityPk.guard_count(4, -500), 2, "pk rule wins")
	assert_eq(MoralityPk.guard_count(0, -1), 1)
	assert_eq(MoralityPk.guard_count(3, -1), 1)
	assert_eq(MoralityPk.guard_count(0, 500), 0)

func test_kill_deltas() -> void:
	assert_eq(MoralityPk.kill_deltas("FORCED", 0), { "pk": 1, "killing_intent": 100, "morality": -10 })
	assert_eq(MoralityPk.kill_deltas("FORCED", -100), { "pk": 1, "killing_intent": 100, "morality": -10 }, "-100 is neutral")
	assert_eq(MoralityPk.kill_deltas("FORCED", -101), { "pk": 1, "killing_intent": 100, "morality": 10 }, "evil victim")
	assert_eq(MoralityPk.kill_deltas("FORCED", 900), { "pk": 1, "killing_intent": 100, "morality": -10 })
	assert_eq(MoralityPk.kill_deltas("CHALLENGE", 0), { "pk": 0, "killing_intent": 100, "morality": 0 })
	assert_eq(MoralityPk.kill_deltas("CHALLENGE", -900), { "pk": 0, "killing_intent": 100, "morality": 0 })

func test_align_of_boundaries() -> void:
	assert_eq(MoralityPk.align_of(0), "NEUTRAL")
	assert_eq(MoralityPk.align_of(100), "NEUTRAL")
	assert_eq(MoralityPk.align_of(101), "GOOD")
	assert_eq(MoralityPk.align_of(-100), "NEUTRAL")
	assert_eq(MoralityPk.align_of(-101), "EVIL")
	assert_eq(MoralityPk.align_of(1000), "GOOD")
	assert_eq(MoralityPk.align_of(-1000), "EVIL")

func test_newbie_protection() -> void:
	assert_false(MoralityPk.can_be_forced(499, 500))
	assert_true(MoralityPk.can_be_forced(500, 500))
	assert_true(MoralityPk.can_be_forced(0, 0), "protect 0 = everyone can be forced")
	assert_true(MoralityPk.is_newbie(0, 500))
	assert_false(MoralityPk.is_newbie(500, 500))

func test_constants_match_contract() -> void:
	assert_eq(MoralityPk.PK_DECAY_ONLINE_S, 1800.0)
	assert_eq(MoralityPk.GUARD_PK_THRESHOLD, 3)
	assert_eq(MoralityPk.ALIGN_GOOD_MIN, 101)
	assert_eq(MoralityPk.ALIGN_EVIL_MAX, -101)
	assert_eq(MoralityPk.clamp_morality(5000), 1000)
	assert_eq(MoralityPk.clamp_morality(-5000), -1000)

## M2 審查：一次強制擊殺不能讓平時行善的人（善惡 ≥ 10）立刻被官兵追殺；PK值 > 3 的寬限要有意義
func test_one_forced_kill_keeps_guard_grace_for_good_standing() -> void:
	for start in [10, 50, 100]:
		var d := MoralityPk.kill_deltas("FORCED", 0)
		var after := MoralityPk.clamp_morality(start + int(d["morality"]))
		assert_eq(MoralityPk.guard_count(1, after), 0, "start %d -> %d: no guard after one kill" % [start, after])
	# 三次之後（PK 3）仍不追殺；第四次（PK 4）才追殺
	var m := 50
	for i in 3:
		m += int(MoralityPk.kill_deltas("FORCED", 0)["morality"])
	assert_eq(MoralityPk.guard_count(3, m), 0, "pk 3, morality %d" % m)
	assert_eq(MoralityPk.guard_count(4, m), MoralityPk.GUARDS_PK)
	# 【已證實】善惡為負 → 進出城有官兵
	assert_eq(MoralityPk.guard_count(0, -1), MoralityPk.GUARDS_EVIL)
