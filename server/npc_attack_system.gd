class_name NpcAttackSystem
extends RefCounted
## 攻擊 NPC（M3C_PLAN §5；M3c 項目 ATTACK_SECT_NPC＋一般 NPC PK）。GameHost.npcpk（以路徑 load()，N4）。
## - 只有 npcs.json 標了 `attack` 的 NPC 能動手（§5.2 綁定清單；其他一律 npc_not_attackable）。
## - KILL：主單位被殺 → 世界 npc_down[npc] = { until_s, by }，到時重生（tick）；CHALLENGE：NPC 永不消失，只「敗走」。
## - 同一位 NPC 同時只能有一場攻擊戰（_busy；第二人 npc_busy＋battle_id，可用既有 battle_join 加入）。
## - 善惡、殺氣：既有戰鬥獎勵依主單位的 monster_row（morality_on_kill／killing_intent_on_kill）給最後一擊者；
##   怪物列沒有給（no_rewards 或兩個值都是 0，例如 GUARD 用的既有 m_city_guard）時由本系統依 §5.4 類別表補一次。
## - 門派後果：動手就算（SectSystem.on_npc_attack）、殺了才算（SectSystem.on_npc_killed）；城內守衛（PkSystem.guard_strike）。
## 主機權威：全部驗證在這裡；客戶端的 atk／menu 欄位只是顯示。

const MODE_KILL := "KILL"
const MODE_CHALLENGE := "CHALLENGE"
const VIA_CTRL := "CTRL"
const VIA_MENU := "MENU"
const VIA_BOTH := "BOTH"
const INTENT_ATTACK := "ATTACK"       # Ctrl+點
const INTENT_MIEPAI := "MIEPAI"       # 對話選單（滅派／硬闖）
const BATTLE_KIND := "NPC_ATTACK"
const DOWN_KEY := "npc_down"          # world.json（§9.1）
const EXT_KEY := "npcpk"              # 角色 ext.npcpk（§9.1）：{ "miepai": { sect_id: 次數 }, "routed": { npc_id: until_s } }
## M3c 審查：CHALLENGE 的 NPC 被打退後，同一角色要等「重生時間」（attack.respawn 或類別預設，CHALLENGE 沒有預設＝3 時辰）
## 才能再找他動手（防止無限刷實戰、學點、善惡）【設計提案】。參戰的每一位玩家都記
const ROUTED_KEY := "routed"
const EVENT_MIEPAI := "MIEPAI"
const EVENT_ATTACK_MASTER := "ATTACK_MASTER"

## §5.4 類別預設重生（時辰；KILL 才用）【設計提案・待考證：原作無資料】
const CATEGORY_RESPAWN := { "CIVILIAN": 3, "CHILD": 3, "ANIMAL": 1, "WORKER": 3, "GUARD": 1, "VILLAIN": 6 }
const DEFAULT_RESPAWN := 3
## §5.4 類別善惡／殺氣（每殺一個；方向【已證實 jyfree jy1_4_1】、量【設計提案】）。怪物列沒有給時才由本系統補
const CATEGORY_DELTAS := {
	"CIVILIAN": [-10, 10], "CHILD": [-20, 20], "ANIMAL": [-3, 2], "WORKER": [-10, 10], "GUARD": [-5, 10],
	"WUSHI": [-10, 10], "VILLAIN": [10, 5], "SECT_MASTER": [10, 20],
}
## §5.5 城內招來的官兵人數（主單位類別）
const GUARD_CALL := { "CIVILIAN": 1, "CHILD": 1, "ANIMAL": 1, "WORKER": 1, "GUARD": 2 }
const CATEGORY_NAMES := {
	"CIVILIAN": "城市居民", "CHILD": "小孩", "ANIMAL": "小動物", "WORKER": "採礦師", "GUARD": "守衛", "WUSHI": "武館武師",
	"VILLAIN": "惡人", "SECT_GATE": "門派守門", "SECT_DISCIPLE": "門派弟子", "SECT_MASTER": "掌門",
}

