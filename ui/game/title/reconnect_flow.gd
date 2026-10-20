class_name ReconnectFlow
extends Node
## 斷線後「重新連線」（M2_PLAN 4.10）：呼叫 NetworkManager.reconnect()（依 last_target 重新加入 ENet／Steam），
## 失敗就每 RETRY_DELAY_S 秒自動重試，最多 MAX_RETRIES 次；主機回 welcome 就成功（標題畫面接著切到角色選擇），
## 主機拒絕（例如被禁止）就停。測試可以換掉 reconnect_fn 並直接呼叫 on_* 模擬結果。

signal status(text: String)
signal finished(ok: bool)

const MAX_RETRIES := 3
const RETRY_DELAY_S := 5.0

var reconnect_fn: Callable = Callable()   # func() -> int（Error）；預設 NetworkManager.reconnect()
var attempts := 0
var running := false
var waiting := false                       # 已送出一次，等結果
var next_try_at := -1.0                    # 秒（_clock）；-1 = 沒排程
var _clock := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiClient.connect_signal("welcomed", _on_welcomed)
	UiClient.connect_signal("rejected", _on_rejected)
	var nm := UiClient._nm()
	if nm != null and nm.has_signal("session_ended"):
		nm.session_ended.connect(_on_session_ended)

func _exit_tree() -> void:
	UiClient.disconnect_signal("welcomed", _on_welcomed)
	UiClient.disconnect_signal("rejected", _on_rejected)
	var nm := UiClient._nm()
	if nm != null and nm.has_signal("session_ended") and nm.session_ended.is_connected(_on_session_ended):
		nm.session_ended.disconnect(_on_session_ended)

## 有沒有可以重新連線的目標
static func available() -> bool:
	var nm := UiClient._nm()
	return nm != null and nm.has_method("reconnect") and not UiClient.last_target().is_empty()

func start() -> void:
	attempts = 0
	running = true
	_try()

func cancel() -> void:
	running = false
	waiting = false
	next_try_at = -1.0

func _try() -> void:
	if not running:
		return
	attempts += 1
	next_try_at = -1.0
	status.emit("重新連線中……（第 %d 次）" % attempts)
	var err := _call_reconnect()
	if err != OK:
		on_failed("無法重新連線（%s）" % error_string(err))
		return
	waiting = true

func _call_reconnect() -> int:
	if reconnect_fn.is_valid():
		return int(reconnect_fn.call())
	var nm := UiClient._nm()
	if nm == null or not nm.has_method("reconnect"):
		return ERR_UNCONFIGURED
	return int(nm.call("reconnect"))

## 這一次失敗：還有次數就排下一次，否則結束
func on_failed(why: String) -> void:
	if not running:
		return
	waiting = false
	if attempts > MAX_RETRIES:
		running = false
		status.emit("%s。已重試 %d 次，請稍後再試。" % [why, MAX_RETRIES])
		finished.emit(false)
		return
	next_try_at = _clock + RETRY_DELAY_S
	status.emit("%s，%d 秒後重試（%d／%d）" % [why, int(RETRY_DELAY_S), attempts, MAX_RETRIES])

func on_succeeded() -> void:
	if not running:
		return
	running = false
	waiting = false
	status.emit("已重新連上主機。")
	finished.emit(true)

func _process(delta: float) -> void:
	_clock += delta
	if running and next_try_at >= 0.0 and _clock >= next_try_at:
		_try()

## 測試用：直接推進時間
func advance(secs: float) -> void:
	_process(secs)

func _on_welcomed(_info: Dictionary) -> void:
	if waiting:
		on_succeeded()

func _on_rejected(reason: String) -> void:
	if running:
		running = false
		waiting = false
		status.emit(UiSocial.reject_text(reason))
		finished.emit(false)

func _on_session_ended(reason: String) -> void:
	if waiting and reason != "left":
		on_failed("連不上主機")
