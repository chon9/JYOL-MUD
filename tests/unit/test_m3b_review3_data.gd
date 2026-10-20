extends "res://tests/test_case.gd"
## M3b 審查 3（資料）：era／src 標記、官方製作鏈、丐幫入派、1.0A 世界不提 1.0B 的地名與門派、黃罩甲、絕情丹、深層迷宮。

const DataLint := preload("res://tools/data_lint.gd")

var loader: DataLoader
var loader_b: DataLoader
var v1a: Dictionary
var v1b: Dictionary

func before_each() -> void:
	if loader == null:
		loader = DataLoader.new()
		loader.load_all("res://data")
		v1a = loader.activate(["1.0A"])
		loader_b = DataLoader.new()   # 另一個 loader：patch 不會改到 1.0A 視圖
		loader_b.load_all("res://data")
		v1b = loader_b.activate(["1.0A", "1.0B"])

func _recipe(view: Dictionary, skill: String, rid: String) -> Dictionary:
	for rc in view["life_skills"][skill].get("recipes", []):
		if str(rc.get("id", "")) == rid:
			return rc
	return {}

func _inputs(rc: Dictionary) -> Array:
	var out: Array = []
	for i in rc.get("inputs", []):
		out.append(str(i.get("item", "")))
	return out

## #1：1.0A 世界的錢莊、鏢頭不提京城、丐幫；1.0B 由 patch 補回
func test_1_0a_talk_has_no_1_0b_names() -> void:
	for id in ["talk_n_ec_xx_banker", "talk_n_ec_xx_biaotou"]:
		var t := str(v1a["text_templates"][id]["self"])
		assert_false(t.contains("京城") or t.contains("丐幫"), "1.0A %s: %s" % [id, t])
	assert_true(str(v1b["text_templates"]["talk_n_ec_xx_banker"]["self"]).contains("京城"), "1.0B 錢莊提京城分號")
	assert_true(str(v1b["text_templates"]["talk_n_ec_xx_biaotou"]["self"]).contains("丐幫"), "1.0B 鏢頭提丐幫不能運鏢")

## #2：細節借自後期的 1.0A 任務列 src 是 later
func test_borrowed_detail_quests_are_later() -> void:
	for q in ["q_sm_lengning", "q_sm_chengwei", "q_sm_qidu", "q_sm_zhuadu"]:
		assert_eq(str(v1a["quests"][q]["src"]), "later", q)
	assert_true(str(v1a["quests"]["q_sm_qidu"]["src_note"]).contains("appear.hours"), "七毒的辰～未時寫在任務列")

## #3：范遙不說話的細節是待考證
func test_fanyao_silence_unverified() -> void:
	assert_eq(str(v1a["text_templates"]["talk_n_mj_fanyao"]["src"]), "unverified")
	assert_false(str(v1a["text_templates"]["talk_n_mj_fanyao"]["src_note"]).contains("【已證實】"))

## #4：丐幫入派沒有善惡門檻（找不到出處），停止傳功照舊
func test_gaibang_join_has_no_morality_gate() -> void:
	var gb: Dictionary = v1b["sects"]["gaibang"]
	for c in gb["join_requires"]:
		assert_false(str(c.get("type", "")).begins_with("morality"), "join_requires: %s" % str(c))
	assert_eq(gb["teach_requires"], [{ "type": "morality_min", "value": 0 }])

## #7：官方製作鏈（礦 → 鐵塊 → 打鐵；線軸 → 布匹 → 裁縫），每一步成品收購價高於材料
func test_official_craft_chain() -> void:
	assert_eq(_inputs(_recipe(v1a, "life_tailoring", "rc_bupao")), ["r_mabu"], "布衣用麻布縫")
	for rid in ["rc_chaidao", "rc_chutou", "rc_shizigao", "rc_caishaqi", "rc_tiechui"]:
		var ins := _inputs(_recipe(v1a, "life_smithing", rid))
		assert_true("r_tiekuai_1" in ins, "%s 用鐵塊：%s" % [rid, str(ins)])
		assert_false("r_kuang_tie" in ins, "%s 不直接用礦：%s" % [rid, str(ins)])
	var sellv := func(id: String) -> int:
		var r: Dictionary = v1b["items"].get(id, {})
		return 0 if r.is_empty() or bool(r.get("no_sell", false)) else maxi(1, int(floor(int(r.get("price", 0)) * 0.3)))
	for sid in v1b["life_skills"]:
		for rc in v1b["life_skills"][sid].get("recipes", []):
			var out_v: int = sellv.call(str(rc["output"]["item"])) * int(rc["output"].get("n", 1))
			var in_v := 0
			for i in rc.get("inputs", []):
				in_v += sellv.call(str(i["item"])) * int(i.get("n", 1))
			assert_true(out_v > in_v, "%s：成品 %d > 材料 %d" % [str(rc["id"]), out_v, in_v])

## #8：黃罩甲只在 1.0B；防禦不再是皮甲的四倍多
func test_huangjia_is_1_0b_and_scaled() -> void:
	assert_false(v1a["items"].has("a_huangjia"), "1.0A 世界沒有黃罩甲")
	assert_has(v1b["items"], "a_huangjia")
	assert_true(int(v1b["items"]["a_huangjia"]["def"]) <= int(v1b["items"]["a_pijia"]["def"]) * 2, "防禦 ≤ 皮甲兩倍")

## 絕情丹：解毒不消耗（一人一顆、唯一解藥）
func test_juequingdan_keep_on_use() -> void:
	var it: Dictionary = v1b["items"]["c_jq_juequingdan"]
	assert_eq(it.get("keep_on_use", false), true)
	assert_eq(it.get("unique_per_char", false), true)

## 高昌迷宮：銅甲機關人只在第 6 層、一次一隻；機關零件值錢
func test_gaochang_deep_floors() -> void:
	var idx: Dictionary = DataLint.room_index(v1a)
	for rid in ["gc_maze4", "gc_maze5"]:
		for e in idx[rid]["room"]["encounter"]["table"]:
			assert_true(str(e["monster"]) != "m_gc_jiguanren2", "%s 沒有銅甲" % rid)
	var has_tj := false
	for e in idx["gc_maze6"]["room"]["encounter"]["table"]:
		if str(e["monster"]) == "m_gc_jiguanren2":
			has_tj = true
			assert_eq(e["count"], [1, 1], "銅甲一次一隻")
	assert_true(has_tj, "第 6 層有銅甲")
	assert_true(int(v1a["items"]["r_gc_lingjian"]["price"]) >= 200, "機關零件值錢")

## 文字：保鏢酬勞、橋邊、嵩山古道方向、陳長老指二袋
func test_text_fixes() -> void:
	assert_false(str(v1b["text_templates"]["talk_n_ec_xx_tangzi"]["self"]).contains("一分錢"))
	assert_false(str(v1b["text_templates"]["gb_tell_amb_ym"]["self"]).contains("橋下"))
	assert_false(str(v1b["text_templates"]["rmr_q_gb_dai1_foreshadow"]["self"]).contains("橋下"))
	assert_true(str(v1b["text_templates"]["talk_n_gb_chen"]["self"]).contains("姜乞丐"))
	var idx: Dictionary = DataLint.room_index(v1b)
	assert_true(str(idx["jcw_songshan"]["room"]["desc"]).contains("少室山腳"))
	assert_true(str(idx["jq_gukou"]["room"]["desc"]).contains("三萬"), "谷口警告")
	assert_true(str(idx["jcn_kongdi"]["room"]["desc"]).contains("送死"), "空地警告")
