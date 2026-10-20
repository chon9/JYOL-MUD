extends "res://tests/unit/test_world_fixture.gd"
## M2_PLAN 4.6.8：角色護照 — 簽章往返（含 JSON 存讀）、竄改偵測、還原的原因碼順序、刪檔後還原、送出時機

func _secret() -> String:
	return str(ws.world.get("world_secret", ""))

func _wid() -> String:
	return str(ws.world.get("world_id", ""))

## JSON 存讀一次（客戶端存檔、手動傳檔都會經過）
func _json_trip(d: Dictionary) -> Dictionary:
	var j := JSON.new()
	assert_eq(j.parse(JSON.stringify(d, "\t")), OK, "json parse")
	return j.data

## 從主機上的角色檔做一份護照（不經 intent）
func _passport_of_file(char_id: String, online_bump := 0.0) -> Dictionary:
	var r: Dictionary = sm.load_character(ws.world_id, s().identity, char_id)
	assert_true(r.get("ok", false), "load char file " + char_id)
	var d: Dictionary = Character.from_dict(r["data"]).to_dict()
	d["online_s"] = float(d["online_s"]) + online_bump
	return Passport.make(_secret(), _wid(), d, ws.world_time())

func test_sign_roundtrip_with_json() -> void:
	if not game_ok():
		return
	var c = make_char("護照甲")
	c.counters["last_meditate_s"] = 12.0
	c.flags["some_flag"] = 3
	c.online_s = 123.456789
	var p: Dictionary = host().make_passport(c)
	assert_eq(int(p["v"]), 1)
	for k in Passport.REQUIRED:
		assert_has(p, k, "passport key")
	assert_eq(p["char_id"], str(c.id))
	assert_eq(p["identity"], s().identity)
	assert_true(Passport.verify(_secret(), _wid(), p), "verify fresh")
	var back := _json_trip(p)
	assert_true(Passport.verify(_secret(), _wid(), back), "verify after JSON save/load")
	assert_eq(Passport.canonical(back["char"]), Passport.canonical(p["char"]), "canonical stable across JSON")
	# 改一個數字 → 驗章失敗
	var bad := _json_trip(p)
	bad["char"]["money"] = int(bad["char"]["money"]) + 1
	assert_false(Passport.verify(_secret(), _wid(), bad), "tampered money")
	var bad2 := _json_trip(p)
	bad2["char"]["attrs"]["str"] = 99
	assert_false(Passport.verify(_secret(), _wid(), bad2), "tampered attr")
	# 別的世界的祕密驗不過
	assert_false(Passport.verify("other_secret", _wid(), p), "other world secret")
	assert_false(Passport.verify(_secret(), "other_world", p), "other world id")

func test_restore_reason_order() -> void:
	if not game_ok():
		return
	var a = make_char("護照甲")
	var a_id := str(a.id)
	var good: Dictionary = host().make_passport(a)
	# char_active：要還原的角色正選著
	assert_eq(reason("passport_restore", { "passport": good }), "char_active")
	make_char("護照乙")   # 換角：甲存檔、離開
	assert_eq(str(ch().name), "護照乙")
	# passport_bad_format
	var f1 := good.duplicate(true)
	f1.erase("sig")
	assert_eq(reason("passport_restore", { "passport": f1 }), "passport_bad_format")
	var f2 := good.duplicate(true)
	f2["v"] = 2
	assert_eq(reason("passport_restore", { "passport": f2 }), "passport_bad_format")
	var f3 := good.duplicate(true)
	f3["char"] = "nope"
	assert_eq(reason("passport_restore", { "passport": f3 }), "passport_bad_format")
	assert_eq(reason("passport_restore", { "passport": {} }), "passport_bad_format")
	# passport_wrong_world
	var w := good.duplicate(true)
	w["world_id"] = "another_world"
	assert_eq(reason("passport_restore", { "passport": w }), "passport_wrong_world")
	# passport_wrong_identity
	var idp := good.duplicate(true)
	idp["identity"] = "local_ffffffffffffffffffffffffffffffff"
	idp["char"]["identity"] = "local_ffffffffffffffffffffffffffffffff"
	assert_eq(reason("passport_restore", { "passport": idp }), "passport_wrong_identity")
	# passport_bad_sig
	var bs := _json_trip(good)
	bs["char"]["money"] = int(bs["char"]["money"]) + 1000
	assert_eq(reason("passport_restore", { "passport": bs }), "passport_bad_sig")
	# passport_not_needed：主機上的檔案存在且 online_s ≥ 護照的
	assert_eq(reason("passport_restore", { "passport": _json_trip(good) }), "passport_not_needed")
	# 護照比較新 → 還原成功、覆寫主機檔
	var newer := _passport_of_file(a_id, 500.0)
	clear_events()
	assert_true(send("passport_restore", { "passport": _json_trip(newer) }).get("ok", false), "restore newer")
	assert_eq(lastp("passport_restored").get("name", ""), "護照甲")
	var r: Dictionary = sm.load_character(ws.world_id, s().identity, a_id)
	assert_true(absf(float(r["data"]["online_s"]) - float(newer["char"]["online_s"])) < 0.01, "file overwritten")

