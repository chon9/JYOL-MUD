extends "res://tests/unit/test_world_fixture.gd"
## M3d WP-ARTS 整合測試的共用基底（本檔沒有 test_ 方法，執行器只會載入它）。
## 真的 res://data、真的 GameHost（ArtsSystem 由 WP-LAW 的 M3D_SYSTEMS 載入），intent 走完整路徑。
## 其他 WP 平行開發（M3D_PLAN §0.1 #5）：WP-ERRANDS 才加的既有 NPC 任務陣列（§9.6）在這裡用 ensure_giver 補進生效表
## （after_each 的 _restore_rules 會重建，不會留下來）。

func before_each() -> void:
	world_name = "w_m3d_arts"
	super.before_each()

func arts():
	return host().get("arts") if host() != null else null

## 建角、入派（不經拜師流程；同 test_m3c2_spar）、變強；回傳角色（失敗 null）
func join_char(sect_id: String, char_name := "武功鏈俠", gender := "M", city := "xixia"):
	if not game_ok():
		return null
	if make_char(char_name, city, { "wit": 5 }, gender) == null:
		return null
	ws.options["sect_hostile_entry"] = false
	if sect_id != "":
		ch().sect = sect_id
		host().sects.on_join(s(), sect_id, str(tables()["sects"][sect_id].get("head_npc", "")))
	make_strong()
	ch().combat_xp = 1000000
	ch().learn_points = 5000
	Survival.rest_full(ch(), tables(), ws.options)
	clear_events()
	return ch()

func set_skills(d: Dictionary) -> void:
	for k in d:
		ch().skills.set_level(str(k), int(d[k]), tables())
	s().sheet_dirty = true

func lv(skill: String) -> int:
	return int(ch().skills.level(skill))

## WP-ERRANDS 才會寫進既有 NPC 的 quests 陣列（M3D_PLAN §9.6）：還沒合併時在生效表裡補上
func ensure_giver(npc_id: String, qid: String) -> void:
	var row: Dictionary = tables()["npcs"].get(npc_id, {})
	if row.is_empty():
		return
	var qs: Array = (row.get("quests", []) as Array).duplicate()
	if not qs.has(qid):
		qs.append(qid)
	row["quests"] = qs
	var sv: Array = (row.get("services", []) as Array).duplicate()
	if not sv.has("QUEST"):
		sv.append("QUEST")
	row["services"] = sv

func qstage(qid: String) -> String:
	return str(ch().quests["active"].get(qid, {}).get("stage", ""))

func qdone(qid: String) -> Dictionary:
	return ch().quests["done"].get(qid, {})

## quest_talk：開 offer／目前階段的對話（沒有對話的 TALK／DELIVER 直接完成）
func qtalk(npc: String, qid: String) -> Dictionary:
	return send("quest_talk", { "npc": npc, "quest": qid })

## 在目前開著的對話節點選 choice
func pick(npc: String, qid: String, choice: String) -> Dictionary:
	var d := lastp("dialogue")
	return send("dialogue_choose", { "npc": npc, "quest": qid, "node": str(d.get("node", "")), "choice": choice })

## STATE 目標（QuestSystem.on_sheet 每真實秒一次）：立刻檢查一次
func state_check() -> void:
	s().quest_state_check_ms = -100000
	s().sheet_dirty = true
	host().quests.on_sheet(s())
	ws.flush()

## 打贏目前的戰鬥（多波：每波都清光，直到戰鬥結束）
func win_battle(peer := 1) -> void:
	var sess: Session = ws.sessions.get(peer)
	for i in 20:
		if sess.battle_id == 0:
			return
		var entry: Dictionary = host().battles.active.get(sess.battle_id, {})
		if entry.is_empty():
			return
		var b: Battle = entry["battle"]
		var me: BattleUnit = null
		for u in b.units:
			if int(u.peer) == peer:
				me = u
		for u in b.units:
			if me != null and u.side != me.side and u.is_active():
				BattleRules.kill(b, u, me)
		b._check_end(tables())
		ws.advance(0.2)

## 打輸目前的戰鬥
func lose_battle(peer := 1) -> void:
	var sess: Session = ws.sessions.get(peer)
	var entry: Dictionary = host().battles.active.get(sess.battle_id, {})
	if entry.is_empty():
		return
	var b: Battle = entry["battle"]
	var me: BattleUnit = null
	var foe: BattleUnit = null
	for u in b.units:
		if int(u.peer) == peer:
			me = u
		elif u.is_active():
			foe = u
	BattleRules.kill(b, me, foe)
	b._check_end(tables())
	for i in 50:
		if sess.battle_id == 0:
			return
		ws.advance(0.1)

func assert_near(actual: float, expected: float, eps := 0.0001, msg := "") -> bool:
	return assert_true(absf(actual - expected) <= eps, "%s expected ≈%s got %s" % [msg, str(expected), str(actual)])
