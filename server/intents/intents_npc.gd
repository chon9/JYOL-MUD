class_name IntentsNpc
extends RefCounted
## talk shop_list buy sell learn_list learn join_sect inn_rest set_respawn meal fight（M1_PLAN 3.6）

const F := GameHost.NEEDS_CHAR | GameHost.IDLE

static func register(host: GameHost) -> void:
	var n: NpcSystem = host.npcs
	host.register(Protocol.I_TALK, func(s: Session, a: Dictionary) -> Dictionary:
		return n.talk(s, str(a["npc"])), F)
	host.register(Protocol.I_SHOP_LIST, func(s: Session, a: Dictionary) -> Dictionary:
		return n.shop_list(s, str(a["npc"])), F)
	host.register(Protocol.I_BUY, func(s: Session, a: Dictionary) -> Dictionary:
		return n.buy(s, str(a["npc"]), str(a["item"]), int(a.get("n", 1))), F)
	host.register(Protocol.I_SELL, func(s: Session, a: Dictionary) -> Dictionary:
		return n.sell(s, str(a["npc"]), str(a["item_uid"]), int(a.get("n", 1))), F)
	host.register(Protocol.I_LEARN_LIST, func(s: Session, a: Dictionary) -> Dictionary:
		return n.learn_list(s, str(a["npc"])), F)
	host.register(Protocol.I_LEARN, func(s: Session, a: Dictionary) -> Dictionary:
		return n.learn(s, str(a["npc"]), str(a["skill"]), int(a.get("times", 1))), F)
	host.register(Protocol.I_JOIN_SECT, func(s: Session, a: Dictionary) -> Dictionary:
		return n.join_sect(s, str(a["npc"])), F)
	host.register(Protocol.I_INN_REST, func(s: Session, a: Dictionary) -> Dictionary:
		return n.inn_rest(s, str(a["npc"])), F)
	host.register(Protocol.I_SET_RESPAWN, func(s: Session, a: Dictionary) -> Dictionary:
		return n.set_respawn(s, str(a["npc"])), F)
	host.register(Protocol.I_MEAL, func(s: Session, a: Dictionary) -> Dictionary:
		return n.meal(s, str(a["npc"])), F)
	host.register(Protocol.I_FIGHT, func(s: Session, a: Dictionary) -> Dictionary:
		return n.fight(s, str(a["npc"])), F)
