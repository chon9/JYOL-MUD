class_name RogueLobbyPanel
extends PanelContainer
## 江湖試煉的大廳（ROGUE_PLAN §5.2 LOBBY；WP-UI）：還沒有主機時唯讀顯示試煉者檔案（<資料根目錄>/rogue/profile.json）。
## 永久點數 n / 60、局數、最佳勝場、累計擊敗、首領、名人錄（擊敗過／招募過的名人；沒遇過的顯示「？？？」）、最近 5 局。
## 按鈕「開始試煉」「返回標題」。

signal start_requested
signal title_requested

const UNKNOWN := "？？？"
const RECENT_N := 5
## 名人錄／最近 5 局區塊的高度上限（審查：檔案內容多了之後大廳 694 px 高，訊息列被擠到 720 px 畫面外）；超過就捲動
const LIST_MAX_H := 220.0

var profile: Dictionary = {}
var points_label: Label
var stats_label: Label
var famous_grid: GridContainer
var famous_entries: Array = []    # [{ id, name, known, text }]
var recent_box: VBoxContainer
var start_button: Button
var title_button: Button
var note_label: Label
var list_scroll: ScrollContainer
var points_cap := 0          # 0 = 讀規則表（rogue_rules.points_cap），沒有再用 UiKeys.ROGUE_POINTS_CAP

func _init() -> void:
	add_theme_stylebox_override("panel", UiFrame.style(UiFrame.Kind.JADE))
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(720, 0)
	_build()

