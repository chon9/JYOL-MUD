class_name MessageLog
extends Control
## 聊天／系統浮層（AUTHENTIC_UI_SPEC §9）：沒有底框，亮色字加黑描邊直接畫在畫面左上；左上藍色小圓鈕清除訊息。
## - RichTextLabel 顯示 TextRenderer.render()；最多 500 則；滾輪往上看更早的，5 秒沒操作自動回到最底。
## - 分頁拿掉，改成頻道開關（系統窗「頻道開關」）：13 個原作頻道；M2 起 8 個頻道有內容（CHANNEL_OF）；
##   江湖謠言 同時控制 HUD 右區系統訊息框（全服公告）。拍賣資訊、賭博頻道預設關。
## - 輸入列（頻道選擇鈕＋傳音入密的對象＋聊天輸入 ChatInput）在 HUD 中區最下列：主畫面呼叫 build_input(parent) 把它放進去。
##   M2_PLAN 4.10：發話頻道 千里傳音／傳音入密／輕聲細語／門派交談／組織交談／隊伍交談／江湖謠言（管理員多「天外飛仙」）；
##   預設輕聲細語【原作證實 §9.2】，記住上次選擇（settings.json 的 ui.talk_channel）。
## - 系統訊息框（HUD 右區）：build_announce(parent)；放公告性質的訊息（事件帶 announce／important、別人進入江湖，受「江湖謠言」開關控制）
##   和系統頻道的通知（【系統】【任務】、獲得物品、死亡重生…；左上浮層照樣也有），最多 4 行。
##   審查：只放公告時單機幾乎永遠是空的，HUD 右邊五分之一是一塊死黑框。
## intent_result 失敗時顯示 err_*（橘紅）。

const CHANNELS := ["千里傳音", "天外飛仙", "傳音入密", "門派交談", "組織交談", "隊伍交談", "輕聲細語",
	"拍賣資訊", "江湖謠言", "賭博頻道", "情話綿綿", "好友交談", "祈願天燈"]
const CHANNELS_OFF := ["拍賣資訊", "賭博頻道"]
## 原作 13 個頻道以外、本作新增的顯示頻道（只能在系統窗「頻道開關」關掉，不能發話）：
## 江湖傳聞＝系統【江湖傳聞】廣播（STORY_PLAN §6.3、CH_JIANGHU；【設計提案・非原作】），同時控制右下系統訊息框裡的傳聞
const EXTRA_CHANNELS := ["江湖傳聞"]
const RUMOR_CHANNEL := "江湖傳聞"
## 不能關的頻道：天外飛仙是系統與 GM 的訊息，原作「不能關閉」【已證實 17173 yinan/15】
const LOCKED_ON := ["天外飛仙"]
## 本作已有的發話頻道（其餘在選單裡灰色「尚未開放」）；天外飛仙只有管理員能用（ADMIN_TALK）
const TALK_CHANNELS := ["千里傳音", "傳音入密", "輕聲細語", "門派交談", "組織交談", "隊伍交談", "江湖謠言", "天外飛仙"]
const ADMIN_TALK := ["天外飛仙"]
## 說話要喝水的頻道（和主機 SocialSystem.WATER_CHANNELS 一致；M2_PLAN 5.4）：頻道選單與輸入框提示標「耗水」
const WATER_TALK := ["千里傳音", "輕聲細語", "門派交談", "組織交談", "隊伍交談", "江湖謠言"]
const WATER_TAG := "（耗水）"
const WATER_COLOR := Color("7fc8ff")
const DEFAULT_TALK := "輕聲細語"
const WHISPER := "傳音入密"
## 事件 ch → 原作頻道名（沒有對應的一律顯示）
const CHANNEL_OF := {
	"CHAT_WORLD": "千里傳音", "CHAT_WHISPER": "傳音入密", "CHAT_SAY": "輕聲細語", "CHAT_SECT": "門派交談",
	"CHAT_GUILD": "組織交談", "CHAT_PARTY": "隊伍交談", "CHAT_RUMOR": "江湖謠言", "GM": "天外飛仙",
	"JIANGHU": "江湖傳聞",
}
## 原作頻道名 → 發話用的 ch（M2_PLAN 4.1）
const TALK_CH := {
	"千里傳音": "CHAT_WORLD", "傳音入密": "CHAT_WHISPER", "輕聲細語": "CHAT_SAY", "門派交談": "CHAT_SECT",
	"組織交談": "CHAT_GUILD", "隊伍交談": "CHAT_PARTY", "江湖謠言": "CHAT_RUMOR", "天外飛仙": "GM",
}
const TALK_SETTING := "ui.talk_channel"
const ANNOUNCE_CHANNEL := "江湖謠言"
const ANNOUNCE_LINES := 4
const IDLE_RETURN_S := 5.0
const FONT_SIZE := 15

