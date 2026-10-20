extends "res://tests/unit/test_world_fixture.gd"
## M3c 審查（第二輪，設計／平衡）回歸：
## - 新手保護（newbie_guard_spare）：預設規則城內行兇不招官兵、確認框不寫官兵；classic_strict 照 2001 規則照樣招、善惡負照樣追殺
## - 門口硬闖戰改用有獎勵的專用列（全真一場 160 學點、血刀 60）；執法列 m_*_guard 照舊沒有獎勵
## - 孫婆婆滅派每次 6 人（2001 規則）；黃狗 1.0B、掉黃狗肉，羊掉獸皮；紫金八卦刀 src（第三輪改 proposal）；丁春秋／血刀老祖 attack 是 proposal
## - 稀有掉落只送 lt_rare_drop（不再多一行 item_gain）；丐幫乞討的戰報有模板；debug vital: 鍵
const NA := preload("res://tests/unit/test_m3c_npc_attack.gd")

func _setup(city := "dali", room := "dl_square", xp := 0) -> bool:
	if not game_ok():
		return false
	ws.options["sect_hostile_entry"] = false
	ws.options["encounters_enabled"] = false
	if make_char("二審俠客", city) == null:
		return false
	make_strong()
	ch().combat_xp = xp
	goto(room)
	clear_events()
	return true

func _foes() -> Array:
	var e: Dictionary = NA.battle_entry(self)
	if e.is_empty():
		return []
	return (e["battle"] as Battle).units.filter(func(u): return not u.is_player())

# ---------------------------------------------------------------- 新手與守城官兵
func test_newbie_spared_by_guard_strike_in_default_rules() -> void:
	if not _setup("dali", "dl_square", 0):
		return
	assert_true(GameData.rules.get("newbie_guard_spare", true) != false, "default rules spare newbies")
	var atk: Variant = NA.npc_entry(view(), "n_na_dl_xiaohai").get("atk", null)
	assert_true(atk is Dictionary and bool((atk as Dictionary).get("guard_spare", false)), "view tells the client guards spare me")
	assert_false(str((atk as Dictionary).get("warn", "")).contains("官兵"), "no guard warning for a spared newbie")
	ok("npc_attack", { "npc": "n_na_dl_xiaohai" })
	NA.finish(self)
	assert_true(evs("na_guard_alarm").is_empty(), "no guard alarm")
	assert_false(evs("na_guard_spare").is_empty(), "guards scold the newbie instead")
	assert_eq(s().battle_id, 0, "no GUARD battle")
	# 善惡變負的新手進出城也不被追殺
	assert_true(int(ch().morality) < 0)
	goto("dl_gate_n")
	clear_events()
	ok("move", { "dir": "N" })
	assert_eq(s().battle_id, 0, "negative-morality newbie not chased when leaving the city")

func test_classic_strict_has_no_newbie_exemption() -> void:
	if not _setup("dali", "dl_square", 0):
		return
	use_preset("classic_strict")
	assert_eq(GameData.rules.get("newbie_guard_spare", true), false, "classic_strict: 2001 rule")
	var atk: Variant = host().npcpk.view_entry(s(), "n_na_dl_xiaohai")
	assert_false(atk is Dictionary and bool((atk as Dictionary).get("guard_spare", false)), "strict: not spared")
	ok("npc_attack", { "npc": "n_na_dl_xiaohai" })
	NA.finish(self)
	assert_false(evs("na_guard_alarm").is_empty(), "strict: guards come for the newbie too")
	var g: Dictionary = NA.battle_entry(self)
	assert_eq(str(g.get("kind", "")), "GUARD")
	NA.finish(self)
	# news_4-2：善惡為負進出城就被守衛追殺（沒有新手例外）
	ch().morality = -5
	var pk = host().get("pk")
	assert_false(bool(pk.guard_spares(ch())), "strict: guard_spares false")
	assert_eq(MoralityPk.guard_count(0, -5, bool(pk.guard_spares(ch()))), 1)

func test_veteran_still_gets_guards() -> void:
	if not _setup("dali", "dl_square", 5000):
		return
	ok("npc_attack", { "npc": "n_na_dl_xiaohai" })
	NA.finish(self)
	assert_false(evs("na_guard_alarm").is_empty())
	assert_eq(str(NA.battle_entry(self).get("kind", "")), "GUARD")
	NA.finish(self)

