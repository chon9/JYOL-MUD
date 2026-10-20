class_name SystemPanel
extends VBoxContainer
## 系統窗（Ctrl+5，AUTHENTIC_UI_SPEC §8.6）：照原作的直排骨色長鈕（寬 200）排列，右邊是選中那一項的內容：
## 累計上線時間、新手說明、頻道開關、螢幕對話清除、螢幕對話開關、更改密碼（本作沒有帳號，灰色）、
## 音樂開關（開關＋音量滑桿，呼叫 BgmPlayer.set_music_enabled／set_music_volume）、音效開關（尚未加入）、
## 特殊開關（介面縮放、時間棒清單、損血顯示、戰場格線、小地圖、戰鬥結束自動返回）、離開遊戲（返回角色選擇／離開世界回標題）。
## 設定都記在 settings.json（UiSettings）；改了會發 option_changed(key, value) 讓主畫面立刻套用。
## M2（M2_PLAN 4.10）：特殊開關多了 接受叫戰、接受組隊邀請（set_pref，存在主機的角色上）與 顯示名稱（本機設定，D5）；
## 管理員多一顆「伺服器設定」（發 server_options_requested，主畫面開伺服器設定面板）。累計上線時間頁在 Steam 大廳中有「邀請好友」。
## 故事包（STORY_PLAN §6.3）：「江湖傳聞」頁＝最近的系統傳聞（打開時送 rumor_list，主機回 rumor_list（ui）→ apply_rumor_list）；
## 頻道開關多一個「江湖傳聞」（MessageLog.EXTRA_CHANNELS）。

signal navigate(scene_name: String)
signal option_changed(key: String, value: Variant)
signal server_options_requested

const ITEMS := ["累計上線時間", "新手說明", "頻道開關", "螢幕對話清除", "螢幕對話開關", "更改密碼",
	"音樂開關", "音效開關", "特殊開關", "江湖傳聞", "離開遊戲"]
const RUMOR_PAGE := "江湖傳聞"
const DISABLED_ITEMS := ["更改密碼"]
const SCALES := [0.9, 1.0, 1.15]
const HELP := """【操作說明】
・右邊燈籠：武功 Ctrl+1、屬性 Ctrl+2、裝備 Ctrl+3、指令 Ctrl+4、系統 Ctrl+5；燈籠下的中國結收合燈籠。
・任務 Ctrl+6（也在指令窗「雜項」）；江湖地圖 Ctrl+M 或 M。
・下方熱鍵：F1–F8 指令、Alt+1–8 物品。在指令窗或裝備窗用滑鼠右鍵把東西拖到熱鍵格，拖出熱鍵列就清掉。
・左下卷軸是你所在的地方：點出口移動、點人名對話；按住房名可以把卷軸拖到別處。
・Esc：先放開聊天框，再關視窗，最後收合燈籠。
・戰鬥：輪到你時圓盤指令才會亮：移（綠格）、攻（藍格範圍、紅格目標）、武、防、休、裝、逃（站上白框「逃」格）；快捷鍵 1–7。"""
const OPTIONS := [
	["ui.atb_list", "戰鬥時間棒清單（右側列出每個人的時間棒；原作沒有）"],
	["ui.damage_text", "損血顯示（戰鬥中單位腰部顯示 氣 cur/max）"],
	["ui.grid_lines", "戰場格線"],
	["ui.minimap", "小地圖"],
	["ui.battle_auto_return", "戰鬥結束自動返回"],
	["nav.auto_resume", "趕路遇敵獲勝後繼續趕路"],
	["ui.show_names", "顯示名稱（戰場上其他人的名字牌；只影響自己的畫面）"],
]

var gate: IntentGate
var feedback: PanelFeedback
var sheet: Dictionary = {}
var pref_buttons: Dictionary = {}  # pref key -> CheckButton（特殊開關頁）
var admin_button: Button
var status_label: Label
var message_log: MessageLog       # 主畫面塞進來（頻道開關、螢幕對話清除／開關）
var item_buttons: Dictionary = {}
var page: VBoxContainer
var page_scroll: ScrollContainer
var current := "累計上線時間"
var rumor_items: Array = []        # 最近一次 rumor_list 的 items（新的在前顯示）
var rumor_box: VBoxContainer = null
var _online_since_ms := 0
var _built := false

func _ready() -> void:
	if not _built:
		_build()

