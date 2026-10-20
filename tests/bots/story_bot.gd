extends RefCounted
## 故事驗收 bot（STORY_PLAN §9.2）：一個「玩家」的驅動器，由 tools/story_acceptance.gd 的 worker 在同一行程裡建立。
## 與 tests/unit/test_world_fixture.gd 相同的作法：WorldServer 是真的主機（GameHost、全部系統、--debug-intents），
## 玩家是假的遠端 peer（ClientState.capture_remote 收件），所有動作都經 WorldServer.handle_intent（與網路客戶端同一條路）。
##
## 讀任務列的 test_plan（WP-MERGE 原樣存進 data/quests.json）並照動作語彙執行：
##   walk@<room>（區域圖 BFS，一步一步 move；路上遇敵就打）、accept@<npc>、talk@<npc>、choose@<npc>:<node>:<choice>、
##   act@<qid>:<action>、fight:WIN|FLEE|DEFEAT、buy@<npc>:<item>:<n>、wait:hour=<時辰>、wait:days=<n>、
##   expect_stage:<stage>、expect_absent@<npc>（或 expect_absent:<npc>）、expect_menu:<STATE>、expect_menu_absent@<npc>:<qid>、
##   set_var:<qid>:<name>=<value>（固定隨機的任務變數；捷徑）。
##   M3b：use@<item>（use_item 身上第一個該物品）、expect_no_act@<qid>:<action>（動作此刻必須被拒）、
##   expect_locked@<npc>:<node>:<choice>（對話選項必須上鎖）、debug_give:<item>:<n>（給物品；捷徑，同 setup.items）。
## setup：sect（直接設門派；debug_set 沒有門派鍵，這是唯一不經 intent 的捷徑）、skills、attrs、combat_xp、fame、lilian、
##   morality、flags、items、quests_done、after（"<qid>:<outcome>"：先照那條任務的 test_plan 跑完）、
##   sect_rank（M3b：直接設本派位階；捷徑，同 sect）、attrs_exact（attrs 往下也設）。
## expect（M3b 加）：sect_rank_pending（等聚會的位階）、conditions_absent、money_delta／learn_points_delta（角色數值實際增減）、
##   skill_prof_delta（{ skill: n }：熟練至少增加 n 或升級）。
## debug 只用來滿足門檻、快轉時辰（§9.2）；另外 bot 角色一律加強（屬性、基本武功）並在每場戰鬥前回滿精氣神與食水
## （驗收的是任務流程，不是平衡；平衡由 tools/balance_sim.gd 負責）。
##
## 檢查：每個走過的階段都有 quest_stage 事件；最後的結局（done.outcome 與 quest_complete 的 outcome_label）；
## expect 的數值（money／fame／lilian／learn_points／morality 以任務 reward 事件加總比對，不受路上戰鬥影響）、
## 物品增減、旗標、武功等級、熟練、傳聞；一次性任務完成後選單是 DONE、可重複任務是 COOLDOWN 且快轉後可再接；
## 中途存檔→關主機→同一世界重開→重新選角→繼續（save_reload_at 或預設第 2 個階段），進行中狀態必須完全相同。

const STRONG_ATTRS := ["str", "agi", "con", "guts", "cal"]
const STRONG_SKILLS := { "basic_fist": 120, "basic_blade": 120, "basic_sword": 120, "basic_dodge": 120,
	"basic_parry": 120, "basic_inner": 120 }
const STRONG_ATTR_VALUE := 150
const BOT_COMBAT_XP := 400
const MAX_WALK_STEPS := 600
const BATTLE_MAX_TICKS := 30000
const RESULT_KEYS := { "battle_victory": "VICTORY", "battle_victory_fled": "VICTORY", "battle_defeat": "DEFEAT",
	"battle_fled": "FLED" }
const FIGHT_WANT := { "WIN": "VICTORY", "FLEE": "FLED", "DEFEAT": "DEFEAT" }

var ws: Node
var peer := 0
var identity := ""
var pname := ""
var city := "xixia"
var gender := "M"
var char_id := ""
var seq := 0
var label := ""

var events: Array = []
var sheet: Dictionary = {}
var view: Dictionary = {}
var dlg: Dictionary = {}           # 最後一個開著的 E_DIALOGUE payload（dialogue_close 清空）
var rewards: Dictionary = {}       # E_REWARD 加總
var rumors: Array = []             # jianghu_rumor 的 payload
var stage_titles: Array = []       # quest_stage 的 { quest_name, stage_title }
var completes: Array = []          # quest_complete 的 payload
var fails: Array = []              # quest_fail 的 payload
var villain_prompts: Array = []
var villain_clears: Array = []
var battle_results: Array = []     # 每場戰鬥的結果（VICTORY／FLED／DEFEAT）
var last_npc := ""
var err := ""
var notes: PackedStringArray = []
var reloads := 0
var moves := 0
var keep_weak := false             # 新手（活的江湖驗收：不加強、實戰 < 500）
var allow_reload := true           # 雙人驗收關掉（重開主機會踢掉另一位）

func _init(p_ws: Node, p_peer: int, p_name: String, p_label := "") -> void:
	ws = p_ws
	peer = p_peer
	pname = p_name
	label = p_label if p_label != "" else p_name
	identity = make_identity(p_peer)

static func make_identity(n: int) -> String:
	var h := "%08x%08x" % [n, 0x5703]
	while h.length() < 32:
		h += "%08x" % (randi() & 0x7FFFFFFF)
	return "local_" + h.substr(0, 32)

# ======================================================================== 基礎
func host():
	return ws.game

func s() -> Session:
	return ws.sessions.get(peer)

func ch():
	var o := s()
	return o.character if o != null else null

func tables() -> Dictionary:
	return host().tables

func say(msg: String) -> void:
	print("[story:%s] %s" % [label, msg])

