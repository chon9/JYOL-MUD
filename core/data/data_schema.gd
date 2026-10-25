class_name DataSchema
extends RefCounted
## 欄位型別表與交叉參照表（TECH_ARCH 5.2、5.5.2、5.6）。
## 路徑語法：用 "." 分隔；"key[]" 代表陣列逐一處理；"*" 代表字典的所有值。

const INT_FIELDS := {
	"eras": ["order"],
	"rule_profiles": ["rules.xuedian_cap",
		# M3C2_PLAN §8.4（WP-PACE）
		"rules.novice_learn_pct", "rules.novice_jing_pct", "rules.novice_learn_below",
		# M3c2 審查：新手期另看實戰（novice_xp_below）與雜務＋切磋學點的一輩子上限（novice_lp_cap）
		"rules.novice_xp_below", "rules.novice_lp_cap"],
	"attributes": ["roll_cap"],
	"basic_skills": ["max_level", "attr_bonus_per10.*", "attr_bonus_cap.*"],
	"sects": ["join_requires[].value", "expel_rules[].value", "sect_skill_cap", "sect_art_cap_bonus",
		# M3A_PLAN 3.1
		"teach_requires[].value", "hostile_entry[].count[]", "hostile_entry[].if[].value",
		"sect_skill_gain[].prof", "sect_skill_penalties[].levels", "sect_skill_penalties[].if[].value",
		# M3B_PLAN §4.1（practice、harass）
		"practice.cost.jing", "practice.cost.shen", "practice.cost.neili", "practice.prof[]", "practice.per_npc_cd_s",
		"practice.alms[].money[]", "practice.alms[].n", "harass[].count[]", "harass[].unless[].value"],
	# M3B_PLAN §4.2（新表）
	"sect_ranks": ["rank", "requires[].value", "cost.fame", "cost.lilian", "cost.money"],
	# M3B_PLAN §4.7（新表）
	"escort_routes": ["consign_delay_shichen"],
	"sect_rules": ["ok_if[].value"],
	"martial_arts": ["self_study_until", "self_study_cap", "party_size", "requires[].value",
		"moves[].unlock_level", "moves[].power", "moves[].range",
		"moves[].cost_inner", "moves[].cost_jing"],
	"masters": ["cap", "price", "requires[].value"],
	"regions": ["suggested_xp[]", "world_pos[]"],
	"npcs": ["inn_price", "travel[].price", "meal.food", "meal.water", "hostile_if[].value",
		"fight.requires[].value",
		# M3A_PLAN 6.8、6.9
		"meal.requires[].value", "guide.requires[].value", "trial.party_min", "trial.party_max", "trial.requires[].value",
		# M3C_PLAN §9.4（攻擊 NPC）
		"attack.respawn", "attack.group[].count[]", "attack.group_repeat[].count[]", "attack.requires[].value"],
	"monsters": ["stats.*", "skills.*", "arts[].level", "weapon_power", "armor_power", "combat_xp_ref",
		"learn_points", "combat_xp", "drops[].min", "drops[].max", "money.min", "money.max",
		"morality_on_kill", "killing_intent_on_kill", "drops[].requires[].value"],
	"items": ["atk", "def", "weight", "price", "spoil_days", "stack", "effects[].value",
		# M3B_PLAN §4.6
		"grade",
		# M3C_PLAN §9.4（WP-LOOT 欄位）
		"official.atk", "official.def", "official.weight", "manual.cap", "manual.literacy_min", "manual.prof",
		"manual.jing", "manual.shen", "bonus.*", "requires[].value", "manual.requires[].value"],
	# M3C_PLAN §9.4（新表；檔案不存在時是空表）
	"loot_tables": ["guaranteed[].min", "guaranteed[].max", "groups[].pick[].w", "lockout_shichen"],
	"quests": ["requires[].value", "give_items[].n", "steps[].count", "rewards.money",
		"rewards.combat_xp", "rewards.learn_points", "rewards.fame", "rewards.morality",
		"rewards.items[].n", "rewards.skill_prof.*",
		# STORY_PLAN §4.2（第 2 版列）
		"repeat.max", "stages[].objectives[].count", "stages[].objectives[].requires[].value",
		"stages[].next[].if[].value", "stages[].fail_if[].value", "stages[].room_actions[].requires[].value",
		"outcomes.*.rewards.money", "outcomes.*.rewards.combat_xp", "outcomes.*.rewards.learn_points",
		"outcomes.*.rewards.fame", "outcomes.*.rewards.morality", "outcomes.*.rewards.lilian",
		"outcomes.*.rewards.killing_intent", "outcomes.*.rewards.items[].n", "outcomes.*.rewards.skill_prof.*",
		"outcomes.*.rewards.learn.*",
		# M3B_PLAN §4.9
		"outcomes.*.rewards.sect_rank.rank",
		# M3C2_PLAN §8.4（WP-PACE：門派雜務）
		"chore.lp", "chore.decay_pct[]", "chore.cost.*", "chore.prof_below"],
	# STORY_PLAN §5（WP-MERGE 從碎片建立；檔案不存在時是空表）
	"rumors": ["weight", "requires[].value"],
	"wanderers": ["move_every_ke", "aggro.chance_pct", "aggro.requires[].value", "talk_fight.requires[].value"],
	"ambient": ["weight", "requires[].value"],
	"reactions": ["price_pct", "when[].value"],
	"life_skills": ["jing_cost", "cooldown_s", "cap", "yield[].n[]", "recipes[].inputs[].n",
		"recipes[].output.n", "recipes[].min_level",
		# M3B_PLAN §4.5（第 2 版）
		"yield[].min_level", "recipes[].jing_cost", "recipes[].prof", "hunt.drops[].n[]", "hunt.drops[].min_level",
		"yield[].n_per_levels"],   # M3c2 WP-ECON（M3C2_PLAN §4.4、§9.2）
	"status_effects": ["duration_actions", "persist_tick_real_s", "persist_ticks_per_level"],
	# 房間圖（M1_PLAN 3.11.8，D1）
	"maps": ["escape_tiles_hint", "rooms[].encounter.table[].w", "rooms[].encounter.table[].count[]",
		"rooms[].requires[].value",
		# M3B_PLAN §4.4、§4.10
		"rooms[].hunt_table[].w", "rooms[].on_enter_status.level", "rooms[].on_enter_status.unless[].value"],
	"server_options": ["wait_mode_timeout_s", "wait_mode_timeout_min_s", "wait_mode_round_budget_s",
		"guild_signers", "newbie_pk_protect_xp", "max_players", "autosave_interval_s",
		"game_day_real_s", "bank_capacity", "rule_profile.overrides.xuedian_cap",
		# M2_PLAN 4.7.1
		"chat_water_cost", "chat_min_interval_ms", "party_max", "battle_max_humans", "pending_ttl_real_s", "pending_retry_cooldown_real_s",
		"mail_inbox_max", "mail_min_interval_real_s", "corpse_auth_max",
		# M3A_PLAN 3.10
		"jail_breach_days", "jail_enemy_days", "ban_days", "jail_ransom",
		# STORY_PLAN §5.5
		"rumor_min_gap_s", "rumor_chat_inner_min", "villain_warn_s",
		# M3B_PLAN §4.11
		"bank_money_cap", "consign_fee_base", "consign_fee_per_weight", "consign_hold_days",
		"org_found_fame", "org_signer_fame", "org_found_fee", "org_member_max", "org_petition_days",
		# M3C_PLAN §9.3
		"npc_respawn_pct", "loot_drop_pct",
		# M3C2_PLAN §8.3（WP-PACE）
		"spar_daily_cap",
		# M3D_PLAN §8.3（WP-COMBAT）
		"equip_cooldown_ms"],
	# ROGUE WP-RUN（ROGUE_PLAN §7；檔案不存在時是空表）
	"rogue_rules": ["attr_cap", "art_cap", "weapons_keep", "ally_max", "ally_min_round", "boss_every", "kind_weights.*",
		"rarity_bands[].from", "rarity_bands[].w[]", "boss_reward_w[]", "attr_points.*", "art_level.*", "upgrade_by.*",
		"points_cap", "points_soft", "points_half"],
	"rogue_cards": ["weight", "min_round", "level", "points", "override.qi", "override.neili", "override.attrs.*",
		"override.skills.*", "override.armor_power", "override.weapon_atk", "override.effective_inner"],
	"rogue_foes": ["tier", "min_round", "max_round", "weight", "override.qi", "override.neili", "override.attrs.*",
		"override.skills.*", "override.armor_power", "override.weapon_atk", "override.effective_inner"],
}

