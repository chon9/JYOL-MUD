extends Node
## 權威遊戲邏輯（TECH_ARCH 4.2 #5、6.2、6.3、13.3）。
## 腳本在每個 peer 上都存在（RPC 設定必須一致），但只有主機上 running = true。

signal started(world_id: String)
signal stopped()
signal session_added(peer_id: int)
signal session_removed(peer_id: int)
signal warning(text: String)            # 給主機玩家看的警告（8.3：用了備份、存檔失敗）

const HELLO_TIMEOUT_MS := 5000
const REJECT_DISCONNECT_S := 0.5
const NAME_MAX_LEN := 16
const IDENTITY_MAX_LEN := 64
const RATE_LOG_EVERY := 50
const GAME_HOST_PATH := "res://server/game_host.gd"
const TICK_S := 0.1                      # M1_PLAN 3.5.1：每滿 0.1 秒世界時間呼叫一次 game.tick
const MAX_TICKS_PER_FRAME := 50
const TIME_SCALE_MIN := 0.1
const TIME_SCALE_MAX := 100.0

var running := false
var world: Dictionary = {}               # M0：world.json 的字典（M1 起換成 WorldState）
var world_id := ""
var options: Dictionary = {}
var sessions: Dictionary = {}            # peer_id -> Session
var _handlers: Dictionary = {}           # kind -> Callable(Session, Dictionary) -> Dictionary
var _outbox: Dictionary = {}             # peer_id -> Array[event]
var _pending_hello: Dictionary = {}      # peer_id -> deadline_ms
var _event_seq := 0
var _autosave_left := 0.0
var rng := RandomNumberGenerator.new()
var last_error := ""
var last_warning := ""
var _local_id_re := RegEx.create_from_string("^local_[0-9a-f]{32}$")
var _steam_id_re := RegEx.create_from_string("^steam_[1-9][0-9]{0,19}$")
var stats := { "intents_ok": 0, "intents_rejected": 0, "intents_dropped": 0, "chats": 0 }
## M1：遊戲主機（GameHost）。start() 成功後建立；stop() 時 shutdown() 後設為 null。
## M1_PLAN 缺漏：契約寫 `var game: GameHost`；這裡以 load() 動態建立且不加型別，
## 讓本 Autoload 在其他 WP 的類別尚未合併（或載入失敗）時仍能解析並維持 M0 行為。
var game = null
var game_error := ""
var time_scale := 1.0                    # --time-scale，夾在 [0.1, 100]（D10）
## --debug-intents（M3A_PLAN 6.11）：GameHost 建立時讀這個值決定要不要註冊 debug_set（只給驗收 bot 用）
var debug_intents := false
## M3c2 WP-CARRY：標題畫面開房前勾選的「允許外來角色」（-1 ＝沒指定；0／1）；start() 套用後清回 -1
var host_foreign_choice := -1
var _tick_acc := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_handlers()
	var args := CliArgs.current()
	if args.get("time-scale") is String:
		set_time_scale(float(args["time-scale"]))
	debug_intents = args.has("debug-intents") and str(args["debug-intents"]) != "false"

func _reset_handlers() -> void:
	_handlers = {
		Protocol.I_PING: _intent_ping,
		Protocol.I_CHAT: _intent_chat,
	}

func set_time_scale(v: float) -> void:
	time_scale = clampf(v, TIME_SCALE_MIN, TIME_SCALE_MAX) if v > 0.0 else 1.0

## M1_PLAN 3.5.1：intent 處理器 handler(s: Session, args: Dictionary) -> { ok, reason }
func register_intent(kind: String, handler: Callable) -> void:
	_handlers[kind] = handler

func has_intent_handler(kind: String) -> bool:
	return _handlers.has(kind)

