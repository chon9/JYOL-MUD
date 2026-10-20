extends Control
## 開機（TECH_ARCH 12、M1_PLAN 3.12）：檢查 GameData、顯示 Steam 狀態、依啟動參數決定傳輸並切換畫面。
## - 有 --bot 或 --debug-net → 照 M0 進 net_debug（含 Steam 不可用時自動開離線）。
## - 有連線參數（--offline／--enet-host／--enet-join／--steam-host）且成功 → 角色選擇。
## - 沒有參數 → 標題畫面；Steam 不可用時在標題顯示原因，不自動開離線。

const DEFAULT_BOT := "res://tests/bots/chat_bot.gd"

@onready var _status: Label = $Center/VBox/Status

func _ready() -> void:
	await get_tree().process_frame   # 等所有 Autoload 的 _ready 跑完
	var args := CliArgs.current()

	if not GameData.load_ok:
		_status.text = "資料載入失敗：\n" + "\n".join(GameData.load_errors)
		if DisplayServer.get_name() == "headless":
			SceneRouter.quit(1)
		return

	var lines: PackedStringArray = [SteamManager.status_text()]
	var debug_path := args.has("bot") or args.has("debug-net")
	if args.has("bot"):
		_attach_bot(args["bot"] if args["bot"] is String else DEFAULT_BOT)

	var started := NetworkManager.start_from_args(args)
	var wants_transport := args.has("offline") or args.has("enet-host") or args.has("enet-join") or args.has("steam-host")
	if wants_transport and not started:
		lines.append("啟動參數指定的連線失敗：" + NetworkManager.status_text)
		if args.has("bot") or NetworkManager.dedicated:
			_status.text = "\n".join(lines)
			SceneRouter.quit(1)
			return
		SceneRouter.pending_message = lines[lines.size() - 1]
		SceneRouter.goto("title")
		return
	if debug_path and not wants_transport and not SteamManager.available:
		# M0 行為：除錯／bot 路徑在 Steam 沒開時自動退回單機（GDD 13.1 M0 驗收）
		NetworkManager.start_offline(str(args.get("world", NetworkManager.DEFAULT_WORLD)))
		SceneRouter.pending_message = "%s，已自動進入單機模式。" % SteamManager.status_text()

	_status.text = "\n".join(lines)
	if NetworkManager.dedicated:
		_status.text += "\n專用主機模式：" + NetworkManager.status_text
		return
	if debug_path:
		SceneRouter.goto("net_debug")
	elif wants_transport:
		SceneRouter.goto("char_select")
	else:
		if not SteamManager.available:
			SceneRouter.pending_message = SteamManager.status_text()
		await _play_splash()
		SceneRouter.goto("title")

## 工作室開場圖：引擎的 boot_splash 先顯示同一張圖（載入時不閃白），這裡接著停留到
## SPLASH_HOLD_S 再淡出成黑，然後進標題。按鍵或點滑鼠可以跳過。只有一般開遊戲（沒有參數）才播。
const SPLASH_PATH := "res://assets/splash/splash_studio_jianghu.png"
const SPLASH_HOLD_S := 2.5
const SPLASH_FADE_S := 0.6

var _splash_skip := false

func _play_splash() -> void:
	if DisplayServer.get_name() == "headless" or not ResourceLoader.exists(SPLASH_PATH):
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	var img := TextureRect.new()
	img.name = "Splash"
	img.texture = load(SPLASH_PATH)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(img)
	var left := SPLASH_HOLD_S - Time.get_ticks_msec() / 1000.0   # 從程式啟動起算，boot_splash 已經顯示過的時間也算進去
	while left > 0.0 and not _splash_skip:
		await get_tree().process_frame
		left -= get_process_delta_time()
	var tw := create_tween()
	tw.tween_property(img, "modulate:a", 0.0, SPLASH_FADE_S)
	await tw.finished

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton:
		if event.is_pressed():
			_splash_skip = true

func _attach_bot(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_error("[Boot] bot script not found: " + path)
		SceneRouter.quit(1)
		return
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		# 語法錯誤的 bot 立刻失敗（結束碼 2），不要閒置到 --quit-after
		push_error("[Boot] bot script failed to load: " + path)
		SceneRouter.quit(2)
		return
	var bot := Node.new()
	bot.set_script(script)
	bot.name = "Bot"
	get_tree().root.add_child.call_deferred(bot)
