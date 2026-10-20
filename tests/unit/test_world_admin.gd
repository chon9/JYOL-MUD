extends "res://tests/unit/test_world_fixture.gd"
## M2_PLAN 4.2、4.6.8、4.7：管理員判定、伺服器選項面板、踢人／禁止、重連取代、--opts 解析

func _editable(p: Dictionary) -> Dictionary:
	var out := {}
	for e in p.get("editable", []):
		out[str(e["key"])] = e
	return out

func test_admin_flags() -> void:
	if not game_ok():
		return
	assert_true(s().is_admin, "local host player is admin")
	assert_true(s().is_local)
	make_char("管理甲")
	assert_eq(sheet().get("is_admin", null), true, "sheet.is_admin")
	var peer := add_player("訪客乙")
	assert_false(session_of(peer).is_admin, "remote is not admin")
	assert_eq(sheet_for(peer).get("is_admin", null), false)
	assert_eq(reason_as(peer, "server_opts_get"), "not_admin")
	assert_eq(reason_as(peer, "server_opts_set", { "key": "pk_mode", "value": "OFF" }), "not_admin")
	assert_eq(reason_as(peer, "admin_kick", { "peer": 1 }), "not_admin")
	assert_eq(str(ws.options.get("pk_mode", "")), "CLASSIC", "unchanged")

func test_admin_identities_option() -> void:
	if not game_ok():
		return
	var ident := make_identity(4242)
	ws.options["admin_identities"] = [ident]
	var peer := connect_player("副管", ident)
	assert_true(session_of(peer).is_admin, "identity listed in admin_identities")
	assert_true(send_as(peer, "server_opts_get").get("ok", false))
	assert_eq(evs_for(peer, "server_options").size(), 1)

func test_server_opts_get_shape() -> void:
	if not game_ok():
		return
	make_char("管理甲")
	var peer := add_player("訪客乙")
	clear_events()
	ok("server_opts_get")
	var e := last("server_options")
	assert_true(e.get("ui", false), "ui event")
	var p: Dictionary = e.get("p", {})
	var ed := _editable(p)
	assert_eq(ed.keys().size(), 13, "M3a 的 6 個 + M3B_PLAN §4.11 的 4 個 + M3C_PLAN §9.3 的 2 個 + M3C2_PLAN §8.3 的 spar_daily_cap")
	for k in ["rule_preset", "pk_mode", "wait_mode", "stagecoach_enabled", "scout_enabled", "sect_hostile_entry",
			"enable_era_1_0b", "jail_location", "gb_assembly", "seize_enabled", "npc_respawn_pct", "loot_drop_pct"]:
		assert_has(ed, k, "editable key")
	assert_eq(str(ed["rule_preset"]["label"]), "死亡規則")
	assert_eq(str(ed["rule_preset"]["value"]), "classic_standard")
	assert_eq(str(ed["rule_preset"]["choices"][0]["value"]), "classic_standard", "default preset first")
	assert_eq(ed["rule_preset"]["choices"].size(), GameData.loader.all_tables["rule_profiles"].size())
	# M2 審查：每個規則組合都帶說明；後期官方的屍體消失時間寫明是原作沒寫的暫定值
	for c in ed["rule_preset"]["choices"]:
		assert_true(str(c.get("desc", "")) != "", "desc for %s" % str(c["value"]))
		if str(c["value"]) == "later_official":
			assert_true(str(c["desc"]).contains("原作沒寫"), str(c["desc"]))
	assert_eq(str(ed["sect_hostile_entry"]["label"]), "門派敵對入山")
	assert_eq(str(ed["sect_hostile_entry"]["value"]), "true")
	assert_eq(str(ed["pk_mode"]["value"]), "CLASSIC")
	assert_eq(ed["pk_mode"]["choices"].size(), 3)
	assert_eq(str(ed["wait_mode"]["value"]), "true")
	assert_eq(str(ed["stagecoach_enabled"]["value"]), "false")
	var info: Dictionary = p.get("info", {})
	assert_eq(str(info.get("host_offline_policy", "")), "FROZEN")
	# M2 第三輪審查：封鎖只在 Steam 主機擋得住（ENet／離線的身分是客戶端自報），面板依此決定給不給「踢出並禁止」
	assert_eq(info.get("ban_enforced", true), false, "not a Steam host: ban not enforced")
	assert_eq(str(info.get("world_name", "")), world_name)
	assert_eq(info.get("players", []).size(), 2)
	var me: Dictionary = info["players"][0]
	assert_eq(int(me["peer"]), 1)
	assert_eq(me["is_admin"], true)
	assert_eq(int(info["players"][1]["peer"]), peer)
	assert_true(str(info["players"][1]["identity_short"]).length() <= 14)
	assert_eq(cs.server_options, p, "ClientState keeps last server_options")

