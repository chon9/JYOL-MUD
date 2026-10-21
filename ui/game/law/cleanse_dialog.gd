class_name CleanseDialog
extends NumberedDialog
## 天師消殺氣、京城半仙消 PK值（M3D_PLAN §2.7；WP-LAW）：NPC 選單「消災」開啟。
## 天師（cleanse: KILLING）：目前殺氣、最多能化解幾次、要多少錢，選次數 → cleanse { npc, what: KILLING, times }；
## 半仙（cleanse: PK）：目前 PK值、價錢，確認 → cleanse { npc, what: PK }（每遊戲日一點）。

const WHAT_KILLING := "KILLING"
const WHAT_PK := "PK"

var npc := ""
var npc_name := ""
var what := WHAT_KILLING
var info_label: Label
var times_box: SpinBox
var cost_label: Label
var ok_button: Button

func dialog_size() -> Vector2:
	return Vector2(460, 0)

func _build_body() -> void:
	title_label.text = "消災"
	info_label = UiBuild.label(body, "", 16, true)
	info_label.name = "CleanseInfo"
	var row := UiBuild.hbox(body, 8)
	row.name = "TimesRow"
	UiBuild.label(row, "化解次數：", 15)
	times_box = SpinBox.new()
	times_box.name = "CleanseTimes"
	times_box.min_value = 1
	times_box.max_value = 1
	times_box.step = 1
	times_box.custom_minimum_size = Vector2(110, 0)
	row.add_child(times_box)
	cost_label = UiBuild.accent(UiBuild.label(row, "", 15))
	cost_label.name = "CleanseCost"
	times_box.value_changed.connect(func(_v: float): _update_cost())
	var foot := UiBuild.hbox(body, 8)
	ok_button = UiBuild.button(foot, "化解", _confirm, 120)
	ok_button.name = "CleanseOk"
	add_choice(ok_button)
	add_choice(UiBuild.button(foot, "再想想", close, 90))

## 最多可以化解幾次（同 BountyRules.tianshi）：殺氣每 10 點一次、每次 100 兩
static func max_times(killing_intent: int, money: int) -> int:
	return int(BountyRules.tianshi(killing_intent, BountyRules.TIANSHI_MAX_TIMES, money)["times"])

## 說明文字
static func info_text(kind: String, sh: Dictionary, name: String) -> String:
	var money := UiBuild.num(sh.get("money", 0))
	if kind == WHAT_PK:
		var pk := UiBuild.num(sh.get("pk", 0))
		return "%s：「一天只替你消一點 PK值，一點 %s 兩。」\n你目前的 PK值：%d　身上銀兩：%s 兩" % [name,
			BountyDialog.money_text(BountyRules.BANXIAN_PRICE_PER_PK), pk, BountyDialog.money_text(money)]
	var ki := UiBuild.num(sh.get("killing_intent", 0))
	# M3d 審查：「最多可以化解 N 次」自己一行（原本接在同一行尾，視窗窄時從「化／解」中間斷開）
	return "%s：「每化去 %d 點殺氣，香油錢 %d 兩。」\n你目前的殺氣：%d　身上銀兩：%s 兩\n最多可以化解 %d 次" % [name,
		BountyRules.TIANSHI_PER_TIME, BountyRules.TIANSHI_PRICE_PER_10, ki, BountyDialog.money_text(money),
		CleanseDialog.max_times(ki, money)]

## menu = npc_menu（npc、npc_name）；kind = NPC 列的 cleanse（KILLING／PK）
func open_for(menu: Dictionary, kind: String) -> void:
	ensure_built()
	npc = str(menu.get("npc", ""))
	npc_name = str(menu.get("npc_name", ""))
	what = WHAT_PK if kind == WHAT_PK else WHAT_KILLING
	title_label.text = "消 PK值" if what == WHAT_PK else "化解殺氣"
	status_label.text = ""
	visible = true
	refresh()

func refresh() -> void:
	var sh := UiClient.sheet()
	info_label.text = CleanseDialog.info_text(what, sh, npc_name)
	var n := CleanseDialog.max_times(UiBuild.num(sh.get("killing_intent", 0)), UiBuild.num(sh.get("money", 0)))
	(times_box.get_parent() as Control).visible = what == WHAT_KILLING
	times_box.max_value = maxi(1, n)
	times_box.value = clampf(times_box.value, 1, maxi(1, n))
	if what == WHAT_PK:
		ok_button.text = "消一點 PK值（%s 兩）" % BountyDialog.money_text(BountyRules.BANXIAN_PRICE_PER_PK)
	else:
		ok_button.text = "化解"
	# M3d 審查：按鈕灰掉時說明原因（提示＋狀態列）
	var why := CleanseDialog.block_reason(what, sh)
	ok_button.disabled = why != ""
	ok_button.tooltip_text = why
	status_label.text = why
	_update_cost()

## 按鈕不能按的原因（""＝可以按）
static func block_reason(kind: String, sh: Dictionary) -> String:
	var money := UiBuild.num(sh.get("money", 0))
	if kind == WHAT_PK:
		if UiBuild.num(sh.get("pk", 0)) <= 0:
			return "你身上沒有 PK值，不必消。"
		if money < BountyRules.BANXIAN_PRICE_PER_PK:
			return "銀兩不夠：消一點 PK值要 %s 兩。" % BountyDialog.money_text(BountyRules.BANXIAN_PRICE_PER_PK)
		return ""
	var ki := UiBuild.num(sh.get("killing_intent", 0))
	if ki < BountyRules.TIANSHI_PER_TIME:
		return "殺氣不到 %d 點，不必化解。" % BountyRules.TIANSHI_PER_TIME
	if money < BountyRules.TIANSHI_PRICE_PER_10:
		return "銀兩不夠：化解一次要 %d 兩。" % BountyRules.TIANSHI_PRICE_PER_10
	return ""

func _update_cost() -> void:
	cost_label.text = "共 %d 兩" % (int(times_box.value) * BountyRules.TIANSHI_PRICE_PER_10)

func _confirm() -> void:
	var args := { "npc": npc, "what": what }
	if what == WHAT_KILLING:
		args["times"] = int(times_box.value)
	send(UiKeys.I_CLEANSE, args, [ok_button], close)
