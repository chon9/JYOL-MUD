extends SceneTree
## 資料檢查（TECH_ARCH 15.1、15.2）：非 0 結束碼代表有錯。
## godot --headless --path . --script res://tools/data_lint.gd [-- --dir=res://data --verbose]

const REQUIRE_FIELDS := ["requires", "join_requires", "hostile_if", "teach_requires", "ok_if"]   # ok_if：sect_rules（M3A_PLAN 3.3）
const HOST_OFFLINE_POLICIES := ["FROZEN", "BACKUP_HOST", "DEDICATED"]
const SRC_TAGS := ["verified", "later", "unverified", "proposal"]
## M2_PLAN 4.7.1（與 Protocol.PK_MODES 相同）
const PK_MODES := ["CLASSIC", "CHALLENGE_ONLY", "OFF"]
const M2_BOOL_OPTIONS := ["guards_enabled", "encounters_enabled", "wait_mode", "allow_foreign_characters", "allow_foreign_divine"]
const M2_INT_OPTIONS := {
	"chat_water_cost": [0, 100], "chat_min_interval_ms": [0, 60000], "party_max": [2, 8],
	"battle_max_humans": [1, 8], "pending_ttl_real_s": [5, 3600], "pending_retry_cooldown_real_s": [0, 600], "mail_inbox_max": [1, 1000],
	"mail_min_interval_real_s": [0, 3600], "corpse_auth_max": [0, 16],
}

var errors: PackedStringArray = []
var warnings: PackedStringArray = []

func _initialize() -> void:
	var dir := "res://data"
	var verbose := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.substr(6)
		elif a == "--verbose":
			verbose = true
	var code := lint(dir, verbose)
	quit(code)

func lint(dir: String, verbose := false) -> int:
	var loader := DataLoader.new()
	loader.load_all(dir)
	for e in loader.errors:
		errors.append("load: " + e)
	var eras: Dictionary = loader.all_tables.get("eras", {})

	_check_eras(eras)
	_check_row_eras_and_src(loader, eras)
	_check_requires(loader)
	_check_rule_profiles(loader.all_tables.get("rule_profiles", {}))
	_check_server_options(loader, eras)
	_check_region_maps(loader)
	_check_nested_requires(loader)
	_check_art(dir, loader)
	_check_m3b_raw(loader, eras)
	_check_m3c_options(loader)
	_check_proc_templates(loader)
	_check_m3c2_options(loader)   # M3c2 WP-PACE
	_check_m3d_options(loader)    # M3d（WP-LAW Day-0：五個選項）

	# 每個 era 加上它的 requires 閉包各跑一次 activate()（5.5.2）
	var era_ids: Array = eras.keys()
	era_ids.sort_custom(func(a, b): return int(eras[a].get("order", 0)) < int(eras[b].get("order", 0)))
	for era_id in era_ids:
		var combo := DataLoader.era_closure(eras, era_id)
		var bad := DataLoader.validate_enabled_eras(eras, combo)
		for e in bad:
			errors.append("eras closure %s: %s" % [era_id, e])
		var view := loader.activate(combo)
		for e in loader.activate_errors:
			errors.append("activate %s: %s" % [era_id, e])
		# M1 內容檢查（M1_PLAN 3.11.15）；各 era 視圖相同時錯誤去重
		for e in check_content(view):
			var msg := "content: " + e
			if not (msg in errors):
				errors.append(msg)
		for w in check_story_warnings(view):
			var swmsg := "story: " + w
			if not (swmsg in warnings):
				warnings.append(swmsg)
		# WORLD_2001 §1.4 新手安全規則（warning；測試裡用 assert）
		for w in check_newbie_routes(view):
			var wmsg := "newbie route %s: %s" % [era_id, w]
			if not (wmsg in warnings):
				warnings.append(wmsg)

	var unverified := 0
	for t in loader.all_tables:
		for id in loader.all_tables[t]:
			if loader.all_tables[t][id].get("src", "") == "unverified":
				unverified += 1
				if verbose:
					print("  unverified: %s.%s" % [t, id])

	for w in warnings:
		print("WARN  " + w)
	for e in errors:
		print("ERROR " + e)
	var rows := 0
	for t in loader.all_tables:
		rows += loader.all_tables[t].size()
	print("data_lint: %d files, %d rows, %d maps, %d eras checked, %d unverified rows, %d warnings, %d errors" % [
		loader.file_count, rows, loader.all_maps.size(), era_ids.size(), unverified, warnings.size(), errors.size()])
	print("content_hash: " + loader.content_hash)
	return 1 if errors.size() > 0 else 0

func _check_eras(eras: Dictionary) -> void:
	var bases := 0
	for id in eras:
		var e: Dictionary = eras[id]
		if e.get("base", false):
			bases += 1
		if not e.has("order"):
			errors.append("eras.%s: missing order" % id)
		for r in e.get("requires", []):
			if not eras.has(r):
				errors.append("eras.%s: requires unknown era '%s'" % [id, r])
	if bases != 1:
		errors.append("eras: expected exactly one base era, found %d" % bases)

func _check_row_eras_and_src(loader: DataLoader, eras: Dictionary) -> void:
	for t in loader.all_tables:
		for id in loader.all_tables[t]:
			var row: Dictionary = loader.all_tables[t][id]
			if row.has("era") and not eras.has(row["era"]):
				errors.append("%s.%s: unknown era '%s'" % [t, id, row["era"]])
			if row.has("era_until") and not eras.has(row["era_until"]):
				errors.append("%s.%s: unknown era_until '%s'" % [t, id, row["era_until"]])
			if row.has("src") and not (row["src"] in SRC_TAGS):
				warnings.append("%s.%s: unknown src '%s'" % [t, id, row["src"]])
			# era 與 src 的分工（M3a 審查修正；M3A_PLAN 0.2）：era = 這個東西在哪個版本已經存在（決定世界裡有沒有它），
			# src = 這一列的細節（數字、名單）出處。base era 的列標 src "later" 表示「1.0A 就有，但細節借用後期版」，
			# 必須在 src_note 說明 1.0A 存在的依據與借了哪些後期數字，否則 era 篩選就失去意義。
			if str(row.get("src", "")) == "later" and eras.get(str(row.get("era", "")), {}).get("base", false) \
					and str(row.get("src_note", "")).strip_edges() == "":
				errors.append("%s.%s: era %s with src later needs a src_note (1.0A 依據 + 借用的後期細節)" % [t, id, row.get("era", "")])
	for rid in loader.all_maps:
		var era: String = loader.all_maps[rid].get("era", "")
		if not eras.has(era):
			errors.append("maps/%s: unknown era '%s'" % [rid, era])
		if not loader.all_tables.get("regions", {}).has(rid):
			errors.append("maps/%s: no matching row in regions.json" % rid)
	for era_id in loader.patches:
		if not eras.has(era_id):
			errors.append("patches/%s: unknown era" % era_id)
	# 出口層級的 era（WORLD_2001 §6.2）：必須是存在的 era id
	for rid in loader.all_maps:
		var rooms: Variant = loader.all_maps[rid].get("rooms", [])
		if not (rooms is Array):
			continue
		for room in rooms:
			if not (room is Dictionary) or not (room.get("exits") is Array):
				continue
			for ex in room["exits"]:
				if not (ex is Dictionary):
					continue
				for f in ["era", "era_until"]:
					if ex.has(f) and not eras.has(str(ex[f])):
						errors.append("maps/%s.%s: exit %s has unknown %s '%s'" % [rid, room.get("id", "?"), ex.get("dir", "?"), f, str(ex[f])])

func _check_requires(loader: DataLoader) -> void:
	for t in loader.all_tables:
		if t == "eras":
			continue   # eras.requires 是 era id 清單，不是條件
		for id in loader.all_tables[t]:
			var row: Dictionary = loader.all_tables[t][id]
			for field in REQUIRE_FIELDS:
				for cond in row.get(field, []):
					if not (cond is Dictionary) or not (cond.get("type", "") in DataSchema.REQUIRE_TYPES):
						errors.append("%s.%s.%s: unknown requires type %s" % [t, id, field, str(cond)])

func _check_rule_profiles(profiles: Dictionary) -> void:
	if profiles.is_empty():
		errors.append("rule_profiles: no presets")
	for id in profiles:
		var rules: Dictionary = profiles[id].get("rules", {})
		for key in DataSchema.RULE_DEFAULTS:
			if not rules.has(key):
				errors.append("rule_profiles.%s: missing switch '%s'" % [id, key])
		for key in rules:
			if not DataSchema.RULE_DEFAULTS.has(key):
				errors.append("rule_profiles.%s: unknown switch '%s'" % [id, key])
			elif DataSchema.RULE_ENUMS.has(key) and not (rules[key] in DataSchema.RULE_ENUMS[key]):
				errors.append("rule_profiles.%s: %s='%s' not in %s" % [id, key, rules[key], DataSchema.RULE_ENUMS[key]])
			elif typeof(rules[key]) != typeof(DataSchema.RULE_DEFAULTS[key]):
				errors.append("rule_profiles.%s: %s has wrong type" % [id, key])

func _check_server_options(loader: DataLoader, eras: Dictionary) -> void:
	var so := loader.server_options_default
	if so.is_empty():
		errors.append("server_options.default.json missing or empty")
		return
	for e in DataLoader.validate_enabled_eras(eras, so.get("enabled_eras", [])):
		errors.append("server_options.enabled_eras: " + e)
	var rp: Dictionary = so.get("rule_profile", {})
	if not loader.all_tables.get("rule_profiles", {}).has(rp.get("preset", "")):
		errors.append("server_options.rule_profile.preset '%s' not found" % rp.get("preset", ""))
	for k in rp.get("overrides", {}):
		if not DataSchema.RULE_DEFAULTS.has(k):
			errors.append("server_options.rule_profile.overrides: unknown switch '%s'" % k)
	for s in so.get("sects_enabled", []):
		if not loader.all_tables.get("sects", {}).has(s):
			errors.append("server_options.sects_enabled: unknown sect '%s'" % s)
	if not (so.get("host_offline_policy", "") in HOST_OFFLINE_POLICIES):
		errors.append("server_options.host_offline_policy invalid")
	if int(so.get("max_players", 0)) < 1 or int(so.get("max_players", 0)) > 250:
		errors.append("server_options.max_players out of range")
	if so.has("stagecoach_enabled") and typeof(so["stagecoach_enabled"]) != TYPE_BOOL:
		errors.append("server_options.stagecoach_enabled must be a bool")
	# M2_PLAN 4.7.1
	if not (so.get("pk_mode", "") in PK_MODES):
		errors.append("server_options.pk_mode '%s' not in %s" % [so.get("pk_mode", ""), PK_MODES])
	for k in M2_BOOL_OPTIONS:
		if typeof(so.get(k)) != TYPE_BOOL:
			errors.append("server_options.%s must be a bool" % k)
	# 查看偵察（M3 小範圍）：缺 key = 預設 true；有就必須是 bool
	if so.has("scout_enabled") and typeof(so["scout_enabled"]) != TYPE_BOOL:
		errors.append("server_options.scout_enabled must be a bool")
	for k in M2_INT_OPTIONS:
		if typeof(so.get(k)) != TYPE_INT or int(so[k]) < int(M2_INT_OPTIONS[k][0]) or int(so[k]) > int(M2_INT_OPTIONS[k][1]):
			errors.append("server_options.%s must be an int in %s" % [k, str(M2_INT_OPTIONS[k])])
	var admins: Variant = so.get("admin_identities")
	if not (admins is Array):
		errors.append("server_options.admin_identities must be an array")
	else:
		for a in admins:
			if typeof(a) != TYPE_STRING:
				errors.append("server_options.admin_identities: entries must be strings")

func _check_region_maps(loader: DataLoader) -> void:
	for id in loader.all_tables.get("regions", {}):
		var path: String = loader.all_tables["regions"][id].get("map", "")
		if path == "":
			continue
		if not FileAccess.file_exists(path):
			errors.append("regions.%s: map file missing %s" % [id, path])
		elif not loader.all_maps.has(id):
			errors.append("regions.%s: map %s did not load as region_id '%s'" % [id, path, id])

## data/art.json（戰鬥美術，純表現層）：預設資料夾一定要有；測試用的資料夾沒有就略過
func _check_art(dir: String, loader: DataLoader) -> void:
	var path := dir.path_join("art.json")
	if not FileAccess.file_exists(path):
		if dir == "res://data":
			errors.append("art.json missing")
		return
	var art: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (art is Dictionary):
		errors.append("art.json: not a JSON object")
		return
	for e in DataSchema.check_art(art, loader.all_tables):
		errors.append(e)
	# 有標 placeholder:false 的條目要真的有正式圖（import_art.py 會維護這個旗標）
	for key in art.get("units", {}):
		var u: Dictionary = art["units"][key]
		if u.has("sprite") and u.get("placeholder", true) == false 				and not FileAccess.file_exists("res://assets/art/units/unit_%s_idle.png" % u["sprite"]):
			warnings.append("art.units.%s: placeholder=false but assets/art/units/unit_%s_idle.png is missing (run tools/import_art.py)" % [key, u["sprite"]])

func _check_nested_requires(loader: DataLoader) -> void:
	# 頂層條件欄位：type 已由 _check_requires 檢查，這裡補欄位完整性
	for t in loader.all_tables:
		if t == "eras":
			continue
		for id in loader.all_tables[t]:
			var row: Dictionary = loader.all_tables[t][id]
			for field in REQUIRE_FIELDS:
				for e in check_conditions(row.get(field, []), "%s.%s.%s" % [t, id, field]):
					if not ("unknown requires type" in e) or ".any_of[" in e:
						errors.append(e)
	# 巢狀條件：npcs.fight.requires、maps rooms[].requires
	for id in loader.all_tables.get("npcs", {}):
		# fight、M3A_PLAN 6.8 guide、6.9 trial、meal（選填 requires）
		for sub in ["fight", "guide", "trial", "meal"]:
			var node: Variant = loader.all_tables["npcs"][id].get(sub)
			if node is Dictionary and node.has("requires"):
				errors.append_array(check_conditions(node.get("requires", []), "npcs.%s.%s.requires" % [id, sub]))
	# M3A_PLAN 3.1：sects.hostile_entry[].if
	for id in loader.all_tables.get("sects", {}):
		var he: Variant = loader.all_tables["sects"][id].get("hostile_entry", [])
		if he is Array:
			for i in (he as Array).size():
				if he[i] is Dictionary:
					errors.append_array(check_conditions(he[i].get("if", []), "sects.%s.hostile_entry[%d].if" % [id, i]))
	for rid in loader.all_maps:
		var rooms: Variant = loader.all_maps[rid].get("rooms", [])
		if not (rooms is Array):
			continue
		for room in rooms:
			if room is Dictionary:
				errors.append_array(check_conditions(room.get("requires", []),
					"maps/%s.%s.requires" % [rid, room.get("id", "?")]))

# ============================================================================
# M1 內容檢查（M1_PLAN 3.11.15）。全部是靜態函式，輸入為 DataLoader.activate() 的生效視圖
# （table -> {id -> row}，另含 "maps": {region_id -> map}），回傳錯誤字串清單。
# tests/unit/test_data_content.gd 也直接呼叫這些函式。
# ============================================================================

const START_ROOM := "xx_square"
const DIR_REVERSE := { "N": "S", "S": "N", "E": "W", "W": "E", "NE": "SW", "SW": "NE", "NW": "SE", "SE": "NW",
	"U": "D", "D": "U", "IN": "OUT", "OUT": "IN" }
## M3B_PLAN §4.4：＋MINE FORGE CAST LOOM TANNERY KILN HUNT（與 DataSchema.FEATURES 相同）
const ROOM_FEATURES := ["FIELD", "WOOD", "WATER", "STOVE", "MINE", "FORGE", "CAST", "LOOM", "TANNERY", "KILN", "HUNT"]
## M3a 加 BETRAY JAIL TRIAL GUIDE（M3A_PLAN 6.12；與 Protocol.NPC_SERVICES 相同，GUARD 不是服務而是 NPC kind）
const NPC_SERVICES := ["SHOP", "TEACH", "INN", "RESPAWN", "TRAVEL", "JOIN", "QUEST", "MEAL", "FIGHT",
	"BETRAY", "JAIL", "TRIAL", "GUIDE",
	# M3B_PLAN §4.8（與 DataSchema.NPC_SERVICES 相同）
	"BANK", "ESCORT", "ORG", "RANK",
	# M3D_PLAN §8.4（WP-LAW）
	"BOARD", "LICENSE", "CLEANSE", "TOURNEY"]
const NPC_KINDS := ["FUNC", "MASTER", "SHOP", "QUEST", "STORY", "GUARD", "EVIL_NPC"]
const ALIGNMENTS := ["GOOD", "NEUTRAL", "EVIL"]
const REGION_TYPES := ["CITY", "WILD", "SECT", "DUNGEON"]
const ITEM_TABS := ["WEAPON", "ARMOR", "OTHER", "MATERIAL"]
const ITEM_SLOTS := ["WEAPON", "ARMOR", "HEAD", "NECK", "WRIST", "CLOAK", "RING", "BOOTS", ""]   # M3C_PLAN §8（Protocol.SLOTS＋空）
const WEAPON_TYPES := ["FIST", "BLADE", "SWORD", "STAFF", "WHIP", "SPEAR"]
const ART_CATEGORIES := ["FIST", "BLADE", "SWORD", "STAFF", "WHIP", "SPEAR", "STAB", "INNER", "LIGHTNESS", "HIDDEN",
	"POISON", "MEDIC", "FORMATION", "ACUPOINT"]
## M3A_PLAN 3.4、5.3
const MOVE_AOES := ["SINGLE", "CROSS", "CROSS_L", "LINE", "FAN", "AROUND"]
const ART_TIERS := ["BASIC", "ADVANCED", "SPECIAL", "QUEST"]
## 3.4 的類別專屬欄位：欄位 -> 必須搭配的 category
const ART_CATEGORY_FIELDS := { "formation": "FORMATION", "inner": "INNER", "poison": "POISON", "medic": "MEDIC", "hidden": "HIDDEN" }
const MOVE_STATUS_CHANCE_MAX := 0.35
## M3A_PLAN 3.4「範圍招式（非 SINGLE）威力 × 0.75 再取整」（M3a 審查 B4：以前沒有檢查）。
## 單體參考值＝少林／華山入門武功各解鎖段的最高威力（1–29 級 24、30–59 級 34、60 級起 46）；入門（BASIC）武功的範圍招式
## 威力不得超過 roundi(參考值 × 0.75) = 18／26／35
const AOE_POWER_MULT := 0.75
const BASIC_SINGLE_REF := [[60, 46], [30, 34], [1, 24]]
const ATTR_IDS := ["str", "guts", "wit", "luck", "cal", "agi", "con"]
const VITAL_IDS := ["jing", "qi", "shen", "neili", "food", "water"]
const EFFECT_TYPES := ["restore", "attr", "smoke", "hidden", "cure",   # hidden、cure：M3A_PLAN 3.9
	"FLEE_ANYWHERE", "LIGHT", "LIANDU", "SUMMON"]   # M3D_PLAN §8.4（DataSchema.M3D_EFFECT_TYPES）
const QUEST_STEP_TYPES := ["KILL", "DELIVER", "TALK", "REACH"]
const MONSTER_KINDS := ["MONSTER", "ELITE", "BOSS", "EVIL_NPC"]
const MONSTER_AIS := ["melee_basic", "coward"]
const MONSTER_REQUIRED_SKILLS := ["basic_dodge", "basic_parry", "basic_inner"]
const SECT_SKILL_EFFECTS := ["DEFENSE", "RESIST", "EVADE", "RECOVER", "COUNTER", "REST", "PARALYZE", "CONFUSE",
	"DISTRACT", "HEAVY", "POISON_FANG"]
const BASIC_CURVES := ["CUBIC", "QUARTIC", "LITERACY"]
const SHICHEN := ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]

## 3.8 全部非 UI-only 的固定事件 key（招式 flavor 與 talk_* 由資料推得，另外檢查）
## ＋ 3.7 的 err_<reason>（去掉帶冒號者與 drop:，另加 err_bad_args）＋ M0 既有 key
const REQUIRED_TEMPLATE_KEYS := [
	# 3.8.1
	"char_rolled", "char_created", "char_deleted", "char_entered", "look_room", "char_left", "room_enter", "room_leave",
	"travel", "night_falls", "day_breaks", "hungry", "thirsty", "starving", "parched", "birthday",
	# 3.8.2
	"buy", "sell", "learn", "skill_up", "self_study", "life_learn", "sect_join", "inn_rest", "respawn_set", "meal",
	# 3.8.3
	"item_use", "item_gain", "item_lost", "item_drop", "item_spoiled", "money_gain", "equip", "unequip",
	"overdose", "meat_vow_broken", "wine_vow_broken", "meditate", "cultivate", "exert",
	"work_ok_life_farming", "work_ok_life_woodcut", "work_ok_life_fishing", "work_ok_life_cooking",
	"work_fail_life_farming", "work_fail_life_woodcut", "work_fail_life_fishing", "work_fail_life_cooking",
	"quest_accept", "quest_progress", "quest_complete", "quest_abandon", "reward",
	# 3.8.4
	"battle_move", "atk_fist", "atk_blade", "atk_sword", "atk_staff", "atk_whip", "atk_spear",
	"battle_miss", "battle_crit", "battle_counter", "battle_defend", "battle_rest", "battle_equip", "battle_flee",
	"battle_timeout", "battle_proc_DEFENSE", "battle_proc_RECOVER", "battle_status_on", "battle_status_off",
	"battle_wound_tick", "battle_kill", "battle_death",
	# 3.8.5
	"encounter", "fight_start", "battle_victory", "battle_victory_fled", "battle_defeat", "battle_fled", "battle_reward",
	"death_strict", "death_standard", "death_standard_safe", "death_casual", "respawn", "corpse_looted",
	"corpse_expired",
	# WORLD_2001 §7、§10
	"relocated", "respawn_reset", "err_stagecoach_disabled",
	# M0 既有
	"chat", "pong", "player_join", "player_leave", "roster",
	# 3.7
	"err_bad_args", "err_unknown_intent", "err_unexpected_arg", "err_empty_text", "err_text_too_long",
	"err_bad_channel",
	"err_no_character", "err_no_roll", "err_bad_name", "err_name_taken", "err_too_many_chars", "err_bad_alloc",
	"err_no_such_char", "err_confirm_mismatch", "err_char_active",
	"err_in_battle", "err_busy", "err_overweight", "err_inventory_full", "err_money_cap",
	"err_no_exit", "err_room_locked", "err_no_route",
	"err_not_here", "err_no_service", "err_closed_night", "err_not_enough_money", "err_not_meal_time",
	"err_already_ate",
	"err_no_item", "err_not_usable", "err_not_equippable", "err_not_sellable", "err_not_droppable",
	"err_not_taught", "err_cap_master", "err_cap_xp", "err_cap_sect_skill", "err_cap_arts16", "err_need_self_study", "err_not_known",
	"err_already_known", "err_not_enough_lp", "err_not_enough_jing", "err_not_enough_neili", "err_not_enough_shen",
	"err_already_in_sect",
	"err_req_morality_min", "err_req_morality_max", "err_req_sect", "err_req_no_sect", "err_req_not_enemy_of",
	"err_req_gender", "err_req_attr_min", "err_req_skill_min", "err_req_combat_xp_min", "err_req_pk_max",
	"err_req_quest_flag", "err_req_quest_done", "err_req_killing_intent_max", "err_req_era_enabled",
	"err_req_sect_enabled", "err_req_rule",
	"err_no_inner", "err_nothing_to_do",
	"err_no_feature", "err_no_tool", "err_no_recipe", "err_recipe_level", "err_no_ingredients",
	"err_quest_unknown", "err_quest_active", "err_quest_done", "err_quest_not_active", "err_quest_incomplete",
	"err_quest_full",
	"err_corpse_not_found", "err_corpse_not_yours",
	"err_battle_not_found", "err_battle_over", "err_not_ready", "err_bad_cmd", "err_out_of_range", "err_occupied",
	"err_no_target", "err_art_unknown", "err_move_locked", "err_need_weapon", "err_aoe_not_supported",
	"err_not_on_escape", "err_status_blocked", "err_battle_not_enough_jing",
	# M2_PLAN 4.3（新原因碼）
	"err_bad_target", "err_target_not_here", "err_target_busy", "err_target_offline", "err_target_in_party",
	"err_target_not_in_party", "err_already_in_party", "err_not_in_party", "err_not_leader", "err_party_full",
	"err_invite_pending", "err_invite_refused", "err_no_invite", "err_join_not_allowed", "err_battle_full",
	"err_pk_disabled", "err_pk_challenge_only", "err_pk_not_allowed_here", "err_target_newbie_protected",
	"err_challenge_pending", "err_challenge_refused", "err_challenge_cooldown", "err_invite_cooldown", "err_no_challenge", "err_corpse_protected",
	"err_not_corpse_owner", "err_corpse_auth_full", "err_no_such_player", "err_thirsty", "err_no_sect",
	"err_no_guild", "err_no_party_chat", "err_not_admin", "err_chat_too_fast", "err_no_such_recipient",
	"err_mailbox_full", "err_mail_not_found", "err_mail_too_fast", "err_bad_option", "err_passport_bad_format",
	"err_passport_wrong_world", "err_passport_wrong_identity", "err_passport_bad_sig", "err_passport_not_needed",
	"err_passport_name_taken",
	"err_foreign_disabled",
	# M2_PLAN 4.4.1
	"party_invite_sent", "party_invited", "party_declined", "party_invite_expired", "party_joined", "party_left",
	"party_kicked", "party_leader", "party_disbanded", "battle_join",
	# 4.4.2
	"challenge_sent", "challenge_request", "challenge_declined", "challenge_expired", "challenge_start",
	"force_pk_start", "pk_kill", "pk_value_up", "pk_wanted", "morality_change", "killing_intent_change",
	"guard_attack", "pref_changed", "corpse_authorized", "corpse_auth_granted", "corpse_looted_other",
	"corpse_looted_by", "corpse_public",
	# 4.4.3
	"chat_say", "chat_sect", "chat_party", "chat_whisper", "chat_rumor", "chat_gm", "mail_sent", "mail_arrived",
	"mail_waiting",
	# 4.4.4
	"server_option_changed", "player_kicked", "host_closing", "passport_restored",
	# 查看偵察（docs/GDD.md §5.10【設計提案・非原作】）
	"scout_found", "scout_none", "scout_busy", "scout_expired", "scout_declined", "scout_engage",
	"err_scout_gone", "err_scout_expired", "err_scout_dead",
]

## 3.8 的 UI-only key：不得有模板（TextRenderer 一律不顯示）；M2_PLAN 4.4 另加 5 個
const UI_ONLY_KEYS := ["npc_menu", "shop_list", "teach_list", "battle_gauges", "battle_await", "battle_end",
	"battle_unit_join", "mail_list", "server_options", "world_info_changed", "passport", "scout_offer", "scout_closed"]

