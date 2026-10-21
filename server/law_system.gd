class_name LawSystem
extends RefCounted
## 懸賞與律法（M3D_PLAN §2；WP-LAW）：佈告欄懸賞名單（每遊戲時辰統計）、賞金獵人執照（兩位官爺，一位耳聾）、
## 合法緝拿（PkSystem 的 force_pk 呼叫 lawful_hunt）、懸賞金（罰金從被懸賞者自己的錢扣＋玩家加碼池；系統不生錢）、
## 領賞、NPC 賞金獵人野外追捕、天師消殺氣、京城半仙消 PK值、死於守城官兵／賞金獵人／持照玩家 PK值 −1。
## 純規則在 BountyRules。_init 不加型別：單元測試可以傳假主機（同 PkSystem）。
##
## 存檔（§8.1；全部增量）：world.bounty = { board, board_s, pools, claims, paid_log }；
## 角色 ext.law = { license, license_s, hunt_cd_s }、counters.banxian_day。

const SVC_BOARD := "BOARD"
const SVC_LICENSE := "LICENSE"
const SVC_CLEANSE := "CLEANSE"
const WHAT_KILLING := "KILLING"
const WHAT_PK := "PK"
const HUNTER_WID := "law_hunter"
const TAG_LISTED := "懸賞"
const CH := Protocol.CH_SYSTEM
## 耳聾官爺輪流講的三句（模板 law_deaf_1..3）
const DEAF_LINES := 3
const DEFAULT_WARN_S := 3
const DEFAULT_PROTECT_XP := 500
## 合法緝拿的戰鬥 id 留多久（世界秒；PvP 正常幾分鐘內就結束；斷線打完的也夠）
const LAWFUL_KEEP_S := 7200.0

var host
## 測試與 balance_sim 可以改（預設 BountyRules.HUNTER_CHANCE_PCT）
var hunter_chance_pct := BountyRules.HUNTER_CHANCE_PCT
## 合法緝拿的戰鬥：bid -> { hunter, target, since_s }（不存檔：主機關閉時戰鬥 ABORTED，不結算）
var _lawful: Dictionary = {}
## NPC 賞金獵人的戰鬥：bid -> since_s（不存檔）
var _hunter_bids: Dictionary = {}
## 警告倒數中：peer -> { char_id, room, due_s, tier }（不存檔：斷線即取消）
var _hunts: Dictionary = {}
## 離線角色的摘要快取：char_id -> { identity, name, sect, pk, morality, xp }（上下線時更新；離線時 PK值 不會變）
var _offline: Dictionary = {}
var _offline_loaded := false
var _last_slot := -1
var _deaf_i := 0

func _init(p_host) -> void:
	host = p_host

# ======================================================================== 設定

func enabled() -> bool:
	return host.options.get("bounty_enabled", true) != false

func hunters_on() -> bool:
	return enabled() and host.options.get("bounty_hunters", true) != false

func protect_xp() -> int:
	return int(host.options.get("newbie_pk_protect_xp", DEFAULT_PROTECT_XP))

func shichen_len() -> float:
	return WorldClock.shichen_len(float(host.day_s()))

func today() -> int:
	return int(host.clock()["day"])

## world.bounty（缺的鍵補上；舊世界沒有這個鍵 → 建立）
func data() -> Dictionary:
	var w: Dictionary = host.ws.world
	var b: Variant = w.get("bounty")
	if not (b is Dictionary):
		b = {}
		w["bounty"] = b
	for k in ["pools", "claims", "paid_log"]:
		if not (b.get(k) is Dictionary):
			b[k] = {}
	if not (b.get("board") is Array):
		b["board"] = []
	if not b.has("board_s"):
		b["board_s"] = -1.0
	return b

# ======================================================================== 角色的 ext.law

static func law_ext(ch) -> Dictionary:
	var e: Dictionary = ch.ext
	var l: Variant = e.get("law")
	if not (l is Dictionary):
		l = {}
		e["law"] = l
	return l

static func has_license(ch) -> bool:
	if ch == null:
		return false
	var l: Variant = ch.ext.get("law")
	return l is Dictionary and bool((l as Dictionary).get("license", false))

## 執照有效性：PK值 > 0 → 自動失效（清掉並通知本人）。回傳是否仍有效
func check_license(s: Session) -> bool:
	if s == null or s.character == null or not has_license(s.character):
		return false
	if int(s.character.pk_value()) > 0:
		var l := law_ext(s.character)
		l["license"] = false
		l["license_s"] = 0.0
		host.tell(s, CH, Protocol.E_LAW_LICENSE_VOID, {})
		s.sheet_dirty = true
		return false
	return true

# ======================================================================== 名單（§2.2）

## 換時辰統計一次（主機啟動後第一個 tick 也統計一次）
func tick(_dt: float = 0.0) -> void:
	var c: Dictionary = host.clock()
	var slot := int(c["day"]) * 12 + int(c["shichen_idx"])
	if slot != _last_slot:
		_last_slot = slot
		refresh_board()
	elif not _offline_loaded and _offline_started:
		_load_offline()   # 分批讀離線角色檔；讀完重算一次名單
		if _offline_loaded:
			refresh_board()
	_resolve_hunts()
	_prune()

