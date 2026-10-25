class_name RogueFoes
extends RefCounted
## 江湖試煉的對手生成（ROGUE_PLAN §3.7）【設計提案・非原作】。
## 目標戰力 = 難度(回合) ×（一半看回合曲線、一半看我方戰力）×（首領回合 ×1.15）；
## 從 data/rogue_foes.json 依回合篩候選、擲人數與人選，再用 RoguePower.scale_to 縮放到各自的份額。

const SHARES := { 1: [1.0], 2: [0.6, 0.4], 3: [0.5, 0.25, 0.25] }
const BOSS_SHARES := { 1: [1.0], 2: [0.7, 0.3], 3: [0.6, 0.2, 0.2] }   # 首領至少占 60%（§3.7.2）
const MAX_TRIES := 8
const S_MIN := 0.5
const S_MAX := 2.5
const ACCEPT_TOL := 0.08     # 縮放後與份額差 8% 以內就收（技能、屬性取整數會讓戰力跳一小格）
## 候選的「合適層級」：回合越後面越偏好高 tier（只影響權重，實際強度由縮放決定）
const TIER_PER_ROUNDS := 3.0

## §3.7.1：target(r) = diff(r) × ((1 − blend) × base(r) + blend × my_power) × (首領 ? boss_mult : 1)
static func target(run: RogueRun, my_power: float, r: Dictionary) -> float:
	var rnd := maxi(1, run.round)
	var p0 := float(r.get("p0", 0.0))
	if p0 <= 0.0:
		p0 = my_power if my_power > 0.0 else 1.0
	var base := p0 * float(r.get("p0_mult", 0.9)) * pow(float(r.get("growth", 1.16)), rnd - 1)
	var diff := minf(float(r.get("diff_max", 1.2)), float(r.get("diff_start", 0.8)) + float(r.get("diff_step", 0.04)) * (rnd - 1))
	var blend := clampf(float(r.get("blend", 0.5)), 0.0, 1.0)
	var t := diff * ((1.0 - blend) * base + blend * maxf(0.0, my_power))
	if RogueRules.is_boss_round(rnd, r):
		t *= float(r.get("boss_mult", 1.15))
	return t

## 一場的準備（主機 RogueSystem.fight 與 balance_sim 共用）：以玩家自己的戰鬥規格為戰力參考（RoguePower.set_reference），
## 算我方戰力（玩家＋隊友；隊友依玩家戰力 × 份額縮放）→ 目標 → 對手組合。回 { ally_specs, my_unit, my_power, target, gen }
static func prepare_fight(run: RogueRun, my_spec: Dictionary, tables: Dictionary, r: Dictionary) -> Dictionary:
	RoguePower.set_reference(my_spec)
	var rr := r.duplicate(true)
	rr["p0"] = RoguePower.reference_power(tables, renown_points(run, rr))   # 參考新角色「對你」的戰力（含江湖名聲）
	var my_unit := RoguePower.unit_power(my_spec, tables)
	var ally_specs: Array = []
	for a in run.alive_allies():
		var sp := ally_spec(a, my_unit, tables)
		if not sp.is_empty():
			ally_specs.append(sp)
	# 隊友的戰力打折計（rogue_rules.ally_weight；校準值）：對手專挑氣最少的打，隊友多半先倒，實際貢獻小於自己的 P。
	# 整合者校準為 0：對手只依玩家本人生成，隊友是選卡換來的純加成（ROGUE_PLAN §12）
	var my_power := my_unit + float(rr.get("ally_weight", 1.0)) * RoguePower.side_power(ally_specs, tables)
	var tgt := target(run, my_power, rr)
	var gen := generate(run, tgt, tables, run.rng_for("foes"), rr)
	RoguePower.clear_reference()
	return { "ally_specs": ally_specs, "my_unit": my_unit, "my_power": my_power, "target": tgt, "gen": gen }

## 江湖名聲（0.7.x 試煉審查【設計提案】）：開局的永久點數 × renown_share × 淡出（第 1 回合 1、每回合少 1/renown_fade，
## 到 0 為止；四捨五入）加到參考新角色。點數多的人前幾回合不會變成走過場，好處留到後面的首領與硬仗
static func renown_points(run: RogueRun, r: Dictionary) -> int:
	var pts := maxi(0, run.alloc_points - CharacterFactory.FREE_POINTS)
	var fade := maxi(1, int(r.get("renown_fade", 10)))
	var w := clampf(1.0 - float(maxi(1, run.round) - 1) / fade, 0.0, 1.0)
	return roundi(pts * clampf(float(r.get("renown_share", 0.0)), 0.0, 1.0) * w)

