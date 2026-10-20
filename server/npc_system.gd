class_name NpcSystem
extends RefCounted
## NPC 服務入口（M1_PLAN 3.5.2、3.6）：對話選單、商店、教學、客棧、記錄點、驛站、拜入、齋食、定點戰鬥。
## 每個函式回傳 { ok, reason }；NPC 檢查（not_here → no_service → closed_night）在這裡做。

const SELL_RATE := 0.3

var host: GameHost

func _init(p_host: GameHost) -> void:
	host = p_host

# ---------- 對話 ----------
func talk(s: Session, npc_id: String) -> Dictionary:
	var r := host.npc_here(s, npc_id)
	if r != "":
		return GameHost.fail(r)
	var row := host.npc_row(npc_id)
	var talk_key := str(row.get("talk", ""))
	if talk_key == "":
		talk_key = "talk_" + npc_id
	var p := { "npc_name": host.npc_name(npc_id), "name": str(s.character.name) }
	# STORY_PLAN §5.3、§5.4：招呼語（依善惡／名聲）先送，再送閒聊句（時辰變體 talk_<npc>@<period>）
	# 審查修正：同一位 NPC 同一種態度只招呼一次（talk_greet）；舊版 AmbientSystem 沒有就照舊用 greet_key
	var greet: Variant = host.m2_call(host.ambient, "talk_greet", [s, npc_id], null)
	if greet == null:
		greet = host.m2_call(host.ambient, "greet_key", [s, npc_id], "")
	if greet is String and greet != "":
		host.tell(s, Protocol.CH_SCENE, greet, p.duplicate())
	var tk: Variant = host.m2_call(host.ambient, "talk_key", [s, npc_id], talk_key)
	if tk is String and tk != "":
		talk_key = tk
	host.tell(s, Protocol.CH_SCENE, talk_key, p)
	# 遊蕩惡人白天定點：交談即開戰（§5.2.2 #4；WanderSystem 為 null 時略過）
	if bool(host.m2_call(host.wander, "on_talk", [s, npc_id], false)) or s.battle_id != 0:
		return GameHost.ok()
	# 門規 on_npc（武當 2001-08：善惡過低時與特定師長交談即叛派）；被開除後選單照新身分顯示
	if host.sects != null:
		host.sects.check_state(s, "TALK", npc_id)
		host.sects.try_repent(s, npc_id)   # 恆山犯戒：向知客弟子悔過（M3a 審查 #1）
	# STORY_PLAN §4.13：目前任務目標在此 NPC 且有對話 → 直接開對話，不另開選單
	if s.character != null and s.battle_id == 0 and host.quests.auto_dialogue(s, npc_id):
		return GameHost.ok()
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_NPC_MENU, menu(s, npc_id), true)
	return GameHost.ok()

## 選單內容變了（接任務、交任務）時重送 npc_menu；refresh == true 表示「只更新已開著的對話框，不要另開」
func refresh_menu(s: Session, npc_id: String) -> void:
	var m := menu(s, npc_id)
	m["refresh"] = true
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_NPC_MENU, m, true)

## 3.8.2 npc_menu
func menu(s: Session, npc_id: String) -> Dictionary:
	var row := host.npc_row(npc_id)
	var services: Array = (row.get("services", []) as Array).duplicate()
	var routes: Array = []
	if stagecoach_enabled():
		for rt in row.get("travel", []):
			if rt is Dictionary:
				var to := str(rt.get("to_room", ""))
				if host.index.has_room(to):
					routes.append({ "to_room": to, "to_name": host.room_name(to), "price": int(rt.get("price", 0)) })
	else:
		services.erase("TRAVEL")   # WORLD_2001 D5：馬車關閉時選單沒有「驛站」
	var sect := str(row.get("join_sect", ""))
	var m := {
		"npc": npc_id, "npc_name": host.npc_name(npc_id),
		"services": services,
		"closed": host.npc_closed(row),
		"quests": host.quests.menu_entries(s, npc_id),
		"routes": routes,
		"inn_price": adjusted_price(int(row.get("inn_price", 0)), price_pct(s, npc_id, "INN")) if "INN" in services 			else int(row.get("inn_price", 0)),
		"join_sect": sect,
		"sect_name": str(host.tables.get("sects", {}).get(sect, {}).get("name", "")) if sect != "" else "",
		# M3A_PLAN 6.12（SectSystem 為 null 時給同形狀的空值）
		"betray": false, "jail": null, "trial": null, "guide": null, "teach_blocked": "",
	}
	if host.sects != null:
		m.merge(host.sects.menu_fields(s, npc_id), true)
	# M3B_PLAN §6 npc_menu 新欄位（系統為 null 時給同形狀的空值）：bank、escort（WP-ECON）、org（WP-ORG）；rank、beg 由 SectSystem 給
	var m3b := { "bank": false, "escort": null, "org": null }
	for sys in [host.bank, host.escort, host.orgs]:
		var f: Variant = host.m2_call(sys, "menu_fields", [s, npc_id], {})
		if f is Dictionary:
			m3b.merge(f, true)
	m.merge(m3b, true)
	if not m.has("rank"):
		m["rank"] = null
	if not m.has("beg"):
		m["beg"] = null
	# M3C_PLAN §5.3、§8：npc_menu.attack（{ ok, reason, label, warn } 或 {}；NpcAttackSystem 為 null 時空字典）
	var atk: Variant = host.m2_call(host.npcpk, "menu_fields", [s, npc_id], {})
	m["attack"] = atk if atk is Dictionary else {}
	return m

