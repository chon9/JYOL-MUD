class_name BankSystem
extends RefCounted
## 錢莊（M3B_PLAN §5.2.1；WP-ECON）：存取物品與銀兩，三城共用一個帳戶 ch.bank（O15），隨角色檔存檔。
## GameHost 以路徑 load()（L3）：host.bank；intent 在 server/intents/intents_econ.gd。
##
## 每個動作的驗證順序：no_character → in_battle → jailed → NPC 不在／沒有 BANK → not_at_bank → 各動作自己的檢查。

const SERVICE := "BANK"
const CH := Protocol.CH_SYSTEM
const E_BANK_VIEW := Protocol.E_BANK_VIEW       # ui
const E_BANK_PUT := Protocol.E_BANK_PUT
const E_BANK_TAKE := Protocol.E_BANK_TAKE
const E_BANK_MONEY := Protocol.E_BANK_MONEY

var host: GameHost

func _init(p_host: GameHost) -> void:
	host = p_host

# ---------- 選項 ----------
func capacity() -> int:
	return maxi(0, int(host.options.get("bank_capacity", BankStore.DEFAULT_CAPACITY)))

func money_cap() -> int:
	return maxi(0, int(host.options.get("bank_money_cap", BankStore.DEFAULT_MONEY_CAP)))

# ---------- intent ----------
func open(s: Session, npc_id: String) -> Dictionary:
	var r := _gate(s, npc_id, "bank_open")
	if r != "":
		return GameHost.fail(r)
	_push_view(s, npc_id)
	return GameHost.ok()

func put(s: Session, npc_id: String, uid: String, n: int) -> Dictionary:
	var r := _gate(s, npc_id, "bank_put")
	if r != "":
		return GameHost.fail(r)
	var ch = s.character
	var res := BankStore.put(BankStore.bank_of(ch), ch.inventory, uid, n, host.tables, capacity(), host.now_s(),
		host.make_uid_callable())
	if not res.get("ok", false):
		return GameHost.fail(str(res.get("reason", "no_such_item")))
	var item_id := str(res["item_id"])
	host.tell(s, CH, E_BANK_PUT, { "item_name": host.item_name(item_id), "n": int(res["n"]),
		"npc_name": host.npc_name(npc_id) })
	if host.quests != null:
		host.quests.on_items(s)   # COLLECT 目標會看背包數量
	_after_change(s, npc_id)
	return GameHost.ok({ "uid": str(res["uid"]) })

func take(s: Session, npc_id: String, uid: String, n: int) -> Dictionary:
	var r := _gate(s, npc_id, "bank_take")
	if r != "":
		return GameHost.fail(r)
	var ch = s.character
	var carry_max := int(ch.derived(host.tables, host.options).get("carry_max", 0))
	var res := BankStore.take(BankStore.bank_of(ch), ch.inventory, uid, n, host.tables, carry_max, host.now_s(),
		host.make_uid_callable())
	if not res.get("ok", false):
		return GameHost.fail(str(res.get("reason", "no_such_item")))
	var item_id := str(res["item_id"])
	host.tell(s, CH, E_BANK_TAKE, { "item_name": host.item_name(item_id), "n": int(res["n"]),
		"npc_name": host.npc_name(npc_id) })
	if host.quests != null:
		host.quests.on_items(s)
	_after_change(s, npc_id)
	return GameHost.ok({ "uid": str(res["uid"]) })

## amount > 0 存、< 0 領
func money(s: Session, npc_id: String, amount: int) -> Dictionary:
	var r := _gate(s, npc_id, "bank_money")
	if r != "":
		return GameHost.fail(r)
	var ch = s.character
	var bank := BankStore.bank_of(ch)
	var why := BankStore.money_reason(int(bank["money"]), int(ch.money), amount, money_cap())
	if why != "":
		return GameHost.fail(why)
	var got := BankStore.apply_money(bank, int(ch.money), amount)
	ch.money = int(got["carried"])
	# 模板 bank_money 用 {verb}（存入／領出）；兩個字放在這裡，不另開模板【設計提案】
	host.tell(s, CH, E_BANK_MONEY, { "amount": absi(amount), "deposit": amount > 0, "verb": "存入" if amount > 0 else "領出",
		"bank_money": int(got["bank_money"]), "money": int(ch.money), "npc_name": host.npc_name(npc_id) })
	_after_change(s, npc_id)
	return GameHost.ok({ "bank_money": int(got["bank_money"]) })

## bank_view 的內容：{ money, items:[{uid,item_id,name,n,weight}], used, capacity, money_cap }
func view(ch) -> Dictionary:
	var bank := BankStore.bank_of(ch)
	return {
		"money": int(bank["money"]), "items": BankStore.view_rows(bank, host.tables),
		"used": BankStore.pieces(bank), "capacity": capacity(), "money_cap": money_cap(),
	}

## debug_set bank_clear（§6；intents_debug 由 WP-SECT 呼叫）：清空自己的錢莊
func clear(ch) -> void:
	var bank := BankStore.bank_of(ch)
	bank["money"] = 0
	(bank["items"] as Array).clear()

# ---------- 主機接線 ----------
## NpcSystem.menu 合併（WP-SECT Day-0：m2_call(bank, "menu_fields", [s, npc_id])）：§6 npc_menu.bank
func menu_fields(_s: Session, npc_id: String) -> Dictionary:
	return { "bank": SERVICE in host.npc_row(npc_id).get("services", []) }

# ---------- 內部 ----------
## no_character → in_battle → jailed → not_at_bank
func _gate(s: Session, npc_id: String, kind: String) -> String:
	if s == null or s.character == null:
		return "no_character"
	if s.battle_id != 0:
		return "in_battle"
	var jr: Variant = host.m2_call(host.get("sects"), "jail_gate", [s, kind], "")
	if str(jr) != "":
		return str(jr)
	if host.npc_check(s, npc_id, SERVICE) != "":
		return "not_at_bank"
	return ""

func _push_view(s: Session, npc_id: String) -> void:
	var v := view(s.character)
	v["npc"] = npc_id
	v["npc_name"] = host.npc_name(npc_id)
	v["carried_money"] = int(s.character.money)
	host.tell(s, CH, E_BANK_VIEW, v, true)

func _after_change(s: Session, npc_id: String) -> void:
	s.sheet_dirty = true
	_push_view(s, npc_id)
	host.save_char(s.character)   # 錢與物品搬家後立刻落地（當機不丟）
