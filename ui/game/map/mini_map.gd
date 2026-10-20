class_name MiniMap
extends PanelContainer
## 主畫面右上的區域小地圖（AUTHENTIC_UI_SPEC §10：原作 2018 版沒有常駐小地圖，本作是文字 MUD 需要方位感，所以保留）。
## 小號玉石框；內容是羊皮紙底加墨線房間圖，畫面跟著玩家置中。標題列有收合鈕（狀態記在 settings.json 的
## ui.minimap_collapsed）與「地圖(Ctrl+M)」鈕（open_requested → 主畫面開大地圖）。系統窗特殊開關可以整個關掉。
## 資料（迷霧、到過的房間、趕路）全部由 MapPanel 提供；點房間 → MapPanel 的點擊趕路。
## M3c（M3C_PLAN §4.3–4.5）：
## - 點「往XXX」→ region_clicked（MapPanel 把小地圖與區域圖切到那個鄰區，瀏覽中）；標題列「⟲」＝返回目前區域（back_requested）；
## - 趕路中狀態列旁有「停」鈕（stop_requested）；右鍵 → quick_requested（MapPanel 開快捷目的地選單）。

signal open_requested
signal room_clicked(room_id: String)
signal region_clicked(region_id: String)
signal back_requested
signal stop_requested
signal quick_requested(screen_pos: Vector2)

var title_label: Label
var status_label: Label
var map_button: Button
var collapse_button: Button
var back_button: Button
var stop_button: Button
var view: RegionMapView
var body: VBoxContainer
var collapsed := false
var browsing := false
var expanded_h := 228.0
const COLLAPSED_H := 34.0
var _built := false
## 小地圖縮放：190 寬看得到左右鄰房、上下各一間（原尺寸 150×92 一格，只看得到自己這間）
const MINI_ZOOM := 0.55
## M3c 審查：「⟲」（U+27F2）由後備字型畫成看不懂的小圈 → 用中文「返」；瀏覽別區時標題前加「瀏覽」
const BACK_TEXT := "返"
const BROWSE_PREFIX := "瀏覽 "
const MAP_TEXT := "地圖(Ctrl+M)"
const MAP_TEXT_SHORT := "地圖"

func _ready() -> void:
	if not _built:
		_build()

func _build() -> void:
	_built = true
	add_theme_stylebox_override("panel", UiFrame.style(UiFrame.Kind.JADE_SMALL))
	var col := UiBuild.vbox(self, 3)
	var head := UiBuild.hbox(col, 4)
	collapse_button = UiBuild.button(head, "－", toggle_collapsed)
	collapse_button.custom_minimum_size = Vector2(20, 18)
	collapse_button.add_theme_font_size_override("font_size", 11)
	collapse_button.tooltip_text = "收合／展開小地圖"
	collapse_button.focus_mode = Control.FOCUS_NONE
	back_button = UiBuild.button(head, BACK_TEXT, func(): back_requested.emit())
	back_button.custom_minimum_size = Vector2(24, 18)
	back_button.add_theme_font_size_override("font_size", 13)
	back_button.tooltip_text = "返回目前區域"
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.visible = false
	title_label = UiBuild.label(head, "", 13)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	map_button = UiBuild.button(head, MAP_TEXT, func(): open_requested.emit())
	map_button.tooltip_text = "打開地圖（Ctrl+M）"
	map_button.add_theme_font_size_override("font_size", 12)
	map_button.focus_mode = Control.FOCUS_NONE
	body = UiBuild.vbox(col, 2)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view = RegionMapView.new()
	view.follow_current = true
	view.zoom = MINI_ZOOM
	view.follow_zoom_max = MINI_ZOOM
	view.custom_minimum_size = Vector2(230, 150)
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.room_clicked.connect(func(id: String): room_clicked.emit(id))
	view.region_clicked.connect(func(id: String): region_clicked.emit(id))
	view.context_requested.connect(func(at: Vector2): quick_requested.emit(view.get_screen_position() + at))
	body.add_child(view)
	var srow := UiBuild.hbox(body, 4)
	status_label = UiBuild.muted(UiBuild.label(srow, "", 12))
	status_label.clip_text = true
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop_button = UiBuild.button(srow, "停", func(): stop_requested.emit())
	stop_button.add_theme_font_size_override("font_size", 11)
	stop_button.custom_minimum_size = Vector2(24, 16)
	stop_button.tooltip_text = "停止趕路（Esc）"
	stop_button.focus_mode = Control.FOCUS_NONE
	stop_button.visible = false
	set_collapsed(UiSettings.get_bool("ui.minimap_collapsed"), false)

