class_name RogueScreen
extends UiScreen
## 江湖試煉畫面（ROGUE_PLAN §5.2–§5.5；WP-UI）【設計提案・非原作】。
## 畫面狀態：LOBBY（沒有主機：唯讀試煉者檔案）→ ALLOC（分配屬性、名字）→ PICK（三張卡）→ READY（出戰／放棄）
## → BATTLE（疊上 battle_screen.tscn；上方一條細列：第 N 回合、隊友氣）→ 勝：PICK；敗／放棄：OVER（結算）。
## 主機權威：畫面只送 intent（rogue_open／rogue_start／rogue_pick／rogue_fight／rogue_abandon／equip）、
## 依 rogue_state（§6.3）切換；卡面文字全部來自主機。
## 鍵盤：PICK 時 1／2／3（含數字鍵盤）選卡、Enter 確認；ALLOC 與屬性分配窗 Enter＝確定；READY 時 Enter＝出戰；OVER 時 Enter＝再戰一場；
## 放棄確認窗裡 Enter＝再想想（放棄只能點）；Esc＝取消選取（或關掉屬性分配窗、放棄確認）。
## LOBBY：Enter＝開始試煉、Esc＝返回標題。屬性分配窗與放棄確認是強制回應的：後面墊一層擋滑鼠的暗幕（審查）。

const BATTLE_SCENE := "res://ui/game/battle/battle_screen.tscn"
const STRIP_H := 36.0
const MSG_LINES := 4
const CARD_GAP := 24

var view := UiKeys.ROGUE_VIEW_LOBBY     # LOBBY／ALLOC／PICK／READY／BATTLE／OVER
var state: Dictionary = {}               # 最近一次 rogue_state
var summary: Dictionary = {}             # 最近一次 rogue_over（或 state.summary）
var selected_idx := -1
var _cards_key := ""
var _alloc_key := ""
var _open_pending := false              # 已開主機，等 welcome 再送 rogue_open

## 測試注入：開主機（func(seed:int) -> Error）、換畫面（func(scene:String)）、離開主機（func()）
var starter: Callable = Callable()
var navigator: Callable = Callable()
var leaver: Callable = Callable()

var root_box: HBoxContainer
var hud: RogueHud
var content: Control
var lobby: RogueLobbyPanel
var alloc_panel: RogueAllocPanel
var pick_box: VBoxContainer
var pick_title: Label
var pick_hint: Label
var cards_row: HBoxContainer
var cards: Array = []                    # RogueCard
var pick_button: Button
var pick_abandon_button: Button
var ready_box: VBoxContainer
var ready_title: Label
var ready_boss: Label
var fight_button: Button
var abandon_button: Button
var summary_panel: RogueSummaryPanel
var attr_popup: RogueAllocPanel          # 屬性卡的分配小窗
var attr_idx := -1                       # 屬性分配窗是替哪一張卡開的（開窗時記住；審查）
var popup_layer: Control
var popup_backdrop: ColorRect            # 浮層開著時擋住後面的卡片與按鈕
var confirm_panel: PanelContainer        # 放棄確認
var confirm_yes: Button
var confirm_no: Button
var msg_label: Label
var err_label: Label
var messages: Array = []
var battle: BattleScreen
var strip: PanelContainer                # 戰鬥時上方細列
var strip_round: Label
var strip_allies: HBoxContainer

func _ready() -> void:
	requires_session = false
	_build()
	UiClient.connect_signal("welcomed", _on_welcomed)
	UiClient.connect_signal("events_received", handle_events)
	UiClient.connect_signal("battle_opened", open_battle)
	UiClient.connect_signal("battle_closed", close_battle)
	UiClient.connect_signal("sheet_changed", _on_sheet)
	show_error(take_router_message())
	show_lobby()

func _exit_tree() -> void:
	super._exit_tree()
	UiClient.disconnect_signal("welcomed", _on_welcomed)
	UiClient.disconnect_signal("events_received", handle_events)
	UiClient.disconnect_signal("battle_opened", open_battle)
	UiClient.disconnect_signal("battle_closed", close_battle)
	UiClient.disconnect_signal("sheet_changed", _on_sheet)

# ---------------------------------------------------------------- 版面

