class_name ForeignImport
extends RefCounted
## 外來角色（M3C2_PLAN §5.4；M2_PLAN P2 passport_import）：把別的世界的護照（或匯出檔裡的護照）驗證、截斷成
## 「可以直接 Character.from_dict」的角色字典。純邏輯：客戶端預覽與主機共用同一個 sanitize()。
##
## 誠實說明：別的世界的簽章無法驗證（Passport 的說明），所以這裡不驗簽，只做「截到資料與規則的合法範圍」。
## 世界綁定的東西（錢莊、組織、進行中的任務、冷卻、坐牢、記錄點……）留在原世界（R11）。
## 神兵（全服唯一）只標出來，由主機決定：預設一律拿掉；主機打開 allow_foreign_divine 才照本世界的登記（R10、O4 第二輪）。

const EXPORT_KIND := "jy_char_export"
const EXPORT_V := 1
const FILE_MAX_BYTES := 262144              # §5.1：> 256 KB → 客戶端直接說「檔案無法讀取」
const ATTR_MIN := 13
const ATTR_MAX := 30                         # 創角 13–25 ＋自由點 5
const ATTR_TOTAL_MAX := 7 * 25 + 5           # 180
const COMBAT_XP_MAX := 10000000
const GENERIC_MAX := 1000000                 # 沒有上限的數值（殺氣、PK值、名聲、歷練…）
const DEFAULT_MONEY_CAP := 6000000
const FALLBACK_CITY := "xixia"
const TOP_SKILLS_N := 5
## M3c2 審查：外來角色帶進來的銀兩上限（比 bank_money_cap 低：匯入是複製，不能整筆把別的世界的錢搬進來）【設計提案】
const FOREIGN_MONEY_CAP := 100000
## M3c2 審查：外來角色最多帶幾件珍品（rarity TREASURE；神兵另由主機登記決定）【設計提案】
const FOREIGN_TREASURE_MAX := 2
## M3c2 第三輪審查：匯入的學點上限（規則 xuedian_cap 為 0＝不限時用這個；同 DataSchema 的預設 65200）【設計提案】
const FOREIGN_LP_CAP_FALLBACK := 65200
## M3c2 第三輪審查（O12）：取代／刪後再匯時給玩家看的說明
const GOODS_KEPT_LINE := "銀兩與身上物品沿用本世界的（再次匯入只更新屬性、武功、經驗與學點）"
const GOODS_ONCE_LINE := "銀兩與物品不帶入（這個來源角色第一次匯入時已經帶進過）"
## ext 裡可以帶走的鍵（其他系統的私用資料大多是世界綁定的：頭目鎖、NPC 仇恨、惡人追殺……）
const EXT_KEEP := ["ambient"]

## 讀檔內容（JSON 文字）→ { ok, passport, world_name, kind: "export"|"passport", error }
## 匯出檔 { kind: "jy_char_export", v: 1, …, passport: {…} } 或裸護照 { v, world_id, char_id, … }
## error（M3c2 審查：給玩家看原因）：too_large（> 256 KB）、not_json、not_char、passport_too_large（主機上限 64 KB）
static func parse_text(text: String) -> Dictionary:
	var out := { "ok": false, "passport": {}, "world_name": "", "kind": "", "error": "unreadable" }
	if text.length() > FILE_MAX_BYTES:
		out["error"] = "too_large"
		return out
	var j := JSON.new()
	if text.strip_edges() == "" or j.parse(text) != OK or not (j.data is Dictionary):
		out["error"] = "not_json"
		return out
	var d: Dictionary = j.data
	var res := {}
	if str(d.get("kind", "")) == EXPORT_KIND:
		if not (d.get("passport") is Dictionary):
			out["error"] = "not_char"
			return out
		var pp: Dictionary = (d["passport"] as Dictionary).duplicate(true)
		var wn := str(d.get("world_name", ""))
		if wn != "" and str(pp.get("world_name", "")) == "":
			pp["world_name"] = wn
		res = { "ok": true, "passport": pp, "world_name": wn, "kind": "export", "error": "" }
	elif d.has("char") and d.has("world_id"):
		res = { "ok": true, "passport": d, "world_name": str(d.get("world_name", "")), "kind": "passport", "error": "" }
	else:
		out["error"] = "not_char"
		return out
	# 主機的 passport 參數上限（Protocol.PASSPORT_MAX_BYTES，var_to_bytes）：超過就不送，免得預覽看起來正常、送出才失敗
	if var_to_bytes(res["passport"]).size() > Protocol.PASSPORT_MAX_BYTES:
		out["error"] = "passport_too_large"
		return out
	return res

