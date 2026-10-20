class_name OrgSystem
extends RefCounted
## 組織（M3B_PLAN §5.3，WP-ORG）：創立連署、加入、退出、開除、位階、封號、移交、解散、組織頻道的成員查詢。
## 權威資料在 world.json 的 `guilds`（§4.13，惰性建立）；角色的 `guild` 只是快取，登入時（on_login）校正。
## 總壇、攻城、競標、傭兵、同盟宣戰留 M5（§1.2）。
## GameHost 以路徑 load() 建立本系統（L3）；本檔只透過 host 的公開函式工作，不引用其他 M3b 系統。
##
## world.guilds 的一列（§4.13；"leader_name"、"signer_names"、members[].name 是本系統自用的名字快取，離線成員也能顯示）：
##   { "id", "name", "status": "PETITION"/"ACTIVE", "leader": char_id, "leader_name", "created_s", "petition_until_s",
##     "signers": [char_id], "signer_names": { char_id: name },
##     "members": { char_id: { "rank": 0..4, "title": "", "joined_s", "name" } },
##     "rank_names": ["幫主","副幫主","長老","堂主","幫眾"], "invites": { char_id: until_world_s } }

const WORLD_KEY := "guilds"
const STATUS_PETITION := "PETITION"
const STATUS_ACTIVE := "ACTIVE"
const NPC_SERVICE := "ORG"

const RANK_LEADER := 0
const RANK_VICE := 1
const RANK_MEMBER := 4
const RANK_COUNT := 5
const DEFAULT_RANK_NAMES := ["幫主", "副幫主", "長老", "堂主", "幫眾"]

## 天地會不是組織：會籍是任務旗標（§5.3）
const SOCIETY_FLAGS := { "tdh_member": "天地會" }

# 名字與文字長度（§5.3）
const NAME_MIN := 2
const NAME_MAX := 8
const RANK_NAME_MIN := 1
const RANK_NAME_MAX := 4
const TITLE_MAX := 6

# §4.11 伺服器選項的預設（options.json 沒有時）
const DEFAULT_SIGNERS := 3
const DEFAULT_FOUND_FAME := 150
const DEFAULT_SIGNER_FAME := 20
const DEFAULT_FOUND_FEE := 10000
const DEFAULT_MEMBER_MAX := 50
const DEFAULT_PETITION_DAYS := 3
const DEFAULT_TTL_REAL_S := 60

# §6 事件 key（Day-0 前用與 M3B_PLAN 完全相同的字面值）
const E_ORG_INFO := "org_info"                       # ui
const E_ORG_PETITION := "org_petition"
const E_ORG_SIGNED := "org_signed"
const E_ORG_FOUNDED := "org_founded"
const E_ORG_PETITION_EXPIRED := "org_petition_expired"
const E_ORG_INVITE := "org_invite"                   # ui（pending prompt）
const E_ORG_JOINED := "org_joined"
const E_ORG_LEFT := "org_left"
const E_ORG_KICKED := "org_kicked"
const E_ORG_RANK_CHANGED := "org_rank_changed"
const E_ORG_TITLE_CHANGED := "org_title_changed"
const E_ORG_LEADER_CHANGED := "org_leader_changed"
const E_ORG_DISBANDED := "org_disbanded"
const E_ORG_FEE_REFUND := "org_fee_refund"        # M3b 審查：連署沒成立（過期、作廢、撤回）退手續費
## 連署沒成立時的退款暫存（world 鍵；離線的發起人下次登入領）
const REFUND_KEY := "org_refunds"

# 原因碼（§6；no_guild、no_invite、need_confirm、target_offline、not_enough_money 是既有的）
const R_NO_GUILD := "no_guild"
const R_ALREADY_IN_ORG := "already_in_org"
const R_REQ_FAME_MIN := "req_fame_min"
const R_NOT_ENOUGH_MONEY := "not_enough_money"
const R_BAD_ORG_NAME := "bad_org_name"
const R_ORG_NAME_TAKEN := "org_name_taken"
const R_ALREADY_PETITIONING := "already_petitioning"
const R_NOT_PETITION := "not_petition"
const R_ALREADY_SIGNED := "already_signed"
const R_ORG_FULL := "org_full"
const R_NO_PERMISSION := "no_permission"
const R_LEADER_MUST_TRANSFER := "leader_must_transfer"
const R_NO_INVITE := "no_invite"
const R_NO_SUCH_CHAR := "no_such_char"
const R_SELF_TARGET := "self_target"
const R_TARGET_OFFLINE := "target_offline"
const R_NEED_CONFIRM := "need_confirm"

var host     # GameHost（dispose() 時設成 null）

func _init(p_host) -> void:
	host = p_host

# ================================================================ 資料存取

## world.guilds（惰性建立；既有世界 SaveManager.new_world 已經放了空陣列）
func guilds() -> Array:
	var w: Dictionary = host.ws.world
	if not (w.get(WORLD_KEY) is Array):
		w[WORLD_KEY] = []
	return w[WORLD_KEY]

func find(org_id: String) -> Dictionary:
	if org_id == "":
		return {}
	for g in guilds():
		if g is Dictionary and str(g.get("id", "")) == org_id:
			return g
	return {}

## 角色所屬的 ACTIVE 組織（權威：members）；沒有 → {}
func org_of(char_id: String) -> Dictionary:
	if char_id == "":
		return {}
	for g in guilds():
		if g is Dictionary and str(g.get("status", "")) == STATUS_ACTIVE and _members(g).has(char_id):
			return g
	return {}

func org_id_of(char_id: String) -> String:
	return str(org_of(char_id).get("id", ""))

## 他發起、還在連署中的組織；沒有 → {}
func petition_of(char_id: String) -> Dictionary:
	for g in guilds():
		if g is Dictionary and str(g.get("status", "")) == STATUS_PETITION and str(g.get("leader", "")) == char_id:
			return g
	return {}

