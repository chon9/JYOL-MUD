extends "res://tests/unit/test_world_fixture.gd"
## WP-ECON：生活技能第 2 版引擎（M3B_PLAN §4.5、§5.2.4、§11.1 test_m3b_life）。
## 工具檢查、設施檢查（配方 feature 覆寫）、等級門檻、產出放不下先拒絕、材料鏈 挖礦 → 打鐵 → 鑄劍 → 鐵劍、
## 樵夫燒炭、種麻棉、1.0A 世界沒有工匠。技能列與新物品由 WP-C-lifeskills_content 之後才進 data/ → 本機假資料。

const ROOM := "xx_square"

func before_each() -> void:
	world_name = "w_m3b_life"
	super.before_each()
	if ws.game != null:
		_install_fakes()

func _fake_item(id: String, item_name: String, weight := 1, extra := {}) -> void:
	var row := { "id": id, "name": item_name, "tab": "MATERIAL", "slot": "", "atk": 0, "def": 0, "weight": weight, "price": 10,
		"stack": 99, "spoil_days": 0, "effects": [], "usable": false, "usable_in_battle": false, "no_sell": false,
		"quest_item": false, "desc": "測試", "era": "1.0A", "src": "proposal" }
	row.merge(extra, true)
	if not tables()["items"].has(id):
		tables()["items"][id] = row