# ---------------------------------------------------------------- 門口硬闖戰有收穫
func test_gate_fights_give_rewards_enforcers_do_not() -> void:
	if not _setup("xixia", "xx_square", 200000):
		return
	for sect in ["qz", "hg", "em", "lj", "xh", "xd"]:
		var gate: Dictionary = tables()["monsters"].get("m_npc_%s_gate" % sect, {})
		assert_false(gate.is_empty(), "m_npc_%s_gate exists" % sect)
		assert_false(bool(gate.get("no_rewards", true)), "%s gate row gives rewards" % sect)
		assert_true(int(gate.get("learn_points", 0)) > 0 and int(gate.get("combat_xp", 0)) > 0, "%s gate: 學點、實戰" % sect)
		var enf: Dictionary = tables()["monsters"].get("m_%s_guard" % sect, {})
		assert_true(bool(enf.get("no_rewards", false)), "enforcer m_%s_guard unchanged (no rewards)" % sect)
	for nid in ["n_qz_zhike", "n_hg_zhike", "n_em_gatedizi", "n_lj_zhike", "n_xh_menren", "n_xd_guard"]:
		var a: Dictionary = host().npc_row(nid).get("attack", {})
		assert_true(str(a.get("monster", "")).begins_with("m_npc_") and str(a.get("monster", "")).ends_with("_gate"), "%s uses its gate row" % nid)
	# 研究 gaoshou/31：全真「點知客」一場 160 學點（4 名 × 40）、血刀派一場 60（2 名 × 30）
	var qz: Dictionary = tables()["monsters"]["m_npc_qz_gate"]
	assert_eq(int(qz["learn_points"]) * 4, 160)
	assert_eq(int(tables()["monsters"]["m_npc_xd_gate"]["learn_points"]) * 2, 60)

func test_qz_gate_fight_pays_learn_points() -> void:
	if not _setup("xixia", "qz_gate", 200000):
		return
	var lp0 := int(ch().learn_points)
	ok("npc_attack", { "npc": "n_qz_zhike" })
	assert_eq(_foes().size(), 4)
	NA.finish(self)
	assert_true(int(ch().learn_points) - lp0 >= 160, "全真硬闖一場 ≥ 160 學點（%d）" % (int(ch().learn_points) - lp0))

# ---------------------------------------------------------------- 孫婆婆、黃狗、羊、資料標記
func test_sunpopo_always_six() -> void:
	if not game_ok():
		return
	var a: Dictionary = GameData.tables["npcs"]["n_gm_sunpopo"]["attack"]
	assert_false(a.has("group_repeat"), "2001 rule: no 6→4 repeat group")
	var n := 1
	for g in a.get("group", []):
		n += int(g["count"][1])
	assert_eq(n, 6)

func test_dog_is_1_0b_and_drops_dog_meat_sheep_drops_hide() -> void:
	if not game_ok():
		return
	var all_npcs: Dictionary = GameData.loader.all_tables["npcs"] if GameData.get("loader") != null else {}
	if not all_npcs.is_empty():
		assert_eq(str(all_npcs["n_na_xx_huanggou"]["era"]), "1.0B", "黃狗：2001-10 才有出處")
	assert_true(GameData.tables["npcs"].has("n_na_xx_huanggou"), "default world (1.0A+1.0B) has the dog")
	var dog_m: Dictionary = GameData.tables["monsters"][str(GameData.tables["npcs"]["n_na_xx_huanggou"]["attack"]["monster"])]
	assert_eq(str(dog_m["drops"][0]["item"]), "r_gourou", "黃狗掉黃狗肉")
	assert_eq(str(GameData.tables["items"]["r_gourou"]["name"]), "黃狗肉")
	var sheep_m: Dictionary = GameData.tables["monsters"][str(GameData.tables["npcs"]["n_na_xw_yang"]["attack"]["monster"])]
	assert_eq(str(sheep_m["drops"][0]["item"]), "r_shoupi", "羊掉獸皮，不掉豬肉")
	use_preset("classic_strict")
	assert_false(GameData.tables["npcs"].has("n_na_xx_huanggou"), "classic_strict (1.0A only) has no dog")
	assert_true(GameData.tables["items"].has("w_lt_zijinbaguadao"))
	# M3c 第三輪審查：名稱是 2001 的、數值是編的 → proposal（test_m3c_review3）
	assert_eq(str(GameData.tables["items"]["w_lt_zijinbaguadao"]["src"]), "proposal", "紫金八卦刀：真名、編的數值")