## table -> [[path, target_table], ...]；空字串與 null 不檢查。
## masters.skill_id（可指向四種技能表）、npcs.room、travel.to_room 等房間參照由 data_lint 自訂檢查（M1_PLAN 3.11.15）。
const REFS := {
	"sects": [["join_requires[].sect", "sects"], ["home_city", "regions"], ["gate_region", "regions"],
		["head_npc", "npcs"],
		# M3B_PLAN §4.1
		["harass[].monster", "monsters"]],
	"sect_rules": [["sect", "sects"]],
	"martial_arts": [["sect_id", "sects"], ["base_skill", "basic_skills"], ["requires[].sect", "sects"],
		["moves[].flavor", "text_templates"], ["moves[].status", "status_effects"]],
	"masters": [["npc_id", "npcs"], ["requires[].sect", "sects"], ["tool", "items"]],
	"npcs": [["region", "regions"], ["talk", "text_templates"], ["quests[]", "quests"],
		["join_sect", "sects"], ["shop.items[]", "items"], ["fight.monster", "monsters"],
		# M3B_PLAN §4.8
		["escort.city", "regions"],
		# M3C_PLAN §9.4
		["attack.monster", "monsters"], ["attack.group[].monster", "monsters"],
		["attack.group_repeat[].monster", "monsters"], ["attack.sect", "sects"]],
	"monsters": [["arts[].art", "martial_arts"], ["drops[].item", "items"],
		# M3C_PLAN §9.4
		["loot_table", "loot_tables"]],
	"loot_tables": [["guaranteed[].item", "items"], ["groups[].pick[].item", "items"]],
	"quests": [["giver", "npcs"], ["give_items[].id", "items"], ["rewards.items[].id", "items"],
		["requires[].sect", "sects"],
		# STORY_PLAN §8.3 Day-0（房間參照由 data_lint 自訂檢查）
		["stages[].objectives[].npc", "npcs"], ["stages[].objectives[].item", "items"],
		["stages[].objectives[].monster", "monsters"], ["outcomes.*.rewards.items[].id", "items"],
		# M3C2_PLAN §8.4（WP-PACE）
		["chore.sect", "sects"]],
	"wanderers": [["npc", "npcs"], ["monster", "monsters"]],
	"rumors": [["quest", "quests"]],
	"life_skills": [["tool", "items"], ["yield[].item", "items"], ["recipes[].inputs[].item", "items"],
		["recipes[].output.item", "items"],
		# M3B_PLAN §4.5
		["tools[]", "items"], ["recipes[].tools[]", "items"], ["hunt.drops[].item", "items"]],
	# M3B_PLAN §9.3 Day-0（新表）
	"sect_ranks": [["sect", "sects"], ["quest", "quests"]],
	"escort_routes": [["from_city", "regions"], ["to_city", "regions"], ["job_quest", "quests"]],
	# ROGUE WP-RUN（ROGUE_PLAN §7.2、§7.3；ART 卡的 art 可以是 basic_*，由 data_lint 的 _check_rogue 檢查）
	"rogue_cards": [["item", "items"], ["monster", "monsters"], ["npc", "npcs"]],
	"rogue_foes": [["monster", "monsters"], ["npc", "npcs"], ["minions[]", "rogue_foes"]],
}

