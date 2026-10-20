class_name RumorSystem
extends RefCounted
## 江湖傳聞（STORY_PLAN §5.1）：事件預告、任務結果、玩家事蹟、強制 PK 擊殺、遊蕩惡人。
## 全部【設計提案・非原作】（研究：原作的「江湖謠言」是匿名玩家頻道，沒有系統謠言）；伺服器選項 rumors_enabled 可關。
##
## - 節流：同一 kind 兩則之間至少 rumor_min_gap_s 真實秒（time_scale 換算成世界時間）；
##   任務「全服第一位完成」與擊敗遊蕩惡人以內部參數 _force 略過節流（「必發」）。
## - 去重：同一 kind + 模板 + 玩家名在 DEDUPE_REAL_S 真實秒內只發一次（QuestSystem 與本系統的輪詢可能各發一次）。
## - ws.world.rumors：最近 KEEP 則（隨 world.json 存檔）：{ text_key, params, kind, world_s, scope, region }。
## - DEED 標記存在 ch.ext.ambient.deeds；任務完成次數的快照存在 ch.ext.ambient.qdone（輪詢角色差異）。
##
## STORY_PLAN 缺漏：K3／S2 寫 `_init(p_host: GameHost)`；這裡不加型別（同 PkSystem），讓單元測試可傳入假主機。

const KIND_FORESHADOW := "FORESHADOW"
const KIND_QUEST := "QUEST"
const KIND_DEED := "DEED"
const KIND_PK := "PK"
const KIND_VILLAIN := "VILLAIN"
const KINDS := [KIND_FORESHADOW, KIND_QUEST, KIND_DEED, KIND_PK, KIND_VILLAIN]
const SCOPE_WORLD := "WORLD"
const SCOPE_REGION := "REGION"

const WORLD_KEY := "rumors"            # ws.world 的鍵（§4.7）
const KEEP := 50                       # ws.world.rumors 保留則數
const LOGIN_REPLAY := 5                # 登入補送則數
const DEFAULT_MIN_GAP_S := 120
const DEDUPE_REAL_S := 10.0
const POLL_REAL_S := 1.0               # 事蹟、任務完成輪詢間隔（真實秒）
const EXT_KEY := "ambient"             # ch.ext 的鍵（§4.7：鍵 = 系統名；AmbientSystem 與本系統共用 ambient 區）
## 審查修正（敘事）：新手歡迎風聲與地區權重【設計提案・非原作】
const WELCOME_KEY := "welcome"
const WELCOME_XP_MAX := 500
const LOCAL_WEIGHT_MULT := 4
const CITY_WEIGHT_MULT := 2
const CITY_REGIONS := ["xixia", "dali"]
## 審查修正（第四輪）：出生城沒有就近事件時，新手歡迎風聲優先講的事件（大理出生 → 西夏的雲兒；大理城的 amb_dl_hook_yuner
## 會指路）【設計提案・非原作】；離給予者 WELCOME_NEAR_HOPS 步以內的事件權重再 ×NEAR_WEIGHT_MULT
const WELCOME_PREFER := { "dali": "q_yuner" }
const WELCOME_NEAR_HOPS := 12
const NEAR_WEIGHT_MULT := 2
## 新手歡迎風聲講過的事件，全服每日預告在這段時間（遊戲日）內先避開（同一則風聲不在新手的頭一個畫面出現兩次）
const WELCOME_AVOID_DAYS := 1.0

## 事蹟門檻（§5.1 #3）
const FAME_MARKS := [100, 500, 1000, 5000]
const EVIL_BELOW := -100               # 善惡 < −100 轉惡（與 GameHost.align_of 的 EVIL 門檻相同）
const EVIL_REARM := 0                  # 回到 0 以上才會再發一次「轉惡」
const SAINT_MARK := 1000
const SAINT_REARM := 500
## 事蹟模板（_ambient 碎片提供）
const T_DEED_FAME := "rmr_deed_fame"
const T_DEED_EVIL := "rmr_deed_evil"
const T_DEED_SAINT := "rmr_deed_saint"
const T_DEED_JOIN := "rmr_deed_join"
const T_DEED_BETRAY := "rmr_deed_betray"

