class_name UiKeys
extends RefCounted
## UI 用到的 intent kind、事件 key、方向／服務／屬性等中文對照（M1_PLAN 2.3、3.6、3.8、3.12）。
## 值必須與 M1_PLAN 3.6／3.8 完全相同；UI 不引用 server/**、core/battle/**、core/character/**。

# ---------- intents（3.6） ----------
const I_PING := "ping"
const I_CHAT := "chat"
const I_CHAR_LIST := "char_list"
const I_CHAR_ROLL := "char_roll"
const I_CHAR_CREATE := "char_create"
const I_CHAR_SELECT := "char_select"
const I_CHAR_DELETE := "char_delete"
const I_LOOK := "look"
const I_MOVE := "move"
const I_TRAVEL := "travel"
const I_TALK := "talk"
const I_SHOP_LIST := "shop_list"
const I_BUY := "buy"
const I_SELL := "sell"
const I_LEARN_LIST := "learn_list"
const I_LEARN := "learn"
const I_SELF_STUDY := "self_study"
const I_JOIN_SECT := "join_sect"
const I_INN_REST := "inn_rest"
const I_SET_RESPAWN := "set_respawn"
const I_MEAL := "meal"
const I_FIGHT := "fight"
const I_USE_ITEM := "use_item"
const I_EQUIP := "equip"
const I_UNEQUIP := "unequip"
const I_DROP_ITEM := "drop_item"
const I_MEDITATE := "meditate"
const I_EXERT := "exert"
const I_WORK := "work"
const I_QUEST_ACCEPT := "quest_accept"
const I_QUEST_TURN_IN := "quest_turn_in"
const I_QUEST_ABANDON := "quest_abandon"
const I_LOOT_CORPSE := "loot_corpse"
const I_BATTLE_CMD := "battle_cmd"

const ALL_INTENTS := [
	I_PING, I_CHAT, I_CHAR_LIST, I_CHAR_ROLL, I_CHAR_CREATE, I_CHAR_SELECT, I_CHAR_DELETE,
	I_LOOK, I_MOVE, I_TRAVEL, I_TALK, I_SHOP_LIST, I_BUY, I_SELL, I_LEARN_LIST, I_LEARN,
	I_SELF_STUDY, I_JOIN_SECT, I_INN_REST, I_SET_RESPAWN, I_MEAL, I_FIGHT, I_USE_ITEM,
	I_EQUIP, I_UNEQUIP, I_DROP_ITEM, I_MEDITATE, I_EXERT, I_WORK, I_QUEST_ACCEPT,
	I_QUEST_TURN_IN, I_QUEST_ABANDON, I_LOOT_CORPSE, I_BATTLE_CMD,
]

# ---------- M2 intents（M2_PLAN 4.1；值與 Protocol 相同） ----------
const I_PARTY_INVITE := "party_invite"
const I_PARTY_REPLY := "party_reply"
const I_PARTY_LEAVE := "party_leave"
const I_PARTY_KICK := "party_kick"
const I_PARTY_LEAD := "party_lead"
const I_BATTLE_JOIN := "battle_join"
const I_CHALLENGE := "challenge"
const I_CHALLENGE_REPLY := "challenge_reply"
const I_FORCE_PK := "force_pk"
const I_SET_PREF := "set_pref"
const I_CORPSE_AUTHORIZE := "corpse_authorize"
const I_MAIL_SEND := "mail_send"
const I_MAIL_LIST := "mail_list"
const I_MAIL_READ := "mail_read"
const I_MAIL_DELETE := "mail_delete"
const I_SERVER_OPTS_GET := "server_opts_get"
const I_SERVER_OPTS_SET := "server_opts_set"
const I_ADMIN_KICK := "admin_kick"
const I_PASSPORT_REQUEST := "passport_request"
const I_PASSPORT_RESTORE := "passport_restore"
const I_PASSPORT_IMPORT := "passport_import"

# ---------- 查看偵察（docs/GDD.md §5.10【設計提案・非原作】；值與 Protocol 相同） ----------
const I_SCOUT_ACCEPT := "scout_accept"
const I_SCOUT_DECLINE := "scout_decline"
const SCOUT_INTENTS := [I_SCOUT_ACCEPT, I_SCOUT_DECLINE]
const E_SCOUT_OFFER := "scout_offer"       # ui
const E_SCOUT_CLOSED := "scout_closed"     # ui

# ---------- M3a intents（M3A_PLAN §6.12；值與 Protocol 相同） ----------
const I_SECT_BETRAY := "sect_betray"
const I_JAIL_RANSOM := "jail_ransom"
const I_SECT_TRIAL := "sect_trial"
const I_NPC_GUIDE := "npc_guide"
const M3A_INTENTS := [I_SECT_BETRAY, I_JAIL_RANSOM, I_SECT_TRIAL, I_NPC_GUIDE]
## 叛教第二段確認要輸入的兩個字（M3A_PLAN §7.6）
const BETRAY_WORD := "叛教"
## M3a 事件（§6.12；文字由模板處理，這裡只列 UI 需要辨識的）
const E_SECT_JOIN := "sect_join"
const E_SECT_BREACH := "sect_breach"
const E_SECT_EXPEL := "sect_expel"
const E_SECT_BETRAY := "sect_betray"
const E_JAIL_IN := "jail_in"
const E_JAIL_OUT := "jail_out"
const E_JAIL_RANSOM_PAID := "jail_ransom_paid"
const E_TRIAL_PASSED := "trial_passed"
## 角色表 sect_info.warnings 的屬性 key → 屬性窗欄位名（§7.9）
const SECT_WARN_LABELS := { "morality": "善惡", "pk": "PK值", "killing_intent": "殺氣" }
const SECT_WARN_TIP := "接近門規底線"
## 學藝被拒的原因碼（npc_menu.teach_blocked、sheet.sect_info.stop_teach）
const TEACH_BLOCK_TITLES := { "sect_stop_teach": "停止傳功", "sect_banned": "禁止學武", "jailed": "思過中", "sect_lockout": "犯戒" }

