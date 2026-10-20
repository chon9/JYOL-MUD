extends SceneTree
## 平衡模擬（M1_PLAN 6.3）：參考角色 P0–P3 對各怪物自動對打，檢查勝率與傷害區間。
## godot --headless --path . --script res://tools/balance_sim.gd -- --no-steam [--runs=500] [--case=<名稱>] [--dir=res://data] [--seed=1]
## 每案例輸出一行；任一案例不通過 → 結束碼 1。
## 雙方都由 BattleAI 控制（玩家方 melee_basic、10 成、用 arts 中威力最高的已解鎖招式）；非等待模式。

const DataLint := preload("res://tools/data_lint.gd")
const ATTRS_P := { "str": 20, "guts": 19, "wit": 21, "luck": 19, "cal": 19, "agi": 20, "con": 20 }

## 案例：[名稱, 玩家代號, 怪物 id, 檢查（可含 "p_attrs" 覆寫參考角色屬性）]
## win＝VICTORY（含「敵人全部逃走」，那種勝利沒有獎勵）；kill＝怪物真的被打死（才有獎勵）。
const CASES := [
	["newbie_vs_rabbit", "P0", "m_rabbit", { "dmg_min": 8.0, "dmg_max": 16.0, "win_min": 0.95, "kill_min": 0.80 }],
	["newbie_str14_vs_rabbit", "P0", "m_rabbit", { "p_attrs": { "str": 14 }, "kill_min": 0.60 }],
	# 大野兔是大兔皮任務怪，也是長程路線上最常見的怪（審查）：新手要打得贏、打完還剩四成上下的氣，才撐得住連續兩場
	["newbie_vs_bigrabbit", "P0", "m_bigrabbit", { "kill_min": 0.90, "qi_left_min": 0.35 }],
	["newbie_vs_wolf", "P0", "m_wolf", { "win_max": 0.10 }],     # 打不贏 → 野狼不該放在出生點／新手生活點附近
	["newbie_vs_boar", "P0", "m_boar", { "win_max": 0.10 }],     # 同上（山豬）
	["p1_vs_wolf", "P1", "m_wolf", { "win_min": 0.80 }],
	["p1_vs_boar", "P1", "m_boar", { "kill_min": 0.55, "kill_max": 0.80 }],   # P1→P2 的主要練功對象
	["p1_vs_bandit", "P1", "m_bandit", { "win_max": 0.40 }],
	["p2_vs_ghost", "P2", "m_ghost", { "win_min": 0.70, "qi_left_min": 0.25 }],
	["newbie_vs_ghost", "P0", "m_ghost", { "win_max": 0.05 }],
	["p3_vs_guiwang", "P3", "m_guiwang", { "win_min": 0.40, "win_max": 0.90 }],
	# M2_PLAN 4.9：山賊頭目是隊伍級精英（4 個參考新手一起打穩贏、死人中位數 ≤ 1；單打很難贏）；守城官兵新手幾乎必敗
	["party4_vs_bandit_chief", "P0", "m_bandit_chief", { "party": 4, "win_min": 0.80, "deaths_median_max": 1 }],
	["solo_vs_bandit_chief", "P0", "m_bandit_chief", { "win_max": 0.20 }],
	["newbie_vs_city_guard", "P0", "m_city_guard", { "win_max": 0.02 }],
]

## 走路案例（審查：新手走得完長程路線嗎）：[名稱, 起點房間, 終點房間, 檢查]
## P0 沿最短步行路線一間一間走，每間照遇敵表擲骰；打得過的（野兔、大野兔）就打，
## 遇到難纏怪（野狼、山豬、山賊）一開打就往逃跑格跑、站上去就逃，氣低於 30% 也逃。
## 兩場戰鬥之間不回氣（保守；遊戲裡其實會自然回復），走進休息點（城、山門、茶棚、綠洲）才回滿。
## surv_min：走完全程沒死的比例。
const ROUTE_CASES := [
	["p0_walk_letter_xx_dl", "xx_station", "dl_station", { "surv_min": 0.90 }],
	["p0_walk_letter_dl_xx", "dl_station", "xx_station", { "surv_min": 0.90 }],
	["p0_walk_xx_shaolin", "xx_square", "sl_gate", { "surv_min": 0.90 }],
	["p0_walk_dl_huashan", "dl_square", "hs_gate", { "surv_min": 0.90 }],
]
const FLEE_FROM := ["m_wolf", "m_boar", "m_bandit"]
const FLEE_QI_PCT := 0.30

## ---------------------------------------------------------------- M3a（M3A_PLAN 10.2）
## 門派案例的資料來自 WP-SECT 碎片（WP-MERGE 合併後才有）：缺武功／怪物／房間時印 SKIP，不算失敗。
## [門派, 入門兵器武功, 驗收招式]（M3A_PLAN 3.2，綁定）
const SECT_CASES := [
	["wudang", "wd_changquan", "wd_cq_1"],
	["emei", "em_piaoxue", "em_px_1"],
	["hengshan", "hg_jianfa", "hg_jf_1"],
	["quanzhen", "qz_jianfa", "qz_jf_1"],
	["gumu", "gm_yunu_jian", "gm_yn_1"],
	["lingjiu", "lj_zhemei", "lj_zm_1"],
	["xingxiu", "xh_chousui", "xh_cs_1"],
	["xuedao", "xd_daofa", "xd_df_1"],
]
const SECT_PREFIX := { "wudang": "wd", "emei": "em", "hengshan": "hg", "quanzhen": "qz", "gumu": "gm",
	"lingjiu": "lj", "xingxiu": "xh", "xuedao": "xd" }
## 新走路案例：端點房間還沒合併時 SKIP（既有 4 條照舊必須通過）
const M3A_ROUTE_CASES := [
	["p0_walk_dl_emei", "dl_square", "em_gate", { "surv_min": 0.90 }],
	["p0_walk_dl_quanzhen", "dl_square", "qz_gate", { "surv_min": 0.90 }],
	["p0_walk_dl_gumu", "dl_square", "gm_entrance", { "surv_min": 0.90 }],
	["p0_walk_dl_wudang", "dl_square", "wd_gate", { "surv_min": 0.90 }],
	["p0_walk_xx_hengshan", "xx_square", "hg_gate", { "surv_min": 0.90 }],
	["p0_walk_xx_lingjiu", "xx_square", "lj_gate", { "surv_min": 0.90 }],
	["p0_walk_xx_xingxiu", "xx_square", "xh_gate", { "surv_min": 0.90 }],
	["p0_walk_xx_xuedao", "xx_square", "xd_gate", { "surv_min": 0.90 }],
	["p0_walk_dl_shaolin_south", "dl_square", "sl_gate", { "surv_min": 0.90 }],
]
const TONGREN_WAVES := [["m_sl_tongren_1", 6], ["m_sl_tongren_2", 6], ["m_sl_tongren_3", 6]]

## ---------------------------------------------------------------- 故事包（STORY_PLAN §2.3、§3.4；WP-MERGE）
## 新地區走路案例：大理廣場 → 衡山小茶店、西夏廣場 → 雁門關口（新手存活率 ≥ 90%）
const STORY_ROUTE_CASES := [
	["p0_walk_hengshan_s", "dl_square", "hn_teahouse", { "surv_min": 0.90 }],
	["p0_walk_yanmen", "xx_square", "ym_gate", { "surv_min": 0.90 }],
]
## 新怪 1v1（§3.4 級距）：[名稱, 玩家代號, 怪物 id, 檢查]；怪物還沒合併時 SKIP
const STORY_CASES := [
	# 藍鳳凰的五毒（房間動作各打 5 隻；福緣門檻的新手也做得到）
	["newbie_vs_lf_wugong", "P0", "m_lf_wugong", { "kill_min": 0.80 }],
	["newbie_vs_lf_qingshe", "P0", "m_lf_qingshe", { "kill_min": 0.90 }],
	["p1_vs_lf_zhizhu", "P1", "m_lf_zhizhu", { "kill_min": 0.90 }],
	["p1_vs_lf_xiezi", "P1", "m_lf_xiezi", { "win_min": 0.40 }],
	# 行俠仗義的強盜：山賊級距（3000）
	["p1_vs_ym_qiangdao", "P1", "m_ym_qiangdao", { "win_max": 0.40 }],
	["p3_vs_ym_qiangdao", "P3", "m_ym_qiangdao", { "win_min": 0.80 }],
	# 孤鴻子的明教分舵主（6000 級距，要打贏）：兩個 P3 穩贏；單人 P2 打不贏（找隊友、可重打）
	["party2_p3_vs_dl_mingjiao", "P3", "m_dl_mingjiao", { "party": 2, "win_min": 0.80 }],
	["p2_vs_dl_mingjiao", "P2", "m_dl_mingjiao", { "win_max": 0.20 }],
	# 劉二爺（下）魔教教徒 6 隻同場、可逃：單挑一隻 P3 也很難贏
	["p3_vs_hn_mojiao", "P3", "m_hn_mojiao", { "win_max": 0.10 }],
	# 華山內奸勞德諾（30000，要打贏）：高於 P3，四人隊伍穩贏
	["p3_vs_xx_laodenuo", "P3", "m_xx_laodenuo", { "win_max": 0.10 }],
	["party4_p3_vs_xx_laodenuo", "P3", "m_xx_laodenuo", { "party": 4, "win_min": 0.80 }],
	# 設計上要逃的：皇宮守衛（60000）；超強的遊蕩惡人；追擊 NPC 惡人頭子（15000）
	["p3_vs_xx_palace_guard", "P3", "m_xx_palace_guard", { "win_max": 0.02 }],
	["p3_vs_nanhai", "P3", "m_nanhai", { "win_max": 0.02 }],
	["p3_vs_yeerniang", "P3", "m_yeerniang", { "win_max": 0.02 }],
	["p3_vs_amb_etou", "P3", "m_amb_etou", { "win_max": 0.10 }],
]

## ---------------------------------------------------------------- M3b（M3B_PLAN §11.2；整合者）
## 1.0B 的地區與怪物用 1.0A＋1.0B 的資料視圖（陣法同法）。走路案例照既有規則（P0、難纏怪就逃、休息點回滿）。
const M3B_ROUTE_CASES := [
	["walk_jc_gb", "jc_square", "gb_gate", { "surv_min": 0.90 }],
	["walk_jc_jq", "jc_gate_s", "jq_gukou", { "surv_min": 0.90 }],
	["walk_xx_gc", "xx_square", "gc_outside", { "surv_min": 0.90 }],
]

func m3b_cases() -> Array:
	return [
		["gb_xiejiao7", case_gb_xiejiao7],
		["gb_manbing_party3", case_gb_manbing_party3],
		["gb_manbing_solo", case_gb_manbing_solo],
		# M3b 審查 3：二袋只開上限 60 的二階武功 → 蠻兵要三人各 2 萬打得過、兩人打不過（任務文字「邀齊三人」）
		["gb_manbing_duo", func(r: int, s0: int) -> int: return _party_case("gb_manbing_duo", "m_gb_manbing", 1, 20000, 2, { "win_max": 0.10 }, r, s0)],
		["gb_xiaohuang", case_gb_xiaohuang],
		["gc_robot", case_gc_robot],
		["gc_robot_hit", case_gc_robot_hit],
		["gc_robot_party3", case_gc_robot_party3],
		# M3b 審查 3：銅甲機關人（只在第 6 層、一次一隻）三人各 6 萬打得過，兩人打不過
		["gc_tongjia_party3", func(r: int, s0: int) -> int: return _party_case("gc_tongjia_party3", "m_gc_jiguanren2", 1, 60000, 3, { "win_min": 0.60 }, r, s0)],
		["gc_tongjia_duo", func(r: int, s0: int) -> int: return _party_case("gc_tongjia_duo", "m_gc_jiguanren2", 1, 60000, 2, { "win_max": 0.10 }, r, s0)],
		["mw_mawang", case_mw_mawang],
		["mw_boss_ge_minion", case_mw_boss_ge_minion],
		["mw_mawang_tier", case_mw_mawang_tier],
		["q_ym_mawang_party3", case_q_ym_mawang_party3],
		["q_ym_mawang_solo", case_q_ym_mawang_solo],
		# M3b 審查 4：馬賊王照 gaoshou/25「弱、建議 18 級」降到 1.1 萬（低於同一片空地的道人頭子、隱面人）；
		# 任務文字「湊齊三人、各 1.5 萬；兩人得各 2 萬才有勝算」→ 兩人各 1.5 萬打不過、兩人各 2 萬有勝算（審查 4 補測）
		["q_ym_mawang_duo", func(r: int, s0: int) -> int: return _party_case("q_ym_mawang_duo", "m_mw_mawang", 2, 15000, 2, { "win_max": 0.10 }, r, s0)],
		["q_ym_mawang_duo2", func(r: int, s0: int) -> int: return _party_case("q_ym_mawang_duo2", "m_mw_mawang", 2, 20000, 2, { "win_min": 0.40 }, r, s0)],
		# M3b 審查 3：黃罩甲（防 16）不再是刷裝的異常值——1.5 萬穿著打馬賊王仍在建議的 40–90%
		["mw_mawang_huangjia", case_mw_mawang_huangjia],
		# M3b 審查 3：救柳姑娘的鱷魚（任務文字「三人、各六萬」）：三人各 6 萬穩贏、兩人各 6 萬多半打不過
		["q_jq_eyu_party3", func(r: int, s0: int) -> int: return _party_case("q_jq_eyu_party3", "m_jq_eyu", 1, 60000, 3, { "win_min": 0.80 }, r, s0)],
		["q_jq_eyu_duo", func(r: int, s0: int) -> int: return _party_case("q_jq_eyu_duo", "m_jq_eyu", 1, 60000, 2, { "win_max": 0.40 }, r, s0)],
		["cal_1_0a_laodenuo", func(r: int, s0: int) -> int: return _cal_case("cal_1_0a_laodenuo", "m_xx_laodenuo", 20000, r, s0)],
		["cal_1_0a_duyanren", func(r: int, s0: int) -> int: return _cal_case("cal_1_0a_duyanren", "m_cdb_duyanren", 30000, r, s0)],
		["cal_1_0a_yangkang", func(r: int, s0: int) -> int: return _cal_case("cal_1_0a_yangkang", "m_qz_yangkang", 30000, r, s0)],
		["spot_jcn_kongdi", func(r: int, s0: int) -> int: return _spot_case("spot_jcn_kongdi", "jcn_kongdi", 30000, 1, { "win_min": 0.40, "win_max": 0.85 }, r, s0)],
		["spot_jq_qinghua", func(r: int, s0: int) -> int: return _spot_case("spot_jq_qinghua", "jq_qinghua", 30000, 1, { "win_min": 0.40, "win_max": 0.85 }, r, s0)],
		["spot_jq_dilao", func(r: int, s0: int) -> int: return _spot_case("spot_jq_dilao", "jq_dilao2", 60000, 3, { "win_min": 0.80 }, r, s0)],
		["spot_jq_eyuchi", func(r: int, s0: int) -> int: return _spot_case("spot_jq_eyuchi", "jq_eyuchi", 60000, 3, { "win_min": 0.80 }, r, s0)],
		["spot_gc_maze2", func(r: int, s0: int) -> int: return _spot_case("spot_gc_maze2", "gc_maze2", 30000, 3, { "win_min": 0.80 }, r, s0)],
		["spot_gc_maze3", func(r: int, s0: int) -> int: return _spot_case("spot_gc_maze3", "gc_maze3", 30000, 3, { "win_min": 0.80 }, r, s0)],
		["spot_gc_maze4", func(r: int, s0: int) -> int: return _spot_case("spot_gc_maze4", "gc_maze4", 60000, 3, { "win_min": 0.80 }, r, s0)],
		["spot_gc_maze5", func(r: int, s0: int) -> int: return _spot_case("spot_gc_maze5", "gc_maze5", 60000, 3, { "win_min": 0.80 }, r, s0)],
		["spot_gc_maze6", func(r: int, s0: int) -> int: return _spot_case("spot_gc_maze6", "gc_maze6", 60000, 3, { "win_min": 0.60 }, r, s0)],
		["spot_mw_cave1_solo", func(r: int, s0: int) -> int: return _spot_case("spot_mw_cave1_solo", "mw_cave1", 30000, 1, { "win_min": 0.40, "win_max": 0.85 }, r, s0)],
		["spot_mw_cave2_party2", func(r: int, s0: int) -> int: return _spot_case("spot_mw_cave2_party2", "mw_cave2", 20000, 2, { "win_min": 0.75 }, r, s0)],
		["econ_chain", case_econ_chain],
		["m3c_npcpk", case_m3c_npcpk],   # M3c WP-NPCPK（M3C_PLAN §12.2）：子案例見檔尾區塊
	]

func _with_1_0b(f: Callable) -> int:
	var saved := tables
	if _loader != null:
		tables = _loader.activate(["1.0A", "1.0B"])
	var r: int = f.call()
	tables = saved
	return r

## 丐幫參考角色：P 代號為底、太祖長拳 level 級、乞討 qitao 級；over 覆寫（實戰、氣上限、基本武學）
func gb_spec(code: String, level: int, qitao: int, over: Dictionary = {}) -> Dictionary:
	var s := sect_spec(code, "gaibang", "gb_taizu_quan", level)
	s.skills["gb_xinfa"] = level
	s.skills["qitao"] = qitao
	if s.sect_skill is Dictionary and not (s.sect_skill as Dictionary).is_empty():
		s.sect_skill["level"] = qitao
	for k in over:
		if k == "basic":
			for b in ["basic_fist", "basic_inner", "basic_parry", "basic_dodge"]:
				s.skills[b] = int(over[k])
		else:
			s[k] = over[k]
	s.cmd_arts = cmd_arts_of(s.skills)
	return s

## 實戰 3000 的丐幫弟子（一階武功 30）打 7 個邪教門徒（橋上埋伏一場）：勝率 ≥ 70%
func case_gb_xiejiao7(runs: int, seed0: int) -> int:
	return _with_1_0b(func() -> int:
		if not tables.get("monsters", {}).has("m_gb_xiejiao") or not _has_art("gb_taizu_quan"):
			return _skip("gb_xiejiao7", "m_gb_xiejiao／gb_taizu_quan")
		var ps := gb_spec("P2", 30, 30, { "combat_xp": 3000 })
		var mons: Array = []
		for i in 7:
			mons.append("m_gb_xiejiao")
		return run_generic("gb_xiejiao7", { "win_min": 0.70 }, runs, seed0, func(sd: int) -> Dictionary:
			return simulate_multi([ps], mons, [], sd)))

## 三人各實戰 2 萬（參考角色 _p_at：武學上限 ≈ 49、皮甲）打蠻兵：勝率 ≥ 70%
## M3b 審查 3：原本是三人各 6 萬（武學 60），但二袋只開上限 60、前置 50（≈ 實戰 2 萬）的二階武功——門檻比獎勵高三倍
func case_gb_manbing_party3(runs: int, seed0: int) -> int:
	return _party_case("gb_manbing_party3", "m_gb_manbing", 1, 20000, 3, { "win_min": 0.70 }, runs, seed0)

## n 個參考角色（實戰 xp）打 count 隻 mon（1.0B 視圖）
func _party_case(name: String, mon: String, count: int, xp: int, n: int, chk: Dictionary, runs: int, seed0: int) -> int:
	return _with_1_0b(func() -> int:
		if not tables.get("monsters", {}).has(mon):
			return _skip(name, mon)
		var party := _p_party(xp, n)
		var mons: Array = []
		for i in count:
			mons.append(mon)
		return run_generic(name, chk, runs, seed0, func(sd: int) -> Dictionary:
			return simulate_multi(party, mons, [], sd)))

## 實戰 2 萬穿黃罩甲單挑馬賊王：仍在 40–90%（M3b 審查 3：原本防 35，91%；審查 4：馬賊王降到 1.1 萬，參考角色跟著降；M3c 第三輪審查：防 16→7＝O13 換算）
func case_mw_mawang_huangjia(runs: int, seed0: int) -> int:
	return _with_1_0b(func() -> int:
		if not tables.get("monsters", {}).has("m_mw_mawang") or item_row("a_huangjia").is_empty():
			return _skip("mw_mawang_huangjia", "m_mw_mawang／a_huangjia")
		var party := _p_party(20000, 1)
		party[0]["armor_power"] = armor_def("a_huangjia", 7)
		return run_generic("mw_mawang_huangjia", { "win_min": 0.40, "win_max": 0.90 }, runs, seed0, func(sd: int) -> Dictionary:
			return simulate_multi(party, ["m_mw_mawang"], [], sd)))

## 單人實戰 1 萬（P2 底、一階武功 35）打蠻兵：勝率 ≤ 10%
func case_gb_manbing_solo(runs: int, seed0: int) -> int:
	return _with_1_0b(func() -> int:
		if not tables.get("monsters", {}).has("m_gb_manbing"):
			return _skip("gb_manbing_solo", "m_gb_manbing")
		var ps := gb_spec("P2", 35, 30)
		return run_generic("gb_manbing_solo", { "win_max": 0.10 }, runs, seed0, func(sd: int) -> Dictionary:
			return simulate_multi([ps], ["m_gb_manbing"], [], sd)))

## 新丐幫弟子（P0 底、太祖長拳 1、乞討 1）打小黃：勝率 ≥ 95%
func case_gb_xiaohuang(runs: int, seed0: int) -> int:
	return _with_1_0b(func() -> int:
		if not tables.get("monsters", {}).has("m_gb_xiaohuang"):
			return _skip("gb_xiaohuang", "m_gb_xiaohuang")
		var ps := gb_spec("P0", 1, 1)
		return run_generic("gb_xiaohuang", { "win_min": 0.95 }, runs, seed0, func(sd: int) -> Dictionary:
			return simulate_multi([ps], ["m_gb_xiaohuang"], [], sd)))

