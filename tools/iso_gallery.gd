extends SceneTree
## 等角戰場畫面圖鑑（只截圖、不斷言）：把真實介面驗收拍不到的站位擺出來看，例如玩家在前排面向左、
## 後排名字牌貼在上緣、被兩隻狼包夾、倒在敵人腳下、相鄰兩隻狼、勝利時屍體在玩家前面、低血量、攻擊目標高亮。
## 主機的開場站位永遠是玩家在左上角，所以這些畫面要用假的戰鬥快照擺出來（只是畫面，不經過主機與規則）。
##
##   godot --path . --script res://tools/iso_gallery.gd [--resolution 1920x1032] -- --no-steam --out=<資料夾>
## 需要視窗（不能 --headless）。每張圖存成 <資料夾>/<編號>_<名稱>.png，完成印 ISO_GALLERY_OK。

const BID := 3

var out_dir := ""
var view_size := Vector2(1280, 720)
var root_ctl: Control
var view: BattleIsoView
var shot_n := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	if out_dir == "" or DisplayServer.get_name() == "headless":
		print("ISO_GALLERY_FAIL need --out=<dir> and a window (no --headless)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	view_size = root.get_visible_rect().size   # 戰場填滿整個視窗（視窗大小用 Godot 的 --resolution 調）
	root_ctl = Control.new()
	root_ctl.size = view_size
	root.add_child(root_ctl)

	# 1. 玩家在最前排、敵人在左邊：玩家要面向左，前排名字牌與氣條不出界；輪到我（藍色光圈）
	_scene("front_row_facing_left", [_me(Vector2i(4, 7), 120, 186), _wolf(2, "野狼甲", Vector2i(3, 7)), _rabbit(3, "大野兔", Vector2i(1, 6))], true)
	await _wait(0.6)
	await _shot("front_row_facing_left")

	# 2. 玩家在最後一排上緣：名字牌貼著上緣；蓄勢中（沒有光圈）
	_scene("back_row_top_edge", [_me(Vector2i(4, 0), 186, 186), _wolf(2, "野狼甲", Vector2i(5, 0)), _wolf(3, "野狼乙", Vector2i(4, 1))], false)
	await _wait(0.6)
	await _shot("back_row_top_edge_charging")

	# 3. 被兩隻狼包夾，同時挨兩下又砍中一隻（交手中的飄字、閃紅、透視）
	_scene("sandwich", [_me(Vector2i(0, 0), 120, 168), _wolf(2, "野狼甲", Vector2i(1, 0)), _wolf(3, "野狼乙", Vector2i(0, 1))], false)
	await _wait(0.4)
	_ev("atk_claw", { "atk_uid": 2, "def_uid": 1, "dmg": 30, "crit": true, "def_qi": 90 })
	_ev("atk_blade", { "atk_uid": 1, "def_uid": 2, "dmg": 14, "def_qi": 236 })
	_ev("atk_claw", { "atk_uid": 3, "def_uid": 1, "dmg": 18, "def_qi": 72 })
	await _wait(0.3)
	await _shot("sandwich_hits")
	await _wait(1.6)
	await _shot("sandwich_after_flash")

	# 4. 戰敗：倒在兩隻狼腳下，最後幾下同時到（飄字不疊成柱子、屍體看得到）
	_scene("defeat", [_me(Vector2i(5, 3), 30, 186), _wolf(2, "野狼甲", Vector2i(6, 3)), _wolf(3, "野狼乙", Vector2i(5, 4))], false)
	await _wait(0.4)
	_ev("atk_blade", { "atk_uid": 1, "def_uid": 2, "dmg": 15, "def_qi": 200 })
	_ev("battle_miss", { "atk_uid": 2, "def_uid": 1 })
	_ev("atk_claw", { "atk_uid": 3, "def_uid": 1, "dmg": 14, "def_qi": 16 })
	_ev("atk_claw", { "atk_uid": 2, "def_uid": 1, "dmg": 16, "def_qi": 0 })
	_ev("battle_death", { "uid": 1 })
	_ev("battle_end", { "result": "DEFEAT" })
	await _wait(0.35)
	await _shot("defeat_last_hits")
	await _wait(1.2)
	await _shot("defeat_result")

	# 5. 戰敗：大野兔站在屍體前面
	_scene("defeat_rabbit", [_me(Vector2i(6, 2), 0, 168, "DEAD"), _rabbit(2, "大野兔", Vector2i(6, 3))], false)
	view.vm.ended = true
	await _wait(0.8)
	await _shot("defeat_rabbit_in_front")

	# 5b. 戰敗（審查 round 3）：一隻狼站在屍體正前方一格，連咬幾下才倒；結果出來 2 秒後：
	#     屍體不被狼蓋住、「倒下」牌不撞狼的名字／氣條、飄字不留在半空
	_scene("defeat_wolf_front", [_me(Vector2i(5, 3), 40, 174), _wolf(2, "野狼", Vector2i(5, 4))], false)
	await _wait(0.4)
	_ev("atk_claw", { "atk_uid": 2, "def_uid": 1, "dmg": 16, "def_qi": 24 })
	await _wait(0.5)
	_ev("atk_blade", { "atk_uid": 1, "def_uid": 2, "dmg": 12, "def_qi": 114 })
	await _wait(0.5)
	_ev("atk_claw", { "atk_uid": 2, "def_uid": 1, "dmg": 16, "def_qi": 8 })
	await _wait(0.5)
	_ev("atk_claw", { "atk_uid": 2, "def_uid": 1, "dmg": 32, "crit": true, "def_qi": 0 })
	_ev("battle_death", { "uid": 1 })
	_ev("battle_end", { "result": "DEFEAT" })
	view.settle()
	await _wait(2.0)
	await _shot("defeat_wolf_in_front_settled")

	# 6. 勝利：狼的屍體在玩家前一格，玩家低血量
	_scene("victory", [_me(Vector2i(2, 2), 34, 186), _wolf(2, "野狼", Vector2i(3, 2), "DEAD")], false)
	view.vm.ended = true
	await _wait(0.8)
	await _shot("victory_corpse_in_front_low_hp")

	# 7. 相鄰兩隻狼（加一隻在斜前方）
	_scene("wolves", [_me(Vector2i(1, 3), 186, 186), _wolf(2, "野狼甲", Vector2i(6, 3)), _wolf(3, "野狼乙", Vector2i(7, 3)), _wolf(4, "野狼丙", Vector2i(6, 4))], true)
	await _wait(0.6)
	await _shot("adjacent_wolves_my_turn")

	# 8. 按「攻」後：可打的目標格高亮（滑鼠停在其中一格）
	_scene("attack", [_me(Vector2i(4, 4), 150, 186), _wolf(2, "野狼甲", Vector2i(5, 4)), _wolf(3, "野狼乙", Vector2i(4, 5))], true)
	view.set_highlight([Vector2i(5, 4), Vector2i(4, 5)], UiTheme.HIGHLIGHT_TARGET)
	view.hover_cell = Vector2i(5, 4)
	await _wait(0.6)
	await _shot("attack_target_highlight")

	# 9. M3c 第三輪審查：武器出招特效的方向（真實介面驗收裡玩家永遠在野兔正上方，只拍得到往下打）：
	#    往左（翻面）、往左下／右下斜角、往右上、正下方；輪到我（雙線菱形不能留在身後的格子露出兩角）
	#    （等角投影：螢幕 x ∝ 格 x − 格 y、螢幕 y ∝ 格 x + 格 y）
	for c in [["blade", "left", Vector2i(5, 4), Vector2i(4, 5)], ["sword", "down_left", Vector2i(5, 3), Vector2i(5, 4)],
			["fist", "down_right", Vector2i(5, 3), Vector2i(6, 3)], ["sword", "up_right", Vector2i(5, 4), Vector2i(5, 3)],
			["fist", "up_left", Vector2i(5, 4), Vector2i(4, 4)], ["blade", "below", Vector2i(5, 3), Vector2i(6, 4)],
			["staff", "right", Vector2i(4, 5), Vector2i(5, 4)]]:
		var me := _me(c[2], 150, 186)
		me["wtype"] = { "blade": "BLADE", "sword": "SWORD", "fist": "", "staff": "STAFF" }[c[0]]
		me["weapon"] = { "uid": "it_0001", "name": "兵器", "weapon_type": me["wtype"] }
		_scene("wfx_" + c[1], [me, _rabbit(2, "大野兔", c[3])], true)
		await _wait(0.5)
		_ev("battle_await", { "units": [1], "deadline_tick": 999999 })
		_ev("atk_" + str(c[0]), { "atk_uid": 1, "def_uid": 2, "dmg": 12, "def_qi": 100 })
		# 命中時刻 ≈ 開始後 IMPACT_AT；特效在命中前 LEAD 秒出現、停 HOLD 秒 → 拍在停留段中間
		await _wait(BattleIsoView.IMPACT_AT - WeaponFx.LEAD + WeaponFx.FADE_IN + WeaponFx.HOLD * 0.5)
		await _shot("wfx_%s_%s" % [c[0], c[1]])

	print("ISO_GALLERY_OK shots=%d dir=%s" % [shot_n, out_dir])
	quit(0)

func _me(pos: Vector2i, qi: int, qi_max: int, st := "CHARGING") -> Dictionary:
	return { "uid": 1, "name": "介面俠客", "side": 0, "kind": "PLAYER", "look": "player_m", "peer": 1, "pos": [pos.x, pos.y],
		"qi": qi, "qi_max": qi_max, "gauge": 0.0, "rate": 7.0, "state": st, "move_range": 2,
		"weapon": { "uid": "it_0001", "name": "木刀", "weapon_type": "BLADE" } }

func _wolf(uid: int, n: String, pos: Vector2i, st := "CHARGING") -> Dictionary:
	return { "uid": uid, "name": n, "side": 1, "kind": "MONSTER", "ref": "m_wolf", "peer": 0, "pos": [pos.x, pos.y],
		"qi": 0 if st == "DEAD" else 236, "qi_max": 250, "gauge": 0.0, "rate": 6.0, "state": st }

func _rabbit(uid: int, n: String, pos: Vector2i) -> Dictionary:
	return { "uid": uid, "name": n, "side": 1, "kind": "MONSTER", "ref": "m_bigrabbit", "peer": 0, "pos": [pos.x, pos.y],
		"qi": 120, "qi_max": 150, "gauge": 0.0, "rate": 6.0, "state": "CHARGING" }

func _scene(_label: String, units: Array, my_turn: bool) -> void:
	if view != null:
		view.queue_free()
	view = BattleIsoView.new()
	root_ctl.add_child(view)
	view.size = view_size
	view.set_region("xixia_wild")
	var st := { "bid": BID, "w": 12, "h": 8, "tick": 0, "wait_mode": true, "my_uid": 1,
		"escape": [[7, 5], [8, 6]], "units": units }
	view.set_vm(BattleViewModel.from_state(st))
	if my_turn:
		_ev("battle_await", { "units": [1], "deadline_tick": 999999 })

func _ev(key: String, p: Dictionary) -> void:
	var e := { "seq": 1, "t": 0.0, "ch": "BATTLE", "key": key, "bid": BID, "p": p }
	view.vm.apply_event(e)
	view.on_event(e)

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	shot_n += 1
	var path := out_dir.path_join("%02d_%s.png" % [shot_n, n])
	img.save_png(path)
	print("[IsoGallery] " + path)
