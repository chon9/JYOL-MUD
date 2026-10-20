class_name CommandPanel
extends VBoxContainer
## 指令窗（Ctrl+4，AUTHENTIC_UI_SPEC §8.5）：6 個分頁 溝通／行動／武學／情感／組織／雜項（深褐底、棕黃字），
## 每頁 8 欄 × 4 列青銅方鈕（40×40，單字或雙字浮雕）；提示框黃底黑字。按一下執行，右鍵（或左鍵）拖到 F1–F8 熱鍵格。
## 指令表在 UiCommands；按下只發 command_invoked(id, button)，主畫面 run_command() 執行。
## 冷卻中（修煉內力、生活技能、野外的查看偵察）方鈕灰掉、鈕面變兩行「修煉／（7 秒）」（讀起來「修煉（7 秒）」；Button.text「修煉內力（7 秒）」給提示框），CooldownTracker 本機倒數。

signal command_invoked(id: String, button: Button)

const COLS := 8
const ROWS := 4
const BTN := Vector2(44, 44)
const BTN_MAX := 72.0
const GAP := 4

var tab_bar: TabBar
var grid: GridContainer
var hint_label: Label
var current_tab := "ACTION"
var buttons: Dictionary = {}     # id -> JyButton（目前頁）
var sheet: Dictionary = {}
var view: Dictionary = {}
var cooldowns := CooldownTracker.new()
var _shown_secs := [0, 0, 0]     # 上次畫上去的剩餘秒數 [meditate, life, scout]：變了才重刷（不是每幀）
var _built := false
var frame: PanelContainer
var btn_size := BTN                # 方鈕邊長：跟著框寬放大，8 欄剛好填滿黑框（審查 round 4：右邊空一條、提示下面空一段）

func _ready() -> void:
	ensure_built()

func ensure_built() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 6)
	tab_bar = TabBar.new()
	for t in UiCommands.TABS:
		tab_bar.add_tab(UiCommands.tab_label(t))
	tab_bar.current_tab = UiCommands.TABS.find(current_tab)
	tab_bar.tab_changed.connect(func(i: int): set_tab(UiCommands.TABS[i]))
	add_child(tab_bar)
	frame = UiBuild.framed(self, UiFrame.Kind.INK)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid = GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.add_child(grid)
	frame.resized.connect(_fit_buttons)
	hint_label = UiBuild.muted(UiBuild.label(self, "按一下執行；用滑鼠右鍵把指令拖到下方 F1–F8 熱鍵格。", 14, true))
	_rebuild()

func set_tab(tab: String) -> void:
	current_tab = tab
	if tab_bar != null and tab_bar.current_tab != UiCommands.TABS.find(tab):
		tab_bar.current_tab = UiCommands.TABS.find(tab)
	_rebuild()

func apply_sheet(s: Dictionary) -> void:
	sheet = s
	cooldowns.update(s)
	_refresh_states()

## 倒數的秒數變了才重刷（每秒一次，冷卻結束那一刻也算）；平常不動，免得把 IntentGate 送出中的鎖解開
func _process(_delta: float) -> void:
	if not _built or not is_visible_in_tree():
		return
	var now := _secs()
	if now != _shown_secs:
		_refresh_states()

func _secs() -> Array:
	return [cooldowns.left_s(CooldownTracker.KEY_MEDITATE), cooldowns.left_s(CooldownTracker.KEY_LIFE),
		cooldowns.left_s(CooldownTracker.KEY_SCOUT)]

func apply_view(v: Dictionary) -> void:
	view = v
	_refresh_states()

func _rebuild() -> void:
	if not _built:
		return
	UiBuild.clear(grid)
	buttons.clear()
	var ids: Array = [] if current_tab in UiCommands.LOCKED_TABS else UiCommands.ids_in_tab(current_tab)
	for i in COLS * ROWS:
		if i < ids.size():
			var id: String = ids[i]
			var b := UiBuild.jy_button(grid, JyButton.Style.BRONZE, UiCommands.label(id), Callable(), UiCommands.glyph(id))
			b.custom_minimum_size = btn_size
			b.drag_payload = Hotbar.CMD_PREFIX + id
			b.pressed.connect(func(): command_invoked.emit(id, b))
			buttons[id] = b
		else:
			var e := UiBuild.jy_button(grid, JyButton.Style.SLOT, "", Callable(), "")
			e.custom_minimum_size = btn_size
			e.disabled = true
			e.mouse_default_cursor_shape = Control.CURSOR_ARROW
			e.tooltip_text = UiCommands.LOCKED_TIP if current_tab in UiCommands.LOCKED_TABS else ""
	_refresh_states()

## 方鈕跟著框放大：寬度由框的內寬決定（8 欄剛好填滿），高度由框高決定、不超過寬度（不把視窗撐高）；最小 44
func _fit_buttons() -> void:
	if frame == null or grid == null:
		return
	var sb := frame.get_theme_stylebox("panel")
	var mx := sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT) if sb != null else 0.0
	var my := sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM) if sb != null else 0.0
	var w := clampf(floorf((frame.size.x - mx - GAP * (COLS - 1)) / COLS), BTN.x, BTN_MAX)
	var h := clampf(floorf((frame.size.y - my - GAP * (ROWS - 1)) / ROWS), BTN.y, w)
	if is_equal_approx(w, btn_size.x) and is_equal_approx(h, btn_size.y):
		return
	btn_size = Vector2(w, h)
	for c in grid.get_children():
		(c as Control).custom_minimum_size = btn_size

func _refresh_states() -> void:
	_shown_secs = _secs()
	for id in buttons:
		var b: JyButton = buttons[id]
		var why := UiCommands.unavailable_reason(id, sheet, view)
		var secs := cooldowns.left_s(CooldownTracker.key_for(id))
		var label := CooldownTracker.label(UiCommands.label(id), secs)
		var dis := why != "" or secs > 0
		if b.disabled != dis:
			b.disabled = dis
		if b.text != label:
			b.text = label
		b.set_cooldown_text(CooldownTracker.suffix(secs))
		b.tooltip_text = "%s　%s%s" % [label, UiCommands.tip(id), ("\n" + why) if why != "" else ""]
