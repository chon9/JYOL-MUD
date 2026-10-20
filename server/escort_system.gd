class_name EscortSystem
extends RefCounted
## 鏢局的托鏢與取貨（M3B_PLAN §5.2.2；WP-ECON）。保鏢工作是一般任務（_econ.json 的 q_ec_biao_*），不在這裡。
## GameHost 以路徑 load()（L3）：host.escort；intent 在 server/intents/intents_econ.gd。
##
## world.consignments = [ { id, from_char, from_name, to_char, to_name, from_city, to_city,
##   items: [ { id, n, born_s, lots } ], money, fee, sent_s, arrive_s, ready_s, status } ]（§4.13；惰性建立）
## 狀態：TRANSIT（路上）→ READY（到站，等收件人到 to_city 的鏢局領）→ 過 consign_hold_days 沒人領 → RETURNED
## （回 from_city，寄件人自己去領）。領走（TAKEN）即從清單刪除。不會被劫（O16）。

const SERVICE := "ESCORT"
const CH := Protocol.CH_SYSTEM
const E_CONSIGN_SENT := Protocol.E_CONSIGN_SENT
const E_CONSIGN_LIST := Protocol.E_CONSIGN_LIST   # ui
const E_CONSIGN_ARRIVED := Protocol.E_CONSIGN_ARRIVED
const E_CONSIGN_TAKEN := Protocol.E_CONSIGN_TAKEN
const E_CONSIGN_RETURNED := Protocol.E_CONSIGN_RETURNED
const WORLD_KEY := "consignments"

var host: GameHost

func _init(p_host: GameHost) -> void:
	host = p_host

# ---------- 選項 ----------
func fee_base() -> int:
	return int(host.options.get("consign_fee_base", ConsignCalc.DEFAULT_FEE_BASE))

func fee_per_weight() -> int:
	return int(host.options.get("consign_fee_per_weight", ConsignCalc.DEFAULT_FEE_PER_WEIGHT))

func hold_days() -> int:
	return maxi(1, int(host.options.get("consign_hold_days", ConsignCalc.DEFAULT_HOLD_DAYS)))

# ---------- 資料 ----------
func all() -> Array:
	var c: Variant = host.ws.world.get(WORLD_KEY)
	if not (c is Array):
		c = []
		host.ws.world[WORLD_KEY] = c
	return c

func find(cid: String) -> Dictionary:
	for c in all():
		if c is Dictionary and str(c.get("id", "")) == cid:
			return c
	return {}

## 這位鏢頭在哪座城（npcs[].escort.city）
func npc_city(npc_id: String) -> String:
	var e: Variant = host.npc_row(npc_id).get("escort")
	return str((e as Dictionary).get("city", "")) if e is Dictionary else ""

func city_name(city: String) -> String:
	return host.region_name(city)

