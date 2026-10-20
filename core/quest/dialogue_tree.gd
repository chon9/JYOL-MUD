class_name DialogueTree
extends RefCounted
## 對話樹（STORY_PLAN §4.5）。純邏輯：節點檢視（含上鎖選項與原因）、選項查詢。
## 對話游標與動作執行在主機（QuestSystem）。

const END := "END"
## 節點沒有 choices、只有 goto 到另一個節點時，送給客戶端一個合成的「繼續」選項（id 以 _ 開頭，資料裡的選項不得用）
const NEXT_CHOICE := "_next"
const NEXT_LABEL := "（繼續）"

## 回傳 { dlg, node, speaker, text, choices: [{ id, label, locked, why }], end, goto, do }；
## 對話或節點不存在 → {}。speaker 是資料原值（"npc"、"player" 或 NPC id），主機再換成名字。
## ctx：Requirements 的主機環境（shichen、party_size）。
static func node_view(def: Dictionary, dlg_id: String, node_id: String, ch, tables, options, rules, ctx) -> Dictionary:
	var n := node(def, dlg_id, node_id)
	if n.is_empty():
		return {}
	var choices: Array = []
	for c in n.get("choices", []):
		if not (c is Dictionary):
			continue
		var why := lock_reason(c, ch, tables, options, rules, ctx)
		var locked := why != ""
		if locked and bool(c.get("hide_if_locked", false)):
			continue
		choices.append({ "id": str(c.get("id", "")), "label": str(c.get("label", "")), "locked": locked, "why": why })
	var g := str(n.get("goto", ""))
	var has_next := choices.is_empty() and (n.get("choices", []) as Array).is_empty() and g != "" and g != END
	if has_next:
		choices.append({ "id": NEXT_CHOICE, "label": NEXT_LABEL, "locked": false, "why": "" })
	return {
		"dlg": dlg_id, "node": node_id, "speaker": str(n.get("speaker", "npc")), "text": str(n.get("text", "")),
		"choices": choices, "end": choices.is_empty(), "goto": g,
		"do": (n.get("do", []) as Array).duplicate(true) if n.get("do") is Array else [],
	}

## 選項本身（{ id, label, requires, do, goto }）；合成的「繼續」選項回 { id: "_next", do: [], goto: 節點的 goto }。
## 不存在 → {}
static func choice(def: Dictionary, dlg_id: String, node_id: String, choice_id: String) -> Dictionary:
	var n := node(def, dlg_id, node_id)
	if n.is_empty():
		return {}
	if choice_id == NEXT_CHOICE:
		var g := str(n.get("goto", ""))
		if (n.get("choices", []) as Array).is_empty() and g != "" and g != END:
			return { "id": NEXT_CHOICE, "label": NEXT_LABEL, "requires": [], "do": [], "goto": g }
		return {}
	for c in n.get("choices", []):
		if c is Dictionary and str(c.get("id", "")) == choice_id:
			var out: Dictionary = c.duplicate(true)
			if not (out.get("do") is Array):
				out["do"] = []
			if not (out.get("requires") is Array):
				out["requires"] = []
			out["goto"] = str(out.get("goto", END)) if out.get("goto") != null else END
			return out
	return {}

## 選項上鎖的原因（第一個不成立的條件的中文說明）；沒上鎖回 ""
static func lock_reason(c: Dictionary, ch, tables, options, rules, ctx) -> String:
	var reqs: Variant = c.get("requires", [])
	if not (reqs is Array) or (reqs as Array).is_empty() or ch == null:
		return ""
	var ctx_d: Dictionary = ctx if ctx is Dictionary else {}
	for cond in reqs:
		if not (cond is Dictionary):
			continue
		if Requirements.check([cond], ch, tables, options, rules, ctx_d) != "":
			var d := str(cond.get("desc", ""))
			return d if d != "" else Requirements.describe(cond, tables)
	return ""

static func dialogue(def: Dictionary, dlg_id: String) -> Dictionary:
	var dl: Variant = def.get("dialogues", {}).get(dlg_id, {}) if def.get("dialogues") is Dictionary else {}
	return dl if dl is Dictionary else {}

static func node(def: Dictionary, dlg_id: String, node_id: String) -> Dictionary:
	var nodes: Variant = dialogue(def, dlg_id).get("nodes", {})
	if not (nodes is Dictionary) or not nodes.has(node_id) or not (nodes[node_id] is Dictionary):
		return {}
	return nodes[node_id]

## 開啟對話時的起點：first_time → start，否則 resume（預設 = start）
static func entry_node(def: Dictionary, dlg_id: String, first_time: bool) -> String:
	var dl := dialogue(def, dlg_id)
	var start := str(dl.get("start", ""))
	if first_time:
		return start
	var r := str(dl.get("resume", ""))
	return r if r != "" and (dl.get("nodes", {}) as Dictionary).has(r) else start
