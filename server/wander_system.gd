class_name WanderSystem
extends RefCounted
## 遊蕩惡人與追擊 NPC（STORY_PLAN §5.2）。
## - 白天（HOME）照原作定點在 home_room，不主動出手；交談時 talk_fight.requires 成立即開打（kind FIGHT，可逃）。
##   【已證實】南海鱷神、葉二娘在西夏街上、交談即戰（官方自救手札、gaoshou/23）。
## - 夜裡（ROAM，D13：戌～寅）在允許地區的野外遊蕩，每 move_every_ke 刻走一步；不進安全房間、CITY、SECT、DUNGEON。
##   【設計提案・非原作】（擁有者要求），伺服器選項 wanderers_enabled。
## - 追擊 NPC「惡人頭子」（原作 2001-08-30）：全天 ROAM，列帶 "option": "chase_npcs"，選項關閉時整個不出現。
## - 出手：玩家進入／惡人移入同房，且（非安全房間、實戰 ≥ newbie_pk_protect_xp、玩家閒置、aggro.requires、
##   冷卻已過、擲 chance_pct）→ villain_prompt（倒數 villain_warn_s 真實秒）；倒數內離開 → ESCAPED；
##   倒數結束 → start_ex(…, "CHASE", { no_flee, pull_party })（研究：追擊戰不能逃）。
## - 被擊敗（勝方 side 0）→ 消失 respawn_days 遊戲日，發 VILLAIN 傳聞、記事蹟。
## - 狀態（位置、下次移動、重生時間、每位玩家冷卻）存 ws.world.wanderers；一律用世界時間（主機離線時凍結，S4）。
##
## 主機鉤子（WP-ENGINE 以 host.m2_call(host.wander, …) 呼叫；全部可缺，本系統另以 tick 輪詢玩家位置補上）：
##   tick(dt)、on_moved(s)、on_talk(s, npc_id) -> bool、view_for(s) -> Array、npc_shown(npc_id, room_id) -> bool、
##   on_leave(s)、villain_reply(s, wid, choice)、place(wid, room) -> bool（debug wander_place）。
## STORY_PLAN 缺漏：K3 的 `_init(p_host: GameHost)` 不加型別（同 PkSystem），讓單元測試可傳入假主機。

const MODE_HOME := "HOME"
const MODE_ROAM := "ROAM"
const KIND_CHASE := "CHASE"
const KIND_FIGHT := "FIGHT"
const WHY_ESCAPED := "ESCAPED"
const WHY_FOUGHT := "FOUGHT"
const WHY_GONE := "GONE"
const CHOICE_FIGHT := "FIGHT"
const CHOICE_CALL := "CALL"
const WORLD_KEY := "wanderers"
const EXT_KEY := "wander"
const DEFAULT_WARN_S := 3
const DEFAULT_PROTECT_XP := 500
const DEFAULT_MOVE_EVERY_KE := 4
const KE_PER_SHICHEN := 8
const BLOCKED_REGION_TYPES := ["CITY", "SECT", "DUNGEON"]
const SAFE_REGION_TYPES := ["CITY", "SECT"]

## 本系統送出的文字模板（_ambient 碎片提供）
const T_WARN := "villain_warn"            # 本人：{npc_name}朝你逼近！
const T_ATTACK := "villain_attack"        # 本人：{npc_name}向你撲來！
const T_ESCAPED := "villain_escaped"      # 本人：你甩開了{npc_name}
const T_CALL := "villain_call"            # 同地區的人：{name}在{room_name}遭{npc_name}襲擊
const T_CALL_SENT := "villain_call_sent"  # 本人：你高聲呼救
const T_HOME := "villain_home"            # 同房：{npc_name}回城去了
const T_OUT := "villain_out"              # 同房：{npc_name}出城去了
const T_MOVE_OUT := "villain_move_out"    # 同房：{npc_name}往{dir_label}走了
const T_MOVE_IN := "villain_move_in"      # 同房：{npc_name}走了過來
## 審查修正：新手（實戰 < newbie_pk_protect_xp）不會被出手，但會遇上一段不開打的威嚇（【設計提案・非原作】），
## 讓惡人不只是一行字。模板 wander_newbie_<wid> 存在就用它，否則 wander_newbie；每位角色每個惡人每遊戲日一次。
const T_NEWBIE := "wander_newbie"

var host
var _prompts: Dictionary = {}    # peer -> { wid, char_id, room, expires_s（世界時間）, called }（不存檔，§4.7）
var _seen_room: Dictionary = {}  # peer -> 上次看到的房間（輪詢「進房」用）
var _fights: Dictionary = {}     # bid -> { wid, battle, chars, room }（不存檔：關服時戰鬥本來就 ABORTED）
var _busy_skip: Dictionary = {}  # peer -> wid：惡人來時玩家正在對話（不閒置）而略過；閒下來後再判定一次（不存檔）
var _prune_acc := 0.0
const PRUNE_REAL_S := 60.0

