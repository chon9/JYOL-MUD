extends "res://tests/test_case.gd"
## M3c WP-ART（M3C_PLAN §2.5、§12.1）：tools/import_art.py 與 tools/art_register.py。
## 在暫存目錄裡造一個假的 inbox／輸出目錄／art.json，呼叫 python 處理後用 GDScript 檢查輸出：
## 每類尺寸與目錄、武器特效靠左、placeholder 旗標、--no-json-update 不寫 art.json、覆寫備份位元組相同、快照、art_register。
## 找不到 python 或 Pillow 時整組略過（印出原因，不算失敗；整合機器上有 python）。

var _tmp := ""
var _python := ""

func before_each() -> void:
	_tmp = ProjectSettings.globalize_path(temp_dir("m3c_art_import"))
	DirAccess.make_dir_recursive_absolute(_tmp)
	if _python == "":
		_python = _find_python()

func after_each() -> void:
	if _tmp != "":
		remove_dir_recursive(_tmp)
		_tmp = ""

static func _find_python() -> String:
	for exe in ["python", "py", "python3"]:
		var out: Array = []
		if OS.execute(exe, ["-I", "-c", "import PIL; print('ok')"], out, true) == 0 and "ok" in "".join(out):
			return exe
	return "-"

func _skip() -> bool:
	if _python == "-":
		print("  (skip: python with Pillow not found)")
		return true
	return false

func _tool(name: String) -> String:
	return ProjectSettings.globalize_path("res://tools/" + name)

func _run(script: String, args: Array) -> Dictionary:
	var out: Array = []
	var full: Array = ["-I", _tool(script)]
	full.append_array(args)
	var code := OS.execute(_python, PackedStringArray(full), out, true)
	return { "code": code, "out": "".join(out) }

func _p(rel: String) -> String:
	return _tmp.path_join(rel)

## 假圖：w×h，中間 cw×ch 的不透明色塊（其餘透明；opaque=true 時整張不透明）
static func _img(path: String, w: int, h: int, cw: int, ch: int, opaque: bool = false) -> void:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.5, 0.2, 1.0) if opaque else Color(0, 0, 0, 0))
	img.fill_rect(Rect2i((w - cw) / 2, (h - ch) / 2, cw, ch), Color(0.9, 0.7, 0.2, 1.0))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)

static func _size(path: String) -> Vector2i:
	var img := Image.load_from_file(path)
	return Vector2i(-1, -1) if img == null or img.is_empty() else img.get_size()

static func _art_min() -> Dictionary:
	return {
		"table": "art", "version": 1,
		"units": { "player_m": { "sprite": "player_m", "scale": 1.0, "y_offset": 0, "required": true, "placeholder": true } },
		"player_fallback": { "m": "player_m", "f": "player_m" },
		"backgrounds": {}, "bg_default": "", "fx": {},
		"map": { "world_base": { "file": "map_world_base", "required": false, "placeholder": true },
			"region_bg": { "file": "map_region_bg", "required": false, "placeholder": true },
			"node_room": { "file": "map_node_room", "required": false, "placeholder": true },
			"marker_here": { "file": "map_marker_here", "required": false, "placeholder": true },
			"compass": { "file": "map_compass", "required": false, "placeholder": true },
			"frame_title": { "file": "map_frame_title", "required": false, "placeholder": true } },
		"map_icons": { "inn": { "file": "map_icon_inn", "required": false, "placeholder": true },
			"city": { "file": "map_icon_city", "required": false, "placeholder": true } },
		"weapon_fx": { "sword": { "file": "fx_weapon_sword", "required": false, "placeholder": true },
			"inner": { "file": "fx_skill_inner", "required": false, "placeholder": true } },
		"weapon_icons": { "fist": { "file": "icon_weapon_fist", "required": false, "placeholder": true } },
	}

func _write_art(path: String, art: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(art, "  "))
	f.close()

