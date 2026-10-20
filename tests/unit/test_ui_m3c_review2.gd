extends "res://tests/test_case.gd"
## M3c 審查（第二輪，介面）回歸：
## - 人形與否看 art.json 的 body（野兔不再有拳頭圖示、勞德諾照人的大小畫）；名牌圖示 18 px 畫單字；
##   倒下的目標落點在身體上、目標在正下方時起點挪到身體外側
## - 小地圖「往XXX」不蓋房間框；瀏覽時標題放得下（地圖鈕縮短）
## - 江湖全圖：路線線頭停在圈外、「目的地」不壓地名、「你在這裡」的引線不劃過地名
## - 稀有度：羊皮紙上的深色對比、戰報上色、詳情不寫「官方：」
## - 動手確認框：人多勢眾提醒、新手不寫官兵、CHALLENGE 句子變短；造型提示與屬性窗一致；丐幫乞討戰報有模板

const FX := preload("res://tests/unit/test_m3c_weapon_fx.gd")

var loader: DataLoader
var view: Dictionary
var _nodes: Array = []
var _dir := ""
var _seq := 1900

func before_each() -> void:
	UiSettings.reset_for_tests(true)
	if loader == null:
		loader = DataLoader.new()
		loader.load_all("res://data")
		view = loader.activate(["1.0A"])
	_dir = temp_dir("m3c_review2")
	MapArt.use_textures(null)

func after_each() -> void:
	MapArt.use_textures(null)
	WeaponFx.override_texture("", null)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame
	remove_dir_recursive(_dir)

func _add(n: Node) -> Node:
	tree.root.add_child(n)
	_nodes.append(n)
	return n

# ---------------------------------------------------------------- 人形旗標、圖示、特效幾何
func test_body_flag_overrides_aspect_ratio() -> void:
	assert_eq(ArtRegistry.unit_body("m_rabbit"), "beast", "野兔 272×256 不是人形")
	assert_eq(ArtRegistry.unit_body("m_hunt_yetu"), "beast", "alias 跟著 m_rabbit")
	assert_eq(ArtRegistry.unit_body("n_na_xx_huanggou"), "beast", "黃狗 alias m_wolf")
	for k in ["m_lf_zhizhu", "m_lf_xiezi", "m_xh_scorpion", "m_gm_yufeng", "m_em_mz_ape", "m_lj_xuehu"]:
		assert_eq(ArtRegistry.unit_body(k), "beast", k)
	assert_eq(ArtRegistry.unit_body("m_xx_laodenuo"), "human", "勞德諾 288×256 是人")
	assert_eq(ArtRegistry.unit_body("m_ym_qiangdao"), "human", "強盜 288×256 是人")
	assert_eq(ArtRegistry.unit_body("m_bandit"), "", "沒標的照長寬比")

func _battle_with(units: Array) -> BattleIsoView:
	var st := FX._state()
	st["units"] = units
	var v := BattleIsoView.new()
	_add(v)
	v.size = Vector2(1280, 720)
	v.set_vm(BattleViewModel.from_state(st))
	return v

static func _mon(uid: int, ref: String, nm: String, pos: Array) -> Dictionary:
	return { "uid": uid, "name": nm, "side": 1, "kind": "MONSTER", "peer": 0, "pos": pos, "ref": ref,
		"qi": 60, "qi_max": 60, "gauge": 0.0, "rate": 6.0, "state": "CHARGING", "wtype": "FIST", "wfx": "" }

func test_rabbit_has_no_weapon_icon_humans_do() -> void:
	var st := FX._state()
	var me: Dictionary = st["units"][0]
	var v := _battle_with([me, _mon(2, "m_rabbit", "野兔", [6, 3]), _mon(3, "m_xx_laodenuo", "勞德諾", [8, 1])])
	await tree.process_frame
	await tree.process_frame
	var rabbit: UnitSprite = v.sprites[2]
	var lao: UnitSprite = v.sprites[3]
	assert_true(rabbit.is_tall(), "rabbit art is tall-ish (the old guess)")
	assert_false(rabbit.is_humanoid(), "…but the body flag says beast")
	assert_true(lao.is_humanoid(), "勞德諾 is a person")
	assert_true(lao.is_tall(), "and is sized like a person")
	assert_true((v.sprites[1] as UnitSprite).is_humanoid(), "players are always humanoid")
	v.fx.queue_redraw()
	await tree.process_frame
	assert_eq(rabbit.weapon_kind, "", "no 拳 icon on the rabbit's name plate")
	assert_eq(lao.weapon_kind, "fist", "勞德諾 gets an icon")
	# 野兔咬人：沒有武器特效（照舊打擊火花）
	var e := FX._ev("move_bite", { "atk_uid": 2, "def_uid": 1, "dmg": 3, "def_qi": 170, "crit": false, "cat": "" })
	v.vm.apply_event(e)
	v.on_event(e)
	assert_eq(v.fx.items.filter(func(it): return str(it["type"]) == "weapon").size(), 0, "rabbit bite: no fist fx")

