extends SceneTree
## M3c2 驗收（M3C2_PLAN §10.3）。
##   godot --headless --path . --script res://tools/m3c2_acceptance.gd -- --no-steam [--only=chores[,spar]] [--workers=4] [--timeout=2400]
## 劇本：chores chores_strict chores_all novice spar weihe econ carry_export_import carry_hosted offline_steam title_line reject_msg
## （§10.3 表；chores 的 classic_strict 世界拆成 chores_strict 一個 worker）。
##
## 作法照 tools/m3c_acceptance.gd：協調器（本檔，不帶 --m3c2-worker）每個劇本開一個 worker 子行程（同一個檔案帶
## --m3c2-worker）；worker 在自己的行程裡開真的主機（WorldServer＋GameHost、全部系統、--debug-intents），玩家是假的遠端
## 連線（tests/bots/m3c_bot.gd），一切動作經 handle_intent；每個劇本用全新世界（測試根目錄下）。
## 測試捷徑（不是受測物，同 M3b／M3c bot）：refill 回滿；debug_set 設技能、實戰、銀兩、時辰；chores_all／spar／weihe 直接寫
## 門派（SectSystem.on_join，同單元測試）；切磋用 BattleRules.kill 直接結束戰鬥（勝負不是受測物，獎勵才是）；
## carry_* 在同一個行程裡依序開關世界 A／B／C（同一個身分重新連線）。
## 成功印 M3C2_ACCEPT_OK（結束碼 0）；失敗印 M3C2_ACCEPT_FAIL <劇本> <原因> 並傾印 log 尾端（結束碼 1）。
## log 與世界在 <測試根目錄>/m3c2_acceptance/<run>/；不論成敗所有子程序 OS.kill()。不碰擁有者存檔、不寫 C:。

const BOT := "res://tests/bots/m3c_bot.gd"
const BH := preload("res://tests/unit/test_battle_helpers.gd")
## NetworkManager.Mode（autoload 的 enum；SceneTree 腳本不能直接引用 autoload 的識別字）
const MODE_NONE := 0
const MODE_OFFLINE := 1
const MODE_ENET_HOST := 2
const SCENARIOS := ["chores", "chores_strict", "chores_all", "novice", "spar", "weihe", "econ", "carry_export_import",
	"carry_hosted", "offline_steam", "title_line", "reject_msg"]
const STRICT_JOBS := ["chores_strict"]
const DIVINE := "w_sb_yitian"
const STEAM_ID := "76561190000000001"
const STEAM_IDENT := "steam_76561190000000001"
## 每派一件「全天」雜務：[門派, 任務, 給的人, 給的人房間, 做事房間（"" ＝ 不用房間動作）]（同 test_m3c2_chores.gd）
const ALLDAY := [
	["shaolin", "q_ch_sl_saodi", "n_ch_sl_kanshui", "sl_court", "sl_court"],
	["wudang", "q_ch_wd_taqiang", "n_wd_yulianzhou", "wd_tanqiang", "wd_tanqiang"],
	["emei", "q_ch_em_chanding", "n_em_jingxuan", "em_dadian", "em_dadian"],
	["huashan", "q_ch_hs_tiaoqi", "n_ch_hs_yejing", "hs_hall", "hs_hall"],
	["quanzhen", "q_ch_qz_dujing", "n_qz_xiazhicheng", "qz_reading", "qz_reading"],
	["gumu", "q_ch_gm_hanyu", "n_gm_hanyu", "gm_hanyu", "gm_hanyu"],
	["hengshan", "q_ch_hg_tiaoqi", "n_hg_dingjing", "hg_houshan", "hg_houshan"],
	["lingjiu", "q_ch_lj_dingzuo", "n_lj_lanjian", "lj_east", "lj_east"],
	["xingxiu", "q_ch_xh_anqi", "n_xh_canjizi", "xh_mid1", "xh_mid1"],
	["xuedao", "q_ch_xd_pizhi", "n_xd_shengdi", "xd_yard", "xd_yard"],
	["gaibang", "q_ch_gb_jianchai", "n_gb_zhanggun", "gb_yuan", "gb_yuan"],
]

var _finished := false
var _timeout_s := 2400.0
var _root := ""
var _run_id := ""
var _dir := ""
var _pids: Array[int] = []
var _logs: Dictionary = {}
var _t0 := 0
var _bots: Dictionary = {}     # worker：peer -> bot
var _next_peer := 100
var _rejected: Dictionary = {}  # reject_msg：peer -> 拒絕字串

func _initialize() -> void:
	_run.call_deferred()

func _finalize() -> void:
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()

func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var i := a.find("=")
			if i > 0:
				out[a.substr(2, i - 2)] = a.substr(i + 1)
			else:
				out[a.substr(2)] = "true"
	return out

func _run() -> void:
	_t0 = Time.get_ticks_msec()
	var a := _args()
	_timeout_s = maxf(60.0, str(a.get("timeout", "2400")).to_float())
	_root = DataRoot.resolve_for_tool(CliArgs.current())
	if a.has("m3c2-worker"):
		await _worker(a)
	else:
		await _coordinate(a)

