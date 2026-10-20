class_name Hotbar
extends VBoxContainer
## 底部 HUD 中區的熱鍵列（AUTHENTIC_UI_SPEC §6.2、§6.3）：
## - 第 1 列：指令快捷 F1–F8（9 頁），格子是指令方鈕縮小版；
## - 第 2 列：物品快捷 Alt+1–Alt+8（9 頁），格子顯示物品名前兩字與數量。
## 從指令窗或裝備窗把東西拖到格子上（右鍵或左鍵拖曳）；格子之間可以互拖交換；拖出熱鍵列外就清掉。
## 配置存在 settings.json 的 hotbar.<char_id>（每個角色分開）。冷卻中（修煉內力、生活技能；主機的 sheet.cooldowns）
## 格子灰掉、鈕面變兩行「修煉／（7 秒）」（讀起來「修煉（7 秒）」），冷卻完回到「修煉」。
## 按下格子只發 activated(payload, slot)，實際執行由主畫面 run_command() 處理。

signal activated(payload: String, slot: Button)

const SLOTS := 8
const PAGES := 9
const SLOT_SIZE := Vector2(46, 46)
const ROW_CMD := 0
const ROW_ITEM := 1
const CMD_PREFIX := "cmd:"
const ITEM_PREFIX := "item:"

var gate: IntentGate
var char_id := ""
var cmd_pages: Array = []          # PAGES × SLOTS 個指令 id（"" = 空）
var item_pages: Array = []         # PAGES × SLOTS 個物品 id
var cmd_page := 0
var item_page := 0
var slots: Array = [[], []]        # [row][i] -> HotbarSlot
var page_labels: Array = []        # [row] -> Label
var sheet: Dictionary = {}
var view: Dictionary = {}
var in_battle := false
var cooldowns := CooldownTracker.new()
var _built := false

func _ready() -> void:
	ensure_built()

func ensure_built() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 4)
	_reset_pages()
	for row in [ROW_CMD, ROW_ITEM]:
		var h := UiBuild.hbox(self, 6)
		var pg := UiBuild.vbox(h, 0)
		pg.custom_minimum_size = Vector2(24, 0)
		var lbl := UiBuild.label(pg, "", 13)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		page_labels.append(lbl)
		var up := UiBuild.button(pg, "▲", _flip.bind(row, -1))
		var dn := UiBuild.button(pg, "▼", _flip.bind(row, 1))
		pg.move_child(lbl, 1)   # ▲ 頁碼 ▼
		for b in [up, dn]:
			b.add_theme_font_size_override("font_size", 10)
			b.custom_minimum_size = Vector2(22, 12)
			for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
				b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
			b.add_theme_color_override("font_color", UiTheme.JY_GOLD)
			b.add_theme_color_override("font_hover_color", UiTheme.JY_GOLD_LIGHT)
			b.focus_mode = Control.FOCUS_NONE
			b.tooltip_text = "換頁"
		for i in SLOTS:
			var s := HotbarSlot.new()
			s.bar = self
			s.row = row
			s.index = i
			s.custom_minimum_size = SLOT_SIZE
			s.hotkey_text = ("F%d" % (i + 1)) if row == ROW_CMD else ("A%d" % (i + 1))
			s.pressed.connect(func(): _on_slot_pressed(s))
			h.add_child(s)
			slots[row].append(s)
	refresh()

func _reset_pages() -> void:
	cmd_pages = []
	item_pages = []
	for p in PAGES:
		var c: Array = []
		var it: Array = []
		for i in SLOTS:
			c.append(str(UiCommands.DEFAULT_HOTBAR[i]) if p == 0 else "")
			it.append("")
		cmd_pages.append(c)
		item_pages.append(it)

## 換角色時載入該角色的配置
func load_for(cid: String) -> void:
	char_id = cid
	_reset_pages()
	var saved: Variant = UiSettings.get_value("hotbar." + cid, {}) if cid != "" else {}
	if saved is Dictionary:
		_merge(cmd_pages, (saved as Dictionary).get("cmd", []))
		_merge(item_pages, (saved as Dictionary).get("item", []))
	refresh()

static func _merge(dst: Array, src: Variant) -> void:
	if not (src is Array):
		return
	for p in mini(PAGES, (src as Array).size()):
		var row: Variant = src[p]
		if row is Array:
			for i in mini(SLOTS, (row as Array).size()):
				dst[p][i] = str(row[i])

func save() -> void:
	if char_id != "":
		UiSettings.set_value("hotbar." + char_id, { "cmd": cmd_pages, "item": item_pages })

func payload_at(row: int, i: int) -> String:
	var id: String = (cmd_pages[cmd_page] if row == ROW_CMD else item_pages[item_page])[i]
	if id == "":
		return ""
	return (CMD_PREFIX if row == ROW_CMD else ITEM_PREFIX) + id

func set_payload(row: int, i: int, payload: String) -> void:
	var id := payload.trim_prefix(CMD_PREFIX).trim_prefix(ITEM_PREFIX)
	if row == ROW_CMD:
		cmd_pages[cmd_page][i] = id
	else:
		item_pages[item_page][i] = id
	refresh()
	save()

## 這個 payload 能不能放到這一列
static func accepts(row: int, payload: String) -> bool:
	if row == ROW_CMD:
		return payload.begins_with(CMD_PREFIX) and UiCommands.is_known(payload.trim_prefix(CMD_PREFIX))
	return payload.begins_with(ITEM_PREFIX) and payload.length() > ITEM_PREFIX.length()

func _flip(row: int, d: int) -> void:
	if row == ROW_CMD:
		cmd_page = posmod(cmd_page + d, PAGES)
	else:
		item_page = posmod(item_page + d, PAGES)
	refresh()