func _ctx(s: Session) -> Dictionary:
	return host.sects.req_ctx(s) if host.sects != null else {}

## masters.hours（M3A_PLAN 3.5）：只在這些時辰教；空陣列 = 全天。
## M3A_PLAN 缺漏：時辰不對的原因碼沒有定義，用 not_teach_time（模板在 _rules.json）
func _teach_hour_reason(npc_id: String, skill_id: String) -> String:
	var m := CharData.master_row(host.tables, npc_id, skill_id)
	var hours: Variant = m.get("hours", [])
	if hours is Array and not (hours as Array).is_empty() and not (str(host.clock()["shichen_name"]) in hours):
		return "not_teach_time"
	return ""

## 本派師父拒絕傳授（停止傳功、禁止學武）時送一則說明（sect_stop_teach）
func _stop_teach_note(s: Session, npc_id: String, why: String) -> void:
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_SECT_STOP_TEACH, {
		"npc_name": host.npc_name(npc_id), "sect_name": CharData.sect_name(host.tables, str(s.character.sect)),
		"why": why, "left_s": s.character.ban_left_s() })

# ---------- 商店 ----------
static func sell_price(item_row: Dictionary) -> int:
	return maxi(1, floori(int(item_row.get("price", 0)) * SELL_RATE))

func _sellable(item_row: Dictionary) -> bool:
	return not bool(item_row.get("no_sell", false)) and not bool(item_row.get("quest_item", false))

func shop_list(s: Session, npc_id: String) -> Dictionary:
	var r := host.npc_check(s, npc_id, "SHOP")
	if r != "":
		return GameHost.fail(r)
	if _refused(s, npc_id, "SHOP"):
		return GameHost.fail(Protocol.R_NPC_REFUSE)
	var pct := price_pct(s, npc_id, "SHOP")
	var items_tbl: Dictionary = host.tables.get("items", {})
	var goods: Array = []
	for item_id in _shop_items(npc_id):
		var it: Dictionary = items_tbl.get(item_id, {})
		if it.is_empty():
			continue
		goods.append({ "id": item_id, "name": str(it.get("name", item_id)), "tab": str(it.get("tab", "OTHER")),
			"price": adjusted_price(int(it.get("price", 0)), pct) })
	var refused := shop_refuse_reason(s, npc_id) != ""
	var sellable: Array = []
	for inst in s.character.inventory.items:
		var iid := str(inst.get("id", ""))
		var it2: Dictionary = items_tbl.get(iid, {})
		if it2.is_empty() or not _sellable(it2):
			continue
		var uid := str(inst.get("uid", ""))
		sellable.append({ "uid": uid, "id": iid, "name": str(it2.get("name", iid)),
			"n": int(inst.get("n", 1)), "price": sell_price(it2), "equipped": s.character.inventory.is_equipped(uid) })
	# M3B_PLAN §5.1.6：shop.refuse_if 成立時照樣列出，但帶 refused 與拒賣文字（買不到，仍可賣）
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_SHOP_LIST,
		{ "npc": npc_id, "npc_name": host.npc_name(npc_id), "items": goods, "sellable": sellable,
			"refused": refused, "refuse_text": shop_refuse_text(npc_id) if refused else "" }, true)
	return GameHost.ok()

