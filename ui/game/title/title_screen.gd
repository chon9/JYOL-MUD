extends UiScreen
## 標題畫面（M1_PLAN 3.12）：單機遊玩、區網開房／加入、Steam 開房、連線除錯。
## 連線開始且 ClientState.welcomed 後 → 角色選擇。
## M2（M2_PLAN 4.10）：
## - 斷線回來時顯示原因（主機關閉 →「主機已離線，江湖凍結」、被踢 → 原因）；有上次連線目標時多一顆「重新連線」
##   （ReconnectFlow：最多自動重試 3 次、間隔 5 秒）。
## - Steam 大廳：開房（可勾公開）、邀請好友、搜尋公開大廳並加入（協定版本不同的大廳灰掉）。

var world_edit: LineEdit
var addr_edit: LineEdit
var status_label: Label
var steam_label: Label
var msg_label: Label
var btn_offline: Button
var btn_enet_host: Button
var btn_enet_join: Button
var btn_steam_host: Button
var btn_debug: Button
var btn_reconnect: Button
var reconnect_label: Label
var reconnect: ReconnectFlow
var public_check: CheckBox
var btn_invite: Button
var btn_find: Button
var lobby_list: ItemList
var lobbies: Array = []
var disconnect_info: Dictionary = {}

func _ready() -> void:
	requires_session = false
	_build()
	var nm := _nm()
	if nm:
		nm.status_changed.connect(_on_status)
		status_label.text = nm.status_text
	UiClient.connect_signal("welcomed", _on_welcomed)
	UiClient.connect_signal("rejected", func(r: String): show_message(UiSocial.reject_text(r)))
	var sm := get_node_or_null("/root/SteamManager")
	if sm != null and sm.has_signal("lobby_list_received"):
		sm.lobby_list_received.connect(apply_lobbies)
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("take_disconnect_info"):
		disconnect_info = router.call("take_disconnect_info")
	show_message(take_router_message())
	refresh()

func _exit_tree() -> void:
	super._exit_tree()
	UiClient.disconnect_signal("welcomed", _on_welcomed)

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	# AUTHENTIC_UI_SPEC §14：玉石框、金色毛筆標題、音樂開關
	var frame := UiBuild.framed(center, UiFrame.Kind.JADE)
	var col := UiBuild.vbox(frame, 10)
	col.custom_minimum_size = Vector2(520, 0)
	var title := UiBuild.label(col, "金庸群俠傳 Mini OL", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UiTheme.JY_GOLD_LIGHT)
	title.add_theme_font_override("font", UiTheme.brush_font(0.5))
	title.add_theme_constant_override("outline_size", 4)
	title.add_theme_color_override("font_outline_color", UiTheme.JY_WOOD_DARK)
	var sub := UiBuild.muted(UiBuild.label(col, "JY-Mini OL　好友連線的武俠江湖", 18))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(HSeparator.new())

	var row := UiBuild.hbox(col)
	UiBuild.label(row, "世界名稱").custom_minimum_size = Vector2(90, 0)
	world_edit = UiBuild.line_edit(row, "default", "default", 32)
	btn_offline = UiBuild.button(col, "單機遊玩", _on_offline)
	btn_enet_host = UiBuild.button(col, "區網開房", _on_enet_host)
	var row2 := UiBuild.hbox(col)
	UiBuild.label(row2, "主機位址").custom_minimum_size = Vector2(90, 0)
	addr_edit = UiBuild.line_edit(row2, "127.0.0.1:24565", "127.0.0.1:24565", 64)
	btn_enet_join = UiBuild.button(col, "區網加入", _on_enet_join)
	var srow := UiBuild.hbox(col, 8)
	btn_steam_host = UiBuild.button(srow, "Steam 開房", _on_steam_host)
	btn_steam_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	public_check = CheckBox.new()
	public_check.text = "公開"
	public_check.tooltip_text = "公開大廳（別人可以用「搜尋大廳」找到）；不勾＝只有好友能加入"
	srow.add_child(public_check)
	btn_invite = UiBuild.button(srow, "邀請好友", _on_invite)
	btn_find = UiBuild.button(srow, "搜尋大廳", _on_find)
	steam_label = UiBuild.muted(UiBuild.label(col, "", 15, true))
	lobby_list = ItemList.new()
	lobby_list.custom_minimum_size = Vector2(0, 72)
	lobby_list.visible = false
	lobby_list.item_activated.connect(_on_lobby_activated)
	col.add_child(lobby_list)
	btn_reconnect = UiBuild.button(col, "重新連線", _on_reconnect)
	btn_reconnect.name = "Reconnect"
	reconnect_label = UiBuild.muted(UiBuild.label(col, "", 15, true))
	reconnect = ReconnectFlow.new()
	add_child(reconnect)
	reconnect.status.connect(func(t: String): reconnect_label.text = t)
	reconnect.finished.connect(func(_ok: bool): refresh())
	btn_debug = UiBuild.button(col, "連線除錯", func(): go("net_debug"))
	status_label = UiBuild.muted(UiBuild.label(col, "", 15, true))
	msg_label = UiBuild.label(col, "", 16, true)
	msg_label.add_theme_color_override("font_color", UiTheme.JY_ERROR_LIGHT)
	var music := CheckButton.new()
	music.text = "背景音樂"
	var bgm := get_node_or_null("/root/BgmPlayer")
	music.button_pressed = bool(bgm.get("enabled")) if bgm != null else true
	music.toggled.connect(func(on: bool):
		var b := get_node_or_null("/root/BgmPlayer")
		if b != null and b.has_method("set_music_enabled"):
			b.call("set_music_enabled", on))
	col.add_child(music)


