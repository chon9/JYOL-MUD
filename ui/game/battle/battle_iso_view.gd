class_name BattleIsoView
extends Control
## 等角戰場（GDD 11.3 原作風格）：12×8 格子以 2:1 菱形投影，畫在地區背景上；
## 角色／怪物以 UnitSprite 立繪顯示（腳踩格心、依 x+y 排前後），特效與飄字在 BattleFx。
## 美術一律經 ArtRegistry 查（沒有圖時畫程式暫代剪影）。只負責呈現：所有位置、氣、狀態都來自 BattleViewModel；動畫不擋輸入、不影響回合流程。
##
## 公開給畫面與 UI driver：cell_at(local) / cell_center(cell) / highlight / vm / set_highlight / cell_clicked。
## 原作配色（AUTHENTIC_UI_SPEC §12.1）：移動綠格、攻擊範圍藍格（range_cells）、殺傷／目標紅格（highlight）、
## 游標黃色細菱形外框、逃跑格白色雙線菱形加平貼的「逃」字、輪到我時腳下白色雙線菱形與頭上閃三次黃菱形；
## 石台前兩面畫土色側壁。背景保留主人繪製的地區圖（不用原作的全黑虛空）。
## 倒下的單位一定看得到：屍體先畫（在活人下面）、有活人站在同一格時屍體往前挪、擋到屍體的活人變半透明，
## 並在屍體格前角畫「倒」字牌（BattleFx）。

signal cell_clicked(cell: Vector2i)

const HEAD_ROOM := 1.9         # 最後一排角色頭頂＋名字的空間（格寬倍數；從最上面的格角算起）
const FOOT_ROOM := 0.3         # 最前一排血條的空間
const SIDE_FILL := 0.92        # 格子最多佔可用寬度的比例（左右角不貼邊）
const STEP_DUR := 0.16         # 移動每格秒數
const LUNGE_DUR := 0.34
const LUNGE_REACH := 0.3       # 前衝距離 = 兩人距離的這個比例（停在自己格邊，不衝進對方身上）
const IMPACT_AT := 0.13
const HURT_DUR := 0.38
const XRAY_ALPHA := 0.55       # 擋住我的前排單位變半透明（我站著時）
const XRAY_DEAD := 0.45        # 我倒地時擋在屍體上的單位更透明
const XRAY_COVER := 0.1        # 擋住我身體至少這個比例才透視（只碰到腳邊不算）
const MAX_BACKLOG := 1.2       # 動畫排隊超過這麼久就直接跳到現在（永遠不落後主機太多）
const GRID_FILL := Color(0.05, 0.04, 0.02, 0.07)
const GRID_EDGE := Color(0.18, 0.12, 0.05, 0.30)
const GRID_EDGE_HI := Color(1.0, 0.97, 0.88, 0.16)
const GRID_BORDER := Color(1.0, 0.95, 0.8, 0.55)
const HOVER_FILL := Color(1.0, 0.88, 0.25, 0.10)
const HOVER_EDGE := UiTheme.HOVER_CURSOR
const ESCAPE_GLOW := Color(1.0, 1.0, 1.0)
const ESCAPE_EDGE := Color(1.0, 1.0, 1.0)
const ESCAPE_INK := Color(1.0, 1.0, 1.0)
const WALL_TOP := Color("5a4026")
const WALL_BOTTOM := Color("2e2014")
const WALL_H := 0.175          # 側壁厚 ≈ 0.35 格高（格高 = 格寬 / 2）
const CORPSE_SHIFT := 0.22     # 有活人站在屍體同一格：屍體往前（螢幕下方）挪這麼多格寬
const TURN_FLASH_S := 1.2      # 輪到我：頭上黃菱形閃 3 次

var vm: BattleViewModel
var highlight: Array = []          # Array[Vector2i]
var highlight_color := UiTheme.HIGHLIGHT_MOVE
var range_cells: Array = []        # 攻擊／招式範圍（藍）；highlight 是可點的目標（紅）
# M3a（M3A_PLAN §7.2、§7.5）
var preview_cells: Array = []      # 範圍招式：滑鼠所在中心格會打到的格（半透明橘）
var station_cells: Array = []      # 陣法站位（金框）
var station_missing: Array = []    # 缺人的站位（金框閃爍）
var aoe_flash: Array = []          # battle_aoe：剛打到的格（短暫標示）
var aoe_flash_until := 0.0
const AOE_FLASH_S := 0.8
var show_grid := true
var damage_text := true            # 損血顯示（腰部 cur/max；壓到鄰居時改在名字牌下）
var turn_flash_until := 0.0
var now_tick := 0.0
var hover_cell := Vector2i(-1, -1)
var region_id := ""
var tile_w := 64.0                 # 菱形寬（高 = 寬 / 2）
var origin := Vector2.ZERO         # 格 (0,0) 中心的本地座標
var sprites: Dictionary = {}       # uid -> UnitSprite
var units_layer: Node2D
var fx: BattleFx
var bg_tex: Texture2D
var escape_tex: Texture2D

func _init() -> void:
	custom_minimum_size = Vector2(480, 300)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	units_layer = Node2D.new()
	units_layer.name = "Units"
	add_child(units_layer)
	fx = BattleFx.new()
	fx.name = "Fx"
	fx.view = self
	# 前後順序只用節點順序（不用 z_index）：z_index 會讓人物畫到戰鬥畫面的浮動視窗（結果、招式選擇）上面
	add_child(fx)

func set_vm(m: BattleViewModel) -> void:
	vm = m
	for uid in sprites:
		(sprites[uid] as Node).queue_free()
	sprites.clear()
	fx.clear()
	escape_tex = BattleFx.optional_texture("tile_escape")
	_layout()
	_sync_units()
	queue_redraw()

func set_region(rid: String) -> void:
	region_id = rid
	bg_tex = ArtRegistry.battle_background(rid)
	queue_redraw()

func set_highlight(cells: Array, color: Color) -> void:
	highlight = cells
	highlight_color = color
	queue_redraw()

func clear_highlight() -> void:
	range_cells = []
	preview_cells = []
	station_cells = []
	station_missing = []
	set_highlight([], highlight_color)

