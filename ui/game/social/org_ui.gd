class_name OrgUi
extends RefCounted
## 組織（M3B_PLAN §5.3、§7.4）的純函式：角色表 org、org_info payload 的整理、各操作的權限、名字檢查、
## 玩家選單「邀請入組織」、待回覆邀請。只讀字典，權限只是介面提示（主機才是判定者）。
##
## # M3B_PLAN 缺漏：org_info（ui）的 payload 形狀由 WP-ORG 定（§9.3 Day-0「先寫成 _org.json 註解」），本文件沒寫。
## 這裡照 §4.13 world.guilds 與 §5.3 角色表 org 讀，兩種寫法都接受：
##   { org: { id, name, status, leader_name, rank, rank_name, title, … }|null, members: [ … ]|{ char_id: … }, rank_names, societies, member_max }
##   或把 org 的欄位直接攤在 payload 頂層（id、name、members…）。
## 成員列欄位：char_id、name、rank、rank_name（沒有就用 rank_names[rank]）、title、online、leader。

const ROLE_LEADER := 0
const ROLE_VICE := 1
const ROLE_MEMBER := 4

static func sheet_org(sheet: Dictionary) -> Dictionary:
	var o: Variant = sheet.get("org", null)
	return o if o is Dictionary else {}

static func in_org(sheet: Dictionary) -> bool:
	return str(OrgUi.sheet_org(sheet).get("id", "")) != ""

static func my_rank(sheet: Dictionary) -> int:
	var o := OrgUi.sheet_org(sheet)
	return UiBuild.num(o.get("rank", ROLE_MEMBER)) if not o.is_empty() else -1

## 會籍（天地會等；sheet.societies 或 org_info.societies）
static func societies(d: Dictionary) -> Array:
	var s: Variant = d.get("societies", [])
	return (s as Array).map(func(x): return str(x)) if s is Array else []

## org_info payload → { org: {}, members: [], rank_names: [5], societies: [], member_max }
static func normalize_info(p: Dictionary) -> Dictionary:
	var org: Dictionary = {}
	if p.get("org", null) is Dictionary:
		org = (p["org"] as Dictionary).duplicate()
	elif str(p.get("id", "")) != "":
		org = p.duplicate()
	var raw: Variant = p.get("members", org.get("members", []))
	var rank_names: Array = []
	var rn: Variant = p.get("rank_names", org.get("rank_names", []))
	if rn is Array:
		for x in rn:
			rank_names.append(str(x))
	for i in range(rank_names.size(), UiKeys.ORG_RANKS):
		rank_names.append(str(UiKeys.ORG_DEFAULT_RANK_NAMES[i]))
	var members: Array = []
	if raw is Array:
		for m in raw:
			if m is Dictionary:
				members.append(OrgUi._member(m, rank_names))
	elif raw is Dictionary:
		for cid in raw:
			var m: Variant = raw[cid]
			if m is Dictionary:
				var mm: Dictionary = (m as Dictionary).duplicate()
				if not mm.has("char_id"):
					mm["char_id"] = str(cid)
				members.append(OrgUi._member(mm, rank_names))
	members.sort_custom(func(a, b):
		if int(a["rank"]) != int(b["rank"]):
			return int(a["rank"]) < int(b["rank"])
		if bool(a["online"]) != bool(b["online"]):
			return bool(a["online"])
		return str(a["name"]) < str(b["name"]))
	org.erase("members")
	return {
		"org": org,
		# M3b 審查：主機給的我的權限（連署中的發起人沒有成員列，只能靠它知道自己能撤回）
		"my": (p["my"] as Dictionary).duplicate() if p.get("my", null) is Dictionary else {},
		"members": members,
		"rank_names": rank_names,
		"societies": OrgUi.societies(p) if p.has("societies") else OrgUi.societies(org),
		"member_max": UiBuild.num(p.get("member_max", org.get("member_max", UiClient.world_info().get("org_member_max", 50)))),
	}

static func _member(m: Dictionary, rank_names: Array) -> Dictionary:
	var r := clampi(UiBuild.num(m.get("rank", ROLE_MEMBER)), 0, UiKeys.ORG_RANKS - 1)
	return {
		"char_id": str(m.get("char_id", m.get("id", ""))),
		"name": str(m.get("name", "?")),
		"rank": r,
		"rank_name": str(m.get("rank_name", rank_names[r] if r < rank_names.size() else "")),
		"title": str(m.get("title", "")),
		"online": bool(m.get("online", false)),
	}

## 一列成員的文字：「● 天天　幫主　「鐵掌」」
static func member_line(m: Dictionary) -> String:
	var t := "%s %s　%s" % ["●" if bool(m.get("online", false)) else "○", str(m.get("name", "?")), str(m.get("rank_name", ""))]
	if str(m.get("title", "")) != "":
		t += "　「%s」" % str(m["title"])
	return t

