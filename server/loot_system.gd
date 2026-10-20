class_name LootSystem
extends RefCounted
## 裝備與打寶（M3C_PLAN §6；WP-LOOT）：掉落表的戰鬥 ctx、稀有掉落【江湖傳聞】、神兵全服登記與 PvP 轉移、秘笈研讀。
## GameHost 以路徑 load()（N4）；所有呼叫點用 host.m2_call(host.get("loot"), …)。
##
## 世界存檔：world.divine = { item_id: char_id }（惰性建立）；world.divine_lock = { 掉落表 id: until_s }（神兵全服鎖，M3c 第三輪審查）。
## 角色存檔：ext.loot = { "force": [item_id] }（除錯用的強制掉落，用掉一件刪一件）。
## 【設計提案・非原作】：秘笈（2002-08 系統）、稀有掉落廣播（2001–2003 官方沒有）、神兵掉落（原作來自 2002 武林大會）。

const EXT_KEY := "loot"
const WORLD_DIVINE := "divine"
const WORLD_DIVINE_LOCK := "divine_lock"
const RUMOR_KIND := "DEED"
const BROADCAST_MIN := "TREASURE"     # 珍品以上發【江湖傳聞】（O18）
const DEFAULT_DROP_PCT := 100
const DROP_PCT_RANGE := [10, 300]     # 伺服器選項 loot_drop_pct（§6.6）

## 事件與模板 id（值＝Protocol 常數；Day-0 還沒落地時用同樣的字面值）
const E_RARE_DROP := "lt_rare_drop"
const E_DIVINE_TRANSFER := "lt_divine_transfer"
const E_MANUAL_READ := "lt_manual_read"
const RMR_RARE_DROP := "lt_rmr_rare_drop"
const RMR_DIVINE_DROP := "lt_rmr_divine_drop"
const RMR_DIVINE_TRANSFER := "lt_rmr_divine_transfer"

var host   # GameHost（不寫型別：測試用的假主機也能用）
## 本場戰鬥的 ctx（reward_ctx 建立；on_settle 依角色找回，清掉真的用掉的強制掉落）：char_id -> ctx
var _pending: Dictionary = {}

func _init(p_host) -> void:
	host = p_host

# ======================================================================== 規則與選項

func rules() -> Dictionary:
	var r: Variant = host.rules
	return r if r is Dictionary else {}

func manuals_on() -> bool:
	return rules().get("manuals", true) != false

func broadcast_on() -> bool:
	return rules().get("loot_broadcast", true) != false

func divine_source() -> String:
	return str(rules().get("divine_source", "BOSS_DROP"))

func drop_pct() -> int:
	var o: Variant = host.options
	var v := int((o as Dictionary).get("loot_drop_pct", DEFAULT_DROP_PCT)) if o is Dictionary else DEFAULT_DROP_PCT
	return clampi(v, DROP_PCT_RANGE[0], DROP_PCT_RANGE[1])

func item_row(item_id: String) -> Dictionary:
	return host.tables.get("items", {}).get(item_id, {})

func is_divine(item_id: String) -> bool:
	return bool(item_row(item_id).get("divine", false))

func rarity(item_id: String) -> String:
	return BattleRewards.rarity_of(host.tables, item_id)

# ======================================================================== 戰鬥 ctx（§6.6、§11.3 Day-0）

## 給 BattleRewards.compute 的 ctx：{ rules, blocked, force, drop_pct }。一場戰鬥一個 ctx。
## 有神兵群組的掉落表才校正登記（持有者不存在或身上沒有 → 釋放），其他戰鬥直接用登記值（不讀角色檔）。
func reward_ctx(entry: Dictionary) -> Dictionary:
	var r := rules()
	var ctx := {
		"rules": { "divine_source": str(r.get("divine_source", "BOSS_DROP")), "manuals": manuals_on(),
			"later_loot": r.get("later_loot", true) != false },
		"blocked": [], "force": [], "drop_pct": drop_pct(), "locked": {},
	}
	if _battle_has_divine_group(entry):
		validate_registry()
	ctx["blocked"] = divine_registry().keys()
	ctx["divine_locked"] = divine_locked_tables()
	var chars: Variant = entry.get("chars", {})
	if chars is Dictionary:
		for peer in chars:
			var ch = chars[peer]
			if ch == null:
				continue
			for iid in force_list(ch):
				if not (ctx["force"] as Array).has(iid):
					(ctx["force"] as Array).append(iid)
			var lk := locked_tables(ch)
			if not lk.is_empty():
				(ctx["locked"] as Dictionary)[str(ch.id)] = lk
			_pending[str(ch.id)] = ctx
	return ctx

