extends "res://tests/unit/test_world_fixture.gd"
## M3D_PLAN §5.3.2、§5.3.5–5.3.6、§10.1（WP-EVENTS）：比武排程（日曆、主機開辦）、報名、點名 3 次判負、
## 名次與獎勵（名聲、稱號、盟主令牌）、全服傳聞、表演賽（< 4 人、30 遊戲日獎勵冷卻）、稱號在下一屆收回、叛派收回門派稱號。

var peers: Array = []

func before_each() -> void:
	world_name = "w_m3d_tourney"
	super.before_each()
	peers = []

func _sys():
	return host().get("tourney")

func _setup(n_remote: int, sect := "") -> bool:
	if not game_ok() or _sys() == null:
		fail("TourneySystem 沒有載入")
		return false
	ws.options["wait_mode"] = false
	if make_char("盟主候補") == null:
		return false
	make_strong()
	if sect != "":
		ch().sect = sect
	_qualify(ch())
	goto(TourneyRules.REST_ROOM)
	for i in n_remote:
		var p := add_player("參賽%s" % ["甲", "乙", "丙", "丁", "戊", "己", "庚"][i])
		goto_as(p, TourneyRules.REST_ROOM)
		if sect != "":
			session_of(p).character.sect = sect
		_qualify(session_of(p).character)
		peers.append(p)
	return true

## M3d 審查：報名條件（實戰、善惡、門技、PK值 0）——測試角色一律合格
func _qualify(c) -> void:
	c.combat_xp = maxi(int(c.combat_xp), 20000)
	c.morality = maxi(int(c.morality), 300)
	for sid in ["hengshan", "quanzhen"]:
		var ss := str(tables().get("sects", {}).get(sid, {}).get("sect_skill", ""))
		if ss != "":
			c.skills.set_level(ss, 40, tables())

## 比賽中選手被帶上擂臺；再報名要回休息區找報名員
func _back_to_rest() -> void:
	goto(TourneyRules.REST_ROOM)
	for p in peers:
		goto_as(p, TourneyRules.REST_ROOM)

func _signup_all(kind: String) -> void:
	_back_to_rest()
	assert_true(send("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": kind }).get("ok", false), "本機報名")
	for p in peers:
		var r := send_as(p, "tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": kind })
		assert_true(r.get("ok", false), "peer %d 報名：%s" % [p, str(r)])

## 跑到這種比賽結束：進行中的 DUEL 一律讓 side 0（先列的那位）擊倒獲勝；沒在打就推進時間（點名）
func _run_to_end(kind: String, max_steps := 400) -> void:
	for i in max_steps:
		var ev: Dictionary = _sys().event_of(kind)
		if ev.is_empty():
			return
		var m: Dictionary = ev.get("match", {})
		var bid := int(m.get("bid", 0))
		if bid != 0 and host().battles.active.has(bid):
			var b = host().battles.active[bid]["battle"]
			b.ev_end(0, "KO")
			ws.advance(0.2)
			continue
		ws.advance(5.0)
	fail("比賽沒有在 %d 步內結束" % max_steps)

