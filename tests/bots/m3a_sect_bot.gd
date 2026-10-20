extends Node
## M3a 驗收 bot（M3A_PLAN 10.3）：一個程序一個角色，由 tools/m3a_acceptance.gd 啟動（ENet 客戶端）。
## 角色（--m3a-role）：8 個門派 wudang emei hengshan quanzhen gumu lingjiu xingxiu xuedao，外加 jail（少林坐牢劇本）。
## 每派：創角（性別、出生城依 3.2）→ debug_set 設善惡／實戰／銀兩／學點（善惡為負的等走出城才設）→ 城裡買木劍、乾糧
## → **走路**到山門（不用 teleport；遇敵打兔子、其他就逃）→ 途中第一間新地區的野外房間按「查看」偵察並「離開」，
##   之後第一次只遇到兔子的偵察就「迎戰」（使用者要的查看迎戰流程，GDD 5.10）
## → 武當：引薦書任務；古墓：孫婆婆引路 → 拜師（sect_join）→ 學門派技能、心法、入門兵器武功（另：基本內功；恆山 基本醫術；
##   星宿 基本毒術＋放毒法）→ 修煉內力 → 切磋：戰鬥中用驗收招式（move_* 事件）與驗收指令（內／醫／毒／穴）→ 逃離或打完
## → 確認 sect_info 與武功等級。
## 星宿另跑叛派劇本（need_confirm → sect_betray → 本門武功減半、諂媚歸零、公敵、不能再拜、敵對入山開戰）；
## 武當另跑公敵被抓（叛派後在武當走一步 → SECT_GUARD 不能逃 → 戰死 → 押入 wd_siguo）；
## jail：少林拜師 → 殺氣 2500 → sect_breach（JAIL）＋jail_in（sl_siguo；只有 jail_location CAPITAL 時是京城監獄 jc_jail，事件可能是 jail_in_capital）→ 不能走、世界頻道被拒、輕聲細語可用 → 快轉上線時間 → jail_out（sl_gate；京城監獄出獄到 jc_yamen）。
## 參數：--m3a-role=<role> --m3a-run=<4 hex> --m3a-sync=<絕對路徑>
## 規則：只透過 NetworkManager.send_intent() 與 ClientState 互動；一次只送一個 intent。
## 成功印 M3A_BOT_OK role=<r>（結束碼 0）；失敗印 M3A_BOT_FAIL role=<r> step=<n> <原因>（結束碼 2）。

const MIN_SEND_INTERVAL_MS := 60
const RESULT_TIMEOUT_MS := 15000
const BATTLE_TIMEOUT_MS := 240000
const GOTO_ATTEMPTS := 40
const FOOD_MIN := 40
const RABBITS := ["m_rabbit", "m_bigrabbit"]
## 新地區（M3A_PLAN 2.1）＋恆山山道（舊地區的新房間）：第一間有遇敵表的就偵察
const NEW_REGIONS := ["wudang_foot", "emei_road", "zhongnan_foot", "tianshan_road", "xingxiu_road", "xuedao_road"]
const NEW_ROOMS := ["hg_shandao"]

## 3.2 表（綁定）＋學藝計畫 [技能, 目標等級, 師父]。學藝順序：門派技能 → 心法 → 兵器武功（limits_arts 門派武功上限 = 門派技能 + 10）
const SECTS := {
	"wudang": { "name": "武當", "gender": "M", "birth": "dali", "morality": 100, "join": "n_wd_zhangsanfeng",
		"learn": [["basic_inner", 4, "n_wd_yudaiyan"], ["xiayi", 2, "n_wd_songyuanqiao"], ["wd_xinfa", 2, "n_wd_yudaiyan"], ["wd_changquan", 4, "n_wd_yudaiyan"]],
		"arts": ["wd_changquan", "wd_xinfa"], "art": "wd_changquan", "move": "wd_cq_1", "cmd": "INNER", "weapon": "",
		"spar": "n_wd_spar" },
	"emei": { "name": "峨嵋", "gender": "F", "birth": "dali", "morality": 0, "join": "n_em_miejue",
		"learn": [["basic_inner", 4, "n_em_jingxuan"], ["duane", 2, "n_em_jingzhao"], ["em_xinfa", 2, "n_em_jingjia"], ["em_piaoxue", 4, "n_em_jingjia"]],
		"arts": ["em_piaoxue", "em_xinfa"], "art": "em_piaoxue", "move": "em_px_1", "cmd": "INNER", "weapon": "",
		"spar": "n_em_spar" },
	"hengshan": { "name": "恆山", "gender": "F", "birth": "xixia", "morality": 0, "join": "n_hg_dingxian",
		"learn": [["basic_inner", 4, "n_hg_dingjing"], ["cibei", 4, "n_hg_yusao"], ["hg_xinfa", 2, "n_hg_yihe"], ["hg_jianfa", 4, "n_hg_yihe"], ["basic_medic", 2, "n_hg_yizhen"]],
		"arts": ["hg_jianfa", "hg_xinfa"], "art": "hg_jianfa", "move": "hg_jf_1", "cmd": "MEDIC", "weapon": "w_mujian",
		"spar": "n_hg_spar" },
	"quanzhen": { "name": "全真", "gender": "M", "birth": "dali", "morality": 0, "join": "n_qz_qiuchuji",
		"learn": [["basic_inner", 4, "n_qz_qizhicheng"], ["yangsheng", 4, "n_qz_yinzhiping"], ["qz_xinfa", 2, "n_qz_qiuchuji"], ["qz_jianfa", 4, "n_qz_qiuchuji"]],
		"arts": ["qz_jianfa", "qz_xinfa"], "art": "qz_jianfa", "move": "qz_jf_1", "cmd": "INNER", "weapon": "w_mujian",
		"spar": "n_qz_spar" },
	"gumu": { "name": "古墓", "gender": "F", "birth": "dali", "morality": 0, "join": "n_gm_zhangmen", "guide": "n_gm_sunpopo",
		"learn": [["basic_inner", 4, "n_gm_dashijie"], ["qingxin", 4, "n_gm_zhangmen"], ["gm_xinfa", 2, "n_gm_zhangmen"], ["gm_yunu_jian", 4, "n_gm_zhangmen"]],
		"arts": ["gm_yunu_jian", "gm_xinfa"], "art": "gm_yunu_jian", "move": "gm_yn_1", "cmd": "INNER", "weapon": "w_mujian",
		"spar": "n_gm_spar" },
	"lingjiu": { "name": "靈鷲", "gender": "F", "birth": "xixia", "morality": 0, "join": "n_lj_tonglao",
		"learn": [["basic_inner", 5, "n_lj_tonglao"], ["dingxing", 4, "n_lj_lanjian"], ["lj_xiaoyao", 2, "n_lj_tonglao"], ["lj_zhemei", 4, "n_lj_tonglao"]],
		"arts": ["lj_zhemei", "lj_xiaoyao"], "art": "lj_zhemei", "move": "lj_zm_1", "cmd": "ACUPOINT", "weapon": "",
		"spar": "n_lj_spar" },
	"xingxiu": { "name": "星宿", "gender": "M", "birth": "xixia", "morality": -200, "join": "n_xh_dingchunqiu",
		"learn": [["basic_inner", 4, "n_xh_dingchunqiu"], ["chanmei", 4, "n_xh_shihouzi"], ["xh_xinfa", 2, "n_xh_dingchunqiu"], ["xh_chousui", 6, "n_xh_dingchunqiu"], ["basic_poison", 2, "n_xh_dingchunqiu"], ["xh_fangdu", 2, "n_xh_dingchunqiu"]],
		"arts": ["xh_chousui", "xh_xinfa"], "art": "xh_chousui", "move": "xh_cs_1", "cmd": "POISON", "weapon": "",
		"spar": "n_xh_spar" },
	"xuedao": { "name": "血刀", "gender": "M", "birth": "dali", "morality": -200, "join": "n_xd_laozu",
		"learn": [["basic_inner", 4, "n_xd_kuji"], ["weihe", 2, "n_xd_laozu"], ["xd_xinfa", 2, "n_xd_shengdi"], ["xd_daofa", 4, "n_xd_shengdi"]],
		"arts": ["xd_daofa", "xd_xinfa"], "art": "xd_daofa", "move": "xd_df_1", "cmd": "INNER", "weapon": "",
		"spar": "n_xd_spar" },
	# 門規劇本：少林（西夏出生，走東路到少林山門）
	"jail": { "name": "少林", "gender": "M", "birth": "xixia", "morality": 0, "join": "n_sl_zhike", "learn": [], "arts": [],
		"art": "", "move": "", "cmd": "", "weapon": "", "spar": "" },
}
const CMD_EVENTS := {
	"INNER": ["battle_inner_heal"], "MEDIC": ["battle_medic"],
	"POISON": ["battle_poison_ok", "battle_poison_fail"], "ACUPOINT": ["battle_acupoint_ok", "battle_acupoint_fail"],
}
const CITY_SHOPS := {
	"xixia": { "smith": ["xx_smithy", "n_xx_smith"], "food": ["xx_inn", "n_xx_innkeeper"], "wushi": "n_xx_wushi" },
	"dali": { "smith": ["dl_shop", "n_dl_grocer"], "food": ["dl_inn", "n_dl_innkeeper"], "wushi": "n_dl_wushi" },
}

