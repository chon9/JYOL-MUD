extends "res://tests/unit/test_pk_world_base.gd"
## WP-PK 整合（M2_PLAN 6.1、5.3）：屍體保護期、授權、公開期、單件撿取、corpse_public 只送一次、
## corpse_auth_full、視圖與 my_corpses、重開世界後 authorized 與剩餘時間不變。

func before_each() -> void:
	world_name = "w_corpse"
	super.before_each()

## 擁有者在 xw_road 留下一具屍體（直接用 CorpseSystem.create；死亡流程本身由 test_world_death 測）
func _corpse_of(owner: int) -> String:
	var c = chr(owner)
	var items: Array = c.inventory.take_all()
	assert_true(items.size() >= 2, "starter items: %s" % str(items))
	var id: String = host().corpses.create(c, "xw_road", items)
	ws.flush()
	return id

func _corpse(id: String) -> Dictionary:
	return host().corpses.find(id)

func _view_corpse(peer: int, id: String) -> Dictionary:
	sess(peer).view_dirty = true
	host().flush_session(sess(peer), true)
	ws.flush()
	for c in view_p(peer).get("corpses", []):
		if str(c.get("id", "")) == id:
			return c
	return {}

func _first_uid(id: String) -> String:
	return str(_corpse(id)["items"][0].get("uid", ""))

func test_protected_then_authorized_single_item() -> void:
	if not deps_ok():
		return
	var owner := add("屍主")
	var friend := add("好友")
	var stranger := add("路人")
	for p in [owner, friend, stranger]:
		goto_p(p, "xw_road")
	var id := _corpse_of(owner)
	var n0 := CorpseSystem.pieces(_corpse(id))
	assert_eq(reason_p(stranger, "loot_corpse", { "corpse_id": id }), "corpse_protected")
	var vs := _view_corpse(stranger, id)
	assert_eq(vs.get("can_loot", true), false)
	assert_eq(vs.get("public", true), false)
	assert_false(vs.has("items"), "items hidden while protected")
	assert_true(int(vs.get("left_s", 0)) > 0)
	# 授權（不限房間）
	goto_p(owner, "xx_square")
	assert_eq(reason_p(friend, "corpse_authorize", { "corpse_id": id, "name": "好友" }), "not_corpse_owner")
	assert_eq(reason_p(owner, "corpse_authorize", { "corpse_id": "cp_00000000", "name": "好友" }), "corpse_not_found")
	assert_eq(reason_p(owner, "corpse_authorize", { "corpse_id": id, "name": "沒這人" }), "no_such_player")
	assert_eq(reason_p(owner, "corpse_authorize", { "corpse_id": id, "name": "屍主" }), "bad_target")
	ok_p(owner, "corpse_authorize", { "corpse_id": id, "name": "好友" })
	assert_eq(str(lastp_p(owner, "corpse_authorized").get("name", "")), "好友")
	assert_eq(str(lastp_p(friend, "corpse_auth_granted").get("owner_name", "")), "屍主")
	var vf := _view_corpse(friend, id)
	assert_eq(vf.get("authorized_me", false), true)
	assert_eq(vf.get("can_loot", false), true)
	assert_eq((vf.get("items", []) as Array).size(), (_corpse(id)["items"] as Array).size())
	# 單件撿
	assert_eq(reason_p(friend, "loot_corpse", { "corpse_id": id, "item_uid": "it_ffffffff" }), "no_item")
	var uid := _first_uid(id)
	var first_n := int(_corpse(id)["items"][0].get("n", 1))
	ok_p(friend, "loot_corpse", { "corpse_id": id, "item_uid": uid })
	assert_eq(int(lastp_p(friend, "corpse_looted_other").get("n_items", 0)), first_n)
	assert_eq(str(lastp_p(friend, "corpse_looted_other").get("owner_name", "")), "屍主")
	assert_eq(int(lastp_p(owner, "corpse_looted_by").get("n_items", 0)), first_n)
	assert_eq(str(lastp_p(owner, "corpse_looted_by").get("name", "")), "好友")
	assert_false(_corpse(id).is_empty(), "corpse still there")
	assert_eq(CorpseSystem.pieces(_corpse(id)), n0 - first_n)
	assert_eq(reason_p(stranger, "loot_corpse", { "corpse_id": id }), "corpse_protected", "still protected for others")
	settle()
	var mine: Array = sheet_p(owner).get("my_corpses", [])
	assert_eq(mine.size(), 1, "sheet.my_corpses")
	if mine.size() == 1:
		assert_eq(int(mine[0].get("n_items", 0)), n0 - first_n)

