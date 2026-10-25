class_name Protocol
extends RefCounted
## 協定版本、intent／事件名稱與參數驗證（TECH_ARCH 6.3、M1_PLAN 3.5.5、3.6）。純邏輯，不碰 Autoload。

## 2（2026-10）：s2c_intent_result 多了第 4 個參數 extra（busy 的剩餘秒數）。Godot RPC 參數數目要一致，
## 舊版客戶端收不到 4 個參數的結果，所以升版，握手（c2s_hello）時就把新舊版互相擋掉（M1_PLAN 3.5.3）。
## 3（2026-10，M2_PLAN H2）：intent 集合與 chat 語意改變（7 個發話頻道、密語 to、組隊／PK／飛鴿／管理員／護照）。
## 4（2026-10，M3A_PLAN K1）：戰鬥指令集合（毒醫暗陣內穴＋用藥）、battle_cmd 的 mode、門派 intent、快照與角色表欄位改變。
## 5（2026-10，STORY_PLAN S1）：角色表 quests 列形狀、view 欄位（story_actions、escort、wanderers）、對話樹與故事 intent。
const VERSION := 5
## 握手相容字串（M3C2 R14；M3c2 第二輪審查補註）：**不是**標題顯示的遊戲版本（那是 BuildInfo.version()，
## 只是資訊）。它從 0.1.0 起沒變過，validate_hello 的 version_mismatch 是保留給「存檔／握手格式不相容的大改版」用的；
## 平常能不能連線看協定 VERSION 與資料指紋（content_hash）。改它等於讓所有舊版客戶端連不上。
const GAME_VERSION := "0.1.0"

# ---- intents (c2s)，M1_PLAN 3.6 ----
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

# ---- M2 intents（M2_PLAN 4.1、4.2） ----
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
const I_PASSPORT_IMPORT := "passport_import"      # M3c2 §5.6：實作（外來角色匯入）

# ---- 查看偵察（M3 小範圍【設計提案・非原作】；docs/GDD.md §5.10）：純新增，RPC 簽名不變 → 不升 VERSION ----
## look 多一個可選參數 scout（bool）：true 且在有遇敵表的房間 → 主機擲遇敵表、送 scout_offer（ui）。
## 舊主機不認得 scout 參數（unexpected_arg），所以客戶端只在 world_info.scout_enabled == true 時才帶。
const I_SCOUT_ACCEPT := "scout_accept"
const I_SCOUT_DECLINE := "scout_decline"

# ---- M3a intents（M3A_PLAN §6.12） ----
const I_SECT_BETRAY := "sect_betray"
const I_JAIL_RANSOM := "jail_ransom"
const I_SECT_TRIAL := "sect_trial"
const I_NPC_GUIDE := "npc_guide"
const I_DEBUG_SET := "debug_set"          # 只在主機以 --debug-intents 啟動時註冊（§6.11）

# ---- 故事包 intents（STORY_PLAN §4.14） ----
const I_QUEST_TALK := "quest_talk"
const I_DIALOGUE_CHOOSE := "dialogue_choose"
const I_DIALOGUE_CLOSE := "dialogue_close"
const I_STORY_ACT := "story_act"
const I_VILLAIN_REPLY := "villain_reply"
const I_RUMOR_LIST := "rumor_list"
const VILLAIN_CHOICES := ["FIGHT", "CALL"]

# ---- M3b intents（M3B_PLAN §6；L1：純新增，RPC 簽名不變 → VERSION 維持 5） ----
const I_BEG := "beg"                        # intents_sect.gd（WP-SECT）
const I_SEIZE_ENEMY := "seize_enemy"        # intents_pk.gd（WP-SECT）
const I_BANK_OPEN := "bank_open"            # intents_econ.gd（WP-ECON）
const I_BANK_PUT := "bank_put"
const I_BANK_TAKE := "bank_take"
const I_BANK_MONEY := "bank_money"
const I_CONSIGN_SEND := "consign_send"
const I_CONSIGN_LIST := "consign_list"
const I_CONSIGN_TAKE := "consign_take"
const I_ORG_FOUND := "org_found"            # intents_org.gd（WP-ORG）
const I_ORG_SIGN := "org_sign"
const I_ORG_INVITE := "org_invite"
const I_ORG_REPLY := "org_reply"
const I_ORG_LEAVE := "org_leave"
const I_ORG_KICK := "org_kick"
const I_ORG_SET_RANK := "org_set_rank"
const I_ORG_RANK_NAMES := "org_rank_names"
const I_ORG_TITLE := "org_title"
const I_ORG_LEAD := "org_lead"
const I_ORG_DISBAND := "org_disband"
const I_ORG_INFO := "org_info"

# ---- M3c intents（M3C_PLAN §8；N1：純新增，RPC 簽名不變 → VERSION 維持 5） ----
const I_SET_LOOK := "set_look"           # intents_char.gd（WP-LOOKS）
const I_NPC_ATTACK := "npc_attack"       # intents_npcpk.gd（WP-NPCPK）
const I_MANUAL_READ := "manual_read"     # intents_loot.gd（WP-LOOT）
const LOOK_MAX := 8
const NPC_ATTACK_MODES := ["ATTACK", "MIEPAI"]

# ---- channels (11.1) ----
const CH_SYSTEM := "SYSTEM"
const CH_SCENE := "SCENE"
const CH_BATTLE := "BATTLE"
const CH_CHAT_WORLD := "CHAT_WORLD"
# M2（4.1）
const CH_CHAT_WHISPER := "CHAT_WHISPER"
const CH_CHAT_SAY := "CHAT_SAY"
const CH_CHAT_SECT := "CHAT_SECT"
const CH_CHAT_GUILD := "CHAT_GUILD"
const CH_CHAT_PARTY := "CHAT_PARTY"
const CH_CHAT_RUMOR := "CHAT_RUMOR"
const CH_GM := "GM"
const CH_MAIL := "MAIL"
# 故事包（STORY_PLAN §4.14）：系統【江湖傳聞】
const CH_JIANGHU := "JIANGHU"

# ---- event keys（M0） ----
const E_CHAT := "chat"
const E_PONG := "pong"
const E_JOIN := "player_join"
const E_LEAVE := "player_leave"

