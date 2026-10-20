class_name CorpseDialog
extends UiDialog
## 屍體撿取視窗（M2_PLAN 4.10、4.5.2、5.3）：點場景卷軸的屍體打開。
## - 物品清單（view.corpses[].items，可撿時才有）：每件「拿走」（loot_corpse 帶 item_uid）、「全部拿走」（不帶 item_uid）。
## - 保護期倒數（left_s，真實秒數，本機倒數）；保護期內不是本人也沒被授權 → 只顯示原因，不能撿。
## - 自己的屍體：「允許某人翻動」輸入角色名 → corpse_authorize（最多 4 人，主機判定）。
## 房間更新時主畫面呼叫 refresh_from_view()：屍體不見了（撿光、過期、離開房間）就關掉。
## M2 審查：不能撿時不另放佔位文字（info_label 已說明保護期），物品區與「全部拿走」都藏起來；物品區的高度跟著件數；
## 自己的屍體列出已允許的人（view 的 authorized_names／auth_max，只給擁有者）。

var corpse: Dictionary = {}
var info_label: Label
var items_box: VBoxContainer
var items_scroll: ScrollContainer
var take_all_button: Button
var auth_list_label: Label
var auth_row: HBoxContainer
var auth_edit: LineEdit
var auth_button: Button
const ITEM_ROW_H := 34.0
const ITEMS_MAX_H := 160.0
var _rx_ms := 0
var _shown_left := -1

func frame_kind() -> int:
	return UiFrame.Kind.SCROLL

func dialog_size() -> Vector2:
	return Vector2(520, 0)

func _build_body() -> void:
	info_label = UiBuild.label(body, "", 15, true)
	items_scroll = UiBuild.scroll(body, ITEM_ROW_H)
	items_scroll.size_flags_vertical = Control.SIZE_FILL
	items_box = UiBuild.vbox(items_scroll, 4)
	items_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take_all_button = UiBuild.button(body, "全部拿走", take_all, 140)
	take_all_button.name = "TakeAll"
	take_all_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	auth_list_label = UiBuild.muted(UiBuild.label(body, "", 14, true))
	auth_list_label.name = "AuthList"
	auth_row = UiBuild.hbox(body, 6)
	# 「讓這人翻動：[名字] [允許]」：按鈕就是送出輸入的名字（M2 第三輪審查：「翻動我的屍體」看起來像另一個動作）
	UiBuild.label(auth_row, "讓這人翻動：", 15)
	auth_edit = UiBuild.line_edit(auth_row, "", "角色名字", UiKeys.NAME_MAX_LEN * 2)
	auth_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auth_edit.text_submitted.connect(func(_t): authorize(auth_edit.text))
	auth_button = UiBuild.button(auth_row, "允許", func(): authorize(auth_edit.text), 72)
	auth_button.name = "AuthorizeButton"

func corpse_id() -> String:
	return str(corpse.get("id", ""))

func open_corpse(c: Dictionary) -> void:
	ensure_built()
	status_label.text = ""
	auth_edit.text = ""
	_apply(c)
	visible = true

## 房間更新：同一具屍體換成新資料；不在了就關掉
func refresh_from_view(view: Dictionary) -> void:
	if not visible or corpse.is_empty():
		return
	var c := UiSocial.find_corpse(view, corpse_id())
	if c.is_empty():
		close()
		return
	_apply(c)

func _apply(c: Dictionary) -> void:
	corpse = c
	_rx_ms = Time.get_ticks_msec()
	_shown_left = -1
	title_label.text = "%s的屍體" % str(c.get("owner_name", "?"))
	UiBuild.clear(items_box)
	var can := can_loot()
	var items: Array = c.get("items", []) if c.get("items", []) is Array else []
	var rows := 0
	if can:
		for it in items:
			if not (it is Dictionary):
				continue
			var row := UiBuild.hbox(items_box, 8)
			var l := UiBuild.label(row, "%s ×%d" % [str(it.get("name", it.get("id", "?"))), maxi(1, UiBuild.num(it.get("n", 1)))], 16)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var b := UiBuild.button(row, "拿走", Callable(), 72)
			b.pressed.connect(take_one.bind(str(it.get("uid", "")), b))
			rows += 1
		if items_box.get_child_count() == 0:
			UiBuild.muted(UiBuild.label(items_box, "（屍體上沒有東西了）", 15))
			rows = 1
	# 不能撿：原因已經在 info_label（保護期倒數），不再重複一次
	items_scroll.visible = can
	items_scroll.custom_minimum_size = Vector2(0, clampf(rows * ITEM_ROW_H, ITEM_ROW_H, ITEMS_MAX_H))
	take_all_button.disabled = not can or items.is_empty()
	take_all_button.visible = can and not items.is_empty()
	var mine := bool(c.get("mine", false))
	auth_row.visible = mine
	auth_list_label.visible = mine
	if mine:
		auth_list_label.text = auth_list_text(c)
	_update_info()

## 自己的屍體：已允許誰（最多 auth_max 人）
static func auth_list_text(c: Dictionary) -> String:
	var names: Array = c.get("authorized_names", []) if c.get("authorized_names", []) is Array else []
	var maxn := UiBuild.num(c.get("auth_max", 4))
	if names.is_empty():
		return "還沒有允許任何人翻動（最多 %d 人）。" % maxn
	var t := "已允許（%d／%d）：%s" % [names.size(), maxn, "、".join(PackedStringArray(names.map(func(x): return str(x))))]
	if names.size() >= maxn:
		t += "　名額已滿"
	return t

## 現在能不能撿：主機給的 can_loot；舊主機（M1）沒有這個欄位時只有自己的屍體能撿
func can_loot() -> bool:
	if corpse.has("can_loot"):
		return bool(corpse.get("can_loot", false))
	return bool(corpse.get("mine", false))

func left_s() -> int:
	var base := UiBuild.num(corpse.get("left_s", 0))
	return maxi(0, base - (Time.get_ticks_msec() - _rx_ms) / 1000)

func _update_info() -> void:
	var left := left_s()
	_shown_left = left
	var lines: PackedStringArray = []
	if corpse.has("left_s"):
		lines.append(UiSocial.corpse_status(corpse, left))
	if bool(corpse.get("authorized_me", false)) and not bool(corpse.get("mine", false)):
		lines.append("屍體的主人允許你翻動。")
	lines.append("身上共 %d 件物品。" % UiBuild.num(corpse.get("n_items", 0)))
	info_label.text = "\n".join(lines)

func _process(_delta: float) -> void:
	if visible and not corpse.is_empty() and left_s() != _shown_left:
		_update_info()

func take_one(item_uid: String, b: Button = null) -> void:
	if item_uid == "":
		return
	send(UiKeys.I_LOOT_CORPSE, { "corpse_id": corpse_id(), "item_uid": item_uid }, [b] if b != null else [])

func take_all() -> void:
	send(UiKeys.I_LOOT_CORPSE, { "corpse_id": corpse_id() }, [take_all_button])

func authorize(name: String) -> void:
	name = name.strip_edges()
	if name == "":
		status_label.text = "請輸入要允許的角色名字。"
		return
	send(UiKeys.I_CORPSE_AUTHORIZE, { "corpse_id": corpse_id(), "name": name }, [auth_button], func():
		auth_edit.text = ""
		status_label.text = "")