func _build() -> void:
	_built = true
	_online_since_ms = Time.get_ticks_msec()
	var row := UiBuild.hbox(self, 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := UiBuild.vbox(row, 4)
	col.custom_minimum_size = Vector2(200, 0)
	for it in ITEMS:
		var b := UiBuild.button(col, it, show_page.bind(it))
		b.custom_minimum_size = Vector2(200, 30)
		b.disabled = it in DISABLED_ITEMS
		if b.disabled:
			b.tooltip_text = "本作沒有帳號系統"
		item_buttons[it] = b
	var frame := UiBuild.framed(row, UiFrame.Kind.INK)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 右欄放進捲動框：特殊開關頁（兩個主機開關、連結鍵、伺服器設定、縮放、六個本機開關、說明）比視窗高，
	# 不捲動的話會把整個系統窗撐高、蓋住精氣條和熱鍵列，換頁時視窗也會變大小（M2 審查）
	page_scroll = ScrollContainer.new()
	page_scroll.name = "PageScroll"
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(page_scroll)
	page = UiBuild.vbox(page_scroll, 8)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label = UiBuild.label(null, "", 16, true)
	show_page(current)

func show_page(it: String) -> void:
	current = it
	for k in item_buttons:
		(item_buttons[k] as Button).add_theme_color_override("font_color", UiTheme.CINNABAR if k == it else UiTheme.JY_BTN_TEXT)
	if status_label.get_parent() != null:
		status_label.get_parent().remove_child(status_label)
	UiBuild.clear(page)
	if page_scroll != null:
		page_scroll.scroll_vertical = 0
	UiBuild.accent(UiBuild.label(page, it, 18))
	match it:
		"累計上線時間":
			page.add_child(status_label)
			refresh()
			var sm := get_node_or_null("/root/SteamManager") if is_inside_tree() else null
			if sm != null and int(sm.get("lobby_id")) != 0:
				UiBuild.button(page, "邀請 Steam 好友", func():
					if sm.has_method("open_invite_overlay"):
						sm.call("open_invite_overlay"))
		"新手說明":
			UiBuild.label(page, HELP, 15, true)
		"頻道開關":
			var g := GridContainer.new()
			g.columns = 3
			page.add_child(g)
			for c in MessageLog.CHANNELS + MessageLog.EXTRA_CHANNELS:
				var cb := CheckButton.new()
				cb.name = "Channel_" + c
				cb.text = c
				cb.button_pressed = message_log.channel_enabled(c) if message_log != null else not (c in MessageLog.CHANNELS_OFF)
				if c in MessageLog.LOCKED_ON:
					# 天外飛仙：系統與 GM 的訊息，原作「不能關閉」【已證實 17173 yinan/15】
					cb.button_pressed = true
					cb.disabled = true
					cb.tooltip_text = "系統與管理員的訊息，不能關閉。"
				else:
					cb.toggled.connect(func(on: bool):
						if message_log != null:
							message_log.set_channel_enabled(c, on))
				g.add_child(cb)
			UiBuild.muted(UiBuild.label(page, "關掉的頻道不顯示在左上浮層；「江湖謠言」也控制右下的系統訊息框。「江湖傳聞」是系統的事件與事蹟廣播（非原作），關掉後左上與右下都不顯示。發話頻道在聊天框左邊的頻道鈕切換。", 14, true))
		"螢幕對話清除":
			UiBuild.label(page, "清除畫面左上的所有對話與系統訊息。", 15, true)
			UiBuild.button(page, "清除", func():
				if message_log != null:
					message_log.clear())
		"螢幕對話開關":
			var cb2 := CheckButton.new()
			cb2.text = "顯示左上的對話浮層"
			cb2.button_pressed = message_log.visible if message_log != null else UiSettings.get_bool("ui.chat_overlay")
			cb2.toggled.connect(func(on: bool):
				if message_log != null:
					message_log.set_overlay_visible(on))
			page.add_child(cb2)
		"音樂開關":
			_music_page()
		"音效開關":
			var cb3 := CheckButton.new()
			cb3.text = "音效"
			cb3.disabled = true
			page.add_child(cb3)
			UiBuild.muted(UiBuild.label(page, "音效尚未加入（BGM_PLAN）。", 14, true))
		"特殊開關":
			_options_page()
		RUMOR_PAGE:
			_rumor_page()
		"離開遊戲":
			UiBuild.button(page, "返回角色選擇", func(): navigate.emit("char_select"))
			UiBuild.button(page, "離開世界（回標題）", _on_leave)
			UiBuild.muted(UiBuild.label(page, "離開時主機會自動存檔。", 14))

## 江湖傳聞頁：打開時向主機要最近的傳聞；先顯示上次拿到的
func _rumor_page() -> void:
	UiBuild.muted(UiBuild.label(page, "江湖上最近流傳的消息：事件的風聲、誰完成了什麼、誰打退了惡人。（系統廣播，非原作；主機可在伺服器設定關掉）", 14, true))
	var b := UiBuild.button(page, "重新整理", request_rumors)
	b.name = "RumorRefresh"
	rumor_box = UiBuild.vbox(page, 4)
	rumor_box.name = "RumorList"
	_render_rumors()
	request_rumors()

func request_rumors() -> void:
	var g := gate
	if g == null:
		g = IntentGate.new()
		add_child(g)
		gate = g
	g.send(UiKeys.I_RUMOR_LIST, {}, [], func(ok: bool, reason: String):
		if not ok and feedback != null and is_instance_valid(feedback):
			feedback.show_result(false, reason))

## rumor_list（ui）：items [{ text_key, params, kind, world_s }]
func apply_rumor_list(items: Array) -> void:
	rumor_items = items.filter(func(x): return x is Dictionary)
	_render_rumors()

func _render_rumors() -> void:
	if rumor_box == null or not is_instance_valid(rumor_box) or current != RUMOR_PAGE:
		return
	UiBuild.clear(rumor_box)
	var shown := 0
	var list := rumor_items.duplicate()
	list.sort_custom(func(a, b): return float(a.get("world_s", 0)) > float(b.get("world_s", 0)))
	for it in list:
		var t := StoryUi.rumor_text(it, UiClient.templates())
		if t == "":
			continue
		var row := UiBuild.hbox(rumor_box, 8)
		var tag := UiBuild.accent(UiBuild.label(row, "［%s］" % StoryUi.rumor_kind_label(str(it.get("kind", ""))), 14))
		tag.custom_minimum_size = Vector2(56, 0)
		var l := UiBuild.label(row, t, 15, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiBuild.muted(UiBuild.label(row, StoryUi.world_time_label(float(it.get("world_s", 0))), 13))
		shown += 1
	if shown == 0:
		UiBuild.muted(UiBuild.label(rumor_box, "（最近江湖上風平浪靜）", 15))

func _bgm() -> Node:
	return get_node_or_null("/root/BgmPlayer") if is_inside_tree() else null

func _music_page() -> void:
	var bgm := _bgm()
	var cb := CheckButton.new()
	cb.text = "背景音樂"
	cb.button_pressed = bool(bgm.get("enabled")) if bgm != null else true
	cb.toggled.connect(set_music_enabled)
	page.add_child(cb)
	var h := UiBuild.hbox(page, 8)
	UiBuild.label(h, "音量", 15)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = float(bgm.get("volume")) if bgm != null else 0.6
	sl.custom_minimum_size = Vector2(220, 20)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pct := UiBuild.label(h, "%d%%" % int(sl.value * 100.0), 15)
	sl.value_changed.connect(func(v: float):
		pct.text = "%d%%" % int(v * 100.0)
		set_music_volume(v))
	h.add_child(sl)
	h.move_child(sl, 1)
	if bgm == null:
		UiBuild.muted(UiBuild.label(page, "（沒有載入 BgmPlayer）", 14))

func set_music_enabled(on: bool) -> void:
	var bgm := _bgm()
	if bgm != null and bgm.has_method("set_music_enabled"):
		bgm.call("set_music_enabled", on)

func set_music_volume(v: float) -> void:
	var bgm := _bgm()
	if bgm != null and bgm.has_method("set_music_volume"):
		bgm.call("set_music_volume", v)

func _options_page() -> void:
	# 主機上的角色開關（系統開關【已證實 17173 yinan/33】）
	pref_buttons.clear()
	var prefs: Dictionary = sheet.get("prefs", {}) if sheet.get("prefs", {}) is Dictionary else {}
	for key in UiKeys.PREF_KEYS:
		var cbp := CheckButton.new()
		cbp.name = "Pref_" + key
		cbp.text = UiKeys.PREF_LABELS[key]
		cbp.button_pressed = bool(prefs.get(key, true))
		cbp.toggled.connect(func(on: bool): set_pref(key, on, cbp))
		page.add_child(cbp)
		pref_buttons[key] = cbp
	# 強制 PK 的連結鍵（M2_PLAN 5.2：2001 年叫「連結鍵」，可改鍵）
	var hk := UiBuild.hbox(page, 8)
	UiBuild.label(hk, "強行出手：按住", 15)
	var pk_opt := OptionButton.new()
	pk_opt.name = "PkKeyOption"
	for i in UiSocial.PK_KEYS.size():
		var k: String = UiSocial.PK_KEYS[i]
		pk_opt.add_item(UiSocial.pk_key_label(k), i)
		if k == UiSocial.pk_key():
			pk_opt.select(i)
	pk_opt.item_selected.connect(func(i: int): set_option(UiSocial.PK_KEY_SETTING, UiSocial.PK_KEYS[i]))
	hk.add_child(pk_opt)
	UiBuild.label(hk, "＋點玩家名字", 15)
	admin_button = UiBuild.button(page, "伺服器設定（主機）", func(): server_options_requested.emit())
	admin_button.name = "ServerOptionsButton"
	admin_button.visible = bool(sheet.get("is_admin", false))
	page.add_child(HSeparator.new())
	var h := UiBuild.hbox(page, 8)
	UiBuild.label(h, "介面縮放", 15)
	var opt := OptionButton.new()
	var cur := float(UiSettings.get_value("ui.scale", 1.0))
	for i in SCALES.size():
		opt.add_item("%d%%" % int(round(SCALES[i] * 100.0)), i)
		if is_equal_approx(SCALES[i], cur):
			opt.select(i)
	opt.item_selected.connect(func(i: int): set_option("ui.scale", SCALES[i]))
	h.add_child(opt)
	for o in OPTIONS:
		var key: String = o[0]
		var cb := CheckButton.new()
		cb.text = o[1]
		cb.button_pressed = UiSettings.get_bool(key)
		cb.toggled.connect(func(on: bool): set_option(key, on))
		page.add_child(cb)
	UiBuild.muted(UiBuild.label(page, "戰鬥等待模式：輪到你時時間會停下來等你下令（主機設定）。字級切換尚未提供。", 14, true))

## 接受叫戰／接受組隊邀請：送 set_pref；失敗時把開關撥回去
func set_pref(key: String, on: bool, cb: CheckButton = null) -> void:
	if gate == null:
		return
	if feedback != null:
		feedback.begin()
	gate.send(UiKeys.I_SET_PREF, { "key": key, "value": on }, [cb] if cb != null else [], func(ok: bool, reason: String):
		if feedback != null:
			feedback.show_result(ok, reason)
		if not ok and cb != null and is_instance_valid(cb):
			cb.set_pressed_no_signal(not on))

func set_option(key: String, value: Variant) -> void:
	UiSettings.set_value(key, value)
	option_changed.emit(key, value)

func refresh() -> void:
	if not _built:
		_build()
	var nm := get_node_or_null("/root/NetworkManager") if is_inside_tree() else null
	var secs := (Time.get_ticks_msec() - _online_since_ms) / 1000
	status_label.text = "連線：%s\n本次上線：%d 小時 %d 分 %d 秒" % [str(nm.status_text) if nm else "未連線", secs / 3600, (secs / 60) % 60, secs % 60]

func apply_sheet(s: Dictionary) -> void:
	sheet = s
	if current == "累計上線時間":
		refresh()
	var prefs: Variant = s.get("prefs", {})
	if prefs is Dictionary:
		for key in pref_buttons:
			# 換頁時特殊開關頁的按鈕已被釋放：先檢查再轉型（型別變數接到已釋放的實例會 SCRIPT ERROR）
			var obj: Variant = pref_buttons[key]
			if not is_instance_valid(obj):
				continue
			var cb := obj as CheckButton
			if cb != null and (prefs as Dictionary).has(key) and cb.button_pressed != bool(prefs[key]):
				cb.set_pressed_no_signal(bool(prefs[key]))
	if admin_button != null and is_instance_valid(admin_button):
		admin_button.visible = bool(s.get("is_admin", false))

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and status_label != null and is_instance_valid(status_label) and status_label.get_parent() == null:
		status_label.free()

func _on_leave() -> void:
	navigate.emit("title")
