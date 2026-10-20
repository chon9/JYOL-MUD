class_name IntentsBattle
extends RefCounted
## battle_cmd（M1_PLAN 3.6、3.4.3）。戰鬥中唯一可用的遊戲 intent（不檢查 in_battle）。
## battle_join（M2_PLAN 4.2，C+I）：中途加入同房隊友的戰鬥。

static func register(host: GameHost) -> void:
	host.register(Protocol.I_BATTLE_CMD, func(s: Session, a: Dictionary) -> Dictionary:
		return host.battles.submit(s, a), GameHost.NEEDS_CHAR)
	host.register(Protocol.I_BATTLE_JOIN, func(s: Session, a: Dictionary) -> Dictionary:
		return host.battles.join(s, int(a.get("battle_id", 0))), GameHost.NEEDS_CHAR | GameHost.IDLE)
