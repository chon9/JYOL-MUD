extends "res://tests/unit/test_world_fixture.gd"
## WP-ECON：製作經濟（M3C2_PLAN §4、§10.1 test_m3c2_econ）。
## success_base／success_per_level、yield[].n_per_levels、新配方做得出來、商店材料循環檢查（EconCalc）
## 對構造的循環資料報錯、data_lint WP-ECON 區塊、每小時收入模型（EconModel）的基本性質。

const DataLint := preload("res://tools/data_lint.gd")
const ROOM := "xx_square"

var _loader: DataLoader
var _v1a: Dictionary
var _v1b: Dictionary

func before_each() -> void:
	world_name = "w_m3c2_econ"
	super.before_each()
	if _loader == null:
		_loader = DataLoader.new()
		_loader.load_all("res://data")
		_v1a = _loader.activate(["1.0A"])
		var lb := DataLoader.new()
		lb.load_all("res://data")
		_v1b = lb.activate(["1.0A", "1.0B"])

func _item(id: String, price: int, extra := {}) -> Dictionary:
	var row := { "id": id, "name": id, "price": price, "no_sell": false, "quest_item": false }
	row.merge(extra, true)
	return row

## 最小的經濟表：商店賣 a；配方 a→b、b→c（兩步）
func _mini_tables(price_a: int, price_b: int, price_c: int, pct_rows := {}) -> Dictionary:
	return {
		"items": { "a": _item("a", price_a), "b": _item("b", price_b), "c": _item("c", price_c), "t_x": _item("t_x", 50) },
		"npcs": { "n_shop": { "id": "n_shop", "shop": { "items": ["a", "t_x"] } } },
		"reactions": pct_rows,
		"life_skills": { "life_x": { "id": "life_x", "mode": "CRAFT", "jing_cost": 5, "cooldown_s": 5, "yield": [],
			"recipes": [
				{ "id": "rc_b", "inputs": [ { "item": "a", "n": 2 }, { "item": "t_x", "n": 1 } ], "output": { "item": "b", "n": 1 } },
				{ "id": "rc_c", "inputs": [ { "item": "b", "n": 1 } ], "output": { "item": "c", "n": 2 } },
			] } },
	}

# ---------- 成功率（§4.4） ----------
func test_success_chance_fields() -> void:
	assert_true(is_equal_approx(RecipeCheck.success_chance(0), 0.5), "預設 0.5")
	assert_true(is_equal_approx(RecipeCheck.success_chance(30), 0.65), "預設每級 0.005")
	assert_true(is_equal_approx(RecipeCheck.success_chance(100), 0.95), "上限 0.95")
	assert_true(is_equal_approx(LifeSystem.success_chance(30), 0.65), "LifeSystem 舊呼叫照舊")
	var row := { "success_base": 0.4, "success_per_level": 0.01 }
	assert_true(is_equal_approx(RecipeCheck.success_chance(10, row), 0.5), "技能列覆寫")
	var rc := { "success_base": 0.2 }
	assert_true(is_equal_approx(RecipeCheck.success_chance(10, row, rc), 0.3), "配方覆寫 base、per_level 沿用技能列")
	assert_true(is_equal_approx(LifeSystem.success_chance(10, row, { "success_per_level": 0.0 }), 0.4), "配方 per_level 0")
	assert_true(is_equal_approx(RecipeCheck.success_chance(200, row), 0.95), "上限照舊 0.95")
	assert_true(is_equal_approx(RecipeCheck.success_chance(0, { "success_base": -1.0 }), 0.0), "不會變負")

