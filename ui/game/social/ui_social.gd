class_name UiSocial
extends RefCounted
## M2 社交／PK 介面的純邏輯（M2_PLAN 4.5、4.10）：名字顏色、玩家選單、強制 PK 前的本機檢查、待決提示倒數、
## 戰場鏡像座標、屍體狀態文字、斷線／拒絕原因的中文。只讀 sheet／view／world_info 字典，不碰節點，方便單元測試。

## 玩家選單的動作 id
const ACT_INVITE := "invite"
const ACT_CHALLENGE := "challenge"
const ACT_WHISPER := "whisper"
const ACT_MAIL := "mail"
const ACT_KICK := "kick"
const ACT_LEAD := "lead"
const ACT_FORCE_PK := "force_pk"
## M3b（M3B_PLAN §5.1.5、§5.3）：player_tags.seizable → 「捉拿」；我有邀請權且對方不在組織 → 「邀請入組織」
const ACT_SEIZE := "seize"
const ACT_ORG_INVITE := "org_invite"
const ACT_LABELS := {
	ACT_INVITE: "組隊邀請", ACT_CHALLENGE: "叫戰", ACT_WHISPER: "密語（傳音入密）", ACT_MAIL: "寄信（飛鴿傳書）",
	ACT_KICK: "請出隊伍", ACT_LEAD: "移交領隊", ACT_FORCE_PK: "強行出手",
	ACT_SEIZE: "捉拿", ACT_ORG_INVITE: "邀請入組織",
}

## 強制 PK 的「連結鍵」（M2_PLAN 5.2：2001 年的說明叫「連結鍵」，Ctrl 只見於 newton → 可在系統窗「特殊開關」改）
const PK_KEY_SETTING := "ui.pk_key"
const PK_KEY_DEFAULT := "ctrl"
const PK_KEYS := ["ctrl", "alt", "shift"]
const PK_KEY_LABELS := { "ctrl": "Ctrl", "alt": "Alt", "shift": "Shift" }

## 主機拒絕連線（hello）的原因
const REJECT_TEXT := {
	"protocol_mismatch": "版本不符（連線協定不同），請更新到和主機相同的版本。",
	"version_mismatch": "遊戲版本和主機不同。",
	"content_mismatch": "遊戲資料和主機不同（資料檔版本不一致）。",
	"bad_identity": "無法確認你的身分。",
	"banned": "你被主機禁止進入這個江湖。",
	"already_connected": "這個身分已經在江湖裡了。",
	"server_full": "江湖已經客滿了。",
	"hello_timeout": "連線逾時。",
}
## 被踢的原因（NetworkManager.kick(peer, reason)）
const KICK_TEXT := {
	"admin": "主機把你請出了江湖。",
	"banned": "主機把你請出了江湖，並禁止你再進來。",
	"replaced": "同一個身分從別處登入了。",
}
const HOST_FROZEN_TEXT := "主機已離線，江湖凍結。"

static func pk_key() -> String:
	var k := str(UiSettings.get_value(PK_KEY_SETTING, PK_KEY_DEFAULT))
	return k if k in PK_KEYS else PK_KEY_DEFAULT

static func pk_key_label(key := "") -> String:
	return str(PK_KEY_LABELS.get(key if key != "" else pk_key(), "Ctrl"))

## 這次點擊有沒有按著強制 PK 的連結鍵（Ctrl 在 macOS 也接受 Command）
static func pk_modifier_down(ev: InputEventWithModifiers, key := "") -> bool:
	if ev == null:
		return false
	match key if key != "" else pk_key():
		"alt":
			return ev.alt_pressed
		"shift":
			return ev.shift_pressed
	return ev.ctrl_pressed or ev.meta_pressed

## 選單動作的文字（強行出手帶目前的連結鍵）
static func act_label(act: String) -> String:
	if act == ACT_FORCE_PK:
		return "%s（%s+點名字）" % [ACT_LABELS[ACT_FORCE_PK], pk_key_label()]
	return str(ACT_LABELS.get(act, act))

