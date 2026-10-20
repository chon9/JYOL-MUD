extends Node
## 客戶端狀態鏡像（TECH_ARCH 4.2 #6、11.3、13.3）。主機 → 客戶端的 s2c_* RPC 只寫在這裡。

signal events_received(events: Array)
signal intent_result(seq: int, ok: bool, reason: String)
signal welcomed(world_info: Dictionary)
signal rejected(reason: String)
signal kicked(reason: String)
signal roster_changed(players: Array)
signal sheet_changed(sheet: Dictionary)
signal char_list_changed(list: Array)        # M1_PLAN 3.9.5
signal region_changed(view: Dictionary)      # 3.9.2
signal battle_opened(state: Dictionary)      # 3.9.3
signal battle_closed(result: Dictionary)     # 3.9.4
# M2_PLAN 4.6.9
signal mail_list_changed(list: Array)
signal server_options_changed(opts: Dictionary)
signal world_info_changed(info: Dictionary)
# 故事包（STORY_PLAN §4.14、§6）
signal dialogue_changed(d: Dictionary)          # 最近一次 dialogue 事件；{} = 對話關閉
signal rumors_changed(items: Array)             # rumor_list 事件的 items
signal villain_changed(prompts: Dictionary)     # wid -> villain_prompt payload（villain_clear 時移除）

const LOG_CAPACITY := 2000

## 測試用（M2_PLAN 4.6.9）：有效時，送往「非本地」peer 的 deliver_*（welcome、roster、rejected、events、result、sheet、
## char_list、view、battle_open、battle_close、kick）改成 capture_remote.call(peer_id, what, payload) 而不發 RPC。
## what："welcome" "roster" "rejected" "events" "result"（payload = { seq, ok, reason, extra }）"sheet" "char_list"
## "view" "battle_open" "battle_close" "kick"
var capture_remote: Callable = Callable()
var mail_list: Array = []            # 最近一次 mail_list 事件的 mails
var server_options: Dictionary = {}  # 最近一次 server_options 事件
## 收到 host_closing 之後為 true（NetworkManager 斷線時以 "host_closed" 結束連線；UI 顯示「主機已離線，江湖凍結」）
var host_closing := false

var event_log := EventLogBuffer.new(LOG_CAPACITY)   # 不要命名為 log，會遮蔽內建的 log()
var world_info: Dictionary = {}
var my_peer_id := 0
var in_world := false
var roster: Array = []
var sheet: Dictionary = {}
var display_name := ""
var identity := ""
var char_list: Array = []
var region_view: Dictionary = {}
var battle_state: Dictionary = {}            # battle_opened 時的快照；battle_closed 後清空
var last_battle_result: Dictionary = {}
var last_result_extra: Dictionary = {}       # 最近一個 intent_result 的附加欄位（busy → { left_s }）
var dialogue: Dictionary = {}                # 故事包：目前開著的任務對話（最近一次 dialogue 事件的 payload）
var rumors: Array = []                       # 故事包：最近一次 rumor_list 的 items
var villain_prompts: Dictionary = {}         # 故事包：wid -> villain_prompt payload

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func reset() -> void:
	world_info = {}
	in_world = false
	my_peer_id = 0
	roster = []
	sheet = {}
	char_list = []
	region_view = {}
	battle_state = {}
	last_battle_result = {}
	last_result_extra = {}
	mail_list = []
	server_options = {}
	host_closing = false
	dialogue = {}
	rumors = []
	villain_prompts = {}

## 本機身分：Steam 連線用 SteamID，ENet／離線用 local_<uuid>（6.2）；顯示名稱 Steam 可用時用暱稱
func resolve_identity() -> void:
	var args := CliArgs.current()
	var steam_mode: bool = NetworkManager.mode in [NetworkManager.Mode.STEAM_HOST, NetworkManager.Mode.STEAM_CLIENT]
	if steam_mode and SteamManager.available:
		identity = "steam_" + SteamManager.steam_id_string()
	else:
		identity = SaveManager.local_identity()
	if SteamManager.available:
		display_name = SteamManager.persona_name
	else:
		display_name = "俠客" + SaveManager.profile.capitalize() if SaveManager.profile != "default" else "俠客"
	if args.get("name") is String and args["name"] != "":
		display_name = args["name"]