func test_restore_after_file_deleted() -> void:
	if not game_ok():
		return
	var a = make_char("護照甲")
	var a_id := str(a.id)
	a.money = 777
	var p: Dictionary = _json_trip(host().make_passport(a))
	make_char("護照乙")
	ok("char_delete", { "char_id": a_id, "confirm_name": "護照甲" })
	assert_false(host().char_store.has_char(s().identity, a_id), "deleted")
	assert_true(host().char_ref_by_name("護照甲").is_empty(), "name freed")
	clear_events()
	assert_true(send("passport_restore", { "passport": p }).get("ok", false), "restore deleted char")
	assert_eq(lastp("passport_restored").get("name", ""), "護照甲")
	assert_true(host().char_store.has_char(s().identity, a_id), "file back")
	assert_eq(host().char_ref_by_name("護照甲").get("char_id", ""), a_id, "char_names restored")
	var ids: Array = []
	for row in cs.char_list:
		ids.append(str(row.get("id", row.get("char_id", ""))))
	assert_has(ids, a_id, "char list pushed")
	ok("char_select", { "char_id": a_id })
	assert_eq(int(ch().money), 777)
	assert_true(host().char_store.name_taken("護照甲"), "name taken again")

## M2 審查：刪角後用比刪除時舊的護照還原 → passport_not_needed（擋洗 PK、複製物品）；用最新的護照仍可還原
func test_restore_deleted_rejects_older_passport() -> void:
	if not game_ok():
		return
	var a = make_char("護照甲")
	var a_id := str(a.id)
	var old: Dictionary = _json_trip(host().make_passport(a))
	a.online_s = float(a.online_s) + 600.0
	a.pk = 1
	a.killing_intent = 100
	make_char("護照乙")   # 換角：甲存檔（online_s +600、PK 1）並送出最新護照
	var latest: Dictionary = sm.load_passport(_wid(), a_id)["data"]
	assert_eq(int(latest["char"]["pk"]), 1, "latest passport has the kill")
	ok("char_delete", { "char_id": a_id, "confirm_name": "護照甲" })
	assert_true(sm.deleted_character_online_s(ws.world_id, s().identity, a_id) >= float(a.online_s) - 0.01, "archive seen")
	assert_eq(reason("passport_restore", { "passport": old }), "passport_not_needed", "pre-kill passport refused")
	assert_false(host().char_store.has_char(s().identity, a_id), "nothing written")
	assert_true(send("passport_restore", { "passport": _json_trip(latest) }).get("ok", false), "latest passport restores")
	ok("char_select", { "char_id": a_id })
	assert_eq(int(ch().pk), 1, "PK kept")