func _members(g: Dictionary) -> Dictionary:
	if not (g.get("members") is Dictionary):
		g["members"] = {}
	return g["members"]

func _invites(g: Dictionary) -> Dictionary:
	if not (g.get("invites") is Dictionary):
		g["invites"] = {}
	return g["invites"]

func _signers(g: Dictionary) -> Array:
	if not (g.get("signers") is Array):
		g["signers"] = []
	return g["signers"]

## M3b 審查 4：還算數的連署人（不是發起人、還沒加入任何組織）。簽完後加入別的組織的人不算——
## 以前 sign()／tick() 直接數 signers，_activate() 才略過他們，結果有效連署人不夠也會成立
func valid_signer_count(g: Dictionary) -> int:
	var n := 0
	var leader := str(g.get("leader", ""))
	for cid in _signers(g):
		if str(cid) != leader and org_of(str(cid)).is_empty():
			n += 1
	return n

## 從所有連署中（except 以外）的名單移除這個人（他加入了組織；一個人只能在一個組織）
func _unsign_everywhere(char_id: String, except: Dictionary = {}) -> void:
	for other in guilds():
		if not (other is Dictionary) or is_same(other, except) or str(other.get("status", "")) != STATUS_PETITION:
			continue
		_signers(other).erase(char_id)
		if other.get("signer_names") is Dictionary:
			(other["signer_names"] as Dictionary).erase(char_id)

func rank_names(g: Dictionary) -> Array:
	var names: Variant = g.get("rank_names")
	if names is Array and (names as Array).size() == RANK_COUNT:
		return names
	return DEFAULT_RANK_NAMES.duplicate()

func rank_name(g: Dictionary, rank: int) -> String:
	var names := rank_names(g)
	return str(names[clampi(rank, 0, RANK_COUNT - 1)])

func member_rank(g: Dictionary, char_id: String) -> int:
	var m: Variant = _members(g).get(char_id)
	return int((m as Dictionary).get("rank", RANK_MEMBER)) if m is Dictionary else -1

func member_name(g: Dictionary, char_id: String) -> String:
	var o: Session = host.session_for_char(char_id)
	if o != null and o.character != null:
		return str(o.character.name)
	var m: Variant = _members(g).get(char_id)
	if m is Dictionary and str((m as Dictionary).get("name", "")) != "":
		return str(m["name"])
	if char_id == str(g.get("leader", "")) and str(g.get("leader_name", "")) != "":
		return str(g["leader_name"])
	var sn: Variant = g.get("signer_names")
	if sn is Dictionary and (sn as Dictionary).has(char_id):
		return str(sn[char_id])
	return str(host.pvp_char_name(char_id))

func leader_name(g: Dictionary) -> String:
	return member_name(g, str(g.get("leader", "")))

# ================================================================ 選項

func opt_int(key: String, fallback: int) -> int:
	return int(host.options.get(key, fallback))

func signers_needed() -> int:
	return maxi(1, opt_int("guild_signers", DEFAULT_SIGNERS))

func member_max() -> int:
	return maxi(2, opt_int("org_member_max", DEFAULT_MEMBER_MAX))

func found_fee() -> int:
	return maxi(0, opt_int("org_found_fee", DEFAULT_FOUND_FEE))

func found_fame() -> int:
	return opt_int("org_found_fame", DEFAULT_FOUND_FAME)

func signer_fame() -> int:
	return opt_int("org_signer_fame", DEFAULT_SIGNER_FAME)

# ================================================================ 純檢查

## 組織名：清理後 2–8 個字、只能中日韓文字與數字（§5.3）
static func valid_org_name(name: String) -> bool:
	var n := name.length()
	if n < NAME_MIN or n > NAME_MAX:
		return false
	for i in n:
		if not _is_cjk_or_digit(name.unicode_at(i)):
			return false
	return true

static func _is_cjk_or_digit(c: int) -> bool:
	return (c >= 0x30 and c <= 0x39) \
		or (c >= 0xFF10 and c <= 0xFF19) \
		or (c >= 0x4E00 and c <= 0x9FFF) \
		or (c >= 0x3400 and c <= 0x4DBF) \
		or (c >= 0x20000 and c <= 0x2FA1F) \
		or (c >= 0xF900 and c <= 0xFAFF) \
		or c == 0x3005 or c == 0x3007 \
		or (c >= 0x3040 and c <= 0x30FF) \
		or (c >= 0x31F0 and c <= 0x31FF) \
		or (c >= 0xAC00 and c <= 0xD7AF) \
		or (c >= 0x1100 and c <= 0x11FF) \
		or (c >= 0x3130 and c <= 0x318F)

func _clean(text: String, max_len: int) -> String:
	if host != null and host.has_method("clean_text"):
		return str(host.clean_text(text, max_len))
	return Protocol.clean_text(text, max_len)

func name_taken(name: String) -> bool:
	for g in guilds():
		if g is Dictionary and str(g.get("name", "")) == name:
			return true
	return reserved_name(name)

## M3b 審查 3【設計提案】：門派名（含「X派」「X」兩種寫法，全部 era 的門派）與天地會等秘密會社的名字不能拿來當組織名
## （組織名會顯示在玩家名字旁，org_info 也用「天地會」當會社名稱，同名會冒充）
func reserved_name(name: String) -> bool:
	for v in SOCIETY_FLAGS.values():
		if str(v) == name:
			return true
	var sects: Dictionary = {}
	if GameData != null and GameData.loader != null:
		sects = GameData.loader.all_tables.get("sects", {})
	if sects.is_empty() and host != null:
		sects = host.tables.get("sects", {})
	for sid in sects:
		var sn := str((sects[sid] as Dictionary).get("name", "")) if sects[sid] is Dictionary else ""
		if sn == "":
			continue
		var base := sn.trim_suffix("派")
		if name == sn or name == base or name == base + "派":
			return true
	return false