# ---------- 主機端呼叫 ----------
## 主機玩家（離線、ENet 主機、Steam 主機）進入自己的世界
func begin_local_session() -> void:
	resolve_identity()
	WorldServer.register_local_player(identity, display_name)

## 客戶端連上後第一件事（6.2）
func send_hello() -> void:
	resolve_identity()
	WorldServer.c2s_hello.rpc_id(1, {
		"protocol": Protocol.VERSION,
		"game_version": Protocol.GAME_VERSION,
		"content_hash": GameData.content_hash,
		"identity": identity,
		"display_name": display_name,
	})

# ---------- 主機 → 客戶端：只有 authority（主機）能呼叫 ----------
## welcome = { world_info, your_characters[], your_peer_id }（6.2）
@rpc("authority", "call_remote", "reliable")
func s2c_welcome(welcome: Dictionary) -> void:
	_apply_welcome(welcome)

## 玩家名單（6.6）：players = [{ peer, name }]
@rpc("authority", "call_remote", "reliable")
func s2c_roster(players: Array) -> void:
	_apply_roster(players)

@rpc("authority", "call_remote", "reliable")
func s2c_rejected(reason: String) -> void:
	rejected.emit(reason)

@rpc("authority", "call_remote", "reliable")
func s2c_events(batch: Array) -> void:
	_apply_events(batch)

@rpc("authority", "call_remote", "reliable")
func s2c_sheet(new_sheet: Dictionary) -> void:
	_apply_sheet(new_sheet)

@rpc("authority", "call_remote", "reliable")
func s2c_char_list(list: Array) -> void:
	_apply_char_list(list)

@rpc("authority", "call_remote", "reliable")
func s2c_region_view(view: Dictionary) -> void:
	_apply_region_view(view)

@rpc("authority", "call_remote", "reliable")
func s2c_battle_open(state: Dictionary) -> void:
	_apply_battle_open(state)

@rpc("authority", "call_remote", "reliable")
func s2c_battle_close(result: Dictionary) -> void:
	_apply_battle_close(result)

## extra（附加欄位，可省略）：busy 時 { left_s }；舊主機不送就是 {}
@rpc("authority", "call_remote", "reliable")
func s2c_intent_result(seq: int, ok: bool, reason: String, extra: Dictionary = {}) -> void:
	_apply_result(seq, ok, reason, extra)

@rpc("authority", "call_remote", "reliable")
func s2c_kicked(reason: String) -> void:
	kicked.emit(reason)
	SceneRouter.show_disconnected("被主機請出：" + reason)

# ---------- 主機端：自己就本地處理，別人就 RPC（6.4 本地短路） ----------
func _is_local(peer_id: int) -> bool:
	return peer_id == multiplayer.get_unique_id()

## 測試擷取（capture_remote）：送往非本地 peer 的東西改交給測試；回傳是否已擷取
func _captured(peer_id: int, what: String, payload: Variant) -> bool:
	if not capture_remote.is_valid():
		return false
	var copy: Variant = payload.duplicate(true) if (payload is Dictionary or payload is Array) else payload
	capture_remote.call(peer_id, what, copy)
	return true

func deliver_welcome(peer_id: int, welcome: Dictionary) -> void:
	if not is_inside_tree():
		return   # 程式關閉中：已離開場景樹，送不出也不必送
	if _is_local(peer_id):
		_apply_welcome(welcome)
	elif not _captured(peer_id, "welcome", welcome):
		s2c_welcome.rpc_id(peer_id, welcome)

func deliver_roster(peer_id: int, players: Array) -> void:
	if not is_inside_tree():
		return   # 程式關閉中：已離開場景樹，送不出也不必送
	if _is_local(peer_id):
		_apply_roster(players.duplicate(true))
	elif not _captured(peer_id, "roster", players):
		s2c_roster.rpc_id(peer_id, players)

