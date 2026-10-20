class_name AutoWalkCore
extends RefCounted
## 自動趕路的狀態機（M3C_PLAN §4.2、§4.4）：不依賴場景樹，AutoWalker（介面）與驗收工具直接用。
## 呼叫者的迴圈：
##   act = core.next_step(view, sheet)
##     MOVE    → 送 move { dir }（主機照常驗證每一步）→ core.on_move_result(ok, reason) → 等新的房間 view 再呼叫 next_step
##     WAIT    → 還在等主機回應／房間 view／戰鬥結束
##     STOP    → 停止（reason 是要顯示給玩家的原因）
##     ARRIVED → 抵達
##   戰鬥開始 core.on_battle_start()；戰鬥畫面收起 core.on_battle_end(result, resume_enabled)。
## 停走規則（§4.4，依序檢查，第一個成立就停）：
##   1 戰敗 2 逃走 3 勝利但續走選項關 4 氣 < 三成 5 飽食或飲水 < 20 6 前方出口鎖住 7 前方是要自己決定的房間（不是終點）
##   8 move 被主機拒絕 9 坐牢中
## 續走：只在趕路中被遇敵打斷、結果 VICTORY、續走選項開、且 4–5 都不成立時（從目前房間重新規劃到原目標）。

const QI_MIN_RATIO := 0.30        # 【設計提案】O3
const FOOD_MIN := 20              # 【設計提案】O3
const WATER_MIN := 20

const MSG_DEFEAT := "你倒下了，停止趕路。"
const MSG_FLED := "你逃離了戰鬥，停止趕路。"
const MSG_BATTLE_OVER := "戰鬥結束，停止趕路。"
const MSG_QI := "氣血不足三成，先休息吧。"
const MSG_HUNGRY_THIRSTY := "又餓又渴，先吃點東西。"
const MSG_HUNGRY := "肚子餓了，先吃點東西。"
const MSG_THIRSTY := "口渴了，先喝點水。"
const MSG_LOCKED := "前方%s去不了：%s"
const MSG_DECIDE := "前方是%s，請自己決定要不要進去。"
const MSG_REJECTED := "趕路中斷：%s"
const MSG_JAIL := "身在牢中，無法趕路。"
const MSG_MOVED := "位置變了，停止趕路。"
const MSG_STOPPED := "已停止趕路。"
const MSG_NO_ROUTE := "找不到已知的路，停止趕路。"
const MSG_ARRIVED := "已抵達。"
const PROGRESS := "趕路中：往%s（剩%d步）"

var path: Array = []           # [{ dir, to }]（不含起點）
var idx := 0                   # 下一步在 path 的位置
var from_room := ""            # 目前（最後確認）所在的房間
var dest_room := ""
var dest_name := ""
var note := ""                 # 進度列附註（例：「（只能走到 X，再往前沒去過）」）
var active := false
var move_pending := false      # 已送 move，還沒收到主機回應
var view_pending := false      # 主機已接受 move，還沒看到新房間的 view
var in_battle := false
var battle_result := ""        # 趕路中被戰鬥打斷：VICTORY／DEFEAT／FLED／ALL_FLED／ABORTED
var resume_enabled := true
var rejected := ""             # move 被拒的原因碼（§4.4 #8）
var stop_reason := ""
var arrived := false

## 規劃與停走判斷用的資料（可省；沒有就不檢查 #7、不重新規劃）
var tables: Dictionary = {}
var graph: Dictionary = {}
var known: Dictionary = {}
## 原因碼 → 文字（介面用 UiClient.reason_inline）；空 Callable＝直接寫原因碼
var reason_text: Callable = Callable()

var _rooms: Dictionary = {}    # room_id -> room（tables 的索引，configure 時重建）

func configure(p_tables: Dictionary, p_graph: Dictionary = {}, p_known: Dictionary = {}) -> void:
	_rooms = {}
	tables = p_tables
	graph = p_graph
	known = p_known

## path：[{ dir, to }]（RoutePlanner.steps 的結果）或 RoutePlanner.find_path 的房間清單 [from, …, to]
func start(p_path: Array, cur_room: String, p_dest_name: String, p_note: String = "") -> void:
	_reset()
	path = _normalize(p_path, cur_room)
	from_room = cur_room
	note = p_note
	if path.is_empty():
		stop_reason = MSG_NO_ROUTE
		return
	dest_room = str(path[path.size() - 1].get("to", ""))
	dest_name = p_dest_name if p_dest_name != "" else dest_room
	active = true

func stop(reason: String = MSG_STOPPED) -> void:
	if active:
		stop_reason = reason
	active = false
	move_pending = false
	view_pending = false

func is_active() -> bool:
	return active

func expected_room() -> String:
	return str(path[idx].get("to", "")) if active and idx < path.size() else ""

func target() -> String:
	return dest_room

func remaining() -> int:
	return maxi(0, path.size() - idx)

