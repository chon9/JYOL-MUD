extends "res://tests/unit/test_world_fixture.gd"
## WP-ECON：獵人（M3B_PLAN §5.2.4 HUNT、§5.1.8、§11.1 test_m3b_hunt）：HUNT 開戰、勝利額外掉落、逃跑只加失敗熟練。
## life_hunting 列、獸皮、獵場由內容碎片之後才進 data/ → 本機假資料。
## 戰鬥結算掛鉤（BattleSystem 對 HUNT 呼叫 host.life.on_hunt_settled）是 WP-SECT Day-0；還沒接上時測試直接呼叫。

const ROOM := "xw_grass"

func before_each() -> void:
	world_name = "w_m3b_hunt"
	super.before_each()
	if ws.game != null:
		_install_fakes()

func _install_fakes() -> void:
	for m in [["r_shoupi", "獸皮"], ["r_langpi", "狼皮"]]:
		tables()["items"][m[0]] = { "id": m[0], "name": m[1], "tab": "MATERIAL", "slot": "", "atk": 0, "def": 0, "weight": 1,
			"price": 10, "stack": 99, "spoil_days": 0, "effects": [], "usable": false, "usable_in_battle": false,
			"no_sell": false, "quest_item": false, "desc": "測試", "era": "1.0A", "src": "proposal" }
	tables()["life_skills"]["life_hunting"] = { "id": "life_hunting", "name": "獵人", "mode": "HUNT", "feature": "HUNT",
		"tool": "", "tools": [], "verb": "打獵", "jing_cost": 6, "cooldown_s": 5, "cap": 100, "yield": [], "recipes": [],
		"hunt": { "drops": [
			{ "item": "r_shoupi", "chance": 1.0, "n": [1, 1], "min_level": 1, "monsters": ["m_rabbit", "m_bigrabbit"] },
			{ "item": "r_langpi", "chance": 1.0, "n": [1, 1], "min_level": 1, "monsters": ["m_wolf"] } ] },
		"era": "1.0A", "src": "later" }
	var room: Dictionary = host().index.room(ROOM)
	room["features"] = ["HUNT"]
	room["hunt_table"] = [ { "monster": "m_rabbit", "w": 1 } ]

func _setup() -> bool:
	if not game_ok():
		return false
	if make_char("獵戶") == null:
		return false
	make_strong()
	goto(ROOM)
	clear_events()
	return true

## 結算掛鉤還沒接上（WP-SECT）：HUNT 記錄還在 → 直接呼叫
func _settle_if_unwired(per: String, kills: Array, bid: int) -> void:
	if ch().counters.has(LifeSystem.HUNT_KEY):
		print("[test_m3b_hunt] note: BattleSystem 尚未呼叫 life.on_hunt_settled（WP-SECT §5.1.8），直接呼叫")
		host().life.on_hunt_settled(s(), ch(), { "kind": "HUNT", "per": per, "result": per, "kills": kills, "bid": bid,
			"died": false })
		ws.flush()

func test_hunt_starts_battle() -> void:
	if not _setup():
		return
	assert_eq(reason("work", { "skill": "life_hunting" }), "not_known")
	ch().skills.set_level("life_hunting", 1, tables())
	var jing := int(ch().vitals["jing"])
	var r := send("work", { "skill": "life_hunting" })
	assert_true(r.get("ok", false), "hunt: %s" % str(r))
	assert_true(bool(r.get("hunt", false)))
	assert_true(s().battle_id != 0, "開戰")
	assert_eq(str(host().battles.active[s().battle_id]["kind"]), "HUNT", "battle kind HUNT")
	assert_eq(int(ch().vitals["jing"]), jing - 6, "開戰時扣精")
	assert_true(float(ch().counters.get(LifeSystem.CD_KEY, 0.0)) > ws.world_time(), "開戰時設冷卻")
	assert_false(last(LifeSystem.E_HUNT_START).is_empty(), "hunt_start")
	assert_eq(str(lastp(LifeSystem.E_HUNT_START).get("monster_name", "")), "野兔")
	var info: Dictionary = ch().counters[LifeSystem.HUNT_KEY]
	assert_eq(int(info["bid"]), s().battle_id)

