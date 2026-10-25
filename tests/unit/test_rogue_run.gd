extends "res://tests/test_case.gd"
## ROGUE_PLAN §3.1、§3.5、§3.9.1、§9.1（WP-RUN）：四種卡的效果、ATTR 分配錯誤、兵器保留 3 把、best_card、序列化、summary。

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
	ch.id = "rg_t"
	ch.gender = "M"
	for a in Character.ATTR_IDS:
		ch.attrs[a] = 20
	var g := RandomNumberGenerator.new()
	g.seed = 3
	for id in ["a_bupao", "w_mudao"]:
		var add := ch.inventory.add(id, 1, tables, 0.0, -1, func() -> String: return CharacterFactory.new_item_uid(ch.inventory, g))
		ch.inventory.equip(str(add.uid), tables)
	ch.vitals = { "jing": 80, "qi": 180, "shen": 80, "neili": 0, "food": 100, "water": 100 }
	return ch

func _card(id: String, run: RogueRun, ch: Character) -> Dictionary:
	return RogueDraw.snapshot(tables.rogue_cards[id], 0, run, ch, tables, r)

func test_art_card_sets_level_and_base() -> void:
	var run := RogueRun.new()
	var ch := _char()
	assert_eq(run.apply_card(ch, _card("rg_c_art_hs_jianfa", run, ch), {}, tables, {}, r), "")
	assert_eq(ch.skills.level("hs_jianfa"), 25, "凡 → 25 級")
	assert_true(ch.skills.level("basic_sword") >= 25, "對應基本武學跟上")
	# 精進：+15（凡）
	assert_eq(run.apply_card(ch, _card("rg_c_art_hs_jianfa", run, ch), {}, tables, {}, r), "")
	assert_eq(ch.skills.level("hs_jianfa"), 40, "精進 25 + 15")
	assert_eq(ch.skills.level("basic_sword"), 40)
	# 內功：基本內功一起提升；身法：閃躲
	assert_eq(run.apply_card(ch, _card("rg_c_art_hs_zixia", run, ch), {}, tables, {}, r), "")
	assert_eq(ch.skills.level("hs_zixia"), 60)
	assert_eq(ch.skills.level("basic_inner"), 60, "INNER → basic_inner")
	assert_eq(run.apply_card(ch, _card("rg_c_art_wd_shenfa", run, ch), {}, tables, {}, r), "")
	assert_true(ch.skills.level("basic_dodge") >= 40, "LIGHTNESS → basic_dodge")
	# 基本武學卡
	assert_eq(run.apply_card(ch, _card("rg_c_art_basic_parry", run, ch), {}, tables, {}, r), "")
	assert_eq(ch.skills.level("basic_parry"), 25)
	# 上限 150
	ch.skills.set_level("hs_jianfa", 145, tables)
	var up := _card("rg_c_art_hs_jianfa", run, ch)
	assert_eq(run.apply_card(ch, up, {}, tables, {}, r), "")
	assert_eq(ch.skills.level("hs_jianfa"), 150, "夾在 art_cap")

func test_weapon_card_equips_and_keeps_three() -> void:
	var run := RogueRun.new()
	var ch := _char()
	assert_eq(run.apply_card(ch, _card("rg_c_wpn_w_qingfeng", run, ch), {}, tables, {}, r), "")
	assert_eq(str(ch.inventory.equipped_row("WEAPON", tables).get("name", "")), str(tables.items.w_qingfeng.name), "已裝備")
	for id in ["rg_c_wpn_w_gangdao", "rg_c_wpn_w_lt_heijian", "rg_c_wpn_w_lt_guandao"]:
		assert_eq(run.apply_card(ch, _card(id, run, ch), {}, tables, {}, r), "")
	var ws := ch.inventory.weapon_options(tables)
	assert_eq(ws.size(), 3, "兵器保留 3 把")
	assert_eq(ch.inventory.count("w_mudao"), 0, "丟掉攻擊最低、沒裝備的木刀")
	# 護具：換下的同欄位丟掉
	assert_eq(run.apply_card(ch, _card("rg_c_wpn_a_pijia", run, ch), {}, tables, {}, r), "")
	assert_eq(ch.inventory.count("a_bupao"), 0, "布衣丟掉")
	assert_eq(str(ch.inventory.equipped_row("ARMOR", tables).get("id", "a_pijia")), "a_pijia")

func test_attr_card_alloc_rules() -> void:
	var run := RogueRun.new()
	var ch := _char()
	var c := _card("rg_c_attr_fine", run, ch)
	assert_eq(int(c.points), 4)
	assert_eq(run.apply_card(ch, c, {}, tables, {}, r), "rogue_bad_alloc", "沒給 alloc")
	assert_eq(run.apply_card(ch, c, { "str": 3 }, tables, {}, r), "rogue_bad_alloc", "沒分完")
	assert_eq(run.apply_card(ch, c, { "str": 5, "con": -1 }, tables, {}, r), "rogue_bad_alloc", "負數")
	assert_eq(run.apply_card(ch, c, { "nope": 4 }, tables, {}, r), "rogue_bad_alloc", "不是屬性")
	ch.attrs["str"] = 43
	assert_eq(run.apply_card(ch, c, { "str": 4 }, tables, {}, r), "rogue_attr_cap", "超過 45")
	assert_eq(run.apply_card(ch, c, { "str": 2, "agi": 2.0 }, tables, {}, r), "", "整數的 float 也收")
	assert_eq(int(ch.attrs.str), 45)
	assert_eq(int(ch.attrs.agi), 22)
	assert_eq(run.taken.size(), 1, "失敗的不算拿過")

