class_name GameHost
extends RefCounted
## 遊戲主機（M1_PLAN 3.5.2）：持有所有主機系統，註冊 intent，推送角色表與房間視圖。
## 只在主機上存在（WorldServer.start() 建立）；離線模式走同一條路徑（G2）。

const NEEDS_CHAR := 1
const IDLE := 2
const SHEET_MIN_INTERVAL_S := 0.25
const MINUTE_S := 60.0
const MAX_ACTIVE_QUESTS := 20
const STAT_NAMES := { "jing": "精", "qi": "氣", "shen": "神", "neili": "內力", "food": "飽食", "water": "飲水" }
## WORLD_2001 §8.1：刪掉的房間 -> 舊存檔改放的房間（目標不存在時改回記錄點）
const ROOM_FALLBACK := { "dlw_cave": "dlw_forest" }

var ws: Node
var index: WorldIndex
var char_store: CharacterStore
var regions: RegionSystem
var npcs: NpcSystem
var battles: BattleSystem
var quests: QuestSystem
var life: LifeSystem
var corpses: CorpseSystem
var scout: ScoutSystem     # 查看偵察（M3 小範圍【設計提案・非原作】）
var _minute_acc := 0.0
var _salt := 0

# ---------- M2（M2_PLAN 4.6.1） ----------
## 其他 WP 的新系統與 intent 檔以路徑 load()（H4 容錯接線）：檔案不存在或載入失敗時該系統為 null，呼叫點一律先判斷
const M2_SYSTEMS := { "party": "res://server/party_system.gd", "pk": "res://server/pk_system.gd",
	"social": "res://server/social_system.gd", "mail": "res://server/mail_system.gd" }
const M2_INTENTS := ["res://server/intents/intents_party.gd", "res://server/intents/intents_pk.gd",
	"res://server/intents/intents_social.gd", "res://server/intents/intents_host.gd"]
var party = null       # PartySystem 或 null（H4）
var pk = null          # PkSystem
var social = null      # SocialSystem
var mail = null        # MailSystem
var admin: AdminSystem
var m2_errors: PackedStringArray = []   # 載入失敗的 M2 檔案（測試與除錯用）

# ---------- M3a（M3A_PLAN 6.1、K3） ----------
const M3A_SYSTEMS := { "sects": "res://server/sect_system.gd", "conditions": "res://server/condition_system.gd" }
const M3A_INTENTS := ["res://server/intents/intents_sect.gd"]
const DEBUG_INTENTS := "res://server/intents/intents_debug.gd"
var sects = null        # SectSystem 或 null（K3）
var conditions = null   # ConditionSystem 或 null
## 主機以 --debug-intents 啟動（WorldServer.debug_intents）：才註冊 debug_set（§6.11）
var debug_enabled := false

# ---------- 故事包（STORY_PLAN S2、§8.1） ----------
## WP-AMBIENT 的系統：以路徑 load()，檔案不存在或載入失敗時為 null（S2）；呼叫點一律 m2_call 或先判斷
const STORY_SYSTEMS := { "rumor": "res://server/rumor_system.gd", "wander": "res://server/wander_system.gd",
	"ambient": "res://server/ambient_system.gd" }
const STORY_INTENTS := ["res://server/intents/intents_story.gd", "res://server/intents/intents_ambient.gd"]
var rumor = null        # RumorSystem 或 null
var wander = null       # WanderSystem 或 null
var ambient = null      # AmbientSystem 或 null
var _last_shichen := -1  # 換時辰偵測（quests.on_clock、wander.on_clock）

# ---------- M3b（M3B_PLAN L3、§9.3 Day-0） ----------
## WP-ECON（錢莊、鏢局）與 WP-ORG（組織）的系統與 intent 檔：以路徑 load()，失敗時為 null，呼叫點一律 m2_call 或先判斷
const M3B_SYSTEMS := { "bank": "res://server/bank_system.gd", "escort": "res://server/escort_system.gd",
	"orgs": "res://server/org_system.gd" }
const M3B_INTENTS := ["res://server/intents/intents_econ.gd", "res://server/intents/intents_org.gd"]
var bank = null         # BankSystem 或 null
var escort = null       # EscortSystem 或 null
var orgs = null         # OrgSystem 或 null
## 天地會等會籍旗標（OrgSystem 為 null 時角色表 societies 的退路；OrgSystem.SOCIETY_FLAGS 同值）
const DEFAULT_SOCIETY_FLAGS := { "tdh_member": "天地會" }

# ---------- M3c（M3C_PLAN N4、§11.3 Day-0） ----------
## WP-NPCPK（攻擊 NPC）與 WP-LOOT（掉落、秘笈、神兵）的系統與 intent 檔：以路徑 load()，失敗時為 null，呼叫點一律 m2_call
const M3C_SYSTEMS := { "npcpk": "res://server/npc_attack_system.gd", "loot": "res://server/loot_system.gd" }
const M3C_INTENTS := ["res://server/intents/intents_npcpk.gd", "res://server/intents/intents_loot.gd"]
var npcpk = null        # NpcAttackSystem 或 null
var loot = null         # LootSystem 或 null

# ---------- M3d（M3D_PLAN §9.2；WP-LAW Day-0） ----------
## 五個 WP 的系統與 intent 檔：以路徑 load()（ResourceLoader.exists 才載入），失敗時為 null；呼叫點一律 m2_call
const M3D_SYSTEMS := { "law": "res://server/law_system.gd", "combo": "res://server/combo_system.gd",
	"arts": "res://server/arts_system.gd", "jiebiao": "res://server/jiebiao_system.gd",
	"tourney": "res://server/tourney_system.gd", "errands": "res://server/errands_system.gd" }
const M3D_INTENTS := ["res://server/intents/intents_law.gd", "res://server/intents/intents_combo.gd",
	"res://server/intents/intents_arts.gd", "res://server/intents/intents_events.gd"]
var law = null          # LawSystem 或 null（WP-LAW）
var combo = null        # ComboSystem 或 null（WP-COMBAT）
var arts = null         # ArtsSystem 或 null（WP-ARTS）
var jiebiao = null      # JiebiaoSystem 或 null（WP-EVENTS）
var tourney = null      # TourneySystem 或 null（WP-EVENTS）
var errands = null      # ErrandsSystem 或 null（WP-ERRANDS）

