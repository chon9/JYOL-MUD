class_name LifeSystem
extends RefCounted
## 生活技能動作 work（M1_PLAN 4.12、3.11.12；M3B_PLAN §4.5、§5.2.4 第 2 版）。
## 模式：GATHER（採集 yield）／CRAFT（只有配方）／HUNT（打獵：開一場 HUNT 戰鬥，打贏額外掉落）。
## 同一技能可以同時有 yield 與 recipes（樵夫採木材＋燒炭、種田收稻＋種麻棉）：recipe == "" → 採集，否則照配方做。

const CD_KEY := "life_cd_until_s"     # 角色 counters 內的冷卻到期時間（世界時間）
const HUNT_KEY := "life_hunt"         # 角色 counters：進行中的打獵 { skill, bid, monster }
const BATTLE_KIND_HUNT := BattleSystem.KIND_HUNT
const E_HUNT_START := Protocol.E_HUNT_START
## 生活技能沒有自己的 work_ok_／work_fail_ 模板時改送這兩個（_econ.json 提供）
const E_WORK_OK_GENERIC := "e_work_ok"
const E_WORK_FAIL_GENERIC := "e_work_fail"

var host: GameHost

func _init(p_host: GameHost) -> void:
	host = p_host

## M3C2_PLAN §4.4：讀技能列／配方列的 success_base、success_per_level（預設 0.5／0.005，上限 0.95）
static func success_chance(level: int, row: Dictionary = {}, recipe: Dictionary = {}) -> float:
	return RecipeCheck.success_chance(level, row, recipe)

## 驗證順序（§5.2.4）：no_feature（配方 feature 覆寫）→ not_known → no_tool（tool＋tools＋配方 tools）→ busy
## → not_enough_jing → no_recipe／recipe_level／no_ingredients → 產出放不下 too_heavy（先檢查，不扣精、不扣材料）
func work(s: Session, skill_id: String, recipe_id: String) -> Dictionary:
	var ch = s.character
	var row: Dictionary = host.tables.get("life_skills", {}).get(skill_id, {})
	if row.is_empty():
		return GameHost.fail("not_known")
	var mode := RecipeCheck.mode_of(row)
	var recipe := RecipeCheck.find_recipe(row, recipe_id)   # 只拿來決定設施；找不到在後面回 no_recipe
	var room: Dictionary = host.index.room(s.room_id())
	var feats: Array = room.get("features", [])
	if not RecipeCheck.has_feature(feats, RecipeCheck.feature_for(row, recipe)):
		return GameHost.fail("no_feature")
	var hunting := recipe_id == "" and mode == RecipeCheck.MODE_HUNT
	var hunt_table: Variant = room.get("hunt_table", [])
	if hunting and (not (hunt_table is Array) or (hunt_table as Array).is_empty()):
		return GameHost.fail("no_feature")   # 有 HUNT 設施卻沒有獵物表（lint 會擋）
	var lv := int(ch.skills.level(skill_id))
	if lv < 1:
		return GameHost.fail("not_known")
	if not RecipeCheck.missing_tools(ch.inventory, RecipeCheck.tools_needed(row, recipe)).is_empty():
		return GameHost.fail("no_tool")
	var now := host.now_s()
	if float(ch.counters.get(CD_KEY, 0.0)) > now:
		return host.fail_busy(s, GameHost.COOLDOWN_LIFE)
	var jing_cost := RecipeCheck.jing_cost(row, recipe)
	if int(ch.vitals.get("jing", 0)) < jing_cost:
		return GameHost.fail("not_enough_jing")
	var crafting := recipe_id != "" or mode == RecipeCheck.MODE_CRAFT
	if crafting:
		if recipe.is_empty():
			return GameHost.fail("no_recipe")
		if lv < int(recipe.get("min_level", 1)):
			return GameHost.fail("recipe_level")
		if not RecipeCheck.missing_inputs(ch.inventory, recipe).is_empty():
			return GameHost.fail("no_ingredients")
	var carry_max := int(ch.derived(host.tables, host.options).get("carry_max", 0))
	if crafting:
		if BankStore.fit_reason(ch.inventory, host.tables, carry_max, RecipeCheck.output_of(recipe),
				RecipeCheck.inputs_of(recipe)) != "":
			return GameHost.fail("too_heavy")
	elif not hunting:
		if BankStore.fit_reason(ch.inventory, host.tables, carry_max, RecipeCheck.gather_max(row, lv)) != "":
			return GameHost.fail("too_heavy")

	if hunting:
		return _start_hunt(s, skill_id, row, hunt_table, jing_cost)

	ch.vitals["jing"] = int(ch.vitals.get("jing", 0)) - jing_cost
	ch.counters[CD_KEY] = now + float(row.get("cooldown_s", 5))
	var success := host.rng.randf() < success_chance(lv, row, recipe)
	var pr := _practice(ch, skill_id, success, RecipeCheck.prof_mult(recipe) if success else 1)
	var prof_gain := int(pr.get("gain", 0))
	var sname := host.skill_name(skill_id)
	if success:
		var gained: Array = []   # [[item_id, n]]
		if crafting:
			for inp in RecipeCheck.inputs_of(recipe):
				ch.inventory.remove_item_id(str(inp[0]), int(inp[1]))
				host.item_lost_event(s, str(inp[0]), int(inp[1]))
			gained = RecipeCheck.output_of(recipe)
		else:
			gained = RecipeCheck.roll_gather(row, lv, host.rng)
		var got := _give_all(s, gained)
		_tell_work(s, skill_id, true, { "skill_name": sname, "item_name": str(got.get("name", "")),
			"n": int(got.get("n", 0)), "prof": prof_gain, "recipe_name": str(recipe.get("name", "")) })
	else:
		_tell_work(s, skill_id, false, { "skill_name": sname, "prof": prof_gain,
			"recipe_name": str(recipe.get("name", "")) })
	host.npcs.skill_up_event(s, skill_id, int(pr.get("before", 0)), int(pr.get("after", 0)))
	return GameHost.ok({ "success": success })