func _init(p_host) -> void:
	host = p_host

# ======================================================================== 選項與資料

func roam_enabled() -> bool:
	return host.options.get("wanderers_enabled", true) != false

func warn_s() -> int:
	return maxi(0, int(host.options.get("villain_warn_s", DEFAULT_WARN_S)))

func protect_xp() -> int:
	return int(host.options.get("newbie_pk_protect_xp", DEFAULT_PROTECT_XP))

func rows() -> Dictionary:
	var t: Variant = host.tables.get("wanderers", {})
	return t if t is Dictionary else {}

func row(wid: String) -> Dictionary:
	var r: Variant = rows().get(wid, {})
	return r if r is Dictionary else {}

func ids() -> Array:
	var a := rows().keys()
	a.sort()
	return a

## 列被選項關掉（追擊 NPC 的 chase_npcs）時整個不出現
func row_active(r: Dictionary) -> bool:
	var opt := str(r.get("option", ""))
	return opt == "" or host.options.get(opt, true) != false

func wid_of_npc(npc_id: String) -> String:
	for wid in ids():
		if str(row(wid).get("npc", "")) == npc_id:
			return str(wid)
	return ""

func npc_name_of(wid: String) -> String:
	var r := row(wid)
	var npc := str(r.get("npc", ""))
	var n := str(host.tables.get("npcs", {}).get(npc, {}).get("name", ""))
	if n == "":
		n = str(host.tables.get("monsters", {}).get(str(r.get("monster", "")), {}).get("name", wid))
	return n

## 現在這個時辰的排程項（找不到 = HOME）；wanderers_enabled 關閉時一律 HOME（白天定點的交談即戰不受影響）
func schedule_entry(r: Dictionary, shichen: String) -> Dictionary:
	if roam_enabled():
		for e in r.get("schedule", []):
			if e is Dictionary and shichen in e.get("hours", []):
				return e
	return { "mode": MODE_HOME }

func mode_now(r: Dictionary) -> String:
	var m := str(schedule_entry(r, str(host.clock().get("shichen_name", ""))).get("mode", MODE_HOME))
	return MODE_ROAM if m == MODE_ROAM else MODE_HOME

func _roam_regions(r: Dictionary) -> Array:
	var e := schedule_entry(r, str(host.clock().get("shichen_name", "")))
	var regs: Variant = e.get("regions", [])
	return regs if regs is Array else []

## ws.world.wanderers[wid]：{ room, mode, next_move_s, respawn_s, cd: { char_id: 世界時間 } }
func state(wid: String) -> Dictionary:
	var w: Dictionary = host.ws.world
	var all: Variant = w.get(WORLD_KEY)
	if not (all is Dictionary):
		all = {}
		w[WORLD_KEY] = all
	var st: Variant = all.get(wid)
	if not (st is Dictionary):
		st = { "room": "", "mode": "", "next_move_s": 0.0, "respawn_s": 0.0, "cd": {} }
		all[wid] = st
	if not (st.get("cd") is Dictionary):
		st["cd"] = {}
	return st

func alive(wid: String) -> bool:
	var st := state(wid)
	return float(st.get("respawn_s", 0.0)) <= 0.0 and str(st.get("room", "")) != ""

func room_of(wid: String) -> String:
	return str(state(wid).get("room", "")) if alive(wid) else ""

# ======================================================================== 安全房間（§5.2.3）

## 區域 type 是 CITY 或 SECT；有 INN 服務 NPC；房間 safe: true；WILD 地區沒有遇敵的房間，或緊鄰城門
## （出口通往 CITY／SECT 地區）的第一間房（xw_road、dlw_road、hy_foot、sy_foot…）。
## STORY_PLAN 缺漏：§5.2.3 寫「encounter 為空且是 WILD 地區的第一間」，但舉例的 xw_road、dlw_road 有遇敵；
## 依例子實作成「沒有遇敵」或「緊鄰 CITY／SECT」任一成立即安全（最不意外）。
func is_safe_room(room_id: String) -> bool:
	var room: Dictionary = host.index.room(room_id)
	if room.is_empty():
		return true
	if bool(room.get("safe", false)):
		return true
	var rtype := _region_type(host.index.region_of(room_id))
	if rtype in SAFE_REGION_TYPES:
		return true
	for npc_id in host.index.npcs_in(room_id):
		if "INN" in host.tables.get("npcs", {}).get(str(npc_id), {}).get("services", []):
			return true
	if rtype == "WILD":
		if host.index.encounter_rate(room_id) <= 0.0:
			return true
		for ex in room.get("exits", []):
			if ex is Dictionary and _region_type(host.index.region_of(str(ex.get("to", "")))) in SAFE_REGION_TYPES:
				return true
	return false

func _region_type(region_id: String) -> String:
	return str(host.tables.get("regions", {}).get(region_id, {}).get("type", ""))

