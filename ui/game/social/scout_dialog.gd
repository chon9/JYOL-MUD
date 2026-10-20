class_name ScoutDialog
extends UiDialog
## 查看偵察的邀戰提示（docs/GDD.md §5.10【設計提案・非原作】）：野外按「查看」後主機送 scout_offer（ui 事件），
## 這裡顯示「你發現附近有：野兔 ×2」、怪物立繪與倒數，玩家選
## - 「迎戰」（Enter）→ scout_accept { offer_id }：主機驗證後開戰（同踩地雷），戰鬥畫面打開時本框跟著收起；
## - 「離開」（Esc、⊠）→ scout_decline { offer_id }，框立刻關掉。
## 主機收回提示（換房、進戰鬥、過期、被新的提示取代、主機關掉選項）時送 scout_closed（ui），offer_id 對得上就關掉。
## 怪物一律由主機決定，這裡只回傳 offer_id。

signal answered(accept: bool)

const PORTRAIT := Vector2(72, 72)

var message_label: Label
var monsters_box: HBoxContainer
var countdown_label: Label
var accept_button: Button
var leave_button: Button
var offer: Dictionary = {}
var _expires_ms := 0
var _answered := false

func dialog_size() -> Vector2:
	return Vector2(440, 0)

func _build_body() -> void:
	title_label.text = "查看"
	message_label = UiBuild.label(body, "", 18, true)
	message_label.name = "ScoutText"
	message_label.add_theme_color_override("font_color", UiTheme.JY_SYS_YELLOW)
	monsters_box = UiBuild.hbox(body, 10)
	monsters_box.alignment = BoxContainer.ALIGNMENT_CENTER
	countdown_label = UiBuild.muted(UiBuild.label(body, "", 14))
	countdown_label.name = "ScoutCountdown"
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := UiBuild.hbox(body, 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	accept_button = UiBuild.button(row, "迎戰", accept, 110)
	accept_button.name = "ScoutAccept"
	accept_button.tooltip_text = "上前迎戰（Enter）"
	leave_button = UiBuild.button(row, "離開", close, 110)
	leave_button.name = "ScoutLeave"
	leave_button.tooltip_text = "不驚動牠們（Esc）"

## p = scout_offer 的 payload：{ offer_id, room, room_name, monsters: [ { id, name, n } ], text, ttl_s }
func open_offer(p: Dictionary) -> void:
	ensure_built()
	offer = p.duplicate(true)
	_answered = false
	title_label.text = "查看・%s" % str(p.get("room_name", "")) if str(p.get("room_name", "")) != "" else "查看"
	message_label.text = offer_text(p)
	UiBuild.clear(monsters_box)
	for g in p.get("monsters", []):
		if not (g is Dictionary):
			continue
		var v := UiBuild.vbox(monsters_box, 2)
		var tex := ArtRegistry.unit_texture(str(g.get("id", "")), "MONSTER", "idle")
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.custom_minimum_size = PORTRAIT
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(tr)
		var l := UiBuild.label(v, "%s ×%d" % [str(g.get("name", "?")), int(g.get("n", 1))], 15)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_expires_ms = Time.get_ticks_msec() + int(float(p.get("ttl_s", 30.0)) * 1000.0)
	accept_button.disabled = false
	leave_button.disabled = false
	status_label.text = ""
	_update_countdown()
	visible = true
	accept_button.grab_focus.call_deferred()

## 「你發現附近有：野兔 ×2」（主機給 text 就用 text）
static func offer_text(p: Dictionary) -> String:
	var t := str(p.get("text", ""))
	if t != "":
		return t
	var parts: PackedStringArray = []
	for g in p.get("monsters", []):
		if g is Dictionary:
			parts.append("%s ×%d" % [str(g.get("name", "?")), int(g.get("n", 1))])
	return "你發現附近有：" + "、".join(parts)

func offer_id() -> String:
	return str(offer.get("offer_id", ""))

func offer_room() -> String:
	return str(offer.get("room", ""))

## 迎戰：送 scout_accept；成功時戰鬥畫面會打開（主畫面把對話框收起），失敗顯示原因後關掉
func accept() -> void:
	if offer.is_empty() or _answered:
		return
	_answered = true
	var id := offer_id()
	answered.emit(true)
	send(UiKeys.I_SCOUT_ACCEPT, { "offer_id": id }, [accept_button, leave_button], func():
		if is_instance_valid(self) and offer_id() == id:
			_dismiss())
	# 失敗：UiDialog.send 把原因寫在 status_label；按鈕由 IntentGate 解鎖，再按「離開」關掉

## 離開（按鈕、Esc、⊠）：送 scout_decline（提示已失效也沒關係，主機一律回成功），立刻關掉
func close() -> void:
	if not offer.is_empty() and not _answered:
		_answered = true
		answered.emit(false)
		_gate().send(UiKeys.I_SCOUT_DECLINE, { "offer_id": offer_id() })
	_dismiss()

## 不送任何東西直接收起（主機已收回提示、換了房間、開戰）
func _dismiss() -> void:
	offer = {}
	visible = false
	closed.emit()

## scout_closed（ui）：對得上目前的提示才關
func on_closed(p: Dictionary) -> void:
	if visible and str(p.get("offer_id", "")) == offer_id():
		_dismiss()

## 換房間：主機已經收回提示，直接關
func on_room(room_id: String) -> void:
	if visible and offer_room() != "" and room_id != offer_room():
		_dismiss()

func _process(_delta: float) -> void:
	if visible:
		_update_countdown()

func _update_countdown() -> void:
	var left := maxi(0, ceili((_expires_ms - Time.get_ticks_msec()) / 1000.0))
	var t := "（%d 秒內決定）" % left if left > 0 else "（附近的動靜漸漸遠去……）"
	if countdown_label.text != t:
		countdown_label.text = t

## Enter：迎戰（焦點在聊天框時 Enter 歸聊天框；Esc 由主畫面關對話框＝離開）
func _shortcut_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.keycode in [KEY_ENTER, KEY_KP_ENTER] and not (k.ctrl_pressed or k.alt_pressed or k.shift_pressed):
		var f := get_viewport().gui_get_focus_owner()
		if f is LineEdit or f is TextEdit:
			return
		if accept_button.disabled:
			return
		accept()
		get_viewport().set_input_as_handled()
