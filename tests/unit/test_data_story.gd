extends "res://tests/test_case.gd"
## 故事包資料（WP-MERGE，STORY_PLAN §8.4 #4、§8.5）：每條故事任務的階段圖從 start 走得到、每條路都會結束、
## 結局齊全、NPC 與房間存在、從兩座出生城走得到；§2 新地區與新房間；§3 固定 id；lint 新檢查會抓到壞資料。

const DataLint := preload("res://tools/data_lint.gd")

## §1.1 P0（ev_yangkang、ev_chendabao、ev_misc_2001 碎片未交付，不在這裡）
const P0 := ["q_yuner", "q_xuzhu", "q_liu_jinpen", "q_liu_jinpen_2", "q_xingxia", "q_wentailai", "q_lanfeng",
	"q_guhongzi", "q_hs_jianqi", "q_hs_spy"]
## §1.1 門派表
const SECT_QUESTS := ["q_wd_yinliu", "q_wd_heiyu", "q_wd_longmen", "q_wd_yitian", "q_wd_taiji", "q_em_shougongsha",
	"q_em_shandu", "q_em_baifang", "q_em_lianhuan", "q_sl_riyuebian", "q_xh_huagong", "q_xd_xuehai",
	"q_lj_chengqingshuang", "q_gm_limochou", "q_hg_lincai"]
## §3.2：NPC id -> 房間（本包交付的部分）
const NPC_ROOMS := {
	"n_xx_yuner": "xx_minfang", "n_xx_litaian": "xx_pharmacy", "n_xx_abao": "xn_slope", "n_xx_xuzhu": "xx_yamen",
	"n_xx_palace_guard_l": "xx_palace", "n_xx_palace_guard_r": "xx_palace", "n_xx_ada": "xx_palace",
	"n_sl_daopin": "sl_leftroom", "n_xx_zhangbao": "xx_yamen", "n_dl_wangbutou": "dl_yamen",
	"n_hn_liugongzi": "hn_foot", "n_hn_dizi": "hn_foot", "n_hn_teaman": "hn_teahouse", "n_hn_moda": "hn_shore",
	"n_hn_lulianrong": "hn_island", "n_hn_mimike": "hn_teahouse", "n_hn_longmen": "hn_teahouse",
	"n_dl_cunmin": "dl_square", "n_dlw_guiyi": "dlw_desertcave", "n_lf_lanfenghuang": "rr_eastbank",
	"n_hs_lanyihan": "hs_square", "n_ym_lingzhi": "ym_gate", "n_ym_qiangdao": "ym_bridge", "n_ym_hufei": "ym_inner",
	"n_xx_laodenuo": "xx_inn", "n_hs_linghuchong": "hy_pond", "n_hs_chengbuyou": "hs_siguoya",
	"n_xx_qiaofeng": "xx_inn", "n_xx_azi": "xx_inn", "n_dl_limochou": "dlw_lake",
}

var loader: DataLoader
var view: Dictionary

func before_each() -> void:
	if loader == null:
		loader = DataLoader.new()
		loader.load_all("res://data")
		view = loader.activate(["1.0A"])

func _graph_ok(qid: String) -> void:
	var q: Dictionary = view["quests"][qid]
	var errs := QuestDef.validate(q, view)
	assert_eq(errs.size(), 0, "%s validate:\n  %s" % [qid, "\n  ".join(errs)])
	assert_true(not bool(q.get("_legacy", false)), "%s is a v2 row" % qid)
	assert_true((q["stages"] as Array).size() >= 1, "%s has stages" % qid)

# ---------------------------------------------------------------- 任務列

func test_every_story_quest_exists_and_validates() -> void:
	for qid in P0 + SECT_QUESTS:
		if assert_has(view["quests"], qid, "quest:"):
			_graph_ok(qid)
	# 既有 15 條（實際 14 條＋）一條都沒刪，而且還是舊格式
	for old in ["q_rabbit", "q_rice", "q_letter", "q_letter_dl", "q_bandit", "q_hs_kaoyan"]:
		if assert_has(view["quests"], old, "legacy quest:"):
			assert_true(bool(view["quests"][old].get("_legacy", false)), "%s still legacy" % old)

