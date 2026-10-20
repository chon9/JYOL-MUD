class_name SocialSystem
extends RefCounted
## 聊天頻道（M2_PLAN 4.6.6、4.4.3、5.4）：千里傳音、傳音入密、輕聲細語、門派、組織、隊伍、江湖謠言、天外飛仙。
## 組織頻道（M3B_PLAN §5.3）：成員資格與收件人由 OrgSystem（host.orgs）決定；沒有組織或系統不存在 → no_guild。
## 主機權威：頻道資格、耗水、頻率都在這裡判定；文字先經 GameHost.clean_text 清理（H6）。
## 未選角的 session 只能用千里傳音、不耗水（M0 行為，net_smoke 依賴）；發話頻率照樣檢查（M2 審查：否則沒選角的連線能洗版）。
## 頻率依「身分」記錄，不記在 Session 上（重連會換新 Session，記在上面等於重連就歸零）。

# 4.1 的頻道常數（別名，方便本檔閱讀）
const CH_WORLD := Protocol.CH_CHAT_WORLD
const CH_WHISPER := Protocol.CH_CHAT_WHISPER
const CH_SAY := Protocol.CH_CHAT_SAY
const CH_SECT := Protocol.CH_CHAT_SECT
const CH_GUILD := Protocol.CH_CHAT_GUILD
const CH_PARTY := Protocol.CH_CHAT_PARTY
const CH_RUMOR := Protocol.CH_CHAT_RUMOR
const CH_GM := Protocol.CH_GM
const CHANNELS := Protocol.CHAT_CHANNELS

## 5.4：會耗水的頻道（傳音入密、天外飛仙不耗）
const WATER_CHANNELS := [CH_WORLD, CH_SAY, CH_SECT, CH_GUILD, CH_PARTY, CH_RUMOR]

# 4.4.3 事件 key
const E_CHAT := Protocol.E_CHAT
const E_CHAT_SAY := Protocol.E_CHAT_SAY
const E_CHAT_SECT := Protocol.E_CHAT_SECT
const E_CHAT_PARTY := Protocol.E_CHAT_PARTY
const E_CHAT_WHISPER := Protocol.E_CHAT_WHISPER
const E_CHAT_RUMOR := Protocol.E_CHAT_RUMOR
const E_CHAT_GM := Protocol.E_CHAT_GM
## M3B_PLAN 缺漏：§6 沒有列組織頻道的事件 key → 比照 chat_sect／chat_party 用 chat_guild（模板在 _org.json）
const E_CHAT_GUILD := "chat_guild"

# 4.7.1 選項預設（options.json 沒有時）
const DEFAULT_WATER_COST := 1
const DEFAULT_MIN_INTERVAL_MS := 500
const META_LAST_CHAT := "social_last_chat_ms"   # 舊版記在 Session meta；保留常數給舊測試／工具參考

var host: GameHost
## 測試用：取代 host.party（只需要 sheet_for(s) -> Dictionary）。null = 用 host.party
var party_override: Variant = null
## 測試用：取代 host.orgs（只需要 org_id_of(char_id) -> String、members_online(org_id) -> Array[Session]）。null = 用 host.orgs
var orgs_override: Variant = null
## 測試用：真實時間的位移（毫秒），讓頻率測試不必真的等待
var test_ms_offset := 0
## 身分 → 上次發話的真實毫秒（4.6.6 第 4 步；跨重連）
var _last_chat_ms: Dictionary = {}

func _init(p_host: GameHost) -> void:
	host = p_host

