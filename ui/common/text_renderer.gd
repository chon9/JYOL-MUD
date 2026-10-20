class_name TextRenderer
extends RefCounted
## 把結構化事件組成 BBCode（TECH_ARCH 11.1、M1_PLAN 3.8、3.12）。依「誰在看」選 self / target / other 模板。
## - 事件帶 "ui": true（UI-only）→ 一律回空字串。
## - 模板存在但缺少該看的變體 → 回空字串；key 完全不存在 → 顯示 key + JSON（M0 行為，方便除錯）。

## 頻道色（AUTHENTIC_UI_SPEC §9.3）：亮色，畫在沒有底色的左上浮層上（RichTextLabel 加黑描邊）
const CHANNEL_COLORS := {
	"SYSTEM": "#ffa040",
	"CHAT_WORLD": "#40e0f0",
	"SCENE": "#f4f0e6",
	"BATTLE": "#f0d060",
	# M2 聊天頻道（AUTHENTIC_UI_SPEC §9.3【推測】）
	"CHAT_WHISPER": "#ff80ff",
	"CHAT_SAY": "#f4f0e6",
	"CHAT_SECT": "#80ff80",
	"CHAT_GUILD": "#ffb070",
	"CHAT_PARTY": "#80c0ff",
	"CHAT_RUMOR": "#ffff60",
	"GM": "#a0e0ff",
	"MAIL": "#ffc860",   # 飛鴿傳書：§9.3 沒有列，取祈願天燈的暖黃【設計提案】
	"JIANGHU": "#ffb0a0",   # 系統【江湖傳聞】（STORY_PLAN §6.3【設計提案・非原作】）：和玩家的江湖謠言（黃）分開
}
## 重要系統訊息（事件或 p 帶 "important": true）：白字、紅底色條
const IMPORTANT_FG := "#ffffff"
const IMPORTANT_BG := "#c00000"
## 失敗原因（intent_result）在浮層上的顏色
const ERROR_COLOR := "#ff6a50"
const REASON_FALLBACK := "【系統】無法執行（{reason}）"

static func escape_bbcode(s: String) -> String:
	return s.replace("[", "[lb]")

## 回傳要使用的變體名稱；"" = 此人不該看到（或模板缺這個變體）
static func pick_variant(e: Dictionary, my_peer: int, tpl: Dictionary) -> String:
	var p: Dictionary = e.get("p", {})
	var actor: int = int(p.get("from_peer", p.get("peer", p.get("atk_peer", -1))))
	var target: int = int(p.get("def_peer", -1))
	if actor == my_peer:
		return "self" if tpl.has("self") else ""
	if target == my_peer:
		return "target" if tpl.has("target") else ""
	if tpl.has("other"):
		return "other"
	# 事件沒有任何 peer 欄位（例如 M0 的 pong）：沿用 M0 行為，退回 self
	if actor == -1 and target == -1 and tpl.has("self"):
		return "self"
	return ""

static func render_plain(e: Dictionary, my_peer: int, templates: Dictionary) -> String:
	if bool(e.get("ui", false)):
		return ""
	var key: String = str(e.get("key", ""))
	var p: Dictionary = e.get("p", {})
	if not templates.has(key):
		return "%s %s" % [key, JSON.stringify(p)]
	var tpl: Dictionary = templates[key]
	var variant := pick_variant(e, my_peer, tpl)
	if variant == "":
		return ""
	return fill(str(tpl[variant]), p)

## 獎勵事件（reward、battle_reward）的 {reward_list}：只列不是 0 的項目（審查：「實戰經驗 +0、學習點數 +0」）
const REWARD_PARTS := [["combat_xp", "實戰經驗"], ["learn_points", "學習點數"], ["money", "銀兩"], ["fame", "聲望"], ["morality", "善惡"]]

static func reward_list(p: Dictionary) -> String:
	var parts: PackedStringArray = []
	for pair in REWARD_PARTS:
		var n := int(p.get(pair[0], 0))
		if n != 0:
			parts.append("%s %s%d" % [pair[1], "+" if n > 0 else "", n])
	return "、".join(parts)

static func fill(text: String, p: Dictionary) -> String:
	if text.contains("{reward_list}"):
		var rl := reward_list(p)
		if rl == "":
			return ""   # 什麼都沒拿到：整行不顯示
		text = text.replace("{reward_list}", rl)
	for k in p:
		var v: Variant = p[k]
		if v is Array or v is Dictionary:
			continue
		if v is float and v == floorf(v) and absf(v) < 1e15:
			v = int(v)   # 經過 JSON／RPC 的整數不要顯示成 12.0
		text = text.replace("{%s}" % k, str(v))
	return text

static func render(e: Dictionary, my_peer: int, templates: Dictionary) -> String:
	var plain := render_plain(e, my_peer, templates)
	if plain == "":
		return ""
	if is_important(e):
		return "[bgcolor=%s][color=%s]%s[/color][/bgcolor]" % [IMPORTANT_BG, IMPORTANT_FG, escape_bbcode(plain)]
	var color: String = CHANNEL_COLORS.get(e.get("ch", ""), CHANNEL_COLORS["SCENE"])
	return "[color=%s]%s[/color]" % [color, escape_bbcode(plain)]

static func is_important(e: Dictionary) -> bool:
	var p: Variant = e.get("p", {})
	return bool(e.get("important", false)) or (p is Dictionary and bool((p as Dictionary).get("important", false)))

## intent_result.reason → 中文（M1_PLAN 3.7）：
## drop: 開頭不顯示；帶冒號者查 err_bad_args；其餘查 err_<reason>（req_<type> 即 err_req_<type>）；
## 一律用 self 變體；查不到顯示「【系統】無法執行（{reason}）」。
## params：模板參數（busy 的 {n} = 還要幾秒）
static func render_reason(reason: String, templates: Dictionary, params: Dictionary = {}) -> String:
	if reason == "" or reason.begins_with("drop:"):
		return ""
	var key := "err_bad_args" if reason.contains(":") else "err_" + reason
	var tpl: Variant = templates.get(key, {})
	if tpl is Dictionary and tpl.has("self") and str(tpl["self"]) != "":
		var p := params.duplicate()
		p["reason"] = reason
		return fill(str(tpl["self"]), p)
	return REASON_FALLBACK.replace("{reason}", reason)

## 頻道標籤（開頭的「【系統】」等）只屬於訊息紀錄；嵌在對話框、清單、地圖頁尾、提示框裡時拿掉
static func strip_channel_tag(t: String) -> String:
	var s := t.strip_edges(true, false)
	if s.begins_with("【"):
		var end := s.find("】")
		if end > 0:
			s = s.substr(end + 1).strip_edges(true, false)
	return s

## render_reason 的介面內嵌版（不帶頻道標籤）
static func render_reason_inline(reason: String, templates: Dictionary, params: Dictionary = {}) -> String:
	return strip_channel_tag(render_reason(reason, templates, params))