func test_icon_at_name_plate_size_is_a_glyph() -> void:
	assert_true(WeaponFx.ICON_SIZE < WeaponFx.ICON_ART_MIN, "18 px icons use the single-character glyph")
	for k in WeaponFx.ICON_KINDS:
		assert_eq(str(WeaponFx.ICON_GLYPH[k]).length(), 1, k)
	assert_true(WeaponFx.ICON_GLYPH["sword"] != WeaponFx.ICON_GLYPH["blade"], "劍 and 刀 tell apart")

func test_lying_target_hit_lands_on_the_body() -> void:
	var bv := BattleIsoView.new()
	_add(bv)
	bv.size = Vector2(1280, 720)
	bv.set_vm(BattleViewModel.from_state(FX._state()))
	await tree.process_frame
	var me: UnitSprite = bv.sprites[1]
	var wolf: UnitSprite = bv.sprites[2]
	var it := { "type": "weapon", "sprite": me, "target": wolf, "kind": "blade", "miss": false, "start": 0.0, "dur": WeaponFx.DUR }
	var standing: Dictionary = bv.fx.weapon_geom(it)
	wolf.lie = 1.0
	wolf.vis_state = "DEAD"
	var lying: Dictionary = bv.fx.weapon_geom(it)
	assert_true((lying.target as Vector2).y > (standing.target as Vector2).y, "a lying target is hit lower (on the body, not in the air)")
	var expect := wolf.position + wolf.anim_offset + Vector2(0, -wolf.body_top() * 0.5)
	assert_true((lying.target as Vector2).distance_to(expect) < 0.01)

func test_straight_below_target_starts_beside_the_body() -> void:
	var feet := Vector2(400, 300)
	var g := WeaponFx.geometry(feet, 60.0, 120.0, feet + Vector2(4, 30), 64.0, 1.0)
	assert_true(absf((g.origin as Vector2).x - (feet.x + WeaponFx.STEEP_HAND_X * 60.0)) < 0.01, "origin moved to the outer side")
	var side := WeaponFx.geometry(feet, 60.0, 120.0, feet + Vector2(64, 16), 64.0, 1.0)
	assert_true(absf((side.origin as Vector2).x - (feet.x + WeaponFx.HAND_X * 60.0)) < 0.01, "diagonal neighbours keep the front-hand origin")

# ---------------------------------------------------------------- 小地圖
func _room_view(room: String) -> Dictionary:
	var idx := MapData.room_index(view)
	var region: String = idx[room]["region"]
	return { "room": room, "room_name": str(idx[room]["room"]["name"]), "region": region,
		"region_name": MapData.region_name(view, region), "exits": [], "npcs": [] }

func _panel() -> MapPanel:
	var gate := _add(IntentGate.new()) as IntentGate
	gate.set_sender(func(_k, _a):
		_seq += 1
		return _seq)
	var p := MapPanel.new()
	p.gate = gate
	p.tables_override = view
	p.memory = MapMemory.new(_dir)
	_add(p)
	p.size = Vector2(900, 480)
	p.walker.step_delay_s = 0.0
	var mm := MiniMap.new()
	_add(mm)
	mm.size = Vector2(264, 228)
	p.bind_mini_map(mm)
	p.apply_sheet({ "char_id": "ch_review2", "vitals": { "qi": 100, "qi_max": 100, "food": 90, "water": 90 } })
	return p

func test_edge_label_does_not_cover_a_room() -> void:
	var p := _panel()
	for r in ["xx_square", "xx_gate_e", "xw_road", "xw_grass", "xw_wood", "xw_grass", "xw_creek", "xw_grass", "xw_road"]:
		p.apply_view(_room_view(r))
	await tree.process_frame
	await tree.process_frame
	for v in [p.mini_map.view, p.region_view]:
		var rv := v as RegionMapView
		var items: Array = rv.out_exit_items()
		assert_false(items.is_empty(), "edge labels drawn")
		for it in items:
			var lr: Rect2 = it["label_rect"]
			for id in rv._rects:
				if rv.is_shown(str(id)):
					assert_false((rv._rects[id] as Rect2).intersects(lr), "%s label %s covers room %s (zoom %.2f)" % [str(it["label"]), str(lr), str(id), rv.zoom])

