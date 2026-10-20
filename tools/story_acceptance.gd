extends SceneTree
## 故事驗收（STORY_PLAN §9.2）。
##   godot --headless --path . --script res://tools/story_acceptance.gd -- --no-steam [--chain=q_yuner[,q_xuzhu]] [--branch=abao]
##         [--all] [--jobs-per-worker=3] [--workers=4] [--timeout=3600] [--only=duo|ambient|chains]
## 預設與 --all 相同：每條任務列的每一條 test_plan（＝每個結局至少一次，含各碎片寫的失敗／重試分支）＋雙人＋活的江湖。
## --chain／--branch 只跑指定任務／指定結局或分支（branch 比對 test_plan 的 outcome 與 branch 欄）。
##
## 作法：協調器（本檔，不帶 --story-worker）把工作分給數個 worker 子行程（同一個檔案帶 --story-worker），
## 每個 worker 在自己的行程裡用 WorldServer（--debug-intents、真的 GameHost 與全部系統）跑：
##   - 每條路徑：全新世界、新角色（出生城西夏／大理輪流）→ tests/bots/story_bot.gd 照 test_plan 走路、交談、選擇、戰鬥，
##     中途存檔→關主機→同一世界重開→選回角色→繼續；最後檢查結局、獎勵、旗標、武功、物品、傳聞、重複／冷卻。
##   - duo：tests/bots/story_duo_bot.gd 兩個玩家（appear 各自判斷、組隊打伏擊各自完成 FIGHT、兩人兩種結局、全服第一只發一次）。
##   - ambient：同檔的活的江湖劇本（白天交談即戰、夜裡惡人警告→不動→追擊戰不能逃、警告內離開脫身、新手免疫、傳聞列表）。
## 協調器收集每個 worker 的 STORY_JOB_OK／STORY_JOB_FAIL 行與 SCRIPT ERROR，印出每條鏈的結果、耗時、未覆蓋的結局。
## 成功印 STORY_ACCEPT_OK（結束碼 0）；失敗印 STORY_ACCEPT_FAIL（結束碼 1）。子行程一律 OS.kill()（含 _finalize）。
## 測試資料一律在 --data-root（預設 DataRoot.test_root()＝../JY-Mini-OL-Work/testdata）底下的 story_acceptance/<run>/，不碰玩家的存檔。

const STORY_BOT := "res://tests/bots/story_bot.gd"
const DUO_BOT := "res://tests/bots/story_duo_bot.gd"
const SPECIAL_JOBS := ["duo", "ambient"]

var _finished := false
var _timeout_s := 3600.0
var _root := ""
var _run_id := ""
var _dir := ""

# ---------------------------------------------------------------- 協調器
var _pids: Array[int] = []
var _logs: Dictionary = {}      # worker label -> log path
var _wjobs: Dictionary = {}     # worker label -> [job ids]
var _t0 := 0

# ---------------------------------------------------------------- worker
var _bots: Dictionary = {}      # peer -> bot

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
	_timeout_s = maxf(60.0, str(a.get("timeout", "3600")).to_float())
	_root = DataRoot.resolve_for_tool(CliArgs.current())
	if a.has("story-worker"):
		await _worker(a)
	else:
		await _coordinate(a)

