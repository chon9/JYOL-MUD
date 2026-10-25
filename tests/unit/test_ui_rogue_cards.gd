extends "res://tests/test_case.gd"
## ROGUE_PLAN §5.3、§9.1（WP-UI）：三張卡依種類用對的框、稀有度印與顏色、精進印、隊友立繪、滑過金描邊；
## 鍵盤 1／2／3＋Enter、點兩下送出；屬性卡的分配窗必須用完點數才送 rogue_pick（含 alloc）。

var _nodes: Array = []
var _old_root := ""
var _dir := ""
var sent: Array = []

func before_each() -> void:
	UiSettings.reset_for_tests(true)
	var smn: Node = tree.root.get_node("SaveManager")
	_old_root = smn.root_dir
	_dir = temp_dir("ui_rogue_cards")
	smn.root_dir = _dir
	sent = []

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame
	tree.root.get_node("SaveManager").root_dir = _old_root
	remove_dir_recursive(_dir)

static func card(idx: int, kind: String, rarity: String, extra: Dictionary = {}) -> Dictionary:
	var c := { "idx": idx, "id": "rg_c_test_%d" % idx, "kind": kind, "rarity": rarity, "title": "卡%d" % idx,
		"sub": "說明%d" % idx, "lines": ["第一行", "第二行"], "upgrade": false }
	for k in extra:
		c[k] = extra[k]
	return c

static func pick_state(cards: Array, extra: Dictionary = {}) -> Dictionary:
	var st := { "run_id": "rr_1", "seed": 7, "phase": "PICK", "round": 2, "wins": 1, "foes_beaten": 1, "bosses_beaten": 0,
		"next_round_is_boss": false, "extra_picks": 0, "min_rarity": "", "cards": cards,
		"attrs": { "str": 20, "guts": 18, "wit": 17, "luck": 16, "cal": 15, "agi": 19, "con": 44 }, "attr_cap": 45,
		"allies": [], "arts": [], "gear": {}, "weapons": [], "best_card": {}, "profile": { "points_total": 0, "cap": 60, "runs": 0, "best_wins": 0 } }
	for k in extra:
		st[k] = extra[k]
	return st

static func three_cards() -> Array:
	return [
		card(0, "ART", "FINE", { "upgrade": true, "art": { "id": "hs_jianfa", "level": 40, "category": "SWORD" } }),
		card(1, "WEAPON", "RARE", { "item": { "id": "w_qingfeng", "slot": "WEAPON", "weapon_type": "SWORD", "atk": 15, "def": 0 } }),
		card(2, "ATTR", "COMMON", { "points": 3 }),
	]

func _screen() -> RogueScreen:
	var s: RogueScreen = (load("res://ui/game/rogue/rogue_screen.tscn") as PackedScene).instantiate()
	tree.root.add_child(s)
	_nodes.append(s)
	s.gate.set_sender(func(kind: String, args: Dictionary) -> int:
		sent.append([kind, args])
		return 9000 + sent.size())
	return s

func _ok_all(s: RogueScreen) -> void:
	for i in sent.size():
		s.gate.resolve(9001 + i, true, "")

func test_frame_kind_per_card_kind() -> void:
	assert_eq(RogueCard.frame_kind_for("ART"), UiFrame.Kind.JADE)
	assert_eq(RogueCard.frame_kind_for("WEAPON"), UiFrame.Kind.SCROLL)
	assert_eq(RogueCard.frame_kind_for("ATTR"), UiFrame.Kind.AMBER)
	assert_eq(RogueCard.frame_kind_for("ALLY"), UiFrame.Kind.INK)
	for k in ["ART", "WEAPON", "ATTR", "ALLY"]:
		var c := RogueCard.new(card(0, k, "COMMON"))
		_nodes.append(c)
		assert_true(c.frame.get_theme_stylebox("panel") == UiFrame.style(RogueCard.frame_kind_for(k)), "frame style " + k)
		assert_eq(c.kind_glyph.text, str(UiKeys.ROGUE_KIND_GLYPH[k]), "glyph " + k)
	var w := RogueCard.new(card(1, "WEAPON", "COMMON"))
	_nodes.append(w)
	assert_true(w.frame.theme == UiTheme.paper(), "scroll card uses ink-on-paper theme")
	assert_eq(UiKeys.ROGUE_KIND_GLYPH, { "ART": "武", "WEAPON": "兵", "ARMOR": "甲", "ATTR": "屬", "ALLY": "友" })