func test_server_opts_set_each_key() -> void:
	if not game_ok():
		return
	make_char("管理甲")
	var peer := add_player("訪客乙")
	clear_events_for(peer)
	# rule_preset → 規則立即換成 classic_strict；保留 overrides
	ws.world["rule_profile"] = { "preset": "classic_standard", "overrides": { "jail_enabled": false } }
	ok("server_opts_set", { "key": "rule_preset", "value": "classic_strict" })
	assert_eq(str(GameData.rules.get("death_rule", "")), "STRICT_2001", "rules re-activated")
	assert_eq(GameData.rules.get("jail_enabled", true), false, "overrides kept")
	assert_eq(str(ws.world["rule_profile"]["preset"]), "classic_strict")
	assert_eq(str(ws.options["rule_profile"]["preset"]), "classic_strict")
	var wic := evs_for(peer, "world_info_changed")
	assert_eq(wic.size(), 1, "world_info_changed to everyone")
	if wic.size() == 1:
		assert_true(wic[0].get("ui", false))
		assert_eq(str(wic[0]["p"]["world_info"]["rule_profile"]["death_rule"]), "STRICT_2001")
	var soc := evs_for(peer, "server_option_changed")
	assert_eq(soc.size(), 1)
	if soc.size() == 1:
		assert_eq(str(soc[0]["p"]["label"]), "死亡規則")
		assert_eq(str(soc[0]["p"]["value"]), "懷舊嚴苛（2001）")
	assert_eq(str(cs.world_info.get("rule_profile", {}).get("death_rule", "")), "STRICT_2001", "local world_info updated")
	# pk_mode
	ok("server_opts_set", { "key": "pk_mode", "value": "OFF" })
	assert_eq(str(ws.options["pk_mode"]), "OFF")
	assert_eq(str(ws.world_info()["pk_mode"]), "OFF")
	# wait_mode（bool）
	ok("server_opts_set", { "key": "wait_mode", "value": "false" })
	assert_eq(ws.options["wait_mode"], false)
	assert_eq(ws.world_info()["wait_mode"], false)
	assert_eq(host().battles.battle_opts("xixia")["wait_mode"], false, "new battles use it")
	# stagecoach_enabled
	ok("server_opts_set", { "key": "stagecoach_enabled", "value": "true" })
	assert_eq(ws.options["stagecoach_enabled"], true)
	# 存進 options.json 與 world.json
	var saved: Dictionary = sm.load_options(ws.world_id)
	assert_eq(str(saved.get("pk_mode", "")), "OFF")
	assert_eq(saved.get("wait_mode", true), false)
	assert_eq(saved.get("stagecoach_enabled", false), true)
	var wj: Dictionary = sm.load_world(ws.world_id)["data"]
	assert_eq(str(wj["rule_profile"]["preset"]), "classic_strict")
	# 錯誤
	assert_eq(reason("server_opts_set", { "key": "max_players", "value": "2" }), "bad_option")
	assert_eq(reason("server_opts_set", { "key": "pk_mode", "value": "NOPE" }), "bad_value:value")
	assert_eq(reason("server_opts_set", { "key": "wait_mode", "value": "yes" }), "bad_value:value")
	assert_eq(reason("server_opts_set", { "key": "rule_preset", "value": "no_such_preset" }), "bad_value:value")
	# 重開世界：設定都還在
	restart_world()
	assert_eq(str(ws.options.get("pk_mode", "")), "OFF")
	assert_eq(ws.options.get("wait_mode", true), false)
	assert_eq(str(GameData.rules.get("death_rule", "")), "STRICT_2001", "rule preset survives restart")