## ROAM 時可以待的房間：在允許地區、不是安全房間、地區不是 CITY／SECT／DUNGEON
func roam_ok(room_id: String, regions: Array) -> bool:
	var reg: String = host.index.region_of(room_id)
	return reg != "" and reg in regions and not (_region_type(reg) in BLOCKED_REGION_TYPES) and not is_safe_room(room_id)

## 從 from_room 出發（出口不限地區）最近的可遊蕩房間；沒有回 ""
func nearest_roam_room(from_room: String, regions: Array) -> String:
	if roam_ok(from_room, regions):
		return from_room
	var seen := { from_room: true }
	var queue: Array = [from_room]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for ex in host.index.room(cur).get("exits", []):
			if not (ex is Dictionary):
				continue
			var to := str(ex.get("to", ""))
			if to == "" or seen.has(to) or not host.index.has_room(to):
				continue
			seen[to] = true
			if roam_ok(to, regions):
				return to
			queue.append(to)
	return ""

func ke_len() -> float:
	var day := float(host.day_s()) if host.has_method("day_s") else WorldClock.DEFAULT_DAY_S
	return WorldClock.shichen_len(day) / float(KE_PER_SHICHEN)

func _day_s() -> float:
	return float(host.day_s()) if host.has_method("day_s") else WorldClock.DEFAULT_DAY_S

func _move_interval(r: Dictionary) -> float:
	return maxf(1.0, float(maxi(1, int(r.get("move_every_ke", DEFAULT_MOVE_EVERY_KE)))) * ke_len())

# ======================================================================== 每 tick

func tick(_dt: float = 0.0) -> void:
	if host == null:
		return
	var now: float = host.now_s()
	for wid in ids():
		_update(str(wid), now)
	_poll_players()
	_recheck_busy()
	_resolve_prompts(now)
	_check_fights(now)
	_prune_acc += _real_span(_dt)
	if _prune_acc >= PRUNE_REAL_S:
		_prune_acc = 0.0
		prune_cooldowns(now)

## 審查修正：惡人走進來時玩家正在任務對話中（不閒置）被略過；對話結束、人還在同房 → 再判定一次（只一次）
func _recheck_busy() -> void:
	for peer in _busy_skip.keys():
		var wid := str(_busy_skip[peer])
		var s: Session = _session(int(peer))
		if s == null or s.character == null or room_of(wid) != s.room_id():
			_busy_skip.erase(peer)
			continue
		if not _idle(s) or _prompts.has(s.peer_id):
			continue
		_busy_skip.erase(peer)
		try_aggro(s, wid)

## 審查修正：每位玩家的冷卻（cd、cd_newbie）到期就刪，免得 world.json 越存越大
func prune_cooldowns(now: float) -> int:
	var n := 0
	for wid in ids():
		var st := state(str(wid))
		for key in ["cd", "cd_newbie"]:
			var d: Variant = st.get(key)
			if not (d is Dictionary):
				continue
			for cid in (d as Dictionary).keys():
				if float(d[cid]) <= now:
					(d as Dictionary).erase(cid)
					n += 1
	return n

## 排程、重生、移動
func _update(wid: String, now: float) -> void:
	var r := row(wid)
	var st := state(wid)
	if not row_active(r):
		if str(st.get("room", "")) != "":
			_vanish(wid, st)
		return
	var resp := float(st.get("respawn_s", 0.0))
	if resp > 0.0:
		if now < resp:
			return
		st["respawn_s"] = 0.0
		st["room"] = ""
		st["mode"] = ""
	var mode := mode_now(r)
	if str(st.get("mode", "")) != mode or str(st.get("room", "")) == "":
		_enter_mode(wid, r, st, mode, now)
	elif mode == MODE_ROAM and now >= float(st.get("next_move_s", 0.0)):
		_roam_step(wid, r, st, now)

func _enter_mode(wid: String, r: Dictionary, st: Dictionary, mode: String, now: float) -> void:
	var old := str(st.get("room", ""))
	var was := str(st.get("mode", ""))
	var home := str(r.get("home_room", ""))
	var target := home
	if mode == MODE_ROAM:
		var start := old if old != "" else home
		target = nearest_roam_room(start, _roam_regions(r))
		if target == "":
			target = home if host.index.has_room(home) else start
	if not host.index.has_room(target):
		target = old
	st["mode"] = mode
	st["next_move_s"] = now + _move_interval(r)
	if target == old:
		return
	st["room"] = target
	var nm := npc_name_of(wid)
	if old != "":
		_room_line(old, T_HOME if mode == MODE_HOME else T_OUT, { "npc_name": nm })
		_dirty(old)
	_dirty(target)
	if mode == MODE_ROAM and was == MODE_HOME:
		_rumor(r, "roam", { "npc_name": nm, "region_name": _region_name(host.index.region_of(target)) }, false)
	if mode == MODE_ROAM:
		_arrived(wid, target)

