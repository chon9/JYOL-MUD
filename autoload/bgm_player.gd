extends Node
## 背景音樂（docs/BGM_PLAN.md §3–§4）。純客戶端表現層：只聽 SceneRouter / ClientState 的訊號，不送 intent、不進存檔。
## 曲目配置皆為【推測】，見 BGM_PLAN §3.2；個別地區可在 regions.json 用 "bgm": "<context>" 覆寫。

const BGM_TRACKS := {
	# start / loop_end 單位秒（BGM_PLAN §1 實測靜音點）；gain_db 讓各曲約略拉到 −16 LUFS
	"tianya_guitu": { "path": "res://assets/bgm/群俠聚金庸 天涯循歸途.mp3", "gain_db": -5.3, "start": 0.55, "loop_end": 196.2 },
	"tianye":       { "path": "res://assets/bgm/江湖路 田野風光.mp3",     "gain_db": -3.1, "start": 0.60, "loop_end": 163.5 },
	"daojian":      { "path": "res://assets/bgm/天涯任我行 刀劍同行.mp3", "gain_db": -4.6, "start": 0.57, "loop_end": 150.7 },
	"shipo":        { "path": "res://assets/bgm/石破天驚撼武林.mp3",       "gain_db": -3.8, "start": 0.46, "loop_end": 122.3 },
	"fengqi":       { "path": "res://assets/bgm/風起雲湧震九州.mp3",       "gain_db": -4.4, "start": 0.55, "loop_end": 102.1 },
}
const CONTEXT_TRACK := {
	"title": "tianya_guitu", "town": "tianya_guitu", "sect": "tianya_guitu",
	"wild": "tianye", "dungeon": "fengqi", "battle": "daojian", "boss": "shipo",
}
const TYPE_CONTEXT := { "CITY": "town", "SECT": "sect", "WILD": "wild", "DUNGEON": "dungeon" }
const TITLE_SCENES := ["title", "char_select", "char_create"]
const LOOP_XFADE := 2.0
const SETTINGS_PATH := "user://settings.json"   # 舊位置（沒有 data_root.txt 時）；實際用 _settings_path()（跟著 DataRoot）

static func _settings_path() -> String:
	return DataRoot.path("settings.json")
const SILENT_DB := -60.0

var enabled := true
var volume := 0.6                      # 0..1，Music 匯流排音量

var _players: Array[AudioStreamPlayer] = []
var _active := 0                       # _players 裡正在播的那個
var _track := ""                       # 正在播的曲目鍵
var _region_track := ""                # 地區曲（戰鬥結束要回到它）
var _region_pos := 0.0                 # 開戰時地區曲的播放位置
var _in_battle := false
var _tweens: Array = [null, null]
var _streams: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless" or CliArgs.current().has("no-music"):
		enabled = false
		set_process(false)
		return
	_load_settings()
	_ensure_bus()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)
	SceneRouter.scene_changed.connect(_on_scene_changed)
	ClientState.region_changed.connect(_on_region_changed)
	ClientState.battle_opened.connect(_on_battle_opened)
	ClientState.battle_closed.connect(_on_battle_closed)
	if SceneRouter.current in TITLE_SCENES:
		play_context("title")

# ---------------------------------------------------------------- 公開 API

func play_context(ctx: String, fade := 2.5) -> void:
	var key: String = CONTEXT_TRACK.get(ctx, "")
	if key == "":
		return
	if not _in_battle:
		_region_track = key
	_crossfade_to(key, 0.0, fade, fade)

func set_music_volume(linear: float) -> void:
	volume = clampf(linear, 0.0, 1.0)
	_apply_bus_volume()
	_save_settings()

func set_music_enabled(on: bool) -> void:
	enabled = on
	_apply_bus_volume()
	_save_settings()

# ---------------------------------------------------------------- 訊號

func _on_scene_changed(scene_name: String) -> void:
	if scene_name in TITLE_SCENES:
		_in_battle = false
		play_context("title")

func _on_region_changed(view: Dictionary) -> void:
	var ctx := _context_for_region(str(view.get("region", "")))
	if ctx == "":
		return
	var key: String = CONTEXT_TRACK[ctx]
	if _in_battle:
		# 戰鬥中被移到別區：只更新要恢復的曲子，從頭播
		if key != _region_track:
			_region_track = key
			_region_pos = 0.0
		return
	if key != _track:
		play_context(ctx)

