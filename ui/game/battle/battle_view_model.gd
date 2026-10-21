class_name BattleViewModel
extends RefCounted
## 戰鬥畫面模型（M1_PLAN 3.12）：以 battle_state（3.9.3）初始化，套用戰鬥事件（3.8.4）。
## 不做任何遊戲判定，只鏡像主機送來的結果；時間棒在錨點間外插（TECH_ARCH 10.6）。
## M2（M2_PLAN 4.5.3）：my_side == 1（PvP 被叫戰／被強制的一方）時整個戰場左右鏡像 x' = (w − 1) − x，自己永遠在左邊；
## 模型裡存的都是「畫面座標」，事件進來先 localize_event() 轉換，送出的 target 用 to_host_cell() 轉回主機座標。
## battle_unit_join（ui 事件）＝中途加入的新單位：加進 units／order。
## M3a（M3A_PLAN §5、§7）：我的單位快照多了 cmd_avail／cmd_arts／hidden_items／battle_items／formation；每個單位多了
## statuses（[{ id, name, glyph, color, n, level }]，存成 id → 同形字典）。新指令的可用與否只照快照（主機權威），
## 這裡另外算選目標要用的格子：敵格、自己或隊友格、陣法站位、範圍招式（§5.3 的六種形狀）打到的格。

var bid := 0
var w := UiKeys.GRID_W
var h := UiKeys.GRID_H
var my_uid := 0
var kind := ""                      # ENCOUNTER／FIGHT／GUARD／CHALLENGE／FORCED（舊主機沒有 → ""）
var host_side := 0                  # 主機給的 my_side（0／1）
var mirrored := false               # host_side == 1：畫面左右鏡像
var wait_mode := true
var escape: Array = []              # Array[Vector2i]
var units: Dictionary = {}          # uid -> 單位字典（pos 轉成 Vector2i）
var order: Array = []               # uid 依快照順序
var anchor_tick := 0.0              # 最近一次 battle_gauges 的 tick
var anchors: Dictionary = {}        # uid -> { gauge, rate, charging }
var await_units: Array = []         # 正在等待下令的 uid
var deadline_tick := -1
var submitted := false              # 已送出指令、尚未收到下一個錨點
var ended := false
var result := ""
var afk: Dictionary = {}            # uid -> true（連續兩次逾時，TECH_ARCH 10.7 #4）
var _timeouts: Dictionary = {}      # uid -> 連續逾時次數
var later_cmds := true              # 伺服器規則 later_battle_cmds（world_info）；false →「內」「穴」鎖住（§7.1、D9）
var wave := 0                       # 波次（十八銅人，battle_wave）；0 = 沒有波次
var wave_total := 0
var last_aoe: Dictionary = {}       # 最近一次 battle_aoe：{ uid, cells: Array[Vector2i] }（畫面標格子）
var _status_tick_at: Dictionary = {}   # uid -> 上次扣狀態次數時的 anchor_tick（範圍招式一次行動多個事件，只扣一次）
var dodge_cmd := true               # M3d：規則 dodge_cmd（快照 dodge_cmd；舊主機沒有 → 開）
var last_combo: Dictionary = {}     # M3d：最近一次 battle_combo 的 payload（畫面金字與光帶）

## 8 方向（§5.3 LINE／FAN）：由東開始順時針（畫面座標 y 往下）
const DIRS8 := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]

static func from_state(state: Dictionary) -> BattleViewModel:
	var vm := BattleViewModel.new()
	vm.load_state(state)
	return vm

static func to_cell(v: Variant) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Array and v.size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i(-1, -1)

static func cell_arr(c: Vector2i) -> Array:
	return [c.x, c.y]

static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func load_state(state: Dictionary) -> void:
	bid = int(state.get("bid", 0))
	w = int(state.get("w", UiKeys.GRID_W))
	h = int(state.get("h", UiKeys.GRID_H))
	my_uid = int(state.get("my_uid", 0))
	kind = str(state.get("kind", ""))
	wait_mode = bool(state.get("wait_mode", true))
	anchor_tick = float(state.get("tick", 0))
	units.clear()
	order.clear()
	anchors.clear()
	# my_side：主機給的優先；舊主機沒有時看自己單位的 side
	host_side = int(state.get("my_side", -1))
	if host_side < 0:
		host_side = 0
		for u in state.get("units", []):
			if u is Dictionary and int(u.get("uid", 0)) == my_uid:
				host_side = int(u.get("side", 0))
	mirrored = host_side == 1
	# M3a：波次（十八銅人）與 later_battle_cmds（主機的戰鬥選項；沒有時由戰鬥畫面依 world_info 設定）
	var wv: Variant = state.get("wave", {})
	if wv is Dictionary:
		wave = int(wv.get("n", 0))
		wave_total = int(wv.get("total", 0))
	if state.has("later_battle_cmds"):
		later_cmds = state["later_battle_cmds"] != false
	dodge_cmd = state.get("dodge_cmd", true) != false   # M3d
	escape.clear()
	for e in state.get("escape", []):
		escape.append(to_local_cell(to_cell(e)))
	for u in state.get("units", []):
		if u is Dictionary:
			_add_unit(u)

