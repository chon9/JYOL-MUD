class_name ScenePanel
extends PanelContainer
## 場景卷軸（AUTHENTIC_UI_SPEC §11；M1_PLAN 3.12、3.9.2）：小號竹軸捲軸框、墨字，是畫面的主要內容（文字 MUD）。
## 房名、時辰、描述、出口按鈕（move）、人物清單（點名字 → talk；NPC／玩家暗黃、怪物與屍體橘色）、
## 在場玩家、屍體（自己的 → loot_corpse）、生活技能按鈕（依 features 與已學技能 → work；烹煮彈出食譜選擇）。
## 生活技能冷卻中（sheet.cooldowns.life，所有生活技能共用）按鈕灰掉、文字「砍柴（3 秒）」，冷卻完回到「砍柴」。
## 拖動房名列可以移動卷軸（moved(pos) → 主畫面記在 settings.json）。NPC 說話時在名字旁顯示 3 秒小氣泡。
## 全部內容都從 ClientState 的 region_view 讀，不寫死任何房間或地區 id。
## M2（M2_PLAN 4.10）：
## - 玩家：名字顏色依善惡（惡藍、中立黃、善白）；左鍵 → 選單（組隊邀請、叫戰、密語、寄信、隊長的踢出／移交）；
##   連結鍵（預設 Ctrl，UiSocial.pk_key）+左鍵 → player_action("force_pk")（主畫面確認後送出）。選單動作一律發 player_action(action, player)。
## - 屍體：點名字 → corpse_opened(corpse)（主畫面開撿取視窗）；自己的屍體另有「拾回」直接全部拿走。
## - 戰鬥：同房進行中、joinable 的戰鬥顯示「加入戰鬥」→ battle_join。
## 查看偵察（docs/GDD.md §5.10【設計提案・非原作】；M3a 小範圍「不必來回換地圖找怪」）：有遇敵的野外房間（view.danger）
## 在「動作」列放「查看」鈕＝送 look { scout: true }；冷卻中（sheet.cooldowns.scout）灰掉並顯示「（5 秒）」。
## 主機發現怪物時送 scout_offer，主畫面開 ScoutDialog 讓玩家選「迎戰」或「離開」。
## 故事包（STORY_PLAN §6.5）：
## - view.story_actions [{ act, label }]：「動作」列最前面的紅字按鈕（任務動作，例「捕捉蜈蚣」「休息」）→ story_act { act }；
## - view.wanderers [{ wid, npc, name, hostile }]：人物列以【惡】標記（同一位 NPC 在 npcs 裡就標在他的名字上，不在就另列一個紅字名字）；
## - view.escort [{ npc, name }]（護送 NPC 也在 npcs 裡，帶 escort: true）：人物列的名字後加「（隨行）」，可照常點名字交談；
## - view.npcs 已由主機依 appear 過濾（莫大只在申酉時出現等），照列。

signal moved(pos: Vector2)
signal player_action(action: String, player: Dictionary)
signal corpse_opened(corpse: Dictionary)
## M3b（M3B_PLAN §7.3）：「動作」列的「製作」鈕（有製作型設施或已學會隨地可做的配方）→ 主畫面開製作窗
signal craft_requested()
## M3C_PLAN §5.8：連結鍵（預設 Ctrl）＋左鍵點 NPC 名字 → 主畫面 request_npc_attack（npc ＝ view 的 npcs 項目；
## npcs[].atk 為 null 的受保護 NPC 由主畫面直接在訊息列說「不是你能動手的對象」，不送）
signal npc_attack_requested(npc: Dictionary)
const SAFE_TAG := "安全"
const NO_ENCOUNTER_TAG := "無遇敵"

const BUBBLE_S := 3.0
const HUD_H := 168.0

var gate: IntentGate
var view: Dictionary = {}
var sheet: Dictionary = {}

