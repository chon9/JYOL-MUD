extends "res://tests/unit/test_pk_world_base.gd"
## M3d 驗收劇本（M3D_PLAN §10.3）。由 tools/m3d_acceptance.gd 的 worker 建立（不是單元測試：檔名不以 test_ 開頭，
## 執行器不會撿到）。沿用整合測試的世界夾具（真的 WorldServer＋GameHost、全部系統、--debug-intents 的 intent 路徑、
## 本機 peer 1＋假的遠端 peer）：每個劇本一個全新世界（測試根目錄下 test_tmp/），結束時 after_each 收掉。
## 測試捷徑（不是受測物，同 M3b／M3c／M3c2 驗收）：直接設技能、實戰、銀兩、時辰；入派用 SectSystem.on_join；
## 「打贏／打輸」用 BattleRules.kill 直接結束（勝負不是受測物，結算才是）；兩個以上角色的劇本用遠端 peer。
## 每個劇本回傳一行摘要（info）；失敗以 failures 陣列回報（assert_*）。

const H := preload("res://tests/unit/test_battle_helpers.gd")
const A := preload("res://tests/unit/test_m3c_npc_attack.gd")

var info := ""

func law():
	return host().get("law")

func note(s: String) -> void:
	info += ("；" if info != "" else "") + s

# ======================================================================== 共用
func _pick(npc: String, qid: String, node: String, choice: String) -> void:
	ok("dialogue_choose", { "npc": npc, "quest": qid, "node": node, "choice": choice })

func _pick_p(peer: int, npc: String, qid: String, node: String, choice: String) -> void:
	ok_p(peer, "dialogue_choose", { "npc": npc, "quest": qid, "node": node, "choice": choice })

func _to_day_start() -> void:
	var day: float = host().day_s()
	ws.world["world_time_s"] = (floorf(ws.world_time() / day) + 1.0) * day + 1.0
	ws.advance(0.1)

func _local(char_name: String, city := "xixia", gender := "M") -> bool:
	if not game_ok():
		return false
	if make_char(char_name, city, { "wit": 5 }, gender) == null:
		return false
	ws.options["encounters_enabled"] = false
	Survival.rest_full(ch(), tables(), ws.options)
	clear_events()
	return true

func _villain(peer: int, pk: int, mo := 0, xp := 5000) -> void:
	var c = chr(peer)
	c.combat_xp = maxi(int(c.combat_xp), xp)
	c.pk = pk
	c.pk_stamp_s = c.online_s
	c.morality = mo

## 遠端女角（add_player 只建男角）
func _add_female(char_name: String, city := "xixia") -> int:
	var peer := connect_player(char_name)
	assert_true(send_as(peer, "char_roll").get("ok", false), "char_roll")
	var r := send_as(peer, "char_create", { "name": char_name, "gender": "F", "birth_month": 3, "birth_city": city,
		"alloc": { "wit": 5 } })
	assert_true(r.get("ok", false), "char_create F %s: %s" % [char_name, str(r)])
	return peer

func _kill_now(peer: int, win := true) -> void:
	A.finish(self, peer, win)

## 依任務的 test_plan 路徑走（walk/accept/choose/talk/act/fight/set_var）；peer 1（本機）
func _run_path(qid: String, path: Array) -> bool:
	for st in path:
		var step := str(st)
		var before := failures.size()
		if step.begins_with("walk@"):
			goto(step.substr(5))
		elif step.begins_with("accept@"):
			ok("quest_accept", { "npc": step.substr(7), "quest": qid })
		elif step.begins_with("talk@"):
			ok("quest_talk", { "npc": step.substr(5), "quest": qid })
		elif step.begins_with("choose@"):
			var parts := step.substr(7).split(":")
			_pick(parts[0], qid, parts[1], parts[2])
		elif step.begins_with("act@"):
			ok("story_act", { "act": step.substr(4) })
		elif step.begins_with("fight:"):
			_kill_now(1, step.ends_with("WIN"))
		elif step.begins_with("set_var:"):
			var kv := step.substr(8).split(":")
			var nv := kv[1].split("=")
			var act: Dictionary = ch().quests["active"].get(kv[0], {})
			var vars: Dictionary = act.get_or_add("vars", {})
			vars[nv[0]] = int(nv[1])
		elif step.begins_with("expect_locked@"):
			# 同 tests/bots/story_bot.gd：最後一次送來的對話停在 <npc>:<node>，其中 <choice> 上鎖（或上鎖且隱藏 → 沒送出來）
			var lp := step.substr(14).split(":")
			var dlg: Dictionary = lastp("dialogue")
			if lp.size() != 3:
				fail("bad step " + step)
			elif str(dlg.get("npc", "")) != lp[0] or str(dlg.get("node", "")) != lp[1]:
				fail("expect_locked: dialogue is at %s:%s" % [str(dlg.get("npc", "")), str(dlg.get("node", ""))])
			else:
				for c in dlg.get("choices", []):
					if c is Dictionary and str(c.get("id", "")) == lp[2] and not bool(c.get("locked", false)):
						fail("expect_locked: %s is not locked" % lp[2])
		else:
			fail("unknown path step " + step)
		if failures.size() > before:
			fail("path step failed: " + step)
			return false
	return true

func _plan(qid: String, outcome := "default") -> Array:
	for p in tables()["quests"][qid].get("test_plan", []):
		if str(p.get("outcome", "")) == outcome:
			return p.get("path", [])
	return []

# ======================================================================== A 懸賞與律法
## A（實戰 3 萬）強制 PK 殺 4 人 → 下個時辰上榜 4000；B 找耳聾官爺 → license_deaf；另一位領照 → 合法緝拿 A：
## B 的 PK值 0、善惡不變；A 的 PK值 3、錢少 4000 → B 領賞 +4000；同一天再殺 → 沒有懸賞
func sc_bounty() -> void:
	if not deps_ok(true):
		return
	law().hunter_chance_pct = 0
	ws.options["encounters_enabled"] = false
	var a := add("惡甲")
	var b := add("獵人乙")
	make_strong_p(a)
	chr(a).combat_xp = 30000
	for i in 4:
		var v := add("路人%s" % ["子", "丑", "寅", "卯"][i])
		chr(v).combat_xp = 5000
		goto_p(a, "xw_road")
		goto_p(v, "xw_road")
		make_weak_p(v)
		Survival.rest_full(chr(a), tables(), ws.options)
		var r := ok_p(a, "force_pk", { "target": cid(v) })
		drive_bid(int(r.get("battle_id", 0)), { a: "fight", v: "defend" })
	assert_eq(int(chr(a).pk_value()), 4, "A 殺 4 人 → PK值 4")
	assert_false(law().is_listed(cid(a)), "統計時點前不在名單")
	set_shichen((int(host().clock()["shichen_idx"]) + 1) % 12)
	assert_true(law().is_listed(cid(a)), "下個時辰上榜")
	goto_p(b, "xx_square")
	ok_p(b, "bounty_board", { "npc": "n_law_board_xx" })
	var amt := 0
	for row in lastp_p(b, "bounty_board").get("rows", []):
		if str(row.get("name", "")) == "惡甲":
			amt = int(row.get("amount", 0))
	assert_eq(amt, 4000, "西夏佈告欄：惡甲 4000")
	chr(b).money = 1000
	assert_eq(reason_p(b, "bounty_license", { "npc": "n_law_guanye_xx_b" }), "license_deaf", "耳聾官爺聽錯")
	ok_p(b, "bounty_license", { "npc": "n_law_guanye_xx_a" })
	chr(a).money = 5000
	BankStore.bank_of(chr(a))["money"] = 0
	var mo_b := int(chr(b).morality)
	goto_p(b, "xw_road")
	goto_p(a, "xw_road")
	make_strong_p(b)
	make_weak_p(a)
	var r2 := ok_p(b, "force_pk", { "target": cid(a) })
	assert_true(law().is_lawful_bid(int(r2.get("battle_id", 0))), "持照緝拿＝合法")
	drive_bid(int(r2.get("battle_id", 0)), { b: "fight", a: "defend" })
	assert_eq(int(chr(b).pk_value()), 0, "B 的 PK值 0")
	assert_eq(int(chr(b).morality), mo_b, "B 的善惡不變")
	assert_eq(int(chr(a).pk_value()), 3, "A 的 PK值 3")
	assert_eq(int(chr(a).money), 1000, "A 的錢少了 4000")
	goto_p(b, "xx_square")
	var m0 := int(chr(b).money)
	ok_p(b, "bounty_claim", { "npc": "n_law_guanye_xx_a" })
	assert_eq(int(chr(b).money) - m0, 4000, "B 領賞 +4000")
	# M3d 審查：A 的 PK值 3 已不夠格 → 立刻下榜（不等下個時辰），不能再「合法」緝拿
	assert_false(law().is_listed(cid(a)), "A 立刻下榜")
	Survival.rest_full(chr(a), tables(), ws.options)
	goto_p(b, "xw_road")
	goto_p(a, "xw_road")
	assert_false(law().lawful_hunt(sess(b), chr(a)), "過期的名單不能再緝拿")
	note("PK 4 上榜 %d；耳聾 license_deaf；合法緝拿 B PK 0、A PK 3、罰 4000、領賞 +4000；A 立刻下榜" % amt)