## 加入一個單位（開場快照或 battle_unit_join）；pos 是主機座標。已存在的 uid 只更新
func _add_unit(u: Dictionary) -> int:
	var d: Dictionary = u.duplicate(true)
	var uid := int(d.get("uid", 0))
	if uid == 0:
		return 0
	d["uid"] = uid
	d["pos"] = to_local_cell(to_cell(d.get("pos", [-1, -1])))
	d["side"] = int(d.get("side", 1))
	d["qi"] = int(d.get("qi", 0))
	d["qi_max"] = int(d.get("qi_max", d["qi"]))
	d["state"] = str(d.get("state", "CHARGING"))
	var sts := {}
	var raw: Variant = d.get("statuses", [])
	if raw is Array:
		for st in raw:
			if st is Dictionary and str(st.get("id", "")) != "":
				sts[str(st["id"])] = BattleViewModel.status_entry(str(st["id"]), str(st.get("name", "")),
					int(st.get("n", -1)), int(st.get("level", 1)), str(st.get("glyph", "")), str(st.get("color", "")))
	elif raw is Dictionary:
		for sid in raw:
			var sv: Variant = raw[sid]
			sts[str(sid)] = BattleViewModel.status_entry(str(sid), "", int(sv.get("n", -1)) if sv is Dictionary else -1,
				int(sv.get("level", 1)) if sv is Dictionary else 1)
	d["statuses"] = sts
	units[uid] = d
	if not order.has(uid):
		order.append(uid)
	anchors[uid] = { "gauge": float(d.get("gauge", 0.0)), "rate": float(d.get("rate", 0.0)),
		"charging": d["state"] == "CHARGING" }
	return uid

# ---------- 鏡像（4.5.3） ----------
## 主機座標 → 畫面座標
func to_local_cell(c: Vector2i) -> Vector2i:
	return UiSocial.mirror_cell(c, w) if mirrored else c

## 畫面座標 → 主機座標（送 battle_cmd 的 target）；鏡像是自己的反函數
func to_host_cell(c: Vector2i) -> Vector2i:
	return UiSocial.mirror_cell(c, w) if mirrored else c

func to_host_arr(c: Vector2i) -> Array:
	return cell_arr(to_host_cell(c))

func is_pvp() -> bool:
	return kind in UiKeys.PVP_KINDS

## 事件裡的格子座標轉成畫面座標（battle_move 的 from／to、battle_unit_join 的 unit.pos）；不鏡像時原樣回傳
func localize_event(e: Dictionary) -> Dictionary:
	if not mirrored or str(e.get("ch", "")) != UiKeys.CH_BATTLE:
		return e
	var p: Variant = e.get("p", {})
	if not (p is Dictionary):
		return e
	var need := false
	for k in ["from", "to", "pos", "cells"]:
		if (p as Dictionary).has(k):
			need = true
	if (p as Dictionary).get("unit", null) is Dictionary:
		need = true
	if not need:
		return e
	var out := e.duplicate()
	var np: Dictionary = (p as Dictionary).duplicate(true)
	for k in ["from", "to", "pos"]:
		if np.has(k):
			np[k] = UiSocial.mirror_arr(np[k], w)
	if np.get("cells", null) is Array:   # battle_aoe 的打擊格
		var cs: Array = []
		for c in np["cells"]:
			cs.append(UiSocial.mirror_arr(c, w))
		np["cells"] = cs
	# battle_unit_join 的 unit.pos 由 _add_unit 轉換（它吃主機座標），這裡不動
	out["p"] = np
	return out

# ---------- 查詢 ----------
func unit(uid: int) -> Dictionary:
	return units.get(uid, {})

func me() -> Dictionary:
	return unit(my_uid)

func is_active(uid: int) -> bool:
	var u := unit(uid)
	return not u.is_empty() and not (str(u.get("state", "")) in ["DEAD", "FLED"])

func my_side() -> int:
	return int(me().get("side", 0))

func is_enemy(uid: int) -> bool:
	return int(unit(uid).get("side", -1)) != my_side()

func unit_at(c: Vector2i) -> int:
	for uid in order:
		if is_active(uid) and units[uid]["pos"] == c:
			return uid
	return 0

func is_escape(c: Vector2i) -> bool:
	return escape.has(c)

func in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h

func gauge_at(uid: int, now_tick: float) -> float:
	var a: Dictionary = anchors.get(uid, {})
	if a.is_empty():
		return 0.0
	var g := float(a["gauge"])
	if bool(a["charging"]):
		g += float(a["rate"]) * maxf(0.0, now_tick - anchor_tick)
	return clampf(g, 0.0, UiKeys.GAUGE_FULL)

