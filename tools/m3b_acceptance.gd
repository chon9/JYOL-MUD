extends SceneTree
## M3b 驗收（M3B_PLAN §11.3）。
##   godot --headless --path . --script res://tools/m3b_acceptance.gd -- --no-steam [--only=gaibang[,bank]] [--workers=4] [--timeout=2400]
## 劇本：jingcheng_walk gaibang capital_jail escort bank org craft jueqinggu story era_1_0a（§11.3 表）。
##
## 作法（照 tools/story_acceptance.gd）：協調器（本檔，不帶 --m3b-worker）每個劇本開一個 worker 子行程（同一個檔案帶
## --m3b-worker）；worker 在自己的行程裡開真的主機（WorldServer＋GameHost、全部系統、--debug-intents），玩家是假的遠端
## 連線（tests/bots/m3b_bot.gd，延伸故事驗收 bot），一切動作經 handle_intent；要「重開主機」的劇本照故事驗收的
## 存檔 → 關主機 → 同世界重開 → 重新選角。每個劇本用全新世界（era_1_0a 的 worker 帶 --eras=1.0A）。
## debug_set 只用來設屬性、實戰、銀兩、名聲、歷練、技能等級、時辰快轉；路一律用走的（teleport 不用）。
## 成功印 M3B_ACCEPT_OK（結束碼 0）；失敗印 M3B_ACCEPT_FAIL <劇本> <原因> 並傾印 log 尾端（結束碼 1）。
## log 與世界在 <測試根目錄>/m3b_acceptance/<run>/；不論成敗所有子程序 OS.kill()。不碰擁有者存檔、不寫 C:。

const BOT := "res://tests/bots/m3b_bot.gd"
const SCENARIOS := ["jingcheng_walk", "gaibang", "capital_jail", "escort", "bank", "org", "craft", "jueqinggu", "story",
	"era_1_0a"]

var _finished := false
var _timeout_s := 2400.0
var _root := ""
var _run_id := ""
var _dir := ""
var _pids: Array[int] = []
var _logs: Dictionary = {}
var _t0 := 0
var _bots: Dictionary = {}     # worker：peer -> bot
var _next_peer := 100

func _initialize() -> void:
	_run.call_deferred()

func _finalize() -> void:
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()

func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var i := a.find("=")
			if i > 0:
				out[a.substr(2, i - 2)] = a.substr(i + 1)
			else:
				out[a.substr(2)] = "true"
	return out

func _run() -> void:
	_t0 = Time.get_ticks_msec()
	var a := _args()
	_timeout_s = maxf(60.0, str(a.get("timeout", "2400")).to_float())
	_root = DataRoot.resolve_for_tool(CliArgs.current())
	if a.has("m3b-worker"):
		await _worker(a)
	else:
		await _coordinate(a)

