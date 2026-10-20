extends "res://tests/test_case.gd"
## M3C_PLAN §6.8、§6.7（WP-LOOT）：裝備窗 8 格、稀有度上色、條件不合灰鈕、研讀送出形狀、戰鬥結果上色與「得到寶物！」。
## 全部假資料（資料列暫時放進 GameData，after_each 還原），不碰主機與存檔。

const Scenes := preload("res://tests/unit/test_ui_scenes.gd")

var _nodes: Array = []
var _patched: Dictionary = {}

func before_each() -> void:
	UiSettings.reset_for_tests(true)

func after_each() -> void:
	for t in _patched:
		var tbl: Dictionary = GameData.tables.get(t, {})
		for id in _patched[t]:
			if _patched[t][id] == null:
				tbl.erase(id)
			else:
				tbl[id] = _patched[t][id]
	_patched.clear()
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame

func _add(n: Node) -> Node:
	tree.root.add_child(n)
	_nodes.append(n)
	return n

func _frame() -> void:
	await tree.process_frame

func _put(table: String, id: String, row: Dictionary) -> void:
	if not GameData.tables.has(table):
		GameData.tables[table] = {}
	var tbl: Dictionary = GameData.tables[table]
	if not _patched.has(table):
		_patched[table] = {}
	if not _patched[table].has(id):
		_patched[table][id] = tbl.get(id, null)
	tbl[id] = row

func _gate(sent: Array) -> IntentGate:
	var g := IntentGate.new()
	_add(g)
	g.set_sender(func(kind, args):
		sent.append([kind, args])
		var seq := sent.size()
		g.resolve.call_deferred(seq, true, "")
		return seq)
	return g

static func loot_sheet() -> Dictionary:
	return {
		"char_id": "ch_me", "name": "我", "gender": "M", "carry": 20, "carry_max": 200, "weapon_power": 40, "armor_power": 11,
		"skills": [ { "id": "basic_literacy", "name": "讀書識字", "kind": "BASIC", "level": 25 } ],
		"equipped": { "WEAPON": "u_w", "ARMOR": "", "HEAD": "u_h", "NECK": "", "WRIST": "", "CLOAK": "", "RING": "u_r", "BOOTS": "" },
		"inventory": [
			{ "uid": "u_w", "id": "t_lt_heijian", "name": "黑劍", "tab": "WEAPON", "n": 1, "weight": 5, "equipped_slot": "WEAPON",
			  "usable": false, "equippable": true, "rarity": "FINE", "slot": "WEAPON", "req_ok": true, "req_text": "", "bonus": {},
			  "official": { "atk": 40, "def": 0, "weight": 10 } },
			{ "uid": "u_h", "id": "t_lt_maozi", "name": "帽子", "tab": "ARMOR", "n": 1, "weight": 2, "equipped_slot": "HEAD",
			  "usable": false, "equippable": true, "rarity": "COMMON", "slot": "HEAD", "req_ok": true, "req_text": "", "bonus": {} },
			{ "uid": "u_r", "id": "t_lt_ring", "name": "紅石戒", "tab": "ARMOR", "n": 1, "weight": 1, "equipped_slot": "RING",
			  "usable": false, "equippable": true, "rarity": "TREASURE", "slot": "RING", "req_ok": true, "req_text": "", "bonus": { "cal": 5 } },
			{ "uid": "u_y", "id": "t_lt_yushang", "name": "羽裳", "tab": "ARMOR", "n": 1, "weight": 4, "equipped_slot": "",
			  "usable": false, "equippable": true, "rarity": "COMMON", "slot": "ARMOR", "req_ok": false, "req_text": "限女性", "bonus": {} },
			{ "uid": "u_b", "id": "t_bk_book", "name": "胡青牛醫書", "tab": "OTHER", "n": 1, "weight": 1, "equipped_slot": "",
			  "usable": false, "equippable": false, "rarity": "RARE", "slot": "", "req_ok": true, "req_text": "", "bonus": {} },
			{ "uid": "u_d", "id": "t_sb_sword", "name": "倚天劍", "tab": "WEAPON", "n": 1, "weight": 23, "equipped_slot": "",
			  "usable": false, "equippable": true, "rarity": "DIVINE", "slot": "WEAPON", "req_ok": true, "req_text": "", "bonus": {} },
		],
	}

