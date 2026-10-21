class_name ComboSystem
extends RefCounted
## 合體默契（M3D_PLAN §3.3.2；1.0B，R10）：GameHost.combo（以路徑載入，缺檔時為 null）。
## - combo_bond { target_char }：同房、雙方都沒有夥伴、不是自己 → 對方收到 cb_bond_request（ui）→ combo_reply 同意
##   → world.combo_pairs["<小id>|<大id>"] = { a, b, a_name, b_name, moqi: 0, peihe: 0, since_day, drain_day }，
##   兩個角色 ext.combo = { partner: 對方 id, moqi }（moqi 是鏡像，權威在 world；給 Character.to_combatant 用）。
## - combo_cancel：任一方解除；離線的那一方在下次登入時惰性清掉 ext.combo。
## - combo_nurture（培養感情）：配合度 100 → 默契 +5（上限 100）、配合度歸 0；否則 combo_peihe_low。
## - 消耗（tick）：距 drain_day ≥ 2 遊戲日、而且兩人同時在線 → 配合度 −20；不夠扣 → 配合度 0、默契 −5（最低 0）。
## - 戰鬥：合體一擊成功一次 → 這一對配合度 +10（上限 100）；戰後結算（on_battle_settled）時算一次（只由角色 id 較小的一方計，避免兩人各算一次）。
## - M3d 審查（第 3 輪）：修練素心劍要默契（官方「待到默契值與心性修為都達到一定程度後方可修練」），但官方只寫合體一擊加配合度——
##   還不會合體武功的兩人沒有辦法累積 → 兩人同一邊一起打贏一場（不是比武、不是劫鏢）配合度 +JOINT_PEIHE，
##   每一對每遊戲日最多 JOINT_PEIHE_DAY_CAP【設計提案・非原作】。
## - 修練素心劍的 ctx（req_ctx）：{ combo: { partner, partner_here, same_party, partner_gender, partner_skills, partner_sect_skill, moqi } }；
##   同時寫進 ComboRules.live_ctx（師父列的 requires 不帶 ctx，見 battle_combo.gd）。
## 數字全部【設計提案】（研究：官方只寫「默契值與心性修為達一定程度」「定期扣配合度」）。

const WORLD_KEY := "combo_pairs"
const ERA := "1.0B"
const REQ_TTL_REAL_S := 60.0
const DRAIN_EVERY_DAYS := 2
const DRAIN_PEIHE := 20
const DRAIN_MOQI := 5
const NURTURE_MOQI := 5
const PEIHE_PER_HIT := 10
const MOQI_MAX := 100
const PEIHE_MAX := 100
const TICK_EVERY_S := 1.0
const JOINT_PEIHE := 10            # 【設計提案・非原作】兩人同一邊一起打贏一場
const JOINT_PEIHE_DAY_CAP := 60    # 每一對每遊戲日最多（約 4 個遊戲日攢到修練門檻的默契 10）
const JOINT_SKIP_KINDS := ["DUEL", "ROB"]

var host     # GameHost（dispose() 時設成 null）
var _requests: Dictionary = {}   # 被邀者 char_id -> { from_char, from_name, until_s（世界時間） }
var _battles: Dictionary = {}    # bid -> { b: Battle, gone_s }（有合體夥伴參戰的戰鬥；結算時讀 combo_with；結束 10 秒後丟掉）
var _acc := 0.0

func _init(p_host) -> void:
	host = p_host

# ---------------------------------------------------------------- 資料

func era_on() -> bool:
	return GameData.enabled_eras.has(ERA)

func pairs() -> Dictionary:
	var d: Variant = host.ws.world.get(WORLD_KEY)
	if not (d is Dictionary):
		d = {}
		host.ws.world[WORLD_KEY] = d
	return d

static func pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]

## 這個角色所在的那一對（沒有回 {}）
func pair_of(char_id: String) -> Dictionary:
	if char_id == "":
		return {}
	for k in pairs():
		var p: Dictionary = pairs()[k]
		if str(p.get("a", "")) == char_id or str(p.get("b", "")) == char_id:
			return p
	return {}

static func other_of(p: Dictionary, char_id: String) -> String:
	return str(p.get("b", "")) if str(p.get("a", "")) == char_id else str(p.get("a", ""))