func fail(msg: String) -> bool:
	if err == "":
		var act := {}
		if ch() != null:
			for q in ch().quests.get("active", {}):
				act[q] = { "stage": str(ch().quests["active"][q].get("stage", "")), "objs": ch().quests["active"][q].get("objs", {}) }
		err = "%s (room=%s active=%s)" % [msg, room(), JSON.stringify(act)]
		say("FAIL " + err)
	return false

func room() -> String:
	var o := s()
	return o.room_id() if o != null and o.character != null else ""

## ClientState.capture_remote 經 worker 轉來
func on_capture(what: String, payload: Variant) -> void:
	match what:
		"events":
			for e in payload:
				if e is Dictionary:
					_on_event(e)
		"sheet":
			sheet = payload
		"view":
			view = payload

func _on_event(e: Dictionary) -> void:
	events.append(e)
	if events.size() > 6000:
		events = events.slice(events.size() - 3000)
	var p: Dictionary = e.get("p", {}) if e.get("p") is Dictionary else {}
	match str(e.get("key", "")):
		"dialogue":
			dlg = p
		"dialogue_close":
			dlg = {}
		"reward":
			for k in ["money", "fame", "lilian", "learn_points", "morality", "combat_xp", "killing_intent"]:
				rewards[k] = int(rewards.get(k, 0)) + int(p.get(k, 0))
		"jianghu_rumor":
			rumors.append(p)
		"quest_stage":
			stage_titles.append(p)
		"quest_complete":
			completes.append(p)
		"quest_fail":
			fails.append(p)
		"villain_prompt":
			villain_prompts.append(p)
		"villain_clear":
			villain_clears.append(p)
		_:
			var k := str(e.get("key", ""))
			if RESULT_KEYS.has(k):
				battle_results.append(RESULT_KEYS[k])

func send(kind: String, args: Dictionary = {}) -> Dictionary:
	seq += 1
	var r: Dictionary = ws.handle_intent(peer, seq, kind, args)
	ws.flush()
	return r

func must(kind: String, args: Dictionary = {}) -> bool:
	var r := send(kind, args)
	if not r.get("ok", false):
		return fail("%s %s -> %s" % [kind, JSON.stringify(args), str(r.get("reason", ""))])
	return true

func debug(key: String, value: Variant) -> bool:
	return must("debug_set", { "key": key, "value": value })

func flush_view() -> void:
	if s() != null and s().character != null:
		host().flush_session(s(), true)
	ws.flush()

## 世界往前推 secs 秒（逐 tick，戰鬥、惡人倒數、傳聞輪詢都會跑）
func advance(secs: float) -> void:
	ws.advance(secs)

# ======================================================================== 連線、角色
func connect_session() -> bool:
	ws.on_peer_connected(peer)
	var why: String = ws.handle_hello(peer, {
		"protocol": Protocol.VERSION, "game_version": Protocol.GAME_VERSION,
		"content_hash": GameData.content_hash, "identity": identity, "display_name": pname,
	})
	if why != "":
		return fail("hello: " + why)
	if ws.sessions.has(peer):
		ws.sessions[peer].rate_limiter = TokenBucket.new(1000000.0, 1000000.0)
	seq = 0
	ws.flush()
	return true

func create_char() -> bool:
	if not connect_session():
		return false
	if not must("char_roll"):
		return false
	if not must("char_create", { "name": pname, "gender": gender, "birth_month": 3, "birth_city": city,
			"alloc": { "wit": 5 } }):
		return false
	char_id = str(ch().id)
	if not debug("money", 20000):
		return false
	if not keep_weak:
		make_strong()
		# 中等資歷（武功上限 11 級，learn 獎勵與門派技能才學得上去）；< 500 仍受新手保護，遊蕩惡人不會在鏈上半路出手
		debug("combat_xp", BOT_COMBAT_XP)
	refill()
	return err == ""

## 主機重開後：同一身分重新連線並選回同一個角色
func reselect() -> bool:
	if not connect_session():
		return false
	dlg = {}
	return must("char_select", { "char_id": char_id })

func make_strong() -> void:
	for a in STRONG_ATTRS:
		debug("attr:" + a, STRONG_ATTR_VALUE)
	for sk in STRONG_SKILLS:
		if SkillBook.kind_of(sk, tables()) != "" and int(ch().skills.level(sk)) < int(STRONG_SKILLS[sk]):
			debug("skill:" + sk, STRONG_SKILLS[sk])

## 回滿精氣神內力與食水（測試捷徑，不是 intent；只為了讓長鏈不因飢渴或連戰中斷）
func refill() -> void:
	var c = ch()
	if c == null:
		return
	c.clamp_vitals(tables(), ws.options)
	Survival.rest_full(c, tables(), ws.options)
	c.vitals["food"] = Character.FOOD_MAX
	c.vitals["water"] = Character.WATER_MAX
	s().sheet_dirty = true

# ======================================================================== 戰鬥
func _my_unit(b):
	for u in b.units:
		if int(u.peer) == peer and u.is_active():
			return u
	return null

