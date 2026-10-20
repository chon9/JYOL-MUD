class_name NpcAttackUi
extends RefCounted
## 攻擊 NPC 的介面文字（M3C_PLAN §5.8；純靜態，場景卷軸、主畫面、NPC 對話框共用）。
## npc_entry ＝ 房間 view 的 npcs[] 項目：{ id, name, …, atk: { mode, category, align, sect, menu_label, warn, via, effect } 或 null }。
## 是否真的能動手由主機判定（npc_attack）；這裡只擋本機就看得出來的情況（受保護 NPC、安全的地方、戰鬥中），並組確認框文字。

const MODE_CHALLENGE := "CHALLENGE"
const MODE_MIEPAI := "MIEPAI"
const MODE_ATTACK := "ATTACK"
## 城裡殺了會招來官兵的類別（§5.5）
const GUARD_CATEGORIES := ["CIVILIAN", "CHILD", "ANIMAL", "WORKER", "GUARD"]
const OK_LABEL := "動手"
const CANCEL_LABEL := "再想想"   # M3c 審查：Ctrl+點的確認框與 NPC 對話框的滅派確認用同一組字（動手／再想想）
const TITLE := "動手"            # M3c 審查：不用英文「NPC」（原作介面沒有）

static func atk_of(npc_entry: Dictionary) -> Dictionary:
	var a: Variant = npc_entry.get("atk", null)
	return a if a is Dictionary else {}

static func attackable(npc_entry: Dictionary) -> bool:
	return not atk_of(npc_entry).is_empty()

## 滑鼠提示的附加句（可以動手的 NPC 才有）
static func tooltip_suffix(npc_entry: Dictionary) -> String:
	if not attackable(npc_entry):
		return ""
	return "（%s+點：動手）" % UiSocial.pk_key_label()

## 受保護的本機提示（M3C_PLAN §5.2：npc_not_attackable）
static func not_attackable_text(npc_name: String) -> String:
	var tpl: Variant = UiClient.templates().get("na_not_attackable", {})
	if tpl is Dictionary and str(tpl.get("self", "")) != "":
		return TextRenderer.fill(str(tpl["self"]), { "npc_name": npc_name })
	return "【系統】%s不是你能動手的對象。" % npc_name

## 本機就能判斷的阻擋原因碼（"" ＝ 可以跳確認框）：npc_not_attackable、in_battle、npc_safe_room
static func block_reason(npc_entry: Dictionary, view: Dictionary, sheet: Dictionary) -> String:
	if not attackable(npc_entry):
		return "npc_not_attackable"
	if bool(sheet.get("in_battle", false)):
		return "in_battle"
	if _room_safe(view):
		return "npc_safe_room"
	return ""

## 阻擋原因的訊息列文字（受保護的 NPC 帶名字）
static func block_text(npc_entry: Dictionary, view: Dictionary, sheet: Dictionary) -> String:
	var why := block_reason(npc_entry, view, sheet)
	if why == "npc_not_attackable":
		return not_attackable_text(str(npc_entry.get("name", "對方")))
	return UiClient.reason_text(why) if why != "" else ""

## view.safe 是「沒有遇敵」（城裡也是 true），不是房間資料的 safe：查房間資料（思過處、監獄等）
static func _room_safe(view: Dictionary) -> bool:
	var rid := str(view.get("room", ""))
	var region := str(view.get("region", ""))
	if rid == "" or region == "":
		return false
	var m: Variant = UiClient.tables().get("maps", {}).get(region, {})
	if not (m is Dictionary):
		return false
	for r in (m as Dictionary).get("rooms", []):
		if r is Dictionary and str(r.get("id", "")) == rid:
			return bool(r.get("safe", false))
	return false

static func my_sect(sheet: Dictionary) -> String:
	var s := str(sheet.get("sect", ""))
	if s == "":
		var si: Variant = sheet.get("sect_info", {})
		s = str((si as Dictionary).get("id", "")) if si is Dictionary else ""
	return s

static func sect_label(sect_id: String) -> String:
	if sect_id == "":
		return ""
	var n := UiClient.name_of("sects", sect_id, sect_id)
	for suf in ["派", "門", "教", "宮", "幫"]:
		if n.ends_with(suf):
			return n
	return n + "派"

