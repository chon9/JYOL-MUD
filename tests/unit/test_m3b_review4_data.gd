extends "res://tests/test_case.gd"
## M3b 審查 4（資料）：1.0A 世界不漏 1.0B 地名、丐幫跑腿的已證實獎勵、馬賊王的難度順序、京城附近的路線文字、
## 出處標記（靈犬小黃、小黃免追、四～七袋、游啟）、文件（M3B_PLAN 馬王洞 era、GDD 註 1、延後清單）。

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

## 1.0A 視圖裡會給玩家看的字串（出處備註、desc_1_0b 除外）
func _strings(v: Variant, path: String, out: Array) -> void:
	if v is Dictionary:
		for k in v:
			if str(k).ends_with("src_note") or str(k) == "desc_1_0b":
				continue
			_strings(v[k], path + "." + str(k), out)
	elif v is Array:
		for i in (v as Array).size():
			_strings(v[i], "%s[%d]" % [path, i], out)
	elif v is String:
		out.append([path, v])

func _doc(path: String) -> String:
	return FileAccess.get_file_as_string(path)

## A#1：1.0A 世界的文字不提京城、丐幫、絕情谷、馬王洞、神鵰大俠（era 表與「還沒開放」的系統訊息除外）
func test_1_0a_world_has_no_1_0b_names() -> void:
	var all: Array = []
	_strings(v1a, "", all)
	var allow := [".eras.1.0B.name", ".text_templates.era_1_0b_pending.self", ".text_templates.err_era_locked.self"]
	var bad: Array = []
	for e in all:
		if str(e[0]) in allow:
			continue
		for w in ["京城", "神鵰大俠", "丐幫", "絕情谷", "馬王洞"]:
			if str(e[1]).contains(w):
				bad.append("%s [%s]" % [e[0], w])
				break
	assert_eq(bad, [], "1.0A 文字漏了 1.0B 地名")
	var idx_a := DataLint.room_index(v1a)
	var idx_b := DataLint.room_index(v1b)
	assert_false(str(idx_a["xx_bank"]["room"]["desc"]).contains("京城"), "1.0A 錢莊描述")
	assert_false(str(idx_b["xx_bank"]["room"]["desc"]).contains("京城"), "desc_1_0b 只給有 1.0B 出口的房間（lint §4.4）")
	assert_true(str(v1b["text_templates"]["talk_n_ec_xx_banker"]["self"]).contains("京城"), "1.0B 由掌櫃的對白說京城分號")

## A#2、#3：丐幫跑腿的已證實獎勵（verified_research 1188 行）
func test_errand_rewards_follow_research() -> void:
	var ahuo: Dictionary = v1a["quests"]["q_sm_ahuo"]["outcomes"]["default"]
	assert_eq(int(ahuo["rewards"].get("fame", 0)), 3, "礦工阿火：+3 名聲")
	assert_eq(int(ahuo["rewards"].get("lilian", 0)), 0, "礦工阿火：只有名聲，沒有歷練")
	assert_eq(str(ahuo["src"]), "verified")
	var lao: Dictionary = v1a["quests"]["q_sm_dujulaoren"]
	assert_eq(int(lao["repeat"]["max"]), 0, "西夏老人送藥可重複")
	assert_eq(int(lao["repeat"]["cooldown_days"]), 1, "每天一次")
	assert_eq(int(lao["outcomes"]["default"]["rewards"]["fame"]), 1)
	assert_eq(int(lao["outcomes"]["default"]["rewards"]["lilian"]), 1)
	assert_eq(str(lao["outcomes"]["default"]["field_src"]["money"]), "unverified", "15 兩未重抓")

## A#6：馬賊王照 gaoshou/25「弱、18 級」：級距低於同一片空地的道人頭子、隱面人，仍 ≥ 嘍囉
func test_mawang_tier() -> void:
	var m: Dictionary = v1b["monsters"]
	var mw := int(m["m_mw_mawang"]["combat_xp_ref"])
	for other in ["m_jcn_edaotou", "m_jcn_daoren", "m_jcn_yinmian"]:
		assert_true(mw < int(m[other]["combat_xp_ref"]), "馬賊王 %d < %s %d" % [mw, other, int(m[other]["combat_xp_ref"])])
	assert_true(mw >= int(m["m_mw_mazei"]["combat_xp_ref"]), "boss ≥ 嘍囉")
	assert_eq(int(m["m_mw_mawang"]["stats"]["qi"]), 2000, "氣 2000 照 gaoshou/25")
	var q: Dictionary = v1b["quests"]["q_ym_mawang"]
	assert_eq(int(q["requires"][0]["value"]), 15000)
	assert_true(str(q["stages"][0]["log"]).contains("1.5 萬"), "任務文字跟著門檻")
	assert_true(str(q["outcomes"]["default"]["src_note"]).contains("0.08"), "黃甲掉率")
	var rm := str(v1b["text_templates"]["rmr_q_ym_mawang_first"]["self"])
	assert_true(rm.contains("雁門關西邊的馬王洞") and not rm.contains("關外的馬王洞"), "馬王洞在關口西邊，不是關外：" + rm)
	assert_eq(v1b["regions"]["mawang"]["suggested_xp"], [10000, 30000])
	assert_true(int(v1b["regions"]["jingcheng_north"]["suggested_xp"][1]) >= 30000, "北郊空地要兩三萬")