## M3B_PLAN §4.8、§5.1.6：shop.refuse_if 是「條件組」陣列，任一組全部成立就拒賣 → "shop_refused"；否則 ""
func shop_refuse_reason(s: Session, npc_id: String) -> String:
	var shop: Variant = host.npc_row(npc_id).get("shop")
	if not (shop is Dictionary) or s == null or s.character == null:
		return ""
	var groups: Variant = shop.get("refuse_if", [])
	if not (groups is Array):
		return ""
	for g in groups:
		if g is Array and not (g as Array).is_empty() 				and Requirements.check(g, s.character, host.tables, host.options, host.rules, _ctx(s)) == "":
			return Protocol.R_SHOP_REFUSED
	return ""

## 拒賣的文字：shop.refuse_text 模板的 self 變體（沒有模板時用通用句）
func shop_refuse_text(npc_id: String) -> String:
	var shop: Variant = host.npc_row(npc_id).get("shop")
	var key := str(shop.get("refuse_text", "")) if shop is Dictionary else ""
	var t: Variant = host.tables.get("text_templates", {}).get(key, {})
	if t is Dictionary and str(t.get("self", "")) != "":
		return str(t["self"]).replace("{npc_name}", host.npc_name(npc_id))
	return "%s搖搖頭：「這些東西不賣給你。」" % host.npc_name(npc_id)

func _shop_items(npc_id: String) -> Array:
	var shop: Variant = host.npc_row(npc_id).get("shop")
	if shop is Dictionary:
		return shop.get("items", [])
	return []

func buy(s: Session, npc_id: String, item_id: String, n: int) -> Dictionary:
	var r := host.npc_check(s, npc_id, "SHOP")
	if r != "":
		return GameHost.fail(r)
	var it: Dictionary = host.tables.get("items", {}).get(item_id, {})
	if not (item_id in _shop_items(npc_id)) or it.is_empty():
		return GameHost.fail("no_item")
	if _refused(s, npc_id, "SHOP"):
		return GameHost.fail(Protocol.R_NPC_REFUSE)
	if shop_refuse_reason(s, npc_id) != "":
		var shop: Variant = host.npc_row(npc_id).get("shop")
		var tk := str(shop.get("refuse_text", "")) if shop is Dictionary else ""
		host.tell(s, Protocol.CH_SCENE, tk if tk != "" and host.tables.get("text_templates", {}).has(tk) else Protocol.E_SHOP_REFUSED,
			{ "npc_name": host.npc_name(npc_id), "name": str(s.character.name), "text": shop_refuse_text(npc_id) })
		return GameHost.fail(Protocol.R_SHOP_REFUSED)
	var ch = s.character
	var cost := adjusted_price(int(it.get("price", 0)), price_pct(s, npc_id, "SHOP")) * n
	if int(ch.money) < cost:
		return GameHost.fail("not_enough_money")
	# 不可疊加的物品一件一件放；中途放不下就全部退回
	var added: Array = []
	var calls: Array = [n] if int(it.get("stack", 1)) > 1 else []
	if calls.is_empty():
		for i in n:
			calls.append(1)
	for k in calls:
		var res: Dictionary = host.give_item(ch, item_id, int(k))
		if not res.get("ok", false):
			for a in added:
				ch.inventory.remove(str(a[0]), int(a[1]))
			return GameHost.fail(str(res.get("reason", "inventory_full")))
		added.append([str(res.get("uid", "")), int(k)])
	ch.add_money(-cost)
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_BUY, { "item_name": host.item_name(item_id), "n": n, "cost": cost })
	host.quests.on_buy(s, npc_id, item_id, n)   # STORY_PLAN §4.8：BUY 目標
	return GameHost.ok()

# ---------- 對善惡／名聲的反應（STORY_PLAN §5.4；AmbientSystem 為 null 時原價、不拒絕） ----------
## 100 = 原價
func price_pct(s: Session, npc_id: String, service: String) -> int:
	var v: Variant = host.m2_call(host.ambient, "price_pct", [s, npc_id, service], 100)
	return maxi(1, int(v)) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 100

static func adjusted_price(base: int, pct: int) -> int:
	if pct == 100 or base <= 0:
		return base
	return maxi(1, roundi(base * pct / 100.0))

## 拒絕服務：送 refuse 模板（refuse_reason 回的模板 id）並回 true
func _refused(s: Session, npc_id: String, service: String) -> bool:
	var why: Variant = host.m2_call(host.ambient, "refuse_reason", [s, npc_id, service], "")
	if not (why is String) or why == "":
		return false
	host.tell(s, Protocol.CH_SCENE, str(why), { "npc_name": host.npc_name(npc_id), "name": str(s.character.name) })
	return true

