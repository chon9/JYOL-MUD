extends "res://tests/test_case.gd"
## WP-UI：仿原作客戶端的介面元件（docs/AUTHENTIC_UI_SPEC.md）：程式產生的九宮格框、色票與能量條、設定檔、
## 程式繪製按鈕、燈籠選單、底部 HUD（圖示、能量條、熱鍵列、曆法牌）、指令窗、戰鬥圓盤、NPC 編號選項、商店購物車、
## 主畫面快捷鍵（Ctrl+1–5 原作順序、Ctrl+6 任務、F1–F8 熱鍵、Esc 收合燈籠）。

var _nodes: Array = []

func before_each() -> void:
	UiSettings.reset_for_tests(true)

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame

func _add(n: Node) -> Node:
	tree.root.add_child(n)
	_nodes.append(n)
	return n

func _key(code: int, ctrl := false, alt := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	k.ctrl_pressed = ctrl
	k.alt_pressed = alt
	return k

# ---------------------------------------------------------------- 框、色票、設定

func test_frames_are_generated_for_every_kind() -> void:
	for kind in UiFrame.Kind.values():
		var sb := UiFrame.style(kind)
		assert_true(sb != null, "style %d" % kind)
		assert_true(UiFrame.style(kind) == sb, "cached %d" % kind)
	var jade := UiFrame.texture(UiFrame.Kind.JADE)
	assert_eq(jade.get_size(), Vector2(96, 96))
	var img := jade.get_image()
	assert_eq(img.get_pixel(48, 0), UiFrame.OUTLINE, "outer outline")
	assert_eq(img.get_pixel(5, 5), UiTheme.JY_WOOD_DARK, "corner stud core")
	# 編繩（第 9–14 px）：中段是繩紋三色之一
	var rope := img.get_pixel(48, 11)
	assert_true(rope.is_equal_approx(UiTheme.JY_ROPE) or rope.is_equal_approx(UiTheme.JY_ROPE_DARK) or rope.is_equal_approx(UiTheme.JY_GOLD), "rope band")
	# 固定 seed：重新產生一模一樣
	UiFrame.clear_cache()
	assert_eq(UiFrame.texture(UiFrame.Kind.JADE).get_image().get_pixel(40, 3), img.get_pixel(40, 3), "deterministic noise")
	var sb2 := UiFrame.style(UiFrame.Kind.JADE) as StyleBoxTexture
	assert_eq(sb2.texture_margin_left, 24.0)
	assert_eq(sb2.content_margin_left, 26.0)
	assert_eq(sb2.axis_stretch_horizontal, StyleBoxTexture.AXIS_STRETCH_MODE_TILE, "rope edges tile, not stretch")

func test_palette_and_vital_bars() -> void:
	# §7：精綠、氣紅、神黃、內力藍
	assert_true(UiTheme.JING_COLOR.g > UiTheme.JING_COLOR.r, "精 green")
	assert_true(UiTheme.QI_COLOR.r > UiTheme.QI_COLOR.g, "氣 red")
	assert_true(UiTheme.SHEN_COLOR.r > UiTheme.SHEN_COLOR.b and UiTheme.SHEN_COLOR.g > UiTheme.SHEN_COLOR.b, "神 yellow")
	assert_true(UiTheme.NEILI_COLOR.b > UiTheme.NEILI_COLOR.r, "內力 blue")
	assert_eq(UiTheme.FONT_SIZE, 16)
	var b := ProgressBar.new()
	_add(b)
	UiTheme.vital_bar(b, Color.RED, Color.WHITE)
	assert_true(b.get_theme_stylebox("fill") is StyleBoxTexture, "gradient fill")
	var t := UiTheme.build()
	assert_eq(t.get_color("font_color", "Label"), UiTheme.JY_TEXT, "dark theme: light text")
	assert_eq(t.get_color("font_color", "TooltipLabel"), Color.BLACK, "yellow tooltip, black text")
	assert_eq(UiTheme.paper().get_color("font_color", "Label"), UiTheme.INK, "scroll theme: ink text")
	assert_true(t.is_type_variation("MutedLabel", "Label"))

func test_settings_dotted_keys_in_memory() -> void:
	assert_false(UiSettings.get_bool("ui.atb_list"), "ATB list default off")
	assert_true(UiSettings.get_bool("ui.damage_text"))
	UiSettings.set_value("hotbar.ch_1", { "cmd": [["look"]] })
	assert_eq(UiSettings.get_value("hotbar.ch_1", {})["cmd"][0][0], "look")
	UiSettings.set_value("ui.atb_list", true)
	assert_true(UiSettings.get_bool("ui.atb_list"))
	assert_eq(UiSettings.get_value("nope.nothing", 7), 7)

func test_text_renderer_bright_channels_and_important() -> void:
	assert_eq(TextRenderer.CHANNEL_COLORS["CHAT_WORLD"], "#40e0f0")
	assert_eq(TextRenderer.CHANNEL_COLORS["SYSTEM"], "#ffa040")
	var tpl := { "x": { "self": "重要" } }
	var bb := TextRenderer.render({ "ch": "SYSTEM", "key": "x", "p": { "important": true } }, -1, tpl)
	assert_true(bb.begins_with("[bgcolor=#c00000][color=#ffffff]"), bb)

# ---------------------------------------------------------------- 按鈕、燈籠、HUD

func test_jy_button_faces_and_sizes() -> void:
	var l := JyButton.new(JyButton.Style.LANTERN, "武功(Ctrl+1)")
	_add(l)
	assert_eq(l.face(), "武功")
	assert_eq(l.custom_minimum_size, Vector2(52, 60))
	assert_true(l.clip_text, "long accessible text does not widen the button")
	var d := JyButton.new(JyButton.Style.DISC, "移")
	_add(d)
	assert_eq(d.face(), "移")
	assert_eq(d.custom_minimum_size, Vector2(40, 40))
	var c := JyButton.new(JyButton.Style.CLOSE, "關閉(Esc)")
	_add(c)
	assert_eq(c.face(), "✕")
	assert_eq(c.tooltip_text, "關閉(Esc)")
	await tree.process_frame

func test_lantern_menu_order_and_collapse() -> void:
	var m := LanternMenu.new()
	_add(m)
	await tree.process_frame
	var texts: Array = []
	for b in m.lantern_box.get_children():
		texts.append((b as Button).text)
	assert_eq(texts, ["武功(Ctrl+1)", "屬性(Ctrl+2)", "裝備(Ctrl+3)", "指令(Ctrl+4)", "系統(Ctrl+5)"], "original order")
	var got: Array = []
	m.panel_requested.connect(func(pid): got.append(pid))
	(m.lanterns["inventory"] as Button).pressed.emit()
	assert_eq(got, ["inventory"])
	m.knot.pressed.emit()
	assert_true(m.collapsed and not m.lantern_box.visible, "中國結 collapses")
	assert_true(UiSettings.get_bool("ui.lanterns_collapsed"))
	m.knot.pressed.emit()
	assert_true(m.lantern_box.visible)

func test_status_bar_icons_and_bars() -> void:
	var s := StatusBar.new()
	_add(s)
	await tree.process_frame
	var sheet := { "vitals": { "jing": 80, "jing_max": 92, "qi": 10, "qi_max": 180, "shen": 88, "shen_max": 88,
		"neili": 25, "neili_max": 50, "food": 15, "water": 40 }, "money": 180, "combat_xp": 250, "learn_points": 40, "morality": 3 }
	s.apply_sheet(sheet)
	assert_eq((s.bar_texts["qi"] as Label).text, "10/180")
	assert_eq(s.icons.size(), 7, "食 水 錢 狀 善 學 戰")
	assert_true(s.icon_text("money").contains("180"))
	assert_true(s.icon_text("combat").contains("250"))
	assert_eq((s.icons["food"] as JyButton).tint, UiTheme.LEVEL_LOW, "food < 20% red")
	assert_eq((s.icons["water"] as JyButton).tint, UiTheme.LEVEL_WARN, "water 20–50% orange")
	assert_eq(StatusBar.level_tint(0.9), Color(0, 0, 0, 0))
	s.apply_battle_unit({ "qi": 5, "qi_max": 180, "neili": 1, "neili_max": 50, "jing": 1, "jing_max": 92 })
	assert_eq((s.bar_texts["qi"] as Label).text, "5/180", "battle snapshot updates bars live")

func test_hud_calendar_and_location() -> void:
	assert_eq(BottomHud.calendar_text({ "text": "戌時七刻", "month": 8, "mday": 27 }), "八月廿七 戌時七刻")
	assert_eq(BottomHud.calendar_text({ "text": "辰時三刻", "day": 3 }), "第 3 日 辰時三刻")
	assert_eq(BottomHud.cn_day(1), "初一")
	assert_eq(BottomHud.cn_day(15), "十五")
	assert_eq(BottomHud.cn_num(12), "十二")
	assert_eq(BottomHud.location_text({ "room_name": "市街" }), "市街")
	assert_eq(BottomHud.location_text({ "room_name": "市街", "coords": [7296, 2966] }), "市街 7296,2966")

func test_hotbar_defaults_drop_rules_and_persistence() -> void:
	var h := Hotbar.new()
	_add(h)
	await tree.process_frame
	h.apply_sheet({ "char_id": "ch_a", "vitals": { "neili": 30, "neili_max": 50 },
		"inventory": [{ "uid": "it_1", "id": "c_jingyao", "name": "精藥水", "n": 3, "usable": true }] })
	assert_eq(h.payload_at(Hotbar.ROW_CMD, 0), "cmd:meditate", "F1 修煉內力")
	assert_eq(h.payload_at(Hotbar.ROW_CMD, 2), "cmd:look", "F3 查看")
	assert_true(Hotbar.accepts(Hotbar.ROW_CMD, "cmd:look"))
	assert_false(Hotbar.accepts(Hotbar.ROW_CMD, "item:c_jingyao"), "items only on the Alt row")
	assert_true(Hotbar.accepts(Hotbar.ROW_ITEM, "item:c_jingyao"))
	assert_false(Hotbar.accepts(Hotbar.ROW_CMD, "cmd:no_such"))
	h.set_payload(Hotbar.ROW_ITEM, 0, "item:c_jingyao")
	var it_slot: HotbarSlot = h.slots[Hotbar.ROW_ITEM][0]
	assert_eq(it_slot.count, 3)
	assert_eq(it_slot.face(), "精藥")
	assert_true(it_slot._can_drop_data(Vector2.ZERO, { "jy_hotbar": "item:x" }))
	var fired: Array = []
	h.activated.connect(func(p, _b): fired.append(p))
	h._update_states()
	assert_true(h.trigger(Hotbar.ROW_ITEM, 0), "Alt+1")
	assert_eq(fired, ["item:c_jingyao"])
	# 存在 settings 的 hotbar.<char_id>，換角色再換回來還在
	h.load_for("ch_b")
	assert_eq(h.payload_at(Hotbar.ROW_ITEM, 0), "")
	h.load_for("ch_a")
	assert_eq(h.payload_at(Hotbar.ROW_ITEM, 0), "item:c_jingyao", "per-character layout restored")
	# 修煉內力冷卻：鈕面畫「修煉（N 秒）」（兩行）
	h.apply_sheet({ "char_id": "ch_a", "vitals": { "neili": 30, "neili_max": 50 }, "cooldowns": { "meditate": 9.0 } })
	h._update_states()
	var med: HotbarSlot = h.slots[Hotbar.ROW_CMD][0]
	assert_true(med.disabled and med.visible_text().begins_with("修煉（") and med.visible_text().ends_with(" 秒）") and med.text == med.visible_text(), med.visible_text())
	# 內力不足：施展內功灰色
	h.apply_sheet({ "char_id": "ch_a", "vitals": { "neili": 5, "neili_max": 50 } })
	h._update_states()
	assert_true((h.slots[Hotbar.ROW_CMD][1] as HotbarSlot).disabled, "exert needs 20 neili")

func test_command_panel_tabs_and_drag_payloads() -> void:
	var p := CommandPanel.new()
	_add(p)
	await tree.process_frame
	assert_eq(p.tab_bar.tab_count, 6)
	assert_eq(p.tab_bar.get_tab_title(0), "溝通")
	p.set_tab("MARTIAL")
	assert_true(p.buttons.has("meditate") and p.buttons.has("exert_qi"))
	assert_eq((p.buttons["meditate"] as JyButton).drag_payload, "cmd:meditate", "drag to F1–F8")
	p.set_tab("COMM")
	assert_true(p.buttons.is_empty(), "溝通 not open yet")
	p.set_tab("MISC")
	var got: Array = []
	p.command_invoked.connect(func(id, _b): got.append(id))
	(p.buttons["quests"] as Button).pressed.emit()
	assert_eq(got, ["quests"])
	p.set_tab("ACTION")
	p.apply_sheet({ "skills": [{ "id": "life_fishing", "kind": "LIFE", "level": 1 }] })
	p.apply_view({ "features": ["WATER"] })
	assert_false((p.buttons["work:life_fishing"] as Button).disabled, "fishing where there is water")
	assert_true((p.buttons["work:life_woodcut"] as Button).disabled, "no wood here")

func test_command_bar_two_rows_and_locked_discs() -> void:
	var cb := CommandBar.new()
	_add(cb)
	await tree.process_frame
	assert_eq(cb.discs.size(), 17, "9 + 8 discs")
	var first: JyButton = cb.discs["防"]
	var second: JyButton = cb.discs["移"]
	assert_true(second.position.y > first.position.y and absf(second.position.x - first.position.x - 22.0) < 0.5, "second row shifted half a disc")
	for g in UiKeys.CMD_LOCKED_LABELS:
		assert_true((cb.discs[g] as Button).disabled, "%s locked" % g)
		assert_true((cb.discs[g] as Button).tooltip_text.contains("尚未開放"))
	var got: Array = []
	cb.panel_requested.connect(func(pid): got.append(pid))
	(cb.discs["屬"] as Button).pressed.emit()
	(cb.discs["系"] as Button).pressed.emit()
	assert_eq(got, ["attributes", "system"])
	assert_eq(cb.buttons.size(), 13, "移攻武防休裝逃 + M3a 毒醫暗陣內穴")
	assert_eq(UiKeys.CMD_LOCKED_LABELS, ["輕", "特"], "M3a：只剩輕、特鎖住")

# ---------------------------------------------------------------- 對話框

func test_npc_dialog_numbered_choices_and_digit_keys() -> void:
	var d := NpcDialog.new()
	_add(d)
	await tree.process_frame
	var sent: Array = []
	d._gate().set_sender(func(kind, args):
		sent.append([kind, args])
		return -1)
	d.open_menu({ "npc": "n_x", "npc_name": "小蘭", "services": ["SHOP", "TEACH", "QUEST"], "closed": false, "quests": [] }, "【場景】小蘭：少俠好。")
	assert_eq(d.name_label.text, "小蘭", "name plate")
	assert_eq(d.talk_label.text, "小蘭：少俠好。", "channel tag stripped")
	assert_eq(d.choice_order, ["SHOP", "TEACH", "QUEST"])
	assert_eq((d.service_buttons["SHOP"] as Button).text, "交易")
	var nums: Array = []
	for row in d.services_box.get_children():
		nums.append((row.get_child(0) as Label).text)
	assert_eq(nums, ["1.", "2.", "3."])
	d._unhandled_key_input(_key(KEY_2))
	assert_eq(sent.size(), 1)
	assert_eq(sent[0][0], "learn_list", "2 = 請教")
	d.open_menu({ "npc": "n_x", "npc_name": "小蘭", "services": ["SHOP"], "closed": true }, "")
	assert_true((d.service_buttons["SHOP"] as Button).disabled, "打烊了 → gray choice")
	assert_true(d.closed_label.visible)

func test_shop_cart_totals_and_checkout() -> void:
	var s := ShopDialog.new()
	_add(s)
	await tree.process_frame
	var sent: Array = []
	s._gate().set_sender(func(kind, args):
		sent.append([kind, args])
		return -1)
	s.open_shop({ "npc": "n_x", "npc_name": "店小二", "items": [{ "id": "c_mantou", "name": "饅頭", "price": 5 }],
		"sellable": [{ "uid": "it_1", "id": "w_mudao", "name": "木刀", "n": 1, "price": 3, "equipped": true }] })
	assert_eq(s.title_label.text, "店小二的鋪子")
	s.add_to_cart("c_mantou", 1)
	s.add_to_cart("c_mantou", 10)
	assert_eq(int(s.cart[0]["n"]), 11)
	assert_eq(s.cart_total(), 55)
	assert_eq(s.total_label.text, "55")
	s.add_to_cart("c_mantou", -1)
	assert_eq(s.cart_total(), 50)
	s._on_ok()
	var buys := sent.filter(func(x): return x[0] == "buy")
	assert_eq(buys.size(), 1)
	assert_eq(buys[0], ["buy", { "npc": "n_x", "n": 10, "item": "c_mantou" }])
	assert_true(s.cart.is_empty())
	# 賣：裝備中的東西要按兩次 ✔
	s.set_mode(ShopDialog.MODE_SELL)
	s.add_to_cart("it_1", 1)
	assert_true(bool(s.cart[0]["equipped"]))
	s._pending = 0
	s._on_ok()
	assert_eq(sent.filter(func(x): return x[0] == "sell").size(), 0, "first ✔ only warns")
	assert_true(s.status_label.text.contains(ShopDialog.CONFIRM_TEXT))

# ---------------------------------------------------------------- 主畫面

func test_main_screen_lanterns_hotkeys_and_hotbar() -> void:
	var main = _add((load("res://ui/game/main/main_screen.tscn") as PackedScene).instantiate())
	await tree.process_frame
	var sheet: Dictionary = (load("res://tests/unit/test_ui_scenes.gd") as GDScript).fake_sheet()
	main.apply_sheet(sheet)
	main.apply_view((load("res://tests/unit/test_ui_scenes.gd") as GDScript).fake_view())
	await tree.process_frame
	# 版面：HUD 在下緣 168 高、燈籠在右緣、浮層在左上
	assert_eq(main.hud.size.y, BottomHud.HEIGHT)
	assert_true(main.lanterns.position.x > main.size.x - 80.0, "lanterns on the right edge")
	assert_eq(main.message_log.position, MainScreenOverlay.POS)
	# Ctrl+1–5 原作順序
	var order := ["skills", "attributes", "inventory", "commands", "system"]
	for i in 5:
		main._shortcut_input(_key(KEY_1 + i, true))
		assert_eq(main.current_panel, order[i], "Ctrl+%d" % (i + 1))
	main._shortcut_input(_key(KEY_6, true))
	assert_eq(main.current_panel, "quests", "Ctrl+6 任務")
	main._shortcut_input(_key(KEY_M, true))
	assert_eq(main.current_panel, "map", "Ctrl+M 地圖")
	assert_eq(main.panel_title.text, "地圖")
	# Esc：關視窗 → 再按收合燈籠
	main._shortcut_input(_key(KEY_ESCAPE))
	assert_false(main.panel_frame.visible)
	main._shortcut_input(_key(KEY_ESCAPE))
	assert_true(main.lanterns.collapsed, "Esc last collapses the lanterns")
	main._shortcut_input(_key(KEY_ESCAPE))
	assert_false(main.lanterns.collapsed)
	# F1 = 修煉內力（熱鍵列）
	var sent: Array = []
	main.gate.set_sender(func(kind, args):
		sent.append([kind, args])
		return -1)
	main.hotbar._update_states()
	main._shortcut_input(_key(KEY_F1))
	assert_eq(sent.size(), 1)
	assert_eq(sent[0][0], "meditate")
	# 指令窗按「施展內功回氣」
	main.run_command("cmd:exert_qi")
	assert_eq(sent[1], ["exert", { "stat": "qi" }])
	# 物品熱鍵：可用的物品 → use_item
	main.run_command("item:c_jingyao")
	assert_eq(sent[2], ["use_item", { "item_uid": "it_0003" }])
	# 戰鬥：燈籠隱藏、圓盤「屬」開唯讀屬性窗、Ctrl+數字無效
	main.open_battle((load("res://tests/unit/test_ui_scenes.gd") as GDScript)._battle_state())
	await tree.process_frame
	assert_false(main.lanterns.visible)
	assert_true(main.hud.is_visible_in_tree(), "HUD stays visible in battle")
	main._shortcut_input(_key(KEY_2, true))
	assert_false(main.panel_frame.visible, "no Ctrl+N in battle")
	main.battle.panel_requested.emit("attributes")
	assert_true(main.panel_frame.visible and main.current_panel == "attributes", "屬 disc opens attributes")
	assert_eq(main.get_child(main.get_child_count() - 1), main.panel_layer, "panel above the battle")

## 主畫面浮層位置（§2）
class MainScreenOverlay:
	const POS := Vector2(8, 8)