# ---- event keys（M1_PLAN 3.8，只列固定 key） ----
# 3.8.1
const E_CHAR_ROLLED := "char_rolled"
const E_CHAR_CREATED := "char_created"
const E_CHAR_DELETED := "char_deleted"
const E_CHAR_ENTERED := "char_entered"
const E_LOOK := "look_room"
const E_CHAR_LEFT := "char_left"
const E_ROOM_ENTER := "room_enter"
const E_ROOM_LEAVE := "room_leave"
const E_TRAVEL := "travel"
const E_NIGHT_FALLS := "night_falls"
const E_DAY_BREAKS := "day_breaks"
const E_HUNGRY := "hungry"
const E_THIRSTY := "thirsty"
const E_STARVING := "starving"
const E_PARCHED := "parched"
const E_BIRTHDAY := "birthday"
# 3.8.2
const E_NPC_MENU := "npc_menu"
const E_SHOP_LIST := "shop_list"
const E_TEACH_LIST := "teach_list"
const E_BUY := "buy"
const E_SELL := "sell"
const E_LEARN := "learn"
const E_SKILL_UP := "skill_up"
const E_SELF_STUDY := "self_study"
const E_LIFE_LEARN := "life_learn"
const E_SECT_JOIN := "sect_join"
const E_INN_REST := "inn_rest"
const E_RESPAWN_SET := "respawn_set"
const E_MEAL := "meal"
# 3.8.3
const E_ITEM_USE := "item_use"
const E_ITEM_GAIN := "item_gain"
const E_ITEM_LOST := "item_lost"
const E_ITEM_DROP := "item_drop"
const E_ITEM_SPOILED := "item_spoiled"
const E_MONEY_GAIN := "money_gain"
const E_EQUIP := "equip"
const E_UNEQUIP := "unequip"
const E_OVERDOSE := "overdose"
const E_MEAT_VOW := "meat_vow_broken"
const E_WINE_VOW := "wine_vow_broken"      # M3a 審查 A4：全真弟子飲酒，養生降級
const E_MEDITATE := "meditate"
const E_CULTIVATE := "cultivate"
const E_EXERT := "exert"
const E_WORK_OK_PREFIX := "work_ok_"
const E_WORK_FAIL_PREFIX := "work_fail_"
const E_QUEST_ACCEPT := "quest_accept"
const E_QUEST_PROGRESS := "quest_progress"
const E_QUEST_COMPLETE := "quest_complete"
const E_QUEST_ABANDON := "quest_abandon"
const E_REWARD := "reward"
# 3.8.4（由 Battle 產生）
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
const E_BATTLE_KILL := "battle_kill"
const E_BATTLE_DEATH := "battle_death"
# 3.8.5（由 WORLD 產生）
const E_ENCOUNTER := "encounter"
const E_FIGHT_START := "fight_start"
const E_BATTLE_VICTORY := "battle_victory"
const E_BATTLE_VICTORY_FLED := "battle_victory_fled"
const E_BATTLE_DEFEAT := "battle_defeat"
const E_BATTLE_FLED := "battle_fled"
const E_BATTLE_REWARD := "battle_reward"
const E_DEATH_STRICT := "death_strict"
const E_DEATH_STANDARD := "death_standard"
const E_DEATH_STANDARD_SAFE := "death_standard_safe"
const E_DEATH_CASUAL := "death_casual"
const E_RESPAWN := "respawn"
const E_CORPSE_LOOTED := "corpse_looted"
const E_CORPSE_EXPIRED := "corpse_expired"
# WORLD_2001 §8、§10（純新增）：舊存檔的位置／記錄點已不在生效的房間裡
const E_RELOCATED := "relocated"
const E_RESPAWN_RESET := "respawn_reset"

# ---- event keys（M2_PLAN 4.4） ----
# 4.4.1 組隊與中途加入（WP-PARTY）
const E_PARTY_INVITE_SENT := "party_invite_sent"
const E_PARTY_INVITED := "party_invited"
const E_PARTY_DECLINED := "party_declined"
const E_PARTY_INVITE_EXPIRED := "party_invite_expired"
const E_PARTY_JOINED := "party_joined"
const E_PARTY_LEFT := "party_left"
const E_PARTY_KICKED := "party_kicked"
const E_PARTY_LEADER := "party_leader"
const E_PARTY_DISBANDED := "party_disbanded"
const E_BATTLE_JOIN := "battle_join"
const E_BATTLE_UNIT_JOIN := "battle_unit_join"            # ui
# 4.4.2 PK、守衛、屍體（WP-PK）
const E_CHALLENGE_SENT := "challenge_sent"
const E_CHALLENGE_REQUEST := "challenge_request"
const E_CHALLENGE_DECLINED := "challenge_declined"
const E_CHALLENGE_EXPIRED := "challenge_expired"
const E_CHALLENGE_START := "challenge_start"
const E_FORCE_PK_START := "force_pk_start"
const E_PK_KILL := "pk_kill"
const E_PK_VALUE_UP := "pk_value_up"
const E_PK_WANTED := "pk_wanted"
const E_MORALITY_CHANGE := "morality_change"
const E_KILLING_INTENT_CHANGE := "killing_intent_change"
const E_GUARD_ATTACK := "guard_attack"
const E_PREF_CHANGED := "pref_changed"
const E_CORPSE_AUTHORIZED := "corpse_authorized"
const E_CORPSE_AUTH_GRANTED := "corpse_auth_granted"
const E_CORPSE_LOOTED_OTHER := "corpse_looted_other"
const E_CORPSE_LOOTED_BY := "corpse_looted_by"
const E_CORPSE_PUBLIC := "corpse_public"
# 4.4.3 聊天與飛鴿（WP-SOCIAL）；千里傳音沿用 E_CHAT
const E_CHAT_SAY := "chat_say"
const E_CHAT_SECT := "chat_sect"
const E_CHAT_PARTY := "chat_party"
const E_CHAT_WHISPER := "chat_whisper"
const E_CHAT_RUMOR := "chat_rumor"
const E_CHAT_GM := "chat_gm"
const E_MAIL_SENT := "mail_sent"
const E_MAIL_ARRIVED := "mail_arrived"
const E_MAIL_WAITING := "mail_waiting"
const E_MAIL_LIST := "mail_list"                          # ui
# 4.4.4 主機（WP-HOST）
const E_SERVER_OPTIONS := "server_options"                # ui
const E_WORLD_INFO_CHANGED := "world_info_changed"        # ui
const E_SERVER_OPTION_CHANGED := "server_option_changed"
const E_PLAYER_KICKED := "player_kicked"
const E_HOST_CLOSING := "host_closing"
const E_PASSPORT := "passport"                            # ui
const E_PASSPORT_RESTORED := "passport_restored"
# 查看偵察（純新增）
const E_SCOUT_OFFER := "scout_offer"                      # ui：{ offer_id, room, room_name, monsters: [ { id, name, n } ], text, ttl_s }
const E_SCOUT_CLOSED := "scout_closed"                    # ui：{ offer_id, why }（moved／battle／expired／declined／replaced／logout／disabled）
const E_SCOUT_FOUND := "scout_found"
const E_SCOUT_NONE := "scout_none"
const E_SCOUT_BUSY := "scout_busy"
const E_SCOUT_EXPIRED := "scout_expired"
const E_SCOUT_DECLINED := "scout_declined"
const E_SCOUT_ENGAGE := "scout_engage"
# M3a 門派系統（M3A_PLAN §6.12；模板由 docs/m3a_staging/_rules.json 提供）
const E_SECT_BREACH := "sect_breach"
const E_SECT_EXPEL := "sect_expel"
const E_SECT_BETRAY := "sect_betray"
const E_SECT_STOP_TEACH := "sect_stop_teach"
const E_SECT_SKILL_DECAY := "sect_skill_decay"
const E_SECT_HOSTILE := "sect_hostile"
const E_SECT_REPENT := "sect_repent"                      # 恆山犯戒悔過成功：{ npc_name, sect_name }
const E_SECT_REPENT_REFUSED := "sect_repent_refused"      # 悔過不成：{ npc_name, sect_name, rule_text }
const E_JAIL_IN := "jail_in"
const E_JAIL_OUT := "jail_out"
const E_JAIL_RANSOM_PAID := "jail_ransom_paid"
const E_POISON_FLARE := "poison_flare"
const E_CONDITION_OFF := "condition_off"
const E_NPC_GUIDE := "npc_guide"
const E_TRIAL_PASSED := "trial_passed"
const E_DEBUG_SET := "debug_set"
# 故事包（STORY_PLAN §4.14）
const E_DIALOGUE := "dialogue"                            # ui
const E_DIALOGUE_CLOSE := "dialogue_close"                # ui
const E_QUEST_STAGE := "quest_stage"
const E_QUEST_FAIL := "quest_fail"
const E_RUMOR := "jianghu_rumor"                          # 頻道 CH_JIANGHU
const E_RUMOR_LIST := "rumor_list"                        # ui
const E_VILLAIN_PROMPT := "villain_prompt"                # ui
const E_VILLAIN_CLEAR := "villain_clear"                  # ui
# M3b（M3B_PLAN §6；模板由 docs/m3b_staging/_sect.json／_econ.json／_org.json 提供；# ui 標記的走 "ui": true）
# 門派（WP-SECT）
const E_BEG := "beg"                                      # { npc_name, gain_prof, money, item_name }（self／other）
const E_SECT_ASSEMBLY := "sect_assembly"                  # { sect_name, room_name }
const E_SECT_RANK_UP := "sect_rank_up"                    # { name, sect_name, rank_name }（self／other）
const E_RANK_WAIT := "rank_wait"                          # { sect_name, rank_name, reason, reason_text }
const E_SEIZE_START := "seize_start"                      # { atk_name, def_name, sect_name }
const E_SEIZE_DONE := "seize_done"                        # { name, sect_name, by_name }（全服 SYSTEM）
const E_SHOP_REFUSED := "shop_refused"                    # { npc_name, text_key }
const E_HARASS := "harass"                                # { monster_name, n, sect_name }
const E_CONDITION_ON := "condition_on"                    # §4.10 房間 on_enter_status：{ status_name, level, room_name }
const E_JAIL_IN_CAPITAL := "jail_in_capital"              # 京城監獄的 jail_in 變體（_sect.json）
const E_JAIL_OUT_CAPITAL := "jail_out_capital"
# 錢莊、鏢局（WP-ECON）
const E_BANK_VIEW := "bank_view"                          # ui
const E_BANK_PUT := "bank_put"
const E_BANK_TAKE := "bank_take"
const E_BANK_MONEY := "bank_money"
const E_CONSIGN_SENT := "consign_sent"
const E_CONSIGN_LIST := "consign_list"                    # ui
const E_CONSIGN_ARRIVED := "consign_arrived"
const E_CONSIGN_TAKEN := "consign_taken"
const E_CONSIGN_RETURNED := "consign_returned"
const E_HUNT_START := "hunt_start"
# 組織（WP-ORG）
const E_ORG_INFO := "org_info"                            # ui
const E_ORG_PETITION := "org_petition"
const E_ORG_SIGNED := "org_signed"
const E_ORG_FOUNDED := "org_founded"
const E_ORG_PETITION_EXPIRED := "org_petition_expired"
const E_ORG_INVITE := "org_invite"                        # ui（pending prompt）
const E_ORG_JOINED := "org_joined"
const E_ORG_LEFT := "org_left"
const E_ORG_KICKED := "org_kicked"
const E_ORG_RANK_CHANGED := "org_rank_changed"
const E_ORG_TITLE_CHANGED := "org_title_changed"
const E_ORG_LEADER_CHANGED := "org_leader_changed"
const E_ORG_DISBANDED := "org_disbanded"
## M3b 中 "ui": true 的事件（UI 不經模板）
const M3B_UI_EVENTS := [E_BANK_VIEW, E_CONSIGN_LIST, E_ORG_INFO, E_ORG_INVITE]
# M3c（M3C_PLAN §8；模板 id＝事件 key）
const E_LOOK_CHANGED := "look_changed"                    # ui（self：{ look, look_name, shown }）
const E_NA_ATTACK_START := "na_attack_start"
const E_NA_NPC_KILLED := "na_npc_killed"
const E_NA_NPC_ROUTED := "na_npc_routed"
const E_NA_NPC_BACK := "na_npc_back"
const E_NA_GUARD_ALARM := "na_guard_alarm"
const E_NA_GUARD_SPARE := "na_guard_spare"             # M3c 第二輪審查：新手在城內行兇，官兵喝斥後離開
const E_NA_SECT_ENEMY := "na_sect_enemy"
const E_NA_MASTER_BETRAY := "na_master_betray"
const E_NA_MIEPAI := "na_miepai"
const E_LT_RARE_DROP := "lt_rare_drop"
const E_LT_DIVINE_TRANSFER := "lt_divine_transfer"
const E_LT_MANUAL_READ := "lt_manual_read"
## M3c 中 "ui": true 的事件
const M3C_UI_EVENTS := [E_LOOK_CHANGED]
# ---- M3c2（M3C2_PLAN §7；Q1：純新增，RPC 簽名不變 → VERSION 維持 5） ----
# I_CHAR_SELECT 參數表加 "identity": [TYPE_STRING, false]
# I_PASSPORT_IMPORT 參數表加 "new_name": [TYPE_STRING, false]
const E_FOREIGN_IMPORTED := "foreign_imported"        # ui：{ name, replaced, dropped:[String] }
const E_CH_NO_LP := "ch_no_lp"                        # 系統：{ quest_name, why: "daily"|"novice"|"rule" }
const E_CH_SPAR_CAPPED := "ch_spar_capped"            # 系統：{}
## M3c2 新原因碼（模板 err_<code>）
const R_FOREIGN_SAME_WORLD := "foreign_same_world"
const R_FOREIGN_NOT_NEWER := "foreign_not_newer"
const R_FOREIGN_OWNED := "foreign_owned"
const R_FOREIGN_BAD_DATA := "foreign_bad_data"
## M3c2 審查：外來角色已被較新的匯入取代（舊護照不能還原）；開房且沒開放外來角色時，外來角色不能進入
const R_FOREIGN_SUPERSEDED := "foreign_superseded"
const R_FOREIGN_CHAR_BLOCKED := "foreign_char_blocked"
## M3c2 第二輪審查：每個身分在本世界帶進的不同來源角色數已滿
const R_FOREIGN_QUOTA := "foreign_quota"
const R_ALT_IDENTITY_DENIED := "alt_identity_denied"
const R_CHORE_TIRED := "chore_tired"
## 握手拒絕時附帶主機資訊的原因（§6.3："<code>|<版本>|<協定>|<指紋12>"）
const REJECT_WITH_BUILD := ["protocol_mismatch", "version_mismatch", "content_mismatch"]
## M3c2 中 "ui": true 的事件
const M3C2_UI_EVENTS := [E_FOREIGN_IMPORTED]

