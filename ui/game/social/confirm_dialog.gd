class_name ConfirmDialog
extends UiDialog
## 確認框（M2_PLAN 4.10：強制 PK「確定要對 X 強行出手？」、伺服器設定的踢人／禁止）。
## open_confirm(title, message, ok_label, on_ok)：按「確定」才呼叫 on_ok（由呼叫端送 intent），按「取消」或關閉什麼都不做。

var message_label: Label
var ok_button: Button
var cancel_button: Button
var _on_ok: Callable = Callable()

func dialog_size() -> Vector2:
	return Vector2(440, 0)

func _build_body() -> void:
	message_label = UiBuild.label(body, "", 17, true)
	var row := UiBuild.hbox(body, 12)
	ok_button = UiBuild.button(row, "確定", confirm, 110)
	ok_button.name = "ConfirmOk"
	cancel_button = UiBuild.button(row, "取消", close, 110)

## danger：後果重大（強行出手：PK值、殺氣、善惡）→ 確定鈕的字染紅。鍵盤焦點一律先放在「取消」，
## 按 Enter／空白鍵不會誤出手（M2 第三輪審查）
func open_confirm(title: String, message: String, ok_label: String, on_ok: Callable, danger := false, cancel_label := "取消") -> void:
	ensure_built()
	title_label.text = title
	message_label.text = message
	ok_button.text = ok_label
	cancel_button.text = cancel_label
	status_label.text = ""
	_on_ok = on_ok
	set_danger(danger)
	visible = true
	cancel_button.grab_focus.call_deferred()

func set_danger(on: bool) -> void:
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		if on:
			ok_button.add_theme_color_override(k, UiTheme.JY_RED)
		else:
			ok_button.remove_theme_color_override(k)

func is_danger() -> bool:
	return ok_button != null and ok_button.has_theme_color_override("font_color")

func confirm() -> void:
	var cb := _on_ok
	_on_ok = Callable()
	close()
	if cb.is_valid():
		cb.call()
