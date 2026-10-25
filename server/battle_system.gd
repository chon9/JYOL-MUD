class_name BattleSystem
extends RefCounted
## 戰鬥主機端（M1_PLAN 3.5.2；M2_PLAN 4.6.2）：開戰（含拉入同房隊友）、PvP、中途加入、重連接回、
## 每 tick 推進、轉送戰鬥事件、結算（獎勵、死亡、屍體、重生；每位玩家的結果依自己那一方）。
## Battle 本身只吃戰鬥者規格字典（3.3）；這裡負責把 Character 轉成規格、把結果寫回 Character。
## M2 新系統（host.party、host.pk）可能為 null（H4）：一律用 host.get() 取，判斷後才呼叫。

## 守衛戰不拉隊友（M2 審查）：原作只證實隊友「可以」中途加入；守衛是為了某人的 PK／善惡而來，
## 無辜的隊友不該被拖去打 qi 3000 的官兵、替別人承擔死亡懲罰。要幫忙就用 battle_join 自願加入。
const PULL_KINDS := ["ENCOUNTER", "FIGHT"]
## M3B_PLAN §5.1.5：SEIZE（捉拿公敵）也是 PvP：沒有實戰／學點、不能中途加入、對方欄位遮蔽；結算交 PkSystem（不加懲罰）
## M3D_PLAN §9.2（WP-EVENTS）：ROB（劫鏢）、DUEL（比武的切磋模式）
const PVP_KINDS := ["CHALLENGE", "FORCED", "SEIZE", "ROB", "DUEL"]
## M3B_PLAN §5.1.8：生活技能打獵（LifeSystem.on_hunt_settled）、小黃追咬（一般獎勵）
const KIND_HUNT := "HUNT"
const KIND_HARASS := "HARASS"
const KIND_SEIZE := "SEIZE"
const KIND_ROB := "ROB"        # M3d WP-EVENTS：劫鏢（side 0＝劫鏢方、side 1＝押鏢者＋鏢單位）
const KIND_DUEL := "DUEL"      # M3d WP-EVENTS：比武（切磋模式；沒有死亡懲罰）
const KIND_ROGUE := "ROGUE"    # ROGUE WP-RUN：江湖試煉（不能逃、玩家全倒即判負、沒有獎勵與死亡懲罰）
const DUEL_LIMIT_DEFAULT_S := 600.0
const DEFAULT_MAX_HUMANS := 8

var host: GameHost
## bid -> { battle, kind, room, peers: [peer], chars: { peer: Character }, char_ids: { peer: char_id },
##          identities: { char_id: identity }, silent_peers: [peer] }
var active: Dictionary = {}
var _next_id := 1

func _init(p_host: GameHost) -> void:
	host = p_host

func battle_opts(region_id: String, kind: String = "") -> Dictionary:
	var o: Dictionary = host.options
	return {
		"wait_mode": bool(o.get("wait_mode", true)),
		"wait_mode_timeout_s": float(o.get("wait_mode_timeout_s", 20)),
		"wait_mode_timeout_min_s": float(o.get("wait_mode_timeout_min_s", 8)),
		"wait_mode_round_budget_s": float(o.get("wait_mode_round_budget_s", 45)),
		"escape_tiles": host.index.escape_tiles_hint(region_id),
		"kind": kind,
		# M3A_PLAN 5.1：內、穴兩個指令是否開放（規則 later_battle_cmds；缺省 true）
		"later_battle_cmds": bool(host.rules.get("later_battle_cmds", true)),
		"dodge_cmd": bool(host.rules.get("dodge_cmd", true)),   # M3d WP-COMBAT
	}

func max_humans() -> int:
	return maxi(1, int(host.options.get("battle_max_humans", DEFAULT_MAX_HUMANS)))

static func is_pvp_kind(kind: String) -> bool:
	return kind in PVP_KINDS

## kind："ENCOUNTER" / "FIGHT" / "GUARD"；故事包加 "QUEST"（任務動作 fight）、"CHASE"（遊蕩惡人追擊；不能逃）。回傳 bid。
## kind ∈ PULL_KINDS（遇敵、定點戰；守衛戰不拉）：同房、閒置、有角色的隊友一起入場（side 0，各自收 s2c_battle_open），
## 總玩家數不超過 battle_max_humans。
func start(s: Session, monster_ids: Array, kind: String) -> int:
	return start_ex(s, monster_ids, kind, {})

## M3A_PLAN 5.9：新開戰 API。opts = { "waves": [[ids…], [ids…]], "no_flee": bool, "party_only": bool, "pull_party": bool }
## - waves：第一波用 monster_ids（空的話用 waves[0]）；waves[0] 與 monster_ids 相同時不重複出場。
##   之後每清光一波就從右側放入下一波（battle_wave），最後一波清光才勝利。
## - no_flee：FLEE 回 no_flee（追擊戰、試煉）。
## - pull_party：同房閒置隊友一起入場（沒給時依 kind ∈ PULL_KINDS）。
## - pull_min_xp：只拉實戰 ≥ 這個數的隊友（追擊戰帶 newbie_pk_protect_xp；審查修正）。
## - party_only：開戰時已經在場的隊伍就是全部參戰者，**不能中途加入**（十八銅人限 3 人；M3a 審查修正：
##   原本只在開陣時檢查人數，第 4、5 位隊友可以中途走進來助陣）。_join_check 回 join_not_allowed。
## 新 kind：TRIAL（十八銅人）、SECT_GUARD（敵對入山）；battle_opts 不看 pk_allowed，這兩種照常開打。
func start_ex(s: Session, monster_ids: Array, kind: String, opts: Dictionary) -> int:
	var bid := _next_id
	_next_id += 1
	var room := s.room_id()
	var bo := battle_opts(host.index.region_of(room), kind)
	if bool(opts.get("no_flee", false)):
		bo["no_flee"] = true
	if kind == KIND_ROGUE:   # ROGUE WP-RUN
		bo["no_flee"] = true   # ROGUE WP-RUN
		bo["end_on_players_down"] = true   # ROGUE WP-RUN
		bo["kind"] = KIND_ROGUE   # ROGUE WP-RUN
	var b := Battle.new(bid, int(opts["seed"]) if opts.has("seed") else host.rng.randi(), bo)   # ROGUE WP-RUN：opts.seed（試煉的可重現戰鬥）
	var entry := _new_entry(b, kind, room)
	entry["opts"] = opts.duplicate(true)
	_add_player(entry, s, 0)
	if bool(opts.get("pull_party", kind in PULL_KINDS)):
		var min_xp := int(opts.get("pull_min_xp", 0))
		for o in _pull_candidates(s):
			if b.humans() >= max_humans():
				break
			# 審查修正：pull_min_xp（追擊戰 = newbie_pk_protect_xp）→ 實戰不到的新手隊友不被拉進不能逃的戰鬥（新手保護 S7）
			if int(o.character.combat_xp) < min_xp:
				continue
			_add_player(entry, o, 0)
	_rogue_ally_units(entry, b, opts)   # ROGUE WP-ALLY
	var waves: Array = []
	for w in opts.get("waves", []):
		if w is Array and not w.is_empty():
			waves.append(w)
	var first: Array = monster_ids
	if first.is_empty() and not waves.is_empty():
		first = waves[0]
	if not waves.is_empty() and str(waves[0]) == str(first):
		waves = waves.slice(1)
	var npc_id := str(opts.get("npc", "")) if bool(opts.get("npc_unit", false)) else ""
	for spec in Encounter.monster_specs(first, host.tables):   # 同名多隻 → 野兔甲、野兔乙
		spec["side"] = 1
		spec["peer"] = 0
		if opts.has("hunter_xp"):   # M3d 審查：賞金獵人依被追的人的實戰決定數值（BountyRules.apply_hunter_xp）
			BountyRules.apply_hunter_xp(spec, int(opts["hunter_xp"]), host.tables)
		if npc_id != "":
			_npc_unit_spec(spec, npc_id)   # M3C_PLAN §5.7：攻擊 NPC 的主單位（只有第一個）
			npc_id = ""
		b.add_unit(spec)
	for spec in opts.get("foe_specs", []):   # ROGUE WP-RUN：試煉的對手（RogueFoes 產生的完整規格）
		var fs: Dictionary = (spec as Dictionary).duplicate(true)   # ROGUE WP-RUN
		fs["side"] = 1   # ROGUE WP-RUN
		fs["peer"] = 0   # ROGUE WP-RUN
		b.add_unit(fs)   # ROGUE WP-RUN
	var later: Array = []
	for w in waves:
		var specs: Array = []
		for spec in Encounter.monster_specs(w, host.tables):
			spec["side"] = 1
			spec["peer"] = 0
			specs.append(spec)
		later.append(specs)
	if not later.is_empty():
		b.set_waves(later)
	return _begin(entry)

