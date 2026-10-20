class_name CorpseSystem
extends RefCounted
## 屍體（M1_PLAN 4.13、3.10.2；M2_PLAN 4.6.4、5.3）：建立、保護期（本人＋授權者）、公開期（誰都能撿）、
## 單件撿取、授權、公開通知、到期清除。計時用世界時間（主機離線時凍結，TECH_ARCH 9）。
##
## M2_PLAN 4.6.4 契約寫 `var host: GameHost`；這裡刻意不加型別，讓單元測試可以傳入假主機（行為不變）。

const PRIVATE_S := 600.0      # 0–600 秒：本人與授權者（CLASSIC_30、LATER_10 相同【已證實／後期版】）
const EXPIRE_S := 1800.0      # 1800 秒消失（LATER_10 的消失時間原作沒寫，取 1800【設計提案】D6）
const WINDOWS := {
	"CLASSIC_30": { "private_s": PRIVATE_S, "expire_s": EXPIRE_S },
	"LATER_10": { "private_s": PRIVATE_S, "expire_s": EXPIRE_S },
}
const DEFAULT_AUTH_MAX := 4   # corpse_auth_max【設計提案】

const E_CORPSE_LOOTED := Protocol.E_CORPSE_LOOTED
const E_CORPSE_EXPIRED := Protocol.E_CORPSE_EXPIRED
const E_CORPSE_AUTHORIZED := Protocol.E_CORPSE_AUTHORIZED
const E_CORPSE_AUTH_GRANTED := Protocol.E_CORPSE_AUTH_GRANTED
const E_CORPSE_LOOTED_OTHER := Protocol.E_CORPSE_LOOTED_OTHER
const E_CORPSE_LOOTED_BY := Protocol.E_CORPSE_LOOTED_BY
const E_CORPSE_PUBLIC := Protocol.E_CORPSE_PUBLIC

var host

func _init(p_host) -> void:
	host = p_host

func all() -> Array:
	var c: Variant = host.ws.world.get("corpses")
	if not (c is Array):
		c = []
		host.ws.world["corpses"] = c
	return c

func find(corpse_id: String) -> Dictionary:
	for c in all():
		if c is Dictionary and str(c.get("id", "")) == corpse_id:
			return c
	return {}

## items：物品實例陣列（{ uid, id, n, born_s, lots }；lots 撿回時原樣放回，腐壞時間不變）
func create(ch, room_id: String, items: Array) -> String:
	var id: String = host.new_id("cp_")
	var copies: Array = []
	for it in items:
		if it is Dictionary:
			copies.append(it.duplicate(true))
	all().append({
		"id": id, "owner_identity": str(ch.identity), "char_id": str(ch.id), "owner_name": str(ch.name),
		"room": room_id, "created_s": host.now_s(), "window": str(host.rules.get("corpse_window", "CLASSIC_30")),
		"items": copies, "authorized": [], "public_notified": false,
	})
	host.regions.mark_room_dirty(room_id)
	return id

static func pieces(c: Dictionary) -> int:
	var n := 0
	for it in c.get("items", []):
		if it is Dictionary:
			n += int(it.get("n", 1))
	return n

# ---------- 時間（世界秒） ----------
func private_s(c: Dictionary) -> float:
	return float(WINDOWS.get(str(c.get("window", "CLASSIC_30")), WINDOWS["CLASSIC_30"])["private_s"])

func expire_s(c: Dictionary) -> float:
	return float(WINDOWS.get(str(c.get("window", "CLASSIC_30")), WINDOWS["CLASSIC_30"])["expire_s"])

func age(c: Dictionary, now: float) -> float:
	return now - float(c.get("created_s", 0.0))

func is_public(c: Dictionary, now: float) -> bool:
	return age(c, now) >= private_s(c)

## 到下一個階段的剩餘「真實秒數」：保護期內 → 到公開；公開期 → 到消失（無條件進位、不小於 0）。
## M2_PLAN 缺漏：left_s 指哪一段沒寫死；取「目前這一段還剩多久」，UI 依 public 判斷是保護期倒數還是消失倒數。
func left_s(c: Dictionary, now: float) -> int:
	var end := expire_s(c) if is_public(c, now) else private_s(c)
	var world_left := maxf(0.0, end - age(c, now))
	return maxi(0, ceili(world_left / _time_scale() - 1e-6))

func _time_scale() -> float:
	var ts: Variant = host.ws.get("time_scale")
	return maxf(float(ts), 0.001) if ts != null else 1.0

# ---------- 權限 ----------
static func _char_of(viewer):
	if viewer == null:
		return null
	if viewer is Session:
		return viewer.character
	return viewer

