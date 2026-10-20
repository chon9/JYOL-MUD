class_name VillainPrompt
extends PanelContainer
## 惡人警告（STORY_PLAN §6.4、§5.2.2；夜遊與主動出手【設計提案・非原作】，追擊 NPC 原作 2001-08-30）：
## 主機送 villain_prompt（ui）{ wid, npc_name, countdown_s, can_call } → 非模態提示條（不擋其他操作）：
## 「南海鱷神朝你逼近！」＋倒數條＋「迎戰」「求救」＋「快離開這裡」。
## - 迎戰 → villain_reply { wid, choice: FIGHT }（立刻開打，戰鬥畫面接手）；
## - 求救 → villain_reply { wid, choice: CALL }（通知同地區的人，倒數照走；只能按一次；can_call == false 時不顯示）；
## - 倒數內離開房間 → 主機送 villain_clear { wid, why: ESCAPED }。villain_clear（任何 why）收起；開戰、換房間時主畫面也收起。
## 倒數用本機時間（真實秒數），到 0 時文字改成「躲不掉了！」，等主機開戰。

signal answered(choice: String)

var gate: IntentGate
var prompt: Dictionary = {}
var title_label: Label
var hint_label: Label
var line_label: Label             # 審查修正：惡人自己的警告句（warn_key）
var countdown_bar: ProgressBar
var countdown_label: Label
var fight_button: Button
var call_button: Button
var status_label: Label
var _room := ""                 # 出現時所在的房間（換房間＝已經離開）
var _total_s := 3.0
var _deadline_ms := 0
var _called := false
var _built := false

func _ready() -> void:
	ensure_built()

func _gate() -> IntentGate:
	if gate == null:
		gate = IntentGate.new()
		add_child(gate)
	return gate

func ensure_built() -> void:
	if _built:
		return
	_built = true
	name = "VillainPrompt" if name == "" else name
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.32, 0.04, 0.04, 0.92)
	st.border_color = UiTheme.JY_GOLD
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	add_theme_stylebox_override("panel", st)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var v := UiBuild.vbox(self, 4)
	title_label = UiBuild.label(v, "", 20)
	title_label.name = "VillainText"
	title_label.add_theme_color_override("font_color", Color("ffd040"))
	title_label.add_theme_constant_override("outline_size", 3)
	title_label.add_theme_color_override("font_outline_color", Color.BLACK)
	line_label = UiBuild.label(v, "", 15, true)
	line_label.name = "VillainLine"
	line_label.add_theme_color_override("font_color", Color("ffe0c0"))
	line_label.visible = false
	hint_label = UiBuild.label(v, "快離開這裡！走出這個房間就能脫身。", 15, true)
	hint_label.name = "VillainHint"
	hint_label.add_theme_color_override("font_color", Color.WHITE)
	var bar_row := UiBuild.hbox(v, 8)
	countdown_bar = UiBuild.bar(bar_row, UiTheme.JY_RED, 220.0)
	countdown_bar.name = "VillainBar"
	countdown_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	countdown_label = UiBuild.label(bar_row, "", 15)
	countdown_label.name = "VillainCountdown"
	countdown_label.add_theme_color_override("font_color", Color.WHITE)
	var row := UiBuild.hbox(v, 10)
	fight_button = UiBuild.button(row, "迎戰", fight, 96)
	fight_button.name = "VillainFight"
	fight_button.tooltip_text = "不躲了，立刻開打（追擊戰不能逃）"
	call_button = UiBuild.button(row, "求救", call_help, 96)
	call_button.name = "VillainCall"
	call_button.tooltip_text = "通知同一地區的隊友與玩家你在這裡遇襲"
	status_label = UiBuild.error(UiBuild.label(v, "", 14, true))
	status_label.add_theme_color_override("font_color", UiTheme.JY_ERROR_LIGHT)
	status_label.visible = false

func wid() -> String:
	return str(prompt.get("wid", ""))

## p = villain_prompt payload；room = 目前房間 id（換房間時自動收起）
func open_prompt(p: Dictionary, room := "") -> void:
	ensure_built()
	prompt = p.duplicate(true)
	_room = room
	_called = false
	_total_s = maxf(0.5, float(p.get("countdown_s", 3.0)))
	_deadline_ms = Time.get_ticks_msec() + int(_total_s * 1000.0)
	title_label.text = StoryUi.villain_text(p)
	line_label.text = StoryUi.villain_line(p)
	line_label.visible = line_label.text != ""
	call_button.visible = p.get("can_call", false) == true
	call_button.text = "求救"
	call_button.disabled = false
	fight_button.disabled = false
	status_label.text = ""
	status_label.visible = false
	_update_countdown()
	visible = true

## villain_clear：對得上（或沒帶 wid）才收
func on_clear(p: Dictionary) -> void:
	var w := str(p.get("wid", ""))
	if visible and (w == "" or w == wid()):
		dismiss()

## 換房間：已經離開惡人所在的房間（主機會送 ESCAPED；先收起來）
func on_room(room: String) -> void:
	if visible and _room != "" and room != "" and room != _room:
		dismiss()

func dismiss() -> void:
	prompt = {}
	visible = false

func left_s() -> float:
	return maxf(0.0, (_deadline_ms - Time.get_ticks_msec()) / 1000.0)

func _process(_delta: float) -> void:
	if visible:
		_update_countdown()

func _update_countdown() -> void:
	var left := left_s()
	UiBuild.set_bar(countdown_bar, left, _total_s)
	var t := "%d 秒" % ceili(left) if left > 0.0 else "躲不掉了！"
	if countdown_label.text != t:
		countdown_label.text = t

func fight() -> void:
	if prompt.is_empty():
		return
	answered.emit(UiKeys.VILLAIN_FIGHT)
	var w := wid()
	_reply(UiKeys.VILLAIN_FIGHT, [fight_button, call_button], func(ok: bool):
		if ok and wid() == w:
			dismiss())

func call_help() -> void:
	if prompt.is_empty() or _called:
		return
	_called = true
	answered.emit(UiKeys.VILLAIN_CALL)
	_reply(UiKeys.VILLAIN_CALL, [call_button], func(ok: bool):
		if not is_instance_valid(call_button):
			return
		if ok:
			call_button.text = "已求救"
			call_button.disabled = true
		else:
			_called = false)

func _reply(choice: String, lock: Array, after: Callable) -> void:
	status_label.visible = false
	_gate().send(UiKeys.I_VILLAIN_REPLY, { "wid": wid(), "choice": choice }, lock, func(ok: bool, reason: String):
		if not is_instance_valid(self):
			return
		if not ok:
			status_label.text = UiClient.reason_inline(reason)
			status_label.visible = status_label.text != ""
		after.call(ok))
