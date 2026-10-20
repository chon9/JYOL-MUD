extends RefCounted
## 輕量測試基底（不依賴 GUT，TECH_ARCH 17 #19 的替代方案）。
## 方法名以 test_ 開頭；可選 before_each / after_each；測試可以 await。

var tree: SceneTree
var failures: PackedStringArray = []
var current_test := ""

func fail(msg: String) -> void:
	failures.append("%s: %s" % [current_test, msg])

func assert_true(cond: bool, msg: String = "expected true") -> bool:
	if not cond:
		fail(msg)
	return cond

func assert_false(cond: bool, msg: String = "expected false") -> bool:
	return assert_true(not cond, msg)

func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> bool:
	var same: bool = typeof(actual) == typeof(expected) and actual == expected
	if not same:
		fail("%s expected <%s:%s> got <%s:%s>" % [msg, type_string(typeof(expected)), str(expected),
			type_string(typeof(actual)), str(actual)])
	return same

func assert_type(value: Variant, type: int, msg: String = "") -> bool:
	if typeof(value) != type:
		fail("%s expected type %s got %s (%s)" % [msg, type_string(type), type_string(typeof(value)), str(value)])
		return false
	return true

func assert_has(container: Variant, item: Variant, msg: String = "") -> bool:
	var ok: bool = container.has(item)
	if not ok:
		fail("%s missing <%s>" % [msg, str(item)])
	return ok

func assert_not_has(container: Variant, item: Variant, msg: String = "") -> bool:
	var ok: bool = not container.has(item)
	if not ok:
		fail("%s unexpectedly contains <%s>" % [msg, str(item)])
	return ok

## 測試根目錄（DataRoot.test_root()）下的暫存資料夾，測完由 remove_dir_recursive 清掉
func temp_dir(tag: String) -> String:
	return DataRoot.path("test_tmp/%s_%d_%d" % [tag, OS.get_process_id(), randi() % 1000000])

static func remove_dir_recursive(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	for d in DirAccess.get_directories_at(abs_path):
		remove_dir_recursive(abs_path.path_join(d))
	for f in DirAccess.get_files_at(abs_path):
		DirAccess.remove_absolute(abs_path.path_join(f))
	DirAccess.remove_absolute(abs_path)
