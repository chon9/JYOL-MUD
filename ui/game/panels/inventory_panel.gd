class_name InventoryPanel
extends VBoxContainer
## 裝備窗（Ctrl+3，AUTHENTIC_UI_SPEC §8.4；原作背包與裝備在同一窗，所以「背包」改名「裝備」）：
## - 左半：分頁 武器／防具／其他／原料，下面 5×4 栗色物品格（可捲動）；
## - 右半：墨線人形，周圍裝備格 頭盔／頸／右手／護腕／衣服／披風／戒指／靴子（M3c：8 格全部可用；空格灰底寫部位名）；
## - M3c（M3C_PLAN §6.8，WP-LOOT）：物品名依稀有度上色、詳情列出部位／類型／攻防／重量／加成／條件（不合紅字）／官方數值／
##   秘笈說明（「研讀」鈕，次數 1／5／10）／神兵說明；條件不合時「裝備」鈕灰掉附原因。
## - 下方：金框數值盒「攻 n 防 n」（攻紅字、防黃字）與負重；
## - 選取中的物品：名稱、說明，使用（use_item）、裝備／卸下（equip／unequip）、丟棄（drop_item，確認）。
## 點格子選取；右鍵格子＝使用或裝備；把格子拖到人形＝裝備；拖到 Alt 熱鍵列＝物品快捷。

const COLS := 5
const ROWS := 4
const SLOT := Vector2(46, 46)
## 人形周圍的裝備格：左右兩欄（紙娃娃版面），中間留給角色圖，格子不蓋住臉和身體。
## at = (x, y) 為框內可擺範圍的比例：x 0＝貼左、1＝貼右；y 0＝貼上、1＝貼下。slot = sheet.equipped 的鍵（沒有的部位是灰格）
const BODY_SLOTS := [
	{ "name": "頭盔", "slot": "HEAD", "at": Vector2(0.0, 0.0) },
	{ "name": "右手", "slot": "WEAPON", "at": Vector2(0.0, 0.333) },
	{ "name": "披風", "slot": "CLOAK", "at": Vector2(0.0, 0.667) },
	{ "name": "戒指", "slot": "RING", "at": Vector2(0.0, 1.0) },
	{ "name": "頸", "slot": "NECK", "at": Vector2(1.0, 0.0) },
	{ "name": "護腕", "slot": "WRIST", "at": Vector2(1.0, 0.333) },
	{ "name": "衣服", "slot": "ARMOR", "at": Vector2(1.0, 0.667) },
	{ "name": "靴子", "slot": "BOOTS", "at": Vector2(1.0, 1.0) },
]

var gate: IntentGate
var feedback: PanelFeedback
var tab_bar: TabBar
var grid: GridContainer
var body: Control
var body_buttons: Dictionary = {}    # slot -> JyButton
var stats_label: RichTextLabel
var carry_label: Label
var equip_label: Label
var detail_label: RichTextLabel
var read_times: OptionButton         # 秘笈研讀次數（1／5／10）
var actions: HBoxContainer
var confirm_row: HBoxContainer
var confirm_label: Label
var current_tab := "WEAPON"
var selected_uid := ""
var sheet: Dictionary = {}
var _pending_drop: Dictionary = {}
var _built := false

func _ready() -> void:
	if not _built:
		_build()

func _gate() -> IntentGate:
	if gate == null:
		gate = IntentGate.new()
		add_child(gate)
	return gate

## 面板動作的結果回饋（失敗原因、成功訊息）；主畫面會塞共用的回饋列，單獨使用時自己建一個
func _fb() -> PanelFeedback:
	if feedback == null or not is_instance_valid(feedback):
		feedback = PanelFeedback.new()
		add_child(feedback)
	return feedback

func _send(kind: String, args: Dictionary, lock: Array = []) -> int:
	var fb := _fb()
	fb.begin()
	return _gate().send(kind, args, lock, func(ok: bool, reason: String):
		if is_instance_valid(fb):
			fb.show_result(ok, reason))