## 強行出手確認框的內文（M2_PLAN 5.2）：善惡的變化依對方的善惡（view.players[].align：殺惡人 +10、其餘 −10），
## 並寫明兩個守衛條件（【已證實】善惡為負、PK 值超過 3）；有自己的角色表時算出殺後的善惡／PK 值，會挨打就直說（M2 審查）
static func force_pk_confirm_text(player: Dictionary, my_sheet: Dictionary = {}) -> String:
	var who := str(player.get("name", "?"))
	var evil := str(player.get("align", "")) == UiKeys.ALIGN_EVIL
	var d := MoralityPk.kill_deltas(MoralityPk.KIND_FORCED, MoralityPk.ALIGN_EVIL_MAX if evil else 0)
	var dm := int(d["morality"])
	var moral := "對方是惡人，善惡反而變好（+%d）" % dm if evil else "善惡變差（%d）" % dm
	var t := "確定要對%s強行出手？
殺死對方：PK 值 +1、殺氣 +%d，%s。
" % [who, int(d["killing_intent"]), moral]
	t += "善惡變負、或 PK 值超過 3，進出城都會被守城官兵攻擊。"
	if my_sheet.has("morality") or my_sheet.has("pk"):
		var m_after := MoralityPk.clamp_morality(UiBuild.num(my_sheet.get("morality", 0)) + dm)
		var pk_after := UiBuild.num(my_sheet.get("pk", 0)) + int(d["pk"])
		if MoralityPk.guard_count(pk_after, m_after) > 0:
			t += "
殺了之後你的善惡 %d、PK 值 %d：下次進出城就會有官兵出手。" % [m_after, pk_after]
	return t

## 伺服器設定的玩家名單一行：角色名（遊戲裡看到的名字）為主，Steam／設定檔名稱與身分縮寫放後面
static func admin_player_label(p: Dictionary) -> String:
	var char_name := str(p.get("char_name", ""))
	var head := char_name if char_name != "" else "（未選角）"
	var t := "%s　（%s・%s）" % [head, str(p.get("name", "?")), str(p.get("identity_short", ""))]
	if bool(p.get("is_admin", false)):
		t += "　管理員"
	return t

## 名字顏色：惡藍、中立黃、善白（未知 → 中立）
static func align_color(align: String) -> Color:
	return UiKeys.ALIGN_COLORS.get(align, UiKeys.ALIGN_COLORS[UiKeys.ALIGN_NEUTRAL])

## 名字顏色在淺色卷軸上要加深色描邊（善＝白字）
static func needs_outline(align: String) -> bool:
	return align != UiKeys.ALIGN_EVIL

# ---------------------------------------------------------------- 隊伍

static func party(sheet: Dictionary) -> Dictionary:
	var p: Variant = sheet.get("party", {})
	return p if p is Dictionary else {}

static func in_party(sheet: Dictionary) -> bool:
	return not party(sheet).is_empty() and str(party(sheet).get("id", "")) != ""

static func is_leader(sheet: Dictionary) -> bool:
	var me := str(sheet.get("char_id", ""))
	return in_party(sheet) and me != "" and str(party(sheet).get("leader", "")) == me

static func members(sheet: Dictionary) -> Array:
	var m: Variant = party(sheet).get("members", [])
	return m if m is Array else []

static func in_my_party(sheet: Dictionary, char_id: String) -> bool:
	if char_id == "":
		return false
	for m in members(sheet):
		if m is Dictionary and str(m.get("char_id", "")) == char_id:
			return true
	return false