# ---------- 生命週期 ----------
## 主機開世界：載入或建立 world.json，啟用資料視圖
func start(p_world_id: String, world_name: String = "") -> Error:
	if running:
		stop()
	world_id = p_world_id if p_world_id != "" else "default"
	last_error = ""
	last_warning = ""
	var loaded := SaveManager.load_world(world_id)
	if loaded["ok"]:
		world = loaded["data"]
		options = SaveManager.load_options(world_id)
		var main_path := ProjectSettings.globalize_path(SaveManager.world_path(world_id))
		if str(loaded["source"]) != main_path:
			_warn("世界存檔讀取失敗，已改用備份：%s" % str(loaded["source"]).get_file())
	elif SaveManager.world_files_exist(world_id):
		# 檔案在但全部讀不了（損壞或較新版本的 schema）：不可覆寫，保留原檔交給玩家處理（8.3）
		world = {}
		last_error = "世界「%s」的存檔與 %d 份備份都無法讀取（損壞或版本不符），未開啟以免覆寫。" % [world_id, SaveManager.BAK_COUNT]
		push_error("[WorldServer] " + last_error)
		warning.emit(last_error)
		return ERR_FILE_CORRUPT
	else:
		options = GameData.default_server_options()
		# --rule-preset=<rule_profiles.id>：只影響「新建」的世界（既有世界沿用存檔裡的規則）
		var preset_arg: Variant = CliArgs.current().get("rule-preset")
		if preset_arg is String and preset_arg != "":
			if not GameData.loader.all_tables.get("rule_profiles", {}).has(preset_arg):
				last_error = "未知的規則預設：%s" % preset_arg
				push_error("[WorldServer] " + last_error)
				return ERR_INVALID_PARAMETER
			options["rule_profile"] = { "preset": preset_arg, "overrides": {} }
			print("[WorldServer] new world uses rule preset '%s'" % preset_arg)
		# M3B_PLAN §2.1、O1：新世界的 era = --eras → 規則預設列的 default_eras → server_options.default.enabled_eras
		var eras_arg: Variant = CliArgs.current().get("eras")
		var decided := decide_new_world_eras(eras_arg if eras_arg is String else "", options)
		if str(decided["error"]) != "":
			last_error = str(decided["error"])
			push_error("[WorldServer] " + last_error)
			return ERR_INVALID_PARAMETER
		options["enabled_eras"] = decided["eras"]
		print("[WorldServer] new world enables eras %s (%s)" % [str(decided["eras"]), str(decided["source"])])
		world = SaveManager.new_world(world_id, world_name if world_name != "" else world_id,
			GameData.content_hash, options)
		SaveManager.save_options(world_id, options)
	if options.is_empty():
		options = GameData.default_server_options()
	# 既有世界的 options.json 沒有新版的 key（M2_PLAN 4.7.1）：補預設值（只補缺的，不改已有的）
	var defaults := GameData.default_server_options()
	for k in defaults:
		if not options.has(k):
			options[k] = defaults[k]
	# M3B_PLAN §2.1：world.json 的 enabled_eras 永遠是權威；options 的預設值不得蓋掉它（新預設是 1.0A＋1.0B）
	if world.get("enabled_eras") is Array:
		options["enabled_eras"] = (world["enabled_eras"] as Array).duplicate()
	# M3B_PLAN §2.3、O2：主機在伺服器設定打開 1.0B → pending_eras；開服時套用（通過驗證才寫進 world）
	apply_pending_eras()
	# --opts=key=value[,key=value…]（M2_PLAN 4.6.9）：新建或既有世界都套用並存進 options.json
	var opts_arg: Variant = CliArgs.current().get("opts")
	if opts_arg is String and opts_arg != "":
		var parsed := parse_cli_opts(opts_arg, defaults)
		if str(parsed["error"]) != "":
			last_error = "--opts 不合法：%s" % parsed["error"]
			push_error("[WorldServer] " + last_error)
			world = {}
			return ERR_INVALID_PARAMETER
		var vals: Dictionary = parsed["values"]
		for k in vals:
			options[k] = vals[k]
		SaveManager.save_options(world_id, options)
		print("[WorldServer] --opts applied: %s" % str(vals))
	# --stagecoach=on|off：新建或既有世界都寫進該世界的 options（WORLD_2001 §9.1）；沒給就沿用存檔值，預設 false
	var coach_arg: Variant = CliArgs.current().get("stagecoach")
	if coach_arg is String and coach_arg != "":
		var on: bool = coach_arg.to_lower() in ["on", "true", "1", "yes"]
		if not (coach_arg.to_lower() in ["on", "off", "true", "false", "1", "0", "yes", "no"]):
			last_error = "--stagecoach 只能是 on 或 off：%s" % coach_arg
			push_error("[WorldServer] " + last_error)
			world = {}
			return ERR_INVALID_PARAMETER
		options["stagecoach_enabled"] = on
		SaveManager.save_options(world_id, options)
		print("[WorldServer] stagecoach_enabled = %s" % str(on))
	options["stagecoach_enabled"] = options.get("stagecoach_enabled", false) == true
	# M3c2 WP-CARRY（§5.3）：標題畫面開房前勾的「允許外來角色」→ 存進這個世界的 options.json（只用一次）
	if host_foreign_choice >= 0:
		options["allow_foreign_characters"] = host_foreign_choice == 1
		SaveManager.save_options(world_id, options)
		print("[WorldServer] allow_foreign_characters = %s" % str(host_foreign_choice == 1))
		host_foreign_choice = -1
	if not GameData.activate(world.get("enabled_eras", ["1.0A"]), world.get("rule_profile", {})):
		last_error = "資料啟用失敗：%s" % ", ".join(GameData.activate_errors)
		push_error("[WorldServer] " + last_error)
		world = {}
		return ERR_INVALID_DATA
	world["content_hash"] = GameData.content_hash
	rng.randomize()
	sessions.clear()
	_outbox.clear()
	_pending_hello.clear()
	_autosave_left = float(options.get("autosave_interval_s", 60))
	_tick_acc = 0.0
	running = true
	_create_game()
	save_now()
	started.emit(world_id)
	print("[WorldServer] started world '%s'" % world_id)
	return OK