func _build() -> void:
	_built = true
	add_theme_constant_override("separation", 6)
	var row := UiBuild.hbox(self, 12)
	var left := UiBuild.vbox(row, 0)
	tab_bar = TabBar.new()
	for t in UiKeys.INV_TABS:
		tab_bar.add_tab(UiKeys.INV_TAB_LABELS[t])
	tab_bar.tab_changed.connect(func(i: int): set_tab(UiKeys.INV_TABS[i]))
	left.add_child(tab_bar)
	var gframe := UiBuild.framed(left, UiFrame.Kind.INK)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(COLS * (SLOT.x + 4) + 12, ROWS * (SLOT.y + 4))
	gframe.add_child(sc)
	grid = GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	sc.add_child(grid)
	# 人形與裝備格
	var right := UiBuild.vbox(row, 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bframe := UiBuild.framed(right, UiFrame.Kind.INK)
	body = Figure.new()
	body.custom_minimum_size = Vector2(250, 230)
	bframe.add_child(body)
	for bs in BODY_SLOTS:
		var b := EquipSlot.new()
		b.panel = self
		b.slot = str(bs["slot"])
		b.part = str(bs["name"])
		body.add_child(b)
		body_buttons[b.slot] = b
	body.resized.connect(_place_body_slots)
	_place_body_slots.call_deferred()   # 大小可能在接上 resized 之前就定了：補一次，不然八格全疊在左上角
	var stats := UiBuild.hbox(right, 8)
	var sframe := PanelContainer.new()
	var sst := StyleBoxFlat.new()
	sst.bg_color = Color(0, 0, 0, 0.5)
	sst.border_color = UiTheme.JY_GOLD
	sst.set_border_width_all(1)
	sst.set_content_margin_all(4)
	sframe.add_theme_stylebox_override("panel", sst)
	stats.add_child(sframe)
	stats_label = RichTextLabel.new()
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	stats_label.custom_minimum_size = Vector2(130, 0)
	sframe.add_child(stats_label)
	carry_label = UiBuild.label(stats, "", 15)
	equip_label = UiBuild.muted(UiBuild.label(right, "", 14, true))
	# 選取中的物品
	add_child(HSeparator.new())
	var drow := UiBuild.hbox(self, 8)
	detail_label = RichTextLabel.new()
	detail_label.bbcode_enabled = true
	detail_label.fit_content = true
	detail_label.scroll_active = false
	detail_label.add_theme_font_size_override("normal_font_size", 15)
	detail_label.add_theme_color_override("default_color", UiTheme.JY_TEXT)
	detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_label.custom_minimum_size = Vector2(320, 0)
	drow.add_child(detail_label)
	actions = UiBuild.hbox(drow, 6)
	confirm_row = UiBuild.hbox(self, 8)
	confirm_label = UiBuild.label(confirm_row, "", 15)
	UiBuild.button(confirm_row, "確定丟棄", _on_confirm_drop)
	UiBuild.button(confirm_row, "取消", func(): confirm_row.visible = false)
	confirm_row.visible = false

func _place_body_slots() -> void:
	for bs in BODY_SLOTS:
		var b: Control = body_buttons[str(bs["slot"])]
		var at: Vector2 = bs["at"]
		const M := 6.0   # 離框邊的距離
		b.position = Vector2(M + at.x * (body.size.x - SLOT.x - M * 2.0), M + at.y * (body.size.y - SLOT.y - M * 2.0))
		b.size = SLOT

func set_tab(tab: String) -> void:
	current_tab = tab
	if tab_bar != null and tab_bar.current_tab != UiKeys.INV_TABS.find(tab):
		tab_bar.current_tab = UiKeys.INV_TABS.find(tab)
	# 換頁：預設選這頁第一件已裝備的（沒有就第一件）
	selected_uid = _default_selection()
	_rebuild()

func apply_sheet(s: Dictionary) -> void:
	if not _built:
		_build()
	sheet = s
	body.set_look(str(s.get("look", "")))
	_place_body_slots()
	carry_label.text = "負重 %d / %d" % [UiBuild.num(s.get("carry", 0)), UiBuild.num(s.get("carry_max", 0))]
	stats_label.text = "[color=%s]攻[/color] [color=#ff5040]%d[/color]　[color=%s]防[/color] [color=#ffe040]%d[/color]" % [
		UiTheme.JY_LABEL.to_html(false), UiBuild.num(s.get("weapon_power", 0)), UiTheme.JY_LABEL.to_html(false), UiBuild.num(s.get("armor_power", 0))]
	var eq: Dictionary = s.get("equipped", {})
	var names: PackedStringArray = []
	var worn := 0
	for slot in ["WEAPON", "ARMOR"]:
		var it := find_item(str(eq.get(slot, "")))
		names.append("%s：%s" % [LootUi.SLOT_NAMES[slot], str(it.get("name", "無")) if not it.is_empty() else "無"])
	for slot in eq:
		if not (str(slot) in ["WEAPON", "ARMOR"]) and str(eq[slot]) != "":
			worn += 1
	if worn > 0:
		names.append("其他 %d 件" % worn)
	equip_label.text = "　".join(names)
	for slot in body_buttons:
		var b: EquipSlot = body_buttons[slot]
		var it := find_item(str(eq.get(slot, "")))
		# M3c：主機送幾格就開幾格（舊主機只送 WEAPON／ARMOR → 其他照舊灰色）
		b.supported = eq.has(slot)
		b.rarity = str(it.get("rarity", "COMMON")) if not it.is_empty() else ""
		b.text = "%s：%s" % [b.part, str(it.get("name", ""))] if not it.is_empty() else b.part
		b.glyph = str(it.get("name", "")).left(2) if not it.is_empty() else ""
		b.item_uid = str(it.get("uid", ""))
		b.disabled = not b.supported
		if not b.supported:
			b.tooltip_text = "%s（這個世界的主機沒有此部位）" % b.part
		elif it.is_empty():
			b.tooltip_text = b.part + "（空）"
		else:
			b.tooltip_text = "%s（%s）" % [b.text, LootUi.rarity_name(b.rarity)]
		b.queue_redraw()
	if find_item(selected_uid).is_empty() or str(find_item(selected_uid).get("tab", "OTHER")) != current_tab:
		selected_uid = _default_selection()
	_rebuild()

func _default_selection() -> String:
	var items := items_in_tab(current_tab)
	for it in items:
		if str(it.get("equipped_slot", "")) != "":
			return str(it.get("uid", ""))
	return str(items[0].get("uid", "")) if not items.is_empty() else ""

func find_item(uid: String) -> Dictionary:
	if uid == "":
		return {}
	for it in sheet.get("inventory", []):
		if it is Dictionary and str(it.get("uid", "")) == uid:
			return it
	return {}

func items_in_tab(tab: String) -> Array:
	var out: Array = []
	for it in sheet.get("inventory", []):
		if it is Dictionary and str(it.get("tab", "OTHER")) == tab:
			out.append(it)
	return out

func _rebuild() -> void:
	UiBuild.clear(grid)
	var items := items_in_tab(current_tab)
	for i in maxi(COLS * ROWS, int(ceil(items.size() / float(COLS))) * COLS):
		if i < items.size():
			var it: Dictionary = items[i]
			var uid := str(it.get("uid", ""))
			var nm := str(it.get("name", it.get("id", "")))
			var b := LootSlot.new()
			grid.add_child(b)
			b.text = "%s ×%d%s" % [nm, UiBuild.num(it.get("n", 1)), "（已裝備）" if str(it.get("equipped_slot", "")) != "" else ""]
			b.rarity = str(it.get("rarity", "COMMON"))
			b.glyph = InventoryPanel.slot_glyph(nm)
			b.custom_minimum_size = SLOT
			b.count = UiBuild.num(it.get("n", 1))
			b.marked = uid == selected_uid
			b.drag_payload = Hotbar.ITEM_PREFIX + str(it.get("id", ""))
			b.set_meta("item_uid", uid)
			var desc := str(UiClient.row("items", str(it.get("id", ""))).get("desc", ""))
			var fresh := freshness_text(it)
			b.tooltip_text = b.text + ("\n" + fresh if fresh != "" else "") + "\n" + LootUi.rarity_name(b.rarity) \
				+ ("\n" + desc if desc != "" else "")
			b.hotkey_text = freshness_corner(it)
			b.pressed.connect(func(): select(uid))
			b.gui_input.connect(_on_slot_input.bind(uid))
		else:
			var e := UiBuild.slot(grid, "")
			e.custom_minimum_size = SLOT
			e.disabled = true
			e.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_rebuild_detail()

## 每疊的新鮮度（伺服器在 sheet 裡給 spoil_left_days：最早一批還剩幾天；-1 ＝不會腐壞）
static func freshness_text(it: Dictionary) -> String:
	if not it.has("spoil_left_days"):
		return "" if bool(it.get("perishable", false)) else "不會腐壞"
	var d := float(it.get("spoil_left_days", -1.0))
	if d < 0.0:
		return "不會腐壞"
	if d < 1.0:
		return "最早一批剩不到 1 天會腐壞"
	return "最早一批剩 %d 天會腐壞" % int(floor(d))

## 格子左上角小字：快壞了（不到 3 天）才標
static func freshness_corner(it: Dictionary) -> String:
	var d := float(it.get("spoil_left_days", -1.0))
	if d < 0.0 or d >= 3.0:
		return ""
	return "<1天" if d < 1.0 else "%d天" % int(floor(d))

func select(uid: String) -> void:
	selected_uid = uid
	_rebuild()

## 右鍵：使用或裝備
func _on_slot_input(ev: InputEvent, uid: String) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and not mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		quick_use(uid)

func quick_use(uid: String) -> void:
	var it := find_item(uid)
	if it.is_empty():
		return
	if bool(it.get("usable", false)):
		_send(UiKeys.I_USE_ITEM, { "item_uid": uid })
	elif bool(it.get("equippable", false)) and str(it.get("equipped_slot", "")) == "":
		send_equip(UiKeys.I_EQUIP, { "item_uid": uid })

func _rebuild_detail() -> void:
	UiBuild.clear(actions)
	_cd_buttons.clear()
	var it := find_item(selected_uid)
	if it.is_empty():
		detail_label.text = "（空）" if items_in_tab(current_tab).is_empty() else "點選物品；右鍵使用或裝備；拖到人形裝備、拖到 Alt 熱鍵列。"
		return
	var uid := selected_uid
	var slot := str(it.get("equipped_slot", ""))
	var row := UiClient.row("items", str(it.get("id", "")))
	detail_label.text = detail_bb(it, row, literacy_level())
	detail_label.tooltip_text = str(row.get("desc", ""))
	if bool(it.get("usable", false)):
		var bu := UiBuild.button(actions, "使用")
		bu.pressed.connect(func(): _send(UiKeys.I_USE_ITEM, { "item_uid": uid }, [bu]))
	if slot != "":
		var bq := UiBuild.button(actions, "卸下")
		bq.pressed.connect(func(): send_equip(UiKeys.I_UNEQUIP, { "slot": slot }, [bq]))
		_cd_buttons.append(bq)
	elif bool(it.get("equippable", false)):
		var be := UiBuild.button(actions, "裝備")
		if bool(it.get("req_ok", true)):
			be.pressed.connect(func(): send_equip(UiKeys.I_EQUIP, { "item_uid": uid }, [be]))
			_cd_buttons.append(be)
		else:
			be.disabled = true
			be.tooltip_text = "條件不合：%s" % str(it.get("req_text", ""))
	var m: Variant = row.get("manual", null)
	if m is Dictionary and str((m as Dictionary).get("skill", "")) != "":
		read_times = OptionButton.new()
		for n in READ_TIMES:
			read_times.add_item("%d 遍" % n, n)
		read_times.tooltip_text = "一次研讀幾遍"
		actions.add_child(read_times)
		var br := UiBuild.button(actions, "研讀")
		var need := int((m as Dictionary).get("literacy_min", 0))
		if literacy_level() >= 0 and literacy_level() < need:
			br.disabled = true
			br.tooltip_text = "讀書識字要 %d 級才看得懂" % need
		br.pressed.connect(func(): read_manual(uid, br))
	var bd := UiBuild.button(actions, "丟棄")
	if bool(row.get("no_drop", false)):
		bd.disabled = true
		bd.tooltip_text = "神兵利器不能丟棄"
	else:
		bd.pressed.connect(ask_drop.bind(it))

func ask_drop(it: Dictionary) -> void:
	_pending_drop = it
	confirm_label.text = "確定要丟掉 %s ×%d 嗎？丟掉的東西會直接消失。" % [str(it.get("name", "")), UiBuild.num(it.get("n", 1))]
	confirm_row.visible = true

func _on_confirm_drop() -> void:
	confirm_row.visible = false
	if _pending_drop.is_empty():
		return
	_send(UiKeys.I_DROP_ITEM, { "item_uid": str(_pending_drop.get("uid", "")), "n": clampi(UiBuild.num(_pending_drop.get("n", 1)), 1, 999) })
	_pending_drop = {}

## 人形上的裝備格：接受背包格拖來的物品（裝備）；有東西時點一下選取
class EquipSlot extends JyButton:
	var panel: InventoryPanel
	var slot := ""
	var part := ""
	var item_uid := ""
	var supported := true
	var rarity := ""

	func _init() -> void:
		super(JyButton.Style.SLOT, "", "")
		pressed.connect(func():
			if item_uid != "" and panel != null:
				panel.select_equipped(item_uid))

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return supported and data is Dictionary and (data as Dictionary).get("source") is JyButton \
			and ((data as Dictionary)["source"] as JyButton).has_meta("item_uid")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		var uid := str(((data as Dictionary)["source"] as JyButton).get_meta("item_uid"))
		var it := panel.find_item(uid)
		if bool(it.get("equippable", false)) and str(it.get("equipped_slot", "")) == "":
			panel.send_equip(UiKeys.I_EQUIP, { "item_uid": uid })

	func _draw() -> void:
		super()
		if not supported:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.4, 0.4, 0.4, 0.55))
		elif glyph == "":
			draw_rect(Rect2(Vector2.ZERO, size).grow(-3.0), Color(0.5, 0.5, 0.5, 0.18))   # 空格：灰底
		elif rarity != "" and LootUi.rank(rarity) >= 1:
			draw_rect(Rect2(Vector2.ZERO, size).grow(-2.5), LootUi.rarity_color(rarity), false, 1.5)
		if glyph == "":
			var f := UiTheme.find_font() if UiTheme.find_font() != null else ThemeDB.fallback_font
			var w := f.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(f, Vector2((size.x - w) / 2.0, size.y / 2.0 + 4.0), part, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))

