class_name DataRoot
extends RefCounted
## 本機資料根目錄（存檔 worlds/、profiles/、passports/、settings.json、map_memory/、logs/ 都放在這底下）。
##
## 決定順序（第一個有的就用）：
##   1. 命令列 `--data-root=<dir>`：絕對路徑、`user://…`，或相對路徑（相對於下面的「錨點資料夾」）。
##   2. `data_root.txt`：放在錨點資料夾 —— 匯出版＝.exe 同一層，開發／編輯器執行＝專案根目錄。
##      內容第一個非空、非 # 註解的行就是資料根目錄（相對路徑＝相對於 data_root.txt 所在的資料夾）。
##      另可寫一行 `test=<dir>` 指定測試根目錄（預設＝資料根目錄旁邊的 testdata/）。
##      正式版（tools/export_release.ps1）寫 `userdata` → 存檔跟著 .exe 走（可攜版）；
##      專案根目錄寫 `../JY-Mini-OL-Work/userdata` → 開發執行的存檔在 K:，測試在 ../JY-Mini-OL-Work/testdata。
##      資料夾建不起來或不能寫（例如放在 Program Files）→ 警告並退回 user://。
##   3. 都沒有 → Godot 的 user://（Windows：%APPDATA%\Godot\app_userdata\JY-Mini OL\）。
## 測試：所有 bot（`--bot=`）、所有 `--script` 執行（tools/*.gd、run_tests.gd）沒寫 --data-root 時一律用 test_root()，
## 測試世界永遠不會出現在玩家的世界清單旁邊。

const DEFAULT_ROOT := "user://"
const LEGACY_TEST_ROOT := "user://_test"     # 沒有 data_root.txt 時的測試根目錄（舊行為）
const CONFIG_FILE := "data_root.txt"

static var _cached := ""
static var _cfg: Dictionary = {}
static var _cfg_loaded := false

## 目前生效的根目錄（第一次呼叫時從命令列與 data_root.txt 算出來）
static func root() -> String:
	if _cached == "":
		_cached = resolve(CliArgs.current())
	return _cached

## 錨點資料夾：匯出版＝.exe 所在資料夾；開發／編輯器＝專案根目錄
static func anchor_dir() -> String:
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().replace("\\", "/")
	return ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")

## data_root.txt 解析結果 { file, data, test }（data／test 為 "" ＝ 沒設定）；只讀一次
static func config() -> Dictionary:
	if not _cfg_loaded:
		_cfg_loaded = true
		_cfg = load_config(anchor_dir())
	return _cfg

static func load_config(dir: String) -> Dictionary:
	var file := dir.path_join(CONFIG_FILE)
	if not FileAccess.file_exists(file):
		return { "file": "", "base": dir, "data": "", "test": "" }
	var cfg := parse_config(FileAccess.get_file_as_string(file), dir)
	cfg["file"] = file
	if cfg["data"] != "" and not _writable(cfg["data"]):
		push_warning("[DataRoot] %s 指定的 %s 無法建立或寫入，改用 user://" % [file, cfg["data"]])
		cfg["data"] = ""
	return cfg

## 純函式（單元測試用）：data_root.txt 內容 → { base, data, test }
static func parse_config(text: String, base_dir: String) -> Dictionary:
	var out := { "file": "", "base": base_dir, "data": "", "test": "" }
	for raw in text.replace("﻿", "").split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("test="):
			out["test"] = _abs(line.substr(5).strip_edges(), base_dir)
		elif out["data"] == "":
			out["data"] = _abs(line, base_dir)
	return out

## 由命令列參數算根目錄（設定檔用 config()）
static func resolve(args: Dictionary) -> String:
	return resolve_with(args, config(), is_script_run())

## `godot --script <檔>` 執行的一律是工具／測試（data_lint、balance_sim、run_tests…），不是玩家在玩
static func is_script_run() -> bool:
	var a := OS.get_cmdline_args()
	return "--script" in a or "-s" in a

static func resolve_with(args: Dictionary, cfg: Dictionary, script_run: bool = false) -> String:
	var v: Variant = args.get("data-root")
	if v is String and String(v).strip_edges() != "":
		return normalize_with(String(v), cfg)
	if args.has("bot") or script_run:
		return test_root_of(cfg)
	return cfg.get("data", "") if cfg.get("data", "") != "" else DEFAULT_ROOT

## tools/*.gd 協調器與 run_tests.gd：沒指定就用測試根目錄（它們只會建測試世界）
static func resolve_for_tool(args: Dictionary) -> String:
	return resolve_for_tool_with(args, config())

static func resolve_for_tool_with(args: Dictionary, cfg: Dictionary) -> String:
	var v: Variant = args.get("data-root")
	if v is String and String(v).strip_edges() != "":
		return normalize_with(String(v), cfg)
	return test_root_of(cfg)

## 測試根目錄：data_root.txt 的 test=；否則資料根目錄旁邊的 testdata/；都沒有 → user://_test
static func test_root() -> String:
	return test_root_of(config())

static func test_root_of(cfg: Dictionary) -> String:
	if cfg.get("test", "") != "":
		return cfg["test"]
	if cfg.get("data", "") != "":
		return String(cfg["data"]).get_base_dir().path_join("testdata")
	return LEGACY_TEST_ROOT

static func normalize(s: String) -> String:
	return normalize_with(s, config())

static func normalize_with(s: String, cfg: Dictionary) -> String:
	var p := s.strip_edges().replace("\\", "/")
	if p.begins_with("res://"):
		var t := test_root_of(cfg)
		push_warning("[DataRoot] --data-root 不能放在 res://（專案資料夾），改用 %s" % t)
		return t
	if p == "user:" or p == "user:/" or p == "user://":
		return DEFAULT_ROOT
	if p.begins_with("user://"):
		return p.trim_suffix("/")
	return _abs(p, String(cfg.get("base", anchor_dir())))

static func _abs(p: String, base_dir: String) -> String:
	var s := p.strip_edges().replace("\\", "/")
	if s.begins_with("user://"):
		return s.trim_suffix("/")
	if not s.is_absolute_path():
		s = base_dir.path_join(s)
	s = s.simplify_path()
	return s.trim_suffix("/") if s.length() > 3 else s

static func _writable(dir: String) -> bool:
	var abs_dir := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(abs_dir) and DirAccess.make_dir_recursive_absolute(abs_dir) != OK:
		return false
	var probe := abs_dir.path_join(".write_probe_%d" % OS.get_process_id())
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true

## 只給測試：強制改根目錄（"" ＝ 下次重新從命令列算）
static func override_for_tests(p: String) -> void:
	_cached = p

static func is_default() -> bool:
	return root() == DEFAULT_ROOT

static func path(rel: String) -> String:
	return root().path_join(rel)

## 子行程（協調器開的主機／bot）要帶的參數（一律絕對路徑或 user://，子行程不必再讀 data_root.txt）
static func child_arg(r: String = "") -> String:
	return "--data-root=" + (r if r != "" else root())

static func ensure_dir(dir_path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_path):
		DirAccess.make_dir_recursive_absolute(abs_path)