## M3C_PLAN §5.7：攻擊 NPC 戰的主單位 spec：ref = npc_id（快照 ref 給圖，用 NPC 立繪）、name = NPC 名、
## monster_row = attack.monster（數值與獎勵；Encounter.monster_spec 已帶）、npc = npc_id（NpcAttackSystem 找主單位）
func _npc_unit_spec(spec: Dictionary, npc_id: String) -> void:
	var row := host.npc_row(npc_id)
	if not spec.has("monster_row") or str(spec.get("monster_row", "")) == "":
		spec["monster_row"] = str(spec.get("ref", ""))
	spec["ref"] = npc_id
	spec["npc"] = npc_id
	var nm := str(row.get("name", npc_id))
	spec["name"] = nm
	spec["short"] = str(row.get("short", nm.substr(0, 2) if nm.length() > 2 else nm))

## PvP（M2_PLAN 4.6.2）：kind ∈ ["CHALLENGE", "FORCED"]；atk 在 side 0、def 在 side 1；只有兩人，不拉隊友。
## 規則驗證（同房、pk_mode、地區…）由呼叫端（PkSystem）負責；這裡只擋不可能開打的狀況（回 0）。
## M3B_PLAN §5.1.5：opts = { "pull_party": bool（出手方同房閒置隊友一起入場，side 0）, "seize_sect": String（捉拿的門派） }；
## 目標一方不拉隊友【設計提案】。CHALLENGE／FORCED 照舊只有兩人（opts 空）。
func start_pvp(atk: Session, def: Session, kind: String, opts: Dictionary = {}) -> int:
	if atk == null or def == null or atk.character == null or def.character == null or atk == def:
		return 0
	if atk.battle_id != 0 or def.battle_id != 0:
		return 0
	if not is_pvp_kind(kind):
		push_warning("BattleSystem.start_pvp: unknown kind %s" % kind)
		return 0
	var bid := _next_id
	_next_id += 1
	var room := atk.room_id()
	var bo := battle_opts(host.index.region_of(room), kind)
	if kind == KIND_DUEL:
		bo["duel_limit_s"] = float(opts.get("duel_limit_s", DUEL_LIMIT_DEFAULT_S))   # M3d WP-EVENTS：Battle 判定用戰鬥時間
	var b := Battle.new(bid, host.rng.randi(), bo)
	var entry := _new_entry(b, kind, room)
	entry["opts"] = opts.duplicate(true)
	_add_player(entry, atk, 0)
	_add_player(entry, def, 1)
	if bool(opts.get("pull_party", false)):
		# M3d 審查：劫鏢（ROB）帶 pull_min_xp（新手保護與劫鏢實戰門檻）與 pull_skip_chars（持照者），同 start_ex 的 S7 修正
		var min_xp := int(opts.get("pull_min_xp", 0))
		var skip: Array = opts.get("pull_skip_chars", []) if opts.get("pull_skip_chars", []) is Array else []
		for o in _pull_candidates(atk):
			if b.humans() >= max_humans():
				break
			if o == def:
				continue
			if int(o.character.combat_xp) < min_xp or skip.has(str(o.character.id)):
				continue
			_add_player(entry, o, 0)
	_m3d_events_pre_begin(entry)   # M3d WP-EVENTS：劫鏢的鏢單位
	return _begin(entry)

func _new_entry(b: Battle, kind: String, room: String) -> Dictionary:
	return { "battle": b, "kind": kind, "room": room, "peers": [], "chars": {}, "char_ids": {},
		"identities": {}, "silent_peers": [] }

## 開戰前把一位玩家放進 entry（Battle 仍在 SETUP）
func _add_player(entry: Dictionary, s: Session, side: int) -> void:
	var b: Battle = entry["battle"]
	var ch = s.character
	var spec: Dictionary = ch.to_combatant(host.tables, host.options, side, s.peer_id)
	spec["equip_cd_ms"] = IntentsItem.equip_cooldown_ms(host)   # M3d 審查：換裝兩秒只在 1.0B 世界
	if str(entry.get("kind", "")) == KIND_DUEL:
		_m3d_duel_spec(entry, spec)   # M3d WP-EVENTS：切磋模式不觸發門技、拿掉召喚類道具
	b.add_unit(spec)
	_register_player(entry, s, ch)
	s.battle_id = b.id

func _register_player(entry: Dictionary, s: Session, ch) -> void:
	if host.scout != null:
		host.scout.invalidate(s, ScoutSystem.WHY_BATTLE)   # 進戰鬥：查看偵察的提示失效
	if host.quests != null:
		host.quests.drop_dialogue(s)   # STORY_PLAN §4.5：開戰時清掉對話游標
	if not (entry["peers"] as Array).has(s.peer_id):
		(entry["peers"] as Array).append(s.peer_id)
	entry["chars"][s.peer_id] = ch
	entry["char_ids"][s.peer_id] = str(ch.id)
	entry["identities"][str(ch.id)] = s.identity

func _begin(entry: Dictionary) -> int:
	var b: Battle = entry["battle"]
	active[b.id] = entry
	var evs: Array = b.start(host.tables)
	for peer in entry["peers"]:
		var ps: Session = host.session_for_peer(int(peer))
		if ps != null:
			_open_for(entry, ps)
			_battle_changed(ps)
	_forward(entry, evs)
	host.regions.mark_room_dirty(str(entry["room"]))
	if b.is_over():
		_finish(entry)
	return b.id

## 同房、閒置（battle_id == 0）、有角色的隊友（依加入順序）
func _pull_candidates(s: Session) -> Array:
	var party = host.get("party")
	if party == null:
		return []
	var out: Array = []
	for o in party.members_in_room(s):
		if o != null and o != s and o.character != null and o.battle_id == 0 and o.room_id() == s.room_id():
			out.append(o)
	return out

## 送給某位玩家的戰鬥開場快照：my_uid、kind、my_side；PvP 時對方玩家單位只帶最少欄位＋look（4.5.3）
func _state_for(entry: Dictionary, peer: int) -> Dictionary:
	var b: Battle = entry["battle"]
	var state: Dictionary = b.snapshot(host.tables)
	var my_uid := b.uid_for_peer(peer)
	var my_side := 0
	var me: BattleUnit = b.unit(my_uid)
	if me != null:
		my_side = me.side
	state["my_uid"] = my_uid
	state["kind"] = str(entry.get("kind", ""))
	state["my_side"] = my_side
	var list: Array = []
	for d in state.get("units", []):
		list.append(redact_unit(d, my_side))
	state["units"] = list
	_m3d_events_state(entry, state, my_side)   # M3d WP-EVENTS：劫鏢方不能逃、比武倒數
	return state

## 敵方的玩家單位：只留與怪物相同的公開欄位＋look
static func redact_unit(d: Dictionary, my_side: int) -> Dictionary:
	if str(d.get("kind", "")) != "PLAYER" or int(d.get("side", 0)) == my_side:
		return d
	var out := {}
	for k in ["uid", "name", "short", "side", "kind", "peer", "pos", "qi", "qi_max", "gauge", "rate", "state", "look", "statuses",
			"wtype", "wfx"]:   # M3C_PLAN §7.2（武器特效的純表現欄位）
		if d.has(k):
			out[k] = d[k]
	return out