# ---------- intent ----------
## items：[{ uid, n }]（n <= 0 = 整疊），也接受純 uid 字串（整疊）。
## 驗證順序：no_character → in_battle → jailed → NPC（not_here／no_service／closed_night）→ no_route → no_such_char
## → self_target → 物品（too_many 超過 10 個 uid → no_such_item → equipped_item → not_bankable）→ 銀兩 bad_amount
## → 沒有東西可寄 no_such_item → 運費＋銀兩 > 身上 not_enough_money
func send(s: Session, npc_id: String, to_name: String, to_city: String, items: Array, money: int) -> Dictionary:
	var r := _gate(s, npc_id, "consign_send")
	if r != "":
		return GameHost.fail(r)
	var ch = s.character
	var from_city := npc_city(npc_id)
	var rt := ConsignCalc.route(host.tables, from_city, to_city)
	if rt.is_empty():
		return GameHost.fail("no_route")
	var ref: Dictionary = host.char_ref_by_name(to_name.strip_edges())
	var to_char := str(ref.get("char_id", ""))
	if to_char == "":
		return GameHost.fail("no_such_char")
	if to_char == str(ch.id):
		return GameHost.fail("self_target")
	var picks: Array = []   # [[uid, n]]（同一個 uid 合併）
	for e in items:
		var uid := ""
		var n := 0
		if e is Dictionary:
			uid = str(e.get("uid", ""))
			n = int(e.get("n", 0))
		else:
			uid = str(e)
		var merged := false
		for p in picks:
			if p[0] == uid:
				p[1] = -1 if (n <= 0 or int(p[1]) <= 0) else int(p[1]) + n
				merged = true
		if not merged:
			picks.append([uid, n if n > 0 else -1])
	if picks.size() > ConsignCalc.MAX_ITEMS:
		return GameHost.fail("too_many")
	var weight := 0
	for p in picks:
		var it: Dictionary = ch.inventory.find(str(p[0]))
		if it.is_empty():
			return GameHost.fail("no_such_item")
		if int(p[1]) <= 0:
			p[1] = int(it["n"])
		if int(p[1]) > int(it["n"]):
			return GameHost.fail("no_such_item")
		if ch.inventory.is_equipped(str(p[0])):
			return GameHost.fail("equipped_item")
		var row := CharData.row(host.tables, "items", str(it["id"]))
		if not BankStore.bankable(row):
			return GameHost.fail("not_bankable")
		weight += int(p[1]) * CharData.to_int(row.get("weight", 0))
	# M3b 審查 4：直接呼叫（測試、bot）也要擋溢位——網路路徑已由 Protocol.INT_RANGES 擋在 [0, 6000000]
	if money < 0 or money > BankStore.CARRY_MONEY_CAP:
		return GameHost.fail("bad_amount")
	if picks.is_empty() and money == 0:
		return GameHost.fail("no_such_item")
	var fee := ConsignCalc.fee(weight, fee_base(), fee_per_weight())
	if money + fee > int(ch.money):
		return GameHost.fail("not_enough_money")
	# 套用：扣錢、從背包移出（連同每一批的取得時間）
	ch.money = int(ch.money) - money - fee
	var goods: Array = []
	for p in picks:
		var it: Dictionary = ch.inventory.find(str(p[0]))
		var item_id := str(it["id"])
		var lots := BankStore.take_from_inventory(ch.inventory, str(p[0]), int(p[1]))
		var sum := 0
		for lot in lots:
			sum += int(lot["n"])
		goods.append({ "id": item_id, "n": sum, "born_s": float(lots[0]["born_s"]) if not lots.is_empty() else 0.0,
			"lots": lots })
		host.item_lost_event(s, item_id, sum)
	var now := host.now_s()
	var delay := int(rt.get("consign_delay_shichen", 0))
	var c := {
		"id": host.new_id("cs_"), "from_char": str(ch.id), "from_name": str(ch.name),
		"to_char": to_char, "to_name": _display_name(to_char, to_name),
		"from_city": from_city, "to_city": to_city, "items": goods, "money": money, "fee": fee,
		"sent_s": now, "arrive_s": ConsignCalc.arrive_s(now, delay, host.day_s()), "ready_s": 0.0,
		"status": ConsignCalc.STATUS_TRANSIT,
	}
	all().append(c)
	host.tell(s, CH, E_CONSIGN_SENT, { "to_name": str(c["to_name"]), "city_name": city_name(to_city),
		"fee": fee, "delay_text": ConsignCalc.delay_text(delay), "money": money, "n": goods.size() })
	s.sheet_dirty = true
	host.save_char(ch)
	host.ws.save_now()   # 托鏢的貨不可因當機遺失（比照飛鴿傳書）
	# 送達時間 0（資料寫 0 時辰）→ 立刻到站
	tick(now)
	return GameHost.ok({ "id": str(c["id"]), "fee": fee })