## 掃所有角色（在線用 session，離線用角色檔摘要）→ world.bounty.board。bounty_enabled 關 → 清空名單
func refresh_board() -> void:
	var d := data()
	var old: Dictionary = {}
	for r in d["board"]:
		if r is Dictionary:
			old[str(r.get("char_id", ""))] = r
	var rows: Array = []
	if enabled():
		var px := protect_xp()
		for e in _all_chars():
			if not BountyRules.listed(int(e["pk"]), int(e["morality"]), int(e["xp"]), px):
				continue
			var cid := str(e["char_id"])
			var prev: Dictionary = old.get(cid, {})
			rows.append({ "char_id": cid, "identity": str(e["identity"]), "name": str(e["name"]),
				"sect": str(e["sect"]), "pk": int(e["pk"]), "morality": int(e["morality"]),
				"fine": BountyRules.fine(int(e["pk"]), int(e["morality"])),
				"listed_s": float(prev.get("listed_s", host.now_s())) })
	rows.sort_custom(func(a, b): return float(a["listed_s"]) < float(b["listed_s"]) \
		or (float(a["listed_s"]) == float(b["listed_s"]) and str(a["char_id"]) < str(b["char_id"])))
	var changed := rows.size() != old.size()   # M3d 整合：名單沒變就不重送房間視圖（每時辰重建 NPC 按鈕會吃掉點擊）
	if not changed:
		for r in rows:
			var o: Dictionary = old.get(str(r["char_id"]), {})
			if o.is_empty() or int(o.get("pk", -1)) != int(r["pk"]) or int(o.get("morality", 0)) != int(r["morality"]) 					or str(o.get("name", "")) != str(r["name"]):
				changed = true
				break
	d["board"] = rows
	d["board_s"] = host.now_s()
	_prune_paid_log()
	if not changed:
		return
	# 名單變了 → 在線角色的角色表（law.listed）與房間標籤；剛上榜的人收到通知
	for s in host.sessions():
		if s.character != null:
			s.sheet_dirty = true
			s.view_dirty = true
			var cid2 := str(s.character.id)
			if not old.has(cid2) and not board_row(cid2).is_empty():
				host.tell(s, CH, "law_listed", {})

func board_row(char_id: String) -> Dictionary:
	for r in data()["board"]:
		if r is Dictionary and str(r.get("char_id", "")) == char_id:
			return r
	return {}

func is_listed(char_id: String) -> bool:
	return not board_row(char_id).is_empty()

## 名單上的人（依名字，大小寫不敏感）
func board_row_by_name(nm: String) -> Dictionary:
	var k := CharacterStore.name_key(nm)
	for r in data()["board"]:
		if r is Dictionary and CharacterStore.name_key(str(r.get("name", ""))) == k:
			return r
	return {}

## 全部角色的摘要：[{ char_id, identity, name, sect, pk, morality, xp }]（在線的取記憶體、離線的取快取／角色檔）
func _all_chars() -> Array:
	var out: Array = []
	var seen := {}
	for s in host.sessions():
		if s.character == null:
			continue
		var c = s.character
		seen[str(c.id)] = true
		out.append(_summary(c, str(s.identity)))
	_load_offline()
	var names: Dictionary = host.char_store.names() if host.get("char_store") != null else {}
	var live := {}
	for k in names:
		var e: Variant = names[k]
		if e is Dictionary:
			live[str(e.get("char_id", ""))] = str(e.get("identity", ""))
	for cid in _offline.keys():
		if not live.has(cid):
			_offline.erase(cid)   # 角色已刪除（M3D_PLAN 缺漏：沒有 char_delete 鉤子 → 這裡惰性清掉）
			continue
		if seen.has(cid):
			continue
		out.append(_offline[cid])
	return out

func _summary(c, identity: String) -> Dictionary:
	return { "char_id": str(c.id), "identity": identity if identity != "" else str(c.identity), "name": str(c.name),
		"sect": str(c.sect), "pk": int(_pk_of(c)), "morality": int(c.morality), "xp": int(c.combat_xp) }

## 離線角色的 PK值 照目前的規則算（pk_decay 關時不遞減）
func _pk_of(c) -> int:
	if "pk_decay_on" in c:
		c.pk_decay_on = bool(host.rules.get("pk_decay", true))
	return int(c.pk_value())

## 第一次統計時把離線角色檔讀進快取（之後靠上下線更新）。
## M3d 審查：原本開機後第一個 tick 一次讀完所有角色檔（角色多的世界會卡一下）→ 分批：每次最多 OFFLINE_LOAD_PER_STEP 個，
## tick 每次接著讀，讀完再重算一次名單（_offline_loaded 讀完才是 true）
const OFFLINE_LOAD_PER_STEP := 8
var _offline_queue: Array = []
var _offline_started := false

