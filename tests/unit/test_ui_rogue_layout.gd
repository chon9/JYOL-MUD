extends "res://tests/test_case.gd"
## 江湖試煉畫面在 1280×720 的版面（0.7.x 試煉審查建議的回歸測試）：
## 每一張真的卡（含已會武功的精進卡、帶行囊的兵器卡）內容高度都塞得進卡框；選卡畫面放最高的三張時，
## 卡片、「選定」鈕、訊息列互不重疊，也都在畫面內；選取下沉 8 px 仍在卡片列裡。

const VIEW := Vector2i(1280, 720)

var tables: Dictionary = {}
var r: Dictionary = {}
var _nodes: Array = []

func before_each() -> void:
	UiSettings.reset_for_tests(true)
	if tables.is_empty():
		var loader := DataLoader.new()
		loader.load_all("res://data")
		tables = loader.activate(["1.0A", "1.0B", "rogue"])
	r = RogueRules.rules(tables)

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame

## 有武功、三把兵器的角色：卡面會出現精進、相合／不合、丟掉哪一把等最長的文字
func _rich_char() -> Character:
	var ch := Character.new()
	ch.id = "rg_layout"
	ch.gender = "M"
	for a in Character.ATTR_IDS:
		ch.attrs[a] = 20
	var g := RandomNumberGenerator.new()
	g.seed = 3
	for id in ["a_bupao", "w_qingfeng", "w_gangdao", "w_mudao"]:
		var add := ch.inventory.add(id, 1, tables, 0.0, -1, func() -> String: return CharacterFactory.new_item_uid(ch.inventory, g))
		if id in ["a_bupao", "w_qingfeng"]:
			ch.inventory.equip(str(add.uid), tables)
	for art in tables.martial_arts:
		if tables.rogue_cards.has("rg_c_art_" + str(art)):
			ch.skills.set_level(str(art), 30, tables)
	return ch

func _snapshots() -> Array:
	var out: Array = []
	var run := RogueRun.new()
	run.seed = 1
	run.round = 6
	for ch in [null, _rich_char()]:
		for id in tables.rogue_cards:
			var snap := RogueDraw.snapshot(tables.rogue_cards[id], 0, run, ch, tables, r)
			if not snap.is_empty():
				out.append(snap)
	return out

func _viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = VIEW
	vp.disable_3d = true
	tree.root.add_child(vp)
	_nodes.append(vp)
	return vp

## 卡片排好版（卡大小固定 260×340、等兩個 frame 讓自動換行算出寬度）後量內容高度
func _measure(vp: SubViewport, snaps: Array) -> Array:
	var made: Array = []
	for snap in snaps:
		var c := RogueCard.new(snap)
		vp.add_child(c)
		c.size = RogueCard.CARD_SIZE
		made.append(c)
	await tree.process_frame
	await tree.process_frame
	var out: Array = []
	for c in made:
		out.append([(c as RogueCard).data, (c as RogueCard).frame.get_combined_minimum_size()])
		(c as RogueCard).free()
	return out

func test_every_card_fits_its_frame() -> void:
	var vp := _viewport()
	var kinds := {}
	var tallest := 0.0
	for m in await _measure(vp, _snapshots()):
		var snap: Dictionary = m[0]
		var ms: Vector2 = m[1]
		kinds[str(snap.kind)] = true
		tallest = maxf(tallest, ms.y)
		assert_true(ms.y <= RogueCard.CARD_SIZE.y, "%s 高 %.0f > %.0f：%s" % [snap.id, ms.y, RogueCard.CARD_SIZE.y, str(snap.lines)])
		assert_true(ms.x <= RogueCard.CARD_SIZE.x, "%s 寬 %.0f > %.0f" % [snap.id, ms.x, RogueCard.CARD_SIZE.x])
	assert_eq(kinds.size(), 4, "四種卡都量到")
	assert_true(tallest > 200.0, "真的量到排好的高度（最高 %.0f）" % tallest)
	print("      rogue card tallest content: %.0f / %.0f" % [tallest, RogueCard.CARD_SIZE.y])