func select_equipped(uid: String) -> void:
	var it := find_item(uid)
	if it.is_empty():
		return
	current_tab = str(it.get("tab", current_tab))
	if tab_bar.current_tab != UiKeys.INV_TABS.find(current_tab):
		tab_bar.current_tab = UiKeys.INV_TABS.find(current_tab)
	select(uid)

## 裝備格中間的人形：畫玩家自己的角色圖（初始造型或門派服裝，sheet.look）；沒有圖才退回墨線人形。
## （擁有者回報：裝備頁是一個骨架人，為什麼不用角色圖）
class Figure extends Control:
	var tex: Texture2D = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_look(look: String) -> void:
		var t: Texture2D = ArtRegistry.unit_texture(look if look != "" else "player_m", "PLAYER", "idle")
		if t != tex:
			tex = t
			queue_redraw()

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 0)
		var h := size.y
		if tex != null:
			# 腳底貼框底、高度約佔 94%，水平置中在 c.x（裝備格依同一個中心擺）
			var th := h * 0.94
			var tw := th * float(tex.get_width()) / maxf(1.0, float(tex.get_height()))
			draw_texture_rect(tex, Rect2(c.x - tw / 2.0, h - th, tw, th), false)
			return
		var ink := Color(0.85, 0.8, 0.65, 0.55)
		var w := 1.5
		draw_arc(c + Vector2(0, h * 0.14), h * 0.07, 0, TAU, 24, ink, w, true)
		draw_line(c + Vector2(0, h * 0.21), c + Vector2(0, h * 0.58), ink, w, true)
		draw_line(c + Vector2(-h * 0.16, h * 0.3), c + Vector2(h * 0.16, h * 0.3), ink, w, true)
		draw_line(c + Vector2(-h * 0.16, h * 0.3), c + Vector2(-h * 0.22, h * 0.5), ink, w, true)
		draw_line(c + Vector2(h * 0.16, h * 0.3), c + Vector2(h * 0.22, h * 0.5), ink, w, true)
		draw_line(c + Vector2(0, h * 0.58), c + Vector2(-h * 0.1, h * 0.9), ink, w, true)
		draw_line(c + Vector2(0, h * 0.58), c + Vector2(h * 0.1, h * 0.9), ink, w, true)

