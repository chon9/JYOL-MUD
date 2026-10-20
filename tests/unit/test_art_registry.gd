extends "res://tests/unit/test_battle_helpers.gd"
## 戰鬥美術：data/art.json 結構檢查、ArtRegistry 查表（別名、玩家外觀退回、背景退回、正式圖蓋過暫代圖）、
## 戰鬥快照的表現用欄位 look／ref（M1_PLAN 3.9.3 追加）。

const F := preload("res://tests/unit/test_character_fixtures.gd")

var _tmp := ""

func after_each() -> void:
	ArtRegistry.reset()
	if _tmp != "":
		remove_dir_recursive(_tmp)
		_tmp = ""

static func game_tables() -> Dictionary:
	var loader := DataLoader.new()
	loader.load_all()
	return loader.all_tables

static func art_json() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ArtRegistry.ART_JSON))

## M3c §2.6（A5）：art.json 已替 WP-NPCPK 的新怪物／NPC 準備 alias。平行開發期間那些資料列可能還沒進 monsters／npcs，
## 這裡用本地假列補上（只補缺的），讓 art.json 本身的檢查不依賴其他工作包的進度。
const A5_MONSTERS := ["m_npc_civilian", "m_npc_child", "m_npc_animal", "m_npc_worker", "m_npc_wushi", "m_npc_villain",
	"m_npc_sl_wuseng", "m_npc_sunpopo", "m_npc_dingchunqiu", "m_npc_xd_laozu"]
const A5_NPCS := ["n_na_xx_huanggou", "n_na_xw_yang", "n_na_dl_xiaohai", "n_na_xx_jumin", "n_na_xe_kuangshi", "n_na_xx_eba"]

static func tables_with_a5() -> Dictionary:
	var t := game_tables()
	for mid in A5_MONSTERS:
		if not t["monsters"].has(mid):
			t["monsters"][mid] = { "id": mid }
	for nid in A5_NPCS:
		if not t["npcs"].has(nid):
			t["npcs"][nid] = { "id": nid }
	return t

func test_art_json_is_valid() -> void:
	var errs := DataSchema.check_art(art_json(), tables_with_a5())
	assert_eq(errs, PackedStringArray(), "art.json errors")

## ---------------------------------------------------------------- M3c WP-ART

const BATCH4_SAMPLES := ["m_lf_zhizhu", "m_ym_qiangdao", "n_xx_qiaofeng", "n_hn_longmen", "n_ym_lingzhi"]

static func own_file(sprite: String, pose: String = "idle") -> Texture2D:
	return ArtRegistry._texture_at("res://assets/art/units/unit_%s_%s.png" % [sprite, pose])

func test_m3c_batch4_resolves_to_own_files() -> void:
	ArtRegistry.reset()
	for id in BATCH4_SAMPLES:
		var tex := ArtRegistry.unit_texture(id, "", "idle")
		assert_true(tex != null, id)
		assert_eq(tex, own_file(id), id + " uses its own unit_%s_idle.png, not the old alias" % id)
		assert_false(ArtRegistry.is_placeholder(id), id)
	for bg in ["yanmen", "hengshan_s", "hengshan_s_road"]:
		assert_eq(ArtRegistry.battle_background(bg), ArtRegistry._texture_at("res://assets/art/bg/bg_%s.png" % bg), bg)
	# 比例（§2.1）
	assert_eq(ArtRegistry.unit_display("m_lf_zhizhu")["scale"], 0.35)
	assert_eq(ArtRegistry.unit_display("m_lf_qingshe")["scale"], 0.5)
	assert_eq(ArtRegistry.unit_display("n_xx_qiaofeng")["scale"], 1.1)
	assert_eq(ArtRegistry.unit_display("n_amb_etou_xe")["scale"], 1.05)
	assert_eq(ArtRegistry.unit_display("n_hn_longmen")["scale"], 0.95)
	assert_eq(ArtRegistry.unit_display("n_dl_cunmin")["scale"], 1.0)