func _load_offline() -> void:
	if _offline_loaded or host.get("char_store") == null:
		return
	if not _offline_started:
		_offline_started = true
		var names: Dictionary = host.char_store.names()
		for k in names:
			var e: Variant = names[k]
			if e is Dictionary and str(e.get("char_id", "")) != "":
				_offline_queue.append({ "cid": str(e.get("char_id", "")), "identity": str(e.get("identity", "")) })
	var n := 0
	while not _offline_queue.is_empty() and n < OFFLINE_LOAD_PER_STEP:
		var q: Dictionary = _offline_queue.pop_front()
		var cid := str(q["cid"])
		if _offline.has(cid) or host.session_for_char(cid) != null:
			continue
		var c = host.char_store.load_char(str(q["identity"]), cid)
		n += 1
		if c != null:
			_offline[cid] = _summary(c, str(q["identity"]))
	if _offline_queue.is_empty():
		_offline_loaded = true

func on_login(s: Session) -> void:
	if s != null and s.character != null:
		_offline.erase(str(s.character.id))

func on_logout(s: Session) -> void:
	if s == null or s.character == null:
		return
	_hunts.erase(s.peer_id)
	_offline[str(s.character.id)] = _summary(s.character, str(s.identity))   # 記憶體裡現成的（分批讀檔時也先記上）

func on_char_deleted(char_id: String) -> void:
	_offline.erase(char_id)
	var d := data()
	var rows: Array = []
	for r in d["board"]:
		if r is Dictionary and str(r.get("char_id", "")) != char_id:
			rows.append(r)
	d["board"] = rows
	(d["pools"] as Dictionary).erase(char_id)
	# M3d 審查：刪掉的角色未領的賞金與領賞紀錄也清掉（不留在世界存檔裡）
	(d["claims"] as Dictionary).erase(char_id)
	var pl: Dictionary = d["paid_log"]
	for k in pl.keys():
		var parts := str(k).split("|")
		if parts.size() == 2 and (parts[0] == char_id or parts[1] == char_id):
			pl.erase(k)

## 領賞紀錄只用來擋「同一天」：不是今天的都丟掉（M3d 審查：以前只增不減）
func _prune_paid_log() -> void:
	var pl: Dictionary = data()["paid_log"]
	var t := today()
	for k in pl.keys():
		if int(pl[k]) != t:
			pl.erase(k)

# ======================================================================== 佈告欄（bounty_board）

## 佈告欄或官爺：送 bounty_board（ui）
func board(s: Session, npc_id: String) -> Dictionary:
	var r := _npc_any(s, npc_id, [SVC_BOARD, SVC_LICENSE])
	if r != "":
		return GameHost.fail(r if r != "no_service" else "not_board_npc")
	if _deaf(s, npc_id):
		return GameHost.fail("license_deaf")   # 耳聾的官爺什麼都聽錯（連「看名單」也是）
	host.tell(s, CH, Protocol.E_BOUNTY_BOARD, board_payload(s, npc_id), true)
	return GameHost.ok()

## { rows: [{ name, sect_name, pk, morality, amount, fine, pool, listed_s, listed_text }], refreshed_s, refreshed_text,
##   claims_total, licensed, enabled }
func board_payload(s: Session, npc_id := "") -> Dictionary:
	var d := data()
	var rows: Array = []
	if enabled():
		for r in d["board"]:
			if not (r is Dictionary):
				continue
			var pool := pool_of(str(r["char_id"]))
			rows.append({ "name": str(r["name"]), "sect_name": _sect_name(str(r.get("sect", ""))),
				"pk": int(r["pk"]), "morality": int(r["morality"]), "fine": int(r["fine"]), "pool": pool,
				"amount": int(r["fine"]) + pool, "listed_s": float(r["listed_s"]),
				"listed_text": _when_text(float(r["listed_s"])),
				# M3d 審查：自己那一列（介面把「加碼」灰掉：不能替自己加碼）
				"self": s != null and s.character != null and str(r["char_id"]) == str(s.character.id) })
	var ch = s.character if s != null else null
	return { "rows": rows, "refreshed_s": float(d["board_s"]), "refreshed_text": _when_text(float(d["board_s"])),
		"claims_total": claims_total(str(ch.id)) if ch != null else 0,
		"licensed": has_license(ch), "enabled": enabled(),
		"pool_min": BountyRules.POOL_ADD_MIN, "pool_cap": BountyRules.POOL_CAP, "license_fee": BountyRules.LICENSE_FEE,
		"npc": npc_id, "npc_service": SVC_LICENSE if SVC_LICENSE in host.npc_row(npc_id).get("services", []) else SVC_BOARD }

func _sect_name(sid: String) -> String:
	if sid == "":
		return "無門無派"
	return str(host.tables.get("sects", {}).get(sid, {}).get("name", sid))