var host
## npc_id -> { bid, char_id, peer, mode }（記憶體，不存檔：主機重開時戰鬥本來就 ABORTED）
var _busy: Dictionary = {}

func _init(p_host) -> void:
	host = p_host

# ======================================================================== 查詢

## NPC 的 attack 欄位（沒有＝{}）
func attack_of(npc_id: String) -> Dictionary:
	var a: Variant = host.npc_row(npc_id).get("attack", {})
	return a if a is Dictionary else {}

func enabled() -> bool:
	return host.rules.get("npc_attack", true) != false

## via 允不允許這個動手方式
static func via_allows(via: String, mode: String) -> bool:
	if via == "":
		via = VIA_CTRL
	if mode == INTENT_MIEPAI:
		return via == VIA_MENU or via == VIA_BOTH
	return via == VIA_CTRL or via == VIA_BOTH

## 這位 NPC 牽涉的門派：attack.sect，省略＝SectSystem.npc_sect
func sect_of(npc_id: String, attack: Dictionary) -> String:
	var s0 := str(attack.get("sect", ""))
	if s0 != "":
		return s0
	var sects = host.get("sects")
	if sects != null and sects.has_method("npc_sect"):
		return str(sects.npc_sect(npc_id))
	return ""

## 實際的門派事件："MIEPAI"／"ATTACK_MASTER"／""（§5.1 event：省略＝依 category 推）
static func event_of(attack: Dictionary, mode: String) -> String:
	var ev := str(attack.get("event", ""))
	if ev != "":
		return ev
	if str(attack.get("category", "")) == "SECT_MASTER":
		return EVENT_ATTACK_MASTER
	if mode == INTENT_MIEPAI:
		return EVENT_MIEPAI
	return ""

## 主單位的怪物列陣營（GOOD／NEUTRAL／EVIL）
func alignment_of(attack: Dictionary) -> String:
	var row: Dictionary = host.tables.get("monsters", {}).get(str(attack.get("monster", "")), {})
	return str(row.get("alignment", "NEUTRAL"))

## 這次動手對這位玩家會有的門派後果："BREACH"（違反門規）、"BETRAY"（叛派）、"ENEMY"（成為公敵）、""
func sect_effect(ch, npc_id: String, attack: Dictionary, mode: String) -> String:
	var sid := sect_of(npc_id, attack)
	if sid == "" or ch == null:
		return ""
	var ev := event_of(attack, mode)
	var cat := str(attack.get("category", ""))
	if str(ch.sect) == sid:
		return "BETRAY" if ev == EVENT_ATTACK_MASTER else "BREACH"
	if cat == "SECT_GATE" or ev == EVENT_MIEPAI or ev == EVENT_ATTACK_MASTER or cat == "SECT_MASTER":
		return "" if ch.sect_enemies.has(sid) else "ENEMY"
	return ""

## 給確認框的警告文字（主機算好；UI 也會自己依 sheet 組，這裡是一句話的摘要）
func warn_text(ch, npc_id: String, attack: Dictionary, mode: String) -> String:
	var parts: PackedStringArray = []
	var align := alignment_of(attack)
	if align == "GOOD":
		parts.append("殺死善良的人，善惡會下降")
	elif align == "EVIL":
		parts.append("殺死惡人，善惡會上升")
	if GUARD_CALL.has(str(attack.get("category", ""))) and _city_guarded(host.index.region_of(host.index.room_of_npc(npc_id))) 			and not _is_newbie(ch):
		parts.append("城裡會招來守城官兵")
	# M3c 審查：善惡變負以後，進出有官兵的城都會挨打（新手保護期間例外，MoralityPk.guard_count）
	if _morality_guard_warn(ch, attack):
		parts.append("善惡變成負的以後，每次進出有官兵的城都會被守城官兵攻擊")
	var sid := sect_of(npc_id, attack)
	var sname := _sect_name(sid)
	match sect_effect(ch, npc_id, attack, mode):
		"BREACH":
			parts.append("你是%s弟子，對同門動手會違反門規" % sname)
		"BETRAY":
			parts.append("對%s動手＝叛出%s" % [host.npc_name(npc_id), sname])
		"ENEMY":
			parts.append("動手後你將成為%s公敵" % sname)
	if str(attack.get("mode", MODE_KILL)) == MODE_CHALLENGE:
		parts.append("此人不會被你殺死，但後果照算")
	return "；".join(parts)

