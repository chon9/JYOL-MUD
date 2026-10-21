extends "res://tests/unit/test_world_fixture.gd"
## M3D_PLAN §6.4、E5、§10.1（WP-ERRANDS）：黑龍潭（1.0B 小區域）。
## 五行八卦陣走法（走錯繞回陣口）、1.0A 世界沒有往南的出口、九尾靈狐（瑛姑的委託、捉狐戰、意外收獲擲骰可重現、
## 5% 夜明珠結局）、南坡羊群與白猿扣善惡、沙漠山洞的白猿、武當七獸白猿照舊不扣。

const A := preload("res://tests/unit/test_m3c_npc_attack.gd")
const PATH := ["S", "S", "E", "S", "W", "S"]   # 黑龍潭 → hl_mud1 → … → hl_hut

func _char() -> bool:
	if not game_ok():
		return false
	if make_char("闖陣的人") == null:
		return false
	ws.options["encounters_enabled"] = false
	Survival.rest_full(ch(), tables(), ws.options)
	clear_events()
	return true

func _pick(npc: String, qid: String, node: String, choice: String) -> void:
	ok("dialogue_choose", { "npc": npc, "quest": qid, "node": node, "choice": choice })

func _walk(dirs: Array) -> void:
	for d in dirs:
		ok("move", { "dir": d })

# ---------------------------------------------------------------- 地圖
func test_maze_walk_and_wrong_turns() -> void:
	if not _char():
		return
	goto("xe_heilong")
	_walk(["S"])
	assert_eq(s().room_id(), "hl_mud1", "從黑龍潭往南進泥沼")
	_walk(["S"])
	assert_eq(s().room_id(), "hl_mud2")
	_walk(["W"])
	assert_eq(s().room_id(), "hl_mud1", "走錯（西）繞回陣口")
	_walk(["S", "E", "S"])
	assert_eq(s().room_id(), "hl_mud4")
	_walk(["E"])
	assert_eq(s().room_id(), "hl_mud1", "第四步走錯也繞回陣口")
	_walk(["S", "E", "S", "W", "S"])
	assert_eq(s().room_id(), "hl_hut", "照石碑「離震離兌離」走到瑛姑小屋")
	_walk(["N", "E", "N", "W", "N", "N"])
	assert_eq(s().room_id(), "xe_heilong", "照原路退得出去")
	goto("hl_hut")
	_walk(["OUT"])
	assert_eq(s().room_id(), "xe_heilong", "屋後小路直接出陣")
	assert_eq(str(tables()["regions"]["heilongtan"]["type"]), "DUNGEON")
	assert_eq(str(tables()["regions"]["heilongtan"]["era"]), "1.0B")

## M3d 審查：陣內的出口按鈕一律寫「八卦泥陣」，不洩漏哪個方向繞回陣口（黑龍潭泥沼）
func test_maze_exit_names_hidden() -> void:
	if not _char():
		return
	goto("hl_mud3")
	var v: Dictionary = host().regions.view(s())
	var names: Array = []
	for ex in v.get("exits", []):
		names.append(str(ex.get("to_name", "")))
	assert_eq(names.size(), 4)
	for nm in names:
		assert_eq(nm, "八卦泥陣", "出口名稱不洩漏去處")
	goto("hl_hut")
	var v2: Dictionary = host().regions.view(s())
	var to_names := {}
	for ex in v2.get("exits", []):
		to_names[str(ex.get("to", ""))] = str(ex.get("to_name", ""))
	assert_eq(str(to_names.get("hl_mud5", "")), "八卦泥陣", "陣外照常顯示去處")
	assert_eq(str(to_names.get("hl_fox", "")), str(host().room_name("hl_fox")))

func test_1_0a_world_has_no_south_exit() -> void:
	if not _char():
		return
	use_eras(["1.0A"])
	goto("xe_heilong")
	assert_eq(reason("move", { "dir": "S" }), "no_exit", "1.0A 世界黑龍潭沒有往南的出口")
	assert_false(tables()["regions"].has("heilongtan"))
	assert_false(tables()["quests"].has("q_er_jiuwei"))

func test_npcs_in_place() -> void:
	assert_eq(str(tables()["npcs"]["n_er_yinggu"]["room"]), "hl_hut")
	assert_eq(str(tables()["npcs"]["n_er_cien"]["room"]), "hl_mud3")
	assert_true("q_er_jiuwei" in tables()["npcs"]["n_er_yinggu"]["quests"])

