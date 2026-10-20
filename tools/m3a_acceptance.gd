extends SceneTree
## M3a 驗收指揮（M3A_PLAN 10.3）：1 個 ENet 專用主機（--debug-intents、全新世界、預設規則 classic_standard、--time-scale=20）
## + 每個劇本一個 tests/bots/m3a_sect_bot.gd 客戶端（同時跑）：8 派（創角 → 走路到山門 → 偵察 → 拜師 → 學藝 → 切磋用招式與指令）、
## 星宿叛派、武當公敵被抓、少林坐牢（jail）。
## godot --headless --path . --script res://tools/m3a_acceptance.gd -- --no-steam [--sect=emei[,jail]] [--timeout=2400]
##       [--time-scale=20] [--keep-logs]
## 成功印 M3A_ACCEPT_OK（結束碼 0）；失敗印 M3A_ACCEPT_FAIL <步驟> <原因>（結束碼 1）。所有子程序一律 OS.kill()（含 _finalize）。
## 陣（3 人）：tests/unit/test_battle_formation.gd、balance_sim formation3_bonus；十八銅人：test_world_sect.gd（M3A_PLAN 10.3）。

const ALL_ROLES := ["wudang", "emei", "hengshan", "quanzhen", "gumu", "lingjiu", "xingxiu", "xuedao", "jail"]
const BOT := "res://tests/bots/m3a_sect_bot.gd"
const MAX_CONCURRENT := 7

var _pids: Array[int] = []
var _logs: Dictionary = {}
var _finished := false
var _timeout_s := 2400.0
var _time_scale := 20.0
var _roles: Array = ALL_ROLES.duplicate()
var _run_id := ""
var _dir := ""
var _root := ""             # 測試資料根目錄（--data-root；預設 DataRoot.test_root()＝../JY-Mini-OL-Work/testdata），主機與 bot 都帶同一個
var _sync := ""
var _exe := ""
var _proj := ""
var _port := 0
var _host_pid := 0
var _bot_pids: Dictionary = {}
var _t0 := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--timeout="):
			_timeout_s = maxf(60.0, a.substr(10).to_float())
		elif a.begins_with("--time-scale="):
			_time_scale = clampf(a.substr(13).to_float(), 1.0, 50.0)
		elif a.begins_with("--sect="):
			_roles = []
			for r in a.substr(7).split(",", false):
				if r in ALL_ROLES:
					_roles.append(r)
	create_timer(_timeout_s + 30.0, true, false, true).timeout.connect(func():
		_say("watchdog fired")
		_dump_logs()
		_fail_out("watchdog", "timeout", 1))
	_run.call_deferred()

func _finalize() -> void:
	_kill_all()

