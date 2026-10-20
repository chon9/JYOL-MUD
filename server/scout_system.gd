class_name ScoutSystem
extends RefCounted
## 查看偵察（M3 小範圍【設計提案・非原作】；docs/GDD.md §5.10、docs/M2_PLAN.md §9）。
## 原作的踩地雷只在「走進房間」時判定，練功要在兩個房間之間來回走。本作加一條路：在有遇敵表的房間（野外、洞穴）
## 按「查看」——除了照舊印出房間描述——主機擲一次遇敵表（必定發現；怪物與數量規則同踩地雷），
## 送一個邀戰提示「你發現附近有：野兔 ×2」，玩家選「迎戰」（與踩地雷完全相同的開戰：同房閒置隊友一起拉進來、同樣的獎勵）
## 或「離開」。
## 主機權威：提示存在 Session.scout_offer（id、角色、房間、怪物、到期時間），換房、進戰鬥、離線／換角、過期、
## 主機關掉 scout_enabled 都會失效；迎戰時驗證 id、同一個房間、不在戰鬥中、沒有倒下。怪物由主機決定，客戶端只送 offer_id。
## 冷卻：在有遇敵表的房間偵察一次後 COOLDOWN_S 世界秒內不能再偵察（與修煉內力一樣隨 time_scale 縮放，
## 角色表 cooldowns.scout 送剩餘真實秒數，按鈕顯示「查看（5 秒）」）；安全的房間（沒有遇敵表）查看沒有冷卻，只印房間描述。

const COOLDOWN_KEY := "scout"
const OPTION := "scout_enabled"
## 偵察冷卻（世界秒；time_scale 2 時真實 3 秒）【設計提案】
const COOLDOWN_S := 6.0
## 邀戰提示的有效時間（真實秒，與組隊邀請一樣以 world_span 換算）【設計提案】
const OFFER_TTL_REAL_S := 30.0
## 冷卻寬限（真實秒）：客戶端照收件時刻倒數，主機忙的時候兩邊會差幾個影格；剩不到這麼多就當作冷卻完了，
## 免得玩家看到按鈕亮了、按下去卻是「再等 1 秒吧」（M3a 整合：負載高時 ui_playthrough 偶發）
const GRACE_REAL_S := 0.3

const WHY_MOVED := "moved"
const WHY_BATTLE := "battle"
const WHY_EXPIRED := "expired"
const WHY_DECLINED := "declined"
const WHY_REPLACED := "replaced"
const WHY_LOGOUT := "logout"
const WHY_DISABLED := "disabled"

var host: GameHost

func _init(p_host: GameHost) -> void:
	host = p_host

# ---------- 查詢 ----------
## 伺服器選項 scout_enabled（預設 true；false → 查看與以前一樣只印房間描述）
func enabled() -> bool:
	return host.options.get(OPTION, true) != false

## 這個房間能不能偵察：有遇敵率、遇敵表不是空的（與房間視圖的 danger／safe 同一個判斷）
func scoutable(room_id: String) -> bool:
	if room_id == "" or host.index.encounter_rate(room_id) <= 0.0:
		return false
	var enc: Variant = host.index.room(room_id).get("encounter", {})
	if not (enc is Dictionary):
		return false
	var table: Variant = (enc as Dictionary).get("table", [])
	return table is Array and not (table as Array).is_empty()

## 在這裡按查看會不會偵察（選項開著、有角色、房間可偵察）。
## M3a：坐牢中不能偵察；房間 encounter_exempt 列到自己門派時（古墓迷宮對古墓弟子）也不能偵察（M3A_PLAN 3.6、6.6）
func active_here(s: Session) -> bool:
	if s == null or s.character == null or not enabled() or not scoutable(s.room_id()):
		return false
	if s.character.is_jailed():
		return false
	return not host.regions.encounter_exempt(s.character, s.room_id())

## 冷卻剩餘的「真實秒數」；在不能偵察的地方一律 0（安全的房間查看沒有冷卻）。
## 兩個時鐘取較短者：世界時間（÷ time_scale；測試的 ws.advance 推得動）與主機本機的真實時鐘（Time.get_ticks_msec）。
## 視窗模式掉幀時世界時間會比真實時間慢一點，客戶端照真實時間倒數到 0 就按，主機不能還說「再等 1 秒」。
func cooldown_left_real(s: Session) -> float:
	if not active_here(s):
		return 0.0
	var by_world := host.real_span(maxf(0.0, s.scout_ready_s - host.now_s()))
	var by_clock := maxf(0.0, (s.scout_ready_ms - Time.get_ticks_msec()) / 1000.0)
	return minf(by_world, by_clock)

func has_offer(s: Session) -> bool:
	return s != null and not s.scout_offer.is_empty()