func test_every_outcome_has_a_test_plan_path() -> void:
	for qid in P0 + SECT_QUESTS:
		var q: Dictionary = view["quests"][qid]
		var covered := {}
		for tp in q.get("test_plan", []):
			covered[str(tp.get("outcome", "default"))] = true
			assert_eq(str(tp.get("quest", "")), qid, "%s test_plan quest" % qid)
			assert_true((tp.get("path", []) as Array).size() > 0, "%s test_plan has a path" % qid)
		for oc in q["outcomes"]:
			assert_has(covered, oc, "%s outcome without test path:" % qid)

func test_branching_quests_have_their_endings() -> void:
	var want := { "q_yuner": ["abao", "li"], "q_lanfeng": ["default", "hengshan", "repeat"], "q_hs_jianqi": ["jianzong", "qizong"],
		"q_guhongzi": ["truth", "silent"] }
	for qid in want:
		var keys: Array = view["quests"][qid]["outcomes"].keys()
		keys.sort()
		var exp: Array = want[qid].duplicate()
		exp.sort()
		assert_eq(keys, exp, "%s outcomes" % qid)

func test_story_lint_is_clean() -> void:
	var errs := DataLint.check_story(view)
	assert_eq(errs.size(), 0, "story lint:\n  " + "\n  ".join(errs))
	var v1b := loader.activate(["1.0A", "1.0B"])
	var e2 := DataLint.check_story(v1b)
	assert_eq(e2.size(), 0, "story lint 1.0B:\n  " + "\n  ".join(e2))

func test_quest_places_walkable_from_both_birth_cities() -> void:
	var births := DataLint.birth_rooms(view)
	assert_eq(births.size(), 2, "two birth cities")
	for qid in P0 + SECT_QUESTS:
		var q: Dictionary = view["quests"][qid]
		var g := DataLint.quest_room_graph(view, q)
		for br in births:
			var seen: Dictionary = DataLint._bfs(g, br, "")["seen"]
			for p in DataLint.quest_places(view, q):
				assert_has(seen, p["room"], "%s %s from %s:" % [qid, p["where"], br])

func test_givers_list_their_quests() -> void:
	for qid in P0 + SECT_QUESTS:
		var g := str(view["quests"][qid]["giver"])
		if assert_has(view["npcs"], g, "%s giver:" % qid):
			assert_has(view["npcs"][g]["quests"], qid, "%s giver %s quests:" % [qid, g])
			assert_has(view["npcs"][g]["services"], "QUEST", "%s giver %s services:" % [qid, g])

# ---------------------------------------------------------------- §2 世界接點

func test_new_regions_and_rooms() -> void:
	var r: Dictionary = view["regions"]
	var wp := { "hengshan_s_road": [900, 520], "hengshan_s": [943, 678], "yanmen": [837, 96] }
	for id in wp:
		if assert_has(r, id, "region:"):
			assert_eq(r[id]["type"], "WILD", id)
			assert_eq(r[id]["world_pos"], wp[id], "%s world_pos" % id)
			assert_eq(r[id]["pk_allowed"], true, id)
	var idx := DataLint.room_index(view)
	# §2.2 出口（雙向）
	var links := [["xx_gate_e", "S", "xx_minfang"], ["xx_square", "NW", "xx_yamen"], ["xx_street", "NW", "xx_palace"],
		["xx_palace", "N", "xx_palace_mishi"], ["sl_court", "NW", "sl_leftroom"], ["hs_hall", "N", "hs_siguoya"],
		["dlw_lake", "W", "dlw_desertcave"], ["rr_bend", "E", "rr_eastbank"], ["wd_road1", "SE", "hn_road1"],
		["hn_road1", "S", "hn_road2"], ["hn_road2", "S", "hn_foot"], ["hn_foot", "E", "hn_teahouse"],
		["hn_foot", "NE", "hn_shore"], ["hn_foot", "SE", "hn_bridge"], ["hn_bridge", "S", "hn_island"],
		["hf_fork", "NE", "ym_road"], ["ym_road", "N", "ym_gate"], ["ym_gate", "SE", "ym_bridge"], ["ym_gate", "N", "ym_inner"]]
	for l in links:
		if not (assert_has(idx, l[0], "room:") and assert_has(idx, l[2], "room:")):
			continue
		assert_eq(_exit_to(idx[l[0]]["room"], l[1]), l[2], "%s %s" % [l[0], l[1]])
		assert_eq(_exit_to(idx[l[2]]["room"], DataLint.DIR_REVERSE[l[1]]), l[0], "%s back" % l[2])
	assert_eq(idx["xx_palace_mishi"]["room"]["requires"], [{ "type": "quest_active", "quest": "q_yangkang" }])
	assert_eq(idx["hn_teahouse"]["region"], "hengshan_s")
	assert_false(idx["hn_teahouse"]["room"].has("encounter"), "hn_teahouse is a rest point")
	assert_true("INN" in view["npcs"]["n_hn_teaman"]["services"], "茶店老闆 INN")
	assert_true(str(idx["hf_fork"]["room"]["desc"]).contains("雁門關"), "hf_fork desc mentions 雁門關")
	assert_false(str(view["text_templates"]["talk_n_hf_teaman"]["self"]).contains("封著"), "雁門關 no longer closed")

