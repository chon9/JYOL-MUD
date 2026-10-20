class_name QuestSystem
extends RefCounted
## 任務引擎（M1_PLAN 3.11.11；STORY_PLAN §4，原地升級）：階段（stages）、目標、對話樹與選項、任務區域變數、
## 結局與依結局的獎勵、重複與冷卻、房間動作、護送、時辰與 NPC 出現（appear）、隊伍計分。
## 角色上的狀態見 QuestState（ch.quests = { active, done, cd }）；任務列由 DataLoader 正規化成第 2 版（QuestDef）。
## 主機權威：客戶端只送 intent；離線單機走同一條路徑。

const MAX_TRANSITIONS := 32
const STATE_CHECK_MS := 1000
const FIRSTS_KEY := "quest_firsts"
const FIRST_OUTCOMES_KEY := "quest_first_outcomes"
const ACT_USED_PREFIX := "_act_"      # vars 裡記「repeat: false 的房間動作已用過」
const ACT_WAIT_PREFIX := "_actwait_"  # M3b 審查：fight 動作的 retry_days——沒打贏（逃走、戰敗）要等幾個遊戲日才能再來（世界秒）
var _cur_act := ""                   # 正在跑的房間動作 id（_start_fight 寫進 quest_tag）
const DLG_SEEN_PREFIX := "_dlg_"      # vars 裡記「這段對話開過了」（之後從 resume 開始）
## 審查修正：st["given"] = { item_id: n } 記這次任務實際交到玩家手上的物品（give_items 與 give 動作），
## 扣掉任務自己收回的（take、DELIVER）；放棄或失敗時全部收回，重接不會重複拿到（龍門事件令 1→2→3 的漏洞）。
const GIVEN_KEY := "given"
## 審查修正：give 動作給的可賣物品記在 st.paid 的 "give:<物品>"（件數）；見 _ledger_item
const GIVE_PAID_PREFIX := "give:"

var host: GameHost
var _depth := 0
var _recheck := {}       # peer -> Session（巢狀處理中物品變動，等最外層結束再重算 COLLECT）

func _init(p_host: GameHost) -> void:
	host = p_host

## 第 2 版任務列（生效視圖已正規化；測試直接塞進表的舊格式列在這裡補正規化）
func quest_row(qid: String) -> Dictionary:
	var row: Dictionary = host.tables.get("quests", {}).get(qid, {})
	if row.is_empty() or row.has("stages"):
		return row
	return QuestDef.normalize(row)

static func _active(ch) -> Dictionary:
	QuestState.ensure(ch.quests)
	return ch.quests["active"]

static func _done(ch) -> Dictionary:
	QuestState.ensure(ch.quests)
	return ch.quests["done"]

static func _cd(ch) -> Dictionary:
	QuestState.ensure(ch.quests)
	return ch.quests["cd"]

func _st(ch, qid: String) -> Dictionary:
	return _active(ch).get(qid, {})

func _stage(def: Dictionary, st: Dictionary) -> Dictionary:
	return QuestDef.stage(def, str(st.get("stage", "")))

func _ctx(s: Session) -> Dictionary:
	var c: Dictionary = host.sects.req_ctx(s) if host.sects != null else {}
	if not c.has(Requirements.CTX_SHICHEN):
		c[Requirements.CTX_SHICHEN] = str(host.clock()["shichen_name"])
	return c

## 任務鎖住時列出「還沒達到的條件」（例「福緣 22 以上」），讓玩家知道要練什麼；只列沒達到的那幾條
func _unmet_text(conds: Variant, s: Session) -> String:
	var out: PackedStringArray = []
	if conds is Array:
		for c in conds:
			if c is Dictionary and _req([c], s) != "":
				out.append(Requirements.describe(c, host.tables))
	return "、".join(out)

func _req(conds: Variant, s: Session) -> String:
	if not (conds is Array) or (conds as Array).is_empty():
		return ""
	return Requirements.check(conds, s.character, host.tables, host.options, host.rules, _ctx(s))

func _req_ch(conds: Variant, ch) -> String:
	if not (conds is Array) or (conds as Array).is_empty():
		return ""
	return Requirements.check(conds, ch, host.tables, host.options, host.rules,
		{ Requirements.CTX_SHICHEN: str(host.clock()["shichen_name"]) })

func _shichen() -> String:
	return str(host.clock()["shichen_name"])

static func _hours_ok(hours: Variant, shichen: String) -> bool:
	return not (hours is Array) or (hours as Array).is_empty() or (hours as Array).has(shichen)

# ---------------------------------------------------------------- NPC 選單
## [{ id, name, state, chapter }]；state：AVAILABLE / LOCKED / ACTIVE / READY / DONE / COOLDOWN（COOLDOWN 另附 cooldown_left_s 真實秒）
func menu_entries(s: Session, npc_id: String) -> Array:
	var ch = s.character
	var out: Array = []
	var seen := {}
	for qid in host.npc_row(npc_id).get("quests", []):
		qid = str(qid)
		if quest_row(qid).is_empty() or seen.has(qid):
			continue
		seen[qid] = true
		out.append(_menu_entry(s, qid, npc_id))
	# 不是此 NPC 給的任務，但目前階段有目標在他身上
	var act := _active(ch).keys()
	act.sort()
	for qid in act:
		if seen.has(qid):
			continue
		if not _npc_objectives(ch, qid, npc_id).is_empty():
			seen[qid] = true
			out.append(_menu_entry(s, qid, npc_id))
	return out

func _menu_entry(s: Session, qid: String, npc_id: String) -> Dictionary:
	var row := quest_row(qid)
	var state := _state_for(s, qid, npc_id)
	var e := { "id": qid, "name": str(row.get("name", qid)), "state": state, "chapter": str(row.get("chapter", "")) }
	if state == "LOCKED":
		e["locked_why"] = _unmet_text(row.get("requires", []), s)
	if state == "COOLDOWN":
		e["cooldown_left_s"] = host.real_span(maxf(0.0, QuestState.cooldown_until(s.character.quests, qid) - host.now_s()))
	# M3b 審查 3：READY 是因為護送對象走散（可以重新領）→ 介面顯示「重新領…」而不是「交付／交鏢」
	if state == "READY" and _escort_restartable(s.character, qid, npc_id) != "":
		var only_resume := true
		for o in _npc_objectives(s.character, qid, npc_id):
			if _objective_ready(s, o):
				only_resume = false
		if only_resume:
			e["resume"] = true
	return e

func _state_for(s: Session, qid: String, npc_id: String) -> String:
	var ch = s.character
	if _active(ch).has(qid):
		for o in _npc_objectives(ch, qid, npc_id):
			if _objective_ready(s, o):
				return "READY"
		if _escort_restartable(ch, qid, npc_id) != "":
			return "READY"   # 護送對象走散了：找他再談一次就重新交給你
		return "ACTIVE"
	var row := quest_row(qid)
	var mx := int(row.get("repeat", {}).get("max", 1))
	if mx > 0 and QuestState.done_count(ch.quests, qid) >= mx:
		return "DONE"
	if QuestState.cooldown_until(ch.quests, qid) > host.now_s():
		return "COOLDOWN"
	return "AVAILABLE" if _req(row.get("requires", []), s) == "" else "LOCKED"

## 目前階段裡、在這個 NPC 身上、還沒完成的 TALK／DELIVER 目標
func _npc_objectives(ch, qid: String, npc_id: String) -> Array:
	var out: Array = []
	var st := _st(ch, qid)
	if st.is_empty():
		return out
	var objs: Dictionary = st.get("objs", {})
	for o in _stage(quest_row(qid), st).get("objectives", []):
		if not (o is Dictionary) or str(o.get("npc", "")) != npc_id:
			continue
		# 整合修正（STORY_PLAN 缺漏）：FIGHT 目標也可指定 npc＋dialogue（找強盜、勞德諾交談 → 對話裡的 fight 動作開打），
		# 否則這種目標在 NPC 身上找不到入口（q_xingxia s_bandit、q_hs_spy s_fight）
		var ty := str(o.get("type", ""))
		if not (ty in ["TALK", "DELIVER"]) and not (ty == "FIGHT" and str(o.get("dialogue", "")) != ""):
			continue
		if int(objs.get(str(o.get("id", "")), 0)) >= 1:
			continue
		out.append(o)
	return out