func _open_for(entry: Dictionary, s: Session) -> void:
	ClientState.deliver_battle_open(s.peer_id, _state_for(entry, s.peer_id))

## 某人進出戰鬥：sheet（in_battle）、view（players[].in_battle、battles）、隊伍面板
func _battle_changed(s: Session) -> void:
	if s == null:
		return
	s.sheet_dirty = true
	s.view_dirty = true
	var party = host.get("party")
	if party != null and s.character != null:
		party.on_battle_changed(s)

func tick(dt: float) -> void:
	for bid in active.keys():
		if not active.has(bid):
			continue
		var entry: Dictionary = active[bid]
		var b: Battle = entry["battle"]
		var evs: Array = b.step(dt, host.tables)
		_forward(entry, evs)
		if not b.is_over():
			_m3d_events_tick(entry)   # M3d WP-EVENTS：比武限時與棄權、鏢單位倒下
		if b.is_over():
			_finish(entry)

func _forward(entry: Dictionary, evs: Array) -> void:
	var pvp := is_pvp_kind(str(entry.get("kind", "")))
	var b: Battle = entry["battle"]
	for e in evs:
		if not (e is Dictionary):
			continue
		for peer in entry["peers"]:
			host.ws.forward_event(int(peer), redact_event_for(b, e, int(peer)) if pvp else e)
	if str(entry.get("kind", "")) == KIND_DUEL:
		_m3d_duel_spectate(entry, evs)   # M3d WP-EVENTS：擂臺與休息區的人收到每一擊的文字

## PvP 時不給對方看的單位欄位（4.5.3：敵方玩家只有與怪物相同的公開欄位）。開場快照由 redact_unit 處理；
## 戰鬥中的事件（例：battle_rest 帶 neili、neili_gain）在這裡逐一收件人剔除（M2 第三輪審查）
const PVP_PRIVATE_EVENT_KEYS := ["neili", "neili_gain", "neili_max", "jing", "jing_max", "shen", "shen_gain", "shen_max"]

## 事件的主角（p.uid）是收件人敵方的玩家單位 → 回傳去掉私密欄位的複本；否則原樣回傳
static func redact_event_for(b: Battle, e: Dictionary, peer: int) -> Dictionary:
	var p: Variant = e.get("p")
	if not (p is Dictionary):
		return e
	var has_private := false
	for k in PVP_PRIVATE_EVENT_KEYS:
		if (p as Dictionary).has(k):
			has_private = true
			break
	if not has_private:
		return e
	var u: BattleUnit = b.unit(int(p.get("uid", 0)))
	if u == null or not u.is_player():
		return e
	var me: BattleUnit = b.unit(b.uid_for_peer(peer))
	if me != null and me.side == u.side:
		return e
	var p2: Dictionary = (p as Dictionary).duplicate()
	for k in PVP_PRIVATE_EVENT_KEYS:
		p2.erase(k)
	var e2 := e.duplicate()
	e2["p"] = p2
	return e2

## battle_cmd：battle_not_found → Battle.submit 的原因碼
func submit(s: Session, args: Dictionary) -> Dictionary:
	var bid := int(args.get("battle_id", 0))
	if s.battle_id == 0 or bid != s.battle_id or not active.has(bid):
		return GameHost.fail("battle_not_found")
	var b: Battle = active[bid]["battle"]
	if b.is_over():
		return GameHost.fail("battle_over")
	var no_flee := _m3d_rob_no_flee(active[bid], s, args)   # M3d WP-EVENTS：劫鏢方不能逃（烙跑鞋也不行）
	if no_flee != "":
		return GameHost.fail(no_flee)
	var cmd := { "cmd": str(args.get("cmd", "")) }
	for k in ["target", "art", "move", "power_tenths", "item_uid", "mode"]:
		if args.has(k):
			cmd[k] = args[k]
	var reason: String = b.submit(s.peer_id, cmd, host.tables)
	if reason == "not_enough_jing":
		reason = "battle_not_enough_jing"   # 戰鬥中精不足：另一句提示（err_battle_not_enough_jing），不叫人去客棧
	if reason != "":
		return GameHost.fail(reason)
	return GameHost.ok()

# ---------- M2：中途加入、房間戰鬥清單、重連接回 ----------

## battle_join（4.2）：battle_not_found（不存在或不在同房）→ battle_over → join_not_allowed（沒有仍在場的同隊隊友）
## → battle_full（玩家數 ≥ battle_max_humans 或隊友那一方沒有空格）→ Battle.join_unit 加到隊友那一方
func join(s: Session, bid: int) -> Dictionary:
	var chk := _join_check(s, bid)
	if str(chk["reason"]) != "":
		return GameHost.fail(str(chk["reason"]))
	var entry: Dictionary = active[bid]
	var b: Battle = entry["battle"]
	var side := int(chk["side"])
	var ch = s.character
	var jspec: Dictionary = ch.to_combatant(host.tables, host.options, side, s.peer_id)
	jspec["equip_cd_ms"] = IntentsItem.equip_cooldown_ms(host)   # M3d 審查：換裝兩秒只在 1.0B 世界
	var uid := b.join_unit(jspec, host.tables)
	if uid == 0:
		return GameHost.fail("battle_full")
	_register_player(entry, s, ch)
	(entry["silent_peers"] as Array).erase(s.peer_id)
	s.battle_id = bid
	# M3c 審查：加入攻擊 NPC 的人照樣承擔動手就算的門派後果（違反門規、叛派、公敵）
	if str(entry.get("kind", "")) == "NPC_ATTACK":
		host.m2_call(host.get("npcpk"), "on_join", [s, entry])
	_open_for(entry, s)
	_forward(entry, b.drain_events())   # battle_join、battle_unit_join、battle_gauges：全場（含新加入者）
	_battle_changed(s)
	host.regions.mark_room_dirty(str(entry["room"]))
	return GameHost.ok({ "battle_id": bid })

## 回傳 { reason, side }；reason == "" 表示可以加入（side＝隊友那一方）
func _join_check(s: Session, bid: int) -> Dictionary:
	var r := { "reason": "", "side": 0 }
	if s == null or s.character == null:
		r["reason"] = "no_character"
		return r
	if not active.has(bid) or str(active[bid]["room"]) != s.room_id():
		r["reason"] = "battle_not_found"
		return r
	var entry: Dictionary = active[bid]
	var b: Battle = entry["battle"]
	if b.is_over():
		r["reason"] = "battle_over"
		return r
	if s.battle_id != 0:
		r["reason"] = "in_battle"
		return r
	var side := _teammate_side(entry, s)
	if side < 0:
		r["reason"] = "join_not_allowed"
		return r
	if b.humans() >= max_humans() or b.join_cell(side) == Vector2i(-1, -1):
		r["reason"] = "battle_full"
		return r
	# M3c 審查：攻擊 NPC 的戰鬥，加入的人也要過動手的資格檢查（門派 requires、坐牢、剛打退…）；NpcAttackSystem 為 null 時略過
	if str(entry.get("kind", "")) == "NPC_ATTACK":
		var why := str(host.m2_call(host.get("npcpk"), "join_reason", [s, entry], ""))
		if why != "":
			r["reason"] = why
			return r
	r["side"] = side
	return r

## 戰鬥中仍在場（未倒下、未逃走）的同隊隊友所在的一方；沒有回 -1。
## M2_PLAN 缺漏：PvP（叫戰／強制 PK）一律不能中途加入（start_pvp「只有兩人」），回 -1 → join_not_allowed。
## 試煉（TRIAL）與 opts.party_only 的戰鬥同樣不能中途加入（人數限制在開陣時就定了）。
func _teammate_side(entry: Dictionary, s: Session) -> int:
	if is_pvp_kind(str(entry.get("kind", ""))):
		return -1
	if str(entry.get("kind", "")) == "TRIAL" or bool(entry.get("opts", {}).get("party_only", false)):
		return -1
	var party = host.get("party")
	if party == null:
		return -1
	var me := str(s.character.id)
	var b: Battle = entry["battle"]
	for u in b.units:
		if not u.is_player() or not u.is_active():
			continue
		var cid := str(u.spec.get("ref", ""))
		if cid != me and party.same_party(me, cid):
			return u.side
	return -1

