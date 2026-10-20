extends Node
## 真實介面驗收（UI playthrough）：只透過畫面上的按鈕／輸入框操作，不碰 WorldServer／NetworkManager。
## 執行（headless 斷言）：
##   godot --headless --path . -- --no-steam --offline --world=ui_play --profile=uibot --debug-intents \
##         --bot=res://tests/ui/ui_playthrough.gd --time-scale=2 --quit-after=900
## 截圖（需要視窗）：再加 --ui-shots=<資料夾>（拿掉 --headless）。
## 成功印 UI_PLAY_OK（結束碼 0）；失敗印 UI_PLAY_FAIL step=<n> <原因> 與可見 UI 樹（結束碼 2）；逾時由 --quit-after 以 1 結束。
##
## 流程：除錯畫面「進入江湖」→ 角色選擇（同名舊角色用「刪除」+ 輸入名稱確認刪掉）→ 創角（打字、選項、擲骰、+ 分配、建立）
## → 主畫面（原作版面：右緣燈籠、底部 HUD、左上聊天浮層）：找武介山看任務（對話框開著時點燈籠「屬性」）、
##   北走客棧找店小二開鋪子（原作購物車：點貨品放進待買 → 確定交易）
## → 武館學基本內功（請教清單的原因不帶【系統】）→ 修煉內力（F1 熱鍵，冷卻中灰色倒數）
## → 燈籠開關 屬性／武功／裝備（含快捷鍵與 Esc；武功按自修 ×1、裝備卸下再裝上：結果要顯示在視窗底部的回饋列）、
##   指令窗（Ctrl+4）→ 雜項 → 任務、系統窗、大地圖（含江湖全圖分頁）、聊天框 Esc 放開焦點後 M 開地圖
## → 驛站送信（原作 2001：驛站只管送信，沒有馬車）：小地圖點擊趕路、接任務（進行中不給交付鈕、沒有「驛站」坐車選項）、
##   一路走到大理（西夏東門→荒草坡→小溪→沙丘→大漠邊緣→綠洲→河川古道→過石橋→大理北門；踩地雷遇敵就打，氣血不足就到客棧／綠洲住宿）、
##   大地圖頁尾回到說明、大理驛站交付（清單即時更新）
## → 查看偵察（docs/GDD.md §5.10【設計提案・非原作】）：安全的房間按「查看」只印描述、沒有冷卻；
##   大理郊外按熱鍵列「查看」→ 視窗「你發現附近有：…」、按鈕變「查看（N 秒）」→「離開」關掉；冷卻完按 F3 → 「迎戰」→ 戰鬥畫面
## → 戰鬥只用指令列（防、休、攻＋點目標格、移＋點格子）打到結束；四種指令還沒用齊就在大理郊外來回走到遇敵為止。
## 關鍵斷言：戰鬥中每次輪到玩家，指令列必須在 TURN_TIMEOUT_S 秒內變成可按（抓「蓄勢中……」卡死），
## 戰報也不能出現「你遲遲沒有出手」（代表介面沒讓玩家下令、被主機逾時自動防守）；Ctrl+1 不會變成「移」；
## 戰敗結果不顯示「+0」。對話框開著時點面板：對話框關掉；聊天框打字後 Esc 放開焦點、M 能開地圖。
## M3a（M3A_PLAN 10.4）：戰鬥畫面一定有 毒 醫 暗 陣 內 穴 六個新按鈕；主機以 --debug-intents 啟動時，查看偵察之前用 debug_set
##   給角色恆山心法（內）、基本醫術（醫）、基本毒術＋放毒法（毒）——這是設定，不是受測物——之後的戰鬥要真的從指令列按
##   「內」→ 小選單「運功療傷」、「醫」→ 點自己的綠框格、「毒」→ 點相鄰敵人的紅框格各一次並被接受（截圖 m3a_*）。
##   沒有 --debug-intents 時只印警告、略過這段（舊的執行指令照樣能跑）。
## 故事包（STORY_PLAN §6、§9.2）：雲兒小姐的煩惱（q_yuner，選李台安那條 test_plan）——民房找雲兒 →「任務」→「詳談」
##   → 任務對話視窗（逐字顯示用空白鍵跳過、合成的「（繼續）」、編號選項）接下任務 → 任務窗（Ctrl+6）有章節、任務名、目前階段與目標；
##   走到藥鋪、城北山坡交談（有目前目標的 NPC 直接開對話）、回民房替雲兒做決定 → 任務窗「已完成」分頁顯示結局名
##   → 系統窗「江湖傳聞」頁列出這件事（全服第一位完成的傳聞；同一個世界重跑時是之前那一則）。

## M3b（M3B_PLAN §7、§11.4）：只在 --debug-intents 時跑；世界沒開 1.0B（舊的 1.0A 世界）時丐幫袋位／乞討印警告略過。
##   叛出少林 → 丐幫破廟找陳長老拜師 → 選單「袋位」頁 → 屬性窗門派欄「袋位：無袋弟子」→ 京城廣場對王大娘「乞討」
##   → 西夏錢莊：選單「錢莊」→ 錢莊窗存 50 兩、存一件物品（已用 n／1000 件）→ 西夏鏢局：選單「鏢局」→ 托鏢／取貨／保鏢三頁
##   → 西夏打鐵舖：指令窗「製作」→ 製作窗（設施、配方、缺料原因）→ 西夏衙門書吏：選單「組織」→ 創立（輸入名字）
##   → 指令窗「組織」→ 組織面板（連署中）。截圖 m3b_*。設定用 debug_set（不是受測物）：善惡、名聲、銀兩、生活技能 1 級、teleport。

const UiDriver := preload("res://tests/ui/ui_driver.gd")

const CHAR_NAME := "介面俠客"
const BIRTH_CITY := "西夏"
const SCENE_NET_DEBUG := "res://ui/debug/net_debug.tscn"
const SCENE_CHAR_SELECT := "res://ui/game/char/char_select.tscn"
const SCENE_CHAR_CREATE := "res://ui/game/char/char_create.tscn"
const SCENE_MAIN := "res://ui/game/main/main_screen.tscn"
const PANELS := ["屬性", "武功", "裝備"]   # 燈籠（武功 Ctrl+1、屬性 Ctrl+2、裝備 Ctrl+3）；任務在指令窗的雜項分頁
const TURN_TIMEOUT_S := 8.0          # 戰鬥開始／上一個指令被接受後，指令列必須在這麼多秒內可按
const BATTLE_TIMEOUT_S := 150.0
const MAX_WILD_MOVES := 400
const MAX_BATTLES := 10
const LETTER_DEST := "dl_station"
const MAX_GOTO_ATTEMPTS := 8
const TIMEOUT_TEXT := "你遲遲沒有出手"
const CMD_TEXTS := ["移", "攻", "武", "防", "休", "裝", "逃"]
const FLEE_FROM := ["m_wolf", "m_boar", "m_bandit"]   # 同 tools/balance_sim.gd：新手一遇到就往逃跑格跑
const M3A_BUTTONS := ["毒", "醫", "暗", "陣", "內", "穴"]   # M3A_PLAN 7.1：戰鬥指令列的新按鈕
const M3A_CMDS := ["內", "醫", "毒"]                         # 要真的按一次的（10.4）
## debug_set 設定（不是受測物）：內＝恆山心法（INNER 類）、醫＝基本醫術、毒＝基本毒術＋放毒法
const M3A_SETUP := [["skill:hg_xinfa", 5], ["skill:basic_medic", 5], ["skill:basic_poison", 5], ["skill:xh_fangdu", 5]]

var ui: UiDriver
var step := 0
var _done := false
var used_cmds: Dictionary = {}       # "攻" -> 次數
var battles := 0
var turns_total := 0
var allow_script_errors := false
var shot_move_hl := false            # 戰鬥截圖：每次執行只拍第一次
var shot_strike := false
var shot_atk_hl := false
var shot_inner_full := false         # M3a 審查：滿血時「運功療傷」灰掉附「氣血已滿」
var shot_badge := false              # M3a 審查：下毒之後敵人頭上的狀態圓牌
var victories := 0
var auto_returned := 0               # 戰鬥結束後自動返回（AUTO_RETURN_S）的場數
var route_rooms: Array = []          # 送信路上經過的房間 id
var last_click := ""                 # 最近一次點格子（指令沒被接受時印出來）
var flee_move := false               # 這次「移」是往逃跑格走
var m3a_ready := false               # M3a 設定成功（--debug-intents）：戰鬥要用到 內 醫 毒
var pelt_total: Dictionary = {}      # 會腐壞的原料 id -> 目前件數（看 sheet）
var pelt_gains: Dictionary = {}      # 會腐壞的原料 id -> 件數增加過幾次（＝幾場戰鬥掉過）
const MAX_PELT_BATTLES := 14         # 物品堆疊：為了湊到「兩場戰鬥都掉皮」最多再打幾場

func _ready() -> void:
	SceneRouter.exit_code = 1
	ui = UiDriver.new(get_tree())
	var args := CliArgs.current()
	if args.get("ui-shots") is String:
		ui.shots_dir = str(args["ui-shots"])
	if args.has("ui-verbose"):
		ui.verbose = true
	allow_script_errors = args.has("ui-allow-script-errors")
	print("[UiPlay] ready headless=%s shots=%s" % [str(ui.is_headless()), ui.shots_dir])
	ClientState.sheet_changed.connect(_track_pelts)
	SceneRouter.about_to_quit.connect(_on_about_to_quit)
	_run.call_deferred()

## 審查修正：任何結束路徑都印最後一行（--quit-after 逾時、關視窗、別的地方叫 quit）；還沒有結論就以 0 結束 → 改成失敗
func _on_about_to_quit(code: int) -> void:
	if _done:
		return
	_done = true
	print("UI_PLAY_FAIL step=%d quit without a verdict (requested exit %d)" % [step, code])
	if code == 0:
		SceneRouter.quit_override = 2

# ---------- 基礎 ----------
func _step(n: int, title: String) -> void:
	step = n
	print("[UiPlay] step %d: %s" % [n, title])

func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	if ui.last_error != "" and not msg.contains(ui.last_error):
		msg += " | driver: " + ui.last_error
	print("UI_PLAY_FAIL step=%d %s" % [step, msg])
	ui.detach()
	ui.print_dump("failure at step %d" % step)
	SceneRouter.exit_code = 2
	get_tree().create_timer(0.3, true, false, true).timeout.connect(func(): SceneRouter.quit(2))

func _ok() -> void:
	if _done:
		return
	_done = true
	ui.detach()
	print("UI_PLAY_OK battles=%d turns=%d cmds=%s warnings=%d engine_errors=%d shots=%d" % [battles, turns_total,
		str(used_cmds), ui.warnings.size(), ui.engine_errors.size(), ui.shots.size()])
	for s in ui.shots:
		print("[UiPlay] screenshot " + s)
	SceneRouter.exit_code = 0
	get_tree().create_timer(0.3, true, false, true).timeout.connect(func(): SceneRouter.quit(0))

## 斷言；失敗時記錄並回 false
## 這一步有沒有新的 SCRIPT ERROR／ERROR（UI 腳本壞掉常常只印錯誤、畫面照跑）；--ui-allow-script-errors 時只記警告
func _check_engine_errors() -> bool:
	var errs := ui.new_engine_errors()
	if errs.is_empty():
		return true
	if allow_script_errors:
		for e in errs:
			ui.warn("engine " + e)
		return true
	_fail("%d engine error(s) during this step, first: %s" % [errs.size(), errs[0]])
	return false

## 按鈕鈕面上實際畫出來的字（JyButton 畫 glyph＋冷卻倒數，不是 Button.text）
static func _face(b: Button) -> String:
	return (b as JyButton).visible_text() if b is JyButton else b.text

