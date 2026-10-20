class_name PassportDialog
extends UiDialog
## 角色護照（M2_PLAN 4.10、4.6.8）：角色選擇畫面「護照」打開。
## 列出本機為這個世界存的護照（SaveManager.list_passports／load_passport），「用護照還原」→ passport_restore { passport }。
## 說明文字照 4.6.8 的誠實說明：簽章只防「沒有主機檔案的人」改護照，不防主機玩家本人；護照是災難復原工具，不是防作弊。

const HONEST_NOTE := "角色護照是主機替你的角色存在本機的備份，只用來在主機的角色檔壞掉或遺失時，把角色還原回同一個世界。\n" \
	+ "護照上的簽章只能發現「沒有主機檔案的人」改過護照；它防不了主機玩家本人、拿到主機存檔的人或改程式的人，" \
	+ "也沒辦法在別的世界驗證。所以它是災難復原工具，不是防作弊。"

var note_label: Label
var list_box: VBoxContainer
var entries: Array = []          # [{ char_id, name, saved_s, data }]

func dialog_size() -> Vector2:
	return Vector2(620, 0)

func _build_body() -> void:
	title_label.text = "角色護照"
	note_label = UiBuild.muted(UiBuild.label(body, HONEST_NOTE, 14, true))
	body.add_child(HSeparator.new())
	var sc := UiBuild.scroll(body, 160)
	list_box = UiBuild.vbox(sc, 6)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func open_list() -> void:
	ensure_built()
	status_label.text = ""
	apply_entries(load_entries(str(UiClient.world_info().get("world_id", ""))))
	visible = true

## 讀本機護照（SaveManager 還沒有這些函式時回空清單）
static func load_entries(world_id: String) -> Array:
	var out: Array = []
	var loop := Engine.get_main_loop() as SceneTree
	var sm: Node = loop.root.get_node_or_null("SaveManager") if loop != null else null
	if sm == null or world_id == "" or not sm.has_method("list_passports") or not sm.has_method("load_passport"):
		return out
	for cid in sm.call("list_passports", world_id):
		var r: Variant = sm.call("load_passport", world_id, str(cid))
		if not (r is Dictionary) or not bool((r as Dictionary).get("ok", false)):
			continue
		var data: Variant = (r as Dictionary).get("data", {})
		if data is Dictionary:
			out.append({ "char_id": str(cid), "name": str((data as Dictionary).get("name", cid)),
				"saved_s": float((data as Dictionary).get("saved_s", 0.0)), "data": data })
	return out

func apply_entries(list: Array) -> void:
	ensure_built()
	entries = list
	UiBuild.clear(list_box)
	for e in list:
		if not (e is Dictionary):
			continue
		var row := UiBuild.hbox(list_box, 10)
		var l := UiBuild.label(row, "%s　（上線 %s）" % [str(e.get("name", "?")), PassportDialog.online_text(float(e.get("saved_s", 0.0)))], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := UiBuild.button(row, "用護照還原", Callable(), 120)
		b.pressed.connect(restore.bind(e, b))
	if list_box.get_child_count() == 0:
		UiBuild.muted(UiBuild.label(list_box, "（這台電腦沒有這個世界的角色護照。主機會在自動存檔、離開世界時把護照送給你。）", 15, true))

## saved_s ＝ 角色累計上線秒數（主機寫入護照時）
static func online_text(secs: float) -> String:
	var s := int(secs)
	return "%d 小時 %d 分" % [s / 3600, (s / 60) % 60]

func restore(e: Dictionary, b: Button = null) -> void:
	var data: Variant = e.get("data", {})
	if not (data is Dictionary):
		return
	send(UiKeys.I_PASSPORT_RESTORE, { "passport": data }, [b] if b != null else [], func():
		status_label.text = "已送出還原；角色清單會更新。")