var gate: IntentGate
var text: RichTextLabel
var clear_button: JyButton
var input: LineEdit
var whisper_to: LineEdit              # 傳音入密的對象（角色名）；只在選了傳音入密時出現
var channel_button: MenuButton
var btn_send: Button                 # 舊介面相容：送出鈕（Enter 也會送）
var announce: RichTextLabel
var veil: TextureRect                # 文字底下由左上往外淡出的暗紗（和戰報一樣）
var entries: Array = []              # [{ ch, bb }]，最多 LOG_MAX_LINES
var announce_lines: Array = []      # [{ t, rumor, ch }]（ch：控制它的頻道開關名）
var channel_on: Dictionary = {}      # 頻道名 -> bool
var talk_channel := DEFAULT_TALK
var is_admin := false                # 管理員才能選「天外飛仙」（主畫面依 sheet.is_admin 設定）
var _last_wheel_ms := -1
var _built := false

func _ready() -> void:
	ensure_built()
	UiClient.connect_signal("events_received", _on_events)
	UiClient.connect_signal("intent_result", _on_intent_result)
	for e in UiClient.recent_events(UiKeys.LOG_MAX_LINES):
		if e is Dictionary:
			add_event(e)

func _exit_tree() -> void:
	UiClient.disconnect_signal("events_received", _on_events)
	UiClient.disconnect_signal("intent_result", _on_intent_result)

func ensure_built() -> void:
	if _built:
		return
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in CHANNELS + EXTRA_CHANNELS:
		channel_on[c] = not (c in CHANNELS_OFF)
	var saved: Variant = UiSettings.get_value("ui.channels", {})
	if saved is Dictionary:
		for c in saved:
			if channel_on.has(c):
				channel_on[c] = bool(saved[c])
	for c in LOCKED_ON:
		channel_on[c] = true   # 舊版 settings.json 可能存了「關」
	# 暗紗：主人畫的沙漠／草地很亮，橘、金色字只靠描邊看不清（審查 round 4：戰報有、聊天浮層沒有）；不吃滑鼠
	veil = TextureRect.new()
	veil.name = "Veil"
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 0.78])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.38), Color(0, 0, 0, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 1)
	gt.width = 128
	gt.height = 128
	veil.texture = gt
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_preset(Control.PRESET_TOP_LEFT)
	veil.visible = false
	add_child(veil)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.scroll_following = true
	text.selection_enabled = false
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.offset_left = 14
	text.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	text.add_theme_constant_override("outline_size", 3)
	text.add_theme_color_override("font_outline_color", UiTheme.OVERLAY_OUTLINE)
	text.add_theme_constant_override("line_separation", 1)
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	text.gui_input.connect(_on_text_input)
	add_child(text)
	UiBuild.left_scrollbar(text, self, 3.0, true)   # §9.1：左緣 6 px 細捲軸
	clear_button = UiBuild.jy_button(self, JyButton.Style.SEAL, "清除螢幕對話", clear, "清")
	clear_button.tint = Color("3a7ad8")
	clear_button.custom_minimum_size = Vector2(16, 16)
	clear_button.size = Vector2(16, 16)
	clear_button.position = Vector2(-2, -2)
	visible = UiSettings.get_bool("ui.chat_overlay")