## 5.6 的開關與預設值（1.0 行為）
const RULE_DEFAULTS := {
	"death_rule": "STANDARD",
	"corpse_window": "CLASSIC_30",
	"betrayal_halves_basics": false,
	"xuedian_cap": 65200,
	"jail_enabled": true,
	"self_study_cap": "NONE",
	# M3A_PLAN 3.10
	"sect_violation_mode": "JAIL",
	"later_battle_cmds": true,
	# M3C_PLAN §9.2
	"npc_attack": true,
	"divine_source": "BOSS_DROP",
	"manuals": true,
	"loot_broadcast": true,
	# M3c 審查：掉落表裡 src "later"（後期版才有）的物品掉不掉（classic_strict 關）
	"later_loot": true,
	# M3c 第二輪審查：新手（實戰 < newbie_pk_protect_xp）善惡為負不被守城官兵追殺、城內行兇不招來官兵【設計提案】；
	# classic_strict 關（2001 規則：news_4-2「善惡度為負…只要進城就會被城中守衛追殺」沒有新手例外）
	"newbie_guard_spare": true,
	# M3C2_PLAN §8.2（WP-PACE）：新手學藝加速、雜務學點、切磋獎勵。預設＝關（舊的自訂組合不會突然變快）；四個內建組合明確寫值
	"novice_learn_pct": 100,
	"novice_jing_pct": 100,
	"novice_learn_below": 40,
	# M3c2 審查：實戰到這裡就不算新手（新手學藝加速、雜務／切磋學點都停）；雜務＋切磋學點一輩子最多這麼多【設計提案】
	"novice_xp_below": 30000,
	"novice_lp_cap": 4000,
	"chore_xuedian": false,
	"spar_rewards": false,
	# M3D_PLAN §8.2：PK值 被動遞減（classic_strict 關＝2001 沒有）、2001 的「閃」指令、交易之道影響賣價（選做 F）
	"pk_decay": true,
	"dodge_cmd": true,
	"trade_sell_bonus": false,
	# M3d 審查（第三輪）：後期活動——門派比武與武林大會（2002）、血刀血池比武（2003）。classic_strict 關（2001 只有劫鏢與比武場）
	"later_events": true,
}

const RULE_ENUMS := {
	"death_rule": ["STRICT_2001", "STANDARD", "CASUAL"],
	"corpse_window": ["CLASSIC_30", "LATER_10"],
	"self_study_cap": ["NONE", "HJ_1_5X"],
	"sect_violation_mode": ["JAIL", "EXPEL", "BAN"],
	# M3C_PLAN §9.2
	"divine_source": ["NONE", "BOSS_DROP"],
}

