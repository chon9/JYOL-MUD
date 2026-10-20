extends "res://tests/unit/test_world_fixture.gd"
## WP-NPCPK（M3C_PLAN §5.6、§12.1）：攻擊 NPC 的門派後果。
## 本派攻擊同門 → ATTACK_SECT_NPC 門規 → breach（JAIL／EXPEL 兩種模式）；外人滅派 → 公敵、hostile_entry 觸發；
## 丁春秋：本派 → 叛派、外人 → 公敵；外人打門派弟子不設公敵；華山殺善良 → breach；少林、恆山降級；峨嵋斷惡。

const A := preload("res://tests/unit/test_m3c_npc_attack.gd")

func _setup(city: String, room: String, sect := "") -> bool:
	if not game_ok():
		return false
	ws.options["sect_hostile_entry"] = false
	if make_char("門派俠客", city) == null:
		return false
	make_strong()
	ch().combat_xp = 200000
	if sect != "":
		ch().sect = sect
		host().sects.on_join(s(), sect, str(GameData.tables["sects"][sect].get("head_npc", "")))
	goto(room)
	clear_events()
	return true

func _units(peer := 1) -> int:
	var e := A.battle_entry(self, peer)
	if e.is_empty():
		return 0
	return (e["battle"] as Battle).units.filter(func(u): return not u.is_player()).size()

func _breach_rule_texts() -> Array:
	return evs("sect_breach").map(func(e): return str(e.get("p", {}).get("rule_text", "")))

# ---------------------------------------------------------------- 本派攻擊同門
func test_member_attacks_own_disciple_jail() -> void:
	if not _setup("xixia", "wd_square", "wudang"):
		return
	var r := send("npc_attack", { "npc": "n_wd_zhongfei" })
	assert_true(r.get("ok", false), "attack own disciple: %s" % str(r))
	assert_false(evs("sect_breach").is_empty(), "ATTACK_SECT_NPC → breach")
	assert_true("不得攻擊武當門人" in _breach_rule_texts(), "wd_r_attack_npc text: %s" % str(_breach_rule_texts()))
	assert_eq(str(lastp("sect_breach").get("outcome", "")), "JAIL")
	assert_true(ch().is_jailed(), "jailed (enforced after the fight)")
	A.finish(self, 1, true)
	ws.advance(1.5)
	assert_eq(s().room_id(), "wd_siguo", "sent to 武當思過處 after the battle")
	assert_eq(str(ch().sect), "wudang", "JAIL mode keeps the sect")

func test_member_attacks_own_gate_expel_mode() -> void:
	if not game_ok():
		return
	use_preset("classic_strict")
	if not _setup("xixia", "hg_gate", "hengshan"):
		return
	ok("npc_attack", { "npc": "n_hg_zhike" })
	assert_false(evs("sect_breach").is_empty())
	assert_eq(str(lastp("sect_breach").get("outcome", "")), "EXPEL")
	assert_eq(str(ch().sect), "", "classic_strict: expelled")
	assert_true(ch().sect_traitor.has("hengshan"))
	A.finish(self)

# ---------------------------------------------------------------- 外人
func test_outsider_miepai_wudang_enemy_and_hostile_entry() -> void:
	if not _setup("xixia", "wd_gate"):
		return
	ok("talk", { "npc": "n_wd_zhike" })
	var menu: Dictionary = lastp("npc_menu") if not evs("npc_menu").is_empty() else host().npcs.menu(s(), "n_wd_zhike")
	assert_eq(str(menu.get("attack", {}).get("label", "")), "滅派")
	var r := ok("npc_attack", { "npc": "n_wd_zhike", "mode": "MIEPAI" })
	assert_true(int(r.get("battle_id", 0)) > 0)
	assert_eq(_units(), 3, "3 名武當護山弟子")
	assert_true(ch().sect_enemies.has("wudang"), "outsider 滅派 → 武當公敵")
	assert_false(evs("na_sect_enemy").is_empty())
	assert_false(evs("na_miepai").is_empty())
	A.finish(self)
	if s().battle_id != 0:
		A.finish(self)
	# 之後走進武當：既有 hostile_entry（enemy_of wudang）接手
	ws.options["sect_hostile_entry"] = true
	assert_true(host().sects.hostile_entry(s(), "wd_square"), "hostile entry for the new enemy")
	A.finish(self)
	# 已是公敵：第二次不重複加
	clear_events()
	goto("wd_gate")
	A.advance_shichen(self, 3.2)   # M3c 審查：打退後要等重生時間才能再滅派
	ok("npc_attack", { "npc": "n_wd_zhike", "mode": "MIEPAI" })
	assert_true(evs("na_sect_enemy").is_empty(), "already an enemy")
	assert_eq(ch().sect_enemies.count("wudang"), 1)
	A.finish(self)

func test_outsider_disciple_no_enemy() -> void:
	if not _setup("xixia", "wd_square"):
		return
	ok("npc_attack", { "npc": "n_wd_zhongfei" })
	assert_false(ch().sect_enemies.has("wudang"), "attacking a disciple (outsider) is just a fight")
	assert_true(evs("sect_breach").is_empty())
	A.finish(self)

func test_outsider_gate_enemy_shaolin_and_wuseng_entry() -> void:
	if not _setup("xixia", "sl_gate"):
		return
	ok("npc_attack", { "npc": "n_sl_zhike" })
	assert_eq(_units(), 3, "3 名少林武僧")
	assert_true(ch().sect_enemies.has("shaolin"))
	A.finish(self)
	if s().battle_id != 0:
		A.finish(self)
	ws.options["sect_hostile_entry"] = true
	assert_true(host().sects.hostile_entry(s(), "sl_gate"), "shaolin hostile_entry (m_npc_sl_wuseng) for enemies")
	var e := A.battle_entry(self)
	var ids: Array = (e["battle"] as Battle).units.filter(func(u): return not u.is_player()).map(func(u): return str(u.spec.get("ref", "")))
	assert_true("m_npc_sl_wuseng" in ids)
	A.finish(self)

