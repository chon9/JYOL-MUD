extends Node
## 傳輸層與連線生命週期（TECH_ARCH 6、7、13.2）。UI 只透過 send_intent() 送出操作。
## SteamMultiplayerPeer 以 ClassDB.instantiate() 建立，GodotSteam 不存在時腳本仍可解析。

enum Mode { NONE, OFFLINE, ENET_HOST, ENET_CLIENT, STEAM_HOST, STEAM_CLIENT }

signal session_started(mode: Mode)
signal session_ended(reason: String)
signal status_changed(text: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

const ENET_DEFAULT_PORT := 24565
const ENET_MAX_CLIENTS := 8
const DEFAULT_WORLD := "default"

var mode: Mode = Mode.NONE
var dedicated := false
var status_text := "未連線"
var _intent_seq := 0
var _pending_world_id := ""
## M2_PLAN 4.6.9：上次「加入別人」的目標，給「重新連線」用：{ "mode": "ENET", "address", "port" } 或 { "mode": "STEAM", "lobby_id": int }
var last_target: Dictionary = {}
## 最近一次 session_ended 的原因（"host_closed"＝主機正常關閉、"server_disconnected"、"left"、"switching_lobby"…）
var last_end_reason := ""
## --stop-file=<絕對路徑>：主機每 1 秒檢查；檔案出現 → 刪檔 → 廣播 host_closing → 存檔離線 → quit(0)
var stop_file := ""
var _stop_check_left := 1.0
var _stopping := false
var _switching_lobby := false
const STOP_CHECK_S := 1.0
const STOP_GRACE_S := 0.5      # 廣播 host_closing 之後等一下再關 peer，讓封包送出去

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	SteamManager.lobby_hosted.connect(_on_lobby_hosted)
	SteamManager.lobby_entered.connect(_on_lobby_entered)
	SteamManager.lobby_error.connect(func(r: String): _set_status("Steam 大廳錯誤：" + r))
	if SteamManager.has_signal("join_requested"):
		SteamManager.join_requested.connect(_on_steam_join_requested)
	var args := CliArgs.current()
	dedicated = args.has("dedicated")
	if args.get("stop-file") is String and args["stop-file"] != "":
		stop_file = args["stop-file"]
		print("[NetworkManager] stop file: " + stop_file)

func _process(delta: float) -> void:
	if stop_file == "" or _stopping:
		return
	_stop_check_left -= delta
	if _stop_check_left > 0.0:
		return
	_stop_check_left = STOP_CHECK_S
	if is_host() and FileAccess.file_exists(stop_file):
		_stop_by_file()

## --stop-file 出現：刪檔 → 廣播 host_closing 並送出 → 等 0.5 秒 → leave()（WorldServer.stop 存檔）→ quit(0)
func _stop_by_file() -> void:
	_stopping = true
	DirAccess.remove_absolute(stop_file)
	print("[NetworkManager] stop file found, shutting down")
	if WorldServer.running:
		WorldServer.broadcast_event(Protocol.CH_SYSTEM, Protocol.E_HOST_CLOSING, {})
		WorldServer.flush()
	_flush_transport()
	await get_tree().create_timer(STOP_GRACE_S, true, false, true).timeout
	leave(true)
	get_tree().quit(0)

static func mode_name(m: Mode) -> String:
	return ["NONE", "OFFLINE", "ENET_HOST", "ENET_CLIENT", "STEAM_HOST", "STEAM_CLIENT"][m]

func is_active() -> bool:
	return mode != Mode.NONE

func is_host() -> bool:
	return mode in [Mode.OFFLINE, Mode.ENET_HOST, Mode.STEAM_HOST]

func _set_status(t: String) -> void:
	status_text = t
	print("[NetworkManager] " + t)
	status_changed.emit(t)

func _set_peer(peer: MultiplayerPeer, new_mode: Mode) -> void:
	var smp := multiplayer as SceneMultiplayer
	if smp:
		smp.server_relay = false   # 主機權威：客戶端之間不互傳（17 #11）
	multiplayer.multiplayer_peer = peer
	if smp:
		smp.server_relay = false
	mode = new_mode

## 依啟動參數決定傳輸（7.2）。回傳是否已經開始某種連線。
func start_from_args(args: Dictionary) -> bool:
	var world_id: String = str(args.get("world", DEFAULT_WORLD)) if args.get("world") is String else DEFAULT_WORLD
	if args.has("offline"):
		return start_offline(world_id) == OK
	if args.has("enet-host"):
		var port := int(str(args.get("port", ENET_DEFAULT_PORT))) if args.get("port") is String else ENET_DEFAULT_PORT
		return start_enet_host(world_id, port) == OK
	if args.get("enet-join") is String:
		var hp := CliArgs.split_host_port(args["enet-join"], ENET_DEFAULT_PORT)
		return start_enet_client(hp[0], hp[1]) == OK
	if args.has("steam-host"):
		return host_steam(world_id)
	return false

# ---------- 離線 ----------
func start_offline(world_id: String = DEFAULT_WORLD) -> Error:
	leave(true)
	_set_peer(OfflineMultiplayerPeer.new(), Mode.OFFLINE)   # unique id = 1, is_server() = true
	var err := WorldServer.start(world_id)
	if err != OK:
		_world_start_failed()
		return err
	if not dedicated:
		ClientState.begin_local_session()
	_set_status("單機模式：世界 %s%s" % [world_id, _world_note()])
	session_started.emit(mode)
	return OK

## ROGUE WP-RUN（ROGUE_PLAN §2.2）：江湖試煉＝離線＋記憶體內的試煉世界（WorldServer.start_rogue；不寫任何世界檔）
func start_rogue(seed: int = 0) -> Error:
	leave(true)
	_set_peer(OfflineMultiplayerPeer.new(), Mode.OFFLINE)
	var err := WorldServer.start_rogue(seed)
	if err != OK:
		_world_start_failed()
		return err
	if not dedicated:
		ClientState.begin_local_session()
	_set_status("江湖試煉")
	session_started.emit(mode)
	return OK

func _world_start_failed() -> void:
	leave(true)
	_set_status("無法開啟世界：" + WorldServer.last_error)

## 載入時用了備份等警告，附在狀態列後面（8.3）
func _world_note() -> String:
	return "（%s）" % WorldServer.last_warning if WorldServer.last_warning != "" else ""

# ---------- ENet ----------
func start_enet_host(world_id: String = DEFAULT_WORLD, port: int = ENET_DEFAULT_PORT) -> Error:
	leave(true)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, ENET_MAX_CLIENTS)
	if err != OK:
		_set_status("ENet 開房失敗（埠 %d）：%s" % [port, error_string(err)])
		return err
	_set_peer(peer, Mode.ENET_HOST)
	err = WorldServer.start(world_id)
	if err != OK:
		_world_start_failed()
		return err
	if not dedicated:
		ClientState.begin_local_session()
	_set_status("ENet 主機：埠 %d，世界 %s%s" % [port, world_id, _world_note()])
	session_started.emit(mode)
	return OK

