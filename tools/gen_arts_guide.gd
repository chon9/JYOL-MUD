extends SceneTree
## 攻略附錄「全武功效果一覽」產生器：全部文字由資料（martial_arts / basic_skills / masters / sects / quests / npcs / status_effects）
## 與 SkillEffects（照公式寫的說明）、戰鬥常數（BattleCmds / BattleRules / BattleFormulas / BattleAoe）產生，不手寫數字。
## godot --headless --path . --script res://tools/gen_arts_guide.gd [-- --guide=docs/攻略.md] [--out=<path>] [--version=<版號>]
##   --guide=  直接把附錄寫進攻略：取代 <a id="app-arts"></a> 那一節（到下一個「## 」標題或檔尾）；沒有就接在檔尾。
##   --out=    另存一份附錄（沒給 --guide 時預設存到 DEFAULT_OUT）。
##   --version= 附錄開頭寫的版號（預設 project.godot 的 application/config/version）。
## 世界：新世界預設資料片 1.0A＋1.0B；只在 1.0B 才有的武功、師父標【1.0B】（整個門派是 1.0B 時只標在門派標題）。
## 怪物專用武功（monster_only）不列。每次執行印 COUNTS: 與 PROBLEM:（資料缺漏、畫不出來的條件）。

const DEFAULT_OUT := "K:/Project/JY-Mini-OL-Work/tmp/guide_arts/arts_appendix.md"
const ANCHOR := "<a id=\"app-arts\"></a>"
const ERAS_DEFAULT := ["1.0A", "1.0B"]
const CATEGORY_NAMES := {
	"FIST": "拳掌（空手）", "BLADE": "刀法", "SWORD": "劍法", "WHIP": "鞭法", "STAFF": "棍法", "SPEAR": "槍法", "STAB": "筆刺",
	"INNER": "內功心法", "LIGHTNESS": "輕功", "FORMATION": "陣法", "HIDDEN": "暗器", "MEDIC": "醫術", "POISON": "毒術",
}
const STRIKE_CATS := ["FIST", "BLADE", "SWORD", "WHIP", "STAFF", "SPEAR", "STAB"]
const CN_NUM := ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二", "十三", "十四", "十五", "十六"]
const LATER_SHORT := "（後期規則）"
const UNOBTAINABLE_LINK := "見[武功的解鎖記號](#ch4-5-13)"

var view: Dictionary = {}      # 1.0A＋1.0B
var view_a: Dictionary = {}    # 只有 1.0A（判斷【1.0B】）
var problems: PackedStringArray = []
var quest_learn: Dictionary = {}   # art_id -> PackedStringArray（「任務「X」給第 N 級」）
var flag_src: Dictionary = {}      # 旗標 -> PackedStringArray（設定它的時機：接下任務、做完某一步、完成任務、通過試煉…）
var blocked: Dictionary = {}       # art_id -> 學不到的原因（條件本版達不到）
var unobtainable: Dictionary = {}  # art_id -> true（完全拿不到）
var b_sect := false                # 目前輸出的門派整個是 1.0B（不再逐條標）
var dev_tag := RegEx.create_from_string("（M[0-9]+[a-z]?[^）]*）")
var cjk_space := RegEx.create_from_string("(?<=[\\x{3400}-\\x{9fff}]) (?=[\\x{3400}-\\x{9fff}])")

func _initialize() -> void:
	var out_path := ""
	var guide_path := ""
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.substr(6)
		elif a.begins_with("--guide="):
			guide_path = a.substr(8)
		elif a.begins_with("--version="):
			ver = a.substr(10)
	if out_path == "" and guide_path == "":
		out_path = DEFAULT_OUT
	var loader := DataLoader.new()
	loader.load_all("res://data")
	for e in loader.errors:
		problems.append("load: " + e)
	view = loader.activate(ERAS_DEFAULT)
	for e in loader.activate_errors:
		problems.append("activate: " + e)
	view_a = loader.activate(["1.0A"])
	_index_sources()
	_index_blocked()
	var md := _build(ver)
	var rc := 0
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		if not _write(out_path, md):
			rc = 1
	if guide_path != "" and not _insert_into_guide(guide_path, md):
		rc = 1
	var seen: Dictionary = {}
	for p in problems:
		if not seen.has(p):
			seen[p] = true
			print("PROBLEM: " + p)
	quit(rc)

func _write(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write " + path)
		return false
	f.store_string(text)
	f.close()
	print("wrote " + path)
	return true

## 取代攻略裡的附錄一節（從 ## <a id="app-arts"> 到下一個 ## 標題或檔尾）；沒有就接在檔尾（前面加分隔線）
func _insert_into_guide(path: String, md: String) -> bool:
	var p := path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path)
	if not FileAccess.file_exists(p):
		printerr("guide not found: " + p)
		return false
	var src := FileAccess.get_file_as_string(p)
	var lines := src.split("\n")
	var start := -1
	for i in lines.size():
		if lines[i].begins_with("## ") and lines[i].contains(ANCHOR):
			start = i
			break
	var out := ""
	if start < 0:
		out = src.rstrip("\n") + "\n\n---\n\n" + md
	else:
		var end := lines.size()
		for j in range(start + 1, lines.size()):
			if lines[j].begins_with("## "):
				end = j
				break
		var head := "\n".join(lines.slice(0, start))
		var tail := "\n".join(lines.slice(end)) if end < lines.size() else ""
		out = head + "\n" + md
		if tail != "":
			out = out.rstrip("\n") + "\n\n" + tail
	if not out.ends_with("\n"):
		out += "\n"
	return _write(p, out)