## HUNT（§5.2.4）：擲一隻獵物 → battles.start_ex(s, [m], "HUNT", { pull_party: false })；扣精、設冷卻在開戰時
func _start_hunt(s: Session, skill_id: String, row: Dictionary, table: Variant, jing_cost: int) -> Dictionary:
	var ch = s.character
	var m := RecipeCheck.pick_hunt_monster(table, host.rng)
	if m == "" or not host.tables.get("monsters", {}).has(m):
		return GameHost.fail("no_feature")
	ch.vitals["jing"] = int(ch.vitals.get("jing", 0)) - jing_cost
	ch.counters[CD_KEY] = host.now_s() + float(row.get("cooldown_s", 5))
	host.tell(s, Protocol.CH_SYSTEM, E_HUNT_START, { "skill_name": host.skill_name(skill_id),
		"monster_name": host.monster_name(m) })
	# 先記下（bid 0 = 還不知道）：開戰瞬間就分出勝負時，結算掛鉤在 start_ex 回傳前就會跑
	ch.counters[HUNT_KEY] = { "skill": skill_id, "bid": 0, "monster": m }
	var bid := int(host.battles.start_ex(s, [m], BATTLE_KIND_HUNT, { "pull_party": false }))
	if ch.counters.get(HUNT_KEY) is Dictionary:
		ch.counters[HUNT_KEY]["bid"] = bid
	return GameHost.ok({ "hunt": true, "bid": bid, "monster": m })