## REQUIRED_TEMPLATE_KEYS 中變體不只 self 的 key（3.8 的「變體」欄）；沒列出的 key 只需要 self
const TEMPLATE_VARIANTS := {
	"char_entered": ["self", "other"], "char_left": ["other"], "room_enter": ["other"], "room_leave": ["other"],
	"night_falls": ["other"], "day_breaks": ["other"], "sect_join": ["self", "other"],
	"battle_move": ["self", "other"],
	"atk_fist": ["self", "target", "other"], "atk_blade": ["self", "target", "other"],
	"atk_sword": ["self", "target", "other"], "atk_staff": ["self", "target", "other"],
	"atk_whip": ["self", "target", "other"], "atk_spear": ["self", "target", "other"],
	"battle_miss": ["self", "target", "other"], "battle_crit": ["self", "target", "other"],
	"battle_counter": ["self", "target", "other"], "battle_defend": ["self", "other"],
	"battle_rest": ["self", "other"], "battle_equip": ["self", "other"], "battle_flee": ["self", "other"],
	"battle_timeout": ["self", "other"], "battle_proc_DEFENSE": ["self", "other"],
	"battle_proc_RECOVER": ["self", "other"], "battle_status_on": ["self", "other"],
	"battle_status_off": ["self", "other"], "battle_wound_tick": ["self", "other"],
	"battle_kill": ["other"], "battle_death": ["self", "other"],
	"chat": ["self", "other"], "player_join": ["self", "other"], "player_leave": ["other"], "roster": ["other"],
	# M2_PLAN 4.4
	"party_joined": ["self", "other"], "party_left": ["self", "other"], "party_kicked": ["self", "other"],
	"party_leader": ["self", "other"], "battle_join": ["self", "other"],
	"challenge_start": ["self", "target", "other"], "force_pk_start": ["self", "target", "other"],
	"pk_kill": ["self", "target", "other"],
	"chat_say": ["self", "other"], "chat_sect": ["self", "other"], "chat_party": ["self", "other"],
	"chat_whisper": ["self", "other"], "chat_rumor": ["self", "other"], "chat_gm": ["self", "other"],
	"server_option_changed": ["self", "other"], "player_kicked": ["other"], "host_closing": ["self", "other"],
}
const FLAVOR_VARIANTS := ["self", "target", "other"]

## 條件陣列的格式檢查（type 合法、必要欄位齊全）
static func check_conditions(conds: Variant, label: String, depth := 0) -> PackedStringArray:
	var errs := PackedStringArray()
	if not (conds is Array):
		errs.append("%s: conditions must be an array" % label)
		return errs
	for c in conds:
		if not (c is Dictionary) or not (c.get("type", "") in DataSchema.REQUIRE_TYPES):
			errs.append("%s: unknown requires type %s" % [label, str(c)])
			continue
		for f in DataSchema.REQUIRE_FIELDS_BY_TYPE.get(c["type"], []):
			if not c.has(f):
				errs.append("%s: condition %s missing field '%s'" % [label, c["type"], f])
		# M3A_PLAN 3.7：any_of 的內層條件逐一檢查（最多 2 層）；hour_in 的時辰
		if c["type"] == "any_of" and c.has("options"):
			var opts: Variant = c["options"]
			if not (opts is Array) or (opts as Array).is_empty():
				errs.append("%s: any_of.options must be a non-empty array of arrays" % label)
			elif depth >= 1:
				errs.append("%s: any_of nested too deep (max 2 levels)" % label)
			else:
				for i in (opts as Array).size():
					errs.append_array(check_conditions(opts[i], "%s.any_of[%d]" % [label, i], depth + 1))
		elif c["type"] == "hour_in" and c.has("hours"):
			if not (c["hours"] is Array) or (c["hours"] as Array).is_empty():
				errs.append("%s: hour_in.hours must be a non-empty array" % label)
			else:
				for h in c["hours"]:
					if not (str(h) in SHICHEN):
						errs.append("%s: hour_in '%s' is not a shichen" % [label, str(h)])
	return errs

## room_id -> { "room": Dictionary, "region": String }
static func room_index(view: Dictionary) -> Dictionary:
	var idx := {}
	var maps: Dictionary = view.get("maps", {})
	var rids: Array = maps.keys()
	rids.sort()
	for rid in rids:
		var rooms: Variant = maps[rid].get("rooms", [])
		if not (rooms is Array):
			continue
		for room in rooms:
			if room is Dictionary and str(room.get("id", "")) != "" and not idx.has(room["id"]):
				idx[room["id"]] = { "room": room, "region": rid }
	return idx

## 房間圖的鄰接，room_id -> [room_id]。預設只算步行出口（WORLD_2001 §9.1 lint 1）；
## include_travel = true 時另外加上驛站馬車路線（伺服器選項，非原作）
static func room_graph(view: Dictionary, include_travel := false) -> Dictionary:
	var idx := room_index(view)
	var g := {}
	for rid in idx:
		var nbrs: Array = []
		for ex in idx[rid]["room"].get("exits", []):
			if ex is Dictionary and idx.has(ex.get("to", "")):
				nbrs.append(ex["to"])
		g[rid] = nbrs
	if not include_travel:
		return g
	for nid in view.get("npcs", {}):
		var npc: Dictionary = view["npcs"][nid]
		if not ("TRAVEL" in npc.get("services", [])) or not g.has(npc.get("room", "")):
			continue
		for r in npc.get("travel", []):
			if r is Dictionary and idx.has(r.get("to_room", "")):
				g[npc["room"]].append(r["to_room"])
	return g

## 從 start 出發「走路」BFS 可到達的房間 {room_id: true}
static func reachable_rooms(view: Dictionary, start: String) -> Dictionary:
	return _bfs(room_graph(view), start, "")["seen"]

## 最短步行路徑（房間 id 陣列，含起點與終點）；不可達回 []
static func find_path(view: Dictionary, from: String, to: String) -> Array:
	var r := _bfs(room_graph(view), from, to)
	if not r["seen"].has(to):
		return []
	var path: Array = [to]
	var cur: String = to
	while cur != from:
		cur = r["prev"][cur]
		path.push_front(cur)
	return path

static func _bfs(g: Dictionary, start: String, goal: String) -> Dictionary:
	var seen := {}
	var prev := {}
	if not g.has(start):
		return { "seen": seen, "prev": prev }
	seen[start] = true
	var q: Array = [start]
	while not q.is_empty():
		var cur: String = q.pop_front()
		if cur == goal:
			break
		for n in g[cur]:
			if not seen.has(n):
				seen[n] = true
				prev[n] = cur
				q.append(n)
	return { "seen": seen, "prev": prev }

## 技能 id 屬於哪一種：BASIC / ART / SECT / LIFE / ""（與 SkillBook.kind_of 同一規則）
static func skill_kind(view: Dictionary, skill_id: String) -> String:
	if view.get("basic_skills", {}).has(skill_id):
		return "BASIC"
	if view.get("martial_arts", {}).has(skill_id):
		return "ART"
	for sid in view.get("sects", {}):
		if view["sects"][sid].get("sect_skill", "") == skill_id:
			return "SECT"
	if view.get("life_skills", {}).has(skill_id):
		return "LIFE"
	return ""