## 4.5.2 view.battles：[ { bid, kind, names: [[side0 名字…], [side1 名字…]], joinable } ]（依 bid；只列仍在場的單位）
func room_battles(room_id: String, viewer: Session) -> Array:
	var out: Array = []
	var bids := active.keys()
	bids.sort()
	for bid in bids:
		var entry: Dictionary = active[bid]
		if str(entry["room"]) != room_id:
			continue
		var b: Battle = entry["battle"]
		if b.is_over():
			continue
		var names: Array = [[], []]
		for u in b.units:
			if u.is_active():
				(names[1 if u.side == 1 else 0] as Array).append(u.unit_name())
		out.append({ "bid": int(bid), "kind": str(entry.get("kind", "")), "names": names,
			"joinable": viewer != null and str(_join_check(viewer, int(bid))["reason"]) == "" })
	return out

## 進行中且包含此角色（含已斷線者）的 bid，否則 0
func battle_of_char(char_id: String) -> int:
	for bid in active:
		var entry: Dictionary = active[bid]
		if (entry["battle"] as Battle).is_over():
			continue
		if (entry["char_ids"] as Dictionary).values().has(char_id):
			return int(bid)
	return 0

func humans(bid: int) -> int:
	if not active.has(bid):
		return 0
	return (active[bid]["battle"] as Battle).humans()

## 重連接回（D4）：換 peer、取消 detached/afk、s.character = 戰鬥中的同一個 Character 物件（不從磁碟讀）、
## 送 s2c_battle_open（進入世界由呼叫端 enter_character 接著做）。角色不屬於這個 identity、找不到單位 → false。
func reattach(s: Session, char_id: String) -> bool:
	var bid := battle_of_char(char_id)
	if bid == 0 or s == null:
		return false
	var entry: Dictionary = active[bid]
	if str(entry["identities"].get(char_id, "")) != s.identity:
		return false
	var old_peer := -1
	for p in entry["char_ids"]:
		if str(entry["char_ids"][p]) == char_id:
			old_peer = int(p)
	var ch = entry["chars"].get(old_peer)
	var b: Battle = entry["battle"]
	var u: BattleUnit = null
	for x in b.units:
		if x.is_player() and str(x.spec.get("ref", "")) == char_id:
			u = x
	if ch == null or u == null:
		return false
	if old_peer != s.peer_id:
		var old_s: Session = host.session_for_peer(old_peer)
		if old_s != null and old_s.character == ch and old_s.battle_id == bid:
			old_s.battle_id = 0   # 舊 session 還掛著同一角色（正常流程中 WorldServer 已先移除它）
		(entry["chars"] as Dictionary).erase(old_peer)
		(entry["char_ids"] as Dictionary).erase(old_peer)
		(entry["peers"] as Array).erase(old_peer)
		(entry["silent_peers"] as Array).erase(old_peer)
	(entry["silent_peers"] as Array).erase(s.peer_id)
	_register_player(entry, s, ch)
	u.peer = s.peer_id
	u.spec["peer"] = s.peer_id
	u.detached = false
	u.afk = false
	u.timeouts = 0
	# 進房事件、視圖、未讀信提醒由呼叫端（intents_char.char_select）接著做 enter_character（4.6.1）
	s.character = ch
	s.pending_roll = {}
	s.battle_id = bid
	_open_for(entry, s)
	_battle_changed(s)
	return true

## 玩家斷線：不中止戰鬥（否則快輸的人拔線就能逃過死亡懲罰）。
## 他的單位改為自動「防」，不再推送任何東西給他；戰鬥中已沒有在線玩家時，當場快轉到分出勝負並結算
## （死亡 → handle_death(s = null)：照樣降級、掉屍體、回記錄點並存檔）。ABORTED 只留給主機關閉與 MAX_TICKS。
## 同一角色在戰鬥結束前重新選角 → reattach() 接回（D4）。
func detach_for(s: Session) -> void:
	var bid := s.battle_id
	s.battle_id = 0
	if not active.has(bid):
		return
	var entry: Dictionary = active[bid]
	var silent: Array = entry.get("silent_peers", [])
	if not silent.has(s.peer_id):
		silent.append(s.peer_id)
	entry["silent_peers"] = silent
	(entry["peers"] as Array).erase(s.peer_id)
	var b: Battle = entry["battle"]
	if not b.is_over():
		b.detach_peer(s.peer_id)
	if not b.is_over() and str(entry.get("kind", "")) == KIND_DUEL:
		_m3d_duel_forfeit(entry)   # M3d WP-EVENTS：比武中斷線＝棄權
	if not (entry["peers"] as Array).is_empty() and not b.is_over():
		return   # 還有其他在線玩家：照常由 tick 推進
	while not b.is_over():
		_forward(entry, b.step(Battle.TICK * 100.0, host.tables))
	_finish(entry)

func abort_all() -> void:
	for bid in active.keys():
		if not active.has(bid):
			continue
		var entry: Dictionary = active[bid]
		var b: Battle = entry["battle"]
		if not b.is_over():
			_forward(entry, b.abort())
		_finish(entry)

# ---------- 結算 ----------
func _finish(entry: Dictionary) -> void:
	var b: Battle = entry["battle"]
	if not active.has(b.id):
		return
	active.erase(b.id)
	var out: Dictionary = b.outcome()
	var kind := str(entry.get("kind", ""))
	if kind == KIND_DUEL:
		_m3d_duel_outcome(out)   # M3d WP-EVENTS：一方逃走（棄權）時另一方算勝（不是「全部逃走」）
	var result := str(out.get("result", "ABORTED"))
	var pvp := is_pvp_kind(kind)
	var rewards: Dictionary = {}
	if kind == KIND_ROGUE:
		host.m2_call(host.get("rogue"), "on_battle_finished", [entry, out])   # ROGUE WP-RUN
	if result == "VICTORY" and not pvp and kind != KIND_ROGUE:   # ROGUE WP-RUN：試煉沒有獎勵
		# M3C_PLAN §6.6、§11.3 Day-0：一場戰鬥一個 ctx（規則、已有持有者的神兵、參戰角色的強制掉落）；LootSystem 為 null 時 {}
		var ctx: Variant = host.m2_call(host.get("loot"), "reward_ctx", [entry], {})
		rewards = compute_rewards(b, host.tables, host.rng, ctx if ctx is Dictionary else {})
	var units: Dictionary = out.get("units", {})
	var uids := units.keys()
	uids.sort()
	var summary_units: Array = []
	for uid in uids:
		var u: Dictionary = units[uid]
		if str(u.get("kind", "")) != "PLAYER":
			continue
		var peer := int(u.get("peer", 0))
		var ch = entry["chars"].get(peer)
		if ch == null:
			continue
		var r: Variant = rewards.get(uid, rewards.get(int(uid), null))
		var s: Session = host.session_for_peer(peer)
		if s != null and (peer in entry.get("silent_peers", []) or s.character != ch):
			if s.battle_id == b.id:
				s.battle_id = 0
			s = null
		u["party_kills"] = _party_kills(units, uid)   # STORY_PLAN §4.11：同一方其他玩家打倒的怪物（隊伍計分）
		_settle_player(entry, s, ch, u, r, relative_result(out, int(u.get("side", 0))))
		if pvp:
			summary_units.append({
				"char_id": str(ch.id), "name": str(ch.name), "peer": s.peer_id if s != null else 0,
				"side": int(u.get("side", 0)), "died": bool(u.get("died", false)), "fled": bool(u.get("fled", false)),
				"killed_by_char": _killer_char(b, int(u.get("killed_by", 0))),
			})
	host.regions.mark_room_dirty(str(entry.get("room", "")))
	# M3d WP-EVENTS：劫鏢的分贓與押鏢失敗、比武的晉級（DUEL 不交給 PkSystem：比武不轉移神兵、不加 PK值與殺氣、不廣播）
	_m3d_events_finish(entry, out)
	if kind == KIND_DUEL:
		host.m2_call(host.get("npcpk"), "on_battle_finished", [entry, out])
		return
	if pvp and result != "ABORTED":
		var pk = host.get("pk")
		if pk != null:
			pk.on_pvp_end({ "bid": b.id, "kind": kind, "room": str(entry.get("room", "")), "units": summary_units,
				"seize_sect": str(entry.get("opts", {}).get("seize_sect", "")) })
	# M3C_PLAN §5.3：攻擊 NPC 的戰鬥（解鎖、消失、善惡門派後果、守衛）；NpcAttackSystem 為 null 時略過
	host.m2_call(host.get("npcpk"), "on_battle_finished", [entry, out])