var room_label: Label
var region_label: Label
var clock_label: Label
var desc_label: Label
var exits_box: HFlowContainer
var npcs_box: HFlowContainer
var players_label: Label             # 沒有任何玩家時的「（無）」
var players_box: HFlowContainer
var player_buttons: Dictionary = {}  # char_id -> Button
var player_menu: PopupMenu
var _menu_player: Dictionary = {}
var _menu_actions: Array = []
var _ctrl_click := false
var _npc_ctrl_click := false
var battles_box: HFlowContainer
var corpses_box: HFlowContainer
var life_box: HFlowContainer
var recipe_panel: PanelContainer
var recipe_list: VBoxContainer
var head_row: HBoxContainer
var bubble_layer: Control
var npc_buttons: Dictionary = {}     # npc id -> Button
var _bubbles: Dictionary = {}        # npc id -> { text, until }
var cooldowns := CooldownTracker.new()
var _cd_buttons: Array = []          # [{ b: Button, base: String, locked: bool }]：生活技能與食譜按鈕
var _shown_life_s := 0          # 上次套用的生活技能剩餘秒數：變了才重設按鈕文字
var scout_button: Button = null  # 「查看」（只在可偵察的房間）
var _shown_scout_s := -1
const SCOUT_LABEL := "查看"   # 與 F3 熱鍵、偵察視窗標題「查看・…」、記錄「你仔細查看四周…」同一個名字（GDD §5.10；M3a 審查）
const SCOUT_TIP := "在附近仔細搜尋：發現野獸時可以選擇迎戰或離開（不必來回換地圖找怪）"
const VILLAIN_MARK := "【惡】"
const ESCORT_MARK := "（隨行）"
const STORY_ACT_COLOR := Color("c02020")
var story_buttons: Dictionary = {}   # act -> Button
var craft_button: Button = null      # M3b「製作」
var _drag_from := Vector2(-1, -1)
var _built := false

func _ready() -> void:
	if not _built:
		_build()

func _gate() -> IntentGate:
	if gate == null:
		gate = IntentGate.new()
		add_child(gate)
	return gate

func _build() -> void:
	_built = true
	theme = UiTheme.paper()
	add_theme_stylebox_override("panel", UiFrame.style(UiFrame.Kind.SCROLL_SMALL))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var outer := UiBuild.vbox(self, 4)
	head_row = UiBuild.hbox(outer, 12)
	head_row.mouse_filter = Control.MOUSE_FILTER_STOP
	head_row.mouse_default_cursor_shape = Control.CURSOR_MOVE
	head_row.tooltip_text = "拖動可以移動卷軸"
	head_row.gui_input.connect(_on_head_input)
	room_label = UiBuild.label(head_row, "", 22)
	room_label.add_theme_color_override("font_color", UiTheme.CINNABAR)
	room_label.add_theme_font_override("font", UiTheme.brush_font(0.3))
	region_label = UiBuild.muted(UiBuild.label(head_row, "", 14))
	region_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	region_label.clip_text = true
	clock_label = UiBuild.label(head_row, "", 14)
	var sc := UiBuild.scroll(outer)
	var col := UiBuild.vbox(sc, 5)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label = UiBuild.label(col, "", 16, true)
	desc_label.custom_minimum_size = Vector2(300, 0)
	col.add_child(HSeparator.new())
	exits_box = _flow_row(col, "出口")
	npcs_box = _flow_row(col, "人物")
	players_box = _flow_row(col, "玩家")
	players_label = UiBuild.muted(UiBuild.label(players_box, "（無）", 15))
	battles_box = _flow_row(col, "戰鬥")
	corpses_box = _flow_row(col, "屍體")
	player_menu = PopupMenu.new()
	player_menu.name = "PlayerMenu"
	player_menu.id_pressed.connect(_on_menu_id)
	add_child(player_menu)
	life_box = _flow_row(col, "動作")

	recipe_panel = PanelContainer.new()
	recipe_panel.add_theme_stylebox_override("panel", UiFrame.style(UiFrame.Kind.INK))
	recipe_panel.theme = UiTheme.build()
	recipe_panel.visible = false
	var rv := UiBuild.vbox(recipe_panel, 6)
	UiBuild.accent(UiBuild.label(rv, "選擇食譜", 18))
	recipe_list = UiBuild.vbox(rv, 4)
	UiBuild.button(rv, "取消", func(): recipe_panel.visible = false)
	col.add_child(recipe_panel)
	bubble_layer = Control.new()
	bubble_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble_layer.draw.connect(_draw_bubbles)
	add_child(bubble_layer)

