class_name CraftWindow
extends NumberedDialog
## 製作窗（M3B_PLAN §7.3、§4.5）：場景卷軸「動作」列的「製作」鈕，或指令窗「行動 → 製作」打開。
## 依目前房間的設施（view.features）列出能用的生活技能：
## - 採集／打獵（GATHER、HUNT）：直接一顆按鈕 → work { skill }（打獵由主機開戰）；
## - 配方：材料夠的亮、不夠的灰並寫缺什麼；等級不夠寫「需 N 級」；缺工具寫工具名 → work { skill, recipe }。
## 隨地可做的配方（裁縫、工匠：feature ""）只列已學會的技能。結果訊息由主機事件走系統框。
## 角色表或房間變了就重算（主畫面轉 apply_sheet／apply_view）；冷卻中（sheet.cooldowns.life）全部灰掉並顯示秒數。
## 數字鍵 1–9：依序按第 n 個可做的項目。

var view: Dictionary = {}
var sheet: Dictionary = {}
var list: VBoxContainer
var room_label: Label
var entries: Array = []
var action_buttons: Dictionary = {}   # "skill" 或 "skill:recipe" -> Button
var cooldowns := CooldownTracker.new()
var _shown_s := -1

func dialog_size() -> Vector2:
	return Vector2(640, 420)

func _build_body() -> void:
	title_label.text = "製作"
	room_label = UiBuild.muted(UiBuild.label(body, "", 14, true))
	room_label.name = "Facilities"
	var sc := UiBuild.scroll(body, 300)
	list = UiBuild.vbox(sc, 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func open_craft(v: Dictionary = {}, s: Dictionary = {}) -> void:
	ensure_built()
	view = v if not v.is_empty() else UiClient.region_view()
	sheet = s if not s.is_empty() else UiClient.sheet()
	cooldowns.update(sheet)
	status_label.text = ""
	visible = true
	_render()

func apply_sheet(s: Dictionary) -> void:
	sheet = s
	cooldowns.update(s)
	if _built and visible:
		_render()

func apply_view(v: Dictionary) -> void:
	view = v
	if _built and visible:
		_render()

static func facilities_text(v: Dictionary) -> String:
	var names: PackedStringArray = []
	for f in v.get("features", []):
		var n := str(UiKeys.FEATURE_LABELS.get(str(f), ""))
		if n != "" and not names.has(n):
			names.append(n)
	return "這裡的設施：%s" % ("、".join(names) if not names.is_empty() else "（無；只能做隨地可做的東西）")

func _render() -> void:
	UiBuild.clear(list)
	clear_choices()
	action_buttons.clear()
	room_label.text = "%s　%s" % [str(view.get("room_name", "")), CraftWindow.facilities_text(view)]
	entries = EconUi.craft_entries(view, sheet)
	var cd := cooldowns.left_s(CooldownTracker.KEY_LIFE)
	_shown_s = cd
	var n := 0
	for e in entries:
		var head := UiBuild.accent(UiBuild.label(list, "%s　%s" % [str(e["name"]), ("%d 級" % int(e["level"])) if bool(e["known"]) else "（還沒學會）"], 16))
		head.name = "Skill_" + str(e["id"])
		var g: Variant = e["gather"]
		if g is Dictionary:
			var row := UiBuild.hbox(list, 6)
			var ok := bool(g["ok"])
			if ok:
				n += 1
			NumberedDialog.numbered_label(row, n if ok else 99)
			var b := UiBuild.button(row, CooldownTracker.label(str(g["verb"]), cd))
			b.name = "Gather_" + str(e["id"])
			b.set_meta("base", str(g["verb"]))
			b.set_meta("ok", ok)
			b.disabled = not ok or cd > 0
			b.tooltip_text = "打贏野獸可以得到額外的肉與獸皮" if bool(g.get("hunt", false)) else "在這裡%s" % str(g["verb"])
			var sid := str(e["id"])
			b.pressed.connect(func(): do_work(sid, "", b))
			action_buttons[sid] = b
			if ok:
				add_choice(b)
			if not ok:
				var why := UiBuild.error(UiBuild.label(row, str(g["why"]), 14))
				why.name = "Why_" + sid
		for r in e["recipes"]:
			var row2 := UiBuild.hbox(list, 6)
			var ok2 := bool(r["ok"])
			if ok2:
				n += 1
			NumberedDialog.numbered_label(row2, n if ok2 else 99)
			var label := "%s（%s → %s；%d 級）" % [str(r["name"]), str(r["inputs"]), str(r["output"]), int(r["level"])]
			var b2 := UiBuild.button(row2, CooldownTracker.label(label, cd))
			var key := "%s:%s" % [str(e["id"]), str(r["id"])]
			b2.name = "Recipe_" + str(r["id"])
			b2.set_meta("base", label)
			b2.set_meta("ok", ok2)
			b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b2.disabled = not ok2 or cd > 0
			var sid2 := str(e["id"])
			var rid := str(r["id"])
			b2.pressed.connect(func(): do_work(sid2, rid, b2))
			action_buttons[key] = b2
			if ok2:
				add_choice(b2)
			else:
				var why2 := UiBuild.error(UiBuild.label(row2, str(r["why"]), 14))
				why2.name = "Why_" + rid
				b2.tooltip_text = str(r["why"])
	if entries.is_empty():
		UiBuild.muted(UiBuild.label(list, "這裡沒有可以做的生活技能。礦場、打鐵爐、鑄劍爐、織布機、烘皮爐、燒炭爐、打獵專區在各城與郊外；裁縫、工匠隨地可做。", 15, true))

func do_work(skill: String, recipe: String, b: Button) -> int:
	if b != null and b.disabled:
		return -1
	return send(UiKeys.I_WORK, EconUi.work_args(skill, recipe), [b] if b != null else [])

## 冷卻倒數：秒數變了才改字
func _process(_delta: float) -> void:
	if not visible or not _built:
		return
	var cd := cooldowns.left_s(CooldownTracker.KEY_LIFE)
	if cd == _shown_s:
		return
	_shown_s = cd
	for k in action_buttons:
		var b: Button = action_buttons[k]
		if not is_instance_valid(b):
			continue
		b.text = CooldownTracker.label(str(b.get_meta("base", b.text)), cd)
		b.disabled = not bool(b.get_meta("ok", false)) or cd > 0 or (gate != null and gate.is_pending(UiKeys.I_WORK))