static func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _choose_cmd(b, me, policy: String) -> Dictionary:
	if policy == "defend":
		return { "cmd": "DEFEND" }
	if policy == "flee":
		if b.grid.is_escape(me.pos):
			return { "cmd": "FLEE" }
		var best_e: Vector2i = me.pos
		var bd := 999
		for e in b.grid.escape:
			bd = mini(bd, _dist(me.pos, e))
		for p in b.grid.reachable(me.pos, BattleFormulas.move_range(me)):
			for e in b.grid.escape:
				if _dist(p, e) < bd:
					bd = _dist(p, e)
					best_e = p
		if best_e != me.pos:
			return { "cmd": "MOVE", "target": [best_e.x, best_e.y] }
		return { "cmd": "DEFEND" }
	var enemies: Array = []
	for u in b.units:
		if int(u.side) != int(me.side) and u.is_active():
			enemies.append(u)
	for e in enemies:
		if _dist(me.pos, e.pos) == 1:
			return { "cmd": "ATTACK", "target": [e.pos.x, e.pos.y] }
	var best: Vector2i = me.pos
	var best_d := 999
	for e in enemies:
		best_d = mini(best_d, _dist(me.pos, e.pos))
	for p in b.grid.reachable(me.pos, BattleFormulas.move_range(me)):
		for e in enemies:
			var d := _dist(p, e.pos)
			if d < best_d:
				best_d = d
				best = p
	if best != me.pos:
		return { "cmd": "MOVE", "target": [best.x, best.y] }
	return { "cmd": "DEFEND" }

var flee_rejects := 0   # 本場被拒絕的 FLEE 次數（不能逃的戰鬥）

## 戰鬥中輪到自己就下一個指令（雙人驗收每個 tick 對兩個 bot 各呼叫一次）；戰鬥已不存在回 false
func battle_tick(policy: String) -> bool:
	var o := s()
	if o == null or o.battle_id == 0:
		return false
	var bid := o.battle_id
	var entry: Dictionary = host().battles.active.get(bid, {})
	if entry.is_empty():
		return false
	var b = entry["battle"]
	var me = _my_unit(b)
	if me != null and str(me.state) == "READY":
		var pol := policy
		if pol == "flee" and flee_rejects > 6:
			pol = "fight"   # 不能逃的戰鬥（追擊戰、no_flee）：改打
		var cmd := _choose_cmd(b, me, pol)
		cmd["battle_id"] = bid
		var r := send("battle_cmd", cmd)
		if not r.get("ok", false):
			if str(cmd.get("cmd", "")) == "FLEE":
				flee_rejects += 1
			send("battle_cmd", { "battle_id": bid, "cmd": "DEFEND" })
	return true

## 打到戰鬥結束；回傳本人結果（VICTORY／FLED／DEFEAT／""）。policy：fight／flee／defend
func drive_battle(policy: String) -> String:
	var o := s()
	if o == null or o.battle_id == 0:
		return ""
	var bid := o.battle_id
	var n0 := battle_results.size()
	var ticks := 0
	flee_rejects = 0
	while s() != null and s().battle_id == bid and ticks < BATTLE_MAX_TICKS:
		if not battle_tick(policy):
			break
		ws.advance(0.1)
		ticks += 1
	if s() != null and s().battle_id == bid:
		fail("battle %d did not end" % bid)
		return ""
	advance(0.3)
	var res := str(battle_results[battle_results.size() - 1]) if battle_results.size() > n0 else ""
	if res == "DEFEAT" or ch().vitals.get("qi", 0) <= 0:
		refill()
	return res

## 路上：有戰鬥就打完（遇敵、守衛、惡人）；打輸了就回滿繼續
func clear_battles() -> void:
	var guard := 0
	while s() != null and s().battle_id != 0 and guard < 5 and err == "":
		guard += 1
		var res := drive_battle("fight")
		if res == "DEFEAT":
			notes.append("defeated on the road at %s" % room())
		refill()

# ======================================================================== 走路
func _ctx() -> Dictionary:
	return host().regions._ctx(s())

func path_to(target: String) -> Array:
	var start := room()
	if start == target:
		return []
	var prev := { start: ["", ""] }
	var q: Array = [start]
	var idx := 0
	var c = ch()
	var ctx := _ctx()
	while idx < q.size():
		var r: String = q[idx]
		idx += 1
		for ex in host().index.room(r).get("exits", []):
			if not (ex is Dictionary):
				continue
			var to := str(ex.get("to", ""))
			if to == "" or prev.has(to) or not host().index.has_room(to):
				continue
			if host().regions.lock_reason(c, to, ctx) != "":
				continue
			prev[to] = [r, str(ex.get("dir", ""))]
			if to == target:
				var out: Array = []
				var cur := target
				while cur != start:
					out.push_front(prev[cur][1])
					cur = prev[cur][0]
				return out
			q.append(to)
	return ["?"]

func walk(target: String) -> bool:
	if not host().index.has_room(target):
		return fail("walk: unknown room " + target)
	var steps := 0
	while room() != target:
		if err != "":
			return false
		clear_battles()
		var p := path_to(target)
		if p.is_empty():
			break
		if str(p[0]) == "?":
			return fail("walk: no path %s -> %s" % [room(), target])
		var r := send("move", { "dir": str(p[0]) })
		if not r.get("ok", false):
			var why := str(r.get("reason", ""))
			if why == "in_battle":
				clear_battles()
				continue
			return fail("move %s at %s -> %s" % [str(p[0]), room(), why])
		steps += 1
		moves += 1
		if steps > MAX_WALK_STEPS:
			return fail("walk: too many steps to " + target)
		advance(0.2)
		clear_battles()
		var c = ch()
		var d: Dictionary = c.derived(tables(), ws.options)
		if int(c.vitals.get("qi", 0)) < int(d.get("qi_max", 1)) / 2 or int(c.vitals.get("food", 0)) < 30 \
				or int(c.vitals.get("water", 0)) < 30:
			refill()
	dlg = {}
	return true

# ======================================================================== 任務動作
func quest_row(qid: String) -> Dictionary:
	return host().quests.quest_row(qid)

func active(qid: String) -> Dictionary:
	return ch().quests.get("active", {}).get(qid, {})

func done_entry(qid: String) -> Dictionary:
	var d: Variant = ch().quests.get("done", {}).get(qid, {})
	return d if d is Dictionary else {}

func stage_of(qid: String) -> String:
	return str(active(qid).get("stage", ""))