## 參考角色：P3 底，實戰／武學依建議值放大（3 萬：武學 60、氣 1380；2 萬：武學 50、氣 1180）。
## M3b 審查校準（review 2 #3）：先拿 1.0A 既有打獵怪量 _p_at(x, 上限) 的單人 50% 勝率點（runs=100）：
## 山賊（3000）≈ 8k、明教分舵主（6000）≈ 15k、獨眼仁（12000）≈ 30k、崔叟（20000）≈ 22k、勞德諾（30000）≈ 19k、楊康（40000）≈ 28k
## → combat_xp_ref R 的怪，50% 點落在 0.7R–2.5R（cal_1_0a_* 案例鎖住這個級距）。1.0B 新怪照同一級距調。
func _p_at(xp: int, lv: int) -> Dictionary:
	var ps := player_spec("P3")
	for k in ps.skills.keys():
		ps.skills[k] = lv
	ps.combat_xp = xp
	ps.qi_max = 180 + lv * 20
	ps.qi = ps.qi_max
	ps.effective_inner = lv
	ps.neili_max = lv * 5
	ps.neili = ps.neili_max
	ps.sect_skill = { "id": "foxa", "effect": "DEFENSE", "level": lv }
	return ps

## n 個參考角色（實戰 xp、武學上限）
func _p_party(xp: int, n: int) -> Array:
	var out: Array = []
	for k in n:
		var ps := _p_at(xp, DerivedStats.art_level_cap(xp))
		ps.ref = "sim_at_%d_%d" % [xp, k]
		ps.name = "參考%d" % (k + 1)
		out.append(ps)
	return out

## 1.0A 校準點：參考角色在 xp 實戰單挑既有 1.0A 怪，勝率 25–90%（級距漂了 → 新怪的案例也跟著失準）
func _cal_case(name: String, mon: String, xp: int, runs: int, seed0: int) -> int:
	if not tables.get("monsters", {}).has(mon):
		return _skip(name, mon)
	var party := _p_party(xp, 1)
	return run_generic(name, { "win_min": 0.25, "win_max": 0.90 }, runs, seed0, func(sd: int) -> Dictionary:
		return simulate_multi(party, [mon], [], sd))

## 練功點：照房間的遇敵表（權重、數量）抽一組怪，n 個參考角色（實戰 xp）一起打
func _spot_case(name: String, room_id: String, xp: int, n: int, chk: Dictionary, runs: int, seed0: int) -> int:
	return _with_1_0b(func() -> int:
		var ridx: Dictionary = DataLint.room_index(tables)
		if not ridx.has(room_id):
			return _skip(name, room_id)
		var room: Dictionary = ridx[room_id]["room"]
		var party := _p_party(xp, n)
		return run_generic(name, chk, runs, seed0, func(sd: int) -> Dictionary:
			var rng := RandomNumberGenerator.new()
			rng.seed = sd * 7919 + 13
			return simulate_multi(party, Encounter.pick(room, rng), [], sd)))

## 機關人：每下 200+（鐵心網 FAQ【已證實】）→ 隊伍內容。單人實戰 3 萬幾乎打不過；三人各 3 萬穩贏
func case_gc_robot(runs: int, seed0: int) -> int:
	if not tables.get("monsters", {}).has("m_gc_jiguanren"):
		return _skip("gc_robot", "m_gc_jiguanren")
	var party := _p_party(30000, 1)
	return run_generic("gc_robot", { "win_max": 0.20 }, runs, seed0, func(sd: int) -> Dictionary:
		return simulate_multi(party, ["m_gc_jiguanren"], [], sd))

func case_gc_robot_party3(runs: int, seed0: int) -> int:
	if not tables.get("monsters", {}).has("m_gc_jiguanren"):
		return _skip("gc_robot_party3", "m_gc_jiguanren")
	var party := _p_party(30000, 3)
	return run_generic("gc_robot_party3", { "win_min": 0.85 }, runs, seed0, func(sd: int) -> Dictionary:
		return simulate_multi(party, ["m_gc_jiguanren"], [], sd))

## 機關人打在參考角色身上的平均每下傷害 ≥ 200
func case_gc_robot_hit(runs: int, seed0: int) -> int:
	if not tables.get("monsters", {}).has("m_gc_jiguanren"):
		return _skip("gc_robot_hit", "m_gc_jiguanren")
	var ps: Dictionary = _p_party(30000, 1)[0]
	var tot := 0
	var n := 0
	for i in mini(runs, 100):
		var b := Battle.new(1, seed0 + i, { "wait_mode": false, "escape_tiles": 2 })
		b.add_unit(ps.duplicate(true))
		b.add_unit(Encounter.monster_spec("m_gc_jiguanren", tables))
		b.start(tables)
		while not b.is_over():
			for e in b.step(Battle.TICK, tables):
				var p: Dictionary = e.p
				if int(p.get("atk_uid", 0)) == 2 and p.has("dmg") and not p.get("counter", false) and int(p.dmg) > 0:
					tot += int(p.dmg)
					n += 1
	var avg := tot / float(maxi(1, n))
	var ok := n > 0 and avg >= 200.0
	print("%-24s %s  avg_hit=%6.1f  hits=%d%s" % ["gc_robot_hit", "ok  " if ok else "FAIL", avg, n, "" if ok else "  (平均每下 < 200)"])
	return 1 if ok else 0

## 馬王洞：馬賊王（馬王）單人實戰 2 萬 40–85%（M3b 審查 4：gaoshou/25「弱、18 級」→ 級距 1.1 萬，與熊霸天（10–20 級段）同一檔；建議 1–3 萬的中段）
func case_mw_mawang(runs: int, seed0: int) -> int:
	return _with_1_0b(func() -> int:
		if not tables.get("monsters", {}).has("m_mw_mawang"):
			return _skip("mw_mawang", "m_mw_mawang")
		var party := _p_party(20000, 1)
		return run_generic("mw_mawang", { "win_min": 0.40, "win_max": 0.85 }, runs, seed0, func(sd: int) -> Dictionary:
			return simulate_multi(party, ["m_mw_mawang"], [], sd)))

## boss ≥ 嘍囉：實戰 1.5 萬單挑馬王的勝率不高於單挑一隻馬賊（審查 4：2 萬 → 1.5 萬，跟著級距降）
func case_mw_boss_ge_minion(runs: int, seed0: int) -> int:
	return _with_1_0b(func() -> int:
		if not tables.get("monsters", {}).has("m_mw_mawang") or not tables.get("monsters", {}).has("m_mw_mazei"):
			return _skip("mw_boss_ge_minion", "m_mw_mawang／m_mw_mazei")
		var party := _p_party(15000, 1)
		var wb := 0
		var wm := 0
		for i in runs:
			if str(simulate_multi(party, ["m_mw_mawang"], [], seed0 + i).result) == "VICTORY":
				wb += 1
			if str(simulate_multi(party, ["m_mw_mazei"], [], seed0 + i).result) == "VICTORY":
				wm += 1
		var ok := wb <= wm and wm > 0
		print("%-24s %s  boss_win=%5.1f%%  minion_win=%5.1f%%%s" % ["mw_boss_ge_minion", "ok  " if ok else "FAIL",
			wb * 100.0 / runs, wm * 100.0 / runs, "" if ok else "  (馬王比嘍囉好打)"])
		return 1 if ok else 0)

## M3b 審查 4：gaoshou/25 馬賊王「弱、建議 18 級」，2001-10-13 同一片丐幫左方空地的隱面人「23+」→
## 實戰 2.5 萬單挑：馬賊王的勝率不低於道人頭子、隱面人（級距 1.1 萬 < 1.5 萬 < 2.5 萬，難度順序要跟級距一致）
func case_mw_mawang_tier(runs: int, seed0: int) -> int:
	return _with_1_0b(func() -> int:
		for m in ["m_mw_mawang", "m_jcn_daoren", "m_jcn_yinmian"]:
			if not tables.get("monsters", {}).has(m):
				return _skip("mw_mawang_tier", m)
		var party := _p_party(25000, 1)
		var w := { "m_mw_mawang": 0, "m_jcn_daoren": 0, "m_jcn_yinmian": 0 }
		for m in w:
			for i in runs:
				if str(simulate_multi(party, [m], [], seed0 + i).result) == "VICTORY":
					w[m] += 1
		var ok: bool = w["m_mw_mawang"] >= w["m_jcn_daoren"] and w["m_jcn_daoren"] >= w["m_jcn_yinmian"]
		print("%-24s %s  mawang=%5.1f%%  daoren=%5.1f%%  yinmian=%5.1f%%%s" % ["mw_mawang_tier", "ok  " if ok else "FAIL",
			w["m_mw_mawang"] * 100.0 / runs, w["m_jcn_daoren"] * 100.0 / runs, w["m_jcn_yinmian"] * 100.0 / runs,
			"" if ok else "  (馬賊王比同一片空地的道人頭子／隱面人難打)"])
		return 1 if ok else 0)

## q_ym_mawang 的房間動作戰（洞底 2 隻）：門檻實戰 1.5 萬、要組隊（審查 4：2 萬 → 1.5 萬）
func case_q_ym_mawang_party3(runs: int, seed0: int) -> int:
	return _with_1_0b(func() -> int:
		if not tables.get("monsters", {}).has("m_mw_mawang"):
			return _skip("q_ym_mawang_party3", "m_mw_mawang")
		var party := _p_party(15000, 3)
		return run_generic("q_ym_mawang_party3", { "win_min": 0.80 }, runs, seed0, func(sd: int) -> Dictionary:
			return simulate_multi(party, ["m_mw_mawang", "m_mw_mawang"], [], sd)))

func case_q_ym_mawang_solo(runs: int, seed0: int) -> int:
	return _with_1_0b(func() -> int:
		if not tables.get("monsters", {}).has("m_mw_mawang"):
			return _skip("q_ym_mawang_solo", "m_mw_mawang")
		var party := _p_party(15000, 1)
		return run_generic("q_ym_mawang_solo", { "win_max": 0.10 }, runs, seed0, func(sd: int) -> Dictionary:
			return simulate_multi(party, ["m_mw_mawang", "m_mw_mawang"], [], sd)))

## 生活技能鏈的「每點精換到的銀兩」（收購價 30%），與打獵（獵人：打贏的掉錢＋多剝的皮肉）比。
## 【設計提案】倍率只印報告、不判定：基準與材料取得方式（自己採或買）差很多，0.3–1.5 倍的門檻留給擁有者看數字再定（§11.2）。
## M3b 審查：另判「成品收購價 > 材料收購價」（econ_no_loss；審查 3 起相等也算 FAIL），不成立就 FAIL。
func case_econ_chain(_runs: int, _seed0: int) -> int:
	return _with_1_0b(func() -> int:
		var ls: Dictionary = tables.get("life_skills", {})
		if not ls.has("life_hunting"):
			return _skip("econ_chain", "life_hunting")
		var sellv := func(id: String) -> float:
			var r: Dictionary = tables.get("items", {}).get(id, {})
			return 0.0 if r.is_empty() or bool(r.get("no_sell", false)) else maxf(1.0, floorf(int(r.get("price", 0)) * 0.3))
		# 打獵基準：狩獵區怪物平均掉錢＋獵人額外掉落的收購價，除以每次打獵的精
		var hunt: Dictionary = ls["life_hunting"]
		var mons := ["m_hunt_yetu", "m_hunt_dayetu", "m_hunt_shanzhu", "m_hunt_lang", "m_hunt_xuehu"]
		var tot := 0.0
		var nm := 0
		for mid in mons:
			var m: Dictionary = tables.get("monsters", {}).get(mid, {})
			if m.is_empty():
				continue
			nm += 1
			var money: Variant = m.get("money", {})
			if money is Dictionary and not (money as Dictionary).is_empty():
				tot += (int(money.get("min", 0)) + int(money.get("max", 0))) / 2.0
			for d in m.get("drops", []):
				tot += float(d.get("chance", 0)) * (int(d.get("min", 1)) + int(d.get("max", 1))) / 2.0 * sellv.call(str(d.get("item", "")))
			for d in (hunt.get("hunt", {}) as Dictionary).get("drops", []):
				var ms: Array = d.get("monsters", [])
				if ms.is_empty() or mid in ms:
					var n: Array = d.get("n", [1, 1])
					tot += float(d.get("chance", 0)) * (int(n[0]) + int(n[-1])) / 2.0 * sellv.call(str(d.get("item", "")))
		var base := (tot / maxf(1.0, nm)) / maxf(1.0, float(hunt.get("jing_cost", 10)))
		var lines: PackedStringArray = []
		var outliers: PackedStringArray = []
		var losers: PackedStringArray = []
		for sid in ls:
			var row: Dictionary = ls[sid]
			var jc := maxf(1.0, float(row.get("jing_cost", 5)))
			var y: Variant = row.get("yield", [])
			if y is Array and not (y as Array).is_empty():
				var v := 0.0
				for e in y:
					var n2: Array = e.get("n", [1, 1])
					v += float(e.get("chance", 1)) * (int(n2[0]) + int(n2[-1])) / 2.0 * float(sellv.call(str(e.get("item", ""))))
				var ratio := v / jc / maxf(0.01, base)
				lines.append("%s採集 %.2f" % [str(row.get("name", sid)), ratio])
				if ratio < 0.3 or ratio > 1.5:
					outliers.append("%s採集 %.2f" % [str(row.get("name", sid)), ratio])
			for rc in row.get("recipes", []):
				var out_v := float(sellv.call(str(rc.get("output", {}).get("item", "")))) * int(rc.get("output", {}).get("n", 1))
				var in_v := 0.0
				for inp in rc.get("inputs", []):
					in_v += float(sellv.call(str(inp.get("item", "")))) * int(inp.get("n", 1))
				var jr := maxf(1.0, float(rc.get("jing_cost", row.get("jing_cost", 5))))
				var ratio2 := (out_v - in_v) / jr / maxf(0.01, base)
				# M3b 審查：成品的收購價不能低於材料（賣成品不如賣材料 → 配方沒有意義）
				# M3b 審查 3：相等也不行（白飯、淘洗礦砂、粗布道袍曾經剛好打平 → 做了等於白做）
				if out_v <= in_v:
					losers.append("%s %d<%d" % [str(rc.get("name", rc.get("id", ""))), int(out_v), int(in_v)])
				if ratio2 < 0.3 or ratio2 > 1.5:
					outliers.append("%s %.2f" % [str(rc.get("name", rc.get("id", ""))), ratio2])
		# M3c2 審查 #6：超出 0.3–1.5 倍的配方／採集原本只報告，改成不通過
		print("%-24s %s  打獵基準 %.2f 兩／精；採集 [%s]；超出 0.3–1.5 倍的配方 %d 條%s" % ["econ_chain",
			"ok  " if outliers.is_empty() else "FAIL", base, ", ".join(lines), outliers.size(),
			"" if outliers.is_empty() else "：" + ", ".join(outliers.slice(0, 12)) + (" …" if outliers.size() > 12 else "")])
		print("%-24s %s  成品收購價不高於材料的配方 %d 條%s" % ["econ_no_loss", "ok  " if losers.is_empty() else "FAIL", losers.size(),
			"" if losers.is_empty() else "：" + ", ".join(losers)])
		return 1 if losers.is_empty() and outliers.is_empty() else 0)

var tables: Dictionary = {}
var _loader: DataLoader = null   # 需要別的 era 視圖的案例用（陣法屬 1.0B）
var skipped := 0

func _initialize() -> void:
	var runs := 500
	var only := ""
	var dir := "res://data"
	var seed0 := 1
	for a in OS.get_cmdline_user_args():
		if a == "--pace-trace":
			pace_trace = true
		# 調校用（不改資料）：--pace-rules=novice_learn_pct:3000,novice_jing_pct:10 ；--pace-spar=實戰,參考實戰,學點
		if a.begins_with("--pace-rules="):
			for kv in a.substr(13).split(","):
				var kvs := kv.split(":")
				if kvs.size() == 2:
					pace_rule_over[kvs[0]] = int(kvs[1]) if kvs[1].is_valid_int() else (kvs[1] == "true")
		if a.begins_with("--pace-spar="):
			pace_spar_over = Array(a.substr(12).split(",")).map(func(x): return int(x))
		if a.begins_with("--group="):
			group_mons = Array(a.substr(8).split(","))
		if a.begins_with("--runs="):
			runs = maxi(1, int(a.substr(7)))
		elif a.begins_with("--case="):
			only = a.substr(7)
		elif a.begins_with("--dir="):
			dir = a.substr(6)
		elif a.begins_with("--seed="):
			seed0 = int(a.substr(7))
	var loader := DataLoader.new()
	loader.load_all(dir)
	_loader = loader
	tables = loader.activate(["1.0A"])
	for e in loader.errors:
		print("WARN data: " + e)
	var failed := 0
	var ran := 0
	for c in CASES:
		if only != "" and c[0] != only:
			continue
		ran += 1
		if not run_case(c, runs, seed0):
			failed += 1
	for c in ROUTE_CASES:
		if only != "" and c[0] != only:
			continue
		ran += 1
		if not run_route_case(c, runs, seed0):
			failed += 1
	# M3a：門派、陣法、毒、十八銅人、古墓迷宮、新走路案例
	for c in m3a_cases():
		if only != "" and c[0] != only:
			continue
		var r: int = c[1].call(runs, seed0)
		if r < 0:
			skipped += 1
			continue
		ran += 1
		if r == 0:
			failed += 1
	var ridx: Dictionary = DataLint.room_index(tables)
	for c in M3A_ROUTE_CASES:
		if only != "" and c[0] != only:
			continue
		if not ridx.has(c[1]) or not ridx.has(c[2]):
			print("%-24s SKIP  %s 或 %s 還沒合併" % [c[0], c[1], c[2]])
			skipped += 1
			continue
		ran += 1
		if not run_route_case(c, runs, seed0):
			failed += 1
	# 故事包（STORY_PLAN §2.3、§3.4）
	for c in STORY_ROUTE_CASES:
		if only != "" and c[0] != only:
			continue
		if not ridx.has(c[1]) or not ridx.has(c[2]):
			print("%-24s SKIP  %s 或 %s 還沒合併" % [c[0], c[1], c[2]])
			skipped += 1
			continue
		ran += 1
		if not run_route_case(c, runs, seed0):
			failed += 1
	for c in STORY_CASES:
		if only != "" and c[0] != only:
			continue
		if not tables.get("monsters", {}).has(c[2]):
			print("%-24s SKIP  %s 還沒合併" % [c[0], c[2]])
			skipped += 1
			continue
		ran += 1
		if not run_case(c, runs, seed0):
			failed += 1
	# M3b（M3B_PLAN §11.2）
	var saved_t := tables
	tables = _loader.activate(["1.0A", "1.0B"])
	var ridx_b: Dictionary = DataLint.room_index(tables)
	for c in M3B_ROUTE_CASES:
		if only != "" and c[0] != only:
			continue
		if not ridx_b.has(c[1]) or not ridx_b.has(c[2]):
			print("%-24s SKIP  %s 或 %s 還沒合併" % [c[0], c[1], c[2]])
			skipped += 1
			continue
		ran += 1
		if not run_route_case(c, runs, seed0):
			failed += 1
	tables = saved_t
	for c in m3b_cases():
		if only != "" and c[0] != only:
			continue
		var r3: int = c[1].call(runs, seed0)
		if r3 < 0:
			skipped += 1
			continue
		ran += 1
		if r3 == 0:
			failed += 1
	# M3c WP-LOOT（M3C_PLAN §12.2）：1.0A 視圖
	for c in loot_cases():
		if only != "" and c[0] != only:
			continue
		var r4: int = c[1].call(runs, seed0)
		if r4 < 0:
			skipped += 1
			continue
		ran += 1
		if r4 == 0:
			failed += 1
	# M3c2 WP-PACE（M3C2_PLAN §2.6、§3.3）：1.0A 視圖（丐幫案例自己換視圖）
	for c in pace_cases():
		if only != "" and c[0] != only:
			continue
		var r5: int = c[1].call(runs, seed0)
		if r5 < 0:
			skipped += 1
			continue
		ran += 1
		if r5 == 0:
			failed += 1
	# M3c2 WP-ECON（M3C2_PLAN §4；econ2_cases 在檔尾 WP-ECON 區塊）
	for c in econ2_cases():
		if only != "" and c[0] != only:
			continue
		var r6: int = c[1].call(runs, seed0)
		if r6 < 0:
			skipped += 1
			continue
		ran += 1
		if r6 == 0:
			failed += 1
	if skipped > 0:
		print("BALANCE note: %d 個 M3a／故事包案例因資料尚未合併而略過（SKIP）" % skipped)
	print("BALANCE %s (%d cases, %d failed, runs=%d)" % ["OK" if failed == 0 and ran > 0 else "FAIL", ran, failed, runs])
	quit(0 if failed == 0 and ran > 0 else 1)

