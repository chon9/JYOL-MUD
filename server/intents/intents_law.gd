## （不設 class_name：GameHost 依 M3D_INTENTS 以路徑 load()，M3D_PLAN §2.1）
extends RefCounted
## M3d 懸賞與律法 intent（M3D_PLAN §7；WP-LAW）：bounty_board、bounty_license、bounty_add、bounty_claim、cleanse。
## host.law 為 null 時不註冊（intent 回 unknown_intent）。前三步（no_character → in_battle → jailed）由 GameHost._run_intent 做。

const F := GameHost.NEEDS_CHAR | GameHost.IDLE

static func register(host: GameHost) -> void:
	var law = host.get("law")
	if law == null:
		return
	host.register(Protocol.I_BOUNTY_BOARD, func(s: Session, a: Dictionary) -> Dictionary:
		return law.board(s, str(a.get("npc", ""))), F)
	host.register(Protocol.I_BOUNTY_LICENSE, func(s: Session, a: Dictionary) -> Dictionary:
		return law.license(s, str(a.get("npc", ""))), F)
	host.register(Protocol.I_BOUNTY_ADD, func(s: Session, a: Dictionary) -> Dictionary:
		return law.add(s, str(a.get("npc", "")), host.clean_text(str(a.get("target_name", "")), Protocol.STRING_MAX_LEN),
			_int(a.get("money", 0))), F)
	host.register(Protocol.I_BOUNTY_CLAIM, func(s: Session, a: Dictionary) -> Dictionary:
		return law.claim(s, str(a.get("npc", ""))), F)
	host.register(Protocol.I_CLEANSE, func(s: Session, a: Dictionary) -> Dictionary:
		return law.cleanse(s, str(a.get("npc", "")), str(a.get("what", "")), _int(a.get("times", 1))), F)

## JSON 數字轉 int
static func _int(v: Variant) -> int:
	if v is int:
		return v
	if v is float:
		return int(v)
	if v is String and (v as String).is_valid_int():
		return int(v)
	return 0