## 這次動手會讓善惡下降、而且這個人不在新手保護內（善惡變負後進出城會挨官兵）→ 確認框要警告
func _morality_guard_warn(ch, a: Dictionary) -> bool:
	var align := alignment_of(a)
	return ch != null and (align == "GOOD" or align == "NEUTRAL") and not _is_newbie(ch)

## 守城官兵會不會放過這個人（新手且規則 newbie_guard_spare 開；PkSystem.guard_spares）。M3c 第二輪審查：classic_strict 不放過
func _is_newbie(ch) -> bool:
	if ch == null:
		return false
	var pk = host.get("pk")
	if pk != null and pk.has_method("guard_spares"):
		return bool(pk.guard_spares(ch))
	return MoralityPk.is_newbie(int(ch.combat_xp), 500)

## 這次動手要面對的對手（確認框用，M3c 審查）：[{ name, n }]，n 是 "3" 或 "1–2"；主單位（NPC 本人）在第一個
func foes_of(ch, npc_id: String, attack: Dictionary, _mode: String) -> Array:
	var out: Array = [{ "name": host.npc_name(npc_id), "n": "1" }]
	var group: Variant = attack.get("group", [])
	var rep: Variant = attack.get("group_repeat", [])
	if rep is Array and not (rep as Array).is_empty() and ch != null:
		var sid := sect_of(npc_id, attack)
		if _miepai_count(ch, sid if sid != "" else npc_id) > 0:
			group = rep
	if group is Array:
		for g in group:
			if not (g is Dictionary):
				continue
			var mid := str(g.get("monster", ""))
			if not host.tables.get("monsters", {}).has(mid):
				continue
			var cnt: Variant = g.get("count", [1, 1])
			var lo := 1
			var hi := 1
			if cnt is Array and (cnt as Array).size() >= 2:
				lo = maxi(0, int(cnt[0]))
				hi = maxi(lo, int(cnt[1]))
			if hi <= 0:
				continue
			out.append({ "name": host.monster_name(mid), "n": str(lo) if lo == hi else "%d–%d" % [lo, hi] })
	return out

func _sect_name(sid: String) -> String:
	if sid == "":
		return ""
	var n := str(host.tables.get("sects", {}).get(sid, {}).get("name", sid))
	return n if n.ends_with("派") or n.ends_with("門") or n.ends_with("教") or n.ends_with("宮") or n.ends_with("幫") else n + "派"

func _city_guarded(region_id: String) -> bool:
	var pk = host.get("pk")
	if pk != null and pk.has_method("city_with_guard"):
		return bool(pk.city_with_guard(region_id))
	return false

## 正在消失（KILL 後、重生前）
func npc_down(npc_id: String) -> bool:
	var d: Variant = host.ws.world.get(DOWN_KEY, {})
	if not (d is Dictionary) or not (d as Dictionary).has(npc_id):
		return false
	var e: Variant = d[npc_id]
	return e is Dictionary and float(e.get("until_s", 0.0)) > host.now_s()

func _down() -> Dictionary:
	var d: Variant = host.ws.world.get(DOWN_KEY, null)
	if not (d is Dictionary):
		d = {}
		host.ws.world[DOWN_KEY] = d
	return d

## 某 NPC 目前的攻擊戰 bid（沒有＝0）；鎖住的戰鬥已不存在時順手解鎖
func busy_bid(npc_id: String) -> int:
	if not _busy.has(npc_id):
		return 0
	var bid := int(_busy[npc_id].get("bid", 0))
	if host.battles == null or not host.battles.active.has(bid):
		_busy.erase(npc_id)
		return 0
	return bid

