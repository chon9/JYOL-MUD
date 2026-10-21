extends UiScreen
## 主畫面（AUTHENTIC_UI_SPEC §2：仿原作客戶端版面，1280×720 基準）：
## - 場景區（0,0 到 HUD 上緣）：目前地區的背景圖鋪滿再壓暗 35%；
##   左上 聊天／系統浮層（MessageLog）；其下 場景卷軸（ScenePanel：房名、描述、出口、人物、屍體、生活技能，可拖動）；
##   右上 小地圖（可收合、可在系統窗關掉）；右緣 燈籠選單（武功 Ctrl+1、屬性 Ctrl+2、裝備 Ctrl+3、指令 Ctrl+4、系統 Ctrl+5）。
## - 底部 HUD（BottomHud）：圖示＋4 條能量條、地點牌、曆法牌、F1–F8／Alt+1–8 熱鍵列、頻道鈕＋聊天輸入、殺氣、時鐘、系統訊息框。
## 快捷鍵：Ctrl+1–5 燈籠、Ctrl+6 任務、Ctrl+M（與 M）地圖、F1–F8 指令熱鍵、Alt+1–8 物品熱鍵；
## Esc 先放開輸入框焦點，再關對話框／視窗，最後才收合燈籠。
## 視窗與 NPC 對話框互斥：開一個就關另一個。
## battle_opened 時疊上戰鬥畫面（只蓋上半部，底部 HUD 照常顯示），battle_closed 顯示結果後自動返回；
## 戰鬥中 Ctrl+數字無效（戰鬥圓盤的「屬」「系」可以開屬性窗與系統窗）。
## M2（M2_PLAN 4.10）：
## - 場景卷軸的玩家名：選單動作（組隊邀請、叫戰、密語、寄信、踢出、移交領隊）與 Ctrl+點（強行出手確認框）在 _on_player_action；
## - 組隊／叫戰提示框（PendingPrompts，聊天浮層右邊）、隊伍面板（PartyFrame，小地圖下方）；
## - 對話框層多了 屍體撿取、飛鴿傳書（HUD 鴿章）、伺服器設定（系統窗特殊開關，限管理員）、確認框。
## 查看偵察（docs/GDD.md §5.10【設計提案・非原作】）：「查看」在主機開著 scout_enabled 時送 look { scout: true }；
## 主機的 scout_offer（ui）開 ScoutDialog（迎戰／離開），scout_closed 或換房間時關掉。
## M3a（M3A_PLAN §7.7–7.9）：
## - 坐牢時場景區上方一條提示「思過處：剩 1 小時 32 分（上線時間）」（sheet.jail.left_s，本機倒數）；
## - teach_list 沒帶 teach_blocked 時，沿用同一位 NPC 的 npc_menu.teach_blocked（學藝視窗顯示原因、學習鈕灰掉）；
## - 屬性燈籠在 sect_info.warnings 不是空的時候染紅，提示「接近門規底線」。
## 故事包（STORY_PLAN §6）：
## - dialogue（ui）開任務對話視窗 StoryDialog（和其他對話框互斥），dialogue_close、換房間、開戰時收起；
## - villain_prompt（ui）開非模態的惡人警告 VillainPrompt（聊天浮層右邊、提示列下方），villain_clear、換房間、開戰時收起；
## - rumor_list（ui）交給系統窗的「江湖傳聞」頁；jianghu_rumor 由 MessageLog 顯示；
## - 任務窗「在地圖上標出」→ 打開地圖並標記 hint_room。
## M3b（M3B_PLAN §7）：
## - 錢莊窗（bank_view ui）、鏢局窗（NPC「鏢局」；consign_list ui 交給它）、製作窗（場景「製作」鈕、指令「製作」）、
##   組織面板（指令「組織」送 org_info；衙門書吏「組織」；org_info ui 交給它）、捉拿公敵（指令「捉拿公敵」、玩家選單「捉拿」）
##   都在對話框層，和其他對話框互斥，Esc 關；
## - org_invite（ui）→ 待回覆提示（PendingPrompts）；玩家選單「邀請入組織」→ org_invite { name }；
## - 指令「乞討」→ beg { npc }（最近交談、還在這裡的 NPC，否則房間裡第一位可乞討的）。
## M3c WP-NAV（M3C_PLAN §4）：小地圖接到 MapPanel.bind_mini_map；趕路中 Esc 先停止趕路；
## close_battle 把我的結算交給 MapPanel，戰鬥畫面收起後 MapPanel 決定續走或停（系統選項 nav.auto_resume）。

const BATTLE_SCENE := "res://ui/game/battle/battle_screen.tscn"
const MAP_PANEL := "map"
const MAP_LABEL := "地圖"
const QUEST_PANEL := "quests"
const HUD_H := 168.0
const OVERLAY_RECT := Rect2(8, 8, 552, 280)
const SCENE_POS := Vector2(8, 296)
const SCENE_W := 632.0
const MINI_SIZE := Vector2(264, 228)   # 審查 round 3：220 寬時標題「大漠邊緣 3,」被地圖鈕切掉、左右鄰房名字被框切掉
const LANTERN_W := 52.0
const PANEL_MARGIN := 6.0

var backdrop: SceneBackdrop
var lanterns: LanternMenu
var panel_buttons: Dictionary = {}   # panel id -> 燈籠／地圖鈕
var hud: BottomHud
var hotbar: Hotbar
var scene_panel: ScenePanel
var mini_map: MiniMap
var message_log: MessageLog
var status_bar: StatusBar
var panel_layer: CenterContainer
var panel_frame: PanelContainer
var panel_title: Label
var panel_host: VBoxContainer
var panel_close: JyButton
var panel_feedback: PanelFeedback   # 視窗裡動作的失敗原因與成功訊息顯示在視窗底部
var panels: Dictionary = {}          # panel id -> Control
var command_panel: CommandPanel
var current_panel := ""
var dialog_layer: CenterContainer
var npc_dialog: NpcDialog
var shop_dialog: ShopDialog
var learn_dialog: LearnDialog
var map_panel: MapPanel
var corpse_dialog: CorpseDialog
var mail_dialog: MailDialog
var server_dialog: ServerOptionsDialog
var confirm_dialog: ConfirmDialog
var scout_dialog: ScoutDialog
var story_dialog: StoryDialog
var villain_prompt: VillainPrompt
var bank_window: BankWindow
var escort_window: EscortWindow
var craft_window: CraftWindow
var org_panel: OrgPanel
var seize_dialog: SeizeDialog
var _last_room := ""
var party_frame: PartyFrame
var pending_prompts: PendingPrompts
var battle: BattleScreen = null
var jail_banner: PanelContainer
var jail_label: Label
var last_talk_text := ""
var sheet: Dictionary = {}
var view: Dictionary = {}
var _deferred_view: Dictionary = {}  # 戰敗重生的新房間：戰鬥畫面收起來之後才套用（審查：戰敗小條還在，地點牌已經是重生點）

func _ready() -> void:
	_build()
	UiClient.connect_signal("sheet_changed", apply_sheet)
	UiClient.connect_signal("region_changed", apply_view)
	UiClient.connect_signal("battle_opened", open_battle)
	UiClient.connect_signal("battle_closed", close_battle)
	UiClient.connect_signal("events_received", _on_events)
	var msg := take_router_message()
	if msg != "":
		message_log.add_system(msg)
	if not UiClient.sheet().is_empty():
		apply_sheet(UiClient.sheet())
	if not UiClient.region_view().is_empty():
		apply_view(UiClient.region_view())
	elif UiClient.in_world():
		send(UiKeys.I_LOOK)
	if not UiClient.battle_state().is_empty():
		open_battle(UiClient.battle_state())

func _exit_tree() -> void:
	super._exit_tree()
	UiClient.disconnect_signal("sheet_changed", apply_sheet)
	UiClient.disconnect_signal("region_changed", apply_view)
	UiClient.disconnect_signal("battle_opened", open_battle)
	UiClient.disconnect_signal("battle_closed", close_battle)
	UiClient.disconnect_signal("events_received", _on_events)