# ---- M3d（M3D_PLAN §7；T1：純新增，RPC 簽名不變 → VERSION 維持 5） ----
# WP-LAW
const I_BOUNTY_BOARD := "bounty_board"        # { npc }
const I_BOUNTY_LICENSE := "bounty_license"    # { npc }
const I_BOUNTY_ADD := "bounty_add"            # { npc, target_name, money:int }
const I_BOUNTY_CLAIM := "bounty_claim"        # { npc }
const I_CLEANSE := "cleanse"                  # { npc, what:"KILLING"|"PK", times:int? }
const CLEANSE_WHATS := ["KILLING", "PK"]
# WP-COMBAT
const I_COMBO_BOND := "combo_bond"            # { target_char }
const I_COMBO_REPLY := "combo_reply"          # { from_char, accept:bool }
const I_COMBO_CANCEL := "combo_cancel"        # {}
const I_COMBO_NURTURE := "combo_nurture"      # {}
# battle_cmd：BATTLE_CMDS 加 "DODGE"、"QING"；參數 "mode" 依 cmd 檢查（INNER → INNER_MODES、QING → QING_MODES）
const QING_MODES := ["JUMP", "ESCAPE"]
# WP-ARTS
const I_INTIMIDATE := "intimidate"            # { npc }
const I_LIANDU := "liandu"                    # {}
# WP-EVENTS
const I_ROB_ESCORT := "rob_escort"            # { target_char }
const I_TOURNEY_INFO := "tourney_info"        # {}
const I_TOURNEY_SIGNUP := "tourney_signup"    # { npc, kind }
const I_TOURNEY_WITHDRAW := "tourney_withdraw"  # {}
const I_TOURNEY_HOST := "tourney_host"        # { kind, signup_s:int? }（HOST）
## M3d 事件（M3D_PLAN §7；模板 id＝事件 key；ui 的列在 M3D_UI_EVENTS）
# WP-LAW
const E_BOUNTY_BOARD := "bounty_board"                    # ui：{ rows, refreshed_s, claims_total, licensed, enabled }
const E_LAW_LICENSE_OK := "law_license_ok"
const E_LAW_LICENSE_VOID := "law_license_void"
const E_LAW_BOUNTY_EARNED := "law_bounty_earned"          # { target_name, amount }
const E_LAW_BOUNTY_PAID := "law_bounty_paid"              # { amount }
const E_LAW_HUNTER_WARN := "law_hunter_warn"              # ui：{ wid: "law_hunter", npc_name, warn_s }
const E_LAW_CLEANSED := "law_cleansed"                    # { what, times, cost, killing_intent, pk }
# WP-COMBAT
const E_CB_BOND_REQUEST := "cb_bond_request"              # ui：{ from_char, from_name }
const E_CB_BOND_CHANGED := "cb_bond_changed"              # ui：{ partner_name, moqi, peihe, drain_day }
const E_BATTLE_DODGE := "battle_dodge"
const E_BATTLE_QING_JUMP := "battle_qing_jump"
const E_BATTLE_QING_ESCAPE := "battle_qing_escape"
const E_BATTLE_QING_FAIL := "battle_qing_fail"
const E_BATTLE_COMBO := "battle_combo"
# WP-ARTS
const E_AR_INTIMIDATED := "ar_intimidated"                # { npc_name, gain }
const E_AR_LIANDU := "ar_liandu"                          # { gain, mult }
const E_AR_XUEMO_ENLIGHTENED := "ar_xuemo_enlightened"    # {}
# WP-EVENTS
const E_EV_JB_STARTED := "ev_jb_started"                  # { value, why }
const E_EV_JB_DONE := "ev_jb_done"
const E_EV_JB_FAILED := "ev_jb_failed"
const E_EV_JB_ROBBED := "ev_jb_robbed"                    # { robbers:[name], share }
const E_TOURNEY_STATE := "tourney_state"                  # ui：{ kind, phase, entrants, bracket, next_match }
const E_EV_TOURNEY_CALL := "ev_tourney_call"              # { name, n }
const E_EV_DUEL_RESULT := "ev_duel_result"                # { a, b, winner, how }
# WP-ERRANDS
const E_ER_SPAR_NOT_DISCIPLE := "er_spar_not_disciple"    # {}
## M3d 中 "ui": true 的事件
const M3D_UI_EVENTS := [E_BOUNTY_BOARD, E_LAW_HUNTER_WARN, E_CB_BOND_REQUEST, E_CB_BOND_CHANGED, E_TOURNEY_STATE]
## M3d 原因碼（M3D_PLAN §7；模板 err_<code>，由擁有的 WP 寫）
const M3D_REASONS_LAW := ["bounty_off", "not_board_npc", "license_pk", "license_listed", "license_deaf", "license_none",
	"bounty_not_listed", "bounty_pool_min", "bounty_pool_cap", "bounty_no_claims", "cleanse_nothing", "cleanse_daily",
	"not_cleanse_npc"]