# ---------- 主流程（4.6.6 的 1–7 步） ----------
func chat(s: Session, args: Dictionary) -> Dictionary:
	var ch_name := str(args.get("ch", CH_WORLD))
	if not (ch_name in CHANNELS):
		return GameHost.fail("bad_channel")
	# 1. 清理文字
	var text := clean(str(args.get("text", "")), Protocol.CHAT_MAX_LEN)
	if text.strip_edges().is_empty():
		return GameHost.fail("empty_text")
	# 2. 沒有角色：只能千里傳音（M0 行為，不耗水）；頻率照樣檢查
	if s.character == null:
		if ch_name != CH_WORLD:
			return GameHost.fail("no_character")
		if too_fast(s):
			return GameHost.fail("chat_too_fast")
		_mark_chat(s)
		# 名字是客戶端自報的設定檔名稱，可能和某個角色同名：一律標上「（未入世）」，不能冒充角色（M2 第三輪審查）
		host.ws.broadcast_event(CH_WORLD, E_CHAT, { "from": unbound_name(s.display_name), "from_peer": s.peer_id,
			"text": text, "unbound": true })
		_count_chat()
		return GameHost.ok()
	# 3. 天外飛仙只限管理員（不耗水）
	if ch_name == CH_GM and not is_admin(s):
		return GameHost.fail("not_admin")
	# M3A_PLAN 6.6：坐牢中只能傳音入密、輕聲細語【已證實】
	if s.character.is_jailed() and not (ch_name in [CH_WHISPER, CH_SAY]):
		return GameHost.fail("jailed")
	# 4. 頻率（真實時間，依身分）
	if too_fast(s):
		return GameHost.fail("chat_too_fast")
	# 5. 頻道資格
	var me = s.character
	var whisper_to: Session = null
	var party_peers: Array = []
	var guild_peers: Array = []
	match ch_name:
		CH_SECT:
			if str(me.sect) == "":
				return GameHost.fail("no_sect")
		CH_GUILD:
			guild_peers = guild_peers_of(s)
			if guild_peers.is_empty():
				return GameHost.fail("no_guild")
		CH_PARTY:
			party_peers = party_peers_of(s)
			if party_peers.is_empty():
				return GameHost.fail("no_party_chat")
		CH_WHISPER:
			whisper_to = find_online_by_name(str(args.get("to", "")))
			if whisper_to == null:
				return GameHost.fail("no_such_player")
			if whisper_to == s:
				return GameHost.fail("bad_target")
	# 6. 耗水。飲水 0 不能說話【已證實 官方屬性頁：不限頻道】→ 不耗水的傳音入密也擋；只有管理員的天外飛仙例外
	#    （未選角的千里傳音在第 2 步就送出了，沒有角色、沒有飲水）（M2 第三輪審查）
	#    主機把 chat_water_cost 設成 0 ＝ 關掉說話耗水這整條規則，0 水也能說
	var water := int(me.vitals.get("water", 0))
	var cost := maxi(0, int(host.options.get("chat_water_cost", DEFAULT_WATER_COST)))
	if cost > 0 and ch_name != CH_GM and water <= 0:
		return GameHost.fail("thirsty")
	if ch_name in WATER_CHANNELS:
		if water < cost:
			return GameHost.fail("thirsty")
		if cost > 0:
			me.vitals["water"] = water - cost
			s.sheet_dirty = true
	# 7. 送出
	_mark_chat(s)
	var from := str(me.name)
	var p := { "from": from, "from_peer": s.peer_id, "text": text }
	match ch_name:
		CH_WORLD:
			host.ws.broadcast_event(CH_WORLD, E_CHAT, p)
		CH_SAY:
			_send_to(_room_peers(s.room_id()), CH_SAY, E_CHAT_SAY, p)
		CH_SECT:
			_send_to(_sect_peers(str(me.sect)), CH_SECT, E_CHAT_SECT, p)
		CH_GUILD:
			_send_to(guild_peers, CH_GUILD, E_CHAT_GUILD, p)
		CH_PARTY:
			_send_to(party_peers, CH_PARTY, E_CHAT_PARTY, p)
		CH_WHISPER:
			p["to_name"] = str(whisper_to.character.name)
			_send_to([s.peer_id, whisper_to.peer_id], CH_WHISPER, E_CHAT_WHISPER, p)
		CH_RUMOR:
			# 發話者那份帶本人名字與 peer（self 變體）；其他人那份匿名（other 變體：「(謠言)」）
			var anon := { "from": "", "from_peer": 0, "text": text }
			for peer_id in host.ws.sessions:
				host.ws.queue_event(peer_id, CH_RUMOR, E_CHAT_RUMOR, p if int(peer_id) == s.peer_id else anon)
		CH_GM:
			host.ws.broadcast_event(CH_GM, E_CHAT_GM, p)
	_count_chat()
	return GameHost.ok()

## 沒選角的發話者顯示名：「名字（未入世）」
const UNBOUND_SUFFIX := "（未入世）"
static func unbound_name(display_name: String) -> String:
	return display_name + UNBOUND_SUFFIX

# ---------- 收件人 ----------
func _send_to(peers: Array, ch_name: String, key: String, p: Dictionary) -> void:
	var seen := {}
	for peer_id in peers:
		if seen.has(int(peer_id)):
			continue
		seen[int(peer_id)] = true
		host.ws.queue_event(int(peer_id), ch_name, key, p)

