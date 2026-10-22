extends "res://tests/test_case.gd"
## M1 資料內容（WP-DATA，M1_PLAN 第 5 章、3.11、6.1）：真實資料載入、BFS 可達性、模板涵蓋、
## NPC 房間一致、M1 全部 id 存在、int 欄位轉型，以及 data_lint 新檢查對壞資料的偵測。
## M3a（WP-MERGE，M3A_PLAN 10.1）：10 派列、3.2 固定 id、接點出口雙向、入門武功與驗收招式、新物品與商店。

const DataLint := preload("res://tools/data_lint.gd")

var loader: DataLoader
var view: Dictionary

func before_each() -> void:
	if loader == null:
		loader = DataLoader.new()
		loader.load_all("res://data")
		view = loader.activate(["1.0A"])

# ---------------------------------------------------------------- 載入與 lint

func test_real_data_loads_without_errors() -> void:
	assert_eq(loader.errors.size(), 0, "load errors: %s" % ", ".join(loader.errors))
	assert_eq(loader.all_maps.size(), 44 + 1, "（M3d WP-ERRANDS +1：黑龍潭 1.0B）44 region maps (15 + 16 M3a + 3 故事包 in 1.0A + 2 京城 in 1.0B + M3b 8：京城北郊、丐幫、絕情谷、絕情谷地牢 1.0B；馬王洞、高昌古道、高昌、高昌迷宮 1.0A)")

func test_activate_base_era_without_errors() -> void:
	var v := loader.activate(["1.0A"])
	assert_eq(loader.activate_errors.size(), 0, "activate errors: %s" % ", ".join(loader.activate_errors))
	assert_has(v, "life_skills")
	assert_eq(v["life_skills"].size(), 10, "M1 4 + M3b 6（工匠是 1.0B）")

func test_content_lint_is_clean() -> void:
	var errs := DataLint.check_content(view)
	assert_eq(errs.size(), 0, "content errors:\n  " + "\n  ".join(errs))

func test_game_data_activates_every_preset() -> void:
	var gd: Node = tree.root.get_node("GameData")
	for preset in ["classic_strict", "classic_standard", "later_official", "friends_casual"]:
		assert_true(gd.activate(["1.0A"], { "preset": preset, "overrides": {} }),
			"%s: %s" % [preset, ", ".join(gd.activate_errors)])
	assert_eq(gd.rules["death_rule"], "CASUAL")
	gd.activate(["1.0A"], { "preset": "classic_standard", "overrides": {} })
	assert_eq(gd.rules["death_rule"], "STANDARD")
	assert_eq(gd.rules["corpse_window"], "CLASSIC_30")
	assert_has(gd.tables["maps"], "guiwang")

func test_every_row_has_era_and_valid_src() -> void:
	# WORLD_2001 §6：京城（地區、地圖、n_jc_* 與其對話）是 1.0B；陣法（news 322：2001-10-05 隨神鵰大俠開放）也是 1.0B；
	# M3B_PLAN §0.2、§2.2：丐幫、京城、北郊、絕情谷、工匠、天地會、京城線保鏢是 1.0B，丐幫三袋以上是 xkd；其他全部 1.0A
	var formation_1b := ["basic_formation", "sl_jgfmq", "qz_tiangang", "wd_zhenwu", "formation", "ms_qz_qiuchuji_tiangang",
		"ms_qz_majue_tiangang", "ms_qz_tanchuduan_tiangang", "ms_qz_wangchuyi_tiangang", "ms_qz_liuchuxuan_tiangang",
		"ms_qz_haodatong_tiangang", "ms_qz_sunbuer_tiangang", "ms_qz_qizhicheng_formation", "ms_due_jgfmq", "ms_due_formation",
		"ms_wd_songyuanqiao_zhenwu", "ms_wd_songyuanqiao_formation"]
	var m3b_1b_prefixes := ["gaibang", "gb_", "n_gb_", "m_gb_", "ms_gb_", "q_gb_", "i_gb_", "jueqinggu", "jq_", "n_jq_", "m_jq_",
		"q_jq_", "c_jq_", "w_jq_", "n_tdh_", "q_tdh_", "i_tdh_", "a_tdh_", "h_tdh_", "q_jc_", "m_jc_", "c_jc_", "m_jcn_", "a_jcn_",
		"er_xx_jc", "er_jc_", "er_dl_jc", "q_ec_biao_xx_jc", "q_ec_biao_jc_", "q_ec_biao_dl_jc", "n_ec_jc_",
		# M3b 審查：馬王洞（馬賊王）改 1.0B；京城武館、京城驛站送信（1.0B）
		"mawang", "m_mw_", "q_ym_mawang", "ms_jcwg_", "q_letter_jc_",
		"q_ch_gb_"]   # M3c2：丐幫雜務（丐幫是 1.0B）
	var m3b_1b_ids := ["qinghua", "life_carpentry", "t_juzi", "w_muzhang", "w_xuanmuzhang", "w_muzhua", "a_douli", "a_muzan",
		"ms_ls_mujiang_carpentry", "n_ls_jc_mujiang", "n_ec_xx_tangzi", "n_ec_dl_tangzi", "n_og_jc_shuli",
		"a_huangjia",   # M3b 審查 3：黃罩甲只有 1.0B 的馬賊王會掉
		"bk_wumu", "lt_elite_1b",
		"a_lt_jiehunjiezhi",
		"n_na_xx_huanggou", "m_npc_huanggou", "r_gourou",
		"n_na_xw_yang", "n_na_xe_kuangshi",
		"r_zhangmuxiang"]   # M3c2 審查 #6：工匠（1.0B）的樟木箱   # M3c 第三輪審查：羊、採礦師唯一出處 2002-06-17 → 與黃狗同一規則改 1.0B   # M3c 第二輪審查：黃狗（2001-10 才有出處）、牠的戰鬥單位與黃狗肉是 1.0B；M3c WP-LOOT：武穆遺書（基本陣法只在 1.0B）、1.0B 精英掉落表；M3c 審查：結婚戒指 1.0B（DIAO/2-1 京城婚姻）
	# M3d WP-ERRANDS（M3D_PLAN §6、T8）：1.0B 的跑腿列（柯鎮惡、郭靖、武林帖、黑龍潭）
	m3b_1b_prefixes.append_array(["heilongtan", "n_er_kezhene", "n_er_guojing", "n_er_tiefan", "n_er_yinggu", "n_er_cien",
		"q_er_kezhene", "q_er_jiuwei", "i_er_ke_xin", "i_er_wulintie", "i_er_hulixue", "m_er_wulin_", "m_er_jiuwei", "m_er_yang",
		"p1b_er_"])
	# M3d 整合（M3D_PLAN T8）：WP-LAW 京城列、WP-COMBAT 合體技與貨郎、WP-ARTS 1.0B 武功鏈、WP-EVENTS 劫鏢
	m3b_1b_prefixes.append_array(["n_ev_jb_", "m_ev_jb_", "q_ev_jb_", "i_cb_", "n_cb_", "ms_ar_", "q_ar_qz_", "q_ar_lj_",
		"q_ar_em_", "q_ar_xd_", "i_ar_qz_", "i_ar_ym_", "i_ar_luosha", "i_ar_huangyao", "i_ar_xd_", "m_ar_manbing"])
	m3b_1b_ids.append_array(["qz_r_kill_gumu", "gm_suxin", "lj_bahuang", "qz_chongyang", "qz_kongming", "em_sixiang", "xd_xuemo",
		"ms_gm_xiaolongnu_suxin", "ms_lj_tonglao_bahuang", "n_law_board_jc", "n_law_guanye_jc_a", "n_law_guanye_jc_b",
		"n_law_banxian_jc", "n_ar_qz_shanju", "n_ar_qz_shuliu", "n_ar_qz_yunyou", "n_ar_qz_wangzhijin", "n_ar_lj_wuyazi",
		"n_ar_ym_shouwei", "n_ar_guoxiang", "n_ar_xd_inf_heilong", "n_ar_xd_baoxiang", "n_ar_xd_inf_dali", "n_ar_dingbusan",
		"n_ar_dingbusi", "n_ar_laokelian", "n_ar_xd_xuemo_laozu"])
	# 0.7.0.1：飛星術改 1.0B（2001 官方星宿任務表沒有）：武功、師父列、捉拿叛徒的任務、紅衣女子、星宿叛徒；再訪郭襄走 q_ar_em_ 前綴
	m3b_1b_ids.append_array(["xh_feixing", "ms_xh_dcq_feixing", "q_xh_feixing", "n_xh_hongyinv", "m_xh_pantu"])
	var text_tables := ["text_templates", "rumors", "ambient"]   # 文字列的 era 由 lint 的參照檢查把關（1.0A NPC 不能用 1.0B 模板）
	for t in loader.all_tables:
		if t in DataLoader.NO_ERA_TABLES:
			continue
		for id in loader.all_tables[t]:
			var row: Dictionary = loader.all_tables[t][id]
			var sid := str(id)
			assert_true(row.get("src", "") in DataLint.SRC_TAGS, "%s.%s src '%s'" % [t, id, row.get("src", "")])
			if (t == "sect_ranks" and sid in ["gb_dai3", "gb_dai4", "gb_dai5", "gb_dai6", "gb_dai7"]) or sid == "n_jc_cha_n":
				# M3b 審查：京城北門的查小鏞是後期擺法 → xkd
				assert_eq(row.get("era", ""), "xkd", "%s.%s era (三袋以上、北門查小鏞 era xkd)" % [t, id])
				continue
			if t in text_tables:
				assert_true(row.get("era", "") in (["xkd"] if sid == "talk_n_jc_cha_n" else ["1.0A", "1.0B"]), "%s.%s era" % [t, id])
				continue
			var jc: bool = sid.begins_with("jingcheng") or sid.begins_with("n_jc_") or sid.begins_with("talk_n_jc_")
			var m3b: bool = sid in m3b_1b_ids or (t == "sect_ranks" and sid.begins_with("gb_dai"))
			for pf in m3b_1b_prefixes:
				if sid.begins_with(pf):
					m3b = true
			assert_eq(row.get("era", ""), "1.0B" if jc or m3b or sid in formation_1b else "1.0A", "%s.%s era" % [t, id])
	var maps_1b := ["jingcheng", "jingcheng_wild", "jingcheng_north", "gaibang", "jueqinggu", "jueqinggu_dilao", "mawang",
		"heilongtan"]   # M3d WP-ERRANDS
	for rid in loader.all_maps:
		assert_true(loader.all_maps[rid].get("src", "") in DataLint.SRC_TAGS, "maps/%s src" % rid)
		assert_eq(loader.all_maps[rid]["era"], "1.0B" if rid in maps_1b else "1.0A", "maps/%s era" % rid)

func test_1_0b_view_activates_and_lints_clean() -> void:
	var v := loader.activate(["1.0A", "1.0B"])
	assert_eq(loader.activate_errors.size(), 0, "activate errors: %s" % ", ".join(loader.activate_errors))
	var errs := DataLint.check_content(v)
	assert_eq(errs.size(), 0, "1.0B content errors:\n  " + "\n  ".join(errs))
	assert_eq(DataLint.room_index(v).size(), 266 + 14, "1.0B room count (78 + 105 M3a + 19 故事包 + 審查 1：關外橋下 + M3b 62 + 審查 京城武館；M3d WP-ERRANDS +14：比武場 2、破廟、北橋、紡織店、馬王洞西雪地、黑龍潭 8)")
	assert_eq(v["regions"].size(), 44 + 1, "1.0B region count（M3d WP-ERRANDS：黑龍潭泥沼 heilongtan）")

# ---------------------------------------------------------------- 世界圖

func test_every_room_reachable_from_xx_square() -> void:
	var idx := DataLint.room_index(view)
	assert_eq(idx.size(), 218 + 5, "room count (WORLD_2001 §3.17 的 71 + M3a 105 + 故事包 19 + 審查 1：關外橋下 + M3b 1.0A 22；馬王洞 4 間審查改 1.0B；M3d WP-ERRANDS 1.0A +5：比武場、休息區、破廟、北橋、紡織店)")
	var seen := DataLint.reachable_rooms(view, "xx_square")
	for id in idx:
		assert_has(seen, id, "unreachable on foot:")

func test_path_from_xx_square_to_gw_throne_walks_via_xuedao() -> void:
	var path := DataLint.find_path(view, "xx_square", "gw_throne")
	assert_eq(path.size() - 1, 9, "9 moves: %s" % str(path))
	assert_eq(path[0], "xx_square")
	assert_eq(path[path.size() - 1], "gw_throne")
	assert_true("xe_xuedao" in path, "enters via 血刀洞口: %s" % str(path))
	assert_true("gw_maze" in path, "goes through the maze")
	for r in path:
		assert_false(str(r).ends_with("_station"), "no station on the way: %s" % str(path))

func test_walk_routes_east_and_west() -> void:
	# WORLD_2001 §1.4：西夏東門 → 華山山門 12 步、華山 → 少林 8 步、西夏東門 → 大理北門 16 步
	assert_eq(DataLint.find_path(view, "xx_gate_e", "hs_gate").size() - 1, 12, "xx_gate_e -> hs_gate")
	assert_eq(DataLint.find_path(view, "hs_gate", "sl_gate").size() - 1, 8, "hs_gate -> sl_gate")
	assert_eq(DataLint.find_path(view, "xx_gate_e", "sl_gate").size() - 1, 18, "xx_gate_e -> sl_gate")
	assert_eq(DataLint.find_path(view, "xx_gate_e", "dl_gate_n").size() - 1, 16, "xx_gate_e -> dl_gate_n")
	assert_eq(DataLint.find_path(view, "xx_station", "dl_station").size() - 1, 20, "station -> station")
	# M3A_PLAN 2.3：新南路（峨嵋—終南—武當）讓大理到少林只要 21 步（原作「大理→少林茶食路線經過武當、終南」）
	assert_eq(DataLint.find_path(view, "dl_gate_n", "hs_gate").size() - 1, 21, "dali -> huashan (south road)")
	assert_eq(DataLint.find_path(view, "dl_gate_n", "sl_gate").size() - 1, 21, "dali -> shaolin (south road)")
	var west := DataLint.find_path(view, "xx_gate_e", "dl_gate_n")
	assert_true("de_oasis" in west and "rr_bridge" in west and "xw_creek" in west, "west road: %s" % str(west))
	var east := DataLint.find_path(view, "xx_gate_e", "sl_gate")
	for r in ["xe_road", "hf_teahouse", "hy_foot", "sy_teahouse", "sy_foot"]:
		assert_true(r in east, "east road passes %s: %s" % [r, str(east)])
	var idx := DataLint.room_index(view)
	# UI driver 第 8 步一直按「東」：xx_gate_e → xw_road → xw_grass → xw_hill（死路）不准改（§3.2）
	assert_eq(_exit_to(idx["xx_gate_e"]["room"], "E"), "xw_road")
	assert_eq(_exit_to(idx["xw_road"]["room"], "E"), "xw_grass")
	assert_eq(_exit_to(idx["xw_grass"]["room"], "E"), "xw_hill")
	assert_eq(_exit_to(idx["xw_hill"]["room"], "E"), "", "xw_hill is a dead end")
	assert_eq(_exit_dir(idx["xe_xuedao"]["room"], "gw_entrance"), "IN", "xe_xuedao IN -> gw_entrance")
	assert_eq(_exit_dir(idx["gw_entrance"]["room"], "xe_xuedao"), "OUT")
	assert_eq(_exit_dir(idx["xw_road"]["room"], "xe_road"), "NE")
	assert_eq(_exit_dir(idx["xw_creek"]["room"], "ws_slope"), "S")
	assert_false(idx.has("dlw_cave"), "dlw_cave removed")

