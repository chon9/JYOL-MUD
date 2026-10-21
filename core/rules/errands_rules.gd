class_name ErrandsRules
extends RefCounted
## M3d 跑腿與城鎮學點的純邏輯（M3D_PLAN §6；WP-ERRANDS）。QuestSystem（chore 欄位）、ErrandsSystem（武林帖）、
## tools/balance_sim.gd（er_town_lp_cap）與單元測試共用；不碰主機（core/** 純邏輯）。

# ---------------------------------------------------------------- chore 欄位（§6.1）
const CHORE_KINDS := ["SECT", "TOWN"]
const DECAY_ALL_KEYS := ["money", "fame", "lilian", "combat_xp", "learn_points"]

## chore.kind == "TOWN"（缺 ＝ SECT）
static func is_town(c: Dictionary) -> bool:
	return str(c.get("kind", "SECT")) == "TOWN"

## 第 n_today＋1 次（同一遊戲日）的百分比：decay_pct[min(n, 長度−1)]；沒有 decay_pct → 100
static func chore_pct(c: Dictionary, n_today: int) -> int:
	var dp: Variant = c.get("decay_pct", [100])
	if dp is Array and not (dp as Array).is_empty():
		return clampi(CharData.to_int(dp[mini(maxi(0, n_today), (dp as Array).size() - 1)]), 0, 100)
	return 100

## TOWN 雜務的學點（不看新手期、不看規則 chore_xuedian）：{ "lp": int, "why": ""|"daily" }；lp 欄位本來就是 0 時 why ""
static func town_lp(c: Dictionary, n_today: int) -> Dictionary:
	var base := CharData.to_int(c.get("lp", 0))
	var lp := floori(base * chore_pct(c, n_today) / 100.0)
	if base > 0 and lp <= 0:
		return { "lp": 0, "why": "daily" }
	return { "lp": maxi(0, lp), "why": "" }

## decay_all：正值的 money／fame／lilian／combat_xp／learn_points 乘 pct/100（floor）；負值是代價，不縮放
static func scale_decay_all(rw: Dictionary, pct: int) -> Dictionary:
	var out := rw.duplicate(true)
	for k in DECAY_ALL_KEYS:
		var v := CharData.to_int(out.get(k, 0))
		if v > 0:
			out[k] = floori(v * pct / 100.0)
	return out

# ---------------------------------------------------------------- 武林帖（§6.2.3）
const WULINTIE := "i_er_wulintie"
const WLT_COOLDOWN_DAYS := 3
const WLT_FAME := 60
const WLT_LILIAN := 200
## 實戰門檻 → 對手：< 2 萬 → 1；< 10 萬 → 2；< 50 萬 → 3；其他 → 4
const WLT_TIER_XP := [20000, 100000, 500000]
const WLT_MONSTERS := ["m_er_wulin_1", "m_er_wulin_2", "m_er_wulin_3", "m_er_wulin_4"]

static func wulin_tier(combat_xp: int) -> int:
	for i in WLT_TIER_XP.size():
		if combat_xp < int(WLT_TIER_XP[i]):
			return i + 1
	return WLT_TIER_XP.size() + 1

static func wulin_monster(combat_xp: int) -> String:
	return str(WLT_MONSTERS[wulin_tier(combat_xp) - 1])

## 今天（遊戲日 today）還能不能打：上次打贏在 last_day（-1 ＝ 沒打贏過）
static func wlt_ready(last_day: int, today: int) -> bool:
	return last_day < 0 or today - last_day >= WLT_COOLDOWN_DAYS