# ---------------------------------------------------------------- helpers

func _rows(t: String) -> Array:
	var out: Array = []
	var tb: Variant = view.get(t, {})
	if tb is Dictionary:
		for id in tb:
			out.append(tb[id])
	return out

func _cell(s: String) -> String:
	s = s.replace("|", "｜").replace("\n", " ").strip_edges()
	return s if s != "" else "—"

func _fmt_num(x: float) -> String:
	if is_equal_approx(x, roundf(x)):
		return str(int(roundf(x)))
	return ("%.3f" % x).rstrip("0").rstrip(".")

func _pct(x: float) -> String:
	return _fmt_num(x * 100.0) + "%"

func _is_1_0b_art(id: String) -> bool:
	return not (view_a.get("martial_arts", {}) as Dictionary).has(id)

func _mark_b(id: String) -> String:
	return "【1.0B】" if _is_1_0b_art(id) and not b_sect else ""

## 遊戲內說明文字的排版整理：後期規則的長括號換短稱（在附錄開頭定義一次）、相連括號合併、中文字之間多出的空格拿掉
func _polish(l: String) -> String:
	l = l.replace(SkillEffects.LATER, LATER_SHORT)
	l = l.replace("）（", "；")
	l = l.replace("＋等級/10%", "＋（等級÷10）%")
	l = l.replace("佈陣", "布陣")
	l = cjk_space.sub(l, "", true)
	return l

# ---------------------------------------------------------------- 取得途徑索引

func _add_src(d: Dictionary, key: String, text: String) -> void:
	var arr: PackedStringArray = d.get(key, PackedStringArray())   # PackedStringArray 是值型別：改完要寫回
	if not arr.has(text):
		arr.append(text)
	d[key] = arr

## 收集 v 裡設定的旗標：{"do":"flag"}、"flags": [...]。值 = 是否在含 {"do":"accept"} 的同一串動作裡（接任務時設）
func _collect_flags(v: Variant, accept_ctx: bool, out: Dictionary) -> void:
	if v is Dictionary:
		if str(v.get("do", "")) == "flag" and v.has("flag"):
			out[str(v["flag"])] = bool(out.get(str(v["flag"]), false)) or accept_ctx
		for k in v:
			var x: Variant = v[k]
			if str(k) == "flags" and x is Array:
				for f in x:
					if f is String:
						out[f] = bool(out.get(f, false)) or accept_ctx
			elif str(k) == "do" and x is Array:
				var acc := accept_ctx
				for it in x:
					if it is Dictionary and str(it.get("do", "")) == "accept":
						acc = true
				_collect_flags(x, acc, out)
			else:
				_collect_flags(x, accept_ctx, out)
	elif v is Array:
		for x in v:
			_collect_flags(x, accept_ctx, out)

## 收集 v 裡的 "learn": {art: 等級}
func _collect_learn(v: Variant, out: Dictionary) -> void:
	if v is Dictionary:
		for k in v:
			if str(k) == "learn" and v[k] is Dictionary:
				for art in v[k]:
					out[str(art)] = maxi(int(out.get(str(art), 0)), CharData.to_int(v[k][art], 1))
			else:
				_collect_learn(v[k], out)
	elif v is Array:
		for x in v:
			_collect_learn(x, out)

