class_name StoryUi
extends RefCounted
## 故事包介面的共用小工具（STORY_PLAN §6）：江湖傳聞的文字、任務冷卻的「遊戲時辰」、伺服器設定八項的規格、
## 任務定義（本機 GameData 的 quests 表，第 2 版 stages 格式）的查詢。純函式，測試直接呼叫。
## UI 不引用 server/**（M1_PLAN 3.12）：世界時鐘的常數在這裡另抄一份（server/world_clock.gd 改了要一起改）。

## server/world_clock.gd 的 DEFAULT_DAY_S／START_SHICHEN／SHICHEN
const DEFAULT_DAY_S := 7200.0
const START_SHICHEN := 4
const SHICHEN := ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]

const RUMOR_TAG := "【江湖傳聞】"
## 傳聞的來源（§5.1 kind）→ 江湖傳聞頁的小標
const RUMOR_KIND_LABELS := {
	"FORESHADOW": "風聞", "QUEST": "事件", "DEED": "事蹟", "PK": "血案", "VILLAIN": "惡人",
}
## 舊格式任務（沒有 chapter）在任務窗的分組名
const DEFAULT_CHAPTER := "江湖雜事"

## 伺服器設定面板新增的八項（STORY_PLAN §5.5；預設值照本表）。主機的 server_options.editable 有這個 key 時以主機為準；
## 沒有（主機還沒開放修改）時照這裡顯示目前值（讀得到的話）並灰掉。
const ONOFF := [{ "value": "true", "label": "開" }, { "value": "false", "label": "關" }]
const STORY_OPTIONS := [
	{ "key": "rumors_enabled", "label": "江湖傳聞（非原作）", "default": "true", "choices": ONOFF,
	  "desc": "系統廣播事件預告、任務結果與玩家事蹟（非原作）；原作的「江湖謠言」是玩家匿名頻道，不受影響" },
	{ "key": "rumor_min_gap_s", "label": "傳聞最短間隔", "default": "120",
	  "choices": [{ "value": "30", "label": "30 秒" }, { "value": "60", "label": "1 分鐘" }, { "value": "120", "label": "2 分鐘" },
		{ "value": "300", "label": "5 分鐘" }, { "value": "600", "label": "10 分鐘" }],
	  "desc": "同一類傳聞兩則之間至少隔多久（真實時間）；全服第一位完成的傳聞不受限制" },
	{ "key": "rumor_chat_inner_min", "label": "江湖謠言頻道門檻", "default": "80",
	  "choices": [{ "value": "0", "label": "不限" }, { "value": "30", "label": "基本內功 30" }, { "value": "80", "label": "基本內功 80" }],
	  "desc": "在「江湖謠言」頻道說話需要的基本內功等級（預設照原作 80：鐵心網 FAQ；開放年代【待考證】）" },
	{ "key": "wanderers_enabled", "label": "惡人夜遊（非原作）", "default": "true", "choices": ONOFF,
	  "desc": "南海鱷神、葉二娘戌時到寅時在西夏附近野外遊蕩並主動出手；白天在西夏城裡交談即戰不受此開關影響" },
	{ "key": "villain_warn_s", "label": "惡人出手前警告", "default": "3",
	  "choices": [{ "value": "2", "label": "2 秒" }, { "value": "3", "label": "3 秒" }, { "value": "5", "label": "5 秒" }, { "value": "8", "label": "8 秒" }],
	  "desc": "遊蕩惡人或追擊 NPC 出手前的警告秒數；這段時間內離開房間就能脫身" },
	{ "key": "chase_npcs", "label": "追擊 NPC", "default": "true", "choices": ONOFF,
	  "desc": "野外的惡人頭子會追擊路過的玩家，追擊戰不能逃（原作 2001-08-30）" },
	{ "key": "ambient_lines", "label": "NPC 閒聊與環境句（非原作）", "default": "true", "choices": ONOFF,
	  "desc": "走進房間時偶爾出現一句環境描述或 NPC 自言自語（非原作）" },
	{ "key": "npc_reactions", "label": "NPC 對善惡的反應（非原作）", "default": "FULL",
	  "choices": [{ "value": "OFF", "label": "關" }, { "value": "FLAVOR", "label": "只有招呼語" }, { "value": "FULL", "label": "招呼語＋價格與拒絕服務" }],
	  "desc": "惡名昭彰的人買東西較貴、甚至被拒絕；名聲高的人打折（非原作）。驛站、師父、守衛不受影響" },
]

