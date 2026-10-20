class_name ConditionSystem
extends RefCounted
## 以上線秒數計的定時工作（M3A_PLAN 6.1、6.10；K4）：戰後中毒發作、刑期期滿、禁止學武期滿、坐牢中的人一定在思過處、
## 每遊戲日的門派技能衰減、每分鐘一次的門規狀態檢查（TICK）。GameHost.tick 每 0.1 秒呼叫 tick(dt)，這裡每 1 秒做一次。
## GameHost 以路徑 load() 建立（K3）；host.sects 可能為 null（一律先判斷）。

const STEP_S := 1.0                # 每秒檢查一次（世界 tick 累積）
const STATE_CHECK_S := 60.0        # 每分鐘一次 check_state(TICK)
const OPTION_FLARE := "poison_flare_enabled"

var host: GameHost
var _acc := 0.0
var _state_acc := 0.0
## 已經看過「在戰鬥中」的角色（char_id -> true）：戰後持續狀態已經轉成戰鬥狀態帶進去了（3.11 statuses），
## 戰鬥結束時 WP-CMD 會把還留著的 persists 狀態用 add_condition 寫回來
var _in_battle: Dictionary = {}

func _init(p_host: GameHost) -> void:
	host = p_host

func tick(dt: float) -> void:
	_acc += dt
	if _acc < STEP_S - 1e-6:
		return
	_acc = 0.0
	_state_acc += STEP_S
	var do_state := _state_acc >= STATE_CHECK_S - 1e-6
	if do_state:
		_state_acc = 0.0
	for s in host.sessions():
		if s.character == null:
			continue
		check_now(s)
		if do_state and host.sects != null and s.battle_id == 0:
			host.sects.check_state(s, "TICK")

## 立刻檢查一位角色（debug_set online_s_add 之後也呼叫）
func check_now(s: Session) -> void:
	if s == null or s.character == null:
		return
	var ch = s.character
	_battle_carry(s)
	if s.battle_id == 0:
		_flare(s)
	if host.sects != null:
		if ch.is_jailed():
			if ch.online_s >= float(ch.jail.get("until_online_s", 0.0)):
				host.sects.release(s, "served")
			else:
				host.sects.enforce_jail(s)
		host.sects.enforce_lockout(s)
		host.sects.daily_tick(s)
	var ban_until := float(ch.sect_record.get("ban_until_online_s", 0.0))
	if ban_until > 0.0 and ch.online_s >= ban_until:
		ch.sect_record["ban_until_online_s"] = 0.0   # 禁止學武期滿
		s.sheet_dirty = true

## M3B_PLAN §4.10：戰鬥外施加持續狀態（房間 on_enter_status，例：情花林的情花毒）。
## 次數 = level × persist_ticks_per_level，第一次發作在 persist_tick_real_s 之後（與戰後寫回同一規則）；送 condition_on。
## 回傳是否施加了（狀態不存在、不是 persists 的狀態 → false）
func add(s: Session, status_id: String, level: int = 1) -> bool:
	if s == null or s.character == null:
		return false
	var row: Variant = host.tables.get("status_effects", {}).get(status_id, null)
	if not (row is Dictionary) or not bool(row.get("persists", false)):
		return false
	var ch = s.character
	var lv := maxi(1, level)
	var ticks := maxi(1, lv * int(row.get("persist_ticks_per_level", 1)))
	ch.add_condition(status_id, lv, ticks, float(ch.online_s) + maxf(1.0, float(row.get("persist_tick_real_s", 120))))
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_CONDITION_ON,
		{ "status_name": str(row.get("name", status_id)), "level": int(ch.condition_level(status_id)),
			"room_name": host.room_name(s.room_id()) })
	s.sheet_dirty = true
	return true

## 進了戰鬥：戰後持續狀態由 to_combatant 的 statuses 帶進去（剩餘行動次數 actions_left），但**留在角色身上**：
## 戰鬥中暫停發作（_flare 只在 battle_id == 0 時跑），戰鬥結束由 BattleSystem._settle_conditions 依戰況更新或移除，
## 剩下的發作次數與下次發作時刻不會因為打了一場就重新計時（M3a 審查修正）。
func _battle_carry(s: Session) -> void:
	var cid := str(s.character.id)
	if s.battle_id == 0:
		_in_battle.erase(cid)
		return
	_in_battle[cid] = true

## 戰後發作（§6.10）：到點扣氣上限比例（最低剩 1，不致死）、次數 −1；次數 0 → 移除並送 condition_off。
## 選項 poison_flare_enabled == false：不發作、直接到期移除。
func _flare(s: Session) -> void:
	var ch = s.character
	if ch.conditions.is_empty():
		return
	var on: bool = host.options.get(OPTION_FLARE, true) != false
	var st: Dictionary = host.tables.get("status_effects", {})
	var ids: Array = ch.conditions.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = ch.conditions[id]
		var row: Dictionary = st.get(id, {})
		var sname := str(row.get("name", id))
		if not on:
			ch.clear_condition(id)
			host.tell(s, Protocol.CH_SYSTEM, Protocol.E_CONDITION_OFF, { "status_name": sname })
			s.sheet_dirty = true
			continue
		var interval := maxf(1.0, float(row.get("persist_tick_real_s", 120)))
		var guard := 0
		while ch.conditions.has(id) and ch.online_s >= float(e.get("next_online_s", 0.0)) and guard < 1000:
			guard += 1
			var d: Dictionary = ch.derived(host.tables, host.options)
			var qi_max := int(d.get("qi_max", 1))
			var dmg := maxi(1, roundi(qi_max * float(row.get("persist_qi_pct", 0.0))))
			var before := int(ch.vitals.get("qi", 0))
			var after := maxi(1, before - dmg) if before > 1 else before
			ch.vitals["qi"] = after
			host.tell(s, Protocol.CH_SYSTEM, Protocol.E_POISON_FLARE,
				{ "status_name": sname, "dmg": before - after, "qi": after, "level": int(e.get("level", 1)) })
			e["ticks_left"] = int(e.get("ticks_left", 0)) - 1
			e["next_online_s"] = float(e.get("next_online_s", 0.0)) + interval
			s.sheet_dirty = true
			if int(e["ticks_left"]) <= 0:
				ch.clear_condition(id)
				host.tell(s, Protocol.CH_SYSTEM, Protocol.E_CONDITION_OFF, { "status_name": sname })