func sell(s: Session, npc_id: String, uid: String, n: int) -> Dictionary:
	var r := host.npc_check(s, npc_id, "SHOP")
	if r != "":
		return GameHost.fail(r)
	var ch = s.character
	var inst: Dictionary = ch.inventory.find(uid)
	if inst.is_empty():
		return GameHost.fail("no_item")
	var item_id := str(inst.get("id", ""))
	var it: Dictionary = host.tables.get("items", {}).get(item_id, {})
	if it.is_empty() or not _sellable(it):
		return GameHost.fail("not_sellable")
	if int(inst.get("n", 1)) < n:
		return GameHost.fail("no_item")
	var gain := sell_price(it) * n
	# M1_PLAN 缺漏：money_cap 何時回傳沒有寫；這裡在賣出前檢查，超過上限就不賣（不讓玩家白白損失物品）
	if int(ch.money) + gain > Character.MONEY_CAP:
		return GameHost.fail("money_cap")
	var rm: Dictionary = ch.inventory.remove(uid, n)   # 已裝備的會先卸下
	if not rm.get("ok", false):
		return GameHost.fail(str(rm.get("reason", "no_item")))
	ch.add_money(gain)
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_SELL, { "item_name": host.item_name(item_id), "n": n, "gain": gain })
	return GameHost.ok()

# ---------- 教學 ----------
## 門派技能每次請教要耗內力／神（Learning.SECT_NEILI_COST／SECT_SHEN_COST）。清單上先標出來，
## 不然剛入門、內力 0 的新弟子看到的是可按的鈕，按了才得到「你的內力不夠」（擁有者回報）。
func _sect_train_cost_reason(s: Session, skill_id: String) -> String:
	if SkillBook.kind_of(skill_id, host.tables) != SkillBook.KIND_SECT:
		return ""
	var srow := CharData.sect_of_skill(host.tables, skill_id)
	var cost: Variant = srow.get("sect_skill_train_cost", srow.get("sect_skill_cost", []))
	if typeof(cost) != TYPE_ARRAY:
		return ""
	var v: Dictionary = s.character.vitals
	if (cost as Array).has("neili") and int(v.get("neili", 0)) < Learning.SECT_NEILI_COST:
		return "learn_need_neili"
	if (cost as Array).has("shen") and int(v.get("shen", 0)) < Learning.SECT_SHEN_COST:
		return "learn_need_shen"
	return ""

func learn_list(s: Session, npc_id: String) -> Dictionary:
	var r := host.npc_check(s, npc_id, "TEACH")
	if r != "":
		return GameHost.fail(r)
	var entries: Array = Learning.teach_entries(s.character, npc_id, host.tables, host.options, host.rules)
	var blocked: String = host.sects.can_teach(s, npc_id) if host.sects != null else ""
	for e in entries:
		if not bool(e.get("ok", false)):
			continue
		var why := blocked if blocked != "" else _teach_hour_reason(npc_id, str(e.get("skill", "")))
		if why == "":
			why = _sect_train_cost_reason(s, str(e.get("skill", "")))
		if why != "":
			e["ok"] = false
			e["reason"] = why
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_TEACH_LIST,
		{ "npc": npc_id, "npc_name": host.npc_name(npc_id), "entries": entries, "blocked": blocked }, true)
	return GameHost.ok()

func learn(s: Session, npc_id: String, skill_id: String, times: int) -> Dictionary:
	var r := host.npc_check(s, npc_id, "TEACH")
	if r != "":
		return GameHost.fail(r)
	if host.sects != null:
		host.sects.check_state(s, "LEARN")   # §6.3：學武前檢查門規（可能當場被押走）
		var blocked: String = host.sects.can_teach(s, npc_id)
		if blocked != "":
			if blocked != Protocol.R_JAILED:
				_stop_teach_note(s, npc_id, blocked)
			return GameHost.fail(blocked)
	var hr := _teach_hour_reason(npc_id, skill_id)
	if hr != "":
		return GameHost.fail(hr)
	var ch = s.character
	if SkillBook.kind_of(skill_id, host.tables) == "LIFE":
		return _learn_life(s, npc_id, skill_id)
	var res: Dictionary = Learning.learn(ch, npc_id, skill_id, times, host.tables, host.options, host.rules)
	if not res.get("ok", false):
		return GameHost.fail(str(res.get("reason", "not_taught")))
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_LEARN, {
		"npc_name": host.npc_name(npc_id), "skill_name": host.skill_name(skill_id),
		"times": int(res.get("times_done", 0)), "prof": int(res.get("prof_gain", 0)),
		"lp": int(res.get("lp_cost", 0)), "jing": int(res.get("jing_cost", 0)),
		"level": int(res.get("level_after", 0)) })
	skill_up_event(s, skill_id, int(res.get("level_before", 0)), int(res.get("level_after", 0)))
	return GameHost.ok({ "stopped_reason": str(res.get("stopped_reason", "")) })