const REQUIRE_TYPES := ["morality_min", "morality_max", "sect", "no_sect", "not_enemy_of", "gender",
	"attr_min", "skill_min", "combat_xp_min", "pk_max", "unmarried", "quest_flag", "quest_done",
	"killing_intent_max", "era_enabled", "sect_enabled", "rule",
	# M3A_PLAN 3.7
	"has_item", "any_of", "enemy_of", "pk_min", "killing_intent_min", "sect_master", "party_size_min", "hour_in",
	# M3a 審查修正：旗標「沒有」（古墓守宮砂未失）；desc 選填，給介面顯示
	"not_flag",
	# STORY_PLAN §4.6
	"quest_active", "quest_stage", "quest_var", "quest_outcome", "lilian_min", "fame_min", "combat_xp_max",
	# 審查修正：NPC 依任務進度換話、預告與環境句只對還沒做的人（「沒做完」「沒在做」）
	"quest_not_done", "quest_not_active",
	# 審查修正：上限型武功門檻（藍鳳凰：基本毒術 < 30，台免）
	"skill_max",
	# 0.7.0.1 審查：上限型屬性門檻
	"attr_max",
	# M3B_PLAN §4.3
	"sect_not", "sect_rank_min", "org_member", "no_org", "life_min",
	# M3C2_PLAN §2.3.1（WP-PACE）
	"money_max",
	# M3D_PLAN §8.4：combo_ready（COMBAT）、counter_max（ARTS）、bounty_listed／has_license（LAW）、jb_active（EVENTS）
	"combo_ready", "counter_max", "bounty_listed", "has_license", "jb_active"]

## 各條件 type 必備的欄位（M1_PLAN 3.11.1；data_lint 檢查）
const REQUIRE_FIELDS_BY_TYPE := {
	"morality_min": ["value"], "morality_max": ["value"], "sect": ["sect"], "no_sect": [],
	"not_enemy_of": ["sect"], "gender": ["value"], "attr_min": ["attr", "value"],
	"skill_min": ["skill", "value"], "combat_xp_min": ["value"], "pk_max": ["value"],
	"quest_flag": ["flag"], "quest_done": ["quest"], "killing_intent_max": ["value"],
	"era_enabled": ["era"], "sect_enabled": ["sect"], "rule": ["key", "value"], "unmarried": [],
	# M3A_PLAN 3.7（has_item 的 n 選填，預設 1；any_of 的內層條件由 lint 逐一檢查，最多 2 層）
	"has_item": ["item"], "any_of": ["options"], "enemy_of": ["sect"], "pk_min": ["value"],
	"killing_intent_min": ["value"], "sect_master": ["npc"], "party_size_min": ["value"], "hour_in": ["hours"],
	"not_flag": ["flag"],
	# STORY_PLAN §4.6
	"quest_active": ["quest"], "quest_stage": ["quest", "stage"], "quest_var": ["quest", "var", "value"],
	"quest_outcome": ["quest", "outcome"], "lilian_min": ["value"], "fame_min": ["value"], "combat_xp_max": ["value"],
	"quest_not_done": ["quest"], "quest_not_active": ["quest"],
	"skill_max": ["skill", "value"], "attr_max": ["attr", "value"],
	# M3B_PLAN §4.3（org_member 的 org 選填：空 = 任何組織）
	"sect_not": ["sect"], "sect_rank_min": ["sect", "value"], "org_member": [], "no_org": [], "life_min": ["skill", "value"],
	# M3C2_PLAN §2.3.1
	"money_max": ["value"],
	# M3D_PLAN §8.4
	"combo_ready": ["art"], "counter_max": ["key", "value"], "bounty_listed": [], "has_license": [], "jb_active": [],
}

## 十二時辰名（masters.hours、hour_in 條件；與 WorldClock 相同順序）
const SHICHEN := ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
## sect_rules 的合法值（M3A_PLAN 3.3；其他 event 保留給 M3b，lint 拒絕）
const SECT_RULE_TIERS := ["BREACH"]
const SECT_RULE_KINDS := ["STATE", "EVENT"]
const SECT_RULE_EVENTS := ["KILL_SAME_SECT", "ENTER_REGION",
	# M3C_PLAN §5.6、§9.4
	"ATTACK_SECT_NPC", "KILL_GOOD_NPC", "ATTACK_MASTER"]
## sects.hostile_entry[].rooms
const HOSTILE_ROOMS := ["GATE", "INNER", "ALL"]
const SECT_VISITORS := ["OPEN", "MEMBERS"]

# ---------------------------------------------------------------- M3b（M3B_PLAN §4；WP-SECT Day-0）
## 房間設施（§4.4）：既有 4 種＋M3b 7 種
const FEATURES := ["FIELD", "WOOD", "WATER", "STOVE", "MINE", "FORGE", "CAST", "LOOM", "TANNERY", "KILN", "HUNT"]
## 房間 jail_scope（§4.4）：SECT＝各派思過處（預設）、CAPITAL＝京城監獄（全資料最多一間）
const JAIL_SCOPES := ["SECT", "CAPITAL"]
## 伺服器選項 jail_location（§4.11、O12）
const JAIL_LOCATIONS := ["AUTO", "SECT", "CAPITAL"]
## 伺服器選項 gb_assembly（§4.11、O8）
const ASSEMBLY_MODES := ["DAILY", "MONTHLY"]
## life_skills.mode（§4.5）
const LIFE_MODES := ["GATHER", "CRAFT", "HUNT"]
## sect_ranks.promote（§4.2）
const RANK_PROMOTES := ["JOIN", "QUEST", "AUTO"]
## sect_ranks.cost 能用的鍵（§9.5 #3）
const RANK_COST_KEYS := ["fame", "lilian", "money"]
## NPC 服務（同 Protocol.NPC_SERVICES；lint 從這裡讀，免得 core/data 依賴 protocol 的順序）
const NPC_SERVICES := ["SHOP", "TEACH", "JOIN", "INN", "RESPAWN", "TRAVEL", "MEAL", "FIGHT", "QUEST", "GUARD",
	"BETRAY", "JAIL", "TRIAL", "GUIDE", "BANK", "ESCORT", "ORG", "RANK",
	# M3D_PLAN §8.4
	"BOARD", "LICENSE", "CLEANSE", "TOURNEY"]