func refresh() -> void:
	var nm := _nm()
	var steam_ok: bool = nm != null and nm.steam_ready()
	btn_steam_host.disabled = not steam_ok
	var sm0 := get_node_or_null("/root/SteamManager")
	btn_find.disabled = not steam_ok
	btn_invite.disabled = not (steam_ok and sm0 != null and int(sm0.get("lobby_id")) != 0)
	public_check.disabled = not steam_ok
	var can_re := ReconnectFlow.available() and bool(disconnect_info.get("can_reconnect", not disconnect_info.is_empty()))
	btn_reconnect.visible = can_re
	btn_reconnect.disabled = reconnect.running
	reconnect_label.visible = can_re or reconnect.running
	var sm := get_node_or_null("/root/SteamManager")
	if steam_ok:
		steam_label.text = ""
	elif sm:
		steam_label.text = "Steam 不可用：" + str(sm.status_text())
	else:
		steam_label.text = "Steam 不可用"

func show_message(t: String) -> void:
	if msg_label:
		msg_label.text = t

func world_id() -> String:
	var w := world_edit.text.strip_edges()
	return w if w != "" else "default"

func _on_offline() -> void:
	var nm := _nm()
	if nm == null:
		return
	if nm.start_offline(world_id()) != OK:
		show_message("無法開啟世界：" + str(nm.status_text))
		return
	_after_start()

func _on_enet_host() -> void:
	var nm := _nm()
	if nm == null:
		return
	if nm.start_enet_host(world_id(), nm.ENET_DEFAULT_PORT) != OK:
		show_message(str(nm.status_text))
		return
	_after_start()

func _on_enet_join() -> void:
	var nm := _nm()
	if nm == null:
		return
	var hp := CliArgs.split_host_port(addr_edit.text.strip_edges(), nm.ENET_DEFAULT_PORT)
	if nm.start_enet_client(hp[0], hp[1]) != OK:
		show_message(str(nm.status_text))
		return
	show_message("正在連線 %s:%d ……" % [hp[0], hp[1]])

func _on_steam_host() -> void:
	var nm := _nm()
	if nm and not nm.host_steam(world_id(), public_check.button_pressed):
		show_message(str(nm.status_text))

func _on_invite() -> void:
	var sm := get_node_or_null("/root/SteamManager")
	if sm == null or not sm.has_method("open_invite_overlay") or not sm.call("open_invite_overlay"):
		show_message("無法開啟 Steam 邀請視窗。")

func _on_find() -> void:
	var sm := get_node_or_null("/root/SteamManager")
	if sm == null or not sm.has_method("search_lobbies"):
		return
	lobby_list.visible = true
	lobby_list.clear()
	lobby_list.add_item("搜尋中……")
	lobby_list.set_item_disabled(0, true)
	sm.call("search_lobbies")

## lobbies = SteamManager.lobby_list_received：[{ id, name, proto, game, members }]；協定版本不同的灰掉、不能加入
func apply_lobbies(list: Array) -> void:
	lobbies = list
	lobby_list.visible = true
	lobby_list.clear()
	if list.is_empty():
		lobby_list.add_item("（沒有找到公開大廳）")
		lobby_list.set_item_disabled(0, true)
		return
	for l in list:
		var same := TitleLobby.compatible(l)
		var i := lobby_list.add_item(TitleLobby.label(l))
		lobby_list.set_item_disabled(i, not same)
		if not same:
			lobby_list.set_item_tooltip(i, "版本不符，不能加入")

func _on_lobby_activated(index: int) -> void:
	if index < 0 or index >= lobbies.size() or lobby_list.is_item_disabled(index):
		return
	var sm := get_node_or_null("/root/SteamManager")
	if sm != null and sm.has_method("join_lobby"):
		show_message("正在加入大廳……")
		sm.call("join_lobby", int(lobbies[index].get("id", 0)))

func _on_reconnect() -> void:
	show_message("")
	reconnect.start()
	refresh()

## 主機／離線：welcome 可能在 start 內同步送達
func _after_start() -> void:
	if UiClient.in_world():
		go("char_select")

func _on_welcomed(_info: Dictionary) -> void:
	go("char_select")

func _on_status(t: String) -> void:
	if status_label:
		status_label.text = t
	refresh()

## 大廳清單的文字與版本判斷（純函式）
class TitleLobby:
	static func compatible(l: Dictionary) -> bool:
		var proto := str(l.get("proto", str(Protocol.VERSION)))
		return proto == str(Protocol.VERSION)

	static func label(l: Dictionary) -> String:
		var t := "%s（%d 人）" % [str(l.get("name", "?")), int(l.get("members", 0))]
		return t if TitleLobby.compatible(l) else t + "　版本不符"
