class_name BattleScreen
extends Control
## 戰鬥畫面（AUTHENTIC_UI_SPEC §12；M1_PLAN 3.12、GDD 11.3）：遇敵時直接切成戰鬥畫面，只蓋上半部（主畫面把它放在 HUD 以上），
## 底部 HUD 照常顯示（能量條即時更新、殺氣常亮）。
## - 戰場：等角 12×8（BattleIsoView），保留主人繪製的地區背景與角色立繪；移動綠格、攻擊範圍藍格、目標紅格、游標黃框、
##   逃跑格白色雙線菱形加「逃」字；
## - 戰報：不另設面板，和聊天共用左上浮層的位置（透明底、描邊字）；
## - 指令：右上兩列蜂巢圓盤（CommandBar），可以右鍵拖到任何位置，位置記在 settings.json 的 ui.battle_cmd_pos；
## - 時間棒清單（右側，原作沒有）：系統窗特殊開關「戰鬥時間棒清單」打開時才顯示（輔助功能，預設關）；
## - 結束：沒有結算畫面，獎勵印在戰報，羊皮紙小條「戰鬥結束」（下面一行勝負與獎勵），約 2.3 秒後自動返回（可關；
##   關掉時小條才有「返回」鈕），任意鍵立刻返回。
## 主畫面在 battle_opened 時建立本畫面（setup），battle_closed 時呼叫 show_result()，返回時發 finished。
## M2：PvP 的被叫戰／被強制方（my_side == 1）整個戰場左右鏡像（BattleViewModel），點格子送出前轉回主機座標；
## 中途加入（battle_unit_join）的新單位出現在戰場與時間棒清單。
## M3a（M3A_PLAN §7.1–7.5）：毒、醫、暗、陣、內、穴與「裝 → 用藥」。
## - 選目標：毒、暗、穴 → 射程內的敵格（紅框）；醫、用藥、傳力 → 自己或隊友格（綠框）；
##   陣 → 站位格（金框，缺人的格閃爍），按 Enter（或點自己的格）送出；範圍招式 → 滑鼠移到中心格時半透明預覽打擊格。
## - 小選單（cmd_menu）：毒術／醫術／陣法有多套時先選一套；「暗」先選暗器（數量、傷氣）；「內」四種運功（不可用的灰掉附原因）；
##   「裝」先選「換兵器／用藥」。
## - 快捷鍵 8 毒、9 醫、0 暗，Shift+1 陣、Shift+2 內、Shift+3 穴。
## - 波次（十八銅人）：輪到誰的牌子後面加「第 n／N 波」。
## M3d（M3D_PLAN §3.1–3.4；WP-COMBAT）：「閃」（Shift+4）直接送出；「輕」（Shift+5）小選單「飛身越敵」（綠格＝移動範圍 +1 的空格，
## 可以越過人）／「輕功脫身」；穿烙跑鞋時「逃」任何格子都能按；合體一擊（battle_combo）金色大字＋兩人之間的光帶。

signal finished
signal panel_requested(pid: String)

var vm: BattleViewModel
var gate: IntentGate
var grid_view: BattleIsoView
var gauge_panel: PanelContainer
var gauge_box: VBoxContainer
var turn_label: Label
var me_label: Label
var command_bar: CommandBar
var info_box: VBoxContainer
var log_text: RichTextLabel
var art_picker: ArtPicker
var equip_panel: PanelContainer
var equip_box: VBoxContainer
var result_panel: PanelContainer
var result_title: Label   # 「戰鬥結束」（AUTHENTIC_UI_SPEC §12.1 結束：羊皮紙小條只寫這四個字）
var result_label: Label   # 勝負一行（勝利／戰敗／脫離戰鬥…），小字放在標題下
var result_detail: RichTextLabel   # M3c WP-LOOT：物品名依稀有度上色（BBCode）；.text 仍含純文字內容
var treasure_label: Label          # M3c WP-LOOT：珍品以上時標題下的金字「得到寶物！」
var loot_glow_rarity := ""         # M3c WP-LOOT：最近一次光暈的稀有度（精品以上；測試用）
var return_button: Button
var hint_label: Label
var cancel_button: Button

const LOG_RECT := Rect2(8, 8, 520, 292)
const CMD_MARGIN := 12.0
const RIGHT_W := 300.0             # 時間棒清單寬
const GAUGE_NAME_W := 96.0
const GAUGE_BAR_W := 72.0
const AUTO_RETURN_S := 2.3   # 規格 §12.1：在場上停留約 1.5 秒 ＋「戰鬥結束」小條 0.8 秒
const BACKDROP := UiTheme.JY_VOID

var mode := ""                     # "" / MOVE / ATTACK / ART / POISON / MEDIC / HIDDEN / FORMATION / INNER（傳力）/ ACUPOINT / ITEM
var pending_art: Dictionary = {}   # { art, move, tenths, range, aoe }
var pending: Dictionary = {}       # M3a 指令選目標時要一起送出的參數（art、item_uid、mode…）
var cmd_menu: PanelContainer       # M3a 小選單（毒術／醫術／陣法／暗器／內功／裝）
var cmd_menu_title: Label
var cmd_menu_box: VBoxContainer
var _preview_at := Vector2i(-2, -2)
var sending := false
var log_lines := 0
## 戰報每一行（bb 字串）的副本：結果出來之後才到的戰鬥事件（最後一擊、「你打贏了這一仗」「你獲得…」）
## 要插在「戰鬥結束」那幾行前面，所以要能重排（M3a 審查：結果行跑到致命一擊前面、獎勵重複）
var _log_entries: Array = []
var _result_from := -1            # 結果那幾行在 _log_entries 的起點；-1 = 還沒結束
var return_at_ms := -1
var _anchor_ms := 0
var _gauge_rows: Dictionary = {}   # uid -> { bar, label }
var _built := false
var _was_my_turn := false
var last_state: Dictionary = {}    # M3d：setup 收到的戰鬥快照（3.9.3；WP-EVENTS 的擂臺倒數讀 duel_left_s）

func _ready() -> void:
	if not _built:
		_build()
	UiClient.connect_signal("events_received", _on_events)
	UiClient.connect_signal("region_changed", _on_region_changed)

func _exit_tree() -> void:
	UiClient.disconnect_signal("events_received", _on_events)
	UiClient.disconnect_signal("region_changed", _on_region_changed)

## 遇敵時 battle_opened 可能比地區更新早到（例如從城鎮走進野外就遇敵）：背景跟著目前地區走
## 戰敗重生時的房間更新（勝負已分）不換背景：戰敗小條還在時背景不能先變成城裡
func _on_region_changed(view: Dictionary) -> void:
	if vm != null and (vm.ended or str(vm.me().get("state", "")) in ["DEAD", "FLED"]):
		return
	var rid := str(view.get("region", ""))
	if grid_view != null and rid != "" and rid != grid_view.region_id:
		grid_view.set_region(rid)

