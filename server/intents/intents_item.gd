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
	# M3D_PLAN §9.2：WP-ERRANDS（任務道具）與 WP-ARTS（煉毒小木鼎）先處理；回非空字典＝已處理
	var h = host.m2_call(host.get("errands"), "on_use_item", [s, str(a.get("item_uid", a.get("uid", "")))], {})   # M3d WP-ERRANDS hook
	if h is Dictionary and not h.is_empty(): return h   # M3d WP-ERRANDS hook
	var h2 = host.m2_call(host.get("arts"), "on_use_item", [s, str(a.get("item_uid", a.get("uid", "")))], {})   # M3d WP-ARTS hook
	if h2 is Dictionary and not h2.is_empty(): return h2   # M3d WP-ARTS hook
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

## M3D_PLAN §3.6（R9，2001-10-09）：換裝兩秒間隔是全域的（地圖上的 equip／unequip 也算）；只在 1.0B 世界。
## 伺服器選項 equip_cooldown_ms（預設 2000，0–5000；0 = 關）。Session.last_equip_ms 不存檔。
const EQUIP_CD_DEFAULT_MS := 2000

## M3d 審查（第 3 輪）：兩秒間隔出自 2001-10-09 的 n323 更新（1.0B 之後；同一次更新修的是 1.0B 才有的丐幫京城交易與結婚的 bug）
## → 1.0B 沒開的世界（1.0A-only）不限制；1.0B 世界照伺服器選項。
static func equip_cooldown_ms(host: GameHost) -> int:
	if not GameData.enabled_eras.has("1.0B"):
		return 0
	return clampi(int(host.options.get("equip_cooldown_ms", EQUIP_CD_DEFAULT_MS)), 0, 5000)

## 冷卻中回 "equip_cooldown"，否則 ""（now_ms < 0 ＝ 用 Time.get_ticks_msec()）
static func equip_cd_reason(host: GameHost, s: Session, now_ms: int = -1) -> String:
	var cd := equip_cooldown_ms(host)
	if cd <= 0:
		return ""
	var now := Time.get_ticks_msec() if now_ms < 0 else now_ms
	return "equip_cooldown" if now - int(s.last_equip_ms) < cd else ""

static func equip(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var ch = s.character
	var uid := str(a["item_uid"])
	var cdr := equip_cd_reason(host, s)   # M3d WP-COMBAT
	if cdr != "":
		return GameHost.fail(cdr)
	# M3C_PLAN §6.3：物品 requires（例：限女性）不合 → req_<type>
	var r: Dictionary = ch.inventory.equip(uid, host.tables, ch, host.options, host.rules)
	if not r.get("ok", false):
		return GameHost.fail(str(r.get("reason", "no_item")))
	s.last_equip_ms = Time.get_ticks_msec()   # M3d WP-COMBAT
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_EQUIP, { "item_name": host.item_name(str(ch.inventory.find(uid).get("id", ""))) })
	return GameHost.ok()

static func unequip(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var ch = s.character
	var cdr := equip_cd_reason(host, s)   # M3d WP-COMBAT
	if cdr != "":
		return GameHost.fail(cdr)
	var r: Dictionary = ch.inventory.unequip(str(a["slot"]))
	if not r.get("ok", false):
		return GameHost.fail(str(r.get("reason", "no_item")))
	s.last_equip_ms = Time.get_ticks_msec()   # M3d WP-COMBAT
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
