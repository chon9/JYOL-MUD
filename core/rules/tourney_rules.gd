class_name TourneyRules
extends RefCounted
## 門派比武與武林大會的純規則（M3D_PLAN §5.3；【後期版 2002・設計提案】R14）。純靜態：不碰主機，
## TourneySystem、Battle（DUEL 限時判定）、balance_sim 與單元測試共用。
##
## 研究：武林大會 2002-04、門派比武 2002-09；名聲照 2002 官方數字，稱號照晚期官方表；不發神兵（R14）。
## 單淘汰沒有 3／4 名、5–8 名分級 → 四強同 1200、八強同 300（合併的名次一律取較低的那一格；M3d 審查）【設計提案】。

const KIND_WULIN := "WULIN"
const SECT_PREFIX := "SECT:"
const MIN_ENTRANTS := 2                 # 至少 2 人才開打（不足 → 取消）
const REWARD_MIN_ENTRANTS := 4          # 報名 < 4 → 表演賽（照打，不發名聲與稱號；D4）
const REWARD_COOLDOWN_DAYS := 30        # 同一種比賽每 30 遊戲日最多發一次獎勵（D4）
## M3d 審查：遊戲日只要 2 小時，30 遊戲日＝開機 60 小時（原作是現實一個月一屆，約多 12 倍）→ 另加現實時間冷卻：
## 同一種比賽距上次發獎要滿 30 個現實日（系統時鐘；主機選項 tourney_reward_cooldown_real_days 可改）【設計提案：比照原作每月一屆】
const REWARD_COOLDOWN_REAL_DAYS := 30
const REAL_DAY_S := 86400.0
const DUEL_LIMIT_S := 600.0             # 一場 10 分鐘（戰鬥時間）
const CALL_INTERVAL_REAL_S := 30.0      # 點名間隔（真實秒）
const CALL_MAX := 3                     # 3 次不到判負
const HOST_SIGNUP_DEFAULT_S := 300
const HOST_SIGNUP_MIN_S := 30
const HOST_SIGNUP_MAX_S := 1800
const ARENA_ROOM := "xx_biwu"           # 西夏比武場擂臺（WP-ERRANDS Day-0 建；safe）
const REST_ROOM := "xx_biwu_rest"       # 比武場休息區（報名、點名）
const ARENA_ROOMS := [ARENA_ROOM, REST_ROOM]
const CLERK_NPC := "n_ev_tourney_clerk"
const TOKEN_ITEM := "i_ev_mengzhu_ling" # 盟主令牌：下一屆武林大會開打時收回
const WULIN_TITLE := "武林盟主"
const WULIN_TAG := "盟主"

## 武林大會名聲：名次 1–8（冠軍、亞軍、兩個四強、四個八強）。2002 官方 3000／2000／1500／1200／1000／800／500／300；
## 單淘汰分不出 3／4 名與 5–8 名 → 合併的名次取較低的那一格：四強 1200、八強 300（M3d 審查：原本往上取，八強多了 3 倍）【設計提案】
const WULIN_FAME := [3000, 2000, 1200, 1200, 300, 300, 300, 300]
const SECT_CHAMPION_FAME := 1000
const SECT_CHAMPION_LILIAN := 800

## 門派比武冠軍稱號（研究：晚期官方表）
const SECT_TITLES := {
	"hengshan": "恆山派掌門師姐", "quanzhen": "全真派天樞真人", "xingxiu": "星宿派大師兄", "emei": "峨嵋派峨嵋第一",
	"lingjiu": "靈鷲宮掌門師姐", "gaibang": "丐幫幫主", "shaolin": "少林派掌門師兄", "xuedao": "血刀門少祖",
	"huashan": "華山派武聖", "wudang": "武當派代理掌門", "gumu": "古墓派傳人",
}
## 全真 2–7 名（單淘汰不足 7 名就到實際名次為止）
const QZ_RANK_TITLES := ["天璇真人", "天璣真人", "天權真人", "玉衡真人", "開陽真人", "搖光真人"]

