extends "res://tests/unit/test_battle_helpers.gd"
## M3C_PLAN §6.6（WP-LOOT）：掉落表（必掉、群組、權重、loot_drop_pct、規則 manuals 關時不掉秘笈、神兵群組與全服唯一、
## force）、沒有 loot_table 的怪物結果與舊版相同（固定種子對照）、rarity 帶到結果。
## LootSystem 的結算、傳聞與規則開關在 test_m3c_loot_world.gd。

var lt_tables: Dictionary

func before_each() -> void:
	lt_tables = tables().duplicate(true)
	lt_tables["items"] = {
		"c_pill": { "id": "c_pill", "name": "藥", "rarity": "COMMON" },
		"a_fine": { "id": "a_fine", "name": "良品甲", "rarity": "FINE" },
		"a_fine2": { "id": "a_fine2", "name": "良品乙", "rarity": "FINE" },
		"a_gem": { "id": "a_gem", "name": "紅石戒", "rarity": "TREASURE" },
		"bk_book": { "id": "bk_book", "name": "醫書", "rarity": "TREASURE", "manual": { "skill": "basic_medic", "cap": 60 } },
		"w_god": { "id": "w_god", "name": "玄鐵重劍", "rarity": "DIVINE", "divine": true },
		"r_rabbitskin": { "id": "r_rabbitskin", "name": "兔皮" },
	}
	lt_tables["loot_tables"] = {
		"lt_boss": { "id": "lt_boss",
			"guaranteed": [{ "item": "c_pill", "min": 2, "max": 3 }],
			"groups": [
				{ "chance": 0.30, "pick": [{ "item": "a_fine", "w": 60 }, { "item": "a_fine2", "w": 40 }] },
				{ "chance": 0.05, "pick": [{ "item": "a_gem", "w": 70 }, { "item": "bk_book", "w": 30 }] },
				{ "chance": 0.002, "divine": true, "pick": [{ "item": "w_god", "w": 1 }] },
			] },
		"lt_books": { "id": "lt_books", "guaranteed": [], "groups": [{ "chance": 1.0, "pick": [{ "item": "bk_book", "w": 1 }] }] },
	}
	var boss: Dictionary = lt_tables["monsters"]["m_glass"].duplicate(true)
	boss["id"] = "m_boss"
	boss["loot_table"] = "lt_boss"
	lt_tables["monsters"]["m_boss"] = boss

const RULES_ON := { "divine_source": "BOSS_DROP", "manuals": true }

func _rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r

func _count(n_runs: int, ctx_base: Dictionary, table := "lt_boss") -> Dictionary:
	var c := {}
	for i in n_runs:
		var ctx := ctx_base.duplicate(true)
		for it in BattleRewards.roll_table(lt_tables["loot_tables"][table], lt_tables, _rng(1000 + i), ctx):
			c[it["id"]] = int(c.get(it["id"], 0)) + int(it["n"])
	return c

func test_guaranteed_and_groups_and_weights() -> void:
	var n := 4000
	var c := _count(n, { "rules": RULES_ON })
	assert_true(int(c.get("c_pill", 0)) >= 2 * n and int(c.get("c_pill", 0)) <= 3 * n, "必掉 2–3")
	var fine := int(c.get("a_fine", 0)) + int(c.get("a_fine2", 0))
	assert_true(absf(fine / float(n) - 0.30) < 0.03, "良品群組 30%%（實得 %.3f）" % (fine / float(n)))
	var share := int(c.get("a_fine", 0)) / float(maxi(1, fine))
	assert_true(absf(share - 0.60) < 0.05, "權重 60／40（實得 %.3f）" % share)
	var tre := int(c.get("a_gem", 0)) + int(c.get("bk_book", 0))
	assert_true(absf(tre / float(n) - 0.05) < 0.015, "珍品 5%%（實得 %.3f）" % (tre / float(n)))

func test_drop_pct_scales_groups_not_guaranteed() -> void:
	var n := 3000
	var base := _count(n, { "rules": RULES_ON, "drop_pct": 100 })
	var triple := _count(n, { "rules": RULES_ON, "drop_pct": 300 })
	var f1 := int(base.get("a_fine", 0)) + int(base.get("a_fine2", 0))
	var f3 := int(triple.get("a_fine", 0)) + int(triple.get("a_fine2", 0))
	assert_true(f3 > f1 * 2.5, "loot_drop_pct 300 → 約 3 倍（%d → %d）" % [f1, f3])
	assert_true(int(triple.get("c_pill", 0)) <= 3 * n, "必掉不受影響")
	var tenth := _count(n, { "rules": RULES_ON, "drop_pct": 10 })
	assert_true(int(tenth.get("a_fine", 0)) + int(tenth.get("a_fine2", 0)) < f1 / 5, "10% → 約十分之一")