## 一組對手的有效戰力（Σ 戰力 × 各自的 power_adj）
static func team_power(specs: Array, tables: Dictionary, _r: Dictionary = {}) -> float:
	var total := 0.0
	for s in specs:
		if s is Dictionary:
			total += RoguePower.unit_power(s, tables) * adj_of(s)
	return total

## rogue_foes.power_adj（0.7.x 試煉審查：同戰力分數的首領實際難度差很多——小龍女、李莫愁九成勝、丘處機四成）：
## 有效戰力 = 戰力分數 × power_adj；縮放時就縮到「份額 ÷ power_adj」。由 balance_sim 的 rogue_boss_spread 校準
static func adj_of(spec: Dictionary) -> float:
	return clampf(float(spec.get("rg_adj", 1.0)), 0.5, 2.0)

## 回 { specs（side 1 的完整戰鬥者規格）, power（有效戰力）, boss_id, boss_name, foes: [rogue_foes 列 id] }
static func generate(run: RogueRun, target_power: float, tables: Dictionary, rng: RandomNumberGenerator, rules_in: Dictionary = {}) -> Dictionary:
	var r := rules_in if not rules_in.is_empty() else RogueRules.rules(tables)
	var rows: Dictionary = tables.get("rogue_foes", {})
	var out := { "specs": [], "power": 0.0, "boss_id": "", "boss_name": "", "foes": [] }
	# rogue_debug foes：固定的對手列（不縮放；只用一次）
	if not run.debug_foes.is_empty():
		var picks: Array = []
		for fid in run.debug_foes:
			if rows.has(str(fid)):
				picks.append(rows[str(fid)])
		run.debug_foes = []
		if not picks.is_empty():
			var specs: Array = []
			for row in picks:
				var sp := foe_spec(row, tables)
				if sp.is_empty():
					continue
				specs.append(sp)
				(out["foes"] as Array).append(str(row["id"]))
				if out["boss_id"] == "" and bool(row.get("boss", false)):
					out["boss_id"] = str(row["id"])
					out["boss_name"] = str(sp.get("name", ""))
			_finish(out, specs, tables, r)
			return out
	var rnd := maxi(1, run.round)
	var boss := RogueRules.is_boss_round(rnd, r)
	var normal := _candidates(rows, rnd, false, [])
	var specs2: Array = []
	if boss:
		# 這局招募過的隊友（不論生死）不會變成首領（審查：同一人同時出現在敵我兩邊）
		var bosses := _candidates(rows, rnd, true, run.bosses_seen).filter(func(b): return not is_ally_person(b, run))
		if bosses.is_empty():
			bosses = _candidates(rows, rnd, true, []).filter(func(b): return not is_ally_person(b, run))   # 首領都見過了：同一局才開始重複
		if bosses.is_empty():
			bosses = _candidates(rows, rnd, true, [])
		if not bosses.is_empty():
			# 首領：偏好縮放得到的人選（未縮放戰力最接近份額者機率高）；隨從縮放不到就少帶一位，再不行換首領（最多 MAX_TRIES 次）
			var best: Dictionary = {}
			var best_err := INF
			for attempt in MAX_TRIES:
				var brow: Dictionary = _weighted(bosses, rnd, rng, target_power * 0.8, tables)
				var minions: Array = []
				for mid in brow.get("minions", []):
					if rows.has(str(mid)):
						minions.append(rows[str(mid)])
				var m := rng.randi_range(0, mini(2, minions.size()))
				var team: Array = [brow]
				for i in m:
					team.append(minions[rng.randi_range(0, minions.size() - 1)])
				while not team.is_empty():
					var res := _scale_team(team, BOSS_SHARES[team.size()], target_power, tables, rng, [], true, rnd)
					var err := absf(team_power(res["specs"], tables, r) - target_power) / maxf(0.001, target_power)
					if err < best_err and not (res["specs"] as Array).is_empty():
						best_err = err
						best = { "res": res, "row": brow }
					if bool(res["ok"]) or team.size() == 1:
						break
					team.pop_back()
				if best_err <= ACCEPT_TOL:
					break
			var bres: Dictionary = best.get("res", { "specs": [], "ids": [] })
			specs2 = bres["specs"]
			out["boss_id"] = str(best.get("row", {}).get("id", ""))
			if not specs2.is_empty():
				out["boss_name"] = str(specs2[0].get("name", ""))
			out["foes"] = bres["ids"]
			_finish(out, specs2, tables, r)
			return out
	if normal.is_empty():
		_finish(out, specs2, tables, r)
		return out
	var n := 1
	if rnd >= 5:
		n = rng.randi_range(1, 3)
	elif rnd >= 3:
		n = rng.randi_range(1, 2)
	n = mini(n, Encounter.MAX_MONSTERS)
	while n >= 1:
		var team2: Array = []
		for i in n:
			team2.append(_weighted(normal, rnd, rng))
		var res2 := _scale_team(team2, SHARES[n], target_power, tables, rng, normal, n == 1, rnd)
		if bool(res2["ok"]) or n == 1:
			out["foes"] = res2["ids"]
			_finish(out, res2["specs"], tables, r)
			return out
		n -= 1
	_finish(out, specs2, tables, r)
	return out

