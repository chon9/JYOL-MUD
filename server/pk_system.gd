class_name PkSystem
extends RefCounted
## PK（M2_PLAN 4.6.4、5.2）：叫戰（待決、到期）、強制 PK、系統開關、守城官兵、PvP 結束後的
## PK值／殺氣／善惡與 pk_kill（強制 PK 才廣播全服；叫戰只給兩個當事人）、房間視圖的玩家標記。
## 純規則在 MoralityPk；這裡只做主機端的驗證、狀態與事件。
##
## M2_PLAN 缺漏／偏差：H3 寫 `_init(p_host: GameHost)`；這裡不加型別，讓單元測試可傳入假主機（真主機照常可用）。
## 其他 M2 系統（party、battles.start_pvp、world_span…）一律先確認存在再用（H4）。

const GUARD_MONSTER := "m_city_guard"
const PK_MODE_CLASSIC := "CLASSIC"
const PK_MODE_CHALLENGE_ONLY := "CHALLENGE_ONLY"
const PK_MODE_OFF := "OFF"
const KIND_SEIZE := "SEIZE"   # M3B_PLAN §5.1.5
const DEFAULT_TTL_REAL_S := 60
## 被拒絕或到期後，同一人再向同一人叫戰要等的真實秒數【設計提案】（M2 第三輪審查：防止拒絕後立刻連發洗提示）
const DEFAULT_RETRY_COOLDOWN_REAL_S := 10
const DEFAULT_PROTECT_XP := 500
const PREF_LABELS := { "accept_challenge": "接受叫戰", "accept_party": "接受組隊邀請" }
const STATE_ON := "開"
const STATE_OFF := "關"

# 事件 key（M2_PLAN 4.4.2；Protocol.E_* 的別名）
const E_CHALLENGE_SENT := Protocol.E_CHALLENGE_SENT
const E_CHALLENGE_REQUEST := Protocol.E_CHALLENGE_REQUEST
const E_CHALLENGE_DECLINED := Protocol.E_CHALLENGE_DECLINED
const E_CHALLENGE_EXPIRED := Protocol.E_CHALLENGE_EXPIRED
const E_CHALLENGE_START := Protocol.E_CHALLENGE_START
const E_FORCE_PK_START := Protocol.E_FORCE_PK_START
const E_PK_KILL := Protocol.E_PK_KILL
const E_PK_VALUE_UP := Protocol.E_PK_VALUE_UP
const E_PK_WANTED := Protocol.E_PK_WANTED
const E_MORALITY_CHANGE := Protocol.E_MORALITY_CHANGE
const E_KILLING_INTENT_CHANGE := Protocol.E_KILLING_INTENT_CHANGE
const E_GUARD_ATTACK := Protocol.E_GUARD_ATTACK
const E_PREF_CHANGED := Protocol.E_PREF_CHANGED

## STORY_PLAN §5.1 #4 的強制 PK 傳聞是否直接取代 pk_kill 的全服廣播（見 on_pvp_end 的說明）
const PK_RUMOR_LIVE := false

var host
var pk_rumor_live := PK_RUMOR_LIVE
## 待決叫戰：[{ from_char, to_char, from_name, to_name, expires_s（世界時間）, ttl_real_s }]（不存檔，4.8）
var pending: Array = []
## "叫戰者|對方" → 冷卻結束的世界時間（不存檔）
var _cooldown: Dictionary = {}

func _init(p_host) -> void:
	host = p_host

# ======================================================================== 叫戰