## 同隊緝殺 → law_no_bounty_friend；C 加碼 5000 → D 緝殺得罰金＋5000
func sc_bounty_friends() -> void:
	if not deps_ok(true):
		return
	law().hunter_chance_pct = 0
	ws.options["encounters_enabled"] = false
	var a := add("惡甲")
	var b := add("同夥乙")
	var c := add("苦主丙")
	var d := add("獵人丁")
	_villain(a, 5)
	law().refresh_board()
	assert_true(law().is_listed(cid(a)), "A 在名單上")
	for p in [b, d]:
		goto_p(p, "xx_square")
		chr(p).money = 1000
		ok_p(p, "bounty_license", { "npc": "n_law_guanye_xx_a" })
	goto_p(a, "xw_road")
	goto_p(b, "xw_road")
	ok_p(b, "party_invite", { "target": cid(a) })
	ok_p(a, "party_reply", { "from": cid(b), "accept": true })
	ws.advance(0.2)
	assert_eq(law()._friend_reason(cid(b), cid(a), sess(b), sess(a)), "law_no_bounty_friend", "同隊 → law_no_bounty_friend")
	# 同隊無法對隊友強制 PK（M2 target_in_party）：緝殺結算直接呼叫一次（受測物是防刷判定）
	chr(a).money = 50000
	law()._caught(cid(b), cid(a), "xw_road")
	settle()
	assert_false(evs_p(b, "law_no_bounty_friend").is_empty(), "隊友緝殺 → law_no_bounty_friend")
	assert_eq(law().claims_total(cid(b)), 0, "隊友沒有懸賞")
	assert_eq(int(chr(a).pk_value()), 5, "隊友緝殺 → PK值 不減")
	ok_p(a, "party_leave")
	ws.advance(0.2)
	_villain(a, 5)
	law().refresh_board()
	goto_p(c, "xx_square")
	chr(c).money = 10000
	ok_p(c, "bounty_add", { "npc": "n_law_board_xx", "target_name": "惡甲", "money": 5000 })
	var fine := BountyRules.fine(int(chr(a).pk_value()), int(chr(a).morality))
	goto_p(d, "xw_road")
	goto_p(a, "xw_road")
	make_strong_p(d)
	make_weak_p(a)
	var r := ok_p(d, "force_pk", { "target": cid(a) })
	drive_bid(int(r.get("battle_id", 0)), { d: "fight", a: "defend" })
	assert_eq(law().claims_total(cid(d)), fine + 5000, "D 得罰金 %d ＋ 加碼 5000" % fine)
	assert_eq(int(chr(a).pk_value()), 4, "A PK 5 → 4（還在名單上）")
	# 同一天 D 再殺 A：不發賞金、PK值 也不再減（M3d 審查：朋友不能靠反覆緝拿洗 PK）
	Survival.rest_full(chr(a), tables(), ws.options)
	Survival.rest_full(chr(d), tables(), ws.options)
	make_weak_p(a)
	goto_p(d, "xw_road")
	goto_p(a, "xw_road")
	var r2 := ok_p(d, "force_pk", { "target": cid(a) })
	assert_true(law().is_lawful_bid(int(r2.get("battle_id", 0))), "PK 4 仍可合法緝拿")
	drive_bid(int(r2.get("battle_id", 0)), { d: "fight", a: "defend" })
	assert_false(lastp_p(d, "law_no_bounty_daily").is_empty(), "同一天再殺 → law_no_bounty_daily")
	assert_eq(law().claims_total(cid(d)), fine + 5000, "沒有第二筆")
	assert_eq(int(chr(a).pk_value()), 4, "A 的 PK值 不再減")
	note("同隊 law_no_bounty_friend（PK 不減）；加碼 5000 → D 領 %d；同日再殺不發、PK 不減" % (fine + 5000))

## 名單上的 A 走野外 20 間 → 警告 → 開打、輸 → PK −1；穿烙跑鞋再遇 → 逃走成功
func sc_hunters() -> void:
	if not deps_ok():
		return
	ws.options["encounters_enabled"] = false
	ws.rng.seed = 314159
	var a := add("惡甲")
	_villain(a, 5, 0, 30000)
	law().refresh_board()
	goto_p(a, "xw_road")
	# 固定種子：第一個在 20 間內遇上的種子（8%／間；可重現）
	var warned := 0
	var seed_used := 0
	for sd in range(1, 40):
		ws.rng.seed = sd
		warned = _walk_until_warn(a, 20)
		if warned != 0:
			seed_used = sd
			break
	assert_true(warned > 0, "20 間內至少一次 law_hunter_warn")
	if warned <= 0:
		return
	var warn_s := float(ws.options.get("villain_warn_s", 3))
	ws.advance(warn_s * float(ws.time_scale) + 0.5)
	var bid := sess(a).battle_id
	assert_true(bid != 0 and law().is_hunter_bid(bid), "倒數結束開追擊戰")
	make_weak_p(a)
	drive_bid(bid, { a: "defend" })
	assert_eq(int(chr(a).pk_value()), 4, "死於賞金獵人 PK值 −1")
	# 烙跑鞋
	Survival.rest_full(chr(a), tables(), ws.options)
	law().refresh_board()
	var uid: String = str(host().give_item(chr(a), "i_cb_laopaoxie", 1).get("uid", ""))
	sess(a).last_equip_ms = -100000
	ok_p(a, "equip", { "item_uid": uid })
	LawSystem.law_ext(chr(a))["hunt_cd_s"] = 0.0
	goto_p(a, "xw_road")
	var w2 := _walk_until_warn(a, 60)
	assert_true(w2 > 0, "再遇一次")
	if w2 <= 0:
		return
	ws.advance(warn_s * float(ws.time_scale) + 0.5)
	var bid2 := sess(a).battle_id
	assert_true(bid2 != 0, "第二次追擊戰")
	var fled := false
	for i in 600:
		if not host().battles.active.has(bid2):
			break
		var bt = host().battles.active[bid2]["battle"]
		var u = _unit_of(bt, a)
		if u != null and str(u.state) == "READY":
			var r := send_p(a, "battle_cmd", { "battle_id": bid2, "cmd": "FLEE" })
			assert_true(r.get("ok", false), "穿鞋任何格子都能逃：%s" % str(r))
		ws.advance(0.1)
	fled = str(remote[a].get("battle_close", {}).get("result", "")) == "FLED" or sess(a).battle_id == 0
	assert_true(fled, "穿烙跑鞋逃走成功")
	assert_eq(str(remote[a].get("battle_close", {}).get("result", "")), "FLED", "結果 FLED")
	note("種子 %d 第 %d 間警告 → 追擊戰輸 → PK 4；烙跑鞋第 %d 間再遇 → FLED" % [seed_used, warned, w2])