## 我現在可以下令嗎（3.12 command_bar）：等待模式看 battle_await；非等待模式看我的時間棒是否滿
func is_my_turn(now_tick: float) -> bool:
	if ended or submitted or not is_active(my_uid):
		return false
	if await_units.has(my_uid):
		return true
	if not wait_mode:
		return gauge_at(my_uid, now_tick) >= UiKeys.GAUGE_FULL
	return false

## 等待倒數（秒）；沒有在等回 -1
func seconds_left(now_tick: float) -> float:
	if await_units.is_empty() or deadline_tick < 0:
		return -1.0
	return maxf(0.0, (float(deadline_tick) - now_tick) / UiKeys.TICKS_PER_SEC)

func move_range() -> int:
	return int(me().get("move_range", 2))

## 移動可達格：BFS，4 方向，不能穿越存活單位（3.4.2 BattleGrid.reachable）
func move_targets() -> Array:
	var u := me()
	if u.is_empty():
		return []
	var start: Vector2i = u["pos"]
	var steps := move_range()
	var seen := { start: 0 }
	var queue: Array = [start]
	var out: Array = []
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		var d: int = seen[c]
		if d >= steps:
			continue
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + off
			if not in_grid(n) or seen.has(n) or unit_at(n) != 0:
				continue
			seen[n] = d + 1
			out.append(n)
			queue.append(n)
	return out

## 距離 ≤ rng 的存活敵人位置
func enemy_cells_within(rng: int) -> Array:
	var out: Array = []
	var u := me()
	if u.is_empty():
		return out
	for uid in order:
		if is_active(uid) and is_enemy(uid) and manhattan(units[uid]["pos"], u["pos"]) <= rng:
			out.append(units[uid]["pos"])
	return out

func on_escape() -> bool:
	var u := me()
	return not u.is_empty() and is_escape(u["pos"])

func my_arts() -> Array:
	return me().get("arts", [])

func find_art(art_id: String) -> Dictionary:
	for a in my_arts():
		if a is Dictionary and str(a.get("id", "")) == art_id:
			return a
	return {}

# ---------- M3a：狀態 ----------
## 狀態圖示的一筆（§5.7 快照形狀）；glyph／color 沒給時查本地 status_effects 表
static func status_entry(id: String, name: String = "", n: int = -1, level: int = 1, glyph: String = "", color: String = "") -> Dictionary:
	var row := UiClient.row("status_effects", id)
	if name == "":
		name = str(row.get("name", id))
	if glyph == "":
		glyph = str(row.get("glyph", name.left(1)))
	if color == "":
		color = str(row.get("color", "#c0c0c0"))
	if n < 0:
		n = int(row.get("duration_actions", 0))
	return { "id": id, "name": name, "glyph": glyph, "color": color, "n": n, "level": maxi(1, level) }

## 單位身上的狀態（加上去的順序）
func unit_statuses(uid: int) -> Array:
	var sts: Variant = unit(uid).get("statuses", {})
	return (sts as Dictionary).values() if sts is Dictionary else []

## 「醫」對這個人有沒有用：氣沒滿，或身上有醫術能處理的狀態（中毒、流血）。氣血全滿又沒事的人不當目標（M3a 審查：
## 原本滿血也能選，結果「回復了 0 點氣」白白浪費一回合）
func needs_medic(uid: int) -> bool:
	var u := unit(uid)
	if u.is_empty():
		return false
	if int(u.get("qi", 0)) < int(u.get("qi_max", 0)):
		return true
	# 跟主機 BattleCmds.medic_cures 一致：流血醫得好；中毒只在後期規則（later_battle_cmds）才醫得好（M3a 審查 B2、B5）
	return (later_cmds and has_status(uid, "poison")) or has_status(uid, "bleed")

func has_status(uid: int, sid: String) -> bool:
	var sts: Variant = unit(uid).get("statuses", {})
	return sts is Dictionary and (sts as Dictionary).has(sid)

## 狀態滑鼠提示：「中毒（3 級）剩 4 次」
static func status_tip(st: Dictionary) -> String:
	var t := str(st.get("name", st.get("id", "")))
	if int(st.get("level", 1)) > 1:
		t += "（%d 級）" % int(st["level"])
	if int(st.get("n", 0)) > 0:
		t += " 剩 %d 次" % int(st["n"])
	return t

## 身上的狀態封鎖了這個指令（status_effects.blocks；主機另有 status_blocked）→ 狀態名，沒有回 ""
func status_blocks(cmd: String) -> String:
	for st in unit_statuses(my_uid):
		var row := UiClient.row("status_effects", str(st.get("id", "")))
		var blocks: Variant = row.get("blocks", [])
		if blocks is Array and cmd in (blocks as Array):
			return str(st.get("name", ""))
	return ""

# ---------- M3a：指令可用與資料 ----------
func cmd_avail() -> Dictionary:
	var v: Variant = me().get("cmd_avail", {})
	return v if v is Dictionary else {}

## 「內」可用的運功（cmd_avail.INNER）
func inner_modes() -> Array:
	var v: Variant = cmd_avail().get(UiKeys.CMD_INNER, [])
	return v if v is Array else []