## 現在就能交（時辰對、DELIVER 物品夠或有對話）
func _objective_ready(s: Session, o: Dictionary) -> bool:
	if not _hours_ok(o.get("hours", []), _shichen()):
		return false
	if str(o.get("type", "")) == "DELIVER" and str(o.get("dialogue", "")) == "":
		return int(s.character.inventory.count(str(o.get("item", "")))) >= maxi(1, int(o.get("count", 1)))
	return true

# ---------------------------------------------------------------- 接任務
## 可以接嗎？回 "" 或原因碼（quest_active／quest_done／quest_cooldown／req_*／quest_full）
func _can_accept(s: Session, qid: String) -> String:
	var ch = s.character
	var row := quest_row(qid)
	if row.is_empty():
		return "quest_unknown"
	if _active(ch).has(qid):
		return "quest_active"
	var mx := int(row.get("repeat", {}).get("max", 1))
	if mx > 0 and QuestState.done_count(ch.quests, qid) >= mx:
		return "quest_done"
	if QuestState.cooldown_until(ch.quests, qid) > host.now_s():
		return Protocol.R_QUEST_COOLDOWN
	var req := _req(row.get("requires", []), s)
	if req != "":
		return req
	if _active(ch).size() >= GameHost.MAX_ACTIVE_QUESTS:
		return "quest_full"
	return ""

## 公開版（RumorSystem 的預告篩選用：線上有沒有人接得了這條任務）
func can_accept(s: Session, qid: String) -> String:
	if s == null or s.character == null:
		return "no_char"
	return _can_accept(s, qid)

func _giver_ok(qid: String, npc_id: String) -> bool:
	var row := quest_row(qid)
	return not row.is_empty() and str(row.get("giver", "")) == npc_id and (qid in host.npc_row(npc_id).get("quests", []))

## quest_accept：有 offer 的任務先開那段對話（對話裡的 accept 動作才真的接）；沒有就直接接（M1 行為）
func accept(s: Session, npc_id: String, qid: String) -> Dictionary:
	var r := host.npc_here(s, npc_id)
	if r != "":
		return GameHost.fail(r)
	if not _giver_ok(qid, npc_id):
		return GameHost.fail("quest_unknown")
	var why := _can_accept(s, qid)
	if why != "":
		return GameHost.fail(why)
	_begin()
	if str(quest_row(qid).get("offer", "")) != "":
		_open_dialogue(s, npc_id, qid, str(quest_row(qid)["offer"]), true)
	else:
		_do_accept(s, qid)
	_end(s)
	host.npcs.refresh_menu(s, npc_id)
	return GameHost.ok()

func _do_accept(s: Session, qid: String) -> void:
	var ch = s.character
	var row := quest_row(qid)
	var now := host.now_s()
	_active(ch)[qid] = { "v": QuestState.V, "stage": "", "objs": {}, "vars": {}, "since_world_s": now,
		"stage_since_world_s": now, "escort": "" }
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_QUEST_ACCEPT,
		{ "quest_name": str(row.get("name", qid)), "text": str(row.get("text", "")) })
	for gi in row.get("give_items", []):
		if gi is Dictionary:
			_give(s, str(gi.get("id", "")), int(gi.get("n", 1)), qid)
	_enter_stage(s, qid, str(row.get("start", "")))
	s.sheet_dirty = true

# ---------------------------------------------------------------- 交談、對話
## quest_talk：開 offer 或目前階段在此 NPC 的對話；沒有對話的 TALK／DELIVER 目標直接完成
func talk_quest(s: Session, npc_id: String, qid: String) -> Dictionary:
	var r := host.npc_here(s, npc_id)
	if r != "":
		return GameHost.fail(r)
	var row := quest_row(qid)
	if row.is_empty():
		return GameHost.fail("quest_unknown")
	var ch = s.character
	if not _active(ch).has(qid):
		if not _giver_ok(qid, npc_id):
			return GameHost.fail("quest_not_active")
		return accept(s, npc_id, qid)
	var re_npc := _escort_restartable(ch, qid, npc_id)
	if re_npc != "":
		return _escort_restart(s, npc_id, qid, re_npc)
	return _talk_active(s, npc_id, qid)

## M3b 審查（保鏢死亡後卡關）：護送對象只在階段 on_enter 的 escort_start 交給玩家（例：鏢車 n_ec_biaoche 不站在任何房間）。
## 護送中倒下走散後，回去找給任務的 NPC（同一房間）再談一次 → 重新交給你，不另收費【設計提案】。
## 回傳要重新護送的 NPC id；不適用回 ""
func _escort_restartable(ch, qid: String, npc_id: String) -> String:
	var st := _st(ch, qid)
	if st.is_empty() or str(st.get("escort", "")) != "" or not _giver_ok(qid, npc_id):
		return ""
	var stage := _stage(quest_row(qid), st)
	var esc := ""
	for a in stage.get("on_enter", []):
		if a is Dictionary and str(a.get("do", "")) == "escort_start":
			esc = str(a.get("npc", ""))
	if esc == "":
		return ""
	for o in stage.get("objectives", []):
		if o is Dictionary and str(o.get("type", "")) == "ESCORT" and str(o.get("npc", "")) == esc 				and int(st.get("objs", {}).get(str(o.get("id", "")), 0)) < 1:
			return esc
	return ""

func _escort_restart(s: Session, npc_id: String, qid: String, esc_npc: String) -> Dictionary:
	var st := _st(s.character, qid)
	st["escort"] = esc_npc
	_escort_changed(s)
	host.tell(s, Protocol.CH_SYSTEM, "quest_escort_resumed", { "npc_name": host.npc_name(esc_npc),
		"quest_name": str(quest_row(qid).get("name", qid)) })
	host.npcs.refresh_menu(s, npc_id)
	return GameHost.ok({ "escort": esc_npc })

## refresh：之後重送 npc_menu（refresh: true，只更新已開著的選單）；NpcSystem.talk 直接開對話時不送
func _talk_active(s: Session, npc_id: String, qid: String, refresh := true) -> Dictionary:
	var objs := _npc_objectives(s.character, qid, npc_id)
	if objs.is_empty():
		return GameHost.fail(Protocol.R_DIALOGUE_NONE)
	var o: Dictionary = objs[0]
	for x in objs:
		if _objective_ready(s, x):
			o = x
			break
	if not _hours_ok(o.get("hours", []), _shichen()):
		return GameHost.fail(Protocol.R_QUEST_NOT_NOW)
	_begin()
	var res := GameHost.ok()
	var dlg := str(o.get("dialogue", ""))
	if dlg != "":
		var st := _st(s.character, qid)
		var vars: Dictionary = st["vars"]
		var first := not bool(vars.get(DLG_SEEN_PREFIX + dlg, false))
		vars[DLG_SEEN_PREFIX + dlg] = true
		_open_dialogue(s, npc_id, qid, dlg, first)
	else:
		var why := _precheck_complete(s, qid, str(o.get("id", "")))
		if why != "":
			res = GameHost.fail(why)
		else:
			_mark_complete(s, qid, str(o.get("id", "")))
			_settle(s, qid)
	_end(s)
	if refresh:
		host.npcs.refresh_menu(s, npc_id)
	return res

## NpcSystem.talk：玩家有進行中任務的目前目標在此 NPC 且有對話 → 直接開（回 true，不另開選單）
func auto_dialogue(s: Session, npc_id: String) -> bool:
	if s == null or s.character == null or s.battle_id != 0:
		return false
	var act := _active(s.character).keys()
	act.sort()
	# 審查修正：只有「剛好一條」任務的對話現在真的能往下走時才直接開；目前那句的選項全都上鎖（只剩走開）、
	# 或同一位 NPC 身上有兩條以上任務 → 照常送選單（任務項、教學、拜師、叛派…都點得到；滅絕師太的九陽 < 10 卡住選單）
	var pick := ""
	for qid in act:
		for o in _npc_objectives(s.character, qid, npc_id):
			if str(o.get("dialogue", "")) != "" and _hours_ok(o.get("hours", []), _shichen()) \
					and _dialogue_actionable(s, qid, str(o["dialogue"])):
				if pick != "" and pick != qid:
					return false
				pick = qid
				break
	if pick == "":
		return false
	return bool(_talk_active(s, npc_id, pick, false).get("ok", false))