func start_enet_client(address: String, port: int = ENET_DEFAULT_PORT) -> Error:
	leave(true)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		_set_status("ENet 連線失敗：%s" % error_string(err))
		return err
	_set_peer(peer, Mode.ENET_CLIENT)
	last_target = { "mode": "ENET", "address": address, "port": port }
	_set_status("正在連線 %s:%d ……" % [address, port])
	return OK   # 等 connected_to_server 再送 hello

# ---------- Steam ----------
func steam_ready() -> bool:
	return SteamManager.available and SteamManager.multiplayer_peer_available()

func host_steam(world_id: String = DEFAULT_WORLD, public := false) -> bool:
	if not steam_ready():
		_set_status("無法開 Steam 大廳：" + SteamManager.status_text())
		return false
	leave(true)
	_pending_world_id = world_id
	_set_status("正在建立 Steam 大廳 ……")
	SteamManager.host_lobby(public)   # 等 lobby_hosted
	return true

func _new_steam_peer() -> MultiplayerPeer:
	if not SteamManager.multiplayer_peer_available():
		return null
	return ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer

func _on_lobby_hosted(lobby_id: int) -> void:
	var peer := _new_steam_peer()
	if peer == null:
		SteamManager.leave_lobby()
		_end("steam_peer_missing")
		return
	var err: int = peer.call("create_host", 0)   # create_host(virtual_port = 0)
	if err != OK:
		SteamManager.leave_lobby()
		_end("steam_create_host_failed: %d" % err)
		return
	_set_peer(peer, Mode.STEAM_HOST)
	err = WorldServer.start(_pending_world_id)
	if err != OK:
		_world_start_failed()
		return
	if not dedicated:
		ClientState.begin_local_session()
	_set_status("Steam 主機：大廳 %d%s" % [lobby_id, _world_note()])
	session_started.emit(mode)

func _on_lobby_entered(lobby_id: int, owner_id: int) -> void:
	if owner_id == SteamManager.steam_id:
		return   # 自己是主機，已在 _on_lobby_hosted 處理
	if mode != Mode.NONE:
		leave(true, true)   # 收掉舊連線，但不要離開剛進入的大廳（舊大廳已由 SteamManager 離開）
	var peer := _new_steam_peer()
	if peer == null:
		SteamManager.leave_lobby()
		_end("steam_peer_missing")
		return
	var err: int = peer.call("create_client", owner_id, 0)   # create_client(host_steam_id, virtual_port = 0)
	if err != OK:
		SteamManager.leave_lobby()
		_end("steam_create_client_failed: %d" % err)
		return
	_set_peer(peer, Mode.STEAM_CLIENT)
	last_target = { "mode": "STEAM", "lobby_id": lobby_id }
	_set_status("已進入大廳 %d，正在連線主機 ……" % lobby_id)

## 遊戲中接受 Steam 邀請／好友清單「加入遊戲」（M2_PLAN 4.6.9）：先離開目前連線（主機會存檔），再加入新大廳。
## keep_lobby：舊大廳等新大廳進入成功後才由 SteamManager 離開
func _on_steam_join_requested(target_lobby_id: int) -> void:
	if target_lobby_id <= 0:
		return
	if mode != Mode.NONE:
		_switching_lobby = true
		leave(true, true)
		_switching_lobby = false
	_set_status("正在加入 Steam 大廳 %d ……" % target_lobby_id)
	SteamManager.join_lobby(target_lobby_id)