## 匯出檔的內容（§5.1）
static func make_export(passport: Dictionary, meta: Dictionary) -> Dictionary:
	return {
		"kind": EXPORT_KIND, "v": EXPORT_V,
		"exported_at": str(meta.get("exported_at", Time.get_datetime_string_from_system(false, false))),
		"game_version": str(meta.get("game_version", BuildInfo.version())),
		"protocol": int(meta.get("protocol", BuildInfo.protocol())),
		"content_fp": BuildInfo.fingerprint12(str(meta.get("content_hash", meta.get("content_fp", "")))),
		"world_name": str(meta.get("world_name", "")),
		"passport": passport,
	}

## 回傳 { "ok": bool, "reason": String, "char": Dictionary（已截斷、可直接 Character.from_dict）,
##        "dropped": Array[String]（給人看的清單，例 "未知物品 x_abc ×2"、"錢莊存款（留在原世界）"）,
##        "summary": { name, gender, sect, sect_name, combat_xp, money, items_n, top_skills: [[name, level]], divine: [item_id] } }
## options：世界的伺服器選項（bank_money_cap）；rules：展開後的規則（xuedian_cap）
static func sanitize(passport: Dictionary, tables: Dictionary, rules: Dictionary, options: Dictionary) -> Dictionary:
	var bad := { "ok": false, "reason": "foreign_bad_data", "char": {}, "dropped": [], "summary": {} }
	# 1. 格式（簽章不驗：別的世界無法驗證）
	if Passport.check_format(passport) != "":
		return bad
	var src: Dictionary = passport["char"]
	if not (str(src.get("gender", "M")) in ["M", "F"]):
		return bad
	# 2. Character 往返一次
	var ch := Character.from_dict(src)
	if ch == null or str(ch.id) == "" or str(ch.name) == "":
		return bad
	var dropped: Array = []
	# 3. 外來標記（id、identity 由主機在寫入時換）
	var origin := str(passport["world_id"])
	var world_name := str(passport.get("world_name", ""))
	if world_name == "":
		world_name = origin
	ch.origin_world = origin
	# M3c2 審查：來源鏈（A → B → A 的回流要擋）：護照角色自己的 origin_world、ext.foreign.world_id 與 via 都算「去過的世界」
	var via := worlds_visited(src)

	# 4. 屬性
	_clamp_attrs(ch, dropped)
	# 6（先做實戰：技能上限看截斷後的實戰）
	ch.combat_xp = clampi(ch.combat_xp, 0, COMBAT_XP_MAX)
	# 5. 技能
	_clamp_skills(ch, tables, dropped)
	# 門派：本世界沒有開放 → 武功保留、門派清空
	if ch.sect != "" and CharData.row(tables, "sects", ch.sect).is_empty():
		dropped.append("原門派本世界沒有開放（武功保留，門派身分清除）")
		ch.sect = ""
		ch.sect_rank = 0
		ch.sect_master = ""
	if ch.sect_master != "" and CharData.row(tables, "npcs", ch.sect_master).is_empty():
		ch.sect_master = ""
	ch.sect_enemies = _known_sects(ch.sect_enemies, tables)
	ch.sect_traitor = _known_sects(ch.sect_traitor, tables)
	# 6. 數值
	# M3c2 第三輪審查：規則不限學點（xuedian_cap 0）時匯入仍截到 FOREIGN_LP_CAP_FALLBACK（偽造檔不能帶進無限學點）
	var xcap := CharData.to_int(rules.get("xuedian_cap", 0))
	if xcap <= 0:
		xcap = FOREIGN_LP_CAP_FALLBACK
	ch.learn_points = clampi(ch.learn_points, 0, xcap)
	ch.money = maxi(0, ch.money)   # 上限在物品之後算（M3c2 第二輪審查：銀兩＋物品收購總值一起算）
	ch.morality = clampi(ch.morality, Character.MORALITY_MIN, Character.MORALITY_MAX)
	ch.killing_intent = clampi(ch.killing_intent, 0, GENERIC_MAX)
	ch.pk = clampi(ch.pk, 0, GENERIC_MAX)
	ch.fame = clampi(ch.fame, 0, GENERIC_MAX)
	ch.lilian = clampi(ch.lilian, 0, GENERIC_MAX)
	ch.lili = clampi(ch.lili, 0, GENERIC_MAX)
	# M3c2 第二輪審查：修練次數 ≤ 基本內功等級 × 5、氣上限加成 ≤ 修練次數 × 8（Survival.meditate 是唯一來源）
	_clamp_cultivation(ch, dropped)
	ch.dead_count = clampi(ch.dead_count, 0, GENERIC_MAX)
	ch.sect_rank = clampi(ch.sect_rank, 0, 100)
	ch.online_s = maxf(0.0, ch.online_s) if is_finite(ch.online_s) else 0.0
	# 9. 世界綁定的狀態（先做：錢莊物品不能經由背包截斷「救回來」）
	var novice_lp := CharData.to_int(ch.counters.get(Learning.NOVICE_LP_KEY, 0))
	_reset_world_bound(ch, tables, dropped)
	# M3c2 第二輪審查：新手期雜務＋切磋學點是「一輩子」的上限 → 跟著角色走（不然每換一個世界就多 4000）
	if novice_lp > 0:
		ch.counters[Learning.NOVICE_LP_KEY] = novice_lp
	# 7. 物品
	var divine := _clamp_items(ch, tables, options, rules, dropped)
	# 8. 銀兩＋物品收購總值 ≤ 外來角色上限（M3c2 第二輪審查：高價輕巧的消耗品不能繞過銀兩上限）
	_clamp_value(ch, tables, options, dropped)
	# 精氣神內力、飽食飲水 ≤ 衍生上限（在屬性、技能、裝備都定案之後）
	ch.clamp_vitals(tables, options)

	# M3c2 第三輪審查：NaN／INF（var_to_bytes 會原樣送過來）一律換成 0——存成 JSON 會變 null，讀檔時出錯
	var d: Dictionary = finite_floats(ch.to_dict())
	var ext: Dictionary = d.get("ext", {})
	ext["foreign"] = { "world_id": origin, "world_name": world_name, "char_id": str(passport["char_id"]),
		"saved_s": float(passport.get("saved_s", 0.0)), "imported_s": 0.0, "dropped": dropped.duplicate(), "via": via.duplicate() }
	d["ext"] = ext
	var sm := _summary(ch, tables, divine)
	sm["via"] = via.duplicate()
	return { "ok": true, "reason": "", "char": d, "dropped": dropped, "summary": sm }

