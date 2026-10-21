class_name Character
extends RefCounted
## 角色模型（M1_PLAN 3.2.1、3.10.1）。純資料＋規則，不引用 Autoload。

## 存檔格式版本（檔案的 schema_version）。M3A_PLAN 3.11 寫「1 → 2」，但 SaveManager（凍結檔）只接受
## CHARACTER_SCHEMA_VERSION == 1、Passport 以本常數比對護照：升成 2 會讓所有角色檔被當成損壞、護照全部作廢。
## M3A_PLAN 缺漏：檔案格式維持 1，M3a 的資料版本另外寫在 data_version（DATA_VERSION = 2）；from_dict 讀舊檔補預設。
const SCHEMA_VERSION := 1
## M3B_PLAN §4.12：2 → 3（sect_rank、sect_rank_pending、bank、guild；from_dict 補預設）
const DATA_VERSION := 3
const SECT_HISTORY_MAX := 20
const ATTR_IDS := ["str", "guts", "wit", "luck", "cal", "agi", "con"]
const VITAL_IDS := ["jing", "qi", "shen", "neili", "food", "water"]
const MONEY_CAP := 6000000
const MAX_CHARS_PER_IDENTITY := 3
const MORALITY_MIN := -1000
const MORALITY_MAX := 1000
const SPECIAL_ARTS_MAX := 16
const LITERACY_WIT_CAP := 10      # 讀書識字給悟性的上限【已證實】
const FOOD_MAX := 100
const WATER_MAX := 100

var id: String = ""
var identity: String = ""
var name: String = ""
var gender: String = "M"
var birth_month: int = 1
var birth_city: String = ""
var created_s: float = 0.0
var online_s: float = 0.0
var attrs: Dictionary = {}
var vitals: Dictionary = {}
var combat_xp: int = 0
var learn_points: int = 0
var lili: int = 0
var fame: int = 0
var morality: int = 0
var killing_intent: int = 0
var pk: int = 0                 # M2：PK值「基準值」，搭配 pk_stamp_s 惰性遞減；目前值用 pk_value()
var pk_stamp_s: float = 0.0     # 上次把 pk 正規化時的 online_s（M2_PLAN 4.6.5）
var prefs: Dictionary = default_prefs()   # 系統開關【已證實：開關存在】
var origin_world: String = ""   # 外來角色的來源世界（P2）
var money: int = 0
var sect: String = ""
var sect_enemies: Array = []
## 叛徒記號（M3a 審查修正）：叛派／開除過的門派。公敵（sect_enemies）坐完牢可以改過自新被移除，
## 但叛徒記號永遠留著 → 永遠不能再拜入（研究：「公敵 never rejoin」「未被星宿派做上叛徒標記」「武當公敵 never re-enter」）
var sect_traitor: Array = []
var skills: SkillBook = SkillBook.new()
var inventory: Inventory = Inventory.new()
var location: Dictionary = { "region": "", "room": "" }
var respawn: Dictionary = { "region": "", "room": "" }
var quests: Dictionary = { "active": {}, "done": {}, "cd": {} }   # STORY_PLAN §4.7（QuestState）
var flags: Dictionary = {}
var buffs: Dictionary = { "smoke_until_s": 0.0 }
var qi_bonus: int = 0
var cultivations: int = 0
var counters: Dictionary = default_counters()
var dead_count: int = 0
var dormant: Dictionary = {}
# ---- M3a（M3A_PLAN 3.11） ----
var sect_master: String = ""                     # personal_master 門派（全真）的師父 NPC id
var sect_record: Dictionary = default_sect_record()
var jail: Dictionary = {}                        # 坐牢中：{ sect, room, until_online_s, reason: BREACH/ENEMY, rule }
var conditions: Dictionary = {}                  # 戰後持續狀態：status_id -> { level, ticks_left, next_online_s[, actions_left] }
# ---- 故事包（STORY_PLAN §4.7、D18） ----
var lilian: int = 0                              # 江湖歷練（存檔鍵 "lilian"）
var ext: Dictionary = {}                         # 各系統私用的持久資料：{ "ambient": {...}, "wander": {...} }（鍵 = 系統名）
var appearance: int = 0                          # 初始造型編號 0–8（Looks；純外觀）   # M3c WP-LOOKS
# ---- M3b（M3B_PLAN §4.12） ----
var sect_rank: int = 0                           # 本派位階（WP-SECT）；拜入＝promote JOIN 的列（0）；離派／叛派歸 0
var sect_rank_pending: Dictionary = {}           # 等聚會：{ sect, rank, since_world_s }（WP-SECT）
var bank: Dictionary = default_bank()            # 錢莊（WP-ECON）：{ money, items: [與 inventory.items 同形狀的列] }
var guild: String = ""                           # 組織 id 快取（WP-ORG；權威在 world.guilds，登入時校正）
## 不存檔：主機每 tick 依 PartySystem 填入的隊伍 id（to_combatant 的 party_id）
var party_id: String = ""

func _init() -> void:
	for a in ATTR_IDS:
		attrs[a] = 0
	for v in VITAL_IDS:
		vitals[v] = 0

const PREF_KEYS := ["accept_challenge", "accept_party"]

static func default_prefs() -> Dictionary:
	return { "accept_challenge": true, "accept_party": true }

## WP-CHAR 自訂的計時／累計器（3.2.7）
static func default_counters() -> Dictionary:
	return {
		"food_acc_s": 0.0,          # 飽食下降的時間餘數
		"water_acc_s": 0.0,         # 飲水下降的時間餘數
		"regen_acc_s": 0.0,         # 自然回復的時間餘數
		"last_meditate_s": -1.0,    # < 0 = 從未打坐
		"med_uses": [],             # 最近服藥時間戳（世界時間）
		"last_birthday_year": 0,
		"last_meal_key": "",
	}

static func default_bank() -> Dictionary:
	return { "money": 0, "items": [] }

static func default_sect_record() -> Dictionary:
	return { "joined_online_s": 0.0, "breached": {}, "ban_until_online_s": 0.0, "history": [], "lockout": "" }

# ---------------------------------------------------------------- 序列化

