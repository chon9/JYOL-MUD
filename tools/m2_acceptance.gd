extends SceneTree
## M2 驗收指揮（M2_PLAN 6.3）：1 個 ENet 專用主機 + 4 個 m2_party_bot（leader／member／pker／victim）。
## 組隊、隊伍頻道／密語／謠言、一起打山賊頭目（第 4 人中途加入）、叫戰被拒、強制 PK、屍體授權撿取、
## 飛鴿傳書（離線與在線收件）、主機以 --stop-file 關閉再重開後世界完整恢復。
## godot --headless --path . --script res://tools/m2_acceptance.gd -- --no-steam [--timeout=1500] [--keep-logs] [--time-scale=5]
## 預設 --time-scale=5（M2 審查：10 倍時屍體 1800 世界秒＝180 真實秒，一次 186 秒的執行只剩不到一成餘裕，
## 屍體可能在重開前就自然消失、造成假失敗；5 倍時屍體活 360 真實秒、保護期 120 真實秒）
## 成功印 M2_ACCEPT_OK（結束碼 0）；失敗印 M2_ACCEPT_FAIL <原因>（結束碼 1）。所有子程序一律 OS.kill()（含 _finalize）。

const ROLES := ["leader", "member", "pker", "victim"]
const BOT := "res://tests/bots/m2_party_bot.gd"

var _pids: Array[int] = []
var _logs: Dictionary = {}      # label -> log path
var _finished := false
var _timeout_s := 1500.0
var _time_scale := 5.0
var _keep_logs := false
var _run_id := ""
var _dir := ""
var _root := ""             # 測試資料根目錄（--data-root；預設 DataRoot.test_root()＝../JY-Mini-OL-Work/testdata），主機與 bot 都帶同一個
var _sync := ""
var _exe := ""
var _proj := ""
var _port := 0
var _host_pid := 0
var _host_n := 0
var _bot_pids: Dictionary = {}  # label -> pid
var _t0 := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--timeout="):
			_timeout_s = maxf(60.0, a.substr(10).to_float())
		elif a.begins_with("--time-scale="):
			_time_scale = clampf(a.substr(13).to_float(), 1.0, 50.0)
		elif a == "--keep-logs":
			_keep_logs = true
	create_timer(_timeout_s + 30.0, true, false, true).timeout.connect(func():
		_say("watchdog fired")
		_dump_logs()
		_fail_out("timeout (watchdog)", 1))
	_run.call_deferred()

func _finalize() -> void:
	_kill_all()