var role := ""
var run := ""
var sync_dir := ""
var cfg: Dictionary = {}
var step := 0
var _done := false
var _results: Dictionary = {}
var _events: Array = []
var _last_send_ms := 0

# 戰鬥模型
var _in_battle := false
var _closed := false
var _close_result: Dictionary = {}
var _open_state: Dictionary = {}
var _open_count := 0
var _my_uid := 0
var _my_side := 0
var _await_me := false
var _units: Dictionary = {}
var _escape: Array = []
var _move_range := 2
var _bid := 0
## 戰鬥策略："road"（兔子就打、其他逃）、"spar"（先用驗收指令與招式，達成後逃）、"defend"（只防，等死）、"flee"
var _mode := "road"
var _move_hit := false
var _cmd_done := false
var _cmd_rejects: Dictionary = {}
var _deaths := 0

# 偵察
var _scout_declined := false
var _scout_accepted := false
var _morality_set := false
var _room_region: Dictionary = {}

func _ready() -> void:
	SceneRouter.exit_code = 1
	var args := CliArgs.current()
	role = str(args.get("m3a-role", ""))
	run = str(args.get("m3a-run", ""))
	sync_dir = str(args.get("m3a-sync", ""))
	ClientState.intent_result.connect(func(seq: int, ok: bool, reason: String): _results[seq] = [ok, reason])
	ClientState.events_received.connect(_on_events)
	ClientState.battle_opened.connect(_on_battle_opened)
	ClientState.battle_closed.connect(_on_battle_closed)
	ClientState.rejected.connect(func(r: String): _fail("rejected: " + r))
	print("[M3aBot:%s] ready run=%s sync=%s" % [role, run, sync_dir])
	if not SECTS.has(role) or run == "":
		_fail("bad args: role=%s run=%s" % [role, run])
		return
	cfg = SECTS[role]
	for rid in GameData.tables.get("maps", {}):
		for room in GameData.tables["maps"][rid].get("rooms", []):
			_room_region[str(room.get("id", ""))] = str(rid)
	_run.call_deferred()

# ======================================================================== 基礎
func _on_events(batch: Array) -> void:
	for e in batch:
		if not (e is Dictionary):
			continue
		_events.append(e)
		if str(e.get("ch", "")) == "BATTLE":
			_battle_event(e)
	if _events.size() > 8000:
		_events = _events.slice(_events.size() - 4000)

func _frames(n := 1) -> void:
	for i in n:
		await get_tree().process_frame

func _sleep(secs: float) -> void:
	await get_tree().create_timer(secs, true, false, true).timeout

func _send(kind: String, args: Dictionary = {}, settle := true) -> Dictionary:
	while Time.get_ticks_msec() - _last_send_ms < MIN_SEND_INTERVAL_MS:
		await get_tree().process_frame
	_last_send_ms = Time.get_ticks_msec()
	var seq := NetworkManager.send_intent(kind, args)
	if seq < 0:
		return { "ok": false, "reason": "not_connected" }
	var t0 := Time.get_ticks_msec()
	while not _results.has(seq):
		await get_tree().process_frame
		if _done:
			return { "ok": false, "reason": "done" }
		if Time.get_ticks_msec() - t0 > RESULT_TIMEOUT_MS:
			return { "ok": false, "reason": "timeout" }
	var r: Array = _results[seq]
	_results.erase(seq)
	if settle:
		await _sleep(0.15)   # 讓主機 flush 事件與 sheet
	return { "ok": bool(r[0]), "reason": str(r[1]) }

func _must(kind: String, args: Dictionary = {}) -> bool:
	var r := await _send(kind, args)
	if not r["ok"]:
		_fail("%s %s -> %s" % [kind, str(args), r["reason"]])
		return false
	return true

func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	print("M3A_BOT_FAIL role=%s step=%d %s (room=%s)" % [role, step, msg, _room()])
	_mark("failed", msg)
	SceneRouter.exit_code = 2
	get_tree().create_timer(0.3, true, false, true).timeout.connect(func(): SceneRouter.quit(2))

func _ok_finish() -> void:
	if _done:
		return
	_done = true
	print("M3A_BOT_OK role=%s scout_declined=%s scout_accepted=%s deaths=%d" % [role, str(_scout_declined),
		str(_scout_accepted), _deaths])
	_mark("ok")
	SceneRouter.exit_code = 0
	get_tree().create_timer(0.3, true, false, true).timeout.connect(func(): SceneRouter.quit(0))

