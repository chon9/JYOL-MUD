class_name ArtsSystem
extends RefCounted
## M3d 門派武功鏈的主機端（M3D_PLAN §4；WP-ARTS）。GameHost 依 M3D_SYSTEMS 以路徑 load()（"arts"）；
## 呼叫點一律經 host.m2_call（本系統為 null 時略過）。
## - 星宿 煉毒（§4.4）：intent liandu，或背包裡小木鼎的「使用」（IntentsItem.use_item 的 WP-ARTS 鉤子 → on_use_item）。
## - 血刀 恐嚇（§4.7）：intent intimidate { npc }；血池比武（三階 FIGHT，on_battle_settled 給威嚇熟練）。
## - 全真殺古墓弟子（§4.9）：SectSystem 的 WP-ARTS 區塊呼叫 gumu_kill（殺氣加倍、計數、門規再觸發）。
## - 血魔刀法 悟刀訣（§4.8 步驟 4）：帶著刀訣在血刀門口累計停留 2 個時辰（世界時間；離開就暫停）→ 旗標 xd_xuemo_walked，
##   任務 q_ar_xd_xuemo 的 STATE 目標看到旗標就結束（learn、收回刀訣由任務做）。
## 數字全部在 ArtsRules（純邏輯）。

var host: GameHost
## char_id -> 上次記下的世界時間（在血刀門口、帶著刀訣、任務在悟刀階段）
var _walk_at: Dictionary = {}

func _init(p_host: GameHost) -> void:
	host = p_host

func _day() -> int:
	return int(host.clock()["day"])

func _sects():
	return host.get("sects")

# ======================================================================== 煉毒（§4.4）

## 小木鼎的「使用」＝煉毒；其他物品回 {}（交還給 IntentsItem 照常處理）
func on_use_item(s: Session, uid: String) -> Dictionary:
	if s == null or s.character == null or uid == "":
		return {}
	for it in s.character.inventory.items:
		if str(it.get("uid", "")) == uid:
			return liandu(s) if str(it.get("id", "")) == ArtsRules.MUDING else {}
	return {}

func liandu_reason(s: Session) -> String:
	var ch = s.character
	var why := ArtsRules.liandu_reason(str(ch.sect), int(ch.inventory.count(ArtsRules.MUDING)) > 0,
		int(ch.vitals.get("jing", 0)))
	if why == "" and ArtsRules.liandu_room(ch.counters, _day()) <= 0:
		return "liandu_daily"   # M3d 審查：每遊戲日上限（不扣精）
	return why

## 煉毒：扣精 15、基本毒術熟練 20 × 倍率（夜 ×1.5、星宿地區 ×1.5、中毒 ×2）；每遊戲日合計上限 LIANDU_DAILY_CAP
func liandu(s: Session) -> Dictionary:
	if s == null or s.character == null:
		return GameHost.fail("no_character")
	if _sects() != null and _sects().is_jailed(s):
		return GameHost.fail(Protocol.R_JAILED)   # 使用物品在牢裡放行（吃喝），煉毒不放行
	var why := liandu_reason(s)
	if why != "":
		return GameHost.fail(why)
	var ch = s.character
	var region := host.index.region_of(s.room_id())
	var mult := ArtsRules.liandu_mult(bool(host.clock()["night"]), region, ch.conditions.has(ArtsRules.POISON_CONDITION))
	var gain := ArtsRules.liandu_take(ch.counters, _day(), ArtsRules.liandu_gain(mult))
	ch.vitals["jing"] = int(ch.vitals.get("jing", 0)) - ArtsRules.LIANDU_JING
	var sk := ArtsRules.LIANDU_SKILL
	var res: Dictionary = ch.skills.add_prof(sk, gain, host.tables, host.skill_cap(ch, sk))
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_AR_LIANDU, { "gain": gain, "mult": mult })
	host.npcs.skill_up_event(s, sk, int(res.get("before", 0)), int(res.get("after", 0)))
	s.sheet_dirty = true
	return GameHost.ok({ "gain": gain, "mult": mult })

# ======================================================================== 恐嚇（§4.7）

## 有沒有進行中的任務目標落在這位 NPC 身上
func _quest_target(ch, npc_id: String) -> bool:
	var q = host.quests
	if q == null or not q.has_method("_npc_objectives"):
		return false
	var act: Variant = ch.quests.get("active", {})
	if not (act is Dictionary):
		return false
	for qid in act:
		if not (q._npc_objectives(ch, str(qid), npc_id) as Array).is_empty():
			return true
	return false