# ---------------------------------------------------------------- 九尾靈狐
func _accept_jiuwei() -> void:
	goto("hl_hut")
	ok("quest_accept", { "npc": "n_er_yinggu", "quest": "q_er_jiuwei" })
	_pick("n_er_yinggu", "q_er_jiuwei", "n0", "c_ask")
	_pick("n_er_yinggu", "q_er_jiuwei", "n1", "c_yes")
	assert_true(QuestState.is_active(ch().quests, "q_er_jiuwei"))

func _luck() -> int:
	return int(QuestState.active_entry(ch().quests, "q_er_jiuwei").get("vars", {}).get("luck", -1))

func _hunt_and_turn_in(win := true) -> void:
	goto("hl_fox")
	ok("story_act", { "act": "q_er_jiuwei:a_hunt" })
	assert_true(s().battle_id != 0, "開打九尾靈狐")
	A.finish(self, 1, win)
	if not win:
		return
	assert_eq(item_count("i_er_hulixue"), 1, "取得靈狐血")
	goto("hl_hut")
	ok("quest_talk", { "npc": "n_er_yinggu", "quest": "q_er_jiuwei" })
	_pick("n_er_yinggu", "q_er_jiuwei", "n0", "c_give")

func test_jiuwei_default() -> void:
	if not _char():
		return
	make_strong()
	_accept_jiuwei()
	assert_true(_luck() >= 1 and _luck() <= 20, "接任務時擲意外收獲（1–20）")
	(QuestState.active_entry(ch().quests, "q_er_jiuwei")["vars"] as Dictionary)["luck"] = 7
	var lp0 := int(ch().learn_points)
	var f0 := int(ch().fame)
	_hunt_and_turn_in()
	assert_eq(str(QuestState.done_entry(ch().quests, "q_er_jiuwei").get("outcome", "")), "default")
	assert_eq(int(ch().learn_points) - lp0 >= 100, true, "學點 +100（加上靈狐本身的少量學點）")
	assert_eq(int(ch().fame) - f0, 20, "名聲 +20")
	assert_eq(item_count("i_er_hulixue"), 0, "靈狐血交出去")
	assert_eq(item_count("i_cb_yemingzhu"), 0, "沒有夜明珠")
	assert_eq(reason("quest_accept", { "npc": "n_er_yinggu", "quest": "q_er_jiuwei" }), Protocol.R_QUEST_COOLDOWN, "冷卻 3 遊戲日")

func test_jiuwei_pearl() -> void:
	if not _char():
		return
	if not tables()["items"].has("i_cb_yemingzhu"):
		assert_true(false, "WP-COMBAT 的 i_cb_yemingzhu 不在（整合前）")
		return
	make_strong()
	_accept_jiuwei()
	(QuestState.active_entry(ch().quests, "q_er_jiuwei")["vars"] as Dictionary)["luck"] = 1
	_hunt_and_turn_in()
	assert_eq(str(QuestState.done_entry(ch().quests, "q_er_jiuwei").get("outcome", "")), "pearl")
	assert_eq(item_count("i_cb_yemingzhu"), 1, "意外收獲：夜明珠")

func test_jiuwei_fox_escapes_retry() -> void:
	if not _char():
		return
	make_strong()
	_accept_jiuwei()
	_hunt_and_turn_in(false)
	assert_eq(item_count("i_er_hulixue"), 0)
	assert_eq(str(QuestState.active_entry(ch().quests, "q_er_jiuwei").get("stage", "")), "s_catch", "沒捉到：還在捉狐")

func test_luck_roll_reproducible() -> void:
	if not _char():
		return
	var rolls: Array = []
	for i in 2:
		ws.rng.seed = 424242
		_accept_jiuwei()
		rolls.append(_luck())
		ok("quest_abandon", { "quest": "q_er_jiuwei" })
	assert_eq(rolls[0], rolls[1], "同一個種子擲出同一個結果")
	var ones := 0
	for i in 400:
		var r := RandomNumberGenerator.new()
		r.seed = 1000 + i
		if r.randi_range(0, 19) == 0:
			ones += 1
	assert_true(ones > 5 and ones < 40, "5%% 左右（%d／400）" % ones)

