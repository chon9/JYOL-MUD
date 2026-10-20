class_name SkillsPanel
extends VBoxContainer
## 武功窗（Ctrl+1，AUTHENTIC_UI_SPEC §8.3）：一本攤開的武功秘笈。
## - 左頁：人形墨線剪影（自己的立繪染成墨色），下面是武功等級上限、學點；
## - 右頁：武功清單「少林長拳 3級」＋熟練度細條；使用中的武功紅字紅框；點一列選取；
## - 右緣直排書籤（全、內、輕、拳、掌、指、劍、刀、棍、杖、閃、格、生），依 martial_arts 的 category 分類；
## - 頁腳：特殊武功 n/16、選取中武功的 自修 ×1／×5／×10（生活技能靠動作練習，不能自修）。

const STUDY_TIMES := [1, 5, 10]
const BOOKMARKS := ["全", "內", "輕", "拳", "掌", "指", "劍", "刀", "棍", "杖", "閃", "格", "生"]
const CATEGORY_MARK := {
	"INNER": "內", "LIGHTNESS": "輕", "DODGE": "閃", "FIST": "拳", "PALM": "掌", "FINGER": "指",
	"SWORD": "劍", "BLADE": "刀", "STICK": "棍", "STAFF": "杖", "PARRY": "格",
}
const MARK_NAMES := {
	"全": "全部", "內": "內功", "輕": "輕功", "拳": "拳法", "掌": "掌法", "指": "指法", "劍": "劍法", "刀": "刀法",
	"棍": "棍法", "杖": "杖法", "閃": "閃躲", "格": "招架", "生": "生活技能",
}
const INK_SILHOUETTE := Color(0.17, 0.15, 0.13, 0.8)

var gate: IntentGate
var feedback: PanelFeedback
var cap_label: Label
var lp_label: Label
var footer_label: Label
var selected_label: Label
var list: VBoxContainer
var figure: TextureRect
var marks_box: VBoxContainer
var mark_buttons: Dictionary = {}     # 書籤字 -> Button
var study_buttons: Array = []
var current_mark := "全"
var selected_id := ""
var sheet: Dictionary = {}
var _built := false

func _ready() -> void:
	if not _built:
		_build()

func _gate() -> IntentGate:
	if gate == null:
		gate = IntentGate.new()
		add_child(gate)
	return gate

## 面板動作的結果回饋（失敗原因、成功訊息）；主畫面會塞共用的回饋列，單獨使用時自己建一個
func _fb() -> PanelFeedback:
	if feedback == null or not is_instance_valid(feedback):
		feedback = PanelFeedback.new()
		add_child(feedback)
	return feedback

func _send(kind: String, args: Dictionary, lock: Array = []) -> int:
	var fb := _fb()
	fb.begin()
	return _gate().send(kind, args, lock, func(ok: bool, reason: String):
		if is_instance_valid(fb):
			fb.show_result(ok, reason))

