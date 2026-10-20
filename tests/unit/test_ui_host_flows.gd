extends "res://tests/unit/test_world_fixture.gd"
## 介面 × 真主機：把真正的主機事件餵進真正的主畫面（UI 只送 intent、只看事件），抓「主機正確、畫面壞掉」的協定落差。
## UI 的 IntentGate 改成直接呼叫 ws.handle_intent（結果同步回來，事件要等 ws.flush()，與實際順序相同：
## intent_result 先到、事件後到）。

const MAIN_SCENE := "res://ui/game/main/main_screen.tscn"

var main: Node = null

func before_each() -> void:
	world_name = "w_uiflow"
	UiSettings.reset_for_tests(true)   # 介面設定只放記憶體，不碰使用者的 settings.json
	super.before_each()

func after_each() -> void:
	if main != null and is_instance_valid(main):
		main.queue_free()
		await tree.process_frame
	main = null
	super.after_each()

## 主畫面：gate 直接送到主機（不 flush，事件留到 deliver() 才送，模擬真實順序）
func open_main() -> void:
	main = (load(MAIN_SCENE) as PackedScene).instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	main.gate.set_sender(func(kind: String, args: Dictionary) -> int:
		seq += 1
		ws.handle_intent(1, seq, kind, args)
		return seq)
	deliver()

func deliver() -> void:
	ws.flush()

func press(b: Button) -> void:
	assert_true(b != null and not b.disabled, "button pressable: %s" % (b.text if b else "null"))
	if b != null and not b.disabled:
		b.pressed.emit()

func button_in(root: Node, text: String) -> Button:
	for c in _all(root):
		if c is Button and (c as Button).text == text and not c.is_queued_for_deletion():
			return c
	return null

func label_texts(root: Node) -> Array:
	var out: Array = []
	for c in _all(root):
		if c is Label and not c.is_queued_for_deletion():
			out.append((c as Label).text)
	return out

