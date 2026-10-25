extends "res://tests/test_case.gd"
## 江湖試煉 0.7.x 審查的回歸測試【設計提案・非原作】：卡面文字（屬性名稱、基本武學同步提升）、兵器卡不再是陷阱、
## 同一人不會同局又是隊友又是首領、名人的門派與武功、江湖名聲（點數淡出）、首領的 power_adj、結算的「隊友還站著」。

var tables: Dictionary = {}
var r: Dictionary = {}

func before_each() -> void:
	if tables.is_empty():
		var loader := DataLoader.new()
		loader.load_all("res://data")
		tables = loader.activate(["1.0A", "1.0B", "rogue"])
	r = RogueRules.rules(tables)

func _char(weapon := "w_mudao") -> Character:
	var ch := Character.new()
	ch.id = "rg_review"
	ch.gender = "M"
	for a in Character.ATTR_IDS:
		ch.attrs[a] = 18
	var g := RandomNumberGenerator.new()
	g.seed = 11
	for id in ["a_bupao", weapon]:
		var add := ch.inventory.add(id, 1, tables, 0.0, -1, func() -> String: return CharacterFactory.new_item_uid(ch.inventory, g))
		ch.inventory.equip(str(add.uid), tables)
	ch.vitals = { "jing": 80, "qi": 160, "shen": 80, "neili": 0, "food": 100, "water": 100 }
	return ch

func _run(seed: int, round: int = 1) -> RogueRun:
	var run := RogueRun.new()
	run.seed = seed
	run.round = round
	return run

func _card(id: String, ch: Character, run: RogueRun = null) -> Dictionary:
	return RogueDraw.snapshot(tables.rogue_cards[id], 0, run if run != null else _run(1, 3), ch, tables, r)

static func _joined(c: Dictionary) -> String:
	return "\n".join(c.get("lines", []))

# ---------------------------------------------------------------- 卡面文字

func test_attr_names_match_the_rest_of_the_game() -> void:
	assert_eq(RogueDraw.ATTR_NAMES, UiKeys.ATTR_NAMES, "臂力／機敏，同屬性分配窗與 HUD")
	var c := _card("rg_c_wpn_a_lt_jinggangjie", _char())
	var t := _joined(c)
	assert_true(t.contains("臂力 +"), t)
	assert_false(t.contains("膂力") or t.contains("身法"), t)

func test_weapon_art_card_states_basic_raise() -> void:
	var c := _card("rg_c_art_hs_jianfa", _char())
	var t := _joined(c)
	assert_true(t.contains("基本劍法同步提升到 25 級，攻擊 +6"), t)
	var ch := _char()
	assert_eq(_run(1, 3).apply_card(ch, c, {}, tables, {}, r), "")
	assert_eq(ch.skills.level("basic_sword"), 25, "卡上寫的就是實際套用的")

func test_lightness_card_names_both_basics() -> void:
	var c := _card("rg_c_art_wd_shenfa", _char())
	var t := _joined(c)
	var body := SkillBook.skill_name("basic_body", tables)
	var dodge := SkillBook.skill_name("basic_dodge", tables)
	assert_true(t.contains(body) and t.contains(dodge), t)
	assert_eq(dodge, "閃躲縱躍", "遊戲內名稱")
	var ch := _char()
	assert_eq(_run(1, 3).apply_card(ch, c, {}, tables, {}, r), "")
	assert_eq(ch.skills.level("basic_body"), int(c.art.level))
	assert_eq(ch.skills.level("basic_dodge"), int(c.art.level))

func test_basic_cards_have_numbers() -> void:
	var d := _joined(_card("rg_c_art_basic_dodge", _char()))
	assert_true(d.contains("−0.3%"), d)
	var b := _joined(_card("rg_c_art_basic_body", _char()))
	assert_true(b.contains("+0.03"), b)
	var p := _joined(_card("rg_c_art_basic_parry", _char()))
	assert_true(p.contains("防禦力 +"), p)
	for t in [d, b, p]:
		assert_false(t.contains("更不容易被打中"), "舊的模糊字眼不見了")

# ---------------------------------------------------------------- 兵器卡不是陷阱

