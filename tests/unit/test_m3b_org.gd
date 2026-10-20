extends "res://tests/unit/test_social_fixture.gd"
## WP-ORG：組織（M3B_PLAN §5.3、§6、§11.1）。創立各原因碼；連署滿 → ACTIVE、連署人成員；過期刪除；邀請／回覆、上限、
## 開除權限、位階、封號、移交、幫主不能直接退出、解散；存檔往返（world.guilds）；org_info／npc_menu 形狀。
## 本機 peer 1 是發起人（幫主）；遠端玩家用 soc_add。Day-0（Protocol、GameHost.orgs）還沒落地時：
## intent 直接交給已註冊的處理器（跳過 validate_args），OrgSystem 由 IntentsOrg.install 建立。

const ROOM := "xx_yamen"
const TEST_NPC := "n_og_test_shuli"

var orgs                 # 實際處理 org_* 的 OrgSystem
var npc := ""            # 衙門書吏（ORG 服務）

func before_each() -> void:
	super.before_each()
	_org_wire()

func _org_wire() -> void:
	var h = host()
	if h == null:
		return
	orgs = h.get("orgs")
	if orgs == null:
		orgs = IntentsOrg.install(h)
	if social != null and h.get("orgs") == null:
		social.orgs_override = orgs
	npc = "n_og_xx_shuli"
	if GameData.tables.get("npcs", {}).get(npc, {}).is_empty() or h.index.room_of_npc(npc) != ROOM:
		# 合併前（WP-MERGE 還沒把 _org.json 併進 data）：測試自己放一位書吏
		npc = TEST_NPC
		GameData.tables["npcs"][npc] = { "id": npc, "name": "測試書吏", "kind": "FUNC", "region": "xixia", "room": ROOM,
			"alignment": "NEUTRAL", "talk": "", "services": ["ORG"], "night_closed": false, "desc": "", "era": "1.0A",
			"src": "proposal" }
		h.index.npc_room[npc] = ROOM
	ws.options["guild_signers"] = 2
	ws.options["org_found_fame"] = 150
	ws.options["org_signer_fame"] = 20
	ws.options["org_found_fee"] = 10000
	ws.options["org_member_max"] = 50
	ws.options["org_petition_days"] = 3
	ws.options["pending_ttl_real_s"] = 60

# ---------- intent 路由 ----------
func od(peer: int, kind: String, args: Dictionary = {}) -> Dictionary:
	if Protocol.is_known(kind):
		return soc_send(peer, kind, args)
	var sess: Session = ws.sessions.get(peer)
	if sess == null or not ws._handlers.has(kind):
		return { "ok": false, "reason": "test:no_handler" }
	var r: Dictionary = ws._handlers[kind].call(sess, args)
	pump()
	return r

func oreason(peer: int, kind: String, args: Dictionary = {}) -> String:
	return str(od(peer, kind, args).get("reason", ""))

func ook(peer: int, kind: String, args: Dictionary = {}) -> Dictionary:
	var r := od(peer, kind, args)
	assert_true(r.get("ok", false), "peer %d %s %s -> %s" % [peer, kind, str(args), str(r.get("reason", ""))])
	return r

func cof(peer: int):
	return ch() if peer == 1 else rch(peer)

# ---------- 場景 ----------
## 本機「幫主」與兩位連署人（名聲夠）在衙門；回傳 [b, c]
func _setup() -> Array:
	if not game_ok():
		return []
	if make_char("發起人") == null:
		return []
	goto(ROOM)
	ch().fame = 200
	ch().money = 20000
	var b := soc_add("連署甲", ROOM)
	var c := soc_add("連署乙", ROOM)
	rch(b).fame = 30
	rch(c).fame = 30
	clear_all_events()
	return [b, c]

## 創立並簽滿（guild_signers = 2）→ ACTIVE；回傳組織 id
func _found_active(b: int, c: int, org_name := "江湖小築") -> String:
	var r := ook(1, "org_found", { "npc": npc, "name": org_name })
	var oid := str(r.get("org", ""))
	ook(b, "org_sign", { "npc": npc, "org": oid })
	ook(c, "org_sign", { "npc": npc, "org": oid })
	return oid

func _guild_cache(peer: int) -> String:
	var x = cof(peer)
	return str(x.guild) if x != null and "guild" in x else "<no field>"

# ================================================================ 常數與純函式