# ---------- 故事包（STORY_PLAN §4.14；值與 Protocol（VERSION 5）相同。UI 不直接引用 Protocol，舊主機時也能載入） ----------
const I_QUEST_TALK := "quest_talk"               # { npc, quest }
const I_DIALOGUE_CHOOSE := "dialogue_choose"     # { npc, quest, node, choice }
const I_DIALOGUE_CLOSE := "dialogue_close"       # {}
const I_STORY_ACT := "story_act"                 # { act }
const I_VILLAIN_REPLY := "villain_reply"         # { wid, choice: FIGHT／CALL }
const I_RUMOR_LIST := "rumor_list"               # {}
const STORY_INTENTS := [I_QUEST_TALK, I_DIALOGUE_CHOOSE, I_DIALOGUE_CLOSE, I_STORY_ACT, I_VILLAIN_REPLY, I_RUMOR_LIST]
const VILLAIN_FIGHT := "FIGHT"
const VILLAIN_CALL := "CALL"
const E_DIALOGUE := "dialogue"                   # ui
const E_DIALOGUE_CLOSE := "dialogue_close"       # ui
const E_QUEST_STAGE := "quest_stage"
const E_QUEST_FAIL := "quest_fail"
const E_QUEST_COMPLETE := "quest_complete"
const E_RUMOR := "jianghu_rumor"                 # 頻道 CH_JIANGHU
const E_RUMOR_LIST := "rumor_list"               # ui
const E_VILLAIN_PROMPT := "villain_prompt"       # ui
const E_VILLAIN_CLEAR := "villain_clear"         # ui
const STORY_UI_KEYS := [E_DIALOGUE, E_DIALOGUE_CLOSE, E_RUMOR_LIST, E_VILLAIN_PROMPT, E_VILLAIN_CLEAR]
## 原因碼（§4.14；文字在 text_templates 的 err_／fail_ 模板）
const STORY_REASONS := ["dialogue_none", "dialogue_stale", "choice_locked", "quest_cooldown", "quest_not_now",
	"act_unknown", "act_not_here", "villain_none", "npc_refuse", "escort_lost"]

# ---------- M3b intents（M3B_PLAN §6；值與 Protocol 相同，VERSION 維持 5。UI 不直接引用 Protocol） ----------
const I_BEG := "beg"                             # { npc }
const I_SEIZE_ENEMY := "seize_enemy"             # { name }
const I_BANK_OPEN := "bank_open"                 # { npc }
const I_BANK_PUT := "bank_put"                   # { npc, uid, n }
const I_BANK_TAKE := "bank_take"                 # { npc, uid, n }
const I_BANK_MONEY := "bank_money"               # { npc, amount }（>0 存、<0 領）
const I_CONSIGN_SEND := "consign_send"           # { npc, to, city, items: [{uid, n}], money }
const I_CONSIGN_LIST := "consign_list"           # { npc }
const I_CONSIGN_TAKE := "consign_take"           # { npc, id }
const I_ORG_FOUND := "org_found"                 # { npc, name }
const I_ORG_SIGN := "org_sign"                   # { npc, org }
const I_ORG_INVITE := "org_invite"               # { name }
const I_ORG_REPLY := "org_reply"                 # { org, accept }
const I_ORG_LEAVE := "org_leave"                 # {}
const I_ORG_KICK := "org_kick"                   # { name }
const I_ORG_SET_RANK := "org_set_rank"           # { name, rank }
const I_ORG_RANK_NAMES := "org_rank_names"       # { names }
const I_ORG_TITLE := "org_title"                 # { name, title }
const I_ORG_LEAD := "org_lead"                   # { name }
const I_ORG_DISBAND := "org_disband"             # { confirm }
const I_ORG_INFO := "org_info"                   # {}
const M3B_INTENTS := [I_BEG, I_SEIZE_ENEMY, I_BANK_OPEN, I_BANK_PUT, I_BANK_TAKE, I_BANK_MONEY,
	I_CONSIGN_SEND, I_CONSIGN_LIST, I_CONSIGN_TAKE, I_ORG_FOUND, I_ORG_SIGN, I_ORG_INVITE, I_ORG_REPLY,
	I_ORG_LEAVE, I_ORG_KICK, I_ORG_SET_RANK, I_ORG_RANK_NAMES, I_ORG_TITLE, I_ORG_LEAD, I_ORG_DISBAND, I_ORG_INFO]
# ---------- M3c intents（M3C_PLAN §8；值與 Protocol 相同，VERSION 維持 5） ----------
const I_SET_LOOK := "set_look"                   # { look }（WP-LOOKS）
const I_NPC_ATTACK := "npc_attack"               # { npc, mode? }（WP-NPCPK）
const I_MANUAL_READ := "manual_read"             # { item_uid, times? }（WP-LOOT）
const M3C_INTENTS := [I_SET_LOOK, I_NPC_ATTACK, I_MANUAL_READ]
const LOOK_MAX := 8
const NPC_ATTACK_MODES := ["ATTACK", "MIEPAI"]
const SLOTS := ["WEAPON", "ARMOR", "HEAD", "NECK", "WRIST", "CLOAK", "RING", "BOOTS"]
## 8 個裝備欄的中文（M3C_PLAN 缺漏：§8 沒寫標籤；SLOT_LABELS 維持舊的兩格，WP-LOOT 換用這個）
const SLOT_LABELS_ALL := { "WEAPON": "兵器", "ARMOR": "防具", "HEAD": "帽子", "NECK": "項鍊", "WRIST": "護腕",
	"CLOAK": "披風", "RING": "戒指", "BOOTS": "鞋子" }
## M3c 事件（look_changed 是 ui 事件，其他走模板）
const E_LOOK_CHANGED := "look_changed"
const E_NA_ATTACK_START := "na_attack_start"
const E_NA_NPC_KILLED := "na_npc_killed"
const E_NA_NPC_ROUTED := "na_npc_routed"
const E_NA_NPC_BACK := "na_npc_back"
const E_NA_GUARD_ALARM := "na_guard_alarm"
const E_NA_GUARD_SPARE := "na_guard_spare"
const E_NA_SECT_ENEMY := "na_sect_enemy"
const E_NA_MASTER_BETRAY := "na_master_betray"
const E_NA_MIEPAI := "na_miepai"
const E_LT_RARE_DROP := "lt_rare_drop"
const E_LT_DIVINE_TRANSFER := "lt_divine_transfer"
const E_LT_MANUAL_READ := "lt_manual_read"
const M3C_UI_KEYS := [E_LOOK_CHANGED]
## M3c 原因碼
const M3C_REASONS := ["bad_look", "npc_attack_off", "npc_not_attackable", "npc_safe_room", "npc_busy",
	"manuals_off", "not_manual", "manual_illiterate", "manual_cap", "divine_locked", "npc_routed"]