## 護照角色「去過的世界」（不含護照本身的 world_id）：char.origin_world、char.ext.foreign.world_id、char.ext.foreign.via
static func worlds_visited(src: Dictionary) -> Array:
	var out: Array = []
	var ext: Variant = src.get("ext", {})
	var fx: Variant = ext.get("foreign", {}) if ext is Dictionary else {}
	var cands: Array = [src.get("origin_world", "")]
	if fx is Dictionary:
		cands.append(fx.get("world_id", ""))
		if fx.get("via") is Array:
			cands.append_array(fx["via"])
	for w in cands:
		var ws := CharData.to_str(w)
		if ws != "" and not out.has(ws):
			out.append(ws)
	return out

## 這份護照是不是本世界出去的（同世界不能用匯入，要用「用護照還原」）：
## 護照 world_id、角色的來源鏈（A → B → A）都算。主機另外比對簽章與本世界的角色 id（intents_host）。
static func is_from_world(passport: Dictionary, world_id: String) -> bool:
	if world_id == "":
		return false
	if str(passport.get("world_id", "")) == world_id:
		return true
	var c: Variant = passport.get("char", {})
	return c is Dictionary and worlds_visited(c).has(world_id)

## 取代（§5.6）：新資料換掉本地角色時，本世界綁定的狀態沿用本地角色的（M3c2 審查：錢莊、組織、坐牢、
## 門派禁學、任務冷卻與進行中的任務、計數（每日雜務與切磋上限）、記錄點與位置、其他系統的 ext 資料）
const LOCAL_EXT_SKIP := ["foreign"]
static func keep_local_world_bound(ch: Character, local: Character) -> void:
	ch.bank = local.bank.duplicate(true)
	ch.guild = local.guild
	ch.sect_rank_pending = local.sect_rank_pending.duplicate(true)
	var done: Variant = ch.quests.get("done", {})
	ch.quests = { "active": (local.quests.get("active", {}) as Dictionary).duplicate(true) if local.quests.get("active") is Dictionary else {},
		"done": (done as Dictionary).duplicate(true) if done is Dictionary else {},
		"cd": (local.quests.get("cd", {}) as Dictionary).duplicate(true) if local.quests.get("cd") is Dictionary else {} }
	var imported_lp := CharData.to_int(ch.counters.get(Learning.NOVICE_LP_KEY, 0))
	ch.counters = local.counters.duplicate(true)
	# 新手期學點的一輩子上限：取兩邊較大的（M3c2 第二輪審查）
	ch.counters[Learning.NOVICE_LP_KEY] = maxi(imported_lp, CharData.to_int(local.counters.get(Learning.NOVICE_LP_KEY, 0)))
	# M3c2 第二輪審查：上線時數不能倒退（否則取代前存在客戶端的舊護照 online_s 比較大，passport_restore 會當它較新
	# 而還原 → 已經給出去的東西又回來）。本世界綁定的計時（禁學、冷卻）也是以本地的 online_s 算的
	ch.online_s = maxf(ch.online_s, local.online_s) + 1.0
	ch.jail = local.jail.duplicate(true)
	for k in ["breached", "ban_until_online_s", "lockout"]:
		ch.sect_record[k] = local.sect_record.get(k, Character.default_sect_record()[k])
		if ch.sect_record[k] is Dictionary:
			ch.sect_record[k] = (ch.sect_record[k] as Dictionary).duplicate(true)
	ch.buffs = local.buffs.duplicate(true)
	var fx: Variant = ch.ext.get("foreign")
	var ext := {}
	for k in local.ext:
		if not (str(k) in LOCAL_EXT_SKIP):
			ext[k] = local.ext[k]
	for k in ch.ext:
		if not ext.has(k):
			ext[k] = ch.ext[k]
	if fx != null:
		ext["foreign"] = fx
	ch.ext = ext.duplicate(true)
	ch.location = local.location.duplicate()
	ch.respawn = local.respawn.duplicate()
	ch.birth_city = local.birth_city

