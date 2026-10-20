class_name Passport
extends RefCounted
## 角色護照（M2_PLAN 4.6.8、TECH_ARCH 8.4）：主機把角色存檔連同簽章送給玩家保管，主機存檔遺失時用來還原。
##
## 誠實說明（UI 與 README 照寫）：簽章只證明「沒有主機檔案存取權的人改過護照會被發現」（可察覺竄改）；
## 它不防主機玩家本人、拿到主機存檔（world_secret）的人、改程式的人；對別的世界完全無法驗證。
## 護照是災難復原工具，不是防作弊。
##
## 護照字典：{ "v": 1, "world_id", "char_id", "identity", "name", "char": <角色存檔字典>, "sig", "saved_s" }

const VERSION := 1
const REQUIRED := ["v", "world_id", "char_id", "identity", "name", "char", "sig", "saved_s"]

## 正規化字串：先經 Character 往返一次（補預設、型別一致），再把整數值的 float 一律轉成 int，最後排序鍵輸出。
## M2_PLAN 缺漏：契約只寫「往返一次」；巢狀字典（counters、flags 等）在 JSON 存讀後 int 會變 float（5 → 5.0），
## 往返不一定修得回來，所以這裡多做一步數值正規化，讓「送出時」與「存成 JSON 再讀回」的正規化字串相同。
## legacy = true：背包物品不含 lots（2026-10 物品堆疊改版前簽的護照用這個格式驗證）
## pre_m3b = true：M3b 以前的存檔沒有 M3B_KEYS（錢莊、組織、袋位）；護照裡沒有這些鍵時，正規化也不加（M3b 審查）
const M3B_KEYS := ["bank", "guild", "sect_rank", "sect_rank_pending"]
## pre_m3c = true（M3c 整合）：M3c 以前的存檔沒有 appearance、裝備只有 WEAPON／ARMOR 兩格；護照裡沒有時正規化也不加
const M3C_KEYS := ["appearance"]
const PRE_M3C_SLOTS := ["WEAPON", "ARMOR"]

static func canonical(char_dict: Dictionary, legacy := false, pre_m3b := false, pre_m3c := false) -> String:
	var ch = Character.from_dict(char_dict)
	var d: Variant = ch.to_dict() if ch != null else char_dict
	if legacy and ch != null and d is Dictionary:
		d["inventory"] = ch.inventory.to_dict(true)
	if pre_m3b and d is Dictionary:
		for k in M3B_KEYS:
			if not char_dict.has(k):
				(d as Dictionary).erase(k)
	if pre_m3c and d is Dictionary:
		for k in M3C_KEYS:
			if not char_dict.has(k):
				(d as Dictionary).erase(k)
		var inv: Variant = (d as Dictionary).get("inventory")
		if inv is Dictionary and (inv as Dictionary).get("equipped") is Dictionary:
			var eq := {}
			for slot in PRE_M3C_SLOTS:
				eq[slot] = (inv["equipped"] as Dictionary).get(slot, "")
			inv["equipped"] = eq
	return JSON.stringify(_normalize(d), "", true)