## 上半部（HUD 以上）的全寬區域
func _top_area(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.offset_bottom = -HUD_H

func _build() -> void:
	# 場景區背景
	backdrop = SceneBackdrop.new()
	_top_area(backdrop)
	add_child(backdrop)

	# 左上聊天／系統浮層
	message_log = MessageLog.new()
	message_log.gate = gate
	message_log.position = OVERLAY_RECT.position
	message_log.size = OVERLAY_RECT.size
	add_child(message_log)

	# 場景卷軸
	scene_panel = ScenePanel.new()
	scene_panel.gate = gate
	add_child(scene_panel)
	scene_panel.moved.connect(_on_scene_moved)

	# 右上小地圖
	mini_map = MiniMap.new()
	mini_map.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mini_map.offset_left = -(LANTERN_W + 16.0 + MINI_SIZE.x)
	mini_map.offset_right = -(LANTERN_W + 16.0)
	mini_map.offset_top = 8
	mini_map.offset_bottom = 8 + MINI_SIZE.y
	mini_map.open_requested.connect(func(): toggle_panel(MAP_PANEL))
	add_child(mini_map)
	mini_map.visible = UiSettings.get_bool("ui.minimap")

	# 右緣燈籠
	lanterns = LanternMenu.new()
	lanterns.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lanterns.offset_left = -(LANTERN_W + 8.0)
	lanterns.offset_right = -8
	lanterns.offset_top = 40
	lanterns.panel_requested.connect(toggle_panel)
	add_child(lanterns)
	lanterns.ensure_built()
	for pid in lanterns.lanterns:
		panel_buttons[pid] = lanterns.lanterns[pid]
	panel_buttons[MAP_PANEL] = mini_map.map_button

	# 隊伍面板（小地圖下方）與組隊／叫戰提示框（聊天浮層右邊）
	party_frame = PartyFrame.new()
	party_frame.name = "PartyFrame"
	party_frame.gate = gate
	party_frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	add_child(party_frame)
	pending_prompts = PendingPrompts.new()
	pending_prompts.name = "PendingPrompts"
	pending_prompts.gate = gate
	pending_prompts.visible = false
	add_child(pending_prompts)
	villain_prompt = VillainPrompt.new()
	villain_prompt.name = "VillainPrompt"
	villain_prompt.gate = gate
	add_child(villain_prompt)
	villain_prompt.ensure_built()
	villain_prompt.visibility_changed.connect(_place_villain)

	# 思過處提示列：場景區上緣、聊天浮層右邊（不蓋左上的聊天／系統浮層；M3a UI 審查 #2），位置在 _place_jail_banner
	jail_banner = PanelContainer.new()
	jail_banner.name = "JailBanner"
	var jst := StyleBoxFlat.new()
	jst.bg_color = Color(0.35, 0.05, 0.05, 0.88)
	jst.border_color = UiTheme.JY_GOLD
	jst.set_border_width_all(1)
	jst.set_corner_radius_all(4)
	jst.content_margin_left = 14
	jst.content_margin_right = 14
	jst.content_margin_top = 4
	jst.content_margin_bottom = 4
	jail_banner.add_theme_stylebox_override("panel", jst)
	jail_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jail_banner.visible = false
	jail_label = UiBuild.label(jail_banner, "", 17)
	jail_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(jail_banner)

	# 底部 HUD
	hud = BottomHud.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hud.offset_top = -HUD_H
	add_child(hud)
	hud.ensure_built()
	status_bar = hud.status_bar
	hotbar = hud.hotbar
	hotbar.gate = gate
	hotbar.activated.connect(run_command)
	message_log.build_input(hud.chat_row)
	message_log.build_announce(hud.announce_host)

	# 視窗層（蓋在場景區上，不蓋 HUD）
	panel_layer = CenterContainer.new()
	_top_area(panel_layer)
	panel_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel_layer)
	panel_frame = PanelContainer.new()
	panel_frame.add_theme_stylebox_override("panel", UiFrame.style(UiFrame.Kind.JADE))
	panel_frame.custom_minimum_size = Vector2(760, 470)
	panel_frame.visible = false
	panel_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	panel_layer.add_child(panel_frame)
	var pv := UiBuild.vbox(panel_frame, 6)
	var ph := UiBuild.hbox(pv, 8)
	panel_title = UiBuild.title(ph, "")
	panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_close = UiBuild.close_button(ph, "關閉(Esc)", close_panel)
	panel_host = UiBuild.vbox(pv, 6)
	panel_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_feedback = PanelFeedback.new()
	pv.add_child(panel_feedback)
	var classes := {
		"skills": SkillsPanel, "attributes": AttributesPanel, "inventory": InventoryPanel,
		"commands": CommandPanel, "system": SystemPanel, QUEST_PANEL: QuestPanel,
	}
	for pid in UiKeys.PANELS + UiKeys.EXTRA_PANELS:
		var p: Control = classes[pid].new()
		p.set("gate", gate)
		if "feedback" in p:
			p.set("feedback", panel_feedback)
		p.visible = false
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel_host.add_child(p)
		panels[pid] = p
	command_panel = panels["commands"]
	command_panel.command_invoked.connect(func(id: String, b: Button): run_command(Hotbar.CMD_PREFIX + id, b))
	var sys: SystemPanel = panels["system"]
	sys.navigate.connect(_on_system_nav)
	sys.message_log = message_log
	sys.option_changed.connect(_on_option_changed)
	sys.server_options_requested.connect(open_server_options)
	(panels[QUEST_PANEL] as QuestPanel).hint_requested.connect(show_quest_hint)
	(panels["attributes"] as AttributesPanel).look_change_requested.connect(open_look_dialog)   # M3c WP-LOOKS
	# 大地圖（ui/game/map）：Ctrl+M（原作）與 M
	map_panel = MapPanel.new()
	map_panel.gate = gate
	map_panel.visible = false
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_host.add_child(map_panel)
	panels[MAP_PANEL] = map_panel
	# M3c WP-NAV：小地圖點房間／「往XXX」／返回／停止／右鍵快捷都交給 MapPanel
	map_panel.bind_mini_map(mini_map)

	# 對話框層
	dialog_layer = CenterContainer.new()
	_top_area(dialog_layer)
	dialog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dialog_layer)
	_fit_panel_layer()
	npc_dialog = NpcDialog.new()
	shop_dialog = ShopDialog.new()
	learn_dialog = LearnDialog.new()
	corpse_dialog = CorpseDialog.new()
	mail_dialog = MailDialog.new()
	server_dialog = ServerOptionsDialog.new()
	confirm_dialog = ConfirmDialog.new()
	scout_dialog = ScoutDialog.new()
	scout_dialog.name = "ScoutDialog"
	story_dialog = StoryDialog.new()
	story_dialog.name = "StoryDialog"
	bank_window = BankWindow.new()
	bank_window.name = "BankWindow"
	escort_window = EscortWindow.new()
	escort_window.name = "EscortWindow"
	craft_window = CraftWindow.new()
	craft_window.name = "CraftWindow"
	org_panel = OrgPanel.new()
	org_panel.name = "OrgPanel"
	seize_dialog = SeizeDialog.new()
	seize_dialog.name = "SeizeDialog"
	for d in _dialogs():
		d.gate = gate
		d.visible = false
		dialog_layer.add_child(d)
	# 組隊／叫戰提示要畫在視窗之上（M2 審查：飛鴿、屍體視窗蓋住提示文字，只剩「接受」露在外面，可能誤接叫戰）；
	# 有提示時對話框層往下讓出提示列（_fit_dialog_layer），兩者不重疊
	move_child(pending_prompts, -1)
	move_child(villain_prompt, -1)   # 惡人警告也在視窗之上（非模態，不擋其他操作）
	pending_prompts.resized.connect(_fit_dialog_layer)
	pending_prompts.visibility_changed.connect(_fit_dialog_layer)
	party_frame.confirm_requested.connect(ask_confirm)
	scene_panel.player_action.connect(_on_player_action)
	scene_panel.npc_attack_requested.connect(request_npc_attack)
	scene_panel.corpse_opened.connect(open_corpse)
	scene_panel.craft_requested.connect(open_craft)
	npc_dialog.window_requested.connect(_on_npc_window)
	hud.pigeon.pressed.connect(open_mail)
	_m3d_combat_build()   # M3d WP-COMBAT：默契視窗、夜晚變暗
	_apply_scale()
	resized.connect(_layout_scene)
	_layout_scene()

