extends "res://tests/test_case.gd"
## M2_PLAN 4.1：新 intent 的型別、必填、列舉、範圍；chat 的 to 規則；飛鴿長度；護照大小；VERSION == 3；文字清理（H6）

func _v(kind: String, args: Dictionary) -> String:
	return Protocol.validate_args(kind, args)

func test_version_is_3() -> void:
	assert_true(Protocol.VERSION >= 3, "M2 起至少 3（M3a 升到 4）")

func test_all_m2_intents_known() -> void:
	for k in ["party_invite", "party_reply", "party_leave", "party_kick", "party_lead", "battle_join", "challenge",
			"challenge_reply", "force_pk", "set_pref", "corpse_authorize", "mail_send", "mail_list", "mail_read",
			"mail_delete", "server_opts_get", "server_opts_set", "admin_kick", "passport_request", "passport_restore",
			"passport_import"]:
		assert_true(Protocol.is_known(k), k)
	assert_eq(Protocol.I_PASSPORT_IMPORT, "passport_import")
	assert_eq(Protocol.I_BATTLE_JOIN, "battle_join")

func test_constants() -> void:
	assert_eq(Protocol.CHAT_CHANNELS, ["CHAT_WORLD", "CHAT_WHISPER", "CHAT_SAY", "CHAT_SECT", "CHAT_GUILD",
		"CHAT_PARTY", "CHAT_RUMOR", "GM"])
	assert_eq(Protocol.CH_MAIL, "MAIL")
	assert_false(Protocol.CH_MAIL in Protocol.CHAT_CHANNELS, "MAIL is not a chat channel")
	assert_eq(Protocol.MAIL_MAX_LEN, 200)
	assert_eq(Protocol.PASSPORT_MAX_BYTES, 65536)
	assert_eq(Protocol.PREF_KEYS, ["accept_challenge", "accept_party"])
	assert_eq(Protocol.PK_MODES, ["CLASSIC", "CHALLENGE_ONLY", "OFF"])

func test_event_key_constants() -> void:
	assert_eq(Protocol.E_PARTY_JOINED, "party_joined")
	assert_eq(Protocol.E_CHAT_WHISPER, "chat_whisper")
	assert_eq(Protocol.E_BATTLE_UNIT_JOIN, "battle_unit_join")
	assert_eq(Protocol.E_FORCE_PK_START, "force_pk_start")
	assert_eq(Protocol.E_KILLING_INTENT_CHANGE, "killing_intent_change")
	assert_eq(Protocol.E_CORPSE_PUBLIC, "corpse_public")
	assert_eq(Protocol.E_MAIL_WAITING, "mail_waiting")
	assert_eq(Protocol.E_WORLD_INFO_CHANGED, "world_info_changed")
	assert_eq(Protocol.E_HOST_CLOSING, "host_closing")
	assert_eq(Protocol.E_PASSPORT_RESTORED, "passport_restored")

func test_party_and_pk_types() -> void:
	assert_eq(_v("party_invite", { "target": "ch_1" }), "")
	assert_eq(_v("party_invite", {}), "missing_arg:target")
	assert_eq(_v("party_invite", { "target": 3 }), "bad_type:target")
	assert_eq(_v("party_reply", { "from": "ch_1", "accept": true }), "")
	assert_eq(_v("party_reply", { "from": "ch_1", "accept": 1 }), "bad_type:accept")
	assert_eq(_v("party_reply", { "from": "ch_1" }), "missing_arg:accept")
	assert_eq(_v("party_leave", {}), "")
	assert_eq(_v("party_leave", { "x": 1 }), "unexpected_arg")
	assert_eq(_v("party_kick", { "target": "x".repeat(65) }), "bad_value:target")
	assert_eq(_v("party_lead", { "target": "ch_2" }), "")
	assert_eq(_v("challenge", { "target": "ch_2" }), "")
	assert_eq(_v("challenge_reply", { "from": "ch_2", "accept": false }), "")
	assert_eq(_v("force_pk", { "target": "ch_2" }), "")
	assert_eq(_v("force_pk", {}), "missing_arg:target")

func test_battle_join_range() -> void:
	assert_eq(_v("battle_join", { "battle_id": 1 }), "")
	assert_eq(_v("battle_join", { "battle_id": 2147483647 }), "")
	assert_eq(_v("battle_join", { "battle_id": 0 }), "bad_value:battle_id")
	assert_eq(_v("battle_join", { "battle_id": -5 }), "bad_value:battle_id")
	assert_eq(_v("battle_join", { "battle_id": 1.0 }), "bad_type:battle_id")

func test_set_pref_enum() -> void:
	assert_eq(_v("set_pref", { "key": "accept_challenge", "value": false }), "")
	assert_eq(_v("set_pref", { "key": "accept_party", "value": true }), "")
	assert_eq(_v("set_pref", { "key": "show_name", "value": true }), "bad_value:key")
	assert_eq(_v("set_pref", { "key": "accept_party", "value": "true" }), "bad_type:value")