const R_NPC_NOT_ATTACKABLE := "npc_not_attackable"
const R_NPC_BUSY := "npc_busy"
# ---------- M3c2（M3C2_PLAN §7；值與 Protocol 相同，VERSION 維持 5） ----------
## char_select 多帶 identity（單機讀 Steam 身分的角色）；passport_import 多帶 new_name
const E_FOREIGN_IMPORTED := "foreign_imported"   # ui：{ name, replaced, dropped:[String] }
const E_CH_NO_LP := "ch_no_lp"
const E_CH_SPAR_CAPPED := "ch_spar_capped"
const M3C2_UI_KEYS := [E_FOREIGN_IMPORTED]
const R_FOREIGN_DISABLED := "foreign_disabled"
const R_FOREIGN_SAME_WORLD := "foreign_same_world"
const R_FOREIGN_NOT_NEWER := "foreign_not_newer"
const R_FOREIGN_OWNED := "foreign_owned"
const R_FOREIGN_BAD_DATA := "foreign_bad_data"
const R_FOREIGN_SUPERSEDED := "foreign_superseded"
const R_FOREIGN_CHAR_BLOCKED := "foreign_char_blocked"
const R_FOREIGN_QUOTA := "foreign_quota"
const R_ALT_IDENTITY_DENIED := "alt_identity_denied"
const R_PASSPORT_NAME_TAKEN := "passport_name_taken"
const R_CHORE_TIRED := "chore_tired"
const REJECT_WITH_BUILD := ["protocol_mismatch", "version_mismatch", "content_mismatch"]
## 匯入檔的大小上限（§5.1：> 256 KB 客戶端直接說「檔案無法讀取」）
const IMPORT_FILE_MAX_BYTES := 262144

## M3b 的 ui 事件（頂層 "ui": true）
const E_BANK_VIEW := "bank_view"
const E_CONSIGN_LIST := "consign_list"
const E_ORG_INFO := "org_info"
const E_ORG_INVITE := "org_invite"               # ui＋pending prompt
const M3B_UI_KEYS := [E_BANK_VIEW, E_CONSIGN_LIST, E_ORG_INFO, E_ORG_INVITE]
## M3b 一般事件中 UI 要辨識的（文字照模板）
const E_SECT_RANK_UP := "sect_rank_up"
const E_ORG_JOINED := "org_joined"
const E_ORG_LEFT := "org_left"
const E_ORG_KICKED := "org_kicked"
const E_ORG_DISBANDED := "org_disbanded"
const E_ORG_FOUNDED := "org_founded"
const E_CONSIGN_ARRIVED := "consign_arrived"
const E_SHOP_REFUSED := "shop_refused"
## 組織：位階 5 級（0 幫主…4 幫眾）、預設名稱、封號與位階名字數（M3B_PLAN §5.3）
const ORG_RANKS := 5
const ORG_DEFAULT_RANK_NAMES := ["幫主", "副幫主", "長老", "堂主", "幫眾"]
const ORG_NAME_MIN := 2
const ORG_NAME_MAX := 8
const ORG_RANK_NAME_MAX := 4
const ORG_TITLE_MAX := 6
## 錢莊（§4.11、§5.2.1）：主機沒在 bank_view 給時的預設
const BANK_CAPACITY_DEFAULT := 1000
const BANK_MONEY_CAP_DEFAULT := 6000000
const CARRY_PIECES_MAX := 300
const CARRY_MONEY_MAX := 6000000         # 身上銀兩上限（Character.add_money，600 萬）
## 托鏢運費（§4.11 預設；主機的 world_info／npc_menu 有給就用主機的）
const CONSIGN_FEE_BASE_DEFAULT := 20
const CONSIGN_FEE_PER_WEIGHT_DEFAULT := 2
const CONSIGN_ITEMS_MAX := 10
## 托鏢狀態文字
const CONSIGN_STATUS_LABELS := { "TRANSIT": "運送中", "READY": "已到站", "RETURNED": "已退回", "TAKEN": "已領取" }
## 監獄（§5.1.4）：sheet.jail.scope
const JAIL_SCOPE_CAPITAL := "CAPITAL"
const CAPITAL_JAIL_NAME := "京城監獄"
## 伺服器設定新列（§4.11、§7.9）
const OPT_ENABLE_1_0B := "enable_era_1_0b"
const ERA_1_0B := "1.0B"
const OPT_1_0B_OPENED := "已開放"
const OPT_NEXT_BOOT := "下次開服生效"

const M2_INTENTS := [
	I_PARTY_INVITE, I_PARTY_REPLY, I_PARTY_LEAVE, I_PARTY_KICK, I_PARTY_LEAD, I_BATTLE_JOIN,
	I_CHALLENGE, I_CHALLENGE_REPLY, I_FORCE_PK, I_SET_PREF, I_CORPSE_AUTHORIZE,
	I_MAIL_SEND, I_MAIL_LIST, I_MAIL_READ, I_MAIL_DELETE, I_SERVER_OPTS_GET, I_SERVER_OPTS_SET,
	I_ADMIN_KICK, I_PASSPORT_REQUEST, I_PASSPORT_RESTORE, I_PASSPORT_IMPORT,
]

## set_pref 的 key（M2_PLAN 4.1 PREF_KEYS）與系統窗「特殊開關」的文字
const PREF_ACCEPT_CHALLENGE := "accept_challenge"
const PREF_ACCEPT_PARTY := "accept_party"
const PREF_KEYS := [PREF_ACCEPT_CHALLENGE, PREF_ACCEPT_PARTY]
const PREF_LABELS := { PREF_ACCEPT_CHALLENGE: "接受叫戰", PREF_ACCEPT_PARTY: "接受組隊邀請" }
const PK_MODES := ["CLASSIC", "CHALLENGE_ONLY", "OFF"]
const MAIL_MAX_LEN := 200
const PARTY_MAX_DEFAULT := 5

# ---------- 頻道 ----------
const CH_SYSTEM := "SYSTEM"
const CH_SCENE := "SCENE"
const CH_BATTLE := "BATTLE"
const CH_CHAT_WORLD := "CHAT_WORLD"
# M2 頻道（M2_PLAN 4.1）
const CH_CHAT_WHISPER := "CHAT_WHISPER"
const CH_CHAT_SAY := "CHAT_SAY"
const CH_CHAT_SECT := "CHAT_SECT"
const CH_CHAT_GUILD := "CHAT_GUILD"
const CH_CHAT_PARTY := "CHAT_PARTY"
const CH_CHAT_RUMOR := "CHAT_RUMOR"
const CH_GM := "GM"
const CH_MAIL := "MAIL"
## 故事包：系統【江湖傳聞】（STORY_PLAN §4.14 CH_JIANGHU；【設計提案・非原作】）
const CH_JIANGHU := "JIANGHU"
const CHAT_CHANNELS := [CH_CHAT_WORLD, CH_CHAT_WHISPER, CH_CHAT_SAY, CH_CHAT_SECT, CH_CHAT_GUILD,
	CH_CHAT_PARTY, CH_CHAT_RUMOR, CH_GM]