## 場景卷軸的位置（記在 settings.json 的 ui.scene_pos）與大小（寬 632、高到 HUD 上緣）
func _layout_scene() -> void:
	if scene_panel == null:
		return
	var area := Vector2(size.x, size.y - HUD_H)
	var h := maxf(200.0, area.y - SCENE_POS.y - 8.0)
	scene_panel.size = Vector2(SCENE_W, h)
	var p: Variant = UiSettings.get_value("ui.scene_pos", null)
	var pos := SCENE_POS
	if p is Array and (p as Array).size() >= 2:
		pos = Vector2(float(p[0]), float(p[1]))
	scene_panel.position = ScenePanel.clamp_into(pos, scene_panel.size, area)

	_layout_social()

## 隊伍面板：右邊欄（燈籠左邊），小地圖開著時放在小地圖下方；提示框：聊天浮層右邊、場景區上緣
func _layout_social() -> void:
	if party_frame == null:
		return
	var top := 8.0
	if mini_map != null and mini_map.visible:
		top += MINI_SIZE.y + 8.0
	party_frame.offset_left = -(LANTERN_W + 16.0 + MINI_SIZE.x)
	party_frame.offset_right = -(LANTERN_W + 16.0)
	party_frame.offset_top = top
	party_frame.offset_bottom = top
	var x := OVERLAY_RECT.end.x + 8.0
	var right := size.x - right_reserve() - 8.0
	pending_prompts.position = Vector2(x, 8.0)
	pending_prompts.size = Vector2(maxf(260.0, minf(420.0, right - x)), 0)
	_fit_dialog_layer()
	_place_villain()

## 惡人警告：聊天浮層右邊，組隊／叫戰提示列下方；那一段放不下（視窗太窄）就放到聊天浮層下方
func _place_villain() -> void:
	if villain_prompt == null or not villain_prompt.visible:
		return
	var w := villain_prompt.get_combined_minimum_size()
	w.x = maxf(w.x, 360.0)
	var x0 := OVERLAY_RECT.end.x + 8.0
	var x1 := size.x - right_reserve() - 8.0
	var y := prompt_band_bottom() + 4.0 if pending_prompts != null and pending_prompts.visible else 8.0
	var pos := Vector2(x0 + maxf(0.0, (x1 - x0 - w.x) / 2.0), y)
	if x1 - x0 < w.x:
		pos = Vector2(OVERLAY_RECT.position.x, OVERLAY_RECT.end.y + 8.0)
	villain_prompt.position = pos
	villain_prompt.size = w

## 提示列顯示時，對話框層的上緣移到提示列下方（對話框置中在剩下的區域）
func _fit_dialog_layer() -> void:
	if dialog_layer == null or pending_prompts == null:
		return
	dialog_layer.offset_top = prompt_band_bottom()

func prompt_band_bottom() -> float:
	if pending_prompts == null or not pending_prompts.visible:
		return 0.0
	return pending_prompts.position.y + pending_prompts.get_combined_minimum_size().y + 4.0

func _dialogs() -> Array:
	return [npc_dialog, shop_dialog, learn_dialog, corpse_dialog, mail_dialog, server_dialog, confirm_dialog, scout_dialog, story_dialog,
		bank_window, escort_window, craft_window, org_panel, seize_dialog, look_dialog] + m3d_dialogs

func _on_scene_moved(pos: Vector2) -> void:
	UiSettings.set_value("ui.scene_pos", [int(pos.x), int(pos.y)])

func _apply_scale() -> void:
	var sc := float(UiSettings.get_value("ui.scale", 1.0))
	if is_inside_tree() and sc > 0.0 and not is_equal_approx(get_tree().root.content_scale_factor, sc):
		get_tree().root.content_scale_factor = sc

func _on_option_changed(key: String, value: Variant) -> void:
	match key:
		"ui.minimap":
			mini_map.visible = bool(value) and not _battle_open()
			_fit_panel_layer()
		"ui.scale":
			_apply_scale()
		"ui.atb_list", "ui.damage_text", "ui.grid_lines":
			if _battle_open():
				battle.apply_options()
		UiKeys.SETTING_NIGHT_DIM:
			_m3d_night_refresh()

# ---------- 資料 ----------
func apply_sheet(s: Dictionary) -> void:
	sheet = s
	hud.apply_sheet(s)
	scene_panel.apply_sheet(s)
	party_frame.apply_sheet(s)
	pending_prompts.apply_sheet(s)
	message_log.set_admin(bool(s.get("is_admin", false)))
	_update_jail_banner()
	var warns := SectUi.warnings(s)
	var lt: JyButton = lanterns.lanterns.get("attributes", null)
	if lt != null:
		lt.self_modulate = Color(1.0, 0.45, 0.45) if not warns.is_empty() else Color.WHITE
		lt.tooltip_text = "查看屬性（快捷鍵：Ctrl+2）" + ("
%s：%s" % [UiKeys.SECT_WARN_TIP, "、".join(PackedStringArray(
			warns.map(func(k): return str(UiKeys.SECT_WARN_LABELS.get(str(k), str(k))))))] if not warns.is_empty() else "")
	for pid in panels:
		if panels[pid].has_method("apply_sheet"):
			panels[pid].apply_sheet(s)
	for d in [bank_window, escort_window, craft_window, org_panel]:
		d.apply_sheet(s)
	_m3d_combat_sheet(s)   # M3d WP-COMBAT

func apply_view(v: Dictionary) -> void:
	if _battle_settling():
		_deferred_view = v
		return
	_deferred_view = {}
	view = v
	scene_panel.apply_view(v)
	map_panel.apply_view(v)
	hud.apply_view(v)
	command_panel.apply_view(v)
	backdrop.set_region(str(v.get("region", "")))
	# 換房間時關掉 NPC 相關對話框（M3b：錢莊、鏢局、書吏段的組織面板也一樣）
	var npc_bound: Array = [npc_dialog, shop_dialog, learn_dialog, bank_window, escort_window]
	if org_panel.npc_id() != "":
		npc_bound.append(org_panel)
	for d in npc_bound:
		if d.visible and not _npc_present(v, _dialog_npc(d)):
			d.close()
	craft_window.apply_view(v)
	seize_dialog.apply_view(v)
	if combo_dialog != null:
		combo_dialog.apply_view(v)   # M3d WP-COMBAT
	corpse_dialog.refresh_from_view(v)
	var room := str(v.get("room", ""))
	scout_dialog.on_room(room)
	# 移動：主機已清掉對話游標（§4.5）→ 任務對話直接收起；惡人警告＝已離開那個房間
	if room != "" and _last_room != "" and room != _last_room:
		story_dialog.dismiss()
	villain_prompt.on_room(room)
	if room != "":
		_last_room = room

func _dialog_npc(d: Control) -> String:
	return str(d.call("npc_id")) if d.has_method("npc_id") else ""

func _npc_present(v: Dictionary, npc: String) -> bool:
	for n in v.get("npcs", []):
		if n is Dictionary and str(n.get("id", "")) == npc:
			return true
	return false