## challenge：pk_disabled → bad_target → target_not_here → pk_not_allowed_here → target_busy
## → target_in_party → challenge_pending → challenge_refused → challenge_cooldown → 建立待決叫戰
func challenge(s: Session, target_char: String) -> Dictionary:
	if pk_mode() == PK_MODE_OFF:
		return GameHost.fail("pk_disabled")
	if target_char == str(s.character.id):
		return GameHost.fail("bad_target")
	var t := _here(s, target_char)
	if t == null:
		return GameHost.fail("target_not_here")
	if not pk_allowed_at(s.room_id()):
		return GameHost.fail("pk_not_allowed_here")
	if t.battle_id != 0 or t.character.is_jailed():
		return GameHost.fail("target_busy")   # M3A_PLAN 6.6：坐牢中的人不能被叫戰或強制 PK
	if same_party(s, t):
		return GameHost.fail("target_in_party")
	if not _find(str(s.character.id), target_char).is_empty():
		return GameHost.fail("challenge_pending")
	if not t.character.pref("accept_challenge"):
		return GameHost.fail("challenge_refused")   # 不送提示給對方
	if _cooling(str(s.character.id), target_char):
		return GameHost.fail("challenge_cooldown")
	var ttl := ttl_real_s()
	pending.append({
		"from_char": str(s.character.id), "to_char": target_char,
		"from_name": str(s.character.name), "to_name": str(t.character.name),
		"expires_s": host.now_s() + _world_span(float(ttl)),
	})
	host.tell(s, Protocol.CH_SYSTEM, E_CHALLENGE_SENT, { "name": str(t.character.name) })
	host.tell(t, Protocol.CH_SYSTEM, E_CHALLENGE_REQUEST,
		{ "name": str(s.character.name), "from_char": str(s.character.id), "ttl": ttl })
	t.sheet_dirty = true
	return GameHost.ok()

## challenge_reply：no_challenge → 拒絕（叫戰者收 challenge_declined）→ 接受：重驗 pk_disabled
## → target_not_here → pk_not_allowed_here → target_busy → target_in_party → start_pvp(叫戰者, 我, "CHALLENGE")
func challenge_reply(s: Session, from_char: String, accept: bool) -> Dictionary:
	var me := str(s.character.id)
	var c := _find(from_char, me)
	if c.is_empty() or float(c["expires_s"]) <= host.now_s():
		return GameHost.fail("no_challenge")
	pending.erase(c)
	s.sheet_dirty = true
	var atk: Session = host.session_for_char(from_char)
	if not accept:
		_start_cooldown(from_char, me)
		if atk != null:
			host.tell(atk, Protocol.CH_SYSTEM, E_CHALLENGE_DECLINED, { "name": str(s.character.name) })
		return GameHost.ok()
	if pk_mode() == PK_MODE_OFF:
		return GameHost.fail("pk_disabled")
	if atk == null or atk.character == null or atk.room_id() != s.room_id():
		return GameHost.fail("target_not_here")
	if not pk_allowed_at(s.room_id()):
		return GameHost.fail("pk_not_allowed_here")
	if atk.battle_id != 0 or atk.character.is_jailed():
		return GameHost.fail("target_busy")
	# 叫戰之後兩人才組隊：接受時要重驗（M2 審查；challenge() 與 force_pk 都擋隊友）
	if same_party(atk, s):
		return GameHost.fail("target_in_party")
	return _start_pvp(atk, s, MoralityPk.KIND_CHALLENGE, E_CHALLENGE_START)

# ======================================================================== 強制 PK

## force_pk：pk_disabled → pk_challenge_only → bad_target → target_not_here → pk_not_allowed_here
## → target_busy → target_in_party → target_newbie_protected → start_pvp(我, 對方, "FORCED")
func force_pk(s: Session, target_char: String) -> Dictionary:
	var mode := pk_mode()
	if mode == PK_MODE_OFF:
		return GameHost.fail("pk_disabled")
	if mode == PK_MODE_CHALLENGE_ONLY:
		return GameHost.fail("pk_challenge_only")
	if target_char == str(s.character.id):
		return GameHost.fail("bad_target")
	var t := _here(s, target_char)
	if t == null:
		return GameHost.fail("target_not_here")
	if not pk_allowed_at(s.room_id()):
		return GameHost.fail("pk_not_allowed_here")
	if t.battle_id != 0 or t.character.is_jailed():
		return GameHost.fail("target_busy")
	if same_party(s, t):
		return GameHost.fail("target_in_party")
	if newbie_protected(t.character):
		return GameHost.fail("target_newbie_protected")
	# M3d WP-LAW（M3D_PLAN §2.3）：持照緝拿名單上的人＝合法（開戰前判定；執照在這裡檢查 PK值 > 0 自動失效）
	var law = host.get("law") if host is Object else null
	if law != null and (law as Object).has_method("lawful_hunt") and bool(law.lawful_hunt(s, t.character)):
		var r := _start_pvp(s, t, MoralityPk.KIND_FORCED, E_FORCE_PK_START, { "lawful": true })
		if bool(r.get("ok", false)) and (law as Object).has_method("note_lawful"):
			law.note_lawful(int(r.get("battle_id", 0)), s, t)
		return r
	return _start_pvp(s, t, MoralityPk.KIND_FORCED, E_FORCE_PK_START)

