extends "res://tests/test_case.gd"
## M3B_PLAN §4.3、§11.1：新條件型別 sect_not、sect_rank_min、org_member、no_org、life_min（純角色判定）。

func _tb() -> Dictionary:
	return { "sect_ranks": { "x1": { "id": "x1", "sect": "gaibang", "rank": 1, "name": "一袋弟子" } },
		"sects": { "gaibang": { "id": "gaibang", "name": "丐幫" } } }

func _chk(conds: Array, c: Character) -> String:
	return Requirements.check(conds, c, _tb(), {}, {})

func test_schema_lists_new_types() -> void:
	for t in ["sect_not", "sect_rank_min", "org_member", "no_org", "life_min"]:
		assert_has(DataSchema.REQUIRE_TYPES, t)
		assert_true(DataSchema.REQUIRE_FIELDS_BY_TYPE.has(t), t)
	assert_eq(DataSchema.REQUIRE_FIELDS_BY_TYPE["sect_rank_min"], ["sect", "value"])
	assert_eq(DataSchema.REQUIRE_FIELDS_BY_TYPE["org_member"], [], "org 選填")
	assert_eq(DataSchema.check_conditions([ { "type": "sect_rank_min", "sect": "gaibang" } ], "t").size(), 1, "缺 value")
	assert_eq(DataSchema.check_conditions([ { "type": "no_org" }, { "type": "org_member", "org": "g1" } ], "t").size(), 0)

func test_sect_not() -> void:
	var c := Character.new()
	var cond := [ { "type": "sect_not", "sect": "gaibang" } ]
	assert_eq(_chk(cond, c), "", "沒有門派：不是丐幫")
	c.sect = "shaolin"
	assert_eq(_chk(cond, c), "")
	c.sect = "gaibang"
	assert_eq(_chk(cond, c), "req_sect_not", "丐幫不能運鏢")

func test_sect_rank_min() -> void:
	var c := Character.new()
	var cond := [ { "type": "sect_rank_min", "sect": "gaibang", "value": 2 } ]
	assert_eq(_chk(cond, c), "req_sect_rank_min", "沒有門派")
	c.sect = "shaolin"
	c.sect_rank = 5
	assert_eq(_chk(cond, c), "req_sect_rank_min", "別派的位階不算")
	c.sect = "gaibang"
	c.sect_rank = 1
	assert_eq(_chk(cond, c), "req_sect_rank_min")
	c.sect_rank = 2
	assert_eq(_chk(cond, c), "")
	assert_eq(Requirements.describe({ "type": "sect_rank_min", "sect": "gaibang", "value": 1 }, _tb()), "丐幫一袋弟子以上")

func test_org_member_and_no_org() -> void:
	var c := Character.new()
	assert_eq(_chk([ { "type": "no_org" } ], c), "")
	assert_eq(_chk([ { "type": "org_member" } ], c), "req_org_member")
	c.guild = "g1"
	assert_eq(_chk([ { "type": "no_org" } ], c), "req_no_org")
	assert_eq(_chk([ { "type": "org_member" } ], c), "", "空 org = 任何組織")
	assert_eq(_chk([ { "type": "org_member", "org": "g1" } ], c), "")
	assert_eq(_chk([ { "type": "org_member", "org": "g2" } ], c), "req_org_member")

func test_life_min() -> void:
	var c := Character.new()
	var tb := GameData.tables
	var cond := [ { "type": "life_min", "skill": "life_farming", "value": 10 } ]
	assert_eq(Requirements.check(cond, c, tb, {}, {}), "req_life_min")
	c.skills.set_level("life_farming", 10, tb)
	assert_eq(Requirements.check(cond, c, tb, {}, {}), "")
	assert_true(Requirements.describe(cond[0], tb).contains("生活技能"))

func test_character_m3b_fields_roundtrip() -> void:
	var old := Character.from_dict({ "schema_version": 1, "id": "ch_old" })
	assert_eq(old.sect_rank, 0)
	assert_eq(old.sect_rank_pending, {})
	assert_eq(old.bank, { "money": 0, "items": [] })
	assert_eq(old.guild, "")
	var c := Character.new()
	c.id = "ch_m3b"
	c.sect = "gaibang"
	c.sect_rank = 2
	c.sect_rank_pending = { "sect": "gaibang", "rank": 3, "since_world_s": 12.5 }
	c.bank = { "money": 500, "items": [ { "uid": "it_1", "id": "c_mantou", "n": 3, "born_s": 1.0, "lots": [ { "born_s": 1.0, "n": 3 } ] } ] }
	c.guild = "g1"
	var c2 := Character.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_eq(c2.to_dict(), c.to_dict(), "JSON 往返")
	assert_type(c2.sect_rank, TYPE_INT)
	assert_type(c2.bank["money"], TYPE_INT)
	assert_type(c2.bank["items"][0]["n"], TYPE_INT)
	assert_eq(c2.bank_pieces(), 3)
	assert_eq(str(c2.bank_find("it_1").get("id", "")), "c_mantou")
	assert_eq(c2.bank_find("nope"), {})
	assert_eq(int(c2.to_dict()["data_version"]), 3)