func test_constants_match_contract() -> void:
	assert_eq(IntentsOrg.ALL, ["org_found", "org_sign", "org_invite", "org_reply", "org_leave", "org_kick",
		"org_set_rank", "org_rank_names", "org_title", "org_lead", "org_disband", "org_info"], "§6 intent")
	assert_eq(OrgSystem.SOCIETY_FLAGS, { "tdh_member": "天地會" })
	assert_eq(OrgSystem.DEFAULT_RANK_NAMES, ["幫主", "副幫主", "長老", "堂主", "幫眾"])
	var consts: Dictionary = (load("res://core/protocol.gd") as GDScript).get_script_constant_map()
	var pairs := { "I_ORG_FOUND": "org_found", "I_ORG_SIGN": "org_sign", "I_ORG_INVITE": "org_invite",
		"I_ORG_REPLY": "org_reply", "I_ORG_LEAVE": "org_leave", "I_ORG_KICK": "org_kick",
		"I_ORG_SET_RANK": "org_set_rank", "I_ORG_RANK_NAMES": "org_rank_names", "I_ORG_TITLE": "org_title",
		"I_ORG_LEAD": "org_lead", "I_ORG_DISBAND": "org_disband", "I_ORG_INFO": "org_info",
		"E_ORG_INFO": OrgSystem.E_ORG_INFO, "E_ORG_PETITION": OrgSystem.E_ORG_PETITION,
		"E_ORG_SIGNED": OrgSystem.E_ORG_SIGNED, "E_ORG_FOUNDED": OrgSystem.E_ORG_FOUNDED,
		"E_ORG_PETITION_EXPIRED": OrgSystem.E_ORG_PETITION_EXPIRED, "E_ORG_INVITE": OrgSystem.E_ORG_INVITE,
		"E_ORG_JOINED": OrgSystem.E_ORG_JOINED, "E_ORG_LEFT": OrgSystem.E_ORG_LEFT, "E_ORG_KICKED": OrgSystem.E_ORG_KICKED,
		"E_ORG_RANK_CHANGED": OrgSystem.E_ORG_RANK_CHANGED, "E_ORG_TITLE_CHANGED": OrgSystem.E_ORG_TITLE_CHANGED,
		"E_ORG_LEADER_CHANGED": OrgSystem.E_ORG_LEADER_CHANGED, "E_ORG_DISBANDED": OrgSystem.E_ORG_DISBANDED }
	for k in pairs:
		if consts.has(k):
			assert_eq(consts[k], pairs[k], "Protocol." + k)

func test_valid_org_name() -> void:
	assert_true(OrgSystem.valid_org_name("江湖小築"))
	assert_true(OrgSystem.valid_org_name("天下第1"), "數字可以")
	assert_true(OrgSystem.valid_org_name("十二連環塢八路"), "8 字")
	assert_false(OrgSystem.valid_org_name("幫"), "1 字太短")
	assert_false(OrgSystem.valid_org_name("一二三四五六七八九"), "9 字太長")
	assert_false(OrgSystem.valid_org_name("ABC幫"), "拉丁字母不行")
	assert_false(OrgSystem.valid_org_name("江湖 小築"), "空白不行")
	assert_false(OrgSystem.valid_org_name("江湖！"), "標點不行")
	assert_true(OrgSystem.valid_org_name("さくら組"), "日文假名")
	assert_true(OrgSystem.valid_org_name("１２３"), "全形數字")

# ================================================================ 創立

func test_found_reason_order_and_success() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var b: int = bc[0]
	goto("xx_square")
	assert_eq(oreason(1, "org_found", { "npc": npc, "name": "江湖小築" }), "not_here", "不在書吏面前")
	goto(ROOM)
	ch().fame = 149
	assert_eq(oreason(1, "org_found", { "npc": npc, "name": "江湖小築" }), "req_fame_min")
	ch().fame = 150
	ch().money = 9999
	assert_eq(oreason(1, "org_found", { "npc": npc, "name": "江湖小築" }), "not_enough_money")
	ch().money = 15000
	assert_eq(oreason(1, "org_found", { "npc": npc, "name": "X" }), "bad_org_name")
	assert_eq(oreason(1, "org_found", { "npc": npc, "name": "江湖[小築]" }), "bad_org_name", "清理後不同")
	assert_eq(ch().money, 15000, "失敗不扣錢")
	var r := ook(1, "org_found", { "npc": npc, "name": "江湖小築" })
	assert_eq(ch().money, 5000, "扣一萬兩手續費")
	var g: Dictionary = orgs.find(str(r.get("org", "")))
	assert_eq(str(g.get("status", "")), "PETITION")
	assert_eq(str(g.get("leader", "")), str(ch().id))
	assert_true(float(g["petition_until_s"]) > ws.world_time(), "有期限")
	assert_eq(evs_of(1, "org_petition").size(), 1, "發起人收到")
	assert_eq(evs_of(b, "org_petition").size(), 1, "全服廣播")
	assert_eq(evs_of(b, "org_petition")[0]["p"]["org_name"], "江湖小築")
	ch().money = 20000
	assert_eq(oreason(1, "org_found", { "npc": npc, "name": "第二幫會" }), "already_petitioning")
	assert_eq(ch().money, 20000, "失敗不扣錢")
	# 別人用同名
	rch(b).fame = 200
	rch(b).money = 20000
	assert_eq(oreason(b, "org_found", { "npc": npc, "name": "江湖小築" }), "org_name_taken", "含連署中的")
	assert_eq(_guild_cache(1) in ["", "<no field>"], true, "連署中還不是成員")

