extends RefCounted
## WP-HOST 的 M2 intent（M2_PLAN 4.2）：server_opts_get／server_opts_set／admin_kick／passport_request／
## passport_restore／passport_import。由 GameHost 以路徑 load() 後呼叫 register()（H4）。
## M3c2 WP-CARRY：passport_import 實作（外來角色，M3C2_PLAN §5.6）；server_opts_set 的 allow_foreign_characters 在這裡處理
## 這幾個 intent 都不需要角色、也不限閒置（旗標 0）。

static func register(host: GameHost) -> void:
	host.register(Protocol.I_SERVER_OPTS_GET, func(s: Session, a: Dictionary) -> Dictionary: return opts_get(host, s, a), 0)
	host.register(Protocol.I_SERVER_OPTS_SET, func(s: Session, a: Dictionary) -> Dictionary: return opts_set(host, s, a), 0)
	host.register(Protocol.I_ADMIN_KICK, func(s: Session, a: Dictionary) -> Dictionary: return admin_kick(host, s, a), 0)
	host.register(Protocol.I_PASSPORT_REQUEST, func(s: Session, a: Dictionary) -> Dictionary: return passport_request(host, s, a), 0)
	host.register(Protocol.I_PASSPORT_RESTORE, func(s: Session, a: Dictionary) -> Dictionary: return passport_restore(host, s, a), 0)
	host.register(Protocol.I_PASSPORT_IMPORT, func(s: Session, a: Dictionary) -> Dictionary: return passport_import(host, s, a), 0)

static func opts_get(host: GameHost, s: Session, _a: Dictionary) -> Dictionary:
	return host.admin.opts_get(s)

