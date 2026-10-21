class_name ServerOptionsDialog
extends UiDialog
## 伺服器設定面板（M2_PLAN 4.10、4.7.2；只限管理員）：系統窗「特殊開關」→「伺服器設定」打開。
## - 打開時送 server_opts_get；收到 server_options（ui 事件）後依 editable 清單產生下拉選單（死亡規則、PK 模式、戰鬥等待模式、驛站馬車），
##   選了就送 server_opts_set { key, value }（value 一律字串）；失敗時撥回原值並顯示原因。只影響之後的事件。
## - 玩家名單：踢出、踢出並禁止（都要確認）→ admin_kick { peer, ban }。
## ClientState 尚未合併 server_options 欄位時也能用：直接聽 events_received 的 server_options 事件。
## 故事包（STORY_PLAN §5.5、§6.6）：另一區「江湖事件」放八項（江湖傳聞、傳聞間隔、謠言頻道門檻、惡人夜遊、警告秒數、
## 追擊 NPC、閒聊環境句、NPC 反應）。主機 editable 有這個 key → 和其他項一樣可改（以主機的 label／choices 為準）；
## 沒有（主機還沒開放修改）→ 照 StoryUi.STORY_OPTIONS 顯示目前值並灰掉、附說明。
## M3b（M3B_PLAN §2.3、§4.11、§7.9）：新 4 列（開放 1.0B、監獄位置、丐幫聚會、捉拿公敵）走一般路徑；
## enable_era_1_0b 在世界已開 1.0B 時顯示「已開放」並灰掉，pending_eras 非空（已設定、還沒重開）時顯示「下次開服生效」並灰掉；
## 還沒開時下拉選單第一項是「未開放」（主機的 choices 只有 on）。
## M3c2（M3C2_PLAN §5.3，WP-CARRY）：「允許外來角色」一列（開房時才有意義；單機一律允許）。主機 editable 沒有這個 key，
## 由 intents_host 的 server_opts_set 處理（key allow_foreign_characters、value "true"／"false"）；目前值讀 world_info。
## M3c（M3C_PLAN §9.3，WP-NPCPK）：兩列整數選項「NPC 重生時間」（npc_respawn_pct，10–1000%）與「掉寶倍率」（loot_drop_pct，10–300%）。
## 主機 editable 有這兩個 key → 走一般路徑（可改）；沒有 → 照 M3C_OPTIONS 顯示目前值（預設 100%）並灰掉、附說明。

var info_label: Label
var options_grid: GridContainer
var players_box: VBoxContainer
var confirm_row: HBoxContainer
var confirm_label: Label
var confirm_ok: Button
var opts: Dictionary = {}
var selectors: Dictionary = {}       # key -> OptionButton
var desc_label: Label                # 目前選的規則組合的說明（choices[].desc；舊主機沒有就不顯示）
var story_grid: GridContainer        # 江湖事件八項
var story_note: Label
var story_rows: Dictionary = {}      # key -> OptionButton（含灰掉的）
var _pending_kick: Dictionary = {}   # { peer, ban, name }
const OPTIONS_H := 340.0   # 審查修正：原本 250 只看得到約 6 列，江湖事件八項都在捲動區下方
const PLAYERS_H := 64.0
## M3c 兩個整數選項（§9.3）：key、名稱、可選值（百分比）、說明
const M3C_OPTIONS := [
	{ "key": "npc_respawn_pct", "label": "NPC 重生時間", "values": [10, 25, 50, 100, 200, 300, 500, 1000], "default": 100,
		"desc": "被殺的居民、動物、守衛、惡人多久回來（100% ＝ 類別預設：居民 3 時辰、動物與守衛 1 時辰、惡人 6 時辰）【設計提案】" },
	{ "key": "loot_drop_pct", "label": "掉寶倍率", "values": [10, 25, 50, 100, 150, 200, 300], "default": 100,
		"desc": "頭目與精英掉落表的機率倍率（100% ＝ 預設；不影響一般怪物的既有掉落）【設計提案】" },
]
var m3c_rows: Dictionary = {}        # key -> OptionButton（M3c 兩列，含灰掉的）