func test_pick_screen_no_overlap_at_1280x720() -> void:
	var vp := _viewport()
	# 每種最高的卡
	var worst := {}
	for m in await _measure(vp, _snapshots()):
		var snap: Dictionary = m[0]
		var h: float = (m[1] as Vector2).y
		var k := str(snap.kind)
		if k != "ATTR" and (not worst.has(k) or h > float(worst[k][0])):
			worst[k] = [h, snap]
	var s: RogueScreen = (load("res://ui/game/rogue/rogue_screen.tscn") as PackedScene).instantiate()
	vp.add_child(s)
	await tree.process_frame
	var cards: Array = []
	var i := 0
	for k in ["ALLY", "WEAPON", "ART"]:
		var sn: Dictionary = (worst[k][1] as Dictionary).duplicate(true)
		sn["idx"] = i
		cards.append(sn)
		i += 1
	var arts: Array = []
	for a in ["basic_sword", "basic_inner", "basic_dodge", "basic_fist", "hs_jianfa", "wd_shenfa"]:
		arts.append({ "id": a, "name": SkillBook.skill_name(a, tables), "level": 60, "category": "BASIC" })
	s.apply_state({ "phase": "PICK", "round": 12, "cards": cards, "attrs": { "str": 20 }, "arts": arts,
		"allies": [{ "name": "周芷若", "alive": true, "qi_pct": 0.5, "rarity": "RARE" }, { "name": "小黃", "alive": false }],
		"weapons": [{ "uid": "u1", "name": "青鋒劍", "weapon_type": "SWORD", "atk": 15, "equipped": true },
			{ "uid": "u2", "name": "鬼頭刀", "weapon_type": "BLADE", "atk": 12 }, { "uid": "u3", "name": "長鞭", "weapon_type": "WHIP", "atk": 9 }],
		"gear": { "ARMOR": { "name": "皮甲" }, "HEAD": { "name": "頭巾" }, "BOOTS": { "name": "布鞋" } } })
	for m in ["第 3 回合得勝，稍事調息，氣血回復 120。", "你取得了〔良〕青鋒劍。", "周芷若願與你並肩作戰。", "名人現身試煉場！"]:
		s.add_message(m)
	s.show_error("【系統】現在不能這麼做。")
	await tree.process_frame
	await tree.process_frame
	var screen := Rect2(Vector2.ZERO, Vector2(VIEW))
	var row := s.cards_row.get_global_rect()
	for c in s.cards:
		var cr: Rect2 = (c as RogueCard).get_global_rect()
		assert_true(screen.encloses(cr), "卡在畫面內 %s" % cr)
		assert_true(row.encloses(cr), "卡在卡片列內")
		assert_true((c as RogueCard).frame.get_combined_minimum_size().y <= cr.size.y, "內容塞得進")
	for a in s.cards.size():
		for b in range(a + 1, s.cards.size()):
			assert_false((s.cards[a] as Control).get_global_rect().intersects((s.cards[b] as Control).get_global_rect()), "卡片不重疊")
	var btn := s.pick_button.get_global_rect()
	var msg := s.msg_label.get_global_rect()
	assert_true(row.end.y <= btn.position.y, "選定鈕在卡片下方")
	assert_true(btn.end.y <= msg.position.y, "選定鈕不壓到訊息列")
	assert_true(screen.encloses(msg) and screen.encloses(s.err_label.get_global_rect()), "訊息列在畫面內")
	assert_false(s.hud.get_global_rect().intersects(row), "HUD 不壓到卡片")
	s.select_card(1)
	await tree.process_frame
	var fr: Rect2 = (s.cards[1] as RogueCard).frame.get_global_rect()
	assert_true(fr.end.y <= btn.position.y, "選取下沉後仍在選定鈕上方")
	for k2 in s.hud.art_rows:
		var t: String = (s.hud.art_rows[k2] as Label).text
		assert_false(t.contains("BASIC"), "HUD 不印代碼：" + t)