var host
var _last_by_kind: Dictionary = {}     # kind -> 上一則的世界時間（不存檔）
var _recent_sig: Dictionary = {}       # 去重簽章 -> 到期世界時間
var _poll_acc := 0.0
var _last_shichen := -1
var _foreshadow_day := -1              # 今天已發過預告的遊戲日（不存檔：重開頂多多發一則）
var _firsts_seen: Dictionary = {}      # quest_firsts 中已處理過的任務
var _welcome_rng := RandomNumberGenerator.new()
var _fallback_ext: Dictionary = {}     # Character 還沒有 ext 欄位時（WP-ENGINE 尚未合併）的暫存
var _welcomed: Dictionary = {}         # qid -> 送出新手歡迎風聲的世界時間（不存檔）

func _init(p_host) -> void:
	host = p_host
	# 開服時已存在的「全服第一位」視為已發過（重開不重發）
	var qf: Variant = _world().get("quest_firsts", {})
	if qf is Dictionary:
		for qid in qf:
			_firsts_seen[str(qid)] = true

# ======================================================================== 選項

func enabled() -> bool:
	return host != null and host.options.get("rumors_enabled", true) != false

func min_gap_real_s() -> float:
	return maxf(0.0, float(host.options.get("rumor_min_gap_s", DEFAULT_MIN_GAP_S)))

# ======================================================================== 發布

## 節流後廣播（§5.1）。params 可帶內部旗標 "_force": true（略過節流，不略過 rumors_enabled 與去重）、
## "_record_only": true（只記進 ws.world.rumors，不廣播、不占節流；呼叫端已用自己的事件通知過）。
## 送出的 params 一律去掉 peer 類欄位（傳聞對所有人是同一句話）。回傳是否真的發出。
func post(kind: String, text_key: String, params: Dictionary, scope := "WORLD", region := "") -> bool:
	if not enabled() or text_key == "":
		return false
	var force := bool(params.get("_force", false))
	var record_only := bool(params.get("_record_only", false))
	var p := _clean_params(params)
	var now: float = host.now_s()
	_prune_sigs(now)
	var sig := "%s|%s|%s|%s" % [kind, text_key, str(p.get("name", p.get("atk_name", ""))), str(p.get("def_name", ""))]
	if _recent_sig.has(sig):
		return false
	if not force and not record_only and _last_by_kind.has(kind) \
			and now < float(_last_by_kind[kind]) + _world_span(min_gap_real_s()):
		return false
	if scope != SCOPE_REGION:
		scope = SCOPE_WORLD
		region = ""
	var entry := { "text_key": text_key, "params": p, "kind": kind, "world_s": now, "scope": scope, "region": region }
	var list := _list()
	list.append(entry)
	while list.size() > KEEP:
		list.pop_front()
	if record_only:
		return true   # 只記進紀錄（別的系統已經用自己的事件廣播過；例：PkSystem 的 pk_kill）
	_last_by_kind[kind] = now
	_recent_sig[sig] = now + _world_span(DEDUPE_REAL_S)
	var payload := _payload(entry)
	if scope == SCOPE_WORLD:
		host.ws.broadcast_event(Protocol.CH_JIANGHU, Protocol.E_RUMOR, payload)
	else:
		for s in host.sessions():
			if s.character != null and host.index.region_of(s.room_id()) == region:
				host.ws.queue_event(s.peer_id, Protocol.CH_JIANGHU, Protocol.E_RUMOR, payload.duplicate(true))
	return true

## 最近 n 則（舊 → 新）：[{ text_key, params, kind, world_s }]
func recent(n: int) -> Array:
	var list := _list()
	var out: Array = []
	for i in range(maxi(0, list.size() - maxi(n, 0)), list.size()):
		if list[i] is Dictionary:
			out.append(_payload(list[i]))
	return out