const M3D_REASONS_COMBAT := ["dodge_off", "qing_off", "equip_cooldown", "combo_need_partner", "combo_need_party",
	"combo_pair_mismatch", "combo_moqi_low", "combo_has_partner", "combo_peihe_low", "combo_no_request", "combo_partner_absent",
	"combo_request_pending"]
const M3D_REASONS_ARTS := ["intimidate_not_xd", "intimidate_bad_target", "intimidate_daily", "liandu_no_tool", "liandu_not_xh",
	"liandu_daily"]
const M3D_REASONS_EVENTS := ["jb_no_deposit", "jb_cooldown", "jb_active", "rob_no_escort", "rob_xp", "rob_same_party",
	"tourney_disabled", "tourney_closed", "tourney_signed", "tourney_not_eligible", "tourney_running",
	"tourney_need_xp", "tourney_has_pk", "tourney_need_morality", "tourney_need_sect_skill"]   # 後四個：M3d 審查（報名條件）
const M3D_REASONS_ERRANDS := ["wlt_cooldown", "wlt_place"]
## M3d 服務的中文標籤（UiKeys.SERVICE_LABELS 由 WP-COMBAT 同步）
const M3D_SERVICE_LABELS := { "BOARD": "佈告欄", "LICENSE": "執照", "CLEANSE": "消災", "TOURNEY": "比武報名" }

# ==== ROGUE WP-RUN ====
# ---- 江湖試煉（ROGUE_PLAN §6；U7：純新增，RPC 簽名不變 → VERSION 維持 5） ----
const I_ROGUE_OPEN := "rogue_open"          # { seed:int? }
const I_ROGUE_START := "rogue_start"        # { alloc:Dictionary, name:String?, gender:String?, look:int? }
const I_ROGUE_PICK := "rogue_pick"          # { idx:int, alloc:Dictionary? }
const I_ROGUE_FIGHT := "rogue_fight"        # {}
const I_ROGUE_ABANDON := "rogue_abandon"    # { confirm:bool }
const I_ROGUE_DEBUG := "rogue_debug"        # { op:String, ids:Array?, n:int? }（只在 --debug-intents）
const ROGUE_DEBUG_OPS := ["cards", "foes", "round", "points"]
## 事件（模板 id＝事件 key；ui 的列在 ROGUE_UI_EVENTS）
const E_ROGUE_STATE := "rogue_state"            # ui：§6.3
const E_ROGUE_OVER := "rogue_over"              # ui：§3.9.1 的 summary
const E_ROGUE_ROUND_WON := "rogue_round_won"    # { round, qi, jing, neili }
const E_ROGUE_CARD_TAKEN := "rogue_card_taken"  # { title, rarity_name }
const E_ROGUE_BOSS := "rogue_boss"              # { name }
const E_ROGUE_ALLY_JOINED := "rogue_ally_joined"  # { name }
const E_ROGUE_ALLY_FALLEN := "rogue_ally_fallen"  # { name }
const E_ROGUE_POINTS := "rogue_points"          # { gained, total }
const ROGUE_UI_EVENTS := [E_ROGUE_STATE, E_ROGUE_OVER]
## 原因碼（模板 err_<code>）
const R_ROGUE_OFF := "rogue_off"
const R_ROGUE_PHASE := "rogue_phase"
const R_ROGUE_BAD_CARD := "rogue_bad_card"
const R_ROGUE_BAD_ALLOC := "rogue_bad_alloc"
const R_ROGUE_ATTR_CAP := "rogue_attr_cap"
const R_ROGUE_ALLY_FULL := "rogue_ally_full"
const R_ROGUE_SOLO_ONLY := "rogue_solo_only"
const R_ROGUE_CONFIRM := "rogue_confirm"
const ROGUE_REASONS := [R_ROGUE_OFF, R_ROGUE_PHASE, R_ROGUE_BAD_CARD, R_ROGUE_BAD_ALLOC, R_ROGUE_ATTR_CAP,
	R_ROGUE_ALLY_FULL, R_ROGUE_SOLO_ONLY, R_ROGUE_CONFIRM]
## 戰鬥 kind 與 world_info.mode
const BATTLE_KIND_ROGUE := "ROGUE"
const WORLD_MODE_ROGUE := "ROGUE"
const WORLD_MODE_MUD := "MUD"
## alloc 參數最多幾個鍵（同 char_create 的濫用防護）
const ROGUE_ALLOC_MAX_KEYS := 16
const ROGUE_DEBUG_IDS_MAX := 8

const CHAT_MAX_LEN := 200
const MAIL_MAX_LEN := 200
const PASSPORT_MAX_BYTES := 65536          # passport 參數 var_to_bytes 後的上限
const PREF_KEYS := ["accept_challenge", "accept_party"]
const PK_MODES := ["CLASSIC", "CHALLENGE_ONLY", "OFF"]
const STRING_MAX_LEN := 64        # 3.5.5：所有 String 參數（千里傳音內文除外，見 CHAT_MAX_LEN）
const RATE_PER_SEC := 20.0

const DIRS := ["N", "S", "E", "W", "NE", "NW", "SE", "SW", "U", "D", "IN", "OUT"]
const BATTLE_CMDS := ["MOVE", "ATTACK", "ART", "DEFEND", "REST", "EQUIP", "FLEE",
	"POISON", "MEDIC", "HIDDEN", "FORMATION", "INNER", "ACUPOINT", "ITEM",
	"DODGE", "QING"]   # M3d（M3D_PLAN §3.1、§3.2）