## 第二輪審查：大廳（檔案內容多：名人錄全開、最近 5 局）、配點、結算在 1280×720 都塞得下，訊息列與錯誤列在畫面內
func test_lobby_alloc_over_fit_at_1280x720() -> void:
	var vp := _viewport()
	var s: RogueScreen = (load("res://ui/game/rogue/rogue_screen.tscn") as PackedScene).instantiate()
	vp.add_child(s)
	await tree.process_frame
	var fam := {}
	var all := {}
	for f in RogueLobbyPanel.famous_list(tables):
		if f["foe"] != "":
			fam[f["foe"]] = 3
		if f["card"] != "":
			all[f["card"]] = 2
	var hist: Array = []
	for i in 5:
		hist.append({ "wins": 14, "bosses": 2, "cause": "DEATH", "points": 4, "best_card": { "title": "飄雪穿雲掌 45 級", "rarity": "TREASURE" } })
	s.lobby.apply_profile({ "points_total": 60, "runs": 30, "best_wins": 18, "foes_beaten": 400, "bosses_beaten": 40,
		"famous_beaten": fam, "famous_allied": all, "history": hist }, tables)
	s.add_message("第 3 回合得勝，稍事調息，氣血回復 120。")
	s.show_error("無法開始試煉：連線失敗，請稍後再試。")
	await tree.process_frame
	await tree.process_frame
	var screen := Rect2(Vector2.ZERO, Vector2(VIEW))
	assert_true(RogueLobbyPanel.famous_list(tables).size() >= 10, "名人錄有內容")
	assert_true(screen.encloses(s.lobby.get_global_rect()), "大廳在畫面內 %s" % s.lobby.get_global_rect())
	assert_true(screen.encloses(s.err_label.get_global_rect()), "大廳的錯誤列在畫面內 %s" % s.err_label.get_global_rect())
	assert_true(screen.encloses(s.msg_label.get_global_rect()), "大廳的訊息列在畫面內")
	assert_true(s.lobby.get_global_rect().end.y <= s.msg_label.get_global_rect().position.y, "大廳不壓到訊息列")
	assert_true(s.lobby.list_scroll.get_global_rect().size.y <= RogueLobbyPanel.LIST_MAX_H + 1.0, "名人錄／最近 5 局區塊有高度上限（捲動）")
	print("      rogue lobby: %s  err %s" % [s.lobby.get_global_rect(), s.err_label.get_global_rect()])
	# 配點
	s.apply_state({ "phase": "ALLOC", "roll": { "str": 20, "con": 20, "agi": 20, "guts": 20, "cal": 20, "wit": 20, "luck": 20 },
		"alloc_points": 65, "run_id": "a" })
	await tree.process_frame
	await tree.process_frame
	assert_true(screen.encloses(s.alloc_panel.get_global_rect()), "配點在畫面內 %s" % s.alloc_panel.get_global_rect())
	assert_true(screen.encloses(s.err_label.get_global_rect()), "配點時錯誤列在畫面內")
	# 結算
	s.summary = { "cause": "DEATH", "allies_standing": 1, "rounds": 15, "wins": 14, "foes_beaten": 30, "bosses_beaten": 2,
		"best_card": { "title": "飄雪穿雲掌 45 級", "rarity": "TREASURE" }, "allies_recruited": 2, "points_gained": 4, "points_total": 60,
		"points_cap": 60, "new_best": true }
	s._show_over()
	await tree.process_frame
	await tree.process_frame
	assert_true(screen.encloses(s.summary_panel.get_global_rect()), "結算在畫面內 %s" % s.summary_panel.get_global_rect())
	assert_true(screen.encloses(s.err_label.get_global_rect()), "結算時錯誤列在畫面內")
	assert_true(s.summary_panel.get_global_rect().end.y <= s.msg_label.get_global_rect().position.y, "結算不壓到訊息列")

## 第二輪審查：屬性分配窗、放棄確認是強制回應的——後面墊暗幕擋滑鼠；開著時不能換卡；確定時送給開窗時的那一張
func test_popups_are_modal() -> void:
	var vp := _viewport()
	var s: RogueScreen = (load("res://ui/game/rogue/rogue_screen.tscn") as PackedScene).instantiate()
	vp.add_child(s)
	await tree.process_frame
	var sent: Array = []
	s.apply_state({ "phase": "PICK", "round": 3, "attrs": { "str": 20 }, "cards": [
		{ "idx": 0, "kind": "ATTR", "title": "屬性 +4", "points": 4, "rarity": "FINE", "lines": [] },
		{ "idx": 1, "kind": "ART", "title": "華山劍法 25 級", "rarity": "COMMON", "lines": [], "art": { "id": "hs_jianfa", "level": 25 } },
		{ "idx": 2, "kind": "ATTR", "title": "屬性 +10", "points": 10, "rarity": "DIVINE", "lines": [] }] })
	await tree.process_frame
	await tree.process_frame
	assert_false(s.popup_backdrop.visible, "沒有浮層時沒有暗幕")
	s.select_card(0)
	s.confirm_pick()
	await tree.process_frame
	assert_true(s.attr_popup.visible, "屬性卡開分配窗")
	assert_true(s.popup_backdrop.visible, "分配窗開著 → 暗幕")
	assert_eq(s.popup_backdrop.mouse_filter, Control.MOUSE_FILTER_STOP, "暗幕擋滑鼠")
	var full := Rect2(Vector2.ZERO, Vector2(VIEW))
	assert_true(s.popup_backdrop.get_global_rect().encloses(s.cards_row.get_global_rect()), "暗幕蓋住整列卡片")
	assert_true(full.encloses(s.popup_backdrop.get_global_rect()) and s.popup_backdrop.get_global_rect().size.x >= VIEW.x - 1, "暗幕滿版")
	# 點卡片的路徑（暗幕之外的保險）：開著時不能換卡、也不能再確認
	s.select_card(2)
	assert_eq(s.selected_idx, 0, "分配窗開著時不能換卡")
	(s.cards[2] as RogueCard).press()
	assert_eq(s.selected_idx, 0)
	assert_eq(s.attr_idx, 0, "記住開窗的那一張")
	s.attr_popup.visible = false
	await tree.process_frame
	assert_false(s.popup_backdrop.visible, "關窗 → 暗幕收起")
	s.ask_abandon()
	await tree.process_frame
	assert_true(s.confirm_panel.visible and s.popup_backdrop.visible, "放棄確認也有暗幕")
	s.handle_key(KEY_ESCAPE)
	await tree.process_frame
	assert_false(s.popup_backdrop.visible)
