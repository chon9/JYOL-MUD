extends SceneTree
## 從匯出的 .pck 讀出連線協定版本與資料指紋（tools/export_release.ps1 用 --main-pack 執行；tools/ 不會打包進 .pck）
func _initialize() -> void:
	var loader = load("res://core/data/data_loader.gd").new()
	loader.load_all("res://data")
	print("CONTENT_HASH=" + str(loader.content_hash))
	var p = load("res://core/protocol.gd")
	print("PROTOCOL=" + str(p.VERSION))
	quit(0)
