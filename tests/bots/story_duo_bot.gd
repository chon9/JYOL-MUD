extends RefCounted
## 故事驗收的多人與活的江湖劇本（STORY_PLAN §9.2），由 tools/story_acceptance.gd 的 worker 在同一行程裡跑：
## 一個 WorldServer、兩個假的遠端 session（tests/bots/story_bot.gd 的玩家驅動器，經 ClientState.capture_remote 收件）。
##
## run("duo")：
##   1. 雲兒：甲照 test_plan 選阿寶、乙選李台安（兩人都在線）→ 兩人結局各自正確；全服第一位傳聞
##      rmr_q_yuner_first 只發一次（兩人各收到一則，乙完成後不再發），ws.world.quest_firsts 記的是甲。
##   2. 劉二爺（下）：兩人都接（前置任務照它的 test_plan 走完）、組隊、走到衡山小茶店；
##      甲先「休息」到了秘密客階段 → 甲看得到秘密客、乙看不到（appear 各自判斷）；乙也休息後看得到。
##      乙先對暗語、伏擊時甲不在場、乙打輸（戰敗不算 WIN_OR_FLEE，乙停在伏擊階段）→ 乙回到茶店；
##      甲對暗語開打、乙（同隊、同房、目前目標相符）被拉進同一場 → 打贏後兩人都完成 FIGHT 目標 → 各自回報魯連榮完成。
## run("ambient")：白天交談即戰（葉二娘只對善惡 > 0；可逃）、南海鱷神交談即戰；
##   戌時南海鱷神放到下一間野外房間 → 走進去 → 警告 → 不動 → 追擊戰（CHASE、不能逃）→ 打贏 → villain_clear FOUGHT；
##   葉二娘警告內離開 → ESCAPED、不開打；新手（實戰 < 500）走進惡人所在房間不被出手；江湖傳聞列表（rumor_list）。

var ws: Node
var worker
var bots: Array = []
var err := ""
var info: PackedStringArray = []

func _init(p_ws: Node, p_worker) -> void:
	ws = p_ws
	worker = p_worker

func host():
	return ws.game

func fail(msg: String) -> bool:
	if err == "":
		err = msg
		print("[story:duo] FAIL " + msg)
	return false

func _bot_fail(b) -> bool:
	return fail("%s: %s" % [b.label, b.err])

func run(job: String, world: String) -> Dictionary:
	if not worker.start_world(world, hash(job)):
		return { "ok": false, "err": "world start failed" }
	var ok := false
	match job:
		"duo":
			ok = _duo()
		"ambient":
			ok = _ambient()
		_:
			ok = fail("unknown job " + job)
	if not ok or err != "":
		return { "ok": false, "err": err }
	return { "ok": true, "info": "; ".join(info) }

func _new(peer: int, tag: String, city: String):
	var b = worker.new_bot(peer, worker.unique_name(tag), "duo-" + tag)
	b.city = city
	b.allow_reload = false
	if not b.create_char():
		_bot_fail(b)
		return null
	return b

func _count_rumor(b, key: String) -> int:
	var n := 0
	for r in b.rumors:
		if str(r.get("text_key", "")) == key:
			n += 1
	return n

