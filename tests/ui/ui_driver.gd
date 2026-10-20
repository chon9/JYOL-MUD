extends RefCounted
## 真實介面驅動器（UI driver）：在執行中的遊戲裡，像玩家一樣找控制項、按按鈕、打字、選項目、等條件。
## 只碰 UI（Control 樹、UI 物件自己的屬性）；絕對不呼叫 WorldServer／NetworkManager，
## 這樣才抓得到「主機正確、但介面壞掉」的 bug（例如戰鬥卡在「蓄勢中……」）。
##
## 用法（在 --bot 腳本裡）：
##   const UiDriver := preload("res://tests/ui/ui_driver.gd")
##   var ui := UiDriver.new(get_tree())
##   await ui.click(ui.find_button("進入江湖"))
##
## 點擊預設走真的滑鼠事件（Viewport.push_input，送到控制項中心點），並確認按鈕的 pressed 真的有觸發；
## 被別的控制項擋住時會記錄是誰擋住並回 false（strict_clicks = true）。

var tree: SceneTree
var strict_clicks := true          # 滑鼠點不到按鈕時視為失敗（false 則退回直接 emit pressed 並記警告）
var shots_dir := ""                # --ui-shots=<dir>；空字串 = 不截圖
var shot_index := 0
var shots: PackedStringArray = []  # 已存的截圖完整路徑
var warnings: PackedStringArray = []
var last_error := ""
var verbose := false

var engine_errors: PackedStringArray = []   # 執行期間引擎回報的 SCRIPT ERROR／ERROR（由 ErrorCatcher 收集）
var _catcher: ErrorCatcher = null

## 收集引擎錯誤（Godot 4.5+ 的 Logger）；可能在其他執行緒被呼叫，所以上鎖
class ErrorCatcher extends Logger:
	var lines: PackedStringArray = []
	var mutex := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var kind := "SCRIPT ERROR" if error_type == ERROR_TYPE_SCRIPT else "ERROR"
		mutex.lock()
		lines.append("%s: %s (%s:%d %s)" % [kind, rationale if rationale != "" else code, file, line, function])
		mutex.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass
	func take() -> PackedStringArray:
		mutex.lock()
		var out := lines
		lines = PackedStringArray()
		mutex.unlock()
		return out

func _init(t: SceneTree) -> void:
	tree = t
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)

## 停止收集（結束前呼叫）
func detach() -> void:
	if _catcher != null:
		OS.remove_logger(_catcher)

## 取出自上次呼叫以來的新引擎錯誤（也累積到 engine_errors）
func new_engine_errors() -> PackedStringArray:
	if _catcher == null:
		return PackedStringArray()
	var got := _catcher.take()
	engine_errors.append_array(got)
	return got

# ---------- 小工具 ----------
func info(msg: String) -> void:
	print("[UiDriver] " + msg)

func warn(msg: String) -> void:
	warnings.append(msg)
	print("[UiDriver] WARN " + msg)

func error(msg: String) -> void:
	last_error = msg
	print("[UiDriver] ERROR " + msg)

func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

func root() -> Window:
	return tree.root

func current_scene() -> Node:
	return tree.current_scene

func scene_path() -> String:
	var s := tree.current_scene
	return s.scene_file_path if s != null else ""

# ---------- 等待 ----------
func frames(n: int = 1) -> void:
	for i in n:
		await tree.process_frame

func seconds(s: float) -> void:
	await tree.create_timer(s, true, false, true).timeout

## 每幀檢查 cond；成立回 true，逾時回 false
func wait_until(cond: Callable, timeout_s: float = 5.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()):
		if Time.get_ticks_msec() - t0 > int(timeout_s * 1000.0):
			return false
		await tree.process_frame
	return true