func _roam_step(wid: String, r: Dictionary, st: Dictionary, now: float) -> void:
	st["next_move_s"] = now + _move_interval(r)
	var cur := str(st.get("room", ""))
	var regions := _roam_regions(r)
	var opts: Array = []
	for ex in host.index.room(cur).get("exits", []):
		if ex is Dictionary and roam_ok(str(ex.get("to", "")), regions):
			opts.append(ex)
	if opts.is_empty():
		return   # 沒有合法鄰房：留在原地
	var ex: Dictionary = opts[host.rng.randi_range(0, opts.size() - 1)]
	var to := str(ex.get("to", ""))
	var nm := npc_name_of(wid)
	_room_line(cur, T_MOVE_OUT, { "npc_name": nm, "dir_label": WorldIndex.dir_label(str(ex.get("dir", ""))) })
	st["room"] = to
	_room_line(to, T_MOVE_IN, { "npc_name": nm })
	_dirty(cur)
	_dirty(to)
	_arrived(wid, to)

func _vanish(wid: String, st: Dictionary) -> void:
	var old := str(st.get("room", ""))
	st["room"] = ""
	st["mode"] = ""
	_dirty(old)
	for peer in _prompts.keys():
		if str(_prompts[peer].get("wid", "")) == wid:
			_clear(int(peer), wid, WHY_GONE)

## 惡人移入（或被放到）某房間：同房每位玩家各自判定
func _arrived(wid: String, room_id: String) -> void:
	for s in host.sessions():
		if s.character != null and s.room_id() == room_id:
			try_aggro(s, wid)

# ======================================================================== 玩家位置

## 移動鉤子（RegionSystem.move、NpcSystem.travel 之後呼叫 on_moved(s, from, to)；可缺：tick 也會輪詢）
func on_moved(s: Session, _from := "", _to := "") -> void:
	if s == null or s.character == null:
		return
	var r: String = s.room_id()
	if str(_seen_room.get(s.peer_id, "")) == r:
		return
	_seen_room[s.peer_id] = r
	_player_entered(s)

## 登入：記下位置當基準（登入當下不算走進惡人所在的房間）
func on_login(s: Session) -> void:
	if s != null and s.character != null:
		_seen_room[s.peer_id] = s.room_id()

## 換時辰（GameHost.check_clock）：立刻套用排程（HOME／ROAM 換班），不必等下一個 tick
func on_clock(_idx: int = -1) -> void:
	if host == null:
		return
	var now: float = host.now_s()
	for wid in ids():
		_update(str(wid), now)

## debug world_s_add 快轉之後：同 on_clock（倒數中的警告照真實時間走，不因快轉直接開打）
func on_time_jump(_add_s: float = 0.0) -> void:
	on_clock()

## BattleSystem._settle_player 之後（WP-ENGINE 鉤子）：戰鬥已從 active 移除，立刻結算追蹤中的惡人戰
func on_battle_settled(_s = null, _ch = null, _summary = null) -> void:
	if host != null:
		_check_fights(host.now_s())

func on_leave(s: Session) -> void:
	if s == null:
		return
	_prompts.erase(s.peer_id)
	_seen_room.erase(s.peer_id)
	_busy_skip.erase(s.peer_id)

func _poll_players() -> void:
	var live := {}
	for s in host.sessions():
		if s.character == null:
			continue
		live[s.peer_id] = true
		var r: String = s.room_id()
		if not _seen_room.has(s.peer_id):
			_seen_room[s.peer_id] = r   # 第一次看到（登入）：當基準，登入當下不算走進來
			continue
		if str(_seen_room[s.peer_id]) != r:
			_seen_room[s.peer_id] = r
			_player_entered(s)
	for peer in _seen_room.keys():
		if not live.has(peer):
			_seen_room.erase(peer)

func _player_entered(s: Session) -> void:
	_resolve_prompts(host.now_s())   # 離開了倒數中的房間 → 先算脫身
	for wid in ids():
		if room_of(str(wid)) == s.room_id():
			try_aggro(s, str(wid))

# ======================================================================== 出手

## 這位玩家此刻會不會被這個惡人盯上（不擲骰、不看冷卻）；view_for 的 hostile 也用它
func would_attack(s: Session, wid: String) -> bool:
	var r := row(wid)
	if r.is_empty() or not row_active(r) or not roam_enabled() or s == null or s.character == null:
		return false
	# 伺服器選項 encounters_enabled == false（測試／管理用，關掉路上的隨機戰鬥）：惡人也不主動出手（交談即戰照舊）
	if host.options.get("encounters_enabled", true) == false:
		return false
	var st := state(wid)
	if not alive(wid) or str(st.get("mode", "")) != MODE_ROAM or str(st.get("room", "")) != s.room_id():
		return false
	if is_safe_room(s.room_id()):
		return false
	var ch = s.character
	if int(ch.combat_xp) < protect_xp():
		return false   # S7 新手保護
	var ag: Variant = r.get("aggro", {})
	var reqs: Variant = ag.get("requires", []) if ag is Dictionary else []
	return reqs_ok(reqs if reqs is Array else [], s)