func _start_pvp(atk: Session, def: Session, kind: String, start_key: String, opts: Dictionary = {}) -> Dictionary:
	if host.battles == null or not host.battles.has_method("start_pvp"):
		# M2_PLAN 缺漏：WP-PARTY 的 start_pvp 不存在時（H4）沒有指定原因碼；回 bad_cmd，不送開戰事件
		return GameHost.fail("bad_cmd")
	# 叫戰／出手的兩人之間的其他待決叫戰都失效（開打了）
	_drop_between(str(atk.character.id), str(def.character.id))
	var room := atk.room_id()
	var p := { "atk_name": str(atk.character.name), "def_name": str(def.character.name),
		"atk_peer": atk.peer_id, "def_peer": def.peer_id }
	var bid := int(host.battles.start_pvp(atk, def, kind, opts)) if not opts.is_empty() else int(host.battles.start_pvp(atk, def, kind))
	if bid == 0:
		return GameHost.fail("target_busy")
	host.ws.queue_room_event(room, Protocol.CH_SCENE, start_key, p)
	atk.sheet_dirty = true
	def.sheet_dirty = true
	return GameHost.ok({ "battle_id": bid })

# ======================================================================== 系統開關

func set_pref(s: Session, key: String, value: bool) -> Dictionary:
	if not PREF_LABELS.has(key):
		return GameHost.fail("bad_value:key")   # Protocol 列舉已擋；防禦性檢查
	s.character.prefs[key] = value
	host.tell(s, Protocol.CH_SYSTEM, E_PREF_CHANGED,
		{ "label": str(PREF_LABELS[key]), "state": STATE_ON if value else STATE_OFF })
	s.sheet_dirty = true
	return GameHost.ok()

# ======================================================================== 守衛

## 進出城（換了地區，且舊或新地區是 type == CITY）且該城有 GUARD NPC、guard_count > 0 → 官兵開戰。
## 兩個不同的城之間（例：驛站馬車西夏 → 大理）＝出一個城、進另一個城，也算（M2 第三輪審查）
func on_move(s: Session, from_room: String, to_room: String) -> bool:
	if not bool(host.options.get("guards_enabled", true)):
		return false
	if s == null or s.character == null or s.battle_id != 0:
		return false
	var from_region: String = host.index.region_of(from_room)
	var to_region: String = host.index.region_of(to_room)
	if from_region == to_region:
		return false   # 城內移動、同一地區內移動
	var city := ""
	for r in [to_region, from_region]:
		if city == "" and _is_city(r) and _has_guard(r):
			city = r
	if city == "":
		return false   # 城外移動，或進出的城沒有官兵
	var ch = s.character
	# M3c 審查：新手（實戰 < protect_xp）善惡負不被官兵追殺，PK值 > 3 照舊（MoralityPk.guard_count）；
	# 第二輪審查：只在規則 newbie_guard_spare 開時（classic_strict 關＝2001 規則，沒有新手例外）
	var n := MoralityPk.guard_count(ch.pk_value(), int(ch.morality), guard_spares(ch))
	n = _law_guard_count(ch, n)   # M3d WP-LAW：劫鏢標記期間至少 PK > 3 的人數（M3D_PLAN §5.2.3、A9）
	if n <= 0:
		return false
	host.tell(s, Protocol.CH_BATTLE, E_GUARD_ATTACK, { "n": n })
	var ids: Array = []
	for i in n:
		ids.append(GUARD_MONSTER)
	host.battles.start(s, ids, "GUARD")
	return true