const INNER_MODES := ["HEAL", "EXPEL", "UNSEAL", "TRANSFER"]   # battle_cmd INNER 的 mode（M3A_PLAN §5.1）
## NPC 服務（lint 與 UI）；M3a 加 BETRAY JAIL TRIAL GUIDE（§6.12）
const NPC_SERVICES := ["SHOP", "TEACH", "JOIN", "INN", "RESPAWN", "TRAVEL", "MEAL", "FIGHT", "QUEST", "GUARD",
	"BETRAY", "JAIL", "TRIAL", "GUIDE",
	# M3b（M3B_PLAN §4.8）：錢莊、鏢局（WP-ECON）、組織（WP-ORG）、袋位（WP-SECT）
	"BANK", "ESCORT", "ORG", "RANK",
	# M3d（M3D_PLAN §7）：佈告欄、執照、消災（WP-LAW）、比武報名（WP-EVENTS）
	"BOARD", "LICENSE", "CLEANSE", "TOURNEY"]
## M3b 服務的中文標籤（UiKeys.SERVICE_LABELS 由 WP-UI 同步）
const M3B_SERVICE_LABELS := { "BANK": "錢莊", "ESCORT": "鏢局", "ORG": "組織", "RANK": "袋位" }
## M3b 原因碼（M3B_PLAN §6；err_<reason> 模板由 _sect／_econ／_org 碎片提供）
# 門派（WP-SECT）
const R_NO_PRACTICE := "no_practice"
const R_CANT_BEG := "cant_beg"
const R_BEG_COOLDOWN := "beg_cooldown"
const R_NOT_ENOUGH_SHEN := "not_enough_shen"
const R_ERA_LOCKED := "era_locked"
const R_SEIZE_DISABLED := "seize_disabled"
const R_NOT_ENEMY := "not_enemy"
const R_TARGET_NEWBIE_PROTECTED := "target_newbie_protected"   # 既有（M2）
const R_NO_PK_HERE := "no_pk_here"
const R_TARGET_BUSY := "target_busy"
const R_SHOP_REFUSED := "shop_refused"
# 錢莊、鏢局（WP-ECON）
const R_NOT_AT_BANK := "not_at_bank"
const R_NOT_BANKABLE := "not_bankable"
const R_BANK_FULL := "bank_full"
const R_EQUIPPED_ITEM := "equipped_item"
const R_NO_SUCH_ITEM := "no_such_item"
const R_TOO_HEAVY := "too_heavy"
const R_TOO_MANY := "too_many"
const R_BANK_MONEY_CAP := "bank_money_cap"
const R_NOT_ENOUGH_BANK_MONEY := "not_enough_bank_money"
const R_MONEY_CAP := "money_cap"
const R_NO_ROUTE := "no_route"
const R_NO_SUCH_CHAR := "no_such_char"
const R_SELF_TARGET := "self_target"
# 組織（WP-ORG）
const R_ALREADY_IN_ORG := "already_in_org"
const R_BAD_ORG_NAME := "bad_org_name"
const R_ORG_NAME_TAKEN := "org_name_taken"
const R_ALREADY_PETITIONING := "already_petitioning"
const R_NOT_PETITION := "not_petition"
const R_ALREADY_SIGNED := "already_signed"
const R_ORG_FULL := "org_full"
const R_NO_PERMISSION := "no_permission"
const R_LEADER_MUST_TRANSFER := "leader_must_transfer"
const R_NO_INVITE := "no_invite"
const R_NO_GUILD := "no_guild"                             # 既有（M2 組織頻道）
# 新條件型別（§4.3；Requirements 回 "req_<type>"）
const R_REQ_SECT_NOT := "req_sect_not"
const R_REQ_SECT_RANK_MIN := "req_sect_rank_min"
const R_REQ_ORG_MEMBER := "req_org_member"
const R_REQ_NO_ORG := "req_no_org"
const R_REQ_LIFE_MIN := "req_life_min"
const M3B_REASONS := [R_NO_PRACTICE, R_CANT_BEG, R_BEG_COOLDOWN, R_NOT_ENOUGH_SHEN, R_ERA_LOCKED, R_SEIZE_DISABLED,
	R_NOT_ENEMY, R_TARGET_NEWBIE_PROTECTED, R_NO_PK_HERE, R_TARGET_BUSY, R_SHOP_REFUSED,
	R_NOT_AT_BANK, R_NOT_BANKABLE, R_BANK_FULL, R_EQUIPPED_ITEM, R_NO_SUCH_ITEM, R_TOO_HEAVY, R_TOO_MANY,
	R_BANK_MONEY_CAP, R_NOT_ENOUGH_BANK_MONEY, R_MONEY_CAP, R_NO_ROUTE, R_NO_SUCH_CHAR, R_SELF_TARGET,
	R_ALREADY_IN_ORG, R_BAD_ORG_NAME, R_ORG_NAME_TAKEN, R_ALREADY_PETITIONING, R_NOT_PETITION, R_ALREADY_SIGNED,
	R_ORG_FULL, R_NO_PERMISSION, R_LEADER_MUST_TRANSFER, R_NO_INVITE,
	R_REQ_SECT_NOT, R_REQ_SECT_RANK_MIN, R_REQ_ORG_MEMBER, R_REQ_NO_ORG, R_REQ_LIFE_MIN]
## M3c 原因碼（M3C_PLAN §8；err_<reason> 模板由擁有該原因碼的 WP 寫）
const R_BAD_LOOK := "bad_look"
const R_NPC_ATTACK_OFF := "npc_attack_off"
const R_NPC_NOT_ATTACKABLE := "npc_not_attackable"
const R_NPC_SAFE_ROOM := "npc_safe_room"
const R_NPC_BUSY := "npc_busy"
const R_MANUALS_OFF := "manuals_off"
const R_NOT_MANUAL := "not_manual"
const R_MANUAL_ILLITERATE := "manual_illiterate"
const R_MANUAL_CAP := "manual_cap"
const R_DIVINE_LOCKED := "divine_locked"
## M3c 審查：CHALLENGE 的 NPC 剛被你打退（同一角色要等重生時間才能再找他動手）
const R_NPC_ROUTED := "npc_routed"
const M3C_REASONS := [R_BAD_LOOK, R_NPC_ATTACK_OFF, R_NPC_NOT_ATTACKABLE, R_NPC_SAFE_ROOM, R_NPC_BUSY,
	R_MANUALS_OFF, R_NOT_MANUAL, R_MANUAL_ILLITERATE, R_MANUAL_CAP, R_DIVINE_LOCKED, R_NPC_ROUTED]
## 組織位階數（0 幫主 … 4 幫眾；M3B_PLAN §5.3）
const ORG_RANKS := 5
## M3a 原因碼（§6.12；err_<reason> 模板由 _rules.json 提供）
const R_SECT_STOP_TEACH := "sect_stop_teach"
const R_SECT_BANNED := "sect_banned"
const R_SECT_LOCKOUT := "sect_lockout"
const R_JAILED := "jailed"
const R_NEED_CONFIRM := "need_confirm"
const R_NO_PRISONER := "no_prisoner"
const R_TRIAL_PARTY := "trial_party"
const R_NO_FLEE := "no_flee"
## 故事包原因碼（STORY_PLAN §4.14；fail_<code> 模板由 docs/story_staging/_engine.json 提供）
const R_DIALOGUE_NONE := "dialogue_none"
const R_DIALOGUE_STALE := "dialogue_stale"
const R_CHOICE_LOCKED := "choice_locked"
const R_QUEST_COOLDOWN := "quest_cooldown"
const R_QUEST_NOT_NOW := "quest_not_now"
const R_ACT_UNKNOWN := "act_unknown"
const R_ACT_NOT_HERE := "act_not_here"
const R_VILLAIN_NONE := "villain_none"
const R_NPC_REFUSE := "npc_refuse"
const R_ESCORT_LOST := "escort_lost"
const STORY_REASONS := [R_DIALOGUE_NONE, R_DIALOGUE_STALE, R_CHOICE_LOCKED, R_QUEST_COOLDOWN, R_QUEST_NOT_NOW,
	R_ACT_UNKNOWN, R_ACT_NOT_HERE, R_VILLAIN_NONE, R_NPC_REFUSE, R_ESCORT_LOST]
