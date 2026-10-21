class_name ComboDialog
extends NumberedDialog
## 合體默契視窗（M3D_PLAN §3.3.4；1.0B；WP-COMBAT）：燈籠「默契」打開。
## - 有夥伴：夥伴名字、默契（0–100）、配合度（0–100）、下次扣點日；【培養感情】（配合度滿 100 才能按）、【取消默契】（再確認一次）；
## - 沒有夥伴：列出同房的其他玩家，各一顆【建立默契】→ combo_bond { target_char }；
## - 對方的請求（cb_bond_request，ui）：open_request → 【接受】【拒絕】→ combo_reply { from_char, accept }。
## 1.0A-only 世界（sheet.combo.era_on == false）只顯示「尚未開放」。數字鍵 1–9 按第 n 顆按鈕。

const RULE_TEXT := "兩人建立默契之後，一起作戰、在 3 秒內各出同一套合體武功，就有機會打出合體一擊；成功越多次配合度越高，配合度滿了可以「培養感情」加深默契。好些日子沒一起上線配合，配合度會慢慢掉。"
const ERA_OFF_TEXT := "這個世界還沒有開放神鵰大俠（1.0B）的內容，沒有合體技。"

var sheet: Dictionary = {}
var view: Dictionary = {}
var request: Dictionary = {}     # { from_char, from_name, until_ms }
var info: VBoxContainer
var list: VBoxContainer
var confirm_box: VBoxContainer
var countdown_label: Label = null   # 請求剩幾秒（M3d 審查）

func dialog_size() -> Vector2:
	return Vector2(520, 0)

func _build_body() -> void:
	title_label.text = UiKeys.COMBO_TITLE
	var rule := UiBuild.muted(UiBuild.label(body, RULE_TEXT, 14, true))
	rule.name = "Rule"
	info = UiBuild.vbox(body, 4)
	info.name = "Info"
	list = UiBuild.vbox(body, 4)
	list.name = "Actions"
	confirm_box = UiBuild.vbox(body, 6)
	confirm_box.name = "Confirm"

## sheet.combo：{ partner_name, partner_char, moqi, peihe, since_day, drain_day, next_drain_day, era_on }
static func combo_of(s: Dictionary) -> Dictionary:
	var c: Variant = s.get("combo", {})
	return c if c is Dictionary else {}

static func era_on(s: Dictionary) -> bool:
	var c := ComboDialog.combo_of(s)
	if c.has("era_on"):
		return c["era_on"] != false
	var eras: Variant = UiClient.world_info().get("enabled_eras", [])
	return eras is Array and (eras as Array).has(UiKeys.COMBO_ERA)

## 同房可以邀請的其他玩家
static func candidates(v: Dictionary, my_char: String) -> Array:
	var out: Array = []
	for p in v.get("players", []):
		if p is Dictionary and str(p.get("char_id", "")) != "" and str(p.get("char_id", "")) != my_char:
			out.append(p)
	return out

## 「默契 35／100　配合度 60／100　下次扣點：第 12 日」
static func status_line(c: Dictionary) -> String:
	var t := "默契 %d／100　配合度 %d／100" % [int(c.get("moqi", 0)), int(c.get("peihe", 0))]
	if int(c.get("next_drain_day", 0)) > 0:
		t += "　下次扣點：第 %d 日" % int(c["next_drain_day"])
	return t

func open_panel(s: Dictionary, v: Dictionary = {}) -> void:
	ensure_built()
	sheet = s
	view = v if not v.is_empty() else UiClient.region_view()
	status_label.text = ""
	visible = true
	_render()

func open_request(p: Dictionary, s: Dictionary, v: Dictionary = {}) -> void:
	request = { "from_char": str(p.get("from_char", "")), "from_name": str(p.get("from_name", "")),
		"until_ms": Time.get_ticks_msec() + int(float(p.get("ttl_s", 60)) * 1000.0) }
	open_panel(s, v)

func apply_sheet(s: Dictionary) -> void:
	sheet = s
	if _built and visible:
		_render()

func apply_view(v: Dictionary) -> void:
	view = v
	if _built and visible:
		_render()

func partner_name() -> String:
	return str(ComboDialog.combo_of(sheet).get("partner_name", ""))