## 範圍招式預覽（滑鼠所在中心格的打擊格）
func set_preview(cells: Array) -> void:
	preview_cells = cells
	queue_redraw()

## 陣法站位：cells 全部畫金框，missing（缺人）閃爍
func set_stations(cells: Array, missing: Array) -> void:
	station_cells = cells
	station_missing = missing
	queue_redraw()

## 滑鼠停在單位上：提示名稱與身上的狀態（§7.5「滑鼠提示名稱與剩餘次數」）
func _get_tooltip(at_position: Vector2) -> String:
	return tooltip_at(cell_at(at_position))

func tooltip_at(c: Vector2i) -> String:
	if vm == null or not vm.in_grid(c):
		return ""
	var uid := vm.unit_at(c)
	if uid == 0:
		return ""
	var sts := vm.unit_statuses(uid)
	if sts.is_empty():
		return ""
	var parts: PackedStringArray = []
	for st in sts:
		parts.append(BattleViewModel.status_tip(st))
	return "%s：%s" % [str(vm.unit(uid).get("name", "")), "、".join(parts)]

## 攻擊範圍（藍格，畫在目標紅格下面）
func set_range(cells: Array) -> void:
	range_cells = cells
	queue_redraw()

## 曼哈頓距離 1..r 以內、在格子內的格（不含自己）
static func cells_within(center: Variant, r: int, gw: int, gh: int) -> Array:
	var c := Vector2i(center) if (center is Vector2i or center is Vector2) else BattleViewModel.to_cell(center)
	var out: Array = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d := absi(dx) + absi(dy)
			var n := c + Vector2i(dx, dy)
			if d >= 1 and d <= r and n.x >= 0 and n.y >= 0 and n.x < gw and n.y < gh:
				out.append(n)
	return out

## 輪到我：頭上閃三次黃色菱形
func flash_turn() -> void:
	turn_flash_until = now_s() + TURN_FLASH_S
	if fx != null and vm != null and sprites.has(vm.my_uid):
		fx.drop_words(sprites[vm.my_uid])

func grid_w() -> int:
	return vm.w if vm else UiKeys.GRID_W

func grid_h() -> int:
	return vm.h if vm else UiKeys.GRID_H

func in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < grid_w() and c.y < grid_h()

# ---------- 投影 ----------
## 在 area 內放得下整個菱形格（含頭頂／腳下空間）並置中；回傳 { tile_w, origin }
static func fit(area: Vector2, gw: int, gh: int) -> Dictionary:
	var span := float(gw + gh) / 2.0                  # 菱形總寬 = span 個格寬，總高 = span / 2 個格寬
	var tw := minf(area.x * SIDE_FILL / span, area.y / (span * 0.5 + HEAD_ROOM + FOOT_ROOM))
	tw = maxf(tw, 8.0)
	var total_h := (span * 0.5 + HEAD_ROOM + FOOT_ROOM) * tw
	var top := (area.y - total_h) / 2.0 + HEAD_ROOM * tw
	var left := (area.x - span * tw) / 2.0
	return { "tile_w": tw, "origin": Vector2(left + float(gh) * tw / 2.0, top + tw / 4.0) }

## 連續格座標 → 本地像素（格心在整數座標）
static func project(g: Vector2, org: Vector2, tw: float) -> Vector2:
	return org + Vector2((g.x - g.y) * tw / 2.0, (g.x + g.y) * tw / 4.0)

## 本地像素 → 連續格座標（project 的反函數）
static func unproject(p: Vector2, org: Vector2, tw: float) -> Vector2:
	var d := p - org
	var a := d.x / (tw / 2.0)       # x - y
	var b := d.y / (tw / 4.0)       # x + y
	return Vector2((a + b) / 2.0, (b - a) / 2.0)

func _layout() -> void:
	var f := BattleIsoView.fit(size, grid_w(), grid_h())
	tile_w = f["tile_w"]
	origin = f["origin"]

func grid_to_local(g: Vector2) -> Vector2:
	return BattleIsoView.project(g, origin, tile_w)

func cell_center(c: Vector2i) -> Vector2:
	_layout()
	return grid_to_local(Vector2(c))

## 菱形精準點選：反投影後四捨五入；格外回 (-1,-1)
func cell_at(local: Vector2) -> Vector2i:
	_layout()
	var g := BattleIsoView.unproject(local, origin, tile_w)
	var c := Vector2i(floori(g.x + 0.5), floori(g.y + 0.5))
	return c if in_grid(c) else Vector2i(-1, -1)

func diamond(center: Vector2, inset := 1.0) -> PackedVector2Array:
	var hw := tile_w / 2.0 * inset
	var hh := tile_w / 4.0 * inset
	return PackedVector2Array([center + Vector2(0, -hh), center + Vector2(hw, 0), center + Vector2(0, hh), center + Vector2(-hw, 0)])

## 依 x+y 由遠到近排序（同深度依 y、再依 uid）。倒下的單位一律先畫（屍體平躺在地上，
## 是地面的一部分：前一格的屍體不會蓋到後一格活人的腳與氣條）
static func depth_order(entries: Dictionary, down: Dictionary = {}) -> Array:
	var keys: Array = entries.keys()
	keys.sort_custom(func(a, b):
		var la: bool = down.get(a, false)
		var lb: bool = down.get(b, false)
		if la != lb:
			return la
		var ga: Vector2 = entries[a]
		var gb: Vector2 = entries[b]
		var da := ga.x + ga.y
		var db := gb.x + gb.y
		if not is_equal_approx(da, db):
			return da < db
		if not is_equal_approx(ga.y, gb.y):
			return ga.y < gb.y
		return int(a) < int(b))
	return keys

# ---------- 美術登錄（ArtRegistry，data/art.json）----------
## unit_ref：ArtRegistry.ref_for_unit（玩家 look、怪物／NPC ref）；舊快照沒有 ref 時用名字對回資料表
static func unit_ref(u: Dictionary) -> String:
	var r := ArtRegistry.ref_for_unit(u)
	if r != "":
		return r
	return BattleIsoView.ref_from_name(u)