## M3c2 整合（M3C2_PLAN §2.3.3）：交給 SectSystem.spar_adjust 在 apply_rewards 之前改寫切磋弟子給的實戰與學點；
## 傳這場打倒的全部怪物 ref 與 BattleRewards 的分成（1/√存活玩家數），結果框顯示的就是真的發出去的量
func _spar_adjust(entry: Dictionary, s: Session, ch, r: Dictionary) -> void:
	var sects = host.get("sects")
	if sects == null or not (sects as Object).has_method("spar_adjust"):
		return
	var b: Battle = entry["battle"]
	var dead: Array = []
	var alive := 0
	for u in b.units:
		if u.side == 1 and not u.is_player() and u.is_dead():
			dead.append(str(u.spec.get("monster_row", u.spec.get("ref", ""))))
		elif u.side == 0 and u.is_player() and u.is_active():
			alive += 1
	sects.spar_adjust(s, ch, r, str(entry.get("kind", "")), dead, 1.0 / sqrt(float(maxi(1, alive))))

## M3C_PLAN §6.6：BattleRewards.compute 的第 4 個參數 ctx 由 WP-LOOT 加上；還沒有時照舊 3 個參數（容錯，平行開發）
static func compute_rewards(b: Battle, tables: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary) -> Dictionary:
	var sc: Script = BattleRewards
	var n_args := 3
	for m in sc.get_script_method_list():
		if str(m.get("name", "")) == "compute":
			n_args = (m.get("args", []) as Array).size()
			break
	if n_args >= 4:
		return sc.call("compute", b, tables, rng, ctx)
	return sc.call("compute", b, tables, rng)

## 同一方「其他」玩家單位的 kills（怪物 id）串起來
static func _party_kills(units: Dictionary, me_uid: Variant) -> Array:
	var me: Dictionary = units[me_uid]
	var out: Array = []
	var uids := units.keys()
	uids.sort()
	for k in uids:
		if k == me_uid:
			continue
		var o: Dictionary = units[k]
		if str(o.get("kind", "")) != "PLAYER" or int(o.get("side", 0)) != int(me.get("side", 0)):
			continue
		for m in o.get("kills", []):
			out.append(str(m))
	return out

## 相對於某一方的結果（4.5.3：我方勝 = VICTORY）。Battle.outcome() 的 result 以 side 0 為準，winner_side 換算。
## 回傳 VICTORY／DEFEAT／ALL_FLED／ABORTED（_settle_player 再依 died／fled 細分）
static func relative_result(out: Dictionary, side: int) -> String:
	var result := str(out.get("result", "ABORTED"))
	if result == "ABORTED" or result == "NONE":
		return "ABORTED"
	var fallback := -1
	if result == "VICTORY":
		fallback = 0
	elif result == "DEFEAT":
		fallback = 1
	var w := int(out.get("winner_side", fallback))
	if w == -1:
		return "ALL_FLED"
	return "VICTORY" if w == side else "DEFEAT"

## 擊殺者單位 uid → 擊殺者 char_id（玩家才有；怪物或沒有擊殺者回 ""）
static func _killer_char(b: Battle, killer_uid: int) -> String:
	if killer_uid <= 0:
		return ""
	var k: BattleUnit = b.unit(killer_uid)
	if k == null or not k.is_player():
		return ""
	return str(k.spec.get("ref", ""))

func _settle_player(entry: Dictionary, s: Session, ch, u: Dictionary, r: Variant, result: String) -> void:
	var b: Battle = entry["battle"]
	var pvp := is_pvp_kind(str(entry.get("kind", "")))
	var duel := str(entry.get("kind", "")) == KIND_DUEL   # M3d WP-EVENTS
	ch.apply_battle_outcome(u, host.tables, host.options)
	_settle_consumed(s, ch, u)       # M3A_PLAN 5.8 #1
	if not duel:
		_settle_conditions(ch, u)    # M3A_PLAN 5.8 #2（切磋模式：戰鬥中的狀態不帶出來）
	var died := bool(u.get("died", false)) and not duel   # 切磋模式沒有死亡（M3D_PLAN §5.3.4）
	var fled := bool(u.get("fled", false))
	var per := result
	if died:
		per = "DEFEAT"
	elif fled or result == "ALL_FLED":
		per = "FLED"
	# 勝利但沒有任何敵人被打死＝對手全部逃走，沒有獎勵（UI 顯示「對手逃走了」）
	# M3d：比武（DUEL）判定勝、對手棄權都不算「對手逃走」
	var enemies_fled := per == "VICTORY" and not duel and not b.units.any(func(x): return x.side != int(u.get("side", 0)) and x.is_dead())
	var close := {
		"bid": b.id, "result": per, "you_died": died, "enemies_fled": enemies_fled,
		"rewards": { "combat_xp": 0, "learn_points": 0, "money": 0, "items": [] },
		"death": {}, "kind": str(entry.get("kind", "")),
	}
	if s != null:
		match per:
			"VICTORY":
				host.tell(s, Protocol.CH_BATTLE,
					Protocol.E_BATTLE_VICTORY_FLED if enemies_fled else Protocol.E_BATTLE_VICTORY, {})
			"DEFEAT":
				host.tell(s, Protocol.CH_BATTLE, Protocol.E_BATTLE_DEFEAT, {})
			"FLED":
				host.tell(s, Protocol.CH_BATTLE, Protocol.E_BATTLE_FLED, {})
	if per == "VICTORY":
		var kills: Array = []
		if r is Dictionary:
			_spar_adjust(entry, s, ch, r)   # M3c2 整合：切磋獎勵在發放前依規則／每日上限／新手期改寫（M3C2_PLAN §2.3.3）
			var got: Dictionary = ch.apply_rewards(r, host.rules)
			close["rewards"]["combat_xp"] = int(got.get("combat_xp", 0))
			close["rewards"]["learn_points"] = int(got.get("learn_points", 0))
			close["rewards"]["money"] = int(got.get("money", 0))
			for it in r.get("items", []):
				if not (it is Dictionary):
					continue
				var item_id := str(it.get("id", ""))
				var n := int(it.get("n", 1))
				var g: Dictionary = host.give_item(ch, item_id, n)
				if g.get("ok", false):
					close["rewards"]["items"].append({ "id": item_id, "name": host.item_name(item_id), "n": n,
						# M3C_PLAN §6.7：稀有度（WP-LOOT 的 items.rarity；預設 COMMON）
						"rarity": str(host.tables.get("items", {}).get(item_id, {}).get("rarity", "COMMON")) })
					if s != null and not bool(host.m2_call(host.get("loot"), "announces", [item_id], false)):
						host.item_gain_event(s, item_id, n)
			kills = r.get("kills", [])
			# M3C_PLAN §6.7：稀有掉落的傳聞與通知（LootSystem 為 null 時略過）
			host.m2_call(host.get("loot"), "on_settle", [s, ch, close["rewards"]["items"], kills, str(entry.get("room", ""))])
		else:
			kills = u.get("kills", [])   # 例：no_rewards 的切磋對手，仍要計 KILL 任務
		if s != null:
			if not pvp and str(entry.get("kind", "")) != KIND_ROGUE:   # PvP 沒有實戰與學點（5.2），不送「獲得 0 點」的訊息（ROGUE WP-RUN：試煉同）
				host.tell(s, Protocol.CH_BATTLE, Protocol.E_BATTLE_REWARD, {
					"combat_xp": close["rewards"]["combat_xp"], "learn_points": close["rewards"]["learn_points"],
					"money": close["rewards"]["money"] })
			host.quests.on_kills(s, kills)
	# M3A_PLAN 5.8 #3：門派系統（可能為 null，K3）
	var summary := battle_summary(entry, u, per)
	# STORY_PLAN §4.8：任務（FIGHT 目標、隊伍 KILL、護送）在 on_kills 之後；遊蕩惡人（WanderSystem 可能為 null）
	if s != null and host.quests != null:
		host.quests.on_battle_settled(s, summary)
	host.m2_call(host.get("wander"), "on_battle_settled", [s, ch, summary])
	var sects = host.get("sects")
	if sects != null and sects.has_method("on_battle_settled"):
		sects.on_battle_settled(s, ch, summary)
	# M3B_PLAN §5.1.8：打獵（WP-ECON 的 LifeSystem；沒有這個方法時略過）
	if str(entry.get("kind", "")) == KIND_HUNT:
		host.m2_call(host.life, "on_hunt_settled", [s, ch, summary])
	var rg_handled := false   # ROGUE WP-RUN
	if str(entry.get("kind", "")) == KIND_ROGUE:   # ROGUE WP-RUN：close.rogue；試煉的倒下不呼叫 handle_death（O8）
		rg_handled = bool(host.m2_call(host.get("rogue"), "settle_player", [s, ch, u, per, close], false))   # ROGUE WP-RUN
	if died and not rg_handled:   # ROGUE WP-RUN
		close["death"] = handle_death(s, ch, str(entry.get("room", "")), summary)
	if duel:
		_m3d_duel_restore(ch, close)   # M3d WP-EVENTS：戰後精氣神內力補滿
	if s != null:
		s.battle_id = 0
		ClientState.deliver_battle_close(s.peer_id, close)
		_battle_changed(s)
		host.flush_session(s, true)
	host.m3d_battle_settled(s, ch, summary)   # M3d
	host.save_char(ch)

