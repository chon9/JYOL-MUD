extends "res://tests/unit/test_sect_m3b_fixture.gd"
## M3B_PLAN §5.1.1、§11.1：位階（袋位）與聚會。
## 拜入 rank 0；任務獎勵 → 待升；DAILY 辰時聚會升級並扣 cost；requires 不成立保留；MONTHLY 只在 1 日；
## 離線錯過聚會登入補升；叛派歸 0；二階武功在二袋前回 req_sect_rank_min；RANK 選單、角色表 sect_info.rank。

func _setup() -> void:
	install_gb()
	make_char("測丐弟子")

func test_join_sets_rank_zero_and_sheet() -> void:
	if not game_ok():
		return
	_setup()
	ch().sect_rank = 5   # 舊值要被拜入蓋掉
	goto(GB_HALL)
	ok("join_sect", { "npc": CHEN })
	assert_eq(str(ch().sect), GB)
	assert_eq(int(ch().sect_rank), 0, "拜入＝promote JOIN 的列")
	refresh_sheet()
	var rk: Variant = sheet().get("sect_info", {}).get("rank")
	assert_true(rk is Dictionary, "sect_info.rank")
	assert_eq(int(rk.get("level", -1)), 0)
	assert_eq(str(rk.get("name", "")), "無袋弟子")
	assert_eq(rk.get("pending"), null)
	assert_eq(str(rk.get("next", {}).get("name", "")), "一袋弟子")
	assert_true((rk.get("next", {}).get("requires_text", []) as Array).size() >= 2, "下一袋的條件文字")

func test_rank_menu_on_rank_service() -> void:
	if not game_ok():
		return
	_setup()
	join_gb()
	goto(GB_HALL)
	clear_events()
	ok("talk", { "npc": CHEN })
	var m := lastp("npc_menu")
	assert_true(m.get("rank") is Dictionary, "RANK 服務的 npc_menu.rank")
	var rows: Array = m["rank"].get("rows", [])
	assert_eq(rows.size(), 4)
	assert_true(bool(rows[0].get("current", false)))
	assert_eq(str(rows[1].get("quest", "")), Q_DAI1)
	assert_eq(str(m["rank"].get("assembly_mode", "")), "DAILY")
	assert_true(m.has("bank") and m.has("escort") and m.has("org") and m.has("beg"), "M3b npc_menu 欄位一律存在")

func test_quest_reward_queues_pending_then_daily_assembly_promotes() -> void:
	if not game_ok():
		return
	_setup()
	join_gb()
	ch().fame = 300
	ch().lilian = 300
	# 走任務獎勵的路徑（QuestSystem._give_rewards → SectSystem.queue_rank）
	host().quests._give_rewards(s(), { "sect_rank": { "sect": GB, "rank": 1 } }, false)
	ws.flush()
	assert_eq(int(ch().sect_rank), 0, "assembly：先記待升")
	assert_eq(str(ch().sect_rank_pending.get("sect", "")), GB)
	assert_eq(int(ch().sect_rank_pending.get("rank", 0)), 1)
	assert_eq(str(lastp("rank_wait").get("reason", "")), "assembly")
	refresh_sheet()
	assert_eq(int(sheet()["sect_info"]["rank"]["pending"]["rank"]), 1)
	clear_events()
	to_next_chen()
	assert_eq(int(ch().sect_rank), 1, "辰時聚會升一袋")
	assert_true(ch().sect_rank_pending.is_empty())
	assert_false(evs("sect_assembly").is_empty(), "聚會事件")
	assert_eq(str(lastp("sect_rank_up").get("rank_name", "")), "一袋弟子")
	# 同一遊戲日只聚一次
	var day := int(ws.world.get("gb_assembly_last_day", 0))
	clear_events()
	host().sects.assembly_tick(host().now_s())
	assert_true(evs("sect_assembly").is_empty(), "同一天不再聚")
	assert_eq(int(ws.world.get("gb_assembly_last_day", 0)), day)

