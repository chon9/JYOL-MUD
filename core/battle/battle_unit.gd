class_name BattleUnit
extends RefCounted
## 戰鬥單位（M1_PLAN 3.4.2）。只讀「戰鬥者規格字典」（3.3），不引用 Character。

const CHARGING := "CHARGING"
const READY := "READY"
const ACTING := "ACTING"
const DEAD := "DEAD"
const FLED := "FLED"

var uid: int = 0
var spec: Dictionary = {}
var side: int = 0
var peer: int = 0
var pos: Vector2i = Vector2i(-1, -1)
var qi: int = 0
var neili: int = 0
var jing: int = 0
var shen: int = 0
var gauge: float = 0.0
var rate: float = 0.0
var state: String = CHARGING
var defending: bool = false
var statuses: Dictionary = {}       # status id -> 剩餘行動次數
var status_levels: Dictionary = {}  # status id -> 等級（M3a；中毒等級等，預設 1）
var used_items: Dictionary = {}     # M3a：戰鬥中用掉的堆疊 item_uid -> 數量（暗器、藥；戰後從背包扣）
var formation: Dictionary = {}      # M3a：所在陣法 { art, art_name, members: [uid], atk, def, cost, paid }
var med_taken: int = 0            # 本場戰鬥吃過幾次回復藥（氣血失調／昏迷判定）
var start_statuses: Dictionary = {} # M3a：開戰時從 spec.statuses 帶入的狀態 id -> 等級（戰後對照用）
var cured_statuses: Dictionary = {} # M3a 審查修正：戰鬥中被「治好」（解藥、醫、逼毒、衝穴）的狀態 id -> true；只是行動次數用完的不算
var queued_cmd: Dictionary = {}
var kills: Array = []               # 由此單位最後一擊的怪物 id
var last_hitter: int = 0
var afk: bool = false
var timeouts: int = 0               # 連續逾時次數（10.7 #4）
var detached: bool = false          # 玩家斷線：不再等他下令，一律自動「防」直到戰鬥結束
var escape_ready: bool = false      # coward AI：已在逃跑格上喘過一口氣，下次行動才 FLEE

# 內部欄位（非契約，但其他 battle 類別會用）
var weapon: Dictionary = {}         # 目前手上的兵器（3.3 weapon 形狀）
var killed_by: int = 0
var overflow: float = 0.0           # 同 tick 滿條排序用
var start_pos: Vector2i = Vector2i(-1, -1)
var actions: int = 0                # 已執行的行動數（統計用）

# ---- M3d（M3D_PLAN §3、§9.2；WP-COMBAT） ----
var dmg_dealt := 0                  # 本場打出的總傷害（resolve_strike 命中時累計，含反擊與合體一擊；WP-EVENTS 判定用）
var hits_landed := 0                # 本場命中次數（同上）
var dodging := false                # 「閃」：到自己下次行動前被打中的機率降低（§3.1；execute 開頭與 defending 一起清掉）
var combo_mark: Dictionary = {}     # 合體技：{ group, t（戰鬥秒）, dmg, def_uid }；空＝沒有（§3.3.3）
var combo_hits := 0                 # 本場成功的合體一擊次數（戰後 ComboSystem 給配合度）
var combo_with: Array = []          # 合體成功時的夥伴角色 id（每次一筆）
var last_equip_t := -999.0          # 上一次戰鬥中換裝的戰鬥時間（秒；§3.6）

func _init(p_uid: int = 0, p_spec: Dictionary = {}) -> void:
	uid = p_uid
	spec = p_spec.duplicate(true)
	side = int(spec.get("side", 0))
	peer = int(spec.get("peer", 0))
	qi = int(spec.get("qi", spec.get("qi_max", 1)))
	neili = int(spec.get("neili", 0))
	jing = int(spec.get("jing", spec.get("jing_max", 0)))
	shen = int(spec.get("shen", spec.get("shen_max", 0)))
	var w: Dictionary = spec.get("weapon", {})
	weapon = _norm_weapon(w)
	# M3A_PLAN 5.7：戰鬥開始時 spec.statuses 直接放入單位（帶等級）
	var st: Variant = spec.get("statuses", {})
	if st is Dictionary:
		for sid in st:
			var v: Variant = st[sid]
			var n := 1
			var lv := 1
			if v is Dictionary:
				n = int(v.get("n", 1))
				lv = int(v.get("level", 1))
			elif typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				n = int(v)
			if n >= 1:
				statuses[str(sid)] = n
				status_levels[str(sid)] = maxi(1, lv)
				start_statuses[str(sid)] = maxi(1, lv)