func run_case(c: Array, runs: int, seed0: int) -> bool:
	var name: String = c[0]
	var chk: Dictionary = c[3]
	var pspec := player_spec(c[1])
	var p_attrs: Dictionary = chk.get("p_attrs", {})
	for k in p_attrs:
		pspec.attrs[k] = p_attrs[k]
	var mspec := Encounter.monster_spec(c[2], tables)
	if mspec.is_empty():
		print("%-24s FAIL  怪物 %s 不存在" % [name, c[2]])
		return false
	var wins := 0
	var kills := 0
	var actions := 0
	var dmg_sum := 0
	var dmg_n := 0
	var qi_left := 0.0
	var aborted := 0
	var n_players := maxi(1, int(chk.get("party", 1)))
	var deaths: Array = []
	for i in runs:
		var r := simulate(pspec, mspec, seed0 + i, n_players)
		deaths.append(int(r.deaths))
		if r.result == "VICTORY":
			wins += 1
			qi_left += r.qi_pct
			if r.killed:
				kills += 1
		elif r.result == "ABORTED":
			aborted += 1
		actions += r.actions
		dmg_sum += r.dmg_sum
		dmg_n += r.dmg_n
	var win_rate := wins / float(runs)
	var kill_rate := kills / float(runs)
	var avg_dmg := dmg_sum / float(dmg_n) if dmg_n > 0 else 0.0
	var avg_qi := qi_left / float(wins) if wins > 0 else 0.0
	var why: PackedStringArray = []
	if chk.has("kill_min") and kill_rate < chk.kill_min:
		why.append("擊殺率 < %.0f%%" % (chk.kill_min * 100))
	if chk.has("kill_max") and kill_rate > chk.kill_max:
		why.append("擊殺率 > %.0f%%" % (chk.kill_max * 100))
	if chk.has("win_min") and win_rate < chk.win_min:
		why.append("勝率 < %.0f%%" % (chk.win_min * 100))
	if chk.has("win_max") and win_rate > chk.win_max:
		why.append("勝率 > %.0f%%" % (chk.win_max * 100))
	if chk.has("rounds_min") and actions / float(runs) < float(chk.rounds_min):
		why.append("平均行動數 < %.1f（比參考線快太多）" % float(chk.rounds_min))
	if chk.has("dmg_min") and avg_dmg < chk.dmg_min:
		why.append("平均傷害 < %.0f" % chk.dmg_min)
	if chk.has("dmg_max") and avg_dmg > chk.dmg_max:
		why.append("平均傷害 > %.0f" % chk.dmg_max)
	if chk.has("qi_left_min") and avg_qi < chk.qi_left_min:
		why.append("勝場剩餘氣 < %.0f%%" % (chk.qi_left_min * 100))
	deaths.sort()
	var deaths_median: int = deaths[deaths.size() / 2]
	if chk.has("deaths_median_max") and deaths_median > int(chk.deaths_median_max):
		why.append("死亡人數中位數 > %d" % int(chk.deaths_median_max))
	var ok := why.is_empty()
	var party_note := "  party=%d deaths_median=%d" % [n_players, deaths_median] if n_players > 1 else ""
	print("%-24s %s  win=%5.1f%%  kill=%5.1f%%  rounds=%5.1f  dmg=%6.1f  qi_left=%5.1f%%  aborted=%d%s%s" % [name, "ok  " if ok else "FAIL",
		win_rate * 100.0, kill_rate * 100.0, actions / float(runs), avg_dmg, avg_qi * 100.0, aborted, party_note,
		"" if ok else "  (" + "；".join(why) + ")"])
	return ok

## n_players > 1：同一個參考角色 n 份一起打（隊伍案例）；統計只看第一位（uid 1）的傷害與剩餘氣，deaths＝玩家方死亡人數
func simulate(pspec: Dictionary, mspec: Dictionary, s: int, n_players: int = 1) -> Dictionary:
	var b := Battle.new(1, s, { "wait_mode": false, "escape_tiles": 2 })
	for k in n_players:
		var ps := pspec.duplicate(true)
		if k > 0:
			ps.ref = "%s_%d" % [str(pspec.ref), k + 1]
			ps.name = "%s%d" % [str(pspec.name), k + 1]
		b.add_unit(ps)
	b.add_unit(mspec)
	var mon_uid := n_players + 1
	var dmg_sum := 0
	var dmg_n := 0
	b.start(tables)
	while not b.is_over():
		for e in b.step(Battle.TICK, tables):
			var p: Dictionary = e.p
			if p.get("atk_uid", 0) == 1 and p.has("dmg") and not p.get("counter", false):
				dmg_sum += int(p.dmg)
				dmg_n += 1
	var me: BattleUnit = b.unit(1)
	var deaths := 0
	for u in b.units:
		if u.side == 0 and u.is_dead():
			deaths += 1
	return { "result": b.result_name(), "killed": b.unit(mon_uid).is_dead(), "actions": me.actions, "dmg_sum": dmg_sum, "dmg_n": dmg_n,
		"qi_pct": me.qi / float(me.qi_max()), "deaths": deaths }

## ---------------------------------------------------------------- 走路案例

func run_route_case(c: Array, runs: int, seed0: int) -> bool:
	var name: String = c[0]
	var chk: Dictionary = c[3]
	var path: Array = DataLint.find_path(tables, c[1], c[2])
	if path.is_empty():
		print("%-24s FAIL  %s -> %s 走不到" % [name, c[1], c[2]])
		return false
	var idx: Dictionary = DataLint.room_index(tables)
	var survived := 0
	var fights := 0
	var fled := 0
	var flee_tries := 0
	var deaths_by := {}
	for i in runs:
		var r := walk_route(path, idx, seed0 + i * 7919)
		fights += int(r.fights)
		fled += int(r.fled)
		flee_tries += int(r.flee_tries)
		if r.dead:
			deaths_by[r.killer] = int(deaths_by.get(r.killer, 0)) + 1
		else:
			survived += 1
	var surv := survived / float(runs)
	var ok := surv >= float(chk.get("surv_min", 0.9))
	var killers: PackedStringArray = []
	for k in deaths_by:
		killers.append("%s×%d" % [k, deaths_by[k]])
	print("%-24s %s  surv=%5.1f%%  steps=%d  fights=%4.2f  flee_ok=%5.1f%%  deaths=[%s]%s" % [name, "ok  " if ok else "FAIL",
		surv * 100.0, path.size() - 1, fights / float(runs), (100.0 * fled / float(flee_tries)) if flee_tries > 0 else 100.0,
		", ".join(killers), "" if ok else "  (存活率 < %.0f%%)" % (float(chk.get("surv_min", 0.9)) * 100)])
	return ok