func test_sign_until_active() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var b: int = bc[0]
	var c: int = bc[1]
	var oid := str(ook(1, "org_found", { "npc": npc, "name": "江湖小築" }).get("org", ""))
	assert_eq(oreason(b, "org_sign", { "npc": npc, "org": "g_nope" }), "not_petition")
	assert_eq(oreason(1, "org_sign", { "npc": npc, "org": oid }), "self_target", "發起人不能自己簽")
	rch(b).fame = 19
	assert_eq(oreason(b, "org_sign", { "npc": npc, "org": oid }), "req_fame_min")
	rch(b).fame = 20
	clear_all_events()
	var r1 := ook(b, "org_sign", { "npc": npc, "org": oid })
	assert_eq(int(r1.get("signed", 0)), 1)
	assert_eq(evs_of(b, "org_signed").size(), 1, "簽名者收到")
	assert_eq(evs_of(1, "org_signed").size(), 1, "發起人收到")
	assert_eq(oreason(b, "org_sign", { "npc": npc, "org": oid }), "already_signed")
	clear_all_events()
	ook(c, "org_sign", { "npc": npc, "org": oid })
	var g: Dictionary = orgs.find(oid)
	assert_eq(str(g["status"]), "ACTIVE", "簽滿成立")
	assert_eq(int(g["members"][str(ch().id)]["rank"]), 0, "發起人幫主")
	assert_eq(int(g["members"][str(rch(b).id)]["rank"]), 4, "連署人幫眾")
	assert_eq(int(g["members"][str(rch(c).id)]["rank"]), 4)
	assert_eq(evs_of(1, "org_founded").size(), 1, "全服 org_founded")
	assert_eq(evs_of(c, "org_founded").size(), 1)
	assert_eq(orgs.org_id_of(str(rch(b).id)), oid)
	if "guild" in ch():
		assert_eq(str(ch().guild), oid, "在線成員 ch.guild 快取")
		assert_eq(str(rch(b).guild), oid)
	assert_eq(oreason(1, "org_found", { "npc": npc, "name": "第二幫會" }), "already_in_org")
	# 已成立 → 不能再連署
	var d := soc_add("後來者", ROOM)
	rch(d).fame = 50
	assert_eq(oreason(d, "org_sign", { "npc": npc, "org": oid }), "not_petition")

func test_petition_expires() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var oid := str(ook(1, "org_found", { "npc": npc, "name": "江湖小築" }).get("org", ""))
	ook(bc[0], "org_sign", { "npc": npc, "org": oid })
	clear_all_events()
	var g: Dictionary = orgs.find(oid)
	orgs.tick(float(g["petition_until_s"]) - 1.0)
	assert_false(orgs.find(oid).is_empty(), "期限前還在")
	orgs.tick(float(g["petition_until_s"]) + 1.0)
	pump()
	assert_true(orgs.find(oid).is_empty(), "過期刪除")
	assert_eq(evs_of(1, "org_petition_expired").size(), 1, "發起人收到過期")
	# M3b 審查：連署沒成立 → 手續費全額退還
	assert_eq(ch().money, 20000, "手續費退還")
	assert_eq(evs_of(1, "org_fee_refund").size(), 1, "org_fee_refund")
	assert_eq(int(evs_of(1, "org_fee_refund")[0]["p"]["money"]), 10000)
	# 可以重新發起同名
	ook(1, "org_found", { "npc": npc, "name": "江湖小築" })

func test_petition_founder_can_withdraw() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var oid := str(ook(1, "org_found", { "npc": npc, "name": "江湖小築" }).get("org", ""))
	assert_eq(oreason(1, "org_disband", { "confirm": false }), "need_confirm")
	assert_eq(ch().money, 10000)
	ook(1, "org_disband", { "confirm": true })
	assert_true(orgs.find(oid).is_empty(), "撤回連署")
	assert_eq(ch().money, 20000, "撤回連署也退手續費（M3b 審查）")

