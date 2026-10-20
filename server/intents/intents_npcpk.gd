## （不設 class_name：GameHost 依 M3C_INTENTS 以路徑 load()，N4）
extends RefCounted
## npc_attack { npc, mode? }（M3C_PLAN §5.3、§8）：對標了 attack 的 NPC 動手。mode "ATTACK"（Ctrl+點，預設）或 "MIEPAI"（對話選單「滅派」）。
## 旗標 NEEDS_CHAR | IDLE（戰鬥中回 in_battle）；坐牢中由 SectSystem.jail_gate 擋（jailed）。

const CI := GameHost.NEEDS_CHAR | GameHost.IDLE

static func register(host: GameHost) -> void:
	host.register(Protocol.I_NPC_ATTACK, func(s: Session, a: Dictionary) -> Dictionary:
		var sys = host.get("npcpk")
		if sys == null:
			return GameHost.fail(Protocol.R_NPC_ATTACK_OFF)
		return sys.attack(s, str(a["npc"]), str(a.get("mode", "ATTACK"))), CI)