## 怪物／NPC 名字對回資料 id（同名多隻的「野兔甲」取最長前綴）；找不到回 ""
static func ref_from_name(u: Dictionary) -> String:
	var name := str(u.get("name", ""))
	var tree := Engine.get_main_loop() as SceneTree
	var gd: Node = tree.root.get_node_or_null("GameData") if tree != null and tree.root != null else null
	if gd == null or name == "":
		return ""
	var best := ""
	var best_len := 0
	for table in ["monsters", "npcs"]:
		var rows: Dictionary = gd.tables.get(table, {})
		for id in rows:
			var n := str((rows[id] as Dictionary).get("name", ""))
			if n != "" and name.begins_with(n) and n.length() > best_len:
				best = str(id)
				best_len = n.length()
	return best

static func unit_texture(u: Dictionary, pose: String) -> Texture2D:
	return ArtRegistry.unit_texture(BattleIsoView.unit_ref(u), str(u.get("kind", "")), pose)

static func unit_display(u: Dictionary) -> Dictionary:
	return ArtRegistry.unit_display(BattleIsoView.unit_ref(u))

# ---------- 單位同步 ----------
func _sync_units() -> void:
	if vm == null:
		return
	for uid in vm.order:
		if sprites.has(uid):
			continue
		var u: Dictionary = vm.units[uid]
		var s := UnitSprite.new()
		s.name = "Unit%d" % int(uid)
		units_layer.add_child(s)
		s.setup(u, int(u["side"]) == vm.my_side())
		s.is_me = uid == vm.my_uid
		s.tile_w = tile_w
		s.gpos = Vector2(u["pos"])
		s.shown_qi = int(u.get("qi", 0))
		s.snap_state(str(u.get("state", "")))
		sprites[uid] = s
	for uid in sprites:
		_face_enemies(uid)

func _screen_x(g: Vector2) -> float:
	return g.x - g.y

## 開場：面向敵方（敵方平均位置在右邊就翻轉）
func _face_enemies(uid: int) -> void:
	var s: UnitSprite = sprites[uid]
	var me_side := int(vm.unit(uid).get("side", 0))
	var sum := 0.0
	var n := 0
	for o in vm.order:
		if int(vm.unit(o).get("side", 0)) != me_side and vm.is_active(o):
			sum += _screen_x(Vector2(vm.unit(o)["pos"]))
			n += 1
	if n > 0:
		var dx := sum / n - _screen_x(s.gpos)
		if absf(dx) > 0.01:
			s.facing_right = dx > 0.0

## 閒著時面向最近的敵人（移動完、對手繞到身後也會轉回來）
func _face_nearest(uid: int) -> void:
	var s: UnitSprite = sprites[uid]
	var me_side := int(vm.unit(uid).get("side", 0))
	var best := INF
	var target := Vector2.ZERO
	for o in vm.order:
		if o == uid or int(vm.unit(o).get("side", 0)) == me_side or not vm.is_active(o):
			continue
		var g := Vector2(vm.unit(o)["pos"])
		var d := g.distance_squared_to(s.gpos)
		if d < best:
			best = d
			target = g
	if best < INF:
		_face_toward(s, target)

func _face_toward(s: UnitSprite, target: Vector2) -> void:
	var dx := _screen_x(target) - _screen_x(s.gpos)
	if absf(dx) > 0.01:
		s.facing_right = dx > 0.0

static func now_s() -> float:
	return Time.get_ticks_msec() / 1000.0

func _process(_delta: float) -> void:
	if vm == null:
		return
	_layout()
	var now := now_s()
	var t_my_turn := vm.is_my_turn(now_tick)
	var pos: Dictionary = {}
	var down: Dictionary = {}
	for uid in sprites:
		var s: UnitSprite = sprites[uid]
		var u: Dictionary = vm.unit(uid)
		s.tile_w = tile_w
		if now >= s.locked_until:
			s.gpos = Vector2(u.get("pos", Vector2i.ZERO))
			s.shown_qi = int(u.get("qi", 0))
			s.snap_state(str(u.get("state", "")))
			if s.vis_state == "ALIVE":
				_face_nearest(uid)
		s.qi_max = maxi(1, int(u.get("qi_max", 1)))
		s.vm_qi = int(u.get("qi", 0)) if s.vis_state == "ALIVE" else 0
		s.gauge = vm.gauge_at(uid, now_tick) / UiKeys.GAUGE_FULL
		s.is_me = uid == vm.my_uid
		s.my_turn = s.is_me and t_my_turn
		s.awaiting = vm.await_units.has(uid) and not s.is_me
		s.position = grid_to_local(s.gpos)
		pos[uid] = s.gpos
		down[uid] = s.vis_state != "ALIVE"
	# 有活人站在屍體同一格（例如敵人踩在我的屍體上）：屍體往前挪，露出來
	for uid in sprites:
		var c: UnitSprite = sprites[uid]
		if c.vis_state == "DEAD" and BattleIsoView.corpse_covered(uid, pos, down):
			c.position += Vector2(0, tile_w * CORPSE_SHIFT)
	var ordered := BattleIsoView.depth_order(pos, down)
	# 戰敗畫面（審查 round 3）：自己的屍體畫在最上面，不被站在前一格的兇手蓋住
	var mine: UnitSprite = sprites.get(vm.my_uid, null)
	if vm.ended and mine != null and mine.vis_state == "DEAD" and ordered.has(vm.my_uid):
		ordered.erase(vm.my_uid)
		ordered.append(vm.my_uid)
	for i in ordered.size():
		var sp: UnitSprite = sprites[ordered[i]]
		sp.depth = i + 1
		if sp.get_index() != i:
			units_layer.move_child(sp, i)
	_update_xray()
	queue_redraw()

## 屍體這一格（四捨五入）是否有活人站著
static func corpse_covered(uid: int, pos: Dictionary, down: Dictionary) -> bool:
	var cell := Vector2i(roundi((pos[uid] as Vector2).x), roundi((pos[uid] as Vector2).y))
	for o in pos:
		if o != uid and not bool(down.get(o, false)):
			var g: Vector2 = pos[o]
			if Vector2i(roundi(g.x), roundi(g.y)) == cell:
				return true
	return false

