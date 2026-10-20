class_name IntentsSelf
extends RefCounted
## self_study meditate exert work（M1_PLAN 3.6）

const F := GameHost.NEEDS_CHAR | GameHost.IDLE

static func register(host: GameHost) -> void:
	host.register(Protocol.I_SELF_STUDY, func(s: Session, a: Dictionary) -> Dictionary:
		return self_study(host, s, a), F)
	host.register(Protocol.I_MEDITATE, func(s: Session, a: Dictionary) -> Dictionary:
		return meditate(host, s, a), F)
	host.register(Protocol.I_EXERT, func(s: Session, a: Dictionary) -> Dictionary:
		return exert(host, s, a), F)
	host.register(Protocol.I_WORK, func(s: Session, a: Dictionary) -> Dictionary:
		return host.life.work(s, str(a["skill"]), str(a.get("recipe", ""))), F)

static func self_study(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var skill_id := str(a["skill"])
	var r: Dictionary = Learning.self_study(s.character, skill_id, int(a.get("times", 1)),
		host.tables, host.options, host.rules)
	if not r.get("ok", false):
		return GameHost.fail(str(r.get("reason", "not_known")))
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_SELF_STUDY, {
		"skill_name": host.skill_name(skill_id), "times": int(r.get("times_done", 0)),
		"prof": int(r.get("prof_gain", 0)), "jing": int(r.get("jing_cost", 0)) })
	host.npcs.skill_up_event(s, skill_id, int(r.get("level_before", 0)), int(r.get("level_after", 0)))
	return GameHost.ok({ "stopped_reason": str(r.get("stopped_reason", "")) })

static func meditate(host: GameHost, s: Session, _a: Dictionary) -> Dictionary:
	var r: Dictionary = Survival.meditate(s.character, host.tables, host.options, host.now_s())
	if not r.get("ok", false):
		if str(r.get("reason", "")) == "busy":
			return host.fail_busy(s, GameHost.COOLDOWN_MEDITATE)
		return GameHost.fail(str(r.get("reason", "nothing_to_do")))
	if str(r.get("kind", "")) == "cultivate":
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_CULTIVATE,
			{ "qi_gain": int(r.get("qi_gain", 0)), "count": int(s.character.cultivations) })
	else:
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_MEDITATE,
			{ "gain": int(r.get("gain", 0)), "neili": int(r.get("neili", s.character.vitals.get("neili", 0))) })
	return GameHost.ok()

static func exert(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var stat := str(a["stat"])
	var r: Dictionary = Survival.exert(s.character, stat, host.tables, host.options)
	if not r.get("ok", false):
		return GameHost.fail(str(r.get("reason", "not_enough_neili")))
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_EXERT, { "stat_name": host.stat_name(stat), "gain": int(r.get("gain", 0)) })
	return GameHost.ok()