func test_new_regions_pass_newbie_rules() -> void:
	# §2.3：西夏、大理 → 衡山小茶店、雁門關口 的路線也套 WORLD_2001 §1.4
	var errs := DataLint.check_newbie_routes(view)
	assert_eq(errs.size(), 0, "newbie safety:\n  " + "\n  ".join(errs))
	var p := DataLint.find_path(view, "wd_road1", "hn_teahouse")
	assert_eq(p.size() - 1, 4, "wd_road1 -> hn_teahouse is 4 steps: %s" % str(p))
	var p2 := DataLint.find_path(view, "hf_teahouse", "ym_gate")
	assert_eq(p2.size() - 1, 4, "hf_teahouse -> ym_gate is 4 steps: %s" % str(p2))
	var idx := DataLint.room_index(view)
	for rid in ["hn_foot", "ym_gate"]:
		for e in idx[rid]["room"]["encounter"]["table"]:
			assert_true(e["monster"] in DataLint.NEWBIE_EDGE_MONSTERS, "%s next to a rest point has only rabbits" % rid)

func _exit_to(room: Dictionary, dir: String) -> String:
	for ex in room.get("exits", []):
		if ex.get("dir", "") == dir:
			return str(ex.get("to", ""))
	return ""

# ---------------------------------------------------------------- §3 固定 id

func test_fixed_npc_ids_and_rooms() -> void:
	for nid in NPC_ROOMS:
		if assert_has(view["npcs"], nid, "npc:"):
			assert_eq(view["npcs"][nid]["room"], NPC_ROOMS[nid], "%s room" % nid)
	var ap: Dictionary = view["npcs"]["n_hn_moda"].get("appear", {})
	assert_eq(ap.get("hours", []), ["申", "酉"], "莫大 appears 申酉 (D3)")
	assert_true(not (view["npcs"]["n_xx_zhangbao"]["appear"]["hours"] as Array).has("子"), "張豹 absent at 子")

func test_fixed_items_monsters_flags() -> void:
	for it in ["i_hn_wulintie", "c_dahuandan", "i_xz_huixin", "i_gh_jiashu", "i_gh_yunerxin", "c_niuroubing",
			"r_lf_wugong", "r_lf_qingshe", "r_lf_xiezi", "r_lf_zhizhu", "r_lf_chanchu", "r_lf_mabu", "r_kuang_zi",
			"r_kuang_lv", "i_ym_baohe", "c_lingzhicao", "c_baijiu", "c_yangrujiu", "c_zhuyeqing", "i_wtl_gongwen",
			"i_hs_mihan", "i_hs_zhuijiling", "i_hs_qizongwupu"]:
		assert_has(view["items"], it, "item:")
	for m in ["m_xx_palace_guard", "m_hn_mojiao", "m_dl_mingjiao", "m_lf_wugong", "m_lf_zhizhu", "m_ym_qiangdao",
			"m_xx_laodenuo", "m_nanhai", "m_yeerniang", "m_amb_etou"]:
		assert_has(view["monsters"], m, "monster:")
	assert_eq(view["items"]["c_dahuandan"]["price"], 1400, "D6 大還丹 1400")
	assert_true("c_dahuandan" in view["npcs"]["n_xx_pharmacist"]["shop"]["items"], "D6 西夏藥鋪")
	for a in ["hs_zixia", "xh_huagong"]:
		if assert_has(view["martial_arts"], a, "art:"):
			assert_eq(view["martial_arts"][a]["tier"], "QUEST", a)
	var flags := DataLint.flags_set_somewhere(view)
	for f in DataLint.STORY_UNLOCK_FLAGS:
		assert_has(flags, f, "flag set by a quest:")
	assert_has(DataLint.conditions_of_type(view["martial_arts"]["sl_riyuebian"]["requires"], "quest_flag"),
		{ "type": "quest_flag", "flag": "sl_riyuebian_ok" }, "art_patches 日月鞭法:")