## 世界時間 → 「第 3 日 午時」（佈告欄顯示用）
func _when_text(world_s: float) -> String:
	if world_s < 0.0:
		return ""
	var c := WorldClock.clock(world_s, float(host.day_s()))
	return "第 %d 日 %s時" % [int(c["day"]), str(c["shichen_name"])]

# ======================================================================== 執照（bounty_license）

func license(s: Session, npc_id: String) -> Dictionary:
	var r := _npc_any(s, npc_id, [SVC_LICENSE])
	if r != "":
		return GameHost.fail(r)
	if _deaf(s, npc_id):
		return GameHost.fail("license_deaf")
	var ch = s.character
	if has_license(ch) and check_license(s):
		host.tell(s, CH, Protocol.E_LAW_LICENSE_OK, { "npc_name": host.npc_name(npc_id), "fee": 0, "again": true })
		return GameHost.ok({ "already": true })
	var why := BountyRules.license_reason(int(ch.pk_value()), is_listed(str(ch.id)), int(ch.money))
	if why != "":
		return GameHost.fail(why)
	ch.money = int(ch.money) - BountyRules.LICENSE_FEE
	var l := law_ext(ch)
	l["license"] = true
	l["license_s"] = host.now_s()
	host.tell(s, CH, Protocol.E_LAW_LICENSE_OK, { "npc_name": host.npc_name(npc_id), "fee": BountyRules.LICENSE_FEE, "again": false })
	s.sheet_dirty = true
	return GameHost.ok()

## 耳聾官爺（列欄位 deaf: true）：一律聽錯，輪流講三句（law_deaf_1..3），不收錢
func _deaf(s: Session, npc_id: String) -> bool:
	if host.npc_row(npc_id).get("deaf", false) != true:
		return false
	_deaf_i = (_deaf_i % DEAF_LINES) + 1
	host.tell(s, Protocol.CH_SCENE, "law_deaf_%d" % _deaf_i, { "npc_name": host.npc_name(npc_id) })
	return true

# ======================================================================== 加碼（bounty_add）

func pool_of(char_id: String) -> int:
	var p: Variant = data()["pools"].get(char_id)
	return int((p as Dictionary).get("added", 0)) if p is Dictionary else 0

func add(s: Session, npc_id: String, target_name: String, money: int) -> Dictionary:
	var r := _npc_any(s, npc_id, [SVC_BOARD, SVC_LICENSE])
	if r != "":
		return GameHost.fail(r if r != "no_service" else "not_board_npc")
	if SVC_LICENSE in host.npc_row(npc_id).get("services", []) and _deaf(s, npc_id):
		return GameHost.fail("license_deaf")
	if not enabled():
		return GameHost.fail("bounty_off")
	var row := board_row_by_name(target_name)
	if row.is_empty():
		return GameHost.fail("bounty_not_listed")
	var ch = s.character
	if str(row["char_id"]) == str(ch.id):
		return GameHost.fail(Protocol.R_SELF_TARGET)
	if money < BountyRules.POOL_ADD_MIN:
		return GameHost.fail("bounty_pool_min")
	var tid := str(row["char_id"])
	if pool_of(tid) + money > BountyRules.POOL_CAP:
		return GameHost.fail("bounty_pool_cap")
	if int(ch.money) < money:
		return GameHost.fail("not_enough_money")
	ch.money = int(ch.money) - money
	var pools: Dictionary = data()["pools"]
	var p: Dictionary = pools.get(tid, {}) if pools.get(tid) is Dictionary else {}
	p["added"] = int(p.get("added", 0)) + money
	var con: Dictionary = p.get("contributors", {}) if p.get("contributors") is Dictionary else {}
	con[str(ch.id)] = int(con.get(str(ch.id), 0)) + money
	p["contributors"] = con
	pools[tid] = p
	host.tell(s, CH, "law_pool_added", { "target_name": str(row["name"]), "money": money, "pool": int(p["added"]), "amount": int(p["added"]) })
	host.tell(s, CH, Protocol.E_BOUNTY_BOARD, board_payload(s, npc_id), true)
	s.sheet_dirty = true
	return GameHost.ok({ "pool": int(p["added"]) })

# ======================================================================== 領賞（bounty_claim）

func claims_of(char_id: String) -> Array:
	var c: Variant = data()["claims"].get(char_id)
	return c if c is Array else []

func claims_total(char_id: String) -> int:
	var t := 0
	for e in claims_of(char_id):
		if e is Dictionary:
			t += int(e.get("amount", 0))
	return t

