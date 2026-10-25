class_name BattleAI
extends RefCounted
## 怪物 AI（M1_PLAN 4.9）。一律 10 成出招。
## 怪物只用 arts[0]；玩家方（balance_sim 的自動玩家）用 arts 中威力最高的已解鎖招式。

const AI_TENTHS := 10
const POISON_CHANCE := 0.30      # 有 POISON 武功的怪 30% 機率用毒（M3A_PLAN 5.5）【設計提案】
const RG_FINISH_PCT := 0.15      # 江湖試煉的對手：搆得到氣 < 15% 的人先補刀（分散出手的例外）【設計提案・非原作】

static func choose(b: Battle, u: BattleUnit, tables: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if u.ai_kind() == "ally":
		return _ally_basic(b, u, tables, rng)   # ROGUE WP-ALLY：江湖試煉的 AI 隊友（ROGUE_PLAN §4.3）
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
		if _rg_spread(b, u):
			# 江湖試煉的對手分散出手（ROGUE 審查：玩家倒下＝這一局結束，對手專打玩家時隊友常常還滿血）：
			# 先打「氣剩下比例最高」的，同比例比 uid；但搆得到氣不到 RG_FINISH_PCT 的人時先補刀（比例最低的先），
			# 倒下要有看得見的最後一擊，也不能靠站在隊友旁邊一直不被打（第二輪審查）【設計提案・非原作】
			in_reach.sort_custom(func(a, b2):
				var fa := float(a.qi) / maxf(1.0, float(a.qi_max()))
				var fb := float(b2.qi) / maxf(1.0, float(b2.qi_max()))
				var la := fa < RG_FINISH_PCT
				var lb := fb < RG_FINISH_PCT
				if la != lb:
					return la
				if not is_equal_approx(fa, fb):
					return fa < fb if la else fa > fb
				return a.uid < b2.uid)
		else:
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

## 江湖試煉（opts.kind ROGUE）的對手（side 1）分散出手；opts.rg_spread 可明確開關（balance_sim 校準用）
static func _rg_spread(b: Battle, u: BattleUnit) -> bool:
	if b == null or u.side != 1:
		return false
	return bool(b.opts.get("rg_spread", str(b.opts.get("kind", "")) == "ROGUE"))

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
	if not u.is_player() and u.ai_kind() != "ally" and not art_ids.is_empty():   # ROGUE WP-ALLY：隊友同玩家用全部武功
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

# ==== ROGUE WP-ALLY ====
## 江湖試煉的 AI 隊友（ROGUE_PLAN §4.3）【設計提案・非原作】：同 _melee_basic，差異——
## (1) 招式用 arts 全部（usable_moves 對 ai ally 不只取 arts[0]）；(2) 攻擊範圍內的目標：氣最少 → 離最近的我方玩家單位最近 → uid；
## (3) 不逃；特殊指令只用毒（_poison_cmd）；(4) 打不到人時往「離我方玩家最近的敵人」移動（護著主角）。
static func _ally_basic(b: Battle, u: BattleUnit, tables: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var enemies := _enemies(b, u)
	if enemies.is_empty():
		return { "cmd": "DEFEND" }
	if not u.cmd_arts("POISON").is_empty():
		var pc := _poison_cmd(b, u, enemies, tables, rng)
		if not pc.is_empty():
			return pc
	var players: Array[Vector2i] = []
	for o in b.units:
		if o.side == u.side and o.is_player() and o.is_active():
			players.append(o.pos)
	var moves := usable_moves(u, tables, b)
	var max_range := 1
	for m in moves:
		max_range = maxi(max_range, int(m.move.get("range", 1)))
	var in_reach: Array = enemies.filter(func(e): return BattleGrid.manhattan(u.pos, e.pos) <= max_range)
	if not in_reach.is_empty():
		in_reach.sort_custom(func(a, c):
			if a.qi != c.qi:
				return a.qi < c.qi
			var da := _dist_to(a.pos, players) if not players.is_empty() else 0
			var dc := _dist_to(c.pos, players) if not players.is_empty() else 0
			if da != dc:
				return da < dc
			return a.uid < c.uid)
		for t in in_reach:
			var d := BattleGrid.manhattan(u.pos, t.pos)
			for m in moves:
				var aoe := str(m.move.get("aoe", "SINGLE"))
				if BattleAoe.is_aoe(aoe):
					var center: Vector2i = u.pos if aoe == "AROUND" else t.pos
					if BattleAoe.check(b, u, m.move, center) == "" \
							and BattleAoe.enemies_in(b, u, BattleAoe.cells(aoe, u.pos, center, int(m.move.get("range", 1)))).has(t):
						return { "cmd": "ART", "art": m.art, "move": str(m.move.id), "power_tenths": AI_TENTHS,
							"target": [center.x, center.y] }
				elif int(m.move.get("range", 1)) >= d:
					return { "cmd": "ART", "art": m.art, "move": str(m.move.id), "power_tenths": AI_TENTHS,
						"target": [t.pos.x, t.pos.y] }
			if d <= 1:
				return { "cmd": "ATTACK", "target": [t.pos.x, t.pos.y] }
	var goals: Array[Vector2i] = []
	if players.is_empty():
		for e in enemies:
			goals.append(e.pos)
	else:
		var best: BattleUnit = null
		var best_d := 1 << 30
		for e in enemies:
			var de := _dist_to(e.pos, players)
			if de < best_d or (de == best_d and best != null and e.uid < best.uid):
				best = e
				best_d = de
		goals.append(best.pos)
	var dest := _best_cell_toward(b, u, goals)
	if dest == Vector2i(-1, -1) and goals.size() == 1 and enemies.size() > 1:
		# 擋住了：退回「最近的任何敵人」
		var all: Array[Vector2i] = []
		for e in enemies:
			all.append(e.pos)
		dest = _best_cell_toward(b, u, all)
	if dest == Vector2i(-1, -1):
		return { "cmd": "DEFEND" }
	return { "cmd": "MOVE", "target": [dest.x, dest.y] }
