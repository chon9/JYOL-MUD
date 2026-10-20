class_name IntentsScout
extends RefCounted
## 查看偵察的回覆 scout_accept／scout_decline（ScoutSystem；docs/GDD.md §5.10【設計提案・非原作】）。
## 偵察本身由 look { scout: true } 觸發（IntentsMove.look）。

static func register(host: GameHost) -> void:
	host.register(Protocol.I_SCOUT_ACCEPT, func(s: Session, a: Dictionary) -> Dictionary:
		return host.scout.accept(s, str(a["offer_id"])), GameHost.NEEDS_CHAR | GameHost.IDLE)
	host.register(Protocol.I_SCOUT_DECLINE, func(s: Session, a: Dictionary) -> Dictionary:
		return host.scout.decline(s, str(a["offer_id"])), GameHost.NEEDS_CHAR)