func today() -> int:
	return int(host.clock()["day"])

func _name_in(p: Dictionary, cid: String) -> String:
	return str(p.get("a_name", "")) if str(p.get("a", "")) == cid else str(p.get("b_name", ""))

# ---------------------------------------------------------------- intents

func bond(s: Session, target_char: String) -> Dictionary:
	if not era_on():
		return GameHost.fail("era_locked")
	var ch = s.character
	if target_char == "" or target_char == str(ch.id):
		return GameHost.fail("not_here")
	var t: Session = host.session_for_char(target_char)
	if t == null or t.character == null or t.room_id() != s.room_id():
		return GameHost.fail("not_here")
	if not pair_of(str(ch.id)).is_empty() or not pair_of(target_char).is_empty():
		return GameHost.fail("combo_has_partner")
	# M3d 審查：對方還有沒過期的請求（不論誰送的）→ 不再送、不再跳視窗（防洗版）；自己同時只能有一個送出中的請求
	var now: float = host.now_s()
	var live: Dictionary = _requests.get(target_char, {})
	if not live.is_empty() and float(live.get("until_s", 0.0)) >= now:
		return GameHost.fail("combo_request_pending")
	for k in _requests.keys():
		if str(_requests[k].get("from_char", "")) == str(ch.id) and float(_requests[k].get("until_s", 0.0)) >= now:
			return GameHost.fail("combo_request_pending")
	_requests[target_char] = { "from_char": str(ch.id), "from_name": str(ch.name),
		"until_s": host.now_s() + host.world_span(REQ_TTL_REAL_S) }
	host.tell(t, Protocol.CH_SYSTEM, "cb_bond_request", { "from_char": str(ch.id), "from_name": str(ch.name),
		"ttl_s": REQ_TTL_REAL_S }, true)
	host.tell(s, Protocol.CH_SYSTEM, "cb_bond_sent", { "target_name": str(t.character.name) })
	return GameHost.ok()

func reply(s: Session, from_char: String, accept: bool) -> Dictionary:
	if not era_on():
		return GameHost.fail("era_locked")
	var me := str(s.character.id)
	var r: Dictionary = _requests.get(me, {})
	if r.is_empty() or str(r.get("from_char", "")) != from_char or float(r.get("until_s", 0.0)) < host.now_s():
		_requests.erase(me)
		return GameHost.fail("combo_no_request")
	_requests.erase(me)
	var f: Session = host.session_for_char(from_char)
	if not accept:
		if f != null:
			host.tell(f, Protocol.CH_SYSTEM, "cb_bond_refused", { "target_name": str(s.character.name) })
		return GameHost.ok()
	if f == null or f.character == null or f.room_id() != s.room_id():
		return GameHost.fail("not_here")
	if not pair_of(me).is_empty() or not pair_of(from_char).is_empty():
		return GameHost.fail("combo_has_partner")
	var d := today()
	var a := from_char if from_char < me else me
	var b := me if a == from_char else from_char
	var names := { from_char: str(f.character.name), me: str(s.character.name) }
	pairs()[pair_key(a, b)] = { "a": a, "b": b, "a_name": names[a], "b_name": names[b], "moqi": 0, "peihe": 0,
		"since_day": d, "drain_day": d }
	for x in [s, f]:
		_sync_ext(x)
		host.tell(x, Protocol.CH_SYSTEM, "cb_bond_formed", { "partner_name": str(names[other_of(pair_of(me), str(x.character.id))]) })
	_changed(pair_of(me))
	return GameHost.ok()

func cancel(s: Session) -> Dictionary:
	if not era_on():
		return GameHost.fail("era_locked")
	var me := str(s.character.id)
	var p := pair_of(me)
	if p.is_empty():
		return GameHost.fail("combo_need_partner")
	var other := other_of(p, me)
	pairs().erase(pair_key(str(p.a), str(p.b)))
	for cid in [me, other]:
		var x: Session = host.session_for_char(cid)
		if x == null or x.character == null:
			continue
		_clear_ext(x.character)
		ComboRules.live_ctx.erase(cid)
		host.tell(x, Protocol.CH_SYSTEM, "cb_bond_cancelled", { "partner_name": _name_in(p, other_of(p, cid)) })
		host.tell(x, Protocol.CH_SYSTEM, "cb_bond_changed", { "partner_name": "", "moqi": 0, "peihe": 0, "drain_day": 0 }, true)
		x.sheet_dirty = true
		host.save_char(x.character)
	return GameHost.ok()

