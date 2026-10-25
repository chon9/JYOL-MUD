extends "res://tests/test_case.gd"
## M3C2_PLAN §6.1、E2（WP-CARRY）：BuildInfo.line() 格式；project.godot 與 export_presets.cfg 的版本一致。

func test_fingerprint12() -> void:
	assert_eq(BuildInfo.fingerprint12("sha256:9d24a2e10ccc0123456789abcdef"), "9d24a2e10ccc")
	assert_eq(BuildInfo.fingerprint12("9d24a2e10ccc0123"), "9d24a2e10ccc")
	assert_eq(BuildInfo.fingerprint12(""), "")
	assert_eq(BuildInfo.fingerprint12("sha256:abc"), "abc")

func test_line_format() -> void:
	var line := BuildInfo.line("sha256:9d24a2e10ccc0123456789")
	assert_eq(line, "v%s　協定 %d　資料 9d24a2e10ccc" % [BuildInfo.version(), Protocol.VERSION])
	assert_true(line.begins_with("v0.8.0.0　"), line)
	assert_eq(BuildInfo.protocol(), 5, "Protocol.VERSION stays 5 (Q1)")
	assert_eq(BuildInfo.format_line("0.6.0.0", 5, "1a2b3c4d5e6f"), "v0.6.0.0　協定 5　資料 1a2b3c4d5e6f")
	assert_eq(BuildInfo.format_line("0.6.0.0", 5, ""), "v0.6.0.0　協定 5　資料 ?")
	assert_eq(BuildInfo.line(GameData.content_hash), "v%s　協定 5　資料 %s" % [BuildInfo.version(),
		GameData.content_hash.trim_prefix("sha256:").substr(0, 12)])

func test_version_matches_project_and_export_presets() -> void:
	assert_eq(BuildInfo.version(), "0.8.0.0")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot")
	assert_eq(str(cfg.get_value("application", "config/version", "")), "0.8.0.0")
	var ex := ConfigFile.new()
	assert_eq(ex.load("res://export_presets.cfg"), OK, "export_presets.cfg")
	var found := 0
	for sec in ex.get_sections():
		if ex.has_section_key(sec, "application/file_version"):
			assert_eq(str(ex.get_value(sec, "application/file_version")), BuildInfo.version(), sec + " file_version")
			assert_eq(str(ex.get_value(sec, "application/product_version")), BuildInfo.version(), sec + " product_version")
			found += 1
	assert_true(found >= 1, "export preset has versions")
	# 握手相容字串維持（R14）
	assert_eq(Protocol.GAME_VERSION, "0.1.0")
