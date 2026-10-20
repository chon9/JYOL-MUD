extends "res://tests/unit/test_pk_world_base.gd"
## M3C_PLAN §6.5（WP-LOOT）：神兵全服唯一（有人持有不掉／不能再給）、惰性釋放、PvP 轉移（叫戰、強制、捉拿）、
## 不能賣丟存、死亡不掉、divine_source NONE 不掉。
## 研究：17173 xinshou/11「玩家如被其他玩家打死，不管是以何種方式…神兵利器將自動跑到該玩家身上」。

const SWORD := "w_sb_yitian"

func _loot():
	return host().get("loot")

func _pair(room := "xw_road") -> Array:
	var a := add("甲俠")
	var b := add("乙俠")
	goto_p(a, room)
	goto_p(b, room)
	return [a, b]

func _grant(peer: int, item := SWORD) -> Dictionary:
	return _loot().grant_divine(sess(peer), item)

func test_unique_grant_and_locks() -> void:
	if not deps_ok():
		return
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	assert_true(_grant(a).get("ok", false), "給 A 倚天劍")
	assert_eq(_loot().holder_of(SWORD), cid(a), "world.divine 登記")
	assert_eq(str(_grant(b).get("reason", "")), "divine_locked", "全服唯一")
	assert_eq(str(_loot().grant_divine(sess(b), "w_lt_heijian").get("reason", "")), "bad_value:value", "不是神兵")
	var uid := ""
	for it in chr(a).inventory.items:
		if str(it.get("id", "")) == SWORD:
			uid = str(it.get("uid", ""))
	assert_eq(reason_p(a, "drop_item", { "item_uid": uid, "n": 1 }), "divine_locked", "不能丟")
	assert_false(BankStore.bankable(tables()["items"][SWORD]), "不能存（錢莊、托鏢）")
	assert_false(host().npcs._sellable(tables()["items"][SWORD]), "不能賣")
	assert_eq(chr(a).inventory.count(SWORD), 1)

func test_lazy_release_and_reward_ctx_blocked() -> void:
	if not deps_ok():
		return
	var p := _pair()
	var a: int = p[0]
	assert_true(_grant(a).get("ok", false))
	var b := Battle.new(1, 1, {})
	b.add_unit(Encounter.monster_spec("m_guiwang", tables()))
	var ctx: Dictionary = _loot().reward_ctx({ "battle": b, "chars": {} })
	assert_has(ctx.get("blocked", []), SWORD, "有人持有 → blocked")
	# 持有者身上已經沒有（例：管理員拿走、角色刪除）→ 打頭目時惰性釋放
	chr(a).inventory.remove_item_id(SWORD, 1)
	ctx = _loot().reward_ctx({ "battle": b, "chars": {} })
	assert_false((ctx.get("blocked", []) as Array).has(SWORD), "身上沒有 → 釋放")
	assert_eq(_loot().holder_of(SWORD), "")
	# 不存在的角色也釋放
	_loot().divine_registry()[SWORD] = "ch_nobody00"
	_loot().validate_registry()
	assert_eq(_loot().holder_of(SWORD), "")

func test_divine_source_none_never_drops() -> void:
	if not deps_ok():
		return
	use_preset("classic_strict")
	assert_eq(str(GameData.rules.get("divine_source", "")), "NONE")
	var a := add("甲俠")
	var ctx: Dictionary = _loot().reward_ctx({ "chars": { sess(a).peer_id: chr(a) } })
	_loot().debug_force(sess(a), "w_sb_xuantie")
	ctx = _loot().reward_ctx({ "chars": { sess(a).peer_id: chr(a) } })
	var got := BattleRewards.roll_table(tables()["loot_tables"]["lt_m_guiwang"], tables(), RandomNumberGenerator.new(), ctx)
	assert_false(got.any(func(it): return it["id"] == "w_sb_xuantie"), "classic_strict：神兵不掉（連除錯強制都不行）")

func _equip_sword(peer: int) -> void:
	assert_true(_grant(peer).get("ok", false))
	for it in chr(peer).inventory.items:
		if str(it.get("id", "")) == SWORD:
			assert_true(chr(peer).inventory.equip(str(it["uid"]), tables(), chr(peer))["ok"])

func _check_transferred(winner: int, loser: int) -> void:
	settle()
	assert_eq(chr(winner).inventory.count(SWORD), 1, "倚天劍到了殺手身上")
	assert_eq(chr(loser).inventory.count(SWORD), 0, "受害者沒有了")
	assert_eq(str(chr(loser).inventory.equipped.get("WEAPON", "")), "", "已裝備的先卸下")
	assert_eq(_loot().holder_of(SWORD), cid(winner), "登記更新")
	assert_false(lastp_p(winner, "lt_divine_transfer").is_empty(), "殺手收到 lt_divine_transfer")
	assert_false(lastp_p(loser, "lt_divine_transfer").is_empty(), "受害者收到 lt_divine_transfer")
	assert_eq(int(lastp_p(loser, "lt_divine_transfer").get("def_peer", 0)), sess(loser).peer_id, "受害者看 target 句")

func test_transfer_on_forced_pk() -> void:
	if not deps_ok(true):
		return
	ws.options["newbie_pk_protect_xp"] = 0
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	var watcher := add("旁觀")
	_equip_sword(b)
	make_strong_p(a)
	make_weak_p(b)
	ok_p(a, "force_pk", { "target": cid(b) })
	drive_bid(sess(a).battle_id, { a: "fight", b: "defend" })
	_check_transferred(a, b)
	var keys: Array = evs_p(watcher, "jianghu_rumor").map(func(e): return str(e.get("p", {}).get("text_key", "")))
	assert_has(keys, "lt_rmr_divine_transfer", "【江湖傳聞】神兵易主")
	assert_eq(chr(b).inventory.count(SWORD), 0, "死亡也沒有掉在屍體上（keep_on_death 後轉給殺手）")

func test_transfer_on_challenge() -> void:
	if not deps_ok(true):
		return
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	_equip_sword(b)
	make_strong_p(a)
	make_weak_p(b)
	ok_p(a, "challenge", { "target": cid(b) })
	ok_p(b, "challenge_reply", { "from": cid(a), "accept": true })
	drive_bid(sess(a).battle_id, { a: "fight", b: "defend" })
	_check_transferred(a, b)

func test_transfer_on_seize_and_offline_killer() -> void:
	if not deps_ok():
		return
	var p := _pair()
	var a: int = p[0]
	var b: int = p[1]
	_equip_sword(b)
	# 捉拿（SEIZE）也算（「不管是以何種方式」）：PkSystem 對每個死於玩家的單位呼叫 on_pvp_kill
	_loot().on_pvp_kill(cid(a), cid(b), { "kind": "SEIZE", "room": "xw_road" })
	_check_transferred(a, b)
	# 殺手不在線 → 留在受害者身上
	_loot().on_pvp_kill("ch_offline0", cid(a), { "kind": "FORCED", "room": "xw_road" })
	assert_eq(chr(a).inventory.count(SWORD), 1, "殺手離線：不轉")
	# 自殺／同歸於盡（殺手＝受害者）不轉
	_loot().on_pvp_kill(cid(a), cid(a), {})
	assert_eq(chr(a).inventory.count(SWORD), 1)
