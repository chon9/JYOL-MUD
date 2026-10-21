extends "res://tests/unit/test_m3d_arts_base.gd"
## M3D_PLAN §4.7（C7，WP-ARTS）：血刀 恐嚇——對象限制（故事／功能／商店／任務 NPC；不是守衛、師父、本派、佈告欄、任務對象）、
## 每個 NPC 每遊戲日一次、威嚇熟練每日上限 200（恐嚇＋血池）、善惡 −10、精 20、神 20、非血刀不行。

func _xd() -> bool:
	if join_char("xuedao") == null:
		return false
	ch().morality = -200
	set_skills({ "weihe": 10 })
	return true

func _prof() -> int:
	return int(ch().skills.prof("weihe"))

func test_effects() -> void:
	if not _xd():
		return
	goto("xx_inn")
	var p0 := _prof()
	var mo: int = ch().morality
	var j0 := int(ch().vitals["jing"])
	var s0 := int(ch().vitals["shen"])
	ok("intimidate", { "npc": "n_xx_innkeeper" })
	assert_eq(_prof() - p0, 20, "威嚇熟練 +20（沒有 < 50 的限制）")
	assert_eq(int(ch().morality) - mo, -10, "善惡 −10")
	assert_eq(j0 - int(ch().vitals["jing"]), 20, "精 −20")
	assert_eq(s0 - int(ch().vitals["shen"]), 20, "神 −20")
	assert_eq(str(lastp(Protocol.E_AR_INTIMIDATED).get("npc_name", "")), host().npc_name("n_xx_innkeeper"))
	var said := false
	for k in ["ar_intimidate_1", "ar_intimidate_2", "ar_intimidate_3", "ar_intimidate_4"]:
		if not evs(k).is_empty():
			said = true
	assert_true(said, "NPC 回一句害怕的話")

func test_no_below_50_limit() -> void:
	if not _xd():
		return
	set_skills({ "weihe": 80 })
	goto("xx_inn")
	var p0 := _prof()
	ok("intimidate", { "npc": "n_xx_azi" })
	assert_eq(_prof() - p0, 20, "威嚇 80 照樣長（跟雜務 q_ch_xd_kongxia 不同）")

func test_daily_once_per_npc() -> void:
	if not _xd():
		return
	goto("xx_inn")
	ok("intimidate", { "npc": "n_xx_laodenuo" })
	assert_eq(reason("intimidate", { "npc": "n_xx_laodenuo" }), "intimidate_daily")
	ok("intimidate", { "npc": "n_xx_qiaofeng" })   # 別人可以
	var day: float = host().day_s()
	ws.world["world_time_s"] = (floorf(ws.world_time() / day) + 1.0) * day + 1.0
	ws.advance(0.1)
	Survival.rest_full(ch(), tables(), ws.options)
	ok("intimidate", { "npc": "n_xx_laodenuo" })

func test_daily_cap_200() -> void:
	if not _xd():
		return
	goto("xx_inn")
	var day := int(host().clock()["day"])
	ch().counters[ArtsRules.COUNTER_WEIHE_GAIN] = { "day": day, "n": 190 }
	var p0 := _prof()
	ok("intimidate", { "npc": "n_xx_innkeeper" })
	assert_eq(_prof() - p0, 10, "只剩 10 點額度")
	p0 = _prof()
	ok("intimidate", { "npc": "n_xx_azi" })
	assert_eq(_prof() - p0, 0, "滿 200：熟練不再長")
	assert_eq(int(lastp(Protocol.E_AR_INTIMIDATED).get("gain", -1)), 0)

func test_bad_targets() -> void:
	if not _xd():
		return
	goto("xx_inn")
	assert_eq(reason("intimidate", { "npc": "n_xx_cook" }), "intimidate_bad_target", "師父（MASTER）")
	assert_eq(reason("intimidate", { "npc": "n_xx_pharmacist" }), "not_here", "不在同一間房")
	goto("xx_gate_e")
	assert_eq(reason("intimidate", { "npc": "n_xx_guard" }), "intimidate_bad_target", "守衛")
	goto("xd_yard")
	assert_eq(reason("intimidate", { "npc": "n_xd_spar" }), "intimidate_bad_target", "本派的人")
	# 佈告欄（WP-LAW 的 BOARD；資料還沒合併時略過）
	if tables()["npcs"].has("n_law_board_xx"):
		goto(str(tables()["npcs"]["n_law_board_xx"]["room"]))
		assert_eq(reason("intimidate", { "npc": "n_law_board_xx" }), "intimidate_bad_target", "佈告欄")
	# 任務進行中的對象
	var row := { "kind": "STORY", "services": [] }
	assert_true(ArtsRules.intimidate_target_ok(row, "", "xuedao", false))
	assert_false(ArtsRules.intimidate_target_ok(row, "", "xuedao", true), "任務對象")
	assert_false(ArtsRules.intimidate_target_ok({ "kind": "STORY", "services": ["TOURNEY"] }, "", "xuedao", false), "比武報名")
	assert_false(ArtsRules.intimidate_target_ok({ "kind": "FUNC", "services": ["CLEANSE"] }, "", "xuedao", false), "天師")