# ======================================================================== 房間視圖與選單（§5.3、§8）

## view.npcs[].atk：{ mode, category, align, sect, menu_label, warn, via } 或 null（不能 Ctrl+點動手）
func view_entry(s: Session, npc_id: String) -> Variant:
	var a := attack_of(npc_id)
	if a.is_empty() or not enabled() or not via_allows(str(a.get("via", VIA_CTRL)), INTENT_ATTACK):
		return null
	var ch = s.character if s != null else null
	return {
		"mode": str(a.get("mode", MODE_KILL)), "category": str(a.get("category", "")),
		"align": alignment_of(a), "sect": sect_of(npc_id, a), "menu_label": str(a.get("menu_label", "")),
		"warn": warn_text(ch, npc_id, a, INTENT_ATTACK), "via": str(a.get("via", VIA_CTRL)),
		"effect": sect_effect(ch, npc_id, a, INTENT_ATTACK),
		"foes": foes_of(ch, npc_id, a, INTENT_ATTACK),
		"morality_guard": _morality_guard_warn(ch, a),
		"guard_spare": _is_newbie(ch),   # M3c 第二輪審查：守城官兵會放過這位新手（確認框不寫「會招來官兵」）
	}

## npc_menu.attack：{ ok, reason, label, warn } 或 {}（只有 via 含 MENU 的 NPC）
func menu_fields(s: Session, npc_id: String) -> Dictionary:
	var a := attack_of(npc_id)
	if a.is_empty() or not via_allows(str(a.get("via", VIA_CTRL)), INTENT_MIEPAI):
		return {}
	var why := check(s, npc_id, INTENT_MIEPAI)
	var ch = s.character if s != null else null
	return { "ok": why == "", "reason": why, "label": str(a.get("menu_label", "滅派")),
		"warn": warn_text(ch, npc_id, a, INTENT_MIEPAI), "effect": sect_effect(ch, npc_id, a, INTENT_MIEPAI),
		"foes": foes_of(ch, npc_id, a, INTENT_MIEPAI), "sect_name": _sect_name(sect_of(npc_id, a)),
		"morality_guard": _morality_guard_warn(ch, a), "guard_spare": _is_newbie(ch) }

# ======================================================================== npc_attack

## §5.3 驗證順序（第一個失敗就回）：npc_attack_off → NPC 不在（npc_here）→ npc_not_attackable → npc_safe_room
## → jailed → npc_busy → attack.requires（req_*）。回 "" 表示可以
func check(s: Session, npc_id: String, mode: String) -> String:
	if not enabled():
		return Protocol.R_NPC_ATTACK_OFF
	var here: String = host.npc_here(s, npc_id)
	if here != "":
		return here
	var a := attack_of(npc_id)
	if a.is_empty() or not via_allows(str(a.get("via", VIA_CTRL)), mode):
		return Protocol.R_NPC_NOT_ATTACKABLE
	if bool(host.index.room(s.room_id()).get("safe", false)):
		return Protocol.R_NPC_SAFE_ROOM
	if s.character.is_jailed():
		return Protocol.R_JAILED
	if busy_bid(npc_id) != 0:
		return Protocol.R_NPC_BUSY
	return _check_person(s, npc_id, a)

## 對這個人的檢查（check 與 join_reason 共用）：剛被打退（npc_routed）→ attack.requires（req_*）
func _check_person(s: Session, npc_id: String, a: Dictionary) -> String:
	if str(a.get("mode", MODE_KILL)) == MODE_CHALLENGE and routed_left(s.character, npc_id) > 0.0:
		return Protocol.R_NPC_ROUTED
	var req: Variant = a.get("requires", [])
	if req is Array and not (req as Array).is_empty():
		var ctx: Dictionary = host.sects.req_ctx(s) if host.get("sects") != null else {}
		var r: String = Requirements.check(req, s.character, host.tables, host.options, host.rules, ctx)
		if r != "":
			return r
	return ""

