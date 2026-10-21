extends SceneTree
## M3d 驗收（M3D_PLAN §10.3）。
##   godot --headless --path . --script res://tools/m3d_acceptance.gd -- --no-steam [--only=bounty[,combo]] [--workers=4] [--timeout=2400]
## 劇本：bounty bounty_friends hunters cleanse pk_decay dodge_qing combo equip_cd night arts_chains intimidate qz_gumu
##       jiebiao rob tourney sect_tourney errands town_lp heilongtan spar_bug strict_events（§10.3 表＋審查第三輪，一個劇本一個 worker）。
##
## 作法照 tools/m3c2_acceptance.gd：協調器（本檔，不帶 --m3d-worker）每個劇本開一個 worker 子行程（同一個檔案帶
## --m3d-worker）；worker 在自己的行程裡用整合測試的世界夾具（tools/m3d_accept_scenarios.gd：真的 WorldServer＋GameHost、
## 全部系統、intent 路徑；本機 peer 1＋假的遠端 peer＝兩個以上角色的劇本），每個劇本一個全新世界（測試根目錄 test_tmp/）。
## arts_chains 另外在 worker 裡呼叫 tools/story_acceptance.gd --chain=<q_ar_* 六條>（同 §10.3「用 story_acceptance 的方式」）。
## 成功印 M3D_ACCEPT_OK（結束碼 0）；失敗印 M3D_ACCEPT_FAIL <劇本> <原因> 並傾印 log 尾端（結束碼 1）。
## log 在 <測試根目錄>/m3d_acceptance/<run>/；不論成敗所有子程序 OS.kill()。不碰擁有者存檔、不寫 C:。

const SCEN := "res://tools/m3d_accept_scenarios.gd"
const SCENARIOS := ["bounty", "bounty_friends", "hunters", "cleanse", "pk_decay", "dodge_qing", "combo", "equip_cd", "night",
	"arts_chains", "intimidate", "qz_gumu", "jiebiao", "rob", "tourney", "sect_tourney", "errands", "town_lp", "heilongtan",
	"spar_bug", "strict_events"]
const ARTS_CHAINS := ["q_ar_qz_chongyang", "q_ar_qz_kongming", "q_ar_lj_bahuang", "q_ar_xh_muding", "q_ar_em_luosha",
	"q_ar_xd_xuemo"]

var _finished := false
var _timeout_s := 2400.0
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
	_timeout_s = maxf(60.0, str(a.get("timeout", "2400")).to_float())
	_root = DataRoot.resolve_for_tool(CliArgs.current())
	if a.has("m3d-worker"):
		await _worker(a)
	else:
		await _coordinate(a)

func _say(msg: String) -> void:
	print("[m3d_acceptance %6.1fs] %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, msg])

# ======================================================================== 協調器
func _coordinate(a: Dictionary) -> void:
	randomize()
	_run_id = "%04x" % (randi() % 0x10000)
	_dir = ProjectSettings.globalize_path(_root.path_join("m3d_acceptance/%s" % _run_id))
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
				"res://tools/m3d_acceptance.gd", "--", "--no-steam", "--debug-intents", "--m3d-worker",
				"--m3d-run=%s" % _run_id, "--job=" + job, DataRoot.child_arg(_root)])
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
				if line.begins_with("M3D_JOB_OK ") or line.begins_with("M3D_JOB_FAIL "):
					results[job] = line.strip_edges()
					_say(line.strip_edges())
			if txt.contains("SCRIPT ERROR"):
				results[job] = "M3D_JOB_FAIL %s SCRIPT ERROR in %s" % [job, _logs[job]]
			if not results.has(job):
				results[job] = "M3D_JOB_FAIL %s worker exited (code %d) without a result" % [job, OS.get_process_exit_code(wpid)]
			if str(results[job]).begins_with("M3D_JOB_FAIL"):
				_dump(job)
		if queue.is_empty() and running.is_empty():
			break
	for job in running:
		OS.kill(running[job])
		if not results.has(job):
			results[job] = "M3D_JOB_FAIL %s timeout" % job
			_dump(job)
	print("")
	print("==== M3d 驗收 run=%s ====" % _run_id)
	var failed: Array = []
	for job in jobs:
		var line := str(results.get(job, "M3D_JOB_FAIL %s missing" % job))
		print(("PASS  " if line.begins_with("M3D_JOB_OK") else "FAIL  ") + line.substr(line.find(" ") + 1))
		if not line.begins_with("M3D_JOB_OK"):
			failed.append(line)
	var elapsed := (Time.get_ticks_msec() - _t0) / 1000.0
	if failed.is_empty():
		print("M3D_ACCEPT_OK run=%s scenarios=%d elapsed=%.0fs" % [_run_id, jobs.size(), elapsed])
		_finish(0)
	else:
		for f in failed:
			print("M3D_ACCEPT_FAIL " + str(f).substr(str(f).find(" ") + 1))
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
	print("M3D_ACCEPT_FAIL " + msg)
	_finish(1)

func _finish(code: int) -> void:
	if _finished:
		return
	_finished = true
	_finalize()
	quit(code)

# ======================================================================== worker
func _worker(a: Dictionary) -> void:
	var run := str(a.get("m3d-run", "x"))
	var job := str(a.get("job", ""))
	randomize()
	DataRoot.override_for_tests(_root)
	if root.has_node("SaveManager"):
		root.get_node("SaveManager").root_dir = _root
	var t0 := Time.get_ticks_msec()
	var sc: RefCounted = load(SCEN).new()
	sc.tree = self
	sc.world_name = "m3d_%s_%s" % [run, job]
	sc.current_test = job
	var fn := "sc_" + job
	if job == "arts_chains":
		fn = "sc_arts_1_0a"
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
	if ok and job == "arts_chains":
		var r := _story_chains()
		ok = bool(r["ok"])
		if ok:
			info += "；" + str(r["info"])
		else:
			err = str(r["info"])
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	if ok:
		print("M3D_JOB_OK %s %.1fs %s" % [job, secs, info])
	else:
		print("M3D_JOB_FAIL %s %.1fs %s" % [job, secs, err])
	if root.has_node("NetworkManager"):
		root.get_node("NetworkManager").leave(true)
	await process_frame
	quit(0 if ok else 1)

## story_acceptance --chain=<q_ar_* 六條>（它自己開 worker、全新世界）；回 { ok, info }
func _story_chains() -> Dictionary:
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var out: Array = []
	var args := PackedStringArray(["--headless", "--path", proj, "--script", "res://tools/story_acceptance.gd", "--",
		"--no-steam", "--chain=" + ",".join(ARTS_CHAINS), DataRoot.child_arg(_root)])
	var code := OS.execute(exe, args, out, true)
	var txt := "\n".join(out)
	for line in txt.split("\n"):
		if line.begins_with("STORY_ACCEPT_OK"):
			return { "ok": true, "info": line.strip_edges() }
	var tail := txt.split("\n")
	return { "ok": false, "info": "story_acceptance --chain exit %d: %s" % [code, " / ".join(tail.slice(maxi(0, tail.size() - 15)))] }