func _all(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c.is_queued_for_deletion():
			continue
		out.append(c)
		out.append_array(_all(c))
	return out

func quest_row_text(dlg: Node, quest_name: String) -> String:
	for t in label_texts(dlg.detail_box):
		if str(t).begins_with(quest_name + "　"):
			return t
	return ""

# ---------------------------------------------------------------- 任務對話框

func test_quest_dialog_follows_host_through_accept_and_turn_in() -> void:
	if not game_ok():
		return
	make_char()
	goto("xx_station")
	await open_main()
	var dlg: NpcDialog = main.npc_dialog
	ok("talk", { "npc": "n_xx_station" })
	assert_true(dlg.visible, "talk opens the dialog")
	press(dlg.service_buttons.get("QUEST"))
	assert_true(quest_row_text(dlg, "驛站送信").contains("可接"), str(label_texts(dlg.detail_box)))
	# 接受：結果先到（本地標成進行中），主機重送的選單後到
	press(button_in(dlg.detail_box, "接受"))
	await tree.process_frame
	deliver()
	await tree.process_frame
	assert_true(dlg.visible, "still open")
	assert_true(quest_row_text(dlg, "驛站送信").contains("進行中"), str(label_texts(dlg.detail_box)))
	assert_eq(button_in(dlg.detail_box, "交付"), null, "ACTIVE quest at the giver: no 交付 button (must go to 大理)")
	assert_eq(dlg.status_label.text, "")
	# 關掉對話框後主機再重送的選單不會把它打開
	dlg.close()
	host().npcs.refresh_menu(s(), "n_xx_station")
	deliver()
	assert_false(dlg.visible, "refresh npc_menu must not reopen a closed dialog")

	# 驛站只管送信（WORLD_2001 D5）：馬車預設關，信要自己走到大理驛站
	assert_eq(reason("travel", { "npc": "n_xx_station", "dest": "dl_station" }), "stagecoach_disabled")
	goto("dl_station")
	deliver()
	ok("talk", { "npc": "n_dl_station" })
	assert_true(dlg.visible and dlg.npc_id() == "n_dl_station")
	press(dlg.service_buttons.get("QUEST"))
	assert_true(quest_row_text(dlg, "驛站送信").contains("可交付"), str(label_texts(dlg.detail_box)))
	var money := int(ch().money)
	press(button_in(dlg.detail_box, "交付"))
	await tree.process_frame
	assert_eq(int(ch().money), money + 100, "turned in")
	# 結果先到：舊的「可交付」列已經拿掉，不會留一顆會失敗的交付鈕
	assert_eq(quest_row_text(dlg, "驛站送信"), "", "turned-in quest removed before the refresh arrives")
	deliver()
	await tree.process_frame
	assert_eq(quest_row_text(dlg, "驛站送信"), "", "host refresh: q_letter no longer listed at 大理驛站")
	assert_true(quest_row_text(dlg, "驛站送信（大理）").contains("可接"), str(label_texts(dlg.detail_box)))
	assert_eq(button_in(dlg.detail_box, "交付"), null, "no stale 交付 button")
	assert_eq(dlg.status_label.text, "", "no error shown")

## UI 稽核 round 3：任務面板要能再看到任務說明（去哪裡、打什麼），不能只在接任務時的訊息紀錄出現一次
func test_quest_panel_shows_where_to_go_from_host_sheet() -> void:
	if not game_ok():
		return
	make_char()
	goto("xx_square")
	await open_main()
	ok("quest_accept", { "npc": "n_wujieshan", "quest": "q_rabbit" })
	host().flush_session(s(), true)
	deliver()
	await tree.process_frame
	main.open_panel("quests")
	await tree.process_frame
	var texts := label_texts(main.panels["quests"])
	var desc := str(tables()["quests"]["q_rabbit"]["text"])
	assert_true(desc.contains("荒草坡"), "data names the hunting spot")
	var found := false
	for t in texts:
		if str(t).contains(desc):
			found = true
	assert_true(found, "quest panel shows the quest description: " + str(texts))
	main.close_panel()

func test_dialog_status_has_no_channel_tag() -> void:
	if not game_ok():
		return
	make_char()
	goto("xx_station")
	await open_main()
	var dlg: NpcDialog = main.npc_dialog
	ok("talk", { "npc": "n_xx_station" })
	dlg.send(UiKeys.I_QUEST_TURN_IN, { "npc": "n_xx_station", "quest": "q_letter" })
	assert_true(dlg.status_label.text != "", "error shown")
	assert_false(dlg.status_label.text.contains("【"), "inline reason without channel tag: " + dlg.status_label.text)

# ---------------------------------------------------------------- 商店

func test_shop_sell_list_marks_equipped_and_confirms() -> void:
	if not game_ok():
		return
	make_char()
	var weapon_uid := str(ch().inventory.equipped.get("WEAPON", ""))
	assert_true(weapon_uid != "", "new character starts with a weapon equipped")
	set_shichen(6)   # 午時：鋪子開著
	goto("xx_smithy")
	await open_main()
	ok("talk", { "npc": "n_xx_smith" })
	press(main.npc_dialog.service_buttons.get("SHOP"))
	deliver()
	await tree.process_frame
	var shop: ShopDialog = main.shop_dialog
	assert_true(shop.visible, "shop open")
	var sellable: Array = lastp("shop_list").get("sellable", [])
	var flagged := false
	for it in sellable:
		if str(it.get("uid", "")) == weapon_uid:
			flagged = bool(it.get("equipped", false))
	assert_true(flagged, "host marks the equipped weapon in sellable[]")
	# 購物車流程（AUTHENTIC_UI_SPEC §8.8）：「賣」分頁 → 點我的物品放進待賣 → ✔
	shop.set_mode(ShopDialog.MODE_SELL)
	var marked: JyButton = null
	for t in _all(shop.mine_grid):
		if t is JyButton and (t as JyButton).text.contains(ShopDialog.EQUIPPED_MARK):
			marked = t
	assert_true(marked != null and marked.marked, "my items mark the equipped weapon with a red frame")
	if marked == null:
		return
	press(marked)
	assert_eq(shop.cart.size(), 1, "weapon in the sell cart")
	assert_true(bool(shop.cart[0]["equipped"]), "cart entry flagged equipped")
	press(shop.btn_ok)
	assert_eq(str(ch().inventory.equipped.get("WEAPON", "")), weapon_uid, "first ✔ only asks")
	assert_true(shop.status_label.text.contains(ShopDialog.CONFIRM_TEXT), shop.status_label.text)
	press(shop.btn_ok)
	assert_eq(str(ch().inventory.equipped.get("WEAPON", "")), "", "second ✔ sells")

# ---------------------------------------------------------------- 修煉內力冷卻

func test_meditate_button_shows_cooldown() -> void:
	if not game_ok():
		return
	make_char()
	ch().skills.set_level("basic_inner", 5, tables())
	ch().vitals["neili"] = 0
	s().sheet_dirty = true
	host().flush_session(s(), true)
	ws.flush()
	await open_main()
	# 修煉內力在熱鍵列 F1（AUTHENTIC_UI_SPEC §6.3）
	var btn: HotbarSlot = main.hotbar.slots[Hotbar.ROW_CMD][0]
	assert_eq(main.hotbar.payload_at(Hotbar.ROW_CMD, 0), "cmd:meditate", "F1 = 修煉內力")
	await tree.process_frame
	assert_false(btn.disabled, "ready")
	press(btn)
	deliver()
	await tree.process_frame
	assert_true(btn.disabled, "cooling down after a successful meditate")
	assert_true(RegEx.create_from_string("^修煉（([1-9]|10) 秒）$").search(btn.visible_text()) != null and btn.text == btn.visible_text(), "countdown drawn on the face: " + btn.visible_text())
	assert_true(float(sheet().get("cooldowns", {}).get("meditate", 0.0)) > 0.0, "sheet carries the cooldown")
	ws.advance(Survival.MEDITATE_COOLDOWN_S + 0.5)
	s().sheet_dirty = true
	host().flush_session(s(), true)
	ws.flush()
	await tree.process_frame
	assert_false(btn.disabled, "ready again: " + btn.text)
	assert_eq(btn.text, "修煉")
	assert_eq(btn.visible_text(), "修煉", "face back to plain 修煉")


# ---------------------------------------------------------------- 面板回饋（UI 稽核 round 2）
## 回歸：面板（860×480）蓋住訊息紀錄；面板裡的自修、使用、裝備、卸下失敗時原因只進訊息紀錄，玩家按了看不到任何反應。
## 現在失敗原因顯示在面板底部的回饋列，成功時主機送的系統訊息也顯示在那裡。

func test_skills_panel_shows_self_study_failure_and_success() -> void:
	if not game_ok():
		return
	make_char()
	ch().combat_xp = 2000
	ch().skills.set_level("basic_inner", 1, tables())
	ch().learn_points = 0
	s().sheet_dirty = true
	host().flush_session(s(), true)
	ws.flush()
	await open_main()
	main.open_panel("skills")
	var fb: PanelFeedback = main.panel_feedback
	assert_true(fb.is_visible_in_tree(), "feedback strip visible inside the open panel")
	var b := button_in(main.panels["skills"], "×1")
	assert_true(b != null, "self-study button exists")
	if b == null:
		return
	press(b)
	await tree.process_frame
	assert_eq(fb.status_label.text, UiClient.reason_inline("not_enough_lp"), "failure reason shown in the panel")
	assert_false(fb.status_label.text.contains("【"), "no channel tag")
	# 有學點：成功 → 失敗原因清掉，主機的「你閉目揣摩……」出現在回饋列
	ch().learn_points = 100
	s().sheet_dirty = true
	host().flush_session(s(), true)
	deliver()
	await tree.process_frame
	b = button_in(main.panels["skills"], "×1")
	press(b)
	await tree.process_frame
	assert_eq(fb.status_label.text, "", "success clears the old failure: " + fb.status_label.text)
	deliver()
	await tree.process_frame
	assert_true(fb.feed_label.text.contains("熟練度"), "host self_study message shown in the panel: " + fb.feed_label.text)
	# 重開面板清空回饋
	main.close_panel()
	main.open_panel("skills")
	assert_eq(fb.feed_label.text, "")

func test_inventory_panel_shows_unequip_result_and_equip_failure() -> void:
	if not game_ok():
		return
	make_char()
	assert_true(str(ch().inventory.equipped.get("WEAPON", "")) != "", "starts with a weapon equipped")
	await open_main()
	main.open_panel("inventory")
	var fb: PanelFeedback = main.panel_feedback
	var b := button_in(main.panels["inventory"], "卸下")
	assert_true(b != null, "卸下 button on the equipped weapon")
	if b == null:
		return
	press(b)
	await tree.process_frame
	assert_eq(fb.status_label.text, "")
	assert_eq(str(ch().inventory.equipped.get("WEAPON", "")), "", "host unequipped")
	deliver()
	await tree.process_frame
	assert_true(fb.feed_label.text.contains("卸下了"), "host unequip message shown in the panel: " + fb.feed_label.text)
	# 主機拒絕（東西已經不在背包裡，例如另一個視窗剛賣掉）→ 原因顯示在面板裡
	var inv: InventoryPanel = main.panels["inventory"]
	inv._send(UiKeys.I_EQUIP, { "item_uid": "no_such_uid" })
	await tree.process_frame
	assert_eq(fb.status_label.text, UiClient.reason_inline(reason(UiKeys.I_EQUIP, { "item_uid": "no_such_uid" })),
		"equip failure shown in the panel")
	assert_true(fb.status_label.text != "")

# ---------------------------------------------------------------- 生活技能冷卻（場景卷軸按鈕）

func test_life_button_shows_cooldown() -> void:
	if not game_ok():
		return
	make_char()
	goto("xw_wood")
	ok("learn", { "npc": "n_xw_woodcutter", "skill": "life_woodcut" })
	Survival.rest_full(ch(), tables(), ws.options)
	s().sheet_dirty = true
	host().flush_session(s(), true)
	ws.flush()
	await open_main()
	var b := button_in(main.scene_panel, "砍柴")
	assert_true(b != null, "砍柴 button in the scene scroll")
	if b == null:
		return
	press(b)
	deliver()
	await tree.process_frame
	await tree.process_frame
	var cool: Button = null
	for c in _all(main.scene_panel):
		if c is Button and (c as Button).text.begins_with("砍柴（"):
			cool = c
	assert_true(cool != null, "life button shows the countdown")
	if cool == null:
		return
	assert_true(RegEx.create_from_string("^砍柴（[1-5] 秒）$").search(cool.text) != null, cool.text)
	assert_true(cool.disabled, "disabled while cooling")
	ws.advance(5.5)
	s().sheet_dirty = true
	host().flush_session(s(), true)
	ws.flush()
	await tree.process_frame
	await tree.process_frame
	var ready := button_in(main.scene_panel, "砍柴")
	assert_true(ready != null and not ready.disabled, "back to 砍柴")