func _walk_until_warn(peer: int, max_rooms: int) -> int:
	var n0 := evs_p(peer, "law_hunter_warn").size()
	for i in max_rooms:
		var here := sess(peer).room_id()
		var dir := "E" if here == "xw_road" else "W"
		var r := send_p(peer, "move", { "dir": dir })
		if not r.get("ok", false):
			fail("move %s from %s: %s" % [dir, here, str(r)])
			return -1
		ws.advance(0.1)
		if evs_p(peer, "law_hunter_warn").size() > n0:
			return i + 1
	return 0

## 殺氣 95 找西夏天師消 10 次 → 只消 9 次扣 900；1.0B 半仙 PK 2 → 1、扣 10000；同日 → cleanse_daily
func sc_cleanse() -> void:
	if not deps_ok():
		return
	law().hunter_chance_pct = 0
	var a := add("殺星甲")
	goto_p(a, "xw_road")
	var c = chr(a)
	c.killing_intent = 95
	c.money = 5000
	var r := ok_p(a, "cleanse", { "npc": "n_law_tianshi_xx", "what": "KILLING", "times": 10 })
	assert_eq(int(r.get("times", 0)), 9, "只消 9 次")
	assert_eq(int(c.money), 4100, "扣 900 兩")
	assert_eq(int(c.killing_intent), 5)
	c.pk = 2
	c.pk_stamp_s = c.online_s
	c.money = 25000
	goto_p(a, "jc_square")
	ok_p(a, "cleanse", { "npc": "n_law_banxian_jc", "what": "PK" })
	assert_eq(int(c.pk_value()), 1, "半仙：PK 2 → 1")
	assert_eq(int(c.money), 15000, "扣 10000")
	assert_eq(reason_p(a, "cleanse", { "npc": "n_law_banxian_jc", "what": "PK" }), "cleanse_daily")
	note("天師 9 次 900 兩；半仙 PK 2→1 扣 10000；同日 cleanse_daily")

## classic_strict：PK 2、上線 2 小時 → 仍 2；classic_standard → 0
func sc_pk_decay() -> void:
	if not deps_ok():
		return
	var a := add("甲俠")
	use_preset("classic_strict")
	ws.advance(0.1)
	var c = chr(a)
	c.pk = 2
	c.pk_stamp_s = c.online_s
	c.online_s += 7200.0
	assert_eq(int(c.pk_value()), 2, "classic_strict：2 小時後仍 2")
	use_preset("classic_standard")
	ws.advance(0.1)
	assert_eq(int(c.pk_value()), 0, "classic_standard：2 小時 → 0")
	note("strict 2→2；standard 2→0")

# ======================================================================== B 戰鬥增補
## 閃：BattleRules 直接跑 2000 次，下降 ∈ [0.15, 0.30]；輕：JUMP 越過敵人、ESCAPE 統計率
func sc_dodge_qing() -> void:
	var rates := []
	for dodging in [false, true]:
		var b := H.make_battle([H.player_spec({ "qi": 100000, "qi_max": 100000, "skills": { "basic_dodge": 100 } }),
			H.monster("m_wolf", { "qi": 100000, "qi_max": 100000 })], 4242)
		H.place(b, 1, 1, 3)
		H.place(b, 2, 2, 3)
		var rng := RandomNumberGenerator.new()
		rng.seed = 2001
		var hits := 0
		for i in 2000:
			b.unit(1).dodging = dodging
			b.unit(1).qi = b.unit(1).qi_max()
			var ev := BattleRules.resolve_strike(b, b.unit(2), b.unit(1), {}, {}, 0, H.tables(), rng, false, true)
			if H.find(ev, "battle_miss").is_empty():
				hits += 1
		rates.append(hits / 2000.0)
	var drop: float = rates[0] - rates[1]
	assert_true(drop >= 0.15 and drop <= 0.30, "閃：命中率 %.3f → %.3f，下降 %.3f ∈ [0.15, 0.30]" % [rates[0], rates[1], drop])
	# 輕 JUMP
	var bj := H.make_battle([H.player_spec({ "qi": 100000, "qi_max": 100000, "neili": 100, "neili_max": 100 }),
		H.monster("m_wolf"), H.monster("m_wolf"), H.monster("m_wolf")], 4242)
	H.place(bj, 1, 1, 3)
	H.place(bj, 2, 2, 3)
	H.place(bj, 3, 2, 2)
	H.place(bj, 4, 2, 4)
	var rj := H.do_cmd(bj, 1, { "cmd": "QING", "mode": "JUMP", "target": [4, 3] })
	assert_eq(rj.err, "", "QING JUMP")
	assert_eq(bj.unit(1).pos, Vector2i(4, 3), "越過敵人")
	# 輕 ESCAPE：輕功 50、基本輕功 50 → 50%
	var okn := 0
	var n := 1000
	for sd in range(1, n + 1):
		var be := H.make_battle([H.player_spec({ "neili": 100, "neili_max": 100, "lightness": 50, "skills": { "basic_body": 50 } }),
			H.monster("m_wolf")], sd)
		var want := BattleRules.qing_escape_chance(be.unit(1))
		if sd == 1:
			assert_true(absf(want - 0.5) < 0.001, "公式 50%")
		if not H.find(H.do_cmd(be, 1, { "cmd": "QING", "mode": "ESCAPE" }).events, "battle_qing_escape").is_empty():
			okn += 1
	var er := okn / float(n)
	assert_true(absf(er - 0.5) <= 0.05, "ESCAPE 統計 %.3f ≈ 0.50" % er)
	# later_battle_cmds 關 → qing_off
	var off := H.make_battle([H.player_spec({ "neili": 100, "neili_max": 100 }), H.monster("m_wolf")], 7, { "later_battle_cmds": false })
	assert_eq(H.do_cmd(off, 1, { "cmd": "QING", "mode": "ESCAPE" }).err, "qing_off")
	note("閃 %.3f→%.3f（−%.3f）；JUMP 越過；ESCAPE %.3f" % [rates[0], rates[1], drop, er])