## HUD 中區最下列：頻道選擇鈕（目前頻道名▾）＋傳音入密的對象＋單行聊天輸入（節點名 ChatInput，給 ui_playthrough 找）
func build_input(parent: Node) -> HBoxContainer:
	ensure_built()
	var row := UiBuild.hbox(parent, 4)
	channel_button = MenuButton.new()
	channel_button.name = "ChannelButton"
	channel_button.flat = false
	channel_button.focus_mode = Control.FOCUS_NONE
	channel_button.custom_minimum_size = Vector2(96, 22)
	channel_button.add_theme_font_size_override("font_size", 13)
	channel_button.tooltip_text = "頻道選擇"
	var pm := channel_button.get_popup()
	pm.about_to_popup.connect(_refresh_channel_menu)
	pm.id_pressed.connect(func(i: int): set_talk_channel(CHANNELS[i]))
	row.add_child(channel_button)
	_refresh_channel_menu()
	whisper_to = UiBuild.line_edit(row, "", "對象名字", UiKeys.NAME_MAX_LEN * 2)
	whisper_to.name = "WhisperTo"
	whisper_to.size_flags_horizontal = Control.SIZE_FILL
	whisper_to.custom_minimum_size = Vector2(88, 22)
	whisper_to.add_theme_font_size_override("font_size", 14)
	whisper_to.tooltip_text = "傳音入密的對象（角色名）"
	whisper_to.text_submitted.connect(func(_t): input.grab_focus())
	input = UiBuild.line_edit(row, "", "", 200)
	input.name = "ChatInput"
	input.custom_minimum_size = Vector2(0, 22)
	input.add_theme_font_size_override("font_size", 14)
	# HUD 中區最下列只有 22 px 高：輸入框、頻道鈕的內距縮小
	for e in [input, whisper_to]:
		for st in ["normal", "focus"]:
			var sb := ((e as LineEdit).get_theme_stylebox(st) as StyleBox).duplicate() as StyleBox
			sb.content_margin_top = 1
			sb.content_margin_bottom = 1
			(e as LineEdit).add_theme_stylebox_override(st, sb)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb2 := (channel_button.get_theme_stylebox(st) as StyleBox).duplicate() as StyleBox
		sb2.content_margin_top = 1
		sb2.content_margin_bottom = 1
		channel_button.add_theme_stylebox_override(st, sb2)
	input.text_submitted.connect(func(_t): _on_send())
	input.gui_input.connect(_on_input_key)
	whisper_to.gui_input.connect(_on_input_key)
	btn_send = UiBuild.button(row, "送出", _on_send)
	btn_send.visible = false
	var saved := str(UiSettings.get_value(TALK_SETTING, DEFAULT_TALK))
	set_talk_channel(saved, false)
	return row

## 頻道選單：只列發話頻道（2001 FAQ 的 8 個；其餘 5 個是後期的顯示頻道，只在系統窗「頻道開關」出現）。
## 耗水的標「（耗水）」；天外飛仙只有管理員能選。id = CHANNELS 的索引。
## M2 審查：13 項全列時 720p 要捲動，且看不出哪些頻道會扣水
func _refresh_channel_menu() -> void:
	if channel_button == null:
		return
	var pm := channel_button.get_popup()
	pm.clear()
	for i in CHANNELS.size():
		var c: String = CHANNELS[i]
		if not (c in TALK_CHANNELS):
			continue
		var ok := can_talk(c)
		var label := channel_label(c)
		if not ok:
			label = "%s（只限主機）" % c
		# 單選鈕：目前的發話頻道打勾（M2 審查：選單看不出目前是哪個頻道）
		pm.add_radio_check_item(label, i)
		var idx := pm.get_item_index(i)
		pm.set_item_disabled(idx, not ok)
		pm.set_item_checked(idx, c == talk_channel)
	if pm.visible or not channel_button.is_inside_tree():
		return
	# 開在頻道鈕的「上方」：MenuButton 預設開在下方，頻道鈕在畫面最下列，放不下時 Godot 把選單往上推、蓋住按鈕本身，
	# 放開滑鼠的那一下就選中了蓋在按鈕上的那一項（選單變成 8 項後實際發生：一點就切到江湖謠言）
	var top: Vector2 = channel_button.get_screen_position()
	var h := int(ceil(pm.get_contents_minimum_size().y))
	pm.position = Vector2i(int(top.x), maxi(0, int(top.y) - h))
	_place_channel_popup.call_deferred()