## M3b 審查：發起人離線時過期 → 退款記在 world.org_refunds，登入時入帳；發起人接受別的組織邀請 → 連署馬上作廢、退款
func test_refund_offline_and_void() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var b: int = bc[0]
	var c: int = bc[1]
	rch(b).fame = 200
	rch(b).money = 15000
	var b_id := str(rch(b).id)
	var oid := str(ook(b, "org_found", { "npc": npc, "name": "離線幫" }).get("org", ""))
	assert_eq(rch(b).money, 5000)
	soc_drop(b)
	var g: Dictionary = orgs.find(oid)
	orgs.tick(float(g["petition_until_s"]) + 1.0)
	assert_true(orgs.find(oid).is_empty())
	var pend: Variant = ws.world.get("org_refunds", {}).get(b_id)
	assert_true(pend is Array and (pend as Array).size() == 1 and int(pend[0]["money"]) == 10000, "離線退款記下：%s" % str(pend))
	# 登入入帳（用本機角色驗 on_login 的入帳路徑）
	ws.world["org_refunds"][str(ch().id)] = [{ "org_name": "離線幫", "money": 300 }]
	var m0: int = ch().money
	clear_all_events()
	orgs.on_login(s())
	pump()
	assert_eq(ch().money, m0 + 300, "登入時入帳")
	assert_eq(evs_of(1, "org_fee_refund").size(), 1)
	assert_false(ws.world["org_refunds"].has(str(ch().id)), "領過就清掉")
	# 作廢：本機發起連署，之後接受別的組織邀請 → 連署在 tick 時作廢並退款
	var oid2 := str(ook(1, "org_found", { "npc": npc, "name": "作廢幫" }).get("org", ""))
	assert_true(oid2 != "", "發起連署")
	var m1: int = ch().money
	ws.options["guild_signers"] = 1
	rch(c).fame = 200
	rch(c).money = 20000
	var oid3 := str(ook(c, "org_found", { "npc": npc, "name": "別人幫" }).get("org", ""))
	var d := soc_add("連署丙", ROOM)
	rch(d).fame = 30
	ook(d, "org_sign", { "npc": npc, "org": oid3 })
	assert_eq(str(orgs.find(oid3).get("status", "")), "ACTIVE")
	ook(c, "org_invite", { "name": "發起人" })
	ook(1, "org_reply", { "org": oid3, "accept": true })
	assert_eq(orgs.org_id_of(str(ch().id)), oid3)
	assert_true(orgs.find(oid2).is_empty(), "發起人加入別的組織 → 自己的連署作廢")
	assert_eq(ch().money, m1 + 10000, "作廢也退手續費")

# ================================================================ 邀請與回覆

func test_invite_reply_and_limits() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var b: int = bc[0]
	var c: int = bc[1]
	var d := soc_add("遊俠", "xx_square")
	assert_eq(oreason(d, "org_invite", { "name": "連署甲" }), "no_guild", "沒有組織不能邀請")
	var oid := _found_active(b, c)
	assert_eq(oreason(b, "org_invite", { "name": "遊俠" }), "no_permission", "幫眾不能邀請")
	assert_eq(oreason(1, "org_invite", { "name": "沒這個人" }), "no_such_char")
	assert_eq(oreason(1, "org_invite", { "name": "發起人" }), "self_target")
	assert_eq(oreason(1, "org_invite", { "name": "連署甲" }), "already_in_org")
	var e := soc_add("離線客", "xx_square")
	soc_drop(e)
	assert_eq(oreason(1, "org_invite", { "name": "離線客" }), "target_offline")
	clear_all_events()
	ook(1, "org_invite", { "name": "遊俠" })
	var inv := evs_of(d, "org_invite")
	assert_eq(inv.size(), 1, "目標收到 org_invite")
	assert_true(bool(inv[0].get("ui", false)), "org_invite 是 ui 事件")
	assert_eq(inv[0]["p"]["org"], oid)
	assert_eq(inv[0]["p"]["from_name"], "發起人")
	assert_eq(int(inv[0]["p"]["ttl"]), 60)
	# 拒絕 → 邀請沒了
	ook(d, "org_reply", { "org": oid, "accept": false })
	assert_eq(oreason(d, "org_reply", { "org": oid, "accept": true }), "no_invite", "拒絕後不能再接受")
	# 再邀 → 接受
	ook(1, "org_invite", { "name": "遊俠" })
	clear_all_events()
	ook(d, "org_reply", { "org": oid, "accept": true })
	assert_eq(orgs.org_id_of(str(rch(d).id)), oid)
	assert_eq(int(orgs.find(oid)["members"][str(rch(d).id)]["rank"]), 4, "新成員是幫眾")
	assert_eq(evs_of(1, "org_joined").size(), 1, "成員收到 org_joined")
	assert_eq(evs_of(d, "org_joined").size(), 1)
	# 上限
	ws.options["org_member_max"] = 4
	var f := soc_add("滿員客", "xx_square")
	assert_eq(oreason(1, "org_invite", { "name": "滿員客" }), "org_full")
	ws.options["org_member_max"] = 5
	ook(1, "org_invite", { "name": "滿員客" })
	ws.options["org_member_max"] = 4
	assert_eq(oreason(f, "org_reply", { "org": oid, "accept": true }), "org_full", "回覆時也檢查")

func test_invite_expires() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var oid := _found_active(bc[0], bc[1])
	var d := soc_add("遊俠", "xx_square")
	ook(1, "org_invite", { "name": "遊俠" })
	var until := float(orgs.find(oid)["invites"][str(rch(d).id)])
	assert_true(until > ws.world_time(), "有效期")
	ws.world["world_time_s"] = until + 1.0
	assert_eq(oreason(d, "org_reply", { "org": oid, "accept": true }), "no_invite", "過期")
	assert_eq(orgs.org_id_of(str(rch(d).id)), "")

