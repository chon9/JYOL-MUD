class_name RogueProfile
extends RefCounted
## 試煉者檔案（ROGUE_PLAN §3.9.3）【設計提案・非原作】：<資料根目錄>/rogue/profile.json。
## 永久點數只在江湖試煉開局時加到可分配點數；絕不影響 MUD 角色或世界（U10、O1）。
## 讀：本體壞掉時依序試 .bak1–.bak5（SaveManager.write_json_atomic 的備份輪替）；全都不能讀 → 預設值（不覆蓋壞檔，
## 下一次寫入時壞檔會被輪替成 .bak1 保留）。寫由主機端（RogueSystem）以 SaveManager.write_json_atomic 進行。

const SCHEMA := 1
const FILE_REL := "rogue/profile.json"
const HISTORY_MAX := 20
const DEFAULT_CAP := 60
const BAK_COUNT := 5
const INT_KEYS := ["points_total", "runs", "best_wins", "total_wins", "foes_beaten", "bosses_beaten", "updated"]

static func default_profile() -> Dictionary:
	return {
		"schema": SCHEMA, "identity": "", "name": "",
		"points_total": 0, "runs": 0, "best_wins": 0, "total_wins": 0,
		"foes_beaten": 0, "bosses_beaten": 0,
		"famous_beaten": {}, "famous_allied": {},
		"history": [],
		"in_progress": {},
		"updated": 0,
	}

static func _int(v: Variant, def: int = 0) -> int:
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT and is_finite(v):
		return int(v)
	if typeof(v) == TYPE_STRING and (v as String).is_valid_int():
		return (v as String).to_int()
	return def

## 缺鍵補預設、型別轉 int、夾 0..cap（點數）／非負（其餘）
static func normalize(d: Variant, cap: int = DEFAULT_CAP) -> Dictionary:
	var p := default_profile()
	if not (d is Dictionary):
		return p
	var src: Dictionary = d
	p["identity"] = str(src.get("identity", "")) if src.get("identity") is String else ""
	p["name"] = str(src.get("name", "")) if src.get("name") is String else ""
	for k in INT_KEYS:
		p[k] = maxi(0, _int(src.get(k, 0)))
	p["points_total"] = clampi(int(p["points_total"]), 0, maxi(0, cap))
	for k in ["famous_beaten", "famous_allied"]:
		var m: Variant = src.get(k, {})
		var out := {}
		if m is Dictionary:
			for id in m:
				var n := maxi(0, _int(m[id]))
				if n > 0:
					out[str(id)] = n
		p[k] = out
	var hist: Array = []
	if src.get("history") is Array:
		for h in src["history"]:
			if not (h is Dictionary):
				continue
			var bc: Variant = h.get("best_card", {})
			hist.append({
				"t": maxi(0, _int(h.get("t", 0))), "seed": maxi(0, _int(h.get("seed", 0))),
				"wins": maxi(0, _int(h.get("wins", 0))), "bosses": maxi(0, _int(h.get("bosses", 0))),
				"cause": str(h.get("cause", "DEATH")) if str(h.get("cause", "DEATH")) in RogueRules.CAUSES else "DEATH",
				"points": maxi(0, _int(h.get("points", 0))),
				"best_card": { "id": str(bc.get("id", "")), "title": str(bc.get("title", "")), "rarity": str(bc.get("rarity", "")) }
					if bc is Dictionary else { "id": "", "title": "", "rarity": "" },
			})
			if hist.size() >= HISTORY_MAX:
				break
	p["history"] = hist
	p["in_progress"] = _norm_progress(src.get("in_progress", {}))
	return p

