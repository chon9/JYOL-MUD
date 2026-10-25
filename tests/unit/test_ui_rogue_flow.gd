extends "res://tests/test_case.gd"
## ROGUE_PLAN §5.2、§5.4、§5.5、§9.1（WP-UI）：用假的 rogue_state 事件序列走 LOBBY → ALLOC → PICK → READY → BATTLE → OVER，
## 每個按鈕送出正確的 intent 與參數；大廳唯讀讀試煉者檔案；HUD 的隊友、兵器、武功；結算畫面；返回標題。
## 不開主機：開主機、換畫面、離開主機都用注入的 Callable；intent 用假的 sender 收下。

var _nodes: Array = []
var _old_root := ""
var _dir := ""
var sent: Array = []
var started: Array = []
var navigated: Array = []
var left := 0

func before_each() -> void:
	UiSettings.reset_for_tests(true)
	var smn: Node = tree.root.get_node("SaveManager")
	_old_root = smn.root_dir
	_dir = temp_dir("ui_rogue_flow")
	smn.root_dir = _dir
	sent = []
	started = []
	navigated = []
	left = 0

func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame
	tree.root.get_node("SaveManager").root_dir = _old_root
	remove_dir_recursive(_dir)

func _screen() -> RogueScreen:
	var s: RogueScreen = (load("res://ui/game/rogue/rogue_screen.tscn") as PackedScene).instantiate()
	s.starter = func(sd: int) -> Error:
		started.append(sd)
		return OK
	s.navigator = func(scene: String) -> void: navigated.append(scene)
	s.leaver = func() -> void: left += 1
	tree.root.add_child(s)
	_nodes.append(s)
	s.gate.set_sender(func(kind: String, args: Dictionary) -> int:
		sent.append([kind, args])
		return 7000 + sent.size())
	return s

func _ok_all(s: RogueScreen) -> void:
	for i in sent.size():
		s.gate.resolve(7001 + i, true, "")

func _write_profile(p: Dictionary) -> void:
	var path := RogueLobbyPanel.profile_path(_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(p))
	f.close()

static func base_state(phase: String, extra: Dictionary = {}) -> Dictionary:
	var st := { "run_id": "rr_flow", "seed": 12345, "phase": phase, "round": 1, "wins": 0, "foes_beaten": 0, "bosses_beaten": 0,
		"next_round_is_boss": false, "extra_picks": 0, "min_rarity": "", "cards": [],
		"roll": { "str": 18, "guts": 15, "wit": 20, "luck": 14, "cal": 16, "agi": 17, "con": 19 }, "alloc_points": 8, "attr_cap": 45,
		"attrs": { "str": 20, "guts": 16, "wit": 20, "luck": 14, "cal": 16, "agi": 19, "con": 21 },
		"allies": [], "arts": [], "gear": { "ARMOR": { "uid": "it_a1", "item_id": "a_bupao", "name": "布衣", "rarity": "COMMON" } },
		"weapons": [ { "uid": "it_w1", "item_id": "w_mudao", "name": "木刀", "weapon_type": "BLADE", "atk": 3, "equipped": true } ],
		"best_card": {}, "profile": { "points_total": 3, "cap": 60, "runs": 1, "best_wins": 2 } }
	for k in extra:
		st[k] = extra[k]
	return st

static func ev(key: String, p: Dictionary, ui := false) -> Dictionary:
	var e := { "seq": 1, "t": 0.0, "ch": "SYSTEM", "key": key, "p": p }
	if ui:
		e["ui"] = true
	return e

static func summary(extra: Dictionary = {}) -> Dictionary:
	var s := { "run_id": "rr_flow", "seed": 12345, "cause": "DEATH", "rounds": 7, "wins": 6, "foes_beaten": 9, "bosses_beaten": 1,
		"best_card": { "id": "rg_c_wpn_w_qingfeng", "title": "青鋒劍", "rarity": "RARE" }, "allies_recruited": 1,
		"points_gained": 5, "points_total": 8, "new_best": true }
	for k in extra:
		s[k] = extra[k]
	return s

