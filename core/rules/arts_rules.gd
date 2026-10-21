class_name ArtsRules
extends RefCounted
## M3d 門派武功鏈的純規則（M3D_PLAN §4；WP-ARTS）：星宿煉毒、血刀恐嚇與血池、全真殺古墓弟子、血魔刀法悟刀訣。
## 純邏輯（core/** 不碰主機）：ArtsSystem 讀主機狀態後呼叫這裡算數字。所有數字【設計提案】，出處見各常數註解。

# ---------------------------------------------------------------- 星宿 煉毒（§4.4；研究 od50「煉毒」原文，數字【設計提案】）
const MUDING := "i_ar_xh_muding"           # 小木鼎（出塵子「邪惡的練毒」給）
const LIANDU_SECT := "xingxiu"
const LIANDU_SKILL := "basic_poison"       # 基本毒術
const LIANDU_JING := 15                    # 每次扣精
const LIANDU_BASE := 20                    # 每次基本毒術熟練度
## 「特定狀況」（原文沒寫是哪些）【設計提案】：夜裡、在星宿地區、身上中毒；相乘
const LIANDU_NIGHT_MULT := 1.5
const LIANDU_REGION_MULT := 1.5
const LIANDU_POISON_MULT := 2.0
const LIANDU_REGIONS := ["xingxiu", "xingxiu_road"]
const POISON_CONDITION := "poison"

## 煉毒倍率：三種狀況相乘（最大 4.5）
static func liandu_mult(night: bool, region_id: String, poisoned: bool) -> float:
	var m := 1.0
	if night:
		m *= LIANDU_NIGHT_MULT
	if region_id in LIANDU_REGIONS:
		m *= LIANDU_REGION_MULT
	if poisoned:
		m *= LIANDU_POISON_MULT
	return m

## M3d 審查：每遊戲日基本毒術熟練最多 +200（比照恐嚇＋血池的威嚇每日上限）【設計提案】
const LIANDU_DAILY_CAP := 200
const COUNTER_LIANDU_GAIN := "liandu_gain"         # { day, n }：當日煉毒已得的熟練

## 今天還能煉多少熟練
static func liandu_room(counters: Dictionary, day: int) -> int:
	var e := day_entry(counters, COUNTER_LIANDU_GAIN, day, "")
	return maxi(0, LIANDU_DAILY_CAP - int(e.get("n", 0)))

## 記下今天加了多少；回實際可加的量（被上限截斷）
static func liandu_take(counters: Dictionary, day: int, want: int) -> int:
	var e := day_entry(counters, COUNTER_LIANDU_GAIN, day, "")
	var got := clampi(want, 0, maxi(0, LIANDU_DAILY_CAP - int(e.get("n", 0))))
	e["n"] = int(e.get("n", 0)) + got
	return got

static func liandu_gain(mult: float) -> int:
	return roundi(LIANDU_BASE * mult)

## 煉毒能不能做：回原因碼或 ""（先看門派、再看工具、再看精；照 §4.4 的原因碼）
static func liandu_reason(sect: String, has_tool: bool, jing: int) -> String:
	if sect != LIANDU_SECT:
		return "liandu_not_xh"
	if not has_tool:
		return "liandu_no_tool"
	if jing < LIANDU_JING:
		return "not_enough_jing"
	return ""

# ---------------------------------------------------------------- 血刀 恐嚇（§4.7；研究「恐嚇」指令，數字【設計提案】）
const INTIMIDATE_SECT := "xuedao"
const WEIHE := "weihe"                     # 威嚇（血刀門派技能）
const INTIMIDATE_JING := 20
const INTIMIDATE_SHEN := 20
const INTIMIDATE_MORALITY := -10
const INTIMIDATE_GAIN := 20                # 每次威嚇熟練度（沒有 < 50 的限制，跟雜務 q_ch_xd_kongxia 不同）
const WEIHE_DAILY_CAP := 200               # 恐嚇＋血池，每遊戲日威嚇熟練最多 +200
const INTIMIDATE_KINDS := ["STORY", "FUNC", "SHOP", "QUEST"]
## 這些服務的 NPC 不能恐嚇：衙門與佈告欄（WP-LAW）、比武報名（WP-EVENTS）、看守、收徒與傳功
const INTIMIDATE_BLOCK_SERVICES := ["BOARD", "LICENSE", "CLEANSE", "TOURNEY", "JAIL", "JOIN", "TEACH", "TRIAL"]
const INTIMIDATE_LINES := 4                # 模板 ar_intimidate_1..4 輪流
const COUNTER_INTIMIDATE := "intimidate"           # { day, npcs: [id] }
const COUNTER_WEIHE_GAIN := "intimidate_gain"      # { day, n }：當日已得的威嚇熟練（恐嚇＋血池）

