class_name RogueAllocPanel
extends PanelContainer
## 江湖試煉的屬性分配窗（ROGUE_PLAN §5.2 ALLOC、§5.3 屬性卡；WP-UI）。琥珀框（屬性窗）。
## 兩種用法：
## - 開局（with_identity = true）：七項＝擲骰值＋分配（＋／－）、剩餘點數、單項上限提示；名字、性別、造型；「重擲」「入陣」。
## - 屬性卡（with_identity = false）：七項＝目前屬性＋這張卡的點數；「確定」「取消」。
## 點數必須剛好分完才能確定（主機也會檢查：rogue_bad_alloc／rogue_attr_cap）。

signal confirmed(alloc: Dictionary)
signal rerolled
signal cancelled

var base: Dictionary = {}      # attr -> 擲骰值（或目前屬性）
var alloc: Dictionary = {}     # attr -> 這次分配的點數
var points := 0
var cap := UiKeys.ROGUE_ATTR_CAP
var with_identity := true

var title_label: Label
var remain_label: Label
var cap_label: Label
var value_labels: Dictionary = {}   # attr -> Label（「18 ＋2 ＝ 20」）
var plus_buttons: Dictionary = {}
var minus_buttons: Dictionary = {}
var identity_box: VBoxContainer
var name_edit: LineEdit
var gender_option: OptionButton
var look_option: OptionButton
var confirm_button: Button
var reroll_button: Button
var cancel_button: Button
var even_button: Button

func _init() -> void:
	add_theme_stylebox_override("panel", UiFrame.style(UiFrame.Kind.AMBER))
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(460, 0)
	_build()