# ---------------------------------------------------------------- M3c 打寶（M3C_PLAN §6.8；WP-LOOT）

const READ_TIMES := [1, 5, 10]

## 詳情（BBCode）：名稱（稀有度色）、數量、重量、新鮮度＋LootUi.detail_bb 的裝備／秘笈／神兵說明
func detail_bb(it: Dictionary, row: Dictionary, literacy: int) -> String:
	var lines: PackedStringArray = []
	var n := UiBuild.num(it.get("n", 1))
	# M3c 審查：名稱不加「【珍品】」（下一行就是稀有度）；有部位的裝備重量在部位那一行（不重複寫「重」）
	var has_slot := str(it.get("slot", row.get("slot", ""))) != ""
	var head := "%s ×%d" % [LootUi.bb_name(str(it.get("name", it.get("id", ""))), it.get("rarity", "COMMON"), false), n]
	if not has_slot:
		head += "　重 %d" % (UiBuild.num(it.get("weight", 0)) * n)
	if str(it.get("equipped_slot", "")) != "":
		head += "（已裝備）"
	lines.append(head)
	var fr := freshness_text(it)
	if fr != "":
		lines.append(fr)
	var more := LootUi.detail_bb(it, row, literacy)
	# detail_bb 的第一行是名稱＋稀有度：這裡已經有名稱，只留稀有度
	var parts := more.split("\n")
	if parts.size() > 0:
		lines.append("[color=#%s]%s[/color]" % [LootUi.dark_color(it.get("rarity", "COMMON")).to_html(false),
			LootUi.rarity_name(it.get("rarity", "COMMON"))])
		for i in range(1, parts.size()):
			lines.append(parts[i])
	return "\n".join(lines)