# ---------------------------------------------------------------- 羊群與白猿
func _kill_all(monsters: Array) -> int:
	var m0 := int(ch().morality)
	start_battle(monsters)
	A.finish(self, 1, true)
	return int(ch().morality) - m0

func test_sheep_and_ape_lower_morality() -> void:
	if not _char():
		return
	make_strong()
	ch().morality = 1000
	goto("hl_slope")
	assert_eq(_kill_all(["m_er_yang", "m_er_yang", "m_er_yang", "m_er_yang"]), -100, "一群 4 隻羊：善惡 −100（一次減 100 左右）")
	assert_eq(_kill_all(["m_er_baiyuan"]), -5, "白猿 −5")
	assert_eq(_kill_all(["m_wd_baiyuan"]), 0, "武當龍門七獸的白猿照 M3c 不扣")

func test_encounter_tables() -> void:
	var slope: Dictionary = {}
	var cave: Dictionary = {}
	for rid in tables()["maps"]:
		for r in tables()["maps"][rid]["rooms"]:
			if r["id"] == "hl_slope":
				slope = r
			elif r["id"] == "dlw_desertcave":
				cave = r
	var ids: Array = []
	for e in slope.get("encounter", {}).get("table", []):
		ids.append(str(e["monster"]))
	assert_true("m_er_yang" in ids and "m_er_baiyuan" in ids, "南坡：羊群與白猿")
	var ids2: Array = []
	for e in cave.get("encounter", {}).get("table", []):
		ids2.append(str(e["monster"]))
	assert_true("m_er_baiyuan" in ids2, "沙漠山洞有白猿（E5）")
	assert_eq(str(tables()["monsters"]["m_er_baiyuan"]["era"]), "1.0A")

# ---------------------------------------------------------------- 截圖（只在有視窗時；headless 直接略過）
## K:/Project/JY-Mini-OL-Work/shots/m3d/WP-ERRANDS/：黑龍潭的場景與區域圖、瑛姑的委託對話、三八紅的對話、武林帖開打
const SHOTS_DIR := "K:/Project/JY-Mini-OL-Work/shots/m3d/WP-ERRANDS"

func _shot(main: Node, name: String) -> void:
	for i in 90:   # 對話框逐字顯示，等它跑完
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := tree.root.get_texture().get_image()
	if img == null:
		return
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	img.save_png(SHOTS_DIR.path_join(name + ".png"))

func test_ui_shots() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not _char():
		return
	make_strong()
	ch().fame = 600
	ch().lilian = 600
	var main: Node = (load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	goto("xe_heilong")
	await _shot(main, "er_01_xe_heilong")
	_walk(["S", "S", "W"])
	await _shot(main, "er_02_maze_wrong_turn")
	_walk(["S", "E", "S", "W", "S"])
	main.open_panel("map")
	await _shot(main, "er_03_heilongtan_map")
	main.close_panel()
	ok("talk", { "npc": "n_er_yinggu" })
	await _shot(main, "er_04_yinggu_menu")
	ok("quest_accept", { "npc": "n_er_yinggu", "quest": "q_er_jiuwei" })
	_pick("n_er_yinggu", "q_er_jiuwei", "n0", "c_ask")
	await _shot(main, "er_05_yinggu_offer")
	_pick("n_er_yinggu", "q_er_jiuwei", "n1", "c_yes")
	goto("hl_slope")
	await _shot(main, "er_06_slope")
	goto("xx_square")
	ok("quest_accept", { "npc": "n_xx_zhugeyi", "quest": "q_er_zhugeyi" })
	_pick("n_xx_zhugeyi", "q_er_zhugeyi", "n0", "c_yes")
	goto("dl_fangzhi")
	ok("quest_talk", { "npc": "n_er_sanbahong", "quest": "q_er_zhugeyi" })
	await _shot(main, "er_07_sanbahong")
	ok("dialogue_close")
	goto("mw_snow")
	ok("talk", { "npc": "n_er_kezhene" })
	await _shot(main, "er_08_kezhene_menu")
	ok("dialogue_close")
	goto("xw_road")
	ok("use_item", { "item_uid": give("i_er_wulintie", 1) })
	await _shot(main, "er_09_wulintie_fight")
	A.finish(self, 1, true)
	await _shot(main, "er_10_wulintie_won")
	main.queue_free()
	await tree.process_frame