## CHALLENGE 的 NPC 被這個角色打退後還要等幾秒（世界秒；0 = 可以再打）
func routed_left(ch, npc_id: String) -> float:
	if ch == null:
		return 0.0
	var e: Variant = ch.ext.get(EXT_KEY, {})
	if not (e is Dictionary):
		return 0.0
	var m: Variant = (e as Dictionary).get(ROUTED_KEY, {})
	if not (m is Dictionary) or not (m as Dictionary).has(npc_id):
		return 0.0
	return maxf(0.0, float(m[npc_id]) - host.now_s())

func _set_routed(ch, npc_id: String, until_s: float) -> void:
	var e: Variant = ch.ext.get(EXT_KEY, {})
	if not (e is Dictionary):
		e = {}
	var m: Variant = (e as Dictionary).get(ROUTED_KEY, {})
	if not (m is Dictionary):
		m = {}
	for k in (m as Dictionary).keys():   # 過期的順手清掉（存檔不會越長越大）
		if float(m[k]) <= host.now_s():
			(m as Dictionary).erase(k)
	m[npc_id] = until_s
	e[ROUTED_KEY] = m
	ch.ext[EXT_KEY] = e

## 重生（KILL）／調息（CHALLENGE）的世界秒數：attack.respawn 或類別預設 × 1 時辰 × npc_respawn_pct
func respawn_span(a: Dictionary) -> float:
	var resp := int(a.get("respawn", CATEGORY_RESPAWN.get(str(a.get("category", "")), DEFAULT_RESPAWN)))
	var pct := clampi(int(host.options.get("npc_respawn_pct", 100)), 10, 1000)
	# M3C_PLAN 缺漏：§5.3 寫「1 時辰 = 7200 世界秒」，但 WorldClock 的 1 時辰 = game_day_real_s ÷ 12（預設 600 世界秒）；
	# 這裡照世界時鐘（玩家看到的時辰）算
	return float(maxi(1, resp)) * WorldClock.shichen_len(host.day_s()) * float(pct) / 100.0

# ======================================================================== battle_join（M3c 審查）

## 隊友用 battle_join 加入攻擊 NPC 的戰鬥（BattleSystem._join_check 呼叫）：與親自動手同樣的資格檢查
## （規則、坐牢、剛被打退、attack.requires；不看 busy 與房間——就是這一場、同一間）。回 "" 表示可以
func join_reason(s: Session, entry: Dictionary) -> String:
	if s == null or s.character == null:
		return "no_character"
	var npc_id := _entry_npc(entry)
	if npc_id == "":
		return ""
	if not enabled():
		return Protocol.R_NPC_ATTACK_OFF
	var a := attack_of(npc_id)
	if a.is_empty():
		return Protocol.R_NPC_NOT_ATTACKABLE
	if s.character.is_jailed():
		return Protocol.R_JAILED
	return _check_person(s, npc_id, a)

## 加入成功後（BattleSystem.join）：加入的人照樣承擔「動手就算」的門派後果（違反門規、叛派、公敵）
func on_join(s: Session, entry: Dictionary) -> void:
	var npc_id := _entry_npc(entry)
	if npc_id == "" or s == null or s.character == null:
		return
	var a := attack_of(npc_id)
	if a.is_empty():
		return
	var opts: Variant = entry.get("opts", {})
	var mode := str(opts.get("npc_mode", INTENT_ATTACK)) if opts is Dictionary else INTENT_ATTACK
	_sect_on_attack(s, npc_id, a, mode)

func _entry_npc(entry: Dictionary) -> String:
	if str(entry.get("kind", "")) != BATTLE_KIND:
		return ""
	var opts: Variant = entry.get("opts", {})
	return str(opts.get("npc", "")) if opts is Dictionary else ""