## 這位玩家看得到的最近 n 則（REGION 傳聞只給同地區的人）；rumor_list intent 用
func list_for(s: Session, n: int = KEEP) -> Array:
	var region := ""
	if s != null and s.character != null:
		region = host.index.region_of(s.room_id())
	var out: Array = []
	for e in _list():
		if not (e is Dictionary):
			continue
		if str(e.get("scope", SCOPE_WORLD)) == SCOPE_REGION and str(e.get("region", "")) != region:
			continue
		out.append(_payload(e))
	return out.slice(maxi(0, out.size() - n))

## 登入：補送最近 LOGIN_REPLAY 則（不受選項以外的限制）；建立事蹟基準（不把舊成就當新事蹟廣播）；
## 新角色第一次登入另送一則只給他的風聲（welcome_foreshadow）
func on_login(s: Session) -> void:
	if s == null or s.character == null:
		return
	_baseline(s.character)
	if not enabled():
		return
	for p in list_for(s, LOGIN_REPLAY):
		p["replay"] = true
		host.ws.queue_event(s.peer_id, Protocol.CH_JIANGHU, Protocol.E_RUMOR, p)
	welcome_foreshadow(s)

## 審查修正（敘事）：新手（實戰 < WELCOME_XP_MAX）第一次登入，送一則「他自己接得了」的事件風聲，
## 優先挑任務給予者在他所在地區（或出生城）的事件；只送本人、不占全服節流、每角色一次（ch.ext.ambient.welcome）。
## 【設計提案・非原作】（原作沒有系統謠言）。
func welcome_foreshadow(s: Session) -> bool:
	if not enabled() or s == null or s.character == null:
		return false
	var amb := _ext(s.character)
	if bool(amb.get(WELCOME_KEY, false)) or int(s.character.combat_xp) >= WELCOME_XP_MAX:
		return false
	# 審查修正（第四輪）：登入補送的那幾則（含剛發的每日預告）講過的事件不再挑（新手頭一個畫面同一則出現兩次）
	var skip := {}
	for p in list_for(s, LOGIN_REPLAY):
		var q0 := _quest_of_text(str(p.get("text_key", "")))
		if q0 != "":
			skip[q0] = true
	var prefer := str(WELCOME_PREFER.get(_birth_region(s.character), ""))
	var row := pick_foreshadow(str(host.clock().get("shichen_name", "")), s, skip, prefer)
	if row.is_empty():
		return false
	amb[WELCOME_KEY] = true
	var qid := str(row.get("quest", ""))
	if qid != "":
		_welcomed[qid] = host.now_s()
	var entry := { "text_key": str(row["text"]), "params": { "quest_name": _quest_name(qid) }, "kind": KIND_FORESHADOW,
		"world_s": host.now_s(), "scope": SCOPE_WORLD, "region": "" }
	host.ws.queue_event(s.peer_id, Protocol.CH_JIANGHU, Protocol.E_RUMOR, _payload(entry))
	return true

## debug rumor_flush（§4.15）：清空節流與去重
func flush() -> void:
	_last_by_kind.clear()
	_recent_sig.clear()
	_foreshadow_day = -1

## intents_debug 的名字（WP-ENGINE）
func debug_flush() -> void:
	flush()

# ======================================================================== 每 tick

## 預告（每換時辰檢查一次）、事蹟與任務完成輪詢（每 POLL_REAL_S 真實秒）
func tick(dt: float) -> void:
	if host == null:
		return
	_poll_acc += _real_span(dt)
	if _poll_acc >= POLL_REAL_S:
		_poll_acc = 0.0
		poll()
	var c: Dictionary = host.clock()
	var sidx := int(c.get("shichen_idx", 0))
	if sidx != _last_shichen:
		_last_shichen = sidx
		maybe_foreshadow(c)