## M3C_PLAN §5.5：城內對居民、守衛動手 → 守城官兵（n 名 m_city_guard，既有 "GUARD" 戰）。
## guards_enabled 關、玩家不在、已死（氣 ≤ 0）或在戰鬥中 → false。reason_key 事件（na_guard_alarm）先送本人與同房
func guard_strike(s: Session, n: int, reason_key: String) -> bool:
	if not bool(host.options.get("guards_enabled", true)):
		return false
	if s == null or s.character == null or s.battle_id != 0 or n <= 0:
		return false
	# M3c 第二輪審查：新手保護與「善惡負進出城」用同一個規則旗標（newbie_guard_spare）——以前只擋了有出處的追殺、
	# 沒擋這個【設計提案】的即時官兵，0 實戰的新手打贏居民後一定被官兵（勝率 0%）打死
	if guard_spares(s.character):
		var sp := { "name": str(s.character.name), "peer": s.peer_id }
		if host.ws != null and host.ws.has_method("queue_room_event") and s.room_id() != "":
			host.ws.queue_room_event(s.room_id(), Protocol.CH_BATTLE, Protocol.E_NA_GUARD_SPARE, sp)
		else:
			host.tell(s, Protocol.CH_BATTLE, Protocol.E_NA_GUARD_SPARE, sp)
		return false
	var vit: Variant = s.character.get("vitals")
	if vit is Dictionary and int((vit as Dictionary).get("qi", 1)) <= 0:
		return false
	if host.battles == null:
		return false
	# 一則房間事件：本人看 self、同房看 other（TextRenderer 依 peer 選）
	var p := { "n": n, "name": str(s.character.name), "peer": s.peer_id }
	if host.ws != null and host.ws.has_method("queue_room_event") and s.room_id() != "":
		host.ws.queue_room_event(s.room_id(), Protocol.CH_BATTLE, reason_key, p)
	else:
		host.tell(s, Protocol.CH_BATTLE, reason_key, p)
	var ids: Array = []
	for i in n:
		ids.append(GUARD_MONSTER)
	host.battles.start(s, ids, "GUARD")
	return true

## 規則 newbie_guard_spare 開（預設；classic_strict 關）且這個角色是新手（實戰 < newbie_pk_protect_xp）→ 守城官兵放過他
## （善惡負進出城不追殺、城內行兇不招官兵；PK值 > 3 照舊追殺）。M3c 第二輪審查
func guard_spares(ch) -> bool:
	if ch == null:
		return false
	var r: Variant = host.rules
	if r is Dictionary and (r as Dictionary).get("newbie_guard_spare", true) == false:
		return false
	return newbie_protected(ch)

## 新手保護（實戰 < newbie_pk_protect_xp）——身上有神兵的人不算（M3c 第三輪審查）：
## 以前持有者可以叫戰一個新手分身、故意輸掉，把神兵「寄放」在不能被強制 PK、守城官兵也放過的新手身上，
## 「被玩家打死就轉給殺手」（xinshou/11）永遠不會發生。現在拿著神兵就失去新手保護（強制 PK、官兵、門派捉拿都一樣）。
func newbie_protected(ch) -> bool:
	if ch == null or not MoralityPk.is_newbie(int(ch.combat_xp), protect_xp()):
		return false
	var loot: Variant = host.get("loot") if host is Object else null
	if loot == null or not (loot as Object).has_method("holds_divine"):
		return true   # 沒有 LootSystem（測試用的假主機）：照舊只看實戰
	return not bool(loot.holds_divine(ch))

## 這個地區是城（type CITY）且有官兵（GUARD NPC）
func city_with_guard(region_id: String) -> bool:
	return _is_city(region_id) and _has_guard(region_id)

func _is_city(region_id: String) -> bool:
	return str(host.tables.get("regions", {}).get(region_id, {}).get("type", "")) == "CITY"

func _has_guard(region_id: String) -> bool:
	var npcs: Dictionary = host.tables.get("npcs", {})
	for nid in npcs:
		var row: Variant = npcs[nid]
		if row is Dictionary and str(row.get("kind", "")) == "GUARD" and str(row.get("region", "")) == region_id:
			return true
	return false

# ======================================================================== PvP 結束