func dialog_size() -> Vector2:
	return Vector2(620, 0)

func _ready() -> void:
	super._ready()
	UiClient.connect_signal("events_received", _on_events)

func _exit_tree() -> void:
	UiClient.disconnect_signal("events_received", _on_events)

func _build_body() -> void:
	title_label.text = "伺服器設定"
	info_label = UiBuild.label(body, "", 15, true)
	UiBuild.muted(UiBuild.label(body, "改了只影響之後發生的事（例如之後的死亡、之後開的戰鬥）。", 14, true))
	# 選項放進捲動區：故事包多了「江湖事件」八項，整個面板比 720p 的場景區高（對話框層在 HUD 以上）
	var osc := UiBuild.scroll(body, OPTIONS_H)
	osc.name = "OptionsScroll"
	var ov := UiBuild.vbox(osc, 6)
	ov.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_grid = GridContainer.new()
	options_grid.columns = 2
	options_grid.add_theme_constant_override("h_separation", 12)
	options_grid.add_theme_constant_override("v_separation", 6)
	ov.add_child(options_grid)
	desc_label = UiBuild.muted(UiBuild.label(ov, "", 14, true))
	desc_label.name = "PresetDesc"
	desc_label.visible = false
	ov.add_child(HSeparator.new())
	UiBuild.accent(UiBuild.label(ov, "江湖事件", 16))
	story_grid = GridContainer.new()
	story_grid.name = "StoryOptions"
	story_grid.columns = 2
	story_grid.add_theme_constant_override("h_separation", 12)
	story_grid.add_theme_constant_override("v_separation", 4)
	ov.add_child(story_grid)
	story_note = UiBuild.muted(UiBuild.label(ov, "", 13, true))
	story_note.name = "StoryNote"
	story_note.visible = false
	body.add_child(HSeparator.new())
	UiBuild.accent(UiBuild.label(body, "江湖中的玩家", 16))
	var sc := UiBuild.scroll(body, PLAYERS_H)
	players_box = UiBuild.vbox(sc, 4)
	players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_row = UiBuild.hbox(body, 8)
	confirm_label = UiBuild.label(confirm_row, "", 15, true)
	confirm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_ok = UiBuild.button(confirm_row, "確定", confirm_kick, 80)
	confirm_ok.name = "KickConfirm"
	UiBuild.button(confirm_row, "取消", cancel_kick, 80)
	confirm_row.visible = false

func open_panel() -> void:
	ensure_built()
	status_label.text = ""
	visible = true
	var cached := UiClient.server_options()
	if not cached.is_empty():
		apply_options(cached)
	else:
		info_label.text = "讀取中……"
	send(UiKeys.I_SERVER_OPTS_GET, {})

## o = 4.7.2：{ editable: [ { key, label, value, choices: [ { value, label } ] } ], info: { world_name, host_offline_policy, players: [...] } }
func apply_options(o: Dictionary) -> void:
	ensure_built()
	opts = o
	var info: Dictionary = o.get("info", {}) if o.get("info", {}) is Dictionary else {}
	var policy := "主機離線時江湖凍結" if str(info.get("host_offline_policy", "FROZEN")) == "FROZEN" else str(info.get("host_offline_policy", ""))
	info_label.text = "世界：%s　（%s）" % [str(info.get("world_name", "")), policy]
	UiBuild.clear(options_grid)
	UiBuild.clear(story_grid)
	selectors.clear()
	story_rows.clear()
	var story_keys := StoryUi.story_option_keys()
	var hosted := {}
	for row in o.get("editable", []):
		if not (row is Dictionary):
			continue
		var key := str(row.get("key", ""))
		var grid: GridContainer = story_grid if key in story_keys else options_grid
		if key in story_keys:
			hosted[key] = true
		var row_label := UiBuild.label(grid, str(row.get("label", key)), 15)
		var ob := OptionButton.new()
		ob.name = "Opt_" + key
		ob.custom_minimum_size = Vector2(260, 0)
		var cur := str(row.get("value", ""))
		var i := 0
		for ch in row.get("choices", []):
			if not (ch is Dictionary):
				continue
			ob.add_item(str(ch.get("label", ch.get("value", ""))), i)
			ob.set_item_metadata(i, str(ch.get("value", "")))
			if str(ch.get("desc", "")) != "":
				ob.set_item_tooltip(i, str(ch.get("desc", "")))
			if str(ch.get("value", "")) == cur:
				ob.select(i)
			i += 1
		ob.set_meta("value", cur)
		if key == UiKeys.OPT_ENABLE_1_0B:
			_era_row(row, ob, row_label, o)
		ob.item_selected.connect(func(idx: int): _on_selected(key, ob, idx))
		grid.add_child(ob)
		selectors[key] = ob
		if key in story_keys:
			story_rows[key] = ob
	_add_unhosted_story_options(o, hosted)
	_add_m3c_options(o)
	_add_foreign_option(o)   # M3c2 WP-CARRY
	_add_spar_cap_option(o)   # M3c2 WP-PACE
	_add_m3d_options(o)   # M3d WP-LAW
	_update_desc()
	_build_players(info.get("players", []) if info.get("players", []) is Array else [], bool(info.get("ban_enforced", false)))