static func is_owner(c: Dictionary, ch) -> bool:
	return ch != null and str(c.get("char_id", "")) == str(ch.id) and str(c.get("owner_identity", "")) == str(ch.identity)

static func authorized_list(c: Dictionary) -> Array:
	var a: Variant = c.get("authorized")
	if not (a is Array):
		a = []
		c["authorized"] = a
	return a

static func is_authorized(c: Dictionary, ch) -> bool:
	return ch != null and str(ch.id) in authorized_list(c).map(func(x): return str(x))

func can_loot(c: Dictionary, ch, now: float) -> bool:
	if ch == null:
		return false
	return is_public(c, now) or is_owner(c, ch) or is_authorized(c, ch)

# ---------- 快照 ----------
## M2_PLAN 4.5.2 corpses[]：既有 id、owner_name、mine、n_items ＋ can_loot、public、left_s、authorized_me、items（可撿時才有）、
## authorized_names／auth_max（只給擁有者）
func in_room(room_id: String, viewer) -> Array:
	var ch = _char_of(viewer)
	var now: float = host.now_s()
	var out: Array = []
	for c in all():
		if not (c is Dictionary) or str(c.get("room", "")) != room_id:
			continue
		var may := can_loot(c, ch, now)
		var e := {
			"id": str(c.get("id", "")), "owner_name": str(c.get("owner_name", "")),
			"mine": is_owner(c, ch),
			"n_items": pieces(c),
			"can_loot": may, "public": is_public(c, now), "left_s": left_s(c, now),
			"authorized_me": is_authorized(c, ch),
		}
		# 擁有者看得到已經允許了誰（最多 corpse_auth_max 人；M2 審查：否則滿了只會得到 corpse_auth_full）
		if bool(e["mine"]):
			var names: Array = []
			for aid in authorized_list(c):
				var n := _display_name(str(aid), "")
				names.append(n if n != "" else "？")
			e["authorized_names"] = names
			e["auth_max"] = _auth_max()
		if may:
			var items: Array = []
			for it in c.get("items", []):
				if it is Dictionary:
					var iid := str(it.get("id", ""))
					items.append({ "uid": str(it.get("uid", "")), "id": iid, "name": host.item_name(iid), "n": int(it.get("n", 1)) })
			e["items"] = items
		out.append(e)
	return out

## M2_PLAN 4.5.1 my_corpses
func mine(ch) -> Array:
	var now: float = host.now_s()
	var out: Array = []
	if ch == null:
		return out
	for c in all():
		if not (c is Dictionary) or not is_owner(c, ch):
			continue
		out.append({
			"id": str(c.get("id", "")), "room_name": host.room_name(str(c.get("room", ""))),
			"public": is_public(c, now), "left_s": left_s(c, now), "n_items": pieces(c),
		})
	return out

# ---------- intent ----------
## corpse_authorize：corpse_not_found（不限房間）→ not_corpse_owner → no_such_player → bad_target → corpse_auth_full
func authorize(s: Session, corpse_id: String, name: String) -> Dictionary:
	var c := find(corpse_id)
	if c.is_empty():
		return GameHost.fail("corpse_not_found")
	var ch = s.character
	if not is_owner(c, ch):
		return GameHost.fail("not_corpse_owner")
	var ref := _char_ref_by_name(name)
	var target_id := str(ref.get("char_id", ""))
	if target_id == "":
		return GameHost.fail("no_such_player")
	if target_id == str(ch.id):
		return GameHost.fail("bad_target")
	var auth := authorized_list(c)
	var already := target_id in auth.map(func(x): return str(x))
	if not already and auth.size() >= _auth_max():
		return GameHost.fail("corpse_auth_full")
	if not already:
		auth.append(target_id)
	var room := str(c.get("room", ""))
	var target_name := _display_name(target_id, name)
	host.tell(s, Protocol.CH_SYSTEM, E_CORPSE_AUTHORIZED, { "name": target_name, "room_name": host.room_name(room) })
	var other: Session = host.session_for_char(target_id)
	if other != null:
		host.tell(other, Protocol.CH_SYSTEM, E_CORPSE_AUTH_GRANTED,
			{ "owner_name": str(c.get("owner_name", "")), "room_name": host.room_name(room) })
		other.view_dirty = true
	host.regions.mark_room_dirty(room)
	host.ws.save_now()   # 授權名單要能撐過當機（4.8 corpses[].authorized）
	return GameHost.ok()