static func from_dict(d: Dictionary) -> Character:
	var c := Character.new()
	c.id = CharData.to_str(d.get("id", ""))
	c.identity = CharData.to_str(d.get("identity", ""))
	c.name = CharData.to_str(d.get("name", ""))
	c.gender = CharData.to_str(d.get("gender", "M"))
	c.birth_month = clampi(CharData.to_int(d.get("birth_month", 1), 1), 1, 12)
	c.birth_city = CharData.to_str(d.get("birth_city", ""))
	c.created_s = CharData.to_float(d.get("created_s", 0.0))
	c.online_s = CharData.to_float(d.get("online_s", 0.0))
	var a: Variant = d.get("attrs", {})
	for k in ATTR_IDS:
		c.attrs[k] = CharData.to_int(a.get(k, 0)) if typeof(a) == TYPE_DICTIONARY else 0
	var v: Variant = d.get("vitals", {})
	for k in VITAL_IDS:
		c.vitals[k] = CharData.to_int(v.get(k, 0)) if typeof(v) == TYPE_DICTIONARY else 0
	c.combat_xp = CharData.to_int(d.get("combat_xp", 0))
	c.learn_points = CharData.to_int(d.get("learn_points", 0))
	c.lili = CharData.to_int(d.get("lili", 0))
	c.fame = CharData.to_int(d.get("fame", 0))
	c.morality = CharData.to_int(d.get("morality", 0))
	c.killing_intent = CharData.to_int(d.get("killing_intent", 0))
	c.pk = maxi(0, CharData.to_int(d.get("pk", 0)))
	c.pk_stamp_s = CharData.to_float(d.get("pk_stamp_s", 0.0))
	c.prefs = _prefs_from(d.get("prefs", {}))
	c.origin_world = CharData.to_str(d.get("origin_world", ""))
	c.money = CharData.to_int(d.get("money", 0))
	c.sect = CharData.to_str(d.get("sect", ""))
	c.sect_enemies = []
	for s in (d.get("sect_enemies", []) if d.get("sect_enemies", []) is Array else []):
		if CharData.to_str(s) != "":
			c.sect_enemies.append(CharData.to_str(s))
	c.sect_traitor = []
	for s in (d.get("sect_traitor", []) if d.get("sect_traitor", []) is Array else []):
		if CharData.to_str(s) != "" and not c.sect_traitor.has(CharData.to_str(s)):
			c.sect_traitor.append(CharData.to_str(s))
	c.skills = SkillBook.from_dict(_dict(d.get("skills", {})))
	c.inventory = Inventory.from_dict(_dict(d.get("inventory", {})))
	c.location = _place(d.get("location", {}))
	c.respawn = _place(d.get("respawn", {}))
	c.quests = QuestState.migrate(_dict(d.get("quests", {})))   # STORY_PLAN §4.12：舊 {step, counts}、done:int 自動遷移
	c.flags = _dict(d.get("flags", {})).duplicate(true)
	c.buffs = { "smoke_until_s": 0.0 }
	var b := _dict(d.get("buffs", {}))
	for k in b:
		c.buffs[k] = CharData.to_float(b[k]) if typeof(b[k]) in [TYPE_INT, TYPE_FLOAT] else b[k]
	c.qi_bonus = CharData.to_int(d.get("qi_bonus", 0))
	c.cultivations = CharData.to_int(d.get("cultivations", 0))
	c.counters = _counters_from(_dict(d.get("counters", {})))
	c.dead_count = CharData.to_int(d.get("dead_count", 0))
	c.dormant = _dict(d.get("dormant", {})).duplicate(true)
	# M3a：舊檔（沒有 data_version）沒有這些欄位 → 預設值
	c.sect_master = CharData.to_str(d.get("sect_master", ""))
	c.sect_record = _sect_record_from(d.get("sect_record", {}))
	c.jail = _jail_from(d.get("jail", {}))
	c.conditions = _conditions_from(d.get("conditions", {}))
	# 故事包：舊檔沒有 → 0／{}
	c.lilian = maxi(0, CharData.to_int(d.get("lilian", 0)))
	c.ext = _dict(d.get("ext", {})).duplicate(true)
	# M3c 初始造型：舊檔沒有 → 0；不合法 → 0   # M3c WP-LOOKS
	c.appearance = Looks.sanitize(d.get("appearance", 0))   # M3c WP-LOOKS
	# M3b（DATA_VERSION 3）：舊檔沒有 → 預設值
	c.sect_rank = maxi(0, CharData.to_int(d.get("sect_rank", 0)))
	c.sect_rank_pending = _rank_pending_from(d.get("sect_rank_pending", {}))
	c.bank = _bank_from(d.get("bank", {}))
	c.guild = CharData.to_str(d.get("guild", "")) if typeof(d.get("guild", "")) == TYPE_STRING else ""
	return c

static func _rank_pending_from(v: Variant) -> Dictionary:
	var d := _dict(v)
	if CharData.to_str(d.get("sect", "")) == "":
		return {}
	return { "sect": CharData.to_str(d.get("sect", "")), "rank": maxi(0, CharData.to_int(d.get("rank", 0))),
		"since_world_s": CharData.to_float(d.get("since_world_s", 0.0)) }

## 錢莊：money ≥ 0；items 的每一列照 Inventory 的列格式清理（uid、id、n、born_s；其他鍵原樣保留給 WP-ECON）
static func _bank_from(v: Variant) -> Dictionary:
	var d := _dict(v)
	var out := default_bank()
	out["money"] = maxi(0, CharData.to_int(d.get("money", 0)))
	var items: Array = []
	var src: Variant = d.get("items", [])
	if typeof(src) == TYPE_ARRAY:
		for it in src:
			if typeof(it) != TYPE_DICTIONARY:
				continue
			var n := CharData.to_int(it.get("n", 1), 1)
			if n <= 0 or CharData.to_str(it.get("uid", "")) == "" or CharData.to_str(it.get("id", "")) == "":
				continue
			var e: Dictionary = (it as Dictionary).duplicate(true)
			e["uid"] = CharData.to_str(it["uid"])
			e["id"] = CharData.to_str(it["id"])
			e["n"] = n
			e["born_s"] = CharData.to_float(it.get("born_s", 0.0))
			if it.get("lots") is Array:
				var lots: Array = []
				for lot in it["lots"]:
					if typeof(lot) == TYPE_DICTIONARY:
						lots.append({ "born_s": CharData.to_float(lot.get("born_s", 0.0)), "n": CharData.to_int(lot.get("n", 0)) })
				e["lots"] = lots
			items.append(e)
	out["items"] = items
	for k in d:
		if not out.has(k):
			out[k] = d[k]   # WP-ECON 自訂的鍵原樣保留
	return out

static func _sect_record_from(v: Variant) -> Dictionary:
	var d := _dict(v)
	var r := default_sect_record()
	r["joined_online_s"] = CharData.to_float(d.get("joined_online_s", 0.0))
	r["ban_until_online_s"] = CharData.to_float(d.get("ban_until_online_s", 0.0))
	r["lockout"] = CharData.to_str(d.get("lockout", "")) if typeof(d.get("lockout", "")) == TYPE_STRING else ""
	var br := {}
	var src_br := _dict(d.get("breached", {}))
	for k in src_br:
		if bool(src_br[k]):
			br[CharData.to_str(k)] = true
	r["breached"] = br
	var hist: Array = []
	var src_h: Variant = d.get("history", [])
	if typeof(src_h) == TYPE_ARRAY:
		for h in src_h:
			if typeof(h) == TYPE_DICTIONARY:
				hist.append({ "sect": CharData.to_str(h.get("sect", "")), "what": CharData.to_str(h.get("what", "")),
					"online_s": CharData.to_float(h.get("online_s", 0.0)) })
	while hist.size() > SECT_HISTORY_MAX:
		hist.pop_front()
	r["history"] = hist
	return r

static func _jail_from(v: Variant) -> Dictionary:
	var d := _dict(v)
	if d.is_empty() or CharData.to_str(d.get("sect", "")) == "":
		return {}
	return { "sect": CharData.to_str(d.get("sect", "")), "room": CharData.to_str(d.get("room", "")),
		"until_online_s": CharData.to_float(d.get("until_online_s", 0.0)),
		"reason": CharData.to_str(d.get("reason", "BREACH")), "rule": CharData.to_str(d.get("rule", "")),
		"days": maxi(1, CharData.to_int(d.get("days", 1), 1)), "notified": bool(d.get("notified", true)),
		# M3B_PLAN §5.1.4：SECT（各派思過處）／CAPITAL（京城監獄）；舊檔 → SECT
		"scope": "CAPITAL" if CharData.to_str(d.get("scope", "SECT")) == "CAPITAL" else "SECT" }