## M3c2 第三輪審查（O12）：取代時銀兩與身上物品（含裝備）沿用本地角色的
static func keep_local_goods(ch: Character, local: Character) -> void:
	ch.money = local.money
	ch.inventory = Inventory.from_dict(local.inventory.to_dict())

## M3c2 第三輪審查（O12）：拿掉銀兩與身上所有物品（同一個來源角色刪後再匯）
static func strip_goods(ch: Character) -> void:
	ch.money = 0
	ch.inventory = Inventory.new()

## 把字典／陣列裡所有非有限的浮點數換成 0.0（遞迴；回傳同一個物件）
static func finite_floats(v: Variant) -> Variant:
	if v is Dictionary:
		for k in (v as Dictionary).keys():
			var x: Variant = v[k]
			if typeof(x) == TYPE_FLOAT and not is_finite(x):
				v[k] = 0.0
			elif x is Dictionary or x is Array:
				finite_floats(x)
	elif v is Array:
		for i in (v as Array).size():
			var x: Variant = v[i]
			if typeof(x) == TYPE_FLOAT and not is_finite(x):
				v[i] = 0.0
			elif x is Dictionary or x is Array:
				finite_floats(x)
	return v

# ---------------------------------------------------------------- 步驟

static func _clamp_attrs(ch: Character, dropped: Array) -> void:
	var changed := false
	var total := 0
	for k in Character.ATTR_IDS:
		var v := int(ch.attrs.get(k, 0))
		var c := clampi(v, ATTR_MIN, ATTR_MAX)
		if c != v:
			changed = true
		ch.attrs[k] = c
		total += c
	# 總和超過：每次從目前最高的一項扣 1（同分取 ATTR_IDS 順序靠前的）
	while total > ATTR_TOTAL_MAX:
		var best := ""
		for k in Character.ATTR_IDS:
			if int(ch.attrs[k]) > ATTR_MIN and (best == "" or int(ch.attrs[k]) > int(ch.attrs[best])):
				best = k
		if best == "":
			break
		ch.attrs[best] = int(ch.attrs[best]) - 1
		total -= 1
		changed = true
	if changed:
		dropped.append("屬性截到合法範圍（每項 %d–%d、總和 ≤ %d）" % [ATTR_MIN, ATTR_MAX, ATTR_TOTAL_MAX])