func claim(s: Session, npc_id: String) -> Dictionary:
	var r := _npc_any(s, npc_id, [SVC_LICENSE])
	if r != "":
		return GameHost.fail(r)
	if _deaf(s, npc_id):
		return GameHost.fail("license_deaf")
	if not check_license(s):
		return GameHost.fail("license_none")
	var ch = s.character
	var list := claims_of(str(ch.id))
	if claims_total(str(ch.id)) <= 0:
		return GameHost.fail("bounty_no_claims")
	var room := maxi(0, Character.MONEY_CAP - int(ch.money))
	if room <= 0:
		return GameHost.fail(Protocol.R_MONEY_CAP)
	var paid := 0
	var left: Array = []
	for e in list:
		if not (e is Dictionary):
			continue
		var amt := int(e.get("amount", 0))
		var take := mini(amt, room - paid)
		paid += take
		if amt - take > 0:
			var rest := (e as Dictionary).duplicate()
			rest["amount"] = amt - take
			left.append(rest)
	ch.add_money(paid)
	var claims: Dictionary = data()["claims"]
	if left.is_empty():
		claims.erase(str(ch.id))
	else:
		claims[str(ch.id)] = left   # 身上放不下的留著（money_cap 照舊）
	host.tell(s, CH, Protocol.E_LAW_BOUNTY_PAID, { "amount": paid, "npc_name": host.npc_name(npc_id) })
	s.sheet_dirty = true
	return GameHost.ok({ "amount": paid })

# ======================================================================== 合法緝拿（PkSystem.force_pk → 這裡）

## force_pk 的其他檢查都過了之後：有效執照＋目標在名單上 → 合法（R3）
func lawful_hunt(s: Session, target_ch) -> bool:
	if not enabled() or s == null or s.character == null or target_ch == null:
		return false
	if not has_license(s.character):
		return false
	var lic := check_license(s)
	return BountyRules.lawful(lic, int(s.character.pk_value()), listed_live(target_ch))

## 名單上、而且照目前的 PK值／善惡／實戰仍然夠格（M3d 審查：名單是每時辰的快照；
## 緝拿或半仙消過 PK值 之後快照會過期 → 合法緝拿與 NPC 獵人一律以這個為準）
func listed_live(ch) -> bool:
	if ch == null or not is_listed(str(ch.id)):
		return false
	return BountyRules.listed(int(_pk_of(ch)), int(ch.morality), int(ch.combat_xp), protect_xp())

## PK值 變了之後重新判定：不再夠格 → 立刻從名單拿掉（不等下個時辰）；還在 → 更新 PK／罰金欄。回傳是否仍在名單上
func recheck_listing(ch) -> bool:
	if ch == null:
		return false
	var cid := str(ch.id)
	var row := board_row(cid)
	if row.is_empty():
		return false
	var pk := int(_pk_of(ch))
	if enabled() and BountyRules.listed(pk, int(ch.morality), int(ch.combat_xp), protect_xp()):
		row["pk"] = pk
		row["morality"] = int(ch.morality)
		row["fine"] = BountyRules.fine(pk, int(ch.morality))
		return true
	var d := data()
	var rows: Array = []
	for r in d["board"]:
		if r is Dictionary and str(r.get("char_id", "")) != cid:
			rows.append(r)
	d["board"] = rows
	var s: Session = host.session_for_char(cid)
	if s != null:
		s.sheet_dirty = true
		s.view_dirty = true
		if host.get("regions") != null:
			host.regions.mark_room_dirty(s.room_id())
	return false

func note_lawful(bid: int, s: Session, t: Session) -> void:
	if bid == 0 or s == null or t == null:
		return
	_lawful[bid] = { "hunter": str(s.character.id), "target": str(t.character.id), "since_s": host.now_s() }

func is_lawful_bid(bid: int) -> bool:
	return _lawful.has(bid)

func forget_bid(bid: int) -> void:
	_lawful.erase(bid)

## PvP 結束（PkSystem.on_pvp_end 開頭，經 GameHost.m3d_pvp_end）：合法緝拿成立 → 目標 PK值 −1、傳聞、懸賞記到獵人名下
func on_pvp_end(summary: Dictionary) -> void:
	var bid := int(summary.get("bid", 0))
	if not _lawful.has(bid):
		return
	var rec: Dictionary = _lawful[bid]
	var units: Array = summary.get("units", [])
	var sides := {}
	for u in units:
		if u is Dictionary:
			sides[str(u.get("char_id", ""))] = int(u.get("side", 0))
	for v in units:
		if not (v is Dictionary) or not bool(v.get("died", false)):
			continue
		var victim_id := str(v.get("char_id", ""))
		var killer_id := str(v.get("killed_by_char", ""))
		# 只有出手的持照者（side 0）殺死名單上的目標才算緝拿；目標反殺獵人照 PkSystem 的自衛規則
		if killer_id == "" or killer_id == victim_id or int(sides.get(killer_id, 1)) != 0 or int(sides.get(victim_id, 0)) == 0:
			continue
		_caught(killer_id, victim_id, str(summary.get("room", "")))