func _build() -> void:
	_built = true
	if get_parent() == null or not (get_parent() is Control):
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var dim := ColorRect.new()
	dim.color = BACKDROP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	grid_view = BattleIsoView.new()
	grid_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid_view.cell_clicked.connect(_on_cell)
	add_child(grid_view)

	# 戰報：左上浮層（描邊字）。底下墊一層由左往右淡出的暗紗：主人畫的沙漠／草地背景很亮，
	# 黃色系統字與戰鬥字只靠描邊看不清楚（審查 round 3）；暗紗不吃滑鼠
	var veil := TextureRect.new()
	# 以左上角為圓心往外淡出（右緣、下緣都沒有硬邊）；比戰報區大一圈，最新幾行（下方）仍在暗處
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 0.72])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.42), Color(0, 0, 0, 0.0)])
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
	veil.position = Vector2.ZERO
	veil.size = (LOG_RECT.position + LOG_RECT.size) * Vector2(1.45, 1.5)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	log_text = RichTextLabel.new()
	log_text.bbcode_enabled = true
	log_text.scroll_following = true
	log_text.position = LOG_RECT.position
	log_text.size = LOG_RECT.size
	log_text.add_theme_font_size_override("normal_font_size", 15)
	log_text.add_theme_constant_override("outline_size", 4)
	log_text.add_theme_color_override("font_outline_color", UiTheme.OVERLAY_OUTLINE)
	# 戰報浮層蓋在戰場左上（玩家開場就站在左上角）：文字區不能吃掉點格子的滑鼠（捲軸本身仍可拖）
	# 捲軸：內建的在浮層右緣，戰報一長就是一根貫穿戰場的長條（審查）；改成左緣 6 px 細捲軸（§9.1），只當位置指示、不吃滑鼠
	log_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_text)
	UiBuild.left_scrollbar(log_text, self, 1.0, false)

	# 時間棒清單（選用）
	gauge_panel = UiBuild.framed(self, UiFrame.Kind.INK)
	gauge_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	gauge_panel.offset_left = -RIGHT_W - 8.0
	gauge_panel.offset_right = -8
	gauge_panel.offset_top = -120
	gauge_panel.offset_bottom = 120
	var gv := UiBuild.vbox(gauge_panel, 4)
	UiBuild.accent(UiBuild.label(gv, "時間棒", 15))
	gauge_box = UiBuild.vbox(gv, 3)

	# 指令圓盤＋提示
	command_bar = CommandBar.new()
	add_child(command_bar)
	command_bar.command_chosen.connect(_on_command)
	command_bar.panel_requested.connect(func(pid: String): panel_requested.emit(pid))
	command_bar.moved.connect(func(p: Vector2): UiSettings.set_value("ui.battle_cmd_pos", [int(p.x), int(p.y)]))
	info_box = UiBuild.vbox(self, 4)
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_label = UiBuild.plate(info_box, "", 16, 220)
	turn_label.add_theme_color_override("font_color", UiTheme.JY_LABEL)
	turn_label.clip_text = false
	# 「兵器：木刀」與提示：淺字直接畫在亮沙地上看不清（審查），墊一塊半透明深色底牌
	me_label = UiBuild.label(info_box, "", 14)
	me_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_dark_plate(me_label)
	hint_label = UiBuild.label(info_box, "", 14, true)
	hint_label.custom_minimum_size = Vector2(300, 0)
	_dark_plate(hint_label)
	cancel_button = UiBuild.button(info_box, "取消選擇", cancel_mode)
	cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cancel_button.disabled = true

	# 浮動層：招式選擇、武器清單、結束小條
	var layer := CenterContainer.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	art_picker = ArtPicker.new()
	art_picker.visible = false
	art_picker.picked.connect(_on_art_picked)
	art_picker.cancelled.connect(cancel_mode)
	layer.add_child(art_picker)
	equip_panel = UiBuild.framed(layer, UiFrame.Kind.JADE)
	equip_panel.visible = false
	var ev := UiBuild.vbox(equip_panel, 6)
	UiBuild.title(ev, "換兵器")
	equip_box = UiBuild.vbox(ev, 4)
	UiBuild.button(ev, "取消", func(): equip_panel.visible = false)
	# 小選單不放在置中層：開在指令圓盤旁邊、避開自己的人物（M3a 審查 C9：以前蓋住自己的人物與氣血）
	var menu_layer := Control.new()
	menu_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_layer)
	cmd_menu = UiBuild.framed(menu_layer, UiFrame.Kind.JADE)
	cmd_menu.name = "CmdMenu"
	cmd_menu.visible = false
	cmd_menu.custom_minimum_size = Vector2(300, 0)
	var mv := UiBuild.vbox(cmd_menu, 6)
	cmd_menu_title = UiBuild.title(mv, "")
	cmd_menu_box = UiBuild.vbox(mv, 4)
	UiBuild.button(mv, "取消", cancel_mode)
	# 戰鬥結束：羊皮紙小條放在下緣、戰場以外的空地（_place_result：哪個角落蓋到的格子最少，逃跑格與人物最不能蓋）
	var rlayer := Control.new()
	rlayer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rlayer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rlayer)
	result_panel = UiBuild.framed(rlayer, UiFrame.Kind.SCROLL_SMALL)
	result_panel.theme = UiTheme.paper()
	result_panel.visible = false
	result_panel.custom_minimum_size = Vector2(360, 0)
	var rv := UiBuild.vbox(result_panel, 6)
	result_title = UiBuild.label(rv, "戰鬥結束", 30)
	result_title.add_theme_font_override("font", UiTheme.brush_font(0.4))
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	treasure_label = UiBuild.label(rv, "得到寶物！", 18)
	treasure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	treasure_label.add_theme_color_override("font_color", LootUi.rarity_color("DIVINE"))
	treasure_label.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.0, 0.9))
	treasure_label.add_theme_constant_override("outline_size", 3)
	treasure_label.visible = false
	result_label = UiBuild.label(rv, "", 20)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_detail = RichTextLabel.new()
	result_detail.bbcode_enabled = true
	result_detail.fit_content = true
	result_detail.scroll_active = false
	result_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_detail.add_theme_font_size_override("normal_font_size", RESULT_FONT_SIZE)
	result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(result_detail)
	# 自動換行的字要有固定寬度，否則面板量最小高度時以 0 寬計算，小條會變成一整條直的長面板
	result_detail.custom_minimum_size = Vector2(336, 0)
	return_button = UiBuild.button(rv, "返回", func(): finished.emit())
	return_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	gate = IntentGate.new()
	add_child(gate)
	apply_options()
	resized.connect(_place_commands)
	resized.connect(func():
		if result_panel.visible:
			_place_result())
	_place_commands()

static func _dark_plate(l: Label) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.045, 0.035, 0.72)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	l.add_theme_stylebox_override("normal", sb)
	l.add_theme_color_override("font_color", Color("f4ead2"))
	l.add_theme_constant_override("outline_size", 2)
	l.add_theme_color_override("font_outline_color", UiTheme.OVERLAY_OUTLINE)

## 系統窗特殊開關：時間棒清單、損血顯示、格線
func apply_options() -> void:
	gauge_panel.visible = UiSettings.get_bool("ui.atb_list")
	grid_view.show_grid = UiSettings.get_bool("ui.grid_lines")
	grid_view.damage_text = UiSettings.get_bool("ui.damage_text")

## 指令圓盤預設在右上；拖過就用記住的位置（夾在畫面內）
func _place_commands() -> void:
	if command_bar == null:
		return
	var def := Vector2(size.x - command_bar.size.x - CMD_MARGIN, CMD_MARGIN)
	var p: Variant = UiSettings.get_value("ui.battle_cmd_pos", null)
	var pos := def
	if p is Array and (p as Array).size() >= 2:
		pos = Vector2(float(p[0]), float(p[1]))
	command_bar.position = CommandBar.clamp_pos(pos, command_bar.size, size)

## state = 3.9.3
func setup(state: Dictionary) -> void:
	if not _built:
		_build()
	vm = BattleViewModel.from_state(state)
	if not state.has("later_battle_cmds"):
		vm.later_cmds = BattleScreen.later_cmds_enabled()
	last_state = state   # M3d：快照（WP-EVENTS 擂臺倒數用）
	_anchor_ms = Time.get_ticks_msec()
	grid_view.set_region(str(UiClient.region_view().get("region", "")))
	grid_view.set_vm(vm)
	_build_gauges()
	_refresh()

## 伺服器規則 later_battle_cmds（M3A_PLAN §6.12 world_info.later_battle_cmds；舊主機看展開後的 rule_profile；都沒有 → 開）
static func later_cmds_enabled() -> bool:
	var wi := UiClient.world_info()
	if wi.has("later_battle_cmds"):
		return wi["later_battle_cmds"] != false
	var rp: Variant = wi.get("rule_profile", {})
	if rp is Dictionary and (rp as Dictionary).has("later_battle_cmds"):
		return rp["later_battle_cmds"] != false
	return true