# ---------- n_per_levels（§4.4） ----------
func test_n_per_levels() -> void:
	var e := { "item": "a", "n": [1, 2], "min_level": 1, "n_per_levels": 20 }
	assert_eq(RecipeCheck.n_bonus(e, 1), 0)
	assert_eq(RecipeCheck.n_bonus(e, 20), 0, "多 19 級還不到 20")
	assert_eq(RecipeCheck.n_bonus(e, 21), 1)
	assert_eq(RecipeCheck.n_bonus(e, 50), 2)
	assert_eq(RecipeCheck.yield_range(e, 50), [3, 4], "上下限各 +2")
	assert_eq(RecipeCheck.yield_range({ "item": "a", "n": [1, 1] }, 99), [1, 1], "沒寫 n_per_levels 不變")
	assert_eq(RecipeCheck.n_bonus({ "item": "a", "n_per_levels": 5, "min_level": 41 }, 50), 1, "從 min_level 算起")
	assert_eq(RecipeCheck.n_bonus({ "item": "a", "n_per_levels": 0 }, 50), 0, "0 = 不變")
	var row := { "yield": [e, { "item": "b", "n": [1, 1], "min_level": 30, "n_per_levels": 10 }] }
	assert_eq(RecipeCheck.gather_max(row, 21), [["a", 3]])
	assert_eq(RecipeCheck.gather_max(row, 50), [["a", 4], ["b", 3]])
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 20:
		var got := RecipeCheck.roll_gather({ "yield": [{ "item": "a", "chance": 1.0, "n": [1, 1], "min_level": 1, "n_per_levels": 10 }] }, 31, rng)
		assert_eq(got, [["a", 4]], "31 級 = 1 + 3")
	var ge := EconModel.gather_expect({ "yield": [{ "item": "a", "chance": 0.5, "n": [1, 3], "min_level": 1, "n_per_levels": 10 }] }, 21)
	assert_true(is_equal_approx(float(ge["a"]), 0.5 * 4.0), "期望 = 機率 × (lo+hi)/2（含加成）")

## 真資料：釣魚 41 級一次成功拿到 魚 1+2、鰻魚 1（LifeSystem.work 走 n_per_levels）
func test_gather_scales_with_level_in_world() -> void:
	if not game_ok() or make_char("漁夫") == null:
		return
	goto(ROOM)
	host().index.room(ROOM)["features"] = ["WATER"]
	ch().skills.set_level("life_fishing", 41, tables())
	give("t_yugan", 1)
	var tries := 0
	while item_count("r_fish") == 0 and tries < 40:
		tries += 1
		Survival.rest_full(ch(), tables(), ws.options)
		ch().counters.erase(LifeSystem.CD_KEY)
		var r := send("work", { "skill": "life_fishing" })
		assert_true(r.get("ok", false), "work: %s" % str(r))
	assert_eq(item_count("r_fish"), 3, "魚 1 + ⌊40/20⌋")
	assert_eq(item_count("r_manyu"), 1, "鰻魚 41 級 1 條")
	assert_has([0, 3], item_count("r_liyu"), "鯉魚 1 + ⌊20/10⌋（機率 0.95）")

## 真資料：新配方做得出來（廚師 麥餅、樵夫 燒焦炭）
func test_new_recipes_craft() -> void:
	if not game_ok() or make_char("廚子") == null:
		return
	goto(ROOM)
	host().index.room(ROOM)["features"] = ["STOVE", "KILN"]
	ch().skills.set_level("life_cooking", 20, tables())
	give("r_mai", 30)
	var tries := 0
	while item_count("c_maibing") == 0 and tries < 15:
		tries += 1
		Survival.rest_full(ch(), tables(), ws.options)
		ch().counters.erase(LifeSystem.CD_KEY)
		var r := send("work", { "skill": "life_cooking", "recipe": "rc_maibing" })
		assert_true(r.get("ok", false), "rc_maibing: %s" % str(r))
	assert_eq(item_count("c_maibing"), 1, "麥 ×2 → 麥餅")
	assert_eq(item_count("r_mai") % 2, 0, "每次成功扣 2 麥")
	ch().skills.set_level("life_woodcut", 40, tables())
	give("w_chaidao", 1)
	give("r_songmu", 30)
	tries = 0
	while item_count("r_jiaotan") == 0 and tries < 15:
		tries += 1
		Survival.rest_full(ch(), tables(), ws.options)
		ch().counters.erase(LifeSystem.CD_KEY)
		var r2 := send("work", { "skill": "life_woodcut", "recipe": "rc_jiaotan" })
		assert_true(r2.get("ok", false), "rc_jiaotan: %s" % str(r2))
	assert_eq(item_count("r_jiaotan"), 1, "松木 ×2 → 焦炭")
	ch().skills.set_level("life_woodcut", 39, tables())
	Survival.rest_full(ch(), tables(), ws.options)
	ch().counters.erase(LifeSystem.CD_KEY)
	assert_eq(reason("work", { "skill": "life_woodcut", "recipe": "rc_jiaotan" }), "recipe_level", "39 級不能燒焦炭")