func test_rooms_match_plan_regions() -> void:
	var expect := {
		"xixia": ["xx_square", "xx_gate_e", "xx_inn", "xx_inn_2f", "xx_station", "xx_street", "xx_pharmacy", "xx_smithy", "xx_wuguan"],
		"xixia_wild": ["xw_road", "xw_grass", "xw_wood", "xw_creek", "xw_hill"],
		"xixia_north": ["xn_slope", "xn_snow"],
		"xixia_east": ["xe_road", "xe_mine", "xe_xuedao", "xe_heilong", "xe_river"],
		"guiwang": ["gw_entrance", "gw_hall", "gw_maze", "gw_throne"],
		"hengshan_foot": ["hf_paddy", "hf_teahouse", "hf_shore", "hf_fork"],
		"huayin_road": ["hy_road", "hy_foot", "hy_pond"],
		"huashan": ["hs_gate", "hs_square", "hs_hall"],
		"songshan_road": ["sy_road", "sy_wdfork", "sy_teahouse", "sy_pines", "sy_foot"],
		"shaolin": ["sl_gate", "sl_court", "sl_wuchang", "sl_hall", "sl_zhaitang", "sl_caiyuan", "sl_zhulin"],
		"xixia_south": ["ws_slope", "ws_ford", "ws_dunes"],
		"desert_edge": ["de_edge", "de_cave", "de_oasis"],
		"river_road": ["rr_upper", "rr_road", "rr_bend", "rr_bridge"],
		"dali_wild": ["dlw_road", "dlw_river", "dlw_paddy", "dlw_lake", "dlw_forest", "dlw_eastwood", "dlw_fork"],
		"dali": ["dl_square", "dl_station", "dl_gate_n", "dl_inn", "dl_yamen", "dl_wuguan", "dl_shop"],
	}
	# M3A_PLAN 2.1、2.2：新地區與加到既有地圖的房間（extra_rooms）
	var m3a := {
		"emei": ["em_gate", "em_square", "em_jingzhao", "em_caiyuan", "em_dadian", "em_chanfang", "em_kitchen", "em_miejue", "em_zhou", "em_siguo"],
		"emei_maze": ["em_mz_1", "em_mz_2", "em_mz_3", "em_mz_4"],
		"emei_road": ["em_road1", "em_road2", "em_teahouse", "em_road3", "em_bandit", "em_road4", "em_foot"],
		"gumu": ["gm_entrance", "gm_hall", "gm_lianwu", "gm_food", "gm_huayuan", "gm_xiaolongnu", "gm_hanyu", "gm_xiaomei", "gm_shishi"],
		"gumu_maze": ["gm_mz_1", "gm_mz_2", "gm_mz_dead", "gm_mz_3", "gm_mz_4"],
		"hengshan": ["hg_gate", "hg_square", "hg_hall", "hg_first", "hg_kitchen", "hg_woodshed", "hg_houshan", "hg_field"],
		"hengshan_foot": ["hg_shandao"],
		"lingjiu": ["lj_gate", "lj_square", "lj_hall", "lj_east", "lj_west"],
		"quanzhen": ["qz_gate", "qz_road", "qz_sanqing", "qz_square", "qz_reading", "qz_chongyang", "qz_houshan", "qz_cave", "qz_garden", "qz_siguo"],
		"shaolin": ["sl_luohan", "sl_cangjing", "sl_siguo"],
		"tianshan_road": ["ts_road1", "ts_hut", "ts_xuegu", "ts_road2"],
		"wudang": ["wd_gate", "wd_square", "wd_daotian", "wd_shufang", "wd_dadian", "wd_tanqiang", "wd_houshan", "wd_siguo", "wd_sanqing", "wd_neitang"],
		"wudang_foot": ["wd_road1", "wd_woods", "wd_road2"],
		"xingxiu": ["xh_gate", "xh_hall", "xh_left", "xh_right", "xh_mid1", "xh_mid2"],
		"xingxiu_road": ["xh_road1", "xh_road2", "xh_marsh"],
		"xuedao": ["xd_gate", "xd_hall", "xd_yard", "xd_pool", "xd_mishi"],
		"xuedao_road": ["xd_road1", "xd_road2", "xd_tent", "xd_road3", "xd_snowfield", "xd_road4"],
		"zhongnan_foot": ["zn_road1", "zn_road2", "zn_river", "zn_foot", "zn_east", "zn_backhill"],
	}
	# STORY_PLAN §2.2：故事包新地區與加到既有地圖的房間（_world 碎片）
	var story := {
		"hengshan_s_road": ["hn_road1", "hn_road2"],
		"hengshan_s": ["hn_foot", "hn_teahouse", "hn_shore", "hn_bridge", "hn_island"],
		"yanmen": ["ym_road", "ym_gate", "ym_bridge", "ym_inner", "ym_qiaoxia"],   # ym_qiaoxia：審查修正（淫賊在強盜下方）
		"xixia": ["xx_minfang", "xx_yamen", "xx_palace", "xx_palace_mishi"],
		"shaolin": ["sl_leftroom"], "huashan": ["hs_siguoya"], "dali_wild": ["dlw_desertcave"], "river_road": ["rr_eastbank"],
	}
	# M3B_PLAN §3.2（1.0A 部分）：錢莊、鏢局、打鐵舖、布莊、大漠礦場、雁門關外與石碑、馬王洞、高昌古道、高昌、高昌迷宮
	var m3b := {
		"xixia": ["xx_bank", "xx_biaoju", "xx_tiepu", "xx_buzhuang"], "dali": ["dl_bank", "dl_biaoju", "dl_tiepu"],
		"desert_edge": ["de_mine"], "yanmen": ["ym_outside", "ym_stele"],
		"gaochang_road": ["gc_road1", "gc_road2", "gc_road3"],   # 馬王洞 M3b 審查改 1.0B
		"gaochang": ["gc_outside", "gc_jihut_out", "gc_jihut"],
		"gaochang_maze": ["gc_maze1", "gc_maze2", "gc_maze3", "gc_maze4", "gc_maze5", "gc_maze6"],
	}
	# M3D_PLAN §9.5（1.0A 地圖上的房間；破廟、北橋在 1.0A 地圖檔裡，各時代都在）
	var m3d := { "xixia": ["xx_biwu", "xx_biwu_rest"], "zhongnan_foot": ["zn_pomiao", "zn_bridge"], "dali": ["dl_fangzhi"] }
	for extra in [m3a, story, m3b, m3d]:
		for region in extra:
			if not expect.has(region):
				expect[region] = []
			expect[region] = expect[region] + extra[region]
	var idx := DataLint.room_index(view)
	var n := 0
	for region in expect:
		for room in expect[region]:
			n += 1
			if assert_has(idx, room, "room:"):
				assert_eq(idx[room]["region"], region, "%s region" % room)
	assert_eq(n, idx.size(), "plan lists every room")

func test_room_features_and_locks() -> void:
	var idx := DataLint.room_index(view)
	var feats := { "xx_inn": "STOVE", "dl_inn": "STOVE", "sl_zhaitang": "STOVE",
		"sl_caiyuan": "FIELD", "dlw_paddy": "FIELD", "hf_paddy": "FIELD",
		"xw_wood": "WOOD", "sl_zhulin": "WOOD", "sy_pines": "WOOD", "dlw_eastwood": "WOOD",
		"xw_creek": "WATER", "dlw_lake": "WATER", "xe_heilong": "WATER", "xe_river": "WATER", "hf_shore": "WATER",
		"hy_pond": "WATER", "ws_ford": "WATER", "de_oasis": "WATER", "rr_bend": "WATER", "dlw_river": "WATER" }
	for r in feats:
		assert_true(feats[r] in idx[r]["room"]["features"], "%s has %s" % [r, feats[r]])
	assert_eq(idx["hs_hall"]["room"]["requires"], [{ "type": "sect", "sect": "huashan" }], "hs_hall lock")
	for r in ["sl_gate", "sl_court", "sl_wuchang", "hs_gate", "hs_square", "gw_throne", "xx_square", "dl_square",
			"hf_teahouse", "sy_teahouse", "de_oasis"]:
		assert_false(idx[r]["room"].has("encounter") and float(idx[r]["room"]["encounter"].get("rate", 0)) > 0.0,
			"%s must not have encounters" % r)
	for r in ["hf_teahouse", "sy_teahouse", "de_oasis"]:
		assert_false("STOVE" in idx[r]["room"]["features"], "%s has no STOVE" % r)

func test_encounter_tables_match_plan() -> void:
	var idx := DataLint.room_index(view)
	var g: Dictionary = idx["xw_grass"]["room"]["encounter"]
	assert_eq(g["rate"], 0.25)
	assert_eq(g["table"], [
		{ "monster": "m_rabbit", "w": 70, "count": [1, 2] },
		{ "monster": "m_bigrabbit", "w": 30, "count": [1, 1] }])
	assert_eq(idx["xw_road"]["room"]["encounter"]["rate"], 0.15)
	assert_eq(idx["gw_entrance"]["room"]["encounter"]["table"], [{ "monster": "m_ghost", "w": 100, "count": [1, 1] }])
	assert_eq(idx["gw_hall"]["room"]["encounter"]["table"][0]["count"], [1, 2])
	assert_eq(idx["gw_maze"]["room"]["encounter"]["table"][0]["count"], [1, 2])
	assert_eq(idx["dlw_forest"]["room"]["encounter"]["rate"], 0.25)
	assert_eq(idx["sy_wdfork"]["room"]["encounter"]["table"][2], { "monster": "m_bandit", "w": 10, "count": [1, 1] })
	# 新手生活點與必經路不放打不贏的怪（6.3）
	for rid in ["xw_wood", "dlw_road", "dlw_lake"]:
		for e in idx[rid]["room"]["encounter"]["table"]:
			assert_eq(e["monster"], "m_rabbit", "%s only rabbits" % rid)
	# §1.4 規則 2–6：沿出生城 → 門派山門、出生城之間的最短步行路線（1.0A 與 1.0B 都要過）
	var v1b := loader.activate(["1.0A", "1.0B"])
	for v in [view, v1b]:
		var errs := DataLint.check_newbie_routes(v)
		assert_eq(errs.size(), 0, "newbie safety:\n  " + "\n  ".join(errs))
	# §1.4 規則 3 的四間房
	for rid in ["xw_road", "dlw_road", "hy_foot", "sy_foot"]:
		for e in idx[rid]["room"]["encounter"]["table"]:
			assert_true(e["monster"] in ["m_rabbit", "m_bigrabbit"], "%s next to a gate: only rabbits" % rid)
	# §1.4 表格的數字（遇敵期望，不含起訖房間）
	var seg := func(a: String, b: String) -> Dictionary:
		return DataLint.path_expectation(view, DataLint.find_path(view, a, b))
	var e1: Dictionary = seg.call("xx_gate_e", "de_oasis")
	_assert_near(float(e1["total"]), 1.06, 0.005, "xx_gate_e -> de_oasis total")
	# M3a WP-MERGE：de_edge 野狼 20→10（大理→靈鷲 路段 §2.3），0.096 → 0.084
	_assert_near(float(e1["hard"]), 0.084, 0.005, "xx_gate_e -> de_oasis hard")
	_assert_near(float(e1["boar"]), 0.024, 0.005, "xx_gate_e -> de_oasis boar")
	_assert_near(float(e1["bandit"]), 0.012, 0.0005, "xx_gate_e -> de_oasis bandit")
	var e2: Dictionary = seg.call("xx_gate_e", "dl_gate_n")
	_assert_near(float(e2["total"]), 1.68, 0.005, "west road total")
	_assert_near(float(e2["hard"]), 0.164, 0.01, "west road hard")
	var e3: Dictionary = seg.call("hs_gate", "sl_gate")
	_assert_near(float(e3["hard"]), 0.162, 0.01, "huashan -> shaolin hard")
	assert_true(float(e3["boar"]) <= 0.10 and float(e3["bandit"]) <= 0.015, "huashan -> shaolin boar/bandit")

func test_lint_newbie_rules_catch_regressions() -> void:
	var bad := view.duplicate(true)
	for room in bad["maps"]["xixia_wild"]["rooms"]:
		if room["id"] == "xw_road":
			room["encounter"]["table"].append({ "monster": "m_wolf", "w": 50, "count": [1, 1] })
	for room in bad["maps"]["desert_edge"]["rooms"]:
		if room["id"] == "de_cave":
			room["encounter"]["table"][2]["w"] = 60
	var errs := "\n".join(DataLint.check_newbie_routes(bad))
	assert_true("room xw_road next to a city/sect gate has m_wolf" in errs, "rule 3: " + errs.left(300))
	assert_true("weight of m_bandit is 60" in errs, "rule 5")
	assert_true("bandit" in errs and "segment" in errs, "rule 2 bandit budget")

