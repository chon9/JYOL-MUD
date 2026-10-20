extends "res://tests/unit/test_world_fixture.gd"
## M3b 審查：保鏢工作（q_ec_biao_*）。護送中倒下走散 → 回給任務的鏢頭再談一次重新領鏢車；護送途中不能搭驛站馬車。

const Q := "q_ec_biao_xx_dl"
const GIVER := "n_ec_xx_biaotou"
const CART := "n_ec_biaoche"

func before_each() -> void:
	world_name = "w_m3b_escort_job"
	super.before_each()

func _accept() -> bool:
	if not game_ok() or GameData.tables.get("quests", {}).get(Q, {}).is_empty():
		return false
	if make_char("保鏢俠") == null:
		return false
	goto("xx_biaoju")
	var r := send("quest_talk", { "npc": GIVER, "quest": Q })
	assert_true(r.get("ok", false), "接保鏢：%s" % str(r))
	return host().quests.is_escorting(ch(), CART)

func test_lost_cart_can_be_picked_up_again() -> void:
	if not _accept():
		return
	assert_true(host().quests.is_escorting(ch(), CART), "接了就帶著鏢車")
	# 護送中戰死 → 走散
	host().quests.on_battle_settled(s(), { "died": true, "per": "DEFEAT", "result": "DEFEAT" })
	ws.flush()
	assert_false(host().quests.is_escorting(ch(), CART), "倒下 → 鏢車走散")
	var menu: Array = host().quests.menu_entries(s(), GIVER)
	var st := ""
	for e in menu:
		if str(e.get("id", "")) == Q:
			st = str(e.get("state", ""))
	assert_eq(st, "READY", "鏢頭選單標成可以談（重新領車）")
	var r := send("quest_talk", { "npc": GIVER, "quest": Q })
	assert_true(r.get("ok", false), "再談一次：%s" % str(r))
	assert_true(host().quests.is_escorting(ch(), CART), "重新交給你")
	assert_false(last("quest_escort_resumed").is_empty(), "quest_escort_resumed")
	# 已經帶著車：再談不會重複觸發
	assert_eq(host().quests._escort_restartable(ch(), Q, GIVER), "")
	# 送到就完成
	goto("dl_biaoju")
	host().quests.on_reach(s())
	ws.flush()
	assert_false(QuestState.is_active(ch().quests, Q), "送達完成")

func test_no_coach_while_escorting() -> void:
	if not _accept():
		return
	ws.options["stagecoach_enabled"] = true
	goto("xx_station")
	var m0: int = ch().money
	assert_eq(reason("travel", { "npc": "n_xx_station", "dest": "dl_station" }), "escorting", "護送中不能搭車")
	assert_eq(s().room_id(), "xx_station")
	assert_eq(ch().money, m0, "沒扣錢")
	# 放棄保鏢之後就能搭
	ch().money = maxi(ch().money, 1000)
	assert_true(send("quest_abandon", { "quest": Q }).get("ok", false))
	assert_true(send("travel", { "npc": "n_xx_station", "dest": "dl_station" }).get("ok", false), "沒在護送 → 可以搭")