## 我已經是這一派的公敵（sheet.enemy_of 是門派名字）
static func already_enemy(sheet: Dictionary, sect_id: String) -> bool:
	var names: Variant = sheet.get("enemy_of", [])
	if not (names is Array):
		return false
	var nm := UiClient.name_of("sects", sect_id, sect_id)
	return (names as Array).has(nm) or (names as Array).has(sect_id) or (names as Array).has(sect_label(sect_id))

## 門派後果："BREACH"（違反門規）、"BETRAY"（叛派）、"ENEMY"（成為公敵）、""。主機給了 atk.effect 就用主機的
static func sect_effect(atk: Dictionary, sheet: Dictionary, mode: String = MODE_ATTACK) -> String:
	if atk.has("effect"):
		return str(atk["effect"])   # 主機依這位玩家算好的（view 的是 Ctrl 動手、npc_menu 的是滅派）
	var sid := str(atk.get("sect", ""))
	if sid == "":
		return ""
	var cat := str(atk.get("category", ""))
	if my_sect(sheet) == sid:
		return "BETRAY" if cat == "SECT_MASTER" else "BREACH"
	if cat == "SECT_GATE" or cat == "SECT_MASTER" or mode == MODE_MIEPAI:
		return "" if already_enemy(sheet, sid) else "ENEMY"
	return ""

static func _city_with_guard(view: Dictionary) -> bool:
	var region := str(view.get("region", ""))
	if region == "" or str(UiClient.row("regions", region).get("type", "")) != "CITY":
		return false
	var npcs: Dictionary = UiClient.table("npcs")
	for nid in npcs:
		var r: Variant = npcs[nid]
		if r is Dictionary and str(r.get("kind", "")) == "GUARD" and str(r.get("region", "")) == region:
			return true
	return false

## 這次要面對的對手：主機給的 atk.foes（[{ name, n }]）；舊主機沒有時依資料表的 attack.group 自己算（不知道是不是第二次滅派）
static func foes_of(npc_entry: Dictionary) -> Array:
	var atk := atk_of(npc_entry)
	var f: Variant = atk.get("foes", null)
	if f is Array and not (f as Array).is_empty():
		return f
	var out: Array = [{ "name": str(npc_entry.get("name", npc_entry.get("npc_name", "對方"))), "n": "1" }]
	var a: Variant = UiClient.row("npcs", str(npc_entry.get("id", ""))).get("attack", {})
	if a is Dictionary:
		for g in (a as Dictionary).get("group", []):
			if not (g is Dictionary):
				continue
			var cnt: Variant = g.get("count", [1, 1])
			var lo := int(cnt[0]) if cnt is Array and (cnt as Array).size() >= 2 else 1
			var hi := int(cnt[1]) if cnt is Array and (cnt as Array).size() >= 2 else 1
			if hi > 0:
				out.append({ "name": UiClient.name_of("monsters", str(g.get("monster", ""))), "n": str(lo) if lo == hi else "%d–%d" % [lo, hi] })
	return out

## 「孫婆婆、古墓弟子 ×5（共 6 人）」；只有一個人時回 ""
static func foes_text(foes: Array) -> String:
	if foes.size() <= 1:
		return ""
	var parts: PackedStringArray = []
	var total := 0
	var exact := true
	for f in foes:
		if not (f is Dictionary):
			continue
		var n := str(f.get("n", "1"))
		parts.append(str(f.get("name", "")) + ("" if n == "1" else " ×%s" % n))
		if n.is_valid_int():
			total += int(n)
		else:
			exact = false
	return "、".join(parts) + ("（共 %d 人）" % total if exact else "")