## 快照說這個 M3a 指令能用（不看是否輪到我）；內、穴另看 later_battle_cmds
func cmd_open(cmd: String) -> bool:
	var a := cmd_avail()
	match cmd:
		UiKeys.CMD_INNER:
			return later_cmds and not inner_modes().is_empty()
		UiKeys.CMD_ACUPOINT:
			return later_cmds and a.get(cmd, false) == true
		UiKeys.CMD_HIDDEN:
			return a.get(cmd, false) == true and not hidden_items().is_empty()
		UiKeys.CMD_ITEM:
			return a.get(cmd, false) == true and not battle_items().is_empty()
		UiKeys.CMD_DODGE:
			return dodge_cmd and a.get(cmd, dodge_cmd) == true
		UiKeys.CMD_QING:
			return later_cmds and not qing_modes().is_empty()
	return a.get(cmd, false) == true

# ---------- M3d：閃、輕、烙跑鞋（M3D_PLAN §3.1–3.4；WP-COMBAT） ----------
## 「輕」現在可用的 mode（快照 cmd_avail.QING：["JUMP", "ESCAPE"] 的子集）
func qing_modes() -> Array:
	var v: Variant = cmd_avail().get(UiKeys.CMD_QING, [])
	return v if v is Array else []

## 飛身越敵的落點：曼哈頓距離 ≤ 移動範圍 + 1 的空格（可以越過有人的格子）
func jump_targets() -> Array:
	var u := me()
	if u.is_empty():
		return []
	var start: Vector2i = u["pos"]
	var steps := move_range() + 1
	var out: Array = []
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			if c != start and manhattan(c, start) <= steps and unit_at(c) == 0:
				out.append(c)
	return out

## 穿著烙跑鞋、這場允許 → 任何格子都能逃（快照 flee_anywhere）
func flee_anywhere() -> bool:
	return bool(me().get("flee_anywhere", false))

func is_dodging(uid: int) -> bool:
	return bool(unit(uid).get("dodging", false))

func hidden_items() -> Array:
	var v: Variant = me().get("hidden_items", [])
	return (v as Array).filter(func(it): return it is Dictionary and int(it.get("n", 0)) > 0) if v is Array else []

func battle_items() -> Array:
	var v: Variant = me().get("battle_items", [])
	return (v as Array).filter(func(it): return it is Dictionary and int(it.get("n", 0)) > 0) if v is Array else []

## cmd_arts 的一類（POISON／MEDIC／HIDDEN／FORMATION／INNER／ACUPOINT），統一成 [{ id, name, range, level, cost_inner }]。
## 主機給的可能是 id 字串或已附名稱與射程的字典（§7.1「附名稱與 moves[0] 射程」）；缺的查本地 martial_arts 表
func cmd_arts(cat: String) -> Array:
	var all: Variant = me().get("cmd_arts", {})
	var lst: Variant = (all as Dictionary).get(cat, []) if all is Dictionary else []
	var out: Array = []
	if not (lst is Array):
		return out
	for a in lst:
		var d: Dictionary = (a as Dictionary).duplicate() if a is Dictionary else { "id": str(a) }
		var aid := str(d.get("id", ""))
		if aid == "":
			continue
		var row := UiClient.row("martial_arts", aid)
		var m0: Dictionary = {}
		var moves: Variant = row.get("moves", [])
		if moves is Array and not (moves as Array).is_empty() and moves[0] is Dictionary:
			m0 = moves[0]
		if not d.has("name"):
			d["name"] = str(row.get("name", aid))
		if not d.has("range"):
			d["range"] = int(m0.get("range", 1))
		if not d.has("cost_inner"):
			d["cost_inner"] = int(m0.get("cost_inner", 0))
		if not d.has("level"):
			d["level"] = int(find_art(aid).get("level", 0))
		d["id"] = aid
		out.append(d)
	return out

## 暗器射程（§5.4）：3 + floor(基本暗器 / 40) + 暗器武功 range_bonus，最多 6；主機在單位上給 hidden_range 時用主機的
func hidden_range(basic_hidden: int, range_bonus: int = 0) -> int:
	if me().has("hidden_range"):
		return int(me()["hidden_range"])
	return BattleViewModel.hidden_range_for(basic_hidden, range_bonus)

static func hidden_range_for(basic_hidden: int, range_bonus: int = 0) -> int:
	return mini(6, 3 + floori(maxi(0, basic_hidden) / 40.0) + maxi(0, range_bonus))

# ---------- M3a：選目標的格子 ----------
## 自己或同側活著的單位（醫、用藥、傳力；綠框）。include_self = false 時不含自己
func ally_cells_within(rng: int, include_self := true, needs_heal := false) -> Array:
	var out: Array = []
	var u := me()
	if u.is_empty():
		return out
	for uid in order:
		if not is_active(uid) or is_enemy(uid):
			continue
		if uid == my_uid and not include_self:
			continue
		if needs_heal and not needs_medic(uid):
			continue
		if manhattan(units[uid]["pos"], u["pos"]) <= rng:
			out.append(units[uid]["pos"])
	return out