func list(s: Session, npc_id: String) -> Dictionary:
	var r := _gate(s, npc_id, "consign_list")
	if r != "":
		return GameHost.fail(r)
	_push_list(s, npc_id)
	return GameHost.ok()

## 驗證順序：gate → 找不到、不是給你的、不在這座城等你領 no_such_item → 放不下 too_heavy／too_many → 銀兩 money_cap
func take(s: Session, npc_id: String, cid: String) -> Dictionary:
	var r := _gate(s, npc_id, "consign_take")
	if r != "":
		return GameHost.fail(r)
	var ch = s.character
	var city := npc_city(npc_id)
	var c := find(cid)
	if c.is_empty() or not _takeable_here(c, str(ch.id), city):
		# M3B_PLAN 缺漏：「不在這座城」沒有專屬原因碼 → 一律 no_such_item（這裡沒有你的貨）
		return GameHost.fail("no_such_item")
	var gains: Array = []
	for g in c.get("items", []):
		if g is Dictionary:
			gains.append([str(g.get("id", "")), int(g.get("n", 0))])
	var carry_max := int(ch.derived(host.tables, host.options).get("carry_max", 0))
	var why := BankStore.fit_reason(ch.inventory, host.tables, carry_max, gains)
	if why != "":
		return GameHost.fail(why)
	var money := int(c.get("money", 0))
	if int(ch.money) + money > BankStore.CARRY_MONEY_CAP:
		return GameHost.fail("money_cap")
	for g in c.get("items", []):
		if not (g is Dictionary):
			continue
		var item_id := str(g.get("id", ""))
		var n := int(g.get("n", 0))
		var lots: Variant = g.get("lots", [])
		var res: Dictionary = host.give_item(ch, item_id, n, float(g.get("born_s", host.now_s())),
			lots if lots is Array else [])
		if res.get("ok", false):
			host.item_gain_event(s, item_id, n)
	ch.money = int(ch.money) + money
	var returned := str(c.get("status", "")) == ConsignCalc.STATUS_RETURNED
	c["status"] = ConsignCalc.STATUS_TAKEN
	all().erase(c)
	host.tell(s, CH, E_CONSIGN_TAKEN, {
		"from_name": str(c.get("from_name", "")), "to_name": str(c.get("to_name", "")),
		"returned": returned, "n": gains.size(), "money": money, "city_name": city_name(city) })
	if host.quests != null:
		host.quests.on_items(s)   # M3b 審查：取貨也可能完成 COLLECT 目標（同 BankSystem.take）
	s.sheet_dirty = true
	# M3b 審查 3：貨從 world.json 移到角色身上 → 先寫 world.json 再寫角色檔（同翻屍體，M2 審查）。
	# 兩次寫入之間當機時最多是貨物消失，不會在角色和託運單上各留一份（以前角色先寫，重開後可以再領一次）
	host.ws.save_now(true)
	_push_list(s, npc_id)
	return GameHost.ok()

## 每分鐘（GameHost._minute_jobs）：到站 → READY 並通知在線收件人；READY 過期 → RETURNED 並通知在線寄件人
func tick(now_world_s: float = -1.0) -> void:
	if host == null or host.ws == null:
		return
	var now := host.now_s() if now_world_s < 0.0 else now_world_s
	var days := hold_days()
	var day := host.day_s()
	for c in all():
		if not (c is Dictionary):
			continue
		var before := str(c.get("status", ""))
		var after := ConsignCalc.next_status(c, now, days, day)
		if after == before:
			continue
		c["status"] = after
		if after == ConsignCalc.STATUS_READY:
			c["ready_s"] = float(c.get("arrive_s", now))
			var rs: Session = host.session_for_char(str(c.get("to_char", "")))
			if rs != null:
				_tell_arrived(rs, c)
			# 一次 tick 內可能同時過期（主機長時間跳時）：再推一步
			after = ConsignCalc.next_status(c, now, days, day)
			if after != ConsignCalc.STATUS_READY:
				c["status"] = after
		if str(c["status"]) == ConsignCalc.STATUS_RETURNED:
			c["returned_s"] = now
			var ss: Session = host.session_for_char(str(c.get("from_char", "")))
			if ss != null:
				_tell_returned(ss, c)
	# M3b 審查 3：寄件人已刪除的貨退回時沒人能領 → 從 world.consignments 拿掉（以前永遠留著）
	var ref := all()
	for i in range(ref.size() - 1, -1, -1):
		var c2: Variant = ref[i]
		if c2 is Dictionary and bool(c2.get("from_deleted", false)) and str(c2.get("status", "")) == ConsignCalc.STATUS_RETURNED:
			ref.remove_at(i)