static func _clamp_skills(ch: Character, tables: Dictionary, dropped: Array) -> void:
	var xp_cap := DerivedStats.art_level_cap(ch.combat_xp)
	var capped: Array = []
	for sid in ch.skills.entries.keys():
		var kind := SkillBook.kind_of(sid, tables)
		if kind == "":
			dropped.append("未知技能 %s（%d 級）" % [sid, ch.skills.level(sid)])
			ch.skills.entries.erase(sid)
			continue
		if kind == SkillBook.KIND_ART and bool(CharData.row(tables, "martial_arts", sid).get("monster_only", false)):
			dropped.append("不可學的武功 %s" % SkillBook.skill_name(sid, tables))
			ch.skills.entries.erase(sid)
			continue
		var lv := ch.skills.level(sid)
		var cap := SkillBook.max_level_of(sid, tables)
		if kind != SkillBook.KIND_LIFE:
			cap = mini(cap, xp_cap)
		if lv < 0:
			ch.skills.entries.erase(sid)
			continue
		if lv > cap:
			capped.append("%s %d→%d" % [SkillBook.skill_name(sid, tables), lv, cap])
			if cap <= 0:
				ch.skills.entries.erase(sid)
			else:
				ch.skills.set_level(sid, cap, tables)
			continue
		# 熟練度：不低於本級門檻、不高於技能最高級的門檻（遊戲內被實戰擋住時熟練度仍會累積，合法）
		var p := ch.skills.prof(sid)
		var lo := SkillBook.prof_for_level(sid, lv, tables) if lv > 0 else 0
		var hi := SkillBook.prof_for_level(sid, SkillBook.max_level_of(sid, tables), tables)
		ch.skills.entries[sid] = { "level": lv, "prof": clampi(p, lo, maxi(lo, hi)) }
	if not capped.is_empty():
		dropped.append("技能等級截到上限：" + "、".join(capped))
	# 特殊武功數 ≤ SPECIAL_ARTS_MAX：多的從最低等級開始拿掉
	var arts: Array = ch.skills.special_arts(tables)
	if arts.size() > Character.SPECIAL_ARTS_MAX:
		arts.sort_custom(func(a, b):
			var la := ch.skills.level(a)
			var lb := ch.skills.level(b)
			return la < lb or (la == lb and str(a) < str(b)))
		var extra := arts.size() - Character.SPECIAL_ARTS_MAX
		for i in extra:
			var sid := str(arts[i])
			dropped.append("特殊武功超過 %d 門：%s（%d 級）" % [Character.SPECIAL_ARTS_MAX, SkillBook.skill_name(sid, tables), ch.skills.level(sid)])
			ch.skills.entries.erase(sid)