# ---------- 防循環（§4.3） ----------
func test_min_buy_pct() -> void:
	assert_eq(EconCalc.min_buy_pct(_v1a), 95, "名聲折扣 95%")
	assert_eq(EconCalc.min_buy_pct({ "reactions": {} }), 100)
	var rx := { "r1": { "services": ["SHOP"], "price_pct": 95 }, "r2": { "services": ["SHOP", "INN"], "price_pct": 90 },
		"r3": { "services": ["SHOP"], "price_pct": 120 }, "r4": { "services": ["INN"], "price_pct": 50 } }
	assert_eq(EconCalc.min_buy_pct({ "reactions": rx }), 85, "負值加總、只算 SHOP、漲價不算")
	assert_eq(EconCalc.buy_price({ "price": 13 }, 95), 12, "四捨五入同商店")
	assert_eq(EconCalc.buy_price({ "price": 1 }, 50), 1, "最少 1")
	assert_eq(EconCalc.sell_price({ "price": 10 }), 3)
	assert_eq(EconCalc.sell_price({ "price": 1 }), 1, "最少 1")
	assert_eq(EconCalc.sell_price({ "price": 100, "no_sell": true }), 0, "不能賣")

func test_loop_check_catches_constructed_loops() -> void:
	# a 買 10（最低 10）；b = 2a → 成本 20；c = b / 2 → 每件 10
	var ok_t := _mini_tables(10, 60, 30)          # b 收購 18 < 20；c 收購 9×2 = 18 < 20
	assert_eq(EconCalc.loop_violations(ok_t).size(), 0, "沒有循環：%s" % str(EconCalc.loop_violations(ok_t)))
	assert_true(EconCalc.buy_basis(ok_t).has("c"), "兩步閉包：c 也算商店買得到")
	assert_true(is_equal_approx(float(EconCalc.buy_basis(ok_t)["c"]), 10.0))
	var direct := _mini_tables(10, 70, 30)         # b 收購 21 ≥ 20
	var v1 := EconCalc.loop_violations(direct)
	assert_eq(v1.size(), 1, "直接循環")
	assert_true("rc_b" in v1[0], v1[0] if v1.size() > 0 else "")
	var two := _mini_tables(10, 60, 34)           # c 收購 10×2 = 20 ≥ 20（相等也算）
	var v2 := EconCalc.loop_violations(two)
	assert_eq(v2.size(), 1, "多步驟循環（相等也不行）")
	assert_true(v2.size() > 0 and "rc_c" in v2[0])
	# 折扣：最低買價 90% → a 9、b 成本 18；b 收購 18 ≥ 18
	var disc := _mini_tables(10, 60, 28, { "rx": { "services": ["SHOP"], "price_pct": 90 } })
	assert_eq(EconCalc.loop_violations(disc).size(), 1, "用最低折扣價判定")
	# 工具不算材料：t_x 在商店也一樣
	assert_eq(EconCalc.consumed_inputs(direct["life_skills"]["life_x"]["recipes"][0]), [["a", 2]])
	# 不是全部材料都買得到 → 不檢查
	var self_t := _mini_tables(10, 900, 900)
	self_t["npcs"]["n_shop"]["shop"]["items"] = ["t_x"]
	assert_eq(EconCalc.loop_violations(self_t).size(), 0, "材料要自己採 → 不是循環")

func test_real_data_has_no_loops() -> void:
	assert_eq(EconCalc.loop_violations(_v1a), PackedStringArray(), "1.0A")
	assert_eq(EconCalc.loop_violations(_v1b), PackedStringArray(), "1.0A＋1.0B")
	# 種子在商店：種麻 → 紡線 → 織布 → 縫衣這條全在閉包內（M3c2 調價的理由）
	var basis := EconCalc.buy_basis(_v1a)
	for id in ["r_zhongzi_ma", "r_ma", "r_xianzhou", "r_mabu", "r_mianhua", "r_mianbu"]:
		assert_true(basis.has(id), "閉包含 %s" % id)
	assert_true(EconCalc.closure_recipe_count(_v1a) >= 8)

