extends "res://tests/unit/test_world_fixture.gd"
## WP-PK 整合測試的共用基底（本檔沒有 test_ 方法）：test_world_pk.gd、test_world_corpse.gd 共用。
## 多玩家輔助來自 WP-HOST 的 test_world_fixture.gd（M2_PLAN 4.6.10）。這裡一律用 call() 呼叫，
## 讓本檔在那些輔助還沒合併時仍能載入；缺東西時 deps_ok() 讓測試以清楚的訊息失敗。

## 檢查 M2 整合測試需要的其他 WP 介面；缺少時記一筆失敗並回 false
func deps_ok(need_pvp := false) -> bool:
	if not game_ok():
		return false
	var missing: PackedStringArray = []
	for m in ["add_player", "send_as", "reason_as", "evs_for", "sheet_for", "view_for", "battle_open_for",
			"session_of", "goto_as"]:
		if not has_method(m):
			missing.append("fixture." + m + "（WP-HOST 4.6.10）")
	if host().get("pk") == null:
		missing.append("GameHost.pk（WP-HOST 4.6.1 接線）")
	if not ws.has_intent_handler("challenge"):
		missing.append("intents_pk 註冊（WP-HOST 4.6.1 M2_INTENTS）")
	if need_pvp and not host().battles.has_method("start_pvp"):
		missing.append("BattleSystem.start_pvp（WP-PARTY 4.6.2）")
	if not missing.is_empty():
		fail("M2 dependency missing: " + ", ".join(missing))
		return false
	return true

# ---------- 多玩家輔助（轉呼叫 fixture） ----------
func add(char_name: String, city := "xixia") -> int:
	return int(call("add_player", char_name, city))

func send_p(peer: int, kind: String, args: Dictionary = {}) -> Dictionary:
	return call("send_as", peer, kind, args)

func ok_p(peer: int, kind: String, args: Dictionary = {}) -> Dictionary:
	var r := send_p(peer, kind, args)
	assert_true(r.get("ok", false), "peer %d %s %s -> %s" % [peer, kind, str(args), str(r.get("reason", ""))])
	return r

func reason_p(peer: int, kind: String, args: Dictionary = {}) -> String:
	return str(call("reason_as", peer, kind, args))

func evs_p(peer: int, key: String) -> Array:
	return call("evs_for", peer, key)

func lastp_p(peer: int, key: String) -> Dictionary:
	var a := evs_p(peer, key)
	return a[a.size() - 1].get("p", {}) if not a.is_empty() else {}

## 讓別人（非發話者）的 dirty 角色表／房間視圖照 0.25 秒節流送出
func settle() -> void:
	ws.advance(0.3)

func sheet_p(peer: int) -> Dictionary:
	return call("sheet_for", peer)

func view_p(peer: int) -> Dictionary:
	return call("view_for", peer)

func bopen_p(peer: int) -> Dictionary:
	return call("battle_open_for", peer)

func sess(peer: int) -> Session:
	return call("session_of", peer)

func chr(peer: int):
	return sess(peer).character

func cid(peer: int) -> String:
	return str(chr(peer).id)

func goto_p(peer: int, room: String) -> void:
	call("goto_as", peer, room)

# ---------- 角色調整 ----------
func make_strong_p(peer: int) -> void:
	var c = chr(peer)
	for a in ["str", "agi", "con", "guts", "cal"]:
		c.attrs[a] = 150
	for sk in ["basic_fist", "basic_blade", "basic_dodge", "basic_parry"]:
		c.skills.set_level(sk, 80, tables())
	c.combat_xp = maxi(int(c.combat_xp), 5000)
	c.clamp_vitals(tables(), ws.options)
	Survival.rest_full(c, tables(), ws.options)

func make_weak_p(peer: int, qi := 1) -> void:
	var c = chr(peer)
	c.vitals["qi"] = qi

# ---------- 戰鬥驅動 ----------
func _unit_of(b, peer: int):
	for u in b.units:
		if int(u.peer) == peer:
			return u
	return null

func _cmd_for(b, me, policy: String) -> Dictionary:
	if me == null or policy == "defend":
		return { "cmd": "DEFEND" }
	if policy == "rest":
		return { "cmd": "REST" }
	var enemies: Array = []
	for u in b.units:
		if int(u.side) != int(me.side) and u.is_active():
			enemies.append(u)
	for e in enemies:
		if _dist(me.pos, e.pos) == 1:
			return { "cmd": "ATTACK", "target": [e.pos.x, e.pos.y] }
	var best: Vector2i = me.pos
	var best_d := 999
	for e in enemies:
		best_d = mini(best_d, _dist(me.pos, e.pos))
	for p in b.grid.reachable(me.pos, BattleFormulas.move_range(me)):
		for e in enemies:
			var d := _dist(p, e.pos)
			if d < best_d:
				best_d = d
				best = p
	if best != me.pos:
		return { "cmd": "MOVE", "target": [best.x, best.y] }
	return { "cmd": "DEFEND" }

## 驅動一場戰鬥到結束：policies = { peer: "fight" | "defend" }（主機座標；不經 UI 鏡像）
func drive_bid(bid: int, policies: Dictionary, max_s := 900.0) -> bool:
	var t := 0.0
	while host().battles.active.has(bid) and t < max_s:
		var b = host().battles.active[bid]["battle"]
		for peer in policies:
			var u = _unit_of(b, int(peer))
			if u != null and str(u.state) == "READY" and not b.is_over():
				var cmd := _cmd_for(b, u, str(policies[peer]))
				cmd["battle_id"] = bid
				var r := send_p(int(peer), "battle_cmd", cmd)
				if not r.get("ok", false):
					send_p(int(peer), "battle_cmd", { "battle_id": bid, "cmd": "DEFEND" })
		ws.advance(0.1)
		t += 0.1
	return assert_false(host().battles.active.has(bid), "battle %d should end within %d s" % [bid, int(max_s)])

## 推進一場戰鬥 secs 秒（不要求結束）
func drive_for(bid: int, policies: Dictionary, secs: float) -> void:
	var t := 0.0
	while host().battles.active.has(bid) and t < secs:
		var b = host().battles.active[bid]["battle"]
		for peer in policies:
			var u = _unit_of(b, int(peer))
			if u != null and str(u.state) == "READY" and not b.is_over():
				var cmd := _cmd_for(b, u, str(policies[peer]))
				cmd["battle_id"] = bid
				var r := send_p(int(peer), "battle_cmd", cmd)
				if not r.get("ok", false):
					send_p(int(peer), "battle_cmd", { "battle_id": bid, "cmd": "DEFEND" })
		ws.advance(0.1)
		t += 0.1

func active_kind(peer: int) -> String:
	var s := sess(peer)
	if s == null or s.battle_id == 0:
		return ""
	return str(host().battles.active.get(s.battle_id, {}).get("kind", ""))