func _battle_has_divine_group(entry: Dictionary) -> bool:
	var b = entry.get("battle")
	if b == null:
		return false
	var mt: Dictionary = host.tables.get("monsters", {})
	var lts: Dictionary = host.tables.get("loot_tables", {})
	for u in b.units:
		if u.is_player():
			continue
		var mid := str(u.spec.get("monster_row", u.spec.get("ref", "")))
		var lt: Dictionary = lts.get(str(mt.get(mid, {}).get("loot_table", "")), {})
		for g in lt.get("groups", []):
			if g is Dictionary and bool(g.get("divine", false)):
				return true
	return false

# ======================================================================== 結算（§6.7）

## BattleSystem._settle_player 發完獎勵物品後呼叫：items = close.rewards.items（{ id, name, n, rarity }，只含真的放進背包的）。
## 珍品以上 → self lt_rare_drop＋【江湖傳聞】lt_rmr_rare_drop（規則 loot_broadcast）；神兵 → 登記持有者＋lt_rmr_divine_drop。
func on_settle(s, ch, items: Array, monster_ids: Array, room_id: String) -> void:
	if ch == null:
		return
	var ctx: Variant = _pending.get(str(ch.id), null)
	_pending.erase(str(ch.id))
	if ctx is Dictionary:
		var used: Variant = (ctx as Dictionary).get("used_force", [])
		if used is Array:
			for iid in used:
				_unforce(ch, str(iid))
		# M3c 第三輪審查（神兵全服鎖）：這場真的擲了神兵群組 → 那張表的神兵群組全服鎖 lockout_shichen 個時辰
		var dv_rolled: Variant = (ctx as Dictionary).get("divine_rolled", [])
		if dv_rolled is Array:
			for lt_id in dv_rolled:
				_lock_divine(str(lt_id))
		# M3c 審查（頭目鎖）：這場真的擲了有 lockout_shichen 的掉落表 → 這個角色鎖到那時
		var rolled: Variant = (ctx as Dictionary).get("lockout_rolled", [])
		if rolled is Array:
			for pr in rolled:
				if pr is Array and (pr as Array).size() >= 2 and str(pr[0]) == str(ch.id):
					_lock(ch, str(pr[1]))
	var monster_name := _monster_name_for(monster_ids)
	for it in items:
		if not (it is Dictionary):
			continue
		var iid := str(it.get("id", ""))
		var rar := str(it.get("rarity", rarity(iid)))
		if is_divine(iid):
			divine_registry()[iid] = str(ch.id)
			_save_world()
		if BattleRewards.rarity_rank(rar) < BattleRewards.rarity_rank(BROADCAST_MIN):
			continue
		# 傳聞參數照 §6.7 綁定：{ name, item, monster, room }；本人事件另帶 item_name、label（稀有度名）
		var p := { "name": str(ch.name), "item": host.item_name(iid), "monster": monster_name,
			"room": host.room_name(room_id) }
		if s != null:
			var sp := p.duplicate()
			sp["item_name"] = host.item_name(iid)
			sp["rarity"] = rar
			sp["label"] = rarity_label(rar)
			host.tell(s, Protocol.CH_SYSTEM, E_RARE_DROP, sp)
		if broadcast_on():
			_rumor(RMR_DIVINE_DROP if rar == "DIVINE" else RMR_RARE_DROP, p)

## 這件戰利品會由 on_settle 另外送本人 lt_rare_drop（珍品以上）→ 戰鬥結算不再送一般的 item_gain（M3c 第二輪審查：
## 訊息列同一件寶物出現兩行「你得到精鋼戒 ×1。」「你得到了精鋼戒！（珍品）」）
func announces(item_id: String) -> bool:
	return BattleRewards.rarity_rank(rarity(item_id)) >= BattleRewards.rarity_rank(BROADCAST_MIN)