func _rows() -> void:
	_put("items", "t_lt_heijian", { "id": "t_lt_heijian", "name": "黑劍", "slot": "WEAPON", "weapon_type": "SWORD", "atk": 40, "weight": 5,
		"rarity": "FINE", "official": { "atk": 40, "def": 0, "weight": 10 } })
	_put("items", "t_lt_maozi", { "id": "t_lt_maozi", "name": "帽子", "slot": "HEAD", "def": 4, "weight": 2 })
	_put("items", "t_lt_ring", { "id": "t_lt_ring", "name": "紅石戒", "slot": "RING", "def": 3, "weight": 1, "rarity": "TREASURE", "bonus": { "cal": 5 } })
	_put("items", "t_lt_yushang", { "id": "t_lt_yushang", "name": "羽裳", "slot": "ARMOR", "def": 3, "weight": 4,
		"requires": [{ "type": "gender", "value": "F" }] })
	_put("items", "t_bk_book", { "id": "t_bk_book", "name": "胡青牛醫書", "slot": "", "rarity": "RARE",
		"manual": { "skill": "basic_medic", "cap": 60, "literacy_min": 20, "prof": 6, "jing": 15, "shen": 15 } })
	_put("items", "t_sb_sword", { "id": "t_sb_sword", "name": "倚天劍", "slot": "WEAPON", "weapon_type": "SWORD", "atk": 80, "weight": 23,
		"rarity": "DIVINE", "divine": true, "no_drop": true })

func _panel(sent: Array) -> InventoryPanel:
	_rows()
	var p := InventoryPanel.new()
	p.gate = _gate(sent)
	_add(p)
	await _frame()
	p.apply_sheet(loot_sheet())
	return p

func _actions(p: InventoryPanel) -> Dictionary:
	var out := {}
	for c in p.actions.get_children():
		if c is Button:
			out[(c as Button).text] = c
	return out

func test_eight_body_slots_and_rarity() -> void:
	var sent: Array = []
	var p := await _panel(sent)
	assert_eq(p.body_buttons.size(), 8)
	for slot in UiKeys.SLOTS:
		assert_true((p.body_buttons[slot] as InventoryPanel.EquipSlot).supported, "%s 可用" % slot)
		assert_false((p.body_buttons[slot] as Button).disabled)
	assert_eq(p.body_buttons["HEAD"].item_uid, "u_h", "帽子在頭部欄")
	assert_eq(p.body_buttons["RING"].rarity, "TREASURE")
	assert_true(p.body_buttons["NECK"].tooltip_text.contains("空"), "空格寫部位名")
	# 舊主機只送兩格 → 其他照舊灰色
	var old := loot_sheet()
	old["equipped"] = { "WEAPON": "u_w", "ARMOR": "" }
	p.apply_sheet(old)
	assert_false((p.body_buttons["HEAD"] as InventoryPanel.EquipSlot).supported)
	p.apply_sheet(loot_sheet())
	# 物品格依稀有度上色
	p.set_tab("WEAPON")
	var slots := {}
	for c in p.grid.get_children():
		if c is InventoryPanel.LootSlot and (c as Button).has_meta("item_uid"):
			slots[str(c.get_meta("item_uid"))] = c
	assert_eq(slots["u_w"].rarity, "FINE")
	assert_eq(slots["u_d"].rarity, "DIVINE")
	assert_true((slots["u_d"] as Button).tooltip_text.begins_with("倚天劍 ×"), "提示框照舊以「名稱 ×」開頭（UI 驅動用）")
	assert_true((slots["u_d"] as Button).tooltip_text.contains("神兵"))
	assert_eq(LootUi.rarity_color("RARE"), Color("#5b9bf0"))
	assert_eq(LootUi.rarity_name("TREASURE"), "珍品")
	assert_eq(LootUi.decorated_name("鋸齒刀", "RARE"), "【精品】鋸齒刀")
	assert_eq(LootUi.decorated_name("黑劍", "FINE"), "黑劍", "良品不加字樣")