func test_manuals_off_never_drops_manual() -> void:
	var c := _count(3000, { "rules": { "divine_source": "BOSS_DROP", "manuals": false } })
	assert_eq(int(c.get("bk_book", 0)), 0, "規則 manuals 關：秘笈權重當 0")
	assert_true(int(c.get("a_gem", 0)) > 0, "同群組的其他物品照常")
	assert_eq(_count(200, { "rules": { "manuals": false } }, "lt_books"), {}, "只有秘笈的群組 → 什麼都不掉")
	assert_eq(int(_count(50, { "rules": RULES_ON }, "lt_books").get("bk_book", 0)), 50)

func test_divine_group_rules_blocked_and_unique() -> void:
	# 規則 NONE（或沒有 ctx）→ 神兵群組不擲
	var forced := { "rules": { "divine_source": "NONE" }, "force": ["w_god"] }
	assert_eq(int(_count(50, forced).get("w_god", 0)), 0, "divine_source NONE：連強制都不掉")
	assert_eq(int(_count(50, { "force": ["w_god"] }).get("w_god", 0)), 0, "沒有規則（LootSystem 不在）＝不掉神兵")
	# BOSS_DROP：0.2% 機率；強制 → 必中
	var ctx := { "rules": RULES_ON, "force": ["w_god"] }
	var got := BattleRewards.roll_table(lt_tables["loot_tables"]["lt_boss"], lt_tables, _rng(5), ctx)
	assert_true(got.any(func(it): return it["id"] == "w_god"), "強制掉落必中")
	assert_eq(ctx.get("used_force", []), ["w_god"], "用掉的記在 ctx.used_force")
	assert_eq(ctx.get("divine_dropped", []), ["w_god"])
	# 同一個 ctx 再擲一次（同場第二隻頭目）→ 已掉出、強制已用完 → 不會再掉
	var again := BattleRewards.roll_table(lt_tables["loot_tables"]["lt_boss"], lt_tables, _rng(6), ctx)
	assert_false(again.any(func(it): return it["id"] == "w_god"), "全服唯一：同一場不會掉兩把")
	# 已有持有者（blocked）→ 這一擲作廢
	var ctx2 := { "rules": RULES_ON, "force": ["w_god"], "blocked": ["w_god"] }
	var got2 := BattleRewards.roll_table(lt_tables["loot_tables"]["lt_boss"], lt_tables, _rng(5), ctx2)
	assert_false(got2.any(func(it): return it["id"] == "w_god"), "有人持有 → 不掉")
	# 自然機率約 0.2%
	var n := 20000
	var natural := int(_count(n, { "rules": RULES_ON }).get("w_god", 0))
	assert_true(natural >= 15 and natural <= 70, "0.2%%（%d / %d）" % [natural, n])

func test_force_picks_item_in_its_group() -> void:
	var ctx := { "rules": RULES_ON, "force": ["a_gem"] }
	var got := BattleRewards.roll_table(lt_tables["loot_tables"]["lt_boss"], lt_tables, _rng(77), ctx)
	assert_true(got.any(func(it): return it["id"] == "a_gem"), "force 的物品在群組裡 → 必中該群組並選它")
	assert_false(got.any(func(it): return it["id"] == "bk_book"), "同群組只出一件")
	var ctx_out := { "rules": RULES_ON, "force": ["not_in_table"] }
	BattleRewards.roll_table(lt_tables["loot_tables"]["lt_boss"], lt_tables, _rng(77), ctx_out)
	assert_false(ctx_out.has("used_force"), "不在此表的強制掉落不會被用掉")

func _boss_battle(mid: String) -> Battle:
	var b := Battle.new(9, 4321, default_opts({}))
	b.add_unit(player_spec())
	b.add_unit(Encounter.monster_spec(mid, lt_tables))
	b.start(lt_tables)
	b.unit(2).state = BattleUnit.DEAD
	b.unit(2).killed_by = 1
	b.unit(1).kills = [mid]
	assert_true(b._check_end())
	return b

func test_compute_integrates_table_and_rarity() -> void:
	var r := BattleRewards.compute(_boss_battle("m_boss"), lt_tables, _rng(3), { "rules": RULES_ON, "force": ["a_gem"] })
	var items: Array = r[1].items
	var by := {}
	for it in items:
		by[it["id"]] = it
	assert_eq(int(by["r_rabbitskin"]["n"]), 2, "既有 drops 照舊先擲")
	assert_true(int(by["c_pill"]["n"]) >= 2, "掉落表必掉")
	assert_eq(by["a_gem"]["rarity"], "TREASURE", "rarity 帶到結果")
	assert_eq(by["r_rabbitskin"]["rarity"], "COMMON")

func test_no_loot_table_identical_to_before() -> void:
	# 同一個種子：沒有 loot_table 的怪物，給不給 ctx 結果都一樣（rng 用量也一樣：後面再抽一個數比對）
	for seed_v in [1, 2, 3, 99]:
		var r1 := _rng(seed_v)
		var r2 := _rng(seed_v)
		var a := BattleRewards.compute(_boss_battle("m_glass"), lt_tables, r1)
		var b := BattleRewards.compute(_boss_battle("m_glass"), lt_tables, r2, { "rules": RULES_ON, "force": ["a_gem"], "drop_pct": 300 })
		assert_eq(a, b, "seed %d" % seed_v)
		assert_eq(r1.randi(), r2.randi(), "rng 用量相同")

