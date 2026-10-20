extends "res://tests/unit/test_pk_world_base.gd"
## M3c 審查（第三輪，設計／平衡）回歸：
## 1. 紫金八卦刀：名稱真、數值編 → src proposal（classic_strict 的 later_loot 照樣不擋）
## 2. 黃罩甲換成 M3c O13 級距：def ⌈35 ÷ 5⌉ = 7、official.def 35；不再比所有 M3c 防具都高
## 3. 神兵全服鎖：神兵群組每張表全服每 lockout_shichen 只擲一次（隊友輪流搶最後一擊不再倍增）
## 4. 拿著神兵就沒有新手保護（不能把神兵寄放在新手分身上）
## 5. 羊、採礦師與黃狗同一個時代規則 → 1.0B（classic_strict 沒有；不列在 1.0A 房間清單）
## 6. 機關人不掉寶（gaoshou/25「--（無）」）
## 7. 白猿扣善惡：列【待考證】（M3C_PLAN §1.2）

const SWORD := "w_sb_yitian"

func _loot():
	return host().get("loot")

# ---------------------------------------------------------------- 1、2、5、6、7：資料
func test_zijin_blade_is_proposal_and_still_drops_in_strict() -> void:
	if not game_ok():
		return
	var it: Dictionary = GameData.tables["items"]["w_lt_zijinbaguadao"]
	assert_eq(str(it["src"]), "proposal", "invented numbers on a real name = proposal")
	var lt := { "guaranteed": [], "groups": [{ "chance": 1.0, "pick": [{ "item": "w_lt_zijinbaguadao", "w": 1 }] }] }
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var got := BattleRewards.roll_table(lt, GameData.tables, rng, { "rules": { "divine_source": "NONE", "later_loot": false } })
	assert_true(got.any(func(x): return str(x["id"]) == "w_lt_zijinbaguadao"), "later_loot only blocks src later")

func test_huangjia_on_m3c_armor_scale() -> void:
	if not game_ok():
		return
	var it: Dictionary = GameData.tables["items"]["a_huangjia"]
	assert_eq(int(it["official"]["def"]), 35, "official +35 kept")
	assert_eq(int(it["def"]), int(ceil(35.0 / 5.0)), "O13: def = ceil(official / 5)")
	assert_false(str(it["src_note"]).begins_with("M3b"), "the note leads with the current value")
	# 不比最好的官方衣服（羊皮襖子 8）好
	assert_true(int(it["def"]) <= int(GameData.tables["items"]["a_lt_yangpiaozi"]["def"]), "not better than 羊皮襖子")

func test_sheep_and_miner_are_1_0b_like_the_dog() -> void:
	if not game_ok():
		return
	for nid in ["n_na_xw_yang", "n_na_xe_kuangshi", "n_na_xx_huanggou"]:
		assert_eq(str(GameData.tables["npcs"][nid]["era"]), "1.0B", nid)
	assert_true(host().index.npcs_in("xw_grass").has("n_na_xw_yang"), "default world: the sheep is on 荒草坡 (room field)")
	assert_true(host().index.npcs_in("xe_mine").has("n_na_xe_kuangshi"), "default world: the miner is at the mine")
	# 1.0A 的房間清單不列 1.0B NPC（M3b L7）
	for rid in ["xixia_wild", "xixia_east"]:
		var m: Dictionary = GameData.tables["maps"][rid]
		for room in m["rooms"]:
			for nid in room.get("npcs", []):
				assert_false(str(nid) in ["n_na_xw_yang", "n_na_xe_kuangshi"], "%s lists %s" % [str(room["id"]), str(nid)])
	use_preset("classic_strict")
	for nid in ["n_na_xw_yang", "n_na_xe_kuangshi"]:
		assert_false(GameData.tables["npcs"].has(nid), "classic_strict (1.0A) has no %s" % nid)

func test_jiguanren_drops_no_treasure() -> void:
	if not game_ok():
		return
	var m: Dictionary = GameData.tables["monsters"]["m_gc_jiguanren"]
	assert_eq(str(m.get("loot_table", "")), "", "gaoshou/25: 機關人 drops nothing")
	for d in m.get("drops", []):
		assert_eq(BattleRewards.rarity_of(GameData.tables, str(d["item"])), "COMMON", "only the 凡品 salvage")
	assert_true(str(GameData.tables["monsters"]["m_gc_jiguanren2"].get("loot_table", "")) != "", "the 銅甲 boss keeps its table")

func test_baiyuan_morality_is_documented_as_unverified() -> void:
	if not game_ok():
		return
	var m: Dictionary = GameData.tables["monsters"]["m_wd_baiyuan"]
	assert_eq(int(m["morality_on_kill"]), 0)
	assert_true(str(m["src_note"]).contains("扣善惡") and str(m["src_note"]).contains("待考證"), "the verified fact is recorded, deferral tagged")
	var plan := FileAccess.get_file_as_string("res://docs/M3C_PLAN.md")
	assert_true(plan.contains("殺白猿、黃兔扣善惡"), "listed in M3C_PLAN §1.2")