## M2 審查：名字已被另一個仍存在的角色用了 → passport_name_taken，不寫檔、索引不動
func test_restore_name_taken_refused() -> void:
	if not game_ok():
		return
	var a = make_char("護照甲")
	var a_id := str(a.id)
	var p: Dictionary = _json_trip(host().make_passport(a))
	make_char("護照乙")
	ok("char_delete", { "char_id": a_id, "confirm_name": "護照甲" })
	var c = make_char("護照甲")   # 名字已釋出，被新角色取走
	var c_id := str(c.id)
	assert_eq(reason("passport_restore", { "passport": p }), "passport_name_taken")
	assert_false(host().char_store.has_char(s().identity, a_id), "not written")
	assert_eq(host().char_ref_by_name("護照甲").get("char_id", ""), c_id, "index unchanged")

## M2 審查：刪除後還原也要遵守每個身分 3 個角色的上限
func test_restore_deleted_respects_char_limit() -> void:
	if not game_ok():
		return
	var a = make_char("護照甲")
	var a_id := str(a.id)
	var p: Dictionary = _json_trip(host().make_passport(a))
	make_char("護照乙")
	ok("char_delete", { "char_id": a_id, "confirm_name": "護照甲" })
	make_char("護照丙")
	make_char("護照丁")
	assert_eq(host().char_store.count(s().identity), Character.MAX_CHARS_PER_IDENTITY)
	assert_eq(reason("passport_restore", { "passport": p }), "too_many_chars")
	assert_false(host().char_store.has_char(s().identity, a_id), "not written")

func test_passport_request_and_client_save() -> void:
	if not game_ok():
		return
	var a = make_char("護照甲")
	assert_eq(reason("passport_request", { "char_id": "ch_nope" }), "no_such_char")
	clear_events()
	ok("passport_request", { "char_id": str(a.id) })
	var e := last("passport")
	assert_true(e.get("ui", false), "passport is a ui event")
	assert_eq(str(e.get("p", {}).get("char_id", "")), str(a.id))
	# ClientState 已存到 user://passports/<world_id>/<char_id>.json
	assert_has(sm.list_passports(_wid()), str(a.id), "saved on client")
	var lp: Dictionary = sm.load_passport(_wid(), str(a.id))
	assert_true(lp["ok"], "load_passport")
	assert_false(lp["data"].has("peer"), "peer stripped")
	assert_true(Passport.verify(_secret(), _wid(), lp["data"]), "saved passport verifies")
	assert_eq(sm.load_passport(_wid(), "ch_none")["ok"], false)
	assert_eq(reason("passport_import", { "passport": lp["data"] }), "foreign_disabled")

func test_passport_sent_on_switch_and_autosave() -> void:
	if not game_ok():
		return
	var a = make_char("護照甲")
	clear_events()
	make_char("護照乙")   # 換角 → 甲的護照
	var got: Array = []
	for e in evs("passport"):
		got.append(str(e["p"].get("char_id", "")))
	assert_has(got, str(a.id), "passport on char switch")
	var peer := add_player("護照丙")
	clear_events_for(peer)
	host().on_autosave()
	ws.flush()
	assert_eq(evs_for(peer, "passport").size(), 1, "remote gets passport on autosave")
	var rp: Dictionary = evs_for(peer, "passport")[0]["p"]
	assert_eq(str(rp.get("name", "")), "護照丙")
	assert_true(Passport.verify(_secret(), _wid(), _json_trip(rp)), "remote passport verifies")

func test_restore_wrong_owner_remote() -> void:
	if not game_ok():
		return
	var a = make_char("護照甲")
	var p := _json_trip(host().make_passport(a))
	var peer := add_player("護照丁")
	assert_eq(reason_as(peer, "passport_restore", { "passport": p }), "char_active", "active char checked first")
	make_char("護照乙")
	assert_eq(reason_as(peer, "passport_restore", { "passport": p }), "passport_wrong_identity")