func _check(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond

func _run() -> void:
	var steps: Array[Callable] = [_enter_world, _char_select, _char_create, _main_ready, _npc_quest, _npc_shop,
		_inner_and_meditate, _panels, _m2_social, _story_quest, _letter_quest, _m3a_setup, _scout, _go_wild_and_fight, _pelts_one_slot, _villain_prompt_ui, _m3a_sect_screens, _m3b_screens, _m3c_screens, _m3c2_screens]
	for s in steps:
		if _done:
			return
		var ok: bool = await s.call()
		if not ok:
			_fail("step returned false")
			return
		if not _check_engine_errors():
			return
	if not _done:
		_ok()

# ---------- 1. 除錯畫面 → 角色選擇 ----------
func _enter_world() -> bool:
	_step(1, "net_debug -> 進入江湖")
	if not _check(await ui.wait_scene(SCENE_NET_DEBUG, 15.0), "net_debug scene not shown (scene=%s)" % ui.scene_path()):
		return false
	await ui.shot("net_debug")
	if not await ui.click_text("進入江湖", "exact", null, 15.0):
		return false
	return _check(await ui.wait_scene(SCENE_CHAR_SELECT, 10.0), "char_select not shown")

# ---------- 2. 角色選擇（刪掉同名舊角色）→ 建立新角色 ----------
func _char_select() -> bool:
	_step(2, "char_select")
	await ui.seconds(0.5)   # 等 char_list 回來
	var row_label := ui.find_label(CHAR_NAME, "prefix")
	if row_label != null:
		print("[UiPlay] deleting old character via UI")
		var del := ui.find_button("刪除", "exact", row_label.get_parent().get_parent())   # CharInfo → CharInfoBox → 列
		if not await ui.click(del):
			return false
		var edit := ui.find(func(c): return c is LineEdit and (c as LineEdit).placeholder_text.contains("輸入角色名稱")) as LineEdit
		if not await ui.type_text(edit, CHAR_NAME):
			return false
		await ui.shot("delete_confirm")
		if not await ui.click_text("確定刪除"):
			return false
		if not _check(await ui.wait_until(func(): return ui.find_label(CHAR_NAME, "prefix") == null, 5.0),
				"old character still listed after delete"):
			return false
	await ui.shot("char_select")
	if not await ui.click_text("建立新角色"):
		return false
	return _check(await ui.wait_scene(SCENE_CHAR_CREATE, 5.0), "char_create not shown")

# ---------- 3. 創角 ----------
func _char_create() -> bool:
	_step(3, "char_create")
	await ui.frames(2)
	var name_edit := ui.find(func(c): return c is LineEdit) as LineEdit
	if not await ui.type_text(name_edit, CHAR_NAME):
		return false
	var opts: Array = ui.find_all(func(c): return c is OptionButton)
	if not _check(opts.size() >= 3, "expected 3 OptionButtons (性別/月份/城市), got %d" % opts.size()):
		return false
	# M3c（M3C_PLAN §3.4、§12.4）：造型選擇器（右半邊，預設分頁）——女性 9 格（截圖）→ 切回男性重設為 0 → 點第 4 格
	if not await _look_picker_create(opts[0]):
		return false
	if not await ui.select_option(opts[1], "3 月"):
		return false
	if not await ui.select_option(opts[2], BIRTH_CITY, "contains"):
		return false
	var create_btn := ui.find_button("建立")
	if not _check(create_btn != null and create_btn.disabled, "建立 should be disabled before rolling"):
		return false
	# 擲骰：臂力那列的「擲骰」欄（標籤的下一個兄弟）由 — 變成數字
	var str_label := ui.find(func(c): return c is Label and (c as Label).text == "臂力" and c.get_parent() is GridContainer) as Label
	if not _check(str_label != null, "attribute row 臂力 not found"):
		return false
	var roll_label := ui.sibling(str_label, 1) as Label
	if not await ui.click_text("擲骰"):
		return false
	if not _check(await ui.wait_until(func(): return roll_label.text.is_valid_int(), 5.0), "roll did not fill attributes (臂力=%s)" % roll_label.text):
		return false
	await ui.click_text("擲骰")   # 再擲一次（可無限重擲）
	await ui.seconds(0.2)
	var plus := ui.sibling(str_label, 4) as Button
	if not _check(plus != null and plus.text == "+", "臂力 + button not found"):
		return false
	for i in 5:
		if not await ui.click(plus):
			return false
	if not _check(ui.find_label("剩餘點數：0") != null, "free points not fully allocated"):
		return false
	if not _check(not create_btn.disabled, "建立 still disabled after name + roll + allocation"):
		return false
	await ui.shot("char_create")
	if not await ui.click(create_btn):
		return false
	return _check(await ui.wait_scene(SCENE_MAIN, 10.0), "main screen not shown after 建立 (status: %s)" % _status_text())

## 創角畫面的造型選擇器：受測物是格子數、名稱依性別換、切性別重設、點格子選中、建立後 sheet.look
const CREATE_LOOK := 4   # 少年俠客
func _look_picker_create(gender_opt: OptionButton) -> bool:
	var picker := ui.find_by_class("LookPicker")
	if not _check(picker != null, "char_create: no LookPicker"):
		return false
	var cc: Node = null   # 創角畫面沒有自己的 class_name：在整個畫面找「造型：」字樣
	if not _check(picker.get_global_rect().size.x >= 600.0, "look picker too narrow: %s" % str(picker.get_global_rect())):
		return false
	if not await ui.select_option(gender_opt, "女"):
		return false
	await ui.frames(2)
	var cells: Array = picker.get("cells")
	if not _check(cells.size() == 9 and str(cells[1].get("art")) == "look_f01" and str(cells[1].get("look_name")) == "俠女",
			"female picker cells: %s" % str(cells.map(func(c): return str(c.get("look_name"))))):
		return false
	if not await ui.click(cells[7]):
		return false
	await ui.frames(2)
	if not _check(int(picker.get("selected")) == 7, "click on 醫女 did not select it (selected %d)" % int(picker.get("selected"))):
		return false
	await ui.shot("m3c_create_picker_female")
	if not await ui.select_option(gender_opt, "男"):
		return false
	await ui.frames(2)
	cells = picker.get("cells")
	if not _check(int(picker.get("selected")) == 0 and str(cells[CREATE_LOOK].get("art")) == "look_m%02d" % CREATE_LOOK,
			"gender switch did not reset the look (selected %d, cell art %s)" % [int(picker.get("selected")), str(cells[CREATE_LOOK].get("art"))]):
		return false
	if not await ui.click(cells[CREATE_LOOK]):
		return false
	var want_name := str(Looks.NAMES_M[CREATE_LOOK])
	if not _check(await ui.wait_until(func(): return int(picker.get("selected")) == CREATE_LOOK and ui.find_label(want_name, "contains", cc) != null, 2.0),
			"look %d (%s) not selected/shown" % [CREATE_LOOK, want_name]):
		return false
	await ui.shot("m3c_create_picker")
	return true

func _status_text() -> String:
	var l := ui.find(func(c): return c is Label and (c as Label).text != "" and (c as Label).has_theme_color_override("font_color") and (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF) as Label
	return l.text if l != null else ""

# ---------- 4. 主畫面 ----------
func _scene_panel() -> Control:
	return ui.find_by_class("ScenePanel")

func _room_name() -> String:
	var sp := _scene_panel()
	if sp == null:
		return ""
	var rl: Variant = sp.get("room_label")
	return (rl as Label).text if rl is Label else ""

func _region_text() -> String:
	var sp := _scene_panel()
	if sp == null:
		return ""
	var rl: Variant = sp.get("region_label")
	return (rl as Label).text if rl is Label else ""

func _exits_box() -> Control:
	return ui.row_of_label("出口", "HFlowContainer", _scene_panel())

func _npcs_box() -> Control:
	return ui.row_of_label("人物", "HFlowContainer", _scene_panel())

func _battle() -> Control:
	return ui.find_by_class("BattleScreen")

func _main_ready() -> bool:
	_step(4, "main screen")
	if not _check(await ui.wait_until(func(): return _room_name() != "", 10.0), "room name never shown"):
		return false
	print("[UiPlay] in room %s (%s)" % [_room_name(), _region_text()])
	await ui.shot("main_screen")
	if not _check(_exits_box() != null and ui.find_buttons("：", "contains", _exits_box()).size() > 0, "no exit buttons"):
		return false
	# 主畫面常駐小地圖（「沒有大地圖」）
	var mm := _mini_map()
	if not _check(mm != null, "mini map not on the main screen"):
		return false
	var mv: Variant = mm.get("view")
	if not _check(mv != null and str(mv.get("current")) != "" and (mv as Control).size.y >= 120.0,
			"mini map empty or too small: %s" % ui.describe(mm)):
		return false
	# M3c：創角選的造型（look 4 少年俠客）在角色表（sheet.look／appearance）
	return _check(await ui.wait_until(func(): return str(UiClient.sheet().get("look", "")) == "look_m%02d" % CREATE_LOOK 		and UiBuild.num(UiClient.sheet().get("appearance", -1)) == CREATE_LOOK, 3.0),
		"created look not in sheet: look=%s appearance=%s" % [str(UiClient.sheet().get("look", "")), str(UiClient.sheet().get("appearance", ""))])

func _mini_map() -> Control:
	return ui.find_by_class("MiniMap")

func _room_id() -> String:
	return str(UiClient.region_view().get("room", ""))

func _vital(k: String) -> int:
	return UiBuild.num((UiClient.sheet().get("vitals", {}) as Dictionary).get(k, 0))

# ---------- 走路（照原作：城市之間用走的，沿路踩地雷） ----------
## 步行路線圖（客戶端資料表；era 關掉的出口載入時就拿掉了）：room -> [[to, dir]]
func _graph() -> Dictionary:
	var g := {}
	var maps: Dictionary = UiClient.tables().get("maps", {})
	for rid in maps:
		for room in (maps[rid] as Dictionary).get("rooms", []):
			var edges: Array = []
			for ex in room.get("exits", []):
				edges.append([str(ex.get("to", "")), str(ex.get("dir", ""))])
			g[str(room.get("id", ""))] = edges
	return g

## BFS：回傳方向代碼陣列（["E", "S", …]）；走不到回 null
func _path(from: String, to: String) -> Variant:
	if from == to:
		return []
	var g := _graph()
	var prev := { from: null }
	var q: Array = [from]
	while not q.is_empty():
		var cur: String = q.pop_front()
		for e in g.get(cur, []):
			var nxt: String = e[0]
			if prev.has(nxt):
				continue
			prev[nxt] = [cur, e[1]]
			if nxt == to:
				var out: Array = []
				var c := to
				while prev[c] != null:
					out.push_front(prev[c][1])
					c = prev[c][0]
				return out
			q.append(nxt)
	return null

## 走到 room：每一步按出口鈕；遇敵就用指令列打完；死了（重生在別處）或走錯就重新規劃。heal：氣不足一半先去住宿
func _goto(room: String, heal := true) -> bool:
	for attempt in MAX_GOTO_ATTEMPTS:
		if _done:
			return false
		if _battle() != null and not await _fight():
			return false
		if _room_id() == room:
			return true
		var path: Variant = _path(_room_id(), room)
		if not _check(path != null, "no walking path %s -> %s" % [_room_id(), room]):
			return false
		var g := _graph()
		for dir in path:
			if _done:
				return false
			if _battle() != null and not await _fight():
				return false
			var cur := _room_id()
			var expect := ""
			for e in g.get(cur, []):
				if e[1] == dir:
					expect = e[0]
			if expect == "":
				break   # 已經不在原路線上：重新規劃
			if heal and not await _ensure_healthy():
				return false
			if _room_id() != cur:
				break   # 去住宿了：重新規劃
			if not await _walk(UiKeys.dir_label(dir)):
				return false
			# 踩地雷：戰鬥畫面可能比房間更新晚一點出現
			await ui.wait_until(func(): return _battle() != null, 0.15)
			if _battle() != null and not await _fight():
				return false
			if not (_room_id() in route_rooms):
				route_rooms.append(_room_id())
			if _room_id() != expect:
				break
		if _room_id() == room:
			return true
	return _check(false, "could not reach %s (at %s)" % [room, _room_id()])

## 氣不到六成（或精太低）：走到最近的客棧／茶棚／綠洲，用 NPC 對話框「住宿」；錢不夠就原地等自然回復。
## 路過休息點時氣不到九成也順便住一晚（同 balance_sim p0_walk：每到休息點就回滿；死後重生只有一半氣，不能直接上路）
func _ensure_healthy() -> bool:
	var npcs: Dictionary = UiClient.tables().get("npcs", {})
	var inns := {}
	for nid in npcs:
		if "INN" in (npcs[nid] as Dictionary).get("services", []):
			inns[str(npcs[nid].get("room", ""))] = nid
	var at_inn := inns.has(_room_id()) and _vital("qi") * 10 < _vital("qi_max") * 9
	if not at_inn and _vital("qi") * 10 >= _vital("qi_max") * 6 and _vital("jing") >= 10:
		return true
	var best := ""
	var best_len := 1 << 30
	for r in inns:
		var p: Variant = _path(_room_id(), r)
		if p != null and (p as Array).size() < best_len:
			best_len = (p as Array).size()
			best = r
	var money := UiBuild.num(UiClient.sheet().get("money", 0))
	if best != "" and money >= UiBuild.num(npcs[inns[best]].get("inn_price", 0)):
		print("[UiPlay] qi %d/%d: rest at %s" % [_vital("qi"), _vital("qi_max"), best])
		if not await _goto(best, false):
			return false
		var dlg := await _talk(str(npcs[inns[best]].get("name", "")))
		if dlg == null:
			return false
		if not await ui.click_text("住宿", "prefix", dlg):
			return false
		await ui.wait_until(func(): return _vital("qi") * 10 >= _vital("qi_max") * 9, 3.0)
		await ui.shot("inn_rest")
		if not await _close_dialog(dlg):
			return false
		return true
	ui.warn("qi %d/%d and no affordable inn: waiting" % [_vital("qi"), _vital("qi_max")])
	await ui.wait_until(func(): return _vital("qi") * 10 >= _vital("qi_max") * 6, 60.0)
	return true

## 按某方向（"北" "東"…）的出口，等房名改變或戰鬥開始
func _walk(dir_label: String) -> bool:
	var box := _exits_box()
	var b := ui.find_button(dir_label + "：", "prefix", box, true)
	if b == null:
		return _check(false, "no enabled exit '%s' in %s" % [dir_label, _room_name()])
	var before := _room_id()
	if not await ui.click(b):
		# 整合修正：按下與放開之間場景卷軸剛好重建（新的房間 view 到了），出口鈕被換掉 → 不是介面壞掉。
		# 已經移動或開打就算成功；否則重新找同一個出口再按一次
		if _room_id() != before or _battle() != null:
			ui.last_error = ""
			return true
		if ui.last_error != "" and not ui.last_error.contains("freed"):
			return false
		ui.warn("exit button '%s' was rebuilt during the click: retrying" % dir_label)
		ui.last_error = ""
		await ui.frames(2)
		b = ui.find_button(dir_label + "：", "prefix", _exits_box(), true)
		if b == null:
			return _check(false, "no enabled exit '%s' in %s after a rebuild" % [dir_label, _room_name()])
		if not await ui.click(b):
			return false
	var moved := await ui.wait_until(func(): return _room_id() != before or _battle() != null, 5.0)
	if not moved:
		ui.warn("walk %s from %s: room did not change" % [dir_label, before])
	return true

## 找人物按鈕（名字開頭）→ 等 NPC 對話框
func _talk(npc_name: String) -> Control:
	if not await ui.click_text(npc_name, "prefix", _npcs_box()):
		return null
	var opened := func() -> bool:
		var d := ui.find_by_class("NpcDialog")
		return d != null and ui.find_label(npc_name, "exact", d) != null
	if not await ui.wait_until(opened, 5.0):
		_fail("NPC dialog for %s did not open" % npc_name)
		return null
	return ui.find_by_class("NpcDialog")

func _close_dialog(dlg: Control) -> bool:
	var close := ui.find_button("關閉", "exact", dlg)
	if not await ui.click(close):
		return false
	return _check(await ui.wait_until(func(): return not dlg.is_visible_in_tree(), 3.0), "%s did not close" % ui.describe(dlg))

func _npc_quest() -> bool:
	_step(5, "talk 武介山 -> 任務")
	var dlg := await _talk("武介山")
	if dlg == null:
		return false
	if not await ui.click_text("任務", "prefix", dlg):
		return false
	await ui.frames(2)
	var accept := ui.find_button("接受", "exact", dlg, true)
	if accept != null:
		if not await ui.click(accept):
			return false
		await ui.wait_until(func(): return ui.find_label("進行中", "contains", dlg) != null, 3.0)
	await ui.shot("npc_quest")
	# 進行中（東西還沒湊齊）的任務不給「交付」鈕（按了只會得到錯誤）
	if ui.find_label("進行中", "contains", dlg) != null and not _check(ui.find_button("交付", "exact", dlg) == null,
			"ACTIVE quest shows a 交付 button"):
		return false
	# 對話框開著時點「屬性」：對話框要關掉，面板不能被壓在對話框下面；Esc 關面板
	if not await ui.click_text("屬性(", "prefix"):
		return false
	if not _check(await ui.wait_until(func(): return _panel_open("屬性"), 3.0), "屬性 did not open while a dialog was up"):
		return false
	if not _check(not dlg.is_visible_in_tree(), "NPC dialog still open on top of the 屬性 panel"):
		return false
	await ui.shot("panel_over_dialog")
	await ui.press_key(KEY_ESCAPE)
	return _check(await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0), "Esc did not close the panel")

func _npc_shop() -> bool:
	_step(6, "客棧 店小二 -> 交易")
	if not await _walk("北"):
		return false
	var dlg := await _talk("店小二")
	if dlg == null:
		return false
	if not await ui.click_text("交易", "prefix", dlg):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_by_class("ShopDialog") != null, 5.0), "shop dialog did not open"):
		return false
	var shop := ui.find_by_class("ShopDialog")
	if not _check(ui.find_label("的鋪子", "contains", shop) != null, "shop title missing"):
		return false
	# 原作購物車：點商店貨品放進「待買」→ 總價牌更新 → 按「確定交易」才送出 buy
	var money_before := _shop_money(shop)
	var good: Button = null
	var sg: Variant = shop.get("shop_grid")
	if sg is Control:
		good = ui.find(func(c): return c is Button and not (c as Button).disabled and (c as Button).text.contains("兩"), sg) as Button
	if not _check(good != null, "no goods in the shop grid"):
		return false
	print("[UiPlay] shop: put %s in the cart" % good.text.get_slice("
", 0))
	if not await ui.click(good):
		return false
	var total: Variant = shop.get("total_label")
	if not _check(await ui.wait_until(func(): return total is Label and (total as Label).text.to_int() > 0, 3.0),
			"cart total did not update after clicking a good"):
		return false
	await ui.shot("shop_cart")
	if not await ui.click(ui.find_button("確定交易", "exact", shop, true)):
		return false
	if not _check(await ui.wait_until(func(): return _shop_money(shop) < money_before, 5.0),
			"money did not drop after 確定交易 (%d -> %d)" % [money_before, _shop_money(shop)]):
		return false
	print("[UiPlay] shop money %d -> %d" % [money_before, _shop_money(shop)])
	await ui.shot("shop")
	# 身上的裝備（木刀、布衣）在「我的物品」要標「已裝備」（紅框＋名稱），避免新手把唯一的兵器賣掉
	if not await ui.click(ui.find_button("賣", "exact", shop)):
		return false
	var eq := ui.find_button(ShopDialog.EQUIPPED_MARK, "contains", shop)
	if not _check(eq != null and bool(eq.get("marked")), "equipped items not marked in the sell list"):
		return false
	if not await _close_dialog(shop):
		return false
	return await _walk("南")

func _shop_money(shop: Control) -> int:
	var l := ui.find_label("身上銀兩：", "prefix", shop)
	return l.text.get_slice("：", 1).to_int() if l != null else -1

# ---------- 4b. 驛站送信（坐車、交付、地圖頁尾、小地圖趕路） ----------
func _dialog_text(dlg: Control) -> String:
	var parts: PackedStringArray = []
	for c in ui.find_all(func(x): return x is Label, dlg):
		parts.append((c as Label).text)
	return " | ".join(parts)

func _map_footer() -> String:
	var mp := ui.find_by_class("MapPanel", null, false)
	var l: Variant = mp.get("status_label") if mp != null else null
	return (l as Label).text if l is Label else ""

func _mini_status() -> String:
	var mm := _mini_map()
	var l: Variant = mm.get("status_label") if mm != null else null
	return (l as Label).text if l is Label else ""

## 小地圖上點某間房（房間方框中心）
func _click_mini_room(room_id: String) -> bool:
	var mm := _mini_map()
	var v: Variant = mm.get("view") if mm != null else null
	if not _check(v != null, "mini map view missing"):
		return false
	var rects: Dictionary = v.get("_rects")
	if not _check(rects.has(room_id), "mini map has no room %s" % room_id):
		return false
	var at: Vector2 = (v.call("screen_rect", room_id) as Rect2).get_center()
	if not _check(Rect2(Vector2.ZERO, (v as Control).size).has_point(at), "room %s is outside the mini map (%s, view %s)" % [room_id, str(at), str((v as Control).size)]):
		return false
	await ui.click_local(v, at)
	return true

func _letter_quest() -> bool:
	_step(10, "驛站送信：接信")
	if not await _walk("南"):
		return false
	if not _check(_room_name() == "西夏驛站", "expected 西夏驛站, at %s" % _room_name()):
		return false
	# 小地圖：點到過的廣場 → 自動走過去（小地圖頁尾顯示已抵達），再走回來
	if not await _click_mini_room("xx_square"):
		return false
	if not _check(await ui.wait_until(func(): return _room_name() == "西夏廣場" and _mini_status() == "已抵達。", 6.0),
			"mini map walk failed (room %s, status「%s」)" % [_room_name(), _mini_status()]):
		return false
	await ui.shot("mini_map_walked")
	if not await _walk("南"):
		return false
	var dlg := await _talk("驛站管事")
	if dlg == null:
		return false
	# 原作 2001：驛站只管送信。馬車是伺服器選項（預設關），選單上不能有「驛站」坐車
	if not _check(ui.find_button("驛站", "prefix", dlg) == null, "carriage entry shown although stagecoach is off: %s" % _dialog_text(dlg)):
		return false
	if not await ui.click_text("任務", "exact", dlg):
		return false
	if not await ui.click_text("接受", "exact", dlg):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_label("驛站送信　[進行中]", "exact", dlg) != null, 3.0),
			"驛站送信 not 進行中: %s" % _dialog_text(dlg)):
		return false
	# 信要送到大理：在這裡不能交付，也不能有交付鈕
	if not _check(ui.find_button("交付", "exact", dlg) == null, "交付 button shown at the giver: %s" % _dialog_text(dlg)):
		return false
	await ui.shot("letter_accepted")
	if not await _close_dialog(dlg):
		return false
	_step(11, "驛站送信：走到大理（沿路遇敵就打）")
	route_rooms = [_room_id()]
	var t0 := Time.get_ticks_msec()
	if not await _goto(LETTER_DEST):
		return false
	print("[UiPlay] walked the letter to 大理: %d rooms, %d battles so far, %.0f s" % [route_rooms.size(), battles,
		(Time.get_ticks_msec() - t0) / 1000.0])
	if not _check("de_oasis" in route_rooms and "rr_bridge" in route_rooms, "route did not go overland: %s" % str(route_rooms)):
		return false
	# 大地圖：換了區域，頁尾回到使用說明（不是上一區的「已抵達。」）
	await ui.press_key(KEY_M)
	if not _check(await ui.wait_until(func(): return _panel_open("地圖"), 3.0), "M did not open the map in 大理"):
		return false
	await ui.seconds(0.2)
	if not _check(_map_footer().begins_with("點擊到過的房間"), "map footer not reset after walking to 大理:「%s」" % _map_footer()):
		return false
	await ui.shot("map_in_dali")
	await ui.press_key(KEY_ESCAPE)
	if not _check(await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0), "Esc did not close the map"):
		return false
	_step(12, "驛站送信：大理驛站交付")
	dlg = await _talk("大理驛站管事")
	if dlg == null:
		return false
	if not _check(ui.find_button("驛站", "prefix", dlg) == null, "carriage entry shown at 大理: %s" % _dialog_text(dlg)):
		return false
	if not await ui.click_text("任務", "exact", dlg):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_label("驛站送信　[可交付]", "exact", dlg) != null, 3.0),
			"驛站送信 not 可交付 at 大理: %s" % _dialog_text(dlg)):
		return false
	var money := UiBuild.num(UiClient.sheet().get("money", 0))
	if not await ui.click_text("交付", "exact", dlg):
		return false
	# 交付後清單即時更新：已完成的任務不能還掛著「可交付」與交付鈕
	var gone := func() -> bool:
		return ui.find_label("驛站送信　[可交付]", "exact", dlg) == null and ui.find_button("交付", "exact", dlg) == null
	if not _check(await ui.wait_until(gone, 3.0), "stale quest list after turn-in: %s" % _dialog_text(dlg)):
		return false
	await ui.seconds(0.3)
	if not _check(not _dialog_text(dlg).contains("沒有接這個任務") and not _dialog_text(dlg).contains("【"),
			"dialog shows an error after turn-in: %s" % _dialog_text(dlg)):
		return false
	if not _check(await ui.wait_until(func(): return UiBuild.num(UiClient.sheet().get("money", 0)) >= money + 100, 3.0),
			"letter reward not paid (money %d -> %d)" % [money, UiBuild.num(UiClient.sheet().get("money", 0))]):
		return false
	await ui.shot("letter_turned_in")
	return await _close_dialog(dlg)

# ---------- 4c. 武館學基本內功 → 修煉內力冷卻 ----------
func _inner_and_meditate() -> bool:
	_step(7, "武館 基本內功 + 修煉內力")
	for d in ["西", "西"]:
		if not await _walk(d):
			return false
	var dlg := await _talk("武館教頭")
	if dlg == null:
		return false
	if not await ui.click_text("請教", "exact", dlg):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_by_class("LearnDialog") != null, 5.0), "learn dialog did not open"):
		return false
	var ld := ui.find_by_class("LearnDialog")
	await ui.seconds(0.2)
	# 不能學的原因是嵌在清單裡的文字：不帶「【系統】」頻道標籤
	if not _check(not _dialog_text(ld).contains("【"), "channel tag inside the learn list: %s" % _dialog_text(ld)):
		return false
	var name_l := ui.find_label("基本內功", "exact", ld)
	var learn: Button = null
	if name_l != null:
		learn = ui.find_button("請教 ×1", "exact", name_l.get_parent(), true)
	if learn != null:
		if not await ui.click(learn):
			return false
		await ui.seconds(0.5)
	else:
		ui.warn("基本內功 not learnable here: %s" % _dialog_text(ld))
	await ui.shot("learn_inner")
	if not await _close_dialog(ld):
		return false
	# F1 熱鍵「修煉」：按下後文字變「修煉（N 秒）」（N = 1–10）並灰掉，冷卻完回到「修煉」（主機的 sheet.cooldowns，本機倒數）
	var bar := ui.find_by_class("Hotbar")
	var med := ui.find_button("修煉", "exact", bar) if bar != null else null
	if med != null and not med.disabled:
		if not await ui.click(med):
			return false
		var cd_re := RegEx.create_from_string("^修煉（([1-9]|10) 秒）$")
		if not _check(await ui.wait_until(func(): return med.disabled and cd_re.search(_face(med)) != null, 3.0),
				"修煉 not cooling down after use (face「%s」 disabled=%s)" % [_face(med), str(med.disabled)]):
			return false
		await ui.shot("meditate_cooldown")
		print("[UiPlay] meditate cooldown shown on the face: " + _face(med))
		if not _check(await ui.wait_until(func(): return _face(med) == "修煉" and not med.disabled, 15.0),
				"修煉 did not come back after the cooldown (face「%s」 disabled=%s)" % [_face(med), str(med.disabled)]):
			return false
		print("[UiPlay] meditate ready again: " + _face(med))
	else:
		ui.warn("修煉內力 unavailable (no 基本內功?)")
	for d in ["東", "東"]:
		if not await _walk(d):
			return false
	return _check(_room_name() == "西夏廣場", "expected 西夏廣場, at %s" % _room_name())

# ---------- 5. 面板 ----------
func _panel_open(title: String) -> bool:
	return ui.find_button("關閉(Esc)") != null and ui.find(func(c): return c is Label and (c as Label).text == title \
		and (c as Label).get_theme_font_size("font_size") >= 20) != null

## 面板回饋列（UI 稽核 round 2）：面板蓋住訊息紀錄，面板裡的動作結果（成功訊息或失敗原因）必須在面板裡看得到
func _feedback_text() -> String:
	var fb := ui.find_by_class("PanelFeedback")
	if fb == null:
		return ""
	return (str(fb.get("feed_label").text) + "
" + str(fb.get("status_label").text)).strip_edges()

func _skills_feedback() -> bool:
	var sp := ui.find_by_class("SkillsPanel")
	var b: Button = ui.find_button("×1", "exact", sp, true) if sp != null else null
	if b == null:
		ui.warn("no self-study button in 武功 (skipped feedback check)")
		return true
	if not await ui.click(b):
		return false
	if not _check(await ui.wait_until(func(): return _feedback_text() != "", 3.0),
			"自修 ×1 gave no visible feedback inside the 武功 panel"):
		return false
	print("[UiPlay] 自修 feedback: " + _feedback_text().replace("
", " / "))
	await ui.shot("panel_武功_feedback")
	return true

func _inventory_feedback() -> bool:
	var inv := ui.find_by_class("InventoryPanel")
	# 先點人形上的武器格選取（原作：裝備窗左邊人形，有東西的格子點一下選取）
	var weapon := ui.find(func(c): return c is Button and "item_uid" in c and "slot" in c and str(c.get("item_uid")) != "" 		and str(c.get("slot")) == "weapon", inv) as Button
	if weapon == null:
		weapon = ui.find(func(c): return c is Button and "item_uid" in c and "slot" in c and str(c.get("item_uid")) != "", inv) as Button
	if weapon != null:
		if not await ui.click(weapon):
			return false
		await ui.wait_until(func(): return ui.find_button("卸下", "exact", inv, true) != null, 2.0)
	var un := ui.find_button("卸下", "exact", inv, true)
	if un == null:
		ui.warn("nothing equipped in the 武器 tab (skipped feedback check)")
		return true
	if not await ui.click(un):
		return false
	if not _check(await ui.wait_until(func(): return _feedback_text().contains("卸下"), 3.0),
			"卸下 gave no visible feedback inside the 裝備 window: 「%s」" % _feedback_text()):
		return false
	# 裝回去（之後還要打架）
	var eq: Button = null
	if await ui.wait_until(func(): return ui.find_button("裝備", "exact", ui.find_by_class("InventoryPanel"), true) != null, 3.0):
		eq = ui.find_button("裝備", "exact", ui.find_by_class("InventoryPanel"), true)
	if not _check(eq != null, "裝備 button did not appear after 卸下"):
		return false
	if not await ui.click(eq):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_button("卸下", "exact", ui.find_by_class("InventoryPanel"), true) != null, 3.0),
			"weapon not re-equipped"):
		return false
	print("[UiPlay] 裝備 feedback: " + _feedback_text().replace("
", " / "))
	return true

func _panels() -> bool:
	_step(8, "windows: lanterns, 指令, 任務, 系統, map")
	for p in PANELS:
		if not await ui.click_text(p + "(", "prefix"):
			return false
		if not _check(await ui.wait_until(func(): return _panel_open(p), 3.0), "panel %s did not open" % p):
			return false
		if p == "裝備":
			# 裝備窗自己的分頁（武器／防具／其他／原料），不是訊息紀錄的 全部／戰鬥／系統
			var inv := ui.find_by_class("InventoryPanel")
			var tb: TabBar = null
			if inv != null:
				tb = ui.find(func(c): return c is TabBar, inv) as TabBar
			if not _check(tb != null, "inventory TabBar not found"):
				return false
			for i in tb.tab_count:
				await ui.select_tab(tb, i)
			await ui.select_tab(tb, 0)
			if not await _inventory_feedback():
				return false
		if p == "武功" and not await _skills_feedback():
			return false
		await ui.shot("panel_" + p)
		if not await ui.click_text("關閉(Esc)"):
			return false
		if not _check(await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0), "panel %s did not close" % p):
			return false
	# 指令窗（燈籠「指令」）：6 分頁青銅方鈕；雜項 → 任務 開任務窗
	if not await ui.click_text("指令(", "prefix"):
		return false
	if not _check(await ui.wait_until(func(): return _panel_open("指令"), 3.0), "指令 window did not open"):
		return false
	var cp := ui.find_by_class("CommandPanel")
	var ctb: TabBar = ui.find(func(c): return c is TabBar, cp) as TabBar if cp != null else null
	if not _check(ctb != null and ctb.tab_count == 6, "指令 window should have 6 tabs"):
		return false
	await ui.select_tab(ctb, UiCommands.TABS.find("MARTIAL"))
	if not _check(ui.find_button("修煉內力", "exact", cp) != null, "武學 tab has no 修煉內力"):
		return false
	await ui.shot("panel_指令")
	await ui.select_tab(ctb, UiCommands.TABS.find("MISC"))
	if not await ui.click(ui.find_button("任務", "exact", cp, true)):
		return false
	if not _check(await ui.wait_until(func(): return _panel_open("任務"), 3.0), "雜項 → 任務 did not open the quest window"):
		return false
	# 任務窗要能再看到任務說明（去哪裡打大兔皮），不能只在接任務時的訊息紀錄出現一次（UI 稽核 round 3）
	if not _check(ui.find_label("荒草坡", "contains", ui.find_by_class("QuestPanel")) != null,
			"任務 window does not say where to go (q_rabbit description missing)"):
		return false
	await ui.shot("panel_任務")
	await ui.press_key(KEY_ESCAPE)
	if not _check(await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0), "Esc did not close the quest window"):
		return false
	# Ctrl+6 也開任務窗
	await ui.press_key(KEY_6, true)
	if not _check(await ui.wait_until(func(): return _panel_open("任務"), 3.0), "Ctrl+6 did not open the quest window"):
		return false
	await ui.press_key(KEY_ESCAPE)
	if not _check(await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0), "Esc did not close the quest window"):
		return false
	# 系統窗（燈籠「系統」）
	if not await ui.click_text("系統(", "prefix"):
		return false
	if not _check(await ui.wait_until(func(): return _panel_open("系統"), 3.0), "系統 window did not open"):
		return false
	await ui.shot("panel_系統")
	if not await ui.click_text("關閉(Esc)"):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0), "系統 window did not close"):
		return false
	# 快捷鍵：「武功(Ctrl+N)」→ Ctrl+N 開、Esc 關
	var sk := ui.find_button("武功(Ctrl+", "prefix")
	var n := sk.text.get_slice("Ctrl+", 1).to_int() if sk != null else 0
	if n >= 1 and n <= 9:
		await ui.press_key(KEY_0 + n, true)
		if not _check(await ui.wait_until(func(): return _panel_open("武功"), 3.0), "Ctrl+%d did not open 武功" % n):
			return false
		await ui.press_key(KEY_ESCAPE)
		if not _check(await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0), "Esc did not close panel"):
			return false
	# 聊天框：打字時 M 不開地圖；Esc 放開焦點後 M 開地圖
	# M2：聊天框節點名固定 ChatInput（預設發話頻道改成輕聲細語，placeholder 不再有「千里傳音」；M2_PLAN 6.4）
	var chat := ui.find(func(c): return c is LineEdit and str(c.name) == "ChatInput") as LineEdit
	if not _check(chat != null, "chat box not found"):
		return false
	if not await ui.type_text(chat, "mm"):
		return false
	await ui.press_key(KEY_M)
	if not _check(not _panel_open("地圖"), "M opened the map while typing in chat"):
		return false
	await ui.press_key(KEY_ESCAPE)
	if not _check(not chat.has_focus(), "Esc did not release the chat box"):
		return false
	await ui.press_key(KEY_M)
	if not _check(await ui.wait_until(func(): return _panel_open("地圖"), 3.0), "M did not open the map after Esc from chat"):
		return false
	await ui.press_key(KEY_ESCAPE)
	if not _check(await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0), "Esc did not close the map"):
		return false
	chat.clear()
	# 大地圖（另一位開發者正在做）：有就開關一次，沒有就略過
	var map_btn := ui.find(func(c): return c is Button and ((c as Button).text.begins_with("地圖") or (c as Button).text.begins_with("大地圖")))
	if map_btn != null:
		print("[UiPlay] map button found: " + ui.describe(map_btn))
		if await ui.click(map_btn):
			await ui.seconds(0.3)
			await ui.shot("map")
			# 江湖全圖分頁（原作座標的區域方框不重疊；馬車預設關，沒有驛站路線）
			var mp := ui.find_by_class("MapPanel")
			var mtc := ui.find(func(c): return c is TabContainer, mp) as TabContainer if mp != null else null
			var mtb: TabBar = mtc.get_tab_bar() if mtc != null else null
			if mtb != null and mtb.tab_count > 1:
				await ui.select_tab(mtb, 1)
				await ui.seconds(0.2)
				await ui.shot("map_world")
				await ui.select_tab(mtb, 0)
			await ui.press_key(KEY_ESCAPE)
			await ui.seconds(0.2)
			var close := ui.find_button("關閉(Esc)")
			if close == null:
				close = ui.find_button("關閉")
			if close != null:
				await ui.click(close)
		ui.last_error = ""
	else:
		print("[UiPlay] no map button (skipped)")
	return true