func test_cost_deducted_and_requires_rechecked() -> void:
	if not game_ok():
		return
	_setup()
	join_gb()
	ch().sect_rank = 1
	ch().fame = 600
	ch().lilian = 600
	host().sects.queue_rank(s(), GB, 2)
	# 聚會前名聲掉到門檻以下 → 保留待升
	ch().fame = 400
	clear_events()
	to_next_chen()
	assert_eq(int(ch().sect_rank), 1, "requires 不成立：繼續等")
	assert_eq(int(ch().sect_rank_pending.get("rank", 0)), 2)
	assert_eq(str(lastp("rank_wait").get("reason", "")), "requires")
	ch().fame = 600
	to_next_chen()
	assert_eq(int(ch().sect_rank), 2)
	assert_eq(int(ch().fame), 350, "升二袋扣名聲 250")
	assert_eq(int(ch().lilian), 350, "扣歷練 250")

func test_auto_rank_on_assembly() -> void:
	if not game_ok():
		return
	_setup()
	join_gb()
	ch().sect_rank = 2
	ch().fame = 1300
	to_next_chen()
	assert_eq(int(ch().sect_rank), 3, "AUTO 列：requires 成立就在聚會時升一級")

func test_monthly_only_on_day_one() -> void:
	if not game_ok():
		return
	_setup()
	join_gb()
	ws.options["gb_assembly"] = "MONTHLY"
	ch().fame = 300
	ch().lilian = 300
	host().sects.queue_rank(s(), GB, 1)
	to_next_chen()   # 第 2 日辰時
	assert_eq(int(ch().sect_rank), 0, "MONTHLY：不是 1 日不聚會")
	var sys = host().sects
	assert_eq(sys.last_assembly_day(sys.assembly_time_of_day(31) + 1.0), 31)
	assert_eq(sys.last_assembly_day(sys.assembly_time_of_day(45) + 1.0), 31)
	# 快轉到第 31 日辰時
	var day_len := float(ws.options.get("game_day_real_s", 7200))
	ws.world["world_time_s"] = sys.assembly_time_of_day(31) + 1.0
	ws.advance(0.1)
	host()._minute_jobs()
	assert_eq(int(ch().sect_rank), 1, "MONTHLY：每月 1 日辰時聚會")
	assert_true(day_len > 0.0)

func test_offline_member_catches_up_on_login() -> void:
	if not game_ok():
		return
	_setup()
	join_gb()
	ch().fame = 300
	ch().lilian = 300
	host().sects.queue_rank(s(), GB, 1)
	var cid := str(ch().id)
	host().switch_out(s())   # 離線（存檔、離開世界）
	ws.flush()
	to_next_chen()           # 聚會時不在線
	ok("char_select", { "char_id": cid })
	assert_eq(int(ch().sect_rank), 1, "登入時補升（錯過了一次聚會）")
	assert_true(ch().sect_rank_pending.is_empty())

func test_betray_resets_rank() -> void:
	if not game_ok():
		return
	_setup()
	join_gb()
	ch().sect_rank = 2
	ch().sect_rank_pending = { "sect": GB, "rank": 3, "since_world_s": 0.0 }
	goto(GB_HALL)
	ok("sect_betray", { "npc": CHEN, "confirm": true })
	assert_eq(int(ch().sect_rank), 0, "叛派歸 0")
	assert_true(ch().sect_rank_pending.is_empty(), "清待升")

func test_advanced_art_needs_rank_two() -> void:
	if not game_ok():
		return
	_setup()
	join_gb()
	ch().learn_points = 10000
	ch().combat_xp = 100000
	goto(GB_HALL)
	assert_eq(reason("learn", { "npc": CHEN, "skill": GB_ADV }), "req_sect_rank_min", "二袋前學不到二階武功")
	ch().sect_rank = 2
	ok("learn", { "npc": CHEN, "skill": GB_ADV })
	assert_true(int(ch().skills.level(GB_ADV)) >= 1)

func test_debug_set_sect_rank_and_assembly_now() -> void:
	if not game_ok():
		return
	_setup()
	join_gb()
	var IntentsDebug: GDScript = load("res://server/intents/intents_debug.gd")
	var r: Dictionary = IntentsDebug.apply(host(), s(), "sect_rank", 1)
	assert_true(r.get("ok", false))
	assert_eq(int(ch().sect_rank), 1)
	assert_eq(str(IntentsDebug.apply(host(), s(), "guild", "g1").get("reason", "")), "bad_value:key")
	ch().fame = 600
	ch().lilian = 600
	host().sects.queue_rank(s(), GB, 2)
	assert_true(IntentsDebug.apply(host(), s(), "assembly_now", true).get("ok", false))
	assert_eq(int(ch().sect_rank), 2, "assembly_now 立刻聚會")
