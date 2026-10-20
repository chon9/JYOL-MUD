class_name MapPanel
extends VBoxContainer
## 大地圖面板（主畫面「地圖」按鈕／M 鍵）：兩個分頁
##   區域圖：目前區域的房間圖（迷霧：只顯示到過的房間），點擊到過的房間 → 客戶端尋路 → 逐步送 move。
##   江湖全圖：各區域位置、步行相連與驛站路線、建議實戰。
## 到過的房間記在本機資料根目錄（MapMemory），純外觀，主機不知道也不需要知道。
## 故事包：任務窗「在地圖上標出」→ set_quest_mark(room)：區域圖與小地圖在那個房間畫「★任務」虛框，頁尾寫地點；
## 不在目前區域或還沒去過時頁尾說明在哪一區；clear_quest_mark() 取消。
## M3c（M3C_PLAN §4）：
## - 跨區趕路：區域圖點房間、江湖全圖點地區 → RoutePlanner 在全世界「已探索房間」上找最短路（迷霧照舊）；
##   目標沒探索 → 走到最接近目標的已探索房間，進度列寫「（只能走到 X，再往前沒去過）」。
## - 快捷目的地（頁尾「快捷」與小地圖右鍵）：記錄點、最近的客棧／茶棚／綠洲、本派山門、出生城、任務目標；不能去的灰掉並寫原因。
## - 進度列「趕路中：往X（剩N步）」＋「停止」鈕＋Esc（主畫面）；小地圖也顯示。
## - 遇敵：暫停；戰鬥畫面收起後依 §4.4 停或續走（系統選項 nav.auto_resume，預設開）。
## - 「往XXX」：區域圖與小地圖切到那個鄰區（瀏覽中），那區到過的房間可以點來趕路；「返回目前區域」回來。

const HINT := "點擊到過的房間可自動趕路（可跨區）；紅點＝可能遇敵；藍色「往…」＝切到那一區的地圖。"
const MINI_HINT := "點擊到過的房間可自動趕路。"
const MINI_BROWSE_HINT := "點房間趕路；「返」回來。"   # M3c 審查：小地圖頁尾很窄，長句會被切掉
const TAB_REGION := 0
const TAB_WORLD := 1
const NEVER_BEEN := "那裡還沒去過。"
const BROWSE_TAG := "（瀏覽中）"
const AUTO_RESUME_KEY := "nav.auto_resume"

var gate: IntentGate
var memory := MapMemory.new()
var walker: AutoWalker
var tabs: TabContainer
var region_scroll: ScrollContainer
var region_view: RegionMapView
var world_view: WorldMapView
var region_title: Label
var status_label: Label
var cancel_button: Button
var back_button: Button
var quick_button: MenuButton
var quick_popup: PopupMenu          # 小地圖右鍵用（同一份選項）

var tables_override: Dictionary = {}   # 測試用；空＝讀 GameData
var mini_map: MiniMap = null          # 主畫面常駐小地圖（可為 null）
var _shown_region := ""               # 上次 refresh 的（實際所在）區域；換區域時把頁尾狀態還原成說明
var browse_region := ""               # 「往XXX」切過去瀏覽的區域；空＝目前區域
var view: Dictionary = {}
var sheet: Dictionary = {}
var _model_cache: Dictionary = {}     # region_id -> region_model
var _world_cache: Dictionary = {}
var _graph: Dictionary = {}
var _graph_src: Variant = null
var _quick_items: Array = []          # RoutePlanner.quick_destinations 的結果（選單 id = 索引）
var battle_result := ""               # 這場戰鬥我的結算（close_battle 時記下，戰鬥畫面收起時交給 walker）
var quest_mark := ""
var _built := false

func _ready() -> void:
	if not _built:
		_build()
	visibility_changed.connect(_on_visibility_changed)

func _gate() -> IntentGate:
	if gate == null:
		gate = IntentGate.new()
		add_child(gate)
	return gate