func test_public_period_anyone_loots_and_notice_once() -> void:
	if not deps_ok():
		return
	var owner := add("屍主")
	var stranger := add("路人")
	goto_p(owner, "xx_square")
	goto_p(stranger, "xw_road")
	var id := _corpse_of(owner)
	ws.advance(601.0 + 60.0)          # 過保護期，且至少跑一次每分鐘工作
	assert_eq(evs_p(owner, "corpse_public").size(), 1)
	ws.advance(180.0)
	assert_eq(evs_p(owner, "corpse_public").size(), 1, "sent only once")
	assert_eq(_corpse(id).get("public_notified", false), true)
	var vs := _view_corpse(stranger, id)
	assert_eq(vs.get("public", false), true)
	assert_eq(vs.get("can_loot", false), true)
	ok_p(stranger, "loot_corpse", { "corpse_id": id })
	assert_true(_corpse(id).is_empty(), "looted clean")

func test_auth_full() -> void:
	if not deps_ok():
		return
	var owner := add("屍主")
	var names := ["甲一", "乙二", "丙三", "丁四", "戊五"]
	for n in names:
		add(n)
	var id := _corpse_of(owner)
	var cap := int(ws.options.get("corpse_auth_max", 4))
	for i in cap:
		ok_p(owner, "corpse_authorize", { "corpse_id": id, "name": names[i] })
	ok_p(owner, "corpse_authorize", { "corpse_id": id, "name": names[0] })   # 重複授權同一人不算
	assert_eq((_corpse(id)["authorized"] as Array).size(), cap)
	assert_eq(reason_p(owner, "corpse_authorize", { "corpse_id": id, "name": names[cap] }), "corpse_auth_full")

func test_restart_keeps_authorized_and_time_left() -> void:
	if not deps_ok():
		return
	if not has_method("restart_world"):
		fail("M2 dependency missing: fixture.restart_world（WP-HOST 4.6.10）")
		return
	var owner := add("屍主")
	var friend := add("好友")
	var id := _corpse_of(owner)
	ok_p(owner, "corpse_authorize", { "corpse_id": id, "name": "好友" })
	ws.advance(100.0)
	var before: Dictionary = _corpse(id).duplicate(true)
	var left_before: int = host().corpses.left_s(_corpse(id), host().now_s())
	var friend_id := cid(friend)
	call("restart_world")
	var after := _corpse(id)
	assert_false(after.is_empty(), "corpse survives restart")
	assert_eq(after.get("authorized", []), [friend_id], "authorized list restored")
	assert_eq(int(CorpseSystem.pieces(after)), int(CorpseSystem.pieces(before)))
	assert_eq(float(after.get("created_s", 0.0)), float(before.get("created_s", -1.0)))
	assert_true(absi(host().corpses.left_s(after, host().now_s()) - left_before) <= 1, "time left frozen while host was off")
	assert_eq(bool(after.get("public_notified", true)), false)

## 物品堆疊改版：屍體上的物品帶 lots，撿回來時每一批的取得時間（腐壞時間）不變，而且併回同一格
func test_loot_keeps_lots() -> void:
	if not deps_ok():
		return
	var owner := add("撿皮人")
	goto_p(owner, "xw_road")
	var c = chr(owner)
	var now: float = host().now_s() + 1000.0
	host().give_item(c, "r_rabbitskin", 2, now - 500.0)
	host().give_item(c, "r_rabbitskin", 3, now - 100.0)
	assert_eq(c.inventory.items.filter(func(it): return it["id"] == "r_rabbitskin").size(), 1, "兩場戰鬥的兔皮同一格")
	var id := _corpse_of(owner)
	var on_corpse: Array = _corpse(id)["items"].filter(func(it): return str(it.get("id", "")) == "r_rabbitskin")
	assert_eq(on_corpse.size(), 1)
	assert_eq(on_corpse[0].get("lots", []).size(), 2, "屍體上保留每一批")
	host().give_item(c, "r_rabbitskin", 1, now)   # 復活後又打到一張
	ok_p(owner, "loot_corpse", { "corpse_id": id })
	var skins: Array = c.inventory.items.filter(func(it): return it["id"] == "r_rabbitskin")
	assert_eq(skins.size(), 1, "撿回來併進同一格")
	assert_eq(int(skins[0]["n"]), 6)
	assert_eq(skins[0]["lots"], [{ "born_s": now - 500.0, "n": 2 }, { "born_s": now - 100.0, "n": 3 }, { "born_s": now, "n": 1 }])