## 選單顯示後用實際大小再對齊一次（底邊貼頻道鈕上緣）
func _place_channel_popup() -> void:
	if channel_button == null or not channel_button.is_inside_tree():
		return
	var pm := channel_button.get_popup()
	if not pm.visible:
		return
	var top: Vector2 = channel_button.get_screen_position()
	pm.position = Vector2i(int(top.x), maxi(0, int(top.y) - pm.size.y))

## 頻道選單上的字：耗水頻道加「（耗水）」
static func channel_label(c: String) -> String:
	return c + WATER_TAG if c in WATER_TALK else c

func can_talk(c: String) -> bool:
	if not (c in TALK_CHANNELS):
		return false
	return is_admin or not (c in ADMIN_TALK)

func set_admin(on: bool) -> void:
	if is_admin == on:
		return
	is_admin = on
	_refresh_channel_menu()
	if not can_talk(talk_channel):
		set_talk_channel(DEFAULT_TALK, false)

## 切換發話頻道（remember：記到 settings.json，下次開遊戲沿用）
func set_talk_channel(c: String, remember := true) -> void:
	talk_channel = c if can_talk(c) else DEFAULT_TALK
	if remember:
		UiSettings.set_value(TALK_SETTING, talk_channel)
	if channel_button != null:
		channel_button.text = talk_channel + "▾"
		# 耗水頻道：頻道鈕的字染成水藍、提示寫明（M2 審查：輸入框的「（耗水）」一打字就看不到）
		var water := talk_channel in WATER_TALK
		if water:
			channel_button.add_theme_color_override("font_color", WATER_COLOR)
			channel_button.add_theme_color_override("font_hover_color", WATER_COLOR)
		else:
			channel_button.remove_theme_color_override("font_color")
			channel_button.remove_theme_color_override("font_hover_color")
		channel_button.tooltip_text = "頻道選擇（%s）" % ("這個頻道說話要喝水" if water else "說話不耗水")
		_refresh_channel_menu()
	if whisper_to != null:
		whisper_to.visible = talk_channel == WHISPER
	if input != null:
		input.placeholder_text = "%s……（Enter 送出）" % channel_label(talk_channel)

## 玩家選單「密語」：切到傳音入密、填好對象，游標放進聊天框
func start_whisper(to_name: String) -> void:
	set_talk_channel(WHISPER)
	if whisper_to != null:
		whisper_to.text = to_name
	if input != null and input.is_inside_tree():
		input.grab_focus()

## 組成 chat 的參數（M2_PLAN 4.1）：千里傳音不帶 ch（和 M0／net_smoke 相同）；傳音入密帶 to；
## 回傳 {} 表示不送（空字、傳音入密沒有對象）
func chat_args(t: String) -> Dictionary:
	t = t.strip_edges()
	if t.is_empty():
		return {}
	var ch: String = TALK_CH.get(talk_channel, UiKeys.CH_CHAT_SAY)
	var args := { "text": t }
	if ch != UiKeys.CH_CHAT_WORLD:
		args["ch"] = ch
	if ch == UiKeys.CH_CHAT_WHISPER:
		var to := whisper_to.text.strip_edges() if whisper_to != null else ""
		if to == "":
			return {}
		args["to"] = to
	return args

## HUD 右區：系統訊息框（INK 框、黃字、最多 4 行）
func build_announce(parent: Node) -> RichTextLabel:
	ensure_built()
	var frame := UiBuild.framed(parent, UiFrame.Kind.INK)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	announce = RichTextLabel.new()
	announce.bbcode_enabled = true
	# 長訊息會換行：超出 4 行高時捲到最新一行（捲軸不顯示）
	announce.scroll_active = true
	announce.scroll_following = true
	announce.get_v_scroll_bar().modulate = Color(1, 1, 1, 0)
	announce.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
	announce.fit_content = false
	announce.add_theme_color_override("default_color", UiTheme.JY_SYS_YELLOW)
	announce.add_theme_font_size_override("normal_font_size", 14)
	announce.size_flags_vertical = Control.SIZE_EXPAND_FILL
	announce.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(announce)
	# 長訊息換行後最上一行被框切半（審查 round 4）：捲到底、只露整行
	announce.resized.connect(func(): UiBuild.stick_whole_lines.call_deferred(announce))
	_render_announce()
	return announce