func apply_sheet(s: Dictionary) -> void:
	ensure_built()
	sheet = s
	var cid := str(s.get("char_id", ""))
	if cid != char_id:
		load_for(cid)
	cooldowns.update(s)
	refresh()

func apply_view(v: Dictionary) -> void:
	view = v
	refresh()

func meditate_cooling() -> bool:
	return cooldowns.left_ms(CooldownTracker.KEY_MEDITATE) > 0

## 熱鍵（F1–F8 = 列 0、Alt+1–8 = 列 1）
func trigger(row: int, i: int) -> bool:
	ensure_built()
	if i < 0 or i >= SLOTS:
		return false
	var s: HotbarSlot = slots[row][i]
	if s.disabled or payload_at(row, i) == "":
		return false
	_on_slot_pressed(s)
	return true

func _on_slot_pressed(s: HotbarSlot) -> void:
	var p := payload_at(s.row, s.index)
	if p != "":
		activated.emit(p, s)

func _process(_delta: float) -> void:
	if _built:
		_update_states()

## 文字、glyph、可按與否（每幀：IntentGate 收到結果時會把格子解鎖，冷卻中要再鎖回去）
func refresh() -> void:
	if not _built:
		return
	(page_labels[ROW_CMD] as Label).text = str(cmd_page + 1)
	(page_labels[ROW_ITEM] as Label).text = "%02d" % (item_page + 1)
	for i in SLOTS:
		var cs: HotbarSlot = slots[ROW_CMD][i]
		var cid: String = cmd_pages[cmd_page][i]
		cs.style = JyButton.Style.BRONZE if cid != "" else JyButton.Style.SLOT
		cs.glyph = UiCommands.glyph(cid) if cid != "" else ""
		cs.text = UiCommands.glyph(cid) if cid != "" else ""   # 格子小：用短名（「修煉」），冷卻中「修煉（7 秒）」
		cs.state_sig = []      # 換頁／換指令：下一次 _update_states 重組文字與提示
		slots[ROW_ITEM][i].state_sig = []
		cs.drag_payload = payload_at(ROW_CMD, i)
		var is_ := item_pages[item_page][i] as String
		var it_slot: HotbarSlot = slots[ROW_ITEM][i]
		it_slot.style = JyButton.Style.SLOT
		var row := UiClient.row("items", is_) if is_ != "" else {}
		var nm := str(row.get("name", UiCommands.find_item(sheet, is_).get("name", is_))) if is_ != "" else ""
		it_slot.text = nm
		it_slot.glyph = nm.left(2)
		it_slot.count = UiCommands.item_count(sheet, is_) if is_ != "" else 0
		it_slot.drag_payload = payload_at(ROW_ITEM, i)
	_update_states()

## 每幀只比對狀態（可按與否、剩餘秒數）；文字與提示框只在 指令／秒數／不能用的原因／數量 變了才重組
func _update_states() -> void:
	for i in SLOTS:
		var cs: HotbarSlot = slots[ROW_CMD][i]
		var cid: String = cmd_pages[cmd_page][i]
		var why := UiCommands.unavailable_reason(cid, sheet, view) if cid != "" else ""
		var secs := cooldowns.left_s(CooldownTracker.key_for(cid)) if cid != "" else 0
		var pending := gate != null and cid != "" and gate.is_pending(intent_of(cid))
		var dis := cid == "" or why != "" or secs > 0 or pending or in_battle
		if cs.disabled != dis:
			cs.disabled = dis
		var sig := [cid, secs, why]
		if cs.state_sig != sig:
			cs.state_sig = sig
			# 鈕面：名稱（glyph）＋ 冷卻中下一行「（7 秒）」→ 讀起來「修煉（7 秒）」；Button.text 同一串（提示、UI driver）
			cs.set_cooldown_text(CooldownTracker.suffix(secs) if cid != "" else "")
			cs.text = CooldownTracker.label(UiCommands.glyph(cid), secs) if cid != "" else ""
			var tip := "%s　%s" % [CooldownTracker.label(UiCommands.label(cid), secs), UiCommands.tip(cid)] if cid != "" else "（空）把指令窗的指令拖到這裡，按 F%d 使用" % (i + 1)
			if why != "":
				tip += "
" + why
			cs.tooltip_text = tip
		var it_slot: HotbarSlot = slots[ROW_ITEM][i]
		var iid: String = item_pages[item_page][i]
		var n := UiCommands.item_count(sheet, iid) if iid != "" else 0
		var idis := iid == "" or n <= 0 or (gate != null and gate.is_pending(UiKeys.I_USE_ITEM))
		if it_slot.disabled != idis:
			it_slot.disabled = idis
		if it_slot.count != n:
			it_slot.count = n
			it_slot.queue_redraw()
		var isig := [iid, n, it_slot.text]
		if it_slot.state_sig != isig:
			it_slot.state_sig = isig
			it_slot.tooltip_text = ("%s ×%d（Alt+%d 使用）" % [it_slot.text, n, i + 1]) if iid != "" else "（空）把裝備窗的物品拖到這裡，按 Alt+%d 使用" % (i + 1)

## 指令對應的 intent（判斷送出中用）
static func intent_of(cmd_id: String) -> String:
	match cmd_id:
		"look":
			return UiKeys.I_LOOK
		"meditate":
			return UiKeys.I_MEDITATE
		"exert_qi", "exert_jing", "exert_shen":
			return UiKeys.I_EXERT
	if UiCommands.is_work(cmd_id):
		return UiKeys.I_WORK
	return ""