func talk(npc: String, qid: String) -> bool:
	dlg = {}
	last_npc = npc
	var n0 := events.size()
	if not must("talk", { "npc": npc }):
		return false
	if s().battle_id != 0:
		return true   # 交談即戰（惡人）或任務的開戰
	if not dlg.is_empty() and str(dlg.get("npc", "")) == npc:
		advance_dialogue()
		return true
	# 沒有自動開的對話：從選單點任務項（本鏈的任務優先，其次第一個 READY）
	var entries: Array = host().quests.menu_entries(s(), npc)
	var pick := ""
	for e in entries:
		if str(e.get("id", "")) == qid and str(e.get("state", "")) in ["READY", "ACTIVE", "AVAILABLE"]:
			pick = qid
	if pick == "":
		for e in entries:
			if str(e.get("state", "")) == "READY":
				pick = str(e.get("id", ""))
				break
	if pick == "":
		# 沒有任務項可點：只有閒聊（例如完成後確認選單），不算失敗
		notes.append("talk %s: menu only %s" % [npc, JSON.stringify(entries)])
		return events.size() > n0
	if not must("quest_talk", { "npc": npc, "quest": pick }):
		return false
	advance_dialogue()
	return true

## 只有合成「（繼續）」的節點自動按過去；對話結束（沒有選項）就按「結束」（同 UI）
func advance_dialogue() -> void:
	for i in 30:
		if dlg.is_empty() or err != "":
			return
		var cs: Array = dlg.get("choices", [])
		if cs.is_empty():
			send("dialogue_close")
			dlg = {}
			return
		if cs.size() == 1 and str(cs[0].get("id", "")) == DialogueTree.NEXT_CHOICE:
			var r := send("dialogue_choose", { "npc": str(dlg.get("npc", "")), "quest": str(dlg.get("quest", "")),
				"node": str(dlg.get("node", "")), "choice": DialogueTree.NEXT_CHOICE })
			if not r.get("ok", false):
				fail("(繼續) at %s -> %s" % [str(dlg.get("node", "")), str(r.get("reason", ""))])
				return
			continue
		return

## offer 對話的路徑沒寫在 test_plan 裡（只寫 accept@）：在對話樹裡找一條通到 accept 動作的選項路徑照著選
func auto_accept(qid: String) -> bool:
	var def := quest_row(qid)
	for guard in 12:
		advance_dialogue()
		if dlg.is_empty() or not active(qid).is_empty():
			return not active(qid).is_empty() or fail("offer dialogue ended without accepting " + qid)
		var path := _accept_path(def, str(dlg.get("dlg", "")), str(dlg.get("node", "")), {})
		if path.is_empty():
			return fail("offer %s: no choice path to accept from node %s" % [qid, str(dlg.get("node", ""))])
		if not choose(str(dlg.get("npc", "")), str(dlg.get("node", "")), str(path[0])):
			return false
	return not active(qid).is_empty() or fail("auto accept " + qid)

static func _has_accept(acts: Variant) -> bool:
	if acts is Array:
		for a in acts:
			if a is Dictionary and str(a.get("do", "")) == "accept":
				return true
	return false

func _accept_path(def: Dictionary, dlg_id: String, node_id: String, seen: Dictionary) -> Array:
	if seen.has(node_id):
		return []
	seen[node_id] = true
	var n := DialogueTree.node(def, dlg_id, node_id)
	if n.is_empty():
		return []
	if _has_accept(n.get("do", [])):
		return ["_here"]
	var g := str(n.get("goto", ""))
	if (n.get("choices", []) as Array).is_empty():
		if g != "" and g != DialogueTree.END:
			var sub := _accept_path(def, dlg_id, g, seen)
			if not sub.is_empty():
				return [DialogueTree.NEXT_CHOICE] + sub
		return []
	for c in n.get("choices", []):
		if not (c is Dictionary):
			continue
		if _has_accept(c.get("do", [])):
			return [str(c.get("id", ""))]
		var cg := str(c.get("goto", ""))
		if cg != "" and cg != DialogueTree.END:
			var sub2 := _accept_path(def, dlg_id, cg, seen)
			if not sub2.is_empty():
				return [str(c.get("id", ""))] + sub2
	return []

func choose(npc: String, node: String, choice: String) -> bool:
	advance_dialogue()
	if dlg.is_empty():
		return fail("choose %s:%s:%s: no dialogue open" % [npc, node, choice])
	if str(dlg.get("npc", "")) != npc or str(dlg.get("node", "")) != node:
		return fail("choose %s:%s:%s: dialogue is at %s:%s (%s)" % [npc, node, choice, str(dlg.get("npc", "")),
			str(dlg.get("node", "")), str(dlg.get("text", "")).left(40)])
	var found := false
	for c in dlg.get("choices", []):
		if c is Dictionary and str(c.get("id", "")) == choice:
			found = true
			if bool(c.get("locked", false)):
				return fail("choose %s: locked (%s)" % [choice, str(c.get("why", ""))])
	if not found:
		return fail("choose %s:%s: no such choice (have %s)" % [node, choice, JSON.stringify(dlg.get("choices", []))])
	var q := str(dlg.get("quest", ""))
	if not must("dialogue_choose", { "npc": npc, "quest": q, "node": node, "choice": choice }):
		return false
	advance_dialogue()
	return true

func fight(want: String) -> bool:
	if s().battle_id == 0:
		return fail("fight:%s but no battle is running" % want)
	var policy := "fight"
	match want:
		"FLEE":
			policy = "flee"
		"DEFEAT":
			policy = "defend"
	if policy == "fight":
		refill()
	var res := drive_battle(policy)
	if res != str(FIGHT_WANT.get(want, "VICTORY")):
		return fail("fight:%s ended %s" % [want, res])
	return true