func _build() -> void:
	_built = true
	add_theme_constant_override("separation", 6)
	# 視窗是羊皮紙（SCROLL）框：用卷軸主題，頁尾的字是墨色（審查：白字、淺灰字在羊皮紙上看不清）
	theme = UiTheme.paper()
	custom_minimum_size = Vector2(760, 400)   # 1280×720 時要放得進小地圖左邊（主畫面視窗層 984 寬）
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)

	region_scroll = ScrollContainer.new()
	region_scroll.name = "區域圖"
	region_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	region_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(region_scroll)
	region_view = RegionMapView.new()
	region_view.room_clicked.connect(_on_room_clicked)
	region_view.region_clicked.connect(show_region)
	region_view.context_requested.connect(func(at: Vector2): open_quick_menu(region_view.get_screen_position() + at))
	region_scroll.add_child(region_view)
	region_scroll.resized.connect(func():
		region_view.fit_into(region_scroll.size)
		_center_current.call_deferred())

	world_view = WorldMapView.new()
	world_view.name = "江湖全圖"
	world_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	world_view.region_clicked.connect(walk_to_region)
	tabs.add_child(world_view)

	var foot := UiBuild.hbox(self, 10)
	region_title = UiBuild.label(foot, "", 17)
	region_title.add_theme_color_override("font_color", UiTheme.INK)
	status_label = UiBuild.muted(UiBuild.label(foot, HINT, 15, true))
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quick_button = MenuButton.new()
	quick_button.text = "快捷▾"
	quick_button.flat = false
	quick_button.tooltip_text = "快捷目的地：記錄點、最近的客棧、本派山門、出生城、任務目標"
	quick_button.add_theme_font_size_override("font_size", 15)
	foot.add_child(quick_button)
	quick_button.about_to_popup.connect(func(): _fill_quick(quick_button.get_popup()))
	quick_button.get_popup().id_pressed.connect(_on_quick_pressed)
	back_button = UiBuild.button(foot, "返回目前區域", back_to_current)
	back_button.visible = false
	cancel_button = UiBuild.button(foot, "停止", func(): walker.stop(AutoWalkCore.MSG_STOPPED))
	cancel_button.tooltip_text = "停止趕路（Esc）"
	cancel_button.visible = false
	quick_popup = PopupMenu.new()
	add_child(quick_popup)
	quick_popup.id_pressed.connect(_on_quick_pressed)

	walker = AutoWalker.new()
	walker.gate = _gate()
	walker.state_changed.connect(_on_walk_state)
	add_child(walker)

func tables() -> Dictionary:
	return tables_override if not tables_override.is_empty() else UiClient.tables()

## 全世界房間圖（tables 換了才重建）
func graph() -> Dictionary:
	var t := tables()
	if _graph_src == null or not is_same(_graph_src, t) or _graph.is_empty():
		_graph = RoutePlanner.graph(t)
		_graph_src = t
	return _graph

## 已探索房間（目前房間一定算）
func known() -> Dictionary:
	var k := memory.visited.duplicate()
	if current_room() != "":
		k[current_room()] = true
	return k

# ---------- 資料 ----------
func apply_sheet(s: Dictionary) -> void:
	if not _built:
		_build()
	sheet = s
	walker.sheet = s
	var cid := str(s.get("char_id", ""))
	if cid != "" and cid != memory.char_id:
		memory.set_char(cid)
		var room := str(view.get("room", ""))
		if room != "":
			memory.mark(room)
		refresh()

func apply_view(v: Dictionary) -> void:
	if not _built:
		_build()
	view = v
	memory.mark(str(v.get("room", "")))
	walker.core.known = known()
	walker.on_view(v)
	if browse_region != "" and browse_region == current_region():
		browse_region = ""   # 走進了正在瀏覽的那一區
	refresh()

## 戰鬥開始（主畫面 open_battle）
func on_battle() -> void:
	battle_result = ""
	if walker != null:
		walker.on_battle()

## 戰鬥結算（主畫面 close_battle）：記下我的結果
func on_battle_result(result: Dictionary) -> void:
	battle_result = str(result.get("result", ""))

## 戰鬥畫面收起（主畫面 _on_battle_finished）：趕路中被打斷的話，依結果與續走選項決定
func on_battle_closed() -> void:
	if walker != null:
		walker.on_battle_end(battle_result if battle_result != "" else "ABORTED", UiSettings.get_bool(AUTO_RESUME_KEY))
	battle_result = ""

func is_walking() -> bool:
	return walker != null and walker.is_walking()

## Esc：正在趕路 → 停止並回 true（主畫面不再關視窗、收燈籠）
func esc_stop() -> bool:
	if not is_walking():
		return false
	walker.stop(AutoWalkCore.MSG_STOPPED)
	return true

func current_room() -> String:
	return str(view.get("room", ""))

func current_region() -> String:
	var r := str(view.get("region", ""))
	if r == "" and current_room() != "":
		var idx := MapData.room_index(tables())
		r = str(idx.get(current_room(), {}).get("region", ""))
	return r