# ---------- 指令（指令窗、熱鍵列） ----------
## payload："cmd:<id>" 或 "item:<item id>"（UiCommands）
func run_command(payload: String, b: Button = null) -> void:
	var lock: Array = [b] if b != null else []
	if payload.begins_with(Hotbar.ITEM_PREFIX):
		var it := UiCommands.find_item(sheet, payload.trim_prefix(Hotbar.ITEM_PREFIX))
		if it.is_empty():
			return
		var uid := str(it.get("uid", ""))
		if bool(it.get("usable", false)):
			send(UiKeys.I_USE_ITEM, { "item_uid": uid }, lock)
		elif bool(it.get("equippable", false)) and str(it.get("equipped_slot", "")) == "" and not _battle_open():
			send(UiKeys.I_EQUIP, { "item_uid": uid }, lock)
		return
	var id := payload.trim_prefix(Hotbar.CMD_PREFIX)
	if _battle_open():
		return
	match id:
		"look":
			# 主機開著查看偵察才帶 scout（舊主機不認得這個參數）
			send(UiKeys.I_LOOK, { "scout": true } if UiClient.scout_enabled() else {}, lock)
		"meditate":
			send(UiKeys.I_MEDITATE, {}, lock)
		"exert_qi", "exert_jing", "exert_shen":
			send(UiKeys.I_EXERT, { "stat": id.trim_prefix("exert_") }, lock)
		"quests":
			toggle_panel(QUEST_PANEL)
		"map":
			toggle_panel(MAP_PANEL)
		"craft":
			open_craft()
		"org":
			open_org()
		"seize":
			open_seize()
		"beg":
			var npc := SectUi.beg_target(view, sheet, npc_dialog.npc_id())
			if npc == "":
				message_log.add_error(UiCommands.unavailable_reason("beg", sheet, view))
				return
			send(UiKeys.I_BEG, { "npc": npc }, lock)
		_:
			if UiCommands.is_work(id):
				var sk := id.substr(UiCommands.WORK_PREFIX.length())
				if sk == UiKeys.LIFE_COOKING:
					close_panel()
					scene_panel.open_recipes_for_known()
				else:
					scene_panel._on_work(sk, "", b if b != null else Button.new())

# ---------- 視窗 ----------
func toggle_panel(pid: String) -> void:
	if current_panel == pid and panel_frame.visible:
		close_panel()
	else:
		open_panel(pid)

## in_battle_ok：戰鬥中由圓盤「屬」「系」開（唯讀的屬性窗、系統窗）
func open_panel(pid: String, in_battle_ok := false) -> void:
	if not panels.has(pid):
		return
	if _battle_open() and not (in_battle_ok and pid in ["attributes", "system"]):
		return
	_close_dialogs()
	for k in panels:
		panels[k].visible = k == pid
	current_panel = pid
	panel_feedback.reset()
	panel_feedback.visible = pid != MAP_PANEL   # 地圖窗有自己的頁尾狀態列；回饋列只會在頁尾下面留一塊空白（審查 round 3）
	panel_title.text = UiKeys.PANEL_LABELS.get(pid, pid)
	var kind: String = UiKeys.PANEL_FRAMES.get(pid, "JADE")
	panel_frame.add_theme_stylebox_override("panel", UiFrame.style(UiFrame.Kind[kind]))
	_fit_panel_layer()
	var want: Vector2 = UiKeys.PANEL_SIZES.get(pid, Vector2(760, 470))
	var avail := panel_area_size() - Vector2(PANEL_MARGIN, PANEL_MARGIN) * 2.0
	panel_frame.custom_minimum_size = want.min(avail.max(Vector2(400, 300)))
	panel_frame.size = Vector2.ZERO
	if panels[pid].has_method("apply_sheet") and not sheet.is_empty():
		panels[pid].apply_sheet(sheet)
	if pid == "commands":
		command_panel.apply_view(view)
	panel_frame.visible = true
	if _battle_open():
		move_child(panel_layer, get_child_count() - 1)

## 視窗層只用右邊欄（小地圖＋燈籠）以左的區域：審查 round 3——1280×720 時商店／武功／裝備窗蓋住小地圖左欄，
## 1920 時地圖窗右緣蓋到燈籠
func right_reserve() -> float:
	var r := LANTERN_W + 16.0
	if mini_map != null and mini_map.visible:
		r += MINI_SIZE.x + 8.0
	return r

func _fit_panel_layer() -> void:
	for layer in [panel_layer, dialog_layer]:
		if layer != null:
			(layer as Control).offset_right = -right_reserve()

## 視窗可用的大小（HUD 以上、右邊欄以左）
func panel_area_size() -> Vector2:
	var vs := get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	return Vector2(vs.x - right_reserve(), vs.y - HUD_H)

func close_panel() -> void:
	panel_frame.visible = false
	current_panel = ""

func _close_dialogs() -> bool:
	var any := false
	for d in _dialogs():
		if d.visible:
			d.close()
			any = true
	return any

func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_ESCAPE:
		# 1. 正在打字：Esc 只放開輸入框（不然 M 等字母鍵會一直打進聊天框）
		if _typing():
			get_viewport().gui_get_focus_owner().release_focus()
		elif map_panel.esc_stop():
			pass   # M3c WP-NAV：趕路中 Esc 先停止趕路（不關視窗、不收燈籠）
		elif _close_dialogs():
			pass
		elif panel_frame.visible:
			close_panel()
		elif not _battle_open():
			lanterns.set_collapsed(not lanterns.collapsed, false)   # 最後才收合燈籠（不記住，下次開遊戲照常展開）
		else:
			return
		get_viewport().set_input_as_handled()
		return
	var mods := k.ctrl_pressed or k.alt_pressed or k.meta_pressed or k.shift_pressed
	# 物品熱鍵 Alt+1–8：戰鬥中也可以吃藥
	if k.alt_pressed and not k.ctrl_pressed and k.keycode >= KEY_1 and k.keycode <= KEY_8:
		hotbar.trigger(Hotbar.ROW_ITEM, k.keycode - KEY_1)
		get_viewport().set_input_as_handled()
		return
	if _battle_open():
		return   # 戰鬥畫面蓋住場景區：視窗與地圖都不開（戰鬥快捷鍵由 BattleScreen 處理）
	if k.keycode >= KEY_F1 and k.keycode <= KEY_F8 and not mods:
		hotbar.trigger(Hotbar.ROW_CMD, k.keycode - KEY_F1)
		get_viewport().set_input_as_handled()
		return
	if not mods and k.physical_keycode in WASD_KEYS and not _typing():
		get_viewport().set_input_as_handled()
		_wasd_queue(k.physical_keycode)
		return
	if k.keycode == KEY_M and not k.alt_pressed and not k.meta_pressed and (k.ctrl_pressed or not _typing()):
		toggle_panel(MAP_PANEL)
		get_viewport().set_input_as_handled()
		return
	if k.ctrl_pressed and not k.alt_pressed and k.keycode >= KEY_1 and k.keycode <= KEY_5:
		toggle_panel(UiKeys.PANELS[k.keycode - KEY_1])
		get_viewport().set_input_as_handled()
		return
	if k.ctrl_pressed and not k.alt_pressed and k.keycode == UiKeys.QUESTS_HOTKEY:
		toggle_panel(QUEST_PANEL)
		get_viewport().set_input_as_handled()

## WASD 走路：W 北、S 南、A 西、D 東；兩鍵一起按走斜向（W+A 西北、W+D 東北、S+A 西南、S+D 東南）。
## 第一個鍵按下後等 WASD_COMBO_S 收集同時按的鍵，再照出口鈕走一步（沒有那個出口就不動）。
## 用實體鍵位（physical_keycode），換鍵盤配置也一樣在左手位置。
const WASD_KEYS := [KEY_W, KEY_A, KEY_S, KEY_D]
const WASD_COMBO_S := 0.08
var _wasd_pending := false
var _wasd_seen: Dictionary = {}

func _wasd_queue(key: int) -> void:
	_wasd_seen[key] = true
	if _wasd_pending:
		return
	_wasd_pending = true
	await get_tree().create_timer(WASD_COMBO_S).timeout
	_wasd_pending = false
	var held := func(kc: int) -> bool: return _wasd_seen.has(kc) or Input.is_physical_key_pressed(kc)
	var dir := wasd_dir(held.call(KEY_W), held.call(KEY_S), held.call(KEY_A), held.call(KEY_D))
	_wasd_seen.clear()
	if dir == "" or not is_inside_tree() or _battle_open() or _typing():
		return
	for d in _dialogs():
		if d.visible:
			return   # 對話、商店等視窗開著時不走（免得視窗內容跟所在房間對不上）
	if map_panel.is_walking():
		map_panel.esc_stop()   # 自己按方向就停止自動趕路
	scene_panel.key_move(dir)