static func _fame(ch) -> int:
	return int(ch.fame) if ch != null and "fame" in ch else 0

# ================================================================ intent

## org_found（§5.3 創立）：NPC → already_in_org → req_fame_min → not_enough_money → bad_org_name／org_name_taken
## → already_petitioning → 扣手續費 → 建 PETITION、全服 org_petition。
## M3b 審查：連署沒成立（過期、發起人加入別的組織而作廢、撤回）全額退手續費【設計提案】（原本不退）
func found(s: Session, npc_id: String, name: String) -> Dictionary:
	var r: String = host.npc_check(s, npc_id, NPC_SERVICE)
	if r != "":
		return GameHost.fail(r)
	var ch = s.character
	var me := str(ch.id)
	if not org_of(me).is_empty():
		return GameHost.fail(R_ALREADY_IN_ORG)
	if _fame(ch) < found_fame():
		return GameHost.fail(R_REQ_FAME_MIN)
	var fee := found_fee()
	if int(ch.money) < fee:
		return GameHost.fail(R_NOT_ENOUGH_MONEY)
	var raw := name.strip_edges()
	var clean := _clean(raw, 64)
	if clean != raw or not valid_org_name(clean):
		return GameHost.fail(R_BAD_ORG_NAME)
	if name_taken(clean):
		return GameHost.fail(R_ORG_NAME_TAKEN)
	if not petition_of(me).is_empty():
		return GameHost.fail(R_ALREADY_PETITIONING)
	ch.add_money(-fee)
	var now: float = host.now_s()
	var days := maxi(1, opt_int("org_petition_days", DEFAULT_PETITION_DAYS))
	var g := {
		"id": host.new_id("g"), "name": clean, "status": STATUS_PETITION,
		"leader": me, "leader_name": str(ch.name), "created_s": now,
		"petition_until_s": now + float(days) * float(host.day_s()),
		"signers": [], "signer_names": {}, "members": {},
		"rank_names": DEFAULT_RANK_NAMES.duplicate(), "invites": {}, "fee": fee,
	}
	guilds().append(g)
	s.sheet_dirty = true
	# M3b 審查 4：扣手續費後馬上存（以前等下次自動存檔，兩次寫入之間當機手續費可能不見又退不回）。
	# 角色檔先、world.json 後（save_now 預設）：當機在兩次寫入之間時是「錢扣了、連署沒存」（損失），
	# 不會是「錢沒扣、連署在」——那樣連署過期還會再退一次手續費（複製）。同 EscortSystem.send 的順序
	if host.ws != null:
		host.ws.save_now()
	host.ws.broadcast_event(Protocol.CH_SYSTEM, E_ORG_PETITION, {
		"name": str(ch.name), "org_name": clean, "org": str(g["id"]), "peer": s.peer_id,
		"fee": fee, "signer_fame": signer_fame(), "need": signers_needed(), "days": days })
	# 門檻改低（主機設定 guild_signers）時，發起當下可能已經夠了：0 人時不會，這裡不必檢查
	_refresh_npc(s, npc_id)   # M3b 審查：書吏頁面馬上顯示連署中的組織
	return GameHost.ok({ "org": str(g["id"]) })

## 開著的書吏選單重送（npc_menu refresh: true；只更新已開著的選單）
func _refresh_npc(s: Session, npc_id: String) -> void:
	if s != null and host.get("npcs") != null and npc_id != "":
		host.npcs.refresh_menu(s, npc_id)

## org_sign（§5.3 連署）：NPC → 組織是 PETITION（not_petition）→ 自己不是發起人（self_target）→ 不在組織
## → 自己沒有發起中的連署（already_petitioning）→ 名聲 ≥ org_signer_fame → 沒簽過 → 簽滿 → ACTIVE
func sign(s: Session, npc_id: String, org_id: String) -> Dictionary:
	var r: String = host.npc_check(s, npc_id, NPC_SERVICE)
	if r != "":
		return GameHost.fail(r)
	var ch = s.character
	var me := str(ch.id)
	var g := find(org_id)
	if g.is_empty() or str(g.get("status", "")) != STATUS_PETITION:
		return GameHost.fail(R_NOT_PETITION)
	if str(g.get("leader", "")) == me:
		return GameHost.fail(R_SELF_TARGET)
	if not org_of(me).is_empty():
		return GameHost.fail(R_ALREADY_IN_ORG)
	# M3B_PLAN 缺漏：發起人去簽別人的連署沒有規定；兩邊都成立時他會同時是幫主與幫眾 → 擋下（already_petitioning）
	if not petition_of(me).is_empty():
		return GameHost.fail(R_ALREADY_PETITIONING)
	if _fame(ch) < signer_fame():
		return GameHost.fail(R_REQ_FAME_MIN)
	var signers := _signers(g)
	if me in signers:
		return GameHost.fail(R_ALREADY_SIGNED)
	signers.append(me)
	if not (g.get("signer_names") is Dictionary):
		g["signer_names"] = {}
	g["signer_names"][me] = str(ch.name)
	var need := signers_needed()
	var have := valid_signer_count(g)
	var p := { "name": str(ch.name), "org_name": str(g["name"]), "org": org_id, "signed": have,
		"need": need, "peer": s.peer_id }
	host.tell(s, Protocol.CH_SYSTEM, E_ORG_SIGNED, p.duplicate())
	var founder: Session = host.session_for_char(str(g.get("leader", "")))
	if founder != null:
		host.tell(founder, Protocol.CH_SYSTEM, E_ORG_SIGNED, p.duplicate())
	if have >= need:
		_activate(g)
	s.sheet_dirty = true
	_refresh_npc(s, npc_id)
	return GameHost.ok({ "org": org_id, "signed": have, "need": need })