func _build() -> void:
	var m := UiBuild.margin(self, 12)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var outer := UiBuild.vbox(m, 8)
	root_box = UiBuild.hbox(outer, 12)
	root_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hud = RogueHud.new()
	hud.name = "RogueHud"
	hud.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hud.equip_requested.connect(_on_equip)
	root_box.add_child(hud)
	content = CenterContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(content)
	var stack := UiBuild.vbox(content, 0)
	# LOBBY
	lobby = RogueLobbyPanel.new()
	lobby.name = "Lobby"
	lobby.start_requested.connect(start_trial)
	lobby.title_requested.connect(back_to_title)
	stack.add_child(lobby)
	# ALLOC
	alloc_panel = RogueAllocPanel.new()
	alloc_panel.name = "Alloc"
	alloc_panel.confirmed.connect(_on_alloc_confirmed)
	alloc_panel.rerolled.connect(send_open)
	stack.add_child(alloc_panel)
	# PICK
	pick_box = UiBuild.vbox(stack, 14)
	pick_box.name = "Pick"
	pick_title = UiBuild.title(pick_box, "")
	pick_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pick_hint = UiBuild.muted(UiBuild.label(pick_box, "點一張卡選取，再點一次或按「選定」；鍵盤 1／2／3 選卡、Enter 確認。", 14))
	pick_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cards_row = UiBuild.hbox(pick_box, CARD_GAP)
	cards_row.name = "Cards"
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var prow := UiBuild.hbox(pick_box, 16)
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	pick_button = UiBuild.button(prow, "選定", confirm_pick, 140)
	pick_button.name = "PickConfirm"
	pick_abandon_button = UiBuild.button(prow, "放棄試煉", ask_abandon, 140)
	pick_abandon_button.name = "PickAbandon"
	# READY
	ready_box = UiBuild.vbox(stack, 14)
	ready_box.name = "Ready"
	var rframe := UiBuild.framed(ready_box, UiFrame.Kind.INK)
	var rv := UiBuild.vbox(rframe, 10)
	rv.custom_minimum_size = Vector2(420, 0)
	ready_title = UiBuild.title(rv, "")
	ready_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_boss = UiBuild.label(rv, "下一場：名人登場", 20)
	ready_boss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_boss.add_theme_color_override("font_color", UiTheme.JY_RED)
	ready_boss.add_theme_font_override("font", UiTheme.brush_font(0.5))
	var rhint := UiBuild.muted(UiBuild.label(rv, "出戰前可以在左邊換兵器。試煉中不能逃跑；按 Enter 出戰。", 14, true))
	rhint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rrow := UiBuild.hbox(rv, 16)
	rrow.alignment = BoxContainer.ALIGNMENT_CENTER
	fight_button = UiBuild.button(rrow, "出戰", fight, 140)
	fight_button.name = "Fight"
	abandon_button = UiBuild.button(rrow, "放棄試煉", ask_abandon, 140)
	abandon_button.name = "Abandon"
	# OVER
	summary_panel = RogueSummaryPanel.new()
	summary_panel.name = "Summary"
	summary_panel.again_requested.connect(send_open)
	summary_panel.title_requested.connect(back_to_title)
	stack.add_child(summary_panel)
	# 訊息列
	var mrow := UiBuild.vbox(outer, 2)
	msg_label = UiBuild.label(mrow, "", 15, true)
	msg_label.name = "Messages"
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	err_label = UiBuild.error(UiBuild.label(mrow, "", 15, true))
	err_label.name = "Error"
	err_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 浮層：屬性卡分配窗、放棄確認
	popup_layer = Control.new()
	popup_layer.name = "Popups"
	popup_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(popup_layer)
	popup_backdrop = ColorRect.new()
	popup_backdrop.name = "Backdrop"
	popup_backdrop.color = Color(0, 0, 0, 0.45)
	popup_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	popup_backdrop.visible = false
	popup_layer.add_child(popup_backdrop)
	var pc := CenterContainer.new()
	pc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_layer.add_child(pc)
	var pstack := UiBuild.vbox(pc, 0)
	attr_popup = RogueAllocPanel.new()
	attr_popup.name = "AttrPopup"
	attr_popup.visible = false
	attr_popup.confirmed.connect(_on_attr_confirmed)
	attr_popup.cancelled.connect(func(): attr_popup.visible = false)
	attr_popup.visibility_changed.connect(_sync_backdrop)
	pstack.add_child(attr_popup)
	confirm_panel = UiBuild.framed(pstack, UiFrame.Kind.INK)
	confirm_panel.name = "AbandonConfirm"
	confirm_panel.visible = false
	confirm_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	confirm_panel.visibility_changed.connect(_sync_backdrop)
	var cv := UiBuild.vbox(confirm_panel, 10)
	cv.custom_minimum_size = Vector2(380, 0)
	UiBuild.title(cv, "放棄試煉？").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ct := UiBuild.label(cv, "這一局就此結束；已經打贏的場次照樣換成永久屬性點。", 15, true)
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var crow := UiBuild.hbox(cv, 16)
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	confirm_yes = UiBuild.button(crow, "放棄", abandon, 120)
	confirm_yes.name = "AbandonYes"
	confirm_no = UiBuild.button(crow, "再想想", func(): confirm_panel.visible = false, 120)
	confirm_no.name = "AbandonNo"
	# 戰鬥細列（戰鬥畫面上方）
	strip = UiBuild.framed(self, UiFrame.Kind.INK)
	strip.name = "BattleStrip"
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.offset_bottom = STRIP_H
	strip.visible = false
	var sh := UiBuild.hbox(strip, 14)
	strip_round = UiBuild.label(sh, "", 16)
	strip_round.add_theme_color_override("font_color", UiTheme.JY_GOLD_LIGHT)
	strip_allies = UiBuild.hbox(sh, 14)