## 四個鍵的狀態 → 方向碼（N/S/E/W/NE/NW/SE/SW；相反的鍵互相抵消；都沒有 → ""）
static func wasd_dir(n: bool, s: bool, w: bool, e: bool) -> String:
	var v := "N" if n and not s else ("S" if s and not n else "")
	var h := "W" if w and not e else ("E" if e and not w else "")
	return v + h

## 正在打字（聊天框等）時 M 不開地圖
func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit

func _battle_open() -> bool:
	return battle != null and is_instance_valid(battle)

## 戰鬥已經分出勝負（結束，或我已倒下／逃走），畫面還沒收：這時來的房間更新是重生後的位置，先不套用
func _battle_settling() -> bool:
	if not _battle_open() or battle.vm == null:
		return false
	return battle.vm.ended or str(battle.vm.me().get("state", "")) in ["DEAD", "FLED"]

func _on_system_nav(scene_name: String) -> void:
	if scene_name == "title":
		var nm := _nm()
		_leaving = true
		if nm:
			nm.leave()
		_leaving = false
	go(scene_name)

# ---------- 事件 ----------
func _on_events(batch: Array) -> void:
	for e in batch:
		if e is Dictionary:
			handle_event(e)

func handle_event(e: Dictionary) -> void:
	var key := str(e.get("key", ""))
	var p: Dictionary = e.get("p", {})
	if key.begins_with(UiKeys.TALK_PREFIX):
		last_talk_text = TextRenderer.render_plain(e, UiClient.my_peer(), UiClient.templates())
		scene_panel.show_bubble(str(p.get("npc", key.trim_prefix(UiKeys.TALK_PREFIX))), last_talk_text)
		return
	if _m3d_dispatch(key, p):   # M3d（M3D_PLAN §9.2）：各 WP 的事件先處理；回 true＝已處理
		return
	match key:
		UiKeys.E_NPC_MENU:
			if bool(p.get("refresh", false)):
				# 接／交任務後主機重送的選單：只更新已開著的同一位 NPC，不另開（玩家可能已經關掉）
				if npc_dialog.visible and npc_dialog.npc_id() == str(p.get("npc", "")):
					npc_dialog.refresh_menu(p)
				if escort_window.visible and escort_window.npc_id() == str(p.get("npc", "")):
					escort_window.refresh_menu(p)
				if org_panel.visible and org_panel.npc_id() == str(p.get("npc", "")) and org_panel.npc_id() != "":
					org_panel.refresh_menu(p)
				return
			_show_dialog(npc_dialog)
			npc_dialog.open_menu(p, last_talk_text)
			last_talk_text = ""
		UiKeys.E_SHOP_LIST:
			_show_dialog(shop_dialog)
			shop_dialog.open_shop(p)
		UiKeys.E_TEACH_LIST:
			if not p.has("teach_blocked") and npc_dialog.npc_id() == str(p.get("npc", "")):
				p = p.duplicate()
				p["teach_blocked"] = str(npc_dialog.menu.get("teach_blocked", ""))
			_show_dialog(learn_dialog)
			learn_dialog.open_list(p)
		UiKeys.E_SCOUT_OFFER:
			if _battle_open():
				return
			_show_dialog(scout_dialog)
			scout_dialog.open_offer(p)
		UiKeys.E_SCOUT_CLOSED:
			scout_dialog.on_closed(p)
		UiKeys.E_DIALOGUE:
			if _battle_open():
				return
			last_talk_text = ""
			if not story_dialog.visible:
				_show_dialog(story_dialog)
			story_dialog.open_node(p)
		UiKeys.E_DIALOGUE_CLOSE:
			story_dialog.on_closed(p)
		UiKeys.E_VILLAIN_PROMPT:
			if _battle_open():
				return
			villain_prompt.open_prompt(p, str(view.get("room", "")))
			_place_villain()
		UiKeys.E_VILLAIN_CLEAR:
			villain_prompt.on_clear(p)
		# M3b
		UiKeys.E_BANK_VIEW:
			if _battle_open():
				return
			var bnpc := str(p.get("npc", ""))
			if bnpc == "":
				bnpc = bank_window.npc_id() if bank_window.visible else npc_dialog.npc_id()
			if not bank_window.visible:
				_show_dialog(bank_window)
			bank_window.open_view(p, bnpc)
		UiKeys.E_CONSIGN_LIST:
			escort_window.apply_list(p)
		UiKeys.E_ORG_INFO:
			org_panel.apply_info(p)
		UiKeys.E_ORG_INVITE:
			pending_prompts.add_org_invite(p)
		UiKeys.E_LOOK_CHANGED:
			on_look_changed(e)
		UiKeys.E_RUMOR_LIST:
			var items: Variant = p.get("items", [])
			(panels["system"] as SystemPanel).apply_rumor_list(items if items is Array else [])

func _show_dialog(d: Control) -> void:
	close_panel()
	_fit_panel_layer()
	for x in _dialogs():
		if x != d:
			x.visible = false

# ---------- M2：玩家、屍體、飛鴿、伺服器設定 ----------
## 場景卷軸玩家選單的動作（UiSocial.ACT_*）
func _on_player_action(action: String, p: Dictionary) -> void:
	var cid := str(p.get("char_id", ""))
	var name := str(p.get("name", "?"))
	match action:
		UiSocial.ACT_INVITE:
			send(UiKeys.I_PARTY_INVITE, { "target": cid })
		UiSocial.ACT_CHALLENGE:
			var why := UiSocial.challenge_block(p, view, sheet, UiClient.pk_mode())
			if why != "":
				message_log.add_error(why)
				return
			send(UiKeys.I_CHALLENGE, { "target": cid })
		UiSocial.ACT_WHISPER:
			message_log.start_whisper(name)
		UiSocial.ACT_MAIL:
			_show_dialog(mail_dialog)
			mail_dialog.compose_to(name)
		UiSocial.ACT_KICK:
			ask_confirm("請出隊伍", "確定要把%s請出隊伍？" % name, "請出", func(): send(UiKeys.I_PARTY_KICK, { "target": cid }))
		UiSocial.ACT_LEAD:
			ask_confirm("移交領隊", "確定要把領隊交給%s？" % name, "移交", func(): send(UiKeys.I_PARTY_LEAD, { "target": cid }))
		UiSocial.ACT_FORCE_PK:
			request_force_pk(p)
		UiSocial.ACT_SEIZE:
			_show_dialog(seize_dialog)
			seize_dialog.open_for(p, view)
		UiSocial.ACT_ORG_INVITE:
			send(UiKeys.I_ORG_INVITE, { "name": name })
		UiSocial.ACT_ROB:
			m3d_events_open_rob(p)   # M3d 整合：WP-EVENTS 劫鏢確認

## Ctrl+點玩家名：本機就知道不行（新手、不能動手的地方、PK 模式、同隊）→ 直接顯示原因、不送；否則確認框
func request_force_pk(p: Dictionary) -> void:
	var why := UiSocial.force_pk_block(p, view, sheet, UiClient.pk_mode())
	if why != "":
		message_log.add_error(why)
		return
	var cid := str(p.get("char_id", ""))
	# 善惡的後果依對方的 align（殺惡人 +10，其餘 −10；M2_PLAN 5.2）；自己的善惡／PK 值決定會不會挨官兵
	ask_confirm("強行出手", UiSocial.force_pk_confirm_text(p, sheet), "出手", func(): send(UiKeys.I_FORCE_PK, { "target": cid }), true)

## 確認框（強行出手、隊伍的踢人／移交／離隊）：按「確定」才呼叫 on_ok；danger＝確定鈕染紅（強行出手）
func ask_confirm(title: String, message: String, ok_label: String, on_ok: Callable, danger := false, cancel_label := "取消") -> void:
	_show_dialog(confirm_dialog)
	confirm_dialog.open_confirm(title, message, ok_label, on_ok, danger, cancel_label)