## 1.0B 男全真＋女古墓：建立默契 → 組隊、同房（默契 0 即可；M3d 審查）→ 小龍女教 → 一起打怪 → battle_combo → 配合度增加
func sc_combo() -> void:
	if not _local("全真少俠", "xixia", "M"):
		return
	var her := _add_female("古墓少女")
	var me = ch()
	var hc = chr(her)
	ws.options["sect_hostile_entry"] = false
	host().sects.on_join(s(), "quanzhen", str(tables()["sects"]["quanzhen"].get("head_npc", "")))
	host().sects.on_join(sess(her), "gumu", str(tables()["sects"]["gumu"].get("head_npc", "")))
	me.sect = "quanzhen"
	hc.sect = "gumu"
	for c in [me, hc]:
		c.morality = 100
		c.combat_xp = 200000
		c.learn_points = 5000
		for at in ["wit", "con", "str", "agi", "cal"]:
			c.attrs[at] = 80
		c.skills.set_level("basic_sword", 80, tables())
		c.skills.set_level("basic_dodge", 60, tables())
		c.skills.set_level("basic_inner", 80, tables())
	goto("gm_xiaolongnu")
	goto_p(her, "gm_xiaolongnu")
	me.skills.set_level("qz_jianfa", 60, tables())
	me.skills.set_level("yangsheng", 30, tables())
	hc.skills.set_level("gm_yunu_jian", 60, tables())
	hc.skills.set_level("qingxin", 30, tables())
	for c in [me, hc]:
		Survival.rest_full(c, tables(), ws.options)
	ok("combo_bond", { "target_char": str(hc.id) })
	ok_p(her, "combo_reply", { "from_char": str(me.id), "accept": true })
	assert_false(host().combo.pair_of(str(me.id)).is_empty(), "建立默契")
	ok("party_invite", { "target": str(hc.id) })
	ok_p(her, "party_reply", { "from": str(me.id), "accept": true })
	ws.advance(0.2)
	host().combo.refresh_live_ctx()
	var args := { "npc": "n_gm_xiaolongnu", "skill": "gm_suxin", "times": 1 }
	# M3d 審查（第 3 輪）：修練要默契（官方「默契值與心性修為都達到一定程度」）→ 默契 0 學不到；
	# 兩人同一邊一起打贏攢配合度（每對每遊戲日最多 60）→ 配合度滿 100 培養感情 → 默契 +5；攢到 10 再學（不除錯寫默契）
	var pr: Dictionary = host().combo.pair_of(str(me.id))
	assert_eq(int(pr.get("moqi", -1)), 0, "默契 0")
	assert_eq(Requirements.combo_ready_reason({ "art": "gm_suxin" }, me, tables(), host().sects.req_ctx(s())), "combo_moqi_low",
		"默契 0 → 還不能學")
	var wins := 0
	var days := 0
	var need := int(tables()["martial_arts"]["gm_suxin"]["combo"].get("moqi_min", 0))
	while int(pr.get("moqi", 0)) < need and days < 12:
		for k in 7:
			for c in [me, hc]:
				Survival.rest_full(c, tables(), ws.options)
			var jb := start_battle(["m_rabbit"])
			if jb == 0:
				fail("開戰失敗（一起打）")
				return
			var bb = host().battles.active[jb]["battle"]
			if wins == 0:
				assert_eq(int(bb.humans()), 2, "隊友一起進戰鬥")
			A.finish(self, 1, true)   # 打贏（勝負不是受測物，結算才是）
			assert_eq(int(sess(her).battle_id), 0, "夥伴也結算了")
			wins += 1
			if int(pr.get("peihe", 0)) >= 100:
				ok("combo_nurture")
		ws.world["world_time_s"] = ws.world_time() + host().day_s()
		ws.advance(0.2)
		days += 1
	assert_true(int(pr.get("moqi", 0)) >= need, "一起打贏 %d 場、%d 個遊戲日 → 默契 %d" % [wins, days, int(pr.get("moqi", 0))])
	goto("gm_xiaolongnu")
	goto_p(her, "gm_xiaolongnu")
	me.skills.set_level("yangsheng", 30, tables())
	hc.skills.set_level("qingxin", 30, tables())
	host().combo.refresh_live_ctx()
	assert_eq(Requirements.combo_ready_reason({ "art": "gm_suxin" }, me, tables(), host().sects.req_ctx(s())), "",
		"默契夠、同房同隊、配得上 → 可以學")
	note("默契 0 學不到；一起打贏 %d 場（%d 遊戲日）攢到默契 %d" % [wins, days, int(pr.get("moqi", 0))])
	ok("learn", args)
	ok_p(her, "learn", args)
	assert_true(me.skills.level("gm_suxin") >= 1 and hc.skills.level("gm_suxin") >= 1, "兩人都學到素心劍")
	for c in [me, hc]:
		c.skills.set_level("gm_suxin", 60, tables())
	# 換上劍
	for p in [1, her]:
		var cc = chr(p)
		var uid: String = str(host().give_item(cc, "w_mujian", 1).get("uid", ""))
		sess(p).last_equip_ms = -100000
		if p == 1:
			ok("equip", { "item_uid": uid })
		else:
			ok_p(p, "equip", { "item_uid": uid })
	var peihe0 := int(host().combo.pair_of(str(me.id)).get("peihe", 0))
	var combos := 0
	for round_i in 40:   # 默契 10（成功率 23.5%）→ 多打幾場
		for c in [me, hc]:
			Survival.rest_full(c, tables(), ws.options)
		for c in [me, hc]:
			c.clamp_vitals(tables(), ws.options)
			Survival.rest_full(c, tables(), ws.options)
		var bid := start_battle(["m_bandit"])
		if bid == 0:
			fail("開戰失敗")
			return
		combos += _drive_combo(bid, her)
		ws.advance(0.5)
		if combos > 0:
			break
	assert_true(combos > 0, "至少一次 battle_combo（ART 被拒：%s）" % _combo_art_err)
	var peihe1 := int(host().combo.pair_of(str(me.id)).get("peihe", 0))
	assert_true(peihe1 > peihe0, "配合度增加 %d → %d" % [peihe0, peihe1])
	note("兩人學到素心劍；battle_combo（至少 %d 次）；配合度 %d→%d" % [combos, peihe0, peihe1])

## 兩人都用素心劍「雙劍合璧」打同一個敵人（窗內兩招 → 合體一擊）；回傳 battle_combo 次數
func _drive_combo(bid: int, her: int) -> int:
	var hits := 0
	var t := 0.0
	var art_err := ""
	while host().battles.active.has(bid) and t < 300.0:
		var b = host().battles.active[bid]["battle"]
		for u0 in b.units:
			hits = maxi(hits, int(u0.get("combo_hits")))
		for peer in [1, her]:
			var u = _unit_of(b, peer)
			if u == null or str(u.state) != "READY" or b.is_over():
				continue
			var foe = null
			for e in b.units:
				if int(e.side) != int(u.side) and e.is_active():
					foe = e
			if foe == null:
				continue
			var cmd := {}
			var is_art := _dist(u.pos, foe.pos) == 1
			if is_art:
				cmd = { "cmd": "ART", "art": "gm_suxin", "move": "gm_sx_1", "power_tenths": 10, "target": [foe.pos.x, foe.pos.y] }
			else:
				cmd = _cmd_for(b, u, "fight")
			cmd["battle_id"] = bid
			var r := send_p(peer, "battle_cmd", cmd) if peer != 1 else send("battle_cmd", cmd)
			if not r.get("ok", false):
				if is_art and art_err == "":
					art_err = str(r.get("reason", ""))
				var d := { "battle_id": bid, "cmd": "DEFEND" }
				if peer != 1:
					send_p(peer, "battle_cmd", d)
				else:
					send("battle_cmd", d)
		ws.advance(0.1)
		t += 0.1
	if art_err != "":
		note("ART 被拒：" + art_err)
		_combo_art_err = art_err
	return hits

var _combo_art_err := ""

## 連按兩次換武器間隔 1 秒 → equip_cooldown；2.1 秒 → 成功
func sc_equip_cd() -> void:
	if not _local("換裝俠客"):
		return
	var a := give("w_mujian")
	var b := give("w_dandao")
	s().last_equip_ms = -100000
	ok("equip", { "item_uid": a })
	OS.delay_msec(1000)
	assert_eq(reason("equip", { "item_uid": b }), "equip_cooldown", "間隔 1 秒 → equip_cooldown")
	OS.delay_msec(1100)
	ok("equip", { "item_uid": b })
	assert_eq(str(ch().inventory.equipped.get("WEAPON", "")), b, "2.1 秒 → 成功")
	note("1.0 秒 equip_cooldown；2.1 秒成功")

## 撥到戌時：夜晚變暗；給夜明珠 → 不變暗（畫面截圖在 ui_playthrough 有視窗那一輪）
func sc_night() -> void:
	if not _local("夜行人"):
		return
	set_shichen(10)   # 戌
	host().flush_session(s(), true)
	ws.flush()
	var sh := sheet()
	assert_true(bool(sh.get("clock", {}).get("night", false)), "戌時是夜晚")
	var ms := load("res://ui/game/main/main_screen.gd")
	assert_true(ms.night_dim_on(sh), "夜晚變暗")
	give("i_cb_yemingzhu")
	s().sheet_dirty = true
	host().flush_session(s(), true)
	ws.flush()
	var inv_ids: Array = []
	for it in sheet().get("inventory", []):
		inv_ids.append(str(it.get("id", "")) if it is Dictionary else str(it))
	assert_false(ms.night_dim_on(sheet()), "有夜明珠不變暗（背包 %s）" % str(inv_ids))
	set_shichen(6)
	host().flush_session(s(), true)
	ws.flush()
	assert_false(bool(sheet().get("clock", {}).get("night", true)), "午時不是夜晚")
	note("戌時變暗；夜明珠不暗；午時亮")