## 能不能恐嚇這位 NPC：回原因碼或 ""（門派 → 在不在 → 對象 → 今天恐嚇過 → 精 → 神）
func intimidate_reason(s: Session, npc_id: String) -> String:
	var ch = s.character
	if str(ch.sect) != ArtsRules.INTIMIDATE_SECT:
		return "intimidate_not_xd"
	var here := host.npc_here(s, npc_id)
	if here != "":
		return here
	var nsect: String = _sects().npc_sect(npc_id) if _sects() != null else ""
	if not ArtsRules.intimidate_target_ok(host.npc_row(npc_id), nsect, str(ch.sect), _quest_target(ch, npc_id)):
		return "intimidate_bad_target"
	var e := ArtsRules.day_entry(ch.counters, ArtsRules.COUNTER_INTIMIDATE, _day())
	if npc_id in e.get("npcs", []):
		return "intimidate_daily"
	if int(ch.vitals.get("jing", 0)) < ArtsRules.INTIMIDATE_JING:
		return "not_enough_jing"
	if int(ch.vitals.get("shen", 0)) < ArtsRules.INTIMIDATE_SHEN:
		return "not_enough_shen"
	return ""

## 恐嚇：扣精 20、神 20、善惡 −10、威嚇熟練 +20（當日恐嚇＋血池合計上限 200）；NPC 回一句害怕的話
func intimidate(s: Session, npc_id: String) -> Dictionary:
	if s == null or s.character == null:
		return GameHost.fail("no_character")
	var why := intimidate_reason(s, npc_id)
	if why != "":
		return GameHost.fail(why)
	var ch = s.character
	var day := _day()
	var e := ArtsRules.day_entry(ch.counters, ArtsRules.COUNTER_INTIMIDATE, day)
	(e["npcs"] as Array).append(npc_id)
	ch.vitals["jing"] = int(ch.vitals.get("jing", 0)) - ArtsRules.INTIMIDATE_JING
	ch.vitals["shen"] = int(ch.vitals.get("shen", 0)) - ArtsRules.INTIMIDATE_SHEN
	var dm: int = ch.add_morality(ArtsRules.INTIMIDATE_MORALITY)
	var gain := _weihe_gain(s, ArtsRules.INTIMIDATE_GAIN, day)
	var line := (e["npcs"] as Array).size() % ArtsRules.INTIMIDATE_LINES + 1
	var npc_name := host.npc_name(npc_id)
	host.tell(s, Protocol.CH_SYSTEM, "ar_intimidate_%d" % line, { "npc_name": npc_name })
	host.tell(s, Protocol.CH_SYSTEM, Protocol.E_AR_INTIMIDATED, { "npc_name": npc_name, "gain": gain })
	if dm != 0:
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_MORALITY_CHANGE, { "delta": dm, "value": int(ch.morality) })
		host.regions.mark_room_dirty(s.room_id())   # 名字顏色可能變了
	s.sheet_dirty = true
	if _sects() != null:
		_sects().check_state(s, "TICK")   # 善惡變了 → 門規
	return GameHost.ok({ "gain": gain })

## 威嚇熟練（受每日上限截斷）；回實際加的熟練
func _weihe_gain(s: Session, want: int, day: int) -> int:
	var ch = s.character
	var got := ArtsRules.weihe_take(ch.counters, day, want)
	if got <= 0:
		return 0
	var sk := ArtsRules.WEIHE
	var res: Dictionary = ch.skills.add_prof(sk, got, host.tables, host.skill_cap(ch, sk))
	host.npcs.skill_up_event(s, sk, int(res.get("before", 0)), int(res.get("after", 0)))
	return got

# ======================================================================== 戰鬥結算（血池）

## GameHost.m3d_battle_settled → 這裡（BattleSystem._settle_player 結尾）
func on_battle_settled(s: Session, ch, summary: Dictionary) -> void:
	if s == null or ch == null or s.character != ch:
		return
	if str(summary.get("kind", "")) != "FIGHT" or str(summary.get("result", "")) != "VICTORY":
		return
	var tier := 0
	for k in summary.get("kills", []):
		tier = maxi(tier, ArtsRules.xuechi_tier(str(k)))
	if tier <= 0 or str(ch.sect) != ArtsRules.INTIMIDATE_SECT:
		return
	if host.rules is Dictionary and host.rules.get("later_events", true) == false:
		return   # M3d 審查第三輪：血池是 2003 的內容，classic_strict（規則 later_events 關）沒有
	var day := _day()
	var e := ArtsRules.day_entry(ch.counters, ArtsRules.COUNTER_XUECHI, day, "")
	var n: Dictionary = e.get_or_add("n", {})
	var key := str(tier)
	if int(n.get(key, 0)) >= ArtsRules.XUECHI_DAILY:
		host.tell(s, Protocol.CH_SYSTEM, "ar_xuechi_daily", { "npc_name": host.npc_name(str(ArtsRules.XUECHI[tier]["npc"])) })
		return
	n[key] = int(n.get(key, 0)) + 1
	var gain := _weihe_gain(s, int(ArtsRules.XUECHI[tier]["gain"]), day)
	host.tell(s, Protocol.CH_SYSTEM, "ar_xuechi_won", { "npc_name": host.npc_name(str(ArtsRules.XUECHI[tier]["npc"])),
		"gain": gain, "left": ArtsRules.XUECHI_DAILY - int(n[key]), "count": ArtsRules.XUECHI_DAILY - int(n[key]) })
	s.sheet_dirty = true