## 事蹟與任務完成（測試可直接呼叫）
func poll() -> void:
	_poll_firsts()
	for s in host.sessions():
		if s.character == null:
			continue
		_poll_quest_each(s.character)
		_poll_deeds(s.character)

## FORESHADOW（§5.1 #1）：條件成立、還沒人完成的預告列，每個遊戲日最多一則（依 weight 抽）
func maybe_foreshadow(c: Dictionary) -> bool:
	if not enabled():
		return false
	var day := int(c.get("day", 0))
	if day == _foreshadow_day:
		return false
	# 審查修正（第四輪）：剛對新手講過的事件先避開；沒有別的可講才照樣發
	var avoid := {}
	var now: float = host.now_s()
	for q in _welcomed.keys():
		if now - float(_welcomed[q]) <= WELCOME_AVOID_DAYS * _day_s():
			avoid[q] = true
		else:
			_welcomed.erase(q)
	var chosen := pick_foreshadow(str(c.get("shichen_name", "")), null, avoid)
	if chosen.is_empty() and not avoid.is_empty():
		chosen = pick_foreshadow(str(c.get("shichen_name", "")))
	if chosen.is_empty():
		return false
	var qid2 := str(chosen.get("quest", ""))
	var ok := post(KIND_FORESHADOW, str(chosen["text"]), { "quest_name": _quest_name(qid2) })
	if ok:
		_foreshadow_day = day
	return ok

## 依 weight 抽一條預告列；who 不是 null 時只看「這個人接得了」的任務（新手歡迎風聲），否則看線上有沒有人接得了。
## 審查修正（敘事）：任務給予者所在地區有人（who：他本人在那裡或那是他的出生城）時權重 ×LOCAL_WEIGHT_MULT，
## 給予者在兩座出生城（新手最先到的地方）×CITY_WEIGHT_MULT【設計提案・非原作】
## skip：不挑的任務（{ qid: true }）；prefer：who 接得了這條就直接挑它（新手歡迎風聲；審查修正第四輪）
func pick_foreshadow(hour: String, who: Session = null, skip: Dictionary = {}, prefer := "") -> Dictionary:
	var firsts: Variant = _world().get("quest_firsts", {})
	if not (firsts is Dictionary):
		firsts = {}
	var quests: Dictionary = host.tables.get("quests", {})
	var picks: Array = []
	var total := 0
	var rows: Dictionary = host.tables.get("rumors", {})
	var ids := rows.keys()
	ids.sort()
	for rid in ids:
		var row: Variant = rows[rid]
		if not (row is Dictionary) or str(row.get("kind", KIND_FORESHADOW)) != KIND_FORESHADOW:
			continue
		var qid := str(row.get("quest", ""))
		if qid != "" and not quests.has(qid):
			continue
		var rw: Variant = row.get("requires_world", {})
		var nf := str(rw.get("not_first", qid)) if rw is Dictionary else qid
		if nf != "" and (firsts as Dictionary).has(nf):
			continue   # 已經有人完成：預告停止
		var hours: Variant = row.get("hours", [])
		if hours is Array and not (hours as Array).is_empty() and not (hour in hours):
			continue
		var w := maxi(0, int(row.get("weight", 1)))
		if w <= 0 or str(row.get("text", "")) == "" or (qid != "" and skip.has(qid)):
			continue
		# 審查修正：只放「線上有人接得了」的任務風聲（新手不會聽到只有武當弟子能接的事）
		if who != null:
			if qid == "" or not _can_take(who, qid):
				continue
		elif qid != "" and not _someone_can_take(qid):
			continue
		w *= _local_mult(qid, who)
		if who != null and _near(who, qid):
			w *= NEAR_WEIGHT_MULT
		picks.append([row, w])
		total += w
	if picks.is_empty() or total <= 0:
		return {}
	if prefer != "":
		for pw in picks:
			if str((pw[0] as Dictionary).get("quest", "")) == prefer:
				return pw[0]
	# 新手歡迎風聲用自己的亂數（只是一句話，不要改動戰鬥、遇敵用的主機亂數序列）
	var roll: int = (_welcome_rng.randi_range(1, total) if who != null else host.rng.randi_range(1, total))
	var chosen: Dictionary = picks[picks.size() - 1][0]
	for pw in picks:
		roll -= int(pw[1])
		if roll <= 0:
			chosen = pw[0]
			break
	return chosen

