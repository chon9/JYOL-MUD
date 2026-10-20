class_name WorldClock
extends RefCounted
## 世界時鐘（M1_PLAN 4.15）：時辰、刻、晝夜、日曆。純計算。

const SHICHEN := ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
const KE := ["初", "一", "二", "三", "四", "五", "六", "七"]
const NIGHT_IDX := [10, 11, 0, 1, 2]       # 戌 亥 子 丑 寅
const START_SHICHEN := 4                    # 新世界從辰時開始
const DEFAULT_DAY_S := 7200.0

static func shichen_len(day_s: float) -> float:
	return maxf(day_s, 12.0) / 12.0

## 世界時間 → { shichen_idx, shichen_name, ke, night, day, month, year, text }
static func clock(world_s: float, day_s: float = DEFAULT_DAY_S) -> Dictionary:
	var day_len := maxf(day_s, 12.0)
	var sc := shichen_len(day_len)
	var clock_s := maxf(world_s, 0.0) + START_SHICHEN * sc
	var in_day := fposmod(clock_s, day_len)
	var idx := clampi(floori(in_day / sc), 0, 11)
	var ke := clampi(floori((in_day - idx * sc) / sc * 8.0), 0, 7)
	var day := floori(clock_s / day_len) + 1
	var month := (floori((day - 1) / 30.0) % 12) + 1
	var year := floori((day - 1) / 360.0) + 1
	return {
		"shichen_idx": idx,
		"shichen_name": SHICHEN[idx],
		"ke": ke,
		"night": idx in NIGHT_IDX,
		"day": day,
		"month": month,
		"year": year,
		"text": "%s時%s刻" % [SHICHEN[idx], KE[ke]],
	}

static func is_night(world_s: float, day_s: float = DEFAULT_DAY_S) -> bool:
	return bool(clock(world_s, day_s)["night"])

## 世界時間要再加多少秒才會到達某個時辰的起點（測試與 bot 用）
static func seconds_until_shichen(world_s: float, target_idx: int, day_s: float = DEFAULT_DAY_S) -> float:
	var day_len := maxf(day_s, 12.0)
	var sc := shichen_len(day_len)
	var clock_s := maxf(world_s, 0.0) + START_SHICHEN * sc
	var in_day := fposmod(clock_s, day_len)
	var target := posmod(target_idx, 12) * sc
	var d := target - in_day
	if d < 0.0:
		d += day_len
	return d