# ---------- M3b：錢莊、鏢局、製作、組織、捉拿 ----------
## NPC 選單「鏢局」「組織」（書吏）
func _on_npc_window(kind: String, menu: Dictionary) -> void:
	match kind:
		"ESCORT":
			_show_dialog(escort_window)
			escort_window.open_menu(menu)
		"ORG":
			_show_dialog(org_panel)
			org_panel.open_clerk(menu)

func open_craft() -> void:
	if _battle_open():
		return
	_show_dialog(craft_window)
	craft_window.open_craft(view, sheet)

func open_org() -> void:
	if _battle_open():
		return
	_show_dialog(org_panel)
	org_panel.open_panel()

func open_seize() -> void:
	if _battle_open():
		return
	_show_dialog(seize_dialog)
	seize_dialog.open_list(view)

func open_corpse(c: Dictionary) -> void:
	_show_dialog(corpse_dialog)
	corpse_dialog.open_corpse(c)

func open_mail() -> void:
	if mail_dialog.visible:
		mail_dialog.close()
		return
	_show_dialog(mail_dialog)
	mail_dialog.open_inbox()

## 任務窗「在地圖上標出」：打開地圖、標記提示地點
func show_quest_hint(room_id: String) -> void:
	if _battle_open() or room_id == "":
		return
	open_panel(MAP_PANEL)
	map_panel.set_quest_mark(room_id)

func open_server_options() -> void:
	if not UiClient.is_admin() and not bool(sheet.get("is_admin", false)):
		return
	_show_dialog(server_dialog)
	server_dialog.open_panel()

# ---------- 戰鬥 ----------
func open_battle(state: Dictionary) -> void:
	if battle != null and is_instance_valid(battle):
		battle.queue_free()
	map_panel.on_battle()
	close_panel()
	story_dialog.dismiss()
	villain_prompt.dismiss()
	law_hide_banner()   # M3d 審查：開戰就收起賞金獵人橫幅
	for d in _dialogs():
		d.visible = false
	var scene := load(BATTLE_SCENE) as PackedScene
	battle = scene.instantiate() as BattleScreen
	add_child(battle)
	_top_area(battle)
	battle.setup(state)
	battle.finished.connect(_on_battle_finished)
	battle.panel_requested.connect(func(pid: String): open_panel(pid, true))
	lanterns.visible = false
	mini_map.visible = false
	party_frame.visible = false
	hud.set_in_battle(true)

func close_battle(result: Dictionary) -> void:
	if battle == null or not is_instance_valid(battle):
		return
	map_panel.on_battle_result(result)   # M3c WP-NAV：趕路續走依我的結算
	# M3c 審查：主機先送 battle_close、同一輪才送最後一批戰鬥事件（含最後一擊）；晚一拍再顯示結果，
	# 最後一擊的動畫與武器特效才排得進去（結果框等它播完，BattleScreen.show_result）
	battle.call_deferred("show_result", result)

func _on_battle_finished() -> void:
	if battle != null and is_instance_valid(battle):
		battle.queue_free()
	battle = null
	close_panel()
	lanterns.visible = true
	mini_map.visible = UiSettings.get_bool("ui.minimap")
	party_frame.apply_sheet(sheet)
	_layout_social()
	hud.set_in_battle(false)
	if not sheet.is_empty():
		hud.apply_sheet(sheet)
	if not _deferred_view.is_empty():
		apply_view(_deferred_view)
	map_panel.on_battle_closed()   # M3c WP-NAV：遇敵獲勝 → 0.5 秒後續走（nav.auto_resume）；否則寫原因停止

func _process(_delta: float) -> void:
	if _battle_open() and battle.vm != null:
		status_bar.apply_battle_unit(battle.vm.me())
	if jail_banner != null and jail_banner.visible:
		_update_jail_banner()
	if villain_prompt != null and villain_prompt.visible:
		_place_villain()   # 提示列出現／消失時跟著上下移

## 思過處提示列：sheet.jail（{ sect_name, room_name, left_s }）；不在坐牢就收起來
func _update_jail_banner() -> void:
	var j: Variant = sheet.get("jail", null)
	if not (j is Dictionary) or (j as Dictionary).is_empty():
		jail_banner.visible = false
		return
	var left := SectUi.left_now(float(j.get("left_s", 0)), int(sheet.get(CooldownTracker.RX_KEY, 0)))
	var t := SectUi.jail_banner(j, left)
	if jail_label.text != t:
		jail_label.text = t
		jail_banner.reset_size()
	jail_banner.visible = true
	_place_jail_banner()

## 提示列放在聊天浮層（OVERLAY_RECT）右邊到右邊欄之間置中；有待回覆提示框時放在它下面；
## 那一段放不下（視窗太窄）就放到聊天浮層下方
func _place_jail_banner() -> void:
	var w := jail_banner.get_combined_minimum_size()
	var x0 := OVERLAY_RECT.end.x + 8.0
	var x1 := size.x - right_reserve() - 8.0
	var y := 8.0
	if pending_prompts != null and pending_prompts.visible:
		y = prompt_band_bottom() + 4.0
	var pos := Vector2(x0 + maxf(0.0, (x1 - x0 - w.x) / 2.0), y)
	if x1 - x0 < w.x:
		pos = Vector2(OVERLAY_RECT.position.x, OVERLAY_RECT.end.y + 8.0)
	jail_banner.position = pos
	jail_banner.size = w

func jail_text() -> String:
	return jail_label.text if jail_banner.visible else ""

## 場景區背景：目前地區的背景圖（ArtRegistry，與戰鬥同一組）以 cover 鋪滿，再疊黑色 35% 壓暗；
## 沒有圖時用雕木暗色加暗角
class SceneBackdrop extends Control:
	const DIM := Color(0, 0, 0, 0.35)
	var tex: Texture2D
	var region := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_region(rid: String) -> void:
		if rid == region:
			return
		region = rid
		tex = ArtRegistry.battle_background(rid) if rid != "" else null
		queue_redraw()

	func _draw() -> void:
		if tex != null:
			var ts := tex.get_size()
			var k := maxf(size.x / ts.x, size.y / ts.y)
			var ds := ts * k
			draw_texture_rect(tex, Rect2((size - ds) / 2.0, ds), false)
			draw_rect(Rect2(Vector2.ZERO, size), DIM)
			return
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.JY_WOOD_DARK)
		var side := size.x * 0.15
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(side, 0), Vector2(side, size.y), Vector2(0, size.y)]),
			PackedColorArray([Color(0, 0, 0, 0.4), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.4)]))
		draw_polygon(PackedVector2Array([Vector2(size.x - side, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(size.x - side, size.y)]),
			PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.4), Color(0, 0, 0, 0.4), Color(0, 0, 0, 0)]))

# ==== M3c WP-LOOKS ====
## 更換造型視窗（M3C_PLAN §3.4 第 3 點）：成員初始化時就建立，_build() 的 _dialogs() 迴圈把它放進對話框層並接上 gate
var look_dialog: LookDialog = LookDialog.new()

## 屬性視窗「更換造型」→ 依目前角色表開 LookDialog（送 set_look）
## M3c 審查：更換造型之後的回饋——訊息列印「你換上了…的打扮。」（look_changed 是 ui 事件，模板不會自動印），
## 並把剛才為了開造型視窗而關掉的屬性視窗重新打開（新的立繪在那裡看得到）
func on_look_changed(e: Dictionary) -> void:
	var plain := e.duplicate()
	plain.erase("ui")
	var t := TextRenderer.render_plain(plain, UiClient.my_peer(), UiClient.templates())
	if t != "":
		message_log.add_system(t)
	if _reopen_attrs_after_look and not _battle_open():
		_reopen_attrs_after_look = false
		open_panel("attributes")

var _reopen_attrs_after_look := false

func open_look_dialog() -> void:
	if look_dialog == null:
		return
	_reopen_attrs_after_look = current_panel == "attributes" and panel_frame.visible
	_show_dialog(look_dialog)
	look_dialog.open_for(UiClient.sheet())

