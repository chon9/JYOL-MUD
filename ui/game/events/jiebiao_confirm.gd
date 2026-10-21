class_name JiebiaoConfirm
extends NumberedDialog
## 劫鏢（M3D_PLAN §5.2.2；1.0B；WP-EVENTS）：列出同房頭上標「押鏢」的玩家（view.players[].tags），
## 確認「確定要劫 X 的鏢？」→ rob_escort { target_char }。確認段寫明後果（劫鏢算強制 PK：PK值 +1、
## 一個時辰的劫鏢標記〔守城官兵追殺〕、開打後劫鏢方不能逃；成功由活著的劫鏢者平分鏢價八成）。
## 本機先擋明顯不行的情況（實戰不到 10 萬、城裡不能動手、同隊、對方戰鬥中），其餘交主機判斷。數字鍵 1–9 選第 n 個人。

const RULE_TEXT := "劫鏢算強制 PK：PK值 +1，開打當下起一個時辰內進城，守城官兵會追殺。開打後劫鏢方不能逃（無敵烙跑鞋也不行）。打倒鏢車（或客商）、或押鏢的人倒下／逃走就算得手，活著的劫鏢者平分鏢價的八成。"
const TAG := "押鏢"

var view: Dictionary = {}
var list: VBoxContainer
var confirm_box: VBoxContainer

func dialog_size() -> Vector2:
	return Vector2(500, 0)

func _build_body() -> void:
	title_label.text = "劫鏢"
	UiBuild.muted(UiBuild.label(body, RULE_TEXT, 14, true))
	list = UiBuild.vbox(body, 4)
	list.name = "Targets"
	confirm_box = UiBuild.vbox(body, 6)
	confirm_box.name = "Confirm"

## 同房押鏢中的人（不含自己）
static func targets(v: Dictionary, my_char := "") -> Array:
	var out: Array = []
	for p in v.get("players", []):
		if not (p is Dictionary):
			continue
		if my_char != "" and str(p.get("char_id", "")) == my_char:
			continue
		var tags: Variant = p.get("tags", [])
		if tags is Array and (tags as Array).has(TAG):
			out.append(p)
	return out

## 本機能先擋的原因（"" ＝交給主機）：實戰不到 10 萬、城裡（不能 PK 的地區）、同隊、對方戰鬥中
static func block_reason(player: Dictionary, v: Dictionary, s: Dictionary) -> String:
	if int(s.get("combat_xp", 0)) < JiebiaoRules.MIN_COMBAT_XP:
		return "實戰不到十萬，還沒有劫鏢的本事。"
	if v.has("pk_allowed") and not bool(v.get("pk_allowed", true)):
		return "這裡不能動手。"
	if UiSocial.in_my_party(s, str(player.get("char_id", ""))):
		return "不能劫自己隊伍的鏢。"
	if bool(player.get("in_battle", false)):
		return "對方正在戰鬥中。"
	return ""

static func confirm_text(name: String) -> String:
	return "確定要劫%s的鏢？" % name

func open_list(v: Dictionary = {}) -> void:
	ensure_built()
	view = v if not v.is_empty() else UiClient.region_view()
	status_label.text = ""
	visible = true
	_render()

## 玩家選單「劫鏢」：直接到確認段
func open_for(player: Dictionary, v: Dictionary = {}) -> void:
	open_list(v)
	ask(player)

func apply_view(v: Dictionary) -> void:
	view = v
	if _built and visible:
		_render()

func _render() -> void:
	UiBuild.clear(list)
	clear_choices()
	var me := str(UiClient.sheet().get("char_id", ""))
	var i := 0
	for p in JiebiaoConfirm.targets(view, me):
		i += 1
		var row := UiBuild.hbox(list, 6)
		NumberedDialog.numbered_label(row, i)
		var nm := str(p.get("name", "?"))
		var l := UiBuild.label(row, nm + ("（戰鬥中）" if bool(p.get("in_battle", false)) else ""), 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pp: Dictionary = p
		var b := UiBuild.button(row, "劫鏢", func(): ask(pp), 70)
		b.name = "Rob_" + nm
		b.disabled = bool(p.get("in_battle", false))
		add_choice(b)
	if i == 0:
		UiBuild.muted(UiBuild.label(list, "這裡沒有押鏢的人。", 15))

func ask(player: Dictionary) -> void:
	UiBuild.clear(confirm_box)
	var nm := str(player.get("name", ""))
	if nm == "":
		return
	var why := JiebiaoConfirm.block_reason(player, view, UiClient.sheet())
	if why != "":
		status_label.text = why
		return
	var l := UiBuild.label(confirm_box, JiebiaoConfirm.confirm_text(nm), 16, true)
	l.name = "RobText"
	var row := UiBuild.hbox(confirm_box, 8)
	var ok := UiBuild.button(row, "劫鏢", Callable(), 90)
	ok.name = "RobOk"
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		ok.add_theme_color_override(k, UiTheme.JY_RED)
	var cid := str(player.get("char_id", ""))
	ok.pressed.connect(func(): send(UiKeys.I_ROB_ESCORT, { "target_char": cid }, [ok], close))
	var cancel := UiBuild.button(row, "取消", func(): UiBuild.clear(confirm_box), 90)
	NumberedDialog.focus_later(cancel)