static func _conditions_from(v: Variant) -> Dictionary:
	var out := {}
	var d := _dict(v)
	for k in d:
		var e := _dict(d[k])
		var lv := CharData.to_int(e.get("level", 0))
		var ticks := CharData.to_int(e.get("ticks_left", 0))
		if lv <= 0 or ticks <= 0:
			continue
		out[CharData.to_str(k)] = { "level": lv, "ticks_left": ticks, "next_online_s": CharData.to_float(e.get("next_online_s", 0.0)) }
		if e.has("actions_left"):
			out[CharData.to_str(k)]["actions_left"] = maxi(0, CharData.to_int(e.get("actions_left", 0)))
	return out

func to_dict() -> Dictionary:
	var a := {}
	for k in ATTR_IDS:
		a[k] = int(attrs.get(k, 0))
	var v := {}
	for k in VITAL_IDS:
		v[k] = int(vitals.get(k, 0))
	return {
		"schema_version": SCHEMA_VERSION,
		"id": id, "identity": identity, "name": name, "gender": gender,
		"birth_month": birth_month, "birth_city": birth_city,
		"created_s": created_s, "online_s": online_s,
		"attrs": a, "vitals": v,
		"combat_xp": combat_xp, "learn_points": learn_points, "lili": lili, "fame": fame,
		"morality": morality, "killing_intent": killing_intent, "pk": pk,
		"pk_stamp_s": pk_stamp_s, "prefs": prefs.duplicate(), "origin_world": origin_world,
		"money": money, "sect": sect, "sect_enemies": sect_enemies.duplicate(),
		"sect_traitor": sect_traitor.duplicate(),
		"skills": skills.to_dict(),
		"inventory": inventory.to_dict(),
		"location": location.duplicate(),
		"respawn": respawn.duplicate(),
		"quests": quests.duplicate(true),
		"flags": flags.duplicate(true),
		"buffs": buffs.duplicate(true),
		"qi_bonus": qi_bonus, "cultivations": cultivations,
		"counters": counters.duplicate(true),
		"dead_count": dead_count,
		"dormant": dormant.duplicate(true),
		"data_version": DATA_VERSION,
		"sect_master": sect_master,
		"sect_record": sect_record.duplicate(true),
		"jail": jail.duplicate(true),
		"conditions": conditions.duplicate(true),
		"lilian": lilian,
		"ext": ext.duplicate(true),
		"appearance": appearance,   # M3c WP-LOOKS
		"sect_rank": sect_rank,
		"sect_rank_pending": sect_rank_pending.duplicate(true),
		"bank": bank.duplicate(true),
		"guild": guild,
	}

static func _dict(v: Variant) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}

static func _prefs_from(v: Variant) -> Dictionary:
	var out := default_prefs()
	var d := _dict(v)
	for k in PREF_KEYS:
		if d.has(k):
			out[k] = bool(d[k])
	return out

static func _place(v: Variant) -> Dictionary:
	var d := _dict(v)
	return { "region": CharData.to_str(d.get("region", "")), "room": CharData.to_str(d.get("room", "")) }

## 舊 API（M1）：改由 QuestState.migrate 處理新舊格式
static func _quests_from(v: Variant) -> Dictionary:
	return QuestState.migrate(_dict(v))

static func _counters_from(d: Dictionary) -> Dictionary:
	var c := default_counters()
	for k in d:
		c[k] = d[k]
	for k in ["food_acc_s", "water_acc_s", "regen_acc_s", "last_meditate_s"]:
		c[k] = CharData.to_float(c[k], -1.0 if k == "last_meditate_s" else 0.0)
	c["last_birthday_year"] = CharData.to_int(c["last_birthday_year"])
	c["last_meal_key"] = CharData.to_str(c["last_meal_key"])
	var uses: Array = []
	for t in (c["med_uses"] if typeof(c["med_uses"]) == TYPE_ARRAY else []):
		uses.append(CharData.to_float(t))
	c["med_uses"] = uses
	return c

# ---------------------------------------------------------------- 數值

func effective_attrs(tables: Dictionary, options: Dictionary) -> Dictionary:
	var a := {}
	for k in ATTR_IDS:
		a[k] = int(attrs.get(k, 0))
	for slot in Inventory.SLOTS:
		var r := inventory.equipped_row(slot, tables)
		for e in r.get("effects", []):
			if typeof(e) == TYPE_DICTIONARY and e.get("type", "") == "attr" and a.has(e.get("stat", "")):
				a[e["stat"]] += CharData.to_int(e.get("value", 0))
		# M3C_PLAN §6.2、§6.3：裝備的屬性加成 bonus { attr: int }（只限 ATTR_IDS）
		var bonus: Variant = r.get("bonus", {})
		if typeof(bonus) == TYPE_DICTIONARY:
			for attr in bonus:
				if a.has(String(attr)):
					a[String(attr)] += CharData.to_int(bonus[attr])
	# 讀書識字每 10 級 +1 悟性，最多 +10【已證實】（上限讀 basic_skills.attr_bonus_cap.wit）
	var lit_cap: Variant = CharData.row(tables, "basic_skills", "basic_literacy").get("attr_bonus_cap", {})
	var lit_max := CharData.to_int(lit_cap.get("wit", LITERACY_WIT_CAP), LITERACY_WIT_CAP) \
		if typeof(lit_cap) == TYPE_DICTIONARY else LITERACY_WIT_CAP
	a["wit"] += mini(lit_max, floori(skills.level("basic_literacy") / 10.0))
	if bool(options.get("attr_from_basic_skills", false)):
		for sid in skills.entries:
			if sid == "basic_literacy":
				continue   # 上面已算過
			var br := CharData.row(tables, "basic_skills", sid)
			if br.is_empty():
				continue
			var per10: Variant = br.get("attr_bonus_per10", {})
			if typeof(per10) != TYPE_DICTIONARY:
				continue
			var caps: Variant = br.get("attr_bonus_cap", {})
			var tens := floori(skills.level(sid) / 10.0)
			for attr in per10:
				if a.has(attr):
					var bonus: int = tens * CharData.to_int(per10[attr])
					if typeof(caps) == TYPE_DICTIONARY and caps.has(attr):
						bonus = mini(bonus, CharData.to_int(caps[attr]))   # 14/15/14【已證實】
					a[attr] += bonus
	return a

func derived(tables: Dictionary, options: Dictionary) -> Dictionary:
	return DerivedStats.compute(self, tables, options)

func clamp_vitals(tables: Dictionary, options: Dictionary) -> void:
	var d := derived(tables, options)
	for k in ["jing", "qi", "shen", "neili"]:
		vitals[k] = clampi(int(vitals.get(k, 0)), 0, int(d[k + "_max"]))
	vitals["food"] = clampi(int(vitals.get("food", 0)), 0, FOOD_MAX)
	vitals["water"] = clampi(int(vitals.get("water", 0)), 0, WATER_MAX)

func add_money(n: int) -> int:
	var before := money
	money = clampi(money + n, 0, MONEY_CAP)
	return money - before