## 這段對話的入口句：有內容可看（沒有選項的節點，或合成的「繼續」），或至少一個沒上鎖、不是「直接走開」
## （沒有動作又 goto END）的選項
func _dialogue_actionable(s: Session, qid: String, dlg: String) -> bool:
	var def := quest_row(qid)
	var first := not bool(_st(s.character, qid).get("vars", {}).get(DLG_SEEN_PREFIX + dlg, false))
	var node_id := DialogueTree.entry_node(def, dlg, first)
	if node_id == "":
		return false
	var v := DialogueTree.node_view(def, dlg, node_id, s.character, host.tables, host.options, host.rules, _ctx(s))
	var choices: Array = v.get("choices", [])
	if choices.is_empty():
		return true
	for c in choices:
		if bool(c.get("locked", false)):
			continue
		var cid := str(c.get("id", ""))
		if cid == DialogueTree.NEXT_CHOICE:
			return true
		var full := DialogueTree.choice(def, dlg, node_id, cid)
		var g := str(full.get("goto", DialogueTree.END))
		if not (full.get("do", []) as Array).is_empty() or (g != "" and g != DialogueTree.END):
			return true
	return false

## M1 的 quest_turn_in：等於完成此 NPC 的 TALK／DELIVER 目標（有對話的開對話）
func turn_in(s: Session, npc_id: String, qid: String) -> Dictionary:
	var ch = s.character
	if not _active(ch).has(qid):
		return GameHost.fail("quest_not_active")
	var r := host.npc_here(s, npc_id)
	if r != "":
		return GameHost.fail(r)
	if _npc_objectives(ch, qid, npc_id).is_empty():
		# M3b 審查 3：鏢車丟了時選單顯示 READY，介面送的是 quest_turn_in——同樣交給 _escort_restart（以前回 quest_incomplete，玩家領不回鏢車）
		var re_npc := _escort_restartable(ch, qid, npc_id)
		if re_npc != "":
			return _escort_restart(s, npc_id, qid, re_npc)
		return GameHost.fail("quest_incomplete")
	return _talk_active(s, npc_id, qid)

## dialogue_choose：游標必須一致（npc、quest、node），否則 dialogue_stale；上鎖 → choice_locked；
## 選項的動作有任何一項做不到（take 數量不夠…）→ 整個選項不執行
func choose(s: Session, npc_id: String, qid: String, node_id: String, choice_id: String) -> Dictionary:
	var cur: Dictionary = s.dialogue
	if cur.is_empty():
		return GameHost.fail(Protocol.R_DIALOGUE_NONE)
	if str(cur.get("npc", "")) != npc_id or str(cur.get("quest", "")) != qid or str(cur.get("node", "")) != node_id:
		return GameHost.fail(Protocol.R_DIALOGUE_STALE)
	if host.npc_here(s, npc_id) != "":
		drop_dialogue(s)
		return GameHost.fail(Protocol.R_DIALOGUE_STALE)
	var def := quest_row(qid)
	var dlg := str(cur.get("dlg", ""))
	var c := DialogueTree.choice(def, dlg, node_id, choice_id)
	if c.is_empty():
		return GameHost.fail(Protocol.R_DIALOGUE_STALE)
	if _req(c.get("requires", []), s) != "":
		return GameHost.fail(Protocol.R_CHOICE_LOCKED)
	var why := _precheck(s, qid, c.get("do", []))
	if why != "":
		return GameHost.fail(why)
	_begin()
	_run_actions(s, qid, npc_id, c.get("do", []))
	# 動作沒有關掉對話（fight、close、fail、換了對話）→ 往下一個節點
	if s.dialogue.get("dlg") == dlg and str(s.dialogue.get("quest", "")) == qid and str(s.dialogue.get("node", "")) == node_id:
		var g := str(c.get("goto", DialogueTree.END))
		if g == "" or g == DialogueTree.END:
			_close_dialogue(s, true)
		else:
			_show_node(s, npc_id, qid, dlg, g)
	_settle_all(s)
	_end(s)
	host.npcs.refresh_menu(s, npc_id)
	return GameHost.ok()

## dialogue_close：沒有開著的對話也回 ok（重複按「結束」不報錯）
func close_dialogue(s: Session) -> Dictionary:
	_close_dialogue(s, true)
	return GameHost.ok()

## 移動、開戰、斷線時清掉游標（有的話送 dialogue_close）
func drop_dialogue(s: Session) -> void:
	if s != null and s.has_dialogue():
		_close_dialogue(s, s.character != null)

func _close_dialogue(s: Session, notify: bool) -> void:
	if s.dialogue.is_empty():
		return
	var npc := str(s.dialogue.get("npc", ""))
	s.dialogue = {}
	if notify:
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_DIALOGUE_CLOSE, { "npc": npc }, true)

func _open_dialogue(s: Session, npc_id: String, qid: String, dlg: String, first: bool) -> void:
	var def := quest_row(qid)
	var node_id := DialogueTree.entry_node(def, dlg, first)
	if node_id == "":
		_close_dialogue(s, true)
		return
	_show_node(s, npc_id, qid, dlg, node_id)

## 移到某節點：設游標 → 執行節點的 do → 送 dialogue（動作把對話關掉時就不送）
func _show_node(s: Session, npc_id: String, qid: String, dlg: String, node_id: String) -> void:
	var def := quest_row(qid)
	if DialogueTree.node(def, dlg, node_id).is_empty():
		_close_dialogue(s, true)
		return
	var cur := { "npc": npc_id, "quest": qid, "dlg": dlg, "node": node_id }
	s.dialogue = cur
	var v := DialogueTree.node_view(def, dlg, node_id, s.character, host.tables, host.options, host.rules, _ctx(s))
	var acts: Array = v.get("do", [])
	if not acts.is_empty():
		if _precheck(s, qid, acts) == "":
			_run_actions(s, qid, npc_id, acts)
		if s.dialogue != cur:
			return
		# 節點動作可能改了條件（變數、物品）→ 重算選項是否上鎖
		v = DialogueTree.node_view(def, dlg, node_id, s.character, host.tables, host.options, host.rules, _ctx(s))
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_DIALOGUE, {
		"npc": npc_id, "npc_name": host.npc_name(npc_id), "quest": qid, "quest_name": str(def.get("name", qid)),
		"dlg": dlg, "node": node_id, "speaker_name": _speaker_name(s, npc_id, str(v.get("speaker", "npc"))),
		"text": _fill(s, npc_id, str(v.get("text", ""))), "choices": _fill_choices(s, npc_id, v.get("choices", [])),
		"end": bool(v.get("end", true)),
	}, true)
	# 審查修正：結束節點（沒有選項，或只剩 goto END）送出後就收掉游標、不另送 dialogue_close（客戶端「結束」不送東西）；
	# 否則游標一直留著，WanderSystem._idle 把玩家當成「忙碌」，遊蕩惡人整段時間都不會出手
	if bool(v.get("end", true)) and s.dialogue == cur:
		s.dialogue = {}

func _speaker_name(s: Session, npc_id: String, speaker: String) -> String:
	match speaker:
		"npc", "":
			return host.npc_name(npc_id)
		"player":
			return str(s.character.name)
	return host.npc_name(speaker)

func _fill(s: Session, npc_id: String, text: String) -> String:
	return GameHost.fill_address(text.replace("{name}", str(s.character.name)).replace("{npc_name}", host.npc_name(npc_id)), s.character)

func _fill_choices(s: Session, npc_id: String, choices: Array) -> Array:
	var out: Array = []
	for c in choices:
		var d: Dictionary = (c as Dictionary).duplicate()
		d["label"] = _fill(s, npc_id, str(d.get("label", "")))
		out.append(d)
	return out

# ---------------------------------------------------------------- 動作
## 動作執行前的檢查：take 與 DELIVER 的 complete 加總後物品夠不夠、accept 能不能接、fight 時是否已在戰鬥
func _precheck(s: Session, qid: String, acts: Variant) -> String:
	if not (acts is Array):
		return ""
	var need := {}
	var ch = s.character
	for a in acts:
		if not (a is Dictionary):
			continue
		match str(a.get("do", "")):
			"take":
				var it := str(a.get("item", ""))
				need[it] = int(need.get(it, 0)) + maxi(1, int(a.get("n", 1)))
			"complete":
				var o := _current_objective(ch, qid, str(a.get("obj", "")))
				if str(o.get("type", "")) == "DELIVER" and o.get("consume", true) != false \
						and int(_st(ch, qid).get("objs", {}).get(str(o.get("id", "")), 0)) < 1:
					var it2 := str(o.get("item", ""))
					need[it2] = int(need.get(it2, 0)) + maxi(1, int(o.get("count", 1)))
			"accept":
				if not _active(ch).has(qid):
					var why := _can_accept(s, qid)
					if why != "":
						return why
			"fight":
				if s.battle_id != 0:
					return "in_battle"
	for it in need:
		if int(ch.inventory.count(str(it))) < int(need[it]):
			return "quest_incomplete"
	return ""