## 稀有度中文名（server 不依賴 ui/ 的 LootUi；與 LootUi.NAMES 相同）
const RARITY_NAMES := { "COMMON": "凡品", "FINE": "良品", "RARE": "精品", "TREASURE": "珍品", "DIVINE": "神兵" }

static func rarity_label(r: String) -> String:
	return str(RARITY_NAMES.get(r, "凡品"))

func _monster_name_for(monster_ids: Array) -> String:
	# 最稀有的那隻（有 loot_table 的優先），不然第一隻
	var best := ""
	for m in monster_ids:
		var mid := str(m)
		if best == "":
			best = mid
		if str(host.tables.get("monsters", {}).get(mid, {}).get("loot_table", "")) != "":
			best = mid
			break
	return host.monster_name(best) if best != "" else ""

func _rumor(key: String, p: Dictionary) -> bool:
	var rumor = host.get("rumor")
	if rumor == null or not rumor.has_method("post"):
		return false
	var params := p.duplicate()
	params.erase("rarity")
	params["_force"] = true   # 稀有掉落本來就少；不讓一般傳聞的節流把它吃掉（去重照舊）
	return bool(host.m2_call(rumor, "post", [RUMOR_KIND, key, params], false))

# ======================================================================== 神兵（§6.5）

func divine_registry() -> Dictionary:
	var w: Dictionary = host.ws.world
	if not (w.get(WORLD_DIVINE) is Dictionary):
		w[WORLD_DIVINE] = {}
	return w[WORLD_DIVINE]

## 這個角色身上（背包或裝備）有神兵（M3c 第三輪審查：持有神兵就沒有新手保護，PkSystem.newbie_protected）
func holds_divine(ch) -> bool:
	if ch == null or ch.inventory == null:
		return false
	for it in ch.inventory.items:
		if it is Dictionary and is_divine(str(it.get("id", ""))):
			return true
	return false

func holder_of(item_id: String) -> String:
	return str(divine_registry().get(item_id, ""))

## 惰性校正：登記的持有者角色不存在或身上沒有該物品 → 釋放登記
func validate_registry() -> void:
	var reg := divine_registry()
	for iid in reg.keys():
		var ch = char_any(str(reg[iid]))
		if ch == null or ch.inventory.count(str(iid)) <= 0:
			reg.erase(iid)

## M3c 審查：角色刪除（intents_char.char_delete）→ 釋放他持有的神兵登記（神兵可以再掉給別人）。
## 之後用舊護照還原這個角色時，passport_restore 會呼叫 on_char_restored 把別人已經持有的神兵拿掉
func on_char_deleted(char_id: String) -> void:
	var reg := divine_registry()
	var changed := false
	for iid in reg.keys():
		if str(reg[iid]) == char_id:
			reg.erase(iid)
			changed = true
	if changed:
		_save_world()

## 護照還原（寫檔前）：身上每一把神兵——登記在別人名下 → 拿掉（全服唯一）；沒有人登記 → 登記給他。回傳拿掉的物品 id
func on_char_restored(ch) -> Array:
	var removed: Array = []
	if ch == null:
		return removed
	var reg := divine_registry()
	var changed := false
	for it in ch.inventory.items.duplicate():
		var iid := str(it.get("id", ""))
		if not is_divine(iid):
			continue
		var holder := str(reg.get(iid, ""))
		if holder != "" and holder != str(ch.id):
			ch.inventory.remove(str(it.get("uid", "")), int(it.get("n", 1)))   # 已裝備的會先卸下
			removed.append(iid)
		elif holder == "":
			reg[iid] = str(ch.id)
			changed = true
	if changed:
		_save_world()
	return removed

## 線上找不到就從角色檔讀（world.char_names）
func char_any(char_id: String):
	if char_id == "":
		return null
	var o = host.session_for_char(char_id)
	if o != null:
		return o.character
	var names: Variant = host.ws.world.get("char_names", {})
	if not (names is Dictionary) or host.char_store == null:
		return null
	for k in names:
		var e: Variant = names[k]
		if e is Dictionary and str(e.get("char_id", "")) == char_id:
			return host.char_store.load_char(str(e.get("identity", "")), char_id)
	return null

