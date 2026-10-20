extends "res://tests/test_case.gd"
## M3C_PLAN §7（WP-FX）：武器出招特效。
## WeaponFx.kind_for 每種組合（各武器類型、爪、六種武功類別、舊主機沒有 cat、獸類回 ""）；
## 主機純表現欄位（快照 wtype／wfx、命中事件 cat、換兵器事件）；
## BattleIsoView＋假 BattleViewModel：拿刀的玩家打狼 → 特效層一筆 blade、起點在前手、角度朝目標；
## 拿劍的玩家打左邊的人 → sword、向左翻轉；狼咬人 → 沒有武器特效（打擊火花）；名牌圖示 kind。

const H := preload("res://tests/unit/test_battle_helpers.gd")

var _nodes: Array = []

func after_each() -> void:
	WeaponFx.override_texture("", null)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame

static func _ev(key: String, p: Dictionary) -> Dictionary:
	var pp := p.duplicate()
	if not pp.has("bid"):
		pp["bid"] = 9
	return { "ch": "BATTLE", "key": key, "bid": 9, "p": pp }

static func _player(wtype: String, wfx := "") -> Dictionary:
	return { "kind": "PLAYER", "wtype": wtype, "wfx": wfx }

# ---------------------------------------------------------------- kind_for

func test_kind_for_weapon_types() -> void:
	var hit := _ev("atk_blade", { "cat": "" })
	assert_eq(WeaponFx.kind_for(_player("SWORD"), hit, true), "sword")
	assert_eq(WeaponFx.kind_for(_player("BLADE"), hit, true), "blade")
	assert_eq(WeaponFx.kind_for(_player("STAFF"), hit, true), "staff")
	assert_eq(WeaponFx.kind_for(_player("WHIP"), hit, true), "whip")
	assert_eq(WeaponFx.kind_for(_player("FIST"), hit, true), "fist")
	assert_eq(WeaponFx.kind_for(_player("SPEAR"), hit, true), "staff", "槍類（本作沒有槍法）畫棍的掃動")
	assert_eq(WeaponFx.kind_for(_player(""), hit, true), "fist", "空字串 → 拳掌")
	assert_eq(WeaponFx.kind_for(_player("LANCE?"), hit, true), "fist", "不明 → 拳掌")
	assert_eq(WeaponFx.kind_for({ "kind": "PLAYER" }, hit, true), "fist", "沒有 wtype（舊主機）→ 拳掌")
	assert_eq(WeaponFx.kind_for({ "kind": "PLAYER", "weapon": { "weapon_type": "SWORD" } }, hit, true), "sword",
		"舊主機沒有 wtype：自己的單位用 weapon.weapon_type")
	# 玩家永遠算人形（畫面傳 false 也一樣）
	assert_eq(WeaponFx.kind_for(_player("BLADE"), hit, false), "blade")

func test_kind_for_claw() -> void:
	var hit := _ev("atk_fist", { "cat": "" })
	assert_eq(WeaponFx.kind_for(_player("FIST", "claw"), hit, true), "claw", "物品 fx = claw → 爪")
	assert_eq(WeaponFx.kind_for(_player("FIST", "glitter"), hit, true), "fist", "不認得的 fx 不算")
	# 用爪類武功（類別 FIST）也是爪
	assert_eq(WeaponFx.kind_for(_player("FIST", "claw"), _ev("move_fist_claw", { "cat": "FIST" }), true), "claw")

func test_kind_for_skill_categories() -> void:
	var u := _player("SWORD")
	assert_eq(WeaponFx.kind_for(u, _ev("move_sword_basic", { "cat": "STAB" }), true), "stab")
	assert_eq(WeaponFx.kind_for(u, _ev("battle_hidden_hit", { "cat": "HIDDEN" }), true), "hidden")
	assert_eq(WeaponFx.kind_for(u, _ev("move_fist_basic", { "cat": "INNER" }), true), "inner")
	assert_eq(WeaponFx.kind_for(u, _ev("battle_poison_ok", { "cat": "POISON" }), true), "poison")
	assert_eq(WeaponFx.kind_for(u, _ev("battle_medic", { "cat": "MEDIC" }), true), "medic")
	assert_eq(WeaponFx.kind_for(u, _ev("battle_formation_on", { "cat": "FORMATION" }), true), "formation")
	# 兵器類武功（刀法）照實際裝備的兵器
	assert_eq(WeaponFx.kind_for(_player("BLADE"), _ev("move_blade_basic", { "cat": "BLADE" }), true), "blade")
	# 技能類別優先於非人形判斷（第 1 步在第 2 步之前）
	assert_eq(WeaponFx.kind_for({ "kind": "MONSTER", "wtype": "FIST" }, _ev("battle_poison_ok", { "cat": "POISON" }), false), "poison")