# ---------- M2：頻道選擇、飛鴿傳書、隊伍面板、特殊開關、伺服器設定 ----------
## 單機世界只有自己一人：隊伍面板驗「沒有隊伍時不顯示」＋隊伍頻道回「沒有隊伍」；多人組隊由 tools/m2_acceptance.gd 驗
func _m2_social() -> bool:
	_step(14, "M2: 頻道選擇、飛鴿傳書、隊伍面板、特殊開關、伺服器設定")
	var chat := ui.find(func(c): return c is LineEdit and str(c.name) == "ChatInput") as LineEdit
	var mb := ui.find(func(c): return c is MenuButton and str(c.name) == "ChannelButton") as MenuButton
	if not _check(chat != null and mb != null, "ChatInput / ChannelButton not found"):
		return false
	# 1) 頻道選單：7 個發話頻道＋管理員（單機的本機玩家）的天外飛仙；耗水的標「（耗水）」
	if not await ui.choose_menu(mb, "輕聲細語", "prefix"):
		return false
	var items := ui.menu_items(mb)
	for want in ["千里傳音", "傳音入密", "輕聲細語", "門派交談", "組織交談", "隊伍交談", "江湖謠言", "天外飛仙"]:
		if not _check(items.any(func(t): return str(t).begins_with(want)), "channel menu has no %s: %s" % [want, str(items)]):
			return false
	if not _check(items.size() == 8, "channel menu should list only the 8 talk channels: %s" % str(items)):
		return false
	if not _check(items.any(func(t): return str(t) == "輕聲細語（耗水）") and items.any(func(t): return str(t) == "傳音入密"),
			"water tags wrong: %s" % str(items)):
		return false
	if not _check(mb.text.begins_with("輕聲細語"), "channel button text '%s'" % mb.text):
		return false
	# 截圖時選單要開著（審查：之前只拍到關著的頻道鈕）
	if ui.shots_dir != "" and not ui.is_headless():
		await ui.push_mouse_click(ui.center_of(mb))
		if not await ui.wait_until(func(): return mb.get_popup().visible, 2.0):
			mb.show_popup()
			await ui.frames(2)
		await ui.shot("m2_channel")
		mb.get_popup().hide()
		await ui.frames(2)
	# 2) 輕聲細語：同房（只有自己）也看得到自己的話
	var say := "江湖兒女" + str(randi() % 1000)
	if not await ui.type_text(chat, say, true, true):
		return false
	if not _check(await ui.wait_until(func(): return _log_contains("【輕聲細語】你：" + say), 5.0), "say line not in the chat overlay"):
		return false
	# 3) 隊伍交談：沒有隊伍 → 「隊伍頻道沒人聽」
	if not await ui.choose_menu(mb, "隊伍交談", "prefix"):
		return false
	await ui.seconds(0.6)   # chat_min_interval_ms 500
	if not await ui.type_text(chat, "集合了", true, true):
		return false
	if not _check(await ui.wait_until(func(): return _log_contains("隊伍頻道沒人聽"), 5.0), "no no_party_chat error for 隊伍交談"):
		return false
	# 4) 傳音入密：出現對象欄
	if not await ui.choose_menu(mb, "傳音入密", "prefix"):
		return false
	var wt := ui.find(func(c): return c is LineEdit and str(c.name) == "WhisperTo") as LineEdit
	if not _check(wt != null, "傳音入密 did not show the WhisperTo box"):
		return false
	if not await ui.choose_menu(mb, "輕聲細語", "prefix"):
		return false
	if not _check(ui.find(func(c): return c is LineEdit and str(c.name) == "WhisperTo") == null, "WhisperTo still visible"):
		return false
	await ui.press_key(KEY_ESCAPE)
	# 5) 隊伍面板：沒有隊伍時不顯示
	var pf := ui.find_by_class("PartyFrame", null, false)
	if not _check(pf != null, "PartyFrame not in the main screen"):
		return false
	if not _check(not pf.is_visible_in_tree(), "PartyFrame visible without a party"):
		return false
	# 6) 飛鴿傳書：鴿章 → 收件匣／寫信；寄給不存在的人 → 查無此人
	var pigeon := ui.find(func(c): return c is BaseButton and str(c.name) == "Pigeon") as BaseButton
	if not _check(pigeon != null, "飛鴿傳書 seal (Pigeon) not found"):
		return false
	if not await ui.click(pigeon):
		return false
	var md := ui.find_by_class("MailDialog")
	if not _check(await ui.wait_until(func():
			md = ui.find_by_class("MailDialog")
			return md != null, 3.0), "飛鴿傳書 window did not open"):
		return false
	md = ui.find_by_class("MailDialog")   # lambda 裡的指派不會帶出來
	if not _check(ui.find_label("飛鴿傳書", "exact", md) != null, "mail window has no title"):
		return false
	await ui.shot("m2_mail_inbox")
	var tb := ui.find(func(c): return c is TabBar, md) as TabBar
	if not _check(tb != null and tb.tab_count == 2, "mail window tabs"):
		return false
	await ui.select_tab(tb, 1)
	var to_edit := md.get("to_edit") as LineEdit
	var body := md.get("body_edit") as TextEdit
	if not await ui.type_text(to_edit, "無此俠客"):
		return false
	if not await ui.type_text_edit(body, "久聞大名。"):
		return false
	if not await ui.click_text("放出信鴿", "exact", md):
		return false
	var st := md.get("status_label") as Label
	if not _check(await ui.wait_until(func(): return st.text.contains("查無此人"), 5.0), "mail to nobody: status '%s'" % st.text):
		return false
	await ui.shot("m2_mail_compose")
	if not await ui.click(md.get("close_button")):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_by_class("MailDialog") == null, 3.0), "mail window did not close"):
		return false
	# 7) 系統窗「特殊開關」：接受叫戰／接受組隊邀請（set_pref）、伺服器設定（主機）
	if not await ui.click_text("系統(", "prefix"):
		return false
	if not _check(await ui.wait_until(func(): return _panel_open("系統"), 3.0), "系統 window did not open"):
		return false
	if not await ui.click_text("特殊開關"):
		return false
	var party_pref := ui.find(func(c): return c is CheckButton and str(c.name) == "Pref_accept_party") as CheckButton
	var chal_pref := ui.find(func(c): return c is CheckButton and str(c.name) == "Pref_accept_challenge") as CheckButton
	if not _check(party_pref != null and chal_pref != null, "特殊開關 has no 接受組隊邀請／接受叫戰"):
		return false
	var was := party_pref.button_pressed
	if not await ui.click(party_pref):
		return false
	if not _check(await ui.wait_until(func(): return party_pref.button_pressed != was and not party_pref.disabled 			and (_feedback_text().contains("接受組隊邀請") or _log_contains("接受組隊邀請：")), 5.0),
			"set_pref accept_party: no pref_changed (feedback '%s')" % _feedback_text()):
		return false
	if not await ui.click(party_pref):
		return false
	if not _check(await ui.wait_until(func(): return party_pref.button_pressed == was and not party_pref.disabled, 5.0), "接受組隊邀請 did not toggle back"):
		return false
	await ui.shot("m2_prefs")
	if not await ui.click_text("伺服器設定（主機）"):
		return false
	var sd: Control = null
	if not _check(await ui.wait_until(func():
			sd = ui.find_by_class("ServerOptionsDialog")
			return sd != null and ui.find(func(c): return c is OptionButton and str(c.name) == "Opt_pk_mode", sd) != null, 5.0),
			"伺服器設定 did not open with options"):
		return false
	sd = ui.find_by_class("ServerOptionsDialog")   # lambda 裡的指派不會帶出來
	for key in ["rule_preset", "pk_mode", "wait_mode", "stagecoach_enabled"]:
		if not _check(ui.find(func(c): return c is OptionButton and str(c.name) == "Opt_" + key, sd) != null, "伺服器設定 has no %s" % key):
			return false
	await ui.shot("m2_server_options")
	if not await ui.click(sd.get("close_button")):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_by_class("ServerOptionsDialog") == null, 3.0), "伺服器設定 did not close"):
		return false
	# 伺服器設定面板開在置中層時系統窗會先收起；還開著就關掉
	if ui.find_button("關閉(Esc)") != null and not await ui.click_text("關閉(Esc)"):
		return false
	return _check(await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0), "系統 window did not close")

## 聊天浮層（RichTextLabel）裡有沒有這段文字
## 聊天／系統浮層最後幾行（失敗訊息用）
func _log_tail(n: int) -> String:
	for c in ui.controls(null, false):
		if c is RichTextLabel and (c as RichTextLabel).get_parsed_text().contains("【"):
			var lines := (c as RichTextLabel).get_parsed_text().strip_edges().split("\n")
			return " / ".join(lines.slice(maxi(0, lines.size() - n)))
	return "?"

func _log_contains(t: String) -> bool:
	for c in ui.controls(null, false):
		if c is RichTextLabel and (c as RichTextLabel).get_parsed_text().contains(t):
			return true
	return false

# ---------- 故事包：任務對話、任務窗、江湖傳聞 ----------
const STORY_QUEST := "q_yuner"
const STORY_OUTCOME := "li"
const STORY_OFFER_CHOICES := ["c_ask", "c_help"]   # 雲兒的 offer：「姑娘為何愁眉不展？」→（繼續）→「我替妳去看看他們兩個。」
const STORY_RUMOR_HINT := "雲兒姑娘"                # rmr_q_yuner_first 的文字片段

func _story_dialog() -> Control:
	var d := ui.find_by_class("StoryDialog")
	return d if d != null and d.is_visible_in_tree() else null

func _npc_display(npc_id: String) -> String:
	return str(UiClient.tables().get("npcs", {}).get(npc_id, {}).get("name", npc_id))

func _story_button(d: Control, choice: String) -> Button:
	for b in d.get("choice_buttons"):
		if is_instance_valid(b) and (b as Button).is_visible_in_tree() and not (b as Button).disabled \
				and str((b as Button).get_meta("choice", "")) == choice:
			return b
	return null

func _story_node() -> String:
	var d := _story_dialog()
	return str(d.call("node_id")) if d != null else ""

## 選一個選項（逐字顯示中先按空白鍵跳過；之前若有合成的「（繼續）」先按掉）
func _story_pick(choice: String, shot_name := "") -> bool:
	for i in 40:
		var d := _story_dialog()
		if not _check(d != null, "story dialog is not open (want choice %s)" % choice):
			return false
		if d.call("is_typing"):
			# 逐字顯示：等它顯示完（40 字／秒；不按空白鍵，免得觸發畫面上有焦點的按鈕）
			await ui.wait_until(func(): return _story_dialog() == null or not _story_dialog().call("is_typing"), 10.0)
			continue
		var b := _story_button(d, choice)
		if b == null:
			b = _story_button(d, "_next")
			if b == null:
				await ui.frames(3)
				continue
		var is_target := str(b.get_meta("choice", "")) == choice
		if is_target and shot_name != "":
			await ui.shot(shot_name)   # 文字顯示完、選項都出來時拍（選之前）
		var n0 := _story_node()
		if not await ui.click(b):
			return false
		await ui.wait_until(func(): return _story_node() != n0, 3.0)
		if is_target:
			return true
	var d2 := _story_dialog()
	var desc: PackedStringArray = []
	if d2 != null:
		for b2 in d2.get("choice_buttons"):
			if is_instance_valid(b2):
				desc.append("%s(vis=%s dis=%s)" % [str(b2.get_meta("choice", "")), str((b2 as Button).is_visible_in_tree()), str((b2 as Button).disabled)])
	return _check(false, "choice %s never appeared (node %s, choices %s)" % [choice, _story_node(), ", ".join(desc)])

## 對話剩下的「（繼續）」按完，最後按「結束」
func _story_finish() -> bool:
	for i in 40:
		var d := _story_dialog()
		if d == null:
			return true
		if d.call("is_typing"):
			# 逐字顯示：等它顯示完（40 字／秒；不按空白鍵，免得觸發畫面上有焦點的按鈕）
			await ui.wait_until(func(): return _story_dialog() == null or not _story_dialog().call("is_typing"), 10.0)
			continue
		var b := _story_button(d, "_next")
		if b == null:
			b = _story_button(d, "__end")
		if b == null:
			await ui.frames(3)
			continue
		var n0 := _story_node()
		if not await ui.click(b):
			return false
		await ui.wait_until(func(): return _story_dialog() == null or _story_node() != n0, 3.0)
	return _check(_story_dialog() == null, "story dialog did not end")

## 點人物：有目前目標的 NPC 直接開任務對話（不另開服務選單）
func _story_talk(npc_id: String) -> bool:
	var nm := _npc_display(npc_id)
	if not await ui.click_text(nm, "prefix", _npcs_box()):
		return false
	return _check(await ui.wait_until(func(): return _story_dialog() != null, 5.0), "talking to %s did not open the story dialog" % nm)

func _quest_panel_text() -> String:
	var qp := ui.find_by_class("QuestPanel")
	if qp == null:
		return ""
	var parts: PackedStringArray = []
	for c in ui.controls(qp):
		if c is Label:
			parts.append((c as Label).text)
		elif c is Button:
			parts.append((c as Button).text)
		elif c is RichTextLabel:
			parts.append((c as RichTextLabel).get_parsed_text())
	return " | ".join(parts)

func _story_quest() -> bool:
	_step(18, "故事包：雲兒小姐的煩惱（任務對話、任務窗、江湖傳聞）")
	var row: Dictionary = UiClient.tables().get("quests", {}).get(STORY_QUEST, {})
	var plan: Dictionary = {}
	for p in row.get("test_plan", []):
		if p is Dictionary and str(p.get("outcome", "")) == STORY_OUTCOME:
			plan = p
	if not _check(not plan.is_empty(), "%s has no test_plan for outcome %s" % [STORY_QUEST, STORY_OUTCOME]):
		return false
	var title := str(row.get("name", STORY_QUEST))
	var first_stage: Dictionary = (row.get("stages", []) as Array)[0]
	var back_to := _room_id()   # 之後的步驟（驛站送信）從這裡用相對方向走
	var shot_dialog := false
	for st in plan.get("path", []):
		var step_s := str(st)
		if _done:
			return false
		if step_s.begins_with("walk@"):
			if _story_dialog() != null and not await _story_finish():
				return false
			if not await _goto(step_s.substr(5)):
				return false
		elif step_s.begins_with("accept@"):
			var dlg := await _talk(_npc_display(step_s.substr(7)))
			if dlg == null:
				return false
			if not await ui.click_text("任務", "prefix", dlg):
				return false
			var talk_btn := ui.find(func(c): return c is Button and str(c.name) == "QuestTalk_" + STORY_QUEST \
				and not (c as Button).disabled, dlg)
			if not _check(talk_btn != null, "quest list has no 詳談 button for %s" % STORY_QUEST):
				return false
			if not await ui.click(talk_btn):
				return false
			if not _check(await ui.wait_until(func(): return _story_dialog() != null, 5.0), "詳談 did not open the story dialog"):
				return false
			for i in STORY_OFFER_CHOICES.size():
				if not await _story_pick(STORY_OFFER_CHOICES[i], "story_offer" if i == 0 else ""):
					return false
			if not await _story_finish():
				return false
			if not _check(await ui.wait_until(func(): return _sheet_has_quest(STORY_QUEST), 3.0), "offer did not accept " + STORY_QUEST):
				return false
			# 任務窗：章節、任務名、目前階段標題、目標
			await ui.press_key(KEY_6, true)
			if not _check(await ui.wait_until(func(): return _panel_open("任務"), 3.0), "Ctrl+6 did not open the quest window"):
				return false
			var qb := ui.find_button(title, "contains", ui.find_by_class("QuestPanel"), true)
			if qb != null:
				await ui.click(qb)
			await ui.frames(3)
			var txt := _quest_panel_text()
			for want in [str(row.get("chapter", "")), title, str(first_stage.get("title", "")),
					str((first_stage.get("objectives", []) as Array)[0].get("text", ""))]:
				if not _check(want == "" or txt.contains(want), "quest window lacks '%s' (%s)" % [want, txt.left(300)]):
					return false
			await ui.shot("story_quest_log")
			await ui.press_key(KEY_ESCAPE)
			if not _check(await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0), "Esc did not close the quest window"):
				return false
		elif step_s.begins_with("talk@"):
			if _story_dialog() != null and not await _story_finish():
				return false
			if not await _story_talk(step_s.substr(5)):
				return false
		elif step_s.begins_with("choose@"):
			var parts := step_s.substr(7).split(":")
			if not await _story_pick(parts[2], "" if shot_dialog else "story_dialog_choice"):
				return false
			shot_dialog = true
		else:
			return _check(false, "ui story step not supported: " + step_s)
	if not await _story_finish():
		return false
	var label_want := str(row.get("outcomes", {}).get(STORY_OUTCOME, {}).get("label", ""))
	if not _check(await ui.wait_until(func(): return _quest_done_label(STORY_QUEST) == label_want, 5.0),
			"quests_done for %s: '%s', want '%s'" % [STORY_QUEST, _quest_done_label(STORY_QUEST), label_want]):
		return false
	# 任務窗「已完成」分頁：結局名
	await ui.press_key(KEY_6, true)
	if not _check(await ui.wait_until(func(): return _panel_open("任務"), 3.0), "Ctrl+6 did not open the quest window"):
		return false
	if not await ui.click_text("已完成", "prefix", ui.find_by_class("QuestPanel")):
		return false
	var qb2 := ui.find_button(title, "contains", ui.find_by_class("QuestPanel"), true)
	if qb2 != null:
		await ui.click(qb2)
	if not _check(await ui.wait_until(func(): return _quest_panel_text().contains(label_want), 3.0),
			"已完成 tab does not show the outcome '%s' (%s)" % [label_want, _quest_panel_text().left(300)]):
		return false
	await ui.shot("story_quest_done")
	await ui.press_key(KEY_ESCAPE)
	await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0)
	# 江湖傳聞：系統窗的「江湖傳聞」頁（主機回 rumor_list）
	if not await ui.click_text("系統(", "prefix"):
		return false
	if not _check(await ui.wait_until(func(): return _panel_open("系統"), 3.0), "系統 window did not open"):
		return false
	if not await ui.click_text("江湖傳聞", "exact", ui.find_by_class("SystemPanel")):
		return false
	var has_rumor := func() -> bool:
		var box := ui.find(func(c): return str(c.name) == "RumorList")
		if box == null:
			return false
		for c in ui.controls(box):
			if c is Label and (c as Label).text.contains(STORY_RUMOR_HINT):
				return true
		return false
	if not _check(await ui.wait_until(has_rumor, 12.0), "江湖傳聞 page does not list the q_yuner rumour"):
		return false
	await ui.shot("story_rumor")
	print("[UiPlay] story: message log shows 【江湖傳聞】 = %s" % str(_log_contains("江湖傳聞")))
	if not await ui.click_text("關閉(Esc)"):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0), "系統 window did not close"):
		return false
	return await _goto(back_to)

func _sheet_has_quest(qid: String) -> bool:
	for q in UiClient.sheet().get("quests", []):
		if q is Dictionary and str(q.get("id", "")) == qid:
			return true
	return false

func _quest_done_label(qid: String) -> String:
	for q in UiClient.sheet().get("quests_done", []):
		if q is Dictionary and str(q.get("id", "")) == qid:
			return str(q.get("outcome_label", ""))
	return ""

# ---------- 6a. 查看偵察 ----------
func _scout_window() -> Control:
	return ui.find_by_class("ScoutDialog")

func _look_button() -> Button:
	var bar := ui.find_by_class("Hotbar")
	return ui.find(func(c): return c is HotbarSlot and (c as HotbarSlot).glyph == "查看", bar) as Button if bar != null else null

## 查看鈕可以按（冷卻完、沒有送出中）
func _look_ready(b: Button) -> bool:
	return b != null and not b.disabled and _face(b) == "查看"

