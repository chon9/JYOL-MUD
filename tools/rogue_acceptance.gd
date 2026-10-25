extends SceneTree
## 江湖試煉驗收（ROGUE_PLAN §9.3）【設計提案・非原作】。只跑 headless（U2）。
##   godot --headless --path . --script res://tools/rogue_acceptance.gd -- --no-steam [--only=start_run,lose_run] [--workers=4] [--timeout=1800]
## 劇本：start_run pick_each_kind win_round ally_acts lose_run points_persist boss_round abandon determinism mud_unaffected
##
## 作法照 tools/m3d_acceptance.gd：協調器（本檔，不帶 --rogue-worker）每個劇本開一個 worker 子行程（同一個檔案帶
## --rogue-worker）；worker 用 tools/rogue_accept_scenarios.gd（真的 WorldServer.start_rogue＋GameHost、--debug-intents、
## 測試根目錄下的新資料夾；mud_unaffected 先開一個 MUD 世界 w_rg_mud）。
## 成功印 ROGUE_ACCEPT_OK（結束碼 0）；失敗印 ROGUE_ACCEPT_FAIL <劇本> <原因> 並傾印 log 尾端（結束碼 1）。
## log 在 <測試根目錄>/rogue_acceptance/<run>/；不論成敗只 OS.kill() 自己開的子程序 PID。不碰擁有者存檔、不寫 C:。

const SCEN := "res://tools/rogue_accept_scenarios.gd"
const SCENARIOS := ["start_run", "pick_each_kind", "win_round", "ally_acts", "lose_run", "points_persist", "boss_round",
	"abandon", "determinism", "mud_unaffected"]

var _finished := false
var _timeout_s := 1800.0
var _root := ""
var _run_id := ""
var _dir := ""
var _pids: Array[int] = []
var _logs: Dictionary = {}
var _t0 := 0

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
	_timeout_s = maxf(60.0, str(a.get("timeout", "1800")).to_float())
	_root = DataRoot.resolve_for_tool(CliArgs.current())
	if a.has("rogue-worker"):
		await _worker(a)
	else:
		await _coordinate(a)

func _say(msg: String) -> void:
	print("[rogue_acceptance %6.1fs] %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, msg])

# ======================================================================== 協調器
func _coordinate(a: Dictionary) -> void:
	randomize()
	_run_id = "%04x" % (randi() % 0x10000)
	_dir = ProjectSettings.globalize_path(_root.path_join("rogue_acceptance/%s" % _run_id))
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
				"res://tools/rogue_acceptance.gd", "--", "--no-steam", "--debug-intents", "--rogue-worker",
				"--rogue-run=%s" % _run_id, "--job=" + job, DataRoot.child_arg(_root)])
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
				if line.begins_with("ROGUE_JOB_OK ") or line.begins_with("ROGUE_JOB_FAIL "):
					results[job] = line.strip_edges()
					_say(line.strip_edges())
			if txt.contains("SCRIPT ERROR"):
				results[job] = "ROGUE_JOB_FAIL %s SCRIPT ERROR in %s" % [job, _logs[job]]
			if not results.has(job):
				results[job] = "ROGUE_JOB_FAIL %s worker exited (code %d) without a result" % [job, OS.get_process_exit_code(wpid)]
			if str(results[job]).begins_with("ROGUE_JOB_FAIL"):
				_dump(job)
		if queue.is_empty() and running.is_empty():
			break
	for job in running:
		OS.kill(running[job])
		if not results.has(job):
			results[job] = "ROGUE_JOB_FAIL %s timeout" % job
			_dump(job)
	print("")
	print("==== 江湖試煉驗收 run=%s ====" % _run_id)
	var failed: Array = []
	for job in jobs:
		var line := str(results.get(job, "ROGUE_JOB_FAIL %s missing" % job))
		print(("PASS  " if line.begins_with("ROGUE_JOB_OK") else "FAIL  ") + line.substr(line.find(" ") + 1))
		if not line.begins_with("ROGUE_JOB_OK"):
			failed.append(line)
	var elapsed := (Time.get_ticks_msec() - _t0) / 1000.0
	if failed.is_empty():
		print("ROGUE_ACCEPT_OK run=%s scenarios=%d elapsed=%.0fs" % [_run_id, jobs.size(), elapsed])
		_finish(0)
	else:
		for f in failed:
			print("ROGUE_ACCEPT_FAIL " + str(f).substr(str(f).find(" ") + 1))
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
	print("ROGUE_ACCEPT_FAIL " + msg)
	_finish(1)

func _finish(code: int) -> void:
	if _finished:
		return
	_finished = true
	_finalize()
	quit(code)

# ======================================================================== worker
func _worker(a: Dictionary) -> void:
	var run := str(a.get("rogue-run", "x"))
	var job := str(a.get("job", ""))
	randomize()
	DataRoot.override_for_tests(_root)
	if root.has_node("SaveManager"):
		root.get_node("SaveManager").root_dir = _root
	var t0 := Time.get_ticks_msec()
	var sc: RefCounted = load(SCEN).new()
	sc.tree = self
	sc.world_name = "rg_%s_%s" % [run, job]
	sc.current_test = job
	var fn := "sc_" + job
	var ok := true
	var err := ""
	if not sc.has_method(fn):
		ok = false
		err = "no scenario " + fn
	else:
		await sc.call("before_each")
		if sc.failures.is_empty():
			await sc.call(fn)
		await sc.call("after_each")
		if not sc.failures.is_empty():
			ok = false
			err = " | ".join(sc.failures)
	var info := str(sc.get("info"))
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	if ok:
		print("ROGUE_JOB_OK %s %.1fs %s" % [job, secs, info])
	else:
		print("ROGUE_JOB_FAIL %s %.1fs %s" % [job, secs, err])
	if root.has_node("NetworkManager"):
		root.get_node("NetworkManager").leave(true)
	await process_frame
	quit(0 if ok else 1)