## 透視：畫在我前面、身體擋到我（站著或倒地）的單位變半透明，玩家永遠看得到自己在哪、躺在哪；
## 擋住我方屍體的活人也變半透明（倒下的人一定看得到）
func _update_xray() -> void:
	var me: UnitSprite = sprites.get(vm.my_uid, null)
	var mine := Rect2()
	if me != null and me.shows_label():
		mine = me.self_rect(me.position)
	var dead := me != null and me.vis_state != "ALIVE"
	var corpses: Array = []
	for uid in sprites:
		var c: UnitSprite = sprites[uid]
		if c != me and c.vis_state == "DEAD" and c.ally and c.visible:
			corpses.append(c.self_rect(c.position))
	for uid in sprites:
		var s: UnitSprite = sprites[uid]
		var want := 1.0
		if s != me and s.vis_state == "ALIVE":
			var body := s.body_rect(s.position + s.anim_offset)
			if me != null and mine.size != Vector2.ZERO and s.depth > me.depth:
				var cover := body.intersection(mine)
				if cover.get_area() >= mine.get_area() * XRAY_COVER:
					want = XRAY_DEAD if dead else XRAY_ALPHA
			for r in corpses:
				var cr: Rect2 = r
				if body.intersection(cr).get_area() >= cr.get_area() * XRAY_COVER * 2.0:
					want = minf(want, XRAY_DEAD)
		s.xray_target = want

# ---------- 輸入 ----------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c := cell_at(event.position)
		if c != hover_cell:
			hover_cell = c
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := cell_at(event.position)
		if vm and vm.in_grid(c):
			cell_clicked.emit(c)
			accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover_cell != Vector2i(-1, -1):
		hover_cell = Vector2i(-1, -1)
		queue_redraw()
	elif what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()

# ---------- 繪製 ----------
func _draw() -> void:
	_layout()
	_draw_background()
	var gw := grid_w()
	var gh := grid_h()
	# 整塊地面微暗，讓格子與人物在亮背景上也看得清楚
	var outer := PackedVector2Array([grid_to_local(Vector2(-0.5, -0.5)), grid_to_local(Vector2(gw - 0.5, -0.5)),
		grid_to_local(Vector2(gw - 0.5, gh - 0.5)), grid_to_local(Vector2(-0.5, gh - 0.5))])
	_draw_walls(gw, gh)
	draw_colored_polygon(outer, GRID_FILL)
	if vm != null:
		var pulse := 0.5 + 0.5 * sin(now_s() * 3.0)
		for c in vm.escape:
			_draw_escape(c, pulse)
	# 格線：深色線＋下方 1px 亮邊（像刻在地上），亮暗背景都看得到；特殊開關可以關掉
	for x in range(1, gw if show_grid else 1):
		var a := grid_to_local(Vector2(x - 0.5, -0.5))
		var b := grid_to_local(Vector2(x - 0.5, gh - 0.5))
		draw_line(a, b, GRID_EDGE, 1.2, true)
		draw_line(a + Vector2(0, 1), b + Vector2(0, 1), GRID_EDGE_HI, 1.0, true)
	for y in range(1, gh if show_grid else 1):
		var a := grid_to_local(Vector2(-0.5, y - 0.5))
		var b := grid_to_local(Vector2(gw - 0.5, y - 0.5))
		draw_line(a, b, GRID_EDGE, 1.2, true)
		draw_line(a + Vector2(0, 1), b + Vector2(0, 1), GRID_EDGE_HI, 1.0, true)
	if vm != null:
		var pulse2 := 0.5 + 0.5 * sin(now_s() * 3.0)
		for c in vm.escape:
			_draw_escape_edge(c, pulse2)
	var closed := outer.duplicate()
	closed.append(outer[0])
	draw_polyline(closed, Color(0, 0, 0, 0.35), 3.5, true)
	draw_polyline(closed, GRID_BORDER, 1.5, true)
	var redge := Color(UiTheme.HIGHLIGHT_RANGE, 0.9)
	for c in range_cells:
		if highlight.has(c):
			continue
		var rc := grid_to_local(Vector2(c))
		draw_colored_polygon(diamond(rc, 0.94), UiTheme.HIGHLIGHT_RANGE)
		_outline(diamond(rc, 0.94), redge, 1.5)
	var edge := Color(highlight_color, minf(1.0, highlight_color.a * 2.0))
	for c in highlight:
		var center := grid_to_local(Vector2(c))
		draw_colored_polygon(diamond(center, 0.94), highlight_color)
		_outline(diamond(center, 0.94), edge, 2.0)
	# 陣法站位：金框；缺人的格閃爍
	var blink := 0.35 + 0.65 * (0.5 + 0.5 * sin(now_s() * 6.0))
	for c in station_cells:
		var sc := grid_to_local(Vector2(c))
		var miss: bool = station_missing.has(c)
		var col := Color(UiTheme.JY_GOLD, blink if miss else 0.95)
		_outline(diamond(sc, 0.9), col, 3.0)
		if miss:
			draw_colored_polygon(diamond(sc, 0.9), Color(UiTheme.HIGHLIGHT_STATION, UiTheme.HIGHLIGHT_STATION.a * blink))
	# 範圍招式預覽（半透明）與剛打到的格
	for c in preview_cells:
		draw_colored_polygon(diamond(grid_to_local(Vector2(c)), 0.8), UiTheme.HIGHLIGHT_AOE)
	if now_s() < aoe_flash_until:
		var fa := clampf((aoe_flash_until - now_s()) / AOE_FLASH_S, 0.0, 1.0)
		for c in aoe_flash:
			draw_colored_polygon(diamond(grid_to_local(Vector2(c)), 0.86), Color(UiTheme.HIGHLIGHT_AOE, 0.45 * fa))
	# M3d 審查：「閃」的架勢（到自己下次行動前）——腳下青色菱形＋淡填色，一眼看得出誰在閃
	if vm != null:
		var dp := 0.6 + 0.4 * sin(now_s() * 4.0)
		for uid in sprites:
			if not vm.is_dodging(int(uid)):
				continue
			var ds: UnitSprite = sprites[uid]
			if not is_instance_valid(ds) or not ds.visible:
				continue
			var dc := ds.position
			draw_colored_polygon(diamond(dc, 0.86), Color(BattleFx.DODGE_COLOR, 0.18 * dp))
			_outline(diamond(dc, 0.86), Color(BattleFx.DODGE_COLOR, 0.9 * dp), 2.5)
	# 行動中（輪到我）：腳下白色雙線菱形
	if my_turn_ring_visible():
		var mc := my_turn_ring_center()
		_outline(diamond(mc, 0.98), Color(1, 1, 1, 0.95), 1.5)
		_outline(diamond(mc, 0.78), Color(1, 1, 1, 0.95), 1.5)
	# 游標：黃色細菱形外框、不填色；只在要選格子時（移／攻／武有高亮）才畫
	if in_grid(hover_cell) and not highlight.is_empty():
		var hc := grid_to_local(Vector2(hover_cell))
		var hot := highlight.has(hover_cell)
		_outline(diamond(hc, 0.96), HOVER_EDGE, 2.0 if hot else 1.5)