func walk_route(path: Array, idx: Dictionary, s: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var pspec := player_spec("P0")
	var qi_max := int(pspec.qi_max)
	var qi := qi_max
	var out := { "dead": false, "killer": "", "fights": 0, "fled": 0, "flee_tries": 0 }
	for i in range(1, path.size()):
		var rid: String = path[i]
		if DataLint.is_rest_room(tables, idx, rid):
			qi = qi_max
			continue
		var mons := Encounter.roll(idx[rid]["room"], rng)
		if mons.is_empty():
			continue
		out.fights += 1
		var spec := pspec.duplicate(true)
		spec.qi = qi
		var r := fight_newbie(spec, Encounter.monster_specs(mons, tables), rng.randi())
		if r.tried_flee:
			out.flee_tries += 1
			if r.result != "DEFEAT":
				out.fled += 1
		if r.result == "DEFEAT":
			out.dead = true
			out.killer = "%s@%s" % [mons[0], rid]
			return out
		qi = maxi(1, int(r.qi))
	return out

## 玩家是真人單位（等待模式），由 newbie_cmd 下令；怪物照 BattleAI。
func fight_newbie(pspec: Dictionary, mspecs: Array, s: int) -> Dictionary:
	pspec.erase("ai")
	pspec.peer = 1
	var b := Battle.new(1, s, { "wait_mode": true, "escape_tiles": 2 })
	b.add_unit(pspec)
	for m in mspecs:
		b.add_unit(m)
	b.start(tables)
	var me: BattleUnit = b.unit(1)
	var st := { "tried_flee": false }
	while not b.is_over():
		b.step(Battle.TICK, tables)
		if b.state == Battle.State.AWAIT_COMMAND and me in b.waiting_humans():
			var cmd := newbie_cmd(b, me, st)
			if b.submit(1, cmd, tables) != "":
				b.submit(1, { "cmd": "DEFEND" }, tables)
	return { "result": b.result_name(), "qi": me.qi, "tried_flee": st.tried_flee }

func newbie_cmd(b: Battle, me: BattleUnit, st: Dictionary) -> Dictionary:
	var enemies: Array = b.units.filter(func(e): return e.side != me.side and e.is_active())
	var scary := false
	for e in enemies:
		if str(e.spec.get("ref", "")) in FLEE_FROM:
			scary = true
	var flee := scary or me.qi < FLEE_QI_PCT * me.qi_max()
	if flee and not b.grid.escape.is_empty():
		st.tried_flee = true
		if b.grid.is_escape(me.pos):
			return { "cmd": "FLEE" }
		var goals: Array[Vector2i] = []
		goals.assign(b.grid.escape)
		var dest := BattleAI._best_cell_toward(b, me, goals)
		if dest != Vector2i(-1, -1):
			return { "cmd": "MOVE", "target": [dest.x, dest.y] }
	var adj: Array = enemies.filter(func(e): return BattleGrid.manhattan(me.pos, e.pos) == 1)
	if not adj.is_empty():
		adj.sort_custom(func(a, c): return a.qi < c.qi)
		return { "cmd": "ATTACK", "target": [adj[0].pos.x, adj[0].pos.y] }
	if flee:
		return { "cmd": "DEFEND" }
	var goals2: Array[Vector2i] = []
	for e in enemies:
		goals2.append(e.pos)
	var d2 := BattleAI._best_cell_toward(b, me, goals2)
	if d2 != Vector2i(-1, -1):
		return { "cmd": "MOVE", "target": [d2.x, d2.y] }
	return { "cmd": "DEFEND" }

## ---------------------------------------------------------------- 參考角色（6.3）

func item_row(id: String) -> Dictionary:
	return tables.get("items", {}).get(id, {})

func weapon_of(item_id: String, uid: String) -> Dictionary:
	if item_id == "":
		return { "uid": "", "item_id": "", "weapon_type": "FIST", "atk": 0, "name": "" }
	var r := item_row(item_id)
	return { "uid": uid, "item_id": item_id, "weapon_type": str(r.get("weapon_type", "BLADE")),
		"atk": int(r.get("atk", 4)), "name": str(r.get("name", item_id)) }

func armor_def(item_id: String, fallback: int) -> int:
	var r := item_row(item_id)
	return int(r.get("def", fallback)) if not r.is_empty() else fallback

func player_spec(code: String) -> Dictionary:
	var attrs := ATTRS_P.duplicate()
	var skills := {}
	var weapon := weapon_of("", "")
	var armor := 0
	var xp := 0
	var qi_max := 180
	var sect_skill := {}
	var lightness := 0
	match code:
		"P0":
			weapon = weapon_of("w_mudao", "it_sim1")
			armor = armor_def("a_bupao", 2)
		"P1":
			skills = { "foxa": 10, "sl_changquan": 10, "basic_fist": 10, "basic_inner": 5, "basic_parry": 5, "basic_dodge": 5 }
			armor = armor_def("a_bupao", 2)
			xp = 500
			qi_max = 180 + 10 * 8
		"P2":
			skills = { "foxa": 30, "sl_changquan": 35, "basic_fist": 35, "basic_inner": 30, "basic_parry": 30,
				"basic_dodge": 30, "sl_shenfa": 20, "basic_body": 20 }
			armor = armor_def("a_cubudaopao", 4)
			attrs.wit += 2   # 粗布道袍 悟性 +2
			xp = 10000
			qi_max = 180 + 60 * 8
			lightness = 20
		"P3":
			skills = { "foxa": 40, "sl_changquan": 40, "basic_fist": 40, "basic_inner": 40, "basic_parry": 40,
				"basic_dodge": 40, "sl_shenfa": 40, "basic_body": 40 }
			armor = armor_def("a_pijia", 8)
			xp = 15000
			qi_max = 180 + 100 * 8
			lightness = 40
	if skills.has("foxa"):
		sect_skill = { "id": "foxa", "effect": "DEFENSE", "level": skills.foxa }
	var inner := int(skills.get("basic_inner", 0))
	var neili_max := inner * 5
	var jing_max := 50 + int(attrs.wit) * 2 + (inner / 10) * 8
	var shen_max := 50 + int(attrs.cal) * 2
	var arts: Array = []
	if skills.has("sl_changquan"):
		arts.append("sl_changquan")
	return {
		"kind": "PLAYER", "ref": "sim_" + code, "name": "模擬" + code, "side": 0, "peer": 0, "ai": "melee_basic",
		"attrs": attrs, "qi": qi_max, "qi_max": qi_max, "neili": neili_max, "neili_max": neili_max,
		"jing": jing_max, "jing_max": jing_max, "shen": shen_max, "shen_max": shen_max,
		"skills": skills, "arts": arts, "weapon": weapon, "weapon_options": [weapon] if weapon.uid != "" else [],
		"armor_power": armor, "effective_inner": inner, "lightness": lightness, "sect_skill": sect_skill,
		"killing_intent": 0, "carry_ratio": 0.1, "monster_row": "", "combat_xp": xp,
	}

## ---------------------------------------------------------------- M3a 案例（M3A_PLAN 10.2）

## [[名稱, Callable(runs, seed0) -> int]]：1 通過、0 失敗、-1 資料還沒合併（SKIP）
func m3a_cases() -> Array:
	var out: Array = []
	for sc in SECT_CASES:
		var sid: String = sc[0]
		var art: String = sc[1]
		var p: String = SECT_PREFIX[sid]
		var n1 := "p1_sect_" + sid
		# 整合（M3A_PLAN 12）：計畫原寫 0.70–0.98，但參考線少林長拳 20 級本身就是 100%，「與少林長拳同級」改成
		# 勝率 ≥ 0.70 且平均行動數 ≥ 參考線 × 0.55（不比少林長拳快一倍以上 → 沒有哪一派過強）
		out.append([n1, func(runs: int, s0: int) -> int:
			return case_sect_vs(n1, sid, art, "P1", 20, "m_wolf",
				{ "win_min": 0.70, "rounds_min": ref_cq20_rounds(runs, s0) * 0.55 }, runs, s0)])
		# 整合：計畫原寫 ≥ 0.90，但範本華山弟子（P0 華山劍法 5 級）只有 ~54%；切磋輸了不會死、驗收 bot 勝敗都算過，
		# 改成「與華山弟子同級」：0.35–0.85
		var n2 := "p0_vs_%s_dizi" % sid
		out.append([n2, func(runs: int, s0: int) -> int:
			return case_sect_vs(n2, sid, art, "P0", 5, "m_%s_dizi" % p, { "win_min": 0.35, "win_max": 0.85 }, runs, s0)])
		var n3 := "newbie_vs_%s_guard" % sid
		out.append([n3, func(runs: int, s0: int) -> int:
			var g := "m_%s_guard" % p
			if not tables.get("monsters", {}).has(g):
				return _skip(n3, "怪物 " + g)
			return run_generic(n3, { "win_max": 0.05 }, runs, s0, func(sd: int) -> Dictionary:
				return simulate_multi([player_spec("P0")], [g], [], sd))])
	# M3a 審查 B4：範圍招式在一對多時的優勢。P1 入門兵器武功 20 級打一群怪（預設 3 隻大野兔；偵察常遇到成群的怪），
	# 平均行動數不得少於少林長拳 20 級（單體）同一場面的 0.55 倍
	for sc in SECT_CASES:
		var gsid: String = sc[0]
		var gart: String = sc[1]
		var gn := "p1_sect_%s_vs_group" % gsid
		out.append([gn, func(runs: int, s0: int) -> int:
			if not _has_art(gart):
				return _skip(gn, "武功 " + gart)
			var gps := sect_spec("P1", gsid, gart, 20)
			return run_generic(gn, { "rounds_min": ref_cq20_group_rounds(runs, s0) * 0.55 }, runs, s0, func(sd: int) -> Dictionary:
				return simulate_multi([gps], group_mons, [], sd))])
	out.append(["ref_p1_shaolin_cq20_vs_group", func(runs: int, s0: int) -> int:
		var rps := sect_spec("P1", "shaolin", "sl_changquan", 20)
		return run_generic("ref_p1_shaolin_cq20_vs_group", {}, runs, s0, func(sd: int) -> Dictionary:
			return simulate_multi([rps], group_mons, [], sd))])
	# 參考線（只印數字、不判定）：同一套模擬下少林長拳 20 級打野狼、P0 華山劍法 5 級打華山弟子（切磋怪的範本）
	out.append(["ref_p1_shaolin_cq20", func(runs: int, s0: int) -> int:
		var ps := sect_spec("P1", "shaolin", "sl_changquan", 20)
		return run_generic("ref_p1_shaolin_cq20", {}, runs, s0, func(sd: int) -> Dictionary:
			return simulate_multi([ps], ["m_wolf"], [], sd))])
	out.append(["ref_p0_vs_hs_trainee", func(runs: int, s0: int) -> int:
		if not tables.get("monsters", {}).has("m_hs_trainee"):
			return _skip("ref_p0_vs_hs_trainee", "怪物 m_hs_trainee")
		var ps := sect_spec("P0", "huashan", "hs_jianfa", 5)
		return run_generic("ref_p0_vs_hs_trainee", {}, runs, s0, func(sd: int) -> Dictionary:
			return simulate_multi([ps], ["m_hs_trainee"], [], sd))])
	out.append(["party3_vs_tongren", case_tongren])
	out.append(["formation3_bonus", case_formation])
	out.append(["poison_p1_vs_wolf", case_poison])
	out.append(["gumu_maze_p3", case_gumu_maze])
	return out

var _ref_rounds := -1.0
var _ref_group_rounds := -1.0
var group_mons: Array = ["m_bigrabbit", "m_bigrabbit", "m_bigrabbit"]   # --group=m_a,m_b 可換（3 隻野狼 P1 全輸，看不出差別）

## 少林長拳 20 級 P1 打一群怪（預設 3 隻大野兔）的平均行動數（p1_sect_*_vs_group 的速度下限參考）
func ref_cq20_group_rounds(runs: int, s0: int) -> float:
	if _ref_group_rounds < 0.0:
		var ps := sect_spec("P1", "shaolin", "sl_changquan", 20)
		var acts := 0
		for i in runs:
			acts += int(simulate_multi([ps], group_mons, [], s0 + i).actions)
		_ref_group_rounds = acts / float(maxi(1, runs))
	return _ref_group_rounds

## 少林長拳 20 級 P1 打野狼的平均行動數（p1_sect_* 的速度下限參考；同一組種子只算一次）
func ref_cq20_rounds(runs: int, s0: int) -> float:
	if _ref_rounds < 0.0:
		var ps := sect_spec("P1", "shaolin", "sl_changquan", 20)
		var acts := 0
		for i in runs:
			acts += int(simulate_multi([ps], ["m_wolf"], [], s0 + i).actions)
		_ref_rounds = acts / float(maxi(1, runs))
	return _ref_rounds

func _skip(name: String, what: String) -> int:
	print("%-24s SKIP  %s 還沒合併" % [name, what])
	return -1

func _has_art(id: String) -> bool:
	return tables.get("martial_arts", {}).has(id)

## 門派參考角色：以 P0／P1 為底，換成該派的入門兵器武功（等級 level）、對應基本武學、門派技能與兵器
func sect_spec(code: String, sect_id: String, art_id: String, level: int) -> Dictionary:
	var s := player_spec(code)
	var arow: Dictionary = tables.get("martial_arts", {}).get(art_id, {})
	var srow: Dictionary = tables.get("sects", {}).get(sect_id, {})
	var sk: Dictionary = (s.skills as Dictionary).duplicate()
	var base_lv := int(sk.get("basic_fist", 0))
	sk.erase("foxa")
	sk.erase("sl_changquan")
	sk.erase("basic_fist")
	var cat := str(arow.get("category", "FIST"))
	var basic := str(arow.get("base_skill", BattleFormulas.basic_for_category(cat)))
	if base_lv > 0:
		sk[basic] = base_lv
	sk[art_id] = level
	var ss_id := str(srow.get("sect_skill", ""))
	var ss_lv := 1 if code == "P0" else 10
	var ss := {}
	if ss_id != "":
		sk[ss_id] = ss_lv
		var eff: Variant = srow.get("sect_skill_effect", {})
		ss = { "id": ss_id, "effect": str(eff.get("effect", "")) if eff is Dictionary else str(eff), "level": ss_lv,
			"name": str(srow.get("sect_skill_name", ss_id)) }
	s.skills = sk
	s.arts = [art_id] if BattleFormulas.BATTLE_CATEGORIES.has(cat) else []
	s.sect = sect_id
	s.sect_skill = ss
	var g: Array = srow.get("gender", ["M"])
	s.gender = str(g[0]) if not g.is_empty() else "M"
	var w := weapon_for(cat)
	s.weapon = w
	s.weapon_options = [w] if str(w.uid) != "" else []
	s.cmd_arts = cmd_arts_of(sk)
	return s

## 該類別最便宜的兵器（拳腳 → 空手）
func weapon_for(cat: String) -> Dictionary:
	if cat == "FIST":
		return weapon_of("", "")
	var best := ""
	var price := 1 << 30
	var ids: Array = tables.get("items", {}).keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = tables.items[id]
		if str(r.get("weapon_type", "")) == cat and int(r.get("price", 0)) < price:
			best = str(id)
			price = int(r.get("price", 0))
	return weapon_of(best, "it_sim1") if best != "" else weapon_of("", "")

## spec.cmd_arts（M3A_PLAN 3.11）：依武功類別分類；ACUPOINT = acupoint:true
func cmd_arts_of(sk: Dictionary) -> Dictionary:
	var out := { "POISON": [], "MEDIC": [], "HIDDEN": [], "FORMATION": [], "INNER": [], "ACUPOINT": [] }
	var arts_t: Dictionary = tables.get("martial_arts", {})
	var ids: Array = sk.keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = arts_t.get(id, {})
		if r.is_empty() or int(sk[id]) < 1:
			continue
		var cat := str(r.get("category", ""))
		if out.has(cat):
			(out[cat] as Array).append(str(id))
		if bool(r.get("acupoint", false)):
			(out.ACUPOINT as Array).append(str(id))
	return out

func case_sect_vs(name: String, sect_id: String, art_id: String, code: String, level: int, mon: String, chk: Dictionary,
		runs: int, seed0: int) -> int:
	if not _has_art(art_id):
		return _skip(name, "武功 " + art_id)
	if not tables.get("monsters", {}).has(mon):
		return _skip(name, "怪物 " + mon)
	var ps := sect_spec(code, sect_id, art_id, level)
	return run_generic(name, chk, runs, seed0, func(sd: int) -> Dictionary:
		return simulate_multi([ps], [mon], [], sd))

func _tongren_waves() -> Array:
	var out: Array = []
	for w in TONGREN_WAVES:
		var ids: Array = []
		for i in int(w[1]):
			ids.append(str(w[0]))
		out.append(ids)
	return out

func _tongren_ready(name: String) -> bool:
	for w in TONGREN_WAVES:
		if not tables.get("monsters", {}).has(str(w[0])):
			_skip(name, "怪物 " + str(w[0]))
			return false
	return true

func _p3_party(n: int, over: Dictionary = {}) -> Array:
	var out: Array = []
	for k in n:
		var ps := player_spec("P3")
		ps.ref = "sim_P3_%d" % (k + 1)
		ps.name = "模擬P3_%d" % (k + 1)
		for key in over:
			ps[key] = over[key]
		out.append(ps)
	return out

func case_tongren(runs: int, seed0: int) -> int:
	if not _tongren_ready("party3_vs_tongren"):
		return -1
	var waves := _tongren_waves()
	var party := _p3_party(3)
	return run_generic("party3_vs_tongren", { "win_min": 0.40, "win_max": 0.85 }, runs, seed0, func(sd: int) -> Dictionary:
		return simulate_multi(party, waves[0], waves.slice(1), sd))

## 3 人金剛伏魔圈 vs 同條件無陣（同一套「站定、相鄰才打」的指令），勝率至少高 15 個百分點。
## 陣法 2001-10-05 隨神鵰大俠（1.0B）開放（news 322）→ 這個案例用 1.0A + 1.0B 的資料視圖
func case_formation(runs: int, seed0: int) -> int:
	var saved := tables
	if _loader != null:
		tables = _loader.activate(["1.0A", "1.0B"])
	var r := _case_formation(runs, seed0)
	tables = saved
	return r

func _case_formation(runs: int, seed0: int) -> int:
	if not _has_art("sl_jgfmq"):
		return _skip("formation3_bonus", "武功 sl_jgfmq")
	if not _tongren_ready("formation3_bonus"):
		return -1
	var sk := (player_spec("P3").skills as Dictionary).duplicate()
	sk["sl_jgfmq"] = 50
	sk["basic_formation"] = 50
	sk["foxa"] = 70
	var party := _p3_party(3, { "skills": sk, "party_id": "sim_party", "cmd_arts": cmd_arts_of(sk), "sect": "shaolin" })
	var waves := _tongren_waves()
	var rates: Array = []
	var counts := { "battle_formation_on": 0, "battle_formation_off": 0 }
	for use_form in [true, false]:
		var wins := 0
		for i in runs:
			var r := simulate_multi(party, waves[0], waves.slice(1), seed0 + i,
				func(b: Battle, u: BattleUnit) -> Dictionary: return formation_policy(b, u, use_form), true,
				counts if use_form else {})
			if r.result == "VICTORY":
				wins += 1
		rates.append(wins / float(runs))
	var ok: bool = rates[0] - rates[1] >= 0.15
	print("%-24s %s  win_formation=%5.1f%%  win_plain=%5.1f%%  diff=%+5.1fpp  formation_on=%.1f off=%.1f /場%s" % [
		"formation3_bonus", "ok  " if ok else "FAIL", rates[0] * 100.0, rates[1] * 100.0, (rates[0] - rates[1]) * 100.0,
		counts.battle_formation_on / float(runs), counts.battle_formation_off / float(runs), "" if ok else "  (差距 < 15pp)"])
	return 1 if ok else 0

## 站定（不移動，免得破陣）：施陣者先結陣；有敵人在射程內就照 AI 出招，否則防
func formation_policy(b: Battle, u: BattleUnit, use_form: bool) -> Dictionary:
	if use_form and u.uid == 1 and u.formation.is_empty():
		var c := { "cmd": "FORMATION", "art": "sl_jgfmq" }
		if BattleRules.validate_cmd(b, u, c, tables) == "":
			return c
	var ai := BattleAI.choose(b, u, tables, b.rng)
	if str(ai.get("cmd", "")) == "MOVE":
		return { "cmd": "DEFEND" }
	return ai

## P1 只用毒指令（放毒法 20 級）＋防：平均戰鬥時間比普通攻擊長，但勝率 ≥ 0.5
func case_poison(runs: int, seed0: int) -> int:
	if not _has_art("xh_fangdu"):
		return _skip("poison_p1_vs_wolf", "武功 xh_fangdu")
	var ps := sect_spec("P1", "xingxiu", "xh_fangdu", 20)
	ps.skills["basic_poison"] = 20
	# 整合：P1 底子的基本內功 5 → 內力 25，只夠放 6 次毒就只能一直防，勝率 0%。
	# 走毒路線的星宿弟子會練內功；參考角色改成基本內功 20（內力 100）
	ps.skills["basic_inner"] = 20
	ps.neili_max = 100
	ps.neili = 100
	ps.effective_inner = 20
	ps.cmd_arts = cmd_arts_of(ps.skills)
	ps.arts = []
	var wins := 0
	var acts := 0
	for i in runs:
		var r := simulate_multi([ps], ["m_wolf"], [], seed0 + i,
			func(b: Battle, u: BattleUnit) -> Dictionary: return poison_policy(b, u))
		if r.result == "VICTORY":
			wins += 1
		acts += int(r.actions)
	var base_acts := 0
	var base := player_spec("P1")
	for i in runs:
		base_acts += int(simulate(base, Encounter.monster_spec("m_wolf", tables), seed0 + i).actions)
	var win := wins / float(runs)
	var ok := win >= 0.5 and acts > base_acts
	print("%-24s %s  win=%5.1f%%  rounds=%5.1f  rounds_plain=%5.1f%s" % ["poison_p1_vs_wolf", "ok  " if ok else "FAIL",
		win * 100.0, acts / float(runs), base_acts / float(runs), "" if ok else "  (勝率 < 50% 或沒有比普通攻擊久)"])
	return 1 if ok else 0

func poison_policy(b: Battle, u: BattleUnit) -> Dictionary:
	for e in b.units:
		if e.side != u.side and e.is_active():
			var c := { "cmd": "POISON", "art": "xh_fangdu", "target": [e.pos.x, e.pos.y] }
			if BattleRules.validate_cmd(b, u, c, tables) == "":
				return c
	return { "cmd": "DEFEND" }

## P3 在古墓迷宮連打 3 場（中間不回氣）的存活率 0.6–0.95
func case_gumu_maze(runs: int, seed0: int) -> int:
	var rooms: Array = []
	var idx: Dictionary = DataLint.room_index(tables)
	for rid in idx:
		if str(idx[rid].get("region", "")) == "gumu_maze" \
				and not Encounter.pick(idx[rid]["room"], RandomNumberGenerator.new()).is_empty():
			rooms.append(rid)
	if rooms.is_empty():
		return _skip("gumu_maze_p3", "地區 gumu_maze")
	rooms.sort()
	var survived := 0
	for i in runs:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed0 + i * 7919
		var ps := player_spec("P3")
		var alive := true
		for k in 3:
			var mons := Encounter.pick(idx[rooms[rng.randi_range(0, rooms.size() - 1)]]["room"], rng)
			var r := simulate_multi([ps], mons, [], rng.randi())
			if r.result != "VICTORY":
				alive = false
				break
			ps = ps.duplicate(true)
			ps.qi = maxi(1, roundi(float(r.qi_pct) * int(ps.qi_max)))
		if alive:
			survived += 1
	var surv := survived / float(runs)
	var ok := surv >= 0.6 and surv <= 0.95
	print("%-24s %s  surv=%5.1f%%  rooms=%d%s" % ["gumu_maze_p3", "ok  " if ok else "FAIL", surv * 100.0, rooms.size(),
		"" if ok else "  (存活率不在 60%–95%)"])
	return 1 if ok else 0

## 通用：跑 runs 場、統計並印一行。sim(seed) 回傳 simulate_multi() 形狀的字典
func run_generic(name: String, chk: Dictionary, runs: int, seed0: int, sim: Callable) -> int:
	var wins := 0
	var kills := 0
	var actions := 0
	var qi_left := 0.0
	var aborted := 0
	var deaths: Array = []
	for i in runs:
		var r: Dictionary = sim.call(seed0 + i)
		deaths.append(int(r.get("deaths", 0)))
		if r.result == "VICTORY":
			wins += 1
			qi_left += float(r.qi_pct)
			if r.killed:
				kills += 1
		elif r.result == "ABORTED":
			aborted += 1
		actions += int(r.actions)
	var win_rate := wins / float(runs)
	var why: PackedStringArray = []
	if chk.has("win_min") and win_rate < chk.win_min:
		why.append("勝率 < %.0f%%" % (chk.win_min * 100))
	if chk.has("win_max") and win_rate > chk.win_max:
		why.append("勝率 > %.0f%%" % (chk.win_max * 100))
	# M3a 審查 B4：p1_sect_* 的 rounds_min 以前寫了卻沒有檢查（只有 run_case 看）
	if chk.has("rounds_min") and actions / float(runs) < float(chk.rounds_min):
		why.append("平均行動數 %.1f < %.1f（比參考線快太多）" % [actions / float(runs), float(chk.rounds_min)])
	if chk.has("qi_left_max") and wins > 0 and qi_left / wins > float(chk.qi_left_max):
		why.append("勝場剩餘氣 > %.0f%%（比參考線輕鬆太多）" % (float(chk.qi_left_max) * 100))
	deaths.sort()
	var ok := why.is_empty()
	print("%-24s %s  win=%5.1f%%  kill=%5.1f%%  rounds=%5.1f  qi_left=%5.1f%%  aborted=%d  deaths_median=%d%s" % [name,
		"ok  " if ok else "FAIL", win_rate * 100.0, kills * 100.0 / runs, actions / float(runs),
		(qi_left / wins * 100.0) if wins > 0 else 0.0, aborted, deaths[deaths.size() / 2],
		"" if ok else "  (" + "；".join(why) + ")"])
	return 1 if ok else 0

## 多人、多波次。policy 無效 → 玩家全由 BattleAI（非等待模式）；有效 → 玩家是真人單位（等待模式），由 policy 下令。
## place_formation：開戰後把前 3 位玩家放到金剛伏魔圈的站位（(2,3)、(1,4)、(3,4)）
func simulate_multi(pspecs: Array, first: Array, waves: Array, s: int, policy: Callable = Callable(),
		place_formation: bool = false, counts: Dictionary = {}) -> Dictionary:
	var human := policy.is_valid()
	var b := Battle.new(1, s, { "wait_mode": human, "escape_tiles": 2 })
	var n := 0
	for ps0 in pspecs:
		var ps: Dictionary = ps0.duplicate(true)
		n += 1
		if human:
			ps.erase("ai")
			ps.peer = n
		b.add_unit(ps)
	for m in Encounter.monster_specs(first, tables):
		b.add_unit(m)
	var later: Array = []
	for w in waves:
		later.append(Encounter.monster_specs(w, tables))
	if not later.is_empty():
		b.set_waves(later)
	b.start(tables)
	if place_formation and n >= 3:
		b.unit(1).pos = Vector2i(2, 3)
		b.unit(2).pos = Vector2i(1, 4)
		b.unit(3).pos = Vector2i(3, 4)
	while not b.is_over():
		for e in b.step(Battle.TICK, tables):
			if counts.has(e.key):
				counts[e.key] = int(counts[e.key]) + 1
		if human and b.state == Battle.State.AWAIT_COMMAND:
			for u in b.waiting_humans():
				if b.submit(u.peer, policy.call(b, u), tables) != "":
					b.submit(u.peer, { "cmd": "DEFEND" }, tables)
	var me: BattleUnit = b.unit(1)
	var deaths := 0
	for u in b.units:
		if u.side == 0 and u.is_dead():
			deaths += 1
	# M3c2 WP-PACE：另回 tick 數與第一位玩家戰後的精氣神內力（節奏模擬的時間與戰後狀態）
	return { "result": b.result_name(), "killed": b.units.filter(func(u): return u.side == 1).all(func(u): return u.is_dead()),
		"actions": me.actions, "dmg_sum": 0, "dmg_n": 0, "qi_pct": me.qi / float(me.qi_max()), "deaths": deaths,
		"ticks": b.tick_no, "qi": me.qi, "jing": me.jing, "shen": me.shen, "neili": me.neili, "dead": me.is_dead() }

# ==== M3c WP-LOOT ====
## 裝備與打寶的平衡（M3C_PLAN §12.2）。掉落表的經濟用期望值（解析）＋固定種子的擲骰次數；戰鬥案例照 run_generic。
## - loot_econ_elite：實戰 2 萬連打精英（山賊頭目：FIGHT 服務、可重複；勝率×每小時場數）1 小時，賣店銀兩期望 ≤ 現行 1.25 倍
## - loot_econ_boss：鬼王 100 場，銀兩期望 ≤ 1.25 倍；固定種子 100 場的珍品次數 2–9
## - armor_full_kit：最便宜一整套 7 件官方防具 vs 現行布衣，對鬼王勝率提高 ≤ 15 個百分點
## - divine_duel：同實戰（同派同武功、同等級）的兩人 PvP，一人拿倚天劍、一人拿店裡最好的劍：勝率 ≤ 75%
## - manual_speed：讀書識字 40 讀華陀內昭圖 0→40 級所需精神與學點，與自修相比不得快於 2 倍（M3c 審查：加學點）
const LOOT_SELL_RATE := 0.3   # ＝ NpcSystem.SELL_RATE
const LOOT_ARMOR_SLOTS := ["ARMOR", "HEAD", "NECK", "WRIST", "CLOAK", "RING", "BOOTS"]

func loot_cases() -> Array:
	return [
		["loot_econ_elite", case_loot_econ_elite],
		["loot_econ_boss", case_loot_econ_boss],
		["armor_full_kit", case_armor_full_kit],
		["divine_duel", case_divine_duel],
		["manual_speed", case_manual_speed],
		["loot_rate_hour", case_loot_rate_hour],
	]

func _sell(item_id: String) -> float:
	var r := item_row(item_id)
	if r.is_empty() or bool(r.get("no_sell", false)) or bool(r.get("quest_item", false)):
		return 0.0
	return maxf(1.0, floorf(float(r.get("price", 0)) * LOOT_SELL_RATE))

## 一隻怪「現行」的期望收益（銀兩＋既有 drops 賣店），與掉落表的期望增量（同規則：神兵群組只在 BOSS_DROP、秘笈照擲）
func _base_ev(mid: String) -> float:
	var row: Dictionary = tables.get("monsters", {}).get(mid, {})
	var ev := 0.0
	var m: Variant = row.get("money", {})
	if m is Dictionary and not (m as Dictionary).is_empty():
		ev += (float(m.get("min", 0)) + float(m.get("max", m.get("min", 0)))) / 2.0
	for d in row.get("drops", []):
		var ch := minf(1.0, float(d.get("chance", 0.0)))
		ev += ch * (float(d.get("min", 1)) + float(d.get("max", d.get("min", 1)))) / 2.0 * _sell(str(d.get("item", "")))
	return ev

func _loot_ev(mid: String) -> float:
	var lt: Dictionary = tables.get("loot_tables", {}).get(str(tables.get("monsters", {}).get(mid, {}).get("loot_table", "")), {})
	var ev := 0.0
	for g in lt.get("guaranteed", []):
		ev += (float(g.get("min", 1)) + float(g.get("max", g.get("min", 1)))) / 2.0 * _sell(str(g.get("item", "")))
	for grp in lt.get("groups", []):
		var total := 0.0
		var val := 0.0
		for p in grp.get("pick", []):
			total += float(p.get("w", 0))
			val += float(p.get("w", 0)) * _sell(str(p.get("item", "")))
		if total > 0.0:
			ev += float(grp.get("chance", 0.0)) * val / total
	return ev

func _econ_line(name: String, mid: String, extra := "") -> int:
	if not tables.get("monsters", {}).has(mid) or str(tables.monsters[mid].get("loot_table", "")) == "":
		return _skip(name, mid + " 掉落表")
	var base := _base_ev(mid)
	var add := _loot_ev(mid)
	var ratio := (base + add) / maxf(1.0, base)
	var ok := ratio <= 1.25
	print("%-24s %s  base=%6.1f  loot=+%5.1f  ratio=%.3f%s%s" % [name, "ok  " if ok else "FAIL", base, add, ratio, extra,
		"" if ok else "  (掉落賣店銀兩 > 現行 1.25 倍)"])
	return 1 if ok else 0

## 實戰 2 萬打山賊頭目：先跑勝率（決定一小時實際賣得到的量），比例本身與勝率無關（同一場景的勝場收益比）
func case_loot_econ_elite(runs: int, seed0: int) -> int:
	var mid := "m_bandit_chief"
	if not tables.get("monsters", {}).has(mid):
		return _skip("loot_econ_elite", mid)
	var party := _p_party(20000, 1)
	var wins := 0
	var acts := 0
	var n := mini(runs, 200)
	for i in n:
		var r := simulate_multi(party, [mid], [], seed0 + i)
		acts += int(r.actions)
		if r.result == "VICTORY":
			wins += 1
	# 一場約 actions × 2 秒＋休息、走路 60 秒【設計提案】；只用來印每小時的量
	var per_fight_s := acts / float(maxi(1, n)) * 2.0 + 60.0
	var fights_h := 3600.0 / per_fight_s * wins / float(maxi(1, n))
	var base_h := _base_ev(mid) * fights_h
	var add_h := _loot_ev(mid) * fights_h
	_elite_fights_h = fights_h
	return _econ_line("loot_econ_elite", mid, "  win=%.0f%%  fights/h=%.1f  silver/h %.0f→%.0f" % [100.0 * wins / maxi(1, n), fights_h, base_h, base_h + add_h])

## M3c 審查：每小時的量（不只每場比例）。一個角色全力刷：三個頭目（有 lockout_shichen 的表，每表每鎖定期擲一次）＋精英（loot_econ_elite 的每小時場數）。
## - 頭目珍品 ≤ 0.25 件／小時（§6.1「頭目稀有」）；全部珍品 ≤ 0.5 件／小時；
## - 每把神兵的期望時數 ≥ 300 小時；掉神兵的表一定要有 lockout_shichen（不然無上限）
## M3c 第三輪審查：神兵改用「4 人隊伍輪流搶最後一擊、三個頭目都打」的模型——頭目鎖跟著最後一擊者，隊伍每人各擲一次；
## 神兵群組另有全服鎖（BattleRewards.DIVINE_LOCK_SCOPE == "WORLD"）→ 每張表每鎖定期全服只擲一次，不隨人數變多。
## 檢查兩個數：每把神兵最快幾小時、三個頭目合起來「全服第一把神兵」幾小時，都要 ≥ 300。
var _elite_fights_h := 45.0
const LOOT_RATE_PARTY_N := 4
const LOOT_RATE_BOSS_TREASURE_H := 0.25
const LOOT_RATE_ALL_TREASURE_H := 0.5
const LOOT_RATE_DIVINE_MIN_H := 300.0

func _treasure_p(lt: Dictionary) -> float:
	var p := 0.0
	for grp in lt.get("groups", []):
		if bool(grp.get("divine", false)):
			continue
		var total := 0.0
		var hit := 0.0
		for pk in grp.get("pick", []):
			total += float(pk.get("w", 0))
			if BattleRewards.rarity_rank(BattleRewards.rarity_of(tables, str(pk.get("item", "")))) >= BattleRewards.rarity_rank("TREASURE"):
				hit += float(pk.get("w", 0))
		if total > 0.0:
			p += float(grp.get("chance", 0.0)) * hit / total
	return p

func case_loot_rate_hour(_runs: int, _seed0: int) -> int:
	var lts: Dictionary = tables.get("loot_tables", {})
	if lts.is_empty():
		return _skip("loot_rate_hour", "loot_tables")
	var day_s := float(WorldClock.DEFAULT_DAY_S)
	var boss_h := 0.0
	var worst_divine_h := INF
	var any_divine_rate := 0.0
	var unlocked := ""
	var world_lock := BattleRewards.DIVINE_LOCK_SCOPE == "WORLD"
	for lid in lts:
		var lt: Dictionary = lts[lid]
		var has_dv := false
		var dv_p := 0.0
		for grp in lt.get("groups", []):
			if bool(grp.get("divine", false)):
				has_dv = true
				dv_p += float(grp.get("chance", 0.0))
		if not has_dv:
			continue
		var lock_n := int(lt.get("lockout_shichen", 0))
		if lock_n <= 0:
			unlocked = str(lid)
			continue
		var rolls_h := 3600.0 / (float(lock_n) * WorldClock.shichen_len(day_s))
		boss_h += rolls_h * _treasure_p(lt)
		if dv_p > 0.0:
			# 神兵：全服鎖 → 每鎖定期一擲；沒有全服鎖 → 隊伍每人輪流各一擲
			var dv_rolls_h := rolls_h if world_lock else rolls_h * float(LOOT_RATE_PARTY_N)
			worst_divine_h = minf(worst_divine_h, 1.0 / (dv_rolls_h * dv_p))
			any_divine_rate += dv_rolls_h * dv_p
	var elite_p := 0.0
	var mid := "m_bandit_chief"
	var elt: Dictionary = lts.get(str(tables.get("monsters", {}).get(mid, {}).get("loot_table", "")), {})
	if not elt.is_empty():
		elite_p = _treasure_p(elt)
	var elite_h := elite_p * _elite_fights_h
	var all_h := boss_h + elite_h
	var first_any_h := 1.0 / any_divine_rate if any_divine_rate > 0.0 else INF
	var ok := unlocked == "" and boss_h <= LOOT_RATE_BOSS_TREASURE_H and all_h <= LOOT_RATE_ALL_TREASURE_H 			and worst_divine_h >= LOOT_RATE_DIVINE_MIN_H and first_any_h >= LOOT_RATE_DIVINE_MIN_H
	print("%-24s %s  珍品／小時：頭目 %.3f（≤ %.2f）＋精英 %.3f（%.1f 場）＝ %.3f（≤ %.2f）；神兵（%d 人輪流、%s）每把最快 %.0f 小時、全服第一把 %.0f 小時（≥ %.0f）%s" % [
		"loot_rate_hour", "ok  " if ok else "FAIL", boss_h, LOOT_RATE_BOSS_TREASURE_H, elite_h, _elite_fights_h, all_h,
		LOOT_RATE_ALL_TREASURE_H, LOOT_RATE_PARTY_N, "全服鎖" if world_lock else "各自鎖", worst_divine_h, first_any_h, LOOT_RATE_DIVINE_MIN_H,
		("  (%s 沒有 lockout_shichen)" % unlocked) if unlocked != "" else ""])
	return 1 if ok else 0

func case_loot_econ_boss(runs: int, seed0: int) -> int:
	var mid := "m_guiwang"
	# M3c 第二輪審查：這是「每場都擲群組」的上限；實際上同一角色每 lockout_shichen（1 遊戲日）只擲一次群組（loot_rate_hour 才是實際收入）
	var lt_lock := int(tables.get("loot_tables", {}).get(str(tables.monsters[mid].get("loot_table", "")), {}).get("lockout_shichen", 0))
	var r := _econ_line("loot_econ_boss", mid, "  （每場都擲＝上限；頭目鎖 %d 時辰實際更少）" % lt_lock if lt_lock > 0 else "")
	if r <= 0:
		return r
	# 固定種子 100 場：珍品（TREASURE 以上）次數 2–9
	var lt: Dictionary = tables.loot_tables[str(tables.monsters[mid].loot_table)]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed0 * 7919 + 3
	var n_tre := 0
	for i in 100:
		var ctx := { "rules": { "divine_source": "BOSS_DROP", "manuals": true }, "blocked": [], "force": [], "drop_pct": 100 }
		for it in BattleRewards.roll_table(lt, tables, rng, ctx):
			if BattleRewards.rarity_rank(BattleRewards.rarity_of(tables, str(it.id))) >= BattleRewards.rarity_rank("TREASURE"):
				n_tre += 1
	var ok := n_tre >= 2 and n_tre <= 9
	print("%-24s %s  鬼王 100 場珍品 %d 次%s" % ["loot_econ_boss_treasure", "ok  " if ok else "FAIL", n_tre, "" if ok else "  (不在 2–9)"])
	return 1 if ok else 0

## 最便宜的一整套官方防具（有 official 欄、男角能穿、每個部位一件、取最低價；同價取 id 小的）
func cheapest_kit() -> Dictionary:
	var kit := {}
	var ids: Array = tables.get("items", {}).keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = tables.items[id]
		var slot := str(r.get("slot", ""))
		if not (slot in LOOT_ARMOR_SLOTS) or not (r.get("official") is Dictionary):
			continue
		var male_ok := true
		for c in r.get("requires", []):
			if c is Dictionary and str(c.get("type", "")) == "gender" and str(c.get("value", "")) != "M":
				male_ok = false
		if not male_ok:
			continue
		if not kit.has(slot) or int(r.get("price", 0)) < int(item_row(kit[slot]).get("price", 0)):
			kit[slot] = str(id)
	return kit

func case_armor_full_kit(runs: int, seed0: int) -> int:
	var kit := cheapest_kit()
	if kit.size() < LOOT_ARMOR_SLOTS.size() or not tables.get("monsters", {}).has("m_guiwang"):
		return _skip("armor_full_kit", "7 個部位的官方防具／m_guiwang（%s）" % str(kit))
	var def_sum := 0
	var bonus := {}
	for slot in kit:
		var r := item_row(kit[slot])
		def_sum += int(r.get("def", 0))
		var b: Variant = r.get("bonus", {})
		if b is Dictionary:
			for k in b:
				bonus[k] = int(bonus.get(k, 0)) + int(b[k])
	# 判定的參考角色：實戰 2 萬（＝鬼王 combat_xp_ref；與 loot_econ_elite 同一個實戰）、武學 49（實戰上限）、P3 底，只換防具。
	# 另印（不判定）最敏感點：布衣勝率剛過 30% 的參考角色（防具差異在勢均力敵時最明顯）
	var ps: Dictionary = _p_at(20000, 49)
	ps.armor_power = armor_def("a_bupao", 2)
	var probe := _kit_probe(def_sum, bonus, seed0)
	var kitted: Dictionary = ps.duplicate(true)
	kitted.armor_power = def_sum
	for k in bonus:
		kitted.attrs[k] = int(kitted.attrs.get(k, 0)) + int(bonus[k])
	var w0 := 0
	var w1 := 0
	var n := runs
	for i in n:
		if simulate_multi([ps], ["m_guiwang"], [], seed0 + i).result == "VICTORY":
			w0 += 1
		if simulate_multi([kitted], ["m_guiwang"], [], seed0 + i).result == "VICTORY":
			w1 += 1
	var d := (w1 - w0) / float(n)
	var ok := d <= 0.15
	var names: PackedStringArray = []
	for slot in LOOT_ARMOR_SLOTS:
		names.append(str(item_row(kit[slot]).get("name", kit[slot])))
	print("%-24s %s  參考 武學 %d：布衣 win=%5.1f%%  整套（%s；防 %d）win=%5.1f%%  +%.1f pp%s" % ["armor_full_kit", "ok  " if ok else "FAIL",
		int(ps.skills.get("basic_fist", 0)), 100.0 * w0 / n, "、".join(names), def_sum, 100.0 * w1 / n, d * 100.0, "" if ok else "  (> 15 個百分點)"])
	print("%-24s info  最敏感點 武學 %d：布衣 win=%5.1f%%  整套 win=%5.1f%%  %+.1f pp（只列印）" % ["armor_full_kit_probe",
		int(probe.lv), float(probe.w0) * 100.0, float(probe.w1) * 100.0, (float(probe.w1) - float(probe.w0)) * 100.0])
	return 1 if ok else 0

## 布衣勝率剛過 30% 的參考角色（武學由低往高找），回傳 { lv, w0, w1 }（60 場）
func _kit_probe(def_sum: int, bonus: Dictionary, seed0: int) -> Dictionary:
	var out := { "lv": 0, "w0": 0.0, "w1": 0.0 }
	for lv in [15, 20, 25, 30, 35, 40, 45, 49]:
		var cand: Dictionary = _p_at(lv * 400, lv)
		cand.armor_power = armor_def("a_bupao", 2)
		var kit: Dictionary = cand.duplicate(true)
		kit.armor_power = def_sum
		for k in bonus:
			kit.attrs[k] = int(kit.attrs.get(k, 0)) + int(bonus[k])
		var w0 := 0
		var w1 := 0
		for i in 60:
			if simulate_multi([cand], ["m_guiwang"], [], seed0 + 5000 + i).result == "VICTORY":
				w0 += 1
			if simulate_multi([kit], ["m_guiwang"], [], seed0 + 5000 + i).result == "VICTORY":
				w1 += 1
		out = { "lv": lv, "w0": w0 / 60.0, "w1": w1 / 60.0 }
		if w0 >= 18:
			break
	return out

## 同派同武功同等級的兩人 PvP（AI 對打）：A 拿倚天劍、B 拿 1.0A 商店最好的劍（黑劍）
func case_divine_duel(runs: int, seed0: int) -> int:
	var art := "hs_jianfa"
	if not _has_art(art) or item_row("w_sb_yitian").is_empty():
		return _skip("divine_duel", art + "／w_sb_yitian")
	var best := ""
	for nid in tables.get("npcs", {}):
		var shop: Variant = tables.npcs[nid].get("shop", {})
		if not (shop is Dictionary):
			continue
		for iid in shop.get("items", []):
			var r := item_row(str(iid))
			if str(r.get("weapon_type", "")) == "SWORD" and (best == "" or int(r.get("atk", 0)) > int(item_row(best).get("atk", 0))):
				best = str(iid)
	var wins := 0
	var n := runs
	for i in n:
		var a := _duel_spec(art, "w_sb_yitian", 0)
		var b := _duel_spec(art, best, 1)
		var bt := Battle.new(1, seed0 + i, { "wait_mode": false, "escape_tiles": 2 })
		bt.add_unit(a)
		bt.add_unit(b)
		bt.start(tables)
		var guard := 0
		while not bt.is_over() and guard < 200000:
			bt.step(Battle.TICK, tables)
			guard += 1
		if bt.unit(2).is_dead() and not bt.unit(1).is_dead():
			wins += 1
	var wr := wins / float(n)
	var ok := wr <= 0.75
	print("%-24s %s  倚天劍 vs %s（%s %d 級、實戰 %d）win=%5.1f%%%s" % ["divine_duel", "ok  " if ok else "FAIL",
		str(item_row(best).get("name", best)), str(tables.martial_arts[art].get("name", art)), DUEL_LV, DUEL_XP, wr * 100.0, "" if ok else "  (> 75%)"])
	return 1 if ok else 0

## 神兵是 2002 武林大會頂尖玩家的獎品 → 參考角色取頂尖（實戰 100 萬、武學 200；上限 5+√(實戰/10)=321）【設計提案】
const DUEL_XP := 1000000
const DUEL_LV := 200

func _duel_spec(art: String, weapon_id: String, side: int) -> Dictionary:
	var s := _p_at(DUEL_XP, DUEL_LV)
	var sk: Dictionary = {}
	for k in ["basic_sword", "basic_inner", "basic_parry", "basic_dodge", "basic_body"]:
		sk[k] = DUEL_LV
	sk[art] = DUEL_LV
	s.skills = sk
	s.arts = [art]
	s.sect = "huashan"
	s.sect_skill = {}
	s.cmd_arts = cmd_arts_of(sk)
	s.weapon = weapon_of(weapon_id, "it_duel%d" % side)
	s.weapon_options = [s.weapon]
	s.side = side
	s.peer = 0
	s.ref = "sim_duel_%d" % side
	s.name = "對手%d" % side
	s.kind = "PLAYER"
	s.ai = "melee_basic"
	return s

## 讀書識字 40 讀華陀內昭圖（basic_medic，每次熟練 +10、精 10＋神 10；M3c 第二輪審查）0→40 級，vs 自修（悟性 21：每次熟練 ⌊21/4⌋、精 wit_cost）
const MANUAL_SPEED_MIN := 0.9
func case_manual_speed(_runs: int, _seed0: int) -> int:
	var row := item_row("bk_huatuo")
	var m: Variant = row.get("manual", {})
	if not (m is Dictionary) or (m as Dictionary).is_empty():
		return _skip("manual_speed", "bk_huatuo")
	var skill := str(m.get("skill", "basic_medic"))
	var need := SkillBook.prof_for_level(skill, 40, tables)
	var reads := ceili(need / float(maxi(1, int(m.get("prof", Learning.MANUAL_DEFAULT_PROF)))))
	var manual_cost := reads * (int(m.get("jing", Learning.MANUAL_DEFAULT_JING)) + int(m.get("shen", Learning.MANUAL_DEFAULT_SHEN)))
	var wit := int(ATTRS_P.wit)
	var gain := maxi(1, floori(wit / 4.0))
	var times := ceili(need / float(gain))
	var self_cost := times * int(Learning.wit_cost(wit)["jing"])
	var speed := self_cost / float(maxi(1, manual_cost))   # >1 = 秘笈比自修快
	# M3c 審查：學點也比（研讀每次 LP_PER_TIME，與自修同價）：秘笈省下的學點不得超過一半（＝不得快於 2 倍）
	var manual_lp := reads * Learning.LP_PER_TIME
	var self_lp := times * Learning.LP_PER_TIME
	var lp_speed := self_lp / float(maxi(1, manual_lp))
	# M3c 第二輪審查：也不得比自修慢（< 0.9 倍＝珍品秘笈比自己練還差；以前 0.40 倍）
	var ok := speed <= 2.0 and speed >= MANUAL_SPEED_MIN and manual_lp > 0 and lp_speed <= 2.0
	print("%-24s %s  0→40 熟練 %d：秘笈 %d 次／精神 %d／學點 %d　自修 %d 次／精 %d／學點 %d　秘笈快 %.2f 倍（學點 %.2f 倍）%s" % ["manual_speed", "ok  " if ok else "FAIL",
		need, reads, manual_cost, manual_lp, times, self_cost, self_lp, speed, lp_speed, "" if ok else "  (> 2 倍、< %.1f 倍或不花學點)" % MANUAL_SPEED_MIN])
	return 1 if ok else 0

# ==== M3c WP-NPCPK ====
## 攻擊 NPC 的平衡（M3C_PLAN §12.2；單人參考角色同 _p_party：P3 底依實戰放大）。全部通過回 1。
## - npc_civilian：新角色打城市居民 ≥ 90%
## - npc_wushi_newbie／npc_wushi_50k：實戰 0 打武館教頭 ≤ 5%、實戰 5 萬 ≥ 50%
## - wd_disciple_150k：實戰 15 萬單人打 1 名武當弟子（n_wd_* 的戰鬥單位 m_wd_guard ×1）≥ 50%
##   ＝研究 2002 攻略「實戰 15 萬…在武當大廳來回走遇隨機武當弟子」的刷法
## - npc_master：實戰 100 萬單人打丁春秋、血刀老祖 ≤ 10%（不可能單挑贏）
## - gate_*（M3c 第二輪審查）：門口硬闖戰的專用列（有實戰、學點）：研究區間中段單人 ≥ 50%、實戰 6 萬 ≤ 5%
## - 孫婆婆滅派只有一種陣容（孫婆婆＋5；第二輪審查拿掉 2002 的「之後 4 個」，2001 規則下回不到墓口）
## - miepai_wudang／miepai_gumu（M3c 審查：改判定，用滅派專用列；以下是舊說明）：只列印（不判定）。M3C_PLAN 缺漏：§12.2 要「15 萬單人打 3 名武當護山 ≥ 50%」「6 萬單人打孫婆婆＋5 ≥ 40%」，
##   但 §5.2 綁定的群組是既有的公敵執法單位 m_wd_guard／m_gm_guard（敵對入山用，刻意做得很強：參考角色 6 萬單挑 1 名守墓弟子 0%、
##   15 萬單挑 1 名護山 ~88%、打 3 名 0%）。不改既有怪物列（會動到敵對入山與捉拿），也不改綁定的群組 → 這兩案改成只列印，交整合者決定
func case_m3c_npcpk(runs: int, seed0: int) -> int:
	var cases := [
		["npc_civilian", "P0", 0, ["m_npc_civilian"], { "win_min": 0.90 }],
		["npc_wushi_newbie", "P0", 0, ["m_npc_wushi"], { "win_max": 0.05 }],
		["npc_wushi_50k", "", 50000, ["m_npc_wushi"], { "win_min": 0.50 }],
		["wd_disciple_150k", "", 150000, ["m_wd_guard"], { "win_min": 0.50 }],
		["npc_master", "", 1000000, ["m_npc_dingchunqiu"], { "win_max": 0.10 }],
		["npc_master_xd", "", 1000000, ["m_npc_xd_laozu"], { "win_max": 0.10 }],
		# M3c 審查：滅派改用專用弱列（m_npc_wd_hushan、m_npc_gm_dizi），判定（2002 攻略：6 萬單人刷孫婆婆、15 萬刷武當）
		["miepai_wudang", "", 150000, ["m_npc_wd_hushan", "m_npc_wd_hushan", "m_npc_wd_hushan"], { "win_min": 0.50 }],
		["miepai_gumu", "", 60000, ["m_npc_sunpopo", "m_npc_gm_dizi", "m_npc_gm_dizi", "m_npc_gm_dizi", "m_npc_gm_dizi", "m_npc_gm_dizi"], { "win_min": 0.50 }],
		# M3c 第二輪審查：門口硬闖戰改用有獎勵的專用列 m_npc_<p>_gate（研究 gaoshou/31：全真 13–27.5 萬「點知客」一場 160 學點、
		# 血刀派 10–22 萬一場 60 學點；其他門派無資料，比照 18 萬）。判定研究區間中段單人 ≥ 50%、6 萬 ≤ 5%（不是新手刷點的地方）
		["gate_qz_200k", "", 200000, ["m_npc_qz_gate", "m_npc_qz_gate", "m_npc_qz_gate", "m_npc_qz_gate"], { "win_min": 0.50 }],
		["gate_qz_60k", "", 60000, ["m_npc_qz_gate", "m_npc_qz_gate", "m_npc_qz_gate", "m_npc_qz_gate"], { "win_max": 0.05 }],
		["gate_xd_160k", "", 160000, ["m_npc_xd_gate", "m_npc_xd_gate"], { "win_min": 0.50 }],
		["gate_xd_60k", "", 60000, ["m_npc_xd_gate", "m_npc_xd_gate"], { "win_max": 0.05 }],
		["gate_hg_180k", "", 180000, ["m_npc_hg_gate", "m_npc_hg_gate"], { "win_min": 0.50 }],
		["gate_em_180k", "", 180000, ["m_npc_em_gate", "m_npc_em_gate"], { "win_min": 0.50 }],
		["gate_lj_180k", "", 180000, ["m_npc_lj_gate", "m_npc_lj_gate"], { "win_min": 0.50 }],
		["gate_xh_180k", "", 180000, ["m_npc_xh_gate", "m_npc_xh_gate"], { "win_min": 0.50 }],
		# M3c 第二輪審查：街頭惡霸是新手區唯一會重生的「加善惡」對象 → 實戰 2000 單人要打得贏、0 實戰打不贏
		["npc_villain_2k", "", 2000, ["m_npc_villain"], { "win_min": 0.50 }],
		["npc_villain_newbie", "P0", 0, ["m_npc_villain"], { "win_max": 0.10 }],
		["miepai_gumu_newbie", "P0", 0, ["m_npc_sunpopo", "m_npc_gm_dizi", "m_npc_gm_dizi", "m_npc_gm_dizi", "m_npc_gm_dizi", "m_npc_gm_dizi"], { "win_max": 0.05 }],
	]
	var all_ok := 1
	for c in cases:
		var mons: Array = c[3]
		var missing := ""
		for m in mons:
			if not tables.get("monsters", {}).has(str(m)):
				missing = str(m)
		if missing != "":
			_skip(str(c[0]), missing)
			continue
		var party: Array = [player_spec(str(c[1]))] if str(c[1]) != "" else _p_party(int(c[2]), 1)
		var r := run_generic(str(c[0]), c[4], runs, seed0, func(sd: int) -> Dictionary:
			return simulate_multi(party, mons, [], sd))
		if r == 0:
			all_ok = 0
	return all_ok

# ==== M3c2 WP-PACE ====
## M3C2_PLAN §2.6、§2.5、§3.3：門派節奏 pace_<派>、雜務防刷 chore_bot_cap、血刀威嚇 xd_weihe_uplift。
## pace_<派>：剛拜師（P0 屬性、悟性 21、起始學點 100、實戰 0）到 §2.2 的 P2 門檻的真實遊玩時數。
## 模型（綁定，§2.6）：真的 CharacterFactory／Character／Learning.learn（masters.json 的師父與上限、規則 classic_standard）、
## Survival.tick 回精回氣、WorldClock 的時辰（雜務時辰窗）、雜務資料（quests.chore）、切磋與野外戰鬥用 simulate_multi。
## 時間：走一間房 4 秒、對話 6 秒、房間動作 8 秒、學藝每次 1 秒（10 次一批）、戰鬥 ticks × Battle.TICK ＋ 結果畫面 2.5 ＋ 偵察冷卻 6。
## 策略（每一步依序檢查，第一個成立就做）：(a) 雜務 (b) 學門檻表裡完成度最低的技能 10 次 (c) 切磋 (d) 出門練功 8 場 (e) 等回精回氣。
const PACE_SECTS := ["shaolin", "huashan", "wudang", "emei", "hengshan", "quanzhen", "gumu", "lingjiu", "xingxiu", "xuedao", "gaibang"]
## §2.2 門檻表：[入門武功, 心法]。丐幫：M3C2_PLAN 缺漏——「第一位師父教的最低 cap 的 ART」照字面是瘋魔杖法（cap 60，
## 但要二袋、太祖棍法 50、心法 30、乞討 30，不是入門武功）→ 改用傳功長老第一門沒有前置條件的入門武功太祖長拳（與 gb_spec 相同）
const PACE_GATE := {
	"shaolin": ["sl_changquan", "sl_xinfa"], "huashan": ["hs_jianfa", "hs_xinfa"], "wudang": ["wd_changquan", "wd_xinfa"],
	"emei": ["em_piaoxue", "em_xinfa"], "hengshan": ["hg_jianfa", "hg_xinfa"], "quanzhen": ["qz_jianfa", "qz_xinfa"],
	"gumu": ["gm_yunu_jian", "gm_xinfa"], "lingjiu": ["lj_zhemei", "lj_xiaoyao"], "xingxiu": ["xh_chousui", "xh_xinfa"],
	"xuedao": ["xd_daofa", "xd_xinfa"], "gaibang": ["gb_taizu_quan", "gb_xinfa"],
}
const PACE_LV_SECT := 30
const PACE_LV_ART := 35
const PACE_LV_BASE := 35
const PACE_LV_XINFA := 30
const PACE_LV_BASIC := 30
const PACE_XP := 9000
## M3c2 審查 #1：「第二階段」要真的打得動第二階段的練功點——門檻另含 P2 參考角色（player_spec("P2")）的其他部分：
## 本派輕功與基本輕功各 20、氣上限 660（180＋60 次修練 × 8；P2 參考）；最後還要通過「門檻角色 vs m_ghost」
## 勝率 ≥ 70%、剩氣 ≥ 25%（原 p2_vs_ghost 標準）。armor：P2 參考是粗布道袍（def 4），本模型照創角的布衣（def 2）【較嚴】。
const PACE_LIGHT := {
	"shaolin": "sl_shenfa", "emei": "em_shenfa", "gumu": "gm_tianluo_shen", "hengshan": "hg_shenfa", "lingjiu": "lj_yueying",
	"quanzhen": "qz_jinyan", "wudang": "wd_shenfa", "xingxiu": "xh_shenfa", "xuedao": "xd_xuedun",
}
const PACE_LV_LIGHT := 20
const PACE_QI_MAX := 660
const PACE_GHOST := "m_ghost"
const PACE_GHOST_WIN := 0.70
const PACE_GHOST_QI := 0.25
const PACE_GHOST_SIMS := 40
const PACE_BONUS_QI := 80            # 門檻都到了但還打不過鬼：再修練 10 次、武功與基本功再 +2（每次）
const PACE_BONUS_LV := 2
const PACE_BONUS_MAX := 6
const PACE_MEDITATE_S := 10.0        # 打坐冷卻 Survival.MEDITATE_COOLDOWN_S
const PACE_CULT_JING := 0.6          # 有學點可學時，精 ≥ 六成才打坐修練
const PACE_STEP_S := 4.0
const PACE_TALK_S := 6.0
const PACE_ACT_S := 8.0
const PACE_LEARN_S := 1.0
const PACE_BATTLE_END_S := 2.5
const PACE_SCOUT_S := 6.0
const PACE_BATCH := 10
## M3c2 第三輪審查 #3：「真人操作」估計——機器人不看選單、不讀字、打完立刻接下一場。報告另列「含真人操作」的時數
## （每場戰鬥 +25 秒、每件雜務交接 +25 秒、每次學藝 +0.5 秒；直接加在機器人時數上，不重跑：等待時的回精回氣不扣，偏保守）。
## 只報告、不當通過條件（3 小時是機器人的最佳情況，見 README／GDD）【設計提案】
const PACE_HUMAN_FIGHT_S := 25.0
const PACE_HUMAN_CHORE_S := 25.0
const PACE_HUMAN_LEARN_S := 0.5
const PACE_HUNT_N := 8
const PACE_WIN_MIN := 0.8
const PACE_SPAR_WIN_MIN := 0.3
const PACE_WINRATE_SIMS := 50
const PACE_HUNT_RADIUS := 8
const PACE_QI_FIGHT := 0.6          # 氣 ≥ 60% 才出門練功／切磋
const PACE_QI_BACK := 0.3           # 氣 < 30% 就回（§2.6 (d)）
const PACE_WAIT_S := 30.0
const PACE_MAX_H := 12.0
const PACE_RUNS_MAX := 100
const PACE_BAND := { "shaolin": [2.5, 3.5], "xuedao": [2.0, 5.0] }
const PACE_BAND_DEFAULT := [2.0, 4.5]
const PACE_CHORE_SHARE_MIN := 0.30  # 少林：雜務佔學點收入 ≥ 30%
const CHORE_DAY_CAP_LP := 600       # §2.5
const WEIHE_LEVELS := [10, 50, 100]
const WEIHE_HITS := 20000           # §3.3 寫 5000 次出手；用 20000 次壓低觸發率的抽樣誤差（比 5000 嚴格）
const WEIHE_RATIO := [0.70, 0.80]

var pace_trace := false             # --pace-trace：印每 30 分鐘的進度（第一輪）
var pace_rule_over := {}
var pace_spar_over: Array = []
var _pace_winrate := {}             # "<怪>|<數量>|<角色強度>" -> 勝率（各輪共用；兩把兵器取較好的）
var _pace_wpick := {}               # 同一個鍵 -> 用入門武功類別的兵器（true）或身上的木刀（false）
var _pace_dist := {}                # 起點房間 -> { 房間: 步數 }
var _pace_graph := {}

func pace_cases() -> Array:
	var out: Array = []
	for sid in PACE_SECTS:
		var nm := "pace_" + str(sid)
		var sect_id := str(sid)
		out.append([nm, func(runs: int, s0: int) -> int:
			if sect_id == "gaibang":
				return _with_1_0b(func() -> int: return case_pace(sect_id, runs, s0))
			return case_pace(sect_id, runs, s0)])
	out.append(["chore_bot_cap", case_chore_bot_cap])
	out.append(["xd_weihe_uplift", case_xd_weihe_uplift])
	return out

## classic_standard 的規則（RULE_DEFAULTS ＋ 預設組合）
func pace_rules(preset := "classic_standard") -> Dictionary:
	var r: Dictionary = DataSchema.RULE_DEFAULTS.duplicate(true)
	var rp: Dictionary = tables.get("rule_profiles", {}).get(preset, {})
	var rr: Variant = rp.get("rules", {})
	if rr is Dictionary:
		for k in rr:
			r[k] = rr[k]
	for k in pace_rule_over:
		r[k] = pace_rule_over[k]
	return r

func pace_options() -> Dictionary:
	var o: Dictionary = _loader.server_options_default.duplicate(true) if _loader != null else {}
	return o

func _pace_dists(from: String) -> Dictionary:
	if _pace_graph.is_empty():
		_pace_graph = DataLint.room_graph(tables)
	var key := from + "@" + str(tables.get("sects", {}).has("gaibang"))
	if _pace_dist.has(key):
		return _pace_dist[key]
	var d := { from: 0 }
	var q: Array = [from]
	while not q.is_empty():
		var c: String = q.pop_front()
		for n in _pace_graph.get(c, []):
			if not d.has(n):
				d[n] = int(d[c]) + 1
				q.append(n)
	_pace_dist[key] = d
	return d

func _pace_steps(a: String, b: String) -> int:
	if a == b:
		return 0
	return int(_pace_dists(a).get(b, 999))

## 門派的固定資料：門檻、師父、雜務路線、切磋、練功點、客棧
func _pace_setup(sid: String) -> Dictionary:
	_pace_graph = DataLint.room_graph(tables)
	_pace_dist.clear()
	var srow: Dictionary = tables.get("sects", {}).get(sid, {})
	var arts: Dictionary = tables.get("martial_arts", {})
	var npcs: Dictionary = tables.get("npcs", {})
	var gate: Array = PACE_GATE[sid]
	var art := str(gate[0])
	var xinfa := str(gate[1])
	var ss := str(srow.get("sect_skill", ""))
	var base := str(arts.get(art, {}).get("base_skill", "basic_fist"))
	var light := str(PACE_LIGHT.get(sid, ""))
	if light != "" and not arts.has(light):
		light = ""
	var skills := [ss, art, base, xinfa, "basic_inner", "basic_parry", "basic_dodge", "basic_body"]
	if light != "":
		skills.append(light)
	var masters := {}
	for sk in skills:
		var ms: Array = []
		for m in tables.get("masters", {}).values():
			if str(m.get("skill_id", "")) == sk and npcs.has(str(m.get("npc_id", ""))):
				ms.append(m)
		ms.sort_custom(func(a, b): return int(a.get("cap", 0)) > int(b.get("cap", 0)))
		masters[sk] = ms
	var ss_cap := 0
	for m in masters.get(ss, []):
		var ok_req := true
		for r in m.get("requires", []):
			if r is Dictionary and str(r.get("type", "")) in ["skill_min", "sect_master"]:
				ok_req = false
		if ok_req:
			ss_cap = maxi(ss_cap, int(m.get("cap", 0)))
	# M3C2_PLAN 缺漏：武當俠義、峨嵋斷惡（師父只教到 20）、丐幫乞討（陳長老只教到 10）的門派技能 30 學不到 → 門檻取 min(30, 師父上限)
	var targets := { ss: mini(PACE_LV_SECT, ss_cap), art: PACE_LV_ART, base: PACE_LV_BASE, xinfa: PACE_LV_XINFA,
		"basic_inner": PACE_LV_BASIC, "basic_parry": PACE_LV_BASIC, "basic_dodge": PACE_LV_BASIC }
	# M3c2 審查 #1：P2 參考角色的身法 20、基本輕功 20（師父教得到才算）
	var extra := { "basic_body": PACE_LV_LIGHT }
	if light != "":
		extra[light] = PACE_LV_LIGHT
	for sk in extra:
		if not (masters.get(sk, []) as Array).is_empty() and not targets.has(sk):
			targets[sk] = int(extra[sk])
	var gate_room := str(srow.get("gate_room", ""))
	# 雜務
	var chores: Array = []
	for qid in tables.get("quests", {}):
		var q: Dictionary = tables["quests"][qid]
		var c: Variant = q.get("chore", null)
		if not (c is Dictionary) or str(c.get("sect", "")) != sid:
			continue
		var route := _pace_chore_route(q)
		if route.is_empty():
			continue
		chores.append({ "qid": str(qid), "def": q, "chore": c, "route": route,
			"cd_s": float(q.get("repeat", {}).get("cooldown_days", 0.0)) * 7200.0 })
	chores.sort_custom(func(a, b): return int(a.chore.get("lp", 0)) > int(b.chore.get("lp", 0)))
	# 切磋
	var spar_mon := ""
	var spar_room := ""
	var prefix := str(srow.get("prefix", ""))
	for nid in npcs:
		var f: Variant = npcs[nid].get("fight", {})
		if not (f is Dictionary):
			continue
		var mid := str(f.get("monster", ""))
		if not Learning.is_spar_monster(mid) or not tables.get("monsters", {}).has(mid):
			continue
		if mid == "m_%s_dizi" % prefix or (sid == "huashan" and mid == "m_hs_trainee"):
			spar_mon = mid
			spar_room = str(npcs[nid].get("room", ""))
	# 練功點：山門附近（PACE_HUNT_RADIUS 步內）有遇敵表的房間
	var hunt: Array = []
	var ridx: Dictionary = DataLint.room_index(tables)
	var dg := _pace_dists(gate_room)
	for rid in dg:
		if int(dg[rid]) > PACE_HUNT_RADIUS or not ridx.has(rid):
			continue
		var enc: Variant = ridx[rid]["room"].get("encounter", null)
		if not (enc is Dictionary):
			continue
		var tbl: Array = enc.get("table", [])
		var tw := 0
		for e in tbl:
			tw += maxi(0, int(e.get("w", 0)))
		for e in tbl:
			var mid2 := str(e.get("monster", ""))
			if tw <= 0 or not tables.get("monsters", {}).has(mid2):
				continue
			var cnt: Array = e.get("count", [1, 1])
			hunt.append({ "room": rid, "monster": mid2, "p": maxi(0, int(e.get("w", 0))) / float(tw),
				"lo": int(cnt[0]) if cnt.size() > 0 else 1, "hi": int(cnt[cnt.size() - 1]) if cnt.size() > 0 else 1 })
	# 客棧（回精：來回比原地等快才去）
	var inn_room := ""
	var inn_price := 0
	var best := 999
	for nid in npcs:
		var n: Dictionary = npcs[nid]
		if "INN" in n.get("services", []):
			var dd := _pace_steps(gate_room, str(n.get("room", "")))
			if dd < best:
				best = dd
				inn_room = str(n.get("room", ""))
				inn_price = int(n.get("inn_price", 10))
	return { "sid": sid, "art": art, "xinfa": xinfa, "ss": ss, "base": base, "skills": skills, "masters": masters,
		"targets": targets, "gate_room": gate_room, "chores": chores, "spar_mon": spar_mon, "spar_room": spar_room,
		"hunt": hunt, "inn_room": inn_room, "inn_price": inn_price, "home": str(srow.get("home_city", "xixia")),
		"gender": str((srow.get("gender", ["M"]) as Array)[0]) if not (srow.get("gender", []) as Array).is_empty() else "M",
		"personal": bool(srow.get("personal_master", false)) }

## 雜務路線：[{ room, kind: TALK/ACT/FIGHT, hours, requires, item, monster, count }]；要先去買東西的（送酒、蛇膽）回 []
func _pace_chore_route(q: Dictionary) -> Array:
	var npcs: Dictionary = tables.get("npcs", {})
	var giver := str(q.get("giver", ""))
	if not npcs.has(giver):
		return []
	var given := {}
	for gi in q.get("give_items", []):
		if gi is Dictionary:
			given[str(gi.get("id", ""))] = true
	var out: Array = [{ "room": str(npcs[giver].get("room", "")), "kind": "TALK" }]
	for stg in q.get("stages", []):
		if not (stg is Dictionary):
			continue
		var kill_n := 0
		for o in stg.get("objectives", []):
			if o is Dictionary and str(o.get("type", "")) == "KILL":
				kill_n += maxi(1, int(o.get("count", 1)))
		for ra in stg.get("room_actions", []):
			if not (ra is Dictionary):
				continue
			var fight := {}
			for a in ra.get("do", []):
				if a is Dictionary and str(a.get("do", "")) == "fight":
					fight = a
			if not fight.is_empty():
				out.append({ "room": str(ra.get("room", "")), "kind": "FIGHT", "monster": str((fight.get("monsters", [""]) as Array)[0]),
					"count": maxi(1, kill_n) })
			else:
				out.append({ "room": str(ra.get("room", "")), "kind": "ACT", "hours": ra.get("hours", []), "requires": ra.get("requires", []) })
		for o in stg.get("objectives", []):
			if not (o is Dictionary):
				continue
			var ty := str(o.get("type", ""))
			if ty in ["TALK", "DELIVER"] and npcs.has(str(o.get("npc", ""))):
				var it := str(o.get("item", "")) if ty == "DELIVER" else ""
				if it != "" and not given.has(it):
					return []   # 要自己去買或去打的東西（嗜酒的淨歧、邪惡的練毒）：模擬不做
				out.append({ "room": str(npcs[str(o["npc"])].get("room", "")), "kind": "TALK" })
	return out

## P0 新弟子（真的 CharacterFactory；悟性 21；剛拜師）
func _pace_new_char(su: Dictionary, rng: RandomNumberGenerator, opts: Dictionary) -> Character:
	var ch := CharacterFactory.create({ "id": "sim_pace", "identity": "local_sim", "name": "節奏", "gender": su.gender,
		"birth_month": 1, "birth_city": su.home, "alloc": {} }, ATTRS_P.duplicate(), tables, opts, rng, 0.0)
	ch.sect = str(su.sid)
	ch.morality = -150 if str(su.sid) in ["xingxiu", "xuedao"] else 100
	if bool(su.personal):
		for m in su.masters.get(su.art, []):
			for r in m.get("requires", []):
				if r is Dictionary and str(r.get("type", "")) == "sect_master" and ch.sect_master == "":
					ch.sect_master = str(r.get("npc", ""))
	return ch

func _pace_spend(st: Dictionary, secs: float, regen := true) -> void:
	if secs <= 0.0:
		return
	Survival.tick(st.ch, secs, not regen, tables, st.opts)
	st.T = float(st.T) + secs

func _pace_walk(st: Dictionary, to: String) -> bool:
	if to == "" or to == str(st.room):
		return to != ""
	var n := _pace_steps(str(st.room), to)
	if n >= 999:
		return false
	_pace_spend(st, n * PACE_STEP_S)
	st.room = to
	return true

func _pace_shichen(t: float) -> String:
	return str(WorldClock.clock(t, 7200.0)["shichen_name"])

func _pace_day(t: float) -> int:
	return int(WorldClock.clock(t, 7200.0)["day"])   # 子時換日（同主機 QuestSystem.day_index）

## 這個技能現在的目標等級（門檻都到了但還打不過鬼時，入門武功與它的基本功每次再 +2）
func _pace_target(st: Dictionary, sk: String) -> int:
	var t := int(st.su.targets.get(sk, 0))
	if sk == str(st.su.art) or sk == str(st.su.base):
		t += int(st.get("bonus", 0)) * PACE_BONUS_LV
	return t

func _pace_qi_target(st: Dictionary) -> int:
	return PACE_QI_MAX + int(st.get("bonus", 0)) * PACE_BONUS_QI

## 技能門檻（§2.2 表＋實戰 9000）
func _pace_skill_gate(st: Dictionary) -> bool:
	var ch: Character = st.ch
	if int(ch.combat_xp) < PACE_XP:
		return false
	for sk in st.su.targets:
		if ch.skills.level(str(sk)) < int(st.su.targets[sk]):
			return false
	return true

## 到達第二階段：技能門檻＋（目標加碼後的）技能、氣上限，而且打得動 m_ghost（M3c2 審查 #1）
func _pace_done(st: Dictionary) -> bool:
	var ch: Character = st.ch
	if not _pace_skill_gate(st):
		return false
	if float(st.get("t_skill", -1.0)) < 0.0:
		st.t_skill = float(st.T)
	for sk in st.su.targets:
		if ch.skills.level(str(sk)) < mini(_pace_target(st, str(sk)), _pace_cap(ch, str(sk))):
			return false
	if int(ch.derived(tables, st.opts)["qi_max"]) < _pace_qi_target(st) and _pace_can_cultivate(st):
		return false
	if not tables.get("monsters", {}).has(PACE_GHOST):
		return true
	var g := _pace_ghost(st)
	if float(g.win) >= PACE_GHOST_WIN and float(g.qi) >= PACE_GHOST_QI:
		return true
	if int(st.get("bonus", 0)) < PACE_BONUS_MAX:
		st.bonus = int(st.get("bonus", 0)) + 1
	else:
		return true   # 加碼到上限還打不過：算到達（報表的「vs 鬼」欄會照實寫，case 判 FAIL）
	return false

## 門檻角色 vs m_ghost：滿狀態、兩把兵器取較好的；{ win, qi（勝場平均剩氣比例） }；依角色強度快取
var _pace_ghostc := {}
func _pace_ghost(st: Dictionary) -> Dictionary:
	var key := _pace_key(st, PACE_GHOST, 1) + "|%d|%d" % [int(st.ch.skills.level(str(st.su.art))), int(st.ch.cultivations)]
	if _pace_ghostc.has(key):
		return _pace_ghostc[key]
	var d := ch_derived_full(st)
	var best := { "win": -1.0, "qi": 0.0 }
	for use_cat in [true, false]:
		var spec := _pace_spec(st, use_cat)
		spec.qi = int(d.qi_max)
		spec.jing = int(d.jing_max)
		spec.neili = int(d.neili_max)
		spec.shen = int(d.shen_max)
		var w := 0
		var q := 0.0
		for i in PACE_GHOST_SIMS:
			var r := simulate_multi([spec], [PACE_GHOST], [], 9100 + i)
			if str(r.result) == "VICTORY" and bool(r.killed):
				w += 1
				q += float(r.qi_pct)
		var rate := w / float(PACE_GHOST_SIMS)
		if rate > float(best.win):
			best = { "win": rate, "qi": (q / w) if w > 0 else 0.0 }
	_pace_ghostc[key] = best
	return best

## 修練（打坐：內力滿了才會把內力化成氣上限 +8；次數上限 基本內功 × 5）還有沒有空間
func _pace_can_cultivate(st: Dictionary) -> bool:
	var ch: Character = st.ch
	var inner := ch.skills.level("basic_inner")
	return inner >= 1 and ch.cultivations < inner * Survival.CULTIVATE_PER_INNER

## (b2) 修練：氣上限還沒到目標 → 打坐一次（內力沒滿先補內力；滿了就修練）。每次精 2、10 秒冷卻（真的 Survival.meditate）
func _pace_try_cultivate(st: Dictionary) -> bool:
	var ch: Character = st.ch
	if int(ch.derived(tables, st.opts)["qi_max"]) >= _pace_qi_target(st) or not _pace_can_cultivate(st):
		return false
	if int(ch.vitals.jing) < Survival.MEDITATE_JING:
		return false
	# 精優先給學藝：還有學點可以學、精又不到六成 → 先不打坐（打坐每次精 2，會把回的精吃光）
	if ch.learn_points >= PACE_BATCH and int(ch.vitals.jing) < PACE_CULT_JING * int(ch.derived(tables, st.opts)["jing_max"]):
		return false
	var r := Survival.meditate(ch, tables, st.opts, float(st.T))
	if not bool(r.get("ok", false)):
		if str(r.get("reason", "")) == "busy":
			_pace_spend(st, PACE_MEDITATE_S)
			return true
		return false
	_pace_spend(st, PACE_MEDITATE_S)
	st.n_meditate = int(st.get("n_meditate", 0)) + 1
	return true

## (a) 雜務：門派對、時辰窗內（到做事房間時也在窗內）、不在冷卻、代價付得起、今天學點還沒遞減到 0
func _pace_try_chore(st: Dictionary) -> bool:
	var ch: Character = st.ch
	var day := _pace_day(st.T)
	if int(st.chore_day.day) != day:
		st.chore_day = { "day": day, "n": {} }
	for c in st.su.chores:
		var qid: String = c.qid
		if float(st.chore_cd.get(qid, -1.0)) > float(st.T):
			continue
		var n_today := int(st.chore_day.n.get(qid, 0))
		var got := Learning.chore_lp(c.chore, n_today, ch, tables, st.rules)
		if int(got.lp) <= 0:
			continue
		if Requirements.check(c.def.get("requires", []), ch, tables, st.opts, st.rules,
				{ Requirements.CTX_SHICHEN: _pace_shichen(st.T) }) != "":
			continue
		if Learning.chore_cost_reason(ch, c.chore) != "":
			continue
		# 走一遍路線估時間：房間動作要在時辰窗內
		var t: float = st.T
		var room: String = st.room
		var ok := true
		for step in c.route:
			t += _pace_steps(room, str(step.room)) * PACE_STEP_S
			room = str(step.room)
			if str(step.kind) == "ACT":
				var hs: Variant = step.get("hours", [])
				if hs is Array and not (hs as Array).is_empty() and not (_pace_shichen(t) in hs):
					ok = false
				if Requirements.check(step.get("requires", []), ch, tables, st.opts, st.rules) != "":
					ok = false
				t += PACE_ACT_S
			elif str(step.kind) == "FIGHT":
				if _pace_win(st, str(step.monster), 1) < PACE_WIN_MIN:
					ok = false   # 打不過的狩獵雜務先不接
				t += 60.0 * int(step.count)
			else:
				t += PACE_TALK_S
		if not ok:
			continue
		for step in c.route:
			_pace_walk(st, str(step.room))
			match str(step.kind):
				"ACT":
					_pace_spend(st, PACE_ACT_S)
				"FIGHT":
					for i in int(step.count):
						if _pace_fight(st, [str(step.monster)], "wild").result != "VICTORY":
							st.chore_cd[qid] = float(st.T) + 600.0   # 打輸了：這趟雜務作廢（模型簡化成放棄，10 分鐘後再說）
							return true
				_:
					_pace_spend(st, PACE_TALK_S)
		while Learning.chore_cost_reason(ch, c.chore) != "" and float(st.T) - float(st.t0) < PACE_MAX_H * 3600.0:
			_pace_spend(st, PACE_WAIT_S)
		var cost: Variant = c.chore.get("cost", {})
		if cost is Dictionary:
			for k in cost:
				ch.vitals[str(k)] = maxi(0, int(ch.vitals.get(str(k), 0)) - int(cost[k]))
		got = Learning.chore_lp(c.chore, int(st.chore_day.n.get(qid, 0)) if int(st.chore_day.day) == _pace_day(st.T) else 0, ch, tables, st.rules)
		if int(st.chore_day.day) != _pace_day(st.T):
			st.chore_day = { "day": _pace_day(st.T), "n": {} }
		st.chore_day.n[qid] = int(st.chore_day.n.get(qid, 0)) + 1
		ch.add_learn_points(int(got.lp), st.rules)
		Learning.note_novice_lp(ch, int(got.lp))
		st.lp_src.chore = int(st.lp_src.chore) + int(got.lp)
		var rw: Dictionary = c.def.get("outcomes", {}).get("default", {}).get("rewards", {})
		var sp := Learning.chore_prof(rw.get("skill_prof", {}), int(c.chore.get("prof_below", 50)), ch, tables)
		for sk in sp:
			ch.skills.add_prof(str(sk), int(sp[sk]), tables, _pace_cap(ch, str(sk)))
		st.chore_cd[qid] = float(st.T) + float(c.cd_s)
		st.n_chores = int(st.n_chores) + 1
		return true
	return false

func _pace_cap(ch: Character, sk: String) -> int:
	var mx := SkillBook.max_level_of(sk, tables)
	if SkillBook.kind_of(sk, tables) == SkillBook.KIND_LIFE:
		return mx
	return mini(mx, DerivedStats.art_level_cap(ch.combat_xp))

## 這個技能現在可以跟哪位師父學（check_master 通過的第一位，依上限高低）
func _pace_master(st: Dictionary, sk: String) -> String:
	for m in st.su.masters.get(sk, []):
		var nid := str(m.get("npc_id", ""))
		if Learning.check_master(st.ch, nid, sk, tables, st.opts, st.rules) == "":
			# 學費付不起一批（例：武館教頭收錢、身上只剩幾兩）→ 記下「要賺錢」，練功時改挑掉錢多的怪（M3c2 審查：丐幫新手常常身無分文）
			if int(m.get("price", 0)) * PACE_BATCH > int(st.ch.money):
				st.need_money = true
				continue
			return nid
	return ""

## 學一次要多少精／內力／神（新手加速後）
func _pace_learn_need(st: Dictionary, sk: String) -> Dictionary:
	var ch: Character = st.ch
	var wc := Learning.wit_cost(int(ch.effective_attrs(tables, st.opts)["wit"]))
	var nm := Learning.novice_mults(ch, sk, st.rules)
	var jing := maxi(1, roundi(int(wc.jing) * float(nm.jing))) if float(nm.jing) != 1.0 or float(nm.prof) != 1.0 else int(wc.jing)
	var neili := 0
	var shen := 0
	if SkillBook.kind_of(sk, tables) == SkillBook.KIND_SECT:
		var srow := CharData.sect_of_skill(tables, sk)
		var cost: Variant = srow.get("sect_skill_train_cost", srow.get("sect_skill_cost", []))
		if cost is Array:
			if (cost as Array).has("neili"):
				neili = Learning.SECT_NEILI_COST
			if (cost as Array).has("shen"):
				shen = Learning.SECT_SHEN_COST
	return { "jing": jing, "neili": neili, "shen": shen }

## (b) 學點 ≥ 10 且精夠 → 學門檻表裡完成度最低、沒被上限擋住的技能 10 次
func _pace_try_learn(st: Dictionary) -> bool:
	var ch: Character = st.ch
	if ch.learn_points < PACE_BATCH:
		return false
	var best := ""
	var best_r := 9.0
	var best_npc := ""
	for sk in st.su.targets:
		var tgt := _pace_target(st, str(sk))
		var lv := ch.skills.level(str(sk))
		if lv >= tgt or lv >= _pace_cap(ch, str(sk)):
			continue
		var nid := _pace_master(st, str(sk))
		if nid == "":
			continue
		var need := _pace_learn_need(st, str(sk))
		if int(ch.vitals.neili) < int(need.neili) or int(ch.vitals.shen) < int(need.shen):
			continue
		if int(ch.vitals.jing) < int(need.jing) * PACE_BATCH:
			continue
		var r := lv / float(tgt)
		if r < best_r:
			best_r = r
			best = str(sk)
			best_npc = nid
	if best == "":
		return false
	var npc_room := str(tables.get("npcs", {}).get(best_npc, {}).get("room", ""))
	var moved := npc_room != str(st.room)
	if not _pace_walk(st, npc_room):
		return false
	if moved:
		_pace_spend(st, PACE_TALK_S)
	st.need_money = false
	var res := Learning.learn(ch, best_npc, best, PACE_BATCH, tables, st.opts, st.rules)
	var n := int(res.get("times_done", 0))
	_pace_spend(st, n * PACE_LEARN_S)
	st.n_learn = int(st.n_learn) + n
	return n > 0

## 角色的戰鬥單位（真的 to_combatant）。use_cat：換成入門武功類別最便宜的兵器（拳腳＝空手）；否則用身上裝備的（創角的木刀）。
## 玩家會挑打得比較好的那一把：_pace_win 對兩種都算勝率、記下比較好的（_pace_wpick）
func _pace_spec(st: Dictionary, use_cat := false) -> Dictionary:
	var ch: Character = st.ch
	var spec := ch.to_combatant(tables, st.opts, 0, 0)
	spec.ai = "melee_basic"
	if use_cat:
		var cat := str(tables.get("martial_arts", {}).get(st.su.art, {}).get("category", "FIST"))
		var w := weapon_for(cat)
		spec.weapon = w
		spec.weapon_options = [w] if str(w.uid) != "" else []
	return spec

## 戰鬥：回傳 simulate_multi 的結果；勝利時發實戰、學點、銀兩（kind：wild／spar）；時間 = ticks × TICK ＋ 2.5 ＋ 6
func _pace_fight(st: Dictionary, mons: Array, kind: String) -> Dictionary:
	var ch: Character = st.ch
	var rng: RandomNumberGenerator = st.rng
	_pace_win(st, str(mons[0]), mons.size())   # 決定用哪把兵器（快取）
	var use_cat := bool(_pace_wpick.get(_pace_key(st, str(mons[0]), mons.size()), true))
	var r := simulate_multi([_pace_spec(st, use_cat)], mons, [], rng.randi())
	_pace_spend(st, int(r.ticks) * Battle.TICK, false)
	_pace_spend(st, PACE_BATTLE_END_S + PACE_SCOUT_S)
	ch.vitals.qi = maxi(1, int(r.qi))
	ch.vitals.jing = maxi(0, int(r.jing))
	ch.vitals.shen = maxi(0, int(r.shen))
	ch.vitals.neili = maxi(0, int(r.neili))
	st.n_fights = int(st.n_fights) + 1
	if str(r.result) == "VICTORY" and bool(r.killed):
		var xp0 := int(ch.combat_xp)
		var xp := 0
		var lp := 0
		var money := 0
		for mid in mons:
			var row: Dictionary = tables.get("monsters", {}).get(str(mid), {})
			if row.is_empty() or bool(row.get("no_rewards", false)):
				continue
			xp += BattleRewards.xp_for(row, xp0, 1.0)
			lp += BattleRewards.lp_for(row, xp0, 1.0)
			var mr: Variant = row.get("money", {})
			if mr is Dictionary and not (mr as Dictionary).is_empty():
				money += rng.randi_range(int(mr.get("min", 0)), maxi(int(mr.get("min", 0)), int(mr.get("max", 0))))
		if kind == "spar":
			if not Learning.is_novice(ch, tables, st.rules):
				lp = 0
			# M3c2 審查：一場最多 SPAR_LP_MAX、雜務＋切磋學點一輩子上限（同 SectSystem.spar_adjust）
			lp = mini(Learning.spar_lp(lp), Learning.novice_lp_left(ch, st.rules))
			Learning.note_novice_lp(ch, lp)
		ch.combat_xp += xp
		ch.add_learn_points(lp, st.rules)
		ch.money += money
		st.xp_src[kind] = int(st.xp_src.get(kind, 0)) + xp
		st.lp_src[kind] = int(st.lp_src.get(kind, 0)) + lp
	elif bool(r.get("dead", false)) and kind != "spar":
		# 戰敗（切磋除外）：回山門重來，氣剩 1【模型簡化：不扣實戰】
		_pace_spend(st, 120.0)
		st.room = st.su.gate_room
		st.deaths = int(st.deaths) + 1
	return r

## (c) 切磋：今天還有獎勵、氣 ≥ 60%
func _pace_try_spar(st: Dictionary) -> bool:
	var ch: Character = st.ch
	if str(st.su.spar_mon) == "" or st.rules.get("spar_rewards", false) != true:
		return false
	var day := _pace_day(st.T)
	if int(st.spar.day) != day:
		st.spar = { "day": day, "n": 0 }
	if int(st.spar.n) >= int(st.opts.get("spar_daily_cap", 30)):
		return false
	if int(ch.vitals.qi) < PACE_QI_FIGHT * int(ch.derived(tables, st.opts)["qi_max"]):
		return false
	# 幾乎打不過的切磋不打（勝率 < 30% 先去練功、學藝；輸了不扣東西，所以 30% 以上照打）【模型】
	if _pace_win(st, str(st.su.spar_mon), 1) < PACE_SPAR_WIN_MIN:
		return false
	_pace_walk(st, str(st.su.spar_room))
	_pace_spend(st, PACE_TALK_S)
	var r := _pace_fight(st, [str(st.su.spar_mon)], "spar")
	if str(r.result) == "VICTORY":
		st.spar.n = int(st.spar.n) + 1
	return true

func _pace_sig(st: Dictionary) -> String:
	var ch: Character = st.ch
	var tot := 0
	for sk in st.su.targets:
		tot += ch.skills.level(str(sk))
	return "%s_%d_%d_%d" % [st.su.sid, tot / 5, ch.skills.level(str(st.su.base)) / 5, int(ch.derived(tables, st.opts)["qi_max"]) / 40]

func _pace_key(st: Dictionary, mid: String, n: int) -> String:
	return "%s|%d|%s" % [mid, n, _pace_sig(st)]

func _pace_win(st: Dictionary, mid: String, n: int) -> float:
	var key := _pace_key(st, mid, n)
	if _pace_winrate.has(key):
		return float(_pace_winrate[key])
	var d := ch_derived_full(st)
	var mons: Array = []
	for i in n:
		mons.append(mid)
	var best := -1.0
	for use_cat in [true, false]:
		var spec := _pace_spec(st, use_cat)
		spec.qi = int(d.qi_max)
		spec.jing = int(d.jing_max)
		spec.neili = int(d.neili_max)
		spec.shen = int(d.shen_max)
		var w := 0
		for i in PACE_WINRATE_SIMS:
			var r := simulate_multi([spec], mons, [], 7000 + i)
			if str(r.result) == "VICTORY" and bool(r.killed):
				w += 1
		var rate := w / float(PACE_WINRATE_SIMS)
		if rate > best:
			best = rate
			_pace_wpick[key] = use_cat
	_pace_winrate[key] = best
	return best

func ch_derived_full(st: Dictionary) -> Dictionary:
	return (st.ch as Character).derived(tables, st.opts)

## (d) 出門練功一趟：勝率 ≥ 0.8 中實戰最高的怪，打 8 場（偵察：不是目標的怪就放過，每次 6 秒），氣 < 30% 就回
func _pace_try_hunt(st: Dictionary) -> bool:
	var ch: Character = st.ch
	var qmax := int(ch.derived(tables, st.opts)["qi_max"])
	if int(ch.vitals.qi) < PACE_QI_FIGHT * qmax:
		return false
	var best := {}
	var best_v := -1.0
	for h in st.su.hunt:
		var row: Dictionary = tables.get("monsters", {}).get(str(h.monster), {})
		if row.is_empty() or float(h.p) <= 0.0:
			continue
		if _pace_win(st, str(h.monster), ceili((int(h.lo) + int(h.hi)) / 2.0)) < PACE_WIN_MIN:
			continue
		var v := BattleRewards.xp_for(row, int(ch.combat_xp), 1.0) * (int(h.lo) + int(h.hi)) / 2.0
		if bool(st.get("need_money", false)):
			var mr: Variant = row.get("money", {})
			v = ((float(mr.get("min", 0)) + float(mr.get("max", 0))) / 2.0 if mr is Dictionary and not (mr as Dictionary).is_empty() else 0.0) * (int(h.lo) + int(h.hi)) / 2.0
		# 同樣的實戰：離山門近、遇到機率高的優先
		var cost := _pace_steps(str(st.su.gate_room), str(h.room)) * PACE_STEP_S * 2.0 / PACE_HUNT_N + (1.0 / float(h.p) - 1.0) * PACE_SCOUT_S
		var score := v / (60.0 + cost)
		if score > best_v:
			best_v = score
			best = h
	if best.is_empty():
		return false
	if not _pace_walk(st, str(best.room)):
		return false
	var rng: RandomNumberGenerator = st.rng
	for i in PACE_HUNT_N:
		if int(ch.vitals.qi) < PACE_QI_BACK * qmax:
			break
		# 偵察：要找到目標怪平均要擲 1/p 次，每次 6 秒（找到的那一次算在戰鬥時間裡）
		var tries := 1
		while rng.randf() >= float(best.p) and tries < 50:
			tries += 1
		_pace_spend(st, (tries - 1) * PACE_SCOUT_S)
		var mons: Array = []
		for k in rng.randi_range(int(best.lo), maxi(int(best.lo), int(best.hi))):
			mons.append(str(best.monster))
		var r := _pace_fight(st, mons, "wild")
		if str(r.result) != "VICTORY":
			break
	return true

## (e) 等：原地等回精回氣（客棧來回比較快就去休息）
func _pace_wait(st: Dictionary) -> void:
	var ch: Character = st.ch
	var d := ch.derived(tables, st.opts)
	var regen_per_s: float = ceilf(int(d.jing_max) * Survival.REGEN_PCT) / Survival.REGEN_INTERVAL_S
	var need := maxf(0.0, int(d.jing_max) * 0.9 - int(ch.vitals.jing))
	var wait_s := need / maxf(0.01, regen_per_s)
	var inn := str(st.su.inn_room)
	if inn != "" and ch.money >= int(st.su.inn_price):
		var trip := (_pace_steps(str(st.room), inn) + _pace_steps(inn, str(st.su.gate_room))) * PACE_STEP_S + PACE_TALK_S
		if trip < wait_s and trip < 600.0:
			_pace_walk(st, inn)
			_pace_spend(st, PACE_TALK_S)
			ch.money -= int(st.su.inn_price)
			Survival.rest_full(ch, tables, st.opts)
			st.n_inn = int(st.n_inn) + 1
			return
	_pace_spend(st, PACE_WAIT_S)
	st.wait_s = float(st.wait_s) + PACE_WAIT_S

## 一輪：回傳 { hours, lp_src, xp_src, ch, timeout }
func pace_run(su: Dictionary, sd: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd * 104729 + 17
	var opts := pace_options()
	var rules := pace_rules()
	var ch := _pace_new_char(su, rng, opts)
	var t0 := rng.randf_range(0.0, 7200.0)   # 起始時辰均勻隨機
	var st := { "ch": ch, "su": su, "rng": rng, "opts": opts, "rules": rules, "T": t0, "t0": t0, "room": su.gate_room,
		"lp_src": { "start": int(ch.learn_points), "chore": 0, "spar": 0, "wild": 0, "quest": 0 },
		"xp_src": { "spar": 0, "wild": 0 }, "chore_cd": {}, "chore_day": { "day": -1, "n": {} }, "spar": { "day": -1, "n": 0 },
		"n_fights": 0, "n_learn": 0, "n_chores": 0, "n_inn": 0, "deaths": 0, "wait_s": 0.0,
		"t_skill": -1.0, "bonus": 0, "n_meditate": 0 }
	var limit := t0 + PACE_MAX_H * 3600.0
	var next_trace := t0
	if pace_trace:
		var hs: PackedStringArray = []
		for h in su.hunt:
			hs.append("%s@%s(d%d p%.2f %d-%d)" % [h.monster, h.room, _pace_steps(str(su.gate_room), str(h.room)), float(h.p), int(h.lo), int(h.hi)])
		print("  hunt: " + ", ".join(hs))
	while not _pace_done(st) and float(st.T) < limit:
		if pace_trace and float(st.T) >= next_trace:
			next_trace += 1800.0
			var lv: PackedStringArray = []
			for sk in su.targets:
				lv.append("%s %d/%d" % [sk, ch.skills.level(str(sk)), int(su.targets[sk])])
			print("  [%.1fh] xp %d lp %d money %d jing %d/%d qi %d fights %d chores %d learn %d wait %.0fm deaths %d | %s" % [
				(float(st.T) - t0) / 3600.0, ch.combat_xp, ch.learn_points, ch.money, int(ch.vitals.jing),
				int(ch.derived(tables, opts).jing_max), int(ch.vitals.qi), int(st.n_fights), int(st.n_chores), int(st.n_learn),
				float(st.wait_s) / 60.0, int(st.deaths), ", ".join(lv)])
		if _pace_try_chore(st):
			continue
		if _pace_try_learn(st):
			continue
		if _pace_try_spar(st):
			continue
		if _pace_try_cultivate(st):
			continue
		if _pace_try_hunt(st):
			continue
		_pace_wait(st)
	var t_sk := float(st.t_skill) if float(st.t_skill) >= 0.0 else float(st.T)
	return { "hours": (float(st.T) - t0) / 3600.0, "timeout": not _pace_done(st), "st": st,
		"skill_hours": (t_sk - t0) / 3600.0, "active_hours": (float(st.T) - t0 - float(st.wait_s)) / 3600.0 }

static func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[clampi(int(floor(q * (s.size() - 1) + 0.5)), 0, s.size() - 1)])

func case_pace(sid: String, runs: int, seed0: int) -> int:
	var name := "pace_" + sid
	if not tables.get("sects", {}).has(sid) or not PACE_GATE.has(sid):
		return _skip(name, "門派 " + sid)
	if pace_spar_over.size() == 3:
		for mid in tables.get("monsters", {}):
			if Learning.is_spar_monster(str(mid)) and not bool(tables.monsters[mid].get("no_rewards", false)):
				tables.monsters[mid]["combat_xp"] = int(pace_spar_over[0])
				tables.monsters[mid]["combat_xp_ref"] = int(pace_spar_over[1])
				tables.monsters[mid]["learn_points"] = int(pace_spar_over[2])
	var su := _pace_setup(sid)
	var n := mini(runs, PACE_RUNS_MAX)
	var hours: Array = []
	var skill_hours: Array = []
	var active_hours: Array = []
	var human_hours: Array = []
	var meds := 0
	var bonus := 0
	var lp := { "start": 0, "chore": 0, "spar": 0, "wild": 0, "quest": 0 }
	var xp := { "spar": 0, "wild": 0 }
	var timeouts := 0
	var fights := 0
	var chores := 0
	var learns := 0
	var inns := 0
	var deaths := 0
	var waits := 0.0
	var finals: Array = []
	for i in n:
		var r := pace_run(su, seed0 + i)
		hours.append(float(r.hours))
		skill_hours.append(float(r.skill_hours))
		active_hours.append(float(r.active_hours))
		meds += int(r.st.get("n_meditate", 0))
		bonus += int(r.st.get("bonus", 0))
		if bool(r.timeout):
			timeouts += 1
		var st: Dictionary = r.st
		human_hours.append(float(r.hours) + (int(st.n_fights) * PACE_HUMAN_FIGHT_S + int(st.n_chores) * PACE_HUMAN_CHORE_S 			+ int(st.n_learn) * PACE_HUMAN_LEARN_S) / 3600.0)
		for k in lp:
			lp[k] = int(lp[k]) + int(st.lp_src.get(k, 0))
		for k in xp:
			xp[k] = int(xp[k]) + int(st.xp_src.get(k, 0))
		fights += int(st.n_fights)
		chores += int(st.n_chores)
		learns += int(st.n_learn)
		inns += int(st.n_inn)
		deaths += int(st.deaths)
		waits += float(st.wait_s)
		if finals.size() < 10:
			finals.append(st)
	var med := _pct(hours, 0.5)
	var band: Array = PACE_BAND.get(sid, PACE_BAND_DEFAULT)
	var earned := maxi(1, int(lp.chore) + int(lp.spar) + int(lp.wild) + int(lp.quest))
	var chore_share := int(lp.chore) / float(earned)
	var why: PackedStringArray = []
	if med < float(band[0]) or med > float(band[1]):
		why.append("中位數 %.2f 小時不在 %.1f–%.1f" % [med, float(band[0]), float(band[1])])
	if timeouts * 2 > n:
		why.append("過半數超過 %d 小時" % int(PACE_MAX_H))
	if not why.is_empty() and str(su.spar_mon) == "":
		# M3C2_PLAN 缺漏：本派沒有切磋弟子（m_<派>_dizi）→ 實戰只能靠野外怪（凍結），9000 實戰的門檻到不了
		why.append("本派沒有切磋弟子 m_%s_dizi（實戰只能打野外怪）：M3C2_PLAN 缺漏，交整合者" % str(tables.sects[sid].get("prefix", "")))
	if sid == "shaolin" and chore_share < PACE_CHORE_SHARE_MIN:
		why.append("雜務學點 %.0f%% < %.0f%%" % [chore_share * 100.0, PACE_CHORE_SHARE_MIN * 100.0])
	# 門檻角色 vs m_ghost（M3c2 審查 #1：通過條件；原 p2_vs_ghost 標準：勝率 ≥ 70%、剩氣 ≥ 25%）
	var gwin := 0.0
	var gqi := 0.0
	var gn := 0
	if tables.get("monsters", {}).has(PACE_GHOST):
		for fst in finals:
			var g := _pace_ghost(fst)
			gwin += float(g.win)
			gqi += float(g.qi)
			gn += 1
		gwin /= maxf(1.0, gn)
		gqi /= maxf(1.0, gn)
		if gwin < PACE_GHOST_WIN or gqi < PACE_GHOST_QI:
			why.append("門檻角色 vs 鬼 勝 %.0f%%／剩氣 %.0f%%（要 ≥ %.0f%%／≥ %.0f%%）" % [gwin * 100.0, gqi * 100.0, PACE_GHOST_WIN * 100.0, PACE_GHOST_QI * 100.0])
	var ok := why.is_empty()
	print("%-24s %s  median=%.2fh  P10=%.2fh  P90=%.2fh  含真人操作 median=%.2fh P90=%.2fh  runs=%d  timeout=%d  技能門檻 %.2fh  實際操作 %.2fh（等待 %.0f 分／輪）  學點來源 雜務 %.0f%%／切磋 %.0f%%／野外 %.0f%%（合計 %d／輪）  實戰 切磋 %.0f%%／野外 %.0f%%  戰鬥 %.0f／輪  雜務 %.0f／輪  學藝 %.0f 次／輪  打坐 %.0f／輪  加碼 %.1f  客棧 %.1f／輪  戰敗 %d  門檻 vs 鬼 勝 %.0f%% 剩氣 %.0f%%%s" % [
		name, "ok  " if ok else "FAIL", med, _pct(hours, 0.1), _pct(hours, 0.9), _pct(human_hours, 0.5), _pct(human_hours, 0.9), n, timeouts,
		_pct(skill_hours, 0.5), _pct(active_hours, 0.5), waits / 60.0 / n,
		int(lp.chore) * 100.0 / earned, int(lp.spar) * 100.0 / earned, int(lp.wild) * 100.0 / earned, earned / n,
		int(xp.spar) * 100.0 / maxi(1, int(xp.spar) + int(xp.wild)), int(xp.wild) * 100.0 / maxi(1, int(xp.spar) + int(xp.wild)),
		fights / float(n), chores / float(n), learns / float(n), meds / float(n), bonus / float(n), inns / float(n), deaths,
		gwin * 100.0, gqi * 100.0,
		"" if ok else "  (" + "；".join(why) + ")"])
	return 1 if ok else 0

## §2.5：一派所有雜務一個遊戲日的理論最大學點 ≤ CHORE_DAY_CAP_LP；最高本派武功 40 的角色只做雜務一個遊戲日 = 0 學點
func case_chore_bot_cap(_runs: int, _seed0: int) -> int:
	return _with_1_0b(func() -> int:
		var per := {}
		var per_lines: PackedStringArray = []
		var rules := pace_rules()
		var opts := pace_options()
		var bad: PackedStringArray = []
		for qid in tables.get("quests", {}):
			var q: Dictionary = tables["quests"][qid]
			var c: Variant = q.get("chore", null)
			if not (c is Dictionary):
				continue
			var sid := str(c.get("sect", ""))
			var hours: Array = []
			for r in q.get("requires", []):
				if r is Dictionary and str(r.get("type", "")) == "hour_in":
					hours = r.get("hours", [])
			var cd := maxf(1.0, float(q.get("repeat", {}).get("cooldown_days", 0.0)) * 7200.0)
			# 遊戲日 = floor(世界秒 / 7200)：一天從世界秒 0（辰時）開始；貪婪地在時辰窗內每隔冷卻做一次
			var count := 0
			var t := 0.0
			while t < 7200.0:
				var sc := str(WorldClock.clock(t, 7200.0)["shichen_name"])
				if hours.is_empty() or sc in hours:
					count += 1
					t += cd
				else:
					t += 60.0
			var dp: Array = c.get("decay_pct", [100])
			var lp := 0
			for k in count:
				lp += floori(int(c.get("lp", 0)) * int(dp[mini(k, dp.size() - 1)]) / 100.0)
			per[sid] = int(per.get(sid, 0)) + lp
		var ids: Array = per.keys()
		ids.sort()
		var ok := true
		for sid in ids:
			per_lines.append("%s %d" % [sid, int(per[sid])])
			if int(per[sid]) > CHORE_DAY_CAP_LP:
				ok = false
				bad.append(sid)
		# 過了新手期：最高本派武功 40 → 每件雜務學點 0
		var vet_zero := true
		for sid in ids:
			if not tables.get("sects", {}).has(sid):
				continue
			var su := { "sid": sid, "home": str(tables["sects"][sid].get("home_city", "xixia")), "gender": "M", "personal": false, "masters": {}, "art": "" }
			var rng := RandomNumberGenerator.new()
			var ch := _pace_new_char(su, rng, opts)
			var arts: Dictionary = tables.get("martial_arts", {})
			for aid in arts:
				if str(arts[aid].get("sect_id", "")) == sid and not bool(arts[aid].get("monster_only", false)):
					ch.skills.set_level(str(aid), 40, tables)
					break
			for qid in tables["quests"]:
				var c2: Variant = tables["quests"][qid].get("chore", null)
				if c2 is Dictionary and str(c2.get("sect", "")) == sid and int(Learning.chore_lp(c2, 0, ch, tables, rules).lp) != 0:
					vet_zero = false
		ok = ok and vet_zero
		print("%-24s %s  一個遊戲日理論最大學點（上限 %d）：%s；40 級角色 %s%s" % ["chore_bot_cap", "ok  " if ok else "FAIL",
			CHORE_DAY_CAP_LP, "、".join(per_lines), "0 學點" if vet_zero else "還有學點",
			"" if ok else "  (超過上限：%s)" % ", ".join(bad)])
		# M3c2 第二輪審查 #3：切磋不在 600 的雜務上限裡 → 另外報「雜務＋切磋」一個遊戲日的理論最大值
		# （切磋 = spar_daily_cap 場 × 一場最多 SPAR_LP_MAX；新角色實戰 0 時拿最多）。兩者合計受一輩子上限 novice_lp_cap 限制
		var cap_n := clampi(int(opts.get("spar_daily_cap", 30)), 0, 200)
		var both: PackedStringArray = []
		var mons: Dictionary = tables.get("monsters", {})
		for sid in ids:
			var srow: Dictionary = tables.get("sects", {}).get(sid, {})
			var mid := "m_hs_trainee" if sid == "huashan" else "m_%s_dizi" % str(srow.get("prefix", ""))
			var per_fight := Learning.spar_lp(BattleRewards.lp_for(mons.get(mid, {}), 0, 1.0)) if mons.has(mid) else 0
			both.append("%s %d＋%d＝%d" % [sid, int(per[sid]), cap_n * per_fight, int(per[sid]) + cap_n * per_fight])
		print("%-24s REPORT  雜務＋切磋（%d 場 × 一場最多 %d）一個遊戲日理論最大學點：%s；兩者合計一輩子上限 %d（novice_lp_cap）" % [
			"chore_bot_cap", cap_n, Learning.SPAR_LP_MAX, "、".join(both), int(rules.get("novice_lp_cap", 0))])
		return 1 if ok else 0)

## §3.3：P1 血刀（威嚇 10／50／100）對野狼出手，量「有威嚇／威嚇效果移除」的平均每擊傷害比 → 新／舊增傷比 ∈ [0.70, 0.80]
## 觸發的那一下傷害 = max(1, round(基礎 × HEAVY_MULT))：基礎傷害 = 觸發那一下 ÷ HEAVY_MULT（威嚇效果移除），沒觸發的不變。
## 舊增傷（期望值）= proc_chance(lv) × 0.5（M3a：×1.5、機率不打折）。
func case_xd_weihe_uplift(_runs: int, seed0: int) -> int:
	if not _has_art("xd_daofa") or not tables.get("monsters", {}).has("m_wolf"):
		return _skip("xd_weihe_uplift", "xd_daofa／m_wolf")
	var ok := true
	var parts: PackedStringArray = []
	for lv in WEIHE_LEVELS:
		var ps := sect_spec("P1", "xuedao", "xd_daofa", 20)
		ps.sect_skill = { "id": "weihe", "effect": "HEAVY", "level": lv }
		ps.skills["weihe"] = lv
		var wolf := Encounter.monster_spec("m_wolf", tables)
		wolf.qi = 1 << 28
		wolf.qi_max = 1 << 28
		var b := Battle.new(1, seed0 + lv, { "wait_mode": false, "escape_tiles": 2 })
		b.add_unit(ps)
		b.add_unit(wolf)
		b.start(tables)
		var me := b.unit(1)
		var foe := b.unit(2)
		me.pos = Vector2i(1, 3)
		foe.pos = Vector2i(2, 3)
		var dmg_sum := 0.0
		var base_sum := 0.0
		var hits := 0
		var procs := 0
		var tries := 0
		while hits < WEIHE_HITS and tries < WEIHE_HITS * 4:
			tries += 1
			me.jing = 9000
			me.neili = 9000
			me.qi = me.qi_max()
			foe.qi = 1 << 28
			me.state = BattleUnit.READY
			var cmd := { "cmd": "ATTACK", "target": [foe.pos.x, foe.pos.y] }
			if BattleRules.validate_cmd(b, me, cmd, tables) != "":
				me.state = BattleUnit.CHARGING
				continue
			var ev: Array = BattleRules.execute(b, me, cmd, tables, b.rng)
			var heavy := false
			var dmg := -1
			for e in ev:
				if str(e.key) == "battle_proc_HEAVY":
					heavy = true
				var p: Dictionary = e.p
				if int(p.get("atk_uid", 0)) == 1 and p.has("dmg") and not p.get("counter", false):
					dmg = int(p.dmg)
			if dmg <= 0:
				continue
			hits += 1
			dmg_sum += dmg
			if heavy:
				procs += 1
				base_sum += dmg / BattleStatus.HEAVY_MULT
			else:
				base_sum += dmg
		var up_new := dmg_sum / maxf(1.0, base_sum) - 1.0
		var up_old := BattleFormulas.proc_chance(lv) * 0.5
		var ratio := up_new / maxf(1e-9, up_old)
		parts.append("lv%d 觸發 %.1f%% 增傷 +%.2f%%（舊 +%.2f%%）比 %.2f" % [lv, procs * 100.0 / maxi(1, hits), up_new * 100.0, up_old * 100.0, ratio])
		if ratio < WEIHE_RATIO[0] or ratio > WEIHE_RATIO[1]:
			ok = false
	print("%-24s %s  %s%s" % ["xd_weihe_uplift", "ok  " if ok else "FAIL", "；".join(parts), "" if ok else "  (新／舊增傷比不在 0.70–0.80)"])
	return 1 if ok else 0

# ==== M3c2 WP-ECON ====
## M3C2_PLAN §4：製作經濟。回傳 [[名稱, Callable(runs, seed0) -> int]]
## - econ_hourly：每條生活技能鏈在等級 10／30／50 的每小時收入（EconModel；§4.1 時間模型），
##   對同階段戰鬥收入（§4.2：P1 打山豬、P2 打鬼、實戰 2 萬打山賊頭目；每場 行動數 × 2 秒＋60 秒，銀兩＋掉落賣店）。
##   等級 30、50：0.5–0.9 倍；等級 10：> 0 且 0.3–0.9 倍；每條鏈 10 ≤ 30 ≤ 50；hunt_tailor 只檢查 > 0、不遞減，
##   M3c2 審查 #5 起另外不能超過 0.9 倍（R7：生產收入低於同階段戰鬥）。
##   M3c2 審查 #6：製作鏈在等級 30、50 的最佳產物必須是製作技能的成品（製作比直接賣原料划算）。
## - econ_loop：商店買得到的材料（含多步驟閉包）做出來的成品，收購價一定低於材料最低買價（EconCalc.loop_violations）。
## [鏈 id, 技能, 只採集, 製作技能（M3c2 審查 #6：等級 30、50 這些技能的成品要比賣原料划算）]
const ECON2_CHAINS := [
	["g_farm", ["life_farming"], true, []],
	["g_wood", ["life_woodcut"], true, []],
	["g_fish", ["life_fishing"], true, []],
	["g_mine", ["life_mining"], true, []],
	["farm_cook", ["life_farming", "life_cooking"], false, ["life_cooking"]],
	["fish_cook", ["life_fishing", "life_woodcut", "life_cooking"], false, ["life_cooking"]],
	["wood_char", ["life_woodcut"], false, ["life_woodcut"]],
	["wood_carp", ["life_woodcut", "life_carpentry"], false, ["life_carpentry"]],
	["mine_smith", ["life_mining", "life_smithing"], false, ["life_smithing"]],
	["mine_sword", ["life_mining", "life_smithing", "life_swordsmith", "life_woodcut"], false, ["life_swordsmith"]],
	["ma_tailor", ["life_farming", "life_weaving", "life_tailoring"], false, ["life_weaving", "life_tailoring"]],
	["hunt_tailor", ["life_hunting", "life_weaving", "life_tailoring"], false, ["life_weaving", "life_tailoring"]],
]
## 製作要勝過賣原料的等級（M3c2 審查 #6）
const ECON2_CRAFT_WIN_LEVELS := [30, 50]
## M3c2 第二輪審查 #2：等級 10 的製作品每小時收入也要 > 0（製作不能一開始就賠錢），
## 例外只有研究的等級擋住的鏈（擁有者決定 O8；README「生活技能」同步）：
const ECON2_L10_CRAFT_EXEMPT := {
	"wood_char": "燒炭 20 級才開（研究 鐵心網：炭爐 30 級以上，本作已壓到 20）；10 級只能賣木材",
	"ma_tailor": "麻要種田 21 級才收得到（研究 鐵心網）；之前只能買麻種子，照 R8 一定虧；10 級只能賣稻米",
}
## [技能等級, 參考角色（精上限與戰鬥）, 練功怪, 報表標籤]
const ECON2_STAGES := [[10, "P1", "m_boar", "P1"], [30, "P2", "m_ghost", "P2"], [50, "20k", "m_bandit_chief", "20k"]]
const ECON2_BAND := { 10: [0.3, 0.9], 30: [0.5, 0.9], 50: [0.5, 0.9] }
const ECON2_HUNT_ONLY := ["hunt_tailor"]
const ECON2_HUNT_MONSTERS := ["m_hunt_yetu", "m_hunt_dayetu", "m_hunt_shanzhu", "m_hunt_lang", "m_hunt_xuehu"]
const ECON2_HUNT_FIGHT_S := 30.0   # （舊）打獵一場固定 30 秒——M3c2 審查 #5：比戰鬥基準（行動數 × 2 秒＋60 秒）快好幾倍，改用下面的模型
## M3c2 審查 #5：打獵一場的時間＝同階段參考角色打狩獵區獵物的平均行動數 × 2 秒＋ECON2_HUNT_OVERHEAD_S
## （和戰鬥基準同一個時間模型：每場另加 60 秒——結果畫面、在獵場找獵物、走位【設計提案】）
const ECON2_HUNT_OVERHEAD_S := 60.0
const ECON2_FIGHT_SIMS := 200

func econ2_cases() -> Array:
	return [
		["econ_hourly", case_econ_hourly],
		["econ_loop", case_econ_loop],
	]

## 參考角色的回精速度（精／秒）：精上限 × Survival.REGEN_PCT / REGEN_INTERVAL_S
func _econ2_regen(code: String) -> float:
	# §4.1：等級 10→P1、30→P2、50→P3 的精上限（等級 50 的戰鬥基準是實戰 2 萬，另算）
	var ps: Dictionary = player_spec("P3" if code == "20k" else code)
	return float(ps.jing_max) * Survival.REGEN_PCT / Survival.REGEN_INTERVAL_S

## 同階段戰鬥收入（兩／小時）：勝場（怪物真的死了）× 每場（銀兩＋掉落賣店）期望
func _econ2_combat_h(code: String, mid: String, runs: int, seed0: int) -> Dictionary:
	if not tables.get("monsters", {}).has(mid):
		return {}
	var party: Array = _p_party(20000, 1) if code == "20k" else [player_spec(code)]
	var n := mini(runs, ECON2_FIGHT_SIMS)
	var acts := 0
	var kills := 0
	for i in n:
		var r := simulate_multi(party, [mid], [], seed0 + i)
		acts += int(r.actions)
		if r.result == "VICTORY" and bool(r.get("killed", true)):
			kills += 1
	var per_fight_s := acts / float(maxi(1, n)) * 2.0 + 60.0
	var fights_h := 3600.0 / per_fight_s * kills / float(maxi(1, n))
	var ev := _base_ev(mid) + _loot_ev(mid)
	return { "h": ev * fights_h, "fights_h": fights_h, "ev": ev, "kill": kills / float(maxi(1, n)) }

## 打獵一場的秒數：參考角色對狩獵區每種獵物的平均行動數 × 2 ＋ ECON2_HUNT_OVERHEAD_S（獵物平均）
func _econ2_hunt_fight_s(code: String, runs: int, seed0: int) -> float:
	var party: Array = _p_party(20000, 1) if code == "20k" else [player_spec(code)]
	var n := mini(runs, 60)
	var tot := 0.0
	var nm := 0
	for mid in ECON2_HUNT_MONSTERS:
		if not tables.get("monsters", {}).has(mid):
			continue
		nm += 1
		var acts := 0
		for i in n:
			acts += int(simulate_multi(party, [mid], [], seed0 + i).actions)
		tot += acts / float(maxi(1, n)) * 2.0
	return (tot / maxf(1.0, nm)) + ECON2_HUNT_OVERHEAD_S

func case_econ_hourly(runs: int, seed0: int) -> int:
	return _with_1_0b(func() -> int:
		var ls: Dictionary = tables.get("life_skills", {})
		if not ls.has("life_hunting"):
			return _skip("econ_hourly", "life_hunting")
		var combat := {}
		var head: PackedStringArray = []
		for st in ECON2_STAGES:
			var c := _econ2_combat_h(st[1], st[2], runs, seed0)
			if c.is_empty():
				return _skip("econ_hourly", st[2])
			combat[st[0]] = c
			head.append("%s %s %.0f/h（%.1f 場×%.1f 兩）" % [st[3], st[2], c.h, c.fights_h, c.ev])
		print("%-24s REPORT  同階段戰鬥收入：%s" % ["econ_hourly", "；".join(head)])
		var base := { "tables": tables, "potion_per_jing": EconModel.potion_per_jing(tables),
			"hunt_monsters": ECON2_HUNT_MONSTERS, "hunt_fight_s": ECON2_HUNT_FIGHT_S }
		var hunt_s := {}
		var hs_txt: PackedStringArray = []
		for st in ECON2_STAGES:
			hunt_s[st[0]] = _econ2_hunt_fight_s(st[1], runs, seed0)
			hs_txt.append("%s %.0f 秒" % [st[3], float(hunt_s[st[0]])])
		print("%-24s REPORT  打獵一場（行動數 × 2＋%.0f 秒）：%s" % ["econ_hourly", ECON2_HUNT_OVERHEAD_S, "；".join(hs_txt)])
		var bad := 0
		for ch in ECON2_CHAINS:
			var cname: String = ch[0]
			if (ch[1] as Array).any(func(s): return not ls.has(s)):
				print("%-24s SKIP  %s 的技能還沒合併" % ["econ_hourly", cname])
				continue
			var parts: PackedStringArray = []
			var why: PackedStringArray = []
			var prev := -INF
			for st in ECON2_STAGES:
				var lv: int = st[0]
				var ch_h: float = combat[lv].h
				var b2 := base.duplicate()
				b2.regen = _econ2_regen(st[1])
				b2.hunt_fight_s = float(hunt_s[lv])
				var best := EconModel.chain_best(b2, ch[1], lv, ch[2], ch_h * 0.7 / 3600.0)
				var rate: float = best.rate
				var ratio := rate / maxf(1.0, ch_h)
				var craft_txt := ""
				if not (ch[3] as Array).is_empty():
					var cp := EconModel.craft_products(tables, ch[3], ch[1])
					var cb := EconModel.chain_best(b2, ch[1], lv, ch[2], ch_h * 0.7 / 3600.0, cp)
					craft_txt = "［製作 %s %.0f］" % [_econ2_item_name(str(cb.item)), float(cb.rate)]
					if lv in ECON2_CRAFT_WIN_LEVELS and float(cb.rate) < rate - 0.5:
						why.append("L%d 製作品（%s %.0f）不如賣原料（%s %.0f）" % [lv, _econ2_item_name(str(cb.item)), float(cb.rate),
							_econ2_item_name(best.item), rate])
					if lv == 10 and not (float(cb.rate) > 0.0):
						if ECON2_L10_CRAFT_EXEMPT.has(cname):
							craft_txt += "（練功期：%s）" % str(ECON2_L10_CRAFT_EXEMPT[cname])
						else:
							why.append("L10 製作品（%s %.0f）不賺錢" % [_econ2_item_name(str(cb.item)), float(cb.rate)])
				parts.append("L%d %s %.0f/h (%.2f×%s) %s%s" % [lv, best.mode, rate, ratio, st[3], _econ2_item_name(best.item), craft_txt])
				if cname in ECON2_HUNT_ONLY:
					var hb: Array = ECON2_BAND[lv]
					if not (rate > 0.0) or ratio > float(hb[1]):
						why.append("L%d %.2f×（> 0 且 ≤ %.1f）" % [lv, ratio, float(hb[1])])
				else:
					var band: Array = ECON2_BAND[lv]
					if not (rate > 0.0) or ratio < float(band[0]) or ratio > float(band[1]):
						why.append("L%d %.2f× 不在 %.1f–%.1f" % [lv, ratio, band[0], band[1]])
				if rate < prev - 0.5:
					why.append("L%d 比前一級少" % lv)
				prev = rate
			if not why.is_empty():
				bad += 1
			print("%-12s %s  %-11s %s%s" % ["econ_hourly", "ok  " if why.is_empty() else "FAIL", cname, "  ".join(parts),
				"" if why.is_empty() else "  ← " + "；".join(why)])
		return 1 if bad == 0 else 0)

func _econ2_item_name(id: String) -> String:
	return str(tables.get("items", {}).get(id, {}).get("name", id))

## 1.0A 與 1.0A＋1.0B 兩個視圖都檢查（1.0B 多了京城的商店與工匠）
func case_econ_loop(_runs: int, _seed0: int) -> int:
	var errs := EconCalc.loop_violations(tables)
	var n_a := EconCalc.closure_recipe_count(tables)
	var pct := EconCalc.min_buy_pct(tables)
	var box := { "n_b": 0, "errs_b": PackedStringArray() }   # lambda 抓的是值：用字典帶回結果
	_with_1_0b(func() -> int:
		box.errs_b = EconCalc.loop_violations(tables)
		box.n_b = EconCalc.closure_recipe_count(tables)
		return 1)
	var n_b: int = box.n_b
	for e in box.errs_b:
		if not (e in errs):
			errs.append("[1.0B] " + e)
	print("%-12s %s  商店材料循環 %d 條（最低買價 %d%%；閉包內配方 1.0A %d 條、1.0A＋1.0B %d 條）%s" % ["econ_loop",
		"ok  " if errs.is_empty() else "FAIL", errs.size(), pct, n_a, n_b, "" if errs.is_empty() else "：" + "；".join(errs)])
	return 1 if errs.is_empty() else 0