func test_corpse_and_loot() -> void:
	assert_eq(_v("corpse_authorize", { "corpse_id": "cp_1", "name": "阿朱" }), "")
	assert_eq(_v("corpse_authorize", { "corpse_id": "cp_1" }), "missing_arg:name")
	assert_eq(_v("loot_corpse", { "corpse_id": "cp_1" }), "")
	assert_eq(_v("loot_corpse", { "corpse_id": "cp_1", "item_uid": "it_1" }), "")
	assert_eq(_v("loot_corpse", { "corpse_id": "cp_1", "item_uid": 3 }), "bad_type:item_uid")

func test_chat_to_rules() -> void:
	assert_eq(_v("chat", { "text": "hi", "ch": "CHAT_SAY" }), "")
	assert_eq(_v("chat", { "text": "hi", "ch": "GM" }), "")
	assert_eq(_v("chat", { "text": "hi", "ch": "CHAT_RUMOR" }), "")
	assert_eq(_v("chat", { "text": "hi", "ch": "MAIL" }), "bad_channel")
	assert_eq(_v("chat", { "text": "hi", "ch": "CHAT_WHISPER", "to": "阿朱" }), "")
	assert_eq(_v("chat", { "text": "hi", "ch": "CHAT_WHISPER" }), "missing_arg:to")
	assert_eq(_v("chat", { "text": "hi", "to": "阿朱" }), "unexpected_arg", "to without whisper (default world)")
	assert_eq(_v("chat", { "text": "hi", "ch": "CHAT_SAY", "to": "阿朱" }), "unexpected_arg")
	assert_eq(_v("chat", { "text": "hi", "ch": "CHAT_WHISPER", "to": "x".repeat(65) }), "bad_value:to")
	assert_eq(_v("chat", { "text": "hi", "ch": "CHAT_WHISPER", "to": 5 }), "bad_type:to")
	# 順序：empty_text 在 to 規則之前
	assert_eq(_v("chat", { "text": "  ", "ch": "CHAT_WHISPER" }), "empty_text")
	assert_eq(_v("chat", { "text": "x".repeat(Protocol.CHAT_MAX_LEN), "ch": "CHAT_SAY" }), "", "200 chars ok")

func test_mail_lengths() -> void:
	assert_eq(_v("mail_send", { "to": "阿朱", "text": "x".repeat(200) }), "", "text is not capped at 64")
	assert_eq(_v("mail_send", { "to": "阿朱", "text": "x".repeat(201) }), "text_too_long")
	assert_eq(_v("mail_send", { "to": "阿朱", "text": "   " }), "empty_text")
	assert_eq(_v("mail_send", { "to": "x".repeat(65), "text": "hi" }), "bad_value:to")
	assert_eq(_v("mail_send", { "to": "阿朱" }), "missing_arg:text")
	assert_eq(_v("mail_list", {}), "")
	assert_eq(_v("mail_read", { "id": "ml_1" }), "")
	assert_eq(_v("mail_delete", {}), "missing_arg:id")

func test_admin_args() -> void:
	assert_eq(_v("server_opts_get", {}), "")
	assert_eq(_v("server_opts_set", { "key": "pk_mode", "value": "OFF" }), "")
	assert_eq(_v("server_opts_set", { "key": "wait_mode", "value": true }), "bad_type:value")
	assert_eq(_v("admin_kick", { "peer": 5 }), "")
	assert_eq(_v("admin_kick", { "peer": 5, "ban": true }), "")
	assert_eq(_v("admin_kick", { "peer": 0 }), "bad_value:peer")
	assert_eq(_v("admin_kick", { "peer": 5, "ban": "yes" }), "bad_type:ban")

func test_passport_args() -> void:
	assert_eq(_v("passport_request", { "char_id": "ch_1" }), "")
	assert_eq(_v("passport_restore", { "passport": { "v": 1 } }), "")
	assert_eq(_v("passport_restore", { "passport": "x" }), "bad_type:passport")
	assert_eq(_v("passport_import", { "passport": {} }), "")
	var big := { "char": { "blob": "x".repeat(Protocol.PASSPORT_MAX_BYTES) } }
	assert_eq(_v("passport_restore", { "passport": big }), "bad_value:passport")
	assert_eq(_v("passport_import", { "passport": big }), "bad_value:passport")
	# 護照裡的長字串（角色名、簽章）不受 64 字上限限制，只看整體大小
	assert_eq(_v("passport_restore", { "passport": { "sig": "a".repeat(64 * 3) } }), "")

func test_clean_text() -> void:
	assert_eq(Protocol.clean_text("  [b]你好[/b]  ", 200), "［b］你好［/b］")
	assert_eq(Protocol.clean_text("a\nb\tc", 200), "a b c")
	assert_eq(Protocol.clean_text("a" + String.chr(7) + "b" + String.chr(0x7F) + "c", 200), "abc")
	assert_eq(Protocol.clean_text("一二三四五", 3), "一二三")
	assert_eq(Protocol.clean_text("   ", 10), "")
