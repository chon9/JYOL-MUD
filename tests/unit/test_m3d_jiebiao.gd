extends "res://tests/unit/test_world_fixture.gd"
## M3D_PLAN §5.2.1、§10.1（WP-EVENTS）：危險鏢。條件（實戰／名聲／歷練、丐幫不行）、押金、送達 2 倍、冷卻、
## 失敗五種（逃走、死亡、被劫〔test_m3d_rob〕、登出、放棄）、主機關閉不算失敗、特殊地雷、「押鏢」標籤、1.0A 看不到。

const Q := "q_ev_jb_xx_dl_huo"
const GIVER := "n_ev_jb_xx"
const CART := "n_ev_jb_cart"
const VALUE := 3200

func before_each() -> void:
	world_name = "w_m3d_jiebiao"
	super.before_each()

func _ready_char(char_name := "押鏢俠") -> bool:
	if not game_ok() or GameData.tables.get("quests", {}).get(Q, {}).is_empty():
		fail("危險鏢資料不在（1.0B 視圖）")
		return false
	if host().get("jiebiao") == null:
		fail("JiebiaoSystem 沒有載入")
		return false
	if make_char(char_name) == null:
		return false
	make_strong()
	var c = ch()
	c.combat_xp = 100000
	c.fame = 100
	c.lilian = 100
	c.money = 20000
	return true

func _accept() -> Dictionary:
	goto("xx_biaoju")
	return send("quest_accept", { "npc": GIVER, "quest": Q })

func _active() -> Dictionary:
	return JiebiaoSystem.active_of(ch())

func test_requires_and_gaibang() -> void:
	if not _ready_char():
		return
	ch().combat_xp = 99999
	goto("xx_biaoju")
	assert_eq(reason("quest_accept", { "npc": GIVER, "quest": Q }), "req_combat_xp_min", "實戰不到 10 萬")
	ch().combat_xp = 100000
	ch().fame = 99
	assert_eq(reason("quest_accept", { "npc": GIVER, "quest": Q }), "req_fame_min", "名聲不到 100")
	ch().fame = 100
	ch().lilian = 50
	assert_eq(reason("quest_accept", { "npc": GIVER, "quest": Q }), "req_lilian_min", "歷練不到 100")
	ch().lilian = 100
	ch().sect = "gaibang"
	assert_eq(reason("quest_accept", { "npc": GIVER, "quest": Q }), "req_sect_not", "丐幫不能運鏢")
	assert_eq(JiebiaoRules.accept_reason(200000, 500, 500, "gaibang"), "req_sect_not")
	assert_eq(int(ch().money), 20000, "沒接成不扣錢")

func test_deposit_success_double_and_cooldown() -> void:
	if not _ready_char():
		return
	var r := _accept()
	assert_true(r.get("ok", false), "接危險鏢：%s" % str(r))
	assert_eq(int(ch().money), 20000 - VALUE, "扣押金＝鏢價")
	var a := _active()
	assert_eq(str(a.get("quest", "")), Q)
	assert_eq(int(a.get("value", 0)), VALUE)
	assert_true(host().quests.is_escorting(ch(), CART), "鏢車跟著走")
	assert_false(last("ev_jb_started").is_empty(), "ev_jb_started")
	assert_true(Requirements.check([{ "type": "jb_active" }], ch(), tables(), ws.options, host().rules, {}) == "", "jb_active 成立")
	assert_false(Requirements.check([{ "type": "jb_active", "value": false }], ch(), tables(), ws.options, host().rules, {}) == "",
		"jb_active value:false 不成立")
	# 押鏢標籤（別人看）
	var tags: Dictionary = host().jiebiao.player_tags(s(), s())
	assert_has(tags.get("tags", []), "押鏢", "頭上標「押鏢」")
	# 同時只能一趟
	assert_eq(reason("quest_accept", { "npc": GIVER, "quest": "q_ev_jb_xx_dl_hu" }), "jb_active", "已經有一趟危險鏢")
	var fame0 := int(ch().fame)
	goto("dl_biaoju")
	host().quests.on_reach(s())
	host().jiebiao.reconcile(s())
	ws.flush()
	assert_false(QuestState.is_active(ch().quests, Q), "送達完成")
	assert_true(_active().is_empty(), "active 清掉")
	assert_eq(int(ch().money), 20000 + VALUE, "還押金＋鏢價（合計 2 × 鏢價）→ 淨 +鏢價")
	assert_eq(int(ch().fame), fame0 + 3, "名聲 +3")
	assert_false(last("ev_jb_done").is_empty(), "ev_jb_done")
	var cd: float = float(JiebiaoSystem.data_of(ch())["cd"].get(GIVER, 0.0))
	var left: float = cd - float(host().now_s())
	assert_true(left > 1700.0 and left <= 7200.0 + 1.0, "不接鏢冷卻 30／60／120 分：%f" % left)
	assert_true([1800.0, 3600.0, 7200.0].any(func(x): return absf(left - x) < 2.0), "冷卻是三選一：%f" % left)
	goto("xx_biaoju")
	assert_eq(reason("quest_accept", { "npc": GIVER, "quest": Q }), "jb_cooldown", "冷卻中：目前沒有鏢可供承接")
	# 另一位二掌櫃不受影響
	goto("dl_biaoju")
	assert_true(send("quest_accept", { "npc": "n_ev_jb_dl", "quest": "q_ev_jb_dl_xx_hu" }).get("ok", false), "別的二掌櫃照接")