func test_ally_card_and_full() -> void:
	var run := RogueRun.new()
	var ch := _char()
	for id in ["rg_c_ally_hs_dizi", "rg_c_ally_wushi"]:
		assert_eq(run.apply_card(ch, _card(id, run, ch), {}, tables, {}, r), "")
	assert_eq(run.allies.size(), 2)
	assert_eq(str(run.allies[0].monster), "m_hs_trainee")
	var shares: Dictionary = r.get("ally_share", {})   # 整合者：份額照 rogue_rules 的校準值（ROGUE_PLAN §12）
	assert_eq(float(run.allies[0].share), float(shares.COMMON), "凡 → rogue_rules.ally_share.COMMON")
	assert_eq(float(run.allies[1].share), float(shares.FINE), "良 → rogue_rules.ally_share.FINE")
	assert_true(run.allies[1].has("override"), "MUD 數值列太強的隊友帶 override")
	assert_eq(run.apply_card(ch, _card("rg_c_ally_zhouzhiruo", run, ch), {}, tables, {}, r), "rogue_ally_full")
	run.allies[0]["alive"] = false
	assert_eq(run.apply_card(ch, _card("rg_c_ally_zhouzhiruo", run, ch), {}, tables, {}, r), "", "有一位倒下 → 可以再招")
	assert_eq(str(run.allies[2].name), "周芷若")
	assert_eq(str(run.allies[2].ref), "n_em_zhouzhiruo")
	assert_true(str(run.allies[0].slot) != str(run.allies[2].slot), "slot 不重複")
	var sp := RogueFoes.ally_spec(run.allies[2], 40.0, tables)
	assert_eq(str(sp.kind), "ALLY")
	assert_eq(int(sp.side), 0)
	assert_eq(str(sp.rg_ally), str(run.allies[2].slot))
	var want := 40.0 * float(shares.RARE)
	assert_true(absf(RoguePower.unit_power(sp, tables) - want) <= want * 0.1, "縮放到份額")

func test_best_card_rule() -> void:
	var run := RogueRun.new()
	var ch := _char()
	run.apply_card(ch, _card("rg_c_art_hs_jianfa", run, ch), {}, tables, {}, r)
	assert_eq(str(run.best_card.rarity), "COMMON")
	run.apply_card(ch, _card("rg_c_art_em_foguang", run, ch), {}, tables, {}, r)
	assert_eq(str(run.best_card.id), "rg_c_art_em_foguang", "稀有度高者")
	run.apply_card(ch, _card("rg_c_art_sl_changquan", run, ch), {}, tables, {}, r)
	assert_eq(str(run.best_card.id), "rg_c_art_em_foguang", "低的不換")
	run.apply_card(ch, _card("rg_c_art_qz_tonggui", run, ch), {}, tables, {}, r)
	assert_eq(str(run.best_card.id), "rg_c_art_qz_tonggui", "同階取較晚的")

func test_on_won_summary_and_dict() -> void:
	var run := RogueRun.new()
	run.run_id = "rr1"
	run.seed = 77
	run.on_won(2, false)
	run.round = 5
	run.on_won(3, true, "rg_f_zhouzhiruo")
	assert_eq(run.wins, 2)
	assert_eq(run.round, 6)
	assert_eq(run.foes_beaten, 5)
	assert_eq(run.bosses_beaten, 1)
	assert_eq(run.extra_picks, 1, "首領 → 多一次選卡")
	run.cause = "ABANDON"
	var sm := run.summary()
	for k in ["run_id", "seed", "cause", "rounds", "wins", "foes_beaten", "bosses_beaten", "best_card", "allies_recruited",
			"points_gained", "points_total", "new_best"]:
		assert_true(sm.has(k), "summary 有 %s" % k)
	assert_eq(str(sm.cause), "ABANDON")
	assert_eq(sm.famous_beaten, ["rg_f_zhouzhiruo"])
	var back := RogueRun.from_dict(run.to_dict())
	assert_eq(back.to_dict(), run.to_dict(), "to_dict／from_dict 來回一致")

func test_rng_for_streams() -> void:
	var run := RogueRun.new()
	run.seed = 5
	assert_eq(run.rng_for("roll").randi(), run.rng_for("roll").randi(), "同狀態同亂數")
	assert_true(run.rng_for("roll").randi() != run.rng_for("foes").randi(), "不同串流不同")
	var a := run.rng_for("draw").randi()
	run.draws += 1
	assert_true(run.rng_for("draw").randi() != a, "同回合第二次抽卡不同")