func _can_take(s: Session, qid: String) -> bool:
	var q = host.get("quests")
	if q == null or not q.has_method("can_accept"):
		return true
	return str(q.can_accept(s, qid)) == ""

## 給予者所在地區：線上有人在那裡（who 指定時只看他）或是他的出生城 → ×LOCAL_WEIGHT_MULT；給予者在出生城 → ×CITY_WEIGHT_MULT
func _local_mult(qid: String, who: Session) -> int:
	if qid == "":
		return 1
	var giver := str(host.tables.get("quests", {}).get(qid, {}).get("giver", ""))
	var room := str(host.tables.get("npcs", {}).get(giver, {}).get("room", ""))
	if room == "":
		return 1
	var greg: String = host.index.region_of(room)
	var people: Array = [who] if who != null else host.sessions()
	for s in people:
		if s == null or s.character == null:
			continue
		if host.index.region_of(s.room_id()) == greg or _birth_region(s.character) == greg:
			return LOCAL_WEIGHT_MULT
	if greg in CITY_REGIONS:
		return CITY_WEIGHT_MULT
	return 1

## 給予者離這位玩家 WELCOME_NEAR_HOPS 步以內（WorldIndex.hops；假主機沒有就算不近）
func _near(who: Session, qid: String) -> bool:
	if who == null or who.character == null or qid == "" or not host.index.has_method("hops"):
		return false
	var giver := str(host.tables.get("quests", {}).get(qid, {}).get("giver", ""))
	var room := str(host.tables.get("npcs", {}).get(giver, {}).get("room", ""))
	if room == "":
		return false
	return int(host.index.hops(who.room_id(), room, WELCOME_NEAR_HOPS)) >= 0

## 傳聞模板 id → 預告列的任務（沒有回 ""）
func _quest_of_text(text_key: String) -> String:
	if text_key == "":
		return ""
	var rows: Dictionary = host.tables.get("rumors", {})
	for rid in rows:
		var r: Variant = rows[rid]
		if r is Dictionary and str(r.get("text", "")) == text_key:
			return str(r.get("quest", ""))
	return ""

func _birth_region(ch) -> String:
	var b: Variant = ch.get("birth_city")
	return str(b) if b != null else ""

## 線上至少一位角色現在接得了這條任務（QuestSystem.can_accept == ""）；QuestSystem 不在（單元測試的假主機）時一律算可以
func _someone_can_take(qid: String) -> bool:
	var q = host.get("quests")
	if q == null or not q.has_method("can_accept"):
		return true
	for s in host.sessions():
		if s.character != null and str(q.can_accept(s, qid)) == "":
			return true
	return false

# ======================================================================== 任務（§5.1 #2）

## ws.world.quest_firsts（QuestSystem 擁有）出現新任務 → rumors.first（必發，一次）
func _poll_firsts() -> void:
	var qf: Variant = _world().get("quest_firsts", {})
	if not (qf is Dictionary):
		return
	for qid in qf:
		var q := str(qid)
		if _firsts_seen.has(q):
			continue
		_firsts_seen[q] = true
		var key := _quest_rumor_key(q, "first")
		if key != "":
			# 審查修正：第一位完成者的結局也進傳聞（{outcome_label}；QuestSystem 記在 quest_first_outcomes）
			var outs: Variant = _world().get("quest_first_outcomes", {})
			var oc := str(outs.get(q, "")) if outs is Dictionary else ""
			post(KIND_QUEST, key, { "name": str(qf[qid]), "quest_name": _quest_name(q),
				"outcome_label": _outcome_label(q, { "outcome": oc }), "_force": true })

