class_name TourneyDialog
extends NumberedDialog
## 比武報名視窗（M3D_PLAN §5.3、§10.4；WP-EVENTS）：西夏比武場休息區的報名員（服務 TOURNEY）、
## 或任何時候收到 tourney_state（ui）時更新。內容：
## - 目前的場次（武林大會／各派門派比武）：階段（報名中／進行中／已結束）、人數、開打倒數、「報名」「退出」；
## - 選中場次的對戰表（每一輪一欄：甲 對 乙 → 勝者；輪空、點名不到、時間到判定、擊倒）、下一場與點名次數；
## - 日曆（下幾場的日子與時辰）與規則說明（切磋模式、十分鐘判定、表演賽、不發神兵）；
## - 主機（或管理者）多一列「開辦」：武林大會／本派比武，報名秒數。
## 數字鍵 1–9 按第 n 顆可按的按鈕；Esc 關（主畫面）。

const RULE_TEXT := "切磋模式：沒有死亡懲罰，戰後精氣神內力補滿，門派技能不觸發、召喚類道具不能用。一場十分鐘，時間到依總傷害、命中次數、剩餘氣的比例判定。點名三次不到判負；逃走、斷線算棄權。報名不到四人是表演賽（不發名聲與稱號），同一種比賽三十個遊戲日、而且三十個現實日內只發一次獎。不發神兵。"
const PHASE_TEXT := { "SIGNUP": "報名中", "RUNNING": "比賽進行中", "DONE": "已結束" }
const HOW_TEXT := { "KO": "擊倒", "JUDGE": "判定", "FORFEIT": "棄權", "BYE": "輪空" }

## npc_dialog 按「比武報名」時記下來；主畫面收到 tourney_state 時看到這個旗標就打開視窗（客戶端靜態，不經網路）
static var pending_open := false
static var pending_npc := ""

var npc := ""
var state: Dictionary = {}
var selected := ""                 # 選中的場次 kind（""＝主機給的那一場）
var head_label: Label
var events_box: VBoxContainer
var bracket_box: VBoxContainer
var bracket_scroll: ScrollContainer
var info_label: Label
var calendar_label: Label
var host_box: HBoxContainer
var host_secs: SpinBox
## M3d 審查第三輪：報名倒數在視窗開著時每秒往下數（原本只在收到新狀態或按「重新整理」時才更新）
var _applied_ms := 0
var _tick_acc := 0.0
var _live: Array = []              # [[Label, 場次 Dictionary, 前綴, 後綴]]
## 測試用：可用高度（< 0 ＝看所在的對話框層，或視窗高度扣掉 HUD）
var avail_h_override := -1.0
const HUD_H := 168.0
const FIT_MARGIN := 12.0
const BRACKET_MIN_H := 72.0

static func request(npc_id: String) -> void:
	pending_open = true
	pending_npc = npc_id

func frame_kind() -> int:
	return UiFrame.Kind.SCROLL

func dialog_size() -> Vector2:
	return Vector2(640, 0)

func _build_body() -> void:
	title_label.text = "比武報名"
	head_label = UiBuild.accent(UiBuild.label(body, "", 17, true))
	head_label.name = "TourneyHead"
	events_box = UiBuild.vbox(body, 4)
	events_box.name = "TourneyEvents"
	info_label = UiBuild.label(body, "", 15, true)
	info_label.name = "TourneyInfo"
	bracket_scroll = UiBuild.scroll(body, 120.0)
	bracket_scroll.name = "BracketScroll"
	bracket_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	bracket_box = UiBuild.vbox(bracket_scroll, 2)
	bracket_box.name = "Bracket"
	bracket_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	calendar_label = UiBuild.muted(UiBuild.label(body, "", 14, true))
	calendar_label.name = "TourneyCalendar"
	UiBuild.muted(UiBuild.label(body, RULE_TEXT, 13, true))
	host_box = UiBuild.hbox(body, 6)
	host_box.name = "TourneyHost"
	UiBuild.label(host_box, "主機開辦新的一場，報名時間", 14)
	host_secs = SpinBox.new()
	host_secs.min_value = TourneyRules.HOST_SIGNUP_MIN_S
	host_secs.max_value = TourneyRules.HOST_SIGNUP_MAX_S
	host_secs.step = 30
	host_secs.value = TourneyRules.HOST_SIGNUP_DEFAULT_S
	host_secs.suffix = "秒"
	host_box.add_child(host_secs)
	var hw := UiBuild.button(host_box, "武林大會", func(): _host("WULIN"), 96)
	hw.name = "HostWulin"
	var hs := UiBuild.button(host_box, "本派比武", func(): _host("SECT"), 96)
	hs.name = "HostSect"
	var row := UiBuild.hbox(body, 8)
	var rf := UiBuild.button(row, "重新整理", refresh, 110)
	rf.name = "TourneyRefresh"
	UiBuild.button(row, "關閉", close, 90)