## summary = { bid, kind, room, units: [ { char_id, name, peer（離線 0）, side, died, fled, killed_by_char } ] }
func on_pvp_end(summary: Dictionary) -> void:
	var kind := str(summary.get("kind", ""))
	# M3D_PLAN §9.2（WP-LAW Day-0）：先交給 M3d 各系統（懸賞領賞、劫鏢分贓、比武判定）
	if host is Object and (host as Object).has_method("m3d_pvp_end"):
		host.m3d_pvp_end(summary)
	# M3d：比武（DUEL）沒有死亡懲罰——不轉移神兵、不加 PK值、殺氣、善惡、不廣播（在 _loot_pvp_kills 之前）
	if kind == "DUEL":
		return
	# M3d：劫鏢（ROB）照強制 PK 算（PK值 +1、殺氣、善惡、pk_kill；R15）
	var as_kind := "FORCED" if kind == "ROB" else kind
	# M3d WP-LAW：持照緝拿（合法）的戰鬥 → 出手者不加 PK值、不扣善惡、殺氣只加 LAWFUL_KILLING_INTENT、不廣播 pk_kill
	var law = host.get("law") if host is Object else null
	var lawful := law != null and (law as Object).has_method("is_lawful_bid") and bool(law.is_lawful_bid(int(summary.get("bid", 0))))
	# M3C_PLAN §6.5、§11.3 Day-0 (6)：任何 PvP（叫戰、強制 PK、捉拿）死於玩家 → 神兵歸殺手（LootSystem 為 null 時略過）
	_loot_pvp_kills(summary)
	# M3B_PLAN §5.1.5、§5.1.8：捉拿公敵（SEIZE）＝FORCED 的路徑但不加懲罰：抓的人不加 PK 值、殺氣、善惡，
	# 不廣播 pk_kill、不算同門相殘；被抓的公敵已在死亡處理時關押（capture_on_death）→ 全服 seize_done
	if kind == KIND_SEIZE:
		var sects0 = host.get("sects")
		if sects0 != null and sects0.has_method("on_seize_end"):
			sects0.on_seize_end(summary)
		return
	var units: Array = summary.get("units", [])
	var room := str(summary.get("room", ""))
	for v in units:
		if not (v is Dictionary) or not bool(v.get("died", false)):
			continue
		var killer_id := str(v.get("killed_by_char", ""))
		if killer_id == "" or killer_id == str(v.get("char_id", "")):
			continue
		var k: Dictionary = {}
		for u in units:
			if u is Dictionary and str(u.get("char_id", "")) == killer_id:
				k = u
		var victim_ch = _char_any(str(v.get("char_id", "")))
		var victim_morality := int(victim_ch.morality) if victim_ch != null else 0
		var killer_s: Session = host.session_for_char(killer_id)
		var killer_ch = killer_s.character if killer_s != null else _char_any(killer_id)
		var atk_name := str(k.get("name", "")) if not k.is_empty() else ""
		if atk_name == "" and killer_ch != null:
			atk_name = str(killer_ch.name)
		var def_name := str(v.get("name", ""))
		if def_name == "" and victim_ch != null:
			def_name = str(victim_ch.name)
		var atk_peer := killer_s.peer_id if killer_s != null else 0
		var def_s: Session = host.session_for_char(str(v.get("char_id", "")))
		var def_peer := def_s.peer_id if def_s != null else 0
		var kill_p := { "atk_name": atk_name, "def_name": def_name, "atk_peer": atk_peer, "def_peer": def_peer,
			"room_name": host.room_name(room) }
		# 誰算「強制 PK」：只有出手的人（side 0；start_pvp 一律把出手者放 side 0，PvP 不能中途加入）。
		# 原作的 PK值 +1 綁在「按連結鍵強迫開啟戰斗」的惡意 PK【已證實 17173 xinshou/10】；
		# 被強制 PK 的人反殺出手者是自衛，照叫戰擊殺算（PK值不加、善惡不變、殺氣照加、不廣播全服）【設計提案】（M2 第三輪審查）
		var eff_kind := effective_kill_kind(as_kind, int(k.get("side", 0)) if not k.is_empty() else 0)
		var lawful_kill := lawful and eff_kind == MoralityPk.KIND_FORCED   # M3d WP-LAW：只有出手的持照者算合法緝拿
		# 【設計提案】（M2_PLAN 5.2）：原作沒有這種廣播的記載。強制 PK 的擊殺才廣播全服「【江湖傳聞】」；
		# 叫戰是雙方同意的比武，只告訴兩個當事人（M2 審查）
		# STORY_PLAN §5.1 #4：強制 PK 的擊殺交給 RumorSystem（kind PK）。
		# - pk_rumor_live == true：全服改收 jianghu_rumor（頻道 JIANGHU，受 rumors_enabled 與節流），兩個當事人各收自己的 pk_kill；
		#   RumorSystem 為 null、選項關閉或被節流時照舊直接廣播 pk_kill（不漏掉擊殺消息）。
		# - pk_rumor_live == false（目前預設）：照 M2 廣播 pk_kill（其 other 模板本來就是「【江湖傳聞】…」），
		#   另把這則記進傳聞紀錄（rumor_list 看得到），不重複廣播。
		# STORY_PLAN 缺漏：tests/unit/test_world_pk.gd::test_force_pk_kill_effects（非本 WP 檔案）要求旁觀者收到 pk_kill；
		# 該測試更新後把 PK_RUMOR_LIVE 改成 true 即完全照 §5.1 #4。
		if lawful_kill:
			# M3d WP-LAW：合法緝拿不廣播 pk_kill（傳聞 rmr_law_caught 由 LawSystem.on_pvp_end 發）；兩個當事人照常收 pk_kill
			for peer_id in [atk_peer, def_peer]:
				if int(peer_id) != 0:
					host.ws.queue_event(int(peer_id), Protocol.CH_SYSTEM, E_PK_KILL, kill_p)
		elif eff_kind == MoralityPk.KIND_FORCED and pk_rumor_live and _post_pk_rumor(kill_p, false):
			for peer_id in [atk_peer, def_peer]:
				if int(peer_id) != 0:
					host.ws.queue_event(int(peer_id), Protocol.CH_SYSTEM, E_PK_KILL, kill_p)
		elif eff_kind == MoralityPk.KIND_FORCED:
			host.ws.broadcast_event(Protocol.CH_SYSTEM, E_PK_KILL, kill_p)
			if not pk_rumor_live:
				_post_pk_rumor(kill_p, true)
		else:
			for peer_id in [atk_peer, def_peer]:
				if int(peer_id) != 0:
					host.ws.queue_event(int(peer_id), Protocol.CH_SYSTEM, E_PK_KILL, kill_p)
		if killer_ch == null:
			continue
		# M3A_PLAN 6.3：強制 PK 的發起者殺死同門 → KILL_SAME_SECT（叫戰、被出手者反殺不算）
		var sects = host.get("sects")
		if sects != null and killer_s != null and victim_ch != null:
			sects.on_pvp_kill(killer_s, victim_ch, eff_kind == MoralityPk.KIND_FORCED and not lawful_kill)   # M3d WP-LAW：合法緝拿不算同門相殘
		var d := MoralityPk.kill_deltas(eff_kind, victim_morality)
		if lawful_kill:
			d = _law_lawful_deltas(d)   # M3d WP-LAW
		var pk_before: int = killer_ch.pk_value()
		var pk_after := pk_before
		if int(d["pk"]) != 0:
			pk_after = killer_ch.add_pk(int(d["pk"]))
		var ki: int = killer_ch.add_killing_intent(int(d["killing_intent"]))
		var mo: int = killer_ch.add_morality(int(d["morality"]))
		if killer_s != null:
			if pk_after > pk_before:
				host.tell(killer_s, Protocol.CH_SYSTEM, E_PK_VALUE_UP, { "pk": pk_after })
				if pk_before <= MoralityPk.GUARD_PK_THRESHOLD and pk_after > MoralityPk.GUARD_PK_THRESHOLD:
					host.tell(killer_s, Protocol.CH_SYSTEM, E_PK_WANTED, { "pk": pk_after })
			if mo != 0:
				host.tell(killer_s, Protocol.CH_SYSTEM, E_MORALITY_CHANGE, { "delta": mo, "value": int(killer_ch.morality) })
			if ki != 0:
				host.tell(killer_s, Protocol.CH_SYSTEM, E_KILLING_INTENT_CHANGE,
					{ "delta": ki, "value": int(killer_ch.killing_intent) })
			killer_s.sheet_dirty = true
			host.regions.mark_room_dirty(killer_s.room_id())   # 名字顏色可能變了
			if sects != null and killer_s.battle_id == 0:
				sects.check_state(killer_s, "PK")   # PK值、善惡、殺氣改變後檢查門規
		host.save_char(killer_ch)
	if lawful:
		law.forget_bid(int(summary.get("bid", 0)))   # M3d WP-LAW