# ======================================================================== 雙人
func _duo() -> bool:
	var plans: Dictionary = worker.all_plans()
	var a = _new(100, "甲", "xixia")
	var b = _new(101, "乙", "dali")
	if a == null or b == null:
		return false
	# ---- 1. 雲兒：兩種結局、全服第一只發一次
	var pa: Dictionary = a.find_plan(plans, "q_yuner", "abao")
	var pb: Dictionary = b.find_plan(plans, "q_yuner", "li")
	if pa.is_empty() or pb.is_empty():
		return fail("q_yuner plans missing")
	if not a.run_plan(pa, plans, true):
		return _bot_fail(a)
	a.advance(3.0)
	if not b.run_plan(pb, plans, true):
		return _bot_fail(b)
	a.advance(3.0)
	if str(a.done_entry("q_yuner").get("outcome", "")) != "abao" or str(b.done_entry("q_yuner").get("outcome", "")) != "li":
		return fail("yuner outcomes %s / %s" % [str(a.done_entry("q_yuner")), str(b.done_entry("q_yuner"))])
	var first := str(ws.world.get("quest_firsts", {}).get("q_yuner", ""))
	if first != a.pname:
		return fail("quest_firsts.q_yuner = '%s', want %s" % [first, a.pname])
	var ra := _count_rumor(a, "rmr_q_yuner_first")
	var rb := _count_rumor(b, "rmr_q_yuner_first")
	if ra != 1 or rb != 1:
		return fail("first-completion rumor delivered %d/%d times (want exactly once each)" % [ra, rb])
	info.append("yuner abao/li ok, first rumor once")
	# ---- 2. 劉二爺（下）
	for o in [a, b]:
		if not o.satisfy_requires("q_liu_jinpen_2", plans):
			return _bot_fail(o)
	if not a.must("party_invite", { "target": b.char_id }) or not b.must("party_reply", { "from": a.char_id, "accept": true }):
		return fail("party: %s %s" % [a.err, b.err])
	for o in [a, b]:
		if not _steps(o, "q_liu_jinpen_2", ["walk@hn_island", "accept@n_hn_lulianrong", "choose@n_hn_lulianrong:n0:c_help",
				"choose@n_hn_lulianrong:n1:c_ming", "walk@hn_teahouse"]):
			return false
	if a.room() != "hn_teahouse" or b.room() != "hn_teahouse":
		return fail("not both at hn_teahouse: %s %s" % [a.room(), b.room()])
	if not a.do_step("act@q_liu_jinpen_2:a_rest", "q_liu_jinpen_2", {}):
		return _bot_fail(a)
	a._let_a_second_pass()
	if a.stage_of("q_liu_jinpen_2") != "s_mimike" or b.stage_of("q_liu_jinpen_2") != "s_rest":
		return fail("stages after rest: %s / %s" % [a.stage_of("q_liu_jinpen_2"), b.stage_of("q_liu_jinpen_2")])
	if not _sees(a, "n_hn_mimike") or _sees(b, "n_hn_mimike"):
		return fail("appear per player: A sees mimike=%s, B sees=%s" % [str(_sees(a, "n_hn_mimike")), str(_sees(b, "n_hn_mimike"))])
	if b.send("talk", { "npc": "n_hn_mimike" }).get("ok", false):
		return fail("B could talk to mimike before its own stage")
	info.append("appear: only A sees 秘密客")
	if not b.do_step("act@q_liu_jinpen_2:a_rest", "q_liu_jinpen_2", {}):
		return _bot_fail(b)
	b._let_a_second_pass()
	if not _sees(b, "n_hn_mimike"):
		return fail("B does not see mimike at s_mimike")
	# 乙先對暗語；甲先離開茶店（伏擊只拉同房隊友）；乙打輸 → 停在伏擊階段
	var out_room := _neighbor(a, "hn_teahouse")
	if out_room == "" or not a.walk(out_room):
		return fail("A could not step out of the teahouse: " + a.err)
	for st in ["talk@n_hn_mimike", "choose@n_hn_mimike:n0:c_sun", "choose@n_hn_mimike:n1:c_chan", "choose@n_hn_mimike:n2:c_what"]:
		if not b.do_step(st, "q_liu_jinpen_2", {}):
			return _bot_fail(b)
	if b.s().battle_id == 0:
		return fail("B's ambush did not start")
	if a.s().battle_id != 0:
		return fail("A was pulled into B's ambush from another room")
	# 乙只防、要輸：把乙在這場的氣壓低（測試設定；結果不靠亂數運氣——bot 角色加強過，只防也可能撐到對手失誤）
	var be: Dictionary = b.host().battles.active.get(b.s().battle_id, {})
	if not be.is_empty():
		var bu = b._my_unit(be["battle"])
		if bu != null:
			bu.qi = mini(int(bu.qi), 40)
	if b.drive_battle("defend") != "DEFEAT":
		return fail("B was supposed to lose the ambush")
	b.refill()
	if b.stage_of("q_liu_jinpen_2") != "s_fight":
		return fail("B after defeat at %s, want s_fight" % b.stage_of("q_liu_jinpen_2"))
	info.append("B lost the ambush and stays at s_fight")
	if not b.walk("hn_teahouse") or not a.walk("hn_teahouse"):
		return fail("walk back: %s %s" % [a.err, b.err])
	# 甲對暗語 → 伏擊拉進乙 → 兩人打贏 → 兩人都完成
	for st in ["talk@n_hn_mimike", "choose@n_hn_mimike:n0:c_sun", "choose@n_hn_mimike:n1:c_chan", "choose@n_hn_mimike:n2:c_what"]:
		if not a.do_step(st, "q_liu_jinpen_2", {}):
			return _bot_fail(a)
	var bid: int = a.s().battle_id
	if bid == 0 or b.s().battle_id != bid:
		return fail("party ambush: A battle %d, B battle %d" % [bid, b.s().battle_id])
	a.refill()
	b.refill()
	var t := 0
	while (a.s().battle_id != 0 or b.s().battle_id != 0) and t < 30000:
		a.battle_tick("fight")
		b.battle_tick("fight")
		ws.advance(0.1)
		t += 1
	a.advance(0.5)
	var sa: String = a.stage_of("q_liu_jinpen_2")
	var sb: String = b.stage_of("q_liu_jinpen_2")
	if sa != "s_report" or sb != "s_report":
		return fail("after the party ambush: A %s, B %s (want both s_report; results %s / %s)" % [sa, sb,
			str(a.battle_results.slice(-1)), str(b.battle_results.slice(-1))])
	info.append("party ambush: both completed FIGHT")
	for st in ["walk@hn_island", "talk@n_hn_lulianrong", "choose@n_hn_lulianrong:n0:c_trap", "choose@n_hn_lulianrong:n1:c_next"]:
		if not a.do_step(st, "q_liu_jinpen_2", {}):
			return _bot_fail(a)
	for st in ["walk@hn_island", "talk@n_hn_lulianrong", "choose@n_hn_lulianrong:n0:c_wait",
			"choose@n_hn_lulianrong:n_wait:c_trap2", "choose@n_hn_lulianrong:n1:c_next"]:
		if not b.do_step(st, "q_liu_jinpen_2", {}):
			return _bot_fail(b)
	for o in [a, b]:
		if o.done_entry("q_liu_jinpen_2").is_empty() or not o.active("q_liu_jinpen_2").is_empty():
			return fail("%s did not finish q_liu_jinpen_2" % o.label)
	info.append("both finished q_liu_jinpen_2")
	return err == ""