func _index_sources() -> void:
	for q in _rows("quests"):
		if not (q is Dictionary):
			continue
		var qn := str(q.get("name", q.get("id", "")))
		var outs: Variant = q.get("outcomes", {})
		var multi := outs is Dictionary and (outs as Dictionary).size() > 1
		var parts: Array = []   # [節點, 旗標說明, 習得說明前綴]
		if outs is Dictionary:
			for k in outs:
				var o: Variant = outs[k]
				var lab := str(o.get("label", k)) if o is Dictionary else str(k)
				if multi:
					parts.append([o, "以「%s」結局完成任務「%s」" % [lab, qn], "任務「%s」以「%s」結局" % [qn, lab]])
				else:
					parts.append([o, "完成任務「%s」" % qn, "任務「%s」" % qn])
		if q.get("rewards", null) is Dictionary:
			parts.append([q["rewards"], "完成任務「%s」" % qn, "任務「%s」" % qn])
		var stages: Variant = q.get("stages", [])
		if stages is Array:
			for s in stages:
				if s is Dictionary:
					parts.append([s, "任務「%s」做完「%s」這一步" % [qn, str(s.get("title", s.get("id", "")))], "任務「%s」途中" % qn])
		var steps: Variant = q.get("steps", [])
		if steps is Array and not (steps as Array).is_empty():
			parts.append([steps, "任務「%s」途中" % qn, "任務「%s」途中" % qn])
		for pt in parts:
			var fl: Dictionary = {}
			_collect_flags(pt[0], false, fl)
			for f in fl:
				_add_src(flag_src, f, pt[1])
			var ln: Dictionary = {}
			_collect_learn(pt[0], ln)
			for art in ln:
				_add_src(quest_learn, art, "%s給第 %d 級" % [pt[2], int(ln[art])])
		var dl: Dictionary = {}
		_collect_flags(q.get("dialogues", {}), false, dl)
		for f in dl:
			_add_src(flag_src, f, ("接下任務「%s」" % qn) if bool(dl[f]) else ("任務「%s」途中" % qn))
		var dln: Dictionary = {}
		_collect_learn(q.get("dialogues", {}), dln)
		for art in dln:
			_add_src(quest_learn, art, "任務「%s」途中給第 %d 級" % [qn, int(dln[art])])
	for npc in _rows("npcs"):
		if not (npc is Dictionary):
			continue
		var tr: Variant = npc.get("trial", null)
		if tr is Dictionary and str(tr.get("reward_flag", "")) != "":
			_add_src(flag_src, str(tr["reward_flag"]), "通過試煉「%s」" % str(tr.get("name", "")))
		var fl2: Dictionary = {}
		_collect_flags(npc, false, fl2)
		for f in fl2:
			_add_src(flag_src, f, "和%s對話" % str(npc.get("name", "")))
	# 其他表格（物品、事件…）裡的 {"do":"flag"}
	for t in view:
		if t in ["quests", "npcs", "martial_arts", "masters"]:
			continue
		var fl3: Dictionary = {}
		var tb: Variant = view[t]
		if tb is Dictionary:
			for id in tb:
				var r: Variant = tb[id]
				if r is Dictionary:
					var one: Dictionary = {}
					for k in r:
						if str(k) != "requires":
							_collect_flags(r[k], false, one)
					fl3.merge(one)
		for f in fl3:
			if not flag_src.has(f):
				_add_src(flag_src, f, "特定事件")
				problems.append("flag set outside quests/npcs (%s): %s" % [t, f])

## 頂層條件本版達不到的武功：quest_flag 沒人給、或要求一門本版學不到的武功
func _index_blocked() -> void:
	var changed := true
	while changed:
		changed = false
		for a in _rows("martial_arts"):
			if not (a is Dictionary) or bool(a.get("monster_only", false)):
				continue
			var id := str(a.get("id", ""))
			if blocked.has(id):
				continue
			for c in a.get("requires", []):
				if not (c is Dictionary):
					continue
				var why := ""
				var t := str(c.get("type", ""))
				if t == "quest_flag" and not flag_src.has(str(c.get("flag", ""))):
					why = "flag"
				elif t == "skill_min" and unobtainable.has(str(c.get("skill", ""))):
					why = "skill:" + str(c.get("skill", ""))
				if why != "":
					blocked[id] = why
					if not quest_learn.has(id):
						unobtainable[id] = true
					changed = true
					problems.append("blocked (%s): %s" % [id, why])
					break

# ---------------------------------------------------------------- 條件、師父、自修

## 條件文字；quest_flag 換成設定該旗標的時機（找得到時）
func _cond_text(c: Dictionary, owner: String) -> String:
	var t := str(c.get("type", ""))
	if t == "any_of":
		var groups := PackedStringArray()
		var simple := true
		for g in c.get("options", []):
			if g is Array:
				var sub := PackedStringArray()
				for x in g:
					if x is Dictionary:
						sub.append(_cond_text(x, owner))
				if sub.size() != 1:
					simple = false
				groups.append("、".join(sub))
		if simple:
			return "或".join(groups)
		return "（符合其中一項：" + "；或 ".join(groups) + "）"
	if t == "quest_flag":
		var fl := str(c.get("flag", ""))
		if flag_src.has(fl):
			return "或".join(flag_src[fl])
		problems.append("quest_flag never set (%s): %s" % [owner, fl])
		return "要有一個任務記號（本版沒有任務或試煉會給）"
	if t == "combo_ready":
		return "合體條件都符合，見下方"
	var d := Requirements.describe(c, view)
	if d == "特殊條件":
		problems.append("requires unrendered (%s): %s" % [owner, JSON.stringify(c)])
	if t == "skill_min" and unobtainable.has(str(c.get("skill", ""))):
		d += "（這門武功本版學不到）"
	return d

## 師父地點：所在地區＋房間
func _npc_place(npc: Dictionary) -> String:
	var reg := str(npc.get("region", ""))
	var rm := str(npc.get("room", ""))
	var parts := PackedStringArray()
	if reg != "":
		var rn := CharData.region_name(view, reg)
		if rn != reg:
			parts.append(rn)
		else:
			problems.append("region name missing: " + reg)
	if rm != "":
		var r := CharData.room(view, rm)
		if r.has("name"):
			parts.append(str(r["name"]))
		else:
			problems.append("room name missing: " + rm)
	return "・".join(parts)

