class_name CommandBar
extends Control
## 戰鬥指令圓盤（AUTHENTIC_UI_SPEC §12.2；M1_PLAN 3.12）：直徑 40 的圓盤兩列蜂巢排列（第二列右移半顆）：
##   第一列 防 內 休 逃 輕 裝 武 屬 系；第二列 移 攻 特 毒 醫 陣 暗 穴。
## 已實作 移 攻 武 防 休 裝 逃（快捷鍵 1–7，只在輪到我時可按；逃只有站在逃跑格上可按）；
## M3a（M3A_PLAN §7.1）：毒 醫 暗 陣 內 穴（快捷鍵 8 9 0、Shift+1 2 3）依快照 cmd_avail 啟用；
## 伺服器規則 later_battle_cmds 關掉時「內」「穴」維持不能用樣式，提示「原作 2002 年才有（伺服器規則關閉）」。
## 身上的狀態封鎖某個指令（例：封穴不能移、逃）時該指令灰掉，提示寫是哪個狀態。
## 屬／系 開屬性窗（唯讀）與系統窗（panel_requested）；輕、特 用「不能用」樣式，提示「尚未開放」。
## 整組可以用滑鼠右鍵拖到任何位置（moved(pos) → 戰鬥畫面記在 settings.json 的 ui.battle_cmd_pos）。

signal command_chosen(cmd: String)
signal panel_requested(pid: String)
signal moved(pos: Vector2)

const DISC := 40.0
const GAP := 4.0

var buttons: Dictionary = {}     # cmd -> JyButton（已實作的 13 個）
var discs: Dictionary = {}       # 圓盤字 -> JyButton（全部）
var _drag_from := Vector2(-1, -1)
var _built := false

func _ready() -> void:
	if not _built:
		_build()

func _build() -> void:
	_built = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	var w := 0.0
	for r in UiKeys.CMD_DISC_ROWS.size():
		var row: Array = UiKeys.CMD_DISC_ROWS[r]
		for i in row.size():
			var g: String = row[i]
			var b := UiBuild.disc_button(self, g)
			b.size = Vector2(DISC, DISC)
			b.position = Vector2(i * (DISC + GAP) + (DISC + GAP) / 2.0 * r, r * (DISC - 2.0))
			w = maxf(w, b.position.x + DISC)
			b.gui_input.connect(_on_drag_input)
			discs[g] = b
			if UiKeys.CMD_BY_GLYPH.has(g):
				var cmd: String = UiKeys.CMD_BY_GLYPH[g]
				b.pressed.connect(func(): command_chosen.emit(cmd))
				b.tooltip_text = UiKeys.CMD_TOOLTIPS.get(cmd, g)
				buttons[cmd] = b
			elif UiKeys.CMD_PANEL_GLYPHS.has(g):
				var pid: String = UiKeys.CMD_PANEL_GLYPHS[g]
				b.pressed.connect(func(): panel_requested.emit(pid))
				b.tooltip_text = UiKeys.CMD_PANEL_TIPS.get(g, g)
			else:
				b.disabled = true
				b.tooltip_text = "%s：%s" % [g, UiKeys.CMD_LOCKED_TIP]
	custom_minimum_size = Vector2(w, DISC * 2.0 - 2.0)
	size = custom_minimum_size

## 這個指令現在不能用的原因（"" = 可以用；不看是否輪到我）。M1 指令看格子，M3a 指令看快照 cmd_avail
static func unavailable_reason(vm: BattleViewModel, cmd: String) -> String:
	if vm == null:
		return ""
	if cmd in UiKeys.LATER_CMDS and not vm.later_cmds:
		return UiKeys.LATER_CMDS_TIP
	var blocked := vm.status_blocks(cmd)
	if blocked != "":
		return "%s中，不能使用" % blocked
	match cmd:
		UiKeys.CMD_FLEE:
			return "" if vm.on_escape() else "要先站上「逃」格"
		UiKeys.CMD_ATTACK:
			return "" if not vm.enemy_cells_within(1).is_empty() else "身旁沒有敵人"
		UiKeys.CMD_ART:
			return "" if not vm.my_arts().is_empty() else "沒有可施展的武功"
		UiKeys.CMD_MOVE:
			return "" if not vm.move_targets().is_empty() else "無路可走"
	if cmd in UiKeys.M3A_CMDS and not vm.cmd_open(cmd):
		return UiKeys.CMD_UNAVAIL_TIPS.get(cmd, "目前不能用")
	# 醫：射程內沒有要治的人（氣滿、沒有中毒流血）→ 跟「運功療傷」的「氣血已滿」一樣灰掉（M3a UI 審查 #4）
	if cmd == UiKeys.CMD_MEDIC and vm.ally_cells_within(medic_range(vm), true, true).is_empty():
		return MEDIC_NOTHING_TIP
	return ""

const MEDIC_NOTHING_TIP := "身旁的人氣血都滿，不必療傷"

## 醫的最遠射程（醫術武功裡最大的 range；沒有醫術武功＝相鄰 1 格）
static func medic_range(vm: BattleViewModel) -> int:
	var r := 1
	for a in vm.cmd_arts(UiKeys.CMD_MEDIC):
		if a is Dictionary:
			r = maxi(r, int(a.get("range", 1)))
	return r

## 依模型狀態設定可按與否
func refresh(vm: BattleViewModel, now_tick: float) -> void:
	if not _built:
		_build()
	var my_turn := vm != null and vm.is_my_turn(now_tick)
	for cmd in buttons:
		var b := buttons[cmd] as JyButton
		var why := CommandBar.unavailable_reason(vm, cmd)
		var ok := my_turn and why == ""
		var tip: String = UiKeys.CMD_TOOLTIPS.get(cmd, cmd)
		if why != "":
			tip = "%s\n（%s）" % [tip, why]
		if b.tooltip_text != tip:
			b.tooltip_text = tip
		if b.disabled == ok:
			b.disabled = not ok
			b.queue_redraw()

func is_enabled(cmd: String) -> bool:
	return buttons.has(cmd) and not (buttons[cmd] as Button).disabled

## 右鍵拖曳整組圓盤
func _on_drag_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			_drag_from = mb.global_position - position
		elif _drag_from.x >= 0.0:
			_drag_from = Vector2(-1, -1)
			moved.emit(position)
		return
	var mm := ev as InputEventMouseMotion
	if mm != null and _drag_from.x >= 0.0 and (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		var area := (get_parent() as Control).size if get_parent() is Control else Vector2(4096, 4096)
		position = CommandBar.clamp_pos(mm.global_position - _drag_from, size, area)

static func clamp_pos(p: Vector2, sz: Vector2, area: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 0.0, maxf(0.0, area.x - sz.x)), clampf(p.y, 0.0, maxf(0.0, area.y - sz.y)))