func _scout() -> bool:
	_step(15, "查看偵察（安全的房間只印描述；野外 離開／迎戰）")
	if not _check(UiClient.scout_enabled(), "host world_info.scout_enabled is not true"):
		return false
	var look := _look_button()
	if not _check(look != null, "no 查看 slot on the hotbar"):
		return false
	# 安全的房間：查看只印房間描述，沒有視窗、沒有冷卻
	if bool(UiClient.region_view().get("safe", false)):
		var safe_room := _room_name()
		if not _check(await ui.wait_until(func(): return _look_ready(look), 5.0), "查看 not ready in a safe room (face「%s」)" % _face(look)):
			return false
		if not await ui.click(look):
			return false
		await ui.seconds(0.6)
		if not _check(_scout_window() == null, "scout window opened in safe room %s" % safe_room):
			return false
		if not _check(_look_ready(look), "查看 cooling down in a safe room (face「%s」)" % _face(look)):
			return false
		if not _check(_log_contains("【%s】" % safe_room), "look text for %s not in the log" % safe_room):
			return false
	if not await _goto("dlw_road"):
		return false
	if not await _ensure_healthy():
		return false
	if _room_id() != "dlw_road" and not await _goto("dlw_road"):
		return false
	# 第一次：點熱鍵列的「查看」→ 視窗 →「離開」
	var win := await _open_scout(false)
	if win == null:
		return false
	await ui.shot("scout_offer")
	if not _check(look.disabled and _face(look).begins_with("查看（"), "查看 not cooling after scouting (face「%s」)" % _face(look)):
		return false
	print("[UiPlay] scout cooldown on the face: " + _face(look))
	if not await ui.click_text("離開", "exact", win):
		return false
	if not _check(await ui.wait_until(func(): return _scout_window() == null, 3.0), "scout window did not close after 離開"):
		return false
	if not _check(_battle() == null, "離開 started a battle"):
		return false
	if not _check(await ui.wait_until(func(): return _log_contains("悄悄避開"), 3.0), "decline text not in the log"):
		return false
	await ui.shot("scout_declined")
	# 第二次：冷卻完按 F3 → 視窗 →「迎戰」→ 戰鬥畫面
	if _battle() != null and not await _fight():
		return false
	win = await _open_scout(true)
	if win == null:
		return false
	if not await ui.click_text("迎戰", "exact", win):
		return false
	if not _check(await ui.wait_until(func(): return _battle() != null, 5.0), "迎戰 did not open the battle screen"):
		return false
	if not _check(_scout_window() == null, "scout window still visible over the battle"):
		return false
	print("[UiPlay] scout accepted -> battle")
	return await _fight()

## 等查看鈕冷卻完，按下（hotkey＝F3，否則點熱鍵格），等邀戰視窗；回傳視窗（失敗回 null）
func _open_scout(hotkey: bool) -> Control:
	var look := _look_button()
	if not _check(await ui.wait_until(func(): return _look_ready(look), 15.0), "查看 never became ready (face「%s」)" % _face(look)):
		return null
	if hotkey:
		await ui.press_key(KEY_F3)
	elif not await ui.click(look):
		return null
	if not await ui.wait_until(func(): return _scout_window() != null, 5.0):
		_check(false, "scout window did not appear in %s (hotkey=%s, face「%s」 disabled=%s, log tail: %s)" % [_room_name(),
			str(hotkey), _face(look), str(look.disabled), _log_tail(4)])
		return null
	var win := _scout_window()
	var msg := ui.find(func(c): return c is Label and (c as Label).text.begins_with("你發現附近有："), win) as Label
	if not _check(msg != null and msg.text.contains("×"), "scout window text wrong: %s" % _dialog_text(win)):
		return null
	if not _check(ui.find_button("迎戰", "exact", win, true) != null and ui.find_button("離開", "exact", win, true) != null,
			"scout window lacks 迎戰／離開"):
		return null
	print("[UiPlay] scout window: " + msg.text)
	return win

# ---------- 6. 野外 + 戰鬥 ----------
func _coverage_done() -> bool:
	if m3a_ready:
		for t in M3A_CMDS:
			if not used_cmds.has(t):
				return false
	return used_cmds.has("攻") and used_cmds.has("移") and used_cmds.has("防") and used_cmds.has("休")

# ---------- M3a 設定 ----------
## 只有這裡直接送 intent（debug_set 是設定用的除錯指令，介面上沒有按鈕）；其餘全部透過畫面
func _debug_set(key: String, value: Variant) -> String:
	# 離線模式的主機在同一個程序：結果可能在 send_intent 回來之前就送到，所以先接訊號
	var res := { "done": false, "reason": "", "seq": -2 }
	var got := {}
	var cb := func(sq: int, ok: bool, reason: String):
		got[sq] = "" if ok else reason
		if sq == int(res["seq"]):
			res["done"] = true
			res["reason"] = got[sq]
	ClientState.intent_result.connect(cb)
	var seq := NetworkManager.send_intent("debug_set", { "key": key, "value": value })
	res["seq"] = seq
	if got.has(seq):
		res["done"] = true
		res["reason"] = got[seq]
	if seq < 0:
		ClientState.intent_result.disconnect(cb)
		return "not_connected"
	await ui.wait_until(func(): return bool(res["done"]), 5.0)
	ClientState.intent_result.disconnect(cb)
	return str(res["reason"]) if bool(res["done"]) else "timeout"

func _m3a_setup() -> bool:
	_step(14, "M3a 設定：內／醫／毒（debug_set）")
	for kv in M3A_SETUP:
		var why: String = await _debug_set(str(kv[0]), kv[1])
		if why == "unknown_intent":
			ui.warn("host has no --debug-intents: M3a 內／醫／毒 coverage skipped")
			return true
		if not _check(why == "", "debug_set %s -> %s" % [str(kv[0]), why]):
			return false
	m3a_ready = true
	await ui.seconds(0.5)
	print("[UiPlay] M3a setup done (內 醫 毒 will be pressed in battle)")
	return true

# ---------- 惡人警告（審查修正：VillainPrompt 的「迎戰」「求救」、倒數、離開房間就收起，之前只有 duo bot 測過） ----------
## 只在 --debug-intents（m3a_ready）時跑。設定（不是受測物）：夜裡（戌時）、實戰 600（過新手保護）、警告倒數拉長到 20 秒
## （截圖來得及；倒數本身由 test_ui_villain_prompt 測）、teleport 到荒草坡、wander_place 把南海鱷神放進來（出手機率 60%，沒跳警告就再放一次）。
## 受測物：警告條出現、文字有惡人名、有「迎戰」鈕與倒數、「快離開這裡」；從畫面點出口離開 → 警告條收起、沒有開打。
func _villain_prompt_ui() -> bool:
	if not m3a_ready:
		return true
	_step(19, "惡人警告：VillainPrompt（迎戰／求救、倒數；離開房間就收起）")
	if _battle() != null and not await _fight():
		return false
	var xp0 := int(UiClient.sheet().get("combat_xp", 0))
	for kv in [["option:villain_warn_s", 20], ["combat_xp", 600], ["hour", "戌"]]:
		if not _check(await _debug_set(str(kv[0]), kv[1]) == "", "debug_set %s" % str(kv[0])):
			return false
	if not await _teleport("xw_grass"):
		return false
	var vp: Control = null
	for i in 12:
		if not _check(await _debug_set("wander_place", "w_nanhai:xw_grass") == "", "debug_set wander_place"):
			return false
		if await ui.wait_until(func(): return ui.find_by_class("VillainPrompt") != null, 1.5):
			vp = ui.find_by_class("VillainPrompt")
			break
		if _battle() != null and not await _fight():
			return false
	if not _check(vp != null, "VillainPrompt did not show after 12 placements"):
		return false
	var title := ui.find(func(c): return c is Label and str(c.name) == "VillainText", vp) as Label
	if not _check(title != null and title.text.contains("南海鱷神"), "villain text: %s" % (title.text if title != null else "<none>")):
		return false
	if not _check(ui.find_button("迎戰", "exact", vp) != null, "VillainPrompt has no 迎戰 button"):
		return false
	var cd := ui.find(func(c): return c is Label and str(c.name) == "VillainCountdown", vp) as Label
	if not _check(cd != null and cd.text.ends_with("秒"), "countdown label: %s" % (cd.text if cd != null else "<none>")):
		return false
	if not _check(ui.find_label("快離開這裡", "prefix", vp) != null, "VillainPrompt lacks the 快離開這裡 hint"):
		return false
	await ui.shot("villain_prompt")
	# 從畫面離開房間（往西回東門外官道）→ 主機送 villain_clear ESCAPED，警告條收起、不開打
	if not await _walk("西"):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_by_class("VillainPrompt") == null, 5.0), "VillainPrompt still shown after leaving the room"):
		return false
	var chased := _battle() != null and str(ClientState.battle_state.get("kind", "")) == "CHASE"
	if not _check(not chased, "a chase battle started although the player left in time"):
		return false
	if _battle() != null and not await _fight():
		return false
	# 還原設定：天亮（惡人回城）、實戰改回原值、倒數改回預設
	for kv in [["hour", "卯"], ["combat_xp", xp0], ["option:villain_warn_s", 3]]:
		if not _check(await _debug_set(str(kv[0]), kv[1]) == "", "debug_set %s (restore)" % str(kv[0])):
			return false
	return true

# ---------- M3a 門派畫面（審查：拜師確認、不符合條件、叛教兩段、思過處提示、看守人贖人、新門派師父對話） ----------
## 只在 --debug-intents（m3a_ready）時跑：用 debug_set teleport／morality 把角色放到場景（設定，不是受測物），
## 之後全部從畫面點：人物鈕 → 對話框 → 拜師／叛教／看守人。
func _m3a_sect_screens() -> bool:
	if not m3a_ready:
		return true
	_step(16, "M3a 門派畫面：拜師、叛教、思過處")
	if _battle() != null and not await _fight():
		return false
	# 1. 恆山（只收女弟子）：男角色看到紅字「你目前不符合：只收女弟子」
	if not await _teleport("hg_hall"):
		return false
	var dlg := await _talk("定閒師太")
	if dlg == null:
		return false
	await ui.shot("m3a_master_hengshan")
	if not await ui.click_text("拜師", "exact", dlg):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_label("你目前不符合", "prefix", dlg) != null, 3.0),
			"恆山 join confirm does not mark 只收女弟子 as unmet: %s" % _dialog_text(dlg)):
		return false
	if not _check(ui.find_label("你目前不符合", "prefix", dlg).text.contains("只收女弟子"), "unmet line: %s" % _dialog_text(dlg)):
		return false
	await ui.shot("m3a_join_unmet")
	if not await ui.click_text("再想想", "exact", dlg):
		return false
	if not await _close_dialog(dlg):
		return false
	# 2. 星宿（男女皆收、善惡 −100 以下）：師父對話 → 拜師確認 → 拜入 → 叛教兩段
	if not _check(await _debug_set("morality", -200) == "", "debug_set morality"):
		return false
	if not await _teleport("xh_hall"):
		return false
	dlg = await _talk("丁春秋")
	if dlg == null:
		return false
	await ui.shot("m3a_master_xingxiu")
	if not await ui.click_text("拜師", "exact", dlg):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_button("確定拜師", "exact", dlg, true) != null, 3.0), "no 確定拜師"):
		return false
	if not _check(ui.find_label("你目前不符合", "prefix", dlg) == null, "星宿 join shows unmet conditions: %s" % _dialog_text(dlg)):
		return false
	await ui.shot("m3a_join_confirm")
	if not await ui.click(ui.find_button("確定拜師", "exact", dlg, true)):
		return false
	if not _check(await ui.wait_until(func(): return str(UiClient.sheet().get("sect", "")) == "xingxiu", 5.0), "join 星宿 failed"):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_button("叛教", "exact", dlg, true) != null, 3.0), "no 叛教 after joining"):
		return false
	if not await ui.click(ui.find_button("叛教", "exact", dlg, true)):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_button("我意已決", "exact", dlg, true) != null, 3.0), "betray step 1 missing"):
		return false
	await ui.shot("m3a_betray")
	if not await ui.click(ui.find_button("我意已決", "exact", dlg, true)):
		return false
	var le := ui.find(func(c): return c is LineEdit and (c as LineEdit).name == "BetrayWord", dlg) as LineEdit
	if not _check(le != null, "betray step 2: no word box"):
		return false
	if not _check(ui.find_button("叛出師門", "exact", dlg, true) == null, "叛出師門 enabled before typing"):
		return false
	if not await ui.type_text(le, "叛教"):
		return false
	await ui.shot("m3a_betray_confirm")
	if not await ui.click(ui.find_button("叛出師門", "exact", dlg, true)):
		return false
	if not _check(await ui.wait_until(func(): return str(UiClient.sheet().get("sect", "")) == "", 5.0), "betray did not leave the sect"):
		return false
	await ui.seconds(0.3)
	var d2 := ui.find_by_class("NpcDialog")
	if d2 != null and d2.is_visible_in_tree():
		await _close_dialog(d2)
	# 3. 少林：拜入 → 善惡跌破 −299 → 押進思過處（提示列）→ 看守人的贖人列 → 坐滿出獄
	if not _check(await _debug_set("morality", 0) == "", "debug_set morality"):
		return false
	if not await _teleport("sl_gate"):
		return false
	dlg = await _talk("知客僧")
	if dlg == null:
		return false
	if not await ui.click_text("拜師", "exact", dlg):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_button("確定拜師", "exact", dlg, true) != null, 3.0), "no 確定拜師 at 少林"):
		return false
	if not await ui.click(ui.find_button("確定拜師", "exact", dlg, true)):
		return false
	if not _check(await ui.wait_until(func(): return str(UiClient.sheet().get("sect", "")) == "shaolin", 5.0), "join 少林 failed"):
		return false
	await _close_dialog(dlg)
	if not _check(await _debug_set("morality", -400) == "", "debug_set morality -400"):
		return false
	var jailed := func() -> bool:
		var jb := ui.find(func(c): return c is PanelContainer and (c as Control).name == "JailBanner")
		return UiClient.sheet().get("jail", null) is Dictionary and jb != null and jb.is_visible_in_tree()
	if not _check(await ui.wait_until(jailed, 5.0), "not jailed (or no jail banner) after 善惡 −400 in 少林"):
		return false
	# M3b O12（審查修正）：違反門規只有 jail_location CAPITAL 才關京城監獄（看守人在監獄門口，牢裡沒人可談）；AUTO 仍是思過處
	var capital := str(ClientState.world_info.get("jail_breach_resolved", "SECT")) == "CAPITAL"
	var jail_room := "jc_jail" if capital else "sl_siguo"
	if not _check(await ui.wait_until(func(): return _room_id() == jail_room, 5.0), "not moved into %s (room %s)" % [jail_room, _room_id()]):
		return false
	await ui.seconds(0.4)
	await ui.shot("m3a_jail_banner")
	if capital:
		if not _check(await _debug_set("online_s_add", 7300) == "", "debug_set online_s_add"):
			return false
		return _check(await ui.wait_until(func(): return not (UiClient.sheet().get("jail", null) is Dictionary), 5.0), "still jailed after serving")
	dlg = await _talk("普知")
	if dlg == null:
		return false
	if not await ui.click_text("思過處", "prefix", dlg):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_button("贖人", "prefix", dlg) != null, 3.0),
			"jail warden lists no prisoner / 贖人 row: %s" % _dialog_text(dlg)):
		return false
	await ui.shot("m3a_jail_warden")
	await _close_dialog(dlg)
	# 坐滿刑期（上線時間快轉）→ 出獄回山門
	if not _check(await _debug_set("online_s_add", 7300) == "", "debug_set online_s_add"):
		return false
	return _check(await ui.wait_until(func(): return not (UiClient.sheet().get("jail", null) is Dictionary), 5.0), "still jailed after serving")

# ---------- M3b：袋位、乞討、錢莊、鏢局、製作、組織 ----------
func _close_npc_dialog() -> void:
	var dd := ui.find_by_class("NpcDialog")
	if dd != null and dd.is_visible_in_tree():
		await _close_dialog(dd)

func _window_open(cls: Variant) -> Control:
	var w := ui.find(func(c): return is_instance_of(c, cls))
	return w if w != null and w.is_visible_in_tree() else null