## 進行中的一局（審查：當機、強制關閉時點數不能歸零）：每打贏一場由主機寫一次；下一次 rogue_open（或大廳讀檔）以 LEAVE 結算。
## { run_id, seed, wins, bosses_beaten, foes_beaten, best_card, famous_beaten: [ids], famous_allied: [ids], t }；沒有＝{}
static func _norm_progress(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	var rid := str(d.get("run_id", "")) if d.get("run_id") is String else ""
	var wins := maxi(0, _int(d.get("wins", 0)))
	if rid == "" or wins <= 0:
		return {}
	var bc: Variant = d.get("best_card", {})
	var out := { "run_id": rid, "seed": maxi(0, _int(d.get("seed", 0))), "wins": wins,
		"bosses_beaten": maxi(0, _int(d.get("bosses_beaten", 0))), "foes_beaten": maxi(0, _int(d.get("foes_beaten", 0))),
		"t": maxi(0, _int(d.get("t", 0))),
		"best_card": { "id": str(bc.get("id", "")), "title": str(bc.get("title", "")), "rarity": str(bc.get("rarity", "")) }
			if bc is Dictionary else { "id": "", "title": "", "rarity": "" } }
	for k in ["famous_beaten", "famous_allied"]:
		var lst: Array = []
		if d.get(k) is Array:
			for id in d[k]:
				lst.append(str(id))
		out[k] = lst
	return out

## 由一局的 summary（RogueRun.summary）做出 in_progress 紀錄
static func progress_of(summary: Dictionary, t: int) -> Dictionary:
	var rec := summary.duplicate(true)
	rec["t"] = t
	return _norm_progress(rec)

## 有沒結算的 in_progress → 以 LEAVE 結算（apply_run）；回 { profile, settled: bool, summary }
static func settle_pending(p: Dictionary, r: Dictionary) -> Dictionary:
	var cap := int(r.get("points_cap", DEFAULT_CAP))
	var np := normalize(p, cap)
	var ip: Dictionary = np.get("in_progress", {})
	if ip.is_empty():
		return { "profile": np, "settled": false, "summary": {} }
	var summary := ip.duplicate(true)
	summary["cause"] = "LEAVE"
	return { "profile": apply_run(np, summary, r), "settled": true, "summary": summary }

static func path(root_dir: String) -> String:
	return root_dir.path_join(FILE_REL)

static func read(root_dir: String) -> Dictionary:
	var main := path(root_dir)
	var candidates: Array = [main]
	for i in range(1, BAK_COUNT + 1):
		candidates.append("%s.bak%d" % [main, i])
	for c in candidates:
		if not FileAccess.file_exists(c):
			continue
		var text := FileAccess.get_file_as_string(c)
		var json := JSON.new()
		if text.is_empty() or json.parse(text) != OK or not (json.data is Dictionary):
			continue
		if _int((json.data as Dictionary).get("schema", 0)) > SCHEMA:
			continue   # 較新版本寫的檔：不認得就不用（也不覆蓋：寫入時輪替成備份）
		return normalize(json.data)
	return default_profile()

## 結算一局：回新的 profile；summary 的 points_gained、points_total、new_best 在這裡算好填回（§3.9.2）
static func apply_run(p: Dictionary, summary: Dictionary, r: Dictionary) -> Dictionary:
	var cap := int(r.get("points_cap", DEFAULT_CAP))
	var np := normalize(p, cap)
	var wins := maxi(0, _int(summary.get("wins", 0)))
	var bosses := maxi(0, _int(summary.get("bosses_beaten", 0)))
	var new_best := wins > int(np["best_wins"])
	var gained := RogueRules.award(wins, bosses, int(np["points_total"]), new_best, r)
	np["points_total"] = clampi(int(np["points_total"]) + gained, 0, cap)
	np["runs"] = int(np["runs"]) + 1
	np["best_wins"] = maxi(int(np["best_wins"]), wins)
	np["total_wins"] = int(np["total_wins"]) + wins
	np["foes_beaten"] = int(np["foes_beaten"]) + maxi(0, _int(summary.get("foes_beaten", 0)))
	np["bosses_beaten"] = int(np["bosses_beaten"]) + bosses
	for k in ["famous_beaten", "famous_allied"]:
		var m: Dictionary = np[k]
		var lst: Variant = summary.get(k, [])
		if lst is Array:
			for id in lst:
				m[str(id)] = int(m.get(str(id), 0)) + 1
	var t := _int(summary.get("t", 0))
	if t <= 0:
		t = int(Time.get_unix_time_from_system())
	var bc: Variant = summary.get("best_card", {})
	var entry := {
		"t": t, "seed": maxi(0, _int(summary.get("seed", 0))), "wins": wins, "bosses": bosses,
		"cause": str(summary.get("cause", "DEATH")) if str(summary.get("cause", "DEATH")) in RogueRules.CAUSES else "DEATH",
		"points": gained,
		"best_card": { "id": str(bc.get("id", "")), "title": str(bc.get("title", "")), "rarity": str(bc.get("rarity", "")) }
			if bc is Dictionary else { "id": "", "title": "", "rarity": "" },
	}
	var hist: Array = np["history"]
	hist.push_front(entry)
	while hist.size() > HISTORY_MAX:
		hist.pop_back()
	np["updated"] = t
	np["in_progress"] = {}   # 這一局（或之前沒結算的那一局）已經結算
	summary["points_gained"] = gained
	summary["points_total"] = int(np["points_total"])
	summary["new_best"] = new_best
	summary["points_cap"] = cap   # 結算畫面的「累計 n / 上限」讀這個（審查：不寫死 60）
	return np
