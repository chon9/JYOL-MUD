extends "res://tests/test_case.gd"
## WP-SOCIAL 純邏輯：頻道常數與 4.1 一致、耗水頻道清單、本地文字清理（H6 的相容版本）。

func test_channel_constants_match_contract() -> void:
	assert_eq(SocialSystem.CHANNELS, ["CHAT_WORLD", "CHAT_WHISPER", "CHAT_SAY", "CHAT_SECT", "CHAT_GUILD",
		"CHAT_PARTY", "CHAT_RUMOR", "GM"], "4.1 CHAT_CHANNELS 順序")
	assert_eq(SocialSystem.WATER_CHANNELS, ["CHAT_WORLD", "CHAT_SAY", "CHAT_SECT", "CHAT_GUILD", "CHAT_PARTY",
		"CHAT_RUMOR"], "4.6.6 WATER_CHANNELS")
	assert_false("CHAT_WHISPER" in SocialSystem.WATER_CHANNELS, "密語不耗水")
	assert_false("GM" in SocialSystem.WATER_CHANNELS, "天外飛仙不耗水")

func test_constants_agree_with_protocol_when_present() -> void:
	# Day-0 合併後 Protocol 會有這些常數；之前只驗已存在的
	var pairs := {
		"CH_CHAT_WHISPER": SocialSystem.CH_WHISPER, "CH_CHAT_SAY": SocialSystem.CH_SAY,
		"CH_CHAT_SECT": SocialSystem.CH_SECT, "CH_CHAT_GUILD": SocialSystem.CH_GUILD,
		"CH_CHAT_PARTY": SocialSystem.CH_PARTY, "CH_CHAT_RUMOR": SocialSystem.CH_RUMOR, "CH_GM": SocialSystem.CH_GM,
		"CH_MAIL": MailSystem.CH_MAIL, "MAIL_MAX_LEN": MailSystem.MAIL_MAX_LEN,
		"E_CHAT_SAY": SocialSystem.E_CHAT_SAY, "E_CHAT_SECT": SocialSystem.E_CHAT_SECT,
		"E_CHAT_PARTY": SocialSystem.E_CHAT_PARTY, "E_CHAT_WHISPER": SocialSystem.E_CHAT_WHISPER,
		"E_CHAT_RUMOR": SocialSystem.E_CHAT_RUMOR, "E_CHAT_GM": SocialSystem.E_CHAT_GM,
		"E_MAIL_SENT": MailSystem.E_MAIL_SENT, "E_MAIL_ARRIVED": MailSystem.E_MAIL_ARRIVED,
		"E_MAIL_WAITING": MailSystem.E_MAIL_WAITING, "E_MAIL_LIST": MailSystem.E_MAIL_LIST,
		"I_MAIL_SEND": IntentsSocial.I_MAIL_SEND, "I_MAIL_LIST": IntentsSocial.I_MAIL_LIST,
		"I_MAIL_READ": IntentsSocial.I_MAIL_READ, "I_MAIL_DELETE": IntentsSocial.I_MAIL_DELETE,
	}
	var consts: Dictionary = (load("res://core/protocol.gd") as GDScript).get_script_constant_map()
	for k in pairs:
		if consts.has(k):
			assert_eq(consts[k], pairs[k], "Protocol." + k)
	if consts.has("CHAT_CHANNELS") and (consts["CHAT_CHANNELS"] as Array).size() > 1:
		assert_eq(consts["CHAT_CHANNELS"], SocialSystem.CHANNELS, "Protocol.CHAT_CHANNELS")

func test_clean_text_local() -> void:
	assert_eq(SocialSystem.clean_text_local("  [b]hi[/b]  ", 200), "［b］hi［/b］")
	assert_eq(SocialSystem.clean_text_local("a" + char(1) + "b" + char(7) + "c" + char(0x1b) + "d", 200), "abcd", "控制字元")
	assert_eq(SocialSystem.clean_text_local("一\n二\t三", 200), "一 二 三", "換行與 tab 變空白")
	assert_eq(SocialSystem.clean_text_local("x" + char(0x85) + "y" + char(0x7f) + "z", 200), "xyz", "C1 與 DEL")
	assert_eq(SocialSystem.clean_text_local("abcdef", 3), "abc", "截長度")
	assert_eq(SocialSystem.clean_text_local(char(1) + char(2), 200), "", "全是控制字元 → 空")
	assert_eq(SocialSystem.clean_text_local("江湖謠言", 200), "江湖謠言", "中文不變")