func test_m3c_sixteen_looks() -> void:
	ArtRegistry.reset()
	var seen := {}
	for g in ["m", "f"]:
		for n in range(1, 9):
			var look := "look_%s%02d" % [g, n]
			var tex := ArtRegistry.unit_texture(look, "PLAYER", "idle")
			assert_eq(tex, own_file(look), look + " idle is its own file")
			assert_false(seen.has(tex), look + " distinct")
			seen[tex] = true
			assert_eq(ArtRegistry.unit_display(look)["scale"], 1.0, look)
			# 姿勢絕不借別人的：有自己的出招圖就用自己的（§11 空手版已交），沒有就 null
			var atk := ArtRegistry.unit_texture(look, "PLAYER", "attack")
			assert_eq(atk, own_file(look, "attack"), look + " attack is own or null, never borrowed")
			assert_true(atk == null or atk != ArtRegistry.unit_texture("player_" + g, "PLAYER", "attack"), look)
	# A2 原意：只有 idle 的造型出招回 null（用假設定驗證，不依賴目前有哪些姿勢圖）
	var cfg := art_json()
	cfg["units"]["look_m05"] = { "sprite": "n_wd_zhangsanfeng", "scale": 1.0 }
	ArtRegistry.use_config(cfg)
	assert_true(ArtRegistry.unit_texture("look_m05", "PLAYER", "idle") != null)
	assert_eq(ArtRegistry.unit_texture("look_m05", "PLAYER", "attack"), null, "idle-only look → null attack")

func test_m3c_a5_aliases() -> void:
	var units: Dictionary = art_json()["units"]
	for id in A5_MONSTERS + A5_NPCS:
		assert_true(units.has(id), "A5 entry " + id)
		assert_true(str(units[id].get("alias", "")) != "", id + " is an alias")
		assert_true(ArtRegistry.unit_texture(id, "", "idle") != null, id + " resolves")

func test_m3c_new_sections_registered() -> void:
	var art := art_json()
	assert_eq(art["map"].keys(), ArtRegistry.MAP_KEYS)
	assert_eq(art["map_icons"].keys(), ArtRegistry.MAP_ICON_KEYS)
	assert_eq(art["weapon_fx"].keys(), ArtRegistry.WEAPON_FX_KEYS)
	assert_eq(art["weapon_icons"].keys(), ArtRegistry.WEAPON_ICON_KEYS)
	# 旗標與實際檔案一致（import_art.py 維護）
	for pair in [["map", "map"], ["map_icons", "map"], ["weapon_fx", "fx"], ["weapon_icons", "icons"]]:
		for key in art[pair[0]]:
			var e: Dictionary = art[pair[0]][key]
			var exists := FileAccess.file_exists("res://assets/art/%s/%s.png" % [pair[1], e["file"]])
			assert_eq(bool(e["placeholder"]), not exists, "%s.%s placeholder flag" % [pair[0], key])

func test_m3c_new_api_real_config() -> void:
	ArtRegistry.reset()
	var art := art_json()
	for key in ArtRegistry.MAP_KEYS:
		var want_null: bool = bool(art["map"][key]["placeholder"])
		assert_eq(ArtRegistry.map_texture(key) == null, want_null, "map " + key)
	assert_eq(ArtRegistry.has_map_art(), not bool(art["map"]["world_base"]["placeholder"]))
	for key in ArtRegistry.WEAPON_FX_KEYS:
		var tex := ArtRegistry.weapon_fx_texture(key)
		assert_eq(tex == null, bool(art["weapon_fx"][key]["placeholder"]), "weapon_fx " + key)
		if tex != null:
			assert_eq(tex.get_size(), Vector2(1024, 512), "fx size " + key)
	for key in ArtRegistry.WEAPON_ICON_KEYS:
		var tex := ArtRegistry.weapon_icon(key)
		assert_eq(tex == null, bool(art["weapon_icons"][key]["placeholder"]), "icon " + key)
	for bad in ["", "spear", "nope"]:
		assert_eq(ArtRegistry.map_texture(bad), null)
		assert_eq(ArtRegistry.map_icon(bad), null)
		assert_eq(ArtRegistry.weapon_fx_texture(bad), null)
		assert_eq(ArtRegistry.weapon_icon(bad), null)