func _install_fakes() -> void:
	for t in [["t_shizigao", "十字鎬", 3], ["t_caishaqi", "採沙器", 2], ["t_tiechui", "打鐵鎚", 3], ["t_juzi", "鋸子", 2],
			["t_zhenxian", "針線包", 1]]:
		_fake_item(t[0], t[1], t[2], { "stack": 1, "tab": "OTHER", "tool": true })
	for m in [["r_kuang_tie", "鐵礦石", 2], ["r_tiekuai_1", "鐵塊", 3], ["r_mutan", "木炭", 1], ["r_zhongzi_ma", "麻種子", 1],
			["r_ma", "麻", 1], ["r_mianhua", "棉花", 1], ["r_xianzhou", "線軸", 1], ["r_mabu", "麻布", 1],
			["r_shoupi", "獸皮", 2], ["r_pige", "皮革", 2], ["r_shazi", "礦砂", 1]]:
		_fake_item(m[0], m[1], m[2])
	_fake_item("w_tiejian", "鐵劍", 4, { "tab": "WEAPON", "slot": "WEAPON", "weapon_type": "SWORD", "stack": 1 })
	_fake_item("w_lengning", "冷凝劍", 4, { "tab": "WEAPON", "slot": "WEAPON", "weapon_type": "SWORD", "stack": 1 })
	var ls: Dictionary = tables()["life_skills"]
	ls["life_mining"] = { "id": "life_mining", "name": "挖礦", "mode": "GATHER", "feature": "MINE", "tool": "t_shizigao",
		"tools": [], "verb": "挖礦", "jing_cost": 6, "cooldown_s": 5, "cap": 100,
		"yield": [ { "item": "r_kuang_tie", "chance": 1.0, "n": [1, 1], "min_level": 1 },
			{ "item": "r_kuang_lv", "chance": 1.0, "n": [1, 1], "min_level": 20 } ],
		"recipes": [ { "id": "rc_taoxi", "name": "淘洗", "inputs": [ { "item": "r_shazi", "n": 1 } ],
			"output": { "item": "r_kuang_tie", "n": 1 }, "min_level": 1, "tools": ["t_caishaqi"] } ],
		"era": "1.0A", "src": "later" }
	ls["life_smithing"] = { "id": "life_smithing", "name": "打鐵", "mode": "CRAFT", "feature": "FORGE", "tool": "t_tiechui",
		"jing_cost": 8, "cooldown_s": 5, "cap": 100, "yield": [],
		"recipes": [ { "id": "rc_tiekuai_1", "name": "鐵塊", "inputs": [ { "item": "r_kuang_tie", "n": 3 } ],
			"output": { "item": "r_tiekuai_1", "n": 1 }, "min_level": 1, "prof": 3 } ],
		"era": "1.0A", "src": "later" }
	ls["life_swordsmith"] = { "id": "life_swordsmith", "name": "鑄劍", "mode": "CRAFT", "feature": "CAST", "tool": "t_tiechui",
		"jing_cost": 10, "cooldown_s": 5, "cap": 100, "yield": [],
		"recipes": [ { "id": "rc_tiejian", "name": "鐵劍", "inputs": [ { "item": "r_tiekuai_1", "n": 1 }, { "item": "r_mutan", "n": 1 } ],
			"output": { "item": "w_tiejian", "n": 1 }, "min_level": 1 },
			{ "id": "rc_lengning", "name": "冷凝劍", "inputs": [ { "item": "r_tiekuai_1", "n": 2 }, { "item": "r_mutan", "n": 2 } ],
			"output": { "item": "w_lengning", "n": 1 }, "min_level": 30, "jing_cost": 30 } ],
		"era": "1.0A", "src": "later" }
	ls["life_weaving"] = { "id": "life_weaving", "name": "織布", "mode": "CRAFT", "feature": "LOOM", "tool": "",
		"jing_cost": 5, "cooldown_s": 5, "cap": 100, "yield": [],
		"recipes": [ { "id": "rc_xianzhou", "name": "線軸", "inputs": [ { "item": "r_ma", "n": 2 } ],
			"output": { "item": "r_xianzhou", "n": 1 }, "min_level": 1 },
			{ "id": "rc_pige", "name": "皮革", "inputs": [ { "item": "r_shoupi", "n": 1 } ],
			"output": { "item": "r_pige", "n": 1 }, "min_level": 1, "feature": "TANNERY" } ],
		"era": "1.0A", "src": "later" }
	ls["life_tailoring"] = { "id": "life_tailoring", "name": "裁縫", "mode": "CRAFT", "feature": "", "tool": "t_zhenxian",
		"jing_cost": 5, "cooldown_s": 5, "cap": 100, "yield": [],
		"recipes": [ { "id": "rc_dummy_bag", "name": "布包", "inputs": [ { "item": "r_mabu", "n": 1 } ],
			"output": { "item": "r_xianzhou", "n": 1 }, "min_level": 1 } ],
		"era": "1.0A", "src": "proposal" }
	ls["life_carpentry"] = { "id": "life_carpentry", "name": "工匠", "mode": "CRAFT", "feature": "", "tool": "t_juzi",
		"jing_cost": 5, "cooldown_s": 5, "cap": 100, "yield": [],
		"recipes": [ { "id": "rc_mudao", "name": "木刀", "inputs": [ { "item": "r_wood", "n": 2 } ],
			"output": { "item": "w_mudao", "n": 1 }, "min_level": 1 } ],
		"era": "1.0B", "src": "verified" }
	# 既有列的替換（§4.5）：樵夫加燒炭（KILN）、種田加種麻（FIELD）
	var wc: Dictionary = ls["life_woodcut"]
	wc["recipes"] = [ { "id": "rc_shaotan", "name": "燒炭", "inputs": [ { "item": "r_wood", "n": 3 } ],
		"output": { "item": "r_mutan", "n": 1 }, "min_level": 1, "feature": "KILN" } ]
	var fm: Dictionary = ls["life_farming"]
	fm["recipes"] = [ { "id": "rc_zhongma", "name": "種麻", "inputs": [ { "item": "r_zhongzi_ma", "n": 1 } ],
		"output": { "item": "r_ma", "n": 2 }, "min_level": 10, "feature": "FIELD" } ]

func _room_features(feats: Array, room := ROOM) -> void:
	host().index.room(room)["features"] = feats

func _learn(skill: String, lv := 1) -> void:
	ch().skills.set_level(skill, lv, tables())

func _work(skill: String, recipe := "") -> Dictionary:
	Survival.rest_full(ch(), tables(), ws.options)
	ch().counters.erase(LifeSystem.CD_KEY)
	return send("work", { "skill": skill, "recipe": recipe })

func _work_reason(skill: String, recipe := "") -> String:
	return str(_work(skill, recipe).get("reason", ""))

## 反覆做到拿到 n 個 item；回傳嘗試次數
func _work_until(skill: String, item: String, n: int, recipe := "", max_tries := 60) -> int:
	var tries := 0
	while item_count(item) < n and tries < max_tries:
		tries += 1
		var r := _work(skill, recipe)
		assert_true(r.get("ok", false), "work %s %s: %s" % [skill, recipe, str(r)])
		if not r.get("ok", false):
			break
	return tries

func _setup() -> bool:
	if not game_ok():
		return false
	if make_char("工匠") == null:
		return false
	goto(ROOM)
	clear_events()
	return true

