extends SceneTree
## M3c 驗收（M3C_PLAN §12.3）。
##   godot --headless --path . --script res://tools/m3c_acceptance.gd -- --no-steam [--only=looks[,nav_walk]] [--workers=4] [--timeout=2400]
## 劇本：looks nav_walk npc_good npc_sect loot_rare manual equip8 divine_pvp fx_snapshot（§12.3 表；minimap_edge 在介面驗收）。
## loot_rare 另開一個 classic_strict 世界的 worker（loot_rare_strict）驗「沒有傳聞」。
##
## 作法照 tools/m3b_acceptance.gd：協調器（本檔，不帶 --m3c-worker）每個劇本開一個 worker 子行程（同一個檔案帶
## --m3c-worker）；worker 在自己的行程裡開真的主機（WorldServer＋GameHost、全部系統、--debug-intents），玩家是假的遠端
## 連線（tests/bots/m3c_bot.gd，延伸 M3b／故事驗收 bot），一切動作經 handle_intent；每個劇本用全新世界。
## debug_set 只用來設屬性、實戰、銀兩、技能、時辰快轉、給物品、強制掉落、開指定怪戰鬥；路一律用走的
## （teleport 只把 bot 送回起點）。測試捷徑（同 M3b bot）：refill 回滿、nav_walk 直接把氣設成 25%。
## 成功印 M3C_ACCEPT_OK（結束碼 0）；失敗印 M3C_ACCEPT_FAIL <劇本> <原因> 並傾印 log 尾端（結束碼 1）。
## log 與世界在 <測試根目錄>/m3c_acceptance/<run>/；不論成敗所有子程序 OS.kill()。不碰擁有者存檔、不寫 C:。

const BOT := "res://tests/bots/m3c_bot.gd"
const SCENARIOS := ["looks", "nav_walk", "npc_good", "npc_sect", "loot_rare", "manual", "equip8", "divine_pvp", "fx_snapshot"]
## 劇本 → 額外的 worker（同劇本的另一個世界）
const EXTRA_JOBS := { "loot_rare": ["loot_rare_strict"] }

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
	if a.has("m3c-worker"):
		await _worker(a)
	else:
		await _coordinate(a)

func _say(msg: String) -> void:
	print("[m3c_acceptance %6.1fs] %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, msg])

# ======================================================================== 協調器
func _coordinate(a: Dictionary) -> void:
	randomize()
	_run_id = "%04x" % (randi() % 0x10000)
	_dir = ProjectSettings.globalize_path(_root.path_join("m3c_acceptance/%s" % _run_id))
	DirAccess.make_dir_recursive_absolute(_dir)
	var jobs: Array = SCENARIOS.duplicate()
	if a.has("only"):
		jobs = []
		for j in str(a["only"]).split(",", false):
			if not (j in SCENARIOS):
				_fail_out("? unknown scenario " + j)
				return
			jobs.append(j)
	for j in jobs.duplicate():
		for x in EXTRA_JOBS.get(j, []):
			jobs.append(x)
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
				"res://tools/m3c_acceptance.gd", "--", "--no-steam", "--debug-intents", "--m3c-worker",
				"--m3c-run=%s" % _run_id, "--job=" + job, DataRoot.child_arg(_root)])
			if job.ends_with("_strict"):
				args.append("--rule-preset=classic_strict")
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
				if line.begins_with("M3C_JOB_OK ") or line.begins_with("M3C_JOB_FAIL "):
					results[job] = line.strip_edges()
					_say(line.strip_edges())
			if txt.contains("SCRIPT ERROR"):
				results[job] = "M3C_JOB_FAIL %s SCRIPT ERROR in %s" % [job, _logs[job]]
			if not results.has(job):
				results[job] = "M3C_JOB_FAIL %s worker exited (code %d) without a result" % [job, OS.get_process_exit_code(wpid)]
			if str(results[job]).begins_with("M3C_JOB_FAIL"):
				_dump(job)
		if queue.is_empty() and running.is_empty():
			break
	for job in running:
		OS.kill(running[job])
		if not results.has(job):
			results[job] = "M3C_JOB_FAIL %s timeout" % job
			_dump(job)
	print("")
	print("==== M3c 驗收 run=%s ====" % _run_id)
	var failed: Array = []
	for job in jobs:
		var line := str(results.get(job, "M3C_JOB_FAIL %s missing" % job))
		print(("PASS  " if line.begins_with("M3C_JOB_OK") else "FAIL  ") + line.substr(line.find(" ") + 1))
		if not line.begins_with("M3C_JOB_OK"):
			failed.append(line)
	var elapsed := (Time.get_ticks_msec() - _t0) / 1000.0
	if failed.is_empty():
		print("M3C_ACCEPT_OK run=%s scenarios=%d elapsed=%.0fs" % [_run_id, jobs.size(), elapsed])
		_finish(0)
	else:
		for f in failed:
			var rest := str(f).substr(str(f).find(" ") + 1)
			print("M3C_ACCEPT_FAIL " + rest)
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
	print("M3C_ACCEPT_FAIL " + msg)
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
	var run := str(a.get("m3c-run", "x"))
	var job := str(a.get("job", ""))
	randomize()
	DataRoot.override_for_tests(_root)
	var wroot := _root.path_join("m3c_acceptance/worlds")
	root.get_node("SaveManager").root_dir = wroot
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(wroot))
	var ws := _ws()
	ws.debug_intents = true
	ws.set_time_scale(1.0)
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	root.get_node("ClientState").capture_remote = _capture
	var t0 := Time.get_ticks_msec()
	var world := "m3c_%s_%s" % [run, job]
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
		print("M3C_JOB_OK %s %.1fs %s" % [job, secs, str(res.get("info", ""))])
	else:
		print("M3C_JOB_FAIL %s %.1fs %s" % [job, secs, str(res.get("err", "?"))])
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