## 對每個死於玩家的單位：LootSystem.on_pvp_kill(killer_char, victim_char, summary)
func _loot_pvp_kills(summary: Dictionary) -> void:
	var loot = host.get("loot")
	if loot == null or not host.has_method("m2_call"):
		return
	for v in summary.get("units", []):
		if not (v is Dictionary) or not bool(v.get("died", false)):
			continue
		var killer_id := str(v.get("killed_by_char", ""))
		var victim_id := str(v.get("char_id", ""))
		if killer_id == "" or killer_id == victim_id:
			continue
		host.m2_call(loot, "on_pvp_kill", [killer_id, victim_id, summary])

## 強制 PK 擊殺的江湖傳聞（STORY_PLAN §5.1 #4；模板 e_pk_kill 由 _ambient 碎片提供）。發出回 true
## record_only：只記進傳聞紀錄，不另外廣播（RumorSystem 的內部參數 _record_only）
func _post_pk_rumor(kill_p: Dictionary, record_only: bool) -> bool:
	var rumor = host.get("rumor")
	if rumor == null or not rumor.has_method("post"):
		return false
	var p := { "atk_name": str(kill_p.get("atk_name", "")), "def_name": str(kill_p.get("def_name", "")),
		"room_name": str(kill_p.get("room_name", "")) }
	if record_only:
		p["_record_only"] = true
	return bool(rumor.post("PK", "e_pk_kill", p))