# ======================================================================== test_plan
func apply_setup(st: Dictionary, plans: Dictionary) -> bool:
	if st.is_empty():
		return true
	var c = ch()
	# after：先照前置任務的路徑跑完（它自己的 setup 可能把門檻設低，所以先跑、再套本路徑的 setup）
	var after := str(st.get("after", ""))
	if after != "":
		var i := after.find(":")
		var aq := after.substr(0, i) if i > 0 else after
		var ao := after.substr(i + 1) if i > 0 else ""
		var pre := find_plan(plans, aq, ao)
		if pre.is_empty():
			return fail("setup after: no plan for " + after)
		say("setup: running %s first" % after)
		if not run_plan(pre, plans, false):
			return false
	var sect := str(st.get("sect", ""))
	if sect != "":
		if not tables().get("sects", {}).has(sect):
			return fail("setup: unknown sect " + sect)
		c.sect = sect   # 捷徑：門派（debug_set 沒有門派鍵）
		s().sheet_dirty = true
	if st.has("sect_rank"):
		c.sect_rank = int(st["sect_rank"])   # 捷徑（M3b）：位階
		c.sect_rank_pending = {}
		s().sheet_dirty = true
	# attrs 只往上補（bot 角色已加強）；attrs_exact（M3b：鬥酒醉倒路徑要低屬性）＝照寫的值設，往下也設
	var exact := bool(st.get("attrs_exact", false))
	for a in st.get("attrs", {}):
		if exact or int(c.attrs.get(a, 0)) < int(st["attrs"][a]):
			debug("attr:" + str(a), int(st["attrs"][a]))
	for sk in st.get("skills", {}):
		debug("skill:" + str(sk), int(st["skills"][sk]))
	for k in ["combat_xp", "fame", "lilian", "morality"]:
		if st.has(k):
			debug(k, int(st[k]))
	var fl: Variant = st.get("flags", [])
	if fl is Array:
		for f in fl:
			debug("flag:" + str(f), true)
	for it in st.get("items", {}):
		var g: Dictionary = host().give_item(c, str(it), int(st["items"][it]))
		if not g.get("ok", false):
			return fail("setup: give %s" % str(it))
	for qd in st.get("quests_done", []):
		ch().quests["done"][str(qd)] = { "n": 1, "outcome": "default", "world_s": host().now_s(), "failed": 0 }
	s().sheet_dirty = true
	flush_view()
	return err == ""

## 路徑沒寫到的接任務門檻：quest_done → 先把前置任務照它的 test_plan 走完（不用 debug）；
## quest_flag／skill_min／attr_min／實戰／名聲／歷練 → debug_set（§9.2：debug 只用來滿足門檻）；門派 → 同 setup 捷徑。
## hour_in 不處理（路徑自己有 wait:hour）。
func satisfy_requires(qid: String, plans: Dictionary, depth := 0) -> bool:
	var reqs: Array = quest_row(qid).get("requires", [])
	for c in reqs:
		if not (c is Dictionary):
			continue
		if Requirements.check([c], ch(), tables(), ws.options, host().rules, {}) == "":
			continue
		match str(c.get("type", "")):
			"quest_done":
				var pq := str(c.get("quest", ""))
				var pre := find_plan(plans, pq, "")
				if pre.is_empty() or depth > 3:
					return fail("prerequisite %s has no test_plan" % pq)
				notes.append("ran prerequisite " + pq)
				say("prerequisite: running %s first" % pq)
				if not run_plan(pre, plans, false):
					return false
			"quest_flag":
				notes.append("debug flag " + str(c.get("flag", "")))
				debug("flag:" + str(c.get("flag", "")), true)
			"skill_min":
				debug("skill:" + str(c.get("skill", "")), int(c.get("value", 0)))
			"attr_min":
				debug("attr:" + str(c.get("attr", "")), int(c.get("value", 0)))
			"combat_xp_min":
				debug("combat_xp", int(c.get("value", 0)))
			"fame_min":
				debug("fame", int(c.get("value", 0)))
			"lilian_min":
				debug("lilian", int(c.get("value", 0)))
			"sect":
				ch().sect = str(c.get("sect", ""))
				s().sheet_dirty = true
	flush_view()
	return err == ""

static func find_plan(plans: Dictionary, qid: String, outcome: String) -> Dictionary:
	for p in plans.get(qid, []):
		if outcome == "" or str(p.get("outcome", "")) == outcome:
			return p
	return {}

func _snapshot() -> Dictionary:
	var c = ch()
	var inv := {}
	for it in c.inventory.items:
		var id := str(it.get("id", ""))
		if id != "" and not inv.has(id):
			inv[id] = int(c.inventory.count(id))
	var sk := {}
	for id in c.skills.entries:
		sk[str(id)] = [int(c.skills.level(str(id))), int(c.skills.prof(str(id)))]
	return { "inv": inv, "skills": sk, "money": int(c.money), "fame": int(c.fame), "lilian": int(c.lilian),
		"morality": int(c.morality), "learn_points": int(c.learn_points) }

func count_item(id: String) -> int:
	return int(ch().inventory.count(id))