func test_exit_era_is_filtered_by_activate() -> void:
	var idx := DataLint.room_index(view)
	assert_eq(_exit_to(idx["hy_foot"]["room"], "NE"), "", "1.0A: hy_foot has no NE exit")
	assert_eq(_exit_to(idx["sy_pines"]["room"], "N"), "", "1.0A: sy_pines has no N exit")
	var raw_has := false
	for room in loader.all_maps["huayin_road"]["rooms"]:
		if room["id"] == "hy_foot":
			raw_has = _exit_to(room, "NE") == "jcw_huashan"
	assert_true(raw_has, "raw data keeps the 1.0B exit")
	var v1b := loader.activate(["1.0A", "1.0B"])
	var idx2 := DataLint.room_index(v1b)
	assert_eq(_exit_to(idx2["hy_foot"]["room"], "NE"), "jcw_huashan", "1.0B: hy_foot NE")
	assert_eq(_exit_to(idx2["sy_pines"]["room"], "N"), "jcw_songshan", "1.0B: sy_pines N")
	assert_eq(DataLint.find_path(v1b, "jc_gate_s", "hs_gate").size() - 1, 4, "jc_gate_s -> hs_gate")
	assert_eq(DataLint.find_path(v1b, "jc_gate_s", "sl_gate").size() - 1, 5, "jc_gate_s -> sl_gate")
	assert_true(DataLoader.exit_active({ "dir": "N", "to": "x" }, { "1.0A": true }), "no era = kept")
	assert_false(DataLoader.exit_active({ "dir": "N", "to": "x", "era": "1.0B" }, { "1.0A": true }), "era off")
	assert_false(DataLoader.exit_active({ "dir": "N", "to": "x", "era_until": "1.0B" }, { "1.0A": true, "1.0B": true }), "era_until on")

## 回歸（UI 稽核 round 2）：新角色照大兔皮任務往東走，在狼嚎丘被兩隻野狼打死。
## 新手必經路（官道、荒草坡：通往胡楊林／小溪的生活點）不放野狼這類 P0 打不贏的怪；
## 任務怪大野兔最常出現的地方要是新手打得過的房間，而不是狼窩。
func test_newbie_path_has_no_wolves_and_quest_monster_lives_there() -> void:
	var idx := DataLint.room_index(view)
	var mons: Dictionary = view.get("monsters", {})
	var bigrabbit_ref := int(mons["m_bigrabbit"]["combat_xp_ref"])
	for rid in ["xw_road", "xw_grass"]:
		for e in idx[rid]["room"]["encounter"]["table"]:
			var ref := int(mons[e["monster"]]["combat_xp_ref"])
			assert_true(ref <= bigrabbit_ref, "%s: %s too strong for the newbie path" % [rid, e["monster"]])
	var share := func(rid: String) -> float:
		var enc: Dictionary = idx[rid]["room"]["encounter"]
		var total := 0.0
		var hit := 0.0
		for e in enc["table"]:
			total += float(e["w"])
			if e["monster"] == "m_bigrabbit":
				hit += float(e["w"])
		return float(enc["rate"]) * hit / maxf(total, 1.0)
	assert_true(share.call("xw_grass") > share.call("xw_hill"),
		"大野兔 per-entry chance: grass %.3f must beat wolf hill %.3f" % [share.call("xw_grass"), share.call("xw_hill")])
	var q: Dictionary = view.get("quests", {}).get("q_rabbit", {})
	assert_true(str(q.get("text", "")).contains("荒草坡"), "quest text names where to hunt")

# ---------------------------------------------------------------- NPC

func test_every_npc_room_is_consistent() -> void:
	var idx := DataLint.room_index(view)
	for nid in view["npcs"]:
		var npc: Dictionary = view["npcs"][nid]
		if str(npc["room"]) == "" and DataLint.escort_npcs(view).has(nid):
			continue   # M3B_PLAN §4.9：鏢車只供護送，不站在房間
		if assert_has(idx, npc["room"], "npc %s room:" % nid):
			assert_true(nid in idx[npc["room"]]["room"]["npcs"], "%s listed in %s" % [nid, npc["room"]])
			assert_eq(npc["region"], idx[npc["room"]]["region"], "%s region" % nid)

func test_all_m1_npcs_exist_with_services() -> void:
	var expect := {
		"n_xx_cha": ["xx_gate_e", ["RESPAWN"]], "n_xx_guard": ["xx_gate_e", []],
		"n_wujieshan": ["xx_square", ["QUEST"]], "n_xx_innkeeper": ["xx_inn", ["INN", "SHOP"]],
		"n_xx_cook": ["xx_inn", ["TEACH"]], "n_zhangwuji": ["xx_inn_2f", []],
		"n_xx_station": ["xx_station", ["TRAVEL", "QUEST"]], "n_xx_pharmacist": ["xx_pharmacy", ["SHOP"]],
		"n_xx_smith": ["xx_smithy", ["SHOP"]], "n_xx_wushi": ["xx_wuguan", ["TEACH"]],
		"n_yeerniang": ["xx_street", []], "n_nanhai": ["xx_street", []], "n_chenjialuo": ["xw_road", []],
		"n_xw_fisher": ["xw_creek", ["TEACH"]], "n_xw_woodcutter": ["xw_wood", ["TEACH"]],
		"n_xe_miner": ["xe_mine", []], "n_hf_teaman": ["hf_teahouse", ["INN", "SHOP"]],
		"n_sy_teaman": ["sy_teahouse", ["INN", "SHOP"]], "n_de_host": ["de_oasis", ["INN", "SHOP"]],
		"n_sl_cha": ["sl_gate", ["RESPAWN"]], "n_sl_zhike": ["sl_gate", ["JOIN", "QUEST", "TEACH", "BETRAY"]],   # M3c2：化緣雜務
		"n_sl_huizhen": ["sl_wuchang", ["TEACH"]], "n_sl_huixu": ["sl_wuchang", ["TEACH"]],
		"n_sl_huikong": ["sl_wuchang", ["TEACH"]], "n_sl_zhaiseng": ["sl_zhaitang", ["MEAL"]],
		"n_hs_cha": ["hs_gate", ["RESPAWN"]], "n_yuebuqun": ["hs_square", ["JOIN", "QUEST", "TEACH", "BETRAY"]],
		"n_ludayou": ["hs_square", ["FIGHT"]], "n_liangfa": ["hs_hall", ["QUEST", "TEACH"]],
		"n_dl_station": ["dl_station", ["TRAVEL", "QUEST"]], "n_dl_cha": ["dl_gate_n", ["RESPAWN"]],
		"n_dl_guard": ["dl_gate_n", []], "n_dl_innkeeper": ["dl_inn", ["INN", "SHOP"]],
		"n_dl_cook": ["dl_inn", ["TEACH"]], "n_dl_bukuai": ["dl_yamen", ["QUEST"]],
		"n_weixiaobao": ["dl_yamen", ["QUEST"]],   # 故事包：化功大法（q_xh_huagong） "n_shuanger": ["dl_yamen", []], "n_dl_wushi": ["dl_wuguan", ["TEACH"]],
		"n_dl_grocer": ["dl_shop", ["SHOP"]], "n_taoyun": ["dlw_paddy", ["QUEST", "TEACH"]],
		"n_guiwang": ["gw_throne", ["FIGHT"]],
		"n_bandit_chief": ["xw_hill", ["FIGHT"]],   # M2_PLAN 4.9（WP-PARTY Day-0）
	}
	# M3a：42 個 M1/M2 NPC + 少林補充 4 + 8 派 119；故事包 39（_world 1、_ambient 3、ev_* 24、sect_stories 11）
	assert_eq(view["npcs"].size(), 264 + 18 + 1, "npc count（0.7.0.1 1.0A +1：小梅房裡的石壁；M3d 1.0A +18：律法 8、跑腿 6、血池 3、比武報名員；M3c2 審查：少林務農僧、火工頭陀 +2；M3c2：雜務 NPC n_ch_* +10、少林切磋弟子 n_sl_spar +1；審查修正 +12：王大富人、李裁縫、楊康、賣藝商人、婦人、清為、崔叟、豬哥義、朱珠、布莊老闆、菜商、江清睿；M3b 1.0A +32；M3c WP-NPCPK n_na_* +6；M3c 第二輪審查：黃狗改 1.0B −1；第三輪：羊、採礦師改 1.0B −2）")
	for nid in expect:
		if not assert_has(view["npcs"], nid, "npc:"):
			continue
		var npc: Dictionary = view["npcs"][nid]
		assert_eq(npc["room"], expect[nid][0], "%s room" % nid)
		var svc: Array = npc["services"].duplicate()
		svc.sort()
		var want: Array = expect[nid][1].duplicate()
		want.sort()
		assert_eq(svc, want, "%s services" % nid)
		assert_eq(npc["talk"], "talk_" + nid, "%s talk key" % nid)

func test_jingcheng_is_era_gated_to_1_0b() -> void:
	# WORLD_2001 §6：1.0A 視圖沒有任何京城房間、地區與 n_jc_* NPC；1.0B 有，而且只有驛站、客棧、查小鏞、守衛
	var idx := DataLint.room_index(view)
	for rid in idx:
		assert_false(str(rid).begins_with("jc_") or str(rid).begins_with("jcw_"), "1.0A has room %s" % rid)
	for nid in view["npcs"]:
		assert_false(str(nid).begins_with("n_jc_"), "1.0A has npc %s" % nid)
	assert_not_has(view["regions"], "jingcheng", "1.0A region:")
	assert_not_has(view["regions"], "jingcheng_wild", "1.0A region:")
	var v1b := loader.activate(["1.0A", "1.0B"])
	var idx2 := DataLint.room_index(v1b)
	for rid in ["jc_station", "jc_street", "jc_inn", "jc_gate_s", "jcw_crossroad", "jcw_songshan", "jcw_huashan"]:
		assert_has(idx2, rid, "1.0B room:")
	# M3B_PLAN §8.3：完整京城（固定 id）；O3：1.0B 京城可出生，出生房 jc_square
	for rid in ["jc_square", "jc_bank", "jc_biaoju", "jc_yamen", "jc_jail_gate", "jc_jail", "jc_buzhuang", "jc_pharmacy",
			"jc_street_n", "jc_smithy", "jc_tiepu", "jc_zijin", "jc_coffin", "jc_tdh_hall", "jc_gate_n"]:
		assert_has(idx2, rid, "1.0B room:")
	for nid in ["n_jc_cha", "n_jc_guard", "n_jc_innkeeper", "n_jc_station", "n_jc_wushi", "n_jc_guard_n", "n_jc_jailer",
			"n_jc_bukuai", "n_jc_smith", "n_jc_pharmacist", "n_jc_zijin_guard", "n_tdh_zhanggui", "n_tdh_chenjinnan", "n_tdh_shop"]:
		assert_has(v1b["npcs"], nid, "1.0B jingcheng npc:")
	assert_eq(v1b["regions"]["jingcheng"]["birth_allowed"], true, "京城 is a birth city in 1.0B (O3)")
	assert_eq(v1b["regions"]["jingcheng"]["birth_room"], "jc_square")
	assert_eq(DataLint.birth_rooms(v1b), ["dl_square", "jc_square", "xx_square"])
	# M3b 審查：京城北門沒有查小鏞（2001 山門附近沒有記錄點；各城門都有是後期擺法 → xkd）
	assert_not_has(v1b["npcs"], "n_jc_cha_n", "1.0B 北門沒有查小鏞")
	assert_eq(DataLint.birth_rooms(view), ["dl_square", "xx_square"], "1.0A: only xixia/dali")

func test_npc_service_details() -> void:
	var n: Dictionary = view["npcs"]
	# 驛站馬車【設計提案・非原作】：只有 stagecoach_enabled 時有用（WORLD_2001 §4.2、§6.1）
	assert_eq(n["n_xx_station"]["travel"], [{ "to_room": "dl_station", "price": 150 }])
	assert_eq(n["n_dl_station"]["travel"], [{ "to_room": "xx_station", "price": 150 }])
	assert_type(n["n_xx_station"]["travel"][0]["price"], TYPE_INT, "travel price")
	assert_eq(n["n_xx_station"]["quests"], ["q_letter"])
	assert_eq(n["n_dl_station"]["quests"], ["q_letter_dl"])
	var n1b: Dictionary = loader.activate(["1.0A", "1.0B"])["npcs"]
	assert_eq(n1b["n_xx_station"]["travel"], [{ "to_room": "dl_station", "price": 150 }, { "to_room": "jc_station", "price": 120 }])
	assert_eq(n1b["n_dl_station"]["travel"], [{ "to_room": "xx_station", "price": 150 }, { "to_room": "jc_station", "price": 150 }])
	assert_eq(n1b["n_jc_station"]["travel"], [{ "to_room": "xx_station", "price": 120 }, { "to_room": "dl_station", "price": 150 }])
	assert_eq(n1b["n_jc_innkeeper"]["inn_price"], 20)
	for inn in ["n_xx_innkeeper", "n_dl_innkeeper"]:
		assert_eq(n[inn]["inn_price"], 20, inn)
	assert_eq(n["n_dl_innkeeper"]["shop"]["items"], ["c_mantou", "c_water", "i_er_shaodaozi", "i_ar_zhuangyuanhong"])   # M3D_PLAN §9.6：燒刀子酒（WP-ERRANDS）、狀元紅（WP-ARTS）
	# 故事包 解救文泰來：西夏客棧加賣三種酒（ev_wentailai shop_patches）
	assert_eq(n["n_xx_innkeeper"]["shop"]["items"], ["c_mantou", "c_water", "c_baijiu", "c_yangrujiu", "c_zhuyeqing", "i_ar_zhuangyuanhong"])   # M3D_PLAN §9.6：狀元紅（WP-ARTS）
	assert_true("c_dahuandan" in n["n_xx_pharmacist"]["shop"]["items"], "尋找虛竹：大還丹在西夏藥鋪")
	for rest in ["n_hf_teaman", "n_sy_teaman", "n_de_host"]:
		assert_eq(n[rest]["inn_price"], 15, rest)
		assert_eq(n[rest]["shop"]["items"], ["c_mantou", "c_water", "c_qiyao"], rest)
		assert_eq(n[rest]["night_closed"], false, rest)
	for closed in ["n_xx_pharmacist", "n_xx_smith", "n_dl_grocer"]:
		assert_eq(n[closed]["night_closed"], true, closed)
	assert_eq(n["n_xx_wushi"]["night_closed"], false, "武館 open at night")
	assert_eq(n["n_sl_zhaiseng"]["meal"], { "food": 40, "water": 40, "hours": ["卯", "午", "酉"] })
	assert_eq(n["n_sl_zhike"]["join_sect"], "shaolin")
	assert_eq(n["n_yuebuqun"]["join_sect"], "huashan")
	assert_eq(n["n_ludayou"]["fight"]["monster"], "m_hs_trainee")
	assert_eq(n["n_guiwang"]["fight"]["monster"], "m_guiwang")
	assert_true("c_smoke" in n["n_dl_grocer"]["shop"]["items"], "grocer sells smoke")
	assert_eq(n["n_xx_smith"]["shop"]["items"].size(), 27, "smith items (+ 皮鞭、金錢鏢、飛蝗石；M3b 十字鎬、針線包；M3c WP-LOOT +12：刀劍 8、防具 4)")