func test_kind_for_old_host_without_cat() -> void:
	var u := _player("BLADE")
	assert_eq(WeaponFx.kind_for(u, _ev("battle_hidden_hit", {}), true), "hidden")
	assert_eq(WeaponFx.kind_for(u, _ev("battle_hidden_miss", {}), true), "hidden")
	assert_eq(WeaponFx.kind_for(u, _ev("battle_poison_ok", {}), true), "poison")
	assert_eq(WeaponFx.kind_for(u, _ev("battle_poison_fail", {}), true), "poison")
	assert_eq(WeaponFx.kind_for(u, _ev("battle_medic", {}), true), "medic")
	assert_eq(WeaponFx.kind_for(u, _ev("battle_formation_on", {}), true), "formation")
	assert_eq(WeaponFx.kind_for(u, _ev("battle_acupoint_ok", {}), true), "stab")
	assert_eq(WeaponFx.kind_for(u, _ev("atk_blade", {}), true), "blade", "一般命中沒有 cat → 兵器")
	assert_eq(WeaponFx.kind_for(u, _ev("battle_miss", {}), true), "blade")
	# 點穴武功的類別是拳（cat 不是技能類別）→ 依事件 key 仍是刺
	assert_eq(WeaponFx.kind_for(u, _ev("battle_acupoint_ok", { "cat": "FIST" }), true), "stab")

func test_kind_for_beasts_and_humanoid_monsters() -> void:
	var hit := _ev("atk_fist", { "cat": "" })
	assert_eq(WeaponFx.kind_for({ "kind": "MONSTER", "wtype": "FIST" }, hit, false), "", "獸類 → 既有火花")
	assert_eq(WeaponFx.kind_for({ "kind": "MONSTER", "wtype": "BLADE" }, hit, false), "", "非人形就算有 wtype 也不畫")
	assert_eq(WeaponFx.kind_for({ "kind": "MONSTER", "wtype": "BLADE" }, hit, true), "blade", "人形怪（山賊）拿刀")
	assert_eq(WeaponFx.kind_for({ "kind": "NPC", "wtype": "SWORD" }, hit, true), "sword")
	assert_eq(WeaponFx.kind_for({ "kind": "MONSTER" }, hit, true), "fist", "人形怪沒有兵器 → 拳掌")
	assert_eq(WeaponFx.icon_kind({ "kind": "MONSTER", "wtype": "FIST" }, false), "")
	assert_eq(WeaponFx.icon_kind(_player("WHIP"), false), "whip")

func test_placement() -> void:
	assert_eq(WeaponFx.placement("medic"), "target")
	assert_eq(WeaponFx.placement("formation"), "ground")
	for k in ["sword", "blade", "staff", "whip", "fist", "claw", "stab", "hidden", "inner", "poison"]:
		assert_eq(WeaponFx.placement(k), "attack", k)

# ---------------------------------------------------------------- 幾何與時序

func test_geometry_hand_angle_flip() -> void:
	var feet := Vector2(100, 200)
	var g := WeaponFx.geometry(feet, 80.0, 100.0, Vector2(300, 150), 64.0)
	assert_true((g.origin as Vector2).is_equal_approx(feet + Vector2(0.28 * 80.0, -0.55 * 100.0)), "前手：面向右")
	assert_true(absf(float(g.angle) - ((Vector2(300, 150) - (g.origin as Vector2)).angle())) < 0.0001, "朝目標")
	assert_false(bool(g.flip), "向右不翻轉")
	var d := (Vector2(300, 150) - (g.origin as Vector2)).length()
	assert_true(is_equal_approx(float(g.length), minf(d * 0.9, 1.6 * 64.0)), "長度 = min(距離 × 0.9, 1.6 格寬)")
	assert_true(is_equal_approx(float(g.height), float(g.length) * 0.5))
	var g2 := WeaponFx.geometry(feet, 80.0, 100.0, Vector2(20, 160), 64.0)
	assert_true((g2.origin as Vector2).is_equal_approx(feet + Vector2(-0.28 * 80.0, -0.55 * 100.0)), "前手：面向左")
	assert_true(bool(g2.flip), "向左垂直翻轉")
	# 很近：長度 = 距離 × 0.9（不超過目標）
	var g3 := WeaponFx.geometry(feet, 80.0, 100.0, feet + Vector2(60, -55), 64.0)
	assert_true(float(g3.length) <= ((feet + Vector2(60, -55)) - (g3.origin as Vector2)).length() * 0.9 + 22.5, "近身不會畫太長")

