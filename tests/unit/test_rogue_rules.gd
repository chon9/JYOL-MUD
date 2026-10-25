extends "res://tests/test_case.gd"
## ROGUE_PLAN §3.8、§3.9.2、§9.1（WP-RUN）：永久點數公式、回合回復、首領回合、規則列讀取。

var tables: Dictionary = {}
var r: Dictionary = {}

func before_each() -> void:
	if tables.is_empty():
		var loader := DataLoader.new()
		loader.load_all("res://data")
		tables = loader.activate(["1.0A", "1.0B", "rogue"])
	r = RogueRules.rules(tables)

func test_rules_row_and_defaults() -> void:
	assert_eq(int(r["attr_cap"]), 45)
	assert_eq(int(r["boss_every"]), 5)
	assert_eq(int(r["points_cap"]), 60)
	assert_true(float(r["p0"]) > 0.0, "p0（參考新角色戰力）> 0")
	var d := RogueRules.rules({})
	assert_eq(int(d["ally_max"]), 2, "沒有規則列 → DEFAULTS")
	assert_eq((d["kind_weights"] as Dictionary).get("ART"), 35)

## 公式本身用 ROGUE_PLAN §3.9.2 的原始常數（k 1.5、soft 20、half 30）驗；資料列的校準值另外驗（test_award_data_values）
func _plan_rules() -> Dictionary:
	var rr := r.duplicate(true)
	rr["points_k"] = 1.5
	rr["points_soft"] = 20
	rr["points_half"] = 30
	rr["points_cap"] = 60
	return rr

func test_award_data_values() -> void:
	# 0.7.x 試煉審查校準（data/rogue_rules.json）：k 1.3、half 20 → 前 5 局每局約 4 點、第 28–30 局才到 60
	assert_eq(RogueRules.award(6, 1, 0, true, r), int(floor(float(r.points_k) * sqrt(6.0) + 1e-9)) + 1 + 1)
	assert_eq(RogueRules.award(7, 1, 0, true, r), 5, "7 勝 1 首領 新紀錄：⌊1.3·√7⌋ = 3，+1 +1")
	assert_eq(RogueRules.award(2, 0, 0, false, r), 1, "2 勝：⌊1.3·√2⌋ = 1")
	assert_true(RogueRules.award(9, 1, 40, false, r) < RogueRules.award(9, 1, 0, false, r), "累計 40 後遞減")

func test_award_table() -> void:
	var pr := _plan_rules()
	assert_eq(RogueRules.award(0, 0, 0, false, pr), 0, "0 勝 0 點")
	assert_eq(RogueRules.award(1, 0, 0, true, pr), 1, "1 勝 1 點（新紀錄但不到 3 勝不加）")
	assert_eq(RogueRules.award(6, 1, 0, true, pr), 5, "6 勝 1 首領 新紀錄 → 3+1+1")
	assert_eq(RogueRules.award(6, 1, 0, false, pr), 4, "不是新紀錄 → 4")
	assert_eq(RogueRules.award(2, 0, 0, true, pr), 2, "2 勝：⌊1.5·√2⌋ = 2，新紀錄要 ≥ 3 勝")
	assert_eq(RogueRules.award(3, 0, 0, true, pr), 3, "3 勝新紀錄：2 + 1")

func test_award_diminishing_and_cap() -> void:
	var pr := _plan_rules()
	var full := RogueRules.award(9, 1, 0, false, pr)   # 4 + 1 = 5
	assert_eq(full, 5)
	var dim := RogueRules.award(9, 1, 30, false, pr)   # round(5 · 30/60) = 3（2.5 四捨五入）
	assert_true(dim < full and dim >= 1, "累計 ≥ 20 後遞減：%d" % dim)
	assert_eq(RogueRules.award(1, 0, 50, false, pr), 1, "遞減後至少 1（raw > 0）")
	assert_eq(RogueRules.award(0, 0, 50, false, pr), 0, "raw 0 → 0")
	assert_eq(RogueRules.award(16, 3, 58, true, pr), 2, "上限 60：最多補到 60")
	assert_eq(RogueRules.award(16, 3, 60, true, pr), 0, "已滿 60 → 0")
	assert_eq(RogueRules.award(4, 0, 19, false, pr), 3, "累計 19 還不遞減")

func test_restore_rule() -> void:
	var ch := _char()
	var d := ch.derived(tables, {})
	ch.vitals["qi"] = 10
	ch.vitals["jing"] = 0
	ch.vitals["shen"] = int(d["shen_max"])
	ch.vitals["neili"] = 0
	ch.vitals["food"] = 3
	ch.conditions = { "poison": { "level": 1 } }
	var got := RogueRules.restore(ch, tables, {}, false, r)
	var qmax := int(d["qi_max"])
	assert_eq(int(got["qi"]), int(floor(qmax * 0.35)), "氣 +35%")
	assert_eq(int(ch.vitals["qi"]), 10 + int(floor(qmax * 0.35)))
	assert_eq(int(got["shen"]), 0, "已滿的不加（夾上限）")
	assert_eq(int(got["neili"]), int(floor(int(d["neili_max"]) * 0.5)), "內力 +50%")
	assert_eq(int(ch.vitals["food"]), Character.FOOD_MAX, "飽食補滿")
	assert_true(ch.conditions.is_empty(), "戰後狀態清掉")
	ch.vitals["qi"] = qmax - 1
	got = RogueRules.restore(ch, tables, {}, false, r)
	assert_eq(int(ch.vitals["qi"]), qmax, "夾在最大值")
	ch.vitals["qi"] = 1
	ch.vitals["neili"] = 0
	got = RogueRules.restore(ch, tables, {}, true, r)
	assert_eq(int(ch.vitals["qi"]), qmax, "首領回合全滿")
	assert_eq(int(ch.vitals["neili"]), int(d["neili_max"]), "首領回合內力全滿")

func test_boss_round_and_rarity_weights() -> void:
	assert_false(RogueRules.is_boss_round(4, r))
	assert_true(RogueRules.is_boss_round(5, r))
	assert_true(RogueRules.is_boss_round(10, r))
	assert_eq(RogueRules.rarity_weights(1, r), [60, 30, 10, 0, 0])
	assert_eq(RogueRules.rarity_weights(6, r), [40, 35, 20, 5, 0])
	assert_eq(RogueRules.rarity_weights(20, r), [10, 25, 33, 23, 9])
	assert_eq(RogueRules.rarity_weights(3, r, "RARE"), [0, 0, 60, 30, 10], "首領獎勵")
	assert_eq(RogueRules.cn_number(40), "四十")
	assert_eq(RogueRules.cn_number(15), "十五")
	assert_eq(RogueRules.cn_number(105), "一百零五")
	assert_eq(RogueRules.cn_number(120), "一百二十")

func _char() -> Character:
	var ch := Character.new()
	for a in Character.ATTR_IDS:
		ch.attrs[a] = 20
	ch.skills.set_level("basic_inner", 40, tables)
	ch.vitals = { "jing": 0, "qi": 0, "shen": 0, "neili": 0, "food": 100, "water": 100 }
	return ch