## 標題列：「江湖小築（成員 3／50，在線 2）」
static func org_header(info: Dictionary) -> String:
	var org: Dictionary = info.get("org", {})
	var ms: Array = info.get("members", [])
	var online := ms.filter(func(m): return bool(m.get("online", false))).size()
	if str(org.get("status", "")) == "PETITION":
		# 整合者（M3b 截圖審查）：連署中還沒有成員，「成員 0／50」看不出進度 → 改寫連署人數
		var pt: Variant = org.get("petition", null)
		if pt is Dictionary:
			return "%s　連署中（%d／%d 人簽名）" % [str(org.get("name", "")), UiBuild.num(pt.get("signed", 0)), UiBuild.num(pt.get("need", 0))]
		return "%s　連署中" % str(org.get("name", ""))
	return "%s（成員 %d／%d，在線 %d）" % [str(org.get("name", "")), ms.size(), UiBuild.num(info.get("member_max", 50)), online]

## 我的位階與封號：「你的位階：堂主　封號：鐵掌」
static func my_line(info: Dictionary, my_char: String, sheet: Dictionary) -> String:
	var rank := -1
	var rank_name := ""
	var title := ""
	for m in info.get("members", []):
		if str(m.get("char_id", "")) == my_char and my_char != "":
			rank = int(m["rank"])
			rank_name = str(m["rank_name"])
			title = str(m["title"])
	if rank < 0:
		var o := OrgUi.sheet_org(sheet)
		if o.is_empty():
			o = info.get("org", {})
		rank = UiBuild.num(o.get("rank", -1))
		rank_name = str(o.get("rank_name", ""))
		title = str(o.get("title", ""))
	if rank < 0:
		return ""
	return "你的位階：%s　封號：%s" % [rank_name if rank_name != "" else str(UiKeys.ORG_DEFAULT_RANK_NAMES[clampi(rank, 0, 4)]),
		title if title != "" else "（無）"]

## 我在 info 裡的位階（成員列 → 主機的 my.rank → 角色表）
static func rank_in(info: Dictionary, my_char: String, sheet: Dictionary) -> int:
	for m in info.get("members", []):
		if my_char != "" and str(m.get("char_id", "")) == my_char:
			return int(m["rank"])
	var my: Variant = info.get("my", {})
	if my is Dictionary and (my as Dictionary).has("rank"):
		return UiBuild.num(my["rank"])
	var o := OrgUi.sheet_org(sheet)
	return UiBuild.num(o.get("rank", -1)) if not o.is_empty() else UiBuild.num((info.get("org", {}) as Dictionary).get("rank", -1))

# ---------------------------------------------------------------- 權限（§5.3）
static func can_invite(rank: int) -> bool:
	return rank >= 0 and rank <= ROLE_VICE

## 開除：對方位階數字大於自己；幫主不能被踢
static func can_kick(rank: int, target_rank: int) -> bool:
	return rank >= 0 and target_rank > rank and target_rank != ROLE_LEADER

static func can_set_rank(rank: int) -> bool:
	return rank == ROLE_LEADER

static func can_title(rank: int) -> bool:
	return rank >= 0 and rank <= ROLE_VICE

static func can_rank_names(rank: int) -> bool:
	return rank == ROLE_LEADER

static func can_transfer(rank: int) -> bool:
	return rank == ROLE_LEADER

static func can_disband(rank: int) -> bool:
	return rank == ROLE_LEADER

## 連署中（還沒成立）的組織：info.org.status == PETITION
static func is_petition(info: Dictionary) -> bool:
	var o: Variant = info.get("org", {})
	return o is Dictionary and str((o as Dictionary).get("status", "")) == "PETITION"

## 退出：幫主要先移交或解散（leader_must_transfer）
static func leave_block(rank: int) -> String:
	if rank < 0:
		return "no_guild"
	return "leader_must_transfer" if rank == ROLE_LEADER else ""

# ---------------------------------------------------------------- 名字
## 單一字元是不是中日韓文字或數字（§5.3：組織名只能中日韓文字與數字）
static func is_cjk_or_digit(c: String) -> bool:
	if c.length() != 1:
		return false
	var u := c.unicode_at(0)
	return (u >= 0x30 and u <= 0x39) or (u >= 0xFF10 and u <= 0xFF19) \
		or (u >= 0x4E00 and u <= 0x9FFF) or (u >= 0x3400 and u <= 0x4DBF) or (u >= 0xF900 and u <= 0xFAFF) \
		or (u >= 0x20000 and u <= 0x2FA1F) or (u >= 0x3040 and u <= 0x30FF) or (u >= 0xAC00 and u <= 0xD7AF) \
		or (u >= 0x1100 and u <= 0x11FF) or (u >= 0x3130 and u <= 0x318F)

## 組織名：2–8 個字、只能中日韓文字與數字 → 原因碼（"" = 可送）
static func name_block(name: String) -> String:
	var n := name.strip_edges()
	if n.length() < UiKeys.ORG_NAME_MIN or n.length() > UiKeys.ORG_NAME_MAX:
		return "bad_org_name"
	for i in n.length():
		if not OrgUi.is_cjk_or_digit(n[i]):
			return "bad_org_name"
	return ""

static func rank_name_ok(name: String) -> bool:
	var n := name.strip_edges()
	return n.length() >= 1 and n.length() <= UiKeys.ORG_RANK_NAME_MAX