func _say(msg: String) -> void:
	print("[m3b_acceptance %6.1fs] %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, msg])

# ======================================================================== 協調器
func _coordinate(a: Dictionary) -> void:
	randomize()
	_run_id = "%04x" % (randi() % 0x10000)
	_dir = ProjectSettings.globalize_path(_root.path_join("m3b_acceptance/%s" % _run_id))
	DirAccess.make_dir_recursive_absolute(_dir)
	var jobs: Array = SCENARIOS.duplicate()
	if a.has("only"):
		jobs = []
		for j in str(a["only"]).split(",", false):
			if not (j in SCENARIOS):
				_fail_out("? unknown scenario " + j)
				return
			jobs.append(j)
	var n_workers := clampi(int(str(a.get("workers", "4"))), 1, 10)
	_say("run=%s dir=%s scenarios=%s workers<=%d" % [_run_id, _dir, ",".join(jobs), n_workers])
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var queue: Array = jobs.duplicate()
	var running: Dictionary = {}
	var results: Dictionary = {}
	var deadline := Time.get_ticks_msec() + int(_timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		while not queue.is_empty() and running.size() < n_workers:
			var job: String = queue.pop_front()
			var log_path := _dir.path_join(job + ".log")
			_logs[job] = log_path
			var args := PackedStringArray(["--headless", "--path", proj, "--log-file", log_path, "--script",
				"res://tools/m3b_acceptance.gd", "--", "--no-steam", "--debug-intents", "--m3b-worker",
				"--m3b-run=%s" % _run_id, "--job=" + job, DataRoot.child_arg(_root)])
			if job == "era_1_0a":
				args.append("--eras=1.0A")
			var pid := OS.create_process(exe, args, false)
			if pid <= 0:
				_fail_out("%s spawn failed" % job)
				return
			_pids.append(pid)
			running[job] = pid
			_say("spawned %s pid=%d" % [job, pid])
		await create_timer(0.5, true, false, true).timeout
		for job in running.keys():
			var wpid: int = running[job]
			if OS.is_process_running(wpid):
				continue
			running.erase(job)
			var txt := _log_text(job)
			for line in txt.split("\n"):
				if line.begins_with("M3B_JOB_OK ") or line.begins_with("M3B_JOB_FAIL "):
					results[job] = line.strip_edges()
					_say(line.strip_edges())
			if txt.contains("SCRIPT ERROR"):
				results[job] = "M3B_JOB_FAIL %s SCRIPT ERROR in %s" % [job, _logs[job]]
			if not results.has(job):
				results[job] = "M3B_JOB_FAIL %s worker exited (code %d) without a result" % [job, OS.get_process_exit_code(wpid)]
			if str(results[job]).begins_with("M3B_JOB_FAIL"):
				_dump(job)
		if queue.is_empty() and running.is_empty():
			break
	for job in running:
		OS.kill(running[job])
		if not results.has(job):
			results[job] = "M3B_JOB_FAIL %s timeout" % job
			_dump(job)
	print("")
	print("==== M3b 驗收 run=%s ====" % _run_id)
	var failed: Array = []
	for job in jobs:
		var line := str(results.get(job, "M3B_JOB_FAIL %s missing" % job))
		print(("PASS  " if line.begins_with("M3B_JOB_OK") else "FAIL  ") + line.substr(line.find(" ") + 1))
		if not line.begins_with("M3B_JOB_OK"):
			failed.append(line)
	var elapsed := (Time.get_ticks_msec() - _t0) / 1000.0
	if failed.is_empty():
		print("M3B_ACCEPT_OK run=%s scenarios=%d elapsed=%.0fs" % [_run_id, jobs.size(), elapsed])
		_finish(0)
	else:
		for f in failed:
			var rest := str(f).substr(str(f).find(" ") + 1)
			print("M3B_ACCEPT_FAIL " + rest)
		_finish(1)

func _log_text(job: String) -> String:
	var p: String = _logs.get(job, "")
	if p == "" or not FileAccess.file_exists(p):
		return ""
	return FileAccess.get_file_as_string(p)

func _dump(job: String) -> void:
	var lines := _log_text(job).split("\n")
	print("----- %s (%s) 尾端 -----" % [job, _logs.get(job, "")])
	var at := -1
	for i in lines.size():
		if lines[i].contains("SCRIPT ERROR"):
			at = i
			break
	if at >= 0:
		print("\n".join(lines.slice(maxi(0, at - 3), mini(lines.size(), at + 12))))
	else:
		print("\n".join(lines.slice(maxi(0, lines.size() - 40))))

func _fail_out(msg: String) -> void:
	print("M3B_ACCEPT_FAIL " + msg)
	_finish(1)

func _finish(code: int) -> void:
	if _finished:
		return
	_finished = true
	_finalize()
	quit(code)

# ======================================================================== worker
func _ws() -> Node:
	return root.get_node("WorldServer")

func _capture(peer_id: int, what: String, payload: Variant) -> void:
	var b = _bots.get(peer_id)
	if b != null:
		b.on_capture(what, payload)

func _worker(a: Dictionary) -> void:
	var run := str(a.get("m3b-run", "x"))
	var job := str(a.get("job", ""))
	randomize()
	DataRoot.override_for_tests(_root)
	var wroot := _root.path_join("m3b_acceptance/worlds")
	root.get_node("SaveManager").root_dir = wroot
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(wroot))
	var ws := _ws()
	ws.debug_intents = true
	ws.set_time_scale(1.0)
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	root.get_node("ClientState").capture_remote = _capture
	var t0 := Time.get_ticks_msec()
	var world := "m3b_%s_%s" % [run, job]
	var res := {}
	if ws.start(world) != OK:
		res = { "ok": false, "err": "world start failed: " + str(ws.last_error) }
	else:
		ws.rng.seed = hash(world)
		var fn := Callable(self, "_sc_" + job)
		if not fn.is_valid():
			res = { "ok": false, "err": "no scenario " + job }
		else:
			res = fn.call()
	if ws.running:
		ws.stop()
	_bots.clear()
	root.get_node("ClientState").capture_remote = Callable()
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	if bool(res.get("ok", false)):
		print("M3B_JOB_OK %s %.1fs %s" % [job, secs, str(res.get("info", ""))])
	else:
		print("M3B_JOB_FAIL %s %.1fs %s" % [job, secs, str(res.get("err", "?"))])
	await process_frame
	quit(0 if bool(res.get("ok", false)) else 1)

const NAME_CHARS := "甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉戌亥春夏秋冬東南西北"
func unique_name(prefix: String) -> String:
	var out := prefix
	for i in 4:
		out += NAME_CHARS[randi() % NAME_CHARS.length()]
	return out

## 新玩家：建角（出生城、性別），strong=false 時不加強（新手）
func player(tag: String, city := "xixia", gender := "M", strong := true):
	_next_peer += 1
	var b = load(BOT).new(_ws(), _next_peer, unique_name(tag), tag)
	b.city = city
	b.gender = gender
	b.keep_weak = not strong
	_bots[_next_peer] = b
	if not b.create_char():
		return b
	return b

func _ok(info: String) -> Dictionary:
	return { "ok": true, "info": info }

func _bad(b) -> Dictionary:
	return { "ok": false, "err": "[%s] %s" % [b.label, b.err] }

func _err(msg: String) -> Dictionary:
	return { "ok": false, "err": msg }

func host():
	return _ws().game

func opts() -> Dictionary:
	return _ws().options

# ------------------------------------------------------------------------ jingcheng_walk
## 西夏出生 → 東路 → 華山腳下 → 華山古道 → 南郊 → 京城南門 → 廣場（region jingcheng；華山腳下起 ≤ 20 步）；
## 另一角色京城出生成功、在 jc_square
func _sc_jingcheng_walk() -> Dictionary:
	var b = player("京行")
	if b.err != "":
		return _bad(b)
	if not b.walk("hy_foot"):
		return _bad(b)
	var m0: int = b.moves
	for r in ["jcw_huashan", "jcw_crossroad", "jc_gate_s", "jc_square"]:
		if not b.walk(r):
			return _bad(b)
	var steps: int = b.moves - m0
	if not b.expect(b.region() == "jingcheng", "region %s, want jingcheng" % b.region()):
		return _bad(b)
	if not b.expect(steps <= 20, "hy_foot -> jc_square took %d steps (> 20)" % steps):
		return _bad(b)
	var c = player("京生", "jingcheng")
	if c.err != "":
		return _bad(c)
	if not c.expect(c.room() == "jc_square", "jingcheng birth at %s" % c.room()):
		return _bad(c)
	return _ok("walk xixia->jc_square moves=%d (hy_foot->square %d steps); 京城出生 at %s" % [b.moves, steps, c.room()])

# ------------------------------------------------------------------------ gaibang
func _sc_gaibang() -> Dictionary:
	var b = player("丐", "jingcheng", "F")
	if b.err != "":
		return _bad(b)
	var m0: int = b.moves
	if not b.walk("gb_gate"):
		return _bad(b)
	if not b.expect(b.moves - m0 == 5, "jc_square -> gb_gate took %d steps (want 5)" % (b.moves - m0)):
		return _bad(b)
	if not b.walk("gb_pomiao") or not b.must("join_sect", { "npc": "n_gb_chen" }):
		return _bad(b)
	if not b.expect(str(b.ch().sect) == "gaibang", "sect %s" % str(b.ch().sect)):
		return _bad(b)
	b.debug("learn_points", 5000)
	if not b.must("learn", { "npc": "n_gb_chen", "skill": "qitao" }):
		return _bad(b)
	if not b.expect(int(b.ch().skills.level("qitao")) >= 1, "qitao level %d" % int(b.ch().skills.level("qitao"))):
		return _bad(b)
	# 乞討 3 次：不同 NPC 都成功、熟練增加；同一個 NPC 第二次回冷卻
	if not b.walk("jc_square"):
		return _bad(b)
	var beg_targets := ["n_jc_roubao"]   # 王大娘（SHOP）；同派的姜乞丐不能乞討（cant_beg）
	var p0: int = int(b.ch().skills.prof("qitao")) + int(b.ch().skills.level("qitao")) * 100000
	for npc in beg_targets:
		b.refill()
		if not b.must("beg", { "npc": npc }):
			return _bad(b)
	if not b.expect_reason("beg", { "npc": "n_jc_roubao" }, Protocol.R_BEG_COOLDOWN):
		return _bad(b)
	if not b.expect_reason("beg", { "npc": "n_gb_jiang" }, Protocol.R_CANT_BEG):
		return _bad(b)
	if not b.walk("jc_street"):
		return _bad(b)
	b.refill()
	if not b.must("beg", { "npc": "n_jc_lidashen" }):
		return _bad(b)
	if not b.walk("jc_pharmacy"):
		return _bad(b)
	b.refill()
	if not b.must("beg", { "npc": "n_jc_pharmacist" }):
		return _bad(b)
	var p1: int = int(b.ch().skills.prof("qitao")) + int(b.ch().skills.level("qitao")) * 100000
	if not b.expect(p1 > p0, "qitao did not grow (%d -> %d)" % [p0, p1]):
		return _bad(b)
	if not b.expect(b.evs("beg").size() >= 3, "beg events %d" % b.evs("beg").size()):
		return _bad(b)
	# 傳功長老學丐幫心法、太祖長拳；二階武功在二袋前回 req_sect_rank_min
	if not b.walk("gb_houdian"):
		return _bad(b)
	for sk in ["gb_xinfa", "gb_taizu_quan"]:
		if not b.must("learn", { "npc": "n_gb_chuangong", "skill": sk }):
			return _bad(b)
	var sh: Dictionary = b.fresh_sheet()
	var si: Dictionary = sh.get("sect_info", {}) if sh.get("sect_info") is Dictionary else {}
	if not b.expect(str(si.get("id", si.get("sect", ""))) == "gaibang" or str(b.ch().sect) == "gaibang", "sect_info %s" % str(si)):
		return _bad(b)
	if not b.expect_reason("learn", { "npc": "n_gb_chuangong", "skill": "gb_fengmo" }, Protocol.R_REQ_SECT_RANK_MIN):
		return _bad(b)
	# 一袋：q_gb_dai1 照資料的 test_plan 走（三城情報、三次埋伏、殺滿 20），setup 只用 debug 鍵（門派已是真的拜入）
	var plan := _plan("q_gb_dai1", 0)
	if plan.is_empty():
		return _err("q_gb_dai1 has no test_plan")
	var st: Dictionary = (plan.get("setup", {}) as Dictionary).duplicate(true)
	st.erase("sect")
	st.erase("sect_rank")
	plan["setup"] = st
	b.make_strong()
	if not b.run_plan(plan, _plans(), true):
		return _bad(b)
	var pend: Dictionary = b.ch().sect_rank_pending
	if not b.expect(int(pend.get("rank", -1)) == 1, "after q_gb_dai1 pending %s (want rank 1)" % str(pend)):
		return _bad(b)
	sh = b.fresh_sheet()
	var rk: Variant = (sh.get("sect_info", {}) as Dictionary).get("rank", {}) if sh.get("sect_info") is Dictionary else {}
	b.say("sheet rank before assembly: %s" % str(rk))
	var n0: int = b.mark()
	if not b.to_next_shichen("辰"):
		return _bad(b)
	b.flush_view()
	if not b.expect(int(b.ch().sect_rank) == 1, "after 辰時 assembly rank %d (pending %s)" % [int(b.ch().sect_rank), str(b.ch().sect_rank_pending)]):
		return _bad(b)
	var up: Dictionary = b.last_ev("sect_rank_up", n0)
	if not b.expect(not up.is_empty(), "no sect_rank_up event"):
		return _bad(b)
	if not b.expect(str(up.get("p", {}).get("rank_name", "")) == "一袋弟子", "rank_name %s" % str(up.get("p", {}))):
		return _bad(b)
	sh = b.fresh_sheet()
	rk = (sh.get("sect_info", {}) as Dictionary).get("rank", {}) if sh.get("sect_info") is Dictionary else {}
	if not b.expect(rk is Dictionary and int(rk.get("level", -1)) == 1 and str(rk.get("name", "")) == "一袋弟子",
			"sheet sect_info.rank %s" % str(rk)):
		return _bad(b)
	return _ok("joined 丐幫, qitao Lv%d, beg x3 + cooldown, 二階 locked, q_gb_dai1 done (moves=%d battles=%d), 辰時聚會 → 一袋弟子" %
		[int(b.ch().skills.level("qitao")), b.moves, b.battle_results.size()])

# ------------------------------------------------------------------------ capital_jail
func _join_shaolin(b) -> bool:
	if not b.walk("sl_gate"):
		return false
	if not b.must("join_sect", { "npc": "n_sl_zhike" }):
		return false
	return b.expect(str(b.ch().sect) == "shaolin", "not in 少林: %s" % str(b.ch().sect))

func _sc_capital_jail() -> Dictionary:
	# 路上不遇敵（三人長途步行；遇敵不是本劇本要驗的）、敵對入山不開戰（叛派者要走出少林山門）
	opts()["encounters_enabled"] = false
	opts()["sect_hostile_entry"] = false
	# 審查修正：AUTO（預設）時違反門規仍關各派思過處、只有被捉拿的公敵送京城監獄；違規進京城要選項 CAPITAL
	opts()["jail_location"] = "AUTO"
	var gs = _ws().game.sects
	if gs.breach_jail_resolved() != "SECT" or gs.jail_location_resolved() != "CAPITAL" 			or gs.jail_room_for("shaolin", "BREACH") != "sl_siguo" or gs.jail_room_for("shaolin", "ENEMY") != "jc_jail":
		return _err("AUTO: breach=%s/%s enemy=%s/%s (want SECT sl_siguo / CAPITAL jc_jail)" % [gs.breach_jail_resolved(),
			gs.jail_room_for("shaolin", "BREACH"), gs.jail_location_resolved(), gs.jail_room_for("shaolin", "ENEMY")])
	opts()["jail_location"] = "CAPITAL"
	var a = player("同門甲")
	var b = player("同門乙", "xixia", "M", false)
	if a.err != "":
		return _bad(a)
	if b.err != "":
		return _bad(b)
	b.debug("combat_xp", 600)   # 不受新手保護（500）
	for p in [a, b]:
		if not _join_shaolin(p):
			return _bad(p)
	if not a.walk("jcw_crossroad"):
		return _bad(a)
	if not b.walk("jcw_crossroad"):
		return _bad(b)
	var na: int = a.mark()
	if not a.must("force_pk", { "target": b.char_id }):
		return _bad(a)
	if not b.expect(int(b.s().battle_id) != 0, "B not in battle after force_pk"):
		return _bad(b)
	if not a.drive_pvp(_ws(), [a, b], ["fight", "defend"]):
		return _err("pvp battle did not end")
	_ws().advance(1.5)
	a.flush_view()
	var breach: Dictionary = a.last_ev("sect_breach", na)
	if not a.expect(not breach.is_empty() and str(breach.get("p", {}).get("outcome", "")) == "JAIL",
			"sect_breach %s" % str(breach)):
		return _bad(a)
	var jin: Dictionary = a.last_ev("jail_in", na)
	if jin.is_empty():
		jin = a.last_ev("jail_in_capital", na)
	if not a.expect(not jin.is_empty(), "no jail_in"):
		return _bad(a)
	if not a.expect(a.ch().is_jailed() and a.room() == "jc_jail", "A at %s jailed=%s" % [a.room(), str(a.ch().is_jailed())]):
		return _bad(a)
	if not a.expect(str(_ws().world_info().get("jail_location_resolved", "")) == "CAPITAL", "world_info jail_location_resolved %s" % str(_ws().world_info().get("jail_location_resolved", ""))):
		return _bad(a)
	if not a.expect_reason("chat", { "text": "冤枉啊", "ch": Protocol.CH_CHAT_WORLD }, "jailed"):
		return _bad(a)
	if not a.must("chat", { "text": "有人嗎", "ch": Protocol.CH_CHAT_SAY }):
		return _bad(a)
	# B 重生後走到監獄門口贖人
	b.refill()
	b.say("B respawned at %s" % b.room())
	if not b.walk("jc_jail_gate"):
		return _bad(b)
	b.debug("money", 150000)
	var nr: int = a.mark()
	if not b.must("jail_ransom", { "npc": "n_jc_jailer", "name": a.pname }):
		return _bad(b)
	_ws().advance(1.5)
	a.flush_view()
	var out: Dictionary = a.last_ev("jail_out", nr)
	if out.is_empty():
		out = a.last_ev("jail_out_capital", nr)
	if not a.expect(not out.is_empty() and not a.ch().is_jailed() and a.room() == "jc_yamen",
			"after ransom room=%s jailed=%s out=%s" % [a.room(), str(a.ch().is_jailed()), str(out)]):
		return _bad(a)
	opts()["jail_location"] = "AUTO"
	# 公敵被抓（AUTO 預設）：A' 叛出少林 → 少林弟子 B 在南郊捉拿 → A' 戰死 → 京城監獄（ENEMY）
	var e = player("叛僧", "xixia", "M", false)
	if e.err != "":
		return _bad(e)
	e.debug("combat_xp", 1000)
	if not _join_shaolin(e):
		return _bad(e)
	if not e.must("sect_betray", { "npc": "n_sl_zhike", "confirm": true }):
		return _bad(e)
	if not e.expect(e.ch().sect_enemies.has("shaolin"), "betrayer not an enemy of 少林"):
		return _bad(e)
	if not e.walk("jcw_crossroad"):
		return _bad(e)
	if not b.walk("jcw_crossroad"):
		return _bad(b)
	b.refill()
	var ne: int = e.mark()
	if not b.must("seize_enemy", { "name": e.pname }):
		return _bad(b)
	if not b.drive_pvp(_ws(), [b, e], ["fight", "defend"]):
		return _err("seize battle did not end")
	_ws().advance(1.5)
	e.flush_view()
	if not e.expect(e.ch().is_jailed() and str(e.ch().jail.get("reason", "")) == "ENEMY", "enemy jail %s" % str(e.ch().jail)):
		return _bad(e)
	if not e.expect(e.room() == "jc_jail", "enemy at %s (want jc_jail)" % e.room()):
		return _bad(e)
	if not e.expect(not e.last_ev("seize_done", ne).is_empty() or not b.last_ev("seize_done").is_empty(), "no seize_done"):
		return _bad(e)
	return _ok("AUTO: breach→sl_siguo, enemy→jc_jail; CAPITAL: 同門相殘 → sect_breach JAIL → jc_jail, world chat jailed, say ok, ransom → jc_yamen; 公敵 seized → jc_jail ENEMY")

# ------------------------------------------------------------------------ escort
func _sc_escort() -> Dictionary:
	opts()["encounters_enabled"] = false
	var a = player("鏢甲")
	var b = player("鏢乙")
	if a.err != "" or b.err != "":
		return _bad(a if a.err != "" else b)
	if not a.walk("xx_biaoju") or not b.walk("xx_biaoju"):
		return _bad(a if a.err != "" else b)
	if not a.must("party_invite", { "target": b.char_id }) or not b.must("party_reply", { "from": a.char_id, "accept": true }):
		return _bad(a if a.err != "" else b)
	var qid := "q_ec_biao_xx_dl"
	for p in [a, b]:
		if not p.must("quest_accept", { "npc": "n_ec_xx_biaotou", "quest": qid }):
			return _bad(p)
		p.advance_dialogue()
		if p.active(qid).is_empty() and not p.auto_accept(qid):
			return _bad(p)
	var m0 := [int(a.ch().money), int(b.ch().money)]
	var f0 := [int(a.ch().fame), int(b.ch().fame)]
	if not a.walk_with(b, "dl_biaoju"):
		return _bad(a)
	_ws().advance(1.0)
	for p in [a, b]:
		p._let_a_second_pass()
	for i in 2:
		var p = [a, b][i]
		if not p.expect(p.done_entry(qid).has("n"), "%s did not complete %s (active %s)" % [p.pname, qid, str(p.active(qid))]):
			return _bad(p)
		var dm: int = int(p.ch().money) - int(m0[i])
		var df: int = int(p.ch().fame) - int(f0[i])
		if not p.expect(dm == 150 and df == 3, "%s reward money %+d fame %+d (want +150, +3)" % [p.pname, dm, df]):
			return _bad(p)
	# 丐幫弟子不能接保鏢
	var g = player("丐鏢")
	if g.err != "":
		return _bad(g)
	g.ch().sect = "gaibang"   # 捷徑（同故事 bot 的 setup.sect）
	g.s().sheet_dirty = true
	if not g.walk("xx_biaoju"):
		return _bad(g)
	if not g.expect_reason("quest_accept", { "npc": "n_ec_xx_biaotou", "quest": qid }, Protocol.R_REQ_SECT_NOT):
		return _bad(g)
	# 托鏢：A 在大理鏢局寄 1 件給 B 到西夏 → 快轉 4 時辰 → B 收到 consign_arrived → B 走回西夏鏢局領
	if not a.walk("dl_shop") or not a.must("buy", { "npc": "n_dl_grocer", "item": "c_mantou", "n": 1 }):
		return _bad(a)
	if not a.walk("dl_biaoju"):
		return _bad(a)
	var uid: String = a.uid_of("c_mantou")
	var nb: int = b.mark()
	if not a.must("consign_send", { "npc": "n_ec_dl_biaotou", "to": b.pname, "city": "xixia", "items": [{ "uid": uid, "n": 1 }], "money": 0 }):
		return _bad(a)
	var sc: float = host().day_s() / 12.0
	if not a.debug("world_s_add", sc * 4.0 + 5.0):
		return _bad(a)
	_ws().advance(0.5)
	if not b.expect(not b.last_ev("consign_arrived", nb).is_empty(), "B got no consign_arrived"):
		return _bad(b)
	if not b.walk("xx_biaoju"):
		return _bad(b)
	var have0: int = b.count_item("c_mantou")
	var ready: Array = []
	for c in host().escort.all():
		if str(c.get("to_char", "")) == b.char_id and str(c.get("status", "")) == "READY":
			ready.append(str(c.get("id", "")))
	if not b.must("consign_list", { "npc": "n_ec_xx_biaotou" }):
		return _bad(b)
	if not b.expect(ready.size() == 1, "ready consignments %s" % str(ready)):
		return _bad(b)
	if not b.must("consign_take", { "npc": "n_ec_xx_biaotou", "id": ready[0] }):
		return _bad(b)
	if not b.expect(b.count_item("c_mantou") == have0 + 1, "consign_take did not give the item"):
		return _bad(b)
	return _ok("2-player party escort 西夏→大理 (both +150 兩 +3 名聲), 丐幫 refused req_sect_not, consign 大理→西夏 arrived after 4 時辰 and taken")

# ------------------------------------------------------------------------ bank
func _sc_bank() -> Dictionary:
	var b = player("錢客")
	if b.err != "":
		return _bad(b)
	if not b.walk("xx_smithy"):
		return _bad(b)
	for it in ["w_mujian", "w_chaidao", "t_zhenxian"]:
		if not b.must("buy", { "npc": "n_xx_smith", "item": it, "n": 1 }):
			return _bad(b)
	if not b.walk("xx_bank"):
		return _bad(b)
	var npc := "n_ec_xx_banker"
	if not b.must("bank_open", { "npc": npc }):
		return _bad(b)
	if not b.must("bank_money", { "npc": npc, "amount": 500 }):
		return _bad(b)
	for it in ["w_mujian", "w_chaidao", "t_zhenxian"]:
		if not b.must("bank_put", { "npc": npc, "uid": b.uid_of(it), "n": 1 }):
			return _bad(b)
	var v: Dictionary = host().bank.view(b.ch())
	if not b.expect(int(v.get("money", 0)) == 500 and (v.get("items", []) as Array).size() == 3, "bank view %s" % str(v)):
		return _bad(b)
	var why: String = b.reload_world(_ws(), [b])
	if why != "":
		return _err(why)
	v = host().bank.view(b.ch())
	if not b.expect(int(v.get("money", 0)) == 500 and (v.get("items", []) as Array).size() == 3, "after reload bank view %s" % str(v)):
		return _bad(b)
	# 大理錢莊取出（三城共用）
	if not b.walk("dl_bank"):
		return _bad(b)
	var npc2 := "n_ec_dl_banker"
	var m0: int = int(b.ch().money)
	if not b.must("bank_money", { "npc": npc2, "amount": -500 }):
		return _bad(b)
	for e in (v.get("items", []) as Array):
		if not b.must("bank_take", { "npc": npc2, "uid": str(e.get("uid", "")), "n": int(e.get("n", 1)) }):
			return _bad(b)
	if not b.expect(int(b.ch().money) == m0 + 500, "money after withdraw %d (want %d)" % [int(b.ch().money), m0 + 500]):
		return _bad(b)
	for it in ["w_mujian", "w_chaidao", "t_zhenxian"]:
		if not b.expect(b.count_item(it) == 1, "%s not back in bag" % it):
			return _bad(b)
	return _ok("西夏錢莊存 500 兩＋3 件 → 存檔重開 → 仍在 → 大理錢莊取出（三城共用）")

# ------------------------------------------------------------------------ org
func _sc_org() -> Dictionary:
	opts()["guild_signers"] = 1
	opts()["encounters_enabled"] = false
	var a = player("幫主")
	var b = player("幫眾")
	var c = player("旁觀")
	for p in [a, b, c]:
		if p.err != "":
			return _bad(p)
	a.debug("fame", 150)
	a.debug("money", 20000)
	b.debug("fame", 20)
	for p in [a, b, c]:
		if not p.walk("xx_yamen"):
			return _bad(p)
	var npc := "n_og_xx_shuli"
	var r: Dictionary = a.send("org_found", { "npc": npc, "name": "江湖小築" })
	if not r.get("ok", false):
		return _err("org_found -> %s" % str(r))
	var gid := str(r.get("org", ""))
	var n0: int = a.mark()
	if not b.must("org_sign", { "npc": npc, "org": gid }):
		return _bad(b)
	if not a.expect(not a.last_ev("org_founded", n0).is_empty() or not b.last_ev("org_founded").is_empty(), "no org_founded"):
		return _bad(a)
	var g: Dictionary = host().orgs.find(gid)
	if not a.expect(str(g.get("status", "")) == "ACTIVE", "guild status %s" % str(g.get("status", ""))):
		return _bad(a)
	# 位階 0＝幫主（最高）、4＝幫眾（OrgSystem.DEFAULT_RANK_NAMES）
	var ra: int = host().orgs.member_rank(g, a.char_id)
	var rb: int = host().orgs.member_rank(g, b.char_id)
	if not a.expect(host().orgs.rank_name(g, ra) == "幫主" and host().orgs.rank_name(g, rb) == "幫眾",
			"ranks: leader %d(%s) member %d(%s)" % [ra, host().orgs.rank_name(g, ra), rb, host().orgs.rank_name(g, rb)]):
		return _bad(a)
	if not a.expect(host().orgs.leader_name(g) == a.pname, "leader %s" % host().orgs.leader_name(g)):
		return _bad(a)
	# 組織頻道
	var na: int = a.mark()
	var nc: int = c.mark()
	if not b.must("chat", { "text": "幫主好", "ch": Protocol.CH_CHAT_GUILD }):
		return _bad(b)
	_ws().advance(0.2)
	if not a.expect(not a.last_ev("chat_guild", na).is_empty(), "leader did not get chat_guild"):
		return _bad(a)
	if not c.expect(c.last_ev("chat_guild", nc).is_empty(), "bystander got chat_guild"):
		return _bad(c)
	if not c.expect_reason("chat", { "text": "我也要", "ch": Protocol.CH_CHAT_GUILD }, Protocol.R_NO_GUILD):
		return _bad(c)
	# 退出、再邀請、接受
	if not b.must("org_leave"):
		return _bad(b)
	var nb: int = b.mark()
	if not a.must("org_invite", { "name": b.pname }):
		return _bad(a)
	if not b.expect(not b.last_ev("org_invite", nb).is_empty(), "no org_invite prompt"):
		return _bad(b)
	if not b.must("org_reply", { "org": gid, "accept": true }):
		return _bad(b)
	var why: String = a.reload_world(_ws(), [a, b, c])
	if why != "":
		return _err(why)
	g = host().orgs.find(gid)
	if not a.expect(not g.is_empty() and str(g.get("name", "")) == "江湖小築", "guild after reload %s" % str(g)):
		return _bad(a)
	if not a.expect(host().orgs.org_id_of(a.char_id) == gid and host().orgs.org_id_of(b.char_id) == gid and host().orgs.org_id_of(c.char_id) == "",
			"membership after reload a=%s b=%s c=%s" % [host().orgs.org_id_of(a.char_id), host().orgs.org_id_of(b.char_id), host().orgs.org_id_of(c.char_id)]):
		return _bad(a)
	return _ok("org_found 江湖小築 + 1 signer → ACTIVE, CHAT_GUILD only to members, bystander no_guild, leave → invite → join, survives save/reload")

# ------------------------------------------------------------------------ craft
func _work_until(b, skill: String, recipe: String, item: String, want: int, max_tries := 80) -> bool:
	var tries := 0
	while b.count_item(item) < want:
		tries += 1
		if tries > max_tries:
			return b.fail("work %s %s: only %d %s after %d tries" % [skill, recipe, b.count_item(item), item, max_tries])
		b.refill()
		var args := { "skill": skill }
		if recipe != "":
			args["recipe"] = recipe
		var r: Dictionary = b.send("work", args)
		if not r.get("ok", false):
			return b.fail("work %s -> %s" % [JSON.stringify(args), str(r.get("reason", ""))])
		# 生活技能有冷卻（life_skills.cooldown_s，世界秒）：等它過去（路上遇敵照打）
		var cd := float(host().tables.get("life_skills", {}).get(skill, {}).get("cooldown_s", 5))
		b.advance(cd + 0.3)
		b.clear_battles()
	return true

func _sc_craft() -> Dictionary:
	var b = player("工匠")
	if b.err != "":
		return _bad(b)
	for sk in ["life_mining", "life_smithing", "life_swordsmith"]:
		if not b.debug("skill:" + sk, 1):
			return _bad(b)
	b.debug("money", 20000)
	if not b.walk("xx_tiepu"):
		return _bad(b)
	for it in [["t_shizigao", 1], ["t_tiechui", 1], ["r_mutan", 4]]:
		if not b.must("buy", { "npc": "n_xx_zhangtie", "item": it[0], "n": it[1] }):
			return _bad(b)
	if not b.walk("xe_mine"):
		return _bad(b)
	if not _work_until(b, "life_mining", "", "r_kuang_tie", 6):
		return _bad(b)
	var ores: int = b.count_item("r_kuang_tie")
	if not b.walk("xx_tiepu"):
		return _bad(b)
	if not _work_until(b, "life_smithing", "rc_tiekuai_1", "r_tiekuai_1", 2):
		return _bad(b)
	if not _work_until(b, "life_swordsmith", "rc_tiejian", "w_tiejian", 1):
		return _bad(b)
	# 1.0B：京城木匠學工匠 → 嵩山松林砍木材 → 做木劍
	if not b.walk("jc_street_n"):
		return _bad(b)
	b.debug("learn_points", 2000)
	if not b.must("learn", { "npc": "n_ls_jc_mujiang", "skill": "life_carpentry" }):
		return _bad(b)
	if not b.must("buy", { "npc": "n_ls_jc_mujiang", "item": "t_juzi", "n": 1 }):
		return _bad(b)
	if not b.debug("skill:life_woodcut", 1):
		return _bad(b)
	if not b.walk("jc_smithy") or not b.must("buy", { "npc": "n_jc_smith", "item": "w_chaidao", "n": 1 }):
		return _bad(b)
	if not b.walk("sy_pines"):
		return _bad(b)
	if not _work_until(b, "life_woodcut", "", "r_wood", 2):
		return _bad(b)
	var mj0: int = b.count_item("w_mujian")
	if not _work_until(b, "life_carpentry", "rc_mujian", "w_mujian", mj0 + 1):
		return _bad(b)
	return _ok("挖礦 → 鐵礦石 ×%d → 打鐵 鐵塊 → 鑄劍 鐵劍 ×%d；京城木匠學工匠 → 松林砍木 → 木劍" % [ores, b.count_item("w_tiejian")])

# ------------------------------------------------------------------------ jueqinggu
func _sc_jueqinggu() -> Dictionary:
	var b = player("谷客", "jingcheng")
	if b.err != "":
		return _bad(b)
	if not b.walk("jc_gate_s"):
		return _bad(b)
	var m0: int = b.moves
	if not b.walk("jq_gukou"):
		return _bad(b)
	if not b.expect(b.moves - m0 == 3, "jc_gate_s -> jq_gukou %d steps (want 3)" % (b.moves - m0)):
		return _bad(b)
	if not b.expect("n_jq_fanyiweng" in host().index.npcs_in("jq_gukou"), "樊一翁 not at 谷口"):
		return _bad(b)
	# 資料的第二條 test_plan（§11.3 jueqinggu：走情花林 → 公孫止 → 丹房取絕情丹 → 用絕情丹解毒）
	var plan := _plan("q_jq_liumei", 1)
	if plan.is_empty():
		return _err("q_jq_liumei#1 test_plan missing")
	if not b.run_plan(plan, _plans(), true):
		return _bad(b)
	if not b.expect(not b.ch().conditions.has("qinghua"), "still poisoned by 情花"):
		return _bad(b)
	# M3b 審查 3：絕情丹 keep_on_use——解毒後丹藥還在身上（一人一顆，用掉就再也解不了）
	if not b.expect(b.count_item("c_jq_juequingdan") == 1, "絕情丹 consumed by cure (keep_on_use)"):
		return _bad(b)
	return _ok("南門 → 谷口 3 步、樊一翁在；情花林 → 石屋 公孫止 → 丹房 絕情丹 → 解毒（情花毒已解、絕情丹仍在身上 ×%d%s）" % [
		b.count_item("c_jq_juequingdan"), "" if b.notes.is_empty() else "; " + "; ".join(b.notes)])

# ------------------------------------------------------------------------ story
func _sc_story() -> Dictionary:
	var b = player("事件")
	if b.err != "":
		return _bad(b)
	var p1 := _plan("q_sm_dujulaoren", 0)
	if p1.is_empty() or not b.run_plan(p1, _plans(), true):
		return _bad(b) if b.err != "" else _err("q_sm_dujulaoren has no test_plan")
	var c = player("運鐵")
	if c.err != "":
		return _bad(c)
	var p2 := _plan("q_sm_yuntie", 0)
	if p2.is_empty():
		return _err("q_sm_yuntie has no test_plan")
	# 只走到張鐵那一步（§11.3）
	var path: Array = p2.get("path", [])
	var cut := path.find("walk@xx_tiepu")
	if cut < 0:
		return _err("q_sm_yuntie path has no walk@xx_tiepu")
	var part := p2.duplicate(true)
	part["path"] = path.slice(0, cut + 2)
	part["outcome"] = "none"
	part["expect"] = {}
	if not c.run_plan(part, _plans(), false):
		return _bad(c)
	if not c.expect(not c.active("q_sm_yuntie").is_empty(), "q_sm_yuntie not active at 張鐵"):
		return _bad(c)
	return _ok("獨居老人 done (rewards checked); 運鐵 reached 張鐵 at %s (stage %s)" % [c.room(), c.stage_of("q_sm_yuntie")])

# ------------------------------------------------------------------------ era_1_0a
func _sc_era_1_0a() -> Dictionary:
	var eras: Array = _ws().world.get("enabled_eras", [])
	if eras != ["1.0A"]:
		return _err("world eras %s (want [1.0A])" % str(eras))
	for rid in ["jc_square", "gb_gate", "jq_gukou"]:
		if host().index.has_room(rid):
			return _err("1.0A world has room " + rid)
	var b = player("舊版")
	if b.err != "":
		return _bad(b)
	# 創角：出生城只有兩座
	var births: Array = []
	for rid in host().tables.get("regions", {}):
		if bool(host().tables["regions"][rid].get("birth_allowed", false)):
			births.append(rid)
	births.sort()
	if not b.expect(births == ["dali", "xixia"], "birth cities %s" % str(births)):
		return _bad(b)
	var c2 = load(BOT).new(_ws(), 999, unique_name("京"), "jcbirth")
	_bots[999] = c2
	if not c2.connect_session() or not c2.must("char_roll"):
		return _bad(c2)
	if not c2.expect_reason("char_create", { "name": c2.pname, "gender": "M", "birth_month": 3, "birth_city": "jingcheng",
			"alloc": { "wit": 5 } }, "bad_value:birth_city"):
		return _bad(c2)
	if not b.expect_reason("work", { "skill": "life_carpentry" }, "not_known"):
		return _bad(b)
	b.ch().sect = "shaolin"   # 捷徑：門派
	if not b.expect_reason("seize_enemy", { "name": "某人" }, Protocol.R_ERA_LOCKED):
		return _bad(b)
	b.ch().sect = ""
	# 錢莊、組織、挖礦照常
	if not b.walk("xx_bank") or not b.must("bank_open", { "npc": "n_ec_xx_banker" }):
		return _bad(b)
	if not b.walk("xx_yamen") or not b.must("talk", { "npc": "n_og_xx_shuli" }):
		return _bad(b)
	b.debug("skill:life_mining", 1)
	if not b.walk("xx_tiepu") or not b.must("buy", { "npc": "n_xx_zhangtie", "item": "t_shizigao", "n": 1 }):
		return _bad(b)
	if not b.walk("xe_mine") or not b.must("work", { "skill": "life_mining" }):
		return _bad(b)
	return _ok("1.0A world: no 京城/丐幫/絕情谷 rooms, births %s, 京城 birth refused, 工匠 not_known, seize era_locked; bank/org clerk/mining ok" % str(births))

# ------------------------------------------------------------------------ 資料
func _plans() -> Dictionary:
	var out := {}
	var gd: Node = root.get_node("GameData")
	var qs: Dictionary = gd.loader.all_tables.get("quests", {}) if gd.loader != null else gd.tables.get("quests", {})
	for qid in qs:
		var tp: Variant = qs[qid].get("test_plan", [])
		if tp is Array and not (tp as Array).is_empty():
			out[qid] = tp
	return out

func _plan(qid: String, idx: int) -> Dictionary:
	var tp: Array = _plans().get(qid, [])
	return (tp[idx] as Dictionary).duplicate(true) if idx < tp.size() else {}