func _build() -> void:
	_built = true
	add_theme_constant_override("separation", 6)
	var row := UiBuild.hbox(self, 0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 書本
	var book := PanelContainer.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = UiTheme.JY_PARCHMENT
	paper.border_color = Color("6e5a3a")
	paper.set_border_width_all(2)
	paper.set_content_margin_all(10)
	book.add_theme_stylebox_override("panel", paper)
	book.theme = UiTheme.paper()
	book.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(book)
	var pages := UiBuild.hbox(book, 0)
	var left := UiBuild.vbox(pages, 4)
	left.custom_minimum_size = Vector2(190, 0)
	figure = TextureRect.new()
	figure.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	figure.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	figure.custom_minimum_size = Vector2(180, 220)
	figure.modulate = INK_SILHOUETTE
	figure.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(figure)
	cap_label = UiBuild.label(left, "", 14, true)
	lp_label = UiBuild.muted(UiBuild.label(left, "", 14, true))
	# 中縫陰影
	var spine := Spine.new()
	pages.add_child(spine)
	var right := UiBuild.vbox(pages, 4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc := UiBuild.scroll(right, 300)
	list = UiBuild.vbox(sc, 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 書籤
	marks_box = UiBuild.vbox(row, 2)
	for m in BOOKMARKS:
		var b := UiBuild.button(marks_box, m, set_mark.bind(m))
		b.custom_minimum_size = Vector2(26, 26)
		b.add_theme_font_size_override("font_size", 14)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = MARK_NAMES.get(m, m)
		mark_buttons[m] = b
	# 頁腳
	var foot := UiBuild.hbox(self, 8)
	footer_label = UiBuild.accent(UiBuild.label(foot, "", 15))
	selected_label = UiBuild.label(foot, "", 15)
	selected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiBuild.muted(UiBuild.label(foot, "自修", 14))
	for times in STUDY_TIMES:
		var b := UiBuild.button(foot, "×%d" % times)
		b.pressed.connect(_on_study_selected.bind(times, b))
		study_buttons.append(b)

func set_mark(m: String) -> void:
	current_mark = m
	_rebuild()

static func mark_of(sk: Dictionary) -> String:
	if str(sk.get("kind", "")) == "LIFE":
		return "生"
	return str(CATEGORY_MARK.get(str(sk.get("category", "")), ""))

func apply_sheet(s: Dictionary) -> void:
	if not _built:
		_build()
	sheet = s
	cap_label.text = "武功等級上限（實戰）：%d" % UiBuild.num(s.get("art_level_cap", 0))
	lp_label.text = "學點 %d" % UiBuild.num(s.get("learn_points", 0))
	footer_label.text = "特殊武功 %d/%d" % [UiBuild.num(s.get("special_arts", 0)), UiBuild.num(s.get("special_arts_max", UiKeys.SPECIAL_ARTS_MAX))]
	var look := str(s.get("look", ""))
	if look == "":
		look = "player_" + str(s.get("gender", "m")).to_lower()
	figure.texture = ArtRegistry.unit_texture(look, "PLAYER", "idle")
	if figure.texture == null:
		figure.texture = ArtRegistry.unit_texture("player_m", "PLAYER", "idle")
	# 預設選第一門能自修的武功
	if _find(selected_id).is_empty() or str(_find(selected_id).get("kind", "")) == "LIFE":
		selected_id = ""
		for sk in s.get("skills", []):
			if sk is Dictionary and str(sk.get("kind", "")) != "LIFE":
				selected_id = str(sk.get("id", ""))
				break
	_rebuild()

func _find(id: String) -> Dictionary:
	for sk in sheet.get("skills", []):
		if sk is Dictionary and str(sk.get("id", "")) == id:
			return sk
	return {}

func skills_for_mark(m: String) -> Array:
	var out: Array = []
	for sk in sheet.get("skills", []):
		if not (sk is Dictionary):
			continue
		if m == "全" or SkillsPanel.mark_of(sk) == m:
			out.append(sk)
	return out

func _rebuild() -> void:
	if not _built:
		return
	for m in mark_buttons:
		var b: Button = mark_buttons[m]
		var has: bool = m == "全" or not skills_for_mark(m).is_empty()
		b.modulate = Color(1, 1, 1, 1.0 if has else 0.45)
		b.add_theme_color_override("font_color", UiTheme.CINNABAR if m == current_mark else UiTheme.JY_BTN_TEXT)
	UiBuild.clear(list)
	var items := skills_for_mark(current_mark)
	if items.is_empty():
		UiBuild.muted(UiBuild.label(list, "（尚未學會）", 15))
	for sk in items:
		_skill_row(sk)
	var sel := _find(selected_id)
	var can := not sel.is_empty() and str(sel.get("kind", "")) != "LIFE"
	selected_label.text = ("選取：%s" % str(sel.get("name", ""))) if can else "（點選一門武功）"
	for b in study_buttons:
		(b as Button).disabled = not can

func _skill_row(sk: Dictionary) -> void:
	var id := str(sk.get("id", ""))
	var box := PanelContainer.new()
	var active := bool(sk.get("active", sk.get("enabled", false)))
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0) if id != selected_id else Color(0.78, 0.6, 0.31, 0.25)
	st.border_color = UiTheme.CINNABAR if active else Color(0, 0, 0, 0)
	st.set_border_width_all(1 if active else 0)
	st.set_content_margin_all(3)
	box.add_theme_stylebox_override("panel", st)
	list.add_child(box)
	var v := UiBuild.vbox(box, 1)
	var b := UiBuild.button(v, "%s　%d級" % [str(sk.get("name", id)), UiBuild.num(sk.get("level", 0))], func():
		selected_id = id
		_rebuild())
	b.theme_type_variation = "ChoiceButton"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 16)
	if active:
		b.add_theme_color_override("font_color", UiTheme.CINNABAR)
	var kind := str(sk.get("kind", ""))
	b.tooltip_text = UiKeys.SKILL_KIND_LABELS.get(kind, kind)
	var prof := UiBuild.num(sk.get("prof", 0))
	var next := UiBuild.num(sk.get("next_prof", 0))
	var h := UiBuild.hbox(v, 6)
	var bar := UiBuild.bar(h, Color("8a5a2a"), 180)
	bar.custom_minimum_size = Vector2(180, 5)
	UiBuild.set_bar(bar, prof, next if next > 0 else maxi(1, prof))
	UiBuild.muted(UiBuild.label(h, "%d / %d" % [prof, next] if next > 0 else "%d" % prof, 12))

func _on_study_selected(times: int, b: Button) -> void:
	if selected_id != "":
		_on_study(selected_id, times, b)

func _on_study(skill: String, times: int, b: Button) -> void:
	_send(UiKeys.I_SELF_STUDY, { "skill": skill, "times": times }, [b])

## 書本中縫：8 px 暗色陰影
class Spine extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(12, 0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, size.y), Vector2(0, size.y)]),
			PackedColorArray([Color(0, 0, 0, 0), Color(0.2, 0.12, 0.05, 0.45), Color(0.2, 0.12, 0.05, 0.45), Color(0, 0, 0, 0)]))
		draw_line(Vector2(w / 2.0, 0), Vector2(w / 2.0, size.y), Color(0.3, 0.2, 0.1, 0.6), 1.0)