## 隊伍成員一行的文字：「★名字　所在地　戰鬥中」
## 隊伍列的全文（提示框用）；with_battle = false 時不含「戰鬥中」（面板另放一個不會被截掉的標籤）
static func member_line(m: Dictionary, with_battle := true) -> String:
	var parts: PackedStringArray = []
	parts.append(("★" if bool(m.get("leader", false)) else "　") + str(m.get("name", "?")))
	if not bool(m.get("online", true)):
		parts.append("（離線）")
	elif str(m.get("room_name", "")) != "":
		parts.append(str(m.get("room_name", "")))
	if with_battle and bool(m.get("in_battle", false)):
		parts.append("戰鬥中")
	return "　".join(parts)

## 隊伍列的「戰鬥中」標籤（M2 審查：名字長時整行被截斷，戰鬥中永遠看不到，而這正是決定要不要去幫忙的資訊）
static func member_battle_tag(m: Dictionary) -> String:
	return "戰鬥中" if bool(m.get("in_battle", false)) and bool(m.get("online", true)) else ""

# ---------------------------------------------------------------- 玩家

static func is_self(player: Dictionary, my_peer: int, my_char: String) -> bool:
	if my_char != "" and str(player.get("char_id", "")) == my_char:
		return true
	return my_peer != 0 and int(player.get("peer", -1)) == my_peer

## 場景卷軸點玩家名的選單：[[action, label], …]
static func player_menu(player: Dictionary, sheet: Dictionary) -> Array:
	var out: Array = []
	var cid := str(player.get("char_id", ""))
	var mate := in_my_party(sheet, cid)
	if not mate:
		out.append([ACT_INVITE, act_label(ACT_INVITE)])
		out.append([ACT_CHALLENGE, act_label(ACT_CHALLENGE)])
	out.append([ACT_WHISPER, act_label(ACT_WHISPER)])
	out.append([ACT_MAIL, act_label(ACT_MAIL)])
	if mate and is_leader(sheet):
		out.append([ACT_KICK, act_label(ACT_KICK)])
		out.append([ACT_LEAD, act_label(ACT_LEAD)])
	if OrgUi.can_invite_player(player, sheet):
		out.append([ACT_ORG_INVITE, act_label(ACT_ORG_INVITE)])
	if bool(player.get("seizable", false)):
		out.append([ACT_SEIZE, act_label(ACT_SEIZE)])
	if not mate:
		out.append([ACT_FORCE_PK, act_label(ACT_FORCE_PK)])
	return out

## 強制 PK 送出前在本機就能確定不行的原因碼（"" = 可以送，交給主機判定）。
## M2_PLAN 4.10：newbie 或 pk_allowed == false 直接顯示原因、不送；PK 模式與同隊也是確定的，一起擋。
static func force_pk_block(player: Dictionary, view: Dictionary, sheet: Dictionary, pk_mode: String) -> String:
	if pk_mode == "OFF":
		return "pk_disabled"
	if pk_mode == "CHALLENGE_ONLY":
		return "pk_challenge_only"
	if not bool(view.get("pk_allowed", false)):
		return "pk_not_allowed_here"
	if in_my_party(sheet, str(player.get("char_id", ""))):
		return "target_in_party"
	if bool(player.get("newbie", false)):
		return "target_newbie_protected"
	return ""

## 叫戰的本機檢查（同上，但不看新手）
static func challenge_block(player: Dictionary, view: Dictionary, sheet: Dictionary, pk_mode: String) -> String:
	if pk_mode == "OFF":
		return "pk_disabled"
	if not bool(view.get("pk_allowed", false)):
		return "pk_not_allowed_here"
	if in_my_party(sheet, str(player.get("char_id", ""))):
		return "target_in_party"
	return ""

## 玩家名的提示框
static func player_tip(player: Dictionary) -> String:
	var parts: PackedStringArray = []
	parts.append(str(UiKeys.ALIGN_LABELS.get(str(player.get("align", "")), "中立")))
	if bool(player.get("newbie", false)):
		parts.append("新手")
	if str(player.get("party_id", "")) != "":
		parts.append("有隊伍")
	if bool(player.get("in_battle", false)):
		parts.append("戰鬥中")
	return "%s（%s）\n左鍵：選單；%s+左鍵：強行出手" % [str(player.get("name", "?")), "、".join(parts), pk_key_label()]

