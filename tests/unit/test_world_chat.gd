extends "res://tests/unit/test_social_fixture.gd"
## WP-SOCIAL：聊天頻道（M2_PLAN 4.6.6、4.4.3、5.4、6.1）。
## 本機 peer 1 在 xx_square；B 同房、C 在 xx_gate_e。

const ROOM_A := "xx_square"
const ROOM_B := "xx_gate_e"

var b := 0
var c := 0

func _setup_three(b_sect := "", c_sect := "") -> bool:
	if not game_ok():
		return false
	if make_char("說話者") == null:
		return false
	goto(ROOM_A)
	b = soc_add("同房客", ROOM_A, b_sect)
	c = soc_add("隔壁客", ROOM_B, c_sect)
	clear_all_events()
	return true

func _water(peer: int) -> int:
	var x = ch() if peer == 1 else rch(peer)
	return int(x.vitals.get("water", 0))

func _chat(peer: int, text: String, chan := "", to := "") -> Dictionary:
	var a := { "text": text }
	if chan != "":
		a["ch"] = chan
	if to != "":
		a["to"] = to
	return soc_send(peer, "chat", a)

func _got(peer: int, key: String) -> int:
	return evs_of(peer, key).size()

# ---------- 每個頻道的收件人集合 ----------
func test_world_channel_reaches_everyone_and_costs_water() -> void:
	if not _setup_three():
		return
	var watcher := soc_add("")          # 沒選角的 session 也收得到千里傳音
	clear_all_events()
	var w0 := _water(1)
	assert_true(_chat(1, "大家好").get("ok", false), "world chat")
	for peer in [1, b, c, watcher]:
		assert_eq(_got(peer, "chat"), 1, "peer %d gets chat" % peer)
	var e: Dictionary = evs_of(b, "chat")[0]
	assert_eq(e["ch"], "CHAT_WORLD")
	assert_eq(e["p"]["from"], "說話者")
	assert_eq(int(e["p"]["from_peer"]), 1)
	assert_eq(e["p"]["text"], "大家好")
	assert_eq(_water(1), w0 - 1, "千里傳音耗水 1（M0 處理器已被覆蓋）")

func test_say_reaches_same_room_only() -> void:
	if not _setup_three():
		return
	var w0 := _water(1)
	assert_true(_chat(1, "悄悄話", "CHAT_SAY").get("ok", false), "say")
	assert_eq(_got(1, "chat_say"), 1, "self")
	assert_eq(_got(b, "chat_say"), 1, "same room")
	assert_eq(_got(c, "chat_say"), 0, "other room")
	assert_eq(evs_of(b, "chat_say")[0]["ch"], "CHAT_SAY")
	assert_eq(_water(1), w0 - 1, "輕聲細語耗水")

func test_sect_channel_and_no_sect() -> void:
	if not _setup_three("shaolin", "huashan"):
		return
	assert_eq(_reason_chat(1, "師兄", "CHAT_SECT"), "no_sect", "我沒有門派")
	ch().sect = "shaolin"
	var far := soc_add("遠方師弟", ROOM_B, "shaolin")
	clear_all_events()
	var w0 := _water(1)
	assert_true(_chat(1, "師兄弟們", "CHAT_SECT").get("ok", false), "sect chat")
	assert_eq(_got(1, "chat_sect"), 1, "self")
	assert_eq(_got(b, "chat_sect"), 1, "同門同房")
	assert_eq(_got(far, "chat_sect"), 1, "同門不同房")
	assert_eq(_got(c, "chat_sect"), 0, "別派")
	assert_eq(_water(1), w0 - 1)

func test_guild_always_no_guild() -> void:
	if not _setup_three():
		return
	ch().sect = "shaolin"
	var w0 := _water(1)
	assert_eq(_reason_chat(1, "幫主", "CHAT_GUILD"), "no_guild")
	assert_eq(_water(1), w0, "失敗不耗水")

func test_party_channel_uses_party_members() -> void:
	if not _setup_three():
		return
	var w0 := _water(1)
	social.party_override = null
	if host().get("party") == null:
		assert_eq(_reason_chat(1, "隊友", "CHAT_PARTY"), "no_party_chat", "沒有組隊系統＝沒有隊伍")
	var fake := FakeParty.new()
	social.party_override = fake
	assert_eq(_reason_chat(1, "隊友", "CHAT_PARTY"), "no_party_chat", "沒有隊伍")
	assert_eq(_water(1), w0, "失敗不耗水")
	fake.members = [1, c]
	assert_true(_chat(1, "集合", "CHAT_PARTY").get("ok", false), "party chat")
	assert_eq(_got(1, "chat_party"), 1, "self")
	assert_eq(_got(c, "chat_party"), 1, "隊友（不同房也收得到）")
	assert_eq(_got(b, "chat_party"), 0, "非隊友")
	assert_eq(_water(1), w0 - 1)
	social.party_override = null