## 一位師父的描述：名字（地點）教到 N 級，＋條件
func _master_text(m: Dictionary, from_level: int) -> String:
	var npc := CharData.row(view, "npcs", str(m.get("npc_id", "")))
	if npc.is_empty():
		problems.append("master npc missing: " + str(m.get("npc_id", "")))
		return ""
	var s := str(npc.get("name", ""))
	var place := _npc_place(npc)
	if place != "":
		s += "（%s）" % place
	var cap := CharData.to_int(m.get("cap", 0))
	s += ("從 %d 級教到 %d 級" % [from_level, cap]) if from_level > 0 else ("教到 %d 級" % cap)
	var mid := str(m.get("id", ""))
	var extra := PackedStringArray()
	var price := CharData.to_int(m.get("price", 0))
	if price > 0:
		extra.append("每次 %d 兩" % price)
	var tool := str(m.get("tool", ""))
	if tool != "":
		extra.append("要帶" + CharData.item_name(view, tool))
	var req: Variant = m.get("requires", [])
	if req is Array:
		for c in req:
			if c is Dictionary:
				extra.append(_cond_text(c, "master " + mid))
	if m.has("hours") and m["hours"] is Array:
		var hs := PackedStringArray()
		for h in m["hours"]:
			hs.append(str(h) + "時")
		extra.append("只在" + "、".join(hs))
	if not extra.is_empty():
		s += "（" + "；".join(extra) + "）"
	var in_a := (view_a.get("masters", {}) as Dictionary).has(mid)
	var npc_a := CharData.row(view_a, "npcs", str(m.get("npc_id", "")))
	var svc_a: Variant = npc_a.get("services", [])
	if not b_sect and (not in_a or npc_a.is_empty() or not (svc_a is Array and (svc_a as Array).has("TEACH"))):
		s += "【1.0B】"
	return s

## 真的教得到的師父：上限 ≤ 自修門檻（self_study_until）的師父永遠教不到（Learning.check_master：未滿門檻 need_self_study、滿了 cap_master）
func _masters_list(skill_id: String) -> PackedStringArray:
	var ms := CharData.masters_for_skill(view, skill_id)
	ms.sort_custom(func(a, b): return CharData.to_int(a.get("cap", 0)) < CharData.to_int(b.get("cap", 0)))
	var until := CharData.to_int(CharData.row(view, "martial_arts", skill_id).get("self_study_until", 0))
	var parts := PackedStringArray()
	for m in ms:
		if until > 0 and CharData.to_int(m.get("cap", 0)) <= until:
			problems.append("master can never teach (cap %d ≤ self_study_until %d): %s %s" % [CharData.to_int(m.get("cap", 0)), until, skill_id, str(m.get("npc_id", ""))])
			continue
		var t := _master_text(m, until)
		if t != "":
			parts.append(t)
	return parts

func _requires_text(a: Dictionary) -> String:
	var parts := PackedStringArray()
	var req: Variant = a.get("requires", [])
	if req is Array:
		for c in req:
			if c is Dictionary:
				parts.append(_cond_text(c, str(a.get("id", ""))))
	if parts.is_empty():
		var cb: Variant = a.get("combo", null)
		return "見下方合體條件" if cb is Dictionary and not (cb as Dictionary).is_empty() else "無"
	return "、".join(parts)

func _self_study_text(a: Dictionary) -> String:
	var id := str(a.get("id", ""))
	var until := CharData.to_int(a.get("self_study_until", 0))
	var cap := Learning.self_study_cap(null, id, view, {})
	var has_m := not _masters_list(id).is_empty()
	if until > 0 and not has_m and cap <= until:
		return "沒有師父；自己練，最高 %d 級" % cap
	var parts := PackedStringArray()
	if until > 0:
		var head := "任務給了之後" if quest_learn.has(id) else "學習條件符合就能自己起手"
		parts.append("%s，前 %d 級只能自己練%s" % [head, until, ("（師父從 %d 級起才教）" % until) if has_m else ""])
	if cap > 0:
		parts.append(("學會後" if until <= 0 else "") + "自己練最高 %d 級" % cap)
	else:
		parts.append("不能自己練")
	return "；".join(parts)

func _source_text(a: Dictionary) -> String:
	var id := str(a.get("id", ""))
	if unobtainable.has(id):
		return "本版還沒有取得途徑：學習條件裡有一項目前沒有任何任務或試煉能達成（%s）" % UNOBTAINABLE_LINK
	var parts := PackedStringArray()
	if not _masters_list(id).is_empty():
		parts.append("師父教（見下）")
	if quest_learn.has(id):
		parts.append("；".join(quest_learn[id]))
	if parts.is_empty():
		if CharData.to_int(a.get("self_study_until", 0)) > 0:
			parts.append("沒有師父教，自己練")
		else:
			problems.append("no source: " + id)
			parts.append("（資料中沒有取得方式）")
	var s := "；".join(parts)
	if blocked.has(id):
		s += "。但學習條件裡有一項本版達不到，任務給的等級之後沒辦法再往上升"
	return s

# ---------------------------------------------------------------- 效果

## SkillEffects 給的「類別通則」行（同類別、同對應基本武學的每門武功都一樣）→ 放在通則一節，個別武功不再重複
func _generic_lines(cat: String, base: String) -> PackedStringArray:
	return SkillEffects._art({ "category": cat, "base_skill": base }, view)

func _effect_lines(a: Dictionary) -> PackedStringArray:
	var id := str(a.get("id", ""))
	var ls := SkillEffects.lines(id, view)
	var cat := str(a.get("category", ""))
	var gen := _generic_lines(cat, str(a.get("base_skill", ""))) if (cat in STRIKE_CATS or cat == "INNER" or cat == "LIGHTNESS") else PackedStringArray()
	var desc := str(a.get("desc", ""))
	var out := PackedStringArray()
	for l in ls:
		if l.begins_with("招式：") or (desc != "" and l == desc) or gen.has(l):
			continue
		out.append(_polish(l))
	return out