func _precheck_complete(s: Session, qid: String, oid: String) -> String:
	return _precheck(s, qid, [{ "do": "complete", "obj": oid }])

func _current_objective(ch, qid: String, oid: String) -> Dictionary:
	var st := _st(ch, qid)
	if st.is_empty():
		return {}
	return QuestDef.objective(quest_row(qid), str(st.get("stage", "")), oid)

## 依序執行動作（§4.4）。fight 最後才開打（同一串裡其他動作先做完）。
func _run_actions(s: Session, qid: String, npc_id: String, acts: Variant) -> void:
	if not (acts is Array):
		return
	var ch = s.character
	var fight: Dictionary = {}
	for a in acts:
		if not (a is Dictionary) or s.character == null:
			continue
		var st := _st(ch, qid)
		match str(a.get("do", "")):
			"accept":
				if st.is_empty() and _can_accept(s, qid) == "":
					_do_accept(s, qid)
			"complete":
				if not st.is_empty():
					_mark_complete(s, qid, str(a.get("obj", "")))
			"var":
				if not st.is_empty():
					var val: Variant = a.get("value")
					var pool: Variant = a.get("random", null)
					if pool is Array and not (pool as Array).is_empty():
						val = pool[host.rng.randi_range(0, (pool as Array).size() - 1)]
					st["vars"][str(a.get("name", ""))] = QuestState.clean_value(val)
					s.sheet_dirty = true
			"goto":
				if not st.is_empty():
					_enter_stage(s, qid, str(a.get("stage", "")))
			"finish":
				if not st.is_empty():
					_finish(s, qid, str(a.get("outcome", QuestDef.DEFAULT_OUTCOME)))
			"fail":
				if not st.is_empty():
					_fail(s, qid, str(a.get("reason", "")))
			"give":
				var gi := str(a.get("item", ""))
				var gn := maxi(1, int(a.get("n", 1)))
				if _ledger_item(gi):
					# 審查修正：能賣、能吃的物品（韋小寶的金戒指、雲兒的清水與牛肉餅）記進中途獎勵帳：
					# 上一次放棄／失敗時沒還回來（賣掉、吃掉）的件數，重接後不再給（放棄→重接→再拿去賣的漏洞）
					var gk := GIVE_PAID_PREFIX + gi
					var skip := _consume_prepaid_units(ch, qid, gk, gn)
					if gn - skip > 0:
						_give(s, gi, gn - skip, qid)
					_note_paid(st, gk, gn)
				else:
					_give(s, gi, gn, qid)
			"take":
				_take(s, str(a.get("item", "")), maxi(1, int(a.get("n", 1))), qid)
			"reward":
				var rw: Variant = a.get("rewards", null)
				if not (rw is Dictionary):
					rw = (a as Dictionary).duplicate()
					(rw as Dictionary).erase("do")
				# 審查修正：放棄（或失敗）前已經領過的中途獎勵，重接後不再發（放棄→重接→再領的漏洞）
				var pk := "reward:" + JSON.stringify(rw, "", true)
				if not _consume_prepaid(ch, qid, pk):
					_give_rewards(s, rw, false)
				_note_paid(st, pk)   # 抵掉的也算這一次領過（再放棄時照樣記回去）
			"flag":
				ch.flags[str(a.get("flag", ""))] = true
				s.sheet_dirty = true
			"unflag":
				ch.flags.erase(str(a.get("flag", "")))
				s.sheet_dirty = true
			"learn":
				var sk_id := str(a.get("skill", ""))
				if a.has("add"):
					var lk := "learn:%s:%d" % [sk_id, maxi(1, int(a.get("add", 1)))]
					if not _consume_prepaid(ch, qid, lk):
						_learn(s, sk_id, int(ch.skills.level(sk_id)) + maxi(1, int(a.get("add", 1))))
					_note_paid(st, lk)
				else:
					_learn(s, sk_id, int(a.get("level", 1)))
			"fight":
				fight = a
			"escort_start":
				if not st.is_empty():
					st["escort"] = str(a.get("npc", npc_id))
					_escort_changed(s)
			"escort_end":
				if not st.is_empty():
					st["escort"] = ""
					_escort_changed(s)
			"tell":
				host.tell(s, Protocol.CH_SYSTEM, str(a.get("key", "")), _params(s, qid, npc_id))
			"rumor":
				_rumor(s, str(a.get("key", "")), str(a.get("scope", "WORLD")), _params(s, qid, npc_id))
			"close":
				_close_dialogue(s, true)
	if not fight.is_empty():
		_start_fight(s, qid, fight)

## 這次任務中途發過的獎勵（reward 動作、learn add）：st["paid"] = { key: 次數 }；give 動作的 "give:<物品>" 記件數
static func _note_paid(st: Dictionary, key: String, n := 1) -> void:
	if st.is_empty() or n <= 0:
		return
	var paid: Dictionary = st.get_or_add(QuestState.PAID_KEY, {})
	paid[key] = int(paid.get(key, 0)) + n

## give 動作要記帳的物品：能賣（有價、不是 no_sell、不是任務物品）。信件、令牌等任務物品不記
## （任務後面還要收回；記了反而重接後拿不到、卡關）
func _ledger_item(item_id: String) -> bool:
	var row: Variant = host.tables.get("items", {}).get(item_id, null)
	if not (row is Dictionary):
		return false
	return int(row.get("price", 0)) > 0 and row.get("no_sell", false) != true and row.get("quest_item", false) != true

## 放棄／失敗那一次帶走、還沒抵掉的件數（最多 n）抵掉，回抵掉幾件
static func _consume_prepaid_units(ch, qid: String, key: String, n: int) -> int:
	var all: Variant = ch.quests.get(QuestState.PAID_KEY)
	if not (all is Dictionary) or not ((all as Dictionary).get(qid) is Dictionary):
		return 0
	var d: Dictionary = all[qid]
	var k := mini(n, int(d.get(key, 0)))
	if k <= 0:
		return 0
	if int(d[key]) - k > 0:
		d[key] = int(d[key]) - k
	else:
		d.erase(key)
	if d.is_empty():
		(all as Dictionary).erase(qid)
	return k

## give 帳扣掉任務自己收回（take、DELIVER）或放棄時收回的件數（只剩玩家留著、賣掉或吃掉的）
func _unnote_give(st: Dictionary, item_id: String, k: int) -> void:
	if st.is_empty() or k <= 0 or not (st.get(QuestState.PAID_KEY) is Dictionary):
		return
	var paid: Dictionary = st[QuestState.PAID_KEY]
	var gk := GIVE_PAID_PREFIX + item_id
	if not paid.has(gk):
		return
	var left := int(paid[gk]) - k
	if left > 0:
		paid[gk] = left
	else:
		paid.erase(gk)

## 放棄／失敗的那一次已經領過、還沒抵掉的中途獎勵：有就抵掉一次並回 true（這次不發）
static func _consume_prepaid(ch, qid: String, key: String) -> bool:
	var all: Variant = ch.quests.get(QuestState.PAID_KEY)
	if not (all is Dictionary) or not ((all as Dictionary).get(qid) is Dictionary):
		return false
	var d: Dictionary = all[qid]
	var n := int(d.get(key, 0))
	if n <= 0:
		return false
	if n == 1:
		d.erase(key)
	else:
		d[key] = n - 1
	if d.is_empty():
		(all as Dictionary).erase(qid)
	return true

## 放棄／失敗：把這次中途領過的獎勵記到角色上（ch.quests.paid[qid]），重接時抵掉；任務完成時清掉
static func _carry_paid(ch, qid: String, st: Dictionary) -> void:
	var paid: Variant = st.get(QuestState.PAID_KEY)
	if not (paid is Dictionary) or (paid as Dictionary).is_empty():
		return
	var all: Dictionary = ch.quests.get_or_add(QuestState.PAID_KEY, {})
	var d: Dictionary = all.get_or_add(qid, {})
	for k in paid:
		d[str(k)] = int(d.get(str(k), 0)) + int(paid[k])