func test_m3c_new_api_injected_art() -> void:
	_tmp = temp_dir("art_m3c")
	for sub in ["map", "fx", "icons"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_tmp.path_join(sub)))
	var img := Image.create(24, 18, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.6, 0.9, 1))
	for f in ["map/map_world_base.png", "map/map_icon_inn.png", "fx/fx_weapon_blade.png", "fx/fx_skill_poison.png", "icons/icon_weapon_whip.png", "map/map_compass.png"]:
		img.save_png(ProjectSettings.globalize_path(_tmp.path_join(f)))
	var cfg := art_json()
	for pair in [["map", "world_base"], ["map_icons", "inn"], ["weapon_fx", "blade"], ["weapon_fx", "poison"], ["weapon_icons", "whip"]]:
		cfg[pair[0]][pair[1]]["placeholder"] = false
	cfg["map"]["compass"]["placeholder"] = true          # 檔案在，但旗標說沒有正式圖 → null
	cfg["map"]["node_room"]["placeholder"] = false       # 旗標說有，檔案不在 → null
	ArtRegistry.use_config(cfg, _tmp)
	assert_true(ArtRegistry.has_map_art())
	assert_eq(ArtRegistry.map_texture("world_base").get_size(), Vector2(24, 18))
	assert_true(ArtRegistry.map_icon("inn") != null)
	assert_eq(ArtRegistry.map_icon("city"), null)
	assert_true(ArtRegistry.weapon_fx_texture("blade") != null)
	assert_true(ArtRegistry.weapon_fx_texture("poison") != null, "fx_skill_ file name")
	assert_eq(ArtRegistry.weapon_fx_texture("sword"), null)
	assert_true(ArtRegistry.weapon_icon("whip") != null)
	assert_eq(ArtRegistry.map_texture("compass"), null, "placeholder flag wins")
	assert_eq(ArtRegistry.map_texture("node_room"), null, "missing file")
	assert_eq(ArtRegistry.map_texture("world_base"), ArtRegistry.map_texture("world_base"), "cached")
	# 沒有區塊的舊設定 → 全部 null、不報錯
	var old := art_json()
	for sec in ["map", "map_icons", "weapon_fx", "weapon_icons"]:
		old.erase(sec)
	ArtRegistry.use_config(old, _tmp)
	assert_false(ArtRegistry.has_map_art())
	assert_eq(ArtRegistry.weapon_fx_texture("blade"), null)

func test_m3c_check_art_new_sections() -> void:
	var t := tables_with_a5()
	var art := art_json()
	art.erase("weapon_icons")
	art["map"]["world_base"]["file"] = "map_world"
	art["map"]["sea"] = { "file": "map_sea" }
	art["map_icons"]["inn"] = { "required": false }
	art["weapon_fx"]["inner"]["file"] = "fx_weapon_inner"
	art["weapon_fx"]["sword"]["placeholder"] = "no"
	var joined := "\n".join(DataSchema.check_art(art, t))
	for frag in ["art.json: missing 'weapon_icons'", "art.map.world_base: file must be 'map_world_base'",
			"art.map.sea: unknown key", "art.map_icons.inn: needs 'file'", "art.weapon_fx.inner: file must be 'fx_skill_inner'",
			"art.weapon_fx.sword: placeholder must be true/false"]:
		assert_true(frag in joined, "expected error: " + frag)
	var art2 := art_json()
	art2["map"] = []
	assert_true("art.map: must be an object" in "\n".join(DataSchema.check_art(art2, t)))

func test_check_art_catches_bad_data() -> void:
	var t := game_tables()
	var art := art_json()
	art["units"]["m_wolf"] = { "alias": "m_nope" }
	art["units"].erase("m_boar")
	art["units"]["m_rabbit"]["scale"] = 0
	art["units"]["huashan_m"] = { "alias": "m_hs_trainee" }   # 明確做出環：huashan_m → m_hs_trainee → huashan_m
	art["units"]["m_hs_trainee"] = { "alias": "huashan_m" }
	art["backgrounds"].erase("dali")
	art["bg_default"] = "nowhere"
	var joined := "\n".join(DataSchema.check_art(art, t))
	for frag in ["m_wolf: alias 'm_nope' missing", "monster 'm_boar' has no art entry", "m_rabbit: scale",
			"alias cycle", "region 'dali' has no background", "bg_default"]:
		assert_true(frag in joined, "expected error: " + frag)

func test_every_monster_npc_and_region_resolves() -> void:
	var t := game_tables()
	for mid in t["monsters"]:
		assert_true(ArtRegistry.unit_texture(mid, "MONSTER", "idle") != null, "idle art for " + mid)
	for nid in ["n_ludayou", "n_guiwang"]:
		assert_true(ArtRegistry.unit_texture(nid, "NPC", "idle") != null, "idle art for " + nid)
	for rid in t["regions"]:
		assert_true(ArtRegistry.battle_background(rid) != null, "background for " + rid)
	for fx in ["hit", "slash", "palm", "tile_escape", "fx_hit"]:
		assert_true(ArtRegistry.fx_texture(fx) != null, "fx " + fx)