# ---------------------------------------------------------------- 師父

func test_masters_cover_plan() -> void:
	var by := {}
	for mid in view["masters"]:
		var m: Dictionary = view["masters"][mid]
		by["%s|%s" % [m["npc_id"], m["skill_id"]]] = m
		assert_type(m["cap"], TYPE_INT, "%s cap" % mid)
		assert_type(m["price"], TYPE_INT, "%s price" % mid)
		assert_false(m.has("art_id"), "%s has no art_id (D4)" % mid)
	for wg in ["n_xx_wushi", "n_dl_wushi"]:
		for s in ["basic_blade", "basic_sword", "basic_staff", "basic_inner", "basic_parry", "basic_fist",
				"basic_dodge", "basic_body", "basic_literacy"]:
			var key: String = "%s|%s" % [wg, s]
			if assert_has(by, key, "wuguan:"):
				assert_eq(by[key]["cap"], 30, key)
				assert_eq(by[key]["price"], 5, key)
				assert_eq(by[key]["requires"], [], key)
		assert_not_has(by, "%s|basic_whip" % wg, "wuguan does not teach whip")
	var foxa10 := { "type": "skill_min", "skill": "foxa", "value": 10 }
	for key in ["n_sl_huizhen|sl_changquan", "n_sl_huizhen|sl_luohanquan", "n_sl_huizhen|sl_xinfa",
			"n_sl_huizhen|sl_shenfa", "n_sl_huixu|sl_cibeidao", "n_sl_huikong|sl_luohanjian"]:
		if assert_has(by, key, "shaolin art:"):
			assert_eq(by[key]["cap"], 100, key)
			assert_true(foxa10 in by[key]["requires"], "%s needs 佛法 10" % key)
	for b in ["basic_inner", "basic_fist", "basic_parry", "basic_dodge", "basic_body"]:
		var key: String = "n_sl_huizhen|" + b
		if assert_has(by, key, "huizhen basic:"):
			assert_eq(by[key]["cap"], 140, key)
			assert_eq(by[key]["requires"], [{ "type": "sect", "sect": "shaolin" }], key)
	assert_eq(by["n_sl_zhike|foxa"]["cap"], 50)
	assert_eq(by["n_sl_zhike|foxa"]["requires"], [{ "type": "sect", "sect": "shaolin" }])
	assert_eq(by["n_yuebuqun|hs_jianfa"]["cap"], 100)
	assert_eq(by["n_yuebuqun|rufeng"]["cap"], 50)
	var lf := { "basic_inner": 140, "basic_fist": 150, "basic_parry": 140, "basic_dodge": 140, "basic_sword": 150, "basic_body": 140 }
	for b in lf:
		assert_eq(by["n_liangfa|" + b]["cap"], lf[b], "liangfa " + b)
	var life := { "n_xx_cook|life_cooking": "", "n_dl_cook|life_cooking": "", "n_xw_fisher|life_fishing": "t_yugan",
		"n_xw_woodcutter|life_woodcut": "w_chaidao", "n_taoyun|life_farming": "t_chutou" }
	for key in life:
		if assert_has(by, key, "life master:"):
			assert_eq(by[key]["tool"], life[key], key)
			assert_eq(by[key]["price"], 50, key)

func test_master_skill_ids_resolve_to_kinds() -> void:
	assert_eq(DataLint.skill_kind(view, "basic_inner"), "BASIC")
	assert_eq(DataLint.skill_kind(view, "sl_changquan"), "ART")
	assert_eq(DataLint.skill_kind(view, "foxa"), "SECT")
	assert_eq(DataLint.skill_kind(view, "rufeng"), "SECT")
	assert_eq(DataLint.skill_kind(view, "life_fishing"), "LIFE")
	assert_eq(DataLint.skill_kind(view, "nope"), "")

# ---------------------------------------------------------------- 武學、門派

func test_basic_skills_table() -> void:
	var b: Dictionary = view["basic_skills"]
	assert_eq(b.size(), 16, "17 列，基本陣法屬 1.0B（news 322）")
	assert_eq(loader.activate(["1.0A", "1.0B"])["basic_skills"].size(), 17)
	assert_eq(b["basic_inner"]["curve"], "QUARTIC")
	assert_eq(b["basic_inner"]["difficulty"], 0.8)
	assert_eq(b["basic_literacy"]["curve"], "LITERACY")
	assert_eq(b["basic_fist"]["attr_bonus_per10"], { "str": 1 })
	assert_type(b["basic_inner"]["attr_bonus_per10"]["con"], TYPE_INT, "attr_bonus_per10.*")
	assert_type(b["basic_sword"]["max_level"], TYPE_INT, "max_level")
	for id in b:
		if id != "basic_inner" and id != "basic_literacy":
			assert_eq(b[id]["curve"], "CUBIC", id)
			assert_eq(b[id]["difficulty"], 0.9, id)

func test_martial_arts_table() -> void:
	var a: Dictionary = view["martial_arts"]
	for id in ["sl_changquan", "sl_luohanquan", "sl_xinfa", "sl_shenfa", "sl_cibeidao", "sl_luohanjian",
			"hs_xinfa", "hs_jianfa", "hs_pishiquan", "mon_bite", "mon_claw", "mon_ram", "mon_blade", "mon_ghost", "mon_guiwang"]:
		assert_has(a, id, "art:")
	assert_eq(a["sl_changquan"]["moves"].size(), 3)
	var cq3: Dictionary = a["sl_changquan"]["moves"][2]
	assert_eq([cq3["id"], cq3["unlock_level"], cq3["power"], cq3["range"], cq3["cost_inner"]], ["sl_cq_3", 60, 44, 1, 10])
	assert_eq(a["hs_jianfa"]["difficulty"], 0.8)
	assert_eq(a["hs_jianfa"]["moves"][2]["name"], "白虹貫日")
	assert_eq(a["mon_guiwang"]["moves"][1]["range"], 2)
	# 0.7.0.1：劈石破玉拳由梁發教（華山心法 30、儒風 10；17173 2003-10-21），不再鎖在不存在的桃谷六仙任務
	var ps_req := {}
	for c in a["hs_pishiquan"]["requires"]:
		if str(c.get("type", "")) == "skill_min":
			ps_req[str(c["skill"])] = int(c["value"])
	assert_eq(ps_req, { "hs_xinfa": 30, "rufeng": 10 }, "劈石 華山心法 30、儒風 10")
	assert_false(str(a["hs_pishiquan"]["requires"]).contains("q_taogu_done"), "劈石 not locked behind 桃谷六仙")
	for id in a:
		var row: Dictionary = a[id]
		# 怪物專用武功：mon_*，或 M3a 門派前綴的 <p>_mon_*
		assert_eq(row["monster_only"], id.begins_with("mon_") or id.contains("_mon_"), "%s monster_only" % id)
		assert_type(row["self_study_cap"], TYPE_INT, "%s self_study_cap" % id)
		for mv in row["moves"]:
			assert_true(mv["aoe"] in DataLint.MOVE_AOES, "%s aoe" % mv["id"])
			if id in ["sl_changquan", "sl_luohanquan", "sl_cibeidao", "sl_luohanjian", "hs_jianfa", "hs_pishiquan"] or id.begins_with("mon_"):
				assert_eq(mv["aoe"], "SINGLE", "M1 art %s stays SINGLE" % mv["id"])
	assert_eq(a["sl_xinfa"]["category"], "INNER")
	assert_eq(a["sl_shenfa"]["category"], "LIGHTNESS")
	assert_eq(a["sl_cibeidao"]["moves"][0]["flavor"], "move_blade_basic")

func test_sects_table() -> void:
	var sl: Dictionary = view["sects"]["shaolin"]
	var hs: Dictionary = view["sects"]["huashan"]
	assert_eq(sl["gender"], ["M"])
	assert_eq(hs["gender"], ["M", "F"])
	assert_eq(sl["sect_skill_effect"], { "effect": "DEFENSE" })
	assert_eq(hs["sect_skill_effect"], { "effect": "RECOVER" })
	assert_eq(sl["sect_skill_cap"], 100)
	assert_eq(hs["sect_skill_cap"], 100)
	assert_true({ "type": "quest_flag", "flag": "hs_trial_passed" } in hs["join_requires"], "huashan trial flag")
	assert_eq(sl["sect_skill"], "foxa")
	assert_eq(hs["sect_skill"], "rufeng")

func test_attributes_table() -> void:
	var at: Dictionary = view["attributes"]
	assert_eq(at.size(), 7)
	var names := { "str": "臂力", "guts": "膽識", "wit": "悟性", "luck": "福緣", "cal": "定力", "agi": "機敏", "con": "根骨" }
	for id in names:
		assert_eq(at[id]["name"], names[id], id)
		assert_eq(at[id]["roll_cap"], 25, id)

# ---------------------------------------------------------------- 物品、怪物

func test_items_table() -> void:
	var it: Dictionary = view["items"]
	# M3c2 WP-ECON：新原料／料理 10 列（§4.4）另外點名；WP-PACE 的雜務道具 i_ch_* 另計（各自的測試檢查）
	var m3c2_econ := ["r_mai", "r_shucai", "r_songmu", "r_zhangmu", "r_liyu", "r_manyu", "c_maibing", "c_liyutang", "c_caifan", "c_kaomanyu"]
	for id in m3c2_econ:
		assert_has(it, id, "M3c2 WP-ECON")
	var older := it.keys().filter(func(k): return not str(k).begins_with("i_ch_") and not (str(k) in m3c2_econ))
	assert_eq(older.size(), 236 + 8 + 3, "0.7.0.1 1.0A +3（周芷若的信、張無忌的回信、鐵指環）；M3d 1.0A +8（跑腿 5、狀元紅、小木鼎、盟主令牌）；27 + _cmd 8 + 門派 11 + 皮鞭 + 故事包 50 + 審查 14（尋找楊康、陳大寶、2001 雜事）+ M3b 1.0A 44（審查 3：黃罩甲改 1.0B）+ M3c WP-LOOT 1.0A 81（武穆遺書、結婚戒指 1.0B）")
	# M3C_PLAN §1.4 F1：官方武器表第二個數字是重量 → 武器 def 一律 0
	assert_eq([it["w_mudao"]["weapon_type"], it["w_mudao"]["atk"], it["w_mudao"]["def"], it["w_mudao"]["price"]], ["BLADE", 4, 0, 20])
	assert_eq(it["a_cubudaopao"]["effects"], [{ "type": "attr", "stat": "wit", "value": 2 }])
	assert_eq(it["c_jingyao"]["effects"], [{ "type": "restore", "stat": "jing", "value": 50 }])
	assert_eq(it["c_kaoyu"]["effects"].size(), 2)
	assert_eq(it["c_smoke"]["effects"], [{ "type": "smoke", "value": 300 }])
	assert_eq(it["c_smoke"]["price"], 5000)
	assert_eq(it["i_letter"]["quest_item"], true)
	assert_eq(it["i_letter"]["no_sell"], true)
	assert_eq(it["r_bigrabbitskin"]["no_sell"], true)
	assert_eq(it["c_mantou"]["spoil_days"], 3)
	assert_eq(it["a_bupao"]["slot"], "ARMOR")
	assert_type(it["c_jingyao"]["effects"][0]["value"], TYPE_INT, "effects[].value")
	assert_type(it["w_gangdao"]["weight"], TYPE_INT, "weight")

func test_monsters_table() -> void:
	var m: Dictionary = view["monsters"]
	assert_eq(m.size(), 118 + 7 + 1, "0.7.0.1 1.0A +1（周芷若）；M3d 1.0A +7（賞金獵人 3、沙漠白猿、血池三階）；M3c2 少林切磋弟子 m_sl_dizi +1；M1 的 8 種 + M2_PLAN 4.9 的山賊頭目、守城官兵 + M3a 33 + 故事包 32 + 審查 8 + 第三輪審查 1（李莫愁）+ M3b 1.0A 15（馬賊、馬王審查改 1.0B）+ M3c m_npc_* 10 + M3c 審查 2（滅派專用 m_npc_gm_dizi、m_npc_wd_hushan）+ 第二輪審查 6（門口硬闖 m_npc_<p>_gate；黃狗 m_npc_huanggou 是 1.0B 不算）")
	assert_has(m, "m_bandit_chief", "M2 4.9:")
	assert_has(m, "m_city_guard", "M2 4.9:")
	if m.has("m_city_guard"):
		assert_eq(m["m_city_guard"]["no_rewards"], true)
	var r: Dictionary = m["m_rabbit"]
	assert_eq([r["stats"]["qi"], r["stats"]["str"], r["stats"]["con"], r["stats"]["agi"]], [60, 8, 10, 15])
	assert_eq(r["skills"], { "basic_dodge": 5, "basic_parry": 0, "basic_inner": 0 })
	assert_eq(r["ai"], "coward")
	assert_eq(r["armor_power"], 26, "6.3 校準：臂力 14 的新手也打得死野兔")
	assert_eq(m["m_bigrabbit"]["armor_power"], 31)
	assert_eq([m["m_boar"]["stats"]["qi"], m["m_boar"]["stats"]["str"], m["m_boar"]["learn_points"]], [250, 13, 12], "P1 練功對象")
	assert_type(r["stats"]["qi"], TYPE_INT, "stats.*")
	assert_type(r["skills"]["basic_dodge"], TYPE_INT, "skills.*")
	assert_type(r["drops"][0]["chance"], TYPE_FLOAT, "drop chance stays float")
	assert_eq(m["m_ghost"]["stats"]["qi"], 450, "D6")
	assert_eq(m["m_bandit"]["weapon_type"], "BLADE")
	assert_eq([m["m_bandit"]["morality_on_kill"], m["m_bandit"]["killing_intent_on_kill"]], [3, 5])
	assert_eq(m["m_hs_trainee"]["no_rewards"], false)   # M3c2 §2.3.3：切磋給獎勵
	assert_eq(m["m_hs_trainee"]["weapon_type"], "SWORD")
	assert_eq(m["m_guiwang"]["drops"][0], { "item": "c_qiyao", "chance": 1.0, "min": 2, "max": 3 })
	assert_eq(m["m_guiwang"]["kind"], "BOSS")
	assert_eq(m["m_bigrabbit"]["combat_xp_ref"], 200)

func test_status_effects_table() -> void:
	var w: Dictionary = view["status_effects"]["inner_wound"]
	assert_eq(w["duration_actions"], 5)
	assert_eq(w["blocks"], ["REST"])
	assert_eq(w["qi_pct_per_action"], 0.02)