func test_no_deposit() -> void:
	if not _ready_char():
		return
	ch().money = VALUE - 1
	assert_eq(str(_accept().get("reason", "")), "jb_no_deposit", "押金不夠")
	assert_false(QuestState.is_active(ch().quests, Q), "任務不成立")
	assert_eq(int(ch().money), VALUE - 1)

func test_fail_on_flee_and_death() -> void:
	if not _ready_char():
		return
	assert_true(_accept().get("ok", false))
	host().jiebiao.on_battle_settled(s(), ch(), { "kind": "ENCOUNTER", "per": "FLED", "died": false })
	ws.flush()
	assert_true(_active().is_empty(), "逃走 → 失敗")
	assert_false(QuestState.is_active(ch().quests, Q), "任務 fail")
	assert_eq(int(ch().money), 20000 - VALUE, "押金沒收")
	assert_eq(str(lastp("ev_jb_failed").get("why", "")), "fled")
	# 死亡（冷卻沒設：失敗不設不接鏢冷卻）
	goto("xx_biaoju")
	assert_true(send("quest_accept", { "npc": GIVER, "quest": Q }).get("ok", false), "失敗後可以再接")
	host().jiebiao.on_battle_settled(s(), ch(), { "kind": "ENCOUNTER", "per": "DEFEAT", "died": true })
	ws.flush()
	assert_true(_active().is_empty(), "死亡 → 失敗")
	assert_eq(str(lastp("ev_jb_failed").get("why", "")), "died")
	assert_eq(int(ch().money), 20000 - 2 * VALUE)
	# 比武（DUEL）的逃走不算
	assert_true(send("quest_accept", { "npc": GIVER, "quest": Q }).get("ok", false))
	host().jiebiao.on_battle_settled(s(), ch(), { "kind": "DUEL", "per": "FLED", "died": false })
	assert_false(_active().is_empty(), "比武棄權不算押鏢失敗")

func test_real_battle_flee_fails() -> void:
	if not _ready_char():
		return
	assert_true(_accept().get("ok", false))
	start_battle(["m_rabbit"])
	drive_battle("flee", 300.0)
	ws.flush()
	if str(cs.last_battle_result.get("result", "")) == "FLED":
		assert_true(_active().is_empty(), "真的戰鬥裡逃走 → 失敗")
		assert_false(QuestState.is_active(ch().quests, Q))
	else:
		assert_false(_active().is_empty(), "沒逃成（打完了）→ 鏢照走")

func test_fail_on_abandon_and_logout() -> void:
	if not _ready_char():
		return
	assert_true(_accept().get("ok", false))
	assert_true(send("quest_abandon", { "quest": Q }).get("ok", false))
	assert_true(_active().is_empty(), "放棄 → 失敗")
	assert_eq(str(lastp("ev_jb_failed").get("why", "")), "abandon")
	assert_eq(int(ch().money), 20000 - VALUE, "押金沒收")
	goto("xx_biaoju")
	assert_true(send("quest_accept", { "npc": GIVER, "quest": Q }).get("ok", false))
	host().jiebiao.on_logout(s())
	assert_true(_active().is_empty(), "登出 → 失敗")
	assert_false(QuestState.is_active(ch().quests, Q))