func _m3b_screens() -> bool:
	if not m3a_ready:
		return true
	_step(20, "M3b 畫面：袋位、乞討、錢莊、鏢局、製作、組織")
	if _battle() != null and not await _fight():
		return false
	var eras: Variant = ClientState.world_info.get("enabled_eras", [])
	var has_b: bool = eras is Array and "1.0B" in eras
	if not has_b:
		ui.warn("world has no 1.0B (old 1.0A world): 丐幫袋位／乞討 skipped; use a fresh --world")
	if not _check(await _debug_set("morality", 0) == "", "debug_set morality 0"):
		return false
	if has_b:
		# 1. 叛出少林（M3a 那段拜入的），再到丐幫拜師
		if str(UiClient.sheet().get("sect", "")) != "":
			if not await _teleport("sl_gate"):
				return false
			var d0 := await _talk("知客僧")
			if d0 == null:
				return false
			if not await ui.click(ui.find_button("叛教", "exact", d0, true)):
				return false
			if not _check(await ui.wait_until(func(): return ui.find_button("我意已決", "exact", d0, true) != null, 3.0), "betray step 1 missing"):
				return false
			await ui.click(ui.find_button("我意已決", "exact", d0, true))
			var le0 := ui.find(func(c): return c is LineEdit and (c as LineEdit).name == "BetrayWord", d0) as LineEdit
			if not _check(le0 != null, "betray: no word box"):
				return false
			await ui.type_text(le0, "叛教")
			await ui.click(ui.find_button("叛出師門", "exact", d0, true))
			if not _check(await ui.wait_until(func(): return str(UiClient.sheet().get("sect", "")) == "", 5.0), "did not leave 少林"):
				return false
			await ui.seconds(0.3)
			await _close_npc_dialog()
			if not _check(await _debug_set("morality", 0) == "", "debug_set morality 0"):
				return false
		if not await _teleport("gb_pomiao"):
			return false
		var dlg := await _talk("陳長老")
		if dlg == null:
			return false
		await ui.shot("m3b_master_gaibang")
		if not await ui.click_text("拜師", "exact", dlg):
			return false
		if not _check(await ui.wait_until(func(): return ui.find_button("確定拜師", "exact", dlg, true) != null, 3.0), "no 確定拜師 at 丐幫"):
			return false
		await ui.click(ui.find_button("確定拜師", "exact", dlg, true))
		if not _check(await ui.wait_until(func(): return str(UiClient.sheet().get("sect", "")) == "gaibang", 5.0), "join 丐幫 failed"):
			return false
		# 袋位頁（陳長老選單）
		if not _check(await ui.wait_until(func(): return ui.find_button("袋位", "exact", dlg, true) != null, 3.0), "陳長老 menu has no 袋位"):
			return false
		await ui.click(ui.find_button("袋位", "exact", dlg, true))
		if not _check(await ui.wait_until(func(): return ui.find_label("一袋弟子", "contains", dlg) != null, 3.0), "袋位 page does not list 一袋弟子: %s" % _dialog_text(dlg)):
			return false
		await ui.seconds(0.3)
		await ui.shot("m3b_rank_page")
		await _close_npc_dialog()
		# 屬性窗門派欄「袋位：…」
		if not await ui.click_text("屬性(", "prefix"):
			return false
		if not _check(await ui.wait_until(func(): return ui.find_label("袋位：", "contains") != null, 3.0), "屬性 window shows no 袋位 line"):
			return false
		await ui.shot("m3b_attr_rank")
		await ui.click_text("關閉(Esc)")
		await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0)
		# 2. 乞討：京城廣場王大娘（NPC 選單多「乞討」）
		if not await _teleport("jc_square"):
			return false
		var d2 := await _talk("王大娘")
		if d2 == null:
			return false
		if not _check(await ui.wait_until(func(): return ui.find_button("乞討", "exact", d2, true) != null, 3.0), "王大娘 menu has no enabled 乞討"):
			return false
		await ui.shot("m3b_beg_menu")
		var prof0 := _qitao_prof()
		await ui.click(ui.find_button("乞討", "exact", d2, true))
		if not _check(await ui.wait_until(func(): return _qitao_prof() > prof0, 4.0), "乞討 did not raise 乞討 proficiency"):
			return false
		await ui.seconds(0.3)
		await ui.shot("m3b_beg_done")
		await _close_npc_dialog()
	# 3. 錢莊
	if not _check(await _debug_set("money", 5000) == "", "debug_set money"):
		return false
	if not await _teleport("xx_bank"):
		return false
	var d3 := await _talk("錢莊掌櫃")
	if d3 == null:
		return false
	if not await ui.click_text("錢莊", "exact", d3):
		return false
	if not _check(await ui.wait_until(func(): return _window_open(BankWindow) != null, 5.0), "錢莊 window did not open"):
		return false
	var bw := _window_open(BankWindow) as BankWindow
	var me := ui.find(func(c): return c is LineEdit and str((c as LineEdit).name) == "MoneyEdit", bw) as LineEdit
	if not _check(me != null, "bank: no money box"):
		return false
	await ui.type_text(me, "50")
	if not await ui.click(ui.find(func(c): return c is Button and str((c as Button).name) == "Deposit", bw)):
		return false
	if not _check(await ui.wait_until(func(): return bw.bank_money_label.text.contains("50"), 5.0), "deposit not shown: %s" % bw.bank_money_label.text):
		return false
	# 存一件：身上一列（不是裝備中的）→ 存入
	var row: Button = null
	for r in bw.carry_rows():
		if EconUi.not_storable_reason(r) == "":
			var want := "%s_%s" % [BankWindow.SIDE_CARRY, str(r.get("uid", ""))]
			row = ui.find(func(c): return c is Button and str((c as Button).name) == want, bw) as Button
			if row != null:
				break
	if row != null:
		await ui.click(row)
		var used0: String = bw.used_label.text
		await ui.click(ui.find(func(c): return c is Button and str((c as Button).name) == "Put", bw))
		if not _check(await ui.wait_until(func(): return bw.used_label.text != used0, 5.0), "bank put: used count did not change (%s)" % used0):
			return false
	else:
		ui.warn("bank: no storable carry row")
	await ui.seconds(0.3)
	await ui.shot("m3b_bank")
	# M3b 審查 3：從錢莊取出（錢莊那一欄選一列 → ← 取出）也要拍
	var brow: Button = null
	for r2 in bw.bank_rows():
		var want2 := "%s_%s" % [BankWindow.SIDE_BANK, str(r2.get("uid", ""))]
		brow = ui.find(func(c): return c is Button and str((c as Button).name) == want2, bw) as Button
		if brow != null:
			break
	if not _check(brow != null, "bank: nothing stored to take back"):
		return false
	await ui.click(brow)
	var used1: String = bw.used_label.text
	await ui.click(ui.find(func(c): return c is Button and str((c as Button).name) == "Take", bw))
	if not _check(await ui.wait_until(func(): return bw.used_label.text != used1, 5.0), "bank take: used count did not change (%s)" % used1):
		return false
	# M3b 審查 4：錢莊那一欄取空了 → 數字鍵換到身上那一欄（以前兩欄都沒有編號）
	if bw.bank_rows().is_empty() and not bw.carry_rows().is_empty():
		if not _check(bw.side == BankWindow.SIDE_CARRY, "bank: number keys stay on the empty bank list"):
			return false
	await ui.seconds(0.3)
	await ui.shot("m3b_bank_take")
	await ui.press_key(KEY_ESCAPE)
	await ui.wait_until(func(): return not bw.is_visible_in_tree(), 3.0)
	await _close_npc_dialog()
	# 4. 鏢局：托鏢／取貨／保鏢
	if not await _teleport("xx_biaoju"):
		return false
	# M3b 審查 3：取貨頁要有一筆真的貨（單機寄不了給自己 → debug 放一筆寄給自己、在西夏等你領的饅頭＋120 兩）
	if not _check(await _debug_set("consign_demo", "c_mantou") == "", "debug_set consign_demo"):
		return false
	var d4 := await _talk("鏢頭")
	if d4 == null:
		return false
	if not await ui.click_text("鏢局", "exact", d4):
		return false
	if not _check(await ui.wait_until(func(): return _window_open(EscortWindow) != null, 5.0), "鏢局 window did not open"):
		return false
	var ew := _window_open(EscortWindow)
	await ui.seconds(0.3)
	await ui.shot("m3b_escort_send")
	for t in ["TAKE", "JOB"]:
		var want_t: String = "Tab_" + t
		var tb := ui.find(func(c): return c is Button and str((c as Button).name) == want_t, ew)
		if not _check(tb != null, "escort tab %s missing" % t):
			return false
		await ui.click(tb)
		await ui.seconds(0.4)
		await ui.shot("m3b_escort_" + t.to_lower())
		if t == "TAKE":
			var find_tk := func() -> Button:
				return ui.find(func(c): return c is Button and str((c as Button).name).begins_with("Take_"), ew) as Button
			if not _check(await ui.wait_until(func(): return find_tk.call() != null, 5.0), "取貨 page lists no consignment to take"):
				return false
			var tk: Button = find_tk.call()
			await ui.shot("m3b_escort_take_goods")
			var m_before := int(UiClient.sheet().get("money", 0))
			await ui.click(tk)
			if not _check(await ui.wait_until(func(): return int(UiClient.sheet().get("money", 0)) >= m_before + 120, 5.0), "consign_take: money not received"):
				return false
			await ui.seconds(0.4)
			await ui.shot("m3b_escort_take_done")
	await ui.press_key(KEY_ESCAPE)
	await ui.wait_until(func(): return not ew.is_visible_in_tree(), 3.0)
	await _close_npc_dialog()
	# 5. 製作窗（西夏打鐵舖：打鐵、鑄劍；生活技能 1 級是設定）
	for sk in ["life_smithing", "life_swordsmith", "life_mining"]:
		if not _check(await _debug_set("skill:" + sk, 1) == "", "debug_set skill:" + sk):
			return false
	if not await _teleport("xx_tiepu"):
		return false
	if not await ui.click_text("指令(", "prefix"):
		return false
	if not _check(await ui.wait_until(func(): return _panel_open("指令"), 3.0), "指令 window did not open"):
		return false
	var cp := ui.find_by_class("CommandPanel")
	var ctb: TabBar = ui.find(func(c): return c is TabBar, cp) as TabBar if cp != null else null
	await ui.select_tab(ctb, UiCommands.TABS.find("ACTION"))
	if not await ui.click(ui.find_button("製作", "exact", cp, true)):
		return false
	if not _check(await ui.wait_until(func(): return _window_open(CraftWindow) != null, 5.0), "製作 window did not open"):
		return false
	var cw := _window_open(CraftWindow)
	if not _check(ui.find(func(c): return c is Button and str((c as Button).name).begins_with("Recipe_"), cw) != null, "craft window lists no recipes"):
		return false
	await ui.seconds(0.3)
	await ui.shot("m3b_craft")
	await ui.press_key(KEY_ESCAPE)
	await ui.wait_until(func(): return not cw.is_visible_in_tree(), 3.0)
	var pc := ui.find_button("關閉(Esc)")
	if pc != null:
		await ui.click(pc)
		await ui.seconds(0.2)
	# 6. 組織：衙門書吏創立 → 組織面板
	if not _check(await _debug_set("fame", 150) == "", "debug_set fame"):
		return false
	if not _check(await _debug_set("money", 20000) == "", "debug_set money"):
		return false
	if not await _teleport("xx_yamen"):
		return false
	var d6 := await _talk("衙門書吏")
	if d6 == null:
		return false
	if not await ui.click_text("組織", "exact", d6):
		return false
	if not _check(await ui.wait_until(func(): return _window_open(OrgPanel) != null, 5.0), "書吏 → 組織 did not open the clerk page"):
		return false
	var op := _window_open(OrgPanel)
	var fe := ui.find(func(c): return c is LineEdit and str((c as LineEdit).name) == "FoundName", op) as LineEdit
	if not _check(fe != null, "clerk page has no name box"):
		return false
	await ui.type_text(fe, "介面幫")
	await ui.seconds(0.2)
	await ui.shot("m3b_org_clerk")
	var fb := ui.find(func(c): return c is Button and str((c as Button).name) == "Found", op) as Button
	if not await ui.click(fb):
		return false
	if not _check(await ui.wait_until(func(): return _log_contains("介面幫"), 5.0), "org_found produced no message"):
		return false
	# M3b 審查：書吏頁跟著更新（清單裡有自己的連署、創立灰掉、上半部顯示連署中）
	var clerk_has := func() -> bool:
		var txt := ""
		for l in op.find_children("*", "Label", true, false):
			txt += (l as Label).text
		var fb2 := ui.find(func(c): return c is Button and str((c as Button).name) == "Found", op) as Button
		return txt.contains("「介面幫」") and fb2 != null and fb2.disabled and not txt.contains("你不在任何組織裡")
	if not _check(await ui.wait_until(clerk_has, 5.0), "clerk page did not refresh after org_found"):
		return false
	await ui.seconds(0.3)
	await ui.shot("m3b_org_petition")
	await ui.press_key(KEY_ESCAPE)
	await ui.wait_until(func(): return not op.is_visible_in_tree(), 3.0)
	await _close_npc_dialog()
	if not await ui.click_text("指令(", "prefix"):
		return false
	await ui.wait_until(func(): return _panel_open("指令"), 3.0)
	cp = ui.find_by_class("CommandPanel")
	ctb = ui.find(func(c): return c is TabBar, cp) as TabBar if cp != null else null
	await ui.select_tab(ctb, UiCommands.TABS.find("GUILD"))
	if not await ui.click(ui.find_button("組織", "exact", cp, true)):
		return false
	if not _check(await ui.wait_until(func(): return _window_open(OrgPanel) != null, 5.0), "指令 → 組織 did not open the org panel"):
		return false
	await ui.seconds(0.3)
	# M3b 審查：連署中的發起人看得到「撤回連署」
	if not _check(await ui.wait_until(func(): return ui.find_button("撤回連署", "exact", _window_open(OrgPanel)) != null, 5.0),
			"org panel has no 撤回連署 for the petition founder"):
		return false
	await ui.shot("m3b_org_panel")
	await ui.press_key(KEY_ESCAPE)
	await ui.wait_until(func(): return _window_open(OrgPanel) == null, 3.0)
	pc = ui.find_button("關閉(Esc)")
	if pc != null:
		await ui.click(pc)
	# M3b 審查 3：組織邀請提示（單機沒有別的玩家 → debug 建一個示範組織邀請自己），拍完按拒絕
	if not _check(await _debug_set("org_invite_demo", "青龍會") == "", "debug_set org_invite_demo"):
		return false
	var prompt_of := func() -> Control:
		return ui.find(func(c): return c is Control and str((c as Control).name) == "Prompt_org_debug_demo_org" and (c as Control).is_visible_in_tree())
	if not _check(await ui.wait_until(func(): return prompt_of.call() != null, 5.0), "org_invite prompt did not show"):
		return false
	# M3b 審查 4：自己有連署中的組織 → 提示多一行「接受後你發起的連署…將作廢」
	if not _check(ui.find(func(c): return c is Label and str((c as Label).name) == "OrgWarn" and (c as Label).text.contains("作廢"), prompt_of.call()) != null,
			"org_invite prompt has no petition warning"):
		return false
	await ui.seconds(0.3)
	await ui.shot("m3b_org_invite")
	await ui.click(ui.find_button("拒絕", "exact", prompt_of.call(), true))
	await ui.wait_until(func(): return prompt_of.call() == null or ui.find_button("拒絕", "exact", prompt_of.call(), true) == null, 5.0)
	if not _check(await _debug_set("org_demo_clear", 1) == "", "debug_set org_demo_clear"):
		return false
	# 連署直接成立（debug）→ 組織面板：成員名單、選自己 → 幫主的動作列（審查：一行裝不下，拆成三行）
	if not _check(await _debug_set("org_activate", 1) == "", "debug_set org_activate"):
		return false
	if not await ui.click_text("指令(", "prefix"):
		return false
	await ui.wait_until(func(): return _panel_open("指令"), 3.0)
	cp = ui.find_by_class("CommandPanel")
	ctb = ui.find(func(c): return c is TabBar, cp) as TabBar if cp != null else null
	await ui.select_tab(ctb, UiCommands.TABS.find("GUILD"))
	if not await ui.click(ui.find_button("組織", "exact", cp, true)):
		return false
	if not _check(await ui.wait_until(func(): return _window_open(OrgPanel) != null, 5.0), "指令 → 組織 did not reopen the org panel"):
		return false
	var opa := _window_open(OrgPanel)
	var my_name := str(UiClient.sheet().get("name", ""))
	if not _check(await ui.wait_until(func(): return ui.find_button(my_name, "contains", opa, true) != null, 5.0),
			"active org panel lists no member %s" % my_name):
		return false
	await ui.click(ui.find_button(my_name, "contains", opa, true))
	if not _check(await ui.wait_until(func(): return ui.find(func(c): return c is Button and str((c as Button).name) == "Act_lead", opa) != null, 5.0),
			"active org panel has no leader actions"):
		return false
	await ui.seconds(0.3)
	# 每一列動作都要在對話框內（審查：700px 對話框裝不下一整行）
	var dlg_rect := opa.get_global_rect()
	for id in ["kick", "set_rank", "title", "lead", "disband", "leave"]:
		var want_id: String = "Act_" + str(id)
		var ab := ui.find(func(c): return c is Button and str((c as Button).name) == want_id, opa) as Button
		if ab != null and not _check(dlg_rect.encloses(ab.get_global_rect()), "org action %s overflows the dialog" % id):
			return false
	# M3b 審查 4：選到自己（幫主）時位階下拉也停用
	var rp := ui.find(func(c): return c is OptionButton and str((c as OptionButton).name) == "RankPick", opa) as OptionButton
	if rp != null and not _check(rp.disabled, "org rank dropdown is enabled with yourself selected"):
		return false
	await ui.shot("m3b_org_active")
	await ui.press_key(KEY_ESCAPE)
	await ui.wait_until(func(): return _window_open(OrgPanel) == null, 3.0)
	pc = ui.find_button("關閉(Esc)")
	if pc != null:
		await ui.click(pc)
	print("[UiPlay] M3b screens done")
	return true

## 乞討的等級＋熟練（看 sheet.skills；格式容錯）
func _qitao_prof() -> int:
	var sk: Variant = UiClient.sheet().get("skills", [])
	if sk is Array:
		for e in sk:
			if e is Dictionary and str(e.get("id", "")) == "qitao":
				return int(e.get("level", 0)) * 100000 + int(e.get("prof", 0))
	elif sk is Dictionary and (sk as Dictionary).has("qitao"):
		var e2: Variant = sk["qitao"]
		if e2 is Dictionary:
			return int(e2.get("level", 0)) * 100000 + int(e2.get("prof", 0))
		return int(e2) * 100000
	return 0

func _teleport(room: String) -> bool:
	if not _check(await _debug_set("teleport", room) == "", "debug_set teleport %s" % room):
		return false
	return _check(await ui.wait_until(func(): return _room_id() == room, 5.0), "teleport to %s: still in %s" % [room, _room_id()])

## 送信路上遇到的戰鬥不一定把 防／休／攻／移 都用到：不夠就在大理郊外（北門大道 ⇄ 洱海邊，只有野兔）來回走到遇敵
## 截圖模式另外要拍到一張勝利畫面
func _go_wild_and_fight() -> bool:
	_step(13, "大理郊外來回走（指令列覆蓋：%s）" % str(used_cmds))
	var moves := 0
	var shot_wild := false
	while moves < MAX_WILD_MOVES:
		if _done:
			return false
		if _battle() != null and not await _fight():
			return false
		var need_victory := ui.shots_dir != "" and not ui.is_headless() and victories == 0
		if (_coverage_done() and not need_victory) or battles >= MAX_BATTLES:
			break
		if not (_room_id() in ["dlw_road", "dlw_lake"]):
			if not await _goto("dlw_road"):
				return false
			continue
		if not shot_wild:
			shot_wild = true
			await ui.shot("wild")
		if not await _ensure_healthy():
			return false
		if not (_room_id() in ["dlw_road", "dlw_lake"]):
			continue
		if not await _walk("西" if _room_id() == "dlw_road" else "東"):
			return false
		await ui.wait_until(func(): return _battle() != null, 0.15)
		moves += 1
	if not _check(battles > 0, "no encounter after %d moves" % moves):
		return false
	if not _check(used_cmds.has("攻"), "never got to use 攻 in %d battles" % battles):
		return false
	if not _check(used_cmds.has("移"), "never got to use 移 in %d battles" % battles):
		return false
	if m3a_ready:
		for t in M3A_CMDS:
			if not _check(used_cmds.has(t), "M3a: never pressed 「%s」 in %d battles: %s" % [t, battles, str(used_cmds)]):
				return false
	return _check(used_cmds.has("防") and used_cmds.has("休"), "防/休 not both used: %s" % str(used_cmds))

## 物品堆疊（擁有者截圖：兔皮被拆成 5 格）：記下每種會腐壞的原料件數增加了幾次（每場戰鬥的掉落各算一次）
func _track_pelts(sheet: Dictionary) -> void:
	var now := {}
	for it in sheet.get("inventory", []):
		if it is Dictionary and bool(it.get("perishable", false)) and str(it.get("tab", "")) == "MATERIAL":
			var iid := str(it.get("id", ""))
			now[iid] = int(now.get(iid, 0)) + int(it.get("n", 0))
	for iid in now:
		if int(now[iid]) > int(pelt_total.get(iid, 0)):
			pelt_gains[iid] = int(pelt_gains.get(iid, 0)) + 1
	pelt_total = now

func _pelt_id_two_battles() -> String:
	var ids := pelt_gains.keys()
	ids.sort()
	for iid in ids:
		if int(pelt_gains[iid]) >= 2 and int(pelt_total.get(iid, 0)) > 0:
			return str(iid)
	return ""

## 兩場以上戰鬥掉的同一種皮（會腐壞）在裝備窗「原料」分頁只佔一格，而且滑鼠提示有新鮮度
func _pelts_one_slot() -> bool:
	_step(17, "物品堆疊：兩場戰鬥的獸皮同一格（%s）" % str(pelt_gains))
	var extra := 0
	var moves := 0
	while _pelt_id_two_battles() == "" and extra < MAX_PELT_BATTLES and moves < MAX_WILD_MOVES:
		if _done:
			return false
		if _battle() != null:
			extra += 1
			if not await _fight():
				return false
			continue
		if not (_room_id() in ["dlw_road", "dlw_lake"]):
			if not await _goto("dlw_road"):
				return false
			continue
		if not await _ensure_healthy():
			return false
		if not (_room_id() in ["dlw_road", "dlw_lake"]):
			continue
		if not await _walk("西" if _room_id() == "dlw_road" else "東"):
			return false
		await ui.wait_until(func(): return _battle() != null, 0.15)
		moves += 1
	var iid := _pelt_id_two_battles()
	if not _check(iid != "", "no pelt dropped in 2+ battles after %d extra battles: %s" % [extra, str(pelt_gains)]):
		return false
	var nm := str(UiClient.row("items", iid).get("name", iid))
	if not await ui.click_text("裝備(", "prefix"):
		return false
	if not _check(await ui.wait_until(func(): return _panel_open("裝備"), 3.0), "裝備 window did not open"):
		return false
	var inv := ui.find_by_class("InventoryPanel")
	var tb: TabBar = ui.find(func(c): return c is TabBar, inv) as TabBar if inv != null else null
	if not _check(tb != null, "inventory TabBar not found"):
		return false
	await ui.select_tab(tb, UiKeys.INV_TABS.find("MATERIAL"))
	await ui.frames(2)
	var slots: Array = []
	for b in ui.find_all(func(c): return c is Button and c.has_meta("item_uid") and (c as Button).tooltip_text.begins_with(nm + " ×"), inv):
		slots.append(b)
	print("[UiPlay] %s (%s) gains=%d total=%d slots=%d" % [nm, iid, int(pelt_gains[iid]), int(pelt_total.get(iid, 0)), slots.size()])
	if not _check(slots.size() == 1, "%s from %d battles occupies %d slots (want 1)" % [nm, int(pelt_gains[iid]), slots.size()]):
		return false
	var tip: String = (slots[0] as Button).tooltip_text
	if not _check(tip.contains("最早一批剩") and tip.contains("會腐壞"), "slot tooltip has no freshness line: 「%s」" % tip):
		return false
	await ui.shot("pelts_one_slot")
	if not await ui.click_text("關閉(Esc)"):
		return false
	return _check(await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0), "裝備 window did not close")

func _cmd_button(battle: Control, text: String) -> Button:
	return ui.find_button(text, "exact", battle)

func _bar_enabled(battle: Control) -> bool:
	for t in CMD_TEXTS:
		var b := _cmd_button(battle, t)
		if b != null and not b.disabled:
			return true
	return false

func _turn_text(battle: Control) -> String:
	var l := ui.find(func(c): return c is Label and ((c as Label).text.begins_with("蓄勢") or (c as Label).text.begins_with("輪到你") \
		or (c as Label).text.begins_with("等待") or (c as Label).text == "戰鬥結束"), battle) as Label
	return l.text if l != null else "?"

func _battle_log(battle: Control) -> String:
	var r := ui.find(func(c): return c is RichTextLabel, battle) as RichTextLabel
	return r.get_parsed_text() if r != null else ""

func _result_shown(battle: Control) -> bool:
	var rp: Variant = battle.get("result_panel")
	return rp is Control and (rp as Control).visible

func _grid(battle: Control) -> Control:
	return ui.find_by_class("BattleIsoView", battle)

