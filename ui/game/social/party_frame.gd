class_name PartyFrame
extends PanelContainer
## 隊伍面板（M2_PLAN 4.10 擇一：燈籠旁的小框）：有隊伍時顯示在右上小地圖下方（小地圖關掉時頂到最上面）。
## 依 sheet.party（4.5.1）：成員（依加入順序）、★領隊、離線、所在地、戰鬥中；
## 領隊對別的成員有「領」（移交領隊 party_lead）、「踢」（party_kick）；每個人都有「離隊」（party_leave）。
## 三個動作都先發 confirm_requested 由主畫面的確認框確認（M2 審查：12 px 的「領」「踢」緊貼著，一個誤點就踢人／交出領隊）；
## 沒人接這個訊號時（單元測試）直接送出。

signal confirm_requested(title: String, message: String, ok_label: String, on_ok: Callable)

var gate: IntentGate
var sheet: Dictionary = {}
var title_label: Label
var list_box: VBoxContainer
var leave_button: Button
var member_rows: Dictionary = {}     # char_id -> HBoxContainer
const KICK_GAP := 12.0
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
	add_theme_stylebox_override("panel", UiFrame.style(UiFrame.Kind.INK))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UiBuild.vbox(self, 3)
	var head := UiBuild.hbox(v, 6)
	title_label = UiBuild.accent(UiBuild.label(head, "隊伍", 15))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave_button = UiBuild.button(head, "離隊", ask_leave)
	leave_button.add_theme_font_size_override("font_size", 13)
	leave_button.tooltip_text = "離開隊伍（戰鬥中也可以，戰鬥照常進行）"
	list_box = UiBuild.vbox(v, 2)
	visible = false

func apply_sheet(s: Dictionary) -> void:
	ensure_built()
	sheet = s
	UiBuild.clear(list_box)
	member_rows.clear()
	if not UiSocial.in_party(s):
		visible = false
		return
	var ms := UiSocial.members(s)
	var maxn := UiBuild.num(UiClient.world_info().get("party_max", UiKeys.PARTY_MAX_DEFAULT))
	title_label.text = "隊伍（%d／%d）" % [ms.size(), maxn if maxn > 0 else UiKeys.PARTY_MAX_DEFAULT]
	var me := str(s.get("char_id", ""))
	var lead := UiSocial.is_leader(s)
	for m in ms:
		if not (m is Dictionary):
			continue
		var cid := str(m.get("char_id", ""))
		var row := UiBuild.hbox(list_box, 4)
		var l := UiBuild.label(row, UiSocial.member_line(m, false), 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.tooltip_text = UiSocial.member_line(m)
		# 「戰鬥中」獨立成不截斷的標籤：長名字只會截掉地點，不會截掉戰鬥中
		var tag := UiSocial.member_battle_tag(m)
		if tag != "":
			var bt := UiBuild.label(row, tag, 13)
			bt.name = "Battle_" + cid
			bt.autowrap_mode = TextServer.AUTOWRAP_OFF
			bt.add_theme_color_override("font_color", UiTheme.JY_SYS_YELLOW)
			bt.tooltip_text = "正在戰鬥，走到同一個地方可以加入"
		if cid == me:
			l.add_theme_color_override("font_color", UiTheme.JY_GOLD_LIGHT)
		elif not bool(m.get("online", true)):
			UiBuild.muted(l)
		if lead and cid != me:
			var mname := str(m.get("name", ""))
			var bl := UiBuild.button(row, "領", ask_lead.bind(cid, mname))
			bl.name = "Lead_" + cid
			bl.tooltip_text = "把領隊交給%s" % mname
			bl.add_theme_font_size_override("font_size", 12)
			var gap := Control.new()   # 「領」「踢」分開一點，避免誤點
			gap.custom_minimum_size = Vector2(KICK_GAP, 0)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(gap)
			var bk := UiBuild.button(row, "踢", ask_kick.bind(cid, mname))
			bk.name = "Kick_" + cid
			bk.tooltip_text = "把%s請出隊伍" % mname
			bk.add_theme_font_size_override("font_size", 12)
		member_rows[cid] = row
	visible = true

## 先確認再送（有人接 confirm_requested 時）
func _confirm(title: String, message: String, ok_label: String, on_ok: Callable) -> void:
	if confirm_requested.get_connections().is_empty():
		on_ok.call()
	else:
		confirm_requested.emit(title, message, ok_label, on_ok)

func ask_leave() -> void:
	_confirm("離隊", "確定要離開隊伍？", "離隊", leave)

func ask_kick(char_id: String, mname: String) -> void:
	_confirm("請出隊伍", "確定要把%s請出隊伍？" % mname, "請出", kick.bind(char_id))

func ask_lead(char_id: String, mname: String) -> void:
	_confirm("移交領隊", "確定要把領隊交給%s？" % mname, "移交", lead_to.bind(char_id))

func leave() -> void:
	_gate().send(UiKeys.I_PARTY_LEAVE, {}, [leave_button])

func kick(char_id: String) -> void:
	_gate().send(UiKeys.I_PARTY_KICK, { "target": char_id })

func lead_to(char_id: String) -> void:
	_gate().send(UiKeys.I_PARTY_LEAD, { "target": char_id })