func test_vice_can_invite() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var b: int = bc[0]
	_found_active(b, bc[1])
	ook(1, "org_set_rank", { "name": "連署甲", "rank": 1 })
	soc_add("遊俠", "xx_square")
	ook(b, "org_invite", { "name": "遊俠" })

# ================================================================ 開除、位階、封號、移交、退出、解散

func test_kick_permissions() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var b: int = bc[0]
	var c: int = bc[1]
	var oid := _found_active(b, c)
	assert_eq(oreason(b, "org_kick", { "name": "發起人" }), "no_permission", "幫主不能被踢")
	assert_eq(oreason(b, "org_kick", { "name": "連署乙" }), "no_permission", "同位階不能踢")
	assert_eq(oreason(1, "org_kick", { "name": "發起人" }), "self_target")
	assert_eq(oreason(1, "org_kick", { "name": "路人" }), "no_such_char")
	ook(1, "org_set_rank", { "name": "連署甲", "rank": 3 })
	clear_all_events()
	ook(b, "org_kick", { "name": "連署乙" })
	assert_eq(orgs.org_id_of(str(rch(c).id)), "", "堂主踢幫眾")
	var ke := evs_of(c, "org_kicked")
	assert_eq(ke.size(), 1, "被踢者收到")
	assert_eq(int(ke[0]["p"]["peer"]), c, "被踢者看到 self 變體")
	assert_eq(evs_of(1, "org_kicked").size(), 1, "其他成員收到")
	if "guild" in rch(c):
		assert_eq(str(rch(c).guild), "", "快取清掉")
	# 離線成員也能踢
	ook(1, "org_invite", { "name": "連署乙" })
	ook(c, "org_reply", { "org": oid, "accept": true })
	soc_drop(c)
	ook(1, "org_kick", { "name": "連署乙" })
	assert_eq((orgs.find(oid)["members"] as Dictionary).size(), 2)

func test_rank_title_names() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var b: int = bc[0]
	var c: int = bc[1]
	var oid := _found_active(b, c)
	assert_eq(oreason(b, "org_set_rank", { "name": "連署乙", "rank": 2 }), "no_permission", "只有幫主")
	assert_eq(oreason(1, "org_set_rank", { "name": "連署甲", "rank": 0 }), "bad_value:rank", "不能設 0")
	assert_eq(oreason(1, "org_set_rank", { "name": "連署甲", "rank": 5 }), "bad_value:rank")
	assert_eq(oreason(1, "org_set_rank", { "name": "發起人", "rank": 2 }), "self_target")
	clear_all_events()
	ook(1, "org_set_rank", { "name": "連署甲", "rank": 1 })
	assert_eq(int(orgs.find(oid)["members"][str(rch(b).id)]["rank"]), 1)
	var rc := evs_of(b, "org_rank_changed")
	assert_eq(rc.size(), 1)
	assert_eq(int(rc[0]["p"]["def_peer"]), b, "對象看到 target 變體")
	assert_eq(rc[0]["p"]["rank_name"], "副幫主")
	# 封號：幫主、副幫主可封；副幫主只能封自己或更低位階
	assert_eq(oreason(c, "org_title", { "name": "連署乙", "title": "大俠" }), "no_permission", "幫眾不能封")
	ook(b, "org_title", { "name": "連署乙", "title": "護法" })
	assert_eq(oreason(b, "org_title", { "name": "發起人", "title": "老大" }), "no_permission", "副幫主不能封幫主")
	assert_eq(oreason(1, "org_title", { "name": "連署甲", "title": "一二三四五六七" }), "bad_value:title", "超過 6 字")
	ook(1, "org_title", { "name": "連署甲", "title": "左護法" })
	assert_eq(str(orgs.find(oid)["members"][str(rch(b).id)]["title"]), "左護法")
	ook(1, "org_title", { "name": "連署甲", "title": "" })
	assert_eq(str(orgs.find(oid)["members"][str(rch(b).id)]["title"]), "", "清掉封號")
	# 位階名稱
	assert_eq(oreason(b, "org_rank_names", { "names": ["一", "二", "三", "四", "五"] }), "no_permission")
	assert_eq(oreason(1, "org_rank_names", { "names": ["一", "二", "三", "四"] }), "bad_value:names", "要 5 個")
	assert_eq(oreason(1, "org_rank_names", { "names": ["總瓢把子", "二", "三", "四", "五個字太長"] }), "bad_value:names")
	assert_eq(oreason(1, "org_rank_names", { "names": ["一", "", "三", "四", "五"] }), "bad_value:names", "空的不行")
	ook(1, "org_rank_names", { "names": ["總舵主", "香主", "紅旗", "白旗", "兄弟"] })
	assert_eq(orgs.rank_name(orgs.find(oid), 1), "香主")
	var sh: Variant = orgs.sheet_for(rs(b))
	assert_eq(str(sh["rank_name"]), "香主", "角色表用新名稱")