## org_invite：已在組織 → 位階 ≤ 1（no_permission）→ 目標存在（no_such_char）、不是自己、在線（target_offline）
## → 目標不在組織（already_in_org）→ 人數 < org_member_max（org_full）→ 記邀請、目標收 org_invite（ui）
func invite(s: Session, target_name: String) -> Dictionary:
	var me := str(s.character.id)
	var g := org_of(me)
	if g.is_empty():
		return GameHost.fail(R_NO_GUILD)
	if member_rank(g, me) > RANK_VICE:
		return GameHost.fail(R_NO_PERMISSION)
	var tname := target_name.strip_edges()
	var t: Session = host.session_for_char_name(tname)
	if t == null or t.character == null:
		return GameHost.fail(R_TARGET_OFFLINE if not host.char_ref_by_name(tname).is_empty() else R_NO_SUCH_CHAR)
	var tid := str(t.character.id)
	if tid == me:
		return GameHost.fail(R_SELF_TARGET)
	if not org_of(tid).is_empty():
		return GameHost.fail(R_ALREADY_IN_ORG)
	if _members(g).size() >= member_max():
		return GameHost.fail(R_ORG_FULL)
	var ttl := maxi(1, opt_int("pending_ttl_real_s", DEFAULT_TTL_REAL_S))
	_invites(g)[tid] = host.now_s() + float(host.world_span(float(ttl)))
	_send_invite(t, g, str(s.character.name), ttl)
	t.sheet_dirty = true
	return GameHost.ok({ "ttl": ttl })

func _send_invite(t: Session, g: Dictionary, from_name: String, ttl: int) -> void:
	# M3b 審查 4：petition_name＝受邀的人自己發起中的連署（接受就作廢、退手續費；提示框要先講）
	var mine := petition_of(str(t.character.id)) if t != null and t.character != null else {}
	host.tell(t, Protocol.CH_SYSTEM, E_ORG_INVITE, { "org": str(g["id"]), "org_name": str(g["name"]),
		"from_name": from_name, "ttl": ttl, "peer": t.peer_id, "petition_name": str(mine.get("name", "")) }, true)

## org_reply：邀請存在且未過期（no_invite）→ 拒絕：刪掉邀請 → 接受：不在組織（already_in_org）→ 未滿（org_full）→ 幫眾
func reply(s: Session, org_id: String, accept: bool) -> Dictionary:
	var me := str(s.character.id)
	var g := find(org_id)
	if g.is_empty() or str(g.get("status", "")) != STATUS_ACTIVE:
		return GameHost.fail(R_NO_INVITE)
	var inv := _invites(g)
	if not inv.has(me) or float(inv[me]) < host.now_s():
		inv.erase(me)
		return GameHost.fail(R_NO_INVITE)
	inv.erase(me)
	s.sheet_dirty = true
	if not accept:
		return GameHost.ok()
	if not org_of(me).is_empty():
		return GameHost.fail(R_ALREADY_IN_ORG)
	if _members(g).size() >= member_max():
		return GameHost.fail(R_ORG_FULL)
	_add_member(g, me, str(s.character.name), RANK_MEMBER)
	_tell_members(g, E_ORG_JOINED, { "name": str(s.character.name), "org_name": str(g["name"]), "peer": s.peer_id })
	# M3b 審查：自己發起中的連署作廢、退手續費（一個人只能在一個組織）
	var mine := petition_of(me)
	if not mine.is_empty():
		guilds().erase(mine)
		host.tell(s, Protocol.CH_SYSTEM, E_ORG_PETITION_EXPIRED, { "org_name": str(mine["name"]), "peer": s.peer_id })
		_refund(mine)
	return GameHost.ok({ "org": org_id })

## org_leave：不在組織（no_guild）→ 幫主要先移交或解散（leader_must_transfer）→ 退出
func leave(s: Session) -> Dictionary:
	var me := str(s.character.id)
	var g := org_of(me)
	if g.is_empty():
		return GameHost.fail(R_NO_GUILD)
	if str(g.get("leader", "")) == me:
		return GameHost.fail(R_LEADER_MUST_TRANSFER)
	_tell_members(g, E_ORG_LEFT, { "name": str(s.character.name), "org_name": str(g["name"]), "peer": s.peer_id })
	_remove_member(g, me)
	return GameHost.ok()

## org_kick：不在組織 → 對象是本組織成員（no_such_char）→ 不是自己 → 對象位階數字大於自己（no_permission；幫主不能被踢）
func kick(s: Session, target_name: String) -> Dictionary:
	var me := str(s.character.id)
	var g := org_of(me)
	if g.is_empty():
		return GameHost.fail(R_NO_GUILD)
	var tid := _member_by_name(g, target_name)
	if tid == "":
		return GameHost.fail(R_NO_SUCH_CHAR)
	if tid == me:
		return GameHost.fail(R_SELF_TARGET)
	if tid == str(g.get("leader", "")) or member_rank(g, tid) <= member_rank(g, me):
		return GameHost.fail(R_NO_PERMISSION)
	var tname := member_name(g, tid)
	var t: Session = host.session_for_char(tid)
	var p := { "name": tname, "by_name": str(s.character.name), "org_name": str(g["name"]),
		"peer": t.peer_id if t != null else 0 }
	_tell_members(g, E_ORG_KICKED, p)
	_remove_member(g, tid)
	return GameHost.ok()

