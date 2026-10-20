## （不設 class_name：GameHost 依 M2_INTENTS 以路徑 load()，H4）
extends RefCounted
## challenge challenge_reply force_pk set_pref corpse_authorize，以及覆蓋 M1 的 loot_corpse（加 item_uid）。
## M2_PLAN 4.2。GameHost 依 M2_INTENTS 以路徑載入本檔並呼叫 register（H4）；
## 在 M1 的 IntentsItem 之後註冊，所以 loot_corpse 由這裡接手。

const CI := GameHost.NEEDS_CHAR | GameHost.IDLE
const C := GameHost.NEEDS_CHAR

static func register(host: GameHost) -> void:
	host.register(Protocol.I_CHALLENGE, func(s: Session, a: Dictionary) -> Dictionary:
		if host.pk == null:
			return GameHost.fail("pk_disabled")
		return host.pk.challenge(s, str(a["target"])), CI)
	host.register(Protocol.I_CHALLENGE_REPLY, func(s: Session, a: Dictionary) -> Dictionary:
		if host.pk == null:
			return GameHost.fail("no_challenge")
		return host.pk.challenge_reply(s, str(a["from"]), bool(a["accept"])), CI)
	host.register(Protocol.I_FORCE_PK, func(s: Session, a: Dictionary) -> Dictionary:
		if host.pk == null:
			return GameHost.fail("pk_disabled")
		return host.pk.force_pk(s, str(a["target"])), CI)
	host.register(Protocol.I_SET_PREF, func(s: Session, a: Dictionary) -> Dictionary:
		if host.pk == null:
			# 沒有 PkSystem 時開關仍然寫進角色（組隊邀請也看它）
			s.character.prefs[str(a["key"])] = bool(a["value"])
			return GameHost.ok()
		return host.pk.set_pref(s, str(a["key"]), bool(a["value"])), C)
	host.register(Protocol.I_CORPSE_AUTHORIZE, func(s: Session, a: Dictionary) -> Dictionary:
		return host.corpses.authorize(s, str(a["corpse_id"]), str(a["name"])), C)
	host.register(Protocol.I_LOOT_CORPSE, func(s: Session, a: Dictionary) -> Dictionary:
		return host.corpses.loot(s, str(a["corpse_id"]), str(a.get("item_uid", ""))), CI)
	# M3B_PLAN §5.1.5：捉拿公敵（1.0B）。SectSystem 為 null 時回 era_locked（功能不存在）
	host.register(Protocol.I_SEIZE_ENEMY, func(s: Session, a: Dictionary) -> Dictionary:
		if host.get("sects") == null:
			return GameHost.fail(Protocol.R_ERA_LOCKED)
		return host.sects.seize(s, str(a["name"])), CI)