## 依序執行動作語彙（帶下一步，讓 accept@ 判斷要不要自動走 offer）
func _steps(o, qid: String, list: Array) -> bool:
	for i in list.size():
		if not o.do_step(str(list[i]), qid, {}, str(list[i + 1]) if i + 1 < list.size() else ""):
			return _bot_fail(o)
	return true

func _sees(b, npc: String) -> bool:
	b.flush_view()
	for n in b.view.get("npcs", []):
		if n is Dictionary and str(n.get("id", n.get("npc", ""))) == npc:
			return true
	return false

## 相鄰、走得進去的房間（伏擊時暫時離開用）
func _neighbor(b, room_id: String) -> String:
	for ex in host().index.room(room_id).get("exits", []):
		var to := str(ex.get("to", ""))
		if to != "" and host().regions.lock_reason(b.ch(), to, b._ctx()) == "":
			return to
	return ""

# ======================================================================== 活的江湖
func _ambient() -> bool:
	var w = host().get("wander")
	if w == null:
		return fail("WanderSystem not loaded")
	var p = _new(100, "俠", "xixia")
	if p == null:
		return false
	p.debug("combat_xp", 1000)
	p.debug("morality", 0)
	# ---- 白天：定點、交談即戰
	p.debug("hour", "辰")
	if not p.walk("xx_street"):
		return _bot_fail(p)
	if not _sees(p, "n_yeerniang") or not _sees(p, "n_nanhai"):
		return fail("day: 葉二娘／南海鱷神 not at xx_street (view %s)" % JSON.stringify(p.view.get("npcs", [])))
	if not p.must("talk", { "npc": "n_yeerniang" }):
		return _bot_fail(p)
	if p.s().battle_id != 0:
		return fail("葉二娘 attacked a player with morality 0")
	p.debug("morality", 100)
	if not p.must("talk", { "npc": "n_yeerniang" }) or p.s().battle_id == 0:
		return fail("葉二娘 talk did not start a fight at morality 100")
	if p.drive_battle("flee") != "FLED":
		return fail("could not flee the daytime 葉二娘 fight")
	p.refill()
	if not p.must("talk", { "npc": "n_nanhai" }) or p.s().battle_id == 0:
		return fail("南海鱷神 talk did not start a fight")
	if p.drive_battle("fight") != "VICTORY":
		return fail("could not beat 南海鱷神 in the daytime fight")
	p.refill()
	info.append("day: talk-to-fight ok (葉二娘 only for morality > 0)")
	# ---- 夜裡：警告 → 不動 → 追擊戰（不能逃）
	p.debug("hour", "戌")
	var rows: Dictionary = w.rows()
	var regions: Array = rows.get("w_nanhai", {}).get("schedule", [])[1].get("regions", [])
	var pair := _wild_pair(p, regions)
	if pair.is_empty():
		return fail("no roamable wild room pair near 西夏 for %s" % str(regions))
	var r1: String = pair[0]
	var r2: String = pair[1]
	if not p.walk(r1):
		return _bot_fail(p)
	var prompted := _enter_until_warned(p, "w_nanhai", r1, r2)
	if err != "":
		return false
	if not prompted:
		return fail("南海鱷神 never warned after 20 entries into %s" % r2)
	var c0: int = p.villain_clears.size()
	p.advance(float(ws.options.get("villain_warn_s", 3)) * ws.time_scale + 2.0)
	var bid: int = p.s().battle_id
	if bid == 0:
		return fail("warning ran out but no chase battle started")
	var entry: Dictionary = host().battles.active.get(bid, {})
	if str(entry.get("kind", "")) != "CHASE" and str(entry.get("battle").get("kind") if entry.get("battle") != null else "") != "CHASE":
		info.append("chase battle kind=%s" % str(entry.get("kind", "?")))
	if not bool(entry.get("opts", {}).get("no_flee", false)):
		return fail("chase battle allows fleeing (opts %s)" % str(entry.get("opts", {})))
	var res: String = p.drive_battle("flee")   # 先試逃：不能逃 → 被拒後改打
	if p.flee_rejects == 0:
		return fail("FLEE was never refused in the chase battle")
	if res != "VICTORY":
		return fail("chase battle ended %s" % res)
	var fought := false
	for i in range(c0, p.villain_clears.size()):
		if str(p.villain_clears[i].get("why", "")) == "FOUGHT":
			fought = true
	if not fought:
		return fail("no villain_clear FOUGHT")
	p.refill()
	info.append("night: warned at %s, chase battle no-flee, won" % r2)
	# ---- 警告內離開 → 脫身
	if not p.walk(r1):
		return _bot_fail(p)
	var escaped := false
	if not _enter_until_warned(p, "w_yeerniang", r1, r2):
		return fail("葉二娘 never warned") if err == "" else false
	var c1: int = p.villain_clears.size()
	if p.send("move", { "dir": _dir_to(r2, r1) }).get("ok", false) == false:
		return fail("could not step back to " + r1)
	p.advance(0.5)
	for j in range(c1, p.villain_clears.size()):
		if str(p.villain_clears[j].get("why", "")) == "ESCAPED":
			escaped = true
	if p.s().battle_id != 0:
		var e3: Dictionary = host().battles.active.get(p.s().battle_id, {})
		if str(e3.get("kind", "")) == "CHASE":
			return fail("escaped player was still chased")
		p.clear_battles()
	if not escaped:
		return fail("葉二娘 warning: leaving the room did not give ESCAPED")
	info.append("night: left during the warning → ESCAPED")
	# ---- 新手免疫
	var n = _new(101, "新", "xixia")
	if n == null:
		return false
	n.debug("combat_xp", 0)
	n.debug("hour", "戌")
	if not n.walk(r1):
		return _bot_fail(n)
	for i in 5:
		if n.room() != r1 and not n.walk(r1):
			return _bot_fail(n)
		if not n.debug("wander_place", "w_nanhai:" + r2):
			return _bot_fail(n)
		if not n.send("move", { "dir": _dir_to(r1, r2) }).get("ok", false):
			return fail("newbie move refused")
		var nb: int = n.s().battle_id
		if not n.villain_prompts.is_empty():
			return fail("newbie (combat_xp 0) got a villain warning")
		n.advance(5.0)
		if n.s().battle_id != 0 and nb == 0:
			var e2: Dictionary = host().battles.active.get(n.s().battle_id, {})
			if str(e2.get("kind", "")) == "CHASE":
				return fail("newbie was chased")
		n.clear_battles()
		n.refill()
	info.append("newbie immune")
	# ---- 江湖傳聞列表
	var before: int = p.events.size()
	if not p.must("rumor_list"):
		return _bot_fail(p)
	var got := false
	for i in range(before, p.events.size()):
		if str(p.events[i].get("key", "")) == "rumor_list":
			got = true
			info.append("rumor_list items=%d" % (p.events[i].get("p", {}).get("items", []) as Array).size())
	if not got:
		return fail("no rumor_list event")
	var villain_rumor := false
	for r in p.rumors:
		if str(r.get("kind", "")) == "VILLAIN":
			villain_rumor = true
	info.append("villain rumor=%s" % str(villain_rumor))
	return err == ""