## org_set_rank：只有幫主（no_permission）→ 對象是成員（no_such_char）→ 不是自己（self_target）→ rank 1–4（bad_value:rank；0 要用移交）
func set_rank(s: Session, target_name: String, rank: int) -> Dictionary:
	var me := str(s.character.id)
	var g := org_of(me)
	if g.is_empty():
		return GameHost.fail(R_NO_GUILD)
	if str(g.get("leader", "")) != me:
		return GameHost.fail(R_NO_PERMISSION)
	var tid := _member_by_name(g, target_name)
	if tid == "":
		return GameHost.fail(R_NO_SUCH_CHAR)
	if tid == me:
		return GameHost.fail(R_SELF_TARGET)
	# M3B_PLAN 缺漏：位階超出範圍的原因碼沒有定義 → 沿用參數驗證的 bad_value:<arg>
	if rank < RANK_VICE or rank > RANK_MEMBER:
		return GameHost.fail("bad_value:rank")
	_members(g)[tid]["rank"] = rank
	var t: Session = host.session_for_char(tid)
	_tell_members(g, E_ORG_RANK_CHANGED, { "name": member_name(g, tid), "rank": rank, "rank_name": rank_name(g, rank),
		"by_name": str(s.character.name), "org_name": str(g["name"]), "peer": s.peer_id,
		"def_peer": t.peer_id if t != null else 0 })
	return GameHost.ok()

## org_rank_names：只有幫主 → 5 個名稱、每個清理後 1–4 字（bad_value:names）
func set_rank_names(s: Session, names: Array) -> Dictionary:
	var me := str(s.character.id)
	var g := org_of(me)
	if g.is_empty():
		return GameHost.fail(R_NO_GUILD)
	if str(g.get("leader", "")) != me:
		return GameHost.fail(R_NO_PERMISSION)
	if names.size() != RANK_COUNT:
		return GameHost.fail("bad_value:names")
	var out: Array = []
	for n in names:
		if not (n is String):
			return GameHost.fail("bad_value:names")
		var c := _clean(str(n), 64)
		if c.length() < RANK_NAME_MIN or c.length() > RANK_NAME_MAX:
			return GameHost.fail("bad_value:names")
		out.append(c)
	g["rank_names"] = out
	# M3B_PLAN 缺漏：改位階名稱沒有事件 → 刷新在線成員的角色表（rank_name），面板重開時看到新名稱
	for o in members_online(str(g["id"])):
		o.sheet_dirty = true
	return GameHost.ok({ "names": out.duplicate() })

## org_title：幫主與副幫主可封（no_permission）；副幫主只能封自己或位階數字大於 1 的人；0–6 字（bad_value:title）
func set_title(s: Session, target_name: String, title: String) -> Dictionary:
	var me := str(s.character.id)
	var g := org_of(me)
	if g.is_empty():
		return GameHost.fail(R_NO_GUILD)
	var my_rank := member_rank(g, me)
	if my_rank > RANK_VICE:
		return GameHost.fail(R_NO_PERMISSION)
	var tid := _member_by_name(g, target_name)
	if tid == "":
		return GameHost.fail(R_NO_SUCH_CHAR)
	if my_rank == RANK_VICE and tid != me and member_rank(g, tid) <= RANK_VICE:
		return GameHost.fail(R_NO_PERMISSION)
	var t_raw := title.strip_edges()
	var t_clean := _clean(t_raw, 64)
	if t_clean.length() > TITLE_MAX:
		return GameHost.fail("bad_value:title")
	_members(g)[tid]["title"] = t_clean
	var t: Session = host.session_for_char(tid)
	_tell_members(g, E_ORG_TITLE_CHANGED, { "name": member_name(g, tid), "title": t_clean,
		"by_name": str(s.character.name), "org_name": str(g["name"]), "peer": s.peer_id,
		"def_peer": t.peer_id if t != null else 0 })
	return GameHost.ok()

## org_lead（移交）：只有幫主 → 對象是成員 → 不是自己 → 新幫主位階 0，舊幫主改副幫主（1）【設計提案】
func transfer(s: Session, target_name: String) -> Dictionary:
	var me := str(s.character.id)
	var g := org_of(me)
	if g.is_empty():
		return GameHost.fail(R_NO_GUILD)
	if str(g.get("leader", "")) != me:
		return GameHost.fail(R_NO_PERMISSION)
	var tid := _member_by_name(g, target_name)
	if tid == "":
		return GameHost.fail(R_NO_SUCH_CHAR)
	if tid == me:
		return GameHost.fail(R_SELF_TARGET)
	var mem := _members(g)
	mem[tid]["rank"] = RANK_LEADER
	mem[me]["rank"] = RANK_VICE
	g["leader"] = tid
	g["leader_name"] = member_name(g, tid)
	var t: Session = host.session_for_char(tid)
	_tell_members(g, E_ORG_LEADER_CHANGED, { "name": str(g["leader_name"]), "old_name": str(s.character.name),
		"org_name": str(g["name"]), "peer": s.peer_id, "def_peer": t.peer_id if t != null else 0 })
	return GameHost.ok()

## org_disband：幫主、confirm: true（客戶端兩段確認；否則 need_confirm）→ 成員 guild = ""、org_disbanded。
## 連署中的發起人也可以用它撤回連署（M3b 審查：手續費全額退還）【設計提案】
func disband(s: Session, confirm: bool) -> Dictionary:
	var me := str(s.character.id)
	var g := org_of(me)
	if g.is_empty():
		g = petition_of(me)
		if g.is_empty():
			return GameHost.fail(R_NO_GUILD)
	if str(g.get("leader", "")) != me:
		return GameHost.fail(R_NO_PERMISSION)
	if not confirm:
		return GameHost.fail(R_NEED_CONFIRM)
	var p := { "name": str(s.character.name), "leader_name": str(s.character.name), "org_name": str(g["name"]),
		"peer": s.peer_id }
	if str(g.get("status", "")) == STATUS_ACTIVE:
		_tell_members(g, E_ORG_DISBANDED, p)
	else:
		host.tell(s, Protocol.CH_SYSTEM, E_ORG_DISBANDED, p)
	var ids: Array = _members(g).keys()
	guilds().erase(g)
	if str(g.get("status", "")) != STATUS_ACTIVE:
		_refund(g)
	for cid in ids:
		_sync_cache(str(cid))
	s.sheet_dirty = true
	return GameHost.ok()