# ==== M3c WP-NPCPK ====
## Ctrl+點 NPC 名（M3C_PLAN §5.8）：受保護（npcs[].atk 為 null）、戰鬥中、安全的地方 → 訊息列直接說原因、不送；
## 否則確認框（紅色「動手」；內文 NpcAttackUi.confirm_text：善惡、城內官兵、門派後果）→ npc_attack { npc, mode: ATTACK }
func request_npc_attack(p: Dictionary) -> void:
	var why := NpcAttackUi.block_reason(p, view, sheet)
	if why == "npc_not_attackable":
		message_log.add_system(NpcAttackUi.not_attackable_text(str(p.get("name", ""))))   # 「{name}不是你能動手的對象。」
		return
	if why != "":
		message_log.add_error(why)
		return
	var nid := str(p.get("id", ""))
	ask_confirm(NpcAttackUi.TITLE, NpcAttackUi.confirm_text(p, sheet, view), NpcAttackUi.OK_LABEL,
		func(): send(UiKeys.I_NPC_ATTACK, { "npc": nid, "mode": NpcAttackUi.MODE_ATTACK }), true, NpcAttackUi.CANCEL_LABEL)

# ==== M3d 事件分派（WP-COMBAT Day-0；M3D_PLAN §9.2） ====
## 各 WP 的新對話框：m3d_add_dialog(d) 放進對話框層、接上 gate、加入 _dialogs()（互斥、Esc 關）
var m3d_dialogs: Array = []

func m3d_add_dialog(d: Control) -> void:
	if d == null or m3d_dialogs.has(d):
		return
	d.set("gate", gate)
	d.visible = false
	if d.get_parent() == null:
		dialog_layer.add_child(d)
	m3d_dialogs.append(d)

## 依 UiKeys.M3D_*_EVENTS 把事件交給各 WP 的處理函式（各在下面自己的具名區塊，回 true＝已處理）。
## 不在任何清單裡的 key 也依序問一次（各 WP 可以處理自己新加的一般事件）；都回 false 就照舊往下。
func _m3d_dispatch(key: String, p: Dictionary) -> bool:
	if key in UiKeys.M3D_LAW_EVENTS:
		return _m3d_law_event(key, p)
	if key in UiKeys.M3D_COMBAT_EVENTS:
		return _m3d_combat_event(key, p)
	if key in UiKeys.M3D_ARTS_EVENTS:
		return _m3d_arts_event(key, p)
	if key in UiKeys.M3D_EVENTS_EVENTS:
		return _m3d_events_event(key, p)
	if key in UiKeys.M3D_ERRANDS_EVENTS:
		return _m3d_errands_event(key, p)
	return false

# ==== M3d WP-LAW ====
## 佈告欄名單（bounty_board → BountyDialog）、賞金獵人警告橫幅（law_hunter_warn，倒數；沒有回覆按鈕）。
## 其他 law_* 事件照一般文字顯示（回 false）。M3d 審查：名單視窗經 m3d_add_dialog 加入 _dialogs()（Esc 關、與其他視窗互斥）。
var bounty_dialog: BountyDialog = null
var law_banner: PanelContainer = null
var _law_banner_left := 0
var _law_banner_gen := 0   # M3d 審查：每次新的警告換一代，舊的計時器鏈自己停（不會兩條一起倒數）

func _m3d_law_event(key: String, p: Dictionary) -> bool:
	match key:
		UiKeys.E_BOUNTY_BOARD:
			if bounty_dialog == null:
				bounty_dialog = BountyDialog.new()
				bounty_dialog.name = "BountyDialog"
				m3d_add_dialog(bounty_dialog)
			_show_dialog(bounty_dialog)
			bounty_dialog.open_board(p)
			return true
		UiKeys.E_LAW_HUNTER_WARN:
			_law_show_banner(str(p.get("npc_name", "賞金獵人")), int(p.get("warn_s", 3)))
			return true   # 文字版（law_hunter_coming）另外送；這則 ui 事件本身不進訊息框
		UiKeys.E_LAW_HUNTER_ESCAPED, UiKeys.E_LAW_HUNTER_ATTACK:
			law_hide_banner()   # 離開房間（主機判定甩掉了）／打起來了：橫幅收起，文字照常顯示
			return false
	return false

## 收起賞金獵人橫幅（換房間、開戰、甩掉、追上）
func law_hide_banner() -> void:
	_law_banner_gen += 1
	_law_banner_left = 0
	if law_banner != null:
		law_banner.visible = false

func _law_show_banner(npc_name: String, secs: int) -> void:
	if law_banner == null:
		law_banner = PanelContainer.new()
		law_banner.name = "LawHunterBanner"
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.35, 0.05, 0.05, 0.9)
		st.border_color = UiTheme.JY_GOLD
		st.set_border_width_all(2)
		st.set_corner_radius_all(6)
		st.set_content_margin_all(8)
		law_banner.add_theme_stylebox_override("panel", st)
		law_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := UiBuild.label(law_banner, "", 18)
		l.name = "Text"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(law_banner)
		# M3d 審查：放在視窗層與對話框層底下（不蓋住 NPC 視窗的 ✕、比武報名的標題）
		var under := dialog_layer.get_index()
		if panel_layer != null and panel_layer.get_parent() == self:
			under = mini(under, panel_layer.get_index())
		move_child(law_banner, under)
	_law_banner_gen += 1
	_law_banner_left = maxi(0, secs)
	law_banner.visible = true
	_law_tick_banner(npc_name, _law_banner_gen)

func _law_tick_banner(npc_name: String, gen: int) -> void:
	if law_banner == null or not law_banner.visible or gen != _law_banner_gen:
		return
	var l := law_banner.get_node("Text") as Label
	l.text = "懸賞犯！%s逼近了——%d 秒內離開這裡就能甩掉他" % [npc_name, _law_banner_left] if _law_banner_left > 0 \
		else "%s追上來了！" % npc_name
	law_banner.reset_size()
	law_banner.position = Vector2((size.x - law_banner.size.x) / 2.0, 56.0)
	if _law_banner_left <= 0 or not is_inside_tree():
		if is_inside_tree():
			get_tree().create_timer(1.5).timeout.connect(func():
				if law_banner != null and _law_banner_left <= 0 and gen == _law_banner_gen:
					law_banner.visible = false)
		return
	_law_banner_left -= 1
	get_tree().create_timer(1.0).timeout.connect(func(): _law_tick_banner(npc_name, gen))

# ==== M3d WP-COMBAT ====
## 合體默契（M3D_PLAN §3.3.4）：燈籠「默契」→ ComboDialog；cb_bond_request（ui）→ 同一個視窗的「接受／拒絕」；
## cb_bond_changed（ui）→ 重畫（角色表的 combo 隨後也會更新）。
## 夜晚變暗（§3.5）：時鐘 night 且背包沒有 LIGHT 道具（夜明珠）→ 場景圖、小地圖、區域圖蓋一層深藍半透明（alpha 0.35），
## 小地圖只亮目前房間與相鄰房間；設定 ui.night_dim（預設開；純客戶端）。
var combo_dialog: ComboDialog
var night_scene: NightVeil
var night_mini: NightVeil
var night_map: NightVeil

func _m3d_combat_build() -> void:
	combo_dialog = ComboDialog.new()
	combo_dialog.name = "ComboDialog"
	m3d_add_dialog(combo_dialog)
	lanterns.combo_requested.connect(open_combo)
	night_scene = NightVeil.new()
	night_scene.name = "NightVeil"
	_top_area(night_scene)
	add_child(night_scene)
	move_child(night_scene, backdrop.get_index() + 1)   # 只蓋背景，不蓋聊天浮層與場景卷軸的字
	night_mini = NightVeil.new()
	night_mini.name = "NightVeilMini"
	night_mini.fog_view = mini_map.view
	night_mini.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mini_map.view.add_child(night_mini)
	night_map = NightVeil.new()
	night_map.name = "NightVeilMap"
	night_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_panel.add_child(night_map)
	_m3d_night_refresh()