static func _norm_weapon(w: Dictionary) -> Dictionary:
	return {
		"uid": str(w.get("uid", "")),
		"item_id": str(w.get("item_id", "")),
		"weapon_type": str(w.get("weapon_type", "FIST")) if str(w.get("weapon_type", "")) != "" else "FIST",
		"atk": int(w.get("atk", 0)),
		"name": str(w.get("name", "")),
	}

func is_active() -> bool:
	return state != DEAD and state != FLED

func is_ai() -> bool:
	return peer == 0 or str(spec.get("ai", "")) != ""

func can_charge() -> bool:
	return state == CHARGING

func is_dead() -> bool:
	return state == DEAD

func is_fled() -> bool:
	return state == FLED

func unit_name() -> String:
	return str(spec.get("name", ""))

func kind() -> String:
	return str(spec.get("kind", "MONSTER"))

func is_player() -> bool:
	return kind() == "PLAYER"

func attr(id: String) -> int:
	return int(spec.get("attrs", {}).get(id, 0))

func skill(id: String) -> int:
	return int(spec.get("skills", {}).get(id, 0))

func qi_max() -> int:
	return maxi(1, int(spec.get("qi_max", qi)))

func neili_max() -> int:
	return int(spec.get("neili_max", 0))

func jing_max() -> int:
	return int(spec.get("jing_max", jing))

func shen_max() -> int:
	return int(spec.get("shen_max", shen))

func arts() -> Array:
	return spec.get("arts", [])

func weapon_options() -> Array:
	return spec.get("weapon_options", [])

func weapon_type() -> String:
	return str(weapon.get("weapon_type", "FIST"))

func armor_power() -> int:
	return int(spec.get("armor_power", 0))

func effective_inner() -> int:
	return int(spec.get("effective_inner", 0))

func lightness() -> int:
	return int(spec.get("lightness", 0))

func killing_intent() -> int:
	return int(spec.get("killing_intent", 0))

func carry_ratio() -> float:
	return float(spec.get("carry_ratio", 0.0))

func sect_skill() -> Dictionary:
	return spec.get("sect_skill", {})

func ai_kind() -> String:
	var a := str(spec.get("ai", ""))
	return a if a != "" else "melee_basic"

## ---------------------------------------------------------------- M3a 規格欄位（M3A_PLAN 3.11）

func gender() -> String:
	return str(spec.get("gender", ""))

func sect() -> String:
	return str(spec.get("sect", ""))

func party_id() -> String:
	return str(spec.get("party_id", ""))

## cmd_arts[cat]（POISON MEDIC HIDDEN FORMATION INNER ACUPOINT）
func cmd_arts(cat: String) -> Array:
	var d: Variant = spec.get("cmd_arts", {})
	if not (d is Dictionary):
		return []
	var a: Variant = d.get(cat, [])
	return a if a is Array else []

func hidden_items() -> Array:
	var a: Variant = spec.get("hidden_items", [])
	return a if a is Array else []

func battle_items() -> Array:
	var a: Variant = spec.get("battle_items", [])
	return a if a is Array else []

## 堆疊列（hidden_items／battle_items）找 uid；找不到回 {}
static func stack_of(list: Array, item_uid: String) -> Dictionary:
	for it in list:
		if it is Dictionary and str(it.get("uid", "")) == item_uid:
			return it
	return {}

## 這個堆疊在戰鬥中還剩幾個（spec 的 n − 已用掉）
func stack_left(it: Dictionary) -> int:
	if it.is_empty():
		return 0
	return maxi(0, int(it.get("n", 0)) - int(used_items.get(str(it.get("uid", "")), 0)))

## ---------------------------------------------------------------- M3d 規格欄位（WP-COMBAT；Character.to_combatant 帶入）

## 穿著有 FLEE_ANYWHERE 效果的裝備（無敵烙跑鞋，§3.4）
func flee_anywhere() -> bool:
	return bool(spec.get("flee_anywhere", false))

## 合體技規格 { partner_char, moqi }；沒有夥伴回 {}
func combo_spec() -> Dictionary:
	var c: Variant = spec.get("combo", {})
	return c if c is Dictionary else {}

## 角色 id（玩家單位的 spec.ref 就是角色 id；char_id 有給就用它）
func char_id() -> String:
	return str(spec.get("char_id", spec.get("ref", ""))) if is_player() else ""

## 換裝冷卻（毫秒；spec.equip_cd_ms 由 to_combatant 依伺服器選項 equip_cooldown_ms 帶入；缺省 -1＝看 Battle.opts）
func equip_cd_ms() -> int:
	return int(spec.get("equip_cd_ms", -1))

func status_level(id: String) -> int:
	if not statuses.has(id):
		return 0
	return maxi(1, int(status_levels.get(id, 1)))