## 型別欄位為 TYPE_NIL 的參數不檢查型別（debug_set 的 value；§6.12「任意，型別不檢查」）
const ANY_TYPE := TYPE_NIL
const SLOTS := ["WEAPON", "ARMOR", "HEAD", "NECK", "WRIST", "CLOAK", "RING", "BOOTS"]   # M3c §8：取代原本兩格（I_UNEQUIP 的列舉跟著擴）
const EXERT_STATS := ["jing", "qi", "shen"]
const GENDERS := ["M", "F"]
const LIFE_SKILLS := ["life_farming", "life_woodcut", "life_fishing", "life_cooking",
	# M3b（M3B_PLAN §4.5，id 綁定）：挖礦、打鐵、鑄劍、工匠（1.0B）、織布、裁縫、獵人
	"life_mining", "life_smithing", "life_swordsmith", "life_carpentry", "life_weaving", "life_tailoring", "life_hunting"]
const BATTLE_W := 12
const BATTLE_H := 8

## kind -> { arg_name: [type, required] }（3.6）
const INTENT_SCHEMA := {
	I_PING: { "nonce": [TYPE_INT, false] },
	I_CHAT: { "text": [TYPE_STRING, true], "ch": [TYPE_STRING, false], "to": [TYPE_STRING, false] },
	I_CHAR_LIST: {},
	I_CHAR_ROLL: {},
	I_CHAR_CREATE: { "name": [TYPE_STRING, true], "gender": [TYPE_STRING, true],
		"birth_month": [TYPE_INT, true], "birth_city": [TYPE_STRING, true], "alloc": [TYPE_DICTIONARY, true],
		"look": [TYPE_INT, false] },
	I_CHAR_SELECT: { "char_id": [TYPE_STRING, true], "identity": [TYPE_STRING, false] },   # M3c2 §5.7：identity 可選
	I_CHAR_DELETE: { "char_id": [TYPE_STRING, true], "confirm_name": [TYPE_STRING, true] },
	I_LOOK: { "scout": [TYPE_BOOL, false] },
	I_MOVE: { "dir": [TYPE_STRING, true] },
	I_TRAVEL: { "npc": [TYPE_STRING, true], "dest": [TYPE_STRING, true] },
	I_TALK: { "npc": [TYPE_STRING, true] },
	I_SHOP_LIST: { "npc": [TYPE_STRING, true] },
	I_BUY: { "npc": [TYPE_STRING, true], "item": [TYPE_STRING, true], "n": [TYPE_INT, false] },
	I_SELL: { "npc": [TYPE_STRING, true], "item_uid": [TYPE_STRING, true], "n": [TYPE_INT, false] },
	I_LEARN_LIST: { "npc": [TYPE_STRING, true] },
	I_LEARN: { "npc": [TYPE_STRING, true], "skill": [TYPE_STRING, true], "times": [TYPE_INT, false] },
	I_SELF_STUDY: { "skill": [TYPE_STRING, true], "times": [TYPE_INT, false] },
	I_JOIN_SECT: { "npc": [TYPE_STRING, true] },
	I_INN_REST: { "npc": [TYPE_STRING, true] },
	I_SET_RESPAWN: { "npc": [TYPE_STRING, true] },
	I_MEAL: { "npc": [TYPE_STRING, true] },
	I_FIGHT: { "npc": [TYPE_STRING, true] },
	I_USE_ITEM: { "item_uid": [TYPE_STRING, true] },
	I_EQUIP: { "item_uid": [TYPE_STRING, true] },
	I_UNEQUIP: { "slot": [TYPE_STRING, true] },
	I_DROP_ITEM: { "item_uid": [TYPE_STRING, true], "n": [TYPE_INT, false] },
	I_MEDITATE: {},
	I_EXERT: { "stat": [TYPE_STRING, true] },
	I_WORK: { "skill": [TYPE_STRING, true], "recipe": [TYPE_STRING, false] },
	I_QUEST_ACCEPT: { "npc": [TYPE_STRING, true], "quest": [TYPE_STRING, true] },
	I_QUEST_TURN_IN: { "npc": [TYPE_STRING, true], "quest": [TYPE_STRING, true] },
	I_QUEST_ABANDON: { "quest": [TYPE_STRING, true] },
	I_LOOT_CORPSE: { "corpse_id": [TYPE_STRING, true], "item_uid": [TYPE_STRING, false] },
	I_BATTLE_CMD: { "battle_id": [TYPE_INT, true], "cmd": [TYPE_STRING, true], "target": [TYPE_ARRAY, false],
		"art": [TYPE_STRING, false], "move": [TYPE_STRING, false], "power_tenths": [TYPE_INT, false],
		"item_uid": [TYPE_STRING, false], "mode": [TYPE_STRING, false] },
	# ---- M2（4.1） ----
	I_PARTY_INVITE: { "target": [TYPE_STRING, true] },
	I_PARTY_REPLY: { "from": [TYPE_STRING, true], "accept": [TYPE_BOOL, true] },
	I_PARTY_LEAVE: {},
	I_PARTY_KICK: { "target": [TYPE_STRING, true] },
	I_PARTY_LEAD: { "target": [TYPE_STRING, true] },
	I_BATTLE_JOIN: { "battle_id": [TYPE_INT, true] },
	I_CHALLENGE: { "target": [TYPE_STRING, true] },
	I_CHALLENGE_REPLY: { "from": [TYPE_STRING, true], "accept": [TYPE_BOOL, true] },
	I_FORCE_PK: { "target": [TYPE_STRING, true] },
	I_SET_PREF: { "key": [TYPE_STRING, true], "value": [TYPE_BOOL, true] },
	I_CORPSE_AUTHORIZE: { "corpse_id": [TYPE_STRING, true], "name": [TYPE_STRING, true] },
	I_MAIL_SEND: { "to": [TYPE_STRING, true], "text": [TYPE_STRING, true] },
	I_MAIL_LIST: {},
	I_MAIL_READ: { "id": [TYPE_STRING, true] },
	I_MAIL_DELETE: { "id": [TYPE_STRING, true] },
	I_SERVER_OPTS_GET: {},
	I_SERVER_OPTS_SET: { "key": [TYPE_STRING, true], "value": [TYPE_STRING, true] },
	I_ADMIN_KICK: { "peer": [TYPE_INT, true], "ban": [TYPE_BOOL, false] },
	I_PASSPORT_REQUEST: { "char_id": [TYPE_STRING, true] },
	I_PASSPORT_RESTORE: { "passport": [TYPE_DICTIONARY, true] },
	I_PASSPORT_IMPORT: { "passport": [TYPE_DICTIONARY, true], "new_name": [TYPE_STRING, false] },   # M3c2 §5.6
	# ---- 查看偵察 ----
	I_SCOUT_ACCEPT: { "offer_id": [TYPE_STRING, true] },
	I_SCOUT_DECLINE: { "offer_id": [TYPE_STRING, true] },
	# ---- M3a（§6.12） ----
	I_SECT_BETRAY: { "npc": [TYPE_STRING, true], "confirm": [TYPE_BOOL, false] },
	I_JAIL_RANSOM: { "npc": [TYPE_STRING, true], "name": [TYPE_STRING, true] },
	I_SECT_TRIAL: { "npc": [TYPE_STRING, true] },
	I_NPC_GUIDE: { "npc": [TYPE_STRING, true] },
	I_DEBUG_SET: { "key": [TYPE_STRING, true], "value": [ANY_TYPE, true] },
	# ---- 故事包（STORY_PLAN §4.14） ----
	I_QUEST_TALK: { "npc": [TYPE_STRING, true], "quest": [TYPE_STRING, true] },
	I_DIALOGUE_CHOOSE: { "npc": [TYPE_STRING, true], "quest": [TYPE_STRING, true], "node": [TYPE_STRING, true],
		"choice": [TYPE_STRING, true] },
	I_DIALOGUE_CLOSE: {},
	I_STORY_ACT: { "act": [TYPE_STRING, true] },
	I_VILLAIN_REPLY: { "wid": [TYPE_STRING, true], "choice": [TYPE_STRING, true] },
	I_RUMOR_LIST: {},
	# ---- M3b（M3B_PLAN §6） ----
	I_BEG: { "npc": [TYPE_STRING, true] },
	I_SEIZE_ENEMY: { "name": [TYPE_STRING, true] },
	I_BANK_OPEN: { "npc": [TYPE_STRING, true] },
	I_BANK_PUT: { "npc": [TYPE_STRING, true], "uid": [TYPE_STRING, true], "n": [TYPE_INT, true] },
	I_BANK_TAKE: { "npc": [TYPE_STRING, true], "uid": [TYPE_STRING, true], "n": [TYPE_INT, true] },
	I_BANK_MONEY: { "npc": [TYPE_STRING, true], "amount": [TYPE_INT, true] },
	I_CONSIGN_SEND: { "npc": [TYPE_STRING, true], "to": [TYPE_STRING, true], "city": [TYPE_STRING, true],
		"items": [TYPE_ARRAY, true], "money": [TYPE_INT, true] },
	I_CONSIGN_LIST: { "npc": [TYPE_STRING, true] },
	I_CONSIGN_TAKE: { "npc": [TYPE_STRING, true], "id": [TYPE_STRING, true] },
	I_ORG_FOUND: { "npc": [TYPE_STRING, true], "name": [TYPE_STRING, true] },
	I_ORG_SIGN: { "npc": [TYPE_STRING, true], "org": [TYPE_STRING, true] },
	I_ORG_INVITE: { "name": [TYPE_STRING, true] },
	I_ORG_REPLY: { "org": [TYPE_STRING, true], "accept": [TYPE_BOOL, true] },
	I_ORG_LEAVE: {},
	I_ORG_KICK: { "name": [TYPE_STRING, true] },
	I_ORG_SET_RANK: { "name": [TYPE_STRING, true], "rank": [TYPE_INT, true] },
	I_ORG_RANK_NAMES: { "names": [TYPE_ARRAY, true] },
	I_ORG_TITLE: { "name": [TYPE_STRING, true], "title": [TYPE_STRING, true] },
	I_ORG_LEAD: { "name": [TYPE_STRING, true] },
	I_ORG_DISBAND: { "confirm": [TYPE_BOOL, true] },
	I_ORG_INFO: {},
	# ---- M3c（M3C_PLAN §8） ----
	I_SET_LOOK: { "look": [TYPE_INT, true] },
	I_NPC_ATTACK: { "npc": [TYPE_STRING, true], "mode": [TYPE_STRING, false] },
	I_MANUAL_READ: { "item_uid": [TYPE_STRING, true], "times": [TYPE_INT, false] },
	# ---- M3d（M3D_PLAN §7） ----
	I_BOUNTY_BOARD: { "npc": [TYPE_STRING, true] },
	I_BOUNTY_LICENSE: { "npc": [TYPE_STRING, true] },
	I_BOUNTY_ADD: { "npc": [TYPE_STRING, true], "target_name": [TYPE_STRING, true], "money": [TYPE_INT, true] },
	I_BOUNTY_CLAIM: { "npc": [TYPE_STRING, true] },
	I_CLEANSE: { "npc": [TYPE_STRING, true], "what": [TYPE_STRING, true], "times": [TYPE_INT, false] },
	I_COMBO_BOND: { "target_char": [TYPE_STRING, true] },
	I_COMBO_REPLY: { "from_char": [TYPE_STRING, true], "accept": [TYPE_BOOL, true] },
	I_COMBO_CANCEL: {},
	I_COMBO_NURTURE: {},
	I_INTIMIDATE: { "npc": [TYPE_STRING, true] },
	I_LIANDU: {},
	I_ROB_ESCORT: { "target_char": [TYPE_STRING, true] },
	I_TOURNEY_INFO: {},
	I_TOURNEY_SIGNUP: { "npc": [TYPE_STRING, true], "kind": [TYPE_STRING, true] },
	I_TOURNEY_WITHDRAW: {},
	I_TOURNEY_HOST: { "kind": [TYPE_STRING, true], "signup_s": [TYPE_INT, false] },
	# ---- ROGUE WP-RUN（ROGUE_PLAN §6.1） ----
	I_ROGUE_OPEN: { "seed": [TYPE_INT, false] },
	I_ROGUE_START: { "alloc": [TYPE_DICTIONARY, true], "name": [TYPE_STRING, false], "gender": [TYPE_STRING, false],
		"look": [TYPE_INT, false] },
	I_ROGUE_PICK: { "idx": [TYPE_INT, true], "alloc": [TYPE_DICTIONARY, false] },
	I_ROGUE_FIGHT: {},
	I_ROGUE_ABANDON: { "confirm": [TYPE_BOOL, true] },
	I_ROGUE_DEBUG: { "op": [TYPE_STRING, true], "ids": [TYPE_ARRAY, false], "n": [TYPE_INT, false] },
}