func test_timing() -> void:
	assert_true(is_equal_approx(WeaponFx.DUR, 0.28), "全長 0.28 秒")
	assert_eq(WeaponFx.alpha_at(-0.01), 0.0)
	assert_true(WeaponFx.alpha_at(0.03) > 0.4 and WeaponFx.alpha_at(0.03) < 0.6, "淡入")
	assert_eq(WeaponFx.alpha_at(0.1), 1.0, "停")
	assert_true(WeaponFx.alpha_at(0.23) < 1.0 and WeaponFx.alpha_at(0.23) > 0.0, "淡出")
	assert_eq(WeaponFx.alpha_at(0.29), 0.0)

# ---------------------------------------------------------------- 主機純表現欄位（§7.2）

func test_host_snapshot_wtype_wfx() -> void:
	var t: Dictionary = H.tables().duplicate(true)
	var items: Dictionary = t.get("items", {}).duplicate(true)
	items["w_test_claw"] = { "id": "w_test_claw", "name": "鐵爪", "weapon_type": "FIST", "fx": "claw" }
	t["items"] = items
	var p := H.player_spec()
	var claw := H.player_spec({ "peer": 2, "name": "爪客", "weapon": H.weapon("it_9", "w_test_claw", "FIST", 5, "鐵爪"),
		"weapon_options": [H.weapon("it_9", "w_test_claw", "FIST", 5, "鐵爪")] })
	var b := Battle.new(1, 7, H.default_opts())
	b.add_unit(p)
	b.add_unit(claw)
	b.add_unit(H.monster("m_wolf"))
	b.start(t)
	var snap := b.snapshot(t)
	var u1: Dictionary = snap.units[0]
	var u2: Dictionary = snap.units[1]
	var u3: Dictionary = snap.units[2]
	assert_eq(str(u1.get("wtype", "?")), "BLADE", "玩家拿木刀")
	assert_eq(str(u1.get("wfx", "?")), "", "木刀沒有 fx")
	assert_eq(str(u2.get("wfx", "?")), "claw", "爪類兵器的 fx")
	assert_true(u3.has("wtype"), "怪物也有 wtype")
	assert_eq(str(u3.get("wtype")), str(t.monsters.m_wolf.get("weapon_type", "FIST")), "怪物＝怪物列 weapon_type")
	assert_eq(str(u3.get("wfx", "?")), "")

func test_host_hit_events_have_cat() -> void:
	var t := H.tables()
	var b := H.make_battle([H.player_spec({ "skills": { "basic_blade": 30 } }), H.monster("m_rabbit", { "qi": 5000, "qi_max": 5000 })], 99)
	H.place(b, 1, 5, 3)
	H.place(b, 2, 6, 3)
	var out := H.do_cmd(b, 1, { "cmd": "ATTACK", "target": [6, 3] })
	var found := 0
	for e in out.get("events", []):
		var k := str(e.get("key", ""))
		if k == "battle_miss" or k.begins_with("atk_"):
			if int(e.p.get("atk_uid", 0)) == 1:
				assert_true(e.p.has("cat"), "命中／未命中帶 cat")
				assert_eq(str(e.p.get("cat", "?")), "", "普攻 cat 空字串")
				found += 1
	assert_true(found >= 1, "有出手事件")
	# 換兵器事件帶新的 wtype
	var b2 := H.make_battle([H.player_spec(), H.monster("m_rabbit", { "qi": 5000, "qi_max": 5000 })], 5)
	var out2 := H.do_cmd(b2, 1, { "cmd": "EQUIP", "item_uid": "it_0002" })
	var eq: Array = H.find(out2.get("events", []), "battle_equip")
	assert_eq(eq.size(), 1)
	if eq.size() == 1:
		assert_eq(str(eq[0].p.get("wtype", "")), "SWORD", "換木劍")
		assert_true(eq[0].p.has("wfx"))
	assert_eq(t.is_empty(), false)

