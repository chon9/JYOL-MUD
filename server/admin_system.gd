class_name AdminSystem
extends RefCounted
## 管理員（M2_PLAN 4.2 server_opts_get／server_opts_set／admin_kick、4.6.8、4.7.2）。
## 管理員 = Session.is_admin（本機主機玩家，或 identity ∈ options.admin_identities）。

const EDITABLE_KEYS := ["rule_preset", "pk_mode", "wait_mode", "stagecoach_enabled", "scout_enabled", "sect_hostile_entry",
	# M3B_PLAN §2.3、§4.11
	"enable_era_1_0b", "jail_location", "gb_assembly", "seize_enabled",
	# M3C_PLAN §9.3（整合者：WP-NPCPK 的面板列需要主機開放）
	"npc_respawn_pct", "loot_drop_pct"]
const LABELS := {
	"rule_preset": "死亡規則", "pk_mode": "PK 模式", "wait_mode": "戰鬥等待模式", "stagecoach_enabled": "驛站馬車（非原作）",
	"scout_enabled": "查看偵察（非原作）", "sect_hostile_entry": "門派敵對入山",
	"enable_era_1_0b": "開放神鵰大俠（1.0B）內容", "jail_location": "監獄位置", "gb_assembly": "丐幫聚會",
	"seize_enabled": "捉拿公敵",
	"npc_respawn_pct": "NPC 重生時間", "loot_drop_pct": "掉寶倍率",
}
## M3c 兩個百分比選項（M3C_PLAN §9.3；值與面板 ServerOptionsDialog.M3C_OPTIONS 相同）
const PCT_CHOICES := {
	"npc_respawn_pct": [10, 25, 50, 100, 200, 300, 500, 1000],
	"loot_drop_pct": [10, 25, 50, 100, 150, 200, 300],
}
const PCT_DESC := {
	"npc_respawn_pct": "被殺的居民、動物、守衛、惡人多久回來（100% ＝ 類別預設）【設計提案】",
	"loot_drop_pct": "頭目與精英掉落表的機率倍率（100% ＝ 預設；不影響一般怪物的既有掉落）【設計提案】",
}
# ---- M3b（M3B_PLAN §2.3、§4.11） ----
const ERA_1_0B := "1.0B"
## enable_era_1_0b 的狀態值：off（可開）／on（要開；只在 off 時能選）／pending（已排定下次開服）／enabled（已開放）
const ERA_STATE_LABELS := { "off": "未開放", "on": "開放（下次開服生效）", "pending": "下次開服生效", "enabled": "已開放" }
const ERA_DESC := "打開後下次開服才生效（京城、丐幫、絕情谷、工匠等 1.0B 內容）；只能開、不能關。要關請在關服後編輯 world.json 的 enabled_eras"
const JAIL_LOCATION_LABELS := { "AUTO": "自動（被捉拿的公敵關京城監獄，違反門規仍關各派思過處）", "SECT": "各派思過處", "CAPITAL": "京城監獄（違規與公敵都關京城）【設計提案】" }
const JAIL_LOCATION_DESC := "京城監獄：被抓的公敵一律關京城監獄；違反門規仍要本派有執法者才坐牢（否則禁止學武）。出獄送到京城衙門"
const ASSEMBLY_LABELS := { "DAILY": "每日辰時（設計提案）", "MONTHLY": "每月初一辰時（原作）" }
const ASSEMBLY_DESC := "丐幫升袋在聚會時生效。原作每月一日聚會；主機離線時世界凍結，預設改成每日辰時"
const SEIZE_DESC := "1.0B：門派弟子可捉拿本派公敵（可組隊；抓的人不加 PK 值、殺氣、善惡），被抓的公敵關進監獄"
const HOSTILE_DESC := "公敵或不合門派要求的人走進山門，會被守山弟子攻擊；關掉則各派山門任何人都能自由進出"
## 下拉選項的說明（滑鼠提示）
const SCOUT_DESC := "在野外按「查看」可以找附近的怪物，自己決定迎戰或離開（冷卻 6 秒）；關掉則只能走動踩地雷"
const PK_MODE_LABELS := { "CLASSIC": "懷舊（叫戰＋強制 PK）", "CHALLENGE_ONLY": "只能叫戰", "OFF": "禁止 PK" }
const ONOFF := [{ "value": "true", "label": "開" }, { "value": "false", "label": "關" }]
const KICK_REASON := "admin"

var host: GameHost

func _init(p_host: GameHost) -> void:
	host = p_host

# ---------- 讀取 ----------
func current_preset() -> String:
	var rp: Variant = host.ws.world.get("rule_profile", {})
	if rp is Dictionary and str(rp.get("preset", "")) != "":
		return str(rp["preset"])
	var orp: Variant = host.options.get("rule_profile", {})
	return str(orp.get("preset", "classic_standard")) if orp is Dictionary else "classic_standard"

