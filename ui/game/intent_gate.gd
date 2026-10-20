class_name IntentGate
extends Node
## 送出 intent 並鎖住按鈕，直到收到同 seq 的 intent_result（逾時 5 秒自動解鎖）（M1_PLAN 3.12 UI 規則）。
## 離線／主機模式的本地短路會在 send_intent() 內同步回 intent_result，所以先掛監聽再送。

signal finished(seq: int, kind: String, ok: bool, reason: String)

const REASON_TIMEOUT := "timeout"
const REASON_OFFLINE := "not_connected"

## seq -> { kind, lock: Array[Control], cb: Callable, deadline_ms: int }
var _pending: Dictionary = {}
var _sender: Callable = Callable()   # 測試可替換：func(kind, args) -> int

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiClient.connect_signal("intent_result", _on_intent_result)

func _exit_tree() -> void:
	UiClient.disconnect_signal("intent_result", _on_intent_result)
	for seq in _pending.keys():
		_unlock(_pending[seq].get("lock", []))
	_pending.clear()

func set_sender(cb: Callable) -> void:
	_sender = cb

func pending_count() -> int:
	return _pending.size()

func is_pending(kind: String) -> bool:
	for seq in _pending:
		if _pending[seq]["kind"] == kind:
			return true
	return false

## 回傳 seq；沒有連線時回 -1 並立刻以 not_connected 結束
func send(kind: String, args: Dictionary = {}, lock: Array = [], on_result: Callable = Callable()) -> int:
	var captured := {}
	var capture := func(s: int, ok: bool, reason: String) -> void:
		captured[s] = [ok, reason]
	var hooked := UiClient.connect_signal("intent_result", capture)
	var seq: int = _sender.call(kind, args) if _sender.is_valid() else _default_send(kind, args)
	if hooked:
		UiClient.disconnect_signal("intent_result", capture)
	if seq < 0:
		_finish_now(seq, kind, false, REASON_OFFLINE, on_result)
		return seq
	if captured.has(seq):
		_finish_now(seq, kind, captured[seq][0], captured[seq][1], on_result)
		return seq
	_lock(lock)
	_pending[seq] = { "kind": kind, "lock": lock, "cb": on_result,
		"deadline_ms": Time.get_ticks_msec() + int(UiKeys.INTENT_TIMEOUT_S * 1000.0) }
	return seq

func _default_send(kind: String, args: Dictionary) -> int:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or not loop.root.has_node("NetworkManager"):
		return -1
	return int(loop.root.get_node("NetworkManager").send_intent(kind, args))

func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var now := Time.get_ticks_msec()
	for seq in _pending.keys():
		if now >= int(_pending[seq]["deadline_ms"]):
			resolve(seq, false, REASON_TIMEOUT)

func _on_intent_result(seq: int, ok: bool, reason: String) -> void:
	if _pending.has(seq):
		resolve(seq, ok, reason)

## 由 intent_result 或逾時呼叫；測試也可直接呼叫
func resolve(seq: int, ok: bool, reason: String) -> void:
	if not _pending.has(seq):
		return
	var p: Dictionary = _pending[seq]
	_pending.erase(seq)
	_unlock(p["lock"])
	_finish_now(seq, p["kind"], ok, reason, p["cb"])

func _finish_now(seq: int, kind: String, ok: bool, reason: String, cb: Callable) -> void:
	if cb.is_valid():
		cb.call(ok, reason)
	finished.emit(seq, kind, ok, reason)

static func _lock(controls: Array) -> void:
	for c in controls:
		if is_instance_valid(c) and c is BaseButton:
			c.disabled = true

static func _unlock(controls: Array) -> void:
	for c in controls:
		if is_instance_valid(c) and c is BaseButton:
			c.disabled = false