func test_host_art_hit_cat_is_category() -> void:
	var t := H.tables()
	# 找一個資料表裡的兵器類武功（刀法），用它出招 → cat = BLADE
	var art := ""
	var mv := ""
	for id in t.get("martial_arts", {}):
		var row: Dictionary = t.martial_arts[id]
		if str(row.get("category", "")) == "BLADE" and not (row.get("moves", []) as Array).is_empty():
			var m0: Dictionary = row.moves[0]
			if int(m0.get("unlock_level", 1)) <= 1 and int(m0.get("cost_inner", 0)) == 0 and int(m0.get("range", 1)) >= 1 \
					and str(m0.get("aoe", "SINGLE")) == "SINGLE":
				art = str(id)
				mv = str(m0.get("id", ""))
				break
	if art == "":
		return   # 測試資料表沒有刀法：略過
	var b := H.make_battle([H.player_spec({ "skills": { art: 30, "basic_blade": 30 }, "arts": [art] }),
		H.monster("m_rabbit", { "qi": 5000, "qi_max": 5000 })], 11)
	H.place(b, 1, 5, 3)
	H.place(b, 2, 6, 3)
	var out := H.do_cmd(b, 1, { "cmd": "ART", "art": art, "move": mv, "target": [6, 3], "power_tenths": 10 })
	var cats: Array = []
	for e in out.get("events", []):
		if int(e.p.get("atk_uid", 0)) == 1 and e.p.has("cat"):
			cats.append(str(e.p.cat))
	assert_true(not cats.is_empty(), "出招事件帶 cat（%s）" % str(out.get("err", "")))
	for c in cats:
		assert_eq(c, "BLADE", "用刀法時 cat = 武功類別")

# ---------------------------------------------------------------- 畫面（BattleIsoView＋假 VM）

static func _state() -> Dictionary:
	return {
		"bid": 9, "w": 12, "h": 8, "tick": 0, "wait_mode": true, "my_uid": 1,
		"escape": [[0, 6], [11, 1]],
		"units": [
			{ "uid": 1, "name": "持刀俠客", "side": 0, "kind": "PLAYER", "peer": 1, "pos": [5, 3], "look": "player_m",
			  "qi": 180, "qi_max": 180, "gauge": 0.0, "rate": 7.0, "state": "CHARGING", "wtype": "BLADE", "wfx": "",
			  "weapon": { "uid": "it_0001", "name": "木刀", "weapon_type": "BLADE" },
			  "weapon_options": [ { "uid": "it_0001", "name": "木刀", "weapon_type": "BLADE" },
				{ "uid": "it_0002", "name": "木劍", "weapon_type": "SWORD" } ] },
			{ "uid": 2, "name": "灰狼", "side": 1, "kind": "MONSTER", "peer": 0, "pos": [6, 3], "ref": "m_wolf",
			  "qi": 60, "qi_max": 60, "gauge": 0.0, "rate": 6.25, "state": "CHARGING", "wtype": "FIST", "wfx": "" },
			{ "uid": 3, "name": "使劍客", "side": 1, "kind": "PLAYER", "peer": 2, "pos": [8, 1], "look": "player_m",
			  "qi": 180, "qi_max": 180, "gauge": 0.0, "rate": 7.0, "state": "CHARGING", "wtype": "SWORD", "wfx": "" },
		],
	}

func _view() -> BattleIsoView:
	var v := BattleIsoView.new()
	tree.root.add_child(v)
	_nodes.append(v)
	v.size = Vector2(1280, 720)
	v.set_vm(BattleViewModel.from_state(_state()))
	return v

func _send(v: BattleIsoView, key: String, p: Dictionary) -> void:
	var e := _ev(key, p)
	v.vm.apply_event(e)
	v.on_event(e)

func _weapon_items(v: BattleIsoView) -> Array:
	return v.fx.items.filter(func(it): return str(it["type"]) == "weapon")

