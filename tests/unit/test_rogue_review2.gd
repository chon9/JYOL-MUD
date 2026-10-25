extends "res://tests/test_case.gd"
## 江湖試煉第二輪審查的回歸測試【設計提案・非原作】：卡面戰力、精進卡權重、拳掌卡與拳套卡的文字、隊友功力的說法、
## 名人的武功與門派（喬峰、丘處機、張松溪、胡斐）、對手補刀、進行中一局的結算（當機不歸零）。

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
	ch.id = "rg_review2"
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

static func _arts_of(mon: Dictionary) -> Array:
	return (mon.get("arts", []) as Array).map(func(a): return str(a.get("art", "")))

# ---------------------------------------------------------------- 卡面戰力（RogueDraw.annotate_power）

func test_power_pct_on_cards() -> void:
	var ch := _char()
	var run := _run(1, 3)
	var cards: Array = [_card("rg_c_attr_rare", ch, run), _card("rg_c_art_xd_daofa", ch, run), _card("rg_c_ally_guojing", ch, run),
		_card("rg_c_art_basic_parry", ch, run)]
	var lv0 := ch.skills.level("xd_daofa")
	var attrs0: Dictionary = ch.attrs.duplicate()
	RogueDraw.annotate_power(cards, run, ch, tables, r)
	assert_true(cards[0].has("power_pct") and int(cards[0].power_pct) > 0, "屬性卡：戰力上升 %s" % str(cards[0].get("power_pct")))
	assert_true(str(cards[0].get("power_note", "")).contains("臂力"), "屬性卡註明怎麼估的")
	assert_true(int(cards[1].power_pct) > 0, "與木刀相合的刀法：戰力上升")
	assert_false(cards[2].has("power_pct"), "隊友卡沒有戰力數字")
	assert_true(cards[3].has("power_pct"))
	assert_eq(ch.skills.level("xd_daofa"), lv0, "只用副本估算，不改角色")
	assert_eq(ch.attrs, attrs0)
	assert_true(run.taken.is_empty(), "不改這一局")
	assert_false(RoguePower.has_reference(), "估完參考還原")
	# 用不上的劍法（拿木刀）比相合的刀法低
	var sw := [_card("rg_c_art_hs_jianfa", ch, run)]
	RogueDraw.annotate_power(sw, run, ch, tables, r)
	assert_true(int(sw[0].power_pct) < int(cards[1].power_pct), "不合兵器的武功估得比較低 %d < %d" % [int(sw[0].power_pct), int(cards[1].power_pct)])

func test_card_power_text_and_armor_kind() -> void:
	assert_eq(RogueCard.power_text({ "power_pct": 12 }), "戰力 ▲12%")
	assert_eq(RogueCard.power_text({ "power_pct": -3 }), "戰力 ▼3%")
	assert_eq(RogueCard.power_text({ "power_pct": 0 }), "戰力 持平")
	assert_eq(RogueCard.power_text({}), "")
	var ch := _char()
	var armor := _card("rg_c_wpn_a_pijia", ch)
	assert_eq(str(armor.kind), "WEAPON", "協定的種類不變")
	assert_eq(RogueCard.display_kind(armor), "ARMOR", "護具卡顯示護具")
	assert_true(RogueCard.tooltip_for(armor, tables).begins_with("護具〔"), RogueCard.tooltip_for(armor, tables))
	assert_eq(RogueCard.display_kind(_card("rg_c_wpn_w_gangdao", ch)), "WEAPON")
	var c := RogueCard.new(armor)
	assert_eq(c.kind_glyph.text, "甲")
	c.free()

func test_trial_tooltip_drops_open_world_lines() -> void:
	var c := _card("rg_c_art_basic_inner", _char())
	var tip := RogueCard.tooltip_for(c, tables)
	assert_false(tip.contains("江湖謠言") or tip.contains("熱鍵"), tip)
	assert_true(tip.contains("內力上限"), "試煉用得到的說明還在")

# ---------------------------------------------------------------- 卡面文字

func test_fist_cards_do_not_contradict() -> void:
	var ch := _char("w_qingfeng")
	var fist_id := ""
	for id in tables.rogue_cards:
		var c: Dictionary = tables.rogue_cards[id]
		if str(c.get("kind", "")) == "ART" and str(tables.martial_arts.get(str(c.get("art", "")), {}).get("category", "")) == "FIST":
			fist_id = str(id)
			break
	assert_true(fist_id != "")
	var card := _card(fist_id, ch)
	assert_true(str(card.sub).ends_with("不挑兵器"), str(card.sub))
	assert_false(_joined(card).contains("空手或拳套"))
	assert_true(_joined(card).contains("拿什麼兵器都能出招"), _joined(card))
	# 拳套卡說出相合的拳掌武功
	ch.skills.set_level("hs_pishiquan", 30, tables)
	var glove := ""
	for id in tables.rogue_cards:
		var c2: Dictionary = tables.rogue_cards[id]
		var row: Dictionary = tables.items.get(str(c2.get("item", "")), {})
		if str(c2.get("kind", "")) == "WEAPON" and str(row.get("slot", "")) == "WEAPON" and str(row.get("weapon_type", "")) == "FIST":
			glove = str(id)
			break
	assert_true(glove != "", "有拳套卡")
	assert_true(_joined(_card(glove, ch)).contains("與你的劈石破玉拳相合"), _joined(_card(glove, ch)))

func test_ally_share_wording() -> void:
	assert_eq(RogueDraw.share_text(1.0), "功力與你相當")
	assert_eq(RogueDraw.share_text(0.45), "功力約為你的四成半")
	assert_eq(RogueDraw.share_text(0.7), "功力約為你的七成")
	var t := _joined(_card("rg_c_ally_hs_dizi", _char(), _run(1, 3)))
	assert_false(t.contains("成功力"), t)