# ---------------------------------------------------------------- M3d（M3D_PLAN §8.4；WP-LAW Day-0）
## NPC 選填欄位 cleanse 的值（服務 CLEANSE 必須有）；deaf: bool（LICENSE 的耳聾官爺）
const NPC_CLEANSE_KINDS := ["KILLING", "PK"]
## 道具 effects[].type 的 M3d 新值（data_lint EFFECT_TYPES 同步）
const M3D_EFFECT_TYPES := ["FLEE_ANYWHERE", "LIGHT", "LIANDU", "SUMMON"]
## quests.chore.kind（WP-ERRANDS；缺＝SECT）；chore.decay_all: bool
const CHORE_KINDS := ["SECT", "TOWN"]
## martial_arts.combo（Dictionary，取代舊的 bool）必備欄位；pair 一定 2 列，每列必有 art
const ART_COMBO_FIELDS := ["group", "pair"]
## 新表必備欄位（WP-MERGE 的 lint 用）
const REQUIRED_FIELDS := {
	"sect_ranks": ["id", "sect", "rank", "name", "requires", "promote", "cost", "era", "src"],
	"escort_routes": ["id", "from_city", "to_city", "consign_delay_shichen", "job_quest", "era", "src"],
}
# ==== ROGUE WP-RUN ====（ROGUE_PLAN §2.2、§7）
## eras.mode_only（bool）：只能用於特定模式（江湖試煉）的 era；MUD 世界不得啟用（WorldServer 擋）
const ERA_MODE_ONLY := "mode_only"
const ROGUE_ERA := "rogue"
## rogue_cards.kind（同 RogueRules.KINDS；core/data 不依賴 core/rogue 的載入順序，照抄字面值）
const ROGUE_CARD_KINDS := ["ART", "WEAPON", "ATTR", "ALLY"]
## rogue_foes.override 的鍵（同 RogueFoes.OVERRIDE_KEYS）
const ROGUE_FOE_OVERRIDE_KEYS := ["qi", "neili", "attrs", "skills", "armor_power", "weapon_atk", "effective_inner"]
## 新表必備欄位
const ROGUE_REQUIRED := {
	"rogue_cards": ["id", "kind", "rarity", "weight", "min_round", "era", "src"],
	"rogue_foes": ["id", "monster", "tier", "min_round", "max_round", "boss", "weight", "era", "src"],
	"rogue_rules": ["id", "era", "src"],
}

## era 列是不是模式專用
static func era_mode_only(eras: Dictionary, era_id: String) -> bool:
	var r: Variant = eras.get(era_id, {})
	return r is Dictionary and (r as Dictionary).get(ERA_MODE_ONLY, false) == true