## 畫面上的區域（瀏覽中＝別區）
func shown_region() -> String:
	return browse_region if browse_region != "" else current_region()

func region_model(region_id: String) -> Dictionary:
	if not _model_cache.has(region_id):
		_model_cache[region_id] = MapData.region_model(tables(), region_id)
	return _model_cache[region_id]

func refresh() -> void:
	if not _built:
		return
	var rid := shown_region()
	var browsing := browse_region != ""
	var model := region_model(rid) if rid != "" else {}
	var k := memory.visited.duplicate()
	var focus := browse_focus() if browsing else ""
	region_view.focus_room = focus
	region_view.setup(tables(), model, k, current_room())
	region_view.fit_into(region_scroll.size)
	region_view.set_walk_target(walker.target() if walker.is_walking() else "")
	_center_current.call_deferred()
	_push_walk_path()
	var nm := str(model.get("name", "")) if browsing else str(view.get("region_name", model.get("name", "")))
	var total := (model.get("by_id", {}) as Dictionary).size()
	if nm != "":
		region_title.text = "%s%s　已探索 %d／%d 處" % [nm, BROWSE_TAG if browsing else "", region_view.visible_rooms().size(), total]
	else:
		region_title.text = "（尚未進入世界）"
	back_button.visible = browsing
	var cur_rid := current_region()
	if cur_rid != _shown_region:
		# 換了區域（驛站、走出城）：上一區的「已抵達。」等趕路結果不再適用
		_shown_region = cur_rid
		if not walker.is_walking() and not browsing:
			_set_status(HINT)
	region_view.set_quest_mark(quest_mark)
	if mini_map != null:
		mini_map.show_region(tables(), model, k, current_room(), region_title.text,
			walker.target() if walker.is_walking() else "", browsing, focus)
		mini_map.view.set_quest_mark(quest_mark)
	var coach: bool = ClientState.world_info.get("stagecoach_enabled", false) == true
	if _world_cache.is_empty() or _world_cache.get("stagecoach", false) != coach:
		_world_cache = MapData.world_model(tables(), coach)
		_world_cache["stagecoach"] = coach
	world_view.setup(_world_cache, cur_rid)
	_push_walk_path()

## 區域圖比視窗大時捲到目前房間（置中）；瀏覽別區時捲到 focus 房間
func _center_current() -> void:
	if region_scroll == null or not region_scroll.is_inside_tree():
		return
	await get_tree().process_frame   # 等 ScrollContainer 依新的 custom_minimum_size 重排
	if not is_instance_valid(region_view):
		return
	var id := region_view.focus_id()
	if id == "":
		return
	var r := region_view.screen_rect(id)
	if r.size == Vector2.ZERO:
		return
	var c := r.get_center()
	region_scroll.scroll_horizontal = int(maxf(0.0, c.x - region_scroll.size.x / 2.0))
	region_scroll.scroll_vertical = int(maxf(0.0, c.y - region_scroll.size.y / 2.0))

func show_tab(i: int) -> void:
	if tabs != null:
		tabs.current_tab = i

# ---------- 「往XXX」切區瀏覽（§4.5） ----------
## 區域圖與小地圖改顯示 region_id（同一份迷霧）；region_id 是目前區域或空＝返回
func show_region(region_id: String) -> void:
	if not _built:
		_build()
	if region_id == "" or region_id == current_region():
		back_to_current()
		return
	if not (tables().get("maps", {}) as Dictionary).has(region_id):
		return
	browse_region = region_id
	show_tab(TAB_REGION)
	refresh()
	if walker.is_walking():
		return
	var model := region_model(region_id)
	var seen := 0
	for id in model.get("by_id", {}):
		if memory.has(id):
			seen += 1
	if seen == 0:
		_set_status(NEVER_BEEN)
	else:
		_set_status("瀏覽%s：點到過的房間可以直接趕路過去。" % MapData.region_name(tables(), region_id), false, MINI_BROWSE_HINT)

func back_to_current() -> void:
	var was := browse_region != ""
	browse_region = ""
	refresh()
	if was and not walker.is_walking():
		_set_status(HINT)