func _say(msg: String) -> void:
	print("[m2_acceptance %5.1fs] %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, msg])

func _run() -> void:
	_t0 = Time.get_ticks_msec()
	randomize()
	_run_id = "%04x" % (randi() % 0x10000)
	_exe = OS.get_executable_path()
	_proj = ProjectSettings.globalize_path("res://").trim_suffix("/")
	_root = DataRoot.resolve_for_tool(CliArgs.current())
	_dir = ProjectSettings.globalize_path(_root.path_join("m2_acceptance/%s" % _run_id))
	_sync = _dir.path_join("sync")
	DirAccess.make_dir_recursive_absolute(_sync)
	_port = 25000 + randi() % 5000
	_say("run=%s port=%d dir=%s time_scale=%.1f" % [_run_id, _port, _dir, _time_scale])

	if not await _start_host():
		_fail_out("host did not come up", 1)
		return
	for r in ROLES:
		if _spawn_bot(r, "") <= 0:
			_fail_out("failed to spawn bot " + r, 1)
			return

	var deadline := Time.get_ticks_msec() + int(_timeout_s * 1000.0)
	var member_left := false
	var restarted := false
	var member_returned := false
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.25, true, false, true).timeout
		if _finished:
			return
		# 任何 bot 失敗 → 立刻結束
		for label in _bot_pids:
			var pid: int = _bot_pids[label]
			if not OS.is_process_running(pid) and OS.get_process_exit_code(pid) != 0:
				_say("%s exited with %d" % [label, OS.get_process_exit_code(pid)])
				_dump_logs()
				_fail_out("bot %s failed: %s" % [label, _fail_line(label)], 1)
				return
		if not OS.is_process_running(_host_pid):
			_dump_logs()
			_fail_out("host exited unexpectedly (code %d)" % OS.get_process_exit_code(_host_pid), 1)
			return
		# 第 12 步：隊員程序結束 → member.left
		if not member_left and _bot_pids.has("member") and not OS.is_process_running(_bot_pids["member"]):
			if not _log_text("member").contains("M2_BOT_OK role=member"):
				_dump_logs()
				_fail_out("member exited without M2_BOT_OK", 1)
				return
			member_left = true
			_touch("orchestrator.member.left")
			_say("member is offline -> member.left")
		# 第 14 步：三個 restart.ready → 關主機、檢查 world.json、重開
		if member_left and not restarted and _all_have(["leader", "pker", "victim"], "restart.ready"):
			if not await _restart_host():
				return
			restarted = true
			_touch("orchestrator.host.restarted")
			_say("host restarted -> host.restarted")
		# 第 16 步：重開後讓隊員回來收信
		if restarted and not member_returned:
			member_returned = true
			if _spawn_bot("member", "return", "member_return") <= 0:
				_fail_out("failed to respawn member", 1)
				return
		if member_returned and _all_have(ROLES, "final") and _bots_exited_ok():
			break
	if Time.get_ticks_msec() >= deadline:
		_dump_logs()
		_fail_out("timeout (step progress: %s)" % _progress(), 1)
		return
	# 全部完成：正常關主機，檢查 log
	_touch("host.stop")
	if not await _wait_exit(_host_pid, 30.0):
		_fail_out("host did not stop after the final host.stop", 1)
		return
	var bad := _script_errors()
	if bad != "":
		_dump_logs()
		_fail_out("SCRIPT ERROR in logs: " + bad, 1)
		return
	_say("all bots M2_BOT_OK; host logs clean")
	print("M2_ACCEPT_OK run=%s elapsed=%.0fs" % [_run_id, (Time.get_ticks_msec() - _t0) / 1000.0])
	_finish(0)

# ---------- 主機 ----------
func _host_args() -> Array:
	return ["--no-steam", "--dedicated", "--enet-host", "--port=%d" % _port, "--world=m2acc_" + _run_id,
		# encounters_enabled=false：路上不踩地雷。嚴格死亡規則下單獨走路遇狼會死、掉武功，越死越弱、最後卡在柵欄
		# （M2 第三輪審查：兩次執行都在 boss1.ready 逾時）。驗收測的是組隊／PK／屍體／飛鴿，不是野外練功
		"--rule-preset=classic_strict", "--opts=newbie_pk_protect_xp=0,encounters_enabled=false,rumor_chat_inner_min=0", "--time-scale=%s" % str(_time_scale),
		"--stop-file=" + _sync.path_join("host.stop"), "--quit-after=%d" % int(_timeout_s + 60.0)]

func _start_host() -> bool:
	_host_n += 1
	var label := "host%d" % _host_n
	_host_pid = _spawn(label, _host_args())
	if _host_pid <= 0:
		return false
	if not await _wait_for_log(label, "ENet 主機", 30.0):
		_dump_logs()
		return false
	_say("%s up (pid %d)" % [label, _host_pid])
	return true