func test_admin_kick_and_ban() -> void:
	if not game_ok():
		return
	make_char("管理甲")
	var a := add_player("訪客乙")
	var b := add_player("訪客丙")
	var a_ident := identity_of(a)
	assert_eq(reason("admin_kick", { "peer": 1 }), "bad_target", "self")
	assert_eq(reason("admin_kick", { "peer": 999 }), "bad_target", "no such peer")
	clear_events_for(b)
	ok("admin_kick", { "peer": a, "ban": true })
	assert_eq(str(remote[a].get("kick", "")), "admin", "kicked peer told why")
	assert_false(ws.sessions.has(a), "session removed at once")
	assert_eq(evs_for(b, "player_kicked").size(), 1, "others told")
	if evs_for(b, "player_kicked").size() == 1:
		assert_eq(str(evs_for(b, "player_kicked")[0]["p"]["name"]), "訪客乙")
	assert_eq(ws.world["known_identities"][a_ident]["banned"], true)
	assert_eq(reason_as(a, "look"), "drop:no_session", "kicked peer can't act")
	# 再 hello 被拒 banned
	ws.on_peer_connected(500)
	assert_eq(ws.handle_hello(500, { "protocol": Protocol.VERSION, "game_version": Protocol.GAME_VERSION,
		"content_hash": GameData.content_hash, "identity": a_ident, "display_name": "x" }), "banned")
	# 只踢不禁止：可以再加入
	var b_ident := identity_of(b)
	ok("admin_kick", { "peer": b })
	assert_false(ws.world["known_identities"][b_ident].get("banned", false))
	var b2 := connect_player("訪客丙", b_ident)
	assert_true(ws.sessions.has(b2), "rejoined after plain kick")
	# 禁止名單在重開世界後還在
	restart_world()
	assert_eq(ws.validate_hello(600, { "protocol": Protocol.VERSION, "game_version": Protocol.GAME_VERSION,
		"content_hash": GameData.content_hash, "identity": a_ident, "display_name": "x" }), "banned")

func test_reconnect_replaces_old_session() -> void:
	if not game_ok():
		return
	make_char("管理甲")
	goto("xx_square")
	var a := add_player("重連俠")
	var ident := identity_of(a)
	var char_id := str(session_of(a).character.id)
	goto_as(a, "xx_square")
	session_of(a).character.money = 4321
	clear_events()
	var a2 := connect_player("重連俠", ident)
	assert_true(ws.sessions.has(a2), "new session accepted")
	assert_false(ws.sessions.has(a), "old session removed")
	assert_eq(evs("char_left").size(), 1, "old character left the room")
	var r: Dictionary = sm.load_character(ws.world_id, ident, char_id)
	assert_eq(int(r["data"]["money"]), 4321, "old session saved before removal")
	assert_true(send_as(a2, "char_select", { "char_id": char_id }).get("ok", false), "select again")
	assert_eq(int(session_of(a2).character.money), 4321)
	# 主機本機玩家不會被同身分取代
	assert_eq(ws.validate_hello(700, { "protocol": Protocol.VERSION, "game_version": Protocol.GAME_VERSION,
		"content_hash": GameData.content_hash, "identity": s().identity, "display_name": "x" }), "already_connected")
	# 滿員時，同身分重連不算多一人
	ws.options["max_players"] = ws.sessions.size()
	var a3 := connect_player("重連俠", ident)
	assert_true(ws.sessions.has(a3), "reconnect allowed when full")
	assert_eq(ws.validate_hello(701, { "protocol": Protocol.VERSION, "game_version": Protocol.GAME_VERSION,
		"content_hash": GameData.content_hash, "identity": make_identity(701), "display_name": "x" }), "server_full")

func test_cli_opts_parse() -> void:
	var d: Dictionary = GameData.default_server_options()
	var r: Dictionary = ws.parse_cli_opts("newbie_pk_protect_xp=0,guards_enabled=off,pk_mode=CHALLENGE_ONLY,party_max=4", d)
	assert_eq(str(r["error"]), "")
	assert_eq(r["values"], { "newbie_pk_protect_xp": 0, "guards_enabled": false, "pk_mode": "CHALLENGE_ONLY", "party_max": 4 })
	assert_eq(typeof(r["values"]["party_max"]), TYPE_INT)
	assert_true(str(ws.parse_cli_opts("max_players=3", d)["error"]) != "", "not a CLI key")
	assert_true(str(ws.parse_cli_opts("pk_mode=WAR", d)["error"]) != "", "bad enum")
	assert_true(str(ws.parse_cli_opts("party_max=abc", d)["error"]) != "", "bad int")
	assert_true(str(ws.parse_cli_opts("party_max=-1", d)["error"]) != "", "negative")
	assert_true(str(ws.parse_cli_opts("wait_mode=maybe", d)["error"]) != "", "bad bool")
	assert_true(str(ws.parse_cli_opts("oops", d)["error"]) != "", "no =")
	assert_true(ws.parse_cli_opts("oops", d)["values"].is_empty())