## 依 last_target 重新加入（斷線畫面的「重新連線」）；沒有目標回 ERR_UNCONFIGURED
func reconnect() -> Error:
	if last_target.is_empty():
		return ERR_UNCONFIGURED
	match str(last_target.get("mode", "")):
		"ENET":
			return start_enet_client(str(last_target.get("address", "")), int(last_target.get("port", ENET_DEFAULT_PORT)))
		"STEAM":
			if not steam_ready():
				_set_status("無法重新連線：" + SteamManager.status_text())
				return ERR_UNAVAILABLE
			var target_id := int(last_target.get("lobby_id", 0))
			if target_id <= 0:
				return ERR_UNCONFIGURED
			if mode != Mode.NONE:
				leave(true, true)
			_set_status("正在重新加入 Steam 大廳 %d ……" % target_id)
			SteamManager.join_lobby(target_id)
			return OK
	return ERR_UNCONFIGURED

# ---------- 連線事件 ----------
func _on_connected_to_server() -> void:
	_set_status("已連上主機（peer %d），送出 hello ……" % multiplayer.get_unique_id())
	ClientState.send_hello()          # 客戶端連上後第一件事
	session_started.emit(mode)

func _on_connection_failed() -> void:
	_set_status("連線失敗")
	_leave_client_lobby()
	_reset_peer()
	_end("connection_failed")

func _on_server_disconnected() -> void:
	var closed: bool = ClientState.host_closing
	_set_status("主機已離線，江湖凍結" if closed else "與主機斷線")
	_leave_client_lobby()
	_reset_peer()
	_end("host_closed" if closed else "server_disconnected")

func _leave_client_lobby() -> void:
	if mode == Mode.STEAM_CLIENT:
		SteamManager.leave_lobby()

func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		WorldServer.on_peer_connected(peer_id)   # 開始 5 秒 hello 計時
	peer_joined.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		WorldServer.on_peer_disconnected(peer_id)
	peer_left.emit(peer_id)

func identity_for_peer(peer_id: int, claimed: String) -> String:
	# Steam 模式下用 peer 回報的真實 SteamID，忽略客戶端自報值
	if mode == Mode.STEAM_HOST and multiplayer.multiplayer_peer.has_method("get_steam_id_for_peer_id"):
		var sid := int(multiplayer.multiplayer_peer.call("get_steam_id_for_peer_id", peer_id))
		return "steam_%d" % sid if sid > 0 else ""   # 查不到就給空字串，validate_hello 會拒絕
	return claimed   # ENet / 離線：信任本機設定檔的 local_<uuid>

func kick(peer_id: int, reason: String) -> void:
	ClientState.deliver_kick(peer_id, reason)
	get_tree().create_timer(0.5).timeout.connect(force_disconnect.bind(peer_id))

func force_disconnect(peer_id: int) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer and not (peer is OfflineMultiplayerPeer) and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		peer.disconnect_peer(peer_id)

func _exit_tree() -> void:
	leave(true)   # 關閉遊戲時存檔並關閉 peer，讓 SteamManager 能乾淨 steamShutdown

func _reset_peer() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

## keep_lobby：接受邀請進入新大廳時只收掉舊連線，不離開 SteamManager 目前的大廳
func leave(silent := false, keep_lobby := false) -> void:
	if mode == Mode.NONE and (keep_lobby or SteamManager.lobby_id == 0):
		return
	if WorldServer.running:
		WorldServer.stop()   # 會先廣播 host_closing、存檔
	_flush_transport()
	var peer := multiplayer.multiplayer_peer
	if peer and not (peer is OfflineMultiplayerPeer):
		peer.close()
	_reset_peer()
	if not keep_lobby:
		SteamManager.leave_lobby()
	ClientState.reset()
	if not silent:
		_set_status("已離開")
	_end("switching_lobby" if _switching_lobby else "left")

## 關 peer 前把已排入的封包送出去（ENet；否則 host_closing 可能跟著連線一起被丟掉）
func _flush_transport() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer and (peer as ENetMultiplayerPeer).host != null:
		(peer as ENetMultiplayerPeer).host.flush()

func _end(reason: String) -> void:
	mode = Mode.NONE
	last_end_reason = reason
	ClientState.reset()
	session_ended.emit(reason)

# ---------- Intent 入口（UI 只呼叫這個） ----------
func send_intent(kind: String, args: Dictionary = {}) -> int:
	_intent_seq += 1
	if mode == Mode.NONE:
		return -1
	if multiplayer.is_server():
		# 主機玩家與離線模式：本地短路，不走 RPC（6.4）
		WorldServer.handle_intent(multiplayer.get_unique_id(), _intent_seq, kind, args)
	else:
		WorldServer.c2s_intent.rpc_id(1, _intent_seq, kind, args)
	return _intent_seq