## M3B_PLAN §2.1、O1：新建世界的 era。eras_arg（--eras=1.0A,1.0B；空字串＝沒給）優先 → opts.rule_profile.preset 那一列的
## default_eras（classic_strict = ["1.0A"]）→ opts.enabled_eras（server_options.default：["1.0A","1.0B"]）。
## 回傳 { eras: Array, source: "cli"|"preset"|"default", error: String }；結果都經 DataLoader.validate_enabled_eras 檢查
static func decide_new_world_eras(eras_arg: String, opts: Dictionary) -> Dictionary:
	var all_eras: Dictionary = GameData.loader.all_tables.get("eras", {})
	if eras_arg != "":
		var eras_list: Array = []
		for e in eras_arg.split(",", false):
			if e.strip_edges() != "" and not (e.strip_edges() in eras_list):
				eras_list.append(e.strip_edges())
		var bad := DataLoader.validate_enabled_eras(all_eras, eras_list)
		if not bad.is_empty():
			return { "eras": [], "source": "cli", "error": "--eras 不合法：%s" % ", ".join(bad) }
		return { "eras": eras_list, "source": "cli", "error": "" }
	var preset_eras := preset_default_eras(opts)
	if not preset_eras.is_empty() and DataLoader.validate_enabled_eras(all_eras, preset_eras).is_empty():
		return { "eras": preset_eras, "source": "preset", "error": "" }
	var def: Array = (opts.get("enabled_eras", ["1.0A"]) as Array).duplicate() if opts.get("enabled_eras") is Array else ["1.0A"]
	var bad2 := DataLoader.validate_enabled_eras(all_eras, def)
	if not bad2.is_empty():
		return { "eras": [], "source": "default", "error": "預設的 enabled_eras 不合法：%s" % ", ".join(bad2) }
	return { "eras": def, "source": "default", "error": "" }

## M3B_PLAN §2.1：規則預設列（--rule-preset 或 options.rule_profile.preset）的 default_eras；沒有回 []
static func preset_default_eras(opts: Dictionary) -> Array:
	var rp: Variant = opts.get("rule_profile", {})
	var preset := str(rp.get("preset", "")) if rp is Dictionary else ""
	var row: Variant = GameData.loader.all_tables.get("rule_profiles", {}).get(preset, {})
	var de: Variant = row.get("default_eras", []) if row is Dictionary else []
	var out: Array = []
	if de is Array:
		for e in de:
			if not (str(e) in out):
				out.append(str(e))
	return out

## M3B_PLAN §2.3：options.pending_eras 非空且合法 → 寫進 world.enabled_eras、清掉 pending_eras、存 options（world 在開服的 save_now 存）。
## 不合法時保留在 options 裡並警告。回傳是否套用了
func apply_pending_eras() -> bool:
	var pend: Variant = options.get("pending_eras", [])
	if not (pend is Array) or (pend as Array).is_empty():
		return false
	var list: Array = []
	for e in pend:
		if not (str(e) in list):
			list.append(str(e))
	var bad := DataLoader.validate_enabled_eras(GameData.loader.all_tables.get("eras", {}), list)
	if not bad.is_empty():
		_warn("待開放的資料片不合法，沒有套用：%s" % ", ".join(bad))
		return false
	world["enabled_eras"] = list
	options["enabled_eras"] = list.duplicate()
	options["pending_eras"] = []
	SaveManager.save_options(world_id, options)
	print("[WorldServer] pending eras applied: %s" % str(list))
	return true

func stop() -> void:
	if not running:
		return
	# M2_PLAN 4.6.9：停止前先告訴所有人（客戶端顯示「主機已離線，江湖凍結」），並立刻送出
	broadcast_event(Protocol.CH_SYSTEM, Protocol.E_HOST_CLOSING, {})
	flush()
	if game != null:
		game.shutdown()          # 中止戰鬥（ABORTED）、存所有在線角色
		flush()
	save_now()
	if game != null:
		game.dispose()   # 切斷 GameHost ↔ 子系統的循環引用
	game = null
	_reset_handlers()
	running = false
	sessions.clear()
	_outbox.clear()
	_pending_hello.clear()
	stopped.emit()