static func story_option_keys() -> Array:
	return STORY_OPTIONS.map(func(o): return str(o["key"]))

static func story_option(key: String) -> Dictionary:
	for o in STORY_OPTIONS:
		if str(o["key"]) == key:
			return o
	return {}

## 主機沒有把這項放進 editable 時的目前值：server_options 的 info／options、world_info；都沒有就用預設值
static func option_value(key: String, opts: Dictionary, wi: Dictionary) -> String:
	for src in [opts.get("options", {}), (opts.get("info", {}) as Dictionary).get("options", {}) if opts.get("info", {}) is Dictionary else {}, wi]:
		if src is Dictionary and (src as Dictionary).has(key):
			return value_string((src as Dictionary)[key])
	return str(story_option(key).get("default", ""))

## 選項值一律字串（server_opts_set 的 value）；JSON 來的整數不要變成 "120.0"
static func value_string(v: Variant) -> String:
	if v is bool:
		return "true" if v else "false"
	if v is float and v == floorf(v):
		return str(int(v))
	return str(v)

# ---------------------------------------------------------------- 時間

static func day_s() -> float:
	var wi := UiClient.world_info()
	for k in ["game_day_real_s", "day_s"]:
		var v: Variant = wi.get(k, null)
		if (v is int or v is float) and float(v) > 0.0:
			return float(v)
	return DEFAULT_DAY_S

## 世界秒數 → 「約 3 個時辰」「約 1 天 2 個時辰」（冷卻剩餘、等待）；0 以下回 ""
static func span_text(world_secs: float, p_day_s: float = 0.0) -> String:
	if world_secs <= 0.0:
		return ""
	var d := p_day_s if p_day_s > 0.0 else day_s()
	var n := maxi(1, ceili(world_secs / (d / 12.0) - 1e-6))
	if n < 12:
		return "約 %d 個時辰" % n
	var days := n / 12
	var rest := n % 12
	return "約 %d 天" % days if rest == 0 else "約 %d 天 %d 個時辰" % [days, rest]

## 世界秒數（世界時鐘的絕對時間）→ 「第 3 天 戌時」
static func world_time_label(world_s: float, p_day_s: float = 0.0) -> String:
	var d := p_day_s if p_day_s > 0.0 else day_s()
	var sc := d / 12.0
	var clock_s := maxf(world_s, 0.0) + START_SHICHEN * sc
	var day := int(floor(clock_s / d)) + 1
	var idx := int(floor(fmod(clock_s, d) / sc)) % 12
	return "第 %d 天 %s時" % [day, SHICHEN[idx]]

# ---------------------------------------------------------------- 江湖傳聞

## E_RUMOR／E_RUMOR_LIST 項目 { text_key, params, kind, world_s } → 純文字（不含【江湖傳聞】）。
## 模板可能有 other／self／text 任一變體（傳聞是對所有人說的：先用 other）；模板不存在時用 params.text，再不行就不顯示
static func rumor_text(p: Dictionary, templates: Dictionary) -> String:
	var key := str(p.get("text_key", ""))
	var params: Dictionary = p.get("params", {}) if p.get("params", {}) is Dictionary else {}
	var tpl: Variant = templates.get(key, null)
	var raw := ""
	if tpl is Dictionary:
		for v in ["other", "self", "text", "target"]:
			if (tpl as Dictionary).has(v) and str(tpl[v]) != "":
				raw = str(tpl[v])
				break
	elif tpl is String:
		raw = str(tpl)
	if raw == "":
		raw = str(params.get("text", ""))
	if raw == "":
		return ""
	return TextRenderer.strip_channel_tag(TextRenderer.fill(raw, params))

static func rumor_line(p: Dictionary, templates: Dictionary) -> String:
	var t := rumor_text(p, templates)
	return RUMOR_TAG + t if t != "" else ""

static func rumor_kind_label(kind: String) -> String:
	return str(RUMOR_KIND_LABELS.get(kind, "傳聞"))

# ---------------------------------------------------------------- 遊蕩惡人