# ======================================================================== C 武功鏈
## story_acceptance 跑 q_ar_* 的 test_plan 由協調器另開；這裡驗 1.0A 視圖看不到 1.0B 的鏈
func sc_arts_1_0a() -> void:
	if not game_ok():
		return
	use_eras(["1.0A"])
	for qid in ["q_ar_qz_chongyang", "q_ar_qz_kongming", "q_ar_lj_bahuang", "q_ar_em_luosha", "q_ar_xd_xuemo"]:
		assert_false(tables()["quests"].has(qid), "1.0A 沒有 " + qid)
	assert_true(tables()["quests"].has("q_ar_xh_muding"), "小木鼎（1.0A）在")
	note("1.0A 視圖 5 條 1.0B 鏈不出現、小木鼎在")

## 血刀弟子恐嚇 3 個不同 NPC → 威嚇熟練 +60、善惡 −30；同一個再一次 → intimidate_daily
func sc_intimidate() -> void:
	if not _local("血刀弟子"):
		return
	ws.options["sect_hostile_entry"] = false
	ch().sect = "xuedao"
	host().sects.on_join(s(), "xuedao", str(tables()["sects"]["xuedao"].get("head_npc", "")))
	ch().morality = -200
	ch().skills.set_level("weihe", 10, tables())
	ch().combat_xp = 100000
	goto("xx_inn")
	var p0 := int(ch().skills.prof("weihe"))
	var mo := int(ch().morality)
	for npc in ["n_xx_innkeeper", "n_xx_azi", "n_xx_laodenuo"]:
		Survival.rest_full(ch(), tables(), ws.options)
		ok("intimidate", { "npc": npc })
	assert_eq(int(ch().skills.prof("weihe")) - p0, 60, "威嚇熟練 +60")
	assert_eq(int(ch().morality) - mo, -30, "善惡 −30")
	assert_eq(reason("intimidate", { "npc": "n_xx_innkeeper" }), "intimidate_daily")
	note("3 個 NPC 威嚇 +60、善惡 −30；同 NPC intimidate_daily")

## 全真弟子殺 11 個古墓弟子 → 第 11 個後門規觸發（classic_standard → 坐牢）
func sc_qz_gumu() -> void:
	if not _local("全真弟子"):
		return
	ws.options["sect_hostile_entry"] = false
	ch().sect = "quanzhen"
	host().sects.on_join(s(), "quanzhen", str(tables()["sects"]["quanzhen"].get("head_npc", "")))
	ch().morality = 500
	make_strong()
	var jailed_at := 0
	for i in 11:
		goto("zn_road2")
		Survival.rest_full(ch(), tables(), ws.options)
		start_battle(["m_gm_dizi"])
		_kill_now(1, true)
		host().sects.check_state(s(), "BATTLE")
		if ch().is_jailed() and jailed_at == 0:
			jailed_at = i + 1
	assert_eq(int(ch().counters.get(ArtsRules.COUNTER_QZ_GUMU, 0)), 11, "計數 11")
	assert_eq(jailed_at, 11, "第 11 個後坐牢")
	assert_eq(str(ch().jail.get("rule", "")), "qz_r_kill_gumu")
	note("第 %d 個觸發 qz_r_kill_gumu（坐牢）" % jailed_at)

# ======================================================================== D 事件
## 實戰 10 萬在西夏接送貨鏢（扣 3200）→ 到大理 +6400；再接 → jb_cooldown；大理二掌櫃接護送鏢 → 遇特殊地雷逃 → 失敗
func sc_jiebiao() -> void:
	if not _local("押鏢俠"):
		return
	make_strong()
	var c = ch()
	c.combat_xp = 100000
	c.fame = 100
	c.lilian = 100
	c.money = 20000
	goto("xx_biaoju")
	ok("quest_accept", { "npc": "n_ev_jb_xx", "quest": "q_ev_jb_xx_dl_huo" })
	assert_eq(int(c.money), 20000 - 3200, "押金 3200")
	JiebiaoSystem.active_of(c)["rooms_since"] = -1000   # 路上的地雷另測
	goto("dl_biaoju")
	host().quests.on_reach(s())
	host().jiebiao.reconcile(s())
	ws.flush()
	assert_eq(int(c.money), 20000 + 3200, "送達 +6400")
	goto("xx_biaoju")
	assert_eq(reason("quest_accept", { "npc": "n_ev_jb_xx", "quest": "q_ev_jb_xx_dl_huo" }), "jb_cooldown")
	goto("dl_biaoju")
	var m1 := int(c.money)
	ok("quest_accept", { "npc": "n_ev_jb_dl", "quest": "q_ev_jb_dl_xx_hu" })
	var dep := m1 - int(c.money)
	assert_true(dep > 0, "護送鏢押金 %d" % dep)
	# 穿烙跑鞋，走野外直到特殊地雷，逃
	var uid := give("i_cb_laopaoxie")
	s().last_equip_ms = -100000
	ok("equip", { "item_uid": uid })
	var hit := false
	for i in 200:
		goto("xw_road" if i % 2 == 0 else "xw_grass")
		if s().battle_id != 0:
			hit = true
			break
	assert_true(hit, "遇上特殊地雷")
	if not hit:
		return
	var fbid := s().battle_id
	for i in 1200:
		if s().battle_id == 0:
			break
		var fb = host().battles.active.get(fbid, {}).get("battle")
		var me = _unit_of(fb, 1) if fb != null else null
		if me != null and str(me.state) == "READY":
			send("battle_cmd", { "battle_id": fbid, "cmd": "FLEE" })
		ws.advance(0.1)
	assert_eq(str(cs.last_battle_result.get("result", "")), "FLED", "穿烙跑鞋逃走")
	assert_true(JiebiaoSystem.active_of(c).is_empty(), "逃走 → 押鏢失敗")
	assert_eq(int(c.money), m1 - dep, "押金沒了")
	note("送貨鏢 −3200 → +6400；jb_cooldown；護送鏢地雷逃走 → 失敗、押金 %d 沒收" % dep)

## A 押鏢、B 劫鏢：標記立即存在；B 逃 → no_flee；B 殺鏢車 → B 得 2560、A 失敗、B PK +1；B 進西夏 → 官兵 2 名
func sc_rob() -> void:
	if not _local("押鏢甲"):
		return
	make_strong()
	var c = ch()
	c.combat_xp = 100000
	c.fame = 100
	c.lilian = 100
	c.money = 20000
	goto("xx_biaoju")
	ok("quest_accept", { "npc": "n_ev_jb_xx", "quest": "q_ev_jb_xx_dl_huo" })
	JiebiaoSystem.active_of(c)["rooms_since"] = -1000
	goto("xw_grass")
	var b := add("劫鏢乙")
	var rc = chr(b)
	rc.combat_xp = 100000
	rc.money = 0
	goto_p(b, "xw_grass")
	var pk0 := int(rc.pk_value())
	var r := ok_p(b, "rob_escort", { "target_char": str(c.id) })
	assert_true(JiebiaoRules.rob_marked(rc.ext, host().now_s()), "劫鏢標記立即存在")
	var entry: Dictionary = host().battles.active.get(s().battle_id, {})
	var bt = entry.get("battle")
	assert_eq(reason_p(b, "battle_cmd", { "battle_id": bt.id, "cmd": "FLEE" }), "no_flee", "劫鏢方逃 → no_flee")
	var cart = bt.unit(int(entry.get("rob_uid", 0)))
	var ru = _unit_of(bt, b)
	BattleRules.kill(bt, cart, ru)
	ws.advance(0.3)
	assert_eq(int(rc.money), 2560, "B 得 2560")
	assert_true(JiebiaoSystem.active_of(c).is_empty(), "A 押鏢失敗")
	assert_eq(int(rc.pk_value()), pk0 + 1, "B PK值 +1")
	# 進西夏：守城官兵 2 名
	Survival.rest_full(rc, tables(), ws.options)
	goto_p(b, "xw_road")
	goto_p(b, "xx_gate_e")
	var bid := sess(b).battle_id
	if bid == 0:
		host().pk.on_move(sess(b), "xw_road", "xx_gate_e")
		bid = sess(b).battle_id
	assert_true(bid != 0, "守城官兵追殺")
	var guards := 0
	if bid != 0:
		for u in host().battles.active[bid]["battle"].units:
			if int(u.side) == 1:
				guards += 1
		host().battles.abort_all()
	assert_eq(guards, 2, "官兵 2 名")
	note("標記即時；劫鏢方 no_flee；殺鏢車 B +2560、PK +1、A 失敗；進西夏官兵 %d 名" % guards)

