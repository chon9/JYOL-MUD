extends "res://tests/unit/test_world_fixture.gd"
## M3C_PLAN §6.6–6.7、§6.9（WP-LOOT）：真的主機打鬼王——強制掉落、rarity 帶到結算、lt_rare_drop、
## 【江湖傳聞】lt_rmr_rare_drop（規則 loot_broadcast 開關）、reward_ctx 的形狀與強制掉落只用掉一次。

func _fight_guiwang() -> Dictionary:
	make_strong()
	ch().combat_xp = 200000
	for sk in ["basic_fist", "basic_blade", "basic_dodge", "basic_parry"]:
		ch().skills.set_level(sk, 120, tables())
	ch().attrs["con"] = 300
	Survival.rest_full(ch(), tables(), ws.options)
	start_battle(["m_guiwang"], "FIGHT")
	return drive_battle("fight")

func _rumor_keys(list: Array) -> Array:
	var out: Array = []
	for e in list:
		out.append(str(e.get("p", {}).get("text_key", "")))
	return out

func test_forced_treasure_drop_reaches_settlement_and_rumor() -> void:
	if not game_ok():
		return
	assert_true(host().get("loot") != null, "LootSystem 已載入")
	make_char()
	var watcher := int(call("add_player", "旁觀者"))
	host().loot.debug_force(s(), "a_lt_hongshijie")
	assert_eq(host().loot.force_list(ch()), ["a_lt_hongshijie"])
	var res := _fight_guiwang()
	assert_eq(str(res.get("result", "")), "VICTORY", "打贏鬼王")
	var got := {}
	for it in res.get("rewards", {}).get("items", []):
		got[str(it.get("id", ""))] = it
	assert_true(got.has("a_lt_hongshijie"), "強制掉落出現在結算：%s" % str(got.keys()))
	assert_eq(str(got.get("a_lt_hongshijie", {}).get("rarity", "")), "TREASURE")
	assert_true(got.has("c_jingyao"), "掉落表必掉")
	assert_eq(item_count("a_lt_hongshijie"), 1)
	assert_false(lastp("lt_rare_drop").is_empty(), "本人收到 lt_rare_drop")
	assert_eq(str(lastp("lt_rare_drop").get("item_name", "")), "紅石戒")
	assert_has(_rumor_keys(call("evs_for", watcher, "jianghu_rumor")), "lt_rmr_rare_drop", "別人收到【江湖傳聞】")
	assert_eq(host().loot.force_list(ch()), [], "強制掉落用掉一次就清掉")

func test_no_broadcast_in_classic_strict() -> void:
	if not game_ok():
		return
	use_preset("classic_strict")
	assert_eq(GameData.rules.get("loot_broadcast", true), false, "classic_strict 關傳聞")
	make_char()
	var watcher := int(call("add_player", "旁觀者"))
	host().loot.debug_force(s(), "a_lt_hongshijie")
	var res := _fight_guiwang()
	assert_eq(str(res.get("result", "")), "VICTORY")
	# M3c 審查：classic_strict 的 later_loot 關 → 紅石戒（src later，2004 17173）連強制掉落也不掉
	assert_eq(item_count("a_lt_hongshijie"), 0, "後期版物品不掉")
	assert_true(lastp("lt_rare_drop").is_empty(), "沒有珍品就沒有通知")
	# 非後期版的珍品（珠索，jyfree 官方武器）照常有本人通知、沒有傳聞
	clear_events()
	host().loot.on_settle(s(), ch(), [{ "id": "w_lt_zhusuo", "name": "珠索", "n": 1, "rarity": "TREASURE" }], ["m_guiwang"], s().room_id())
	ws.flush()
	assert_false(lastp("lt_rare_drop").is_empty(), "本人照樣收到")
	assert_false(_rumor_keys(call("evs_for", watcher, "jianghu_rumor")).has("lt_rmr_rare_drop"), "沒有傳聞")

func test_reward_ctx_shape() -> void:
	if not game_ok():
		return
	make_char()
	ws.options["loot_drop_pct"] = 250
	host().loot.debug_force(s(), "w_lt_heijian")
	var ctx: Dictionary = host().loot.reward_ctx({ "chars": { 1: ch() } })
	assert_eq(ctx.get("force", []), ["w_lt_heijian"])
	assert_eq(int(ctx.get("drop_pct", 0)), 250)
	assert_eq(str(ctx.get("rules", {}).get("divine_source", "")), str(GameData.rules.get("divine_source", "")))
	assert_true(ctx.get("blocked") is Array)
	ws.options["loot_drop_pct"] = 9999
	assert_eq(int(host().loot.reward_ctx({ "chars": {} }).get("drop_pct", 0)), 300, "範圍 10–300")
	# 沒用到的強制掉落留著（例：打的是沒有這件的怪）
	host().loot.on_settle(s(), ch(), [], ["m_rabbit"], "xx_square")
	assert_eq(host().loot.force_list(ch()), ["w_lt_heijian"])

func test_shops_sell_new_gear_only_common_fine() -> void:
	if not game_ok():
		return
	var items: Dictionary = tables()["items"]
	var n_new := 0
	for nid in ["n_xx_smith", "n_dl_grocer"]:
		var shop: Array = tables()["npcs"][nid]["shop"]["items"]
		for iid in shop:
			if str(iid).begins_with("w_lt_") or str(iid).begins_with("a_lt_"):
				n_new += 1
				assert_true(str(items[iid].get("rarity", "COMMON")) in ["COMMON", "FINE"], "%s 不上架精品以上" % iid)
	assert_true(n_new >= 20, "西夏、大理上了新貨")

## M3c 審查（頭目鎖）：鬼王的掉落表擲過一次後，這個角色 12 時辰內只拿必掉；時間到了解鎖
func test_boss_lockout_per_character() -> void:
	if not game_ok():
		return
	make_char()
	var res := _fight_guiwang()
	assert_eq(str(res.get("result", "")), "VICTORY")
	assert_has(host().loot.locked_tables(ch()), "lt_m_guiwang", "locked after one roll")
	var left: float = host().loot.lock_left(ch(), "lt_m_guiwang")
	assert_true(left > WorldClock.shichen_len(host().day_s()) * 11.0, "about one game day: %.0f" % left)
	var ctx: Dictionary = host().loot.reward_ctx({ "chars": { 1: ch() } })
	assert_has(ctx.get("locked", {}).get(str(ch().id), []), "lt_m_guiwang", "reward_ctx carries the lock")
	ws.world["world_time_s"] = ws.world_time() + left + 1.0
	assert_false(host().loot.locked_tables(ch()).has("lt_m_guiwang"), "unlocked after a game day")
	# 強制掉落用掉後（_unforce）不能把鎖一起刪掉
	host().loot.debug_force(s(), "w_lt_heijian")
	host().loot._lock(ch(), "lt_m_guiwang")
	host().loot._unforce(ch(), "w_lt_heijian")
	assert_has(host().loot.locked_tables(ch()), "lt_m_guiwang", "unforce keeps the lock")