## 1.0B 這一列的三種狀態（§2.3）：已開放／下次開服生效／未開放（可選 on）
static func era_state(row: Dictionary, opts_payload: Dictionary = {}) -> String:
	var wi := UiClient.world_info()
	var eras: Variant = wi.get("enabled_eras", [])
	if (eras is Array and (eras as Array).has(UiKeys.ERA_1_0B)) or str(row.get("value", "")) == "opened":
		return "OPENED"
	var pend: Variant = wi.get("pending_eras", (opts_payload.get("info", {}) as Dictionary).get("pending_eras", []) if opts_payload.get("info", {}) is Dictionary else [])
	if row.get("pending", false) == true or (pend is Array and (pend as Array).has(UiKeys.ERA_1_0B)):
		return "PENDING"
	return "CLOSED"

func _era_row(row: Dictionary, ob: OptionButton, l: Label, o: Dictionary) -> void:
	match ServerOptionsDialog.era_state(row, o):
		"OPENED":
			ob.clear()
			ob.add_item(UiKeys.OPT_1_0B_OPENED, 0)
			ob.set_item_metadata(0, str(row.get("value", "")))
			ob.disabled = true
			ob.tooltip_text = "這個世界已經有神鵰大俠（1.0B）的內容；不能關閉（要關請離線編輯 world.json）。"
		"PENDING":
			_mark_era_pending(ob, l)
		_:
			var cur := str(row.get("value", ""))
			var has_cur := false
			for i in ob.item_count:
				if str(ob.get_item_metadata(i)) == cur:
					has_cur = true
			if not has_cur:
				var keep: Array = []
				for i in ob.item_count:
					keep.append([ob.get_item_text(i), ob.get_item_metadata(i), ob.get_item_tooltip(i)])
				ob.clear()
				ob.add_item("未開放", 0)
				ob.set_item_metadata(0, cur)
				for it in keep:
					ob.add_item(str(it[0]), ob.item_count)
					ob.set_item_metadata(ob.item_count - 1, it[1])
					ob.set_item_tooltip(ob.item_count - 1, str(it[2]))
				ob.select(0)
			ob.tooltip_text = "打開京城、丐幫、絕情谷等神鵰大俠內容；只能開、不能關，下次開服生效。"

func _mark_era_pending(ob: OptionButton, l: Label = null) -> void:
	ob.clear()
	ob.add_item(UiKeys.OPT_NEXT_BOOT, 0)
	ob.set_item_metadata(0, "on")
	ob.set_meta("value", "on")
	ob.disabled = true
	ob.tooltip_text = "已設定開放神鵰大俠（1.0B），下次開服生效。"
	if l != null and not l.text.contains(UiKeys.OPT_NEXT_BOOT):
		l.text += "（%s）" % UiKeys.OPT_NEXT_BOOT