## org_info：送 org_info（ui）給本人（形狀見 info_payload）
func info(s: Session) -> Dictionary:
	var p := info_payload(s)
	p["peer"] = s.peer_id
	host.tell(s, Protocol.CH_SYSTEM, E_ORG_INFO, p, true)
	return GameHost.ok()

# ================================================================ 快照

## org_info 的 payload（Day-0 契約，WP-UI 的組織面板用；docs/m3b_staging/_org.json 的 org_info_shape 同步）：
## { "org": null | { "id", "name", "status", "leader", "leader_name", "created_s", "rank_names": [5],
##       "member_count", "member_max", "members_online",
##       "members": [ { "char_id", "name", "rank", "rank_name", "title", "online", "joined_s" } ]（位階、加入順序）,
##       "petition": null | { "signed", "need", "signers": [name], "left_s"（真實秒數） } },
##   "my": null | { "rank", "rank_name", "title", "can_invite", "can_kick", "can_set_rank", "can_title",
##       "can_rank_names", "can_transfer", "can_disband", "can_leave" },
##   "societies": ["天地會"],
##   "found": { "fee", "fame_min", "signer_fame_min", "need" } }
## 連署中的發起人：org 是那個 PETITION（members 空、petition 有值），my.rank = 0、只有 can_disband（撤回）
func info_payload(s: Session) -> Dictionary:
	var ch = s.character if s != null else null
	var me := str(ch.id) if ch != null else ""
	var g := org_of(me)
	if g.is_empty():
		g = petition_of(me)
	var out := { "org": null, "my": null, "societies": societies_of(ch),
		"found": { "fee": found_fee(), "fame_min": found_fame(), "signer_fame_min": signer_fame(),
			"need": signers_needed() } }
	if g.is_empty():
		return out
	var active := str(g.get("status", "")) == STATUS_ACTIVE
	var members: Array = []
	var online := 0
	var mem := _members(g)
	for cid in mem:
		var m: Dictionary = mem[cid]
		var on: bool = host.session_for_char(str(cid)) != null
		if on:
			online += 1
		members.append({ "char_id": str(cid), "name": member_name(g, str(cid)), "rank": int(m.get("rank", RANK_MEMBER)),
			"rank_name": rank_name(g, int(m.get("rank", RANK_MEMBER))), "title": str(m.get("title", "")),
			"online": on, "joined_s": float(m.get("joined_s", 0.0)) })
	members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["rank"]) != int(b["rank"]):
			return int(a["rank"]) < int(b["rank"])
		return float(a["joined_s"]) < float(b["joined_s"]))
	var petition: Variant = null
	if not active:
		var names: Array = []
		for cid in _signers(g):
			if org_of(str(cid)).is_empty():   # M3b 審查 4：已加入別的組織的不列（不算數）
				names.append(member_name(g, str(cid)))
		var left_world := maxf(0.0, float(g.get("petition_until_s", 0.0)) - float(host.now_s()))
		petition = { "signed": names.size(), "need": signers_needed(), "signers": names,
			"left_s": int(ceil(float(host.real_span(left_world)))) }
	out["org"] = { "id": str(g["id"]), "name": str(g["name"]), "status": str(g.get("status", "")),
		"leader": str(g.get("leader", "")), "leader_name": leader_name(g), "created_s": float(g.get("created_s", 0.0)),
		"rank_names": rank_names(g).duplicate(), "member_count": mem.size(), "member_max": member_max(),
		"members_online": online, "members": members, "petition": petition }
	var rank := member_rank(g, me) if active else RANK_LEADER
	var is_leader := str(g.get("leader", "")) == me
	out["my"] = { "rank": rank, "rank_name": rank_name(g, rank),
		"title": str((mem.get(me, {}) as Dictionary).get("title", "")) if active else "",
		"can_invite": active and rank <= RANK_VICE, "can_kick": active and rank < RANK_MEMBER,
		"can_set_rank": active and is_leader, "can_title": active and rank <= RANK_VICE,
		"can_rank_names": active and is_leader, "can_transfer": active and is_leader,
		"can_disband": is_leader, "can_leave": active and not is_leader }
	return out

## 角色表的 org（§5.3）：{ id, name, rank, rank_name, title, leader_name, members_online } 或 null
func sheet_for(s: Session) -> Variant:
	if s == null or s.character == null:
		return null
	var me := str(s.character.id)
	var g := org_of(me)
	if g.is_empty():
		return null
	var rank := member_rank(g, me)
	return { "id": str(g["id"]), "name": str(g["name"]), "rank": rank, "rank_name": rank_name(g, rank),
		"title": str(_members(g)[me].get("title", "")), "leader_name": leader_name(g),
		"members_online": members_online(str(g["id"])).size() }

## 角色表一次給兩個欄位：{ "org": …|null, "societies": [String] }（GameHost 合併進角色表）
func sheet_fields(s: Session) -> Dictionary:
	return { "org": sheet_for(s), "societies": societies_of(s.character if s != null else null) }

## 會籍旗標 → 名稱（天地會）
func societies_of(ch) -> Array:
	var out: Array = []
	if ch == null or not ("flags" in ch) or not (ch.flags is Dictionary):
		return out
	for fl in SOCIETY_FLAGS:
		if bool(ch.flags.get(fl, false)):
			out.append(str(SOCIETY_FLAGS[fl]))
	return out

## 房間 players[] 的組織名（§6 player_tags.org_name）
func player_tags(o: Session) -> Dictionary:
	if o == null or o.character == null:
		return { "org_name": "" }
	return { "org_name": str(org_of(str(o.character.id)).get("name", "")) }