func _say(msg: String) -> void:
	print("[story_acceptance %6.1fs] %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, msg])

## test_plan 全部（qid -> [plan]），依任務 id 排序
func all_plans() -> Dictionary:
	var out := {}
	var gd: Node = root.get_node("GameData")
	var qs: Dictionary = gd.loader.all_tables.get("quests", {}) if gd.loader != null else {}
	if qs.is_empty():
		qs = gd.tables.get("quests", {})
	var ids: Array = qs.keys()
	ids.sort()
	for qid in ids:
		var tp: Variant = qs[qid].get("test_plan", [])
		if tp is Array and not (tp as Array).is_empty():
			out[qid] = tp
	return out

static func job_id(qid: String, idx: int) -> String:
	return "%s#%d" % [qid, idx]

# ======================================================================== 協調器
func _coordinate(a: Dictionary) -> void:
	randomize()
	_run_id = "%04x" % (randi() % 0x10000)
	_dir = ProjectSettings.globalize_path(_root.path_join("story_acceptance/%s" % _run_id))
	DirAccess.make_dir_recursive_absolute(_dir)
	var plans := all_plans()
	var chains: Array = []
	if a.has("chain"):
		chains = str(a["chain"]).split(",", false)
	var branch := str(a.get("branch", ""))
	var only := str(a.get("only", ""))
	var jobs: Array = []
	var outcomes_all := {}      # qid -> { outcome: true }（資料宣告的結局）
	var outcomes_planned := {}  # qid -> { outcome: true }（有路徑的結局）
	for qid in plans:
		var row: Dictionary = root.get_node("GameData").tables.get("quests", {}).get(qid, {})
		var oc: Dictionary = {}
		for k in row.get("outcomes", {}):
			oc[str(k)] = true
		outcomes_all[qid] = oc
		if not chains.is_empty() and not (qid in chains):
			continue
		var tp: Array = plans[qid]
		for i in tp.size():
			var p: Dictionary = tp[i]
			outcomes_planned.get_or_add(qid, {})[str(p.get("outcome", ""))] = true
			if branch != "" and str(p.get("outcome", "")) != branch and str(p.get("branch", "")) != branch:
				continue
			jobs.append(job_id(qid, i))
	if only == "duo" or only == "ambient":
		jobs = [only]
	elif only != "chains" and chains.is_empty() and branch == "":
		jobs.append_array(SPECIAL_JOBS)
	if jobs.is_empty():
		_fail_out("no jobs (chain=%s branch=%s)" % [str(chains), branch])
		return
	# 宣告了但沒有任何路徑的結局 → 列為未覆蓋（全部跑時算失敗）
	var uncovered: PackedStringArray = []
	for qid in outcomes_all:
		for oc in outcomes_all[qid]:
			if not outcomes_planned.get(qid, {}).has(oc):
				uncovered.append("%s:%s" % [qid, oc])
	var n_workers := clampi(int(str(a.get("workers", "4"))), 1, 8)
	var per := maxi(1, ceili(float(jobs.size()) / float(n_workers)))
	if a.has("jobs-per-worker"):
		per = maxi(1, int(str(a["jobs-per-worker"])))
	# 重的工作（長鏈）先分出去
	var queue: Array = jobs.duplicate()
	_say("run=%s dir=%s jobs=%d workers<=%d per=%d" % [_run_id, _dir, jobs.size(), n_workers, per])
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var running: Dictionary = {}   # label -> pid
	var results: Dictionary = {}   # job -> line
	var wi := 0
	var deadline := Time.get_ticks_msec() + int(_timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		while not queue.is_empty() and running.size() < n_workers:
			var batch: Array = queue.slice(0, per)
			queue = queue.slice(per)
			wi += 1
			var label := "w%02d" % wi
			var log_path := _dir.path_join(label + ".log")
			_logs[label] = log_path
			_wjobs[label] = batch
			var args := PackedStringArray(["--headless", "--path", proj, "--log-file", log_path, "--script",
				"res://tools/story_acceptance.gd", "--", "--no-steam", "--debug-intents", "--story-worker",
				"--story-run=%s_%s" % [_run_id, label], "--jobs=" + ",".join(batch),
				"--timeout=%d" % int(_timeout_s), DataRoot.child_arg(_root)])
			var pid := OS.create_process(exe, args, false)
			if pid <= 0:
				_fail_out("spawn " + label)
				return
			_pids.append(pid)
			running[label] = pid
			_say("spawned %s pid=%d jobs=%s" % [label, pid, ",".join(batch)])
		await create_timer(0.5, true, false, true).timeout
		for label in running.keys():
			var wpid: int = running[label]
			if OS.is_process_running(wpid):
				continue
			running.erase(label)
			var txt := _log_text(label)
			for line in txt.split("\n"):
				if line.begins_with("STORY_JOB_OK ") or line.begins_with("STORY_JOB_FAIL "):
					var job := line.split(" ")[1]
					results[job] = line.strip_edges()
					_say(line.strip_edges())
			if txt.contains("SCRIPT ERROR"):
				for job in _wjobs[label]:
					if not str(results.get(job, "")).begins_with("STORY_JOB_FAIL"):
						results[job] = "STORY_JOB_FAIL %s SCRIPT ERROR in %s" % [job, _logs[label]]
				_dump(label, "SCRIPT ERROR")
			for job in _wjobs[label]:
				if not results.has(job):
					results[job] = "STORY_JOB_FAIL %s worker %s exited (code %d) without a result" % [job, label,
						OS.get_process_exit_code(wpid)]
					_dump(label, "")
		if queue.is_empty() and running.is_empty():
			break
	for label in running:
		OS.kill(running[label])
		for job in _wjobs[label]:
			if not results.has(job):
				results[job] = "STORY_JOB_FAIL %s timeout" % job
	# 報告
	var failed := 0
	print("")
	print("==== 故事驗收 run=%s ====" % _run_id)
	for job in jobs:
		var line := str(results.get(job, "STORY_JOB_FAIL %s missing" % job))
		if line.begins_with("STORY_JOB_FAIL"):
			failed += 1
		print(("PASS  " if line.begins_with("STORY_JOB_OK") else "FAIL  ") + line.substr(line.find(" ") + 1))
	if not uncovered.is_empty():
		print("未覆蓋的結局（沒有任何 test_plan）：" + ", ".join(uncovered))
	if not uncovered.is_empty() and chains.is_empty() and branch == "" and only == "":
		failed += uncovered.size()
	var elapsed := (Time.get_ticks_msec() - _t0) / 1000.0
	if failed == 0:
		print("STORY_ACCEPT_OK run=%s jobs=%d elapsed=%.0fs" % [_run_id, jobs.size(), elapsed])
		_finish(0)
	else:
		print("STORY_ACCEPT_FAIL run=%s failed=%d/%d elapsed=%.0fs" % [_run_id, failed, jobs.size(), elapsed])
		_finish(1)

func _log_text(label: String) -> String:
	var p: String = _logs.get(label, "")
	if p == "" or not FileAccess.file_exists(p):
		return ""
	return FileAccess.get_file_as_string(p)

func _dump(label: String, needle: String) -> void:
	var lines := _log_text(label).split("\n")
	print("----- %s (%s) -----" % [label, _logs.get(label, "")])
	if needle != "":
		for i in lines.size():
			if lines[i].contains(needle):
				print("\n".join(lines.slice(maxi(0, i - 3), mini(lines.size(), i + 12))))
				return
	print("\n".join(lines.slice(maxi(0, lines.size() - 40))))

func _fail_out(msg: String) -> void:
	print("STORY_ACCEPT_FAIL " + msg)
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
	var run := str(a.get("story-run", "x"))
	randomize()
	DataRoot.override_for_tests(_root)
	root.get_node("SaveManager").root_dir = _root.path_join("story_acceptance/worlds")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_root.path_join("story_acceptance/worlds")))
	var ws := _ws()
	ws.debug_intents = true
	ws.set_time_scale(1.0)
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	root.get_node("ClientState").capture_remote = _capture
	var plans := all_plans()
	var jobs: Array = str(a.get("jobs", "")).split(",", false)
	var all_ok := true
	var n := 0
	for job in jobs:
		n += 1
		var t0 := Time.get_ticks_msec()
		var world := ("st_%s_%d" % [run, n]).replace("#", "_")
		var res := {}
		if job == "duo" or job == "ambient":
			var duo = load(DUO_BOT).new(ws, self)
			res = duo.run(job, world)
		else:
			res = _run_chain(job, world, plans, n)
		if ws.running:
			ws.stop()
		_bots.clear()
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		if bool(res.get("ok", false)):
			print("STORY_JOB_OK %s %.1fs %s" % [job, secs, str(res.get("info", ""))])
		else:
			all_ok = false
			print("STORY_JOB_FAIL %s %.1fs %s" % [job, secs, str(res.get("err", "?"))])
		await process_frame
	root.get_node("ClientState").capture_remote = Callable()
	quit(0 if all_ok else 1)