## 角色的任務完成次數變多 → rumors.each（受節流）；全服第一次那一次由 first 負責
func _poll_quest_each(ch) -> void:
	var amb := _ext(ch)
	var done: Variant = ch.quests.get("done", {}) if ch.quests is Dictionary else {}
	if not (done is Dictionary):
		return
	var first_poll := not amb.has("qdone")
	var snap: Dictionary = amb.get_or_add("qdone", {})
	var qf: Variant = _world().get("quest_firsts", {})
	for qid in done:
		var q := str(qid)
		var n := _done_count(done[qid])
		var before := int(snap.get(q, 0))
		snap[q] = n
		if first_poll or n <= before:
			continue
		var key := _quest_rumor_key(q, "each")
		if key == "":
			continue
		if qf is Dictionary and str((qf as Dictionary).get(q, "")) == str(ch.name) and before == 0:
			continue   # 這次就是全服第一位：first 已發
		post(KIND_QUEST, key, { "name": str(ch.name), "quest_name": _quest_name(q),
			"outcome_label": _outcome_label(q, done[qid]) })

static func _done_count(v: Variant) -> int:
	if v is Dictionary:
		return int(v.get("n", 0))
	return int(v) if (v is int or v is float) else 0

func _quest_rumor_key(qid: String, which: String) -> String:
	var r: Variant = host.tables.get("quests", {}).get(qid, {}).get("rumors", {})
	return str(r.get(which, "")) if r is Dictionary else ""

func _quest_name(qid: String) -> String:
	return str(host.tables.get("quests", {}).get(qid, {}).get("name", qid))

func _outcome_label(qid: String, d: Variant) -> String:
	if not (d is Dictionary):
		return ""
	var oc := str(d.get("outcome", ""))
	var outs: Variant = host.tables.get("quests", {}).get(qid, {}).get("outcomes", {})
	if outs is Dictionary and outs.get(oc) is Dictionary:
		return str(outs[oc].get("label", ""))
	return ""

# ======================================================================== 事蹟（§5.1 #3）

## 第一次看到這個角色：以目前狀態當基準，不廣播
func _baseline(ch) -> void:
	var amb := _ext(ch)
	if not amb.has("deeds") or not (amb["deeds"] is Dictionary) or not amb["deeds"].has("init"):
		var top := 0
		for m in FAME_MARKS:
			if int(ch.fame) >= int(m):
				top = int(m)
		amb["deeds"] = { "init": true, "fame": top, "evil": int(ch.morality) < EVIL_BELOW,
			"saint": int(ch.morality) >= SAINT_MARK, "sect": str(ch.sect), "villains": {} }
	if not amb.has("qdone"):
		var snap := {}
		var done: Variant = ch.quests.get("done", {}) if ch.quests is Dictionary else {}
		if done is Dictionary:
			for qid in done:
				snap[str(qid)] = _done_count(done[qid])
		amb["qdone"] = snap

## 名聲里程碑、轉惡、善惡 +1000、加入門派、叛派。發不出去（節流）就下次再試；選項關閉時只記標記。
func _poll_deeds(ch) -> void:
	var amb := _ext(ch)
	if not (amb.get("deeds") is Dictionary) or not amb["deeds"].has("init"):
		_baseline(ch)
		return
	var d: Dictionary = amb["deeds"]
	var nm := str(ch.name)
	# 名聲：只發跨過的最高一級
	var top := int(d.get("fame", 0))
	var reach := top
	for m in FAME_MARKS:
		if int(ch.fame) >= int(m) and int(m) > reach:
			reach = int(m)
	if reach > top and _deed(T_DEED_FAME, { "name": nm, "fame": reach }):
		d["fame"] = reach
	# 轉惡（善惡 < −100）；回到 0 以上重新武裝
	var mo := int(ch.morality)
	if mo >= EVIL_REARM:
		d["evil"] = false
	elif mo < EVIL_BELOW and not bool(d.get("evil", false)) and _deed(T_DEED_EVIL, { "name": nm }):
		d["evil"] = true
	if mo < SAINT_REARM:
		d["saint"] = false
	elif mo >= SAINT_MARK and not bool(d.get("saint", false)) and _deed(T_DEED_SAINT, { "name": nm }):
		d["saint"] = true
	# 門派
	var was := str(d.get("sect", ""))
	var now_sect := str(ch.sect)
	if was != now_sect:
		var sent := true
		if was == "" and now_sect != "":
			sent = _deed(T_DEED_JOIN, { "name": nm, "sect_name": _sect_name(now_sect) })
		elif was != "" and now_sect == "" and _is_traitor(ch, was):
			sent = _deed(T_DEED_BETRAY, { "name": nm, "sect_name": _sect_name(was) })
		if sent:
			d["sect"] = now_sect

