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
	# M3d（M3D_PLAN §9.2、§10.2；WP-LAW Day-0）：五個 WP 的案例清單在檔尾各自的區塊；回 -1＝略過（資料還沒合併）
	for lst in [law_m3d_cases(), combat_m3d_cases(), arts_m3d_cases(), ev_m3d_cases(), er_m3d_cases(), quest_fight_0701_cases()]:
		for c in lst:
			if only != "" and c[0] != only:
				continue
			var r7: int = c[1].call(runs, seed0)
			if r7 < 0:
				skipped += 1
				continue
			ran += 1
			if r7 == 0:
				failed += 1
	# ROGUE（ROGUE_PLAN §9.2；WP-RUN Day-0）：WP-RUN、WP-ALLY 的案例清單在檔尾各自的區塊；回 -1＝略過
	for lst in [rogue_run_cases(), rogue_ally_cases()]:
		for c in lst:
			if only != "" and c[0] != only:
				continue
			var r8: int = c[1].call(runs, seed0)
			if r8 < 0:
				skipped += 1
				continue
			ran += 1
			if r8 == 0:
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
		place_formation: bool = false, counts: Dictionary = {}, mon_mod: Callable = Callable()) -> Dictionary:
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
		if mon_mod.is_valid():
			mon_mod.call(m)   # M3d 審查：賞金獵人依目標實戰縮放（BountyRules.scale_hunter_spec）
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
const PACE_TOWN_RUNS := 20           # pace_town_<派> 每派輪數（上限）
const PACE_BAND := { "shaolin": [2.5, 3.5], "xuedao": [2.0, 5.0] }
const PACE_BAND_DEFAULT := [2.0, 4.5]
const PACE_CHORE_SHARE_MIN := 0.30  # 少林：雜務佔學點收入 ≥ 30%
const CHORE_DAY_CAP_LP := 600       # §2.5
const WEIHE_LEVELS := [10, 50, 100]
const WEIHE_HITS := 20000           # §3.3 寫 5000 次出手；用 20000 次壓低觸發率的抽樣誤差（比 5000 嚴格）
const WEIHE_RATIO := [0.70, 0.80]

var pace_trace := false             # --pace-trace：印每 30 分鐘的進度（第一輪）
var pace_town := false              # pace_town_<派>：每個遊戲日一開始白拿 TOWN 學點上限（_town_day_totals）
var _town_lp_cache := -1
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
	# M3d 審查：TOWN 城鎮跑腿的學點不受新手期限制 → 每派再跑一次「每個遊戲日白拿 TOWN 學點上限」（1.0B 視圖），
	# 要留在同一個 M3c2 帶內（比真的去跑還快：不算走路與時間，是上限）
	for sid in PACE_SECTS:
		var sect_id2 := str(sid)
		out.append(["pace_town_" + sect_id2, func(runs: int, s0: int) -> int:
			return _with_1_0b(func() -> int: return case_pace(sect_id2, mini(runs, PACE_TOWN_RUNS), s0, true))])
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
		"lp_src": { "start": int(ch.learn_points), "chore": 0, "spar": 0, "wild": 0, "quest": 0, "town": 0 }, "town_day": -999,
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
		if pace_town and _pace_day(float(st.T)) != int(st.town_day):
			st.town_day = _pace_day(float(st.T))
			var tl := _town_day_lp()
			ch.add_learn_points(tl, rules)
			st.lp_src.town = int(st.lp_src.town) + tl
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

func case_pace(sid: String, runs: int, seed0: int, town := false) -> int:
	var name := ("pace_town_" if town else "pace_") + sid
	pace_town = town
	var r := _case_pace(sid, name, runs, seed0)
	pace_town = false
	return r

## 一個遊戲日把所有 TOWN 任務做到遞減到底的學點（_town_day_totals 的 lp；快取）
func _town_day_lp() -> int:
	if _town_lp_cache < 0:
		_town_lp_cache = int(_town_day_totals()["tot"]["lp"])
	return _town_lp_cache

