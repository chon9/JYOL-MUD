class_name HotbarSlot
extends JyButton
## 熱鍵列的一格：接受指令窗／裝備窗拖來的東西；格子之間互拖交換；拖出熱鍵列外清掉。

var bar: Hotbar
var row := 0
var index := 0
var _drag_from_me := false
var state_sig: Array = []          # Hotbar._update_states 上次套用的狀態（變了才重組文字與提示框）

func _init() -> void:
	super(JyButton.Style.SLOT, "", "")

func _get_drag_data(at: Vector2) -> Variant:
	var d: Variant = super(at)
	if d != null:
		_drag_from_me = true
	return d

func _gui_input(event: InputEvent) -> void:
	var was := drag_payload
	super(event)
	if was != "" and get_viewport() != null and get_viewport().gui_is_dragging():
		_drag_from_me = true

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and bar != null and Hotbar.accepts(row, str((data as Dictionary).get("jy_hotbar", "")))

func _drop_data(_at: Vector2, data: Variant) -> void:
	var payload := str((data as Dictionary).get("jy_hotbar", ""))
	var src: Variant = (data as Dictionary).get("source", null)
	if src is HotbarSlot and src != self and (src as HotbarSlot).row == row:
		# 熱鍵格之間：交換
		var mine := bar.payload_at(row, index)
		(src as HotbarSlot)._drag_from_me = false
		bar.set_payload(row, (src as HotbarSlot).index, mine)
	bar.set_payload(row, index, payload)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drag_from_me:
		_drag_from_me = false
		if bar != null and not get_viewport().gui_is_drag_successful():
			bar.set_payload(row, index, "")   # 拖到熱鍵列外：清掉這一格
