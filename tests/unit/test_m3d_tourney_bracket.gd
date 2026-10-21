extends "res://tests/test_case.gd"
## M3D_PLAN §5.3.3、§10.1（WP-EVENTS）：TourneyRules 的對戰表（2–17 人、輪空、上屆冠軍種子、可重現）、晉級、名次、限時判定、稱號。

static func _ids(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append("c%02d" % i)
	return out

func test_bracket_sizes_and_byes() -> void:
	assert_eq(TourneyRules.bracket(_ids(0), "", 1), [], "0 人 → 不開")
	assert_eq(TourneyRules.bracket(_ids(1), "", 1), [], "1 人 → 不開（至少 2 人）")
	for n in range(2, 18):
		var ids := _ids(n)
		var br := TourneyRules.bracket(ids, "", 7)
		var size := TourneyRules.bracket_size(n)
		assert_eq(br.size(), size / 2, "%d 人：%d 場" % [n, size / 2])
		var seen := {}
		var byes := 0
		for m in br:
			var a := str(m[0])
			var b := str(m[1])
			assert_false(a == "" and b == "", "%d 人：不會有兩邊都輪空的場次" % n)
			for x in [a, b]:
				if x == "":
					byes += 1
				else:
					assert_false(seen.has(x), "%d 人：%s 只出現一次" % [n, x])
					seen[x] = true
		assert_eq(seen.size(), n, "%d 人全部在表上" % n)
		assert_eq(byes, size - n, "%d 人：輪空 %d" % [n, size - n])

func test_bracket_five_has_three_byes() -> void:
	var br := TourneyRules.bracket(_ids(5), "", 3)
	var byes := 0
	for m in br:
		if str(m[1]) == "" or str(m[0]) == "":
			byes += 1
	assert_eq(byes, 3, "5 人 → 輪空 3（驗收劇本 tourney）")

func test_bracket_reproducible_and_seeded() -> void:
	var ids := _ids(11)
	assert_eq(TourneyRules.bracket(ids, "", 42), TourneyRules.bracket(ids, "", 42), "同一個 seed 同一張表")
	var diff := false
	for s in range(1, 20):
		if TourneyRules.bracket(ids, "", s) != TourneyRules.bracket(ids, "", 42):
			diff = true
	assert_true(diff, "不同 seed 會洗出不同的表")

func test_champion_seeded_in_lower_half() -> void:
	for n in [2, 3, 5, 8, 13, 17]:
		var ids := _ids(n)
		var champ := str(ids[n - 1])
		for s in [1, 2, 3]:
			var br := TourneyRules.bracket(ids, champ, s)
			var slot := (br.size() / 2) if br.size() > 1 else 0
			assert_eq(str(br[slot][0]), champ, "%d 人 seed %d：上屆冠軍在下半區種子位（第 %d 場第一格）" % [n, s, slot])
	# 上屆冠軍沒報名 → 照常洗牌
	var br2 := TourneyRules.bracket(_ids(4), "nobody", 5)
	assert_eq(br2.size(), 2)

func test_next_round_and_places() -> void:
	# 5 人：c00..c04；第一輪 [a, b]，自己排一張已知的表來算名次
	var r1 := [{ "a": "A", "b": "", "winner": "A" }, { "a": "B", "b": "", "winner": "B" },
		{ "a": "C", "b": "", "winner": "C" }, { "a": "D", "b": "E", "winner": "E" }]
	var nr := TourneyRules.next_round(["A", "B", "C", "E"])
	assert_eq(nr, [["A", "B"], ["C", "E"]], "勝者兩兩配對")
	var r2 := [{ "a": "A", "b": "B", "winner": "A" }, { "a": "C", "b": "E", "winner": "C" }]
	var r3 := [{ "a": "A", "b": "C", "winner": "C" }]
	var order := { "A": 1, "B": 2, "C": 3, "D": 4, "E": 5 }
	var pl := TourneyRules.places([r1, r2, r3], order)
	var got := {}
	for p in pl:
		got[str(p.id)] = int(p.place)
	assert_eq(got, { "C": 1, "A": 2, "B": 3, "E": 3, "D": 5 }, "冠軍 1、亞軍 2、四強 3、八強 5（輪空不算贏）")
	assert_eq(str(pl[0].id), "C")
	assert_eq(str(pl[2].id), "B", "同名次依報名先後")
	# 兩人都點名不到（勝者 ""）：兩個都算輸家，沒有冠軍
	var pl2 := TourneyRules.places([[{ "a": "X", "b": "Y", "winner": "" }]], {})
	assert_eq(pl2.size(), 2)
	assert_eq(int(pl2[0].place), 2)

func test_judge_three_tiers() -> void:
	var base := { "dmg": 100, "hits": 5, "qi": 500, "qi_max": 1000, "order": 2 }
	var a := base.duplicate()
	var b := base.duplicate()
	a["dmg"] = 101
	assert_eq(TourneyRules.judge(a, b), 0, "總傷害多者勝")
	a = base.duplicate()
	b["hits"] = 6
	assert_eq(TourneyRules.judge(a, b), 1, "傷害相同 → 命中多者勝")
	b = base.duplicate()
	b["qi"] = 600
	assert_eq(TourneyRules.judge(a, b), 1, "命中也相同 → 氣比例高者勝")
	var c := { "dmg": 100, "hits": 5, "qi": 300, "qi_max": 600, "order": 9 }   # 比例 0.5 同 a
	assert_eq(TourneyRules.judge(a, c), 0, "全都一樣 → 先報名者（order 小）勝")
	assert_eq(TourneyRules.judge(c, a), 1)

func test_titles_and_fame() -> void:
	assert_eq(TourneyRules.title_for("WULIN", 0), "武林盟主")
	assert_eq(TourneyRules.title_for("WULIN", 1), "")
	assert_eq(TourneyRules.title_for("SECT:shaolin", 0), "少林派掌門師兄")
	assert_eq(TourneyRules.title_for("SECT:shaolin", 1), "", "只有全真有 2–7 名的稱號")
	assert_eq(TourneyRules.title_for("SECT:quanzhen", 0), "全真派天樞真人")
	assert_eq(TourneyRules.title_for("SECT:quanzhen", 1), "天璇真人")
	assert_eq(TourneyRules.title_for("SECT:quanzhen", 6), "搖光真人")
	assert_eq(TourneyRules.title_for("SECT:quanzhen", 7), "")
	assert_eq(TourneyRules.wulin_fame(0), 3000)
	assert_eq(TourneyRules.wulin_fame(2), 1200, "四強取 1200（M3d 審查）")
	assert_eq(TourneyRules.wulin_fame(3), 1200)
	assert_eq(TourneyRules.wulin_fame(4), 300, "八強取 300")
	assert_eq(TourneyRules.wulin_fame(7), 300)
	assert_eq(TourneyRules.wulin_fame(8), 0)
	for sid in ["shaolin", "huashan", "emei", "gumu", "hengshan", "lingjiu", "quanzhen", "wudang", "xingxiu", "xuedao", "gaibang"]:
		assert_true(TourneyRules.SECT_TITLES.has(sid) and TourneyRules.SECT_SCHEDULE.has(sid), "門派 %s 有稱號與時辰" % sid)

func test_rewarded_rule() -> void:
	assert_false(TourneyRules.rewarded(3, 100, -1), "報名 < 4 → 表演賽")
	assert_true(TourneyRules.rewarded(4, 100, -1), "4 人、從沒發過 → 發")
	assert_false(TourneyRules.rewarded(8, 100, 80), "30 遊戲日內發過 → 表演賽")
	assert_true(TourneyRules.rewarded(8, 110, 80), "滿 30 日 → 發")
	# M3d 審查：另加現實 30 日冷卻
	var d30 := TourneyRules.REWARD_COOLDOWN_REAL_DAYS * TourneyRules.REAL_DAY_S
	assert_false(TourneyRules.rewarded(8, 110, 80, 1000.0 + d30 - 1.0, 1000.0), "現實不到 30 日 → 表演賽")
	assert_true(TourneyRules.rewarded(8, 110, 80, 1000.0 + d30, 1000.0), "現實滿 30 日 → 發")
	assert_true(TourneyRules.rewarded(8, 110, 80, 5000.0, -1.0), "舊存檔沒記現實時間 → 只看遊戲日")
	assert_false(TourneyRules.rewarded(8, 100, 80, 1.0e9, 1.0), "遊戲日不夠仍不發")

func test_kind_helpers() -> void:
	assert_true(TourneyRules.valid_kind("WULIN"))
	assert_true(TourneyRules.valid_kind("SECT:emei"))
	assert_false(TourneyRules.valid_kind("SECT:"))
	assert_false(TourneyRules.valid_kind("SECT:nobody"))
	assert_eq(TourneyRules.sect_of("SECT:wudang"), "wudang")
	assert_eq(TourneyRules.kind_name("SECT:wudang", { "wudang": "武當" }), "武當門派比武")
