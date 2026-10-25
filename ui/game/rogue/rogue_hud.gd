class_name RogueHud
extends PanelContainer
## 江湖試煉的局內 HUD（ROGUE_PLAN §5.4；WP-UI）：左側直欄，玉框（JADE）。
## 回合「第 N 回合」（名牌）、勝場、擊敗數；下一場是首領時紅字「名人登場」。
## 隊友兩格（立繪縮圖、名字、氣條；倒下的灰掉寫「已殞」）。兵器與護具（目前裝備加框；沒裝備的兵器有「裝備」鈕 → equip）。
## 武功（名字、等級、類別；與目前兵器不合的灰字）。屬性七項（琥珀小框）。
## 資料：rogue_state（§6.3）＋角色表（UiClient.sheet()：生命值；state 缺欄位時也從角色表補物品與技能）。

signal equip_requested(item_uid: String)

const WIDTH := 300.0
const THUMB := Vector2(44, 44)
## 需要持對應兵器的武功類別（其他類別：拳掌、內功、輕功、基本武學……不挑兵器）
const WEAPON_CATEGORIES := ["SWORD", "BLADE", "STAFF", "WHIP", "SPEAR", "STAB"]
## 主機 rogue_state.arts 的 category：武功類別，基本武學一律 "BASIC"（server/rogue_system.gd state()）
const CATEGORY_NAMES := { "SWORD": "劍法", "BLADE": "刀法", "STAFF": "杖法", "WHIP": "鞭法", "SPEAR": "槍法", "STAB": "筆法",
	"FIST": "拳掌", "INNER": "內功", "LIGHTNESS": "輕功", "DODGE": "閃躲", "PARRY": "招架", "BASIC": "基本武學" }

var state: Dictionary = {}
var sheet: Dictionary = {}
var round_label: Label
var stats_label: Label
var boss_label: Label
var vitals_label: Label
var ally_rows: Array = []        # [{ box, name, bar, status, thumb_holder }]
var gear_box: VBoxContainer
var arts_box: VBoxContainer
var attr_labels: Dictionary = {}
var equip_buttons: Dictionary = {}   # uid -> Button
var art_rows: Dictionary = {}        # art id -> Label