func _params(s: Session, qid: String, npc_id: String) -> Dictionary:
	return { "name": str(s.character.name), "npc_name": host.npc_name(npc_id) if npc_id != "" else "",
		"quest_name": host.quest_name(qid), "room_name": host.room_name(s.room_id()) }

func _escort_changed(s: Session) -> void:
	s.view_dirty = true
	s.sheet_dirty = true
	host.regions.mark_room_dirty(s.room_id(), s.peer_id)

## qid != ""：記進這次任務的 given（放棄／失敗時收回）
func _give(s: Session, item_id: String, n: int, qid := "") -> void:
	if item_id == "" or n <= 0 or not host.tables.get("items", {}).has(item_id):
		return
	# M3B_PLAN §5.4：unique_per_char（絕情丹「一人一顆」）：身上已有就不給（任務不失敗），最多給 1 個
	if bool(host.tables["items"][item_id].get("unique_per_char", false)):
		if int(s.character.inventory.count(item_id)) > 0:
			return
		n = 1
	var g: Dictionary = host.give_item(s.character, item_id, n)
	if g.get("ok", false):
		host.item_gain_event(s, item_id, n)
		if qid != "":
			var st := _st(s.character, qid)
			if not st.is_empty():
				var given: Dictionary = st.get_or_add(GIVEN_KEY, {})
				given[item_id] = int(given.get(item_id, 0)) + n
	s.sheet_dirty = true

## qid != ""：任務自己收回的物品從 given 扣掉（之後放棄不會多收）；回實際收走的件數
func _take(s: Session, item_id: String, n: int, qid := "") -> int:
	var have := int(s.character.inventory.count(item_id))
	var k := mini(n, have)
	if k <= 0:
		return 0
	s.character.inventory.remove_item_id(item_id, k)
	host.item_lost_event(s, item_id, k)
	if qid != "":
		var st := _st(s.character, qid)
		var given: Variant = st.get(GIVEN_KEY, null)
		if given is Dictionary and (given as Dictionary).has(item_id):
			var left := int(given[item_id]) - k
			if left > 0:
				given[item_id] = left
			else:
				(given as Dictionary).erase(item_id)
		_unnote_give(st, item_id, k)
	s.sheet_dirty = true
	return k

## learn：直接學到該級（已高於則不變；受 skill_cap）
func _learn(s: Session, skill_id: String, level: int) -> void:
	if skill_id == "" or SkillBook.kind_of(skill_id, host.tables) == "":
		return
	var ch = s.character
	var before := int(ch.skills.level(skill_id))
	var target := mini(level, host.skill_cap(ch, skill_id))
	if target <= before:
		return
	ch.skills.set_level(skill_id, target, host.tables)
	host.npcs.skill_up_event(s, skill_id, before, target)
	s.sheet_dirty = true

func _rumor(s: Session, key: String, scope: String, params: Dictionary) -> void:
	if key == "":
		return
	var region := host.index.region_of(s.room_id()) if s.character != null else ""
	host.m2_call(host.get("rumor"), "post", ["QUEST", key, params, scope if scope in QuestDef.RUMOR_SCOPES else "WORLD", region], false)

## 獎勵（§4.9）：既有欄位＋lilian、killing_intent、learn、rumor。always_tell：結局獎勵一律送 reward 事件（M1 行為）
func _give_rewards(s: Session, rw_in: Variant, always_tell := true, params: Dictionary = {}) -> void:
	var ch = s.character
	var rw := QuestDef.norm_rewards(rw_in)
	var got: Dictionary = ch.apply_rewards(rw, host.rules)
	var any := false
	for k in ["combat_xp", "learn_points", "money", "fame", "morality", "lilian", "killing_intent"]:
		if int(got.get(k, 0)) != 0:
			any = true
	if always_tell or any:
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_REWARD, {
			"combat_xp": int(got.get("combat_xp", 0)), "learn_points": int(got.get("learn_points", 0)),
			"money": int(got.get("money", 0)), "fame": int(got.get("fame", 0)), "morality": int(got.get("morality", 0)),
			"lilian": int(got.get("lilian", 0)), "killing_intent": int(got.get("killing_intent", 0)) })
	for it in rw.get("items", []):
		if it is Dictionary:
			_give(s, str(it.get("id", "")), int(it.get("n", 1)))
	# M3B_PLAN §4.9、§5.4：sect_rank 獎勵 → SectSystem.queue_rank（assembly 記待升，否則立即升）
	var sr: Variant = rw.get("sect_rank", null)
	if sr is Dictionary and host.get("sects") != null:
		host.sects.queue_rank(s, str(sr.get("sect", "")), int(sr.get("rank", 0)))
	var sp: Variant = rw.get("skill_prof", {})
	if sp is Dictionary:
		var keys: Array = sp.keys()
		keys.sort()
		for skill_id in keys:
			var before := int(ch.skills.level(str(skill_id)))
			var res: Dictionary = ch.skills.add_prof(str(skill_id), int(sp[skill_id]), host.tables,
				host.skill_cap(ch, str(skill_id)))
			host.npcs.skill_up_event(s, str(skill_id), before, int(res.get("after", before)))
	var ln: Variant = rw.get("learn", {})
	if ln is Dictionary:
		var keys2: Array = ln.keys()
		keys2.sort()
		for skill_id in keys2:
			_learn(s, str(skill_id), int(ln[skill_id]))
	# learn_add：在目前等級上再升 n 級（審查修正：藍鳳凰「基本毒術升一級」每次都升）
	var la: Variant = rw.get("learn_add", {})
	if la is Dictionary:
		var keys3: Array = la.keys()
		keys3.sort()
		for skill_id in keys3:
			var add := int(la[skill_id])
			if add > 0:
				_learn(s, str(skill_id), int(ch.skills.level(str(skill_id))) + add)
	if str(rw.get("rumor", "")) != "":
		var p := params if not params.is_empty() else { "name": str(ch.name) }
		_rumor(s, str(rw["rumor"]), "WORLD", p)
	s.sheet_dirty = true

# ---------------------------------------------------------------- 階段推進
## 完成目前階段的某個目標（DELIVER：扣物品）
func _mark_complete(s: Session, qid: String, oid: String) -> void:
	var ch = s.character
	var st := _st(ch, qid)
	var o := _current_objective(ch, qid, oid)
	if st.is_empty() or o.is_empty():
		return
	var objs: Dictionary = st["objs"]
	var t := str(o.get("type", ""))
	var need := maxi(1, int(o.get("count", 1)))
	if t == "DELIVER" and int(objs.get(oid, 0)) < 1 and o.get("consume", true) != false:
		_take(s, str(o.get("item", "")), need, qid)
	objs[oid] = need if t in ["KILL", "BUY", "COLLECT"] else 1
	_progress_event(s, qid, o, need, need)
	s.sheet_dirty = true

func _progress_event(s: Session, qid: String, o: Dictionary, have: int, need: int) -> void:
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_QUEST_PROGRESS, {
		"quest_name": host.quest_name(qid), "have": have, "need": need, "target_name": _target_name(o) })

func _target_name(o: Dictionary) -> String:
	var txt := str(o.get("text", ""))
	if txt != "":
		return txt
	match str(o.get("type", "")):
		"KILL":
			return host.monster_name(str(o.get("monster", "")))
		"REACH":
			return host.room_name(str(o.get("room", "")))
		"DELIVER":
			return "%s（%s）" % [host.npc_name(str(o.get("npc", ""))), host.item_name(str(o.get("item", "")))]
		"COLLECT", "BUY":
			return host.item_name(str(o.get("item", "")))
	return host.npc_name(str(o.get("npc", "")))

func _enter_stage(s: Session, qid: String, stage_id: String) -> void:
	var st := _st(s.character, qid)
	var def := quest_row(qid)
	var stage := QuestDef.stage(def, stage_id)
	if st.is_empty() or stage.is_empty():
		return
	st["stage"] = stage_id
	st["objs"] = {}
	st["stage_since_world_s"] = host.now_s()
	var texts: Array = []
	for o in stage.get("objectives", []):
		if o is Dictionary:
			texts.append(str(o.get("text", "")))
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_QUEST_STAGE, {
		"quest_name": str(def.get("name", qid)), "stage_title": str(stage.get("title", "")), "objectives": texts })
	s.sheet_dirty = true
	s.view_dirty = true
	_run_actions(s, qid, "", stage.get("on_enter", []))