static func _clamp_cultivation(ch: Character, dropped: Array) -> void:
	var cmax := maxi(0, ch.skills.level("basic_inner")) * Survival.CULTIVATE_PER_INNER
	var c := clampi(ch.cultivations, 0, cmax)
	var q := clampi(ch.qi_bonus, 0, c * Survival.CULTIVATE_QI)
	if c != ch.cultivations or q != ch.qi_bonus:
		dropped.append("修練次數與氣上限加成截到合法範圍（基本內功 %d 級：最多修練 %d 次、氣 +%d）" % [
			ch.skills.level("basic_inner"), cmax, cmax * Survival.CULTIVATE_QI])
	ch.cultivations = c
	ch.qi_bonus = q

## 外來角色帶進來的「財產上限」：銀兩上限（bank_money_cap、MONEY_CAP、FOREIGN_MONEY_CAP 取小）
## 同時套在「銀兩＋身上物品的收購總值」。超過時先拿掉背包裡（未裝備）單價最高的物品，仍超過再卸下裝備中最貴的；
## 剩下的額度才是銀兩。神兵不算（由主機決定：預設不帶入）。
static func money_cap_of(options: Dictionary) -> int:
	return mini(mini(CharData.to_int(options.get("bank_money_cap", DEFAULT_MONEY_CAP), DEFAULT_MONEY_CAP), Character.MONEY_CAP),
		FOREIGN_MONEY_CAP)

static func items_value(inv: Inventory, tables: Dictionary) -> int:
	var v := 0
	for it in inv.items:
		var row := CharData.row(tables, "items", str(it.get("id", "")))
		if bool(row.get("divine", false)):
			continue
		v += EconCalc.sell_price(row) * int(it.get("n", 1))
	return v

static func _clamp_value(ch: Character, tables: Dictionary, options: Dictionary, dropped: Array) -> void:
	var cap := money_cap_of(options)
	var inv := ch.inventory
	var value := items_value(inv, tables)
	var removed := {}
	var removed_v := 0
	var guard := 0
	while value > cap and guard < 100000:
		guard += 1
		# 先背包（沒裝備的），再裝備；同一層挑單價最高的
		var best: Dictionary = {}
		var best_p := 0
		var best_eq := true
		for it in inv.items:
			var row := CharData.row(tables, "items", str(it.get("id", "")))
			if bool(row.get("divine", false)):
				continue
			var p := EconCalc.sell_price(row)
			if p <= 0:
				continue
			var eq := inv.is_equipped(str(it.get("uid", "")))
			if best.is_empty() or (best_eq and not eq) or (eq == best_eq and p > best_p):
				best = it
				best_p = p
				best_eq = eq
		if best.is_empty():
			break
		var uid := str(best["uid"])
		var n_have := int(best.get("n", 1))
		var n := mini(n_have, ceili(float(value - cap) / float(best_p)))
		if best_eq:
			for slot in Inventory.SLOTS:
				if str(inv.equipped.get(slot, "")) == uid:
					inv.equipped[slot] = ""
		var nm := CharData.item_name(tables, str(best["id"]))
		inv.remove(uid, n)
		removed[nm] = int(removed.get(nm, 0)) + n
		removed_v += n * best_p
		value -= n * best_p
	if not removed.is_empty():
		var parts: Array = []
		for k in removed:
			parts.append("%s ×%d" % [str(k), int(removed[k])])
		dropped.append("物品收購總值超過外來角色上限 %d 兩的部分（約 %d 兩）：%s" % [cap, removed_v, "、".join(parts)])
	var mcap := maxi(0, cap - value)
	if ch.money > mcap:
		dropped.append("銀兩超過外來角色上限 %d 兩的部分（%d 兩；銀兩＋物品收購價合計不超過上限）" % [cap, ch.money - mcap])
	ch.money = clampi(ch.money, 0, mcap)

static func _known_sects(list: Array, tables: Dictionary) -> Array:
	var out: Array = []
	for s in list:
		if not CharData.row(tables, "sects", str(s)).is_empty() and not out.has(str(s)):
			out.append(str(s))
	return out