## 「輪到我」的腳下白色雙線菱形：只在我的人物靜止時畫，而且畫在人物現在站的格子。
## M3c 第三輪審查：以前用 VM 的格子（事件一到就是新位置）——出招前衝、走路動畫還沒播完時，菱形畫在人物身後的格子，
## 被身體擋住只露出左右兩角，看起來像刀特效後面一個白色箭頭（117_m3c_weapon_fx_blade）
func my_turn_ring_visible() -> bool:
	if vm == null or vm.ended or not vm.is_my_turn(now_tick):
		return false
	var s: UnitSprite = sprites.get(vm.my_uid, null)
	if s == null:
		return true
	return now_s() >= s.locked_until and s.anim_offset.length() < 0.5

func my_turn_ring_center() -> Vector2:
	var s: UnitSprite = sprites.get(vm.my_uid, null)
	if s != null:
		return grid_to_local(s.gpos)
	return grid_to_local(Vector2(vm.me().get("pos", Vector2i.ZERO)))

func _outline(pts: PackedVector2Array, col: Color, width: float) -> void:
	var p := pts.duplicate()
	p.append(pts[0])
	draw_polyline(p, col, width, true)

## 逃跑格（原作）：白色「逃」字平貼在地上（等角變形：轉 45° 再壓扁一半），畫在格線下；白色雙線菱形外框畫在格線上
func _draw_escape(c: Vector2i, _pulse: float) -> void:
	var center := grid_to_local(Vector2(c))
	draw_colored_polygon(diamond(center, 0.94), Color(1, 1, 1, 0.08))
	var font := UnitSprite.ui_font()
	if font == null:
		return
	var fs := int(clampf(tile_w * 0.36, 12.0, 40.0))
	var tw := font.get_string_size("逃", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var k := 0.7071
	draw_set_transform_matrix(Transform2D(Vector2(k, k * 0.5), Vector2(-k, k * 0.5), center))
	var p := Vector2(-tw / 2.0, fs * 0.36)
	draw_string_outline(font, p, "逃", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, fs / 8), Color(0, 0, 0, 0.45))
	draw_string(font, p, "逃", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ESCAPE_INK, 0.95))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_escape_edge(c: Vector2i, pulse: float) -> void:
	var center := grid_to_local(Vector2(c))
	_outline(diamond(center, 0.95), Color(0, 0, 0, 0.35), 3.5)
	_outline(diamond(center, 0.95), Color(ESCAPE_EDGE, 0.8 + 0.2 * pulse), 1.5)
	_outline(diamond(center, 0.78), Color(ESCAPE_EDGE, 0.8 + 0.2 * pulse), 1.5)

## 石台側壁：左下、右下兩面，土色漸層，厚約 0.35 格高
func _draw_walls(gw: int, gh: int) -> void:
	var lft := grid_to_local(Vector2(-0.5, gh - 0.5))
	var bot := grid_to_local(Vector2(gw - 0.5, gh - 0.5))
	var rgt := grid_to_local(Vector2(gw - 0.5, -0.5))
	var dh := Vector2(0, tile_w * WALL_H)
	draw_polygon(PackedVector2Array([lft, bot, bot + dh, lft + dh]),
		PackedColorArray([WALL_TOP, WALL_TOP, WALL_BOTTOM, WALL_BOTTOM]))
	var side := WALL_TOP.darkened(0.15)
	var side_b := WALL_BOTTOM.darkened(0.15)
	draw_polygon(PackedVector2Array([bot, rgt, rgt + dh, bot + dh]), PackedColorArray([side, side, side_b, side_b]))
	draw_polyline(PackedVector2Array([lft + dh, bot + dh, rgt + dh]), Color(0, 0, 0, 0.5), 1.5, true)


## 背景：有圖就等比放大到蓋滿（cover）；沒圖畫地區色調的程式地面
func _draw_background() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if bg_tex != null:
		var ts := bg_tex.get_size()
		var k := maxf(size.x / ts.x, size.y / ts.y)
		var ds := ts * k
		draw_texture_rect(bg_tex, Rect2((size - ds) / 2.0, ds), false)
		return
	var pal := BattleIsoView.region_palette(region_id)
	draw_rect(r, pal[0])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(region_id) + 7
	var big := maxf(size.x, size.y)
	for i in 70:
		var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var rad := big * rng.randf_range(0.02, 0.07)
		var col: Color = pal[1] if rng.randf() < 0.6 else pal[2]
		draw_set_transform(p, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, rad, Color(col, rng.randf_range(0.18, 0.4)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 上方遠景較暗、四周暗角
	var band := size.y * 0.3
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, band), Vector2(0, band)]),
		PackedColorArray([Color(pal[3], 0.75), Color(pal[3], 0.75), Color(pal[3], 0.0), Color(pal[3], 0.0)]))
	var side := size.x * 0.12
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(side, 0), Vector2(side, size.y), Vector2(0, size.y)]),
		PackedColorArray([Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.3)]))
	draw_polygon(PackedVector2Array([Vector2(size.x - side, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(size.x - side, size.y)]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0)]))