## loot_corpse：corpse_not_found（不在此房間）→ corpse_protected → no_item → 移入背包（全部或單件；放不下的留著）
func loot(s: Session, corpse_id: String, item_uid: String = "") -> Dictionary:
	var c := find(corpse_id)
	if c.is_empty() or str(c.get("room", "")) != s.room_id():
		return GameHost.fail("corpse_not_found")
	var ch = s.character
	var now: float = host.now_s()
	if not can_loot(c, ch, now):
		return GameHost.fail("corpse_protected")
	var take: Array = []
	var keep: Array = []
	for it in c.get("items", []):
		if not (it is Dictionary):
			continue
		if item_uid == "" or str(it.get("uid", "")) == item_uid:
			take.append(it)
		else:
			keep.append(it)
	if item_uid != "" and take.is_empty():
		return GameHost.fail("no_item")
	var moved := 0
	var last_reason := ""
	for it in take:
		var item_id := str(it.get("id", ""))
		var n := int(it.get("n", 1))
		var lots: Array = it.get("lots", []) if it.get("lots") is Array else []
		var res: Dictionary = host.give_item(ch, item_id, n, float(it.get("born_s", now)), lots)
		if res.get("ok", false):
			moved += n
		else:
			last_reason = str(res.get("reason", "inventory_full"))
			keep.append(it)
	if moved == 0:
		return GameHost.fail(last_reason if last_reason != "" else "inventory_full")
	# 保持屍體上物品的原始順序
	var order: Array = c.get("items", [])
	var left: Array = []
	for it in order:
		if it in keep:
			left.append(it)
	c["items"] = left
	if left.is_empty():
		all().erase(c)
	if is_owner(c, ch):
		host.tell(s, Protocol.CH_SYSTEM, E_CORPSE_LOOTED, { "n_items": moved })
	else:
		host.tell(s, Protocol.CH_SYSTEM, E_CORPSE_LOOTED_OTHER, { "owner_name": str(c.get("owner_name", "")), "n_items": moved })
		var owner: Session = host.session_for_char(str(c.get("char_id", "")))
		if owner != null:
			host.tell(owner, Protocol.CH_SYSTEM, E_CORPSE_LOOTED_BY, { "name": str(ch.name), "n_items": moved })
			owner.sheet_dirty = true   # my_corpses 的件數變了
	host.regions.mark_room_dirty(s.room_id())
	s.view_dirty = true
	# 物品已移進角色、屍體已改。兩個檔案不能一起原子寫入：先寫 world.json（屍體少了物品）再寫角色檔，
	# 兩次寫入之間當機時物品會消失，但不會同時留在屍體和角色身上（複製；M2 審查）
	host.ws.save_now(true)
	return GameHost.ok({ "n_items": moved })

## 每 60 秒世界時間呼叫：過保護期 → 擁有者（在線）收一次 corpse_public；到期 → 清除、擁有者收 corpse_expired
func expire(now: float) -> void:
	for c in all().duplicate():
		if not (c is Dictionary):
			continue
		var room := str(c.get("room", ""))
		var owner: Session = host.session_for_char(str(c.get("char_id", "")))
		if age(c, now) >= expire_s(c):
			all().erase(c)
			host.regions.mark_room_dirty(room)
			if owner != null:
				host.tell(owner, Protocol.CH_SYSTEM, E_CORPSE_EXPIRED, { "room_name": host.room_name(room) })
				owner.sheet_dirty = true
			continue
		if is_public(c, now) and not bool(c.get("public_notified", false)):
			# 只送一次：擁有者不在線也標記（上線時不補送；my_corpses 的 public 欄位會顯示）
			c["public_notified"] = true
			host.regions.mark_room_dirty(room)   # can_loot 對旁人改變了
			if owner != null:
				host.tell(owner, Protocol.CH_SYSTEM, E_CORPSE_PUBLIC, { "room_name": host.room_name(room) })
				owner.sheet_dirty = true

# ---------- 輔助 ----------
func _auth_max() -> int:
	return int(host.options.get("corpse_auth_max", DEFAULT_AUTH_MAX))

## GameHost.char_ref_by_name（WP-HOST）；舊主機沒有時直接查 world.char_names
func _char_ref_by_name(name: String) -> Dictionary:
	if host.has_method("char_ref_by_name"):
		var r: Variant = host.char_ref_by_name(name)
		return r if r is Dictionary else {}
	var names: Variant = host.ws.world.get("char_names", {})
	if names is Dictionary:
		var e: Variant = names.get(name.strip_edges().to_lower())
		if e is Dictionary:
			return e
	return {}

## 被授權者的正式名字（大小寫依角色本身）；查不到就用輸入的名字
func _display_name(char_id: String, fallback: String) -> String:
	var o: Session = host.session_for_char(char_id)
	if o != null:
		return str(o.character.name)
	if host.has_method("pvp_char_name"):
		var n := str(host.pvp_char_name(char_id))
		if n != "":
			return n
	return fallback.strip_edges()
