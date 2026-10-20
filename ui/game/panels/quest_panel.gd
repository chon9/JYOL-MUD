class_name QuestPanel
extends VBoxContainer
## 任務窗（M1_PLAN 3.12；AUTHENTIC_UI_SPEC §8.5：原作沒有燈籠，從指令窗「雜項」或 Ctrl+6 開，玉石框）。
## 故事包升級（STORY_PLAN §6.2）：
## - 上方兩個分頁鈕「進行中」「已完成」。
## - 左欄依 chapter 分組（點章名收合／展開），右欄是選中任務的內容：
##   進行中：任務說明（去哪裡做）、目前階段標題與 log、目標清單（have/need，完成打 ◎）、已走過的階段（灰字）、
##   護送對象、提示地點（點了 hint_requested(room) → 主畫面在地圖上標記）、放棄（確認）。
##   已完成：結局名、完成次數；可重複任務顯示冷卻剩餘（遊戲時辰，sheet.quest_cd）。
## - 角色表的任務列：新格式 { id, name, chapter, stage, stage_title, log, objectives:[{text,have,need,done}], hint_room, escort }；
##   舊格式 { id, name, giver_name, text, steps } 照樣顯示（WP-ENGINE 未合併、舊主機）。
##   quests_done：新格式 [{ id, name, chapter, outcome_label, n }]，舊格式 [qid]。
## - 已走過的階段：角色表只給目前階段，這裡記下看過的階段（本次上線），再用本機任務資料從 start 順著 next 補齊前面的階段。

signal hint_requested(room_id: String)

const TAB_ACTIVE := "active"
const TAB_DONE := "done"
const LIST_W := 220.0

var gate: IntentGate
var feedback: PanelFeedback
var sheet: Dictionary = {}
var tab := TAB_ACTIVE
var selected := ""                    # 目前選中的任務 id
var collapsed: Dictionary = {}        # chapter -> true（收合）
var history: Dictionary = {}          # qid -> [{ stage, title, log }]（看過的階段，依先後）
var tab_buttons: Dictionary = {}      # tab -> Button
var list_box: VBoxContainer
var detail_box: VBoxContainer
var quest_buttons: Dictionary = {}    # qid -> Button（左欄）
var confirm_row: HBoxContainer
var confirm_label: Label
var _pending_abandon := ""
var _built := false

func _ready() -> void:
	if not _built:
		_build()

func _gate() -> IntentGate:
	if gate == null:
		gate = IntentGate.new()
		add_child(gate)
	return gate

## 面板動作的結果回饋（失敗原因、成功訊息）；主畫面會塞共用的回饋列，單獨使用時自己建一個
func _fb() -> PanelFeedback:
	if feedback == null or not is_instance_valid(feedback):
		feedback = PanelFeedback.new()
		add_child(feedback)
	return feedback

func _send(kind: String, args: Dictionary, lock: Array = []) -> int:
	var fb := _fb()
	fb.begin()
	return _gate().send(kind, args, lock, func(ok: bool, reason: String):
		if is_instance_valid(fb):
			fb.show_result(ok, reason))