## 生效資料視圖與規則一律即時讀 GameData（測試會以 GameData.activate 切換 rule_profile）
var tables: Dictionary:
	get:
		return GameData.tables
var rules: Dictionary:
	get:
		return GameData.rules
var options: Dictionary:
	get:
		return ws.options
var rng: RandomNumberGenerator:
	get:
		return ws.rng

func _init(p_ws: Node) -> void:
	ws = p_ws
	index = WorldIndex.new(GameData.tables)
	char_store = CharacterStore.new(self)
	regions = RegionSystem.new(self)
	npcs = NpcSystem.new(self)
	battles = BattleSystem.new(self)
	quests = QuestSystem.new(self)
	life = LifeSystem.new(self)
	corpses = CorpseSystem.new(self)
	scout = ScoutSystem.new(self)
	var secret := str(ws.world.get("world_secret", ws.world_id))
	_salt = secret.hash() & 0xFFFFFFFF
	ws.world["clock_last_night"] = bool(clock()["night"])   # 開服時同步，不廣播
	_migrate_corpses()
	IntentsChar.register(self)
	IntentsMove.register(self)
	IntentsNpc.register(self)
	IntentsSelf.register(self)
	IntentsItem.register(self)
	IntentsQuest.register(self)
	IntentsBattle.register(self)
	IntentsScout.register(self)
	admin = AdminSystem.new(self)
	_load_m2_systems()
	_register_m2_intents()
	debug_enabled = ws.get("debug_intents") == true
	_load_systems(M3A_SYSTEMS)
	var m3a_intents: Array = M3A_INTENTS.duplicate()
	if debug_enabled:
		m3a_intents.append(DEBUG_INTENTS)
	_register_intent_files(m3a_intents)
	if not (ws.world.get(QuestSystem.FIRSTS_KEY) is Dictionary):
		ws.world[QuestSystem.FIRSTS_KEY] = {}
	_load_systems(STORY_SYSTEMS)
	_register_intent_files(STORY_INTENTS)
	_load_systems(M3B_SYSTEMS)
	_register_intent_files(M3B_INTENTS)
	_load_systems(M3C_SYSTEMS)
	_register_intent_files(M3C_INTENTS)
	_load_m3d()   # M3d WP-LAW
	_load_rogue()   # ROGUE WP-RUN
	_last_shichen = int(clock()["shichen_idx"])
	if sects != null:
		m2_call(sects, "init_assembly", [now_s()])   # 新世界／舊世界第一次：從下一次聚會算起

func _load_m2_systems() -> void:
	_load_systems(M2_SYSTEMS)

## 以路徑 load() 建立系統（H4／K3）：失敗時該欄位為 null，路徑記進 m2_errors
func _load_systems(table: Dictionary) -> void:
	for key in table:
		var path: String = table[key]
		var inst: Variant = null
		if ResourceLoader.exists(path):
			var script := load(path) as GDScript
			if script != null and script.can_instantiate():
				inst = script.new(self)
			else:
				m2_errors.append(path)
				push_warning("[GameHost] M2 system failed to load: " + path)
		set(key, inst)

func _register_m2_intents() -> void:
	_register_intent_files(M2_INTENTS)

func _register_intent_files(paths: Array) -> void:
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			m2_errors.append(path)
			push_warning("[GameHost] M2 intents failed to load: " + path)
			continue
		script.call("register", self)

## 呼叫可能為 null（或還沒有該方法）的 M2 系統；不能呼叫時回 fallback。
## 故事包（S2）：平行開發的系統參數個數可能比呼叫端少 → 多的參數截掉（例：on_moved(s) 收到 [s, from, to]）
func m2_call(sys: Variant, method: String, args: Array = [], fallback: Variant = null) -> Variant:
	if sys == null or not (sys as Object).has_method(method):
		return fallback
	var n := (sys as Object).get_method_argument_count(method)
	if n >= 0 and n < args.size():
		args = args.slice(0, n)
	return (sys as Object).callv(method, args)

# ---------- 註冊與固定步驟（3.5.3） ----------
## handler(s: Session, args: Dictionary) -> { ok, reason }；flags：NEEDS_CHAR、IDLE
func register(kind: String, handler: Callable, flags: int) -> void:
	ws.register_intent(kind, func(s: Session, args: Dictionary) -> Dictionary:
		return _run_intent(s, args, handler, flags, kind))

func _run_intent(s: Session, args: Dictionary, handler: Callable, flags: int, kind: String = "") -> Dictionary:
	if flags & NEEDS_CHAR:
		var r := require_char(s)
		if r != "":
			return fail(r)
	if flags & IDLE:
		var r2 := require_idle(s)
		if r2 != "":
			return fail(r2)
	# M3a 思過處（§6.6）：坐牢中只放行 SectSystem.JAIL_ALLOWED（需要角色的 intent 才檢查；選角、主機設定不受影響）
	if (flags & NEEDS_CHAR) and sects != null:
		var r3: String = sects.jail_gate(s, kind)
		if r3 != "":
			return fail(r3)
	var rg: String = rogue.gate(s, kind) if rogue != null else ""   # ROGUE WP-RUN
	if rg != "": return fail(rg)   # ROGUE WP-RUN
	var result: Variant = handler.call(s, args)
	if not (result is Dictionary):
		push_error("[GameHost] handler returned non-dictionary")
		return fail("bad_cmd")
	if result.get("ok", false):
		if not result.has("reason"):
			result["reason"] = ""
		if s.character != null:
			s.sheet_dirty = true
		flush_session(s, true)   # 成功的 intent 之後，下一個 flush 前一定送出最新角色表
	return result

static func ok(extra: Dictionary = {}) -> Dictionary:
	var r := { "ok": true, "reason": "" }
	r.merge(extra, true)
	return r

const COOLDOWN_MEDITATE := "meditate"
const COOLDOWN_LIFE := "life"
const COOLDOWN_SCOUT := "scout"   # 查看偵察（ScoutSystem.COOLDOWN_KEY）

static func fail(reason: String) -> Dictionary:
	return { "ok": false, "reason": reason }

func require_char(s: Session) -> String:
	return "" if s.character != null else "no_character"

func require_idle(s: Session) -> String:
	return "in_battle" if s.battle_id != 0 else ""

func npc_row(npc_id: String) -> Dictionary:
	return tables.get("npcs", {}).get(npc_id, {})

