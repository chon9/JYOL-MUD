extends Node
## Steam 初始化、callbacks、大廳（TECH_ARCH 2.1、7.3、13.1）。
## 不直接引用 `Steam` 識別字：GodotSteam 不存在時腳本仍可解析，一律經由 Engine.get_singleton()。

signal steam_initialized(ok: bool, reason: String)
signal lobby_hosted(lobby_id: int)                  # 主機：大廳建立成功
signal lobby_entered(lobby_id: int, owner_id: int)  # 任何人：進入大廳成功
signal lobby_error(reason: String)
signal lobby_list_received(lobbies: Array)
## 遊戲已開時接受邀請／好友清單「加入遊戲」（M2_PLAN 4.6.9）：NetworkManager 先離開目前連線再呼叫 join_lobby
signal join_requested(lobby_id: int)

const APP_ID := 480
const LOBBY_TAG_KEY := "game"
const LOBBY_TAG_VALUE := "jymini_v1"   # 過濾 480 上的垃圾大廳
const MAX_MEMBERS := 8

# Steamworks 列舉的整數值（17 #4、#7、#8 已對 4.23 核對：與 Steam.LOBBY_TYPE_* 等常數值相同）
const LOBBY_TYPE_PRIVATE := 0
const LOBBY_TYPE_FRIENDS_ONLY := 1
const LOBBY_TYPE_PUBLIC := 2
const LOBBY_COMPARISON_EQUAL := 0
const LOBBY_DISTANCE_FILTER_WORLDWIDE := 3
const RESULT_OK := 1
const CHAT_ROOM_ENTER_RESPONSE_SUCCESS := 1

var available := false
var init_status := -1        # -1 未嘗試；0 OK；1 其他失敗；2 Steam 沒開；3 用戶端過舊；10 外掛不存在；11 --no-steam
var init_reason := ""
var steam_id: int = 0
var persona_name := ""
var lobby_id: int = 0
var _steam: Object = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 暫停時回呼也不能停
	if "--no-steam" in OS.get_cmdline_user_args():
		_fail(11, "Steam disabled by --no-steam")
		return
	if not extension_loaded():
		_fail(10, "GodotSteam not loaded")
		return
	_steam = Engine.get_singleton("Steam")

	var res: Variant = _call_init()
	var status := 1
	var verbal := ""
	if res is Dictionary:
		status = int(res.get("status", 1))
		verbal = str(res.get("verbal", ""))
	if status != 0:
		_fail(status, "steamInitEx status=%d (%s)" % [status, verbal])
		return

	available = true
	init_status = 0
	steam_id = int(_steam.call("getSteamID"))
	persona_name = str(_steam.call("getPersonaName"))
	print("Steam OK: %s (%d)" % [persona_name, steam_id])

	_connect_signal("lobby_created", _on_lobby_created)
	_connect_signal("lobby_joined", _on_lobby_joined)
	_connect_signal("join_requested", _on_join_requested)
	_connect_signal("lobby_match_list", _on_lobby_match_list)
	steam_initialized.emit(true, "")
	_check_cold_start_invite()

static func extension_loaded() -> bool:
	return Engine.has_singleton("Steam") and ClassDB.class_exists("Steam")

static func multiplayer_peer_available() -> bool:
	return ClassDB.class_exists("SteamMultiplayerPeer") and ClassDB.can_instantiate("SteamMultiplayerPeer")

## 唯一的初始化路徑（2.1）。4.23：steamInitEx(app_id, embed_callbacks) -> {status, verbal}（17 #1 已驗證）
func _call_init() -> Variant:
	return _steam.call("steamInitEx", APP_ID, false)

func _connect_signal(sig: String, callable: Callable) -> void:
	if _steam.has_signal(sig):
		_steam.connect(sig, callable)
	else:
		push_warning("[SteamManager] signal missing: " + sig)

func _process(_delta: float) -> void:
	if available:
		_steam.call("run_callbacks")   # embed 已關閉，所以一定要自己呼叫

func _exit_tree() -> void:
	if not available:
		return
	var peer := multiplayer.multiplayer_peer
	if peer and peer.is_class("SteamMultiplayerPeer"):
		peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	leave_lobby()
	available = false
	_steam.call("steamShutdown")

func _fail(status: int, reason: String) -> void:
	available = false
	init_status = status
	init_reason = reason
	push_warning("[SteamManager] " + reason)
	steam_initialized.emit(false, reason)

## 給 UI 顯示的中文原因（7.3）
func status_text() -> String:
	match init_status:
		0: return "Steam 已連線：%s" % persona_name
		1: return "Steam 初始化失敗（其他原因）"
		2: return "Steam 沒有開啟"
		3: return "Steam 用戶端版本過舊"
		10: return "未載入 GodotSteam 外掛"
		11: return "已用 --no-steam 停用 Steam"
	return "Steam 尚未初始化"

# ---------- 建立大廳（主機） ----------
func host_lobby(public := false) -> void:
	if not available:
		lobby_error.emit("steam_unavailable")
		return
	_steam.call("createLobby", LOBBY_TYPE_PUBLIC if public else LOBBY_TYPE_FRIENDS_ONLY, MAX_MEMBERS)

