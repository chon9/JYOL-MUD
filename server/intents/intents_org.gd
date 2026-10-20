class_name IntentsOrg
extends RefCounted
## 組織 intent（M3B_PLAN §6，WP-ORG）：org_found、org_sign、org_invite、org_reply、org_leave、org_kick、org_set_rank、
## org_rank_names、org_title、org_lead、org_disband、org_info。
## GameHost 依 M3B_INTENTS 以路徑載入本檔並呼叫 register(host)（L3）。

# §6 的 intent（Day-0 前用與 M3B_PLAN 完全相同的字面值；Protocol 有同名常數時以 test_m3b_org 驗證一致）
const I_ORG_FOUND := "org_found"
const I_ORG_SIGN := "org_sign"
const I_ORG_INVITE := "org_invite"
const I_ORG_REPLY := "org_reply"
const I_ORG_LEAVE := "org_leave"
const I_ORG_KICK := "org_kick"
const I_ORG_SET_RANK := "org_set_rank"
const I_ORG_RANK_NAMES := "org_rank_names"
const I_ORG_TITLE := "org_title"
const I_ORG_LEAD := "org_lead"
const I_ORG_DISBAND := "org_disband"
const I_ORG_INFO := "org_info"
const ALL := [I_ORG_FOUND, I_ORG_SIGN, I_ORG_INVITE, I_ORG_REPLY, I_ORG_LEAVE, I_ORG_KICK, I_ORG_SET_RANK,
	I_ORG_RANK_NAMES, I_ORG_TITLE, I_ORG_LEAD, I_ORG_DISBAND, I_ORG_INFO]

static func register(host: GameHost) -> void:
	install(host)

## 註冊處理器並回傳實際使用的 OrgSystem。優先用 GameHost 載入的 host.orgs；沒有時（Day-0 尚未接線或載入失敗）
## 由這裡建立一份只給這些處理器用的實例（此時沒有 tick／on_login：連署不會過期、ch.guild 不在登入時校正）。
static func install(host: GameHost) -> Variant:
	var orgs: Variant = host.get("orgs")
	if orgs == null:
		orgs = OrgSystem.new(host)
	var nc := GameHost.NEEDS_CHAR
	var idle := GameHost.NEEDS_CHAR | GameHost.IDLE
	# 在書吏面前的兩個動作比照其他 NPC 服務：戰鬥中不能做
	host.register(I_ORG_FOUND, func(s: Session, a: Dictionary) -> Dictionary:
		return orgs.found(s, str(a.get("npc", "")), str(a.get("name", ""))), idle)
	host.register(I_ORG_SIGN, func(s: Session, a: Dictionary) -> Dictionary:
		return orgs.sign(s, str(a.get("npc", "")), str(a.get("org", ""))), idle)
	host.register(I_ORG_INVITE, func(s: Session, a: Dictionary) -> Dictionary:
		return orgs.invite(s, str(a.get("name", ""))), nc)
	host.register(I_ORG_REPLY, func(s: Session, a: Dictionary) -> Dictionary:
		return orgs.reply(s, str(a.get("org", "")), bool(a.get("accept", false))), nc)
	host.register(I_ORG_LEAVE, func(s: Session, _a: Dictionary) -> Dictionary:
		return orgs.leave(s), nc)
	host.register(I_ORG_KICK, func(s: Session, a: Dictionary) -> Dictionary:
		return orgs.kick(s, str(a.get("name", ""))), nc)
	host.register(I_ORG_SET_RANK, func(s: Session, a: Dictionary) -> Dictionary:
		return orgs.set_rank(s, str(a.get("name", "")), int(a.get("rank", -1))), nc)
	host.register(I_ORG_RANK_NAMES, func(s: Session, a: Dictionary) -> Dictionary:
		var names: Variant = a.get("names", [])
		return orgs.set_rank_names(s, names if names is Array else []), nc)
	host.register(I_ORG_TITLE, func(s: Session, a: Dictionary) -> Dictionary:
		return orgs.set_title(s, str(a.get("name", "")), str(a.get("title", ""))), nc)
	host.register(I_ORG_LEAD, func(s: Session, a: Dictionary) -> Dictionary:
		return orgs.transfer(s, str(a.get("name", ""))), nc)
	host.register(I_ORG_DISBAND, func(s: Session, a: Dictionary) -> Dictionary:
		return orgs.disband(s, bool(a.get("confirm", false))), nc)
	host.register(I_ORG_INFO, func(s: Session, _a: Dictionary) -> Dictionary:
		return orgs.info(s), nc)
	return orgs