func test_view_blade_hit_on_wolf() -> void:
	var v := _view()
	await tree.process_frame
	var me: UnitSprite = v.sprites[1]
	var wolf: UnitSprite = v.sprites[2]
	assert_true(me.is_tall(), "玩家是人形")
	assert_false(wolf.is_tall(), "狼不是人形")
	_send(v, "atk_blade", { "atk_uid": 1, "def_uid": 2, "dmg": 12, "def_qi": 48, "crit": false, "cat": "" })
	var w := _weapon_items(v)
	assert_eq(w.size(), 1, "特效層一筆武器特效")
	if w.size() != 1:
		return
	var it: Dictionary = w[0]
	assert_eq(str(it.kind), "blade", "拿刀 → 刀光")
	assert_false(bool(it.miss))
	assert_true(it.sprite == me and it.target == wolf)
	# 時序：命中前 0.06 秒出現（命中＝動畫起點 + IMPACT_AT）
	var lead := (me.ready_at - BattleIsoView.LUNGE_DUR + BattleIsoView.IMPACT_AT) - float(it.start)
	assert_true(absf(lead - WeaponFx.LEAD) < 0.02, "命中前 %.3f 秒出現" % lead)
	assert_true(is_equal_approx(float(it.dur), 0.28))
	# 沒有另外的打擊火花（人形用武器特效取代）
	assert_eq(v.fx.items.filter(func(x): return str(x["type"]) == "burst").size(), 0, "人形出手不畫舊火花")
	# 幾何：起點在攻擊者前手、角度朝狼身體中心、向右不翻轉
	var g := v.fx.weapon_geom(it)
	var feet := me.position + me.anim_offset
	var hand := feet + Vector2(0.28 * me.figure_width(), -0.55 * me.figure_height())
	assert_true((g.origin as Vector2).distance_to(hand) < 0.01, "起點＝前手 %s vs %s" % [str(g.origin), str(hand)])
	var center := wolf.position + wolf.anim_offset + Vector2(0, -wolf.body_top() * 0.5)   # M3c 第二輪審查：現在的身高
	assert_true(absf(wrapf(float(g.angle) - (center - (g.origin as Vector2)).angle(), -PI, PI)) < 0.001, "朝目標")
	assert_false(bool(g.flip), "向右不翻轉")
	assert_true(float(g.length) <= 1.6 * v.tile_w + 0.01)

func test_view_sword_toward_left_flips() -> void:
	var v := _view()
	await tree.process_frame
	# 使劍客（在右上）打持刀俠客（左下）：劍、向左翻轉
	_send(v, "atk_sword", { "atk_uid": 3, "def_uid": 1, "dmg": 9, "def_qi": 171, "crit": false, "cat": "" })
	var w := _weapon_items(v)
	assert_eq(w.size(), 1)
	if w.size() != 1:
		return
	assert_eq(str(w[0].kind), "sword")
	var sw: UnitSprite = v.sprites[3]
	var g := v.fx.weapon_geom(w[0])
	var feet := sw.position + sw.anim_offset
	assert_true((g.origin as Vector2).x < feet.x, "面向左：前手在左邊")
	assert_true((g.origin as Vector2).distance_to(feet + Vector2(-0.28 * sw.figure_width(), -0.55 * sw.figure_height())) < 0.01)
	assert_true(bool(g.flip), "指向左半邊時垂直翻轉")
	# 未命中也畫（較淡）
	_send(v, "battle_miss", { "atk_uid": 3, "def_uid": 1, "move": "木劍", "cat": "" })
	var w2 := _weapon_items(v)
	assert_eq(w2.size(), 2)
	if w2.size() == 2:
		assert_true(bool(w2[1].miss), "未命中標記")

func test_view_wolf_bite_keeps_spark() -> void:
	var v := _view()
	await tree.process_frame
	_send(v, "atk_fist", { "atk_uid": 2, "def_uid": 1, "dmg": 5, "def_qi": 175, "crit": false, "cat": "" })
	assert_eq(_weapon_items(v).size(), 0, "獸類沒有武器特效")
	assert_eq(v.fx.items.filter(func(x): return str(x["type"]) == "burst").size(), 1, "維持既有的打擊火花")