## 打一場：只用指令列與格子點擊
func _fight() -> bool:
	battles += 1
	_step(9, "battle %d" % battles)
	var battle := _battle()
	await ui.frames(2)
	if not _check_battle_view(battle):
		return false
	await ui.shot("battle_%d_start" % battles)
	var t_battle := Time.get_ticks_msec()
	var t_turn := Time.get_ticks_msec()
	var turn := 0
	while true:
		if _done:
			return false
		if not is_instance_valid(battle):
			return _check(false, "battle screen vanished before result")
		if _battle_log(battle).contains(TIMEOUT_TEXT):
			return _check(false, "battle log shows a server timeout (「%s」): UI never let the player act; turn label=%s" % [TIMEOUT_TEXT, _turn_text(battle)])
		if _result_shown(battle):
			break
		if Time.get_ticks_msec() - t_battle > int(BATTLE_TIMEOUT_S * 1000.0):
			return _check(false, "battle did not end in %d s" % int(BATTLE_TIMEOUT_S))
		if not _bar_enabled(battle):
			if Time.get_ticks_msec() - t_turn > int(TURN_TIMEOUT_S * 1000.0):
				return _check(false, "command bar not enabled within %.0f s (turn label「%s」, turn %d)" % [TURN_TIMEOUT_S, _turn_text(battle), turn])
			await ui.frames(1)
			continue
		turn += 1
		turns_total += 1
		var accepted := await _take_turn(battle, turn)
		if _done:
			return false
		if not accepted:
			return _check(false, "battle command was not accepted on turn %d" % turn)
		t_turn = Time.get_ticks_msec()
	var result_label: Label = battle.get("result_label")
	print("[UiPlay] battle %d result: %s after %d turns (cmds %s)" % [battles, result_label.text if result_label else "?", turn, str(used_cmds)])
	var detail: Variant = battle.get("result_detail")
	if detail is Label and not _check(not (detail as Label).text.contains("+0"), "result shows zero rewards: %s" % (detail as Label).text):
		return false
	var won := result_label != null and result_label.text.contains("勝")
	if won:
		victories += 1
	# M3c（M3C_PLAN §6.7）：打寶那一場——結果框物品依稀有度標「【珍品】」、標題下金字「得到寶物！」
	if m3c_loot_battle and won:
		battle.set("return_at_ms", -1)   # 先停住自動返回再檢查、截圖
		var tl: Variant = battle.get("treasure_label")
		var rd: Variant = battle.get("result_detail")
		var rd_text := (rd as RichTextLabel).get_parsed_text() if rd is RichTextLabel else (str((rd as Label).text) if rd is Label else "")
		m3c_loot_ok = tl is Label and (tl as Label).visible and rd_text.contains("珍品")
		print("[UiPlay] M3c loot result: treasure_label=%s detail「%s」" % [str((tl as Label).visible) if tl is Label else "-", rd_text.replace("
", " / ")])
		await ui.seconds(0.7)
		await ui.shot("m3c_loot_result")
	# 原作沒有結算畫面：結果小條出來約 AUTO_RETURN_S 秒後自動回到主畫面；第一場驗證自動返回，之後按「返回」
	if auto_returned == 0 and int(battle.get("return_at_ms")) >= 0:
		await ui.shot("battle_%d_%s_strip" % [battles, "victory" if won else "result"])
		if not _check(await ui.wait_until(func(): return _battle() == null, BattleScreen.AUTO_RETURN_S + 3.0),
				"battle did not auto-return %.1f s after the result" % BattleScreen.AUTO_RETURN_S):
			return false
		auto_returned += 1
		print("[UiPlay] battle %d auto-returned" % battles)
		return true
	if ui.shots_dir != "" and not ui.is_headless():
		battle.set("return_at_ms", -1)   # 截圖時先停住自動返回
	await ui.shot("battle_%d_%s" % [battles, "victory" if won else "result"])
	if _battle() == null:
		return true   # 截圖期間已經自動返回
	# 自動返回開著時小條沒有「返回」鈕（規格 §12.1）；任意鍵立刻返回
	if not _check(not (battle.get("return_button") as Button).visible, "result strip shows 返回 while auto-return is on"):
		return false
	await ui.press_key(KEY_ENTER)
	return _check(await ui.wait_until(func(): return _battle() == null, 5.0), "battle screen did not close after a key press")

## 這一回合該不該逃：對手有難纏怪（野狼、山豬、山賊），或自己的氣不到三成（同 balance_sim 的 p0_walk 新手策略，WORLD_2001 §1.4 規則 7）
func _should_flee(battle: Control) -> bool:
	var grid := _grid(battle)
	var vm: Variant = grid.get("vm") if grid != null else null
	if vm == null or (vm.escape as Array).is_empty():
		return false
	for uid in vm.order:
		if vm.is_active(uid) and vm.is_enemy(uid) and BattleIsoView.unit_ref(vm.units[uid]) in FLEE_FROM:
			return true
	var me: Dictionary = vm.me()
	return int(me.get("qi", 0)) * 10 < int(me.get("qi_max", 1)) * 3

## 選指令：難纏怪或氣太低就往逃跑格走、站上去按「逃」（新手打不過野狼，原作也是逃）；
## 否則第 1 回合 防、第 2 回合 休，之後能攻就攻（點相鄰敵人），不能就移（點最靠近敵人的格子）
func _take_turn(battle: Control, turn: int) -> bool:
	var choice := "防"
	var flee := _should_flee(battle)
	if flee and _enabled(battle, "逃"):
		choice = "逃"
	elif flee and _enabled(battle, "移"):
		choice = "移"
		flee_move = true
	elif flee and _enabled(battle, "攻"):
		choice = "攻"
	elif flee:
		choice = "防"
	elif _m3a_choice(battle) != "":
		choice = _m3a_choice(battle)
	elif not used_cmds.has("防"):
		choice = "防"
	elif not used_cmds.has("休"):
		choice = "休"
	elif _enabled(battle, "攻"):
		choice = "攻"
	elif _enabled(battle, "移"):
		choice = "移"
	if not _enabled(battle, choice):
		choice = "防"
	if m3a_ready and not shot_badge and used_cmds.has("毒"):
		shot_badge = true
		# 毒沒下中（被避開、抵抗）時也要拍到狀態圓牌：在畫面的模型上給一個敵人掛「中毒」再拍（只影響本機畫面，
		# 不送主機；下一個快照就會蓋回主機的真實狀態）。M3a 審查 C8：以前沒中就沒有這張圖
		var forced := false
		if not _any_status(battle):
			forced = _force_status_badge(battle)
		await ui.frames(2)
		# 敵人名字牌左邊的「毒」圓牌。毒沒下中、是畫面上硬掛的 → 檔名加 _forced（戰報會寫「落空」，不要誤會成真的中毒；M3a UI 審查 #5）
		await ui.shot("m3a_status_badge_forced" if forced else "m3a_status_badge")
		if not _check(_any_status(battle) or not forced, "status badge was not shown"):
			return false
	if m3a_ready and not shot_inner_full and _me_full(battle) and _enabled(battle, "內"):
		if not await _shot_inner_full(battle):
			return false
	if turn == 1:
		await ui.shot("battle_%d_your_turn" % battles)   # 指令列亮起的樣子
		# Ctrl+1 是「屬性」快捷鍵：戰鬥中不能變成「移」，也不能在戰鬥畫面下開面板
		await ui.press_key(KEY_1, true)
		var grid := _grid(battle)
		if not _check(grid != null and (grid.get("highlight") as Array).is_empty() and str(battle.get("mode")) == "",
				"Ctrl+1 entered a battle mode (mode=%s)" % str(battle.get("mode"))):
			return false
		if not _check(ui.find_button("關閉(Esc)") == null and not _panel_open("屬性"), "Ctrl+1 opened a panel during battle"):
			return false
	var ok := await _issue(battle, choice)
	flee_move = false
	if not ok and choice != "防" and not _done:
		ui.warn("turn %d: %s not accepted, falling back to 防" % [turn, choice])
		ui.last_error = ""
		ok = await _issue(battle, "防")
		choice = "防"
	if ok:
		used_cmds[choice] = int(used_cmds.get(choice, 0)) + 1
		if choice in ["攻", "移"] and int(used_cmds[choice]) == 1:
			await ui.shot("battle_%d_turn%d_%s" % [battles, turn, choice])
		if choice in M3A_CMDS:
			print("[UiPlay] M3a: 「%s」 accepted in battle %d turn %d" % [choice, battles, turn])
	return ok

## 還沒按過、現在可以按的 內／醫／毒（毒要有相鄰的敵人；內、醫要氣沒滿——滿血療傷會被灰掉，M3a 審查）
func _m3a_choice(battle: Control) -> String:
	if not m3a_ready:
		return ""
	for t in M3A_CMDS:
		if used_cmds.has(t) or not _enabled(battle, t):
			continue
		if t in ["內", "醫"] and _me_full(battle):
			continue
		if t == "毒":
			var grid := _grid(battle)
			var vm: Variant = grid.get("vm") if grid != null else null
			if vm == null or (vm.enemy_cells_within(1) as Array).is_empty():
				continue
		return t
	return ""

func _me_full(battle: Control) -> bool:
	var grid := _grid(battle)
	var vm: Variant = grid.get("vm") if grid != null else null
	if vm == null:
		return false
	var me: Dictionary = vm.me()
	return int(me.get("qi", 0)) >= int(me.get("qi_max", 1))

## 畫面模型上給第一個活著的敵人掛「中毒」（只為了拍狀態圓牌）；回傳有沒有掛上
func _force_status_badge(battle: Control) -> bool:
	var grid := _grid(battle)
	var vm: Variant = grid.get("vm") if grid != null else null
	if vm == null:
		return false
	for uid in vm.order:
		var u: Dictionary = vm.unit(uid)
		if vm.is_active(uid) and int(u.get("side", 0)) != vm.my_side():
			if not (u.get("statuses") is Dictionary):
				u["statuses"] = {}
			u["statuses"]["poison"] = BattleViewModel.status_entry("poison", "", -1, 2)
			grid.queue_redraw()
			print("[UiPlay] forced a 中毒 badge on uid %d for the screenshot" % int(uid))
			return true
	return false

func _any_status(battle: Control) -> bool:
	var grid := _grid(battle)
	var vm: Variant = grid.get("vm") if grid != null else null
	if vm == null:
		return false
	for uid in vm.order:
		if vm.is_active(uid) and not (vm.unit_statuses(uid) as Array).is_empty():
			return true
	return false

## 滿血時打開「內」：「運功療傷」要灰掉並寫「氣血已滿」；拍照後關掉選單（不花這一回合）
func _shot_inner_full(battle: Control) -> bool:
	shot_inner_full = true
	if not await ui.click(_cmd_button(battle, "內")):
		return false
	var opened := func() -> bool:
		return (battle.call("menu_texts") as Array).size() > 0
	if not await ui.wait_until(opened, 2.0):
		return _check(false, "內 menu did not open at full health")
	var texts: Array = battle.call("menu_texts")
	if not _check(str(texts[0]).contains("氣血已滿") and ui.find_button("運功療傷", "exact", battle, true) == null,
			"full health: 運功療傷 should be greyed with 氣血已滿 (menu %s)" % str(texts)):
		return false
	await ui.shot("m3a_inner_full")
	battle.call("cancel_mode")
	await ui.frames(2)
	return true

func _enabled(battle: Control, t: String) -> bool:
	var b := _cmd_button(battle, t)
	return b != null and not b.disabled

## 按指令（需要目標的會等格子高亮再點）；回傳指令是否被接受（指令列變灰）
func _issue(battle: Control, t: String) -> bool:
	if not await ui.click(_cmd_button(battle, t)):
		return false
	if t == "內":
		# 小選單「運功」：四種運功，不能用的灰掉並附原因；選「運功療傷」
		var heal := "運功療傷"
		if not await ui.wait_until(func(): return ui.find_button(heal, "exact", battle, true) != null, 2.0):
			ui.error("內: no enabled「%s」in the menu (menu: %s)" % [heal, str(battle.call("menu_texts"))])
			return false
		await ui.shot("m3a_inner_menu")
		if not await ui.click(ui.find_button(heal, "exact", battle, true)):
			return false
	if t in ["攻", "移", "醫", "毒"]:
		var grid := _grid(battle)
		if grid == null:
			return _check(false, "battle grid not found")
		if not await ui.wait_until(func(): return not (grid.get("highlight") as Array).is_empty(), 2.0):
			ui.error("%s: no highlighted cells" % t)
			return false
		var cell := _pick_cell(grid, t)
		if t == "移" and not shot_move_hl:
			shot_move_hl = true
			await ui.shot("battle_%d_my_turn_move_highlight" % battles)   # 輪到我、移動範圍高亮
		if t == "攻" and not shot_atk_hl:
			shot_atk_hl = true
			await ui.shot("battle_%d_attack_target_highlight" % battles)   # 按「攻」後可打的目標格高亮
		if t == "醫":
			await ui.shot("m3a_medic_target")    # 綠框：自己或隊友
		if t == "毒":
			await ui.shot("m3a_poison_target")   # 藍色射程＋紅框敵人
		# 等角格子：用 cell_center 取菱形中心，並確認反查回同一格
		var at: Vector2 = grid.call("cell_center", cell)
		if not _check(grid.call("cell_at", at) == cell, "cell_center/cell_at mismatch for %s" % str(cell)):
			return false
		await ui.click_local(grid, at)
		last_click = "%s cell %s at %s (global %s), highlight %s, hovered %s" % [t, str(cell), str(at), str(grid.get_global_transform() * at),
			str(grid.get("highlight")), ui.describe(ui.hovered_control()) if ui.hovered_control() != null else "?"]
	# 被接受：整排指令變灰（送出中／已下令）；被拒：會再亮起
	var ok := await ui.wait_until(func(): return not is_instance_valid(battle) or not _bar_enabled(battle) or _result_shown(battle), 3.0)
	# 先確認被接受再等出手動畫拍照（等待中下一回合可能已亮起，不能拿來判斷是否被接受）
	if ok and t == "攻" and not shot_strike and ui.shots_dir != "" and not ui.is_headless() and is_instance_valid(battle):
		await _shot_strike(battle, _grid(battle))
	if ok and t == "攻" and m3c_fx_shot_kind != "" and is_instance_valid(battle):
		await _shot_weapon_fx(battle, m3c_fx_shot_kind)   # M3c：武器特效正在畫的那一刻
	if not ok:
		ui.error("%s: command bar still enabled 3 s after issuing (turn label「%s」; %s; log tail「%s」)" % [t, _turn_text(battle), last_click,
			_battle_log(battle).right(160).replace("
", " / ")])
	return ok

## 出手動畫拍照：等我打中敵人的傷害飄字（敵方頭上「-N」）剛出現（我還在前衝）時截圖；閃避就留到下次攻擊
func _shot_strike(battle: Control, grid: Control) -> void:
	var fx: Variant = grid.get("fx")
	if fx == null:
		return
	var hit := func() -> bool:
		if not is_instance_valid(battle):
			return true
		var now := BattleIsoView.now_s()
		for it in (fx.get("items") as Array):
			var on_enemy := is_instance_valid(it["sprite"]) and not bool(it["sprite"].get("ally"))
			if on_enemy and str(it["type"]) == "text" and str(it["text"]).begins_with("-") and now >= float(it["start"]) and now - float(it["start"]) < 0.2:
				return true
		return false
	if await ui.wait_until(hit, 3.0) and is_instance_valid(battle):
		shot_strike = true
		await ui.shot("battle_%d_attack_lunge_damage" % battles)

## 戰場呈現檢查：等角戰場、每個單位都是立繪（UnitSprite 有 idle 圖，不是圓形棋子）、頭上名字是完整名字、
## 背景是這場戰鬥所在地區的圖、時間棒的名字也沒被截斷
func _check_battle_view(battle: Control) -> bool:
	var grid := _grid(battle)
	if not _check(grid != null, "BattleIsoView not found in battle screen"):
		return false
	if not _check(ui.find_by_class("BattleGridView", battle, false) == null, "old flat BattleGridView still present"):
		return false
	for t in M3A_BUTTONS:
		if not _check(_cmd_button(battle, t) != null, "M3a: no「%s」button on the battle command bar" % t):
			return false
	var vm: Variant = grid.get("vm")
	var sprites: Dictionary = grid.get("sprites")
	if not _check(vm != null and not (vm.order as Array).is_empty(), "battle view has no units"):
		return false
	var desc: Array = []
	for uid in vm.order:
		var u: Dictionary = vm.units[uid]
		var full := str(u.get("name", ""))
		var s: Variant = sprites.get(uid)
		if not _check(s != null and ui.class_of(s) == "UnitSprite", "unit %s (%s) has no UnitSprite" % [str(uid), full]):
			return false
		if not _check(bool(s.call("has_art")), "unit %s「%s」is drawn without a sprite texture (ref=%s)" % [str(uid), full, BattleIsoView.unit_ref(u)]):
			return false
		if not _check(str(s.get("display_name")) == full and full.length() >= 2, "unit name truncated: shown「%s」full「%s」" % [str(s.get("display_name")), full]):
			return false
		# 右側時間棒清單是系統窗選項（ui.atb_list，預設關）：開著時名字也不能被截斷
		var gp: Variant = battle.get("gauge_panel")
		if gp is Control and (gp as Control).is_visible_in_tree():
			var name_l := ui.find(func(c): return c is Label and (c as Label).text == full, gp) as Label
			if not _check(name_l != null and not name_l.clip_text and name_l.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING,
					"gauge list does not show the full name「%s」" % full):
				return false
		desc.append("%s(%s%s)" % [full, BattleIsoView.unit_ref(u), "" if not ArtRegistry.is_placeholder(BattleIsoView.unit_ref(u), str(u.get("kind", ""))) else ",placeholder"])
	var rid := str(UiClient.region_view().get("region", ""))
	if not _check(rid != "" and str(grid.get("region_id")) == rid, "battle region「%s」!= current region「%s」" % [str(grid.get("region_id")), rid]):
		return false
	var bg: Variant = grid.get("bg_tex")
	if not _check(bg != null and bg == ArtRegistry.battle_background(rid), "battle background is not the art for region %s" % rid):
		return false
	print("[UiPlay] battle view: region=%s units=%s" % [rid, ", ".join(desc)])
	return true

## 攻：第一個高亮的敵人格；移：離最近敵人最近的高亮格（逃跑中：離最近逃跑格最近的高亮格）
func _pick_cell(grid: Control, t: String) -> Vector2i:
	var cells: Array = grid.get("highlight")
	if t == "攻" or t == "毒":
		return cells[0]
	if t == "醫":
		var vm0: Variant = grid.get("vm")
		var mine: Vector2i = vm0.me().get("pos", cells[0]) if vm0 != null else cells[0]
		return mine if mine in cells else cells[0]
	var enemies: Array = []
	var vm: Variant = grid.get("vm")
	if vm != null and flee_move:
		enemies.assign(vm.escape)
	elif vm != null:
		for uid in vm.order:
			if vm.is_active(uid) and vm.is_enemy(uid):
				enemies.append(vm.units[uid]["pos"])
	var best: Vector2i = cells[0]
	var best_d := 1 << 30
	for c in cells:
		var d := 1 << 30
		for e in enemies:
			d = mini(d, absi(c.x - e.x) + absi(c.y - e.y))
		if d < best_d:
			best_d = d
			best = c
	return best

# ---------- M3c（M3C_PLAN §12.4）：造型、跨區趕路、小地圖「往XXX」、攻擊 NPC 確認框、滅派、武器特效、打寶結果與 8 格裝備 ----------
## 只在 --debug-intents（m3a_ready）時跑（之前的步驟已把角色移來移去；這裡的 teleport／debug_set 是設定，不是受測物）。
var m3c_fx_seen: Dictionary = {}       # 戰鬥畫面出現過的武器特效 kind（_process 輪詢 BattleFx.items）
var m3c_fx_shot_kind := ""             # 下一次「攻」被接受後，等這種特效出現就拍照
var m3c_loot_battle := false           # 這一場要檢查結果框的稀有度上色
var m3c_loot_ok := false
var _fx_poll_t := 0.0
var _fx_shooting := false
var m3c_fx_shot_taken: Dictionary = {}   # kind → 截圖已存

func _take_fx_shot(kind: String) -> void:
	_fx_shooting = true
	await ui.shot("m3c_weapon_fx_" + kind)
	m3c_fx_shot_taken[kind] = true
	if m3c_fx_shot_kind == kind:
		m3c_fx_shot_kind = ""
	_fx_shooting = false

func _process(delta: float) -> void:
	_fx_poll_t -= delta
	if _fx_poll_t > 0.0 or ui == null or _done:
		return
	_fx_poll_t = 0.03
	var grid := ui.find_by_class("BattleIsoView")
	if grid == null:
		return
	var fx: Variant = grid.get("fx")
	if fx == null:
		return
	var now := BattleIsoView.now_s()
	for it in (fx.get("items") as Array):
		if it is Dictionary and str(it.get("type", "")) == "weapon":
			m3c_fx_seen[str(it.get("kind", ""))] = true
			# M3c 第三輪審查：拍照改在這裡輪詢（以前只在「攻」被接受之後等 3 秒；一刀打死野兔時戰鬥先結束、
			# 特效被拉到現在播完，等待落空又不報錯 → 劍的截圖默默不見）
			if m3c_fx_shot_kind != "" and not _fx_shooting and str(it.get("kind", "")) == m3c_fx_shot_kind 					and now >= float(it["start"]) + 0.03 and now <= float(it["start"]) + float(it["dur"]) - 0.05:
				_take_fx_shot(m3c_fx_shot_kind)

## 「攻」被接受之後：等指定種類的武器特效正在畫（出現後、淡出前）時拍照
func _shot_weapon_fx(battle: Control, kind: String) -> void:
	var grid := _grid(battle)
	var fx: Variant = grid.get("fx") if grid != null else null
	if fx == null:
		return
	var showing := func() -> bool:
		if not is_instance_valid(battle):
			return true
		var now := BattleIsoView.now_s()
		for it in (fx.get("items") as Array):
			if str(it.get("type", "")) == "weapon" and str(it.get("kind", "")) == kind and now >= float(it["start"]) + 0.05 \
					and now <= float(it["start"]) + float(it["dur"]) - 0.08:
				return true
		return false
	# 截圖由 _process 在特效正在畫的那一刻拍（_take_fx_shot）；這裡只等它拍完，沒拍到就重試下一次「攻」
	if await ui.wait_until(func(): return m3c_fx_shot_taken.has(kind) or not is_instance_valid(battle), 3.0) and is_instance_valid(battle):
		return
	if is_instance_valid(battle) and not m3c_fx_shot_taken.has(kind) and showing.call() == false:
		print("[UiPlay] M3c: %s fx not caught after this 攻 — will retry on the next one" % kind)

func _map_panel() -> Control:
	return ui.find_by_class("MapPanel", null, false)

func _confirm_dialog() -> Control:
	var d := ui.find_by_class("ConfirmDialog")
	return d if d != null and d.is_visible_in_tree() else null

func _npc_button(npc_name: String) -> Button:
	return ui.find_button(npc_name, "prefix", _npcs_box())

func _m3c_screens() -> bool:
	if not m3a_ready:
		return true
	_step(21, "M3c 畫面：造型、趕路、小地圖往XXX、攻擊 NPC、滅派、武器特效、打寶")
	if _battle() != null and not await _fight():
		return false
	for f in [_m3c_look_dialog, _m3c_world_route, _m3c_minimap_edge, _m3c_npc_attack, _m3c_weapon_fx, _m3c_loot]:
		if _done:
			return false
		if not await f.call():
			return false
		if _battle() != null and not await _fight():
			return false
	return true

## 屬性窗「更換造型」→ LookDialog（入派中有提示）→ 點第 6 格 → 確定 → sheet.appearance
func _m3c_look_dialog() -> bool:
	print("[UiPlay] M3c: 更換造型")
	if not await ui.click_text("屬性(", "prefix"):
		return false
	if not _check(await ui.wait_until(func(): return _panel_open("屬性"), 3.0), "屬性 did not open"):
		return false
	if not _check(ui.find_label("造型：", "prefix", ui.find_by_class("AttributesPanel")) != null, "屬性 window has no 造型 line"):
		return false
	if not await ui.click_text("更換造型", "exact"):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_by_class("LookDialog") != null, 3.0), "LookDialog did not open"):
		return false
	var ld := ui.find_by_class("LookDialog")
	var picker: Variant = ld.get("picker")
	var cells: Array = picker.get("cells")
	if not _check(cells.size() == 9, "look dialog cells %d" % cells.size()):
		return false
	if not await ui.click(cells[6]):
		return false
	await ui.frames(2)
	await ui.shot("m3c_look_dialog")
	if not await ui.click(ui.find_button("確定", "exact", ld, true)):
		return false
	if not _check(await ui.wait_until(func(): return UiBuild.num(UiClient.sheet().get("appearance", -1)) == 6, 4.0),
			"set_look 6 not applied (appearance %s)" % str(UiClient.sheet().get("appearance", ""))):
		return false
	await ui.wait_until(func(): return ui.find_by_class("LookDialog") == null, 2.0)
	# M3c 審查：換完要有回饋——訊息列「你換上了…的打扮。」、屬性窗重新打開
	if not _check(await ui.wait_until(func(): return _log_contains("你換上了"), 3.0), "no 你換上了 line after 更換造型 (log「%s」)" % _log_tail(3)):
		return false
	if not _check(await ui.wait_until(func(): return _panel_open("屬性"), 3.0), "屬性 window did not come back after 更換造型"):
		return false
	await ui.seconds(0.2)
	await ui.shot("m3c_attr_look")
	return await _close_panel()

## 跨區趕路中遇敵：打完 → 回到地圖（全圖分頁）→ 等自動續走；等待中又遇敵就再打（最多 6 輪）。
## 回傳「沒有戰鬥、正在趕路（頁尾 趕路中：往…）」
func _resume_world_walk(mp: Control, mtc: TabContainer) -> bool:
	for _i in 6:
		if _battle() == null and bool(mp.call("is_walking")) and _map_footer().begins_with("趕路中：往"):
			return true
		if _battle() == null and _map_footer().begins_with("遇敵"):
			await ui.wait_until(func(): return _battle() != null, 3.0)
		if _battle() != null and not await _fight():
			return false
		if not _panel_open("地圖"):
			await ui.press_key(KEY_M)
			await ui.wait_until(func(): return _panel_open("地圖"), 3.0)
		await ui.select_tab(mtc.get_tab_bar(), MapPanel.TAB_WORLD)
		await ui.wait_until(func(): return _battle() != null or (bool(mp.call("is_walking")) and _map_footer().begins_with("趕路中：往")), 4.0)
	return _battle() == null and bool(mp.call("is_walking")) and _map_footer().begins_with("趕路中：往")

## 江湖全圖點地區 → 跨區趕路（頁尾「趕路中：往X（剩N步）」）→ Esc 停（地圖不關）；快捷目的地 → 停止鈕
func _m3c_world_route() -> bool:
	print("[UiPlay] M3c: 江湖全圖趕路、快捷、Esc 停")
	if not await _teleport("xx_square"):
		return false
	await ui.press_key(KEY_M)
	if not _check(await ui.wait_until(func(): return _panel_open("地圖"), 3.0), "M did not open the map"):
		return false
	var mp := _map_panel()
	var mtc := ui.find(func(c): return c is TabContainer, mp) as TabContainer
	await ui.select_tab(mtc.get_tab_bar(), MapPanel.TAB_WORLD)
	await ui.seconds(0.3)
	var wv: Control = mp.get("world_view")
	var at: Vector2 = wv.call("center_of", "dali")
	if not _check(str(wv.call("region_at", at)) == "dali", "world map: 大理 station not at its center (%s)" % str(wv.call("region_at", at))):
		return false
	await ui.click_local(wv, at)
	if not _check(await ui.wait_until(func(): return bool(mp.call("is_walking")) and (_map_footer().begins_with("趕路中：往") or _map_footer().begins_with("遇敵")), 3.0),
			"world-map click did not start walking (footer「%s」)" % _map_footer()):
		return false
	# 一出城就遇敵（隨機）：打完等自動續走再往下（不穩修正；M3c2 第二輪審查：續走的等待裡又遇敵也要接著打）
	if not _check(await _resume_world_walk(mp, mtc), "walk did not resume after the encounter (footer「%s」)" % _map_footer()):
		return false
	print("[UiPlay] world route: " + _map_footer())
	await ui.seconds(0.4)
	await ui.shot("m3c_world_route")
	# M3c2 整合（不穩修正）：截圖到按 Esc 之間又遇敵 → 先打完、回到地圖、等自動續走（否則 Esc 會關地圖）
	if not _check(await _resume_world_walk(mp, mtc) and _battle() == null and bool(mp.call("is_walking")),
			"world walk not running before Esc (footer「%s」)" % _map_footer()):
		return false
	await ui.press_key(KEY_ESCAPE)
	if not _check(await ui.wait_until(func(): return not bool(mp.call("is_walking")) and _map_footer().contains("已停止趕路"), 3.0),
			"Esc did not stop the walk (footer「%s」)" % _map_footer()):
		return false
	if not _check(_panel_open("地圖"), "Esc closed the map instead of only stopping the walk"):
		return false
	await ui.seconds(0.2)
	await ui.shot("m3c_walk_stop_esc")   # M3c 第二輪審查：Esc 停走「已停止趕路。」要有截圖
	if _battle() != null and not await _fight():
		return false
	if not await _m3c_walk_stop_shots(mp, mtc):
		return false
	if not _panel_open("地圖"):
		await ui.press_key(KEY_M)
		await ui.wait_until(func(): return _panel_open("地圖"), 3.0)
	await ui.select_tab(mtc.get_tab_bar(), MapPanel.TAB_REGION)
	await ui.seconds(0.2)
	var qb: MenuButton = mp.get("quick_button")
	if not await ui.choose_menu(qb, "最近的客棧", "prefix"):
		return false
	var items := ui.menu_items(qb)
	print("[UiPlay] quick destinations: " + str(items))
	if not _check(items.size() == 5 and items.any(func(t): return str(t).begins_with("本派山門")), "quick menu items %s" % str(items)):
		return false
	var started := await ui.wait_until(func(): return bool(mp.call("is_walking")) or _map_footer() == "已抵達。", 3.0)
	if not _check(started, "quick destination did not start (footer「%s」)" % _map_footer()):
		return false
	# M3c 第二輪審查：隨機遇敵常常搶走這張（89 拍成小黃的戰鬥）→ 打完、等自動續走、確定是「趕路中」才拍
	for _i in 3:
		if _battle() == null:
			break
		if not await _fight():
			return false
		if not _panel_open("地圖"):
			await ui.press_key(KEY_M)
			await ui.wait_until(func(): return _panel_open("地圖"), 3.0)
		await ui.wait_until(func(): return _battle() != null or _map_footer().begins_with("趕路中：往") or not bool(mp.call("is_walking")), 4.0)
	if bool(mp.call("is_walking")):
		await ui.wait_until(func(): return _map_footer().begins_with("趕路中：往"), 3.0)
	if not _check(_battle() == null, "quick walk: still in a battle before the shot"):
		return false
	print("[UiPlay] quick walk footer:「%s」" % _map_footer())
	await ui.shot("m3c_quick_walk")
	var cb: Button = mp.get("cancel_button")
	if bool(mp.call("is_walking")) and cb != null and cb.is_visible_in_tree():
		if not await ui.click(cb):
			# M3c2 整合（不穩修正）：按下去的瞬間踩到地雷、戰鬥畫面蓋住停止鈕 → 不是介面壞掉：打完再停
			if _battle() == null:
				return false
			ui.last_error = ""
			if not await _fight():
				return false
			if bool(mp.call("is_walking")) and cb.is_visible_in_tree():
				if not _panel_open("地圖"):
					await ui.press_key(KEY_M)
					await ui.wait_until(func(): return _panel_open("地圖"), 3.0)
				if not await ui.click(cb):
					return false
		if not _check(await ui.wait_until(func(): return not bool(mp.call("is_walking")), 3.0), "停止 did not stop the walk"):
			return false
	if _battle() != null and not await _fight():
		return false
	if _panel_open("地圖"):
		await ui.press_key(KEY_ESCAPE)
	return _check(await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0), "map did not close")

## M3c 第二輪審查：趕路停走原因的截圖（以前只有文字測試）：
## 遇敵暫停（encounter_next 強制遇敵；續走延遲拉長，戰鬥收起後頁尾是「戰鬥結束，稍後繼續趕路。」時拍）、
## 氣血不足（vital:qi）、肚子餓（vital:food）。都在西夏廣場往大理的路上，拍完把氣、飽食加回來
func _m3c_walk_stop_shots(mp: Control, mtc: TabContainer) -> bool:
	print("[UiPlay] M3c: 趕路停走原因截圖")
	var walker: Node = mp.get("walker")
	var wv: Control = mp.get("world_view")
	var start_walk := func() -> bool:
		if not _panel_open("地圖"):
			await ui.press_key(KEY_M)
			await ui.wait_until(func(): return _panel_open("地圖"), 3.0)
		await ui.select_tab(mtc.get_tab_bar(), MapPanel.TAB_WORLD)
		await ui.seconds(0.2)
		await ui.click_local(wv, wv.call("center_of", "dali"))
		return await ui.wait_until(func(): return bool(mp.call("is_walking")) or _map_footer() != "", 3.0)
	# 1. 遇敵暫停
	if not await _teleport("xx_gate_e"):
		return false
	var old_delay: float = walker.get("resume_delay_s")
	walker.set("resume_delay_s", 6.0)
	if not _check(await _debug_set("encounter_next", true) == "", "debug_set encounter_next"):
		return false
	await start_walk.call()
	if not _check(await ui.wait_until(func(): return _battle() != null, 8.0), "encounter_next: no battle while walking (footer「%s」)" % _map_footer()):
		walker.set("resume_delay_s", old_delay)
		return false
	var pause_txt := _map_footer()
	if not await _fight():
		walker.set("resume_delay_s", old_delay)
		return false
	if not _panel_open("地圖"):
		await ui.press_key(KEY_M)
		await ui.wait_until(func(): return _panel_open("地圖"), 3.0)
	await ui.select_tab(mtc.get_tab_bar(), MapPanel.TAB_WORLD)
	await ui.seconds(0.3)
	print("[UiPlay] encounter pause footer:「%s」→「%s」" % [pause_txt, _map_footer()])
	# M3c 第三輪審查：打贏之後、續走之前頁尾改寫「戰鬥結束，稍後繼續趕路。」（不再留著「遇敵交戰中」）
	var paused_ok := _map_footer() == AutoWalker.RESUME_WAIT_TEXT
	if not _check(paused_ok or not bool(mp.call("is_walking")), "after the won fight the walk footer was「%s」(want「%s」)" % [_map_footer(), AutoWalker.RESUME_WAIT_TEXT]):
		walker.set("resume_delay_s", old_delay)
		return false
	if paused_ok:
		await ui.shot("m3c_walk_encounter_pause")
	walker.set("resume_delay_s", old_delay)
	if not _check(pause_txt == AutoWalker.PAUSE_TEXT or paused_ok, "walk footer during the encounter was「%s」" % pause_txt):
		return false
	(walker as Node).call("stop", "")
	await ui.wait_until(func(): return not bool(mp.call("is_walking")), 3.0)
	if _battle() != null and not await _fight():
		return false
	# 2. 氣血不足、3. 肚子餓
	for c in [["vital:qi", 1, "氣血不足", "m3c_walk_stop_qi"], ["vital:food", 5, "肚子餓", "m3c_walk_stop_hungry"]]:
		if not await _teleport("xx_square"):
			return false
		await _debug_set("vital:qi", 99999)   # 上一張拍完先補滿，只留這一張要的停走原因
		await _debug_set("vital:food", 99999)
		if not _check(await _debug_set(str(c[0]), c[1]) == "", "debug_set %s" % str(c[0])):
			return false
		await ui.seconds(0.3)
		await start_walk.call()
		var stopped := await ui.wait_until(func(): return not bool(mp.call("is_walking")) and _map_footer().contains(str(c[2])), 4.0)
		print("[UiPlay] walk stop (%s):「%s」" % [str(c[0]), _map_footer()])
		if not _check(stopped, "%s did not stop the walk with「%s」(footer「%s」)" % [str(c[0]), str(c[2]), _map_footer()]):
			return false
		await ui.seconds(0.2)
		await ui.shot(str(c[3]))
		if bool(mp.call("is_walking")):
			(walker as Node).call("stop", "")
		if _battle() != null and not await _fight():
			return false
	await _debug_set("vital:qi", 99999)
	await _debug_set("vital:food", 99999)
	# 下一張「快捷目的地」要走幾步才拍得到趕路中：從城外荒草坡出發（最近的客棧在城裡）
	if not await _teleport("xw_grass"):
		return false
	await ui.seconds(0.3)
	return true

## 小地圖「往XXX」→ 切到鄰區（瀏覽中、⟲）→ 點那區到過的房間 → 跨區趕路 → 停止 → ⟲ 回目前區域
func _m3c_minimap_edge() -> bool:
	print("[UiPlay] M3c: 小地圖往XXX")
	var mp := _map_panel()
	# 上一步的快捷趕路途中遇敵打贏後會自動續走（nav.auto_resume）：先等續走的 0.5 秒過去、停下來，
	# 不然下面點小地圖房間會變成「已取消趕路」（M3c 審查後的不穩）
	await ui.seconds(0.8)
	if bool(mp.call("is_walking")):
		(mp.get("walker") as Node).call("stop", "")
		await ui.wait_until(func(): return not bool(mp.call("is_walking")), 2.0)
	var known: Dictionary = mp.call("known")
	var tables := UiClient.tables()
	var edge_room := ""
	var to_region := ""
	var maps: Dictionary = tables.get("maps", {})
	var region_of := {}
	for rid in maps:
		for room in (maps[rid] as Dictionary).get("rooms", []):
			region_of[str(room.get("id", ""))] = str(rid)
	for room in (maps.get("xixia", {}) as Dictionary).get("rooms", []):
		for ex in room.get("exits", []):
			var to := str(ex.get("to", ""))
			if known.has(to) and region_of.get(to, "xixia") != "xixia" and known.has(str(room.get("id", ""))):
				edge_room = str(room.get("id", ""))
				to_region = str(region_of[to])
				break
		if edge_room != "":
			break
	if not _check(edge_room != "", "no explored 西夏 room with an explored neighbouring region"):
		return false
	if not await _teleport(edge_room):
		return false
	var mm := _mini_map()
	var v: Control = mm.get("view")
	await ui.wait_until(func(): return str(v.get("current")) == edge_room, 3.0)
	await ui.frames(3)
	var hit := Vector2(-1, -1)
	var sz := v.size
	var y := 2.0
	while y < sz.y and hit.x < 0:
		var x := 2.0
		while x < sz.x:
			var p := Vector2(x, y)
			if str(v.call("region_at", p)) == to_region and str(v.call("room_at", p)) == "":
				hit = p
				break
			x += 3.0
		y += 3.0
	if not _check(hit.x >= 0, "mini map shows no clickable 往%s at %s" % [to_region, edge_room]):
		return false
	await ui.click_local(v, hit)
	if not _check(await ui.wait_until(func(): return bool(mm.get("browsing")) and str(mp.get("browse_region")) == to_region, 3.0),
			"往XXX click did not switch the mini map to %s (browsing %s, browse_region %s)" % [to_region, str(mm.get("browsing")), str(mp.get("browse_region"))]):
		return false
	var back: Button = mm.get("back_button")
	if not _check(back != null and back.is_visible_in_tree() and back.text == "返", "no 返 back button while browsing"):
		return false
	if not _check(str((mm.get("title_label") as Label).text).begins_with("瀏覽"), "mini map title has no 瀏覽 cue"):
		return false
	await ui.seconds(0.2)
	await ui.shot("m3c_minimap_edge_browse")
	# 那區畫面上看得到、到過的房間裡挑路最遠的一間（趕路要走幾步，截得到「趕路中」）
	var target := ""
	var best := -1
	var g: Dictionary = mp.call("graph")
	var rects: Dictionary = v.get("_rects")
	for rid in rects:
		if known.has(str(rid)) and region_of.get(str(rid), "") == to_region and str(rid) != edge_room:
			var r := (v.call("screen_rect", str(rid)) as Rect2)
			if Rect2(Vector2.ZERO, v.size).has_point(r.get_center()):
				var n := RoutePlanner.find_path(g, edge_room, str(rid), known).size()
				if n > best:
					best = n
					target = str(rid)
	if not _check(target != "", "browsed region %s shows no explored room to click" % to_region):
		return false
	if not await _click_mini_room(target):
		return false
	if not _check(await ui.wait_until(func(): return bool(mp.call("is_walking")) or _room_id() == target, 3.0),
			"clicking %s in the browsed region did not start walking (mini status「%s」)" % [target, _mini_status()]):
		return false
	print("[UiPlay] mini map browse %s → walk to %s:「%s」" % [to_region, target, _mini_status()])
	await ui.shot("m3c_minimap_edge_walk")
	var stop: Button = mm.get("stop_button")
	# M3c2 第二輪審查（不穩修正）：遇敵時 is_walking() 仍是 true（只是暫停）→ 先打完再按「停」，不然會點到戰鬥畫面
	for _i in 4:
		if _battle() != null:
			if not await _fight():
				return false
			continue
		if not bool(mp.call("is_walking")):
			break
		if stop != null and stop.is_visible_in_tree():
			if not await ui.click(stop):
				return false
			await ui.wait_until(func(): return not bool(mp.call("is_walking")) or _battle() != null, 3.0)
		else:
			(mp.get("walker") as Node).call("stop", "")
	if _battle() != null and not await _fight():
		return false
	if bool(mm.get("browsing")):
		if not await ui.click(back):
			return false
		if not _check(await ui.wait_until(func(): return not bool(mm.get("browsing")) and str(mp.get("browse_region")) == "", 3.0),
				"⟲ did not return to the current region"):
			return false
	await ui.seconds(0.2)
	await ui.shot("m3c_minimap_edge_back")
	return true

## Ctrl+點 NPC：確認框（小孩 KILL＋官兵、村民 CHALLENGE；取消不送）；受保護 NPC 只在訊息列說明；武當知客「滅派」
func _m3c_npc_attack() -> bool:
	print("[UiPlay] M3c: 攻擊 NPC 確認框、滅派")
	if not await _teleport("dl_square"):
		return false
	if not _check(await ui.wait_until(func(): return _npc_button("小孩") != null and _npc_button("大理村民") != null, 3.0),
			"dl_square has no 小孩/大理村民 buttons"):
		return false
	var b := _npc_button("小孩")
	if not _check(b.tooltip_text.contains("動手"), "小孩 tooltip lacks the Ctrl hint:「%s」" % b.tooltip_text):
		return false
	if not await ui.click(b, true):
		return false
	if not _check(await ui.wait_until(func(): return _confirm_dialog() != null, 3.0), "Ctrl+click 小孩 did not open the confirm box"):
		return false
	var txt := str((_confirm_dialog().get("message_label") as Label).text)
	# M3c 第二輪審查：介面驗收的角色是新手——預設規則（newbie_guard_spare）官兵放過他，確認框不寫官兵那句
	if not _check(txt.contains("善惡") and not txt.contains("守城官兵") and txt.contains("暫時消失"), "child confirm text:「%s」" % txt):
		return false
	await ui.shot("m3c_npc_attack_confirm_child")
	if not await ui.click(_confirm_dialog().get("cancel_button")):
		return false
	await ui.wait_until(func(): return _confirm_dialog() == null, 2.0)
	if not _check(_battle() == null, "cancel still started a fight"):
		return false
	if not await ui.click(_npc_button("大理村民"), true):
		return false
	if not _check(await ui.wait_until(func(): return _confirm_dialog() != null, 3.0), "Ctrl+click 村民 did not open the confirm box"):
		return false
	txt = str((_confirm_dialog().get("message_label") as Label).text)
	# M3c 審查：CHALLENGE 不說「殺死」；取消鈕與滅派一樣是「再想想」；標題沒有英文 NPC
	if not _check(txt.contains("不會死") and not txt.contains("殺死"), "challenge confirm text:「%s」" % txt):
		return false
	if not _check(str((_confirm_dialog().get("cancel_button") as Button).text) == "再想想", "confirm cancel label"):
		return false
	await ui.shot("m3c_npc_attack_confirm_challenge")
	await ui.click(_confirm_dialog().get("cancel_button"))
	await ui.wait_until(func(): return _confirm_dialog() == null, 2.0)
	# 受保護（任務 NPC 白勇）：不開確認框，訊息列「不是你能動手的對象」
	if not await ui.click(_npc_button("白勇"), true):
		return false
	if not _check(await ui.wait_until(func(): return _log_contains("不是你能動手的對象"), 3.0) and _confirm_dialog() == null,
			"protected NPC: no message / confirm opened (log「%s」)" % _log_tail(3)):
		return false
	await ui.shot("m3c_npc_protected")
	await _close_npc_dialog()
	# 滅派（武當知客道長的選單；Ctrl+點不行）
	if not await _teleport("wd_gate"):
		return false
	var d := await _talk("知客道長")
	if d == null:
		return false
	if not _check(await ui.wait_until(func(): return ui.find_button("滅派", "prefix", d) != null, 3.0), "知客道長 menu has no 滅派:「%s」" % _dialog_text(d)):
		return false
	await ui.shot("m3c_miepai_option")
	if not await ui.click(ui.find_button("滅派", "prefix", d, true)):
		return false
	var says_enemy := func() -> bool:
		if _dialog_text(d).contains("公敵"):
			return true
		var cd := _confirm_dialog()
		return cd != null and str((cd.get("message_label") as Label).text).contains("公敵")
	if not _check(await ui.wait_until(says_enemy, 3.0), "滅派 confirm does not mention 公敵:「%s」" % _dialog_text(d)):
		return false
	# M3c 審查：滅派確認要說清楚要面對幾個人
	if not _check(_dialog_text(d).contains("共 3 人") or (_confirm_dialog() != null and str((_confirm_dialog().get("message_label") as Label).text).contains("共 3 人")),
			"滅派 confirm does not say how many foes:「%s」" % _dialog_text(d)):
		return false
	await ui.shot("m3c_miepai_confirm")
	var cancel := ui.find_button("再想想", "exact", d, true)
	if cancel == null:
		cancel = ui.find_button("取消", "exact", d, true)
	if cancel == null and _confirm_dialog() != null:
		cancel = _confirm_dialog().get("cancel_button")
	if not _check(cancel != null, "滅派 confirm has no cancel button"):
		return false
	await ui.click(cancel)
	await ui.seconds(0.3)
	if not _check(_battle() == null and not str(UiClient.sheet().get("enemy_of", [])).contains("武當"), "cancelled 滅派 still had an effect"):
		return false
	await _close_npc_dialog()
	return true

## 裝備窗：選取某 uid 的物品格（依序切分頁找）
func _inv_select(uid: String) -> bool:
	var inv := ui.find_by_class("InventoryPanel")
	var tb := ui.find(func(c): return c is TabBar, inv) as TabBar
	for i in tb.tab_count:
		await ui.select_tab(tb, i)
		await ui.frames(2)
		var b := ui.find(func(c): return c is Button and c.has_meta("item_uid") and str(c.get_meta("item_uid")) == uid, inv) as Button
		if b != null:
			return await ui.click(b)
	return _check(false, "item %s not in the 裝備 window" % uid)

func _uid_of(item_id: String) -> String:
	for it in UiClient.sheet().get("inventory", []):
		if it is Dictionary and str(it.get("id", "")) == item_id:
			return str(it.get("uid", ""))
	return ""

func _open_inventory() -> Control:
	if not await ui.click_text("裝備(", "prefix"):
		return null
	if not _check(await ui.wait_until(func(): return _panel_open("裝備"), 3.0), "裝備 did not open"):
		return null
	return ui.find_by_class("InventoryPanel")

func _close_panel() -> bool:
	if ui.find_button("關閉(Esc)", "exact", null, true) != null:
		await ui.click_text("關閉(Esc)")
	return _check(await ui.wait_until(func(): return ui.find_button("關閉(Esc)") == null, 3.0), "panel did not close")

## 武器特效：拿刀、拿劍、空手各打一隻野兔（debug_set battle_monster），戰鬥畫面要畫出 blade／sword／fist 特效、名牌有武器小圖示
func _m3c_weapon_fx() -> bool:
	print("[UiPlay] M3c: 武器特效")
	if not await _teleport("dl_square"):
		return false
	for kv in [["attr:str", 120], ["attr:con", 120], ["attr:agi", 120], ["skill:basic_blade", 100], ["skill:basic_sword", 100],
			["skill:basic_fist", 100], ["skill:basic_dodge", 100], ["give_item", "w_mujian:1"], ["give_item", "w_mudao:1"]]:
		if not _check(await _debug_set(str(kv[0]), kv[1]) == "", "debug_set %s" % str(kv[0])):
			return false
	for kind in ["blade", "sword", "fist"]:
		if not await _ensure_healthy():
			return false
		if not await _m3c_wield(kind):
			return false
		m3c_fx_seen.clear()
		m3c_fx_shot_kind = kind
		if not _check(await _debug_set("battle_monster", "m_rabbit") == "", "debug_set battle_monster"):
			return false
		if not _check(await ui.wait_until(func(): return _battle() != null, 5.0), "no battle for the %s fx" % kind):
			return false
		await ui.frames(3)
		var grid := _grid(_battle())
		var sprites: Dictionary = grid.get("sprites")
		var vm: Variant = grid.get("vm")
		var icon := ""
		for uid in sprites:
			var u: Dictionary = vm.units.get(uid, {})
			if int(u.get("peer", 0)) == ClientState.my_peer_id and str(u.get("kind", "")) == "PLAYER":
				icon = str(sprites[uid].get("weapon_kind"))
		if not _check(icon == kind, "name-plate weapon icon '%s' (want %s)" % [icon, kind]):
			return false
		if not await _fight():
			return false
		if not _check(m3c_fx_seen.has(kind), "no %s weapon fx drawn (seen %s)" % [kind, str(m3c_fx_seen.keys())]):
			return false
		await ui.wait_until(func(): return not _fx_shooting, 2.0)
		if not ui.is_headless() and ui.shots_dir != "" and not m3c_fx_shot_taken.has(kind):
			ui.warn("M3c: %s weapon fx was drawn but no m3c_weapon_fx_%s screenshot was caught" % [kind, kind])
		print("[UiPlay] M3c: %s fx drawn (icon %s)" % [kind, icon])
	m3c_fx_shot_kind = ""
	return true

## 依 kind 換手上的兵器（經由裝備窗：選物品 → 裝備；fist ＝ 卸下武器）
func _m3c_wield(kind: String) -> bool:
	var want_id := str({ "blade": "w_mudao", "sword": "w_mujian" }.get(kind, ""))
	var eq: Dictionary = UiClient.sheet().get("equipped", {})
	var cur_uid := str(eq.get("WEAPON", ""))
	var cur_id := ""
	for it in UiClient.sheet().get("inventory", []):
		if it is Dictionary and str(it.get("uid", "")) == cur_uid:
			cur_id = str(it.get("id", ""))
	if (want_id == "" and cur_uid == "") or (want_id != "" and cur_id == want_id):
		return true
	var inv := await _open_inventory()
	if inv == null:
		return _check(false, "M3c 換兵器（%s）：裝備窗打不開" % kind)
	if want_id == "":
		if not await _inv_select(cur_uid):
			return _check(false, "M3c 換兵器：背包裡找不到手上的兵器 %s" % cur_uid)
		if not await ui.click_text("卸下", "exact", inv):
			return _check(false, "M3c 換兵器：按不到「卸下」")
		if not _check(await ui.wait_until(func(): return str((UiClient.sheet().get("equipped", {}) as Dictionary).get("WEAPON", "")) == "", 3.0), "卸下 weapon failed"):
			return false
	else:
		var uid := _uid_of(want_id)
		if not await _inv_select(uid):
			return _check(false, "M3c 換兵器：背包裡找不到 %s（uid '%s'）" % [want_id, uid])
		if not await ui.click_text("裝備", "exact", inv):
			return _check(false, "M3c 換兵器：按不到「裝備」")
		if not _check(await ui.wait_until(func(): return str((UiClient.sheet().get("equipped", {}) as Dictionary).get("WEAPON", "")) == uid, 3.0), "equip %s failed" % want_id):
			return false
	return await _close_panel()

## 打寶：強制掉落珍品（debug_set loot_force）→ 打山賊頭目 → 結果框珍品上色、「得到寶物！」→ 裝備窗 8 格、珍品詳情
func _m3c_loot() -> bool:
	print("[UiPlay] M3c: 打寶")
	for kv in [["attr:str", 220], ["attr:con", 220], ["attr:agi", 200], ["skill:basic_blade", 200], ["skill:basic_dodge", 200]]:
		if not _check(await _debug_set(str(kv[0]), kv[1]) == "", "debug_set %s" % str(kv[0])):
			return false
	if not await _m3c_wield("blade"):
		return _check(false, "M3c 打寶：換木刀失敗（在 %s）" % _room_id())
	if not _check(await _debug_set("loot_force", "a_lt_jinggangjie") == "", "debug_set loot_force"):
		return false
	for attempt in 3:
		if not await _ensure_healthy():
			return _check(false, "M3c 打寶：第 %d 次開打前回復失敗（在 %s，氣 %d/%d）" % [attempt + 1, _room_id(), _vital("qi"), _vital("qi_max")])
		if not _check(await _debug_set("battle_monster", "m_bandit_chief") == "", "debug_set battle_monster"):
			return false
		if not _check(await ui.wait_until(func(): return _battle() != null, 5.0), "no 山賊頭目 battle"):
			return false
		m3c_loot_battle = true
		m3c_loot_ok = false
		if not await _fight():
			return _check(false, "M3c 打寶：第 %d 場山賊頭目沒打完（在 %s）" % [attempt + 1, _room_id()])
		m3c_loot_battle = false
		if m3c_loot_ok:
			break
	if not _check(m3c_loot_ok and _uid_of("a_lt_jinggangjie") != "", "no 珍品 drop shown in the battle result (bag uid '%s')" % _uid_of("a_lt_jinggangjie")):
		return false
	var inv := await _open_inventory()
	if inv == null:
		return _check(false, "M3c 打寶：裝備窗打不開")
	var slots: Dictionary = inv.get("body_buttons")
	var enabled := 0
	for k in slots:
		if not (slots[k] as Button).disabled:
			enabled += 1
	if not _check(slots.size() == 8 and enabled == 8, "inventory body slots %d (enabled %d)" % [slots.size(), enabled]):
		return false
	if not await _inv_select(_uid_of("a_lt_jinggangjie")):
		return false
	var detail := str((inv.get("detail_label") as RichTextLabel).get_parsed_text())
	if not _check(detail.contains("珍品"), "treasure detail lacks 珍品:「%s」" % detail):
		return false
	await ui.seconds(0.2)
	await ui.shot("m3c_inventory_treasure")
	return await _close_panel()

# ---------- 22. M3c2（M3C2_PLAN §10.4）：門派雜務、匯出／匯入角色、標題版本列 ----------
## 每派一件全天雜務：門派 -> [任務, 給的人, 給的人房間]（同 tools/m3c2_acceptance.gd ALLDAY）
const M3C2_CHORES := {
	"shaolin": ["q_ch_sl_saodi", "n_ch_sl_kanshui", "sl_court"], "wudang": ["q_ch_wd_taqiang", "n_wd_yulianzhou", "wd_tanqiang"],
	"emei": ["q_ch_em_chanding", "n_em_jingxuan", "em_dadian"], "huashan": ["q_ch_hs_tiaoqi", "n_ch_hs_yejing", "hs_hall"],
	"quanzhen": ["q_ch_qz_dujing", "n_qz_xiazhicheng", "qz_reading"], "gumu": ["q_ch_gm_hanyu", "n_gm_hanyu", "gm_hanyu"],
	"hengshan": ["q_ch_hg_tiaoqi", "n_hg_dingjing", "hg_houshan"], "lingjiu": ["q_ch_lj_dingzuo", "n_lj_lanjian", "lj_east"],
	"xingxiu": ["q_ch_xh_anqi", "n_xh_canjizi", "xh_mid1"], "xuedao": ["q_ch_xd_pizhi", "n_xd_shengdi", "xd_yard"],
	"gaibang": ["q_ch_gb_jianchai", "n_gb_zhanggun", "gb_yuan"],
}
const FOREIGN_NAME := "異鄉俠客"
const FOREIGN_FILE := "異鄉俠客_朋友的江湖_ui.jychar.json"
const BAD_FILE := "壞掉的角色檔_ui.jychar.json"
const CLASH_FILE := "同名俠客_朋友的江湖_ui.jychar.json"
const RENAMED_NAME := "改名俠客"
const STEAM_TEST_IDENT := "steam_76561190000000777"
const STEAM_TEST_NAME := "蒸汽俠"

func _m3c2_screens() -> bool:
	_step(22, "M3c2 畫面：門派雜務、匯出／匯入角色、標題版本列")
	if _battle() != null and not await _fight():
		return false
	if m3a_ready and not await _m3c2_chore():
		return false
	if _battle() != null and not await _fight():
		return false
	if not await _m3c2_export_import():
		return false
	return await _m3c2_title_line()

## NPC 對話框「任務」→「接受」→ 場景的紅字任務動作 → 再找 NPC 交付 → 任務結束（截圖 m3c2_chore_*）
func _m3c2_chore() -> bool:
	var sect := str(UiClient.sheet().get("sect", ""))
	if not M3C2_CHORES.has(sect):
		ui.warn("M3c2 雜務：角色目前門派 '%s' 沒有對應的全天雜務，略過" % sect)
		return true
	var row: Array = M3C2_CHORES[sect]
	var qid := str(row[0])
	var giver := str(row[1])
	var room := str(row[2])
	var qname := str(UiClient.tables().get("quests", {}).get(qid, {}).get("name", qid))
	# 設定（不是受測物）：精神回滿，免得交差時代價不夠
	for k in ["vital:jing", "vital:shen"]:
		var why: String = await _debug_set(k, 9999)
		if not _check(why == "", "debug_set %s: %s" % [k, why]):
			return false
	if not await _goto(room):
		return false
	var lp0 := UiBuild.num(UiClient.sheet().get("learn_points", 0))
	var dlg := await _talk(_npc_display(giver))
	if dlg == null:
		return false
	if not await ui.click_text("任務", "prefix", dlg):
		return false
	var ql := await _wait_label(qname, dlg)
	if not _check(ql != null, "chore %s not in %s's quest list" % [qname, _npc_display(giver)]):
		return false
	var accept := ui.find_button("接受", "exact", ql.get_parent(), true)
	if not _check(accept != null, "chore %s has no 接受 button (%s)" % [qname, ql.text]):
		return false
	if not await ui.click(accept):
		return false
	if not _check(await ui.wait_until(func(): return _sheet_has_quest(qid), 3.0), "接受 did not start " + qid):
		return false
	await ui.shot("m3c2_chore_accept")
	if not await _close_dialog(dlg):
		return false
	var act_name := "StoryAct_" + qid + "_a_work"
	var holder := { "b": null }
	await ui.wait_until(func():
		holder["b"] = ui.find(func(c): return c is Button and str(c.name) == act_name and not (c as Button).disabled)
		return holder["b"] != null, 5.0)
	var act_btn: Button = holder["b"]
	if not _check(act_btn != null, "no room action button %s in %s" % [act_name, _room_name()]):
		return false
	if not await ui.click(act_btn):
		return false
	var work_text := str(UiClient.tables().get("text_templates", {}).get("ch_work_" + qid.trim_prefix("q_ch_"), {}).get("self", ""))
	await ui.wait_until(func(): return work_text == "" or _log_contains(work_text.left(8)), 3.0)
	# 交付：有目前目標的 NPC 會直接開任務對話；沒有台詞的雜務開 NPC 對話框 →「任務」→「交付」
	if not await ui.click_text(_npc_display(giver), "prefix", _npcs_box()):
		return false
	await ui.wait_until(func(): return _story_dialog() != null or ui.find_by_class("NpcDialog") != null, 5.0)
	if _story_dialog() != null:
		if not await _story_finish():
			return false
	if _sheet_has_quest(qid):
		var d2 := ui.find_by_class("NpcDialog")
		if not _check(d2 != null, "turn in: no NPC dialog for %s" % _npc_display(giver)):
			return false
		if not await ui.click_text("任務", "prefix", d2):
			return false
		var th := { "b": null }
		await ui.wait_until(func():
			th["b"] = ui.find_button("交付", "exact", d2, true)
			return th["b"] != null, 3.0)
		var turn_in: Button = th["b"]
		if not _check(turn_in != null, "chore %s: no 交付 button" % qname):
			return false
		if not await ui.click(turn_in):
			return false
		if not _check(await ui.wait_until(func(): return not _sheet_has_quest(qid), 3.0), "交付 did not finish " + qid):
			return false
		await ui.frames(3)
		await ui.shot("m3c2_chore_result")
		await _close_dialog(d2)
	else:
		await ui.frames(3)
		await ui.shot("m3c2_chore_result")
	var lp1 := UiBuild.num(UiClient.sheet().get("learn_points", 0))
	print("[UiPlay] M3c2 雜務 %s（%s）：學點 %d → %d" % [qname, sect, lp0, lp1])
	return true

func _wait_label(text: String, under: Node) -> Label:
	var h := { "l": null }
	await ui.wait_until(func():
		h["l"] = ui.find_label(text, "prefix", under)
		return h["l"] != null, 3.0)
	return h["l"]

## 系統窗「離開遊戲」→「返回角色選擇」→ 角色列「匯出」（訊息列出檔案路徑）→ 測試設定：把匯出檔改成「朋友世界」的角色檔
## →「匯入角色」→「匯出資料夾」→ 點檔案 → 預覽 →「確定匯入」→ 清單出現（外來）的角色（截圖 m3c2_export／import_preview／char_foreign）
func _m3c2_export_import() -> bool:
	if not await _m3c2_steam_group():
		return false
	if not await ui.click_text("系統(", "prefix"):
		return false
	if not _check(await ui.wait_until(func(): return _panel_open("系統"), 3.0), "系統 window did not open"):
		return false
	if not await ui.click_text("離開遊戲", "exact", ui.find_by_class("SystemPanel")):
		return false
	if not await ui.click_text("返回角色選擇", "exact"):
		return false
	if not _check(await ui.wait_scene(SCENE_CHAR_SELECT, 10.0), "char_select not shown after 返回角色選擇"):
		return false
	var rh := { "l": null }
	await ui.wait_until(func():
		rh["l"] = ui.find_label(CHAR_NAME, "prefix")
		return rh["l"] != null, 5.0)
	var row_label: Label = rh["l"]
	if not _check(row_label != null, "char_select has no row for " + CHAR_NAME):
		return false
	if not await _m3c2_steam_confirm():
		return false
	var exp_btn := ui.find_button("匯出", "exact", row_label.get_parent().get_parent(), true)   # CharInfo → CharInfoBox → 列
	if not _check(exp_btn != null, "row %s has no 匯出 button" % CHAR_NAME):
		return false
	if not await ui.click(exp_btn):
		return false
	var eh := { "t": "" }
	await ui.wait_until(func():
		var l := ui.find_label("已匯出到：", "prefix")
		eh["t"] = l.text if l != null else ""
		return str(eh["t"]) != "", 8.0)
	var exp_text := str(eh["t"])
	if not _check(exp_text != "", "export did not report a path"):
		return false
	await ui.shot("m3c2_export")
	# M3c2 第三輪審查：匯出訊息是三行（「已匯出到：」、路徑、說明）
	var exp_lines := exp_text.split("\n")
	var path := (exp_lines[1] if exp_lines.size() >= 2 else "").strip_edges().replace("\\", "/")
	if not _check(FileAccess.file_exists(path) and path.ends_with(".jychar.json"), "export file missing: " + path):
		return false
	# 測試設定（不是受測物）：朋友給的檔案＝同一份角色換成別的世界、別的角色 id 與名字
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not _check(d is Dictionary and (d as Dictionary).get("passport") is Dictionary, "export file is not an export"):
		return false
	var pp: Dictionary = d["passport"]
	var ident := "local_" + "ef".repeat(16)
	pp["world_id"] = "w_ui_friend"
	pp["char_id"] = "ch_uifriend1"
	pp["identity"] = ident
	pp["name"] = FOREIGN_NAME
	pp["saved_s"] = Time.get_unix_time_from_system()   # 每次執行都比上一次新（重跑時取代上次匯入的那個本地角色）
	pp["char"]["id"] = "ch_uifriend1"
	pp["char"]["identity"] = ident
	pp["char"]["name"] = FOREIGN_NAME
	d["world_name"] = "朋友的江湖"
	var fpath := path.get_base_dir().path_join(FOREIGN_FILE)
	var f := FileAccess.open(fpath, FileAccess.WRITE)
	if not _check(f != null, "cannot write " + fpath):
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	# 測試設定：壞檔、和名字撞到的朋友角色檔（改名列）
	var bad := path.get_base_dir().path_join(BAD_FILE)
	var fb0 := FileAccess.open(bad, FileAccess.WRITE)
	if not _check(fb0 != null, "cannot write " + bad):
		return false
	fb0.store_string("{ 這不是 JSON")
	fb0.close()
	var d2: Dictionary = (d as Dictionary).duplicate(true)
	d2["passport"]["char_id"] = "ch_uifriend2"
	d2["passport"]["char"]["id"] = "ch_uifriend2"
	d2["passport"]["name"] = CHAR_NAME
	d2["passport"]["char"]["name"] = CHAR_NAME
	var f2 := FileAccess.open(path.get_base_dir().path_join(CLASH_FILE), FileAccess.WRITE)
	if not _check(f2 != null, "cannot write " + CLASH_FILE):
		return false
	f2.store_string(JSON.stringify(d2))
	f2.close()
	if not await ui.click_text("匯入角色", "exact"):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_by_class("ImportDialog") != null, 3.0), "ImportDialog did not open"):
		return false
	var dlg := ui.find_by_class("ImportDialog")
	if not await ui.click_text("匯出資料夾", "exact", dlg):
		return false
	# 壞檔：原因寫在預覽區（截圖 m3c2_import_bad）
	if not await _m3c2_pick_file(dlg, BAD_FILE):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_label(ImportDialog.unreadable_text("not_json"), "exact", dlg) != null, 3.0),
			"broken file: preview does not say why"):
		return false
	await ui.shot("m3c2_import_bad")
	# 本世界的檔案（剛剛匯出的）：只有提示與摘要、確定匯入灰掉（截圖 m3c2_import_sameworld）
	if not await _m3c2_pick_file(dlg, path.get_file()):
		return false
	var cb0 := ui.find(func(c): return c is Button and str(c.name) == "ConfirmImport", dlg) as Button
	if not _check(await ui.wait_until(func(): return ui.find_label(ImportDialog.SAME_WORLD_HINT, "exact", dlg) != null \
			and cb0 != null and cb0.disabled and ui.find_label("會被拿掉", "prefix", dlg) == null, 3.0), "same-world file preview wrong"):
		return false
	await ui.shot("m3c2_import_sameworld")
	# 名字撞到：按確定匯入 → 改名列（截圖 m3c2_import_rename）→ 填新名字再送
	if not await _m3c2_pick_file(dlg, CLASH_FILE):
		return false
	if not _check(await ui.wait_until(func(): return cb0 != null and not cb0.disabled, 3.0), "clash file not importable"):
		return false
	if not await ui.click(cb0):
		return false
	var rr := ui.find(func(c): return c is Control and str(c.name) == "RenameRow", dlg) as Control
	if not _check(await ui.wait_until(func(): return rr != null and rr.visible, 4.0), "rename row not shown after name clash (status: %s)" % _status_text()):
		return false
	await ui.shot("m3c2_import_rename")
	var re := ui.find(func(c): return c is LineEdit, rr) as LineEdit
	if not _check(re != null, "rename edit missing"):
		return false
	re.text = RENAMED_NAME
	if not await ui.click(cb0):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_label(RENAMED_NAME + "（外來）", "prefix") != null, 6.0),
			"char list has no %s（外來） after rename import (status: %s)" % [RENAMED_NAME, _status_text()]):
		return false
	if not await ui.click_text("匯入角色", "exact"):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_by_class("ImportDialog") != null and ui.find_by_class("ImportDialog").visible, 3.0), "ImportDialog did not reopen"):
		return false
	dlg = ui.find_by_class("ImportDialog")
	if not await ui.click_text("匯出資料夾", "exact", dlg):
		return false
	var fh := { "b": null }
	await ui.wait_until(func():
		fh["b"] = ui.find_button(FOREIGN_FILE, "contains", dlg, true)
		return fh["b"] != null, 3.0)
	var fb: Button = fh["b"]
	if not _check(fb != null, "import file list has no " + FOREIGN_FILE):
		return false
	if not await ui.click(fb):
		return false
	var confirm := ui.find(func(c): return c is Button and str(c.name) == "ConfirmImport", dlg) as Button
	if not _check(await ui.wait_until(func(): return confirm != null and not confirm.disabled \
			and ui.find_label(FOREIGN_NAME, "contains", dlg) != null, 3.0), "import preview did not show " + FOREIGN_NAME):
		return false
	await ui.shot("m3c2_import_preview")
	if not await ui.click(confirm):
		return false
	if not _check(await ui.wait_until(func(): return ui.find_label(FOREIGN_NAME + "（外來）", "prefix") != null, 6.0),
			"char list has no %s（外來） after import (status: %s)" % [FOREIGN_NAME, _status_text()]):
		return false
	await ui.frames(3)
	await ui.shot("m3c2_char_foreign")
	return true

