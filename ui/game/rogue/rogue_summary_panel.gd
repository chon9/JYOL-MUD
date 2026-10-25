class_name RogueSummaryPanel
extends PanelContainer
## 江湖試煉結算（ROGUE_PLAN §5.5；WP-UI）：琥珀框大窗「試煉結束」。
## 死因、倒在第幾回合（勝幾場）、擊敗對手、首領、最好的一張卡（稀有度色）、招募隊友數、永久點數 +n（累計 / 60）、新紀錄。
## 按鈕「再戰一場」（rogue_open）、「返回標題」。資料＝主機的 summary（§3.9.1）。

signal again_requested
signal title_requested

var summary: Dictionary = {}
var cause_label: Label
var note_label: Label
var rounds_label: Label
var foes_label: Label
var best_label: Label
var allies_label: Label
var points_label: Label
var record_label: Label
var again_button: Button
var title_button: Button

func _init() -> void:
	add_theme_stylebox_override("panel", UiFrame.style(UiFrame.Kind.AMBER))
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(520, 0)
	_build()

func _build() -> void:
	var v := UiBuild.vbox(self, 8)
	var t := UiBuild.label(v, "試煉結束", 36)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", UiTheme.JY_GOLD_LIGHT)
	t.add_theme_font_override("font", UiTheme.brush_font(0.5))
	t.add_theme_constant_override("outline_size", 4)
	t.add_theme_color_override("font_outline_color", UiTheme.JY_WOOD_DARK)
	cause_label = UiBuild.label(v, "", 22)
	cause_label.name = "Cause"
	cause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cause_label.add_theme_color_override("font_color", UiTheme.JY_ERROR_LIGHT)
	note_label = UiBuild.muted(UiBuild.label(v, "", 15, true))
	note_label.name = "Note"
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(HSeparator.new())
	rounds_label = UiBuild.label(v, "", 18)
	rounds_label.name = "Rounds"
	foes_label = UiBuild.label(v, "", 18)
	foes_label.name = "Foes"
	best_label = UiBuild.label(v, "", 18, true)
	best_label.name = "Best"
	allies_label = UiBuild.label(v, "", 18)
	allies_label.name = "Allies"
	v.add_child(HSeparator.new())
	points_label = UiBuild.plate(v, "", 22)
	points_label.name = "Points"
	record_label = UiBuild.label(v, "新紀錄", 22)
	record_label.name = "Record"
	record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record_label.add_theme_color_override("font_color", UiKeys.COMBO_GOLD)
	record_label.add_theme_font_override("font", UiTheme.brush_font(0.5))
	var brow := UiBuild.hbox(v, 16)
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	again_button = UiBuild.button(brow, "再戰一場", func(): again_requested.emit(), 150)
	again_button.name = "Again"
	title_button = UiBuild.button(brow, "返回標題", func(): title_requested.emit(), 150)
	title_button.name = "ToTitle"

static func cause_text(cause: String) -> String:
	return str(UiKeys.ROGUE_CAUSE_TEXT.get(cause, "試煉結束"))

## 「第幾回合」那一行（審查：summary.rounds＝結束時所在的回合＝勝場＋1，不是「撐過」的回合數）
static func rounds_text(cause: String, rounds: int, wins: int) -> String:
	rounds = maxi(1, rounds)
	match cause:
		"ABANDON":
			return "於第 %d 回合放棄（勝 %d 場）" % [rounds, wins]
		"LEAVE":
			return "於第 %d 回合離開（勝 %d 場）" % [rounds, wins]
		"TIMEOUT":
			return "第 %d 回合久戰不決（勝 %d 場）" % [rounds, wins]
	return "倒在第 %d 回合（勝 %d 場）" % [rounds, wins]

func apply_summary(s: Dictionary) -> void:
	summary = s.duplicate(true)
	cause_label.text = cause_text(str(s.get("cause", "")))
	var standing := UiBuild.num(s.get("allies_standing", 0))
	note_label.text = UiKeys.ROGUE_DOWN_NOTE if str(s.get("cause", "")) == "DEATH" and standing > 0 else ""
	note_label.visible = note_label.text != ""
	var rounds := UiBuild.num(s.get("rounds", 0))
	var wins := UiBuild.num(s.get("wins", 0))
	rounds_label.text = rounds_text(str(s.get("cause", "")), rounds, wins)
	foes_label.text = "擊敗對手 %d 名　首領 %d 位" % [UiBuild.num(s.get("foes_beaten", 0)), UiBuild.num(s.get("bosses_beaten", 0))]
	var bc: Variant = s.get("best_card", {})
	if bc is Dictionary and str((bc as Dictionary).get("title", "")) != "":
		var r := str(bc.get("rarity", "COMMON"))
		best_label.text = "最好的一張卡：〔%s〕%s" % [RogueCard.rarity_name(r), str(bc["title"])]
		best_label.add_theme_color_override("font_color", RogueCard.rarity_color(r))
	else:
		best_label.text = "最好的一張卡：沒有"
		best_label.remove_theme_color_override("font_color")
	allies_label.text = "招募隊友 %d 位" % UiBuild.num(s.get("allies_recruited", 0))
	points_label.text = "永久點數 +%d（累計 %d / %d）" % [UiBuild.num(s.get("points_gained", 0)),
		UiBuild.num(s.get("points_total", 0)), UiBuild.num(s.get("points_cap", 0)) if UiBuild.num(s.get("points_cap", 0)) > 0
			else RogueLobbyPanel.rules_points_cap()]
	record_label.visible = bool(s.get("new_best", false))