func _build() -> void:
	_built = true
	add_theme_constant_override("separation", 6)
	var tabs := UiBuild.hbox(self, 8)
	for t in [[TAB_ACTIVE, "進行中"], [TAB_DONE, "已完成"]]:
		var b := UiBuild.button(tabs, t[1], set_tab.bind(t[0]), 96)
		b.name = "Tab_" + str(t[0])
		tab_buttons[t[0]] = b
	var row := UiBuild.hbox(self, 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lf := UiBuild.framed(row, UiFrame.Kind.INK)
	lf.custom_minimum_size = Vector2(LIST_W, 0)
	var lsc := UiBuild.scroll(lf, 260)
	list_box = UiBuild.vbox(lsc, 2)
	list_box.name = "QuestList"
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rf := UiBuild.framed(row, UiFrame.Kind.INK)
	rf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rsc := UiBuild.scroll(rf, 260)
	detail_box = UiBuild.vbox(rsc, 6)
	detail_box.name = "QuestDetail"
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_row = UiBuild.hbox(self, 8)
	confirm_label = UiBuild.label(confirm_row, "", 16)
	UiBuild.button(confirm_row, "確定放棄", _on_confirm)
	UiBuild.button(confirm_row, "取消", func(): confirm_row.visible = false)
	confirm_row.visible = false
	_paint_tabs()

func set_tab(t: String) -> void:
	if not _built:
		_build()
	if tab != t:
		tab = t
		selected = ""
	_paint_tabs()
	refresh()

func _paint_tabs() -> void:
	for k in tab_buttons:
		(tab_buttons[k] as Button).add_theme_color_override("font_color", UiTheme.CINNABAR if k == tab else UiTheme.JY_BTN_TEXT)

# ---------------------------------------------------------------- 資料

func apply_sheet(s: Dictionary) -> void:
	if not _built:
		_build()
	sheet = s
	_record_history()
	refresh()

func active_rows() -> Array:
	return (sheet.get("quests", []) as Array).filter(func(q): return q is Dictionary) if sheet.get("quests", []) is Array else []

## 已完成：新格式的字典，舊格式（qid 字串）轉成 { id, name }
func done_rows() -> Array:
	var out: Array = []
	var src: Variant = sheet.get("quests_done", [])
	if not (src is Array):
		return out
	for d in src:
		if d is Dictionary:
			out.append(d)
		elif d is String or d is StringName:
			out.append({ "id": str(d), "name": UiClient.name_of("quests", str(d)) })
	return out

func _rows() -> Array:
	return active_rows() if tab == TAB_ACTIVE else done_rows()

## 記下看過的階段（階段換了就加一筆）
func _record_history() -> void:
	var live := {}
	for q in active_rows():
		var qid := str(q.get("id", ""))
		var stage := str(q.get("stage", ""))
		live[qid] = true
		if stage == "":
			continue
		var h: Array = history.get(qid, [])
		if h.is_empty() or str(h[h.size() - 1]["stage"]) != stage:
			h.append({ "stage": stage, "title": str(q.get("stage_title", "")), "log": str(q.get("log", "")) })
		else:
			h[h.size() - 1]["title"] = str(q.get("stage_title", ""))
			h[h.size() - 1]["log"] = str(q.get("log", ""))
		history[qid] = h
	for qid in history.keys():
		if not live.has(qid):
			history.erase(qid)   # 完成、放棄、失敗：重接時從頭記

## 已走過的階段（不含目前階段）：本機資料從 start 順著 next 走到目前階段（條件分支用看過的紀錄選路），再併入本次看過的
func past_stages(q: Dictionary) -> Array:
	var qid := str(q.get("id", ""))
	var cur := str(q.get("stage", ""))
	var seen: Array = history.get(qid, [])
	var seen_ids := {}
	for h in seen:
		seen_ids[str(h["stage"])] = h
	var out: Array = []
	var def := StoryUi.quest_def(qid)
	var stages: Array = def.get("stages", []) if def.get("stages", []) is Array else []
	if cur != "" and not stages.is_empty():
		var s := str(def.get("start", ""))
		var guard := 0
		while s != "" and s != cur and not s.begins_with("END") and guard < 64:
			guard += 1
			var st := StoryUi.stage_def(def, s)
			if st.is_empty():
				break
			out.append({ "stage": s, "title": str(st.get("title", "")), "log": str(st.get("log", "")) })
			s = _next_stage(st.get("next", ""), seen_ids, cur)
	var have := {}
	for o in out:
		have[str(o["stage"])] = true
	for h in seen:
		var sid := str(h["stage"])
		if sid != cur and not have.has(sid):
			out.append(h)
			have[sid] = true
	return out

## next 是字串 → 照走；是條件陣列 → 走到目前階段或看過的那一支，看不出來就停
static func _next_stage(nx: Variant, seen_ids: Dictionary, cur: String) -> String:
	if nx is String:
		return str(nx)
	if nx is Array:
		for br in nx:
			if br is Dictionary:
				var g := str(br.get("goto", ""))
				if g == cur or seen_ids.has(g):
					return g
	return ""

# ---------------------------------------------------------------- 畫面

func refresh() -> void:
	if not _built:
		return
	var rows := _rows()
	if selected == "" or not rows.any(func(q): return str(q.get("id", "")) == selected):
		selected = str(rows[0].get("id", "")) if not rows.is_empty() else ""
	_build_list(rows)
	_build_detail(rows)

## 左欄：章 → 任務
func _build_list(rows: Array) -> void:
	UiBuild.clear(list_box)
	quest_buttons.clear()
	if rows.is_empty():
		UiBuild.muted(UiBuild.label(list_box, "（目前沒有任務）" if tab == TAB_ACTIVE else "（還沒完成任何任務）", 15))
		return
	var order: Array = []
	var groups := {}
	for q in rows:
		var c := StoryUi.chapter_of(q)
		if not groups.has(c):
			groups[c] = []
			order.append(c)
		groups[c].append(q)
	for c in order:
		var folded := bool(collapsed.get(c, false))
		var hb := UiBuild.button(list_box, "%s %s（%d）" % ["▶" if folded else "▼", c, (groups[c] as Array).size()])
		hb.name = "Chapter_" + c
		hb.flat = true
		hb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		hb.add_theme_color_override("font_color", UiTheme.JY_LABEL)
		hb.add_theme_font_size_override("font_size", 15)
		hb.tooltip_text = "收合／展開"
		hb.pressed.connect(toggle_chapter.bind(c))
		if folded:
			continue
		for q in groups[c]:
			var qid := str(q.get("id", ""))
			var t := "　" + str(q.get("name", UiClient.name_of("quests", qid)))
			if tab == TAB_DONE and UiBuild.num(q.get("n", 1)) > 1:
				t += "×%d" % UiBuild.num(q.get("n", 1))
			var b := UiBuild.button(list_box, t)
			b.name = "Quest_" + qid
			b.flat = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 15)
			b.clip_text = true
			# 審查修正：沒選中的列也要設字色（flat 按鈕預設是深褐色字，在黑底清單上幾乎看不見，對比約 1.4:1）
			b.add_theme_color_override("font_color", UiTheme.JY_SYS_YELLOW if qid == selected else UiTheme.JY_TEXT)
			b.add_theme_color_override("font_hover_color", UiTheme.JY_LABEL)
			b.add_theme_color_override("font_pressed_color", UiTheme.JY_SYS_YELLOW)
			b.add_theme_color_override("font_focus_color", UiTheme.JY_SYS_YELLOW if qid == selected else UiTheme.JY_TEXT)
			b.pressed.connect(select_quest.bind(qid))
			quest_buttons[qid] = b

