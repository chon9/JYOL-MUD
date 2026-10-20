class_name BattleRewards
extends RefCounted
## 戰鬥獎勵（M1_PLAN 3.4.7、4.8；GDD 2.4）。
## 4.8 的比例需要玩家實戰：讀 spec.combat_xp（M1_PLAN 3.3，Character.to_combatant() 會帶上；缺省 0）。

## 回傳 { player_uid: { combat_xp, learn_points, money, items:[{id,n,rarity}], morality, killing_intent, kills } }
## M3C_PLAN §6.6：ctx（可省；LootSystem.reward_ctx 給）＝ { "rules": { divine_source, manuals }, "blocked": [已有持有者的神兵],
## "force": [強制掉落的物品 id], "drop_pct": int（伺服器選項 loot_drop_pct，預設 100） }。
## 怪物列有 loot_table 時，既有 drops 照舊先擲，再擲掉落表；沒有 loot_table 的怪物結果與 M3c 以前相同（rng 用量也相同）。
## ctx 會被就地加上 "used_force": [這次真的用掉的強制掉落]、"divine_dropped": [這次掉出的神兵]（LootSystem 用）。
## M3c 審查（頭目鎖）：掉落表有 lockout_shichen 時，同一個角色（最後一擊者）在鎖定期間只拿 guaranteed、不擲群組；
## ctx.locked = { char_id: [掉落表 id] }（LootSystem.reward_ctx 給）；這次真的擲了的記進 ctx.lockout_rolled = [[char_id, 表 id]]。
static func compute(b: Battle, tables: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> Dictionary:
	var out := {}
	if b.result != Battle.Result.VICTORY:
		return out
	# M2：沒有怪物的戰鬥（PvP）不給任何獎勵（M2_PLAN 4.6.3、5.2「PvP 獎勵：無」）
	if not b.units.any(func(u): return not u.is_player()):
		return out
	var survivors: Array = b.units.filter(func(u): return u.side == 0 and u.is_player() and u.is_active())
	if survivors.is_empty():
		return out
	survivors.sort_custom(func(a, c): return a.uid < c.uid)
	var share := 1.0 / sqrt(float(survivors.size()))
	for s in survivors:
		out[s.uid] = { "combat_xp": 0, "learn_points": 0, "money": 0, "items": [], "morality": 0,
			"killing_intent": 0, "kills": s.kills.duplicate() }
	var monsters: Array = b.units.filter(func(u): return u.side == 1 and not u.is_player() and u.is_dead())
	monsters.sort_custom(func(a, c): return a.uid < c.uid)
	var mt: Dictionary = tables.get("monsters", {})
	for m in monsters:
		var mid := str(m.spec.get("monster_row", m.spec.get("ref", "")))
		var row: Dictionary = mt.get(mid, {})
		if row.is_empty() or bool(row.get("no_rewards", false)):
			continue
		# 實戰、學點：每位存活未逃的玩家各自計算
		for s in survivors:
			var r: Dictionary = out[s.uid]
			r.combat_xp += xp_for(row, int(s.spec.get("combat_xp", 0)), share)
			r.learn_points += lp_for(row, int(s.spec.get("combat_xp", 0)), share)
		# 掉落、銀兩、善惡、殺氣：給最後一擊者；最後一擊者不在存活名單 → uid 最小的存活玩家
		var receiver: BattleUnit = null
		for s in survivors:
			if s.uid == m.killed_by:
				receiver = s
		var killer_alive := receiver != null
		if receiver == null:
			receiver = survivors[0]
		var items: Array = []
		for d in row.get("drops", []):
			var chance := float(d.get("chance", 0.0))
			if rng.randf() < chance:
				var lo := int(d.get("min", 1))
				var hi := int(d.get("max", lo))
				var n := rng.randi_range(mini(lo, hi), maxi(lo, hi))
				if n > 0:
					items.append({ "id": str(d.get("item", "")), "n": n })
		var money := 0
		var mrow: Variant = row.get("money", {})
		if mrow is Dictionary and not mrow.is_empty():
			var mlo := int(mrow.get("min", 0))
			var mhi := int(mrow.get("max", mlo))
			money = rng.randi_range(mini(mlo, mhi), maxi(mlo, mhi))
		var rr: Dictionary = out[receiver.uid]
		rr.money += money
		var lt_id := str(row.get("loot_table", ""))
		if lt_id != "":
			var lt: Dictionary = tables.get("loot_tables", {}).get(lt_id, {})
			var who := str(receiver.spec.get("ref", ""))
			var locked := is_locked(ctx, who, lt_id)
			if not locked and int(lt.get("lockout_shichen", 0)) > 0:
				var rolled: Array = ctx.get("lockout_rolled", []) if ctx.get("lockout_rolled") is Array else []
				rolled.append([who, lt_id])
				ctx["lockout_rolled"] = rolled
			for it in roll_table(lt, tables, rng, ctx, locked):
				items.append(it)
		for it in items:
			_add_item(rr.items, it.id, it.n, rarity_of(tables, str(it.id)))
		if killer_alive:
			rr.morality += int(row.get("morality_on_kill", 0))
			rr.killing_intent += int(row.get("killing_intent_on_kill", 0))
	return out

static func ratio(monster_ref_xp: int, player_xp: int) -> float:
	return float(monster_ref_xp + 1000) / float(maxi(0, player_xp) + 1000)

static func xp_for(row: Dictionary, player_xp: int, share: float) -> int:
	var base := int(row.get("combat_xp", 0))
	if base <= 0:
		return 0
	var r := clampf(ratio(int(row.get("combat_xp_ref", 0)), player_xp), 0.1, 2.0)
	return maxi(1, roundi(base * r * share))

static func lp_for(row: Dictionary, player_xp: int, share: float) -> int:
	var base := int(row.get("learn_points", 0))
	if base <= 0:
		return 0
	var r := clampf(ratio(int(row.get("combat_xp_ref", 0)), player_xp), 0.2, 3.0)
	return maxi(1, roundi(base * r * share))

static func _add_item(list: Array, id: String, n: int, rarity := "COMMON") -> void:
	for it in list:
		if it.id == id:
			it.n += n
			return
	list.append({ "id": id, "n": n, "rarity": rarity })

# ---------------------------------------------------------------- 掉落表（M3C_PLAN §6.6；WP-LOOT）

const RARITIES := ["COMMON", "FINE", "RARE", "TREASURE", "DIVINE"]

static func rarity_of(tables: Dictionary, item_id: String) -> String:
	var r := str(tables.get("items", {}).get(item_id, {}).get("rarity", "COMMON"))
	return r if RARITIES.has(r) else "COMMON"

static func rarity_rank(r: String) -> int:
	return maxi(0, RARITIES.find(r))

## 擲一張掉落表：guaranteed 全給；每個 groups[i] 擲一次 chance（乘 drop_pct/100，神兵群組除外），中了依權重 w 挑一件。
## - 神兵群組（divine: true）只在 ctx.rules.divine_source == "BOSS_DROP" 時擲；挑到已有持有者的（blocked）→ 這一擲作廢。
## - ctx.rules.manuals == false：秘笈（有 manual 欄）的權重當 0。
## - ctx.rules.later_loot == false（classic_strict；M3c 審查）：src "later"（後期版才有）的物品權重當 0。
## - ctx.force：此表任何群組裡有強制掉落的物品 → 必中該群組並選該物品（一次性：用掉的記進 ctx.used_force）。
## - locked（M3c 審查：頭目鎖）：只給 guaranteed 與強制掉落，群組不擲。
## - 神兵全服鎖（M3c 第三輪審查）：有 lockout_shichen 的表，神兵群組每 lockout_shichen 全服只擲一次（不論誰打、幾個人輪流
##   搶最後一擊）。ctx.divine_locked = [全服還鎖著的表 id]（LootSystem.reward_ctx 給）；這一場真的擲了神兵群組的表記進
##   ctx.divine_rolled = [表 id]（同一場第二隻同表的怪就算鎖定），LootSystem.on_settle 據此上全服鎖。
## 回傳 [{ id, n }]
static func roll_table(lt: Dictionary, tables: Dictionary, rng: RandomNumberGenerator, ctx: Dictionary = {}, locked := false) -> Array:
	var out: Array = []
	if lt.is_empty():
		return out
	var rules: Dictionary = ctx.get("rules", {}) if ctx.get("rules") is Dictionary else {}
	var manuals_on: bool = rules.get("manuals", true) != false
	var later_on: bool = rules.get("later_loot", true) != false
	var divine_on := str(rules.get("divine_source", "NONE")) == "BOSS_DROP"
	var pct := clampf(float(ctx.get("drop_pct", 100)), 0.0, 1000.0) / 100.0
	var items_t: Dictionary = tables.get("items", {})
	for g in lt.get("guaranteed", []):
		if not (g is Dictionary):
			continue
		var lo := int(g.get("min", 1))
		var hi := int(g.get("max", lo))
		var n := rng.randi_range(mini(lo, hi), maxi(lo, hi))
		if n > 0 and items_t.has(str(g.get("item", ""))):
			out.append({ "id": str(g.get("item", "")), "n": n })
	for grp in lt.get("groups", []):
		if not (grp is Dictionary):
			continue
		var divine := bool(grp.get("divine", false))
		if divine and not divine_on:
			continue
		var dv_locked := divine and is_divine_locked(ctx, lt)
		var picks: Array = []
		var total := 0
		for p in grp.get("pick", []):
			if not (p is Dictionary):
				continue
			var iid := str(p.get("item", ""))
			var w := maxi(0, int(p.get("w", 0)))
			if not items_t.has(iid):
				w = 0
			elif not manuals_on and items_t[iid].get("manual") is Dictionary:
				w = 0
			elif not later_on and str(items_t[iid].get("src", "")) == "later":
				w = 0
			picks.append([iid, w])
			total += w
		if total <= 0:
			continue
		var chosen := ""
		var forced := _forced_pick(picks, ctx)
		if forced != "":
			chosen = forced
		elif locked or dv_locked:
			continue
		else:
			if divine:
				_note_divine_roll(ctx, lt)
			var chance := float(grp.get("chance", 0.0)) * (1.0 if divine else pct)
			if rng.randf() >= chance:
				continue
			var roll := rng.randi_range(1, total)
			for pk in picks:
				roll -= int(pk[1])
				if roll <= 0:
					chosen = str(pk[0])
					break
		if chosen == "":
			continue
		if bool(items_t.get(chosen, {}).get("divine", false)):
			var blocked: Array = ctx.get("blocked", []) if ctx.get("blocked") is Array else []
			var dropped: Array = ctx.get("divine_dropped", []) if ctx.get("divine_dropped") is Array else []
			if blocked.has(chosen) or dropped.has(chosen):
				continue   # 全服唯一：已有人持有 → 這一擲作廢（不補擲別的）
			dropped.append(chosen)
			ctx["divine_dropped"] = dropped
		out.append({ "id": chosen, "n": 1 })
	return out

## 神兵全服鎖的範圍（balance_sim loot_rate_hour 依這個值算「幾個人一起刷」）：WORLD＝每張表全服共用一個鎖
const DIVINE_LOCK_SCOPE := "WORLD"

## 這張表的神兵群組全服還鎖著（ctx.divine_locked），或這一場已經擲過（ctx.divine_rolled）。沒有 lockout_shichen 或沒有 id 的表不鎖
static func is_divine_locked(ctx: Dictionary, lt: Dictionary) -> bool:
	var lt_id := str(lt.get("id", ""))
	if lt_id == "" or int(lt.get("lockout_shichen", 0)) <= 0:
		return false
	for k in ["divine_locked", "divine_rolled"]:
		var l: Variant = ctx.get(k, [])
		if l is Array and (l as Array).has(lt_id):
			return true
	return false

static func _note_divine_roll(ctx: Dictionary, lt: Dictionary) -> void:
	var lt_id := str(lt.get("id", ""))
	if lt_id == "" or int(lt.get("lockout_shichen", 0)) <= 0:
		return
	var rolled: Array = ctx.get("divine_rolled", []) if ctx.get("divine_rolled") is Array else []
	if not rolled.has(lt_id):
		rolled.append(lt_id)
	ctx["divine_rolled"] = rolled

## 這個角色對這張掉落表還在鎖定中（ctx.locked = { char_id: [表 id] }）。
## M3c 第二輪審查：也看這一場已經擲過的（ctx.lockout_rolled）——同一場有兩隻用同一張鎖定表的怪時，
## 以前每一隻都讀戰鬥開始時的快照、各擲一次；現在第二隻起就算鎖定
static func is_locked(ctx: Dictionary, char_id: String, lt_id: String) -> bool:
	if char_id == "":
		return false
	var rolled: Variant = ctx.get("lockout_rolled", [])
	if rolled is Array:
		for pr in rolled:
			if pr is Array and (pr as Array).size() >= 2 and str(pr[0]) == char_id and str(pr[1]) == lt_id:
				return true
	var m: Variant = ctx.get("locked", {})
	if not (m is Dictionary):
		return false
	var l: Variant = (m as Dictionary).get(char_id, [])
	return l is Array and (l as Array).has(lt_id)

## 群組裡有 ctx.force 的物品（權重 > 0）→ 回傳它並記進 ctx.used_force（同一件只用一次）
static func _forced_pick(picks: Array, ctx: Dictionary) -> String:
	var force: Variant = ctx.get("force", [])
	if not (force is Array) or (force as Array).is_empty():
		return ""
	var used: Array = ctx.get("used_force", []) if ctx.get("used_force") is Array else []
	for pk in picks:
		var iid := str(pk[0])
		if int(pk[1]) > 0 and (force as Array).has(iid) and not used.has(iid):
			used.append(iid)
			ctx["used_force"] = used
			return iid
	return ""