## 對手列（首領）是不是這局招募過的隊友本人（同 NPC，或同怪物列）
static func is_ally_person(row: Dictionary, run: RogueRun) -> bool:
	var npc := str(row.get("npc", ""))
	var mon := str(row.get("monster", ""))
	for a in run.allies:
		if (npc != "" and str(a.get("npc", "")) == npc) or (mon != "" and str(a.get("monster", "")) == mon):
			return true
	return false

## 隊友卡（npc／monster）是不是這局見過的首領本人（RogueDraw.eligible 用）
static func same_person_seen(npc: String, monster: String, boss_ids: Array, tables: Dictionary) -> bool:
	var rows: Dictionary = tables.get("rogue_foes", {})
	for id in boss_ids:
		var row: Dictionary = rows.get(str(id), {})
		if row.is_empty():
			continue
		if (npc != "" and str(row.get("npc", "")) == npc) or (monster != "" and str(row.get("monster", "")) == monster):
			return true
	return false

## 依份額縮放一隊；縮放不到（係數超出 [0.5, 2.5]）的人換人，最多 MAX_TRIES 次。pool 空＝不換人（首領隊）。
## must：失敗也回最接近的結果
static func _scale_team(team: Array, shares: Array, target_power: float, tables: Dictionary, rng: RandomNumberGenerator,
		pool: Array, must: bool, rnd: int = 0) -> Dictionary:
	var specs: Array = []
	var ids: Array = []
	var all_ok := true
	var rnd_guess := 1
	for i in team.size():
		var row: Dictionary = team[i]
		var part := target_power * float(shares[i])
		var best: Dictionary = {}
		var best_row := row
		for t in MAX_TRIES:
			var sp := foe_spec(row, tables, rnd)
			if not sp.is_empty():
				var adj := adj_of(sp)
				var res := RoguePower.scale_to(sp, part / adj, tables, S_MIN, S_MAX)
				var err := absf(float(res["power"]) * adj - part) / maxf(0.001, part)
				if best.is_empty() or err < float(best["err"]):
					best = { "spec": res["spec"], "err": err }
					best_row = row
				if err <= ACCEPT_TOL:
					break
			if pool.is_empty():
				break
			row = _weighted(pool, rnd_guess, rng, part, tables)
		if best.is_empty():
			all_ok = false
			continue
		if float(best["err"]) > ACCEPT_TOL:
			all_ok = false
		var spec: Dictionary = best["spec"]
		spec["rg_foe"] = str(best_row["id"])
		specs.append(spec)
		ids.append(str(best_row["id"]))
	return { "specs": specs, "ids": ids, "ok": all_ok and not specs.is_empty() }

static func _candidates(rows: Dictionary, rnd: int, boss: bool, exclude: Array) -> Array:
	var ids: Array = rows.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		var row: Dictionary = rows[id]
		if bool(row.get("boss", false)) != boss or exclude.has(str(id)):
			continue
		if int(row.get("min_round", 1)) > rnd:
			continue
		var mx := int(row.get("max_round", 0))
		if mx > 0 and rnd > mx:
			continue
		if int(row.get("weight", 1)) <= 0:
			continue
		out.append(row)
	return out