func _learn_life(s: Session, npc_id: String, skill_id: String) -> Dictionary:
	var ch = s.character
	var res: Dictionary = Learning.learn_life(ch, npc_id, skill_id, host.tables)
	if not res.get("ok", false):
		return GameHost.fail(str(res.get("reason", "not_taught")))
	var tool := str(res.get("tool_item", ""))
	var tool_name := ""
	if tool != "" and host.tables.get("items", {}).has(tool):
		tool_name = host.item_name(tool)
		if int(ch.inventory.count(tool)) == 0:   # 4.12：背包已有就不給
			var g: Dictionary = host.give_item(ch, tool, 1)
			if g.get("ok", false):
				host.item_gain_event(s, tool, 1)
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_LIFE_LEARN, {
		"npc_name": host.npc_name(npc_id), "skill_name": host.skill_name(skill_id),
		"cost": int(res.get("money_cost", 0)), "tool_name": tool_name })
	skill_up_event(s, skill_id, 0, int(s.character.skills.level(skill_id)))
	return GameHost.ok()

func skill_up_event(s: Session, skill_id: String, before: int, after: int) -> void:
	if after > before:
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_SKILL_UP, { "skill_name": host.skill_name(skill_id), "level": after })

# ---------- 拜入門派 ----------
func join_sect(s: Session, npc_id: String) -> Dictionary:
	var r := host.npc_check(s, npc_id, "JOIN")
	if r != "":
		return GameHost.fail(r)
	var ch = s.character
	if str(ch.sect) != "":
		return GameHost.fail("already_in_sect")
	var sect_id := str(host.npc_row(npc_id).get("join_sect", ""))
	var sect: Dictionary = host.tables.get("sects", {}).get(sect_id, {})
	if sect.is_empty():
		return GameHost.fail("no_service")
	var genders: Variant = sect.get("gender", [])
	if genders is Array and not genders.is_empty() and not (str(ch.gender) in genders):
		return GameHost.fail("req_gender")
	var req: String = Requirements.check(sect.get("join_requires", []), ch, host.tables, host.options, host.rules, _ctx(s))
	if req != "":
		return GameHost.fail(req)
	ch.sect = sect_id
	if host.sects != null:
		host.sects.on_join(s, sect_id, npc_id)   # 門規起點、全真的師父（sect_master）、紀錄
	host.ws.broadcast_event(Protocol.CH_SYSTEM, Protocol.E_SECT_JOIN,
		{ "name": str(ch.name), "peer": s.peer_id, "sect_name": str(sect.get("name", sect_id)) })
	# 已開著的對話框換成弟子的選單（拜師 → 叛教、請教不再被擋）；M3a 審查：原本要關掉重開才看得到「叛教」
	refresh_menu(s, npc_id)
	return GameHost.ok()

# ---------- 客棧、記錄點、齋食 ----------
func inn_rest(s: Session, npc_id: String) -> Dictionary:
	var r := host.npc_check(s, npc_id, "INN")
	if r != "":
		return GameHost.fail(r)
	if _refused(s, npc_id, "INN"):
		return GameHost.fail(Protocol.R_NPC_REFUSE)
	var ch = s.character
	var price := adjusted_price(int(host.npc_row(npc_id).get("inn_price", 20)), price_pct(s, npc_id, "INN"))
	if int(ch.money) < price:
		return GameHost.fail("not_enough_money")
	ch.add_money(-price)
	Survival.rest_full(ch, host.tables, host.options)
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_INN_REST, { "cost": price, "room_name": host.room_name(host.index.room_of_npc(npc_id)) })
	return GameHost.ok()

