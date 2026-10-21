class_name ErrandsSystem
extends RefCounted
## M3d 跑腿與城鎮學點（M3D_PLAN §6；WP-ERRANDS）。GameHost 以路徑 load()（host.errands；不設型別的 _init，測試能傳假主機）。
## 任務本身（柯鎮惡 → 郭靖、豬哥義 → 三八紅、送便當、酒鬼、阿虎、九尾靈狐）都是一般任務 v2＋chore 欄位（QuestSystem）；
## 這裡只做任務引擎做不到的部分：
##   - 武林帖（i_er_wulintie，1.0B）：在野外或城裡「使用」→ 依實戰開打武林人士 m_er_wulin_1..4（FIGHT、可逃、不拉隊友、不准中途加入）；
##     打贏 → 名聲 +WLT_FAME、歷練 +WLT_LILIAN、記 counters.wulintie_day；距上次打贏不到 WLT_COOLDOWN_DAYS 遊戲日 → wlt_cooldown
##     （帖子不扣）；輸或逃 → 帖子已用、不設冷卻。研究：2001-12-03「買武林帖去打，似乎得 3 天才能打一次」【已證實】；
##     賣家、價錢、對手、每次獎勵【設計提案】（作者 8 張＋其他來源 → 名聲 3000、歷練 10000）。
## 呼叫點：IntentsItem.use_item 開頭的 WP-ERRANDS 單行鉤子（on_use_item）、GameHost.m3d_battle_settled（on_battle_settled）。

const WULINTIE := ErrandsRules.WULINTIE
const WLT_DAY_KEY := "wulintie_day"
const WLT_COOLDOWN_DAYS := ErrandsRules.WLT_COOLDOWN_DAYS
const WLT_FAME := ErrandsRules.WLT_FAME
const WLT_LILIAN := ErrandsRules.WLT_LILIAN
const WLT_ROOM_TYPES := ["WILD", "CITY"]
const R_WLT_COOLDOWN := "wlt_cooldown"
const R_WLT_PLACE := "wlt_place"
const E_WLT_START := "er_wlt_start"
const E_WLT_WIN := "er_wlt_win"
const E_WLT_LOST := "er_wlt_lost"
const E_WLT_REFUND := "er_wlt_refund"

var host
## bid -> char_id：武林帖開的戰鬥（行程內；主機重開時戰鬥本來就作廢）
var _wlt_battles: Dictionary = {}

func _init(p_host) -> void:
	host = p_host

# ---------------------------------------------------------------- 純邏輯（core/rules/errands_rules.gd）
static func wulin_tier(combat_xp: int) -> int:
	return ErrandsRules.wulin_tier(combat_xp)

static func wulin_monster(combat_xp: int) -> String:
	return ErrandsRules.wulin_monster(combat_xp)

static func wlt_ready(last_day: int, today: int) -> bool:
	return ErrandsRules.wlt_ready(last_day, today)

# ---------------------------------------------------------------- 鉤子
## IntentsItem.use_item：不是武林帖 → {}（交回原本的流程）；是 → 處理完回 ok／fail
func on_use_item(s, uid: String) -> Dictionary:
	if s == null or s.character == null or uid == "":
		return {}
	var ch = s.character
	var inst: Dictionary = ch.inventory.find(uid)
	if inst.is_empty() or str(inst.get("id", "")) != WULINTIE:
		return {}
	if s.battle_id != 0:
		return GameHost.fail("in_battle")
	if not _place_ok(s):
		return GameHost.fail(R_WLT_PLACE)
	var today := _today()
	if not wlt_ready(CharData.to_int(ch.counters.get(WLT_DAY_KEY, -1), -1), today):
		return GameHost.fail(R_WLT_COOLDOWN)
	var mid := wulin_monster(int(ch.combat_xp))
	if not host.tables.get("monsters", {}).has(mid):
		return GameHost.fail(R_WLT_PLACE)   # 資料缺（1.0A 世界沒有武林帖，正常走不到這裡）
	ch.inventory.remove(uid, 1)
	host.item_lost_event(s, WULINTIE, 1)
	s.sheet_dirty = true
	host.tell(s, Protocol.CH_SYSTEM, E_WLT_START, { "npc_name": host.monster_name(mid) })
	# M3d 審查：武林帖是一個人的挑戰——不拉隊友，也不准中途加入（party_only；否則強的朋友走進來代打、
	# 或朋友搶到最後一擊時帖子白白用掉）【設計提案】
	var bid := int(host.battles.start_ex(s, [mid], "FIGHT", { "pull_party": false, "party_only": true }))
	if bid > 0:
		_wlt_battles[bid] = str(ch.id)
	return GameHost.ok()

## GameHost.m3d_battle_settled：武林帖的戰鬥打贏 → 名聲、歷練、冷卻
func on_battle_settled(s, ch, summary: Dictionary) -> void:
	if ch == null:
		return
	var bid := int(summary.get("bid", 0))
	if not _wlt_battles.has(bid) or str(_wlt_battles[bid]) != str(ch.id):
		return
	_wlt_battles.erase(bid)
	var per := str(summary.get("per", summary.get("result", "")))
	# M3d 審查第三輪：主機關閉（abort_all）或戰鬥逾時＝ABORTED → 沒分勝負，帖子退還（_settle_player 之後照常存檔）
	if per == "ABORTED":
		var g: Dictionary = host.give_item(ch, WULINTIE, 1)
		if s != null and bool(g.get("ok", false)):
			host.item_gain_event(s, WULINTIE, 1)
			host.tell(s, Protocol.CH_SYSTEM, E_WLT_REFUND, {})
			s.sheet_dirty = true
		return
	var won := per == "VICTORY" and not (summary.get("kills", []) as Array).is_empty()
	if not won:
		if s != null:
			host.tell(s, Protocol.CH_SYSTEM, E_WLT_LOST, {})
		return
	var got: Dictionary = ch.apply_rewards({ "fame": WLT_FAME, "lilian": WLT_LILIAN }, host.rules)
	ch.counters[WLT_DAY_KEY] = _today()
	if s != null:
		host.tell(s, Protocol.CH_SYSTEM, E_WLT_WIN, { "fame": int(got.get("fame", 0)), "lilian": int(got.get("lilian", 0)) })
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_REWARD, {
			"combat_xp": 0, "learn_points": 0, "money": 0, "fame": int(got.get("fame", 0)), "morality": 0,
			"lilian": int(got.get("lilian", 0)), "killing_intent": 0 })
		s.sheet_dirty = true

# ---------------------------------------------------------------- 內部
func _today() -> int:
	return int(host.clock().get("day", 0))

## 野外或城裡（地區 type WILD／CITY）、不在牢裡
func _place_ok(s) -> bool:
	var sects = host.get("sects")
	if sects != null and (sects as Object).has_method("is_jailed") and bool(sects.is_jailed(s)):
		return false
	var rid: String = host.index.region_of(s.room_id())
	var rtype := str(host.tables.get("regions", {}).get(rid, {}).get("type", ""))
	return rtype in WLT_ROOM_TYPES