func test_transfer_leave_disband() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var b: int = bc[0]
	var c: int = bc[1]
	var oid := _found_active(b, c)
	assert_eq(oreason(1, "org_leave"), "leader_must_transfer")
	assert_eq(oreason(b, "org_lead", { "name": "連署乙" }), "no_permission")
	clear_all_events()
	ook(1, "org_lead", { "name": "連署甲" })
	var g: Dictionary = orgs.find(oid)
	assert_eq(str(g["leader"]), str(rch(b).id), "新幫主")
	assert_eq(int(g["members"][str(rch(b).id)]["rank"]), 0)
	assert_eq(int(g["members"][str(ch().id)]["rank"]), 1, "舊幫主改副幫主")
	assert_eq(evs_of(c, "org_leader_changed").size(), 1)
	assert_eq(int(evs_of(b, "org_leader_changed")[0]["p"]["def_peer"]), b)
	# 舊幫主現在可以退出
	clear_all_events()
	ook(1, "org_leave")
	assert_eq(orgs.org_id_of(str(ch().id)), "")
	assert_eq(evs_of(1, "org_left").size(), 1, "自己收到")
	assert_eq(evs_of(c, "org_left").size(), 1, "成員收到")
	assert_eq(oreason(1, "org_leave"), "no_guild")
	# 解散
	assert_eq(oreason(c, "org_disband", { "confirm": true }), "no_permission")
	assert_eq(oreason(b, "org_disband", { "confirm": false }), "need_confirm")
	clear_all_events()
	ook(b, "org_disband", { "confirm": true })
	assert_true(orgs.find(oid).is_empty(), "刪除")
	assert_eq(orgs.org_id_of(str(rch(c).id)), "")
	assert_eq(evs_of(c, "org_disbanded").size(), 1)
	if "guild" in rch(c):
		assert_eq(str(rch(c).guild), "")
	assert_eq(oreason(c, "org_info"), "")
	# 名字可以再用
	ch().fame = 200
	ch().money = 20000
	ook(1, "org_found", { "npc": npc, "name": "江湖小築" })

# ================================================================ 快照形狀

func test_info_and_menu_shapes() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var b: int = bc[0]
	var none: Dictionary = orgs.info_payload(s())
	assert_eq(none["org"], null)
	assert_eq(none["my"], null)
	assert_eq(none["societies"], [])
	assert_eq(int(none["found"]["fee"]), 10000)
	assert_eq(int(none["found"]["fame_min"]), 150)
	assert_eq(int(none["found"]["signer_fame_min"]), 20)
	assert_eq(int(none["found"]["need"]), 2)
	var m: Dictionary = orgs.menu_fields(s(), npc)
	assert_true(m["org"] is Dictionary, "ORG NPC 有 org 欄位")
	assert_eq(m["org"]["can_found"], true)
	assert_eq(m["org"]["petitions"], [])
	var oid := str(ook(1, "org_found", { "npc": npc, "name": "江湖小築" }).get("org", ""))
	var mb: Dictionary = orgs.menu_fields(rs(b), npc)
	assert_eq((mb["org"]["petitions"] as Array).size(), 1)
	var pe: Dictionary = mb["org"]["petitions"][0]
	for k in ["id", "name", "leader_name", "signed", "need"]:
		assert_has(pe, k, "petition 欄位")
	assert_eq(pe["leader_name"], "發起人")
	assert_eq(orgs.menu_fields(s(), "n_xx_zhangbao"), { "org": null }, "非 ORG NPC")
	var pet: Dictionary = orgs.info_payload(s())
	assert_eq(pet["org"]["status"], "PETITION")
	assert_eq(int(pet["org"]["petition"]["need"]), 2)
	assert_eq(pet["my"]["can_disband"], true)
	assert_eq(pet["my"]["can_invite"], false)
	ook(b, "org_sign", { "npc": npc, "org": oid })
	ook(bc[1], "org_sign", { "npc": npc, "org": oid })
	clear_all_events()
	ook(1, "org_info")
	var ev := evs_of(1, "org_info")
	assert_eq(ev.size(), 1, "org_info 送給本人")
	assert_true(bool(ev[0].get("ui", false)), "ui 事件")
	var p: Dictionary = ev[0]["p"]
	var o: Dictionary = p["org"]
	for k in ["id", "name", "status", "leader", "leader_name", "created_s", "rank_names", "member_count", "member_max",
			"members_online", "members", "petition"]:
		assert_has(o, k, "org." + k)
	assert_eq(o["status"], "ACTIVE")
	assert_eq(o["petition"], null)
	assert_eq(int(o["member_count"]), 3)
	assert_eq(int(o["members_online"]), 3)
	assert_eq(o["members"][0]["name"], "發起人", "幫主排第一")
	for k in ["char_id", "name", "rank", "rank_name", "title", "online", "joined_s"]:
		assert_has(o["members"][0], k, "members[]." + k)
	for k in ["rank", "rank_name", "title", "can_invite", "can_kick", "can_set_rank", "can_title", "can_rank_names",
			"can_transfer", "can_disband", "can_leave"]:
		assert_has(p["my"], k, "my." + k)
	assert_eq(p["my"]["can_leave"], false, "幫主不能直接退出")
	assert_eq(p["my"]["can_set_rank"], true)
	var sh: Variant = orgs.sheet_for(s())
	assert_eq(sh, { "id": oid, "name": "江湖小築", "rank": 0, "rank_name": "幫主", "title": "", "leader_name": "發起人",
		"members_online": 3 }, "角色表 org")
	assert_eq(orgs.player_tags(rs(b)), { "org_name": "江湖小築" })
	var d := soc_add("遊俠", "xx_square")
	assert_eq(orgs.sheet_for(rs(d)), null)
	assert_eq(orgs.player_tags(rs(d)), { "org_name": "" })
	rch(d).flags["tdh_member"] = true
	assert_eq(orgs.sheet_fields(rs(d)), { "org": null, "societies": ["天地會"] }, "天地會不是組織")