## 日曆（WorldClock：一個月 30 遊戲日）。武林大會：每月第 15 日午時開打，第 8 日起可報名。
const WULIN_DAY := 15
const WULIN_SHICHEN := 6                # 午
const WULIN_SIGNUP_DAY := 8
## 門派比武：每月第 1、2 日（研究：2002 晚期官方時程週六／週日），從上個月第 24 日起可報名
const SECT_SIGNUP_DAY := 24
## sect → [第幾日, 時辰 idx]（§5.3.7：古墓 午、靈鷲 未、血刀 申、丐幫 酉、星宿 戌 在第 1 日；少林 巳、武當 午、峨嵋 未、華山 申、恆山 酉、全真 戌 在第 2 日）
const SECT_SCHEDULE := {
	"gumu": [1, 6], "lingjiu": [1, 7], "xuedao": [1, 8], "gaibang": [1, 9], "xingxiu": [1, 10],
	"shaolin": [2, 5], "wudang": [2, 6], "emei": [2, 7], "huashan": [2, 8], "hengshan": [2, 9], "quanzhen": [2, 10],
}
## 2002 各派報名 NPC（本包只做一位報名員；src_note 用）
const SECT_CLERKS_2002 := "2002 各派由本派的掌門弟子在門派廣場受理報名；本包統一在西夏比武場休息區的報名員報名【設計提案】"

## ---------------------------------------------------------------- 報名條件（M3d 審查第 3 輪）
## 研究：武林大會「每位參賽者都要通過武林大會報名員的武功測驗」（2002；測驗內容沒有記載）；門派比武初賽條件（晚期官方）——
## 恆山 實戰 20 萬、善惡 200、門技 10、沒有 PK值；全真 20 萬、善惡 200、門技 30；少林 沒有 PK值；其他派 實戰 ≥ 1000
## （丐幫的「二袋以上」本作沒有對應的袋數規則 → 照其他派【待考證】）。
## 本作換算：2002 的「實戰 20 萬」照 R12 的尺度（2002 的 500 萬 → 本作 10 萬，÷50）→ 4000；
## 武林大會的「武功測驗」→ 實戰 ≥ 10,000 且沒有 PK值【設計提案】（全新角色不能靠放水比武拿 3000 名聲與稱號）。
const WULIN_ENTRY := { "xp": 10000, "no_pk": true }
const SECT_ENTRY_DEFAULT := { "xp": 1000 }
const SECT_ENTRY := {
	"hengshan": { "xp": 4000, "morality": 200, "sect_skill": 10, "no_pk": true },
	"quanzhen": { "xp": 4000, "morality": 200, "sect_skill": 30 },
	"shaolin": { "xp": 1000, "no_pk": true },
}

static func entry_req(kind: String) -> Dictionary:
	if kind == KIND_WULIN:
		return WULIN_ENTRY
	return SECT_ENTRY.get(sect_of(kind), SECT_ENTRY_DEFAULT)

## 報名（與開打、點名時重查）的條件。who = { sect, combat_xp, pk, morality, sect_skill }。
## 回 ""（可以）或原因碼：tourney_not_eligible（門派比武不是該派弟子）／tourney_need_xp／tourney_has_pk／
## tourney_need_morality／tourney_need_sect_skill
static func entry_reason(kind: String, who: Dictionary) -> String:
	if is_sect_kind(kind) and str(who.get("sect", "")) != sect_of(kind):
		return "tourney_not_eligible"
	var req := entry_req(kind)
	if int(who.get("combat_xp", 0)) < int(req.get("xp", 0)):
		return "tourney_need_xp"
	if bool(req.get("no_pk", false)) and int(who.get("pk", 0)) > 0:
		return "tourney_has_pk"
	if req.has("morality") and int(who.get("morality", 0)) < int(req["morality"]):
		return "tourney_need_morality"
	if int(who.get("sect_skill", 0)) < int(req.get("sect_skill", 0)):
		return "tourney_need_sect_skill"
	return ""

## 報名條件的說明文字（報名視窗用）
static func entry_text(kind: String) -> String:
	var req := entry_req(kind)
	var parts: Array = ["實戰 %d 以上" % int(req.get("xp", 0))]
	if req.has("morality"):
		parts.append("善惡 %d 以上" % int(req["morality"]))
	if req.has("sect_skill"):
		parts.append("門派技能 %d 級以上" % int(req["sect_skill"]))
	if bool(req.get("no_pk", false)):
		parts.append("沒有 PK值")
	return "、".join(PackedStringArray(parts))