func _sect_on_attack(s: Session, npc_id: String, a: Dictionary, mode: String) -> void:
	var sects = host.get("sects")
	if sects != null and sects.has_method("on_npc_attack"):
		var aa := a.duplicate(true)
		aa["sect"] = sect_of(npc_id, a)
		aa["event"] = event_of(a, mode)
		sects.on_npc_attack(s, npc_id, aa)

## npc_attack 的處理器；mode "ATTACK"（Ctrl）或 "MIEPAI"（選單）
func attack(s: Session, npc_id: String, mode: String) -> Dictionary:
	if mode == "":
		mode = INTENT_ATTACK
	if not (mode in Protocol.NPC_ATTACK_MODES):
		return GameHost.fail("bad_value:mode")
	var why := check(s, npc_id, mode)
	if why != "":
		var f := GameHost.fail(why)
		if why == Protocol.R_NPC_BUSY:
			f["battle_id"] = busy_bid(npc_id)
		return f
	var a := attack_of(npc_id)
	var ch = s.character
	var sid := sect_of(npc_id, a)
	var ids: Array = [str(a.get("monster", ""))]
	var group: Variant = a.get("group", [])
	var rep: Variant = a.get("group_repeat", [])
	var times := _miepai_count(ch, sid if sid != "" else npc_id)
	var has_repeat: bool = rep is Array and not (rep as Array).is_empty()
	if has_repeat and times > 0:
		group = rep
	if group is Array:
		for g in group:
			if not (g is Dictionary) or not host.tables.get("monsters", {}).has(str(g.get("monster", ""))):
				continue
			var cnt: Variant = g.get("count", [1, 1])
			var lo := 1
			var hi := 1
			if cnt is Array and (cnt as Array).size() >= 2:
				lo = maxi(0, int(cnt[0]))
				hi = maxi(lo, int(cnt[1]))
			for i in host.rng.randi_range(lo, hi):
				ids.append(str(g["monster"]))
	var room := s.room_id()
	# M3c 審查：先開戰；開不成（bid <= 0）時什麼都不算（滅派次數不加、房間不出現動手的字）
	var bid := int(host.battles.start_ex(s, ids, BATTLE_KIND,
		{ "npc": npc_id, "npc_unit": true, "no_flee": false, "npc_mode": mode }))
	if bid <= 0:
		return GameHost.fail("bad_cmd")
	if has_repeat:
		_miepai_bump(ch, sid if sid != "" else npc_id)
	var start_key := Protocol.E_NA_MIEPAI if mode == INTENT_MIEPAI else Protocol.E_NA_ATTACK_START
	var p := { "name": str(ch.name), "npc_name": host.npc_name(npc_id), "peer": s.peer_id,
		"sect_name": _sect_name(sid), "n": ids.size() }
	host.ws.queue_room_event(room, Protocol.CH_SCENE, start_key, p)
	if host.battles.active.has(bid):
		_busy[npc_id] = { "bid": bid, "char_id": str(ch.id), "peer": s.peer_id, "mode": mode }
	# 動手就算的門派後果（§5.6 ATTACK 類）：開戰之後才處理，坐牢／開除的瞬移等戰鬥結束（SectSystem 既有行為）
	_sect_on_attack(s, npc_id, a, mode)
	host.regions.mark_room_dirty(room)
	return GameHost.ok({ "battle_id": bid })

func _miepai_count(ch, key: String) -> int:
	var e: Variant = ch.ext.get(EXT_KEY, {})
	if not (e is Dictionary):
		return 0
	var m: Variant = e.get("miepai", {})
	return int(m.get(key, 0)) if m is Dictionary else 0

func _miepai_bump(ch, key: String) -> void:
	var e: Variant = ch.ext.get(EXT_KEY, {})
	if not (e is Dictionary):
		e = {}
	var m: Variant = e.get("miepai", {})
	if not (m is Dictionary):
		m = {}
	m[key] = int(m.get(key, 0)) + 1
	e["miepai"] = m
	ch.ext[EXT_KEY] = e

# ======================================================================== 戰鬥結束（BattleSystem._finish 結尾）