func add_learn_points(n: int, rules: Dictionary) -> int:
	var before := learn_points
	var after := learn_points + n
	var cap := CharData.to_int(rules.get("xuedian_cap", 0))
	if n > 0 and cap > 0:
		after = min(after, max(cap, learn_points))
	learn_points = max(0, after)
	return learn_points - before

# ---------------------------------------------------------------- PK、善惡、殺氣（M2_PLAN 4.6.5）

## M3d WP-LAW（M3D_PLAN §2.6）：規則 pk_decay（執行期欄位，**不存檔**；GameHost 在載入與規則變更時設定，
## balance_sim 與測試直接設）。false＝2001 沒有被動遞減（classic_strict）
var pk_decay_on: bool = true

## 目前的 PK值（pk_decay_on 時扣除依上線時間的遞減）
func pk_value() -> int:
	return MoralityPk.pk_value(pk, pk_stamp_s, online_s, pk_decay_on)

## 先把基準正規化成目前值（pk_stamp_s = online_s），再加 n（可為負：緝殺、賞金獵人、守城官兵、半仙）；
## 結果最低 0；回傳新的目前值（M3D_PLAN §2.6）
func add_pk(n: int) -> int:
	pk = maxi(0, pk_value() + n)
	pk_stamp_s = online_s
	return pk

func align() -> String:
	return MoralityPk.align_of(morality)

## 回傳實際變化量（夾在 ±1000）
func add_morality(d: int) -> int:
	var before := morality
	morality = clampi(morality + d, MORALITY_MIN, MORALITY_MAX)
	return morality - before

## 回傳實際變化量（不低於 0）
func add_killing_intent(d: int) -> int:
	var before := killing_intent
	killing_intent = maxi(0, killing_intent + d)
	return killing_intent - before

# ---------------------------------------------------------------- 門派、坐牢、戰後狀態（M3A_PLAN 3.11）

func is_jailed() -> bool:
	return not jail.is_empty()

## 刑期剩餘（上線秒；K4）
func jail_left_s() -> float:
	if jail.is_empty():
		return 0.0
	return maxf(0.0, CharData.to_float(jail.get("until_online_s", 0.0)) - online_s)

## 禁止學武剩餘（上線秒）
## 犯戒（恆山：沒有執法者，違規＝進不了山、不能學、直到悔過；M3a 審查 #1）：sect_record.lockout = 觸犯的門規 id
func is_locked_out() -> bool:
	return sect != "" and String(sect_record.get("lockout", "")) != ""

func ban_left_s() -> float:
	return maxf(0.0, CharData.to_float(sect_record.get("ban_until_online_s", 0.0)) - online_s)

## 加入戰後持續狀態；已有同一狀態時取較高等級、較多次數，發作時刻沿用舊的
func add_condition(id: String, level: int, ticks: int, next_online_s: float) -> void:
	if id == "" or level <= 0 or ticks <= 0:
		return
	if conditions.has(id):
		var e: Dictionary = conditions[id]
		e["level"] = maxi(int(e.get("level", 0)), level)
		e["ticks_left"] = maxi(int(e.get("ticks_left", 0)), ticks)
		return
	conditions[id] = { "level": level, "ticks_left": ticks, "next_online_s": next_online_s }

## 回傳是否真的有這個狀態
func clear_condition(id: String) -> bool:
	return conditions.erase(id)

func condition_level(id: String) -> int:
	return int(conditions.get(id, {}).get("level", 0))

func add_sect_history(sect_id: String, what: String) -> void:
	var hist: Array = sect_record.get("history", [])
	hist.append({ "sect": sect_id, "what": what, "online_s": online_s })
	while hist.size() > SECT_HISTORY_MAX:
		hist.pop_front()
	sect_record["history"] = hist

## 叛派／開除的懲罰（M3A_PLAN 6.5、D8）。就地修改並回傳
## { sect, arts: { skill_id: [before, after] }, sect_skill: [before, 0], items_removed: [ { id, n } ] }。
## 預設（2001 各派頁、jb170）：本門武功（martial_arts.sect_id == 該派）等級減半（floor；0 就移除）、sect_only 物品沒收，門派技能不動；
## rules.betrayal_halves_basics（後期官方頁 jy2-22）：全部特殊武功與基本武學都減半、門派技能歸零。
## 最後清空 sect、sect_master，把該派加入 sect_enemies（公敵）與 sect_traitor（叛徒，永遠不能再拜入），記一筆 history。
func betray_penalty(tables: Dictionary, rules: Dictionary, what: String = "BETRAY") -> Dictionary:
	var sid := sect
	var out := { "sect": sid, "arts": {}, "sect_skill": [0, 0], "items_removed": [] }
	if sid == "":
		return out
	var all := bool(rules.get("betrayal_halves_basics", false))
	var srow := CharData.row(tables, "sects", sid)
	var ss := String(srow.get("sect_skill", ""))
	var keys: Array = skills.entries.keys()
	keys.sort()
	for k in keys:
		if k == ss:
			continue
		var kind := SkillBook.kind_of(k, tables)
		var halve := false
		if kind == SkillBook.KIND_ART:
			halve = all or String(CharData.row(tables, "martial_arts", k).get("sect_id", "")) == sid
		elif kind == SkillBook.KIND_BASIC:
			halve = all
		if not halve:
			continue
		var before := skills.level(k)
		if before <= 0:
			continue
		var after := floori(before / 2.0)
		skills.set_level(k, after, tables)
		out["arts"][k] = [before, after]
	# 門派技能歸零只屬後期官方規則（jy2-22），跟「全部減半」同一個開關；2001 各派頁只說「本門武功減半」（jb170）→ 不動
	if ss != "":
		var ss_lv := skills.level(ss)
		out["sect_skill"] = [ss_lv, 0 if all else ss_lv]
		if all:
			skills.set_level(ss, 0, tables)
	var removed: Array = []
	for it in inventory.items.duplicate():
		var r := CharData.row(tables, "items", String(it.get("id", "")))
		if String(r.get("sect_only", "")) == sid:
			var n := int(it.get("n", 1))
			inventory.remove(String(it.get("uid", "")), n)
			removed.append({ "id": String(it.get("id", "")), "n": n })
	out["items_removed"] = removed
	sect = ""
	sect_master = ""
	sect_rank = 0               # M3B_PLAN §5.1.1：叛派、開除 → 位階歸 0、清掉待升
	sect_rank_pending = {}
	if not sect_enemies.has(sid):
		sect_enemies.append(sid)
	if not sect_traitor.has(sid):
		sect_traitor.append(sid)
	sect_record["breached"] = {}
	sect_record["lockout"] = ""
	add_sect_history(sid, what)
	return out

# ---------------------------------------------------------------- 錢莊（M3B_PLAN §4.12；WP-SECT 骨架，WP-ECON 使用）

## 錢莊裡的件數（堆疊物品算 n 件；容量 bank_capacity 比的就是這個數）
func bank_pieces() -> int:
	var total := 0
	for it in bank.get("items", []):
		if typeof(it) == TYPE_DICTIONARY:
			total += maxi(0, CharData.to_int(it.get("n", 1), 1))
	return total