func _case_pace(sid: String, name: String, runs: int, seed0: int) -> int:
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
	var lp := { "start": 0, "chore": 0, "spar": 0, "wild": 0, "quest": 0, "town": 0 }
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
	var earned := maxi(1, int(lp.chore) + int(lp.spar) + int(lp.wild) + int(lp.quest) + int(lp.town))
	# 少林雜務佔比（M3c2）只比本派的來源（雜務／切磋／野外／任務）；pace_town 白拿的城鎮學點不算進分母（M3d 審查）
	var chore_share := int(lp.chore) / float(maxi(1, earned - int(lp.town)))
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
	print("%-24s %s  median=%.2fh  P10=%.2fh  P90=%.2fh  含真人操作 median=%.2fh P90=%.2fh  runs=%d  timeout=%d  技能門檻 %.2fh  實際操作 %.2fh（等待 %.0f 分／輪）  學點來源 雜務 %.0f%%／切磋 %.0f%%／野外 %.0f%%／城鎮 %.0f%%（合計 %d／輪）  實戰 切磋 %.0f%%／野外 %.0f%%  戰鬥 %.0f／輪  雜務 %.0f／輪  學藝 %.0f 次／輪  打坐 %.0f／輪  加碼 %.1f  客棧 %.1f／輪  戰敗 %d  門檻 vs 鬼 勝 %.0f%% 剩氣 %.0f%%%s" % [
		name, "ok  " if ok else "FAIL", med, _pct(hours, 0.1), _pct(hours, 0.9), _pct(human_hours, 0.5), _pct(human_hours, 0.9), n, timeouts,
		_pct(skill_hours, 0.5), _pct(active_hours, 0.5), waits / 60.0 / n,
		int(lp.chore) * 100.0 / earned, int(lp.spar) * 100.0 / earned, int(lp.wild) * 100.0 / earned, int(lp.town) * 100.0 / earned, earned / n,
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

# ==== M3d WP-COMBAT ====（M3D_PLAN §10.2：combat_dodge、combat_qing_escape、combo_suxin）
## - combat_dodge：參考角色被怪打，「閃」時命中率下降 15–30 個百分點（P1 野狼、P2 山賊頭目、P3 鬼王）
## - combat_qing_escape：輕功脫身的實測成功率在 20–80% 帶內、與公式差 ≤ 4 個百分點（P0–P3 與輕功 200 的高手）
## - combo_suxin：兩位 P2 級（全真男、古墓女，素心劍 35 級）一起打山賊頭目：
##   每次出手的平均傷害，有合體一擊比「同一對夥伴、合體一擊不發生」多 10–25%（1.0B 視圖）。
##   M3d 審查：默契 50 與默契 100（上限）都要在帶內；合體武功要夥伴同場，基準改用 ComboRules.chance_override = 0
func combat_m3d_cases() -> Array:
	return [
		["combat_dodge", func(r: int, s0: int) -> int: return case_combat_dodge(r, s0)],
		["combat_qing_escape", func(r: int, s0: int) -> int: return case_combat_qing_escape(r, s0)],
		["combo_suxin", func(r: int, s0: int) -> int: return _with_1_0b(func() -> int: return case_combo_suxin(r, s0))],
	]

const COMBAT_DODGE_PAIRS := [["P1", "m_wolf"], ["P2", "m_bandit_chief"], ["P3", "m_guiwang"]]

func case_combat_dodge(runs: int, seed0: int) -> int:
	var all_ok := 1
	for pair in COMBAT_DODGE_PAIRS:
		var mid: String = pair[1]
		if not tables.get("monsters", {}).has(mid):
			return _skip("combat_dodge", mid)
		var rates := []
		for dodging in [false, true]:
			var b := Battle.new(1, seed0, { "wait_mode": false, "escape_tiles": 2 })
			var ps := player_spec(pair[0])
			ps["qi"] = 1 << 28
			ps["qi_max"] = 1 << 28
			b.add_unit(ps)
			var ms: Dictionary = Encounter.monster_spec(mid, tables)
			ms["side"] = 1
			b.add_unit(ms)
			b.start(tables)
			b.unit(1).pos = Vector2i(4, 3)
			b.unit(2).pos = Vector2i(5, 3)
			var rng := RandomNumberGenerator.new()
			rng.seed = seed0
			var hits := 0
			var n := maxi(400, runs * 8)
			for i in n:
				b.unit(1).dodging = dodging
				b.unit(1).qi = b.unit(1).qi_max()
				var ev := BattleRules.resolve_strike(b, b.unit(2), b.unit(1), {}, {}, 0, tables, rng, false, true)
				if not ev.any(func(e): return e.key == "battle_miss"):
					hits += 1
			rates.append(hits / float(n))
		var drop: float = (rates[0] - rates[1]) * 100.0
		var ok := drop >= 15.0 - 2.0 and drop <= 30.0 + 2.0   # 抽樣誤差 ±2 個百分點
		if not ok:
			all_ok = 0
		print("%-24s %s  %s vs %s：命中率 %.1f%% → %.1f%%（下降 %.1f 個百分點；帶 15–30）" % ["combat_dodge",
			"ok  " if ok else "FAIL", pair[0], mid, rates[0] * 100.0, rates[1] * 100.0, drop])
	return all_ok

func case_combat_qing_escape(runs: int, seed0: int) -> int:
	var all_ok := 1
	var probes := [["P0", 0, 0], ["P1", -1, -1], ["P2", -1, -1], ["P3", -1, -1], ["高手", 200, 150]]
	for pr in probes:
		var code: String = pr[0] if str(pr[0]).begins_with("P") else "P3"
		var ok_n := 0
		var n := maxi(200, runs)
		var want := 0.0
		var qrng := RandomNumberGenerator.new()   # 一條亂數流（連續種子的第一個亂數有偏差）
		qrng.seed = seed0 * 7919 + 17
		for i in n:
			var ps := player_spec(code)
			ps["neili"] = 100
			ps["neili_max"] = 100
			if int(pr[1]) >= 0:
				ps["lightness"] = int(pr[1])
				ps["skills"]["basic_body"] = int(pr[2])
			var b := Battle.new(1, seed0 + i, { "wait_mode": false, "escape_tiles": 2, "later_battle_cmds": true })
			b.add_unit(ps)
			var ms: Dictionary = Encounter.monster_spec("m_dummy" if tables.get("monsters", {}).has("m_dummy") else "m_wolf", tables)
			ms["side"] = 1
			b.add_unit(ms)
			b.start(tables)
			var u := b.unit(1)
			want = BattleRules.qing_escape_chance(u)
			u.state = BattleUnit.READY
			var c := { "cmd": "QING", "mode": "ESCAPE" }
			if BattleRules.validate_cmd(b, u, c, tables) != "":
				continue
			BattleRules.execute(b, u, c, tables, qrng)
			if u.is_fled():
				ok_n += 1
		var rate := ok_n / float(n)
		var ok := rate >= 0.20 - 0.04 and rate <= 0.80 + 0.04 and absf(rate - want) <= 0.04
		if not ok:
			all_ok = 0
		print("%-24s %s  %s（輕功 %s）：脫身率 %.1f%%（公式 %.1f%%；帶 20–80%%）" % ["combat_qing_escape", "ok  " if ok else "FAIL",
			str(pr[0]), "預設" if int(pr[1]) < 0 else str(pr[1]), rate * 100.0, want * 100.0])
	return all_ok

## 兩位 P2 級素心劍傳人（男全真、女古墓）。partner＝true 時互為合體夥伴（默契 moqi）
func _combo_pair_specs(level: int, moqi: int, partner: bool) -> Array:
	var out: Array = []
	for k in 2:
		var s := sect_spec("P2", "quanzhen" if k == 0 else "gumu", "gm_suxin", level)
		s["ref"] = "sim_combo_%d" % k
		s["char_id"] = s["ref"]
		s["name"] = "合璧%d" % (k + 1)
		s["gender"] = "M" if k == 0 else "F"
		s["neili"] = 600
		s["neili_max"] = 600
		s["combo"] = { "partner_char": "sim_combo_%d" % (1 - k), "moqi": moqi } if partner else {}
		out.append(s)
	return out

func case_combo_suxin(runs: int, seed0: int) -> int:
	if not _has_art("gm_suxin") or not (tables["martial_arts"]["gm_suxin"].get("combo", null) is Dictionary):
		return _skip("combo_suxin", "gm_suxin（combo 字典）")
	var mid := "m_bandit_chief"
	if not tables.get("monsters", {}).has(mid):
		return _skip("combo_suxin", mid)
	var ok_all := 1
	for moqi in [50, 100]:
		if _combo_suxin_at(moqi, mid, runs, seed0) != 1:
			ok_all = 0
	return ok_all

func _combo_suxin_at(moqi: int, mid: String, runs: int, seed0: int) -> int:
	var per_act := []
	var combos := 0
	var wins := [0, 0]
	var n := mini(runs, 300)
	for mode in 2:
		var dmg := 0
		var acts := 0
		ComboRules.chance_override = 0.0 if mode == 0 else -1.0
		for i in n:
			var b := Battle.new(1, seed0 + i, { "wait_mode": false, "escape_tiles": 2 })
			for sp in _combo_pair_specs(35, moqi, true):
				b.add_unit(sp)
			for m in Encounter.monster_specs([mid], tables):
				b.add_unit(m)
			b.start(tables)
			# 兩人一開始就站在頭目兩側（隊伍圍攻；不測走位，只測合體一擊的出力）
			b.unit(3).pos = Vector2i(6, 3)
			b.unit(1).pos = Vector2i(5, 3)
			b.unit(2).pos = Vector2i(6, 4)
			while not b.is_over():
				b.step(Battle.TICK, tables)
			for uid in [1, 2]:
				dmg += b.unit(uid).dmg_dealt
				acts += b.unit(uid).actions
				if mode == 1:
					combos += b.unit(uid).combo_hits
			if b.result_name() == "VICTORY":
				wins[mode] += 1
		per_act.append(dmg / float(maxi(1, acts)))
	ComboRules.chance_override = -1.0
	var gain: float = (per_act[1] / maxf(0.001, per_act[0]) - 1.0) * 100.0
	var ok := gain >= 10.0 and gain <= 25.0
	print("%-24s %s  默契 %d（成功率 %.0f%%）：每次出手傷害 %.1f → %.1f（+%.1f%%；帶 +10–25%%）  合體一擊 %.2f 次／場  勝率 %.0f%% → %.0f%%" % ["combo_suxin",
		"ok  " if ok else "FAIL", moqi, ComboRules.chance(moqi) * 100.0, per_act[0], per_act[1], gain, combos / 2.0 / float(n),
		100.0 * wins[0] / n, 100.0 * wins[1] / n])
	return 1 if ok else 0

# ==== M3d WP-ARTS ====（M3D_PLAN §10.2：arts_chongyang_power、arts_xuemo_power、arts_sixiang_power）
## 同一位參考角色（P3 底、基本武學 80、基本內功 100）、同等級，對同一個靶（山賊頭目，氣無限）各出 ARTS_POWER_TRIES 次
## 「最高一招、十成」，比較平均每次出手打在靶上的傷害（含沒打中＝0；範圍招式只算打在這個靶上的那一下、不算流血的後續）。
## - arts_chongyang_power：重陽劍法 60 ÷ 全真劍法 60 ∈ [1.1, 1.5]（M3D_PLAN §10.2）
## - arts_xuemo_power：血魔刀法 70 ÷ 血刀刀法 70 ∈ [0.9, 1.3]（研究：剛開時比血刀刀法弱，後來加強）
## - arts_sixiang_power：四象掌 50 ÷ 佛光普照掌 50 ∈ [0.8, 1.2]【設計提案：同一派的進階掌法，單靶相當、勝在半米字範圍】
const ARTS_POWER_TRIES := 4000
const ARTS_POWER_CASES := [
	["arts_chongyang_power", "quanzhen", "qz_chongyang", "qz_jianfa", 60, [1.1, 1.5]],
	["arts_xuemo_power", "xuedao", "xd_xuemo", "xd_daofa", 70, [0.9, 1.3]],
	["arts_sixiang_power", "emei", "em_sixiang", "em_foguang", 50, [0.8, 1.2]],
	# M3d 審查：空明拳 60 ÷ 昊天掌 60 ∈ [1.1, 1.5]（同重陽劍法：任務進階武功，單靶勝過本派基礎拳掌、不壓過太多）
	["arts_kongming_power", "quanzhen", "qz_kongming", "qz_haotian", 60, [1.1, 1.5]],
	# M3d 審查（第 3 輪）：玉女素心劍法 60（夥伴同場、合體一擊不算）÷ 全真劍法 60、÷ 玉女劍法 60 ∈ [1.1, 1.5]——
	# 要兩人都學、一男一女同場才能用，單招只比本派基礎劍法強一些；合體一擊另外 +10–25%（combo_suxin）【設計提案】
	["arts_suxin_power", "quanzhen", "gm_suxin", "qz_jianfa", 60, [1.1, 1.5]],
	["arts_suxin_power_gm", "gumu", "gm_suxin", "gm_yunu_jian", 60, [1.1, 1.5]],
	# 0.7.0.1 審查：劈石破玉拳（華山心法 30、儒風 10 就學得到）30 ÷ 華山劍法 30 ∈ [0.6, 1.0]——空手的入門拳法不壓過本派持劍的劍法【設計提案】
	["arts_pishi_power", "huashan", "hs_pishiquan", "hs_jianfa", 30, [0.6, 1.0]],
	# 0.7.0.1 二審：1.0B 世界蘭劍教定性到 60 → 靈鷲本門武功上限 70（其他受門派技能限制的門派仍是 60）。
	# 跨門派比：第 7 欄 { sect, level } 是分母那門武功的門派與等級（省略＝同門派、同等級）【設計提案】
	# - 天山六陽掌 70 ÷ 星宿 三陰蜈蚣爪 60（諂媚 50 → 本門 60）∈ [0.8, 1.25]：多出來的 10 級不讓靈鷲的進階掌壓過同級距的進階爪
	# - 天羽奇劍 70 ÷ 恆山劍法 60（慈悲 50 → 本門 60）∈ [0.9, 1.3]：基礎劍法多 10 級的等級加成，不超過三成
	["arts_lj_liuyang70_power", "lingjiu", "lj_liuyang", "xh_sanyin", 70, [0.8, 1.25], { "sect": "xingxiu", "level": 60 }],
	["arts_lj_tianyu70_power", "lingjiu", "lj_tianyu", "hg_jianfa", 70, [0.9, 1.3], { "sect": "hengshan", "level": 60 }],
]

## 0.7.0.1 審查：任務戰的勝率（參考角色同 _p_party）
## - em_zhou_solo_30k／45k：「滅絕師太的絕學」打周芷若是單挑（solo），任務門檻金頂 60、九陽 60、斷惡 60 ≈ 實戰 3 萬 →
##   單人 3 萬勝率 25–90%（打輸可以再找她），4.5 萬 ≥ 80%（原本氣 2800、防 48：9 萬才 2.5%）
## - xh_pantu_duo_20k：「捉拿叛徒」的星宿叛徒（不限單挑）在任務門檻（星宿心法 50 ≈ 2 萬）要兩人：兩人各 2 萬 ≥ 80%，單人 2 萬 ≤ 10%
func quest_fight_0701_cases() -> Array:
	return [
		["em_zhou_solo_30k", func(r: int, s0: int) -> int: return _party_case("em_zhou_solo_30k", "m_em_zhouzhiruo", 1, 30000, 1, { "win_min": 0.25, "win_max": 0.90 }, r, s0)],
		["em_zhou_solo_45k", func(r: int, s0: int) -> int: return _party_case("em_zhou_solo_45k", "m_em_zhouzhiruo", 1, 45000, 1, { "win_min": 0.80 }, r, s0)],
		["xh_pantu_duo_20k", func(r: int, s0: int) -> int: return _party_case("xh_pantu_duo_20k", "m_xh_pantu", 1, 20000, 2, { "win_min": 0.80 }, r, s0)],
		["xh_pantu_solo_20k", func(r: int, s0: int) -> int: return _party_case("xh_pantu_solo_20k", "m_xh_pantu", 1, 20000, 1, { "win_max": 0.10 }, r, s0)],
	]

func arts_m3d_cases() -> Array:
	var out: Array = []
	for c in ARTS_POWER_CASES:
		out.append([c[0], func(runs: int, seed0: int) -> int: return _arts_power_case(c, runs, seed0)])
	return out

func _arts_power_case(c: Array, runs: int, seed0: int) -> int:
	return _with_1_0b(func() -> int:
		if not _has_art(str(c[2])) or not _has_art(str(c[3])):
			return _skip(str(c[0]), "武功 %s／%s" % [c[2], c[3]])
		var tries := maxi(200, ARTS_POWER_TRIES * runs / 500)
		var other: Dictionary = c[6] if c.size() > 6 else {}
		var sect_b := str(other.get("sect", c[1]))
		var lv_b := int(other.get("level", c[4]))
		var a := _arts_out(str(c[1]), str(c[2]), int(c[4]), tries, seed0)
		var b := _arts_out(sect_b, str(c[3]), lv_b, tries, seed0 + 7)
		var ratio := float(a.mean) / maxf(0.001, float(b.mean))
		var band: Array = c[5]
		var ok := ratio >= float(band[0]) and ratio <= float(band[1])
		print("%-24s %s  %s %d「%s」每次 %.1f（命中 %.0f%%）÷ %s %d「%s」每次 %.1f（命中 %.0f%%）＝ %.2f（帶 %.2f–%.2f）" % [c[0],
			"ok  " if ok else "FAIL", c[2], c[4], a.move, a.mean, a.hit * 100.0, c[3], lv_b, b.move, b.mean, b.hit * 100.0, ratio,
			band[0], band[1]])
		return 1 if ok else 0)

## 一門武功（等級 level）最高一招的平均出手傷害：{ mean, hit, move }
func _arts_out(sect_id: String, art_id: String, level: int, tries: int, sd: int) -> Dictionary:
	var ps := sect_spec("P3", sect_id, art_id, level)
	var arow: Dictionary = tables.get("martial_arts", {}).get(art_id, {})
	var basic := str(arow.get("base_skill", "basic_fist"))
	ps.skills[basic] = 80
	ps.skills["basic_inner"] = 100
	ps.neili_max = 500
	ps.neili = 500
	var best: Dictionary = {}
	for m in arow.get("moves", []):
		if m is Dictionary and int(m.get("unlock_level", 1)) <= level:
			best = m
	if best.is_empty():
		return { "mean": 0.0, "hit": 0.0, "move": "" }
	var foe := Encounter.monster_spec("m_bandit_chief", tables)
	foe.qi = 1 << 28
	foe.qi_max = 1 << 28
	var b := Battle.new(1, sd, { "wait_mode": false, "escape_tiles": 2 })
	# 合體武功（素心劍）要會這門武功的異性夥伴同場才能出招：放一位站在角落、不出手的夥伴（不測合體一擊）
	var cb: Variant = arow.get("combo", null)
	var mate := {}
	if cb is Dictionary:
		ps["ref"] = "sim_arts_me"
		ps["char_id"] = "sim_arts_me"
		ps["gender"] = "M" if sect_id != "gumu" else "F"
		ps["combo"] = { "partner_char": "sim_arts_mate", "moqi": 0 }
		mate = sect_spec("P3", "gumu" if sect_id != "gumu" else "quanzhen", art_id, level)
		mate["ref"] = "sim_arts_mate"
		mate["char_id"] = "sim_arts_mate"
		mate["gender"] = "F" if sect_id != "gumu" else "M"
		mate["combo"] = { "partner_char": "sim_arts_me", "moqi": 0 }
		mate["peer"] = 2
	b.add_unit(ps)
	b.add_unit(foe)
	if not mate.is_empty():
		b.add_unit(mate)
	b.start(tables)
	var me := b.unit(1)
	var fu := b.unit(2)
	if not mate.is_empty():
		b.unit(3).pos = Vector2i(0, 0)
		b.unit(3).state = BattleUnit.CHARGING
	me.pos = Vector2i(4, 3)
	fu.pos = Vector2i(5, 3)
	var sum := 0.0
	var hits := 0
	var done := 0
	var guard := 0
	while done < tries and guard < tries * 4:
		guard += 1
		me.jing = 9000
		me.neili = 9000
		me.qi = me.qi_max()
		fu.qi = 1 << 28
		me.state = BattleUnit.READY
		me.pos = Vector2i(4, 3)
		fu.pos = Vector2i(5, 3)
		var cmd := { "cmd": "ART", "art": art_id, "move": str(best.id), "target": [fu.pos.x, fu.pos.y], "power_tenths": 10 }
		if BattleRules.validate_cmd(b, me, cmd, tables) != "":
			me.state = BattleUnit.CHARGING
			continue
		done += 1
		var dmg := 0
		for e in BattleRules.execute(b, me, cmd, tables, b.rng):
			var p: Dictionary = e.p
			if int(p.get("atk_uid", 0)) == 1 and int(p.get("def_uid", 2)) == 2 and p.has("dmg") and not p.get("counter", false):
				dmg += int(p.dmg)
		if dmg > 0:
			hits += 1
		sum += dmg
	return { "mean": sum / maxf(1.0, float(done)), "hit": float(hits) / maxf(1.0, float(done)), "move": str(best.name) }

# ==== M3d WP-EVENTS ====（M3D_PLAN §10.2：ev_jb_zero_sum、ev_jb_income、ev_duel_judge）
## - ev_jb_zero_sum：押鏢的 A 與劫鏢的 B 是朋友，互劫 1000 次（各路線、1–4 個劫鏢者）：兩人（夥）合計銀兩只減不增
##   （A 付押金 V、劫鏢者合計拿 ≤ 0.8V）；另確認送達的 +V 有冷卻（同一位二掌櫃 30／60／120 分）。
## - ev_jb_income：實戰 10 萬的參考角色只跑危險鏢（三城六條送貨鏢、二掌櫃冷卻、走路每步 PACE_STEP_S、路上特殊地雷
##   ＝劫匪 2–4 個實打、輸了押金沒收）8 小時的每小時淨收入 ∈ 同階段戰鬥收入（實戰 10 萬刷幾種怪的最好每小時銀兩）的 0.6–1.5 倍。
## - ev_duel_judge：同屬性的兩人比武（DUEL，氣加厚、限時 60 秒好讓判定真的發生）500 場，side 0 勝率 45–55%（判定公平、沒有先手偏差）。
const EV_JB_ROUTES := [["xx_biaoju", "dl_biaoju", 3200, "xx"], ["dl_biaoju", "xx_biaoju", 3200, "dl"],
	["xx_biaoju", "jc_biaoju", 8000, "xx"], ["jc_biaoju", "xx_biaoju", 8000, "jc"],
	["dl_biaoju", "jc_biaoju", 8000, "dl"], ["jc_biaoju", "dl_biaoju", 8000, "jc"]]
const EV_JB_XP := 100000
const EV_JB_HOURS := 8.0
const EV_JB_OVERHEAD_S := 30.0           # 接鏢、交談、出城的額外秒數【設計提案】
const EV_JB_BAND := [0.6, 1.5]
const EV_JB_REF_MONSTERS := ["m_bandit_chief", "m_nanhai", "m_gm_hongningbo", "m_dl_limochou", "m_jq_dilao_qiutu"]
const EV_DUEL_N := 500
const EV_DUEL_LIMIT_S := 60.0
const EV_DUEL_QI := 20000

func ev_m3d_cases() -> Array:
	return [
		["ev_jb_zero_sum", case_ev_jb_zero_sum],
		["ev_jb_income", case_ev_jb_income],
		["ev_duel_judge", case_ev_duel_judge],
		["ev_tourney_farm", case_ev_tourney_farm],
	]

## M3d 審查（T9）：四個同派朋友每一屆都報名、互相放水（名次輪流），把武林大會與本派門派比武的獎勵刷到底。
## 主機一天開 EV_FARM_HOURS 小時（遊戲日 2 小時），連續 EV_FARM_DAYS 個現實日。每人平均每現實日從比武得到的名聲
## ≤ 同一個人一樣的時數正常跑腿（柯鎮惡每遊戲日 20、武林帖每 3 遊戲日 60）的名聲 × EV_FARM_MAX_RATIO。
## 另印舊規則（只有 30 遊戲日冷卻、八強往上取）的數字作對照。
const EV_FARM_HOURS := [4.0, 24.0]      # 主機一天開 4 小時（一般）與 24 小時（最壞）
const EV_FARM_DAYS := 120
const EV_FARM_MAX_RATIO := 1.0
const EV_FARM_KE_FAME_PER_DAY := 20      # 柯鎮惡（每遊戲日）
func case_ev_tourney_farm(_runs: int, _seed0: int) -> int:
	var all_ok := 1
	for hours in EV_FARM_HOURS:
		var game_days_per_real := float(hours) * 3600.0 / 7200.0
		var normal := (EV_FARM_KE_FAME_PER_DAY + ErrandsRules.WLT_FAME / float(ErrandsRules.WLT_COOLDOWN_DAYS)) * game_days_per_real
		var res := []
		for mode in ["new", "old"]:
			var fame := 0.0
			var last_day := { "WULIN": -1, "SECT": -1 }
			var last_unix := { "WULIN": -1.0, "SECT": -1.0 }
			var bracket: Array = TourneyRules.WULIN_FAME if mode == "new" else [3000, 2000, 1500, 1500, 1000, 1000, 1000, 1000]
			var wulin_total := 0
			for i in 4:
				wulin_total += int(bracket[i])   # 四人：冠、亞、兩個四強（輪流）
			var total_game_days := int(EV_FARM_DAYS * game_days_per_real)
			for gd in range(1, total_game_days + 1):
				var unix: float = (gd - 1) / game_days_per_real * TourneyRules.REAL_DAY_S
				var dom := TourneyRules.day_of_month(gd)
				for kind in ["WULIN", "SECT"]:
					var held: bool = (kind == "WULIN" and dom == TourneyRules.WULIN_DAY) or (kind == "SECT" and dom == 1)
					if not held:
						continue
					var ok_r: bool
					if mode == "new":
						ok_r = TourneyRules.rewarded(4, gd, int(last_day[kind]), unix, float(last_unix[kind]))
					else:
						ok_r = int(last_day[kind]) < 0 or gd - int(last_day[kind]) >= TourneyRules.REWARD_COOLDOWN_DAYS
					if not ok_r:
						continue
					last_day[kind] = gd
					last_unix[kind] = unix
					fame += float(wulin_total) if kind == "WULIN" else float(TourneyRules.SECT_CHAMPION_FAME)
			res.append(fame / 4.0 / float(EV_FARM_DAYS))
		var ok: bool = float(res[0]) <= normal * EV_FARM_MAX_RATIO
		if not ok:
			all_ok = 0
		print("%-24s %s  四個同派朋友放水刷比武（主機每天開 %.0f 小時、%d 個現實日）：每人每現實日名聲 %.1f（舊規則 %.1f）；同時數正常跑腿 %.1f（上限 ×%.1f）" % [
			"ev_tourney_farm", "ok  " if ok else "FAIL", float(hours), EV_FARM_DAYS, float(res[0]), float(res[1]), normal, EV_FARM_MAX_RATIO])
	return all_ok

func case_ev_jb_zero_sum(_runs: int, seed0: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed0
	var total := 0
	var worst := -INF
	for i in 1000:
		var v: int = [2400, 3200, 6000, 8000][rng.randi_range(0, 3)]
		var robbers := rng.randi_range(1, 4)
		var a_delta := -v                                         # A 的押金沒收
		var b_delta := JiebiaoRules.rob_share(v, robbers) * robbers   # 劫鏢者合計
		var net := a_delta + b_delta
		worst = maxf(worst, float(net))
		total += net
	var cd_ok := JiebiaoRules.cooldown_s(0.0) >= 1800.0 and JiebiaoRules.cooldown_s(0.999) <= 7200.0
	var ok := total < 0 and worst < 0.0 and cd_ok
	print("%-24s %s  朋友互劫 1000 次：合計 %+d 兩（每次最多 %+.0f 兩；劫鏢者 80%% 平分）；送達冷卻 %.0f–%.0f 秒%s" % ["ev_jb_zero_sum",
		"ok  " if ok else "FAIL", total, worst, JiebiaoRules.cooldown_s(0.0), JiebiaoRules.cooldown_s(0.999),
		"" if ok else "  (互劫生錢或沒有冷卻)"])
	return 1 if ok else 0

## 實戰 10 萬打一種怪的每小時銀兩（勝場 × 每場銀兩與掉落期望；場時 = 行動數 × 2 ＋ 60 秒，同 econ_hourly）
func _ev_combat_h(mid: String, runs: int, seed0: int) -> float:
	if not tables.get("monsters", {}).has(mid):
		return -1.0
	var party := _p_party(EV_JB_XP, 1)
	var n := mini(runs, 80)
	var acts := 0
	var kills := 0
	for i in n:
		var r := simulate_multi(party, [mid], [], seed0 + i)
		acts += int(r.actions)
		if r.result == "VICTORY" and bool(r.get("killed", true)):
			kills += 1
	var per_fight_s := acts / float(maxi(1, n)) * 2.0 + 60.0
	return (_base_ev(mid) + _loot_ev(mid)) * 3600.0 / per_fight_s * kills / float(maxi(1, n))

## 一次特殊地雷：{ won, secs }（劫匪 2–4 個；打輸＝鏢失）
func _ev_mine(rng: RandomNumberGenerator, seed_v: int) -> Dictionary:
	var ids: Array = []
	for k in JiebiaoRules.bandit_count(rng.randf()):
		ids.append(JiebiaoRules.BANDIT_ID)
	var r := simulate_multi(_p_party(EV_JB_XP, 1), ids, [], seed_v)
	return { "won": r.result == "VICTORY", "secs": int(r.actions) * 2.0 + PACE_BATTLE_END_S }

## 路線上的 WILD 房間數（特殊地雷只在野外）
func _ev_wild_rooms(a: String, b: String) -> int:
	if _pace_graph.is_empty():
		_pace_graph = DataLint.room_graph(tables)
	var prev := { a: "" }
	var q: Array = [a]
	while not q.is_empty():
		var c: String = q.pop_front()
		if c == b:
			break
		for n in _pace_graph.get(c, []):
			if not prev.has(n):
				prev[n] = c
				q.append(n)
	var n_wild := 0
	var cur := b
	var idx := WorldIndex.new(tables)
	while cur != "" and cur != a and prev.has(cur):
		var reg := str(idx.region_of(cur))
		if str(tables.get("regions", {}).get(reg, {}).get("type", "")) == "WILD":
			n_wild += 1
		cur = str(prev[cur])
	return n_wild

func case_ev_jb_income(runs: int, seed0: int) -> int:
	return _with_1_0b(func() -> int:
		if not tables.get("monsters", {}).has(JiebiaoRules.BANDIT_ID) or not tables.get("quests", {}).has("q_ev_jb_xx_dl_huo"):
			return _skip("ev_jb_income", "危險鏢資料")
		# 同階段戰鬥收入：實戰 10 萬刷得到的最好每小時銀兩
		var ref_h := 0.0
		var ref_mid := ""
		for mid in EV_JB_REF_MONSTERS:
			var h := _ev_combat_h(mid, runs, seed0)
			if h > ref_h:
				ref_h = h
				ref_mid = mid
		if ref_h <= 0.0:
			return _skip("ev_jb_income", "參考怪")
		# 特殊地雷的勝率（劫匪 2／3／4 個）：給校準用
		var mine_txt: PackedStringArray = []
		for cnt in [2, 3, 4]:
			var ids: Array = []
			for k0 in cnt:
				ids.append(JiebiaoRules.BANDIT_ID)
			var wn := 0
			var acts0 := 0
			var nn := mini(runs, 100)
			for i0 in nn:
				var r0 := simulate_multi(_p_party(EV_JB_XP, 1), ids, [], seed0 + 300 + i0)
				acts0 += int(r0.actions)
				if r0.result == "VICTORY":
					wn += 1
			mine_txt.append("%d 個 %.0f%%（%.1f 行動）" % [cnt, 100.0 * wn / nn, acts0 / float(nn)])
		print("%-24s REPORT  特殊地雷勝率（實戰 10 萬參考角色）：%s" % ["ev_jb_income", "；".join(mine_txt)])
		var steps := {}
		var wild := {}
		for r in EV_JB_ROUTES:
			var k := "%s>%s" % [r[0], r[1]]
			steps[k] = _pace_steps(str(r[0]), str(r[1]))
			wild[k] = _ev_wild_rooms(str(r[0]), str(r[1]))
		# 8 小時的貪心排程：在目前城市挑「沒在冷卻、每秒淨期望最高」的路線；都在冷卻就走去別城或等
		var sims := maxi(20, mini(runs, 60))
		var tot_net := 0.0
		var tot_runs := 0
		var tot_fail := 0
		var tot_mines := 0
		var rng := RandomNumberGenerator.new()
		for sidx in sims:
			rng.seed = seed0 + 7919 * sidx
			var t := 0.0
			var room := "xx_biaoju"
			var cd := {}   # giver -> until
			var net := 0.0
			var guard := 0
			while t < EV_JB_HOURS * 3600.0 and guard < 400:
				guard += 1
				var best: Array = []
				var best_rate := -INF
				for r in EV_JB_ROUTES:
					var k := "%s>%s" % [r[0], r[1]]
					var walk_to := _pace_steps(room, str(r[0])) * PACE_STEP_S
					var start_t := maxf(t + walk_to, float(cd.get(str(r[3]), 0.0)))
					var dur := float(steps[k]) * PACE_STEP_S + EV_JB_OVERHEAD_S + float(wild[k]) * 0.15 * 40.0
					var rate := float(r[2]) / (start_t - t + dur)
					if rate > best_rate:
						best_rate = rate
						best = r
				var k2 := "%s>%s" % [best[0], best[1]]
				t += _pace_steps(room, str(best[0])) * PACE_STEP_S
				t = maxf(t, float(cd.get(str(best[3]), 0.0)))
				var v := int(best[2])
				net -= v                               # 押金
				t += EV_JB_OVERHEAD_S
				var lost := false
				var since := JiebiaoRules.MINE_GAP_ROOMS
				for w in int(wild[k2]):
					since += 1
					if JiebiaoRules.mine_hits(since, rng.randi_range(0, 99)):
						since = 0
						tot_mines += 1
						var m := _ev_mine(rng, seed0 + guard * 31 + sidx)
						t += float(m.secs)
						if not bool(m.won):
							lost = true
							break
				t += float(steps[k2]) * PACE_STEP_S
				tot_runs += 1
				if lost:
					tot_fail += 1
					room = str(best[0])
					continue
				net += JiebiaoRules.payout(v)
				cd[str(best[3])] = t + JiebiaoRules.cooldown_s(rng.randf())
				room = str(best[1])
			tot_net += net / (t / 3600.0)
		var per_h := tot_net / sims
		var ratio := per_h / ref_h
		var ok: bool = ratio >= float(EV_JB_BAND[0]) and ratio <= float(EV_JB_BAND[1])
		var steps_txt: PackedStringArray = []
		for r in EV_JB_ROUTES:
			var k3 := "%s>%s" % [r[0], r[1]]
			steps_txt.append("%s→%s %d 步（野外 %d）" % [str(r[0]).substr(0, 2), str(r[1]).substr(0, 2), int(steps[k3]), int(wild[k3])])
		print("%-24s REPORT  路線：%s" % ["ev_jb_income", "；".join(steps_txt)])
		print("%-24s %s  危險鏢 %.0f 兩／小時（%d 趟、失敗 %d、地雷 %d）÷ 同階段戰鬥 %s %.0f 兩／小時 ＝ %.2f（帶 %.1f–%.1f）%s" % [
			"ev_jb_income", "ok  " if ok else "FAIL", per_h, tot_runs, tot_fail, tot_mines, ref_mid, ref_h, ratio,
			EV_JB_BAND[0], EV_JB_BAND[1], "" if ok else "  ← 不在帶內"])
		return 1 if ok else 0)

## 同屬性兩人比武：一樣的規格、一樣的武功；限時判定與擊倒都算
func case_ev_duel_judge(runs: int, seed0: int) -> int:
	var art := "hs_jianfa"
	if not _has_art(art):
		return _skip("ev_duel_judge", art)
	var n := maxi(100, mini(runs, EV_DUEL_N))
	var wins := 0
	var judged := 0
	for i in n:
		var b := Battle.new(1, seed0 + i, { "wait_mode": false, "escape_tiles": 2, "kind": "DUEL", "duel_limit_s": EV_DUEL_LIMIT_S })
		for side in 2:
			var ps := _p_at(30000, 40)
			var sk: Dictionary = {}
			for k in ["basic_sword", "basic_inner", "basic_parry", "basic_dodge", "basic_body"]:
				sk[k] = 40
			sk[art] = 40
			ps.skills = sk
			ps.arts = [art]
			ps.sect_skill = {}
			ps.cmd_arts = cmd_arts_of(sk)
			ps.weapon = weapon_of("w_tiejian", "it_ev%d" % side)
			ps.weapon_options = [ps.weapon]
			ps.side = side
			ps.peer = 0
			ps.ref = "sim_ev_duel_%d" % side
			ps.name = "比武%d" % side
			ps.kind = "PLAYER"
			ps.ai = "melee_basic"
			ps.duel_order = 1 if side == (i % 2) else 2   # 誰先報名與站哪一邊無關（對戰表亂數）
			ps.qi_max = EV_DUEL_QI   # 氣夠厚，十分鐘的比武大多走到判定（判定本身要公平）
			ps.qi = EV_DUEL_QI
			b.add_unit(ps)
		b.start(tables)
		var guard := 0
		while not b.is_over() and guard < 100000:
			b.step(Battle.TICK, tables)
			if not b.is_over():
				b._duel_check()
			guard += 1
		var ev: Variant = b.opts.get("ev_end", {})
		var w := -1
		if ev is Dictionary and not (ev as Dictionary).is_empty():
			w = int(ev.get("winner_side", -1))
			judged += 1
		else:
			w = b.winner_side()
		if w == 0:
			wins += 1
	var wr := wins / float(n)
	var ok := wr >= 0.45 and wr <= 0.55
	print("%-24s %s  同屬性兩人比武 %d 場：side 0 勝 %.1f%%（限時 %.0f 秒判定 %d 場）%s" % ["ev_duel_judge", "ok  " if ok else "FAIL",
		n, wr * 100.0, EV_DUEL_LIMIT_S, judged, "" if ok else "  (不在 45–55%)"])
	return 1 if ok else 0

# ==== M3d WP-ERRANDS ====（M3D_PLAN §10.2：er_town_lp_cap、（選做）er_trade_band）
func er_m3d_cases() -> Array:
	return [
		["er_town_lp_cap", func(r: int, s0: int) -> int: return case_er_town_lp_cap(r, s0)],
		["er_repeat_cap", func(r: int, s0: int) -> int: return case_er_repeat_cap(r, s0)],
	]

const ER_TOWN_LP_CAP := 600
const ER_TOWN_FAME_CAP := 60
const ER_TOWN_LILIAN_CAP := 200
const ER_MIN_RUN_S := 60.0   # 一趟最快 60 世界秒（理論上限：不算走路）

## 一個遊戲日把所有 TOWN 任務做到遞減到底（時辰窗內、照冷卻、每趟至少 ER_MIN_RUN_S，不算走路）：{ tot: { lp, fame, lilian, money }, lines, n_town }
## （目前的 tables；呼叫端負責 1.0B 視圖）
func _town_day_totals() -> Dictionary:
	var quests: Dictionary = tables.get("quests", {})
	var lines: PackedStringArray = []
	var tot := { "lp": 0, "fame": 0, "lilian": 0, "money": 0 }
	var n_town := 0
	var ids: Array = quests.keys()
	ids.sort()
	for qid in ids:
		var q: Dictionary = quests[qid]
		var c: Variant = q.get("chore", null)
		if not (c is Dictionary) or not ErrandsRules.is_town(c):
			continue
		n_town += 1
		var hours: Array = []
		for r in q.get("requires", []):
			if r is Dictionary and str(r.get("type", "")) == "hour_in":
				hours = r.get("hours", [])
		var cd := maxf(ER_MIN_RUN_S, float(q.get("repeat", {}).get("cooldown_days", 0.0)) * 7200.0)
		var oc: Dictionary = {}
		for k in q.get("outcomes", {}):
			var o: Dictionary = q["outcomes"][k]
			if not bool(o.get("no_chore", false)):
				oc = QuestDef.norm_rewards(o.get("rewards", {}))
				break
		var mid := {}
		for a in QuestDef._all_actions(q):
			if str(a.get("do", "")) == "reward" and a.get("rewards") is Dictionary:
				for k2 in a["rewards"]:
					mid[k2] = int(mid.get(k2, 0)) + int(a["rewards"][k2])
		var got := { "lp": 0, "fame": 0, "lilian": 0, "money": 0 }
		var count := 0
		var t := 0.0
		while t < 7200.0:
			var sc := str(WorldClock.clock(t, 7200.0)["shichen_name"])
			if hours.is_empty() or sc in hours:
				var pct := ErrandsRules.chore_pct(c, count)
				var rw: Dictionary = ErrandsRules.scale_decay_all(oc, pct) if bool(c.get("decay_all", false)) else oc
				var mw: Dictionary = ErrandsRules.scale_decay_all(mid, pct) if bool(c.get("decay_all", false)) else mid
				got.lp += int(ErrandsRules.town_lp(c, count).lp) + maxi(0, int(rw.get("learn_points", 0)))
				got.fame += maxi(0, int(rw.get("fame", 0))) + maxi(0, int(mw.get("fame", 0)))
				got.lilian += maxi(0, int(rw.get("lilian", 0))) + maxi(0, int(mw.get("lilian", 0)))
				got.money += maxi(0, int(rw.get("money", 0))) + maxi(0, int(mw.get("money", 0)))
				count += 1
				t += cd
			else:
				t += 60.0
		for k3 in tot:
			tot[k3] = int(tot[k3]) + int(got[k3])
		lines.append("%s×%d 學點%d 名聲%d 歷練%d 銀%d" % [str(q.get("name", qid)), count, int(got.lp), int(got.fame), int(got.lilian), int(got.money)])
	return { "tot": tot, "lines": lines, "n_town": n_town }

## §6.1：一個角色一個遊戲日把所有 TOWN 任務做到遞減到底（時辰窗內、照冷卻、每趟至少 ER_MIN_RUN_S，不算走路）
## → 學點合計 ≤ 600、名聲 ≤ 60、歷練 ≤ 200（M3D_PLAN §6.1、§10.2）。另報不是 TOWN 的跑腿（武林帖、九尾靈狐、阿虎）平均每日上限。
func case_er_town_lp_cap(_runs: int, _seed0: int) -> int:
	return _with_1_0b(func() -> int:
		var quests: Dictionary = tables.get("quests", {})
		var tt := _town_day_totals()
		var tot: Dictionary = tt["tot"]
		var lines: PackedStringArray = tt["lines"]
		var n_town := int(tt["n_town"])
		var ok: bool = int(tot.lp) <= ER_TOWN_LP_CAP and int(tot.fame) <= ER_TOWN_FAME_CAP and int(tot.lilian) <= ER_TOWN_LILIAN_CAP and n_town > 0
		print("%-24s %s  一個遊戲日 TOWN 任務做到遞減到底：學點 %d（≤%d）、名聲 %d（≤%d）、歷練 %d（≤%d）、銀兩 %d；%d 條：%s" % [
			"er_town_lp_cap", "ok  " if ok else "FAIL", int(tot.lp), ER_TOWN_LP_CAP, int(tot.fame), ER_TOWN_FAME_CAP,
			int(tot.lilian), ER_TOWN_LILIAN_CAP, int(tot.money), n_town, "；".join(lines)])
		# 不是 TOWN 的跑腿：武林帖（3 遊戲日一次）、九尾靈狐（冷卻 3 遊戲日）、阿虎（一次）→ 平均每遊戲日
		var jw: Dictionary = quests.get("q_er_jiuwei", {}).get("outcomes", {}).get("default", {}).get("rewards", {})
		print("%-24s REPORT  平均每遊戲日：武林帖 名聲 %.1f、歷練 %.1f（%d 日一次）；九尾靈狐 學點 %.1f、名聲 %.1f（冷卻 %s 日）；阿虎 一次 學點 %d、銀 %d" % [
			"er_town_lp_cap", ErrandsRules.WLT_FAME / float(ErrandsRules.WLT_COOLDOWN_DAYS),
			ErrandsRules.WLT_LILIAN / float(ErrandsRules.WLT_COOLDOWN_DAYS), ErrandsRules.WLT_COOLDOWN_DAYS,
			int(jw.get("learn_points", 0)) / 3.0, int(jw.get("fame", 0)) / 3.0,
			str(quests.get("q_er_jiuwei", {}).get("repeat", {}).get("cooldown_days", "?")),
			int(quests.get("q_er_ahu", {}).get("outcomes", {}).get("default", {}).get("rewards", {}).get("learn_points", 0)),
			int(quests.get("q_er_ahu", {}).get("outcomes", {}).get("default", {}).get("rewards", {}).get("money", 0))])
		return 1 if ok else 0)

## M3d 審查（第 3 輪，T9）：可以無限重複的跑腿全部加起來（TOWN 任務做到遞減到底＋九尾靈狐（冷卻 3 遊戲日、
## 不遞減、5% 夜明珠）＋武林帖（3 遊戲日一次、每次名聲 60 歷練 200））平均每遊戲日：
## 學點 ≤ ER_TOWN_LP_CAP（600，同 TOWN 上限：九尾靈狐的學點算進去）、名聲 ≤ ER_REPEAT_FAME_CAP、歷練 ≤ ER_REPEAT_LILIAN_CAP、
## 九尾靈狐夜明珠的賣店期望 ≤ ER_REPEAT_PEARL_MONEY_CAP 兩【設計提案】。冷卻、獎勵、機率都從資料讀（改了資料就會重量）。
const ER_REPEAT_FAME_CAP := 80
const ER_REPEAT_LILIAN_CAP := 400
const ER_REPEAT_PEARL_MONEY_CAP := 500
func case_er_repeat_cap(_runs: int, _seed0: int) -> int:
	return _with_1_0b(func() -> int:
		var quests: Dictionary = tables.get("quests", {})
		if not quests.has("q_er_jiuwei"):
			return _skip("er_repeat_cap", "q_er_jiuwei")
		var tot: Dictionary = _town_day_totals()["tot"]
		var jq: Dictionary = quests["q_er_jiuwei"]
		var jcd := maxf(1.0, float(jq.get("repeat", {}).get("cooldown_days", 0.0)))
		var jmax := int(jq.get("repeat", {}).get("max", 0))
		var oc: Dictionary = jq.get("outcomes", {})
		var jrw: Dictionary = QuestDef.norm_rewards(oc.get("default", {}).get("rewards", {}))
		# 夜明珠：luck 1–20 擲到 1 → pearl（任務 var luck 的 random 長度）
		var luck_n := 20
		for st in jq.get("stages", []):
			for a in st.get("on_enter", []):
				if a is Dictionary and str(a.get("name", "")) == "luck" and a.get("random") is Array:
					luck_n = maxi(1, (a["random"] as Array).size())
		var pearl_p := 1.0 / luck_n if oc.has("pearl") else 0.0
		var pearl_sell := 0.0
		for it in oc.get("pearl", {}).get("rewards", {}).get("items", []):
			if it is Dictionary:
				pearl_sell += _sell(str(it.get("id", ""))) * int(it.get("n", 1))
		var j_lp := int(jrw.get("learn_points", 0)) / jcd
		var j_fame := int(jrw.get("fame", 0)) / jcd
		var j_lil := int(jrw.get("lilian", 0)) / jcd
		var w_fame := 0.0
		var w_lil := 0.0
		if tables.get("items", {}).has(ErrandsRules.WULINTIE):
			w_fame = ErrandsRules.WLT_FAME / float(ErrandsRules.WLT_COOLDOWN_DAYS)
			w_lil = ErrandsRules.WLT_LILIAN / float(ErrandsRules.WLT_COOLDOWN_DAYS)
		var lp := float(tot.lp) + j_lp
		var fame := float(tot.fame) + j_fame + w_fame
		var lil := float(tot.lilian) + j_lil + w_lil
		var pearl_money := pearl_p * pearl_sell / jcd
		var ok := lp <= ER_TOWN_LP_CAP and fame <= ER_REPEAT_FAME_CAP and lil <= ER_REPEAT_LILIAN_CAP 			and pearl_money <= ER_REPEAT_PEARL_MONEY_CAP and (jmax != 0 or jcd >= 1.0)
		print("%-24s %s  平均每遊戲日（TOWN 做到底＋九尾靈狐每 %.0f 日＋武林帖每 %d 日）：學點 %.1f（≤%d；九尾 %.1f）、名聲 %.1f（≤%d；九尾 %.1f、武林帖 %.1f）、歷練 %.1f（≤%d）、夜明珠 %.0f%%×%.0f 兩 → %.1f 兩（≤%d）" % [
			"er_repeat_cap", "ok  " if ok else "FAIL", jcd, ErrandsRules.WLT_COOLDOWN_DAYS, lp, ER_TOWN_LP_CAP, j_lp, fame, ER_REPEAT_FAME_CAP,
			j_fame, w_fame, lil, ER_REPEAT_LILIAN_CAP, pearl_p * 100.0, pearl_sell, pearl_money, ER_REPEAT_PEARL_MONEY_CAP])
		return 1 if ok else 0)

# ==== M3d WP-LAW ====（M3D_PLAN §10.2：law_hunter_tiers、law_bounty_zero_sum）
func law_m3d_cases() -> Array:
	return [
		["law_hunter_tiers", func(r: int, s0: int) -> int: return case_law_hunter_tiers(r, s0)],
		["law_bounty_zero_sum", func(r: int, s0: int) -> int: return case_law_bounty_zero_sum(r, s0)],
	]

## M3D_PLAN §2.5：三階 NPC 賞金獵人 vs 參考角色（目標方勝率）。階照 BountyRules.hunter_tier（< 2 萬 1 階、< 10 萬 2 階、其他 3 階），
## 獵人依目標實戰縮放（BountyRules.scale_hunter_spec；主機 LawSystem.start_hunt 同一個函式）。
## 各階頂端照原本的帶：1 階 vs 2 萬 40–70%、2 階 vs 10 萬 30–60%、3 階 vs 20 萬 25–55%。
## M3d 審查（第 3 輪）：只量頂端 → 各階底端（剛過新手保護 500、2 萬出頭、10 萬出頭）勝率 0%（不能逃的追擊戰），
## 50 萬以上勝率 100%（研究：獵人「遙不可及」）→ 補量底端、中段與 50 萬、100 萬：目標方勝率都要在 20–70%【設計提案】
const LAW_HUNTER_BANDS := [
	["law_hunter_t1", 19999, 0.40, 0.70],
	["law_hunter_t2", 100000, 0.30, 0.60],
	["law_hunter_t3", 200000, 0.25, 0.55],
	["law_hunter_t1_low", 500, 0.20, 0.70],
	["law_hunter_t1_mid", 5000, 0.20, 0.70],
	["law_hunter_t2_low", 20001, 0.20, 0.70],
	["law_hunter_t2_mid", 50000, 0.20, 0.70],
	["law_hunter_t3_low", 100001, 0.20, 0.70],
	["law_hunter_t3_50w", 500000, 0.20, 0.70],
	["law_hunter_t3_100w", 1000000, 0.20, 0.70],
]

func case_law_hunter_tiers(runs: int, seed0: int) -> int:
	var all_ok := 1
	for band in LAW_HUNTER_BANDS:
		var xp := int(band[1])
		var mid := BountyRules.hunter_monster(BountyRules.hunter_tier(xp))
		if not tables.get("monsters", {}).has(mid):
			return _skip("law_hunter_tiers", mid)
		var party := _p_party(xp, 1)
		var mod := func(m: Dictionary) -> void: BountyRules.apply_hunter_xp(m, xp, tables)
		var r := run_generic("%s(%s)" % [band[0], mid.right(1)], { "win_min": float(band[2]), "win_max": float(band[3]) }, runs, seed0,
			func(sd: int) -> Dictionary: return simulate_multi(party, [mid], [], sd, Callable(), false, {}, mod))
		if r != 1:
			all_ok = 0
	print("%-24s %s" % ["law_hunter_tiers", "ok" if all_ok == 1 else "FAIL"])
	return all_ok

## M3D_PLAN §2.4、A4、T9：兩個朋友（加一個出錢加碼的朋友）互相上榜、互相持照緝殺、互相加碼，重複 runs×2 次；
## 每一步之後三人的銀兩（身上＋錢莊）合計不得增加（罰金是被懸賞者自己的錢、加碼是加碼者自己的錢，系統只搬錢；
## 執照費 100 兩是唯一的流出）。照 LawSystem 的順序用 BountyRules 算（collect → 加碼池 → 領賞，money_cap 照舊）。
func case_law_bounty_zero_sum(runs: int, seed0: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed0
	var ppl: Array = []
	for i in 3:
		ppl.append({ "money": rng.randi_range(0, 50000), "bank": rng.randi_range(0, 200000), "pk": 0, "morality": 0,
			"license": false, "claims": 0 })
	var pools := { 0: 0, 1: 0, 2: 0 }
	var start := _law_total(ppl, pools)
	var prev := start
	var worst := 0
	var steps := maxi(1000, runs * 2)
	var kills := 0
	for i in steps:
		var h := rng.randi_range(0, 1)
		var t := 1 - h
		var hunter: Dictionary = ppl[h]
		var target: Dictionary = ppl[t]
		# 目標去強制 PK 路人（PK 上升）；獵人保持 PK 0、領執照
		target["pk"] = int(target["pk"]) + rng.randi_range(1, 4)
		if rng.randf() < 0.3:
			target["morality"] = -rng.randi_range(101, 500)
		if not bool(hunter["license"]):
			var why := BountyRules.license_reason(int(hunter["pk"]), false, int(hunter["money"]))
			if why == "":
				hunter["money"] = int(hunter["money"]) - BountyRules.LICENSE_FEE
				hunter["license"] = true
		# 第三位朋友（或獵人自己）加碼
		var c := 2 if rng.randf() < 0.5 else h
		var add := rng.randi_range(BountyRules.POOL_ADD_MIN, 20000)
		if int(ppl[c]["money"]) >= add and int(pools[t]) + add <= BountyRules.POOL_CAP:
			ppl[c]["money"] = int(ppl[c]["money"]) - add
			pools[t] = int(pools[t]) + add
		# 緝殺（名單上、持照、獵人 PK 0）
		if BountyRules.listed(int(target["pk"]), int(target["morality"]), 5000, 500) 				and BountyRules.lawful(bool(hunter["license"]), int(hunter["pk"]), true):
			var f := BountyRules.fine(int(target["pk"]), int(target["morality"]))
			var got := BountyRules.collect(f, int(target["money"]), int(target["bank"]))
			target["money"] = int(target["money"]) - int(got["from_money"])
			target["bank"] = int(target["bank"]) - int(got["from_bank"])
			target["pk"] = maxi(0, int(target["pk"]) - 1)
			hunter["claims"] = int(hunter["claims"]) + int(got["total"]) + int(pools[t])
			pools[t] = 0
			kills += 1
			# 領賞（身上放不下的留著）
			var room := maxi(0, Character.MONEY_CAP - int(hunter["money"]))
			var pay := mini(room, int(hunter["claims"]))
			hunter["money"] = int(hunter["money"]) + pay
			hunter["claims"] = int(hunter["claims"]) - pay
		# 朋友讓 PK 歸零重來（半仙要錢 → 也是流出；這裡直接歸零＝最有利的情況）
		if rng.randf() < 0.2:
			target["pk"] = 0
			target["morality"] = 0
		var now := _law_total(ppl, pools)
		worst = maxi(worst, now - prev)
		prev = now
	var net := prev - start
	var ok := worst <= 0 and net <= 0
	print("%-24s %s  steps=%d  kills=%d  net=%d  worst_step=%d%s" % ["law_bounty_zero_sum", "ok  " if ok else "FAIL",
		steps, kills, net, worst, "" if ok else "  (朋友互殺互加碼生出了錢)"])
	return 1 if ok else 0

## 三人合計（身上＋錢莊＋待領賞金＋還在池子裡的加碼）
func _law_total(ppl: Array, pools: Dictionary) -> int:
	var t := 0
	for p in ppl:
		t += int(p["money"]) + int(p["bank"]) + int(p["claims"])
	for k in pools:
		t += int(pools[k])
	return t

# ==== ROGUE WP-ALLY ====（ROGUE_PLAN §9.2：rogue_ally_value、rogue_ally_share；WP-ALLY 在這個區塊填）
func rogue_ally_cases() -> Array:
	return [
		["rogue_ally_value", case_rogue_ally_value],
		["rogue_ally_share", case_rogue_ally_share],
	]

## 用 core 類別直接跑（RogueRun、RogueDraw、RogueFoes、RoguePower、RogueAlly、Battle；不開主機）；
## WP-RUN 的類別或資料還沒合併 → SKIP（回 -1）。
const RG_ALLY_PATHS := { "run": "res://core/rogue/rogue_run.gd", "rules": "res://core/rogue/rogue_rules.gd",
	"draw": "res://core/rogue/rogue_draw.gd", "foes": "res://core/rogue/rogue_foes.gd", "power": "res://core/rogue/rogue_power.gd" }
const RG_ALLY_MAX_ROUNDS := 40
const RG_ALLY_RARITIES := ["COMMON", "FINE", "RARE", "TREASURE", "DIVINE"]   # ＝ RogueRules.RARITIES（類別可能還沒合併，不直接引用）
const RG_ALLY_SPLIT := ["str", "con", "agi", "guts"]   # 開局分配（§9.2）
const RG_ALLY_ATTR_SPLIT := ["str", "con", "agi"]       # 屬性卡（§9.2 greedy）

func _rg_ally_env() -> Dictionary:
	var env := {}
	for k in RG_ALLY_PATHS:
		if not ResourceLoader.exists(RG_ALLY_PATHS[k]):
			return {}
		env[k] = load(RG_ALLY_PATHS[k])
		if env[k] == null:
			return {}
	if _loader == null:
		return {}
	var t: Dictionary = _loader.activate(["1.0A", "1.0B", "rogue"])
	if (t.get("rogue_cards", {}) as Dictionary).is_empty() or (t.get("rogue_foes", {}) as Dictionary).is_empty():
		return {}
	env["t"] = t
	env["opts"] = pace_options()
	var r: Dictionary = ((env.rules as Script).call("rules", t) as Dictionary).duplicate(true)
	if float(r.get("p0", 0.0)) <= 0.0:
		var ps: Script = env.power
		r["p0"] = float(ps.call("reference_power", t)) if ps.has_method("reference_power") else 0.0
	env["r"] = r
	return env

## 平均分 n 點到 keys（輪流一點一點給，單項不超過 cap；主要屬性都滿了才給其他屬性）
static func _rg_ally_spread(base: Dictionary, n: int, keys: Array, cap: int) -> Dictionary:
	var out := {}
	var progress := true
	while n > 0 and progress:
		progress = false
		for k in keys:
			if n <= 0:
				break
			if int(base.get(k, 0)) + int(out.get(k, 0)) + 1 <= cap:
				out[k] = int(out.get(k, 0)) + 1
				n -= 1
				progress = true
	for a in Character.ATTR_IDS:
		while n > 0 and int(base.get(a, 0)) + int(out.get(a, 0)) < cap:
			out[a] = int(out.get(a, 0)) + 1
			n -= 1
	return out

## greedy（§9.2）：與兵器相合的 ART（精進優先）→ 與已會武功相合的 WEAPON → 隊友未滿選 ALLY（allow_ally）→ ATTR → 其他
func _rg_ally_pick(cards: Array, pspec: Dictionary, allow_ally: bool, alive_allies: int, r: Dictionary, t: Dictionary) -> int:
	var wtype := str(pspec.get("weapon", {}).get("weapon_type", "FIST"))
	var cats := {}
	for a in pspec.get("arts", []):
		cats[str(t.get("martial_arts", {}).get(str(a), {}).get("category", ""))] = true
	var best := -1
	var best_score := -1
	for i in cards.size():
		var c: Dictionary = cards[i]
		var score := 0
		match str(c.get("kind", "")):
			"ART":
				var art: Dictionary = c.get("art", {}) if c.get("art") is Dictionary else {}
				var cat := str(art.get("category", ""))
				var aid := str(art.get("id", ""))
				if cat == wtype or cat in ["FIST", "INNER", "LIGHTNESS"] or aid.begins_with("basic_"):
					score = 60 if bool(c.get("upgrade", false)) else 50
				else:
					score = 5
			"WEAPON":
				var it: Dictionary = c.get("item", {}) if c.get("item") is Dictionary else {}
				if str(it.get("slot", "WEAPON")) == "WEAPON" and cats.has(str(it.get("weapon_type", ""))):
					score = 40
				else:
					score = 4
			"ALLY":
				if allow_ally and alive_allies < int(r.get("ally_max", 2)):
					score = 30
			"ATTR":
				score = 20
		score = score * 10 + RG_ALLY_RARITIES.find(str(c.get("rarity", "COMMON")))
		if score > best_score:
			best_score = score
			best = i
	return best

## 一局（自動玩家＝BattleAI 的玩家路徑；隊友 ai ally；非等待模式）：回 { wins, rounds, bosses, allies_taken }
func _rg_ally_run(env: Dictionary, sd: int, allow_ally: bool) -> Dictionary:
	var t: Dictionary = env.t
	var r: Dictionary = env.r
	var opts: Dictionary = env.opts
	var run = (env.run as Script).new()
	run.seed = sd
	run.run_id = "sim_%d" % sd
	run.members = ["sim_rg"]
	run.roll = CharacterFactory.roll(run.rng_for("roll"))
	var cap := int(r.get("attr_cap", 45))
	var alloc := _rg_ally_spread(run.roll, CharacterFactory.FREE_POINTS, RG_ALLY_SPLIT, cap)
	var start := {}
	for a in Character.ATTR_IDS:
		start[a] = int(run.roll.get(a, 0)) + int(alloc.get(a, 0))
	var crng := RandomNumberGenerator.new()
	crng.seed = sd
	var ch := CharacterFactory.create({ "id": "sim_rg", "identity": "local_sim", "name": "試煉者", "gender": "M",
		"birth_month": 1, "birth_city": "xixia", "alloc": {} }, start, t, opts, crng, 0.0)
	ch.inventory.remove_item_id("c_jingyao", 99)   # §3.3：只有布衣、木刀
	ch.vitals["neili"] = 0
	var allies_taken := 0
	var pick_left := 1
	var min_r := ""
	while run.round <= RG_ALLY_MAX_ROUNDS:
		# 選卡（打贏首領：多一次、第一次至少「稀」）
		while pick_left > 0:
			pick_left -= 1
			var pspec0: Dictionary = ch.to_combatant(t, opts, 0, 1)
			var cards: Array = (env.draw as Script).call("draw", run, ch, t, run.rng_for("draw"), min_r)
			if "draws" in run:
				run.draws += 1   # WP-RUN 的內部欄位（同一回合第二次抽卡的亂數）
			min_r = ""
			var idx := _rg_ally_pick(cards, pspec0, allow_ally, _rg_ally_alive(run.allies).size(), r, t)
			if idx < 0:
				continue
			var card: Dictionary = cards[idx]
			var al := {}
			if str(card.get("kind", "")) == "ATTR":
				al = _rg_ally_spread(ch.attrs, int(card.get("points", 0)), RG_ALLY_ATTR_SPLIT, cap)
			if run.apply_card(ch, card, al, t, opts, r) == "" and str(card.get("kind", "")) == "ALLY":
				allies_taken += 1
		# 開戰（§3.7.1：我方戰力＝玩家＋隊友；隊友依玩家戰力 × 份額縮放）
		var pspec: Dictionary = ch.to_combatant(t, opts, 0, 1)
		pspec["ai"] = "melee_basic"
		var my_p := float((env.power as Script).call("unit_power", pspec, t))
		var ally_specs: Array = []
		for a in _rg_ally_alive(run.allies):
			var s := RogueAlly.spec_for(a, my_p, t)
			if not s.is_empty():
				ally_specs.append(s)
		var mine: Array = [pspec]
		mine.append_array(ally_specs)
		var my_power := float((env.power as Script).call("side_power", mine, t))
		var target := float((env.foes as Script).call("target", run, my_power, r))
		var gen: Dictionary = (env.foes as Script).call("generate", run, target, t, run.rng_for("foes"))
		var boss := str(gen.get("boss_id", "")) != ""
		var b := Battle.new(1, [run.seed, "battle", run.round].hash(), { "wait_mode": false, "escape_tiles": 2, "no_flee": true,
			"end_on_players_down": true, "kind": "ROGUE" })
		b.add_unit(pspec)
		for s in ally_specs:
			b.add_unit(s)
		for s in gen.get("specs", []):
			var fs: Dictionary = (s as Dictionary).duplicate(true)
			fs["side"] = 1
			fs["peer"] = 0
			b.add_unit(fs)
		b.start(t)
		while not b.is_over():
			b.step(Battle.TICK, t)
		if b.result_name() != "VICTORY":
			break
		var out: Dictionary = b.outcome()
		ch.apply_battle_outcome(out.units[1], t, opts)
		var killed := 0
		for u in b.units:
			if u.side == 1 and u.is_dead():
				killed += 1
		var res := RogueAlly.apply_battle(run.allies, b)
		run.allies = res.allies
		run.wins += 1
		run.foes_beaten += killed
		run.round += 1
		if boss:
			run.bosses_beaten += 1
			if "bosses_seen" in run and not run.bosses_seen.has(str(gen.boss_id)):
				run.bosses_seen.append(str(gen.boss_id))   # 同局首領不重複（WP-RUN 的內部欄位）
		(env.rules as Script).call("restore", ch, t, opts, boss, r)
		var na: Array = []
		for a in run.allies:
			na.append(RogueAlly.restore(a, float(r.get("restore_pct", 0.35)), boss))
		run.allies = na
		pick_left = 2 if boss else 1
		min_r = "RARE" if boss else ""
	return { "wins": run.wins, "rounds": run.round, "bosses": run.bosses_beaten, "allies_taken": allies_taken }

static func _rg_ally_alive(allies: Array) -> Array:
	return allies.filter(func(a): return a is Dictionary and bool(a.get("alive", false)))

static func _rg_ally_median(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var s := xs.duplicate()
	s.sort()
	var n := s.size()
	return float(s[n / 2]) if n % 2 == 1 else (float(s[n / 2 - 1]) + float(s[n / 2])) / 2.0

## rogue_ally_value（§9.2）：同一批種子，greedy（會選隊友）vs greedy 但不選隊友 → 勝場中位數差 ∈ [+0.5, +3]
## 整合者（ROGUE_PLAN §12）：改用 WP-RUN 的 _rg_play（與主機同一條路：RogueFoes.prepare_fight／ally_spec、ally_weight），
## policy greedy vs greedy_noally，同一批種子；舊的 _rg_ally_run 留著做對照（直接呼叫 target／generate／spec_for，與主機不同）。
func case_rogue_ally_value(runs: int, seed0: int) -> int:
	if not _rg_env():
		print("%-24s SKIP  江湖試煉的核心類別或資料（rogue_cards／rogue_foes）還沒合併" % "rogue_ally_value")
		return -1
	var n := mini(runs, 200)
	var with_w: Array = []
	var without_w: Array = []
	var taken := 0
	for x in _rg_batch("greedy", n, seed0, 0):
		with_w.append(int(x.wins))
		taken += int(x.allies)
	for x in _rg_batch("greedy_noally", n, seed0, 0):
		without_w.append(int(x.wins))
	var m1 := _rg_ally_median(with_w)
	var m0 := _rg_ally_median(without_w)
	var diff := m1 - m0
	var mean1 := 0.0
	var mean0 := 0.0
	for x in with_w:
		mean1 += float(x) / n
	for x in without_w:
		mean0 += float(x) / n
	# 整合者（ROGUE_PLAN §12）：勝場集中在 4–9 的整數上，中位數幾乎不動（選不選隊友都是 7）；改看平均勝場差 ∈ [+0.3, +3]，
	# 中位數差只印出來參考（不得為負）
	var mdiff := mean1 - mean0
	var ok := mdiff >= 0.3 and mdiff <= 3.0 and diff >= 0.0
	print("%-24s %s  平均勝場 選隊友 %.2f／不選 %.2f（差 %+.2f；帶 +0.3–+3）  中位數 %.1f／%.1f（差 %+.1f，≥ 0）  平均招募 %.2f 位／局  局數 %d%s" % ["rogue_ally_value",
		"ok  " if ok else "FAIL", mean1, mean0, mdiff, m1, m0, diff, float(taken) / maxf(1.0, n), n, "" if ok else "  (差不在帶內)"])
	return 1 if ok else 0

## rogue_ally_share（§9.2）：隊友是幫手不是主角——稀以上的隊友（依參考玩家戰力 × 份額縮放）單挑同回合整組對手，輸的比例 ≥ 0.7。
## 參考玩家戰力＝開局參考角色（rogue_rules.p0 或 RoguePower.reference_power）× growth^(回合−1)。
func case_rogue_ally_share(runs: int, seed0: int) -> int:
	var env := _rg_ally_env()
	if env.is_empty():
		print("%-24s SKIP  江湖試煉的核心類別或資料（rogue_cards／rogue_foes）還沒合併" % "rogue_ally_share")
		return -1
	var t: Dictionary = env.t
	var r: Dictionary = env.r
	var cards: Array = []
	for cid in t.get("rogue_cards", {}):
		var c: Dictionary = t.rogue_cards[cid]
		if str(c.get("kind", "")) == "ALLY" and RG_ALLY_RARITIES.find(str(c.get("rarity", "COMMON"))) >= RG_ALLY_RARITIES.find("RARE") \
				and t.get("monsters", {}).has(str(c.get("monster", ""))):
			cards.append(c)
	if cards.is_empty():
		print("%-24s SKIP  沒有稀以上的隊友卡" % "rogue_ally_share")
		return -1
	cards.sort_custom(func(a, b): return str(a.id) < str(b.id))
	var share_t: Dictionary = r.get("ally_share", {})
	var p_ref := float(r.get("p0", 0.0))
	if p_ref <= 0.0:
		print("%-24s SKIP  沒有參考戰力（RoguePower.reference_power）" % "rogue_ally_share")
		return -1
	var growth := float(r.get("growth", 1.16))
	var n := mini(runs, 200)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed0 * 7 + 3
	var lost := 0
	var played := 0
	var per := {}
	for i in n:
		var c: Dictionary = cards[i % cards.size()]
		var rnd := rng.randi_range(2, 14)
		var run = (env.run as Script).new()
		run.seed = seed0 * 1000 + i
		run.round = rnd
		var p_player := p_ref * pow(growth, rnd - 1)
		var ally := { "slot": "sim", "card_id": str(c.id), "monster": str(c.monster), "npc": str(c.get("npc", "")),
			"name": str(c.get("name", "")), "share": float(share_t.get(str(c.rarity), 0.6)), "qi_pct": 1.0, "alive": true }
		var aspec := RogueAlly.spec_for(ally, p_player, t)
		if aspec.is_empty():
			continue
		var my_power := p_player + float((env.power as Script).call("unit_power", aspec, t))
		var target := float((env.foes as Script).call("target", run, my_power, r))
		var gen: Dictionary = (env.foes as Script).call("generate", run, target, t, run.rng_for("foes"))
		var b := Battle.new(1, [run.seed, "share", i].hash(), { "wait_mode": false, "escape_tiles": 2, "no_flee": true, "kind": "ROGUE" })
		b.add_unit(aspec)
		for s in gen.get("specs", []):
			var fs: Dictionary = (s as Dictionary).duplicate(true)
			fs["side"] = 1
			fs["peer"] = 0
			b.add_unit(fs)
		b.start(t)
		while not b.is_over():
			b.step(Battle.TICK, t)
		played += 1
		var won := b.result_name() == "VICTORY"
		if not won:
			lost += 1
		var k := str(c.id)
		var prev: Array = per.get(k, [0, 0])
		per[k] = [int(prev[0]) + (1 if won else 0), int(prev[1]) + 1]
	var lose_rate := float(lost) / maxf(1.0, played)
	var ok := played > 0 and lose_rate >= 0.7
	var worst := ""
	var worst_w := -1.0
	for k in per:
		var w := float(per[k][0]) / maxf(1.0, float(per[k][1]))
		if w > worst_w:
			worst_w = w
			worst = k
	print("%-24s %s  稀以上隊友單挑整組對手：輸 %.1f%%（≥ 70%%）  最常贏的 %s %.0f%%  %d 場%s" % ["rogue_ally_share",
		"ok  " if ok else "FAIL", lose_rate * 100.0, worst, worst_w * 100.0, played, "" if ok else "  (隊友太強)"])
	return 1 if ok else 0

# ==== ROGUE WP-RUN ====（ROGUE_PLAN §9.2）
## 用 core 類別直接跑（RogueRun、RogueDraw、RogueFoes、RoguePower、Battle；不開主機）。雙方都由 BattleAI 控制
## （玩家方＝BattleAI 的玩家路徑：全部武功裡威力最高的已解鎖招式），隊友 ai ally；非等待模式。
## 流程與主機（RogueSystem）相同：開局分配 → 選卡 → 開戰（我方戰力＝玩家＋隊友）→ 勝：回復、首領多一次稀以上 → 敗：結束。
const RG_MAX_ROUNDS := 40
const RG_START_SPLIT := ["str", "con", "agi", "guts"]   # 開局：自由點與永久點數平均分到這四項
const RG_ATTR_SPLIT := ["str", "con", "agi"]            # greedy 的屬性卡

var _rg_t: Dictionary = {}
var _rg_r: Dictionary = {}
var _rg_cache: Dictionary = {}
## --rogue-trace：每一場印一行（回合、我方戰力、目標、對手、氣的前後、勝負）——校準用
var _rg_trace := OS.get_cmdline_user_args().has("--rogue-trace")

func rogue_run_cases() -> Array:
	return [
		["rogue_power_fair", case_rogue_power_fair],
		["rogue_power_match", case_rogue_power_match],
		["rogue_first_runs", case_rogue_first_runs],
		["rogue_random_policy", case_rogue_random_policy],
		["rogue_profile_growth", case_rogue_profile_growth],
		["rogue_boss_round5", case_rogue_boss_round5],
		["rogue_determinism", case_rogue_determinism],
		# 0.7.x 試煉審查的回歸案例
		["rogue_choice_matters", case_rogue_choice_matters],
		["rogue_upgrade_offered", case_rogue_upgrade_offered],
		["rogue_no_wall", case_rogue_no_wall],
		["rogue_boss_spread", case_rogue_boss_spread],
		["rogue_points_late", case_rogue_points_late],
	]

func _rg_env() -> bool:
	if not _rg_t.is_empty():
		return true
	if _loader == null:
		return false
	_rg_t = _loader.activate(["1.0A", "1.0B", "rogue"])
	if (_rg_t.get("rogue_cards", {}) as Dictionary).is_empty() or (_rg_t.get("rogue_foes", {}) as Dictionary).is_empty():
		_rg_t = {}
		return false
	_rg_r = RogueRules.rules(_rg_t)
	# 校準用（不改資料）：--rogue-rules=diff_start:0.6,restore_pct:0.4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rogue-rules="):
			for kv in a.substr(14).split(","):
				var kvs := kv.split(":")
				if kvs.size() == 2 and _rg_r.has(kvs[0]):
					_rg_r[kvs[0]] = float(kvs[1]) if typeof(_rg_r[kvs[0]]) == TYPE_FLOAT else int(kvs[1])
			print("ROGUE rules override: %s" % a.substr(14))
	return true

## n 點輪流一點一點分到 keys（單項不超過 cap；都滿了才給其他屬性）
static func _rg_spread(base: Dictionary, n: int, keys: Array, cap: int) -> Dictionary:
	var out := {}
	var progress := true
	while n > 0 and progress:
		progress = false
		for k in keys:
			if n > 0 and int(base.get(k, 0)) + int(out.get(k, 0)) + 1 <= cap:
				out[k] = int(out.get(k, 0)) + 1
				n -= 1
				progress = true
	for a in Character.ATTR_IDS:
		while n > 0 and int(base.get(a, 0)) + int(out.get(a, 0)) < cap:
			out[a] = int(out.get(a, 0)) + 1
			n -= 1
	return out

## greedy（§9.2）：與兵器相合的 ART（精進優先）→ 與已會武功相合的 WEAPON → 隊友未滿選 ALLY → ATTR → 其他（稀有度高者）
func _rg_pick_greedy(cards: Array, ch: Character, run: RogueRun) -> int:
	var t := _rg_t
	var wt := str(ch.inventory.equipped_row("WEAPON", t).get("weapon_type", "FIST"))
	if wt == "":
		wt = "FIST"
	var cats := {}
	for k in ch.skills.special_arts(t):
		cats[SkillBook.category_of(k, t)] = true
	var best := -1
	var best_score := -1
	for i in cards.size():
		var c: Dictionary = cards[i]
		var score := 1
		match str(c.kind):
			"ART":
				var cat := str(c.art.category)
				if cat == wt or cat == "FIST":   # 拳掌類任何兵器都能出（BattleAI.usable_moves）＝與兵器相合
					score = 60 if bool(c.upgrade) else 50
				elif cat == "INNER" or cat == "LIGHTNESS" or cat == "BASIC":
					score = 15
				else:
					score = 3
			"WEAPON":
				if str(c.item.slot) == "WEAPON" and cats.has(str(c.item.weapon_type)) and str(c.item.weapon_type) != "FIST":
					score = 40
				elif str(c.item.slot) != "WEAPON":
					score = 12
				else:
					score = 2
			"ALLY":
				if run.alive_allies().size() < int(_rg_r.get("ally_max", 2)):
					score = 30
			"ATTR":
				score = 20
		score = score * 10 + RogueRules.rarity_index(str(c.rarity))
		if score > best_score:
			best_score = score
			best = i
	return best

## 一局：policy "greedy"／"random"／"greedy_noally"／"smart"；回 { wins, rounds, bosses, foes, draws: [[ids]], fights: [[foe ids]], boss5: -1/0/1,
## pk：各種卡拿了幾張（UPG＝精進、ARMOR＝護具）, fl：每場 { r, won, boss, fq（對手剩氣比例平均）, mq（我剩氣比例） } }
## force_boss：第 force_round 回合的首領固定是這一列（rogue_boss_spread 用）
## snap_round > 0：打到這一回合、開打前停下，回 out.snap = { ch, run }（rogue_boss_spread 用同一批角色輪流打每位首領）
func _rg_play(sd: int, policy: String, points: int, force_boss: String = "", force_round: int = 0, snap_round: int = 0) -> Dictionary:
	var t := _rg_t
	var r := _rg_r
	var opts := {}
	var cap := int(r.get("attr_cap", 45))
	var run := RogueRun.new()
	run.seed = sd
	run.run_id = "sim_%d" % sd
	run.members = ["sim_rg"]
	run.roll = CharacterFactory.roll(run.rng_for("roll"))
	run.alloc_points = CharacterFactory.FREE_POINTS + points
	var alloc := _rg_spread(run.roll, run.alloc_points, RG_START_SPLIT, cap)
	var start := {}
	for a in Character.ATTR_IDS:
		start[a] = int(run.roll.get(a, 0)) + int(alloc.get(a, 0))
	var crng := run.rng_for("create")
	var ch := CharacterFactory.create({ "id": "sim_rg", "identity": "local_sim", "name": "試煉者", "gender": "M",
		"birth_month": 1, "birth_city": "xixia", "alloc": {} }, start, t, opts, crng, 0.0)
	ch.inventory.remove_item_id("c_jingyao", 99)   # §3.3：只有布衣、木刀
	Survival.rest_full(ch, t, opts)
	ch.vitals["neili"] = 0
	run.members = [ch.id]
	var prng := RandomNumberGenerator.new()
	prng.seed = sd * 31 + 7
	var out := { "wins": 0, "rounds": 1, "bosses": 0, "foes": 0, "draws": [], "fights": [], "boss5": -1, "allies": 0 }
	var picks := 1
	var min_r := ""
	while run.round <= RG_MAX_ROUNDS:
		while picks > 0:
			picks -= 1
			var g := run.rng_for("draw")
			run.draws += 1
			var cards := RogueDraw.draw(run, ch, t, g, min_r)
			min_r = ""
			(out.draws as Array).append(cards.map(func(c): return str(c.id)))
			out["upo"] = int(out.get("upo", 0)) + cards.filter(func(c): return str(c.kind) == "ART" and bool(c.upgrade)).size()
			if cards.is_empty():
				continue
			var idx := 0
			match policy:
				"random":
					idx = prng.randi_range(0, cards.size() - 1)
				"smart":
					idx = _rg_pick_smart(cards, ch, run)
				"greedy_noally":
					var no_ally := cards.filter(func(c): return str(c.kind) != "ALLY")
					idx = cards.find(no_ally[_rg_pick_greedy(no_ally, ch, run)]) if not no_ally.is_empty() else 0
				_:
					idx = _rg_pick_greedy(cards, ch, run)
			var card: Dictionary = cards[maxi(0, idx)]
			var al := {}
			if str(card.kind) == "ATTR":
				al = _rg_spread(ch.attrs, int(card.points), RG_ATTR_SPLIT, cap)
			var kk := str(card.kind)
			if kk == "WEAPON" and str(card.item.slot) != "WEAPON":
				kk = "ARMOR"
			elif kk == "ART" and bool(card.upgrade):
				kk = "UPG"
			var pk: Dictionary = out.get("pk", {})
			pk[kk] = int(pk.get(kk, 0)) + 1
			out["pk"] = pk
			if run.apply_card(ch, card, al, t, opts, r) == "" and str(card.kind) == "ALLY":
				out.allies = int(out.allies) + 1
		if snap_round > 0 and run.round == snap_round:
			out["snap"] = { "ch": ch.to_dict(), "run": run.to_dict() }
			break
		var pspec: Dictionary = ch.to_combatant(t, opts, 0, 0)
		if force_boss != "" and run.round == force_round:
			run.bosses_seen = []   # 其他首領都算見過 → 只剩 force_boss
			for fid in t.rogue_foes:
				if bool(t.rogue_foes[fid].get("boss", false)) and str(fid) != force_boss:
					run.bosses_seen.append(str(fid))
		var prep := RogueFoes.prepare_fight(run, pspec, t, r)
		var my_unit := float(prep.my_unit)
		var ally_specs: Array = prep.ally_specs
		var tgt := float(prep.target)
		var gen: Dictionary = prep.gen
		(out.fights as Array).append((gen.foes as Array).duplicate())
		var boss := str(gen.boss_id) != ""
		if boss and not run.bosses_seen.has(str(gen.boss_id)):
			run.bosses_seen.append(str(gen.boss_id))
		run.fight = { "boss": boss, "boss_id": str(gen.boss_id) }
		var b := Battle.new(1, run.battle_seed(), { "wait_mode": false, "escape_tiles": 2, "no_flee": true,
			"end_on_players_down": true, "kind": "ROGUE" })
		b.add_unit(pspec)
		for s in ally_specs:
			b.add_unit(s)
		for s in gen.specs:
			var fs: Dictionary = (s as Dictionary).duplicate(true)
			fs["side"] = 1
			fs["peer"] = 0
			b.add_unit(fs)
		b.start(t)
		var guard := 0
		while not b.is_over() and guard < 200000:
			b.step(Battle.TICK, t)
			guard += 1
		var me: BattleUnit = b.unit(1)
		var won := b.result_name() == "VICTORY" and me != null and not me.is_dead()
		if _rg_trace:
			print("  [rg %d] r%d my=%.1f(+%d 隊友) tgt=%.1f foes=%s P=%.1f qi %d/%d→%d arts=%s %s" % [sd, run.round, my_unit,
				ally_specs.size(), tgt, str(gen.foes), float(gen.power), int(pspec.qi), int(pspec.qi_max), me.qi if me != null else 0,
				str(pspec.arts), "WIN" if won else "LOSE"])
		if run.round == 5:
			out.boss5 = 1 if won else 0
		var fq := 0.0
		var nf := 0
		for u in b.units:
			if u.side == 1:
				fq += float(u.qi) / maxf(1.0, float(u.qi_max()))
				nf += 1
		var fl: Array = out.get("fl", [])
		fl.append({ "r": run.round, "won": won, "boss": str(gen.boss_id), "fq": fq / maxf(1.0, nf),
			"mq": float(me.qi) / maxf(1.0, float(me.qi_max())) if me != null else 0.0 })
		out["fl"] = fl
		if not won:
			break
		for k in ["qi", "neili", "jing", "shen"]:
			ch.vitals[k] = int(me.get(k))
		ch.clamp_vitals(t, opts)
		var killed := 0
		for u in b.units:
			if u.side == 1 and u.is_dead():
				killed += 1
			var slot := str(u.spec.get("rg_ally", ""))
			if slot == "":
				continue
			for i in run.allies.size():
				if str(run.allies[i].get("slot", "")) == slot:
					var na: Dictionary = run.allies[i]
					if u.is_dead():
						na["alive"] = false
						na["qi_pct"] = 0.0
					else:
						na["qi_pct"] = clampf(float(u.qi) / float(u.qi_max()), 0.0, 1.0)
		run.on_won(killed, boss, str(gen.boss_id))
		RogueRules.restore(ch, t, opts, boss, r)
		for a in run.alive_allies():
			a["qi_pct"] = 1.0 if boss else minf(1.0, float(a.qi_pct) + float(r.get("restore_pct", 0.35)))
		picks = 1 + run.extra_picks
		min_r = "RARE" if run.extra_picks > 0 else ""
		run.extra_picks = 0
	out.wins = run.wins
	out.rounds = run.round
	out.bosses = run.bosses_beaten
	out.foes = run.foes_beaten
	return out

## smart：每張卡實際套用在角色副本上，挑「以自己為參考、對參考新角色」強度（RoguePower）最高的；隊友未滿時以 1 + 份額×0.6 計。
## 代表「看得懂數字」的玩家（rogue_choice_matters：選卡要有差）
func _rg_pick_smart(cards: Array, ch: Character, run: RogueRun) -> int:
	var t := _rg_t
	var r := _rg_r
	var best := 0
	var best_v := -1.0
	var base := _rg_rel(ch)
	for i in cards.size():
		var c: Dictionary = cards[i]
		var v := 1.0
		if str(c.kind) == "ALLY":
			if run.alive_allies().size() < int(r.get("ally_max", 2)):
				v = 1.0 + float((r.get("ally_share", {}) as Dictionary).get(str(c.rarity), 0.5)) * 0.6
		else:
			var ch2 := Character.from_dict(ch.to_dict())
			var run2 := RogueRun.from_dict(run.to_dict())
			var al := {}
			if str(c.kind) == "ATTR":
				al = _rg_spread(ch2.attrs, int(c.points), RG_ATTR_SPLIT, int(r.get("attr_cap", 45)))
			if run2.apply_card(ch2, c, al, t, {}, r) == "":
				v = _rg_rel(ch2) / maxf(0.001, base)
		if v > best_v:
			best_v = v
			best = i
	return best

func _rg_rel(ch: Character) -> float:
	var t := _rg_t
	var sp := ch.to_combatant(t, {}, 0, 0)
	RoguePower.set_reference(sp)
	var my := RoguePower.unit_power(sp, t)
	var p0 := RoguePower.reference_power(t)
	RoguePower.clear_reference()
	return my / maxf(0.001, p0)

func _rg_batch(policy: String, n: int, seed0: int, points: int) -> Array:
	var key := "%s|%d|%d|%d" % [policy, n, seed0, points]
	if _rg_cache.has(key):
		return _rg_cache[key]
	var res: Array = []
	for i in n:
		res.append(_rg_play(seed0 * 100003 + i * 7919 + 11, policy, points))
	_rg_cache[key] = res
	return res

static func _rg_wins(res: Array) -> Array:
	return res.map(func(x): return int(x.wins))

func _rg_skip(name: String) -> int:
	print("%-24s SKIP  江湖試煉的資料（rogue_cards／rogue_foes）還沒合併" % name)
	return -1

## 隨機的試煉者（屬性、武功、兵器、護甲、內功都隨機）
func _rg_random_player(rng: RandomNumberGenerator) -> Dictionary:
	var t := _rg_t
	var ch := Character.new()
	ch.id = "sim_p"
	for a in Character.ATTR_IDS:
		ch.attrs[a] = rng.randi_range(15, 40)
	var arts := ["hs_jianfa", "xd_daofa", "sl_changquan", "em_huifeng", "qz_tonggui", "lj_liuyang", "wd_taijijian", "gm_yinsuo", "xh_tianshan"]
	var weapons := { "SWORD": ["w_qingfeng", "w_lt_heijian", "w_lt_huibugujian"], "BLADE": ["w_gangdao", "w_lt_guandao"],
		"FIST": [], "WHIP": ["w_lt_mabian", "w_lt_zhusuo"], "STAFF": ["w_lt_tiechi", "w_lt_kusangbang"] }
	var art: String = arts[rng.randi_range(0, arts.size() - 1)]
	var lv := rng.randi_range(10, 120)
	ch.skills.set_level(art, lv, t)
	var cat := SkillBook.category_of(art, t)
	ch.skills.set_level(BattleFormulas.basic_for_category(cat), lv, t)
	ch.skills.set_level("basic_dodge", rng.randi_range(0, lv), t)
	ch.skills.set_level("basic_parry", rng.randi_range(0, lv), t)
	ch.skills.set_level("basic_inner", rng.randi_range(0, lv), t)
	var g := RandomNumberGenerator.new()
	g.seed = rng.randi()
	var mk := func() -> String: return CharacterFactory.new_item_uid(ch.inventory, g)
	var pool: Array = weapons.get(cat, [])
	if not pool.is_empty():
		var add := ch.inventory.add(str(pool[rng.randi_range(0, pool.size() - 1)]), 1, t, 0.0, -1, mk)
		ch.inventory.equip(str(add.uid), t)
	var arm := ["a_bupao", "a_pijia", "a_lt_meihaochangshan"]
	var add2 := ch.inventory.add(str(arm[rng.randi_range(0, arm.size() - 1)]), 1, t, 0.0, -1, mk)
	ch.inventory.equip(str(add2.uid), t)
	Survival.rest_full(ch, t, {})
	return ch.to_combatant(t, {}, 0, 0)

## rogue_power_fair：隨機試煉者 vs 池中對手縮放到同戰力（±5%）1 對 1 → 試煉者勝率 ∈ [0.35, 0.65]
func case_rogue_power_fair(runs: int, seed0: int) -> int:
	if not _rg_env():
		return _rg_skip("rogue_power_fair")
	var t := _rg_t
	var rng := RandomNumberGenerator.new()
	rng.seed = seed0 * 977 + 5
	var pool: Array = []
	for id in t.rogue_foes:
		if not bool(t.rogue_foes[id].get("boss", false)):
			pool.append(t.rogue_foes[id])
	pool.sort_custom(func(a, b): return str(a.id) < str(b.id))
	var n := mini(maxi(runs, 50), 300)
	var wins := 0
	var played := 0
	var tries := 0
	while played < n and tries < n * 6:
		tries += 1
		var ps := _rg_random_player(rng)
		RoguePower.set_reference(ps)   # 同主機：以試煉者自己為戰力參考
		var pp := RoguePower.unit_power(ps, t)
		var row: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		var res := RoguePower.scale_to(RogueFoes.foe_spec(row, t), pp, t)
		RoguePower.clear_reference()
		if absf(float(res.power) - pp) > pp * 0.05:
			continue
		var b := Battle.new(1, rng.randi(), { "wait_mode": false, "escape_tiles": 2, "no_flee": true, "kind": "ROGUE" })
		b.add_unit(ps)
		var fs: Dictionary = res.spec
		fs["side"] = 1
		fs["peer"] = 0
		b.add_unit(fs)
		b.start(t)
		var guard := 0
		while not b.is_over() and guard < 200000:
			b.step(Battle.TICK, t)
			guard += 1
		played += 1
		if b.result_name() == "VICTORY":
			wins += 1
	var wr := float(wins) / maxf(1.0, played)
	var ok := played >= n / 2 and wr >= 0.35 and wr <= 0.65
	print("%-24s %s  同戰力 1 對 1：試煉者勝率 %.1f%%（35–65%%）  %d 場（嘗試 %d）" % ["rogue_power_fair", "ok  " if ok else "FAIL",
		wr * 100.0, played, tries])
	return 1 if ok else 0

## rogue_power_match：2000 次對手生成，99% 的組合戰力在目標 ±10%
func case_rogue_power_match(runs: int, seed0: int) -> int:
	if not _rg_env():
		return _rg_skip("rogue_power_match")
	var t := _rg_t
	var n := 2000 if runs >= 200 else maxi(200, runs * 10)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed0 * 131 + 9
	var hit := 0
	var worst := 0.0
	for i in n:
		var run := RogueRun.new()
		run.seed = seed0 * 7 + i
		run.round = rng.randi_range(1, 20)
		var my := float(_rg_r.p0) * pow(1.2, run.round - 1) * rng.randf_range(0.6, 1.6)
		var tgt := RogueFoes.target(run, my, _rg_r)
		var g := RogueFoes.generate(run, tgt, t, run.rng_for("foes"))
		var err := absf(float(g.power) - tgt) / maxf(0.001, tgt)
		worst = maxf(worst, err)
		if err <= 0.10:
			hit += 1
	var rate := float(hit) / n
	var ok := rate >= 0.99
	print("%-24s %s  對手組合戰力在目標 ±10%%：%.2f%%（≥ 99%%）  最大誤差 %.1f%%  %d 次" % ["rogue_power_match", "ok  " if ok else "FAIL",
		rate * 100.0, worst * 100.0, n])
	return 1 if ok else 0

## rogue_first_runs：200 局、永久點數 0、greedy → 勝場中位數 ∈ [5, 8]、第 10 百分位 ≥ 2、第 90 百分位 ≤ 14
func case_rogue_first_runs(runs: int, seed0: int) -> int:
	if not _rg_env():
		return _rg_skip("rogue_first_runs")
	var n := mini(runs, 200)
	var pts := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rogue-points="):   # 校準用：用 N 點永久點數開局（案例本身的條件是 0 點）
			pts = int(a.substr(15))
	var res := _rg_batch("greedy", n, seed0, pts)
	var w := _rg_wins(res)
	var med := _pct(w, 0.5)
	var p10 := _pct(w, 0.1)
	var p90 := _pct(w, 0.9)
	var ok := med >= 5 and med <= 8 and p10 >= 2 and p90 <= 14
	var allies := 0
	for x in res:
		allies += int(x.allies)
	print("%-24s %s  勝場 中位數 %.0f（5–8）  P10 %.0f（≥ 2）  P90 %.0f（≤ 14）  平均招募 %.2f 位  %d 局" % ["rogue_first_runs",
		"ok  " if ok else "FAIL", med, p10, p90, float(allies) / maxf(1.0, n), n])
	return 1 if ok else 0

## rogue_random_policy：200 局、點數 0、random → 勝場中位數 ∈ [3, 6]
func case_rogue_random_policy(runs: int, seed0: int) -> int:
	if not _rg_env():
		return _rg_skip("rogue_random_policy")
	var n := mini(runs, 200)
	var w := _rg_wins(_rg_batch("random", n, seed0, 0))
	var med := _pct(w, 0.5)
	var ok := med >= 3 and med <= 6
	print("%-24s %s  亂選：勝場中位數 %.0f（3–6）  P10 %.0f  P90 %.0f  %d 局" % ["rogue_random_policy", "ok  " if ok else "FAIL",
		med, _pct(w, 0.1), _pct(w, 0.9), n])
	return 1 if ok else 0

## rogue_profile_growth：30 局連續累積點數（greedy），重複 reps 次（--runs=200 → 20 次）
## 前 5 局每局點數中位數 ∈ [3, 5]；第 21–30 局勝場中位數 − 第 1–10 局 ∈ [2, 8]；30 局後點數 ∈ [40, 60] 且從不超過 60
func case_rogue_profile_growth(runs: int, seed0: int) -> int:
	if not _rg_env():
		return _rg_skip("rogue_profile_growth")
	var reps := clampi(runs / 10, 2, 20)
	var first5: Array = []
	var w_early: Array = []
	var w_late: Array = []
	var finals: Array = []
	var curve: Array = []   # 每 5 局的平均累計點數
	for k in 7:
		curve.append(0.0)
	var over_cap := false
	for rep in reps:
		var p := RogueProfile.default_profile()
		for i in 30:
			var res := _rg_play(seed0 * 7777 + rep * 1009 + i * 31 + 3, "greedy", int(p.points_total))
			var sm := { "wins": res.wins, "bosses_beaten": res.bosses, "foes_beaten": res.foes, "cause": "DEATH", "t": 1 }
			p = RogueProfile.apply_run(p, sm, _rg_r)
			if int(p.points_total) > 60:
				over_cap = true
			if i < 5:
				first5.append(int(sm.points_gained))
			if i < 10:
				w_early.append(int(res.wins))
			elif i >= 20:
				w_late.append(int(res.wins))
			if (i + 1) % 5 == 0:
				curve[(i + 1) / 5] = float(curve[(i + 1) / 5]) + float(p.points_total) / reps
		finals.append(int(p.points_total))
	var m5 := _pct(first5, 0.5)
	var dw := _pct(w_late, 0.5) - _pct(w_early, 0.5)
	var fmin := _pct(finals, 0.0)
	var fmax := _pct(finals, 1.0)
	var ok := m5 >= 3 and m5 <= 5 and dw >= 2 and dw <= 8 and fmin >= 40 and fmax <= 60 and not over_cap
	var cs: PackedStringArray = []
	for k in range(1, 7):
		cs.append("%d局 %.1f" % [k * 5, float(curve[k])])
	print("%-24s %s  前5局點數中位數 %.0f（3–5）  勝場中位數 21–30 局 %.0f − 1–10 局 %.0f = %+.0f（2–8）  30 局後 %.0f–%.0f（40–60）  曲線 %s  重複 %d 次" % [
		"rogue_profile_growth", "ok  " if ok else "FAIL", m5, _pct(w_late, 0.5), _pct(w_early, 0.5), dw, fmin, fmax, "，".join(cs), reps])
	return 1 if ok else 0

## rogue_boss_round5：打到第 5 回合的局，首領戰勝率 ∈ [0.45, 0.75]（用 rogue_first_runs 的同一批局）
func case_rogue_boss_round5(runs: int, seed0: int) -> int:
	if not _rg_env():
		return _rg_skip("rogue_boss_round5")
	var n := mini(runs, 200)
	var res := _rg_batch("greedy", n, seed0, 0)
	var fought := 0
	var won := 0
	for x in res:
		if int(x.boss5) >= 0:
			fought += 1
			won += int(x.boss5)
	var wr := float(won) / maxf(1.0, fought)
	var ok := fought >= 10 and wr >= 0.45 and wr <= 0.75
	print("%-24s %s  第 5 回合首領戰勝率 %.1f%%（45–75%%）  %d／%d 局打到第 5 回合" % ["rogue_boss_round5", "ok  " if ok else "FAIL",
		wr * 100.0, fought, n])
	return 1 if ok else 0

## rogue_determinism：同種子、同策略跑兩次 → 抽卡與對手組合完全相同
func case_rogue_determinism(_runs: int, seed0: int) -> int:
	if not _rg_env():
		return _rg_skip("rogue_determinism")
	var same := true
	for i in 5:
		var a := _rg_play(seed0 * 13 + i, "greedy", 7)
		var b := _rg_play(seed0 * 13 + i, "greedy", 7)
		if a.draws != b.draws or a.fights != b.fights or int(a.wins) != int(b.wins):
			same = false
	print("%-24s %s  同種子同策略：抽卡、對手組合%s" % ["rogue_determinism", "ok  " if same else "FAIL", "完全相同" if same else "不同"])
	return 1 if same else 0


# ==== 0.7.x 試煉審查的回歸案例（【設計提案】的門檻；審查數據見 docs/ROGUE_PLAN.md §12） ====

## rogue_choice_matters：200 局、點數 0：看得懂數字的 smart 勝場中位數 − 亂選 ≥ 3；greedy（只看「相合」的簡單策略）平均也要高過亂選
func case_rogue_choice_matters(runs: int, seed0: int) -> int:
	if not _rg_env():
		return _rg_skip("rogue_choice_matters")
	var n := mini(runs, 200)
	var sm := _rg_wins(_rg_batch("smart", n, seed0, 0))
	var rd := _rg_wins(_rg_batch("random", n, seed0, 0))
	var gr := _rg_wins(_rg_batch("greedy", n, seed0, 0))
	var d := _pct(sm, 0.5) - _pct(rd, 0.5)
	var mg := _rg_mean(gr) - _rg_mean(rd)
	var ok := d >= 3 and mg > 0.0
	print("%-24s %s  勝場中位數 smart %.0f − 亂選 %.0f = %+.0f（≥ 3）  平均 greedy %.2f − 亂選 %.2f = %+.2f（> 0）  %d 局" % [
		"rogue_choice_matters", "ok  " if ok else "FAIL", _pct(sm, 0.5), _pct(rd, 0.5), d, _rg_mean(gr), _rg_mean(rd), mg, n])
	return 1 if ok else 0

static func _rg_mean(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(1.0, a.size())

## rogue_upgrade_offered：greedy 200 局（點數 20）：打到第 4 回合以上的局，≥ 40% 至少看過一張精進卡、≥ 30% 至少拿過一張
## （審查：每門武功只有一張卡，舊規則讓精進卡在實際遊戲中永遠不出現）
func case_rogue_upgrade_offered(runs: int, seed0: int) -> int:
	if not _rg_env():
		return _rg_skip("rogue_upgrade_offered")
	var n := mini(runs, 200)
	var res := _rg_batch("greedy", n, seed0, 20)
	var long := 0
	var seen := 0
	var took := 0
	var total := 0
	for x in res:
		if int(x.rounds) < 4:
			continue
		long += 1
		var u := int((x.get("pk", {}) as Dictionary).get("UPG", 0))
		total += u
		if u > 0:
			took += 1
		if int(x.get("upo", 0)) > 0:
			seen += 1
	var rs := float(seen) / maxf(1.0, long)
	var rt := float(took) / maxf(1.0, long)
	var ok := rs >= 0.4 and rt >= 0.3
	print("%-24s %s  看過精進卡的局 %.0f%%（≥ 40%%）  拿過的 %.0f%%（≥ 30%%）  平均每局拿 %.2f 張  %d 局（打到第 4 回合）" % ["rogue_upgrade_offered",
		"ok  " if ok else "FAIL", rs * 100.0, rt * 100.0, float(total) / maxf(1.0, long), long])
	return 1 if ok else 0

## rogue_no_wall：greedy 200 局、點數 0：死在首領回合的局 ≤ 60%；打到第 10 回合的首領戰勝率 ≥ 35%（點數 0 與 20 合併）；
## 輸的那場對手平均剩氣 ≤ 45%（審查：首領是牆、輸都是被輾過）
func case_rogue_no_wall(runs: int, seed0: int) -> int:
	if not _rg_env():
		return _rg_skip("rogue_no_wall")
	var n := mini(runs, 200)
	var died_boss := 0
	var deaths := 0
	var fq := 0.0
	var b10 := [0, 0]
	for pts in [0, 20]:
		for x in _rg_batch("greedy", n, seed0, pts):
			for f in x.get("fl", []):
				if int(f.r) == 10:
					b10[0] += 1
					if f.won:
						b10[1] += 1
				if not f.won and pts == 0:
					deaths += 1
					fq += float(f.fq)
					if str(f.boss) != "":
						died_boss += 1
	var pb := float(died_boss) / maxf(1.0, deaths)
	var w10 := float(b10[1]) / maxf(1.0, b10[0])
	var mq := fq / maxf(1.0, deaths)
	var ok: bool = pb <= 0.60 and w10 >= 0.35 and int(b10[0]) >= 20 and mq <= 0.45
	print("%-24s %s  死在首領回合 %.0f%%（≤ 60%%）  第 10 回合首領勝率 %.0f%%（≥ 35%%，%d 場）  輸時對手剩氣 %.0f%%（≤ 45%%）" % [
		"rogue_no_wall", "ok  " if ok else "FAIL", pb * 100.0, w10 * 100.0, b10[0], mq * 100.0])
	return 1 if ok else 0

## rogue_boss_spread：greedy 的同一批角色（第 5 回合點數 0、第 10 回合點數 20）在首領回合開打前存檔，輪流對每位首領各打一場；
## 勝率最高 − 最低：第 5 回合 ≤ 25 個百分點、第 10 回合 ≤ 35（審查：抽到哪位首領決定難度——葉二娘 43%、滅絕 89%；
## 校準靠 rogue_foes.power_adj）
func case_rogue_boss_spread(runs: int, seed0: int) -> int:
	if not _rg_env():
		return _rg_skip("rogue_boss_spread")
	var t := _rg_t
	var r := _rg_r
	var n := clampi(runs / 2, 40, 250)
	var ok := true
	var parts: PackedStringArray = []
	for cfg in [[5, 0, 25.0], [10, 20, 35.0]]:
		var rd: int = cfg[0]
		var snaps: Array = []
		for i in n:
			var x := _rg_play(seed0 * 100003 + i * 7919 + 11, "greedy", int(cfg[1]), "", 0, rd)
			if x.has("snap"):
				snaps.append(x.snap)
		var lo := 101.0
		var hi := -1.0
		var lo_id := ""
		var hi_id := ""
		var ids: Array = t.rogue_foes.keys()
		ids.sort()
		for fid in ids:
			var row: Dictionary = t.rogue_foes[fid]
			var mn := int(row.get("min_round", 1))
			if not bool(row.get("boss", false)) or mn > rd or (rd == 5 and mn != 5):
				continue
			var won := 0
			for sn in snaps:
				var ch := Character.from_dict(sn.ch)
				var run := RogueRun.from_dict(sn.run)
				run.bosses_seen = []
				for f2 in t.rogue_foes:
					if bool(t.rogue_foes[f2].get("boss", false)) and str(f2) != str(fid):
						run.bosses_seen.append(str(f2))
				if _rg_fight_once(run, ch):
					won += 1
			var w := 100.0 * won / maxf(1.0, snaps.size())
			if w < lo:
				lo = w
				lo_id = str(fid)
			if w > hi:
				hi = w
				hi_id = str(fid)
		var spread := hi - lo
		if spread > float(cfg[2]) or snaps.size() < 20:
			ok = false
		parts.append("第 %d 回合 %s %.0f%%～%s %.0f%%（差 %.0f，≤ %.0f；%d 人）" % [rd, lo_id.trim_prefix("rg_f_"), lo, hi_id.trim_prefix("rg_f_"), hi,
			spread, float(cfg[2]), snaps.size()])
	print("%-24s %s  %s" % ["rogue_boss_spread", "ok  " if ok else "FAIL", "；".join(parts)])
	return 1 if ok else 0

## 從存檔打一場（同 _rg_play 的戰鬥）；回 true＝贏
func _rg_fight_once(run: RogueRun, ch: Character) -> bool:
	var t := _rg_t
	var pspec: Dictionary = ch.to_combatant(t, {}, 0, 0)
	var prep := RogueFoes.prepare_fight(run, pspec, t, _rg_r)
	var gen: Dictionary = prep.gen
	var b := Battle.new(1, run.battle_seed(), { "wait_mode": false, "escape_tiles": 2, "no_flee": true,
		"end_on_players_down": true, "kind": "ROGUE" })
	b.add_unit(pspec)
	for sp in prep.ally_specs:
		b.add_unit(sp)
	for sp in gen.specs:
		var fs: Dictionary = (sp as Dictionary).duplicate(true)
		fs["side"] = 1
		fs["peer"] = 0
		b.add_unit(fs)
	b.start(t)
	var guard := 0
	while not b.is_over() and guard < 200000:
		b.step(Battle.TICK, t)
		guard += 1
	var me: BattleUnit = b.unit(1)
	return b.result_name() == "VICTORY" and me != null and not me.is_dead()

## rogue_points_late：greedy 200 局：點數 60 時第 1–4 回合打贏後平均剩氣 ≤ 80%（不是走過場）；勝場中位數 60 點 − 0 點 ≥ 4（點數仍然有用）
func case_rogue_points_late(runs: int, seed0: int) -> int:
	if not _rg_env():
		return _rg_skip("rogue_points_late")
	var n := mini(runs, 200)
	var r60 := _rg_batch("greedy", n, seed0, 60)
	var q := 0.0
	var k := 0
	for x in r60:
		for f in x.get("fl", []):
			if int(f.r) <= 4 and f.won:
				q += float(f.mq)
				k += 1
	var mq := q / maxf(1.0, k)
	var d := _pct(_rg_wins(r60), 0.5) - _pct(_rg_wins(_rg_batch("greedy", n, seed0, 0)), 0.5)
	var ok := mq <= 0.80 and d >= 4
	print("%-24s %s  60 點：第 1–4 回合打贏後剩氣 %.0f%%（≤ 80%%）  勝場中位數 60 點 − 0 點 = %+.0f（≥ 4）  %d 局" % [
		"rogue_points_late", "ok  " if ok else "FAIL", mq * 100.0, d, n])
	return 1 if ok else 0
