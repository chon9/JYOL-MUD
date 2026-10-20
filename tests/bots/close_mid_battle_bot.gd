extends "res://tests/bots/m1_playthrough_bot.gd"
## 回歸：戰鬥中關閉遊戲不能報錯（擁有者回報：按視窗 X 後出現一串 get_unique_id on null / !is_inside_tree）。
## 跑 M1 驗收流程，第一場戰鬥一開就關閉：
##   --close-mode=wm    送出視窗關閉要求（等同按右上角 X，走 SceneRouter 的正常離線流程）
##   --close-mode=quit  直接 get_tree().quit()（舊路徑：場景樹直接拆掉，靠 ClientState 的 is_inside_tree 防護）
## 判定看輸出裡有沒有 SCRIPT ERROR / ERROR，並印出 CLOSE_BOT_SENT。

var _close_sent := false

func _ready() -> void:
	super._ready()
	ClientState.battle_opened.connect(_on_first_battle)

func _on_first_battle(_state: Dictionary) -> void:
	if _close_sent:
		return
	_close_sent = true
	var mode := str(CliArgs.current().get("close-mode", "wm"))
	print("CLOSE_BOT_SENT mode=%s" % mode)
	SceneRouter.exit_code = 0
	if mode == "quit":
		get_tree().quit(0)
	else:
		get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