func test_famous_arts_and_affil_round2() -> void:
	var m: Dictionary = tables.monsters
	assert_true(_arts_of(m.m_rg_qiaofeng).has("rg_mon_xianglong"), "喬峰有降龍十八掌")
	assert_true(_arts_of(m.m_rg_qiaofeng).has("gb_qinlong"), "喬峰：擒龍功")
	assert_true(_arts_of(m.m_rg_guojing).has("gm_jiuyin"), "郭靖：九陰真經")
	assert_true(_arts_of(m.m_rg_guojing) != _arts_of(m.m_rg_qiaofeng))
	assert_false(_arts_of(m.m_rg_qiuchuji).has("qz_xiantian"), "先天氣功是王重陽的")
	assert_true(_arts_of(m.m_rg_qiuchuji).has("qz_jianfa"), "丘處機：全真劍法")
	assert_eq(str(_card("rg_c_ally_zhangsongxi", _char(), _run(1, 3)).sub), "隊友・武當")
	assert_eq(str(_card("rg_c_ally_hufei", _char(), _run(1, 3)).sub), "隊友・遼東")
	var lines := _joined(_card("rg_c_ally_qiaofeng", _char(), _run(1, 3)))
	assert_true(lines.contains("降龍十八掌"), lines)

## 精進卡在候選裡的權重加倍（審查：換種子就掉到 40% 以下）
func test_upgrade_cards_weighted() -> void:
	var ch := _char()
	var run := _run(5, 5)
	ch.skills.set_level("xd_daofa", 30, tables)
	var seen_up := 0
	var seen_art := 0
	for i in 400:
		run.draws = i
		var g := run.rng_for("draw")
		var row := RogueDraw._pick_row("ART", 0, run, ch, tables, g, {}, r, "")
		if row.is_empty():
			continue
		seen_art += 1
		if str(row.get("art", "")) == "xd_daofa":
			seen_up += 1
	var n_common := RogueDraw.candidates("ART", "COMMON", run, ch, tables, {}, r).size()
	assert_true(seen_art > 300)
	# 沒加權時約 1/候選數（搭配偏好時更高）；加權 ×3 之後明顯高於 1/候選數
	assert_true(float(seen_up) / seen_art > 1.5 / maxf(1.0, n_common), "精進卡 %d／%d（凡卡候選 %d）" % [seen_up, seen_art, n_common])

# ---------------------------------------------------------------- 對手補刀（BattleAI）

func test_rogue_foes_finish_low_targets() -> void:
	var p := { "kind": "PLAYER", "ref": "p", "name": "試煉者", "side": 0, "peer": 1, "ai": "melee_basic",
		"attrs": { "str": 20, "guts": 20, "wit": 20, "luck": 20, "cal": 20, "agi": 20, "con": 20 },
		"qi": 400, "qi_max": 400, "neili": 0, "neili_max": 0, "jing": 100, "jing_max": 100, "shen": 100, "shen_max": 100,
		"skills": {}, "arts": [], "weapon": { "uid": "", "item_id": "", "weapon_type": "FIST", "atk": 0, "name": "" }, "armor_power": 0 }
	var ally := p.duplicate(true)
	ally["kind"] = "ALLY"
	ally["ai"] = "ally"
	ally["peer"] = 0
	ally["rg_ally"] = "rg_ally_0"
	var foe := p.duplicate(true)
	foe["kind"] = "MONSTER"
	foe["side"] = 1
	foe["peer"] = 0
	var b := Battle.new(3, 5, { "wait_mode": false, "kind": "ROGUE", "no_flee": true, "end_on_players_down": true })
	b.add_unit(p)
	b.add_unit(ally)
	b.add_unit(foe)
	b.start(tables)
	var me := b.unit(1)
	var al := b.unit(2)
	var f := b.unit(3)
	me.pos = Vector2i(4, 3)
	al.pos = Vector2i(6, 3)
	f.pos = Vector2i(5, 3)
	me.qi = 200
	al.qi = 400
	var c := BattleAI.choose(b, f, tables, RandomNumberGenerator.new())
	assert_eq(c.target, [6, 3], "平常先打氣比例高的（隊友）")
	me.qi = 40   # 10%
	var c2 := BattleAI.choose(b, f, tables, RandomNumberGenerator.new())
	assert_eq(c2.target, [4, 3], "搆得到氣 < 15% 的人時先補刀")

# ---------------------------------------------------------------- 進行中一局（當機不歸零）

func test_in_progress_settles_as_leave() -> void:
	var p := RogueProfile.default_profile()
	var run := _run(77, 1)
	run.run_id = "rr_crash"
	run.on_won(2, false)
	run.on_won(1, false)
	p["in_progress"] = RogueProfile.progress_of(run.summary(), 1000)
	var np := RogueProfile.normalize(p)
	assert_eq(int(np.in_progress.wins), 2, "normalize 保留 in_progress")
	var res := RogueProfile.settle_pending(np, r)
	assert_true(bool(res.settled))
	var sp: Dictionary = res.profile
	assert_eq(int(sp.runs), 1)
	assert_eq(str(sp.history[0].cause), "LEAVE")
	assert_eq(int(sp.history[0].wins), 2)
	assert_eq(int(sp.points_total), RogueRules.award(2, 0, 0, true, r))
	assert_true((sp.in_progress as Dictionary).is_empty(), "結算後清掉")
	assert_false(bool(RogueProfile.settle_pending(sp, r).settled), "不會結算兩次")
	assert_true(RogueProfile.normalize({ "in_progress": { "run_id": "x", "wins": 0 } }).in_progress.is_empty(), "0 勝不留")