## 剩下的路（M3c 審查：地圖畫路線用）：[目前房間, 下一間, …, 目的地]；沒在走 → []
func remaining_rooms() -> Array:
	if not active:
		return []
	var out: Array = [from_room]
	for i in range(idx, path.size()):
		out.append(str(path[i].get("to", "")))
	return out

func progress_text() -> String:
	return (PROGRESS % [dest_name, remaining()]) + note

## 看最新的房間 view：到了下一間就往前推；被移到路線上的其他房間就對齊；完全意外的房間就停
func observe(view: Dictionary) -> void:
	if not active:
		return
	var room := str(view.get("room", ""))
	if room == "" or room == from_room:
		return
	var at := -1
	for i in range(idx, path.size()):
		if str(path[i].get("to", "")) == room:
			at = i
			break
	if at < 0:
		stop(MSG_MOVED)
		return
	idx = at + 1
	from_room = room
	view_pending = false
	if idx >= path.size():
		active = false
		arrived = true
		stop_reason = MSG_ARRIVED

func next_step(view: Dictionary, sheet: Dictionary) -> Dictionary:
	if arrived:
		return { "action": "ARRIVED" }
	if not active:
		return { "action": "STOP", "reason": stop_reason }
	if in_battle:
		return { "action": "WAIT" }
	# 1–3：趕路中被戰鬥打斷（先於房間比對：戰敗重生到記錄點時要說「你倒下了」，不是「位置變了」）
	if battle_result != "":
		var r := battle_result
		battle_result = ""
		match r:
			"DEFEAT":
				return _stop(MSG_DEFEAT)
			"FLED", "ALL_FLED":
				return _stop(MSG_FLED)
			"VICTORY":
				if not resume_enabled:
					return _stop(MSG_BATTLE_OVER)
				var why := _vitals_block(sheet)
				if why != "":
					return _stop(why)
				if graph.is_empty():
					observe(view)   # 沒有圖：沿原路線對齊
					view_pending = false
				else:
					_replan(str(view.get("room", from_room)))
				if arrived:
					return { "action": "ARRIVED" }
				if not active:
					return { "action": "STOP", "reason": stop_reason }
			_:
				return _stop(MSG_BATTLE_OVER)
	observe(view)
	if arrived:
		return { "action": "ARRIVED" }
	if not active:
		return { "action": "STOP", "reason": stop_reason }
	if move_pending:
		return { "action": "WAIT" }
	if view_pending:
		return { "action": "WAIT" }
	if idx >= path.size():
		active = false
		arrived = true
		stop_reason = MSG_ARRIVED
		return { "action": "ARRIVED" }
	# 4–5
	var vb := _vitals_block(sheet)
	if vb != "":
		return _stop(vb)
	var step: Dictionary = path[idx]
	var dir := str(step.get("dir", ""))
	var to := str(step.get("to", ""))
	# 6：前方出口鎖住（主機 view 才有 locked）
	if str(view.get("room", from_room)) == from_room:
		for ex in view.get("exits", []):
			if ex is Dictionary and str(ex.get("dir", "")) == dir and bool(ex.get("locked", false)):
				var nm := str(ex.get("to_name", "")) if str(ex.get("to_name", "")) != "" else _room_name(to)
				return _stop(MSG_LOCKED % [nm, str(ex.get("lock_reason", ""))])
	# 7：要自己決定的房間（終點除外）
	if to != dest_room and decision_room(to, sheet):
		return _stop(MSG_DECIDE % _room_name(to))
	# 8：上一步被主機拒絕
	if rejected != "":
		var code := rejected
		rejected = ""
		return _stop(MSG_REJECTED % _reason(code))
	# 9：坐牢中
	if _jailed(sheet):
		return _stop(MSG_JAIL)
	move_pending = true
	return { "action": "MOVE", "dir": dir, "to": to }

func on_move_result(ok: bool, reason: String) -> void:
	if not active:
		return
	move_pending = false
	if ok:
		view_pending = true
	else:
		rejected = reason if reason != "" else "error"

func on_battle_start() -> void:
	if not active:
		return
	in_battle = true
	move_pending = false

## result：VICTORY／DEFEAT／FLED／ALL_FLED（ABORTED 也接受，當成「戰鬥結束」）
func on_battle_end(result: String, p_resume_enabled: bool) -> void:
	if not active:
		return
	in_battle = false
	battle_result = result if result != "" else "ABORTED"
	resume_enabled = p_resume_enabled

