extends "res://tests/unit/test_world_fixture.gd"
## 故事包整合修正（整合者）：碎片的寫法與引擎的接縫。方法名 test_story_*（--filter=story 可單跑）。
## - FIGHT 目標帶 npc＋dialogue（q_xingxia 的強盜、q_hs_spy 的勞德諾）：交談直接開那段對話，選項裡的 fight 開打；
##   逃走後再交談又能開（重打）；打贏後這個 NPC 不再有任務入口。

func before_each() -> void:
	world_name = "w_story_integ"
	super.before_each()

func test_story_fight_objective_with_dialogue_opens_on_talk() -> void:
	if not game_ok():
		return
	make_char()
	make_strong()
	assert_true(host().quests.debug_stage(s(), "q_xingxia", "s_bandit").get("ok", false), "debug_stage s_bandit")
	goto("ym_bridge")
	var entries: Array = host().quests.menu_entries(s(), "n_ym_qiangdao")
	var states := entries.map(func(e): return str(e.get("state", "")))
	assert_true("READY" in states, "強盜的選單有 q_xingxia 的入口：%s" % str(entries))
	clear_events()
	ok("talk", { "npc": "n_ym_qiangdao" })
	var d := lastp("dialogue")
	assert_eq(str(d.get("quest", "")), "q_xingxia", "交談直接開 FIGHT 目標的對話：%s" % str(d))
	assert_eq(str(d.get("dlg", "")), "d_qiangdao")
	ok("dialogue_close")
	# 打贏 → 下一階段，強盜不再有任務入口
	host().quests.on_battle_settled(s(), { "per": "VICTORY",
		"quest_tag": { "quest": "q_xingxia", "obj": "o_fight", "by": str(ch().id), "solo": false, "members": [] } })
	assert_eq(str(ch().quests["active"]["q_xingxia"]["stage"]), "s_return")
	assert_true(host().quests.menu_entries(s(), "n_ym_qiangdao").is_empty(), "打贏後強盜沒有任務入口")