## 報名員選單：記住 NPC 並要一份狀態（主畫面收到 tourney_state 後呼叫 apply_state 並顯示）
func open_for(npc_id: String) -> void:
	ensure_built()
	npc = npc_id
	status_label.text = ""
	visible = true
	if not state.is_empty():
		_render()
	refresh()

func refresh() -> void:
	send(UiKeys.I_TOURNEY_INFO, {})

func apply_state(p: Dictionary) -> void:
	ensure_built()
	state = p.duplicate(true)
	_applied_ms = Time.get_ticks_msec()
	_tick_acc = 0.0
	if pending_npc != "":
		npc = pending_npc
	_render()

# ---------------------------------------------------------------- 純邏輯（單元測試用）
## 階段的中文＋倒數
static func phase_line(ev: Dictionary) -> String:
	var ph := str(ev.get("phase", ""))
	var t := str(PHASE_TEXT.get(ph, ph))
	if ph == "SIGNUP":
		var left := int(ev.get("start_left_s", 0))
		# M3d 審查：倒數是現實時間（日曆那一行是遊戲日），寫清楚免得混淆
		t += "（現實時間約 %s後開打）" % duration_text(left) if left > 0 else "（即將開打）"
	return t

static func duration_text(sec: int) -> String:
	if sec >= 3600:
		return "%d 小時 %d 分" % [sec / 3600, (sec % 3600) / 60]
	if sec >= 60:
		return "%d 分 %d 秒" % [sec / 60, sec % 60]
	return "%d 秒" % sec

## 一場的文字：「甲 對 乙 → 甲（擊倒）」；輪空「甲（輪空）」；未打「甲 對 乙」
static func match_text(m: Dictionary) -> String:
	var a := str(m.get("a", ""))
	var b := str(m.get("b", ""))
	if a == "" or b == "":
		var who := a if a != "" else b
		return "%s（輪空）" % who if who != "" else "（空）"
	var t := "%s 對 %s" % [a, b]
	if bool(m.get("done", false)):
		var w := str(m.get("winner", ""))
		var how := str(HOW_TEXT.get(str(m.get("how", "")), ""))
		t += " → %s" % (w if w != "" else "雙雙判負")
		if how != "" and w != "":
			t += "（%s）" % how
	return t

## 第 n 輪的名稱（從決賽倒數）：決賽、四強、八強、十六強…
static func round_name(i: int, n_rounds: int) -> String:
	var from_end := n_rounds - 1 - i
	match from_end:
		0:
			return "決賽"
		1:
			return "四強"
		2:
			return "八強"
	return "%d 強" % (1 << (from_end + 1))

## 列表只放跟我有關的場次：武林大會、我門派的比武、我報了名的、正在進行的（別派的報名中場次不列）
static func relevant(ev: Dictionary, my_sect_kind: String, signed: Array) -> bool:
	var k := str(ev.get("kind", ""))
	if k == TourneyRules.KIND_WULIN or (k != "" and k == my_sect_kind) or signed.has(k):
		return true
	return str(ev.get("phase", "")) == "RUNNING"

