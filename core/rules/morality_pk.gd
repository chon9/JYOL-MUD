class_name MoralityPk
extends RefCounted
## PK值、善惡、殺氣、守衛的純規則（M2_PLAN 4.6.4、5.2）。只吃參數，不引用 Autoload 或主機。
## 數值除「PK值每 30 分鐘 −1【已證實 newton】」「PK > 3 守衛追殺【已證實】」「善惡負被攻擊【已證實】」之外，
## 一律是【設計提案】。

const PK_DECAY_ONLINE_S := 1800.0      # 每 1800 秒角色上線時間 −1（只算上線時間：世界凍結時不遞減）
const GUARD_PK_THRESHOLD := 3          # PK值 > 3 → 守城官兵追殺
const ALIGN_GOOD_MIN := 101            # 善惡 > 100 → 善（名字白色）
const ALIGN_EVIL_MAX := -101           # 善惡 < -100 → 惡（名字藍色）
const MORALITY_MIN := -1000
const MORALITY_MAX := 1000
const KILL_KILLING_INTENT := 100       # 殺死玩家 +100 殺氣（叫戰、強制都算）
## 強制擊殺非惡人【設計提案】。原本是 −50：配上【已證實】的「善惡為負進出城就有官兵」，一次 PK 就讓善惡 0 的人
## 進出城挨打，【已證實】的「PK值 > 3 才追殺」形同虛設（M2 審查）。改小，讓平時有行善（善惡 ≥ 10）的人保有這個寬限。
const FORCED_KILL_MORALITY := -10
const FORCED_KILL_EVIL_MORALITY := 10  # 強制擊殺惡人
const GUARDS_PK := 2                   # PK值 > 3 → 2 名官兵
const GUARDS_EVIL := 1                 # 否則善惡 < 0 → 1 名

const ALIGN_GOOD := "GOOD"
const ALIGN_NEUTRAL := "NEUTRAL"
const ALIGN_EVIL := "EVIL"
const KIND_FORCED := "FORCED"
const KIND_CHALLENGE := "CHALLENGE"

static func align_of(morality: int) -> String:
	if morality >= ALIGN_GOOD_MIN:
		return ALIGN_GOOD
	if morality <= ALIGN_EVIL_MAX:
		return ALIGN_EVIL
	return ALIGN_NEUTRAL

## 惰性遞減：max(0, pk_base − floor((online_s − pk_stamp_s) / 1800))
static func pk_value(pk_base: int, pk_stamp_s: float, online_s: float) -> int:
	if pk_base <= 0:
		return 0
	var elapsed := maxf(0.0, online_s - pk_stamp_s)
	return maxi(0, pk_base - floori(elapsed / PK_DECAY_ONLINE_S))

## 進出城時的官兵人數：pk > 3 → 2；否則 morality < 0 → 1；否則 0。
## newbie（實戰 < protect_xp）：只看 PK值 > 3【已證實】；善惡負不追殺【設計提案・M3c 審查】——
## M3c 起新手區有善惡為負的可殺 NPC（黃狗、羊、小孩、老礦工），新手殺一隻就善惡 < 0，
## 守城官兵（新手勝率 0%）會在每次進出城時打死他，形成死亡循環
static func guard_count(pk: int, morality: int, newbie := false) -> int:
	if pk > GUARD_PK_THRESHOLD:
		return GUARDS_PK
	if morality < 0 and not newbie:
		return GUARDS_EVIL
	return 0

## 擊殺玩家時擊殺者的變化
static func kill_deltas(kind: String, victim_morality: int) -> Dictionary:
	var forced := kind == KIND_FORCED
	var moral := 0
	if forced:
		moral = FORCED_KILL_EVIL_MORALITY if victim_morality <= ALIGN_EVIL_MAX else FORCED_KILL_MORALITY
	return { "pk": 1 if forced else 0, "killing_intent": KILL_KILLING_INTENT, "morality": moral }

## 新手保護：實戰 < protect_xp 不能被強制 PK
static func can_be_forced(target_combat_xp: int, protect_xp: int) -> bool:
	return target_combat_xp >= protect_xp

static func is_newbie(combat_xp: int, protect_xp: int) -> bool:
	return not can_be_forced(combat_xp, protect_xp)

static func clamp_morality(v: int) -> int:
	return clampi(v, MORALITY_MIN, MORALITY_MAX)