## 物品堆疊改版前簽的護照（物品沒有 lots）仍然驗得過；竄改照樣抓得到
func test_legacy_passport_without_lots() -> void:
	if not game_ok():
		return
	var c = make_char("舊護照")
	var p: Dictionary = _json_trip(host().make_passport(c))
	for it in p["char"]["inventory"]["items"]:
		it.erase("lots")
	# 多一格被舊版拆開的同物品（舊存檔常見）→ 新格式的正規化字串會不同，只能靠舊格式簽章驗
	var first: Dictionary = p["char"]["inventory"]["items"][0]
	p["char"]["inventory"]["items"].append({ "uid": "it_legacy01", "id": str(first["id"]), "n": 1, "born_s": 5.0 })
	p["sig"] = (_secret() + _wid() + Passport.canonical(p["char"], true)).sha256_text()   # 舊版程式算的簽章
	assert_true(Passport.verify(_secret(), _wid(), p), "legacy passport verifies")
	var bad := _json_trip(p)
	bad["char"]["inventory"]["items"][0]["n"] = int(bad["char"]["inventory"]["items"][0]["n"]) + 1
	assert_false(Passport.verify(_secret(), _wid(), bad), "tampered legacy item count")

## M3b 審查：M3b 以前簽的護照（角色沒有 bank、guild、sect_rank、sect_rank_pending）仍然驗得過；竄改照樣抓得到
func test_pre_m3b_passport_verifies() -> void:
	if not game_ok():
		return
	var c = make_char("前護照")
	var p: Dictionary = _json_trip(host().make_passport(c))
	for k in Passport.M3B_KEYS:
		p["char"].erase(k)
	# 舊版程式的正規化字串：from_dict → to_dict 沒有 M3b 欄位
	var d: Dictionary = Character.from_dict(p["char"]).to_dict()
	for k in Passport.M3B_KEYS:
		d.erase(k)
	p["sig"] = (_secret() + _wid() + JSON.stringify(Passport._normalize(d), "", true)).sha256_text()
	assert_false(Passport.sign(_secret(), _wid(), p["char"]) == str(p["sig"]), "新格式的簽章不同（不然測不到）")
	assert_true(Passport.verify(_secret(), _wid(), p), "pre-M3b passport verifies")
	var bad := _json_trip(p)
	bad["char"]["money"] = int(bad["char"]["money"]) + 100
	assert_false(Passport.verify(_secret(), _wid(), bad), "tampered pre-M3b money")
	# 同時是堆疊改版前（沒有 lots）＋M3b 以前
	var p2: Dictionary = _json_trip(p)
	for it in p2["char"]["inventory"]["items"]:
		it.erase("lots")
	p2["sig"] = (_secret() + _wid() + Passport.canonical(p2["char"], true, true)).sha256_text()
	assert_true(Passport.verify(_secret(), _wid(), p2), "legacy + pre-M3b verifies")