func test_zijin_blade_not_blocked_by_later_loot_off() -> void:
	if not game_ok():
		return
	var lt := { "guaranteed": [], "groups": [{ "chance": 1.0, "pick": [{ "item": "w_lt_zijinbaguadao", "w": 1 }] }] }
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var got := BattleRewards.roll_table(lt, GameData.tables, rng, { "rules": { "divine_source": "NONE", "manuals": false, "later_loot": false } })
	assert_true(got.any(func(it): return str(it["id"]) == "w_lt_zijinbaguadao"), "later_loot off still drops a 1.0A-named item")

func test_master_attack_src_is_proposal() -> void:
	if not game_ok():
		return
	for nid in ["n_xh_dingchunqiu", "n_xd_laozu"]:
		var a: Dictionary = GameData.tables["npcs"][nid]["attack"]
		assert_eq(str(a["src"]), "proposal", "%s: outsider = enemy is a proposal" % nid)
		assert_true(str(a["src_note"]).contains("已證實"), "%s: the betrayal part stays marked verified in the note" % nid)

# ---------------------------------------------------------------- 訊息
func test_rare_drop_not_announced_twice() -> void:
	if not game_ok():
		return
	make_char()
	host().loot.debug_force(s(), "a_lt_hongshijie")
	make_strong()
	ch().combat_xp = 200000
	for sk in ["basic_fist", "basic_blade", "basic_dodge", "basic_parry"]:
		ch().skills.set_level(sk, 120, tables())
	ch().attrs["con"] = 300
	Survival.rest_full(ch(), tables(), ws.options)
	clear_events()
	start_battle(["m_guiwang"], "FIGHT")
	var res := drive_battle("fight")
	assert_eq(str(res.get("result", "")), "VICTORY")
	assert_false(lastp("lt_rare_drop").is_empty(), "lt_rare_drop for the treasure")
	var dup := evs("item_gain").filter(func(e): return str(e.get("p", {}).get("item_name", "")) == "紅石戒")
	assert_eq(dup.size(), 0, "no second 你得到… line for the same treasure")
	assert_false(evs("item_gain").is_empty(), "ordinary drops still get item_gain")

func test_every_sect_effect_has_a_proc_template() -> void:
	if not game_ok():
		return
	var tpl: Dictionary = GameData.tables["text_templates"]
	for sid in GameData.tables["sects"]:
		var e: Variant = GameData.tables["sects"][sid].get("sect_skill_effect", {})
		var eff := str((e as Dictionary).get("effect", "")) if e is Dictionary else str(e)
		if eff != "":
			assert_true(tpl.has("battle_proc_" + eff), "%s: battle_proc_%s template" % [sid, eff])
	var line := TextRenderer.render_plain({ "ch": "BATTLE", "key": "battle_proc_POISON_FANG",
		"p": { "uid": 1, "name": "甲", "peer": 1, "skill_name": "乞討", "def_uid": 2 } }, 1, tpl)
	assert_false(line.begins_with("battle_proc_"), "rendered, not the raw key: " + line)
	assert_true(line.contains("乞討"), line)

func test_debug_vital_key() -> void:
	if not game_ok():
		return
	make_char()
	var D: GDScript = load("res://server/intents/intents_debug.gd")
	assert_true(bool(D.apply(host(), s(), "vital:qi", 3).get("ok", false)))
	assert_eq(int(ch().vitals["qi"]), 3)
	assert_true(bool(D.apply(host(), s(), "vital:food", 5).get("ok", false)))
	assert_eq(int(ch().vitals["food"]), 5)
	assert_eq(str(D.apply(host(), s(), "vital:nope", 5).get("reason", "")), "bad_value:key")