## 新手遇上夜遊的惡人：條件同 would_attack，只差在實戰未滿保護線
func would_taunt_newbie(s: Session, wid: String) -> bool:
	var r := row(wid)
	if r.is_empty() or not row_active(r) or not roam_enabled() or s == null or s.character == null:
		return false
	if host.options.get("encounters_enabled", true) == false:
		return false
	var st := state(wid)
	if not alive(wid) or str(st.get("mode", "")) != MODE_ROAM or str(st.get("room", "")) != s.room_id():
		return false
	if is_safe_room(s.room_id()) or int(s.character.combat_xp) >= protect_xp():
		return false
	var ag: Variant = r.get("aggro", {})
	var reqs: Variant = ag.get("requires", []) if ag is Dictionary else []
	return reqs_ok(reqs if reqs is Array else [], s)

## 送一段威嚇（CH_SCENE，只給本人）；回傳是否送出
func _newbie_taunt(s: Session, wid: String) -> bool:
	if not would_taunt_newbie(s, wid) or not _idle(s):
		return false
	var st := state(wid)
	var nb: Dictionary = st.get_or_add("cd_newbie", {})
	var cid := str(s.character.id)
	var now: float = host.now_s()
	if float(nb.get(cid, 0.0)) > now:
		return false
	nb[cid] = now + _day_s()
	var key := "%s_%s" % [T_NEWBIE, wid]
	if not host.tables.get("text_templates", {}).has(key):
		key = T_NEWBIE
	host.tell(s, Protocol.CH_SCENE, key, { "npc_name": npc_name_of(wid), "name": str(s.character.name),
		"room_name": _room_name(s.room_id()) })
	return true

## 判定並送出警告（§5.2.2 #2）；回傳是否送出了 villain_prompt
func try_aggro(s: Session, wid: String) -> bool:
	if s == null or s.character == null or _prompts.has(s.peer_id):
		return false
	if not would_attack(s, wid):
		if not _newbie_taunt(s, wid) and would_taunt_newbie(s, wid) and not _idle(s):
			_busy_skip[s.peer_id] = wid
		return false
	if not _idle(s):
		_busy_skip[s.peer_id] = wid   # 審查修正：對話中被略過 → 對話結束後還在同房就再判定一次（_recheck_busy）
		return false
	_busy_skip.erase(s.peer_id)
	var r := row(wid)
	var st := state(wid)
	var cid := str(s.character.id)
	var now: float = host.now_s()
	if float(st["cd"].get(cid, 0.0)) > now:
		return false
	var ag: Variant = r.get("aggro", {})
	var chance := clampi(int(ag.get("chance_pct", 100)) if ag is Dictionary else 100, 0, 100)
	if chance <= 0 or host.rng.randi_range(1, 100) > chance:
		return false
	var w := warn_s()
	_prompts[s.peer_id] = { "wid": wid, "char_id": cid, "room": s.room_id(),
		"expires_s": now + _world_span(float(w)), "called": false }
	var nm := npc_name_of(wid)
	var wk := warn_key(wid)
	host.tell(s, Protocol.CH_BATTLE, wk, { "npc_name": nm, "countdown_s": w })
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_VILLAIN_PROMPT,
		{ "wid": wid, "npc_name": nm, "countdown_s": w, "can_call": _helpers(s).size() > 0, "warn_key": wk }, true)
	if w <= 0:
		_resolve_prompts(now)
	return true

## 審查修正（敘事）：每個惡人自己的警告句 villain_warn_<wid>（像 wander_newbie_<wid>）；沒有就用通用的 villain_warn
func warn_key(wid: String) -> String:
	var k := "%s_%s" % [T_WARN, wid]
	return k if host.tables.get("text_templates", {}).has(k) else T_WARN

## 閒置：不在戰鬥、沒坐牢、沒在任務對話中
func _idle(s: Session) -> bool:
	if s.battle_id != 0:
		return false
	if s.character.has_method("is_jailed") and s.character.is_jailed():
		return false
	var dlg: Variant = s.get("dialogue")
	return not (dlg is Dictionary and not (dlg as Dictionary).is_empty())

func _resolve_prompts(now: float) -> void:
	for peer in _prompts.keys():
		if not _prompts.has(peer):
			continue
		var p: Dictionary = _prompts[peer]
		var wid := str(p["wid"])
		var s: Session = _session(int(peer))
		if s == null or s.character == null or str(s.character.id) != str(p["char_id"]):
			_prompts.erase(peer)   # 斷線、換角：倒數取消（§4.7 不存檔）
			continue
		if room_of(wid) != str(p["room"]):
			_clear(int(peer), wid, WHY_GONE)
			continue
		if s.room_id() != str(p["room"]):
			_set_cd(wid, str(p["char_id"]), now)
			_clear(int(peer), wid, WHY_ESCAPED)
			host.tell(s, Protocol.CH_BATTLE, T_ESCAPED, { "npc_name": npc_name_of(wid) })
			continue
		if s.battle_id != 0:
			_set_cd(wid, str(p["char_id"]), now)
			_clear(int(peer), wid, WHY_FOUGHT if _fighting(s.battle_id, wid) else WHY_GONE)
			continue
		if now >= float(p["expires_s"]):
			_start_chase(s, wid)