## 戰鬥結算掛鉤（M3B_PLAN §5.1.8，BattleSystem 在 HUNT 戰鬥結束後呼叫）：
## 本人勝利 → practice_life(成功)＋hunt.drops；逃跑或失敗 → practice_life(失敗)。s 可能為 null（斷線結算）
func on_hunt_settled(s: Session, ch, summary: Dictionary) -> void:
	if ch == null:
		return
	if str(summary.get("kind", BATTLE_KIND_HUNT)) != BATTLE_KIND_HUNT:
		return
	var info: Variant = ch.counters.get(HUNT_KEY)
	var skill_id := ""
	if info is Dictionary:
		var bid := int((info as Dictionary).get("bid", 0))
		if bid != 0 and summary.has("bid") and int(summary["bid"]) != bid:
			return   # 不是這場打獵
		skill_id = str((info as Dictionary).get("skill", ""))
	if skill_id == "":
		skill_id = _hunt_skill()
	ch.counters.erase(HUNT_KEY)
	var row: Dictionary = host.tables.get("life_skills", {}).get(skill_id, {})
	if row.is_empty() or int(ch.skills.level(skill_id)) < 1:
		return
	var per := str(summary.get("per", summary.get("result", "")))
	var won := per == "VICTORY" and not bool(summary.get("died", false))
	var pr := _practice(ch, skill_id, won, 1)
	var sname := host.skill_name(skill_id)
	if won:
		var kills: Array = summary.get("kills", []) if summary.get("kills") is Array else []
		var drops := RecipeCheck.roll_hunt_drops(row, int(ch.skills.level(skill_id)), kills, host.rng)
		var got := _give_all(s, drops, ch)
		if s != null:
			_tell_work(s, skill_id, true, { "skill_name": sname, "item_name": str(got.get("name", "")),
				"n": int(got.get("n", 0)), "prof": int(pr.get("gain", 0)), "recipe_name": "" })
	elif s != null:
		_tell_work(s, skill_id, false, { "skill_name": sname, "prof": int(pr.get("gain", 0)), "recipe_name": "" })
	if s != null:
		host.npcs.skill_up_event(s, skill_id, int(pr.get("before", 0)), int(pr.get("after", 0)))
		s.sheet_dirty = true

# ---------- 內部 ----------
## times 次 Learning.practice_life；回傳 { before, after（等級）, gain（熟練度合計，含升級前後）}
func _practice(ch, skill_id: String, success: bool, times: int) -> Dictionary:
	var lv_before := int(ch.skills.level(skill_id))
	var gain := 0
	for i in maxi(1, times):
		var r: Dictionary = Learning.practice_life(ch, skill_id, success, host.tables)
		gain += int(r.get("gain", 0))
	return { "before": lv_before, "after": int(ch.skills.level(skill_id)), "gain": gain }

## 產出入背包（放不下的作廢；work 已先檢查過）；回傳第一項 { name, n }
func _give_all(s: Session, gained: Array, ch = null) -> Dictionary:
	if ch == null:
		ch = s.character
	var first := {}
	for g in gained:
		var res: Dictionary = host.give_item(ch, str(g[0]), int(g[1]))
		if res.get("ok", false):
			if s != null:
				host.item_gain_event(s, str(g[0]), int(g[1]))
			if first.is_empty():
				first = { "name": host.item_name(str(g[0])), "n": int(g[1]) }
	return first

func _tell_work(s: Session, skill_id: String, ok: bool, p: Dictionary) -> void:
	var key := (Protocol.E_WORK_OK_PREFIX if ok else Protocol.E_WORK_FAIL_PREFIX) + skill_id
	if not host.tables.get("text_templates", {}).has(key):
		key = E_WORK_OK_GENERIC if ok else E_WORK_FAIL_GENERIC
	host.tell(s, Protocol.CH_SYSTEM, key, p)

## 沒有記錄時，用資料裡第一個 HUNT 模式的技能
func _hunt_skill() -> String:
	var rows: Dictionary = host.tables.get("life_skills", {})
	var ids := rows.keys()
	ids.sort()
	for id in ids:
		if rows[id] is Dictionary and RecipeCheck.mode_of(rows[id]) == RecipeCheck.MODE_HUNT:
			return str(id)
	return ""