## 依 weight × 層級親和度擲一列。part > 0 時（換人）改成偏好「未縮放戰力最接近份額」的列
static func _weighted(cands: Array, rnd: int, rng: RandomNumberGenerator, part: float = 0.0, tables: Dictionary = {}) -> Dictionary:
	var ideal := clampf(1.0 + (rnd - 1) / TIER_PER_ROUNDS, 1.0, 6.0)
	var weights: Array = []
	for c in cands:
		var w := float(c.get("weight", 1))
		if part > 0.0 and not tables.is_empty():
			var raw := RoguePower.unit_power(foe_spec(c, tables), tables)
			var ratio := raw / maxf(0.001, part)
			if ratio < 1.0:
				ratio = 1.0 / maxf(0.001, ratio)
			w = w / (ratio * ratio)
		else:
			w = w / (1.0 + absf(float(c.get("tier", 1)) - ideal))
		weights.append(maxi(1, roundi(w * 100.0)))
	var i := RogueRules.pick_weighted(weights, rng)
	return cands[maxi(0, i)]

## 一列對手的未縮放規格：Encounter.monster_spec；有 npc 時名字、簡稱、立繪用 NPC（同 BattleSystem._npc_unit_spec）
static func foe_spec(row: Dictionary, tables: Dictionary, rnd: int = 0) -> Dictionary:
	var spec := Encounter.monster_spec(str(row.get("monster", "")), tables)
	if spec.is_empty():
		return {}
	var npc := str(row.get("npc", ""))
	var nrow: Dictionary = tables.get("npcs", {}).get(npc, {}) if npc != "" else {}
	if not nrow.is_empty():
		spec["ref"] = npc
		spec["npc"] = npc
		var nm := str(nrow.get("name", npc))
		spec["name"] = nm
		spec["short"] = str(nrow.get("short", nm.substr(0, 2) if nm.length() > 2 else nm))
	if str(row.get("name", "")) != "":
		spec["name"] = str(row["name"])
	apply_override(spec, row.get("override", {}))
	spec["side"] = 1
	spec["peer"] = 0
	spec["rg_foe"] = str(row.get("id", ""))
	if bool(row.get("boss", false)):
		spec["rg_boss"] = true
	var adj := row_adj(row, rnd)
	if adj != 1.0:
		spec["rg_adj"] = adj
	return spec

## power_adj：數字（所有回合）或 { "起始回合": 倍率 }（取起始回合 ≤ 本回合的最後一個；rnd 0 = 不分回合時取最早的）
static func row_adj(row: Dictionary, rnd: int) -> float:
	var v: Variant = row.get("power_adj", 1.0)
	if v is Dictionary:
		var best_from := -1
		var out := 1.0
		for k in v:
			var f := int(str(k))
			if (rnd <= 0 or f <= rnd) and (best_from < 0 or (f > best_from if rnd > 0 else f < best_from)):
				best_from = f
				out = float(v[k])
		return out
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	return 1.0