## 瀏覽時畫面跟著的房間：從目前房間（或目前區域到過的房間）走過去的入口；沒有就那區第一間到過的
func browse_focus() -> String:
	if browse_region == "":
		return ""
	var cur_model := region_model(current_region()) if current_region() != "" else {}
	var first_any := ""
	for oe in cur_model.get("out_exits", []):
		if str(oe.get("to_region", "")) != browse_region:
			continue
		var to := str(oe.get("to", ""))
		if str(oe.get("from", "")) == current_room() and memory.has(to):
			return to
		if first_any == "" and memory.has(to):
			first_any = to
	if first_any != "":
		return first_any
	for r in region_model(browse_region).get("rooms", []):
		if memory.has(str(r.get("id", ""))):
			return str(r.get("id", ""))
	return ""

# ---------- 趕路 ----------
func _on_room_clicked(id: String) -> void:
	if walker.is_walking():
		walker.stop("已取消趕路。")
		return
	if id == "" or id == current_room():
		return
	if not memory.has(id):
		_set_status("還沒去過那裡，找不到路。")
		return
	if not UiClient.battle_state().is_empty():
		_set_status("戰鬥中不能趕路。")
		return
	var g := graph()
	var path := RoutePlanner.find_path(g, current_room(), id, known())
	if path.size() < 2:
		_set_status("找不到已知的路。")
		return
	_start(path, RoutePlanner.room_name(tables(), id), "")

## 江湖全圖點地區：走到那一區最近的已探索房間；那區沒去過 → 走到最接近的已探索房間
func walk_to_region(region_id: String) -> void:
	if walker.is_walking():
		walker.stop("已取消趕路。")
		return
	if region_id == "":
		return
	var rname := MapData.region_name(tables(), region_id)
	if region_id == current_region():
		_set_status("你已經在%s了。" % rname)
		return
	if not UiClient.battle_state().is_empty():
		_set_status("戰鬥中不能趕路。")
		return
	var r := RoutePlanner.region_target(tables(), graph(), current_room(), region_id, known())
	var path: Array = r.get("path", [])
	if str(r.get("room", "")) == "" or path.size() < 2:
		_set_status("找不到往%s的已知道路（那裡還沒去過）。" % rname)
		return
	var note := "" if bool(r.get("exact", false)) else _partial_note(str(r["room"]))
	_start(path, rname, note)

## 快捷目的地清單（每次打開選單時重算）
func quick_items() -> Array:
	_quick_items = RoutePlanner.quick_destinations(tables(), graph(), current_room(), known(), sheet, quest_mark)
	return _quick_items

func _fill_quick(pm: PopupMenu) -> void:
	pm.clear()
	var items := quick_items()
	for i in items.size():
		var q: Dictionary = items[i]
		pm.add_item(quick_label(q), i)
		var at := pm.get_item_index(i)
		pm.set_item_disabled(at, not bool(q["ok"]))
		if not bool(q["ok"]):
			pm.set_item_tooltip(at, str(q["reason"]))

## 「記錄點：大理廣場」「最近的客棧：西夏客棧」「本派山門（你沒有門派）」
static func quick_label(q: Dictionary) -> String:
	var t := str(q.get("label", ""))
	if str(q.get("name", "")) != "":
		t += "：" + str(q["name"])
	if not bool(q.get("ok", false)) and str(q.get("reason", "")) != "":
		t += "（%s）" % str(q["reason"])
	elif bool(q.get("ok", false)) and not bool(q.get("exact", true)):
		t += "（只能走到附近）"
	return t

## 小地圖右鍵 / 區域圖右鍵：同一份快捷選單
func open_quick_menu(screen_pos: Vector2) -> void:
	_fill_quick(quick_popup)
	quick_popup.reset_size()
	quick_popup.popup(Rect2i(Vector2i(screen_pos), Vector2i.ZERO))

func _on_quick_pressed(i: int) -> void:
	walk_quick(i)

## 走第 i 個快捷目的地（索引對應 quick_items()）
func walk_quick(i: int) -> void:
	if i < 0 or i >= _quick_items.size():
		return
	var q: Dictionary = _quick_items[i]
	if not bool(q["ok"]):
		_set_status("%s：%s" % [str(q["label"]), str(q["reason"])])
		return
	if walker.is_walking():
		walker.stop("")
	if not UiClient.battle_state().is_empty():
		_set_status("戰鬥中不能趕路。")
		return
	var dest_name := str(q["name"]) if str(q["name"]) != "" else str(q["label"])
	var note := "" if bool(q["exact"]) else _partial_note(str(q["dest"]))
	_start(q["path"], dest_name, note)

