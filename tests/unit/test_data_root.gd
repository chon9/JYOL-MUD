extends "res://tests/test_case.gd"
## 資料根目錄：--data-root ＞ data_root.txt ＞ user://；測試世界與玩家的存檔分開（bot／協調器沒指定時用測試根目錄）。

const NO_CFG := { "file": "", "base": "K:/Game", "data": "", "test": "" }

func test_resolve_without_config() -> void:
	assert_eq(DataRoot.resolve_with({}, NO_CFG), "user://", "沒有 data_root.txt → user://")
	assert_eq(DataRoot.resolve_with({ "bot": "res://tests/bots/m1_playthrough_bot.gd" }, NO_CFG), DataRoot.LEGACY_TEST_ROOT, "bot 預設測試根目錄")
	assert_eq(DataRoot.resolve_with({ "bot": "x", "data-root": "user://" }, NO_CFG), "user://", "明確指定 user:// 才會用真存檔")
	assert_eq(DataRoot.resolve_with({ "data-root": "user://_test/" }, NO_CFG), "user://_test")
	assert_eq(DataRoot.resolve_with({ "data-root": "my_tests" }, NO_CFG), "K:/Game/my_tests", "相對路徑＝相對於錨點資料夾")
	assert_eq(DataRoot.resolve_with({ "data-root": "C:/tmp/jy" }, NO_CFG), "C:/tmp/jy")
	assert_eq(DataRoot.resolve_with({ "data-root": "D:\\saves\\jy\\" }, NO_CFG), "D:/saves/jy", "反斜線與結尾斜線")
	assert_eq(DataRoot.resolve_with({ "data-root": true }, NO_CFG), "user://", "--data-root 沒給值 → 忽略")
	assert_eq(DataRoot.resolve_for_tool_with({}, NO_CFG), DataRoot.LEGACY_TEST_ROOT, "協調器預設測試根目錄")
	assert_eq(DataRoot.resolve_for_tool_with({ "data-root": "user://_test/x" }, NO_CFG), "user://_test/x")

func test_parse_config() -> void:
	var c := DataRoot.parse_config("\ufeff# 註解\n\n  userdata  \r\n", "K:/Project/JY-Mini-OL-Release")
	assert_eq(c["data"], "K:/Project/JY-Mini-OL-Release/userdata", "可攜版：相對於 .exe 資料夾")
	assert_eq(DataRoot.test_root_of(c), "K:/Project/JY-Mini-OL-Release/testdata", "測試根目錄預設在旁邊")
	var d := DataRoot.parse_config("../JY-Mini-OL-Work/userdata\n", "K:/Project/JY-Mini OL")
	assert_eq(d["data"], "K:/Project/JY-Mini-OL-Work/userdata", "開發：../ 會化簡")
	assert_eq(DataRoot.test_root_of(d), "K:/Project/JY-Mini-OL-Work/testdata")
	var e := DataRoot.parse_config("D:/jy/save\ntest=../t\n", "K:/Game")
	assert_eq(e["data"], "D:/jy/save", "絕對路徑")
	assert_eq(e["test"], "K:/t", "test= 指定測試根目錄（相對於設定檔資料夾）")
	assert_eq(DataRoot.parse_config("# 只有註解\n", "K:/Game")["data"], "", "沒有路徑 → 不設定")

func test_resolve_with_config() -> void:
	var c := DataRoot.parse_config("userdata", "K:/Game")
	assert_eq(DataRoot.resolve_with({}, c), "K:/Game/userdata", "一般遊玩用 data_root.txt")
	assert_eq(DataRoot.resolve_with({ "bot": "x" }, c), "K:/Game/testdata", "bot 用測試根目錄（不是 user://）")
	assert_eq(DataRoot.resolve_for_tool_with({}, c), "K:/Game/testdata", "協調器用測試根目錄")
	assert_eq(DataRoot.resolve_with({}, c, true), "K:/Game/testdata", "--script 工具（data_lint、balance_sim…）用測試根目錄")
	assert_eq(DataRoot.resolve_with({ "data-root": "K:/x" }, c, true), "K:/x", "--script 也可明確指定")
	assert_true(DataRoot.is_script_run(), "run_tests.gd 是 --script 執行")
	assert_eq(DataRoot.resolve_with({ "data-root": "K:/x/y" }, c), "K:/x/y", "--data-root 優先")
	assert_eq(DataRoot.resolve_with({ "data-root": "scratch" }, c), "K:/Game/scratch")
	assert_eq(DataRoot.normalize_with("res://worlds", c), "K:/Game/testdata", "res:// 不能當根目錄")

func test_project_config_keeps_tests_off_appdata() -> void:
	# 專案根目錄的 data_root.txt：開發與測試都不寫 %APPDATA%
	var cfg := DataRoot.config()
	assert_true(cfg["file"] != "", "專案根目錄有 data_root.txt")
	assert_false(String(cfg["data"]).begins_with("user://"), "開發資料根目錄不在 user://")
	assert_false(DataRoot.test_root().begins_with("user://"), "測試根目錄不在 user://")

func test_runner_uses_test_root() -> void:
	# run_tests.gd 開頭已切到測試根目錄
	assert_eq(DataRoot.root(), DataRoot.resolve_for_tool(CliArgs.current()))
	assert_false(DataRoot.is_default(), "單元測試不寫 user:// 根目錄")
	assert_false(ProjectSettings.globalize_path(DataRoot.root()).begins_with(OS.get_user_data_dir()), "測試根目錄不在 %APPDATA%")
	assert_eq(DataRoot.child_arg("K:/t"), "--data-root=K:/t")
	assert_eq(MapMemory.new().dir, DataRoot.path("map_memory"))
	var sm = tree.root.get_node_or_null("SaveManager")
	if sm != null:
		assert_eq(sm.root_dir, DataRoot.root())
		assert_true(str(sm.world_dir("abc")).begins_with(DataRoot.root()), "worlds 在測試根目錄底下")