func toggle_chapter(c: String) -> void:
	collapsed[c] = not bool(collapsed.get(c, false))
	refresh()

func select_quest(qid: String) -> void:
	selected = qid
	refresh()

func _row(rows: Array, qid: String) -> Dictionary:
	for q in rows:
		if str(q.get("id", "")) == qid:
			return q
	return {}

func _build_detail(rows: Array) -> void:
	UiBuild.clear(detail_box)
	var q := _row(rows, selected)
	if q.is_empty():
		UiBuild.muted(UiBuild.label(detail_box, "（點左邊的任務看詳情）" if not rows.is_empty() else "", 15))
		return
	if tab == TAB_ACTIVE:
		_detail_active(q)
	else:
		_detail_done(q)

func _detail_active(q: Dictionary) -> void:
	var qid := str(q.get("id", ""))
	var qname := str(q.get("name", UiClient.name_of("quests", qid)))
	var head := UiBuild.hbox(detail_box, 8)
	var t := UiBuild.label(head, qname, 19)
	t.name = "QuestName"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_color_override("font_color", UiTheme.JY_GOLD_LIGHT)
	var ab := UiBuild.button(head, "放棄", func(): ask_abandon(qid, qname))
	ab.name = "Abandon"
	var giver := str(q.get("giver_name", ""))
	if giver == "":
		giver = UiClient.name_of("npcs", str(StoryUi.quest_def(qid).get("giver", "")), "")
	var sub: PackedStringArray = [StoryUi.chapter_of(q)]
	if giver != "":
		sub.append("委託：" + giver)
	UiBuild.muted(UiBuild.label(detail_box, "　".join(sub), 14))
	# 任務說明（去哪裡、做什麼）：角色表的 text → 本機資料
	var desc := str(q.get("text", ""))
	if desc == "":
		desc = str(StoryUi.quest_def(qid).get("text", ""))
	if desc != "":
		var dl := UiBuild.label(detail_box, desc, 15, true)
		dl.name = "QuestText"
	# 目前階段
	var stitle := str(q.get("stage_title", ""))
	var log_text := str(q.get("log", ""))
	if stitle != "" or log_text != "":
		detail_box.add_child(HSeparator.new())
		if stitle != "":
			var st := UiBuild.accent(UiBuild.label(detail_box, "目前：" + stitle, 17))
			st.name = "StageTitle"
		if log_text != "":
			var ll := UiBuild.label(detail_box, log_text, 15, true)
			ll.name = "StageLog"
	# 目標（新：objectives；舊：steps）
	var objs: Variant = q.get("objectives", q.get("steps", []))
	if objs is Array:
		for o in objs:
			if o is Dictionary:
				UiBuild.label(detail_box, QuestPanel.objective_text(o), 15, true)
	# 護送
	var esc := QuestPanel.escort_name(q.get("escort", ""))
	if esc != "":
		var el := UiBuild.label(detail_box, "護送：%s（隨行中，別走散了）" % esc, 15, true)
		el.name = "Escort"
		el.add_theme_color_override("font_color", UiTheme.JY_LABEL)
	# 提示地點
	var hint := str(q.get("hint_room", ""))
	if hint != "":
		var hb := UiBuild.button(detail_box, "在地圖上標出：%s" % StoryUi.room_label(hint))
		hb.name = "HintRoom"
		hb.tooltip_text = "打開地圖並標記這個地點"
		hb.pressed.connect(func(): hint_requested.emit(hint))
	# 已走過的階段（灰字）
	var past := past_stages(q)
	if not past.is_empty():
		detail_box.add_child(HSeparator.new())
		UiBuild.muted(UiBuild.label(detail_box, "已走過", 14))
		for h in past:
			var line := "✓ %s" % str(h.get("title", ""))
			if str(h.get("log", "")) != "":
				line += "：" + str(h["log"])
			var pl := UiBuild.muted(UiBuild.label(detail_box, line, 14, true))
			pl.name = "Past_" + str(h.get("stage", ""))

