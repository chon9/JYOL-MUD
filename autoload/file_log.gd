extends Node
## 遊戲記錄檔：<資料根目錄>/logs/godot.log（取代 Godot 內建、寫在 %APPDATA% 的 user://logs/）。
## project.godot 已關掉 debug/file_logging（內建記錄檔只能寫 user://），改由這裡用 OS.add_logger() 收 print／錯誤。
## 只在有視窗時啟用（或帶使用者參數 --file-log）：headless 的測試／bot 輸出已經在主控台，協調器另外用 --log-file 收子程序記錄（寫在測試根目錄）。
## 每次啟動把上一份改名 godot_<時間>.log，最多留 MAX_OLD 份。

const MAX_OLD := 5

class _FileLogger extends Logger:
	var _f: FileAccess
	var _m := Mutex.new()

	func _init(f: FileAccess) -> void:
		_f = f

	func _write(s: String) -> void:
		_m.lock()
		if _f != null:
			_f.store_string(s)
			_f.flush()
		_m.unlock()

	func _log_message(message: String, _error: bool) -> void:
		_write(message if message.ends_with("\n") else message + "\n")

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
		var msg := rationale if rationale != "" else code
		_write("%s: %s\n   at: %s (%s:%d)\n" % [kind, msg, function, file, line])

	func close() -> void:
		_m.lock()
		_f = null
		_m.unlock()

var log_path := ""
var _logger: _FileLogger

func _init() -> void:
	var forced := "--file-log" in OS.get_cmdline_user_args()   # 測試用：headless 也寫
	if not forced and (DisplayServer.get_name() == "headless" or "--log-file" in OS.get_cmdline_args()):
		return
	var dir := ProjectSettings.globalize_path(DataRoot.path("logs"))
	DirAccess.make_dir_recursive_absolute(dir)
	log_path = dir.path_join("godot.log")
	_rotate(dir)
	var f := FileAccess.open(log_path, FileAccess.WRITE)
	if f == null:
		log_path = ""
		return
	f.store_string("JY-Mini OL %s  %s\n" % [ProjectSettings.get_setting("application/config/version", ""), Time.get_datetime_string_from_system()])
	_logger = _FileLogger.new(f)
	OS.add_logger(_logger)

func _rotate(dir: String) -> void:
	if FileAccess.file_exists(log_path):
		var stamp := Time.get_datetime_string_from_unix_time(int(FileAccess.get_modified_time(log_path))).replace(":", ".")
		DirAccess.rename_absolute(log_path, dir.path_join("godot_%s.log" % stamp))
	var old: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("godot_") and f.ends_with(".log"):
			old.append(f)
	old.sort()
	while old.size() > MAX_OLD:
		DirAccess.remove_absolute(dir.path_join(old.pop_front()))

func _exit_tree() -> void:
	if _logger != null:
		OS.remove_logger(_logger)
		_logger.close()
