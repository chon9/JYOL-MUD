extends "res://tests/unit/test_world_fixture.gd"
## 故事包審查修正的回歸測試（方法名 test_story_review_*；--filter=story 可單跑）。
## - learn_add：藍鳳凰「基本毒術升一級」每次完成都在目前等級上 +1（原本 learn 是絕對等級，1 級以上就沒升）
## - 放棄任務收回對話給的物品（龍門事件令重接 1→2→3 的漏洞）；失敗也收回
## - npc_here 尊重遊蕩惡人的位置（夜裡南海鱷神不在西大街，交談回 not_here）
## - 招呼語同一位 NPC 同一種態度只說一次，新手招呼只給商店／功能 NPC
## - NPC 依任務結局換話（ambient 交談列）
## - 預告傳聞只放線上有人接得了的任務
## - 新手遇上夜遊惡人：不開打，但有一段威嚇
## - 任務變數 random（日月鞭法的隨機佛經）
## - 全服第一位完成的傳聞帶結局名

func before_each() -> void:
	world_name = "w_story_review"
	super.before_each()

# ---------------------------------------------------------------- learn_add
func test_story_review_learn_add_is_relative() -> void:
	if not game_ok():
		return
	make_char()
	ch().skills.set_level("basic_poison", 3, tables())
	assert_true(host().quests.debug_stage(s(), "q_lanfeng", "s_return").get("ok", false), "debug_stage")
	host().quests._finish(s(), "q_lanfeng", "default")
	assert_eq(int(ch().skills.level("basic_poison")), 4, "已有 3 級：完成後升到 4 級（原本 learn 絕對等級 1 → 不變）")
	# 機制：直接指定 default 結局時 learn_add 照樣在目前等級上 +1（實際再做會走 repeat 結局，見 test_world_story_review3）
	ch().quests["cd"].erase("q_lanfeng")
	assert_true(host().quests.debug_stage(s(), "q_lanfeng", "s_return").get("ok", false), "debug_stage again")
	host().quests._finish(s(), "q_lanfeng", "default")
	assert_eq(int(ch().skills.level("basic_poison")), 5, "第二次完成再升一級")
	var oc: Dictionary = tables()["quests"]["q_lanfeng"]["outcomes"]["default"]
	assert_eq(str(oc.get("field_src", {}).get("morality", "")), "later", "善惡 −100 標 later")

func test_story_review_learn_add_action() -> void:
	if not game_ok():
		return
	make_char()
	ch().skills.set_level("basic_poison", 2, tables())
	assert_true(host().quests.debug_stage(s(), "q_lanfeng", "s_return").get("ok", false))
	host().quests._run_actions(s(), "q_lanfeng", "", [{ "do": "learn", "skill": "basic_poison", "add": 1 }])
	assert_eq(int(ch().skills.level("basic_poison")), 3, "learn 動作的 add")
	var errs := QuestDef.check_actions([{ "do": "learn", "skill": "basic_poison", "add": 0 }], "t", {}, tables(), {})
	assert_true(errs.size() > 0, "add < 1 是 lint 錯誤")

# ---------------------------------------------------------------- 放棄收回
func _longmen_accept() -> void:
	ok("talk", { "npc": "n_wd_moshenggu" })
	ok("quest_talk", { "npc": "n_wd_moshenggu", "quest": "q_wd_longmen" })
	ok("dialogue_choose", { "npc": "n_wd_moshenggu", "quest": "q_wd_longmen", "node": "n0", "choice": "c_heard" })
	ok("dialogue_choose", { "npc": "n_wd_moshenggu", "quest": "q_wd_longmen", "node": "n1", "choice": "c_yes" })
	send("dialogue_close")

func test_story_review_abandon_takes_back_dialogue_items() -> void:
	if not game_ok():
		return
	make_char()
	ch().sect = "wudang"
	ch().attrs["wit"] = 30
	ch().attrs["cal"] = 30
	goto("wd_houshan")
	for i in 3:
		_longmen_accept()
		assert_true(ch().quests["active"].has("q_wd_longmen"), "accepted (round %d)" % i)
		assert_eq(item_count("i_wd_longmenling"), 1, "只有一面龍門事件令（round %d）" % i)
		ok("quest_abandon", { "quest": "q_wd_longmen" })
		assert_eq(item_count("i_wd_longmenling"), 0, "放棄時收回對話給的事件令（round %d）" % i)

func test_story_review_abandon_keeps_items_the_quest_already_took() -> void:
	if not game_ok():
		return
	make_char()
	give("i_wd_longmenling", 1)   # 玩家自己原本就有一面（例如別的來源）：任務只收回它自己給、還沒收回的
	assert_true(host().quests.debug_stage(s(), "q_wd_longmen", "s_orphan").get("ok", false))
	host().quests._run_actions(s(), "q_wd_longmen", "", [{ "do": "give", "item": "i_wd_longmenling", "n": 1 }])
	assert_eq(item_count("i_wd_longmenling"), 2)
	host().quests._run_actions(s(), "q_wd_longmen", "", [{ "do": "take", "item": "i_wd_longmenling", "n": 1 }])
	assert_eq(item_count("i_wd_longmenling"), 1)
	ok("quest_abandon", { "quest": "q_wd_longmen" })
	assert_eq(item_count("i_wd_longmenling"), 1, "任務給的那一面已經收回過，不再多收")