func test_whisper_only_two_parties_no_water() -> void:
	if not _setup_three():
		return
	var w0 := _water(1)
	assert_true(_chat(1, "只告訴你", "CHAT_WHISPER", "隔壁客").get("ok", false), "whisper")
	assert_eq(_got(1, "chat_whisper"), 1, "self")
	assert_eq(_got(c, "chat_whisper"), 1, "target")
	assert_eq(_got(b, "chat_whisper"), 0, "旁人")
	var p: Dictionary = evs_of(c, "chat_whisper")[0]["p"]
	assert_eq(p["to_name"], "隔壁客")
	assert_eq(p["from"], "說話者")
	assert_eq(int(p["from_peer"]), 1)
	assert_eq(_water(1), w0, "傳音入密不耗水")

func test_whisper_errors() -> void:
	if not _setup_three():
		return
	assert_eq(_reason_chat(1, "喂", "CHAT_WHISPER", "查無此人"), "no_such_player")
	assert_eq(_reason_chat(1, "喂", "CHAT_WHISPER", "說話者"), "bad_target", "自己")
	soc_drop(c)
	assert_eq(_reason_chat(1, "喂", "CHAT_WHISPER", "隔壁客"), "no_such_player", "離線")

func test_rumor_is_anonymous_for_others() -> void:
	if not _setup_three():
		return
	var watcher := soc_add("")
	clear_all_events()
	var w0 := _water(1)
	# 審查修正：江湖謠言頻道預設要基本內功 80（rumor_chat_inner_min，照原作）
	assert_eq(_reason_chat(1, "聽說鬼王出世了", "CHAT_RUMOR"), "req_skill_min", "基本內功不到 80 不能在謠言頻道說話")
	assert_eq(_water(1), w0, "被擋下不耗水")
	ch().skills.set_level("basic_inner", 80, GameData.tables)
	assert_true(_chat(1, "聽說鬼王出世了", "CHAT_RUMOR").get("ok", false), "rumor")
	for peer in [1, b, c, watcher]:
		assert_eq(_got(peer, "chat_rumor"), 1, "peer %d gets rumor" % peer)
	var mine: Dictionary = evs_of(1, "chat_rumor")[0]["p"]
	assert_eq(mine["from"], "說話者", "發話者那份有名字")
	assert_eq(int(mine["from_peer"]), 1)
	for peer in [b, c, watcher]:
		var p: Dictionary = evs_of(peer, "chat_rumor")[0]["p"]
		assert_eq(p["from"], "", "他人那份匿名")
		assert_eq(int(p["from_peer"]), 0)
		assert_eq(p["text"], "聽說鬼王出世了")
	assert_eq(_water(1), w0 - 1, "謠言耗水")

func test_gm_requires_admin_and_costs_no_water() -> void:
	if not _setup_three():
		return
	_set_admin(rs(b), false)
	var wb := _water(b)
	assert_eq(_reason_chat(b, "公告", "GM"), "not_admin")
	assert_eq(_water(b), wb, "not_admin 不耗水")
	_set_admin(s(), true)
	var w0 := _water(1)
	assert_true(_chat(1, "今晚維修", "GM").get("ok", false), "admin GM")
	for peer in [1, b, c]:
		assert_eq(_got(peer, "chat_gm"), 1, "peer %d gets GM" % peer)
	assert_eq(evs_of(c, "chat_gm")[0]["ch"], "GM")
	assert_eq(_water(1), w0, "天外飛仙不耗水")

# ---------- 耗水、頻率、未選角、清理 ----------
## M2 第三輪審查：飲水 0 不能說話【已證實 官方屬性頁，不限頻道】——不耗水的傳音入密也擋
func test_thirsty_blocks_all_channels() -> void:
	if not _setup_three():
		return
	ch().vitals["water"] = 0
	ch().skills.set_level("basic_inner", 80, GameData.tables)   # 謠言頻道的內功門檻先過（審查修正：預設 80）
	for chan in ["CHAT_WORLD", "CHAT_SAY", "CHAT_RUMOR"]:
		assert_eq(_reason_chat(1, "渴", chan), "thirsty", chan)
	assert_eq(_got(b, "chat_say"), 0, "沒送出")
	assert_eq(_reason_chat(1, "水……", "CHAT_WHISPER", "同房客"), "thirsty", "飲水 0：密語也不能說")
	ch().vitals["water"] = 1
	assert_true(_chat(1, "水……", "CHAT_WHISPER", "同房客").get("ok", false), "有水時密語照常、不耗水")
	assert_eq(_water(1), 1, "密語不耗水")
	ch().vitals["water"] = 0
	ws.options["chat_water_cost"] = 0
	assert_true(_chat(1, "免費", "CHAT_SAY").get("ok", false), "chat_water_cost=0 不檢查")
	assert_eq(_water(1), 0)

