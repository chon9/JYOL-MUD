class_name IntentsStory
extends RefCounted
## quest_talk dialogue_choose dialogue_close story_act（STORY_PLAN §4.14）。
## GameHost 以路徑 load()（STORY_INTENTS）後呼叫 register；villain_reply、rumor_list 由 WP-AMBIENT 的 intents_ambient.gd 註冊。

const F := GameHost.NEEDS_CHAR | GameHost.IDLE

static func register(host: GameHost) -> void:
	var q: QuestSystem = host.quests
	host.register(Protocol.I_QUEST_TALK, func(s: Session, a: Dictionary) -> Dictionary:
		return q.talk_quest(s, str(a["npc"]), str(a["quest"])), F)
	host.register(Protocol.I_DIALOGUE_CHOOSE, func(s: Session, a: Dictionary) -> Dictionary:
		return q.choose(s, str(a["npc"]), str(a["quest"]), str(a["node"]), str(a["choice"])), F)
	host.register(Protocol.I_DIALOGUE_CLOSE, func(s: Session, _a: Dictionary) -> Dictionary:
		return q.close_dialogue(s), GameHost.NEEDS_CHAR)
	host.register(Protocol.I_STORY_ACT, func(s: Session, a: Dictionary) -> Dictionary:
		return q.room_action(s, str(a["act"])), F)