## PkSystem.on_pvp_end 對每個死於玩家的單位呼叫（叫戰、強制、捉拿都算；xinshou/11「不管是以何種方式」）。
## 受害者身上（含已裝備）的神兵全部移給殺手（無視負重；已裝備的先卸下）；殺手離線或不存在 → 留在受害者身上。
func on_pvp_kill(killer_char_id: String, victim_char_id: String, summary: Dictionary) -> void:
	if killer_char_id == "" or killer_char_id == victim_char_id:
		return
	var ks = host.session_for_char(killer_char_id)
	if ks == null or ks.character == null:
		return
	var killer = ks.character
	var victim = char_any(victim_char_id)
	if victim == null:
		return
	var moved: Array = []
	for it in victim.inventory.items.duplicate():
		var iid := str(it.get("id", ""))
		if not is_divine(iid):
			continue
		var n := int(it.get("n", 1))
		var lots: Array = (it.get("lots", []) as Array).duplicate(true) if it.get("lots") is Array else []
		victim.inventory.remove(str(it.get("uid", "")), n)   # 已裝備的會先卸下
		var g: Dictionary = killer.inventory.add_lots(iid, lots if not lots.is_empty() else [{ "born_s": host.now_s(), "n": n }],
			host.tables, -1, host.make_uid_callable())
		if not g.get("ok", false):
			# 殺手背包滿（300 件）：放回受害者身上（不會遺失）
			victim.inventory.add_lots(iid, [{ "born_s": host.now_s(), "n": n }], host.tables, -1, host.make_uid_callable())
			continue
		divine_registry()[iid] = str(killer.id)
		moved.append(iid)
	if moved.is_empty():
		return
	var vs = host.session_for_char(victim_char_id)
	var room := str(summary.get("room", ""))
	for iid in moved:
		var p := { "atk_name": str(killer.name), "def_name": str(victim.name), "item_name": host.item_name(iid),
			"room_name": host.room_name(room), "atk_peer": ks.peer_id, "def_peer": vs.peer_id if vs != null else 0 }
		host.ws.queue_event(ks.peer_id, Protocol.CH_SYSTEM, E_DIVINE_TRANSFER, p.duplicate())
		if vs != null:
			host.ws.queue_event(vs.peer_id, Protocol.CH_SYSTEM, E_DIVINE_TRANSFER, p.duplicate())
		if broadcast_on():
			_rumor(RMR_DIVINE_TRANSFER, { "atk_name": str(killer.name), "def_name": str(victim.name),
				"item_name": host.item_name(iid), "room_name": host.room_name(room) })
	ks.sheet_dirty = true
	host.save_char(killer)
	if vs != null:
		vs.sheet_dirty = true
	host.save_char(victim)
	_save_world()

## 管理員／除錯給神兵（§6.5）：已有人持有 → divine_locked；不是神兵 → bad_value:value
func grant_divine(s, item_id: String) -> Dictionary:
	if s == null or s.character == null:
		return GameHost.fail("no_character")
	if not is_divine(item_id):
		return GameHost.fail("bad_value:value")
	validate_registry()
	var cur := holder_of(item_id)
	if cur != "" and cur != str(s.character.id):
		return GameHost.fail("divine_locked")
	if s.character.inventory.count(item_id) > 0:
		divine_registry()[item_id] = str(s.character.id)
		return GameHost.ok()
	var g: Dictionary = s.character.inventory.add(item_id, 1, host.tables, host.now_s(), -1, host.make_uid_callable())
	if not g.get("ok", false):
		return GameHost.fail(str(g.get("reason", "inventory_full")))
	divine_registry()[item_id] = str(s.character.id)
	host.item_gain_event(s, item_id, 1)
	s.sheet_dirty = true
	host.save_char(s.character)
	_save_world()
	return GameHost.ok()

## 神兵登記一有變動就寫 world.json（很少發生；當機後登記遺失會讓第二把同名神兵掉出來）。
## 角色檔已由呼叫端先寫（先角色、後世界，同 BattleSystem.handle_death 的順序）
func _save_world() -> void:
	if host.ws != null and host.ws.has_method("save_now") and not (host.ws.world as Dictionary).is_empty():
		host.ws.save_now(true)