## STORY_PLAN §4.6、§4.13：appear 不成立的 NPC 對這位玩家不在；正在護送的 NPC 跟著玩家走
func npc_here(s: Session, npc_id: String) -> String:
	if s.character == null or npc_row(npc_id).is_empty():
		return "not_here"
	if quests != null and quests.is_escorting(s.character, npc_id):
		return ""
	if index.room_of_npc(npc_id) != s.room_id():
		return "not_here"
	# M3c（§5.3）：被殺後重生前的 NPC 不在
	if m2_call(npcpk, "npc_down", [npc_id], false) == true:
		return "not_here"
	if quests != null and not quests.npc_visible(s.character, npc_id):
		return "not_here"
	# 審查修正：遊蕩惡人夜裡不在定點、被擊退後重生前也不在（與 RegionSystem.view 同一個判斷；WanderSystem 為 null 時略過）
	if m2_call(wander, "npc_shown", [npc_id, s.room_id()], true) == false:
		return "not_here"
	return ""

## 3.5.3 第 4 步：not_here → no_service → closed_night
func npc_check(s: Session, npc_id: String, service: String) -> String:
	var r := npc_here(s, npc_id)
	if r != "":
		return r
	var row := npc_row(npc_id)
	if not (service in row.get("services", [])):
		return "no_service"
	if npc_closed(row):
		return "closed_night"
	return ""

func npc_closed(row: Dictionary) -> bool:
	return bool(row.get("night_closed", false)) and bool(clock()["night"])

# ---------- 時間 ----------
func now_s() -> float:
	return ws.world_time()

func day_s() -> float:
	return float(options.get("game_day_real_s", WorldClock.DEFAULT_DAY_S))

func clock() -> Dictionary:
	return WorldClock.clock(now_s(), day_s())

## H5：真實秒數換成世界時間的長度（time_scale 加速時，60 秒的邀請不會在 1.2 秒內過期）
func world_span(real_s: float) -> float:
	var scale := float(ws.get("time_scale")) if ws != null and ws.get("time_scale") != null else 1.0
	return real_s * scale

## 世界時間的長度換回真實秒數（送給 UI 的 left_s、ttl）
func real_span(world_s: float) -> float:
	var scale := float(ws.get("time_scale")) if ws != null and ws.get("time_scale") != null else 1.0
	return world_s / maxf(scale, 0.001)

func tick(dt: float) -> void:
	battles.tick(dt)
	scout.tick()
	if party != null:
		m2_call(party, "tick", [now_s()])
	if pk != null:
		m2_call(pk, "tick", [now_s()])
	# K4：上線秒數不隨 --time-scale 縮放（坐牢、禁武、中毒發作、PK值遞減都以它計）
	var online_dt := real_span(dt)
	for s in sessions():
		if s.character == null:
			continue
		var ch = s.character
		ch.online_s += online_dt
		ch.party_id = party_id_of(s)
		var before: Dictionary = ch.vitals.duplicate()
		var notes: Array = Survival.tick(ch, dt, s.battle_id != 0, tables, options)
		for key in notes:
			tell(s, Protocol.CH_SYSTEM, str(key), {})
		if ch.vitals != before:
			s.sheet_dirty = true
	if conditions != null:
		conditions.tick(dt)
	# 故事包（S2）：江湖傳聞、遊蕩惡人
	m2_call(rumor, "tick", [dt])
	m2_call(wander, "tick", [dt])
	m2_call(ambient, "tick", [dt])
	m3d_tick(dt)   # M3d WP-LAW
	check_clock()
	_minute_acc += dt
	if _minute_acc >= MINUTE_S:
		_minute_acc -= MINUTE_S
		_minute_jobs()
	_check_day_night()
	_flush_dirty()

func _minute_jobs() -> void:
	var now := now_s()
	var c := clock()
	for s in sessions():
		if s.character == null:
			continue
		var ch = s.character
		for sp in ch.inventory.spoil(now, day_s(), tables):
			tell(s, Protocol.CH_SYSTEM, Protocol.E_ITEM_SPOILED,
				{ "item_name": item_name(str(sp.get("id", ""))), "n": int(sp.get("n", 1)) })
			s.sheet_dirty = true
		var attr: String = Survival.birthday_check(ch, int(c["year"]), int(c["month"]), rng)
		if attr != "":
			tell(s, Protocol.CH_SYSTEM, Protocol.E_BIRTHDAY, { "attr_name": attr_name(attr) })
			s.sheet_dirty = true
	corpses.expire(now)
	# M3b：托鏢到站／退回、組織連署過期；門派聚會（換時辰時也檢查，這裡補 debug 快轉跨過辰時的情況）
	m2_call(escort, "tick", [now])
	m2_call(orgs, "tick", [now])
	if sects != null:
		m2_call(sects, "assembly_tick", [now])
	# M3c（§5.3）：被殺的 NPC 到時重生
	m2_call(npcpk, "tick", [now])

## 換時辰（STORY_PLAN §4.8）：每位在線角色 quests.on_clock（WAIT、STATE、appear），再通知 WanderSystem／AmbientSystem
func check_clock() -> void:
	var idx := int(clock()["shichen_idx"])
	if idx == _last_shichen:
		return
	_last_shichen = idx
	for s in sessions():
		if s.character != null:
			quests.on_clock(s)
	m2_call(wander, "on_clock", [idx])
	m2_call(ambient, "on_clock", [idx])
	if sects != null:
		m2_call(sects, "assembly_tick", [now_s()])   # M3B_PLAN §5.1.1：辰時聚會

func _check_day_night() -> void:
	var c := clock()
	var night := bool(c["night"])
	if night == bool(ws.world.get("clock_last_night", false)):
		return
	ws.world["clock_last_night"] = night
	ws.broadcast_event(Protocol.CH_SYSTEM, Protocol.E_NIGHT_FALLS if night else Protocol.E_DAY_BREAKS,
		{ "clock": c["text"] })
	for s in sessions():
		s.view_dirty = true
		s.sheet_dirty = true

# ---------- 推送 ----------
func push_sheet(s: Session) -> void:
	s.sheet_dirty = false
	if s.character == null:
		return
	quests.on_sheet(s)   # STATE 目標（節流：同一角色每秒最多一次）
	var sheet: Dictionary = s.character.to_sheet(tables, options, rules, now_s())
	var c := clock()
	sheet["clock"] = { "text": c["text"], "night": c["night"], "day": c["day"] }
	sheet["in_battle"] = s.battle_id != 0
	sheet["battle_id"] = s.battle_id
	sheet["cooldowns"] = cooldowns(s)
	_sheet_m2(s, sheet)
	s.last_sheet_s = now_s()
	ClientState.deliver_sheet(s.peer_id, sheet)

