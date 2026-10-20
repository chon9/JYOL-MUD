class_name UiDialog
extends PanelContainer
## 對話框共同基底（AUTHENTIC_UI_SPEC §4、§8）：依 frame_kind() 套原作外框（玉石／琥珀／捲軸），
## 標題列是金色毛筆字＋右上 ⊠ 關閉鈕（可讀名稱「關閉」），內容區；由主畫面放在置中層。

signal closed

var gate: IntentGate
var title_label: Label
var body: VBoxContainer
var close_button: JyButton
var status_label: Label
var _built := false

func _ready() -> void:
	ensure_built()

func ensure_built() -> void:
	if _built:
		return
	_built = true
	add_theme_stylebox_override("panel", UiFrame.style(frame_kind()))
	if frame_kind() in [UiFrame.Kind.SCROLL, UiFrame.Kind.SCROLL_SMALL]:
		theme = UiTheme.paper()
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = dialog_size()
	var v := UiBuild.vbox(self, 8)
	var head := UiBuild.hbox(v, 8)
	title_label = UiBuild.title(head, "")
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button = UiBuild.close_button(head, "關閉", close)
	body = UiBuild.vbox(v, 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	status_label = UiBuild.error(UiBuild.label(v, "", 15, true))
	_build_body()

## 子類別覆寫：外框種類（UiFrame.Kind）
func frame_kind() -> int:
	return UiFrame.Kind.JADE

## 子類別覆寫
func dialog_size() -> Vector2:
	return Vector2(520, 0)

func _build_body() -> void:
	pass

func _gate() -> IntentGate:
	if gate == null:
		gate = IntentGate.new()
		add_child(gate)
	return gate

func send(kind: String, args: Dictionary, lock: Array = [], on_ok: Callable = Callable()) -> int:
	status_label.text = ""
	return _gate().send(kind, args, lock, func(ok: bool, reason: String):
		if not is_instance_valid(self):
			return
		if ok:
			if on_ok.is_valid():
				on_ok.call()
		else:
			status_label.text = UiClient.reason_inline(reason))

func close() -> void:
	visible = false
	closed.emit()
