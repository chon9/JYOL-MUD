extends "res://tests/test_case.gd"
## ROGUE_PLAN §3.4、§9.1（WP-RUN）：抽卡的決定性、種類、稀有度、條件與卡面快照。

var tables: Dictionary = {}
var r: Dictionary = {}

func before_each() -> void:
	if tables.is_empty():
		var loader := DataLoader.new()
		loader.load_all("res://data")
		tables = loader.activate(["1.0A", "1.0B", "rogue"])
	r = RogueRules.rules(tables)

func _char() -> Character:
	var ch := Character.new()
	ch.id = "rg_test"
	ch.gender = "M"
	for a in Character.ATTR_IDS:
		ch.attrs[a] = 18
	var g := RandomNumberGenerator.new()
	g.seed = 7
	for id in ["a_bupao", "w_mudao"]:
		var add := ch.inventory.add(id, 1, tables, 0.0, -1, func() -> String: return CharacterFactory.new_item_uid(ch.inventory, g))
		ch.inventory.equip(str(add.uid), tables)
	ch.vitals = { "jing": 80, "qi": 160, "shen": 80, "neili": 0, "food": 100, "water": 100 }
	return ch

func _run(seed: int, round: int = 1) -> RogueRun:
	var run := RogueRun.new()
	run.seed = seed
	run.round = round
	return run

func _ids(cards: Array) -> Array:
	return cards.map(func(c): return str(c.id))

func test_same_seed_same_cards() -> void:
	var a := RogueDraw.draw(_run(42), _char(), tables, _run(42).rng_for("draw"))
	var b := RogueDraw.draw(_run(42), _char(), tables, _run(42).rng_for("draw"))
	assert_eq(_ids(a), _ids(b), "同種子同結果")
	assert_eq(a.size(), 3, "三張")
	var diff := 0
	for s in range(100, 130):
		if _ids(RogueDraw.draw(_run(s), _char(), tables, _run(s).rng_for("draw"))) != _ids(a):
			diff += 1
	assert_true(diff > 20, "不同種子大多不同")

func test_kinds_rarity_unique_and_snapshot_shape() -> void:
	var ch := _char()
	for s in range(1, 80):
		var run := _run(s, 1 + s % 9)
		var cards := RogueDraw.draw(run, ch, tables, run.rng_for("draw"))
		assert_eq(cards.size(), 3)
		var kinds := {}
		var ids := {}
		for i in cards.size():
			var c: Dictionary = cards[i]
			kinds[c.kind] = true
			ids[c.id] = true
			assert_eq(int(c.idx), i, "idx")
			assert_true(str(c.title) != "" and str(c.sub) != "", "title/sub")
			assert_true((c.lines as Array).size() >= 1 and (c.lines as Array).size() <= 4, "lines 1–4")
			assert_true(c.rarity in RogueRules.RARITIES)
			match str(c.kind):
				"ART":
					assert_true(c.has("art") and c.art.has("level") and c.art.has("category"))
				"WEAPON":
					assert_true(c.has("item") and c.item.has("slot"))
				"ATTR":
					assert_true(int(c.points) >= 3)
				"ALLY":
					assert_true(c.has("ally") and str(c.ally.monster) != "")
		assert_true(kinds.size() >= 2 or s == -1, "至少兩種種類（seed %d：%s）" % [s, str(_ids(cards))])
		assert_eq(ids.size(), 3, "不重複 id")

func test_ally_gating() -> void:
	var ch := _char()
	for s in range(1, 60):
		var run := _run(s, 1)
		for c in RogueDraw.draw(run, ch, tables, run.rng_for("draw")):
			assert_true(str(c.kind) != "ALLY", "第 1 回合不出隊友")
	for s in range(1, 60):
		var run2 := _run(s, 5)
		run2.allies = [{ "card_id": "rg_c_ally_hs_dizi", "alive": true }, { "card_id": "rg_c_ally_em_dizi", "alive": true }]
		for c in RogueDraw.draw(run2, ch, tables, run2.rng_for("draw")):
			assert_true(str(c.kind) != "ALLY", "已有兩位活著的隊友 → 不出")
	# 招過（含死掉的）同一位不再出
	var run3 := _run(3, 4)
	run3.allies = [{ "card_id": "rg_c_ally_hs_dizi", "alive": false }]
	var cand := RogueDraw.candidates("ALLY", "COMMON", run3, ch, tables, {}, r)
	assert_false(cand.any(func(c): return str(c.id) == "rg_c_ally_hs_dizi"), "死過的隊友不再出")
	assert_true(cand.size() >= 1)

func test_boss_reward_min_rare() -> void:
	var ch := _char()
	for s in range(1, 60):
		var run := _run(s, 6)
		for c in RogueDraw.draw(run, ch, tables, run.rng_for("draw"), "RARE"):
			assert_true(RogueRules.rarity_index(str(c.rarity)) >= 2, "首領獎勵全 ≥ 稀：%s %s" % [c.id, c.rarity])

