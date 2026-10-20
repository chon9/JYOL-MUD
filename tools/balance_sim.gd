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
		print("%-24s REPORT  打獵基準 %.2f 兩／精；採集 [%s]；超出 0.3–1.5 倍的配方 %d 條：%s" % ["econ_chain", base,
			", ".join(lines), outliers.size(), ", ".join(outliers.slice(0, 12)) + (" …" if outliers.size() > 12 else "")])
		print("%-24s %s  成品收購價不高於材料的配方 %d 條%s" % ["econ_no_loss", "ok  " if losers.is_empty() else "FAIL", losers.size(),
			"" if losers.is_empty() else "：" + ", ".join(losers)])
		return 1 if losers.is_empty() else 0)

var tables: Dictionary = {}
var _loader: DataLoader = null   # 需要別的 era 視圖的案例用（陣法屬 1.0B）
var skipped := 0

func _initialize() -> void:
	var runs := 500
	var only := ""
	var dir := "res://data"
	var seed0 := 1
	for a in OS.get_cmdline_user_args():
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
	return { "result": b.result_name(), "killed": b.units.filter(func(u): return u.side == 1).all(func(u): return u.is_dead()),
		"actions": me.actions, "dmg_sum": 0, "dmg_n": 0, "qi_pct": me.qi / float(me.qi_max()), "deaths": deaths }

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