func _detail_done(q: Dictionary) -> void:
	var qid := str(q.get("id", ""))
	var t := UiBuild.label(detail_box, str(q.get("name", UiClient.name_of("quests", qid))), 19)
	t.name = "QuestName"
	t.add_theme_color_override("font_color", UiTheme.JY_GOLD_LIGHT)
	UiBuild.muted(UiBuild.label(detail_box, StoryUi.chapter_of(q), 14))
	var ol := str(q.get("outcome_label", ""))
	if ol != "":
		var l := UiBuild.label(detail_box, "結局：" + ol, 16, true)
		l.name = "Outcome"
	var n := UiBuild.num(q.get("n", 1))
	UiBuild.label(detail_box, "完成 %d 次" % maxi(1, n), 15)
	var desc := str(StoryUi.quest_def(qid).get("text", ""))
	if desc != "":
		UiBuild.muted(UiBuild.label(detail_box, desc, 14, true))
	var left := StoryUi.cooldown_left({ "id": qid }, sheet)
	if left > 0.0:
		var cl := UiBuild.label(detail_box, "可再接：還要%s" % StoryUi.span_text(left), 15, true)
		cl.name = "Cooldown"
		cl.add_theme_color_override("font_color", UiTheme.JY_LABEL)

## 目標一行：「◎ 到藥鋪找李台安」「・擊敗山賊（1/3）」
static func objective_text(o: Dictionary) -> String:
	var mark := "◎" if bool(o.get("done", false)) else "・"
	var need := UiBuild.num(o.get("need", 0))
	var prog := "（%d/%d）" % [mini(UiBuild.num(o.get("have", 0)), need), need] if need > 0 else ""
	return "　%s %s%s" % [mark, str(o.get("text", "")), prog]

## 角色表的 escort：npc id（查名字）、名字字串、或 { npc, name }
static func escort_name(v: Variant) -> String:
	if v is Dictionary:
		return str((v as Dictionary).get("name", UiClient.name_of("npcs", str((v as Dictionary).get("npc", "")), "")))
	if v is Array:
		var names: PackedStringArray = []
		for x in v:
			var n := escort_name(x)
			if n != "":
				names.append(n)
		return "、".join(names)
	var s := str(v) if v != null else ""
	if s == "":
		return ""
	return UiClient.name_of("npcs", s, s)

func ask_abandon(qid: String, qname: String) -> void:
	_pending_abandon = qid
	confirm_label.text = "確定放棄「%s」？任務給的物品會被收回。" % qname
	confirm_row.visible = true

func _on_confirm() -> void:
	confirm_row.visible = false
	if _pending_abandon != "":
		_send(UiKeys.I_QUEST_ABANDON, { "quest": _pending_abandon })
	_pending_abandon = ""