static func villain_text(p: Dictionary) -> String:
	var n := str(p.get("npc_name", ""))
	return "%s朝你逼近！" % (n if n != "" else "惡人")

## 審查修正（敘事）：這個惡人自己的警告句（villain_prompt 的 warn_key 模板；去掉結尾的「快離開這裡！」，提示列已經有）
static func villain_line(p: Dictionary) -> String:
	var key := str(p.get("warn_key", ""))
	var tpl: Variant = UiClient.templates().get(key, null) if key != "" and key != "villain_warn" else null
	if not (tpl is Dictionary):
		return ""
	var t := TextRenderer.fill(str((tpl as Dictionary).get("self", "")), p)
	return t.trim_suffix("快離開這裡！").strip_edges()

# ---------------------------------------------------------------- 任務定義（本機資料）

static func quest_def(qid: String) -> Dictionary:
	return UiClient.row("quests", qid)

static func stage_def(def: Dictionary, stage_id: String) -> Dictionary:
	for st in def.get("stages", []):
		if st is Dictionary and str(st.get("id", "")) == stage_id:
			return st
	return {}

## 任務的分章（角色表列的 chapter → 本機資料 → 預設）
static func chapter_of(row: Dictionary) -> String:
	var c := str(row.get("chapter", ""))
	if c == "":
		c = str(quest_def(str(row.get("id", ""))).get("chapter", ""))
	return c if c != "" else DEFAULT_CHAPTER

## 這位 NPC 是不是這條任務目前階段的某個未完成目標（TALK／DELIVER／ESCORT 等帶 npc 的目標）。
## 用本機資料 + 角色表的 stage 判斷；資料是舊格式（沒有 stages）時回 false（照舊用 交付）
static func npc_has_current_objective(qid: String, npc_id: String, sh: Dictionary) -> bool:
	var row := sheet_quest(sh, qid)
	if row.is_empty():
		return false
	var st := stage_def(quest_def(qid), str(row.get("stage", "")))
	if st.is_empty():
		return false
	var done := {}
	var objs: Array = row.get("objectives", []) if row.get("objectives", []) is Array else []
	var defs: Array = st.get("objectives", []) if st.get("objectives", []) is Array else []
	for i in defs.size():
		if i < objs.size() and objs[i] is Dictionary and bool(objs[i].get("done", false)):
			done[i] = true
	for i in defs.size():
		var o: Variant = defs[i]
		if o is Dictionary and str(o.get("npc", "")) == npc_id and not done.has(i):
			return true
	return false

static func sheet_quest(sh: Dictionary, qid: String) -> Dictionary:
	for q in sh.get("quests", []):
		if q is Dictionary and str(q.get("id", "")) == qid:
			return q
	return {}

## 任務列的「接」要不要先開對話（資料有 offer → quest_talk 開 offer 對話；沒有 → 舊的 quest_accept）
static func has_offer(qid: String) -> bool:
	return str(quest_def(qid).get("offer", "")) != ""

## 冷卻剩餘的世界秒數：角色表 quest_cd（§4.14，世界秒）→ npc_menu 任務項的 cooldown_left_s（主機給真實秒；
## 正常速度時兩者相同）等欄位；都沒有回 0
static func cooldown_left(entry: Dictionary, sh: Dictionary) -> float:
	var cd: Variant = sh.get("quest_cd", {})
	if cd is Dictionary:
		var w: Variant = (cd as Dictionary).get(str(entry.get("id", "")), null)
		if w is int or w is float:
			return float(w)
	for k in ["cooldown_left_s", "left_s", "cd_s", "cooldown_s"]:
		var v: Variant = entry.get(k, null)
		if v is int or v is float:
			return float(v)
	return 0.0

## 房間名與所在地區名（本機資料）；查不到回 id
static func room_label(room_id: String) -> String:
	if room_id == "":
		return ""
	var idx := MapData.room_index(UiClient.tables())
	var r: Dictionary = idx.get(room_id, {})
	var room: Dictionary = r.get("room", {}) if r.get("room", {}) is Dictionary else {}
	var nm := str(room.get("name", room_id))
	var region := str(r.get("region", ""))
	var rn := UiClient.name_of("regions", region, "") if region != "" else ""
	return "%s（%s）" % [nm, rn] if rn != "" and rn != region else nm