## 一條路徑。checks == false：只跑（setup 的 after）
func run_plan(plan: Dictionary, plans: Dictionary, checks := true) -> bool:
	var qid := str(plan.get("quest", ""))
	var def := quest_row(qid)
	if def.is_empty():
		return fail("unknown quest " + qid)
	if not apply_setup(plan.get("setup", {}), plans):
		return false
	if str(plan.get("outcome", "")) != "none" and not satisfy_requires(qid, plans):
		return false
	var expect: Dictionary = plan.get("expect", {})
	var before := _snapshot()
	var r0 := rewards.duplicate()
	var rumor0 := rumors.size()
	var stage0 := stage_titles.size()
	var complete0 := completes.size()
	var reload_at := str(plan.get("save_reload_at", ""))
	if reload_at == "" and checks:
		var stg: Array = def.get("stages", [])
		reload_at = str(stg[1].get("id", "")) if stg.size() > 1 else ""
	var reloaded := not checks or reload_at == "" or not allow_reload
	var visited := {}
	var path: Array = plan.get("path", [])
	for i in path.size():
		var step := str(path[i])
		if not do_step(step, qid, expect, str(path[i + 1]) if i + 1 < path.size() else ""):
			return fail("step %d '%s' failed: %s" % [i, step, err]) if err == "" else false
		_let_a_second_pass()
		var sg := stage_of(qid)
		if sg != "":
			visited[sg] = true
		# 中途存檔重載：到了指定階段、沒有開著的對話、不在戰鬥中，而且下一步不是接著的選項或戰鬥
		if not reloaded and sg == reload_at and s().battle_id == 0 and dlg.is_empty():
			var nxt := str(path[i + 1]) if i + 1 < path.size() else ""
			if not (nxt.begins_with("choose@") or nxt.begins_with("fight:")):
				if not save_reload(qid):
					return false
				reloaded = true
	if not checks:
		return err == ""
	if not reloaded:
		notes.append("save_reload_at %s never reached quietly" % reload_at)
	return check_expect(plan, def, expect, before, r0, rumor0, stage0, complete0, visited)

func do_step(step: String, qid: String, expect: Dictionary, next_step := "") -> bool:
	if s() != null and s().battle_id != 0 and not step.begins_with("fight:"):
		clear_battles()
	if step.begins_with("walk@"):
		return walk(step.substr(5))
	if step.begins_with("accept@"):
		var npc := step.substr(7)
		last_npc = npc
		dlg = {}
		var r := send("quest_accept", { "npc": npc, "quest": qid })
		if not r.get("ok", false):
			var why := str(r.get("reason", ""))
			if expect.has("second_accept") and why == str(expect["second_accept"]) and done_entry(qid).has("n"):
				notes.append("re-accept refused as expected: " + why)
				return true
			return fail("quest_accept %s %s -> %s" % [npc, qid, why])
		advance_dialogue()
		if not dlg.is_empty() and active(qid).is_empty() and not next_step.begins_with("choose@" + npc + ":"):
			return auto_accept(qid)
		return true
	if step.begins_with("talk@"):
		return talk(step.substr(5), qid)
	if step.begins_with("choose@"):
		var parts := step.substr(7).split(":")
		if parts.size() != 3:
			return fail("bad step " + step)
		return choose(parts[0], parts[1], parts[2])
	if step.begins_with("act@"):
		dlg = {}
		return must("story_act", { "act": step.substr(4) })
	if step.begins_with("fight:"):
		return fight(step.substr(6))
	if step.begins_with("buy@"):
		var b := step.substr(4).split(":")
		if b.size() < 2:
			return fail("bad step " + step)
		return must("buy", { "npc": b[0], "item": b[1], "n": int(b[2]) if b.size() > 2 else 1 })
	if step.begins_with("wait:hour="):
		dlg = {}
		var ok := debug("hour", step.substr(10))
		advance(0.5)
		clear_battles()
		return ok
	if step.begins_with("wait:days="):
		dlg = {}
		var ok2 := debug("world_s_add", step.substr(10).to_float() * host().day_s() + 1.0)
		advance(0.5)
		refill()
		clear_battles()
		return ok2
	# set_var:<qid>:<name>=<value>：把任務區域變數固定成某值（審查修正：日月鞭法的隨機佛經；捷徑，同 setup 的門派）
	if step.begins_with("set_var:"):
		var sv := step.substr(8)
		var c1 := sv.find(":")
		var eq := sv.find("=")
		if c1 <= 0 or eq <= c1:
			return fail("bad step " + step)
		var vq := sv.substr(0, c1)
		var st0: Dictionary = active(vq)
		if st0.is_empty():
			return fail("set_var: %s is not active" % vq)
		var raw := sv.substr(eq + 1)
		var val: Variant = raw
		if raw.is_valid_int():
			val = int(raw)
		elif raw in ["true", "false"]:
			val = raw == "true"
		st0["vars"][sv.substr(c1 + 1, eq - c1 - 1)] = val
		s().sheet_dirty = true
		notes.append("set_var " + sv)
		return true
	if step.begins_with("expect_stage:"):
		var want := step.substr(13)
		return true if stage_of(qid) == want else fail("expect_stage %s, at %s" % [want, stage_of(qid)])
	if step.begins_with("expect_absent@") or step.begins_with("expect_absent:"):
		var npc2 := step.substr(14)
		flush_view()
		for n in view.get("npcs", []):
			if n is Dictionary and str(n.get("id", n.get("npc", ""))) == npc2:
				return fail("expect_absent: %s is in view" % npc2)
		var r2 := send("talk", { "npc": npc2 })
		return true if not r2.get("ok", false) else fail("expect_absent: talk %s succeeded" % npc2)
	if step.begins_with("expect_menu:"):
		var want_state := step.substr(12)
		for e in host().quests.menu_entries(s(), last_npc):
			if str(e.get("id", "")) == qid:
				return true if str(e.get("state", "")) == want_state else fail("expect_menu %s, got %s" % [want_state, str(e.get("state", ""))])
		return fail("expect_menu: %s not in %s's menu" % [qid, last_npc])
	if step.begins_with("expect_menu_absent@"):
		var mp := step.substr(19).split(":")
		for e in host().quests.menu_entries(s(), mp[0]):
			if str(e.get("id", "")) == (mp[1] if mp.size() > 1 else qid) and str(e.get("state", "")) == "AVAILABLE":
				return fail("expect_menu_absent: %s is AVAILABLE" % str(e.get("id", "")))
		var r3 := send("quest_accept", { "npc": mp[0], "quest": mp[1] if mp.size() > 1 else qid })
		return true if not r3.get("ok", false) else fail("expect_menu_absent: accept succeeded")
	# ---- M3b 語彙
	if step.begins_with("use@"):
		dlg = {}
		var iid := step.substr(4)
		var uid := ""
		for it in ch().inventory.items:
			if str(it.get("id", "")) == iid:
				uid = str(it.get("uid", ""))
				break
		if uid == "":
			return fail("use@%s: not carrying it" % iid)
		return must("use_item", { "item_uid": uid })
	if step.begins_with("expect_no_act@"):
		dlg = {}
		var na := step.substr(14)
		var rn := send("story_act", { "act": na })
		return true if not rn.get("ok", false) else fail("expect_no_act: %s succeeded" % na)
	if step.begins_with("expect_locked@"):
		var lp := step.substr(14).split(":")
		if lp.size() != 3:
			return fail("bad step " + step)
		advance_dialogue()
		if dlg.is_empty() or str(dlg.get("npc", "")) != lp[0] or str(dlg.get("node", "")) != lp[1]:
			return fail("expect_locked: dialogue is at %s:%s" % [str(dlg.get("npc", "")), str(dlg.get("node", ""))])
		for c in dlg.get("choices", []):
			if c is Dictionary and str(c.get("id", "")) == lp[2]:
				return true if bool(c.get("locked", false)) else fail("expect_locked: %s is not locked" % lp[2])
		# 上鎖且 hide 的選項不送出來：也算上鎖
		notes.append("expect_locked: %s hidden" % lp[2])
		return true
	if step.begins_with("debug_give:"):
		var dg := step.substr(11).split(":")
		var gr: Dictionary = host().give_item(ch(), dg[0], int(dg[1]) if dg.size() > 1 else 1)
		host().quests.on_items(s())   # 同撿到東西：重算 COLLECT
		s().sheet_dirty = true
		flush_view()
		return true if gr.get("ok", false) else fail("debug_give %s" % dg[0])
	return fail("unknown step " + step)