# ---------------------------------------------------------------- 待決邀請／叫戰（4.5.1 sheet.pending）

## 依 sheet.pending 列出要顯示的提示：[{ type: "party"|"challenge", from_char, name, left }]，left 是本機倒數後的秒數（≥ 0）。
## rx_ms：收到這份 sheet 的本機時刻（ClientState 蓋的 CooldownTracker.RX_KEY）；now_ms：現在
static func pending_rows(sheet: Dictionary, now_ms: int) -> Array:
	var out: Array = []
	var pend: Variant = sheet.get("pending", {})
	if not (pend is Dictionary):
		return out
	var rx := int(sheet.get(CooldownTracker.RX_KEY, now_ms))
	var elapsed := maxf(0.0, float(now_ms - rx) / 1000.0)
	var inv: Variant = (pend as Dictionary).get("party_invite", {})
	if inv is Dictionary and str((inv as Dictionary).get("from_char", "")) != "":
		out.append(_pending_row("party", inv, elapsed))
	for c in (pend as Dictionary).get("challenges", []):
		if c is Dictionary and str(c.get("from_char", "")) != "":
			out.append(_pending_row("challenge", c, elapsed))
	# M3b 組織邀請（sheet.pending.org_invite；M3B_PLAN §5.3「組織邀請用既有 pending prompt」）
	for o in OrgUi.pending_invites(sheet):
		out.append(org_row(o, elapsed))
	return out.filter(func(r): return int(r["left"]) > 0)

## 組織邀請的提示列：from_char 放組織 id（pending_key 用），org 另存
static func org_row(o: Dictionary, elapsed: float) -> Dictionary:
	var r := _pending_row("org", { "from_char": str(o.get("org", "")), "name": str(o.get("from_name", o.get("name", ""))),
		"left_s": o.get("left_s", o.get("ttl_s", 60)) }, elapsed)
	r["org"] = str(o.get("org", ""))
	r["org_name"] = str(o.get("org_name", ""))
	r["petition_name"] = str(o.get("petition_name", ""))   # M3b 審查 4：接受會讓自己發起的連署作廢
	return r

static func _pending_row(type: String, d: Dictionary, elapsed: float) -> Dictionary:
	return { "type": type, "from_char": str(d.get("from_char", "")), "name": str(d.get("name", "?")),
		"left": maxi(0, ceili(float(d.get("left_s", 0)) - elapsed - 1e-6)) }

static func pending_text(row: Dictionary) -> String:
	return "%s%s" % [pending_head(row), pending_countdown(row)]

## 提示的主文（不含倒數）；倒數另放一個不換行的標籤（M2 審查：「（60」「秒）」被拆成兩行）
static func pending_head(row: Dictionary) -> String:
	if str(row.get("type", "")) == "org":
		return OrgUi.invite_head(row)
	if str(row.get("type", "")) == "party":
		return "%s邀請你加入隊伍" % str(row.get("name", "?"))
	return "%s向你叫戰！%s" % [str(row.get("name", "?")), CHALLENGE_RISK_SHORT]

## 叫戰的風險說明（M2_PLAN 5.2：叫戰擊殺是真的死亡——屍體、死亡規則的懲罰，殺人者殺氣 +100；M2 審查）
const CHALLENGE_RISK_SHORT := "（生死自負）"
const CHALLENGE_RISK := "接受就是生死決鬥：輸了會死（照死亡規則受罰、留下屍體），對方殺氣 +100。"

static func pending_countdown(row: Dictionary) -> String:
	return "（%d 秒）" % int(row.get("left", 0))

static func pending_key(row: Dictionary) -> String:
	return "%s:%s" % [str(row.get("type", "")), str(row.get("from_char", ""))]