# ================================================================ 存檔往返與登入校正

func test_save_roundtrip_and_login_fix() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var b: int = bc[0]
	var oid := _found_active(b, bc[1])
	ook(1, "org_set_rank", { "name": "連署甲", "rank": 2 })
	ook(1, "org_title", { "name": "連署甲", "title": "執法" })
	var my_id := str(ch().id)
	var b_id := str(rch(b).id)
	# b 離線時被開除：快取在他登入時校正
	soc_drop(b)
	ook(1, "org_kick", { "name": "連署甲" })
	soc_restart()
	_org_wire()
	assert_true(ws.world.get("guilds") is Array, "world.guilds 存檔")
	var g: Dictionary = orgs.find(oid)
	assert_false(g.is_empty(), "重開後組織還在")
	assert_eq(str(g["status"]), "ACTIVE")
	assert_eq(str(g["leader"]), my_id)
	assert_false((g["members"] as Dictionary).has(b_id), "開除生效")
	assert_eq((g["members"] as Dictionary).size(), 2)
	# 本機重新選角
	var r := me_send("char_select", { "char_id": my_id })
	assert_true(r.get("ok", false), "char_select: %s" % str(r))
	if host().get("orgs") == null:
		orgs.on_login(s())   # GameHost 尚未接線（Day-0）：只驗本 WP 的行為
	assert_eq(orgs.org_id_of(my_id), oid)
	if "guild" in ch():
		assert_eq(str(ch().guild), oid, "登入校正")
		# 存檔裡留著錯的快取 → 登入改正
		ch().guild = "g_stale"
		orgs.on_login(s())
		assert_eq(str(ch().guild), oid)
	assert_eq(orgs.member_name(g, my_id), "發起人")

func test_pending_invite_resent_on_login() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var oid := _found_active(bc[0], bc[1])
	var d := soc_add("遊俠", "xx_square")
	ook(1, "org_invite", { "name": "遊俠" })
	_cap[d] = []
	orgs.on_login(rs(d))
	pump()
	var inv := evs_of(d, "org_invite")
	assert_eq(inv.size(), 1, "登入補送有效的邀請")
	assert_eq(inv[0]["p"]["org"], oid)

## M3b 審查：刪除角色 → 移出組織；幫主被刪 → 交給位階最高的成員；全刪光 → 解散
func test_char_delete_leaves_org() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var b: int = bc[0]
	var c: int = bc[1]
	var oid := _found_active(b, c)
	ook(1, "org_set_rank", { "name": "連署乙", "rank": 2 })
	var doomed := str(ch().id)
	if make_char("留下者") == null:
		return
	var r := me_send("char_delete", { "char_id": doomed, "confirm_name": "發起人" })
	assert_true(r.get("ok", false), "char_delete: %s" % str(r))
	var g: Dictionary = orgs.find(oid)
	assert_false(g.is_empty(), "組織還在")
	assert_false((g["members"] as Dictionary).has(doomed), "刪掉的角色不在成員裡")
	assert_eq(str(g["leader"]), str(rch(c).id), "幫主交給位階最高的連署乙")
	assert_eq(int(g["members"][str(rch(c).id)]["rank"]), 0)
	assert_eq(orgs.leader_name(g), "連署乙")
	# 全部成員刪光 → 解散
	orgs.on_char_deleted(str(rch(c).id))
	orgs.on_char_deleted(str(rch(b).id))
	assert_true(orgs.find(oid).is_empty(), "沒人了 → 組織消失")

# ================================================================ M3b 審查 3

