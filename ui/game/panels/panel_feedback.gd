class_name PanelFeedback
extends VBoxContainer
## 面板回饋列（UI 稽核 round 2）：860×480 的面板幾乎蓋住訊息紀錄，面板裡的動作（自修、使用、裝備、卸下、丟棄、放棄任務）
## 成功或失敗都要在面板內看得到。
## - status_label：最近一次面板動作失敗的原因（intent_result 的 reason，介面內嵌版，不帶頻道標籤）。
## - feed_label：面板開著時收到的系統頻道訊息（主機在成功時送的「你自修了……」「你裝備了……」），最多 FEED_LINES 行。
## 面板開啟時 reset()；送出新動作時 begin()。

const FEED_LINES := 3

var status_label: Label
var feed_label: Label
var _lines: PackedStringArray = []
var _built := false

func _ready() -> void:
	ensure_built()
	UiClient.connect_signal("events_received", _on_events)

func _exit_tree() -> void:
	UiClient.disconnect_signal("events_received", _on_events)

func ensure_built() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 2)
	add_child(HSeparator.new())
	# AUTHENTIC_UI_SPEC §14：回饋列是黃字（成功訊息），失敗原因紅字
	feed_label = UiBuild.label(self, "", 15, true)
	feed_label.add_theme_color_override("font_color", UiTheme.JY_LABEL)
	status_label = UiBuild.error(UiBuild.label(self, "", 15, true))

func reset() -> void:
	ensure_built()
	_lines = PackedStringArray()
	feed_label.text = ""
	status_label.text = ""

## 送出新的面板動作：清掉上一次的失敗原因
func begin() -> void:
	ensure_built()
	status_label.text = ""

func show_result(ok: bool, reason: String) -> void:
	ensure_built()
	status_label.text = "" if ok else UiClient.reason_inline(reason)

func add_line(t: String) -> void:
	ensure_built()
	if t == "":
		return
	_lines.append(t)
	while _lines.size() > FEED_LINES:
		_lines.remove_at(0)
	feed_label.text = "\n".join(_lines)

## 只收系統頻道（自修、使用、裝備……都在 SYSTEM）；面板沒開時不收
func add_event(e: Dictionary) -> void:
	if str(e.get("ch", "")) != UiKeys.CH_SYSTEM or MessageLog.is_quiet_system(e):
		return
	add_line(TextRenderer.strip_channel_tag(TextRenderer.render_plain(e, UiClient.my_peer(), UiClient.templates())))

func _on_events(batch: Array) -> void:
	if not is_visible_in_tree():
		return
	for e in batch:
		if e is Dictionary:
			add_event(e)