func _build_gauges() -> void:
	UiBuild.clear(gauge_box)
	_gauge_rows.clear()
	for uid in vm.order:
		var u: Dictionary = vm.units[uid]
		var row := UiBuild.hbox(gauge_box, 6)
		var name_l := UiBuild.label(row, (UnitSprite.ALLY_TAG if UnitSprite.is_rogue_ally(u) else "") + str(u.get("name", "?")), 14)   # ROGUE WP-ALLY
		name_l.custom_minimum_size = Vector2(GAUGE_NAME_W, 0)
		name_l.add_theme_color_override("font_color", UiTheme.NAME_ALLY if int(u["side"]) == vm.my_side() else UiTheme.NAME_ENEMY)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(GAUGE_BAR_W, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UiTheme.vital_bar(bar, UiTheme.TIME_BAR, UiTheme.TIME_BAR.lightened(0.3))
		row.add_child(bar)
		var info := UiBuild.label(row, "", 13)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.clip_text = true
		info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_gauge_rows[uid] = { "bar": bar, "label": info, "name": name_l }

func now_tick() -> float:
	if vm == null:
		return 0.0
	return vm.anchor_tick + float(Time.get_ticks_msec() - _anchor_ms) / 1000.0 * UiKeys.TICKS_PER_SEC

func _process(_delta: float) -> void:
	if command_bar != null:
		info_box.position = command_bar.position + Vector2(0, command_bar.size.y + 6.0)
	if return_at_ms >= 0 and Time.get_ticks_msec() >= return_at_ms:
		return_at_ms = -1
		finished.emit()
	if log_text != null:
		log_text.visible = not log_covered()
	if vm == null:
		return
	grid_view.now_tick = now_tick()
	grid_view.queue_redraw()
	_refresh()

func _refresh() -> void:
	var t := now_tick()
	if gauge_panel.visible:
		for uid in _gauge_rows:
			var r: Dictionary = _gauge_rows[uid]
			var u: Dictionary = vm.unit(uid)
			UiBuild.set_bar(r["bar"], vm.gauge_at(uid, t), UiKeys.GAUGE_FULL)
			var st := str(u.get("state", ""))
			var extra := ""
			if st in ["DEAD", "FLED"]:
				extra = UiKeys.UNIT_STATE_LABELS.get(st, st)
			elif vm.afk.has(uid):
				extra = "神遊中"
			elif vm.await_units.has(uid):
				extra = "等待下令"
			(r["label"] as Label).text = "氣 %d/%d %s" % [UiBuild.num(u.get("qi", 0)), UiBuild.num(u.get("qi_max", 0)), extra]
	var m := vm.me()
	var wname := str((m.get("weapon", {}) as Dictionary).get("name", ""))
	me_label.text = "兵器：%s" % (wname if wname != "" else "空手")
	var mine := vm.is_my_turn(t)
	var wave_tag := "　第 %d／%d 波" % [vm.wave, vm.wave_total] if vm.wave > 0 and vm.wave_total > 1 else ""
	if vm.ended:
		turn_label.text = "戰鬥結束"
	elif mine:
		var left := vm.seconds_left(t)
		turn_label.text = "輪到你出手！" + ("（剩 %d 秒）" % int(ceil(left)) if left >= 0.0 else "")
	elif not vm.await_units.is_empty():
		var left2 := vm.seconds_left(t)
		turn_label.text = "等待其他人下令……" + ("（%d 秒）" % int(ceil(left2)) if left2 >= 0.0 else "")
	else:
		turn_label.text = "蓄勢中……" if vm.wait_mode else "蓄勢中（半即時）……"
	if wave_tag != "" and not vm.ended:
		turn_label.text += wave_tag
	# 輪到我：頭上閃黃色菱形（BattleIsoView），戰報印一行
	if mine and not _was_my_turn and not vm.ended:
		grid_view.flash_turn()
		_log_plain("輪到你出手了。", TextRenderer.CHANNEL_COLORS["BATTLE"])
	_was_my_turn = mine
	command_bar.refresh(vm, t)
	if sending or vm.ended or result_panel.visible:
		for cmd in command_bar.buttons:
			(command_bar.buttons[cmd] as Button).disabled = true
	if (mode != "" or cmd_menu.visible) and not vm.is_my_turn(t):
		cancel_mode()
	# 戰鬥結束後：「取消選擇」收起來、圓盤整組變暗（審查：結束了還像可以按）
	var over := vm.ended or result_panel.visible
	# 「取消選擇」只在真的有東西可取消（選了移／攻／武、開著招式或兵器清單）時出現（審查 round 4：蓄勢中也掛著）
	var selecting := mode != "" or art_picker.visible or equip_panel.visible or cmd_menu.visible
	cancel_button.visible = not over and selecting
	cancel_button.disabled = over or not selecting
	command_bar.modulate = Color(1, 1, 1, 0.45 if over else 1.0)
	for g in command_bar.discs:
		if over:
			(command_bar.discs[g] as Button).disabled = true
	if mode == "" and not art_picker.visible and not cmd_menu.visible:
		var idle := UiKeys.BATTLE_IDLE_HINT if vm.is_my_turn(t) and not vm.ended else ""
		if hint_label.text != idle:
			hint_label.text = idle
	hint_label.visible = hint_label.text != ""
	_update_preview()
	if mode == UiKeys.CMD_FORMATION:
		_refresh_stations()
	if has_method("_m3d_events_duel_hud"): call("_m3d_events_duel_hud", last_state)   # M3d WP-EVENTS（M3D_PLAN §9.2）

## 快捷鍵 1–7 對應 移 攻 武 防 休 裝 逃（只在可按時有效；帶 Ctrl／Alt／Shift／Meta 的不算，
## 例如 Ctrl+1 是主畫面的燈籠快捷鍵，不能變成「移」）。結果小條出來後任意鍵立刻返回。
func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or vm == null:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if result_panel.visible:
		if not (k.keycode in [KEY_CTRL, KEY_ALT, KEY_SHIFT, KEY_META]):
			return_at_ms = -1
			finished.emit()
			get_viewport().set_input_as_handled()
		return
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return
	# 陣：選好站位後按 Enter 送出
	if mode == UiKeys.CMD_FORMATION and k.keycode in [KEY_ENTER, KEY_KP_ENTER] and not k.shift_pressed:
		submit_formation()
		get_viewport().set_input_as_handled()
		return
	var cmd := BattleScreen.hotkey_cmd(k)
	if cmd != "" and command_bar.is_enabled(cmd):
		_on_command(cmd)
		get_viewport().set_input_as_handled()

## 數字鍵 → 指令：1–7 移攻武防休裝逃、8 毒、9 醫、0 暗；Shift+1 陣、Shift+2 內、Shift+3 穴（M3A_PLAN §7.1）。
## Shift+數字在部分鍵盤配置下 keycode 會是符號（! @ #），所以也看實體鍵
static func hotkey_cmd(k: InputEventKey) -> String:
	if k.shift_pressed:
		for code in [k.keycode, k.physical_keycode]:
			if UiKeys.M3A_SHIFT_HOTKEYS.has(code):
				return UiKeys.M3A_SHIFT_HOTKEYS[code]
			if UiKeys.M3D_SHIFT_HOTKEYS.has(code):
				return UiKeys.M3D_SHIFT_HOTKEYS[code]   # M3d：Shift+4 閃、Shift+5 輕
		var sym := { KEY_EXCLAM: KEY_1, KEY_AT: KEY_2, KEY_NUMBERSIGN: KEY_3 }
		if sym.has(k.keycode):
			return UiKeys.M3A_SHIFT_HOTKEYS[sym[k.keycode]]
		var sym4 := { KEY_DOLLAR: KEY_4, KEY_PERCENT: KEY_5 }
		if sym4.has(k.keycode):
			return UiKeys.M3D_SHIFT_HOTKEYS[sym4[k.keycode]]
		return ""
	if UiKeys.M3A_HOTKEYS.has(k.keycode):
		return UiKeys.M3A_HOTKEYS[k.keycode]
	var i := int(k.keycode) - int(KEY_1)
	if i < 0 or i >= UiKeys.BATTLE_CMDS.size():
		return ""
	return UiKeys.BATTLE_CMDS[i]

# ---------- 指令 ----------
func _on_command(cmd: String) -> void:
	if vm == null or not vm.is_my_turn(now_tick()):
		return
	cancel_mode()
	menu_anchor_cmd = cmd   # M3d 審查第三輪：小選單開在按下的那顆指令鈕附近
	match cmd:
		UiKeys.CMD_MOVE:
			mode = cmd
			grid_view.set_highlight(vm.move_targets(), UiTheme.HIGHLIGHT_MOVE)
			hint_label.text = "點選綠色格子移動。"
		UiKeys.CMD_ATTACK:
			mode = cmd
			grid_view.set_range(BattleIsoView.cells_within(vm.me().get("pos", Vector2i.ZERO), 1, grid_view.grid_w(), grid_view.grid_h()))
			grid_view.set_highlight(vm.enemy_cells_within(1), UiTheme.HIGHLIGHT_TARGET)
			hint_label.text = "藍色是攻擊範圍；點選紅色格上的敵人。"
		UiKeys.CMD_ART:
			var m := vm.me()
			art_picker.open(vm.my_arts(), UiBuild.num(m.get("neili", 0)), UiBuild.num(m.get("jing", 0)))
		UiKeys.CMD_DEFEND, UiKeys.CMD_REST, UiKeys.CMD_FLEE:
			submit({ "cmd": cmd })
		UiKeys.CMD_EQUIP:
			_open_equip_menu()
		UiKeys.CMD_POISON:
			_choose_art(UiKeys.CMD_POISON, "選擇毒術", _target_poison)
		UiKeys.CMD_MEDIC:
			var marts := vm.cmd_arts(UiKeys.CMD_MEDIC)
			if marts.size() <= 1:
				_target_medic(marts[0] if not marts.is_empty() else {})
			else:
				_choose_art(UiKeys.CMD_MEDIC, "選擇醫術", _target_medic)
		UiKeys.CMD_HIDDEN:
			_open_hidden_menu()
		UiKeys.CMD_FORMATION:
			_choose_art(UiKeys.CMD_FORMATION, "選擇陣法", _target_formation)
		UiKeys.CMD_INNER:
			_open_inner_menu()
		UiKeys.CMD_ACUPOINT:
			var aarts := vm.cmd_arts(UiKeys.CMD_ACUPOINT)
			_target_acupoint(aarts[0] if not aarts.is_empty() else {})
		UiKeys.CMD_DODGE:
			submit({ "cmd": UiKeys.CMD_DODGE })
		UiKeys.CMD_QING:
			_open_qing_menu()

func _on_art_picked(art_id: String, move_id: String, tenths: int, rng: int) -> void:
	var shape := BattleScreen.move_aoe(vm.find_art(art_id), art_id, move_id)
	pending_art = { "art": art_id, "move": move_id, "power_tenths": tenths, "range": maxi(1, rng), "aoe": shape }
	mode = UiKeys.CMD_ART
	grid_view.set_range(BattleIsoView.cells_within(vm.me().get("pos", Vector2i.ZERO), pending_art["range"], grid_view.grid_w(), grid_view.grid_h()))
	if shape == "SINGLE":
		grid_view.set_highlight(vm.enemy_cells_within(pending_art["range"]), UiTheme.HIGHLIGHT_TARGET)
		hint_label.text = "藍色是招式射程；點選紅色格上的敵人。"
	else:
		grid_view.set_highlight(vm.aoe_centers(shape, pending_art["range"]), UiTheme.HIGHLIGHT_TARGET)
		hint_label.text = "%s：滑鼠移到紅色格上預覽打到的格子，點一下出招。" % UiKeys.AOE_LABELS.get(shape, shape)

## 招式的範圍形狀：快照的招式有 aoe 就用，否則查本地 martial_arts；都沒有就是單體
static func move_aoe(art: Dictionary, art_id: String, move_id: String) -> String:
	for m in art.get("moves", []):
		if m is Dictionary and str(m.get("id", "")) == move_id and m.has("aoe"):
			return str(m["aoe"])
	for m in UiClient.row("martial_arts", art_id).get("moves", []):
		if m is Dictionary and str(m.get("id", "")) == move_id:
			return str(m.get("aoe", "SINGLE"))
	return "SINGLE"

## 範圍招式：滑鼠停在可點的中心格上 → 半透明預覽打擊格
func _update_preview() -> void:
	if grid_view == null:
		return
	var c := grid_view.hover_cell
	var shape := str(pending_art.get("aoe", "SINGLE"))
	var want := mode == UiKeys.CMD_ART and shape != "SINGLE" and grid_view.highlight.has(c)
	if not want:
		if not grid_view.preview_cells.is_empty():
			grid_view.set_preview([])
		_preview_at = Vector2i(-2, -2)
		return
	if c == _preview_at:
		return
	_preview_at = c
	grid_view.set_preview(BattleViewModel.aoe_cells(shape, vm.me().get("pos", Vector2i.ZERO), c,
		int(pending_art.get("range", 1)), vm.w, vm.h))

## 指令小選單（運功、醫術…）、武功選單、換裝面板開著而且壓到戰報：戰報先藏起來，
## 不然戰報字會從選單框邊露出一截（「氣。」；M3a UI 審查 #6）
func log_covered() -> bool:
	if log_text == null:
		return false
	var lr := log_text.get_global_rect()
	for p in [cmd_menu, art_picker, equip_panel]:
		if p is Control and (p as Control).is_visible_in_tree() and (p as Control).get_global_rect().intersects(lr):
			return true
	return false

# ---------- M3a 指令 ----------
## 小選單：entries = [{ text, ok, tip, cb }]
func _open_menu(title: String, entries: Array) -> void:
	cmd_menu_title.text = title
	UiBuild.clear(cmd_menu_box)
	for en in entries:
		var b := UiBuild.button(cmd_menu_box, str(en.get("text", "")))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not bool(en.get("ok", true))
		b.tooltip_text = str(en.get("tip", ""))
		var cb: Callable = en.get("cb", Callable())
		b.pressed.connect(func():
			cmd_menu.visible = false
			if cb.is_valid():
				cb.call())
	cmd_menu.visible = true
	cmd_menu.reset_size()
	_place_cmd_menu()

const MENU_MARGIN := 8.0
## 小選單蓋到戰鬥訊息框的扣分（比蓋到格子重、比蓋到自己輕）；離指令鈕每 1 px 的扣分（同分時挑近的）
const MENU_LOG_PENALTY := 300.0
const MENU_DIST_PENALTY := 0.02
## 最後按下的指令（小選單靠著它的按鈕放；沒有＝只看圓盤）
var menu_anchor_cmd := ""

## 指令鈕在本畫面座標的矩形（找不到 → 空 Rect2）
func cmd_button_rect(cmd: String) -> Rect2:
	if command_bar == null or cmd == "" or not command_bar.buttons.has(cmd):
		return Rect2()
	var b := command_bar.buttons[cmd] as Control
	if b == null or not b.is_visible_in_tree():
		return Rect2()
	return Rect2(b.global_position - global_position, b.size)

## 小選單的位置：圓盤左邊、圓盤下方（提示列之下）、圓盤右邊、左上角、左下角裡，蓋到自己格子最少（其次蓋到最少格）的那個
func _place_cmd_menu() -> void:
	if cmd_menu == null or command_bar == null:
		return
	var sz := cmd_menu.get_combined_minimum_size().max(cmd_menu.size)
	cmd_menu.size = sz
	var bar := Rect2(command_bar.position, command_bar.size)
	var below := info_box.position.y + info_box.size.y + MENU_MARGIN if info_box != null else bar.end.y + MENU_MARGIN
	var cands := [Vector2(bar.position.x - sz.x - MENU_MARGIN, bar.position.y), Vector2(bar.end.x - sz.x, below),
		Vector2(bar.end.x + MENU_MARGIN, bar.position.y), Vector2(MENU_MARGIN, MENU_MARGIN),
		Vector2(MENU_MARGIN, size.y - sz.y - MENU_MARGIN)]
	# M3d 審查第三輪：按下的指令鈕旁邊（左邊同高、正下方靠右對齊）也是候選；蓋到戰鬥訊息框扣分；同分挑離按鈕近的
	var anchor := cmd_button_rect(menu_anchor_cmd)
	var anchor_c := (anchor.get_center() if anchor.has_area() else bar.get_center())
	if anchor.has_area():
		cands.push_front(Vector2(bar.position.x - sz.x - MENU_MARGIN, anchor.position.y))
		cands.push_front(Vector2(anchor.end.x - sz.x, maxf(bar.end.y, below) if below > bar.end.y else bar.end.y + MENU_MARGIN))
	var log_r := Rect2()
	if log_text != null and log_text.is_visible_in_tree():
		log_r = Rect2(log_text.global_position - global_position, log_text.size)
	var best := Vector2(MENU_MARGIN, MENU_MARGIN)
	var best_score := INF
	for c0 in cands:
		var c := Vector2(clampf(c0.x, 0.0, maxf(0.0, size.x - sz.x)), clampf(c0.y, 0.0, maxf(0.0, size.y - sz.y)))
		var r := Rect2(c, sz)
		var sc := result_cover_score(r) + (1000.0 if covers_my_unit(r) else 0.0) + (500.0 if r.intersects(bar) else 0.0)
		if log_r.has_area() and r.intersects(log_r):
			sc += MENU_LOG_PENALTY
		sc += r.get_center().distance_to(anchor_c) * MENU_DIST_PENALTY
		if sc < best_score - 0.01:
			best_score = sc
			best = c
	cmd_menu.position = best

## 這個矩形有沒有蓋到自己的人物（格子中心往上一個人身高，含名牌與氣血）
func covers_my_unit(r: Rect2) -> bool:
	if grid_view == null or vm == null or vm.me().is_empty():
		return false
	var c: Vector2 = grid_view.position + grid_view.cell_center(_my_pos())
	return r.grow(4.0).intersects(Rect2(c - Vector2(40, 110), Vector2(80, 130)))

func menu_texts() -> Array:
	var out: Array = []
	for b in cmd_menu_box.get_children():
		if b is Button:
			out.append((b as Button).text)
	return out

## 某一類 cmd_arts 只有一套就直接用，多套就先選
func _choose_art(cat: String, title: String, then: Callable) -> void:
	var arts := vm.cmd_arts(cat)
	if arts.is_empty():
		return
	if arts.size() == 1:
		then.call(arts[0])
		return
	var entries: Array = []
	for a in arts:
		entries.append({ "text": "%s（%d 級）　射程 %d" % [str(a.get("name", "")), int(a.get("level", 0)), int(a.get("range", 1))],
			"cb": then.bind(a) })
	_open_menu(title, entries)

func _my_pos() -> Vector2i:
	return vm.me().get("pos", Vector2i.ZERO)

## 進入選敵格模式（毒、暗、穴）：藍色射程＋紅框敵人
func _target_enemy(cmd: String, rng: int, args: Dictionary, hint: String) -> void:
	mode = cmd
	pending = args
	pending["range"] = maxi(1, rng)
	grid_view.set_range(BattleIsoView.cells_within(_my_pos(), pending["range"], grid_view.grid_w(), grid_view.grid_h()))
	grid_view.set_highlight(vm.enemy_cells_within(pending["range"]), UiTheme.HIGHLIGHT_TARGET)
	hint_label.text = hint

## 進入選自己或隊友模式（醫、用藥、傳力）：綠框
func _target_ally(cmd: String, rng: int, include_self: bool, args: Dictionary, hint: String) -> void:
	mode = cmd
	pending = args
	pending["range"] = maxi(1, rng)
	grid_view.set_range([])
	grid_view.set_highlight(vm.ally_cells_within(pending["range"], include_self), UiTheme.HIGHLIGHT_ALLY)
	hint_label.text = hint

func _target_poison(art: Dictionary) -> void:
	_target_enemy(UiKeys.CMD_POISON, int(art.get("range", 1)), { "art": str(art.get("id", "")) },
		"%s：點選紅色格上的敵人下毒。" % str(art.get("name", "毒")))

func _target_medic(art: Dictionary) -> void:
	var args := {}
	if not art.is_empty():
		args["art"] = str(art.get("id", ""))
	var rng := maxi(1, int(art.get("range", 1)))
	# 只標氣沒滿（或中毒、流血）的人；大家都好好的就不進選格模式（滿血療傷只會白白浪費一回合）
	if vm.ally_cells_within(rng, true, true).is_empty():
		cancel_mode()
		hint_label.text = "身旁的人氣血都滿，不必療傷。"
		return
	mode = UiKeys.CMD_MEDIC
	pending = args
	pending["range"] = rng
	grid_view.set_range([])
	grid_view.set_highlight(vm.ally_cells_within(rng, true, true), UiTheme.HIGHLIGHT_ALLY)
	hint_label.text = "點選綠色格（頭上有綠色箭頭）：替自己或隊友療傷。"

func _target_acupoint(art: Dictionary) -> void:
	var args := {}
	if not art.is_empty():
		args["art"] = str(art.get("id", ""))
	_target_enemy(UiKeys.CMD_ACUPOINT, maxi(1, int(art.get("range", 1))) if not art.is_empty() else 1, args,
		"點選紅色格上的敵人點穴。")

## 暗：先選暗器（數量、傷氣），再選敵人
func _open_hidden_menu() -> void:
	var entries: Array = []
	for it in vm.hidden_items():
		entries.append({ "text": "%s ×%d　傷氣 %d" % [str(it.get("name", "")), int(it.get("n", 0)), int(it.get("dmg", 0))],
			"cb": _target_hidden.bind(it) })
	if entries.is_empty():
		return
	_open_menu("選擇暗器", entries)

func _target_hidden(it: Dictionary) -> void:
	var args := { "item_uid": str(it.get("uid", "")) }
	var harts := vm.cmd_arts(UiKeys.CMD_HIDDEN)
	var bonus := 0
	if not harts.is_empty():
		args["art"] = str(harts[0].get("id", ""))
		var hrow: Variant = UiClient.row("martial_arts", str(harts[0].get("id", ""))).get("hidden", {})
		bonus = int((hrow as Dictionary).get("range_bonus", 0)) if hrow is Dictionary else 0
	var rng := vm.hidden_range(BattleScreen.my_skill_level("basic_hidden"), bonus)
	_target_enemy(UiKeys.CMD_HIDDEN, rng, args, "%s：點選紅色格上的敵人（射程 %d）。" % [str(it.get("name", "")), rng])

## 角色表裡某項武學的等級（暗器射程用）
static func my_skill_level(skill_id: String) -> int:
	for s in UiClient.sheet().get("skills", []):
		if s is Dictionary and str(s.get("id", "")) == skill_id:
			return UiBuild.num(s.get("level", 0))
	return 0

## 陣：顯示站位格（金框，缺人的格閃爍）；Enter 或點自己的格送出
func _target_formation(art: Dictionary) -> void:
	mode = UiKeys.CMD_FORMATION
	pending = { "art": str(art.get("id", "")), "stations": vm.formation_stations(str(art.get("id", ""))) }
	grid_view.set_range([])
	grid_view.set_highlight([_my_pos()], UiTheme.HIGHLIGHT_STATION)
	_refresh_stations()

func _refresh_stations() -> void:
	var cells := vm.station_cells(pending.get("stations", []))
	var missing := vm.station_missing(cells)
	grid_view.set_stations(cells, missing)
	var t := "%s：金框是站位，缺人的格會閃。按 Enter（或點自己的格）結陣。" % UiClient.name_of("martial_arts", str(pending.get("art", "")), "陣法")
	if not missing.is_empty():
		t += "（還缺 %d 人）" % missing.size()
	if hint_label.text != t:
		hint_label.text = t

func submit_formation() -> void:
	if mode != UiKeys.CMD_FORMATION:
		return
	submit({ "cmd": UiKeys.CMD_FORMATION, "art": str(pending.get("art", "")) })

## 內：四種運功；不可用的灰掉並附原因
func _open_inner_menu() -> void:
	var entries: Array = []
	for m in UiKeys.INNER_MODES:
		var why := inner_block(m)
		var text: String = UiKeys.INNER_MODE_LABELS[m]
		if why != "":
			text += "（%s）" % why
		var cb := _inner_chosen.bind(m)
		entries.append({ "text": text, "ok": why == "", "tip": why, "cb": cb })
	_open_menu("運功", entries)

## 這種運功現在不能用的原因（"" = 可以）
func inner_block(m: String) -> String:
	match m:
		"HEAL":
			var me_u := vm.me()
			if not me_u.is_empty() and int(me_u.get("qi", 0)) >= int(me_u.get("qi_max", 0)):
				return "氣血已滿"
		"EXPEL":
			if not vm.has_status(vm.my_uid, "poison"):
				return "沒有中毒"
		"UNSEAL":
			if not vm.has_status(vm.my_uid, "acupoint"):
				return "沒有被封穴"
		"TRANSFER":
			if vm.ally_cells_within(1, false).is_empty():
				return "身旁沒有隊友"
	if not vm.inner_modes().has(m):
		return "目前不能用"
	return ""

func _inner_chosen(m: String) -> void:
	if m == "TRANSFER":
		_target_ally(UiKeys.CMD_INNER, 1, false, { "mode": m }, "點選綠色格上的隊友傳送內力。")
		return
	submit({ "cmd": UiKeys.CMD_INNER, "mode": m })

## ---------- M3d：輕（M3D_PLAN §3.2） ----------
## 輕：飛身越敵／輕功脫身；不可用的灰掉附原因
func _open_qing_menu() -> void:
	var entries: Array = []
	for m in UiKeys.QING_MODES:
		var why := qing_block(m)
		var text: String = UiKeys.QING_MODE_LABELS[m]
		if why != "":
			text += "（%s）" % why
		else:
			# M3d 審查第三輪：可用時也寫出耗多少內力（飛身越敵 10 + 2 × 移動範圍、輕功脫身 30）
			text += "（耗內力 %d）" % qing_cost(m)
		entries.append({ "text": text, "ok": why == "", "tip": why if why != "" else str(UiKeys.QING_MODE_TIPS.get(m, "")),
			"cb": _qing_chosen.bind(m) })
	_open_menu("輕功", entries)

## 這種輕功要耗的內力（JUMP：10 + 2 × 移動範圍（快照 move_range，同 BattleRules.qing_jump_cost）；ESCAPE：30）
func qing_cost(m: String) -> int:
	if m == "ESCAPE":
		return UiKeys.QING_ESCAPE_COST
	return BattleRules.QING_JUMP_BASE + BattleRules.QING_JUMP_PER_RANGE * vm.move_range()

## 這種輕功現在不能用的原因（"" = 可以）
func qing_block(m: String) -> String:
	if not vm.later_cmds:
		return UiKeys.LATER_CMDS_TIP
	var blocked := vm.status_blocks(UiKeys.CMD_MOVE if m == "JUMP" else UiKeys.CMD_FLEE)
	if blocked != "":
		return "%s中" % blocked
	if m == "JUMP" and vm.jump_targets().is_empty():
		return "無處落腳"
	if not vm.qing_modes().has(m):
		if m == "ESCAPE" and int(vm.me().get("neili", 0)) >= UiKeys.QING_ESCAPE_COST:
			return UiKeys.QING_NO_ESCAPE_TIP
		# M3d 審查：寫出要多少（新角色最大內力 20，永遠湊不到 30 卻不知道為什麼）
		return "內力不足，需 %d" % qing_cost(m)
	return ""

func _qing_chosen(m: String) -> void:
	if m == "ESCAPE":
		submit({ "cmd": UiKeys.CMD_QING, "mode": "ESCAPE" })
		return
	cmd_menu.visible = false
	mode = UiKeys.CMD_QING
	pending = { "mode": "JUMP" }
	grid_view.set_range([])
	grid_view.set_highlight(vm.jump_targets(), UiTheme.HIGHLIGHT_MOVE)
	hint_label.text = "點選綠色格子：施展輕功飛身過去（可以越過人）。"

## 裝：換兵器／用藥
func _open_equip_menu() -> void:
	var items := vm.battle_items()
	var med_ok := vm.cmd_open(UiKeys.CMD_ITEM)
	_open_menu("裝", [
		{ "text": "換兵器", "cb": _open_equip },
		{ "text": "用藥（%d 種）" % items.size() if med_ok else "用藥（身上沒有能在戰鬥中用的藥）", "ok": med_ok, "cb": _open_item_menu },
	])

func _open_item_menu() -> void:
	var entries: Array = []
	for it in vm.battle_items():
		entries.append({ "text": "%s ×%d" % [str(it.get("name", "")), int(it.get("n", 0))], "cb": _target_item.bind(it) })
	if not entries.is_empty():
		_open_menu("用藥", entries)

func _target_item(it: Dictionary) -> void:
	_target_ally(UiKeys.CMD_ITEM, 1, true, { "item_uid": str(it.get("uid", "")) },
		"%s：點選綠色格（自己或身旁的隊友）。" % str(it.get("name", "")))

func _open_equip() -> void:
	UiBuild.clear(equip_box)
	var m := vm.me()
	var cur := str((m.get("weapon", {}) as Dictionary).get("uid", ""))
	for opt in m.get("weapon_options", []):
		if not (opt is Dictionary):
			continue
		var uid := str(opt.get("uid", ""))
		var b := UiBuild.button(equip_box, "%s%s" % [str(opt.get("name", "")), "（手上）" if uid == cur else ""])
		b.disabled = uid == cur
		b.pressed.connect(func():
			equip_panel.visible = false
			submit({ "cmd": UiKeys.CMD_EQUIP, "item_uid": uid }))
	var bare := UiBuild.button(equip_box, "空手" + ("（目前）" if cur == "" else ""))
	bare.disabled = cur == ""
	bare.pressed.connect(func():
		equip_panel.visible = false
		submit({ "cmd": UiKeys.CMD_EQUIP, "item_uid": "" }))
	equip_panel.visible = true

func _on_cell(c: Vector2i) -> void:
	if mode == "" or vm == null:
		return
	if not grid_view.highlight.has(c):
		return
	var target := vm.to_host_arr(c)   # 鏡像時轉回主機座標（M2_PLAN 4.5.3）
	match mode:
		UiKeys.CMD_MOVE:
			submit({ "cmd": UiKeys.CMD_MOVE, "target": target })
		UiKeys.CMD_ATTACK:
			submit({ "cmd": UiKeys.CMD_ATTACK, "target": target })
		UiKeys.CMD_ART:
			submit({ "cmd": UiKeys.CMD_ART, "art": pending_art["art"], "move": pending_art["move"],
				"power_tenths": int(pending_art["power_tenths"]), "target": target })
		UiKeys.CMD_FORMATION:
			submit_formation()
		UiKeys.CMD_QING:
			submit({ "cmd": UiKeys.CMD_QING, "mode": "JUMP", "target": target })
		UiKeys.CMD_POISON, UiKeys.CMD_MEDIC, UiKeys.CMD_HIDDEN, UiKeys.CMD_ACUPOINT, UiKeys.CMD_ITEM, UiKeys.CMD_INNER:
			var cmd := { "cmd": mode, "target": target }
			for k in ["art", "item_uid", "mode"]:
				if pending.has(k) and str(pending[k]) != "":
					cmd[k] = pending[k]
			submit(cmd)

func cancel_mode() -> void:
	mode = ""
	pending_art = {}
	pending = {}
	hint_label.text = ""
	grid_view.clear_highlight()
	art_picker.visible = false
	equip_panel.visible = false
	if cmd_menu != null:
		cmd_menu.visible = false

## 組成 battle_cmd 的 args（3.6）
func build_args(cmd: Dictionary) -> Dictionary:
	var args := { "battle_id": vm.bid }
	for k in cmd:
		args[k] = cmd[k]
	return args

func submit(cmd: Dictionary) -> void:
	if vm == null or sending:
		return
	var args := build_args(cmd)
	cancel_mode()
	sending = true
	gate.send(UiKeys.I_BATTLE_CMD, args, [], func(ok: bool, reason: String):
		sending = false
		if ok:
			vm.mark_submitted()
		else:
			vm.unmark_submitted()
			_log_plain(UiClient.reason_inline(reason), TextRenderer.ERROR_COLOR))

# ---------- 事件 ----------
func _on_events(batch: Array) -> void:
	for e in batch:
		if e is Dictionary:
			apply_event(e)

func apply_event(e: Dictionary) -> void:
	if vm == null:
		return
	e = vm.localize_event(e)
	var applied := vm.apply_event(e)
	if applied and str(e.get("key", "")) == UiKeys.E_BATTLE_UNIT_JOIN:
		_build_gauges()
	if applied and str(e.get("key", "")) == UiKeys.E_BATTLE_GAUGES:
		_anchor_ms = Time.get_ticks_msec()
	if applied:
		grid_view.on_event(e)   # 只播動畫，不影響 VM 與回合流程
	if str(e.get("ch", "")) == UiKeys.CH_BATTLE:
		var bb := TextRenderer.render(e, UiClient.my_peer(), UiClient.templates())
		if bb != "":
			if _result_from >= 0:
				_insert_before_result(bb)
			else:
				_append(bb)

func _log_plain(t: String, color: String = "#ffa040") -> void:
	if t != "":
		_append("[color=%s]%s[/color]" % [color, TextRenderer.escape_bbcode(t)])

func _append(bb: String) -> void:
	if log_lines >= UiKeys.LOG_MAX_LINES:
		log_text.remove_paragraph(0)
		log_lines -= 1
		if not _log_entries.is_empty():
			_log_entries.pop_front()
			if _result_from > 0:
				_result_from -= 1
	log_text.append_text(bb + "\n")
	_log_entries.append(bb)
	log_lines += 1
	# 審查 round 4：結束時最後幾行（擊倒、「你一個轉身，逃…」）沒捲上來、最下一行切半：自己捲到底、只露整行
	UiBuild.stick_whole_lines.call_deferred(log_text)

## 結果出來後才到的戰鬥行：插在結果行前面，整個戰報重畫
func _insert_before_result(bb: String) -> void:
	_log_entries.insert(clampi(_result_from, 0, _log_entries.size()), bb)
	_result_from += 1
	while _log_entries.size() > UiKeys.LOG_MAX_LINES:
		_log_entries.pop_front()
		_result_from = maxi(0, _result_from - 1)
	log_text.clear()
	for line in _log_entries:
		log_text.append_text(str(line) + "\n")
	log_lines = _log_entries.size()
	UiBuild.stick_whole_lines.call_deferred(log_text)

## 戰報純文字（測試用）
func log_plain_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	var rx := RegEx.create_from_string("\\[[^\\]]*\\]")
	for line in _log_entries:
		out.append(rx.sub(str(line), "", true))
	return out

const RESULT_MARGIN := 12.0

## 結果小條的位置：右下、左下、正下方三個候選，挑蓋到最少格子的（逃跑格、有人的格子權重高）；
## 審查：原本固定在下緣正中，1920 時壓住逃跑格和半個戰場
func _place_result() -> void:
	if result_panel == null:
		return
	var sz := result_panel.get_combined_minimum_size().max(result_panel.size)
	var area := size
	var y := area.y - sz.y - RESULT_MARGIN
	var cands := [Vector2(area.x - sz.x - RESULT_MARGIN, y), Vector2(RESULT_MARGIN, y), Vector2((area.x - sz.x) / 2.0, y)]
	var best: Vector2 = cands[0]
	var best_score := INF
	for c in cands:
		var sc := result_cover_score(Rect2(c, sz))
		if sc < best_score - 0.01:
			best_score = sc
			best = c
	result_panel.position = Vector2(clampf(best.x, 0.0, maxf(0.0, area.x - sz.x)), clampf(best.y, 0.0, maxf(0.0, area.y - sz.y)))

## 一個矩形蓋到幾格戰場：一般格 1、有人（活的或屍體）5、逃跑格 10
func result_cover_score(r: Rect2) -> float:
	if grid_view == null or vm == null:
		return 0.0
	var occupied := {}
	for uid in vm.units:
		var u: Dictionary = vm.units[uid]
		if str(u.get("state", "")) != "FLED":
			occupied[u.get("pos", Vector2i(-1, -1))] = true
	var score := 0.0
	var gr := r.grow(6.0)
	for x in grid_view.grid_w():
		for y in grid_view.grid_h():
			var c := Vector2i(x, y)
			if not gr.has_point(grid_view.position + grid_view.cell_center(c)):
				continue
			score += 10.0 if vm.is_escape(c) else (5.0 if occupied.has(c) else 1.0)
	return score

## 只列出有拿到的獎勵；全部是 0（戰敗、死亡）時回空字串，不顯示「+0 +0 +0」
static func reward_line(rw: Dictionary) -> String:
	var parts: PackedStringArray = []
	for pair in [["combat_xp", "實戰經驗"], ["learn_points", "學習點數"], ["money", "銀兩"]]:
		var n := UiBuild.num(rw.get(pair[0], 0))
		if n != 0:
			parts.append("%s +%d" % [pair[1], n])
	return "　".join(parts)

## result = 3.9.4
## M3c 審查：一擊斃命時「戰鬥結束」小條與「倒下」比最後一擊的武器特效還早出來 → 有特效還在播就先等它播完
## （最多 RESULT_WAIT_MAX 秒；沒有特效時立刻顯示，行為與以前相同）
const RESULT_WAIT_MAX := 0.6
var _result_token := 0

func show_result(result: Dictionary) -> void:
	if not _built:
		_build()
	cancel_mode()
	var wait := 0.0
	if grid_view != null and grid_view.fx != null and grid_view.fx.has_method("weapon_fx_left"):
		grid_view.fx.compress_weapon_fx()
		wait = minf(RESULT_WAIT_MAX, float(grid_view.fx.weapon_fx_left()))
	_result_token += 1
	if vm:
		vm.ended = true   # 等特效時指令列就關掉（勝負已分；之後才到的事件照 ended 收尾）
	if wait > 0.02 and is_inside_tree():
		var tok := _result_token
		get_tree().create_timer(wait).timeout.connect(func():
			if tok == _result_token and is_instance_valid(self):
				_show_result_now(result))
		return
	_show_result_now(result)

func _show_result_now(result: Dictionary) -> void:
	if vm:
		vm.ended = true
		grid_view.settle()   # 還在排隊的動畫直接收尾：倒下的就躺下，不會站著蓋在別人身上
		grid_view.fx.close_popups()   # 結果小條出來：飄字（-19、-5…）全部收掉，之後也不再飄（審查 round 4）
	var r := str(result.get("result", ""))
	result_label.text = UiKeys.RESULT_LABELS.get(r, r)
	var lines: PackedStringArray = []
	var rw: Dictionary = result.get("rewards", {})
	var rogue := BattleScreen.is_rogue_result(result, vm)   # ROGUE WP-ALLY：試煉不顯示實戰／學點／金錢、死亡損失
	return_button.text = "繼續" if rogue else "返回"   # ROGUE WP-ALLY
	if rogue:
		rw = {}
		lines = BattleScreen.rogue_result_lines(result)
	elif r == "VICTORY" and bool(result.get("enemies_fled", false)):
		result_label.text = "對手逃走了"
		lines.append("對手逃出戰圈，這一仗沒有任何收穫。下次趁牠氣血不足一成前一口氣解決。")
	elif not rw.is_empty():
		var gains := reward_line(rw)
		if gains != "":
			lines.append(gains)
		var items := loot_names(rw.get("items", []))
		if not items.is_empty():
			lines.append("得到：" + "、".join(items))
	var death: Dictionary = result.get("death", {})
	if not rogue and (bool(result.get("you_died", false)) or not death.is_empty()):
		lines.append("你死了。")
		for sl in death.get("skill_losses", []):
			if sl is Dictionary:
				lines.append("%s 退步到 %d 級" % [str(sl.get("name", sl.get("skill", ""))), UiBuild.num(sl.get("to", 0))])
		if UiBuild.num(death.get("n_items", 0)) > 0:
			lines.append("%d 件物品留在屍體上" % UiBuild.num(death.get("n_items", 0)))
		if UiBuild.num(death.get("money_lost", 0)) > 0:
			lines.append("掉了 %d 兩銀子" % UiBuild.num(death.get("money_lost", 0)))
		if str(death.get("respawn_room_name", "")) != "":
			lines.append("你將在%s醒來。" % str(death.get("respawn_room_name", "")))
	var bb_lines: PackedStringArray = []
	for l in lines:
		bb_lines.append(loot_line_bb(rw.get("items", []), _result_font(), RESULT_FONT_SIZE, result_detail.custom_minimum_size.x)
			if l.begins_with("得到：") else TextRenderer.escape_bbcode(l))
	result_detail.text = "\n".join(bb_lines)
	_loot_flair(rw.get("items", []) if r == "VICTORY" else [])
	# 戰報：「戰鬥結束」放在最後；實戰／學點／銀兩主機已經用 battle_reward 印過（不重複），物品與死亡損失另印。
	# 之後才到的戰鬥事件插在這幾行前面（_insert_before_result）
	_result_from = _log_entries.size()
	_log_plain("戰鬥結束：%s" % result_label.text, TextRenderer.CHANNEL_COLORS["SYSTEM"])
	for l in lines:
		if not rw.is_empty() and l == reward_line(rw):
			continue
		if l.begins_with("對手逃出戰圈"):
			continue   # 主機 battle_victory_fled 已經說過
		if l.begins_with("得到："):
			_append(loot_log_bb(rw.get("items", []), TextRenderer.CHANNEL_COLORS["BATTLE"]))   # M3c 第二輪審查：戰報也依稀有度上色
			continue
		_log_plain(l, TextRenderer.CHANNEL_COLORS["BATTLE"])
	result_panel.visible = true
	result_panel.size = Vector2.ZERO
	result_panel.reset_size()
	_place_result()
	_place_result.call_deferred()
	# 自動返回開著（預設）時不放「返回」鈕：原作沒有結算畫面，小條出來就自己回去（任意鍵立刻返回）；
	# 關掉自動返回時才需要按鈕（M3a UI 審查 #8）
	var auto := UiSettings.get_bool("ui.battle_auto_return")
	return_button.visible = not auto
	if auto:
		return_at_ms = Time.get_ticks_msec() + int(AUTO_RETURN_S * 1000.0)

# ---------------------------------------------------------------- M3c 戰利品稀有度（M3C_PLAN §6.7；WP-LOOT）

## 「名稱 ×n」：精品以上前面加「【精品】」等字樣（純文字；戰報與結果行共用）
static func loot_names(items: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for it in items:
		if it is Dictionary:
			out.append("%s ×%d" % [LootUi.decorated_name(str(it.get("name", it.get("id", ""))), it.get("rarity", "COMMON")),
				UiBuild.num(it.get("n", 1))])
	return out

## 戰報（深色底）的「得到：」行：凡品照戰報色，良品以上用 LootUi.dark_color（M3c 第二輪審查）
static func loot_log_bb(items: Array, base_color: String) -> String:
	var parts: PackedStringArray = []
	for it in items:
		if it is Dictionary:
			var nm := TextRenderer.escape_bbcode(str(it.get("name", it.get("id", ""))))
			var r: Variant = it.get("rarity", "COMMON")
			var t := "%s ×%d" % [LootUi.decorated_name(nm, r), UiBuild.num(it.get("n", 1))]
			parts.append(("[color=#%s]%s[/color]" % [LootUi.dark_color(r).to_html(false), t]) if LootUi.rank(r) >= 1 else t)
	return "[color=%s]得到：%s[/color]" % [base_color, "、".join(parts)]

## 結果框的「得到：」行（BBCode，依稀有度上色）。
## M3c 第三輪審查：給了字型與寬度時自己排行——一件「名稱 ×n」整件換到下一行，不會留一個「×1」孤零零在下一行
## （自動換行會在名稱與「×」中間的空白斷開，129_m3c_loot_result）。沒給字型（測試、舊呼叫）照舊一行，交給自動換行。
const RESULT_FONT_SIZE := 16
const LOOT_WRAP_SLACK := 0.94      # 量出來的寬度留 6% 餘裕（RichTextLabel 的排版與 Font.get_string_size 略有差異）

static func loot_line_bb(items: Array, font: Font = null, font_size := RESULT_FONT_SIZE, max_w := 0.0) -> String:
	var parts: PackedStringArray = []
	var plain: PackedStringArray = []
	for it in items:
		if it is Dictionary:
			var raw := str(it.get("name", it.get("id", "")))
			var nm := TextRenderer.escape_bbcode(raw)
			parts.append("%s ×%d" % [LootUi.bb_name_paper(nm, it.get("rarity", "COMMON")), UiBuild.num(it.get("n", 1))])
			plain.append("%s ×%d" % [LootUi.decorated_name(raw, it.get("rarity", "COMMON")), UiBuild.num(it.get("n", 1))])
	return "得到：" + join_wrapped(parts, plain, "、", "得到：", font, font_size, max_w * LOOT_WRAP_SLACK)

## 把幾段（bb：BBCode、plain：量寬度用的純文字）用 sep 串起來；放不下的那一段前面換行（整段不拆開）
static func join_wrapped(bb: PackedStringArray, plain: PackedStringArray, sep: String, prefix: String, font: Font,
		font_size: int, max_w: float) -> String:
	if font == null or max_w <= 0.0:
		return sep.join(bb)
	var out := ""
	var line_w := font.get_string_size(prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var sep_w := font.get_string_size(sep, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	for i in bb.size():
		var w := font.get_string_size(plain[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if i == 0:
			out += bb[i]
			line_w += w
			continue
		if line_w + sep_w + w > max_w:
			out += sep + "
" + bb[i]
			line_w = w
		else:
			out += sep + bb[i]
			line_w += sep_w + w
	return out

func _result_font() -> Font:
	if result_detail == null:
		return null
	return result_detail.get_theme_font("normal_font")

## 最好的稀有度（沒有物品回 ""）
static func best_rarity(items: Array) -> String:
	var best := ""
	for it in items:
		if it is Dictionary and (best == "" or LootUi.rank(it.get("rarity", "COMMON")) > LootUi.rank(best)):
			best = LootUi.norm(it.get("rarity", "COMMON"))
	return best

## 精品以上：結果框 0.6 秒光暈；珍品以上：標題下金字「得到寶物！」
func _loot_flair(items: Array) -> void:
	var best := best_rarity(items)
	treasure_label.visible = best != "" and LootUi.rank(best) >= LootUi.rank("TREASURE")
	loot_glow_rarity = ""
	result_panel.self_modulate = Color.WHITE
	if best == "" or LootUi.rank(best) < LootUi.rank("RARE"):
		return
	loot_glow_rarity = best
	var c := LootUi.rarity_color(best)
	result_panel.self_modulate = Color(1.0 + c.r * 0.6, 1.0 + c.g * 0.6, 1.0 + c.b * 0.6)
	var tw := create_tween()
	tw.tween_property(result_panel, "self_modulate", Color.WHITE, 0.6)

# ==== M3d WP-EVENTS ====（M3D_PLAN §5.3.4、§9.2：比武（DUEL）的擂臺倒數）
## 戰鬥畫面上方正中的名牌「擂臺 9:58」：只在 DUEL（快照 kind == "DUEL" 或帶 duel_left_s ≥ 0）時出現。
## 主機的限時用戰鬥時間（tick × 0.1 秒；等待下令時 tick 照走）；客戶端在等待下令時時間棒暫停、tick 不再前進，
## 所以倒數取「快照之後的 tick 差」與「快照之後的真實秒數」兩者較大的一個（time_scale 1 時兩者一致）。
## 最後 60 秒字轉紅。時間到由主機判定（總傷害 → 命中 → 氣比例 → 先報名者）。
var duel_hud: Label = null
var _duel_key := ""
var _duel_ms0 := 0

static func duel_left(state: Dictionary, tick_now: float, real_elapsed_s: float = 0.0) -> float:
	if state.is_empty():
		return -1.0
	var left0 := float(state.get("duel_left_s", -1.0))
	if left0 < 0.0 and str(state.get("kind", "")) != "DUEL":
		return -1.0
	if left0 < 0.0:
		left0 = float(state.get("duel_limit_s", TourneyRules.DUEL_LIMIT_S))
	var t0 := float(state.get("tick", 0))
	var by_tick := maxf(0.0, tick_now - t0) / float(UiKeys.TICKS_PER_SEC)
	return maxf(0.0, left0 - maxf(by_tick, maxf(0.0, real_elapsed_s)))

static func duel_text(left: float) -> String:
	var s := int(ceil(left))
	return "擂臺　%d:%02d" % [s / 60, s % 60]

func _m3d_events_duel_hud(state: Dictionary) -> void:
	var key := "%s|%s|%s" % [str(state.get("bid", "")), str(state.get("tick", "")), str(state.get("duel_left_s", ""))]
	if key != _duel_key:
		_duel_key = key
		_duel_ms0 = Time.get_ticks_msec()
	var real_s := float(Time.get_ticks_msec() - _duel_ms0) / 1000.0
	var left := BattleScreen.duel_left(state, now_tick(), real_s) if vm != null else -1.0
	if left < 0.0:
		if duel_hud != null:
			duel_hud.get_parent().visible = false
		return
	if duel_hud == null:
		duel_hud = UiBuild.plate(self, "", 20, 150.0)
		duel_hud.name = "DuelHud"
		var plate := duel_hud.get_parent() as Control
		plate.name = "DuelHudPlate"
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.position = Vector2(0.0, 8.0)
		plate.tooltip_text = "比武限時十分鐘（戰鬥時間）：時間到依總傷害、命中次數、剩餘氣的比例判定勝負"
	var plate2 := duel_hud.get_parent() as Control
	plate2.visible = true
	plate2.position.x = (size.x - plate2.size.x) * 0.5
	duel_hud.text = BattleScreen.duel_text(left)
	duel_hud.add_theme_color_override("font_color", UiTheme.JY_RED if left <= 60.0 else UiTheme.JY_TEXT)

# ==== ROGUE WP-ALLY ====
## ROGUE_PLAN §4.6、§6.4：江湖試煉的結果框。result.kind（或快照 kind）== "ROGUE" → 不顯示實戰／學點／金錢與死亡損失，
## 改顯示 result.rogue = { round, won, boss, allies_fallen: [名字], over }：「第 N 回合　勝」或「試煉結束」、倒下的隊友名單。
const ROGUE_KIND := "ROGUE"

static func is_rogue_result(result: Dictionary, model: BattleViewModel = null) -> bool:
	if str(result.get("kind", "")) == ROGUE_KIND:
		return true
	return model != null and model.kind == ROGUE_KIND

static func rogue_result_lines(result: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var rg: Variant = result.get("rogue", {})
	var d: Dictionary = rg if rg is Dictionary else {}
	var rnd := UiBuild.num(d.get("round", 0))
	var won := bool(d.get("won", str(result.get("result", "")) == "VICTORY"))
	var over := bool(d.get("over", false))
	if over or not won:
		if bool(result.get("you_died", false)) or str(result.get("result", "")) == "DEFEAT":
			out.append("你力戰倒下。")
			if UiBuild.num(d.get("allies_standing", 0)) > 0:
				out.append(UiKeys.ROGUE_DOWN_NOTE)   # 審查：「隊友還站著怎麼就輸了」
		out.append("試煉結束")
	elif rnd > 0:
		out.append(("第 %d 回合　勝" % rnd) + ("（名人敗退）" if bool(d.get("boss", false)) else ""))
	else:
		out.append("勝")
	var fallen: PackedStringArray = []
	var fl: Variant = d.get("allies_fallen", [])
	var fl_arr: Array = fl if fl is Array else []
	for n in fl_arr:
		if str(n) != "":
			fallen.append(str(n))
	if not fallen.is_empty():
		out.append("倒下的隊友：" + "、".join(fallen))
	return out