## 浮層（屬性分配窗、放棄確認）開著 → 暗幕擋滑鼠
func _sync_backdrop() -> void:
	if popup_backdrop != null:
		popup_backdrop.visible = (attr_popup != null and attr_popup.visible) or (confirm_panel != null and confirm_panel.visible)

func popup_open() -> bool:
	return popup_backdrop != null and popup_backdrop.visible

# ---------------------------------------------------------------- 狀態

func _show_only(n: Control) -> void:
	for c in [lobby, alloc_panel, pick_box, ready_box, summary_panel]:
		(c as Control).visible = c == n

func show_lobby() -> void:
	view = UiKeys.ROGUE_VIEW_LOBBY
	hud.visible = false
	_show_only(lobby)
	var smn := get_node_or_null("/root/SaveManager")
	var root_dir := str(smn.get("root_dir")) if smn != null else ""
	lobby.apply_profile(RogueLobbyPanel.read_profile(root_dir) if root_dir != "" else RogueLobbyPanel.default_profile())

## rogue_state（§6.3）
func apply_state(st: Dictionary) -> void:
	state = st.duplicate(true)
	var phase := str(st.get("phase", ""))
	if not UiKeys.ROGUE_PHASES.has(phase):
		return
	view = phase
	hud.visible = phase in [UiKeys.ROGUE_PHASE_PICK, UiKeys.ROGUE_PHASE_READY, UiKeys.ROGUE_PHASE_BATTLE]
	if hud.visible:
		hud.apply(state, UiClient.sheet())
	if phase != UiKeys.ROGUE_PHASE_PICK:
		attr_popup.visible = false
	if phase != UiKeys.ROGUE_PHASE_PICK and phase != UiKeys.ROGUE_PHASE_READY:
		confirm_panel.visible = false
	match phase:
		UiKeys.ROGUE_PHASE_ALLOC:
			_show_only(alloc_panel)
			var key := "%s|%s|%d" % [str(st.get("run_id", "")), JSON.stringify(st.get("roll", {})), UiBuild.num(st.get("alloc_points", 0))]
			if key != _alloc_key:
				_alloc_key = key
				alloc_panel.setup(st.get("roll", {}) if st.get("roll") is Dictionary else {}, UiBuild.num(st.get("alloc_points", 0)),
					_attr_cap(), true)
		UiKeys.ROGUE_PHASE_PICK:
			_show_only(pick_box)
			_apply_cards()
		UiKeys.ROGUE_PHASE_READY:
			_show_only(ready_box)
			ready_title.text = "第 %d 回合・準備出戰" % maxi(1, UiBuild.num(st.get("round", 1)))
			ready_boss.visible = bool(st.get("next_round_is_boss", false))
		UiKeys.ROGUE_PHASE_BATTLE:
			pass   # 戰鬥畫面疊在上面；底下保持原樣
		UiKeys.ROGUE_PHASE_OVER:
			var sm: Variant = st.get("summary", {})
			if sm is Dictionary and not (sm as Dictionary).is_empty():
				summary = sm
			_show_over()
	_update_strip()

func _attr_cap() -> int:
	var c := UiBuild.num(state.get("attr_cap", 0))
	return c if c > 0 else UiKeys.ROGUE_ATTR_CAP