func test_shutdown_keeps_escort() -> void:
	if not _ready_char():
		return
	assert_true(_accept().get("ok", false))
	var cid := str(ch().id)
	host().shutdown()
	restart_world()
	if not game_ok():
		return
	assert_true(send("char_select", { "char_id": cid }).get("ok", false), "選回角色")
	ws.flush()
	assert_false(_active().is_empty(), "主機關閉不算失敗：登入時繼續")
	assert_true(QuestState.is_active(ch().quests, Q))
	assert_eq(int(ch().money), 20000 - VALUE)

func test_special_landmine() -> void:
	if not _ready_char():
		return
	assert_true(_accept().get("ok", false))
	# 純規則：每 3 間最多一次
	assert_false(JiebiaoRules.mine_hits(1, 0), "遇過之後第 1 間不擲")
	assert_false(JiebiaoRules.mine_hits(2, 0), "第 2 間不擲")
	assert_true(JiebiaoRules.mine_hits(3, 14), "第 3 間 15%")
	assert_false(JiebiaoRules.mine_hits(3, 15))
	for v in [0.0, 0.3, 0.5, 0.99]:
		var n: int = JiebiaoRules.bandit_count(v)
		assert_true(n >= 2 and n <= 4, "劫匪 2–4 個")
	# 整合：來回走野外房間直到遇上（15%，100 次沒遇上的機率 < 1e-6）
	var hit := false
	for i in 100:
		goto("xw_road" if i % 2 == 0 else "xw_grass")
		if s().battle_id != 0:
			hit = true
			break
	assert_true(hit, "押鏢中走野外會遇上特殊地雷")
	if not hit:
		return
	assert_eq(int(_active().get("rooms_since", -1)), 0, "遇上後計數歸 0")
	var b = host().battles.active[s().battle_id]["battle"]
	var bandits := 0
	for u in b.units:
		if u.side == 1:
			assert_eq(str(u.spec.get("monster_row", u.spec.get("ref", ""))).begins_with("m_ev_jb_bandit") \
				or str(u.spec.get("ref", "")).begins_with("m_ev_jb_bandit"), true, "劫匪")
			bandits += 1
	assert_true(bandits >= 2 and bandits <= 4, "2–4 個劫匪：%d" % bandits)
	assert_false(last("ev_jb_ambush").is_empty(), "ev_jb_ambush")
	drive_battle("fight", 900.0)
	if str(cs.last_battle_result.get("result", "")) == "VICTORY":
		assert_false(_active().is_empty(), "打退劫匪 → 鏢照走")

func test_city_rooms_have_no_mines() -> void:
	if not _ready_char():
		return
	assert_true(_accept().get("ok", false))
	for i in 40:
		goto("xx_square" if i % 2 == 0 else "xx_biaoju")
		assert_eq(s().battle_id, 0, "城裡不會遇上")

func test_era_1_0a_hides_danger_escort() -> void:
	if not game_ok():
		return
	use_eras(["1.0A"])
	assert_false(GameData.tables.get("npcs", {}).has(GIVER), "1.0A-only 沒有二掌櫃")
	assert_false(GameData.tables.get("quests", {}).has(Q), "1.0A-only 沒有危險鏢")
	if make_char("一點零甲") == null:
		return
	goto("xx_biaoju")
	assert_eq(reason("quest_accept", { "npc": GIVER, "quest": Q }), "not_here")
	assert_eq(reason("rob_escort", { "target_char": "nobody" }), "era_locked", "1.0A 劫鏢 era_locked")

func test_sheet_fields() -> void:
	if not _ready_char():
		return
	assert_true(_accept().get("ok", false))
	var f: Dictionary = host().jiebiao.sheet_fields(s())
	assert_eq(int(f["jiebiao"]["active"].get("value", 0)), VALUE)
	assert_eq(str(f["jiebiao"]["active"].get("kind_name", "")), "送貨鏢")
	ws.flush()
	if sheet().has("jiebiao"):
		assert_eq(int(sheet()["jiebiao"]["active"].get("value", 0)), VALUE, "角色表帶出押鏢中")