## §4.4 #7：房間 requires 非空（全部只要求「本派」而玩家就是該派弟子者除外【M3C_PLAN 缺漏：本派弟子回自己門派的內室】）；
## jail: true；某派 gate_room 而玩家不是該派弟子；房內有 GUIDE 服務 NPC
func decision_room(room_id: String, sheet: Dictionary) -> bool:
	var room := _room(room_id)
	if room.is_empty():
		return false
	var my_sect := str(sheet.get("sect", ""))
	var req: Variant = room.get("requires", [])
	if req is Array and not (req as Array).is_empty():
		var own_only := my_sect != ""
		for r in req:
			if not (r is Dictionary and str(r.get("type", "")) == "sect" and str(r.get("sect", "")) == my_sect):
				own_only = false
				break
		if not own_only:
			return true
	if bool(room.get("jail", false)):
		return true
	var sects: Variant = tables.get("sects", {})
	var rows: Array = (sects as Dictionary).values() if sects is Dictionary else (sects if sects is Array else [])
	for row in rows:
		if row is Dictionary and str(row.get("gate_room", "")) == room_id and str(row.get("id", "")) != my_sect:
			return true
	var npcs: Variant = tables.get("npcs", {})
	if npcs is Dictionary:
		for nid in room.get("npcs", []):
			var n: Variant = npcs.get(str(nid), {})
			if n is Dictionary and n.get("services", []) is Array and (n["services"] as Array).has("GUIDE"):
				return true
	return false

# ---------------------------------------------------------------- 內部

func _reset() -> void:
	path = []
	idx = 0
	from_room = ""
	dest_room = ""
	dest_name = ""
	note = ""
	active = false
	move_pending = false
	view_pending = false
	in_battle = false
	battle_result = ""
	rejected = ""
	stop_reason = ""
	arrived = false

func _stop(reason: String) -> Dictionary:
	stop(reason)
	stop_reason = reason
	return { "action": "STOP", "reason": reason }

## [from, a, b] 房間清單 → [{dir,to}]；已經是 [{dir,to}] 的原樣
func _normalize(p: Array, cur_room: String) -> Array:
	if p.is_empty():
		return []
	if p[0] is Dictionary:
		return p.duplicate(true)
	var rooms: Array = p.duplicate()
	if str(rooms[0]) != cur_room:
		rooms.push_front(cur_room)
	if rooms.size() < 2:
		return []
	if not graph.is_empty():
		return RoutePlanner.steps(graph, rooms)
	return RoutePlanner.steps(RoutePlanner.graph(tables), rooms) if not tables.is_empty() else []

## 勝利續走：從目前房間重新規劃到原目標（有圖時；沒有圖就沿原路線對齊）
func _replan(room: String) -> void:
	if room == "":
		room = from_room
	if room == dest_room:
		active = false
		arrived = true
		stop_reason = MSG_ARRIVED
		return
	from_room = room
	view_pending = false
	if graph.is_empty():
		return
	var k := known.duplicate()
	k[room] = true
	var rooms := RoutePlanner.find_path(graph, room, dest_room, k)
	if rooms.is_empty():
		# 終點本來就不是已探索房間（只能走到最近處）：沿原路線剩下的部分
		var rest: Array = path.slice(idx)
		if rest.is_empty():
			stop(MSG_NO_ROUTE)
		return
	path = RoutePlanner.steps(graph, rooms)
	idx = 0
	if path.is_empty():
		stop(MSG_NO_ROUTE)

func _vitals_block(sheet: Dictionary) -> String:
	var v: Dictionary = sheet.get("vitals", {}) if sheet.get("vitals", {}) is Dictionary else {}
	# M3C_PLAN 缺漏：§4.4 寫 sheet.qi／sheet.food，實際角色表放在 sheet.vitals（兩種都讀）
	var qi_max := float(v.get("qi_max", sheet.get("qi_max", 0)))
	var qi := float(v.get("qi", sheet.get("qi", qi_max)))
	if qi_max > 0.0 and qi < qi_max * QI_MIN_RATIO:
		return MSG_QI
	var has_food := v.has("food") or sheet.has("food")
	var has_water := v.has("water") or sheet.has("water")
	var hungry := has_food and float(v.get("food", sheet.get("food", 100))) < FOOD_MIN
	var thirsty := has_water and float(v.get("water", sheet.get("water", 100))) < WATER_MIN
	if hungry and thirsty:
		return MSG_HUNGRY_THIRSTY
	if hungry:
		return MSG_HUNGRY
	if thirsty:
		return MSG_THIRSTY
	return ""

func _jailed(sheet: Dictionary) -> bool:
	var j: Variant = sheet.get("jail", null)
	return (j is Dictionary and not (j as Dictionary).is_empty()) or (j is bool and j)

func _reason(code: String) -> String:
	if reason_text.is_valid():
		var t := str(reason_text.call(code))
		if t != "":
			return t
	return code

func _room(room_id: String) -> Dictionary:
	if _rooms.is_empty():
		var maps: Variant = tables.get("maps", {})
		if not (maps is Dictionary):
			return {}
		for rid in maps:
			var m: Variant = maps[rid]
			if not (m is Dictionary) or not (m.get("rooms", []) is Array):
				continue
			for room in m["rooms"]:
				if room is Dictionary and str(room.get("id", "")) != "" and not _rooms.has(str(room["id"])):
					_rooms[str(room["id"])] = room
	var r: Variant = _rooms.get(room_id, {})
	return r if r is Dictionary else {}

func _room_name(room_id: String) -> String:
	var r := _room(room_id)
	return str(r.get("name", room_id)) if not r.is_empty() else room_id