## 匯入視窗的檔案清單：點某個檔案
func _m3c2_pick_file(dlg: Node, file_name: String) -> bool:
	var fh := { "b": null }
	await ui.wait_until(func():
		fh["b"] = ui.find_button(file_name, "contains", dlg, true)
		return fh["b"] != null, 3.0)
	if not _check(fh["b"] != null, "import file list has no " + file_name):
		return false
	return await ui.click(fh["b"])

## 測試設定：在這個世界放一個「另一個 Steam 帳號」的角色檔（朋友把整個世界資料夾給你）→ 角色選擇出現 Steam 分組；
## 按「進入江湖」跳出確認框（截圖 m3c2_steam_group、m3c2_steam_confirm）→ 取消
func _m3c2_steam_group() -> bool:
	var wid := str(UiClient.world_info().get("world_id", ""))
	if not _check(wid != "", "no world id"):
		return false
	var base: Dictionary = {}
	var cid := str(UiClient.sheet().get("char_id", ""))
	var rc: Dictionary = SaveManager.load_character(wid, UiClient.identity(), cid)
	if rc.get("ok", false) and rc.get("data") is Dictionary:
		base = (rc["data"] as Dictionary).duplicate(true)
	if base.is_empty():
		var r: Dictionary = SaveManager.load_passport(wid, cid)
		if r.get("ok", false) and r.get("data") is Dictionary and (r["data"] as Dictionary).get("char") is Dictionary:
			base = (r["data"]["char"] as Dictionary).duplicate(true)
	if not _check(not base.is_empty(), "no local passport to copy for the Steam character"):
		return false
	for k in 2:
		var dd := base.duplicate(true)
		dd["id"] = "ch_uisteam%02d" % k
		dd["identity"] = STEAM_TEST_IDENT
		dd["name"] = STEAM_TEST_NAME + str(k + 1)
		dd["origin_world"] = ""
		if not _check(SaveManager.save_character(wid, STEAM_TEST_IDENT, dd) == OK, "cannot write steam character"):
			return false
	return true