## 依目前狀態推進（自動目標標記 → 階段完成 → on_complete → next）；最多 MAX_TRANSITIONS 次
func _settle(s: Session, qid: String) -> void:
	if s == null or s.character == null:
		return
	for i in MAX_TRANSITIONS:
		var st := _st(s.character, qid)
		if st.is_empty():
			return
		var def := quest_row(qid)
		var stage := _stage(def, st)
		if stage.is_empty():
			if def.is_empty() or QuestDef.stage(def, str(def.get("start", ""))).is_empty():
				return   # 任務資料不見了：狀態留著，等資料回來
			_enter_stage(s, qid, str(def["start"]))
			continue
		if not (stage.get("fail_if", []) as Array).is_empty() and _req(stage["fail_if"], s) == "":
			_fail(s, qid, str(stage.get("fail_reason", "")))
			return
		_auto_marks(s, qid, st, stage)
		if not _stage_done(s, st, stage):
			return
		var sid := str(stage.get("id", ""))
		_run_actions(s, qid, "", stage.get("on_complete", []))
		st = _st(s.character, qid)
		if st.is_empty() or str(st.get("stage", "")) != sid:
			continue
		var g := _pick_next(s, stage.get("next", []))
		if QuestDef.is_end(g):
			_finish(s, qid, QuestDef.outcome_of(g))
			return
		if QuestDef.stage(def, g).is_empty():
			push_warning("[QuestSystem] %s.%s: next '%s' missing" % [qid, sid, g])
			return
		_enter_stage(s, qid, g)
	push_warning("[QuestSystem] %s: too many stage transitions" % qid)

func _settle_all(s: Session) -> void:
	if s == null or s.character == null:
		return
	var act := _active(s.character).keys()
	act.sort()
	for qid in act:
		_settle(s, qid)

func _pick_next(s: Session, nx: Array) -> String:
	var last := QuestDef.END + ":" + QuestDef.DEFAULT_OUTCOME
	for e in nx:
		if not (e is Dictionary):
			continue
		last = str(e.get("goto", last))
		if not e.has("if") or _req(e["if"], s) == "":
			return last
	return last

## REACH、ESCORT、WAIT、STATE：條件成立就記上完成（COLLECT 不記，每次即時看背包）
func _auto_marks(s: Session, qid: String, st: Dictionary, stage: Dictionary) -> void:
	var objs: Dictionary = st["objs"]
	var room := s.room_id()
	for o in stage.get("objectives", []):
		if not (o is Dictionary):
			continue
		var oid := str(o.get("id", ""))
		if int(objs.get(oid, 0)) >= 1:
			continue
		var hit := false
		match str(o.get("type", "")):
			"REACH":
				hit = room != "" and room == str(o.get("room", ""))
			"ESCORT":
				hit = str(st.get("escort", "")) == str(o.get("npc", "")) and room == str(o.get("to_room", ""))
			"WAIT":
				if o.has("days"):
					hit = host.now_s() - float(st.get("stage_since_world_s", 0.0)) >= float(o["days"]) * host.day_s() - 0.001
				else:
					hit = _hours_ok(o.get("hours", []), _shichen()) and not (o.get("hours", []) as Array).is_empty()
			"STATE":
				hit = _req(o.get("requires", []), s) == ""
		if hit:
			objs[oid] = 1
			_progress_event(s, qid, o, 1, 1)
			s.sheet_dirty = true

func _objective_done(s: Session, st: Dictionary, o: Dictionary) -> bool:
	var mark := int(st.get("objs", {}).get(str(o.get("id", "")), 0))
	var need := maxi(1, int(o.get("count", 1)))
	match str(o.get("type", "")):
		"KILL", "BUY":
			return mark >= need
		"COLLECT":
			return mark >= need or int(s.character.inventory.count(str(o.get("item", "")))) >= need
	return mark >= 1

func _stage_done(s: Session, st: Dictionary, stage: Dictionary) -> bool:
	var objs: Array = stage.get("objectives", [])
	if objs.is_empty():
		return true
	var any := bool(stage.get("any", false))
	for o in objs:
		if not (o is Dictionary):
			continue
		var d := _objective_done(s, st, o)
		if any and d:
			return true
		if not any and not d:
			return false
	return not any

## 任務結束：記 done（次數、結局、世界時間）、冷卻、全服第一、事件、結局獎勵、傳聞
func _finish(s: Session, qid: String, outcome: String) -> void:
	var ch = s.character
	if not _active(ch).has(qid):
		return
	var def := quest_row(qid)
	_active(ch).erase(qid)
	var pall: Variant = ch.quests.get(QuestState.PAID_KEY)
	if pall is Dictionary:
		(pall as Dictionary).erase(qid)   # 完成了：之前放棄時記下的中途獎勵不再抵（下一輪重做照常發）
	var now := host.now_s()
	var d := QuestState.done_entry(ch.quests, qid)
	if d.is_empty():
		d = { "n": 0, "outcome": "", "world_s": 0.0, "failed": 0 }
	d["n"] = int(d["n"]) + 1
	d["outcome"] = outcome
	d["world_s"] = now
	_done(ch)[qid] = d
	_set_cooldown(ch, def, now)
	var firsts: Variant = host.ws.world.get(FIRSTS_KEY)
	if not (firsts is Dictionary):
		firsts = {}
		host.ws.world[FIRSTS_KEY] = firsts
	if not (firsts as Dictionary).has(qid):
		firsts[qid] = str(ch.name)   # 全服第一位（RumorSystem 輪詢它發 rumors.first）
		var fo: Variant = host.ws.world.get(FIRST_OUTCOMES_KEY)
		if not (fo is Dictionary):
			fo = {}
			host.ws.world[FIRST_OUTCOMES_KEY] = fo
		fo[qid] = outcome   # 審查修正：傳聞要說得出結局（例：雲兒嫁給了誰）
	var oc: Dictionary = def.get("outcomes", {}).get(outcome, {}) if def.get("outcomes", {}).get(outcome) is Dictionary else {}
	var label := str(oc.get("label", ""))
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_QUEST_COMPLETE, { "quest_name": str(def.get("name", qid)), "outcome_label": label })
	var params := { "name": str(ch.name), "quest_name": str(def.get("name", qid)), "outcome_label": label,
		"room_name": host.room_name(s.room_id()) }
	_give_rewards(s, oc.get("rewards", {}), true, params)
	# 任務列的 rumors.first／each 由 RumorSystem 輪詢 ws.world.quest_firsts 與各角色的 done 次數發出（WP-AMBIENT，§5.1 #2），
	# 這裡不再重複發；結局獎勵的 rumor 與動作 rumor 照上面直接交給 RumorSystem。
	s.sheet_dirty = true
	s.view_dirty = true

func _set_cooldown(ch, def: Dictionary, now: float) -> void:
	var days := float(def.get("repeat", {}).get("cooldown_days", 0.0))
	if days > 0.0:
		_cd(ch)[str(def.get("id", ""))] = now + days * host.day_s()

## 任務失敗：移除、收回 give_items、done.failed += 1、冷卻；可再接
func _fail(s: Session, qid: String, reason_key: String) -> void:
	var ch = s.character
	if not _active(ch).has(qid):
		return
	var def := quest_row(qid)
	var st := _st(ch, qid)
	_active(ch).erase(qid)
	_take_back(s, def, st)
	_carry_paid(ch, qid, st)
	var d := QuestState.done_entry(ch.quests, qid)
	if d.is_empty():
		d = { "n": 0, "outcome": "", "world_s": 0.0, "failed": 0 }
	d["failed"] = int(d["failed"]) + 1
	_done(ch)[qid] = d
	_set_cooldown(ch, def, host.now_s())
	if str(s.dialogue.get("quest", "")) == qid:
		_close_dialogue(s, true)
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_QUEST_FAIL, {
		"quest_name": str(def.get("name", qid)), "reason": reason_key, "reason_text": _template_text(reason_key) })
	s.sheet_dirty = true
	s.view_dirty = true

func _template_text(key: String) -> String:
	if key == "":
		return ""
	var row: Variant = host.tables.get("text_templates", {}).get(key, {})
	if not (row is Dictionary):
		return ""
	return str(row.get("self", row.get("text", "")))

