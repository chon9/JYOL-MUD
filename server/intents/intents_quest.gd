class_name IntentsQuest
extends RefCounted
## quest_accept quest_turn_in quest_abandon（M1_PLAN 3.6）

const F := GameHost.NEEDS_CHAR | GameHost.IDLE

static func register(host: GameHost) -> void:
	var q: QuestSystem = host.quests
	host.register(Protocol.I_QUEST_ACCEPT, func(s: Session, a: Dictionary) -> Dictionary:
		return q.accept(s, str(a["npc"]), str(a["quest"])), F)
	host.register(Protocol.I_QUEST_TURN_IN, func(s: Session, a: Dictionary) -> Dictionary:
		return q.turn_in(s, str(a["npc"]), str(a["quest"])), F)
	host.register(Protocol.I_QUEST_ABANDON, func(s: Session, a: Dictionary) -> Dictionary:
		return q.abandon(s, str(a["quest"])), F)