## 主機 editable 沒有的江湖事件選項：照本機規格顯示目前值、灰掉。
## # STORY_PLAN 缺漏：§5.5 要伺服器設定面板能改這八項，但 server/admin_system.gd（EDITABLE_KEYS、opts_set）在 §8.2 凍結，
## 主機端要由整合者加上；加了之後這裡自動改走上面的一般路徑（可改）。
func _add_unhosted_story_options(o: Dictionary, hosted: Dictionary) -> void:
	var missing := 0
	for spec in StoryUi.STORY_OPTIONS:
		var key := str(spec["key"])
		if hosted.has(key):
			continue
		missing += 1
		UiBuild.muted(UiBuild.label(story_grid, str(spec["label"]), 15))
		var ob := OptionButton.new()
		ob.name = "Opt_" + key
		ob.custom_minimum_size = Vector2(260, 0)
		var cur := StoryUi.option_value(key, o, UiClient.world_info())
		var i := 0
		for ch in spec["choices"]:
			ob.add_item(str(ch["label"]), i)
			ob.set_item_metadata(i, str(ch["value"]))
			if str(ch["value"]) == cur:
				ob.select(i)
			i += 1
		ob.set_meta("value", cur)
		ob.disabled = true
		ob.tooltip_text = "%s
（這個主機還沒開放在面板上修改；可在 options.json 設定）" % str(spec.get("desc", ""))
		story_grid.add_child(ob)
		story_rows[key] = ob
	story_note.text = "灰色的項目：這個主機還沒開放在面板上修改，顯示的是目前值或預設值。" if missing > 0 else ""
	story_note.visible = missing > 0

## M3c 兩列（§9.3）：主機 editable 已有的走一般路徑（上面的迴圈）；沒有的照本機規格顯示目前值、灰掉。
## M3C_PLAN 缺漏：server/admin_system.gd（EDITABLE_KEYS、choices、opts_set）不在 WP-NPCPK 的檔案內，面板修改要由整合者在主機端開放；
## 開放後這裡自動改走一般路徑。目前值：server_options.info.options[key] → info[key] → world_info[key] → 預設 100
func _add_m3c_options(o: Dictionary) -> void:
	m3c_rows.clear()
	for spec in M3C_OPTIONS:
		var key := str(spec["key"])
		if selectors.has(key):
			m3c_rows[key] = selectors[key]
			continue
		UiBuild.muted(UiBuild.label(options_grid, str(spec["label"]), 15))
		var ob := OptionButton.new()
		ob.name = "Opt_" + key
		ob.custom_minimum_size = Vector2(260, 0)
		var cur := ServerOptionsDialog.m3c_value(key, o, int(spec["default"]))
		var vals: Array = (spec["values"] as Array).duplicate()
		if not (cur in vals):
			vals.append(cur)
			vals.sort()
		for i in vals.size():
			ob.add_item("%d%%" % int(vals[i]), i)
			ob.set_item_metadata(i, str(vals[i]))
			if int(vals[i]) == cur:
				ob.select(i)
		ob.set_meta("value", str(cur))
		ob.disabled = true
		ob.tooltip_text = "%s\n（這個主機還沒開放在面板上修改；可在 options.json 設定 %s）" % [str(spec["desc"]), key]
		options_grid.add_child(ob)
		m3c_rows[key] = ob

static func m3c_value(key: String, o: Dictionary, def: int) -> int:
	var info: Variant = o.get("info", {})
	if info is Dictionary:
		var io2: Variant = (info as Dictionary).get("options", {})
		if io2 is Dictionary and (io2 as Dictionary).has(key):
			return int((io2 as Dictionary)[key])
		if (info as Dictionary).has(key):
			return int((info as Dictionary)[key])
	var wi := UiClient.world_info()
	if wi.has(key):
		return int(wi[key])
	return def