func _fill_inbox() -> void:
	var inbox := _p("inbox")
	_img(inbox.path_join("map_world_base.png"), 800, 600, 800, 600, true)
	_img(inbox.path_join("map_region_bg.png"), 300, 200, 300, 200, true)
	_img(inbox.path_join("map_node_room.png"), 200, 100, 160, 60)
	_img(inbox.path_join("map_marker_here.png"), 120, 120, 40, 80)
	_img(inbox.path_join("map_icon_inn.png"), 128, 128, 64, 64)
	_img(inbox.path_join("map_compass.png"), 300, 300, 200, 200)
	_img(inbox.path_join("map_frame_title.png"), 400, 100, 380, 60)
	_img(inbox.path_join("fx_weapon_sword.png"), 600, 600, 300, 300)   # 方塊內容 → 靠左放進 1024x512
	_img(inbox.path_join("fx_skill_inner.png"), 1774, 887, 1500, 600)
	_img(inbox.path_join("icon_weapon_fist.png"), 300, 300, 120, 200)
	_img(inbox.path_join("map_nonsense.png"), 64, 64, 32, 32)
	_img(inbox.path_join("fx_weapon_spear.png"), 64, 64, 32, 32)

func test_import_every_m3c_class() -> void:
	if _skip():
		return
	_fill_inbox()
	var art_path := _p("art.json")
	_write_art(art_path, _art_min())
	var before := FileAccess.get_file_as_bytes(art_path)
	var r := _run("import_art.py", ["--inbox", _p("inbox"), "--out", _p("out"), "--art-json", art_path,
		"--no-json-update", "--no-backup"])
	assert_eq(r["code"], 0, "import ok: " + str(r["out"]).right(600))
	assert_eq(FileAccess.get_file_as_bytes(art_path), before, "--no-json-update leaves art.json byte-identical")
	var want := {
		"out/map/map_world_base.png": Vector2i(2400, 1800), "out/map/map_region_bg.png": Vector2i(1024, 1024),
		"out/map/map_node_room.png": Vector2i(384, 192), "out/map/map_marker_here.png": Vector2i(256, 256),
		"out/map/map_icon_inn.png": Vector2i(256, 256), "out/map/map_compass.png": Vector2i(512, 512),
		"out/map/map_frame_title.png": Vector2i(1024, 256), "out/fx/fx_weapon_sword.png": Vector2i(1024, 512),
		"out/fx/fx_skill_inner.png": Vector2i(1024, 512), "out/icons/icon_weapon_fist.png": Vector2i(256, 256),
	}
	for rel in want:
		assert_eq(_size(_p(rel)), want[rel], rel)
	assert_false(FileAccess.file_exists(_p("out/map/map_nonsense.png")), "unknown map name skipped")
	assert_false(FileAccess.file_exists(_p("out/fx/fx_weapon_spear.png")), "unknown weapon fx skipped")
	assert_true("map_nonsense.png" in str(r["out"]) and "fx_weapon_spear.png" in str(r["out"]), "warned about unknown names")
	# 武器特效：裁邊後靠左、垂直置中 → 左緣中點有內容、右側空白
	var fx := Image.load_from_file(_p("out/fx/fx_weapon_sword.png"))
	assert_true(fx.get_pixel(2, 256).a > 0.5, "effect starts at the left edge")
	assert_true(fx.get_pixel(900, 256).a < 0.05, "square effect does not stretch to the right")
	assert_true(fx.get_pixel(256, 2).a > 0.5, "vertically fills (contain)")
	# 圖示：裁邊後置中
	var icon := Image.load_from_file(_p("out/icons/icon_weapon_fist.png"))
	assert_true(icon.get_pixel(128, 128).a > 0.5 and icon.get_pixel(2, 128).a < 0.05, "icon centred")
	# 房間框：不裁邊（透明邊距保留）
	var node := Image.load_from_file(_p("out/map/map_node_room.png"))
	assert_true(node.get_pixel(192, 3).a < 0.05, "frame margin kept (not trimmed)")
	# 重跑：內容相同就不重寫
	var r2 := _run("import_art.py", ["--inbox", _p("inbox"), "--out", _p("out"), "--art-json", art_path,
		"--no-json-update", "--no-backup"])
	assert_true("files written: 0" in str(r2["out"]), "idempotent")