func _rumor_keys(b) -> Array:
	return b.rumors.map(func(p): return str(p.get("text_key", "")))

func reload_world_all(bots: Array) -> String:
	return load(BOT).reload_world(_ws(), bots)

func _new_bot(tag: String, city := "xixia", gender := "M", look := -1, strong := true):
	_next_peer += 1
	var b = load(BOT).new(_ws(), _next_peer, unique_name(tag), tag)
	b.city = city
	b.gender = gender
	b.look = look
	b.keep_weak = not strong
	_bots[_next_peer] = b
	b.create_char()
	return b

func _foes(st: Dictionary) -> Array:
	var out: Array = []
	for u in st.get("units", []):
		if u is Dictionary and int(u.get("side", 0)) != int(st.get("my_side", 0)):
			out.append(u)
	return out

## 某玩家自己出手的事件裡出現過的 cat
func _cats_since(b, n0: int) -> Dictionary:
	var cats := {}
	for i in range(n0, b.events.size()):
		var p: Variant = b.events[i].get("p", {})
		if p is Dictionary and (p as Dictionary).has("cat") and int((p as Dictionary).get("atk_peer", 0)) == b.peer:
			cats[str(p["cat"])] = true
	return cats

# ------------------------------------------------------------------------ looks
## 創角男 look 5 → sheet.look／summary.look；戰鬥快照 look＋wtype；戰鬥中 set_look → in_battle；set_look 2；9 → bad_value:look；
## 走到少林拜師 → shaolin_m、appearance 2；存檔重開 → appearance 2；女 look 7 → look_f07；不帶 look → player_m
func _sc_looks() -> Dictionary:
	var b = _new_bot("造型", "xixia", "M", 5)
	if b.err != "":
		return _bad(b)
	var sh: Dictionary = b.fresh_sheet()
	if not b.expect(str(sh.get("look", "")) == "look_m05" and int(sh.get("appearance", -1)) == 5,
			"sheet look %s appearance %s" % [str(sh.get("look", "")), str(sh.get("appearance", ""))]):
		return _bad(b)
	var sm: Dictionary = b.ch().to_summary(host().tables)
	if not b.expect(str(sm.get("look", "")) == "look_m05", "summary look %s" % str(sm.get("look", ""))):
		return _bad(b)
	if not b.debug("battle_monster", "m_rabbit"):
		return _bad(b)
	var st: Dictionary = b.battle_state()
	var me: Dictionary = b.my_snapshot_unit(st)
	if not b.expect(str(me.get("look", "")) == "look_m05" and me.has("wtype"),
			"battle unit look %s has wtype %s" % [str(me.get("look", "")), str(me.has("wtype"))]):
		return _bad(b)
	# 戰鬥中換造型 → in_battle（既有 IDLE 旗標的原因碼；整合紀錄）
	if not b.expect_reason("set_look", { "look": 3 }, "in_battle"):
		return _bad(b)
	b.drive_battle("fight")
	var n0: int = b.mark()
	if not b.must("set_look", { "look": 2 }):
		return _bad(b)
	sh = b.fresh_sheet()
	if not b.expect(str(sh.get("look", "")) == "look_m02", "after set_look 2: %s" % str(sh.get("look", ""))):
		return _bad(b)
	if not b.expect(not b.last_ev("look_changed", n0).is_empty(), "no look_changed event"):
		return _bad(b)
	if not b.expect_reason("set_look", { "look": 9 }, "bad_value:look"):
		return _bad(b)
	if not b.walk("sl_gate") or not b.must("join_sect", { "npc": "n_sl_zhike" }):
		return _bad(b)
	sh = b.fresh_sheet()
	if not b.expect(str(sh.get("look", "")) == "shaolin_m" and int(sh.get("appearance", -1)) == 2,
			"in 少林: look %s appearance %s" % [str(sh.get("look", "")), str(sh.get("appearance", ""))]):
		return _bad(b)
	var why := reload_world_all([b])
	if why != "":
		return _err(why)
	sh = b.fresh_sheet()
	if not b.expect(int(b.ch().appearance) == 2 and str(sh.get("look", "")) == "shaolin_m",
			"after reload appearance %d look %s" % [int(b.ch().appearance), str(sh.get("look", ""))]):
		return _bad(b)
	var f = _new_bot("造型女", "dali", "F", 7)
	if f.err != "":
		return _bad(f)
	sh = f.fresh_sheet()
	if not f.expect(str(sh.get("look", "")) == "look_f07", "female look %s" % str(sh.get("look", ""))):
		return _bad(f)
	var o = _new_bot("舊客", "xixia", "M", -1)
	if o.err != "":
		return _bad(o)
	var olook := str(o.fresh_sheet().get("look", ""))
	if not o.expect(olook == "player_m", "no-look char %s" % olook):
		return _bad(o)
	return _ok("look_m05 in sheet/summary/battle (wtype '%s'); in battle → in_battle; set_look 2; 9 → bad_value:look; 少林 → shaolin_m (appearance 2, survives reload); F look 7 → look_f07; no look → player_m" % str(me.get("wtype", "")))