static func _normalize(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[str(k)] = _normalize(v[k])
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for x in v:
				arr.append(_normalize(x))
			return arr
		TYPE_FLOAT:
			var f: float = v
			if is_finite(f) and f == floorf(f) and absf(f) < 9.0e15:
				return int(f)
			return f
		TYPE_STRING_NAME:
			return str(v)
	return v

static func sign(world_secret: String, world_id: String, char_dict: Dictionary) -> String:
	return (world_secret + world_id + canonical(char_dict)).sha256_text()

## 格式檢查：回傳 "" 或 "passport_bad_format"
static func check_format(passport: Dictionary) -> String:
	for k in REQUIRED:
		if not passport.has(k):
			return "passport_bad_format"
	if not (typeof(passport["v"]) in [TYPE_INT, TYPE_FLOAT]) or int(passport["v"]) != VERSION:
		return "passport_bad_format"
	for k in ["world_id", "char_id", "identity", "name", "sig"]:
		if typeof(passport[k]) != TYPE_STRING or str(passport[k]) == "":
			return "passport_bad_format"
	if not (passport["char"] is Dictionary):
		return "passport_bad_format"
	var c: Dictionary = passport["char"]
	if str(c.get("id", "")) != str(passport["char_id"]) or str(c.get("identity", "")) == "" or str(c.get("name", "")) == "":
		return "passport_bad_format"
	if not (typeof(c.get("schema_version")) in [TYPE_INT, TYPE_FLOAT]) or int(c["schema_version"]) != Character.SCHEMA_VERSION:
		return "passport_bad_format"
	if not (typeof(passport["saved_s"]) in [TYPE_INT, TYPE_FLOAT]):
		return "passport_bad_format"
	return ""

static func verify(world_secret: String, world_id: String, passport: Dictionary) -> bool:
	if check_format(passport) != "":
		return false
	if str(passport["world_id"]) != world_id:
		return false
	if Passport.sign(world_secret, world_id, passport["char"]) == str(passport["sig"]):
		return true
	# 改版前的護照：物品沒有 lots（堆疊改版前）、沒有 M3b 欄位（M3b 以前）——簽章是用當時的格式算的，四種組合都試
	var c: Dictionary = passport["char"]
	var pre_m3b := _is_pre_m3b(c)
	var pre_m3c := _is_pre_m3c(c)
	for legacy in ([false, true] if _is_legacy(c) else [false]):
		for strip in ([false, true] if pre_m3b else [false]):
			for strip_c in ([false, true] if pre_m3c else [false]):
				if not legacy and not strip and not strip_c:
					continue
				if (world_secret + world_id + canonical(c, legacy, strip, strip_c)).sha256_text() == str(passport["sig"]):
					return true
	return false

## 護照角色沒有 appearance → M3c 以前簽的（M3c 整合：8 格裝備與外觀改了簽章格式，0.5.0.0 的護照要照樣驗得過）
## M3c 審查：舊格式只簽 WEAPON／ARMOR；裝備欄另有其他鍵（HEAD、RING…）的護照不可能是 M3c 以前簽的——
## 否則有人在 0.5.0.0 的護照裡加上 equipped.HEAD 等，簽章照樣驗得過、還原時直接裝上（繞過 Inventory.equip 的條件）
static func _is_pre_m3c(char_dict: Dictionary) -> bool:
	for k in M3C_KEYS:
		if char_dict.has(k):
			return false
	var inv: Variant = char_dict.get("inventory", {})
	if inv is Dictionary and (inv as Dictionary).get("equipped") is Dictionary:
		for slot in (inv["equipped"] as Dictionary):
			if not PRE_M3C_SLOTS.has(str(slot)):
				return false
	return true

## 護照角色沒有任何 M3b 欄位 → M3b 以前簽的
static func _is_pre_m3b(char_dict: Dictionary) -> bool:
	for k in M3B_KEYS:
		if char_dict.has(k):
			return false
	return true

static func _is_legacy(char_dict: Dictionary) -> bool:
	var inv: Variant = char_dict.get("inventory", {})
	if not (inv is Dictionary):
		return true
	for it in inv.get("items", []):
		if it is Dictionary and it.has("lots"):
			return false
	return true

## 建立護照：char_dict 是 Character.to_dict() 的結果
static func make(world_secret: String, world_id: String, char_dict: Dictionary, saved_s: float) -> Dictionary:
	return {
		"v": VERSION,
		"world_id": world_id,
		"char_id": str(char_dict.get("id", "")),
		"identity": str(char_dict.get("identity", "")),
		"name": str(char_dict.get("name", "")),
		"char": char_dict,
		"sig": Passport.sign(world_secret, world_id, char_dict),
		"saved_s": saved_s,
	}