func test_player_looks_and_fallbacks() -> void:
	for look in ["player_m", "player_f", "shaolin_m", "huashan_m", "huashan_f"]:
		assert_true(ArtRegistry.unit_texture(look, "PLAYER", "idle") != null, look)
	# 還沒有圖的門派（用不存在的假門派 nosect：art.json 沒條目）→ 依性別退回布衣；有圖的門派用自己的服裝
	assert_eq(ArtRegistry.unit_texture("nosect_f", "PLAYER", "idle"), ArtRegistry.unit_texture("player_f", "PLAYER", "idle"))
	assert_eq(ArtRegistry.unit_texture("nosect_m", "PLAYER", "idle"), ArtRegistry.unit_texture("player_m", "PLAYER", "idle"))
	# 丐幫（M3c：§11 空手版服裝已到、已登記）用自己的圖
	assert_eq(ArtRegistry.unit_texture("gaibang_m", "PLAYER", "idle"), own_file("gaibang_m"))
	assert_true(ArtRegistry.unit_texture("wudang_m", "PLAYER", "idle") != ArtRegistry.unit_texture("player_m", "PLAYER", "idle"), "武當有自己的服裝")
	assert_eq(ArtRegistry.unit_texture("", "PLAYER", "idle"), ArtRegistry.unit_texture("player_m", "PLAYER", "idle"))
	# 別名
	# m_hs_trainee 有自己的正式圖時用自己的，沒有才退回別名 huashan_m（結果依 assets/art_in 匯入了什麼而定）
	var trainee := ArtRegistry.unit_texture("m_hs_trainee", "MONSTER", "idle")
	assert_true(trainee != null, "m_hs_trainee")
	if not FileAccess.file_exists("res://assets/art/units/unit_m_hs_trainee_idle.png"):
		assert_eq(trainee, ArtRegistry.unit_texture("huashan_m", "PLAYER", "idle"))
	assert_eq(ArtRegistry.unit_texture("n_ludayou", "NPC", "idle"), trainee, "n_ludayou → m_hs_trainee")
	assert_eq(ArtRegistry.unit_texture("n_guiwang", "NPC", "idle"), ArtRegistry.unit_texture("m_guiwang", "MONSTER", "idle"))
	# 未知怪物、沒有的姿勢 → null（呼叫端自己處理）
	assert_eq(ArtRegistry.unit_texture("m_unknown_beast", "MONSTER", "idle"), null)
	assert_eq(ArtRegistry.unit_texture("m_wolf", "MONSTER", "victory_dance"), null)

func test_unit_display() -> void:
	assert_eq(ArtRegistry.unit_display("player_m"), { "scale": 1.0, "y_offset": 0.0 })
	assert_eq(ArtRegistry.unit_display("m_rabbit")["scale"], 0.45)
	assert_eq(ArtRegistry.unit_display("m_bigrabbit")["scale"], 0.65)
	assert_eq(ArtRegistry.unit_display("m_wolf")["scale"], 0.7)
	assert_eq(ArtRegistry.unit_display("m_guiwang")["scale"], 1.3)
	assert_eq(ArtRegistry.unit_display("n_guiwang")["scale"], 1.3, "alias inherits")
	assert_eq(ArtRegistry.unit_display("m_hs_trainee")["scale"], 1.0)
	assert_true(float(ArtRegistry.unit_display("m_ghost")["y_offset"]) < 0.0, "ghost floats")
	assert_eq(ArtRegistry.unit_display("m_unknown_beast"), { "scale": 1.0, "y_offset": 0.0 })
	assert_eq(ArtRegistry.unit_display("emei_f")["scale"], 1.0)

func test_background_fallbacks() -> void:
	assert_eq(ArtRegistry.battle_background("xixia"), ArtRegistry.battle_background("xixia_wild"), "city → nearest wild")
	assert_eq(ArtRegistry.battle_background("dali"), ArtRegistry.battle_background("dali_wild"))
	assert_true(ArtRegistry.battle_background("no_such_region") != null, "unknown → default")
	assert_eq(ArtRegistry.battle_background(""), ArtRegistry.battle_background("jingcheng_wild"))
	assert_true(ArtRegistry.battle_background("guiwang") != ArtRegistry.battle_background("huashan"))