## 錢莊裡 uid 這一列（找不到回 {}）；回傳的是列本身（不是複本），WP-ECON 可直接改
func bank_find(uid: String) -> Dictionary:
	if uid == "":
		return {}
	for it in bank.get("items", []):
		if typeof(it) == TYPE_DICTIONARY and String(it.get("uid", "")) == uid:
			return it
	return {}

func pref(key: String) -> bool:
	return bool(prefs.get(key, default_prefs().get(key, true)))

func apply_battle_outcome(unit: Dictionary, tables: Dictionary, options: Dictionary) -> void:
	for k in ["qi", "neili", "jing", "shen"]:
		if unit.has(k):
			vitals[k] = CharData.to_int(unit[k])
	if unit.has("weapon_uid"):
		var wuid := String(unit["weapon_uid"])
		if wuid != String(inventory.equipped.get("WEAPON", "")):
			if wuid == "":
				inventory.unequip("WEAPON")
			else:
				inventory.equip(wuid, tables, self, options)   # M3c：條件不合（例：限女性）的兵器不換上
	clamp_vitals(tables, options)

func apply_rewards(r: Dictionary, rules: Dictionary) -> Dictionary:
	var xp: int = max(0, CharData.to_int(r.get("combat_xp", 0)))
	combat_xp += xp
	var lp := add_learn_points(CharData.to_int(r.get("learn_points", 0)), rules)
	var m := add_money(CharData.to_int(r.get("money", 0)))
	var f := CharData.to_int(r.get("fame", 0))
	fame += f
	var mb := morality
	morality = clampi(morality + CharData.to_int(r.get("morality", 0)), MORALITY_MIN, MORALITY_MAX)
	var kb := killing_intent
	killing_intent = max(0, killing_intent + CharData.to_int(r.get("killing_intent", 0)))
	for fl in r.get("flags", []):
		flags[String(fl)] = true
	# STORY_PLAN §4.9：江湖歷練（不低於 0）
	var lb := lilian
	lilian = maxi(0, lilian + CharData.to_int(r.get("lilian", 0)))
	return {
		"combat_xp": xp, "learn_points": lp, "money": m, "fame": f,
		"morality": morality - mb, "killing_intent": killing_intent - kb, "lilian": lilian - lb,
	}

# ---------------------------------------------------------------- 快照

func to_combatant(tables: Dictionary, options: Dictionary, side: int, peer_id: int) -> Dictionary:
	var d := derived(tables, options)
	var sk := {}
	var keys := skills.entries.keys()
	keys.sort()
	for k in keys:
		if skills.level(k) >= 1:
			sk[k] = skills.level(k)
	var arts: Array = []
	for k in skills.special_arts(tables):
		if CharData.BATTLE_CATEGORIES.has(SkillBook.category_of(k, tables)):
			arts.append(k)
	var weapon := { "uid": "", "item_id": "", "weapon_type": "FIST", "atk": 0, "name": "" }
	var wuid := String(inventory.equipped.get("WEAPON", ""))
	# M3C_PLAN §6.3：戰鬥中可換的兵器只列條件合格的（已裝備的那把一定在）
	var wopts: Array = []
	for w in inventory.weapon_options(tables):
		if w["uid"] == wuid or Inventory.requirement_reason(CharData.row(tables, "items", String(w["item_id"])), self, tables, options) == "":
			wopts.append(w)
		if w["uid"] == wuid:
			weapon = w.duplicate()
	var sect_skill := {}
	if sect != "":
		var srow := CharData.row(tables, "sects", sect)
		var ss := String(srow.get("sect_skill", ""))
		if ss != "" and skills.level(ss) >= 1:
			var eff: Variant = srow.get("sect_skill_effect", {})
			var eff_s := String(eff.get("effect", "")) if typeof(eff) == TYPE_DICTIONARY else String(eff)
			sect_skill = { "id": ss, "effect": eff_s, "level": skills.level(ss) }
	var cmax := int(d["carry_max"])
	return {
		# ---- M3a（M3A_PLAN 3.11） ----
		"gender": gender,
		"sect": sect,
		"cmd_arts": cmd_arts(tables),
		"hidden_items": hidden_items(tables),
		"battle_items": battle_items(tables),
		"statuses": combat_statuses(tables),
		"party_id": party_id,
		"kind": "PLAYER", "ref": id, "name": name, "side": side, "peer": peer_id, "ai": "",
		"look": battle_look(),   # 純表現用（戰鬥美術），不影響規則
		"attrs": d["attrs"].duplicate(),
		"qi": int(vitals["qi"]), "qi_max": int(d["qi_max"]),
		"neili": int(vitals["neili"]), "neili_max": int(d["neili_max"]),
		"jing": int(vitals["jing"]), "jing_max": int(d["jing_max"]),
		"shen": int(vitals["shen"]), "shen_max": int(d["shen_max"]),
		"skills": sk,
		"arts": arts,
		"weapon": weapon,
		"weapon_options": wopts,
		"armor_power": int(d["armor_power"]),
		"effective_inner": int(d["effective_inner"]),
		"lightness": int(d["lightness"]),
		"sect_skill": sect_skill,
		"killing_intent": killing_intent,
		"carry_ratio": (float(d["carry"]) / cmax) if cmax > 0 else 0.0,
		"monster_row": "",
		# M3c2 整合：BattleRewards 的實戰／學點比例要玩家實戰（M1_PLAN 4.8；battle_rewards.gd 檔頭「to_combatant 會帶上」）。
		# 以前漏帶 → 主機上每一場都當成實戰 0（實戰 ×2、學點 ×3 的上限），和 balance_sim 的模型不一致
		"combat_xp": combat_xp,
		# ---- M3d WP-COMBAT（M3D_PLAN §3.3.3、§3.4、§3.6） ----
		"char_id": id,                                  # 合體技找夥伴用（ref 也是角色 id）
		"combo": _combo_spec(),                         # { partner_char, moqi }；沒有夥伴 {}
		"flee_anywhere": _equipped_effect(tables, "FLEE_ANYWHERE"),   # 無敵烙跑鞋
		"equip_cd_ms": clampi(CharData.to_int(options.get("equip_cooldown_ms", 2000), 2000), 0, 5000),   # 換裝兩秒（戰鬥時間）
	}

## M3d WP-COMBAT：合體夥伴（ext.combo = { partner, moqi }；moqi 是 ComboSystem 寫的鏡像，權威在 world.combo_pairs）
func _combo_spec() -> Dictionary:
	var c: Variant = ext.get("combo", {})
	if not (c is Dictionary) or String((c as Dictionary).get("partner", "")) == "":
		return {}
	return { "partner_char": String(c["partner"]), "moqi": CharData.to_int(c.get("moqi", 0)) }

## M3d WP-COMBAT：身上裝備中有沒有某種 effects[].type（FLEE_ANYWHERE…）
func _equipped_effect(tables: Dictionary, effect_type: String) -> bool:
	for slot in inventory.equipped:
		var uid := String(inventory.equipped[slot])
		if uid == "":
			continue
		var row := CharData.row(tables, "items", String(inventory.find(uid).get("id", "")))
		for e in row.get("effects", []):
			if typeof(e) == TYPE_DICTIONARY and String(e.get("type", "")) == effect_type:
				return true
	return false