## 世界與玩家（story_duo_bot 也用）
func start_world(world: String, seed_v: int) -> bool:
	var ws := _ws()
	if ws.running:
		ws.stop()
	if ws.start(world) != OK:
		push_error("[story_acceptance] start %s: %s" % [world, str(ws.last_error)])
		return false
	ws.rng.seed = seed_v
	return true

## 角色名在整個資料根目錄唯一（name_taken）：前綴 + 3 個隨機天干地支字
const NAME_CHARS := "甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉戌亥春夏秋冬東南西北"
func unique_name(prefix: String) -> String:
	var out := prefix
	for i in 4:
		out += NAME_CHARS[randi() % NAME_CHARS.length()]
	return out

func new_bot(peer: int, char_name: String, label: String):
	var b = load(STORY_BOT).new(_ws(), peer, char_name, label)
	_bots[peer] = b
	return b

func _run_chain(job: String, world: String, plans: Dictionary, n: int) -> Dictionary:
	var i := job.find("#")
	var qid := job.substr(0, i)
	var idx := int(job.substr(i + 1))
	var tp: Array = plans.get(qid, [])
	if idx < 0 or idx >= tp.size():
		return { "ok": false, "err": "no plan " + job }
	var plan: Dictionary = tp[idx]
	if not start_world(world, hash(job)):
		return { "ok": false, "err": "world start failed" }
	var b = new_bot(100, unique_name("驗"), job)
	b.city = "dali" if idx % 2 == 1 else "xixia"
	if not b.create_char():
		return { "ok": false, "err": b.err }
	b.say("plan %s outcome=%s branch=%s city=%s" % [job, str(plan.get("outcome", "")), str(plan.get("branch", "")), b.city])
	var ok: bool = b.run_plan(plan, plans, true)
	if not ok or b.err != "":
		return { "ok": false, "err": b.err }
	var info := "outcome=%s reloads=%d moves=%d battles=%d" % [str(plan.get("outcome", "")), b.reloads, b.moves,
		b.battle_results.size()]
	if not b.notes.is_empty():
		info += " notes=" + "; ".join(b.notes)
	return { "ok": true, "info": info }