# ------------------------------------------------------------------------ nav_walk
## 西夏出生先手動走到華山山門（記錄已探索房間）→ 送回起點 → RoutePlanner 跨區路徑（只含已探索、跨 ≥ 2 區）→
## AutoWalkCore 驅動、途中強制遇敵打贏後自動續走 → 抵達；續走關閉時打贏後停（「戰鬥結束」）；氣 25% → 「氣血不足三成」
func _sc_nav_walk() -> Dictionary:
	var b = _new_bot("趕路")
	if b.err != "":
		return _bad(b)
	var start: String = b.room()
	if not b.walk_record("hs_gate"):
		return _bad(b)
	var n_known: int = b.known.size()
	if not b.debug("teleport", start):
		return _bad(b)
	b.refill()
	var tables: Dictionary = host().tables
	var g: Dictionary = RoutePlanner.graph(tables)
	var path: Array = RoutePlanner.find_path(g, start, "hs_gate", b.known)
	if not b.expect(path.size() >= 2 and str(path[0]) == start and str(path[path.size() - 1]) == "hs_gate", "path %s" % str(path)):
		return _bad(b)
	var regions := {}
	for r in path:
		if not b.known.has(str(r)):
			return _err("path has unexplored room %s" % str(r))
		regions[host().index.region_of(str(r))] = true
	if not b.expect(regions.size() >= 2, "path spans %d regions" % regions.size()):
		return _bad(b)
	# 迷霧：沒探索過的目標（少林山門）→ 走得到的最近已探索房間，不把未探索房間放進路徑
	var near: Dictionary = RoutePlanner.nearest_known_toward(g, start, "sl_gate", b.known)
	if not b.expect(not bool(near.get("exact", true)) and b.known.has(str(near.get("room", ""))),
			"nearest_known_toward sl_gate %s" % str(near)):
		return _bad(b)
	var core = AutoWalkCore.new()
	core.configure(tables, g, b.known)
	core.start(path, start, "華山山門")
	if not b.expect(core.progress_text().begins_with("趕路中：往華山山門（剩"), "progress %s" % core.progress_text()):
		return _bad(b)
	var r1: Dictionary = b.auto_walk(core, 2, true)
	if not b.expect(str(r1.get("result", "")) == "ARRIVED" and b.room() == "hs_gate", "auto walk 1: %s at %s" % [str(r1), b.room()]):
		return _bad(b)
	if not b.expect(int(r1.get("battles", 0)) >= 1 and int(r1.get("resumed", 0)) >= 1, "no encounter/resume on walk 1: %s" % str(r1)):
		return _bad(b)
	# 續走關閉：打贏後停在原地
	if not b.debug("teleport", start):
		return _bad(b)
	b.refill()
	var core2 = AutoWalkCore.new()
	core2.configure(tables, g, b.known)
	core2.start(path, start, "華山山門")
	var r2: Dictionary = b.auto_walk(core2, 2, false)
	if not b.expect(str(r2.get("result", "")) == "STOP" and str(r2.get("reason", "")) == AutoWalkCore.MSG_BATTLE_OVER and b.room() != "hs_gate",
			"auto walk 2 (no resume): %s at %s" % [str(r2), b.room()]):
		return _bad(b)
	# 氣 25%（測試捷徑：直接改角色）→ 停
	var c = b.ch()
	var qmax := int(c.derived(tables, opts()).get("qi_max", 100))
	c.vitals["qi"] = int(qmax * 0.25)
	b.s().sheet_dirty = true
	var here: String = b.room()
	var p3: Array = RoutePlanner.find_path(g, here, "hs_gate", b.known)
	var core3 = AutoWalkCore.new()
	core3.configure(tables, g, b.known)
	core3.start(p3, here, "華山山門")
	var r3: Dictionary = b.auto_walk(core3, -1, true)
	if not b.expect(str(r3.get("reason", "")) == AutoWalkCore.MSG_QI and b.room() == here, "qi 25%%: %s at %s" % [str(r3), b.room()]):
		return _bad(b)
	return _ok("explored %d rooms; path %d rooms over %d regions; walk 1 ARRIVED steps=%d battles=%d resumed=%d; no-resume STOP「%s」; qi 25%% STOP「%s」; fog: sl_gate → %s" %
		[n_known, path.size(), regions.size(), int(r1["steps"]), int(r1["battles"]), int(r1["resumed"]), str(r2["reason"]), str(r3["reason"]), str(near.get("room", ""))])

