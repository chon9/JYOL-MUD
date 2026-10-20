class_name IntentsItem
extends RefCounted
## use_item equip unequip drop_item loot_corpse（M1_PLAN 3.6）；M3c：equip 的物品條件、no_drop（WP-LOOT）

const F := GameHost.NEEDS_CHAR | GameHost.IDLE

static func register(host: GameHost) -> void:
	host.register(Protocol.I_USE_ITEM, func(s: Session, a: Dictionary) -> Dictionary:
		return use_item(host, s, a), F)
	host.register(Protocol.I_EQUIP, func(s: Session, a: Dictionary) -> Dictionary:
		return equip(host, s, a), F)
	host.register(Protocol.I_UNEQUIP, func(s: Session, a: Dictionary) -> Dictionary:
		return unequip(host, s, a), F)
	host.register(Protocol.I_DROP_ITEM, func(s: Session, a: Dictionary) -> Dictionary:
		return drop_item(host, s, a), F)
	host.register(Protocol.I_LOOT_CORPSE, func(s: Session, a: Dictionary) -> Dictionary:
		return host.corpses.loot(s, str(a["corpse_id"])), F)

static func use_item(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var ch = s.character
	var uid := str(a["item_uid"])
	var inst: Dictionary = ch.inventory.find(uid)
	var item_id := str(inst.get("id", ""))
	var now := host.now_s()
	var r: Dictionary = Survival.use_item(ch, uid, host.tables, host.options, now)
	if not r.get("ok", false):
		return GameHost.fail(str(r.get("reason", "no_item")))
	if str(r.get("item_id", "")) != "":
		item_id = str(r["item_id"])
	# 守護者之煙（4.11）：使用後 value 秒內遇敵率 ×0.1
	for eff in host.tables.get("items", {}).get(item_id, {}).get("effects", []):
		if eff is Dictionary and str(eff.get("type", "")) == "smoke":
			ch.buffs["smoke_until_s"] = maxf(float(ch.buffs.get("smoke_until_s", 0.0)), now + float(eff.get("value", 0)))
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_ITEM_USE,
		{ "item_name": host.item_name(item_id), "effects": r.get("effects_applied", []) })
	if bool(r.get("overdose", false)):
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_OVERDOSE, {})
	# M3A_PLAN 6.10：解藥在戰鬥外解除戰後持續狀態
	for ap in r.get("effects_applied", []):
		if ap is Dictionary and str(ap.get("stat", "")) == "cure" and int(ap.get("gain", 0)) > 0:
			var sid := str(ap.get("status", ""))
			host.tell(s, Protocol.CH_SYSTEM, Protocol.E_CONDITION_OFF,
				{ "status_name": str(host.tables.get("status_effects", {}).get(sid, {}).get("name", sid)) })
	var loss: Dictionary = r.get("sect_skill_loss", {})
	if not loss.is_empty():
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_WINE_VOW if str(loss.get("kind", "")) == "WINE" else Protocol.E_MEAT_VOW,
			{ "skill_name": str(loss.get("name", "")), "level": int(loss.get("to", 0)) })
	return GameHost.ok()

static func equip(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var ch = s.character
	var uid := str(a["item_uid"])
	# M3C_PLAN §6.3：物品 requires（例：限女性）不合 → req_<type>
	var r: Dictionary = ch.inventory.equip(uid, host.tables, ch, host.options, host.rules)
	if not r.get("ok", false):
		return GameHost.fail(str(r.get("reason", "no_item")))
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_EQUIP, { "item_name": host.item_name(str(ch.inventory.find(uid).get("id", ""))) })
	return GameHost.ok()

static func unequip(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var ch = s.character
	var r: Dictionary = ch.inventory.unequip(str(a["slot"]))
	if not r.get("ok", false):
		return GameHost.fail(str(r.get("reason", "no_item")))
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_UNEQUIP,
		{ "item_name": host.item_name(str(ch.inventory.find(str(r.get("uid", ""))).get("id", ""))) })
	return GameHost.ok()

static func drop_item(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var ch = s.character
	var uid := str(a["item_uid"])
	var n := int(a.get("n", 1))
	var inst: Dictionary = ch.inventory.find(uid)
	if inst.is_empty():
		return GameHost.fail("no_item")
	var item_id := str(inst.get("id", ""))
	if bool(host.tables.get("items", {}).get(item_id, {}).get("quest_item", false)):
		return GameHost.fail("not_droppable")
	# M3C_PLAN §6.3、§6.5：神兵（no_drop）不能丟
	if bool(host.tables.get("items", {}).get(item_id, {}).get("no_drop", false)):
		return GameHost.fail("divine_locked")
	if int(inst.get("n", 1)) < n:
		return GameHost.fail("no_item")
	var r: Dictionary = ch.inventory.remove(uid, n)
	if not r.get("ok", false):
		return GameHost.fail(str(r.get("reason", "no_item")))
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_ITEM_DROP, { "item_name": host.item_name(item_id), "n": n })
	return GameHost.ok()