## 戰鬥指令可用的武功（M3A_PLAN 3.11、5.1）：{ POISON, MEDIC, HIDDEN, FORMATION, INNER, ACUPOINT }。
## 等級 ≥ 1、非 monster_only；INNER 依等級高到低（同級依 id）；ACUPOINT = acupoint: true 的武功（任何類別）。
const CMD_ART_CATEGORIES := ["POISON", "MEDIC", "HIDDEN", "FORMATION", "INNER"]

func cmd_arts(tables: Dictionary) -> Dictionary:
	var out := { "POISON": [], "MEDIC": [], "HIDDEN": [], "FORMATION": [], "INNER": [], "ACUPOINT": [] }
	for k in skills.special_arts(tables):
		var r := CharData.row(tables, "martial_arts", k)
		var cat := String(r.get("category", ""))
		if CMD_ART_CATEGORIES.has(cat):
			(out[cat] as Array).append(k)
		if bool(r.get("acupoint", false)):
			(out["ACUPOINT"] as Array).append(k)
	(out["INNER"] as Array).sort_custom(func(a, b):
		var la := skills.level(a)
		var lb := skills.level(b)
		return la > lb or (la == lb and String(a) < String(b)))
	return out

## 暗器堆疊：effects 有 hidden 的物品 [ { uid, item_id, name, n, dmg } ]
func hidden_items(tables: Dictionary) -> Array:
	var out: Array = []
	for it in inventory.items:
		var r := CharData.row(tables, "items", String(it.get("id", "")))
		for e in r.get("effects", []):
			if typeof(e) == TYPE_DICTIONARY and String(e.get("type", "")) == "hidden":
				out.append({ "uid": String(it["uid"]), "item_id": String(it["id"]), "name": String(r.get("name", it["id"])),
					"n": int(it["n"]), "dmg": CharData.to_int(e.get("value", 0)) })
				break
	return out

## 戰鬥中能用的藥：usable 且 usable_in_battle 的物品 [ { uid, item_id, name, n, effects } ]
func battle_items(tables: Dictionary) -> Array:
	var out: Array = []
	for it in inventory.items:
		var r := CharData.row(tables, "items", String(it.get("id", "")))
		if not bool(r.get("usable", false)) or not bool(r.get("usable_in_battle", false)):
			continue
		var effects: Variant = r.get("effects", [])
		if typeof(effects) != TYPE_ARRAY or effects.is_empty():
			continue
		var spec := { "uid": String(it["uid"]), "item_id": String(it["id"]), "name": String(r.get("name", it["id"])),
			"n": int(it["n"]), "effects": (effects as Array).duplicate(true) }
		if bool(r.get("keep_on_use", false)):
			spec["keep_on_use"] = true   # M3b 審查 3：用了不扣（絕情丹）
		out.append(spec)
	return out

## 戰後持續狀態帶進戰鬥：{ status_id: { n, level } }。n = 上一場剩下的行動次數 actions_left（沒有記錄時用 duration_actions）；
## actions_left == 0（戰鬥中的發作次數已經用完）不帶進戰鬥，只剩戰後每 2 分鐘的發作（M3a 審查修正：不因每打一場就重新計時）
func combat_statuses(tables: Dictionary) -> Dictionary:
	var out := {}
	var keys: Array = conditions.keys()
	keys.sort()
	for k in keys:
		var lv := int(conditions[k].get("level", 0))
		if lv <= 0:
			continue
		var row := CharData.row(tables, "status_effects", k)
		var n := maxi(1, CharData.to_int(row.get("duration_actions", 6), 6))
		if conditions[k].has("actions_left"):
			n = mini(n, int(conditions[k]["actions_left"]))
		if n <= 0:
			continue
		out[k] = { "n": n, "level": lv }
	return out

## 戰鬥外觀代號（純表現用）："<門派 id 或 player>_<m|f>"，例 "shaolin_m"、"player_f"。
## M3c：未入派用初始造型（"player_m"、"look_m05"…），入派後門派服裝優先。   # M3c WP-LOOKS
func battle_look() -> String:   # M3c WP-LOOKS
	return Looks.battle_look(sect, gender, appearance)   # M3c WP-LOOKS

func to_summary(tables: Dictionary) -> Dictionary:
	return {
		"char_id": id, "name": name, "gender": gender,
		"sect_name": CharData.sect_name(tables, sect),
		"combat_xp": combat_xp,
		"room_name": CharData.room_name(tables, String(location.get("room", ""))),
		"look": battle_look(),   # M3c WP-LOOKS
		# M3c2 WP-CARRY（M3C2_PLAN §5.6、§7）：外來角色標記；online_s 給匯出時比對本機護照是否最新
		"foreign": origin_world != "",
		"origin_world_name": "" if origin_world == "" else (String(ext["foreign"].get("world_name", origin_world)) if ext.get("foreign") is Dictionary else origin_world),
		"online_s": online_s,
	}

## now_s >= 0：物品帶 spoil_left_days（最早一批還剩幾天會壞；-1 ＝不會腐壞）
func to_sheet(tables: Dictionary, options: Dictionary, rules: Dictionary, now_s: float = -1.0) -> Dictionary:
	var d := derived(tables, options)
	var base := {}
	for k in ATTR_IDS:
		base[k] = int(attrs.get(k, 0))
	var sk_list: Array = []
	var keys := skills.entries.keys()
	keys.sort()
	for k in keys:
		var lv := skills.level(k)
		var maxl := SkillBook.max_level_of(k, tables)
		sk_list.append({
			"id": k, "name": SkillBook.skill_name(k, tables), "kind": SkillBook.kind_of(k, tables),
			"category": SkillBook.category_of(k, tables), "level": lv, "prof": skills.prof(k),
			"next_prof": SkillBook.prof_for_level(k, lv + 1, tables) if lv < maxl else skills.prof(k),
		})
	var inv_list: Array = []
	for it in inventory.items:
		var r := CharData.row(tables, "items", it["id"])
		var slot := String(r.get("slot", ""))
		inv_list.append({
			"uid": it["uid"], "id": it["id"], "name": String(r.get("name", it["id"])),
			"tab": String(r.get("tab", "OTHER")), "n": int(it["n"]),
			"weight": CharData.to_int(r.get("weight", 0)),
			"equipped_slot": inventory.slot_of(it["uid"]),
			"usable": bool(r.get("usable", false)),
			"equippable": Inventory.SLOTS.has(slot),
			"perishable": CharData.to_int(r.get("spoil_days", 0)) > 0,
		})
		inv_list[inv_list.size() - 1].merge(loot_fields(r, tables, options, rules))   # M3C_PLAN §6.3
		if now_s >= 0.0:
			var day_s := CharData.to_float(options.get("game_day_real_s", 7200.0))
			var left := inventory.spoil_left_s(it, now_s, day_s, tables)
			inv_list[inv_list.size() - 1]["spoil_left_days"] = left / day_s if left >= 0.0 and day_s > 0.0 else -1.0
	var region := String(location.get("region", ""))
	var room_id := String(location.get("room", ""))
	var resp_room := String(respawn.get("room", ""))
	return {
		"char_id": id, "name": name, "gender": gender, "birth_month": birth_month, "birth_city": birth_city,
		"sect": sect, "sect_name": CharData.sect_name(tables, sect),
		"attrs": d["attrs"].duplicate(), "attrs_base": base,
		"vitals": {
			"jing": int(vitals["jing"]), "jing_max": int(d["jing_max"]),
			"qi": int(vitals["qi"]), "qi_max": int(d["qi_max"]),
			"shen": int(vitals["shen"]), "shen_max": int(d["shen_max"]),
			"neili": int(vitals["neili"]), "neili_max": int(d["neili_max"]),
			"food": int(vitals["food"]), "water": int(vitals["water"]),
		},
		"carry": int(d["carry"]), "carry_max": int(d["carry_max"]),
		"combat_xp": combat_xp, "learn_points": learn_points,
		"learn_points_cap": CharData.to_int(rules.get("xuedian_cap", 0)),
		"lili": lili, "fame": fame, "morality": morality, "killing_intent": killing_intent, "pk": pk_value(),
		"align": align(), "prefs": { "accept_challenge": pref("accept_challenge"), "accept_party": pref("accept_party") },
		"money": money,
		"art_level_cap": int(d["art_level_cap"]),
		"weapon_power": int(d["weapon_power"]), "armor_power": int(d["armor_power"]),
		"special_arts": skills.special_arts(tables).size(), "special_arts_max": SPECIAL_ARTS_MAX,
		"skills": sk_list,
		"inventory": inv_list,
		"equipped": inventory.to_dict()["equipped"],   # M3C_PLAN §6.3：8 個裝備欄
		"quests": _quest_sheet(tables),
		"quests_done": _quests_done_sheet(tables),
		"quest_cd": _quest_cd_sheet(now_s),
		"lilian": lilian,
		"location": { "region": region, "region_name": CharData.region_name(tables, region),
			"room": room_id, "room_name": CharData.room_name(tables, room_id) },
		"respawn": { "room": resp_room, "room_name": CharData.room_name(tables, resp_room) if resp_room != "" else "" },
		"clock": {},
		"in_battle": false, "battle_id": 0,
		# ---- M3a（M3A_PLAN 6.12） ----
		"sect_info": sect_info(tables, options, rules),
		"enemy_of": _enemy_names(tables),
		"traitor_of": sect_traitor.map(func(x): return CharData.sect_name(tables, String(x))),
		"jail": _jail_sheet(tables),
		# M3B_PLAN §6 角色表新欄位（org、societies 由 GameHost 依 OrgSystem 補上；這裡給同形狀的預設值）
		"org": null,
		"societies": [],
		"conditions": _conditions_sheet(tables),
		"look": battle_look(), "appearance": appearance,   # M3c WP-LOOKS
	}