## econ_no_loss（既有規則）：成品收購價 > 材料收購價
func test_real_data_no_loss() -> void:
	var items: Dictionary = _v1b["items"]
	for e in EconCalc.all_recipes(_v1b):
		var rc: Dictionary = e[1]
		var out := RecipeCheck.output_of(rc)
		var o := EconCalc.sell_price(items.get(str(out[0][0]), {})) * int(out[0][1])
		var i := 0
		for inp in RecipeCheck.inputs_of(rc):
			i += EconCalc.sell_price(items.get(str(inp[0]), {})) * int(inp[1])
		assert_true(o > i, "%s.%s 成品 %d > 材料 %d" % [e[0], str(rc.get("id", "")), o, i])

func test_lint_block() -> void:
	assert_eq(DataLint._check_m3c2_econ(_v1a), PackedStringArray(), "真資料 1.0A 乾淨")
	assert_eq(DataLint._check_m3c2_econ(_v1b), PackedStringArray(), "真資料 1.0A＋1.0B 乾淨")
	var bad := _v1b.duplicate(true)
	bad["life_skills"]["life_fishing"]["yield"][0]["n_per_levels"] = -1
	bad["life_skills"]["life_cooking"]["success_base"] = 1.5
	bad["life_skills"]["life_cooking"]["recipes"][0]["success_per_level"] = -0.1
	# 布莊賣的麻布直接縫粗布道袍：把粗布道袍改成 1 塊麻布 → 收購 36 ≥ 麻布最低買價
	for rc in bad["life_skills"]["life_tailoring"]["recipes"]:
		if str(rc["id"]) == "rc_cubudaopao":
			rc["inputs"] = [{ "item": "r_mabu", "n": 1 }]
	var errs := DataLint._check_m3c2_econ(bad)
	var joined := "\n".join(errs)
	assert_true("n_per_levels" in joined, joined)
	assert_true("success_base" in joined, joined)
	assert_true("success_per_level" in joined, joined)
	assert_true("rc_cubudaopao" in joined and "econ_loop" in joined, joined)
	# 主流程（check_content）也會叫到
	assert_true(DataLint.check_content(bad).size() >= errs.size())

# ---------- 每小時收入模型（§4.1） ----------
func test_econ_model_basics() -> void:
	var base := { "tables": _v1b, "regen": 0.24, "potion_per_jing": EconModel.potion_per_jing(_v1b),
		"hunt_monsters": ["m_hunt_yetu"], "hunt_fight_s": 30.0 }
	assert_true(is_equal_approx(EconModel.potion_per_jing(_v1b), 0.6), "精藥水 30 兩回 50 精")
	var ctx := base.duplicate()
	ctx.merge({ "level": 30, "skills": ["life_fishing"], "gather_only": true, "shop": {}, "potion": false })
	assert_eq(EconModel.action(ctx, 5, 5.0), [maxf(5.0, 5 / 0.24), 0.0], "自然回精：精 / 回精速度")
	ctx.potion = true
	var a: Array = EconModel.action(ctx, 5, 5.0)
	assert_true(is_equal_approx(float(a[0]), 5.0) and is_equal_approx(float(a[1]), (5 - 0.24 * 5) * 0.6), "精藥水：冷卻、補不足的精")
	ctx.potion = false
	assert_has(EconModel.products(ctx), "r_fish")
	assert_not_has(EconModel.products(ctx), "r_manyu", "30 級還釣不到鰻魚")
	# 等級越高越賺（同一條鏈）
	var prev := -INF
	for lv in [10, 30, 50]:
		var best := EconModel.chain_best(base, ["life_fishing"], lv, true, 0.1)
		assert_true(float(best.rate) > 0.0, "L%d > 0" % lv)
		assert_true(float(best.rate) >= prev, "L%d 不遞減" % lv)
		prev = float(best.rate)
	# 做不出來（沒有技能）→ NAN
	var none := base.duplicate()
	none.merge({ "level": 10, "skills": [], "gather_only": false, "shop": {}, "potion": false })
	assert_true(is_nan(EconModel.product_rate(none, "c_maibing", 0.1)))
	# 商店模式：買得到的東西成本 = 買價、時間 0
	var sh := base.duplicate()
	sh.merge({ "level": 10, "skills": [], "gather_only": false, "shop": EconModel.shop_prices(_v1b), "potion": false })
	var c := EconModel.unit_cost(sh, "r_mabu", 0.1)
	assert_eq(c, [0.0, float(EconCalc.buy_price(_v1b["items"]["r_mabu"], 95))])