# ---------------------------------------------------------------- 大廳

func test_lobby_reads_profile_read_only() -> void:
	_write_profile({ "schema": 1, "points_total": 12, "runs": 4, "best_wins": 7, "total_wins": 15, "foes_beaten": 22, "bosses_beaten": 2,
		"famous_beaten": {}, "famous_allied": {}, "history": [
			{ "t": 100, "seed": 1, "wins": 7, "bosses": 1, "cause": "DEATH", "points": 5, "best_card": { "id": "x", "title": "青鋒劍", "rarity": "RARE" } },
			{ "t": 90, "seed": 2, "wins": 2, "bosses": 0, "cause": "ABANDON", "points": 2, "best_card": {} } ], "updated": 100 })
	var before := FileAccess.get_file_as_string(RogueLobbyPanel.profile_path(_dir))
	var s := _screen()
	await tree.process_frame
	assert_eq(s.view, "LOBBY")
	assert_eq(s.lobby.points_label.text, "永久點數 12 / 60")
	assert_true(s.lobby.stats_label.text.contains("4 局") and s.lobby.stats_label.text.contains("最佳 7 勝"), s.lobby.stats_label.text)
	assert_true(s.lobby.stats_label.text.contains("擊敗 22 名") and s.lobby.stats_label.text.contains("首領 2 位"))
	assert_eq(s.lobby.recent_box.get_child_count(), 2, "two history rows")
	var l0 := (s.lobby.recent_box.get_child(0) as Label).text
	assert_true(l0.contains("勝 7 場") and l0.contains("力戰而亡") and l0.contains("+5") and l0.contains("〔稀〕青鋒劍"), l0)
	assert_true((s.lobby.recent_box.get_child(1) as Label).text.contains("放棄試煉"))
	assert_eq(FileAccess.get_file_as_string(RogueLobbyPanel.profile_path(_dir)), before, "lobby never writes")