## 把惡人放在 r2、從 r1 走進去，直到收到警告而且沒有同時踩到地雷（踩到地雷時警告會被戰鬥取消並記冷卻：
## 清掉冷卻再試；出手機率 chance_pct 也可能擲不中）。回傳是否拿到一個還在倒數的警告
func _enter_until_warned(p, wid: String, r1: String, r2: String) -> bool:
	var w = host().get("wander")
	for i in 25:
		if p.room() != r1 and not p.walk(r1):
			return _bot_fail(p)
		w.clear_cooldown(wid, p.char_id)
		if not p.debug("wander_place", "%s:%s" % [wid, r2]):
			return _bot_fail(p)
		if not p.send("move", { "dir": _dir_to(r1, r2) }).get("ok", false):
			return fail("move %s -> %s refused" % [r1, r2])
		p.advance(0.1)
		if p.s().battle_id == 0 and not w.pending_prompt(p.peer).is_empty():
			return true
		p.clear_battles()
		p.refill()
	return false

func _dir_to(from: String, to: String) -> String:
	for ex in host().index.room(from).get("exits", []):
		if str(ex.get("to", "")) == to:
			return str(ex.get("dir", ""))
	return ""

## 西夏附近、惡人可遊蕩的兩間相鄰野外房間（都不是安全房間）
func _wild_pair(p, regions: Array) -> Array:
	var w = host().get("wander")
	var start: String = p.room()
	var seen := { start: true }
	var q: Array = [start]
	var i := 0
	while i < q.size() and i < 4000:
		var r: String = q[i]
		i += 1
		if w.roam_ok(r, regions) and not w.is_safe_room(r):
			for ex in host().index.room(r).get("exits", []):
				var to := str(ex.get("to", ""))
				if to != "" and w.roam_ok(to, regions) and not w.is_safe_room(to):
					return [r, to]
		for ex in host().index.room(r).get("exits", []):
			var to2 := str(ex.get("to", ""))
			if to2 != "" and not seen.has(to2):
				seen[to2] = true
				q.append(to2)
	return []