# ---------- 事件 key（3.8，只列 UI 需要辨識的） ----------
const E_CHAR_ROLLED := "char_rolled"
const E_CHAR_CREATED := "char_created"
const E_CHAR_DELETED := "char_deleted"
const E_CHAR_ENTERED := "char_entered"
const E_NPC_MENU := "npc_menu"
const E_SHOP_LIST := "shop_list"
const E_TEACH_LIST := "teach_list"
const E_ENCOUNTER := "encounter"
const E_FIGHT_START := "fight_start"
const E_BATTLE_GAUGES := "battle_gauges"
const E_BATTLE_AWAIT := "battle_await"
const E_BATTLE_END := "battle_end"
const E_BATTLE_MOVE := "battle_move"
const E_BATTLE_MISS := "battle_miss"
const E_BATTLE_CRIT := "battle_crit"
const E_BATTLE_COUNTER := "battle_counter"
const E_BATTLE_DEFEND := "battle_defend"
const E_BATTLE_REST := "battle_rest"
const E_BATTLE_EQUIP := "battle_equip"
const E_BATTLE_FLEE := "battle_flee"
const E_BATTLE_TIMEOUT := "battle_timeout"
const E_BATTLE_PROC_DEFENSE := "battle_proc_DEFENSE"
const E_BATTLE_PROC_RECOVER := "battle_proc_RECOVER"
const E_BATTLE_STATUS_ON := "battle_status_on"
const E_BATTLE_STATUS_OFF := "battle_status_off"
const E_BATTLE_WOUND_TICK := "battle_wound_tick"
# M3a 戰鬥事件（M3A_PLAN §5.6、§5.10；UI 需要辨識的）
const E_BATTLE_POISON_OK := "battle_poison_ok"
const E_BATTLE_POISON_FAIL := "battle_poison_fail"
const E_BATTLE_POISON_TICK := "battle_poison_tick"
const E_BATTLE_MEDIC := "battle_medic"
const E_BATTLE_HIDDEN_HIT := "battle_hidden_hit"
const E_BATTLE_HIDDEN_MISS := "battle_hidden_miss"
const E_BATTLE_FORMATION_ON := "battle_formation_on"
const E_BATTLE_FORMATION_OFF := "battle_formation_off"
const E_BATTLE_INNER_HEAL := "battle_inner_heal"
const E_BATTLE_INNER_EXPEL := "battle_inner_expel"
const E_BATTLE_INNER_UNSEAL_OK := "battle_inner_unseal_ok"
const E_BATTLE_INNER_UNSEAL_FAIL := "battle_inner_unseal_fail"
const E_BATTLE_INNER_TRANSFER := "battle_inner_transfer"
const E_BATTLE_ACUPOINT_OK := "battle_acupoint_ok"
const E_BATTLE_ACUPOINT_FAIL := "battle_acupoint_fail"
const E_BATTLE_STATUS_SKIP := "battle_status_skip"
const E_BATTLE_CONFUSED := "battle_confused"
const E_BATTLE_ITEM_USE := "battle_item_use"
const E_BATTLE_WAVE := "battle_wave"
const E_BATTLE_AOE := "battle_aoe"            # ui：{ uid, name, peer, move, cells: [[x,y]…] }
const BATTLE_PROC_PREFIX := "battle_proc_"
const E_BATTLE_KILL := "battle_kill"
const E_BATTLE_DEATH := "battle_death"
const TALK_PREFIX := "talk_"
# M2 事件（M2_PLAN 4.4；只列 UI 需要辨識的）
const E_BATTLE_JOIN := "battle_join"
const E_BATTLE_UNIT_JOIN := "battle_unit_join"
const E_PARTY_INVITED := "party_invited"
const E_CHALLENGE_REQUEST := "challenge_request"
const E_MAIL_ARRIVED := "mail_arrived"
const E_MAIL_WAITING := "mail_waiting"
const E_MAIL_LIST := "mail_list"
const E_SERVER_OPTIONS := "server_options"
const E_WORLD_INFO_CHANGED := "world_info_changed"
const E_PASSPORT := "passport"
const E_PASSPORT_RESTORED := "passport_restored"
const E_HOST_CLOSING := "host_closing"
const E_PK_KILL := "pk_kill"
const E_CORPSE_PUBLIC := "corpse_public"

## UI-only 事件（3.8：頂層帶 "ui": true，沒有模板）
const UI_ONLY_KEYS := [E_NPC_MENU, E_SHOP_LIST, E_TEACH_LIST, E_BATTLE_GAUGES, E_BATTLE_AWAIT, E_BATTLE_END,
	E_BATTLE_UNIT_JOIN, E_MAIL_LIST, E_SERVER_OPTIONS, E_WORLD_INFO_CHANGED, E_PASSPORT, E_SCOUT_OFFER, E_SCOUT_CLOSED,
	E_BATTLE_AOE, E_BANK_VIEW, E_CONSIGN_LIST, E_ORG_INFO, E_ORG_INVITE,
	"bounty_board", "law_hunter_warn", "cb_bond_request", "cb_bond_changed", "tourney_state"]   # M3d（= M3D_UI_KEYS）

# ---------- 善惡與名字顏色（M2_PLAN 4.10、5.2：惡藍、中立黃、善白【已證實：顏色】） ----------
const ALIGN_GOOD := "GOOD"
const ALIGN_NEUTRAL := "NEUTRAL"
const ALIGN_EVIL := "EVIL"
const ALIGN_COLORS := { ALIGN_EVIL: Color("4060ff"), ALIGN_NEUTRAL: Color("f0d060"), ALIGN_GOOD: Color("ffffff") }
const ALIGN_LABELS := { ALIGN_EVIL: "惡", ALIGN_NEUTRAL: "中立", ALIGN_GOOD: "善" }