## M3C_PLAN §6.3：角色表背包物品的打寶欄位 { rarity, slot, req_ok, req_text, bonus, official? }
func loot_fields(r: Dictionary, tables: Dictionary, options: Dictionary, rules: Dictionary) -> Dictionary:
	var out := {
		"rarity": String(r.get("rarity", "COMMON")) if String(r.get("rarity", "")) != "" else "COMMON",
		"slot": String(r.get("slot", "")),
		"req_ok": true, "req_text": "", "bonus": {},
	}
	var bonus: Variant = r.get("bonus", {})
	if typeof(bonus) == TYPE_DICTIONARY:
		for k in bonus:
			out["bonus"][String(k)] = CharData.to_int(bonus[k])
	if typeof(r.get("official")) == TYPE_DICTIONARY:
		var o: Dictionary = r["official"]
		var off := {}
		for k in o:
			off[String(k)] = CharData.to_int(o[k])
		out["official"] = off
	var req: Variant = r.get("requires", [])
	if typeof(req) == TYPE_ARRAY and not (req as Array).is_empty():
		var bad: PackedStringArray = []
		for c in req:
			if typeof(c) == TYPE_DICTIONARY and Requirements.check([c], self, tables, options, rules) != "":
				bad.append(Requirements.describe(c, tables))
		out["req_ok"] = bad.is_empty()
		out["req_text"] = "、".join(bad)
	return out

## 角色表 sect_info：{ id, name, skill_id, skill_name, skill_level, master, stop_teach, ban_left_s, warnings }
## （沒有門派時 id 為空字串、其餘為空值）。stop_teach：jailed／sect_banned／sect_stop_teach／""。
func sect_info(tables: Dictionary, options: Dictionary, rules: Dictionary) -> Dictionary:
	var srow := CharData.row(tables, "sects", sect)
	var ss := String(srow.get("sect_skill", ""))
	return {
		"id": sect, "name": CharData.sect_name(tables, sect),
		"skill_id": ss, "skill_name": String(srow.get("sect_skill_name", "")),
		"skill_level": skills.level(ss) if ss != "" else 0,
		"master": CharData.npc_name(tables, sect_master) if sect_master != "" else "",
		"stop_teach": teach_block_reason(tables, options, rules) if sect != "" else "",
		"ban_left_s": ban_left_s() if sect != "" else 0.0,
		"warnings": rule_warnings(tables, rules) if sect != "" else [],
		# M3B_PLAN §5.1.1：{ level, name, pending: { rank, name }|null, next: { name, requires_text }|null }；本派沒有位階表時 null
		"rank": rank_sheet(tables),
	}

## 本派生效的位階列（依 rank 排序）
func rank_rows(tables: Dictionary) -> Array:
	return sect_rank_rows(tables, sect)

static func sect_rank_rows(tables: Dictionary, sect_id: String) -> Array:
	var out: Array = []
	if sect_id == "":
		return out
	var t: Variant = tables.get("sect_ranks", {})
	if not (t is Dictionary):
		return out
	for id in t:
		var r: Variant = t[id]
		if typeof(r) == TYPE_DICTIONARY and String(r.get("sect", "")) == sect_id:
			out.append(r)
	out.sort_custom(func(a, b): return CharData.to_int(a.get("rank", 0)) < CharData.to_int(b.get("rank", 0)))
	return out

func rank_sheet(tables: Dictionary) -> Variant:
	if sect == "":
		return null
	var rows := rank_rows(tables)
	if rows.is_empty():
		return null
	var cur_name := ""
	var nxt: Variant = null
	for r in rows:
		var rk := CharData.to_int(r.get("rank", 0))
		if rk == sect_rank:
			cur_name = String(r.get("name", ""))
		elif rk == sect_rank + 1 and nxt == null:
			var texts: Array = []
			for c in r.get("requires", []):
				if typeof(c) == TYPE_DICTIONARY:
					texts.append(Requirements.describe(c, tables))
			if String(r.get("promote", "")) == "QUEST" and String(r.get("quest", "")) != "":
				var q := String(r["quest"])
				texts.append("完成任務「%s」" % String(CharData.row(tables, "quests", q).get("name", q)))
			nxt = { "name": String(r.get("name", "")), "requires_text": texts }
	var pend: Variant = null
	if String(sect_rank_pending.get("sect", "")) == sect:
		var prk := CharData.to_int(sect_rank_pending.get("rank", 0))
		pend = { "rank": prk, "name": Requirements.rank_name(tables, sect, prk) }
	return { "level": sect_rank, "name": cur_name, "pending": pend, "next": nxt }