# ======================================================================== 頭目鎖（M3c 審查）
## 有 lockout_shichen 的掉落表（三個掉神兵的頭目）：同一角色擲過一次後，lockout_shichen 個時辰內只拿 guaranteed。
## ext.loot.lock = { 表 id: until_s（世界秒）}【設計提案】——原作無掉率資料；鎖是為了讓「頭目稀有」、
## 神兵與珍品不能靠無限重打刷出來（鬼王是 FIGHT 服務、銅甲是迷宮遇敵、李莫愁是任務戰）

func _lock(ch, lt_id: String) -> void:
	var lt: Dictionary = host.tables.get("loot_tables", {}).get(lt_id, {})
	var n := int(lt.get("lockout_shichen", 0))
	if n <= 0:
		return
	var e: Variant = ch.ext.get(EXT_KEY, {})
	if not (e is Dictionary):
		e = {}
	var m: Variant = (e as Dictionary).get("lock", {})
	if not (m is Dictionary):
		m = {}
	for k in (m as Dictionary).keys():
		if float(m[k]) <= host.now_s():
			(m as Dictionary).erase(k)
	m[lt_id] = host.now_s() + float(n) * WorldClock.shichen_len(host.day_s())
	(e as Dictionary)["lock"] = m
	ch.ext[EXT_KEY] = e

## 神兵全服鎖（M3c 第三輪審查）：以前鎖只跟著最後一擊者，隊友輪流搶最後一擊＝每人每 12 時辰各擲一次神兵，
## 4 人輪流打鬼王，玄鐵重劍約 250 小時、三個頭目第一把神兵約 83 小時（低於 balance_sim 的 300 小時底線）。
## 現在神兵群組每張表全服每 lockout_shichen 只擲一次；一般群組（良品～珍品）照舊是每個角色自己的鎖。
## 已經上鎖（還沒到期）就不延長：同一場的多個玩家結算、或同一場兩隻同表的怪都只鎖一次。
func _lock_divine(lt_id: String) -> void:
	var lt: Dictionary = host.tables.get("loot_tables", {}).get(lt_id, {})
	var n := int(lt.get("lockout_shichen", 0))
	if n <= 0:
		return
	var m := _divine_lock_map()
	for k in m.keys():
		if float(m[k]) <= host.now_s():
			m.erase(k)
	if m.has(lt_id):
		return
	m[lt_id] = host.now_s() + float(n) * WorldClock.shichen_len(host.day_s())

func _divine_lock_map() -> Dictionary:
	var w: Dictionary = host.ws.world
	if not (w.get(WORLD_DIVINE_LOCK) is Dictionary):
		w[WORLD_DIVINE_LOCK] = {}
	return w[WORLD_DIVINE_LOCK]

## 全服神兵群組還鎖著的掉落表 id
func divine_locked_tables() -> Array:
	var out: Array = []
	var m := _divine_lock_map()
	for k in m:
		if float(m[k]) > host.now_s():
			out.append(str(k))
	return out

## 全服神兵鎖還要等幾秒（世界秒；0 = 沒鎖）
func divine_lock_left(lt_id: String) -> float:
	return maxf(0.0, float(_divine_lock_map().get(lt_id, 0.0)) - host.now_s())

## 這個角色還鎖著的掉落表 id
func locked_tables(ch) -> Array:
	var out: Array = []
	var e: Variant = ch.ext.get(EXT_KEY, {})
	if not (e is Dictionary):
		return out
	var m: Variant = (e as Dictionary).get("lock", {})
	if not (m is Dictionary):
		return out
	for k in m:
		if float(m[k]) > host.now_s():
			out.append(str(k))
	return out

## 還要等幾秒（世界秒；0 = 沒鎖）
func lock_left(ch, lt_id: String) -> float:
	var e: Variant = ch.ext.get(EXT_KEY, {})
	if not (e is Dictionary) or not ((e as Dictionary).get("lock") is Dictionary):
		return 0.0
	return maxf(0.0, float((e as Dictionary)["lock"].get(lt_id, 0.0)) - host.now_s())

# ======================================================================== 強制掉落（debug_set loot_force）

func force_list(ch) -> Array:
	var e: Variant = ch.ext.get(EXT_KEY, {})
	if not (e is Dictionary):
		return []
	var f: Variant = (e as Dictionary).get("force", [])
	return (f as Array).duplicate() if f is Array else []

