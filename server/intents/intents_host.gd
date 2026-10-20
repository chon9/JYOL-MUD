extends RefCounted
## WP-HOST 的 M2 intent（M2_PLAN 4.2）：server_opts_get／server_opts_set／admin_kick／passport_request／
## passport_restore／passport_import。由 GameHost 以路徑 load() 後呼叫 register()（H4）。
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
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_PASSPORT_RESTORED, { "name": str(restored.name) })
	host.push_char_list(s)
	host.ws.save_now()
	return GameHost.ok({ "char_id": char_id })

## P2（M2_PLAN 2.2）：外來角色匯入尚未實作
static func passport_import(_host: GameHost, _s: Session, _a: Dictionary) -> Dictionary:
	return GameHost.fail("foreign_disabled")
