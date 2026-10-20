class_name NumberedDialog
extends UiDialog
## M3b 新視窗共用的基底（M3B_PLAN §7「新視窗都能用 Esc 關、數字鍵選」）：
## - Esc 由主畫面關（_close_dialogs 走 _dialogs() 清單）；
## - 數字鍵 1–9 依序按下 choices 裡第 n 顆可按的按鈕（正在輸入框打字時不攔截）。
## 子類別在重建清單時呼叫 clear_choices()／add_choice(b)，並可在按鈕前面放「1.」編號（numbered_label）。

var choices: Array = []          # 依編號順序的 BaseButton

func clear_choices() -> void:
	choices.clear()

func add_choice(b: BaseButton) -> BaseButton:
	choices.append(b)
	return b

## 第 i 個（0 起算）可選的項目；不存在回 null
func choice_at(i: int) -> BaseButton:
	var live := choices.filter(func(c): return is_instance_valid(c) and not (c as Node).is_queued_for_deletion())
	if i < 0 or i >= live.size():
		return null
	return live[i]

## 數字鍵 n（1 起算）→ 按下對應的項目；回傳是否處理
func press_number(n: int) -> bool:
	var b := choice_at(n - 1)
	if b == null or b.disabled:
		return false
	if b is Button and (b as Button).toggle_mode:
		(b as Button).button_pressed = true
	b.pressed.emit()
	return true

## 下一幀再把焦點給 c（那時 c 可能已經被清掉：先檢查還在樹上）
static func focus_later(c: Control) -> void:
	var f := func():
		if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree():
			c.grab_focus()
	f.call_deferred()

## 「1.」編號標籤（跟 NPC 選單同樣的黃色數字）
static func numbered_label(parent: Node, n: int) -> Label:
	var num := UiBuild.accent(UiBuild.label(parent, "%d." % n if n <= 9 else "　", 16))
	num.custom_minimum_size = Vector2(22, 0)
	return num

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f is LineEdit or f is TextEdit or f is SpinBox:
		return
	var n := int(k.keycode) - int(KEY_0)
	if n < 1 or n > 9:
		return
	if press_number(n):
		get_viewport().set_input_as_handled()