# ------------------------------------------------------------------------ npc_good
## 大理廣場：A 殺小孩（B 同時動手 → npc_busy）→ 善惡 −20、殺氣 +20、PK值不變、na_npc_killed、守衛 → 小孩消失 → 3 時辰後回來；
## 村民 CHALLENGE 敗走仍在；受保護的 NPC → npc_not_attackable；武館教頭開戰、逃走後仍在、照樣能學
func _sc_npc_good() -> Dictionary:
	var a = _new_bot("動手甲", "dali")
	var b = _new_bot("旁觀乙", "dali")
	if a.err != "" or b.err != "":
		return _bad(a if a.err != "" else b)
	for p in [a, b]:
		if not p.walk("dl_square"):
			return _bad(p)
	b.flush_view()
	if not b.expect("n_na_dl_xiaohai" in b.view_npc_ids(), "小孩 not in dl_square view %s" % str(b.view_npc_ids())):
		return _bad(b)
	var atk_x: Variant = b.view_npc("n_na_dl_xiaohai").get("atk")
	var atk_b: Variant = b.view_npc("n_lj_baiyong").get("atk")
	if not b.expect(atk_x is Dictionary and atk_b == null, "view atk: xiaohai %s baiyong %s" % [str(atk_x), str(atk_b)]):
		return _bad(b)
	# M3c 第二輪審查：預設規則（newbie_guard_spare）下新手城內行兇不招官兵 → A 先當老手（實戰 5000），守衛那一段才驗得到
	if not a.debug("combat_xp", 5000):
		return _bad(a)
	var mor0: int = int(a.ch().morality)
	var ki0: int = int(a.ch().killing_intent)
	var pk0: int = int(a.ch().pk)
	var n0: int = a.mark()
	var r: Dictionary = a.send("npc_attack", { "npc": "n_na_dl_xiaohai" })
	if not a.expect(r.get("ok", false) and int(a.s().battle_id) != 0, "npc_attack xiaohai -> %s" % str(r)):
		return _bad(a)
	var bid: int = int(a.s().battle_id)
	var rb: Dictionary = b.send("npc_attack", { "npc": "n_na_dl_xiaohai" })
	if not b.expect(not rb.get("ok", false) and str(rb.get("reason", "")) == "npc_busy" and int(rb.get("battle_id", 0)) == bid,
			"second attacker -> %s (want npc_busy battle_id %d)" % [str(rb), bid]):
		return _bad(b)
	if not a.expect(not a.last_ev("na_attack_start", n0).is_empty(), "no na_attack_start"):
		return _bad(a)
	var res: String = a.drive_battle("fight")
	if not a.expect(res == "VICTORY", "xiaohai battle %s" % res):
		return _bad(a)
	var dm: int = int(a.ch().morality) - mor0
	var dk: int = int(a.ch().killing_intent) - ki0
	if not a.expect(dm == -20 and dk == 20 and int(a.ch().pk) == pk0,
			"kill child: morality %+d killing %+d pk %d→%d (want −20, +20, pk same)" % [dm, dk, pk0, int(a.ch().pk)]):
		return _bad(a)
	if not a.expect(not a.last_ev("na_npc_killed", n0).is_empty(), "no na_npc_killed"):
		return _bad(a)
	a.advance(0.5)
	if not a.expect(not a.last_ev("na_guard_alarm", n0).is_empty() and int(a.s().battle_id) != 0,
			"no guard alarm/battle (battle_id %d)" % int(a.s().battle_id)):
		return _bad(a)
	var gkind := str(host().battles.active.get(int(a.s().battle_id), {}).get("kind", ""))
	a.drive_battle("flee")
	a.refill()
	b.flush_view()
	if not b.expect(not ("n_na_dl_xiaohai" in b.view_npc_ids()), "小孩 still in view after kill"):
		return _bad(b)
	var rt: Dictionary = b.send("talk", { "npc": "n_na_dl_xiaohai" })
	if not b.expect(not rt.get("ok", false), "talk to a killed NPC -> %s" % str(rt)):
		return _bad(b)
	var nb: int = b.mark()
	if not b.debug("world_s_add", 3 * 600 + 120):
		return _bad(b)
	b.advance(0.5)
	b.flush_view()
	if not b.expect(not b.last_ev("na_npc_back", nb).is_empty() and "n_na_dl_xiaohai" in b.view_npc_ids(),
			"小孩 not back (events %s, npcs %s)" % [str(b.evs("na_npc_back", nb)), str(b.view_npc_ids())]):
		return _bad(b)
	# CHALLENGE：村民敗走、仍在
	if a.room() != "dl_square" and not a.walk("dl_square"):
		return _bad(a)
	a.refill()
	mor0 = int(a.ch().morality)
	var n1: int = a.mark()
	if not a.must("npc_attack", { "npc": "n_dl_cunmin" }):
		return _bad(a)
	res = a.drive_battle("fight")
	if not a.expect(res == "VICTORY" and int(a.ch().morality) - mor0 == -10, "cunmin %s morality %+d" % [res, int(a.ch().morality) - mor0]):
		return _bad(a)
	if not a.expect(not a.last_ev("na_npc_routed", n1).is_empty(), "no na_npc_routed"):
		return _bad(a)
	a.advance(0.5)
	if a.s().battle_id != 0:
		a.drive_battle("flee")
	a.refill()
	b.flush_view()
	if not b.expect("n_dl_cunmin" in b.view_npc_ids(), "村民 gone after CHALLENGE"):
		return _bad(b)
	if not b.must("talk", { "npc": "n_dl_cunmin" }):
		return _bad(b)
	# 受保護（任務 NPC，沒有 attack）
	if not b.expect_reason("npc_attack", { "npc": "n_lj_baiyong" }, "npc_not_attackable"):
		return _bad(b)
	# 武館教頭：開戰、打不過就逃、NPC 仍在、照樣能學
	if not b.walk("dl_wuguan"):
		return _bad(b)
	b.refill()
	if not b.must("npc_attack", { "npc": "n_dl_wushi" }):
		return _bad(b)
	var wres: String = b.drive_battle("flee")
	b.refill()
	if b.room() != "dl_wuguan" and not b.walk("dl_wuguan"):
		return _bad(b)
	b.flush_view()
	if not b.expect("n_dl_wushi" in b.view_npc_ids(), "武館教頭 gone"):
		return _bad(b)
	if not b.must("learn_list", { "npc": "n_dl_wushi" }):
		return _bad(b)
	return _ok("xiaohai: npc_busy for 2nd attacker, morality −20 killing +20 pk unchanged, killed → guard battle (%s) → gone → back after 3 時辰; cunmin routed −10 still there; baiyong not attackable; wushi fight %s, still teaches" % [gkind, wres])