func _caught(hunter_id: String, victim_id: String, room: String) -> void:
	var row := board_row(victim_id)
	var hs: Session = host.session_for_char(hunter_id)
	var victim_s: Session = host.session_for_char(victim_id)
	var victim = victim_s.character if victim_s != null else _load_any(victim_id)
	var hunter_name: String = str(host.pvp_char_name(hunter_id))
	var victim_name := str(victim.name) if victim != null else str(row.get("name", ""))
	# 傳聞（取代 pk_kill 的全服廣播；R3）
	var rumor = host.get("rumor")
	if rumor != null and (rumor as Object).has_method("post"):
		rumor.post("PK", "rmr_law_caught", { "hunter": hunter_name, "target": victim_name, "room_name": host.room_name(room),
			"name": hunter_name, "def_name": victim_name, "_force": true })
	if victim == null:
		return
	# 懸賞金：先算罰金（PK值 −1 之前）
	var pre_pk := int(victim.pk_value())
	var bounty_ok := not row.is_empty() and enabled()
	var why := ""
	if bounty_ok:
		why = _friend_reason(hunter_id, victim_id, hs, victim_s)
	if not bounty_ok:
		_save(victim, victim_s)
		return
	if why != "":
		# M3d 審查：同隊／同組織／同日重複 → 不發賞金，也不減 PK值（否則朋友互殺就能洗掉 PK值，繞過半仙）
		if hs != null:
			host.tell(hs, CH, why, { "target_name": victim_name })
		_save(victim, victim_s)
		return
	var fine := BountyRules.fine(pre_pk, int(victim.morality))
	var bank: Dictionary = BankStore.bank_of(victim)
	var got := BountyRules.collect(fine, int(victim.money), int(bank.get("money", 0)))
	victim.money = int(victim.money) - int(got["from_money"])
	bank["money"] = int(bank.get("money", 0)) - int(got["from_bank"])
	var pools: Dictionary = data()["pools"]
	var added := pool_of(victim_id)
	pools.erase(victim_id)
	var amount := int(got["total"]) + added
	# 被持照玩家緝殺 PK值 −1（R4；【設計提案】研究只證實死於守衛／特定 NPC −1）：只有真的發了賞金（> 0 兩）、而且是名單上的目標才減。
	# M3d 審查第三輪：身上與錢莊都沒錢、也沒有加碼 → 賞金 0 兩 → 不減（不然幾個朋友輪流緝殺就能免費洗 PK值，繞過半仙）
	if amount > 0:
		victim.add_pk(-1)
		if victim_s != null:
			victim_s.sheet_dirty = true
		recheck_listing(victim)
	_save(victim, victim_s)
	data()["paid_log"]["%s|%s" % [hunter_id, victim_id]] = today()
	var claims: Dictionary = data()["claims"]
	var list: Array = claims.get(hunter_id, []) if claims.get(hunter_id) is Array else []
	list.append({ "target_name": victim_name, "amount": amount, "s": host.now_s() })
	claims[hunter_id] = list
	if hs != null:
		host.tell(hs, CH, Protocol.E_LAW_BOUNTY_EARNED, { "target_name": victim_name, "amount": amount })
		hs.sheet_dirty = true
	if victim_s != null and int(got["total"]) > 0:
		host.tell(victim_s, CH, "law_fined", { "amount": int(got["total"]) })

## 防刷（R4）：同隊、同組織 → law_no_bounty_friend；同一獵人對同一目標同一天已領過 → law_no_bounty_daily
func _friend_reason(hunter_id: String, victim_id: String, hs: Session, vs: Session) -> String:
	if hs != null and vs != null:
		var pa := str(host.party_id_of(hs)) if host.has_method("party_id_of") else ""
		if pa != "" and pa == str(host.party_id_of(vs)):
			return "law_no_bounty_friend"
	var orgs = host.get("orgs")
	if orgs != null and (orgs as Object).has_method("org_id_of"):
		var oa := str(orgs.org_id_of(hunter_id))
		if oa != "" and oa == str(orgs.org_id_of(victim_id)):
			return "law_no_bounty_friend"
	if int(data()["paid_log"].get("%s|%s" % [hunter_id, victim_id], -1)) == today():
		return "law_no_bounty_daily"
	return ""

## 在線的取記憶體、離線的讀角色檔
func _load_any(char_id: String):
	var s: Session = host.session_for_char(char_id)
	if s != null:
		return s.character
	var names: Variant = host.ws.world.get("char_names", {})
	if not (names is Dictionary) or host.get("char_store") == null:
		return null
	for k in names:
		var e: Variant = names[k]
		if e is Dictionary and str(e.get("char_id", "")) == char_id:
			var c = host.char_store.load_char(str(e.get("identity", "")), char_id)
			# M3d 審查第三輪：讀檔的角色 pk_decay_on 是預設 true → 照目前規則設（pk_decay 關時不遞減）
			if c != null and "pk_decay_on" in c:
				c.pk_decay_on = bool(host.rules.get("pk_decay", true))
			return c
	return null

func _save(c, s: Session) -> void:
	if c == null:
		return
	host.save_char(c)
	if s == null and (_offline_loaded or _offline.has(str(c.id))):
		_offline[str(c.id)] = _summary(c, str(c.identity))

# ======================================================================== NPC 賞金獵人（§2.5）

