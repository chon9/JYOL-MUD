extends "res://tests/unit/test_battle_helpers.gd"
## 決定性回放：種子 + 單位規格 + 指令序列（含送達的 tick）→ 事件序列完全相同（M1_PLAN 3.4.1）。
## 黃金檔 tests/fixtures/battle_golden_01.json 由 build_golden() 產生（見檔案的 _how 欄位）。

const GOLDEN_PATH := "res://tests/fixtures/battle_golden_01.json"
const GOLDEN_SEED := 20261017

static func golden_specs() -> Array:
	return [
		player_spec({ "weapon": bare(), "neili": 40, "neili_max": 50, "effective_inner": 10,
			"skills": { "sl_changquan": 30, "basic_fist": 30, "basic_dodge": 10, "basic_parry": 10, "basic_inner": 10, "foxa": 10 },
			"arts": ["sl_changquan"], "sect_skill": { "id": "foxa", "effect": "DEFENSE", "level": 10 } }),
		monster("m_rabbit"),
		monster("m_wolf"),
	]

## 用自動玩家打一場並產生黃金檔內容
static func build_golden() -> Dictionary:
	var specs := golden_specs()
	var opts := default_opts()
	var b := Battle.new(1, GOLDEN_SEED, opts)
	for s in specs:
		b.add_unit(s)
	var ev := b.start(tables())
	var r := play(b, [1])
	ev.append_array(r.events)
	return { "_how": "godot --headless --path . --script <產生器> 呼叫 test_battle_replay.gd 的 build_golden()；改動戰鬥邏輯後需重新產生並人工確認差異",
		"seed": GOLDEN_SEED, "opts": opts, "specs": specs, "commands": r.commands,
		"result": b.result_name(), "ticks": b.tick_no, "events_json": JSON.stringify(ev) }

static func run_fixture(g: Dictionary) -> Dictionary:
	var b := Battle.new(1, int(g.seed), g.opts)
	for s in g.specs:
		b.add_unit(s)
	var ev := b.start(tables())
	ev.append_array(replay(b, g.commands))
	return { "battle": b, "events": ev }

func _load_golden() -> Dictionary:
	if not FileAccess.file_exists(GOLDEN_PATH):
		fail("缺少黃金檔 " + GOLDEN_PATH)
		return {}
	var f := FileAccess.open(GOLDEN_PATH, FileAccess.READ)
	var g: Variant = JSON.parse_string(f.get_as_text())
	assert_type(g, TYPE_DICTIONARY, "golden json")
	return g if g is Dictionary else {}

func test_golden_replay_matches() -> void:
	var g := _load_golden()
	if g.is_empty():
		return
	var out := run_fixture(g)
	var b: Battle = out.battle
	assert_true(b.is_over(), "回放後戰鬥結束")
	assert_eq(b.result_name(), str(g.result))
	assert_eq(b.tick_no, int(g.ticks))
	var got := JSON.stringify(out.events)
	if not assert_eq(got.length(), str(g.events_json).length(), "事件 JSON 長度"):
		pass
	assert_true(got == str(g.events_json), "事件序列與黃金檔完全相同")
	var keys := keys_of(out.events)
	assert_true(keys.has("battle_await"), "黃金檔涵蓋等待模式")
	assert_true(keys.has("move_fist_basic"), "黃金檔涵蓋出招")
	assert_true(keys.has("battle_kill"), "黃金檔涵蓋擊殺")

func test_same_input_twice_identical() -> void:
	var a := build_golden()
	var c := build_golden()
	assert_eq(a.events_json, c.events_json)
	assert_eq(JSON.stringify(a.commands), JSON.stringify(c.commands))
	# 錄下的指令回放 = 原本的事件
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(a))
	var out := run_fixture(parsed)
	assert_true(JSON.stringify(out.events) == a.events_json, "以 JSON 往返後的規格與指令回放結果相同")

func test_different_seed_differs() -> void:
	var g := build_golden()
	var b := Battle.new(1, GOLDEN_SEED + 1, default_opts())
	for s in golden_specs():
		b.add_unit(s)
	var ev := b.start(tables())
	ev.append_array(play(b, [1]).events)
	assert_true(JSON.stringify(ev) != g.events_json, "種子不同 → 結果不同")

func test_command_tick_matters() -> void:
	# 同樣的指令晚一個 tick 送達 → 等待時間不同，事件不同（tick 是輸入的一部分）
	var g := build_golden()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(g))
	var late: Array = []
	for c in parsed.commands:
		var c2: Dictionary = c.duplicate(true)
		c2.tick = int(c.tick) + 1
		late.append(c2)
	parsed.commands = late
	var out := run_fixture(parsed)
	assert_true(JSON.stringify(out.events) != g.events_json)