## 等某個訊號（逾時回 false）
func wait_signal(obj: Object, sig: String, timeout_s: float = 5.0) -> bool:
	var flag := { "hit": false }
	var cb := func(_a = null, _b = null, _c = null, _d = null): flag["hit"] = true
	obj.connect(sig, cb, CONNECT_ONE_SHOT)
	var ok := await wait_until(func(): return flag["hit"], timeout_s)
	if not ok and obj.is_connected(sig, cb):
		obj.disconnect(sig, cb)
	return ok

## 等目前場景換成 path（res://…tscn）
func wait_scene(path: String, timeout_s: float = 10.0) -> bool:
	return await wait_until(func(): return scene_path() == path, timeout_s)

# ---------- 尋找控制項 ----------
## 回傳 under（預設 root）底下所有 Control；visible_only 時只回在樹中可見者
func controls(under: Node = null, visible_only: bool = true) -> Array:
	var out: Array = []
	_collect(under if under != null else root(), visible_only, out)
	return out

func _collect(n: Node, visible_only: bool, out: Array) -> void:
	for c in n.get_children():
		if c is Control:
			if visible_only and not (c as Control).is_visible_in_tree():
				continue
			out.append(c)
		elif c is CanvasItem and visible_only and not (c as CanvasItem).visible:
			continue
		_collect(c, visible_only, out)

## 依條件找第一個（pred: func(Control) -> bool）
func find(pred: Callable, under: Node = null, visible_only: bool = true) -> Control:
	for c in controls(under, visible_only):
		if pred.call(c):
			return c
	return null

func find_all(pred: Callable, under: Node = null, visible_only: bool = true) -> Array:
	return controls(under, visible_only).filter(pred)

func find_by_path(path: String) -> Node:
	return root().get_node_or_null(path)

## meta：有 key（且 value != null 時值相同）
func find_by_meta(key: String, value: Variant = null, under: Node = null) -> Control:
	return find(func(c): return c.has_meta(key) and (value == null or c.get_meta(key) == value), under)

## 依腳本 class_name（例如 "ScenePanel"、"BattleScreen"）或引擎類別找
func find_by_class(cls: String, under: Node = null, visible_only: bool = true) -> Control:
	return find(func(c): return class_of(c) == cls or c.is_class(cls), under, visible_only)

func class_of(n: Object) -> String:
	var s: Script = n.get_script()
	while s != null:
		var g := s.get_global_name()
		if g != "":
			return g
		s = s.get_base_script()
	return n.get_class()

## mode："exact" / "prefix" / "contains"
static func text_match(t: String, want: String, mode: String) -> bool:
	match mode:
		"prefix":
			return t.begins_with(want)
		"contains":
			return t.contains(want)
	return t == want

func find_button(text: String, mode: String = "exact", under: Node = null, enabled_only: bool = false) -> Button:
	return find(func(c): return c is Button and text_match((c as Button).text, text, mode) \
		and (not enabled_only or not (c as Button).disabled), under) as Button

func find_buttons(text: String, mode: String = "exact", under: Node = null) -> Array:
	return find_all(func(c): return c is Button and text_match((c as Button).text, text, mode), under)

func find_label(text: String, mode: String = "exact", under: Node = null) -> Label:
	return find(func(c): return c is Label and text_match((c as Label).text, text, mode), under) as Label

## 有相同父節點、緊接在 anchor 之後第 offset 個兄弟（例如 GridContainer 的同一列）
func sibling(anchor: Node, offset: int) -> Node:
	if anchor == null:
		return null
	var p := anchor.get_parent()
	var i := anchor.get_index() + offset
	return p.get_child(i) if p != null and i >= 0 and i < p.get_child_count() else null

## 「標題 Label + 內容」那種列：回傳與標題 Label 同列（同父節點）的第一個 cls 控制項
func row_of_label(label_text: String, cls: String, under: Node = null) -> Control:
	var l := find_label(label_text, "exact", under)
	if l == null:
		return null
	for c in l.get_parent().get_children():
		if c != l and c is Control and (class_of(c) == cls or c.is_class(cls)):
			return c
	return null

