extends "res://tests/unit/test_world_fixture.gd"
## M3b 審查 3（伺服器端）：
## - 鏢車走散後，介面送的 quest_turn_in 也能重新領車；選單項標 resume（介面顯示「重領鏢車」而不是「交鏢」）
## - 押進監獄／出獄瞬移 → 護送對象走散；護送中不能讓人引路（同驛站馬車）
## - 取貨：先寫 world.json 再寫角色檔（磁碟上的 world.json 已經沒有那筆貨）
## - 寄件人刪除後，退回的托鏢會被清掉
## - 組織名不能用門派名、天地會
## - 絕情丹 keep_on_use：解毒不消耗（戰鬥外、戰鬥中）

const Q := "q_ec_biao_xx_dl"
const GIVER := "n_ec_xx_biaotou"
const CART := "n_ec_biaoche"

func before_each() -> void:
	world_name = "w_m3b_review3"
	super.before_each()

func _accept_escort() -> bool:
	if not game_ok() or GameData.tables.get("quests", {}).get(Q, {}).is_empty():
		return false
	if make_char("審查俠") == null:
		return false
	goto("xx_biaoju")
	var r := send("quest_talk", { "npc": GIVER, "quest": Q })
	assert_true(r.get("ok", false), "接保鏢：%s" % str(r))
	return host().quests.is_escorting(ch(), CART)

func _menu_entry(npc_id: String, qid: String) -> Dictionary:
	for e in host().quests.menu_entries(s(), npc_id):
		if str(e.get("id", "")) == qid:
			return e
	return {}

func test_lost_cart_turn_in_resumes() -> void:
	if not _accept_escort():
		return
	assert_false(_menu_entry(GIVER, Q).has("resume"), "帶著車時沒有 resume")
	host().quests.on_battle_settled(s(), { "died": true, "per": "DEFEAT", "result": "DEFEAT" })
	ws.flush()
	assert_false(host().quests.is_escorting(ch(), CART), "倒下 → 走散")
	var e := _menu_entry(GIVER, Q)
	assert_eq(str(e.get("state", "")), "READY")
	assert_eq(e.get("resume", false), true, "選單標 resume → 介面顯示重領鏢車")
	# 介面（鏢局保鏢頁、NPC 任務頁）以前送 quest_turn_in → quest_incomplete
	var r := send("quest_turn_in", { "npc": GIVER, "quest": Q })
	assert_true(r.get("ok", false), "quest_turn_in 也能重新領車：%s" % str(r))
	assert_true(host().quests.is_escorting(ch(), CART), "重新交給你")
	assert_false(last("quest_escort_resumed").is_empty())

func test_jail_drops_escort() -> void:
	if not _accept_escort():
		return
	var sects = host().sects
	var sid := "shaolin"
	if sects.jail_room_for(sid, "BREACH") == "":
		return
	assert_true(sects._jail_char(ch(), sid, 1, "BREACH", ""), "押人")
	clear_events()
	sects.enforce_jail(s())
	ws.flush()
	assert_true(ch().is_jailed())
	assert_false(host().quests.is_escorting(ch(), CART), "押進監獄 → 鏢車走散")
	assert_false(last("fail_escort_lost").is_empty(), "通知走散")
	# 出獄（衙門旁）也不會帶著車；任務還在、可以回鏢頭重新領
	sects.release(s(), "admin")
	ws.flush()
	assert_false(ch().is_jailed())
	assert_false(host().quests.is_escorting(ch(), CART))
	assert_true(QuestState.is_active(ch().quests, Q), "任務沒有失敗")

func test_guide_refused_while_escorting() -> void:
	if not _accept_escort():
		return
	if GameData.tables.get("npcs", {}).get("n_gm_sunpopo", {}).is_empty():
		return
	goto("gm_entrance")
	ch().gender = "F"
	var before := s().room_id()
	assert_eq(reason("npc_guide", { "npc": "n_gm_sunpopo" }), "escorting", "護送中不能讓人引路")
	assert_eq(s().room_id(), before)
	assert_true(host().quests.is_escorting(ch(), CART), "鏢車還在")

func test_reserved_org_names() -> void:
	if not game_ok():
		return
	var orgs = host().get("orgs")
	if orgs == null:
		return
	for n in ["丐幫", "少林", "少林派", "天地會"]:
		assert_true(orgs.reserved_name(n), "保留名稱 %s" % n)
		assert_true(orgs.name_taken(n), "name_taken %s" % n)
	assert_false(orgs.reserved_name("江湖小築"))
	assert_false(orgs.name_taken("江湖小築"))

func test_juequingdan_kept_on_cure() -> void:
	if not game_ok() or GameData.tables.get("items", {}).get("c_jq_juequingdan", {}).is_empty():
		return
	if make_char("情花客") == null:
		return
	var uid := give("c_jq_juequingdan", 1)
	ch().add_condition("qinghua", 1, 12, ch().online_s + 120.0)
	assert_eq(ch().condition_level("qinghua"), 1, "中了情花毒")
	var r := send("use_item", { "item_uid": uid })
	assert_true(r.get("ok", false), "用絕情丹：%s" % str(r))
	assert_eq(item_count("c_jq_juequingdan"), 1, "keep_on_use：用了還在")
	assert_eq(ch().condition_level("qinghua"), 0, "情花毒解了")
	# 戰鬥中：battle_items 帶 keep_on_use，用了不算進 used_items
	var bi: Array = ch().battle_items(GameData.tables)
	var spec: Dictionary = {}
	for it in bi:
		if str(it.get("item_id", "")) == "c_jq_juequingdan":
			spec = it
	assert_eq(spec.get("keep_on_use", false), true, "戰鬥用的物品帶 keep_on_use")
	# 一般的藥照舊會扣
	var u2 := give("c_jieduyao", 1) if not GameData.tables.get("items", {}).get("c_jieduyao", {}).is_empty() else ""
	if u2 != "":
		var n0 := item_count("c_jieduyao")
		send("use_item", { "item_uid": u2 })
		assert_eq(item_count("c_jieduyao"), n0 - 1, "解毒藥照舊會用掉")