## M3c 整合：0.5.0.0（M3b）簽的護照——角色沒有 appearance、裝備只有 WEAPON／ARMOR 兩格——仍然驗得過；竄改照樣抓得到
func test_pre_m3c_passport_verifies() -> void:
	if not game_ok():
		return
	var c = make_char("舊版護照")
	var p: Dictionary = _json_trip(host().make_passport(c))
	p["char"].erase("appearance")
	var eq: Dictionary = p["char"]["inventory"]["equipped"]
	p["char"]["inventory"]["equipped"] = { "WEAPON": eq.get("WEAPON", ""), "ARMOR": eq.get("ARMOR", "") }
	# 0.5.0.0 的正規化字串：from_dict → to_dict 沒有 appearance、裝備兩格
	var d: Dictionary = Character.from_dict(p["char"]).to_dict()
	d.erase("appearance")
	var deq: Dictionary = d["inventory"]["equipped"]
	d["inventory"]["equipped"] = { "WEAPON": deq.get("WEAPON", ""), "ARMOR": deq.get("ARMOR", "") }
	p["sig"] = (_secret() + _wid() + JSON.stringify(Passport._normalize(d), "", true)).sha256_text()
	assert_false(Passport.sign(_secret(), _wid(), p["char"]) == str(p["sig"]), "新格式的簽章不同（不然測不到）")
	assert_true(Passport.verify(_secret(), _wid(), p), "pre-M3c passport verifies")
	var bad := _json_trip(p)
	bad["char"]["money"] = int(bad["char"]["money"]) + 100
	assert_false(Passport.verify(_secret(), _wid(), bad), "tampered pre-M3c money")
	var bad2 := _json_trip(p)
	bad2["char"]["inventory"]["equipped"]["WEAPON"] = "w_sb_yitian"
	assert_false(Passport.verify(_secret(), _wid(), bad2), "tampered pre-M3c weapon")
	# M3c 審查：舊護照（只有 WEAPON／ARMOR）加上新欄位（HEAD、RING…）→ 不再當成 M3c 以前的格式，簽章驗不過
	var bad3 := _json_trip(p)
	var uid := ""
	for it in bad3["char"]["inventory"]["items"]:
		uid = str(it.get("uid", ""))
		break
	bad3["char"]["inventory"]["equipped"]["HEAD"] = uid if uid != "" else "u_fake"
	assert_false(Passport.verify(_secret(), _wid(), bad3), "pre-M3c passport + unsigned HEAD slot is rejected")
	var bad4 := _json_trip(p)
	bad4["char"]["inventory"]["equipped"]["RING"] = ""
	assert_false(Passport._is_pre_m3c(bad4["char"]), "extra slot key → not the pre-M3c format")

## M3c 審查：神兵持有者刪角 → 登記釋放；神兵給了別人之後再用舊護照還原 → 還原的角色身上沒有那把神兵（全服唯一）。
## 沒有人接手時還原 → 神兵回到他身上並重新登記
func test_restore_deleted_divine_holder_no_duplicate() -> void:
	if not game_ok():
		return
	var loot = host().get("loot")
	if loot == null:
		return
	var a = make_char("神兵甲")
	var a_id := str(a.id)
	assert_true(loot.grant_divine(s(), "w_sb_yitian").get("ok", false), "grant to 甲")
	var p: Dictionary = _json_trip(host().make_passport(a))
	var b = make_char("神兵乙")
	ok("char_delete", { "char_id": a_id, "confirm_name": "神兵甲" })
	assert_eq(loot.holder_of("w_sb_yitian"), "", "deleting the holder releases the registry")
	assert_true(loot.grant_divine(s(), "w_sb_yitian").get("ok", false), "乙 now gets the sword")
	assert_eq(loot.holder_of("w_sb_yitian"), str(b.id))
	assert_true(send("passport_restore", { "passport": p }).get("ok", false), "restore 甲")
	var back = host().char_store.load_char(s().identity, a_id)
	assert_true(back != null, "甲 file back")
	assert_eq(back.inventory.count("w_sb_yitian"), 0, "restored 甲 does not bring a second 倚天劍")
	assert_eq(loot.holder_of("w_sb_yitian"), str(b.id), "registry still 乙")

func test_restore_deleted_divine_unclaimed_comes_back() -> void:
	if not game_ok():
		return
	var loot = host().get("loot")
	if loot == null:
		return
	var a = make_char("神兵丙")
	var a_id := str(a.id)
	assert_true(loot.grant_divine(s(), "w_sb_tulong").get("ok", false))
	var p: Dictionary = _json_trip(host().make_passport(a))
	make_char("神兵丁")
	ok("char_delete", { "char_id": a_id, "confirm_name": "神兵丙" })
	assert_true(send("passport_restore", { "passport": p }).get("ok", false), "restore 丙")
	var back = host().char_store.load_char(s().identity, a_id)
	assert_eq(back.inventory.count("w_sb_tulong"), 1, "nobody took it: it comes back")
	assert_eq(loot.holder_of("w_sb_tulong"), a_id, "re-registered")
