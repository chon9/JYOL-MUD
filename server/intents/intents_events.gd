## （不設 class_name：GameHost 依 M3D_INTENTS 以路徑 load()）
extends RefCounted
## M3d WP-EVENTS 的 intent（M3D_PLAN §7）：rob_escort（劫鏢）、tourney_info／tourney_signup／tourney_withdraw／tourney_host（比武）。
## host.jiebiao／host.tourney 為 null 時回 era_locked／tourney_disabled（功能不存在）。

const CI := GameHost.NEEDS_CHAR | GameHost.IDLE
const C := GameHost.NEEDS_CHAR

static func register(host: GameHost) -> void:
	host.register(Protocol.I_ROB_ESCORT, func(s: Session, a: Dictionary) -> Dictionary:
		var jb = host.get("jiebiao")
		if jb == null:
			return GameHost.fail(Protocol.R_ERA_LOCKED)
		return jb.rob(s, str(a["target_char"])), CI)
	host.register(Protocol.I_TOURNEY_INFO, func(s: Session, _a: Dictionary) -> Dictionary:
		var t = host.get("tourney")
		if t == null:
			return GameHost.fail("tourney_disabled")
		return t.info(s), C)
	host.register(Protocol.I_TOURNEY_SIGNUP, func(s: Session, a: Dictionary) -> Dictionary:
		var t = host.get("tourney")
		if t == null:
			return GameHost.fail("tourney_disabled")
		return t.signup(s, str(a["npc"]), str(a["kind"])), CI)
	host.register(Protocol.I_TOURNEY_WITHDRAW, func(s: Session, _a: Dictionary) -> Dictionary:
		var t = host.get("tourney")
		if t == null:
			return GameHost.fail("tourney_disabled")
		return t.withdraw(s), CI)   # M3d 審查：比武中不能送（要棄權就逃＝判負）
	host.register(Protocol.I_TOURNEY_HOST, func(s: Session, a: Dictionary) -> Dictionary:
		var t = host.get("tourney")
		if t == null:
			return GameHost.fail("tourney_disabled")
		return t.host_open(s, str(a["kind"]), int(a.get("signup_s", 0))), C)
