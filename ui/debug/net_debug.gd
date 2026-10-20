extends Control
## 網路除錯畫面（TECH_ARCH 12 net_debug.tscn）：單機／ENet／Steam 開房、加入、邀請、搜尋與 RPC 聊天。
## UI 不寫 RPC，只讀 ClientState、只呼叫 NetworkManager.send_intent()。

const MAX_LINES := 500

var _status: Label
var _steam_label: Label
var _roster_label: Label
var _world_edit: LineEdit
var _addr_edit: LineEdit
var _public_check: CheckBox
var _lobby_list: ItemList
var _log: RichTextLabel
var _input: LineEdit
var _btn_offline: Button
var _btn_enet_host: Button
var _btn_enet_join: Button
var _btn_steam_host: Button
var _btn_invite: Button
var _btn_find: Button
var _btn_leave: Button
var _btn_ping: Button
var _btn_send: Button
var _btn_enter: Button
var _lines := 0
var _lobbies: Array = []

func _ready() -> void:
	_build_ui()
	NetworkManager.status_changed.connect(_on_status)
	NetworkManager.session_started.connect(func(_m): _refresh())
	NetworkManager.session_ended.connect(_on_session_ended)
	ClientState.events_received.connect(_on_events)
	ClientState.intent_result.connect(_on_intent_result)
	ClientState.welcomed.connect(_on_welcomed)
	ClientState.rejected.connect(func(r: String): _system("主機拒絕連線：" + r))
	ClientState.roster_changed.connect(_on_roster)
	WorldServer.warning.connect(func(t: String): _system("【主機警告】" + t))
	SteamManager.lobby_list_received.connect(_on_lobby_list)
	SteamManager.lobby_error.connect(func(r: String): _system("Steam 大廳錯誤：" + r))
	_status.text = NetworkManager.status_text
	var msg := SceneRouter.take_message()
	if msg != "":
		_system(msg)
	for e in ClientState.event_log.last(MAX_LINES):
		_append_event(e)
	_on_roster(ClientState.roster)
	_refresh()

# ---------- 版面 ----------
func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	bg.add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(360, 0)
	left.add_theme_constant_override("separation", 6)
	root.add_child(left)

	var title := Label.new()
	title.text = "江湖連線除錯（M0）"
	title.add_theme_font_size_override("font_size", 26)
	left.add_child(title)
	_steam_label = Label.new()
	_steam_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_steam_label)

	_world_edit = _labeled_edit(left, "世界名稱", "default")
	_btn_offline = _button(left, "單機遊玩", _on_offline)
	_btn_enet_host = _button(left, "開 ENet 主機（埠 %d）" % NetworkManager.ENET_DEFAULT_PORT, _on_enet_host)
	_addr_edit = _labeled_edit(left, "主機位址", "127.0.0.1:%d" % NetworkManager.ENET_DEFAULT_PORT)
	_btn_enet_join = _button(left, "加入 ENet 主機", _on_enet_join)
	left.add_child(HSeparator.new())
	_public_check = CheckBox.new()
	_public_check.text = "公開大廳（可被搜尋，測試用）"
	left.add_child(_public_check)
	_btn_steam_host = _button(left, "開 Steam 大廳", _on_steam_host)
	_btn_invite = _button(left, "邀請好友（Steam 覆蓋介面）", _on_invite)
	_btn_find = _button(left, "搜尋大廳", _on_find)
	_lobby_list = ItemList.new()
	_lobby_list.custom_minimum_size = Vector2(0, 110)
	_lobby_list.tooltip_text = "雙擊加入大廳"
	_lobby_list.item_activated.connect(_on_lobby_activated)
	left.add_child(_lobby_list)
	left.add_child(HSeparator.new())
	_btn_ping = _button(left, "Ping 主機", _on_ping)
	_btn_leave = _button(left, "離開", _on_leave)
	_btn_enter = _button(left, "進入江湖", _on_enter)   # M1：在世界中時進入角色選擇

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	root.add_child(right)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)
	_roster_label = Label.new()
	_roster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_roster_label)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_log)
	var row := HBoxContainer.new()
	right.add_child(row)
	_input = LineEdit.new()
	_input.placeholder_text = "千里傳音……（Enter 送出）"
	_input.max_length = Protocol.CHAT_MAX_LEN
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_t): _on_send())
	row.add_child(_input)
	_btn_send = _button(row, "送出", _on_send)

