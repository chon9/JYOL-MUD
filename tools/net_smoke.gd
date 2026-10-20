extends SceneTree
## 連線冒煙測試（TECH_ARCH 15.1、15.2）：開 1 個 ENet 主機 + 2 個 bot 客戶端（OS.create_process，--headless），
## 驗證聊天經由主機轉送到每個 bot。結束時（含失敗、逾時）一律 OS.kill 所有子程序。
## godot --headless --path . --script res://tools/net_smoke.gd -- --no-steam [--timeout=60] [--keep-logs]

const BOT_COUNT := 2

var _pids: Array[int] = []
var _logs: Dictionary = {}      # label -> log path
var _root := ""                 # 測試資料根目錄（--data-root；預設 DataRoot.test_root()＝../JY-Mini-OL-Work/testdata）
var _finished := false
var _timeout_s := 60.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--timeout="):
			_timeout_s = maxf(10.0, a.substr(10).to_float())
	# 看門狗：不論 _run 發生什麼事，時間到一定清掉子程序並結束
	create_timer(_timeout_s + 15.0, true, false, true).timeout.connect(func():
		print("[net_smoke] watchdog fired")
		_finish(1))
	_run.call_deferred()

func _finalize() -> void:
	_kill_all()

func _run() -> void:
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://").trim_suffix("/")
	_root = DataRoot.resolve_for_tool(CliArgs.current())
	var log_dir := ProjectSettings.globalize_path(_root.path_join("net_smoke"))
	DirAccess.make_dir_recursive_absolute(log_dir)
	randomize()
	var port := 25000 + randi() % 5000
	var child_quit := str(int(_timeout_s + 10.0))
	print("[net_smoke] godot=%s project=%s port=%d" % [exe, proj, port])

	var host_pid := _spawn(exe, proj, log_dir, "host", [
		"--no-steam", "--enet-host", "--port=%d" % port, "--world=net_smoke",
		"--profile=smoke_host", "--name=主機", "--quit-after=" + child_quit])
	if host_pid <= 0:
		_finish(1)
		return
	if not await _wait_for_log("host", "ENet 主機", 15.0):
		print("[net_smoke] host did not come up")
		_dump_logs()
		_finish(1)
		return

	var bot_pids: Array[int] = []
	for i in BOT_COUNT:
		var label := "bot%d" % (i + 1)
		var pid := _spawn(exe, proj, log_dir, label, [
			"--no-steam", "--enet-join=127.0.0.1:%d" % port, "--bot",
			"--bot-expect=%d" % (BOT_COUNT + 1), "--bot-chats=%d" % BOT_COUNT,
			"--profile=smoke_" + label, "--name=" + label, "--quit-after=" + child_quit])
		if pid <= 0:
			_finish(1)
			return
		bot_pids.append(pid)

	var deadline := Time.get_ticks_msec() + int(_timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var running := 0
		for pid in bot_pids:
			if OS.is_process_running(pid):
				running += 1
		if running == 0:
			break
		await create_timer(0.25, true, false, true).timeout

	var ok := true
	for i in bot_pids.size():
		var pid := bot_pids[i]
		var label := "bot%d" % (i + 1)
		if OS.is_process_running(pid):
			print("[net_smoke] %s timed out" % label)
			ok = false
			continue
		var code := OS.get_process_exit_code(pid)
		var saw_ok := _log_text(label).contains("BOT_OK")
		print("[net_smoke] %s exit=%d BOT_OK=%s" % [label, code, saw_ok])
		if code != 0 or not saw_ok:
			ok = false
	if not OS.is_process_running(host_pid):
		print("[net_smoke] host exited early (code %d)" % OS.get_process_exit_code(host_pid))
		ok = false
	var host_log := _log_text("host")
	var joined := host_log.count("session joined")
	print("[net_smoke] host sessions joined: %d (expected %d)" % [joined, BOT_COUNT + 1])
	if joined < BOT_COUNT + 1:
		ok = false
	if not ok:
		_dump_logs()
	print("[net_smoke] %s" % ("PASS" if ok else "FAIL"))
	_finish(0 if ok else 1)

func _spawn(exe: String, proj: String, log_dir: String, label: String, user_args: Array) -> int:
	var log_path := log_dir.path_join("%s.log" % label)
	if FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(log_path)
	_logs[label] = log_path
	var args := PackedStringArray(["--headless", "--path", proj, "--log-file", log_path, "--"])
	args.append_array(PackedStringArray(user_args))
	args.append(DataRoot.child_arg(_root))
	var pid := OS.create_process(exe, args, false)
	if pid <= 0:
		print("[net_smoke] failed to spawn " + label)
	else:
		_pids.append(pid)
		print("[net_smoke] spawned %s pid=%d" % [label, pid])
	return pid

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

func _dump_logs() -> void:
	for label in _logs:
		print("----- %s (%s) -----" % [label, _logs[label]])
		var lines := _log_text(label).split("\n")
		print("\n".join(lines.slice(maxi(0, lines.size() - 40))))

func _kill_all() -> void:
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
			print("[net_smoke] killed pid %d" % pid)
	_pids.clear()

func _finish(code: int) -> void:
	if _finished:
		return
	_finished = true
	_kill_all()
	quit(code)
