class_name AutoWalker
extends Node
## 點擊趕路的介面驅動（M3C_PLAN §4.2）：狀態機在 AutoWalkCore（不依賴場景樹）；這裡負責計時、送 intent、轉發事件。
## 每步：core.next_step → 送 move（主機照常驗證，沒有新權限）→ 等 intent_result → 等房間 view 換到下一間 → 短暫停頓 → 下一步。
## 遇敵：暫停；戰鬥畫面收起後 0.5 秒依 §4.4 決定停或續走（續走選項 nav.auto_resume）。
## 停走一律寫原因（AutoWalkCore 的 MSG_*）；玩家取消、Esc、被移到意料外的房間時立刻停。

signal state_changed(walking: bool, text: String)

const STEP_DELAY_S := 0.32   # 一步停一下，讓地圖上的棋子看得到一格一格走（MapToken.MOVE_S）
const VIEW_TIMEOUT_S := 4.0
const RESUME_DELAY_S := 0.5
const WALKING_TEXT := "趕路中…"   # 舊名（沒有目的地名稱時的進度列）
const PAUSE_TEXT := "遇敵交戰中，趕路暫停。"
## M3c 第三輪審查：打贏、要續走時，等續走的那一下（預設 0.5 秒）不再留著「遇敵交戰中」——仗已經打完了
const RESUME_WAIT_TEXT := "戰鬥結束，稍後繼續趕路。"

var gate: IntentGate
var core := AutoWalkCore.new()
var view: Dictionary = {}       # 最新的房間 view（MapPanel 轉來）
var sheet: Dictionary = {}      # 最新的角色表（停走 #4、#5、#9）
var phase := ""                # "" | "result" | "view" | "delay" | "battle"
var deadline_ms := 0
var gen := 0                   # 每次送出或取消都 +1，舊回呼一律忽略
var last_text := ""
var step_delay_s := STEP_DELAY_S   # 測試可設 0
var resume_delay_s := RESUME_DELAY_S
var interrupted_by_battle := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	core.reason_text = func(code: String) -> String: return UiClient.reason_inline(code)

func is_walking() -> bool:
	return phase != ""

func target() -> String:
	return core.target() if is_walking() else ""

func remaining() -> int:
	return core.remaining() if is_walking() else 0

func remaining_rooms() -> Array:
	return core.remaining_rooms() if is_walking() else []

func configure(tables: Dictionary, graph: Dictionary, known: Dictionary) -> void:
	core.configure(tables, graph, known)

## 開始走：path 是 [{ dir, to }] 或 RoutePlanner.find_path 的房間清單；cur_room 是目前所在房間
func start(path: Array, cur_room: String, dest_name: String = "", note: String = "") -> void:
	if is_walking():
		stop("")
	if path.is_empty():
		return
	core.start(path, cur_room, dest_name, note)
	if not core.is_active():
		_emit(false, core.stop_reason)
		return
	interrupted_by_battle = false
	phase = "delay"
	_emit(true, progress_text())
	_send_next()

func progress_text() -> String:
	return core.progress_text() if core.dest_name != "" else WALKING_TEXT

## 停止；text 非空時顯示原因
func stop(text: String = AutoWalkCore.MSG_STOPPED) -> void:
	var was := is_walking()
	gen += 1
	phase = ""
	core.stop(text)
	interrupted_by_battle = false
	if was or text != "":
		_emit(false, text)

func _emit(walking: bool, text: String) -> void:
	last_text = text
	state_changed.emit(walking, text)

func _send_next() -> void:
	if phase == "":
		return
	if not UiClient.battle_state().is_empty():
		on_battle()
		return
	var act := core.next_step(view, sheet)
	match str(act.get("action", "")):
		"MOVE":
			if gate == null:
				stop("趕路中斷：無法送出指令。")
				return
			phase = "result"
			gen += 1
			var my_gen := gen
			deadline_ms = Time.get_ticks_msec() + int((UiKeys.INTENT_TIMEOUT_S + 1.0) * 1000.0)
			_emit(true, progress_text())
			gate.send(UiKeys.I_MOVE, { "dir": str(act.get("dir", "")) }, [], _on_result.bind(my_gen))
		"WAIT":
			if core.view_pending:
				phase = "view"
				deadline_ms = Time.get_ticks_msec() + int(VIEW_TIMEOUT_S * 1000.0)
		"ARRIVED":
			_finish(AutoWalkCore.MSG_ARRIVED)
		_:
			_finish(str(act.get("reason", AutoWalkCore.MSG_STOPPED)))

func _finish(text: String) -> void:
	gen += 1
	phase = ""
	interrupted_by_battle = false
	_emit(false, text)

func _on_result(ok: bool, reason: String, my_gen: int) -> void:
	if my_gen != gen or phase != "result":
		return
	core.on_move_result(ok, reason)
	if not ok:
		_send_next()   # → §4.4 #8 STOP「趕路中斷：…」
		return
	phase = "view"
	deadline_ms = Time.get_ticks_msec() + int(VIEW_TIMEOUT_S * 1000.0)
	_check_view()

## 由地圖面板在 region_changed 時呼叫
func on_view(v: Dictionary) -> void:
	view = v
	if not is_walking():
		return
	_check_view()

func _check_view() -> void:
	if phase == "battle":
		return   # 戰鬥中只記下 view（戰敗重生的位置等），收起後由 core.next_step 依 §4.4 判斷

	var before := core.remaining()
	core.observe(view)
	if core.arrived:
		_finish(AutoWalkCore.MSG_ARRIVED)
		return
	if not core.is_active():
		_finish(core.stop_reason)
		return
	if core.remaining() != before and phase in ["view", "result"]:
		phase = "delay"
		deadline_ms = Time.get_ticks_msec() + int(step_delay_s * 1000.0)
		_emit(true, progress_text())

## 由地圖面板在 battle_opened 時呼叫：趕路中被遇敵打斷 → 暫停（戰鬥畫面收起後 on_battle_end 決定）
func on_battle() -> void:
	if not is_walking() or phase == "battle":
		return
	gen += 1
	core.on_battle_start()
	phase = "battle"
	interrupted_by_battle = true
	_emit(true, PAUSE_TEXT)

## 戰鬥畫面收起：result 是該玩家的結算（VICTORY／DEFEAT／FLED／ALL_FLED／ABORTED）
func on_battle_end(result: String, resume_enabled: bool) -> void:
	if phase != "battle":
		return
	core.on_battle_end(result, resume_enabled)
	phase = "delay"
	deadline_ms = Time.get_ticks_msec() + int(resume_delay_s * 1000.0)
	if result == "VICTORY" and resume_enabled:
		_emit(true, RESUME_WAIT_TEXT)

func _process(_delta: float) -> void:
	if phase == "" or phase == "battle":
		return
	if Time.get_ticks_msec() < deadline_ms:
		return
	match phase:
		"delay":
			_send_next()
		"view":
			stop("趕路中斷：沒有收到房間資訊。")
		"result":
			stop("趕路中斷：主機沒有回應。")