func test_minimap_browse_title_fits() -> void:
	var p := _panel()
	for r in ["xx_square", "xx_gate_e", "xw_road", "xx_gate_e"]:
		p.apply_view(_room_view(r))
	p.show_region("xixia_wild")
	assert_eq(p.mini_map.map_button.text, MiniMap.MAP_TEXT_SHORT, "short map button while browsing")
	assert_eq(p.mini_map.title_label.text, "瀏覽 西夏郊外")
	assert_eq(p.mini_map.title_label.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "never cuts half a glyph")
	p.back_to_current()
	assert_eq(p.mini_map.map_button.text, MiniMap.MAP_TEXT, "full button text back")

# ---------------------------------------------------------------- 江湖全圖
func test_world_route_overlays_stay_off_labels() -> void:
	var model := MapData.world_model(view)
	for sz in [Vector2(900, 440), Vector2(760, 440)]:
		var w := WorldMapView.new()
		_add(w)
		w.size = sz
		w.setup(model, "xixia")
		w.set_walk_route(["xixia", "xixia_wild", "xixia_south", "desert_edge", "river_road", "dali_wild"])
		var route: Array = []
		for r in ["xixia", "xixia_wild", "xixia_south", "desert_edge", "river_road", "dali_wild"]:
			if w._marks.has(r):
				route.append(r)
		w.set_walk_route(route)
		if route.size() < 2:
			continue
		# 線頭停在記號的圈外
		for sg in w.walk_route_segments():
			for id in route:
				var c: Vector2 = (w._marks[id] as Rect2).get_center()
				assert_true((sg[0] as Vector2).distance_to(c) >= w._mark_radius(id) - 0.5 or (sg[1] as Vector2).distance_to(c) >= w._mark_radius(id) - 0.5,
					"segment ends outside the ring of %s" % id)
		# 「目的地」不壓地名
		var dr: Rect2 = w.dest_label_rect()
		assert_true(dr.has_area())
		for id in w._labels:
			assert_false((w._labels[id] as Rect2).intersects(dr), "目的地 overlaps the name of %s @ %s" % [id, str(sz)])
	# 「你在這裡」的引線不劃過地名（審查的截圖：在西夏時引線劃過「西夏」）：位置挑不劃過的；真的擠到只能劃過時，
	# 畫的時候字的部分留白（leader_pieces）——畫出來的每一段都不碰任何地名
	for sz2 in [Vector2(760, 440), Vector2(880, 390), Vector2(900, 440), Vector2(1000, 470)]:
		var w2 := WorldMapView.new()
		_add(w2)
		w2.size = sz2
		for r2 in model["regions"]:
			w2.setup(model, str(r2["id"]))
			var here := w2.here_label()
			if here.is_empty():
				continue
			var lead: Array = here.get("leader", [])
			if lead.size() != 2:
				continue
			var pieces: Array = w2.leader_pieces(lead)
			for pc in pieces:
				for id in w2._labels:
					assert_false(MapLayout.segment_hits_rect(pc[0], pc[1], w2._labels[id] as Rect2),
						"%s @ %s: a drawn 你在這裡 leader piece crosses the name of %s" % [r2["id"], str(sz2), id])
			if str(r2["id"]) in ["xixia", "dali"]:
				assert_false(pieces.is_empty(), "%s: the leader is still drawn (outside the names)" % r2["id"])

# ---------------------------------------------------------------- 稀有度、戰報、詳情
static func _contrast(a: Color, b: Color) -> float:
	var la := 0.2126 * pow(a.r, 2.2) + 0.7152 * pow(a.g, 2.2) + 0.0722 * pow(a.b, 2.2)
	var lb := 0.2126 * pow(b.r, 2.2) + 0.7152 * pow(b.g, 2.2) + 0.0722 * pow(b.b, 2.2)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