func set_respawn(s: Session, npc_id: String) -> Dictionary:
	var r := host.npc_check(s, npc_id, "RESPAWN")
	if r != "":
		return GameHost.fail(r)
	var room := host.index.room_of_npc(npc_id)
	s.character.respawn = { "region": host.index.region_of(room), "room": room }
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_RESPAWN_SET, { "room_name": host.room_name(room) })
	return GameHost.ok()

func meal(s: Session, npc_id: String) -> Dictionary:
	var r := host.npc_check(s, npc_id, "MEAL")
	if r != "":
		return GameHost.fail(r)
	var m: Variant = host.npc_row(npc_id).get("meal", {})
	if not (m is Dictionary):
		m = {}
	var c := host.clock()
	if not (str(c["shichen_name"]) in m.get("hours", [])):
		return GameHost.fail("not_meal_time")
	# M3a：齋飯只限本派弟子等（meal.requires，選填；M3A_PLAN 4.2 第 3 點）
	var mreq: Variant = m.get("requires", [])
	if mreq is Array and not (mreq as Array).is_empty():
		var mr: String = Requirements.check(mreq, s.character, host.tables, host.options, host.rules, _ctx(s))
		if mr != "":
			return GameHost.fail(mr)
	var ch = s.character
	var key := "%d_%d" % [int(c["day"]), int(c["shichen_idx"])]
	if str(ch.counters.get("last_meal_key", "")) == key:
		return GameHost.fail("already_ate")
	Survival.eat_meal(ch, int(m.get("food", 0)), int(m.get("water", 0)))
	ch.counters["last_meal_key"] = key
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_MEAL, { "npc_name": host.npc_name(npc_id) })
	return GameHost.ok()

# ---------- 驛站 ----------
## 驛站馬車【設計提案・非原作】：伺服器選項 stagecoach_enabled，預設關（WORLD_2001 D5）
func stagecoach_enabled() -> bool:
	return host.options.get("stagecoach_enabled", false) == true

func travel(s: Session, npc_id: String, dest: String) -> Dictionary:
	if not stagecoach_enabled():
		return GameHost.fail("stagecoach_disabled")
	var r := host.npc_check(s, npc_id, "TRAVEL")
	if r != "":
		return GameHost.fail(r)
	var price := -1
	for rt in host.npc_row(npc_id).get("travel", []):
		if rt is Dictionary and str(rt.get("to_room", "")) == dest:
			price = int(rt.get("price", 0))
	if price < 0 or not host.index.has_room(dest):
		return GameHost.fail("no_route")
	var ch = s.character
	# M3b 審查：護送（保鏢）途中不能搭車——鏢車得跟著人一步一步走（不然搭車就能領保鏢酬勞）
	if host.quests != null and not host.quests.escort_npcs(ch).is_empty():
		return GameHost.fail("escorting")
	if int(ch.money) < price:
		return GameHost.fail("not_enough_money")
	var from := s.room_id()
	ch.add_money(-price)
	host.regions.teleport(s, dest)
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_TRAVEL,
		{ "from_name": host.room_name(from), "to_name": host.room_name(dest), "cost": price })
	host.quests.on_reach(s)
	# 和步行（RegionSystem.move）一樣跑移動鉤子：隊友的隊伍面板更新位置；搭車進出城照樣過守城官兵（M2 第三輪審查）
	host.m2_call(host.party, "on_moved", [s])
	host.m2_call(host.wander, "on_moved", [s, from, dest])
	host.m2_call(host.ambient, "on_enter_room", [s, from, dest])
	if host.pk != null:
		host.m2_call(host.pk, "on_move", [s, from, dest], false)
	return GameHost.ok()

# ---------- 定點戰鬥 ----------
func fight(s: Session, npc_id: String) -> Dictionary:
	var r := host.npc_check(s, npc_id, "FIGHT")
	if r != "":
		return GameHost.fail(r)
	var f: Variant = host.npc_row(npc_id).get("fight", {})
	if not (f is Dictionary) or str(f.get("monster", "")) == "" \
			or not host.tables.get("monsters", {}).has(str(f.get("monster", ""))):
		return GameHost.fail("no_service")
	var req: String = Requirements.check(f.get("requires", []), s.character, host.tables, host.options, host.rules, _ctx(s))
	if req != "":
		return GameHost.fail(req)
	host.tell(s, Protocol.CH_BATTLE, Protocol.E_FIGHT_START, { "npc_name": host.npc_name(npc_id) })
	host.battles.start(s, [str(f["monster"])], "FIGHT")
	return GameHost.ok()