func _say(msg: String) -> void:
	print("[m3a_acceptance %6.1fs] %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, msg])

func _run() -> void:
	_t0 = Time.get_ticks_msec()
	if _roles.is_empty():
		_fail_out("args", "no valid --sect", 1)
		return
	randomize()
	_run_id = "%04x" % (randi() % 0x10000)
	_exe = OS.get_executable_path()
	_proj = ProjectSettings.globalize_path("res://").trim_suffix("/")
	_root = DataRoot.resolve_for_tool(CliArgs.current())
	_dir = ProjectSettings.globalize_path(_root.path_join("m3a_acceptance/%s" % _run_id))
	_sync = _dir.path_join("sync")
	DirAccess.make_dir_recursive_absolute(_sync)
	_port = 25000 + randi() % 5000
	_say("run=%s port=%d dir=%s time_scale=%.1f roles=%s" % [_run_id, _port, _dir, _time_scale, str(_roles)])
	if not await _start_host():
		_fail_out("host", "did not come up", 1)
		return
	# 主機最多 8 個連線（NetworkManager.ENET_MAX_CLIENTS、max_players）：同時最多 MAX_CONCURRENT 個 bot，跑完一個補一個
	var pending: Array = _roles.duplicate()
	var deadline := Time.get_ticks_msec() + int(_timeout_s * 1000.0)
	var reported := {}
	while Time.get_ticks_msec() < deadline:
		while not pending.is_empty() and _bot_pids.size() - reported.size() < MAX_CONCURRENT:
			var r: String = pending.pop_front()
			if _spawn_bot(r) <= 0:
				_fail_out("spawn", "bot " + r, 1)
				return
			await create_timer(0.5, true, false, true).timeout
		await create_timer(0.5, true, false, true).timeout
		if _finished:
			return
		if not OS.is_process_running(_host_pid):
			_dump_logs()
			_fail_out("host", "exited unexpectedly (code %d)" % OS.get_process_exit_code(_host_pid), 1)
			return
		var running := 0
		for label in _bot_pids:
			var pid: int = _bot_pids[label]
			if OS.is_process_running(pid):
				running += 1
				continue
			if reported.has(label):
				continue
			reported[label] = true
			var code := OS.get_process_exit_code(pid)
			if code != 0 or not _log_text(label).contains("M3A_BOT_OK role=" + label):
				_dump_logs([label, "host"])
				_fail_out(label, _bot_line(label, "M3A_BOT_FAIL"), 1)
				return
			_say("%s done: %s" % [label, _bot_line(label, "M3A_BOT_OK")])
		if running == 0 and pending.is_empty():
			break
	if Time.get_ticks_msec() >= deadline:
		_dump_logs()
		_fail_out("timeout", "bots still running: %s" % str(_bot_pids.keys().filter(func(l): return OS.is_process_running(_bot_pids[l]))), 1)
		return
	# 查看迎戰（使用者要的偵察流程）至少一個 bot 實際迎戰過
	var accepted := 0
	for label in _bot_pids:
		if _bot_line(label, "M3A_BOT_OK").contains("scout_accepted=true"):
			accepted += 1
	_say("scout accepted by %d/%d bots" % [accepted, _bot_pids.size()])
	if accepted == 0 and _roles.size() >= 3:
		_fail_out("scout", "no bot ever accepted a scouted fight", 1)
		return
	_touch("host.stop")
	if not await _wait_exit(_host_pid, 30.0):
		_fail_out("host", "did not stop after host.stop", 1)
		return
	var bad := _script_errors()
	if bad != "":
		_dump_logs()
		_fail_out("logs", "SCRIPT ERROR in " + bad, 1)
		return
	_say("all bots M3A_BOT_OK; logs clean")
	print("M3A_ACCEPT_OK run=%s roles=%d elapsed=%.0fs" % [_run_id, _roles.size(), (Time.get_ticks_msec() - _t0) / 1000.0])
	_finish(0)

# ---------- 主機 ----------
func _start_host() -> bool:
	var args := ["--no-steam", "--dedicated", "--enet-host", "--port=%d" % _port, "--world=m3a_accept_" + _run_id,
		"--debug-intents", "--rule-preset=classic_standard", "--time-scale=%s" % str(_time_scale),
		"--stop-file=" + _sync.path_join("host.stop"), "--quit-after=%d" % int(_timeout_s + 60.0)]
	_host_pid = _spawn("host", args)
	if _host_pid <= 0:
		return false
	if not await _wait_for_log("host", "ENet 主機", 30.0):
		_dump_logs()
		return false
	_say("host up (pid %d)" % _host_pid)
	return true

func _spawn_bot(r: String) -> int:
	var args := ["--no-steam", "--enet-join=127.0.0.1:%d" % _port, "--profile=m3a_%s_%s" % [r, _run_id],
		"--name=" + r, "--bot=" + BOT, "--m3a-role=" + r, "--m3a-run=" + _run_id, "--m3a-sync=" + _sync,
		"--quit-after=%d" % int(_timeout_s + 30.0)]
	var pid := _spawn(r, args)
	if pid > 0:
		_bot_pids[r] = pid
	return pid

func _bot_line(label: String, prefix: String) -> String:
	for line in _log_text(label).split("\n"):
		if line.begins_with(prefix):
			return line.strip_edges()
	return "(no %s line; exit %d)" % [prefix, OS.get_process_exit_code(_bot_pids.get(label, 0))]

func _touch(name: String) -> void:
	var f := FileAccess.open(_sync.path_join(name), FileAccess.WRITE)
	if f != null:
		f.store_string("1")
		f.close()

# ---------- 程序 ----------
func _spawn(label: String, user_args: Array) -> int:
	var log_path := _dir.path_join("%s.log" % label)
	if FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(log_path)
	_logs[label] = log_path
	var args := PackedStringArray(["--headless", "--path", _proj, "--log-file", log_path, "--"])
	args.append_array(PackedStringArray(user_args))
	args.append(DataRoot.child_arg(_root))
	var pid := OS.create_process(_exe, args, false)
	if pid <= 0:
		_say("failed to spawn " + label)
	else:
		_pids.append(pid)
		_say("spawned %s pid=%d" % [label, pid])
	return pid

func _wait_exit(pid: int, secs: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not OS.is_process_running(pid):
			return true
		await create_timer(0.2, true, false, true).timeout
	return false

func _log_text(label: String) -> String:
	var p: String = _logs.get(label, "")
	if p == "" or not FileAccess.file_exists(p):
		return ""
	return FileAccess.get_file_as_string(p)

func _wait_for_log(label: String, needle: String, secs: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _log_text(label).contains(needle):
			return true
		await create_timer(0.2, true, false, true).timeout
	return false

func _script_errors() -> String:
	var out: PackedStringArray = []
	for label in _logs:
		if _log_text(label).contains("SCRIPT ERROR"):
			out.append(label)
	return ", ".join(out)

func _dump_logs(only: Array = []) -> void:
	for label in _logs:
		if not only.is_empty() and not (label in only):
			continue
		print("----- %s (%s) -----" % [label, _logs[label]])
		var lines := _log_text(label).split("\n")
		print("\n".join(lines.slice(maxi(0, lines.size() - 50))))

func _kill_all() -> void:
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
			print("[m3a_acceptance] killed pid %d" % pid)
	_pids.clear()

func _fail_out(where: String, reason: String, code: int) -> void:
	if _finished:
		return
	print("M3A_ACCEPT_FAIL %s %s" % [where, reason])
	_finish(code)

func _finish(code: int) -> void:
	if _finished:
		return
	_finished = true
	_kill_all()
	quit(code)