func _show_over() -> void:
	view = UiKeys.ROGUE_PHASE_OVER
	hud.visible = false
	_show_only(summary_panel)
	summary_panel.apply_summary(summary)

func _apply_cards() -> void:
	var list: Array = state.get("cards", []) if state.get("cards") is Array else []
	var boss_reward := UiBuild.num(state.get("extra_picks", 0)) > 0 or str(state.get("min_rarity", "")) != ""
	pick_title.text = "名人敗退，再選一張" if boss_reward else "第 %d 回合・選一張" % maxi(1, UiBuild.num(state.get("round", 1)))
	var key := JSON.stringify(list) + "|" + str(state.get("round", 0)) + "|" + str(state.get("extra_picks", 0))
	if key == _cards_key and cards.size() == list.size():
		return
	_cards_key = key
	UiBuild.clear(cards_row)
	cards = []
	selected_idx = -1
	for i in list.size():
		if not (list[i] is Dictionary):
			continue
		var cd: Dictionary = (list[i] as Dictionary).duplicate()
		if not cd.has("idx"):
			cd["idx"] = i
		var c := RogueCard.new(cd)
		c.name = "Card%d" % i
		c.clicked.connect(select_card)
		c.activated.connect(func(_i: int): confirm_pick())
		cards_row.add_child(c)
		cards.append(c)
	_refresh_pick_button()

func _refresh_pick_button() -> void:
	pick_button.disabled = selected_idx < 0

## 選第 idx 張（卡片快照的 idx；-1＝取消選取）
func select_card(idx: int) -> void:
	if popup_open():
		return   # 浮層開著不能換卡（審查：換了卡，分配窗的點數會送到另一張卡）
	selected_idx = -1
	for c in cards:
		var on: bool = (c as RogueCard).idx == idx
		(c as RogueCard).set_selected(on)
		if on:
			selected_idx = idx
	_refresh_pick_button()

func card_at(idx: int) -> RogueCard:
	for c in cards:
		if (c as RogueCard).idx == idx:
			return c
	return null

## 「選定」：屬性卡先開分配窗（點數要用完）；其他直接送 rogue_pick
func confirm_pick() -> void:
	var c := card_at(selected_idx)
	if c == null or view != UiKeys.ROGUE_PHASE_PICK or popup_open():
		return
	if c.kind == "ATTR":
		var attrs: Variant = state.get("attrs", UiClient.sheet().get("attrs", {}))
		attr_popup.setup(attrs if attrs is Dictionary else {}, UiBuild.num(c.data.get("points", 0)), _attr_cap(), false)
		attr_idx = c.idx
		attr_popup.visible = true
		return
	send(UiKeys.I_ROGUE_PICK, { "idx": c.idx }, [pick_button], _on_result)

func _on_attr_confirmed(alloc: Dictionary) -> void:
	var c := card_at(attr_idx)
	if c == null or c.kind != "ATTR":
		return
	attr_popup.visible = false
	send(UiKeys.I_ROGUE_PICK, { "idx": c.idx, "alloc": alloc }, [pick_button], _on_result)

func _on_alloc_confirmed(alloc: Dictionary) -> void:
	send(UiKeys.I_ROGUE_START, { "alloc": alloc, "name": alloc_panel.player_name(), "gender": alloc_panel.gender(),
		"look": alloc_panel.look() }, [alloc_panel.confirm_button, alloc_panel.reroll_button], _on_result)

func fight() -> void:
	if view != UiKeys.ROGUE_PHASE_READY:
		return
	send(UiKeys.I_ROGUE_FIGHT, {}, [fight_button, abandon_button], _on_result)

func ask_abandon() -> void:
	if view in [UiKeys.ROGUE_PHASE_PICK, UiKeys.ROGUE_PHASE_READY]:
		confirm_panel.visible = true

func abandon() -> void:
	confirm_panel.visible = false
	send(UiKeys.I_ROGUE_ABANDON, { "confirm": true }, [abandon_button, pick_abandon_button], _on_result)

func _on_equip(uid: String) -> void:
	var b: Variant = hud.equip_buttons.get(uid, null)
	send(UiKeys.I_EQUIP, { "item_uid": uid }, [b] if b != null else [], _on_result)