func open_combo() -> void:
	if _battle_open():
		return
	_show_dialog(combo_dialog)
	combo_dialog.open_panel(sheet, view)

func _m3d_combat_event(key: String, p: Dictionary) -> bool:
	match key:
		UiKeys.E_CB_BOND_REQUEST:
			if _battle_open():
				return true
			_show_dialog(combo_dialog)
			combo_dialog.open_request(p, sheet, view)
			message_log.add_system("%s想和你建立默契（燈籠「默契」可以回覆）。" % str(p.get("from_name", "")))
			return true
		UiKeys.E_CB_BOND_CHANGED:
			if combo_dialog.visible:
				var s2 := sheet.duplicate()
				var c: Dictionary = (s2.get("combo", {}) as Dictionary).duplicate() if s2.get("combo") is Dictionary else {}
				for k in ["partner_name", "moqi", "peihe", "drain_day"]:
					if p.has(k):
						c[k] = p[k]
				s2["combo"] = c
				combo_dialog.apply_sheet(s2)
			return true
	return false

func _m3d_combat_sheet(s: Dictionary) -> void:
	lanterns.set_combo_visible(ComboDialog.era_on(s) and not s.is_empty())
	if combo_dialog != null:
		combo_dialog.apply_sheet(s)
	_m3d_night_refresh()

## 夜裡（sheet.clock.night）、沒有夜明珠、設定沒關 → 變暗
static func night_dim_on(s: Dictionary) -> bool:
	if UiSettings.get_value(UiKeys.SETTING_NIGHT_DIM, true) == false:
		return false
	var clk: Variant = s.get("clock", {})
	if not (clk is Dictionary) or not bool((clk as Dictionary).get("night", false)):
		return false
	return not has_light(s)

## 背包裡有 effects 含 LIGHT 的道具（夜明珠）
static func has_light(s: Dictionary) -> bool:
	for it in s.get("inventory", []):
		if not (it is Dictionary):
			continue
		for e in UiClient.row("items", str(it.get("id", ""))).get("effects", []):
			if e is Dictionary and str(e.get("type", "")) == UiKeys.ITEM_EFFECT_LIGHT:
				return true
	return false

func _m3d_night_refresh() -> void:
	if night_scene == null:
		return
	var on := night_dim_on(sheet)
	for v in [night_scene, night_mini, night_map]:
		v.set_on(on)

func night_dimmed() -> bool:
	return night_scene != null and night_scene.on

## 夜晚的深藍半透明層（不吃滑鼠）。fog_view 有給（小地圖）時，目前房間與相鄰房間以外再加深成霧
class NightVeil extends Control:
	const FOG := Color(0.02, 0.03, 0.10, 0.62)
	var on := false
	var fog_view: Control = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func set_on(v: bool) -> void:
		on = v
		visible = v
		queue_redraw()

	func _process(_d: float) -> void:
		if on and fog_view != null and is_visible_in_tree():   # 戰鬥中（主畫面藏起來）不重畫
			queue_redraw()

	## 小地圖亮著的範圍：目前房間與前後左右斜角相鄰、畫得出來的房間的方框聯集（本控制項座標）
	func lit_rect() -> Rect2:
		if fog_view == null or not ("model" in fog_view):
			return Rect2()
		var model: Dictionary = fog_view.get("model")
		var pos: Dictionary = model.get("pos", {}) if model is Dictionary else {}
		var cur := str(fog_view.call("focus_id"))
		if not pos.has(cur):
			return Rect2()
		var r: Rect2 = fog_view.call("screen_rect", cur)
		var pc: Vector2i = pos[cur]
		var lit_ids := { cur: true }
		for id in pos:
			var d: Vector2i = (pos[id] as Vector2i) - pc
			if id != cur and absi(d.x) <= 1 and absi(d.y) <= 1 and bool(fog_view.call("is_shown", id)):
				r = r.merge(fog_view.call("screen_rect", id))
				lit_ids[id] = true
		# M3d 審查：目前房間與亮著的相鄰房間的「往XXX」出區箭頭與字也要亮（原本落在霧裡，深藍字疊深藍底看不清）
		if fog_view.has_method("out_exit_screen_rects"):
			for er in fog_view.call("out_exit_screen_rects", lit_ids):
				r = r.merge(er as Rect2)
		return r.grow(4.0)

	func _draw() -> void:
		if not on:
			return
		var full := Rect2(Vector2.ZERO, size)
		draw_rect(full, UiKeys.NIGHT_DIM_COLOR)
		if fog_view == null:
			return
		var lit := lit_rect()
		if lit.size == Vector2.ZERO:
			return
		lit = lit.intersection(full)
		# 亮區以外四塊加深
		draw_rect(Rect2(0, 0, size.x, lit.position.y), FOG)
		draw_rect(Rect2(0, lit.end.y, size.x, size.y - lit.end.y), FOG)
		draw_rect(Rect2(0, lit.position.y, lit.position.x, lit.size.y), FOG)
		draw_rect(Rect2(lit.end.x, lit.position.y, size.x - lit.end.x, lit.size.y), FOG)

# ==== M3d WP-ARTS ====
func _m3d_arts_event(_key: String, _p: Dictionary) -> bool:
	return false

# ==== M3d WP-EVENTS ====
## M3D_PLAN §5.2、§5.3：tourney_state（ui）→ 比武報名視窗（開著就更新；報名員選單剛按「比武報名」也打開）；
## 擂臺點名叫到自己時跳一句醒目的提示。ev_jb_*、ev_duel_result 是一般文字事件（回 false 照常顯示）。
## 劫鏢視窗：m3d_events_open_rob(player) ／ m3d_events_open_rob_list()（M3D_PLAN 缺漏：玩家選單 UiSocial 沒有 WP-EVENTS 的鉤子，
## 由整合者在玩家選單加「劫鏢」一列：對方 tags 有「押鏢」時顯示，按下呼叫 m3d_events_open_rob(p)）。
var tourney_dialog: TourneyDialog = null
var jiebiao_confirm: JiebiaoConfirm = null

func _m3d_events_event(key: String, p: Dictionary) -> bool:
	match key:
		UiKeys.E_TOURNEY_STATE:
			var d := _m3d_events_tourney()
			d.apply_state(p)
			if TourneyDialog.pending_open and not d.visible:
				TourneyDialog.pending_open = false
				_show_dialog(d)
				d.visible = true
			return true
		UiKeys.E_EV_TOURNEY_CALL:
			if str(p.get("name", "")) == str(sheet.get("name", "")) and message_log != null:
				message_log.add_error("輪到你上擂臺了！到西夏比武場（擂臺或休息區）等候，三次點名不到判負。")
			return false
	return false

func _m3d_events_tourney() -> TourneyDialog:
	if tourney_dialog == null:
		tourney_dialog = TourneyDialog.new()
		tourney_dialog.name = "TourneyDialog"
		m3d_add_dialog(tourney_dialog)
	return tourney_dialog

func _m3d_events_rob() -> JiebiaoConfirm:
	if jiebiao_confirm == null:
		jiebiao_confirm = JiebiaoConfirm.new()
		jiebiao_confirm.name = "JiebiaoConfirm"
		m3d_add_dialog(jiebiao_confirm)
	return jiebiao_confirm

## 比武報名視窗（報名員選單、或指令）：npc_id 空＝只看不報名
func m3d_events_open_tourney(npc_id := "") -> void:
	if _battle_open():
		return
	var d := _m3d_events_tourney()
	_show_dialog(d)
	d.open_for(npc_id)

## 劫鏢確認（玩家選單「劫鏢」）
func m3d_events_open_rob(player: Dictionary) -> void:
	if _battle_open():
		return
	var d := _m3d_events_rob()
	_show_dialog(d)
	d.open_for(player, view)

## 同房押鏢的人清單
func m3d_events_open_rob_list() -> void:
	if _battle_open():
		return
	var d := _m3d_events_rob()
	_show_dialog(d)
	d.open_list(view)

# ==== M3d WP-ERRANDS ====
func _m3d_errands_event(_key: String, _p: Dictionary) -> bool:
	return false