func on_battle_finished(entry: Dictionary, out: Dictionary) -> void:
	if str(entry.get("kind", "")) != BATTLE_KIND:
		return
	var opts: Variant = entry.get("opts", {})
	var npc_id := str(opts.get("npc", "")) if opts is Dictionary else ""
	if npc_id == "":
		return
	var lock: Dictionary = _busy.get(npc_id, {})
	var b: Battle = entry["battle"]
	if int(lock.get("bid", -1)) == b.id:
		_busy.erase(npc_id)
	var a := attack_of(npc_id)
	if a.is_empty():
		return
	var npc_unit: BattleUnit = null
	for u in b.units:
		if str(u.spec.get("npc", "")) == npc_id:
			npc_unit = u
	var result := str(out.get("result", ""))
	var won := result != "ABORTED" and int(out.get("winner_side", -1)) == 0
	if npc_unit == null or not npc_unit.is_dead() or not won:
		return   # 玩家輸或逃：NPC 不消失，什麼都不結算（動手就算的已經算過）
	var room := str(entry.get("room", ""))
	var mode := str(a.get("mode", MODE_KILL))
	var killer_s: Session = null
	var killer_ch = null
	var k: BattleUnit = b.unit(int(npc_unit.killed_by))
	if k != null and k.is_player():
		killer_s = host.session_for_char(str(k.spec.get("ref", "")))
		killer_ch = _char_of(entry, str(k.spec.get("ref", "")))
	if killer_ch == null:
		killer_ch = _char_of(entry, str(lock.get("char_id", "")))
		killer_s = host.session_for_char(str(lock.get("char_id", "")))
	if killer_s != null and killer_s.character != killer_ch:
		killer_s = null
	var killer_name := str(killer_ch.name) if killer_ch != null else ""
	var p := { "name": killer_name, "npc_name": host.npc_name(npc_id), "room_name": host.room_name(room),
		"peer": killer_s.peer_id if killer_s != null else 0 }
	var span := respawn_span(a)
	if mode == MODE_KILL:
		_down()[npc_id] = { "until_s": host.now_s() + span, "by": str(killer_ch.id) if killer_ch != null else "" }
		host.ws.queue_room_event(room, Protocol.CH_SCENE, Protocol.E_NA_NPC_KILLED, p)
		if killer_s != null and killer_s.room_id() != room:
			host.tell(killer_s, Protocol.CH_SCENE, Protocol.E_NA_NPC_KILLED, p.duplicate())
		host.regions.mark_room_dirty(room)
	else:
		host.ws.queue_room_event(room, Protocol.CH_SCENE, Protocol.E_NA_NPC_ROUTED, p)
		# M3c 審查：打退後同一批人要等重生時間才能再找他動手（npc_routed）
		var until: float = host.now_s() + span
		var chars: Variant = entry.get("chars", {})
		if chars is Dictionary:
			for peer in chars:
				var c = chars[peer]
				if c == null or c == killer_ch:
					continue
				_set_routed(c, npc_id, until)
				host.save_char(c)
		if killer_ch != null:
			_set_routed(killer_ch, npc_id, until)
	if killer_ch != null:
		# 戰鬥獎勵只在最後一擊者「打完還站著」時才給善惡殺氣（BattleRewards killer_alive）：沒給到時這裡補
		var rewarded: bool = k != null and k.is_player() and k.is_active() and k.side == 0 \
				and str(k.spec.get("ref", "")) == str(killer_ch.id)
		_morality(killer_s, killer_ch, a, rewarded)
		var sects = host.get("sects")
		if sects != null and sects.has_method("on_npc_killed"):
			var aa := a.duplicate(true)
			aa["sect"] = sect_of(npc_id, a)
			sects.on_npc_killed(killer_s, killer_ch, npc_id, aa, alignment_of(a))
		# M3c 審查：_settle_player 已經存過檔；這裡的善惡、殺氣、佛法／慈悲、打退冷卻是之後才改的 → 一律再存一次
		host.save_char(killer_ch)
	# §5.5 守城官兵：城內殺居民／小孩／動物／採礦師（1 名）或守衛（2 名）
	var cat := str(a.get("category", ""))
	var guard_s: Session = killer_s
	if guard_s == null:
		guard_s = host.session_for_char(str(lock.get("char_id", "")))
	if GUARD_CALL.has(cat) and guard_s != null and _city_guarded(host.index.region_of(room)) and guard_s.room_id() == room:
		var pk = host.get("pk")
		if pk != null and pk.has_method("guard_strike"):
			pk.guard_strike(guard_s, int(GUARD_CALL[cat]), Protocol.E_NA_GUARD_ALARM)