## 隊伍 id（PartySystem 為 null 時 ""）；to_combatant 的 party_id 由這裡每 tick 填進角色（M3A_PLAN 3.11）
func party_id_of(s: Session) -> String:
	if party == null or s == null or s.character == null or not (party as Object).has_method("party_id_of"):
		return ""
	return str(party.party_id_of(str(s.character.id)))

## M2_PLAN 4.5.1：角色表新增欄位；系統為 null（H4）時給空值。pk／align／prefs 由 Character.to_sheet（WP-PK）產生，
## 還沒有時這裡補上同形狀的預設值，UI 不必判斷有沒有。
func _sheet_m2(s: Session, sheet: Dictionary) -> void:
	var ch = s.character
	if not sheet.has("pk"):
		sheet["pk"] = int(ch.pk) if "pk" in ch else 0
	if not sheet.has("align"):
		sheet["align"] = align_of(int(ch.morality) if "morality" in ch else 0)
	if not sheet.has("prefs"):
		sheet["prefs"] = { "accept_challenge": true, "accept_party": true }
	var pt: Variant = m2_call(party, "sheet_for", [s], {})
	sheet["party"] = pt if pt is Dictionary else {}
	var inv: Variant = m2_call(party, "pending_for", [s], {})
	var chal: Variant = m2_call(pk, "pending_for", [s], [])
	sheet["pending"] = { "party_invite": inv if inv is Dictionary else {}, "challenges": chal if chal is Array else [] }
	sheet["mail_unread"] = int(m2_call(mail, "unread_count", [ch], 0))
	var mine: Variant = m2_call(corpses, "mine", [ch], [])
	sheet["my_corpses"] = mine if mine is Array else []
	sheet["is_admin"] = is_admin(s)
	_sheet_m3b(s, sheet)
	m3d_sheet(s, sheet)   # M3d WP-LAW

## M3B_PLAN §6 角色表：org（OrgSystem）、societies（會籍旗標）；系統為 null 時給同形狀的預設值
func _sheet_m3b(s: Session, sheet: Dictionary) -> void:
	var ch = s.character
	var f: Variant = m2_call(orgs, "sheet_fields", [s], null)
	if f is Dictionary:
		sheet["org"] = f.get("org", null)
		sheet["societies"] = f.get("societies", []) if f.get("societies") is Array else []
	else:
		sheet["org"] = null
		var soc: Array = []
		for fl in DEFAULT_SOCIETY_FLAGS:
			if bool(ch.flags.get(fl, false)):
				soc.append(str(DEFAULT_SOCIETY_FLAGS[fl]))
		sheet["societies"] = soc

## 名字顏色的善惡分類（M2_PLAN 5.2：> 100 GOOD、< −100 EVIL；與 MoralityPk.align_of 相同門檻）。
## 只在 WP-PK 的欄位或 player_tags 不存在時當預設值用。
static func align_of(morality: int) -> String:
	if morality > 100:
		return "GOOD"
	if morality < -100:
		return "EVIL"
	return "NEUTRAL"

## 冷卻剩餘的「真實秒數」（世界時間 ÷ time_scale，送出當下計算）：{ "meditate": float, "life": float, "scout": float }；
## scout 只在目前房間能偵察時非 0（安全的房間查看沒有冷卻）；
## UI 收到時記下本機時刻自己倒數（按鈕灰掉並顯示「修煉（7 秒）」），不輪詢主機
func cooldowns(s: Session) -> Dictionary:
	return { COOLDOWN_MEDITATE: cooldown_left_s(s, COOLDOWN_MEDITATE), COOLDOWN_LIFE: cooldown_left_s(s, COOLDOWN_LIFE),
		COOLDOWN_SCOUT: cooldown_left_s(s, COOLDOWN_SCOUT) }

## 單一冷卻的剩餘真實秒數（0 = 可用）
func cooldown_left_s(s: Session, key: String) -> float:
	if s.character == null:
		return 0.0
	var left := 0.0
	match key:
		COOLDOWN_MEDITATE:
			var last := float(s.character.counters.get("last_meditate_s", -1.0))
			if last >= 0.0:
				left = maxf(0.0, last + Survival.MEDITATE_COOLDOWN_S - now_s())
		COOLDOWN_LIFE:
			left = maxf(0.0, float(s.character.counters.get(LifeSystem.CD_KEY, 0.0)) - now_s())
		COOLDOWN_SCOUT:
			return scout.cooldown_left_real(s) if scout != null else 0.0   # 已經是真實秒數
	var scale := float(ws.get("time_scale")) if ws.get("time_scale") != null else 1.0
	return left / maxf(scale, 0.001)

## 冷卻中的失敗（3.7 busy）：結果帶 cooldown 與 left_s（剩餘真實秒數，無條件進位、至少 1），
## 並在回 intent_result 之前先送最新角色表（含 cooldowns），讓按鈕立刻開始倒數
func fail_busy(s: Session, key: String) -> Dictionary:
	var r := fail("busy")
	r["cooldown"] = key
	r["left_s"] = maxi(1, ceili(cooldown_left_s(s, key) - 1e-6))
	if s.character != null:
		s.sheet_dirty = true
		flush_session(s, true)
	return r

func push_view(s: Session) -> void:
	s.view_dirty = false
	if s.character == null:
		return
	s.last_view_s = now_s()
	ClientState.deliver_region_view(s.peer_id, regions.view(s))

## force：忽略 0.25 秒節流（intent 成功後、戰鬥結束後）
func flush_session(s: Session, force := false) -> void:
	var now := now_s()
	if s.sheet_dirty and (force or now - s.last_sheet_s >= SHEET_MIN_INTERVAL_S):
		push_sheet(s)
	if s.view_dirty and (force or now - s.last_view_s >= SHEET_MIN_INTERVAL_S):
		push_view(s)

func _flush_dirty() -> void:
	for s in sessions():
		if s.sheet_dirty or s.view_dirty:
			flush_session(s)

func push_char_list(s: Session) -> void:
	ClientState.deliver_char_list(s.peer_id, char_list_for(s))   # M3c2 WP-CARRY：另附可選身分的角色（§5.7）

