class_name RegionSystem
extends RefCounted
## 房間占用、移動、房間視圖（3.9.2）、進出房間事件、踩地雷（4.14）。M1_PLAN 3.5.2。
## 房間占用不另存：由在線 session 的角色位置推得。

const SMOKE_MULT := 0.1

var host: GameHost

## intents_debug.gd META_ENCOUNTER_NEXT（同值）
const DEBUG_ENCOUNTER_NEXT := "dbg_encounter_next"

func _init(p_host: GameHost) -> void:
	host = p_host

func sessions_in(room_id: String, except_peer := 0) -> Array:
	var out: Array = []
	for s in host.sessions():
		if s.peer_id != except_peer and s.character != null and s.room_id() == room_id:
			out.append(s)
	return out

func mark_room_dirty(room_id: String, except_peer := 0) -> void:
	for s in sessions_in(room_id, except_peer):
		s.view_dirty = true

## 選角進入世界：本人收 self（你來到了…），同房其他人收 other（…出現在這裡）
func enter_world(s: Session) -> void:
	var room := s.room_id()
	s.last_region = host.index.region_of(room)   # M3a：登入不算「走進這個地區」
	host.ws.queue_room_event(room, Protocol.CH_SCENE, Protocol.E_CHAR_ENTERED,
		{ "name": s.character.name, "peer": s.peer_id, "room_name": host.room_name(room) })
	mark_room_dirty(room, s.peer_id)
	s.view_dirty = true

## room：要通知的房間；空字串＝角色目前的位置
func leave_world(s: Session, room := "") -> void:
	if room == "":
		room = s.room_id()
	host.ws.queue_room_event(room, Protocol.CH_SCENE, Protocol.E_CHAR_LEFT,
		{ "name": s.character.name, "peer": s.peer_id }, s.peer_id)
	mark_room_dirty(room, s.peer_id)

## 步行移動到相鄰房間：room_leave（舊房其他人）→ 換位置 → room_enter（新房其他人）
func _walk(s: Session, to_room: String, dir: String) -> void:
	var ch = s.character
	var from := s.room_id()
	_scout_moved(s)
	host.quests.drop_dialogue(s)   # STORY_PLAN §4.5：移動時清掉對話游標
	host.ws.queue_room_event(from, Protocol.CH_SCENE, Protocol.E_ROOM_LEAVE,
		{ "name": ch.name, "peer": s.peer_id, "dir_label": WorldIndex.dir_label(dir) }, s.peer_id)
	mark_room_dirty(from, s.peer_id)
	ch.location = { "region": host.index.region_of(to_room), "room": to_room }
	var back := WorldIndex.reverse_dir(dir)
	host.ws.queue_room_event(to_room, Protocol.CH_SCENE, Protocol.E_ROOM_ENTER,
		{ "name": ch.name, "peer": s.peer_id, "from_label": WorldIndex.dir_label(back) if back != "" else "" }, s.peer_id)
	mark_room_dirty(to_room, s.peer_id)
	s.view_dirty = true

## 換房間：查看偵察的提示失效（ScoutSystem）；冷卻還沒完時重送角色表（安全的房間 cooldowns.scout 歸 0，回到野外再顯示）
func _scout_moved(s: Session) -> void:
	if host.scout == null:
		return
	host.scout.invalidate(s, ScoutSystem.WHY_MOVED)
	if s.scout_ready_s > host.now_s() or s.scout_ready_ms > Time.get_ticks_msec():
		s.sheet_dirty = true

## 瞬間移動（驛站、重生、引路、押入／放出思過處）：不送步行文字，只更新兩邊的房間視圖。
## M1_PLAN 缺漏：3.8 沒有「搭車離開／醒轉出現」給旁人的事件 key，這裡只刷新旁人的房間視圖。
## hooks：跑 SectSystem.on_enter_room（M3A_PLAN 6.1「走路／瞬移後呼叫」）；押入／放出思過處與 debug 瞬移傳 false。
func teleport(s: Session, to_room: String, hooks := true) -> void:
	var ch = s.character
	var from := s.room_id()
	_scout_moved(s)
	host.quests.drop_dialogue(s)
	mark_room_dirty(from, s.peer_id)
	ch.location = { "region": host.index.region_of(to_room), "room": to_room }
	mark_room_dirty(to_room, s.peer_id)
	s.view_dirty = true
	if hooks and host.sects != null:
		host.sects.on_enter_room(s, to_room)
	elif not hooks:
		s.last_region = host.index.region_of(to_room)
	if hooks:
		host.m3d_enter_room(s, from, to_room)   # M3d WP-LAW
		enter_status(s, to_room)