## 登入（GameHost 登入流程：m2_call(escort, "on_login", [s])）：等你領的貨、退回給你的貨各送一則
func on_login(s: Session) -> void:
	if s == null or s.character == null:
		return
	var me := str(s.character.id)
	for c in all():
		if not (c is Dictionary):
			continue
		var st := str(c.get("status", ""))
		if st == ConsignCalc.STATUS_READY and str(c.get("to_char", "")) == me:
			_tell_arrived(s, c)
		elif st == ConsignCalc.STATUS_RETURNED and str(c.get("from_char", "")) == me:
			_tell_returned(s, c)

## 角色刪除：寄給他的貨退回寄件城；他寄出、已退回的貨刪掉
func on_char_deleted(char_id: String) -> void:
	var keep: Array = []
	for c in all():
		if not (c is Dictionary):
			continue
		if str(c.get("from_char", "")) == char_id and str(c.get("status", "")) == ConsignCalc.STATUS_RETURNED:
			continue
		if str(c.get("to_char", "")) == char_id and str(c.get("status", "")) in [ConsignCalc.STATUS_TRANSIT, ConsignCalc.STATUS_READY]:
			c["status"] = ConsignCalc.STATUS_RETURNED
			c["returned_s"] = host.now_s()
			if str(c.get("from_char", "")) == char_id:
				continue   # 寄給自己刪掉的角色（不會發生；防禦）
		# M3b 審查 3：寄件人刪了、貨還在路上或等人領 → 收件人照領；過期退回時（tick）直接清掉
		if str(c.get("from_char", "")) == char_id:
			c["from_deleted"] = true
		keep.append(c)
	var ref := all()
	ref.clear()
	ref.append_array(keep)

## NpcSystem.menu 合併：§6 npc_menu.escort = { city, city_name, ready, routes: [{ city, city_name, delay_text }] }|null
func menu_fields(s: Session, npc_id: String) -> Dictionary:
	if not (SERVICE in host.npc_row(npc_id).get("services", [])):
		return { "escort": null }
	var city := npc_city(npc_id)
	var routes: Array = []
	for rt in ConsignCalc.routes_from(host.tables, city):
		var to := str(rt.get("to_city", ""))
		routes.append({ "city": to, "city_name": city_name(to),
			"delay_text": ConsignCalc.delay_text(int(rt.get("consign_delay_shichen", 0))) })
	var ready := 0
	if s != null and s.character != null:
		ready = _waiting_here(str(s.character.id), city).size()
	return { "escort": { "city": city, "city_name": city_name(city), "ready": ready, "routes": routes } }

# ---------- 內部 ----------
## no_character → in_battle → jailed → NPC（not_here／no_service／closed_night）→ 這位 NPC 沒寫城 no_service
func _gate(s: Session, npc_id: String, kind: String) -> String:
	if s == null or s.character == null:
		return "no_character"
	if s.battle_id != 0:
		return "in_battle"
	var jr: Variant = host.m2_call(host.get("sects"), "jail_gate", [s, kind], "")
	if str(jr) != "":
		return str(jr)
	var r := host.npc_check(s, npc_id, SERVICE)
	if r != "":
		return r
	if npc_city(npc_id) == "":
		return "no_service"   # M3B_PLAN 缺漏：ESCORT NPC 沒有 escort.city（lint 擋）→ 當作沒有這項服務
	return ""