func _build() -> void:
	var v := UiBuild.vbox(self, 8)
	var t := UiBuild.label(v, UiKeys.ROGUE_TITLE, 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", UiTheme.JY_GOLD_LIGHT)
	t.add_theme_font_override("font", UiTheme.brush_font(0.5))
	t.add_theme_constant_override("outline_size", 4)
	t.add_theme_color_override("font_outline_color", UiTheme.JY_WOOD_DARK)
	var sub := UiBuild.muted(UiBuild.label(v, "每回合選一張卡：武功、兵器、屬性或隊友，連戰到倒下為止。武功、兵器、隊友每局歸零；永久屬性點留下來，下一局開局時多分配。", 15, true))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_label = UiBuild.muted(UiBuild.label(v, "【設計提案・非原作】永久點數只用在江湖試煉，不影響江湖裡的角色與世界。", 13, true))
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(HSeparator.new())
	points_label = UiBuild.plate(v, "", 20)
	points_label.name = "Points"
	stats_label = UiBuild.label(v, "", 16, true)
	stats_label.name = "Stats"
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_scroll = ScrollContainer.new()
	list_scroll.name = "ListScroll"
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.custom_minimum_size = Vector2(0, LIST_MAX_H)
	v.add_child(list_scroll)
	var cols := UiBuild.hbox(list_scroll, 16)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var left := UiBuild.vbox(cols, 4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiBuild.accent(UiBuild.label(left, "名人錄", 17))
	famous_grid = GridContainer.new()
	famous_grid.name = "Famous"
	famous_grid.columns = 3
	famous_grid.add_theme_constant_override("h_separation", 14)
	left.add_child(famous_grid)
	var right := UiBuild.vbox(cols, 4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiBuild.accent(UiBuild.label(right, "最近 %d 局" % RECENT_N, 17))
	recent_box = UiBuild.vbox(right, 2)
	recent_box.name = "Recent"
	var brow := UiBuild.hbox(v, 16)
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	start_button = UiBuild.button(brow, "開始試煉", func(): start_requested.emit(), 160)
	start_button.name = "Start"
	title_button = UiBuild.button(brow, "返回標題", func(): title_requested.emit(), 160)
	title_button.name = "ToTitle"

# ---------- 試煉者檔案（唯讀） ----------

## 預設檔案（RogueProfile 還沒合併時的後備；欄位同 ROGUE_PLAN §3.9.3）
static func default_profile() -> Dictionary:
	return { "schema": 1, "identity": "", "name": "", "points_total": 0, "runs": 0, "best_wins": 0, "total_wins": 0,
		"foes_beaten": 0, "bosses_beaten": 0, "famous_beaten": {}, "famous_allied": {}, "history": [], "updated": 0 }

static func profile_path(root_dir: String) -> String:
	return root_dir.path_join(UiKeys.ROGUE_PROFILE_REL)

## 讀 <root_dir>/rogue/profile.json；有 RogueProfile（WP-RUN）就用它（含正規化），沒有就自己讀。永不寫檔。
## 上次沒結算的一局（當機、強制關閉時留下的 in_progress）只在記憶體裡先算進去顯示；寫回由主機在開局時做。
static func read_profile(root_dir: String) -> Dictionary:
	const RP := "res://core/rogue/rogue_profile.gd"
	const RR := "res://core/rogue/rogue_rules.gd"
	if ResourceLoader.exists(RP):
		var s: Variant = load(RP)
		if s is GDScript and (s as GDScript).can_instantiate():
			var r: Variant = (s as GDScript).call("read", root_dir)
			if r is Dictionary:
				var ip: Variant = (r as Dictionary).get("in_progress", {})
				if ip is Dictionary and not (ip as Dictionary).is_empty() and ResourceLoader.exists(RR):
					var rules: Variant = (load(RR) as GDScript).call("rules", raw_tables())
					var st: Variant = (s as GDScript).call("settle_pending", r, rules)
					if st is Dictionary and (st as Dictionary).get("profile") is Dictionary:
						r = st["profile"]
				return _merge_defaults(r)
	var path := profile_path(root_dir)
	if not FileAccess.file_exists(path):
		return default_profile()
	var txt := FileAccess.get_file_as_string(path)
	var j := JSON.new()
	if j.parse(txt) != OK:
		return default_profile()   # 壞檔：只顯示預設，不動檔案（備份與修復交給主機端的 RogueProfile）
	var d: Variant = j.data
	return _merge_defaults(d) if d is Dictionary else default_profile()

static func _merge_defaults(d: Dictionary) -> Dictionary:
	var out := default_profile()
	for k in d:
		out[k] = d[k]
	for k in ["points_total", "runs", "best_wins", "total_wins", "foes_beaten", "bosses_beaten"]:
		out[k] = maxi(0, UiBuild.num(out.get(k, 0)))
	for k in ["famous_beaten", "famous_allied"]:
		if not (out[k] is Dictionary):
			out[k] = {}
	if not (out["history"] is Array):
		out["history"] = []
	return out

## 名人錄的名單：rogue_foes 的首領列＋rogue_cards 的稀以上隊友列（名字取 NPC，沒有就取怪物）。
## 大廳時客戶端的生效視圖還沒開 rogue era → 讀 GameData.loader.all_tables（原始資料）。
static func famous_list(tables: Dictionary = {}) -> Array:
	var t := tables if not tables.is_empty() else raw_tables()
	var out: Array = []
	var seen := {}
	var foes: Dictionary = t.get("rogue_foes", {}) if t.get("rogue_foes") is Dictionary else {}
	var ids := foes.keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = foes[id]
		if not bool(r.get("boss", false)):
			continue
		var nm := _person_name(t, str(r.get("npc", "")), str(r.get("monster", "")))
		if seen.has(nm):
			continue
		seen[nm] = true
		out.append({ "name": nm, "foe": str(id), "card": "" })
	var cards: Dictionary = t.get("rogue_cards", {}) if t.get("rogue_cards") is Dictionary else {}
	var cids := cards.keys()
	cids.sort()
	for id in cids:
		var c: Dictionary = cards[id]
		if str(c.get("kind", "")) != "ALLY" or LootUi.rank(c.get("rarity", "COMMON")) < 2:
			continue
		var nm2 := str(c.get("name", "")) if str(c.get("name", "")) != "" else _person_name(t, str(c.get("npc", "")), str(c.get("monster", "")))
		if seen.has(nm2):
			for e in out:
				if e["name"] == nm2 and e["card"] == "":
					e["card"] = str(id)
			continue
		seen[nm2] = true
		out.append({ "name": nm2, "foe": "", "card": str(id) })
	return out

static func _person_name(t: Dictionary, npc: String, monster: String) -> String:
	var npcs: Dictionary = t.get("npcs", {}) if t.get("npcs") is Dictionary else {}
	if npc != "" and npcs.get(npc) is Dictionary:
		return str(npcs[npc].get("name", npc))
	var mons: Dictionary = t.get("monsters", {}) if t.get("monsters") is Dictionary else {}
	if monster != "" and mons.get(monster) is Dictionary:
		return str(mons[monster].get("name", monster))
	return npc if npc != "" else monster

static func raw_tables() -> Dictionary:
	var loop := Engine.get_main_loop() as SceneTree
	var gd: Node = loop.root.get_node_or_null("GameData") if loop != null else null
	if gd == null:
		return {}
	var ld: Variant = gd.get("loader")
	if ld is Object and (ld as Object).get("all_tables") is Dictionary:
		return (ld as Object).get("all_tables")
	var v: Variant = gd.get("tables")
	return v if v is Dictionary else {}

## 永久點數上限：rogue_rules.points_cap（原始資料；大廳時還沒開 rogue era）→ UiKeys 預設
static func rules_points_cap(tables: Dictionary = {}) -> int:
	var t := tables if not tables.is_empty() else raw_tables()
	var rr: Variant = t.get("rogue_rules", {})
	if rr is Dictionary and (rr as Dictionary).get("rg_rules") is Dictionary:
		var n := UiBuild.num((rr["rg_rules"] as Dictionary).get("points_cap", 0))
		if n > 0:
			return n
	return UiKeys.ROGUE_POINTS_CAP

## 歷史一筆的一行文字
static func history_line(h: Dictionary) -> String:
	var cause := str(UiKeys.ROGUE_CAUSE_TEXT.get(str(h.get("cause", "")), ""))
	var t := "勝 %d 場" % UiBuild.num(h.get("wins", 0))
	var b := UiBuild.num(h.get("bosses", 0))
	if b > 0:
		t += "、首領 %d" % b
	if cause != "":
		t += "　" + cause
	t += "　永久點數 +%d" % UiBuild.num(h.get("points", 0))
	var bc: Variant = h.get("best_card", {})
	if bc is Dictionary and str((bc as Dictionary).get("title", "")) != "":
		t += "　最佳：〔%s〕%s" % [RogueCard.rarity_name(str(bc.get("rarity", "COMMON"))), str(bc["title"])]
	return t

func apply_profile(p: Dictionary, tables: Dictionary = {}) -> void:
	profile = _merge_defaults(p)
	points_label.text = "永久點數 %d / %d" % [int(profile["points_total"]), points_cap if points_cap > 0 else rules_points_cap(tables)]
	stats_label.text = "已試煉 %d 局　最佳 %d 勝　累計擊敗 %d 名　首領 %d 位" % [int(profile["runs"]), int(profile["best_wins"]),
		int(profile["foes_beaten"]), int(profile["bosses_beaten"])]
	UiBuild.clear(famous_grid)
	famous_entries = []
	var beaten: Dictionary = profile["famous_beaten"]
	var allied: Dictionary = profile["famous_allied"]
	for f in famous_list(tables):
		var nb := UiBuild.num(beaten.get(f["foe"], 0)) if f["foe"] != "" else 0
		var na := UiBuild.num(allied.get(f["card"], 0)) if f["card"] != "" else 0
		var known := nb > 0 or na > 0
		var parts: PackedStringArray = []
		if nb > 0:
			parts.append("敗 %d" % nb)
		if na > 0:
			parts.append("友 %d" % na)
		var text := ("%s（%s）" % [f["name"], "、".join(parts)]) if known else UNKNOWN
		var l := UiBuild.label(famous_grid, text, 15)
		if not known:
			UiBuild.muted(l)
		famous_entries.append({ "name": f["name"], "known": known, "text": text })
	UiBuild.clear(recent_box)
	var hist: Array = profile["history"]
	if hist.is_empty():
		UiBuild.muted(UiBuild.label(recent_box, "還沒有試煉紀錄。", 15))
	for i in mini(RECENT_N, hist.size()):
		if hist[i] is Dictionary:
			UiBuild.label(recent_box, history_line(hist[i]), 14, true)