## 走進房間（GameHost.m3d_enter_room）：名單上的人在野外擲 HUNTER_CHANCE_PCT → 警告、倒數、追擊戰
func on_enter_room(s: Session, _from: String, to: String) -> void:
	if not hunters_on() or s == null or s.character == null or s.battle_id != 0:
		return
	var ch = s.character
	if ch.is_jailed() or _hunts.has(s.peer_id):
		return
	if not listed_live(ch) or not _wild_room(to):
		return
	var l := law_ext(ch)
	var now: float = host.now_s()
	if float(l.get("hunt_cd_s", 0.0)) > now:
		return
	if host.rng.randi_range(1, 100) > hunter_chance_pct:
		return
	var tier := BountyRules.hunter_tier(int(ch.combat_xp))
	l["hunt_cd_s"] = now + BountyRules.HUNTER_COOLDOWN_SHICHEN * shichen_len()
	var w := maxi(0, int(host.options.get("villain_warn_s", DEFAULT_WARN_S)))
	var mid := BountyRules.hunter_monster(tier)
	_hunts[s.peer_id] = { "char_id": str(ch.id), "room": to, "due_s": now + host.world_span(float(w)), "tier": tier }
	var nm: String = str(host.monster_name(mid))
	host.tell(s, Protocol.CH_BATTLE, "law_hunter_coming", { "npc_name": nm, "countdown_s": w, "n": w })
	host.tell(s, CH, Protocol.E_LAW_HUNTER_WARN, { "wid": HUNTER_WID, "npc_name": nm, "warn_s": w }, true)
	if w <= 0:
		_resolve_hunts()

func _wild_room(room_id: String) -> bool:
	var room: Dictionary = host.index.room(room_id)
	if room.is_empty() or bool(room.get("safe", false)):
		return false
	var region: String = host.index.region_of(room_id)
	return str(host.tables.get("regions", {}).get(region, {}).get("type", "")) == "WILD"

## 倒數：離開房間＝逃掉；倒數結束還在 → 開追擊戰（不能逃；烙跑鞋由 WP-COMBAT 例外）
func _resolve_hunts() -> void:
	if _hunts.is_empty():
		return
	var now: float = host.now_s()
	for peer in _hunts.keys():
		var h: Dictionary = _hunts[peer]
		var s: Session = host.session_for_peer(int(peer))
		if s == null or s.character == null or str(s.character.id) != str(h["char_id"]):
			_hunts.erase(peer)
			continue
		if s.room_id() != str(h["room"]):
			_hunts.erase(peer)
			host.tell(s, Protocol.CH_BATTLE, "law_hunter_escaped",
				{ "npc_name": host.monster_name(BountyRules.hunter_monster(int(h["tier"]))) })
			continue
		if s.battle_id != 0 or s.character.is_jailed():
			_hunts.erase(peer)
			continue
		if now >= float(h["due_s"]):
			_hunts.erase(peer)
			start_hunt(s, int(h["tier"]))

## 開賞金獵人的追擊戰（測試也直接呼叫）；回 bid
func start_hunt(s: Session, tier: int) -> int:
	var mid := BountyRules.hunter_monster(tier)
	if not host.tables.get("monsters", {}).has(mid) or host.battles == null:
		return 0
	host.tell(s, Protocol.CH_BATTLE, "law_hunter_attack", { "npc_name": host.monster_name(mid) })
	# M3d 審查：獵人的數值依目標實戰（各階底端不再必死、20 萬以上仍有威脅；BountyRules.apply_hunter_xp）
	var opts := { "no_flee": true, "pull_party": true, "pull_min_xp": protect_xp(), "law_hunter": true,
		"hunter_xp": int(s.character.combat_xp) }
	var bid := int(host.battles.start_ex(s, [mid], "CHASE", opts))
	if bid != 0:
		_hunter_bids[bid] = { "since_s": host.now_s(), "target": str(s.character.id) }
	return bid

func is_hunter_bid(bid: int) -> bool:
	return _hunter_bids.has(bid)

## 戰鬥結算（BattleSystem._settle_player 結尾，經 GameHost.m3d_battle_settled）：
## 死於賞金獵人（CHASE＋law_hunter）或守城官兵（GUARD）→ PK值 −1【已證實 xinshou/21：守衛或特定 NPC】
func on_battle_settled(s: Session, ch, summary: Dictionary) -> void:
	if ch == null:
		return
	var kind := str(summary.get("kind", ""))
	var bid := int(summary.get("bid", 0))
	var hunter := kind == "CHASE" and _hunter_bids.has(bid)
	if not hunter and kind != "GUARD":
		return
	if bool(summary.get("died", false)):
		# M3d 審查：獵人追擊戰只有被追的那個人（名單上的目標）−1；被拉進來的隊友不算
		if hunter and str((_hunter_bids.get(bid, {}) as Dictionary).get("target", str(ch.id))) != str(ch.id):
			return
		var before := int(ch.pk_value())
		ch.add_pk(-1)
		recheck_listing(ch)
		if s != null:
			s.sheet_dirty = true
			if before > 0:
				host.tell(s, CH, "law_pk_down", { "pk": int(ch.pk_value()) })
		if hunter:
			var rumor = host.get("rumor")
			if rumor != null and (rumor as Object).has_method("post"):
				rumor.post("PK", "rmr_law_hunted", { "name": str(ch.name), "room_name": host.room_name(str(summary.get("room", ""))) })
		host.save_char(ch)
	elif hunter and str(summary.get("result", summary.get("per", ""))) == "VICTORY" and s != null:
		host.tell(s, Protocol.CH_BATTLE, "law_hunter_beaten", {})

