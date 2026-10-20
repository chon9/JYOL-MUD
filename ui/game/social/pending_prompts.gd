class_name PendingPrompts
extends VBoxContainer
## 組隊邀請／叫戰提示框（M2_PLAN 4.10、4.5.1）：sheet.pending 有東西就顯示「接受／拒絕」與倒數（真實秒數，本機倒數）。
## 完全由 sheet 重建：重連、換畫面後只要主機的 pending 還在就會再出現。
## 回覆後那一列留在原位、按鈕停用並顯示「已回覆」，等新的 sheet 不再列才移除（M2 審查：立刻移除會讓下面的列
## 往上補到游標底下，連點兩下就誤接了叫戰）；有列移除後 MOVE_GUARD_MS 內的點擊一律不算。
## 接受組隊 → party_reply { from, accept: true }；拒絕 → accept: false；叫戰同理 → challenge_reply。
## M3b：組織邀請（org_invite ui 事件，或 sheet.pending.org_invite）→ org_reply { org, accept }。事件來的邀請記在本機，
## 到期（left_s／ttl_s，預設 60 秒）或回覆後移除；角色表也列同一個組織時以角色表為準。

var gate: IntentGate
var sheet: Dictionary = {}
var rows: Dictionary = {}            # pending_key -> { panel, label, row: Dictionary }
var _answered: Dictionary = {}       # pending_key -> true：已回覆，等主機更新
var _last_tick := -1
var _moved_ms := -100000             # 最後一次有列被移除（其他列跟著移位）的時間
var _org_local: Dictionary = {}      # org id -> { o: 邀請內容, until_ms }（org_invite 事件）
const MOVE_GUARD_MS := 300
const ANSWERED_TEXT := "已回覆"

func _init() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _gate() -> IntentGate:
	if gate == null:
		gate = IntentGate.new()
		add_child(gate)
	return gate

func apply_sheet(s: Dictionary) -> void:
	sheet = s
	# 主機已經不列的提示，回覆標記也清掉
	var live := {}
	for r in UiSocial.pending_rows(s, Time.get_ticks_msec()):
		live[UiSocial.pending_key(r)] = true
	for k in _answered.keys():
		if not live.has(k):
			_answered.erase(k)
	refresh()

## 目前要顯示的提示（含已回覆、等主機更新的列）
func current_rows() -> Array:
	var now := Time.get_ticks_msec()
	var out := UiSocial.pending_rows(sheet, now)
	for org in _org_local.keys():
		var e: Dictionary = _org_local[org]
		var left := ceili(float(int(e["until_ms"]) - now) / 1000.0)
		if left <= 0:
			_org_local.erase(org)
			continue
		var k := "org:%s" % org
		if out.any(func(r): return UiSocial.pending_key(r) == k):
			continue
		var o: Dictionary = (e["o"] as Dictionary).duplicate()
		o["left_s"] = left
		out.append(UiSocial.org_row(o, 0.0))
	return out

## org_invite（ui）事件：{ org, org_name, from_name, left_s? / ttl_s? }
func add_org_invite(p: Dictionary) -> void:
	var org := str(p.get("org", p.get("org_id", "")))
	if org == "":
		return
	var o := p.duplicate()
	o["org"] = org
	var ttl := float(p.get("left_s", p.get("ttl_s", 60)))
	_org_local[org] = { "o": o, "until_ms": Time.get_ticks_msec() + int(maxf(1.0, ttl) * 1000.0) }
	_answered.erase("org:" + org)
	refresh()

## 還能回覆的提示（扣掉已回覆的）
func open_rows() -> Array:
	return current_rows().filter(func(r): return not _answered.has(UiSocial.pending_key(r)))

func refresh() -> void:
	var want := current_rows()
	var keys := {}
	for r in want:
		keys[UiSocial.pending_key(r)] = r
	for k in rows.keys():
		if not keys.has(k):
			var old: Control = rows[k]["panel"]
			rows.erase(k)
			if is_instance_valid(old):
				remove_child(old)
				old.queue_free()
			_moved_ms = Time.get_ticks_msec()
	for k in keys:
		var r: Dictionary = keys[k]
		if not rows.has(k):
			_add_row(k, r)
		var entry: Dictionary = rows[k]
		entry["row"] = r
		var t := UiSocial.pending_head(r)
		if (entry["label"] as Label).text != t:
			(entry["label"] as Label).text = t
			if str(r.get("type", "")) != "challenge":
				(entry["label"] as Label).tooltip_text = t
		var done := _answered.has(k)
		var cd := ANSWERED_TEXT if done else UiSocial.pending_countdown(r)
		if (entry["countdown"] as Label).text != cd:
			(entry["countdown"] as Label).text = cd
		# 已回覆 → 一律停用（IntentGate 收到結果會解鎖，這裡再鎖回去）；回覆失敗（標記被清掉）→ 恢復
		var was_done := bool(entry.get("done", false))
		for key in ["yes", "no"]:
			var btn := entry[key] as Button
			if done:
				btn.disabled = true
			elif was_done:
				btn.disabled = false
		if was_done != done:
			entry["done"] = done
			(entry["panel"] as Control).modulate.a = 0.6 if done else 1.0
	visible = not rows.is_empty()