func current_value(key: String) -> String:
	match key:
		"rule_preset":
			return current_preset()
		"pk_mode":
			return str(host.options.get("pk_mode", "CLASSIC"))
		"wait_mode":
			return "true" if bool(host.options.get("wait_mode", true)) else "false"
		"stagecoach_enabled":
			return "true" if host.options.get("stagecoach_enabled", false) == true else "false"
		"scout_enabled":
			return "false" if host.options.get("scout_enabled", true) == false else "true"
		"sect_hostile_entry":
			return "false" if host.options.get("sect_hostile_entry", true) == false else "true"
		"enable_era_1_0b":
			return era_1_0b_state()
		"jail_location":
			var jl := str(host.options.get("jail_location", "AUTO"))
			return jl if jl in JAIL_LOCATION_LABELS else "AUTO"
		"gb_assembly":
			return "MONTHLY" if str(host.options.get("gb_assembly", "DAILY")) == "MONTHLY" else "DAILY"
		"seize_enabled":
			return "false" if host.options.get("seize_enabled", true) == false else "true"
		"npc_respawn_pct", "loot_drop_pct":
			return str(int(host.options.get(key, 100)))
	return ""

## 1.0B 的狀態：enabled（世界已開）／pending（options.pending_eras 有 1.0B）／off
func era_1_0b_state() -> String:
	var eras: Variant = host.ws.world.get("enabled_eras", [])
	if eras is Array and ERA_1_0B in eras:
		return "enabled"
	var pend: Variant = host.options.get("pending_eras", [])
	if pend is Array and ERA_1_0B in pend:
		return "pending"
	return "off"

## 規則組合的說明（伺服器設定面板在下拉選單下方顯示目前選的那一組；M2 審查：「後期官方」與預設的屍體時間其實一樣，
## 面板卻沒說，改了看不出差別）
const DEATH_DESC := {
	"STRICT_2001": "死亡：全部武功降一級、全部物品留在屍體上",
	"STANDARD": "死亡：實戰 500 以下不受影響，否則最高的特殊武功降一級、只掉裝備",
	"CASUAL": "死亡：不降級，只掉一成銀兩",
}
const CORPSE_DESC := {
	"CLASSIC_30": "屍體：前 10 分鐘只有本人和授權者能翻，之後 20 分鐘誰都能翻，30 分鐘消失",
	"LATER_10": "屍體：10 分鐘保護後誰都能翻；原作沒寫何時消失，暫用 30 分鐘【設計提案】（目前和懷舊的屍體時間相同）",
}

## 違反門規的後果（M3A_PLAN D10、§6.3）
const VIOLATION_DESC := {
	"JAIL": "違反門規：押入思過處 1 遊戲日（2001-11 以後的官方規則；沒有執法者的門派改成禁止學武）",
	"EXPEL": "違反門規：立即逐出門派（2001-08 以前）",
	"BAN": "違反門規：禁止學武 1 遊戲日",
}

static func preset_desc(rules: Dictionary) -> String:
	var parts: PackedStringArray = []
	parts.append(str(DEATH_DESC.get(str(rules.get("death_rule", "")), "")))
	parts.append(str(CORPSE_DESC.get(str(rules.get("corpse_window", "")), "")))
	parts.append(str(VIOLATION_DESC.get(str(rules.get("sect_violation_mode", "JAIL")), "")))
	if str(rules.get("sect_violation_mode", "JAIL")) == "JAIL" and rules.get("jail_enabled", true) == false:
		parts.append("（本組合關閉思過處：違反門規一律改成禁止學武）")
	if bool(rules.get("betrayal_halves_basics", false)):
		parts.append("叛派：全部武功與基本武學減半、門派技能歸零，成為該派公敵")
	else:
		parts.append("叛派：本門武功減半、門派技能歸零，成為該派公敵")
	if rules.get("later_battle_cmds", true) == false:
		parts.append("戰鬥指令「內」「穴」關閉（原作 2002 年才有）")
	return "
".join(Array(parts).filter(func(t): return str(t) != ""))