func deliver_rejected(peer_id: int, reason: String) -> void:
	if not is_inside_tree():
		return   # 程式關閉中：已離開場景樹，送不出也不必送
	if _is_local(peer_id):
		rejected.emit(reason)
	elif not _captured(peer_id, "rejected", reason):
		s2c_rejected.rpc_id(peer_id, reason)

func deliver_events(peer_id: int, batch: Array) -> void:
	if not is_inside_tree():
		return   # 程式關閉中：已離開場景樹，送不出也不必送
	if _is_local(peer_id):
		_apply_events(batch)
	elif not _captured(peer_id, "events", batch):
		s2c_events.rpc_id(peer_id, batch)

func deliver_result(peer_id: int, seq: int, ok: bool, reason: String, extra: Dictionary = {}) -> void:
	if not is_inside_tree():
		return   # 程式關閉中：已離開場景樹，送不出也不必送
	if _is_local(peer_id):
		_apply_result(seq, ok, reason, extra.duplicate(true))
	elif _captured(peer_id, "result", { "seq": seq, "ok": ok, "reason": reason, "extra": extra }):
		pass
	elif extra.is_empty():
		s2c_intent_result.rpc_id(peer_id, seq, ok, reason)
	else:
		s2c_intent_result.rpc_id(peer_id, seq, ok, reason, extra)

## 先記下這個結果的附加欄位再發訊號：收訊號的 UI 同步呼叫 UiClient.reason_text() 時就讀得到（busy 的剩餘秒數）
func _apply_result(seq: int, ok: bool, reason: String, extra: Dictionary) -> void:
	last_result_extra = extra
	intent_result.emit(seq, ok, reason)

func deliver_sheet(peer_id: int, new_sheet: Dictionary) -> void:
	if not is_inside_tree():
		return   # 程式關閉中：已離開場景樹，送不出也不必送
	if _is_local(peer_id):
		_apply_sheet(new_sheet.duplicate(true))
	elif not _captured(peer_id, "sheet", new_sheet):
		s2c_sheet.rpc_id(peer_id, new_sheet)

func deliver_char_list(peer_id: int, list: Array) -> void:
	if not is_inside_tree():
		return   # 程式關閉中：已離開場景樹，送不出也不必送
	if _is_local(peer_id):
		_apply_char_list(list.duplicate(true))
	elif not _captured(peer_id, "char_list", list):
		s2c_char_list.rpc_id(peer_id, list)

func deliver_region_view(peer_id: int, view: Dictionary) -> void:
	if not is_inside_tree():
		return   # 程式關閉中：已離開場景樹，送不出也不必送
	if _is_local(peer_id):
		_apply_region_view(view.duplicate(true))
	elif not _captured(peer_id, "view", view):
		s2c_region_view.rpc_id(peer_id, view)

func deliver_battle_open(peer_id: int, state: Dictionary) -> void:
	if not is_inside_tree():
		return   # 程式關閉中：已離開場景樹，送不出也不必送
	if _is_local(peer_id):
		_apply_battle_open(state.duplicate(true))
	elif not _captured(peer_id, "battle_open", state):
		s2c_battle_open.rpc_id(peer_id, state)

func deliver_battle_close(peer_id: int, result: Dictionary) -> void:
	if not is_inside_tree():
		return   # 程式關閉中：已離開場景樹，送不出也不必送
	if _is_local(peer_id):
		_apply_battle_close(result.duplicate(true))
	elif not _captured(peer_id, "battle_close", result):
		s2c_battle_close.rpc_id(peer_id, result)

func deliver_kick(peer_id: int, reason: String) -> void:
	if not is_inside_tree():
		return   # 程式關閉中：已離開場景樹，送不出也不必送
	if not _is_local(peer_id) and not _captured(peer_id, "kick", reason):
		s2c_kicked.rpc_id(peer_id, reason)

# ---------- 套用 ----------
func _apply_welcome(welcome: Dictionary) -> void:
	var info: Dictionary = welcome.get("world_info", {})
	world_info = info
	my_peer_id = int(welcome.get("your_peer_id", multiplayer.get_unique_id()))
	in_world = true
	var chars: Variant = welcome.get("your_characters", [])
	# 客戶端用主機給的 enabled_eras 與已展開的 rule_profile 建立同樣的視圖（5.5.4）
	if not multiplayer.is_server():
		GameData.activate(info.get("enabled_eras", ["1.0A"]), info.get("rule_profile", {}))
	welcomed.emit(info)
	_apply_char_list(chars if chars is Array else [])