## 回傳身上神兵的 id 清單（主機依登記決定留不留）
static func _clamp_items(ch: Character, tables: Dictionary, options: Dictionary, rules: Dictionary, dropped: Array) -> Array:
	var inv := ch.inventory
	var removed := {}   # 顯示文字 -> n
	# M3c2 審查：同一個 uid 出現兩次（手改的檔）→ 只留第一件（find／remove／裝備都只認第一件）
	var seen := {}
	var uniq: Array = []
	for it0 in inv.items:
		var u := str(it0.get("uid", ""))
		if seen.has(u):
			var w0 := "重複編號的 %s" % CharData.item_name(tables, str(it0.get("id", "")))
			removed[w0] = int(removed.get(w0, 0)) + int(it0.get("n", 1))
			continue
		seen[u] = true
		uniq.append(it0)
	inv.items = uniq
	var treasure := 0
	for it in inv.items.duplicate():
		var iid := str(it.get("id", ""))
		var row := CharData.row(tables, "items", iid)
		var n := int(it.get("n", 1))
		var why := ""
		if row.is_empty():
			why = "未知物品 %s" % iid
		elif bool(row.get("quest_item", false)):
			why = "任務物品 %s" % str(row.get("name", iid))
		elif bool(row.get("no_transfer", false)):
			why = "不能帶走的物品 %s" % str(row.get("name", iid))
		if why != "":
			inv.remove(str(it["uid"]), n)
			removed[why] = int(removed.get(why, 0)) + n
			continue
		# M3c2 審查：珍品最多帶 FOREIGN_TREASURE_MAX 件（神兵不在這裡算：由主機登記決定）
		if str(row.get("rarity", "")) == "TREASURE" and not bool(row.get("divine", false)):
			var keep := clampi(FOREIGN_TREASURE_MAX - treasure, 0, n)
			treasure += keep
			if keep < n:
				inv.remove(str(it["uid"]), n - keep)
				var wt := "超過 %d 件的珍品 %s" % [FOREIGN_TREASURE_MAX, str(row.get("name", iid))]
				removed[wt] = int(removed.get(wt, 0)) + (n - keep)
				if keep <= 0:
					continue
				n = keep
		var stack := maxi(1, CharData.to_int(row.get("stack", 1), 1))
		if n > stack:
			inv.remove(str(it["uid"]), n - stack)
			var w2 := "超過堆疊上限的 %s" % str(row.get("name", iid))
			removed[w2] = int(removed.get(w2, 0)) + (n - stack)
	# 件數上限
	while inv.pieces() > Inventory.MAX_PIECES and not inv.items.is_empty():
		var last: Dictionary = inv.items[inv.items.size() - 1]
		var w3 := "超過背包件數的 %s" % CharData.item_name(tables, str(last["id"]))
		removed[w3] = int(removed.get(w3, 0)) + int(last["n"])
		inv.remove(str(last["uid"]), int(last["n"]))
	# 裝備：放錯欄的搬回正確的欄；不符合裝備條件的卸到背包
	inv.fix_slots(tables)
	for slot in Inventory.SLOTS:
		var uid := str(inv.equipped.get(slot, ""))
		if uid == "":
			continue
		var it2 := inv.find(uid)
		var r2 := CharData.row(tables, "items", str(it2.get("id", "")))
		if Inventory.requirement_reason(r2, ch, tables, options, rules) != "":
			inv.equipped[slot] = ""
			dropped.append("卸下不符合裝備條件的 %s（留在背包）" % str(r2.get("name", it2.get("id", ""))))
	# 負重：從單件最重的開始拿掉
	var cap := int(ch.derived(tables, options).get("carry_max", 0))
	var guard := 0
	while inv.weight(tables) > cap and not inv.items.is_empty() and guard < 10000:
		guard += 1
		var heavy: Dictionary = {}
		var hw := -1
		for it3 in inv.items:
			var w := CharData.to_int(CharData.row(tables, "items", str(it3["id"])).get("weight", 0))
			if w > hw:
				hw = w
				heavy = it3
		if hw <= 0:
			break
		var w4 := "超過負重的 %s" % CharData.item_name(tables, str(heavy["id"]))
		removed[w4] = int(removed.get(w4, 0)) + 1
		inv.remove(str(heavy["uid"]), 1)
	var keys := removed.keys()
	keys.sort()
	for k in keys:
		dropped.append("%s ×%d" % [str(k), int(removed[k])])
	var divine: Array = []
	for it4 in inv.items:
		var iid4 := str(it4.get("id", ""))
		if bool(CharData.row(tables, "items", iid4).get("divine", false)) and not divine.has(iid4):
			divine.append(iid4)
	return divine