func nurture(s: Session) -> Dictionary:
	if not era_on():
		return GameHost.fail("era_locked")
	var p := pair_of(str(s.character.id))
	if p.is_empty():
		return GameHost.fail("combo_need_partner")
	if int(p.get("peihe", 0)) < PEIHE_MAX:
		return GameHost.fail("combo_peihe_low")
	p["moqi"] = mini(MOQI_MAX, int(p.get("moqi", 0)) + NURTURE_MOQI)
	p["peihe"] = 0
	for cid in [str(p.a), str(p.b)]:
		var x: Session = host.session_for_char(cid)
		if x != null:
			host.tell(x, Protocol.CH_SYSTEM, "cb_nurtured", { "partner_name": _name_in(p, other_of(p, cid)), "moqi": int(p.moqi) })
	_changed(p)
	return GameHost.ok()

# ---------------------------------------------------------------- 週期

func tick(dt: float) -> void:
	_acc += dt
	_scan_battles()
	if _acc < TICK_EVERY_S:
		return
	_acc = 0.0
	var now: float = host.now_s()
	for k in _requests.keys():
		if float(_requests[k].get("until_s", 0.0)) < now:
			_requests.erase(k)
	drain_all(today())
	refresh_live_ctx()

## 每對關係：距 drain_day ≥ 2 遊戲日、兩人同時在線 → 配合度 −20（不夠 → 0、默契 −5）；回傳扣了幾對
func drain_all(day: int) -> int:
	var n := 0
	for k in pairs().keys():
		var p: Dictionary = pairs()[k]
		if day - int(p.get("drain_day", day)) < DRAIN_EVERY_DAYS:
			continue
		var sa: Session = host.session_for_char(str(p.get("a", "")))
		var sb: Session = host.session_for_char(str(p.get("b", "")))
		if sa == null or sb == null or sa.character == null or sb.character == null:
			continue
		var pe := int(p.get("peihe", 0))
		if pe >= DRAIN_PEIHE:
			p["peihe"] = pe - DRAIN_PEIHE
		else:
			p["peihe"] = 0
			p["moqi"] = maxi(0, int(p.get("moqi", 0)) - DRAIN_MOQI)
		p["drain_day"] = day
		n += 1
		for x in [sa, sb]:
			host.tell(x, Protocol.CH_SYSTEM, "cb_drained", { "partner_name": _name_in(p, other_of(p, str(x.character.id))),
				"moqi": int(p.moqi), "peihe": int(p.peihe) })
		_changed(p)
	return n

## 有合體夥伴參戰的戰鬥記下來（結算時讀 combo_with；BattleSystem 的 summary 沒有帶 combo_hits，見 on_battle_settled）
func _scan_battles() -> void:
	var bs = host.get("battles")
	if bs == null or not ("active" in bs):
		return
	var now: float = host.now_s()
	for bid in _battles.keys():
		if bs.active.has(bid):
			continue
		var e: Dictionary = _battles[bid]
		if float(e.get("gone_s", -1.0)) < 0.0:
			e["gone_s"] = now
		elif now - float(e["gone_s"]) > 10.0:
			_battles.erase(bid)
	for bid in bs.active:
		if _battles.has(bid):
			continue
		var b: Battle = bs.active[bid].get("battle")
		if b == null:
			continue
		for u in b.units:
			if not u.combo_spec().is_empty():
				_battles[bid] = { "b": b, "gone_s": -1.0 }
				break

# ---------------------------------------------------------------- 鉤子（GameHost.m3d_*）

func on_login(s: Session) -> void:
	if s == null or s.character == null:
		return
	var p := pair_of(str(s.character.id))
	var c: Variant = s.character.ext.get("combo", {})
	if p.is_empty():
		if c is Dictionary and str((c as Dictionary).get("partner", "")) != "":
			_clear_ext(s.character)   # 夥伴在我離線時解除了 → 惰性清掉
	else:
		_sync_ext(s)
	refresh_live_ctx()