# ---------- 驗證順序 ----------
func test_tool_and_feature_checks() -> void:
	if not _setup():
		return
	_room_features([])
	assert_eq(_work_reason("life_mining"), "no_feature", "沒有礦場")
	_room_features(["MINE"])
	assert_eq(_work_reason("life_mining"), "not_known")
	_learn("life_mining")
	assert_eq(_work_reason("life_mining"), "no_tool", "沒有十字鎬")
	give("t_shizigao")
	_work_until("life_mining", "r_kuang_tie", 1)
	assert_true(item_count("r_kuang_tie") >= 1, "採到鐵礦石")
	assert_eq(item_count("r_kuang_lv"), 0, "綠石礦要 20 級")
	# 配方另要的工具（淘洗要採沙器）
	give("r_shazi", 2)
	assert_eq(_work_reason("life_mining", "rc_taoxi"), "no_tool", "配方 tools")
	give("t_caishaqi")
	var before := item_count("r_kuang_tie")
	_work_until("life_mining", "r_kuang_tie", before + 1, "rc_taoxi")
	assert_true(item_count("r_kuang_tie") > before, "淘洗")
	# 技能 tools 欄（除了 tool 之外也要帶）
	tables()["life_skills"]["life_mining"]["tools"] = ["t_juzi"]
	assert_eq(_work_reason("life_mining"), "no_tool", "技能 tools")
	# 冷卻 busy、精不足
	tables()["life_skills"]["life_mining"]["tools"] = []
	assert_true(_work("life_mining").get("ok", false))
	assert_eq(reason("work", { "skill": "life_mining" }), "busy")
	ch().counters.erase(LifeSystem.CD_KEY)
	ch().vitals["jing"] = 2
	assert_eq(reason("work", { "skill": "life_mining" }), "not_enough_jing")

func test_level_gate_yield_and_recipe() -> void:
	if not _setup():
		return
	_room_features(["MINE", "CAST"])
	_learn("life_mining", 20)
	give("t_shizigao")
	_work_until("life_mining", "r_kuang_lv", 1)
	assert_true(item_count("r_kuang_lv") >= 1, "20 級擲得到綠石礦")
	_learn("life_swordsmith", 29)
	give("t_tiechui")
	give("r_tiekuai_1", 2)
	give("r_mutan", 2)
	assert_eq(_work_reason("life_swordsmith", "rc_lengning"), "recipe_level", "冷凝劍要 30 級")
	_learn("life_swordsmith", 30)
	ch().vitals["jing"] = 20
	ch().counters.erase(LifeSystem.CD_KEY)
	assert_eq(reason("work", { "skill": "life_swordsmith", "recipe": "rc_lengning" }), "not_enough_jing", "配方 jing_cost 30")
	assert_eq(_work_reason("life_swordsmith", "rc_nothing"), "no_recipe")
	assert_eq(_work_reason("life_swordsmith"), "no_recipe", "CRAFT 一定要配方")

func test_recipe_feature_override() -> void:
	if not _setup():
		return
	_learn("life_woodcut")
	give("w_chaidao")
	give("r_wood", 6)
	_room_features(["KILN"])
	assert_eq(_work_reason("life_woodcut"), "no_feature", "採木材要 WOOD")
	_work_until("life_woodcut", "r_mutan", 1, "rc_shaotan")
	assert_eq(item_count("r_mutan"), 1, "燒炭")
	assert_eq(item_count("r_wood"), 3, "木材 ×3 → 木炭 ×1")
	_room_features(["WOOD"])
	assert_eq(_work_reason("life_woodcut", "rc_shaotan"), "no_feature", "燒炭要 KILN")
	# 織布：皮革配方在 TANNERY
	_learn("life_weaving")
	give("r_shoupi", 1)
	_room_features(["LOOM"])
	assert_eq(_work_reason("life_weaving", "rc_pige"), "no_feature")
	_room_features(["TANNERY"])
	assert_eq(_work_reason("life_weaving", "rc_xianzhou"), "no_feature", "線軸在 LOOM")
	_work_until("life_weaving", "r_pige", 1, "rc_pige")
	assert_eq(item_count("r_pige"), 1)
	# 裁縫：隨地（feature ""）
	_room_features([])
	_learn("life_tailoring")
	give("t_zhenxian")
	give("r_mabu", 1)
	_work_until("life_tailoring", "r_xianzhou", 1, "rc_dummy_bag")
	assert_eq(item_count("r_mabu"), 0, "隨地裁縫")