func _partial_note(reach_room: String) -> String:
	return "（只能走到%s，再往前沒去過）" % RoutePlanner.room_name(tables(), reach_room)

func _start(room_path: Array, dest_name: String, note: String) -> void:
	var g := graph()
	var steps := RoutePlanner.steps(g, room_path)
	if steps.is_empty():
		_set_status("找不到已知的路。")
		return
	walker.view = view
	walker.sheet = sheet
	walker.configure(tables(), g, known())
	walker.start(steps, current_room(), dest_name, note)
	var target := walker.target()
	region_view.set_walk_target(target)
	if mini_map != null:
		mini_map.view.set_walk_target(target)
	_push_walk_path()

func _on_walk_state(walking: bool, text: String) -> void:
	cancel_button.visible = walking
	if not walking:
		region_view.set_walk_target("")
		if text == AutoWalkCore.MSG_ARRIVED and browse_region != "":
			browse_region = ""   # 抵達：畫面回到目前區域
			refresh()
	_set_status(text if text != "" else HINT, walking)

func _set_status(text: String, walking := false, mini_text := "") -> void:
	status_label.text = text
	status_label.theme_type_variation = "ErrorLabel" if walking else "MutedLabel"
	if mini_map != null:
		mini_map.set_status(mini_text if mini_text != "" else (MINI_HINT if text == HINT else text), walking)
		mini_map.view.set_walk_target(walker.target() if walking else "")
	_push_walk_path()

## M3c 審查：區域圖、小地圖、江湖全圖都畫出剩下的路（全圖畫經過的地區與目的地）
func _push_walk_path() -> void:
	if walker == null or region_view == null:
		return
	var rooms: Array = walker.remaining_rooms()
	region_view.set_walk_path(rooms)
	if mini_map != null and mini_map.view != null:
		mini_map.view.set_walk_path(rooms)
	if world_view != null:
		world_view.set_walk_route(route_regions(rooms))

## 房間路線 → 經過的地區（連續相同的合併）：[目前地區, …, 目的地所在地區]
func route_regions(rooms: Array) -> Array:
	var out: Array = []
	if rooms.is_empty():
		return out
	var idx := MapData.room_index(tables())
	for r in rooms:
		var rid := str(idx.get(str(r), {}).get("region", ""))
		if rid != "" and (out.is_empty() or str(out[out.size() - 1]) != rid):
			out.append(rid)
	return out

## 任務提示地點：標在區域圖上並在頁尾說明（不在本區、還沒去過時說在哪裡）
func set_quest_mark(room_id: String) -> void:
	if not _built:
		_build()
	quest_mark = room_id
	refresh()
	if room_id == "":
		_set_status(HINT)
		return
	_set_status(quest_mark_text(room_id))

func clear_quest_mark() -> void:
	set_quest_mark("")

func quest_mark_text(room_id: String) -> String:
	var idx := MapData.room_index(tables())
	var r: Dictionary = idx.get(room_id, {})
	var room: Dictionary = r.get("room", {}) if r.get("room", {}) is Dictionary else {}
	var nm := str(room.get("name", room_id))
	var rid := str(r.get("region", ""))
	if rid != "" and rid != current_region():
		return "任務地點：%s（在%s，不在這一區）" % [nm, MapData.region_name(tables(), rid)]
	if not region_view.is_shown(room_id):
		return "任務地點：%s（還沒去過，地圖上找不到）" % nm
	return "任務地點：%s（地圖上的「★任務」）" % nm

## 主畫面小地圖點房間：同大地圖的點擊趕路
func walk_to(id: String) -> void:
	_on_room_clicked(id)

## 主畫面接線：小地圖的「往XXX」、返回、停止、右鍵
func bind_mini_map(mm: MiniMap) -> void:
	mini_map = mm
	mm.room_clicked.connect(walk_to)
	mm.region_clicked.connect(show_region)
	mm.back_requested.connect(back_to_current)
	mm.stop_requested.connect(func(): walker.stop(AutoWalkCore.MSG_STOPPED))
	mm.quick_requested.connect(open_quick_menu)

func _on_visibility_changed() -> void:
	# 關掉地圖就停止趕路（看不到狀態時不要自己一直走）；主畫面小地圖看得到時照走
	var mini_shown := mini_map != null and mini_map.is_visible_in_tree()
	if not is_visible_in_tree() and walker != null and walker.is_walking() and not mini_shown and walker.phase != "battle":
		walker.stop("已取消趕路。")
	elif is_visible_in_tree():
		refresh()
