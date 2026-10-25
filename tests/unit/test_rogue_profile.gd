extends "res://tests/test_case.gd"
## ROGUE_PLAN §3.9.3、§9.1（WP-RUN）：試煉者檔案的 normalize、壞檔退回預設／備份、apply_run（點數、歷史 20 筆、名人錄）。

var dir := ""
var r: Dictionary = {}

func before_each() -> void:
	dir = temp_dir("rogue_profile")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	r = RogueRules.DEFAULTS.duplicate(true)

func after_each() -> void:
	remove_dir_recursive(dir)

func test_default_and_normalize() -> void:
	var d := RogueProfile.default_profile()
	assert_eq(int(d.schema), 1)
	assert_eq(int(d.points_total), 0)
	assert_eq(d.history, [])
	var n := RogueProfile.normalize({ "points_total": 75.0, "runs": "3", "best_wins": -4, "famous_beaten": { "rg_f_x": 2.0, "y": 0 },
		"history": [{ "wins": 3.0, "cause": "WEIRD" }, "bad"], "extra": 1 })
	assert_eq(n.points_total, 60, "夾在上限 60")
	assert_eq(n.runs, 3, "字串轉 int")
	assert_eq(n.best_wins, 0, "負數歸 0")
	assert_eq(n.famous_beaten, { "rg_f_x": 2 }, "0 次的不留")
	assert_eq((n.history as Array).size(), 1, "壞的歷史列略過")
	assert_eq(str(n.history[0].cause), "DEATH", "不認得的死因 → DEATH")
	assert_false(n.has("extra"))
	assert_eq(RogueProfile.normalize("junk"), RogueProfile.default_profile())

func test_read_missing_corrupt_and_backup() -> void:
	assert_eq(RogueProfile.read(dir), RogueProfile.default_profile(), "檔案不在 → 預設")
	var path := RogueProfile.path(dir)
	assert_true(path.ends_with("rogue/profile.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	assert_eq(RogueProfile.read(dir), RogueProfile.default_profile(), "壞檔 → 預設")
	var b := FileAccess.open(path + ".bak1", FileAccess.WRITE)
	b.store_string(JSON.stringify({ "schema": 1, "points_total": 12, "runs": 4 }))
	b.close()
	var p := RogueProfile.read(dir)
	assert_eq(int(p.points_total), 12, "本體壞了 → 讀備份")
	var f2 := FileAccess.open(path, FileAccess.WRITE)
	f2.store_string(JSON.stringify({ "schema": 1, "points_total": 20, "runs": 5 }))
	f2.close()
	assert_eq(int(RogueProfile.read(dir).points_total), 20, "本體優先")

func test_apply_run_points_and_records() -> void:
	var p := RogueProfile.default_profile()
	var s1 := { "run_id": "a", "seed": 5, "cause": "DEATH", "rounds": 7, "wins": 6, "foes_beaten": 9, "bosses_beaten": 1,
		"best_card": { "id": "rg_c_art_hs_jianfa", "title": "華山劍法 二十五級", "rarity": "COMMON" },
		"famous_beaten": ["rg_f_zhouzhiruo"], "famous_allied": ["rg_c_ally_hufei"], "t": 1000 }
	var p1 := RogueProfile.apply_run(p, s1, r)
	assert_eq(int(s1.points_gained), 5, "首局 6 勝 1 首領 → 5")
	assert_eq(int(s1.points_total), 5)
	assert_true(bool(s1.new_best))
	assert_eq(int(p1.points_total), 5)
	assert_eq(int(p1.runs), 1)
	assert_eq(int(p1.best_wins), 6)
	assert_eq(int(p1.total_wins), 6)
	assert_eq(int(p1.foes_beaten), 9)
	assert_eq(int(p1.bosses_beaten), 1)
	assert_eq(p1.famous_beaten, { "rg_f_zhouzhiruo": 1 })
	assert_eq(p1.famous_allied, { "rg_c_ally_hufei": 1 })
	assert_eq(int(p1.history[0].points), 5)
	assert_eq(int(p1.history[0].t), 1000)
	assert_eq(int(p.points_total), 0, "不改傳進來的字典")
	var s2 := { "wins": 2, "bosses_beaten": 0, "cause": "ABANDON", "famous_beaten": ["rg_f_zhouzhiruo"], "t": 2000 }
	var p2 := RogueProfile.apply_run(p1, s2, r)
	assert_false(bool(s2.new_best))
	assert_eq(int(s2.points_gained), 2)
	assert_eq(p2.famous_beaten, { "rg_f_zhouzhiruo": 2 }, "名人錄計數")
	assert_eq(str(p2.history[0].cause), "ABANDON", "最新在前")
	assert_eq(str(p2.history[1].cause), "DEATH")

func test_history_cap_and_points_cap() -> void:
	var p := RogueProfile.default_profile()
	for i in 30:
		p = RogueProfile.apply_run(p, { "wins": 9, "bosses_beaten": 1, "cause": "DEATH", "t": 100 + i }, r)
		assert_true(int(p.points_total) <= 60, "從不超過 60")
	assert_eq((p.history as Array).size(), 20, "歷史最多 20 筆")
	assert_eq(int(p.history[0].t), 129, "最新在前")
	assert_eq(int(p.points_total), 60, "最後到上限")
	assert_eq(int(p.runs), 30)