## 本派師父拒絕傳授的原因（M3A_PLAN 6.1 can_teach 的純角色部分）："" ／ jailed ／ sect_lockout ／ sect_banned ／ sect_stop_teach
func teach_block_reason(tables: Dictionary, options: Dictionary, rules: Dictionary) -> String:
	if is_jailed():
		return "jailed"
	if is_locked_out():
		return "sect_lockout"
	if ban_left_s() > 0.0:
		return "sect_banned"
	var tr: Variant = CharData.row(tables, "sects", sect).get("teach_requires", [])
	if typeof(tr) == TYPE_ARRAY and not tr.is_empty():
		if Requirements.check(tr, self, tables, options, rules) != "":
			return "sect_stop_teach"
	return ""

## 屬性燈籠（M3A_PLAN 6.12、news 318）：距離本派任一 BREACH 狀態規則門檻 10% 以內（或已越線）的屬性。
## 10% 的寬度 = max(門檻絕對值 × 10%, 下限)（下限：善惡 20、殺氣 100、PK值 1）【設計提案】；
## PK值、殺氣為 0 時不亮（例：PK值 ≤ 0 的門規，PK值 0 不算接近）。
const WARN_MIN_MARGIN := { "morality": 20, "killing_intent": 100, "pk": 1 }

func rule_warnings(tables: Dictionary, rules: Dictionary = {}) -> Array:
	var out: Array = []
	if sect == "":
		return out
	# 只看目前 sect_violation_mode 適用的門規列（sect_rules.modes；SectSystem.rules_of 同一規則）
	var mode := String(rules.get("sect_violation_mode", "JAIL"))
	var rows: Array = CharData.rows(tables, "sect_rules")
	rows.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	for r in rows:
		if typeof(r) != TYPE_DICTIONARY or String(r.get("sect", "")) != sect or String(r.get("kind", "")) != "STATE":
			continue
		var modes: Variant = r.get("modes", [])
		if typeof(modes) == TYPE_ARRAY and not modes.is_empty() and not modes.has(mode):
			continue
		for c in r.get("ok_if", []):
			if typeof(c) != TYPE_DICTIONARY:
				continue
			var attr := ""
			var cur := 0
			var t := String(c.get("type", ""))
			match t:
				"morality_min", "morality_max":
					attr = "morality"
					cur = morality
				"pk_max":
					attr = "pk"
					cur = pk_value()
				"killing_intent_max":
					attr = "killing_intent"
					cur = killing_intent
				_:
					continue
			if out.has(attr):
				continue
			var th := CharData.to_int(c.get("value", 0))
			var margin := maxi(int(WARN_MIN_MARGIN[attr]), ceili(absi(th) * 0.1))
			var warn := false
			if t == "morality_min":
				warn = cur < th + margin
			elif t == "morality_max":
				warn = cur > th - margin
			else:
				warn = cur > 0 and cur > th - margin
			if warn:
				out.append(attr)
	return out

func _enemy_names(tables: Dictionary) -> Array:
	var out: Array = []
	for sid in sect_enemies:
		out.append(CharData.sect_name(tables, String(sid)))
	return out

func _jail_sheet(tables: Dictionary) -> Variant:
	if jail.is_empty():
		return null
	var room_id := String(jail.get("room", ""))
	return { "sect_name": CharData.sect_name(tables, String(jail.get("sect", ""))),
		"room_name": CharData.room_name(tables, room_id), "left_s": jail_left_s(),
		"scope": String(jail.get("scope", "SECT")), "reason": String(jail.get("reason", "")) }

## [ { id, name, glyph, color, level, left_s } ]；left_s = 到最後一次發作的上線秒
func _conditions_sheet(tables: Dictionary) -> Array:
	var out: Array = []
	var keys: Array = conditions.keys()
	keys.sort()
	for k in keys:
		var e: Dictionary = conditions[k]
		var row := CharData.row(tables, "status_effects", k)
		var tick := maxf(1.0, CharData.to_float(row.get("persist_tick_real_s", 120), 120.0))
		var left := maxf(0.0, CharData.to_float(e.get("next_online_s", 0.0)) - online_s) \
			+ maxf(0.0, float(int(e.get("ticks_left", 0)) - 1)) * tick
		out.append({ "id": k, "name": String(row.get("name", k)), "glyph": String(row.get("glyph", "")),
			"color": String(row.get("color", "")), "level": int(e.get("level", 0)), "left_s": left })
	return out

static func _sorted_keys(d: Variant) -> Array:
	var keys: Array = _dict(d).keys()
	keys.sort()
	return keys

## STORY_PLAN §4.14 角色表 quests 列：{ id, name, chapter, stage, stage_title, log, objectives: [{ text, have, need, done }],
## hint_room, escort }。escort = 護送中的 NPC 名字（"" = 沒有；escort_npc 是 id）。
## 另外保留 M1 的 giver_name、text、steps（= objectives）給舊介面。
func _quest_sheet(tables: Dictionary) -> Array:
	var out: Array = []
	QuestState.ensure(quests)
	var active := _dict(quests.get("active", {}))
	for qid in _sorted_keys(active):
		var q := CharData.row(tables, "quests", qid)
		if not q.is_empty() and not q.has("stages"):
			q = QuestDef.normalize(q)
		var st := _dict(active[qid])
		var stage_id := String(st.get("stage", ""))
		var stage := QuestDef.stage(q, stage_id)
		var objs: Array = []
		for p in QuestState.objective_progress(q, st, self, tables):
			objs.append({ "text": String(p["text"]), "have": int(p["have"]), "need": int(p["need"]), "done": bool(p["done"]) })
		var esc := String(st.get("escort", ""))
		out.append({
			"id": qid, "name": String(q.get("name", qid)), "chapter": String(q.get("chapter", "")),
			"stage": stage_id, "stage_title": String(stage.get("title", "")), "log": String(stage.get("log", "")),
			"objectives": objs, "hint_room": String(stage.get("hint_room", "")),
			"escort": CharData.npc_name(tables, esc) if esc != "" else "", "escort_npc": esc,
			"giver_name": CharData.npc_name(tables, String(q.get("giver", ""))),
			"text": String(q.get("text", "")),
			"steps": objs.duplicate(true),
		})
	return out

## [{ id, name, chapter, outcome_label, n }]（依 id 排序；只列完成過的，失敗次數不算）
func _quests_done_sheet(tables: Dictionary) -> Array:
	var out: Array = []
	var done := _dict(quests.get("done", {}))
	for qid in _sorted_keys(done):
		var d := QuestState.migrate_done(done[qid])
		if int(d["n"]) <= 0:
			continue
		var q := CharData.row(tables, "quests", qid)
		var oc: Variant = q.get("outcomes", {})
		var label := ""
		if oc is Dictionary and oc.get(String(d["outcome"])) is Dictionary:
			label = String(oc[String(d["outcome"])].get("label", ""))
		out.append({ "id": qid, "name": String(q.get("name", qid)), "chapter": String(q.get("chapter", "")),
			"outcome_label": label, "n": int(d["n"]) })
	return out

## { qid: 剩餘世界秒 }（只列還在冷卻中的；now_s < 0 時不知道現在幾點 → 空）
func _quest_cd_sheet(now_s: float) -> Dictionary:
	var out := {}
	if now_s < 0.0:
		return out
	var cd := _dict(quests.get("cd", {}))
	for qid in _sorted_keys(cd):
		var left := CharData.to_float(cd[qid]) - now_s
		if left > 0.0:
			out[qid] = left
	return out