# ---------- 戰鬥種類（M2_PLAN 4.5.3） ----------
## FIGHT 是玩家找 NPC 開打（例：山賊頭目），不是玩家之間的「切磋」（那是後期的結構化 PvP，verified_research：post-launch）
const BATTLE_KIND_LABELS := {
	"ENCOUNTER": "遇敵", "FIGHT": "打鬥", "GUARD": "守城官兵", "CHALLENGE": "叫戰", "FORCED": "強制 PK",
	"ROB": "劫鏢", "DUEL": "比武",   # M3d（M3D_PLAN §5.2、§5.3）
}
const PVP_KINDS := ["CHALLENGE", "FORCED"]

# ---------- 戰鬥 ----------
const GRID_W := 12
const GRID_H := 8
const GAUGE_FULL := 100.0
const TICKS_PER_SEC := 10.0
const CMD_MOVE := "MOVE"
const CMD_ATTACK := "ATTACK"
const CMD_ART := "ART"
const CMD_DEFEND := "DEFEND"
const CMD_REST := "REST"
const CMD_EQUIP := "EQUIP"
const CMD_FLEE := "FLEE"
## 快捷鍵 1–7 的順序（M1；索引就是數字鍵）
const BATTLE_CMDS := [CMD_MOVE, CMD_ATTACK, CMD_ART, CMD_DEFEND, CMD_REST, CMD_EQUIP, CMD_FLEE]
# M3a 指令（M3A_PLAN §5.1；值與 Protocol.BATTLE_CMDS 相同）
const CMD_POISON := "POISON"
const CMD_MEDIC := "MEDIC"
const CMD_HIDDEN := "HIDDEN"
const CMD_FORMATION := "FORMATION"
const CMD_INNER := "INNER"
const CMD_ACUPOINT := "ACUPOINT"
const CMD_ITEM := "ITEM"
const M3A_CMDS := [CMD_POISON, CMD_MEDIC, CMD_HIDDEN, CMD_FORMATION, CMD_INNER, CMD_ACUPOINT, CMD_ITEM]
# M3d 指令（M3D_PLAN §3.1、§3.2；值與 Protocol.BATTLE_CMDS 相同）
const CMD_DODGE := "DODGE"
const CMD_QING := "QING"
const M3D_CMDS := [CMD_DODGE, CMD_QING]
const BATTLE_CMDS_ALL := [CMD_MOVE, CMD_ATTACK, CMD_ART, CMD_DEFEND, CMD_REST, CMD_EQUIP, CMD_FLEE,
	CMD_POISON, CMD_MEDIC, CMD_HIDDEN, CMD_FORMATION, CMD_INNER, CMD_ACUPOINT, CMD_ITEM, CMD_DODGE, CMD_QING]
## 「內」的四種運功（battle_cmd 的 mode）與選單文字
const INNER_MODES := ["HEAL", "EXPEL", "UNSEAL", "TRANSFER"]
const INNER_MODE_LABELS := { "HEAL": "運功療傷", "EXPEL": "逼毒", "UNSEAL": "衝穴", "TRANSFER": "傳力" }
## M3a 快捷鍵（§7.1）：8 毒、9 醫、0 暗；Shift+1 陣、Shift+2 內、Shift+3 穴
const M3A_HOTKEYS := { KEY_8: CMD_POISON, KEY_9: CMD_MEDIC, KEY_0: CMD_HIDDEN }
const M3A_SHIFT_HOTKEYS := { KEY_1: CMD_FORMATION, KEY_2: CMD_INNER, KEY_3: CMD_ACUPOINT }
## 「內」「穴」屬於 2002-01-25（決戰光明頂）；伺服器規則 later_battle_cmds 關掉時的提示（§7.1、D9）
const LATER_CMDS := [CMD_INNER, CMD_ACUPOINT, CMD_QING]
const LATER_CMDS_TIP := "原作 2002 年才有（伺服器規則關閉）"
## 範圍招式形狀（§5.3）
const AOE_SHAPES := ["SINGLE", "CROSS", "CROSS_L", "LINE", "FAN", "AROUND"]
const AOE_LABELS := { "SINGLE": "單體", "CROSS": "小十字", "CROSS_L": "大十字", "LINE": "直線", "FAN": "半米字", "AROUND": "周身" }
## 戰鬥指令圓盤（AUTHENTIC_UI_SPEC §12.2）：原作 19 字對照；前 7 個（移攻武防休裝逃）已實作，快捷鍵 1–7
const CMD_LABELS := {
	CMD_MOVE: "移", CMD_ATTACK: "攻", CMD_ART: "武", CMD_DEFEND: "防",
	CMD_REST: "休", CMD_EQUIP: "裝", CMD_FLEE: "逃",
	CMD_DODGE: "閃", CMD_QING: "輕",   # M3d
}
## 原作完整順序（說明用）：移 攻 武 特 防 休 裝 逃 系 毒 醫 暗 陣 屬 內 輕 穴 絕 馴
const CMD_ALL_GLYPHS := ["移", "攻", "武", "特", "防", "休", "裝", "逃", "系", "毒", "醫", "暗", "陣", "屬", "內", "輕", "穴", "絕", "馴"]
## 兩列蜂巢排列（第二列右移半顆）；「絕」「馴」本作不放
const CMD_DISC_ROWS := [
	["防", "閃", "內", "休", "逃", "輕", "裝", "武", "屬", "系"],   # M3d：「閃」在「防」後面（M3D_PLAN §3.1）
	["移", "攻", "特", "毒", "醫", "陣", "暗", "穴"],
]
## 圓盤字 → 指令（已實作）；「屬」「系」開視窗
const CMD_BY_GLYPH := {
	"移": CMD_MOVE, "攻": CMD_ATTACK, "武": CMD_ART, "防": CMD_DEFEND, "休": CMD_REST, "裝": CMD_EQUIP, "逃": CMD_FLEE,
	"毒": CMD_POISON, "醫": CMD_MEDIC, "暗": CMD_HIDDEN, "陣": CMD_FORMATION, "內": CMD_INNER, "穴": CMD_ACUPOINT,
	"閃": CMD_DODGE, "輕": CMD_QING,   # M3d
}
const CMD_PANEL_GLYPHS := { "屬": "attributes", "系": "system" }
## 尚未開放的指令（不能用樣式）：輕功「輕」、特攻「特」（M3a 仍鎖住；§1.2）
## M3d：「輕」開放（跟著 later_battle_cmds），只剩「特」鎖住
const CMD_LOCKED_LABELS := ["特"]
const CMD_LOCKED_TIP := "尚未開放"
const CMD_TOOLTIPS := {
	CMD_MOVE: "移動到綠色格（快捷鍵 1）", CMD_ATTACK: "普通攻擊：藍色是攻擊範圍、紅色是可打的敵人（快捷鍵 2）",
	CMD_ART: "施展武功（耗內力，快捷鍵 3）", CMD_DEFEND: "防守，減少受到的傷害（快捷鍵 4）",
	CMD_REST: "調息回氣（快捷鍵 5）", CMD_EQUIP: "換兵器（快捷鍵 6）",
	CMD_FLEE: "站上白框「逃」格才能逃（快捷鍵 7）",
	CMD_POISON: "施毒：用毒術對敵人下毒（快捷鍵 8）",
	CMD_MEDIC: "醫療：替自己或身旁隊友療傷（快捷鍵 9）",
	CMD_HIDDEN: "暗器：先選暗器，再選敵人（快捷鍵 0）",
	CMD_FORMATION: "結陣：隊友站上金框站位後施展陣法（快捷鍵 Shift+1）",
	CMD_INNER: "內功：運功療傷、逼毒、衝穴、傳力（快捷鍵 Shift+2）",
	CMD_ACUPOINT: "點穴：封住相鄰敵人的穴道（快捷鍵 Shift+3）",
	CMD_DODGE: "閃：到下次行動前比較不容易被打中，但不反擊（快捷鍵 Shift+4）",
	CMD_QING: "輕功：越過敵人跳得更遠，或原地施展輕功脫身（耗內力，快捷鍵 Shift+5）",
}
## 不能按時的說明（快照 cmd_avail 為 false 時附在提示後面）
const CMD_UNAVAIL_TIPS := {
	CMD_POISON: "還沒學會毒術", CMD_MEDIC: "還沒學會醫術", CMD_HIDDEN: "需要暗器功夫與身上的暗器",
	CMD_FORMATION: "還沒學會陣法", CMD_INNER: "還沒學會內功", CMD_ACUPOINT: "需要點穴武功或基本刺術 10 級",
	CMD_DODGE: "目前不能閃", CMD_QING: "內力不足，施展不了輕功",
}
const CMD_PANEL_TIPS := { "屬": "查看屬性（唯讀）", "系": "系統選單" }
const BATTLE_IDLE_HINT := "白框「逃」字格＝逃跑格；站上去後按「逃」即可脫離戰鬥。"
const ATTACK_KEYS := ["atk_fist", "atk_blade", "atk_sword", "atk_staff", "atk_whip", "atk_spear"]
const RESULT_LABELS := {
	"VICTORY": "勝利", "DEFEAT": "戰敗", "FLED": "脫離戰鬥", "ALL_FLED": "脫離戰鬥", "ABORTED": "戰鬥中止",
}
const UNIT_STATE_LABELS := {
	"CHARGING": "蓄勢", "READY": "待命", "ACTING": "出手", "DEAD": "倒地", "FLED": "已逃",
}

