class_name IntentsChar
extends RefCounted
## char_list char_roll char_create char_select char_delete（M1_PLAN 3.6）
## M3c WP-LOOKS（M3C_PLAN §3.3）：char_create 可選 look；set_look { look }（免費、純外觀）

const NOTE_SECT_FALLBACK := "（拜在門下時仍穿門派服裝）"

static func register(host: GameHost) -> void:
	host.register(Protocol.I_CHAR_LIST, func(s: Session, a: Dictionary) -> Dictionary: return char_list(host, s, a), 0)
	host.register(Protocol.I_CHAR_ROLL, func(s: Session, a: Dictionary) -> Dictionary: return char_roll(host, s, a), GameHost.IDLE)
	host.register(Protocol.I_CHAR_CREATE, func(s: Session, a: Dictionary) -> Dictionary: return char_create(host, s, a), GameHost.IDLE)
	host.register(Protocol.I_CHAR_SELECT, func(s: Session, a: Dictionary) -> Dictionary: return char_select(host, s, a), GameHost.IDLE)
	host.register(Protocol.I_CHAR_DELETE, func(s: Session, a: Dictionary) -> Dictionary: return char_delete(host, s, a), GameHost.IDLE)
	# M3c：旗標照 §3.3 是 NEEDS_CHAR | IDLE，但「坐牢中也可以換」而思過處閘門（SectSystem.JAIL_ALLOWED，WP-NPCPK 的檔）
	# 只在 NEEDS_CHAR 時檢查 → 這裡只登記 IDLE、角色檢查在處理器內做（結果相同：沒有角色回 no_character）
	host.register(Protocol.I_SET_LOOK, func(s: Session, a: Dictionary) -> Dictionary: return set_look(host, s, a), GameHost.IDLE)

static func char_list(host: GameHost, s: Session, _a: Dictionary) -> Dictionary:
	host.push_char_list(s)
	return GameHost.ok()

static func char_roll(host: GameHost, s: Session, _a: Dictionary) -> Dictionary:
	var roll: Dictionary = CharacterFactory.roll(host.rng)
	s.pending_roll = roll.duplicate()
	var p := {}
	var total := 0
	for attr in Character.ATTR_IDS:
		p[attr] = int(roll.get(attr, 0))
		total += int(roll.get(attr, 0))
	p["total"] = total
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_CHAR_ROLLED, p)
	return GameHost.ok()

## 驗證順序：bad_value:birth_city（最先）→ no_roll → bad_name → name_taken → too_many_chars → bad_alloc → bad_look（M3c）
static func char_create(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var city := str(a["birth_city"])
	# M3B_PLAN §5.1.9：出生城＝生效 regions 中 birth_allowed 的 CITY（1.0B 多京城；1.0A 世界只有西夏、大理）
	if not (city in birth_cities(host)):
		return GameHost.fail("bad_value:birth_city")
	if s.pending_roll.is_empty():
		return GameHost.fail("no_roll")
	var char_name := str(a["name"])
	if CharacterFactory.validate_name(char_name) != "":
		return GameHost.fail("bad_name")
	if host.char_store.name_taken(char_name):
		return GameHost.fail("name_taken")
	if host.char_store.count(s.identity) >= Character.MAX_CHARS_PER_IDENTITY:
		return GameHost.fail("too_many_chars")
	var alloc: Dictionary = a["alloc"]
	if CharacterFactory.validate_alloc(alloc) != "":
		return GameHost.fail("bad_alloc")
	# M3c：造型編號（Protocol.INT_RANGES 已擋成 bad_value:look；這裡是第二道）
	var look := look_arg(a)
	if look < 0:
		return GameHost.fail(Protocol.R_BAD_LOOK)
	var p := {
		"id": host.new_id("ch_"), "identity": s.identity, "name": char_name, "gender": str(a["gender"]),
		"birth_month": int(a["birth_month"]), "birth_city": city, "alloc": alloc.duplicate(),
		"look": look,
	}
	var ch = CharacterFactory.create(p, s.pending_roll, host.tables, host.options, host.rng, host.now_s())
	if ch == null:
		return GameHost.fail("bad_alloc")
	var err := host.save_char(ch)
	if err != OK:
		return GameHost.fail("drop:save_failed")
	host.char_store.register_name(ch)
	s.pending_roll = {}
	if s.character != null:
		host.switch_out(s)
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_CHAR_CREATED, { "name": str(ch.name), "char_id": str(ch.id) })
	host.enter_character(s, ch)
	host.push_char_list(s)
	host.ws.save_now()   # char_names 索引立即落地
	return GameHost.ok({ "char_id": str(ch.id) })