# ---------- 查看 ----------
## look 的偵察部分（房間描述已經印了）。回傳 "offer"、"none"（遇敵表挑不出怪物）、"busy"（冷卻中）或 ""（不適用）
func on_look(s: Session) -> String:
	if not active_here(s) or s.battle_id != 0:
		return ""
	var now := host.now_s()
	var left_real := cooldown_left_real(s)
	if left_real > GRACE_REAL_S:
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_SCOUT_BUSY, { "n": maxi(1, ceili(left_real - 1e-6)) })
		return "busy"
	s.scout_ready_s = now + COOLDOWN_S
	s.scout_ready_ms = Time.get_ticks_msec() + int(round(host.real_span(COOLDOWN_S) * 1000.0))
	s.sheet_dirty = true   # cooldowns.scout 立刻開始倒數
	var room_id := s.room_id()
	var ids: Array = []
	for mid in Encounter.pick(host.index.room(room_id), host.rng):
		if host.tables.get("monsters", {}).has(str(mid)):
			ids.append(str(mid))
	invalidate(s, WHY_REPLACED)
	if ids.is_empty():
		host.tell(s, Protocol.CH_SCENE, Protocol.E_SCOUT_NONE, { "room_name": host.room_name(room_id) })
		return "none"
	var offer := {
		"id": host.new_id("sc_"), "char_id": str(s.character.id), "room": room_id, "monsters": ids,
		"expires_s": now + host.world_span(OFFER_TTL_REAL_S),
	}
	s.scout_offer = offer
	var text := monsters_text(ids)
	host.tell(s, Protocol.CH_SCENE, Protocol.E_SCOUT_FOUND, { "room_name": host.room_name(room_id), "monsters": text })
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_SCOUT_OFFER, {
		"offer_id": str(offer["id"]), "room": room_id, "room_name": host.room_name(room_id),
		"monsters": groups(ids), "text": "你發現附近有：" + text, "ttl_s": OFFER_TTL_REAL_S,
	}, true)
	return "offer"

## [ { id, name, n } ]（依第一次出現的順序合併同種怪物）
func groups(ids: Array) -> Array:
	var out: Array = []
	var at := {}
	for mid in ids:
		var k := str(mid)
		if at.has(k):
			out[int(at[k])]["n"] = int(out[int(at[k])]["n"]) + 1
		else:
			at[k] = out.size()
			out.append({ "id": k, "name": host.monster_name(k), "n": 1 })
	return out

## 「野兔 ×2、野狼 ×1」
func monsters_text(ids: Array) -> String:
	var parts: PackedStringArray = []
	for g in groups(ids):
		parts.append("%s ×%d" % [str(g["name"]), int(g["n"])])
	return "、".join(parts)

# ---------- intent ----------
## scout_accept：scout_gone（沒有這個提示、換了房間或角色、選項已關）→ scout_expired → scout_dead（氣 ≤ 0）→ 開戰。
## 不在戰鬥中由 GameHost.IDLE 先擋（in_battle）。開戰與踩地雷相同：battles.start(…, "ENCOUNTER")，同房閒置隊友一起入場。
func accept(s: Session, offer_id: String) -> Dictionary:
	var o := s.scout_offer
	if o.is_empty() or str(o.get("id", "")) != offer_id:
		return GameHost.fail("scout_gone")
	if str(o.get("char_id", "")) != str(s.character.id) or str(o.get("room", "")) != s.room_id():
		invalidate(s, WHY_MOVED)
		return GameHost.fail("scout_gone")
	if not enabled():
		invalidate(s, WHY_DISABLED)
		return GameHost.fail("scout_gone")
	if host.now_s() > float(o.get("expires_s", 0.0)):
		expire(s)
		return GameHost.fail("scout_expired")
	if int(s.character.vitals.get("qi", 0)) <= 0:
		return GameHost.fail("scout_dead")
	var ids: Array = (o.get("monsters", []) as Array).duplicate()
	s.scout_offer = {}
	var names: PackedStringArray = []
	for mid in ids:
		names.append(host.monster_name(str(mid)))
	host.tell(s, Protocol.CH_BATTLE, Protocol.E_SCOUT_ENGAGE, {
		"clock": host.clock()["text"], "room_name": host.room_name(s.room_id()), "monsters": "、".join(names) })
	host.regions.start_encounter(s, ids)
	return GameHost.ok()

## scout_decline：一律成功（提示已經失效也一樣，視窗本來就要關）；對得上目前的提示才清掉並印一句
func decline(s: Session, offer_id: String) -> Dictionary:
	var o := s.scout_offer
	if not o.is_empty() and str(o.get("id", "")) == offer_id:
		s.scout_offer = {}
		host.tell(s, Protocol.CH_SCENE, Protocol.E_SCOUT_DECLINED, {})
	return GameHost.ok()

# ---------- 失效 ----------
## 清掉提示；notify → 送 scout_closed（ui）讓視窗關掉
func invalidate(s: Session, why: String, notify := true) -> void:
	if s == null or s.scout_offer.is_empty():
		return
	var id := str(s.scout_offer.get("id", ""))
	s.scout_offer = {}
	if notify:
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_SCOUT_CLOSED, { "offer_id": id, "why": why }, true)

func expire(s: Session) -> void:
	if s == null or s.scout_offer.is_empty():
		return
	host.tell(s, Protocol.CH_SCENE, Protocol.E_SCOUT_EXPIRED, {})
	invalidate(s, WHY_EXPIRED)

## 每 tick：過期、換了房間／角色、進了戰鬥、選項被關掉的提示一律失效（走路、開戰、離線另有即時的呼叫點）
func tick() -> void:
	var now := host.now_s()
	var on := enabled()
	for s in host.sessions():
		if s.scout_offer.is_empty():
			continue
		var o: Dictionary = s.scout_offer
		if s.character == null or str(o.get("char_id", "")) != str(s.character.id):
			invalidate(s, WHY_LOGOUT)
		elif s.battle_id != 0:
			invalidate(s, WHY_BATTLE)
		elif str(o.get("room", "")) != s.room_id():
			invalidate(s, WHY_MOVED)
		elif not on:
			invalidate(s, WHY_DISABLED)
		elif now > float(o.get("expires_s", 0.0)):
			expire(s)
