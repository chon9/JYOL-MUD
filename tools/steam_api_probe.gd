extends SceneTree
## 列出 GodotSteam 實際提供的方法、訊號、常數（TECH_ARCH 17）。godot --headless --path . --script res://tools/steam_api_probe.gd -- --no-steam
const METHODS := ["steamInitEx","steamInit","get_steam_init_result","run_callbacks","steamShutdown","getSteamID","getPersonaName","createLobby","setLobbyJoinable","setLobbyData","getLobbyData","joinLobby","getLobbyOwner","leaveLobby","inviteUserToLobby","activateGameOverlayInviteDialog","addRequestLobbyListStringFilter","addRequestLobbyListDistanceFilter","addRequestLobbyListResultCountFilter","requestLobbyList","getNumLobbyMembers","getFriendCount","getFriendByIndex","getFriendPersonaName","isSteamRunning","get_godotsteam_version"]
const SIGNALS := ["lobby_created","lobby_joined","join_requested","lobby_match_list","lobby_invite","persona_state_change"]
const CONSTS := ["LOBBY_TYPE_PRIVATE","LOBBY_TYPE_FRIENDS_ONLY","LOBBY_TYPE_PUBLIC","LOBBY_TYPE_INVISIBLE","CHAT_ROOM_ENTER_RESPONSE_SUCCESS","LOBBY_DISTANCE_FILTER_WORLDWIDE","LOBBY_DISTANCE_FILTER_DEFAULT","LOBBY_COMPARISON_EQUAL","RESULT_OK","STEAM_API_INIT_RESULT_OK","STEAM_API_INIT_RESULT_NO_STEAM_CLIENT","FRIEND_FLAG_IMMEDIATE"]
func _sig(cls: String, m: Dictionary) -> String:
	var a := []
	for x in m.args: a.append("%s:%s" % [x.name, type_string(x.type)])
	var d: Array = m.get("default_args", [])
	return "%s(%s)%s -> %s" % [m.name, ", ".join(a), (" defaults=%s" % [d]) if d.size() else "", type_string(m.return.type)]
func _init() -> void:
	print("has_singleton(Steam)=", Engine.has_singleton("Steam"), " class_exists=", ClassDB.class_exists("Steam"))
	print("SMP class_exists=", ClassDB.class_exists("SteamMultiplayerPeer"), " can_instantiate=", ClassDB.can_instantiate("SteamMultiplayerPeer"), " parent=", ClassDB.get_parent_class("SteamMultiplayerPeer"))
	var ml := {}
	for m in ClassDB.class_get_method_list("Steam", true): ml[m.name] = m
	for n in METHODS: print("M ", _sig("Steam", ml[n]) if ml.has(n) else n + " MISSING")
	var sl := {}
	for s in ClassDB.class_get_signal_list("Steam", true): sl[s.name] = s
	for n in SIGNALS:
		if sl.has(n):
			var a := []
			for x in sl[n].args: a.append("%s:%s" % [x.name, type_string(x.type)])
			print("S %s(%s)" % [n, ", ".join(a)])
		else: print("S ", n, " MISSING")
	for n in CONSTS:
		print("C ", n, "=", ClassDB.class_get_integer_constant("Steam", n) if ClassDB.class_has_integer_constant("Steam", n) else "MISSING")
	for m in ClassDB.class_get_method_list("SteamMultiplayerPeer", true): print("PM ", _sig("SteamMultiplayerPeer", m))
	for p in ClassDB.class_get_property_list("SteamMultiplayerPeer", true): print("PP ", p.name)
	print("PEER disconnect_peer=", ClassDB.class_has_method("SteamMultiplayerPeer","disconnect_peer",false), " _disconnect_peer=", ClassDB.class_has_method("SteamMultiplayerPeer","_disconnect_peer",true))
	print("version=", Engine.get_singleton("Steam").call("get_godotsteam_version"))
	quit(0)