func test_quest_target_refused() -> void:
	if not _xd():
		return
	# 恐嚇雜務的牧民：接了 q_ch_xd_kongxia 就是任務對象
	goto("xd_tent")
	ok("intimidate", { "npc": "n_xd_herder" })
	var day: float = host().day_s()
	ws.world["world_time_s"] = (floorf(ws.world_time() / day) + 1.0) * day + 1.0
	ws.advance(0.1)
	Survival.rest_full(ch(), tables(), ws.options)
	ok("quest_accept", { "npc": "n_xd_herder", "quest": "q_ch_xd_kongxia" })
	assert_eq(reason("intimidate", { "npc": "n_xd_herder" }), "intimidate_bad_target", "任務進行中的對象")

func test_not_xd_and_vitals() -> void:
	if not _xd():
		return
	goto("xx_inn")
	ch().vitals["jing"] = 19
	assert_eq(reason("intimidate", { "npc": "n_xx_innkeeper" }), "not_enough_jing")
	ch().vitals["jing"] = 100
	ch().vitals["shen"] = 19
	assert_eq(reason("intimidate", { "npc": "n_xx_innkeeper" }), "not_enough_shen")
	ch().vitals["shen"] = 100
	ch().sect = "xingxiu"
	assert_eq(reason("intimidate", { "npc": "n_xx_innkeeper" }), "intimidate_not_xd")

# ---------------------------------------------------------------- 介面（npc_dialog.gd 的 WP-ARTS 區塊）
const SHOTS_DIR := "K:/Project/JY-Mini-OL-Work/shots/m3d/WP-ARTS"
var _ui_nodes: Array = []

func _dialog_for(npc: String) -> NpcDialog:
	ok("talk", { "npc": npc })
	var menu := lastp("npc_menu")
	var d := NpcDialog.new()
	var g := IntentGate.new()
	tree.root.add_child(g)
	_ui_nodes.append(g)
	g.set_sender(func(kind, args):
		var r := send(str(kind), args)
		var sq := seq
		g.resolve.call_deferred(sq, bool(r.get("ok", false)), str(r.get("reason", "")))
		return sq)
	d.gate = g
	tree.root.add_child(d)
	d.open_menu(menu, "")
	return d

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for i in 3:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := tree.root.get_texture().get_image()
	if img == null:
		return
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	img.save_png(SHOTS_DIR.path_join(name + ".png"))

func test_ui_intimidate_menu() -> void:
	if not _xd():
		return
	goto("xx_inn")
	ws.flush()
	var d := _dialog_for("n_xx_innkeeper")
	await tree.process_frame
	var b: Button = d.service_buttons.get(NpcDialog.ARTS_INTIMIDATE)
	assert_true(b != null, "血刀弟子對掌櫃有「恐嚇」")
	if b != null:
		assert_eq(b.text, "恐嚇")
		d.visible = true
		await _shot("npc_dialog_intimidate")
		var p0 := _prof()
		b.pressed.emit()
		await tree.process_frame
		assert_eq(_prof() - p0, 20, "按下 → intimidate { npc }")
	d.queue_free()
	var d2 := _dialog_for("n_xx_cook")
	assert_false(d2.service_buttons.has(NpcDialog.ARTS_INTIMIDATE), "師父沒有「恐嚇」")
	d2.queue_free()
	ch().sect = "huashan"
	s().sheet_dirty = true
	host().flush_session(s(), true)
	ws.flush()
	var d3 := _dialog_for("n_xx_azi")
	assert_false(d3.service_buttons.has(NpcDialog.ARTS_INTIMIDATE), "不是血刀弟子沒有「恐嚇」")
	d3.queue_free()
	for n in _ui_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_ui_nodes.clear()