static func check_content(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	errs.append_array(_c_maps(view))
	errs.append_array(_c_reachability(view))
	errs.append_array(_c_npc_rooms(view))
	errs.append_array(_c_npc_services(view))
	errs.append_array(_c_masters(view))
	errs.append_array(_c_quests(view))
	errs.append_array(_c_life_skills(view))
	errs.append_array(_c_monsters_and_arts(view))
	errs.append_array(_c_encounters(view))
	errs.append_array(_c_regions(view))
	errs.append_array(_c_templates(view))
	errs.append_array(_c_items(view))
	errs.append_array(_c_misc(view))
	errs.append_array(check_m3a(view))
	errs.append_array(check_story(view))
	errs.append_array(check_m3b(view))
	errs.append_array(check_m3c_npcpk(view))
	errs.append_array(_check_m3c_loot(view))   # M3c WP-LOOT
	errs.append_array(_check_m3c2_pace(view))   # M3c2 WP-PACE
	errs.append_array(_check_m3c2_econ(view))   # M3c2 WP-ECON
	# M3D_PLAN §9.2（WP-LAW Day-0）：每個 WP 在檔尾自己的區塊
	errs.append_array(_check_m3d_law(view))
	errs.append_array(_check_m3d_combat(view))
	errs.append_array(_check_m3d_arts(view))
	errs.append_array(_check_m3d_events(view))
	errs.append_array(_check_m3d_errands(view))
	errs.append_array(_check_0701(view))   # 0.7.0.1
	return errs

# 1. 房間圖格式、id 全域唯一、出口目標存在、雙向性、features 合法
static func _c_maps(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var maps: Dictionary = view.get("maps", {})
	var owner := {}
	for rid in maps:
		var m: Dictionary = maps[rid]
		if not (m.get("rooms") is Array) or m["rooms"].is_empty():
			errs.append("maps/%s: rooms[] missing or empty" % rid)
			continue
		if m.has("tiles") or m.has("legend"):
			errs.append("maps/%s: tile format is not used in M1 (D1)" % rid)
		if typeof(m.get("escape_tiles_hint", 2)) != TYPE_INT or int(m.get("escape_tiles_hint", 2)) < 0:
			errs.append("maps/%s: escape_tiles_hint must be int >= 0" % rid)
		for room in m["rooms"]:
			if not (room is Dictionary):
				errs.append("maps/%s: room is not an object" % rid)
				continue
			var id: String = str(room.get("id", ""))
			if id == "":
				errs.append("maps/%s: room with empty id" % rid)
				continue
			if owner.has(id):
				errs.append("maps/%s: duplicate room id '%s' (also in %s)" % [rid, id, owner[id]])
				continue
			owner[id] = rid
			for f in ["name", "desc"]:
				if str(room.get(f, "")) == "":
					errs.append("maps/%s.%s: missing %s" % [rid, id, f])
			if not (room.get("exits") is Array):
				errs.append("maps/%s.%s: exits[] missing" % [rid, id])
			if not (room.get("npcs", []) is Array):
				errs.append("maps/%s.%s: npcs must be an array" % [rid, id])
			if not (room.get("features", []) is Array):
				errs.append("maps/%s.%s: features must be an array" % [rid, id])
			else:
				for f in room.get("features", []):
					if not (f in ROOM_FEATURES):
						errs.append("maps/%s.%s: bad feature '%s'" % [rid, id, f])
			if room.has("encounter") and not (room["encounter"] is Dictionary):
				errs.append("maps/%s.%s: encounter must be an object" % [rid, id])
	var idx := room_index(view)
	for id in idx:
		var room: Dictionary = idx[id]["room"]
		var exits: Variant = room.get("exits", [])
		if not (exits is Array):
			continue
		var dirs := {}
		for ex in exits:
			if not (ex is Dictionary):
				errs.append("room %s: exit is not an object" % id)
				continue
			var d: String = str(ex.get("dir", ""))
			var to: String = str(ex.get("to", ""))
			if not DIR_REVERSE.has(d):
				errs.append("room %s: bad exit dir '%s'" % [id, d])
				continue
			if dirs.has(d):
				errs.append("room %s: duplicate exit dir %s" % [id, d])
			dirs[d] = true
			if not idx.has(to):
				errs.append("room %s: exit %s -> unknown room '%s'" % [id, d, to])
				continue
			if ex.get("oneway", false):
				continue
			var back := false
			for ex2 in idx[to]["room"].get("exits", []):
				if ex2 is Dictionary and ex2.get("dir", "") == DIR_REVERSE[d] and ex2.get("to", "") == id:
					back = true
			if not back:
				errs.append("room %s: exit %s -> %s has no reverse exit %s" % [id, d, to, DIR_REVERSE[d]])
	return errs

# 2. 純步行可達性（WORLD_2001 §9.1 lint 1–3）：
#    從 xx_square 走得到每一個房間（沒有孤立房間）；出生城彼此走得到；
#    每個 SECT／DUNGEON 地區至少有一間房從每座出生城走得到；DELIVER 目標 NPC 從給任務的 NPC 走得到
static func _c_reachability(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var idx := room_index(view)
	if not idx.has(START_ROOM):
		errs.append("start room '%s' missing" % START_ROOM)
		return errs
	var g := room_graph(view)
	var seen: Dictionary = _bfs(g, START_ROOM, "")["seen"]
	var ids: Array = idx.keys()
	ids.sort()
	for id in ids:
		if not seen.has(id):
			errs.append("room %s (%s) unreachable from %s" % [id, idx[id]["region"], START_ROOM])
	var regions: Dictionary = view.get("regions", {})
	var births := birth_rooms(view)
	for br in births:
		if not idx.has(br):
			continue
		var from_birth: Dictionary = _bfs(g, br, "")["seen"]
		for other in births:
			if idx.has(other) and not from_birth.has(other):
				errs.append("birth room %s cannot walk to birth room %s" % [br, other])
		var rids: Array = regions.keys()
		rids.sort()
		for rid in rids:
			if not (regions[rid].get("type", "") in ["SECT", "DUNGEON"]):
				continue
			var ok := false
			for id in idx:
				if idx[id]["region"] == rid and from_birth.has(id):
					ok = true
					break
			if not ok:
				errs.append("%s region %s cannot be reached on foot from birth room %s" % [regions[rid].get("type", ""), rid, br])
	var npc_rooms := {}
	for nid in view.get("npcs", {}):
		npc_rooms[nid] = str(view["npcs"][nid].get("room", ""))
	for qid in view.get("quests", {}):
		var q: Dictionary = view["quests"][qid]
		var giver_room: String = npc_rooms.get(str(q.get("giver", "")), "")
		if not idx.has(giver_room):
			continue
		var reach: Dictionary = {}
		for st in q.get("steps", []):
			if not (st is Dictionary) or st.get("type", "") != "DELIVER":
				continue
			var target_room: String = npc_rooms.get(str(st.get("target", "")), "")
			if not idx.has(target_room):
				continue
			if reach.is_empty():
				reach = _bfs(g, giver_room, "")["seen"]
			if not reach.has(target_room):
				errs.append("quests.%s: DELIVER target %s (%s) not reachable on foot from giver room %s" % [qid, st.get("target", ""), target_room, giver_room])
	return errs

## 生效視圖裡每座可出生城市的 birth_room（依地區 id 排序）
static func birth_rooms(view: Dictionary) -> Array:
	var out: Array = []
	var regions: Dictionary = view.get("regions", {})
	var rids: Array = regions.keys()
	rids.sort()
	for rid in rids:
		var r: Dictionary = regions[rid]
		if r.get("birth_allowed", false) and str(r.get("birth_room", "")) != "":
			out.append(str(r["birth_room"]))
	return out

# ============================================================================
# WORLD_2001 §1.4 新手安全規則（lint 印 warning；tests/unit/test_data_content.gd 用 assert）
# 沿著每座出生城到每個門派山門、以及出生城彼此之間的最短步行路線檢查：
#  2. 相鄰休息點之間：難纏怪（野狼、山豬、山賊）期望 ≤ 0.15 場、山豬 ≤ 0.10、山賊 ≤ 0.015
#  3. 路線上緊接在 CITY／SECT 房間前後的房間只能有 m_rabbit、m_bigrabbit
#  4. 離任何 CITY／SECT 房間 2 步以內不放 m_bandit
#  5. 路線上的怪 combat_xp_ref ≤ 3000，達到 3000 的權重 ≤ 10
#  6. 路線上遇敵率 ≤ 0.15（舊有練功點除外）
# 休息點 = CITY／SECT 地區的房間，以及有 INN 服務 NPC、不遇敵的房間（茶棚、綠洲）。
# ============================================================================
const HARD_MONSTERS := ["m_wolf", "m_boar", "m_bandit"]
const NEWBIE_EDGE_MONSTERS := ["m_rabbit", "m_bigrabbit"]
const NEWBIE_HARD_MAX := 0.15
const NEWBIE_BOAR_MAX := 0.10
const NEWBIE_BANDIT_MAX := 0.015
const NEWBIE_XP_REF_MAX := 3000
const NEWBIE_STRONG_W_MAX := 10
const NEWBIE_RATE_MAX := 0.15
## 死路練功點（M3A_PLAN 2.3 規則 6：新的只限 wd_woods、em_bandit，≤ 0.30）
const NEWBIE_RATE_EXEMPT := ["xw_grass", "xw_wood", "xw_hill", "dlw_forest", "wd_woods", "em_bandit",
	# M3B_PLAN §3.4 #4：丐幫左方空地（原作 20–29 級練功點，死路，≤ 0.30）
	"jcn_kongdi"]
## M3B_PLAN §3.4 #2、§9.5 #8：京城門口的新手怪（乞丐頭子、不良少年，combat_xp_ref ≤ 500）可放在緊鄰京城城門的房間
const NEWBIE_EDGE_REGION_EXTRA := { "jingcheng_wild": ["m_jc_qigaitou", "m_jc_buliang"],
	"jingcheng_north": ["m_jc_qigaitou", "m_jc_buliang"] }
const NEWBIE_RATE_EXEMPT_MAX := 0.30
const EPS := 0.000001

## 門派地區的山門：地區裡第一間有出口通往地區外的房間（依房間順序）
static func sect_gate_rooms(view: Dictionary) -> Array:
	var out: Array = []
	var maps: Dictionary = view.get("maps", {})
	var idx := room_index(view)
	var regions: Dictionary = view.get("regions", {})
	var rids: Array = regions.keys()
	rids.sort()
	for rid in rids:
		if regions[rid].get("type", "") != "SECT" or not maps.has(rid):
			continue
		for room in maps[rid].get("rooms", []):
			var found := false
			for ex in room.get("exits", []):
				var to := str(ex.get("to", ""))
				if idx.has(to) and idx[to]["region"] != rid:
					found = true
			if found:
				out.append(str(room["id"]))
				break
	return out

static func is_rest_room(view: Dictionary, idx: Dictionary, room_id: String) -> bool:
	if not idx.has(room_id):
		return false
	var region: Dictionary = view.get("regions", {}).get(idx[room_id]["region"], {})
	if region.get("type", "") in ["CITY", "SECT"]:
		return true
	var room: Dictionary = idx[room_id]["room"]
	var enc: Variant = room.get("encounter")
	if enc is Dictionary and float(enc.get("rate", 0.0)) > 0.0:
		return false
	for nid in room.get("npcs", []):
		if "INN" in view.get("npcs", {}).get(nid, {}).get("services", []):
			return true
	return false

## §1.4 規則 1：休息點本身，或離休息點只差一步的房間（例如 xw_road 緊鄰西夏東門）
static func is_rest_or_next_to_rest(view: Dictionary, idx: Dictionary, g: Dictionary, room_id: String) -> bool:
	if is_rest_room(view, idx, room_id):
		return true
	for n in g.get(room_id, []):
		if is_rest_room(view, idx, n):
			return true
	return false

## 一間房的遇敵期望：{ total, hard, boar, bandit }（rate × 權重比例）
static func room_encounter_expectation(room: Dictionary) -> Dictionary:
	var out := { "total": 0.0, "hard": 0.0, "boar": 0.0, "bandit": 0.0 }
	var enc: Variant = room.get("encounter")
	if not (enc is Dictionary):
		return out
	var rate := float(enc.get("rate", 0.0))
	var wsum := 0
	for e in enc.get("table", []):
		if e is Dictionary:
			wsum += int(e.get("w", 0))
	if wsum <= 0 or rate <= 0.0:
		return out
	out["total"] = rate
	for e in enc.get("table", []):
		if not (e is Dictionary):
			continue
		var p := rate * float(int(e.get("w", 0))) / float(wsum)
		var mid := str(e.get("monster", ""))
		if mid in HARD_MONSTERS:
			out["hard"] += p
		if mid == "m_boar":
			out["boar"] += p
		if mid == "m_bandit":
			out["bandit"] += p
	return out

## 路徑上（不含起點與終點房間）的遇敵期望加總
static func path_expectation(view: Dictionary, path: Array) -> Dictionary:
	var idx := room_index(view)
	var out := { "total": 0.0, "hard": 0.0, "boar": 0.0, "bandit": 0.0 }
	for i in range(1, path.size() - 1):
		if not idx.has(path[i]):
			continue
		var e := room_encounter_expectation(idx[path[i]]["room"])
		for k in out:
			out[k] += e[k]
	return out

## 休息點之間一段路的遇敵期望：段內不是休息點本身的房間都算（「離休息點一步」的分段點也算進去）
static func segment_expectation(view: Dictionary, idx: Dictionary, seg: Array) -> Dictionary:
	var out := { "total": 0.0, "hard": 0.0, "boar": 0.0, "bandit": 0.0 }
	for rid in seg:
		if not idx.has(rid) or is_rest_room(view, idx, rid):
			continue
		var e := room_encounter_expectation(idx[rid]["room"])
		for k in out:
			out[k] += e[k]
	return out

## 新手路線：每座出生城的 birth_room 到每個門派山門、到其他出生城的最短步行路線
static func newbie_routes(view: Dictionary) -> Array:
	var out: Array = []
	var births := birth_rooms(view)
	for br in births:
		for gate in sect_gate_rooms(view):
			out.append(find_path(view, br, gate))
		for other in births:
			if other != br:
				out.append(find_path(view, br, other))
		# STORY_PLAN §2.3、§8.5 #8：新地區（衡山小茶店、雁門關口）
		for target in STORY_ROUTE_TARGETS:
			if room_index(view).has(target):
				out.append(find_path(view, br, target))
	return out

static func check_newbie_routes(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var idx := room_index(view)
	var g := room_graph(view)
	var regions: Dictionary = view.get("regions", {})
	var monsters: Dictionary = view.get("monsters", {})
	var town := {}
	for id in idx:
		if regions.get(idx[id]["region"], {}).get("type", "") in ["CITY", "SECT"]:
			town[id] = true
	# 離 CITY／SECT 房間的步數（多源 BFS）
	var dist := {}
	var q: Array = []
	for id in town:
		dist[id] = 0
		q.append(id)
	while not q.is_empty():
		var cur: String = q.pop_front()
		for n in g.get(cur, []):
			if not dist.has(n):
				dist[n] = int(dist[cur]) + 1
				q.append(n)
	var checked := {}
	for path in newbie_routes(view):
		if path.size() < 2:
			continue
		var label := "%s->%s" % [path[0], path[path.size() - 1]]
		# 規則 2：相鄰休息點之間
		var seg: Array = [path[0]]
		for i in range(1, path.size()):
			seg.append(path[i])
			if is_rest_or_next_to_rest(view, idx, g, path[i]) or i == path.size() - 1:
				var key := "%s|%s" % [seg[0], seg[seg.size() - 1]]
				if seg.size() > 2 and not checked.has(key):
					checked[key] = true
					var e := segment_expectation(view, idx, seg)
					var tag := "%s: segment %s->%s" % [label, seg[0], seg[seg.size() - 1]]
					if float(e["hard"]) > NEWBIE_HARD_MAX + EPS:
						errs.append("%s hard encounters %.3f > %.2f" % [tag, e["hard"], NEWBIE_HARD_MAX])
					if float(e["boar"]) > NEWBIE_BOAR_MAX + EPS:
						errs.append("%s boar %.3f > %.2f" % [tag, e["boar"], NEWBIE_BOAR_MAX])
					if float(e["bandit"]) > NEWBIE_BANDIT_MAX + EPS:
						errs.append("%s bandit %.4f > %.3f" % [tag, e["bandit"], NEWBIE_BANDIT_MAX])
				seg = [path[i]]
		for i in path.size():
			var rid: String = path[i]
			if town.has(rid) or not idx.has(rid):
				continue
			var enc: Variant = idx[rid]["room"].get("encounter")
			if not (enc is Dictionary):
				continue
			var table: Array = enc.get("table", []) if enc.get("table") is Array else []
			var next_to_town: bool = (i > 0 and town.has(path[i - 1])) or (i < path.size() - 1 and town.has(path[i + 1]))
			for e2 in table:
				if not (e2 is Dictionary):
					continue
				var mid := str(e2.get("monster", ""))
				# 規則 3
				if next_to_town and not (mid in NEWBIE_EDGE_MONSTERS) 						and not (mid in NEWBIE_EDGE_REGION_EXTRA.get(str(idx[rid]["region"]), [])):
					errs.append("%s: room %s next to a city/sect gate has %s (only rabbits allowed)" % [label, rid, mid])
				# 規則 4
				if mid == "m_bandit" and int(dist.get(rid, 99)) <= 2:
					errs.append("%s: room %s has m_bandit within %d steps of a city/sect" % [label, rid, int(dist.get(rid, 99))])
				# 規則 5
				var ref := int(monsters.get(mid, {}).get("combat_xp_ref", 0))
				if ref > NEWBIE_XP_REF_MAX:
					errs.append("%s: room %s has %s (combat_xp_ref %d > %d)" % [label, rid, mid, ref, NEWBIE_XP_REF_MAX])
				elif ref >= NEWBIE_XP_REF_MAX and int(e2.get("w", 0)) > NEWBIE_STRONG_W_MAX:
					errs.append("%s: room %s weight of %s is %d > %d" % [label, rid, mid, int(e2.get("w", 0)), NEWBIE_STRONG_W_MAX])
			# 規則 6
			if float(enc.get("rate", 0.0)) > NEWBIE_RATE_MAX + EPS and not (rid in NEWBIE_RATE_EXEMPT):
				errs.append("%s: room %s encounter rate %.2f > %.2f" % [label, rid, float(enc.get("rate", 0.0)), NEWBIE_RATE_MAX])
	# 規則 6 對每一格野外都成立（不只最短路線上的房間；例如北邊雪地這種岔路）
	for rid in idx:
		if regions.get(idx[rid]["region"], {}).get("type", "") != "WILD":
			continue
		var cap := NEWBIE_RATE_EXEMPT_MAX if rid in NEWBIE_RATE_EXEMPT else NEWBIE_RATE_MAX
		var enc2: Variant = idx[rid]["room"].get("encounter")
		if enc2 is Dictionary and float(enc2.get("rate", 0.0)) > cap + EPS:
			errs.append("wild: room %s encounter rate %.2f > %.2f" % [rid, float(enc2.get("rate", 0.0)), cap])
	var uniq := PackedStringArray()
	for e3 in errs:
		if not (e3 in uniq):
			uniq.append(e3)
	return uniq

# 3. npcs.room 存在、房間 npcs 含此 NPC（雙向一致）、region 一致
static func _c_npc_rooms(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var idx := room_index(view)
	var npcs: Dictionary = view.get("npcs", {})
	var maps: Dictionary = view.get("maps", {})
	var escorts := escort_npcs(view)
	for nid in npcs:
		var npc: Dictionary = npcs[nid]
		var room_id: String = str(npc.get("room", ""))
		# M3B_PLAN §4.9：只供護送的 NPC（鏢車 n_ec_biaoche）不站在任何房間：room ""、沒有服務、被某條任務 ESCORT
		if room_id == "" and escorts.has(nid) and (npc.get("services", []) as Array).is_empty():
			continue
		if not idx.has(room_id):
			errs.append("npcs.%s: room '%s' does not exist" % [nid, room_id])
			continue
		# M3B_PLAN §8.1、§9.5 #9：比房間地圖 era 新的 NPC（例：1.0B 丐幫弟子站在 1.0A 的大理廣場）不寫進舊 era 的房間清單，
		# 由 npcs.room 放（WorldIndex 以 npcs.room 補；1.0A 世界不會看到不存在的 NPC id）
		var map_era := str(maps.get(idx[room_id]["region"], {}).get("era", ""))
		var cross_era := str(npc.get("era", "")) != map_era
		# M3c2 整合：雜務 NPC n_ch_* 已由整合者寫進地圖房間清單（M3C2_PLAN §9.4 例外），不再豁免
		if not (nid in idx[room_id]["room"].get("npcs", [])) and not cross_era:
			errs.append("npcs.%s: room %s does not list this npc" % [nid, room_id])
		if npc.get("region", "") != idx[room_id]["region"]:
			errs.append("npcs.%s: region '%s' != room region '%s'" % [nid, npc.get("region", ""), idx[room_id]["region"]])
	for rid in idx:
		for nid in idx[rid]["room"].get("npcs", []):
			if not npcs.has(nid):
				errs.append("room %s: npc '%s' not in npcs.json" % [rid, nid])
			elif npcs[nid].get("room", "") != rid:
				errs.append("room %s: npc '%s' has room '%s'" % [rid, nid, npcs[nid].get("room", "")])
	return errs

## 被任務 ESCORT 目標或 escort_start 動作護送的 NPC id（M3B_PLAN §4.9）
static func escort_npcs(view: Dictionary) -> Dictionary:
	var out := {}
	for qid in view.get("quests", {}):
		var q: Dictionary = view["quests"][qid]
		for s in q.get("stages", []):
			if not (s is Dictionary):
				continue
			for o in s.get("objectives", []):
				if o is Dictionary and str(o.get("type", "")) == "ESCORT" and str(o.get("npc", "")) != "":
					out[str(o["npc"])] = true
		for a in QuestDef._all_actions(q):
			if str(a.get("do", "")) == "escort_start" and str(a.get("npc", "")) != "":
				out[str(a["npc"])] = true
	return out

# 4. 服務一致
static func _c_npc_services(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var idx := room_index(view)
	var npcs: Dictionary = view.get("npcs", {})
	var teachers := {}
	for mid in view.get("masters", {}):
		teachers[view["masters"][mid].get("npc_id", "")] = true
	for nid in npcs:
		var npc: Dictionary = npcs[nid]
		var services: Array = npc.get("services", [])
		var quests: Array = npc.get("quests", [])
		var label := "npcs.%s" % nid
		if not (npc.get("kind", "") in NPC_KINDS):
			errs.append("%s: bad kind '%s'" % [label, npc.get("kind", "")])
		if not (npc.get("alignment", "") in ALIGNMENTS):
			errs.append("%s: bad alignment '%s'" % [label, npc.get("alignment", "")])
		if str(npc.get("talk", "")) != "talk_" + nid:
			errs.append("%s: talk must be 'talk_%s'" % [label, nid])
		for s in services:
			if not (s in NPC_SERVICES):
				errs.append("%s: unknown service '%s'" % [label, s])
		if "SHOP" in services:
			var shop: Variant = npc.get("shop")
			if not (shop is Dictionary) or not (shop.get("items") is Array) or shop["items"].is_empty():
				errs.append("%s: SHOP without shop.items" % label)
			else:
				for it in shop["items"]:
					if not view.get("items", {}).has(it):
						errs.append("%s: shop item '%s' missing" % [label, it])
		if "INN" in services and int(npc.get("inn_price", -1)) < 0:
			errs.append("%s: INN without inn_price" % label)
		if "TRAVEL" in services:
			var routes: Variant = npc.get("travel", [])
			if not (routes is Array) or routes.is_empty():
				errs.append("%s: TRAVEL without travel routes" % label)
			else:
				for r in routes:
					if not (r is Dictionary) or not idx.has(r.get("to_room", "")):
						errs.append("%s: travel to_room %s missing" % [label, str(r)])
					elif int(r.get("price", -1)) < 0:
						errs.append("%s: travel price missing" % label)
		if "JOIN" in services and not view.get("sects", {}).has(npc.get("join_sect", "")):
			errs.append("%s: JOIN with unknown join_sect '%s'" % [label, npc.get("join_sect", "")])
		if "FIGHT" in services:
			var fight: Variant = npc.get("fight")
			if not (fight is Dictionary) or not view.get("monsters", {}).has(fight.get("monster", "")):
				errs.append("%s: FIGHT monster missing" % label)
		if "TEACH" in services and not teachers.has(nid):
			errs.append("%s: TEACH but no masters rows" % label)
		if teachers.has(nid) and not ("TEACH" in services):
			errs.append("%s: has masters rows but no TEACH service" % label)
		# M3A_PLAN 8.5 #7：BETRAY、JAIL、TRIAL、GUIDE
		if "BETRAY" in services and not view.get("sects", {}).has(npc.get("join_sect", "")):
			errs.append("%s: BETRAY needs join_sect naming a sect" % label)
		if "JAIL" in services:
			var jr: Dictionary = idx.get(str(npc.get("room", "")), {}).get("room", {})
			# M3b：京城監獄看守人站在監獄門口，管相鄰的牢房（SectSystem.jail_room_of_npc）
			var next_jail := false
			for ex in jr.get("exits", []):
				if ex is Dictionary and bool(idx.get(str(ex.get("to", "")), {}).get("room", {}).get("jail", false)):
					next_jail = true
			if not bool(jr.get("jail", false)) and not next_jail:
				errs.append("%s: JAIL npc must stand in (or next to) a jail:true room" % label)
		# M3B_PLAN §4.8、§9.5 #7
		if "ESCORT" in services:
			var city := str(npc.get("escort", {}).get("city", "")) if npc.get("escort") is Dictionary else ""
			if city == "" or str(view.get("regions", {}).get(city, {}).get("type", "")) != "CITY":
				errs.append("%s: ESCORT needs escort.city naming a CITY region (got '%s')" % [label, city])
			else:
				var routed := false
				for rid2 in view.get("escort_routes", {}):
					var er: Dictionary = view["escort_routes"][rid2]
					if str(er.get("from_city", "")) == city or str(er.get("to_city", "")) == city:
						routed = true
				if not routed:
					errs.append("%s: ESCORT city %s has no escort_routes row" % [label, city])
		if "RANK" in services:
			var rs := str(npc.get("join_sect", ""))
			if str(view.get("sects", {}).get(rs, {}).get("ranks", "")) == "":
				errs.append("%s: RANK needs join_sect naming a sect with ranks" % label)
		if npc.get("shop") is Dictionary and npc["shop"].has("refuse_if"):
			var rif: Variant = npc["shop"]["refuse_if"]
			if not (rif is Array):
				errs.append("%s: shop.refuse_if must be an array of condition groups" % label)
			else:
				for gi in (rif as Array).size():
					if not (rif[gi] is Array) or (rif[gi] as Array).is_empty():
						errs.append("%s: shop.refuse_if[%d] must be a non-empty array of conditions" % [label, gi])
					else:
						errs.append_array(check_conditions(rif[gi], "%s.shop.refuse_if[%d]" % [label, gi]))
				var rt := str(npc["shop"].get("refuse_text", ""))
				if rt != "" and not view.get("text_templates", {}).has(rt):
					errs.append("%s: shop.refuse_text template '%s' missing" % [label, rt])
		if "TRIAL" in services:
			var tr: Variant = npc.get("trial")
			if not (tr is Dictionary) or str(tr.get("id", "")) == "" or str(tr.get("reward_flag", "")) == "" \
					or not (tr.get("waves") is Array) or (tr["waves"] as Array).is_empty():
				errs.append("%s: TRIAL needs trial{id, waves[], reward_flag}" % label)
			else:
				for w in tr["waves"]:
					if not (w is Array) or (w as Array).is_empty():
						errs.append("%s: trial wave must be a non-empty array" % label)
						continue
					for m in w:
						if not view.get("monsters", {}).has(m):
							errs.append("%s: trial monster '%s' missing" % [label, m])
				var pmin := int(tr.get("party_min", 1))
				var pmax := int(tr.get("party_max", pmin))
				if pmin < 1 or pmax < pmin:
					errs.append("%s: trial party_min/party_max invalid" % label)
		if "GUIDE" in services:
			var gd: Variant = npc.get("guide")
			var to := str(gd.get("to_room", "")) if gd is Dictionary else ""
			if not idx.has(to):
				errs.append("%s: GUIDE to_room '%s' missing" % [label, to])
			elif idx[to]["region"] != str(npc.get("region", "")):
				errs.append("%s: GUIDE to_room %s is outside the npc's region" % [label, to])
		for q in quests:
			if not view.get("quests", {}).has(q):
				errs.append("%s: quest '%s' missing" % [label, q])
			elif view["quests"][q].get("giver", "") != nid:
				errs.append("%s: quest '%s' giver is '%s'" % [label, q, view["quests"][q].get("giver", "")])
		if not quests.is_empty() and not ("QUEST" in services):
			errs.append("%s: has quests but no QUEST service" % label)
		if "MEAL" in services:
			var meal: Variant = npc.get("meal")
			if not (meal is Dictionary) or not meal.has("food") or not meal.has("water") \
					or not (meal.get("hours") is Array) or meal["hours"].is_empty():
				errs.append("%s: MEAL without meal{food,water,hours}" % label)
			else:
				for h in meal["hours"]:
					if not (h in SHICHEN):
						errs.append("%s: meal hour '%s' is not a shichen" % [label, h])
	return errs

# 5. masters.skill_id 可解析；tool 存在
static func _c_masters(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var seen := {}
	for mid in view.get("masters", {}):
		var m: Dictionary = view["masters"][mid]
		var label := "masters.%s" % mid
		var sid: String = str(m.get("skill_id", ""))
		if m.has("art_id"):
			errs.append("%s: art_id was renamed to skill_id (D4)" % label)
		if skill_kind(view, sid) == "":
			errs.append("%s: skill_id '%s' resolves to no skill table" % [label, sid])
		if not view.get("npcs", {}).has(m.get("npc_id", "")):
			errs.append("%s: npc_id '%s' missing" % [label, m.get("npc_id", "")])
		var tool: String = str(m.get("tool", ""))
		if tool != "" and not view.get("items", {}).has(tool):
			errs.append("%s: tool '%s' missing" % [label, tool])
		if typeof(m.get("cap")) != TYPE_INT or int(m["cap"]) < 1:
			errs.append("%s: cap must be int >= 1" % label)
		if typeof(m.get("price", 0)) != TYPE_INT or int(m.get("price", 0)) < 0:
			errs.append("%s: price must be int >= 0" % label)
		# M3A_PLAN 3.5：hours（選填，只在這些時辰教；空陣列 = 全天）
		if m.has("hours"):
			if not (m["hours"] is Array):
				errs.append("%s: hours must be an array" % label)
			else:
				for h in m["hours"]:
					if not (str(h) in SHICHEN):
						errs.append("%s: hours '%s' is not a shichen" % [label, str(h)])
		var key: String = "%s|%s" % [m.get("npc_id", ""), sid]
		if seen.has(key):
			errs.append("%s: duplicate npc+skill (also %s)" % [label, seen[key]])
		seen[key] = mid
	return errs

# 6. 任務步驟目標、物品、獎勵
static func _c_quests(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var idx := room_index(view)
	for qid in view.get("quests", {}):
		var q: Dictionary = view["quests"][qid]
		var label := "quests.%s" % qid
		var giver: String = str(q.get("giver", ""))
		if not view.get("npcs", {}).has(giver):
			errs.append("%s: giver '%s' missing" % [label, giver])
		elif not (qid in view["npcs"][giver].get("quests", [])):
			errs.append("%s: giver %s does not list this quest" % [label, giver])
		# STORY_PLAN §8.5 #1–#2：第 2 版列（stages）用 QuestDef.validate；舊格式（_legacy）照舊檢查 steps
		if not bool(q.get("_legacy", false)) and q.get("stages") is Array:
			# M3B_PLAN §4.9：sect_rank 獎勵（QuestDef 凍結、不認得這個鍵）→ 這裡另外檢查（check_m3b）
			for e in QuestDef.validate(q, view):
				if not ("unknown reward key 'sect_rank'" in e):
					errs.append(e)
			continue
		var steps: Variant = q.get("steps", [])
		if not (steps is Array) or steps.is_empty():
			errs.append("%s: steps[] missing" % label)
			steps = []
		for i in steps.size():
			var st: Variant = steps[i]
			if not (st is Dictionary):
				errs.append("%s.steps[%d]: not an object" % [label, i])
				continue
			var ty: String = str(st.get("type", ""))
			var target: String = str(st.get("target", ""))
			if not (ty in QUEST_STEP_TYPES):
				errs.append("%s.steps[%d]: bad type '%s'" % [label, i, ty])
				continue
			if typeof(st.get("count", 1)) != TYPE_INT or int(st.get("count", 1)) < 1:
				errs.append("%s.steps[%d]: count must be int >= 1" % [label, i])
			match ty:
				"KILL":
					if not view.get("monsters", {}).has(target):
						errs.append("%s.steps[%d]: KILL target monster '%s' missing" % [label, i, target])
				"DELIVER":
					if not view.get("npcs", {}).has(target):
						errs.append("%s.steps[%d]: DELIVER target npc '%s' missing" % [label, i, target])
					if not view.get("items", {}).has(st.get("item", "")):
						errs.append("%s.steps[%d]: DELIVER item '%s' missing" % [label, i, st.get("item", "")])
				"TALK":
					if not view.get("npcs", {}).has(target):
						errs.append("%s.steps[%d]: TALK target npc '%s' missing" % [label, i, target])
				"REACH":
					if not idx.has(target):
						errs.append("%s.steps[%d]: REACH target room '%s' missing" % [label, i, target])
		for gi in q.get("give_items", []):
			if not (gi is Dictionary) or not view.get("items", {}).has(gi.get("id", "")):
				errs.append("%s: give_items %s missing" % [label, str(gi)])
		var rw: Variant = q.get("rewards", {})
		if not (rw is Dictionary):
			errs.append("%s: rewards must be an object" % label)
			continue
		for it in rw.get("items", []):
			if not (it is Dictionary) or not view.get("items", {}).has(it.get("id", "")):
				errs.append("%s: rewards.items %s missing" % [label, str(it)])
		for sk in rw.get("skill_prof", {}):
			if skill_kind(view, sk) == "":
				errs.append("%s: rewards.skill_prof skill '%s' missing" % [label, sk])
		for f in rw.get("flags", []):
			if typeof(f) != TYPE_STRING or f == "":
				errs.append("%s: rewards.flags must be non-empty strings" % label)
	return errs

# 7. 生活技能：工具、產出、食譜物品存在；feature 合法
static func _c_life_skills(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var items: Dictionary = view.get("items", {})
	for lid in view.get("life_skills", {}):
		var l: Dictionary = view["life_skills"][lid]
		var label := "life_skills.%s" % lid
		var mode := str(l.get("mode", "GATHER"))
		if not (mode in DataSchema.LIFE_MODES):
			errs.append("%s: bad mode '%s'" % [label, mode])
		# M3B_PLAN §4.5：CRAFT 技能的 feature 可以是 ""（隨地，裁縫、工匠）
		if not (l.get("feature", "") in ROOM_FEATURES) and not (mode == "CRAFT" and str(l.get("feature", "")) == ""):
			errs.append("%s: bad feature '%s'" % [label, l.get("feature", "")])
		for t2 in l.get("tools", []):
			if not items.has(str(t2)):
				errs.append("%s: tools item '%s' missing" % [label, t2])
		if str(l.get("tool", "")) != "" and not items.has(l["tool"]):
			errs.append("%s: tool '%s' missing" % [label, l["tool"]])
		for y in l.get("yield", []):
			if not (y is Dictionary) or not items.has(y.get("item", "")):
				errs.append("%s: yield item %s missing" % [label, str(y)])
				continue
			var n: Variant = y.get("n", [])
			if not (n is Array) or n.size() != 2 or int(n[0]) < 1 or int(n[1]) < int(n[0]):
				errs.append("%s: yield n must be [min,max] with 1 <= min <= max" % label)
			if float(y.get("chance", 0.0)) <= 0.0 or float(y.get("chance", 0.0)) > 1.0:
				errs.append("%s: yield chance must be in (0,1]" % label)
		for rc in l.get("recipes", []):
			if not (rc is Dictionary):
				errs.append("%s: recipe is not an object" % label)
				continue
			for inp in rc.get("inputs", []):
				if not (inp is Dictionary) or not items.has(inp.get("item", "")):
					errs.append("%s: recipe %s input %s missing" % [label, rc.get("id", "?"), str(inp)])
			var out: Variant = rc.get("output", {})
			if not (out is Dictionary) or not items.has(out.get("item", "")):
				errs.append("%s: recipe %s output missing" % [label, rc.get("id", "?")])
			# M3B_PLAN §4.5：配方 feature 覆寫（"" = 隨地）、額外工具
			if rc.has("feature") and str(rc["feature"]) != "" and not (str(rc["feature"]) in ROOM_FEATURES):
				errs.append("%s: recipe %s bad feature '%s'" % [label, rc.get("id", "?"), rc["feature"]])
			for t3 in rc.get("tools", []):
				if not items.has(str(t3)):
					errs.append("%s: recipe %s tool '%s' missing" % [label, rc.get("id", "?"), t3])
		match mode:
			"HUNT":
				var h: Variant = l.get("hunt")
				if not (h is Dictionary) or not (h.get("drops") is Array):
					errs.append("%s: HUNT needs hunt{drops[]}" % label)
				else:
					for d in h["drops"]:
						if not (d is Dictionary) or not items.has(str(d.get("item", ""))):
							errs.append("%s: hunt drop %s missing" % [label, str(d)])
							continue
						if float(d.get("chance", 0.0)) <= 0.0 or float(d.get("chance", 0.0)) > 1.0:
							errs.append("%s: hunt drop %s chance must be in (0,1]" % [label, d["item"]])
						for mid in d.get("monsters", []):
							if not view.get("monsters", {}).has(str(mid)):
								errs.append("%s: hunt drop %s monster '%s' missing" % [label, d["item"], mid])
			"GATHER":
				# 既有的廚師只有配方（M1）：GATHER 要 yield 或 recipes
				if (l.get("yield", []) as Array).is_empty() and (l.get("recipes", []) as Array).is_empty():
					errs.append("%s: needs yield or recipes" % label)
			"CRAFT":
				if (l.get("recipes", []) as Array).is_empty():
					errs.append("%s: CRAFT needs recipes" % label)
	return errs

# 8. 怪物的武功存在；monster_only 武功不出現在 masters
static func _c_monsters_and_arts(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var arts: Dictionary = view.get("martial_arts", {})
	for mid in view.get("monsters", {}):
		var m: Dictionary = view["monsters"][mid]
		var label := "monsters.%s" % mid
		if (m.get("arts", []) as Array).is_empty():
			errs.append("%s: arts[] empty" % label)
		for a in m.get("arts", []):
			if not (a is Dictionary) or not arts.has(a.get("art", "")):
				errs.append("%s: art %s missing" % [label, str(a)])
		for s in MONSTER_REQUIRED_SKILLS:
			if not m.get("skills", {}).has(s):
				errs.append("%s: skills missing %s" % [label, s])
		for s in ["qi", "neili", "jing"] + ATTR_IDS:
			if typeof(m.get("stats", {}).get(s)) != TYPE_INT:
				errs.append("%s: stats.%s missing or not int" % [label, s])
		if not (m.get("kind", "") in MONSTER_KINDS):
			errs.append("%s: bad kind '%s'" % [label, m.get("kind", "")])
		if not (m.get("ai", "") in MONSTER_AIS):
			errs.append("%s: bad ai '%s'" % [label, m.get("ai", "")])
		if not (m.get("weapon_type", "FIST") in WEAPON_TYPES):
			errs.append("%s: bad weapon_type '%s'" % [label, m.get("weapon_type", "")])
		for d in m.get("drops", []):
			if not (d is Dictionary) or int(d.get("min", 1)) < 1 or int(d.get("max", 1)) < int(d.get("min", 1)):
				errs.append("%s: bad drop %s" % [label, str(d)])
	for aid in arts:
		var a: Dictionary = arts[aid]
		if not (a.get("category", "") in ART_CATEGORIES):
			errs.append("martial_arts.%s: bad category '%s'" % [aid, a.get("category", "")])
		for mv in a.get("moves", []):
			if mv is Dictionary and not (mv.get("aoe", "SINGLE") in MOVE_AOES):
				errs.append("martial_arts.%s: move %s bad aoe '%s'" % [aid, mv.get("id", "?"), mv.get("aoe", "")])
	for msid in view.get("masters", {}):
		var sid: String = view["masters"][msid].get("skill_id", "")
		if arts.has(sid) and arts[sid].get("monster_only", false):
			errs.append("masters.%s: teaches monster_only art '%s'" % [msid, sid])
	return errs

# 9. 遇敵表
static func _c_encounters(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var idx := room_index(view)
	for rid in idx:
		var enc: Variant = idx[rid]["room"].get("encounter")
		if not (enc is Dictionary):
			continue
		var rate := float(enc.get("rate", -1.0))
		if rate < 0.0 or rate > 1.0:
			errs.append("room %s: encounter.rate must be in [0,1]" % rid)
		var table: Variant = enc.get("table", [])
		if not (table is Array) or (rate > 0.0 and table.is_empty()):
			errs.append("room %s: encounter.table empty" % rid)
			continue
		for e in table:
			if not (e is Dictionary) or not view.get("monsters", {}).has(e.get("monster", "")):
				errs.append("room %s: encounter monster %s missing" % [rid, str(e)])
				continue
			if typeof(e.get("w")) != TYPE_INT or int(e["w"]) <= 0:
				errs.append("room %s: encounter weight for %s must be int > 0" % [rid, e["monster"]])
			var c: Variant = e.get("count", [])
			if not (c is Array) or c.size() != 2 or typeof(c[0]) != TYPE_INT or typeof(c[1]) != TYPE_INT \
					or c[0] < 1 or c[1] < c[0] or c[1] > 4:
				errs.append("room %s: encounter count for %s must be [a,b] with 1 <= a <= b <= 4" % [rid, e["monster"]])
	return errs

# 10. 區格與出生城
static func _c_regions(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var idx := room_index(view)
	for rid in view.get("regions", {}):
		var r: Dictionary = view["regions"][rid]
		if not (r.get("type", "") in REGION_TYPES):
			errs.append("regions.%s: bad type '%s'" % [rid, r.get("type", "")])
		if not view.get("maps", {}).has(rid):
			errs.append("regions.%s: no active map" % rid)
		var br: String = str(r.get("birth_room", ""))
		if r.get("birth_allowed", false):
			if r.get("type", "") != "CITY":
				errs.append("regions.%s: birth_allowed but type is not CITY" % rid)
			if not idx.has(br):
				errs.append("regions.%s: birth_room '%s' missing" % [rid, br])
			elif idx[br]["region"] != rid:
				errs.append("regions.%s: birth_room '%s' belongs to %s" % [rid, br, idx[br]["region"]])
		elif br != "" and not idx.has(br):
			errs.append("regions.%s: birth_room '%s' missing" % [rid, br])
	errs.append_array(check_world_pos(view.get("regions", {})))
	return errs

## 大地圖「江湖全圖」用的 world_pos（選填）：[x, y] 兩個 0~1000 的整數，不同區域不能同一點
static func check_world_pos(regions: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var used := {}
	var ids: Array = regions.keys()
	ids.sort()
	for rid in ids:
		var r: Variant = regions[rid]
		if not (r is Dictionary) or not r.has("world_pos"):
			continue
		var wp: Variant = r["world_pos"]
		if not (wp is Array) or wp.size() != 2 or typeof(wp[0]) != TYPE_INT or typeof(wp[1]) != TYPE_INT \
				or wp[0] < 0 or wp[1] < 0 or wp[0] > 1000 or wp[1] > 1000:
			errs.append("regions.%s: world_pos must be [x, y] integers in 0..1000, got %s" % [rid, str(wp)])
			continue
		var key := "%d,%d" % [wp[0], wp[1]]
		if used.has(key):
			errs.append("regions.%s: world_pos %s same as regions.%s" % [rid, key, used[key]])
		else:
			used[key] = rid
	return errs

# 11. 模板涵蓋
static func _c_templates(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var tpl: Dictionary = view.get("text_templates", {})
	for key in REQUIRED_TEMPLATE_KEYS:
		_need_template(tpl, key, TEMPLATE_VARIANTS.get(key, ["self"]), errs)
	for key in UI_ONLY_KEYS:
		if tpl.has(key):
			errs.append("text_templates: UI-only key '%s' must not have a template" % key)
	for aid in view.get("martial_arts", {}):
		for mv in view["martial_arts"][aid].get("moves", []):
			if mv is Dictionary:
				_need_template(tpl, str(mv.get("flavor", "")), FLAVOR_VARIANTS, errs)
	for nid in view.get("npcs", {}):
		_need_template(tpl, str(view["npcs"][nid].get("talk", "")), ["self"], errs)
	for lid in view.get("life_skills", {}):
		_need_template(tpl, "work_ok_" + lid, ["self"], errs)
		_need_template(tpl, "work_fail_" + lid, ["self"], errs)
	return errs

static func _need_template(tpl: Dictionary, key: String, variants: Array, errs: PackedStringArray) -> void:
	if key == "":
		errs.append("text_templates: empty template key referenced")
		return
	if not tpl.has(key):
		errs.append("text_templates: missing '%s'" % key)
		return
	for v in variants:
		if str(tpl[key].get(v, "")) == "":
			errs.append("text_templates.%s: missing variant '%s'" % [key, v])

# 12. 物品效果與武器類別
static func _c_items(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	for iid in view.get("items", {}):
		var it: Dictionary = view["items"][iid]
		var label := "items.%s" % iid
		if not (it.get("tab", "") in ITEM_TABS):
			errs.append("%s: bad tab '%s'" % [label, it.get("tab", "")])
		if not (it.get("slot", "") in ITEM_SLOTS):
			errs.append("%s: bad slot '%s'" % [label, it.get("slot", "")])
		if it.get("slot", "") == "WEAPON" and not (it.get("weapon_type", "") in WEAPON_TYPES):
			errs.append("%s: WEAPON slot needs weapon_type in %s" % [label, WEAPON_TYPES])
		if int(it.get("stack", 1)) < 1:
			errs.append("%s: stack must be >= 1" % label)
		var has_use := false
		for e in it.get("effects", []):
			if not (e is Dictionary) or not (e.get("type", "") in EFFECT_TYPES):
				errs.append("%s: bad effect %s" % [label, str(e)])
				continue
			match e["type"]:
				"restore":
					has_use = true
					if not (e.get("stat", "") in VITAL_IDS):
						errs.append("%s: restore stat '%s' invalid" % [label, e.get("stat", "")])
				"attr":
					if not (e.get("stat", "") in ATTR_IDS):
						errs.append("%s: attr stat '%s' invalid" % [label, e.get("stat", "")])
				"smoke":
					has_use = true
				"LIANDU":
					has_use = true   # M3d 整合：小木鼎由背包「使用」觸發煉毒（M3D_PLAN §4.4）
				"cure":
					# M3A_PLAN 3.9：解除狀態（status 存在、max_level ≥ 1）；沒有 value
					has_use = true
					if not view.get("status_effects", {}).has(str(e.get("status", ""))):
						errs.append("%s: cure status '%s' missing" % [label, e.get("status", "")])
					if not (typeof(e.get("max_level")) in [TYPE_INT, TYPE_FLOAT]) or int(e.get("max_level", 0)) < 1:
						errs.append("%s: cure max_level must be a number >= 1" % label)
					continue
				"hidden":
					# 暗器彈藥：value = 敵人傷氣；poisonable 選填 bool
					if e.has("poisonable") and typeof(e["poisonable"]) != TYPE_BOOL:
						errs.append("%s: hidden poisonable must be a bool" % label)
					if typeof(e.get("value")) == TYPE_INT and int(e["value"]) < 1:
						errs.append("%s: hidden value must be >= 1" % label)
			if typeof(e.get("value")) != TYPE_INT:
				errs.append("%s: effect value must be int" % label)
		if bool(it.get("usable", false)) != has_use:
			errs.append("%s: usable must be true exactly when it has restore/smoke/cure effects" % label)
		var so := str(it.get("sect_only", ""))
		if so != "" and not view.get("sects", {}).has(so):
			errs.append("%s: sect_only '%s' is not a sect" % [label, so])
	return errs

# 其他：門派技能、基本武學曲線、屬性表
static func _c_misc(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	for sid in view.get("sects", {}):
		var s: Dictionary = view["sects"][sid]
		var eff: Variant = s.get("sect_skill_effect", {})
		if not (eff is Dictionary) or not (eff.get("effect", "") in SECT_SKILL_EFFECTS):
			errs.append("sects.%s: sect_skill_effect.effect invalid" % sid)
		if typeof(s.get("sect_skill_cap")) != TYPE_INT:
			errs.append("sects.%s: sect_skill_cap must be int" % sid)
		if str(s.get("sect_skill", "")) == "":
			errs.append("sects.%s: sect_skill missing" % sid)
		for g in s.get("gender", []):
			if not (g in ["M", "F"]):
				errs.append("sects.%s: bad gender '%s'" % [sid, g])
	for bid in view.get("basic_skills", {}):
		if not (view["basic_skills"][bid].get("curve", "") in BASIC_CURVES):
			errs.append("basic_skills.%s: bad curve" % bid)
		for a in view["basic_skills"][bid].get("attr_bonus_per10", {}):
			if not (a in ATTR_IDS):
				errs.append("basic_skills.%s: attr_bonus_per10 bad attr '%s'" % [bid, a])
	for aid in view.get("attributes", {}):
		if not (aid in ATTR_IDS):
			errs.append("attributes.%s: unknown attribute id" % aid)
	for a in ATTR_IDS:
		if not view.get("attributes", {}).has(a):
			errs.append("attributes: missing '%s'" % a)
	return errs

# ============================================================================
# M3a 檢查（M3A_PLAN 8.5）。check_content() 會呼叫 check_m3a()。
# ============================================================================

## 3.2 各派固定 id（綁定；acceptance bot 依此寫）
## sect -> [head_npc, head_room, entry_master, [entry_arts], acceptance_move, spar_npc, spar_monster, jail_room]
const SECT_FIXED := {
	"wudang": ["n_wd_zhangsanfeng", "wd_neitang", "n_wd_yudaiyan", ["wd_changquan", "wd_xinfa"], "wd_cq_1", "n_wd_spar", "m_wd_dizi", "wd_siguo"],
	"emei": ["n_em_miejue", "em_miejue", "n_em_jingjia", ["em_piaoxue", "em_xinfa"], "em_px_1", "n_em_spar", "m_em_dizi", "em_siguo"],
	"hengshan": ["n_hg_dingxian", "hg_hall", "n_hg_yihe", ["hg_jianfa", "hg_xinfa"], "hg_jf_1", "n_hg_spar", "m_hg_dizi", ""],
	"quanzhen": ["n_qz_qiuchuji", "qz_sanqing", "n_qz_qiuchuji", ["qz_jianfa", "qz_xinfa"], "qz_jf_1", "n_qz_spar", "m_qz_dizi", "qz_siguo"],
	"gumu": ["n_gm_zhangmen", "gm_hall", "n_gm_zhangmen", ["gm_yunu_jian", "gm_xinfa"], "gm_yn_1", "n_gm_spar", "m_gm_dizi", "gm_shishi"],
	"lingjiu": ["n_lj_tonglao", "lj_hall", "n_lj_tonglao", ["lj_zhemei", "lj_xiaoyao"], "lj_zm_1", "n_lj_spar", "m_lj_dizi", ""],
	"xingxiu": ["n_xh_dingchunqiu", "xh_hall", "n_xh_dingchunqiu", ["xh_chousui", "xh_xinfa"], "xh_cs_1", "n_xh_spar", "m_xh_dizi", ""],
	"xuedao": ["n_xd_laozu", "xd_hall", "n_xd_shengdi", ["xd_daofa", "xd_xinfa"], "xd_df_1", "n_xd_spar", "m_xd_dizi", ""],
}
## 既有兩派的 NPC 沿用舊 id（n_yuebuqun 等），不檢查 NPC 前綴
const SECT_PREFIX_LEGACY := ["shaolin", "huashan"]
## 2.3 規則 1：新休息點各要一個 INN（inn_price 10–20），且不遇敵
const M3A_REST_ROOMS := ["em_teahouse", "ts_hut", "xd_tent"]
## 6.12 機制事件與原因碼（_rules.json、_cmd.json 碎片）：key -> 變體
const M3A_TEMPLATE_KEYS := {
	"sect_breach": ["self"], "sect_expel": ["self", "other"], "sect_betray": ["self", "other"], "sect_stop_teach": ["self"],
	"sect_skill_decay": ["self"], "sect_hostile": ["self"], "jail_in": ["self", "other"], "jail_out": ["self"],
	"jail_ransom_paid": ["self"], "poison_flare": ["self"], "condition_off": ["self"], "npc_guide": ["self"],
	"trial_passed": ["self"],
	"sect_repent": ["self"], "sect_repent_refused": ["self"], "err_sect_lockout": ["self"], "err_req_sect_lockout": ["self"],
	"err_sect_stop_teach": ["self"], "err_sect_banned": ["self"], "err_jailed": ["self"], "err_need_confirm": ["self"],
	"err_no_prisoner": ["self"], "err_trial_party": ["self"], "err_no_flee": ["self"], "err_not_teach_time": ["self"],
	"err_req_has_item": ["self"], "err_req_any_of": ["self"], "err_req_enemy_of": ["self"], "err_req_pk_min": ["self"],
	"err_req_killing_intent_min": ["self"], "err_req_sect_master": ["self"], "err_req_party_size_min": ["self"],
	"err_req_hour_in": ["self"],
	"battle_poison_ok": ["self", "target", "other"], "battle_poison_fail": ["self", "target", "other"],
	"battle_poison_tick": ["self", "other"], "battle_medic": ["self", "target", "other"],
	"battle_hidden_hit": ["self", "target", "other"], "battle_hidden_miss": ["self", "target", "other"],
	"battle_formation_on": ["self", "other"], "battle_formation_off": ["self", "other"],
	"battle_inner_heal": ["self", "other"], "battle_inner_expel": ["self", "other"],
	"battle_inner_unseal_ok": ["self", "other"], "battle_inner_unseal_fail": ["self", "other"],
	"battle_inner_transfer": ["self", "target", "other"], "battle_acupoint_ok": ["self", "target", "other"],
	"battle_acupoint_fail": ["self", "target", "other"], "battle_status_skip": ["self", "other"],
	"battle_confused": ["self", "other"], "battle_item_use": ["self", "target", "other"], "battle_wave": ["other"],
	"battle_bleed_tick": ["self", "other"], "battle_aoe": ["self"],
	"battle_proc_RESIST": ["self", "other"], "battle_proc_EVADE": ["self", "other"], "battle_proc_COUNTER": ["self", "other"],
	"battle_proc_REST": ["self", "other"], "battle_proc_PARALYZE": ["self", "other"], "battle_proc_CONFUSE": ["self", "other"],
	"battle_proc_DISTRACT": ["self", "other"], "battle_proc_HEAVY": ["self", "other"],
	"err_cmd_disabled": ["self"], "err_no_poison_art": ["self"], "err_no_medic": ["self"], "err_not_ally": ["self"],
	"err_no_hidden": ["self"], "err_no_ammo": ["self"], "err_no_formation_art": ["self"], "err_formation_party": ["self"],
	"err_formation_stations": ["self"], "err_no_inner_art": ["self"], "err_nothing_to_expel": ["self"],
	"err_full_qi": ["self"], "err_nothing_to_heal": ["self"],
	"err_not_sealed": ["self"], "err_no_acupoint": ["self"], "err_bad_direction": ["self"],
}
## 8.5 #11：常見簡體字黑名單（只收「繁體不會用到」的字形）
const SIMPLIFIED_CHARS := "门师剑气内医阵宫灵鹫恒当华这说时们来对过还进长发经见实战护让将张风东无为与从杀罚龙马鸟书体么点头话给处动开关应观刘赵陈杨吗级练伤药钱买卖习传贼岭边仅够难欢请认识问间页写术宝云会谢听"   # 宝云会谢听：STORY_PLAN §8.5 #9

static func check_m3a(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	errs.append_array(_c_sects(view))
	errs.append_array(_c_sect_rules(view))
	errs.append_array(_c_arts_m3a(view))
	errs.append_array(_c_rooms_m3a(view))
	errs.append_array(_c_simplified(view))
	var tpl: Dictionary = view.get("text_templates", {})
	for key in M3A_TEMPLATE_KEYS:
		_need_template(tpl, key, M3A_TEMPLATE_KEYS[key], errs)
	return errs

static func _has_service(view: Dictionary, nid: String, svc: String) -> bool:
	return svc in view.get("npcs", {}).get(nid, {}).get("services", [])

## 條件陣列（含 any_of 內層）裡所有 type == t 的條件
static func conditions_of_type(conds: Variant, t: String) -> Array:
	var out: Array = []
	if not (conds is Array):
		return out
	for c in conds:
		if not (c is Dictionary):
			continue
		if c.get("type", "") == t:
			out.append(c)
		if c.get("type", "") == "any_of" and c.get("options") is Array:
			for opt in c["options"]:
				out.append_array(conditions_of_type(opt, t))
	return out

# 8.5 #2、#6：門派列、固定 id、收徒 NPC 走得到
static func _c_sects(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var idx := room_index(view)
	var npcs: Dictionary = view.get("npcs", {})
	var arts: Dictionary = view.get("martial_arts", {})
	var g := room_graph(view)
	var birth_reach := {}
	for br in birth_rooms(view):
		birth_reach[br] = _bfs(g, br, "")["seen"]
	var taught := {}
	for mid in view.get("masters", {}):
		taught[str(view["masters"][mid].get("skill_id", ""))] = true
	for sid in view.get("sects", {}):
		var s: Dictionary = view["sects"][sid]
		var label := "sects.%s" % sid
		var prefix := str(s.get("prefix", ""))
		var gate_region := str(s.get("gate_region", ""))
		if prefix == "":
			errs.append("%s: prefix missing" % label)
		var gate := str(s.get("gate_room", ""))
		if not idx.has(gate):
			errs.append("%s: gate_room '%s' missing" % [label, gate])
		elif idx[gate]["region"] != gate_region:
			errs.append("%s: gate_room %s is not in gate_region %s" % [label, gate, gate_region])
		var head := str(s.get("head_npc", ""))
		if not npcs.has(head):
			errs.append("%s: head_npc '%s' missing" % [label, head])
		else:
			for svc in ["JOIN", "BETRAY"]:
				if not _has_service(view, head, svc):
					errs.append("%s: head_npc %s lacks %s" % [label, head, svc])
			if str(npcs[head].get("join_sect", "")) != sid:
				errs.append("%s: head_npc %s join_sect is '%s'" % [label, head, npcs[head].get("join_sect", "")])
			var hroom := str(npcs[head].get("room", ""))
			for br in birth_reach:
				if not birth_reach[br].has(hroom):
					errs.append("%s: head_npc room %s cannot be reached on foot from birth room %s" % [label, hroom, br])
		if typeof(s.get("enforcer")) != TYPE_BOOL:
			errs.append("%s: enforcer must be a bool" % label)
		var jail := str(s.get("jail_room", ""))
		if not bool(s.get("enforcer", false)) and jail != "":
			errs.append("%s: enforcer false needs jail_room \"\"" % label)
		if jail != "":
			if not idx.has(jail):
				errs.append("%s: jail_room '%s' missing" % [label, jail])
			elif not bool(idx[jail]["room"].get("jail", false)):
				errs.append("%s: jail_room %s is not jail:true" % [label, jail])
		for e in s.get("enforcers", []):
			if not npcs.has(e):
				errs.append("%s: enforcer npc '%s' missing" % [label, e])
		# 犯戒（恆山，M3a 審查 #1）：breach_outcome "" 或 LOCKOUT；LOCKOUT 要有站在山門的 repent_npc、且沒有執法者
		var bo := str(s.get("breach_outcome", ""))
		if not (bo in ["", "LOCKOUT"]):
			errs.append("%s: breach_outcome '%s' not in [\"\", LOCKOUT]" % [label, bo])
		elif bo == "LOCKOUT":
			var rn := str(s.get("repent_npc", ""))
			if not npcs.has(rn):
				errs.append("%s: breach_outcome LOCKOUT needs repent_npc (missing '%s')" % [label, rn])
			elif str(npcs[rn].get("room", "")) != str(s.get("gate_room", "")):
				errs.append("%s: repent_npc %s must stand in gate_room %s" % [label, rn, s.get("gate_room", "")])
			if bool(s.get("enforcer", false)):
				errs.append("%s: breach_outcome LOCKOUT is for sects without an enforcer" % label)
		var he: Variant = s.get("hostile_entry", [])
		if not (he is Array):
			errs.append("%s: hostile_entry must be an array" % label)
			he = []
		for h in he:
			if not (h is Dictionary):
				errs.append("%s: hostile_entry row is not an object" % label)
				continue
			if not view.get("monsters", {}).has(str(h.get("monster", ""))):
				errs.append("%s: hostile_entry monster '%s' missing" % [label, h.get("monster", "")])
			if not (h.get("rooms", "") in DataSchema.HOSTILE_ROOMS):
				errs.append("%s: hostile_entry rooms '%s' not in %s" % [label, h.get("rooms", ""), DataSchema.HOSTILE_ROOMS])
			var cnt: Variant = h.get("count", [])
			if not (cnt is Array) or cnt.size() != 2 or int(cnt[0]) < 1 or int(cnt[1]) < int(cnt[0]) or int(cnt[1]) > 4:
				errs.append("%s: hostile_entry count must be [a,b] with 1 <= a <= b <= 4" % label)
			if float(h.get("chance", -1.0)) <= 0.0 or float(h.get("chance", -1.0)) > 1.0:
				errs.append("%s: hostile_entry chance must be in (0,1]" % label)
			if bool(h.get("capture", false)) and jail == "":
				errs.append("%s: hostile_entry capture needs a jail_room" % label)
		if not (s.get("visitors", "") in DataSchema.SECT_VISITORS):
			errs.append("%s: visitors '%s' not in %s" % [label, s.get("visitors", ""), DataSchema.SECT_VISITORS])
		elif s["visitors"] == "MEMBERS":
			var locked := false
			for rid in idx:
				if idx[rid]["region"] == gate_region and rid != gate and not (idx[rid]["room"].get("requires", []) as Array).is_empty():
					locked = true
			if not locked:
				errs.append("%s: visitors MEMBERS but no room past the gate has requires" % label)
		var meal := str(s.get("meal_npc", ""))
		if meal != "" and not _has_service(view, meal, "MEAL"):
			errs.append("%s: meal_npc '%s' missing or has no MEAL" % [label, meal])
		if typeof(s.get("personal_master", false)) != TYPE_BOOL:
			errs.append("%s: personal_master must be a bool" % label)
		for f in ["sect_skill_gain", "sect_skill_penalties", "teach_requires"]:
			if not (s.get(f, []) is Array):
				errs.append("%s: %s must be an array" % [label, f])
		if not taught.has(str(s.get("sect_skill", ""))):
			errs.append("%s: sect_skill '%s' has no masters row" % [label, s.get("sect_skill", "")])
		# K5 前綴
		if prefix != "":
			for rid in idx:
				if idx[rid]["region"] == gate_region and not rid.begins_with(prefix + "_"):
					errs.append("%s: room %s lacks prefix '%s_'" % [label, rid, prefix])
			for aid in arts:
				if str(arts[aid].get("sect_id", "")) == sid and not aid.begins_with(prefix + "_"):
					errs.append("%s: art %s lacks prefix '%s_'" % [label, aid, prefix])
			if not (sid in SECT_PREFIX_LEGACY):
				for nid in npcs:
					# M3c2 WP-PACE：雜務 NPC 的前綴是 n_ch_<派前綴>_（M3C2_PLAN Q6）
					var ch_ok: bool = str(nid).begins_with("n_ch_%s_" % prefix) or str(nid).begins_with("n_ar_%s_" % prefix)   # M3d 整合：WP-ARTS 武功鏈 NPC n_ar_<派前綴>_
					if str(npcs[nid].get("region", "")) == gate_region and not nid.begins_with("n_%s_" % prefix) and not ch_ok:
						errs.append("%s: npc %s lacks prefix 'n_%s_'" % [label, nid, prefix])
		# 3.2 固定 id
		if SECT_FIXED.has(sid):
			var fx: Array = SECT_FIXED[sid]
			if head != fx[0]:
				errs.append("%s: head_npc must be %s (3.2)" % [label, fx[0]])
			if npcs.has(fx[0]) and str(npcs[fx[0]].get("room", "")) != fx[1]:
				errs.append("%s: %s must stand in %s (3.2)" % [label, fx[0], fx[1]])
			if not _has_service(view, fx[2], "TEACH"):
				errs.append("%s: entry master %s missing or has no TEACH (3.2)" % [label, fx[2]])
			var move_ok := false
			for aid in fx[3]:
				if not arts.has(aid):
					errs.append("%s: entry art %s missing (3.2)" % [label, aid])
					continue
				for c in arts[aid].get("requires", []):
					var bad := false
					if c is Dictionary and c.get("type", "") == "any_of":
						for opt in c.get("options", []):
							for c2 in opt:
								if not (c2 is Dictionary) or c2.get("type", "") != "sect":
									bad = true
					elif not (c is Dictionary) or c.get("type", "") != "sect":
						bad = true
					if bad:
						errs.append("%s: entry art %s may only require sect (3.2): %s" % [label, aid, str(c)])
				for mv in arts[aid].get("moves", []):
					if mv is Dictionary and mv.get("id", "") == fx[4]:
						move_ok = true
						if int(mv.get("unlock_level", 0)) != 1 or not (mv.get("aoe", "SINGLE") in ["SINGLE", "CROSS"]) \
								or int(mv.get("range", 0)) < 1:
							errs.append("%s: acceptance move %s must be unlock 1, SINGLE/CROSS, range >= 1 (3.2)" % [label, fx[4]])
			if not move_ok:
				errs.append("%s: acceptance move %s not in entry arts (3.2)" % [label, fx[4]])
			var spar: Variant = npcs.get(fx[5], {}).get("fight", {})
			if not _has_service(view, fx[5], "FIGHT") or not (spar is Dictionary) or str(spar.get("monster", "")) != fx[6]:
				errs.append("%s: spar npc %s must FIGHT %s (3.2)" % [label, fx[5], fx[6]])
			if jail != fx[7]:
				errs.append("%s: jail_room must be '%s' (3.2)" % [label, fx[7]])
	return errs

# 8.5 #3
static func _c_sect_rules(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var tpl: Dictionary = view.get("text_templates", {})
	for rid in view.get("sect_rules", {}):
		var r: Dictionary = view["sect_rules"][rid]
		var label := "sect_rules.%s" % rid
		if not view.get("sects", {}).has(str(r.get("sect", ""))):
			errs.append("%s: sect '%s' missing" % [label, r.get("sect", "")])
		if not (r.get("tier", "") in DataSchema.SECT_RULE_TIERS):
			errs.append("%s: bad tier '%s'" % [label, r.get("tier", "")])
		match str(r.get("kind", "")):
			"STATE":
				if not (r.get("ok_if") is Array) or (r["ok_if"] as Array).is_empty():
					errs.append("%s: STATE rule needs ok_if" % label)
			"EVENT":
				var ev := str(r.get("event", ""))
				if not (ev in DataSchema.SECT_RULE_EVENTS):
					errs.append("%s: bad event '%s'" % [label, ev])
				elif ev == "ENTER_REGION" and not view.get("regions", {}).has(str(r.get("event_arg", ""))):
					errs.append("%s: ENTER_REGION event_arg '%s' is not a region" % [label, r.get("event_arg", "")])
			_:
				errs.append("%s: bad kind '%s'" % [label, r.get("kind", "")])
		# modes：適用的 sect_violation_mode（JAIL／BAN = 2001-11-15 以後的坐牢名單；EXPEL = 2001-08 叛派名單）
		var modes: Variant = r.get("modes", [])
		if not (modes is Array):
			errs.append("%s: modes must be an array" % label)
		else:
			for m in modes:
				if not (m in DataSchema.RULE_ENUMS["sect_violation_mode"]):
					errs.append("%s: bad mode '%s'" % [label, m])
		# on_npc：只在與這些 NPC 交談時檢查（STATE 才有意義）
		var on_npc: Variant = r.get("on_npc", [])
		if not (on_npc is Array):
			errs.append("%s: on_npc must be an array" % label)
		elif not (on_npc as Array).is_empty():
			if str(r.get("kind", "")) != "STATE":
				errs.append("%s: on_npc needs kind STATE" % label)
			for nid in on_npc:
				if not view.get("npcs", {}).has(str(nid)):
					errs.append("%s: on_npc '%s' missing" % [label, nid])
		var tk := str(r.get("text", ""))
		if not tpl.has(tk) or str(tpl[tk].get("self", "")) == "":
			errs.append("%s: text template '%s' missing" % [label, tk])
	return errs

# 8.5 #4
static func _c_arts_m3a(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var arts: Dictionary = view.get("martial_arts", {})
	var max_cap := {}
	for mid in view.get("masters", {}):
		var m: Dictionary = view["masters"][mid]
		var sid := str(m.get("skill_id", ""))
		max_cap[sid] = maxi(int(max_cap.get(sid, 0)), int(m.get("cap", 0)))
	var move_owner := {}
	for aid in arts:
		var a: Dictionary = arts[aid]
		var label := "martial_arts.%s" % aid
		var cat := str(a.get("category", ""))
		var tier := str(a.get("tier", "BASIC"))
		if not (tier in ART_TIERS):
			errs.append("%s: bad tier '%s'" % [label, tier])
		if tier == "QUEST" and conditions_of_type(a.get("requires", []), "quest_flag").is_empty():
			errs.append("%s: QUEST art needs a quest_flag condition" % label)
		for f in ART_CATEGORY_FIELDS:
			var v: Variant = a.get(f)
			if v != null:
				if not (v is Dictionary):
					errs.append("%s: %s must be an object or null" % [label, f])
				elif cat != ART_CATEGORY_FIELDS[f]:
					errs.append("%s: %s needs category %s (is %s)" % [label, f, ART_CATEGORY_FIELDS[f], cat])
		if cat == "FORMATION" and not bool(a.get("monster_only", false)):
			var fm: Variant = a.get("formation")
			if not (fm is Dictionary) or not (fm.get("stations") is Array) or int(fm.get("party_size", 0)) < 2 \
					or (fm["stations"] as Array).size() != int(fm.get("party_size", 0)):
				errs.append("%s: FORMATION needs formation{party_size >= 2, stations[party_size]}" % label)
		if a.has("acupoint") and typeof(a["acupoint"]) != TYPE_BOOL:
			errs.append("%s: acupoint must be a bool" % label)
		var moves: Array = a.get("moves", []) if a.get("moves") is Array else []
		if cat in ["POISON", "MEDIC", "HIDDEN"] and moves.is_empty():
			errs.append("%s: %s art needs at least one move (3.4)" % [label, cat])
		var cap := maxi(int(max_cap.get(aid, 0)), int(a.get("self_study_cap", 0)))
		var skip_cap := bool(a.get("monster_only", false)) or cap <= 0 or (tier == "QUEST" and int(max_cap.get(aid, 0)) <= 1)
		for mv in moves:
			if not (mv is Dictionary):
				errs.append("%s: move is not an object" % label)
				continue
			var mvid := str(mv.get("id", ""))
			if move_owner.has(mvid):
				errs.append("%s: duplicate move id %s (also in %s)" % [label, mvid, move_owner[mvid]])
			move_owner[mvid] = aid
			var power := int(mv.get("power", 0))
			if power > 0 and int(mv.get("cost_inner", 0)) * 2 > power:
				errs.append("%s: move %s cost_inner %d > power/2 (3.4)" % [label, mvid, int(mv.get("cost_inner", 0))])
			if str(mv.get("status", "")) != "" and float(mv.get("status_chance", 0.0)) > MOVE_STATUS_CHANCE_MAX + EPS:
				errs.append("%s: move %s status_chance > %.2f (3.4)" % [label, mvid, MOVE_STATUS_CHANCE_MAX])
			if tier == "BASIC" and not bool(a.get("monster_only", false)) and str(mv.get("aoe", "SINGLE")) != "SINGLE":
				var acap := roundi(basic_single_ref(int(mv.get("unlock_level", 1))) * AOE_POWER_MULT)
				if power > acap:
					errs.append("%s: area move %s power %d > %d (single ref × %.2f, 3.4)" % [label, mvid, power, acap, AOE_POWER_MULT])
			if int(mv.get("unlock_level", 0)) < 1:
				errs.append("%s: move %s unlock_level must be >= 1" % [label, mvid])
			elif not skip_cap and int(mv.get("unlock_level", 0)) > cap:
				errs.append("%s: move %s unlock_level %d > highest teach/self-study cap %d" % [label, mvid, int(mv["unlock_level"]), cap])
	return errs

## 入門武功單體招式的參考威力（依解鎖等級）
static func basic_single_ref(unlock: int) -> int:
	for p in BASIC_SINGLE_REF:
		if unlock >= int(p[0]):
			return int(p[1])
	return int(BASIC_SINGLE_REF[-1][1])

# 8.5 #8、#10
static func _c_rooms_m3a(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var idx := room_index(view)
	var sects: Dictionary = view.get("sects", {})
	var jail_rooms := {}
	for sid in sects:
		if str(sects[sid].get("jail_room", "")) != "":
			jail_rooms[str(sects[sid]["jail_room"])] = sid
	for rid in idx:
		var room: Dictionary = idx[rid]["room"]
		if room.has("jail"):
			if typeof(room["jail"]) != TYPE_BOOL:
				errs.append("room %s: jail must be a bool" % rid)
			elif room["jail"] and not jail_rooms.has(rid) and str(room.get("jail_scope", "SECT")) != "CAPITAL":
				errs.append("room %s: jail:true but no sect uses it as jail_room" % rid)
		if room.has("encounter_exempt"):
			if not (room["encounter_exempt"] is Array):
				errs.append("room %s: encounter_exempt must be an array" % rid)
			else:
				for s in room["encounter_exempt"]:
					if not sects.has(s):
						errs.append("room %s: encounter_exempt sect '%s' missing" % [rid, s])
		if room.has("meditate"):
			var md: Variant = room["meditate"]
			if not (md is Dictionary) or not (typeof(md.get("mult")) in [TYPE_INT, TYPE_FLOAT]) or float(md.get("mult", 0)) <= 0.0 \
					or not (typeof(md.get("drain_pct", 0.0)) in [TYPE_INT, TYPE_FLOAT]) \
					or float(md.get("drain_pct", 0.0)) < 0.0 or float(md.get("drain_pct", 0.0)) > 1.0:
				errs.append("room %s: meditate must be { mult > 0, drain_pct 0..1 }" % rid)
	for rid in M3A_REST_ROOMS:
		if not idx.has(rid):
			errs.append("rest room %s missing (2.3)" % rid)
			continue
		var enc: Variant = idx[rid]["room"].get("encounter")
		if enc is Dictionary and float(enc.get("rate", 0.0)) > 0.0:
			errs.append("rest room %s must not have encounters (2.3)" % rid)
		var inn := false
		for nid in idx[rid]["room"].get("npcs", []):
			var n: Dictionary = view.get("npcs", {}).get(nid, {})
			if "INN" in n.get("services", []) and int(n.get("inn_price", -1)) >= 10 and int(n.get("inn_price", -1)) <= 20:
				inn = true
		if not inn:
			errs.append("rest room %s needs an INN npc with inn_price 10..20 (2.3)" % rid)
	return errs

# 8.5 #11：所有表與地圖的字串值不得含常見簡體字
static func _c_simplified(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	for t in view:
		if t == "maps":
			for rid in view["maps"]:
				_scan_simplified(view["maps"][rid], "maps/%s" % rid, errs)
		elif view[t] is Dictionary:
			for id in view[t]:
				_scan_simplified(view[t][id], "%s.%s" % [t, id], errs)
	return errs

static func _scan_simplified(node: Variant, label: String, errs: PackedStringArray) -> void:
	if node is String:
		for ch in node:
			if ch in SIMPLIFIED_CHARS:
				errs.append("%s: simplified character '%s' in \"%s\"" % [label, ch, node.left(40)])
				return
	elif node is Dictionary:
		for k in node:
			_scan_simplified(node[k], label, errs)
	elif node is Array:
		for v in node:
			_scan_simplified(v, label, errs)

# ============================================================================
# 故事包檢查（STORY_PLAN §8.5）。check_content() 會呼叫 check_story()。
# ============================================================================
## §5.4：永不受善惡／名聲反應影響的服務
const REACTION_NEVER_SERVICES := ["RESPAWN", "TRAVEL", "QUEST", "TEACH", "JOIN", "JAIL", "GUIDE"]
## §2.3：新地區的休息點／入口，從出生城走過去也要符合 WORLD_2001 §1.4 新手規則（newbie_routes 會加進去）
const STORY_ROUTE_TARGETS := ["hn_teahouse", "ym_gate",
	# M3B_PLAN §3.4：絕情谷谷口、高昌古道的駝隊歇腳處（新地區入口）
	"jq_gukou", "gc_road2"]
## §8.5 #4：log 裡表示時段的字詞（時辰字要接「時／刻／、」等才算，避免「公子」「弟子」誤判）
const TIME_WORDS := ["黃昏", "傍晚", "清晨", "天亮", "白天", "白日", "夜裡", "夜間", "入夜", "天黑", "深夜", "半夜", "午夜", "正午", "日落", "日出"]
const SHICHEN_SUFFIX := ["時", "刻", "、", "到", "至", "～", "或", "和"]
## §8.5 #6：故事包負責的解鎖旗標（§1.1 門派表、§3.5 新增）一定要有任務會設，否則是錯誤；
## 其他武功旗標（M3a 留下、本包範圍外的任務，如師命難違、1.0B 鐵指環）沒有任務設時只印 warning（check_story_warnings）
const STORY_UNLOCK_FLAGS := ["wd_q_yinliu", "wd_q_heiyu", "wd_q_longmen", "wd_q_yitian", "wd_q_taiji", "em_shougongsha",
	"em_miejian_ok", "xd_xuehai_lv1", "hs_qizong", "hs_jianzong", "hs_zixia_ok", "xh_huagong_ok", "sl_riyuebian_ok"]

static func check_story(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	errs.append_array(_s_quest_reach(view))
	errs.append_array(_s_appear(view))
	errs.append_array(_s_drops(view))
	errs.append_array(_s_flags(view))
	errs.append_array(_s_wanderers(view))
	errs.append_array(_s_reactions(view))
	errs.append_array(_s_rumors_ambient(view))
	errs.append_array(_s_test_plan(view))
	errs.append_array(_s_quest_refs(view))
	errs.append_array(_s_outcome_src(view))
	var idx := room_index(view)
	for rid in idx:
		if idx[rid]["room"].has("safe") and typeof(idx[rid]["room"]["safe"]) != TYPE_BOOL:
			errs.append("room %s: safe must be a bool" % rid)
	return errs

## 第 2 版（非舊格式正規化）的任務 id，排序
static func story_quests(view: Dictionary) -> Array:
	var out: Array = []
	for qid in view.get("quests", {}):
		var q: Dictionary = view["quests"][qid]
		if not bool(q.get("_legacy", false)) and q.get("stages") is Array:
			out.append(qid)
	out.sort()
	return out

## 條件能不能在「做這條任務」的情境下成立：本任務的 quest_active／quest_stage／quest_var 一定能成立；
## 其他條件要原樣出現在任務的 requires 裡（例：sect huashan 的房間 ↔ 任務限華山派）
static func cond_satisfiable_in_quest(c: Variant, q: Dictionary) -> bool:
	if not (c is Dictionary):
		return false
	var t := str(c.get("type", ""))
	if t in ["quest_active", "quest_stage", "quest_var"] and str(c.get("quest", "")) == str(q.get("id", "")):
		return true
	if t == "any_of":
		for opt in c.get("options", []):
			var ok := true
			for c2 in opt:
				if not cond_satisfiable_in_quest(c2, q):
					ok = false
			if ok:
				return true
		return false
	for r in q.get("requires", []):
		if r is Dictionary and r == c:
			return true
	return false

## 走路圖：有 requires 的房間只有在條件都能於任務情境成立時才走得進去（§8.5 #3）
static func quest_room_graph(view: Dictionary, q: Dictionary) -> Dictionary:
	var idx := room_index(view)
	var g := room_graph(view)
	var blocked := {}
	for rid in idx:
		for c in idx[rid]["room"].get("requires", []):
			if not cond_satisfiable_in_quest(c, q):
				blocked[rid] = true
	var out := {}
	for rid in g:
		var nb: Array = []
		if not blocked.has(rid):
			for n in g[rid]:
				if not blocked.has(n):
					nb.append(n)
		out[rid] = nb
	return out

## 一條任務會用到的地點：[{where, room}]（給予者、目標 NPC、REACH／ESCORT 房間、房間動作）
static func quest_places(view: Dictionary, q: Dictionary) -> Array:
	var out: Array = []
	var npcs: Dictionary = view.get("npcs", {})
	var giver := str(q.get("giver", ""))
	if npcs.has(giver):
		out.append({ "where": "giver " + giver, "room": str(npcs[giver].get("room", "")) })
	for s in q.get("stages", []):
		if not (s is Dictionary):
			continue
		for o in s.get("objectives", []):
			if not (o is Dictionary):
				continue
			var n := str(o.get("npc", ""))
			# 不站在房間裡的護送 NPC（鏢車，M3B_PLAN §4.9）跟著玩家走，不算地點
			if n != "" and npcs.has(n) and not (str(o.get("type", "")) == "ESCORT" and str(npcs[n].get("room", "")) == ""):
				out.append({ "where": "%s.%s npc %s" % [s.get("id", ""), o.get("id", ""), n], "room": str(npcs[n].get("room", "")) })
			for rk in ["room", "to_room"]:
				if str(o.get(rk, "")) != "":
					out.append({ "where": "%s.%s %s" % [s.get("id", ""), o.get("id", ""), rk], "room": str(o[rk]) })
		for a in s.get("room_actions", []):
			if a is Dictionary and str(a.get("room", "")) != "":
				out.append({ "where": "%s room action %s" % [s.get("id", ""), a.get("id", "")], "room": str(a["room"]) })
	return out

# #3：每個任務地點從兩座出生城走得到（S6；requires 房間要在任務情境可滿足）
static func _s_quest_reach(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var idx := room_index(view)
	var births := birth_rooms(view)
	for qid in story_quests(view):
		var q: Dictionary = view["quests"][qid]
		var g := quest_room_graph(view, q)
		var seen_from := {}
		for br in births:
			seen_from[br] = _bfs(g, br, "")["seen"]
		for p in quest_places(view, q):
			var room := str(p["room"])
			if not idx.has(room):
				errs.append("quests.%s: %s room '%s' missing" % [qid, p["where"], room])
				continue
			for br in births:
				if not seen_from[br].has(room):
					errs.append("quests.%s: %s room %s not reachable on foot from %s (S6)" % [qid, p["where"], room, br])
	return errs

static func log_mentions_time(text: String) -> bool:
	for w in TIME_WORDS:
		if text.contains(w):
			return true
	for h in SHICHEN:
		for suf in SHICHEN_SUFFIX:
			if text.contains(h + suf):
				return true
		if text.contains("、" + h):
			return true
	return false

# #4：appear 合法；有時辰限制的目標 NPC（appear.hours 或目標 hours），階段 log 要提到時辰
static func _s_appear(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var npcs: Dictionary = view.get("npcs", {})
	for nid in npcs:
		var ap: Variant = npcs[nid].get("appear")
		if ap == null:
			continue
		if not (ap is Dictionary):
			errs.append("npcs.%s: appear must be an object" % nid)
			continue
		var hs: Variant = ap.get("hours", [])
		if not (hs is Array):
			errs.append("npcs.%s: appear.hours must be an array" % nid)
		else:
			for h in hs:
				if not (str(h) in SHICHEN):
					errs.append("npcs.%s: appear.hours bad shichen '%s'" % [nid, str(h)])
		errs.append_array(DataSchema.check_conditions(ap.get("requires", []), "npcs.%s.appear.requires" % nid))
	for qid in story_quests(view):
		var q: Dictionary = view["quests"][qid]
		for s in q.get("stages", []):
			if not (s is Dictionary):
				continue
			for o in s.get("objectives", []):
				if not (o is Dictionary) or str(o.get("type", "")) == "WAIT":
					continue
				var limited := false
				if o.get("hours") is Array and not (o["hours"] as Array).is_empty():
					limited = true
				var n := str(o.get("npc", ""))
				if n != "" and npcs.has(n) and npcs[n].get("appear") is Dictionary:
					var ah: Variant = npcs[n]["appear"].get("hours", [])
					if ah is Array and not (ah as Array).is_empty() and (ah as Array).size() < SHICHEN.size():
						limited = true
				if limited and not log_mentions_time(str(s.get("log", ""))):
					errs.append("quests.%s.%s: objective %s is time-limited but the stage log names no time (§7.2 #4)" % [qid, s.get("id", ""), o.get("id", "")])
	return errs

# #5：任務物品的掉落一定要有 requires、而且必掉（chance 100；1.0 等效）
static func _s_drops(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var items: Dictionary = view.get("items", {})
	for mid in view.get("monsters", {}):
		for d in view["monsters"][mid].get("drops", []):
			if not (d is Dictionary):
				continue
			if d.has("requires"):
				errs.append_array(DataSchema.check_conditions(d["requires"], "monsters.%s.drops.%s.requires" % [mid, d.get("item", "")]))
			var it: Dictionary = items.get(str(d.get("item", "")), {})
			if not bool(it.get("quest_item", false)):
				continue
			if not (d.get("requires") is Array) or (d["requires"] as Array).is_empty():
				errs.append("monsters.%s: quest item drop %s needs requires (§3.4)" % [mid, d.get("item", "")])
			if float(d.get("chance", 0.0)) < 1.0:
				errs.append("monsters.%s: quest item drop %s must be guaranteed (chance 100)" % [mid, d.get("item", "")])
	return errs

## 任務會設定的旗標（flag 動作、獎勵 flags）＋門派試煉的 reward_flag
static func flags_set_somewhere(view: Dictionary) -> Dictionary:
	var out := {}
	for qid in view.get("quests", {}):
		var q: Dictionary = view["quests"][qid]
		var legacy_rw: Variant = q.get("rewards", {})
		if legacy_rw is Dictionary:
			for f in legacy_rw.get("flags", []):
				out[str(f)] = true
		var ocs: Variant = q.get("outcomes", {})
		if ocs is Dictionary:
			for k in ocs:
				var rw: Variant = ocs[k].get("rewards", {}) if ocs[k] is Dictionary else {}
				if rw is Dictionary:
					for f in rw.get("flags", []):
						out[str(f)] = true
		for a in QuestDef._all_actions(q):
			match str(a.get("do", "")):
				"flag":
					out[str(a.get("flag", ""))] = true
				"reward":
					var rw2: Variant = a.get("rewards", a)
					if rw2 is Dictionary:
						for f in rw2.get("flags", []):
							out[str(f)] = true
	for nid in view.get("npcs", {}):
		var tr: Variant = view["npcs"][nid].get("trial")
		if tr is Dictionary and str(tr.get("reward_flag", "")) != "":
			out[str(tr["reward_flag"])] = true
	return out

# #6：martial_arts 的 quest_flag 都至少有一條任務（或試煉）會設
static func _s_flags(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var set_flags := flags_set_somewhere(view)
	for aid in view.get("martial_arts", {}):
		for c in conditions_of_type(view["martial_arts"][aid].get("requires", []), "quest_flag"):
			var f := str(c.get("flag", ""))
			if f in STORY_UNLOCK_FLAGS and not set_flags.has(f):
				errs.append("martial_arts.%s: quest_flag '%s' is never set by any quest (§8.5 #6)" % [aid, f])
	for f in STORY_UNLOCK_FLAGS:
		if not set_flags.has(f):
			errs.append("story unlock flag '%s' is never set by any quest (§1.1、§3.5)" % f)
	return errs

## warning（不擋 lint）：武功鎖的旗標沒有任何任務或試煉會設（本包範圍外的內容）；
## 房間 requires 指到還沒合併的任務（例：xx_palace_mishi ↔ q_yangkang，ev_yangkang 碎片未交付）
static func check_story_warnings(view: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var idx := room_index(view)
	for rid in idx:
		var bad := PackedStringArray()
		_collect_quest_ref_errors(idx[rid]["room"].get("requires", []), view, "room %s.requires" % rid, bad)
		for e in bad:
			out.append(e + " (room stays closed until that quest exists)")
	var set_flags := flags_set_somewhere(view)
	for aid in view.get("martial_arts", {}):
		for c in conditions_of_type(view["martial_arts"][aid].get("requires", []), "quest_flag"):
			var f := str(c.get("flag", ""))
			if not set_flags.has(f) and not (f in STORY_UNLOCK_FLAGS):
				out.append("martial_arts.%s: quest_flag '%s' is not set by any quest or trial yet" % [aid, f])
	return out

# #7：遊蕩惡人
static func _s_wanderers(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var idx := room_index(view)
	var regions: Dictionary = view.get("regions", {})
	for wid in view.get("wanderers", {}):
		var w: Dictionary = view["wanderers"][wid]
		var label := "wanderers.%s" % wid
		if not idx.has(str(w.get("home_room", ""))):
			errs.append("%s: home_room '%s' missing" % [label, w.get("home_room", "")])
		if not view.get("monsters", {}).has(str(w.get("monster", ""))):
			errs.append("%s: monster '%s' missing" % [label, w.get("monster", "")])
		if not view.get("npcs", {}).has(str(w.get("npc", ""))):
			errs.append("%s: npc '%s' missing" % [label, w.get("npc", "")])
		var sched: Variant = w.get("schedule", [])
		if not (sched is Array) or (sched as Array).is_empty():
			errs.append("%s: schedule[] missing" % label)
			continue
		for e in sched:
			if not (e is Dictionary):
				errs.append("%s: schedule entry is not an object" % label)
				continue
			if not (str(e.get("mode", "")) in ["HOME", "ROAM"]):
				errs.append("%s: schedule mode '%s' not HOME/ROAM" % [label, e.get("mode", "")])
			for h in e.get("hours", []):
				if not (str(h) in SHICHEN):
					errs.append("%s: schedule bad shichen '%s'" % [label, str(h)])
			for r in e.get("regions", []):
				if not regions.has(str(r)):
					errs.append("%s: region '%s' missing" % [label, r])
				elif str(regions[r].get("type", "")) in ["CITY", "SECT"]:
					errs.append("%s: roams into %s region %s" % [label, regions[r]["type"], r])
		for k in ["aggro", "talk_fight"]:
			if w.get(k) is Dictionary:
				errs.append_array(DataSchema.check_conditions(w[k].get("requires", []), "%s.%s.requires" % [label, k]))
	return errs

static func _s_reactions(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var tpl: Dictionary = view.get("text_templates", {})
	for rid in view.get("reactions", {}):
		var r: Dictionary = view["reactions"][rid]
		for s in r.get("services", []):
			if str(s) in REACTION_NEVER_SERVICES:
				errs.append("reactions.%s: service %s must never be affected (§5.4)" % [rid, s])
		errs.append_array(DataSchema.check_conditions(r.get("when", []), "reactions.%s.when" % rid))
		for k in ["greet", "refuse"]:
			if str(r.get(k, "")) != "" and not tpl.has(str(r[k])):
				errs.append("reactions.%s: %s template '%s' missing" % [rid, k, r[k]])
	return errs

static func _s_rumors_ambient(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var tpl: Dictionary = view.get("text_templates", {})
	var idx := room_index(view)
	for rid in view.get("rumors", {}):
		var r: Dictionary = view["rumors"][rid]
		if not tpl.has(str(r.get("text", ""))):
			errs.append("rumors.%s: text template '%s' missing" % [rid, r.get("text", "")])
		for h in r.get("hours", []):
			if not (str(h) in SHICHEN):
				errs.append("rumors.%s: bad shichen '%s'" % [rid, str(h)])
	for aid in view.get("ambient", {}):
		var a: Dictionary = view["ambient"][aid]
		# 交談列（審查修正：NPC 依任務進度與結局換話）：talk 模板 + npc 必填，不是環境句
		if str(a.get("talk", "")) != "":
			if not tpl.has(str(a["talk"])):
				errs.append("ambient.%s: talk template '%s' missing" % [aid, a["talk"]])
			if str(a.get("npc", "")) == "" or not view.get("npcs", {}).has(str(a["npc"])):
				errs.append("ambient.%s: talk row needs an existing npc ('%s')" % [aid, a.get("npc", "")])
			errs.append_array(DataSchema.check_conditions(a.get("requires", []), "ambient.%s.requires" % aid))
			continue
		if not tpl.has(str(a.get("text", ""))):
			errs.append("ambient.%s: text template '%s' missing" % [aid, a.get("text", "")])
		if str(a.get("room", "")) != "" and not idx.has(str(a["room"])):
			errs.append("ambient.%s: room '%s' missing" % [aid, a["room"]])
		if str(a.get("region", "")) != "" and not view.get("regions", {}).has(str(a["region"])):
			errs.append("ambient.%s: region '%s' missing" % [aid, a["region"]])
		if str(a.get("npc", "")) != "" and not view.get("npcs", {}).has(str(a["npc"])):
			errs.append("ambient.%s: npc '%s' missing" % [aid, a["npc"]])
		errs.append_array(DataSchema.check_conditions(a.get("requires", []), "ambient.%s.requires" % aid))
	for qid in view.get("quests", {}):
		var rm: Variant = view["quests"][qid].get("rumors", {})
		if rm is Dictionary:
			for k in rm:
				if str(rm[k]) != "" and not tpl.has(str(rm[k])):
					errs.append("quests.%s: rumors.%s template '%s' missing" % [qid, k, rm[k]])
	return errs

## 審查修正：故事任務的每個結局都要標 src（verified／later／proposal）；field_src 逐欄覆寫，
## 欄位名要是獎勵欄位、值要是合法的 src。這樣混了後期數字或【設計提案】數值的結局不會只藏在自由文字的 src_note 裡。
static func _s_outcome_src(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	for qid in story_quests(view):
		var q: Dictionary = view["quests"][qid]
		for oc in q.get("outcomes", {}):
			var o: Variant = q["outcomes"][oc]
			if not (o is Dictionary):
				continue
			var L := "quests.%s.outcomes.%s" % [qid, oc]
			if not (str(o.get("src", "")) in QuestDef.SRC_TAGS):
				errs.append("%s: src must be one of %s (got '%s')" % [L, str(QuestDef.SRC_TAGS), str(o.get("src", ""))])
			var fs: Variant = o.get("field_src", {})
			if not (fs is Dictionary):
				errs.append("%s: field_src must be an object" % L)
				continue
			var rw: Variant = o.get("rewards", {})
			for k in fs:
				if not (str(k) in QuestDef.REWARD_KEYS):
					errs.append("%s: field_src key '%s' is not a reward field" % [L, k])
				elif not (rw is Dictionary) or not (rw as Dictionary).has(str(k)):
					errs.append("%s: field_src key '%s' not in rewards" % [L, k])
				if not (str(fs[k]) in QuestDef.SRC_TAGS):
					errs.append("%s: field_src.%s must be one of %s" % [L, k, str(QuestDef.SRC_TAGS)])
	return errs

# #10：故事任務的 test_plan 涵蓋每個結局
static func _s_test_plan(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	for qid in story_quests(view):
		var q: Dictionary = view["quests"][qid]
		# M3c2 WP-PACE：門派雜務（group sect_chores）是可重複的短工作，由 test_m3c2_chores 與 m3c2_acceptance chores 覆蓋，不寫 test_plan
		if str(q.get("group", "")) == M3C2_CHORE_GROUP:
			continue
		var covered := {}
		var tp: Variant = q.get("test_plan", [])
		if tp is Array:
			for e in tp:
				if e is Dictionary:
					covered[str(e.get("outcome", QuestDef.DEFAULT_OUTCOME))] = true
		for oc in q.get("outcomes", {}):
			if not covered.has(str(oc)):
				errs.append("quests.%s: test_plan has no path for outcome '%s' (§8.5 #10)" % [qid, oc])
	return errs

const QUEST_REF_TYPES := ["quest_active", "quest_stage", "quest_var", "quest_outcome", "quest_done", "quest_not_done",
	"quest_not_active"]

## 條件裡指到的任務／階段／結局要存在（quest_active、quest_stage、quest_var、quest_outcome、quest_done）
static func _collect_quest_ref_errors(node: Variant, view: Dictionary, label: String, errs: PackedStringArray) -> void:
	if node is Array:
		for v in node:
			_collect_quest_ref_errors(v, view, label, errs)
		return
	if not (node is Dictionary):
		return
	var t := str(node.get("type", ""))
	if t in QUEST_REF_TYPES and node.has("quest"):
		var qid := str(node.get("quest", ""))
		var quests: Dictionary = view.get("quests", {})
		if not quests.has(qid):
			errs.append("%s: %s refers to unknown quest '%s'" % [label, t, qid])
		else:
			var q: Dictionary = quests[qid]
			if t == "quest_stage":
				var st: Variant = node.get("stage", "")
				var want: Array = st if st is Array else [st]
				for sid in want:
					if QuestDef.stage(q, str(sid)).is_empty():
						errs.append("%s: quest_stage %s has no stage '%s'" % [label, qid, str(sid)])
			elif t == "quest_outcome" and not q.get("outcomes", {}).has(str(node.get("outcome", ""))):
				errs.append("%s: quest_outcome %s has no outcome '%s'" % [label, qid, str(node.get("outcome", ""))])
		return
	for k in node:
		if node[k] is Array or node[k] is Dictionary:
			_collect_quest_ref_errors(node[k], view, label, errs)

# 條件裡的任務參照（任務列、NPC appear、怪物掉落、遊蕩惡人、傳聞、環境句）
static func _s_quest_refs(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	for qid in view.get("quests", {}):
		var q: Dictionary = view["quests"][qid]
		var clean := q.duplicate()
		clean.erase("test_plan")
		_collect_quest_ref_errors(clean, view, "quests.%s" % qid, errs)
	for nid in view.get("npcs", {}):
		_collect_quest_ref_errors(view["npcs"][nid].get("appear", {}), view, "npcs.%s.appear" % nid, errs)
	for mid in view.get("monsters", {}):
		_collect_quest_ref_errors(view["monsters"][mid].get("drops", []), view, "monsters.%s.drops" % mid, errs)
	for t in ["wanderers", "ambient", "reactions"]:
		for id in view.get(t, {}):
			_collect_quest_ref_errors(view[t][id], view, "%s.%s" % [t, id], errs)
	for rid in view.get("rumors", {}):
		var r: Dictionary = view["rumors"][rid]
		var rw: Variant = r.get("requires_world", {})
		if rw is Dictionary and str(rw.get("not_first", "")) != "" and not view.get("quests", {}).has(str(rw["not_first"])):
			errs.append("rumors.%s: requires_world.not_first unknown quest '%s'" % [rid, rw["not_first"]])
	return errs

# ============================================================================
# M3b 檢查（M3B_PLAN §9.5，WP-MERGE）。check_content() 會呼叫 check_m3b()；
# era 一致性（§9.5 #9）要看全部 era 的原始資料，在 lint() 的 _check_m3b_raw() 裡。
# ============================================================================
## §3.4 #2、#5、#6、§9.5 #8：只能放這些怪的房間（房間存在時才檢查）
const M3B_ROOM_ONLY := {
	"jcn_road1": ["m_rabbit", "m_bigrabbit", "m_jc_qigaitou", "m_jc_buliang"],
	"jcn_road2": ["m_rabbit", "m_bigrabbit", "m_jc_qigaitou", "m_jc_buliang"],
	"jcn_road3": ["m_rabbit", "m_bigrabbit", "m_jc_qigaitou", "m_jc_buliang", "m_wolf"],
	"jq_road1": ["m_rabbit", "m_bigrabbit", "m_jc_qigaitou", "m_jc_buliang", "m_wolf"],
	"jq_gukou": ["m_rabbit", "m_bigrabbit", "m_jc_qigaitou", "m_jc_buliang", "m_wolf"],
	"gc_road1": ["m_rabbit", "m_bigrabbit", "m_wolf"],
}
## §3.4 #4、#6：遇敵率上限
const M3B_ROOM_RATE_MAX := { "jcn_road4": 0.20, "jcn_kongdi": 0.30, "gc_road2": 0.0 }
## §3.4 #7：京城北門、南門外 1 步內不放 m_bandit 等級以上的怪
const M3B_CAPITAL_GATES := ["jc_gate_n", "jc_gate_s"]
## Protocol §6 的 M3b 事件中要有模板的（ui 事件、有退回模板的 jail_*_capital 不列）
const M3B_EVENTS := ["beg", "sect_assembly", "sect_rank_up", "rank_wait", "seize_start", "seize_done", "shop_refused",
	"harass", "condition_on", "bank_put", "bank_take", "bank_money", "consign_sent", "consign_arrived", "consign_taken",
	"consign_returned", "hunt_start", "org_petition", "org_signed", "org_founded", "org_petition_expired", "org_joined",
	"org_left", "org_kicked", "org_rank_changed", "org_title_changed", "org_leader_changed", "org_disbanded"]

static func check_m3b(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	errs.append_array(_m3b_sects_and_ranks(view))
	errs.append_array(_m3b_conditions(view))
	errs.append_array(_m3b_rooms(view))
	errs.append_array(_m3b_escort_routes(view))
	errs.append_array(_m3b_life_chain(view))
	errs.append_array(_m3b_quests_items(view))
	var tpl: Dictionary = view.get("text_templates", {})
	for r in Protocol.M3B_REASONS:
		_need_template(tpl, "err_" + str(r), ["self"], errs)
	for k in M3B_EVENTS:
		# 捉拿公敵是 1.0B（模板 era 1.0B）：1.0A 視圖不要求
		if str(k).begins_with("seize_") and not view.get("regions", {}).has("jingcheng"):
			continue
		_need_template(tpl, k, ["self"], errs)
	return errs

# #2、#3：門派新欄位與位階表
static func _m3b_sects_and_ranks(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var sects: Dictionary = view.get("sects", {})
	var ranks: Dictionary = view.get("sect_ranks", {})
	var regions: Dictionary = view.get("regions", {})
	var by_sect := {}
	for rid in ranks:
		var r: Dictionary = ranks[rid]
		var label := "sect_ranks.%s" % rid
		for f in DataSchema.REQUIRED_FIELDS["sect_ranks"]:
			if not r.has(f):
				errs.append("%s: missing field '%s'" % [label, f])
		var sid := str(r.get("sect", ""))
		by_sect.get_or_add(sid, []).append(int(r.get("rank", -1)))
		var promote := str(r.get("promote", ""))
		if not (promote in DataSchema.RANK_PROMOTES):
			errs.append("%s: promote '%s' not in %s" % [label, promote, DataSchema.RANK_PROMOTES])
		var cost: Variant = r.get("cost", {})
		if not (cost is Dictionary):
			errs.append("%s: cost must be an object" % label)
		else:
			for k in cost:
				if not (str(k) in DataSchema.RANK_COST_KEYS):
					errs.append("%s: cost key '%s' not in %s" % [label, k, DataSchema.RANK_COST_KEYS])
				elif typeof(cost[k]) != TYPE_INT or int(cost[k]) < 0:
					errs.append("%s: cost.%s must be an int >= 0" % [label, k])
		errs.append_array(check_conditions(r.get("requires", []), label + ".requires"))
		if r.has("assembly") and typeof(r["assembly"]) != TYPE_BOOL:
			errs.append("%s: assembly must be a bool" % label)
		if promote == "QUEST":
			var qid := str(r.get("quest", ""))
			if not view.get("quests", {}).has(qid):
				errs.append("%s: QUEST promote needs an active quest (got '%s')" % [label, qid])
			elif not _quest_grants_rank(view["quests"][qid], sid, int(r.get("rank", -1))):
				errs.append("%s: quest %s never rewards sect_rank {%s, %d}" % [label, qid, sid, int(r.get("rank", -1))])
	for sid in by_sect:
		var lv: Array = by_sect[sid]
		lv.sort()
		for i in lv.size():
			if int(lv[i]) != i:
				errs.append("sect_ranks: sect %s ranks must run 0..n without gaps (got %s)" % [sid, str(lv)])
				break
	for sid in sects:
		var s: Dictionary = sects[sid]
		var label := "sects.%s" % sid
		var rk := str(s.get("ranks", ""))
		if rk != "" and not by_sect.has(rk):
			errs.append("%s: ranks '%s' has no active sect_ranks rows" % [label, rk])
		for f in ["no_escort", "respawn_at_gate"]:
			if s.has(f) and typeof(s[f]) != TYPE_BOOL:
				errs.append("%s: %s must be a bool" % [label, f])
		var pr: Variant = s.get("practice")
		if pr != null:
			if not (pr is Dictionary):
				errs.append("%s: practice must be an object or null" % label)
			else:
				if str(pr.get("verb", "")) == "" or str(pr.get("target", "")) != "NPC":
					errs.append("%s: practice needs verb and target NPC" % label)
				var pp: Variant = pr.get("prof", [])
				if not (pp is Array) or pp.size() != 2 or int(pp[0]) < 1 or int(pp[1]) < int(pp[0]):
					errs.append("%s: practice.prof must be [min,max] with 1 <= min <= max" % label)
				if not (pr.get("cost") is Dictionary):
					errs.append("%s: practice.cost must be an object" % label)
				else:
					for k in pr["cost"]:
						if not (str(k) in ["jing", "shen", "neili"]):
							errs.append("%s: practice.cost key '%s'" % [label, k])
				if typeof(pr.get("per_npc_cd_s", 0)) != TYPE_INT or int(pr.get("per_npc_cd_s", 0)) < 0:
					errs.append("%s: practice.per_npc_cd_s must be an int >= 0" % label)
				for a in pr.get("alms", []):
					if not (a is Dictionary) or float(a.get("chance", 0.0)) <= 0.0 or float(a.get("chance", 0.0)) > 1.0:
						errs.append("%s: practice.alms %s chance must be in (0,1]" % [label, str(a)])
					elif a.has("item") and not view.get("items", {}).has(str(a["item"])):
						errs.append("%s: practice.alms item '%s' missing" % [label, a["item"]])
				for k2 in pr.get("npc_kinds", []):
					if not (str(k2) in NPC_KINDS):
						errs.append("%s: practice.npc_kinds '%s' not in %s" % [label, k2, NPC_KINDS])
		var hr: Variant = s.get("harass", [])
		if not (hr is Array):
			errs.append("%s: harass must be an array" % label)
		else:
			for h in hr:
				if not (h is Dictionary) or not (h.get("regions") is Dictionary):
					errs.append("%s: harass row needs regions{}" % label)
					continue
				for reg in h["regions"]:
					if str(regions.get(reg, {}).get("type", "")) != "CITY":
						errs.append("%s: harass region '%s' is not an active CITY" % [label, reg])
					var p := float(h["regions"][reg])
					if p < 0.0 or p > 1.0:
						errs.append("%s: harass chance for %s must be in [0,1]" % [label, reg])
				if not view.get("monsters", {}).has(str(h.get("monster", ""))):
					errs.append("%s: harass monster '%s' missing" % [label, h.get("monster", "")])
				var c: Variant = h.get("count", [1, 1])
				if not (c is Array) or c.size() != 2 or int(c[0]) < 1 or int(c[1]) < int(c[0]) or int(c[1]) > 4:
					errs.append("%s: harass count must be [a,b] with 1 <= a <= b <= 4" % label)
				errs.append_array(check_conditions(h.get("unless", []), label + ".harass.unless"))
	return errs

## 任務的某個結局（或 reward 動作）給 sect_rank {sect, rank}
static func _quest_grants_rank(q: Dictionary, sect: String, rank: int) -> bool:
	for rw in _quest_reward_dicts(q):
		if rw is Dictionary and rw.get("sect_rank") is Dictionary:
			if str(rw["sect_rank"].get("sect", "")) == sect and int(rw["sect_rank"].get("rank", -1)) == rank:
				return true
	return false

static func _quest_reward_dicts(q: Dictionary) -> Array:
	var rws: Array = []
	var ocs: Variant = q.get("outcomes", {})
	if ocs is Dictionary:
		for k in ocs:
			if ocs[k] is Dictionary:
				rws.append(ocs[k].get("rewards", {}))
	for a in QuestDef._all_actions(q):
		if str(a.get("do", "")) == "reward":
			rws.append(a.get("rewards", a))
	return rws

# #1：新條件的欄位內容（sect_rank_min 指到有位階的門派；life_min 只收生活技能）
static func _m3b_conditions(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var found: Array = []
	for t in view:
		if t == "maps":
			for rid in view["maps"]:
				_collect_conds(view["maps"][rid], "maps/%s" % rid, found)
		elif view[t] is Dictionary:
			for id in view[t]:
				_collect_conds(view[t][id], "%s.%s" % [t, id], found)
	for pair in found:
		var c: Dictionary = pair[1]
		match str(c.get("type", "")):
			"sect_rank_min":
				var sid := str(c.get("sect", ""))
				if str(view.get("sects", {}).get(sid, {}).get("ranks", "")) == "":
					errs.append("%s: sect_rank_min sect '%s' is not an active sect with ranks" % [pair[0], sid])
			"life_min":
				if not view.get("life_skills", {}).has(str(c.get("skill", ""))):
					errs.append("%s: life_min skill '%s' is not an active life skill" % [pair[0], c.get("skill", "")])
			"sect_not":
				if not view.get("sects", {}).has(str(c.get("sect", ""))):
					errs.append("%s: sect_not sect '%s' is not an active sect" % [pair[0], c.get("sect", "")])
	return errs

static func _collect_conds(node: Variant, label: String, out: Array) -> void:
	if node is Dictionary:
		if str(node.get("type", "")) in ["sect_rank_min", "life_min", "sect_not"]:
			out.append([label, node])
		for k in node:
			if k != "test_plan":
				_collect_conds(node[k], label, out)
	elif node is Array:
		for v in node:
			_collect_conds(v, label, out)

# #4、#8：房間新欄位與 §3.4 的房間規則
static func _m3b_rooms(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var idx := room_index(view)
	var monsters: Dictionary = view.get("monsters", {})
	var capital := 0
	for rid in idx:
		var room: Dictionary = idx[rid]["room"]
		if room.has("jail_scope"):
			if not (str(room["jail_scope"]) in DataSchema.JAIL_SCOPES):
				errs.append("room %s: jail_scope '%s' not in %s" % [rid, room["jail_scope"], DataSchema.JAIL_SCOPES])
			elif str(room["jail_scope"]) == "CAPITAL":
				capital += 1
				if not bool(room.get("jail", false)):
					errs.append("room %s: jail_scope CAPITAL needs jail:true" % rid)
				var rel := str(room.get("jail_release_to", ""))
				if not idx.has(rel):
					errs.append("room %s: CAPITAL jail needs jail_release_to naming an active room (got '%s')" % [rid, rel])
		var feats: Array = room.get("features", []) if room.get("features") is Array else []
		var ht: Variant = room.get("hunt_table")
		if "HUNT" in feats:
			if not (ht is Array) or (ht as Array).is_empty():
				errs.append("room %s: HUNT needs hunt_table" % rid)
		elif ht != null:
			errs.append("room %s: hunt_table without HUNT feature" % rid)
		if ht is Array:
			for e in ht:
				if not (e is Dictionary) or not monsters.has(str(e.get("monster", ""))):
					errs.append("room %s: hunt_table monster %s missing" % [rid, str(e)])
					continue
				if not bool(monsters[e["monster"]].get("hunt", false)):
					errs.append("room %s: hunt_table monster %s is not hunt:true" % [rid, e["monster"]])
				if typeof(e.get("w")) != TYPE_INT or int(e["w"]) <= 0:
					errs.append("room %s: hunt_table weight for %s must be int > 0" % [rid, e["monster"]])
		var oes: Variant = room.get("on_enter_status")
		if oes != null:
			if not (oes is Dictionary) or not view.get("status_effects", {}).has(str(oes.get("status", ""))):
				errs.append("room %s: on_enter_status status missing" % rid)
			else:
				if float(oes.get("chance", 1.0)) <= 0.0 or float(oes.get("chance", 1.0)) > 1.0:
					errs.append("room %s: on_enter_status chance must be in (0,1]" % rid)
				errs.append_array(check_conditions(oes.get("unless", []), "room %s.on_enter_status.unless" % rid))
		if M3B_ROOM_ONLY.has(rid) and room.get("encounter") is Dictionary:
			for e in room["encounter"].get("table", []):
				if e is Dictionary and not (str(e.get("monster", "")) in M3B_ROOM_ONLY[rid]):
					errs.append("room %s: %s not allowed here (§3.4 only %s)" % [rid, e.get("monster", ""), str(M3B_ROOM_ONLY[rid])])
		if M3B_ROOM_RATE_MAX.has(rid):
			var rate := float(room["encounter"].get("rate", 0.0)) if room.get("encounter") is Dictionary else 0.0
			if rate > float(M3B_ROOM_RATE_MAX[rid]) + EPS:
				errs.append("room %s: encounter rate %.2f > %.2f (§3.4)" % [rid, rate, float(M3B_ROOM_RATE_MAX[rid])])
	if capital > 1:
		errs.append("rooms: %d jail_scope CAPITAL rooms (at most one, §4.4)" % capital)
	var bandit_ref := int(monsters.get("m_bandit", {}).get("combat_xp_ref", 1 << 30))
	for gate in M3B_CAPITAL_GATES:
		if not idx.has(gate):
			continue
		for ex in idx[gate]["room"].get("exits", []):
			var to := str(ex.get("to", "")) if ex is Dictionary else ""
			if not idx.has(to) or str(view.get("regions", {}).get(idx[to]["region"], {}).get("type", "")) == "CITY":
				continue
			var enc: Variant = idx[to]["room"].get("encounter")
			if enc is Dictionary:
				for e in enc.get("table", []):
					if e is Dictionary and int(monsters.get(str(e.get("monster", "")), {}).get("combat_xp_ref", 0)) >= bandit_ref:
						errs.append("room %s (1 step outside %s): %s is m_bandit-level or stronger (§3.4 #7)" % [to, gate, e["monster"]])
	return errs

# #6：鏢局路線
static func _m3b_escort_routes(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var regions: Dictionary = view.get("regions", {})
	var pairs := {}
	for rid in view.get("escort_routes", {}):
		var r: Dictionary = view["escort_routes"][rid]
		var label := "escort_routes.%s" % rid
		for f in DataSchema.REQUIRED_FIELDS["escort_routes"]:
			if not r.has(f):
				errs.append("%s: missing field '%s'" % [label, f])
		var a := str(r.get("from_city", ""))
		var b := str(r.get("to_city", ""))
		for c in [a, b]:
			if str(regions.get(c, {}).get("type", "")) != "CITY":
				errs.append("%s: '%s' is not an active CITY region" % [label, c])
		if a == b:
			errs.append("%s: from_city == to_city" % label)
		var key := a + ">" + b
		if pairs.has(key):
			errs.append("%s: route %s already defined by %s" % [label, key, pairs[key]])
		pairs[key] = rid
		if typeof(r.get("consign_delay_shichen")) != TYPE_INT or int(r.get("consign_delay_shichen", 0)) < 1:
			errs.append("%s: consign_delay_shichen must be an int >= 1" % label)
		var q: Dictionary = view.get("quests", {}).get(str(r.get("job_quest", "")), {})
		if q.is_empty():
			errs.append("%s: job_quest '%s' missing" % [label, r.get("job_quest", "")])
		elif str(q.get("era", "")) != str(r.get("era", "")):
			errs.append("%s: job_quest %s era %s != route era %s" % [label, r["job_quest"], q.get("era", ""), r.get("era", "")])
	return errs

# #5：生活技能材料鏈不斷頭（每個配方輸入、工具在同一個 era 視圖裡有取得來源）
static func _m3b_life_chain(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var src := {}
	for nid in view.get("npcs", {}):
		var shop: Variant = view["npcs"][nid].get("shop")
		if shop is Dictionary and "SHOP" in view["npcs"][nid].get("services", []):
			for it in shop.get("items", []):
				src[str(it)] = "shop " + nid
	for lid in view.get("life_skills", {}):
		var l: Dictionary = view["life_skills"][lid]
		for y in l.get("yield", []):
			if y is Dictionary:
				src[str(y.get("item", ""))] = "yield " + lid
		for rc in l.get("recipes", []):
			if rc is Dictionary and rc.get("output") is Dictionary:
				src[str(rc["output"].get("item", ""))] = "recipe %s.%s" % [lid, rc.get("id", "")]
		var h: Variant = l.get("hunt")
		if h is Dictionary:
			for d in h.get("drops", []):
				if d is Dictionary:
					src[str(d.get("item", ""))] = "hunt " + lid
	for mid in view.get("monsters", {}):
		for d in view["monsters"][mid].get("drops", []):
			if d is Dictionary and not (d.get("requires") is Array and not (d["requires"] as Array).is_empty()):
				src[str(d.get("item", ""))] = "drop " + mid
	for lid in view.get("life_skills", {}):
		var l: Dictionary = view["life_skills"][lid]
		var need: Array = []
		if str(l.get("tool", "")) != "":
			need.append(["tool", str(l["tool"])])
		for t in l.get("tools", []):
			need.append(["tools", str(t)])
		for rc in l.get("recipes", []):
			if not (rc is Dictionary):
				continue
			for inp in rc.get("inputs", []):
				if inp is Dictionary:
					need.append(["recipe %s input" % rc.get("id", ""), str(inp.get("item", ""))])
			for t in rc.get("tools", []):
				need.append(["recipe %s tool" % rc.get("id", ""), str(t)])
		for n in need:
			if view.get("items", {}).has(n[1]) and not src.has(n[1]):
				errs.append("life_skills.%s: %s '%s' has no source in this era (shop, yield, recipe, hunt or drop)" % [lid, n[0], n[1]])
	return errs

# #10：sect_rank 獎勵、物品新欄位型別
static func _m3b_quests_items(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var rank_rows: Dictionary = view.get("sect_ranks", {})
	for qid in view.get("quests", {}):
		var q: Dictionary = view["quests"][qid]
		for rw in _quest_reward_dicts(q):
			if not (rw is Dictionary) or not rw.has("sect_rank"):
				continue
			var sr: Variant = rw["sect_rank"]
			if not (sr is Dictionary) or str(sr.get("sect", "")) == "" or typeof(sr.get("rank")) != TYPE_INT:
				errs.append("quests.%s: sect_rank reward must be {sect, rank:int}" % qid)
				continue
			var ok := false
			for rid in rank_rows:
				var r: Dictionary = rank_rows[rid]
				if str(r.get("quest", "")) == qid and str(r.get("sect", "")) == str(sr["sect"]) and int(r.get("rank", -1)) == int(sr["rank"]):
					ok = true
			if not ok:
				errs.append("quests.%s: sect_rank {%s, %d} has no sect_ranks row whose quest is this quest (§4.9)" % [qid, sr["sect"], int(sr["rank"])])
	for iid in view.get("items", {}):
		var it: Dictionary = view["items"][iid]
		for f in ["unique_per_char", "bankable", "tool", "keep_on_use"]:
			if it.has(f) and typeof(it[f]) != TYPE_BOOL:
				errs.append("items.%s: %s must be a bool" % [iid, f])
		if it.has("grade") and (typeof(it["grade"]) != TYPE_INT or int(it["grade"]) < 1 or int(it["grade"]) > 3):
			errs.append("items.%s: grade must be 1, 2 or 3" % iid)
	return errs

## #9 era 一致性（全部 era 的原始資料）：
##  - 出口指向「地圖 era 比自己新」的房間時，出口本身要帶 era（≥ 目標 era）；
##  - 雙向出口的有效 era（max(房間地圖 era, 出口 era)）一致；
##  - NPC 的 era 不得比站的房間的地圖 era 舊（1.0A NPC 站在 1.0B 房間會在 1.0A 世界懸空）；
##  - 有 desc_1_0b 的房間必須有帶 era "1.0B" 的出口（§4.4）。
func _check_m3b_raw(loader: DataLoader, eras: Dictionary) -> void:
	var order := func(e: String) -> int:
		return int(eras.get(e, {}).get("order", 0))
	var room_era := {}
	var rooms := {}
	for rid in loader.all_maps:
		var m: Dictionary = loader.all_maps[rid]
		for room in m.get("rooms", []):
			if room is Dictionary:
				room_era[str(room.get("id", ""))] = str(m.get("era", ""))
				rooms[str(room.get("id", ""))] = room
	var eff := func(rid: String, ex: Dictionary) -> int:
		return maxi(order.call(room_era.get(rid, "")), order.call(str(ex.get("era", room_era.get(rid, "")))))
	for rid in rooms:
		var room: Dictionary = rooms[rid]
		var has_1b_exit := false
		for ex in room.get("exits", []):
			if not (ex is Dictionary):
				continue
			if str(ex.get("era", "")) == "1.0B":
				has_1b_exit = true
			var to := str(ex.get("to", ""))
			if not rooms.has(to):
				continue
			var mine: int = order.call(room_era[rid])
			var theirs: int = order.call(room_era[to])
			if theirs > mine and order.call(str(ex.get("era", room_era[rid]))) < theirs:
				errors.append("maps: exit %s %s -> %s (era %s room) must carry \"era\": \"%s\" (§9.5 #9)" % [rid, ex.get("dir", "?"), to, room_era[to], room_era[to]])
			for back in rooms[to].get("exits", []):
				if back is Dictionary and str(back.get("to", "")) == rid and str(back.get("dir", "")) == str(DIR_REVERSE.get(str(ex.get("dir", "")), "")):
					if eff.call(rid, ex) != eff.call(to, back):
						errors.append("maps: exit %s %s -> %s and its reverse have different effective eras (§9.5 #9)" % [rid, ex.get("dir", "?"), to])
		if str(room.get("desc_1_0b", "")) != "" and not has_1b_exit:
			errors.append("maps: room %s has desc_1_0b but no exit with era 1.0B (§4.4)" % rid)
	for nid in loader.all_tables.get("npcs", {}):
		var npc: Dictionary = loader.all_tables["npcs"][nid]
		var r := str(npc.get("room", ""))
		if room_era.has(r) and order.call(str(npc.get("era", ""))) < order.call(room_era[r]):
			errors.append("npcs.%s: era %s is older than its room %s (era %s) (§9.5 #9)" % [nid, npc.get("era", ""), r, room_era[r]])

# ============================================================================
# M3c 攻擊 NPC（M3C_PLAN §5.9 lint，WP-NPCPK）。check_content() 呼叫 check_m3c_npcpk()；伺服器選項在 _check_m3c_options()
# ============================================================================
## §5.9：KILL 的 NPC 不得有的服務
const M3C_KILL_FORBIDDEN_SERVICES := ["QUEST", "TEACH", "JOIN", "SHOP", "INN", "RESPAWN", "TRAVEL", "BANK", "ESCORT", "ORG",
	"JAIL", "RANK", "GUIDE", "MEAL"]
## §9.3 新整數選項的範圍
const M3C_INT_OPTIONS := { "npc_respawn_pct": [10, 1000], "loot_drop_pct": [10, 300] }
## §8 NPCPK 的事件（要有模板；na_npc_back 只有 other 變體）
const M3C_NPCPK_EVENTS := ["na_attack_start", "na_npc_killed", "na_npc_routed", "na_guard_alarm", "na_sect_enemy",
	"na_master_betray", "na_miepai", "na_guard_spare"]
const M3C_NPCPK_REASONS := ["npc_attack_off", "npc_not_attackable", "npc_safe_room", "npc_busy", "npc_routed"]

## M3c 第二輪審查：門派技能的 effect 會送 battle_proc_<EFFECT> 事件（BattleStatus.proc_event）——沒有模板時戰報直接露出
## 事件 key 與 JSON（丐幫乞討 POISON_FANG 就是這樣漏掉的）。DEFENSE、RECOVER 由 battle_rules 用同一個前綴送
func _check_proc_templates(loader: DataLoader) -> void:
	var tpl: Dictionary = loader.all_tables.get("text_templates", {})
	var effects := {}
	for sid in loader.all_tables.get("sects", {}):
		var row: Variant = loader.all_tables["sects"][sid]
		if not (row is Dictionary):
			continue
		var e: Variant = (row as Dictionary).get("sect_skill_effect", {})
		if e is String and str(e) != "":
			effects[str(e)] = sid
		else:
			_collect_effects(e, effects, str(sid))
	for eff in effects:
		var key := "battle_proc_" + str(eff)
		if not tpl.has(key):
			errors.append("text_templates: missing %s（sects.%s 的門派技能效果；戰報會露出事件 key）" % [key, effects[eff]])

## sects 列裡任何一層的 "effect": "<大寫>"（門派技能效果）
func _collect_effects(v: Variant, out: Dictionary, sid: String) -> void:
	if v is Dictionary:
		for k in v:
			if str(k) == "effect" and v[k] is String and str(v[k]) != "" and str(v[k]) == str(v[k]).to_upper():
				out[str(v[k])] = sid
			else:
				_collect_effects(v[k], out, sid)
	elif v is Array:
		for x in v:
			_collect_effects(x, out, sid)

func _check_m3c_options(loader: DataLoader) -> void:
	var so := loader.server_options_default
	for k in M3C_INT_OPTIONS:
		if not so.has(k):
			continue   # 舊的 options 檔：缺 key ＝ 預設
		if typeof(so[k]) != TYPE_INT or int(so[k]) < int(M3C_INT_OPTIONS[k][0]) or int(so[k]) > int(M3C_INT_OPTIONS[k][1]):
			errors.append("server_options.%s must be an int in %s" % [k, str(M3C_INT_OPTIONS[k])])

static func check_m3c_npcpk(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var npcs: Dictionary = view.get("npcs", {})
	var mons: Dictionary = view.get("monsters", {})
	var sects: Dictionary = view.get("sects", {})
	var tpl: Dictionary = view.get("text_templates", {})
	# 被任務、遊蕩、環境句、反應引用的 NPC（全文出現 id 就算）
	var quest_text := JSON.stringify(view.get("quests", {}))
	var other_text := JSON.stringify([view.get("wanderers", {}), view.get("ambient", {}), view.get("reactions", {})])
	var idx := room_index(view)
	for nid in npcs:
		var row: Dictionary = npcs[nid]
		if not row.has("attack"):
			continue
		var label := "npcs.%s.attack" % nid
		var a: Variant = row["attack"]
		if not (a is Dictionary):
			errs.append("%s: must be an object" % label)
			continue
		var mode := str(a.get("mode", ""))
		if not (mode in DataSchema.NPC_ATTACK_MODES_DATA):
			errs.append("%s: bad mode '%s'" % [label, mode])
		var cat := str(a.get("category", ""))
		if not (cat in DataSchema.NPC_ATTACK_CATEGORIES):
			errs.append("%s: bad category '%s'" % [label, cat])
		var via := str(a.get("via", "CTRL"))
		if not (via in DataSchema.NPC_ATTACK_VIA):
			errs.append("%s: bad via '%s'" % [label, via])
		if (via == "MENU" or via == "BOTH") and str(a.get("menu_label", "")) == "":
			errs.append("%s: via %s needs menu_label" % [label, via])
		if not mons.has(str(a.get("monster", ""))):
			errs.append("%s: monster '%s' missing" % [label, a.get("monster", "")])
		for gk in ["group", "group_repeat"]:
			var g: Variant = a.get(gk, [])
			if not (g is Array):
				errs.append("%s.%s: must be an array" % [label, gk])
				continue
			for e in g:
				if not (e is Dictionary) or not mons.has(str(e.get("monster", ""))):
					errs.append("%s.%s: monster '%s' missing" % [label, gk, (e as Dictionary).get("monster", "") if e is Dictionary else e])
					continue
				var c: Variant = e.get("count", [1, 1])
				if not (c is Array) or (c as Array).size() != 2 or int(c[0]) < 0 or int(c[1]) < int(c[0]) or int(c[1]) > 8:
					errs.append("%s.%s: count must be [min, max] with 0 ≤ min ≤ max ≤ 8" % [label, gk])
		var ev := str(a.get("event", ""))
		if not (ev in DataSchema.NPC_ATTACK_EVENTS):
			errs.append("%s: bad event '%s'" % [label, ev])
		if ev == "ATTACK_MASTER" and cat != "SECT_MASTER":
			errs.append("%s: ATTACK_MASTER only on SECT_MASTER" % label)
		if a.has("requires"):
			errs.append_array(check_conditions(a["requires"], label + ".requires"))
		if a.has("respawn") and (typeof(a["respawn"]) != TYPE_INT or int(a["respawn"]) < 1):
			errs.append("%s: respawn must be an int ≥ 1 (時辰)" % label)
		if mode == "CHALLENGE" and a.has("respawn"):
			errs.append("%s: CHALLENGE NPCs never disappear (no respawn)" % label)
		if not (str(a.get("src", "")) in SRC_TAGS):
			errs.append("%s: src must be one of %s" % [label, SRC_TAGS])
		if cat.begins_with("SECT_"):
			var sid := str(a.get("sect", row.get("join_sect", "")))
			if sid == "":
				# npc_sect：所在房間的地區是門派地區
				var region := str(idx.get(str(row.get("room", "")), {}).get("region", row.get("region", "")))
				for s0 in sects:
					if str(sects[s0].get("gate_region", "")) == region:
						sid = str(s0)
			if sid == "" or not sects.has(sid):
				errs.append("%s: %s needs a sect (attack.sect or the NPC's sect region)" % [label, cat])
		if mode == "KILL":
			for svc in row.get("services", []):
				if str(svc) in M3C_KILL_FORBIDDEN_SERVICES:
					errs.append("%s: KILL NPC must not offer service %s (§5.9)" % [label, svc])
			if quest_text.contains('"%s"' % nid):
				errs.append("%s: KILL NPC is referenced by a quest (§5.9; use CHALLENGE)" % label)
			if other_text.contains('"%s"' % nid):
				errs.append("%s: KILL NPC is referenced by wanderers/ambient/reactions (§5.9)" % label)
			var qs: Variant = row.get("quests", [])
			if qs is Array and not (qs as Array).is_empty():
				errs.append("%s: KILL NPC gives quests" % label)
	for k in M3C_NPCPK_EVENTS:
		_need_template(tpl, k, ["self"], errs)
	_need_template(tpl, "na_npc_back", ["other"], errs)
	for r in M3C_NPCPK_REASONS:
		_need_template(tpl, "err_" + str(r), ["self"], errs)
	for sid in sects:
		for p in sects[sid].get("sect_skill_penalties", []):
			if p is Dictionary and not (str(p.get("trigger", "")) in DataSchema.SECT_PENALTY_TRIGGERS):
				errs.append("sects.%s.sect_skill_penalties: bad trigger '%s'" % [sid, p.get("trigger", "")])
			if p is Dictionary and str(p.get("trigger", "")) == "KILL_NPC_ALIGNMENT" 					and not (str(p.get("alignment", "")) in ["GOOD", "NEUTRAL", "EVIL"]):
				errs.append("sects.%s.sect_skill_penalties: KILL_NPC_ALIGNMENT needs alignment" % sid)
	return errs

# ==== M3c WP-LOOT ====
## M3C_PLAN §6（WP-LOOT 區塊；§11.2）：物品的打寶欄位、秘笈、神兵、掉落表、商店不賣精品以上。
const LOOT_RARITIES := ["COMMON", "FINE", "RARE", "TREASURE", "DIVINE"]
const LOOT_SLOTS := ["WEAPON", "ARMOR", "HEAD", "NECK", "WRIST", "CLOAK", "RING", "BOOTS", ""]
const LOOT_ATTRS := ["str", "guts", "wit", "luck", "cal", "agi", "con"]

static func _check_m3c_loot(tables: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var items: Dictionary = tables.get("items", {})
	var lts: Dictionary = tables.get("loot_tables", {})
	for iid in items:
		var it: Dictionary = items[iid]
		var label := "items.%s" % iid
		var rar := str(it.get("rarity", "COMMON"))
		if not (rar in LOOT_RARITIES):
			errs.append("%s: bad rarity '%s'" % [label, rar])
		var slot := str(it.get("slot", ""))
		if not (slot in LOOT_SLOTS):
			errs.append("%s: bad slot '%s' (M3c 8 slots)" % [label, slot])
		if slot == "WEAPON" and int(it.get("def", 0)) != 0:
			errs.append("%s: weapon def must be 0 (M3C_PLAN §1.4 F1：第二個數字是重量)" % label)
		if it.has("official"):
			var off: Variant = it["official"]
			if not (off is Dictionary):
				errs.append("%s: official must be { atk, def, weight }" % label)
			else:
				for k in off:
					if not (str(k) in ["atk", "def", "weight"]) or not (typeof(off[k]) in [TYPE_INT, TYPE_FLOAT]):
						errs.append("%s: official.%s must be int atk/def/weight" % [label, k])
		if it.has("bonus"):
			var bo: Variant = it["bonus"]
			if not (bo is Dictionary):
				errs.append("%s: bonus must be a dictionary" % label)
			else:
				for k in bo:
					if not (str(k) in LOOT_ATTRS):
						errs.append("%s: bonus key '%s' not in Character.ATTR_IDS" % [label, k])
		if it.has("requires"):
			if not (it["requires"] is Array):
				errs.append("%s: requires must be an array" % label)
			else:
				errs.append_array(check_conditions(it["requires"], label + ".requires"))
		if it.has("fx") and (str(it["fx"]) != "claw" or str(it.get("weapon_type", "")) != "FIST"):
			errs.append("%s: fx only \"claw\" on FIST weapons" % label)
		if it.has("manual"):
			var m: Variant = it["manual"]
			if not (m is Dictionary):
				errs.append("%s: manual must be a dictionary" % label)
			else:
				var sk := str(m.get("skill", ""))
				if not (tables.get("basic_skills", {}).has(sk) or tables.get("martial_arts", {}).has(sk)):
					errs.append("%s: manual.skill '%s' must be a basic skill or martial art" % [label, sk])
				if int(m.get("cap", 0)) <= 0 or int(m.get("literacy_min", -1)) < 0 or int(m.get("prof", 0)) <= 0:
					errs.append("%s: manual needs cap > 0, literacy_min >= 0, prof > 0" % label)
				if m.get("requires", []) is Array:
					errs.append_array(check_conditions(m.get("requires", []), label + ".manual.requires"))
				if str(it.get("slot", "")) != "" or bool(it.get("usable", false)):
					errs.append("%s: manual items are not equippable or usable" % label)
		if bool(it.get("divine", false)):
			for need in ["no_sell", "no_drop", "keep_on_death", "unique_world"]:
				if not bool(it.get(need, false)):
					errs.append("%s: divine item needs %s: true" % [label, need])
			if it.get("bankable", true) != false:
				errs.append("%s: divine item needs bankable: false" % label)
			if rar != "DIVINE":
				errs.append("%s: divine item needs rarity DIVINE" % label)
	# 掉落表
	var divine_in: Dictionary = {}
	for lid in lts:
		var lt: Dictionary = lts[lid]
		var label := "loot_tables.%s" % lid
		for g in lt.get("guaranteed", []):
			if not (g is Dictionary) or not items.has(str(g.get("item", ""))):
				errs.append("%s.guaranteed: unknown item %s" % [label, str(g.get("item", "")) if g is Dictionary else "?"])
				continue
			if int(g.get("min", 1)) < 1 or int(g.get("max", 1)) < int(g.get("min", 1)):
				errs.append("%s.guaranteed.%s: need 1 <= min <= max" % [label, g.get("item", "")])
			if bool(items[str(g["item"])].get("divine", false)):
				errs.append("%s.guaranteed: divine item %s cannot be guaranteed" % [label, g.get("item", "")])
		var gi := 0
		for grp in lt.get("groups", []):
			var gl := "%s.groups[%d]" % [label, gi]
			gi += 1
			if not (grp is Dictionary):
				errs.append(gl + ": must be a dictionary")
				continue
			var ch := float(grp.get("chance", 0.0))
			if ch <= 0.0 or ch > 1.0:
				errs.append(gl + ": chance must be in (0, 1]")
			var dv := bool(grp.get("divine", false))
			var picks: Variant = grp.get("pick", [])
			if not (picks is Array) or (picks as Array).is_empty():
				errs.append(gl + ": pick must be a non-empty array")
				continue
			for p in picks:
				var iid := str(p.get("item", "")) if p is Dictionary else ""
				if not items.has(iid):
					errs.append("%s: unknown item '%s'" % [gl, iid])
					continue
				if int(p.get("w", 0)) <= 0:
					errs.append("%s.%s: weight w must be > 0" % [gl, iid])
				var is_dv := bool(items[iid].get("divine", false))
				if is_dv != dv:
					errs.append("%s.%s: divine items only in divine groups (and divine groups only hold divine items)" % [gl, iid])
				if is_dv:
					if divine_in.has(iid) and divine_in[iid] != lid:
						errs.append("%s: divine %s already drops from %s (one boss per divine weapon, §6.5)" % [gl, iid, divine_in[iid]])
					divine_in[iid] = lid
		# M3c 審查（頭目鎖）：lockout_shichen 是 >= 0 的整數；掉神兵的表一定要有（不然神兵、珍品可以無限重打刷）
		var lko: Variant = lt.get("lockout_shichen", 0)
		if typeof(lko) != TYPE_INT or int(lko) < 0:
			errs.append("%s.lockout_shichen: must be an int >= 0" % label)
		elif divine_in.values().has(lid) and int(lko) <= 0:
			errs.append("%s: a table with a divine group needs lockout_shichen > 0 (M3c review: boss loot lockout)" % label)
	# 怪物 → 掉落表
	for mid in tables.get("monsters", {}):
		var lt_id := str(tables["monsters"][mid].get("loot_table", ""))
		if lt_id != "" and not lts.has(lt_id):
			errs.append("monsters.%s: loot_table '%s' not found" % [mid, lt_id])
	# 商店：精品以上不上架（§6.2 #6）；神兵、傳家不上架
	for nid in tables.get("npcs", {}):
		var shop: Variant = tables["npcs"][nid].get("shop", {})
		if not (shop is Dictionary):
			continue
		for iid in shop.get("items", []):
			var row: Dictionary = items.get(str(iid), {})
			if row.is_empty():
				continue
			if LOOT_RARITIES.find(str(row.get("rarity", "COMMON"))) >= 2:
				errs.append("npcs.%s.shop: %s is %s (RARE+ is never sold, §6.2)" % [nid, iid, row.get("rarity", "")])
	return errs

# ==== M3c2 WP-PACE ====
## M3C2_PLAN §2.3、§8：雜務（quests.chore）、規則鍵、伺服器選項 spar_daily_cap
const M3C2_INT_OPTIONS := { "spar_daily_cap": [0, 200] }

func _check_m3c2_options(loader: DataLoader) -> void:
	var so := loader.server_options_default
	for k in M3C2_INT_OPTIONS:
		if typeof(so.get(k)) != TYPE_INT or int(so[k]) < int(M3C2_INT_OPTIONS[k][0]) or int(so[k]) > int(M3C2_INT_OPTIONS[k][1]):
			errors.append("server_options.%s must be an int in %s" % [k, str(M3C2_INT_OPTIONS[k])])

const M3C2_CHORE_GROUP := "sect_chores"
const M3C2_CHORE_COST_KEYS := ["jing", "shen", "qi"]
const M3C2_CHORE_LP := [10, 100]
const M3C2_SPAR_XP := [20, 300]
const M3C2_SPAR_LP := [2, 30]
const M3C2_TEMPLATES := ["ch_no_lp", "ch_no_lp_daily", "ch_no_lp_novice", "ch_spar_capped", "ch_spar_rule",
	"err_chore_tired", "err_req_money_max", "err_req_has_item"]

## 雜務列（chore 欄位）、每派至少 3 件且至少一件全天、切磋弟子的獎勵欄位、模板（M3C2_PLAN §2.1、§2.3）
static func _check_m3c2_pace(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var quests: Dictionary = view.get("quests", {})
	var sects: Dictionary = view.get("sects", {})
	var per_sect := {}
	var allday := {}
	for qid in quests:
		var q: Dictionary = quests[qid]
		var c: Variant = q.get("chore", null)
		var grp := str(q.get("group", ""))
		if c == null:
			if grp == M3C2_CHORE_GROUP:
				errs.append("quests.%s: group sect_chores needs a chore field (M3C2 §2.3.1)" % qid)
			continue
		var L := "quests.%s.chore" % qid
		if not (c is Dictionary):
			errs.append("%s: must be an object" % L)
			continue
		if str(c.get("kind", "SECT")) == "TOWN":
			continue   # M3d WP-ERRANDS：城鎮任務（chore.kind TOWN）由 _check_m3d_errands 檢查（M3D_PLAN §6.1）
		var sect := str(c.get("sect", ""))
		var req_sect := ""
		for r in q.get("requires", []):
			if r is Dictionary and str(r.get("type", "")) == "sect":
				req_sect = str(r.get("sect", ""))
		if sect == "" or sect != req_sect:
			errs.append("%s: sect '%s' must match requires sect '%s'" % [L, sect, req_sect])
		var lp: Variant = c.get("lp", null)
		if typeof(lp) != TYPE_INT or int(lp) < M3C2_CHORE_LP[0] or int(lp) > M3C2_CHORE_LP[1]:
			errs.append("%s: lp must be an int in %s" % [L, str(M3C2_CHORE_LP)])
		var dp: Variant = c.get("decay_pct", null)
		if not (dp is Array) or (dp as Array).is_empty():
			errs.append("%s: decay_pct must be a non-empty array" % L)
		else:
			var prev := 101
			for v in dp:
				if typeof(v) != TYPE_INT or int(v) < 0 or int(v) > 100 or int(v) > prev:
					errs.append("%s: decay_pct must be non-increasing ints in [0, 100]" % L)
					break
				prev = int(v)
		var cost: Variant = c.get("cost", {})
		if not (cost is Dictionary):
			errs.append("%s: cost must be an object" % L)
		else:
			for k in cost:
				if not (str(k) in M3C2_CHORE_COST_KEYS) or typeof(cost[k]) != TYPE_INT or int(cost[k]) < 0:
					errs.append("%s: cost.%s must be one of %s with an int >= 0" % [L, str(k), str(M3C2_CHORE_COST_KEYS)])
		if typeof(c.get("prof_below", 50)) != TYPE_INT:
			errs.append("%s: prof_below must be an int" % L)
		if str(c.get("src_note", "")).strip_edges() == "":
			errs.append("%s: src_note missing" % L)
		if grp == M3C2_CHORE_GROUP:
			if not str(qid).begins_with("q_ch_"):
				errs.append("quests.%s: sect chores use the q_ch_ prefix (M3C2 Q6)" % qid)
			var rp: Variant = q.get("repeat", {})
			if not (rp is Dictionary) or int((rp as Dictionary).get("max", 1)) != 0 or float((rp as Dictionary).get("cooldown_days", 0.0)) <= 0.0:
				errs.append("quests.%s: sect chores need repeat { max 0, cooldown_days > 0 } (M3C2 §2.5)" % qid)
		per_sect[sect] = int(per_sect.get(sect, 0)) + 1
		var timed := false
		for r in q.get("requires", []):
			if r is Dictionary and str(r.get("type", "")) == "hour_in":
				timed = true
		if not timed:
			allday[sect] = true
	for sid in sects:
		if not per_sect.has(sid):
			errs.append("sects.%s: no sect chores (M3C2 §2.3.2：每派至少 3 件)" % sid)
			continue
		if int(per_sect[sid]) < 3:
			errs.append("sects.%s: only %d sect chores (need >= 3)" % [sid, int(per_sect[sid])])
		if not allday.has(sid):
			errs.append("sects.%s: needs at least one all-day chore (no hour_in)" % sid)
	for mid in view.get("monsters", {}):
		var smid := str(mid)
		if not (smid == "m_hs_trainee" or (smid.ends_with("_dizi") and not smid.begins_with("m_npc_"))):
			continue
		var m: Dictionary = view["monsters"][mid]
		if bool(m.get("no_rewards", false)):
			continue
		var xp := int(m.get("combat_xp", 0))
		var mlp := int(m.get("learn_points", 0))
		if xp < M3C2_SPAR_XP[0] or xp > M3C2_SPAR_XP[1]:
			errs.append("monsters.%s: spar combat_xp %d outside %s (M3C2 §2.1)" % [mid, xp, str(M3C2_SPAR_XP)])
		if mlp < M3C2_SPAR_LP[0] or mlp > M3C2_SPAR_LP[1]:
			errs.append("monsters.%s: spar learn_points %d outside %s (M3C2 §2.1)" % [mid, mlp, str(M3C2_SPAR_LP)])
	var tpl: Dictionary = view.get("text_templates", {})
	if not tpl.is_empty():
		for k in M3C2_TEMPLATES:
			if not tpl.has(k):
				errs.append("text_templates: missing '%s' (M3C2 §2.3)" % k)
	return errs

# ==== M3c2 WP-ECON ====
## M3C2_PLAN §4.3、§4.4：商店材料循環（EconCalc.loop_violations，含多步驟閉包、最低買價 MIN_BUY_PCT）；
## 新欄位 yield[].n_per_levels（int ≥ 0）、success_base（0–1）、success_per_level（≥ 0）。
## 新增配方或改價做出「商店買材料 → 做 → 賣」賺錢的循環，這裡立刻報錯。
static func _check_m3c2_econ(tables: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var ls: Variant = tables.get("life_skills", {})
	if not (ls is Dictionary) or (ls as Dictionary).is_empty():
		return errs
	for sid in ls:
		var row: Variant = ls[sid]
		if not (row is Dictionary):
			continue
		var y: Variant = row.get("yield", [])
		if y is Array:
			for i in (y as Array).size():
				var e: Variant = y[i]
				if e is Dictionary and e.has("n_per_levels"):
					var npl: Variant = e["n_per_levels"]
					if typeof(npl) != TYPE_INT or int(npl) < 0:
						errs.append("life_skills.%s.yield[%d].n_per_levels must be an int >= 0 (M3C2 §4.4)" % [sid, i])
		var srcs: Array = [["life_skills.%s" % sid, row]]
		for rc in RecipeCheck.recipes_of(row):
			if rc is Dictionary:
				srcs.append(["life_skills.%s.recipes.%s" % [sid, str(rc.get("id", ""))], rc])
		for pair in srcs:
			var d: Dictionary = pair[1]
			if d.has("success_base"):
				var sb: Variant = d["success_base"]
				if not (typeof(sb) in [TYPE_FLOAT, TYPE_INT]) or float(sb) < 0.0 or float(sb) > 1.0:
					errs.append("%s.success_base must be a number in [0, 1] (M3C2 §4.4)" % pair[0])
			if d.has("success_per_level"):
				var sp: Variant = d["success_per_level"]
				if not (typeof(sp) in [TYPE_FLOAT, TYPE_INT]) or float(sp) < 0.0:
					errs.append("%s.success_per_level must be a number >= 0 (M3C2 §4.4)" % pair[0])
	for e in EconCalc.loop_violations(tables):
		errs.append("life_skills.%s (M3C2 §4.3 econ_loop)" % e)
	return errs

# ==== M3d WP-COMBAT ====（M3D_PLAN §9.2；WP-COMBAT 在這個區塊填）
## M3D_PLAN §3：1.0B 視圖（以 i_cb_laopaoxie 或京城在不在判斷）要有烙跑鞋、夜明珠（效果 FLEE_ANYWHERE／LIGHT）、西域貨郎與商品；
## 合體武功（combo 字典）的 pair 各邊要有 gender（M／F／""）、min ≥ 1；有合體武功的師父列要有 combo_ready；
## 模板：閃、輕、合體事件與 COMBAT 原因碼（err_*）；1.0A 視圖不可出現 cb 前綴的列與合體武功（T8）
const CB_TEMPLATES_A := ["battle_dodge", "battle_qing_jump", "battle_qing_escape", "battle_qing_fail",
	"err_dodge_off", "err_qing_off", "err_equip_cooldown"]
const CB_TEMPLATES_B := ["battle_combo", "cb_bond_sent", "cb_bond_refused", "cb_bond_formed", "cb_bond_cancelled", "cb_nurtured",
	"cb_drained", "talk_n_cb_jc_huolang", "err_combo_need_partner", "err_combo_need_party", "err_combo_pair_mismatch",
	"err_combo_moqi_low", "err_combo_has_partner", "err_combo_peihe_low", "err_combo_no_request", "err_req_combo_ready",
	"err_combo_partner_absent", "err_combo_request_pending"]

static func _check_m3d_combat(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var items: Dictionary = view.get("items", {})
	var npcs: Dictionary = view.get("npcs", {})
	var arts: Dictionary = view.get("martial_arts", {})
	var tpl: Dictionary = view.get("text_templates", {})
	var b_view: bool = items.has("i_cb_laopaoxie") or (view.get("regions", {}) as Dictionary).has("jingcheng")
	for t in CB_TEMPLATES_A + (CB_TEMPLATES_B if b_view else []):
		if not tpl.has(t):
			errs.append("text_templates.%s missing (M3D §3 WP-COMBAT)" % t)
	if b_view:
		for pair in [["i_cb_laopaoxie", "FLEE_ANYWHERE", "BOOTS"], ["i_cb_yemingzhu", "LIGHT", ""]]:
			var row: Dictionary = items.get(pair[0], {})
			if row.is_empty():
				errs.append("items.%s missing (M3D §3.4／§3.5)" % pair[0])
				continue
			if not (row.get("effects", []) as Array).any(func(e): return e is Dictionary and str(e.get("type", "")) == pair[1]):
				errs.append("items.%s: effects needs %s" % [pair[0], pair[1]])
			if str(row.get("slot", "")) != pair[2]:
				errs.append("items.%s: slot must be '%s'" % [pair[0], pair[2]])
		var hl: Dictionary = npcs.get("n_cb_jc_huolang", {})
		if hl.is_empty():
			errs.append("npcs.n_cb_jc_huolang missing (M3D §3.4)")
		else:
			var sold: Array = (hl.get("shop", {}) as Dictionary).get("items", [])
			for iid in ["i_cb_laopaoxie", "i_cb_yemingzhu"]:
				if not sold.has(iid):
					errs.append("npcs.n_cb_jc_huolang.shop.items: missing %s" % iid)
	for aid in arts:
		var cb: Variant = arts[aid].get("combo", null)
		if not (cb is Dictionary):
			continue
		if str(arts[aid].get("era", "")) == "1.0A":
			errs.append("martial_arts.%s: combo arts are 1.0B (M3D §3.3.5)" % aid)
		for side in (cb as Dictionary).get("pair", []):
			if side is Dictionary:
				if not (str(side.get("gender", "")) in ["", "M", "F"]):
					errs.append("martial_arts.%s.combo.pair: gender must be M/F/\"\"" % aid)
				if int(side.get("min", 0)) < 1:
					errs.append("martial_arts.%s.combo.pair: min must be >= 1" % aid)
		if int((cb as Dictionary).get("moqi_min", 0)) < 0 or int((cb as Dictionary).get("moqi_min", 0)) > 100:
			errs.append("martial_arts.%s.combo.moqi_min must be 0–100" % aid)
		# 教這套合體武功的師父列要有 combo_ready（修練要夥伴、組隊、默契）
		for mid in view.get("masters", {}):
			var m: Dictionary = view["masters"][mid]
			if str(m.get("skill_id", "")) != str(aid):
				continue
			var req: Array = m.get("requires", []) if m.get("requires", []) is Array else []
			if not req.any(func(r): return r is Dictionary and str(r.get("type", "")) == "combo_ready" and str(r.get("art", "")) == str(aid)):
				errs.append("masters.%s: teaches combo art %s without combo_ready (M3D §3.3.1)" % [mid, aid])
	if not b_view:
		for t in ["items", "npcs", "monsters", "quests", "masters"]:
			for id in view.get(t, {}):
				if str(id).begins_with("i_cb_") or str(id).begins_with("n_cb_") or str(id).begins_with("ms_cb_"):
					errs.append("%s.%s: cb rows are 1.0B（1.0A 視圖不可出現）" % [t, id])
	return errs

# ==== M3d WP-ARTS ====（M3D_PLAN §9.2；WP-ARTS 在這個區塊填）
## 1.0A 視圖一定要有的（煉毒、恐嚇、血池、殺古墓殺氣）；1.0B 視圖（以山居隱士在不在判斷）再加四條武功鏈與門規
const ARTS_IDS_A := { "quests": ["q_ar_xh_muding"], "items": ["i_ar_xh_muding", "i_ar_zhuangyuanhong"],
	"npcs": ["n_ar_xd_xuechi", "n_ar_xd_xuechi_2", "n_ar_xd_xuechi_3"],
	"monsters": ["m_ar_xd_xuechi_1", "m_ar_xd_xuechi_2", "m_ar_xd_xuechi_3"] }
const ARTS_IDS_B := { "quests": ["q_ar_qz_chongyang", "q_ar_qz_kongming", "q_ar_lj_bahuang", "q_ar_em_luosha", "q_ar_xd_xuemo"],
	"masters": ["ms_ar_qz_shanju", "ms_ar_qz_shuliu", "ms_ar_qz_yunyou", "ms_ar_qz_wangzhijin", "ms_ar_lj_lanjian_bahuang",
		"ms_ar_guoxiang_sixiang", "ms_ar_xd_xuemo"],
	"npcs": ["n_ar_qz_shanju", "n_ar_qz_shuliu", "n_ar_qz_yunyou", "n_ar_qz_wangzhijin", "n_ar_lj_wuyazi", "n_ar_ym_shouwei",
		"n_ar_guoxiang", "n_ar_xd_inf_heilong", "n_ar_xd_baoxiang", "n_ar_xd_inf_dali", "n_ar_dingbusan", "n_ar_dingbusi",
		"n_ar_laokelian", "n_ar_xd_xuemo_laozu"],
	"monsters": ["m_ar_manbing"],
	"items": ["i_ar_qz_tuijianxin", "i_ar_ym_tuijianxin", "i_ar_luoshajian", "i_ar_huangyaowan", "i_ar_xd_daojue"],
	"martial_arts": ["em_sixiang", "xd_xuemo", "qz_chongyang", "qz_kongming", "lj_bahuang"],
	"sect_rules": ["qz_r_kill_gumu"], "text_templates": ["ar_xuemo_enlightened", "ar_cy_letter", "ar_cy_shuliu"] }
const ARTS_TEMPLATES := ["ar_intimidated", "ar_liandu", "ar_intimidate_1", "ar_intimidate_2",
	"ar_intimidate_3", "ar_intimidate_4", "ar_xuechi_won", "ar_xuechi_daily", "ar_qz_gumu_kill", "err_intimidate_not_xd",
	"err_intimidate_bad_target", "err_intimidate_daily", "err_liandu_no_tool", "err_liandu_not_xh",
	"err_liandu_daily"]
## 1.0B 才有的武功：1.0A 視圖不可出現（T8）
const ARTS_B_ONLY := ["em_sixiang", "xd_xuemo", "qz_chongyang", "qz_kongming", "lj_bahuang"]

static func _check_m3d_arts(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var full := (view.get("npcs", {}) as Dictionary).has("n_ar_qz_shanju")
	var want: Array = [ARTS_IDS_A, ARTS_IDS_B] if full else [ARTS_IDS_A]
	for ids in want:
		for t in ids:
			for id in ids[t]:
				if not (view.get(t, {}) as Dictionary).has(id):
					errs.append("m3d arts: %s.%s missing (M3D_PLAN §8.5)" % [t, id])
	if not full:
		for aid in ARTS_B_ONLY:
			if (view.get("martial_arts", {}) as Dictionary).has(aid):
				errs.append("m3d arts: martial_arts.%s must be 1.0B (M3D_PLAN T8)" % aid)
	var tt: Dictionary = view.get("text_templates", {})
	for k in ARTS_TEMPLATES:
		if not tt.has(k):
			errs.append("m3d arts: text_templates.%s missing" % k)
	# 血池三階：NPC 的 fight.monster 對到 ArtsRules.XUECHI 的怪物，怪物 no_rewards
	var npcs: Dictionary = view.get("npcs", {})
	var mons: Dictionary = view.get("monsters", {})
	for tier in ArtsRules.XUECHI:
		var e: Dictionary = ArtsRules.XUECHI[tier]
		var nrow: Dictionary = npcs.get(str(e["npc"]), {})
		var f: Variant = nrow.get("fight", {})
		if not nrow.is_empty() and (not (f is Dictionary) or str((f as Dictionary).get("monster", "")) != str(e["monster"])):
			errs.append("m3d arts: npcs.%s fight.monster must be %s (ArtsRules.XUECHI)" % [e["npc"], e["monster"]])
		var mrow: Dictionary = mons.get(str(e["monster"]), {})
		if not mrow.is_empty() and not bool(mrow.get("no_rewards", false)):
			errs.append("m3d arts: monsters.%s must be no_rewards (血池是比武)" % e["monster"])
	# 小木鼎：LIANDU 效果（ArtsSystem.on_use_item 攔下使用）
	var md: Dictionary = view.get("items", {}).get(ArtsRules.MUDING, {})
	if not md.is_empty():
		var has := false
		for ef in md.get("effects", []):
			if ef is Dictionary and str(ef.get("type", "")) == "LIANDU":
				has = true
		if not has or not bool(md.get("usable", false)):
			errs.append("m3d arts: items.%s needs usable + a LIANDU effect (M3D_PLAN §4.4)" % ArtsRules.MUDING)
	# 殺古墓門規：counter_max 指到 ArtsRules 的計數
	var rr: Dictionary = view.get("sect_rules", {}).get(ArtsRules.QZ_GUMU_RULE, {})
	if not rr.is_empty():
		var ok := false
		for c in rr.get("ok_if", []):
			if c is Dictionary and str(c.get("type", "")) == "counter_max" and str(c.get("key", "")) == ArtsRules.COUNTER_QZ_GUMU:
				ok = true
		if not ok:
			errs.append("m3d arts: sect_rules.%s ok_if needs counter_max %s" % [ArtsRules.QZ_GUMU_RULE, ArtsRules.COUNTER_QZ_GUMU])
	return errs

# ==== M3d WP-EVENTS ====（M3D_PLAN §9.2；WP-EVENTS 在這個區塊填）
## §5.2：危險鏢（group jiebiao）的 jiebiao { value > 0, kind hu|huo, from, to } 合法、給的人列出它、護送 NPC 與劫鏢戰的鏢單位存在、
##   ESCORT 目標的 NPC 與 kind 對得上、era 1.0B；劫匪怪物存在。§5.3：報名員有 TOURNEY 服務、盟主令牌不能賣不能丟、
##   每個門派都有冠軍稱號與比武時辰。兩者的事件與原因碼模板都要在。
const EV_TEMPLATES := ["ev_jb_started", "ev_jb_done", "ev_jb_failed", "ev_jb_robbed", "ev_jb_rob_repelled", "ev_jb_rob_share",
	"ev_jb_rob_marked", "ev_jb_rob_start", "ev_jb_ambush", "ev_jb_fail", "err_jb_no_deposit", "err_jb_cooldown", "err_jb_active",
	"err_rob_no_escort", "err_rob_xp", "err_rob_same_party"]
const EV_TOURNEY_TEMPLATES := ["ev_tourney_open", "ev_tourney_signed", "ev_tourney_withdrawn", "ev_tourney_start",
	"ev_tourney_cancelled", "ev_tourney_bye", "ev_tourney_forfeit", "ev_tourney_done", "ev_tourney_reward", "ev_tourney_title_lost",
	"ev_tourney_call", "ev_duel_result", "ev_duel_line", "ev_duel_line_miss", "rmr_ev_tourney_champion", "rmr_ev_sect_champion",
	"err_tourney_disabled", "err_tourney_closed", "err_tourney_signed", "err_tourney_not_eligible", "err_tourney_running",
	"err_tourney_need_xp", "err_tourney_has_pk", "err_tourney_need_morality", "err_tourney_need_sect_skill", "ev_tourney_disqualified"]

static func _check_m3d_events(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var quests: Dictionary = view.get("quests", {})
	var npcs: Dictionary = view.get("npcs", {})
	var mons: Dictionary = view.get("monsters", {})
	var tpl: Dictionary = view.get("text_templates", {})
	var any_jb := false
	for qid in quests:
		var q: Dictionary = quests[qid]
		if str(q.get("group", "")) != JiebiaoRules.QUEST_GROUP:
			continue
		any_jb = true
		var L := "m3d events: quests.%s" % qid
		var spec := JiebiaoRules.spec_of(q)
		if spec.is_empty():
			errs.append("%s: jiebiao { value > 0, kind hu|huo } missing or bad (M3D_PLAN §5.2.1)" % L)
			continue
		if str(q.get("era", "")) != "1.0B":
			errs.append("%s: danger escorts are era 1.0B (T8)" % L)
		var giver := str(q.get("giver", ""))
		if not npcs.has(giver) or not (qid in npcs[giver].get("quests", [])):
			errs.append("%s: giver %s must exist and list the quest" % [L, giver])
		var esc := str(JiebiaoRules.ESCORT_NPC[str(spec["kind"])])
		if not npcs.has(esc):
			errs.append("%s: escort npc %s missing" % [L, esc])
		var found := false
		for st in q.get("stages", []):
			for o in st.get("objectives", []) if st is Dictionary else []:
				if o is Dictionary and str(o.get("type", "")) == "ESCORT":
					found = true
					if str(o.get("npc", "")) != esc:
						errs.append("%s: ESCORT npc must be %s for kind %s" % [L, esc, str(spec["kind"])])
		if not found:
			errs.append("%s: needs an ESCORT objective" % L)
		var unit := str(JiebiaoRules.ROB_UNIT[str(spec["kind"])])
		if not mons.has(unit):
			errs.append("%s: rob unit monster %s missing" % [L, unit])
	if any_jb:
		if not mons.has(JiebiaoRules.BANDIT_ID):
			errs.append("m3d events: monsters.%s (special landmine bandits) missing" % JiebiaoRules.BANDIT_ID)
		for k in EV_TEMPLATES:
			if not tpl.has(k):
				errs.append("m3d events: text_templates.%s missing" % k)
	if npcs.has(TourneyRules.CLERK_NPC):
		if not ("TOURNEY" in npcs[TourneyRules.CLERK_NPC].get("services", [])):
			errs.append("m3d events: npcs.%s needs the TOURNEY service" % TourneyRules.CLERK_NPC)
		for k in EV_TOURNEY_TEMPLATES:
			if not tpl.has(k):
				errs.append("m3d events: text_templates.%s missing" % k)
		var tok: Dictionary = view.get("items", {}).get(TourneyRules.TOKEN_ITEM, {})
		if tok.is_empty():
			errs.append("m3d events: items.%s missing" % TourneyRules.TOKEN_ITEM)
		elif not bool(tok.get("no_sell", false)) or not bool(tok.get("no_drop", false)) or not bool(tok.get("keep_on_death", false)):
			errs.append("m3d events: items.%s must be no_sell + no_drop + keep_on_death" % TourneyRules.TOKEN_ITEM)
		for sid in view.get("sects", {}):
			if not TourneyRules.SECT_SCHEDULE.has(str(sid)) or not TourneyRules.SECT_TITLES.has(str(sid)):
				errs.append("m3d events: sect %s has no tourney schedule or champion title (TourneyRules)" % str(sid))
	return errs

# ==== M3d WP-ERRANDS ====（M3D_PLAN §9.2；WP-ERRANDS 在這個區塊填）
## M3D_PLAN §6.1：chore.kind（SECT／TOWN）、decay_all；TOWN 的任務 repeat.max == 0、decay_pct 最後一個 ≤ 30、lp 0–100；
## §6、§8.5：WP-ERRANDS 的 NPC／怪物／道具／模板存在（1.0B 的列只在 1.0B 視圖檢查）；黑龍潭迷宮走得到瑛姑、走錯的出口繞回陣口；
## §6.5：每個切磋弟子都對得到一個門派（SectSystem.spar_sect 同規則）
const ER_NPCS_A := ["n_er_sanbahong", "n_er_xx_funv", "n_er_xx_nongfu", "n_er_dl_zuigui", "n_er_dl_ahu", "n_er_dl_qingqing"]
const ER_NPCS_B := ["n_er_kezhene", "n_er_guojing", "n_er_tiefan", "n_er_yinggu", "n_er_cien"]
const ER_QUESTS_A := ["q_er_zhugeyi", "q_er_biandang_xx", "q_er_biandang_dl", "q_er_zuigui", "q_er_ahu"]
const ER_QUESTS_B := ["q_er_kezhene", "q_er_jiuwei"]
const ER_MONSTERS_A := ["m_er_baiyuan"]
const ER_MONSTERS_B := ["m_er_wulin_1", "m_er_wulin_2", "m_er_wulin_3", "m_er_wulin_4", "m_er_jiuwei", "m_er_yang"]
const ER_TEMPLATES := ["er_spar_not_disciple", "er_town_no_lp", "er_zuigui_stolen"]
const ER_TEMPLATES_B := ["er_wlt_start", "er_wlt_win", "er_wlt_lost", "er_wlt_refund"]
const ER_MAZE := ["hl_mud1", "hl_mud2", "hl_mud3", "hl_mud4", "hl_mud5"]

static func _check_m3d_errands(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var quests: Dictionary = view.get("quests", {})
	for qid in quests:
		var q: Dictionary = quests[qid]
		var c: Variant = q.get("chore", null)
		if not (c is Dictionary):
			continue
		var L := "quests.%s.chore" % qid
		var kind := str((c as Dictionary).get("kind", "SECT"))
		if not (kind in DataSchema.CHORE_KINDS):
			errs.append("%s.kind '%s' not in %s (M3D §6.1)" % [L, kind, str(DataSchema.CHORE_KINDS)])
			continue
		if (c as Dictionary).has("decay_all") and typeof(c["decay_all"]) != TYPE_BOOL:
			errs.append("%s.decay_all must be a bool (M3D §6.1)" % L)
		if kind != "TOWN":
			continue
		var rp: Variant = q.get("repeat", {})
		if not (rp is Dictionary) or int((rp as Dictionary).get("max", 1)) != 0:
			errs.append("quests.%s: TOWN chores must be repeatable (repeat.max 0) (M3D §6.1)" % qid)
		var lp: Variant = c.get("lp", null)
		if typeof(lp) != TYPE_INT or int(lp) < 0 or int(lp) > 100:
			errs.append("%s: lp must be an int in [0, 100]" % L)
		var dp: Variant = c.get("decay_pct", null)
		if not (dp is Array) or (dp as Array).is_empty():
			errs.append("%s: decay_pct must be a non-empty array" % L)
		else:
			var prev := 101
			for v in dp:
				if typeof(v) != TYPE_INT or int(v) < 0 or int(v) > 100 or int(v) > prev:
					errs.append("%s: decay_pct must be non-increasing ints in [0, 100]" % L)
					break
				prev = int(v)
			if int((dp as Array)[(dp as Array).size() - 1]) > 30:
				errs.append("%s: TOWN decay_pct must end at <= 30 (M3D §6.1)" % L)
		var cost: Variant = c.get("cost", {})
		if not (cost is Dictionary):
			errs.append("%s: cost must be an object" % L)
		if typeof(c.get("prof_below", 50)) != TYPE_INT:
			errs.append("%s: prof_below must be an int" % L)
		if str(c.get("src_note", "")).strip_edges() == "":
			errs.append("%s: src_note missing" % L)
	# 列存在（1.0B 視圖才有 1.0B 的列）
	var npcs: Dictionary = view.get("npcs", {})
	var mons: Dictionary = view.get("monsters", {})
	var items: Dictionary = view.get("items", {})
	var has_b := npcs.has("n_er_kezhene")
	for nid in ER_NPCS_A + (ER_NPCS_B if has_b else []):
		if not npcs.has(nid):
			errs.append("npcs.%s missing (M3D §8.5)" % nid)
	for qid in ER_QUESTS_A + (ER_QUESTS_B if has_b else []):
		if not quests.has(qid):
			errs.append("quests.%s missing (M3D §8.5)" % qid)
	for mid in ER_MONSTERS_A + (ER_MONSTERS_B if has_b else []):
		if not mons.has(mid):
			errs.append("monsters.%s missing (M3D §8.5)" % mid)
	if has_b:
		for mid in ["m_er_wulin_1", "m_er_wulin_2", "m_er_wulin_3", "m_er_wulin_4"]:
			if mons.has(mid) and not bool(mons[mid].get("no_rewards", false)):
				errs.append("monsters.%s: 武林帖的對手要 no_rewards（獎勵是名聲歷練，M3D §6.2.3）" % mid)
		if not items.has("i_er_wulintie"):
			errs.append("items.i_er_wulintie missing (M3D §6.2.3)")
	for mid in ["m_er_baiyuan", "m_er_yang"]:
		if mons.has(mid) and int(mons[mid].get("morality_on_kill", 0)) >= 0:
			errs.append("monsters.%s: must lower morality (M3D §6.4、E5)" % mid)
	var tpl: Dictionary = view.get("text_templates", {})
	if not tpl.is_empty():
		for k in ER_TEMPLATES + (ER_TEMPLATES_B if has_b else []):
			if not tpl.has(k):
				errs.append("text_templates: missing '%s' (M3D §6)" % k)
		if has_b:
			for code in Protocol.M3D_REASONS_ERRANDS:
				if not tpl.has("err_" + str(code)):
					errs.append("text_templates: missing 'err_%s' (M3D §7)" % code)
	# 黑龍潭：陣口走得到瑛姑小屋；陣裡走錯（單向）的出口一律繞回 hl_mud1
	var idx := room_index(view)
	if idx.has("hl_mud1"):
		if not reachable_rooms(view, "xe_heilong").has("hl_hut"):
			errs.append("heilongtan: hl_hut not reachable from xe_heilong (M3D §6.4)")
		for rid in ER_MAZE:
			if not idx.has(rid):
				errs.append("heilongtan: maze room %s missing" % rid)
				continue
			for ex in idx[rid]["room"].get("exits", []):
				if ex is Dictionary and bool(ex.get("oneway", false)) and str(ex.get("to", "")) != "hl_mud1":
					errs.append("heilongtan: %s wrong turn %s must lead back to hl_mud1" % [rid, str(ex.get("dir", ""))])
	# 切磋弟子 → 門派（E6）
	var sects: Dictionary = view.get("sects", {})
	for mid in mons:
		var smid := str(mid)
		if not (smid == "m_hs_trainee" or (smid.begins_with("m_") and smid.ends_with("_dizi") and not smid.begins_with("m_npc_"))):
			continue
		if smid == "m_hs_trainee":
			continue
		var prefix := smid.substr(2, smid.length() - 7)
		var hit := str(mons[mid].get("sect", "")) != ""
		for sid in sects:
			if str(sects[sid].get("prefix", "")) == prefix:
				hit = true
		if not hit:
			errs.append("monsters.%s: spar monster maps to no sect (M3D §6.5)" % mid)
	return errs

# ==== M3d WP-LAW ====（M3D_PLAN §2、§8.3、§8.4）
const M3D_BOOL_OPTIONS := ["bounty_enabled", "bounty_hunters", "jiebiao_enabled", "tourney_enabled"]
const M3D_INT_OPTIONS := { "equip_cooldown_ms": [0, 5000] }

## 五個 M3d 伺服器選項（缺 key = 預設；有就必須是正確型別與範圍）
func _check_m3d_options(loader: DataLoader) -> void:
	var so := loader.server_options_default
	for k in M3D_BOOL_OPTIONS:
		if so.has(k) and typeof(so[k]) != TYPE_BOOL:
			errors.append("server_options.%s must be a bool (M3D §8.3)" % k)
	for k in M3D_INT_OPTIONS:
		if so.has(k) and (typeof(so[k]) != TYPE_INT or int(so[k]) < int(M3D_INT_OPTIONS[k][0]) or int(so[k]) > int(M3D_INT_OPTIONS[k][1])):
			errors.append("server_options.%s must be an int in %s (M3D §8.3)" % [k, str(M3D_INT_OPTIONS[k])])

const LAW_NPC_IDS := ["n_law_board_xx", "n_law_board_dl", "n_law_guanye_xx_a", "n_law_guanye_xx_b",
	"n_law_guanye_dl_a", "n_law_guanye_dl_b", "n_law_tianshi_xx", "n_law_tianshi_dl"]
const LAW_NPC_IDS_B := ["n_law_board_jc", "n_law_guanye_jc_a", "n_law_guanye_jc_b", "n_law_banxian_jc"]
const LAW_MONSTERS := ["m_law_hunter_1", "m_law_hunter_2", "m_law_hunter_3"]
const LAW_TEMPLATES := ["law_license_ok", "law_license_void", "law_bounty_earned", "law_bounty_paid", "law_cleansed",
	"law_no_bounty_friend", "law_no_bounty_daily", "law_hunter_beaten", "law_hunter_escaped", "law_listed",
	"rmr_law_caught", "rmr_law_hunted", "law_deaf_1", "law_deaf_2", "law_deaf_3"]

## 共通 schema（M3D_PLAN §8.4）：CLEANSE 服務必須有 cleanse（KILLING／PK）、deaf 是 bool、martial_arts.combo 是字典時
## 有 group 與兩列 pair（各有存在的 art）；道具 M3d 效果；chore.kind 列舉。WP-LAW 自己的列：NPC、怪物、模板、err_ 原因碼
static func _check_m3d_law(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var npcs: Dictionary = view.get("npcs", {})
	for nid in npcs:
		var n: Dictionary = npcs[nid]
		var svcs: Array = n.get("services", []) if n.get("services") is Array else []
		if "CLEANSE" in svcs and not (str(n.get("cleanse", "")) in DataSchema.NPC_CLEANSE_KINDS):
			errs.append("npcs.%s: CLEANSE needs cleanse in %s (M3D §8.4)" % [nid, str(DataSchema.NPC_CLEANSE_KINDS)])
		if n.has("cleanse") and not ("CLEANSE" in svcs):
			errs.append("npcs.%s: cleanse field without CLEANSE service" % nid)
		if n.has("deaf") and typeof(n["deaf"]) != TYPE_BOOL:
			errs.append("npcs.%s: deaf must be a bool" % nid)
	var arts: Dictionary = view.get("martial_arts", {})
	for aid in arts:
		var cb: Variant = arts[aid].get("combo", null)
		if not (cb is Dictionary):
			continue   # 舊的 combo: true（WP-COMBAT 改成字典前）不檢查
		for f in DataSchema.ART_COMBO_FIELDS:
			if not (cb as Dictionary).has(f):
				errs.append("martial_arts.%s.combo: missing '%s'" % [aid, f])
		var pair: Variant = (cb as Dictionary).get("pair", [])
		if not (pair is Array) or (pair as Array).size() != 2:
			errs.append("martial_arts.%s.combo.pair must have 2 rows" % aid)
		else:
			for p in pair:
				if not (p is Dictionary) or not arts.has(str(p.get("art", ""))):
					errs.append("martial_arts.%s.combo.pair: art '%s' missing" % [aid, str(p.get("art", "")) if p is Dictionary else "?"])
	for qid in view.get("quests", {}):
		var c: Variant = view["quests"][qid].get("chore", null)
		if c is Dictionary and (c as Dictionary).has("kind") and not (str(c["kind"]) in DataSchema.CHORE_KINDS):
			errs.append("quests.%s.chore.kind '%s' not in %s" % [qid, str(c["kind"]), str(DataSchema.CHORE_KINDS)])
	# WP-LAW 自己的列（1.0B 的列在 1.0A 視圖裡不存在 → 不檢查）
	for nid in LAW_NPC_IDS + (LAW_NPC_IDS_B if npcs.has("n_law_board_jc") else []):
		if not npcs.has(nid):
			errs.append("npcs.%s missing (M3D §2.8)" % nid)
	for nid in npcs:
		var row: Dictionary = npcs[nid]
		if not str(nid).begins_with("n_law_"):
			continue
		var svcs2: Array = row.get("services", [])
		if str(nid).begins_with("n_law_guanye_") and not ("LICENSE" in svcs2):
			errs.append("npcs.%s: 官爺 needs LICENSE" % nid)
		if str(nid).begins_with("n_law_board_") and not ("BOARD" in svcs2):
			errs.append("npcs.%s: 佈告欄 needs BOARD" % nid)
		if str(nid).ends_with("_b") and str(nid).begins_with("n_law_guanye_") and row.get("deaf", false) != true:
			errs.append("npcs.%s: the _b 官爺 is the deaf one (deaf: true)" % nid)
	var mons: Dictionary = view.get("monsters", {})
	for mid in LAW_MONSTERS:
		if not mons.has(mid):
			errs.append("monsters.%s missing (M3D §2.5)" % mid)
		elif not bool(mons[mid].get("no_rewards", false)):
			errs.append("monsters.%s: hunters must be no_rewards (M3D §2.5)" % mid)
	var tpl: Dictionary = view.get("text_templates", {})
	if not tpl.is_empty():
		for k in LAW_TEMPLATES:
			if not tpl.has(k):
				errs.append("text_templates: missing '%s' (M3D §2)" % k)
		for code in Protocol.M3D_REASONS_LAW:
			if not tpl.has("err_" + str(code)):
				errs.append("text_templates: missing 'err_%s' (M3D §7)" % code)
	return errs

# ==== 0.7.0.1 ====（學不到的武功、玩家文字裡的開發標記）
## 玩家看得到的說明文字（desc／name／text）不可留里程碑或工作包標記，例如「（M3）」「（M3b 開放）」「WP-LAW」
const DEV_TAG_TABLES := ["martial_arts", "items", "npcs", "monsters", "quests"]
const DEV_TAG_FIELDS := ["desc", "name", "text"]

static func dev_tag_in(s: String) -> String:
	var re := RegEx.new()
	re.compile("(^|[^A-Za-z0-9_])(M[0-9][a-z0-9]*|WP-[A-Z]+)")
	var m := re.search(s)
	return m.get_string(2) if m != null else ""

## 武功列與師父列裡的 quest_flag 都要有東西給（任務的 flags／{"do":"flag"}、試煉的 reward_flag）；
## 0.7.0.1 之前劈石破玉拳、佛光普照掌、九陰真經、飛星術的旗標沒有任何任務給，資料裡有、玩家卻學不到
static func flags_given(view: Dictionary) -> Dictionary:
	var out := {}
	for t in ["quests", "npcs", "items"]:
		var tb: Dictionary = view.get(t, {})
		for id in tb:
			var r: Variant = tb[id]
			if not (r is Dictionary):
				continue
			for k in r:
				if str(k) != "requires":
					_collect_given(r[k], out)
			var tr: Variant = (r as Dictionary).get("trial", null)
			if tr is Dictionary and str(tr.get("reward_flag", "")) != "":
				out[str(tr["reward_flag"])] = true
	return out

static func _collect_given(v: Variant, out: Dictionary) -> void:
	if v is Dictionary:
		if str(v.get("do", "")) == "flag" and v.has("flag"):
			out[str(v["flag"])] = true
		for k in v:
			var x: Variant = v[k]
			if str(k) == "flags" and x is Array:
				for f in x:
					if f is String:
						out[f] = true
			elif str(k) != "requires" and str(k) != "if":
				_collect_given(x, out)
	elif v is Array:
		for x in v:
			_collect_given(x, out)

static func _check_0701(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	for t in DEV_TAG_TABLES:
		var tb: Dictionary = view.get(t, {})
		for id in tb:
			var r: Variant = tb[id]
			if not (r is Dictionary):
				continue
			for f in DEV_TAG_FIELDS:
				if r.get(f) is String:
					var tag := dev_tag_in(str(r[f]))
					if tag != "":
						errs.append("%s.%s.%s: player text contains dev tag '%s'" % [t, id, f, tag])
	var given := flags_given(view)
	for t in ["martial_arts", "masters"]:
		var tb2: Dictionary = view.get(t, {})
		for id in tb2:
			var r2: Variant = tb2[id]
			if not (r2 is Dictionary) or bool(r2.get("monster_only", false)):
				continue
			for c in r2.get("requires", []):
				if c is Dictionary and str(c.get("type", "")) == "quest_flag" and not given.has(str(c.get("flag", ""))):
					errs.append("%s.%s: quest_flag '%s' is never given by any quest/trial (art unobtainable)" % [t, id, str(c.get("flag", ""))])
	return errs