func test_hunt_victory_extra_drops() -> void:
	if not _setup():
		return
	ch().skills.set_level("life_hunting", 1, tables())
	var prof0 := int(ch().skills.prof("life_hunting"))
	assert_true(send("work", { "skill": "life_hunting" }).get("ok", false))
	var bid: int = s().battle_id
	var res := drive_battle("fight")
	assert_eq(str(res.get("result", "")), "VICTORY", "打贏野兔")
	_settle_if_unwired("VICTORY", ["m_rabbit"], bid)
	assert_eq(item_count("r_shoupi"), 1, "額外掉落獸皮")
	assert_eq(item_count("r_langpi"), 0, "只對寫明的怪")
	assert_eq(int(ch().skills.prof("life_hunting")) - prof0, Learning.LIFE_PROF_OK, "勝利 = 成功熟練")
	assert_false(ch().counters.has(LifeSystem.HUNT_KEY), "結算後清掉記錄")

func test_hunt_flee_only_fail_prof() -> void:
	if not _setup():
		return
	ch().skills.set_level("life_hunting", 1, tables())
	var prof0 := int(ch().skills.prof("life_hunting"))
	# 直接呼叫掛鉤（逃跑的戰鬥結果與兔子 AI 有關，這裡只驗 LifeSystem 的處理）
	ch().counters[LifeSystem.HUNT_KEY] = { "skill": "life_hunting", "bid": 42, "monster": "m_rabbit" }
	host().life.on_hunt_settled(s(), ch(), { "kind": "HUNT", "per": "FLED", "kills": [], "bid": 42, "died": false })
	assert_eq(int(ch().skills.prof("life_hunting")) - prof0, Learning.LIFE_PROF_FAIL, "逃跑 = 失敗熟練")
	assert_eq(item_count("r_shoupi"), 0, "沒有掉落")
	# 戰敗同樣
	ch().counters[LifeSystem.HUNT_KEY] = { "skill": "life_hunting", "bid": 43, "monster": "m_rabbit" }
	host().life.on_hunt_settled(s(), ch(), { "kind": "HUNT", "per": "DEFEAT", "kills": [], "bid": 43, "died": true })
	assert_eq(int(ch().skills.prof("life_hunting")) - prof0, 2 * Learning.LIFE_PROF_FAIL)
	# 別場戰鬥（bid 不符）不算；不是 HUNT 的 kind 不算
	ch().counters[LifeSystem.HUNT_KEY] = { "skill": "life_hunting", "bid": 44, "monster": "m_rabbit" }
	host().life.on_hunt_settled(s(), ch(), { "kind": "HUNT", "per": "VICTORY", "kills": ["m_rabbit"], "bid": 99 })
	host().life.on_hunt_settled(s(), ch(), { "kind": "ENCOUNTER", "per": "VICTORY", "kills": ["m_rabbit"], "bid": 44 })
	assert_eq(item_count("r_shoupi"), 0)
	assert_eq(int(ch().skills.prof("life_hunting")) - prof0, 2 * Learning.LIFE_PROF_FAIL)
	# 斷線結算（s == null）也加熟練與掉落
	host().life.on_hunt_settled(null, ch(), { "kind": "HUNT", "per": "VICTORY", "kills": ["m_rabbit"], "bid": 44 })
	assert_eq(item_count("r_shoupi"), 1)

func test_hunt_real_flee() -> void:
	if not _setup():
		return
	ch().skills.set_level("life_hunting", 1, tables())
	var prof0 := int(ch().skills.prof("life_hunting"))
	assert_true(send("work", { "skill": "life_hunting" }).get("ok", false))
	var bid: int = s().battle_id
	var res := drive_battle("flee")
	var per := str(res.get("result", ""))
	_settle_if_unwired(per, [], bid)
	if per == "FLED":
		assert_eq(int(ch().skills.prof("life_hunting")) - prof0, Learning.LIFE_PROF_FAIL, "逃跑只加失敗熟練")
		assert_eq(item_count("r_shoupi"), 0)
	else:
		# 兔子先跑了或被打死：結果不是 FLED 時只檢查有結算
		assert_false(ch().counters.has(LifeSystem.HUNT_KEY))

func test_hunt_needs_table_and_feature() -> void:
	if not _setup():
		return
	ch().skills.set_level("life_hunting", 1, tables())
	host().index.room(ROOM)["hunt_table"] = []
	assert_eq(reason("work", { "skill": "life_hunting" }), "no_feature", "沒有獵物表")
	goto("xx_square")
	assert_eq(reason("work", { "skill": "life_hunting" }), "no_feature", "城裡不能打獵")
	assert_eq(s().battle_id, 0)