# ---------- 方向（3.1） ----------
const DIRS := ["N", "S", "E", "W", "NE", "NW", "SE", "SW", "U", "D", "IN", "OUT"]
const DIR_LABELS := {
	"N": "北", "S": "南", "E": "東", "W": "西", "NE": "東北", "NW": "西北",
	"SE": "東南", "SW": "西南", "U": "上", "D": "下", "IN": "進", "OUT": "出",
}

# ---------- NPC 服務（3.12） ----------
const SERVICES := ["SHOP", "TEACH", "INN", "RESPAWN", "TRAVEL", "JOIN", "QUEST", "MEAL", "FIGHT",
	"BETRAY", "JAIL", "TRIAL", "GUIDE", "BANK", "ESCORT", "ORG", "RANK",
	"BOARD", "LICENSE", "CLEANSE", "TOURNEY"]   # M3d（M3D_PLAN §7）
const SERVICE_LABELS := {
	"SHOP": "交易", "TEACH": "請教", "INN": "住宿", "RESPAWN": "記錄", "TRAVEL": "驛站",
	"JOIN": "拜師", "QUEST": "任務", "MEAL": "用齋", "FIGHT": "切磋",
	# M3a（§6.12）
	"BETRAY": "叛教", "JAIL": "思過處", "TRIAL": "試煉", "GUIDE": "引路",
	# M3b（§4.8、§6）
	"BANK": "錢莊", "ESCORT": "鏢局", "ORG": "組織", "RANK": "袋位",
	# M3d（M3D_PLAN §7；與 Protocol.M3D_SERVICE_LABELS 相同）
	"BOARD": "佈告欄", "LICENSE": "執照", "CLEANSE": "消災", "TOURNEY": "比武報名",
}
## npc_menu.beg（M3b §5.1.2）：選單裡的「乞討」選項（不是服務；只有本派有 practice 的人看得到）
const BEG_CHOICE := "BEG"
const BEG_LABEL := "乞討"
const QUEST_STATE_LABELS := {
	"AVAILABLE": "可接", "ACTIVE": "進行中", "READY": "可交付", "DONE": "已完成",
	"COOLDOWN": "冷卻中",   # 故事包 §4.10
	"LOCKED": "條件未到",
}

# ---------- 屬性與數值（3.1） ----------
const ATTR_IDS := ["str", "guts", "wit", "luck", "cal", "agi", "con"]
const ATTR_NAMES := {
	"str": "臂力", "guts": "膽識", "wit": "悟性", "luck": "福緣", "cal": "定力", "agi": "機敏", "con": "根骨",
}
const ATTR_SHORT := {
	"str": "臂", "guts": "膽", "wit": "悟", "luck": "福", "cal": "定", "agi": "機", "con": "根",
}
const VITAL_NAMES := {
	"jing": "精", "qi": "氣", "shen": "神", "neili": "內力", "food": "飽食", "water": "飲水",
}
const EXERT_STATS := ["jing", "qi", "shen"]
const GENDER_LABELS := { "M": "男", "F": "女" }
const FREE_POINTS := 5
const MAX_CHARS := 3
const NAME_MAX_LEN := 8

# ---------- 技能與物品 ----------
const SKILL_KINDS := ["BASIC", "ART", "SECT", "LIFE"]
const SKILL_KIND_LABELS := { "BASIC": "基本武學", "ART": "特殊武功", "SECT": "門派技能", "LIFE": "生活技能" }
const SPECIAL_ARTS_MAX := 16
const INV_TABS := ["WEAPON", "ARMOR", "OTHER", "MATERIAL"]
const INV_TAB_LABELS := { "WEAPON": "武器", "ARMOR": "防具", "OTHER": "其他", "MATERIAL": "原料" }
const SLOT_LABELS := { "WEAPON": "兵器", "ARMOR": "防具" }