func _on_lobby_created(connect_result: int, new_lobby_id: int) -> void:
	if connect_result != RESULT_OK:
		lobby_error.emit("createLobby failed: %d" % connect_result)
		return
	lobby_id = new_lobby_id
	if _steam.has_method("setLobbyJoinable"):
		_steam.call("setLobbyJoinable", lobby_id, true)
	_steam.call("setLobbyData", lobby_id, LOBBY_TAG_KEY, LOBBY_TAG_VALUE)
	_steam.call("setLobbyData", lobby_id, "proto", str(Protocol.VERSION))
	# M3c2 第二輪審查：大廳也公布版本與資料指紋（同協定、不同資料的大廳在清單上就灰掉，不必等握手才被拒）
	_steam.call("setLobbyData", lobby_id, "ver", BuildInfo.version())
	_steam.call("setLobbyData", lobby_id, "fp", my_fingerprint())
	_steam.call("setLobbyData", lobby_id, "name", "%s 的江湖" % persona_name)
	lobby_hosted.emit(lobby_id)

## 本機的資料指紋前 12 字（GameData.content_hash；沒有載入時 ""）
static func my_fingerprint() -> String:
	var loop := Engine.get_main_loop() as SceneTree
	var gd: Node = loop.root.get_node_or_null("GameData") if loop != null else null
	return BuildInfo.fingerprint12(str(gd.get("content_hash"))) if gd != null and gd.get("content_hash") != null else ""

# ---------- 加入大廳（客戶端） ----------
func join_lobby(target_lobby_id: int) -> void:
	if not available:
		lobby_error.emit("steam_unavailable")
		return
	_steam.call("joinLobby", target_lobby_id)

# lobby_joined(lobby_id, permissions, locked, response)
func _on_lobby_joined(joined_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		lobby_error.emit("joinLobby failed: %d" % response)
		return
	# 成功進入新大廳後才離開舊的（接受邀請時可能還在自己開的大廳或別人的大廳裡）
	if lobby_id != 0 and lobby_id != joined_id:
		_steam.call("leaveLobby", lobby_id)
	lobby_id = joined_id
	var owner_id := int(_steam.call("getLobbyOwner", joined_id))
	lobby_entered.emit(joined_id, owner_id)   # 主機自己也會收到；NetworkManager 會忽略

# 遊戲已開時，在 Steam 好友清單按「加入遊戲」或接受邀請（17 #6 已驗證：join_requested(lobby_id, steam_id)）
func _on_join_requested(requested_lobby_id: int, _friend_id: int) -> void:
	if join_requested.get_connections().is_empty():
		join_lobby(requested_lobby_id)   # 沒人處理（例如工具腳本）：照舊直接加入
	else:
		join_requested.emit(requested_lobby_id)

# 冷啟動：Steam 以 "+connect_lobby <id>" 啟動遊戲
func _check_cold_start_invite() -> void:
	var args := OS.get_cmdline_args()
	var i := args.find("+connect_lobby")
	if i != -1 and i + 1 < args.size():
		var id := args[i + 1].to_int()
		if id > 0:
			join_lobby.call_deferred(id)

func open_invite_overlay() -> bool:
	if available and lobby_id != 0:
		_steam.call("activateGameOverlayInviteDialog", lobby_id)
		return true
	return false

# 覆蓋介面打不開時的退路：遊戲內好友清單直接邀請（1.1、17 #25）
func invite_friend(friend_steam_id: int) -> bool:
	if available and lobby_id != 0 and _steam.has_method("inviteUserToLobby"):
		return bool(_steam.call("inviteUserToLobby", lobby_id, friend_steam_id))
	return false

func leave_lobby() -> void:
	if available and lobby_id != 0:
		_steam.call("leaveLobby", lobby_id)
	lobby_id = 0

# ---------- 搜尋（只會找到 PUBLIC 大廳；FRIENDS_ONLY 靠邀請或好友清單加入） ----------
func search_lobbies() -> void:
	if not available:
		lobby_error.emit("steam_unavailable")
		return
	_steam.call("addRequestLobbyListStringFilter", LOBBY_TAG_KEY, LOBBY_TAG_VALUE, LOBBY_COMPARISON_EQUAL)
	_steam.call("addRequestLobbyListStringFilter", "proto", str(Protocol.VERSION), LOBBY_COMPARISON_EQUAL)
	_steam.call("addRequestLobbyListDistanceFilter", LOBBY_DISTANCE_FILTER_WORLDWIDE)
	_steam.call("requestLobbyList")

func _on_lobby_match_list(lobbies: Array) -> void:
	var result: Array = []
	for id in lobbies:
		result.append({
			"id": int(id),
			"name": str(_steam.call("getLobbyData", id, "name")),
			"proto": str(_steam.call("getLobbyData", id, "proto")),
			"ver": str(_steam.call("getLobbyData", id, "ver")),
			"fp": str(_steam.call("getLobbyData", id, "fp")),
			"game": str(_steam.call("getLobbyData", id, LOBBY_TAG_KEY)),
			"members": int(_steam.call("getNumLobbyMembers", id)),
		})
	lobby_list_received.emit(result)

## 好友清單（遊戲內邀請用）。friend_flags 4 = immediate（一般好友）
func friends() -> Array:
	var out: Array = []
	if not available:
		return out
	var n := int(_steam.call("getFriendCount", 4))
	for i in n:
		var fid := int(_steam.call("getFriendByIndex", i, 4))
		out.append({ "id": fid, "name": str(_steam.call("getFriendPersonaName", fid)) })
	return out

func steam_id_string() -> String:
	return str(steam_id)