## 角色表的讀書識字等級（沒有角色表時 -1）
func literacy_level() -> int:
	if sheet.is_empty():
		return -1
	for sk in sheet.get("skills", []):
		if sk is Dictionary and str(sk.get("id", "")) == "basic_literacy":
			return UiBuild.num(sk.get("level", 0))
	return 0

func selected_read_times() -> int:
	if read_times == null or not is_instance_valid(read_times) or read_times.selected < 0:
		return 1
	return int(read_times.get_item_id(read_times.selected))

func read_manual(uid: String, lock: Control = null) -> int:
	return _send(UiKeys.I_MANUAL_READ, { "item_uid": uid, "times": selected_read_times() }, [lock] if lock != null else [])

## M3c 審查：格子上的字——三個字以內整個寫（「精鋼戒」不再切成「精鋼」），更長的取前兩個字；字太寬時 _draw_slot 縮小字級
static func slot_glyph(nm: String) -> String:
	return nm if nm.length() <= 3 else nm.left(2)

## 物品格：依稀有度上色（良品以上畫色框、名稱用稀有度色）
class LootSlot extends JyButton:
	var rarity := "COMMON"

	func _init() -> void:
		super(JyButton.Style.SLOT, "", "")
		custom_minimum_size = InventoryPanel.SLOT

	func _draw_slot(font: Font, hot: bool) -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiFrame.style(UiFrame.Kind.SLOT), r)
		var col := LootUi.rarity_color(rarity)
		var rk := LootUi.rank(rarity)
		if rk >= 1:
			draw_rect(r.grow(-3.0), Color(col.r, col.g, col.b, 0.16))
			draw_rect(r.grow(-2.5), col, false, 1.5)
		if hot:
			draw_rect(r.grow(-1.5), UiTheme.JY_GOLD, false, 1.0)
		if marked:
			draw_rect(r.grow(-1.0), JY_MARK, false, 2.0)
		var s := face()
		if s != "":
			var fs := int(clampf(size.y * 0.3, 11.0, 18.0))
			while fs > 10 and font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 6.0:
				fs -= 1
			# M3c 第二輪審查：格子底已帶稀有度色，字再用同色就糊在一起（紫字疊紫底）→ 字一律用一般字色，稀有度看底色與色框
			_center_text(font, s, fs, UiTheme.JY_TEXT, Vector2(0, -1), 2)
		if count > 1:
			var cs := str(count)
			var w := font.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var p := Vector2(size.x - w - 3.0, size.y - 3.0)
			draw_string_outline(font, p, cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.85))
			draw_string(font, p, cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.JY_LABEL)