## 放棄／失敗：收回這次任務交給玩家、還沒被任務收回的物品（st.given）；舊存檔沒有 given → 照舊只收 give_items
func _take_back(s: Session, def: Dictionary, st: Dictionary = {}) -> void:
	var given: Variant = st.get(GIVEN_KEY, null)
	if given is Dictionary:
		var ids: Array = (given as Dictionary).keys()
		ids.sort()
		for it in ids:
			_unnote_give(st, str(it), _take(s, str(it), int(given[it])))
		return
	for gi in def.get("give_items", []):
		if gi is Dictionary:
			_take(s, str(gi.get("id", "")), int(gi.get("n", 1)))

func abandon(s: Session, qid: String) -> Dictionary:
	var ch = s.character
	if not _active(ch).has(qid):
		return GameHost.fail("quest_not_active")
	var def := quest_row(qid)
	if def.get("abandon", true) == false:
		return GameHost.fail(Protocol.R_QUEST_NOT_NOW)   # STORY_PLAN 缺漏：不能放棄的任務沒有專用原因碼
	var st := _st(ch, qid)
	_active(ch).erase(qid)
	_take_back(s, def, st)
	_carry_paid(ch, qid, st)
	if str(s.dialogue.get("quest", "")) == qid:
		_close_dialogue(s, true)
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_QUEST_ABANDON, { "quest_name": str(def.get("name", qid)) })
	s.view_dirty = true
	return GameHost.ok()

# ---------------------------------------------------------------- 房間動作
## [{ act, label }]：進行中、目前階段、在這個房間、時辰與條件成立、沒用掉的房間動作
func room_actions(ch, room_id: String) -> Array:
	var out: Array = []
	if ch == null:
		return out
	var sc := _shichen()
	var act := _active(ch).keys()
	act.sort()
	for qid in act:
		var st := _st(ch, qid)
		for a in _stage(quest_row(qid), st).get("room_actions", []):
			if not (a is Dictionary) or str(a.get("room", "")) != room_id:
				continue
			if not _hours_ok(a.get("hours", []), sc) or _req_ch(a.get("requires", []), ch) != "":
				continue
			if a.get("repeat", true) == false and bool(st.get("vars", {}).get(ACT_USED_PREFIX + str(a.get("id", "")), false)):
				continue
			out.append({ "act": "%s:%s" % [qid, str(a.get("id", ""))], "label": str(a.get("label", "")) })
	return out

## story_act：act = "<qid>:<action id>"
func room_action(s: Session, act: String) -> Dictionary:
	var i := act.find(":")
	if i <= 0:
		return GameHost.fail(Protocol.R_ACT_UNKNOWN)
	var qid := act.substr(0, i)
	var aid := act.substr(i + 1)
	var st := _st(s.character, qid)
	if st.is_empty():
		return GameHost.fail(Protocol.R_ACT_UNKNOWN)
	var a: Dictionary = {}
	for x in _stage(quest_row(qid), st).get("room_actions", []):
		if x is Dictionary and str(x.get("id", "")) == aid:
			a = x
	if a.is_empty():
		return GameHost.fail(Protocol.R_ACT_UNKNOWN)
	if str(a.get("room", "")) != s.room_id():
		return GameHost.fail(Protocol.R_ACT_NOT_HERE)
	if a.get("repeat", true) == false and bool(st["vars"].get(ACT_USED_PREFIX + aid, false)):
		return GameHost.fail(Protocol.R_ACT_UNKNOWN)
	if not _hours_ok(a.get("hours", []), _shichen()):
		return GameHost.fail(Protocol.R_QUEST_NOT_NOW)
	if float(st["vars"].get(ACT_WAIT_PREFIX + aid, 0.0)) > host.now_s():
		return GameHost.fail(Protocol.R_QUEST_NOT_NOW)
	var req := _req(a.get("requires", []), s)
	if req != "":
		return GameHost.fail(req)
	var why := _precheck(s, qid, a.get("do", []))
	if why != "":
		return GameHost.fail(why)
	_begin()
	drop_dialogue(s)
	if a.get("repeat", true) == false:
		st["vars"][ACT_USED_PREFIX + aid] = true
	_cur_act = aid
	_run_actions(s, qid, "", a.get("do", []))
	_cur_act = ""
	_settle_all(s)
	_end(s)
	s.view_dirty = true
	return GameHost.ok()

func _start_fight(s: Session, qid: String, a: Dictionary) -> void:
	if s.battle_id != 0 or s.character == null:
		return
	drop_dialogue(s)
	var monsters: Array = []
	for m in a.get("monsters", []):
		monsters.append(str(m))
	var waves: Array = []
	for w in a.get("waves", []):
		if w is Array:
			var ww: Array = []
			for m in w:
				ww.append(str(m))
			waves.append(ww)
	var solo := bool(a.get("solo", false))
	var tag := { "quest": qid, "obj": str(a.get("obj", "")), "by": str(s.character.id), "solo": solo, "members": [] }
	if _cur_act != "" and float(a.get("retry_days", 0.0)) > 0.0:
		tag["act"] = _cur_act
		tag["retry_days"] = float(a.get("retry_days", 0.0))
	var opts := { "no_flee": bool(a.get("no_flee", false)), "pull_party": not solo, "waves": waves, "quest_tag": tag }
	var npc := str(a.get("npc", ""))
	if npc != "":
		host.tell(s, Protocol.CH_BATTLE, Protocol.E_FIGHT_START, { "npc_name": host.npc_name(npc) })
	if not (host.battles as Object).has_method("start_ex"):
		host.battles.start(s, monsters, "QUEST")
		return
	var bid := int(host.battles.start_ex(s, monsters, "QUEST", opts))
	# 開戰當下在場的玩家（中途加入的不計 FIGHT 目標，§4.11）
	var entry: Dictionary = host.battles.active.get(bid, {})
	if not entry.is_empty() and entry.get("opts") is Dictionary and entry["opts"].get("quest_tag") is Dictionary:
		entry["opts"]["quest_tag"]["members"] = (entry.get("char_ids", {}) as Dictionary).values().duplicate()

# ---------------------------------------------------------------- 自動推進（鉤子）
## 擊殺計數：kills = 此玩家計得到的怪物 id（BattleSystem 給本人最後一擊的；隊友的另由 on_battle_settled 補）
func on_kills(s: Session, kills: Array) -> void:
	_count_kills(s, kills, false)

func _count_kills(s: Session, kills: Array, party_only: bool) -> void:
	if s == null or s.character == null or kills.is_empty():
		return
	_begin()
	var ch = s.character
	var region := host.index.region_of(s.room_id())
	var act := _active(ch).keys()
	act.sort()
	for qid in act:
		var def := quest_row(qid)
		if party_only and def.get("party_credit", true) == false:
			continue
		var st := _st(ch, qid)
		for o in _stage(def, st).get("objectives", []):
			if not (o is Dictionary) or str(o.get("type", "")) != "KILL":
				continue
			var regs: Variant = o.get("regions", [])
			if regs is Array and not (regs as Array).is_empty() and not (regs as Array).has(region):
				continue
			var target := str(o.get("monster", ""))
			var hits := 0
			for k in kills:
				if str(k) == target:
					hits += 1
			if hits == 0:
				continue
			var oid := str(o.get("id", ""))
			var need := maxi(1, int(o.get("count", 1)))
			var before := int(st["objs"].get(oid, 0))
			if before >= need:
				continue
			var have := mini(need, before + hits)
			st["objs"][oid] = have
			_progress_event(s, qid, o, have, need)
			s.sheet_dirty = true
		_settle(s, qid)
	_end(s)