## M3b：consign_send.items 最多幾列（M3B_PLAN §5.2.2「items 最多 10 個 uid」）、org_rank_names 一定 5 個
const CONSIGN_MAX_ITEMS := 10

## 數值參數的範圍（3.6「範圍驗證」欄）：kind -> { arg: [min, max] }
const INT_RANGES := {
	I_CHAR_CREATE: { "birth_month": [1, 12], "look": [0, LOOK_MAX] },
	I_BUY: { "n": [1, 99] },
	I_SELL: { "n": [1, 99] },
	I_LEARN: { "times": [1, 10] },
	I_SELF_STUDY: { "times": [1, 10] },
	I_DROP_ITEM: { "n": [1, 999] },
	I_BATTLE_CMD: { "power_tenths": [1, 10] },
	I_BATTLE_JOIN: { "battle_id": [1, 2147483647] },
	I_ADMIN_KICK: { "peer": [1, 2147483647] },
	# M3b
	I_BANK_PUT: { "n": [1, 9999] },
	I_BANK_TAKE: { "n": [1, 9999] },
	I_BANK_MONEY: { "amount": [-6000000, 6000000] },
	I_CONSIGN_SEND: { "money": [0, 6000000] },
	I_ORG_SET_RANK: { "rank": [0, 4] },
	# M3c
	I_SET_LOOK: { "look": [0, LOOK_MAX] },
	I_MANUAL_READ: { "times": [1, 10] },
	# M3d
	I_BOUNTY_ADD: { "money": [1, 6000000] },
	I_CLEANSE: { "times": [1, 100] },
	I_TOURNEY_HOST: { "signup_s": [30, 1800] },
	# ROGUE WP-RUN（ROGUE_PLAN §6.1）
	I_ROGUE_OPEN: { "seed": [0, 2147483647] },
	I_ROGUE_START: { "look": [0, LOOK_MAX] },
	I_ROGUE_PICK: { "idx": [0, 2] },
	I_ROGUE_DEBUG: { "n": [0, 999] },
}