# ---------- 生活技能（5.6） ----------
const LIFE_COOKING := "life_cooking"
## 房間 feature → 生活技能 id 與動作按鈕（3.12 scene_panel）
const FEATURE_LIFE := {
	"FIELD": "life_farming", "WOOD": "life_woodcut", "WATER": "life_fishing", "STOVE": "life_cooking",
	# M3b（§4.4、§4.5）：採集型的新設施（礦場挖礦、打獵專區打獵）直接一顆按鈕
	"MINE": "life_mining", "HUNT": "life_hunting",
}
const LIFE_VERBS := {
	"life_farming": "耕作", "life_woodcut": "砍柴", "life_fishing": "垂釣", "life_cooking": "烹煮",
	"life_mining": "挖礦", "life_hunting": "打獵",
}
## M3b 製作型設施（§4.4）：場景卷軸「動作」列出現「製作」鈕 → 製作窗（依設施列出配方）
const CRAFT_FEATURES := ["FORGE", "CAST", "LOOM", "TANNERY", "KILN"]
const FEATURE_LABELS := {
	"FIELD": "田地", "WOOD": "樹林", "WATER": "水邊", "STOVE": "爐灶", "MINE": "礦場", "FORGE": "打鐵爐",
	"CAST": "鑄劍爐", "LOOM": "紡紗機與織布機", "TANNERY": "烘皮爐", "KILN": "燒炭爐", "HUNT": "打獵專區",
}
const CRAFT_LABEL := "製作"
const CRAFT_TIP := "打開製作窗：依這裡的設施列出能做的生活技能與配方"

# ---------- 燈籠（AUTHENTIC_UI_SPEC §8.1：原作順序 武功 Ctrl+1、屬性 Ctrl+2、裝備 Ctrl+3、指令 Ctrl+4、系統 Ctrl+5） ----------
const PANELS := ["skills", "attributes", "inventory", "commands", "system"]
const PANEL_LABELS := {
	"skills": "武功", "attributes": "屬性", "inventory": "裝備", "commands": "指令", "system": "系統",
	"quests": "任務", "map": "地圖",
}
## 原作沒有燈籠的視窗：任務（指令窗「雜項」，Ctrl+6）、地圖（Ctrl+M，另保留 M）
const EXTRA_PANELS := ["quests"]
const QUESTS_HOTKEY := KEY_6
## 視窗外框（UiFrame.Kind 名稱）：屬性是琥珀框、地圖是捲軸，其他玉石框
const PANEL_FRAMES := { "attributes": "AMBER", "map": "SCROLL" }
const PANEL_SIZES := {
	"skills": Vector2(760, 470), "attributes": Vector2(560, 450), "inventory": Vector2(760, 470),
	"commands": Vector2(560, 330), "system": Vector2(700, 470), "quests": Vector2(680, 460), "map": Vector2(1240, 540),
}

const INTENT_TIMEOUT_S := 5.0
const LOG_MAX_LINES := 500

static func dir_label(dir: String) -> String:
	return DIR_LABELS.get(dir, dir)

static func service_label(svc: String) -> String:
	return SERVICE_LABELS.get(svc, svc)

static func attr_name(id: String) -> String:
	return ATTR_NAMES.get(id, id)

static func is_ui_only(e: Dictionary) -> bool:
	return bool(e.get("ui", false))

## 招式 flavor 與 atk_* 都帶 def_uid + def_qi（3.8.4）
static func is_hit_event(e: Dictionary) -> bool:
	var p: Dictionary = e.get("p", {})
	return p.has("def_uid") and p.has("def_qi")

## 內力消耗 = ceil(招式內力 × 成數 / 5)（4.7、3.12 art_picker）
static func inner_cost(cost_inner: int, tenths: int) -> int:
	return int(ceil(float(cost_inner) * float(tenths) / 5.0))

# ==== M3d（M3D_PLAN §7；WP-COMBAT Day-0 一次寫好所有 WP 的介面常數；值與 Protocol 相同，VERSION 維持 5） ====
# ---- intents ----
const I_BOUNTY_BOARD := "bounty_board"           # { npc }（WP-LAW）
const I_BOUNTY_LICENSE := "bounty_license"       # { npc }
const I_BOUNTY_ADD := "bounty_add"               # { npc, target_name, money }
const I_BOUNTY_CLAIM := "bounty_claim"           # { npc }
const I_CLEANSE := "cleanse"                     # { npc, what: KILLING|PK, times? }
const CLEANSE_WHATS := ["KILLING", "PK"]
const I_COMBO_BOND := "combo_bond"               # { target_char }（WP-COMBAT）
const I_COMBO_REPLY := "combo_reply"             # { from_char, accept }
const I_COMBO_CANCEL := "combo_cancel"           # {}
const I_COMBO_NURTURE := "combo_nurture"         # {}
const I_INTIMIDATE := "intimidate"               # { npc }（WP-ARTS）
const I_LIANDU := "liandu"                       # {}
const I_ROB_ESCORT := "rob_escort"               # { target_char }（WP-EVENTS）
const I_TOURNEY_INFO := "tourney_info"           # {}
const I_TOURNEY_SIGNUP := "tourney_signup"       # { npc, kind }
const I_TOURNEY_WITHDRAW := "tourney_withdraw"   # {}
const I_TOURNEY_HOST := "tourney_host"           # { kind, signup_s? }
const M3D_INTENTS := [I_BOUNTY_BOARD, I_BOUNTY_LICENSE, I_BOUNTY_ADD, I_BOUNTY_CLAIM, I_CLEANSE,
	I_COMBO_BOND, I_COMBO_REPLY, I_COMBO_CANCEL, I_COMBO_NURTURE, I_INTIMIDATE, I_LIANDU,
	I_ROB_ESCORT, I_TOURNEY_INFO, I_TOURNEY_SIGNUP, I_TOURNEY_WITHDRAW, I_TOURNEY_HOST]