# ------------------------------------------------------------------------ npc_sect
func _sc_npc_sect() -> Dictionary:
	# (a) 武當弟子攻擊同門 → sect_breach（JAIL）→ 武當思過處
	var w = _new_bot("武徒", "dali")
	if w.err != "":
		return _bad(w)
	w.debug("morality", 100)
	w.debug("flag:wd_recommended", true)
	if not w.walk("wd_neitang") or not w.must("join_sect", { "npc": "n_wd_zhangsanfeng" }):
		return _bad(w)
	if not w.walk("wd_gate"):
		return _bad(w)
	w.refill()
	var na: int = w.mark()
	if not w.must("npc_attack", { "npc": "n_wd_beizhong" }):
		return _bad(w)
	w.drive_battle("flee")
	w.advance(1.0)
	w.flush_view()
	var br: Dictionary = w.last_ev("sect_breach", na)
	if not w.expect(not br.is_empty() and str(br.get("p", {}).get("outcome", "")) == "JAIL", "wudang breach %s" % str(br)):
		return _bad(w)
	if not w.expect(w.ch().is_jailed() and w.room() == "wd_siguo", "wudang jail: jailed=%s room=%s" % [str(w.ch().is_jailed()), w.room()]):
		return _bad(w)
	# (b) 外人滅派：知客道長選單「滅派」→ 3 名護山、武當公敵 → 走進武當觸發敵對入山
	var o = _new_bot("滅派客", "dali")
	if o.err != "":
		return _bad(o)
	o.debug("morality", 100)
	if not o.walk("wd_gate"):
		return _bad(o)
	var nm: int = o.mark()
	if not o.must("talk", { "npc": "n_wd_zhike" }):
		return _bad(o)
	var menu: Dictionary = o.last_ev("npc_menu", nm)
	var att: Variant = (menu.get("p", {}) as Dictionary).get("attack", {}) if menu.get("p") is Dictionary else {}
	if not o.expect(att is Dictionary and str(att.get("label", "")) == "滅派" and bool(att.get("ok", false)), "npc_menu.attack %s" % str(att)):
		return _bad(o)
	if not o.expect_reason("npc_attack", { "npc": "n_wd_zhike" }, "npc_not_attackable"):   # via MENU：Ctrl+點不行
		return _bad(o)
	o.refill()
	if not o.must("npc_attack", { "npc": "n_wd_zhike", "mode": "MIEPAI" }):
		return _bad(o)
	var foes := _foes(o.battle_state()).size()
	if not o.expect(foes == 3, "滅派 foes %d (want 3)" % foes):
		return _bad(o)
	var enemy_of: Array = o.fresh_sheet().get("enemy_of", [])
	if not o.expect("wudang" in o.ch().sect_enemies and "武當" in enemy_of, "enemy_of %s / sect_enemies %s" % [str(enemy_of), str(o.ch().sect_enemies)]):
		return _bad(o)
	if not o.expect(not o.last_ev("na_sect_enemy", nm).is_empty(), "no na_sect_enemy"):
		return _bad(o)
	o.drive_battle("flee")
	o.refill()
	if o.room() != "wd_gate" and not o.walk("wd_gate"):
		return _bad(o)
	var nh: int = o.mark()
	for i in 6:
		if o.s().battle_id != 0 or o.room() == "wd_square":
			break
		var pth: Array = o.path_to("wd_square")
		if pth.is_empty() or str(pth[0]) == "?":
			break
		if not o.send("move", { "dir": str(pth[0]) }).get("ok", false):
			break
		o.advance(0.3)
	var hostile: bool = not o.last_ev("sect_hostile", nh).is_empty() or o.s().battle_id != 0
	if not o.expect(hostile, "no hostile entry walking into 武當 (room %s)" % o.room()):
		return _bad(o)
	var hkind := str(host().battles.active.get(int(o.s().battle_id), {}).get("kind", "")) if o.s().battle_id != 0 else "-"
	if o.s().battle_id != 0:
		o.drive_battle("fight")
	# (c) 少林弟子殺善良 NPC（西夏街上的黃狗）→ 佛法 −1 級
	var m = _new_bot("沙彌")
	if m.err != "":
		return _bad(m)
	if not m.walk("sl_gate") or not m.must("join_sect", { "npc": "n_sl_zhike" }):
		return _bad(m)
	m.debug("skill:foxa", 10)
	if not m.walk("xx_street"):
		return _bad(m)
	m.refill()
	var fx0: int = int(m.ch().skills.level("foxa"))
	if not m.must("npc_attack", { "npc": "n_na_xx_huanggou" }):
		return _bad(m)
	var mres: String = m.drive_battle("fight")
	var fx1: int = int(m.ch().skills.level("foxa"))
	if not m.expect(mres == "VICTORY" and fx1 == fx0 - 1, "shaolin kills dog %s: foxa %d → %d" % [mres, fx0, fx1]):
		return _bad(m)
	m.advance(0.5)
	if m.s().battle_id != 0:
		m.drive_battle("flee")
	# (d) 星宿弟子對丁春秋下手 → 叛派
	var x = _new_bot("星徒")
	if x.err != "":
		return _bad(x)
	if not x.walk_until_region("xh_hall", "xingxiu"):
		return _bad(x)
	x.debug("morality", -150)
	if not x.walk("xh_hall") or not x.must("join_sect", { "npc": "n_xh_dingchunqiu" }):
		return _bad(x)
	x.refill()
	var nx: int = x.mark()
	if not x.must("npc_attack", { "npc": "n_xh_dingchunqiu" }):
		return _bad(x)
	if not x.expect(str(x.ch().sect) == "" and "xingxiu" in x.ch().sect_traitor,
			"after attacking 丁春秋: sect '%s' traitor %s" % [str(x.ch().sect), str(x.ch().sect_traitor)]):
		return _bad(x)
	var traitor_of: Array = x.fresh_sheet().get("traitor_of", [])
	if not x.expect(not x.last_ev("na_master_betray", nx).is_empty(), "no na_master_betray"):
		return _bad(x)
	x.drive_battle("flee")
	return _ok("(a) 武當 attacks 同門 → breach JAIL @ wd_siguo; (b) 滅派 menu → 3 護山, enemy_of 武當, hostile entry (%s); (c) 少林 kills dog → 佛法 %d→%d; (d) 星宿 attacks 丁春秋 → betrayed, traitor_of %s" % [hkind, fx0, fx1, str(traitor_of)])

