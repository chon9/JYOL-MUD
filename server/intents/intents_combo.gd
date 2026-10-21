class_name IntentsCombo
extends RefCounted
## 合體默契的 intent（M3D_PLAN §3.3.2、§7；WP-COMBAT）：combo_bond、combo_reply、combo_cancel、combo_nurture。
## GameHost 以路徑註冊（M3D_INTENTS）；ComboSystem（host.combo）不在時一律回 era_locked（功能不存在）。
## intent 名照 Protocol（WP-LAW Day-0 寫好）；這裡用同值的字串常數，Protocol 還沒有時也能載入。

const I_COMBO_BOND := "combo_bond"
const I_COMBO_REPLY := "combo_reply"
const I_COMBO_CANCEL := "combo_cancel"
const I_COMBO_NURTURE := "combo_nurture"
const F := GameHost.NEEDS_CHAR | GameHost.IDLE

static func register(host: GameHost) -> void:
	host.register(I_COMBO_BOND, func(s: Session, a: Dictionary) -> Dictionary:
		return _call(host, "bond", [s, str(a.get("target_char", ""))]), F)
	host.register(I_COMBO_REPLY, func(s: Session, a: Dictionary) -> Dictionary:
		return _call(host, "reply", [s, str(a.get("from_char", "")), bool(a.get("accept", false))]), F)
	host.register(I_COMBO_CANCEL, func(s: Session, _a: Dictionary) -> Dictionary:
		return _call(host, "cancel", [s]), F)
	host.register(I_COMBO_NURTURE, func(s: Session, _a: Dictionary) -> Dictionary:
		return _call(host, "nurture", [s]), F)

static func _call(host: GameHost, method: String, args: Array) -> Dictionary:
	var r: Variant = host.m2_call(host.get("combo"), method, args, null)
	if r is Dictionary:
		return r
	return GameHost.fail("era_locked")