## 陣法站位（相對施陣者）：快照 formation（{ art, stations }）是這一套就用它，否則查本地 martial_arts.formation.stations
func formation_stations(art_id: String) -> Array:
	var f: Variant = me().get("formation", null)
	var st: Variant = null
	if f is Dictionary and (art_id == "" or str(f.get("art", "")) == art_id):
		st = f.get("stations", null)
	if not (st is Array):
		var fr: Variant = UiClient.row("martial_arts", art_id).get("formation", null)
		st = (fr as Dictionary).get("stations", []) if fr is Dictionary else []
	var out: Array = []
	for o in st:
		out.append(to_cell(o))
	if not out.has(Vector2i.ZERO):
		out.push_front(Vector2i.ZERO)
	return out

## 站位格（畫面座標）：施陣者在 [0,0]；本模型裡自己永遠在左側（右側方已整個鏡像），所以不必再左右翻（§5.4）
func station_cells(offsets: Array) -> Array:
	var out: Array = []
	var u := me()
	if u.is_empty():
		return out
	for o in offsets:
		out.append((u["pos"] as Vector2i) + to_cell(o))
	return out

## 站位格上沒有同側、活著的玩家（施陣者自己的格除外）→ 缺人的格（金框閃爍）
func station_missing(cells: Array) -> Array:
	var out: Array = []
	var my_pos: Vector2i = me().get("pos", Vector2i(-1, -1))
	for c in cells:
		var cc: Vector2i = c
		if cc == my_pos:
			continue
		var uid := unit_at(cc)
		if uid == 0 or is_enemy(uid) or str(unit(uid).get("kind", "PLAYER")) != "PLAYER":
			out.append(cc)
	return out

## from → to 的 8 方向單位向量；不在同列、同行或同斜線上回 (0,0)
static func dir_to(from: Vector2i, to: Vector2i) -> Vector2i:
	var d := to - from
	if d == Vector2i.ZERO:
		return Vector2i.ZERO
	if d.x == 0 or d.y == 0 or absi(d.x) == absi(d.y):
		return Vector2i(signi(d.x), signi(d.y))
	return Vector2i.ZERO

## 範圍招式打到的格（§5.3）。origin = 出招者、center = 中心格（LINE／FAN 決定方向；AROUND 不看）；只回格子內的格
static func aoe_cells(shape: String, origin: Vector2i, center: Vector2i, rng: int, gw: int, gh: int) -> Array:
	var out: Array = []
	match shape:
		"CROSS", "CROSS_L":
			out.append(center)
			var arm := 1 if shape == "CROSS" else 3
			for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				for k in range(1, arm + 1):
					out.append(center + (off as Vector2i) * k)
		"LINE", "FAN":
			var d := BattleViewModel.dir_to(origin, center)
			if d == Vector2i.ZERO:
				return []
			var i := DIRS8.find(d)
			var dirs: Array = [d]
			if shape == "FAN":
				dirs = [DIRS8[(i + 7) % 8], d, DIRS8[(i + 1) % 8]]
			for dd in dirs:
				for k in range(1, maxi(1, rng) + 1):
					out.append(origin + (dd as Vector2i) * k)
		"AROUND":
			for dd in DIRS8:
				out.append(origin + (dd as Vector2i))
		_:
			out.append(center)
	return out.filter(func(c): return c.x >= 0 and c.y >= 0 and c.x < gw and c.y < gh)

## 這個中心格打得到的敵人格
func aoe_hits(shape: String, center: Vector2i, rng: int) -> Array:
	var u := me()
	if u.is_empty():
		return []
	var out: Array = []
	for c in BattleViewModel.aoe_cells(shape, u["pos"], center, rng, w, h):
		var uid := unit_at(c)
		if uid != 0 and is_enemy(uid):
			out.append(c)
	return out

## 範圍招式可點的中心格：射程內（曼哈頓，含自己的格）、LINE／FAN 在 8 方向上、範圍內至少一個敵人；AROUND 只有自己的格
func aoe_centers(shape: String, rng: int) -> Array:
	var u := me()
	if u.is_empty():
		return []
	var me_pos: Vector2i = u["pos"]
	if shape == "AROUND":
		return [me_pos] if not aoe_hits(shape, me_pos, rng).is_empty() else []
	var out: Array = []
	for x in w:
		for y in h:
			var c := Vector2i(x, y)
			if manhattan(c, me_pos) > rng:
				continue
			if shape in ["LINE", "FAN"] and BattleViewModel.dir_to(me_pos, c) == Vector2i.ZERO:
				continue
			if not aoe_hits(shape, c, rng).is_empty():
				out.append(c)
	return out