# ------------------------------------------------------------------------ loot_rare
func _loot_rare(strict: bool) -> Dictionary:
	var a = _new_bot("尋寶")
	var c = _new_bot("聽聞")
	if a.err != "" or c.err != "":
		return _bad(a if a.err != "" else c)
	a.make_very_strong()
	if not a.debug("loot_force", "a_lt_hongshijie"):
		return _bad(a)
	var got := {}
	var tries := 0
	var res := ""
	while tries < 4:
		tries += 1
		a.refill()
		var nc: int = a.battle_closes.size()
		if not a.debug("battle_monster", "m_guiwang"):
			return _bad(a)
		res = a.drive_battle("fight")
		if res == "VICTORY" and a.battle_closes.size() > nc:
			var close: Variant = a.battle_closes[a.battle_closes.size() - 1]
			var items: Variant = (close.get("rewards", {}) as Dictionary).get("items", []) if close is Dictionary and close.get("rewards") is Dictionary else []
			for it in items:
				if it is Dictionary and str(it.get("id", "")) == "a_lt_hongshijie":
					got = it
			break
	if not a.expect(res == "VICTORY", "鬼王 battle %s after %d tries" % [res, tries]):
		return _bad(a)
	if strict:
		# M3c 審查：classic_strict 的 later_loot 關 → src later 的紅石戒（2004 17173）不掉，強制掉落也不行；沒有珍品就沒有傳聞
		if not a.expect(got.is_empty(), "classic_strict dropped a later-version item %s" % str(got)):
			return _bad(a)
		if not a.expect(a.last_ev("lt_rare_drop").is_empty(), "classic_strict: lt_rare_drop without a rare item"):
			return _bad(a)
	if not strict and not a.expect(not got.is_empty() and str(got.get("rarity", "")) == "TREASURE", "close.rewards.items hongshijie %s" % str(got)):
		return _bad(a)
	if not strict and not a.expect(not a.last_ev("lt_rare_drop").is_empty(), "no lt_rare_drop"):
		return _bad(a)
	c.advance(0.5)
	c.flush_view()
	var heard: bool = "lt_rmr_rare_drop" in _rumor_keys(c)
	if strict:
		if not c.expect(not heard, "classic_strict: C heard %s" % str(_rumor_keys(c))):
			return _bad(c)
		return _ok("classic_strict: 鬼王 with forced 紅石戒 (src later) → not dropped (later_loot off), no lt_rare_drop, no rumor to C")
	if not c.expect(heard, "C did not hear lt_rmr_rare_drop (rumors %s)" % str(_rumor_keys(c))):
		return _bad(c)
	return _ok("鬼王 (try %d) → 紅石戒 TREASURE in close.rewards.items; lt_rare_drop to A; C heard lt_rmr_rare_drop" % tries)

