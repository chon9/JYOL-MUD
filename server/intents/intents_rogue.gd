class_name IntentsRogue
extends RefCounted
## 江湖試煉的 intent（ROGUE_PLAN §6.1）【設計提案・非原作】。GameHost 依 ROGUE_INTENTS 以路徑 load()。
## host.rogue 為 null 或不在試煉世界（RogueSystem.enabled() == false）→ rogue_off。
## rogue_debug 只在主機以 --debug-intents 啟動時註冊（§3.11，同 debug_set）。

const C := GameHost.NEEDS_CHAR
const CI := GameHost.NEEDS_CHAR | GameHost.IDLE

static func register(host: GameHost) -> void:
	host.register(Protocol.I_ROGUE_OPEN, func(s: Session, a: Dictionary) -> Dictionary:
		var rg = _sys(host)
		if rg == null:
			return GameHost.fail(Protocol.R_ROGUE_OFF)
		return rg.open(s, int(a.get("seed", 0))), 0)
	host.register(Protocol.I_ROGUE_START, func(s: Session, a: Dictionary) -> Dictionary:
		var rg = _sys(host)
		if rg == null:
			return GameHost.fail(Protocol.R_ROGUE_OFF)
		return rg.start(s, a), 0)
	host.register(Protocol.I_ROGUE_PICK, func(s: Session, a: Dictionary) -> Dictionary:
		var rg = _sys(host)
		if rg == null:
			return GameHost.fail(Protocol.R_ROGUE_OFF)
		return rg.pick(s, int(a["idx"]), a.get("alloc", {}) if a.get("alloc") is Dictionary else {}), C)
	host.register(Protocol.I_ROGUE_FIGHT, func(s: Session, _a: Dictionary) -> Dictionary:
		var rg = _sys(host)
		if rg == null:
			return GameHost.fail(Protocol.R_ROGUE_OFF)
		return rg.fight(s), CI)
	host.register(Protocol.I_ROGUE_ABANDON, func(s: Session, a: Dictionary) -> Dictionary:
		var rg = _sys(host)
		if rg == null:
			return GameHost.fail(Protocol.R_ROGUE_OFF)
		return rg.abandon(s, bool(a["confirm"])), C)
	if host.debug_enabled:
		host.register(Protocol.I_ROGUE_DEBUG, func(s: Session, a: Dictionary) -> Dictionary:
			var rg = _sys(host)
			if rg == null:
				return GameHost.fail(Protocol.R_ROGUE_OFF)
			return rg.debug(s, a), 0)

## 試煉世界的 RogueSystem；不是試煉世界（或系統沒載入）回 null
static func _sys(host: GameHost):
	var rg = host.get("rogue")
	if rg == null or not rg.enabled():
		return null
	return rg
