class_name JiebiaoRules
extends RefCounted
## 劫鏢（危險鏢）的純規則（M3D_PLAN §5.2；1.0B；研究 2001-11-15 設計文）。純靜態：不碰主機，
## JiebiaoSystem、balance_sim、單元測試與 WP-LAW 的守城官兵判斷（rob_marked）共用。
##
## 設計文【已證實】：押金＝鏢價、送達領回兩倍、失敗沒收、劫鏢成功分鏢價 80%、劫鏢標記 1 小時（守城官兵追殺）、
## 劫鏢方不能逃、不接鏢冷卻 30／60／120 分、路上有「特殊地雷」、押鏢中頭上標「押鏢」。
## 門檻（實戰、名聲、歷練）R15：照「以下」的解讀取 ≥ 100,000／100／100【待考證】；劫鏢算強制 PK（PK值 +1）【設計提案】。

const QUEST_GROUP := "jiebiao"
const EXT_KEY := "jiebiao"              # ch.ext 的鍵（M3D_PLAN §8.1）
const MIN_COMBAT_XP := 100000           # 接鏢與劫鏢的實戰門檻（R15）
const MIN_FAME := 100
const MIN_LILIAN := 100
const RETURN_MULT := 2                  # 送達：還押金＋鏢價＝ 2 × 鏢價
const SUCCESS_FAME := 3                 # 同一般保鏢
const ROB_SHARE_PCT := 80               # 劫鏢成功：存活的劫鏢者平分 floor(鏢價 × 80%)
const ROB_MARK_S := 3600.0              # 劫鏢標記（世界秒），開戰當下就給
const COOLDOWNS_S := [1800.0, 3600.0, 7200.0]   # 不接鏢冷卻（世界秒，隨機三選一）
const MINE_PCT := 15                    # 特殊地雷：押鏢中進 WILD 房間的機率【設計提案】
const MINE_GAP_ROOMS := 3               # 每 3 間最多一次（遇過之後，接下來 2 間不擲）
const BANDIT_MIN := 2
const BANDIT_MAX := 4
const BANDIT_ID := "m_ev_jb_bandit"
const KIND_HU := "hu"                   # 護送鏢（客商）
const KIND_HUO := "huo"                 # 送貨鏢（鏢車）
const ESCORT_NPC := { KIND_HU: "n_ev_jb_client", KIND_HUO: "n_ev_jb_cart" }
const ROB_UNIT := { KIND_HU: "m_ev_jb_client", KIND_HUO: "m_ev_jb_cart" }
const TAG_ESCORT := "押鏢"
const TAG_ROBBER := "劫鏢"

## 劫鏢標記中（守城官兵至少 MoralityPk.GUARDS_PK 名；WP-LAW 讀）。ch_ext＝角色的 ext 字典
static func rob_marked(ch_ext: Dictionary, now_s: float) -> bool:
	if not (ch_ext is Dictionary):
		return false
	var jb: Variant = ch_ext.get(EXT_KEY, null)
	if not (jb is Dictionary):
		return false
	return _num((jb as Dictionary).get("rob_until_s", 0.0)) > now_s

## 每位存活劫鏢者分到的銀兩：floor(floor(鏢價 × 80%) / 人數)；沒人活著 → 0
static func rob_share(value: int, n_alive: int) -> int:
	if n_alive <= 0 or value <= 0:
		return 0
	return int(floor(float(value) * ROB_SHARE_PCT / 100.0)) / n_alive

## 送達時給回的銀兩（押金＋酬勞）
static func payout(value: int) -> int:
	return maxi(0, value) * RETURN_MULT

## 任務列的危險鏢設定 { value, kind, from, to }；不是危險鏢回 {}
static func spec_of(quest_row: Dictionary) -> Dictionary:
	if str(quest_row.get("group", "")) != QUEST_GROUP:
		return {}
	var j: Variant = quest_row.get("jiebiao", null)
	if not (j is Dictionary):
		return {}
	var v := int(_num((j as Dictionary).get("value", 0)))
	var k := str((j as Dictionary).get("kind", KIND_HUO))
	if v <= 0 or not ESCORT_NPC.has(k):
		return {}
	return { "value": v, "kind": k, "from": str(j.get("from", "")), "to": str(j.get("to", "")) }

## 接鏢的人物門檻（任務列 requires 也寫一份；這裡給 balance_sim 與系統再擋一次）："" 或原因
static func accept_reason(combat_xp: int, fame: int, lilian: int, sect: String) -> String:
	if sect == "gaibang":
		return "req_sect_not"          # 丐幫不能運鏢【已證實 2001】
	if combat_xp < MIN_COMBAT_XP:
		return "req_combat_xp_min"
	if fame < MIN_FAME:
		return "req_fame_min"
	if lilian < MIN_LILIAN:
		return "req_lilian_min"
	return ""

## 冷卻抽籤：rng_value ∈ [0, 1) → 30／60／120 分（世界秒）
static func cooldown_s(rng_value: float) -> float:
	var i := clampi(int(floor(rng_value * COOLDOWNS_S.size())), 0, COOLDOWNS_S.size() - 1)
	return float(COOLDOWNS_S[i])

## 特殊地雷：rooms_since＝上一次地雷之後走過的 WILD 房間數（含這一間；接鏢時從 MINE_GAP_ROOMS 起算＝第一間就能遇上）；
## roll ∈ [0, 100)。遇過一次之後接下來 2 間不擲（每 3 間最多一次）
static func mine_hits(rooms_since: int, roll: int) -> bool:
	if rooms_since < MINE_GAP_ROOMS:
		return false
	return roll < MINE_PCT

## 劫匪數量（rng_value ∈ [0, 1)）
static func bandit_count(rng_value: float) -> int:
	return clampi(BANDIT_MIN + int(floor(rng_value * (BANDIT_MAX - BANDIT_MIN + 1))), BANDIT_MIN, BANDIT_MAX)

## 朋友互劫的淨值（balance_sim ev_jb_zero_sum）：A 押鏢付押金 V、B 劫走拿 rob_share → 兩人合計 = −V + share（< 0）
static func friends_net(value: int, robbers: int) -> int:
	return -value + rob_share(value, robbers) * maxi(1, robbers)

static func _num(v: Variant) -> float:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			return float(v)
		TYPE_STRING:
			return float(v) if (v as String).is_valid_float() else 0.0
	return 0.0