## 蓋上本機收件時刻（CooldownTracker 用它算冷卻到期時刻；只在客戶端，不回送主機）
func _apply_sheet(new_sheet: Dictionary) -> void:
	new_sheet[CooldownTracker.RX_KEY] = Time.get_ticks_msec()
	sheet = new_sheet
	sheet_changed.emit(sheet)

func _apply_char_list(list: Array) -> void:
	char_list = list
	char_list_changed.emit(char_list)

func _apply_region_view(view: Dictionary) -> void:
	region_view = view
	region_changed.emit(region_view)

func _apply_battle_open(state: Dictionary) -> void:
	battle_state = state
	battle_opened.emit(battle_state)

func _apply_battle_close(result: Dictionary) -> void:
	last_battle_result = result
	battle_state = {}
	battle_closed.emit(result)

func _apply_roster(players: Array) -> void:
	roster = players
	roster_changed.emit(roster)

func _apply_events(batch: Array) -> void:
	var now := Time.get_ticks_msec()
	for e in batch:
		if not (e is Dictionary):
			continue
		var p: Dictionary = e.get("p", {}) if e.get("p") is Dictionary else {}
		match e.get("key", ""):
			Protocol.E_PONG:
				p["rtt_ms"] = maxi(0, now - int(p.get("nonce", now)))
			# ---- M2_PLAN 4.6.9 ----
			Protocol.E_PASSPORT:
				var pp := p.duplicate(true)
				pp.erase("peer")   # GameHost.tell 補上的收件 peer，不是護照的一部分
				# 只收目前這個世界的護照（主機送來的 world_id 決定存檔路徑；M2 第三輪審查）
				var cur_world := str(world_info.get("world_id", ""))
				if cur_world != "" and str(pp.get("world_id", "")) != cur_world:
					push_warning("[ClientState] passport for another world ignored: " + str(pp.get("world_id", "")))
				else:
					var err: Error = SaveManager.save_passport(str(pp.get("world_id", "")), str(pp.get("char_id", "")), pp)
					if err != OK:
						push_warning("[ClientState] passport save failed: " + SaveManager.last_error)
			Protocol.E_WORLD_INFO_CHANGED:
				var info: Variant = p.get("world_info", {})
				if info is Dictionary:
					world_info = info
					if not multiplayer.is_server():
						GameData.activate(info.get("enabled_eras", ["1.0A"]), info.get("rule_profile", {}))
					world_info_changed.emit(world_info)
			Protocol.E_MAIL_LIST:
				var mails: Variant = p.get("mails", [])
				mail_list = mails if mails is Array else []
				mail_list_changed.emit(mail_list)
			Protocol.E_SERVER_OPTIONS:
				server_options = p
				server_options_changed.emit(server_options)
			Protocol.E_HOST_CLOSING:
				host_closing = true
			# ---- 故事包（STORY_PLAN §4.14） ----
			Protocol.E_DIALOGUE:
				dialogue = p.duplicate(true)
				dialogue_changed.emit(dialogue)
			Protocol.E_DIALOGUE_CLOSE:
				if dialogue.is_empty() or str(dialogue.get("npc", "")) == str(p.get("npc", "")) or str(p.get("npc", "")) == "":
					dialogue = {}
					dialogue_changed.emit(dialogue)
			Protocol.E_RUMOR_LIST:
				var items: Variant = p.get("items", [])
				rumors = items if items is Array else []
				rumors_changed.emit(rumors)
			Protocol.E_VILLAIN_PROMPT:
				villain_prompts[str(p.get("wid", ""))] = p.duplicate(true)
				villain_changed.emit(villain_prompts)
			Protocol.E_VILLAIN_CLEAR:
				villain_prompts.erase(str(p.get("wid", "")))
				villain_changed.emit(villain_prompts)
		event_log.push(e)
	events_received.emit(batch)