func test_farming_hemp_and_rice_same_skill() -> void:
	if not _setup():
		return
	_room_features(["FIELD"])
	_learn("life_farming", 9)
	give("t_chutou")
	give("r_zhongzi_ma", 2)
	assert_eq(_work_reason("life_farming", "rc_zhongma"), "recipe_level", "種麻 10 級")
	_learn("life_farming", 10)
	_work_until("life_farming", "r_ma", 2, "rc_zhongma")
	assert_eq(item_count("r_ma"), 2, "麻種子 → 麻 ×2")
	_work_until("life_farming", "r_rice", 1)
	assert_true(item_count("r_rice") >= 1, "recipe 空 = 採集稻米")

func test_output_wont_fit_rejected_first() -> void:
	if not _setup():
		return
	_room_features(["FORGE", "MINE"])
	_learn("life_smithing")
	give("t_tiechui")
	give("r_kuang_tie", 3)
	tables()["items"]["r_tiekuai_1"]["weight"] = 1000000
	var jing_before := 0
	Survival.rest_full(ch(), tables(), ws.options)
	jing_before = int(ch().vitals["jing"])
	ch().counters.erase(LifeSystem.CD_KEY)
	assert_eq(reason("work", { "skill": "life_smithing", "recipe": "rc_tiekuai_1" }), "too_heavy")
	assert_eq(int(ch().vitals["jing"]), jing_before, "不扣精")
	assert_eq(item_count("r_kuang_tie"), 3, "不扣材料")
	assert_eq(float(ch().counters.get(LifeSystem.CD_KEY, 0.0)), 0.0, "不設冷卻")
	# 採集：最多可能拿到的放不下也先拒絕
	_learn("life_mining")
	give("t_shizigao")
	tables()["items"]["r_kuang_tie"]["weight"] = 1000000
	assert_eq(_work_reason("life_mining"), "too_heavy")

func test_chain_mine_smith_sword() -> void:
	if not _setup():
		return
	_room_features(["MINE", "FORGE", "CAST", "KILN", "WOOD"])
	for sk in ["life_mining", "life_smithing", "life_swordsmith", "life_woodcut"]:
		_learn(sk)
	give("t_shizigao")
	give("t_tiechui")
	give("w_chaidao")
	_work_until("life_mining", "r_kuang_tie", 3)
	assert_true(item_count("r_kuang_tie") >= 3, "挖到 3 個鐵礦石")
	var prof0 := int(ch().skills.prof("life_smithing"))
	var tries := _work_until("life_smithing", "r_tiekuai_1", 1, "rc_tiekuai_1")
	assert_eq(item_count("r_tiekuai_1"), 1, "3 同級礦 → 鐵塊")
	# 熟練：成功那次 ×3（prof 3），失敗的每次 +2
	var expect := (tries - 1) * Learning.LIFE_PROF_FAIL + 3 * Learning.LIFE_PROF_OK
	assert_eq(int(ch().skills.prof("life_smithing")) - prof0, expect, "配方 prof 倍數")
	_work_until("life_woodcut", "r_wood", 3)
	_work_until("life_woodcut", "r_mutan", 1, "rc_shaotan")
	_work_until("life_swordsmith", "w_tiejian", 1, "rc_tiejian")
	assert_eq(item_count("w_tiejian"), 1, "鐵塊＋木炭 → 鐵劍")
	assert_eq(item_count("r_tiekuai_1"), 0)

func test_generic_template_fallback() -> void:
	if not _setup():
		return
	_room_features(["MINE"])
	_learn("life_mining")
	give("t_shizigao")
	_work_until("life_mining", "r_kuang_tie", 1)
	ws.flush()
	if tables()["text_templates"].has("work_ok_life_mining"):
		assert_false(last("work_ok_life_mining").is_empty())
	else:
		assert_false(last(LifeSystem.E_WORK_OK_GENERIC).is_empty(), "沒有專屬模板 → e_work_ok")
		assert_eq(str(lastp(LifeSystem.E_WORK_OK_GENERIC).get("skill_name", "")), "挖礦")