## 建立 GameHost；失敗時保持 M0 行為（只有 ping、chat）
func _create_game() -> void:
	game = null
	game_error = ""
	_reset_handlers()
	if not ResourceLoader.exists(GAME_HOST_PATH):
		game_error = "missing " + GAME_HOST_PATH
		push_warning("[WorldServer] GameHost unavailable: " + game_error)
		return
	var script := load(GAME_HOST_PATH) as GDScript
	if script == null or not script.can_instantiate():
		game_error = "GameHost script failed to load"
		push_error("[WorldServer] " + game_error)
		return
	game = script.new(self)

## 角色檔先、world.json 後。world_first = true 時反過來（翻屍體：物品從 world.json 的屍體移到角色身上，
## 兩個檔案無法一起原子寫入；先寫 world.json，當機時最多是物品消失，不會在屍體和角色身上各有一份；M2 審查）
func save_now(world_first := false) -> Error:
	if world.is_empty():
		return ERR_UNCONFIGURED
	if game != null and not world_first:
		game.save_all()
	var err := SaveManager.save_world(world)
	if err != OK:
		_warn("存檔失敗，舊檔已保留：" + SaveManager.last_error)
	if game != null and world_first:
		game.save_all()
	return err

func _warn(text: String) -> void:
	last_warning = text
	push_warning("[WorldServer] " + text)
	warning.emit(text)

func world_info() -> Dictionary:
	return {
		"world_id": world.get("world_id", ""),
		"world_name": world.get("world_name", ""),
		"enabled_eras": GameData.enabled_eras.duplicate(),
		"rule_profile": GameData.rules.duplicate(),     # 已展開（5.6）
		"content_hash": GameData.content_hash,
		"protocol": Protocol.VERSION,
		"stagecoach_enabled": options.get("stagecoach_enabled", false) == true,
		# M2_PLAN 4.7.2
		"pk_mode": str(options.get("pk_mode", "CLASSIC")),
		"wait_mode": bool(options.get("wait_mode", true)),
		# 查看偵察（docs/GDD.md §5.10【設計提案・非原作】）：客戶端只在 true 時送 look { scout: true }、顯示查看的冷卻
		"scout_enabled": options.get("scout_enabled", true) != false,
		# M3A_PLAN 6.12：「內」「穴」與規則 later_battle_cmds（classic_strict 關）
		"later_battle_cmds": GameData.rules.get("later_battle_cmds", true) != false,
		# STORY_PLAN §5.5（客戶端決定要不要顯示江湖傳聞頁、惡人標記）
		"rumors_enabled": options.get("rumors_enabled", true) != false,
		"wanderers_enabled": options.get("wanderers_enabled", true) != false,
		# M3B_PLAN §6 world_info 新欄位
		"jail_location_resolved": game.sects.jail_location_resolved() if game != null and game.get("sects") != null else "SECT",
		# M3b 審查：違反門規的牢房（AUTO 仍是各派思過處；只有選項 CAPITAL 才送京城監獄）
		"jail_breach_resolved": game.sects.breach_jail_resolved() if game != null and game.get("sects") != null else "SECT",
		"gb_assembly": "MONTHLY" if str(options.get("gb_assembly", "DAILY")) == "MONTHLY" else "DAILY",
		"seize_enabled": options.get("seize_enabled", true) != false and GameData.enabled_eras.has("1.0B"),
		"pending_eras": (options.get("pending_eras", []) as Array).duplicate() if options.get("pending_eras") is Array else [],
		# 創角的出生城（生效 regions 中 birth_allowed 的 CITY；M3B_PLAN §5.1.9、§7 #10）：[{ id, name }]
		"birth_cities": _birth_cities(),
		# M3c2 WP-CARRY（M3C2_PLAN §5.3、§6）：外來角色（單機一律可以；開房看選項）與主機的版本列
		"allow_foreign_characters": options.get("allow_foreign_characters", false) == true,
		"foreign_allowed": game.foreign_allowed() if game != null else false,
		"game_version": BuildInfo.version(),
	}

func _birth_cities() -> Array:
	var out: Array = []
	var regions: Dictionary = GameData.tables.get("regions", {})
	var ids: Array = regions.keys()
	ids.sort()
	for rid in ids:
		var r: Variant = regions[rid]
		if r is Dictionary and bool(r.get("birth_allowed", false)) and str(r.get("type", "")) == "CITY":
			out.append({ "id": str(rid), "name": str(r.get("name", rid)) })
	return out