## 「開始試煉」：開試煉主機（NetworkManager.start_rogue），welcome 後送 rogue_open
func start_trial() -> void:
	show_error("")
	var err := ERR_UNAVAILABLE
	if starter.is_valid():
		err = starter.call(0)
	else:
		var nm := _nm()
		if nm != null and nm.has_method("start_rogue"):
			err = nm.call("start_rogue", 0)
		else:
			show_error("江湖試煉還沒有準備好。")
			return
	if err != OK:
		var nm2 := _nm()
		show_error("無法開始試煉：" + (str(nm2.get("status_text")) if nm2 != null else error_string(err)))
		return
	requires_session = true
	if UiClient.in_world():
		send_open()
	else:
		_open_pending = true

func _on_welcomed(_info: Dictionary) -> void:
	if _open_pending or view == UiKeys.ROGUE_VIEW_LOBBY and requires_session:
		_open_pending = false
		send_open()

## rogue_open：開局（ALLOC）、重擲、再戰一場
func send_open() -> void:
	_open_pending = false
	_alloc_key = ""
	send(UiKeys.I_ROGUE_OPEN, {}, [lobby.start_button, alloc_panel.reroll_button, summary_panel.again_button], _on_result)

func back_to_title() -> void:
	if leaver.is_valid():
		leaver.call()
	else:
		var nm := _nm()
		if nm != null and int(nm.get("mode")) != 0:
			_leaving = true   # 自己離開：session_ended 不要再導去斷線畫面
			nm.call("leave")
			_leaving = false
	if navigator.is_valid():
		navigator.call("title")
	else:
		go("title")

func _on_result(ok: bool, reason: String) -> void:
	if ok:
		show_error("")
	else:
		show_error(UiClient.reason_inline(reason) if reason != "" else "")

func show_error(t: String) -> void:
	if err_label != null:
		err_label.text = t

func add_message(t: String) -> void:
	if t == "":
		return
	messages.append(t)
	while messages.size() > MSG_LINES:
		messages.pop_front()
	msg_label.text = "\n".join(messages)

# ---------------------------------------------------------------- 事件

func handle_events(batch: Array) -> void:
	for e in batch:
		if e is Dictionary:
			handle_event(e)

func handle_event(e: Dictionary) -> void:
	var key := str(e.get("key", ""))
	var p: Dictionary = e.get("p", {}) if e.get("p") is Dictionary else {}
	match key:
		UiKeys.E_ROGUE_STATE:
			apply_state(p)
		UiKeys.E_ROGUE_OVER:
			summary = p.duplicate(true)
			_show_over()
		_:
			if UiKeys.ROGUE_LOG_FALLBACK.has(key):
				add_message(event_text(e))

## 事件文字：主機模板優先（WP-RUN 的 text_templates），沒有就用 UiKeys 的後備
static func event_text(e: Dictionary) -> String:
	var key := str(e.get("key", ""))
	var tpls := UiClient.templates()
	if tpls.has(key):
		return TextRenderer.render_plain(e, UiClient.my_peer(), tpls)
	var p: Dictionary = e.get("p", {}) if e.get("p") is Dictionary else {}
	return TextRenderer.fill(str(UiKeys.ROGUE_LOG_FALLBACK.get(key, "")), p)

func _on_sheet(sh: Dictionary) -> void:
	if hud.visible:
		hud.apply(state, sh)

# ---------------------------------------------------------------- 戰鬥

func open_battle(bstate: Dictionary) -> void:
	if battle != null and is_instance_valid(battle):
		battle.queue_free()
	attr_popup.visible = false
	confirm_panel.visible = false
	var scene := load(BATTLE_SCENE) as PackedScene
	battle = scene.instantiate() as BattleScreen
	battle.name = "Battle"
	add_child(battle)
	battle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle.offset_top = STRIP_H
	battle.setup(bstate)
	battle.finished.connect(_on_battle_finished)
	move_child(strip, -1)
	strip.visible = true
	_update_strip()

func close_battle(result: Dictionary) -> void:
	if battle == null or not is_instance_valid(battle):
		return
	# 同主畫面：晚一拍再顯示結果，最後一擊的動畫排得進去
	battle.call_deferred("show_result", result)

func battle_open() -> bool:
	return battle != null and is_instance_valid(battle)

func _on_battle_finished() -> void:
	if battle != null and is_instance_valid(battle):
		battle.queue_free()
	battle = null
	strip.visible = false
	if view == UiKeys.ROGUE_PHASE_OVER:
		_show_over()
	elif not state.is_empty():
		apply_state(state)

func _process(_delta: float) -> void:
	if battle_open() and strip.visible:
		_update_strip_live()

