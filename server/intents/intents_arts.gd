## （不設 class_name：GameHost 依 M3D_INTENTS 以路徑 load()，K3／H4）
extends RefCounted
## M3d WP-ARTS 的 intent（M3D_PLAN §4.4、§4.7、§7）：intimidate { npc }、liandu {}。
## host.arts 為 null 時不註冊（intent 回 unknown_intent）。no_character → in_battle → jailed 由 GameHost._run_intent 做。

const F := GameHost.NEEDS_CHAR | GameHost.IDLE

static func register(host: GameHost) -> void:
	if host.get("arts") == null:
		return
	host.register(Protocol.I_INTIMIDATE, func(s: Session, a: Dictionary) -> Dictionary:
		return host.arts.intimidate(s, str(a["npc"])), F)
	host.register(Protocol.I_LIANDU, func(s: Session, _a: Dictionary) -> Dictionary:
		return host.arts.liandu(s), F)