# ---------- 事件 ----------
## 本人收件：payload 一律補上 peer（3.8.1 註）
func tell(s: Session, ch: String, key: String, p: Dictionary, ui := false) -> void:
	if not p.has("peer"):
		p["peer"] = s.peer_id
	if s.character != null and _template_wants_address(key):
		for k in ADDRESS_TOKENS:
			if not p.has(k):
				p[k] = address_word(s.character, k)
	ws.queue_event(s.peer_id, ch, key, p, ui)

## 審查修正（敘事）：依玩家性別稱呼的佔位字（【設計提案】；原作沒有逐字對白）。
## {honorific} 兄台／姑娘、{shaoxia} 少俠／女俠、{shidi} 師弟／師妹、{gege} 大哥／姊姊
const ADDRESS_TOKENS := {
	"honorific": ["兄台", "姑娘"], "shaoxia": ["少俠", "女俠"], "shidi": ["師弟", "師妹"], "gege": ["大哥", "姊姊"],
}

static func address_word(character, token: String) -> String:
	var pair: Array = ADDRESS_TOKENS.get(token, ["", ""])
	return str(pair[1] if character != null and str(character.gender) == "F" else pair[0])

## 文字裡的 {honorific} 等換成對這位玩家的稱呼（任務對話等不經模板的文字）
static func fill_address(text: String, character) -> String:
	if not text.contains("{"):
		return text
	for k in ADDRESS_TOKENS:
		text = text.replace("{%s}" % k, address_word(character, k))
	return text

func _template_wants_address(key: String) -> bool:
	var row: Variant = tables.get("text_templates", {}).get(key, null)
	if not (row is Dictionary):
		return false
	for v in ["self", "target", "other"]:
		var t := str((row as Dictionary).get(v, ""))
		if t.contains("{") and (t.contains("{honorific}") or t.contains("{shaoxia}") or t.contains("{shidi}") or t.contains("{gege}")):
			return true
	return false

func item_gain_event(s: Session, item_id: String, n: int) -> void:
	tell(s, Protocol.CH_SYSTEM, Protocol.E_ITEM_GAIN, { "item_name": item_name(item_id), "n": n })
	if quests != null:
		quests.on_items(s)   # COLLECT（STORY_PLAN §4.8）

func item_lost_event(s: Session, item_id: String, n: int) -> void:
	tell(s, Protocol.CH_SYSTEM, Protocol.E_ITEM_LOST, { "item_name": item_name(item_id), "n": n })
	if quests != null:
		quests.on_items(s)

# ---------- 名稱查表 ----------
func item_name(item_id: String) -> String:
	return str(tables.get("items", {}).get(item_id, {}).get("name", item_id))

func room_name(room_id: String) -> String:
	return str(index.room(room_id).get("name", room_id))

func region_name(region_id: String) -> String:
	return str(tables.get("regions", {}).get(region_id, {}).get("name", region_id))

func npc_name(npc_id: String) -> String:
	return str(npc_row(npc_id).get("name", npc_id))

func attr_name(attr_id: String) -> String:
	return str(tables.get("attributes", {}).get(attr_id, {}).get("name", attr_id))

func skill_name(skill_id: String) -> String:
	return SkillBook.skill_name(skill_id, tables)

func monster_name(monster_id: String) -> String:
	return str(tables.get("monsters", {}).get(monster_id, {}).get("name", monster_id))

func quest_name(quest_id: String) -> String:
	return str(tables.get("quests", {}).get(quest_id, {}).get("name", quest_id))

func stat_name(stat: String) -> String:
	return STAT_NAMES.get(stat, stat)

## WORLD 直接加熟練度（任務 skill_prof）時的等級上限：生活技能看 life_skills.cap，其餘看實戰上限（4.4）
func skill_cap(ch, skill_id: String) -> int:
	var xp_cap: int = DerivedStats.art_level_cap(int(ch.combat_xp))
	match SkillBook.kind_of(skill_id, tables):
		"LIFE":
			return int(tables.get("life_skills", {}).get(skill_id, {}).get("cap", 100))
		"SECT":
			var cap := 100
			for sid in tables.get("sects", {}):
				if str(tables["sects"][sid].get("sect_skill", "")) == skill_id:
					cap = int(tables["sects"][sid].get("sect_skill_cap", 100))
			return mini(cap, xp_cap)
		"BASIC":
			return mini(xp_cap, int(tables.get("basic_skills", {}).get(skill_id, {}).get("max_level", 250)))
		_:
			return xp_cap

# ---------- 實例 id（3.1、3.10.2） ----------
## counter × 黃金比常數（奇數，mod 2^32 是雙射）再 XOR 世界鹽 → 8 hex，在世界內保證唯一
func new_id(prefix: String) -> String:
	var counter := int(ws.world.get("id_counter", 0)) + 1
	ws.world["id_counter"] = counter
	var v := ((counter * 0x9E3779B1) & 0xFFFFFFFF) ^ _salt
	return "%s%08x" % [prefix, v]

func make_item_uid() -> String:
	return new_id("it_")

func make_uid_callable() -> Callable:
	return Callable(self, "make_item_uid")

## 放進背包（WORLD 的物品入帳都走這裡）：回傳 Inventory.add 的結果
## lots：整疊連同每一批的取得時間一起放（屍體撿回、護照）；總數要等於 n，否則改用 born_s 當一批
func give_item(ch, item_id: String, n: int, born_s: float = -1.0, lots: Array = []) -> Dictionary:
	var d: Dictionary = ch.derived(tables, options)
	var cap := int(d.get("carry_max", 0))
	if not lots.is_empty() and Inventory._lots_sum(Inventory._clean_lots(lots, 0.0)) == n:
		return ch.inventory.add_lots(item_id, lots, tables, cap, make_uid_callable())
	return ch.inventory.add(item_id, n, tables, now_s() if born_s < 0.0 else born_s, cap, make_uid_callable())

# ---------- 角色進出 ----------
func sessions() -> Array:
	return ws.sessions.values()

func session_for_peer(peer_id: int) -> Session:
	return ws.sessions.get(peer_id)

func session_for_char(char_id: String) -> Session:
	for s in sessions():
		if s.character != null and s.character.id == char_id:
			return s
	return null

func save_char(ch) -> Error:
	if ws.get("ephemeral") == true: return OK   # ROGUE WP-RUN
	if ch == null:
		return ERR_INVALID_PARAMETER
	return char_store.save(ch)

