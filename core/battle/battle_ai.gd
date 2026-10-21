class_name BattleAI
extends RefCounted
## 怪物 AI（M1_PLAN 4.9）。一律 10 成出招。
## 怪物只用 arts[0]；玩家方（balance_sim 的自動玩家）用 arts 中威力最高的已解鎖招式。

const AI_TENTHS := 10
const POISON_CHANCE := 0.30      # 有 POISON 武功的怪 30% 機率用毒（M3A_PLAN 5.5）【設計提案】

static func choose(b: Battle, u: BattleUnit, tables: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	# 氣 < 10% 才想逃（原為 30%：野兔幾乎每場都在被打死前一刻逃走，新手打不到獎勵）【設計提案】
	if u.ai_kind() == "coward" and u.qi * 10 < u.qi_max():
		var c := _coward_escape(b, u)
		if not c.is_empty():
			return c
	return _melee_basic(b, u, tables, rng)

static func _melee_basic(b: Battle, u: BattleUnit, tables: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var enemies := _enemies(b, u)
	if enemies.is_empty():
		return { "cmd": "DEFEND" }
	if not u.is_player() and not u.cmd_arts("POISON").is_empty():
		var pc := _poison_cmd(b, u, enemies, tables, rng)
		if not pc.is_empty():
			return pc
	var moves := usable_moves(u, tables, b)      # 依威力由高到低
	var max_range := 1
	for m in moves:
		max_range = maxi(max_range, int(m.move.get("range", 1)))
	# 攻擊範圍內（相鄰；有遠程招式時含其射程）氣最少的敵人，同氣比 uid
	var in_reach: Array = enemies.filter(func(e): return BattleGrid.manhattan(u.pos, e.pos) <= max_range)
	if not in_reach.is_empty():
		in_reach.sort_custom(func(a, b2):
			if a.qi != b2.qi:
				return a.qi < b2.qi
			return a.uid < b2.uid)
		for t in in_reach:
			var d := BattleGrid.manhattan(u.pos, t.pos)
			for m in moves:
				var aoe := str(m.move.get("aoe", "SINGLE"))
				if BattleAoe.is_aoe(aoe):
					var center: Vector2i = u.pos if aoe == "AROUND" else t.pos
					if BattleAoe.check(b, u, m.move, center) == "" 							and BattleAoe.enemies_in(b, u, BattleAoe.cells(aoe, u.pos, center, int(m.move.get("range", 1)))).has(t):
						return { "cmd": "ART", "art": m.art, "move": str(m.move.id), "power_tenths": AI_TENTHS,
							"target": [center.x, center.y] }
				elif int(m.move.get("range", 1)) >= d:
					return { "cmd": "ART", "art": m.art, "move": str(m.move.id), "power_tenths": AI_TENTHS,
						"target": [t.pos.x, t.pos.y] }
			if d <= 1:
				return { "cmd": "ATTACK", "target": [t.pos.x, t.pos.y] }
	# 移動到離最近敵人最近的可達格（同距離選 x 再 y 較小）
	var goals: Array[Vector2i] = []
	for e in enemies:
		goals.append(e.pos)
	var dest := _best_cell_toward(b, u, goals)
	if dest == Vector2i(-1, -1):
		return { "cmd": "DEFEND" }
	return { "cmd": "MOVE", "target": [dest.x, dest.y] }

static func _coward_escape(b: Battle, u: BattleUnit) -> Dictionary:
	if b.grid.is_escape(u.pos):
		# 站上逃跑格後要先喘一口氣（浪費一次行動）才逃得掉，玩家有機會追上補刀【設計提案】
		if u.escape_ready:
			return { "cmd": "FLEE" }
		u.escape_ready = true
		return { "cmd": "DEFEND" }
	u.escape_ready = false
	if b.grid.escape.is_empty():
		return {}
	var dest := _best_cell_toward(b, u, b.grid.escape)
	if dest == Vector2i(-1, -1):
		return {}
	return { "cmd": "MOVE", "target": [dest.x, dest.y] }

## 可達格中離 goals 最近者；必須比目前位置更近，否則回 (-1,-1)（視為無法移動）
static func _best_cell_toward(b: Battle, u: BattleUnit, goals: Array[Vector2i]) -> Vector2i:
	var cur := _dist_to(u.pos, goals)
	var best := Vector2i(-1, -1)
	var best_d := cur
	for p in b.grid.reachable(u.pos, BattleFormulas.move_range(u)):
		var d := _dist_to(p, goals)
		if d < best_d or (d == best_d and best != Vector2i(-1, -1) and (p.x < best.x or (p.x == best.x and p.y < best.y))):
			best = p
			best_d = d
	return best

static func _dist_to(p: Vector2i, goals: Array[Vector2i]) -> int:
	var d := 1 << 30
	for g in goals:
		d = mini(d, BattleGrid.manhattan(p, g))
	return d

static func _enemies(b: Battle, u: BattleUnit) -> Array:
	return b.units.filter(func(e): return e.side != u.side and e.is_active())

## 怪物用毒：射程內有敵人、內力夠時 30% 機率（只在有 POISON 武功時才擲骰，不影響 M1 回放）
static func _poison_cmd(b: Battle, u: BattleUnit, enemies: Array, tables: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var arow := BattleCmds.best_cmd_art(u, "POISON", tables)
	if arow.is_empty():
		return {}
	var m := BattleCmds.first_move(arow)
	if u.neili < int(m.get("cost_inner", 0)):
		return {}
	var r := int(m.get("range", 1))
	var cands: Array = enemies.filter(func(e): return BattleGrid.manhattan(u.pos, e.pos) <= r and not e.statuses.has("poison"))
	if cands.is_empty():
		return {}
	if rng == null or rng.randf() >= POISON_CHANCE:
		return {}
	cands.sort_custom(func(a, c): return a.uid < c.uid)
	var t: BattleUnit = cands[0]
	return { "cmd": "POISON", "art": str(arow.id), "target": [t.pos.x, t.pos.y] }

## [{ art, move }]，依威力高→低（同威力保持資料順序）；只含現在付得起、兵器相符的已解鎖招式（M3a：含範圍招式）
## b 有給時，合體武功要夥伴同場（ComboRules.usable）
static func usable_moves(u: BattleUnit, tables: Dictionary, b: Battle = null) -> Array:
	var art_ids: Array = u.arts()
	if not u.is_player() and not art_ids.is_empty():
		art_ids = [art_ids[0]]
	var out: Array = []
	for a in art_ids:
		var row := BattleRules.art_row_for(u, str(a), tables)
		if row.is_empty():
			continue
		var cat := str(row.get("category", "FIST"))
		if cat != "FIST" and u.weapon_type() != cat:
			continue
		if b != null and not ComboRules.usable(b, u, row):
			continue
		var lv := u.skill(str(a))
		for m in row.get("moves", []):
			if int(m.get("unlock_level", 1)) > lv:
				continue
			if u.neili < BattleFormulas.inner_cost(m, AI_TENTHS) or u.jing < int(m.get("cost_jing", 0)):
				continue
			out.append({ "art": str(a), "move": m, "i": out.size() })
	out.sort_custom(func(x, y):
		var px := float(x.move.get("power", 0))
		var py := float(y.move.get("power", 0))
		if px != py:
			return px > py
		return x.i < y.i)
	return out