# ---------------------------------------------------------------- 生活技能、任務、區格

func test_life_skills_table() -> void:
	var l: Dictionary = view["life_skills"]
	var expect := { "life_farming": ["FIELD", "t_chutou"], "life_woodcut": ["WOOD", "w_chaidao"],
		"life_fishing": ["WATER", "t_yugan"], "life_cooking": ["STOVE", ""] }
	for id in expect:
		assert_eq([l[id]["feature"], l[id]["tool"]], expect[id], id)
		assert_eq([l[id]["jing_cost"], l[id]["cooldown_s"], l[id]["cap"]], [5, 5, 100], id)
	# M3c2 WP-ECON §4.2：木材 [1,2] → [1,1]＋每 20 級 +1（n_per_levels）
	assert_eq(l["life_woodcut"]["yield"][0]["n"], [1, 1])
	assert_eq(l["life_woodcut"]["yield"][0]["n_per_levels"], 20)
	assert_type(l["life_farming"]["yield"][0]["n"][0], TYPE_INT, "yield[].n[]")
	assert_type(l["life_farming"]["yield"][0]["n_per_levels"], TYPE_INT, "yield[].n_per_levels")
	var rc: Array = l["life_cooking"]["recipes"]
	assert_eq(rc.size(), 6, "白飯、烤魚＋M3c2 麥餅、鯉魚湯、菜飯、烤鰻魚")
	assert_eq(rc[0], { "id": "rc_baifan", "name": "白飯", "inputs": [{ "item": "r_rice", "n": 1 }],
		"output": { "item": "c_baifan", "n": 1 }, "min_level": 1 })
	assert_eq(rc[1]["min_level"], 5)
	assert_eq(rc[1]["inputs"].size(), 2)

func test_quests_table() -> void:
	var q: Dictionary = view["quests"]
	assert_eq(q.size(), 112 + 6 + 2, "0.7.0.1 1.0A +2（滅絕師太的絕學、王重陽遺刻）；M3d 1.0A +6（小木鼎、豬哥義、便當 2、酒鬼、阿虎）；M3c2 審查：少林幫農、學佛 +2；M3c2 1.0A 雜務 q_ch_* 40；M1/M2 6 + M3a 8 + 故事包 35（P0 12、門派 15、2001 雜事 7、第三輪審查的天龍寺前的李莫愁 1）+ M3b 1.0A 21（q_ym_mawang 審查改 1.0B）")
	assert_eq(q["q_rabbit"]["rewards"]["money"], 100)
	assert_eq(q["q_rabbit"]["rewards"]["learn_points"], 25)
	assert_eq(q["q_rabbit"]["steps"][0]["item"], "r_bigrabbitskin")
	assert_eq(q["q_rice"]["steps"][0]["count"], 5)
	assert_eq(q["q_rice"]["rewards"]["skill_prof"], { "life_farming": 10 })
	assert_type(q["q_rice"]["rewards"]["skill_prof"]["life_farming"], TYPE_INT, "skill_prof.*")
	assert_eq(q["q_letter"]["give_items"], [{ "id": "i_letter", "n": 1 }])
	assert_eq(q["q_letter"]["steps"][0]["target"], "n_dl_station")
	assert_eq(q["q_letter_dl"]["steps"][0]["target"], "n_xx_station")
	assert_eq(q["q_letter"]["repeatable"], true)
	for lq in ["q_letter", "q_letter_dl"]:
		assert_eq(q[lq]["rewards"]["money"], 100, lq)
		assert_eq(q[lq]["rewards"]["fame"], 2, lq)
	assert_true(str(q["q_letter"]["text"]).contains("綠洲"), "letter text gives walking directions")
	assert_eq(q["q_bandit"]["steps"][0], { "type": "KILL", "target": "m_bandit", "item": "", "count": 3, "text": "剿滅山賊" })
	assert_eq(q["q_bandit"]["steps"][1]["type"], "TALK")
	assert_eq(q["q_bandit"]["rewards"]["morality"], 10)
	assert_eq(q["q_hs_kaoyan"]["rewards"]["flags"], ["hs_trial_passed"])
	assert_eq(q["q_hs_kaoyan"]["requires"].size(), 3)
	assert_eq(q["q_hs_kaoyan"]["steps"][0]["target"], "m_hs_trainee")
	for id in q:
		if not bool(q[id].get("_legacy", false)):
			continue   # 故事包第 2 版列沒有舊 rewards（test_data_story 檢查 outcomes）
		for k in ["money", "combat_xp", "learn_points", "fame", "morality"]:
			assert_type(q[id]["rewards"][k], TYPE_INT, "%s rewards.%s" % [id, k])

func test_regions_table() -> void:
	var r: Dictionary = view["regions"]
	assert_eq(r.size(), 37, "15 + M3a 16 + 故事包 3（衡陽古道、衡山、雁門關）+ M3b 3（高昌古道、高昌、高昌迷宮；馬王洞審查改 1.0B）")
	var births: Array = []
	for id in r:
		if r[id]["birth_allowed"]:
			births.append(id)
	births.sort()
	assert_eq(births, ["dali", "xixia"], "only xixia/dali are birth cities")
	assert_eq(r["xixia"]["birth_room"], "xx_square")
	assert_eq(r["dali"]["birth_room"], "dl_square")
	assert_not_has(r, "jingcheng", "1.0A has no 京城:")
	assert_eq(r["guiwang"]["suggested_xp"], [10000, 20000])
	assert_eq(r["guiwang"]["type"], "DUNGEON")
	assert_eq(r["guiwang"]["name"], "血刀洞迷宮")
	# §1.1：原作座標 ÷ 24
	var wp := { "xixia": [304, 124], "dali": [246, 776], "guiwang": [359, 93], "huashan": [725, 326], "shaolin": [967, 292] }
	for id in wp:
		assert_eq(r[id]["world_pos"], wp[id], "%s world_pos" % id)
	assert_true(r["xixia"]["world_pos"][1] < r["dali"]["world_pos"][1], "西夏 north of 大理")
	for id in r:
		assert_eq(r[id]["map"], "res://data/maps/%s.json" % id, "%s map path" % id)

# ---------------------------------------------------------------- 模板

func test_every_required_template_key_exists() -> void:
	var tpl: Dictionary = view["text_templates"]
	for key in DataLint.REQUIRED_TEMPLATE_KEYS:
		if assert_has(tpl, key, "template:"):
			for v in DataLint.TEMPLATE_VARIANTS.get(key, ["self"]):
				assert_true(str(tpl[key].get(v, "")) != "", "%s.%s" % [key, v])
	for key in DataLint.UI_ONLY_KEYS:
		assert_not_has(tpl, key, "UI-only key has a template:")

func test_every_flavor_and_talk_has_template() -> void:
	var tpl: Dictionary = view["text_templates"]
	for aid in view["martial_arts"]:
		for mv in view["martial_arts"][aid]["moves"]:
			if assert_has(tpl, mv["flavor"], "flavor:"):
				for v in ["self", "target", "other"]:
					assert_true(tpl[mv["flavor"]].has(v), "%s.%s" % [mv["flavor"], v])
	for nid in view["npcs"]:
		assert_has(tpl, "talk_" + nid, "talk:")
	for key in ["move_blade_basic", "move_bite", "move_claw", "move_ram", "move_ghost", "move_fist_basic", "move_sword_basic"]:
		assert_has(tpl, key, "new flavor:")

func test_template_placeholders_are_known_payload_fields() -> void:
	# 3.8 各事件 payload 欄位的聯集；招式模板另有 atk/def/art/move/tenths/dmg/part
	var known := ["str", "guts", "wit", "luck", "cal", "agi", "con", "total", "name", "char_id", "peer",
		"honorific", "shaoxia", "shidi", "gege",   # 第三輪審查：GameHost.tell 依性別補上的稱呼
		"room_name", "desc", "exits", "who", "from_label", "dir_label", "from_name", "to_name", "cost", "clock", "attr_name", "npc_name",
		"item_name", "n", "gain", "skill_name", "times", "prof", "lp", "jing", "level", "tool_name", "sect_name",
		"neili", "qi_gain", "count", "stat_name", "quest_name", "text", "have", "need", "target_name",
		"combat_xp", "learn_points", "money", "fame", "morality", "atk", "def", "art", "move", "tenths", "dmg",
		"part", "weapon", "def_qi", "status_name", "by", "monsters", "n_skills", "n_items", "money_lost",
		"shen_gain", "qi", "neili_gain", "from", "nonce", "rtt_ms", "names",
		# M2_PLAN 4.4
		"ttl", "leader_name", "atk_name", "def_name", "pk", "delta", "value", "label", "state", "owner_name",
		"reward_list",
		# M3A_PLAN 5、6.12（WP-CMD battle_cmds.gd、WP-RULES sect_system.gd 的 payload）
		"heal", "art_name", "level_left", "key", "days", "enforcer", "reason_text", "outcome", "rule_text", "trial_name",
		# M3a 審查修正（sect_breach.outcome_text、jail_in.online_text）
		"outcome_text", "online_text",
		# STORY_PLAN §4.14 quest_stage.stage_title；§5.2 遊蕩惡人傳聞的 region_name
		"stage_title", "region_name",
		# 審查修正：全服第一位完成的傳聞帶結局名（quest_complete／rumors.each 的 outcome_label）
		"outcome_label",
		# M3B_PLAN §6 事件 payload（WP-SECT／WP-ECON／WP-ORG）
		"alms_text", "gain_prof", "monster_name", "rank_name", "jail_name", "verb", "amount", "bank_money", "fee", "delay_text",
		"city_name", "org_name", "signer_fame", "signed", "by_name", "title", "old_name",
		# M3C_PLAN §3.3（WP-LOOKS look_changed）、§6.7（WP-LOOT 稀有掉落傳聞：rumor 參數 item／monster／room 由計畫固定）
		"look_name", "note", "item", "monster", "room"]   # TextRenderer 由 combat_xp／learn_points／money／fame／morality 組出來（只列非 0）
	var re := RegEx.new()
	re.compile("\\{([a-z_]+)\\}")
	var tpl: Dictionary = view["text_templates"]
	for key in tpl:
		for v in ["self", "target", "other"]:
			for m in re.search_all(str(tpl[key].get(v, ""))):
				assert_true(m.get_string(1) in known, "%s.%s uses unknown placeholder {%s}" % [key, v, m.get_string(1)])

func test_template_examples_from_plan() -> void:
	var tpl: Dictionary = view["text_templates"]
	assert_eq(tpl["char_created"]["self"], "你以「{name}」之名踏入江湖。")
	assert_eq(tpl["encounter"]["self"], "【{clock}】你在{room_name}踩到了{monsters}！")
	assert_eq(tpl["death_standard_safe"]["self"], "你死了。所幸初入江湖，沒有任何損失。")
	assert_eq(tpl["battle_kill"].has("self"), false, "battle_kill has only other")
	assert_true("{dmg}" in tpl["atk_blade"]["target"], "atk_* target shows dmg")

# ---------------------------------------------------------------- lint 會抓到壞資料

func test_lint_detects_broken_world() -> void:
	var bad := view.duplicate(true)
	var xx: Dictionary = bad["maps"]["xixia"]
	# 單向出口（xx_inn_2f 沒有反向）、不合法 feature
	for room in xx["rooms"]:
		if room["id"] == "xx_inn_2f":
			room["exits"] = []
			room["features"] = ["LAVA"]
	var errs := "\n".join(DataLint.check_content(bad))
	assert_true("xx_inn has no reverse" in errs or "-> xx_inn_2f has no reverse" in errs, "one-way exit detected")
	assert_true("bad feature 'LAVA'" in errs, "bad feature detected")

func test_lint_detects_unreachable_room() -> void:
	# 拿掉 xw_road 的 NE 出口（與 xe_road 的反向出口）和雪地往東的小路：東路、鬼王、門派全部走不到
	var bad := view.duplicate(true)
	for room in bad["maps"]["xixia_wild"]["rooms"]:
		if room["id"] == "xw_road":
			room["exits"] = room["exits"].filter(func(ex): return ex["dir"] != "NE")
	for room in bad["maps"]["xixia_east"]["rooms"]:
		if room["id"] == "xe_road":
			room["exits"] = room["exits"].filter(func(ex): return ex["dir"] != "SW")
		if room["id"] == "xe_xuedao":
			room["exits"] = room["exits"].filter(func(ex): return ex["dir"] != "W")
	# 北邊雪地也有一條路通到血刀洞口，一起切斷
	for room in bad["maps"]["xixia_north"]["rooms"]:
		if room["id"] == "xn_snow":
			room["exits"] = room["exits"].filter(func(ex): return ex["dir"] != "E")
	# M3a 新南路（大理 dlw_fork ─NE─ 峨嵋—終南—武當 ─ sy_wdfork）也接通東西兩邊，一起切斷
	for room in bad["maps"]["dali_wild"]["rooms"]:
		if room["id"] == "dlw_fork":
			room["exits"] = room["exits"].filter(func(ex): return ex["dir"] != "NE")
	for room in bad["maps"]["emei_road"]["rooms"]:
		if room["id"] == "em_road1":
			room["exits"] = room["exits"].filter(func(ex): return ex["dir"] != "SW")
	var errs := "\n".join(DataLint._c_reachability(bad))
	for r in ["xe_road", "gw_throne", "hs_gate", "sl_gate"]:
		assert_true("room %s" % r in errs, "%s unreachable: %s" % [r, errs.left(300)])
	assert_true("SECT region huashan cannot be reached on foot from birth room dl_square" in errs, "sect from dali")
	assert_true("DUNGEON region guiwang cannot be reached on foot from birth room xx_square" in errs, "dungeon from xixia")
	# 馬車路線不算步行
	assert_true(DataLint.room_graph(view, true)["xx_station"].has("dl_station"), "travel edge only when asked")
	assert_false(DataLint.room_graph(view)["xx_station"].has("dl_station"), "walking graph has no travel edge")