## 戰鬥結算（BattleSystem._settle_player，在 on_kills 之後）：summary 有 per（VICTORY／FLED／DEFEAT／ABORTED）、
## quest_tag（{ quest, obj, by, solo, members }）、party_kills（同一方其他玩家打倒的怪物 id）、died
func on_battle_settled(s: Session, summary: Dictionary) -> void:
	if s == null or s.character == null:
		return
	var ch = s.character
	var per := str(summary.get("per", summary.get("result", "")))
	_begin()
	if per == "VICTORY":
		var extra: Variant = summary.get("party_kills", [])
		if extra is Array and not (extra as Array).is_empty():
			_count_kills(s, extra, true)
	var tag: Variant = summary.get("quest_tag", {})
	if tag is Dictionary and not (tag as Dictionary).is_empty() and per != "ABORTED":
		var qid := str(tag.get("quest", ""))
		var oid := str(tag.get("obj", ""))
		var st := _st(ch, qid)
		if not st.is_empty() and oid != "":
			var def := quest_row(qid)
			var mine := str(tag.get("by", "")) == str(ch.id)
			var members: Array = tag.get("members", []) if tag.get("members") is Array else []
			var allowed: bool = mine or (def.get("party_credit", true) != false and not bool(tag.get("solo", false)) \
				and members.has(str(ch.id)))
			var o := _current_objective(ch, qid, oid)
			if allowed and str(o.get("type", "")) == "FIGHT" and int(st["objs"].get(oid, 0)) < 1 \
					and win_ok(str(o.get("win", "WIN")), per):
				st["objs"][oid] = 1
				_progress_event(s, qid, o, 1, 1)
				s.sheet_dirty = true
			elif str(tag.get("act", "")) != "" and per != "VICTORY" and int(st["objs"].get(oid, 0)) < 1 and mine:
				# 逃走或戰敗：這個房間動作要等 retry_days 個遊戲日（2001-11-03「逃跑要再等一天」）
				st["vars"][ACT_WAIT_PREFIX + str(tag["act"])] = host.now_s() + float(tag.get("retry_days", 1.0)) * float(host.day_s())
				host.tell(s, Protocol.CH_SYSTEM, "quest_retry_tomorrow", { "quest_name": str(def.get("name", qid)) })
			_settle(s, qid)
	# 護送中倒下：護送對象走散（ESCORT 目標要重新帶人；不讓任務失敗）
	if bool(summary.get("died", false)):
		drop_escorts(s)
	_end(s)

## 護送對象走散（倒下、被押進監獄、被瞬移走）：ESCORT 目標要回給任務的 NPC 重新領（_escort_restart），任務不失敗。
## 有走散的回 true（送 fail_escort_lost）。M3b 審查 3：坐牢、出獄、門派瞬移也要叫這個（以前鏢車會跟著人進出監獄）
func drop_escorts(s: Session) -> bool:
	if s == null or s.character == null:
		return false
	var lost := false
	for qid in _active(s.character).keys():
		var st2 := _st(s.character, qid)
		if str(st2.get("escort", "")) != "":
			st2["escort"] = ""
			lost = true
	if lost:
		host.tell(s, Protocol.CH_SYSTEM, "fail_" + Protocol.R_ESCORT_LOST, {})
		_escort_changed(s)
	return lost

## FIGHT 目標的 win：WIN（打贏）／WIN_OR_FLEE（打贏或逃走）／ANY（任何結果，含戰敗）
static func win_ok(win: String, per: String) -> bool:
	match win:
		"ANY":
			return per in ["VICTORY", "FLED", "DEFEAT", "ALL_FLED"]
		"WIN_OR_FLEE":
			return per in ["VICTORY", "FLED", "ALL_FLED"]
	return per == "VICTORY"

## 進入房間（走路、搭車、引路、重生）：REACH、ESCORT
func on_reach(s: Session) -> void:
	if s == null or s.character == null:
		return
	_begin()
	_settle_all(s)
	_end(s)

## 物品增減：COLLECT（巢狀處理中先記下，最外層結束再算）
func on_items(s: Session) -> void:
	if s == null or s.character == null:
		return
	if _depth > 0:
		_recheck[s.peer_id] = s
		return
	_begin()
	_settle_all(s)
	_end(s)

## 商店買成功（NpcSystem.buy）：BUY 目標只算本階段開始後買的
func on_buy(s: Session, npc_id: String, item_id: String, n: int) -> void:
	if s == null or s.character == null or n <= 0:
		return
	_begin()
	var ch = s.character
	var act := _active(ch).keys()
	act.sort()
	for qid in act:
		var st := _st(ch, qid)
		for o in _stage(quest_row(qid), st).get("objectives", []):
			if not (o is Dictionary) or str(o.get("type", "")) != "BUY" or str(o.get("item", "")) != item_id:
				continue
			if str(o.get("npc", "")) != "" and str(o.get("npc", "")) != npc_id:
				continue
			var oid := str(o.get("id", ""))
			var need := maxi(1, int(o.get("count", 1)))
			var have := mini(need, int(st["objs"].get(oid, 0)) + n)
			st["objs"][oid] = have
			_progress_event(s, qid, o, have, need)
			s.sheet_dirty = true
		_settle(s, qid)
	_end(s)

## 換時辰（GameHost）：WAIT、STATE；appear 可能變了 → 重送房間視圖
func on_clock(s: Session) -> void:
	if s == null or s.character == null:
		return
	_begin()
	_settle_all(s)
	_end(s)
	s.view_dirty = true

## 角色表推送前（GameHost.push_sheet）：STATE 目標；同一角色每秒最多一次
func on_sheet(s: Session) -> void:
	if s == null or s.character == null or _depth > 0:
		return
	var now := Time.get_ticks_msec()
	if now - s.quest_state_check_ms < STATE_CHECK_MS:
		return
	s.quest_state_check_ms = now
	var ch = s.character
	var act := _active(ch).keys()
	act.sort()
	for qid in act:
		var has_state := false
		for o in _stage(quest_row(qid), _st(ch, qid)).get("objectives", []):
			if o is Dictionary and str(o.get("type", "")) == "STATE":
				has_state = true
		if has_state:
			_begin()
			_settle(s, qid)
			_end(s)

## 登入（GameHost.enter_character）：舊狀態遷移、階段不見了回到起點、護送照舊跟著
func on_login(s: Session) -> void:
	if s == null or s.character == null:
		return
	s.dialogue = {}
	QuestState.ensure(s.character.quests)
	_begin()
	_settle_all(s)
	_end(s)
	s.view_dirty = true
	s.sheet_dirty = true

## debug_set quest_stage：沒接就先接（不檢查條件），再跳到該階段
func debug_stage(s: Session, qid: String, stage: String) -> Dictionary:
	var def := quest_row(qid)
	if def.is_empty():
		return GameHost.fail("quest_unknown")
	if QuestDef.stage(def, stage).is_empty():
		return GameHost.fail("bad_value:value")
	_begin()
	if not _active(s.character).has(qid):
		_do_accept(s, qid)
	if _active(s.character).has(qid):
		_enter_stage(s, qid, stage)
		_settle(s, qid)
	_end(s)
	return GameHost.ok()

## debug_set quest_reset：清 active／done／cd
func debug_reset(s: Session, qid: String) -> void:
	var ch = s.character
	if str(s.dialogue.get("quest", "")) == qid:
		_close_dialogue(s, true)
	_active(ch).erase(qid)
	_done(ch).erase(qid)
	_cd(ch).erase(qid)
	s.sheet_dirty = true
	s.view_dirty = true

# ---------------------------------------------------------------- NPC 出現、護送
## appear（§4.6）：hours 與 requires 都成立才出現在這位玩家的 view、才能交談；沒有 appear 一律出現
func npc_visible(ch, npc_id: String) -> bool:
	var ap: Variant = host.npc_row(npc_id).get("appear")
	if not (ap is Dictionary):
		return true
	if not _hours_ok(ap.get("hours", []), _shichen()):
		return false
	return ch == null or _req_ch(ap.get("requires", []), ch) == ""

## 這位玩家正在護送的 NPC id（依任務 id 排序、不重複）
func escort_npcs(ch) -> Array:
	var out: Array = []
	if ch == null:
		return out
	var act := _active(ch).keys()
	act.sort()
	for qid in act:
		var e := str(_st(ch, qid).get("escort", ""))
		if e != "" and not out.has(e) and not host.npc_row(e).is_empty():
			out.append(e)
	return out

func is_escorting(ch, npc_id: String) -> bool:
	return escort_npcs(ch).has(npc_id)

# ---------------------------------------------------------------- 巢狀處理
func _begin() -> void:
	_depth += 1

func _end(s: Session) -> void:
	_depth = maxi(0, _depth - 1)
	if _depth > 0 or _recheck.is_empty():
		return
	var pending := _recheck.values()
	_recheck.clear()
	for o in pending:
		if o != null and o.character != null:
			_depth += 1
			_settle_all(o)
			_depth -= 1
	if not _recheck.is_empty() and _depth == 0:
		_recheck.clear()   # 一輪就好，避免物品來回觸發