## 全部要打幾輪（依第一輪的場數；對戰表只送到目前這一輪）
static func total_rounds(br: Array) -> int:
	if br.is_empty() or not (br[0] is Array):
		return br.size()
	var m := (br[0] as Array).size()
	var total := 1
	while m > 1:
		m >>= 1
		total += 1
	return maxi(total, br.size())

## 這場不能報名／退出時的原因（列表上直接寫出來；M3d 審查）：別派的比武「限○○弟子」、進行中「報名已截止」、已結束
static func block_text(ev: Dictionary, my_sect_kind: String, signed: Array) -> String:
	var k := str(ev.get("kind", ""))
	var ph := str(ev.get("phase", ""))
	if signed.has(k):
		return ""
	if ph == "RUNNING":
		return "報名已截止"
	if ph == "DONE":
		return "已結束"
	if TourneyRules.is_sect_kind(k) and k != my_sect_kind:
		var sid := TourneyRules.sect_of(k)
		var nm := str(UiClient.row("sects", sid).get("name", "")) if UiClient != null else ""
		if nm == "":
			nm = str(ev.get("kind_name", "")).trim_suffix("門派比武").trim_suffix("比武")
		return "限%s弟子" % nm
	return ""

## 對戰表捲動框的高度：依行數（每行約 22 px），最少一行、最多 300 px（M3d 審查：原本固定 120 px）
static func bracket_height(lines: int) -> float:
	return clampf(lines * 22.0 + 6.0, 28.0, 300.0)

## 視窗太高時對戰表要縮到多高（M3d 審查第三輪：比賽進行中視窗長到 580 px，蓋到底下的 HUD）：
## want＝照行數的高度、others＝視窗其他部分的高度、avail＝可用高度。放得下 → want；放不下 → 縮，最少 BRACKET_MIN_H（再多就捲動）
static func fit_bracket_h(want: float, others: float, avail: float) -> float:
	if avail <= 0.0 or others + want <= avail:
		return want
	return clampf(avail - others, minf(want, BRACKET_MIN_H), want)

## 經過 elapsed_s 秒後的場次（報名倒數往下扣，不小於 0）
static func with_elapsed(ev: Dictionary, elapsed_s: int) -> Dictionary:
	if elapsed_s <= 0 or not ev.has("start_left_s"):
		return ev
	var d := ev.duplicate()
	d["start_left_s"] = maxi(0, int(ev.get("start_left_s", 0)) - elapsed_s)
	return d

func elapsed_s() -> int:
	return int((Time.get_ticks_msec() - _applied_ms) / 1000)

## 可用高度：所在的對話框層的高度（扣掉提示列的位移）；沒有 → 視窗高度扣掉 HUD
func avail_height() -> float:
	if avail_h_override >= 0.0:
		return avail_h_override
	var p := get_parent() as Control
	if p != null and p.size.y > 0.0:
		return p.size.y - FIT_MARGIN
	if is_inside_tree():
		return get_viewport_rect().size.y - HUD_H - FIT_MARGIN
	return 0.0

## 報名條件不合時的說明（主機給的 entry[kind] = { text, why }；why 空＝可以）：「需 實戰 10000 以上、沒有 PK值」
static func entry_block_text(entry: Variant, kind: String) -> String:
	if not (entry is Dictionary) or not ((entry as Dictionary).get(kind) is Dictionary):
		return ""
	var e: Dictionary = entry[kind]
	if str(e.get("why", "")) == "":
		return ""
	return "需%s" % str(e.get("text", ""))

## 這場我能不能報名：報名中、武林大會或我的門派、還沒報
static func can_sign(ev: Dictionary, my_sect_kind: String, signed: Array) -> bool:
	var k := str(ev.get("kind", ""))
	if str(ev.get("phase", "")) != "SIGNUP" or signed.has(k):
		return false
	return k == TourneyRules.KIND_WULIN or (k != "" and k == my_sect_kind)