## 同步驅動時真實時間幾乎不走：STATE 目標的檢查（QuestSystem.on_sheet，每角色每真實秒一次）在這裡放行一次，
## 等於玩家兩個動作之間隔了一秒
func _let_a_second_pass() -> void:
	if s() != null and s().character != null:
		s().quest_state_check_ms = -100000
		s().sheet_dirty = true
		flush_view()

func save_reload(qid: String) -> bool:
	var before := JSON.stringify(active(qid))
	var esc := str(active(qid).get("escort", ""))
	var wid: String = ws.world_id
	say("save/reload at %s.%s (escort=%s)" % [qid, stage_of(qid), esc])
	ws.save_now()
	ws.stop()
	if ws.start(wid) != OK:
		return fail("restart world failed: " + str(ws.last_error))
	ws.rng.seed = hash(label)
	if not reselect():
		return false
	advance(0.2)
	flush_view()
	var after := JSON.stringify(active(qid))
	if before != after:
		return fail("state changed across reload:\n  before %s\n  after  %s" % [before, after])
	if esc != "":
		var shown := false
		for e in view.get("escort", []):
			if e is Dictionary and str(e.get("npc", "")) == esc:
				shown = true
		if not shown:
			return fail("escort %s missing from view after reload" % esc)
	reloads += 1
	return true