func _update_strip() -> void:
	strip_round.text = "%s　第 %d 回合" % [UiKeys.ROGUE_TITLE, maxi(1, UiBuild.num(state.get("round", 1)))]
	UiBuild.clear(strip_allies)
	var allies: Array = state.get("allies", []) if state.get("allies") is Array else []
	for a in allies:
		if a is Dictionary and bool(a.get("alive", true)):
			_strip_ally(str(a.get("name", "")), clampf(float(a.get("qi_pct", 1.0)), 0.0, 1.0) * 100.0, 100.0)

## 戰鬥中依戰鬥快照更新隊友的氣（kind ALLY 的單位）
func _update_strip_live() -> void:
	if battle.vm == null:
		return
	var rows: Array = []
	for uid in battle.vm.order:
		var u: Dictionary = battle.vm.unit(uid)
		if str(u.get("kind", "")) == "ALLY":
			rows.append(u)
	if rows.is_empty():
		return
	var labels := strip_allies.get_children()
	if labels.size() != rows.size():
		UiBuild.clear(strip_allies)
		for u in rows:
			_strip_ally(str(u.get("name", "")), float(u.get("qi", 0)), float(u.get("qi_max", 1)))
		return
	for i in rows.size():
		var bar := labels[i].get_node_or_null("Bar") as ProgressBar
		if bar != null:
			UiBuild.set_bar(bar, float(rows[i].get("qi", 0)), float(rows[i].get("qi_max", 1)))

func _strip_ally(nm: String, v: float, mx: float) -> void:
	var h := UiBuild.hbox(strip_allies, 4)
	var l := UiBuild.label(h, "友　" + nm, 15)
	l.add_theme_color_override("font_color", UiTheme.NAME_ALLY)
	var bar := UiBuild.bar(h, UiTheme.QI_COLOR, 90)
	bar.name = "Bar"
	UiBuild.set_bar(bar, v, mx)

# ---------------------------------------------------------------- 鍵盤

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if handle_key((event as InputEventKey).keycode):
		get_viewport().set_input_as_handled()

## 回 true＝已處理
func handle_key(code: int) -> bool:
	if battle_open():
		return false
	if code == KEY_ESCAPE:
		if attr_popup.visible:
			attr_popup.visible = false
			return true
		if confirm_panel.visible:
			confirm_panel.visible = false
			return true
		if view == UiKeys.ROGUE_PHASE_PICK and selected_idx >= 0:
			select_card(-1)
			return true
		if view == UiKeys.ROGUE_VIEW_LOBBY and lobby.visible:
			back_to_title()   # 大廳：Esc＝返回標題
			return true
		return false
	var enter := code == KEY_ENTER or code == KEY_KP_ENTER
	if confirm_panel.visible:
		# 放棄確認：Enter＝「再想想」（Enter 平常是「出戰」，順手一按不該結束這一局；放棄只能用滑鼠點）
		if enter:
			confirm_panel.visible = false
			return true
		return false
	if attr_popup.visible:
		if enter and not attr_popup.confirm_button.disabled:
			attr_popup.confirm()
			return true
		return false
	match view:
		UiKeys.ROGUE_VIEW_LOBBY:
			if enter and lobby.visible and not lobby.start_button.disabled and not requires_session:
				start_trial()
				return true
		UiKeys.ROGUE_PHASE_ALLOC:
			if enter and alloc_panel.visible and not alloc_panel.confirm_button.disabled:
				alloc_panel.confirm()
				return true
		UiKeys.ROGUE_PHASE_PICK:
			var n := card_key(code)
			if n >= 0:
				var c := card_at(n)
				if c != null:
					select_card(c.idx)
				return true
			if enter and selected_idx >= 0 and not pick_button.disabled:
				confirm_pick()
				return true
		UiKeys.ROGUE_PHASE_READY:
			if enter and not fight_button.disabled:
				fight()
				return true
		UiKeys.ROGUE_PHASE_OVER:
			if enter and summary_panel.visible and not summary_panel.again_button.disabled:
				send_open()   # 結算：Enter＝再戰一場
				return true
	return false

## 1／2／3（主鍵盤或數字鍵盤）→ 第幾張卡（0 起）；其他鍵 -1
static func card_key(code: int) -> int:
	if code >= KEY_1 and code <= KEY_3:
		return code - KEY_1
	if code >= KEY_KP_1 and code <= KEY_KP_3:
		return code - KEY_KP_1
	return -1