# ---- 事件 ----
const E_BOUNTY_BOARD := "bounty_board"           # ui
const E_LAW_LICENSE_OK := "law_license_ok"
const E_LAW_LICENSE_VOID := "law_license_void"
const E_LAW_BOUNTY_EARNED := "law_bounty_earned"
const E_LAW_BOUNTY_PAID := "law_bounty_paid"
const E_LAW_HUNTER_WARN := "law_hunter_warn"     # ui（同 villain_warn 格式）
const E_LAW_HUNTER_ESCAPED := "law_hunter_escaped"   # 文字；M3d 審查：收起警告橫幅
const E_LAW_HUNTER_ATTACK := "law_hunter_attack"     # 文字；M3d 審查：收起警告橫幅
const E_LAW_CLEANSED := "law_cleansed"
const E_CB_BOND_REQUEST := "cb_bond_request"     # ui：{ from_char, from_name }
const E_CB_BOND_CHANGED := "cb_bond_changed"     # ui：{ partner_name, moqi, peihe, drain_day }
const E_BATTLE_DODGE := "battle_dodge"
const E_BATTLE_QING_JUMP := "battle_qing_jump"
const E_BATTLE_QING_ESCAPE := "battle_qing_escape"
const E_BATTLE_QING_FAIL := "battle_qing_fail"
const E_BATTLE_COMBO := "battle_combo"
const E_AR_INTIMIDATED := "ar_intimidated"
const E_AR_LIANDU := "ar_liandu"
const E_AR_XUEMO_ENLIGHTENED := "ar_xuemo_enlightened"
const E_EV_JB_STARTED := "ev_jb_started"
const E_EV_JB_DONE := "ev_jb_done"
const E_EV_JB_FAILED := "ev_jb_failed"
const E_EV_JB_ROBBED := "ev_jb_robbed"
const E_TOURNEY_STATE := "tourney_state"         # ui
const E_EV_TOURNEY_CALL := "ev_tourney_call"
const E_EV_DUEL_RESULT := "ev_duel_result"
const E_ER_SPAR_NOT_DISCIPLE := "er_spar_not_disciple"
const M3D_UI_KEYS := [E_BOUNTY_BOARD, E_LAW_HUNTER_WARN, E_CB_BOND_REQUEST, E_CB_BOND_CHANGED, E_TOURNEY_STATE]
## main_screen 依事件 key 分派給各 WP 的處理函式（M3D_PLAN §9.2）
const M3D_LAW_EVENTS := [E_BOUNTY_BOARD, E_LAW_LICENSE_OK, E_LAW_LICENSE_VOID, E_LAW_BOUNTY_EARNED, E_LAW_BOUNTY_PAID,
	E_LAW_HUNTER_WARN, E_LAW_CLEANSED, E_LAW_HUNTER_ESCAPED, E_LAW_HUNTER_ATTACK]
const M3D_COMBAT_EVENTS := [E_CB_BOND_REQUEST, E_CB_BOND_CHANGED]
const M3D_ARTS_EVENTS := [E_AR_INTIMIDATED, E_AR_LIANDU, E_AR_XUEMO_ENLIGHTENED]
const M3D_EVENTS_EVENTS := [E_EV_JB_STARTED, E_EV_JB_DONE, E_EV_JB_FAILED, E_EV_JB_ROBBED, E_TOURNEY_STATE,
	E_EV_TOURNEY_CALL, E_EV_DUEL_RESULT]
const M3D_ERRANDS_EVENTS := [E_ER_SPAR_NOT_DISCIPLE]
# ---- 原因碼 ----
const M3D_REASONS_COMBAT := ["dodge_off", "qing_off", "equip_cooldown", "combo_need_partner", "combo_need_party",
	"combo_pair_mismatch", "combo_moqi_low", "combo_has_partner", "combo_peihe_low", "combo_no_request", "combo_partner_absent",
	"combo_request_pending"]
const R_EQUIP_COOLDOWN := "equip_cooldown"
# ---- 戰鬥：閃、輕（WP-COMBAT） ----
## 閃 Shift+4、輕 Shift+5（M3a 的 Shift+1–3 之後）
const M3D_SHIFT_HOTKEYS := { KEY_4: CMD_DODGE, KEY_5: CMD_QING }
## 規則 dodge_cmd 關（later_official：2002-01-25 拿掉「閃」）時的提示
const DODGE_OFF_TIP := "原作 2002 年拿掉了（伺服器規則關閉）"
const QING_MODES := ["JUMP", "ESCAPE"]
const QING_MODE_LABELS := { "JUMP": "飛身越敵", "ESCAPE": "輕功脫身" }
const QING_MODE_TIPS := { "JUMP": "跳到移動範圍再多一格的空格，可以越過敵人（耗內力）",
	"ESCAPE": "原地施展輕功逃離戰鬥，不必站上逃跑格；有機率失敗（耗內力 30）" }
const QING_ESCAPE_COST := 30
## 這些戰鬥不能用輕功脫身（任務戰、試煉；追擊戰可以）
const QING_NO_ESCAPE_TIP := "這場戰鬥不能脫身"
## 合體技（battle_combo）的金色大字
const COMBO_BANNER_FMT := "合體技・%s！"
const COMBO_GOLD := Color("ffd860")
# ---- 合體默契（燈籠「武功」分頁；1.0B） ----
const COMBO_BTN_BOND := "建立默契"
const COMBO_BTN_CANCEL := "取消默契"
const COMBO_BTN_NURTURE := "培養感情"
const COMBO_TITLE := "合體默契"
const COMBO_ERA := "1.0B"
# ---- 換裝兩秒（M3D_PLAN §3.6） ----
const EQUIP_COOLDOWN_S := 2.0
const EQUIP_COOLDOWN_TEXT := "換裝要間隔兩秒"
# ---- 夜晚變暗與夜明珠（M3D_PLAN §3.5；設定 ui.night_dim 純客戶端） ----
const SETTING_NIGHT_DIM := "ui.night_dim"
const NIGHT_DIM_COLOR := Color(0.03, 0.05, 0.20, 0.35)
const NIGHT_DIM_LABEL := "夜晚畫面變暗"
const ITEM_EFFECT_LIGHT := "LIGHT"
const ITEM_EFFECT_FLEE_ANYWHERE := "FLEE_ANYWHERE"
# ---- 佈告欄與比武（WP-LAW、WP-EVENTS 用；文字由各 WP 的對話框決定） ----
const BOARD_MENU_BOUNTY := "觀看懸賞名單"
const BOARD_RANKS_LOCKED := "尚未開放"
const PLAYER_TAGS_M3D := ["押鏢", "劫鏢", "懸賞", "盟主"]