## --opts 能改的 key（M2_PLAN 4.7.1 標「CLI」者＋既有可用者）；型別依預設值
const CLI_OPTS := ["guards_enabled", "encounters_enabled", "pending_retry_cooldown_real_s", "chat_water_cost", "chat_min_interval_ms", "party_max", "battle_max_humans",
	"pending_ttl_real_s", "mail_inbox_max", "mail_min_interval_real_s", "corpse_auth_max",
	"pk_mode", "newbie_pk_protect_xp", "wait_mode", "wait_mode_timeout_s", "allow_foreign_characters", "scout_enabled",
	# M3A_PLAN 3.10
	"sect_hostile_entry", "poison_flare_enabled", "jail_breach_days", "jail_enemy_days", "ban_days", "jail_ransom",
	# M3B_PLAN §4.11（WP-SECT；錢莊、組織的整數選項也開放給測試）
	"jail_location", "gb_assembly", "seize_enabled", "guild_signers", "bank_capacity", "bank_money_cap",
	"consign_fee_base", "consign_fee_per_weight", "consign_hold_days", "org_found_fame", "org_signer_fame", "org_found_fee",
	"org_member_max", "org_petition_days",
	# STORY_PLAN §5.5
	"rumors_enabled", "rumor_min_gap_s", "rumor_chat_inner_min", "wanderers_enabled", "villain_warn_s", "chase_npcs",
	"ambient_lines", "npc_reactions",
	# M3C_PLAN §9.3
	"npc_respawn_pct", "loot_drop_pct"]
## STORY_PLAN §5.4：npc_reactions 的合法值
const NPC_REACTION_MODES := ["OFF", "FLAVOR", "FULL"]

## "a=1,b=true" → { values: {a: 1, b: true}, error: "" }；錯誤時 error 非空、values 為空
static func parse_cli_opts(spec: String, defaults: Dictionary) -> Dictionary:
	var values := {}
	for part in spec.split(",", false):
		var item := part.strip_edges()
		if item == "":
			continue
		var eq := item.find("=")
		if eq <= 0:
			return { "values": {}, "error": "格式應為 key=value：%s" % item }
		var key := item.substr(0, eq).strip_edges()
		var raw := item.substr(eq + 1).strip_edges()
		if not (key in CLI_OPTS):
			return { "values": {}, "error": "不能用 --opts 改的設定：%s" % key }
		var def: Variant = defaults.get(key)
		match typeof(def):
			TYPE_BOOL:
				var low := raw.to_lower()
				if low in ["true", "on", "1", "yes"]:
					values[key] = true
				elif low in ["false", "off", "0", "no"]:
					values[key] = false
				else:
					return { "values": {}, "error": "%s 要是 true／false：%s" % [key, raw] }
			TYPE_INT, TYPE_FLOAT:
				if not raw.is_valid_int() or raw.to_int() < 0:
					return { "values": {}, "error": "%s 要是非負整數：%s" % [key, raw] }
				values[key] = raw.to_int()
			_:
				if key == "pk_mode" and not (raw in Protocol.PK_MODES):
					return { "values": {}, "error": "pk_mode 只能是 %s：%s" % ["／".join(Protocol.PK_MODES), raw] }
				if key == "npc_reactions" and not (raw in NPC_REACTION_MODES):
					return { "values": {}, "error": "npc_reactions 只能是 %s：%s" % ["／".join(NPC_REACTION_MODES), raw] }
				if key == "jail_location" and not (raw in DataSchema.JAIL_LOCATIONS):
					return { "values": {}, "error": "jail_location 只能是 %s：%s" % ["／".join(DataSchema.JAIL_LOCATIONS), raw] }
				if key == "gb_assembly" and not (raw in DataSchema.ASSEMBLY_MODES):
					return { "values": {}, "error": "gb_assembly 只能是 %s：%s" % ["／".join(DataSchema.ASSEMBLY_MODES), raw] }
				values[key] = raw
	return { "values": values, "error": "" }

func _process(delta: float) -> void:
	if not running:
		return
	_advance_world(delta * time_scale)
	_check_hello_timeouts()
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = float(options.get("autosave_interval_s", 60))
		save_now()
		if game != null:
			game.on_autosave()   # 每個在線角色一份護照（M2_PLAN 4.6.8）
	flush()

func world_time() -> float:
	return float(world.get("world_time_s", 0.0))

## 世界時間 += scaled；每滿 0.1 秒呼叫一次 game.tick(0.1)（一幀最多 50 次）
func _advance_world(scaled: float) -> void:
	world["world_time_s"] = world_time() + scaled
	if game == null:
		return
	_tick_acc += scaled
	var n := 0
	while _tick_acc >= TICK_S and n < MAX_TICKS_PER_FRAME:
		_tick_acc -= TICK_S
		n += 1
		game.tick(TICK_S)
	if n >= MAX_TICKS_PER_FRAME:
		_tick_acc = minf(_tick_acc, TICK_S)