func toggle_collapsed() -> void:
	set_collapsed(not collapsed)

func set_collapsed(on: bool, persist := true) -> void:
	collapsed = on
	if body != null:
		body.visible = not on
		collapse_button.text = "＋" if on else "－"
	# 收合時只剩標題列（主畫面用錨點放在右上：調整下緣）
	if on:
		offset_bottom = offset_top + COLLAPSED_H
	elif offset_bottom - offset_top < expanded_h:
		offset_bottom = offset_top + expanded_h
	if persist:
		UiSettings.set_value("ui.minimap_collapsed", on)

## 由 MapPanel.refresh() 呼叫；p_browsing＝正在瀏覽別區（標題列出現「⟲」），focus＝瀏覽時畫面跟著的房間
func show_region(tables: Dictionary, model: Dictionary, known: Dictionary, current: String, title: String, walk_target: String,
		p_browsing: bool = false, focus: String = "") -> void:
	if not _built:
		_build()
	browsing = p_browsing
	back_button.visible = p_browsing
	# 標題列很窄（右邊還有「地圖(Ctrl+M)」鈕）：「西夏　已探索 4／9 處」會被切成「西夏　已探」（審查），
	# 小地圖只寫「西夏 4/9」，完整的放在滑鼠提示
	title_label.text = (BROWSE_PREFIX if p_browsing else "") + MiniMap.compact_title(title)
	title_label.tooltip_text = title
	# M3c 第二輪審查（瀏覽時標題被「地圖(Ctrl+M)」切成「瀏覽 西夏郊⁄」）：瀏覽中多了「返」鈕 → 地圖鈕只寫「地圖」、
	# 標題不寫探索數（滑鼠提示有完整的）；字還是太長時用「…」收尾，不會切半個字
	map_button.text = MAP_TEXT_SHORT if p_browsing else MAP_TEXT
	if p_browsing:
		title_label.text = BROWSE_PREFIX + MiniMap.compact_title(title).get_slice(" ", 0)
	view.focus_room = focus
	view.setup(tables, model, known, current)
	view.set_walk_target(walk_target)

## 「西夏　已探索 4／9 處」→「西夏 4/9」；「西夏郊外（瀏覽中）　已探索 2／9 處」→「西夏郊外 2/9」（瀏覽中由 show_region 加「瀏覽 」前綴）；其他格式原樣
static func compact_title(title: String) -> String:
	var re := RegEx.create_from_string("^(.*?)　已探索 ([0-9]+)／([0-9]+) 處$")
	var m := re.search(title)
	if m == null:
		return title
	# 瀏覽中：名稱不加「（瀏覽中）」（小地圖標題很窄），改由 show_region 在前面加短短的「瀏覽 」
	return "%s %s/%s" % [m.get_string(1).trim_suffix(MapPanel.BROWSE_TAG), m.get_string(2), m.get_string(3)]

func set_status(text: String, walking: bool) -> void:
	if not _built:
		_build()
	status_label.text = text
	status_label.tooltip_text = text
	stop_button.visible = walking
	if walking:
		status_label.theme_type_variation = "ErrorLabel"
	else:
		status_label.theme_type_variation = "MutedLabel"