## move intent：jailed → no_exit → room_locked → overweight → 移動 → REACH → 門派（門規、敵對入山）→ 踩地雷
func move(s: Session, dir: String) -> Dictionary:
	var ch = s.character
	if ch.is_jailed():
		return GameHost.fail("jailed")   # 思過處走不出去（§6.6；GameHost 的坐牢關卡已先擋，這裡防禦性再擋）
	var ex := host.index.exit_of(s.room_id(), dir)
	var to := str(ex.get("to", ""))
	if ex.is_empty() or not host.index.has_room(to):
		return GameHost.fail("no_exit")
	if lock_reason(ch, to, _ctx(s)) != "":
		return GameHost.fail("room_locked")
	var d: Dictionary = ch.derived(host.tables, host.options)
	if int(d.get("carry", 0)) > int(d.get("carry_max", 0)):
		return GameHost.fail("overweight")
	var from := s.room_id()
	_walk(s, to, dir)
	host.quests.on_reach(s)
	# M2_PLAN 4.6.1：隊伍（跟隨、視圖）→ 守衛（進出城；已開戰就不擲遇敵）→ 踩地雷
	host.m2_call(host.party, "on_moved", [s])
	# STORY_PLAN §5.2、§5.3：離開房間脫離惡人的警告、進房遇到惡人；環境句（系統為 null 時略過）
	host.m2_call(host.wander, "on_moved", [s, from, to])
	host.m2_call(host.ambient, "on_enter_room", [s, from, to])
	if host.pk != null and bool(host.m2_call(host.pk, "on_move", [s, from, to], false)):
		return GameHost.ok()
	# M3A_PLAN 6.1：門規（ENTER_REGION、狀態規則）與敵對入山；已開戰（守山弟子）就不擲遇敵
	if host.sects != null:
		host.sects.on_enter_room(s, to)
		if s.battle_id != 0 or ch.is_jailed():
			return GameHost.ok()
	host.m3d_enter_room(s, from, to)   # M3d WP-LAW
	enter_status(s, to)   # M3B_PLAN §4.10：情花林等房間的 on_enter_status
	roll_encounter(s)
	return GameHost.ok()

## M3B_PLAN §4.10：房間 on_enter_status { status, level, chance, unless } → ConditionSystem.add（戰後持續狀態）。
## 在戰鬥中、坐牢中、狀態不存在、unless 有一條成立（例：身上帶著絕情丹）時不施加。回傳是否施加了
func enter_status(s: Session, room_id: String) -> bool:
	if s == null or s.character == null or s.battle_id != 0 or s.character.is_jailed():
		return false
	var oes: Variant = host.index.room(room_id).get("on_enter_status", null)
	if not (oes is Dictionary):
		return false
	var sid := str(oes.get("status", ""))
	if sid == "" or not host.tables.get("status_effects", {}).has(sid):
		return false
	var unless: Variant = oes.get("unless", [])
	if unless is Array:
		for c in unless:
			if c is Dictionary and Requirements.ok([c], s.character, host.tables, host.options, host.rules, _ctx(s)):
				return false
	if host.rng.randf() >= float(oes.get("chance", 1.0)):
		return false
	var cs = host.get("conditions")
	if cs == null or not (cs as Object).has_method("add"):
		return false
	return bool(cs.add(s, sid, maxi(1, int(oes.get("level", 1)))))

func is_locked(ch, room_id: String) -> bool:
	return lock_reason(ch, room_id) != ""

func _ctx(s: Session) -> Dictionary:
	return host.sects.req_ctx(s) if host.sects != null else {}

## 進不去的原因碼（req_*）；可進入回 ""。ctx：主機端條件環境（hour_in、party_size_min；M3A_PLAN 3.7）
func lock_reason(ch, room_id: String, ctx: Dictionary = {}) -> String:
	if host.sects != null:
		var lk: String = host.sects.lockout_reason(ch, room_id)   # 恆山犯戒：進不了山（M3a 審查 #1）
		if lk != "":
			return lk
	var reqs: Variant = host.index.room(room_id).get("requires", [])
	if not (reqs is Array) or reqs.is_empty():
		return ""
	return Requirements.check(reqs, ch, host.tables, host.options, host.rules, ctx)

## 這個門派的弟子在此房間不踩地雷、不能偵察（房間 encounter_exempt；古墓迷宮「專人帶路」，M3A_PLAN 3.6）
func encounter_exempt(ch, room_id: String) -> bool:
	if ch == null or str(ch.sect) == "":
		return false
	var ex: Variant = host.index.room(room_id).get("encounter_exempt", [])
	return ex is Array and (ex as Array).has(str(ch.sect))