## 測試用：把世界時間往前推 seconds（不受 time_scale 影響），逐 tick 推進後 flush
func advance(seconds: float) -> void:
	if not running:
		return
	var left := seconds
	while left > 0.0:
		var step := minf(left, TICK_S)
		world["world_time_s"] = world_time() + step
		left -= step
		if game != null:
			_tick_acc += step
			while _tick_acc >= TICK_S - 0.000001:
				_tick_acc = maxf(0.0, _tick_acc - TICK_S)
				game.tick(TICK_S)
	flush()

# ---------- 連線與握手（6.2） ----------
func on_peer_connected(peer_id: int) -> void:
	if running:
		_pending_hello[peer_id] = Time.get_ticks_msec() + HELLO_TIMEOUT_MS

func on_peer_disconnected(peer_id: int) -> void:
	_pending_hello.erase(peer_id)
	remove_session(peer_id)

## 移除一個 session（斷線、被踢、被同一身分的重連取代）：斷線戰鬥照常（自動防）、離隊、存角色、離開房間。
## 回傳是否真的移除了。
func remove_session(peer_id: int) -> bool:
	_outbox.erase(peer_id)
	if not sessions.has(peer_id):
		return false
	var s: Session = sessions[peer_id]
	if game != null:
		game.on_session_removed(s)   # 斷線戰鬥照常、離隊、存角色、離開房間
	sessions.erase(peer_id)
	_outbox.erase(peer_id)
	session_removed.emit(peer_id)
	_broadcast(Protocol.CH_SYSTEM, Protocol.E_LEAVE, { "name": s.display_name, "peer": peer_id })
	_broadcast_roster()
	return true

