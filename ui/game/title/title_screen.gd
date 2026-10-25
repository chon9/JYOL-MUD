extends UiScreen
## 標題畫面（M1_PLAN 3.12）：單機遊玩、區網開房／加入、Steam 開房、連線除錯。
## 連線開始且 ClientState.welcomed 後 → 角色選擇。
## M2（M2_PLAN 4.10）：
## - 斷線回來時顯示原因（主機關閉 →「主機已離線，江湖凍結」、被踢 → 原因）；有上次連線目標時多一顆「重新連線」
##   （ReconnectFlow：最多自動重試 3 次、間隔 5 秒）。
## - Steam 大廳：開房（可勾公開）、邀請好友、搜尋公開大廳並加入（協定版本不同的大廳灰掉）。
## M3c2 WP-CARRY（M3C2_PLAN §5.3、§6.2）：
## - 右下角一行淡色小字：版本、連線協定、資料指紋（BuildInfo.line），跟朋友連線前互相對照。
## - 開房前可勾「允許外來角色」（存進該世界 options.json 的 allow_foreign_characters；預設跟著世界現有設定，新世界不勾）。
## - Steam 大廳清單的不相容列後面附主機的值（大廳資料有的才顯示）。

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
var foreign_check: CheckBox
var build_label: Label
const BUILD_TOOLTIP := "跟朋友連線前互相對照：協定與資料指紋都一樣才能連線。"
var btn_rogue: Button   # ROGUE WP-UI
const ROGUE_TOOLTIP := "肉鴿模式【設計提案・非原作】：每回合選一張卡，連戰到倒下為止；永久屬性點只用在試煉，不影響江湖裡的角色。"
const FOREIGN_TOOLTIP :="開房時接受朋友從別的世界帶來的角色（匯入時會檢查並截斷數值）。單機遊玩一律允許。"

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
	# ROGUE WP-UI（ROGUE_PLAN §5.1）：「江湖試煉」在「單機遊玩」同一列右邊
	var orow := UiBuild.hbox(col, 8)
	orow.name = "OfflineRow"
	btn_offline = UiBuild.button(orow, "單機遊玩", _on_offline)
	btn_offline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_rogue = UiBuild.button(orow, UiKeys.ROGUE_TITLE, _on_rogue, 150)
	btn_rogue.name = "RogueButton"
	btn_rogue.tooltip_text = ROGUE_TOOLTIP
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
	# M3c2 WP-CARRY §5.3：開房（區網、Steam）共用的「允許外來角色」
	var frow := UiBuild.hbox(col, 8)
	UiBuild.muted(UiBuild.label(frow, "開房選項", 15)).custom_minimum_size = Vector2(90, 0)
	foreign_check = CheckBox.new()
	foreign_check.name = "AllowForeign"
	foreign_check.text = "允許外來角色"
	foreign_check.tooltip_text = FOREIGN_TOOLTIP
	frow.add_child(foreign_check)
	# 主題的 CheckBox 字是亮色、底卻是按鈕的米色 → 改用按鈕的深色字（可讀性）
	var ink := foreign_check.get_theme_color("font_color", "Button")
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		foreign_check.add_theme_color_override(k, ink)
	world_edit.text_changed.connect(func(_t: String): load_foreign_choice())
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
	# M3c2 WP-CARRY §6.2：右下角版本列
	build_label = UiBuild.muted(UiBuild.label(null, build_line(), 13))
	build_label.name = "BuildInfoLine"
	build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	build_label.tooltip_text = BUILD_TOOLTIP
	build_label.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(build_label)
	build_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	build_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	build_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	load_foreign_choice()

## BuildInfo.line(GameData.content_hash)
static func build_line() -> String:
	var loop := Engine.get_main_loop() as SceneTree
	var gd: Node = loop.root.get_node_or_null("GameData") if loop != null else null
	return BuildInfo.line(str(gd.get("content_hash")) if gd != null else "")

## 勾選狀態跟著「世界名稱」那個世界的 options.json（沒有這個世界 → 不勾）
func load_foreign_choice() -> void:
	if foreign_check == null:
		return
	var sm := get_node_or_null("/root/SaveManager")
	var on := false
	if sm != null and sm.has_method("load_options"):
		var o: Variant = sm.call("load_options", world_id())
		on = o is Dictionary and (o as Dictionary).get("allow_foreign_characters", false) == true
	foreign_check.set_pressed_no_signal(on)

## 開房前把勾選告訴 WorldServer（start() 時存進 options.json）
func _apply_foreign_choice() -> void:
	var w := get_node_or_null("/root/WorldServer")
	if w != null and w.has_method("set_host_foreign_choice") and foreign_check != null:
		w.call("set_host_foreign_choice", foreign_check.button_pressed)


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

## ROGUE WP-UI（ROGUE_PLAN §5.1）：江湖試煉自己開主機（RogueScreen 的「開始試煉」），這裡只換畫面
func _on_rogue() -> void:
	go(UiKeys.ROGUE_SCENE)

func _on_enet_host() -> void:
	var nm := _nm()
	if nm == null:
		return
	_apply_foreign_choice()
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
	if nm:
		_apply_foreign_choice()
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
			lobby_list.set_item_tooltip(i, "版本不符，不能加入" + TitleLobby.host_values(l))

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
	## 協定相同，而且（大廳有公布資料指紋時）資料指紋也相同（M3c2 第二輪審查；舊主機沒有 fp → 只看協定）
	## my_fp 空 → 讀本機 GameData.content_hash
	static func compatible(l: Dictionary, my_fp := "") -> bool:
		var proto := str(l.get("proto", str(Protocol.VERSION)))
		if proto != str(Protocol.VERSION):
			return false
		var fp := BuildInfo.fingerprint12(str(l.get("fp", "")))
		if fp == "":
			return true
		var mine := my_fp if my_fp != "" else TitleLobby.local_fp()
		return mine == "" or BuildInfo.fingerprint12(mine) == fp

	static func local_fp() -> String:
		var loop := Engine.get_main_loop() as SceneTree
		var gd: Node = loop.root.get_node_or_null("GameData") if loop != null else null
		return BuildInfo.fingerprint12(str(gd.get("content_hash"))) if gd != null and gd.get("content_hash") != null else ""

	static func label(l: Dictionary) -> String:
		var t := "%s（%d 人）" % [str(l.get("name", "?")), int(l.get("members", 0))]
		return t if TitleLobby.compatible(l) else t + "　版本不符" + TitleLobby.host_values(l)

	## M3c2 §6.2：不相容的大廳後面附「（主機 v… 協定 … 資料 …）」——大廳資料有的值才顯示，都沒有回 ""
	static func host_values(l: Dictionary) -> String:
		var parts: Array = []
		var ver := str(l.get("version", l.get("ver", "")))
		if ver != "":
			parts.append("v" + ver)
		if str(l.get("proto", "")) != "":
			parts.append("協定 " + str(l["proto"]))
		var fp := str(l.get("fp", l.get("content_fp", "")))
		if fp != "":
			parts.append("資料 " + BuildInfo.fingerprint12(fp))
		return "" if parts.is_empty() else "（主機 %s）" % "　".join(parts)