func _sc_loot_rare() -> Dictionary:
	return _loot_rare(false)

func _sc_loot_rare_strict() -> Dictionary:
	return _loot_rare(true)

# ------------------------------------------------------------------------ manual
func _sc_manual() -> Dictionary:
	var b = _new_bot("讀書")
	if b.err != "":
		return _bad(b)
	b.debug("combat_xp", 300000)
	b.debug("skill:basic_literacy", 0)
	if not b.debug("give_item", "bk_huqingniu:1"):
		return _bad(b)
	var uid: String = b.uid_of("bk_huqingniu")
	if not b.expect(uid != "", "no bk_huqingniu in bag"):
		return _bad(b)
	if not b.expect_reason("manual_read", { "item_uid": uid, "times": 1 }, "manual_illiterate"):
		return _bad(b)
	if not b.debug("skill:basic_literacy", 25):
		return _bad(b)
	# M3c 審查：研讀每次扣 1 學點（與自修同價）；先給夠，最後檢查真的扣了
	if not b.debug("learn_points", 100000):
		return _bad(b)
	var reads := 0
	var last := {}
	while reads < 6000:
		b.refill()
		last = b.send("manual_read", { "item_uid": uid, "times": 10 })
		if not last.get("ok", false):
			break
		reads += 1
	if not b.expect(str(last.get("reason", "")) == "manual_cap", "stopped with %s after %d reads" % [str(last), reads]):
		return _bad(b)
	var lv: int = int(b.ch().skills.level("basic_medic"))
	if not b.expect(lv == 25, "basic_medic %d (want 25 = 讀書識字)" % lv):
		return _bad(b)
	if not b.expect(b.uid_of("bk_huqingniu") == uid, "manual consumed"):
		return _bad(b)
	if not b.expect(not b.evs("lt_manual_read").is_empty(), "no lt_manual_read"):
		return _bad(b)
	var lp_spent: int = 100000 - int(b.ch().learn_points)
	if not b.expect(lp_spent > 0, "manual reads spent no learn points"):
		return _bad(b)
	return _ok("illiterate → manual_illiterate; 讀書識字 25 → basic_medic 25 after %d×10 reads (學點 −%d) → manual_cap; book kept" % [reads, lp_spent])

# ------------------------------------------------------------------------ equip8
func _sc_equip8() -> Dictionary:
	var b = _new_bot("八格")
	if b.err != "":
		return _bad(b)
	for it in ["a_lt_maozi", "a_lt_zhihuan", "a_lt_yushang"]:
		if not b.debug("give_item", it + ":1"):
			return _bad(b)
	var ap0 := int(b.ch().derived(host().tables, opts()).get("armor_power", 0))
	for it in ["a_lt_maozi", "a_lt_zhihuan"]:
		if not b.must("equip", { "item_uid": b.uid_of(it) }):
			return _bad(b)
	var sh: Dictionary = b.fresh_sheet()
	var eq: Dictionary = sh.get("equipped", {})
	if not b.expect(eq.size() == 8 and str(eq.get("HEAD", "")) != "" and str(eq.get("RING", "")) != "", "sheet.equipped %s" % str(eq)):
		return _bad(b)
	var ap1 := int(b.ch().derived(host().tables, opts()).get("armor_power", 0))
	if not b.expect(ap1 > ap0, "armor_power %d → %d" % [ap0, ap1]):
		return _bad(b)
	if not b.expect_reason("equip", { "item_uid": b.uid_of("a_lt_yushang") }, "req_gender"):
		return _bad(b)
	if not b.must("unequip", { "slot": "HEAD" }):
		return _bad(b)
	if not b.expect(str(b.ch().inventory.equipped.get("HEAD", "")) == "", "HEAD still equipped"):
		return _bad(b)
	var why := reload_world_all([b])
	if why != "":
		return _err(why)
	var eq2: Dictionary = b.ch().inventory.equipped
	if not b.expect(str(eq2.get("RING", "")) != "" and str(eq2.get("HEAD", "")) == "" and eq2.size() == 8, "after reload equipped %s" % str(eq2)):
		return _bad(b)
	return _ok("帽子+指環 equipped (armor %d→%d), 羽裳 → req_gender, unequip HEAD, 8 slots survive reload" % [ap0, ap1])