func test_calendar_rules() -> void:
	var sects := ["shaolin", "gumu", "quanzhen"]
	# 第 8 日起可報名武林大會，第 15 日午時開打
	var o := TourneyRules.calendar_open(8, 0, sects)
	var w := o.filter(func(x): return str(x.kind) == "WULIN")
	assert_eq(w.size(), 1, "第 8 日開放武林大會報名")
	assert_eq(int(w[0].start_day), 15)
	assert_eq(int(w[0].shichen), 6, "午時")
	assert_true(TourneyRules.calendar_open(7, 11, sects).filter(func(x): return str(x.kind) == "WULIN").is_empty(), "第 7 日還沒開")
	assert_true(TourneyRules.calendar_open(15, 6, sects).filter(func(x): return str(x.kind) == "WULIN").is_empty(), "開打時刻就不再報名")
	# 門派比武：上個月 24 日起報名，下個月 1／2 日開打
	var o2 := TourneyRules.calendar_open(24, 0, sects)
	var sl := o2.filter(func(x): return str(x.kind) == "SECT:shaolin")
	assert_eq(sl.size(), 1)
	assert_eq(int(sl[0].start_day), 32, "少林：下個月第 2 日")
	assert_eq(int(sl[0].shichen), 5, "巳時")
	var gm := o2.filter(func(x): return str(x.kind) == "SECT:gumu")
	assert_eq(int(gm[0].start_day), 31, "古墓：下個月第 1 日")
	assert_eq(int(gm[0].shichen), 6, "午時")
	assert_true(TourneyRules.calendar_open(31, 7, sects).filter(func(x): return str(x.kind) == "SECT:gumu").is_empty(), "古墓開打後不再報名")
	assert_eq(TourneyRules.calendar_open(31, 7, sects).filter(func(x): return str(x.kind) == "SECT:shaolin").size(), 1,
		"少林在第 2 日，第 1 日還能報名")
	# world_s_at 是 WorldClock 的反函數
	for d in [1, 15, 32, 365]:
		for sh in [0, 5, 6, 11]:
			var t := TourneyRules.world_s_at(d, sh, 7200.0)
			if t < 0.0:
				continue
			var c := WorldClock.clock(t + 1.0, 7200.0)
			assert_eq(int(c.day), d, "day %d sh %d" % [d, sh])
			assert_eq(int(c.shichen_idx), sh)