# ---------------------------------------------------------------- M3c 審查：頭目鎖、classic_strict 不掉後期版物品
func test_locked_table_only_guaranteed_but_force_still_works() -> void:
	var c := {}
	for i in 600:
		for it in BattleRewards.roll_table(lt_tables["loot_tables"]["lt_boss"], lt_tables, _rng(500 + i), { "rules": RULES_ON }, true):
			c[it["id"]] = int(c.get(it["id"], 0)) + int(it["n"])
	assert_true(int(c.get("c_pill", 0)) >= 1200, "guaranteed still given while locked")
	assert_eq(int(c.get("a_fine", 0)) + int(c.get("a_gem", 0)) + int(c.get("w_god", 0)), 0, "no group rolls while locked")
	var ctx := { "rules": RULES_ON, "force": ["a_gem"] }
	var got := BattleRewards.roll_table(lt_tables["loot_tables"]["lt_boss"], lt_tables, _rng(1), ctx, true)
	assert_true(got.any(func(it): return it["id"] == "a_gem"), "debug force ignores the lock")

func test_compute_respects_lock_and_records_roll() -> void:
	lt_tables["loot_tables"]["lt_boss"]["lockout_shichen"] = 12
	var b := _boss_battle("m_boss")
	var ref := str(b.unit(1).spec.get("ref", ""))
	var ctx := { "rules": RULES_ON }
	BattleRewards.compute(b, lt_tables, _rng(3), ctx)
	assert_eq(ctx.get("lockout_rolled", []), [[ref, "lt_boss"]], "an unlocked roll is recorded for LootSystem")
	var hits := 0
	for i in 300:
		var ctx2 := { "rules": RULES_ON, "drop_pct": 300, "locked": { ref: ["lt_boss"] } }
		var r := BattleRewards.compute(_boss_battle("m_boss"), lt_tables, _rng(900 + i), ctx2)
		for it in r[1].items:
			if str(it["id"]) in ["a_fine", "a_fine2", "a_gem", "bk_book", "w_god"]:
				hits += 1
		assert_false(ctx2.has("lockout_rolled"), "locked roll is not recorded again")
	assert_eq(hits, 0, "locked: only guaranteed/drops")

## M3c 第二輪審查：同一場兩隻用同一張鎖定表的怪（以前各自讀戰鬥開始時的快照、各擲一次）→ 只擲一次群組
func test_two_lockout_monsters_in_one_battle_roll_once() -> void:
	lt_tables["loot_tables"]["lt_boss"]["lockout_shichen"] = 12
	lt_tables["loot_tables"]["lt_boss"]["groups"] = [{ "chance": 1.0, "pick": [{ "item": "a_fine", "w": 1 }] }]
	var b := Battle.new(9, 4321, default_opts({}))
	b.add_unit(player_spec())
	b.add_unit(Encounter.monster_spec("m_boss", lt_tables))
	b.add_unit(Encounter.monster_spec("m_boss", lt_tables))
	b.start(lt_tables)
	for uid in [2, 3]:
		b.unit(uid).state = BattleUnit.DEAD
		b.unit(uid).killed_by = 1
	b.unit(1).kills = ["m_boss", "m_boss"]
	assert_true(b._check_end())
	var ref := str(b.unit(1).spec.get("ref", ""))
	var ctx := { "rules": RULES_ON }
	var r := BattleRewards.compute(b, lt_tables, _rng(3), ctx)
	var fine := 0
	for it in r[1].items:
		if str(it["id"]) == "a_fine":
			fine += int(it["n"])
	assert_eq(fine, 1, "the group is rolled once per character per battle")
	assert_eq(ctx.get("lockout_rolled", []), [[ref, "lt_boss"]], "recorded once")
	assert_true(BattleRewards.is_locked(ctx, ref, "lt_boss"), "a roll in this battle counts as locked")
	assert_false(BattleRewards.is_locked(ctx, "someone_else", "lt_boss"), "other characters are not locked")

func test_later_loot_off_skips_later_items() -> void:
	lt_tables["items"]["a_gem"]["src"] = "later"
	var c := _count(3000, { "rules": { "divine_source": "BOSS_DROP", "manuals": true, "later_loot": false } })
	assert_eq(int(c.get("a_gem", 0)), 0, "src later never drops when later_loot is off")
	assert_true(int(c.get("bk_book", 0)) > 0, "the rest of the group still drops")
	var ctx := { "rules": { "later_loot": false }, "force": ["a_gem"] }
	BattleRewards.roll_table(lt_tables["loot_tables"]["lt_boss"], lt_tables, _rng(1), ctx)
	assert_false(ctx.has("used_force"), "even a debug force cannot drop a later item in classic_strict")