## 擊殺結算用的種類：強制 PK 只有出手者（side 0）算 FORCED；被出手的一方（side 1）反殺照叫戰算【設計提案】
static func effective_kill_kind(battle_kind: String, killer_side: int) -> String:
	if battle_kind == MoralityPk.KIND_FORCED and killer_side != 0:
		return MoralityPk.KIND_CHALLENGE
	return battle_kind

## 在線找不到就從角色檔讀（擊殺者可能在戰鬥中斷線，已存檔離開）
func _char_any(char_id: String):
	var o: Session = host.session_for_char(char_id)
	if o != null:
		return o.character
	var names: Variant = host.ws.world.get("char_names", {})
	if not (names is Dictionary) or host.char_store == null:
		return null
	for k in names:
		var e: Variant = names[k]
		if e is Dictionary and str(e.get("char_id", "")) == char_id:
			var c = host.char_store.load_char(str(e.get("identity", "")), char_id)
			# M3d 審查第三輪：讀檔的角色 pk_decay_on 是預設 true → 照目前規則設（pk_decay 關時不遞減）
			if c != null and "pk_decay_on" in c:
				c.pk_decay_on = bool(host.rules.get("pk_decay", true))
			return c
	return null

# ======================================================================== 快照與生命週期

## 4.5.2 players[]：{ align, newbie }
func player_tags(o: Session) -> Dictionary:
	if o == null or o.character == null:
		return { "align": MoralityPk.ALIGN_NEUTRAL, "newbie": false }
	return {
		"align": str(o.character.align()),
		"newbie": newbie_protected(o.character),
	}

## 4.5.1 pending.challenges：[{ from_char, name, left_s }]（真實秒數）
func pending_for(s: Session) -> Array:
	var out: Array = []
	if s == null or s.character == null:
		return out
	var me := str(s.character.id)
	var now: float = host.now_s()
	for c in pending:
		if str(c["to_char"]) != me or float(c["expires_s"]) <= now:
			continue
		out.append({ "from_char": str(c["from_char"]), "name": str(c["from_name"]),
			"left_s": maxi(0, ceili((float(c["expires_s"]) - now) / _time_scale() - 1e-6)) })
	return out

## 叫戰到期 → 叫戰者收 challenge_expired；對方 sheet 刷新
func tick(now: float) -> void:
	if pending.is_empty():
		return
	for c in pending.duplicate():
		if float(c["expires_s"]) > now:
			continue
		pending.erase(c)
		_start_cooldown(str(c["from_char"]), str(c["to_char"]))
		var atk: Session = host.session_for_char(str(c["from_char"]))
		if atk != null:
			host.tell(atk, Protocol.CH_SYSTEM, E_CHALLENGE_EXPIRED, { "name": str(c["to_name"]) })
		var t: Session = host.session_for_char(str(c["to_char"]))
		if t != null:
			t.sheet_dirty = true

## 換角、斷線、關服：刪除他發出與收到的叫戰（不送通知）
func on_leave(s: Session) -> void:
	if s == null or s.character == null:
		return
	var me := str(s.character.id)
	for c in pending.duplicate():
		if str(c["from_char"]) == me or str(c["to_char"]) == me:
			pending.erase(c)
			var other_id := str(c["to_char"]) if str(c["from_char"]) == me else str(c["from_char"])
			var o: Session = host.session_for_char(other_id)
			if o != null and o != s:
				o.sheet_dirty = true