# ======================================================================== 全真殺古墓弟子（§4.9）

## SectSystem 的 WP-ARTS 區塊呼叫：killer 是全真弟子、死者是古墓（玩家、古墓 NPC 或 sect: gumu 的怪）。
## base：這次擊殺原本給的殺氣（怪物列 killing_intent_on_kill、PK 的 MoralityPk.KILL_KILLING_INTENT…）；n：殺了幾個
func gumu_kill(s: Session, ch, base: int, n := 1) -> void:
	if ch == null or str(ch.sect) != ArtsRules.QZ_SECT or n <= 0:
		return
	var extra := ArtsRules.gumu_extra(base) * n
	var dk: int = ch.add_killing_intent(extra)
	ch.counters[ArtsRules.COUNTER_QZ_GUMU] = int(ch.counters.get(ArtsRules.COUNTER_QZ_GUMU, 0)) + n
	# 坐牢後計數不歸零：每多殺一個都讓門規重新觸發一次（STATE 門規只在「成立 → 不成立」時觸發）【設計提案】
	var br: Variant = ch.sect_record.get("breached", {})
	if br is Dictionary:
		(br as Dictionary).erase(ArtsRules.QZ_GUMU_RULE)
	if s != null and s.character == ch:
		if dk != 0:
			host.tell(s, Protocol.CH_SYSTEM, Protocol.E_KILLING_INTENT_CHANGE, { "delta": dk, "value": int(ch.killing_intent) })
		host.tell(s, Protocol.CH_SYSTEM, "ar_qz_gumu_kill", { "n": int(ch.counters[ArtsRules.COUNTER_QZ_GUMU]) })
		s.sheet_dirty = true

# ======================================================================== 血魔刀法 悟刀訣（§4.8 步驟 4）

func on_enter_room(s: Session, _from: String, _to: String) -> void:
	_walk_update(s)

func tick(_dt: float) -> void:
	if _walk_at.is_empty() and not _any_walker():
		return
	for o in host.sessions():
		_walk_update(o)

func on_logout(s: Session) -> void:
	if s != null and s.character != null:
		_walk_at.erase(str(s.character.id))

## 有沒有在線角色正在悟刀階段（沒有就整個 tick 不做事）
func _any_walker() -> bool:
	for o in host.sessions():
		if o.character != null and _walk_stage(o.character):
			return true
	return false

func _walk_stage(ch) -> bool:
	return str(QuestState.active_entry(ch.quests, ArtsRules.XUEMO_QUEST).get("stage", "")) == ArtsRules.XUEMO_STAGE \
		and not bool(ch.flags.get(ArtsRules.XUEMO_FLAG, false))

func _walk_update(s: Session) -> void:
	if s == null or s.character == null:
		return
	var ch = s.character
	var cid := str(ch.id)
	var here := _walk_stage(ch) and s.room_id() == ArtsRules.XUEMO_ROOM and s.battle_id == 0 \
		and int(ch.inventory.count(ArtsRules.XUEMO_ITEM)) > 0
	if not here:
		_walk_at.erase(cid)
		return
	var now := host.now_s()
	if _walk_at.has(cid):
		ch.counters[ArtsRules.COUNTER_XUEMO_WALK] = float(ch.counters.get(ArtsRules.COUNTER_XUEMO_WALK, 0.0)) \
			+ maxf(0.0, now - float(_walk_at[cid]))
	_walk_at[cid] = now
	if float(ch.counters.get(ArtsRules.COUNTER_XUEMO_WALK, 0.0)) >= ArtsRules.xuemo_need_s(host.day_s()):
		ch.flags[ArtsRules.XUEMO_FLAG] = true
		_walk_at.erase(cid)
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_AR_XUEMO_ENLIGHTENED, {})
		s.sheet_dirty = true