func _check(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond

func _step(n: int, title: String) -> void:
	step = n
	print("[M3aBot:%s] step %d: %s" % [role, n, title])

func _say(msg: String) -> void:
	print("[M3aBot:%s] %s" % [role, msg])

func _mark(s: String, content := "") -> void:
	if sync_dir == "":
		return
	var f := FileAccess.open(sync_dir.path_join("%s.%s" % [role, s]), FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()

func _wait_until(cond: Callable, timeout_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if _done or Time.get_ticks_msec() - t0 > timeout_ms:
			return false
		await get_tree().process_frame
	return true

func _events_since(key: String, from_index: int) -> Array:
	var out: Array = []
	for i in range(maxi(0, from_index), _events.size()):
		if str(_events[i].get("key", "")) == key:
			out.append(_events[i])
	return out

func _wait_event(key: String, from_index: int, timeout_ms: int) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while not _done:
		var got := _events_since(key, from_index)
		if not got.is_empty():
			return got[0]
		if Time.get_ticks_msec() - t0 > timeout_ms:
			break
		await get_tree().process_frame
	return {}

## M3b（O12，審查修正）：jail_location AUTO＋世界有京城監獄（1.0B，新世界預設）→ 被捉拿的公敵關京城監獄；
## 違反門規仍關各派思過處（只有選項 CAPITAL 才送京城，看 jail_breach_resolved）。
## 事件是 jail_in／jail_in_capital 其一，京城監獄出獄送到京城衙門
func _capital() -> bool:
	return str(ClientState.world_info.get("jail_location_resolved", "SECT")) == "CAPITAL"

func _capital_breach() -> bool:
	return str(ClientState.world_info.get("jail_breach_resolved", "SECT")) == "CAPITAL"

func _wait_jail_event(prefix: String, from_index: int, timeout_ms: int) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while not _done:
		for k in [prefix, prefix + "_capital"]:
			var got := _events_since(k, from_index)
			if not got.is_empty():
				return got[0]
		if Time.get_ticks_msec() - t0 > timeout_ms:
			break
		await get_tree().process_frame
	return {}

# ---------- 角色表 ----------
func _sheet() -> Dictionary:
	return ClientState.sheet

func _room() -> String:
	return str(_sheet().get("location", {}).get("room", ""))

func _region() -> String:
	return str(_sheet().get("location", {}).get("region", ""))

func _vital(k: String) -> int:
	return int(_sheet().get("vitals", {}).get(k, 0))

func _money() -> int:
	return int(_sheet().get("money", 0))

func _skill_level(id: String) -> int:
	for s in _sheet().get("skills", []):
		if str(s.get("id", "")) == id:
			return int(s.get("level", 0))
	return 0

func _items(id: String) -> Array:
	var out: Array = []
	for it in _sheet().get("inventory", []):
		if it is Dictionary and str(it.get("id", "")) == id:
			out.append(it)
	return out

func _count(id: String) -> int:
	var n := 0
	for it in _items(id):
		n += int(it.get("n", 1))
	return n

func _first_uid(id: String) -> String:
	var it := _items(id)
	return str(it[0].get("uid", "")) if not it.is_empty() else ""

func _shichen() -> String:
	return str(_sheet().get("clock", {}).get("text", "")).left(1)

func _npc_room(nid: String) -> String:
	return str(GameData.tables.get("npcs", {}).get(nid, {}).get("room", ""))

func _move_name(art: String, move: String) -> String:
	for m in GameData.tables.get("martial_arts", {}).get(art, {}).get("moves", []):
		if str(m.get("id", "")) == move:
			return str(m.get("name", ""))
	return ""

func _sect_name(sid: String) -> String:
	return str(GameData.tables.get("sects", {}).get(sid, {}).get("name", sid))

# ======================================================================== 戰鬥
func _on_battle_opened(state: Dictionary) -> void:
	_in_battle = true
	_closed = false
	_close_result = {}
	_open_state = state
	_open_count += 1
	_await_me = false
	_bid = int(state.get("bid", 0))
	_my_uid = int(state.get("my_uid", 0))
	_my_side = int(state.get("my_side", 0))
	_units.clear()
	_escape.clear()
	for p in state.get("escape", []):
		_escape.append(Vector2i(int(p[0]), int(p[1])))
	for u in state.get("units", []):
		_add_unit(u)
	_say("battle %d opened kind=%s units=%s" % [_bid, str(state.get("kind", "")), str(_enemy_refs())])

func _add_unit(u: Dictionary) -> void:
	var uid := int(u.get("uid", 0))
	var pos: Array = u.get("pos", [0, 0])
	_units[uid] = { "pos": Vector2i(int(pos[0]), int(pos[1])), "side": int(u.get("side", 0)), "alive": true,
		"qi": int(u.get("qi", 1)), "qi_max": maxi(1, int(u.get("qi_max", 1))), "name": str(u.get("name", "")),
		"ref": str(u.get("ref", u.get("monster", ""))) }
	if uid == _my_uid:
		_move_range = int(u.get("move_range", 2))

func _enemy_refs() -> Array:
	var out: Array = []
	for uid in _units:
		if int(_units[uid]["side"]) != _my_side:
			out.append(_units[uid]["name"])
	return out

func _on_battle_closed(result: Dictionary) -> void:
	_closed = true
	_in_battle = false
	_close_result = result
	if bool(result.get("you_died", false)):
		_deaths += 1
	_say("battle %d closed: %s died=%s" % [int(result.get("bid", 0)), str(result.get("result", "")),
		str(result.get("you_died", false))])

func _battle_event(e: Dictionary) -> void:
	var p: Dictionary = e.get("p", {})
	var key := str(e.get("key", ""))
	if key.begins_with("move_") and int(p.get("atk_uid", -1)) == _my_uid and cfg.get("move", "") != "" \
			and str(p.get("move", "")) == _move_name(str(cfg.art), str(cfg.move)):
		_move_hit = true
		_say("acceptance move hit: %s %s" % [key, str(p.get("move", ""))])
	if str(cfg.get("cmd", "")) != "" and key in CMD_EVENTS.get(str(cfg.cmd), []):
		_cmd_done = true
		_say("acceptance command event: %s" % key)
	match key:
		"battle_await":
			for u in p.get("units", []):
				if int(u) == _my_uid:
					_await_me = true
		"battle_unit_join":
			var u: Variant = p.get("unit", {})
			if u is Dictionary:
				_add_unit(u)
		"battle_move":
			var uid := int(p.get("uid", 0))
			if _units.has(uid):
				var to: Array = p.get("to", [0, 0])
				_units[uid]["pos"] = Vector2i(int(to[0]), int(to[1]))
		"battle_kill", "battle_death", "battle_flee":
			var uid2 := int(p.get("uid", 0))
			if _units.has(uid2):
				_units[uid2]["alive"] = false
		"battle_rest", "battle_wound_tick", "battle_inner_heal", "battle_medic":
			var uid4 := int(p.get("uid", p.get("tgt_uid", 0)))
			if _units.has(uid4) and p.has("qi"):
				_units[uid4]["qi"] = int(p["qi"])
		_:
			if p.has("def_uid") and p.has("def_qi"):
				var d := int(p["def_uid"])
				if _units.has(d):
					_units[d]["qi"] = int(p["def_qi"])

static func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _occupied(p: Vector2i) -> bool:
	for uid in _units:
		if uid != _my_uid and _units[uid]["alive"] and _units[uid]["pos"] == p:
			return true
	return false

func _reachable(from: Vector2i, steps: int) -> Array:
	var out: Array = []
	var seen := { from: 0 }
	var q: Array = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if int(seen[c]) >= steps:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= 12 or n.y >= 8 or seen.has(n) or _occupied(n):
				continue
			seen[n] = int(seen[c]) + 1
			out.append(n)
			q.append(n)
	return out

func _enemies() -> Array:
	var out: Array = []
	for uid in _units:
		if _units[uid]["alive"] and int(_units[uid]["side"]) != _my_side:
			out.append(_units[uid])
	return out

## 敵方全是兔子（野兔、大野兔）
func _only_rabbits() -> bool:
	for e in _enemies():
		var nm: String = e["name"]
		if not (nm.contains("野兔")):
			return false
	return true

## 朝 targets 走一步（移動範圍內最接近的格子）；走不近回 {}
func _step_toward(pos: Vector2i, targets: Array) -> Dictionary:
	if targets.is_empty():
		return {}
	var best_d := 999
	for t in targets:
		best_d = mini(best_d, _dist(pos, t))
	var cand := pos
	var cand_d := 999
	for c in _reachable(pos, _move_range):
		var d := 999
		for t in targets:
			d = mini(d, _dist(c, t))
		if d < cand_d or (d == cand_d and (c.x < cand.x or (c.x == cand.x and c.y < cand.y))):
			cand_d = d
			cand = c
	if cand != pos and cand_d < best_d:
		return { "cmd": "MOVE", "target": [cand.x, cand.y] }
	return {}

## 往逃跑格走、站上去就逃；不能逃（no_flee、沒有逃跑格、路被擋住）回 {}，呼叫端改成照打。
## 用真正的步行距離（繞過其他單位）挑格子，不用曼哈頓距離——敵人擋在直線上時才不會原地卡住
func _flee_cmd(pos: Vector2i) -> Dictionary:
	if _escape.is_empty() or bool(_open_state.get("no_flee", false)):
		return {}
	if pos in _escape:
		return { "cmd": "FLEE" }
	var dist := {}
	var q: Array = []
	for e in _escape:
		if not _occupied(e):
			dist[e] = 0
			q.append(e)
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= 12 or n.y >= 8 or dist.has(n) or (_occupied(n) and n != pos):
				continue
			dist[n] = int(dist[c]) + 1
			q.append(n)
	if not dist.has(pos):
		return {}
	var best := pos
	var best_d := int(dist[pos])
	for c in _reachable(pos, _move_range):
		if dist.has(c) and int(dist[c]) < best_d:
			best_d = int(dist[c])
			best = c
	if best == pos:
		return {}
	return { "cmd": "MOVE", "target": [best.x, best.y] }

func _decide() -> Dictionary:
	var me: Dictionary = _units.get(_my_uid, {})
	if me.is_empty() or _mode == "defend":
		return { "cmd": "DEFEND" }
	var pos: Vector2i = me["pos"]
	# 切磋輸了也會死（FIGHT 戰的死亡照常）：切磋時氣低於 55% 就撤，路上 35%
	var low: bool = float(me["qi"]) < (0.55 if _mode == "spar" else 0.35) * float(me["qi_max"])
	var enemies := _enemies()
	var adj: Dictionary = {}
	for e in enemies:
		if _dist(pos, e["pos"]) == 1 and (adj.is_empty() or int(e["qi"]) < int(adj["qi"])):
			adj = e
	var fl := {}
	match _mode:
		"flee":
			fl = _flee_cmd(pos)
		"road":
			if low or not _only_rabbits():
				fl = _flee_cmd(pos)
		"spar":
			if low or (_move_hit and _cmd_done):
				fl = _flee_cmd(pos)
	if not fl.is_empty():
		return fl
	if _mode == "spar" and not (_move_hit and _cmd_done):
		var c := str(cfg.cmd)
		if not _cmd_done and int(_cmd_rejects.get(c, 0)) < 6:
			match c:
				# 主機不接受「氣全滿時療傷／醫自己」（full_qi／nothing_to_heal；M3a 審查 B5）→ 先打一招，掉了氣再用
				"INNER":
					if int(me["qi"]) < int(me["qi_max"]):
						return { "cmd": "INNER", "mode": "HEAL" }
				"MEDIC":
					if int(me["qi"]) < int(me["qi_max"]):
						return { "cmd": "MEDIC", "target": [pos.x, pos.y] }
				"POISON":
					if not adj.is_empty():
						return { "cmd": "POISON", "art": "xh_fangdu", "target": [adj["pos"].x, adj["pos"].y] }
				"ACUPOINT":
					if not adj.is_empty():
						return { "cmd": "ACUPOINT", "art": str(cfg.art), "target": [adj["pos"].x, adj["pos"].y] }
		if not adj.is_empty() and not _move_hit:
			return { "cmd": "ART", "art": str(cfg.art), "move": str(cfg.move), "power_tenths": 10,
				"target": [adj["pos"].x, adj["pos"].y] }
	# 想逃逃不掉：用驗收招式（比普通攻擊重）拚到底
	if not adj.is_empty() and str(cfg.get("art", "")) != "" and _mode != "road":
		return { "cmd": "ART", "art": str(cfg.art), "move": str(cfg.move), "power_tenths": 10,
			"target": [adj["pos"].x, adj["pos"].y] }
	if not adj.is_empty():
		return { "cmd": "ATTACK", "target": [adj["pos"].x, adj["pos"].y] }
	var targets: Array = []
	for e in enemies:
		targets.append(e["pos"])
	var mv := _step_toward(pos, targets)
	return mv if not mv.is_empty() else { "cmd": "DEFEND" }

func _fight() -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while not _closed:
		if _done:
			return {}
		if Time.get_ticks_msec() - t0 > BATTLE_TIMEOUT_MS:
			_fail("battle %d did not end" % _bid)
			return {}
		if _await_me:
			_await_me = false
			var cmd := _decide()
			cmd["battle_id"] = _bid
			if _mode != "road":
				var me: Dictionary = _units.get(_my_uid, {})
				_say("  %s %s qi=%s/%s" % [_mode, str(cmd.get("cmd", "")), str(me.get("qi", "?")), str(me.get("qi_max", "?"))])
			var r := await _send("battle_cmd", cmd, false)
			if not r["ok"] and not (r["reason"] in ["battle_over", "battle_not_found", "not_ready"]):
				_say("battle_cmd %s rejected: %s" % [str(cmd.get("cmd", "")), r["reason"]])
				var c := str(cmd.get("cmd", ""))
				_cmd_rejects[c] = int(_cmd_rejects.get(c, 0)) + 1
				var fb := "REST" if r["reason"] == "not_enough_neili" else "DEFEND"
				var r2 := await _send("battle_cmd", { "battle_id": _bid, "cmd": fb }, false)
				if not r2["ok"]:
					await _send("battle_cmd", { "battle_id": _bid, "cmd": "DEFEND" }, false)
			continue
		await get_tree().process_frame
	var res := _close_result
	await _sleep(0.4)   # 結算後的 sheet／view
	return res

func _handle_battle() -> Dictionary:
	if _in_battle or (not ClientState.battle_state.is_empty() and not _closed):
		return await _fight()
	return {}

# ======================================================================== 移動
func _graph() -> Dictionary:
	var g := {}
	var maps: Dictionary = GameData.tables.get("maps", {})
	for rid in maps:
		for room in maps[rid].get("rooms", []):
			var edges: Array = []
			for ex in room.get("exits", []):
				edges.append([str(ex.get("to", "")), str(ex.get("dir", ""))])
			g[str(room.get("id", ""))] = edges
	return g

func _room_row(room_id: String) -> Dictionary:
	var rid: String = _room_region.get(room_id, "")
	if rid == "":
		return {}
	for room in GameData.tables["maps"][rid].get("rooms", []):
		if str(room.get("id", "")) == room_id:
			return room
	return {}

## 規劃路線時避開：牢房、別派地區的上鎖房間（目的地本身除外）。本派（要拜的門派）的上鎖房間照走
## （例：靈鷲 lj_square 的 any_of「本派或現在就能拜入的人」；走不進去時 move 回 room_locked → 失敗）
func _avoid(room_id: String) -> bool:
	var row := _room_row(room_id)
	if bool(row.get("jail", false)):
		return true
	if (row.get("requires", []) as Array).is_empty():
		return false
	return _room_region.get(room_id, "") != _target_region()

func _target_region() -> String:
	var sid := "shaolin" if role == "jail" else role
	return str(GameData.tables.get("sects", {}).get(sid, {}).get("gate_region", ""))

func _path(from: String, to: String) -> Array:
	var g := _graph()
	var prev := { from: null }
	var q: Array = [from]
	while not q.is_empty():
		var cur: String = q.pop_front()
		if cur == to:
			break
		for e in g.get(cur, []):
			if prev.has(e[0]):
				continue
			if e[0] != to and _avoid(e[0]):
				continue
			prev[e[0]] = [cur, e]
			q.append(e[0])
	if not prev.has(to) or from == to:
		return []
	var out: Array = []
	var c := to
	while c != from:
		out.push_front(prev[c][1])
		c = prev[c][0]
	return out

func _scoutable(room_id: String) -> bool:
	var enc: Variant = _room_row(room_id).get("encounter", {})
	return enc is Dictionary and float(enc.get("rate", 0.0)) > 0.0 and not (enc.get("table", []) as Array).is_empty()

## 原地調息（站著不動不會遇敵）
func _rest_in_place(ratio := 0.8, timeout_ms := 120000) -> bool:
	var t0 := Time.get_ticks_msec()
	while _vital("qi") < int(_vital("qi_max") * ratio):
		if _done or Time.get_ticks_msec() - t0 > timeout_ms:
			return false
		await _sleep(0.25)
	return true

func _eat() -> void:
	for pair in [["food", "c_mantou"], ["water", "c_water"]]:
		if _vital(pair[0]) < FOOD_MIN:
			var uid := _first_uid(pair[1])
			if uid != "":
				await _send("use_item", { "item_uid": uid })

## 善惡為負的角色：走出出生城之後才設（M2：善惡為負進出城會被守衛攻擊）
func _maybe_set_morality() -> void:
	if _morality_set:
		return
	var city := str(cfg.birth)
	if _region() == city or _region() == "":
		return
	_morality_set = true
	await _debug("morality", int(cfg.morality))

## 走到 room；途中遇敵（踩地雷）照 _mode=road 處理；死亡（重生）＝失敗（M3A_PLAN 10.3「死了算失敗」）
func _goto(room: String) -> bool:
	for attempt in GOTO_ATTEMPTS:
		if _done:
			return false
		if _room() == room:
			return true
		var path := _path(_room(), room)
		if path.is_empty():
			_fail("no path %s -> %s" % [_room(), room])
			return false
		var cur := _room()
		for e in path:
			if _done:
				return false
			if _room() != cur:
				break
			await _eat()
			if _vital("qi") < int(_vital("qi_max") * 0.6):
				if not await _rest_in_place(0.85):
					_fail("could not rest at %s" % _room())
					return false
			var r := await _send("move", { "dir": e[1] })
			if not r["ok"]:
				if r["reason"] == "in_battle":
					await _wait_until(func(): return _in_battle, 2000)
					await _road_battle()
					break
				_fail("move %s from %s -> %s" % [e[1], cur, r["reason"]])
				return false
			var dest: String = e[0]
			await _wait_until(func(): return _in_battle or _room() == dest, 1500)
			if not await _road_battle():
				return false
			if _room() != dest:
				break
			cur = dest
			await _maybe_set_morality()
			if not await _maybe_scout():
				return false
		if _room() == room:
			return true
	_fail("could not reach %s (at %s)" % [room, _room()])
	return false

func _road_battle() -> bool:
	if not (_in_battle or (not ClientState.battle_state.is_empty() and not _closed)):
		return true
	_mode = "road"
	var res := await _fight()
	if _done:
		return false
	if bool(res.get("you_died", false)):
		_fail("died on the road (battle %d, %s)" % [int(res.get("bid", 0)), str(_enemy_refs())])
		return false
	return true

# ---------- 查看偵察（GDD 5.10；使用者的「查看 → 冷卻 → 視窗 → 迎戰或離開」） ----------
func _maybe_scout() -> bool:
	if _scout_declined and _scout_accepted:
		return true
	var here := _room()
	# 少林（jail）的東路沒有經過新地區：第一間有遇敵表的野外房間就偵察
	var new_area: bool = role == "jail" or (_room_region.get(here, "") in NEW_REGIONS) or (here in NEW_ROOMS)
	if not _scout_declined and not new_area:
		return true
	if not _scoutable(here):
		return true
	var before := _events.size()
	var r := await _send("look", { "scout": true })
	if not r["ok"]:
		return _check(false, "look scout at %s -> %s" % [here, r["reason"]])
	var t0 := Time.get_ticks_msec()
	var offer := {}
	while Time.get_ticks_msec() - t0 < 4000 and not _done:
		var got := _events_since("scout_offer", before)
		if not got.is_empty():
			offer = got[0].get("p", {})
			break
		if not _events_since("scout_busy", before).is_empty() or not _events_since("scout_none", before).is_empty():
			return true   # 冷卻中或沒挑到怪：下一間再試
		await get_tree().process_frame
	if offer.is_empty():
		return _check(false, "look at %s: no scout_offer" % here)
	var groups: Array = offer.get("monsters", [])
	var rabbits := true
	for g in groups:
		if not (str(g.get("id", "")) in RABBITS):
			rabbits = false
	_say("scout at %s: %s" % [here, str(offer.get("text", ""))])
	if not _scout_declined:
		var b2 := _events.size()
		if not await _must("scout_decline", { "offer_id": str(offer.get("offer_id", "")) }):
			return false
		if (await _wait_event("scout_declined", b2, 3000)).is_empty():
			return _check(false, "no scout_declined after scout_decline")
		_scout_declined = true
		_say("scout declined at %s" % here)
		return true
	if rabbits and _vital("qi") >= int(_vital("qi_max") * 0.7):
		var b3 := _events.size()
		var acc := await _send("scout_accept", { "offer_id": str(offer.get("offer_id", "")) })
		if not acc["ok"]:
			return _check(false, "scout_accept -> %s" % acc["reason"])
		if (await _wait_event("scout_engage", b3, 3000)).is_empty():
			return _check(false, "no scout_engage after scout_accept")
		await _wait_until(func(): return _in_battle, 3000)
		_mode = "road"
		var res := await _fight()
		if bool(res.get("you_died", false)):
			return _check(false, "died in the scouted battle")
		_scout_accepted = true
		_say("scout accepted at %s: %s" % [here, str(res.get("result", ""))])
		return true
	await _send("scout_decline", { "offer_id": str(offer.get("offer_id", "")) })
	return true

# ======================================================================== 共用動作
func _debug(key: String, value: Variant) -> bool:
	return await _must("debug_set", { "key": key, "value": value })

## 反覆消點直到等級達標；處理精、神、內力不足與教學時辰
func _learn_until(npc: String, skill: String, level: int) -> bool:
	if not await _goto(_npc_room(npc)):
		return false
	var guard := 0
	while _skill_level(skill) < level:
		guard += 1
		if guard > 300 or _done:
			return _check(false, "learn %s stuck at %d" % [skill, _skill_level(skill)])
		var r := await _send("learn", { "npc": npc, "skill": skill, "times": 5 })
		if r["ok"]:
			continue
		match r["reason"]:
			"not_enough_jing":
				await _wait_until(func(): return _vital("jing") >= int(_vital("jing_max") * 0.9), 60000)
			"not_enough_shen":
				await _wait_until(func(): return _vital("shen") >= int(_vital("shen_max") * 0.9), 60000)
			"not_enough_neili":
				# 門派技能耗內力（武當、恆山、血刀…：精＋內力）：新角色要先學基本內功再打坐
				if _vital("neili_max") <= 0:
					return _check(false, "learn %s needs neili but neili_max is 0 (learn basic_inner first)" % skill)
				await _meditate_to(_vital("neili_max"))
			"not_teach_time", "closed_night":
				await _sleep(1.0)   # 師父只在某些時辰教（恆山 儀真：辰巳申）／夜裡休息
			_:
				return _check(false, "learn %s from %s: %s" % [skill, npc, r["reason"]])
	_say("learned %s -> %d" % [skill, _skill_level(skill)])
	return true

## 修煉內力到 want（打坐：耗精、補內力）
func _meditate_to(want: int) -> bool:
	var guard := 0
	while _vital("neili") < mini(want, _vital("neili_max")) and not _done:
		guard += 1
		if guard > 200:
			return _check(false, "meditate stuck at neili %d/%d" % [_vital("neili"), _vital("neili_max")])
		var r := await _send("meditate")
		if r["ok"]:
			continue
		match r["reason"]:
			"busy":
				await _sleep(0.3)
			"not_enough_jing":
				await _wait_until(func(): return _vital("jing") >= int(_vital("jing_max") * 0.6), 60000)
			_:
				return _check(false, "meditate: %s" % r["reason"])
	return true

## 在城裡買東西（夜裡關門就等天亮）
func _buy(room: String, npc: String, item: String, n: int) -> bool:
	if not await _goto(room):
		return false
	for i in 200:
		var r := await _send("buy", { "npc": npc, "item": item, "n": n })
		if r["ok"]:
			return true
		if str(r["reason"]) == "closed_night":
			await _sleep(1.0)
			continue
		return _check(false, "buy %s from %s: %s" % [item, npc, r["reason"]])
	return _check(false, "shop %s never opened" % npc)

# ======================================================================== 劇本
func _run() -> void:
	await _frames(2)
	if not await _wait_until(func(): return ClientState.in_world, 30000):
		_fail("never entered the world")
		return
	var steps: Array = [_s1_create, _s2_walk, _s3_join]
	if role == "jail":
		steps.append(_s_jail)
	else:
		steps.append_array([_s4_learn, _s5_spar, _s6_verify])
		if role == "xingxiu":
			steps.append(_s_betray)
		elif role == "wudang":
			steps.append(_s_capture)
	for f in steps:
		if _done:
			return
		var ok: bool = await f.call()
		if not ok:
			_fail("step failed")
			return
	_ok_finish()

## 1：創角、設定數值、在城裡買兵器與乾糧
func _s1_create() -> bool:
	_step(1, "create character (%s %s, birth %s)" % [str(cfg.name), str(cfg.gender), str(cfg.birth)])
	if not await _must("char_list"):
		return false
	for c in ClientState.char_list.duplicate():
		if not await _must("char_delete", { "char_id": str(c["char_id"]), "confirm_name": str(c["name"]) }):
			return false
	var before := 0
	for i in 200:
		before = _events.size()
		if not await _must("char_roll"):
			return false
		var ev := await _wait_event("char_rolled", before, 5000)
		if ev.is_empty():
			return _check(false, "no char_rolled")
		var p: Dictionary = ev.get("p", {})
		if int(p.get("str", 0)) >= 22 and int(p.get("con", 0)) >= 20:
			break
	var nm := "%s%s" % [str(cfg.name), run]
	if not await _must("char_create", { "name": nm, "gender": str(cfg.gender), "birth_month": 5,
			"birth_city": str(cfg.birth), "alloc": { "con": 5 } }):
		return false
	if not await _wait_until(func(): return str(_sheet().get("char_id", "")) != "" and _room() != "", 5000):
		return _check(false, "no sheet after char_create")
	if not (await _debug("combat_xp", 2000) and await _debug("money", 5000) and await _debug("learn_points", 3000)):
		return false
	if int(cfg.morality) >= 0:
		_morality_set = true
		if not await _debug("morality", int(cfg.morality)):
			return false
	var shops: Dictionary = CITY_SHOPS[str(cfg.birth)]
	if str(cfg.weapon) != "":
		if not await _buy(shops.smith[0], shops.smith[1], str(cfg.weapon), 1):
			return false
		await _sleep(0.3)
		if not await _must("equip", { "item_uid": _first_uid(str(cfg.weapon)) }):
			return false
	if not await _buy(shops.food[0], shops.food[1], "c_mantou", 6):
		return false
	if not await _buy(shops.food[0], shops.food[1], "c_water", 6):
		return false
	# 出城前在武館打底（新手照樣做得到）：基本內功（門派技能消點要內力）與手上兵器的基本功，路上被野狼咬到才逃得掉
	var basic := "basic_sword" if str(cfg.weapon) == "w_mujian" else "basic_blade"
	if not (await _learn_until(str(shops.wushi), "basic_inner", 4) and await _learn_until(str(shops.wushi), basic, 10)):
		return false
	_mark("created", nm)
	return true

## 2：走到山門（途中偵察一次並離開；之後第一次只有兔子的偵察就迎戰）
func _s2_walk() -> bool:
	var sid := "shaolin" if role == "jail" else role
	var gate := str(GameData.tables.get("sects", {}).get(sid, {}).get("gate_room", ""))
	_step(2, "walk %s -> %s" % [_room(), gate])
	var t0 := Time.get_ticks_msec()
	if not await _goto(gate):
		return false
	await _maybe_set_morality()
	_say("at the gate %s after %.0fs (scout declined=%s accepted=%s)" % [gate, (Time.get_ticks_msec() - t0) / 1000.0,
		str(_scout_declined), str(_scout_accepted)])
	if not _check(_scout_declined, "never scouted on the way"):
		return false
	_mark("gate")
	return true

## 3：拜師（武當：引薦書；古墓：孫婆婆引路）
func _s3_join() -> bool:
	_step(3, "join sect via %s" % str(cfg.join))
	if role == "wudang":
		if not await _goto("wd_road2"):
			return false
		if not await _must("quest_accept", { "npc": "n_wd_yinjian", "quest": "q_wd_yinjian" }):
			return false
		await _sleep(0.3)
		if not _check(_count("i_wd_yinjianshu") >= 1, "no 引薦書 after quest_accept"):
			return false
		if not await _goto(_npc_room(str(cfg.join))):
			return false
		if not await _must("quest_turn_in", { "npc": str(cfg.join), "quest": "q_wd_yinjian" }):
			return false
	elif role == "gumu":
		var b := _events.size()
		if not await _must("npc_guide", { "npc": str(cfg.guide) }):
			return false
		if (await _wait_event("npc_guide", b, 3000)).is_empty():
			return _check(false, "no npc_guide event")
		await _wait_until(func(): return _room() == "gm_hall", 3000)
	if not await _goto(_npc_room(str(cfg.join))):
		return false
	var b2 := _events.size()
	if not await _must("join_sect", { "npc": str(cfg.join) }):
		return false
	if (await _wait_event("sect_join", b2, 3000)).is_empty():
		return _check(false, "no sect_join event")
	var sid := "shaolin" if role == "jail" else role
	await _wait_until(func(): return str(_sheet().get("sect", "")) == sid, 3000)
	_say("joined %s" % sid)
	_mark("joined")
	return _check(str(_sheet().get("sect", "")) == sid, "sheet.sect=%s" % str(_sheet().get("sect", "")))

## 4：學藝（基本內功 → 打坐 → 門派技能 → 心法 → 兵器武功；另學醫術／毒術），修煉內力。
## 整合（M3A_PLAN 12）：門派技能消點耗內力的門派（精＋內力），新角色內力上限 0 學不了，所以先學基本內功
func _s4_learn() -> bool:
	_step(4, "learn")
	for row in cfg.learn:
		if not await _learn_until(str(row[2]), str(row[0]), int(row[1])):
			return false
		if str(row[0]) == "basic_inner" and not await _meditate_to(_vital("neili_max")):
			return false
	if _vital("neili_max") > 0 and not await _meditate_to(_vital("neili_max")):
		return false
	_say("neili %d/%d jing %d shen %d" % [_vital("neili"), _vital("neili_max"), _vital("jing"), _vital("shen")])
	return true

## 5：切磋（驗收招式＋驗收指令；達成後逃離或打完）
func _s5_spar() -> bool:
	_step(5, "spar with %s: move %s + cmd %s" % [str(cfg.spar), str(cfg.move), str(cfg.cmd)])
	_move_hit = false
	_cmd_done = false
	for attempt in 6:
		if not await _goto(_npc_room(str(cfg.spar))):
			return false
		if not await _rest_in_place(0.95):
			return _check(false, "could not rest before sparring")
		if str(cfg.cmd) in ["INNER", "POISON", "ACUPOINT"]:
			await _meditate_to(_vital("neili_max"))
		_cmd_rejects.clear()
		var r := await _send("fight", { "npc": str(cfg.spar) })
		if not r["ok"]:
			return _check(false, "fight %s -> %s" % [str(cfg.spar), r["reason"]])
		if not await _wait_until(func(): return _in_battle, 3000):
			return _check(false, "spar battle did not open")
		_mode = "spar"
		var res := await _fight()
		_mode = "road"
		if _done:
			return false
		if bool(res.get("you_died", false)):
			return _check(false, "died while sparring")
		_say("spar %d: %s move_hit=%s cmd_done=%s rejects=%s" % [attempt + 1, str(res.get("result", "")),
			str(_move_hit), str(_cmd_done), str(_cmd_rejects)])
		if _move_hit and _cmd_done:
			return true
	return _check(false, "after 6 spars: move_hit=%s cmd_done=%s rejects=%s" % [str(_move_hit), str(_cmd_done),
		str(_cmd_rejects)])

## 6：角色表 sect_info 與兩套武功
func _s6_verify() -> bool:
	_step(6, "verify sheet")
	var si: Dictionary = _sheet().get("sect_info", {})
	if not _check(str(si.get("id", "")) == role, "sect_info.id=%s" % str(si.get("id", ""))):
		return false
	if not _check(int(si.get("skill_level", 0)) >= 1, "sect skill level %d" % int(si.get("skill_level", 0))):
		return false
	for a in cfg.arts:
		if not _check(_skill_level(str(a)) >= 1, "%s level %d" % [str(a), _skill_level(str(a))]):
			return false
	_say("verified: sect_info=%s arts=%s" % [str(si), str(cfg.arts.map(func(a): return "%s:%d" % [a, _skill_level(a)]))])
	_mark("verified")
	return true

## 叛派（星宿）：need_confirm → sect_betray → 本門武功減半（預設規則：諂媚不動）、公敵 → 不能再拜 → 敵對入山開戰
func _s_betray() -> bool:
	_step(7, "betray 星宿")
	var head := "n_xh_dingchunqiu"
	if not await _goto(_npc_room(head)):
		return false
	var cs0 := _skill_level("xh_chousui")
	var basic0 := _skill_level("basic_fist")
	var cm0 := _skill_level("chanmei")
	var r0 := await _send("sect_betray", { "npc": head, "confirm": false })
	if not _check(not r0["ok"] and r0["reason"] == "need_confirm", "betray without confirm -> %s" % str(r0)):
		return false
	var b := _events.size()
	if not await _must("sect_betray", { "npc": head, "confirm": true }):
		return false
	if (await _wait_event("sect_betray", b, 3000)).is_empty():
		return _check(false, "no sect_betray event")
	await _wait_until(func(): return str(_sheet().get("sect", "")) == "", 3000)
	var enemy_names: Array = _sheet().get("enemy_of", [])
	_say("after betray: xh_chousui %d -> %d, basic_fist %d -> %d, chanmei %d, enemy_of %s" % [cs0,
		_skill_level("xh_chousui"), basic0, _skill_level("basic_fist"), _skill_level("chanmei"), str(enemy_names)])
	if not (_check(str(_sheet().get("sect", "")) == "", "still in a sect") \
			and _check(_skill_level("xh_chousui") == cs0 / 2, "xh_chousui %d (was %d)" % [_skill_level("xh_chousui"), cs0]) \
			and _check(_skill_level("basic_fist") == basic0, "basic_fist changed %d -> %d" % [basic0, _skill_level("basic_fist")]) \
			and _check(_skill_level("chanmei") == cm0, "chanmei %d (was %d; 2001 叛派不動門派技能)" % [_skill_level("chanmei"), cm0]) \
			and _check(_sect_name("xingxiu") in enemy_names, "enemy_of %s" % str(enemy_names))):
		return false
	var rj := await _send("join_sect", { "npc": head })
	if not _check(not rj["ok"] and rj["reason"] == "req_not_enemy_of", "re-join -> %s" % str(rj)):
		return false
	# 敵對入山：在星宿地區走一步就有守衛（rooms ALL、星宿可以逃）
	var b2 := _events.size()
	var exits: Array = _graph().get(_room(), [])
	var out_dir := ""
	for e in exits:
		if _room_region.get(e[0], "") == "xingxiu" and (_room_row(e[0]).get("requires", []) as Array).is_empty() 				and not bool(_room_row(e[0]).get("jail", false)):
			out_dir = e[1]
			break
	if not _check(out_dir != "", "no exit inside 星宿 from %s" % _room()):
		return false
	await _send("move", { "dir": out_dir })
	var hostile := await _wait_event("sect_hostile", b2, 4000)
	if hostile.is_empty():
		return _check(false, "no sect_hostile after walking in 星宿 as an enemy")
	if not await _wait_until(func(): return _in_battle, 3000):
		return _check(false, "sect_hostile without a battle")
	if not _check(str(_open_state.get("kind", "")) == "SECT_GUARD", "battle kind %s" % str(_open_state.get("kind", ""))):
		return false
	_mode = "flee"
	var res := await _fight()
	_say("hostile battle: %s died=%s" % [str(res.get("result", "")), str(res.get("you_died", false))])
	_mark("betrayed")
	return true

## 公敵被抓（武當）：叛派 → 在武當走一步 → SECT_GUARD（不能逃）→ 戰死 → 押入 wd_siguo
func _s_capture() -> bool:
	_step(7, "武當 enemy capture")
	var head := "n_wd_zhangsanfeng"
	if not await _goto(_npc_room(head)):
		return false
	var b := _events.size()
	if not await _must("sect_betray", { "npc": head, "confirm": true }):
		return false
	if (await _wait_event("sect_betray", b, 3000)).is_empty():
		return _check(false, "no sect_betray event")
	await _wait_until(func(): return str(_sheet().get("sect", "")) == "", 3000)
	var b2 := _events.size()
	var exits: Array = _graph().get(_room(), [])
	var out_dir := ""
	for e in exits:
		if _room_region.get(e[0], "") == "wudang" and not bool(_room_row(e[0]).get("jail", false)):
			out_dir = e[1]
			break
	if not _check(out_dir != "", "no exit inside 武當 from %s" % _room()):
		return false
	await _send("move", { "dir": out_dir })
	if (await _wait_event("sect_hostile", b2, 4000)).is_empty():
		return _check(false, "no sect_hostile after walking in 武當 as an enemy")
	if not await _wait_until(func(): return _in_battle, 3000):
		return _check(false, "sect_hostile without a battle")
	if not _check(str(_open_state.get("kind", "")) == "SECT_GUARD", "battle kind %s" % str(_open_state.get("kind", ""))):
		return false
	_mode = "defend"
	var res := await _fight()
	_mode = "road"
	if not _check(bool(res.get("you_died", false)), "expected to die vs the 武當 guards: %s" % str(res.get("result", ""))):
		return false
	if (await _wait_jail_event("jail_in", b2, 5000)).is_empty():
		return _check(false, "no jail_in after dying as a 武當 enemy")
	var want_room := "jc_jail" if _capital() else "wd_siguo"
	await _wait_until(func(): return _room() == want_room, 3000)
	var jail: Variant = _sheet().get("jail", null)
	_say("captured: room=%s jail=%s" % [_room(), str(jail)])
	if not (_check(_room() == want_room, "room %s (want %s)" % [_room(), want_room]) \
			and _check(jail is Dictionary and float(jail.get("left_s", 0)) > 7200.0 * 2.5, "jail sheet %s (want 3 days)" % str(jail))):
		return false
	_mark("captured")
	return true

## 坐牢（少林）：殺氣 2500 → sect_breach JAIL + jail_in（sl_siguo）→ 不能走、世界頻道被拒、輕聲細語可用 → 快轉 → jail_out（sl_gate）
func _s_jail() -> bool:
	_step(4, "少林 breach -> 思過處")
	var b := _events.size()
	if not await _debug("killing_intent", 2500):
		return false
	var br := await _wait_event("sect_breach", b, 4000)
	if br.is_empty():
		return _check(false, "no sect_breach after killing_intent 2500")
	if not _check(str(br.get("p", {}).get("outcome", "")) == "JAIL", "breach outcome %s" % str(br.get("p", {}))):
		return false
	if (await _wait_jail_event("jail_in", b, 4000)).is_empty():
		return _check(false, "no jail_in")
	var jroom := "jc_jail" if _capital_breach() else "sl_siguo"
	await _wait_until(func(): return _room() == jroom, 3000)
	if not _check(_room() == jroom, "room %s (want %s)" % [_room(), jroom]):
		return false
	var jail: Variant = _sheet().get("jail", null)
	if not _check(jail is Dictionary and float(jail.get("left_s", 0)) > 0.0, "jail sheet %s" % str(jail)):
		return false
	var dirs: Array = _graph().get(_room(), [])
	var mv := await _send("move", { "dir": str(dirs[0][1]) if not dirs.is_empty() else "N" })
	if not _check(not mv["ok"] and mv["reason"] == "jailed", "move in jail -> %s" % str(mv)):
		return false
	var cw := await _send("chat", { "text": "放我出去", "ch": "CHAT_WORLD" })
	if not _check(not cw["ok"] and cw["reason"] == "jailed", "world chat in jail -> %s" % str(cw)):
		return false
	var cs := await _send("chat", { "text": "我知錯了", "ch": "CHAT_SAY" })
	if not _check(cs["ok"], "say in jail -> %s" % str(cs)):
		return false
	var b2 := _events.size()
	if not await _debug("killing_intent", 0):
		return false
	if not await _debug("online_s_add", 7300):
		return false
	if (await _wait_jail_event("jail_out", b2, 6000)).is_empty():
		return _check(false, "no jail_out after online_s_add 7300")
	var out_room := "jc_yamen" if _capital_breach() else "sl_gate"
	await _wait_until(func(): return _room() == out_room, 3000)
	_say("released: room=%s jail=%s" % [_room(), str(_sheet().get("jail", null))])
	if not _check(_room() == out_room, "room %s after release (want %s)" % [_room(), out_room]):
		return false
	_mark("jailed_and_released")
	return true
