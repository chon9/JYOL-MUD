## （不設 class_name：GameHost 依 M3A_INTENTS 以路徑 load()，K3／H4）
extends RefCounted
## M3a 門派 intent（M3A_PLAN 6.1、6.12）：sect_betray、jail_ransom、sect_trial、npc_guide；M3b 加 beg（M3B_PLAN §5.1.2）。
## host.sects 為 null 時不註冊（intent 回 unknown_intent）。
## 驗證順序的前三步（no_character → in_battle → jailed）由 GameHost._run_intent 做（NEEDS_CHAR、IDLE、坐牢關卡）。

const F := GameHost.NEEDS_CHAR | GameHost.IDLE

static func register(host: GameHost) -> void:
	if host.get("sects") == null:
		return
	host.register(Protocol.I_SECT_BETRAY, func(s: Session, a: Dictionary) -> Dictionary:
		return betray(host, s, a), F)
	host.register(Protocol.I_JAIL_RANSOM, func(s: Session, a: Dictionary) -> Dictionary:
		return host.sects.ransom(s, str(a["npc"]), str(a["name"])), F)
	host.register(Protocol.I_SECT_TRIAL, func(s: Session, a: Dictionary) -> Dictionary:
		return host.sects.start_trial(s, str(a["npc"])), F)
	host.register(Protocol.I_NPC_GUIDE, func(s: Session, a: Dictionary) -> Dictionary:
		return host.sects.guide(s, str(a["npc"])), F)
	# M3B_PLAN §5.1.2：乞討（no_character → in_battle → jailed 由 GameHost 做；其餘在 SectSystem.beg）
	host.register(Protocol.I_BEG, func(s: Session, a: Dictionary) -> Dictionary:
		return host.sects.beg(s, str(a["npc"])), F)

## sect_betray（§6.5）：npc 檢查（not_here → no_service → closed_night）→ 不是本派掌門 no_service → need_confirm → 叛派
static func betray(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var npc := str(a["npc"])
	var r := host.npc_check(s, npc, "BETRAY")
	if r != "":
		return GameHost.fail(r)
	var sid := str(s.character.sect)
	if sid == "" or host.sects.npc_sect(npc) != sid:
		return GameHost.fail("no_service")
	if a.get("confirm", false) != true:
		return GameHost.fail(Protocol.R_NEED_CONFIRM)
	var res: Dictionary = host.sects.betray(s, npc)
	if res.get("ok", false):
		host.npcs.refresh_menu(s, npc)
	return res