## 主機開辦 WULIN → 5 人報名 → 輪空 3 → 不在場被點名 3 次判負 → 打完：冠軍「武林盟主」、令牌、名聲 +3000、傳聞、無死亡懲罰；馬上再開 → 表演賽
func sc_tourney() -> void:
	if not _local("盟主候補"):
		return
	ws.options["wait_mode"] = false
	make_strong()
	var peers: Array = []
	goto(TourneyRules.REST_ROOM)
	# M3d 審查：全新角色（實戰 0）報不了武林大會（要實戰 1 萬、PK值 0）
	assert_eq(reason("tourney_host", { "kind": "WULIN", "signup_s": 60 }), "", "主機開辦")
	assert_eq(reason("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "WULIN" }), "tourney_need_xp", "實戰 0 → 報名員不收")
	host().tourney.current().erase("WULIN")
	ch().combat_xp = int(TourneyRules.WULIN_ENTRY.xp)
	for i in 4:
		var p := add("參賽%s" % ["甲", "乙", "丙", "丁"][i])
		chr(p).combat_xp = int(TourneyRules.WULIN_ENTRY.xp)
		goto_p(p, TourneyRules.REST_ROOM)
		peers.append(p)
	ok("tourney_host", { "kind": "WULIN", "signup_s": 60 })
	ok("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "WULIN" })
	for p in peers:
		ok_p(p, "tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "WULIN" })
	var absent: int = peers[3]
	goto_p(absent, "xx_square")
	var all := [1] + peers
	var fame0 := {}
	var dead0 := {}
	for p in all:
		fame0[p] = int(chr(p).fame)
		dead0[p] = int(chr(p).dead_count)
	ws.advance(61.0)
	var tsys = host().tourney
	var ev: Dictionary = tsys.event_of("WULIN")
	var byes := 0
	for m in ev.get("rounds", [[]])[0]:
		if str(m.a) == "" or str(m.b) == "":
			byes += 1
	assert_eq(byes, 3, "5 人輪空 3")
	_tourney_run("WULIN")
	var absent_name := str(chr(absent).name)
	var calls := 0
	for e in evs("ev_tourney_call"):
		if str(e.p.get("name", "")) == absent_name:
			calls = maxi(calls, int(e.p.get("n", 0)))
	assert_eq(calls, 3, "不在場被點名 3 次")
	var h: Dictionary = tsys.state()["history"][0]
	var champ_peer := 0
	for p in all:
		if str(chr(p).name) == str(h.get("champion", "")):
			champ_peer = p
	assert_true(champ_peer != 0, "有冠軍")
	if champ_peer == 0:
		return
	var cc = chr(champ_peer)
	assert_has(tsys.titles_of(cc), "武林盟主")
	assert_eq(int(cc.inventory.count("i_ev_mengzhu_ling")), 1, "盟主令牌")
	assert_eq(int(cc.fame) - int(fame0[champ_peer]), 3000, "名聲 +3000")
	var heard := false
	for r in host().rumor.recent(20):
		if str(r.get("text_key", "")) == "rmr_ev_tourney_champion":
			heard = true
	assert_true(heard, "全服傳聞")
	for p in all:
		assert_eq(int(chr(p).dead_count), int(dead0[p]), "沒有死亡懲罰 %s" % str(chr(p).name))
	goto_p(absent, TourneyRules.REST_ROOM)
	goto(TourneyRules.REST_ROOM)
	for p in peers:
		goto_p(p, TourneyRules.REST_ROOM)
	ok("tourney_host", { "kind": "WULIN", "signup_s": 30 })
	ok("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "WULIN" })
	for p in peers:
		ok_p(p, "tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "WULIN" })
	ws.advance(31.0)
	assert_true(bool(tsys.event_of("WULIN").get("exhibition", false)), "馬上再開 → 表演賽")
	assert_has(tsys.titles_of(cc), "武林盟主", "M3d 審查第三輪：表演賽開打不收回盟主")
	assert_eq(int(cc.inventory.count("i_ev_mengzhu_ling")), 1, "表演賽開打不收回令牌")
	var f1 := {}
	for p in all:
		f1[p] = int(chr(p).fame)
	_tourney_run("WULIN")
	for p in all:
		assert_eq(int(chr(p).fame), int(f1[p]), "表演賽沒有獎勵")
	assert_eq(str(tsys.state()["champions"].get("WULIN", "")), str(cc.id), "表演賽冠軍不改種子")
	note("輪空 %d；點名 3 次判負；冠軍 %s 武林盟主、令牌、+3000；傳聞；無死亡懲罰；再開＝表演賽（盟主與令牌留著）" % [byes, str(cc.name)])

func _tourney_run(kind: String) -> void:
	var tsys = host().tourney
	for i in 600:
		var ev: Dictionary = tsys.event_of(kind)
		if ev.is_empty():
			return
		var m: Dictionary = ev.get("match", {})
		var bid := int(m.get("bid", 0))
		if bid != 0 and host().battles.active.has(bid):
			host().battles.active[bid]["battle"].ev_end(0, "KO")
			ws.advance(0.2)
			continue
		ws.advance(5.0)
	fail("比武沒有結束")

## M3d 審查第三輪：懷舊嚴苛（classic_strict，規則 later_events 關＝2001）→ 沒有門派比武與武林大會（日曆到了不開、主機開辦不行）、
## 血池三位不陪打；換回預設規則就有
func sc_strict_events() -> void:
	if not _local("嚴苛俠客"):
		return
	var eras: Array = GameData.enabled_eras.duplicate()
	assert_true(GameData.activate(eras, { "preset": "classic_strict" }), "activate classic_strict")
	assert_eq(GameData.rules.get("later_events", true), false, "classic_strict：later_events 關")
	var tsys = host().tourney
	assert_false(bool(tsys.enabled()), "比武關")
	goto(TourneyRules.REST_ROOM)
	assert_eq(reason("tourney_host", { "kind": "WULIN", "signup_s": 30 }), "tourney_disabled", "主機開辦不行")
	var day_s := float(ws.options.get("game_day_real_s", 7200))
	for d in [8, 24]:
		ws.world["world_time_s"] = TourneyRules.world_s_at(d, 4, day_s) + 1.0
		ws.advance(1.0)
		assert_true(tsys.current().is_empty(), "第 %d 日：沒有比武開報名" % d)
	ws.options["sect_hostile_entry"] = false
	ch().sect = "xuedao"
	host().sects.on_join(s(), "xuedao", str(tables()["sects"]["xuedao"].get("head_npc", "")))
	ch().morality = -200
	ch().skills.set_level("weihe", 80, tables())
	goto("xd_pool")
	for npc in ["n_ar_xd_xuechi", "n_ar_xd_xuechi_2", "n_ar_xd_xuechi_3"]:
		assert_eq(reason("fight", { "npc": npc }), "req_rule", "%s 不陪打" % npc)
	# 換回預設規則：比武與血池都回來
	assert_true(GameData.activate(eras, { "preset": "classic_standard" }), "activate classic_standard")
	assert_true(bool(tsys.enabled()), "預設規則有比武")
	Survival.rest_full(ch(), tables(), ws.options)
	assert_eq(reason("fight", { "npc": "n_ar_xd_xuechi" }), "", "預設規則血池陪打")
	note("classic_strict：tourney_disabled、第 8／24 日不開報名、血池 req_rule；classic_standard 恢復")

## 4 位少林弟子門派比武 → 冠軍「少林派掌門師兄」、名聲 +1000、歷練 +800
func sc_sect_tourney() -> void:
	if not _local("少林甲"):
		return
	ws.options["wait_mode"] = false
	make_strong()
	ch().sect = "shaolin"
	ch().combat_xp = 5000   # M3d 審查：門派比武要實戰 1000（少林另要 PK值 0）
	goto(TourneyRules.REST_ROOM)
	var all := [1]
	for i in 3:
		var p := add("少林%s" % ["乙", "丙", "丁"][i])
		chr(p).sect = "shaolin"
		chr(p).combat_xp = 5000
		goto_p(p, TourneyRules.REST_ROOM)
		all.append(p)
	ok("tourney_host", { "kind": "SECT:shaolin", "signup_s": 30 })
	var before := {}
	for p in all:
		if p == 1:
			ok("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "SECT" })
		else:
			ok_p(p, "tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "SECT" })
		before[p] = [int(chr(p).fame), int(chr(p).lilian)]
	ws.advance(31.0)
	_tourney_run("SECT:shaolin")
	var h: Dictionary = host().tourney.state()["history"][0]
	var cp := 0
	for p in all:
		if str(chr(p).name) == str(h.get("champion", "")):
			cp = p
	assert_true(cp != 0, "有冠軍")
	if cp == 0:
		return
	assert_has(host().tourney.titles_of(chr(cp)), "少林派掌門師兄")
	assert_eq(int(chr(cp).fame) - int(before[cp][0]), 1000, "名聲 +1000")
	assert_eq(int(chr(cp).lilian) - int(before[cp][1]), 800, "歷練 +800")
	note("冠軍 %s 少林派掌門師兄、名聲 +1000、歷練 +800" % str(chr(cp).name))

# ======================================================================== E 跑腿
## 柯鎮惡→郭靖 7 次（同一天）名聲 5,5,4,3,2,1,0；豬哥義→三八紅（粗話被拒、再客氣）+200 兩 +8 名聲；武林帖贏 → 再用 wlt_cooldown、帖子還在
func sc_errands() -> void:
	if not _local("跑腿的人"):
		return
	ch().fame = 500
	ch().lilian = 500
	_to_day_start()
	var fames: Array = []
	for i in 7:
		var f0 := int(ch().fame)
		goto("mw_snow")
		ok("quest_accept", { "npc": "n_er_kezhene", "quest": "q_er_kezhene" })
		_pick("n_er_kezhene", "q_er_kezhene", "n0", "c_ask")
		_pick("n_er_kezhene", "q_er_kezhene", "n1", "c_yes")
		goto("zn_bridge")
		ok("quest_talk", { "npc": "n_er_guojing", "quest": "q_er_kezhene" })
		_pick("n_er_guojing", "q_er_kezhene", "n0", "c_give")
		fames.append(int(ch().fame) - f0)
	assert_eq(fames, [5, 5, 4, 3, 2, 1, 0], "柯鎮惡→郭靖 名聲遞減")
	# 豬哥義 → 三八紅
	var m0 := int(ch().money)
	var f1 := int(ch().fame)
	goto("xx_square")
	ok("quest_accept", { "npc": "n_xx_zhugeyi", "quest": "q_er_zhugeyi" })
	_pick("n_xx_zhugeyi", "q_er_zhugeyi", "n0", "c_yes")
	goto("dl_fangzhi")
	ok("quest_talk", { "npc": "n_er_sanbahong", "quest": "q_er_zhugeyi" })
	_pick("n_er_sanbahong", "q_er_zhugeyi", "n0", "c_rude")
	assert_eq(item_count("i_er_zgy_baofu"), 1, "粗話被拒")
	ok("quest_talk", { "npc": "n_er_sanbahong", "quest": "q_er_zhugeyi" })
	_pick("n_er_sanbahong", "q_er_zhugeyi", "n0", "c_polite")
	goto("xx_square")
	ok("quest_talk", { "npc": "n_xx_zhugeyi", "quest": "q_er_zhugeyi" })
	_pick("n_xx_zhugeyi", "q_er_zhugeyi", "n0", "c_give")
	assert_eq(int(ch().money) - m0, 200, "+200 兩")
	assert_eq(int(ch().fame) - f1, 8, "+8 名聲")
	# 武林帖
	make_strong()
	ch().combat_xp = 30000
	var uid := give("i_er_wulintie", 2)
	goto("xw_road")
	ok("use_item", { "item_uid": uid })
	assert_true(s().battle_id != 0, "武林帖開打")
	_kill_now(1, true)
	assert_eq(item_count("i_er_wulintie"), 1)
	assert_eq(reason("use_item", { "item_uid": first_uid("i_er_wulintie") }), "wlt_cooldown")
	assert_eq(item_count("i_er_wulintie"), 1, "冷卻中帖子還在")
	note("柯鎮惡 %s；三八紅 粗話拒、客氣 +200 兩 +8；武林帖贏 → wlt_cooldown" % str(fames))

## 午時送便當 3 次 → 50、30、15；酒鬼拒絕 −40 兩；阿虎 +50 學點 +300 兩；李大嬸（實戰 500）+200 兩 +10 學點
func sc_town_lp() -> void:
	if not _local("城裡跑腿"):
		return
	_to_day_start()
	set_shichen(6)
	var got: Array = []
	for i in 3:
		var lp0 := int(ch().learn_points)
		goto("xx_minfang")
		ok("quest_accept", { "npc": "n_er_xx_funv", "quest": "q_er_biandang_xx" })
		_pick("n_er_xx_funv", "q_er_biandang_xx", "n0", "c_yes")
		goto("hf_paddy")
		ok("quest_talk", { "npc": "n_er_xx_nongfu", "quest": "q_er_biandang_xx" })
		_pick("n_er_xx_nongfu", "q_er_biandang_xx", "n0", "c_give")
		got.append(int(ch().learn_points) - lp0)
	assert_eq(got, [50, 30, 15], "便當學點 50、30、15")
	ch().money = 100
	goto("dl_bank")
	ok("quest_accept", { "npc": "n_er_dl_zuigui", "quest": "q_er_zuigui" })
	_pick("n_er_dl_zuigui", "q_er_zuigui", "n0", "c_no")
	assert_eq(int(ch().money), 60, "酒鬼拒絕 −40 兩")
	var lp1 := int(ch().learn_points)
	var m1 := int(ch().money)
	_run_path("q_er_ahu", _plan("q_er_ahu"))
	assert_eq(int(ch().learn_points) - lp1, 50, "阿虎 +50 學點")
	assert_eq(int(ch().money) - m1, 300, "阿虎 +300 兩")
	ch().combat_xp = 500
	var lp2 := int(ch().learn_points)
	var m2 := int(ch().money)
	goto("jc_street")
	ok("quest_accept", { "npc": "n_jc_lidashen", "quest": "q_jc_xiaobao" })
	_pick("n_jc_lidashen", "q_jc_xiaobao", "n0", "_next")
	_pick("n_jc_lidashen", "q_jc_xiaobao", "n1", "c_help")
	goto("jc_zijin")
	ok("quest_talk", { "npc": "n_jc_zijin_guard", "quest": "q_jc_xiaobao" })
	_pick("n_jc_zijin_guard", "q_jc_xiaobao", "n0", "c_ask")
	_pick("n_jc_zijin_guard", "q_jc_xiaobao", "n1", "_next")
	ok("quest_talk", { "npc": "n_jc_xiaobao", "quest": "q_jc_xiaobao" })
	_pick("n_jc_xiaobao", "q_jc_xiaobao", "n0", "c_mom")
	_pick("n_jc_xiaobao", "q_jc_xiaobao", "n1", "c_promise")
	for d in ["SE", "S", "W"]:   # 帶著小保走回京城大街（瞬移會讓護送對象走散）
		ok("move", { "dir": d })
	ok("quest_talk", { "npc": "n_jc_lidashen", "quest": "q_jc_xiaobao" })
	_pick("n_jc_lidashen", "q_jc_xiaobao", "n0", "_next")
	_pick("n_jc_lidashen", "q_jc_xiaobao", "n1", "_next")
	assert_eq(int(ch().money) - m2, 200, "李大嬸 +200 兩")
	assert_eq(int(ch().learn_points) - lp2, 10, "李大嬸 +10 學點")
	note("便當 %s；酒鬼 −40；阿虎 +50/+300；李大嬸 +200/+10" % str(got))

## 1.0B：從 xe_heilong 進迷宮走到瑛姑 → 九尾靈狐 → 交 → 學點 +100；南坡打羊群 → 善惡下降；1.0A 沒有往南的出口
func sc_heilongtan() -> void:
	if not _local("黑龍潭客"):
		return
	make_strong()
	ch().combat_xp = 30000
	goto("xe_heilong")
	for d in ["S", "S", "E", "S", "W", "S"]:
		ok("move", { "dir": d })
	assert_eq(s().room_id(), "hl_hut", "照石碑走到瑛姑小屋")
	var path: Array = []
	for st in _plan("q_er_jiuwei"):
		if str(st) != "walk@hl_hut" or not path.is_empty():
			path.append(st)
	var k := path.find("walk@hl_hut")   # 打完靈狐、回小屋交差前（靈狐戰本身也給一點學點）
	_run_path("q_er_jiuwei", path.slice(0, k))
	var lp0 := int(ch().learn_points)
	_run_path("q_er_jiuwei", path.slice(k))
	assert_eq(int(ch().learn_points) - lp0, 100, "九尾靈狐交差 學點 +100")
	ch().morality = 1000
	goto("hl_slope")
	start_battle(["m_er_yang", "m_er_yang", "m_er_yang", "m_er_yang"])
	_kill_now(1, true)
	assert_true(int(ch().morality) < 1000, "打羊群善惡下降（%d）" % int(ch().morality))
	use_eras(["1.0A"])
	goto("xe_heilong")
	assert_eq(reason("move", { "dir": "S" }), "no_exit", "1.0A 黑龍潭沒有往南的出口")
	note("迷宮到瑛姑；靈狐 +100 學點；羊群善惡 1000→%d；1.0A no_exit" % int(ch().morality))

## 沒門派打贏陸大有 → 實戰學點 0、q_hs_kaoyan 完成；入華山後再打 → 有獎勵
func sc_spar_bug() -> void:
	if not _local("切磋的人"):
		return
	ws.options["sect_hostile_entry"] = false
	make_strong()
	goto("hs_square")
	ch().skills.set_level("basic_inner", 5, tables())
	ch().skills.set_level("basic_literacy", 5, tables())
	ok("quest_accept", { "npc": "n_yuebuqun", "quest": "q_hs_kaoyan" })
	var xp0 := int(ch().combat_xp)
	var lp0 := int(ch().learn_points)
	Survival.rest_full(ch(), tables(), ws.options)
	ok("fight", { "npc": "n_ludayou" })
	_kill_now(1, true)
	assert_eq(int(ch().combat_xp) - xp0 + int(ch().learn_points) - lp0, 0, "沒門派：實戰學點 0")
	ok("quest_turn_in", { "npc": "n_yuebuqun", "quest": "q_hs_kaoyan" })
	ok("join_sect", { "npc": "n_yuebuqun" })
	assert_eq(str(ch().sect), "huashan")
	xp0 = int(ch().combat_xp)
	Survival.rest_full(ch(), tables(), ws.options)
	ok("fight", { "npc": "n_ludayou" })
	_kill_now(1, true)
	assert_true(int(ch().combat_xp) > xp0, "入華山後有獎勵")
	note("無門派 0；考驗完成、入華山；再打實戰 +%d" % (int(ch().combat_xp) - xp0))

# ======================================================================== 0.7.0.1 學不到的武功
## 峨嵋弟子（金頂 60、九陽 60、斷惡 60）從靜玄接「滅絕師太的絕學」：周芷若的信 → 西夏客棧張無忌 → 回答問題（先答錯一次）
## → 打贏周芷若 → 鐵指環 → 滅絕傳佛光普照掌 1 級；自修到 50（不直接設等級）→ 羅煞劍 → 郭襄傳四象掌 → 郭襄教到 10 → 自修過 10
func _study_to(skill: String, target: int, master := "") -> bool:
	for i in 600:
		if ch().skills.level(skill) >= target:
			return true
		Survival.rest_full(ch(), tables(), ws.options)
		ch().learn_points = 100000
		var r: Dictionary = Learning.learn(ch(), master, skill, 500, tables(), ws.options, host().rules) if master != "" \
			else Learning.self_study(ch(), skill, 500, tables(), ws.options, host().rules)
		if not bool(r.get("ok", false)):
			fail("%s %s stuck at %d: %s" % ["learn" if master != "" else "self_study", skill, ch().skills.level(skill), str(r.get("reason", ""))])
			return false
	return ch().skills.level(skill) >= target

func sc_lost_arts() -> void:
	if not _local("峨嵋傳人", "xixia", "F"):
		return
	ws.options["sect_hostile_entry"] = false
	ch().sect = "emei"
	host().sects.on_join(s(), "emei", str(tables()["sects"]["emei"].get("head_npc", "")))
	make_strong()
	ch().combat_xp = 300000
	for k in ["em_jinding", "em_jiuyang", "duane", "basic_inner"]:
		ch().skills.set_level(k, 60, tables())
	for a in ["str", "wit", "con", "luck"]:
		ch().attrs[a] = maxi(20, int(ch().attrs.get(a, 0)))
	var Q := "q_em_tiezhihuan"
	if not _run_path(Q, ["walk@em_dadian", "accept@n_em_jingxuan", "choose@n_em_jingxuan:n0:c_yes",
			"walk@em_zhou", "talk@n_em_zhouzhiruo", "choose@n_em_zhouzhiruo:n0:c_ok",
			"walk@xx_inn_2f", "talk@n_zhangwuji", "choose@n_zhangwuji:n0:c_give",
			"walk@em_zhou", "talk@n_em_zhouzhiruo", "choose@n_em_zhouzhiruo:n0:c_q1c",
			"talk@n_em_zhouzhiruo", "choose@n_em_zhouzhiruo:n0:c_q1a", "choose@n_em_zhouzhiruo:n1:c_q2a",
			"choose@n_em_zhouzhiruo:n2:c_q3a", "talk@n_em_zhouzhiruo", "choose@n_em_zhouzhiruo:n0:c_fight", "fight:WIN",
			"walk@em_miejue", "talk@n_em_miejue", "choose@n_em_miejue:n0:c_give"]):
		return
	assert_eq(str(ch().quests["done"].get(Q, {}).get("outcome", "")), "default", "滅絕師太的絕學 完成")
	assert_true(bool(ch().flags.get("em_foguang_ok", false)), "em_foguang_ok")
	assert_eq(ch().skills.level("em_foguang"), 1, "佛光 1 級")
	ch().attrs["wit"] = 40
	if not _study_to("em_foguang", 50):
		return
	# 羅煞劍：三波蠻兵要一波一波打完（_kill_now 一次只結束一波）
	var lp: Array = _plan("q_ar_em_luosha", "sixiang")
	var fi := lp.find("fight:WIN")
	if not _run_path("q_ar_em_luosha", lp.slice(0, fi)):
		return
	for i in 10:
		if s().battle_id == 0:
			break
		_kill_now(1, true)
	assert_eq(s().battle_id, 0, "三波蠻兵打完")
	if not _run_path("q_ar_em_luosha", lp.slice(fi + 1)):
		return
	assert_eq(ch().skills.level("em_sixiang"), 1, "郭襄傳四象掌 1 級")
	if not _study_to("em_sixiang", 10, "n_ar_guoxiang"):
		return
	if not _study_to("em_sixiang", 12):
		return
	note("佛光 1（任務）→ 自修 %d；四象掌 郭襄 1→10、自修到 %d" % [ch().skills.level("em_foguang"), ch().skills.level("em_sixiang")])