# ---------------------------------------------------------------- 3：神兵全服鎖
func test_roll_table_divine_group_world_lock() -> void:
	if not game_ok():
		return
	var lt := { "id": "lt_test_boss", "lockout_shichen": 12, "guaranteed": [],
		"groups": [{ "chance": 1.0, "divine": true, "pick": [{ "item": SWORD, "w": 1 }] }] }
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var ctx := { "rules": { "divine_source": "BOSS_DROP" }, "blocked": [] }
	var got := BattleRewards.roll_table(lt, GameData.tables, rng, ctx)
	assert_eq(got.size(), 1, "first roll drops the 神兵")
	assert_eq(ctx.get("divine_rolled", []), ["lt_test_boss"], "the roll is recorded")
	# 同一場第二隻同表的怪：已經擲過
	ctx["divine_dropped"] = []
	assert_true(BattleRewards.roll_table(lt, GameData.tables, rng, ctx).is_empty(), "second monster of the same table in one battle")
	# 全服鎖著（別人剛打過）
	var ctx2 := { "rules": { "divine_source": "BOSS_DROP" }, "blocked": [], "divine_locked": ["lt_test_boss"] }
	assert_true(BattleRewards.roll_table(lt, GameData.tables, rng, ctx2).is_empty(), "world-locked table never rolls the 神兵")
	assert_false(ctx2.has("divine_rolled"), "a locked table is not re-recorded")
	# 強制掉落（除錯）照舊可以
	var ctx3 := { "rules": { "divine_source": "BOSS_DROP" }, "blocked": [], "divine_locked": ["lt_test_boss"], "force": [SWORD] }
	assert_eq(BattleRewards.roll_table(lt, GameData.tables, rng, ctx3).size(), 1, "debug force still works")
	assert_eq(BattleRewards.DIVINE_LOCK_SCOPE, "WORLD", "balance_sim models a world lock")

func _fight_guiwang() -> Dictionary:
	make_strong()
	ch().combat_xp = 200000
	for sk in ["basic_fist", "basic_blade", "basic_dodge", "basic_parry"]:
		ch().skills.set_level(sk, 120, tables())
	ch().attrs["con"] = 300
	Survival.rest_full(ch(), tables(), ws.options)
	start_battle(["m_guiwang"], "FIGHT")
	return drive_battle("fight")

func test_boss_kill_locks_the_divine_roll_for_everyone() -> void:
	if not game_ok():
		return
	make_char("鎖一")
	var res := _fight_guiwang()
	assert_eq(str(res.get("result", "")), "VICTORY")
	assert_has(_loot().divine_locked_tables(), "lt_m_guiwang", "world lock after one roll")
	var left: float = _loot().divine_lock_left("lt_m_guiwang")
	assert_true(left > WorldClock.shichen_len(host().day_s()) * 11.0, "about one game day: %.0f" % left)
	# 另一個角色（隊友輪流搶最後一擊）：reward_ctx 帶著全服鎖
	var b := add("鎖二")
	var ctx: Dictionary = _loot().reward_ctx({ "chars": { sess(b).peer_id: chr(b) } })
	assert_has(ctx.get("divine_locked", []), "lt_m_guiwang", "another character sees the world lock")
	assert_false(_loot().locked_tables(chr(b)).has("lt_m_guiwang"), "the per-character lock (normal groups) is still per character")
	# 上鎖不延長：再結算一次同樣的 ctx，到期時間不變
	var until := float(ws.world["divine_lock"]["lt_m_guiwang"])
	ctx["divine_rolled"] = ["lt_m_guiwang"]
	_loot().on_settle(sess(b), chr(b), [], ["m_guiwang"], sess(b).room_id())
	assert_eq(float(ws.world["divine_lock"]["lt_m_guiwang"]), until, "an active lock is not extended")
	ws.world["world_time_s"] = ws.world_time() + left + 1.0
	assert_false(_loot().divine_locked_tables().has("lt_m_guiwang"), "unlocked after a game day")

# ---------------------------------------------------------------- 4：神兵與新手保護
func test_divine_holder_loses_newbie_protection() -> void:
	if not deps_ok(true):
		return
	var a := add("老手")
	var b := add("新手分身")
	goto_p(a, "xw_road")
	goto_p(b, "xw_road")
	chr(a).combat_xp = 50000
	chr(b).combat_xp = 0
	assert_true(host().pk.newbie_protected(chr(b)), "a plain newbie is protected")
	assert_eq(reason_p(a, "force_pk", { "target": cid(b) }), "target_newbie_protected")
	assert_true(_loot().grant_divine(sess(b), SWORD).get("ok", false))
	assert_true(_loot().holds_divine(chr(b)))
	assert_false(host().pk.newbie_protected(chr(b)), "holding a 神兵 removes newbie protection")
	assert_false(host().pk.guard_spares(chr(b)), "guards no longer spare the holder")
	assert_false(bool(host().pk.player_tags(sess(b)).get("newbie", true)), "snapshot tag follows")
	make_strong_p(a)
	make_weak_p(b)
	ok_p(a, "force_pk", { "target": cid(b) })
	drive_bid(sess(a).battle_id, { a: "fight", b: "defend" })
	settle()
	assert_eq(chr(a).inventory.count(SWORD), 1, "the 神兵 can be taken back by force")
	assert_true(host().pk.newbie_protected(chr(b)), "protection returns once the 神兵 is gone")