func _check_hello_timeouts() -> void:
	var now := Time.get_ticks_msec()
	for peer_id in _pending_hello.keys():
		if now > int(_pending_hello[peer_id]):
			_pending_hello.erase(peer_id)
			push_warning("[WorldServer] hello timeout: peer %d" % peer_id)
			NetworkManager.force_disconnect(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func c2s_hello(hello: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	handle_hello(multiplayer.get_remote_sender_id(), hello)

## 回傳空字串代表通過；否則回傳拒絕原因並在 0.5 秒後斷線。
## 只接受「已連線、尚未握手」的 peer 的第一個 hello；之後的 hello（含已加入者重送、被拒後重試）一律丟棄。
func handle_hello(peer_id: int, hello: Dictionary) -> String:
	if not running:
		return "drop:not_running"
	if not _pending_hello.has(peer_id):
		return "drop:not_pending"
	_pending_hello.erase(peer_id)
	var reason := validate_hello(peer_id, hello)
	if reason != "":
		ClientState.deliver_rejected(peer_id, reject_wire(reason))   # M3c2 WP-CARRY §6.3：附主機的版本、協定、指紋
		get_tree().create_timer(REJECT_DISCONNECT_S).timeout.connect(NetworkManager.force_disconnect.bind(peer_id))
		return reason
	var identity := NetworkManager.identity_for_peer(peer_id, str(hello.get("identity", "")))
	# M2_PLAN 4.6.9：同一身分已有 session（斷線還沒被偵測到、或從另一台重連）→ 移除舊的再接受新的（重連取代）
	var old := session_of_identity(identity)
	if old != null and old.peer_id != peer_id:
		var old_peer := old.peer_id
		print("[WorldServer] identity %s reconnected: peer %d replaces %d" % [identity, peer_id, old_peer])
		remove_session(old_peer)
		NetworkManager.force_disconnect(old_peer)
	_add_session(peer_id, identity, str(hello.get("display_name", "")))
	return ""

func session_of_identity(identity: String) -> Session:
	for s in sessions.values():
		if s.identity == identity:
			return s
	return null

func validate_hello(peer_id: int, hello: Dictionary) -> String:
	if sessions.has(peer_id):
		return "already_joined"
	if int(hello.get("protocol", -1)) != Protocol.VERSION:
		return "protocol_mismatch"
	if str(hello.get("game_version", "")) != Protocol.GAME_VERSION:
		return "version_mismatch"
	if str(hello.get("content_hash", "")) != GameData.content_hash:
		return "content_mismatch"
	var identity := NetworkManager.identity_for_peer(peer_id, str(hello.get("identity", "")))
	if not is_valid_identity(identity, NetworkManager.mode == NetworkManager.Mode.STEAM_HOST):
		return "bad_identity"
	if world.get("known_identities", {}).get(identity, {}).get("banned", false):
		return "banned"
	# 重連取代（M2_PLAN 4.6.9）：同身分的舊 session 會被移除，不算進人數；
	# M2_PLAN 缺漏：主機本機玩家（is_local）沒有網路連線可斷，不能被網路上的同身分取代，仍回 already_connected
	var replacing := 0
	for s in sessions.values():
		if s.identity == identity:
			if s.is_local:
				return "already_connected"
			replacing += 1
	if sessions.size() - replacing >= int(options.get("max_players", 8)):
		return "server_full"
	return ""

## Steam 主機只收主機查到的 steam_<SteamID64>；ENet／離線只收 local_<32 hex>（6.2）
func is_valid_identity(identity: String, steam: bool) -> bool:
	if identity.length() > IDENTITY_MAX_LEN:
		return false
	var re: RegEx = _steam_id_re if steam else _local_id_re
	return re.search(identity) != null

## 主機玩家與離線模式（6.4）：不經網路，直接建立本地 session
func register_local_player(identity: String, display_name: String) -> int:
	var peer_id := multiplayer.get_unique_id()
	if sessions.has(peer_id):
		return peer_id
	_add_session(peer_id, identity, display_name, true)
	return peer_id

## local：主機本機玩家（register_local_player；非 --dedicated，含離線模式）→ 管理員（M2_PLAN 4.6.8）
func _add_session(peer_id: int, identity: String, display_name: String, local := false) -> Session:
	var s := Session.new(peer_id, identity, _clean_name(display_name))
	s.is_local = local
	var admins: Variant = options.get("admin_identities", [])
	s.is_admin = local or (admins is Array and identity in admins)
	sessions[peer_id] = s
	print("[WorldServer] session joined: peer %d %s (%s)" % [peer_id, s.display_name, identity])
	var known: Dictionary = world.get_or_add("known_identities", {})
	var entry: Dictionary = known.get(identity, { "banned": false })
	entry["last_name"] = s.display_name
	known[identity] = entry
	var chars: Array = game.char_list_for(s) if game != null else []   # M3c2 WP-CARRY：含可選身分的角色（§5.7）
	ClientState.deliver_welcome(peer_id, { "world_info": world_info(), "your_characters": chars, "your_peer_id": peer_id })
	session_added.emit(peer_id)
	_broadcast(Protocol.CH_SYSTEM, Protocol.E_JOIN, { "name": s.display_name, "peer": peer_id })
	_broadcast_roster()
	return s

static func _clean_name(n: String) -> String:
	var out := Protocol.clean_text(n, NAME_MAX_LEN)   # H6：同一套清理（控制字元、BBCode 方括號）
	if out.is_empty():
		out = "無名氏"
	return out

# ---------- Intent（6.3） ----------
## 客戶端 → 主機的唯一 RPC 入口
@rpc("any_peer", "call_remote", "reliable")
func c2s_intent(seq: int, kind: String, args: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	handle_intent(multiplayer.get_remote_sender_id(), seq, kind, args)

## 回傳 { ok, reason }。沒有回覆的情況（無 session、速率超過、序號錯）reason 以 "drop:" 開頭。
func handle_intent(peer_id: int, seq: int, kind: String, args: Dictionary) -> Dictionary:
	if not running or not multiplayer.is_server():
		return _drop("not_server")
	var s: Session = sessions.get(peer_id)
	if s == null:
		return _drop("no_session")
	if seq <= s.last_seq:
		return _drop("stale_seq")
	if not s.rate_limiter.allow():
		s.dropped_intents += 1
		if s.dropped_intents == 1 or s.dropped_intents % RATE_LOG_EVERY == 0:
			push_warning("[WorldServer] rate limited: peer %d %s, dropped %d" % [peer_id, s.identity, s.dropped_intents])
		return _drop("rate_limited")
	s.last_seq = seq
	var reason := Protocol.validate_args(kind, args)
	if reason == "" and not _handlers.has(kind):
		reason = "unknown_intent"
	var result: Dictionary
	if reason != "":
		result = { "ok": false, "reason": reason }
	else:
		result = _handlers[kind].call(s, args)
	if result.get("ok", false):
		stats["intents_ok"] += 1
	else:
		stats["intents_rejected"] += 1
	var extra := {}
	if result.has("left_s"):
		extra["left_s"] = int(result["left_s"])   # busy：還要幾秒（M1_PLAN 3.7、3.9.6）
	ClientState.deliver_result(peer_id, seq, bool(result.get("ok", false)), str(result.get("reason", "")), extra)
	return result

func _drop(reason: String) -> Dictionary:
	stats["intents_dropped"] += 1
	return { "ok": false, "reason": "drop:" + reason }

func _intent_ping(s: Session, args: Dictionary) -> Dictionary:
	_queue(s.peer_id, Protocol.CH_SYSTEM, Protocol.E_PONG, { "nonce": int(args.get("nonce", 0)) })
	return { "ok": true }

## M0 千里傳音（送給所有人）。M2 起由 WP-SOCIAL 的 intents_social.gd 以同一個 kind 覆蓋（依頻道路由並扣飲水）；
## 只有 SocialSystem 沒載入時才會走到這裡，此時千里傳音以外的頻道一律 bad_channel。
func _intent_chat(s: Session, args: Dictionary) -> Dictionary:
	var ch: String = args.get("ch", Protocol.CH_CHAT_WORLD)
	if ch != Protocol.CH_CHAT_WORLD:
		return { "ok": false, "reason": "bad_channel" }
	var text := Protocol.clean_text(args["text"] as String, Protocol.CHAT_MAX_LEN)
	if text.is_empty():
		return { "ok": false, "reason": "empty_text" }
	stats["chats"] += 1
	_broadcast(ch, Protocol.E_CHAT, { "from": s.display_name, "from_peer": s.peer_id, "text": text })
	return { "ok": true }

# ---------- 事件（11.1、6.5） ----------
func _make_event(ch: String, key: String, p: Dictionary, ui := false) -> Dictionary:
	_event_seq += 1
	var e := { "seq": _event_seq, "t": world_time(), "ch": ch, "key": key, "p": p }
	if ui:
		e["ui"] = true
	return e

## M1_PLAN 3.5.1：對單一 peer 排入事件；ui == true 的事件頂層帶 "ui": true（沒有模板，只給 UI 用）
func queue_event(peer_id: int, ch: String, key: String, p: Dictionary, ui := false) -> void:
	if not sessions.has(peer_id):
		return
	_outbox.get_or_add(peer_id, []).append(_make_event(ch, key, p, ui))

func broadcast_event(ch: String, key: String, p: Dictionary, ui := false) -> void:
	var e := _make_event(ch, key, p, ui)
	for peer_id in sessions:
		_outbox.get_or_add(peer_id, []).append(e)

## 同房間（已選角且位置在 room_id）的所有玩家；except_peer 不收
func queue_room_event(room_id: String, ch: String, key: String, p: Dictionary, except_peer := 0) -> void:
	var e := {}
	for peer_id in sessions:
		if peer_id == except_peer:
			continue
		var s: Session = sessions[peer_id]
		if s.room_id() != room_id or room_id == "":
			continue
		if e.is_empty():
			e = _make_event(ch, key, p)
		_outbox.get_or_add(peer_id, []).append(e)

## 轉送已組好的事件（Battle 產生的 { ch, key, p, bid[, ui] }）：補上 seq 與 t
func forward_event(peer_id: int, ev: Dictionary) -> void:
	if not sessions.has(peer_id):
		return
	var e := ev.duplicate()
	_event_seq += 1
	e["seq"] = _event_seq
	e["t"] = world_time()
	_outbox.get_or_add(peer_id, []).append(e)

func _queue(peer_id: int, ch: String, key: String, p: Dictionary) -> void:
	_outbox.get_or_add(peer_id, []).append(_make_event(ch, key, p))

func _broadcast(ch: String, key: String, p: Dictionary) -> void:
	var e := _make_event(ch, key, p)
	for peer_id in sessions:
		_outbox.get_or_add(peer_id, []).append(e)

## 玩家名單走 s2c_roster（6.6），不進事件紀錄
func _broadcast_roster() -> void:
	var entries: Array = []
	for s in sessions.values():
		entries.append(s.to_roster_entry())
	for peer_id in sessions:
		ClientState.deliver_roster(peer_id, entries)

## 每幀最多送一次（6.5）
func flush() -> void:
	if _outbox.is_empty():
		return
	var box := _outbox
	_outbox = {}
	for peer_id in box:
		if sessions.has(peer_id) and not box[peer_id].is_empty():
			ClientState.deliver_events(peer_id, box[peer_id])

func pending_events(peer_id: int) -> Array:
	return _outbox.get(peer_id, [])

# ==== M3c2 WP-CARRY ====（M3C2_PLAN §6.3）
## 協定／版本／資料不同的拒絕：送 "<code>|<主機版本>|<主機協定>|<主機指紋12>"；其他原因照舊只有代碼
static func reject_wire(reason: String) -> String:
	if reason in Protocol.REJECT_WITH_BUILD:
		return BuildInfo.reject_reason(reason, GameData.content_hash)
	return reason

## 標題畫面：開房前指定這次開的世界要不要允許外來角色（start() 時存進 options.json）
func set_host_foreign_choice(allow: bool) -> void:
	host_foreign_choice = 1 if allow else 0
