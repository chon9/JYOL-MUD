class_name UiClient
extends RefCounted
## UI 讀取 ClientState／GameData 的唯一入口（M1_PLAN 3.5.4、3.12 UI 規則）。
## 透過 get()／has_signal() 存取，讓 UI 在 ClientState 的 M1 欄位尚未合併時仍能載入（測試用假資料）。

static func _cs() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or not loop.root.has_node("ClientState"):
		return null
	return loop.root.get_node("ClientState")

static func _field(name: String, fallback: Variant) -> Variant:
	var cs := _cs()
	if cs == null:
		return fallback
	var v: Variant = cs.get(name)
	return fallback if v == null else v

static func sheet() -> Dictionary:
	var v: Variant = _field("sheet", {})
	return v if v is Dictionary else {}

static func region_view() -> Dictionary:
	var v: Variant = _field("region_view", {})
	return v if v is Dictionary else {}

static func battle_state() -> Dictionary:
	var v: Variant = _field("battle_state", {})
	return v if v is Dictionary else {}

static func char_list() -> Array:
	var v: Variant = _field("char_list", [])
	return v if v is Array else []

static func my_peer() -> int:
	return int(_field("my_peer_id", 0))

static func in_world() -> bool:
	return bool(_field("in_world", false))

static func world_info() -> Dictionary:
	var v: Variant = _field("world_info", {})
	return v if v is Dictionary else {}

static func identity() -> String:
	return str(_field("identity", ""))

## M2（4.6.9）：ClientState 記下的最近一次 mail_list／server_options；WP-HOST 尚未合併時是空的（UI 另外直接聽事件）
static func mail_list() -> Array:
	var v: Variant = _field("mail_list", [])
	return v if v is Array else []

static func server_options() -> Dictionary:
	var v: Variant = _field("server_options", {})
	return v if v is Dictionary else {}

## 本人是管理員（4.5.1 sheet.is_admin）
static func is_admin() -> bool:
	return bool(sheet().get("is_admin", false))

static func my_char_id() -> String:
	return str(sheet().get("char_id", ""))

## 查看偵察（docs/GDD.md §5.10）：主機的 world_info.scout_enabled；舊主機沒有這個欄位 → false（不送 look 的 scout 參數）
static func scout_enabled() -> bool:
	return world_info().get("scout_enabled", false) == true

## PK 模式（4.7.2 world_info 新增 pk_mode）；舊主機沒有這個欄位 → CLASSIC
static func pk_mode() -> String:
	return str(world_info().get("pk_mode", "CLASSIC"))

# ---------- NetworkManager（M2：重新連線、Steam 大廳） ----------
static func _nm() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or not loop.root.has_node("NetworkManager"):
		return null
	return loop.root.get_node("NetworkManager")

## 上次連線的目標（4.6.9 NetworkManager.last_target）；沒有回 {}
static func last_target() -> Dictionary:
	var nm := _nm()
	if nm == null:
		return {}
	var v: Variant = nm.get("last_target")
	return v if v is Dictionary else {}

static func recent_events(n: int) -> Array:
	var cs := _cs()
	if cs == null:
		return []
	var buf: Variant = cs.get("event_log")
	if buf == null or not buf.has_method("last"):
		return []
	return buf.last(n)

## 連接 ClientState 的訊號；訊號不存在（尚未合併）時略過，回傳是否成功
static func connect_signal(sig: String, cb: Callable) -> bool:
	var cs := _cs()
	if cs == null or not cs.has_signal(sig):
		return false
	if not cs.is_connected(sig, cb):
		cs.connect(sig, cb)
	return true

static func disconnect_signal(sig: String, cb: Callable) -> void:
	var cs := _cs()
	if cs != null and cs.has_signal(sig) and cs.is_connected(sig, cb):
		cs.disconnect(sig, cb)

# ---------- GameData ----------
static func _gd() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or not loop.root.has_node("GameData"):
		return null
	return loop.root.get_node("GameData")

static func tables() -> Dictionary:
	var gd := _gd()
	if gd == null:
		return {}
	var t: Variant = gd.get("tables")
	return t if t is Dictionary else {}

static func table(name: String) -> Dictionary:
	var t: Variant = tables().get(name, {})
	return t if t is Dictionary else {}

static func row(table_name: String, id: String) -> Dictionary:
	var r: Variant = table(table_name).get(id, {})
	return r if r is Dictionary else {}

static func templates() -> Dictionary:
	return table("text_templates")

static func name_of(table_name: String, id: String, fallback: String = "") -> String:
	var r := row(table_name, id)
	return str(r.get("name", fallback if fallback != "" else id))

static func attr_name(id: String) -> String:
	var r := row("attributes", id)
	return str(r.get("name", UiKeys.attr_name(id)))

## 出生城（3.12 char_create）：regions 中 birth_allowed == true 的城市
## M3b（M3B_PLAN §7.10）：只列 world_info 生效 era 的城（客戶端資料表已依 era 過濾，這裡再保險一次）；
## 不是基本 era 的城加資料片名「京城（神鵰大俠）」
static func birth_cities() -> Array:
	var out: Array = []
	var regions := table("regions")
	var eras := table("eras")
	var wi_eras: Variant = world_info().get("enabled_eras", null)
	for id in regions:
		var r: Dictionary = regions[id]
		if not bool(r.get("birth_allowed", false)):
			continue
		var era := str(r.get("era", ""))
		if era != "" and wi_eras is Array and not (wi_eras as Array).is_empty() and not (wi_eras as Array).has(era):
			continue
		var nm := str(r.get("name", id))
		var er: Variant = eras.get(era, null)
		if er is Dictionary and not bool((er as Dictionary).get("base", false)) and str((er as Dictionary).get("name", "")) != "":
			nm += "（%s）" % str(er["name"])
		out.append({ "id": str(id), "name": nm, "seal": str(r.get("name", id)), "era": era })
	out.sort_custom(func(a, b): return a["id"] > b["id"])   # 西夏（xixia）排在大理（dali）前
	return out

## 失敗原因的中文（3.7 查表規則）
## 訊息紀錄用（帶「【系統】」頻道標籤）
static func reason_text(reason: String) -> String:
	return TextRenderer.render_reason(reason, templates(), reason_params(reason))

## 對話框狀態列、清單、地圖頁尾、提示框用（不帶頻道標籤）
static func reason_inline(reason: String) -> String:
	return TextRenderer.render_reason_inline(reason, templates(), reason_params(reason))

## 失敗原因的模板參數：busy 的 {n}（還要幾秒）＝主機在這個結果附上的 left_s；
## 沒有（舊主機）就用角色表 cooldowns 裡最長的剩餘秒數，至少 1
static func reason_params(reason: String) -> Dictionary:
	if reason == "rogue_attr_cap":   # 江湖試煉：單項屬性上限＝主機 rogue_rules.attr_cap（結果附 cap）
		var ex: Variant = _field("last_result_extra", {})
		var cap := int((ex as Dictionary).get("cap", 0)) if ex is Dictionary else 0
		return { "n": cap if cap > 0 else UiKeys.ROGUE_ATTR_CAP }
	if reason != "busy":
		return {}
	var extra: Variant = _field("last_result_extra", {})
	if extra is Dictionary and (extra as Dictionary).has("left_s"):
		return { "n": maxi(1, int((extra as Dictionary)["left_s"])) }
	var n := 1
	var cd: Variant = sheet().get("cooldowns", {})
	if cd is Dictionary:
		for k in cd:
			n = maxi(n, ceili(float(cd[k]) - 1e-6))
	return { "n": n }