func _rebuild_exits() -> void:
	UiBuild.clear(exits_box)
	var jailed := is_jailed()
	for ex in view.get("exits", []):
		if not (ex is Dictionary):
			continue
		var dir := str(ex.get("dir", ""))
		var t := "%s：%s" % [str(ex.get("label", UiKeys.dir_label(dir))), str(ex.get("to_name", ""))]
		var locked := bool(ex.get("locked", false))
		if jailed:
			t += "（思過中）"
		elif locked:
			t += "（不得進入）"
		var b := UiBuild.button(exits_box, t)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_on_move.bind(dir, b))
		if jailed:
			b.disabled = true
			b.tooltip_text = "正在思過處思過，刑期未滿不能離開。"
		elif locked:
			b.disabled = true
			var why := UiClient.reason_inline(str(ex.get("lock_reason", "")))
			b.tooltip_text = why if why != "" else "目前還不能進去。"
	if exits_box.get_child_count() == 0:
		UiBuild.muted(UiBuild.label(exits_box, "（無）"))

func _flow_row(parent: Node, title: String) -> HFlowContainer:
	var row := UiBuild.hbox(parent, 6)
	UiBuild.muted(UiBuild.label(row, title, 15)).custom_minimum_size = Vector2(44, 0)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	row.add_child(flow)
	return flow

func apply_sheet(s: Dictionary) -> void:
	var was_jailed := is_jailed()
	sheet = s
	cooldowns.update(s)
	if _built:
		_rebuild_life()
		if not view.is_empty():
			_rebuild_players()
			if was_jailed != is_jailed():
				_rebuild_exits()

## 坐牢中（角色表 jail 不是空的）：出口一律灰掉並標「思過中」（M3a 審查 C5：以前點了才被拒）
func is_jailed() -> bool:
	var j: Variant = sheet.get("jail", null)
	return j is Dictionary and not (j as Dictionary).is_empty()

