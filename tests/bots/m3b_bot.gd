extends "res://tests/bots/story_bot.gd"
## M3b 驗收 bot（M3B_PLAN §11.3）：一個「玩家」的驅動器，由 tools/m3b_acceptance.gd 的 worker 在同一行程裡建立。
## 沿用故事驗收 bot（tests/bots/story_bot.gd）的作法：WorldServer 是真的主機（GameHost、全部系統、--debug-intents），
## 玩家是假的遠端 peer，所有動作都經 WorldServer.handle_intent；走路用區域圖 BFS 一步一步 move（不 teleport）。
## 這裡只加 M3b 劇本要用的小工具：事件查詢、物品 uid、兩人同行、兩名玩家的對戰驅動、重開主機後重新選角。
## debug_set 只用來設屬性、實戰、銀兩、名聲、歷練、技能等級、時辰快轉（§11.3）；
## 兩個測試捷徑（和故事 bot 的 setup.sect 同一類）：門派直接寫角色（丐幫保鏢被拒的旁證角色）、ws.options 改伺服器選項
## （主機在伺服器設定面板能改的同一份）。

## 從第 n0 個事件起，key 相符的事件
func evs(key: String, n0 := 0) -> Array:
	var out: Array = []
	for i in range(clampi(n0, 0, events.size()), events.size()):
		if str(events[i].get("key", "")) == key:
			out.append(events[i])
	return out

func last_ev(key: String, n0 := 0) -> Dictionary:
	var a := evs(key, n0)
	return a[a.size() - 1] if not a.is_empty() else {}

func mark() -> int:
	return events.size()

func uid_of(item_id: String) -> String:
	for it in ch().inventory.items:
		if str(it.get("id", "")) == item_id:
			return str(it.get("uid", ""))
	return ""

func region() -> String:
	return host().index.region_of(room())

func expect(cond: bool, msg: String) -> bool:
	return true if cond else fail(msg)

## 期望 intent 失敗、原因相符
func expect_reason(kind: String, args: Dictionary, want: String) -> bool:
	var r := send(kind, args)
	if r.get("ok", false):
		return fail("%s %s: expected %s, got ok" % [kind, JSON.stringify(args), want])
	return expect(str(r.get("reason", "")) == want, "%s %s: reason %s, want %s" % [kind, JSON.stringify(args),
		str(r.get("reason", "")), want])

## 兩人同行（組隊護送）：每一步 self 先走、other 跟著走同一個方向（路上不遇敵：劇本關掉 encounters_enabled）
func walk_with(other, target: String) -> bool:
	if not host().index.has_room(target):
		return fail("walk_with: unknown room " + target)
	var steps := 0
	while room() != target:
		if err != "" or other.err != "":
			return false
		var p := path_to(target)
		if p.is_empty():
			break
		if str(p[0]) == "?":
			return fail("walk_with: no path %s -> %s" % [room(), target])
		if not must("move", { "dir": str(p[0]) }):
			return false
		if other.room() != room():
			var r2: Dictionary = other.send("move", { "dir": str(p[0]) })
			if not r2.get("ok", false):
				return fail("partner move %s -> %s" % [str(p[0]), str(r2.get("reason", ""))])
		steps += 1
		moves += 1
		if steps > MAX_WALK_STEPS:
			return fail("walk_with: too many steps")
		advance(0.2)
		if other.room() != room():
			return fail("walk_with: partner at %s, me at %s" % [other.room(), room()])
		for b in [self, other]:
			var c = b.ch()
			if int(c.vitals.get("food", 0)) < 30 or int(c.vitals.get("water", 0)) < 30:
				b.refill()
	return true

## 兩名玩家（或更多）在同一場戰鬥：每個 tick 對每個 bot 依自己的策略下指令，直到戰鬥結束
static func drive_pvp(ws_node: Node, bots: Array, policies: Array, max_ticks := 30000) -> bool:
	var ticks := 0
	while ticks < max_ticks:
		var any := false
		for i in bots.size():
			if bots[i].battle_tick(str(policies[i])):
				any = true
		if not any:
			break
		ws_node.advance(0.1)
		ticks += 1
	ws_node.advance(0.5)
	return ticks < max_ticks

## 存檔 → 關主機 → 同一世界重開 → 每個 bot 重新連線並選回自己的角色
static func reload_world(ws_node: Node, bots: Array) -> String:
	var wid: String = ws_node.world_id
	ws_node.save_now()
	ws_node.stop()
	if ws_node.start(wid) != OK:
		return "restart world failed: " + str(ws_node.last_error)
	for b in bots:
		b.events.clear()
		if not b.reselect():
			return "reselect %s: %s" % [b.pname, b.err]
	ws_node.advance(0.3)
	for b in bots:
		b.flush_view()
	return ""

## 讓時間跨過下一個指定時辰的起點（debug hour；若現在已在該時辰，先撥到下一個時辰再回來）
func to_next_shichen(name: String) -> bool:
	var cur := str(host().clock().get("shichen_name", ""))
	if cur == name:
		var idx: int = WorldClock.SHICHEN.find(name)
		if not debug("hour", WorldClock.SHICHEN[(idx + 1) % 12]):
			return false
	var ok := debug("hour", name)
	advance(0.5)
	return ok

## 角色表（sheet_for 的最新版本）
func fresh_sheet() -> Dictionary:
	s().sheet_dirty = true
	flush_view()
	return sheet
