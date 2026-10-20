class_name StoryDialog
extends UiDialog
## 任務對話視窗（STORY_PLAN §6.1、§4.5；對話文字全是【設計提案】，由主機的任務資料決定）。
## 主機送 dialogue（ui）開啟或換下一句：{ npc, npc_name, quest, quest_name, dlg, node, speaker_name, text,
##   choices: [ { id, label, locked, why } ], end }。
## 版面（審查修正：照 AUTHENTIC_UI_SPEC §8.7 NPC 對話框，680×416、立繪 180×240、立繪下方名牌）：與 NpcDialog 同一種
## 水墨暈染底、沒有標題列；左邊立繪（ArtRegistry，與 NPC 對話框同一套）與名牌，右邊墨框：任務名（小字）、說話者（只在說話的不是
## 這位 NPC 時顯示：玩家或第三人）、內文（逐字顯示，點一下或按空白鍵跳過）、金色分隔線、編號選項（數字鍵 1–9；
## 上鎖的選項灰色、滑鼠提示 why）。名牌：資料沒有 NPC 職稱欄位，照 NpcDialog 只寫名字（「職稱-名字」待資料補職稱）。
## - 選項 → dialogue_choose { npc, quest, node, choice }，主機回下一句（dialogue）或 dialogue_close；
## - 節點用 goto 接下一句：主機（DialogueTree）送一個合成的「繼續」選項（id "_next"），照一般選項處理；
##   萬一沒有選項又還沒結束 → 本地補「繼續」= dialogue_choose 的 choice ""（防呆）；
## - end == true → 只剩「結束」，關掉不送東西（主機已清掉對話游標）；
## - 中途「結束」、⊠、Esc → dialogue_close 後關掉。
## 主機的 dialogue_close、移動（換房間）、開戰時主畫面直接收起（不送）。與 NpcDialog（服務選單）並存。

const PORTRAIT := Vector2(180, 240)
const CHARS_PER_S := 40.0
const CONTINUE_CHOICE := ""

var payload: Dictionary = {}
var quest_label: Label
var speaker_label: Label
var text_label: Label
var choices_box: VBoxContainer
var portrait: TextureRect
var name_plate: Label
var choice_buttons: Array = []     # [Button]（編號順序）
var _reveal := 0.0                 # 目前顯示到第幾個字（逐字）
var _waiting := false              # 選項已送出，等主機回下一句

## 審查修正：照 AUTHENTIC_UI_SPEC §8.7 與 NpcDialog 同一種水墨暈染底、沒有標題列（同一位 NPC 不會換兩種視窗）
func frame_kind() -> int:
	return UiFrame.Kind.INKWASH

func dialog_size() -> Vector2:
	return Vector2(680, 416)