## 字串參數的列舉（3.6「範圍驗證」欄）：kind -> { arg: [允許值] }
const ENUMS := {
	I_CHAR_CREATE: { "gender": GENDERS },
	I_MOVE: { "dir": DIRS },
	I_UNEQUIP: { "slot": SLOTS },
	I_EXERT: { "stat": EXERT_STATS },
	I_WORK: { "skill": LIFE_SKILLS },
	I_BATTLE_CMD: { "cmd": BATTLE_CMDS },   # mode 依 cmd 檢查（BATTLE_CMD_MODES；M3D_PLAN §7）
	I_SET_PREF: { "key": PREF_KEYS },
	I_VILLAIN_REPLY: { "choice": VILLAIN_CHOICES },
	I_NPC_ATTACK: { "mode": NPC_ATTACK_MODES },
	I_CLEANSE: { "what": CLEANSE_WHATS },
	# ROGUE WP-RUN（ROGUE_PLAN §6.1）
	I_ROGUE_START: { "gender": GENDERS },
	I_ROGUE_DEBUG: { "op": ROGUE_DEBUG_OPS },
}

## battle_cmd 的 mode 依 cmd 檢查（M3D_PLAN §7）；表上沒有的 cmd 照 M3a 用 INNER_MODES（舊行為不變）
const BATTLE_CMD_MODES := { "INNER": INNER_MODES, "QING": QING_MODES }

const CHAT_CHANNELS := [CH_CHAT_WORLD, CH_CHAT_WHISPER, CH_CHAT_SAY, CH_CHAT_SECT, CH_CHAT_GUILD,
	CH_CHAT_PARTY, CH_CHAT_RUMOR, CH_GM]

## 玩家輸入的文字（聊天、信件、名字）在主機端先清理（M2_PLAN H6）：換行／定位字元改成空白、去掉其他控制字元、
## `[`→`［`、`]`→`］`（與 WorldServer._clean_name 相同，避免 BBCode 注入），去掉頭尾空白，最後截到 max_len 字。
static func clean_text(text: String, max_len: int) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if c == 0x0A or c == 0x0D or c == 0x09:
			out += " "
		elif c < 0x20 or c == 0x7F or (c >= 0x80 and c < 0xA0) or c == 0x2028 or c == 0x2029:
			continue
		elif c == 0x5B:   # [
			out += "［"
		elif c == 0x5D:   # ]
			out += "］"
		else:
			out += String.chr(c)
	out = out.strip_edges()
	if max_len > 0 and out.length() > max_len:
		out = out.substr(0, max_len)
	return out

static func is_known(kind: String) -> bool:
	return INTENT_SCHEMA.has(kind)

## 型別與範圍驗證。回傳空字串代表通過，否則是錯誤原因。
static func validate_args(kind: String, args: Dictionary) -> String:
	if not INTENT_SCHEMA.has(kind):
		return "unknown_intent"
	var schema: Dictionary = INTENT_SCHEMA[kind]
	for key in args:
		if typeof(key) != TYPE_STRING or not schema.has(key):
			return "unexpected_arg"
		if schema[key][0] != ANY_TYPE and typeof(args[key]) != schema[key][0]:
			return "bad_type:" + str(key)
	for key in schema:
		if schema[key][1] and not args.has(key):
			return "missing_arg:" + str(key)
	if kind == I_CHAT:
		var text: String = args["text"]
		if text.strip_edges().is_empty():
			return "empty_text"
		if text.length() > CHAT_MAX_LEN:
			return "text_too_long"
		if args.has("ch") and not (args["ch"] in CHAT_CHANNELS):
			return "bad_channel"
		# M2（4.1）：傳音入密一定要有對象；其他頻道不能帶 to
		var ch: String = args.get("ch", CH_CHAT_WORLD)
		if ch == CH_CHAT_WHISPER and not args.has("to"):
			return "missing_arg:to"
		if args.has("to") and ch != CH_CHAT_WHISPER:
			return "unexpected_arg"
		if args.has("to") and (args["to"] as String).length() > STRING_MAX_LEN:
			return "bad_value:to"
		return ""
	if kind == I_MAIL_SEND:
		var body: String = args["text"]
		if body.strip_edges().is_empty():
			return "empty_text"
		if body.length() > MAIL_MAX_LEN:
			return "text_too_long"
	if kind == I_PASSPORT_RESTORE or kind == I_PASSPORT_IMPORT:
		if var_to_bytes(args["passport"]).size() > PASSPORT_MAX_BYTES:
			return "bad_value:passport"
	# 3.5.5：String 參數長度 ≤ 64（飛鴿內文例外，上限 MAIL_MAX_LEN）
	for key in args:
		if kind == I_MAIL_SEND and key == "text":
			continue
		if args[key] is String and (args[key] as String).length() > STRING_MAX_LEN:
			return "bad_value:" + str(key)
	var ranges: Dictionary = INT_RANGES.get(kind, {})
	for key in ranges:
		if args.has(key) and (int(args[key]) < int(ranges[key][0]) or int(args[key]) > int(ranges[key][1])):
			return "bad_value:" + str(key)
	var enums: Dictionary = ENUMS.get(kind, {})
	for key in enums:
		if args.has(key) and not (args[key] in enums[key]):
			return "bad_value:" + str(key)
	if kind == I_BATTLE_CMD and args.has("mode"):
		var modes: Array = BATTLE_CMD_MODES.get(str(args["cmd"]), INNER_MODES)
		if not (args["mode"] in modes):
			return "bad_value:mode"
	if kind == I_CHAR_CREATE:
		# alloc 的內容（鍵、值、總和）由 CharacterFactory.validate_alloc 判定（bad_alloc），這裡只擋明顯的濫用
		if (args["alloc"] as Dictionary).size() > 16:
			return "bad_value:alloc"
	# M3b：consign_send.items = [{ uid: String, n: int ≥ 1 }]（最多 10 列）；org_rank_names.names = 5 個字串
	if kind == I_CONSIGN_SEND:
		var its: Array = args["items"]
		if its.size() > CONSIGN_MAX_ITEMS:
			return "bad_value:items"
		for it in its:
			if typeof(it) != TYPE_DICTIONARY or typeof(it.get("uid")) != TYPE_STRING \
					or (it["uid"] as String).length() > STRING_MAX_LEN or typeof(it.get("n", 1)) != TYPE_INT \
					or int(it.get("n", 1)) < 1 or (it as Dictionary).size() > 2:
				return "bad_value:items"
	# ROGUE WP-RUN：alloc 的內容由 RogueRun／RogueSystem 判定（rogue_bad_alloc），這裡只擋濫用；debug ids 只能是字串
	if (kind == I_ROGUE_START or kind == I_ROGUE_PICK) and args.has("alloc") \
			and (args["alloc"] as Dictionary).size() > ROGUE_ALLOC_MAX_KEYS:
		return "bad_value:alloc"
	if kind == I_ROGUE_DEBUG and args.has("ids"):
		var rids: Array = args["ids"]
		if rids.size() > ROGUE_DEBUG_IDS_MAX:
			return "bad_value:ids"
		for x in rids:
			if typeof(x) != TYPE_STRING or (x as String).length() > STRING_MAX_LEN:
				return "bad_value:ids"
	if kind == I_ORG_RANK_NAMES:
		var names: Array = args["names"]
		if names.size() != ORG_RANKS:
			return "bad_value:names"
		for nm in names:
			if typeof(nm) != TYPE_STRING or (nm as String).length() > STRING_MAX_LEN:
				return "bad_value:names"
	if kind == I_BATTLE_CMD and args.has("target"):
		var t: Array = args["target"]
		if t.size() != 2 or typeof(t[0]) != TYPE_INT or typeof(t[1]) != TYPE_INT:
			return "bad_value:target"
		if int(t[0]) < 0 or int(t[0]) >= BATTLE_W or int(t[1]) < 0 or int(t[1]) >= BATTLE_H:
			return "bad_value:target"
	return ""