func test_calendar_opens_signup_in_world() -> void:
	if not _setup(0):
		return
	# 撥到第 8 日辰時
	var day_s := float(ws.options.get("game_day_real_s", 7200))
	ws.world["world_time_s"] = TourneyRules.world_s_at(8, 4, day_s) + 1.0
	ws.advance(1.0)
	var ev: Dictionary = _sys().event_of("WULIN")
	assert_false(ev.is_empty(), "日曆開了武林大會的報名")
	assert_eq(str(ev.get("source", "")), "CALENDAR")
	assert_true(absf(float(ev.start_s) - TourneyRules.world_s_at(15, 6, day_s)) < 0.01, "第 15 日午時開打")
	assert_false(last("ev_tourney_open").is_empty(), "全服通知開放報名")
	ws.options["tourney_enabled"] = false
	assert_eq(reason("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "WULIN" }), "tourney_disabled")
	ws.options["tourney_enabled"] = true
	assert_true(send("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "WULIN" }).get("ok", false))
	assert_eq(reason("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "WULIN" }), "tourney_signed")
	assert_true(send("tourney_withdraw").get("ok", false), "退出報名")
	assert_eq(reason("tourney_withdraw"), "tourney_closed", "沒有報名中的比武")

func test_host_open_and_permissions() -> void:
	if not _setup(1):
		return
	assert_eq(reason_as(peers[0], "tourney_host", { "kind": "WULIN" }), "not_admin", "只有主機或管理者")
	assert_eq(reason("tourney_host", { "kind": "SECT:nobody" }), "bad_value:kind")
	assert_true(send("tourney_host", { "kind": "WULIN", "signup_s": 60 }).get("ok", false), "主機開辦")
	assert_eq(reason("tourney_host", { "kind": "WULIN" }), "tourney_running", "同種比賽已經有一場")
	ws.options["tourney_enabled"] = false
	assert_eq(reason("tourney_host", { "kind": "SECT:shaolin" }), "tourney_disabled")
	ws.options["tourney_enabled"] = true
	# 門派比武只收本派
	assert_true(send("tourney_host", { "kind": "SECT:shaolin", "signup_s": 60 }).get("ok", false))
	assert_eq(reason("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "SECT:shaolin" }), "tourney_not_eligible")
	ch().sect = "shaolin"
	assert_true(send("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "SECT" }).get("ok", false), "SECT＝自己的門派")
	assert_eq(reason("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "SECT:wudang" }), "tourney_closed")
	# 報名要在報名員面前
	goto("xx_square")
	assert_eq(reason("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "WULIN" }), "not_here")
	# tourney_info
	goto(TourneyRules.REST_ROOM)
	assert_true(send("tourney_info").get("ok", false))
	var st := lastp("tourney_state")
	assert_false(st.is_empty(), "tourney_state（ui）")
	assert_has(st.get("signed", []), "SECT:shaolin")

func test_wulin_full_run_rewards_and_exhibition() -> void:
	if not _setup(4):
		return
	assert_true(send("tourney_host", { "kind": "WULIN", "signup_s": 60 }).get("ok", false))
	_signup_all("WULIN")
	# 一位不在場（被點名 3 次判負）
	var absent: int = peers[3]
	goto_as(absent, "xx_square")
	var names := { str(ch().id): str(ch().name) }
	var fame0 := { str(ch().id): int(ch().fame) }
	var dead0 := { str(ch().id): int(ch().dead_count) }
	for p in peers:
		var c = session_of(p).character
		names[str(c.id)] = str(c.name)
		fame0[str(c.id)] = int(c.fame)
		dead0[str(c.id)] = int(c.dead_count)
	ws.advance(61.0)
	var ev: Dictionary = _sys().event_of("WULIN")
	assert_eq(str(ev.get("phase", "")), "RUNNING", "到點開打")
	assert_false(bool(ev.get("exhibition", true)), "5 人、從沒發過 → 正式比賽")
	var byes := 0
	for m in ev["rounds"][0]:
		if str(m.a) == "" or str(m.b) == "":
			byes += 1
	assert_eq(byes, 3, "5 人 → 輪空 3")
	var absent_name: String = session_of(absent).character.name
	_run_to_end("WULIN")
	assert_true(_sys().event_of("WULIN").is_empty(), "比完了")
	# 點名
	var calls := 0
	for e in evs("ev_tourney_call"):
		if str(e.p.get("name", "")) == absent_name:
			calls = maxi(calls, int(e.p.get("n", 0)))
	assert_eq(calls, 3, "不在場的人被點名 3 次")
	var forfeits := evs("ev_tourney_forfeit").filter(func(e): return str(e.p.get("name", "")) == absent_name)
	assert_false(forfeits.is_empty(), "3 次不到判負")
	# 結果
	var hist: Array = _sys().state()["history"]
	assert_eq(hist.size(), 1)
	var h: Dictionary = hist[0]
	var champ_name := str(h.get("champion", ""))
	assert_true(champ_name != "", "有冠軍")
	var champ_id := ""
	for cid in names:
		if names[cid] == champ_name:
			champ_id = cid
	var champ = host().session_for_char(champ_id).character
	assert_eq(int(champ.fame) - int(fame0[champ_id]), 3000, "冠軍名聲 +3000")
	assert_has(_sys().titles_of(champ), "武林盟主", "冠軍稱號")
	assert_eq(int(champ.inventory.count("i_ev_mengzhu_ling")), 1, "盟主令牌")
	var tags: Dictionary = _sys().player_tags(s(), host().session_for_char(champ_id))
	assert_has(tags.get("tags", []), "盟主", "頭上「盟主」")
	var places: Array = h.get("places", [])
	var runner := ""
	for p in places:
		if int(p.place) == 2:
			runner = str(p.name)
	for cid in names:
		if names[cid] == runner:
			assert_eq(int(host().session_for_char(cid).character.fame) - int(fame0[cid]), 2000, "亞軍 +2000")
	for cid in names:
		assert_eq(int(host().session_for_char(cid).character.dead_count), int(dead0[cid]), "沒有死亡懲罰：%s" % names[cid])
	# 全服傳聞
	var heard := false
	if host().get("rumor") != null:
		for r in host().rumor.recent(10):
			if str(r.get("text_key", "")) == "rmr_ev_tourney_champion":
				heard = true
	for e in evs("rumor"):
		if str(e.p.get("text_key", e.p.get("key", ""))) == "rmr_ev_tourney_champion":
			heard = true
	if not heard:
		heard = not evs("rmr_ev_tourney_champion").is_empty()
	assert_true(heard, "全服傳聞：奪魁")
	assert_eq(int(_sys().state()["last_reward_day"].get("WULIN", -1)), int(host().clock().day), "記下發獎日")
	# 馬上再開一次 → 表演賽（30 遊戲日冷卻）（M3d 審查第三輪：表演賽不收回上一屆的稱號與令牌）
	goto_as(absent, TourneyRules.REST_ROOM)
	assert_true(send("tourney_host", { "kind": "WULIN", "signup_s": 30 }).get("ok", false))
	_signup_all("WULIN")
	var fame1 := {}
	for cid in names:
		fame1[cid] = int(host().session_for_char(cid).character.fame)
	ws.advance(31.0)
	var ev2: Dictionary = _sys().event_of("WULIN")
	assert_true(bool(ev2.get("exhibition", false)), "冷卻內 → 表演賽")
	# M3d 審查第三輪：表演賽不收回上一屆的稱號與令牌（正式的下一屆才收回；見 test_m3d_review3）
	assert_true(_sys().titles_of(champ).has("武林盟主"), "表演賽開打 → 盟主稱號還在")
	assert_eq(int(champ.inventory.count("i_ev_mengzhu_ling")), 1, "盟主令牌還在")
	# 上屆冠軍在下半區的種子位
	var slot: int = (ev2["rounds"][0] as Array).size() / 2
	assert_eq(str(ev2["rounds"][0][slot].a), champ_id, "上屆冠軍放在下半區種子位")
	_run_to_end("WULIN")
	for cid in names:
		assert_eq(int(host().session_for_char(cid).character.fame), int(fame1[cid]), "表演賽不發名聲")
	assert_eq(str(_sys().state()["champions"].get("WULIN", "")), champ_id, "表演賽的冠軍不改種子")
	assert_true(_sys().titles_of(champ).has("武林盟主"), "表演賽打完，盟主還是上一屆的")

func test_small_field_exhibition_and_cancel() -> void:
	if not _setup(2):
		return
	assert_true(send("tourney_host", { "kind": "WULIN", "signup_s": 30 }).get("ok", false))
	_signup_all("WULIN")
	ws.advance(31.0)
	assert_true(bool(_sys().event_of("WULIN").get("exhibition", false)), "3 人 → 表演賽")
	_run_to_end("WULIN")
	assert_eq(int(_sys().state()["last_reward_day"].get("WULIN", -1)), -1, "表演賽不記發獎日")
	assert_true(_sys().titles_of(ch()).is_empty(), "表演賽不發稱號")
	# 只有 1 人 → 取消
	assert_true(send("tourney_host", { "kind": "WULIN", "signup_s": 30 }).get("ok", false), "再開一場")
	_back_to_rest()
	assert_true(send("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "WULIN" }).get("ok", false), "一個人報名")
	ws.advance(31.0)
	assert_true(_sys().event_of("WULIN").is_empty(), "不到 2 人 → 取消")
	assert_false(last("ev_tourney_cancelled").is_empty(), "ev_tourney_cancelled")

func test_sect_tourney_titles() -> void:
	if not _setup(3, "shaolin"):
		return
	assert_true(send("tourney_host", { "kind": "SECT:shaolin", "signup_s": 30 }).get("ok", false))
	_signup_all("SECT")
	var before := {}
	for p in [1] + peers:
		var c = session_of(p).character
		before[str(c.id)] = [int(c.fame), int(c.lilian)]
	ws.advance(31.0)
	_run_to_end("SECT:shaolin")
	var h: Dictionary = _sys().state()["history"][0]
	var champ = null
	for p in [1] + peers:
		var c = session_of(p).character
		if str(c.name) == str(h.champion):
			champ = c
	assert_true(champ != null, "有冠軍")
	if champ == null:
		return
	assert_has(_sys().titles_of(champ), "少林派掌門師兄", "少林冠軍稱號")
	assert_eq(int(champ.fame) - int(before[str(champ.id)][0]), 1000, "名聲 +1000")
	assert_eq(int(champ.lilian) - int(before[str(champ.id)][1]), 800, "歷練 +800")
	assert_eq(int(champ.inventory.count("i_ev_mengzhu_ling")), 0, "門派比武沒有令牌")
	var tags: Dictionary = _sys().player_tags(s(), host().session_for_char(str(champ.id)))
	assert_has(tags.get("tags", []), "少林派掌門師兄", "頭上顯示門派稱號")
	var sf: Dictionary = _sys().sheet_fields(host().session_for_char(str(champ.id)))
	assert_has(sf.get("titles", []), "少林派掌門師兄", "角色表 titles")
	# 叛派 → 門派稱號收回
	champ.sect = ""
	assert_false(_sys().titles_of(champ).has("少林派掌門師兄"), "叛派收回")

func test_quanzhen_rank_titles() -> void:
	if not _setup(3, "quanzhen"):
		return
	assert_true(send("tourney_host", { "kind": "SECT:quanzhen", "signup_s": 30 }).get("ok", false))
	_signup_all("SECT")
	ws.advance(31.0)
	_run_to_end("SECT:quanzhen")
	var all_titles: Array = []
	for p in [1] + peers:
		all_titles.append_array(_sys().titles_of(session_of(p).character))
	assert_has(all_titles, "全真派天樞真人")
	assert_has(all_titles, "天璇真人", "亞軍天璇")
	assert_has(all_titles, "天璣真人", "四強依報名先後天璣、天權")
	assert_has(all_titles, "天權真人")

## M3d 審查（第 3 輪）：報名條件——武林大會實戰 1 萬、PK值 0；門派比武實戰 1000（恆山、全真另有善惡、門技；恆山、少林 PK值 0）
func test_entry_requirements_pure() -> void:
	var ok_w := { "sect": "", "combat_xp": 10000, "pk": 0, "morality": 0, "sect_skill": 0 }
	assert_eq(TourneyRules.entry_reason("WULIN", ok_w), "")
	assert_eq(TourneyRules.entry_reason("WULIN", { "combat_xp": 0 }), "tourney_need_xp", "全新角色不能報武林大會")
	assert_eq(TourneyRules.entry_reason("WULIN", { "combat_xp": 50000, "pk": 1 }), "tourney_has_pk")
	assert_eq(TourneyRules.entry_reason("SECT:wudang", { "sect": "wudang", "combat_xp": 999 }), "tourney_need_xp")
	assert_eq(TourneyRules.entry_reason("SECT:wudang", { "sect": "wudang", "combat_xp": 1000, "pk": 3 }), "", "其他派不看 PK值")
	assert_eq(TourneyRules.entry_reason("SECT:wudang", { "sect": "emei", "combat_xp": 99999 }), "tourney_not_eligible")
	assert_eq(TourneyRules.entry_reason("SECT:shaolin", { "sect": "shaolin", "combat_xp": 5000, "pk": 1 }), "tourney_has_pk")
	assert_eq(TourneyRules.entry_reason("SECT:hengshan", { "sect": "hengshan", "combat_xp": 4000, "morality": 199, "sect_skill": 10 }), "tourney_need_morality")
	assert_eq(TourneyRules.entry_reason("SECT:quanzhen", { "sect": "quanzhen", "combat_xp": 4000, "morality": 200, "sect_skill": 29 }), "tourney_need_sect_skill")
	assert_eq(TourneyRules.entry_reason("SECT:quanzhen", { "sect": "quanzhen", "combat_xp": 4000, "morality": 200, "sect_skill": 30 }), "")
	assert_true(TourneyRules.entry_text("WULIN").contains("沒有 PK值"))

func test_entry_requirements_in_world() -> void:
	if not _setup(0):
		return
	ok("tourney_host", { "kind": "WULIN", "signup_s": 60 })
	ch().combat_xp = 9999
	assert_eq(reason("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "WULIN" }), "tourney_need_xp", "實戰不到一萬")
	ch().combat_xp = 10000
	ch().pk = 2
	ch().pk_stamp_s = ch().online_s
	assert_eq(reason("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "WULIN" }), "tourney_has_pk", "有 PK值")
	ch().pk = 0
	assert_true(send("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "WULIN" }).get("ok", false))

## 報名後叛派（門派比武）→ 點名時當作棄權，不會打、也不會拿冠軍獎勵
func test_left_sect_after_signup_forfeits() -> void:
	if not _setup(3, "shaolin"):
		return
	ok("tourney_host", { "kind": "SECT:shaolin", "signup_s": 30 })
	_signup_all("SECT:shaolin")
	var quitter = session_of(peers[0]).character
	quitter.sect = ""
	var f0 := int(quitter.fame)
	ws.advance(31.0)
	var ev: Dictionary = _sys().event_of("SECT:shaolin")
	assert_false(ev.is_empty(), "開打了")
	if ev.is_empty():
		return
	var eid := str(ev.get("id", ""))
	assert_has(ev.get("withdrawn", []), str(quitter.id), "開打時重查：已不是少林弟子 → 當作棄權")
	# 跑到這一場結束（之後日曆可能又開一場同種的，不等那一場）
	for i in 400:
		var cur: Dictionary = _sys().event_of("SECT:shaolin")
		if cur.is_empty() or str(cur.get("id", "")) != eid:
			break
		var bid := int((cur.get("match", {}) as Dictionary).get("bid", 0))
		if bid != 0 and host().battles.active.has(bid):
			host().battles.active[bid]["battle"].ev_end(0, "KO")
			ws.advance(0.2)
			continue
		ws.advance(5.0)
	assert_eq(int(quitter.fame), f0, "叛派的人拿不到門派比武獎勵")
	assert_false(evs_for(peers[0], "ev_tourney_disqualified").is_empty(), "通知本人")

## 比武打到一半不能送 tourney_withdraw（CI）：要棄權就逃
func test_withdraw_blocked_mid_duel() -> void:
	if not _setup(1):
		return
	ok("tourney_host", { "kind": "WULIN", "signup_s": 30 })
	_signup_all("WULIN")
	ws.advance(31.0)
	for i in 40:
		if s().battle_id != 0:
			break
		ws.advance(1.0)
	if s().battle_id == 0:
		fail("沒有開打")
		return
	assert_eq(reason("tourney_withdraw"), "in_battle", "比武中不能退出（要棄權就逃）")

# ------------------------------------------------------------------ M3d 審查第三輪
## 進行中的那一場，名次改成 rounds（ids：報名順序的 char_id）後直接結算
func _force_finish(kind: String, rounds: Array) -> Dictionary:
	var ev: Dictionary = _sys().event_of(kind)
	# 先停住這一場（不是 RUNNING → step 不再推進），把已經開打的比武結束掉
	ev["phase"] = "HOLD"
	for bid in host().battles.active.keys():
		var act: Dictionary = host().battles.active[bid]
		if str(act.get("opts", {}).get("tourney", "")) == str(ev.get("id", "")):
			act["battle"].ev_end(0, "KO")
	ws.advance(0.5)
	ev["rounds"] = rounds
	ev["round"] = rounds.size() - 1
	ev["match"] = {}
	_sys()._finish(ev)
	return ev

func _ids_by_order(kind: String) -> Array:
	var ev: Dictionary = _sys().event_of(kind)
	var out: Array = []
	for e in ev.get("entrants", []):
		out.append(str(e.get("char_id", "")))
	return out

func _fame_of(cid: String) -> int:
	return int(host().session_for_char(cid).character.fame)

## 決賽兩人都沒到（沒有冠軍）：名聲照名次查（兩位決賽者同為第 2 名 → 取較低的那格 1200），不會有人拿冠軍的 3000；
## 正式比賽一樣開始發獎冷卻；沒有盟主稱號
func test_final_no_winner_pays_by_place_and_starts_cooldown() -> void:
	if not _setup(3):
		return
	ok("tourney_host", { "kind": "WULIN", "signup_s": 30 })
	_signup_all("WULIN")
	ws.advance(31.0)
	var ev: Dictionary = _sys().event_of("WULIN")
	assert_false(bool(ev.get("exhibition", true)), "4 人、從沒發過 → 正式比賽")
	var ids := _ids_by_order("WULIN")
	assert_eq(ids.size(), 4)
	var f0 := {}
	for cid in ids:
		f0[cid] = _fame_of(cid)
	var a: String = ids[0]
	var b: String = ids[1]
	var c: String = ids[2]
	var d: String = ids[3]
	_force_finish("WULIN", [
		[{ "a": a, "b": b, "winner": a, "done": true, "how": "KO" }, { "a": c, "b": d, "winner": c, "done": true, "how": "KO" }],
		[{ "a": a, "b": c, "winner": "", "done": true, "how": "FORFEIT" }]])
	for cid in ids:
		assert_eq(_fame_of(cid) - int(f0[cid]), 1200, "%s：沒有冠軍時每人都拿 1200（不是照名單位置拿 3000／2000）" % cid)
		assert_false(_sys().titles_of(host().session_for_char(cid).character).has(TourneyRules.WULIN_TITLE), "沒有冠軍 → 沒有盟主")
	var st: Dictionary = _sys().state()
	assert_eq(int(st["last_reward_day"].get("WULIN", -1)), int(host().clock().day), "沒有冠軍也開始遊戲日冷卻")
	assert_true(float(st["last_reward_unix"].get("WULIN", -1.0)) > 0.0, "沒有冠軍也開始現實日冷卻")
	assert_false(st["champions"].has("WULIN"), "沒有冠軍 → 種子不變")
	# 馬上再開 → 表演賽
	_back_to_rest()
	ok("tourney_host", { "kind": "WULIN", "signup_s": 30 })
	_signup_all("WULIN")
	ws.advance(31.0)
	assert_true(bool(_sys().event_of("WULIN").get("exhibition", false)), "冷卻中 → 表演賽")

## 全真門派比武沒有冠軍：天璇…照名次，不會有人拿到「全真派天樞真人」
func test_sect_no_winner_titles_by_place() -> void:
	if not _setup(3, "quanzhen"):
		return
	ok("tourney_host", { "kind": "SECT:quanzhen", "signup_s": 30 })
	_signup_all("SECT:quanzhen")
	ws.advance(31.0)
	var ids := _ids_by_order("SECT:quanzhen")
	assert_eq(ids.size(), 4)
	var a: String = ids[0]
	var b: String = ids[1]
	var c: String = ids[2]
	var d: String = ids[3]
	_force_finish("SECT:quanzhen", [
		[{ "a": a, "b": b, "winner": a, "done": true, "how": "KO" }, { "a": c, "b": d, "winner": c, "done": true, "how": "KO" }],
		[{ "a": a, "b": c, "winner": "", "done": true, "how": "FORFEIT" }]])
	var all_titles: Array = []
	for cid in ids:
		all_titles.append_array(_sys().titles_of(host().session_for_char(cid).character))
	assert_false(all_titles.has(TourneyRules.SECT_TITLES["quanzhen"]), "沒有冠軍 → 沒有天樞真人：%s" % str(all_titles))
	assert_has(all_titles, "天璇真人", "第 2 名（第一位決賽者）天璇")

## 表演賽開打不收回上一屆的稱號與令牌；開打時就被取消資格的人不算人數（4 報 2 有了 PK值 → 表演賽）；
## 下一場正式的才收回（用武林大會：門派比武在第 1 日會被日曆再開一場）
func test_exhibition_keeps_title_and_disqualified_not_counted() -> void:
	if not _setup(3):
		return
	ok("tourney_host", { "kind": "WULIN", "signup_s": 30 })
	_signup_all("WULIN")
	var q1 = session_of(peers[0]).character
	var q2 = session_of(peers[1]).character
	for q in [q1, q2]:
		q.pk = 1
		q.pk_stamp_s = q.online_s
	ws.advance(31.0)
	var ev: Dictionary = _sys().event_of("WULIN")
	assert_false(ev.is_empty(), "開打了")
	assert_true(bool(ev.get("exhibition", false)), "4 人報名但 2 人開打時有了 PK值 → 只剩 2 人 → 表演賽")
	_run_to_end("WULIN")
	# 正式的一場：4 人 → 冠軍拿到稱號
	for q in [q1, q2]:
		q.pk = 0
	_back_to_rest()
	ok("tourney_host", { "kind": "WULIN", "signup_s": 30 })
	_signup_all("WULIN")
	ws.advance(31.0)
	assert_false(bool(_sys().event_of("WULIN").get("exhibition", true)), "4 人 → 正式")
	_run_to_end("WULIN")
	var champ_id := str(_sys().state()["champions"].get("WULIN", ""))
	assert_true(champ_id != "" and host().session_for_char(champ_id) != null, "有冠軍")
	if champ_id == "" or host().session_for_char(champ_id) == null:
		return
	var champ = host().session_for_char(champ_id).character
	assert_has(_sys().titles_of(champ), TourneyRules.WULIN_TITLE)
	# 冷卻中再開 → 表演賽：稱號、令牌留著、種子不換
	_back_to_rest()
	ok("tourney_host", { "kind": "WULIN", "signup_s": 30 })
	_signup_all("WULIN")
	ws.advance(31.0)
	assert_true(bool(_sys().event_of("WULIN").get("exhibition", false)), "冷卻中 → 表演賽")
	assert_has(_sys().titles_of(champ), TourneyRules.WULIN_TITLE, "表演賽開打不收回稱號")
	assert_eq(int(champ.inventory.count(TourneyRules.TOKEN_ITEM)), 1, "表演賽開打不收回令牌")
	_run_to_end("WULIN")
	assert_eq(str(_sys().state()["champions"].get("WULIN", "")), champ_id, "表演賽冠軍不改種子")
	assert_has(_sys().titles_of(champ), TourneyRules.WULIN_TITLE, "表演賽打完稱號還在")
	# 冷卻過了的正式比賽 → 開打時收回
	_sys().state()["last_reward_day"]["WULIN"] = -1
	_sys().state()["last_reward_unix"]["WULIN"] = -1.0
	_back_to_rest()
	ok("tourney_host", { "kind": "WULIN", "signup_s": 30 })
	_signup_all("WULIN")
	ws.advance(31.0)
	assert_false(bool(_sys().event_of("WULIN").get("exhibition", true)), "冷卻過了 → 正式")
	assert_false(_sys().titles_of(champ).has(TourneyRules.WULIN_TITLE), "正式的下一屆開打 → 收回")
	assert_eq(int(champ.inventory.count(TourneyRules.TOKEN_ITEM)), 0, "令牌收回")

## 規則 later_events 關（classic_strict）：沒有門派比武與武林大會（日曆不開、主機開辦也不行）
func test_strict_rules_no_tourney() -> void:
	if not _setup(0):
		return
	GameData.rules["later_events"] = false
	assert_false(_sys().enabled(), "later_events 關 → 比武關")
	assert_eq(reason("tourney_host", { "kind": "WULIN", "signup_s": 30 }), "tourney_disabled")
	assert_eq(reason("tourney_signup", { "npc": TourneyRules.CLERK_NPC, "kind": "WULIN" }), "tourney_disabled")
	# 日曆撥到武林大會、門派比武的報名日也不開
	var day_s := float(ws.options.get("game_day_real_s", 7200))
	for d in [8, 24]:
		ws.world["world_time_s"] = TourneyRules.world_s_at(d, 4, day_s) + 1.0
		ws.advance(1.0)
		assert_true(_sys().current().is_empty(), "第 %d 日：沒有比武開報名" % d)
	GameData.rules["later_events"] = true
	assert_true(_sys().enabled())
