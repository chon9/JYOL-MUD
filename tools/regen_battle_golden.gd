extends SceneTree
## 重新產生 tests/fixtures/battle_golden_01.json（改動戰鬥邏輯後執行，並人工確認差異）
## godot --headless --path . --script res://tools/regen_battle_golden.gd -- --no-steam

func _init() -> void:
	var T = load("res://tests/unit/test_battle_replay.gd")
	var data: Dictionary = T.build_golden()
	var f := FileAccess.open(T.GOLDEN_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("wrote ", T.GOLDEN_PATH)
	quit(0)