## 隊友的戰鬥者規格（ROGUE_PLAN §4.1）：交給 WP-ALLY 的 RogueAlly.spec_for；隊友卡帶 override（MUD 數值列太強）時，
## 先拿不縮放的規格（share 0）、套 override、再縮放到「我方玩家戰力 × share」，氣依 qi_pct。
## ROGUE_PLAN 缺漏：RogueAlly.spec_for 不認得 override，所以由這裡包一層（RogueSystem 與 balance_sim 共用）
const ALLY_SCRIPT := "res://core/rogue/rogue_ally.gd"
static func ally_spec(ally: Dictionary, my_unit_power: float, tables: Dictionary) -> Dictionary:
	var sc: Script = load(ALLY_SCRIPT) as Script if ResourceLoader.exists(ALLY_SCRIPT) else null
	var ov: Variant = ally.get("override", {})
	var has_ov := ov is Dictionary and not (ov as Dictionary).is_empty()
	if sc != null and not has_ov:
		var sp0: Variant = sc.call("spec_for", ally, my_unit_power, tables)
		return sp0 if sp0 is Dictionary else {}
	var base := ally.duplicate(true)
	base["share"] = 0.0
	base["qi_pct"] = 1.0
	var spec: Dictionary = {}
	if sc != null:
		var sp1: Variant = sc.call("spec_for", base, 0.0, tables)
		spec = sp1 if sp1 is Dictionary else {}
	else:
		spec = foe_spec({ "id": "", "monster": str(ally.get("monster", "")), "npc": str(ally.get("npc", "")) }, tables)
		spec.erase("rg_foe")
		spec.erase("rg_boss")
		spec["kind"] = "ALLY"
		spec["ai"] = "ally"
		spec["rg_ally"] = str(ally.get("slot", ""))
	if spec.is_empty():
		return {}
	apply_override(spec, ov)
	spec["side"] = 0
	spec["peer"] = 0
	var share := float(ally.get("share", 0.0))
	if my_unit_power > 0.0 and share > 0.0:
		spec = RoguePower.scale_to(spec, my_unit_power * share, tables)["spec"]
	var qmax := maxi(1, int(spec.get("qi_max", 1)))
	spec["qi_max"] = qmax
	spec["qi"] = maxi(1, roundi(qmax * clampf(float(ally.get("qi_pct", 1.0)), 0.0, 1.0)))
	spec["neili"] = int(spec.get("neili_max", 0))
	return spec

## rogue_foes.override（ROGUE_PLAN 缺漏的補充）：MUD 數值列是「不可單挑」的門派首腦（丁春秋、血刀老祖 qi 3 萬）時，
## 縮放器（0.5–2.5）拉不回名人級距；試煉改用 override 的數值（立繪與名字仍是原列）。
## 鍵：qi、neili（同時設上限）、attrs（逐項覆寫）、skills（整組取代）、armor_power、weapon_atk、effective_inner
const OVERRIDE_KEYS := ["qi", "neili", "attrs", "skills", "armor_power", "weapon_atk", "effective_inner"]
static func apply_override(spec: Dictionary, ov: Variant) -> void:
	if not (ov is Dictionary) or (ov as Dictionary).is_empty():
		return
	var o: Dictionary = ov
	if o.has("qi"):
		spec["qi"] = maxi(1, int(o["qi"]))
		spec["qi_max"] = spec["qi"]
	if o.has("neili"):
		spec["neili"] = maxi(0, int(o["neili"]))
		spec["neili_max"] = spec["neili"]
	if o.get("attrs") is Dictionary:
		var a: Dictionary = spec.get("attrs", {})
		for k in o["attrs"]:
			a[str(k)] = int(o["attrs"][k])
		spec["attrs"] = a
	if o.get("skills") is Dictionary:
		var sk := {}
		for k in o["skills"]:
			if int(o["skills"][k]) >= 1:
				sk[str(k)] = int(o["skills"][k])
		spec["skills"] = sk
	if o.has("armor_power"):
		spec["armor_power"] = maxi(0, int(o["armor_power"]))
	if o.has("weapon_atk") and spec.get("weapon") is Dictionary:
		spec["weapon"]["atk"] = maxi(0, int(o["weapon_atk"]))
	if o.has("effective_inner"):
		spec["effective_inner"] = maxi(0, int(o["effective_inner"]))

## 同名多隻 → 甲乙丙（同 Encounter.monster_specs）；有效戰力（team_power）
static func _finish(out: Dictionary, specs: Array, tables: Dictionary, r: Dictionary = {}) -> void:
	var counts := {}
	for sp in specs:
		counts[str(sp.get("name", ""))] = int(counts.get(str(sp.get("name", "")), 0)) + 1
	var seen := {}
	for sp in specs:
		var nm := str(sp.get("name", ""))
		if int(counts[nm]) <= 1:
			continue
		var i := int(seen.get(nm, 0))
		seen[nm] = i + 1
		var suffix: String = Encounter.DUP_SUFFIXES[i] if i < Encounter.DUP_SUFFIXES.size() else str(i + 1)
		var short := str(sp.get("short", ""))
		if short == "":
			short = nm
		sp["name"] = nm + suffix
		sp["short"] = short.right(1) + suffix
	out["specs"] = specs
	out["power"] = team_power(specs, tables, r)