func _render() -> void:
	UiBuild.clear(info)
	UiBuild.clear(list)
	UiBuild.clear(confirm_box)
	clear_choices()
	if not ComboDialog.era_on(sheet):
		UiBuild.muted(UiBuild.label(info, ERA_OFF_TEXT, 15, true))
		return
	if not request.is_empty() and Time.get_ticks_msec() > int(request.get("until_ms", 0)):
		request = {}
	if not request.is_empty():
		var rl := UiBuild.label(info, "%s想和你建立默契。" % str(request.get("from_name", "")), 16, true)
		rl.name = "RequestText"
		rl.add_theme_color_override("font_color", UiTheme.JY_SYS_YELLOW)
		var rr := UiBuild.hbox(info, 8)
		var yes := UiBuild.button(rr, "接受", func(): _reply(true), 90)
		yes.name = "Accept"
		var no := UiBuild.button(rr, "拒絕", func(): _reply(false), 90)
		no.name = "Refuse"
		add_choice(yes)
		add_choice(no)
		# M3d 審查：請求 60 秒後失效 → 接受／拒絕旁邊寫剩幾秒（_process 每秒更新）
		countdown_label = UiBuild.muted(UiBuild.label(rr, ComboDialog.left_text(request_left_s()), 14))
		countdown_label.name = "RequestLeft"
	else:
		countdown_label = null
	var c := ComboDialog.combo_of(sheet)
	var pn := partner_name()
	if pn != "":
		var pl := UiBuild.label(info, "合體夥伴：%s" % pn, 17)
		pl.name = "Partner"
		var sl := UiBuild.label(info, ComboDialog.status_line(c), 15)
		sl.name = "Status"
		var row := UiBuild.hbox(list, 8)
		var nb := UiBuild.button(row, UiKeys.COMBO_BTN_NURTURE, func(): send(UiKeys.I_COMBO_NURTURE, {}, []), 110)
		nb.name = "Nurture"
		nb.disabled = int(c.get("peihe", 0)) < 100
		nb.tooltip_text = "配合度滿 100 才能培養感情（默契 +5）" if nb.disabled else "默契 +5、配合度歸 0"
		add_choice(nb)
		var cb := UiBuild.button(row, UiKeys.COMBO_BTN_CANCEL, ask_cancel, 110)
		cb.name = "Cancel"
		add_choice(cb)
		return
	UiBuild.muted(UiBuild.label(info, "你還沒有合體夥伴。", 15))
	var i := 0
	var asking := str(request.get("from_char", ""))
	for p in ComboDialog.candidates(view, str(sheet.get("char_id", sheet.get("id", "")))):
		# M3d 審查：正在邀請你的人不再列一次「建立默契」（按了只會回 combo_request_pending）——用上面的接受／拒絕
		if asking != "" and str(p.get("char_id", "")) == asking:
			continue
		i += 1
		var r := UiBuild.hbox(list, 6)
		NumberedDialog.numbered_label(r, i)
		var nm := str(p.get("name", "?"))
		var busy := bool(p.get("in_battle", false))
		var l := UiBuild.label(r, nm + ("（戰鬥中）" if busy else ""), 16)   # M3d 審查：灰掉的原因寫出來（同劫鏢清單）
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cid := str(p.get("char_id", ""))
		var b := UiBuild.button(r, UiKeys.COMBO_BTN_BOND, func(): send(UiKeys.I_COMBO_BOND, { "target_char": cid }, []), 110)
		b.name = "Bond_" + nm
		b.disabled = busy
		if busy:
			b.tooltip_text = "對方正在戰鬥中，等他打完再說"
			UiBuild.muted(l)
		add_choice(b)
	if i == 0:
		UiBuild.muted(UiBuild.label(list, "這裡沒有別的玩家可以建立默契。", 15))

## 請求還剩幾秒（沒有請求 0）
func request_left_s() -> int:
	if request.is_empty():
		return 0
	return maxi(0, int(ceil((int(request.get("until_ms", 0)) - Time.get_ticks_msec()) / 1000.0)))

static func left_text(sec: int) -> String:
	return "（%d 秒內回覆）" % sec

func _process(_d: float) -> void:
	if not visible or request.is_empty() or countdown_label == null or not is_instance_valid(countdown_label):
		return
	var left := request_left_s()
	if left <= 0:
		request = {}
		_render()
		return
	var t := ComboDialog.left_text(left)
	if countdown_label.text != t:
		countdown_label.text = t

func ask_cancel() -> void:
	UiBuild.clear(confirm_box)
	var l := UiBuild.label(confirm_box, "確定要和%s解除默契？累積的默契會全部歸零。" % partner_name(), 16, true)
	l.name = "CancelText"
	var row := UiBuild.hbox(confirm_box, 8)
	var ok := UiBuild.button(row, UiKeys.COMBO_BTN_CANCEL, Callable(), 110)
	ok.name = "CancelOk"
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		ok.add_theme_color_override(k, UiTheme.JY_RED)
	ok.pressed.connect(func(): send(UiKeys.I_COMBO_CANCEL, {}, [ok], func(): UiBuild.clear(confirm_box)))
	var back := UiBuild.button(row, "算了", func(): UiBuild.clear(confirm_box), 90)
	NumberedDialog.focus_later(back)

func _reply(accept: bool) -> void:
	var from := str(request.get("from_char", ""))
	request = {}
	send(UiKeys.I_COMBO_REPLY, { "from_char": from, "accept": accept }, [])
	_render()