## 過期的合法緝拿紀錄、已結束的獵人戰
func _prune() -> void:
	var now: float = host.now_s()
	for bid in _lawful.keys():
		if now - float(_lawful[bid].get("since_s", now)) > LAWFUL_KEEP_S:
			_lawful.erase(bid)
	if host.battles != null and "active" in host.battles:
		for bid in _hunter_bids.keys():
			if not host.battles.active.has(bid):
				_hunter_bids.erase(bid)

# ======================================================================== 天師與半仙（cleanse）

func cleanse(s: Session, npc_id: String, what: String, times: int) -> Dictionary:
	var r := _npc_any(s, npc_id, [SVC_CLEANSE])
	if r != "":
		return GameHost.fail(r if r != "no_service" else "not_cleanse_npc")
	var row: Dictionary = host.npc_row(npc_id)
	if str(row.get("cleanse", "")) != what:
		return GameHost.fail("not_cleanse_npc")
	var ch = s.character
	if what == WHAT_KILLING:
		if int(ch.killing_intent) < BountyRules.TIANSHI_PER_TIME:
			return GameHost.fail("cleanse_nothing")
		var t := BountyRules.tianshi(int(ch.killing_intent), clampi(times, 1, BountyRules.TIANSHI_MAX_TIMES), int(ch.money))
		if int(t["times"]) <= 0:
			return GameHost.fail("not_enough_money")
		ch.money = int(ch.money) - int(t["cost"])
		ch.add_killing_intent(-int(t["drop"]))
		host.tell(s, CH, Protocol.E_LAW_CLEANSED, { "what": what, "times": int(t["times"]), "cost": int(t["cost"]),
			"killing_intent": int(ch.killing_intent), "value": int(ch.killing_intent), "pk": int(ch.pk_value()), "drop": int(t["drop"]),
			"npc_name": host.npc_name(npc_id) })
		s.sheet_dirty = true
		return GameHost.ok({ "times": int(t["times"]), "cost": int(t["cost"]) })
	# 半仙：每遊戲日 1 點
	var used := 1 if int(ch.counters.get("banxian_day", -1)) == today() else 0
	var b := BountyRules.banxian(int(ch.pk_value()), int(ch.money), used)
	if not bool(b["ok"]):
		return GameHost.fail(str(b["reason"]))
	ch.money = int(ch.money) - int(b["cost"])
	ch.add_pk(-1)
	ch.counters["banxian_day"] = today()
	recheck_listing(ch)
	host.tell(s, CH, Protocol.E_LAW_CLEANSED, { "what": what, "times": 1, "cost": int(b["cost"]),
		"killing_intent": int(ch.killing_intent), "value": int(ch.killing_intent), "pk": int(ch.pk_value()), "drop": 1, "npc_name": host.npc_name(npc_id) })
	s.sheet_dirty = true
	host.regions.mark_room_dirty(s.room_id())
	return GameHost.ok({ "times": 1, "cost": int(b["cost"]) })

# ======================================================================== 快照與條件

## 房間玩家列：名單上的人頭上標「懸賞」
func player_tags(_viewer: Session, o: Session) -> Dictionary:
	if o == null or o.character == null or not enabled() or not is_listed(str(o.character.id)):
		return { "tags": [] }
	return { "tags": [TAG_LISTED], "bounty": true }

## 角色表 law：{ licensed, listed, claims }
func sheet_fields(s: Session) -> Dictionary:
	if s == null or s.character == null:
		return {}
	var cid := str(s.character.id)
	return { "law": { "licensed": has_license(s.character), "listed": enabled() and is_listed(cid), "claims": claims_total(cid) } }

## requirements 的 ctx（SectSystem.req_ctx 合併）
func req_ctx(s: Session) -> Dictionary:
	if s == null or s.character == null:
		return {}
	return { "bounty_listed": enabled() and is_listed(str(s.character.id)), "has_license": has_license(s.character) }

# ======================================================================== 輔助

## NPC 在場且有其中一種服務：not_here → no_service → closed_night
func _npc_any(s: Session, npc_id: String, services: Array) -> String:
	if s == null or s.character == null:
		return "no_character"
	var r: String = host.npc_here(s, npc_id)
	if r != "":
		return r
	var row: Dictionary = host.npc_row(npc_id)
	var svcs: Array = row.get("services", [])
	var any := false
	for sv in services:
		if sv in svcs:
			any = true
	if not any:
		return "no_service"
	if host.npc_closed(row):
		return "closed_night"
	return ""
