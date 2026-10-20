extends "res://tests/unit/test_world_fixture.gd"
## M3C2_PLAN §5.7、R13（WP-CARRY）：單機讀 Steam 身分的角色 —— Steam 有／沒有 → 清單與 needs_confirm；
## 換身分後存檔寫回 steam_* 資料夾；非 OFFLINE 回 alt_identity_denied。

const STEAM_ID := "76561190000000001"
const STEAM_IDENT := "steam_76561190000000001"

var _old_mode := 0
var steam_char_id := ""

func before_each() -> void:
	world_name = "w_m3c2_offsteam"
	super.before_each()
	_old_mode = NetworkManager.mode
	NetworkManager.mode = NetworkManager.Mode.OFFLINE

func after_each() -> void:
	if ws.game != null:
		ws.game.test_steam_id = ""
	NetworkManager.mode = _old_mode
	super.after_each()

## 世界資料夾裡手動放一個 steam_<id> 的角色（朋友把整個世界資料夾給你的情況）
func _plant_steam_char(char_name := "蒸汽俠") -> String:
	var d: Dictionary = ch().to_dict()
	d["id"] = "ch_steam0001"
	d["identity"] = STEAM_IDENT
	d["name"] = char_name
	d["money"] = 4321
	assert_eq(sm.save_character(ws.world_id, STEAM_IDENT, d), OK, "plant steam char")
	host().char_store.register_name(Character.from_dict(d))
	return "ch_steam0001"

func _alt_rows() -> Array:
	var out: Array = []
	for r in cs.char_list:
		if bool(r.get("alt", false)):
			out.append(r)
	return out

func test_steam_not_running_lists_all_steam_folders_with_confirm() -> void:
	if not game_ok():
		return
	make_char("本機俠")
	steam_char_id = _plant_steam_char()
	host().test_steam_id = "none"
	var alts: Array = host().alt_identities(s())
	assert_eq(alts.size(), 1, str(alts))
	assert_eq(str(alts[0]["identity"]), STEAM_IDENT)
	assert_eq(bool(alts[0]["needs_confirm"]), true)
	ok("char_list")
	var rows := _alt_rows()
	assert_eq(rows.size(), 1, "alt row in list")
	assert_eq(str(rows[0]["char_id"]), steam_char_id)
	assert_eq(str(rows[0]["identity"]), STEAM_IDENT)
	assert_eq(bool(rows[0]["needs_confirm"]), true)
	assert_eq(str(rows[0]["name"]), "蒸汽俠")

func test_steam_running_only_own_id_no_confirm() -> void:
	if not game_ok():
		return
	make_char("本機俠")
	_plant_steam_char()
	host().test_steam_id = STEAM_ID
	var alts: Array = host().alt_identities(s())
	assert_eq(alts.size(), 1)
	assert_eq(bool(alts[0]["needs_confirm"]), false)
	host().test_steam_id = "76561190000000999"   # 登入的是別的帳號，世界裡沒有他的資料夾
	assert_eq(host().alt_identities(s()).size(), 0, "other account: nothing")

func test_select_switches_identity_and_saves_back_to_steam_folder() -> void:
	if not game_ok():
		return
	make_char("本機俠")
	var local_ident := s().identity
	var local_ids: Array = sm.list_character_ids(ws.world_id, local_ident)
	var cid := _plant_steam_char()
	host().test_steam_id = "none"
	ok("char_select", { "char_id": cid, "identity": STEAM_IDENT })
	assert_eq(s().identity, STEAM_IDENT, "session identity switched")
	assert_eq(str(ch().id), cid)
	assert_eq(int(ch().money), 4321)
	assert_true(ws.world["known_identities"].has(STEAM_IDENT), "known identity recorded")
	goto("xx_inn")
	ch().money = 9999
	host().save_all()
	var r: Dictionary = sm.load_character(ws.world_id, STEAM_IDENT, cid)
	assert_true(r["ok"], "steam file")
	assert_eq(int(r["data"]["money"]), 9999, "saved back to steam_* folder")
	assert_eq(str(r["data"]["location"]["room"]), "xx_inn")
	assert_eq(str(r["data"]["identity"]), STEAM_IDENT)
	assert_eq(sm.list_character_ids(ws.world_id, local_ident), local_ids, "no extra char in local folder")
	# 清單：目前身分是 Steam；原本的本機身分可以換回來
	ok("char_list")
	var own_ident := ""
	for row in cs.char_list:
		if not bool(row.get("alt", false)):
			own_ident = str(row.get("identity", ""))
	assert_eq(own_ident, STEAM_IDENT)
	assert_eq(cs.active_identity, STEAM_IDENT, "client mirror")
	var back := ""
	for row in _alt_rows():
		if str(row.get("identity", "")) == local_ident:
			back = str(row.get("char_id", ""))
	assert_true(back != "", "local identity offered to switch back")
	ok("char_select", { "char_id": back, "identity": local_ident })
	assert_eq(s().identity, local_ident)
	var r2: Dictionary = sm.load_character(ws.world_id, STEAM_IDENT, cid)
	assert_eq(int(r2["data"]["money"]), 9999, "switch out saved steam char")

func test_denied_when_not_offline_or_unknown() -> void:
	if not game_ok():
		return
	make_char("本機俠")
	var cid := _plant_steam_char()
	host().test_steam_id = "none"
	assert_eq(reason("char_select", { "char_id": cid, "identity": "steam_76561190000000777" }), "alt_identity_denied")
	NetworkManager.mode = NetworkManager.Mode.ENET_HOST
	assert_eq(host().alt_identities(s()).size(), 0, "hosted: none")
	assert_eq(reason("char_select", { "char_id": cid, "identity": STEAM_IDENT }), "alt_identity_denied")
	assert_true(s().identity.begins_with("local_"), "identity unchanged")
	# 同身分（空或相同）照舊
	NetworkManager.mode = NetworkManager.Mode.OFFLINE
	assert_eq(reason("char_select", { "char_id": "ch_nope", "identity": s().identity }), "no_such_char")
