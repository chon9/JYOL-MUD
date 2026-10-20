extends Node
## 切換主要畫面（TECH_ARCH 4.2 #7）。也負責全域主題與 --quit-after。

signal scene_changed(scene_name: String)

const SCENES := {
	"boot": "res://ui/boot/boot.tscn",
	"net_debug": "res://ui/debug/net_debug.tscn",
	"title": "res://ui/game/title/title_screen.tscn",
	"char_select": "res://ui/game/char/char_select.tscn",
	"char_create": "res://ui/game/char/char_create.tscn",
	"main": "res://ui/game/main/main_screen.tscn",
}

var current := ""
var pending_message := ""      # 下一個畫面要顯示的訊息（例如斷線原因）
## 最近一次斷線（M2_PLAN 4.10）：{ kind: HOST_CLOSED／KICKED／LOST／FAILED／OTHER, text, can_reconnect }；標題畫面讀它決定要不要顯示「重新連線」
var disconnect_info: Dictionary = {}
var _host_closing := false     # 收到主機的 host_closing 事件（之後的斷線＝主機關閉，江湖凍結）
var exit_code := 0             # --quit-after 到時的結束碼；bot 會改寫
var theme: Theme = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 按視窗右上角 X 時先走正常的離線流程（存檔、結束戰鬥、送出最後的畫面），再拆場景樹。
	# 自動接受關閉的話，ClientState 會先離開樹，NetworkManager._exit_tree 的存檔流程就送不出東西而報錯。
	get_tree().set_auto_accept_quit(false)
	theme = UiTheme.build()
	get_tree().root.theme = theme
	var args := CliArgs.current()
	if args.get("quit-after") is String:
		var secs := float(args["quit-after"])
		if secs > 0.0:
			get_tree().create_timer(secs, true, false, true).timeout.connect(func():
				print("[SceneRouter] --quit-after reached, exit %d" % exit_code)
				quit(exit_code))
	_hook_session_signals.call_deferred()

## 其他 Autoload（ClientState 在本節點之前、NetworkManager 也是）都建好之後才接訊號
func _hook_session_signals() -> void:
	var cs := get_node_or_null("/root/ClientState")
	if cs != null:
		if cs.has_signal("events_received") and not cs.events_received.is_connected(_on_events):
			cs.events_received.connect(_on_events)
		if cs.has_signal("welcomed") and not cs.welcomed.is_connected(_on_welcomed):
			cs.welcomed.connect(_on_welcomed)
	var nm := get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_signal("session_started") and not nm.session_started.is_connected(_on_session_started):
		nm.session_started.connect(_on_session_started)

func _on_events(batch: Array) -> void:
	for e in batch:
		if e is Dictionary and str(e.get("key", "")) == "host_closing":
			_host_closing = true

func _on_session_started(_mode: int) -> void:
	_host_closing = false

## 遊戲中接受 Steam 邀請（NetworkManager 先收掉舊連線再加入新大廳）：新世界的 welcome 到了，
## 人還在主畫面 → 換到角色選擇（標題與角色選擇畫面自己會處理 welcome）
func _on_welcomed(_info: Dictionary) -> void:
	if current == "main":
		pending_message = "已加入新的江湖。"
		goto("char_select")
func goto(scene_name: String) -> Error:
	if not SCENES.has(scene_name):
		push_error("[SceneRouter] unknown scene: " + scene_name)
		return ERR_DOES_NOT_EXIST
	current = scene_name
	var err := get_tree().change_scene_to_file(SCENES[scene_name])
	scene_changed.emit(scene_name)
	return err

## 斷線、被踢：離線後回標題畫面並顯示原因（M1_PLAN 3.12）。
## M2：主機關閉（收過 host_closing，或連線中途被主機斷開）顯示「主機已離線，江湖凍結」；被踢顯示原因；
## 有上次連線目標（NetworkManager.last_target）時標題畫面會出現「重新連線」。
func show_disconnected(message: String) -> void:
	disconnect_info = classify_disconnect(message, _host_closing)
	_host_closing = false
	pending_message = str(disconnect_info["text"])
	NetworkManager.leave(true)
	goto("title")

## 斷線訊息分類（純函式，測試用）
static func classify_disconnect(message: String, host_closing: bool) -> Dictionary:
	const KICK_PREFIX := "被主機請出："
	if message.begins_with(KICK_PREFIX):
		var reason := message.substr(KICK_PREFIX.length())
		return { "kind": "KICKED", "text": UiSocial.kick_text(reason), "can_reconnect": reason != "banned" }
	if host_closing or message.contains("server_disconnected"):
		return { "kind": "HOST_CLOSED", "text": UiSocial.HOST_FROZEN_TEXT, "can_reconnect": true }
	if message.contains("connection_failed"):
		return { "kind": "FAILED", "text": "連不上主機。", "can_reconnect": true }
	return { "kind": "OTHER", "text": message, "can_reconnect": true }

func take_disconnect_info() -> Dictionary:
	var d := disconnect_info
	disconnect_info = {}
	return d

func take_message() -> String:
	var m := pending_message
	pending_message = ""
	return m

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# 延到這一格結束才關：不能在主機處理到一半（例如正在開戰）時把世界拆掉
		quit.call_deferred(exit_code)

## 結束前先離線（主機會存檔），再結束程序。
## 審查修正：about_to_quit 讓 bot 在任何結束路徑都印出最後一行；quit_override >= 0 時改用它當結束碼
## （例：bot 還沒有結論就被要求以 0 結束 → 改成失敗，免得無聲結束看起來像通過）。
signal about_to_quit(code: int)
var quit_override := -1

func quit(code: int = 0) -> void:
	about_to_quit.emit(code)
	if quit_override >= 0:
		code = quit_override
	NetworkManager.leave(true)
	get_tree().quit(code)
