class_name LookDialog
extends UiDialog
## 更換造型（M3C_PLAN §3.4 第 3 點）：屬性視窗「更換造型」開這個視窗。LookPicker（依自己的性別）＋「確定／取消」；
## 確定 → set_look { look }（免費、純外觀；主機驗證範圍）。拜入門派期間一律穿門派服裝（O2）→ 顯示提示。
## 主畫面的對話框層只有 552 高（HUD 上方），選擇器用 5 欄×2 列，每格立繪仍 ≥ 150×150。

const SECT_HINT := "拜入門派期間一律穿門派服裝；離開門派後換回這裡選的造型。"   # M3c 第二輪審查：以前寫「戰鬥中」，與屬性窗不符
const DIALOG_COLS := 5

var picker: LookPicker
var current_label: Label
var hint_label: Label
var btn_ok: Button
var btn_cancel: Button
var current := 0          # 開啟時的 appearance

func frame_kind() -> int:
	return UiFrame.Kind.JADE

func dialog_size() -> Vector2:
	return Vector2(860, 0)

func _build_body() -> void:
	title_label.text = "更換造型"
	var info := UiBuild.hbox(body, 16)
	current_label = UiBuild.label(info, "", 16)
	UiBuild.accent(current_label)
	hint_label = UiBuild.muted(UiBuild.label(info, "", 15, true))
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var center := CenterContainer.new()
	body.add_child(center)
	picker = LookPicker.new()
	picker.set_columns(DIALOG_COLS)
	picker.set_cell_size(Vector2(162, 188))
	center.add_child(picker)
	picker.look_selected.connect(func(_i: int): _sync())
	var row := UiBuild.hbox(body, 10)
	var note := UiBuild.muted(UiBuild.label(row, "純外觀、不花錢，隨時可以再換（戰鬥中不行）。", 15))
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_ok = UiBuild.button(row, "確定", confirm, 100)
	btn_cancel = UiBuild.button(row, "取消", close, 100)

## 依角色表開啟：性別、目前造型（appearance；舊主機沒有 → 0）、入派提示
func open_for(sheet: Dictionary) -> void:
	ensure_built()
	status_label.text = ""
	current = UiBuild.num(sheet.get("appearance", 0))
	if not Looks.valid(current):
		current = 0
	picker.set_gender(str(sheet.get("gender", "M")))
	picker.set_selected(current)
	hint_label.text = SECT_HINT if str(sheet.get("sect", "")) != "" else ""
	_sync()
	visible = true
	picker.grab_focus.call_deferred()

func _sync() -> void:
	var g := picker.gender
	current_label.text = "目前：%s　→　%s" % [Looks.name_of(g, current), Looks.name_of(g, picker.selected)]
	btn_ok.text = "確定" if picker.selected != current else "關閉"

## 送出的 intent（測試用）
func build_args() -> Dictionary:
	return { "look": picker.selected }

func confirm() -> void:
	if picker.selected == current:
		close()
		return
	send(UiKeys.I_SET_LOOK, build_args(), [btn_ok], func():
		current = picker.selected
		close())