## 武功列專屬欄位（inner / medic / poison / formation / combo / acupoint）的資料數字，以及門派加成
func _data_lines(a: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var cat := str(a.get("category", ""))
	var sid := str(a.get("sect_id", ""))
	var inr: Variant = a.get("inner", null)
	if inr is Dictionary:
		var hm := CharData.to_float(inr.get("heal_mult", 1.0), 1.0)
		var em := CharData.to_float(inr.get("expel_mult", 1.0), 1.0)
		var bits := PackedStringArray()
		if not is_equal_approx(hm, 1.0):
			bits.append("「內」療傷的回氣量 ×%s" % _fmt_num(hm))
		if not is_equal_approx(em, 1.0):
			bits.append("「內」逼毒解掉的毒等級 ×%s" % _fmt_num(em))
		if not bits.is_empty():
			out.append("、".join(bits) + "（要是你等級最高的內功心法才算）" + LATER_SHORT + "。")
	if cat == "INNER" and sid == "quanzhen":
		out.append("全真弟子用「內」療傷，回氣量再 ×%s（門派加成，用哪一門內功心法都算）%s。" % [_fmt_num(BattleCmds.QUANZHEN_HEAL_MULT), LATER_SHORT])
	var md: Variant = a.get("medic", null)
	if md is Dictionary:
		var mm := CharData.to_float(md.get("heal_mult", 1.0), 1.0)
		if not is_equal_approx(mm, 1.0):
			out.append("「醫」的治療量 ×%s。" % _fmt_num(mm))
	if cat == "MEDIC":
		out.append("「醫」一次只治一個人；招式的威力、範圍沒有作用（見[通則](#app-arts-rules)）。")
		out.append("恆山弟子用「醫」，治療量再 ×%s（門派加成）。" % _fmt_num(BattleCmds.HENGSHAN_MEDIC_MULT))
	var pz: Variant = a.get("poison", null)
	if pz is Dictionary:
		var st := str(pz.get("status", "poison"))
		var lb := CharData.to_int(pz.get("level_bonus", 0))
		var s := "「毒」毒中時對方得到「%s」" % _status_name(st)
		if lb != 0:
			s += "，毒力另加 %d" % lb
		out.append(s + "。")
	var f: Variant = a.get("formation", null)
	if f is Dictionary:
		var ab := CharData.to_float(f.get("atk_bonus", 0.0))
		var db := CharData.to_float(f.get("def_bonus", 0.0))
		var per := CharData.to_float(f.get("per_avg_level", 0.0))
		var dur := CharData.to_int(CharData.row(view, "status_effects", "formation").get("duration_actions", 0))
		var s2 := "布陣後每位成員攻擊 +%s、防禦 +%s，陣法等級每 1 級再各 +%s" % [_pct(ab), _pct(db), _pct(per)]
		if dur > 0:
			s2 += "；陣持續 %d 次行動" % dur
		out.append(s2 + "。")
		var fm := BattleCmds.first_move(a)
		if not fm.is_empty():
			out.append("布陣時布陣的人花內力 %d（第一招「%s」的耗內力；招式的威力、射程、範圍沒有作用）。" % [CharData.to_int(fm.get("cost_inner", 0)), str(fm.get("name", ""))])
	if bool(a.get("acupoint", false)):
		out.append("「穴」能點多遠，看這門武功已解鎖的最後一招的射程（花內力 %d）。" % BattleCmds.ACUPOINT_COST)
	var cb: Variant = a.get("combo", null)
	if cb is Dictionary and not (cb as Dictionary).is_empty():
		var ps := PackedStringArray()
		var pair: Variant = cb.get("pair", [])
		if pair is Array:
			for p in pair:
				if p is Dictionary:
					var g := str(p.get("gender", ""))
					var who := "男方" if g == "M" else ("女方" if g == "F" else "一方")
					var t := "%s要%s %d 級" % [who, SkillBook.skill_name(str(p.get("art", "")), view), CharData.to_int(p.get("min", 0))]
					var ssm := CharData.to_int(p.get("sect_skill_min", 0))
					if ssm > 0:
						t += "、自己門派的門派技能 %d 級" % ssm
					ps.append(t)
		var s3 := "合體條件：" + "；".join(ps)
		var moqi := CharData.to_int(cb.get("moqi_min", 0))
		if moqi > 0:
			s3 += "；兩人默契 %d 以上" % moqi
		out.append(s3 + "。")
	return out

func _status_name(sid: String) -> String:
	var r := CharData.row(view, "status_effects", sid)
	if r.is_empty():
		problems.append("status name missing: " + sid)
		return sid
	return str(r.get("name", sid))

func _status_cell(m: Dictionary) -> String:
	var st := str(m.get("status", ""))
	var ch := CharData.to_float(m.get("status_chance", 0.0))
	if st == "" or ch <= 0.0:
		return "—"
	var s := "%s（%s）" % [_status_name(st), _pct(ch)]
	if st in BattleCmds.PLAYER_MOVE_LATER_STATUSES:
		s += "＊"
	return s

func _aoe_name(aoe: String) -> String:
	var t := str(UiKeys.AOE_LABELS.get(aoe, ""))
	if t == "":
		problems.append("aoe label missing: " + aoe)
		return aoe
	return t

## 招式表：依指令實際用到的欄位分四種（武、毒、醫、暗）；陣法沒有表（見 _data_lines）
func _moves_table(a: Dictionary) -> String:
	var moves: Variant = a.get("moves", [])
	if not (moves is Array) or (moves as Array).is_empty():
		return ""
	var cat := str(a.get("category", ""))
	if cat == "FORMATION":
		return ""
	var head := ""
	if cat in STRIKE_CATS:
		head = "| 招式 | 解鎖等級 | 威力 | 射程 | 範圍 | 耗內力（10 成） | 耗精 | 附帶狀態 |\n|---|---|---|---|---|---|---|---|\n"
	elif cat == "POISON":
		head = "| 招式 | 解鎖等級 | 威力（毒中時的傷害） | 射程 | 耗內力 |\n|---|---|---|---|---|\n"
	elif cat == "MEDIC":
		head = "| 招式 | 解鎖等級 | 射程 | 耗內力 |\n|---|---|---|---|\n"
	elif cat == "HIDDEN":
		head = "| 招式 | 解鎖等級 | 威力 | 耗內力 | 附帶狀態 |\n|---|---|---|---|---|\n"
	else:
		problems.append("moves on category without table: %s %s" % [str(a.get("id", "")), cat])
		return ""
	var s := head
	for m in moves:
		if not (m is Dictionary):
			continue
		var nm := _cell(str(m.get("name", "")))
		var ul := CharData.to_int(m.get("unlock_level", 1))
		var pw := CharData.to_int(m.get("power", 0))
		var rng := CharData.to_int(m.get("range", 1))
		var rng_t := ("%d 格" % rng) if rng > 0 else "自身"
		var ci := CharData.to_int(m.get("cost_inner", 0))
		if cat in STRIKE_CATS:
			s += "| %s | %d | %d | %s | %s | %d | %d | %s |\n" % [nm, ul, pw, rng_t, _aoe_name(str(m.get("aoe", "SINGLE"))),
				BattleFormulas.inner_cost(m, 10), CharData.to_int(m.get("cost_jing", 0)), _status_cell(m)]
		elif cat == "POISON":
			s += "| %s | %d | %d | %s | %d |\n" % [nm, ul, pw, rng_t, ci]
		elif cat == "MEDIC":
			s += "| %s | %d | %s | %d |\n" % [nm, ul, rng_t, ci]
		else:
			s += "| %s | %d | %d | %d | %s |\n" % [nm, ul, pw, ci, _status_cell(m)]
	return s

func _art_block(a: Dictionary) -> String:
	var id := str(a.get("id", ""))
	var s := "#### %s%s\n\n" % [str(a.get("name", "")), _mark_b(id)]
	var cat := str(a.get("category", ""))
	var cat_t := str(CATEGORY_NAMES.get(cat, ""))
	if cat_t == "":
		problems.append("category name missing: %s %s" % [id, cat])
		cat_t = cat
	var base := str(a.get("base_skill", ""))
	var sn := CharData.sect_name(view, str(a.get("sect_id", "")))
	if a.get("combo", null) is Dictionary and sn != "":
		s += "- 門派：%s\n" % sn
	s += "- 類別：%s\n" % cat_t
	s += "- 對應基本武學：%s\n" % (SkillBook.skill_name(base, view) if base != "" else "無")
	s += "- 學習條件：%s\n" % _requires_text(a)
	s += "- 取得：%s\n" % _source_text(a)
	var tail := "（要先取得學習資格，本版拿不到）" if unobtainable.has(id) else ""
	for m in _masters_list(id):
		s += "  - %s%s\n" % [m, tail]
	s += "- 自修：%s\n" % _self_study_text(a)
	var passive := _effect_lines(a)
	passive.append_array(_polish_all(_data_lines(a)))
	s += "- **被動效果**：\n"
	if passive.is_empty():
		s += "  - 只有這一類武功的通則（見[各類武功通則](#app-arts-rules)）\n"
	for l in passive:
		s += "  - %s\n" % l
	var mt := _moves_table(a)
	s += "\n"
	if mt != "":
		s += mt + "\n"
	var desc := str(a.get("desc", ""))
	var clean := dev_tag.sub(desc, "", true).strip_edges()
	if clean != desc:
		problems.append("desc dev tag stripped: %s「%s」" % [id, desc])
	if clean != "":
		s += "> %s\n\n" % _polish(clean)
	return s

# ---------------------------------------------------------------- 通則

func _rules_section(arts: Array) -> String:
	var s := "### <a id=\"app-arts-rules\"></a>各類武功通則\n\n"
	s += "下面這些是同一類武功都一樣的效果，個別武功的「被動效果」只寫它自己多出來的部分。標「%s」的效果屬於後期規則：預設的「懷舊標準」規則組合開著，「懷舊嚴苛（2001）」規則組合沒有。\n\n" % LATER_SHORT
	# 出招武功：每個類別取最常見的對應基本武學
	var base_of: Dictionary = {}
	for a in arts:
		var cat := str(a.get("category", ""))
		var base := str(a.get("base_skill", ""))
		if not base_of.has(cat):
			base_of[cat] = {}
		base_of[cat][base] = int(base_of[cat].get(base, 0)) + 1
	s += "**出招武功（戰鬥中按「武」）**\n\n"
	for cat in STRIKE_CATS:
		if not base_of.has(cat):
			continue
		var best := ""
		var n := -1
		for b in base_of[cat]:
			if int(base_of[cat][b]) > n:
				best = str(b)
				n = int(base_of[cat][b])
		s += "- %s\n" % "".join(_polish_all(_generic_lines(cat, best)))
	s += "- 出招實際耗的內力 ＝ 招式耗內力 × 成數 ÷ 5（無條件進位）；招式表列的是預設 10 成的耗量，用 5 成出招就只耗一半。耗精不看成數。\n"
	s += "- 招式表的「附帶狀態」是打中時讓對方得到該狀態的機會；標＊的（%s）只在後期規則開著時才會發生。\n\n" % "、".join(_status_names(BattleCmds.PLAYER_MOVE_LATER_STATUSES))
	s += "**內功心法、輕功**\n\n"
	for cat in ["INNER", "LIGHTNESS"]:
		if not base_of.has(cat):
			continue
		var best2 := ""
		for b in base_of[cat]:
			best2 = str(b)
			break
		s += "- %s\n" % "".join(_polish_all(_generic_lines(cat, best2)))
	s += "- %s\n\n" % _polish("全真弟子用「內」療傷，回氣量再 ×%s（門派加成）%s。" % [_fmt_num(BattleCmds.QUANZHEN_HEAL_MULT), LATER_SHORT])
	s += "**指令武功（毒、醫、暗、陣）**\n\n"
	s += "- 這幾類武功的招式不用選：「毒」「醫」「暗」會自動用已解鎖的最後一招（都還沒解鎖時用第一招），所以招式表只列指令真的會用到的欄位。\n"
	s += "- 「毒」：用到招式的威力（毒中時傷害 ＝ 威力×0.5×(1＋武功等級/60)）、射程、耗內力（下毒時就扣，不論毒中與否）。毒中機會 ＝ 40%＋(毒力−對方抵抗)×0.5%，最少 10%、最多 90%；招式本身沒有另外的中毒機會。\n"
	s += "- 「醫」：只用到招式的射程和耗內力，另外花精 %d、神 %d；一次只治一個人，治療量 ＝ 20＋基本醫術×2＋醫術武功×3，招式的威力和範圍都沒有作用。恆山弟子治療量再 ×%s（門派加成）。\n" % [BattleCmds.MEDIC_JING, BattleCmds.MEDIC_SHEN, _fmt_num(BattleCmds.HENGSHAN_MEDIC_MULT)]
	s += "- 「暗」：傷害另加 招式威力×(1＋武功等級/60)，扣招式的耗內力；射程看基本暗器（另加武功的射程加成），不看招式；招式附帶的狀態照表上的機會。\n"
	s += "- 「陣」：只扣第一招的耗內力，招式的威力、射程、範圍沒有作用；陣的強弱看各陣法武功列的加成。\n\n"
	s += "**招式表的射程與範圍**\n\n"
	s += "射程是能打到幾格外（直走、橫走一格各算一步；直線、半米字斜走一格也算一步）。範圍是打中的形狀：\n\n"
	s += "| 範圍 | 打到哪些格 |\n|---|---|\n"
	s += "| %s | 只有選的那一格 |\n" % _aoe_name("SINGLE")
	s += "| %s | 選的那一格和它上下左右各 1 格，共 5 格 |\n" % _aoe_name("CROSS")
	s += "| %s | 選的那一格和它上下左右各 %d 格，共 %d 格 |\n" % [_aoe_name("CROSS_L"), BattleAoe.CROSS_L_ARM, 1 + 4 * BattleAoe.CROSS_L_ARM]
	s += "| %s | 從自己往一個方向（上下左右或斜向）一直線，長度＝射程 |\n" % _aoe_name("LINE")
	s += "| %s | 從自己往一個方向，加上 8 個方向裡和它相鄰的兩個方向，共三條線，長度＝射程 |\n" % _aoe_name("FAN")
	s += "| %s | 自己周圍 8 格 |\n\n" % _aoe_name("AROUND")
	s += "[回到附錄目錄](#app-arts)\n\n"
	return s

func _polish_all(ls: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for l in ls:
		out.append(_polish(l))
	return out

func _status_names(ids: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for i in ids:
		out.append(_status_name(str(i)))
	return out

# ---------------------------------------------------------------- 主體

func _build(ver: String) -> String:
	var era_names := PackedStringArray()
	for e in ERAS_DEFAULT:
		era_names.append("%s「%s」" % [e, str(CharData.row(view, "eras", e).get("name", e))])
	# 武功分組
	var arts: Array = []
	for a in _rows("martial_arts"):
		if a is Dictionary and not bool(a.get("monster_only", false)):
			arts.append(a)
	var by_sect: Dictionary = {}
	var general: Array = []
	var combos: Array = []
	for a in arts:
		var cb: Variant = a.get("combo", null)
		if cb is Dictionary and not (cb as Dictionary).is_empty():
			combos.append(a)
		elif str(a.get("sect_id", "")) == "":
			general.append(a)
		else:
			var sid := str(a.get("sect_id", ""))
			if not by_sect.has(sid):
				by_sect[sid] = []
			by_sect[sid].append(a)
	var idx := 2
	var counts := PackedStringArray()
	var body := ""
	var toc := PackedStringArray()
	toc.append("[各類武功通則](#app-arts-rules)")
	toc.append("[一、基本武學](#app-arts-basic)")
	for sect in _rows("sects"):
		var sid := str(sect.get("id", ""))
		var list: Array = by_sect.get(sid, [])
		by_sect.erase(sid)
		if list.is_empty():
			continue
		b_sect = not (view_a.get("sects", {}) as Dictionary).has(sid)
		var title := "%s、%s%s（%d 門）" % [CN_NUM[idx - 1], str(sect.get("name", sid)), "【1.0B】" if b_sect else "", list.size()]
		toc.append("[%s](#app-arts-%s)" % [title, sid])
		body += "### <a id=\"app-arts-%s\"></a>%s\n\n" % [sid, title]
		counts.append("%s %d" % [str(sect.get("name", sid)), list.size()])
		idx += 1
		for a in list:
			body += _art_block(a)
		body += "[回到附錄目錄](#app-arts)\n\n"
		b_sect = false
	for sid in by_sect:
		problems.append("arts with unknown sect: " + str(sid))
	if not general.is_empty():
		var title2 := "%s、無門派武功（%d 門）" % [CN_NUM[idx - 1], general.size()]
		toc.append("[%s](#app-arts-general)" % title2)
		body += "### <a id=\"app-arts-general\"></a>%s\n\n" % title2
		counts.append("無門派 %d" % general.size())
		idx += 1
		for a in general:
			body += _art_block(a)
		body += "[回到附錄目錄](#app-arts)\n\n"
	if not combos.is_empty():
		var title3 := "%s、合體武功（%d 門）" % [CN_NUM[idx - 1], combos.size()]
		toc.append("[%s](#app-arts-combo)" % title3)
		body += "### <a id=\"app-arts-combo\"></a>%s\n\n" % title3
		counts.append("合體 %d" % combos.size())
		for a in combos:
			body += _art_block(a)
		body += "[回到附錄目錄](#app-arts)\n\n"

	var s := "## %s附錄：全武功效果一覽\n\n" % ANCHOR
	s += "本附錄由 %s 版的遊戲資料與遊戲內武功說明自動產生（世界資料片 %s，新世界預設），列出玩家學得到的每一門基本武學與武功；怪物專用的武功不列。只有 1.0B 才有的武功、師父標【1.0B】。\n\n" % [ver, "＋".join(era_names)]
	s += "怎麼看：\n\n"
	s += "- **被動效果**：學會之後就有的效果，以及它讓你能用哪些戰鬥指令。學會的武功都算數，不用另外設定；內功心法與輕功只算你等級最高的那一門。同一類武功都一樣的部分寫在[各類武功通則](#app-arts-rules)。\n"
	s += "- **招式**：出招武功（拳掌、刀、劍、鞭、棍、槍、筆刺）在戰鬥中按「武」選招，練到「解鎖等級」才能用，威力隨武功等級放大；毒、醫、暗、陣這幾類的招式不用選，各欄怎麼算見[通則](#app-arts-rules)。\n"
	s += "- 數字照遊戲公式寫，和遊戲內學武視窗、武功窗的說明相同；伺服器規則改了，部分數字會跟著變。標「%s」的效果預設的「懷舊標準」規則組合有，「懷舊嚴苛（2001）」規則組合沒有。\n" % LATER_SHORT
	s += "- 師父欄的「教到 N 級」是那位師父最多能教到的等級；實際還受實戰經驗、門派技能等上限限制（見[第二章](#ch2-1)、[等級上限](#ch3-2-3)）。\n\n"
	s += "目錄：\n\n"
	for t in toc:
		s += "- %s\n" % t
	s += "\n"
	s += _rules_section(arts)
	# 基本武學
	s += "### <a id=\"app-arts-basic\"></a>一、基本武學\n\n"
	var basics := _rows("basic_skills")
	for b in basics:
		var id := str(b.get("id", ""))
		var bb := "【1.0B】" if not (view_a.get("basic_skills", {}) as Dictionary).has(id) else ""
		s += "#### %s%s\n\n" % [str(b.get("name", id)), bb]
		var ls := SkillEffects.lines(id, view)
		if ls.is_empty():
			problems.append("no effect text: " + id)
		for l in ls:
			s += "- %s\n" % _polish(l)
		if id == "basic_medic":
			s += "- 恆山弟子用「醫」，治療量再 ×%s（門派加成）。\n" % _fmt_num(BattleCmds.HENGSHAN_MEDIC_MULT)
		var ml := _masters_list(id)
		s += "- 師父：%s\n" % ("" if not ml.is_empty() else "沒有師父教")
		for m in ml:
			s += "  - %s\n" % m
		s += "\n"
	s += "[回到附錄目錄](#app-arts)\n\n"
	s += body
	print("COUNTS: basic %d; arts %d; %s" % [basics.size(), arts.size(), ", ".join(counts)])
	return s
