extends "res://tests/unit/test_social_fixture.gd"
## WP-ORG：組織頻道 CHAT_GUILD（M3B_PLAN §5.3、§11.1）。只送組織在線成員（含不同房、含自己）；
## 非成員 no_guild（不耗水）；成員發話耗水；連署中不算；被開除、離線、沒有 OrgSystem 的情況。
## 場景輔助與 test_m3b_org.gd 相同（複製一份：繼承測試檔會讓執行器把父類的 test_ 再跑一次）。

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


func _chat(peer: int, text: String) -> Dictionary:
	return soc_send(peer, "chat", { "text": text, "ch": "CHAT_GUILD" })

func _water(peer: int) -> int:
	return int(cof(peer).vitals.get("water", 0))

func test_guild_chat_reaches_online_members_only() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var b: int = bc[0]
	var c: int = bc[1]
	_found_active(b, c)
	goto("xx_square")                                  # 不同房也收得到
	var outsider := soc_add("旁觀者丙", ROOM)          # 同房但不是成員
	var watcher := soc_add("")                          # 沒選角
	clear_all_events()
	var w0 := _water(b)
	var r := _chat(b, "今晚衙門口集合")
	assert_true(r.get("ok", false), "guild chat: %s" % str(r))
	for peer in [1, b, c]:
		assert_eq(evs_of(peer, "chat_guild").size(), 1, "成員 %d 收到" % peer)
	assert_eq(evs_of(outsider, "chat_guild").size(), 0, "非成員收不到")
	assert_eq(evs_of(watcher, "chat_guild").size(), 0, "未選角收不到")
	var e: Dictionary = evs_of(1, "chat_guild")[0]
	assert_eq(e["ch"], "CHAT_GUILD")
	assert_eq(e["p"]["from"], "連署甲")
	assert_eq(int(e["p"]["from_peer"]), b)
	assert_eq(e["p"]["text"], "今晚衙門口集合")
	assert_eq(_water(b), w0 - int(ws.options.get("chat_water_cost", 1)), "組織頻道耗水")

func test_non_member_no_guild_and_no_water() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	_found_active(bc[0], bc[1])
	var outsider := soc_add("旁觀者丙", ROOM)
	clear_all_events()
	var w0 := _water(outsider)
	assert_eq(str(_chat(outsider, "我也要聽").get("reason", "")), "no_guild")
	assert_eq(_water(outsider), w0, "失敗不耗水")
	for peer in [1, bc[0], bc[1]]:
		assert_eq(evs_of(peer, "chat_guild").size(), 0)

func test_petition_is_not_a_guild() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	ook(1, "org_found", { "npc": npc, "name": "江湖小築" })
	assert_eq(str(_chat(1, "連署中").get("reason", "")), "no_guild", "連署中還沒有組織頻道")

func test_kicked_member_loses_channel() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var b: int = bc[0]
	var c: int = bc[1]
	_found_active(b, c)
	ook(1, "org_kick", { "name": "連署乙" })
	clear_all_events()
	assert_eq(str(_chat(c, "我還在嗎").get("reason", "")), "no_guild")
	assert_true(_chat(1, "清理門戶").get("ok", false))
	assert_eq(evs_of(c, "chat_guild").size(), 0, "被開除的人收不到")
	assert_eq(evs_of(b, "chat_guild").size(), 1)

func test_offline_member_skipped() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	var b: int = bc[0]
	var c: int = bc[1]
	_found_active(b, c)
	soc_drop(c)
	clear_all_events()
	assert_true(_chat(1, "點名").get("ok", false))
	assert_eq(evs_of(b, "chat_guild").size(), 1)
	assert_eq(evs_of(1, "chat_guild").size(), 1, "自己也收到")

func test_no_org_system_means_no_guild() -> void:
	var bc := _setup()
	if bc.is_empty():
		return
	_found_active(bc[0], bc[1])
	# OrgSystem 不存在（L3：載入失敗）時一律 no_guild
	var fake := SocialSystem.new(host())
	fake.orgs_override = null
	if host().get("orgs") == null:
		assert_eq(fake.guild_peers_of(s()), [], "沒有 OrgSystem")
	fake.orgs_override = orgs
	assert_eq((fake.guild_peers_of(s()) as Array).size(), 3, "三位在線成員")