func test_story_review_given_survives_save() -> void:
	var raw := { "active": { "q_x": { "v": 2, "stage": "s1", "objs": {}, "vars": {}, "given": { "i_a": 2, "i_b": 0 } } } }
	var m := QuestState.migrate(raw)
	assert_eq(m["active"]["q_x"].get("given", {}), { "i_a": 2 }, "given 存檔往返（0 的丟掉）")
	var legacy := QuestState.migrate({ "active": { "q_y": { "v": 2, "stage": "s1", "objs": {}, "vars": {} } } })
	assert_false(legacy["active"]["q_y"].has("given"), "舊狀態沒有 given → 收回照舊只看 give_items")

# ---------------------------------------------------------------- 惡人位置
func test_story_review_npc_here_respects_wanderer() -> void:
	if not game_ok() or host().get("wander") == null:
		return
	make_char()
	goto("xx_street")
	set_shichen(5)   # 巳時：在西大街
	host().wander.tick(0.1)
	assert_eq(host().npc_here(s(), "n_nanhai"), "", "白天在定點")
	set_shichen(11)  # 亥時：夜遊
	host().wander.tick(0.1)
	assert_true(host().wander.room_of("w_nanhai") != "xx_street", "夜裡不在西大街：%s" % host().wander.room_of("w_nanhai"))
	assert_eq(host().npc_here(s(), "n_nanhai"), "not_here", "不在定點時交談回 not_here（與畫面一致）")
	assert_eq(reason("talk", { "npc": "n_nanhai" }), "not_here")

# ---------------------------------------------------------------- 招呼語
func test_story_review_greet_once_and_only_shops_for_newbies() -> void:
	if not game_ok():
		return
	make_char()
	goto("xx_inn")
	clear_events()
	ok("talk", { "npc": "n_xx_innkeeper" })
	assert_eq(evs("greet_newbie").size(), 1, "第一次交談招呼新手")
	clear_events()
	ok("talk", { "npc": "n_xx_innkeeper" })
	assert_eq(evs("greet_newbie").size(), 0, "同一位 NPC 不再重複招呼")
	clear_events()
	ok("talk", { "npc": "n_xx_laodenuo" })
	assert_eq(evs("greet_newbie").size(), 0, "STORY NPC 不招呼新手")
	# 態度變了（名聲 100）才再招呼
	ch().fame = 150
	clear_events()
	ok("talk", { "npc": "n_xx_laodenuo" })
	assert_eq(evs("greet_fame_small").size(), 1, "名聲 100 的低一級招呼，新角色也碰得到")

# ---------------------------------------------------------------- 依結局換話
func test_story_review_talk_by_quest_outcome() -> void:
	if not game_ok() or host().get("ambient") == null:
		return
	make_char()
	set_shichen(5)
	var a = host().ambient
	assert_eq(a.talk_key(s(), "n_xx_yuner"), "talk_n_xx_yuner", "還沒做：嘆氣")
	ch().quests["done"]["q_yuner"] = { "n": 1, "outcome": "abao", "world_s": 0.0, "failed": 0 }
	assert_eq(a.talk_key(s(), "n_xx_yuner"), "talk_n_xx_yuner@q_abao")
	assert_eq(a.talk_key(s(), "n_xx_abao"), "talk_n_xx_abao@q_abao")
	assert_eq(a.talk_key(s(), "n_xx_litaian"), "talk_n_xx_litaian@q_abao")
	set_shichen(11)
	assert_eq(a.talk_key(s(), "n_xx_yuner"), "talk_n_xx_yuner@q_abao_night", "夜裡的版本")
	ch().quests["done"]["q_yuner"]["outcome"] = "li"
	assert_eq(a.talk_key(s(), "n_xx_litaian"), "talk_n_xx_litaian@q_li_night")
	# 環境句：雲兒嫁了之後，民房夜裡不再嘆氣、阿寶不再喊找不到礦坑
	goto("xx_minfang")
	for r in a.candidates(s()):
		assert_true(str(r.get("id", "")) != "amb_ev_yuner_minfang_night", "做完雲兒就沒有嘆氣的環境句")

# ---------------------------------------------------------------- 預告
func test_story_review_foreshadow_only_takeable() -> void:
	if not game_ok() or host().get("rumor") == null:
		return
	make_char()   # 沒有門派的新角色
	var rs = host().rumor
	var seen := {}
	for i in 40:
		rs.flush()
		rs.maybe_foreshadow({ "day": 1000 + i, "shichen_name": "午" })
	for e in ws.world.get("rumors", []):
		if str(e.get("kind", "")) == "FORESHADOW":
			seen[str(e.get("text_key", ""))] = true
	assert_false(seen.is_empty(), "有預告")
	for row in tables()["rumors"].values():
		if str(row.get("kind", "")) != "FORESHADOW" or not seen.has(str(row.get("text", ""))):
			continue
		var q := str(row.get("quest", ""))
		assert_eq(host().quests.can_accept(s(), q), "", "預告的任務 %s 這位玩家接得了" % q)