func test_chat_too_fast() -> void:
	if not _setup_three():
		return
	ws.options["chat_min_interval_ms"] = 500
	assert_true(_chat(1, "一").get("ok", false), "first")
	var w0 := _water(1)
	assert_eq(_reason_chat(1, "二"), "chat_too_fast")
	assert_eq(_water(1), w0, "太快不耗水")
	social.test_ms_offset += 600
	assert_true(_chat(1, "三").get("ok", false), "after 600 ms")
	social.test_ms_offset = 0

func test_no_character_world_only_free_and_throttled() -> void:
	if not game_ok():
		return
	var lurker := soc_add("")
	ws.options["chat_min_interval_ms"] = 500
	clear_all_events()
	assert_true(_chat(lurker, "hello").get("ok", false), "no-char world chat")
	# M2 審查：沒選角的連線也要檢查頻率，否則能以每秒 20 則洗全服
	assert_eq(_reason_chat(lurker, "again", "CHAT_WORLD"), "chat_too_fast", "未選角也檢查頻率")
	social.test_ms_offset += 600
	assert_true(_chat(lurker, "again", "CHAT_WORLD").get("ok", false), "after 600 ms")
	social.test_ms_offset = 0
	assert_eq(_got(lurker, "chat"), 2)
	var p: Dictionary = evs_of(lurker, "chat")[0]["p"]
	assert_eq(p["from"], "旁觀者（未入世）", "用 session 名稱，標上未入世（不能冒充角色，M2 第三輪審查）")
	assert_true(bool(p.get("unbound", false)), "unbound flag")
	assert_eq(int(p["from_peer"]), lurker)
	for chan in ["CHAT_SAY", "CHAT_RUMOR", "CHAT_SECT", "CHAT_PARTY", "GM"]:
		assert_eq(_reason_chat(lurker, "x", chan), "no_character", chan)
	assert_eq(_reason_chat(lurker, "x", "CHAT_WHISPER", "某人"), "no_character", "whisper")

## M2 審查：15 則連發，未選角的連線只會過 1 則（和選了角色的人一樣）
func test_no_character_flood_is_throttled() -> void:
	if not game_ok():
		return
	var lurker := soc_add("")
	ws.options["chat_min_interval_ms"] = 500
	var n := 0
	for i in 15:
		if _chat(lurker, "spam%d" % i).get("ok", false):
			n += 1
	assert_eq(n, 1, "15 rapid charless chats → 1 accepted")

## 頻率記在身分上：同一個身分換一個新 Session（重連）不會歸零
func test_chat_interval_survives_reconnect() -> void:
	if not _setup_three():
		return
	ws.options["chat_min_interval_ms"] = 500
	var old_s: Session = host().session_for_peer(b)
	assert_true(_chat(b, "一", "CHAT_SAY").get("ok", false), "first")
	var fresh := Session.new(old_s.peer_id + 1000, old_s.identity, old_s.display_name)
	fresh.character = old_s.character
	assert_true(social.too_fast(fresh), "new Session of the same identity is still throttled")
	var other := Session.new(old_s.peer_id + 1001, "someone_else_identity", "別人")
	assert_false(social.too_fast(other), "another identity is not")

func test_bbcode_and_control_chars_cleaned() -> void:
	if not _setup_three():
		return
	assert_true(_chat(1, "[color=red]紅[/color]" + char(7) + "字", "CHAT_SAY").get("ok", false), "say")
	var t: String = evs_of(b, "chat_say")[0]["p"]["text"]
	assert_false("[" in t or "]" in t, "no raw brackets: " + t)
	assert_true("［color=red］紅" in t, "全形括號: " + t)
	assert_false(t.contains(char(7)), "控制字元去掉")

func test_failed_chat_sends_nothing() -> void:
	if not _setup_three():
		return
	assert_eq(_reason_chat(1, "x", "CHAT_SECT"), "no_sect")
	for peer in [1, b, c]:
		assert_eq(_got(peer, "chat_sect"), 0)

# ---------- 小工具 ----------
func _reason_chat(peer: int, text: String, chan := "", to := "") -> String:
	return str(_chat(peer, text, chan, to).get("reason", ""))

func _set_admin(sess: Session, v: bool) -> void:
	if "is_admin" in sess:
		sess.set("is_admin", v)
	else:
		sess.set_meta("is_admin", v)

## 假的組隊系統（WP-PARTY 尚未合併時用）：只實作 SocialSystem 需要的 sheet_for
class FakeParty:
	extends RefCounted
	var members: Array = []   # peer 清單
	func sheet_for(sess) -> Dictionary:
		if not (sess.peer_id in members):
			return {}
		var list: Array = []
		for p in members:
			list.append({ "char_id": "", "name": "", "peer": p, "online": true, "room_name": "", "in_battle": false, "leader": p == members[0] })
		return { "id": "pt_fake", "leader": "", "members": list }