func _restart_host() -> bool:
	_say("all three restart.ready -> host.stop")
	_touch("host.stop")
	if not await _wait_exit(_host_pid, 30.0):
		_fail_out("host did not stop within 30 s of host.stop", 1)
		return false
	_say("host stopped (exit %d)" % OS.get_process_exit_code(_host_pid))
	# world.json 備查並斷言：該屍體 id、兩封信
	var world_dir := ProjectSettings.globalize_path(_root.path_join("worlds/m2acc_%s" % _run_id))
	var wj := world_dir.path_join("world.json")
	if not FileAccess.file_exists(wj):
		_fail_out("world.json missing: " + wj, 1)
		return false
	DirAccess.copy_absolute(wj, _dir.path_join("world_after_stop.json"))
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(wj))
	if not (data is Dictionary):
		_fail_out("world.json unreadable", 1)
		return false
	var corpse_id := _read("leader.corpse")
	var found := false
	for c in data.get("corpses", []):
		if c is Dictionary and str(c.get("id", "")) == corpse_id:
			found = true
	var mails: Array = data.get("mail", [])
	_say("world.json: corpse %s found=%s, mails=%d, world_time_s=%s" % [corpse_id, str(found), mails.size(),
		str(data.get("world_time_s", "?"))])
	if not found:
		_fail_out("world.json has no corpse %s" % corpse_id, 1)
		return false
	if mails.size() < 2:
		_fail_out("world.json has %d mails (want 2)" % mails.size(), 1)
		return false
	# 以相同參數重開（--rule-preset 對既有世界無效，無妨）
	if not await _start_host():
		_fail_out("host did not come back up", 1)
		return false
	return true

# ---------- bot ----------
func _spawn_bot(r: String, phase: String, label := "") -> int:
	if label == "":
		label = r
	var args := ["--no-steam", "--enet-join=127.0.0.1:%d" % _port, "--profile=m2_%s_%s" % [r, _run_id],
		"--name=" + r, "--bot=" + BOT, "--m2-role=" + r, "--m2-run=" + _run_id, "--m2-sync=" + _sync,
		"--quit-after=%d" % int(_timeout_s + 30.0)]
	if phase != "":
		args.append("--m2-phase=" + phase)
	var pid := _spawn(label, args)
	if pid > 0:
		_bot_pids[label] = pid
		if label == "member_return":
			_bot_pids.erase("member")
	return pid

func _bots_exited_ok() -> bool:
	for label in _bot_pids:
		var pid: int = _bot_pids[label]
		if OS.is_process_running(pid) or OS.get_process_exit_code(pid) != 0:
			return false
	return true

func _fail_line(label: String) -> String:
	for line in _log_text(label).split("\n"):
		if line.begins_with("M2_BOT_FAIL"):
			return line
	return "(no M2_BOT_FAIL line)"

# ---------- 同步檔 ----------
func _touch(name: String) -> void:
	var f := FileAccess.open(_sync.path_join(name), FileAccess.WRITE)
	if f != null:
		f.store_string("1")
		f.close()

func _read(name: String) -> String:
	var p := _sync.path_join(name)
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""

func _all_have(roles: Array, step: String) -> bool:
	for r in roles:
		if not FileAccess.file_exists(_sync.path_join("%s.%s" % [r, step])):
			return false
	return true

func _progress() -> String:
	var out: PackedStringArray = []
	var files := DirAccess.get_files_at(_sync)
	for r in ROLES:
		var last := ""
		var last_t := 0
		for f in files:
			if f.begins_with(r + "."):
				var t := FileAccess.get_modified_time(_sync.path_join(f))
				if t >= last_t:
					last_t = t
					last = f
		out.append(last)
	return ", ".join(out)

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

func _dump_logs() -> void:
	for label in _logs:
		print("----- %s (%s) -----" % [label, _logs[label]])
		var lines := _log_text(label).split("\n")
		print("\n".join(lines.slice(maxi(0, lines.size() - 40))))

func _kill_all() -> void:
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
			print("[m2_acceptance] killed pid %d" % pid)
	_pids.clear()

func _fail_out(reason: String, code: int) -> void:
	if _finished:
		return
	print("M2_ACCEPT_FAIL %s" % reason)
	_finish(code)

func _finish(code: int) -> void:
	if _finished:
		return
	_finished = true
	_kill_all()
	quit(code)