func _build_body() -> void:
	title_label.name = "StoryNpcName"
	title_label.visible = false   # NPC 名在立繪下方的名牌（同 NpcDialog）
	close_button.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	var row := UiBuild.hbox(body, 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := UiBuild.vbox(row, 6)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var pf := PanelContainer.new()
	var pst := StyleBoxFlat.new()
	pst.bg_color = Color.BLACK
	pst.border_color = UiTheme.JY_GOLD
	pst.set_border_width_all(2)
	pst.set_corner_radius_all(6)
	pst.set_content_margin_all(4)
	pf.add_theme_stylebox_override("panel", pst)
	left.add_child(pf)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = PORTRAIT
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pf.add_child(portrait)
	# 名牌（§8.7：立繪下方，暗色底、金色繩邊、白字）
	var plate := PanelContainer.new()
	plate.name = "StoryNamePlateBox"
	var nst := StyleBoxFlat.new()
	nst.bg_color = Color("1a120c")
	nst.border_color = UiTheme.JY_ROPE
	nst.set_border_width_all(2)
	nst.set_corner_radius_all(4)
	nst.set_content_margin_all(4)
	plate.add_theme_stylebox_override("panel", nst)
	left.add_child(plate)
	name_plate = UiBuild.label(plate, "", 16)
	name_plate.name = "StoryNamePlate"
	name_plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var box := UiBuild.framed(row, UiFrame.Kind.INK)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc := UiBuild.scroll(box)
	var v := UiBuild.vbox(sc, 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_label = UiBuild.muted(UiBuild.label(v, "", 14))
	quest_label.name = "StoryQuest"
	speaker_label = UiBuild.accent(UiBuild.label(v, "", 16))
	speaker_label.name = "StorySpeaker"
	text_label = UiBuild.label(v, "", 18, true)
	text_label.name = "StoryText"
	text_label.custom_minimum_size = Vector2(380, 0)
	text_label.add_theme_constant_override("line_spacing", 4)
	text_label.mouse_filter = Control.MOUSE_FILTER_STOP
	text_label.tooltip_text = "點一下顯示整段"
	text_label.gui_input.connect(_on_text_input)
	var sep := ColorRect.new()
	sep.color = UiTheme.JY_GOLD
	sep.custom_minimum_size = Vector2(0, 2)
	v.add_child(sep)
	choices_box = UiBuild.vbox(v, 2)
	choices_box.name = "StoryChoices"

# ---------------------------------------------------------------- 資料

func npc_id() -> String:
	return str(payload.get("npc", ""))

func quest_id() -> String:
	return str(payload.get("quest", ""))

func node_id() -> String:
	return str(payload.get("node", ""))

func is_end() -> bool:
	return bool(payload.get("end", false))

## dialogue（ui）事件：開啟或換成下一句
func open_node(p: Dictionary) -> void:
	ensure_built()
	payload = p.duplicate(true)
	_waiting = false
	status_label.text = ""
	var npc_name := str(p.get("npc_name", ""))
	title_label.text = npc_name if npc_name != "" else "對話"
	var qn := str(p.get("quest_name", ""))
	quest_label.text = "任務：%s" % qn if qn != "" else ""
	quest_label.visible = qn != ""
	name_plate.text = npc_name
	# 說話者：NPC 自己說話時名牌已經寫了名字，不再重複；玩家或第三人說話時才顯示
	var sp := str(p.get("speaker_name", ""))
	speaker_label.text = sp if sp != "" else npc_name
	speaker_label.visible = sp != "" and sp != npc_name
	_set_portrait(npc_id())
	text_label.text = str(p.get("text", ""))
	_reveal = 0.0
	text_label.visible_characters = 0 if text_label.text != "" else -1
	_build_choices()
	_sync_reveal()
	visible = true

func _set_portrait(npc: String) -> void:
	var tex := ArtRegistry.unit_texture(npc, "NPC", "idle") if npc != "" else null
	portrait.modulate = Color.WHITE
	if tex == null:
		tex = LookPicker.sheet_look_texture(UiClient.sheet())   # M3c：剪影用自己的外觀（取不到用 player_m）
		portrait.modulate = Color(0.25, 0.22, 0.2, 0.9)
	portrait.texture = tex

## 選項（含「繼續」「結束」）；逐字還沒顯示完時先藏起來
func _build_choices() -> void:
	UiBuild.clear(choices_box)
	choice_buttons.clear()
	var list: Array = payload.get("choices", []) if payload.get("choices", []) is Array else []
	var rows: Array = []
	for c in list:
		if c is Dictionary:
			rows.append(c)
	if rows.is_empty():
		if is_end():
			rows.append({ "id": "__end", "label": "結束", "locked": false, "why": "" })
		else:
			rows.append({ "id": CONTINUE_CHOICE, "label": "繼續……", "locked": false, "why": "" })
	for i in rows.size():
		var c: Dictionary = rows[i]
		var row := UiBuild.hbox(choices_box, 2)
		var num := UiBuild.accent(UiBuild.label(row, "%d." % (i + 1), 18))
		num.custom_minimum_size = Vector2(24, 0)
		var b := UiBuild.button(row, str(c.get("label", "")))
		b.name = "Choice%d" % (i + 1)
		b.theme_type_variation = "ChoiceButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.set_meta("choice", str(c.get("id", "")))
		if bool(c.get("locked", false)):
			b.disabled = true
			var why := str(c.get("why", ""))
			b.tooltip_text = why if why != "" else "目前還不能這麼做。"
		b.pressed.connect(_on_choice.bind(b))
		choice_buttons.append(b)
	# 中途想走：選項外另有「結束」（結束節點已經是唯一的「結束」選項）
	if not is_end():
		var row2 := UiBuild.hbox(choices_box, 2)
		UiBuild.label(row2, "", 18).custom_minimum_size = Vector2(24, 0)
		var bx := UiBuild.button(row2, "結束對話（Esc）")
		bx.name = "StoryLeave"
		bx.theme_type_variation = "ChoiceButton"
		bx.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bx.pressed.connect(close)

## 選項的 id（測試、bot 用）：編號順序，含「繼續」的 "" 與結束節點的 "__end"
func choice_ids() -> Array:
	return choice_buttons.map(func(b): return str((b as Button).get_meta("choice", "")))

func is_typing() -> bool:
	return visible and text_label.visible_characters >= 0 and text_label.visible_characters < text_label.text.length()

func skip_typing() -> void:
	_reveal = float(text_label.text.length())
	_sync_reveal()

func _sync_reveal() -> void:
	var n := text_label.text.length()
	if int(_reveal) >= n:
		text_label.visible_characters = -1
	else:
		text_label.visible_characters = int(_reveal)
	choices_box.visible = not is_typing()

func _process(delta: float) -> void:
	if visible and text_label != null and text_label.visible_characters >= 0:
		_reveal += delta * CHARS_PER_S
		_sync_reveal()

func _on_text_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and is_typing():
		skip_typing()
		text_label.accept_event()

# ---------------------------------------------------------------- 動作

## 第 i 個選項（0 起算；數字鍵 1 = 0）。逐字顯示中先跳過，不直接選（避免連按誤選）
func choose_index(i: int) -> void:
	if is_typing():
		skip_typing()
		return
	if i < 0 or i >= choice_buttons.size():
		return
	var b: Button = choice_buttons[i]
	if not b.disabled:
		_on_choice(b)

func _on_choice(b: Button) -> void:
	if payload.is_empty() or _waiting:
		return
	var cid := str(b.get_meta("choice", ""))
	if cid == "__end":
		_dismiss()
		return
	_waiting = true
	var args := { "npc": npc_id(), "quest": quest_id(), "node": node_id(), "choice": cid }
	var node := node_id()
	status_label.text = ""
	# 只鎖能按的（解鎖時 IntentGate 一律 disabled = false，上鎖的選項不能被解開）
	var lock := choice_buttons.filter(func(x): return not (x as Button).disabled)
	_gate().send(UiKeys.I_DIALOGUE_CHOOSE, args, lock, func(ok: bool, reason: String):
		if not is_instance_valid(self):
			return
		if not ok:
			status_label.text = UiClient.reason_inline(reason)
		# 成功：等主機的下一句或 dialogue_close（通常比結果先到）；還停在同一節點就讓玩家再選
		if node_id() == node:
			_waiting = false)

## ⊠、Esc、「結束對話」：對話還沒結束就送 dialogue_close，然後關掉
func close() -> void:
	if not payload.is_empty() and not is_end():
		_gate().send(UiKeys.I_DIALOGUE_CLOSE, {})
	_dismiss()

## 直接收起、不送（主機已收回：dialogue_close、移動、開戰；或結束節點）
func _dismiss() -> void:
	payload = {}
	_waiting = false
	visible = false
	closed.emit()

## 主機的 dialogue_close：同一位 NPC（或沒帶 npc）才關
func on_closed(p: Dictionary) -> void:
	if not visible:
		return
	var n := str(p.get("npc", ""))
	if n == "" or n == npc_id():
		_dismiss()

## 移動、開戰：主機已清掉對話游標
func dismiss() -> void:
	if visible:
		_dismiss()

## 數字鍵 1–9 選；空白鍵、Enter 在逐字顯示中跳過，顯示完後 Enter 選唯一的選項（繼續／結束）
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return
	if k.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		if is_typing():
			skip_typing()
		elif k.keycode != KEY_SPACE and choice_buttons.size() == 1:
			choose_index(0)
		else:
			return
		get_viewport().set_input_as_handled()
		return
	var i := int(k.keycode) - int(KEY_1)
	if i < 0 or i >= mini(9, choice_buttons.size()):
		return
	choose_index(i)
	get_viewport().set_input_as_handled()