# ==== M3d WP-COMBAT：換裝兩秒（M3D_PLAN §3.6） ====
## 換裝成功後 2 秒內「裝備／卸下」鈕灰掉、提示「換裝要間隔兩秒」；冷卻中右鍵快換、拖到人形也不送（主機另有 equip_cooldown）。
## 冷卻長度用 world_info.equip_cooldown_ms（主機有給時），否則 2 秒。
var equip_cd_until_ms := -1
var _cd_buttons: Array = []
var _cd_shown := false

static func equip_cd_ms() -> int:
	var wi := UiClient.world_info()
	return clampi(int(wi.get("equip_cooldown_ms", int(UiKeys.EQUIP_COOLDOWN_S * 1000.0))), 0, 5000)

func equip_cooling() -> bool:
	return equip_cd_until_ms >= 0 and Time.get_ticks_msec() < equip_cd_until_ms

func send_equip(kind: String, args: Dictionary, lock: Array = []) -> int:
	if equip_cooling():
		_fb().show_result(false, UiKeys.R_EQUIP_COOLDOWN)
		return -1
	var fb := _fb()
	fb.begin()
	return _gate().send(kind, args, lock, func(ok: bool, reason: String):
		if ok:
			equip_cd_until_ms = Time.get_ticks_msec() + equip_cd_ms()
			_apply_cd()
		if is_instance_valid(fb):
			fb.show_result(ok, reason))

func _apply_cd() -> void:
	var on := equip_cooling()
	_cd_shown = on
	for b in _cd_buttons:
		if is_instance_valid(b):
			(b as Button).disabled = on or (b as Button).tooltip_text.begins_with("條件不合")
			if on:
				(b as Button).tooltip_text = UiKeys.EQUIP_COOLDOWN_TEXT
			elif (b as Button).tooltip_text == UiKeys.EQUIP_COOLDOWN_TEXT:
				(b as Button).tooltip_text = ""

func _process(_delta: float) -> void:
	if _cd_shown and not equip_cooling():
		_apply_cd()
	elif not _cd_shown and equip_cooling():
		_apply_cd()