func test_view_skill_fx_placements() -> void:
	var v := _view()
	await tree.process_frame
	_send(v, "battle_hidden_hit", { "atk_uid": 1, "def_uid": 2, "dmg": 7, "def_qi": 53, "part": "胸口", "cat": "HIDDEN",
		"item_name": "飛刀", "item_uid": "x", "left": 3 })
	_send(v, "battle_medic", { "atk_uid": 1, "def_uid": 1, "heal": 20, "cured": false, "def_qi": 180, "cat": "MEDIC" })
	_send(v, "battle_formation_on", { "uid": 1, "name": "持刀俠客", "peer": 1, "art": "x", "art_name": "陣", "members": [], "member_uids": [1] })
	var kinds: Array = _weapon_items(v).map(func(it): return str(it.kind))
	assert_true(kinds.has("hidden"), "暗器 %s" % str(kinds))
	assert_true(kinds.has("medic"), "醫 %s" % str(kinds))
	assert_true(kinds.has("formation"), "陣 %s" % str(kinds))
	for it in _weapon_items(v):
		if str(it.kind) == "medic":
			assert_true(it.sprite == v.sprites[1], "醫畫在目標身上")
		if str(it.kind) == "formation":
			assert_true(it.sprite == v.sprites[1] and it.target == null, "陣畫在施術者腳下")

func test_name_plate_icon_kinds() -> void:
	var v := _view()
	await tree.process_frame
	var list: Array = v.sprites.values()
	v.fx._reserve_badges(list)
	assert_eq((v.sprites[1] as UnitSprite).weapon_kind, "blade", "持刀 → 刀")
	assert_eq((v.sprites[2] as UnitSprite).weapon_kind, "", "狼不畫")
	assert_eq((v.sprites[3] as UnitSprite).weapon_kind, "sword", "使劍 → 劍")
	assert_true((v.sprites[1] as UnitSprite).icon_room() > 0.0, "名牌留出圖示位置")
	assert_eq((v.sprites[2] as UnitSprite).icon_room(), 0.0)
	# 換兵器（主機事件帶 wtype）→ 圖示跟著換
	_send(v, "battle_equip", { "uid": 1, "name": "持刀俠客", "peer": 1, "item_name": "木劍", "item_uid": "it_0002", "wtype": "SWORD", "wfx": "" })
	v.fx._reserve_badges(list)
	assert_eq((v.sprites[1] as UnitSprite).weapon_kind, "sword", "換木劍 → 劍")
	# 舊主機的換兵器事件（沒有 wtype）：自己的單位依 weapon_options 對回
	_send(v, "battle_equip", { "uid": 1, "name": "持刀俠客", "peer": 1, "item_name": "木刀", "item_uid": "it_0001" })
	v.fx._reserve_badges(list)
	assert_eq((v.sprites[1] as UnitSprite).weapon_kind, "blade")
	assert_eq(v.vm.weapon_kind(3, true), "sword")
	# 名牌左端的圖示圓心在牌子裡
	var box := Rect2(Vector2(100, 50), Vector2(120, 30))
	var c := BattleFx.icon_center(box, 20.0)
	assert_true(box.has_point(c), "圖示在名牌內")
	assert_true(c.x < box.get_center().x, "在名牌左側")

func test_texture_override_and_draw_all_kinds() -> void:
	# 沒有圖時 ArtRegistry 回 null → 程式備援；注入假圖時用圖。所有種類都畫得出來（不報錯）
	var ci := RenderingServer.canvas_item_create()
	var glow := RenderingServer.canvas_item_create()
	var g := WeaponFx.geometry(Vector2(100, 200), 80.0, 100.0, Vector2(250, 160), 64.0)
	for k in ArtRegistryKeys.WEAPON_FX:
		WeaponFx.draw_strike(ci, glow, k, g, 0.1, 1.0)
	WeaponFx.draw_medic(ci, glow, Vector2(100, 150), 100.0, 64.0, 0.1, 1.0)
	WeaponFx.draw_formation(ci, glow, Vector2(100, 200), 64.0, 0.1, 1.0)
	var img := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	WeaponFx.override_texture("fx:blade", tex)
	WeaponFx.override_texture("icon:blade", tex)
	assert_true(WeaponFx.fx_texture("blade") == tex, "有圖用圖")
	assert_true(WeaponFx.icon_texture("blade") == tex)
	WeaponFx.draw_strike(ci, glow, "blade", g, 0.1, 1.0)
	WeaponFx.override_texture("", null)
	RenderingServer.free_rid(ci)
	RenderingServer.free_rid(glow)

class ArtRegistryKeys:
	const WEAPON_FX := ["sword", "blade", "staff", "whip", "fist", "claw", "stab", "hidden", "inner", "poison", "medic", "formation"]