# ---------------------------------------------------------------- 新手與夜遊惡人
func test_story_review_newbie_taunt_no_fight() -> void:
	if not game_ok() or host().get("wander") == null:
		return
	make_char()
	ch().combat_xp = 0
	goto("xw_grass")   # 野外、不是安全房間（teleport 不踩地雷）
	set_shichen(10)
	host().wander.tick(0.1)
	host().wander.state("w_nanhai").erase("cd_newbie")   # 入夜時惡人可能剛好遊到荒草坡（已經威嚇過）：重來
	clear_events()
	assert_true(host().wander.place("w_nanhai", "xw_grass"), "惡人走進玩家所在的房間")
	ws.advance(0.2)
	ws.flush()
	assert_eq(evs("villain_prompt").size(), 0, "新手不會被出手")
	assert_eq(s().battle_id, 0)
	assert_eq(evs("wander_newbie_w_nanhai").size(), 1, "但有一段威嚇")
	clear_events()
	assert_true(host().wander.place("w_nanhai", "xw_grass"))
	ws.advance(0.2)
	ws.flush()
	assert_eq(evs("wander_newbie_w_nanhai").size(), 0, "同一個惡人一天只威嚇一次")
	# 過了新手保護線就是一般的警告
	ch().combat_xp = 600
	host().wander.clear_cooldown("w_nanhai", str(ch().id))
	for i in 20:
		if not evs("villain_prompt").is_empty():
			break
		assert_true(host().wander.place("w_nanhai", "xw_grass"))
		ws.advance(0.05)
		ws.flush()
	assert_false(evs("villain_prompt").is_empty(), "實戰 600：照常警告")

# ---------------------------------------------------------------- 隨機任務變數
func test_story_review_random_var() -> void:
	if not game_ok():
		return
	make_char()
	var seen := {}
	for i in 30:
		assert_true(host().quests.debug_stage(s(), "q_sl_riyuebian", "s_fetch").get("ok", false))
		host().quests._run_actions(s(), "q_sl_riyuebian", "", [{ "do": "var", "name": "sutra", "random": ["jingang", "lengyan", "yaoshi"] }])
		seen[str(ch().quests["active"]["q_sl_riyuebian"]["vars"].get("sutra", ""))] = true
		host().quests.debug_reset(s(), "q_sl_riyuebian")
	assert_eq(seen.size(), 3, "三部經都抽得到：%s" % str(seen.keys()))
	assert_false(tables()["quests"]["q_sl_riyuebian"].get("requires", []).any(
		func(c): return str(c.get("flag", "")) == "sl_tongren_passed"), "日月鞭法沒有銅人陣門檻")

# ---------------------------------------------------------------- 第一位完成的傳聞帶結局
func test_story_review_first_rumor_has_outcome() -> void:
	if not game_ok() or host().get("rumor") == null:
		return
	make_char()
	assert_true(host().quests.debug_stage(s(), "q_yuner", "s_choose").get("ok", false))
	host().quests._finish(s(), "q_yuner", "li")
	host().rumor.poll()
	var hit := {}
	for e in ws.world.get("rumors", []):
		if str(e.get("text_key", "")) == "rmr_q_yuner_first":
			hit = e
	assert_false(hit.is_empty(), "first rumor posted")
	assert_eq(str(hit.get("params", {}).get("outcome_label", "")), "雲兒嫁給了李台安")

# ---------------------------------------------------------------- lint：結局要標 src
func test_story_review_lint_outcome_src() -> void:
	var lint = load("res://tools/data_lint.gd")
	var view := { "quests": {
		"q_t": { "id": "q_t", "stages": [{ "id": "s1" }], "outcomes": {
			"a": { "label": "x", "rewards": { "fame": 1 } },
			"b": { "label": "y", "rewards": { "fame": 1, "morality": -1 }, "src": "verified", "field_src": { "morality": "later" } },
			"c": { "label": "z", "rewards": { "fame": 1 }, "src": "verified", "field_src": { "lilian": "maybe" } } } } } }
	var errs: PackedStringArray = lint._s_outcome_src(view)
	var text := "\n".join(errs)
	assert_true(text.contains("outcomes.a: src must be"), "沒標 src 的結局：%s" % text)
	assert_false(text.contains("outcomes.b"), "標好的結局沒有錯誤：%s" % text)
	assert_true(text.contains("outcomes.c: field_src key 'lilian' not in rewards"), text)
	assert_true(text.contains("outcomes.c: field_src.lilian must be one of"), text)
	assert_eq(lint._s_outcome_src({ "quests": tables()["quests"] }).size(), 0, "現有資料全部標好了")