## M3A_PLAN 5.8 #1：HIDDEN 用掉的暗器、ITEM 用掉的藥從背包扣，並送 item_lost
func _settle_consumed(s: Session, ch, u: Dictionary) -> void:
	var used: Dictionary = u.get("used_items", {})
	var uids := used.keys()
	uids.sort()
	for iu in uids:
		var n := int(used[iu])
		if n <= 0:
			continue
		var it: Dictionary = ch.inventory.find(str(iu))
		if it.is_empty():
			continue
		var item_id := str(it.get("id", ""))
		n = mini(n, int(it.get("n", 0)))
		if n <= 0:
			continue
		ch.inventory.remove(str(iu), n)
		if s != null:
			host.item_lost_event(s, item_id, n)
			s.sheet_dirty = true

## M3A_PLAN 5.8 #2：結束時身上 persists 的狀態 → ch.add_condition；開戰時帶進來、戰鬥中解掉的 → clear_condition。
## Character 的新方法由 WP-RULES 提供；還沒有時略過（容錯）。
## 戰後持續狀態寫回（M3A_PLAN 5.8 #2；M3a 審查修正）。帶進戰鬥的狀態（start_statuses）不會在開戰時從角色身上拿掉：
## - 戰鬥中被治好（cured_statuses：解藥、醫、逼毒）→ 移除；只是戰鬥中的行動次數用完 → 保留戰後發作，actions_left = 0（M3a 審查 B1）；
## - 還在、等級沒有變高 → 保留原本的發作次數與下次發作時刻（不重新計時），只更新剩餘行動次數 actions_left；
## - 戰鬥中新中的（或等級變高）→ add_condition（取較高等級、較多次數），actions_left = 剩餘行動次數。
func _settle_conditions(ch, u: Dictionary) -> void:
	var st: Dictionary = host.tables.get("status_effects", {})
	var end: Dictionary = u.get("statuses", {})
	var left: Dictionary = u.get("status_left", {})
	var start: Dictionary = u.get("start_statuses", {})
	var online_v: Variant = ch.get("online_s")
	var online_s := float(online_v) if online_v != null else 0.0
	var conds_v: Variant = ch.get("conditions")
	var conds: Dictionary = conds_v if conds_v is Dictionary else {}
	var cured: Dictionary = u.get("cured_statuses", {})
	for sid in start:
		if end.has(sid) or not bool(st.get(sid, {}).get("persists", false)):
			continue
		var k0 := str(sid)
		if cured.has(sid):
			# 戰鬥中被治好（解藥、醫、逼毒）→ 角色身上的持續狀態一起解除
			if ch.has_method("clear_condition"):
				ch.clear_condition(k0)
		elif conds.has(k0):
			# 只是戰鬥中的行動次數用完：戰後的發作（ticks_left、next_online_s）原封不動保留，之後不再帶進戰鬥（M3a 審查 B1）
			(conds[k0] as Dictionary)["actions_left"] = 0
	for sid in end:
		var row: Dictionary = st.get(sid, {})
		if not bool(row.get("persists", false)) or not ch.has_method("add_condition"):
			continue
		var lv := maxi(1, int(end[sid]))
		var key := str(sid)
		var carried := start.has(sid) and conds.has(key) and lv <= int(start[sid])
		if not carried:
			ch.add_condition(key, lv, lv * int(row.get("persist_ticks_per_level", 0)),
				online_s + float(row.get("persist_tick_real_s", 0)))
		if conds.has(key):
			var e: Dictionary = conds[key]
			# 戰鬥中被逼毒降了等級（還沒解完）→ 角色身上的等級跟著降
			if carried and lv < int(e.get("level", lv)):
				e["level"] = lv
			e["actions_left"] = maxi(0, int(left.get(sid, row.get("duration_actions", 0))))
			# 戰鬥中暫停發作：已經過了的發作時刻延到戰後立刻發作一次（不在戰後一口氣補發好幾次）
			e["next_online_s"] = maxf(float(e.get("next_online_s", 0.0)), online_s)

## M3A_PLAN 5.8 #3 的 summary：{ kind, result, kills, killed_by: { kind, ref, sect }, died, pvp_initiator, same_sect_kills }
func battle_summary(entry: Dictionary, u: Dictionary, per: String) -> Dictionary:
	var b: Battle = entry["battle"]
	var kind := str(entry.get("kind", ""))
	var killed_by := { "kind": "", "ref": "", "sect": "" }
	var k: BattleUnit = b.unit(int(u.get("killed_by", 0)))
	if k != null:
		killed_by = { "kind": k.kind(), "ref": str(k.spec.get("ref", "")), "sect": k.sect() }   # ROGUE WP-ALLY
	var me: BattleUnit = b.unit(int(u.get("uid", 0)))
	var same: Array = []
	if kind == KIND_DUEL:
		me = null   # M3d WP-EVENTS：比武打倒同門不算同門相殘
	if me != null and me.sect() != "":
		for v in b.units:
			if v != me and v.is_player() and v.is_dead() and v.killed_by == me.uid and v.sect() == me.sect():
				same.append(str(v.spec.get("ref", "")))
	var opts: Variant = entry.get("opts", {})
	var tag: Variant = opts.get("quest_tag", {}) if opts is Dictionary else {}
	# M3d 審查：同一邊的其他玩家（角色 id）與「有沒有打倒任何對手」——ComboSystem 判斷合體夥伴一起打贏（戰鬥結束時 active 已移除）
	var my_side := int(u.get("side", 0))
	var allies: Array = []
	var foes_killed := false
	for v in b.units:
		if v.side == my_side:
			if v.is_player() and v.uid != int(u.get("uid", 0)):
				allies.append(v.char_id())
		elif v.is_dead():
			foes_killed = true
	return {
		"allies": allies, "foes_killed": foes_killed,
		"kind": kind, "result": per, "kills": (u.get("kills", []) as Array).duplicate(),
		"killed_by": killed_by, "died": bool(u.get("died", false)) and kind != KIND_DUEL,   # 切磋模式沒有死亡（M3d）
		"pvp_initiator": is_pvp_kind(kind) and int(u.get("side", 0)) == 0,
		"same_sect_kills": same,
		# STORY_PLAN §4.8：開戰動作帶的任務標籤、本人結果、同一方隊友打倒的怪物
		"quest_tag": (tag as Dictionary).duplicate(true) if tag is Dictionary else {},
		"per": per,
		"party_kills": (u.get("party_kills", []) as Array).duplicate() if u.get("party_kills") is Array else [],
		"room": str(entry.get("room", "")),
		"bid": int((entry["battle"] as Battle).id),
		# M3B_PLAN §5.1.5：捉拿公敵的門派（capture_on_death 用；其他戰鬥 ""）
		"seize_sect": str(opts.get("seize_sect", "")) if opts is Dictionary else "",
	}