func _char_of(entry: Dictionary, char_id: String):
	if char_id == "":
		return null
	var chars: Variant = entry.get("chars", {})
	if chars is Dictionary:
		for peer in chars:
			var c = chars[peer]
			if c != null and str(c.id) == char_id:
				return c
	var o: Session = host.session_for_char(char_id)
	return o.character if o != null else null

## 怪物列沒有給善惡／殺氣（no_rewards 或兩值皆 0）→ 依 §5.4 類別補一次；有給的由戰鬥獎勵算過。
## rewarded = 戰鬥獎勵真的給到了這個人（最後一擊者打完還站著）；沒給到（逃走、倒下）時照怪物列的值在這裡補
## （M3c 審查：以前會送「善惡 −10」的訊息、實際卻沒變）。兩種情況都送 morality_change／killing_intent_change
func _morality(s: Session, ch, a: Dictionary, rewarded := true) -> void:
	var row: Dictionary = host.tables.get("monsters", {}).get(str(a.get("monster", "")), {})
	var mo := int(row.get("morality_on_kill", 0))
	var ki := int(row.get("killing_intent_on_kill", 0))
	var by_rewards := not bool(row.get("no_rewards", false)) and (mo != 0 or ki != 0)
	var dm := mo
	var dk := ki
	if not by_rewards:
		var d: Array = CATEGORY_DELTAS.get(str(a.get("category", "")), [0, 0])
		dm = ch.add_morality(int(d[0]))
		dk = ch.add_killing_intent(int(d[1]))
	elif not rewarded:
		dm = ch.add_morality(mo)
		dk = ch.add_killing_intent(ki)
	if s == null:
		return
	if dm != 0:
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_MORALITY_CHANGE, { "delta": dm, "value": int(ch.morality) })
	if dk != 0:
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_KILLING_INTENT_CHANGE, { "delta": dk, "value": int(ch.killing_intent) })
	s.sheet_dirty = true
	host.regions.mark_room_dirty(s.room_id())   # 名字顏色可能變了

# ======================================================================== 重生（每分鐘）

func tick(now_s: float) -> void:
	var d: Variant = host.ws.world.get(DOWN_KEY, null)
	if not (d is Dictionary) or (d as Dictionary).is_empty():
		return
	for npc_id in (d as Dictionary).keys():
		var e: Variant = d[npc_id]
		if e is Dictionary and float(e.get("until_s", 0.0)) > now_s:
			continue
		_back(str(npc_id))

## debug_set npc_respawn_now：npc id 或 "*"
func respawn_now(which: String) -> void:
	var d: Variant = host.ws.world.get(DOWN_KEY, null)
	if not (d is Dictionary):
		return
	for npc_id in (d as Dictionary).keys():
		if which == "*" or which == str(npc_id):
			_back(str(npc_id))

func _back(npc_id: String) -> void:
	var d: Dictionary = _down()
	d.erase(npc_id)
	var room: String = host.index.room_of_npc(npc_id)
	if room == "":
		return
	host.ws.queue_room_event(room, Protocol.CH_SCENE, Protocol.E_NA_NPC_BACK,
		{ "npc_name": host.npc_name(npc_id), "room_name": host.room_name(room) })
	host.regions.mark_room_dirty(room)