func _takeable_here(c: Dictionary, me: String, city: String) -> bool:
	var st := str(c.get("status", ""))
	if st == ConsignCalc.STATUS_READY:
		return str(c.get("to_char", "")) == me and str(c.get("to_city", "")) == city
	if st == ConsignCalc.STATUS_RETURNED:
		return str(c.get("from_char", "")) == me and str(c.get("from_city", "")) == city
	return false

## 在這座城等我領的（到站給我的＋退回給我的）
func _waiting_here(me: String, city: String) -> Array:
	var out: Array = []
	for c in all():
		if c is Dictionary and _takeable_here(c, me, city):
			out.append(c)
	return out

func _entry(c: Dictionary) -> Dictionary:
	var items: Array = []
	for g in c.get("items", []):
		if g is Dictionary:
			items.append({ "item_id": str(g.get("id", "")), "name": host.item_name(str(g.get("id", ""))),
				"n": int(g.get("n", 0)) })
	var left := maxf(0.0, float(c.get("arrive_s", 0.0)) - host.now_s())
	return {
		"id": str(c.get("id", "")), "status": str(c.get("status", "")),
		"from_name": str(c.get("from_name", "")), "to_name": str(c.get("to_name", "")),
		"from_city": str(c.get("from_city", "")), "from_city_name": city_name(str(c.get("from_city", ""))),
		"to_city": str(c.get("to_city", "")), "to_city_name": city_name(str(c.get("to_city", ""))),
		"items": items, "money": int(c.get("money", 0)),
		"arrive_left_s": host.real_span(left),
		"sent_clock": str(WorldClock.clock(float(c.get("sent_s", 0.0)), host.day_s()).get("text", "")),
	}

## consign_list（ui）：{ npc, npc_name, city, city_name, ready: [entry]（在這座城可領）, sent: [entry]（我寄出還沒被領的）,
##   routes: [{ city, city_name, delay_text }], fee_base, fee_per_weight }
func _push_list(s: Session, npc_id: String) -> void:
	var me := str(s.character.id)
	var city := npc_city(npc_id)
	var ready: Array = []
	for c in _waiting_here(me, city):
		ready.append(_entry(c))
	var sent: Array = []
	for c in all():
		if c is Dictionary and str(c.get("from_char", "")) == me and str(c.get("status", "")) != ConsignCalc.STATUS_RETURNED:
			sent.append(_entry(c))
	var mf := menu_fields(s, npc_id)
	var esc: Variant = mf.get("escort")
	host.tell(s, CH, E_CONSIGN_LIST, {
		"npc": npc_id, "npc_name": host.npc_name(npc_id), "city": city, "city_name": city_name(city),
		"ready": ready, "sent": sent, "routes": (esc as Dictionary).get("routes", []) if esc is Dictionary else [],
		"fee_base": fee_base(), "fee_per_weight": fee_per_weight(),
	}, true)

func _tell_arrived(s: Session, c: Dictionary) -> void:
	host.tell(s, CH, E_CONSIGN_ARRIVED, { "from_name": str(c.get("from_name", "")),
		"city_name": city_name(str(c.get("to_city", ""))), "id": str(c.get("id", "")) })

func _tell_returned(s: Session, c: Dictionary) -> void:
	host.tell(s, CH, E_CONSIGN_RETURNED, { "to_name": str(c.get("to_name", "")),
		"city_name": city_name(str(c.get("from_city", ""))), "id": str(c.get("id", "")) })

## 收件人的正式名字：GameHost.pvp_char_name（在線或 char_names 反查），都沒有就用打的字
func _display_name(char_id: String, typed: String) -> String:
	var n := str(host.pvp_char_name(char_id))
	return n if n != "" else host.clean_text(typed, 64)