## 4.13：DeathPenalty → 屍體 → 重生 → 事件。回傳 3.9.4 的 death 字典。
## M3A_PLAN 5.8 #4：先問 host.sects.capture_on_death；回傳 { jail: true } 時照常套死亡懲罰，但不送回記錄點（由 SectSystem 押入思過處）。
func handle_death(s: Session, ch, death_room: String, summary: Dictionary = {}) -> Dictionary:
	var capture := {}
	var sects = host.get("sects")
	if sects != null and sects.has_method("capture_on_death"):
		var cap: Variant = sects.capture_on_death(s, ch, summary)
		if cap is Dictionary:
			capture = cap
	var jailed := bool(capture.get("jail", false))
	if death_room == "":
		death_room = str(ch.location.get("room", ""))
	var dead_before := int(ch.dead_count)
	var dp: Dictionary = DeathPenalty.apply(ch, host.rules, host.tables)
	if int(ch.dead_count) == dead_before:
		ch.dead_count = dead_before + 1   # M1_PLAN 缺漏：dead_count +1 由誰做沒寫死；沒做就由 WORLD 補
	var rule := str(dp.get("rule", host.rules.get("death_rule", "STANDARD")))
	var dropped: Array = dp.get("dropped", [])
	var n_items := 0
	for it in dropped:
		if it is Dictionary:
			n_items += int(it.get("n", 1))
	if not dropped.is_empty() and rule != "CASUAL":
		host.corpses.create(ch, death_room, dropped)
		# 先寫死者的角色檔（物品已移除），再寫 world.json（屍體）。斷線者的角色不在 sessions() 裡，
		# save_now 不會存它，要明寫；順序反過來的話，兩次寫入之間當機會讓物品同時在屍體和舊角色檔裡（M2 審查）
		host.save_char(ch)
		host.ws.save_now()
	var dest := host.respawn_room(ch)
	DeathPenalty.respawn_vitals(ch, host.tables, host.options)
	var losses: Array = dp.get("skill_losses", [])
	var money_lost := int(dp.get("money_lost", 0))
	var death_room_name := host.room_name(death_room)
	if s != null:
		match rule:
			"STRICT_2001":
				host.tell(s, Protocol.CH_SYSTEM, Protocol.E_DEATH_STRICT,
					{ "n_skills": losses.size(), "n_items": n_items, "room_name": death_room_name })
			"CASUAL":
				host.tell(s, Protocol.CH_SYSTEM, Protocol.E_DEATH_CASUAL, { "money_lost": money_lost })
			_:
				if bool(dp.get("safe_newbie", false)):
					host.tell(s, Protocol.CH_SYSTEM, Protocol.E_DEATH_STANDARD_SAFE, {})
				else:
					# M1_PLAN 缺漏：沒有特殊武功可降時，skill_name 為空字串、level 為 0
					var first: Dictionary = losses[0] if not losses.is_empty() and losses[0] is Dictionary else {}
					host.tell(s, Protocol.CH_SYSTEM, Protocol.E_DEATH_STANDARD, {
						"skill_name": str(first.get("name", host.skill_name(str(first.get("skill", ""))) if not first.is_empty() else "")),
						"level": int(first.get("to", 0)), "n_items": n_items, "room_name": death_room_name })
		if not jailed:
			host.regions.teleport(s, dest)
			host.tell(s, Protocol.CH_SYSTEM, Protocol.E_RESPAWN, { "room_name": host.room_name(dest) })
			host.quests.on_reach(s)
	elif not jailed:
		ch.location = { "region": host.index.region_of(dest), "room": dest }
	var out := {
		"rule": rule, "skill_losses": losses.duplicate(true), "n_items": n_items,
		"money_lost": money_lost, "respawn_room_name": host.room_name(dest),
	}
	if jailed:
		out["jailed"] = true
		out["respawn_room_name"] = str(capture.get("room_name", ""))
	return out

# ==== M3d WP-EVENTS ====
## M3D_PLAN §5.2.2（劫鏢 ROB）、§5.3.3–5.3.4（比武 DUEL）。ROB：side 0＝劫鏢方（不能逃）、side 1＝押鏢者＋鏢單位
## （鏢車 m_ev_jb_cart／客商 m_ev_jb_client）；鏢單位倒下＝劫鏢成功，戰鬥當場結束。DUEL：切磋模式（不觸發門技、
## 拿掉召喚類道具、沒有死亡懲罰、戰後補滿），限時 opts.duel_limit_s（戰鬥時間）到了由 Battle._duel_check 判定，
## 逃走與斷線＝棄權；擂臺與休息區的旁觀者收到每一擊的文字（ev_duel_line）。
const DUEL_LINE := "ev_duel_line"
const DUEL_LINE_MISS := "ev_duel_line_miss"

## start_pvp：_begin 之前（Battle 還在 SETUP）。ROB → side 1 加一個鏢單位（opts.jb.kind：hu 客商、huo 鏢車）
func _m3d_events_pre_begin(entry: Dictionary) -> void:
	if str(entry.get("kind", "")) != KIND_ROB:
		return
	var jb: Variant = entry.get("opts", {}).get("jb", {})
	var kind := str(jb.get("kind", JiebiaoRules.KIND_HUO)) if jb is Dictionary else JiebiaoRules.KIND_HUO
	var mid := str(JiebiaoRules.ROB_UNIT.get(kind, JiebiaoRules.ROB_UNIT[JiebiaoRules.KIND_HUO]))
	if not host.tables.get("monsters", {}).has(mid):
		return   # 資料還沒有（平行開發）：只打押鏢者本人
	var b: Battle = entry["battle"]
	for spec in Encounter.monster_specs([mid], host.tables):
		spec["side"] = 1
		spec["peer"] = 0
		entry["rob_uid"] = b.add_unit(spec)
		break

## DUEL 規格：門技清空（不觸發）、召喚類道具（effects 有 SUMMON）拿掉、先報名者的順位（限時判定的最後一層）
func _m3d_duel_spec(entry: Dictionary, spec: Dictionary) -> void:
	spec["sect_skill"] = {}
	var keep: Array = []
	for it in spec.get("battle_items", []):
		if it is Dictionary and _m3d_is_summon(it):
			continue
		keep.append(it)
	spec["battle_items"] = keep
	var order: Variant = entry.get("opts", {}).get("order", {})
	if order is Dictionary:
		spec["duel_order"] = int((order as Dictionary).get(str(spec.get("ref", "")), 1 << 20))

static func _m3d_is_summon(it: Dictionary) -> bool:
	for e in it.get("effects", []):
		if e is Dictionary and str(e.get("type", "")).to_upper() == "SUMMON":
			return true
	return false