func test_default_options_have_m2_keys() -> void:
	var d: Dictionary = GameData.default_server_options()
	assert_eq(d.get("guards_enabled"), true)
	assert_eq(d.get("chat_water_cost"), 1)
	assert_eq(d.get("chat_min_interval_ms"), 500)
	assert_eq(d.get("party_max"), 5)
	assert_eq(d.get("battle_max_humans"), 8)
	assert_eq(d.get("pending_ttl_real_s"), 60)
	assert_eq(d.get("mail_inbox_max"), 50)
	assert_eq(d.get("mail_min_interval_real_s"), 10)
	assert_eq(d.get("corpse_auth_max"), 4)
	assert_eq(d.get("admin_identities"), [])
	# 既有世界的 options.json 缺新 key 時補預設值
	ws.stop()
	var o: Dictionary = sm.load_options(world_name)
	o.erase("party_max")
	sm.save_options(world_name, o)
	assert_eq(ws.start(world_name), OK)
	cs.begin_local_session()
	assert_eq(ws.options.get("party_max"), 5, "missing key filled")

func test_world_span_and_clean_text() -> void:
	if not game_ok():
		return
	var old: float = ws.time_scale
	ws.time_scale = 50.0
	assert_eq(host().world_span(60.0), 3000.0)
	assert_eq(host().real_span(3000.0), 60.0)
	ws.time_scale = old
	assert_eq(host().clean_text("[color=red]x[/color]\n", 200), "［color=red］x［/color］")

func test_name_lookups() -> void:
	if not game_ok():
		return
	make_char("查名甲")
	var peer := add_player("Abc俠")
	var cid := str(session_of(peer).character.id)
	assert_eq(host().session_for_char_name("abc俠"), session_of(peer), "case-insensitive")
	assert_eq(host().session_for_char_name("無此人"), null)
	assert_eq(host().char_ref_by_name("ABC俠"), { "identity": identity_of(peer), "char_id": cid })
	assert_eq(host().char_ref_by_name("無此人"), {})
	assert_eq(host().pvp_char_name(cid), "Abc俠")
	drop_player(peer)
	assert_eq(host().session_for_char_name("Abc俠"), null, "offline")
	assert_eq(host().pvp_char_name(cid), "Abc俠", "offline lookup keeps case")
	assert_eq(host().pvp_char_name("ch_none"), "")

## M3c 整合（M3C_PLAN §9.3）：npc_respawn_pct、loot_drop_pct 在伺服器設定面板可改（百分比選項），存進 options.json
func test_server_opts_set_m3c_pct() -> void:
	if not game_ok():
		return
	make_char("管理丙")
	ok("server_opts_get")
	var ed := _editable(last("server_options").get("p", {}))
	assert_eq(str(ed["npc_respawn_pct"]["value"]), "100")
	assert_eq(str(ed["loot_drop_pct"]["label"]), "掉寶倍率")
	ok("server_opts_set", { "key": "npc_respawn_pct", "value": "50" })
	ok("server_opts_set", { "key": "loot_drop_pct", "value": "200" })
	assert_eq(int(ws.options["npc_respawn_pct"]), 50)
	assert_eq(int(ws.options["loot_drop_pct"]), 200)
	assert_eq(int(sm.load_options(ws.world_id).get("loot_drop_pct", 0)), 200, "saved")
	assert_eq(reason("server_opts_set", { "key": "loot_drop_pct", "value": "5000" }), "bad_value:value")
	var parsed: Dictionary = ws.parse_cli_opts("npc_respawn_pct=200,loot_drop_pct=150", ws.options)
	assert_eq(str(parsed["error"]), "")
	assert_eq(int(parsed["values"]["loot_drop_pct"]), 150)