## [地面, 斑塊1, 斑塊2, 遠景]
static func region_palette(rid: String) -> Array:
	if rid.begins_with("xixia"):
		return [Color("b59d68"), Color("9c8450"), Color("8e9655"), Color("6d5a3a")]
	if rid.begins_with("jingcheng"):
		return [Color("7f9a5c"), Color("6c8a4a"), Color("9a8f62"), Color("3f5a3a")]
	if rid.begins_with("dali"):
		return [Color("6f9c6c"), Color("5d8a5c"), Color("8fae7a"), Color("4a6f78")]
	if rid.begins_with("guiwang"):
		return [Color("2f3b3a"), Color("26302f"), Color("3d5550"), Color("101615")]
	if rid.begins_with("huashan"):
		return [Color("8d8b84"), Color("7a7870"), Color("9d9a90"), Color("c9d2d8")]
	if rid.begins_with("shaolin"):
		return [Color("9c968a"), Color("8a8478"), Color("aaa496"), Color("7a3a2a")]
	return [Color("8d8a62"), Color("7a7850"), Color("9a9470"), Color("4a4a38")]

# ---------- 事件 → 動畫（只看事件內容，不改 VM）----------
func on_event(e: Dictionary) -> void:
	if vm == null or str(e.get("ch", "")) != UiKeys.CH_BATTLE:
		return
	_sync_units()
	_play_event(e)
	if vm.ended:
		settle(false)   # 結果視窗已經出來後才到的最後幾個事件：飄字照放，人直接停在最後的樣子（倒下的就躺著）