## 選項關閉 → 視為已處理（只記標記）；開著 → 發出才算
func _deed(key: String, params: Dictionary) -> bool:
	if not enabled():
		return true
	return post(KIND_DEED, key, params)

## 擊敗遊蕩惡人的事蹟（WanderSystem 呼叫）：記在 deeds.villains[wid]
func note_villain_deed(ch, wid: String) -> void:
	if ch == null:
		return
	var amb := _ext(ch)
	if not (amb.get("deeds") is Dictionary) or not amb["deeds"].has("init"):
		_baseline(ch)
	var v: Dictionary = amb["deeds"].get_or_add("villains", {})
	v[wid] = int(v.get(wid, 0)) + 1

func _is_traitor(ch, sect_id: String) -> bool:
	var t: Variant = ch.get("sect_traitor")
	return t is Array and (t as Array).has(sect_id)

func _sect_name(sect_id: String) -> String:
	return str(host.tables.get("sects", {}).get(sect_id, {}).get("name", sect_id))

# ======================================================================== 輔助

func _world() -> Dictionary:
	return host.ws.world

func _list() -> Array:
	var w := _world()
	var l: Variant = w.get(WORLD_KEY)
	if not (l is Array):
		l = []
		w[WORLD_KEY] = l
	return l

static func _payload(e: Dictionary) -> Dictionary:
	var p: Variant = e.get("params", {})
	return { "text_key": str(e.get("text_key", "")), "params": (p as Dictionary).duplicate(true) if p is Dictionary else {},
		"kind": str(e.get("kind", "")), "world_s": float(e.get("world_s", 0.0)) }

## 去掉內部旗標與 peer 類欄位（傳聞對每個人都是「其他人」的視角）；只留可存進 JSON 的值
static func _clean_params(params: Dictionary) -> Dictionary:
	var out := {}
	for k in params:
		var key := str(k)
		if key.begins_with("_") or key == "peer" or key.ends_with("_peer"):
			continue
		var v: Variant = params[k]
		if v is String or v is int or v is float or v is bool:
			out[key] = v
		elif v is StringName:
			out[key] = str(v)
	return out

func _prune_sigs(now: float) -> void:
	for k in _recent_sig.keys():
		if float(_recent_sig[k]) <= now:
			_recent_sig.erase(k)

## ch.ext.ambient（§4.7）；Character 沒有 ext（WP-ENGINE 尚未合併）時用記憶體暫存
func _ext(ch) -> Dictionary:
	var e: Variant = ch.get("ext")
	if e is Dictionary:
		var a: Variant = e.get(EXT_KEY)
		if not (a is Dictionary):
			a = {}
			e[EXT_KEY] = a
		return a
	return _fallback_ext.get_or_add(str(ch.id), {})

func _world_span(real_s: float) -> float:
	if host.has_method("world_span"):
		return float(host.world_span(real_s))
	return real_s

func _real_span(world_s: float) -> float:
	if host.has_method("real_span"):
		return float(host.real_span(world_s))
	return world_s

func _day_s() -> float:
	if host.has_method("day_s"):
		return float(host.day_s())
	return 86400.0