## B#1–#4：京城附近的路線與服務文字跟真的出口一致
func test_capital_directions() -> void:
	var tt: Dictionary = v1b["text_templates"]
	assert_true(str(tt["talk_n_jc_station"]["self"]).contains("送"), "驛站有信要送")
	assert_false(str(tt["talk_n_jc_station"]["self"]).contains("還沒有要往外送的信"))
	var g := str(tt["talk_n_jc_guard"]["self"])
	assert_true(g.contains("武當走嵩山"), g)
	assert_false(g.contains("沒有直路"), g)
	var idx := DataLint.room_index(v1b)
	var ss := str(idx["jcw_songshan"]["room"]["desc"])
	assert_true(ss.contains("從松林往東"), ss)
	assert_false(str(idx["sl_gate"]["room"]["desc"]).contains("嵩山古道"), "少林山門往西是少室山腳")
	var t := str(v1b["quests"]["q_letter_jc_dl"]["text"])
	assert_false(t.contains("華山腳下"), t)
	var path := DataLint.find_path(v1b, "jc_station", "dl_station")
	assert_true(path.has("jcw_songshan") and path.has("sy_pines"), "最短路經嵩山古道、嵩山松林")
	assert_false(path.has("hy_foot"), "不經華山腳下")

## B#10：救柳姑娘的歷練比照 1.0A 一次性大任務
func test_liumei_reward() -> void:
	assert_eq(int(v1b["quests"]["q_jq_liumei"]["outcomes"]["default"]["rewards"]["lilian"]), 100)

## A#9–#12：出處標記
func test_source_tags() -> void:
	var lq := str(v1b["quests"]["q_jc_lingquan"]["src_note"])
	assert_false(lq.contains("預告大意「京城狗乞食」"), "研究沒有預告原文")
	assert_true(lq.contains("題材【設計提案】"), lq)
	var gb: Dictionary = v1b["sects"]["gaibang"]
	assert_eq(gb["harass"][0].get("unless", []), [], "乞討 30 免追是後期 → 預設不免")
	var ranks: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sect_ranks.json"))
	for rid in ["gb_dai4", "gb_dai5", "gb_dai6", "gb_dai7"]:
		var row: Dictionary = {}
		for r in ranks["rows"]:
			if str(r["id"]) == rid:
				row = r
		assert_false(str(row.get("src", "")) == "later", rid + "：2006 的數字不能標成 xkd 的 later")
		assert_true(str(row.get("src_note", "")).contains("後期版數字"), rid)
	assert_eq(str(v1b["npcs"]["n_gb_youqiming"]["name"]), "游啟", "2001-11-03 只寫「游啟」")
	var all: Array = []
	_strings(v1b, "", all)
	for e in all:
		if str(e[1]).contains("游啟明"):
			assert_true(false, "游啟明 still in %s" % e[0])

## A#4、#5、#7、#8、#13：文件
func test_docs() -> void:
	var plan := _doc("res://docs/M3B_PLAN.md")
	assert_false(plan.contains("馬王洞（mawang，1.0A）"), "§3.2 馬王洞 era")
	assert_false(plan.contains("雁門關補完、馬王洞、1.0A 事件"), "§2.2")
	assert_false(plan.contains("| mingjiao_gaochang_yanmen | [20000, 60000] |"), "地區表")
	for w in ["京城半仙", "無敵烙跑鞋", "夜明珠", "柯鎮惡", "三八紅", "武林帖"]:
		assert_true(plan.contains(w), "M3B_PLAN 延後清單有 " + w)
		assert_true(_doc("res://docs/STORY_PLAN.md").contains(w), "STORY_PLAN §1.2 有 " + w)
	var gdd := _doc("res://docs/GDD.md")
	assert_false(gdd.contains("以入口任務或地區的形式"), "GDD 註 1 不再引用騙局文")
	assert_true(str(v1a["regions"]["guiwang"]["src_note"]).contains("馬王洞"), "鬼王留 1.0A 的理由")