# ---------- 套用事件 ----------
## 回傳 true = 此事件屬於本場戰鬥並已套用
func apply_event(e: Dictionary) -> bool:
	if str(e.get("ch", "")) != UiKeys.CH_BATTLE:
		return false
	var p: Dictionary = e.get("p", {})
	var ebid := int(e.get("bid", p.get("bid", bid)))
	if ebid != bid:
		return false
	var key := str(e.get("key", ""))
	match key:
		UiKeys.E_BATTLE_GAUGES:
			_apply_gauges(p)
		UiKeys.E_BATTLE_UNIT_JOIN:
			var nu: Variant = p.get("unit", {})
			if nu is Dictionary:
				_add_unit(nu)
		UiKeys.E_BATTLE_AWAIT:
			await_units = []
			for uid in p.get("units", []):
				await_units.append(int(uid))
			deadline_tick = int(p.get("deadline_tick", -1))
			if await_units.has(my_uid):
				submitted = false
		UiKeys.E_BATTLE_END:
			ended = true
			result = str(p.get("result", ""))
			await_units = []
		UiKeys.E_BATTLE_MOVE:
			var uid := int(p.get("uid", 0))
			if units.has(uid):
				units[uid]["pos"] = to_cell(p.get("to", cell_arr(units[uid]["pos"])))
			_acted(uid)
		UiKeys.E_BATTLE_REST:
			var uid := int(p.get("uid", 0))
			_set_num(uid, "qi", p, "qi")
			_set_num(uid, "neili", p, "neili")
			_acted(uid)
		UiKeys.E_BATTLE_EQUIP:
			var uid := int(p.get("uid", 0))
			_equip(uid, str(p.get("item_name", "")), p)
			_acted(uid)
		UiKeys.E_BATTLE_DEFEND:
			_acted(int(p.get("uid", 0)))
		UiKeys.E_BATTLE_FLEE:
			_set_state(int(p.get("uid", 0)), "FLED")
		# ---- M3d（M3D_PLAN §3.1–3.3；WP-COMBAT） ----
		UiKeys.E_BATTLE_DODGE:
			var du := int(p.get("uid", 0))
			_acted(du)
			if units.has(du):
				units[du]["dodging"] = true
		UiKeys.E_BATTLE_QING_JUMP:
			var ju := int(p.get("uid", 0))
			if units.has(ju):
				units[ju]["pos"] = to_cell(p.get("to", cell_arr(units[ju]["pos"])))
			_set_num(ju, "neili", p, "neili")
			_acted(ju)
		UiKeys.E_BATTLE_QING_ESCAPE:
			var eu := int(p.get("uid", 0))
			_set_num(eu, "neili", p, "neili")
			_set_state(eu, "FLED")
		UiKeys.E_BATTLE_QING_FAIL:
			var fu := int(p.get("uid", 0))
			_set_num(fu, "neili", p, "neili")
			_acted(fu)
		UiKeys.E_BATTLE_COMBO:
			last_combo = p.duplicate()
			_set_num(int(p.get("def_uid", 0)), "qi", p, "def_qi")
			_acted(int(p.get("atk_uid", 0)))
		UiKeys.E_BATTLE_KILL, UiKeys.E_BATTLE_DEATH:
			_set_state(int(p.get("uid", 0)), "DEAD")
		UiKeys.E_BATTLE_WOUND_TICK:
			_set_num(int(p.get("uid", 0)), "qi", p, "qi")
		UiKeys.E_BATTLE_PROC_RECOVER:
			var uid := int(p.get("uid", 0))
			if units.has(uid):
				var u: Dictionary = units[uid]
				u["qi"] = mini(int(u.get("qi_max", 0)), int(u.get("qi", 0)) + int(p.get("qi_gain", 0)))
				if u.has("shen"):
					u["shen"] = mini(int(u.get("shen_max", u["shen"])), int(u["shen"]) + int(p.get("shen_gain", 0)))
		UiKeys.E_BATTLE_STATUS_ON:
			var uid := int(p.get("uid", 0))
			if units.has(uid):
				var sid := str(p.get("status", ""))
				units[uid]["statuses"][sid] = BattleViewModel.status_entry(sid, str(p.get("status_name", "")),
					int(p.get("n", -1)), int(p.get("level", 1)), str(p.get("glyph", "")), str(p.get("color", "")))
		UiKeys.E_BATTLE_STATUS_OFF:
			var uid := int(p.get("uid", 0))
			if units.has(uid):
				(units[uid]["statuses"] as Dictionary).erase(str(p.get("status", "")))
		UiKeys.E_BATTLE_TIMEOUT:
			var uid := int(p.get("uid", 0))
			await_units.erase(uid)
			_timeouts[uid] = int(_timeouts.get(uid, 0)) + 1
			if int(_timeouts[uid]) >= 2:
				afk[uid] = true
			if uid == my_uid:
				submitted = false
		UiKeys.E_BATTLE_MISS:
			_acted(int(p.get("atk_uid", 0)))
		UiKeys.E_BATTLE_WAVE:
			wave = int(p.get("n", 0))
			wave_total = int(p.get("total", 0))
		UiKeys.E_BATTLE_AOE:
			var cells: Array = []
			for c in p.get("cells", []):
				cells.append(to_cell(c))
			last_aoe = { "uid": int(p.get("uid", 0)), "cells": cells }
		UiKeys.E_BATTLE_POISON_TICK:
			var uid := int(p.get("uid", 0))
			_set_num(uid, "qi", p, "qi")
			_tick_statuses(uid)
		UiKeys.E_BATTLE_STATUS_SKIP, UiKeys.E_BATTLE_CONFUSED:
			_acted(int(p.get("uid", 0)))
		UiKeys.E_BATTLE_FORMATION_OFF:
			for uid in units:
				(units[uid]["statuses"] as Dictionary).erase("formation")
		UiKeys.E_BATTLE_MEDIC:
			# 目標回氣：主機給 def_qi 就照抄，否則加 heal
			var tu := int(p.get("def_uid", 0))
			if not _apply_vitals(p) and units.has(tu):
				_add_num(tu, "qi", int(p.get("heal", 0)))
			_acted(int(p.get("atk_uid", 0)))
		UiKeys.E_BATTLE_INNER_HEAL:
			# { uid, heal, neili, qi }：neili／qi 是運功後的剩餘值（core/battle/battle_cmds.gd）；沒有 qi 時加 heal
			var hu := int(p.get("uid", 0))
			if units.has(hu):
				if p.has("qi"):
					_set_num(hu, "qi", p, "qi")
				else:
					_add_num(hu, "qi", int(p.get("heal", 0)))
				_set_num(hu, "neili", p, "neili")
			_acted(hu)
		UiKeys.E_BATTLE_ITEM_USE:
			# { atk_uid, def_uid, item_name, item_uid, qi, neili }：qi／neili 是用藥對象用藥後的值
			_consume(key, p)
			var du := int(p.get("def_uid", p.get("atk_uid", 0)))
			_set_num(du, "qi", p, "qi")
			_set_num(du, "neili", p, "neili")
			_acted(int(p.get("atk_uid", 0)))
		UiKeys.E_BATTLE_INNER_TRANSFER:
			if not _apply_vitals(p):
				var n := int(p.get("n", 0))
				_add_num(int(p.get("atk_uid", 0)), "neili", -n)
				_add_num(int(p.get("def_uid", 0)), "neili", n)
			_acted(int(p.get("atk_uid", 0)))
		UiKeys.E_BATTLE_INNER_EXPEL, UiKeys.E_BATTLE_INNER_UNSEAL_OK, UiKeys.E_BATTLE_INNER_UNSEAL_FAIL:
			var iu := int(p.get("uid", 0))
			if p.has("neili_left"):
				_set_num(iu, "neili", p, "neili_left")
			_acted(iu)
		_:
			if key in [UiKeys.E_BATTLE_HIDDEN_HIT, UiKeys.E_BATTLE_HIDDEN_MISS]:
				_consume(key, p)
			if UiKeys.is_hit_event(e):
				_set_num(int(p.get("def_uid", 0)), "qi", p, "def_qi")
				if p.has("atk_neili"):
					_set_num(int(p.get("atk_uid", 0)), "neili", p, "atk_neili")
				_acted(int(p.get("atk_uid", 0)))
			elif _apply_vitals(p) or key in [UiKeys.E_BATTLE_POISON_FAIL, UiKeys.E_BATTLE_HIDDEN_MISS,
					UiKeys.E_BATTLE_ACUPOINT_OK, UiKeys.E_BATTLE_ACUPOINT_FAIL, UiKeys.E_BATTLE_ITEM_USE, UiKeys.E_BATTLE_FORMATION_ON]:
				_acted(int(p.get("atk_uid", p.get("uid", 0))))
			return true
	return true