# ======================================================================== 輔助

func pk_mode() -> String:
	var m := str(host.options.get("pk_mode", PK_MODE_CLASSIC))
	return m if m in Protocol.PK_MODES else PK_MODE_CLASSIC

func protect_xp() -> int:
	return int(host.options.get("newbie_pk_protect_xp", DEFAULT_PROTECT_XP))

func retry_cooldown_real_s() -> int:
	return maxi(0, int(host.options.get("pending_retry_cooldown_real_s", DEFAULT_RETRY_COOLDOWN_REAL_S)))

func _start_cooldown(from_char: String, to_char: String) -> void:
	var cd := retry_cooldown_real_s()
	if cd > 0:
		_cooldown[from_char + "|" + to_char] = host.now_s() + _world_span(float(cd))

func _cooling(from_char: String, to_char: String) -> bool:
	var k := from_char + "|" + to_char
	if retry_cooldown_real_s() <= 0:
		return false   # 主機關掉冷卻：立即生效，舊的紀錄一併不算
	if not _cooldown.has(k):
		return false
	if float(_cooldown[k]) > host.now_s():
		return true
	_cooldown.erase(k)
	return false

func ttl_real_s() -> int:
	return int(host.options.get("pending_ttl_real_s", DEFAULT_TTL_REAL_S))

func pk_allowed_at(room_id: String) -> bool:
	var region: String = host.index.region_of(room_id)
	return bool(host.tables.get("regions", {}).get(region, {}).get("pk_allowed", false))

## 「在場」= 有在線 session 選著該角色且 room_id() 相同（4.2）
func _here(s: Session, char_id: String) -> Session:
	var t: Session = host.session_for_char(char_id)
	if t == null or t == s or t.character == null or t.room_id() != s.room_id():
		return null
	return t

## 同隊判定：PartySystem.player_tags(o).party_id（WP-PARTY）；沒有組隊系統時永遠 false
func same_party(a: Session, b: Session) -> bool:
	var party = host.get("party")
	if party == null or not party.has_method("player_tags"):
		return false
	var pa := str(party.player_tags(a).get("party_id", ""))
	return pa != "" and pa == str(party.player_tags(b).get("party_id", ""))

func _find(from_char: String, to_char: String) -> Dictionary:
	for c in pending:
		if str(c["from_char"]) == from_char and str(c["to_char"]) == to_char:
			return c
	return {}

func _drop_between(a: String, b: String) -> void:
	for c in pending.duplicate():
		var f := str(c["from_char"])
		var t := str(c["to_char"])
		if (f == a and t == b) or (f == b and t == a):
			pending.erase(c)

## H5：GameHost.world_span（WP-HOST）；沒有時自己乘 time_scale
func _world_span(real_s: float) -> float:
	if host.has_method("world_span"):
		return float(host.world_span(real_s))
	return real_s * _time_scale()

func _time_scale() -> float:
	var ts: Variant = host.ws.get("time_scale")
	return maxf(float(ts), 0.001) if ts != null else 1.0

# ==== M3d WP-LAW ====（M3D_PLAN §2.3、§2.5、§5.2.3）
## 合法緝拿的擊殺者變化：PK值 0、善惡 0、殺氣 BountyRules.LAWFUL_KILLING_INTENT（R3）
func _law_lawful_deltas(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	out["pk"] = 0
	out["morality"] = 0
	out["killing_intent"] = BountyRules.LAWFUL_KILLING_INTENT
	return out

## 守城官兵人數：劫鏢標記（WP-EVENTS 的 JiebiaoRules.rob_marked）期間至少 MoralityPk.GUARDS_PK（A9）。
## （JiebiaoRules 是 core 的 class_name，直接呼叫）
func _law_guard_count(ch, n: int) -> int:
	if ch == null or n >= MoralityPk.GUARDS_PK:
		return n
	# M3d 審查：JiebiaoRules 已合併 → 直接呼叫（原本每走一步都 load() 一次、再建整張方法表找 rob_marked）
	var ext_v: Variant = ch.get("ext")
	var ext: Dictionary = ext_v if ext_v is Dictionary else {}
	var now := float(host.now_s()) if host.has_method("now_s") else 0.0
	if JiebiaoRules.rob_marked(ext, now):
		return MoralityPk.GUARDS_PK
	return n