func _say(msg: String) -> void:
	print("[m3c2_acceptance %6.1fs] %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, msg])

# ======================================================================== 協調器
func _coordinate(a: Dictionary) -> void:
	randomize()
	_run_id = "%04x" % (randi() % 0x10000)
	_dir = ProjectSettings.globalize_path(_root.path_join("m3c2_acceptance/%s" % _run_id))
	DirAccess.make_dir_recursive_absolute(_dir)
	var jobs: Array = SCENARIOS.duplicate()
	if a.has("only"):
		jobs = []
		for j in str(a["only"]).split(",", false):
			if not (j in SCENARIOS):
				_fail_out("? unknown scenario " + j)
				return
			jobs.append(j)
	var n_workers := clampi(int(str(a.get("workers", "4"))), 1, 10)
	_say("run=%s dir=%s scenarios=%s workers<=%d" % [_run_id, _dir, ",".join(jobs), n_workers])
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var queue: Array = jobs.duplicate()
	var running: Dictionary = {}
	var results: Dictionary = {}
	var deadline := Time.get_ticks_msec() + int(_timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		while not queue.is_empty() and running.size() < n_workers:
			var job: String = queue.pop_front()
			var log_path := _dir.path_join(job + ".log")
			_logs[job] = log_path
			var args := PackedStringArray(["--headless", "--path", proj, "--log-file", log_path, "--script",
				"res://tools/m3c2_acceptance.gd", "--", "--no-steam", "--debug-intents", "--m3c2-worker",
				"--m3c2-run=%s" % _run_id, "--job=" + job, DataRoot.child_arg(_root)])
			if job in STRICT_JOBS:
				args.append("--rule-preset=classic_strict")
			var pid := OS.create_process(exe, args, false)
			if pid <= 0:
				_fail_out("%s spawn failed" % job)
				return
			_pids.append(pid)
			running[job] = pid
			_say("spawned %s pid=%d" % [job, pid])
		await create_timer(0.5, true, false, true).timeout
		for job in running.keys():
			var wpid: int = running[job]
			if OS.is_process_running(wpid):
				continue
			running.erase(job)
			var txt := _log_text(job)
			for line in txt.split("\n"):
				if line.begins_with("M3C2_JOB_OK ") or line.begins_with("M3C2_JOB_FAIL "):
					results[job] = line.strip_edges()
					_say(line.strip_edges())
			if txt.contains("SCRIPT ERROR"):
				results[job] = "M3C2_JOB_FAIL %s SCRIPT ERROR in %s" % [job, _logs[job]]
			if not results.has(job):
				results[job] = "M3C2_JOB_FAIL %s worker exited (code %d) without a result" % [job, OS.get_process_exit_code(wpid)]
			if str(results[job]).begins_with("M3C2_JOB_FAIL"):
				_dump(job)
		if queue.is_empty() and running.is_empty():
			break
	for job in running:
		OS.kill(running[job])
		if not results.has(job):
			results[job] = "M3C2_JOB_FAIL %s timeout" % job
			_dump(job)
	print("")
	print("==== M3c2 驗收 run=%s ====" % _run_id)
	var failed: Array = []
	for job in jobs:
		var line := str(results.get(job, "M3C2_JOB_FAIL %s missing" % job))
		print(("PASS  " if line.begins_with("M3C2_JOB_OK") else "FAIL  ") + line.substr(line.find(" ") + 1))
		if not line.begins_with("M3C2_JOB_OK"):
			failed.append(line)
	var elapsed := (Time.get_ticks_msec() - _t0) / 1000.0
	if failed.is_empty():
		print("M3C2_ACCEPT_OK run=%s scenarios=%d elapsed=%.0fs" % [_run_id, jobs.size(), elapsed])
		_finish(0)
	else:
		for f in failed:
			var rest := str(f).substr(str(f).find(" ") + 1)
			print("M3C2_ACCEPT_FAIL " + rest)
		_finish(1)

func _log_text(job: String) -> String:
	var p: String = _logs.get(job, "")
	if p == "" or not FileAccess.file_exists(p):
		return ""
	return FileAccess.get_file_as_string(p)

func _dump(job: String) -> void:
	var lines := _log_text(job).split("\n")
	print("----- %s (%s) 尾端 -----" % [job, _logs.get(job, "")])
	var at := -1
	for i in lines.size():
		if lines[i].contains("SCRIPT ERROR"):
			at = i
			break
	if at >= 0:
		print("\n".join(lines.slice(maxi(0, at - 3), mini(lines.size(), at + 12))))
	else:
		print("\n".join(lines.slice(maxi(0, lines.size() - 40))))

func _fail_out(msg: String) -> void:
	print("M3C2_ACCEPT_FAIL " + msg)
	_finish(1)

func _finish(code: int) -> void:
	if _finished:
		return
	_finished = true
	_finalize()
	quit(code)

# ======================================================================== worker
func _ws() -> Node:
	return root.get_node("WorldServer")

func _sm() -> Node:
	return root.get_node("SaveManager")

func _nm() -> Node:
	return root.get_node("NetworkManager")

func _gd() -> Node:
	return root.get_node("GameData")

func _capture(peer_id: int, what: String, payload: Variant) -> void:
	if what == "rejected":
		_rejected[peer_id] = payload
	var b = _bots.get(peer_id)
	if b != null:
		b.on_capture(what, payload)

var _world := ""

func _worker(a: Dictionary) -> void:
	var run := str(a.get("m3c2-run", "x"))
	var job := str(a.get("job", ""))
	randomize()
	DataRoot.override_for_tests(_root)
	var wroot := _root.path_join("m3c2_acceptance/worlds")
	_sm().root_dir = wroot
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(wroot))
	var ws := _ws()
	ws.debug_intents = true
	ws.set_time_scale(1.0)
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	root.get_node("ClientState").capture_remote = _capture
	# 單機（OFFLINE）：外來角色一律允許（§5.3）；carry_hosted 自己改成開房
	_nm().set("mode", MODE_OFFLINE)
	var t0 := Time.get_ticks_msec()
	_world = "m3c2_%s_%s" % [run, job]
	var res := {}
	if ws.start(_world) != OK:
		res = { "ok": false, "err": "world start failed: " + str(ws.last_error) }
	else:
		ws.rng.seed = hash(_world)
		var fn := Callable(self, "_sc_" + job)
		if not fn.is_valid():
			res = { "ok": false, "err": "no scenario " + job }
		else:
			res = await fn.call()
	if ws.running:
		ws.stop()
	_bots.clear()
	root.get_node("ClientState").capture_remote = Callable()
	_nm().set("mode", MODE_NONE)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	if bool(res.get("ok", false)):
		print("M3C2_JOB_OK %s %.1fs %s" % [job, secs, str(res.get("info", ""))])
	else:
		print("M3C2_JOB_FAIL %s %.1fs %s" % [job, secs, str(res.get("err", "?"))])
	await process_frame
	quit(0 if bool(res.get("ok", false)) else 1)

const NAME_CHARS := "甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉戌亥春夏秋冬東南西北"
func unique_name(prefix: String) -> String:
	var out := prefix
	for i in 4:
		out += NAME_CHARS[randi() % NAME_CHARS.length()]
	return out

func _new_bot(tag: String, city := "xixia", gender := "M", strong := true):
	_next_peer += 1
	var b = load(BOT).new(_ws(), _next_peer, unique_name(tag), tag)
	b.city = city
	b.gender = gender
	b.keep_weak = not strong
	_bots[_next_peer] = b
	b.create_char()
	return b

func _ok(info: String) -> Dictionary:
	return { "ok": true, "info": info }

func _bad(b) -> Dictionary:
	return { "ok": false, "err": "[%s] %s" % [b.label, b.err] }

func _err(msg: String) -> Dictionary:
	return { "ok": false, "err": msg }

func host():
	return _ws().game

func opts() -> Dictionary:
	return _ws().options

func tables() -> Dictionary:
	return host().tables

## 測試捷徑：直接入派（同單元測試；不是受測物）
func _join(b, sect: String) -> void:
	opts()["sect_hostile_entry"] = false
	b.ch().sect = sect
	host().sects.on_join(b.s(), sect, str(tables()["sects"][sect].get("head_npc", "")))
	b.refill()

## 雜務學點：lp × decay_pct[n-1]/100（n 是本遊戲日第幾次；超過長度用最後一個）
func _chore_lp(qid: String, nth: int) -> int:
	var c: Dictionary = tables()["quests"][qid]["chore"]
	var dec: Array = c.get("decay_pct", [100])
	var pct := int(dec[mini(nth - 1, dec.size() - 1)])
	return int(floor(int(c["lp"]) * pct / 100.0))

## 接 → （房間動作）→ 交；回傳交差的 intent 結果（失敗時 b.err 有原因）
func _do_chore(b, qid: String, giver: String, groom: String, wroom: String) -> Dictionary:
	if not b.walk(groom) or not b.must("quest_accept", { "npc": giver, "quest": qid }):
		return { "ok": false, "reason": b.err }
	if wroom != "":
		if not b.walk(wroom) or not b.must("story_act", { "act": qid + ":a_work" }):
			return { "ok": false, "reason": b.err }
	if not b.walk(groom):
		return { "ok": false, "reason": b.err }
	b.refill()
	return b.send("quest_turn_in", { "npc": giver, "quest": qid })

func _advance_shichen(b, n: float) -> bool:
	var ok: bool = b.debug("world_s_add", host().day_s() / 12.0 * n)
	b.advance(0.3)
	return ok

## 切磋：用 BattleRules.kill 直接結束目前的戰鬥（同 test_m3c_npc_attack.finish）
func _finish_battle(b, win := true) -> void:
	var sess: Session = b.s()
	if sess == null or sess.battle_id == 0:
		return
	var entry: Dictionary = host().battles.active.get(sess.battle_id, {})
	if entry.is_empty():
		return
	var bt: Battle = entry["battle"]
	var me: BattleUnit = null
	for u in bt.units:
		if u.is_player() and int(u.peer) == int(b.peer):
			me = u
	for u in bt.units:
		if win and u.side != me.side and u.is_active():
			BattleRules.kill(bt, u, me)
	if not win:
		var foe: BattleUnit = null
		for u in bt.units:
			if u.side != me.side and u.is_active():
				foe = u
		BattleRules.kill(bt, me, foe)
	bt._check_end(tables())
	var n := 0
	while sess.battle_id == int(bt.id) and n < 200:
		_ws().advance(0.1)
		n += 1
	b.flush_view()

# ------------------------------------------------------------------------ chores
## 新角色（男）走到少林拜師 → 卯時接「挑水」、竹林挑水、交差（學點、基本輕功熟練、精）→ 冷卻中被拒 →
## 掃地兩次（同一遊戲日第 2 次 60%）→ 讀經交差時神不夠 chore_tired（任務留著）→ 回神後交差
func _sc_chores() -> Dictionary:
	var b = _new_bot("雜務")
	if b.err != "":
		return _bad(b)
	if not b.walk("sl_gate") or not b.must("join_sect", { "npc": "n_sl_zhike" }):
		return _bad(b)
	if not b.debug("skill:basic_body", 5):
		return _bad(b)
	if not b.to_next_shichen("卯"):
		return _bad(b)
	var lp0: int = b.ch().learn_points
	var body0: int = b.ch().skills.prof("basic_body")
	var r := _do_chore(b, "q_ch_sl_tiaoshui", "n_ch_sl_kanshui", "sl_court", "sl_zhulin")
	if not b.expect(r.get("ok", false), "挑水 turn in: %s" % str(r.get("reason", ""))):
		return _bad(b)
	var lp1: int = int(b.ch().learn_points) - lp0
	var body1: int = int(b.ch().skills.prof("basic_body")) - body0
	if not b.expect(lp1 == _chore_lp("q_ch_sl_tiaoshui", 1), "挑水 學點 +%d (want %d)" % [lp1, _chore_lp("q_ch_sl_tiaoshui", 1)]):
		return _bad(b)
	if not b.expect(body1 == 30, "挑水 basic_body prof +%d (want 30)" % body1):
		return _bad(b)
	if not b.expect_reason("quest_accept", { "npc": "n_ch_sl_kanshui", "quest": "q_ch_sl_tiaoshui" }, Protocol.R_QUEST_COOLDOWN):
		return _bad(b)
	# 掃地（全天）：第 1 次、冷卻過後同一遊戲日第 2 次
	var lp := int(b.ch().learn_points)
	r = _do_chore(b, "q_ch_sl_saodi", "n_ch_sl_kanshui", "sl_court", "sl_court")
	if not b.expect(r.get("ok", false), "掃地 1: %s" % str(r.get("reason", ""))):
		return _bad(b)
	var s1: int = int(b.ch().learn_points) - lp
	if not b.expect_reason("quest_accept", { "npc": "n_ch_sl_kanshui", "quest": "q_ch_sl_saodi" }, Protocol.R_QUEST_COOLDOWN):
		return _bad(b)
	if not _advance_shichen(b, 1.3):
		return _bad(b)
	lp = int(b.ch().learn_points)
	r = _do_chore(b, "q_ch_sl_saodi", "n_ch_sl_kanshui", "sl_court", "sl_court")
	if not b.expect(r.get("ok", false), "掃地 2: %s" % str(r.get("reason", ""))):
		return _bad(b)
	var s2: int = int(b.ch().learn_points) - lp
	if not b.expect(s1 == _chore_lp("q_ch_sl_saodi", 1) and s2 == _chore_lp("q_ch_sl_saodi", 2),
			"掃地 學點 %d, %d (want %d, %d)" % [s1, s2, _chore_lp("q_ch_sl_saodi", 1), _chore_lp("q_ch_sl_saodi", 2)]):
		return _bad(b)
	# 讀經：代價（神 20）付不起 → chore_tired，任務留著；回神後交差
	if not b.walk("sl_hall") or not b.must("quest_accept", { "npc": "n_ch_sl_jingseng", "quest": "q_ch_sl_dujing" }):
		return _bad(b)
	if not b.must("story_act", { "act": "q_ch_sl_dujing:a_work" }):
		return _bad(b)
	b.ch().vitals["shen"] = 5
	if not b.expect_reason("quest_turn_in", { "npc": "n_ch_sl_jingseng", "quest": "q_ch_sl_dujing" }, Protocol.R_CHORE_TIRED):
		return _bad(b)
	if not b.expect(b.ch().quests.get("active", {}).has("q_ch_sl_dujing"), "讀經 dropped after chore_tired"):
		return _bad(b)
	b.refill()
	if not b.must("quest_turn_in", { "npc": "n_ch_sl_jingseng", "quest": "q_ch_sl_dujing" }):
		return _bad(b)
	return _ok("少林拜師；挑水 學點 +%d、基本輕功熟練 +%d、冷卻中 %s；掃地 +%d → 同日第 2 次 +%d；讀經 神不夠 → %s、回神後交差" % [
		lp1, body1, Protocol.R_QUEST_COOLDOWN, s1, s2, Protocol.R_CHORE_TIRED])

## classic_strict 世界：同樣的挑水 → 學點 0、熟練度照加
func _sc_chores_strict() -> Dictionary:
	if not b_rules_strict():
		return _err("world rules are not classic_strict (chore_xuedian=%s)" % str(host().rules.get("chore_xuedian", null)))
	var b = _new_bot("嚴格雜務")
	if b.err != "":
		return _bad(b)
	if not b.walk("sl_gate") or not b.must("join_sect", { "npc": "n_sl_zhike" }):
		return _bad(b)
	if not b.debug("skill:basic_body", 5) or not b.to_next_shichen("卯"):
		return _bad(b)
	var lp0: int = b.ch().learn_points
	var body0: int = b.ch().skills.prof("basic_body")
	var r := _do_chore(b, "q_ch_sl_tiaoshui", "n_ch_sl_kanshui", "sl_court", "sl_zhulin")
	if not b.expect(r.get("ok", false), "strict 挑水: %s" % str(r.get("reason", ""))):
		return _bad(b)
	var dlp: int = int(b.ch().learn_points) - lp0
	var dbody: int = int(b.ch().skills.prof("basic_body")) - body0
	if not b.expect(dlp == 0 and dbody == 30, "strict 挑水 學點 %+d（want 0）熟練 %+d（want 30）" % [dlp, dbody]):
		return _bad(b)
	return _ok("classic_strict：挑水 學點 %+d、基本輕功熟練 %+d" % [dlp, dbody])

func b_rules_strict() -> bool:
	return host().rules.get("chore_xuedian", true) == false and host().rules.get("spar_rewards", true) == false

## 11 派各做一件全天雜務（1.0A＋1.0B 世界）：完成、有 reward 事件
func _sc_chores_all() -> Dictionary:
	var eras: Array = _ws().world.get("enabled_eras", [])
	if not ("1.0B" in eras):
		return _err("world eras %s lack 1.0B (丐幫)" % str(eras))
	var done: PackedStringArray = []
	for row in ALLDAY:
		var b = _new_bot("雜" + str(row[0]).left(2), "xixia")
		if b.err != "":
			return _bad(b)
		_join(b, str(row[0]))
		var n0: int = b.mark()
		var lp0: int = b.ch().learn_points
		var r := _do_chore(b, str(row[1]), str(row[2]), str(row[3]), str(row[4]))
		if not b.expect(r.get("ok", false), "%s %s: %s" % [row[0], row[1], str(r.get("reason", ""))]):
			return _bad(b)
		if not b.expect(not b.evs("reward", n0).is_empty(), "%s: no reward event" % row[1]):
			return _bad(b)
		done.append("%s %s +%d" % [row[0], row[1], int(b.ch().learn_points) - lp0])
		_ws().remove_session(b.peer)
		_bots.erase(b.peer)
	return _ok("11 派全天雜務：" + "、".join(done))

# ------------------------------------------------------------------------ novice
## 少林新弟子向知客僧學佛法 10 次：熟練度 = 10 ×（悟性熟練 × novice_learn_pct）、精 = 10 × max(1, 悟性精 × novice_jing_pct)；
## 佛法設到 40 再學：回到原值
func _sc_novice() -> Dictionary:
	var b = _new_bot("新手")
	if b.err != "":
		return _bad(b)
	if not b.walk("sl_gate") or not b.must("join_sect", { "npc": "n_sl_zhike" }):
		return _bad(b)
	var rules: Dictionary = host().rules
	# M3c2 審查：新手期另看實戰（novice_xp_below）→ 實戰設在門檻下 1（35 級上限仍夠學到 40）；第三段改成老手
	var xp_below := int(rules.get("novice_xp_below", 30000))
	b.debug("combat_xp", maxi(12250, xp_below - 1))
	b.debug("learn_points", 5000)
	var lpct := int(rules.get("novice_learn_pct", 100))
	var jpct := int(rules.get("novice_jing_pct", 100))
	var c = b.ch()
	var wc := Learning.wit_cost(int(c.effective_attrs(tables(), opts())["wit"]))
	var res := []
	for phase in ["novice", "normal", "veteran"]:
		if phase == "normal" and not b.debug("skill:foxa", 40):
			return _bad(b)
		if phase == "veteran" and (not b.debug("skill:foxa", 10) or not b.debug("combat_xp", xp_below)):
			return _bad(b)
		c.vitals["jing"] = 9000
		c.vitals["neili"] = 9000
		c.vitals["shen"] = 9000
		var p0: int = c.skills.prof("foxa")
		var j0 := int(c.vitals["jing"])
		if not b.must("learn", { "npc": "n_sl_zhike", "skill": "foxa", "times": 10 }):
			return _bad(b)
		var dp: int = int(c.skills.prof("foxa")) - p0
		var dj: int = j0 - int(c.vitals["jing"])
		var want_p := 10 * (roundi(int(wc["prof"]) * lpct / 100.0) if phase == "novice" else int(wc["prof"]))
		var want_j := 10 * (maxi(1, roundi(int(wc["jing"]) * jpct / 100.0)) if phase == "novice" else int(wc["jing"]))
		if not b.expect(dp == want_p and dj == want_j, "%s: 熟練 +%d 精 -%d（want +%d -%d；悟性熟練 %d 精 %d；規則 %d%%/%d%%）" % [
				phase, dp, dj, want_p, want_j, int(wc["prof"]), int(wc["jing"]), lpct, jpct]):
			return _bad(b)
		res.append("%s 熟練 +%d 精 -%d" % [phase, dp, dj])
	return _ok("佛法 10 次（規則 %d%%／%d%%）：%s" % [lpct, jpct, "；".join(res)])

# ------------------------------------------------------------------------ spar
## 少林切磋弟子（M3c2 整合補上的 n_sl_spar／m_sl_dizi）31 場、spar_daily_cap 30：前 30 場有實戰與學點，第 31 場 ch_spar_capped
func _sc_spar() -> Dictionary:
	var b = _new_bot("切磋")
	if b.err != "":
		return _bad(b)
	_join(b, "shaolin")
	opts()["spar_daily_cap"] = 30
	# 從一個遊戲日的開頭打，免得中途換日重設
	var day: float = host().day_s()
	b.debug("world_s_add", (floorf(host().now_s() / day) + 1.0) * day + 1.0 - host().now_s())
	if not b.walk("sl_wuchang"):
		return _bad(b)
	var gave := 0
	var xp_sum := 0
	var lp_sum := 0
	for i in 31:
		b.refill()
		var xp0: int = b.ch().combat_xp
		var lp0: int = b.ch().learn_points
		var n0: int = b.mark()
		if not b.must("fight", { "npc": "n_sl_spar" }):
			return _bad(b)
		_finish_battle(b, true)
		var dx: int = int(b.ch().combat_xp) - xp0
		var dl: int = int(b.ch().learn_points) - lp0
		if i < 30:
			if not b.expect(dx > 0 and dl > 0, "spar %d: xp %+d lp %+d (want > 0)" % [i + 1, dx, dl]):
				return _bad(b)
			gave += 1
			xp_sum += dx
			lp_sum += dl
		else:
			if not b.expect(dx == 0 and dl == 0, "spar 31: xp %+d lp %+d (want 0)" % [dx, dl]):
				return _bad(b)
			if not b.expect(not b.evs(Protocol.E_CH_SPAR_CAPPED, n0).is_empty(), "spar 31: no ch_spar_capped"):
				return _bad(b)
	var sd: Variant = b.ch().counters.get("spar_day", {})
	return _ok("少林切磋 30 場有獎勵（實戰共 +%d、學點共 +%d）、第 31 場 ch_spar_capped；counters.spar_day.n=%s" % [
		xp_sum, lp_sum, str((sd as Dictionary).get("n", "?") if sd is Dictionary else "?")])

# ------------------------------------------------------------------------ weihe
## 血刀弟子（威嚇 100）對木樁：2000 次 BattleStatus.try_proc 觸發率 ∈ [0.20, 0.25]；觸發時傷害 × 1.4（同一下攻擊對照）
func _sc_weihe() -> Dictionary:
	var xd := { "sect": "xuedao", "sect_skill": { "id": "weihe", "effect": "HEAVY", "level": 100 },
		"jing": 9000, "jing_max": 9000, "shen": 88, "neili": 9000, "neili_max": 9000 }
	var bt := BH.make_battle([BH.player_spec(xd), BH.monster("m_dummy")], 2001)
	var u := bt.unit(1)
	var hits := 0
	var n := 2000
	for i in n:
		u.jing = 9000
		u.neili = 9000
		if BattleStatus.try_proc(bt, u, "HEAVY", BH.tables()):
			hits += 1
	var rate := hits / float(n)
	if rate < 0.20 or rate > 0.25:
		return _err("觸發率 %.3f 不在 [0.20, 0.25]" % rate)
	if not is_equal_approx(BattleStatus.HEAVY_MULT, 1.4):
		return _err("HEAVY_MULT %s" % str(BattleStatus.HEAVY_MULT))
	var checked := 0
	var ratios: PackedStringArray = []
	for sd in range(1, 400):
		var a := _weihe_hit(xd, sd)
		if not bool(a["proc"]) or int(a["dmg"]) <= 0:
			continue
		var base := _weihe_hit(xd.merged({ "jing": 2 }, true), sd)
		if bool(base["proc"]) or int(a["dmg"]) != maxi(1, roundi(int(base["dmg"]) * 1.4)):
			return _err("seed %d：觸發 %d vs 基礎 %d（want ×1.4）" % [sd, int(a["dmg"]), int(base["dmg"])])
		ratios.append("%d/%d" % [int(a["dmg"]), int(base["dmg"])])
		checked += 1
		if checked >= 5:
			break
	if checked < 3:
		return _err("only %d proc hits found" % checked)
	return _ok("威嚇 100：2000 次觸發 %d（%.1f%%）；觸發傷害 ×1.4（%s）" % [hits, rate * 100.0, "、".join(ratios)])

func _weihe_hit(over: Dictionary, sd: int) -> Dictionary:
	var bt := BH.make_battle([BH.player_spec(over), BH.monster("m_dummy", { "qi": 99999, "qi_max": 99999 })], sd)
	BH.place(bt, 1, 1, 3)
	BH.place(bt, 2, 2, 3)
	var r := BH.do_cmd(bt, 1, { "cmd": "ATTACK", "target": [2, 3] })
	var dmg := 0
	for e in r.events:
		if int(e.p.get("atk_uid", 0)) == 1 and e.p.has("dmg") and not e.p.get("counter", false):
			dmg = int(e.p.dmg)
	return { "dmg": dmg, "proc": not BH.find(r.events, "battle_proc_HEAVY").is_empty() }

# ------------------------------------------------------------------------ econ
func _work_until(b, skill: String, recipe: String, item: String, want: int, max_tries := 120) -> bool:
	var tries := 0
	while b.count_item(item) < want:
		tries += 1
		if tries > max_tries:
			return b.fail("work %s %s: only %d %s after %d tries" % [skill, recipe, b.count_item(item), item, max_tries])
		b.refill()
		var args := { "skill": skill }
		if recipe != "":
			args["recipe"] = recipe
		var r: Dictionary = b.send("work", args)
		if not r.get("ok", false):
			return b.fail("work %s -> %s" % [JSON.stringify(args), str(r.get("reason", ""))])
		var cd := float(tables().get("life_skills", {}).get(skill, {}).get("cooldown_s", 5))
		b.advance(cd + 0.3)
		b.clear_battles()
	return true

## 做到材料用完（每次一份；失敗也會吃材料）
func _work_all(b, skill: String, recipe: String, input: String, per: int, max_tries := 120) -> bool:
	var tries := 0
	while b.count_item(input) >= per:
		tries += 1
		if tries > max_tries:
			return b.fail("work_all %s %s: still %d %s" % [skill, recipe, b.count_item(input), input])
		b.refill()
		var r: Dictionary = b.send("work", { "skill": skill, "recipe": recipe })
		if not r.get("ok", false):
			return b.fail("work %s %s -> %s" % [skill, recipe, str(r.get("reason", ""))])
		b.advance(float(tables().get("life_skills", {}).get(skill, {}).get("cooldown_s", 5)) + 0.3)
		b.clear_battles()
	return true

func _sell_all(b, npc: String, ids: Array) -> int:
	var got := 0
	for id in ids:
		for _i in 50:
			var uid: String = b.uid_of(str(id))
			if uid == "":
				break
			var n := 0
			for it in b.ch().inventory.items:
				if str(it.get("uid", "")) == uid:
					n = int(it.get("n", 1))
			var m0: int = b.ch().money
			if not b.must("sell", { "npc": npc, "item_uid": uid, "n": clampi(n, 1, 99) }):
				return -1
			got += int(b.ch().money) - m0
	return got

## 新角色學裁縫、織布、種田（等級用 debug 設：學藝本身是 M3b 已驗的流程）：自己收成的麻 → 紡線 → 織布 → 縫布袍 → 賣掉，
## 銀兩增加；再用商店買的麻種子走同一條鏈 → 賣掉後銀兩一定比買種子前少（§4.3 防循環）；EconCalc.loop_violations 0 條
const CLOTH_CHAIN := ["a_bupao", "r_mabu", "r_xianzhou", "r_ma"]
func _sc_econ() -> Dictionary:
	var b = _new_bot("裁縫")
	if b.err != "":
		return _bad(b)
	for sk in [["life_farming", 25], ["life_weaving", 10], ["life_tailoring", 10]]:
		if not b.debug("skill:" + sk[0], sk[1]):
			return _bad(b)
	if not b.walk("xx_tiepu") or not b.must("buy", { "npc": "n_xx_zhangtie", "item": "t_chutou", "n": 1 }):
		return _bad(b)
	if not b.walk("xx_buzhuang") or not b.must("buy", { "npc": "n_ls_xx_fangzhi", "item": "t_zhenxian", "n": 1 }):
		return _bad(b)
	# 1) 自己收成的麻
	var m_start: int = b.ch().money
	if not b.walk("hf_paddy") or not _work_until(b, "life_farming", "", "r_ma", 6):
		return _bad(b)
	var ma_got: int = b.count_item("r_ma")
	if not b.walk("xx_buzhuang"):
		return _bad(b)
	if not _work_all(b, "life_weaving", "rc_xianzhou", "r_ma", 1) or not _work_all(b, "life_weaving", "rc_mabu", "r_xianzhou", 2):
		return _bad(b)
	if not _work_all(b, "life_tailoring", "rc_bupao", "r_mabu", 1):
		return _bad(b)
	var bupao: int = b.count_item("a_bupao")
	if not b.expect(bupao >= 1, "harvest chain made no 布袍"):
		return _bad(b)
	var sold := _sell_all(b, "n_ls_xx_fangzhi", CLOTH_CHAIN + ["r_rice", "r_mai"])
	if sold < 0:
		return _bad(b)
	var gain1: int = int(b.ch().money) - m_start
	if not b.expect(gain1 > 0, "harvest chain money %+d (want > 0)" % gain1):
		return _bad(b)
	# 2) 商店買的種子
	var seeds := 4
	var m0: int = b.ch().money
	if not b.must("buy", { "npc": "n_ls_xx_fangzhi", "item": "r_zhongzi_ma", "n": seeds }):
		return _bad(b)
	var spent: int = m0 - int(b.ch().money)
	if not b.walk("hf_paddy") or not _work_all(b, "life_farming", "rc_zhong_ma", "r_zhongzi_ma", 1):
		return _bad(b)
	if not b.walk("xx_buzhuang"):
		return _bad(b)
	if not _work_all(b, "life_weaving", "rc_xianzhou", "r_ma", 1) or not _work_all(b, "life_weaving", "rc_mabu", "r_xianzhou", 2):
		return _bad(b)
	if not _work_all(b, "life_tailoring", "rc_bupao", "r_mabu", 1):
		return _bad(b)
	var bupao2: int = b.count_item("a_bupao")
	var sold2 := _sell_all(b, "n_ls_xx_fangzhi", CLOTH_CHAIN)
	if sold2 < 0:
		return _bad(b)
	var net2: int = int(b.ch().money) - m0
	if not b.expect(net2 < 0, "bought-seed chain money %+d (want < 0)" % net2):
		return _bad(b)
	var viol := EconCalc.loop_violations(tables())
	if not b.expect(viol.is_empty(), "EconCalc.loop_violations: %s" % ", ".join(viol)):
		return _bad(b)
	return _ok("收成麻 ×%d → 布袍 ×%d → 賣掉 %+d 兩（含剩料）；買種子 ×%d（-%d）→ 布袍 ×%d → 賣 %d → 淨 %+d 兩；loop_violations 0（閉包配方 %d 條）" % [
		ma_got, bupao, gain1, seeds, spent, bupao2, sold2, net2, EconCalc.closure_recipe_count(tables())])

# ------------------------------------------------------------------------ carry
func _switch_world(name: String) -> String:
	var ws := _ws()
	if ws.running:
		ws.save_now()
		ws.stop()
	if ws.start(name) != OK:
		return "start %s failed: %s" % [name, str(ws.last_error)]
	return ""

func _char_by_id(ident: String, cid: String):
	return host().char_store.load_char(ident, cid)

func _foreign_import_ev(b, n0: int) -> Dictionary:
	var e: Dictionary = b.last_ev(Protocol.E_FOREIGN_IMPORTED, n0)
	return e.get("p", {}) if e.get("p", {}) is Dictionary else {}

## 世界 A 建角色、給一件未知物品與一把神兵、實戰 99,999,999、匯出 → 世界 B（單機）匯入：外來標記、未知物品拿掉並列在清單、
## 實戰截到 10,000,000、神兵預設拿掉（M3c2 第二輪審查：不接受外來神兵）；再匯入同一份 → foreign_not_newer；
## 回 A 玩一下再匯出 → B（主機打開 allow_foreign_divine）匯入取代（本地 id、角色數不變、神兵照 R10 登記到新角色）；
## 世界 C（同樣打開）已有人持有那把神兵 → 匯入後神兵不在、清單有寫
func _sc_carry_export_import() -> Dictionary:
	var wa := _world
	var wb := _world + "_b"
	var wc := _world + "_c"
	var b = _new_bot("帶走")
	if b.err != "":
		return _bad(b)
	if not b.debug("divine_grant", DIVINE):
		return _bad(b)
	var c = b.ch()
	c.inventory.items.append({ "uid": "it_zz000001", "id": "x_abc", "n": 1, "born_s": 0.0 })
	c.combat_xp = 99999999
	b.s().sheet_dirty = true
	var pp: Dictionary = host().make_passport(c)
	var path: String = _sm().export_character(pp, { "world_name": "A 的江湖", "content_hash": _gd().content_hash })
	if path == "":
		return _err("export failed: " + str(_sm().last_error))
	if not b.expect(path.begins_with(ProjectSettings.globalize_path(_sm().root_dir).path_join("exports")), "export path %s" % path):
		return _bad(b)
	var a_char := str(c.id)
	# ---- 世界 B（單機）
	var why := _switch_world(wb)
	if why != "":
		return _err(why)
	if not b.connect_session():
		return _bad(b)
	var rf: Dictionary = _sm().read_import_file(path)
	if not b.expect(bool(rf.get("ok", false)) and str(rf.get("kind", "")) == "export", "read_import_file %s" % str(rf)):
		return _bad(b)
	var n0: int = b.mark()
	var r: Dictionary = b.send("passport_import", { "passport": rf["passport"] })
	if not b.expect(r.get("ok", false), "import into B: %s" % str(r.get("reason", ""))):
		return _bad(b)
	var bid := str(r.get("data", {}).get("char_id", r.get("char_id", "")))
	if bid == "":
		bid = str(host().char_ref_by_name(b.pname).get("char_id", ""))
	var ic = _char_by_id(b.identity, bid)
	if ic == null:
		return _err("imported char %s not found" % bid)
	var ev := _foreign_import_ev(b, n0)
	var dropped: Array = ev.get("dropped", [])
	var ids: Array = []
	for it in ic.inventory.items:
		ids.append(str(it.get("id", "")))
	var fx: Variant = ic.ext.get("foreign", null)
	if not b.expect(fx is Dictionary and str((fx as Dictionary).get("char_id", "")) == a_char, "ext.foreign %s" % str(fx)):
		return _bad(b)
	if not b.expect(not ("x_abc" in ids) and dropped.any(func(x): return str(x).contains("x_abc")), "unknown item: ids %s dropped %s" % [str(ids), str(dropped)]):
		return _bad(b)
	if not b.expect(int(ic.combat_xp) == 10000000, "combat_xp %d (want 10,000,000)" % int(ic.combat_xp)):
		return _bad(b)
	if not b.expect(not (DIVINE in ids) and str(host().loot.holder_of(DIVINE)) == "" 			and dropped.any(func(x): return str(x).contains("不接受外來神兵")),
			"divine default off: ids %s holder %s dropped %s" % [str(ids), str(host().loot.holder_of(DIVINE)), str(dropped)]):
		return _bad(b)
	var sum: Dictionary = ic.to_summary(tables())
	if not b.expect(bool(sum.get("foreign", false)), "summary foreign %s" % str(sum.get("foreign", null))):
		return _bad(b)
	if not b.expect_reason("passport_import", { "passport": rf["passport"] }, Protocol.R_FOREIGN_NOT_NEWER):
		return _bad(b)
	var count_b: int = host().char_store.count(b.identity)
	var money_b: int = int(ic.money)   # M3c2 第三輪審查（O12）：取代時銀兩沿用 B 的本地角色
	# ---- 回世界 A 玩一下、再匯出
	why = _switch_world(wa)
	if why != "":
		return _err(why)
	if not b.reselect():
		return _bad(b)
	b.advance(5.0)
	b.debug("money", 4321)
	if not b.walk("xx_inn"):
		return _bad(b)
	b.advance(2.0)
	var pp2: Dictionary = host().make_passport(b.ch())
	var path2: String = _sm().export_character(pp2, { "world_name": "A 的江湖", "content_hash": _gd().content_hash })
	if path2 == "" or path2 == path:
		# 同一分鐘的檔名會相同：寫成另一個檔名（檔名只看分鐘，內容的 saved_s 比較新）
		path2 = path.get_basename() + "_2.jychar.json"
		var f := FileAccess.open(path2, FileAccess.WRITE)
		f.store_string(JSON.stringify({ "kind": "jy_char_export", "v": 1, "game_version": BuildInfo.version(), "protocol": Protocol.VERSION,
			"content_fp": BuildInfo.fingerprint12(_gd().content_hash), "world_name": "A 的江湖", "exported_at": "x", "passport": pp2 }))
		f.close()
	# ---- B：比較新的 → 取代
	why = _switch_world(wb)
	if why != "":
		return _err(why)
	if not b.connect_session():
		return _bad(b)
	opts()["allow_foreign_divine"] = true
	var rf2: Dictionary = _sm().read_import_file(path2)
	n0 = b.mark()
	r = b.send("passport_import", { "passport": rf2.get("passport", {}) })
	if not b.expect(r.get("ok", false), "re-import newer: %s" % str(r.get("reason", ""))):
		return _bad(b)
	var ev2 := _foreign_import_ev(b, n0)
	var ic2 = _char_by_id(b.identity, bid)
	# M3c2 第三輪審查（O12）：更新只帶進成長；銀兩與身上物品（含神兵）沿用 B 的本地角色（A 的 4321 兩不會進來）
	if not b.expect(bool(ev2.get("replaced", false)) and ic2 != null and int(ic2.money) == money_b and money_b != 4321 			and (ev2.get("dropped", []) as Array).any(func(x): return str(x).contains("沿用本世界")),
			"replace: ev %s money %s (local %d)" % [str(ev2), str(ic2.money if ic2 != null else "?"), money_b]):
		return _bad(b)
	if not b.expect(host().char_store.count(b.identity) == count_b, "char count %d → %d" % [count_b, host().char_store.count(b.identity)]):
		return _bad(b)
	var ids2: Array = []
	for it in ic2.inventory.items:
		ids2.append(str(it.get("id", "")))
	if not b.expect(not (DIVINE in ids2) and str(host().loot.holder_of(DIVINE)) == "", "replace keeps local goods (no file divine): ids %s holder %s" % [str(ids2), str(host().loot.holder_of(DIVINE))]):
		return _bad(b)
	# ---- 世界 C：神兵已有人持有
	why = _switch_world(wc)
	if why != "":
		return _err(why)
	var owner = _new_bot("神兵主")
	if owner.err != "":
		return _bad(owner)
	if not owner.debug("divine_grant", DIVINE):
		return _bad(owner)
	opts()["allow_foreign_divine"] = true
	if not b.connect_session():
		return _bad(b)
	n0 = b.mark()
	r = b.send("passport_import", { "passport": rf2.get("passport", {}) })
	if not b.expect(r.get("ok", false), "import into C: %s" % str(r.get("reason", ""))):
		return _bad(b)
	var ev3 := _foreign_import_ev(b, n0)
	var cid3 := str(host().char_ref_by_name(b.pname).get("char_id", ""))
	var ic3 = _char_by_id(b.identity, cid3)
	var ids3: Array = []
	if ic3 != null:
		for it in ic3.inventory.items:
			ids3.append(str(it.get("id", "")))
	if not b.expect(ic3 != null and not (DIVINE in ids3) and (ev3.get("dropped", []) as Array).any(func(x): return str(x).contains("神兵")),
			"C: ids %s dropped %s" % [str(ids3), str(ev3.get("dropped", []))]):
		return _bad(b)
	if not b.expect(str(host().loot.holder_of(DIVINE)) == str(owner.ch().id), "C holder %s" % str(host().loot.holder_of(DIVINE))):
		return _bad(b)
	return _ok("A 匯出 %s；B 匯入：外來、x_abc 拿掉、實戰 → 10,000,000、神兵預設拿掉；同一份 → %s；A 再匯出 → B 取代 %s（id 不變、角色數 %d；銀兩與物品沿用本地、檔案的神兵不帶）；C 神兵被佔 → 拿掉並列清單（%s）" % [
		path.get_file(), Protocol.R_FOREIGN_NOT_NEWER, bid, count_b, "；".join(PackedStringArray(ev3.get("dropped", [])))])

## 開房（ENet 主機）：allow_foreign_characters 關 → foreign_disabled；主機在伺服器設定打開 → 成功
func _sc_carry_hosted() -> Dictionary:
	_nm().set("mode", MODE_ENET_HOST)
	var b = _new_bot("客俠")
	if b.err != "":
		return _bad(b)
	var d: Dictionary = b.ch().to_dict()
	d["id"] = "ch_fx000001"
	d["identity"] = "local_abababababababababababababababab"
	d["name"] = unique_name("遠客")
	var pp: Dictionary = JSON.parse_string(JSON.stringify(Passport.make("friend_secret", "w_friend_world", d, 1000.0)))
	opts()["allow_foreign_characters"] = false
	if not b.expect_reason("passport_import", { "passport": pp }, "foreign_disabled"):
		return _bad(b)
	b.s().is_admin = true   # 本機開房的主機玩家（AdminSystem 的管理員）
	if not b.must("server_opts_set", { "key": "allow_foreign_characters", "value": "true" }):
		return _bad(b)
	if not b.must("passport_import", { "passport": pp }):
		return _bad(b)
	var ref: Dictionary = host().char_ref_by_name(str(d["name"]))
	if not b.expect(not ref.is_empty(), "imported char not registered"):
		return _bad(b)
	return _ok("ENet 開房：選項關 → foreign_disabled；主機打開「允許外來角色」→ 匯入 %s" % str(d["name"]))

## 世界裡手動放一個 steam_<id> 角色 → 單機（Steam 沒開）角色清單有它、needs_confirm → char_select { identity } →
## 移動、存檔 → 寫回那個資料夾，本機身分的資料夾沒有多出角色
func _sc_offline_steam() -> Dictionary:
	var b = _new_bot("本機")
	if b.err != "":
		return _bad(b)
	var wid: String = _ws().world_id
	var local_ident: String = b.identity
	var d: Dictionary = b.ch().to_dict()
	d["id"] = "ch_steam0001"
	d["identity"] = STEAM_IDENT
	d["name"] = unique_name("蒸汽")
	d["money"] = 4321
	if _sm().save_character(wid, STEAM_IDENT, d) != OK:
		return _err("plant steam char failed")
	host().char_store.register_name(Character.from_dict(d))
	var local_ids: Array = _sm().list_character_ids(wid, local_ident)
	b.s().is_local = true   # 單機的玩家是本機 session（bot 是假的遠端 peer；alt_identities 只給本機玩家）
	host().test_steam_id = "none"
	var rows: Array = host().char_list_for(b.s())
	var alt: Dictionary = {}
	for row in rows:
		if bool(row.get("alt", false)) and str(row.get("char_id", "")) == "ch_steam0001":
			alt = row
	if not b.expect(not alt.is_empty() and str(alt.get("identity", "")) == STEAM_IDENT and bool(alt.get("needs_confirm", false)),
			"alt row %s" % str(alt)):
		return _bad(b)
	if not b.must("char_select", { "char_id": "ch_steam0001", "identity": STEAM_IDENT }):
		return _bad(b)
	if not b.expect(b.s().identity == STEAM_IDENT and int(b.ch().money) == 4321, "identity %s money %d" % [b.s().identity, int(b.ch().money)]):
		return _bad(b)
	var start: String = b.room()
	if not b.walk("xx_inn"):
		return _bad(b)
	b.ch().money = 9999
	host().save_all()
	var r: Dictionary = _sm().load_character(wid, STEAM_IDENT, "ch_steam0001")
	if not b.expect(bool(r.get("ok", false)) and int(r["data"]["money"]) == 9999 and str(r["data"]["location"]["room"]) == "xx_inn",
			"steam file %s" % str(r.get("data", {}).get("location", {}))):
		return _bad(b)
	if not b.expect(_sm().list_character_ids(wid, local_ident) == local_ids, "local folder changed"):
		return _bad(b)
	host().test_steam_id = ""
	return _ok("Steam 沒開：清單列出 %s（needs_confirm）；選了 → 身分換成 Steam、%s → xx_inn、存檔寫回 steam_ 資料夾；本機資料夾沒多角色" % [
		STEAM_IDENT, start])

# ------------------------------------------------------------------------ title / reject
## 開標題畫面：右下角版本列 = BuildInfo.line(_gd().content_hash)、以 v0.7.0.0 開頭
func _sc_title_line() -> Dictionary:
	var t: Node = (load("res://ui/game/title/title_screen.tscn") as PackedScene).instantiate()
	root.add_child(t)
	for i in 3:
		await process_frame
	var l: Label = t.get("build_label")
	var want := BuildInfo.line(_gd().content_hash)
	var got := l.text if l != null else "<no label>"
	t.queue_free()
	await process_frame
	if got != want or not got.begins_with("v%s　協定 %d　資料 " % [BuildInfo.version(), Protocol.VERSION]):
		return _err("title line '%s' (want '%s')" % [got, want])
	if not got.begins_with("v0.7.0.0"):
		return _err("title line '%s' does not start with v0.7.0.0" % got)
	var pv := str(ProjectSettings.get_setting("application/config/version", ""))
	return _ok("標題版本列「%s」（config/version %s）" % [got, pv])

## 客戶端送錯的 content_hash 握手 → 拒絕字串帶主機的版本、協定、指紋；客戶端訊息同時列主機與自己
func _sc_reject_msg() -> Dictionary:
	var ws := _ws()
	var peer := 777
	ws.on_peer_connected(peer)
	var why: String = ws.handle_hello(peer, { "protocol": Protocol.VERSION, "game_version": Protocol.GAME_VERSION,
		"content_hash": "sha256:000000000000ffff", "identity": "local_" + "cd".repeat(16), "display_name": "錯版" })
	ws.flush()
	var wire := str(_rejected.get(peer, ""))
	var fp := BuildInfo.fingerprint12(_gd().content_hash)
	if why != "content_mismatch":
		return _err("handle_hello -> '%s' (want content_mismatch)" % why)
	if wire != "content_mismatch|%s|%d|%s" % [BuildInfo.version(), Protocol.VERSION, fp]:
		return _err("wire '%s'" % wire)
	var text := UiSocial.reject_text(wire)
	if not text.contains("主機：v" + BuildInfo.version()) or not text.contains(fp) or not text.contains("你：" + BuildInfo.line(_gd().content_hash)):
		return _err("client text '%s'" % text)
	return _ok("content_mismatch → 「%s」" % text.replace("\n", " ／ "))