func test_detail_requirement_grey_button() -> void:
	var sent: Array = []
	var p := await _panel(sent)
	p.set_tab("ARMOR")
	p.select("u_y")
	var a := _actions(p)
	assert_true(a.has("裝備"))
	assert_true((a["裝備"] as Button).disabled, "條件不合：裝備鈕灰掉")
	assert_true((a["裝備"] as Button).tooltip_text.contains("限女性"))
	assert_true(p.detail_label.text.contains("限女性") and p.detail_label.text.contains("無法裝備"), p.detail_label.text)
	assert_true(p.detail_label.text.contains("#ff5040"), "條件紅字")
	assert_true(p.detail_label.text.contains("部位：衣服"))
	(a["裝備"] as Button).pressed.emit()
	assert_eq(sent.size(), 0, "灰掉的鈕不送")
	p.select("u_r")
	assert_true(p.detail_label.text.contains("定力 +5"), "屬性加成")
	assert_true(p.detail_label.text.contains("珍品"))
	p.set_tab("WEAPON")
	p.select("u_w")
	assert_false(p.detail_label.text.contains("官方："), "M3c 第二輪審查：不顯示與本作數值矛盾的官方原值 " + p.detail_label.text)
	assert_true(p.detail_label.text.contains("類型：劍"))
	p.select("u_d")
	assert_true(p.detail_label.text.contains("全服唯一"))
	assert_true((_actions(p)["丟棄"] as Button).disabled, "神兵不能丟")

func test_manual_read_sends_shape() -> void:
	var sent: Array = []
	var p := await _panel(sent)
	p.set_tab("OTHER")
	p.select("u_b")
	assert_true(p.detail_label.text.contains("讀書識字 25 級：最多讀到 25 級"), p.detail_label.text)
	var a := _actions(p)
	assert_true(a.has("研讀"), "秘笈有研讀鈕")
	assert_true(p.read_times != null)
	assert_eq(p.read_times.item_count, 3, "次數 1／5／10")
	p.read_times.select(1)
	(a["研讀"] as Button).pressed.emit()
	assert_eq(sent.size(), 1)
	assert_eq(sent[0][0], UiKeys.I_MANUAL_READ)
	assert_eq(sent[0][1], { "item_uid": "u_b", "times": 5 })
	# 讀書識字不夠 → 研讀灰掉
	var sh := loot_sheet()
	sh["skills"] = []
	p.apply_sheet(sh)
	p.select("u_b")
	assert_true((_actions(p)["研讀"] as Button).disabled)

func test_battle_result_rarity_colors() -> void:
	var bs = _add((load("res://ui/game/battle/battle_screen.tscn") as PackedScene).instantiate())
	await _frame()
	bs.setup(Scenes._battle_state())
	bs.show_result({ "bid": 3, "result": "VICTORY", "you_died": false, "death": {},
		"rewards": { "combat_xp": 30, "learn_points": 5, "money": 300, "items": [
			{ "id": "c_jingyao", "name": "精藥水", "n": 1, "rarity": "COMMON" },
			{ "id": "w_lt_juchidao", "name": "鋸齒刀", "n": 1, "rarity": "RARE" },
			{ "id": "a_lt_hongshijie", "name": "紅石戒", "n": 1, "rarity": "TREASURE" } ] } })
	var t: String = bs.result_detail.text
	assert_true(t.contains("精藥水 ×1"), t)
	assert_true(t.contains("【精品】鋸齒刀"), "精品以上加字樣")
	assert_true(t.contains("【珍品】紅石戒"))
	assert_true(t.contains("[color=#%s]" % LootUi.paper_color("RARE").to_html(false)), "依稀有度上色")
	assert_true(bs.treasure_label.visible, "珍品以上：得到寶物！")
	assert_eq(bs.treasure_label.text, "得到寶物！")
	assert_eq(bs.loot_glow_rarity, "TREASURE", "0.6 秒光暈")
	assert_true(Array(bs.log_plain_lines()).any(func(l): return l.contains("【珍品】紅石戒")), "戰報也寫字樣")
	# 一般戰利品：沒有金字、沒有光暈
	bs.show_result({ "bid": 3, "result": "VICTORY", "you_died": false, "death": {},
		"rewards": { "combat_xp": 1, "learn_points": 1, "money": 0, "items": [ { "id": "r_rabbitskin", "name": "兔皮", "n": 1 } ] } })
	assert_false(bs.treasure_label.visible)
	assert_eq(bs.loot_glow_rarity, "")
	assert_true(bs.result_detail.text.contains("兔皮"))
	assert_eq(BattleScreen.best_rarity([{ "rarity": "FINE" }, { "rarity": "DIVINE" }, {}]), "DIVINE")
