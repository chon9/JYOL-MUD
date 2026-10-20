class_name BottomHud
extends PanelContainer
## 底部 HUD（AUTHENTIC_UI_SPEC §6）：雕木 HUD 框，左區 272／中區（吸收多出來的寬度）／右區 408。
## - 左區：StatusBar（7 個圓章圖示＋精氣神內力 4 條）
## - 中區：帶 A 地點牌（房名，view 有 coords 時加座標）、玉綠圓珠、曆法牌；帶 B 熱鍵列 2 列＋頻道鈕與聊天輸入
## - 右區：帶 A 殺氣（紅底白字）、本機時間、飛鴿傳書圓章；帶 B 系統訊息框
## 戰鬥中照常顯示（戰鬥畫面只蓋上半部），殺氣常亮。
## M2：飛鴿傳書圓章在 sheet.mail_unread > 0 時閃爍（AUTHENTIC_UI_SPEC §6.1「有新信時閃爍」）；按下由主畫面開飛鴿視窗。

const HEIGHT := 168.0
const LEFT_W := 272.0
const RIGHT_W := 408.0

var status_bar: StatusBar
var hotbar: Hotbar
var location_label: Label
var calendar_label: Label
var kill_label: Label
var clock_label: Label
var pigeon: JyButton
var mail_unread := 0
var orb: Control
var _built := false
var _last_clock := ""

func _ready() -> void:
	ensure_built()

func ensure_built() -> void:
	if _built:
		return
	_built = true
	add_theme_stylebox_override("panel", UiFrame.style(UiFrame.Kind.HUD))
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var cols := UiBuild.hbox(self, 8)
	# 左區
	status_bar = StatusBar.new()
	status_bar.custom_minimum_size = Vector2(LEFT_W - 12.0, 0)
	cols.add_child(status_bar)
	cols.add_child(VSeparator.new())
	# 中區
	var mid := UiBuild.vbox(cols, 2)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var band_a := UiBuild.hbox(mid, 8)
	band_a.custom_minimum_size = Vector2(0, 26)
	location_label = UiBuild.plate(band_a, "", 15, 240)
	location_label.tooltip_text = "所在地"
	location_label.mouse_filter = Control.MOUSE_FILTER_PASS
	orb = JadeOrb.new()
	band_a.add_child(orb)
	calendar_label = UiBuild.plate(band_a, "", 15, 200)
	calendar_label.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hotbar = Hotbar.new()
	mid.add_child(hotbar)
	# 聊天輸入列由主畫面（MessageLog.build_input）放進 chat_row
	chat_row = UiBuild.vbox(mid, 0)
	cols.add_child(VSeparator.new())
	# 右區
	var right := UiBuild.vbox(cols, 4)
	right.custom_minimum_size = Vector2(RIGHT_W - 24.0, 0)
	var ra := UiBuild.hbox(right, 8)
	ra.custom_minimum_size = Vector2(0, 26)
	var kill := UiBuild.framed(ra, UiFrame.Kind.PLATE)
	var ks := StyleBoxFlat.new()
	ks.bg_color = UiTheme.JY_RED
	ks.set_corner_radius_all(2)
	ks.content_margin_left = 8
	ks.content_margin_right = 8
	kill.add_theme_stylebox_override("panel", ks)
	kill_label = UiBuild.label(kill, "殺氣:0", 14)
	kill_label.add_theme_color_override("font_color", Color.WHITE)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ra.add_child(sp)
	clock_label = UiBuild.label(ra, "", 15)
	clock_label.tooltip_text = "現在時間"
	clock_label.mouse_filter = Control.MOUSE_FILTER_PASS
	pigeon = UiBuild.jy_button(ra, JyButton.Style.SEAL, "飛鴿傳書", Callable(), "鴿")
	pigeon.name = "Pigeon"
	pigeon.tooltip_text = "飛鴿傳書"
	announce_host = UiBuild.vbox(right, 0)
	announce_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_update_clock()

var chat_row: VBoxContainer
var announce_host: VBoxContainer