## ban_enforced == false（ENet／區網）：身分是對方自己的設定檔，封鎖擋不住人，不提供「踢出並禁止」
func _build_players(players: Array, ban_enforced := false) -> void:
	UiBuild.clear(players_box)
	var me := UiClient.my_peer()
	for p in players:
		if not (p is Dictionary):
			continue
		var row := UiBuild.hbox(players_box, 8)
		# 角色名（遊戲裡看到的名字）為主，設定檔／Steam 名稱放括號裡（M2 審查：只列設定檔名稱時對不上卷軸上的人）
		var t := UiSocial.admin_player_label(p)
		var l := UiBuild.label(row, t, 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var peer := int(p.get("peer", 0))
		if peer == me or peer <= 0:
			continue
		var name := str(p.get("char_name", "")) if str(p.get("char_name", "")) != "" else str(p.get("name", "?"))
		UiBuild.button(row, "踢出", func(): ask_kick(peer, false, name), 70)
		if ban_enforced:
			UiBuild.button(row, "踢出並禁止", func(): ask_kick(peer, true, name), 110)
	if players_box.get_child_count() == 0:
		UiBuild.muted(UiBuild.label(players_box, "（沒有玩家）", 15))
	elif not ban_enforced:
		UiBuild.muted(UiBuild.label(players_box, "區網連線無法確認對方身分，「禁止再進來」只在 Steam 連線時提供。", 13, true))

## 規則組合下拉選單目前那一項的說明
func _update_desc() -> void:
	var ob: OptionButton = selectors.get("rule_preset", null)
	var t := ""
	if ob != null and ob.selected >= 0:
		t = ob.get_item_tooltip(ob.selected)
	desc_label.text = t
	desc_label.visible = t != ""

## 送出新值；成功才記成目前值，失敗撥回舊值並顯示原因
func _on_selected(key: String, ob: OptionButton, idx: int) -> void:
	var value := str(ob.get_item_metadata(idx))
	var old := str(ob.get_meta("value", ""))
	if value == old:
		return
	status_label.text = ""
	_update_desc()
	_gate().send(UiKeys.I_SERVER_OPTS_SET, { "key": key, "value": value }, [ob], func(ok: bool, reason: String):
		if not is_instance_valid(ob):
			return
		if ok:
			ob.set_meta("value", value)
			if key == UiKeys.OPT_ENABLE_1_0B:
				_mark_era_pending(ob)
		else:
			_select_meta(ob, old)
		if is_instance_valid(self):
			_update_desc()
		if not ok:
			if is_instance_valid(self):
				status_label.text = UiClient.reason_inline(reason))

static func _select_meta(ob: OptionButton, want: String) -> void:
	for i in ob.item_count:
		if str(ob.get_item_metadata(i)) == want:
			ob.select(i)
			return

func select_value(key: String, value: String) -> void:
	var ob: OptionButton = selectors.get(key, null)
	if ob == null:
		return
	for i in ob.item_count:
		if str(ob.get_item_metadata(i)) == value:
			ob.select(i)
			_on_selected(key, ob, i)
			return

func ask_kick(peer: int, ban: bool, name: String) -> void:
	_pending_kick = { "peer": peer, "ban": ban, "name": name }
	confirm_label.text = ("確定要把「%s」請出江湖，並且禁止他再進來？" if ban else "確定要把「%s」請出江湖？（之後還可以再加入）") % name
	confirm_row.visible = true

func cancel_kick() -> void:
	_pending_kick = {}
	confirm_row.visible = false

func confirm_kick() -> void:
	if _pending_kick.is_empty():
		return
	var args := { "peer": int(_pending_kick["peer"]) }
	if bool(_pending_kick["ban"]):
		args["ban"] = true
	cancel_kick()
	send(UiKeys.I_ADMIN_KICK, args, [], func(): send(UiKeys.I_SERVER_OPTS_GET, {}))

func _on_events(batch: Array) -> void:
	for e in batch:
		if e is Dictionary and str(e.get("key", "")) == UiKeys.E_SERVER_OPTIONS:
			var p: Variant = e.get("p", {})
			if p is Dictionary:
				apply_options(p)

# ==== M3c2 WP-CARRY ====
const FOREIGN_KEY := "allow_foreign_characters"
const FOREIGN_LABEL := "允許外來角色"
var foreign_row: OptionButton = null   # 本面板自己加的那一列（不放進 selectors：那是主機 editable 的清單）
const FOREIGN_DESC := "朋友可以把別的世界的角色匯入這個世界（數值會截到合法範圍；神兵看本世界登記）。單機遊玩一律允許。"

## 主機 editable 已有這個 key → 走一般路徑；沒有 → 本面板自己加一列（開／關），送 server_opts_set
func _add_foreign_option(o: Dictionary) -> void:
	foreign_row = null
	if selectors.has(FOREIGN_KEY):
		foreign_row = selectors[FOREIGN_KEY]
		return
	var on := ServerOptionsDialog.foreign_value(o)
	UiBuild.label(options_grid, FOREIGN_LABEL, 15)
	var ob := OptionButton.new()
	ob.name = "Opt_" + FOREIGN_KEY
	ob.custom_minimum_size = Vector2(260, 0)
	ob.add_item("開", 0)
	ob.set_item_metadata(0, "true")
	ob.add_item("關", 1)
	ob.set_item_metadata(1, "false")
	ob.select(0 if on else 1)
	ob.set_meta("value", "true" if on else "false")
	ob.tooltip_text = FOREIGN_DESC
	ob.item_selected.connect(func(idx: int): _on_selected(FOREIGN_KEY, ob, idx))
	options_grid.add_child(ob)
	foreign_row = ob

## 目前值：server_options.info.options → info → world_info.allow_foreign_characters → false
static func foreign_value(o: Dictionary) -> bool:
	var info: Variant = o.get("info", {})
	if info is Dictionary:
		var io2: Variant = (info as Dictionary).get("options", {})
		if io2 is Dictionary and (io2 as Dictionary).has(FOREIGN_KEY):
			return (io2 as Dictionary)[FOREIGN_KEY] == true
		if (info as Dictionary).has(FOREIGN_KEY):
			return (info as Dictionary)[FOREIGN_KEY] == true
	return UiClient.world_info().get(FOREIGN_KEY, false) == true

# ==== M3c2 WP-PACE ====
## M3C2_PLAN §8.3：「每日切磋獎勵」一列（spar_daily_cap，0–200 場）。主機 editable 有這個 key → 走一般路徑（上面的迴圈）；
## 沒有 → 照本機規格顯示目前值並灰掉、附說明（M3C2_PLAN 缺漏：主機端可改清單在 server/admin_system.gd，不在 WP-PACE 的檔案內）。
const SPAR_CAP_KEY := "spar_daily_cap"
const SPAR_CAP_VALUES := [0, 5, 10, 20, 30, 50, 100, 200]
const SPAR_CAP_DESC := "每個遊戲日前幾場切磋給實戰與學點（學點只給新手）；0 ＝ 切磋沒有獎勵【設計提案】"

func _add_spar_cap_option(o: Dictionary) -> void:
	if selectors.has(SPAR_CAP_KEY):
		return
	UiBuild.muted(UiBuild.label(options_grid, "每日切磋獎勵", 15))
	var ob := OptionButton.new()
	ob.name = "Opt_" + SPAR_CAP_KEY
	ob.custom_minimum_size = Vector2(260, 0)
	var cur := ServerOptionsDialog.m3c_value(SPAR_CAP_KEY, o, 30)
	var vals: Array = SPAR_CAP_VALUES.duplicate()
	if not (cur in vals):
		vals.append(cur)
		vals.sort()
	for i in vals.size():
		ob.add_item("%d 場" % int(vals[i]), i)
		ob.set_item_metadata(i, str(vals[i]))
		if int(vals[i]) == cur:
			ob.select(i)
	ob.set_meta("value", str(cur))
	ob.disabled = true
	ob.tooltip_text = "%s\n（這個主機還沒開放在面板上修改；可在 options.json 設定 %s）" % [SPAR_CAP_DESC, SPAR_CAP_KEY]
	options_grid.add_child(ob)

# ==== M3d WP-LAW ====
## M3D_PLAN §8.3：五個 M3d 伺服器選項（懸賞、賞金獵人、換裝間隔、劫鏢、比武）。主機 editable 有這個 key → 走一般路徑
## （上面的迴圈）；沒有 → 照本機規格顯示目前值並灰掉、附說明。
## M3D_PLAN 缺漏：主機端可改清單（server/admin_system.gd 的 EDITABLE_KEYS、choices、opts_set）不在任何 M3d WP 的檔案內，
## 要由整合者加上；加了之後這裡自動改走一般路徑（可改）。
const M3D_OPTIONS := [
	{ "key": "bounty_enabled", "label": "衙門懸賞", "kind": "bool", "default": true,
		"desc": "佈告欄的懸賞名單、賞金獵人執照與領賞。關掉時佈告欄只寫「衙門暫停懸賞」，NPC 賞金獵人也不出現。" },
	{ "key": "bounty_hunters", "label": "賞金獵人追捕", "kind": "bool", "default": true,
		"desc": "懸賞名單上的人走在野外，會被 NPC 賞金獵人追上（先警告、倒數內離開房間就能甩掉）。" },
	{ "key": "equip_cooldown_ms", "label": "換裝間隔", "kind": "ms", "default": 2000, "values": [0, 1000, 2000, 3000, 5000],
		"desc": "兩次換裝之間至少要隔多久（原作 2001-10-09 起兩秒）；0 ＝ 不限制。" },
	{ "key": "jiebiao_enabled", "label": "危險鏢與劫鏢", "kind": "bool", "default": true,
		"desc": "鏢局二掌櫃的危險鏢（押金、成功拿雙倍）與玩家劫鏢（1.0B）。" },
	{ "key": "tourney_enabled", "label": "門派比武與武林大會", "kind": "bool", "default": true,
		"desc": "依遊戲日曆排程的比武大會，主機也可以隨時開辦。" },
]
var m3d_rows: Dictionary = {}   # key -> OptionButton（主機 editable 的那一列，或本面板加的灰色列）

func _add_m3d_options(o: Dictionary) -> void:
	m3d_rows.clear()
	for spec in M3D_OPTIONS:
		var key := str(spec["key"])
		if selectors.has(key):
			m3d_rows[key] = selectors[key]
			continue
		UiBuild.muted(UiBuild.label(options_grid, str(spec["label"]), 15))
		var ob := OptionButton.new()
		ob.name = "Opt_" + key
		ob.custom_minimum_size = Vector2(260, 0)
		var cur: Variant = ServerOptionsDialog.m3d_value(key, o, spec["default"])
		if str(spec["kind"]) == "bool":
			ob.add_item("開", 0)
			ob.set_item_metadata(0, "true")
			ob.add_item("關", 1)
			ob.set_item_metadata(1, "false")
			ob.select(0 if cur == true else 1)
			ob.set_meta("value", "true" if cur == true else "false")
		else:
			var vals: Array = (spec["values"] as Array).duplicate()
			if not (int(cur) in vals):
				vals.append(int(cur))
				vals.sort()
			for i in vals.size():
				ob.add_item("不限制" if int(vals[i]) == 0 else "%.1f 秒" % (int(vals[i]) / 1000.0), i)
				ob.set_item_metadata(i, str(vals[i]))
				if int(vals[i]) == int(cur):
					ob.select(i)
			ob.set_meta("value", str(int(cur)))
		ob.disabled = true
		ob.tooltip_text = "%s\n（這個主機還沒開放在面板上修改；可在 options.json 設定 %s）" % [str(spec["desc"]), key]
		options_grid.add_child(ob)
		m3d_rows[key] = ob

## 目前值：server_options.info.options → info → world_info → 預設
static func m3d_value(key: String, o: Dictionary, def: Variant) -> Variant:
	var info: Variant = o.get("info", {})
	if info is Dictionary:
		var io2: Variant = (info as Dictionary).get("options", {})
		if io2 is Dictionary and (io2 as Dictionary).has(key):
			return (io2 as Dictionary)[key]
		if (info as Dictionary).has(key):
			return (info as Dictionary)[key]
	var wi := UiClient.world_info()
	if wi.has(key):
		return wi[key]
	return def