func save_all() -> void:
	for s in sessions():
		if s.character != null:
			save_char(s.character)

## 讓 s 以角色 ch 進入世界（WORLD_2001 §8）：位置已不在生效的房間裡 → ROOM_FALLBACK → 記錄點（→ 出生城），
## 送 relocated；記錄點已不在生效的房間裡 → 清空，送 respawn_reset
func enter_character(s: Session, ch) -> void:
	s.character = ch
	s.pending_roll = {}
	ch.inventory.consolidate(tables)   # 舊存檔被 60 秒合併窗拆開的同物品堆疊 → 併回去
	var notes: Array = []
	var resp_room := str(ch.respawn.get("room", "")) if ch.respawn is Dictionary else ""
	if resp_room != "" and not index.has_room(resp_room):
		ch.respawn = { "region": "", "room": "" }
		notes.append([Protocol.E_RESPAWN_RESET, { "room_name": room_name(birth_room(ch)) }])
	var old_room := str(ch.location.get("room", ""))
	if not index.has_room(old_room):
		var room := relocation_room(ch, old_room)
		ch.location = { "region": index.region_of(room), "room": room }
		if old_room != "":
			notes.push_front([Protocol.E_RELOCATED, { "room_name": room_name(room) }])
	else:
		ch.location["region"] = index.region_of(old_room)   # 地區改了 id 歸屬時補正
	for n in notes:
		tell(s, Protocol.CH_SYSTEM, str(n[0]), n[1])
	regions.enter_world(s)
	s.sheet_dirty = true
	s.view_dirty = true
	m2_call(mail, "on_enter", [s])   # 有未讀信 → mail_waiting（M2_PLAN 4.6.1）
	# 故事包（§4.8）：任務狀態遷移與護送恢復；補送最近的江湖傳聞；遊蕩惡人
	quests.on_login(s)
	m2_call(rumor, "on_login", [s])
	m2_call(wander, "on_login", [s])
	# M3b：組織快取校正與待處理邀請、托鏢到站通知、錯過聚會的待升補升
	m2_call(orgs, "on_login", [s])
	m2_call(escort, "on_login", [s])
	if sects != null:
		m2_call(sects, "on_login", [s])
	m3d_login(s)   # M3d WP-LAW

## 房間已不存在時要搬去哪裡：ROOM_FALLBACK → 記錄點 → 出生城
func relocation_room(ch, old_room: String) -> String:
	var fb := str(ROOM_FALLBACK.get(old_room, ""))
	if fb != "" and index.has_room(fb):
		return fb
	return respawn_room(ch)

## 開世界時把 ROOM_FALLBACK 房間裡的屍體搬到目標房間（§8.3）
func _migrate_corpses() -> void:
	var list: Variant = ws.world.get("corpses")
	if not (list is Array):
		return
	for c in list:
		if c is Dictionary:
			var fb := str(ROOM_FALLBACK.get(str(c.get("room", "")), ""))
			if fb != "" and index.has_room(fb):
				c["room"] = fb

## 存檔並離開房間（換角、斷線、關服）
## from_room：離開時要通知的房間；空字串＝角色目前的位置
func leave_character(s: Session, announce := true, from_room := "") -> void:
	m2_call(rogue, "on_leave", [s])   # ROGUE WP-RUN
	if s.character == null:
		return
	# M2_PLAN 4.6.1：離線或換角即離隊；他發出與收到的邀請／叫戰一併刪除
	m2_call(party, "on_leave", [s])
	m2_call(pk, "on_leave", [s])
	if quests != null:
		quests.drop_dialogue(s)   # 對話游標不存（§4.7）
	m2_call(wander, "on_leave", [s])   # 惡人警告倒數取消
	m3d_logout(s)   # M3d WP-LAW
	if scout != null:
		scout.invalidate(s, ScoutSystem.WHY_LOGOUT)
	save_char(s.character)
	if announce:
		regions.leave_world(s, from_room)
	s.character = null

func birth_room(ch) -> String:
	var r := str(tables.get("regions", {}).get(str(ch.birth_city), {}).get("birth_room", ""))
	if index.has_room(r):
		return r
	for rid in tables.get("regions", {}):
		var br := str(tables["regions"][rid].get("birth_room", ""))
		if index.has_room(br):
			return br
	return str(index.rooms.keys()[0]) if not index.rooms.is_empty() else ""

func respawn_room(ch) -> String:
	var r := str(ch.respawn.get("room", ""))
	return r if index.has_room(r) else birth_room(ch)

func on_session_removed(s: Session) -> void:
	# 先記住斷線時的房間：最後一個真人斷線時 detach_for 會當場結算，死亡會把角色位置改到重生點；
	# 「…離開了」要送給他實際所在的戰場房間，不是重生點（M2 第三輪審查）
	var room := s.room_id() if s.character != null else ""
	if s.battle_id != 0:
		battles.detach_for(s)   # 斷線不中止戰鬥：自動防守打到分出勝負（照樣受死亡懲罰）
	leave_character(s, true, room)   # 內含 party.on_leave／pk.on_leave（M2_PLAN 4.6.1）

## 換角（連線還在）：先送一份護照（M2_PLAN 4.6.8），再存檔並離開房間
func switch_out(s: Session) -> void:
	if s.character == null:
		return
	send_passport(s, s.character)
	leave_character(s, true)

## 主機關閉（M2_PLAN 2.1「主機離線＝世界凍結」）：戰鬥 ABORTED、存所有在線角色；
## 隊伍、待決邀請／叫戰不存檔（4.8），隨 GameHost 一起消失
func shutdown() -> void:
	for rs in sessions(): m2_call(rogue, "on_leave", [rs])   # ROGUE WP-RUN
	battles.abort_all()
	save_all()
	for s in sessions():
		s.character = null

# ---------- M2 輔助（M2_PLAN 4.6.1） ----------
## H6：玩家輸入的文字先清理
func clean_text(text: String, max_len: int) -> String:
	return Protocol.clean_text(text, max_len)

func is_admin(s: Session) -> bool:
	return s != null and s.is_admin

## 在線且選著此名角色（大小寫不敏感）的 session，否則 null
func session_for_char_name(char_name: String) -> Session:
	var k := CharacterStore.name_key(char_name)
	if k == "":
		return null
	for s in sessions():
		if s.character != null and CharacterStore.name_key(str(s.character.name)) == k:
			return s
	return null

