class_name CooldownTracker
extends RefCounted
## 動作冷卻的本機倒數（修煉內力、生活技能、查看偵察）。主機在角色表 sheet.cooldowns 給「送出當下的剩餘真實秒數」
## （{ "meditate": s, "life": s }，M1_PLAN 3.9.1）；ClientState 收到角色表時蓋上本機收件時刻 sheet._rx_ms，
## 到期時刻 = 收件時刻 + 剩餘秒數，之後每幀自己倒數，不輪詢主機。
## 同一份角色表重複套用（例如開視窗時把舊角色表再給一次）算出同一個到期時刻，不會重設倒數；
## 兩次動作即使剩餘秒數一模一樣，收件時刻不同，第二次倒數照樣開始（不靠數值比對去重）。
## 比上一份更舊的角色表（_rx_ms 較小）不採用。

const KEY_MEDITATE := "meditate"
const KEY_LIFE := "life"
const KEY_SCOUT := "scout"         # 查看偵察：主機只在能偵察的房間給非 0（安全的房間查看沒有冷卻）
const RX_KEY := "_rx_ms"           # ClientState._apply_sheet 蓋的本機收件時刻（Time.get_ticks_msec）

var _ready_ms: Dictionary = {}     # key -> 本機到期 ticks_msec
var _last_rx := -1

## now_ms：測試可指定；預設 Time.get_ticks_msec()。沒有 _rx_ms 的角色表（測試直接餵）以 now 當收件時刻。
func update(sheet: Dictionary, now_ms: int = -1) -> void:
	var cd: Variant = sheet.get("cooldowns", null)
	if not (cd is Dictionary):
		return
	var now := Time.get_ticks_msec() if now_ms < 0 else now_ms
	var rx := int(sheet.get(RX_KEY, now))
	if rx < _last_rx:
		return
	_last_rx = rx
	for k in cd:
		# 四捨五入到毫秒：5.0000000001 秒不會變成 5001 ms（顯示成 6 秒）
		_ready_ms[str(k)] = rx + int(round(maxf(0.0, float(cd[k])) * 1000.0))

func left_ms(key: String, now_ms: int = -1) -> int:
	if key == "":
		return 0
	var now := Time.get_ticks_msec() if now_ms < 0 else now_ms
	return maxi(0, int(_ready_ms.get(key, 0)) - now)

## 剩餘秒數（無條件進位；0 = 可用）
func left_s(key: String, now_ms: int = -1) -> int:
	return ceili(left_ms(key, now_ms) / 1000.0)

## 指令 id → 冷卻 key（"" = 沒有冷卻）：修煉內力 → meditate；所有生活技能共用 life；查看 → scout
static func key_for(cmd_id: String) -> String:
	if cmd_id == "meditate":
		return KEY_MEDITATE
	if cmd_id == "look":
		return KEY_SCOUT
	if UiCommands.is_work(cmd_id):
		return KEY_LIFE
	return ""

## 按鈕文字：「修煉（7 秒）」；secs <= 0 時就是原名
static func label(base: String, secs: int) -> String:
	return base + suffix(secs)

## 名稱後面接的倒數「（7 秒）」；JyButton 冷卻中把它畫在鈕面名稱下一行，鈕面讀起來就是「修煉（7 秒）」
static func suffix(secs: int) -> String:
	return "（%d 秒）" % secs if secs > 0 else ""