## 開場快照：劫鏢方（side 0）一律不能逃；比武帶限時
func _m3d_events_state(entry: Dictionary, state: Dictionary, my_side: int) -> void:
	var kind := str(entry.get("kind", ""))
	if kind == KIND_ROB and my_side == 0:
		state["no_flee"] = true
	if kind == KIND_DUEL:
		var b: Battle = entry["battle"]
		state["duel_limit_s"] = float(b.opts.get("duel_limit_s", DUEL_LIMIT_DEFAULT_S))
		state["duel_left_s"] = maxf(0.0, float(state["duel_limit_s"]) - b.time_s())

## battle_cmd：劫鏢方的 FLEE、QING ESCAPE → no_flee（烙跑鞋也不行；§5.2.2）
func _m3d_rob_no_flee(entry: Dictionary, s: Session, args: Dictionary) -> String:
	if str(entry.get("kind", "")) != KIND_ROB:
		return ""
	var cmd := str(args.get("cmd", ""))
	if not (cmd == "FLEE" or (cmd == "QING" and str(args.get("mode", "")) == "ESCAPE")):
		return ""
	var b: Battle = entry["battle"]
	var me: BattleUnit = b.unit(b.uid_for_peer(s.peer_id))
	return "no_flee" if me != null and me.side == 0 else ""

## 每 tick（戰鬥還沒結束時）：比武限時（Battle._check_end 只在有人行動後才看；這裡補上整段蓄力期間）、
## 比武有人斷線＝棄權、劫鏢的鏢單位倒下＝劫鏢成功
func _m3d_events_tick(entry: Dictionary) -> void:
	var b: Battle = entry["battle"]
	match str(entry.get("kind", "")):
		KIND_DUEL:
			if b.opts.has("duel_limit_s") and b._duel_check():
				_forward(entry, b.drain_events())
				return
			for u in b.units:
				if u.is_player() and u.detached and u.is_active():
					_m3d_duel_forfeit(entry)
					return
		KIND_ROB:
			var cart: BattleUnit = b.unit(int(entry.get("rob_uid", 0)))
			if cart != null and cart.is_dead():
				b.ev_end(0, "ROBBED")
				_forward(entry, b.drain_events())

## 比武棄權：還有在線（沒斷線、在場）玩家的一方勝；兩方都沒有 → 依限時判定的規則
func _m3d_duel_forfeit(entry: Dictionary) -> void:
	var b: Battle = entry["battle"]
	if b.is_over():
		return
	var live := [false, false]
	for u in b.units:
		if u.is_player() and u.is_active() and not u.detached and (u.side == 0 or u.side == 1):
			live[u.side] = true
	if live[0] == live[1]:
		var w := TourneyRules.judge(b._ev_side_stats(0), b._ev_side_stats(1))
		b.ev_end(w, "FORFEIT")
	else:
		b.ev_end(0 if live[0] else 1, "FORFEIT")
	_forward(entry, b.drain_events())

## DUEL 結果：一方全部逃走（棄權）→ 另一方勝（Battle 判成 ALL_FLED）；how 寫進 out.duel_how（KO／JUDGE／FORFEIT）
func _m3d_duel_outcome(out: Dictionary) -> void:
	var units: Dictionary = out.get("units", {})
	var active := [false, false]
	var fled := [false, false]
	for k in units:
		var u: Dictionary = units[k]
		var sd := clampi(int(u.get("side", 0)), 0, 1)
		if bool(u.get("fled", false)):
			fled[sd] = true
		elif not bool(u.get("died", false)):
			active[sd] = true
	var result := str(out.get("result", ""))
	if result == "ALL_FLED" and active[0] != active[1]:
		var w := 0 if active[0] else 1
		out["result"] = "VICTORY" if w == 0 else "DEFEAT"
		out["winner_side"] = w
	var how := "KO"
	if fled[0] or fled[1]:
		how = "FORFEIT"
	out["duel_how"] = how

## 結算之後：劫鏢分贓與押鏢失敗（JiebiaoSystem）、比武晉級（TourneySystem）；系統為 null 時略過
func _m3d_events_finish(entry: Dictionary, out: Dictionary) -> void:
	var b: Battle = entry["battle"]
	var ev: Variant = b.opts.get("ev_end", {})
	if ev is Dictionary and not (ev as Dictionary).is_empty():
		out["ev_end"] = (ev as Dictionary).duplicate()
		if str(entry.get("kind", "")) == KIND_DUEL:
			out["duel_how"] = str(ev.get("how", "JUDGE"))
	match str(entry.get("kind", "")):
		KIND_ROB:
			host.m2_call(host.get("jiebiao"), "on_rob_end", [entry, out])
		KIND_DUEL:
			host.m2_call(host.get("tourney"), "on_duel_end", [entry, out])

## 比武戰後：精氣神內力補滿（沒有死亡、戰鬥中的狀態不帶出來）
func _m3d_duel_restore(ch, close: Dictionary) -> void:
	Survival.rest_full(ch, host.tables, host.options)
	close["you_died"] = false
	close["death"] = {}
	close["duel"] = true

## 擂臺與休息區不在這場戰鬥裡的人：每一擊的房間文字
func _m3d_duel_spectate(entry: Dictionary, evs: Array) -> void:
	var peers: Array = []
	for s in host.sessions():
		if s.character == null or (entry["peers"] as Array).has(s.peer_id):
			continue
		if s.room_id() in TourneyRules.ARENA_ROOMS:
			peers.append(s.peer_id)
	if peers.is_empty():
		return
	for e in evs:
		if not (e is Dictionary):
			continue
		var p: Variant = e.get("p", {})
		if not (p is Dictionary):
			continue
		var key := ""
		var pp := {}
		if (p as Dictionary).has("dmg") and (p as Dictionary).has("atk") and (p as Dictionary).has("def"):
			key = DUEL_LINE
			pp = { "atk": str(p["atk"]), "def": str(p["def"]), "dmg": int(p["dmg"]) }
		elif str(e.get("key", "")) == "battle_miss":
			key = DUEL_LINE_MISS
			pp = { "atk": str(p.get("atk", "")), "def": str(p.get("def", "")) }
		if key == "":
			continue
		for peer in peers:
			host.ws.queue_event(int(peer), Protocol.CH_SCENE, key, pp.duplicate())

## 某場戰鬥某一方的玩家：[{ peer, char_id, ch }]（含斷線者；JiebiaoSystem 開戰當下給劫鏢標記用）
func side_players(bid: int, side: int) -> Array:
	var out: Array = []
	if not active.has(bid):
		return out
	var entry: Dictionary = active[bid]
	var b: Battle = entry["battle"]
	for u in b.units:
		if not u.is_player() or u.side != side:
			continue
		var ch = entry["chars"].get(u.peer)
		out.append({ "peer": u.peer, "char_id": str(u.spec.get("ref", "")), "ch": ch })
	return out

# ==== ROGUE WP-ALLY ====（ROGUE_PLAN §4.2；WP-RUN Day-0 寫的空殼，由 WP-ALLY 實作）
## start_ex：玩家加入之後、怪物之前，把 opts.ally_specs 的隊友單位（side 0、peer 0、ai ally）放進戰場
const ROGUE_ALLY_MAX := 2   # rogue_rules.ally_max 的預設；opts.ally_max 可覆寫

func _rogue_ally_units(entry: Dictionary, b: Battle, opts: Dictionary) -> void:
	var specs: Variant = opts.get("ally_specs", [])
	if not (specs is Array) or (specs as Array).is_empty():
		return
	var cap := int(opts.get("ally_max", ROGUE_ALLY_MAX))
	var n := 0
	for spec in specs:
		if not (spec is Dictionary) or (spec as Dictionary).is_empty():
			continue
		if n >= cap:
			break
		var sp: Dictionary = (spec as Dictionary).duplicate(true)
		sp["side"] = 0   # 隊友永遠站在玩家這一邊（BattleGrid.place_units 放左側）
		sp["peer"] = 0   # AI 控制：Battle 不會等它下令
		sp["kind"] = RogueAlly.KIND
		sp["ai"] = RogueAlly.AI
		b.add_unit(sp)
		n += 1
	if n > 0:
		entry["rogue_allies"] = n