func choices(key: String) -> Array:
	match key:
		"rule_preset":
			var out: Array = []
			var profiles: Dictionary = GameData.loader.all_tables.get("rule_profiles", {})
			var ids: Array = profiles.keys()
			ids.sort()
			# classic_standard（預設）放第一個，其餘照 id 排序
			if "classic_standard" in ids:
				ids.erase("classic_standard")
				ids.push_front("classic_standard")
			for id in ids:
				var rules: Dictionary = profiles[id].get("rules", {}) if profiles[id].get("rules", {}) is Dictionary else {}
				out.append({ "value": str(id), "label": str(profiles[id].get("name", id)), "desc": preset_desc(rules) })
			return out
		"pk_mode":
			var out2: Array = []
			for m in Protocol.PK_MODES:
				out2.append({ "value": m, "label": PK_MODE_LABELS.get(m, m) })
			return out2
		"wait_mode", "stagecoach_enabled":
			return ONOFF.duplicate(true)
		"sect_hostile_entry":
			var oh: Array = ONOFF.duplicate(true)
			for c in oh:
				c["desc"] = HOSTILE_DESC
			return oh
		"scout_enabled":
			var oo: Array = ONOFF.duplicate(true)
			for c in oo:
				c["desc"] = SCOUT_DESC
			return oo
		"enable_era_1_0b":
			var st := era_1_0b_state()
			if st == "off":
				return [{ "value": "off", "label": ERA_STATE_LABELS["off"], "desc": ERA_DESC },
					{ "value": "on", "label": ERA_STATE_LABELS["on"], "desc": ERA_DESC }]
			return [{ "value": st, "label": ERA_STATE_LABELS[st], "desc": ERA_DESC }]
		"jail_location":
			var jo: Array = []
			for v in ["AUTO", "SECT", "CAPITAL"]:
				jo.append({ "value": v, "label": JAIL_LOCATION_LABELS[v], "desc": JAIL_LOCATION_DESC })
			return jo
		"gb_assembly":
			return [{ "value": "DAILY", "label": ASSEMBLY_LABELS["DAILY"], "desc": ASSEMBLY_DESC },
				{ "value": "MONTHLY", "label": ASSEMBLY_LABELS["MONTHLY"], "desc": ASSEMBLY_DESC }]
		"seize_enabled":
			var so: Array = ONOFF.duplicate(true)
			for c in so:
				c["desc"] = SEIZE_DESC
			return so
		"npc_respawn_pct", "loot_drop_pct":
			var po: Array = []
			var vals: Array = (PCT_CHOICES[key] as Array).duplicate()
			var cur := int(host.options.get(key, 100))
			if not (cur in vals):   # --opts 或手改 options.json 的值也列出來
				vals.append(cur)
				vals.sort()
			for v in vals:
				po.append({ "value": str(v), "label": "%d%%" % v, "desc": PCT_DESC[key] })
			return po
	return []

func choice_label(key: String, value: String) -> String:
	for c in choices(key):
		if str(c["value"]) == value:
			return str(c["label"])
	return value

## 4.7.2 server_options 事件的 payload
func snapshot() -> Dictionary:
	var editable: Array = []
	for key in EDITABLE_KEYS:
		var row := { "key": key, "label": LABELS[key], "value": current_value(key), "choices": choices(key) }
		if key == "enable_era_1_0b":
			row["locked"] = era_1_0b_state() != "off"   # 已開放／已排定：灰掉不能改（M3B_PLAN §2.3）
		editable.append(row)
	var players: Array = []
	var list: Array = host.sessions()
	list.sort_custom(func(a, b): return a.peer_id < b.peer_id)
	for s in list:
		players.append({
			"peer": s.peer_id, "name": s.display_name, "identity_short": s.identity_short(), "is_admin": s.is_admin,
			"char_name": str(s.character.name) if s.character != null else "",
		})
	return {
		"editable": editable,
		"info": {
			"world_name": str(host.ws.world.get("world_name", "")),
			"host_offline_policy": str(host.options.get("host_offline_policy", "FROZEN")),
			"players": players,
			# 封鎖只在 Steam 有效：ENet 的身分是客戶端自己的 local_<uuid>，換個設定檔就進得來（TECH_ARCH：ENet 無防冒名）。
			# 面板在 false 時不提供「踢出並禁止」（M2 第三輪審查）
			"ban_enforced": ban_enforced(),
		},
	}

## 封鎖是否真的擋得住：只有 Steam 主機的身分是 Steam 驗證過的 SteamID
static func ban_enforced() -> bool:
	return NetworkManager.mode == NetworkManager.Mode.STEAM_HOST

# ---------- intent ----------
func opts_get(s: Session) -> Dictionary:
	if not host.is_admin(s):
		return GameHost.fail("not_admin")
	send_options(s)
	return GameHost.ok()

func send_options(s: Session) -> void:
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_SERVER_OPTIONS, snapshot(), true)

