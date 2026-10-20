class_name UiScreen
extends Control
## 遊戲畫面的共同基底：全螢幕宣紙底、IntentGate、斷線處理、安全的換畫面。

var gate: IntentGate
var bg: PanelContainer
## 需要連線的畫面：連線意外結束時回標題
var requires_session := true
var _leaving := false

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _enter_tree() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if bg == null:
		bg = PanelContainer.new()
		bg.name = "Bg"
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		move_child(bg, 0)
	if gate == null:
		gate = IntentGate.new()
		gate.name = "IntentGate"
		add_child(gate)
	var nm := _nm()
	if nm and not nm.session_ended.is_connected(_on_session_ended):
		nm.session_ended.connect(_on_session_ended)

func _exit_tree() -> void:
	var nm := _nm()
	if nm and nm.session_ended.is_connected(_on_session_ended):
		nm.session_ended.disconnect(_on_session_ended)

func _nm() -> Node:
	return get_node_or_null("/root/NetworkManager")

func _on_session_ended(reason: String) -> void:
	if not requires_session or reason == "left" or _leaving:
		return
	_leaving = true
	var router := get_node_or_null("/root/SceneRouter")
	if router:
		router.call_deferred("show_disconnected", "連線結束：" + reason)

## 換畫面一律延後一幀，避免在訊號處理中途釋放自己
func go(scene_name: String) -> void:
	if _leaving:
		return
	_leaving = true
	var router := get_node_or_null("/root/SceneRouter")
	if router:
		router.call_deferred("goto", scene_name)

func send(kind: String, args: Dictionary = {}, lock: Array = [], on_result: Callable = Callable()) -> int:
	return gate.send(kind, args, lock, on_result)

func take_router_message() -> String:
	var router := get_node_or_null("/root/SceneRouter")
	return router.take_message() if router else ""