func _on_battle_opened(state: Dictionary) -> void:
	if _in_battle:
		return
	_in_battle = true
	_region_pos = _position()
	var key: String = CONTEXT_TRACK["boss" if _has_boss(state) else "battle"]
	if key == _track:
		return   # 鬼王洞打一般怪：同一首，不中斷
	_crossfade_to(key, 0.0, 0.6, 0.3)

func _on_battle_closed(result: Dictionary) -> void:
	if not _in_battle:
		return
	_in_battle = false
	if _region_track == "" or _region_track == _track:
		return
	# 戰敗：戰鬥曲淡出拉長（BGM_PLAN §4.3）。不用 await，避免狀態卡在戰鬥中
	var died := bool(result.get("you_died", false))
	_crossfade_to(_region_track, _region_pos, 2.5 if died else 1.2, 2.0)

# ---------------------------------------------------------------- 播放

func _process(_dt: float) -> void:
	if _track == "" or _players.is_empty():
		return
	var p := _players[_active]
	if not p.playing:
		return
	# 不靠匯入的 loop：快到 loop_end 時用另一個播放器從 start 重播，交叉淡化
	var info: Dictionary = BGM_TRACKS[_track]
	if p.get_playback_position() >= float(info["loop_end"]) - LOOP_XFADE:
		_crossfade_to(_track, 0.0, LOOP_XFADE, LOOP_XFADE, true)

func _crossfade_to(key: String, from_pos: float, fade_out: float, fade_in: float, force := false) -> void:
	if _players.is_empty() or not BGM_TRACKS.has(key):
		return
	if key == _track and not force:
		return
	var info: Dictionary = BGM_TRACKS[key]
	var stream := _stream(key)
	if stream == null:
		return
	var old := _active
	var new := 1 - _active
	# 舊的淡出後停掉
	_fade(old, SILENT_DB, fade_out, true)
	var p := _players[new]
	p.stream = stream
	p.volume_db = SILENT_DB
	var start := float(info["start"])
	if from_pos <= start or from_pos >= float(info["loop_end"]) - LOOP_XFADE:
		from_pos = start
	p.play(from_pos)
	_fade(new, float(info["gain_db"]), fade_in, false)
	_active = new
	_track = key
	print("[BgmPlayer] %s @%.1fs" % [key, from_pos])

func _fade(idx: int, to_db: float, secs: float, stop_after: bool) -> void:
	var prev = _tweens[idx]
	if prev != null and prev.is_valid():
		prev.kill()
	var p := _players[idx]
	if not p.playing:
		return
	var t := create_tween()
	t.tween_property(p, "volume_db", to_db, maxf(secs, 0.01))
	if stop_after:
		t.tween_callback(p.stop)
	_tweens[idx] = t

func _position() -> float:
	if _players.is_empty() or not _players[_active].playing:
		return 0.0
	return _players[_active].get_playback_position()

func _stream(key: String) -> AudioStream:
	if _streams.has(key):
		return _streams[key]
	var path: String = BGM_TRACKS[key]["path"]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = false
	_streams[key] = s
	if s == null:
		push_warning("[BgmPlayer] missing track %s" % path)
	return s

# ---------------------------------------------------------------- 查表

func _context_for_region(region_id: String) -> String:
	var row: Dictionary = GameData.tables.get("regions", {}).get(region_id, {})
	if row.is_empty():
		return ""
	var override := str(row.get("bgm", ""))
	if override != "" and CONTEXT_TRACK.has(override):
		return override
	return TYPE_CONTEXT.get(str(row.get("type", "")), "")

func _has_boss(state: Dictionary) -> bool:
	var monsters: Dictionary = GameData.tables.get("monsters", {})
	for u in state.get("units", []):
		if u is Dictionary and str(monsters.get(str(u.get("ref", "")), {}).get("kind", "")) == "BOSS":
			return true
	return false

# ---------------------------------------------------------------- 匯流排與設定

func _ensure_bus() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
	_apply_bus_volume()

func _apply_bus_volume() -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, not enabled or volume <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volume, 0.0001)))

func _load_settings() -> void:
	var sp := _settings_path()
	if not FileAccess.file_exists(sp):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(sp))
	if data is Dictionary:
		volume = clampf(float(data.get("music_volume", volume)), 0.0, 1.0)
		enabled = bool(data.get("music_enabled", enabled))

func _save_settings() -> void:
	var data := {}
	var sp := _settings_path()
	DataRoot.ensure_dir(sp.get_base_dir())
	if FileAccess.file_exists(sp):
		var old = JSON.parse_string(FileAccess.get_file_as_string(sp))
		if old is Dictionary:
			data = old
	data["music_volume"] = volume
	data["music_enabled"] = enabled
	var f := FileAccess.open(sp, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