## npc_menu 的 org 欄位（§6）：ORG 服務的 NPC 才有，其他 NPC 為 null
func menu_fields(s: Session, npc_id: String) -> Dictionary:
	var row: Dictionary = host.npc_row(npc_id)
	if not (NPC_SERVICE in row.get("services", [])) or s == null or s.character == null:
		return { "org": null }
	var ch = s.character
	var me := str(ch.id)
	var petitions: Array = []
	for g in guilds():
		if g is Dictionary and str(g.get("status", "")) == STATUS_PETITION:
			# M3b 審查 3：書吏頁也要看得到連署還剩多久（left_s，真實秒數，同 org_info.petition.left_s）
			var left_world := maxf(0.0, float(g.get("petition_until_s", 0.0)) - float(host.now_s()))
			petitions.append({ "id": str(g["id"]), "name": str(g["name"]), "leader_name": leader_name(g),
				"signed": valid_signer_count(g), "need": signers_needed(), "mine": str(g.get("leader", "")) == me,
				"signed_by_me": me in _signers(g), "left_s": int(ceil(float(host.real_span(left_world)))) })
	var can := org_of(me).is_empty() and petition_of(me).is_empty() and _fame(ch) >= found_fame() \
		and int(ch.money) >= found_fee()
	return { "org": { "petitions": petitions, "can_found": can, "fee": found_fee(), "fame_min": found_fame(),
		"signer_fame_min": signer_fame() } }

## 組織在線成員的 session（SocialSystem 的 CHAT_GUILD 用）
func members_online(org_id: String) -> Array:
	var out: Array = []
	var g := find(org_id)
	if g.is_empty() or str(g.get("status", "")) != STATUS_ACTIVE:
		return out
	for cid in _members(g):
		var o: Session = host.session_for_char(str(cid))
		if o != null and o.character != null:
			out.append(o)
	return out

# ================================================================ 主機掛鉤

## 登入（選角）：校正 ch.guild；補送還有效的組織邀請
func on_login(s: Session) -> void:
	if s == null or s.character == null:
		return
	var me := str(s.character.id)
	_sync_cache(me)
	var now: float = host.now_s()
	for g in guilds():
		if not (g is Dictionary) or str(g.get("status", "")) != STATUS_ACTIVE:
			continue
		var inv := _invites(g)
		if inv.has(me) and float(inv[me]) > now:
			var left := maxi(1, int(ceil(float(host.real_span(float(inv[me]) - now)))))
			_send_invite(s, g, leader_name(g), left)
	_pay_refund(s)
	# 名字快取（離線時顯示）
	var g2 := org_of(me)
	if not g2.is_empty():
		_members(g2)[me]["name"] = str(s.character.name)

## 每分鐘（GameHost._minute_jobs）：連署過期 → 刪除、通知發起人；門檻改低時補成立；過期邀請清掉
func tick(now_world_s: float) -> void:
	var list := guilds()
	for g in list.duplicate():
		if not (g is Dictionary):
			list.erase(g)
			continue
		if str(g.get("status", "")) == STATUS_PETITION:
			if valid_signer_count(g) >= signers_needed():
				_activate(g)
			elif float(g.get("petition_until_s", 0.0)) <= now_world_s:
				list.erase(g)
				var founder: Session = host.session_for_char(str(g.get("leader", "")))
				if founder != null:
					host.tell(founder, Protocol.CH_SYSTEM, E_ORG_PETITION_EXPIRED,
						{ "org_name": str(g["name"]), "peer": founder.peer_id })
					founder.sheet_dirty = true
				_refund(g)
			continue
		var inv := _invites(g)
		for cid in inv.keys():
			if float(inv[cid]) <= now_world_s:
				inv.erase(cid)

## 角色刪除（intents_char.char_delete）：從所有組織的成員、連署名單、邀請移除；
## 他是 ACTIVE 組織的幫主 → 交給位階最高（同位階取最早加入）的成員，沒人就解散；他發起的連署 → 刪掉（人都沒了，不退款）
func on_char_deleted(char_id: String) -> void:
	if char_id == "":
		return
	var list := guilds()
	for g in list.duplicate():
		if not (g is Dictionary):
			continue
		_signers(g).erase(char_id)
		if g.get("signer_names") is Dictionary:
			(g["signer_names"] as Dictionary).erase(char_id)
		_invites(g).erase(char_id)
		if str(g.get("leader", "")) == char_id and str(g.get("status", "")) != STATUS_ACTIVE:
			list.erase(g)
			continue
		var mem := _members(g)
		if not mem.has(char_id):
			continue
		var old_name := member_name(g, char_id)
		mem.erase(char_id)
		if str(g.get("leader", "")) != char_id:
			_tell_members(g, E_ORG_LEFT, { "name": old_name, "org_name": str(g["name"]), "peer": 0 })
			continue
		if mem.is_empty():
			list.erase(g)
			continue
		var best := ""
		for cid in mem:
			if best == "":
				best = str(cid)
				continue
			var a: Dictionary = mem[cid]
			var b: Dictionary = mem[best]
			if int(a.get("rank", 9)) < int(b.get("rank", 9)) or (int(a.get("rank", 9)) == int(b.get("rank", 9)) 					and float(a.get("joined_s", 0.0)) < float(b.get("joined_s", 0.0))):
				best = str(cid)
		mem[best]["rank"] = RANK_LEADER
		g["leader"] = best
		g["leader_name"] = member_name(g, best)
		var t: Session = host.session_for_char(best)
		_tell_members(g, E_ORG_LEADER_CHANGED, { "name": str(g["leader_name"]), "old_name": old_name,
			"org_name": str(g["name"]), "peer": 0, "def_peer": t.peer_id if t != null else 0 })
	var w: Dictionary = host.ws.world
	if w.get(REFUND_KEY) is Dictionary:
		(w[REFUND_KEY] as Dictionary).erase(char_id)

# ================================================================ 內部

