extends SceneTree
## 自帶的測試執行器：godot --headless --path . --script res://tests/run_tests.gd -- --no-steam [--filter=<字串>]
## 有任何失敗就以結束碼 1 結束。

const DIRS := ["res://tests/unit", "res://tests/integration"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# 單元測試的檔案（設定、地圖記憶、護照…）一律寫到測試根目錄（DataRoot.test_root()，開發時＝../JY-Mini-OL-Work/testdata），不碰玩家的存檔（--data-root 可改）
	var data_root := DataRoot.resolve_for_tool(CliArgs.current())
	DataRoot.override_for_tests(data_root)
	if root.has_node("SaveManager"):
		root.get_node("SaveManager").root_dir = data_root
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	var files: Array = []
	for dir in DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			if f.begins_with("test_") and f.ends_with(".gd"):
				files.append(dir.path_join(f))
	files.sort()

	var total := 0
	var failed := 0
	var failed_names: PackedStringArray = []
	var t0 := Time.get_ticks_msec()
	for path in files:
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			print("FAIL  %s (script failed to load)" % path)
			failed += 1
			failed_names.append(path)
			continue
		var suite: RefCounted = script.new()
		suite.tree = self
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (filter in name or filter in path):
				continue
			total += 1
			suite.current_test = name
			var before: int = suite.failures.size()
			if suite.has_method("before_each"):
				await suite.call("before_each")
			await suite.call(name)
			if suite.has_method("after_each"):
				await suite.call("after_each")
			var label := "%s::%s" % [path.get_file().get_basename(), name]
			if suite.failures.size() > before:
				failed += 1
				failed_names.append(label)
				print("FAIL  " + label)
				for i in range(before, suite.failures.size()):
					print("      " + suite.failures[i])
			else:
				print("ok    " + label)
	print("\n%d tests, %d failed (%d ms)" % [total, failed, Time.get_ticks_msec() - t0])
	if failed > 0:
		print("FAILED: " + ", ".join(failed_names))
	_cleanup()
	quit(1 if failed > 0 or total == 0 else 0)

func _cleanup() -> void:
	if root.has_node("NetworkManager"):
		root.get_node("NetworkManager").leave(true)
	var test_case := load("res://tests/test_case.gd")
	test_case.remove_dir_recursive(DataRoot.path("test_tmp"))