func _m3c2_steam_confirm() -> bool:
	var hh := { "h": null }
	await ui.wait_until(func():
		hh["h"] = ui.find_label("Steam 角色（", "prefix")
		return hh["h"] != null, 5.0)
	if not _check(hh["h"] != null, "char_select has no Steam group header"):
		return false
	var back := ui.find_button("離開世界", "exact", null, true)
	if not _check(back != null and back.get_global_rect().end.y <= back.get_viewport_rect().size.y + 0.5,
			"離開世界 is off screen with a Steam group: %s" % (str(back.get_global_rect()) if back != null else "missing")):
		return false
	await ui.shot("m3c2_steam_group")
	var row := ui.find_label(STEAM_TEST_NAME + "1", "prefix")
	if not _check(row != null, "Steam character row missing"):
		return false
	var sc := ui.find(func(c): return c is ScrollContainer and str(c.name) == "CharListScroll") as ScrollContainer
	if sc != null:
		sc.ensure_control_visible(row)
		await ui.frames(2)
	var eb := ui.find_button("進入江湖", "exact", row.get_parent().get_parent(), true)   # CharInfo → CharInfoBox → 列
	if not _check(eb != null, "Steam row has no 進入江湖"):
		return false
	if not await ui.click(eb):
		return false
	var ap := ui.find(func(c): return c is Control and str(c.name) == "AltConfirm") as Control
	if not _check(await ui.wait_until(func(): return ap != null and ap.visible, 3.0), "Steam confirm box not shown"):
		return false
	if not _check(ui.find_label("（7656…", "contains", ap) != null, "confirm box does not use the short Steam id"):
		return false
	await ui.shot("m3c2_steam_confirm")
	if not await ui.click_text("取消", "exact", ap):
		return false
	return _check(await ui.wait_until(func(): return not ap.visible, 3.0), "Steam confirm box did not close")

## 角色選擇「離開世界」→ 標題畫面右下角版本列 = BuildInfo.line（截圖 m3c2_title）
func _m3c2_title_line() -> bool:
	if not await ui.click_text("離開世界", "exact"):
		return false
	if not _check(await ui.wait_scene("res://ui/game/title/title_screen.tscn", 10.0), "title screen not shown after 離開世界"):
		return false
	var th := { "l": null }
	await ui.wait_until(func():
		th["l"] = ui.find(func(c): return c is Label and str(c.name) == "BuildInfoLine")
		return th["l"] != null, 5.0)
	var l: Label = th["l"]
	if not _check(l != null, "title: no BuildInfoLine"):
		return false
	var want := BuildInfo.line(GameData.content_hash)
	if not _check(l.text == want and l.text.begins_with("v" + BuildInfo.version()), "title line '%s' (want '%s')" % [l.text, want]):
		return false
	print("[UiPlay] M3c2 標題版本列：" + l.text)
	await ui.shot("m3c2_title")
	return true