func on_logout(s: Session) -> void:
	if s == null or s.character == null:
		return
	var me := str(s.character.id)
	ComboRules.live_ctx.erase(me)
	_requests.erase(me)
	for k in _requests.keys():
		if str(_requests[k].get("from_char", "")) == me:
			_requests.erase(k)

## M3d 審查：原本任何人走一步就整張 refresh_live_ctx（掃全部配對、複製夥伴整張武學表）→ 只更新走動的人與他的夥伴
## （同房、同隊的判定跟著位置變；其他人的由 1 秒 tick 更新）
func on_enter_room(s: Session, _from: String, _to: String) -> void:
	if s == null or s.character == null:
		return
	var me := str(s.character.id)
	var p := pair_of(me)
	if p.is_empty():
		return
	ComboRules.live_ctx[me] = ctx_for(s)
	var o: Session = host.session_for_char(other_of(p, me))
	if o != null and o.character != null:
		ComboRules.live_ctx[str(o.character.id)] = ctx_for(o)

func on_char_deleted(char_id: String) -> void:
	var p := pair_of(char_id)
	if p.is_empty():
		return
	pairs().erase(pair_key(str(p.a), str(p.b)))
	var other: Session = host.session_for_char(other_of(p, char_id))
	if other != null and other.character != null:
		_clear_ext(other.character)
		host.tell(other, Protocol.CH_SYSTEM, "cb_bond_changed", { "partner_name": "", "moqi": 0, "peihe": 0, "drain_day": 0 }, true)
		other.sheet_dirty = true
	ComboRules.live_ctx.erase(char_id)

## 戰後：合體一擊成功幾次 → 配合度 +10／次（上限 100）。summary.combo_hits（整合者若在 battle_summary 帶上）優先；
## 否則讀 _scan_battles 記下的 Battle 的單位 combo_with。只由角色 id 較小的一方計。
## M3D_PLAN 缺漏：§3.3.3 寫「由 battle_summary 帶出 combo_hits」，但 battle_summary 在 WP-EVENTS 的檔案、§9.2 沒有派這一行
func on_battle_settled(_s: Session, ch, summary: Dictionary) -> void:
	if ch == null:
		return
	var me := str(ch.id)
	var p := pair_of(me)
	var bid := int(summary.get("bid", 0))
	var b: Battle = (_battles.get(bid, {}) as Dictionary).get("b", null)
	if p.is_empty() or me != str(p.get("a", "")):
		return
	var partner := other_of(p, me)
	var n := 0
	var joint := false
	var kind_ok := not (str(summary.get("kind", "")) in JOINT_SKIP_KINDS) \
		and str(summary.get("per", summary.get("result", ""))) == "VICTORY"
	if summary.has("allies"):
		# BattleSystem.battle_summary 帶的同邊玩家與「有打倒對手」（結算時 active 已經移除，tick 可能還沒記到這一場）
		joint = kind_ok and (summary["allies"] as Array).has(partner) and bool(summary.get("foes_killed", false))
	if b != null:
		var mine: BattleUnit = null
		var his: BattleUnit = null
		for u in b.units:
			if u.is_player() and u.char_id() == me:
				mine = u
			elif u.is_player() and u.char_id() == partner:
				his = u
		if mine != null and not summary.has("combo_hits"):
			n = (mine.combo_with as Array).count(partner)
		if not summary.has("allies"):
			# 對手逃光的「勝利」不算
			joint = kind_ok and mine != null and his != null and mine.side == his.side \
				and b.units.any(func(x): return x.side != mine.side and x.is_dead())
	if summary.has("combo_hits"):
		n = int(summary["combo_hits"])
	var add := PEIHE_PER_HIT * maxi(0, n)
	if joint:
		var d := today()
		if int(p.get("joint_day", -1)) != d:
			p["joint_day"] = d
			p["joint_today"] = 0
		var j := mini(JOINT_PEIHE, maxi(0, JOINT_PEIHE_DAY_CAP - int(p.get("joint_today", 0))))
		p["joint_today"] = int(p.get("joint_today", 0)) + j
		add += j
	if add <= 0:
		return
	p["peihe"] = mini(PEIHE_MAX, int(p.get("peihe", 0)) + add)
	_changed(p)