func test_lobby_missing_or_broken_profile() -> void:
	var p := RogueLobbyPanel.read_profile(_dir)
	assert_eq(int(p["points_total"]), 0, "no file → default")
	assert_false(FileAccess.file_exists(RogueLobbyPanel.profile_path(_dir)), "not created")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir.path_join("rogue")))
	var f := FileAccess.open(RogueLobbyPanel.profile_path(_dir), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var q := RogueLobbyPanel.read_profile(_dir)
	assert_eq(int(q["points_total"]), 0, "broken → default")

func test_famous_roll_unknown_until_met() -> void:
	var tables := {
		"rogue_foes": {
			"rg_f_zhouzhiruo": { "id": "rg_f_zhouzhiruo", "monster": "m_em_zhouzhiruo", "npc": "n_em_zhouzhiruo", "boss": true },
			"rg_f_qiaofeng": { "id": "rg_f_qiaofeng", "monster": "m_rg_qiaofeng", "npc": "n_xx_qiaofeng", "boss": true },
			"rg_f_wolf": { "id": "rg_f_wolf", "monster": "m_wolf", "boss": false } },
		"rogue_cards": {
			"rg_c_ally_zhouzhiruo": { "id": "rg_c_ally_zhouzhiruo", "kind": "ALLY", "rarity": "RARE", "monster": "m_em_zhouzhiruo", "npc": "n_em_zhouzhiruo" },
			"rg_c_ally_hs_trainee": { "id": "rg_c_ally_hs_trainee", "kind": "ALLY", "rarity": "COMMON", "monster": "m_hs_trainee" } },
		"npcs": { "n_em_zhouzhiruo": { "name": "周芷若" }, "n_xx_qiaofeng": { "name": "喬峰" } },
		"monsters": { "m_wolf": { "name": "野狼" } },
	}
	var list := RogueLobbyPanel.famous_list(tables)
	assert_eq(list.size(), 2, "bosses + rare allies, merged by person")
	var lob := RogueLobbyPanel.new()
	_nodes.append(lob)
	lob.apply_profile({ "famous_beaten": { "rg_f_qiaofeng": 2 }, "famous_allied": { "rg_c_ally_zhouzhiruo": 1 } }, tables)
	var texts: Array = []
	for e in lob.famous_entries:
		texts.append(e["text"])
	assert_has(texts, "喬峰（敗 2）")
	assert_has(texts, "周芷若（友 1）")
	lob.apply_profile({}, tables)
	for e in lob.famous_entries:
		assert_eq(e["text"], "？？？", "unknown hidden")

# ---------------------------------------------------------------- 開局

func test_start_waits_for_welcome_then_opens() -> void:
	var s := _screen()
	await tree.process_frame
	s.lobby.start_button.pressed.emit()
	assert_eq(started, [0], "host started with random seed")
	assert_true(s.requires_session, "now a session screen")
	assert_eq(sent.size(), 0, "waits for welcome")
	s._on_welcomed({ "mode": "ROGUE" })
	assert_eq(sent, [["rogue_open", {}]])
	assert_true(s.lobby.start_button.disabled, "locked while pending")
	_ok_all(s)
	assert_false(s.lobby.start_button.disabled)

func test_start_failure_shows_reason() -> void:
	var s := _screen()
	s.starter = func(_seed: int) -> Error: return ERR_CANT_CREATE
	await tree.process_frame
	s.start_trial()
	assert_true(s.err_label.text.begins_with("無法開始試煉"), s.err_label.text)
	assert_false(s.requires_session)
	assert_eq(sent.size(), 0)

func test_alloc_sends_start_with_identity() -> void:
	var s := _screen()
	await tree.process_frame
	s.handle_events([ev("rogue_state", base_state("ALLOC"), true)])
	assert_eq(s.view, "ALLOC")
	assert_true(s.alloc_panel.visible and not s.hud.visible)
	var ap: RogueAllocPanel = s.alloc_panel
	assert_eq(ap.points, 8, "5 + profile points")
	assert_eq((ap.value_labels["str"] as Label).text, "18")
	assert_true(ap.identity_box.visible and ap.reroll_button.visible)
	assert_true(ap.confirm_button.disabled, "points left")
	assert_eq(ap.cap_label.text, "單項上限 45")
	ap.spread_even()
	assert_eq(ap.remaining(), 0)
	assert_eq(int(ap.alloc["str"]), 2)
	assert_eq(int(ap.alloc["guts"]), 2)
	ap.name_edit.text = "  "
	ap.gender_option.select(1)
	ap.gender_option.item_selected.emit(1)
	ap.look_option.select(3)
	assert_eq(ap.look_option.get_item_text(3), Looks.name_of("F", 3), "female looks")
	ap.confirm_button.pressed.emit()
	assert_eq(sent.size(), 1)
	assert_eq(sent[0][0], "rogue_start")
	var a: Dictionary = sent[0][1]
	assert_eq(a["name"], "試煉者", "blank name → default")
	assert_eq(a["gender"], "F")
	assert_eq(a["look"], 3)
	var sum := 0
	for k in a["alloc"]:
		sum += int(a["alloc"][k])
	assert_eq(sum, 8)
	assert_eq(a["alloc"].size(), 7, "all seven attributes")

func test_alloc_reroll_and_state_resend_keeps_allocation() -> void:
	var s := _screen()
	await tree.process_frame
	s.apply_state(base_state("ALLOC"))
	s.alloc_panel.add("wit", 1)
	s.apply_state(base_state("ALLOC"))
	assert_eq(int(s.alloc_panel.alloc["wit"]), 1, "same run & roll → keep")
	s.alloc_panel.reroll_button.pressed.emit()
	assert_eq(sent, [["rogue_open", {}]])
	_ok_all(s)
	var st2 := base_state("ALLOC", { "run_id": "rr_new", "roll": { "str": 25, "guts": 13, "wit": 13, "luck": 13, "cal": 13, "agi": 13, "con": 13 } })
	s.apply_state(st2)
	assert_eq(int(s.alloc_panel.alloc["wit"]), 0, "new roll → reset")
	assert_eq((s.alloc_panel.value_labels["str"] as Label).text, "25")

# ---------------------------------------------------------------- 局內

func test_ready_fight_and_abandon() -> void:
	var s := _screen()
	await tree.process_frame
	s.apply_state(base_state("READY", { "round": 5, "next_round_is_boss": true }))
	assert_eq(s.view, "READY")
	assert_true(s.ready_box.visible and s.hud.visible)
	assert_eq(s.ready_title.text, "第 5 回合・準備出戰")
	assert_true(s.ready_boss.visible, "boss warning")
	assert_true(s.hud.boss_label.visible, "hud boss warning")
	assert_eq(s.hud.boss_label.text, "下一場：名人登場")
	assert_true(s.handle_key(KEY_ENTER), "enter = fight")
	assert_eq(sent, [["rogue_fight", {}]])
	assert_true(s.fight_button.disabled, "locked")
	_ok_all(s)
	s.abandon_button.pressed.emit()
	assert_true(s.confirm_panel.visible, "confirm first")
	assert_eq(sent.size(), 1, "nothing sent yet")
	assert_true(s.handle_key(KEY_ESCAPE))
	assert_false(s.confirm_panel.visible)
	# 審查：放棄確認窗裡 Enter＝「再想想」（Enter 平常是出戰，順手一按不能結束這一局）
	s.abandon_button.pressed.emit()
	assert_true(s.handle_key(KEY_ENTER), "enter handled in the confirm box")
	assert_false(s.confirm_panel.visible, "enter = keep going")
	assert_eq(sent.size(), 1, "enter never abandons")
	s.abandon_button.pressed.emit()
	assert_true(s.handle_key(KEY_KP_ENTER))
	assert_eq(sent.size(), 1, "keypad enter never abandons either")
	s.abandon_button.pressed.emit()
	s.confirm_yes.pressed.emit()
	assert_eq(sent[1], ["rogue_abandon", { "confirm": true }])

func test_pick_phase_abandon_button() -> void:
	var s := _screen()
	await tree.process_frame
	s.apply_state(base_state("PICK"))
	s.pick_abandon_button.pressed.emit()
	assert_true(s.confirm_panel.visible)
	s.confirm_no.pressed.emit()
	assert_false(s.confirm_panel.visible)
	assert_eq(sent.size(), 0)

func test_hud_allies_gear_arts_equip() -> void:
	var s := _screen()
	await tree.process_frame
	var st := base_state("READY", { "round": 3, "wins": 2, "foes_beaten": 3,
		"allies": [ { "slot": 0, "name": "周芷若", "ref": "n_em_zhouzhiruo", "rarity": "RARE", "qi_pct": 0.5, "alive": true },
			{ "slot": 1, "name": "小黃", "ref": "", "rarity": "COMMON", "qi_pct": 0.0, "alive": false } ],
		"arts": [ { "id": "hs_jianfa", "name": "華山劍法", "level": 40, "category": "SWORD" },
			{ "id": "xd_daofa", "name": "血刀刀法", "level": 25, "category": "BLADE" },
			{ "id": "basic_inner", "name": "基本內功", "level": 30, "category": "BASIC" },
			{ "id": "basic_sword", "name": "基本劍法", "level": 40, "category": "BASIC" } ],
		"weapons": [ { "uid": "it_w1", "item_id": "w_mudao", "name": "木刀", "weapon_type": "BLADE", "atk": 3, "equipped": true },
			{ "uid": "it_w2", "item_id": "w_qingfeng", "name": "青鋒劍", "weapon_type": "SWORD", "atk": 15, "equipped": false } ] })
	s.apply_state(st)
	var h: RogueHud = s.hud
	assert_eq(h.round_label.text, "第 3 回合")
	assert_eq(h.stats_label.text, "勝 2 場　擊敗 3 名")
	assert_true((h.ally_rows[0]["name"] as Label).text.contains("周芷若"))
	assert_eq(h.ally_status(0), "氣 50%")
	assert_eq(h.ally_status(1), "已殞", "fallen ally")
	assert_true((h.ally_rows[1]["box"] as Control).modulate.r < 0.9, "greyed")
	assert_eq(h.equip_buttons.size(), 1, "only the unequipped weapon has a button")
	assert_true(h.gear_box.get_node_or_null("Equipped_it_w1") != null, "equipped weapon framed")
	# 武功：拿刀 → 劍法灰、刀法與內功正常
	assert_eq(str((h.art_rows["hs_jianfa"] as Label).theme_type_variation), "MutedLabel", "sword art greyed with a blade")
	assert_eq(str((h.art_rows["xd_daofa"] as Label).theme_type_variation), "", "blade art fits")
	assert_eq(str((h.art_rows["basic_inner"] as Label).theme_type_variation), "", "inner always fits")
	# 審查：主機送的基本武學類別是 BASIC（server/rogue_system.gd state()），HUD 不能把代碼印給玩家
	var bl := (h.art_rows["basic_sword"] as Label).text
	assert_true(bl.contains("基本武學") and not bl.contains("BASIC"), bl)
	assert_eq(RogueHud.category_name("STAB"), "筆法")
	assert_false(RogueHud.art_fits("STAB", "SWORD"), "筆法要拿筆")
	assert_eq((h.attr_labels["con"] as Label).text, "21")
	(h.equip_buttons["it_w2"] as Button).pressed.emit()
	assert_eq(sent, [["equip", { "item_uid": "it_w2" }]])
	assert_true(RogueHud.art_fits("SWORD", "SWORD") and RogueHud.art_fits("FIST", "SWORD") and not RogueHud.art_fits("WHIP", "FIST"))

func test_log_events_and_errors() -> void:
	var s := _screen()
	await tree.process_frame
	s.handle_events([ev("rogue_card_taken", { "title": "青鋒劍", "rarity_name": "稀" }),
		ev("rogue_round_won", { "round": 2, "qi": 40, "jing": 10, "neili": 5 }),
		ev("rogue_ally_fallen", { "name": "小黃" })])
	assert_true(s.msg_label.text.contains("你取得了〔稀〕青鋒劍。"), s.msg_label.text)
	assert_true(s.msg_label.text.contains("第 2 回合得勝"), s.msg_label.text)
	assert_true(s.msg_label.text.contains("小黃力戰倒下"), s.msg_label.text)
	for i in 6:
		s.add_message("訊息%d" % i)
	assert_eq(s.msg_label.text.split("\n").size(), RogueScreen.MSG_LINES, "keeps the last lines")
	s._on_result(false, "rogue_bad_alloc")
	assert_true(s.err_label.text != "" and not s.err_label.text.contains("rogue_bad_alloc {"), s.err_label.text)
	# 審查：屬性上限不寫死 45，讀主機結果附的 cap
	var cs: Node = tree.root.get_node("ClientState")
	var old_extra: Dictionary = cs.last_result_extra
	cs.last_result_extra = { "cap": 50 }
	s._on_result(false, "rogue_attr_cap")
	assert_true(s.err_label.text.contains("50") and not s.err_label.text.contains("45") and not s.err_label.text.contains("{n}"), s.err_label.text)
	cs.last_result_extra = old_extra
	s._on_result(true, "")
	assert_eq(s.err_label.text, "")

# ---------------------------------------------------------------- 戰鬥、結算

static func battle_state() -> Dictionary:
	return {
		"bid": 9, "w": 12, "h": 8, "tick": 0, "wait_mode": true, "my_uid": 1, "kind": "ROGUE", "escape": [],
		"units": [
			{ "uid": 1, "name": "試煉者", "side": 0, "kind": "PLAYER", "peer": 1, "pos": [1, 3],
			  "qi": 180, "qi_max": 180, "neili": 0, "neili_max": 0, "jing": 92, "jing_max": 92,
			  "gauge": 0.0, "rate": 7.0, "state": "CHARGING", "move_range": 2,
			  "weapon": { "uid": "it_w1", "name": "木刀", "weapon_type": "BLADE" }, "arts": [] },
			{ "uid": 2, "name": "周芷若", "side": 0, "kind": "ALLY", "peer": 0, "pos": [1, 5], "ref": "n_em_zhouzhiruo",
			  "qi": 50, "qi_max": 100, "gauge": 0.0, "rate": 6.0, "state": "CHARGING" },
			{ "uid": 3, "name": "野狼", "side": 1, "kind": "MONSTER", "peer": 0, "pos": [10, 3],
			  "qi": 60, "qi_max": 60, "gauge": 0.0, "rate": 6.25, "state": "CHARGING" },
		],
	}

func test_battle_overlay_and_strip() -> void:
	var s := _screen()
	await tree.process_frame
	s.apply_state(base_state("BATTLE", { "round": 4,
		"allies": [ { "slot": 0, "name": "周芷若", "ref": "n_em_zhouzhiruo", "rarity": "RARE", "qi_pct": 1.0, "alive": true } ] }))
	s.open_battle(battle_state())
	await tree.process_frame
	assert_true(s.battle_open(), "battle overlay")
	assert_true(s.battle.offset_top == RogueScreen.STRIP_H, "below the strip")
	assert_true(s.strip.visible, "strip")
	assert_eq(s.strip_round.text, "江湖試煉　第 4 回合")
	assert_true(s.strip.get_index() > s.battle.get_index(), "strip drawn above the battle")
	s._process(0.0)
	assert_eq(s.strip_allies.get_child_count(), 1, "one ally on the strip")
	var bar := s.strip_allies.get_child(0).get_node("Bar") as ProgressBar
	assert_eq(bar.value, 50.0, "live qi from the battle snapshot")
	assert_false(s.handle_key(KEY_ENTER), "keys go to the battle")
	# 敗：rogue_over 先到，戰鬥畫面還開著 → 收起後顯示結算
	s.handle_events([ev("rogue_over", summary(), true)])
	s.battle.finished.emit()
	await tree.process_frame
	assert_false(s.battle_open())
	assert_false(s.strip.visible)
	assert_eq(s.view, "OVER")
	assert_true(s.summary_panel.visible and not s.hud.visible)

func test_battle_won_returns_to_pick() -> void:
	var s := _screen()
	await tree.process_frame
	s.apply_state(base_state("BATTLE"))
	s.open_battle(battle_state())
	await tree.process_frame
	s.apply_state(base_state("PICK", { "round": 2, "cards": [ { "idx": 0, "id": "a", "kind": "ART", "rarity": "COMMON", "title": "甲" },
		{ "idx": 1, "id": "b", "kind": "ATTR", "rarity": "COMMON", "title": "乙", "points": 3 },
		{ "idx": 2, "id": "c", "kind": "WEAPON", "rarity": "FINE", "title": "丙" } ] }))
	assert_true(s.battle_open(), "result still showing")
	s.battle.finished.emit()
	await tree.process_frame
	assert_eq(s.view, "PICK")
	assert_true(s.pick_box.visible)
	assert_eq(s.cards.size(), 3)

func test_over_summary_and_buttons() -> void:
	var s := _screen()
	await tree.process_frame
	s.apply_state(base_state("OVER", { "summary": summary() }))
	var sp: RogueSummaryPanel = s.summary_panel
	assert_true(sp.visible)
	assert_eq(sp.cause_label.text, "力戰而亡")
	assert_eq(sp.rounds_label.text, "倒在第 7 回合（勝 6 場）", "rounds＝結束時所在的回合（勝場＋1），不說「撐過」")
	assert_eq(RogueSummaryPanel.rounds_text("ABANDON", 7, 6), "於第 7 回合放棄（勝 6 場）")
	assert_eq(RogueSummaryPanel.rounds_text("LEAVE", 3, 2), "於第 3 回合離開（勝 2 場）")
	assert_eq(sp.foes_label.text, "擊敗對手 9 名　首領 1 位")
	assert_eq(sp.best_label.text, "最好的一張卡：〔稀〕青鋒劍")
	assert_true(sp.best_label.get_theme_color("font_color").is_equal_approx(LootUi.rarity_color("RARE")), "rarity color")
	assert_eq(sp.allies_label.text, "招募隊友 1 位")
	assert_eq(sp.points_label.text, "永久點數 +5（累計 8 / 60）")
	assert_true(sp.record_label.visible, "new best")
	assert_false(sp.note_label.visible, "no allies standing → no note")
	# 審查：玩家倒下時隊友還站著 → 說明「試煉以你本人為準」
	sp.apply_summary(summary({ "allies_standing": 1 }))
	assert_true(sp.note_label.visible and sp.note_label.text == UiKeys.ROGUE_DOWN_NOTE, sp.note_label.text)
	var rl := BattleScreen.rogue_result_lines({ "result": "DEFEAT", "you_died": true,
		"rogue": { "round": 6, "won": false, "over": true, "allies_fallen": [], "allies_standing": 1 } })
	assert_true(Array(rl).has(UiKeys.ROGUE_DOWN_NOTE), str(rl))
	for c in ["ABANDON", "TIMEOUT", "LEAVE"]:
		sp.apply_summary(summary({ "cause": c, "new_best": false }))
		assert_eq(sp.cause_label.text, UiKeys.ROGUE_CAUSE_TEXT[c])
		assert_false(sp.record_label.visible)
	sp.again_button.pressed.emit()
	assert_eq(sent, [["rogue_open", {}]], "again = rogue_open")
	_ok_all(s)
	assert_true(s.handle_key(KEY_ENTER), "enter on the summary = again")
	assert_eq(sent.size(), 2)
	assert_eq(sent[1], ["rogue_open", {}])
	sp.title_button.pressed.emit()
	assert_eq(left, 1, "left the trial host")
	assert_eq(navigated, ["title"])

func test_lobby_back_to_title() -> void:
	var s := _screen()
	await tree.process_frame
	s.lobby.title_button.pressed.emit()
	assert_eq(navigated, ["title"])

func test_ui_keys_match_protocol_when_present() -> void:
	# WP-RUN 的 Protocol 常數合併後必須同值（還沒合併時略過）
	var consts := (load("res://core/protocol.gd") as GDScript).get_script_constant_map()
	var mine := (load("res://ui/game/ui_keys.gd") as GDScript).get_script_constant_map()
	for k in ["I_ROGUE_OPEN", "I_ROGUE_START", "I_ROGUE_PICK", "I_ROGUE_FIGHT", "I_ROGUE_ABANDON", "I_ROGUE_DEBUG"]:
		if consts.has(k):
			assert_eq(mine[k], consts[k], k)
	if consts.has("ROGUE_REASONS"):
		for r in consts["ROGUE_REASONS"]:
			assert_has(UiKeys.ROGUE_REASONS, r)
	assert_eq(UiKeys.I_ROGUE_OPEN, "rogue_open")
	assert_eq(UiKeys.ROGUE_CAUSE_TEXT, { "DEATH": "力戰而亡", "ABANDON": "放棄試煉", "TIMEOUT": "久戰不決", "LEAVE": "離開試煉" })