## 江湖試煉三張表的列檢查（data_lint 用；view 是含 rogue 的生效視圖）
static func check_rogue(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	for t in ROGUE_REQUIRED:
		var tb: Dictionary = view.get(t, {})
		for id in tb:
			var row: Dictionary = tb[id]
			for f in ROGUE_REQUIRED[t]:
				if not row.has(f):
					errs.append("%s.%s: missing '%s'" % [t, id, f])
			if str(row.get("era", "")) != ROGUE_ERA:
				errs.append("%s.%s: era must be '%s'" % [t, id, ROGUE_ERA])
			if not str(id).begins_with("rg_"):
				errs.append("%s.%s: id must start with rg_" % [t, id])
	var cards: Dictionary = view.get("rogue_cards", {})
	for id in cards:
		var c: Dictionary = cards[id]
		var kind := str(c.get("kind", ""))
		if not (kind in ROGUE_CARD_KINDS):
			errs.append("rogue_cards.%s: bad kind '%s'" % [id, kind])
		if not (str(c.get("rarity", "")) in ITEM_RARITIES):
			errs.append("rogue_cards.%s: bad rarity '%s'" % [id, str(c.get("rarity", ""))])
		match kind:
			"ART":
				var art := str(c.get("art", ""))
				if not view.get("martial_arts", {}).has(art) and not view.get("basic_skills", {}).has(art):
					errs.append("rogue_cards.%s: art '%s' missing" % [id, art])
				elif view.get("martial_arts", {}).has(art) and bool(view["martial_arts"][art].get("monster_only", false)):
					errs.append("rogue_cards.%s: art '%s' is monster_only" % [id, art])
			"WEAPON":
				var it: Dictionary = view.get("items", {}).get(str(c.get("item", "")), {})
				if it.is_empty() or not (str(it.get("slot", "")) in ITEM_SLOTS):
					errs.append("rogue_cards.%s: item '%s' missing or not equippable" % [id, str(c.get("item", ""))])
			"ALLY":
				if not view.get("monsters", {}).has(str(c.get("monster", ""))):
					errs.append("rogue_cards.%s: monster '%s' missing" % [id, str(c.get("monster", ""))])
		if c.has("override"):
			if not (c["override"] is Dictionary) or kind != "ALLY":
				errs.append("rogue_cards.%s: override only on ALLY cards (object)" % id)
			else:
				for k in c["override"]:
					if not (str(k) in ROGUE_FOE_OVERRIDE_KEYS):
						errs.append("rogue_cards.%s: unknown override key '%s'" % [id, str(k)])
	var foes: Dictionary = view.get("rogue_foes", {})
	for id in foes:
		var f: Dictionary = foes[id]
		var tier := int(f.get("tier", 0))
		if tier < 1 or tier > 6:
			errs.append("rogue_foes.%s: tier must be 1..6" % id)
		var mr: Dictionary = view.get("monsters", {}).get(str(f.get("monster", "")), {})
		if not mr.is_empty() and str(mr.get("ai", "")) == "coward":
			errs.append("rogue_foes.%s: coward monsters are not allowed" % id)
		if f.get("minions", []) is Array and (f.get("minions", []) as Array).size() > 2:
			errs.append("rogue_foes.%s: at most 2 minions" % id)
		if f.has("override"):
			if not (f["override"] is Dictionary):
				errs.append("rogue_foes.%s: override must be an object" % id)
			else:
				for k in f["override"]:
					if not (str(k) in ROGUE_FOE_OVERRIDE_KEYS):
						errs.append("rogue_foes.%s: unknown override key '%s'" % [id, str(k)])
	return errs

# ---------------------------------------------------------------- M3c（M3C_PLAN §9.4；WP-NPCPK Day-0）
const ITEM_SLOTS := Protocol.SLOTS
const ITEM_RARITIES := ["COMMON", "FINE", "RARE", "TREASURE", "DIVINE"]
const NPC_ATTACK_MODES_DATA := ["KILL", "CHALLENGE"]
const NPC_ATTACK_CATEGORIES := ["CIVILIAN", "CHILD", "ANIMAL", "WORKER", "GUARD", "WUSHI", "VILLAIN",
	"SECT_GATE", "SECT_DISCIPLE", "SECT_MASTER"]
const NPC_ATTACK_VIA := ["CTRL", "MENU", "BOTH"]
const NPC_ATTACK_EVENTS := ["", "MIEPAI", "ATTACK_MASTER"]
## sects.sect_skill_penalties[].trigger 的已知值（lint 用）
const SECT_PENALTY_TRIGGERS := ["DRINK", "ENTER_REGION", "DAILY_IF", "KILL_NPC_ALIGNMENT"]

## sects 新選填欄位的預設值（§4.1；其他 10 派不必補）
const SECT_M3B_DEFAULTS := { "ranks": "", "practice": null, "harass": [], "no_escort": false, "respawn_at_gate": true }

## 條件陣列逐一檢查欄位（含 any_of 內層，最多 depth 層）；回傳錯誤字串陣列（data_lint 用）
static func check_conditions(conds: Variant, where: String, depth: int = 0) -> PackedStringArray:
	var errs := PackedStringArray()
	if not (conds is Array):
		errs.append("%s: requires must be an array" % where)
		return errs
	for c in conds:
		if not (c is Dictionary):
			errs.append("%s: condition is not an object" % where)
			continue
		var t := str(c.get("type", ""))
		if not (t in REQUIRE_TYPES):
			errs.append("%s: unknown condition type '%s'" % [where, t])
			continue
		for f in REQUIRE_FIELDS_BY_TYPE.get(t, []):
			if not c.has(f):
				errs.append("%s: %s missing field '%s'" % [where, t, f])
		if t == "any_of":
			if depth >= 1:
				errs.append("%s: any_of nested too deep (max 2 levels)" % where)
				continue
			var opts: Variant = c.get("options", [])
			if not (opts is Array) or (opts as Array).is_empty():
				errs.append("%s: any_of.options must be a non-empty array of arrays" % where)
				continue
			for i in (opts as Array).size():
				errs.append_array(check_conditions(opts[i], "%s.any_of[%d]" % [where, i], depth + 1))
		elif t == "hour_in":
			var hs: Variant = c.get("hours", [])
			if not (hs is Array):
				errs.append("%s: hour_in.hours must be an array" % where)
			else:
				for h in hs:
					if not (str(h) in SHICHEN):
						errs.append("%s: hour_in bad shichen '%s'" % [where, str(h)])
	return errs

## 把整數欄位從 float 轉回 int（就地修改）
static func coerce(table: String, row: Variant) -> void:
	for path in INT_FIELDS.get(table, []):
		_coerce_path(row, (path as String).split("."), 0)

static func _coerce_path(node: Variant, segs: PackedStringArray, i: int) -> void:
	if i >= segs.size():
		return
	var seg := segs[i]
	var last := i == segs.size() - 1
	if seg == "*":
		if node is Dictionary:
			for k in node.keys():
				if last:
					node[k] = _to_int(node[k])
				else:
					_coerce_path(node[k], segs, i + 1)
		return
	var is_arr := seg.ends_with("[]")
	var key := seg.trim_suffix("[]")
	if not (node is Dictionary) or not node.has(key):
		return
	if is_arr:
		var arr: Variant = node[key]
		if not (arr is Array):
			return
		for j in arr.size():
			if last:
				arr[j] = _to_int(arr[j])
			else:
				_coerce_path(arr[j], segs, i + 1)
	elif last:
		node[key] = _to_int(node[key])
	else:
		_coerce_path(node[key], segs, i + 1)

static func _to_int(v: Variant) -> Variant:
	if typeof(v) == TYPE_FLOAT:
		return int(v)
	return v

## 取出某個路徑上的所有值（供交叉參照與 lint 使用）
static func values_at(node: Variant, path: String) -> Array:
	var out: Array = []
	_collect(node, path.split("."), 0, out)
	return out

static func _collect(node: Variant, segs: PackedStringArray, i: int, out: Array) -> void:
	if i >= segs.size():
		out.append(node)
		return
	var seg := segs[i]
	if not (node is Dictionary):
		return
	if seg == "*":
		for k in node:
			_collect(node[k], segs, i + 1, out)
		return
	var key := seg.trim_suffix("[]")
	if not node.has(key):
		return
	if seg.ends_with("[]"):
		if node[key] is Array:
			for v in node[key]:
				_collect(v, segs, i + 1, out)
	else:
		_collect(node[key], segs, i + 1, out)

## 生效視圖裡，生效的列只能引用生效的列（5.5.2）
static func check_references(view: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	for table in REFS:
		if not view.has(table):
			continue
		for id in view[table]:
			var row: Dictionary = view[table][id]
			for ref in REFS[table]:
				var target: String = ref[1]
				for v in values_at(row, ref[0]):
					if v == null or (v is String and v == ""):
						continue
					if not view.has(target) or not view[target].has(v):
						errs.append("%s.%s: %s -> %s '%s' missing or inactive" % [table, id, ref[0], target, str(v)])
	return errs

## ---------------------------------------------------------------- data/art.json（戰鬥美術，純表現層）
## 不屬於遊戲資料（不進 DataLoader、不影響 content_hash）；由 data_lint 與 ArtRegistry 使用。
const ART_SECTIONS := ["units", "player_fallback", "backgrounds", "bg_default", "fx", "map", "map_icons", "weapon_fx", "weapon_icons"]
const ART_POSES := ["idle", "attack", "hurt"]
## M3c 第二輪審查：art.units 的 body 欄（人形／非人形；省略＝依圖的長寬比猜）
const ART_BODIES := ["human", "beast"]
## M3c（M3C_PLAN §2.3）：純表現的檔名區塊。鍵 → 檔名＝前綴＋鍵（weapon_fx 的武功類別用 fx_skill_）。
const ART_MAP_KEYS := ["world_base", "region_bg", "node_room", "node_current", "node_fog", "marker_here", "compass", "frame_title"]
const ART_MAP_ICON_KEYS := ["city", "sect", "cave", "wild", "station", "inn", "shop", "master", "record", "field", "wood", "water", "stove", "danger", "quest", "exit"]
const ART_WEAPON_FX_KEYS := ["sword", "blade", "staff", "whip", "fist", "claw", "stab", "hidden"]
const ART_SKILL_FX_KEYS := ["inner", "poison", "medic", "formation"]
const ART_WEAPON_ICON_KEYS := ["sword", "blade", "staff", "whip", "claw", "fist"]

## 檢查 art.json：別名鏈可解、比例合理、每個地區都有背景、每隻怪物與定點戰鬥 NPC 都有圖條目。
## tables 至少要有 regions、monsters、npcs（可用 DataLoader.all_tables）。
static func check_art(art: Dictionary, tables: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	if art.get("table", "") != "art":
		errs.append("art.json: table field must be 'art'")
	for sec in ART_SECTIONS:
		if not art.has(sec):
			errs.append("art.json: missing '%s'" % sec)
	var units: Dictionary = art.get("units", {}) if art.get("units") is Dictionary else {}
	for key in units:
		var e: Variant = units[key]
		if not (e is Dictionary):
			errs.append("art.units.%s: not an object" % key)
			continue
		var has_sprite := str(e.get("sprite", "")) != ""
		var alias := str(e.get("alias", ""))
		if not has_sprite and alias == "":
			errs.append("art.units.%s: needs 'sprite' or 'alias'" % key)
		if alias != "" and not units.has(alias):
			errs.append("art.units.%s: alias '%s' missing" % [key, alias])
		if e.has("scale") and (not (typeof(e["scale"]) in [TYPE_INT, TYPE_FLOAT]) or float(e["scale"]) <= 0.0 or float(e["scale"]) > 3.0):
			errs.append("art.units.%s: scale must be a number in (0, 3]" % key)
		if e.has("y_offset") and not (typeof(e["y_offset"]) in [TYPE_INT, TYPE_FLOAT]):
			errs.append("art.units.%s: y_offset must be a number" % key)
		if has_sprite and not e.has("scale"):
			errs.append("art.units.%s: sprite entry needs 'scale'" % key)
		# M3c 第二輪審查：body（human／beast）＝人形與否的明確標記（名牌武器圖示、出招特效）；省略＝依圖的長寬比
		if e.has("body") and not (str(e["body"]) in ART_BODIES):
			errs.append("art.units.%s: body must be one of %s" % [key, str(ART_BODIES)])
		if _art_cycle(units, key, "alias"):
			errs.append("art.units.%s: alias cycle" % key)
		if key.begins_with("m_") and not tables.get("monsters", {}).has(key):
			errs.append("art.units.%s: unknown monster id" % key)
		if key.begins_with("n_") and not tables.get("npcs", {}).has(key):
			errs.append("art.units.%s: unknown npc id" % key)
	for mid in tables.get("monsters", {}):
		if not units.has(mid):
			errs.append("art.units: monster '%s' has no art entry" % mid)
	for nid in tables.get("npcs", {}):
		var f: Variant = tables["npcs"][nid].get("fight", {})
		if f is Dictionary and str(f.get("monster", "")) != "" and not units.has(nid):
			errs.append("art.units: fight npc '%s' has no art entry" % nid)
	var fb: Dictionary = art.get("player_fallback", {}) if art.get("player_fallback") is Dictionary else {}
	for g in ["m", "f"]:
		if not units.has(str(fb.get(g, ""))):
			errs.append("art.player_fallback.%s: must name a units entry" % g)
	var bgs: Dictionary = art.get("backgrounds", {}) if art.get("backgrounds") is Dictionary else {}
	for key in bgs:
		var e: Variant = bgs[key]
		if not (e is Dictionary):
			errs.append("art.backgrounds.%s: not an object" % key)
			continue
		var alias := str(e.get("alias", ""))
		if str(e.get("bg", "")) == "" and alias == "":
			errs.append("art.backgrounds.%s: needs 'bg' or 'alias'" % key)
		if alias != "" and not bgs.has(alias):
			errs.append("art.backgrounds.%s: alias '%s' missing" % [key, alias])
		if _art_cycle(bgs, key, "alias"):
			errs.append("art.backgrounds.%s: alias cycle" % key)
		if not tables.get("regions", {}).has(key):
			errs.append("art.backgrounds.%s: unknown region id" % key)
	for rid in tables.get("regions", {}):
		if not bgs.has(rid):
			errs.append("art.backgrounds: region '%s' has no background entry (add an alias)" % rid)
	if not bgs.has(str(art.get("bg_default", ""))):
		errs.append("art.bg_default must name a backgrounds entry")
	var fx: Dictionary = art.get("fx", {}) if art.get("fx") is Dictionary else {}
	for key in fx:
		if not (fx[key] is Dictionary) or str(fx[key].get("file", "")) == "":
			errs.append("art.fx.%s: needs 'file'" % key)
	for sec in ["map", "map_icons", "weapon_fx", "weapon_icons"]:
		errs.append_array(_art_check_file_section(art, sec))
	return errs

## 檔名區塊的期望檔名；不在清單內的鍵 → ""。
static func _art_expected_file(section: String, key: String) -> String:
	match section:
		"map":
			return "map_" + key if key in ART_MAP_KEYS else ""
		"map_icons":
			return "map_icon_" + key if key in ART_MAP_ICON_KEYS else ""
		"weapon_fx":
			if key in ART_WEAPON_FX_KEYS:
				return "fx_weapon_" + key
			return "fx_skill_" + key if key in ART_SKILL_FX_KEYS else ""
		"weapon_icons":
			return "icon_weapon_" + key if key in ART_WEAPON_ICON_KEYS else ""
	return ""

static func _art_check_file_section(art: Dictionary, section: String) -> PackedStringArray:
	var errs := PackedStringArray()
	if not art.has(section):
		return errs   # 缺整個區塊已由 ART_SECTIONS 報過
	if not (art[section] is Dictionary):
		errs.append("art.%s: must be an object" % section)
		return errs
	var sec: Dictionary = art[section]
	for key in sec:
		var e: Variant = sec[key]
		var want := _art_expected_file(section, str(key))
		if want == "":
			errs.append("art.%s.%s: unknown key" % [section, key])
			continue
		if not (e is Dictionary) or str(e.get("file", "")) == "":
			errs.append("art.%s.%s: needs 'file'" % [section, key])
			continue
		if str(e["file"]) != want:
			errs.append("art.%s.%s: file must be '%s' (got '%s')" % [section, key, want, str(e["file"])])
		if e.has("placeholder") and typeof(e["placeholder"]) != TYPE_BOOL:
			errs.append("art.%s.%s: placeholder must be true/false" % [section, key])
	return errs

static func _art_cycle(entries: Dictionary, start: String, field: String) -> bool:
	var seen := {}
	var key := start
	while key != "" and entries.has(key) and entries[key] is Dictionary:
		if seen.has(key):
			return true
		seen[key] = true
		key = str(entries[key].get(field, ""))
	return false