## world.char_names 查詢：{ identity, char_id } 或 {}（不管在不在線）
func char_ref_by_name(char_name: String) -> Dictionary:
	var k := CharacterStore.name_key(char_name)
	if k == "" or char_store == null:
		return {}
	var e: Variant = char_store.names().get(k)
	if not (e is Dictionary) or str(e.get("char_id", "")) == "":
		return {}
	return { "identity": str(e.get("identity", "")), "char_id": str(e.get("char_id", "")) }

## 角色 id → 名字：在線找不到時以 char_names 反查；都沒有回 ""
func pvp_char_name(char_id: String) -> String:
	if char_id == "":
		return ""
	var s := session_for_char(char_id)
	if s != null:
		return str(s.character.name)
	if battles != null:
		for bid in battles.active:
			var chars: Variant = battles.active[bid].get("chars", {})
			if chars is Dictionary:
				for p in chars:
					var c = chars[p]
					if c != null and str(c.id) == char_id:
						return str(c.name)
	var names: Dictionary = char_store.names() if char_store != null else {}
	for k in names:
		if names[k] is Dictionary and str(names[k].get("char_id", "")) == char_id:
			# 索引的鍵是小寫；有角色檔就讀回原本的大小寫
			var ident := str(names[k].get("identity", ""))
			var ch = char_store.load_char(ident, char_id)
			return str(ch.name) if ch != null else str(k)
	return ""

# ---------- 角色護照（M2_PLAN 4.6.8） ----------
func make_passport(ch) -> Dictionary:
	var world_id := str(ws.world.get("world_id", ws.world_id))
	return Passport.make(str(ws.world.get("world_secret", "")), world_id, ch.to_dict(), now_s())

## 送 passport（ui）給本人；客戶端 ClientState 存到 <資料根目錄>/passports/
func send_passport(s: Session, ch) -> void:
	if ws.get("ephemeral") == true: return   # ROGUE WP-RUN
	if s == null or ch == null:
		return
	tell(s, Protocol.CH_SYSTEM, Protocol.E_PASSPORT, make_passport(ch), true)

## WorldServer 自動存檔（每 autosave_interval_s）之後：每個在線且有角色的 session 一份護照
func on_autosave() -> void:
	if ws.get("ephemeral") == true: return   # ROGUE WP-RUN
	for s in sessions():
		if s.character != null:
			send_passport(s, s.character)

# ==== M3c2 WP-CARRY ====（M3C2_PLAN §5.3、§5.7）
const STEAM_IDENTITY_RE := "^steam_[1-9][0-9]{0,19}$"
const META_BASE_IDENTITY := "m3c2_base_identity"   # session 原本的（連線時的）身分；換成 Steam 身分後讓玩家換回來
## 測試用：非空時取代 SteamManager 的目前 SteamID（"none" ＝ Steam 沒開）
var test_steam_id := ""

## 外來角色可以匯入嗎：單機一律可以；開房（ENet／Steam）看 allow_foreign_characters（R9）
func foreign_allowed() -> bool:
	return NetworkManager.mode == NetworkManager.Mode.OFFLINE or options.get("allow_foreign_characters", false) == true

## 目前登入的 Steam 帳號的 SteamID 字串；Steam 沒開／沒登入回 ""
func current_steam_id() -> String:
	if test_steam_id != "":
		return "" if test_steam_id == "none" else test_steam_id
	var sm: Node = ws.get_node_or_null("/root/SteamManager") if ws != null and ws.is_inside_tree() else null
	if sm == null or not bool(sm.get("available")):
		return ""
	var sid := str(sm.call("steam_id_string")) if sm.has_method("steam_id_string") else ""
	return "" if sid == "" or sid == "0" else sid

## session 連線時的身分（換過 Steam 身分後仍記得原本的）
func base_identity(s: Session) -> String:
	return str(s.get_meta(META_BASE_IDENTITY, s.identity)) if s != null else ""

## §5.7：單機（OFFLINE）且本機 session 時，可以改用的身分：[{ identity, needs_confirm, kind: "steam"|"local" }]
## Steam 開著 → 只有 steam_<目前 SteamID>（有那個資料夾才列）；Steam 沒開 → 所有 steam_*（要確認）；
## 另外一律提供原本的本機身分（已換成別的身分時）。不含目前的身分。
func alt_identities(s: Session) -> Array:
	var out: Array = []
	if s == null or not s.is_local or NetworkManager.mode != NetworkManager.Mode.OFFLINE:
		return out
	var re := RegEx.create_from_string(STEAM_IDENTITY_RE)
	var folders: PackedStringArray = SaveManager.list_identities(ws.world_id)
	var sid := current_steam_id()
	if sid != "":
		var mine := "steam_" + sid
		if mine != s.identity and mine in folders and re.search(mine) != null:
			out.append({ "identity": mine, "needs_confirm": false, "kind": "steam" })
	else:
		for f in folders:
			if f != s.identity and re.search(f) != null:
				out.append({ "identity": f, "needs_confirm": true, "kind": "steam" })
	var base := base_identity(s)
	if base != "" and base != s.identity:
		out.append({ "identity": base, "needs_confirm": false, "kind": "local" })
	return out

## 角色清單（3.9.5）：本身分的角色照舊；再附上每個可選身分的角色（摘要多 identity、alt、needs_confirm）
func char_list_for(s: Session) -> Array:
	var out: Array = []
	if s == null or char_store == null:
		return out
	for row in char_store.summaries(s.identity):
		row["identity"] = s.identity
		row["alt"] = false
		row["needs_confirm"] = false
		out.append(row)
	for alt in alt_identities(s):
		for row in char_store.summaries(str(alt["identity"])):
			row["identity"] = str(alt["identity"])
			row["alt"] = true
			row["needs_confirm"] = bool(alt["needs_confirm"])
			row["identity_kind"] = str(alt["kind"])
			out.append(row)
	return out

## char_select { identity }：換成可選身分（必須在 alt_identities 裡，否則 alt_identity_denied）；回傳原因碼或 ""
func switch_identity(s: Session, identity: String) -> String:
	if identity == "" or identity == s.identity:
		return ""
	var allowed := false
	for alt in alt_identities(s):
		if str(alt["identity"]) == identity:
			allowed = true
	if not allowed:
		return Protocol.R_ALT_IDENTITY_DENIED
	if not s.has_meta(META_BASE_IDENTITY):
		s.set_meta(META_BASE_IDENTITY, s.identity)
	if s.character != null:
		switch_out(s)   # 先用舊身分存檔、離開房間
	s.identity = identity
	var known: Dictionary = ws.world.get_or_add("known_identities", {})
	var entry: Dictionary = known.get(identity, { "banned": false })
	entry["last_name"] = s.display_name
	known[identity] = entry
	return ""