func test_weapon_card_keeps_matched_weapon() -> void:
	var ch := _char("w_qingfeng")
	ch.skills.set_level("hs_jianfa", 40, tables)
	var c := _card("rg_c_wpn_w_lt_guandao", ch)   # 刀：與華山劍法不合
	assert_true(_joined(c).contains("放進行囊"), _joined(c))
	assert_eq(_run(1, 3).apply_card(ch, c, {}, tables, {}, r), "")
	assert_eq(str(ch.inventory.equipped_row("WEAPON", tables).get("weapon_type", "")), "SWORD", "相合的劍沒被換掉")
	assert_eq(ch.inventory.count("w_lt_guandao"), 1, "新兵器在行囊裡")
	# 同類、攻擊更高 → 換上
	var same := RogueRun.weapon_auto_equip(ch, tables.items["w_lt_heijian"], tables)
	assert_eq(same, int(tables.items["w_lt_heijian"].get("atk", 0)) >= int(tables.items["w_qingfeng"].get("atk", 0)))
	# 沒有相合的武功：攻擊較高就換
	var plain := _char()
	assert_true(RogueRun.weapon_auto_equip(plain, tables.items["w_lt_guandao"], tables))

func test_weapon_trim_names_the_dropped_one_and_keeps_new() -> void:
	var ch := _char()
	var g := RandomNumberGenerator.new()
	g.seed = 5
	for id in ["w_qingfeng", "w_gangdao"]:
		ch.inventory.add(id, 1, tables, 0.0, -1, func() -> String: return CharacterFactory.new_item_uid(ch.inventory, g))
	assert_eq(ch.inventory.weapon_options(tables).size(), 3)
	var c := _card("rg_c_wpn_w_lt_yujian", ch)
	var t := _joined(c)
	assert_true(t.contains("兵器最多留 3 把：丟掉"), t)
	assert_eq(_run(1, 3).apply_card(ch, c, {}, tables, {}, r), "")
	assert_eq(ch.inventory.weapon_options(tables).size(), 3)
	assert_eq(ch.inventory.count("w_lt_yujian"), 1, "剛拿到的不會被丟掉")

# ---------------------------------------------------------------- 隊友與首領不會是同一人

func test_ally_never_becomes_boss_in_same_run() -> void:
	var ch := _char()
	for s in range(1, 40):
		var run := _run(s, 2)
		var crow: Dictionary = tables.rogue_cards["rg_c_ally_zhouzhiruo"]
		var snap := RogueDraw.snapshot(crow, 0, run, ch, tables, r)
		assert_eq(run.apply_card(ch, snap, {}, tables, {}, r), "")
		run.round = 5
		var g := RogueFoes.generate(run, 12.0, tables, run.rng_for("foes"))
		assert_true(str(g.boss_id) != "rg_f_zhouzhiruo", "seed %d：隊友周芷若被抽成首領" % s)
		ch = _char()

func test_seen_boss_not_offered_as_ally() -> void:
	var run := _run(3, 6)
	run.bosses_seen = ["rg_f_zhouzhiruo"]
	assert_false(RogueDraw.eligible(tables.rogue_cards["rg_c_ally_zhouzhiruo"], run, _char(), tables, r))
	run.bosses_seen = []
	assert_true(RogueDraw.eligible(tables.rogue_cards["rg_c_ally_zhouzhiruo"], run, _char(), tables, r))

# ---------------------------------------------------------------- 名人的門派與武功

static func _arts_of(mon: Dictionary) -> Array:
	return (mon.get("arts", []) as Array).map(func(a): return str(a.get("art", "")))