func test_placeholder_flags_updated() -> void:
	if _skip():
		return
	_fill_inbox()
	var art_path := _p("art.json")
	_write_art(art_path, _art_min())
	var r := _run("import_art.py", ["--inbox", _p("inbox"), "--out", _p("out"), "--art-json", art_path, "--no-backup"])
	assert_eq(r["code"], 0, str(r["out"]).right(400))
	var art: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(art_path))
	assert_eq(art["map"]["world_base"]["placeholder"], false)
	assert_eq(art["map"]["frame_title"]["placeholder"], false)
	assert_eq(art["map_icons"]["inn"]["placeholder"], false)
	assert_eq(art["map_icons"]["city"]["placeholder"], true, "not provided stays placeholder")
	assert_eq(art["weapon_fx"]["sword"]["placeholder"], false)
	assert_eq(art["weapon_fx"]["inner"]["placeholder"], false)
	assert_eq(art["weapon_icons"]["fist"]["placeholder"], false)
	assert_eq(art["units"]["player_m"]["placeholder"], true, "unit without idle stays placeholder")

func test_overwrite_is_backed_up_byte_identical() -> void:
	if _skip():
		return
	var inbox := _p("inbox")
	_img(inbox.path_join("unit_player_m_idle.png"), 256, 256, 80, 200)
	_img(inbox.path_join("icon_weapon_fist.png"), 256, 256, 100, 100)
	# 輸出目錄裡已有內容不同的舊圖
	_img(_p("out/units/unit_player_m_idle.png"), 50, 100, 30, 90)
	_img(_p("out/icons/icon_weapon_fist.png"), 256, 256, 30, 30)
	var old_unit := FileAccess.get_file_as_bytes(_p("out/units/unit_player_m_idle.png"))
	var old_icon := FileAccess.get_file_as_bytes(_p("out/icons/icon_weapon_fist.png"))
	var art_path := _p("art.json")
	_write_art(art_path, _art_min())
	var r := _run("import_art.py", ["--inbox", inbox, "--out", _p("out"), "--art-json", art_path,
		"--no-json-update", "--backup-root", _p("backup")])
	assert_eq(r["code"], 0, str(r["out"]).right(400))
	var unit_bk := _find(_p("backup"), "unit_player_m_idle.png")
	var icon_bk := _find(_p("backup"), "icon_weapon_fist.png")
	assert_true(unit_bk.size() == 1 and unit_bk[0].get_base_dir().ends_with("units"), "unit backup in <date>/units: %s" % [unit_bk])
	assert_true(icon_bk.size() == 1 and icon_bk[0].get_base_dir().ends_with("icons"), "icon backup in <date>/icons: %s" % [icon_bk])
	if unit_bk.size() == 1:
		assert_eq(FileAccess.get_file_as_bytes(unit_bk[0]), old_unit, "backup bytes == old file")
		assert_true(unit_bk[0].get_base_dir().get_base_dir().get_file().length() == 10, "<YYYY-MM-DD> folder")
	if icon_bk.size() == 1:
		assert_eq(FileAccess.get_file_as_bytes(icon_bk[0]), old_icon)
	assert_true(FileAccess.get_file_as_bytes(_p("out/units/unit_player_m_idle.png")) != old_unit, "new file written")
	# 再匯入一次（內容沒變）→ 不再多備份
	_run("import_art.py", ["--inbox", inbox, "--out", _p("out"), "--art-json", art_path, "--no-json-update",
		"--backup-root", _p("backup")])
	assert_eq(_find(_p("backup"), "unit_player_m_idle.png").size(), 1, "no duplicate backup when unchanged")
	# --no-backup：不建備份資料夾
	_img(_p("out2/units/unit_player_m_idle.png"), 50, 100, 30, 90)
	_run("import_art.py", ["--inbox", inbox, "--out", _p("out2"), "--art-json", art_path, "--no-json-update",
		"--no-backup", "--backup-root", _p("backup2")])
	assert_false(DirAccess.dir_exists_absolute(_p("backup2")), "--no-backup")

