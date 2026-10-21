class_name Session
extends RefCounted
## 一位連線玩家（TECH_ARCH 4.1 server/session.gd、M1_PLAN 3.5.2）。

const DIRTY_SHEET := 1

var peer_id: int
var identity: String
var display_name: String
var rate_limiter: TokenBucket
var last_seq := 0
var joined_ms := 0
## M1：目前選中的 Character（null = 未選角）。
## M1_PLAN 缺漏：契約寫 `var character: Character`；這裡刻意不加型別，讓 Session（以及引用它的 WorldServer
## Autoload）在 core/character 尚未合併或載入失敗時仍可解析，M0 功能不受影響。
var character: Variant = null
var pending_roll: Dictionary = {}
var battle_id := 0
var sheet_dirty := false
var view_dirty := false
var last_sheet_s := -1000.0      # 上次送角色表的世界時間（節流 0.25 秒）
var last_view_s := -1000.0
var dirty := 0
var dropped_intents := 0
## M2_PLAN 4.6.8：本地玩家（非 --dedicated 的主機 peer，含離線模式）或 identity ∈ options.admin_identities
var is_admin := false
var is_local := false               # 主機本機玩家（不經網路；不能被踢、不能被重連取代）
## 查看偵察（ScoutSystem）：主機保管的邀戰提示 { id, char_id, room, monsters: [monster id], expires_s（世界時間） }；
## 空 = 沒有。換房、進戰鬥、離線／換角、過期即失效。不存檔。
var scout_offer: Dictionary = {}
var scout_ready_s := -1.0            # 下一次能偵察的世界時間（冷卻；-1 = 從沒偵察過）
var scout_ready_ms := 0              # 同一個冷卻的主機真實時鐘到期時刻（Time.get_ticks_msec；兩者取先到者）
## M3a（SectSystem.on_enter_room）：上一次進房時的地區 id，用來判斷「換了地區」（ENTER_REGION 門規、門派技能衰減）。不存檔。
var last_region := ""
## 故事包（STORY_PLAN §4.5）：對話游標 { npc, quest, dlg, node }；空 = 沒有開著的任務對話。
## 移動、開戰、斷線、dialogue_close 時清除；不存檔（重連後重新交談，從階段的 resume 節點開始）。
var dialogue: Dictionary = {}
## QuestSystem.on_sheet 的節流（真實毫秒；同一角色每秒最多檢查一次 STATE 目標）
var quest_state_check_ms := -100000
## M3D_PLAN §3.6（WP-COMBAT）：上一次在地圖上換裝（equip／unequip 成功）的主機真實毫秒；不存檔
var last_equip_ms := -100000

func has_dialogue() -> bool:
	return not dialogue.is_empty()

func _init(p_peer_id: int, p_identity: String, p_display_name: String) -> void:
	peer_id = p_peer_id
	identity = p_identity
	display_name = p_display_name
	rate_limiter = TokenBucket.new(Protocol.RATE_PER_SEC, Protocol.RATE_PER_SEC)
	joined_ms = Time.get_ticks_msec()

func mark_dirty(flag: int) -> void:
	dirty |= flag
	if flag & DIRTY_SHEET:
		sheet_dirty = true

func has_character() -> bool:
	return character != null

func in_battle() -> bool:
	return battle_id != 0

func room_id() -> String:
	if character == null:
		return ""
	return str(character.location.get("room", ""))

func to_roster_entry() -> Dictionary:
	return { "peer": peer_id, "name": display_name }

## 給管理面板看的短身分（M2_PLAN 4.7.2 identity_short）
func identity_short() -> String:
	if identity.length() <= 14:
		return identity
	return "%s…%s" % [identity.left(8), identity.right(4)]