# ---------------------------------------------------------------- 畫面
func _render() -> void:
	clear_choices()
	_live.clear()
	var el := elapsed_s()
	var s := state
	var kname := str(s.get("kind_name", ""))
	var phase := str(s.get("phase", ""))
	if not bool(s.get("enabled", true)):
		head_label.text = "主機關閉了比武。"
	elif kname == "":
		head_label.text = "目前沒有比武。"
	else:
		var tail := "　【表演賽】" if bool(s.get("exhibition", false)) else ""
		head_label.text = "%s：%s%s" % [kname, TourneyDialog.phase_line(TourneyDialog.with_elapsed(s, el)), tail]
		_live.append([head_label, s, kname + "：", tail])
	# 場次列表
	UiBuild.clear(events_box)
	var signed: Array = s.get("signed", []) if s.get("signed") is Array else []
	var my_sect_kind := str(s.get("my_sect_kind", ""))
	var evs: Array = s.get("events", []) if s.get("events") is Array else []
	var i := 0
	var head_kind := str(s.get("kind", ""))
	for ev in evs:
		# M3d 審查：表頭講的那一場一定列出來（原本表頭寫「報名中」、列表卻說沒有比武）
		if not (ev is Dictionary) or not (TourneyDialog.relevant(ev, my_sect_kind, signed) or str(ev.get("kind", "")) == head_kind):
			continue
		i += 1
		var row := UiBuild.hbox(events_box, 6)
		NumberedDialog.numbered_label(row, i)
		var k := str(ev.get("kind", ""))
		var l := UiBuild.label(row, "%s　%s　%d 人" % [str(ev.get("kind_name", k)), TourneyDialog.phase_line(TourneyDialog.with_elapsed(ev, el)), int(ev.get("n", 0))], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_live.append([l, ev, "%s　" % str(ev.get("kind_name", k)), "　%d 人" % int(ev.get("n", 0))])
		if signed.has(k):
			UiBuild.accent(UiBuild.label(row, "已報名", 14))
			var wb := UiBuild.button(row, "退出", func(): send(UiKeys.I_TOURNEY_WITHDRAW, {}, [], refresh), 64)
			wb.name = "Withdraw_" + k
			add_choice(wb)
		elif TourneyDialog.can_sign(ev, my_sect_kind, signed):
			var need := TourneyDialog.entry_block_text(s.get("entry", {}), k)
			var sb := UiBuild.button(row, "報名", func(): _signup(k), 64)
			sb.name = "Signup_" + k
			sb.disabled = npc == "" or need != ""
			sb.tooltip_text = need if need != "" else ("" if npc != "" else "到西夏比武場休息區找報名員報名")
			add_choice(sb)
			if need != "":
				var nl := UiBuild.muted(UiBuild.label(row, need, 13))
				nl.name = "Need_" + k.replace(":", "_")
			elif npc == "":
				UiBuild.muted(UiBuild.label(row, "找報名員報名", 13))
		else:
			var why := TourneyDialog.block_text(ev, my_sect_kind, signed)
			if why != "":
				var wl := UiBuild.muted(UiBuild.label(row, why, 13))
				wl.name = "Why_" + k.replace(":", "_")
	if i == 0:
		UiBuild.muted(UiBuild.label(events_box, "現在沒有開放報名或進行中的比武。", 15))
	# 對戰表
	UiBuild.clear(bracket_box)
	var br: Array = s.get("bracket", []) if s.get("bracket") is Array else []
	if br.is_empty():
		# M3d 審查：沒有比武時不寫「報名名單：（還沒有人）」（像是有一場可以報）
		var ents: Array = s.get("entrants", []) if s.get("entrants") is Array else []
		if kname != "" and bool(s.get("enabled", true)):
			UiBuild.muted(UiBuild.label(bracket_box, "報名名單：%s" % ("、".join(PackedStringArray(ents)) if not ents.is_empty() else "（還沒有人）"), 14, true))
	else:
		var total := TourneyDialog.total_rounds(br)
		for r in br.size():
			var rl := UiBuild.accent(UiBuild.label(bracket_box, TourneyDialog.round_name(r, total), 15))
			rl.name = "Round%d" % r
			for m in br[r]:
				if m is Dictionary:
					var ml := UiBuild.label(bracket_box, "　" + TourneyDialog.match_text(m), 14)
					if bool(m.get("done", false)) and str(m.get("winner", "")) != "":
						ml.add_theme_color_override("font_color", UiTheme.JY_ROPE_DARK)
	bracket_scroll.visible = bracket_box.get_child_count() > 0
	bracket_scroll.custom_minimum_size = Vector2(0, TourneyDialog.bracket_height(bracket_box.get_child_count()))
	bracket_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# 下一場與名次
	var nm: Dictionary = s.get("next_match", {}) if s.get("next_match") is Dictionary else {}
	var info := ""
	if not nm.is_empty():
		if bool(nm.get("fighting", false)):
			info = "擂臺上：%s 對 %s" % [str(nm.get("a", "")), str(nm.get("b", ""))]
		else:
			info = "下一場：%s 對 %s（點名第 %d 次，三次不到判負）" % [str(nm.get("a", "")), str(nm.get("b", "")), int(nm.get("calls", 0))]
	elif phase == "DONE" and str(s.get("champion", "")) != "":
		info = "冠軍：%s" % str(s.get("champion", ""))
	info_label.text = info
	info_label.visible = info != ""
	# 日曆
	var up: Array = s.get("upcoming", []) if s.get("upcoming") is Array else []
	var parts: PackedStringArray = []
	for u in up:
		if u is Dictionary:
			parts.append("%s：%s" % [str(u.get("kind_name", "")), str(u.get("text", ""))])
	calendar_label.text = ("日曆　" + "　".join(parts)) if not parts.is_empty() else ""
	calendar_label.visible = not parts.is_empty()
	host_box.visible = UiClient.is_admin()
	fit_height()
	call_deferred("fit_height")

## 視窗不能比可用高度高（M3d 審查第三輪）：先讓對戰表照行數，量其他部分，太高就把對戰表縮短（捲動看其餘的）
func fit_height() -> void:
	if bracket_scroll == null or not bracket_scroll.visible:
		return
	var want := TourneyDialog.bracket_height(bracket_box.get_child_count())
	var cur := bracket_scroll.custom_minimum_size.y
	var others := get_combined_minimum_size().y - cur
	var h := TourneyDialog.fit_bracket_h(want, others, avail_height())
	if not is_equal_approx(h, cur):
		bracket_scroll.custom_minimum_size = Vector2(0, h)
		reset_size()

## 每秒把報名倒數往下扣（只改文字，不重建按鈕）
func _process(delta: float) -> void:
	if not visible or _live.is_empty():
		return
	_tick_acc += delta
	if _tick_acc < 1.0:
		return
	_tick_acc = 0.0
	tick_countdown()

func tick_countdown() -> void:
	var el := elapsed_s()
	for e in _live:
		var l := e[0] as Label
		if l == null or not is_instance_valid(l):
			continue
		var t := "%s%s%s" % [str(e[2]), TourneyDialog.phase_line(TourneyDialog.with_elapsed(e[1], el)), str(e[3])]
		if l.text != t:
			l.text = t

func _signup(kind: String) -> void:
	if npc == "":
		status_label.text = "到西夏比武場休息區找報名員報名。"
		return
	send(UiKeys.I_TOURNEY_SIGNUP, { "npc": npc, "kind": kind }, [], refresh)

func _host(which: String) -> void:
	var kind := which
	if which == "SECT":
		var sk := str(state.get("my_sect_kind", ""))
		if sk == "":
			status_label.text = "你沒有門派：只能開辦武林大會。"
			return
		kind = sk
	send(UiKeys.I_TOURNEY_HOST, { "kind": kind, "signup_s": int(host_secs.value) }, [], refresh)

func close() -> void:
	pending_open = false
	super.close()
