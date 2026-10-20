class_name IntentsParty
extends RefCounted
## 組隊 intent（M2_PLAN 4.2）：party_invite／party_reply（C+I）、party_leave／party_kick／party_lead（C）。
## battle_join 由 intents_battle.gd 註冊（處理器在 BattleSystem.join）。
## GameHost 依 M2_INTENTS 以路徑載入本檔並呼叫 register（H4）；host.party 為 null 時不註冊（intent 會回 unknown_intent）。

static func register(host: GameHost) -> void:
	var party = host.get("party")
	if party == null:
		return
	var c := GameHost.NEEDS_CHAR
	var ci := GameHost.NEEDS_CHAR | GameHost.IDLE
	host.register(Protocol.I_PARTY_INVITE, func(s: Session, a: Dictionary) -> Dictionary:
		return party.invite(s, str(a.get("target", ""))), ci)
	host.register(Protocol.I_PARTY_REPLY, func(s: Session, a: Dictionary) -> Dictionary:
		return party.reply(s, str(a.get("from", "")), bool(a.get("accept", false))), ci)
	host.register(Protocol.I_PARTY_LEAVE, func(s: Session, _a: Dictionary) -> Dictionary:
		return party.leave(s), c)
	host.register(Protocol.I_PARTY_KICK, func(s: Session, a: Dictionary) -> Dictionary:
		return party.kick(s, str(a.get("target", ""))), c)
	host.register(Protocol.I_PARTY_LEAD, func(s: Session, a: Dictionary) -> Dictionary:
		return party.lead(s, str(a.get("target", ""))), c)
