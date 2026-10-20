class_name IntentsLoot
extends RefCounted
## manual_read（M3C_PLAN §6.4、§8；WP-LOOT）。GameHost 以路徑載入（M3C_INTENTS）；LootSystem 為 null 時回 manuals_off。

const F := GameHost.NEEDS_CHAR | GameHost.IDLE
const I_MANUAL_READ := "manual_read"   # ＝ Protocol.I_MANUAL_READ

static func register(host: GameHost) -> void:
	host.register(I_MANUAL_READ, func(s: Session, a: Dictionary) -> Dictionary:
		return manual_read(host, s, a), F)

static func manual_read(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var loot = host.get("loot")
	if loot == null or not loot.has_method("read_manual"):
		return GameHost.fail("manuals_off")
	var r: Variant = host.m2_call(loot, "read_manual", [s, str(a.get("item_uid", "")), clampi(int(a.get("times", 1)), 1, 10)],
		GameHost.fail("manuals_off"))
	return r if r is Dictionary else GameHost.fail("manuals_off")