# ======================================================================== 檢查
func check_expect(plan: Dictionary, def: Dictionary, expect: Dictionary, before: Dictionary, r0: Dictionary,
		rumor0: int, stage0: int, complete0: int, visited: Dictionary) -> bool:
	var qid := str(def.get("id", ""))
	var c = ch()
	var partial := expect.has("stage") or expect.has("active_absent") or str(plan.get("outcome", "")) == "none"
	var reaccepted := expect.has("second_accept")   # 路徑最後又接了一次（冷卻後）：任務本來就是進行中
	# 每個走過的階段都有 quest_stage 事件
	var titles := {}
	for i in range(stage0, stage_titles.size()):
		titles[str(stage_titles[i].get("stage_title", ""))] = true
	for sid in visited:
		var t := str(QuestDef.stage(def, str(sid)).get("title", ""))
		if t != "" and not titles.has(t):
			return fail("no quest_stage event for %s.%s (%s)" % [qid, sid, t])
	if expect.has("stage") and stage_of(qid) != str(expect["stage"]):
		return fail("expect stage %s, at %s" % [str(expect["stage"]), stage_of(qid)])
	for q in expect.get("active_absent", []):
		if not active(str(q)).is_empty():
			return fail("expect %s not active" % str(q))
	if not partial:
		if not active(qid).is_empty() and not reaccepted:
			return fail("quest still active at %s" % stage_of(qid))
		var d := done_entry(qid)
		var want := str(expect.get("outcome", plan.get("outcome", "default")))
		if str(d.get("outcome", "")) != want:
			return fail("outcome %s, want %s" % [str(d.get("outcome", "")), want])
		var label_want := str(def.get("outcomes", {}).get(want, {}).get("label", ""))
		var got_label := ""
		for i in range(complete0, completes.size()):
			got_label = str(completes[i].get("outcome_label", ""))
		if completes.size() <= complete0:
			return fail("no quest_complete event")
		if got_label != label_want:
			return fail("quest_complete outcome_label '%s', want '%s'" % [got_label, label_want])
		if expect.has("done_n") and int(d.get("n", 0)) != int(expect["done_n"]):
			return fail("done n %d, want %d" % [int(d.get("n", 0)), int(expect["done_n"])])
	if expect.has("done") and done_entry(str(expect["done"])).is_empty():
		return fail("expect done " + str(expect["done"]))
	# 數值：任務 reward 事件加總
	for pair in [["money", "money"], ["money_gain", "money"], ["fame", "fame"], ["fame_gain", "fame"],
			["lilian", "lilian"], ["lilian_gain", "lilian"], ["learn_points", "learn_points"], ["morality", "morality"]]:
		if expect.has(pair[0]):
			var got := int(rewards.get(pair[1], 0)) - int(r0.get(pair[1], 0))
			if got != int(expect[pair[0]]):
				return fail("%s +%d, want +%d" % [pair[0], got, int(expect[pair[0]])])
	var after := _snapshot()
	# M3b expect 鍵
	for pair2 in [["money_delta", "money"], ["learn_points_delta", "learn_points"]]:
		if expect.has(pair2[0]):
			var dv := int(after[pair2[1]]) - int(before[pair2[1]])
			if dv != int(expect[pair2[0]]):
				return fail("%s %+d, want %+d" % [pair2[0], dv, int(expect[pair2[0]])])
	var spd: Variant = expect.get("skill_prof_delta", {})
	if spd is Dictionary:
		for id in spd:
			var b0: Array = before["skills"].get(str(id), [0, 0])
			var a0: Array = after["skills"].get(str(id), [0, 0])
			if not (int(a0[0]) > int(b0[0]) or int(a0[1]) - int(b0[1]) >= int(spd[id])):
				return fail("skill_prof_delta %s %s -> %s, want +%d" % [str(id), str(b0), str(a0), int(spd[id])])
	if expect.has("sect_rank_pending"):
		var pr := int(c.sect_rank_pending.get("rank", -1)) if not c.sect_rank_pending.is_empty() else -1
		if pr != int(expect["sect_rank_pending"]):
			return fail("sect_rank_pending %d, want %d" % [pr, int(expect["sect_rank_pending"])])
	for cid in expect.get("conditions_absent", []):
		if c.conditions.has(str(cid)):
			return fail("condition %s still present" % str(cid))
	var items: Variant = expect.get("items", {})
	if items is Dictionary:
		for id in items:
			var delta := int(after["inv"].get(id, 0)) - int(before["inv"].get(id, 0))
			if delta != int(items[id]):
				return fail("item %s %+d, want %+d" % [str(id), delta, int(items[id])])
	for id in expect.get("items_absent", []):
		if count_item(str(id)) != 0:
			return fail("item %s should be gone" % str(id))
	var fl: Variant = expect.get("flags", [])
	if fl is Array:
		for f in fl:
			if not bool(c.flags.get(str(f), false)):
				return fail("flag %s not set" % str(f))
	elif fl is Dictionary:
		for f in fl:
			if bool(c.flags.get(str(f), false)) != bool(fl[f]):
				return fail("flag %s is %s, want %s" % [str(f), str(c.flags.get(str(f), false)), str(fl[f])])
	var sk: Variant = expect.get("skills", {})
	if sk is Dictionary:
		for id in sk:
			var lv := int(c.skills.level(str(id)))
			var want_lv := int(sk[id])
			if (want_lv == 0 and lv != 0) or lv < want_lv:
				return fail("skill %s level %d, want %d" % [str(id), lv, want_lv])
	var sp: Variant = expect.get("skill_prof", {})
	if sp is Dictionary:
		for id in sp:
			var b: Array = before["skills"].get(str(id), [0, 0])
			var a: Array = after["skills"].get(str(id), [0, 0])
			if not (int(a[0]) > int(b[0]) or int(a[1]) > int(b[1])):
				return fail("skill_prof %s did not grow (%s -> %s)" % [str(id), str(b), str(a)])
	if expect.has("rumor"):
		advance(3.0)
		var key := str(expect["rumor"])
		var hit := false
		for i in range(rumor0, rumors.size()):
			if str(rumors[i].get("text_key", "")) == key:
				hit = true
		if not hit:
			return fail("no jianghu_rumor %s" % key)
	if expect.get("repeat_cooldown", false) == true and QuestState.cooldown_until(c.quests, qid) <= host().now_s():
		return fail("expected repeat cooldown")
	if not partial and not reaccepted:
		return check_repeat(def)
	if reaccepted and active(qid).is_empty():
		return fail("re-accept after cooldown did not take")
	return true

## 一次性 → 選單 DONE、再接 quest_done；可重複有冷卻 → COOLDOWN、再接 quest_cooldown、快轉後可接
func check_repeat(def: Dictionary) -> bool:
	var qid := str(def.get("id", ""))
	var giver := str(def.get("giver", ""))
	var o := s()
	var mx := int(def.get("repeat", {}).get("max", 1))
	var cd := float(def.get("repeat", {}).get("cooldown_days", 0.0))
	var st: String = host().quests._state_for(o, qid, giver)
	if mx > 0 and int(done_entry(qid).get("n", 0)) >= mx:
		if st != "DONE":
			return fail("one-shot quest menu state %s, want DONE" % st)
		var why: String = host().quests._can_accept(o, qid)
		if why != "quest_done":
			return fail("one-shot quest re-accept: %s" % why)
		return true
	if cd > 0.0:
		if st != "COOLDOWN":
			return fail("repeatable quest menu state %s, want COOLDOWN" % st)
		if host().quests._can_accept(o, qid) != Protocol.R_QUEST_COOLDOWN:
			return fail("repeatable quest not on cooldown")
		debug("world_s_add", cd * host().day_s() + 5.0)
		refill()
		clear_battles()
		var st2: String = host().quests._state_for(o, qid, giver)
		if not (st2 in ["AVAILABLE", "LOCKED"]):
			return fail("after cooldown menu state %s" % st2)
		var why2: String = host().quests._can_accept(o, qid)
		if why2 == Protocol.R_QUEST_COOLDOWN or why2 == "quest_done":
			return fail("after cooldown still refused: " + why2)
	return true
