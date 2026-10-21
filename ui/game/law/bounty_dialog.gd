class_name BountyDialog
extends NumberedDialog
## 衙門懸賞名單（M3D_PLAN §2.2、§2.4、§7；WP-LAW）：收到 bounty_board（ui）開啟。
## 名單（名字、門派、PK值、善惡、懸賞金額＝罰金＋加碼、上榜時間）＋每列「加碼」（bounty_add）＋底部「領賞」（只在官爺處，bounty_claim）。
## 名單每遊戲時辰統計一次（不是即時）；bounty_enabled 關 → 只顯示「衙門暫停懸賞」。數字鍵 1–9 依序按「加碼」。

const TITLE := "懸賞名單"
const OFF_TEXT := "衙門暫停懸賞。"
const EMPTY_TEXT := "名單上目前沒有人。江湖太平。"
const NOTE_TEXT := "名單每個時辰統計一次；持照的賞金獵人緝拿名單上的人不算惡意 PK。懸賞金由被懸賞者自己的錢支付，加上江湖朋友的加碼。"
const COLS := ["姓名", "門派", "PK值", "善惡", "懸賞（兩）", "上榜"]
## M3d 審查：表頭固定在捲動框外面（長名單捲動時不會捲走）→ 表頭與名單是兩個 GridContainer，用固定欄寬對齊
const COL_W := [120, 92, 48, 56, 96, 112, 64]
const ROW_H := 32.0
const SCROLL_MAX_H := 220.0
const SELF_ADD_TIP := "不能替自己加碼"
const NO_CLAIM_TIP := "你沒有可以領的賞金"
## M3d 審查第三輪：自己那一列的加碼鈕灰掉時，按鈕上直接寫「（自己）」，名單下方再寫一行原因（原本只有滑鼠提示）
const SELF_ADD_TEXT := "自己"

var payload: Dictionary = {}
var npc := ""
var head_label: Label
var table: GridContainer
var head_table: GridContainer
var table_scroll: ScrollContainer
var add_box: VBoxContainer
var footer: HBoxContainer
var claim_button: Button

func dialog_size() -> Vector2:
	return Vector2(640, 0)

func _build_body() -> void:
	title_label.text = TITLE
	head_label = UiBuild.label(body, "", 15, true)
	head_label.name = "BoardHead"
	head_table = GridContainer.new()
	head_table.name = "BoardHeader"
	head_table.columns = COLS.size() + 1
	head_table.add_theme_constant_override("h_separation", 14)
	body.add_child(head_table)
	var sc := UiBuild.scroll(body, SCROLL_MAX_H)
	sc.name = "BoardScroll"
	table_scroll = sc
	table = GridContainer.new()
	table.name = "BoardTable"
	table.columns = COLS.size() + 1
	table.add_theme_constant_override("h_separation", 14)
	table.add_theme_constant_override("v_separation", 4)
	sc.add_child(table)
	add_box = UiBuild.vbox(body, 6)
	add_box.name = "AddBox"
	UiBuild.muted(UiBuild.label(body, NOTE_TEXT, 13, true))
	footer = UiBuild.hbox(body, 8)
	footer.name = "BoardFooter"

## p = bounty_board 事件（§7）＋ npc（主機附上的 NPC id）
func open_board(p: Dictionary) -> void:
	ensure_built()
	payload = p
	npc = str(p.get("npc", npc))
	status_label.text = ""
	visible = true
	_render()

## 純文字列（測試與截圖檢查用）：「名字　門派　PK　善惡　金額　時間」
static func row_text(r: Dictionary) -> PackedStringArray:
	return PackedStringArray([str(r.get("name", "")), str(r.get("sect_name", "")), str(UiBuild.num(r.get("pk", 0))),
		str(UiBuild.num(r.get("morality", 0))), BountyDialog.money_text(UiBuild.num(r.get("amount", 0))),
		str(r.get("listed_text", ""))])

## 名單捲動框的高度：跟著列數（每列約 ROW_H），最多 SCROLL_MAX_H（M3d 審查：一兩列時不留 170 px 空白）
static func board_height(n_rows: int) -> float:
	return clampf(n_rows * ROW_H + 6.0, ROW_H + 6.0, SCROLL_MAX_H)

## 這一列能不能加碼：自己那一列不行（"" ＝可以）
static func add_block(r: Dictionary) -> String:
	return SELF_ADD_TIP if r.get("self", false) == true else ""

static func _fix_w(c: Control, col: int) -> void:
	c.custom_minimum_size.x = float(COL_W[clampi(col, 0, COL_W.size() - 1)])