func test_lint_detects_unreachable_delivery() -> void:
	var bad := view.duplicate(true)
	for room in bad["maps"]["xixia_wild"]["rooms"]:
		if room["id"] == "xw_creek":
			room["exits"] = room["exits"].filter(func(ex): return ex["dir"] != "S")
	for room in bad["maps"]["xixia_south"]["rooms"]:
		if room["id"] == "ws_slope":
			room["exits"] = room["exits"].filter(func(ex): return ex["dir"] != "N")
	# M3a 新南路（大理 dlw_fork ─NE─ 峨嵋—終南—武當 ─ sy_wdfork）也接通東西兩邊，一起切斷
	for room in bad["maps"]["dali_wild"]["rooms"]:
		if room["id"] == "dlw_fork":
			room["exits"] = room["exits"].filter(func(ex): return ex["dir"] != "NE")
	for room in bad["maps"]["emei_road"]["rooms"]:
		if room["id"] == "em_road1":
			room["exits"] = room["exits"].filter(func(ex): return ex["dir"] != "SW")
	var errs := "\n".join(DataLint._c_reachability(bad))
	assert_true("birth room xx_square cannot walk to birth room dl_square" in errs, "birth cities split: " + errs.left(300))
	assert_true("quests.q_letter: DELIVER target n_dl_station" in errs, "letter target unreachable")

func test_lint_detects_npc_room_mismatch_and_services() -> void:
	var bad := view.duplicate(true)
	bad["npcs"]["n_wujieshan"]["room"] = "xx_inn"
	bad["npcs"]["n_xx_pharmacist"]["shop"] = null
	bad["npcs"]["n_ludayou"]["fight"] = { "monster": "m_nope", "requires": [] }
	var errs := "\n".join(DataLint.check_content(bad))
	assert_true("npcs.n_wujieshan: room xx_inn does not list this npc" in errs, "npc room mismatch")
	assert_true("room xx_square: npc 'n_wujieshan' has room 'xx_inn'" in errs, "reverse mismatch")
	assert_true("n_xx_pharmacist: SHOP without shop.items" in errs, "shop without items")
	assert_true("n_ludayou: FIGHT monster missing" in errs, "fight monster missing")

func test_lint_detects_bad_masters_quests_templates() -> void:
	var bad := view.duplicate(true)
	bad["masters"]["ms_bad"] = { "id": "ms_bad", "npc_id": "n_xx_wushi", "skill_id": "mon_bite", "cap": 10, "price": 0,
		"tool": "", "requires": [], "era": "1.0A", "src": "proposal" }
	bad["masters"]["ms_bad2"] = { "id": "ms_bad2", "npc_id": "n_xx_wushi", "skill_id": "no_such_skill", "cap": 10,
		"price": 0, "tool": "t_nope", "requires": [], "era": "1.0A", "src": "proposal" }
	bad["quests"]["q_rabbit"]["steps"][0]["item"] = "r_nope"
	bad["text_templates"].erase("err_cap_xp")
	bad["text_templates"].erase("move_ghost")
	bad["text_templates"]["battle_miss"].erase("target")
	var errs := "\n".join(DataLint.check_content(bad))
	assert_true("teaches monster_only art 'mon_bite'" in errs, "monster_only in masters")
	assert_true("skill_id 'no_such_skill' resolves to no skill table" in errs, "unresolved skill")
	assert_true("tool 't_nope' missing" in errs, "missing tool")
	assert_true("DELIVER item 'r_nope' missing" in errs, "quest item")
	assert_true("missing 'err_cap_xp'" in errs, "err template")
	assert_true("missing 'move_ghost'" in errs, "flavor template")
	assert_true("battle_miss: missing variant 'target'" in errs, "variant")

func test_lint_detects_bad_encounters_regions_items() -> void:
	var bad := view.duplicate(true)
	for room in bad["maps"]["xixia_wild"]["rooms"]:
		if room["id"] == "xw_road":
			room["encounter"]["table"][0]["count"] = [1, 5]
		if room["id"] == "xw_grass":
			room["encounter"]["table"][0]["w"] = 0
	bad["regions"]["xixia_wild"]["birth_allowed"] = true
	bad["regions"]["xixia_wild"]["birth_room"] = "xw_road"
	bad["items"]["w_mudao"].erase("weapon_type")
	bad["items"]["c_water"]["effects"][0]["stat"] = "mana"
	var errs := "\n".join(DataLint.check_content(bad))
	assert_true("room xw_road: encounter count" in errs, "count > 4")
	assert_true("room xw_grass: encounter weight" in errs, "weight 0")
	assert_true("regions.xixia_wild: birth_allowed but type is not CITY" in errs, "birth non-city")
	assert_true("items.w_mudao: WEAPON slot needs weapon_type" in errs, "weapon_type")
	assert_true("items.c_water: restore stat 'mana' invalid" in errs, "effect stat")

func test_check_conditions() -> void:
	assert_eq(DataLint.check_conditions([{ "type": "quest_done", "quest": "q_rabbit" }], "x").size(), 0, "quest_done ok")
	assert_eq(DataLint.check_conditions([{ "type": "skill_min", "skill": "foxa" }], "x").size(), 1, "missing value")
	assert_eq(DataLint.check_conditions([{ "type": "nope" }], "x").size(), 1, "unknown type")
	assert_true("quest_done" in DataSchema.REQUIRE_TYPES, "quest_done registered")

# ---------------------------------------------------------------- 工具

func _has_exit(room: Dictionary, to: String) -> bool:
	return _exit_dir(room, to) != ""

func _exit_dir(room: Dictionary, to: String) -> String:
	for ex in room["exits"]:
		if ex["to"] == to:
			return ex["dir"]
	return ""

func _exit_to(room: Dictionary, dir: String) -> String:
	for ex in room["exits"]:
		if ex["dir"] == dir:
			return ex["to"]
	return ""

func _assert_near(actual: float, expected: float, tol: float, msg: String) -> bool:
	return assert_true(absf(actual - expected) <= tol, "%s: %.4f vs %.4f" % [msg, actual, expected])

## M2 審查：守衛 NPC 的描述和它叫出來的官兵用的兵器一致（官兵用刀）
func test_guard_npc_desc_matches_guard_weapon() -> void:
	var t: Dictionary = GameData.tables
	var npc: Dictionary = t.get("npcs", {}).get("n_xx_guard", {})
	var mon: Dictionary = t.get("monsters", {}).get("m_city_guard", {})
	assert_eq(str(mon.get("weapon_type", "")), "BLADE")
	assert_true(str(npc.get("desc", "")).contains("刀"), str(npc.get("desc", "")))
	assert_false(str(npc.get("desc", "")).contains("槍"), "no spear in the description")

# ---------------------------------------------------------------- M3a（WP-MERGE，M3A_PLAN 10.1）

func test_m3a_ten_sects_and_fixed_ids() -> void:
	var s: Dictionary = view["sects"]
	var ids: Array = s.keys()
	ids.sort()
	assert_eq(ids, ["emei", "gumu", "hengshan", "huashan", "lingjiu", "quanzhen", "shaolin", "wudang", "xingxiu", "xuedao"])
	for sid in s:
		for f in ["prefix", "gate_room", "head_npc", "teach_requires", "sect_skill_gain", "sect_skill_penalties",
				"personal_master", "enforcer", "enforcers", "jail_room", "hostile_entry", "visitors", "meal_npc"]:
			assert_true(s[sid].has(f), "sects.%s.%s" % [sid, f])
		assert_false(s[sid].has("jail_region"), "%s: jail_region renamed to jail_room (D11)" % sid)
		assert_false(s[sid].has("expel_rules"), "%s: expel_rules moved to sect_rules (D11)" % sid)
	# 3.1 既有兩派的遷移
	assert_eq([s["shaolin"]["prefix"], s["shaolin"]["gate_room"], s["shaolin"]["head_npc"], s["shaolin"]["jail_room"]],
		["sl", "sl_gate", "n_sl_zhike", "sl_siguo"])
	assert_eq(s["shaolin"]["enforcers"], ["n_sl_puzhi"])
	assert_eq([s["huashan"]["prefix"], s["huashan"]["gate_room"], s["huashan"]["head_npc"], s["huashan"]["jail_room"], s["huashan"]["enforcer"]],
		["hs", "hs_gate", "n_yuebuqun", "", false])
	# 3.2 表：收徒 NPC、性別、門派技能
	var expect := {
		"wudang": ["n_wd_zhangsanfeng", ["M"], "xiayi", "RESIST"], "emei": ["n_em_miejue", ["F"], "duane", "EVADE"],
		"hengshan": ["n_hg_dingxian", ["F"], "cibei", "COUNTER"], "quanzhen": ["n_qz_qiuchuji", ["M"], "yangsheng", "REST"],
		"gumu": ["n_gm_zhangmen", ["F"], "qingxin", "PARALYZE"], "lingjiu": ["n_lj_tonglao", ["F"], "dingxing", "CONFUSE"],
		"xingxiu": ["n_xh_dingchunqiu", ["M", "F"], "chanmei", "DISTRACT"], "xuedao": ["n_xd_laozu", ["M"], "weihe", "HEAVY"],
	}
	for sid in expect:
		assert_eq([s[sid]["head_npc"], s[sid]["gender"], s[sid]["sect_skill"], s[sid]["sect_skill_effect"]["effect"]],
			expect[sid], sid)
		assert_eq(DataLint.skill_kind(view, expect[sid][2]), "SECT", "%s sect skill" % sid)
	# lint 的 3.2 固定 id 表與門派列都過
	var errs := DataLint._c_sects(view)
	assert_eq(errs.size(), 0, "\n".join(errs))

func test_m3a_entry_arts_and_acceptance_moves() -> void:
	var a: Dictionary = view["martial_arts"]
	for sid in DataLint.SECT_FIXED:
		var fx: Array = DataLint.SECT_FIXED[sid]
		var found := false
		for aid in fx[3]:
			if not assert_has(a, aid, "%s entry art:" % sid):
				continue
			assert_eq(a[aid]["sect_id"], sid, "%s sect_id" % aid)
			for c in a[aid]["requires"]:
				assert_true(c["type"] in ["sect", "any_of"], "%s requires only sect: %s" % [aid, str(c)])
			for mv in a[aid]["moves"]:
				if mv["id"] == fx[4]:
					found = true
					assert_eq(mv["unlock_level"], 1, "%s unlock" % fx[4])
					assert_true(mv["aoe"] in ["SINGLE", "CROSS"], "%s aoe" % fx[4])
					assert_true(mv["range"] >= 1, "%s range" % fx[4])
		assert_true(found, "%s acceptance move %s" % [sid, fx[4]])
		assert_eq(view["npcs"][fx[5]]["fight"]["monster"], fx[6], "%s spar" % sid)
		assert_eq(view["monsters"][fx[6]].get("no_rewards", true), false, "%s spar rewards（M3c2 §2.3.3）" % fx[6])
	# 3.2 其他固定點
	var gm_ok := false
	for c in DataLint.conditions_of_type(a["qz_jianfa"]["requires"], "sect"):
		if c["sect"] == "gumu":
			gm_ok = true
	assert_true(gm_ok, "古墓也能學全真劍法")
	assert_eq(a["xh_fangdu"]["category"], "POISON")
	assert_eq(a["lj_zhemei"]["acupoint"], true)
	assert_eq(a["hg_yishu"]["category"], "MEDIC")
	# 陣法 2001-10-05 隨神鵰大俠（1.0B）開放（news 322）：1.0A 沒有陣法武功、基本陣法與陣法狀態
	for id in ["sl_jgfmq", "qz_tiangang", "wd_zhenwu"]:
		assert_false(a.has(id), "1.0A 沒有陣法 %s" % id)
	assert_false(view["basic_skills"].has("basic_formation"), "1.0A 沒有基本陣法")
	assert_false(view["status_effects"].has("formation"), "1.0A 沒有陣法狀態")
	assert_eq(view["npcs"]["n_sl_due"]["services"], [], "1.0A 渡厄只對話")
	var v1b := loader.activate(["1.0A", "1.0B"])
	var a1b: Dictionary = v1b["martial_arts"]
	assert_eq(v1b["npcs"]["n_sl_due"]["services"], ["TEACH"], "1.0B 渡厄教陣")
	assert_eq(a1b["sl_jgfmq"]["category"], "FORMATION")
	var st: Array = []
	for xy in a1b["sl_jgfmq"]["formation"]["stations"]:
		st.append([int(xy[0]), int(xy[1])])   # stations 不在 DataSchema.INT_FIELDS（JSON 讀進來是 float）
	assert_eq(st, [[0, 0], [-1, 1], [1, 1]])
	assert_eq(view["quests"]["q_wd_yinjian"]["rewards"]["flags"], ["wd_recommended"])

func test_m3a_attach_points_are_two_way() -> void:
	# M3A_PLAN 2.2 接點表（不得更改）
	var idx := DataLint.room_index(view)
	var pairs := [["sy_wdfork", "S", "wd_road1"], ["dlw_fork", "NE", "em_road1"], ["hf_fork", "N", "hg_shandao"],
		["em_foot", "E", "zn_road1"], ["wd_road2", "SW", "zn_east"], ["zn_backhill", "E", "gm_entrance"],
		["xn_snow", "W", "ts_road1"], ["ws_dunes", "W", "xh_road1"], ["de_cave", "W", "xd_road1"],
		["sl_hall", "W", "sl_luohan"], ["sl_hall", "E", "sl_cangjing"], ["sl_hall", "NW", "sl_siguo"]]
	for p in pairs:
		assert_eq(_exit_to(idx[p[0]]["room"], p[1]), p[2], "%s %s" % [p[0], p[1]])
		assert_eq(_exit_to(idx[p[2]]["room"], DataLint.DIR_REVERSE[p[1]]), p[0], "%s back" % p[2])
	assert_eq(idx["hg_shandao"]["region"], "hengshan_foot", "hg_shandao is an extra room of 恆山山麓")
	# 2.3 步數
	var steps := { "sy_wdfork|wd_gate": 3, "dlw_fork|em_gate": 7, "em_foot|qz_gate": 4, "zn_foot|gm_entrance": 2,
		"zn_foot|wd_gate": 3, "hf_fork|hg_gate": 2, "xn_snow|lj_gate": 4, "ws_dunes|xh_gate": 3, "de_cave|xd_gate": 6,
		"dl_gate_n|sl_gate": 21, "dl_gate_n|em_gate": 11 }
	for k in steps:
		var ab: PackedStringArray = k.split("|")
		assert_eq(DataLint.find_path(view, ab[0], ab[1]).size() - 1, steps[k], k)
	# 新 desc 照貼（2.2）
	assert_true(str(idx["xn_snow"]["room"]["desc"]).ends_with("往西的雪原上有一條踩出來的小徑，聽說通往天山。"), "xn_snow desc")
	assert_true(str(idx["de_cave"]["room"]["desc"]).contains("血刀門就在雪山裡"), "de_cave desc")
	# 每個門派的山門從兩座出生城都走得到
	for br in DataLint.birth_rooms(view):
		var seen := DataLint.reachable_rooms(view, br)
		for sid in view["sects"]:
			assert_has(seen, view["sects"][sid]["gate_room"], "%s gate from %s:" % [sid, br])