static func title_ok(title: String) -> bool:
	return title.strip_edges().length() <= UiKeys.ORG_TITLE_MAX

const LOCAL_TEXT := {
	"bad_org_name": "組織名要 2–8 個字，只能用中文字（或日韓文字）與數字",
	"bad_rank_name": "位階名稱每個 1–4 個字",
	"bad_title": "封號最多 6 個字",
	"need_target": "請先在成員表選一個人",
	"need_name": "請填對方的角色名",
	"leader_must_transfer": "幫主要先把組織移交給別人，或解散組織，才能退出",
	"no_guild": "你不在任何組織裡",
	"disband_word": "請輸入組織名確認",
}

static func local_text(code: String) -> String:
	return str(LOCAL_TEXT.get(code, UiClient.reason_inline(code)))

## 解散第二段：輸入的字要和組織名完全相同
static func disband_word_ok(typed: String, org_name: String) -> bool:
	return org_name != "" and typed.strip_edges() == org_name

# ---------------------------------------------------------------- 書吏（npc_menu.org）
## npc_menu.org：{ petitions: [ { id, name, leader_name, signed, need } ], can_found, fee }
static func clerk(menu: Dictionary) -> Dictionary:
	var o: Variant = menu.get("org", null)
	return o if o is Dictionary else {}

## 創立條件文字（費用、名聲門檻、連署人數）
static func found_text(c: Dictionary) -> String:
	var wi := UiClient.world_info()
	var fee := UiBuild.num(c.get("fee", wi.get("org_found_fee", 10000)))
	var fame := UiBuild.num(c.get("found_fame", wi.get("org_found_fame", 150)))
	var signers := UiBuild.num(c.get("signers", wi.get("guild_signers", 3)))
	var sfame := UiBuild.num(c.get("signer_fame", wi.get("org_signer_fame", 20)))
	var days := UiBuild.num(c.get("petition_days", wi.get("org_petition_days", 3)))
	return "創立組織：手續費 %s（連署沒成立全額退還），發起人名聲 %d 以上；%d 遊戲日內要有 %d 位名聲 %d 以上的人到各城衙門連署。" % [
		SectUi.money_text(fee), fame, days, signers, sfame]

static func petition_line(p: Dictionary) -> String:
	var t := "「%s」　發起人 %s　已連署 %d／%d" % [str(p.get("name", "")), str(p.get("leader_name", "?")),
		UiBuild.num(p.get("signed", 0)), UiBuild.num(p.get("need", 0))]
	var left := petition_left_text(p)
	if left != "":
		t += "　" + left
	if p.get("mine", false) == true:
		t += "　（你發起的）"
	return t

## M3b 審查 3：連署剩餘時間（主機給 left_s 真實秒數）→「還剩 1 小時 20 分」；沒有欄位回 ""
static func petition_left_text(p: Variant) -> String:
	if not (p is Dictionary) or not (p as Dictionary).has("left_s"):
		return ""
	var left := float((p as Dictionary).get("left_s", 0))
	if left <= 0.0:
		return "（即將到期）"
	return "還剩 %s" % SectUi.duration_text(left)

# ---------------------------------------------------------------- 玩家選單、待回覆邀請
## 玩家選單要不要有「邀請入組織」：我有邀請權、對方 player_tags.org_name 是空的（有這個欄位才算知道）
static func can_invite_player(player: Dictionary, sheet: Dictionary) -> bool:
	if not OrgUi.in_org(sheet) or not OrgUi.can_invite(OrgUi.my_rank(sheet)):
		return false
	return player.has("org_name") and str(player.get("org_name", "")) == ""

## 待回覆的組織邀請（sheet.pending.org_invite 或 org_invites；單筆或陣列）→ [{ org, org_name, from_name, left_s }]
static func pending_invites(sheet: Dictionary) -> Array:
	var out: Array = []
	var pend: Variant = sheet.get("pending", {})
	if not (pend is Dictionary):
		return out
	for k in ["org_invite", "org_invites"]:
		var v: Variant = (pend as Dictionary).get(k, null)
		var arr: Array = []
		if v is Dictionary:
			arr = [v]
		elif v is Array:
			arr = v
		for x in arr:
			if x is Dictionary and str((x as Dictionary).get("org", "")) != "":
				out.append(x)
	return out

## M3b 審查 4：受邀的人自己有連署中的組織 → 提示多一行（接受後那份連署作廢、手續費退還，主機 OrgSystem.reply）
static func invite_warning(row: Dictionary) -> String:
	var pn := str(row.get("petition_name", ""))
	if str(row.get("type", "org")) != "org" or pn == "":
		return ""
	return "接受後你發起的連署「%s」將作廢（退還手續費）" % pn

## 邀請提示的主文：「天天邀請你加入組織「江湖小築」」
static func invite_head(row: Dictionary) -> String:
	var who := str(row.get("name", row.get("from_name", "")))
	var org := str(row.get("org_name", ""))
	return "%s邀請你加入組織%s" % [who if who != "" else "有人", "「%s」" % org if org != "" else ""]