## 房間遇敵表中最強的怪物名稱（依 combat_xp_ref）；沒有遇敵回 ""
func danger_top(room_id: String) -> String:
	var enc: Variant = host.index.room(room_id).get("encounter", {})
	if not (enc is Dictionary) or float(enc.get("rate", 0.0)) <= 0.0:
		return ""
	var best := ""
	var best_ref := -1
	for e in enc.get("table", []):
		if not (e is Dictionary) or float(e.get("w", 0)) <= 0.0:
			continue
		var mid := str(e.get("monster", ""))
		var ref := int(host.tables.get("monsters", {}).get(mid, {}).get("combat_xp_ref", 0))
		if ref > best_ref:
			best_ref = ref
			best = mid
	return host.monster_name(best) if best != "" else ""

## 4.14：只在進入房間時判定；守護者之煙 ×0.1
func roll_encounter(s: Session) -> bool:
	var room_id := s.room_id()
	if host.index.encounter_rate(room_id) <= 0.0 or s.battle_id != 0:
		return false
	# M3C_PLAN §8 debug_set encounter_next：下一次可遇敵的移動必定遇敵（只在 --debug-intents；不看 encounters_enabled）
	var forced := s.has_meta(DEBUG_ENCOUNTER_NEXT) and bool(s.get_meta(DEBUG_ENCOUNTER_NEXT))
	# 伺服器選項 encounters_enabled【設計提案・測試／管理用】：false＝不擲踩地雷（M2 驗收用來排除路上的隨機死亡）
	if host.options.get("encounters_enabled", true) == false and not forced:
		return false
	var ch = s.character
	if ch.is_jailed() or encounter_exempt(ch, room_id):
		return false
	var mult := SMOKE_MULT if float(ch.buffs.get("smoke_until_s", 0.0)) > host.now_s() else 1.0
	var ids: Array = Encounter.pick(host.index.room(room_id), host.rng) if forced 		else Encounter.roll(host.index.room(room_id), host.rng, mult)
	if forced and not ids.is_empty():
		s.remove_meta(DEBUG_ENCOUNTER_NEXT)
	if ids.is_empty():
		return false
	var names: PackedStringArray = []
	for mid in ids:
		names.append(host.monster_name(str(mid)))
	host.tell(s, Protocol.CH_BATTLE, Protocol.E_ENCOUNTER, {
		"clock": host.clock()["text"], "room_name": host.room_name(room_id), "monsters": "、".join(names) })
	start_encounter(s, ids)
	return true

## 踩地雷／查看偵察迎戰共用的開戰：房間 encounter.no_flee（古墓迷宮「不能逃跑」，研究 17173 2001-07-05）→ 逃跑回 no_flee
func start_encounter(s: Session, ids: Array) -> int:
	var enc: Variant = host.index.room(s.room_id()).get("encounter", {})
	if enc is Dictionary and bool(enc.get("no_flee", false)) and (host.battles as Object).has_method("start_ex"):
		return int(host.battles.start_ex(s, ids, "ENCOUNTER", { "no_flee": true }))
	return int(host.battles.start(s, ids, "ENCOUNTER"))

## 3.9.2 players[] 的一列；M2_PLAN 4.5.2 合併 pk.player_tags（align、newbie）與 party.player_tags（party_id）。
## M3B_PLAN §6：seizable（對看的人而言是本派公敵；viewer 為 null 時 false）、org_name（OrgSystem）。
## 系統為 null 時給同形狀的預設值
func player_entry(o: Session, viewer: Session = null) -> Dictionary:
	var c = o.character
	var e := {
		"peer": o.peer_id, "name": str(c.name), "char_id": str(c.id),
		"align": GameHost.align_of(int(c.morality)),
		"newbie": int(c.combat_xp) < int(host.options.get("newbie_pk_protect_xp", 500)),
		"party_id": "",
		"in_battle": o.battle_id != 0,
		"battle_id": o.battle_id,
	}
	var pt: Variant = host.m2_call(host.pk, "player_tags", [o], {})
	if pt is Dictionary:
		e.merge(pt, true)
	var pa: Variant = host.m2_call(host.party, "player_tags", [o], {})
	if pa is Dictionary:
		e.merge(pa, true)
	e["seizable"] = false
	e["org_name"] = ""
	var og: Variant = host.m2_call(host.orgs, "player_tags", [o], {})
	if og is Dictionary:
		e.merge(og, true)
	if host.sects != null:
		e.merge(host.sects.player_tags(viewer, o), true)
	e.merge(host.m3d_player_tags(viewer, o), true)   # M3d WP-LAW
	return e