func debug_force(s, item_id: String) -> void:
	if s == null or s.character == null or item_row(item_id).is_empty():
		return
	var ch = s.character
	var e: Variant = ch.ext.get(EXT_KEY, {})
	if not (e is Dictionary):
		e = {}
	var f: Array = (e as Dictionary).get("force", []) if (e as Dictionary).get("force") is Array else []
	if not f.has(item_id):
		f.append(item_id)
	(e as Dictionary)["force"] = f
	ch.ext[EXT_KEY] = e

func _unforce(ch, item_id: String) -> void:
	var e: Variant = ch.ext.get(EXT_KEY, {})
	if not (e is Dictionary) or not ((e as Dictionary).get("force") is Array):
		return
	var f: Array = (e as Dictionary)["force"]
	f.erase(item_id)
	if f.is_empty():
		(e as Dictionary).erase("force")
		if (e as Dictionary).is_empty():   # 頭目鎖（lock）還在時不能整個刪
			ch.ext.erase(EXT_KEY)

# ======================================================================== 秘笈（§6.4）

## manual_read 的處理器。驗證順序：manuals_off → no_such_item → not_manual → manual_illiterate → req_* → manual_cap
## → not_enough_jing／not_enough_shen。秘笈不消耗。
func read_manual(s, uid: String, times: int) -> Dictionary:
	if not manuals_on():
		return GameHost.fail("manuals_off")
	var ch = s.character
	var inst: Dictionary = ch.inventory.find(uid)
	if inst.is_empty():
		return GameHost.fail("no_such_item")
	var item_id := str(inst.get("id", ""))
	var row := item_row(item_id)
	var m := Learning.manual_of(row)
	if m.is_empty():
		return GameHost.fail("not_manual")
	var skill := str(m.get("skill", ""))
	var r: Dictionary = Learning.read_manual(ch, row, clampi(times, 1, 10), host.tables, int(host.skill_cap(ch, skill)),
		host.options, host.rules)
	if not r.get("ok", false):
		return GameHost.fail(str(r.get("reason", "not_manual")))
	host.tell(s, Protocol.CH_SYSTEM, E_MANUAL_READ, {
		"item_name": host.item_name(item_id), "skill_name": host.skill_name(skill),
		"times": int(r.get("times_done", 0)), "prof": int(r.get("prof_gain", 0)),
		"level": int(r.get("level_after", 0)), "level_before": int(r.get("level_before", 0)),
		"cap": int(r.get("cap_eff", 0)), "value": int(r.get("cap_eff", 0)),
	})
	s.sheet_dirty = true
	return GameHost.ok({ "times_done": int(r.get("times_done", 0)), "level": int(r.get("level_after", 0)),
		"cap": int(r.get("cap_eff", 0)), "stopped_reason": str(r.get("stopped_reason", "")) })

# ==== M3c2 WP-CARRY ====
## M3C2_PLAN §5.5、R10：外來角色帶進來的神兵。本世界登記（world.divine）沒人持有 → 登記給 ch、保留；
## 已有人持有（另一個角色）→ 從 ch 拿掉（已裝備的先卸下）並回傳物品名稱清單。不變成普通複製品。
## 呼叫前（取代時）主機先用 on_char_deleted(本地 id) 撤銷舊角色的登記。先惰性校正登記（持有者已不在或身上沒有 → 釋放）。
func on_foreign_import(ch) -> Array:
	var names: Array = []
	if ch == null or ch.inventory == null:
		return names
	validate_registry()
	var reg := divine_registry()
	var changed := false
	var kept := {}   # 同一把神兵只能有一件（多的一樣拿掉）
	for it in ch.inventory.items.duplicate():
		var iid := str(it.get("id", ""))
		if not is_divine(iid):
			continue
		var n := int(it.get("n", 1))
		var holder := str(reg.get(iid, ""))
		if (holder != "" and holder != str(ch.id)) or kept.has(iid):
			ch.inventory.remove(str(it.get("uid", "")), n)
			names.append(host.item_name(iid))
			continue
		if n > 1:
			ch.inventory.remove(str(it.get("uid", "")), n - 1)
			names.append(host.item_name(iid))
		kept[iid] = true
		if holder == "":
			reg[iid] = str(ch.id)
			changed = true
	if changed:
		_save_world()
	return names