func test_snapshot_and_only_filter() -> void:
	if _skip():
		return
	var inbox := _p("assets/art_in")
	_img(inbox.path_join("unit_wudang_m_idle.png"), 256, 256, 80, 200)
	_img(inbox.path_join("unit_look_f03_attack.png"), 256, 256, 80, 200)
	_img(inbox.path_join("unit_m_wolf_idle.png"), 256, 256, 80, 200)
	_img(_p("assets/art_in_backup_x/sub/unit_player_f_idle.png"), 64, 64, 30, 30)
	_img(_p("assets/art/units/unit_player_m_idle.png"), 64, 128, 30, 100)
	_img(_p("assets/art/units/unit_m_wolf_idle.png"), 64, 64, 30, 30)
	var art_path := _p("art.json")
	_write_art(art_path, _art_min())
	var r := _run("import_art.py", ["--snapshot", "--inbox", inbox, "--out", _p("assets/art"), "--art-json", art_path,
		"--backup-root", _p("backup")])
	assert_eq(r["code"], 0, str(r["out"]))
	assert_true("snapshot: 4 files" in str(r["out"]), str(r["out"]))
	assert_eq(_find(_p("backup"), "unit_m_wolf_idle.png").size(), 0, "monsters are not in the snapshot")
	var pm := _find(_p("backup"), "unit_player_m_idle.png")
	assert_true(pm.size() == 1 and "snapshot_units" in pm[0], "processed player sprite snapshotted")
	assert_eq(_find(_p("backup"), "unit_player_f_idle.png").size(), 1, "art_in_backup* originals included")
	# --only：只處理符合的檔
	var r2 := _run("import_art.py", ["--inbox", inbox, "--out", _p("out"), "--art-json", art_path, "--no-json-update",
		"--no-backup", "--only", "unit_look_*"])
	assert_eq(r2["code"], 0, str(r2["out"]).right(300))
	assert_true(FileAccess.file_exists(_p("out/units/unit_look_f03_attack.png")))
	assert_false(FileAccess.file_exists(_p("out/units/unit_wudang_m_idle.png")), "--only filters")

func test_art_register_m3c_files() -> void:
	if _skip():
		return
	var root := _p("proj")
	DirAccess.make_dir_recursive_absolute(root.path_join("data"))
	for t in ["regions", "monsters", "npcs"]:
		var f := FileAccess.open(root.path_join("data/%s.json" % t), FileAccess.WRITE)
		f.store_string(JSON.stringify({ "rows": [{ "id": "m_wolf" if t == "monsters" else "dali" }] }))
		f.close()
	var art := _art_min()
	art["units"]["m_wolf"] = { "alias": "player_m" }
	art["map"].erase("compass")
	_write_art(root.path_join("data/art.json"), art)
	var inbox := root.path_join("assets/art_in")
	for f in ["map_world_base.png", "map_compass.png", "fx_skill_inner.png", "icon_weapon_fist.png", "unit_m_wolf_idle.png", "map_bogus.png"]:
		_img(inbox.path_join(f), 32, 32, 16, 16)
	# --dry 不寫
	var before := FileAccess.get_file_as_bytes(root.path_join("data/art.json"))
	_run("art_register.py", [root, "--dry"])
	assert_eq(FileAccess.get_file_as_bytes(root.path_join("data/art.json")), before, "--dry")
	# --only 只登記符合的
	var r := _run("art_register.py", [root, "--only", "map_*"])
	assert_eq(r["code"], 0, str(r["out"]))
	var a1: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("data/art.json")))
	assert_eq(a1["map"]["world_base"]["placeholder"], false)
	assert_eq(a1["map"]["compass"], { "file": "map_compass", "required": false, "placeholder": false }, "missing entry created")
	assert_eq(a1["weapon_fx"]["inner"]["placeholder"], true, "filtered out by --only")
	assert_true(a1["units"]["m_wolf"].has("alias"), "filtered out by --only")
	assert_true("map_bogus.png" in str(r["out"]), "unknown map file reported")
	_run("art_register.py", [root])
	var a2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("data/art.json")))
	assert_eq(a2["weapon_fx"]["inner"]["placeholder"], false)
	assert_eq(a2["weapon_icons"]["fist"]["placeholder"], false)
	assert_eq(a2["units"]["m_wolf"]["sprite"], "m_wolf")

## 遞迴找檔名（回傳絕對路徑清單）
static func _find(dir: String, name: String) -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f == name:
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_find(dir.path_join(d), name))
	return out