## 子系統都持有 host（RefCounted 互相引用），不切斷就永遠不會被回收：
## 關閉遊戲時出現「9 resources still in use」，同一次執行反覆開關世界也會累積。
## 由 WorldServer.stop() 在最後一次存檔之後呼叫；之後這個 GameHost 不能再用。
func dispose() -> void:
	for sys in [char_store, regions, npcs, battles, quests, life, corpses, scout, party, pk, social, mail, admin, sects, conditions,
			rumor, wander, ambient, bank, escort, orgs, npcpk, loot, law, combo, arts, jiebiao, tourney, errands]:
		if sys != null and "host" in sys:
			sys.host = null
	law = null
	combo = null
	arts = null
	jiebiao = null
	tourney = null
	errands = null
	rumor = null
	wander = null
	ambient = null
	bank = null
	escort = null
	orgs = null
	npcpk = null
	loot = null
	sects = null
	conditions = null
	party = null
	pk = null
	social = null
	mail = null
	admin = null
	char_store = null
	regions = null
	npcs = null
	battles = null
	quests = null
	life = null
	corpses = null
	scout = null
	index = null
	ws = null

# ==== M3d WP-LAW ====（M3D_PLAN §9.2：系統載入、intent 註冊、分派函式；其他 WP 不改這個檔）
## 載入六個 M3d 系統與四個 intent 檔（檔案不存在 → 該系統 null、intent 不註冊；5 個 WP 可各自先過測試）
func _load_m3d() -> void:
	_load_systems(M3D_SYSTEMS)
	_register_intent_files(M3D_INTENTS)
	_m3d_apply_rules()

func _m3d_systems() -> Array:
	return [law, combo, arts, jiebiao, tourney, errands]

## 規則 pk_decay（M3D_PLAN §2.6）→ 在線角色的執行期欄位 pk_decay_on（不存檔）
func _m3d_apply_rules() -> void:
	var on := bool(rules.get("pk_decay", true)) if rules is Dictionary else true
	for s in sessions():
		if s.character != null and "pk_decay_on" in s.character:
			s.character.pk_decay_on = on

## 角色走進房間（走路與瞬移；RegionSystem 的兩行鉤子）
func m3d_enter_room(s: Session, from: String, to: String) -> void:
	for sys in _m3d_systems():
		m2_call(sys, "on_enter_room", [s, from, to])

## BattleSystem._settle_player 結尾（WP-EVENTS 的一行鉤子）
func m3d_battle_settled(s: Session, ch, summary: Dictionary) -> void:
	for sys in _m3d_systems():
		m2_call(sys, "on_battle_settled", [s, ch, summary])

## PkSystem.on_pvp_end 開頭
func m3d_pvp_end(summary: Dictionary) -> void:
	for sys in _m3d_systems():
		m2_call(sys, "on_pvp_end", [summary])

func m3d_tick(dt: float) -> void:
	_m3d_apply_rules()   # 規則可能被主機改（server_opts_set）；在線角色每 tick 同步，便宜
	for sys in _m3d_systems():
		m2_call(sys, "tick", [dt])

func m3d_login(s: Session) -> void:
	if s != null and s.character != null and "pk_decay_on" in s.character:
		s.character.pk_decay_on = bool(rules.get("pk_decay", true))
	for sys in _m3d_systems():
		m2_call(sys, "on_login", [s])

func m3d_logout(s: Session) -> void:
	for sys in _m3d_systems():
		m2_call(sys, "on_logout", [s])

## 房間玩家列的 M3d 欄位：合併各系統 player_tags(viewer, o) 回傳的字典；"tags"（字串陣列）串接而不是覆蓋
func m3d_player_tags(viewer: Session, o: Session) -> Dictionary:
	var out := { "tags": [] }
	for sys in _m3d_systems():
		var d: Variant = m2_call(sys, "player_tags", [viewer, o], {})
		if not (d is Dictionary):
			continue
		for k in d:
			if str(k) == "tags":
				if d[k] is Array:
					for t in d[k]:
						if not (str(t) in out["tags"]):
							(out["tags"] as Array).append(str(t))
			else:
				out[k] = d[k]
	return out

## 角色刪除。M3D_PLAN 缺漏：§9.2 沒有把 intents_char.char_delete 的呼叫行派給任何 WP（不在表上的修改禁止），
## 所以目前沒有呼叫點；各系統自己在讀到不存在的角色時惰性清掉（LawSystem.refresh_board）。整合者可在
## intents_char.gd 的 on_char_deleted 列後加一行 host.m3d_char_deleted(char_id)。
func m3d_char_deleted(char_id: String) -> void:
	for sys in _m3d_systems():
		m2_call(sys, "on_char_deleted", [char_id])

## 角色表的 M3d 欄位（M3D_PLAN §7 快照增量：law、combo、titles）。M3D_PLAN 缺漏：§9.2 沒寫角色表怎麼合併，
## 照 m3d_player_tags 的作法：各系統 sheet_fields(s) 回傳字典，合併進角色表；系統為 null 時給同形狀的預設值
func m3d_sheet(s: Session, sheet: Dictionary) -> void:
	sheet["law"] = { "licensed": false, "listed": false, "claims": 0 }
	sheet["combo"] = { "partner_name": "", "moqi": 0, "peihe": 0 }
	sheet["titles"] = []
	for sys in _m3d_systems():
		var d: Variant = m2_call(sys, "sheet_fields", [s], {})
		if d is Dictionary:
			sheet.merge(d, true)

# ==== ROGUE WP-RUN ====（ROGUE_PLAN §2.2：江湖試煉的系統與 intent 檔；MUD 世界也載入，RogueSystem.enabled() 為 false 時不作用）
const ROGUE_SYSTEMS := { "rogue": "res://server/rogue_system.gd" }
const ROGUE_INTENTS := ["res://server/intents/intents_rogue.gd"]
var rogue = null        # RogueSystem 或 null

func _load_rogue() -> void:
	_load_systems(ROGUE_SYSTEMS)
	_register_intent_files(ROGUE_INTENTS)