func test_new_tables_loaded() -> void:
	for t in ["rumors", "wanderers", "ambient", "reactions"]:
		assert_true((view[t] as Dictionary).size() > 0, "%s has rows" % t)
	for wid in ["w_nanhai", "w_yeerniang"]:
		assert_has(view["wanderers"], wid, "wanderer:")
	for qid in P0:
		var has_fs := false
		for rid in view["rumors"]:
			if view["rumors"][rid]["quest"] == qid and view["rumors"][rid]["kind"] == "FORESHADOW":
				has_fs = true
		assert_true(has_fs, "%s has a FORESHADOW rumor (§7.2 #6)" % qid)
		assert_true(str(view["quests"][qid]["rumors"].get("first", "")) != "", "%s rumors.first" % qid)

# ---------------------------------------------------------------- lint 會抓到壞的故事資料

func test_lint_catches_broken_story_quests() -> void:
	var bad := view.duplicate(true)
	var q: Dictionary = bad["quests"]["q_yuner"]
	# 死循環：s_thanks 改成跳回 s_choose 自己永遠到不了 END；出現沒有結局的 END
	for s in q["stages"]:
		if s["id"] == "s_thanks":
			s["next"] = [{ "goto": "s_thanks" }]
		if s["id"] == "s_abao":
			s["next"] = [{ "goto": "END:nobody" }]
	var errs := "\n".join(QuestDef.validate(q, bad))
	assert_true(errs.contains("END:nobody"), "missing outcome caught: " + errs)
	assert_true(errs.contains("unreachable") or errs.contains("never reach END"), "graph problem caught: " + errs)
	# 目標 NPC 放到走不到的房間
	bad = view.duplicate(true)
	bad["npcs"]["n_xx_abao"]["room"] = "hs_siguoya"   # 只有華山派進得去
	var e2 := "\n".join(DataLint._s_quest_reach(bad))
	assert_true(e2.contains("q_yuner") and e2.contains("hs_siguoya"), "requires room caught: " + e2)
	# 有時辰限制的 NPC，log 沒寫時辰
	bad = view.duplicate(true)
	for s in bad["quests"]["q_liu_jinpen"]["stages"]:
		s["log"] = "去找莫大。"
	var e3 := "\n".join(DataLint._s_appear(bad))
	assert_true(e3.contains("q_liu_jinpen"), "time-limited log caught: " + e3)
	# 任務掉落沒有 requires／不是必掉
	bad = view.duplicate(true)
	bad["monsters"]["m_lf_wugong"]["drops"][0].erase("requires")
	bad["monsters"]["m_lf_wugong"]["drops"][0]["chance"] = 0.5
	var e4 := "\n".join(DataLint._s_drops(bad))
	assert_true(e4.contains("needs requires") and e4.contains("guaranteed"), "quest drop caught: " + e4)
	# 遊蕩惡人跑進城、反應影響 QUEST 服務、測試路徑缺結局、條件指到不存在的階段
	bad = view.duplicate(true)
	bad["wanderers"]["w_nanhai"]["schedule"][1]["regions"].append("xixia")
	var rx: String = bad["reactions"].keys()[0]
	bad["reactions"][rx]["services"].append("QUEST")
	bad["quests"]["q_yuner"]["test_plan"] = []
	bad["npcs"]["n_hn_mimike"]["appear"]["requires"] = [{ "type": "quest_stage", "quest": "q_liu_jinpen_2", "stage": "s_nope" }]
	var e5 := "\n".join(DataLint.check_story(bad))
	assert_true(e5.contains("roams into CITY"), "wanderer in city caught: " + e5)
	assert_true(e5.contains("must never be affected"), "reaction service caught: " + e5)
	assert_true(e5.contains("q_yuner: test_plan"), "test_plan coverage caught: " + e5)
	assert_true(e5.contains("s_nope"), "bad stage ref caught: " + e5)
	# 簡體字（§8.5 #9 擴充：鳳风、寶宝、雲云…）
	bad = view.duplicate(true)
	bad["quests"]["q_yuner"]["stages"][0]["log"] = "去找李台安说说话，问问他的心意。"
	bad["quests"]["q_xingxia"]["name"] = "行侠仗义宝盒"
	var e6 := "\n".join(DataLint._c_simplified(bad))
	assert_true(e6.contains("q_yuner") and e6.contains("q_xingxia"), "simplified chars caught: " + e6)