func _play_event(e: Dictionary) -> void:
	var p: Dictionary = e.get("p", {})
	var key := str(e.get("key", ""))
	match key:
		UiKeys.E_BATTLE_GAUGES, UiKeys.E_BATTLE_AWAIT, UiKeys.E_BATTLE_END, UiKeys.E_BATTLE_CRIT, UiKeys.E_BATTLE_COUNTER, \
				UiKeys.E_BATTLE_TIMEOUT, UiKeys.E_BATTLE_STATUS_OFF, UiKeys.E_BATTLE_EQUIP:
			pass
		UiKeys.E_BATTLE_MOVE:
			_anim_move(int(p.get("uid", 0)), BattleViewModel.to_cell(p.get("from", [])), BattleViewModel.to_cell(p.get("to", [])))
		UiKeys.E_BATTLE_MISS:
			_anim_strike(int(p.get("atk_uid", 0)), int(p.get("def_uid", 0)), -1, false, key, -1, e)
		UiKeys.E_BATTLE_DEFEND:
			var s := _sprite(int(p.get("uid", 0)))
			if s:
				var t := _start_for([s])
				fx.shield(s, t - now_s())
				s.ready_at = maxf(s.ready_at, t + 0.3)
		UiKeys.E_BATTLE_REST:
			var s := _sprite(int(p.get("uid", 0)))
			if s:
				var t := _start_for([s])
				fx.popup(s, "調息", BattleFx.REST_COLOR, 1.0, t - now_s())
				if int(p.get("qi_gain", 0)) > 0:
					fx.popup(s, "+%d" % int(p.get("qi_gain", 0)), BattleFx.HEAL_COLOR, 0.9, t - now_s() + 0.25)
				s.ready_at = maxf(s.ready_at, t + 0.4)
		UiKeys.E_BATTLE_PROC_RECOVER:
			var s := _sprite(int(p.get("uid", 0)))
			if s and int(p.get("qi_gain", 0)) > 0:
				fx.popup(s, "+%d" % int(p.get("qi_gain", 0)), BattleFx.HEAL_COLOR, 0.9, maxf(0.0, s.ready_at - now_s()))
		UiKeys.E_BATTLE_STATUS_ON:
			var s := _sprite(int(p.get("uid", 0)))
			if s:
				fx.popup(s, str(p.get("status_name", "")), BattleFx.STATUS_COLOR, 0.75, maxf(0.0, s.ready_at - now_s()) + 0.1)
		UiKeys.E_BATTLE_AOE:
			aoe_flash = []
			for c in p.get("cells", []):
				aoe_flash.append(BattleViewModel.to_cell(c))
			aoe_flash_until = now_s() + AOE_FLASH_S
		UiKeys.E_BATTLE_MEDIC, UiKeys.E_BATTLE_ITEM_USE, UiKeys.E_BATTLE_INNER_TRANSFER:
			var s := _sprite(int(p.get("def_uid", p.get("uid", 0))))
			if s:
				var t := _start_for([s])
				var word := "+%d" % int(p.get("heal", 0)) if int(p.get("heal", 0)) > 0 else str(p.get("item_name", "內力"))
				fx.popup(s, word, BattleFx.HEAL_COLOR, 0.9, t - now_s())
				if key != UiKeys.E_BATTLE_ITEM_USE:
					_weapon_fx(e, int(p.get("atk_uid", 0)), int(p.get("def_uid", 0)), t - now_s() + WeaponFx.LEAD, false)   # M3c WP-FX：醫、傳功
				s.ready_at = maxf(s.ready_at, t + 0.3)
		UiKeys.E_BATTLE_INNER_HEAL:
			var s := _sprite(int(p.get("uid", 0)))
			if s:
				var t := _start_for([s])
				fx.popup(s, "運功", BattleFx.REST_COLOR, 1.0, t - now_s())
				if int(p.get("heal", 0)) > 0:
					fx.popup(s, "+%d" % int(p.get("heal", 0)), BattleFx.HEAL_COLOR, 0.9, t - now_s() + 0.25)
				s.ready_at = maxf(s.ready_at, t + 0.4)
		UiKeys.E_BATTLE_INNER_EXPEL, UiKeys.E_BATTLE_INNER_UNSEAL_OK, UiKeys.E_BATTLE_INNER_UNSEAL_FAIL, \
				UiKeys.E_BATTLE_STATUS_SKIP, UiKeys.E_BATTLE_CONFUSED, UiKeys.E_BATTLE_FORMATION_ON, UiKeys.E_BATTLE_WAVE:
			var s := _sprite(int(p.get("uid", 0)))
			if s:
				var words := { UiKeys.E_BATTLE_INNER_EXPEL: "逼毒", UiKeys.E_BATTLE_INNER_UNSEAL_OK: "衝開穴道",
					UiKeys.E_BATTLE_INNER_UNSEAL_FAIL: "衝穴不成", UiKeys.E_BATTLE_STATUS_SKIP: str(p.get("status_name", "動彈不得")),
					UiKeys.E_BATTLE_CONFUSED: "混亂", UiKeys.E_BATTLE_FORMATION_ON: "結陣" }
				fx.popup(s, str(words.get(key, "")), BattleFx.STATUS_COLOR, 0.8, maxf(0.0, s.ready_at - now_s()))
				if key == UiKeys.E_BATTLE_FORMATION_ON:
					_weapon_fx(e, int(p.get("uid", 0)), 0, maxf(0.0, s.ready_at - now_s()) + WeaponFx.LEAD, false)   # M3c WP-FX：陣法地紋
		UiKeys.E_BATTLE_POISON_TICK:
			var s := _sprite(int(p.get("uid", 0)))
			if s:
				var t := _start_for([s])
				s.play_hurt(Vector2.ZERO, t - now_s(), int(p.get("qi", s.shown_qi)))
				fx.popup(s, "-%d" % int(p.get("dmg", 0)), Color("7ddc6e"), 1.0, t - now_s())
		UiKeys.E_BATTLE_HIDDEN_MISS:
			_anim_strike(int(p.get("atk_uid", 0)), int(p.get("def_uid", 0)), -1, false, key, -1, e)
		UiKeys.E_BATTLE_POISON_FAIL, UiKeys.E_BATTLE_ACUPOINT_FAIL:
			_anim_cast(int(p.get("atk_uid", 0)), int(p.get("def_uid", 0)), "無效", e, true)
		UiKeys.E_BATTLE_ACUPOINT_OK:
			_anim_cast(int(p.get("atk_uid", 0)), int(p.get("def_uid", 0)), "封穴", e, false)
		UiKeys.E_BATTLE_WOUND_TICK:
			var s := _sprite(int(p.get("uid", 0)))
			if s:
				var t := _start_for([s])
				s.play_hurt(Vector2.ZERO, t - now_s(), int(p.get("qi", s.shown_qi)))
				fx.popup(s, "-%d" % int(p.get("dmg", 0)), BattleFx.WOUND_COLOR, 1.0, t - now_s())
		UiKeys.E_BATTLE_FLEE:
			var s := _sprite(int(p.get("uid", 0)))
			if s:
				s.play_flee(_start_for([s]) - now_s())
		# ---- M3d（M3D_PLAN §3.1–3.3；WP-COMBAT） ----
		UiKeys.E_BATTLE_DODGE:
			var s := _sprite(int(p.get("uid", 0)))
			if s:
				fx.popup(s, "閃避", BattleFx.DODGE_COLOR, 1.4, _start_for([s]) - now_s())   # M3d 審查：原本白色小字看不清
		UiKeys.E_BATTLE_QING_JUMP:
			# 飛身越敵：直線一躍（越過中間的人），不走 BFS 路徑
			var s := _sprite(int(p.get("uid", 0)))
			var fc := BattleViewModel.to_cell(p.get("from", []))
			var tc := BattleViewModel.to_cell(p.get("to", []))
			if s and in_grid(fc) and in_grid(tc):
				var t := _start_for([s])
				s.play_move([Vector2(fc), Vector2(tc)], t - now_s(), STEP_DUR * 1.5)
				fx.popup(s, "輕功", BattleFx.REST_COLOR, 0.9, t - now_s())
		UiKeys.E_BATTLE_QING_ESCAPE:
			var s := _sprite(int(p.get("uid", 0)))
			if s:
				var t := _start_for([s])
				fx.popup(s, "脫身", BattleFx.REST_COLOR, 0.9, t - now_s())
				s.play_flee(t - now_s())
		UiKeys.E_BATTLE_QING_FAIL:
			var s := _sprite(int(p.get("uid", 0)))
			if s:
				fx.popup(s, "走不脫", BattleFx.STATUS_COLOR, 0.85, _start_for([s]) - now_s())
		UiKeys.E_BATTLE_COMBO:
			var a := _sprite(int(p.get("a_uid", p.get("atk_uid", 0))))
			var b := _sprite(int(p.get("b_uid", 0)))
			var d := _sprite(int(p.get("def_uid", 0)))
			var t0 := _start_for([a, b, d])
			fx.combo(a, b, d, UiKeys.COMBO_BANNER_FMT % str(p.get("art_name", "")), t0 - now_s())
			_anim_strike(int(p.get("atk_uid", 0)), int(p.get("def_uid", 0)), int(p.get("dmg", 0)), true, key,
				int(p.get("def_qi", -1)), e)
		UiKeys.E_BATTLE_KILL, UiKeys.E_BATTLE_DEATH:
			var s := _sprite(int(p.get("uid", 0)))
			if s:
				s.play_death(_start_for([s]) - now_s())
		_:
			if UiKeys.is_hit_event(e):
				_anim_strike(int(p.get("atk_uid", 0)), int(p.get("def_uid", 0)), int(p.get("dmg", 0)),
					bool(p.get("crit", false)), key, int(p.get("def_qi", -1)), e)
			elif key.begins_with(UiKeys.BATTLE_PROC_PREFIX) and key != UiKeys.E_BATTLE_PROC_DEFENSE and str(p.get("skill_name", "")) != "":
				# 門派技能觸發（§5.6）：頭上飄技能名
				var s := _sprite(int(p.get("uid", 0)))
				if s:
					fx.popup(s, str(p.get("skill_name", "")), BattleFx.STATUS_COLOR, 0.8, maxf(0.0, s.ready_at - now_s()))

## 戰鬥結束：丟掉排隊中的動畫，每個人回到自己的格子；已倒下的立刻躺下、逃走的消失
func settle(drop_popups := true) -> void:
	if vm == null:
		return
	for uid in sprites:
		var s: UnitSprite = sprites[uid]
		var u: Dictionary = vm.unit(uid)
		var st := str(u.get("state", ""))
		s.cancel_anims()
		s.gpos = Vector2(u.get("pos", Vector2i.ZERO))
		s.shown_qi = int(u.get("qi", 0))
		s.snap_state(st)
	if drop_popups:
		fx.drop_pending()

func _sprite(uid: int) -> UnitSprite:
	return sprites.get(uid, null)