static func money_text(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## 表頭文字：統計時間、執照、可領賞金
static func head_text(p: Dictionary) -> String:
	if p.get("enabled", true) == false:
		return OFF_TEXT
	var parts: PackedStringArray = []
	var t := str(p.get("refreshed_text", ""))
	if t != "":
		parts.append("統計時間：%s" % t)
	parts.append("你%s賞金獵人執照" % ("持有" if p.get("licensed", false) == true else "沒有"))
	var c := UiBuild.num(p.get("claims_total", 0))
	if c > 0:
		parts.append("待領賞金 %s 兩" % BountyDialog.money_text(c))
	return "　".join(parts)

func _render() -> void:
	head_label.text = BountyDialog.head_text(payload)
	UiBuild.clear(table)
	UiBuild.clear(head_table)
	UiBuild.clear(add_box)
	UiBuild.clear(footer)
	clear_choices()
	var on: bool = payload.get("enabled", true) != false
	table.visible = on
	if on:
		for k in COLS.size():
			BountyDialog._fix_w(UiBuild.accent(UiBuild.label(head_table, COLS[k], 15)), k)
		BountyDialog._fix_w(UiBuild.label(head_table, "", 15), COLS.size())
		var rows: Array = payload.get("rows", []) if payload.get("rows") is Array else []
		var i := 0
		var self_row := false
		for r in rows:
			if not (r is Dictionary):
				continue
			i += 1
			var cells := BountyDialog.row_text(r)
			for j in cells.size():
				var l := UiBuild.label(table, cells[j], 15)
				l.name = "Cell_%d_%d" % [i, j]
				BountyDialog._fix_w(l, j)
				l.clip_text = true
				l.tooltip_text = cells[j]
				if j == 4:
					l.add_theme_color_override("font_color", UiTheme.JY_SYS_YELLOW)
				if j == 3 and UiBuild.num(r.get("morality", 0)) <= BountyRules.LIST_EVIL_MORALITY:
					l.add_theme_color_override("font_color", Color("6fa8ff"))
			var nm := str(r.get("name", ""))
			var blk := BountyDialog.add_block(r)
			var b := UiBuild.button(table, "加碼" if blk == "" else SELF_ADD_TEXT, func(): show_add(nm), 64)
			b.name = "Add_%d" % i
			if blk != "":
				self_row = true
			b.disabled = blk != ""
			b.tooltip_text = blk if blk != "" else \
				"在%s的懸賞上加碼（至少 %d 兩，錢從你身上出、不能取回）" % [nm, UiBuild.num(payload.get("pool_min", 100))]
			if blk == "":
				add_choice(b)
		if i == 0:
			table.visible = false
			UiBuild.muted(UiBuild.label(add_box, EMPTY_TEXT, 15))
		elif self_row:
			var sl := UiBuild.muted(UiBuild.label(add_box, "你自己也在名單上：%s。" % SELF_ADD_TIP, 13, true))
			sl.name = "SelfAddWhy"
		table_scroll.custom_minimum_size = Vector2(0, BountyDialog.board_height(i))
		table_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# M3d 審查：名單空的（或暫停）時連捲動框與表頭一起收起，不留一大塊空白
	table_scroll.visible = table.visible
	head_table.visible = table.visible
	# 領賞：只有官爺（LICENSE）處才有；佈告欄只能看名單、加碼
	if str(payload.get("npc_service", "")) == "LICENSE":
		var c := UiBuild.num(payload.get("claims_total", 0))
		claim_button = UiBuild.button(footer, "領賞（%s 兩）" % BountyDialog.money_text(c), _claim, 150)
		claim_button.name = "ClaimButton"
		claim_button.disabled = c <= 0
		if c <= 0:
			claim_button.tooltip_text = NO_CLAIM_TIP
			var cl := UiBuild.muted(UiBuild.label(footer, NO_CLAIM_TIP, 13))
			cl.name = "ClaimWhy"
	UiBuild.button(footer, "關閉", close, 90)

func show_add(target: String) -> void:
	UiBuild.clear(add_box)
	var row := UiBuild.hbox(add_box, 8)
	UiBuild.label(row, "加碼給%s：" % target, 15)
	var le := UiBuild.line_edit(row, str(UiBuild.num(payload.get("pool_min", 100))), "銀兩", 7)
	le.name = "AddMoney"
	le.custom_minimum_size = Vector2(110, 0)
	UiBuild.label(row, "兩", 15)
	var ok := UiBuild.button(row, "確定加碼", Callable(), 100)
	ok.name = "AddOk"
	ok.pressed.connect(func():
		var m := int(le.text.strip_edges()) if le.text.strip_edges().is_valid_int() else 0
		if m <= 0:
			status_label.text = "請輸入加碼的銀兩。"
			return
		send(UiKeys.I_BOUNTY_ADD, { "npc": npc, "target_name": target, "money": m }, [ok], func(): UiBuild.clear(add_box)))
	UiBuild.button(row, "取消", func(): UiBuild.clear(add_box), 70)
	NumberedDialog.focus_later(le)

func _claim() -> void:
	send(UiKeys.I_BOUNTY_CLAIM, { "npc": npc }, [claim_button], func():
		payload["claims_total"] = 0
		_render())