func req_ctx(s: Session) -> Dictionary:
	if s == null or s.character == null:
		return {}
	return { "combo": ctx_for(s) }

func sheet_fields(s: Session) -> Dictionary:
	if s == null or s.character == null:
		return {}
	var p := pair_of(str(s.character.id))
	var on := era_on()
	if p.is_empty():
		return { "combo": { "partner_name": "", "moqi": 0, "peihe": 0, "era_on": on } }
	return { "combo": { "partner_name": _name_in(p, other_of(p, str(s.character.id))),
		"partner_char": other_of(p, str(s.character.id)), "moqi": int(p.get("moqi", 0)), "peihe": int(p.get("peihe", 0)),
		"since_day": int(p.get("since_day", 0)), "drain_day": int(p.get("drain_day", 0)),
		"next_drain_day": int(p.get("drain_day", 0)) + DRAIN_EVERY_DAYS, "era_on": on } }

# ---------------------------------------------------------------- ctx

## 修練合體武功的 ctx（M3D_PLAN §9.2 的 combo 鍵）
func ctx_for(s: Session) -> Dictionary:
	var me := str(s.character.id)
	var p := pair_of(me)
	if p.is_empty():
		return { "partner": "" }
	var other := other_of(p, me)
	var o: Session = host.session_for_char(other)
	var out := { "partner": other, "partner_here": false, "same_party": false, "partner_gender": "",
		"partner_skills": {}, "partner_sect_skill": 0, "moqi": int(p.get("moqi", 0)) }
	if o == null or o.character == null:
		return out
	var oc = o.character
	out["partner_here"] = o.room_id() == s.room_id() and o.battle_id == 0
	var party = host.get("party")
	out["same_party"] = party != null and bool(party.same_party(me, other))
	out["partner_gender"] = str(oc.gender)
	var sk := {}
	for k in oc.skills.entries.keys():
		var lv: int = oc.skills.level(k)
		if lv >= 1:
			sk[str(k)] = lv
	out["partner_skills"] = sk
	var ss := str(host.tables.get("sects", {}).get(str(oc.sect), {}).get("sect_skill", "")) if str(oc.sect) != "" else ""
	out["partner_sect_skill"] = oc.skills.level(ss) if ss != "" else 0
	return out

## 在線、有夥伴的角色：ComboRules.live_ctx[char_id] = ctx_for(s)
func refresh_live_ctx() -> void:
	var keep := {}
	for s in host.sessions():
		if s.character == null:
			continue
		var me := str(s.character.id)
		if pair_of(me).is_empty():
			continue
		ComboRules.live_ctx[me] = ctx_for(s)
		keep[me] = true
	for k in ComboRules.live_ctx.keys():
		if not keep.has(k) and host.session_for_char(str(k)) != null:
			ComboRules.live_ctx.erase(k)

# ---------------------------------------------------------------- 內部

func _sync_ext(s: Session) -> void:
	var me := str(s.character.id)
	var p := pair_of(me)
	if p.is_empty():
		return
	s.character.ext["combo"] = { "partner": other_of(p, me), "moqi": int(p.get("moqi", 0)) }
	s.sheet_dirty = true

static func _clear_ext(ch) -> void:
	ch.ext.erase("combo")

## 關係變了：在線的兩人 ext 鏡像、角色表、cb_bond_changed（ui）
func _changed(p: Dictionary) -> void:
	for cid in [str(p.get("a", "")), str(p.get("b", ""))]:
		var x: Session = host.session_for_char(cid)
		if x == null or x.character == null:
			continue
		_sync_ext(x)
		host.tell(x, Protocol.CH_SYSTEM, "cb_bond_changed", { "partner_name": _name_in(p, other_of(p, cid)),
			"moqi": int(p.get("moqi", 0)), "peihe": int(p.get("peihe", 0)), "drain_day": int(p.get("drain_day", 0)) }, true)
		host.save_char(x.character)
	refresh_live_ctx()