func _build() -> void:
	var v := UiBuild.vbox(self, 8)
	title_label = UiBuild.title(v, "分配屬性")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var info := UiBuild.hbox(v, 12)
	remain_label = UiBuild.label(info, "", 18)
	remain_label.name = "Remain"
	remain_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap_label = UiBuild.muted(UiBuild.label(info, "", 15))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for a in UiKeys.ATTR_IDS:
		var n := UiBuild.accent(UiBuild.label(grid, UiKeys.ATTR_NAMES[a], 17))
		n.custom_minimum_size = Vector2(56, 0)
		var minus := UiBuild.button(grid, "－", func(): add(a, -1), 40)
		minus.name = "Minus_" + a
		minus_buttons[a] = minus
		var val := UiBuild.label(grid, "", 17)
		val.custom_minimum_size = Vector2(150, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_labels[a] = val
		var plus := UiBuild.button(grid, "＋", func(): add(a, 1), 40)
		plus.name = "Plus_" + a
		plus_buttons[a] = plus
	even_button = UiBuild.button(v, "平均分到臂力、根骨、機敏、膽識", spread_even)
	even_button.name = "Even"
	identity_box = UiBuild.vbox(v, 6)
	var nrow := UiBuild.hbox(identity_box, 8)
	UiBuild.label(nrow, "名字").custom_minimum_size = Vector2(56, 0)
	name_edit = UiBuild.line_edit(nrow, UiKeys.ROGUE_DEFAULT_NAME, UiKeys.ROGUE_DEFAULT_NAME, UiKeys.NAME_MAX_LEN)
	name_edit.name = "NameEdit"
	var grow := UiBuild.hbox(identity_box, 8)
	UiBuild.label(grow, "性別").custom_minimum_size = Vector2(56, 0)
	gender_option = OptionButton.new()
	gender_option.name = "Gender"
	gender_option.add_item(UiKeys.GENDER_LABELS["M"], 0)
	gender_option.add_item(UiKeys.GENDER_LABELS["F"], 1)
	gender_option.item_selected.connect(func(_i: int): _fill_looks())
	grow.add_child(gender_option)
	UiBuild.label(grow, "造型").custom_minimum_size = Vector2(48, 0)
	look_option = OptionButton.new()
	look_option.name = "Look"
	look_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grow.add_child(look_option)
	_fill_looks()
	var brow := UiBuild.hbox(v, 10)
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	reroll_button = UiBuild.button(brow, "重擲", func(): rerolled.emit(), 110)
	reroll_button.name = "Reroll"
	cancel_button = UiBuild.button(brow, "取消", func(): cancelled.emit(), 110)
	cancel_button.name = "Cancel"
	confirm_button = UiBuild.button(brow, "入陣", _on_confirm, 130)
	confirm_button.name = "Confirm"

func _fill_looks() -> void:
	var keep := look_option.selected if look_option.item_count > 0 else 0
	look_option.clear()
	var g := gender()
	for i in Looks.LOOK_MAX + 1:
		look_option.add_item(Looks.name_of(g, i), i)
	look_option.select(clampi(keep, 0, Looks.LOOK_MAX) if keep >= 0 else 0)

## base：七項起始值；pts：要分配的點數；cap_：單項上限；identity：開局（有名字、性別、造型、重擲）
func setup(p_base: Dictionary, pts: int, cap_: int, identity: bool) -> void:
	base = {}
	for a in UiKeys.ATTR_IDS:
		base[a] = UiBuild.num(p_base.get(a, 0))
	points = maxi(0, pts)
	cap = cap_ if cap_ > 0 else UiKeys.ROGUE_ATTR_CAP
	with_identity = identity
	alloc = {}
	for a in UiKeys.ATTR_IDS:
		alloc[a] = 0
	identity_box.visible = identity
	reroll_button.visible = identity
	cancel_button.visible = not identity
	confirm_button.text = "入陣" if identity else "確定"
	title_label.text = "分配屬性" if identity else "屬性 +%d：自由分配" % points
	refresh()

func used() -> int:
	var n := 0
	for a in alloc:
		n += int(alloc[a])
	return n

func remaining() -> int:
	return points - used()

func is_complete() -> bool:
	return remaining() == 0

func total(a: String) -> int:
	return int(base.get(a, 0)) + int(alloc.get(a, 0))

## d = ±1；成功回 true
func add(a: String, d: int) -> bool:
	if not alloc.has(a):
		return false
	var nv := int(alloc[a]) + d
	if nv < 0 or (d > 0 and remaining() <= 0) or (d > 0 and int(base.get(a, 0)) + nv > cap):
		return false
	alloc[a] = nv
	refresh()
	return true

## 把剩下的點數輪流加到臂力、根骨、機敏、膽識（到上限的跳過）
func spread_even() -> void:
	var order := ["str", "con", "agi", "guts", "wit", "cal", "luck"]
	var guard := 0
	while remaining() > 0 and guard < 1000:
		guard += 1
		var moved := false
		for a in order.slice(0, 4):
			if remaining() > 0 and add(a, 1):
				moved = true
		if not moved:
			for a in order:
				if remaining() > 0 and add(a, 1):
					moved = true
		if not moved:
			break
	refresh()

func refresh() -> void:
	var r := remaining()
	remain_label.text = "剩餘點數 %d" % r
	if r == 0:
		UiBuild.muted(remain_label)
	else:
		UiBuild.accent(remain_label)
	cap_label.text = "單項上限 %d" % cap
	for a in UiKeys.ATTR_IDS:
		var b := int(base.get(a, 0))
		var n := int(alloc.get(a, 0))
		(value_labels[a] as Label).text = "%d ＋%d ＝ %d" % [b, n, b + n] if n > 0 else "%d" % b
		(minus_buttons[a] as Button).disabled = n <= 0
		(plus_buttons[a] as Button).disabled = r <= 0 or b + n >= cap
	confirm_button.disabled = r != 0
	confirm_button.tooltip_text = "" if r == 0 else "屬性點要剛好分完。"
	even_button.disabled = r <= 0

func player_name() -> String:
	var n := name_edit.text.strip_edges()
	return n if n != "" else UiKeys.ROGUE_DEFAULT_NAME

func gender() -> String:
	return "F" if gender_option != null and gender_option.selected == 1 else "M"

func look() -> int:
	return maxi(0, look_option.selected)

## 送出用的分配（只放 > 0 的不夠直覺；主機要七項都在 → 全給）
func alloc_out() -> Dictionary:
	var out := {}
	for a in UiKeys.ATTR_IDS:
		out[a] = int(alloc.get(a, 0))
	return out

## 鍵盤 Enter（RogueScreen.handle_key）＝按「入陣／確定」
func confirm() -> void:
	_on_confirm()

func _on_confirm() -> void:
	if not is_complete():
		return
	confirmed.emit(alloc_out())