static func opts_set(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	if str(a["key"]) == OPT_ALLOW_FOREIGN:   # M3c2 WP-CARRY §5.3
		return set_allow_foreign(host, s, str(a["value"]))
	return host.admin.opts_set(s, str(a["key"]), str(a["value"]))

static func admin_kick(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	return host.admin.kick(s, int(a["peer"]), bool(a.get("ban", false)))

## no_such_char（不是我的角色）→ 選著的角色先存檔 → 送護照
static func passport_request(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var char_id := str(a["char_id"])
	if not host.char_store.has_char(s.identity, char_id):
		return GameHost.fail("no_such_char")
	var ch = host.char_store.load_char(s.identity, char_id)
	if ch == null:
		return GameHost.fail("no_such_char")
	if s.character != null and str(s.character.id) == char_id:
		host.save_char(s.character)
	host.send_passport(s, ch)
	return GameHost.ok()

## char_active → passport_bad_format → passport_wrong_world → passport_wrong_identity → passport_bad_sig
## → passport_not_needed（主機檔或刪除封存的 online_s 比護照新）→ too_many_chars（刪除後還原時）
## → passport_name_taken（名字已屬於另一個仍存在的角色）→ 寫入角色檔、補 char_names → passport_restored、s2c_char_list
static func passport_restore(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var pp: Dictionary = a["passport"]
	var char_id := str(pp.get("char_id", "")) if typeof(pp.get("char_id")) == TYPE_STRING else ""
	if char_id != "" and host.session_for_char(char_id) != null:
		return GameHost.fail("char_active")
	# 還在（斷線者自動防的）戰鬥裡：還原的檔案會在戰鬥結束時被 _settle_player 的存檔蓋掉（M2 審查）
	if char_id != "" and host.battles != null and host.battles.battle_of_char(char_id) != 0:
		return GameHost.fail("char_active")
	if Passport.check_format(pp) != "":
		return GameHost.fail("passport_bad_format")
	var world_id := str(host.ws.world.get("world_id", host.ws.world_id))
	if str(pp["world_id"]) != world_id:
		return GameHost.fail("passport_wrong_world")
	var c: Dictionary = pp["char"]
	if str(pp["identity"]) != s.identity or str(c.get("identity", "")) != s.identity:
		return GameHost.fail("passport_wrong_identity")
	var secret := str(host.ws.world.get("world_secret", ""))
	if not Passport.verify(secret, world_id, pp):
		return GameHost.fail("passport_bad_sig")
	var restored = Character.from_dict(c)
	if restored == null or str(restored.id) != char_id:
		return GameHost.fail("passport_bad_format")
	if str(restored.origin_world) != "" and not host.foreign_allowed():
		return GameHost.fail(Protocol.R_FOREIGN_CHAR_BLOCKED)
	# M3c2 審查：外來角色已被同一個來源角色較新的匯入取代（登記指向另一個還在的本地角色）→ 舊護照不能再還原
	var fe_repoint: Variant = null
	var fx: Variant = restored.ext.get("foreign")
	if fx is Dictionary:
		var fkey := str(fx.get("world_id", "")) + FOREIGN_KEY_SEP + str(fx.get("char_id", ""))
		var fe: Variant = foreign_registry(host).get(fkey)
		if fe is Dictionary and str(fe.get("char_id", "")) != char_id:
			if host.char_store.has_char(str(fe.get("identity", "")), str(fe.get("char_id", ""))):
				return GameHost.fail(Protocol.R_FOREIGN_SUPERSEDED)
			fe_repoint = fe   # 取代它的那個也刪了：還原成功後登記改指回這個角色
	var exists: bool = host.char_store.has_char(s.identity, char_id)
	if exists:
		var r: Dictionary = SaveManager.load_character(host.ws.world_id, s.identity, char_id)
		if r.get("ok", false) and r.get("data") is Dictionary:
			var on_host := float(r["data"].get("online_s", 0.0))
			if on_host >= float(restored.online_s):
				return GameHost.fail("passport_not_needed")
	else:
		# 刪除後還原（M2 審查）：護照不能比 deleted/ 裡的封存舊；否則刪角再用舊護照就能洗掉 PK值／殺氣／善惡、
		# 或讓朋友翻走屍體後還原死前的身上物品。用刪除時那份（最新的）護照還原仍然可以（online_s 相等）。
		var archived: float = SaveManager.deleted_character_online_s(host.ws.world_id, s.identity, char_id)
		if archived >= 0.0 and float(restored.online_s) < archived:
			return GameHost.fail("passport_not_needed")
		if host.char_store.count(s.identity) >= Character.MAX_CHARS_PER_IDENTITY:
			return GameHost.fail("too_many_chars")
	# 名字已被「另一個仍存在的角色」占用：拒絕，不寫檔（M2 審查：同名兩人會讓密語、飛鴿、屍體授權找錯人）
	var key := CharacterStore.name_key(str(restored.name))
	var holder: Dictionary = host.char_store.names().get(key, {})
	var holder_id := str(holder.get("char_id", ""))
	var held_by_other := not holder.is_empty() and holder_id != char_id \
			and host.char_store.has_char(str(holder.get("identity", "")), holder_id)
	if held_by_other:
		return GameHost.fail("passport_name_taken")
	restored.identity = s.identity
	# M3c 審查：神兵全服唯一——護照裡的神兵若已登記在別人名下（刪角後掉給了別人）就拿掉；沒有人登記的歸還原的人
	host.m2_call(host.get("loot"), "on_char_restored", [restored])
	if host.save_char(restored) != OK:
		return GameHost.fail("drop:save_failed")
	host.char_store.register_name(restored)
	if fe_repoint is Dictionary:
		fe_repoint["char_id"] = char_id
		fe_repoint["identity"] = s.identity
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_PASSPORT_RESTORED, { "name": str(restored.name) })
	host.push_char_list(s)
	host.ws.save_now()
	return GameHost.ok({ "char_id": char_id })

# ==== M3c2 WP-CARRY ====（M3C2_PLAN §5.3、§5.6）

const FOREIGN_KEY_SEP := "/"
const OPT_ALLOW_FOREIGN := "allow_foreign_characters"
const ALLOW_FOREIGN_LABEL := "允許外來角色"
## M3c2 第二輪審查：外來神兵（預設關；只能改 options.json）、每個身分最多幾個不同的來源角色【設計提案】
const OPT_ALLOW_FOREIGN_DIVINE := "allow_foreign_divine"
const FOREIGN_SOURCES_PER_IDENTITY := 3

## 這個身分在本世界登記過幾個不同的來源角色（含已刪除的）
static func foreign_sources_of(host: GameHost, identity: String) -> int:
	var n := 0
	var reg: Dictionary = foreign_registry(host)
	for k in reg:
		var e: Variant = reg[k]
		if e is Dictionary and str(e.get("identity", "")) == identity:
			n += 1
	return n

## 拿掉角色身上所有的神兵（回傳名稱清單；同名多件各列一次）
static func strip_divine(host: GameHost, ch) -> Array:
	var names: Array = []
	for it in (ch.inventory.items as Array).duplicate():
		var iid := str(it.get("id", ""))
		if bool(CharData.row(host.tables, "items", iid).get("divine", false)):
			ch.inventory.remove(str(it.get("uid", "")), int(it.get("n", 1)))
			names.append(host.item_name(iid))
	return names

## 外來角色登記（world.json foreign_imports）
static func foreign_registry(host: GameHost) -> Dictionary:
	var d: Variant = host.ws.world.get("foreign_imports")
	if not (d is Dictionary):
		d = {}
		host.ws.world["foreign_imports"] = d
	return d

## 順序（§5.6）：foreign_disabled → foreign_bad_data（格式）→ foreign_same_world → foreign_bad_data（截斷）
## → foreign_not_newer／foreign_owned／char_active（重複匯入）／too_many_chars（新角色）／foreign_quota（來源角色數）
## → bad_value:new_name／passport_name_taken → 寫入 → foreign_imported（ui）、s2c_char_list
static func passport_import(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	if not host.foreign_allowed():
		return GameHost.fail("foreign_disabled")
	var pp: Dictionary = a["passport"]
	if Passport.check_format(pp) != "":
		return GameHost.fail(Protocol.R_FOREIGN_BAD_DATA)
	var world_id := str(host.ws.world.get("world_id", host.ws.world_id))
	if from_this_world(host, pp, world_id):
		return GameHost.fail(Protocol.R_FOREIGN_SAME_WORLD)
	var san: Dictionary = ForeignImport.sanitize(pp, host.tables, host.rules, host.options)
	if not bool(san.get("ok", false)):
		return GameHost.fail(Protocol.R_FOREIGN_BAD_DATA)
	var origin_char := str(pp["char_id"])
	var key := str(pp["world_id"]) + FOREIGN_KEY_SEP + origin_char
	var reg: Dictionary = foreign_registry(host)
	var saved_s := float(pp.get("saved_s", 0.0))
	var replace_id := ""
	var e: Variant = reg.get(key)
	if e is Dictionary:
		var local_id := str(e.get("char_id", ""))
		var local_ident := str(e.get("identity", ""))
		var still := local_id != "" and host.char_store.has_char(local_ident, local_id)
		# M3c2 審查（R12）：登記一直留著（本地角色刪掉也一樣）→ 同一份或較舊的護照永遠不能再匯一次
		# （否則「匯入 → 東西給別人 → 刪角 → 再匯同一份」就能複製）
		if not is_finite(saved_s) or saved_s <= CharData.to_float(e.get("saved_s"), 0.0):
			return GameHost.fail(Protocol.R_FOREIGN_NOT_NEWER)
		# M3c2 第三輪審查：登記永遠屬於第一次匯入的身分（本地角色刪掉也一樣）——否則別的身分接手登記，
		# 原身分的來源角色名額就空出一格【設計提案】
		if local_ident != s.identity:
			return GameHost.fail(Protocol.R_FOREIGN_OWNED)
		if still:
			if host.session_for_char(local_id) != null:
				return GameHost.fail("char_active")
			if host.battles != null and host.battles.battle_of_char(local_id) != 0:
				return GameHost.fail("char_active")
			replace_id = local_id
	if replace_id == "" and host.char_store.count(s.identity) >= Character.MAX_CHARS_PER_IDENTITY:
		return GameHost.fail("too_many_chars")
	# M3c2 第二輪審查：檔案沒有簽章、來源鍵（world_id／char_id）可以亂改 → 每個身分在本世界一輩子最多帶進
	# FOREIGN_SOURCES_PER_IDENTITY 個「不同的來源角色」（同一個來源的更新不算；登記刪角後也留著）【設計提案】
	if not (e is Dictionary) and foreign_sources_of(host, s.identity) >= FOREIGN_SOURCES_PER_IDENTITY:
		return GameHost.fail(Protocol.R_FOREIGN_QUOTA)
	# 名字：new_name（驗證同 char_create）否則護照的名字；被「別的」存在角色佔用 → passport_name_taken
	var d: Dictionary = san["char"]
	var char_name := str(d.get("name", ""))
	if a.has("new_name"):
		char_name = str(a["new_name"])
		if CharacterFactory.validate_name(char_name) != "":
			return GameHost.fail("bad_value:new_name")
	elif CharacterFactory.validate_name(char_name) != "":
		return GameHost.fail("passport_name_taken")   # 原名在本世界不合法：同樣請玩家改名
	var holder: Dictionary = host.char_store.names().get(CharacterStore.name_key(char_name), {})
	var holder_id := str(holder.get("char_id", ""))
	if not holder.is_empty() and holder_id != replace_id 			and host.char_store.has_char(str(holder.get("identity", "")), holder_id):
		return GameHost.fail("passport_name_taken")
	# 寫入
	var ch = Character.from_dict(d)
	if ch == null:
		return GameHost.fail(Protocol.R_FOREIGN_BAD_DATA)
	ch.name = char_name
	ch.identity = s.identity
	ch.id = replace_id if replace_id != "" else host.new_id("ch_")
	var now := host.now_s()
	if ch.ext.get("foreign") is Dictionary:
		ch.ext["foreign"]["imported_s"] = now
	ch.counters["last_birthday_year"] = int(host.clock().get("year", 0))   # 生日看本世界的年份（不在匯入當下多長一點）
	# M3c2 審查：每件物品換成本主機發的新編號（護照裡的 uid 可能重複或和本世界的撞號）
	renumber_items(host, ch)
	var dropped: Array = (san["dropped"] as Array).duplicate()
	var kept_local_goods := false
	if replace_id != "":
		# M3c2 審查：取代時本世界綁定的狀態（錢莊、組織、坐牢、禁學、冷卻、每日上限、位置…）沿用本地角色的
		var local = host.char_store.load_char(s.identity, replace_id)
		if local != null:
			ForeignImport.keep_local_world_bound(ch, local)
			# M3c2 第三輪審查（O12）：更新只帶進成長（屬性、武功、經驗、學點…）；銀兩與身上物品沿用本地角色的
			# （護照沒有簽章、saved_s 可以亂改：否則「匯入 → 存錢莊／給別人 → 改大 saved_s 再匯」可以無限複製）。
			# 本地角色在本世界合法拿到的神兵也因此留著，登記不動
			ForeignImport.keep_local_goods(ch, local)
			kept_local_goods = true
			dropped.append(ForeignImport.GOODS_KEPT_LINE)
		else:
			# M3C2 審查：本地角色檔讀不到（壞檔）→ 當作沒有本地資料，照匯入新角色的方式處理組織與護鏢的參照
			host.m2_call(host.get("orgs"), "on_char_deleted", [replace_id])
			host.m2_call(host.get("escort"), "on_char_deleted", [replace_id])
			host.m2_call(host.get("loot"), "on_char_deleted", [replace_id])   # 撤銷讀不到的本地角色的神兵登記（§5.5）
		host.char_store.unregister_char(replace_id)
	if e is Dictionary and not kept_local_goods:
		# M3c2 第三輪審查（O12）：同一個來源角色的銀兩與物品一輩子只帶進一次（第一次匯入）——
		# 本地角色刪掉後再匯較新的檔案，只帶進成長，身上空空
		ForeignImport.strip_goods(ch)
		dropped.append(ForeignImport.GOODS_ONCE_LINE)
	# M3c2 第二輪審查（O4 改）：外來神兵預設一律不帶入（檔案可以偽造，會繞過全服 12 時辰的掉落鎖）；
	# 主機把 allow_foreign_divine 打開才照 R10（本世界沒人持有就登記給匯入的角色）
	if kept_local_goods:
		pass   # 身上是本地角色的東西（神兵登記本來就在這個 id 名下）
	elif host.options.get(OPT_ALLOW_FOREIGN_DIVINE, false) == true:
		var lost: Variant = host.m2_call(host.get("loot"), "on_foreign_import", [ch], [])
		if lost is Array:
			for n in lost:
				dropped.append("神兵 %s（本世界已有人持有）" % str(n))
	else:
		for n in strip_divine(host, ch):
			dropped.append("神兵 %s（這個世界不接受外來神兵）" % str(n))
	if ch.ext.get("foreign") is Dictionary:
		ch.ext["foreign"]["dropped"] = dropped.duplicate()
	ch.clamp_vitals(host.tables, host.options)
	if host.save_char(ch) != OK:
		return GameHost.fail("drop:save_failed")
	host.char_store.register_name(ch)
	reg[key] = { "char_id": str(ch.id), "identity": s.identity, "saved_s": saved_s, "imported_s": now }
	host.ws.save_now()
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_FOREIGN_IMPORTED,
		{ "name": str(ch.name), "replaced": replace_id != "", "dropped": dropped }, true)
	host.push_char_list(s)
	return GameHost.ok({ "char_id": str(ch.id) })

## M3c2 審查：這份護照是不是本世界出去的——world_id、角色的來源鏈（A → B → A）、
## 本世界的簽章對得上（world_id 被改過的本世界護照）、或角色 id 是本世界現有的角色
static func from_this_world(host: GameHost, pp: Dictionary, world_id: String) -> bool:
	if ForeignImport.is_from_world(pp, world_id):
		return true
	var secret := str(host.ws.world.get("world_secret", ""))
	if secret != "" and pp.get("char") is Dictionary:
		var probe: Dictionary = pp.duplicate()
		probe["world_id"] = world_id
		if Passport.verify(secret, world_id, probe):
			return true
	var cid := str(pp.get("char_id", ""))
	if cid != "":
		for k in host.char_store.names():
			if str(host.char_store.names()[k].get("char_id", "")) == cid:
				return true
	return false

## 物品重新編號（裝備欄跟著換）
static func renumber_items(host: GameHost, ch) -> void:
	var inv: Inventory = ch.inventory
	var remap := {}
	for it in inv.items:
		var nu := host.make_item_uid()
		remap[str(it["uid"])] = nu
		it["uid"] = nu
	for slot in Inventory.SLOTS:
		var old := str(inv.equipped.get(slot, ""))
		inv.equipped[slot] = str(remap.get(old, "")) if old != "" else ""

## 伺服器設定面板的「允許外來角色」（§5.3；AdminSystem.EDITABLE_KEYS 沒有這個 key → 由本檔處理）
static func set_allow_foreign(host: GameHost, s: Session, value: String) -> Dictionary:
	if not host.is_admin(s):
		return GameHost.fail("not_admin")
	if not (value in ["true", "false"]):
		return GameHost.fail("bad_value:value")
	host.ws.options[OPT_ALLOW_FOREIGN] = value == "true"
	SaveManager.save_options(host.ws.world_id, host.ws.options)
	host.ws.save_now()
	host.ws.broadcast_event(Protocol.CH_SYSTEM, Protocol.E_SERVER_OPTION_CHANGED,
		{ "label": ALLOW_FOREIGN_LABEL, "value": "開" if value == "true" else "關", "key": OPT_ALLOW_FOREIGN })
	host.ws.broadcast_event(Protocol.CH_SYSTEM, Protocol.E_WORLD_INFO_CHANGED, { "world_info": host.ws.world_info() }, true)
	host.admin.send_options(s)
	return GameHost.ok()