func _apply_gauges(p: Dictionary) -> void:
	anchor_tick = float(p.get("tick", anchor_tick))
	var any_charging := false
	for row in p.get("units", []):
		if not (row is Array) or row.size() < 4:
			continue
		var uid := int(row[0])
		var charging := bool(row[3])
		anchors[uid] = { "gauge": float(row[1]), "rate": float(row[2]), "charging": charging }
		if charging:
			any_charging = true
		if units.has(uid) and not (str(units[uid]["state"]) in ["DEAD", "FLED"]):
			units[uid]["state"] = "CHARGING" if charging else ("READY" if float(row[1]) >= UiKeys.GAUGE_FULL else "CHARGING")
	# 時間棒重新流動 = 不在 AWAIT_COMMAND
	if any_charging:
		await_units = []
		deadline_tick = -1
	submitted = false

func _set_num(uid: int, field: String, p: Dictionary, src: String) -> void:
	if units.has(uid) and p.has(src):
		units[uid][field] = int(p[src])

func _set_state(uid: int, st: String) -> void:
	if units.has(uid):
		units[uid]["state"] = st
		if st in ["DEAD", "FLED"]:
			units[uid]["qi"] = 1 if st == "DEAD" else int(units[uid]["qi"])
	await_units.erase(uid)
	anchors[uid] = { "gauge": 0.0, "rate": 0.0, "charging": false }