## 連署沒成立：把發起時扣的手續費（g.fee；舊存檔沒有就用目前的 org_found_fee）退給發起人。
## 在線 → 馬上入帳；離線 → 記在 world.org_refunds，下次登入（on_login）再入帳
func _refund(g: Dictionary) -> void:
	var cid := str(g.get("leader", ""))
	var amount := int(g.get("fee", found_fee()))
	if cid == "" or amount <= 0:
		return
	g["fee"] = 0
	var w: Dictionary = host.ws.world
	if not (w.get(REFUND_KEY) is Dictionary):
		w[REFUND_KEY] = {}
	var pend: Dictionary = w[REFUND_KEY]
	if not (pend.get(cid) is Array):
		pend[cid] = []
	(pend[cid] as Array).append({ "org_name": str(g.get("name", "")), "money": amount })
	var o: Session = host.session_for_char(cid)
	if o != null:
		_pay_refund(o)

func _pay_refund(s: Session) -> void:
	if s == null or s.character == null:
		return
	var w: Dictionary = host.ws.world
	var pend: Variant = w.get(REFUND_KEY)
	if not (pend is Dictionary):
		return
	var me := str(s.character.id)
	var list: Variant = (pend as Dictionary).get(me)
	(pend as Dictionary).erase(me)
	if not (list is Array):
		return
	var paid := false
	for r in list:
		if not (r is Dictionary):
			continue
		var got: int = s.character.add_money(int(r.get("money", 0)))
		paid = true
		host.tell(s, Protocol.CH_SYSTEM, E_ORG_FEE_REFUND, { "org_name": str(r.get("org_name", "")), "money": got,
			"peer": s.peer_id })
	s.sheet_dirty = true
	# M3b 審查 3：退費從 world.org_refunds 移到角色身上 → 馬上存，先寫 world.json（清掉待退）再寫角色檔。
	# 以前不存，下次自動存檔是角色先寫：兩次寫入之間當機會再退一次
	if paid and host.ws != null:
		host.ws.save_now(true)

## 連署成立：發起人幫主（0），連署人幫眾（4）並成為成員（O14）；已加入別的組織的連署人略過
func _activate(g: Dictionary) -> void:
	var leader := str(g.get("leader", ""))
	if not org_of(leader).is_empty():
		# 發起人已經在別的組織（例如接受了邀請）：這個連署作廢
		guilds().erase(g)
		var founder: Session = host.session_for_char(leader)
		if founder != null:
			host.tell(founder, Protocol.CH_SYSTEM, E_ORG_PETITION_EXPIRED, { "org_name": str(g["name"]), "peer": founder.peer_id })
		_refund(g)
		return
	g["status"] = STATUS_ACTIVE
	g["petition_until_s"] = 0.0
	var now: float = host.now_s()
	g["members"] = {}
	_add_member(g, leader, str(g.get("leader_name", "")), RANK_LEADER, now)
	var names: Dictionary = g.get("signer_names", {}) if g.get("signer_names") is Dictionary else {}
	for cid in _signers(g):
		var id := str(cid)
		if id == leader or not org_of(id).is_empty() or _members(g).size() >= member_max():
			continue
		_add_member(g, id, str(names.get(id, "")), RANK_MEMBER, now)
	# 新成員從別人的連署名單移除（一個人只能在一個組織；_add_member 也會做，這裡留著給舊存檔的成員）
	for cid in _members(g):
		_unsign_everywhere(str(cid), g)
	var ls: Session = host.session_for_char(leader)
	host.ws.broadcast_event(Protocol.CH_SYSTEM, E_ORG_FOUNDED, { "org_name": str(g["name"]), "org": str(g["id"]),
		"name": leader_name(g), "leader_name": leader_name(g), "peer": ls.peer_id if ls != null else 0,
		"members": _members(g).size() })

func _add_member(g: Dictionary, char_id: String, char_name: String, rank: int, now: float = -1.0) -> void:
	_members(g)[char_id] = { "rank": rank, "title": "", "joined_s": host.now_s() if now < 0.0 else now,
		"name": char_name }
	_invites(g).erase(char_id)
	# M3b 審查 4：加入（接受邀請、連署成立）就從別的連署名單拿掉（g 自己的名單由 _activate 迭代中，不動）
	_unsign_everywhere(char_id, g)
	_sync_cache(char_id)

func _remove_member(g: Dictionary, char_id: String) -> void:
	_members(g).erase(char_id)
	_sync_cache(char_id)
	for o in members_online(str(g.get("id", ""))):
		o.sheet_dirty = true

## 在線角色的 ch.guild 快取（Character §4.12；欄位還沒有時略過）與角色表
func _sync_cache(char_id: String) -> void:
	var o: Session = host.session_for_char(char_id)
	if o == null or o.character == null:
		return
	if "guild" in o.character:
		o.character.guild = org_id_of(char_id)
	o.sheet_dirty = true
	o.view_dirty = true   # 房間 players[] 的 org_name

## 本組織成員中名字相符（大小寫不敏感）的 char_id；沒有 → ""
func _member_by_name(g: Dictionary, target_name: String) -> String:
	var k := CharacterStore.name_key(target_name.strip_edges())
	if k == "":
		return ""
	for cid in _members(g):
		if CharacterStore.name_key(member_name(g, str(cid))) == k:
			return str(cid)
	var ref: Dictionary = host.char_ref_by_name(target_name.strip_edges())
	var id := str(ref.get("char_id", ""))
	return id if id != "" and _members(g).has(id) else ""

## 送給組織的每位在線成員（同一份 payload；peer／def_peer 決定 self／target／other 變體）
func _tell_members(g: Dictionary, key: String, p: Dictionary) -> void:
	for o in members_online(str(g.get("id", ""))):
		host.tell(o, Protocol.CH_SYSTEM, key, p.duplicate())
		o.sheet_dirty = true
