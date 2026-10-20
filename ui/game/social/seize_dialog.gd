class_name SeizeDialog
extends NumberedDialog
## 捉拿公敵（M3B_PLAN §7.8、§5.1.5；1.0B）：指令窗「雜項 → 捉拿公敵」列出同房可抓的人（view.players[].seizable），
## 玩家選單「捉拿」也走這裡的確認段。確認「確定要捉拿本派公敵 X？」→ seize_enemy { name }。
## 抓的人不加 PK 值、殺氣、善惡；對方可以逃（說明照 §5.1.5）。數字鍵 1–9 選第 n 個人。

const RULE_TEXT := "只能捉拿本派的公敵；抓人不加 PK 值、殺氣、善惡，可以找隊友幫忙。對方可以逃走；被打倒就押進大牢。"

var view: Dictionary = {}
var list: VBoxContainer
var confirm_box: VBoxContainer

func dialog_size() -> Vector2:
	return Vector2(480, 0)

func _build_body() -> void:
	title_label.text = "捉拿公敵"
	UiBuild.muted(UiBuild.label(body, RULE_TEXT, 14, true))
	list = UiBuild.vbox(body, 4)
	list.name = "Targets"
	confirm_box = UiBuild.vbox(body, 6)
	confirm_box.name = "Confirm"

## 同房可抓的人
static func targets(v: Dictionary) -> Array:
	var out: Array = []
	for p in v.get("players", []):
		if p is Dictionary and bool(p.get("seizable", false)):
			out.append(p)
	return out

## 確認句
static func confirm_text(name: String) -> String:
	return "確定要捉拿本派公敵%s？" % name

func open_list(v: Dictionary = {}) -> void:
	ensure_built()
	view = v if not v.is_empty() else UiClient.region_view()
	status_label.text = ""
	visible = true
	_render()

## 玩家選單「捉拿」：直接到確認段
func open_for(player: Dictionary, v: Dictionary = {}) -> void:
	open_list(v)
	ask(str(player.get("name", "")))

func apply_view(v: Dictionary) -> void:
	view = v
	if _built and visible:
		_render()

func _render() -> void:
	UiBuild.clear(list)
	clear_choices()
	var i := 0
	for p in SeizeDialog.targets(view):
		i += 1
		var row := UiBuild.hbox(list, 6)
		NumberedDialog.numbered_label(row, i)
		var nm := str(p.get("name", "?"))
		var l := UiBuild.label(row, nm + ("（戰鬥中）" if bool(p.get("in_battle", false)) else ""), 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := UiBuild.button(row, "捉拿", func(): ask(nm), 70)
		b.name = "Seize_" + nm
		b.disabled = bool(p.get("in_battle", false))
		add_choice(b)
	if i == 0:
		UiBuild.muted(UiBuild.label(list, "這裡沒有本派的公敵。", 15))

func ask(name: String) -> void:
	UiBuild.clear(confirm_box)
	if name == "":
		return
	var l := UiBuild.label(confirm_box, SeizeDialog.confirm_text(name), 16, true)
	l.name = "SeizeText"
	var row := UiBuild.hbox(confirm_box, 8)
	var ok := UiBuild.button(row, "捉拿", Callable(), 90)
	ok.name = "SeizeOk"
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		ok.add_theme_color_override(k, UiTheme.JY_RED)
	ok.pressed.connect(func(): send(UiKeys.I_SEIZE_ENEMY, { "name": name }, [ok], close))
	var cancel := UiBuild.button(row, "取消", func(): UiBuild.clear(confirm_box), 90)
	NumberedDialog.focus_later(cancel)