## 3.9.2
func view(s: Session) -> Dictionary:
	var ch = s.character
	var room_id := s.room_id()
	var room := host.index.room(room_id)
	var region_id := host.index.region_of(room_id)
	var c := host.clock()
	var exits: Array = []
	var ctx := _ctx(s)
	# M3d 審查：迷陣（房間列 hide_exit_names）的出口一律顯示本房的名字，不洩漏哪個方向通往陣口（八卦泥陣）【設計提案】
	var hide_names := bool(room.get("hide_exit_names", false))
	for ex in room.get("exits", []):
		if not (ex is Dictionary):
			continue
		var to := str(ex.get("to", ""))
		var why := lock_reason(ch, to, ctx)
		exits.append({
			"dir": str(ex.get("dir", "")), "label": WorldIndex.dir_label(str(ex.get("dir", ""))),
			"to": to, "to_name": str(room.get("name", "")) if hide_names else host.room_name(to), "locked": why != "", "lock_reason": why,
		})
	var npc_list: Array = []
	# STORY_PLAN §4.11 #3、§4.14：appear 每位玩家各自判斷；護送中的 NPC 跟著玩家（escort: true）
	var escorts: Array = host.quests.escort_npcs(ch)
	for npc_id in host.index.npcs_in(room_id):
		if escorts.has(npc_id) or not host.quests.npc_visible(ch, npc_id):
			continue
		# 遊蕩惡人夜裡離開定點時不在家（WanderSystem.npc_shown；null 時一律顯示）
		if host.m2_call(host.wander, "npc_shown", [npc_id, room_id], true) == false:
			continue
		# M3c（§5.3）：被殺後重生前的 NPC 不列
		if host.m2_call(host.npcpk, "npc_down", [npc_id], false) == true:
			continue
		var row := host.npc_row(npc_id)
		if row.is_empty():
			continue
		npc_list.append(_npc_entry(npc_id, row, false, s))
	var escort_list: Array = []
	for npc_id in escorts:
		npc_list.append(_npc_entry(npc_id, host.npc_row(npc_id), true, s))
		escort_list.append({ "npc": npc_id, "name": host.npc_name(npc_id) })
	var players: Array = []
	for o in sessions_in(room_id):
		players.append(player_entry(o, s))
	var rate := host.index.encounter_rate(room_id)
	var bl: Variant = host.m2_call(host.battles, "room_battles", [room_id, s], [])
	var wl: Variant = host.m2_call(host.wander, "view_for", [s], [])
	return {
		"pk_allowed": bool(host.tables.get("regions", {}).get(region_id, {}).get("pk_allowed", false)),   # M2_PLAN 4.5.2
		"battles": bl if bl is Array else [],
		"region": region_id, "region_name": host.region_name(region_id),
		"room": room_id, "room_name": str(room.get("name", room_id)),
		"desc": str(room.get("desc", "")), "clock": c["text"], "night": c["night"],
		"exits": exits, "npcs": npc_list, "players": players,
		"features": (room.get("features", []) as Array).duplicate(),
		"corpses": host.corpses.in_room(room_id, ch),
		"danger": rate > 0.0,
		"danger_top": danger_top(room_id),   # 此地最強的怪物（UI 顯示「野外・危險：野狼」）
		"safe": rate <= 0.0,
		# 故事包（STORY_PLAN §4.14）
		"story_actions": host.quests.room_actions(ch, room_id),
		"escort": escort_list,
		"wanderers": wl if wl is Array else [],
	}

## M3C_PLAN §8：npcs[].atk ＝ NpcAttackSystem.view_entry（null＝不能動手；系統為 null 時 null）
func _npc_entry(npc_id: String, row: Dictionary, escort: bool, s: Session = null) -> Dictionary:
	var services: Array = (row.get("services", []) as Array).duplicate()
	if not host.npcs.stagecoach_enabled():
		services.erase("TRAVEL")   # 馬車關閉時不顯示驛站服務（WORLD_2001 D5）
	var e := {
		"id": npc_id, "name": str(row.get("name", npc_id)), "kind": str(row.get("kind", "")),
		"services": services, "closed": host.npc_closed(row),
	}
	if escort:
		e["escort"] = true
	e["atk"] = host.m2_call(host.npcpk, "view_entry", [s, npc_id], null) if s != null and not escort else null
	return e