## 確認框內文（對手、善惡變化、城內官兵、善惡變負的後果、門派後果、CHALLENGE 說明）
static func confirm_text(npc_entry: Dictionary, sheet: Dictionary, view: Dictionary = {}, mode: String = MODE_ATTACK) -> String:
	var atk := atk_of(npc_entry)
	var nm := str(npc_entry.get("name", npc_entry.get("npc_name", "對方")))
	var lines: PackedStringArray = []
	var sid0 := str(atk.get("sect", ""))
	var foes := foes_text(foes_of(npc_entry))
	var challenge := str(atk.get("mode", "")) == MODE_CHALLENGE
	if mode == MODE_MIEPAI:
		# 滅派／硬闖：說清楚是跟整個門派的守山弟子動手，不是只打知客一個人（M3c 審查）
		var who := sect_label(sid0) if sid0 != "" else nm
		lines.append("確定要%s，跟%s動手嗎？" % [str(atk.get("menu_label", "滅派")), who])
	else:
		lines.append("確定要對%s動手嗎？" % nm)
	if foes != "":
		lines.append("・你要一個人面對：%s。" % foes)
		# M3c 第二輪審查：滅派／硬闖是一群人（新手單挑勝率 0%），提醒量力而為
		lines.append("・對方人多勢眾，量力而為。")
	# CHALLENGE（對方不會被殺死）：寫「對善良的人動手」，不寫「殺死」（M3c 審查：兩句互相矛盾）
	match str(atk.get("align", "")):
		"GOOD":
			lines.append("・對善良的人動手，善惡會下降、殺氣會上升。" if challenge else "・殺死善良的人，善惡會下降、殺氣會上升。")
		"EVIL":
			lines.append("・打退惡人，善惡會上升。" if challenge else "・殺死惡人，善惡會上升。")
		"NEUTRAL":
			lines.append("・對他動手，善惡會略為下降、殺氣會上升。" if challenge else "・殺了他，善惡會略為下降、殺氣會上升。")
	# M3c 第二輪審查：主機說官兵會放過這位新手（規則 newbie_guard_spare）時不寫官兵那句
	if str(atk.get("category", "")) in GUARD_CATEGORIES and not bool(atk.get("guard_spare", false)) 			and _city_with_guard(view if not view.is_empty() else UiClient.region_view()):
		lines.append("・這裡是城裡，得手之後會招來守城官兵。")
	# M3c 審查：善惡變負以後進出有官兵的城都會挨打（主機依新手保護算好 morality_guard；舊主機沒有時用實戰 500 估）
	var mg: Variant = atk.get("morality_guard", null)
	var warn_guard: bool = bool(mg) if mg != null else (str(atk.get("align", "")) in ["GOOD", "NEUTRAL"] and UiBuild.num(sheet.get("combat_xp", 0)) >= 500)
	if warn_guard:
		lines.append("・善惡一旦變成負的，每次進出有官兵把守的城，都會被官兵攻擊。")
	var sid := str(atk.get("sect", ""))
	var sname := sect_label(sid)
	match sect_effect(atk, sheet, mode):
		"BREACH":
			lines.append("・你是%s弟子，對同門動手會違反門規。" % sname)
		"BETRAY":
			lines.append("・對%s動手＝叛出%s（本門武功減半、成為公敵）。" % [nm, sname])
		"ENEMY":
			lines.append("・動手後你將成為%s公敵。" % sname)
	if challenge:
		lines.append("・打贏了對方只會敗走、不會死，後果照算。")   # M3c 第二輪審查：原句在確認框換行剩「算。」
	else:
		lines.append("・被殺的人會暫時消失，過一陣子才會再出現。")
	return "\n".join(lines)

## npc_menu.attack（{ ok, reason, label, warn }）→ NPC 對話框用的 npc_entry 形狀
static func entry_from_menu(menu: Dictionary, view: Dictionary = {}) -> Dictionary:
	var nid := str(menu.get("npc", ""))
	var e := { "id": nid, "name": str(menu.get("npc_name", nid)) }
	var row := UiClient.row("npcs", nid)
	var a: Variant = row.get("attack", {})
	var atk := {}
	if a is Dictionary:
		atk = { "mode": str(a.get("mode", "")), "category": str(a.get("category", "")), "sect": str(a.get("sect", "")),
			"menu_label": str(a.get("menu_label", "")) }
		var mrow := UiClient.row("monsters", str(a.get("monster", "")))
		atk["align"] = str(mrow.get("alignment", ""))
	var m: Variant = menu.get("attack", {})
	if m is Dictionary:
		if str(m.get("label", "")) != "":
			atk["menu_label"] = str(m["label"])
		if m.has("effect"):
			atk["effect"] = str(m["effect"])
		for k in ["foes", "morality_guard", "guard_spare"]:
			if m.has(k):
				atk[k] = m[k]
		if str(atk.get("sect", "")) == "" and str(m.get("sect_name", "")) != "":
			atk["sect_name"] = str(m["sect_name"])
	e["atk"] = atk
	if not view.is_empty():
		e["_view"] = true
	return e