## 退費入帳後馬上存檔、先寫 world.json：磁碟上的待退清掉、角色檔有錢（以前等自動存檔，角色先寫，當機會退兩次）
func test_refund_saved_world_first() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	ws.world["org_refunds"] = { str(ch().id): [{ "org_name": "存檔幫", "money": 700 }] }
	ws.save_now()
	var m0: int = ch().money
	orgs.on_login(s())
	pump()
	assert_eq(ch().money, m0 + 700)
	var disk: Dictionary = SaveManager.load_world(ws.world_id)
	var pend: Variant = disk.get("data", {}).get("org_refunds", {})
	assert_false(pend is Dictionary and (pend as Dictionary).has(str(ch().id)), "world.json 已存：待退清掉")
	var cdisk: Dictionary = SaveManager.load_character(ws.world_id, s().identity, str(ch().id))
	assert_eq(int(cdisk.get("data", {}).get("money", -1)), m0 + 700, "角色檔已存：錢入帳")

## 門派名、天地會不能當組織名（org_name_taken）
func test_found_rejects_sect_and_society_names() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	for n in ["丐幫", "武當", "天地會"]:
		assert_eq(oreason(1, "org_found", { "npc": npc, "name": n }), "org_name_taken", n)
	assert_eq(ch().money, 20000, "沒扣手續費")

# ================================================================ M3b 審查 4

## 簽完連署後加入別的組織的人不算數（以前 sign／tick 直接數 signers，有效連署人不夠也會成立）
func test_stale_signer_not_counted() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var oid := _found_active(bc[0], bc[1])   # 發起人（peer 1）的組織已成立
	var e := soc_add("另起爐灶", ROOM)
	rch(e).fame = 200
	rch(e).money = 20000
	var d := soc_add("牆頭草", ROOM)
	var f := soc_add("後簽者", ROOM)
	rch(d).fame = 30
	rch(f).fame = 30
	var pid := str(ook(e, "org_found", { "npc": npc, "name": "新幫" }).get("org", ""))
	assert_eq(int(ook(d, "org_sign", { "npc": npc, "org": pid }).get("signed", 0)), 1)
	ook(1, "org_invite", { "name": "牆頭草" })
	ook(d, "org_reply", { "org": oid, "accept": true })
	assert_eq(orgs.org_id_of(str(rch(d).id)), oid, "牆頭草加入了已成立的組織")
	var p: Dictionary = orgs.find(pid)
	assert_false(str(rch(d).id) in p.get("signers", []), "加入組織 → 從別的連署名單拿掉")
	assert_false((p.get("signer_names", {}) as Dictionary).has(str(rch(d).id)))
	var r := ook(f, "org_sign", { "npc": npc, "org": pid })
	assert_eq(int(r.get("signed", 0)), 1, "只剩一位有效連署人")
	assert_eq(str(orgs.find(pid).get("status", "")), "PETITION", "有效連署人不夠，不成立")
	# 舊存檔可能還留著已入會的連署人：sign／tick 只數有效的
	(orgs.find(pid)["signers"] as Array).append(str(rch(d).id))
	orgs.tick(host().now_s())
	assert_eq(str(orgs.find(pid).get("status", "")), "PETITION", "tick 也不數已入會的人")
	assert_eq(orgs.valid_signer_count(orgs.find(pid)), 1)

## 創立扣了手續費就存檔（角色檔先、world.json 後）
func test_found_saves_immediately() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var m0: int = ch().money
	var oid := str(ook(1, "org_found", { "npc": npc, "name": "存檔幫" }).get("org", ""))
	var cdisk: Dictionary = SaveManager.load_character(ws.world_id, s().identity, str(ch().id))
	assert_eq(int(cdisk.get("data", {}).get("money", -1)), m0 - 10000, "角色檔已存：手續費已扣")
	var disk: Dictionary = SaveManager.load_world(ws.world_id)
	var found := false
	for g in disk.get("data", {}).get("guilds", []):
		if g is Dictionary and str(g.get("id", "")) == oid:
			found = true
	assert_true(found, "world.json 已存：連署在")

## 受邀的人自己有連署中的組織 → 邀請事件帶 petition_name（提示框警告接受會作廢）
func test_invite_carries_own_petition() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	_found_active(bc[0], bc[1])
	var e := soc_add("自立門戶", ROOM)
	rch(e).fame = 200
	rch(e).money = 20000
	ook(e, "org_found", { "npc": npc, "name": "小幫" })
	clear_all_events()
	ook(1, "org_invite", { "name": "自立門戶" })
	var inv := evs_of(e, "org_invite")
	assert_eq(inv.size(), 1)
	assert_eq(str(inv[0]["p"].get("petition_name", "")), "小幫", "邀請帶受邀者自己的連署名")
	var row := UiSocial.org_row(inv[0]["p"], 0.0)
	assert_true(OrgUi.invite_warning(row).contains("小幫"), "提示框的警告句")
	var d := soc_add("清白人", ROOM)
	clear_all_events()
	ook(1, "org_invite", { "name": "清白人" })
	assert_eq(OrgUi.invite_warning(UiSocial.org_row(evs_of(d, "org_invite")[0]["p"], 0.0)), "", "沒有連署就不警告")