## 倒數結束或玩家迎戰：開追擊戰（不能逃）。同房已有這個惡人的追擊戰且是隊友 → 先試著加入
func _start_chase(s: Session, wid: String) -> int:
	var r := row(wid)
	var now: float = host.now_s()
	_prompts.erase(s.peer_id)
	_set_cd(wid, str(s.character.id), now)
	var bid := 0
	for b in _fights:
		var f: Dictionary = _fights[b]
		if str(f["wid"]) == wid and str(f["room"]) == s.room_id() and host.battles.has_method("join") \
				and _battle_active(int(b)):
			var res: Variant = host.battles.join(s, int(b))
			if res is Dictionary and bool(res.get("ok", false)):
				bid = int(b)
				break
	var nm := npc_name_of(wid)
	if bid == 0:
		host.tell(s, Protocol.CH_BATTLE, T_ATTACK, { "npc_name": nm })
		# 審查修正：新手隊友（實戰 < newbie_pk_protect_xp）不被拉進不能逃的追擊戰（新手保護）
		var opts := { "no_flee": bool(r.get("no_flee", true)), "pull_party": true, "pull_min_xp": protect_xp() }
		if host.battles.has_method("start_ex"):
			bid = int(host.battles.start_ex(s, [str(r.get("monster", ""))], KIND_CHASE, opts))
		else:
			bid = int(host.battles.start(s, [str(r.get("monster", ""))], KIND_CHASE))
		_track(bid, wid, s.room_id())
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_VILLAIN_CLEAR, { "wid": wid, "why": WHY_FOUGHT }, true)
	return bid

## villain_reply intent（§4.14）：FIGHT 立刻開打；CALL 通知同地區的隊友與玩家，倒數照走
func villain_reply(s: Session, wid: String, choice: String) -> Dictionary:
	var p: Variant = _prompts.get(s.peer_id)
	if not (p is Dictionary) or str(p.get("wid", "")) != wid or str(p.get("char_id", "")) != str(s.character.id):
		return GameHost.fail(Protocol.R_VILLAIN_NONE)
	if choice == CHOICE_FIGHT:
		if s.room_id() != str(p["room"]) or room_of(wid) != str(p["room"]):
			_resolve_prompts(host.now_s())
			return GameHost.fail(Protocol.R_VILLAIN_NONE)
		var bid := _start_chase(s, wid)
		return GameHost.ok({ "battle_id": bid })
	if choice == CHOICE_CALL:
		if not bool(p.get("called", false)):
			p["called"] = true
			var params := { "name": str(s.character.name), "npc_name": npc_name_of(wid),
				"room_name": _room_name(s.room_id()), "region_name": _region_name(host.index.region_of(s.room_id())) }
			for o in _helpers(s):
				host.tell(o, Protocol.CH_SYSTEM, T_CALL, params.duplicate())
			host.tell(s, Protocol.CH_SYSTEM, T_CALL_SENT, params.duplicate())
		return GameHost.ok()
	return GameHost.fail("bad_value:choice")

## 能聽到求救的人：同地區的其他在線玩家（含隊友）
func _helpers(s: Session) -> Array:
	var out: Array = []
	var reg: String = host.index.region_of(s.room_id())
	for o in host.sessions():
		if o != s and o.character != null and host.index.region_of(o.room_id()) == reg:
			out.append(o)
	return out

func _clear(peer: int, wid: String, why: String) -> void:
	_prompts.erase(peer)
	var s: Session = _session(peer)
	if s != null:
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_VILLAIN_CLEAR, { "wid": wid, "why": why }, true)

func _set_cd(wid: String, char_id: String, now: float) -> void:
	var ag: Variant = row(wid).get("aggro", {})
	var days := float(ag.get("per_player_cooldown_days", 1)) if ag is Dictionary else 1.0
	var cd: Dictionary = state(wid)["cd"]
	for cid in cd.keys():
		if float(cd[cid]) <= now:
			cd.erase(cid)   # 審查修正：順手刪掉到期的冷卻
	cd[char_id] = now + maxf(0.0, days) * _day_s()

# ======================================================================== 白天交談即戰（§5.2.2 #4）