func _equip(uid: int, item_name: String, p: Dictionary = {}) -> void:
	if not units.has(uid):
		return
	var u: Dictionary = units[uid]
	var weapon := { "uid": "", "name": "", "weapon_type": "FIST" }
	for opt in u.get("weapon_options", []):
		if opt is Dictionary and str(opt.get("name", "")) == item_name and item_name != "":
			weapon = (opt as Dictionary).duplicate()
			break
	if item_name != "" and weapon["name"] == "":
		weapon["name"] = item_name
	u["weapon"] = weapon
	# M3C_PLAN §7.2（WP-FX）純表現：換兵器後的武器類型與兵器特效（主機給的優先；舊主機只有自己的 weapon_options 可對）
	if p.has("wtype"):
		u["wtype"] = str(p["wtype"])
		u["wfx"] = str(p.get("wfx", ""))
	elif u.has("wtype") or u.has("weapon_options"):
		u["wtype"] = str(weapon.get("weapon_type", "FIST"))
		u["wfx"] = ""

## M3C_PLAN §7.1（WP-FX）：名牌武器圖示／出招特效用的武器種類（"" = 非人形怪）。humanoid 由畫面傳入（UnitSprite.is_tall()）
func weapon_kind(uid: int, humanoid: bool) -> String:
	return WeaponFx.icon_kind(unit(uid), humanoid) if units.has(uid) else ""

func _acted(uid: int) -> void:
	if uid == 0:
		return
	if units.has(uid):
		units[uid]["dodging"] = false   # M3d：「閃」只到自己下次行動前
	_timeouts.erase(uid)
	afk.erase(uid)
	_tick_statuses(uid)

## 一次行動扣一次狀態剩餘次數（§5.7 行動開始時次數 −1；主機到 0 時另送 battle_status_off）。
## 同一個錨點（同一次行動）的多個事件只扣一次：範圍招式、毒發＋出手
func _tick_statuses(uid: int) -> void:
	if not units.has(uid):
		return
	if is_equal_approx(float(_status_tick_at.get(uid, -1.0)), anchor_tick):
		return
	_status_tick_at[uid] = anchor_tick
	for st in (units[uid]["statuses"] as Dictionary).values():
		if int(st.get("n", 0)) > 1:
			st["n"] = int(st["n"]) - 1

func _add_num(uid: int, field: String, delta: int) -> void:
	if not units.has(uid) or delta == 0:
		return
	var u: Dictionary = units[uid]
	var mx := int(u.get(field + "_max", 0))
	var v := int(u.get(field, 0)) + delta
	u[field] = clampi(v, 0, mx) if mx > 0 else maxi(0, v)

## 新指令事件帶的數值（醫、用藥、傳力、暗器、毒）：只認有前綴的欄位 def_uid → def_qi／def_neili…、atk_uid → atk_neili…
## （沒前綴的 neili 在模板裡常是「耗去多少」，不能當剩餘值）。回傳是否套用了任何欄位
func _apply_vitals(p: Dictionary) -> bool:
	var any := false
	for pair in [["def_uid", "def_"], ["atk_uid", "atk_"]]:
		var uid := int(p.get(pair[0], 0))
		if not units.has(uid):
			continue
		for f in ["qi", "neili", "jing", "shen"]:
			var src: String = str(pair[1]) + f
			if p.has(src):
				var mx := int(units[uid].get(f + "_max", 0))
				units[uid][f] = clampi(int(p[src]), 0, mx) if mx > 0 else int(p[src])
				any = true
	return any

## 暗器丟一個、藥吃一個（只管我自己的單位；戰後主機才從背包扣，這裡先扣數量讓選單與「暗」「裝」的可用狀態正確）
func _consume(key: String, p: Dictionary) -> void:
	if int(p.get("atk_uid", p.get("uid", 0))) != my_uid or not units.has(my_uid):
		return
	var field := "battle_items" if key == UiKeys.E_BATTLE_ITEM_USE else "hidden_items"
	var lst: Variant = units[my_uid].get(field, [])
	if not (lst is Array):
		return
	var iuid := str(p.get("item_uid", ""))
	var iname := str(p.get("item_name", ""))
	for it in lst:
		if not (it is Dictionary):
			continue
		if (iuid != "" and str(it.get("uid", "")) == iuid) or (iuid == "" and str(it.get("name", "")) == iname):
			# 主機給 left（這一疊還剩幾個）就照抄，否則自己減一
			it["n"] = maxi(0, int(p["left"])) if p.has("left") else maxi(0, int(it.get("n", 0)) - 1)
			break

## 送出指令成功後呼叫：我不再在等待清單內
func mark_submitted() -> void:
	submitted = true
	await_units.erase(my_uid)

## 送出失敗：恢復可下令
func unmark_submitted() -> void:
	submitted = false