func _add_row(k: String, r: Dictionary) -> void:
	var panel := UiBuild.framed(self, UiFrame.Kind.INK)
	panel.name = "Prompt_" + k.replace(":", "_")
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UiBuild.vbox(panel, 4)
	# 第一行：整句主文獨佔一行、不換行（M2 第三輪審查：放在按鈕旁邊的固定寬度裡會斷成「…加／入隊伍」、
	# 「（生死自負）」掉到第二行）。名字最長 8 字，整句最多 19 字，放得下；萬一太窄就省略號，滑鼠提示看全文
	var l := UiBuild.label(v, "", 15)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_color_override("font_color", UiTheme.JY_SYS_YELLOW)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# M3b 審查 4：組織邀請、自己有連署中的組織 → 主文下多一行警告（接受＝連署作廢、退手續費）
	var warn := OrgUi.invite_warning(r) if str(r.get("type", "")) == "org" else ""
	if warn != "":
		var wl := UiBuild.label(v, warn, 14)
		wl.name = "OrgWarn"
		wl.autowrap_mode = TextServer.AUTOWRAP_OFF
		wl.clip_text = true
		wl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		wl.add_theme_color_override("font_color", UiTheme.JY_RED)
		wl.tooltip_text = warn
		l.tooltip_text = warn
	# 第二行：倒數（獨立、不換行；M2 審查：「（60」「秒）」被拆成兩行）＋接受／拒絕，靠右
	var h := UiBuild.hbox(v, 8)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(spacer)
	var cd := UiBuild.label(h, "", 15)
	cd.name = "Countdown"
	cd.autowrap_mode = TextServer.AUTOWRAP_OFF
	cd.add_theme_color_override("font_color", UiTheme.JY_SYS_YELLOW)
	var yes := UiBuild.button(h, "接受", Callable(), 64)
	var no := UiBuild.button(h, "拒絕", Callable(), 64)
	if str(r.get("type", "")) == "challenge":
		yes.tooltip_text = UiSocial.CHALLENGE_RISK
		l.tooltip_text = UiSocial.CHALLENGE_RISK
	yes.pressed.connect(func(): answer(k, true))
	no.pressed.connect(func(): answer(k, false))
	rows[k] = { "panel": panel, "label": l, "countdown": cd, "row": r, "yes": yes, "no": no }

## 回覆一個提示；回傳送出的 seq（-1 = 沒送）
func answer(k: String, accept: bool) -> int:
	if not rows.has(k) or _answered.has(k):
		return -1
	# 剛有列移除、其他列移位到游標底下：這次點擊不算（防連點誤接）
	if Time.get_ticks_msec() - _moved_ms < MOVE_GUARD_MS:
		return -1
	var r: Dictionary = rows[k]["row"]
	var kind := UiKeys.I_PARTY_REPLY if str(r.get("type", "")) == "party" else UiKeys.I_CHALLENGE_REPLY
	var args := { "from": str(r.get("from_char", "")), "accept": accept }
	if str(r.get("type", "")) == "org":
		kind = UiKeys.I_ORG_REPLY
		args = { "org": str(r.get("org", r.get("from_char", ""))), "accept": accept }
	_answered[k] = true
	var lock: Array = [rows[k]["yes"], rows[k]["no"]]
	var is_org := str(r.get("type", "")) == "org"
	var org_id := str(args.get("org", ""))
	var seq := _gate().send(kind, args, lock, func(ok: bool, _reason: String):
		if not ok:
			_answered.erase(k)   # 失敗（例如邀請已失效）：交給新的 sheet 決定要不要再顯示
		if is_org:
			_org_local.erase(org_id)   # 組織邀請：回覆過（或已失效）就不再顯示本機記下的那一筆
		refresh())
	refresh()
	return seq

func _process(_delta: float) -> void:
	if sheet.is_empty():
		return
	var tick := Time.get_ticks_msec() / 250
	if tick != _last_tick:
		_last_tick = tick
		refresh()