## NpcSystem.talk 呼叫：惡人在場且 talk_fight.requires 成立 → 開打（kind FIGHT，可逃）。回傳是否開戰。
func on_talk(s: Session, npc_id: String) -> bool:
	var wid := wid_of_npc(npc_id)
	if wid == "" or s == null or s.character == null or s.battle_id != 0:
		return false
	var r := row(wid)
	if not row_active(r) or room_of(wid) != s.room_id():
		return false
	var tf: Variant = r.get("talk_fight", null)
	if not (tf is Dictionary):
		return false
	var reqs: Variant = tf.get("requires", [])
	if not reqs_ok(reqs if reqs is Array else [], s):
		return false
	var mid := str(r.get("monster", ""))
	if not host.tables.get("monsters", {}).has(mid):
		return false
	if _prompts.has(s.peer_id):
		_clear(s.peer_id, str(_prompts[s.peer_id]["wid"]), WHY_FOUGHT)
	host.tell(s, Protocol.CH_BATTLE, Protocol.E_FIGHT_START, { "npc_name": npc_name_of(wid) })
	var bid := int(host.battles.start(s, [mid], KIND_FIGHT))
	_track(bid, wid, s.room_id())
	return bid != 0

# ======================================================================== 戰鬥結束

func _track(bid: int, wid: String, room_id: String) -> void:
	if bid == 0:
		return
	var entry: Variant = host.battles.active.get(bid) if "active" in host.battles else null
	if not (entry is Dictionary):
		return
	_fights[bid] = { "wid": wid, "battle": entry.get("battle"), "chars": entry.get("chars", {}), "room": room_id }

func _battle_active(bid: int) -> bool:
	return "active" in host.battles and (host.battles.active as Dictionary).has(bid)

func _fighting(bid: int, wid: String) -> bool:
	return _fights.has(bid) and str(_fights[bid]["wid"]) == wid

## 追蹤中的戰鬥結束了：side 0 勝 → 惡人被擊敗
func _check_fights(now: float) -> void:
	for bid in _fights.keys():
		if _battle_active(int(bid)):
			continue
		var f: Dictionary = _fights[bid]
		_fights.erase(bid)
		var b: Variant = f.get("battle")
		if b == null or not (b as Object).has_method("outcome"):
			continue
		var out: Dictionary = b.outcome()
		if str(out.get("result", "")) != "VICTORY" or int(out.get("winner_side", 0)) != 0:
			continue
		var names: PackedStringArray = []
		var winners: Array = []
		var chars: Dictionary = f.get("chars", {})
		var units: Dictionary = out.get("units", {})
		for uid in units:
			var u: Dictionary = units[uid]
			if str(u.get("kind", "")) != "PLAYER" or int(u.get("side", 0)) != 0:
				continue
			var ch = chars.get(int(u.get("peer", 0)))
			if ch != null:
				names.append(str(ch.name))
				winners.append(ch)
		defeated(str(f["wid"]), names, winners, str(f["room"]), now)

## 惡人被擊敗（§5.2.2 #5）：消失 respawn_days 遊戲日、VILLAIN 傳聞、事蹟
func defeated(wid: String, names: PackedStringArray, winners: Array, room_id: String, now: float) -> void:
	var r := row(wid)
	var st := state(wid)
	var old := str(st.get("room", ""))
	st["respawn_s"] = now + maxf(0.0, float(r.get("respawn_days", 1))) * _day_s()
	st["room"] = ""
	st["mode"] = ""
	_dirty(old)
	for peer in _prompts.keys():
		if str(_prompts[peer].get("wid", "")) == wid:
			_clear(int(peer), wid, WHY_GONE)
	_rumor(r, "defeated", { "name": "、".join(names), "npc_name": npc_name_of(wid), "room_name": _room_name(room_id),
		"region_name": _region_name(host.index.region_of(room_id)) }, true)
	var rumor = host.get("rumor")
	for ch in winners:
		if rumor != null and rumor.has_method("note_villain_deed"):
			rumor.note_villain_deed(ch, wid)
		else:
			var amb := _ext(ch)
			var v: Dictionary = amb.get_or_add("defeated", {})
			v[wid] = int(v.get(wid, 0)) + 1

# ======================================================================== 視圖與 debug

## view.wanderers（§4.14）：與玩家同房的惡人 [{ wid, npc, name, hostile }]
func view_for(s: Session) -> Array:
	var out: Array = []
	if s == null or s.character == null:
		return out
	for wid in ids():
		var w := str(wid)
		if not row_active(row(w)) or room_of(w) != s.room_id():
			continue
		out.append({ "wid": w, "npc": str(row(w).get("npc", "")), "name": npc_name_of(w), "hostile": would_attack(s, w) })
	return out

## NPC 是否在這個房間（惡人不在 home_room、被擊敗、選項關閉時，靜態 NPC 列表不該再列他）
## STORY_PLAN 缺漏：§4.14 view 只依 appear 過濾 NPC；建議 QuestSystem.npc_visible／RegionSystem.view 也問這裡。
func npc_shown(npc_id: String, room_id: String) -> bool:
	var wid := wid_of_npc(npc_id)
	if wid == "":
		return true
	return row_active(row(wid)) and room_of(wid) == room_id