## 對象 NPC 合不合格（純資料判斷；npc_sect＝SectSystem.npc_sect；quest_target＝有進行中任務的目標在他身上）
static func intimidate_target_ok(row: Dictionary, npc_sect: String, own_sect: String, quest_target: bool) -> bool:
	if row.is_empty() or quest_target:
		return false
	if not (str(row.get("kind", "")) in INTIMIDATE_KINDS):
		return false
	if npc_sect != "" and npc_sect == own_sect:
		return false
	for svc in row.get("services", []):
		if str(svc) in INTIMIDATE_BLOCK_SERVICES:
			return false
	return true

## 當日清單（換日重設）：counters[key] = { day, npcs: [] }
static func day_entry(counters: Dictionary, key: String, day: int, list_key := "npcs") -> Dictionary:
	var e: Variant = counters.get(key, {})
	if not (e is Dictionary) or int((e as Dictionary).get("day", -1)) != day:
		e = { "day": day }
		if list_key != "":
			e[list_key] = []
		counters[key] = e
	return e

## 今天還能加多少威嚇熟練（每日上限 200）
static func weihe_room(counters: Dictionary, day: int) -> int:
	var e := day_entry(counters, COUNTER_WEIHE_GAIN, day, "")
	return maxi(0, WEIHE_DAILY_CAP - int(e.get("n", 0)))

## 記下今天加了多少；回實際可加的量（被上限截斷）
static func weihe_take(counters: Dictionary, day: int, want: int) -> int:
	var e := day_entry(counters, COUNTER_WEIHE_GAIN, day, "")
	var got := clampi(want, 0, maxi(0, WEIHE_DAILY_CAP - int(e.get("n", 0))))
	e["n"] = int(e.get("n", 0)) + got
	return got

# ---------------------------------------------------------------- 血刀 血池（§4.7；2003 血池比武【後期版】，數字【設計提案】）
## 三階對手（NPC → 怪物、威嚇熟練）。M3D_PLAN 缺漏：FIGHT 服務一個 NPC 只能開一種怪，所以三階是三位 NPC
const XUECHI := {
	1: { "npc": "n_ar_xd_xuechi", "monster": "m_ar_xd_xuechi_1", "gain": 30 },
	2: { "npc": "n_ar_xd_xuechi_2", "monster": "m_ar_xd_xuechi_2", "gain": 60 },
	3: { "npc": "n_ar_xd_xuechi_3", "monster": "m_ar_xd_xuechi_3", "gain": 100 },
}
const XUECHI_DAILY := 3                    # 每階每遊戲日 3 次有熟練
const COUNTER_XUECHI := "xuechi"           # { day, n: { "1": int, "2": int, "3": int } }

## 怪物 id → 階（不是血池對手回 0）
static func xuechi_tier(monster_id: String) -> int:
	for t in XUECHI:
		if str(XUECHI[t]["monster"]) == monster_id:
			return int(t)
	return 0

# ---------------------------------------------------------------- 全真殺古墓弟子（§4.9；殺氣比一般高【已證實 2001 mengpai/6】，量【設計提案】）
const QZ_SECT := "quanzhen"
const GUMU_SECT := "gumu"
const COUNTER_QZ_GUMU := "qz_gumu_kills"
const QZ_GUMU_RULE := "qz_r_kill_gumu"
const GUMU_EXTRA_MIN := 5                  # 怪物列本身殺氣 0 時，至少多 5（「比一般高」）

## 加倍的那一份（×2＝原本那份之外再加一次）；原本 0 時給 GUMU_EXTRA_MIN
static func gumu_extra(base_killing_intent: int) -> int:
	return maxi(base_killing_intent, GUMU_EXTRA_MIN)

static func counts_gumu_kill(killer_sect: String, victim_sect: String) -> bool:
	return killer_sect == QZ_SECT and victim_sect == GUMU_SECT

# ---------------------------------------------------------------- 血魔刀法 悟刀訣（§4.8 步驟 4）
const XUEMO_QUEST := "q_ar_xd_xuemo"
const XUEMO_STAGE := "s_walk"
const XUEMO_ROOM := "xd_gate"
const XUEMO_ITEM := "i_ar_xd_daojue"
const XUEMO_FLAG := "xd_xuemo_walked"      # 悟出刀訣（STATE 目標看這個旗標）
const COUNTER_XUEMO_WALK := "xuemo_walk_s"
const XUEMO_SHICHEN := 2                   # 「兩三個時辰」取 2（2002-10-07）

## 要累計停留的世界秒數（2 個時辰）
static func xuemo_need_s(day_s: float) -> float:
	return WorldClock.shichen_len(day_s) * XUEMO_SHICHEN