static func _reset_world_bound(ch: Character, tables: Dictionary, dropped: Array) -> void:
	var bm := int(ch.bank.get("money", 0))
	var bi: Array = ch.bank.get("items", []) if ch.bank.get("items") is Array else []
	if bm > 0 or not bi.is_empty():
		# M3c2 第二輪審查：0 的部分不寫
		var bp: Array = []
		if bm > 0:
			bp.append("銀兩 %d" % bm)
		if not bi.is_empty():
			bp.append("物品 %d 件" % bi.size())
		dropped.append("錢莊存款（留在原世界）：" + "、".join(bp))
	ch.bank = Character.default_bank()
	if ch.guild != "":
		dropped.append("組織（留在原世界）")
	ch.guild = ""
	ch.sect_rank_pending = {}
	var active: Dictionary = ch.quests.get("active", {}) if ch.quests.get("active") is Dictionary else {}
	if not active.is_empty():
		dropped.append("進行中的任務 %d 件（留在原世界）" % active.size())
	var done: Variant = ch.quests.get("done", {})
	ch.quests = { "active": {}, "done": (done as Dictionary).duplicate(true) if done is Dictionary else {}, "cd": {} }
	ch.counters = Character.default_counters()
	if not ch.jail.is_empty():
		dropped.append("坐牢狀態（留在原世界）")
	ch.jail = {}
	ch.sect_record["breached"] = {}
	ch.sect_record["ban_until_online_s"] = 0.0
	ch.sect_record["lockout"] = ""
	ch.buffs = { "smoke_until_s": 0.0 }
	var keep_ext := {}
	for k in EXT_KEEP:
		if ch.ext.has(k):
			keep_ext[k] = ch.ext[k]
	ch.ext = keep_ext
	# 記錄點與位置 → 本世界出生城（出生城不在本世界 → 西夏）
	var city := ch.birth_city
	var reg := CharData.row(tables, "regions", city)
	if reg.is_empty() or not bool(reg.get("birth_allowed", false)) or str(reg.get("birth_room", "")) == "":
		city = FALLBACK_CITY
		reg = CharData.row(tables, "regions", city)
		ch.birth_city = city
	ch.location = { "region": city, "room": str(reg.get("birth_room", "")) }
	ch.respawn = { "region": "", "room": "" }

static func _summary(ch: Character, tables: Dictionary, divine: Array) -> Dictionary:
	var sk: Array = []
	for sid in ch.skills.entries:
		if SkillBook.kind_of(sid, tables) == SkillBook.KIND_LIFE:
			continue
		sk.append([str(sid), ch.skills.level(sid)])
	sk.sort_custom(func(a, b): return int(a[1]) > int(b[1]) or (int(a[1]) == int(b[1]) and str(a[0]) < str(b[0])))
	var top: Array = []
	for i in mini(TOP_SKILLS_N, sk.size()):
		top.append([SkillBook.skill_name(str(sk[i][0]), tables), int(sk[i][1])])
	var dn: Array = []
	for iid in divine:
		dn.append(CharData.item_name(tables, str(iid)))
	return {
		"name": ch.name, "gender": ch.gender, "sect": ch.sect, "sect_name": CharData.sect_name(tables, ch.sect),
		"combat_xp": ch.combat_xp, "money": ch.money, "items_n": ch.inventory.pieces(), "top_skills": top,
		"divine": divine.duplicate(), "divine_names": dn,
	}