## debug wander_place（§4.15）："<wid>:<room>"。重生中也會立刻出現；放下後重新計移動間隔並判定同房玩家
func place(wid: String, room_id: String) -> bool:
	var r := row(wid)
	if r.is_empty() or not host.index.has_room(room_id):
		return false
	var st := state(wid)
	var old := str(st.get("room", ""))
	st["respawn_s"] = 0.0
	st["room"] = room_id
	st["mode"] = mode_now(r)
	st["next_move_s"] = host.now_s() + _move_interval(r)
	_dirty(old)
	_dirty(room_id)
	_arrived(wid, room_id)
	return true

## intents_debug 的名字（WP-ENGINE）
func debug_place(wid: String, room_id: String) -> bool:
	return place(wid, room_id)

## 測試與 debug：清掉某位玩家的冷卻
func clear_cooldown(wid: String, char_id: String) -> void:
	state(wid)["cd"].erase(char_id)

func pending_prompt(peer: int) -> Dictionary:
	var p: Variant = _prompts.get(peer)
	return (p as Dictionary).duplicate() if p is Dictionary else {}

# ======================================================================== 條件與輔助

## 條件判定：常用的角色數值條件在這裡直接算（不依賴 WP-ENGINE 的新條件型別是否已合併），其餘交給 Requirements
func reqs_ok(reqs: Array, s: Session) -> bool:
	for c in reqs:
		if not (c is Dictionary):
			continue
		var ok_local: Variant = local_cond(c, s.character, str(host.clock().get("shichen_name", "")))
		if ok_local == null:
			var ctx := { "shichen": str(host.clock().get("shichen_name", "")) }
			var sects = host.get("sects")
			if sects != null and sects.has_method("req_ctx"):
				ctx = sects.req_ctx(s)
			if Requirements.check([c], s.character, host.tables, host.options, host.rules, ctx) != "":
				return false
		elif not bool(ok_local):
			return false
	return true

## 回 true／false；不認得的型別回 null
static func local_cond(c: Dictionary, ch, shichen: String) -> Variant:
	var v := int(c.get("value", 0))
	match str(c.get("type", "")):
		"morality_min":
			return int(ch.morality) >= v
		"morality_max":
			return int(ch.morality) <= v
		"fame_min":
			return int(ch.fame) >= v
		"fame_max":
			return int(ch.fame) <= v
		"combat_xp_min":
			return int(ch.combat_xp) >= v
		"combat_xp_max":
			return int(ch.combat_xp) <= v
		"lilian_min":
			var l: Variant = ch.get("lilian")
			return int(l if l != null else 0) >= v
		"pk_min":
			return int(ch.pk_value()) >= v
		"pk_max":
			return int(ch.pk_value()) <= v
		"killing_intent_min":
			return int(ch.killing_intent) >= v
		"killing_intent_max":
			return int(ch.killing_intent) <= v
		"sect":
			return str(ch.sect) != "" and str(ch.sect) == str(c.get("sect", c.get("value", "")))
		"no_sect":
			return str(ch.sect) == ""
		"hour_in":
			var hs: Variant = c.get("hours", [])
			return not (hs is Array) or (hs as Array).is_empty() or shichen in hs
	return null

func _session(peer: int) -> Session:
	if host.has_method("session_for_peer"):
		return host.session_for_peer(peer)
	for s in host.sessions():
		if s.peer_id == peer:
			return s
	return null

func _room_line(room_id: String, key: String, p: Dictionary) -> void:
	if room_id != "":
		host.ws.queue_room_event(room_id, Protocol.CH_SCENE, key, p)

func _dirty(room_id: String) -> void:
	if room_id == "":
		return
	var regions = host.get("regions")
	if regions != null and regions.has_method("mark_room_dirty"):
		regions.mark_room_dirty(room_id)

func _rumor(r: Dictionary, which: String, params: Dictionary, force: bool) -> void:
	var rm: Variant = r.get("rumors", {})
	var key := str(rm.get(which, "")) if rm is Dictionary else ""
	var rumor = host.get("rumor")
	if key == "" or rumor == null or not rumor.has_method("post"):
		return
	var p := params.duplicate()
	if force:
		p["_force"] = true
	rumor.post("VILLAIN", key, p)

func _room_name(room_id: String) -> String:
	return str(host.index.room(room_id).get("name", room_id))

func _region_name(region_id: String) -> String:
	return str(host.tables.get("regions", {}).get(region_id, {}).get("name", region_id))

func _ext(ch) -> Dictionary:
	var e: Variant = ch.get("ext")
	if e is Dictionary:
		var a: Variant = e.get(EXT_KEY)
		if not (a is Dictionary):
			a = {}
			e[EXT_KEY] = a
		return a
	return {}

func _world_span(real_s: float) -> float:
	if host.has_method("world_span"):
		return float(host.world_span(real_s))
	return real_s

func _real_span(world_s: float) -> float:
	if host.has_method("real_span"):
		return float(host.real_span(world_s))
	return world_s