# ---------------------------------------------------------------- 丁春秋／血刀老祖
func test_member_attacks_master_betrays() -> void:
	if not _setup("xixia", "xh_hall", "xingxiu"):
		return
	ok("npc_attack", { "npc": "n_xh_dingchunqiu" })
	assert_eq(str(ch().sect), "", "叛派")
	assert_true(ch().sect_traitor.has("xingxiu"))
	assert_true(ch().sect_enemies.has("xingxiu"))
	assert_false(evs("na_master_betray").is_empty())
	assert_true(evs("sect_breach").is_empty(), "betrayal, not a breach")
	A.finish(self, 1, false)

func test_outsider_attacks_master_enemy() -> void:
	if not _setup("xixia", "xd_hall"):
		return
	ok("npc_attack", { "npc": "n_xd_laozu" })
	assert_true(ch().sect_enemies.has("xuedao"))
	assert_false(ch().sect_traitor.has("xuedao"))
	A.finish(self, 1, false)
	assert_false(host().get("npcpk").npc_down("n_xd_laozu"), "masters never disappear")

# ---------------------------------------------------------------- 殺了才算
func test_huashan_kill_good_npc_breach() -> void:
	if not _setup("dali", "dl_square", "huashan"):
		return
	ok("npc_attack", { "npc": "n_na_dl_xiaohai" })
	assert_true(evs("sect_breach").is_empty(), "attacking alone is fine for huashan")
	A.finish(self)
	assert_true("不可殺善良的人" in _breach_rule_texts(), "hs_r_kill_good_npc: %s" % str(_breach_rule_texts()))
	A.finish(self)

func test_huashan_kill_evil_npc_fine() -> void:
	if not _setup("xixia", "xx_street", "huashan"):
		return
	ok("npc_attack", { "npc": "n_na_xx_eba" })
	A.finish(self)
	assert_true(evs("sect_breach").is_empty(), "killing a villain breaks no rule")

func test_shaolin_foxa_decays() -> void:
	if not _setup("dali", "dl_square", "shaolin"):
		return
	ch().skills.set_level("foxa", 10, tables())
	ok("npc_attack", { "npc": "n_na_dl_xiaohai" })
	A.finish(self)
	assert_eq(int(ch().skills.level("foxa")), 9, "佛法 −1 per good NPC")
	assert_false(evs("sect_skill_decay").is_empty())
	A.finish(self)
	# 殺惡人不扣
	goto("xx_street")
	clear_events()
	ok("npc_attack", { "npc": "n_na_xx_eba" })
	A.finish(self)
	assert_eq(int(ch().skills.level("foxa")), 9)

func test_hengshan_cibei_decays_and_breach() -> void:
	if not _setup("dali", "dl_square", "hengshan"):
		return
	ch().skills.set_level("cibei", 10, tables())
	ok("npc_attack", { "npc": "n_dl_cunmin" })
	A.finish(self)
	assert_eq(int(ch().skills.level("cibei")), 9, "慈悲 −1 (CHALLENGE counts too)")
	assert_true("不可殺善良之人" in _breach_rule_texts())
	A.finish(self)

func test_emei_duane_gains_on_evil_npc() -> void:
	if not _setup("xixia", "xx_street", "emei"):
		return
	ch().skills.set_level("duane", 5, tables())
	var before: int = int(ch().skills.level("duane")) * 100000 + int(ch().skills.prof("duane"))
	ok("npc_attack", { "npc": "n_na_xx_eba" })
	A.finish(self)
	var after: int = int(ch().skills.level("duane")) * 100000 + int(ch().skills.prof("duane"))
	assert_true(after > before, "斷惡 grows when killing an evil NPC unit (%d → %d)" % [before, after])

## M3c 審查：隊友用 battle_join 加入滅派也要符合 attack.requires（武當弟子不能加入對武當的滅派），
## 加入的人照樣成為公敵（動手就算）
func test_party_join_checks_requires_and_applies_effects() -> void:
	if not _setup("xixia", "wd_gate"):
		return
	var b := add_player("武當隊友", "xixia")
	var c := add_player("外人隊友", "xixia")
	var bs := session_of(b)
	bs.character.sect = "wudang"
	host().sects.on_join(bs, "wudang", str(GameData.tables["sects"]["wudang"].get("head_npc", "")))
	for p in [b, c]:
		goto_as(p, "wd_gate")
		ok("party_invite", { "target": str(session_of(p).character.id) })
		assert_true(send_as(p, "party_reply", { "from": str(ch().id), "accept": true }).get("ok", false))
	var bid := int(ok("npc_attack", { "npc": "n_wd_zhike", "mode": "MIEPAI" }).get("battle_id", 0))
	assert_eq(reason_as(b, "battle_join", { "battle_id": bid }), "req_sect_not", "a 武當 disciple cannot join the 滅派")
	assert_false(session_of(b).character.sect_enemies.has("wudang"))
	var rc := send_as(c, "battle_join", { "battle_id": bid })
	assert_true(rc.get("ok", false), "outsider teammate joins: %s" % str(rc))
	assert_true(session_of(c).character.sect_enemies.has("wudang"), "joiner becomes a 武當 enemy too")
	A.finish(self)