func test_famous_characters_fit_jin_yong() -> void:
	var m: Dictionary = tables.monsters
	assert_eq(str(m.m_rg_guojing.get("sect", "")), "", "郭靖不是丐幫弟子")
	assert_true(_arts_of(m.m_rg_guojing).has("rg_mon_xianglong"), "降龍十八掌")
	assert_true(_arts_of(m.m_rg_guojing) != _arts_of(m.m_rg_qiaofeng), "郭靖與喬峰不同")
	assert_true(_arts_of(m.m_rg_zhangwuji).has("rg_mon_jiuyang") and _arts_of(m.m_rg_zhangwuji).has("rg_mon_qiankun"))
	assert_true(_arts_of(m.m_rg_zhangwuji) != _arts_of(m.m_rg_zhangsanfeng), "張無忌與張三丰不同")
	assert_false(_arts_of(m.m_rg_linghuchong).has("hs_zixia"), "紫霞神功是岳不群的")
	assert_true(_arts_of(m.m_rg_linghuchong).has("rg_mon_dugu"), "獨孤九劍")
	assert_eq(str(_arts_of(m.m_rg_zhouzhiruo)[0]), "mon_baigu", "九陰白骨爪")
	assert_false((tables.rogue_foes.rg_f_limochou.minions as Array).has("rg_f_gm_dizi"), "李莫愁被逐出古墓")
	assert_true((tables.rogue_foes.rg_f_limochou.minions as Array).has("rg_f_lmc_hongningbo"), "隨從是洪凌波")
	var hf: Dictionary = tables.rogue_cards.rg_c_ally_hufei.override.skills
	assert_true(hf.has("basic_blade") and not hf.has("basic_sword"), "胡家刀法是刀法")
	var gj := _card("rg_c_ally_guojing", _char(), _run(1, 3))
	assert_eq(str(gj.sub), "隊友・襄陽")
	var wj := _card("rg_c_ally_zhangwuji", _char(), _run(1, 3))
	assert_eq(str(wj.sub), "隊友・明教")
	# MUD 世界的周芷若不變
	assert_eq(str(_arts_of(m.m_em_zhouzhiruo)[0]), "em_jinding")

# ---------------------------------------------------------------- 江湖名聲、首領 power_adj

func test_renown_fades_with_rounds() -> void:
	var rr := r.duplicate(true)
	rr["renown_share"] = 0.6
	rr["renown_fade"] = 10
	var run := _run(1, 1)
	run.alloc_points = CharacterFactory.FREE_POINTS + 60
	assert_eq(RogueFoes.renown_points(run, rr), 36, "第 1 回合全額 60×0.6")
	run.round = 6
	assert_eq(RogueFoes.renown_points(run, rr), 18, "第 6 回合一半")
	run.round = 11
	assert_eq(RogueFoes.renown_points(run, rr), 0, "第 11 回合起為 0")
	run.alloc_points = CharacterFactory.FREE_POINTS
	run.round = 1
	assert_eq(RogueFoes.renown_points(run, rr), 0, "沒有點數就沒有名聲")
	assert_true(RoguePower.reference_power(tables, 30) > RoguePower.reference_power(tables, 0), "名聲讓參考新角色變強")

func test_power_adj_by_round() -> void:
	assert_eq(RogueFoes.row_adj({ "power_adj": { "5": 0.9, "10": 1.2 } }, 5), 0.9)
	assert_eq(RogueFoes.row_adj({ "power_adj": { "5": 0.9, "10": 1.2 } }, 12), 1.2)
	assert_eq(RogueFoes.row_adj({ "power_adj": 0.8 }, 10), 0.8)
	assert_eq(RogueFoes.row_adj({}, 10), 1.0)
	# 縮放後的有效戰力仍在目標 ±10%
	for s in range(1, 20):
		var run := _run(s, 10)
		run.bosses_seen = []
		for fid in tables.rogue_foes:
			if bool(tables.rogue_foes[fid].get("boss", false)) and str(fid) != "rg_f_xiaolongnu":
				run.bosses_seen.append(str(fid))
		var g := RogueFoes.generate(run, 30.0, tables, run.rng_for("foes"))
		assert_eq(str(g.boss_id), "rg_f_xiaolongnu")
		assert_true(absf(float(g.power) - 30.0) <= 3.0, "seed %d：有效戰力 %.2f" % [s, float(g.power)])
		assert_true(absf(float((g.specs as Array)[0].get("rg_adj", 1.0)) - float(tables.rogue_foes.rg_f_xiaolongnu.power_adj)) < 0.001)

# ---------------------------------------------------------------- 結算

func test_summary_allies_standing() -> void:
	var run := _run(1, 4)
	run.last_result = { "round": 4, "won": false, "boss": false, "allies_fallen": [], "over": true, "allies_standing": 1 }
	assert_eq(int(run.summary().allies_standing), 1)
	run.last_result = { "round": 4, "won": true, "allies_standing": 2 }
	assert_eq(int(run.summary().allies_standing), 0, "只在輸的時候算")