func test_real_art_overrides_placeholder_and_alias() -> void:
	_tmp = temp_dir("art")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_tmp.path_join("units")))
	var img := Image.create(8, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0, 1))
	img.save_png(ProjectSettings.globalize_path(_tmp.path_join("units/unit_m_hs_trainee_idle.png")))
	img.save_png(ProjectSettings.globalize_path(_tmp.path_join("units/unit_m_wolf_attack.png")))
	ArtRegistry.use_config(art_json(), _tmp)
	var own := ArtRegistry.unit_texture("m_hs_trainee", "MONSTER", "idle")
	assert_true(own != null)
	assert_eq(own.get_size(), Vector2(8, 16), "dedicated file beats alias")
	assert_eq(ArtRegistry.unit_texture("n_ludayou", "NPC", "idle"), own, "npc alias reaches it too")
	assert_eq(ArtRegistry.unit_texture("m_wolf", "MONSTER", "attack").get_size(), Vector2(8, 16))
	assert_false(ArtRegistry.is_placeholder("m_hs_trainee"))
	assert_true(ArtRegistry.is_placeholder("m_wolf"), "only attack is real")
	var ph := ArtRegistry.unit_texture("m_wolf", "MONSTER", "idle")
	assert_true(ph != null and ph.get_height() == 256, "placeholder normalized to 256 px tall")

func test_ref_for_unit() -> void:
	assert_eq(ArtRegistry.ref_for_unit({ "kind": "PLAYER", "look": "huashan_f" }), "huashan_f")
	assert_eq(ArtRegistry.ref_for_unit({ "kind": "PLAYER" }), "player_m", "old host without look")
	assert_eq(ArtRegistry.ref_for_unit({ "kind": "MONSTER", "ref": "m_wolf" }), "m_wolf")
	assert_eq(ArtRegistry.ref_for_unit({ "kind": "MONSTER" }), "")

func test_battle_look_from_character() -> void:
	var c := F.new_char()
	assert_eq(c.battle_look(), "player_m")
	c.gender = "F"
	assert_eq(c.battle_look(), "player_f")
	c.sect = "huashan"
	assert_eq(c.battle_look(), "huashan_f")
	c.gender = "M"
	c.sect = "shaolin"
	assert_eq(c.to_combatant(F.tables(), F.options(), 0, 1)["look"], "shaolin_m")

func test_snapshot_carries_look_and_ref() -> void:
	var b := make_battle([player_spec({ "look": "shaolin_m" }), monster("m_wolf")])
	var s := b.snapshot(tables())
	var me: Dictionary = s.units[0]
	var foe: Dictionary = s.units[1]
	assert_eq(me["look"], "shaolin_m")
	assert_not_has(me, "ref", "player char id is not exposed")
	assert_eq(foe["ref"], "m_wolf")
	assert_not_has(foe, "look")
	assert_eq(ArtRegistry.ref_for_unit(me), "shaolin_m")
	assert_eq(ArtRegistry.ref_for_unit(foe), "m_wolf")
	# 舊格式的 spec（沒有 look）也能開戰，快照的 look 為空字串 → 客戶端退回 player_m
	var b2 := make_battle([player_spec(), monster("m_rabbit")])
	var me2: Dictionary = b2.snapshot(tables()).units[0]
	assert_eq(me2["look"], "")
	assert_eq(ArtRegistry.ref_for_unit(me2), "player_m")

## 回歸：只有 idle 的門派服裝出招／受傷時不能借別人的姿勢圖（擁有者回報全真出招變成布衣）
## 用假的造型 testlook_m：自己的 sprite 指向一張「只有 idle、沒有出招圖」的 NPC 立繪，不依賴目前有哪些美術
func test_pose_never_borrowed_from_fallback() -> void:
	var cfg: Dictionary = art_json()
	cfg["units"]["testlook_m"] = { "sprite": "n_wd_zhangsanfeng" }
	ArtRegistry.use_config(cfg)
	assert_true(ArtRegistry.unit_texture("testlook_m", "PLAYER", "idle") != null, "自己有 idle")
	assert_eq(ArtRegistry.unit_texture("testlook_m", "PLAYER", "attack"), null, "沒有出招圖 → null（用 idle＋程式動畫），不能借布衣的")
	assert_eq(ArtRegistry.unit_texture("testlook_m", "PLAYER", "hurt"), null)
	assert_true(ArtRegistry.unit_texture("shaolin_m", "PLAYER", "attack") != null, "有出招圖的照用")
	# 完全沒有圖的門派仍退回布衣（idle 與姿勢都用布衣的，同一個人）
	assert_eq(ArtRegistry.unit_texture("nosect_m", "PLAYER", "attack"), ArtRegistry.unit_texture("player_m", "PLAYER", "attack"))
	ArtRegistry.reset()