func test_m3a_items_shops_and_rules() -> void:
	var it: Dictionary = view["items"]
	for id in ["h_dangong", "h_jinqianbiao", "h_feihuangshi", "h_tieling", "h_yubiao", "h_tielianzi", "c_jieduyao", "c_jiedulingyao", "w_pibian"]:
		assert_has(it, id, "item:")
	assert_eq(it["h_tielianzi"]["effects"][0]["value"], 35)
	assert_eq(it["c_jieduyao"]["effects"][0]["type"], "cure")
	assert_eq(it["c_jieduyao"]["usable"], true)
	assert_eq(it["w_pibian"]["weapon_type"], "WHIP")
	var n: Dictionary = view["npcs"]
	for id in ["h_jinqianbiao", "h_feihuangshi", "w_pibian"]:
		assert_true(id in n["n_xx_smith"]["shop"]["items"], "西夏兵器鋪 %s" % id)
		assert_true(id in n["n_dl_grocer"]["shop"]["items"], "大理雜貨鋪 %s" % id)
	assert_true("c_jieduyao" in n["n_xx_pharmacist"]["shop"]["items"], "西夏藥鋪 解毒藥")
	assert_true("c_jieduyao" in n["n_dl_grocer"]["shop"]["items"], "大理雜貨鋪 解毒藥")
	assert_eq([n["n_wd_dl_oldman"]["region"], n["n_wd_dl_oldman"]["room"]], ["dali", "dl_shop"], "武當送家書的老人在大理")
	# 3.3：少林 expel_rules 改寫成 sl_r_killing；有門規的派每派至少一條
	var r: Dictionary = view["sect_rules"]
	assert_eq(r["sl_r_killing"]["ok_if"], [{ "type": "killing_intent_max", "value": 2000 }])
	# M3a 審查修正：全真「不得進古墓」只降養生（mengpai/6），不坐牢 → 沒有 qz_r_gumu
	assert_false(r.has("qz_r_gumu"), "進古墓只降養生（sects.quanzhen.sect_skill_penalties）")
	# 研究 全真：飲酒、進入古墓 → 減低養生（M3a 審查 A4）
	assert_eq(view["sects"]["quanzhen"]["sect_skill_penalties"], [{ "trigger": "ENTER_REGION", "region": "gumu", "levels": 1 },
		{ "trigger": "DRINK", "levels": 1 }])
	assert_true(bool(it["c_xd_jiu"].get("alcohol", false)), "青稞酒算酒")
	# 官方暗器頁：六種暗器都可下毒（M3a 審查 A2）
	for hid in ["h_dangong", "h_jinqianbiao", "h_feihuangshi", "h_tieling", "h_tielianzi", "h_yubiao"]:
		assert_true(bool(it[hid]["effects"][0].get("poisonable", false)), hid + " 可下毒")
	# 坐牢名單（JAIL／BAN，jy2-22，2001-11-15 起）與叛派名單（EXPEL，2001-08）分開
	assert_eq(r["wd_r_morality"]["ok_if"], [{ "type": "morality_min", "value": -299 }])
	assert_eq(r["wd_r_morality"]["modes"], ["JAIL", "BAN"])
	assert_eq([r["wd_r_morality_npc_a"]["ok_if"][0]["value"], r["wd_r_morality_npc_b"]["ok_if"][0]["value"]], [-99, -199])
	assert_eq(r["wd_r_morality_npc_a"]["modes"], ["EXPEL"])
	assert_true("n_wd_zhangsanfeng" in r["wd_r_morality_npc_a"]["on_npc"])
	assert_true("n_wd_songyuanqiao" in r["wd_r_morality_npc_b"]["on_npc"])
	assert_eq(r["qz_r_morality"]["ok_if"], [{ "type": "morality_min", "value": -399 }])
	assert_eq(r["qz_r_morality_2001"]["ok_if"], [{ "type": "morality_min", "value": -299 }])
	assert_eq([r["gm_r_pk"]["ok_if"][0]["value"], r["gm_r_killing"]["ok_if"][0]["value"]], [10, 10000])
	assert_eq([r["gm_r_pk_2001"]["ok_if"][0]["value"], r["gm_r_killing_2001"]["ok_if"][0]["value"], r["gm_r_morality"]["ok_if"][0]["value"]], [3, 2000, -500])
	for rid in ["gm_r_pk_2001", "gm_r_killing_2001", "gm_r_morality", "qz_r_morality_2001", "hg_r_killing"]:
		assert_eq(r[rid]["modes"], ["EXPEL"], rid)
	# 武當執法者＝官方 7 人；古墓入派要未婚、守宮砂未失
	assert_eq(view["sects"]["wudang"]["enforcers"].size(), 7)
	var gj: Array = view["sects"]["gumu"]["join_requires"]
	assert_eq(DataLint.conditions_of_type(gj, "unmarried").size(), 1)
	assert_eq(DataLint.conditions_of_type(gj, "not_flag")[0]["flag"], "shougongsha_lost")
	for sid in ["shaolin", "huashan", "wudang", "emei", "hengshan", "quanzhen", "gumu", "lingjiu"]:
		var has := false
		for rid in r:
			if r[rid]["sect"] == sid:
				has = true
		assert_true(has, "%s has sect_rules" % sid)
	var e1 := DataLint._c_sect_rules(view)
	assert_eq(e1.size(), 0, "\n".join(e1))
	# 新休息點（2.3 規則 1）、jail／encounter_exempt／meditate
	var e2 := DataLint._c_rooms_m3a(view)
	assert_eq(e2.size(), 0, "\n".join(e2))

func test_m3a_art_entries() -> void:
	var art: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/art.json"))
	for sid in view["sects"]:
		for g in view["sects"][sid]["gender"]:
			var key := "%s_%s" % [sid, str(g).to_lower()]
			assert_has(art["units"], key, "sect outfit:")
	for nid in view["npcs"]:
		if str(view["npcs"][nid]["region"]) in ["wudang", "emei", "hengshan", "quanzhen", "gumu", "lingjiu", "xingxiu", "xuedao"]:
			assert_has(art["units"], nid, "npc art:")
	for rid in view["regions"]:
		assert_has(art["backgrounds"], rid, "background:")
	# 擁有者匯入正式門派服裝圖之前是 alias player_m；匯入後是 sprite（import_art.py）
	var wm: Dictionary = art["units"]["wudang_m"]
	assert_true(str(wm.get("alias", "")) == "player_m" or str(wm.get("sprite", "")) != "", "wudang_m: plain clothes alias or imported sprite")

func test_lint_m3a_catches_bad_data() -> void:
	var bad := view.duplicate(true)
	bad["sects"]["wudang"]["jail_room"] = "wd_gate"
	bad["sects"]["emei"]["hostile_entry"][0]["monster"] = "m_nope"
	bad["sects"]["hengshan"]["jail_room"] = "hg_hall"
	bad["npcs"]["n_xh_dingchunqiu"]["services"] = ["JOIN", "TEACH"]
	bad["sect_rules"]["wd_r_kill_same"]["event"] = "ATTACK_NOPE"   # M3c：ATTACK_SECT_NPC 已是合法事件
	bad["sect_rules"]["wd_r_morality"]["text"] = "rule_nope"
	bad["martial_arts"]["wd_changquan"]["moves"][0]["unlock_level"] = 999
	bad["martial_arts"]["wd_changquan"]["moves"][1]["aoe"] = "STAR"
	bad["martial_arts"]["wd_changquan"]["moves"][2]["cost_inner"] = 999
	bad["martial_arts"]["wd_xinfa"]["poison"] = { "status": "poison", "level_bonus": 0 }
	bad["martial_arts"]["wd_xinfa"]["tier"] = "QUEST"
	var ms: Dictionary = bad["masters"][bad["masters"].keys()[0]]
	ms["hours"] = ["半夜"]
	bad["items"]["c_jieduyao"]["effects"] = [{ "type": "cure", "status": "nope", "max_level": 5 }]
	bad["items"]["w_xd_miandao"]["sect_only"] = "nope"
	var errs := "\n".join(DataLint.check_content(bad))
	for want in ["sects.wudang: jail_room wd_gate is not jail:true", "sects.emei: hostile_entry monster 'm_nope' missing",
			"sects.hengshan: enforcer false needs jail_room", "head_npc n_xh_dingchunqiu lacks BETRAY",
			"sect_rules.wd_r_kill_same: bad event 'ATTACK_NOPE'", "sect_rules.wd_r_morality: text template 'rule_nope' missing",
			"move wd_cq_1 unlock_level 999 >", "move wd_cq_2 bad aoe 'STAR'", "move wd_cq_3 cost_inner 999 > power/2",
			"martial_arts.wd_xinfa: poison needs category POISON", "martial_arts.wd_xinfa: QUEST art needs a quest_flag",
			"is not a shichen", "items.c_jieduyao: cure status 'nope' missing", "items.w_xd_miandao: sect_only 'nope'",
			"acceptance move wd_cq_1 must be unlock 1"]:
		assert_true(want in errs, "lint should report: %s" % want)
	# 簡體字、any_of 內層、時辰
	var bad2 := view.duplicate(true)
	bad2["npcs"]["n_wd_cha"]["desc"] = "这是简体"
	var errs2 := "\n".join(DataLint.check_content(bad2))
	assert_true("npcs.n_wd_cha: simplified character" in errs2, "simplified detected")
	var conds := [{ "type": "any_of", "options": [[{ "type": "hour_in", "hours": ["卯", "X"] }], [{ "type": "nope" }]] }]
	var cond := "\n".join(DataLint.check_conditions(conds, "x"))
	assert_true("x.any_of[0]: hour_in 'X' is not a shichen" in cond, cond)
	assert_true("x.any_of[1]: unknown requires type" in cond, cond)

## M3a 審查 B4：入門武功的範圍招式威力 × 0.75 上限（M3A_PLAN 3.4）lint 抓得到
func test_lint_detects_strong_basic_area_move() -> void:
	assert_eq([DataLint.basic_single_ref(1), DataLint.basic_single_ref(30), DataLint.basic_single_ref(60)], [24, 34, 46])
	var bad := view.duplicate(true)
	var mv: Dictionary = bad["martial_arts"]["gm_yunu_jian"]["moves"][0]
	assert_eq(str(mv["aoe"]), "CROSS")
	mv["power"] = 20
	var errs := "\n".join(DataLint.check_content(bad))
	assert_true("area move gm_yn_1 power 20 > 18" in errs, "小十字 1 級威力 20 > round(24 × 0.75)")
	assert_false("area move" in "\n".join(DataLint.check_content(view)), "現有資料都合規")

# ---------------------------------------------------------------- M3b（WP-MERGE，M3B_PLAN §11.1）

## §3.2 接點表（唯一權威）：房間 A、方向、房間 B、era；反向出口照 DIR_REVERSE
const M3B_ATTACH := [
	["jc_street", "E", "jc_square", "1.0B"], ["jc_square", "N", "jc_street_n", "1.0B"], ["jc_square", "E", "jc_biaoju", "1.0B"],
	["jc_square", "S", "jc_bank", "1.0B"], ["jc_square", "NE", "jc_yamen", "1.0B"], ["jc_square", "NW", "jc_buzhuang", "1.0B"],
	["jc_square", "SW", "jc_pharmacy", "1.0B"], ["jc_yamen", "N", "jc_jail_gate", "1.0B"], ["jc_jail_gate", "N", "jc_jail", "1.0B"],
	["jc_street_n", "W", "jc_smithy", "1.0B"], ["jc_street_n", "E", "jc_tiepu", "1.0B"], ["jc_street_n", "NW", "jc_zijin", "1.0B"],
	["jc_street_n", "NE", "jc_coffin", "1.0B"], ["jc_coffin", "N", "jc_tdh_hall", "1.0B"], ["jc_street_n", "N", "jc_gate_n", "1.0B"],
	["jc_gate_n", "N", "jcn_road1", "1.0B"], ["jcn_road1", "N", "jcn_road2", "1.0B"], ["jcn_road2", "E", "gb_gate", "1.0B"],
	["jcn_road2", "W", "jcn_kongdi", "1.0B"], ["jcn_road2", "N", "jcn_road3", "1.0B"], ["jcn_road3", "N", "jcn_road4", "1.0B"],
	["jcn_road4", "W", "ym_road", "1.0B"], ["gb_gate", "N", "gb_pomiao", "1.0B"], ["gb_pomiao", "N", "gb_houdian", "1.0B"],
	["gb_pomiao", "E", "gb_yuan", "1.0B"], ["jcw_crossroad", "SE", "jq_road1", "1.0B"], ["jq_road1", "E", "jq_gukou", "1.0B"],
	["jq_gukou", "E", "jq_qinghua", "1.0B"], ["jq_qinghua", "E", "jq_shiwu", "1.0B"], ["jq_shiwu", "N", "jq_danfang", "1.0B"],
	["jq_shiwu", "NE", "jq_shufang", "1.0B"], ["jq_shiwu", "SE", "jq_jianfang", "1.0B"], ["jq_shiwu", "E", "jq_duanchang", "1.0B"],
	["jq_shufang", "N", "jq_dilao1", "1.0B"], ["jq_dilao1", "N", "jq_dilao2", "1.0B"], ["jq_dilao2", "N", "jq_eyuchi", "1.0B"],
	["jq_eyuchi", "E", "jq_dilao3", "1.0B"],
	["ym_bridge", "E", "ym_outside", "1.0A"], ["ym_inner", "W", "ym_stele", "1.0A"], ["ym_gate", "W", "mw_mouth", "1.0B"],
	["mw_mouth", "N", "mw_cave1", "1.0B"], ["mw_cave1", "N", "mw_cave2", "1.0B"], ["mw_cave2", "N", "mw_deep", "1.0B"],
	["ts_road1", "SW", "gc_road1", "1.0A"], ["gc_road1", "W", "gc_road2", "1.0A"], ["gc_road2", "W", "gc_road3", "1.0A"],
	["gc_road3", "W", "gc_outside", "1.0A"], ["gc_outside", "SW", "gc_jihut_out", "1.0A"], ["gc_jihut_out", "S", "gc_jihut", "1.0A"],
	["gc_outside", "N", "gc_maze1", "1.0A"], ["gc_maze1", "N", "gc_maze2", "1.0A"], ["gc_maze2", "N", "gc_maze3", "1.0A"],
	["gc_maze3", "N", "gc_maze4", "1.0A"], ["gc_maze4", "N", "gc_maze5", "1.0A"], ["gc_maze5", "N", "gc_maze6", "1.0A"],
	["xx_square", "SW", "xx_bank", "1.0A"], ["xx_square", "NE", "xx_biaoju", "1.0A"], ["xx_street", "SE", "xx_tiepu", "1.0A"],
	["xx_street", "SW", "xx_buzhuang", "1.0A"], ["dl_square", "NW", "dl_bank", "1.0A"], ["dl_square", "NE", "dl_biaoju", "1.0A"],
	["dl_shop", "E", "dl_tiepu", "1.0A"], ["de_edge", "W", "de_mine", "1.0A"],
]