## 同房（已選角且在該房間）的所有 peer，含發話者
func _room_peers(room_id: String) -> Array:
	var out: Array = []
	if room_id == "":
		return out
	for o in host.sessions():
		if o.character != null and o.room_id() == room_id:
			out.append(o.peer_id)
	return out

## 同門在線角色
func _sect_peers(sect_id: String) -> Array:
	var out: Array = []
	for o in host.sessions():
		if o.character != null and str(o.character.sect) == sect_id:
			out.append(o.peer_id)
	return out

## 全隊在線成員的 peer（含自己）；沒有隊伍或組隊系統不存在（H4）→ []
func party_peers_of(s: Session) -> Array:
	var party: Variant = party_override if party_override != null else host.get("party")
	if party == null or not party.has_method("sheet_for"):
		return []
	var sheet: Variant = party.sheet_for(s)
	if not (sheet is Dictionary) or sheet.is_empty():
		return []
	var out: Array = []
	for m in sheet.get("members", []):
		if not (m is Dictionary) or not bool(m.get("online", true)):
			continue
		var peer_id := int(m.get("peer", 0))
		if peer_id != 0 and host.session_for_peer(peer_id) != null:
			out.append(peer_id)
	if out.is_empty():
		return []
	if not (s.peer_id in out):
		out.push_front(s.peer_id)
	return out

## 組織在線成員的 peer（含自己）；不在組織或 OrgSystem 不存在（L3）→ []
func guild_peers_of(s: Session) -> Array:
	var orgs: Variant = orgs_override if orgs_override != null else host.get("orgs")
	if orgs == null or s == null or s.character == null or not orgs.has_method("org_id_of") 			or not orgs.has_method("members_online"):
		return []
	var org_id := str(orgs.org_id_of(str(s.character.id)))
	if org_id == "":
		return []
	var out: Array = []
	for o in orgs.members_online(org_id):
		if o is Session and o.character != null and host.session_for_peer(o.peer_id) != null:
			out.append(o.peer_id)
	if not (s.peer_id in out):
		out.push_front(s.peer_id)
	return out

# ---------- 查詢與相容（H4：WP-HOST 的輔助函式還沒合併時用同義的本地版本） ----------
func clean(text: String, max_len: int) -> String:
	if host.has_method("clean_text"):
		return str(host.call("clean_text", text, max_len))
	return clean_text_local(text, max_len)

## 與 WorldServer._clean_name 相同的清理（H6）：去控制字元、[ ] 換全形、去頭尾空白、截長度
static func clean_text_local(text: String, max_len: int) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if c < 0x20 or c == 0x7F or (c >= 0x80 and c < 0xA0):
			out += " " if c == 0x0A or c == 0x09 or c == 0x0D else ""
			continue
		out += char(c)
	out = out.replace("[", "［").replace("]", "］").strip_edges()
	return out.substr(0, max_len) if max_len > 0 else out

## 在線且選著此名角色的 session（大小寫不敏感）
func find_online_by_name(char_name: String) -> Session:
	var n := char_name.strip_edges()
	if n == "":
		return null
	if host.has_method("session_for_char_name"):
		return host.call("session_for_char_name", n)
	var key := CharacterStore.name_key(n)
	for o in host.sessions():
		if o.character != null and CharacterStore.name_key(str(o.character.name)) == key:
			return o
	return null

func is_admin(s: Session) -> bool:
	if host.has_method("is_admin"):
		return bool(host.call("is_admin", s))
	if "is_admin" in s:
		return bool(s.get("is_admin"))
	return s.has_meta("is_admin") and bool(s.get_meta("is_admin"))

## 發話頻率的鍵：身分（重連後同一個人）；沒有身分時退回 peer
static func rate_key(s: Session) -> String:
	return s.identity if s.identity != "" else "peer:%d" % s.peer_id

func too_fast(s: Session) -> bool:
	var k := rate_key(s)
	if not _last_chat_ms.has(k):
		return false
	var min_ms := int(host.options.get("chat_min_interval_ms", DEFAULT_MIN_INTERVAL_MS))
	return real_ms() - int(_last_chat_ms[k]) < min_ms

func _mark_chat(s: Session) -> void:
	_last_chat_ms[rate_key(s)] = real_ms()

func real_ms() -> int:
	return Time.get_ticks_msec() + test_ms_offset

func _count_chat() -> void:
	var st: Variant = host.ws.get("stats")
	if st is Dictionary:
		st["chats"] = int(st.get("chats", 0)) + 1
