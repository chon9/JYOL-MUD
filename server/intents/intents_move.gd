class_name IntentsMove
extends RefCounted
## look move travel（M1_PLAN 3.6）

static func register(host: GameHost) -> void:
	host.register(Protocol.I_LOOK, func(s: Session, a: Dictionary) -> Dictionary: return look(host, s, a),
		GameHost.NEEDS_CHAR)
	host.register(Protocol.I_MOVE, func(s: Session, a: Dictionary) -> Dictionary:
		return host.regions.move(s, str(a["dir"])), GameHost.NEEDS_CHAR | GameHost.IDLE)
	host.register(Protocol.I_TRAVEL, func(s: Session, a: Dictionary) -> Dictionary:
		return host.npcs.travel(s, str(a["npc"]), str(a["dest"])), GameHost.NEEDS_CHAR | GameHost.IDLE)

## 查看（MUD 的 look）：把房間描述、出口、人物印進訊息欄，並重送畫面。
## 只重送畫面時面板內容沒變，玩家會以為按了沒反應。
## scout == true（玩家按「查看」；客戶端自動補畫面的 look 不帶）：在有遇敵表的房間另外偵察（ScoutSystem.on_look）。
static func look(host: GameHost, s: Session, a: Dictionary) -> Dictionary:
	var v := host.regions.view(s)
	var exits: Array = []
	for ex in v.get("exits", []):
		var t := "%s：%s" % [ex.get("label", ""), ex.get("to_name", "")]
		if bool(ex.get("locked", false)):
			t += "（不通）"
		exits.append(t)
	var who: Array = []
	for n in v.get("npcs", []):
		who.append(str(n.get("name", "")))
	for p in v.get("players", []):
		if int(p.get("peer", 0)) != s.peer_id:
			who.append(str(p.get("name", "")))
	host.ws.queue_event(s.peer_id, Protocol.CH_SCENE, Protocol.E_LOOK, {
		"room_name": str(v.get("room_name", "")),
		"desc": str(v.get("desc", "")),
		"exits": "、".join(exits) if not exits.is_empty() else "無",
		"who": "、".join(who) if not who.is_empty() else "沒有別人",
	})
	s.sheet_dirty = true
	s.view_dirty = true
	if bool(a.get("scout", false)) and host.scout != null:
		host.scout.on_look(s)
	return GameHost.ok()