func test_rarity_colours_readable() -> void:
	var parchment := Color("#efe3c4")
	for r in LootUi.RARITIES:
		assert_true(_contrast(LootUi.paper_color(r), parchment) >= 4.5, "%s on parchment %.2f" % [r, _contrast(LootUi.paper_color(r), parchment)])
		assert_true(_contrast(LootUi.dark_color(r), Color("#1c120c")) >= 4.5, "%s on dark %.2f" % [r, _contrast(LootUi.dark_color(r), Color("#1c120c"))])
	var bb := LootUi.bb_name_paper("精鋼戒", "TREASURE")
	assert_false(bb.contains("[b]"), "no synthetic bold (the 【珍品】 tag and the name looked different)")
	assert_eq(bb.count("[color="), 1, "tag and name share one colour")

func test_battle_log_loot_line_coloured() -> void:
	var line := BattleScreen.loot_log_bb([{ "id": "c_jinchuang", "name": "金創藥", "n": 1, "rarity": "COMMON" },
		{ "id": "a_lt_jinggangjie", "name": "精鋼戒", "n": 1, "rarity": "TREASURE" }], "#ffa040")
	assert_true(line.contains("【珍品】精鋼戒"), line)
	assert_true(line.contains(LootUi.dark_color("TREASURE").to_html(false)), "treasure coloured in the battle log: " + line)

func test_detail_has_no_official_line() -> void:
	var it := { "uid": "u1", "id": "a_lt_jinggangjie", "name": "精鋼戒", "n": 1, "weight": 1, "rarity": "TREASURE",
		"slot": "RING", "req_ok": true, "official": { "def": 10, "weight": 0 } }
	var row := { "id": "a_lt_jinggangjie", "name": "精鋼戒", "slot": "RING", "def": 2, "weight": 1, "rarity": "TREASURE",
		"official": { "def": 10, "weight": 0 } }
	var bb := LootUi.detail_bb(it, row, -1)
	assert_false(bb.contains("官方"), bb)
	assert_true(bb.contains("防禦 +2"), bb)

# ---------------------------------------------------------------- 確認框、造型提示、模板
func test_confirm_text_strength_newbie_and_short_line() -> void:
	var sheet := { "char_id": "c", "sect": "", "combat_xp": 0, "enemy_of": [] }
	var gm := { "id": "n_gm_sunpopo", "name": "孫婆婆", "atk": { "mode": "CHALLENGE", "category": "SECT_GATE", "align": "GOOD",
		"sect": "gumu", "menu_label": "滅派", "via": "MENU", "effect": "ENEMY",
		"foes": [{ "name": "孫婆婆", "n": "1" }, { "name": "古墓弟子", "n": "5" }] } }
	var t := NpcAttackUi.confirm_text(gm, sheet, {}, NpcAttackUi.MODE_MIEPAI)
	assert_true(t.contains("人多勢眾"), t)
	assert_true(t.contains("共 6 人"), t)
	assert_true(t.contains("後果照算") and not t.contains("但上面的後果照算"), "short CHALLENGE line: " + t)
	var dl_view := { "room": "dl_square", "region": "dali" }
	var kid := { "id": "n_na_dl_xiaohai", "name": "小孩", "atk": { "mode": "KILL", "category": "CHILD", "align": "GOOD", "sect": "",
		"via": "CTRL", "effect": "", "guard_spare": true, "morality_guard": false } }
	var t2 := NpcAttackUi.confirm_text(kid, sheet, dl_view)
	assert_false(t2.contains("官兵"), "spared newbie: no guard line: " + t2)
	assert_false(t2.contains("人多勢眾"), "one foe: no crowd line")
	(kid["atk"] as Dictionary)["guard_spare"] = false
	assert_true(NpcAttackUi.confirm_text(kid, sheet, dl_view).contains("招來守城官兵"), "veterans are warned")

func test_look_hint_matches_attributes_panel() -> void:
	assert_false(LookDialog.SECT_HINT.contains("戰鬥中"), LookDialog.SECT_HINT)
	assert_true(LookDialog.SECT_HINT.contains("門派服裝"))

func test_poison_fang_line_renders() -> void:
	var tpl: Dictionary = view.get("text_templates", {})
	if not tpl.has("battle_proc_POISON_FANG"):
		var all: Dictionary = loader.all_tables.get("text_templates", {})
		assert_true(all.has("battle_proc_POISON_FANG"), "template exists (1.0B)")
		tpl = all
	var line := TextRenderer.render_plain({ "ch": "BATTLE", "key": "battle_proc_POISON_FANG",
		"p": { "bid": 8, "def_uid": 2, "name": "介面俠客", "peer": 1, "skill_name": "乞討", "uid": 1 } }, 1, tpl)
	assert_false(line.contains("battle_proc_") or line.contains("{"), line)