## 生效的出生城 id（birth_allowed、type CITY、birth_room 存在），依 id 排序
static func birth_cities(host: GameHost) -> Array:
	var out: Array = []
	var regions: Dictionary = host.tables.get("regions", {})
	for rid in regions:
		var r: Variant = regions[rid]
		if r is Dictionary and bool(r.get("birth_allowed", false)) and str(r.get("type", "")) == "CITY" \
				and host.index.has_room(str(r.get("birth_room", ""))):
			out.append(str(rid))
	out.sort()
	return out

static func char_select(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var char_id := str(a["char_id"])
	if not host.char_store.has_char(s.identity, char_id):
		return GameHost.fail("no_such_char")
	# M2_PLAN 4.6.1、D4：這個角色還在進行中的戰鬥裡（斷線後自動防）→ 接回原戰鬥，沿用戰鬥中的同一個 Character 物件
	var bid := int(host.m2_call(host.battles, "battle_of_char", [char_id], 0))
	if bid != 0 and host.battles.has_method("reattach"):
		if s.character != null and str(s.character.id) != char_id:
			host.switch_out(s)
		if bool(host.battles.reattach(s, char_id)) and s.character != null:
			host.enter_character(s, s.character)   # 進房事件、視圖、角色表、未讀信提醒
			return GameHost.ok({ "battle_id": bid })
	if s.character != null:
		host.switch_out(s)   # 先送護照、存檔並離開房間（重新選同一個角色也一樣：從檔案重新載入）
	var ch = host.char_store.load_char(s.identity, char_id)
	if ch == null:
		return GameHost.fail("no_such_char")
	host.enter_character(s, ch)
	return GameHost.ok()

static func char_delete(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var char_id := str(a["char_id"])
	if not host.char_store.has_char(s.identity, char_id):
		return GameHost.fail("no_such_char")
	var ch = host.char_store.load_char(s.identity, char_id)
	if ch == null:
		return GameHost.fail("no_such_char")
	if str(ch.name) != str(a["confirm_name"]):
		return GameHost.fail("confirm_mismatch")
	if s.character != null and str(s.character.id) == char_id:
		return GameHost.fail("char_active")
	# 斷線後角色還留在隊友的戰鬥裡（D4 自動防）：戰鬥結束時 _settle_player 會把角色檔寫回來、戰死還會留屍體，
	# 刪掉的角色會復活、名字還能被別人再取一次（M2 審查）。戰鬥中的角色一律當作「正在使用」
	if host.battles != null and host.battles.battle_of_char(char_id) != 0:
		return GameHost.fail("char_active")
	if host.char_store.delete(s.identity, char_id) != OK:
		return GameHost.fail("no_such_char")
	host.m2_call(host.mail, "on_char_deleted", [char_id])
	host.m2_call(host.get("orgs"), "on_char_deleted", [char_id])     # M3b 審查：移出組織、連署名單、邀請；幫主 → 移交或解散
	host.m2_call(host.get("escort"), "on_char_deleted", [char_id])
	host.m2_call(host.get("loot"), "on_char_deleted", [char_id])     # M3c 審查：釋放他持有的神兵登記   # M3b：寄給他的托鏢退回寄件人（WP-ECON）   # 寄給他的信一併刪除；屍體照常到期（M2_PLAN 4.6.1）
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_CHAR_DELETED, { "name": str(ch.name) })
	host.push_char_list(s)
	host.ws.save_now()
	return GameHost.ok()

# ---------------------------------------------------------------- M3c WP-LOOKS

## 參數 look → 0..LOOK_MAX；沒帶 → 0；型別或範圍不對 → -1（bad_look）
static func look_arg(a: Dictionary) -> int:
	if not a.has("look"):
		return 0
	var v: Variant = a["look"]
	if typeof(v) == TYPE_FLOAT and float(v) == floor(float(v)):
		v = int(v)
	if typeof(v) != TYPE_INT or not Looks.valid(int(v)):
		return -1
	return int(v)

## set_look { look }：免費、隨時（戰鬥中 in_battle）、坐牢中也可以換；純外觀
static func set_look(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	if s.character == null:
		return GameHost.fail("no_character")
	if not a.has("look"):
		return GameHost.fail("missing_arg:look")
	var look := look_arg(a)
	if look < 0:
		return GameHost.fail(Protocol.R_BAD_LOOK)
	var ch = s.character
	ch.appearance = look
	var in_sect := str(ch.sect) != ""
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_LOOK_CHANGED, {
		"look": look, "look_name": Looks.name_of(str(ch.gender), look), "shown": str(ch.battle_look()),
		"note": sect_note(host) if in_sect else "",
	}, true)
	s.sheet_dirty = true
	host.save_char(ch)
	return GameHost.ok({ "look": look })

static func sect_note(host: GameHost) -> String:
	var row: Variant = host.tables.get("text_templates", {}).get("look_note_sect", {})
	if row is Dictionary and str(row.get("self", "")) != "":
		return str(row["self"])
	return NOTE_SECT_FALLBACK