func _init() -> void:
	add_theme_stylebox_override("panel", UiFrame.style(UiFrame.Kind.JADE))
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func _build() -> void:
	var sc := UiBuild.scroll(self)
	var v := UiBuild.vbox(sc, 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	round_label = UiBuild.plate(v, "第 1 回合", 20)
	round_label.name = "Round"
	stats_label = UiBuild.label(v, "", 15)
	stats_label.name = "Stats"
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label = UiBuild.label(v, "下一場：名人登場", 18)
	boss_label.name = "Boss"
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.add_theme_color_override("font_color", UiTheme.JY_RED)
	boss_label.add_theme_font_override("font", UiTheme.brush_font(0.5))
	boss_label.visible = false
	vitals_label = UiBuild.muted(UiBuild.label(v, "", 14, true))
	vitals_label.name = "Vitals"
	UiBuild.accent(UiBuild.label(v, "隊友", 16))
	for i in UiKeys.ROGUE_ALLY_MAX:
		var row := UiBuild.hbox(v, 6)
		row.name = "Ally%d" % i
		var holder := CenterContainer.new()
		holder.custom_minimum_size = THUMB
		row.add_child(holder)
		var col := UiBuild.vbox(row, 2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nm := UiBuild.label(col, "", 15)
		var bar := UiBuild.bar(col, UiTheme.QI_COLOR, 150)
		var st := UiBuild.muted(UiBuild.label(col, "", 13))
		ally_rows.append({ "box": row, "name": nm, "bar": bar, "status": st, "thumb_holder": holder, "ref": "~" })
	UiBuild.accent(UiBuild.label(v, "兵器與護具", 16))
	gear_box = UiBuild.vbox(v, 3)
	gear_box.name = "Gear"
	UiBuild.accent(UiBuild.label(v, "武功", 16))
	arts_box = UiBuild.vbox(v, 2)
	arts_box.name = "Arts"
	UiBuild.accent(UiBuild.label(v, "屬性", 16))
	var amber := UiBuild.framed(v, UiFrame.Kind.AMBER)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	amber.add_child(grid)
	for a in UiKeys.ATTR_IDS:
		UiBuild.muted(UiBuild.label(grid, UiKeys.ATTR_SHORT[a], 14))
		var l := UiBuild.label(grid, "0", 15)
		l.custom_minimum_size = Vector2(28, 0)
		attr_labels[a] = l

## 類別的中文
static func category_name(cat: String) -> String:
	return str(CATEGORY_NAMES.get(cat, cat))

## 武功與目前兵器相合嗎（兵器類武功要拿同類兵器；其他類別不挑）
static func art_fits(category: String, weapon_type: String) -> bool:
	if not WEAPON_CATEGORIES.has(category):
		return true
	return category == weapon_type

## state.weapons；沒有 → 從角色表的物品（WEAPON 分頁）補
func weapons() -> Array:
	var w: Variant = state.get("weapons", null)
	if w is Array:
		return w
	var out: Array = []
	var inv: Variant = sheet.get("inventory", [])
	if inv is Array:
		for it in inv:
			if it is Dictionary and str(it.get("tab", "")) == "WEAPON":
				var row := UiClient.row("items", str(it.get("id", "")))
				out.append({ "uid": str(it.get("uid", "")), "item_id": str(it.get("id", "")), "name": str(it.get("name", "")),
					"weapon_type": str(row.get("weapon_type", "")), "atk": UiBuild.num(row.get("atk", 0)),
					"equipped": str(it.get("equipped_slot", "")) == "WEAPON" })
	return out

func current_weapon_type() -> String:
	for w in weapons():
		if w is Dictionary and bool(w.get("equipped", false)):
			return str(w.get("weapon_type", ""))
	return "FIST"

## state.arts；沒有 → 角色表技能（特殊武功＋基本武學）
func arts() -> Array:
	var a: Variant = state.get("arts", null)
	if a is Array:
		return a
	var out: Array = []
	var sk: Variant = sheet.get("skills", [])
	if sk is Array:
		for s in sk:
			if s is Dictionary and ["ART", "BASIC"].has(str(s.get("kind", ""))) and UiBuild.num(s.get("level", 0)) > 0:
				out.append({ "id": str(s.get("id", "")), "name": str(s.get("name", "")), "level": UiBuild.num(s.get("level", 0)),
					"category": str(s.get("category", "")) })
	return out

func apply(p_state: Dictionary, p_sheet: Dictionary) -> void:
	state = p_state
	sheet = p_sheet
	round_label.text = "第 %d 回合" % maxi(1, UiBuild.num(state.get("round", 1)))
	stats_label.text = "勝 %d 場　擊敗 %d 名" % [UiBuild.num(state.get("wins", 0)), UiBuild.num(state.get("foes_beaten", 0))]
	boss_label.visible = bool(state.get("next_round_is_boss", false))
	_apply_vitals()
	_apply_allies()
	_apply_gear()
	_apply_arts()
	var attrs: Variant = state.get("attrs", sheet.get("attrs", {}))
	for a in UiKeys.ATTR_IDS:
		(attr_labels[a] as Label).text = str(UiBuild.num((attrs as Dictionary).get(a, 0))) if attrs is Dictionary else "0"

func _apply_vitals() -> void:
	var vt: Variant = sheet.get("vitals", {})
	if not (vt is Dictionary) or (vt as Dictionary).is_empty():
		vitals_label.text = ""
		return
	vitals_label.text = "氣 %d/%d　精 %d/%d　內力 %d/%d" % [UiBuild.num(vt.get("qi", 0)), UiBuild.num(vt.get("qi_max", 0)),
		UiBuild.num(vt.get("jing", 0)), UiBuild.num(vt.get("jing_max", 0)), UiBuild.num(vt.get("neili", 0)), UiBuild.num(vt.get("neili_max", 0))]

func _apply_allies() -> void:
	var allies: Array = state.get("allies", []) if state.get("allies") is Array else []
	for i in ally_rows.size():
		var r: Dictionary = ally_rows[i]
		var box: Control = r["box"]
		var nm: Label = r["name"]
		var bar: ProgressBar = r["bar"]
		var st: Label = r["status"]
		var holder: Control = r["thumb_holder"]
		if i >= allies.size() or not (allies[i] is Dictionary):
			nm.text = "（空）"
			UiBuild.muted(nm)
			bar.visible = false
			st.text = ""
			box.modulate = Color(1, 1, 1, 0.6)
			UiBuild.clear(holder)
			r["ref"] = "~"
			continue
		var a: Dictionary = allies[i]
		var alive := bool(a.get("alive", true))
		nm.theme_type_variation = ""
		var rar := str(a.get("rarity", ""))
		nm.text = str(a.get("name", ""))
		if rar != "":
			nm.text = "〔%s〕%s" % [RogueCard.rarity_name(rar), nm.text]
		bar.visible = alive
		UiBuild.set_bar(bar, clampf(float(a.get("qi_pct", 1.0)), 0.0, 1.0) * 100.0, 100.0)
		st.text = "氣 %d%%" % roundi(clampf(float(a.get("qi_pct", 1.0)), 0.0, 1.0) * 100.0) if alive else "已殞"
		box.modulate = Color(1, 1, 1, 1) if alive else Color(0.55, 0.55, 0.55, 0.85)
		var ref := str(a.get("ref", ""))
		if str(r["ref"]) != ref:
			UiBuild.clear(holder)
			holder.add_child(RogueCard.make_portrait(ref, THUMB))
			r["ref"] = ref

## 某位隊友是否已殞（測試用）
func ally_status(i: int) -> String:
	return (ally_rows[i]["status"] as Label).text if i < ally_rows.size() else ""

func _apply_gear() -> void:
	UiBuild.clear(gear_box)
	equip_buttons = {}
	for w in weapons():
		if not (w is Dictionary):
			continue
		var uid := str(w.get("uid", ""))
		var equipped := bool(w.get("equipped", false))
		var parent: Node = gear_box
		if equipped:
			var fr := UiBuild.framed(gear_box, UiFrame.Kind.PLATE)
			fr.name = "Equipped_" + uid
			parent = fr
		var row := UiBuild.hbox(parent, 4)
		var rar := str(UiClient.row("items", str(w.get("item_id", ""))).get("rarity", "COMMON"))
		var wt := str(w.get("weapon_type", ""))
		var t := "%s（%s・攻 %d）" % [str(w.get("name", "")), str(LootUi.WEAPON_NAMES.get(wt, wt)), UiBuild.num(w.get("atk", 0))]
		var l := UiBuild.label(row, t, 14, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_color_override("font_color", LootUi.rarity_color(rar))
		if not equipped and uid != "":
			var b := UiBuild.button(row, "裝備", func(): equip_requested.emit(uid))
			b.name = "Equip_" + uid
			equip_buttons[uid] = b
	var gear: Variant = state.get("gear", {})
	if gear is Dictionary:
		var slots: Array = (gear as Dictionary).keys()
		slots.sort()
		for slot in slots:
			if str(slot) == "WEAPON" or not (gear[slot] is Dictionary):
				continue
			var g: Dictionary = gear[slot]
			var fr2 := UiBuild.framed(gear_box, UiFrame.Kind.PLATE)
			var l2 := UiBuild.label(fr2, "%s：%s" % [str(LootUi.SLOT_NAMES.get(str(slot), str(slot))), str(g.get("name", ""))], 14)
			l2.add_theme_color_override("font_color", LootUi.rarity_color(g.get("rarity", "COMMON")))

func _apply_arts() -> void:
	UiBuild.clear(arts_box)
	art_rows = {}
	var wt := current_weapon_type()
	var list := arts()
	if list.is_empty():
		UiBuild.muted(UiBuild.label(arts_box, "（還沒有武功）", 14))
		return
	for a in list:
		if not (a is Dictionary):
			continue
		var cat := str(a.get("category", ""))
		var t := "%s　%d 級" % [str(a.get("name", a.get("id", ""))), UiBuild.num(a.get("level", 0))]
		if cat != "":
			t += "　" + category_name(cat)
		var l := UiBuild.label(arts_box, t, 14)
		if not art_fits(cat, wt):
			UiBuild.muted(l)
			l.tooltip_text = "與目前的兵器不合"
			l.mouse_filter = Control.MOUSE_FILTER_PASS
		art_rows[str(a.get("id", ""))] = l