func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _labeled_edit(parent: Control, label: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	parent.add_child(row)
	return e

func _refresh() -> void:
	var active := NetworkManager.is_active()
	var steam_ok := NetworkManager.steam_ready()
	_steam_label.text = SteamManager.status_text() + ("" if steam_ok or not SteamManager.available else "（缺少 SteamMultiplayerPeer）")
	_btn_steam_host.disabled = not steam_ok
	_btn_find.disabled = not steam_ok
	_public_check.disabled = not steam_ok
	_btn_invite.disabled = not (steam_ok and SteamManager.lobby_id != 0)
	_btn_leave.disabled = not active
	_btn_ping.disabled = not ClientState.in_world
	_btn_send.disabled = not ClientState.in_world
	_btn_enter.disabled = not ClientState.in_world
	_input.editable = ClientState.in_world

# ---------- 按鈕 ----------
func _world_id() -> String:
	var w := _world_edit.text.strip_edges()
	return w if w != "" else NetworkManager.DEFAULT_WORLD

func _on_offline() -> void:
	NetworkManager.start_offline(_world_id())
	_refresh()

func _on_enet_host() -> void:
	NetworkManager.start_enet_host(_world_id(), NetworkManager.ENET_DEFAULT_PORT)
	_refresh()

func _on_enet_join() -> void:
	var hp := CliArgs.split_host_port(_addr_edit.text.strip_edges(), NetworkManager.ENET_DEFAULT_PORT)
	NetworkManager.start_enet_client(hp[0], hp[1])
	_refresh()

func _on_steam_host() -> void:
	NetworkManager.host_steam(_world_id(), _public_check.button_pressed)
	_refresh()

func _on_invite() -> void:
	if not SteamManager.open_invite_overlay():
		_system("目前沒有大廳可以邀請。")

func _on_find() -> void:
	_lobby_list.clear()
	_lobby_list.add_item("搜尋中……")
	SteamManager.search_lobbies()

func _on_lobby_list(lobbies: Array) -> void:
	_lobbies = lobbies
	_lobby_list.clear()
	if lobbies.is_empty():
		_lobby_list.add_item("（沒有找到公開大廳）")
	for l in lobbies:
		_lobby_list.add_item("%s（%d 人）" % [l.get("name", "?"), int(l.get("members", 0))])

func _on_lobby_activated(index: int) -> void:
	if index >= 0 and index < _lobbies.size():
		SteamManager.join_lobby(int(_lobbies[index]["id"]))

func _on_ping() -> void:
	NetworkManager.send_intent(Protocol.I_PING, { "nonce": Time.get_ticks_msec() })

func _on_leave() -> void:
	NetworkManager.leave()
	_refresh()

func _on_enter() -> void:
	if ClientState.in_world:
		SceneRouter.goto("char_select")

func _on_send() -> void:
	var t := _input.text.strip_edges()
	if t.is_empty() or not ClientState.in_world:
		return
	NetworkManager.send_intent(Protocol.I_CHAT, { "text": t })
	_input.clear()

# ---------- 訊號 ----------
func _on_status(t: String) -> void:
	_status.text = t
	_refresh()

func _on_session_ended(reason: String) -> void:
	if reason != "left":
		_system("連線結束：" + reason)
	_on_roster([])
	_refresh()

func _on_welcomed(info: Dictionary) -> void:
	_system("進入世界「%s」（era：%s）" % [info.get("world_name", ""), ", ".join(PackedStringArray(info.get("enabled_eras", [])))])
	_refresh()

func _on_roster(players: Array) -> void:
	var names: PackedStringArray = []
	for p in players:
		names.append("%s#%d" % [p.get("name", "?"), int(p.get("peer", 0))])
	_roster_label.text = "在線：%s" % ("、".join(names) if not names.is_empty() else "（無）")

func _on_intent_result(_seq: int, ok: bool, reason: String) -> void:
	if not ok:
		_system("操作被拒絕：" + reason)

func _on_events(batch: Array) -> void:
	for e in batch:
		_append_event(e)

func _append_event(e: Dictionary) -> void:
	_append_line(TextRenderer.render(e, ClientState.my_peer_id, GameData.tables.get("text_templates", {})))

func _system(text: String) -> void:
	_append_line("[color=#6b6156]%s[/color]" % TextRenderer.escape_bbcode(text))

func _append_line(bb: String) -> void:
	if _lines >= MAX_LINES:
		_log.remove_paragraph(0)
		_lines -= 1
	_log.append_text(bb + "\n")
	_lines += 1