static func is_sect_kind(kind: String) -> bool:
	return kind.begins_with(SECT_PREFIX) and kind.length() > SECT_PREFIX.length()

static func sect_of(kind: String) -> String:
	return kind.substr(SECT_PREFIX.length()) if is_sect_kind(kind) else ""

static func sect_kind(sect: String) -> String:
	return SECT_PREFIX + sect

static func valid_kind(kind: String) -> bool:
	return kind == KIND_WULIN or (is_sect_kind(kind) and SECT_SCHEDULE.has(sect_of(kind)))

## 比賽名稱（武林大會／少林派門派比武）
static func kind_name(kind: String, sect_names: Dictionary = {}) -> String:
	if kind == KIND_WULIN:
		return "武林大會"
	var nm := str(sect_names.get(sect_of(kind), sect_of(kind)))
	return ("%s比武" if nm.ends_with("門") else "%s門派比武") % nm   # 血刀門比武、少林門派比武

## 2 的次方（≥ n）
static func bracket_size(n: int) -> int:
	var p := 1
	while p < n:
		p <<= 1
	return p

## 單淘汰第一輪對戰表：[[a, b], ...]（共 size/2 場；"" ＝輪空）。entrants＝依報名先後的角色 id。
## 每場最多一個輪空（n > size/2 時一定成立）：先把每場的第一格填滿，剩下的人再填第二格。
## 上屆冠軍（仍有報名）放在下半區的種子位（第 size/4 場的第一格；只有一場時就是那一場）；其餘依 seed 洗牌（可重現）。
static func bracket(entrants: Array, champion_id: String, seed: int) -> Array:
	var ids: Array = []
	for e in entrants:
		var s := str(e)
		if s != "" and not ids.has(s):
			ids.append(s)
	if ids.size() < MIN_ENTRANTS:
		return []
	var size := bracket_size(ids.size())
	var n_matches := size / 2
	var others: Array = ids.duplicate()
	var champ := ""
	if champion_id != "" and others.has(champion_id):
		champ = champion_id
		others.erase(champion_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in range(others.size() - 1, 0, -1):   # Fisher–Yates（可重現）
		var j := rng.randi_range(0, i)
		var t: Variant = others[i]
		others[i] = others[j]
		others[j] = t
	var firsts: Array = []
	firsts.resize(n_matches)
	firsts.fill("")
	var seconds: Array = []
	seconds.resize(n_matches)
	seconds.fill("")
	var champ_slot := (n_matches / 2) if n_matches > 1 else 0
	if champ != "":
		firsts[champ_slot] = champ
	var k := 0
	for i in n_matches:
		if str(firsts[i]) != "":
			continue
		if k < others.size():
			firsts[i] = others[k]
			k += 1
	# 第二格：輪空集中在上屆冠軍以外的強勢位置不重要；從最後一場往前填，輪空落在前面的場次
	for i in range(n_matches - 1, -1, -1):
		if k < others.size():
			seconds[i] = others[k]
			k += 1
	var out: Array = []
	for i in n_matches:
		out.append([str(firsts[i]), str(seconds[i])])
	return out

## 下一輪：把上一輪每兩場的勝者配成一場（winners＝依場次的勝者 id，"" ＝兩人都判負）
static func next_round(winners: Array) -> Array:
	var out: Array = []
	var i := 0
	while i < winners.size():
		var a := str(winners[i])
		var b := str(winners[i + 1]) if i + 1 < winners.size() else ""
		out.append([a, b])
		i += 2
	return out

## 限時判定：0＝a 勝、1＝b 勝。總傷害 → 命中次數 → 目前氣／最大氣 → 先報名者（order 小）
static func judge(a: Dictionary, b: Dictionary) -> int:
	var da := int(a.get("dmg", 0))
	var db := int(b.get("dmg", 0))
	if da != db:
		return 0 if da > db else 1
	var ha := int(a.get("hits", 0))
	var hb := int(b.get("hits", 0))
	if ha != hb:
		return 0 if ha > hb else 1
	# 氣比例：交叉相乘比較（整數，不受浮點誤差影響）
	var ra := int(a.get("qi", 0)) * maxi(1, int(b.get("qi_max", 1)))
	var rb := int(b.get("qi", 0)) * maxi(1, int(a.get("qi_max", 1)))
	if ra != rb:
		return 0 if ra > rb else 1
	return 0 if int(a.get("order", 0)) <= int(b.get("order", 0)) else 1

## 名次：rounds＝[[{ a, b, winner }...], ...]（winner：勝者 id；"" ＝兩人都判負；輪空的場次 a 或 b 為 ""）。
## 回傳依名次排好的 [{ id, place }]：冠軍 1、亞軍 2、四強 3、八強 5、十六強 9…（同一輪輸的人同名次；
## 同名次依 order_of[id]（報名先後）排）。輪空晉級不算贏、被輪空的空位不算人。
static func places(rounds: Array, order_of: Dictionary = {}) -> Array:
	var out: Array = []
	if rounds.is_empty():
		return out
	var n_rounds := rounds.size()
	var final_round: Array = rounds[n_rounds - 1]
	var champion := ""
	if final_round.size() == 1 and final_round[0] is Dictionary:
		champion = str((final_round[0] as Dictionary).get("winner", ""))
	if champion != "":
		out.append({ "id": champion, "place": 1 })
	# 從決賽往前：第 r 輪（0 起算）的輸家名次 = 2^(n_rounds - 1 - r) + 1
	for r in range(n_rounds - 1, -1, -1):
		var place := (1 << (n_rounds - 1 - r)) + 1
		var losers: Array = []
		for m in rounds[r]:
			if not (m is Dictionary):
				continue
			var a := str(m.get("a", ""))
			var b := str(m.get("b", ""))
			var w := str(m.get("winner", ""))
			for x in [a, b]:
				if x != "" and x != w and not losers.has(x):
					losers.append(x)
		losers.sort_custom(func(x, y): return int(order_of.get(x, 0)) < int(order_of.get(y, 0)))
		for x in losers:
			out.append({ "id": str(x), "place": place })
	return out

## places() 的每一列 → 名次格（0 起）：名次 − 1 ＋ 同名次裡的第幾個（四強 3、3 → 格 2、3；八強 5×4 → 格 4–7）。
## lowest＝true：同名次的人都取這一組最低的那格（名聲用；照 WULIN_FAME「合併的名次取較低的那格」）。
## 沒有冠軍（決賽兩人都判負）時沒有人拿到格 0：兩位決賽者同為第 2 名 → 名聲取格 2（M3d 審查第三輪：原本照名單位置，亞軍拿走冠軍的 3000）
static func rank_slots(places_rows: Array, lowest := false) -> Array:
	var n_of := {}
	for row in places_rows:
		var place := int(row.get("place", 0)) if row is Dictionary else 0
		n_of[place] = int(n_of.get(place, 0)) + 1
	var out: Array = []
	var seen := {}
	for row in places_rows:
		var place := int(row.get("place", 0)) if row is Dictionary else 0
		var k := int(seen.get(place, 0))
		seen[place] = k + 1
		if place <= 0:
			out.append(999)
		elif lowest:
			out.append(place - 1 + int(n_of[place]) - 1)
		else:
			out.append(place - 1 + k)
	return out

## 武林大會名次 → 名聲（第 1–8 個；之後 0）
static func wulin_fame(rank_index: int) -> int:
	return int(WULIN_FAME[rank_index]) if rank_index >= 0 and rank_index < WULIN_FAME.size() else 0

## 稱號：WULIN 冠軍「武林盟主」；門派冠軍查 SECT_TITLES；全真第 2–7 個依序天璇…搖光
static func title_for(kind: String, rank_index: int) -> String:
	if kind == KIND_WULIN:
		return WULIN_TITLE if rank_index == 0 else ""
	var sect := sect_of(kind)
	if rank_index == 0:
		return str(SECT_TITLES.get(sect, ""))
	if sect == "quanzhen" and rank_index >= 1 and rank_index <= QZ_RANK_TITLES.size():
		return str(QZ_RANK_TITLES[rank_index - 1])
	return ""

## 有沒有發獎：報名 ≥ 4 人，且這種比賽距上次發獎 ≥ 30 遊戲日（last_day < 0 ＝從沒發過），
## 而且距上次發獎 ≥ cooldown_real_s 現實秒（last_unix < 0 ＝舊存檔沒記，只看遊戲日；M3d 審查）
static func rewarded(n_entrants: int, today: int, last_day: int, now_unix := -1.0, last_unix := -1.0,
		cooldown_real_s := REWARD_COOLDOWN_REAL_DAYS * REAL_DAY_S) -> bool:
	if n_entrants < REWARD_MIN_ENTRANTS:
		return false
	if last_day >= 0 and today - last_day < REWARD_COOLDOWN_DAYS:
		return false
	if last_unix >= 0.0 and now_unix >= 0.0 and now_unix - last_unix < cooldown_real_s:
		return false
	return true

# ---------------------------------------------------------------- 日曆
## 一個月 30 日（WorldClock）；day＝WorldClock 的絕對第幾天（1 起）
static func day_of_month(day: int) -> int:
	return ((maxi(day, 1) - 1) % 30) + 1

static func month_index(day: int) -> int:
	return int(floor((maxi(day, 1) - 1) / 30.0))

## 某一天某時辰起點的世界秒（WorldClock.clock 的反函數）
static func world_s_at(day: int, shichen_idx: int, day_s: float) -> float:
	var day_len := maxf(day_s, 12.0)
	var sc := day_len / 12.0
	return float(maxi(day, 1) - 1) * day_len + float(shichen_idx) * sc - float(WorldClock.START_SHICHEN) * sc

## 現在（day、shichen）可以報名的日曆場次：[{ kind, start_day, shichen, cycle }]。
## 武林大會：本月第 8 日起到第 15 日開打前；門派比武：本月第 24 日起（下個月第 1／2 日開打）、或本月第 1／2 日開打前。
## cycle＝開打那個月的月序（同一場只開一次）
static func calendar_open(day: int, shichen_idx: int, sects: Array) -> Array:
	var out: Array = []
	var dom := day_of_month(day)
	var m := month_index(day)
	if dom >= WULIN_SIGNUP_DAY and (dom < WULIN_DAY or (dom == WULIN_DAY and shichen_idx < WULIN_SHICHEN)):
		out.append({ "kind": KIND_WULIN, "start_day": m * 30 + WULIN_DAY, "shichen": WULIN_SHICHEN, "cycle": m })
	for sect in sects:
		var sch: Variant = SECT_SCHEDULE.get(str(sect), null)
		if not (sch is Array):
			continue
		var sd := int(sch[0])
		var sh := int(sch[1])
		var cyc := -1
		if dom >= SECT_SIGNUP_DAY:
			cyc = m + 1
		elif dom < sd or (dom == sd and shichen_idx < sh):
			cyc = m
		if cyc >= 0:
			out.append({ "kind": sect_kind(str(sect)), "start_day": cyc * 30 + sd, "shichen": sh, "cycle": cyc })
	return out

## 下一場的說明（報名員對白、tourney_info 用）：[{ kind, start_day, shichen }]，依開打先後
static func upcoming(day: int, sects: Array) -> Array:
	var out: Array = []
	var m := month_index(day)
	var dom := day_of_month(day)
	var wm := m if dom <= WULIN_DAY else m + 1
	out.append({ "kind": KIND_WULIN, "start_day": wm * 30 + WULIN_DAY, "shichen": WULIN_SHICHEN })
	for sect in sects:
		var sch: Variant = SECT_SCHEDULE.get(str(sect), null)
		if not (sch is Array):
			continue
		var sm := m if dom <= int(sch[0]) else m + 1
		out.append({ "kind": sect_kind(str(sect)), "start_day": sm * 30 + int(sch[0]), "shichen": int(sch[1]) })
	out.sort_custom(func(a, b):
		if int(a.start_day) != int(b.start_day):
			return int(a.start_day) < int(b.start_day)
		return int(a.shichen) < int(b.shichen))
	return out