# ---------------------------------------------------------------- 飛鴿

static func mail_unread(sheet: Dictionary) -> int:
	return UiBuild.num(sheet.get("mail_unread", 0))

static func pigeon_blinks(sheet: Dictionary) -> bool:
	return mail_unread(sheet) > 0

## 鴿章閃爍的透明度（週期 1 秒）
static func blink_alpha(now_ms: int) -> float:
	var t := float(now_ms % 1000) / 1000.0
	return 0.45 + 0.55 * (0.5 + 0.5 * cos(t * TAU))

# ---------------------------------------------------------------- 屍體

## 屍體狀態：保護期（本人與授權者可撿）或公開期；left_s 是目前這個階段還剩幾秒（真實秒數）
static func corpse_status(c: Dictionary, left: int) -> String:
	if bool(c.get("public", false)):
		return "已過保護時間，誰都能翻動（%s後消失）" % duration_text(left)
	# 自己的屍體寫「只有你和你允許的人」（M2 第三輪審查：對擁有者說「本人和他」讀起來像在說別人）
	if bool(c.get("mine", false)):
		return "保護期還剩 %s（只有你和你允許的人能翻動）" % duration_text(left)
	return "保護期還剩 %s（只有本人和他允許的人能翻動）" % duration_text(left)

static func duration_text(secs: int) -> String:
	secs = maxi(0, secs)
	if secs >= 60:
		return "%d 分 %d 秒" % [secs / 60, secs % 60]
	return "%d 秒" % secs

## 自己的屍體寫「我的屍體」，不再加「自己的」（M2 審查：「X的屍體（2 件）　自己的」重複又擠到按鈕邊）
static func corpse_label(c: Dictionary) -> String:
	var n := UiBuild.num(c.get("n_items", 0))
	if bool(c.get("mine", false)):
		return "我的屍體（%d 件）" % n
	var t := "%s的屍體（%d 件）" % [str(c.get("owner_name", "?")), n]
	if bool(c.get("can_loot", false)):
		t += "　可翻動"
	return t

static func find_corpse(view: Dictionary, corpse_id: String) -> Dictionary:
	for c in view.get("corpses", []):
		if c is Dictionary and str(c.get("id", "")) == corpse_id:
			return c
	return {}

# ---------------------------------------------------------------- 戰場鏡像（4.5.3）

## my_side == 1 時 x' = (w − 1) − x（12 寬：11 − x），讓自己永遠在左邊；往返同一個公式
static func mirror_cell(c: Vector2i, w: int) -> Vector2i:
	if c.x < 0:
		return c
	return Vector2i(w - 1 - c.x, c.y)

static func mirror_arr(v: Variant, w: int) -> Variant:
	if v is Array and (v as Array).size() >= 2:
		return [w - 1 - int(v[0]), int(v[1])]
	if v is Vector2i:
		return mirror_cell(v, w)
	return v

## 戰鬥中玩家數字：同房進行中戰鬥的按鈕文字
static func battle_label(b: Dictionary) -> String:
	var names: Variant = b.get("names", [[], []])
	var a: PackedStringArray = []
	var d: PackedStringArray = []
	if names is Array and (names as Array).size() >= 2:
		for n in names[0]:
			a.append(str(n))
		for n in names[1]:
			d.append(str(n))
	var kind := str(UiKeys.BATTLE_KIND_LABELS.get(str(b.get("kind", "")), ""))
	return "%s%s 對 %s" % ["【%s】" % kind if kind != "" else "", "、".join(a), "、".join(d)]

# ---------------------------------------------------------------- 連線

static func reject_text(reason: String) -> String:
	return str(REJECT_TEXT.get(reason, "主機拒絕連線：" + reason))

static func kick_text(reason: String) -> String:
	return str(KICK_TEXT.get(reason, "被主機請出：" + reason))