# ------------------------------------------------------------------------ divine_pvp
func _sc_divine_pvp() -> Dictionary:
	var a = _new_bot("神兵主", "xixia", "M", -1, false)
	var b = _new_bot("奪兵客")
	var c = _new_bot("旁聽客")
	for p in [a, b, c]:
		if p.err != "":
			return _bad(p)
	a.debug("combat_xp", 800)
	b.debug("combat_xp", 2000)
	if not a.debug("divine_grant", "w_sb_yitian"):
		return _bad(a)
	var uid: String = a.uid_of("w_sb_yitian")
	if not a.expect(uid != "", "A has no 倚天劍"):
		return _bad(a)
	if not a.must("equip", { "item_uid": uid }):
		return _bad(a)
	if not a.expect_reason("drop_item", { "item_uid": uid }, "divine_locked"):
		return _bad(a)
	if not a.walk("xx_smithy"):
		return _bad(a)
	var rs: Dictionary = a.send("sell", { "npc": "n_xx_smith", "item_uid": uid, "n": 1 })
	if not a.expect(not rs.get("ok", false), "sold 倚天劍: %s" % str(rs)):
		return _bad(a)
	var sell_reason := str(rs.get("reason", ""))
	for p in [a, b]:
		if not p.walk("xw_road"):
			return _bad(p)
	b.refill()
	a.refill()
	var na: int = a.mark()
	var nb: int = b.mark()
	if not b.must("force_pk", { "target": a.char_id }):
		return _bad(b)
	if not b.drive_pvp(_ws(), [b, a], ["fight", "defend"]):
		return _err("pvp battle did not end")
	_ws().advance(1.0)
	for p in [a, b, c]:
		p.flush_view()
	if not b.expect(b.uid_of("w_sb_yitian") != "" and a.uid_of("w_sb_yitian") == "", "after pvp: B has '%s', A has '%s'" % [b.uid_of("w_sb_yitian"), a.uid_of("w_sb_yitian")]):
		return _bad(b)
	var reg: Variant = _ws().world.get("divine", {})
	if not b.expect(reg is Dictionary and str((reg as Dictionary).get("w_sb_yitian", "")) == b.char_id, "world.divine %s" % str(reg)):
		return _bad(b)
	if not b.expect(not a.last_ev("lt_divine_transfer", na).is_empty() and not b.last_ev("lt_divine_transfer", nb).is_empty(), "lt_divine_transfer missing"):
		return _bad(b)
	if not c.expect("lt_rmr_divine_transfer" in _rumor_keys(c), "C rumors %s" % str(_rumor_keys(c))):
		return _bad(c)
	return _ok("倚天劍: drop → divine_locked, sell → %s; B force_pk A (defend to death) → sword to B, world.divine = B, both lt_divine_transfer, C heard lt_rmr_divine_transfer" % sell_reason)

# ------------------------------------------------------------------------ fx_snapshot
func _sc_fx_snapshot() -> Dictionary:
	var b = _new_bot("刀客")
	if b.err != "":
		return _bad(b)
	if not b.debug("give_item", "w_dandao:1") or not b.must("equip", { "item_uid": b.uid_of("w_dandao") }):
		return _bad(b)
	var n0: int = b.mark()
	if not b.debug("battle_monster", "m_wolf"):
		return _bad(b)
	var st: Dictionary = b.battle_state()
	var me: Dictionary = b.my_snapshot_unit(st)
	var foes := _foes(st)
	var wolf: Dictionary = foes[0] if not foes.is_empty() else {}
	if not b.expect(str(me.get("wtype", "")) == "BLADE" and wolf.has("wtype") and wolf.has("wfx"),
			"snapshot me.wtype %s wolf keys %s" % [str(me.get("wtype", "")), str(wolf.keys())]):
		return _bad(b)
	b.drive_battle("fight")
	var cats := _cats_since(b, n0)
	if not b.expect(cats.has(""), "plain attack events cat %s (want \"\")" % str(cats.keys())):
		return _bad(b)
	# 用刀法（debug 設血刀刀法等級）→ cat BLADE
	b.debug("skill:xd_daofa", 10)
	b.refill()
	var n1: int = b.mark()
	if not b.debug("battle_monster", "m_wolf"):
		return _bad(b)
	var ticks := 0
	var art_rejects := 0
	while b.s().battle_id != 0 and ticks < 20000:
		var bid: int = b.s().battle_id
		var entry: Dictionary = host().battles.active.get(bid, {})
		if entry.is_empty():
			break
		var bt = entry["battle"]
		var u = b._my_unit(bt)
		if u != null and str(u.state) == "READY":
			var cmd: Dictionary = b._choose_cmd(bt, u, "fight")
			if str(cmd.get("cmd", "")) == "ATTACK":
				cmd = { "cmd": "ART", "art": "xd_daofa", "move": "xd_df_1", "power_tenths": 10, "target": cmd["target"] }
			cmd["battle_id"] = bid
			var rr: Dictionary = b.send("battle_cmd", cmd)
			if not rr.get("ok", false):
				art_rejects += 1
				b.send("battle_cmd", { "battle_id": bid, "cmd": "DEFEND" })
		_ws().advance(0.1)
		ticks += 1
	_ws().advance(0.5)
	var cats2 := _cats_since(b, n1)
	if not b.expect(cats2.has("BLADE"), "blade-art events cat %s (want BLADE; ART rejects %d)" % [str(cats2.keys()), art_rejects]):
		return _bad(b)
	return _ok("snapshot me.wtype=BLADE, wolf wtype='%s' wfx='%s'; plain attack cat \"\"; 血刀刀法 cat BLADE" % [str(wolf.get("wtype", "")), str(wolf.get("wfx", ""))])