## not_admin → bad_option → bad_value:value → 套用、存 options.json 與 world.json → 廣播
func opts_set(s: Session, key: String, value: String) -> Dictionary:
	if not host.is_admin(s):
		return GameHost.fail("not_admin")
	if not (key in EDITABLE_KEYS):
		return GameHost.fail("bad_option")
	var ok_values: Array = []
	for c in choices(key):
		ok_values.append(str(c["value"]))
	if not (value in ok_values):
		return GameHost.fail("bad_value:value")
	# M3B_PLAN §2.3：1.0B 只能開、不能關；只有 off → on 這一步可以做
	if key == "enable_era_1_0b" and (era_1_0b_state() != "off" or value != "on"):
		return GameHost.fail("bad_value:value")
	var shown := choice_label(key, value)
	match key:
		"rule_preset":
			var rp: Dictionary = host.ws.world.get("rule_profile", {}) if host.ws.world.get("rule_profile") is Dictionary else {}
			var overrides: Variant = rp.get("overrides", {})
			var new_rp := { "preset": value, "overrides": (overrides as Dictionary).duplicate(true) if overrides is Dictionary else {} }
			host.ws.world["rule_profile"] = new_rp
			host.ws.options["rule_profile"] = new_rp.duplicate(true)
			# 只影響之後的事件（TECH_ARCH 5.6）：已在進行中的戰鬥結算時才讀 rules
			GameData.activate(host.ws.world.get("enabled_eras", ["1.0A"]), new_rp)
		"pk_mode":
			host.ws.options["pk_mode"] = value
		"wait_mode":
			host.ws.options["wait_mode"] = value == "true"   # 只影響之後開的戰鬥（battle_opts 開戰時讀）
		"stagecoach_enabled":
			host.ws.options["stagecoach_enabled"] = value == "true"
			for o in host.sessions():
				o.view_dirty = true   # 驛站選單會變
		"scout_enabled":
			host.ws.options["scout_enabled"] = value == "true"   # 關掉時現有的提示由 ScoutSystem.tick 收回；冷卻跟著角色表歸零
		"sect_hostile_entry":
			host.ws.options["sect_hostile_entry"] = value == "true"   # 只影響之後走進山門的人
		"enable_era_1_0b":
			# 下次開服生效（O2）：pending_eras = 目前的 enabled_eras ＋ 1.0B；不在執行中重建索引
			var cur: Array = (host.ws.world.get("enabled_eras", ["1.0A"]) as Array).duplicate() \
				if host.ws.world.get("enabled_eras") is Array else ["1.0A"]
			if not (ERA_1_0B in cur):
				cur.append(ERA_1_0B)
			var bad := DataLoader.validate_enabled_eras(GameData.loader.all_tables.get("eras", {}), cur)
			if not bad.is_empty():
				return GameHost.fail("bad_value:value")
			host.ws.options["pending_eras"] = cur
			shown = ERA_STATE_LABELS["pending"]
		"jail_location":
			host.ws.options["jail_location"] = value   # 只影響之後押進去的人；已在牢裡的照舊
		"gb_assembly":
			host.ws.options["gb_assembly"] = value
		"seize_enabled":
			host.ws.options["seize_enabled"] = value == "true"
		"npc_respawn_pct", "loot_drop_pct":
			host.ws.options[key] = int(value)   # 只影響之後倒下的 NPC／之後的掉落
	SaveManager.save_options(host.ws.world_id, host.ws.options)
	host.ws.save_now()
	host.ws.broadcast_event(Protocol.CH_SYSTEM, Protocol.E_SERVER_OPTION_CHANGED,
		{ "label": str(LABELS[key]), "value": shown, "key": key })
	host.ws.broadcast_event(Protocol.CH_SYSTEM, Protocol.E_WORLD_INFO_CHANGED, { "world_info": host.ws.world_info() }, true)
	for o in host.sessions():
		o.sheet_dirty = true
	send_options(s)
	return GameHost.ok()

## not_admin → bad_target（自己或沒有此 peer）→ ban → NetworkManager.kick → 其他人 player_kicked
func kick(s: Session, peer: int, ban: bool) -> Dictionary:
	if not host.is_admin(s):
		return GameHost.fail("not_admin")
	var target: Session = host.session_for_peer(peer)
	if target == null or target == s or target.peer_id == s.peer_id or target.is_local:
		return GameHost.fail("bad_target")
	var name := str(target.character.name) if target.character != null else target.display_name
	if ban:
		var known: Dictionary = host.ws.world.get_or_add("known_identities", {})
		var entry: Dictionary = known.get(target.identity, {})
		entry["banned"] = true
		if not entry.has("last_name"):
			entry["last_name"] = target.display_name
		known[target.identity] = entry
	NetworkManager.kick(peer, KICK_REASON)
	# 不等 0.5 秒後的斷線：立刻移除 session（存角色、離開房間、戰鬥照斷線處理），被踢者之後送來的 intent 一律丟棄
	host.ws.remove_session(peer)
	for o in host.sessions():
		if o.peer_id != peer:
			host.ws.queue_event(o.peer_id, Protocol.CH_SYSTEM, Protocol.E_PLAYER_KICKED, { "name": name, "peer": peer })
	host.ws.save_now()
	if host.is_admin(s):
		send_options(s)   # 面板上的名單立刻更新
	return GameHost.ok()