## Esc：放開聊天框焦點（否則 M 等快捷鍵會一直打進聊天框）
func _on_input_key(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		if f is LineEdit:
			(f as LineEdit).release_focus()
			(f as LineEdit).accept_event()

func _on_text_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_last_wheel_ms = Time.get_ticks_msec()

## 5 秒沒捲動就回到最底
func _process(_delta: float) -> void:
	if _last_wheel_ms >= 0 and Time.get_ticks_msec() - _last_wheel_ms > int(IDLE_RETURN_S * 1000.0):
		_last_wheel_ms = -1
		_stick_bottom()

func _gate() -> IntentGate:
	if gate == null:
		gate = IntentGate.new()
		add_child(gate)
	return gate

# ---------------------------------------------------------------- 頻道

func set_channel_enabled(c: String, on: bool) -> void:
	if not channel_on.has(c) or c in LOCKED_ON:
		return
	channel_on[c] = on
	UiSettings.set_value("ui.channels", channel_on.duplicate())
	_rerender()
	_render_announce()

func channel_enabled(c: String) -> bool:
	return bool(channel_on.get(c, true))

func _visible_ch(ch: String) -> bool:
	var c: String = CHANNEL_OF.get(ch, "")
	return c == "" or channel_enabled(c)

## 公告性質：事件帶 announce／important，或別人進入江湖
func is_announcement(e: Dictionary) -> bool:
	var p: Variant = e.get("p", {})
	if bool(e.get("announce", false)) or (p is Dictionary and bool((p as Dictionary).get("announce", false))):
		return true
	if TextRenderer.is_important(e):
		return true
	return str(e.get("key", "")) == UiKeys.E_CHAR_ENTERED and p is Dictionary and int((p as Dictionary).get("peer", -1)) != UiClient.my_peer()

# ---------------------------------------------------------------- 訊息

## 只進聊天紀錄、不進右下系統訊息框的系統事件：開關的結果本身就看得到（開關的狀態），再在三個地方各報一次太吵
## （M2 審查：「接受組隊邀請：關。」同時出現在面板回饋列、左上浮層、右下系統框）
const QUIET_SYSTEM_KEYS := ["pref_changed"]

static func is_quiet_system(e: Dictionary) -> bool:
	return str(e.get("key", "")) in QUIET_SYSTEM_KEYS

func add_event(e: Dictionary) -> void:
	if str(e.get("key", "")) == UiKeys.E_RUMOR:
		add_rumor(e.get("p", {}) if e.get("p", {}) is Dictionary else {})
		return
	var bb := TextRenderer.render(e, UiClient.my_peer(), UiClient.templates())
	if bb == "":
		return
	var rumor := is_announcement(e)
	if rumor or (str(e.get("ch", "")) == UiKeys.CH_SYSTEM and not is_quiet_system(e)):
		add_announcement(TextRenderer.strip_channel_tag(TextRenderer.render_plain(e, UiClient.my_peer(), UiClient.templates())), rumor)
	_push(str(e.get("ch", "")), bb)

func add_system(t: String) -> void:
	if t == "":
		return
	_push(UiKeys.CH_SYSTEM, "[color=%s]%s[/color]" % [TextRenderer.CHANNEL_COLORS["SYSTEM"], TextRenderer.escape_bbcode(t)])

func add_error(reason: String) -> void:
	var t := UiClient.reason_text(reason)
	if t == "":
		return
	_push(UiKeys.CH_SYSTEM, "[color=%s]%s[/color]" % [TextRenderer.ERROR_COLOR, TextRenderer.escape_bbcode(t)])

## 系統【江湖傳聞】（jianghu_rumor，頻道 JIANGHU）：左上浮層一行（傳聞色）＋右下系統訊息框，兩處都受「江湖傳聞」開關控制
func add_rumor(p: Dictionary) -> void:
	var line := StoryUi.rumor_line(p, UiClient.templates())
	if line == "":
		return
	add_announcement(line, true, RUMOR_CHANNEL)
	_push(UiKeys.CH_JIANGHU, "[color=%s]%s[/color]" % [TextRenderer.CHANNEL_COLORS.get(UiKeys.CH_JIANGHU, "#ffd080"), TextRenderer.escape_bbcode(line)])

## rumor：受頻道開關控制的公告（預設「江湖謠言」，傳聞是「江湖傳聞」）
func add_announcement(t: String, rumor := true, ch := ANNOUNCE_CHANNEL) -> void:
	if t == "":
		return
	announce_lines.append({ "t": t, "rumor": rumor, "ch": ch })
	while announce_lines.size() > ANNOUNCE_LINES:
		announce_lines.remove_at(0)
	_render_announce()

func _render_announce() -> void:
	if announce == null:
		return
	announce.clear()
	var show: PackedStringArray = []
	for a in announce_lines:
		if not bool(a["rumor"]) or channel_enabled(str(a.get("ch", ANNOUNCE_CHANNEL))):
			show.append(str(a["t"]))
	announce.append_text(TextRenderer.escape_bbcode("\n".join(show)))
	UiBuild.stick_whole_lines.call_deferred(announce)

func _push(ch: String, bb: String) -> void:
	ensure_built()
	entries.append({ "ch": ch, "bb": bb })
	if _visible_ch(ch):
		text.append_text(bb + "\n")
		_stick_bottom.call_deferred()
	# 超過上限時只移除最舊的段落，不整個重繪（滿 500 行後每個事件都重繪 500 行 BBCode 會卡頓）
	while entries.size() > UiKeys.LOG_MAX_LINES:
		var old: Dictionary = entries.pop_front()
		if not _visible_ch(old["ch"]):
			continue
		for i in String(old["bb"]).count("\n") + 1:   # 一則訊息可能占多段
			if text.get_paragraph_count() > 1:
				text.remove_paragraph(0)

func _rerender() -> void:
	text.clear()
	for en in entries:
		if _visible_ch(en["ch"]):
			text.append_text(en["bb"] + "\n")
	_stick_bottom.call_deferred()

## 捲到最新一行（使用者正在用滾輪往上看時不動）。審查 round 3：浮層停在開場的擲骰、任務文字，之後的訊息都沒捲上來——
## 戰鬥畫面蓋住主畫面、浮層被隱藏時 append 的字，RichTextLabel 的 scroll_following 不會跟上
## 審查 round 4：最上／最下一行切半——只露整行（UiBuild.stick_whole_lines）。暗紗只在有字時出現、大小跟著字走
func _stick_bottom() -> void:
	_fit_veil()
	if text == null or _last_wheel_ms >= 0 or not is_inside_tree():
		return
	UiBuild.stick_whole_lines(text)

func _fit_veil() -> void:
	if veil == null or text == null:
		return
	veil.visible = not entries.is_empty() and text.get_line_count() > 0
	if not veil.visible:
		return
	# 只蓋有字的範圍（字少時不在空白處留一塊暗角），往右、往下各多淡出一圈
	var used_h := minf(size.y, float(text.get_content_height()) + 8.0)
	veil.position = Vector2.ZERO
	veil.size = Vector2(size.x * 1.35, maxf(48.0, used_h) * 1.45)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_RESIZED:
		if _built:
			_stick_bottom.call_deferred()

## 螢幕對話清除
func clear() -> void:
	entries.clear()
	text.clear()
	_fit_veil()

## 螢幕對話開關
func set_overlay_visible(on: bool) -> void:
	visible = on
	UiSettings.set_value("ui.chat_overlay", on)

func visible_lines() -> int:
	var n := 0
	for en in entries:
		if _visible_ch(en["ch"]):
			n += 1
	return n

func _on_events(batch: Array) -> void:
	for e in batch:
		if e is Dictionary:
			add_event(e)

func _on_intent_result(_seq: int, ok: bool, reason: String) -> void:
	if not ok:
		add_error(reason)

func _on_send() -> void:
	if input == null:
		return
	if input.text.strip_edges().is_empty():
		return
	var args := chat_args(input.text)
	if args.is_empty():
		add_system("【系統】傳音入密要先填對象的名字。")
		if whisper_to != null and whisper_to.is_inside_tree():
			whisper_to.grab_focus()
		return
	_gate().send(UiKeys.I_CHAT, args, [btn_send])
	input.clear()