func test_art_eligibility_and_upgrade() -> void:
	var ch := _char()
	var row: Dictionary = tables.rogue_cards["rg_c_art_hs_jianfa"]
	ch.skills.set_level("hs_jianfa", int(r.art_cap), tables)
	assert_false(RogueDraw.eligible(row, _run(1), ch, tables, r), "已到上限（art_cap）→ 不出")
	ch.skills.set_level("hs_jianfa", 60, tables)
	assert_true(RogueDraw.eligible(row, _run(1), ch, tables, r), "已會、等級比卡高但沒到上限 → 精進仍會出（審查：每門武功只有一張卡）")
	ch.skills.set_level("hs_jianfa", 10, tables)
	assert_true(RogueDraw.eligible(row, _run(1), ch, tables, r), "已會但等級較低 → 精進")
	var snap := RogueDraw.snapshot(row, 0, _run(1), ch, tables, r)
	assert_true(bool(snap.upgrade), "精進卡")
	assert_eq(int(snap.art.level), 10 + 15, "凡：+15")
	var fresh := RogueDraw.snapshot(row, 0, _run(1), _char(), tables, r)
	assert_false(bool(fresh.upgrade))
	assert_eq(int(fresh.art.level), 25, "凡 → 25 級")
	assert_eq(str(fresh.title), "華山劍法 25 級", "標題用阿拉伯數字（同卡身與 HUD）")
	assert_true(str(fresh.sub).contains("劍"), "sub 寫兵器類別")

## 審查回歸：真的走一遍「拿卡 → 下次再出」：拿過的武功卡之後會以精進卡出現（不靠手動改等級）
func test_upgrade_offered_after_taking_card() -> void:
	var ch := _char()
	var run := _run(3, 2)
	var row: Dictionary = tables.rogue_cards["rg_c_art_hs_jianfa"]
	var first := RogueDraw.snapshot(row, 0, run, ch, tables, r)
	assert_eq(run.apply_card(ch, first, {}, tables, {}, r), "")
	assert_eq(ch.skills.level("hs_jianfa"), 25)
	assert_true(RogueDraw.eligible(row, run, ch, tables, r), "拿過的武功卡還會再出（精進）")
	var seen := false
	for s in range(1, 400):
		var rr := _run(s, 4)
		rr.taken = run.taken.duplicate(true)
		for c in RogueDraw.draw(rr, ch, tables, rr.rng_for("draw")):
			if str(c.id) == "rg_c_art_hs_jianfa":
				assert_true(bool(c.upgrade), "再出現時是精進卡")
				assert_eq(int(c.art.level), 25 + 15)
				seen = true
	assert_true(seen, "400 次抽卡裡精進卡至少出現一次")
	var up := RogueDraw.snapshot(row, 0, run, ch, tables, r)
	assert_eq(run.apply_card(ch, up, {}, tables, {}, r), "")
	assert_eq(ch.skills.level("hs_jianfa"), 40, "精進 +15")
	assert_eq(ch.skills.level("basic_sword"), 40, "基本劍法跟著提升")

func test_weapon_eligibility() -> void:
	var ch := _char()
	var mu: Dictionary = tables.rogue_cards["rg_c_wpn_w_lt_bishou"] if tables.rogue_cards.has("rg_c_wpn_w_lt_bishou") else {}
	var have := { "id": "rg_c_wpn_w_mudao", "kind": "WEAPON", "rarity": "COMMON", "item": "w_mudao" }
	assert_false(RogueDraw.eligible(have, _run(1), ch, tables, r), "背包已有同 id → 不出")
	var female_only := { "id": "x", "kind": "WEAPON", "rarity": "COMMON", "item": "a_lt_yushang" }
	assert_false(RogueDraw.eligible(female_only, _run(1), ch, tables, r), "條件不合（限女性）→ 不出")
	ch.gender = "F"
	assert_true(RogueDraw.eligible(female_only, _run(1), ch, tables, r))
	assert_true(mu.is_empty() or RogueDraw.eligible(mu, _run(1), ch, tables, r))

func test_debug_cards_fixed() -> void:
	var run := _run(5, 3)
	run.debug_cards = ["rg_c_art_hs_jianfa", "rg_c_attr_fine", "rg_c_ally_zhouzhiruo"]
	var cards := RogueDraw.draw(run, _char(), tables, run.rng_for("draw"))
	assert_eq(_ids(cards), ["rg_c_art_hs_jianfa", "rg_c_attr_fine", "rg_c_ally_zhouzhiruo"])
	assert_true(run.debug_cards.is_empty(), "只用一次")
	assert_eq(int(cards[1].points), 4, "良：+4 點")
	assert_eq(str(cards[2].ally.ref), "n_em_zhouzhiruo", "隊友用 NPC 立繪")