## 動畫起點：等相關單位的上一段動畫做完；落後太多就丟掉排隊、從現在開始
func _start_for(list: Array) -> float:
	var now := now_s()
	var t := now
	for s in list:
		if s != null:
			t = maxf(t, (s as UnitSprite).ready_at)
	if t - now > MAX_BACKLOG:
		for s in list:
			if s != null:
				(s as UnitSprite).cancel_anims()
		t = now
	return t

func _anim_move(uid: int, from: Vector2i, to: Vector2i) -> void:
	var s := _sprite(uid)
	if s == null or not in_grid(from) or not in_grid(to):
		return
	var t := _start_for([s])
	var path := path_between(from, to, uid)
	var pts: Array = []
	for c in path:
		pts.append(Vector2(c))
	s.play_move(pts, t - now_s(), STEP_DUR)

## 移動路徑：4 方向 BFS，避開其他存活單位（與 VM.move_targets 同規則）；找不到就走 L 形
func path_between(from: Vector2i, to: Vector2i, mover: int) -> Array:
	var blocked := {}
	if vm != null:
		for uid in vm.order:
			if uid != mover and vm.is_active(uid):
				blocked[vm.units[uid]["pos"]] = true
	var prev := { from: from }
	var queue: Array = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == to:
			break
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + off
			if not in_grid(n) or prev.has(n) or (blocked.has(n) and n != to):
				continue
			prev[n] = c
			queue.append(n)
	var out: Array = []
	if prev.has(to):
		var c := to
		while c != from:
			out.push_front(c)
			c = prev[c]
		out.push_front(from)
		return out
	out = [from]
	var cur := from
	while cur.x != to.x:
		cur.x += signi(to.x - cur.x)
		out.append(cur)
	while cur.y != to.y:
		cur.y += signi(to.y - cur.y)
		out.append(cur)
	return out

## 出手：攻方面向目標前衝再退回；命中時守方閃紅、擊退、飄傷害；未命中守方側閃、飄「閃」
## 不帶傷害的出手（點穴、下毒失手）：出手者前衝，目標頭上飄字
func _anim_cast(atk_uid: int, def_uid: int, word: String, e: Dictionary = {}, failed := false) -> void:
	var a := _sprite(atk_uid)
	var d := _sprite(def_uid)
	if a == null and d == null:
		return
	var t := _start_for([a, d])
	if a != null and d != null:
		_face_toward(a, d.gpos)
		var dir := (grid_to_local(d.gpos) - grid_to_local(a.gpos)).normalized()
		a.play_lunge(dir * tile_w * 0.2, t - now_s(), LUNGE_DUR)
	if d != null:
		fx.popup(d, word, BattleFx.STATUS_COLOR, 0.9, t - now_s() + IMPACT_AT)
	if not e.is_empty():
		_weapon_fx(e, atk_uid, def_uid, t - now_s() + (IMPACT_AT if a != null else 0.0), failed)

## ---------------------------------------------------------------- M3c WP-FX：武器出招特效（M3C_PLAN §7）
## 依事件與攻擊者（快照 wtype／wfx、事件 cat）選特效並排進 BattleFx；impact_delay = 命中時刻距現在幾秒。
## 回傳是否畫了武器特效（""＝非人形怪的一般攻擊：呼叫端照舊畫打擊火花）
func _weapon_fx(e: Dictionary, atk_uid: int, def_uid: int, impact_delay: float, miss: bool) -> bool:
	if vm == null or fx == null:
		return false
	var a := _sprite(atk_uid)
	var d := _sprite(def_uid)
	var kind := WeaponFx.kind_for(vm.unit(atk_uid), e, a.is_humanoid() if a != null else false)
	if kind == "":
		return false
	match WeaponFx.placement(kind):
		"target":
			if d == null:
				return false
			fx.weapon(null, d, kind, impact_delay, miss)
		"ground":
			if a == null:
				return false
			fx.weapon(a, null, kind, impact_delay, miss)
		_:
			if a == null:
				return false
			fx.weapon(a, d, kind, impact_delay, miss)
	return true

func _anim_strike(atk_uid: int, def_uid: int, dmg: int, crit: bool, key: String, def_qi: int, e: Dictionary = {}) -> void:
	var a := _sprite(atk_uid)
	var d := _sprite(def_uid)
	if a == null and d == null:
		return
	var t := _start_for([a, d])
	var delay := t - now_s()
	var dir := Vector2.ZERO
	if a != null and d != null:
		_face_toward(a, d.gpos)
		_face_toward(d, a.gpos)
		dir = (grid_to_local(d.gpos) - grid_to_local(a.gpos)).normalized()
	if a != null:
		var reach := tile_w * 0.3
		if d != null:
			reach = minf(reach, grid_to_local(d.gpos).distance_to(grid_to_local(a.gpos)) * LUNGE_REACH)
		a.play_lunge(dir * reach, delay, LUNGE_DUR)
	var impact := delay + (IMPACT_AT if a != null else 0.0)
	# M3c WP-FX：人形攻擊者依武器類型／武功類別畫出招特效（未命中也畫，較淡）；非人形怪照舊只有打擊火花
	var drew := false
	if not e.is_empty():
		drew = _weapon_fx(e, atk_uid, def_uid, impact, dmg < 0)
	if d == null:
		return
	if dmg < 0:
		d.play_dodge(Vector2(-dir.y, dir.x) * tile_w * 0.22, impact)
		fx.popup(d, "閃", BattleFx.MISS_COLOR, 1.1, impact)
		return
	d.play_hurt(dir * tile_w * 0.16, impact, def_qi if def_qi >= 0 else d.shown_qi, HURT_DUR)
	if not drew:
		fx.burst(d, BattleFx.burst_kind(key), impact)
	# 我方受傷紅字、敵方受傷金字；爆擊加大加「!」
	var col := BattleFx.DMG_TAKEN_COLOR if d.ally else BattleFx.DMG_COLOR
	if crit:
		fx.popup(d, "-%d!" % dmg, BattleFx.CRIT_COLOR if not d.ally else BattleFx.DMG_TAKEN_COLOR, 1.5, impact)
	else:
		fx.popup(d, "-%d" % dmg, col, 1.1, impact)