# ---------- 互動 ----------
## 讓 ScrollContainer 裡的控制項捲進視野
func ensure_visible(c: Control) -> void:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(c)
		p = p.get_parent()
	await frames(1)

func center_of(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

## ctrl：按著 Ctrl 點（M3c：Ctrl+點 NPC 動手；事件帶 ctrl_pressed，跟真的鍵盤＋滑鼠一樣）
func push_mouse_click(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, ctrl := false) -> void:
	var vp := root()
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	vp.push_input(mm, true)
	await frames(1)
	# 按下／放開前都在同一段程式裡再送一次滑鼠位置：視窗模式下真的滑鼠游標在視窗上時，
	# 作業系統的滑鼠移動事件會在兩幀之間把「滑鼠底下的控制項」改成游標所在處，按下就會落到別的地方
	vp.push_input(mm.duplicate(), true)
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.pressed = true
	down.position = pos
	down.global_position = pos
	down.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	down.ctrl_pressed = ctrl
	vp.push_input(down, true)
	await frames(1)
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	up.button_mask = 0
	var mm2 := mm.duplicate() as InputEventMouseMotion
	mm2.button_mask = down.button_mask
	vp.push_input(mm2, true)
	vp.push_input(up, true)
	await frames(1)

func hovered_control() -> Control:
	var vp := root()
	if vp.has_method("gui_get_hovered_control"):
		return vp.call("gui_get_hovered_control")
	return null

## 按鈕：模擬滑鼠點擊中心點，確認 pressed 觸發。回傳 true = 按下成功；ctrl＝按著 Ctrl 點
func click(c: Control, ctrl := false) -> bool:
	if c == null or not is_instance_valid(c):
		error("click: control not found")
		return false
	if not c.is_visible_in_tree():
		error("click: '%s' is not visible" % describe(c))
		return false
	if c is BaseButton and (c as BaseButton).disabled:
		error("click: '%s' is disabled" % describe(c))
		return false
	await ensure_visible(c)
	if not is_instance_valid(c):
		return false
	var desc := describe(c)
	var flag := { "hit": false }
	var cb := func(): flag["hit"] = true
	var is_button := c is BaseButton
	if is_button:
		(c as BaseButton).pressed.connect(cb, CONNECT_ONE_SHOT)
	var aim := center_of(c)
	var rect_before := c.get_global_rect()
	await push_mouse_click(aim, MOUSE_BUTTON_LEFT, ctrl)
	if not is_button:
		return true
	if flag["hit"]:
		if verbose:
			info("clicked " + desc)
		return true
	var blocker := hovered_control()
	if is_instance_valid(c) and (c as BaseButton).pressed.is_connected(cb):
		(c as BaseButton).pressed.disconnect(cb)
	var why := "mouse click did not reach '%s' (hovered: %s; aimed at %s, rect %s -> %s, viewport %s)" % [desc, describe(blocker) if blocker else "?",
		str(aim), str(rect_before), str(c.get_global_rect()) if is_instance_valid(c) else "freed", str(root().get_visible_rect().size)]
	if strict_clicks:
		error(why)
		return false
	warn(why + " -> emit pressed")
	if is_instance_valid(c):
		(c as BaseButton).pressed.emit()
	return true

## 找到文字相符的按鈕（可等它出現且可按）再點
func click_text(text: String, mode: String = "exact", under: Node = null, timeout_s: float = 5.0) -> bool:
	var ok := await wait_until(func(): return find_button(text, mode, under, true) != null, timeout_s)
	if not ok:
		var b := find_button(text, mode, under)
		error("button '%s' (%s) %s" % [text, mode, "is disabled" if b != null else "not found"])
		return false
	return await click(find_button(text, mode, under, true))

## 在 Control 的區域座標（local）點一下（例如戰鬥格子）
func click_local(c: Control, local: Vector2) -> void:
	await push_mouse_click(c.get_global_transform() * local)

## LineEdit：點一下取得焦點，逐字送 unicode 鍵盤事件；最後確認文字一致
func type_text(e: LineEdit, text: String, clear_first: bool = true, submit: bool = false) -> bool:
	if e == null or not e.is_visible_in_tree():
		error("type_text: LineEdit not visible")
		return false
	await ensure_visible(e)
	await push_mouse_click(center_of(e))
	if not e.has_focus():
		warn("type_text: click did not focus LineEdit -> grab_focus")
		e.grab_focus()
	if clear_first:
		e.select_all()
		await press_key(KEY_BACKSPACE)
	for ch in text:
		var k := InputEventKey.new()
		k.pressed = true
		k.unicode = ch.unicode_at(0)
		root().push_input(k, true)
		var k2 := k.duplicate() as InputEventKey
		k2.pressed = false
		root().push_input(k2, true)
	await frames(1)
	if e.text != text:
		error("type_text: expected '%s' got '%s'" % [text, e.text])
		return false
	if submit:
		await press_key(KEY_ENTER)
	return true

func press_key(keycode: int, ctrl: bool = false, shift: bool = false) -> void:
	var k := InputEventKey.new()
	k.keycode = keycode
	k.physical_keycode = keycode
	k.ctrl_pressed = ctrl
	k.shift_pressed = shift
	k.pressed = true
	root().push_input(k, true)
	await frames(1)
	var up := k.duplicate() as InputEventKey
	up.pressed = false
	root().push_input(up, true)
	await frames(1)

## TextEdit：點一下取得焦點，逐字送 unicode 鍵盤事件；最後確認文字一致
func type_text_edit(e: TextEdit, text: String) -> bool:
	if e == null or not e.is_visible_in_tree():
		error("type_text_edit: TextEdit not visible")
		return false
	await ensure_visible(e)
	await push_mouse_click(center_of(e))
	if not e.has_focus():
		warn("type_text_edit: click did not focus TextEdit -> grab_focus")
		e.grab_focus()
	e.select_all()
	await press_key(KEY_BACKSPACE)
	for ch in text:
		var k := InputEventKey.new()
		k.pressed = true
		k.unicode = ch.unicode_at(0)
		root().push_input(k, true)
		var k2 := k.duplicate() as InputEventKey
		k2.pressed = false
		root().push_input(k2, true)
	await frames(1)
	if e.text != text:
		error("type_text_edit: expected '%s' got '%s'" % [text, e.text])
		return false
	return true

## MenuButton：用滑鼠點開選單（確認彈出），依文字找項目；項目停用時失敗；選定以 id_pressed 送出並收起選單
func choose_menu(mb: MenuButton, text: String, mode: String = "exact") -> bool:
	if mb == null or not mb.is_visible_in_tree():
		error("choose_menu: MenuButton not visible")
		return false
	var pm := mb.get_popup()
	await ensure_visible(mb)
	await push_mouse_click(center_of(mb))
	if not await wait_until(func(): return pm.visible, 2.0):
		warn("choose_menu: click did not open the popup of '%s' -> show_popup" % describe(mb))
		mb.show_popup()
		await frames(2)
	for i in pm.item_count:
		if text_match(pm.get_item_text(i), text, mode):
			if pm.is_item_disabled(i):
				error("choose_menu: item '%s' is disabled" % pm.get_item_text(i))
				pm.hide()
				return false
			pm.id_pressed.emit(pm.get_item_id(i))
			pm.hide()
			await frames(2)
			return true
	error("choose_menu: no item '%s' in %s" % [text, str(menu_items(mb))])
	pm.hide()
	return false

func menu_items(mb: MenuButton) -> Array:
	var pm := mb.get_popup()
	var out: Array = []
	for i in pm.item_count:
		out.append(pm.get_item_text(i))
	return out

## OptionButton：依文字選項目（會點開下拉、再以 select + item_selected 選定）
func select_option(ob: OptionButton, text: String, mode: String = "exact") -> bool:
	if ob == null or not ob.is_visible_in_tree():
		error("select_option: OptionButton not visible")
		return false
	for i in ob.item_count:
		if text_match(ob.get_item_text(i), text, mode):
			ob.select(i)
			ob.item_selected.emit(i)
			await frames(1)
			return ob.selected == i
	error("select_option: no item '%s' in %s" % [text, str(range(ob.item_count).map(func(j): return ob.get_item_text(j)))])
	return false

## ItemList：依文字選；activate = 同時發 item_activated（雙擊）
func select_item(il: ItemList, text: String, mode: String = "exact", activate: bool = false) -> bool:
	if il == null or not il.is_visible_in_tree():
		error("select_item: ItemList not visible")
		return false
	for i in il.item_count:
		if text_match(il.get_item_text(i), text, mode):
			il.select(i)
			il.item_selected.emit(i)
			if activate:
				il.item_activated.emit(i)
			await frames(1)
			return true
	error("select_item: no item '%s'" % text)
	return false

## TabBar：用滑鼠點分頁（點不到時直接設 current_tab）
func select_tab(tb: TabBar, index: int) -> bool:
	if tb == null or index < 0 or index >= tb.tab_count:
		error("select_tab: bad tab %d" % index)
		return false
	var r := tb.get_tab_rect(index)
	await push_mouse_click(tb.get_global_transform() * r.get_center())
	if tb.current_tab != index:
		warn("select_tab: click did not switch tab %d -> set current_tab" % index)
		tb.current_tab = index
		await frames(1)
	return tb.current_tab == index

# ---------- 診斷 ----------
func describe(c: Node) -> String:
	if c == null or not is_instance_valid(c):
		return "<null>"
	var t := ""
	if c is Button or c is Label or c is LineEdit:
		t = " '%s'" % str(c.get("text")).replace("\n", "⏎").left(40)
	return "%s(%s)%s" % [class_of(c), c.name, t]

## 傾印可見 UI 樹：類別、名稱、文字、disabled、visible
func dump(under: Node = null, visible_only: bool = true, max_lines: int = 400) -> String:
	var lines: PackedStringArray = []
	_dump(under if under != null else root(), 0, visible_only, lines, max_lines)
	return "\n".join(lines)

func _dump(n: Node, depth: int, visible_only: bool, lines: PackedStringArray, max_lines: int) -> void:
	if lines.size() >= max_lines:
		return
	for c in n.get_children():
		if c is CanvasItem and visible_only and not (c as CanvasItem).is_visible_in_tree():
			continue
		if c is Control:
			var s := "  ".repeat(depth) + class_of(c) + " " + str(c.name)
			var t: Variant = c.get("text")
			if t is String and t != "":
				s += " text='%s'" % (t as String).replace("\n", "⏎").left(60)
			if c is BaseButton and (c as BaseButton).disabled:
				s += " [disabled]"
			if not (c as Control).visible:
				s += " [hidden]"
			lines.append(s)
		_dump(c, depth + 1, visible_only, lines, max_lines)

func print_dump(title: String, under: Node = null) -> void:
	print("[UiDriver] ---- UI dump: %s (scene %s) ----\n%s\n[UiDriver] ---- end dump ----" % [title, scene_path(), dump(under)])

# ---------- 截圖 ----------
## --ui-shots=<dir> 且非 headless 時存 dir/NN_name.png
func shot(name: String) -> void:
	if shots_dir == "" or is_headless():
		return
	await RenderingServer.frame_post_draw
	var img := root().get_texture().get_image()
	if img == null:
		warn("shot %s: no image" % name)
		return
	DirAccess.make_dir_recursive_absolute(shots_dir)
	shot_index += 1
	var path := shots_dir.path_join("%02d_%s.png" % [shot_index, name])
	var err := img.save_png(path)
	if err != OK:
		warn("shot %s: save_png error %d" % [path, err])
		return
	shots.append(path)
	info("shot " + path)