func test_rarity_seal_and_color() -> void:
	var names := { "COMMON": "凡", "FINE": "良", "RARE": "稀", "TREASURE": "珍", "DIVINE": "神" }
	for r in names:
		var c := RogueCard.new(card(0, "ART", r))
		_nodes.append(c)
		assert_eq(c.rarity_seal.text, names[r], "seal " + r)
		assert_eq(RogueCard.rarity_color(r), LootUi.rarity_color(r), "color " + r)
		var sb := (c.rarity_seal.get_parent() as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
		assert_true(sb != null and sb.bg_color.is_equal_approx(LootUi.rarity_color(r).darkened(0.15)), "seal color " + r)
	var bad := RogueCard.new(card(0, "ART", "WHATEVER"))
	_nodes.append(bad)
	assert_eq(bad.rarity_seal.text, "凡", "unknown rarity → 凡")

func test_texts_from_host_and_upgrade_seal() -> void:
	var a := RogueCard.new(three_cards()[0])
	_nodes.append(a)
	assert_eq(a.title_label.text, "卡0")
	assert_eq(a.sub_label.text, "說明0")
	assert_eq(a.lines_box.get_child_count(), 2)
	assert_eq((a.lines_box.get_child(0) as Label).text, "第一行")
	assert_true(a.upgrade_seal.visible, "upgrade seal visible")
	assert_eq(a.upgrade_seal.text, "精進")
	var b := RogueCard.new(card(0, "ART", "FINE"))
	_nodes.append(b)
	assert_false(b.upgrade_seal.visible, "new art: no seal")
	var w := RogueCard.new(card(0, "WEAPON", "FINE", { "upgrade": true }))
	_nodes.append(w)
	assert_false(w.upgrade_seal.visible, "upgrade only for ART")

func test_ally_portrait_or_silhouette() -> void:
	var a := RogueCard.new(card(0, "ALLY", "RARE", { "ally": { "name": "周芷若", "ref": "n_em_zhouzhiruo", "monster": "m_em_zhouzhiruo" } }))
	_nodes.append(a)
	assert_true(a.portrait != null, "portrait")
	assert_true(a.portrait is TextureRect or a.portrait is RogueCard.Silhouette, "image or silhouette")
	var none := RogueCard.new(card(0, "ALLY", "COMMON", { "ally": { "name": "無名", "ref": "n_no_such_npc_xyz", "monster": "" } }))
	_nodes.append(none)
	assert_true(none.portrait is RogueCard.Silhouette, "no art → silhouette")
	var art := RogueCard.new(card(0, "ART", "COMMON"))
	_nodes.append(art)
	assert_true(art.portrait == null, "only ALLY has a portrait")

func test_hover_and_select_edge() -> void:
	var c := RogueCard.new(card(0, "ART", "COMMON"))
	tree.root.add_child(c)
	_nodes.append(c)
	assert_false(c.edge_visible(), "no edge")
	c.notification(Control.NOTIFICATION_MOUSE_ENTER)
	assert_true(c.edge_visible(), "hover edge")
	c.notification(Control.NOTIFICATION_MOUSE_EXIT)
	assert_false(c.edge_visible(), "edge gone")
	var clicks: Array = []
	var acts: Array = []
	c.clicked.connect(func(i: int): clicks.append(i))
	c.activated.connect(func(i: int): acts.append(i))
	c.press()
	assert_eq(clicks, [0])
	c.set_selected(true)
	assert_true(c.edge_visible(), "selected edge")
	assert_eq(c.frame.offset_top, RogueCard.SINK, "sinks")
	c.press()
	assert_eq(acts, [0], "second click activates")

func test_three_cards_layout_and_keyboard() -> void:
	var s := _screen()
	await tree.process_frame
	s.apply_state(pick_state(three_cards()))
	await tree.process_frame
	assert_eq(s.view, "PICK")
	assert_true(s.pick_box.visible and s.hud.visible, "pick + hud")
	assert_eq(s.cards.size(), 3)
	assert_eq(s.cards_row.get_theme_constant("separation"), 24, "gap 24")
	assert_eq((s.cards[0] as RogueCard).custom_minimum_size, Vector2(260, 340))
	assert_true(s.pick_button.disabled, "nothing selected")
	assert_true(s.handle_key(KEY_2), "key 2")
	assert_eq(s.selected_idx, 1)
	assert_true((s.cards[1] as RogueCard).selected and not (s.cards[0] as RogueCard).selected)
	assert_true(s.handle_key(KEY_ESCAPE), "esc")
	assert_eq(s.selected_idx, -1, "deselected")
	assert_true(s.handle_key(KEY_KP_3), "keypad 3")
	assert_eq(s.selected_idx, 2, "keypad numbers pick cards too")
	s.handle_key(KEY_2)
	assert_true(s.handle_key(KEY_ENTER), "enter")
	assert_eq(sent.size(), 1)
	assert_eq(sent[0], ["rogue_pick", { "idx": 1 }])

## 審查：武功卡的滑鼠提示要有這門武功的完整說明（SkillEffects，同武功窗）
func test_art_card_tooltip_has_skill_effects() -> void:
	var c := RogueCard.new(three_cards()[0])
	_nodes.append(c)
	var fx := SkillEffects.lines("hs_jianfa", UiClient.tables())
	assert_true(not fx.is_empty(), "SkillEffects has hs_jianfa")
	assert_true(c.tooltip_text.contains(fx[0]), c.tooltip_text)
	assert_true(c.tooltip_text.contains("第一行"), "card lines in the tooltip")
	var w := RogueCard.new(three_cards()[1])
	_nodes.append(w)
	assert_false(w.tooltip_text.contains("【武功說明】"), "weapon cards: no art text")

func test_click_twice_sends_pick() -> void:
	var s := _screen()
	await tree.process_frame
	s.apply_state(pick_state(three_cards()))
	(s.cards[0] as RogueCard).press()
	assert_eq(s.selected_idx, 0)
	assert_eq(sent.size(), 0, "first click only selects")
	(s.cards[0] as RogueCard).press()
	assert_eq(sent, [["rogue_pick", { "idx": 0 }]])

func test_attr_card_needs_full_allocation() -> void:
	var s := _screen()
	await tree.process_frame
	s.apply_state(pick_state(three_cards()))
	s.handle_key(KEY_3)
	s.handle_key(KEY_ENTER)
	assert_eq(sent.size(), 0, "ATTR opens the allocation popup first")
	var pop: RogueAllocPanel = s.attr_popup
	assert_true(pop.visible, "popup")
	assert_eq(pop.points, 3)
	assert_eq(pop.remaining(), 3)
	assert_true(pop.confirm_button.disabled, "must use all points")
	assert_false(pop.identity_box.visible, "no name fields")
	assert_true(pop.cancel_button.visible and not pop.reroll_button.visible)
	assert_true(pop.add("str", 1))
	assert_true(pop.add("str", 1))
	# 根骨 44：只能再加 1（上限 45）
	assert_true(pop.add("con", 1))
	assert_false(pop.add("con", 1), "cap 45 / no points left")
	assert_eq(pop.remaining(), 0)
	assert_false(pop.confirm_button.disabled)
	pop.confirm_button.pressed.emit()
	assert_eq(sent.size(), 1)
	assert_eq(sent[0][0], "rogue_pick")
	assert_eq(sent[0][1]["idx"], 2)
	var al: Dictionary = sent[0][1]["alloc"]
	assert_eq(al["str"], 2)
	assert_eq(al["con"], 1)
	var sum := 0
	for k in al:
		sum += int(al[k])
	assert_eq(sum, 3, "exactly the card's points")
	assert_false(pop.visible, "popup closed")

func test_attr_cap_blocks_plus() -> void:
	var p := RogueAllocPanel.new()
	_nodes.append(p)
	p.setup({ "str": 45, "con": 10 }, 2, 45, false)
	assert_true(p.plus_buttons["str"].disabled, "at cap")
	assert_false(p.add("str", 1))
	assert_true(p.minus_buttons["con"].disabled, "nothing to take back")
	p.add("con", 1)
	assert_false(p.minus_buttons["con"].disabled)
	assert_true(p.add("con", -1))
	assert_eq(p.remaining(), 2)

func test_esc_closes_popup() -> void:
	var s := _screen()
	await tree.process_frame
	s.apply_state(pick_state(three_cards()))
	s.select_card(2)
	s.confirm_pick()
	assert_true(s.attr_popup.visible)
	assert_true(s.handle_key(KEY_ESCAPE))
	assert_false(s.attr_popup.visible, "esc closes")
	assert_eq(s.selected_idx, 2, "selection kept")

func test_boss_reward_title_and_new_cards_reset_selection() -> void:
	var s := _screen()
	await tree.process_frame
	s.apply_state(pick_state(three_cards()))
	s.select_card(1)
	var rare := [card(0, "ART", "RARE"), card(1, "WEAPON", "TREASURE"), card(2, "ALLY", "DIVINE", { "ally": { "name": "喬峰", "ref": "n_xx_qiaofeng", "monster": "m_rg_qiaofeng" } })]
	s.apply_state(pick_state(rare, { "round": 6, "extra_picks": 1, "min_rarity": "RARE" }))
	assert_eq(s.pick_title.text, "名人敗退，再選一張")
	assert_eq(s.selected_idx, -1, "new cards → no selection")
	assert_eq((s.cards[2] as RogueCard).frame_kind, UiFrame.Kind.INK)
	s.apply_state(pick_state(three_cards(), { "round": 6 }))
	assert_eq(s.pick_title.text, "第 6 回合・選一張")