func test_m3b_attach_points_and_steps() -> void:
	var v1b := loader.activate(["1.0A", "1.0B"])
	var idx := DataLint.room_index(v1b)
	var idx_a := DataLint.room_index(view)
	for row in M3B_ATTACH:
		var a: String = row[0]
		var b: String = row[2]
		if not (assert_has(idx, a, "room:") and assert_has(idx, b, "room:")):
			continue
		assert_eq(_exit_to(idx[a]["room"], row[1]), b, "%s %s -> %s" % [a, row[1], b])
		assert_eq(_exit_to(idx[b]["room"], DataLint.DIR_REVERSE[row[1]]), a, "%s back to %s" % [b, a])
		if row[3] == "1.0A":
			assert_has(idx_a, b, "1.0A world has %s:" % b)
		else:
			assert_false(idx_a.has(a) and idx_a.has(b), "1.0A world must not have the %s-%s link" % [a, b])
	# #22：1.0A 的雁門古道往東的出口帶 era 1.0B；1.0A 世界沒有、desc 不提京城北郊
	assert_eq(_exit_to(idx_a["ym_road"]["room"], "E"), "", "1.0A: ym_road has no E exit")
	assert_false(str(idx_a["ym_road"]["room"]["desc"]).contains("京城北郊"), "1.0A desc")
	assert_true(str(idx["ym_road"]["room"]["desc"]).contains("京城北郊"), "1.0B desc_1_0b")
	# §3.4 步數
	var steps := { ["jc_square", "gb_gate"]: 5, ["jc_gate_n", "ym_road"]: 5, ["jc_gate_s", "jc_square"]: 2,
		["jc_gate_s", "jq_gukou"]: 3, ["ym_gate", "mw_deep"]: 4, ["xx_square", "xx_bank"]: 1, ["dl_square", "dl_biaoju"]: 1,
		["xx_gate_e", "jc_gate_s"]: 14 }
	for k in steps:
		assert_eq(DataLint.find_path(v1b, k[0], k[1]).size() - 1, steps[k], "%s -> %s" % [k[0], k[1]])
	var gc := DataLint.find_path(view, "xx_square", "gc_outside").size() - 1
	assert_true(gc >= 10 and gc <= 13, "西夏廣場 → 高昌室外 約 12 步（%d）" % gc)

func test_m3b_gaibang_and_ranks() -> void:
	var v1b := loader.activate(["1.0A", "1.0B"])
	assert_not_has(view["sects"], "gaibang", "1.0A:")
	assert_eq(view["sect_ranks"].size(), 0, "1.0A has no ranks")
	var gb: Dictionary = v1b["sects"]["gaibang"]
	assert_eq([gb["gate_room"], gb["head_npc"], gb["sect_skill"], gb["ranks"], gb["respawn_at_gate"], gb["no_escort"]],
		["gb_gate", "n_gb_chen", "qitao", "gaibang", false, true])
	assert_eq(gb["sect_skill_effect"], { "effect": "POISON_FANG" })
	var arts: Array = []
	for aid in v1b["martial_arts"]:
		if str(v1b["martial_arts"][aid].get("sect_id", "")) == "gaibang":
			arts.append(aid)
	arts.sort()
	assert_eq(arts, ["gb_chansi", "gb_fengmo", "gb_huntian", "gb_lianhua", "gb_liuhe_dao", "gb_mantian", "gb_qinlong",
		"gb_taizu_gun", "gb_taizu_quan", "gb_tongchui", "gb_xinfa"], "丐幫 11 套武功（O6）")
	var adv := { "type": "sect_rank_min", "sect": "gaibang", "value": 2 }
	for aid in ["gb_fengmo", "gb_chansi", "gb_qinlong", "gb_huntian", "gb_lianhua"]:
		assert_true(adv in v1b["martial_arts"][aid]["requires"], "%s needs 二袋" % aid)
	var ranks: Array = v1b["sect_ranks"].keys()
	ranks.sort()
	assert_eq(ranks, ["gb_dai0", "gb_dai1", "gb_dai2"], "1.0B: 一袋、二袋（O8）")
	assert_eq(v1b["sect_ranks"]["gb_dai2"]["cost"], { "fame": 250, "lilian": 250 })
	var vx := loader.activate(DataLoader.era_closure(loader.all_tables["eras"], "xkd"))
	assert_eq(vx["sect_ranks"].size(), 8, "xkd: 無袋～七袋")
	assert_eq(v1b["npcs"]["n_jc_smith"]["shop"]["refuse_if"], [[{ "type": "sect", "sect": "gaibang" }]], "O10")

func test_m3b_capital_jail_life_skills_and_escort() -> void:
	var v1b := loader.activate(["1.0A", "1.0B"])
	var caps: Array = []
	for rid in DataLint.room_index(v1b):
		var room: Dictionary = DataLint.room_index(v1b)[rid]["room"]
		if str(room.get("jail_scope", "")) == "CAPITAL":
			caps.append(rid)
	assert_eq(caps, ["jc_jail"], "exactly one CAPITAL jail")
	assert_eq(DataLint.room_index(v1b)["jc_jail"]["room"]["jail_release_to"], "jc_yamen")
	var life := ["life_mining", "life_smithing", "life_swordsmith", "life_weaving", "life_tailoring", "life_hunting"]
	for lid in life:
		assert_has(view["life_skills"], lid, "1.0A life skill:")
	assert_not_has(view["life_skills"], "life_carpentry", "工匠 is 1.0B:")
	assert_has(v1b["life_skills"], "life_carpentry", "1.0B:")
	assert_eq(v1b["life_skills"].size(), 11)
	assert_eq(v1b["life_skills"]["life_hunting"]["mode"], "HUNT")
	assert_eq(v1b["life_skills"]["life_carpentry"]["feature"], "")
	assert_eq(view["items"]["r_kuang_lv"]["grade"], 2)
	assert_eq(view["items"]["r_kuang_zi"]["grade"], 3)
	var routes: Array = v1b["escort_routes"].keys()
	routes.sort()
	assert_eq(routes, ["er_dl_jc", "er_dl_xx", "er_jc_dl", "er_jc_xx", "er_xx_dl", "er_xx_jc"], "6 條保鏢路線")
	var ra: Array = view["escort_routes"].keys()
	ra.sort()
	assert_eq(ra, ["er_dl_xx", "er_xx_dl"], "1.0A: 西夏↔大理")
	var no_gb := { "type": "sect_not", "sect": "gaibang" }
	assert_false(no_gb in view["quests"]["q_ec_biao_xx_dl"].get("requires", []), "1.0A has no 丐幫")
	for qid in ["q_ec_biao_xx_dl", "q_ec_biao_dl_xx", "q_ec_biao_xx_jc", "q_ec_biao_jc_xx", "q_ec_biao_dl_jc", "q_ec_biao_jc_dl"]:
		assert_true(no_gb in v1b["quests"][qid]["requires"], "%s: 丐幫不能運鏢（O17）" % qid)

func test_m3b_fixed_ids_exist() -> void:
	var v1b := loader.activate(["1.0A", "1.0B"])
	var want := {
		"npcs": ["n_gb_chen", "n_gb_chuangong", "n_gb_zhanggun", "n_gb_zhifa", "n_gb_spar", "n_gb_jiang", "n_gb_youqiming",
			"n_gb_pan", "n_gb_shenyi", "n_gb_jc_informant", "n_gb_dl_qigai", "n_jc_guard_n", "n_jc_jailer", "n_jc_wushi",
			"n_jc_bukuai", "n_jc_smith", "n_jc_pharmacist", "n_jc_zijin_guard", "n_tdh_zhanggui", "n_tdh_chenjinnan",
			"n_tdh_shop", "n_jc_zhangyuanwai", "n_jq_gongsunzhi", "n_jq_lve", "n_jq_fanyiweng", "n_jq_qiuqianchi", "n_jq_liumei",
			"n_mj_fanyao", "n_ym_miaorenfeng", "n_ym_keshi", "n_ym_azhu", "n_gc_tuodui", "n_gc_xiangxiang", "n_gc_huoqingtong",
			"n_gc_jilaoren", "n_gc_liwenxiu", "n_xx_zhangtie", "n_ls_kuanggong", "n_ls_dl_zhujian", "n_ls_jc_mujiang",
			"n_ls_xx_fangzhi", "n_ec_biaoche", "n_og_xx_shuli", "n_og_dl_shuli", "n_og_jc_shuli"],
		"monsters": ["m_gb_dizi", "m_gb_xiaohuang", "m_gb_xiejiao", "m_gb_manbing", "m_jcn_mazeitou",
			"m_jcn_edaotou", "m_jcn_daoren", "m_jcn_yinmian", "m_jcn_huguo", "m_jcn_shafeng", "m_jc_qigaitou", "m_jc_buliang",
			"m_jq_lvyi", "m_jq_eyu", "m_jq_fanyiweng", "m_mw_mawang", "m_gc_jiguanren", "m_gc_jiguanren2"],
		"items": ["c_jq_juequingdan", "w_jq_junzijian", "w_jq_shunvjian", "a_huangjia", "r_sm_jieducao",
			"t_shizigao", "t_caishaqi", "t_tiechui", "t_juzi", "t_zhenxian", "r_kuang_tie", "r_tiekuai_1", "r_tiekuai_2",
			"r_tiekuai_3", "r_mutan", "r_jiaotan", "r_zhongzi_ma", "r_zhongzi_mian", "r_ma", "r_mianhua", "r_xianzhou", "r_mabu",
			"r_mianbu", "r_shoupi", "r_pige", "w_tiejian", "w_lengning", "w_muzhang", "w_xuanmuzhang", "w_muzhua", "a_douli"],
		"quests": ["q_gb_dai1", "q_gb_dai2", "q_gb_xin", "q_tdh_ruhui", "q_jc_xiaobao", "q_jc_lingquan", "q_jc_zhangyuanwai",
			"q_jq_liumei", "q_jq_duanchang", "q_ym_tuoyin", "q_ym_xiaofeng", "q_ym_douji", "q_sm_yuntie", "q_sm_qidu",
			"q_sm_zhuadu", "q_sm_lengning", "q_sm_chengwei", "q_sm_dujulaoren", "q_sm_esi_nongfu", "q_sm_ahuo", "q_sm_abao",
			"q_sm_ahong", "q_sm_rixing", "q_sm_shepi", "q_sm_litong", "q_ec_biao_xx_dl"],
		"status_effects": ["qinghua"], "sect_rules": ["gb_r_kill_same"],
		"regions": ["jingcheng_north", "gaibang", "jueqinggu", "jueqinggu_dilao", "mawang", "gaochang_road", "gaochang", "gaochang_maze"],
	}
	for t in want:
		for id in want[t]:
			assert_has(v1b[t], id, "%s:" % t)
	assert_eq(DataLint.room_index(v1b)["jq_qinghua"]["room"]["on_enter_status"]["status"], "qinghua")
	assert_eq(v1b["items"]["c_jq_juequingdan"]["unique_per_char"], true)
	for q in v1b["quests"]:
		if str(q).begins_with("q_mj_"):
			assert_true(false, "O11: no 明教 quests (%s)" % q)
	assert_false("JOIN" in v1b["npcs"]["n_mj_fanyao"]["services"], "O11: 范遙 does not take disciples")

func test_lint_m3b_catches_bad_data() -> void:
	var v1b := loader.activate(["1.0A", "1.0B"])
	assert_eq(DataLint.check_m3b(v1b).size(), 0, "real data clean:\n  " + "\n  ".join(DataLint.check_m3b(v1b)))
	var bad := v1b.duplicate(true)
	bad["monsters"]["m_hunt_lang"]["hunt"] = false
	bad["sect_ranks"]["gb_dai2"]["rank"] = 5
	bad["sect_ranks"]["gb_dai1"]["cost"] = { "xp": 1 }
	bad["escort_routes"]["er_dl_xx"]["to_city"] = "dali"
	bad["escort_routes"]["er_dl_xx"]["from_city"] = "xixia"
	for room in bad["maps"]["jingcheng_north"]["rooms"]:
		if room["id"] == "jcn_road1":
			room["encounter"]["table"].append({ "monster": "m_wolf", "w": 5, "count": [1, 1] })
	for room in bad["maps"]["xixia"]["rooms"]:
		if room["id"] == "xx_bank":
			room["jail"] = true
			room["jail_scope"] = "CAPITAL"
	bad["life_skills"]["life_smithing"]["recipes"][0]["inputs"].append({ "item": "w_jq_junzijian", "n": 1 })
	bad["quests"]["q_gb_dai1"]["outcomes"]["default"]["rewards"]["sect_rank"] = { "sect": "gaibang", "rank": 2 }
	var errs := "\n".join(DataLint.check_m3b(bad))
	for want in ["hunt_table monster m_hunt_lang is not hunt:true", "sect gaibang ranks must run 0..n", "cost key 'xp'",
			"route xixia>dali already defined", "room jcn_road1: m_wolf not allowed here", "2 jail_scope CAPITAL rooms",
			"CAPITAL jail needs jail_release_to", "input 'w_jq_junzijian' has no source",
			"quests.q_gb_dai1: sect_rank {gaibang, 2} has no sect_ranks row"]:
		assert_true(want in errs, "lint should report: %s\n%s" % [want, errs.left(600)])
	# 跨 era 的 NPC 可以只靠 npcs.room 放（1.0B 丐幫弟子在 1.0A 大理廣場）；同 era 的還是要列在房間清單
	assert_false("n_gb_dl_qigai" in "\n".join(DataLint.check_content(v1b)), "cross-era npc placement accepted")
	var bad2 := v1b.duplicate(true)
	for room in bad2["maps"]["jingcheng"]["rooms"]:
		if room["id"] == "jc_yamen":
			room["npcs"].erase("n_jc_bukuai")
	assert_true("npcs.n_jc_bukuai: room jc_yamen does not list this npc" in "\n".join(DataLint.check_content(bad2)), "same-era listing still required")