func test_carpentry_needs_1_0b() -> void:
	if not _setup():
		return
	_learn("life_carpentry")
	give("t_juzi")
	give("r_wood", 2)
	_room_features([])
	_work_until("life_carpentry", "w_mudao", 1, "rc_mudao")
	assert_eq(item_count("w_mudao"), 1, "工匠隨地做木刀")
	# 1.0A 閉包：資料裡 era 1.0B 的列不在生效視圖 → not_known
	tables()["life_skills"].erase("life_carpentry")
	assert_eq(_work_reason("life_carpentry", "rc_mudao"), "not_known", "1.0A 世界沒有工匠")
	# 合併後的真資料：1.0A 生效視圖不含工匠
	var raw: Dictionary = GameData.loader.all_tables.get("life_skills", {}) if GameData.get("loader") != null else {}
	if raw.has("life_carpentry"):
		var view_a: Dictionary = GameData.loader.activate(["1.0A"])
		assert_false(view_a.get("life_skills", {}).has("life_carpentry"), "1.0A 視圖沒有 life_carpentry")

func test_legacy_rows_unchanged() -> void:
	if not _setup():
		return
	# 舊廚師列沒有 mode → CRAFT；沒給配方 → no_recipe（M1 行為）
	goto("xx_inn")
	_learn("life_cooking")
	assert_eq(RecipeCheck.mode_of(tables()["life_skills"]["life_cooking"]), "CRAFT")
	assert_eq(_work_reason("life_cooking"), "no_recipe")
	give("r_rice", 2)
	_work_until("life_cooking", "c_baifan", 1, "rc_baifan")
	assert_true(item_count("c_baifan") >= 1)

# ---------- 純邏輯 ----------
func test_recipe_check_pure() -> void:
	assert_eq(RecipeCheck.mode_of({ "yield": [{ "item": "a" }], "recipes": [] }), "GATHER")
	assert_eq(RecipeCheck.mode_of({ "yield": [], "recipes": [{ "id": "x" }] }), "CRAFT")
	assert_eq(RecipeCheck.mode_of({ "mode": "HUNT" }), "HUNT")
	assert_eq(RecipeCheck.mode_of({ "mode": "bogus", "yield": [{ "item": "a" }] }), "GATHER")
	var row := { "feature": "FORGE", "tool": "t_a", "tools": ["t_b", "t_a"], "jing_cost": 7,
		"recipes": [ { "id": "r1", "feature": "", "tools": ["t_c"], "jing_cost": 3, "prof": 4, "inputs": [{ "item": "m", "n": 2 }],
			"output": { "item": "o", "n": 1 } }, { "id": "r2" } ] }
	var r1 := RecipeCheck.find_recipe(row, "r1")
	assert_eq(RecipeCheck.feature_for(row, r1), "", "配方 feature 覆寫成隨地")
	assert_eq(RecipeCheck.feature_for(row, RecipeCheck.find_recipe(row, "r2")), "FORGE")
	assert_eq(RecipeCheck.feature_for(row, {}), "FORGE")
	assert_true(RecipeCheck.has_feature([], ""))
	assert_false(RecipeCheck.has_feature(["MINE"], "FORGE"))
	assert_eq(RecipeCheck.tools_needed(row, r1), ["t_a", "t_b", "t_c"], "去重")
	assert_eq(RecipeCheck.jing_cost(row, r1), 3)
	assert_eq(RecipeCheck.jing_cost(row, {}), 7)
	assert_eq(RecipeCheck.prof_mult(r1), 4)
	assert_eq(RecipeCheck.prof_mult({}), 1)
	assert_eq(RecipeCheck.inputs_of(r1), [["m", 2]])
	assert_eq(RecipeCheck.output_of(r1), [["o", 1]])
	assert_eq(RecipeCheck.n_range([3, 1]), [1, 3])
	assert_eq(RecipeCheck.n_range(2), [2, 2])
	var g := { "yield": [ { "item": "a", "n": [1, 2] }, { "item": "b", "n": [1, 1], "min_level": 5 } ] }
	assert_eq(RecipeCheck.gather_max(g, 1), [["a", 2]])
	assert_eq(RecipeCheck.gather_max(g, 5), [["a", 2], ["b", 1]])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	assert_eq(RecipeCheck.pick_hunt_monster([], rng), "")
	assert_eq(RecipeCheck.pick_hunt_monster([{ "monster": "m_x", "w": 0 }, { "monster": "m_y", "w": 5 }], rng), "m_y")
	var inv := Inventory.new()
	var st := RecipeCheck.recipe_status(row, r1, 1, inv, [])
	assert_eq(st["reason"], "no_tool")
	assert_eq(st["missing_tools"], ["t_a", "t_b", "t_c"])