## v = 3.9.2
func apply_view(v: Dictionary) -> void:
	if not _built:
		_build()
	view = v
	room_label.text = str(v.get("room_name", ""))
	var tags: PackedStringArray = [str(v.get("region_name", ""))]
	if bool(v.get("safe", false)):
		# M3c 審查：view.safe 只表示「沒有遇敵」（城裡也是）；寫「安全」會讓人以為這裡不能動手。
		# 只有房間資料真的標了 safe（思過處、監獄、茶棚等，不能動手）才寫「安全」
		tags.append(SAFE_TAG if NpcAttackUi._room_safe(v) else NO_ENCOUNTER_TAG)
	elif bool(v.get("danger", false)):
		var top := str(v.get("danger_top", ""))
		tags.append("野外・危險：%s" % top if top != "" else "野外，小心遇敵")
	region_label.text = "　".join(tags)
	clock_label.text = "%s%s" % [str(v.get("clock", "")), "（夜）" if bool(v.get("night", false)) else ""]
	desc_label.text = str(v.get("desc", ""))

	_rebuild_exits()

	UiBuild.clear(npcs_box)
	npc_buttons.clear()
	var villains := ScenePanel.wanderers_by_npc(v)
	var escorts := {}
	for e in v.get("escort", []):
		if e is Dictionary:
			escorts[str(e.get("npc", ""))] = e
	for n in v.get("npcs", []):
		if not (n is Dictionary):
			continue
		var nid := str(n.get("id", ""))
		var t := str(n.get("name", "?"))
		if bool(n.get("closed", false)):
			t += "（打烊）"
		if villains.has(nid):
			t = VILLAIN_MARK + t
		var escorted := bool(n.get("escort", false)) or escorts.has(nid)
		if escorted:
			t += ESCORT_MARK
		var b := UiBuild.button(npcs_box, t)
		b.theme_type_variation = "NameButton"
		b.add_theme_font_size_override("font_size", 16)
		var svc := "、".join(PackedStringArray((n.get("services", []) as Array).map(func(s): return UiKeys.service_label(str(s)))))
		b.tooltip_text = svc if svc != "" else "閒聊"
		if escorted:
			b.tooltip_text = "正跟著你同行（任務護送）" + ("
" + svc if svc != "" else "")
		if villains.has(nid):
			_paint_villain(b)
			b.tooltip_text = "惡名昭彰的人物，招惹他可能會動手。" + ("
" + svc if svc != "" else "")
		# M3c：可以動手的 NPC 提示「（Ctrl+點：動手）」；Ctrl+左鍵 → npc_attack_requested（不交談）
		var sfx := NpcAttackUi.tooltip_suffix(n)
		if sfx != "":
			b.tooltip_text += sfx
		b.gui_input.connect(_on_npc_input)
		b.pressed.connect(func(): on_npc_clicked(n, _npc_ctrl_click, b))
		npc_buttons[nid] = b
	# 遊蕩惡人不在 npcs 裡（夜裡在野外遊蕩）：另列紅字名字（不能交談，警告由 VillainPrompt 處理）
	for w in v.get("wanderers", []):
		if not (w is Dictionary) or npc_buttons.has(str(w.get("npc", ""))):
			continue
		var wl := UiBuild.label(npcs_box, VILLAIN_MARK + str(w.get("name", "?")), 16)
		wl.name = "Wanderer_" + str(w.get("wid", ""))
		_paint_villain(wl)
		wl.mouse_filter = Control.MOUSE_FILTER_PASS
		wl.tooltip_text = "正在附近遊蕩的惡人%s。" % ("，看來來者不善" if w.get("hostile", false) == true else "")
	# 護送中的 NPC（主機沒把他放進 npcs 時另列）
	for e in v.get("escort", []):
		if not (e is Dictionary) or npc_buttons.has(str(e.get("npc", ""))):
			continue
		var el := UiBuild.label(npcs_box, str(e.get("name", UiClient.name_of("npcs", str(e.get("npc", ""))))) + ESCORT_MARK, 16)
		el.name = "Escort_" + str(e.get("npc", ""))
		el.add_theme_color_override("font_color", UiTheme.NAME_NPC)
		el.mouse_filter = Control.MOUSE_FILTER_PASS
		el.tooltip_text = "正跟著你同行（任務護送）"
	if npcs_box.get_child_count() == 0:
		UiBuild.muted(UiBuild.label(npcs_box, "（無）"))

	_rebuild_players()
	_rebuild_battles()
	_rebuild_corpses()
	_rebuild_life()

## view.wanderers 依 npc id：{ npc: wanderer row }
static func wanderers_by_npc(v: Dictionary) -> Dictionary:
	var out := {}
	for w in v.get("wanderers", []):
		if w is Dictionary and str(w.get("npc", "")) != "":
			out[str(w["npc"])] = w
	return out

func _paint_villain(c: Control) -> void:
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		c.add_theme_color_override(k, STORY_ACT_COLOR)

# ---------- 玩家（M2） ----------
func _rebuild_players() -> void:
	UiBuild.clear(players_box)
	player_buttons.clear()
	var my_peer := UiClient.my_peer()
	var my_char := str(sheet.get("char_id", ""))
	for p in view.get("players", []):
		if not (p is Dictionary):
			continue
		var align := str(p.get("align", UiKeys.ALIGN_NEUTRAL))
		var t := str(p.get("name", "?"))
		if bool(p.get("in_battle", false)):
			t += "（戰鬥中）"
		if UiSocial.is_self(p, my_peer, my_char):
			var me := UiBuild.label(players_box, t + "（你）", 15)
			_paint_name(me, align)
			continue
		var b := UiBuild.button(players_box, t)
		b.theme_type_variation = "NameButton"
		b.add_theme_font_size_override("font_size", 16)
		_paint_name(b, align)
		b.tooltip_text = UiSocial.player_tip(p)
		b.gui_input.connect(_on_player_input)
		b.pressed.connect(func(): on_player_clicked(p, _ctrl_click, b))
		player_buttons[str(p.get("char_id", ""))] = b
	if players_box.get_child_count() == 0:
		players_label = UiBuild.muted(UiBuild.label(players_box, "（無）", 15))

## 名字顏色（惡藍、中立黃、善白）：卷軸是淺底，黃、白字加深褐描邊才看得到
func _paint_name(c: Control, align: String) -> void:
	var col := UiSocial.align_color(align)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		c.add_theme_color_override(k, col)
	if UiSocial.needs_outline(align):
		c.add_theme_constant_override("outline_size", 4)
		c.add_theme_color_override("font_outline_color", Color("3a2a18"))

## 記下這次點擊有沒有按強制 PK 的連結鍵（預設 Ctrl，系統窗「特殊開關」可改；Button.pressed 不帶修飾鍵）
func _on_player_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_ctrl_click = UiSocial.pk_modifier_down(mb)

## M3c：記下點 NPC 時有沒有按連結鍵（與強制 PK 同一個鍵）
func _on_npc_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_npc_ctrl_click = UiSocial.pk_modifier_down(mb)

## 點 NPC 名：按著連結鍵 → npc_attack_requested；否則交談
func on_npc_clicked(n: Dictionary, ctrl: bool, b: Button = null) -> void:
	_npc_ctrl_click = false
	if ctrl:
		npc_attack_requested.emit(n)
		return
	_gate().send(UiKeys.I_TALK, { "npc": str(n.get("id", "")) }, [b] if b != null else [])

## 點玩家名：按著連結鍵 → 強行出手；否則開選單
func on_player_clicked(p: Dictionary, ctrl: bool, anchor: Control = null) -> void:
	_ctrl_click = false
	if ctrl:
		player_action.emit(UiSocial.ACT_FORCE_PK, p)
		return
	open_player_menu(p, anchor)

func open_player_menu(p: Dictionary, anchor: Control = null) -> void:
	_menu_player = p
	_menu_actions = UiSocial.player_menu(p, sheet)
	player_menu.clear()
	for i in _menu_actions.size():
		player_menu.add_item(str(_menu_actions[i][1]), i)
	if not is_inside_tree():
		return
	var at := Vector2i(get_global_mouse_position())
	if anchor != null and anchor.is_inside_tree():
		at = Vector2i(anchor.global_position + Vector2(0, anchor.size.y))
	player_menu.popup(Rect2i(at, Vector2i(160, 0)))

func menu_actions() -> Array:
	return _menu_actions.map(func(a): return str(a[0]))

func choose_menu_action(action: String) -> void:
	player_menu.hide()
	player_action.emit(action, _menu_player)

func _on_menu_id(i: int) -> void:
	if i >= 0 and i < _menu_actions.size():
		choose_menu_action(str(_menu_actions[i][0]))

# ---------- 同房的戰鬥（M2 中途加入） ----------
func _rebuild_battles() -> void:
	UiBuild.clear(battles_box)
	for bt in view.get("battles", []):
		if not (bt is Dictionary):
			continue
		var label := UiSocial.battle_label(bt)
		if bool(bt.get("joinable", false)):
			var b := UiBuild.button(battles_box, "加入戰鬥　" + label)
			b.add_theme_font_size_override("font_size", 14)
			b.tooltip_text = "隊友正在這裡打鬥，可以加入幫忙。"
			b.pressed.connect(_on_join_battle.bind(int(bt.get("bid", 0)), b))
		else:
			UiBuild.muted(UiBuild.label(battles_box, label, 14))
	battles_box.get_parent().visible = battles_box.get_child_count() > 0

func _on_join_battle(bid: int, b: Button) -> void:
	_gate().send(UiKeys.I_BATTLE_JOIN, { "battle_id": bid }, [b])

# ---------- 屍體（M2：撿取視窗） ----------
func _rebuild_corpses() -> void:
	UiBuild.clear(corpses_box)
	for c in view.get("corpses", []):
		if not (c is Dictionary):
			continue
		# 自己的屍體：「我的屍體（n 件）」和「全部拾回」放在同一組（間距 2），看得出拾回的是這具屍體上的全部東西
		# （M2 第三輪審查：單獨一顆「拾回」看不出拾什麼）
		var mine := bool(c.get("mine", false))
		var holder: Node = corpses_box
		if mine:
			holder = UiBuild.hbox(corpses_box, 2)
			holder.name = "MyCorpse"
		var b := UiBuild.button(holder, UiSocial.corpse_label(c))
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", UiTheme.NAME_MONSTER)
		b.tooltip_text = "打開撿取視窗"
		b.pressed.connect(func(): corpse_opened.emit(c))
		if mine:
			var lb := UiBuild.button(holder, "全部拾回")
			lb.name = "LootMine"
			lb.add_theme_font_size_override("font_size", 14)
			lb.tooltip_text = "把我的屍體上的東西一次全部拿回來"
			lb.pressed.connect(_on_loot.bind(str(c.get("id", "")), lb))
	corpses_box.get_parent().visible = corpses_box.get_child_count() > 0

func known_life_skills() -> Dictionary:
	var out := {}
	for s in sheet.get("skills", []):
		if s is Dictionary and str(s.get("kind", "")) == "LIFE" and UiBuild.num(s.get("level", 0)) >= 1:
			out[str(s.get("id", ""))] = UiBuild.num(s.get("level", 0))
	return out

func _rebuild_life() -> void:
	UiBuild.clear(life_box)
	_prune_cooldown_buttons()
	story_buttons.clear()
	# 任務動作（紅字，STORY_PLAN §4.3 房間動作）：主機只列這個人此刻能做的
	for a in view.get("story_actions", []):
		if not (a is Dictionary) or str(a.get("act", "")) == "":
			continue
		var act := str(a.get("act", ""))
		var sb := UiBuild.button(life_box, str(a.get("label", act)))
		sb.name = "StoryAct_" + act.replace(":", "_")
		_paint_villain(sb)
		sb.tooltip_text = "任務動作"
		sb.pressed.connect(_on_story_act.bind(act, sb))
		story_buttons[act] = sb
	scout_button = null
	_shown_scout_s = -1
	if ScenePanel.can_scout_here(view):
		scout_button = UiBuild.button(life_box, SCOUT_LABEL)
		scout_button.name = "ScoutButton"
		scout_button.tooltip_text = SCOUT_TIP
		scout_button.pressed.connect(_on_scout.bind(scout_button))
		_apply_scout_cooldown()
	var known := known_life_skills()
	for f in view.get("features", []):
		var skill: String = UiKeys.FEATURE_LIFE.get(str(f), "")
		if skill == "":
			continue
		var verb: String = UiKeys.LIFE_VERBS.get(skill, skill)
		if not known.has(skill):
			# 還沒學：顯示灰色按鈕，讓玩家知道這裡可以做這件事、該找誰學
			var lb := UiBuild.button(life_box, "%s（需先學 %s）" % [verb, UiClient.name_of("life_skills", skill, verb)])
			lb.disabled = true
			var teachers := _life_teachers(skill)
			lb.tooltip_text = "可以向%s學習。" % "、".join(teachers) if not teachers.is_empty() else "還沒學會這項生活技能。"
			continue
		var b := UiBuild.button(life_box, verb)
		_track_cooldown(b, verb, false)
		if skill == UiKeys.LIFE_COOKING:
			b.pressed.connect(_open_recipes.bind(known[skill]))
		else:
			b.pressed.connect(_on_work.bind(skill, "", b))
	craft_button = null
	if EconUi.craft_available(view, sheet):
		craft_button = UiBuild.button(life_box, UiKeys.CRAFT_LABEL)
		craft_button.name = "CraftButton"
		craft_button.tooltip_text = UiKeys.CRAFT_TIP
		craft_button.pressed.connect(func(): craft_requested.emit())
	life_box.get_parent().visible = life_box.get_child_count() > 0

## 教這項生活技能的 NPC 名稱（讀本地資料表 masters）
func _life_teachers(skill: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var masters: Dictionary = UiClient.table("masters")
	for mid in masters:
		var m: Variant = masters[mid]
		if m is Dictionary and str(m.get("skill_id", "")) == skill:
			var nm := UiClient.name_of("npcs", str(m.get("npc_id", "")))
			if nm != "" and not out.has(nm):
				out.append(nm)
	return out

## 指令窗／熱鍵的「烹煮」：用已學的廚師等級開食譜
func open_recipes_for_known() -> void:
	var known := known_life_skills()
	if known.has(UiKeys.LIFE_COOKING):
		_open_recipes(int(known[UiKeys.LIFE_COOKING]))

func _open_recipes(level: int) -> void:
	UiBuild.clear(recipe_list)
	_prune_cooldown_buttons()
	var row := UiClient.row("life_skills", UiKeys.LIFE_COOKING)
	for r in row.get("recipes", []):
		if not (r is Dictionary):
			continue
		var inputs: PackedStringArray = []
		for i in r.get("inputs", []):
			if i is Dictionary:
				inputs.append("%s×%d" % [UiClient.name_of("items", str(i.get("item", ""))), UiBuild.num(i.get("n", 1))])
		var min_lv := UiBuild.num(r.get("min_level", 1))
		var b := UiBuild.button(recipe_list, "%s（%s；%d 級）" % [str(r.get("name", r.get("id", ""))), "、".join(inputs), min_lv])
		b.disabled = level < min_lv
		_track_cooldown(b, b.text, level < min_lv)
		b.pressed.connect(func():
			recipe_panel.visible = false
			_on_work(UiKeys.LIFE_COOKING, str(r.get("id", "")), b))
	if recipe_list.get_child_count() == 0:
		UiBuild.muted(UiBuild.label(recipe_list, "（沒有食譜資料）"))
	recipe_panel.visible = true

# ---------- NPC 說話氣泡 ----------
## 原作在角色頭上顯示白色圓角氣泡、紅字；本作在卷軸裡人物名字旁邊顯示 3 秒
func show_bubble(npc: String, text: String) -> void:
	if text == "":
		return
	_bubbles[npc] = { "text": TextRenderer.strip_channel_tag(text), "until": Time.get_ticks_msec() + int(BUBBLE_S * 1000.0) }

func _prune_cooldown_buttons() -> void:
	_cd_buttons = _cd_buttons.filter(func(e): return is_instance_valid(e["b"]) and not (e["b"] as Node).is_queued_for_deletion())

## 生活技能冷卻：登記一顆按鈕（locked = 本來就不能按，例如食譜等級不夠）並立刻套用目前的倒數
func _track_cooldown(b: Button, base: String, locked: bool) -> void:
	var e := { "b": b, "base": base, "locked": locked }
	_cd_buttons.append(e)
	_apply_cooldown(e, cooldowns.left_s(CooldownTracker.KEY_LIFE))

func _apply_cooldown(e: Dictionary, secs: int) -> void:
	var b: Button = e["b"]
	var t := CooldownTracker.label(str(e["base"]), secs)
	if b.text != t:
		b.text = t
	var dis := bool(e["locked"]) or secs > 0
	if b.disabled != dis:
		b.disabled = dis

## 這個房間能查看偵察：主機開著查看偵察、房間有遇敵表（view.danger）、不是安全的房間
static func can_scout_here(v: Dictionary) -> bool:
	return UiClient.scout_enabled() and bool(v.get("danger", false)) and not bool(v.get("safe", false))

func _on_scout(b: Button) -> void:
	_gate().send(UiKeys.I_LOOK, { "scout": true }, [b])

func _apply_scout_cooldown() -> void:
	if scout_button == null or not is_instance_valid(scout_button):
		return
	var secs := cooldowns.left_s(CooldownTracker.KEY_SCOUT)
	if secs != _shown_scout_s:
		_shown_scout_s = secs
		scout_button.text = CooldownTracker.label(SCOUT_LABEL, secs)
	# 送出中由 IntentGate 鎖住；回來後依冷卻決定（結果可能比角色表晚到，解鎖時不能蓋掉冷卻）
	var dis := secs > 0 or (gate != null and gate.is_pending(UiKeys.I_LOOK))
	if scout_button.disabled != dis:
		scout_button.disabled = dis

func _process(_delta: float) -> void:
	_apply_scout_cooldown()
	var secs := cooldowns.left_s(CooldownTracker.KEY_LIFE)
	if secs != _shown_life_s:
		_shown_life_s = secs
		_prune_cooldown_buttons()
		for e in _cd_buttons:
			_apply_cooldown(e, secs)
	if _bubbles.is_empty() or bubble_layer == null:
		return
	# 到時間就收掉（不靠畫的時候才檢查：卷軸被蓋住、沒重畫時也一樣 3 秒消失）
	var now := Time.get_ticks_msec()
	for npc in _bubbles.keys():
		if now > int(_bubbles[npc]["until"]):
			_bubbles.erase(npc)
	bubble_layer.queue_redraw()

## 目前還顯示中的氣泡（npc id 陣列；測試用）
func active_bubbles() -> Array:
	var now := Time.get_ticks_msec()
	return _bubbles.keys().filter(func(k): return now <= int(_bubbles[k]["until"]))

## 氣泡的矩形（bubble_layer 座標）：§8.7「場景卷軸人物名旁」——畫在名字按鈕右邊、同一列，
## 右邊放不下就放左邊；不往上蓋到「出口」那一列（審查：以前畫在名字正上方，整排出口鈕被蓋住）
func bubble_rect(b: Control, text_w: float, fs: int) -> Rect2:
	var h := fs + 8.0
	var w := text_w + 12.0
	var bpos := b.global_position - bubble_layer.global_position
	var y := bpos.y + (b.size.y - h) / 2.0
	var x := bpos.x + b.size.x + 6.0
	if x + w > bubble_layer.size.x - 4.0:
		x = bpos.x - w - 6.0
	x = clampf(x, 4.0, maxf(4.0, bubble_layer.size.x - w - 4.0))
	return Rect2(Vector2(x, y), Vector2(w, h))

func _draw_bubbles() -> void:
	var ci := bubble_layer
	var now := Time.get_ticks_msec()
	var font := UiTheme.find_font()
	if font == null:
		font = ThemeDB.fallback_font
	for npc in _bubbles.keys():
		var bdata: Dictionary = _bubbles[npc]
		if now > int(bdata["until"]):
			_bubbles.erase(npc)
			continue
		var b: Button = npc_buttons.get(npc, null)
		if b == null or not is_instance_valid(b) or not b.is_visible_in_tree():
			continue
		var t := str(bdata["text"])
		if t.length() > 18:
			t = t.left(17) + "…"
		var fs := 13
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var r := bubble_rect(b, w, fs)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.WHITE
		sb.border_color = Color("5a4630")
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		ci.draw_style_box(sb, r)
		ci.draw_string(font, r.position + Vector2(6, fs + 2), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("c02020"))

# ---------- 拖動 ----------
func _on_head_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_drag_from = mb.global_position - position
		elif _drag_from.x >= 0.0:
			_drag_from = Vector2(-1, -1)
			moved.emit(position)
		return
	var mm := ev as InputEventMouseMotion
	if mm != null and _drag_from.x >= 0.0 and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var area := (get_parent() as Control).size if get_parent() is Control else size
		area.y -= HUD_H
		position = ScenePanel.clamp_into(mm.global_position - _drag_from, size, area)

## 把卷軸夾在場景區內（至少留標題列在畫面裡）
static func clamp_into(pos: Vector2, sz: Vector2, area: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, 0.0, maxf(0.0, area.x - sz.x)), clampf(pos.y, 0.0, maxf(0.0, area.y - 40.0)))

func _on_move(dir: String, b: Button) -> void:
	_gate().send(UiKeys.I_MOVE, { "dir": dir }, [b])

func _on_talk(npc: String, b: Button) -> void:
	_gate().send(UiKeys.I_TALK, { "npc": npc }, [b])

func _on_story_act(act: String, b: Button) -> void:
	_gate().send(UiKeys.I_STORY_ACT, { "act": act }, [b])

func _on_loot(corpse_id: String, b: Button) -> void:
	_gate().send(UiKeys.I_LOOT_CORPSE, { "corpse_id": corpse_id }, [b])

func _on_work(skill: String, recipe: String, b: Button) -> void:
	var args := { "skill": skill }
	if recipe != "":
		args["recipe"] = recipe
	_gate().send(UiKeys.I_WORK, args, [b])