func apply_sheet(s: Dictionary) -> void:
	ensure_built()
	status_bar.apply_sheet(s)
	hotbar.apply_sheet(s)
	kill_label.text = "殺氣:%d" % UiBuild.num(s.get("killing_intent", 0))
	set_mail_unread(UiSocial.mail_unread(s))
	var clock: Dictionary = s.get("clock", {})
	if not clock.is_empty():
		calendar_label.text = BottomHud.calendar_text(clock)
		calendar_label.tooltip_text = "遊戲中時間" + ("（夜）" if bool(clock.get("night", false)) else "")
	var loc: Dictionary = s.get("location", {})
	if location_label.text == "" and str(loc.get("room_name", "")) != "":
		location_label.text = str(loc.get("room_name", ""))

func apply_view(v: Dictionary) -> void:
	ensure_built()
	hotbar.apply_view(v)
	location_label.text = BottomHud.location_text(v)
	location_label.tooltip_text = "%s・%s" % [str(v.get("region_name", "")), str(v.get("room_name", ""))]

## 地點牌：房名；view 帶座標（coords／pos：[x, y]）時加在後面，例「西夏市街 7296,2966」
static func location_text(v: Dictionary) -> String:
	var name := str(v.get("room_name", ""))
	var c: Variant = v.get("coords", v.get("pos", null))
	if c is Array and (c as Array).size() >= 2:
		return "%s %d,%d" % [name, int(c[0]), int(c[1])]
	return name

## 曆法牌：「八月廿七 戌時七刻」（clock 有 month／mday 時）；否則「第 N 日 辰時三刻」
static func calendar_text(clock: Dictionary) -> String:
	var t := str(clock.get("text", ""))
	if clock.has("month") and clock.has("mday"):
		return "%s月%s %s" % [BottomHud.cn_num(int(clock["month"])), BottomHud.cn_day(int(clock["mday"])), t]
	return "第 %d 日 %s" % [UiBuild.num(clock.get("day", 1)), t]

const CN_DIGITS := ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

static func cn_num(n: int) -> String:
	if n <= 10:
		return CN_DIGITS[clampi(n, 0, 10)]
	if n < 20:
		return "十" + CN_DIGITS[n - 10]
	return CN_DIGITS[n / 10] + "十" + (CN_DIGITS[n % 10] if n % 10 != 0 else "")

## 農曆日：初一…初十、十一…二十、廿一…廿九、三十
static func cn_day(d: int) -> String:
	if d <= 10:
		return "初" + CN_DIGITS[clampi(d, 1, 10)]
	if d < 20:
		return "十" + CN_DIGITS[d - 10]
	if d == 20:
		return "二十"
	if d < 30:
		return "廿" + CN_DIGITS[d - 20]
	return "三十"

func set_in_battle(on: bool) -> void:
	ensure_built()
	status_bar.in_battle = on
	hotbar.in_battle = on

func set_mail_unread(n: int) -> void:
	mail_unread = maxi(0, n)
	if pigeon == null:
		return
	pigeon.tooltip_text = "飛鴿傳書（%d 封未讀）" % mail_unread if mail_unread > 0 else "飛鴿傳書"
	if mail_unread == 0:
		pigeon.modulate.a = 1.0

func pigeon_blinking() -> bool:
	return mail_unread > 0

func _process(_delta: float) -> void:
	_update_clock()
	if pigeon != null and mail_unread > 0:
		pigeon.modulate.a = UiSocial.blink_alpha(Time.get_ticks_msec())

func _update_clock() -> void:
	var t := Time.get_time_dict_from_system()
	var s := "%02d:%02d" % [int(t["hour"]), int(t["minute"])]
	if s != _last_clock and clock_label != null:
		_last_clock = s
		clock_label.text = s

## 中央玉綠圓珠（純裝飾）：徑向漸層＋金邊
class JadeOrb extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(36, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		draw_circle(c, r, UiTheme.JY_GOLD)
		for i in 8:
			var k := float(i) / 8.0
			draw_circle(c - Vector2(r, r) * 0.15 * k, (r - 2.0) * (1.0 - k * 0.8), Color("2e6a4a").lerp(Color("8ad0a0"), k))
