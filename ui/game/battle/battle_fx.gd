class_name BattleFx
extends Node2D
## 戰場特效層：飄字（傷害、爆擊、「閃」、「調息」、補氣、狀態）、盾牌圖示、打擊火花。
## 位置跟著單位（每幀依 BattleIsoView 的投影重算），所以視窗縮放時不會飄走。
## 有 fx_hit／fx_slash／fx_palm 圖就用圖，沒有就用程式畫。全部只是顯示，不阻擋任何輸入。

const DMG_COLOR := Color("ffd23a")        # 敵方受傷（金）
const DMG_TAKEN_COLOR := Color("ff4632")  # 我方受傷（紅）
const CRIT_COLOR := Color("ff7a12")
const MISS_COLOR := Color("ffffff")
const REST_COLOR := Color("8affd6")
const HEAL_COLOR := Color("7dff6e")
const WOUND_COLOR := Color("e2a8ff")
const STATUS_COLOR := Color("ffe066")
const OUTLINE := Color(0.06, 0.035, 0.02, 1.0)
const POPUP_DUR := 0.95
const WORD_DUR := 0.85                    # 「調息」「閃」等字：短一點，不拖到下一次交手
const WORD_PLATE := Color(0.05, 0.035, 0.02, 0.62)
const NAME_GAP := 2.0
const POPUP_GAP := 3.0
const SUPERSEDE_FADE := 0.15             # 同一人的新飄字出現後，舊的在這麼久內淡掉（一個人頭上同時只有一個字）
const DROP_FADE := 0.12                  # 結果視窗出現時，還在播的飄字在這麼久內淡掉
const END_LINGER := 0.6                  # 戰鬥結束後飄字最多再留這麼久（不會留到勝利／戰敗畫面還掛著）

var view: BattleIsoView
var items: Array = []              # { type, sprite, start, dur, ... }
var end_at := -1.0                 # 第一次看到 vm.ended 的時間

static var _tex_cache: Dictionary = {}

## 選用的特效圖（tile_escape、fx_hit…）：經 ArtRegistry 查（正式圖 → 暫代圖）；沒有回 null
static func optional_texture(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		_tex_cache[name] = ArtRegistry.fx_texture(name)
	return _tex_cache[name]

## 事件 key → 打擊特效種類：刀劍用 slash，招式（拳掌內力）用 palm，其他用 hit
static func burst_kind(key: String) -> String:
	if key.contains("blade") or key.contains("sword"):
		return "fx_slash"
	if key.begins_with("move_") or key.contains("fist") or key.contains("palm"):
		return "fx_palm"
	return "fx_hit"

func clear() -> void:
	items.clear()
	end_at = -1.0
	closed = false
	queue_redraw()

## 結果小條出來了：所有飄字（數字與字）立刻拿掉，之後到的事件也不再飄字（審查 round 4：勝利畫面還掛著 -19、-5）
var closed := false

func close_popups() -> void:
	closed = true
	items = items.filter(func(it): return str(it["type"]) != "text")
	queue_redraw()

## 還沒開始的特效全部丟掉、已經在播的很快淡掉（戰鬥結束時，排在後面的飄字不再一個個疊上來，結果畫面不留數字）
func drop_pending() -> void:
	var now := _now()
	items = items.filter(func(it): return float(it["start"]) <= now)
	for it in items:
		var left := float(it["start"]) + float(it["dur"]) - now
		if left > DROP_FADE:
			# 直接跳到淡出段：t 從 0.7 開始（見 _draw 的 alpha），在 DROP_FADE 內淡完
			var d := DROP_FADE / 0.3
			it["start"] = now - 0.7 * d
			it["dur"] = d
	queue_redraw()

func _now() -> float:
	return BattleIsoView.now_s()

## M3c 審查：戰鬥結束時，還排在後面（動畫佇列）的武器特效一律拉到現在依序播（每個隔 0.08 秒），
## 不然最後一擊的特效排在一秒後、結果框與「倒下」已經先出來（或被截短成 0 秒根本看不到）
func compress_weapon_fx() -> void:
	var now := _now()
	var later: Array = []
	for it in items:
		if str(it.get("type", "")) == "weapon" and float(it["start"]) > now:
			later.append(it)
	later.sort_custom(func(a, b): return float(a["start"]) < float(b["start"]))
	for i in later.size():
		later[i]["start"] = now + 0.08 * i

## M3c 審查：還在播（或還沒開始）的武器特效最晚什麼時候結束（距現在秒數；沒有＝0）。戰鬥結果框等最後一擊播完才出來
const WEAPON_HP_PLATE := 0.35

## 現在有武器特效正在畫（alpha > 0）的出招者
func weapon_fx_sprites(now: float) -> Array:
	var out: Array = []
	for it in items:
		if str(it["type"]) == "weapon" and WeaponFx.alpha_at(now - float(it["start"])) > 0.0 and is_instance_valid(it["sprite"]):
			if not out.has(it["sprite"]):
				out.append(it["sprite"])
	return out

func weapon_fx_left() -> float:
	var now := _now()
	var left := 0.0
	for it in items:
		if str(it.get("type", "")) == "weapon":
			left = maxf(left, float(it["start"]) + float(it["dur"]) - now)
	return maxf(0.0, left)

## 單位頭上飄字；size 是相對大小（爆擊 1.6）
func popup(s: UnitSprite, text: String, color: Color, size: float, delay: float) -> void:
	if text == "" or closed:
		return
	# 同時出現的飄字（同一人或相鄰兩人）在 _draw 每幀排開，不會疊在一起或蓋到名字牌
	items.append({ "type": "text", "sprite": s, "start": _now() + maxf(0.0, delay),
		"dur": POPUP_DUR if BattleFx.is_number(text) else WORD_DUR, "text": text, "color": color, "size": size })

## 拿掉已經出現的字（閃、防禦、調息…；數字不動）：s = null 時全部。
## 輪到我下令時，上一手留下的「防禦／調息」跟頭上黃菱形、名字牌疊成三層（審查 round 3）；戰鬥結束後也不留孤零零的「閃」
func drop_words(s: UnitSprite = null, pending_too := false) -> void:
	var now := _now()
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		var started := pending_too or float(it["start"]) <= now
		if str(it["type"]) == "text" and not BattleFx.is_number(str(it["text"])) and started and (s == null or it["sprite"] == s):
			items.remove_at(i)
	queue_redraw()

## 數字飄字（-12、+5、-30!）；其他是字（閃、調息、狀態名），底下墊深色牌子
static func is_number(text: String) -> bool:
	return text.begins_with("-") or text.begins_with("+")

func shield(s: UnitSprite, delay: float) -> void:
	items.append({ "type": "shield", "sprite": s, "start": _now() + maxf(0.0, delay), "dur": 0.9 })

func burst(s: UnitSprite, kind: String, delay: float) -> void:
	items.append({ "type": "burst", "sprite": s, "start": _now() + maxf(0.0, delay), "dur": 0.28,
		"tex": BattleFx.optional_texture(kind), "kind": kind })

## ---------------------------------------------------------------- M3c WP-FX：武器出招特效（M3C_PLAN §7.3）
## 一筆 { type: "weapon", sprite: 攻擊者, target: 守方, kind, miss, start, dur }；位置每幀依兩人目前的位置重算。
## impact_delay = 命中的時間（距現在秒數）：命中前 WeaponFx.LEAD 秒出現。kind 見 WeaponFx.kind_for
## medic 畫在守方身上（sprite = 守方）、formation 畫在施術者腳下（target = null）
func weapon(att: UnitSprite, def: UnitSprite, kind: String, impact_delay: float, miss := false) -> void:
	if kind == "" or (att == null and def == null):
		return
	var who: UnitSprite = att if att != null else def
	items.append({ "type": "weapon", "sprite": who, "target": def, "kind": kind, "miss": miss,
		"start": _now() + maxf(0.0, impact_delay - WeaponFx.LEAD), "dur": WeaponFx.DUR })

## 測試／畫圖共用：特效項目目前的幾何（WeaponFx.geometry；守方不在時朝面向畫一格長）
func weapon_geom(it: Dictionary) -> Dictionary:
	var a: UnitSprite = it["sprite"]
	var d: UnitSprite = it.get("target", null) if is_instance_valid(it.get("target", null)) else null
	var tw := view.tile_w if view != null else 64.0
	var feet := a.position + a.anim_offset
	var target := feet + Vector2(tw * (1.0 if a.facing_right else -1.0), -a.figure_height() * WeaponFx.HAND_Y)
	if d != null and d != a:
		# M3c 第二輪審查：身體中心用「現在」的身高（倒下的人、躺平的獸很矮）；以前用站著的身高，
		# 打倒在地的野兔時落點在半空、看起來打在自己腳上
		target = d.position + d.anim_offset + Vector2(0, -d.body_top() * 0.5)
	var facing := 1.0 if target.x > feet.x + 0.5 else (-1.0 if target.x < feet.x - 0.5 else (1.0 if a.facing_right else -1.0))
	return WeaponFx.geometry(feet, a.figure_width(), a.figure_height(), target, tw, facing)

var _glow: RID                     # 加法混色的子 canvas item（不是節點；武器特效的光暈）
var _glow_mat: CanvasItemMaterial

func _ensure_glow() -> RID:
	if not _glow.is_valid():
		_glow = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(_glow, get_canvas_item())
		RenderingServer.canvas_item_set_draw_behind_parent(_glow, true)   # 光暈在名字牌、飄字下面（仍在人物之上）
		_glow_mat = CanvasItemMaterial.new()
		_glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		RenderingServer.canvas_item_set_material(_glow, _glow_mat.get_rid())
	return _glow

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _glow.is_valid():
		RenderingServer.free_rid(_glow)
		_glow = RID()

func _draw_weapon_fx(now: float) -> void:
	var glow := _ensure_glow()
	RenderingServer.canvas_item_clear(glow)
	var ci := get_canvas_item()
	var tw := view.tile_w
	for it in items:
		if str(it["type"]) != "weapon":
			continue
		var t := now - float(it["start"])
		var a := WeaponFx.alpha_at(t)
		if a <= 0.0:
			continue
		if bool(it.get("miss", false)):
			a *= WeaponFx.MISS_ALPHA
		var s: UnitSprite = it["sprite"]
		var kind := str(it["kind"])
		match WeaponFx.placement(kind):
			"target":
				var feet := s.position + s.anim_offset
				var fh := s.figure_height()
				WeaponFx.draw_medic(ci, glow, feet + Vector2(0, -fh * 0.5), fh, tw, t, a)
			"ground":
				WeaponFx.draw_formation(ci, glow, s.position + s.anim_offset, tw, t, a)
			_:
				WeaponFx.draw_strike(ci, glow, kind, weapon_geom(it), t, a)

func _process(_delta: float) -> void:
	var now := _now()
	if view != null and view.vm != null and view.vm.ended:
		if end_at < 0.0:
			end_at = now
			drop_words(null, true)
		var cap := end_at + END_LINGER
		for it in items:
			if str(it["type"]) == "weapon":
				continue   # M3c 審查：武器特效由 compress_weapon_fx 拉到現在、結果框等它播完（本身最長 0.28 秒）
			if float(it["start"]) + float(it["dur"]) > cap:
				it["dur"] = maxf(0.0, cap - float(it["start"]))
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		if now > float(it["start"]) + float(it["dur"]) or not is_instance_valid(it["sprite"]):
			items.remove_at(i)
		elif str(it["type"]) == "weapon" and it.get("target", null) != null and not is_instance_valid(it["target"]):
			it["target"] = null
	queue_redraw()

func _draw() -> void:
	if view == null:
		return
	var now := _now()
	var tw := view.tile_w
	var font := UnitSprite.ui_font()
	# 名字牌與氣條：畫在所有人物之上；名字牌互相重疊時，後排的往上推
	var labelled: Array = view.sprites.values()
	labelled.sort_custom(func(a, b): return (a as UnitSprite).depth < (b as UnitSprite).depth)
	_reserve_badges(labelled)
	var bodies := BattleFx.layout_names_with_hp(labelled, view.damage_text)
	_draw_escape_badges(font)
	_draw_corpse_badges(font)
	_draw_status_badges(font)
	_draw_target_marks()
	_draw_turn_flash()
	# M3c WP-FX：武器特效在人物之上、名字牌之下。M3c 審查曾把它放到腰間氣值小條（780/780）之上（起點才不會被蓋住），
	# 第三輪審查：那樣出招的 0.3 秒內數字被特效蓋住（124_m3c_weapon_fx_fist）→ 小條畫回特效上面，
	# 但出招者的小條底板變淡（WEAPON_HP_PLATE），特效起點透得出來
	_draw_weapon_fx(now)
	var striking := weapon_fx_sprites(now)
	for s in labelled:
		(s as UnitSprite).draw_hp_text(self, WEAPON_HP_PLATE if striking.has(s) else 1.0)
	for s in labelled:
		(s as UnitSprite).draw_bars(self, (s as UnitSprite).position)
	var taken: Array = []          # 已經佔用的框（名字牌＋已排好的飄字）
	for s in labelled:
		if (s as UnitSprite).shows_label():
			(s as UnitSprite).draw_name_plate(self, (s as UnitSprite).name_box)
			if (s as UnitSprite).name_box.size != Vector2.ZERO:
				taken.append((s as UnitSprite).name_box)
				_draw_weapon_icon(s as UnitSprite, font)
		var bar := (s as UnitSprite).bar_rect((s as UnitSprite).position)
		if bar.size != Vector2.ZERO:
			taken.append(bar)
		if not (s as UnitSprite).hp_line and (s as UnitSprite).shows_label():
			var hr := (s as UnitSprite).waist_hp_rect()
			if hr.size != Vector2.ZERO:
				taken.append(hr)   # 腰部損血字也佔位：飄字不會蓋在上面
	# 每個人最新一個已出現的飄字；更早的在 SUPERSEDE_FADE 內淡掉，不往上疊成一根柱子
	var latest: Dictionary = {}
	for it in items:
		if str(it["type"]) == "text" and float(it["start"]) <= now and is_instance_valid(it["sprite"]):
			var k := (it["sprite"] as Object).get_instance_id()
			latest[k] = maxf(float(latest.get(k, -INF)), float(it["start"]))
	for it in items:
		if float(it["dur"]) <= 0.0:
			continue
		var t := (now - float(it["start"])) / float(it["dur"])
		if t < 0.0 or t > 1.0:
			continue
		var s: UnitSprite = it["sprite"]
		var fade := 1.0
		if str(it["type"]) == "text":
			var newest := float(latest.get(s.get_instance_id(), float(it["start"])))
			if float(it["start"]) < newest:
				fade = 1.0 - (now - newest) / SUPERSEDE_FADE
				if fade <= 0.0:
					continue
		var feet := view.grid_to_local(s.gpos) + s.anim_offset
		var above := feet + Vector2(0, -s.label_top())
		if s.name_box.size != Vector2.ZERO and s.name_box.end.y <= feet.y:
			above = Vector2(s.name_box.get_center().x, s.name_box.position.y)
		elif s.vis_state != "ALIVE":
			above = feet + Vector2(0, -s.body_top() - 4.0)   # 倒下的、名字牌在屍體下面或沒畫：從屍體上方飄
		match str(it["type"]):
			"weapon":
				pass   # 已在 _draw_weapon_fx 畫好
			"text":
				if font == null:
					continue
				# 從自己的名字牌正上方彈出、只升一小段（不會飄到別人身上或離身體太遠）
				# 飄字小一點（14 起）、不彈跳（AUTHENTIC_UI_SPEC §12.1）
				var fs0 := int(clampf(tw * 0.2, 14.0, 22.0) * float(it["size"]))
				var rise := tw * 0.2 * (1.0 - pow(1.0 - t, 2.0))
				var pop := 1.0
				var fs := int(fs0 * pop)
				var a := (1.0 if t < 0.7 else 1.0 - (t - 0.7) / 0.3) * fade
				var txt := str(it["text"])
				var ow := maxi(5, fs / 4)
				# 位置用不放大的字算一次就記住（之後只往上升一點），不會每幀跳來跳去；
				# 名字牌後來移動（例如有人倒下）而壓到別的字時才重新找位置
				if it.has("off") and fade >= 1.0:
					var rel0: Rect2 = it["box_rel"]
					if BattleFx._overlaps(Rect2(above + rel0.position, rel0.size), taken):
						it.erase("off")
				if not it.has("off"):
					var w0 := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs0).x
					var others: Array = []
					for b in bodies:
						if b[0] != s:
							others.append(b[1])
					var base := BattleFx.popup_base(above, w0, fs0, maxi(5, fs0 / 4))
					var at := BattleFx.place_popup(base, w0, fs0, maxi(5, fs0 / 4), signf(above.x - BattleFx.nearest_x(s, bodies)), taken, others,
						Rect2(Vector2.ZERO, view.size), s.name_box.size.x)
					it["off"] = at - above + Vector2(w0 / 2.0, 0)
					var b0 := BattleFx.popup_box(at, w0, fs0, maxi(5, fs0 / 4))
					it["box_rel"] = Rect2(b0.position - above, b0.size)
				var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var p := above + (it["off"] as Vector2) + Vector2(-w / 2.0, -rise)
				var box := BattleFx.popup_box(p, w, fs, ow)
				if fade >= 1.0:
					var rel: Rect2 = it["box_rel"]
					taken.append(Rect2(above + rel.position, rel.size))   # 佔住起始位置（後來的字不會放到這裡）
				if not BattleFx.is_number(txt):
					var sb := StyleBoxFlat.new()
					sb.bg_color = Color(WORD_PLATE, WORD_PLATE.a * a)
					sb.set_corner_radius_all(int(box.size.y / 2.0))
					draw_style_box(sb, box)
				draw_string_outline(font, p + Vector2(1.5, 2.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ow, Color(0, 0, 0, 0.45 * a))
				draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ow, Color(OUTLINE, OUTLINE.a * a))
				draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(it["color"], a))
			"shield":
				# 防守的盾牌只畫在還站著的人身上：逃走（站上逃跑格先「防」一下再逃）或倒下的人，
				# 盾牌留在原地就變成逃跑格上一面沒有意義的灰盾（審查）
				if s.vis_state == "ALIVE" and s.modulate.a >= 0.3 and not (view.vm != null and view.vm.ended):
					var front := Vector2(tw * (0.22 if s.facing_right else -0.22), -s.figure_height() * 0.45)
					_draw_shield(feet + front, tw * 0.26 * (1.0 + 0.25 * maxf(0.0, 1.0 - t * 5.0)), 1.0 if t < 0.6 else 1.0 - (t - 0.6) / 0.4)
			"burst":
				var center := feet + Vector2(0, -s.figure_height() * 0.5)
				var tex: Texture2D = it["tex"]
				var a2 := 1.0 - t
				if tex != null:
					var sz := tw * (0.7 + 0.5 * t)
					draw_texture_rect(tex, Rect2(center - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), false, Color(1, 1, 1, a2))
				else:
					_draw_spark(center, tw * (0.15 + 0.4 * t), a2, str(it["kind"]))

## 有人站著（或躺著）的逃跑格：格子被人擋住，在格子右角補一個小「逃」牌（畫在人物上面）
func _draw_escape_badges(font: Font) -> void:
	if view.vm == null or font == null:
		return
	var tw := view.tile_w
	var occupied := {}
	for s in view.sprites.values():
		var sp := s as UnitSprite
		if sp.vis_state != "FLED" and sp.visible:   # 屍體躺在逃跑格上也補牌子（不然只露出一角金邊）
			occupied[Vector2i(roundi(sp.gpos.x), roundi(sp.gpos.y))] = true
	var pulse := 0.5 + 0.5 * sin(_now() * 3.0)
	for c in view.vm.escape:
		if not occupied.has(c):
			continue
		var fs := int(clampf(tw * 0.16, 11.0, 20.0))
		var r := fs * 0.75
		# 右角、左角、上角、下角依序挑第一個不壓到名字牌的（審查 round 4：屍體躺在逃跑格上，「逃」章壓在「野兔　倒下」牌右端）
		var base := view.grid_to_local(Vector2(c))
		var center := base + Vector2(tw * 0.36, -tw * 0.02)
		for off in [Vector2(tw * 0.36, -tw * 0.02), Vector2(-tw * 0.36, -tw * 0.02), Vector2(0, -tw * 0.2), Vector2(0, tw * 0.2)]:
			var cand: Vector2 = base + off
			var box := Rect2(cand - Vector2(r + 2.0, r + 2.0), Vector2(r + 2.0, r + 2.0) * 2.0)
			var hit := false
			for s2 in view.sprites.values():
				var nb: Rect2 = (s2 as UnitSprite).name_box
				if (s2 as UnitSprite).shows_label() and nb.size != Vector2.ZERO and nb.intersects(box):
					hit = true
					break
			if not hit:
				center = cand
				break
		draw_circle(center, r + 2.0, Color(0.25, 0.12, 0.0, 0.85))
		draw_circle(center, r, Color(1.0, 0.8, 0.2, 0.85 + 0.15 * pulse))
		var w := font.get_string_size("逃", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, center + Vector2(-w / 2.0, fs * 0.36), "逃", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, BattleIsoView.ESCAPE_INK)

## 倒下的單位：在屍體那一格的前角畫一個「倒」字牌（畫在所有人物上面），被別人擋住也找得到誰倒在哪裡
func _draw_corpse_badges(font: Font) -> void:
	if view.vm == null or font == null:
		return
	var tw := view.tile_w
	for s in view.sprites.values():
		var sp := s as UnitSprite
		if sp.vis_state != "DEAD" or not sp.visible:
			continue
		# 名字牌已經寫「○○　倒下」：不再另畫一個「倒」字章疊在牌子左端（審查 round 4：一具屍體兩個「倒」）
		if sp.shows_label() and sp.name_box.size != Vector2.ZERO:
			continue
		var center := sp.position + Vector2(-tw * 0.3, tw * 0.06)
		var fs := int(clampf(tw * 0.16, 11.0, 18.0))
		var r := fs * 0.72
		draw_circle(center, r + 2.0, Color(0.1, 0.0, 0.0, 0.9))
		draw_circle(center, r, UiTheme.JY_RED if sp.ally else Color("8a8070"))
		var w := font.get_string_size("倒", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, center + Vector2(-w / 2.0, fs * 0.36), "倒", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

## 狀態圖示（M3A_PLAN §7.5）：活著的單位一排小圓章，底色＝狀態 color、字＝glyph（中毒「毒」綠、封穴「穴」…）。
## 圓章直徑約 19 px，畫在**自己名字牌裡的左端**（名字牌為它加寬，BattleFx._reserve_badges），一看就知道是誰的；
## 沒有名字牌時放頭頂（M3a UI 審查 #5：以前浮在「無效」字與名字牌之間，分不出是誰的）
const BADGE_R := 9.5
const BADGE_FONT := 14
const BADGE_STEP := BADGE_R * 2.0 + 2.0

static func badge_room(n: int) -> float:
	return 0.0 if n <= 0 else n * BADGE_STEP + 2.0

## 名字牌左邊留出圓章的寬度（排版前呼叫）；M3c WP-FX：最左邊再留武器小圖示的位置
func _reserve_badges(list: Array) -> void:
	for s in list:
		var sp := s as UnitSprite
		var n := 0
		if view.vm != null and sp.vis_state == "ALIVE" and sp.visible:
			n = (view.vm.unit_statuses(sp.uid) as Array).size()
			sp.weapon_kind = WeaponFx.icon_kind(view.vm.unit(sp.uid), sp.is_humanoid())
		else:
			sp.weapon_kind = ""
		sp.badge_w = sp.icon_room() + BattleFx.badge_room(n)

## 名牌武器小圖示：名字牌左端、名字那一列置中（M3C_PLAN §7.3）
static func icon_center(name_box: Rect2, name_h: float) -> Vector2:
	return Vector2(name_box.position.x + 3.0 + WeaponFx.ICON_SIZE / 2.0, name_box.position.y + maxf(WeaponFx.ICON_SIZE / 2.0, name_h / 2.0))

func _draw_weapon_icon(sp: UnitSprite, font: Font) -> void:
	if sp.icon_room() <= 0.0 or sp.vis_state != "ALIVE":
		return
	WeaponFx.draw_icon(self, sp.weapon_kind, BattleFx.icon_center(sp.name_box, sp.plate_name_h(sp.name_box)), font, sp.modulate.a)

## 第 i 個圓章的圓心：名字牌左端、名字那一列置中；沒有名字牌 → 頭頂上方置中
static func badge_center(name_box: Rect2, name_h: float, head_top: Vector2, i: int, n: int) -> Vector2:
	if name_box.size != Vector2.ZERO:
		return Vector2(name_box.position.x + 3.0 + BADGE_R + i * BADGE_STEP, name_box.position.y + maxf(BADGE_R, name_h / 2.0))
	return Vector2(head_top.x - BADGE_STEP * (n - 1) / 2.0 + i * BADGE_STEP, head_top.y - BADGE_R - 2.0)

func _draw_status_badges(font: Font) -> void:
	if view.vm == null or font == null:
		return
	for s in view.sprites.values():
		var sp := s as UnitSprite
		if sp.vis_state != "ALIVE" or not sp.visible:
			continue
		var sts := view.vm.unit_statuses(sp.uid)
		if sts.is_empty():
			continue
		var head := Vector2(sp.position.x, sp.position.y - sp.label_top())
		for i in sts.size():
			var st: Dictionary = sts[i]
			var c := BattleFx.badge_center(sp.name_box, sp.plate_name_h(sp.name_box), head, i, sts.size()) + Vector2(sp.icon_room() if sp.name_box.size != Vector2.ZERO else 0.0, 0)
			draw_circle(c, BADGE_R + 1.5, Color(0, 0, 0, 0.85))
			draw_circle(c, BADGE_R, Color.from_string(str(st.get("color", "#c0c0c0")), Color("c0c0c0")))
			var g := str(st.get("glyph", "?")).left(1)
			var gw := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT).x
			draw_string_outline(font, c + Vector2(-gw / 2.0, BADGE_FONT * 0.36), g, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT, 3, Color(0, 0, 0, 0.9))
			draw_string(font, c + Vector2(-gw / 2.0, BADGE_FONT * 0.36), g, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FONT, Color.WHITE)

## 輪到我：頭上（名字牌上方）閃三次黃色菱形
func _draw_turn_flash() -> void:
	var now := _now()
	if view.vm == null or now > view.turn_flash_until:
		return
	var me: UnitSprite = view.sprites.get(view.vm.my_uid, null)
	if me == null or me.vis_state != "ALIVE":
		return
	var left := view.turn_flash_until - now
	var phase := fmod(BattleIsoView.TURN_FLASH_S - left, BattleIsoView.TURN_FLASH_S / 3.0) / (BattleIsoView.TURN_FLASH_S / 3.0)
	if phase > 0.6:
		return
	var tw := view.tile_w
	var top := me.name_box.position.y if me.name_box.size != Vector2.ZERO else me.position.y - me.label_top()
	var c := Vector2(me.position.x, top - tw * 0.12)
	var r := tw * 0.1
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)])
	draw_colored_polygon(pts, Color(1.0, 0.9, 0.2, 0.95))
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color(0.3, 0.2, 0.0, 0.9), 1.5, true)

## 按「攻／武」選目標時：可打的敵人頭上（名字牌上方）一個上下跳的紅色箭頭——高亮格大多被敵人身體擋住，光看格子不容易找。
## 醫／用藥／傳力選自己或隊友時（綠格）：同樣在可點的自己人頭上畫綠色箭頭，腳下的綠格再描一圈會閃的外框
## 畫在人物上面——只有自己一個目標時，綠格整個被自己的身體與選取圈蓋住（M3a 審查）。
func _draw_target_marks() -> void:
	if view.vm == null or view.highlight.is_empty():
		return
	var ally_mode := view.highlight_color.is_equal_approx(UiTheme.HIGHLIGHT_ALLY)
	if not ally_mode and not view.highlight_color.is_equal_approx(UiTheme.HIGHLIGHT_TARGET):
		return
	var tw := view.tile_w
	var bob := -absf(sin(_now() * 6.0)) * tw * 0.05   # 只往上跳：箭頭尖端不會壓到名字牌（審查 round 3）
	var fill := Color(0.35, 0.95, 0.4, 0.95) if ally_mode else Color(0.95, 0.3, 0.2, 0.9)
	var fill_hot := Color(0.5, 1.0, 0.55, 1.0) if ally_mode else Color(1.0, 0.32, 0.2, 1.0)
	var ink := Color(0.02, 0.18, 0.04, 0.95) if ally_mode else Color(0.15, 0.03, 0.02, 0.95)
	if ally_mode:
		var pulse := 0.55 + 0.45 * (0.5 + 0.5 * sin(_now() * 5.0))
		for c in view.highlight:
			var center := view.grid_to_local(Vector2(c))
			var d := view.diamond(center, 0.9)
			var closed := d.duplicate()
			closed.append(d[0])
			draw_polyline(closed, Color(0.4, 1.0, 0.45, pulse), maxf(2.5, tw * 0.04), true)
	for uid in view.sprites:
		var sp: UnitSprite = view.sprites[uid]
		if sp.vis_state != "ALIVE" or not sp.shows_label() or sp.ally != ally_mode:
			continue
		# 用主機位置判斷（敵人可能還在走過去的動畫中，箭頭跟著身體）
		var cell := BattleViewModel.to_cell(view.vm.unit(uid).get("pos", Vector2i(-1, -1)))
		if not view.highlight.has(cell):
			continue
		var top := sp.name_box.position.y if sp.name_box.size != Vector2.ZERO else sp.position.y - sp.label_top()
		if not view.vm.unit_statuses(int(uid)).is_empty():
			top -= int(clampf(tw * 0.13, 10.0, 15.0)) * 1.4 + 4.0   # 狀態圓牌那一排上面
		var cx := sp.name_box.get_center().x if sp.name_box.size != Vector2.ZERO else sp.position.x
		var hot := view.hover_cell == cell
		var r := tw * (0.13 if hot else 0.1)
		var tip := Vector2(cx, top - 6.0 + bob)
		var pts := PackedVector2Array([tip, tip + Vector2(-r, -r * 1.1), tip + Vector2(r, -r * 1.1)])
		draw_colored_polygon(pts, fill_hot if hot else fill)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, ink, maxf(1.5, tw * 0.022), true)

## 飄字的起點：字框底邊貼在 above（名字牌頂）上方一點
static func popup_base(above: Vector2, w: float, fs: int, ow: int) -> Vector2:
	var p := above + Vector2(-w / 2.0, 0)
	var box := BattleFx.popup_box(p, w, fs, ow)
	return p + Vector2(0, above.y - POPUP_GAP - box.end.y)

## 最靠近 s 的其他人（活著）的螢幕 x；沒有回 s 自己的 x
static func nearest_x(s: UnitSprite, bodies: Array) -> float:
	var best := INF
	var x := s.position.x
	for b in bodies:
		if b[0] == s:
			continue
		var d: float = (b[0] as UnitSprite).position.distance_squared_to(s.position)
		if d < best:
			best = d
			x = (b[0] as UnitSprite).position.x
	return x

## 飄字找位置：自己頭上 → 遠離鄰居那一側 → 另一側 → 上一列（同樣三個）→ 再上一列；
## 不壓名字牌、氣條、別的飄字、也不蓋在別人身上。都擠不下就放上一列（最多升兩列，不會疊成高柱子）
static func place_popup(base: Vector2, w: float, fs: int, ow: int, away: float, taken: Array, others: Array, bounds := Rect2(),
		plate_w := 0.0) -> Vector2:
	var box := BattleFx.popup_box(base, w, fs, ow)
	var dx := box.size.x * 0.55 + POPUP_GAP
	var dy := box.size.y + POPUP_GAP
	var sg := away if away != 0.0 else 1.0
	var beside := plate_w / 2.0 + box.size.x / 2.0 + POPUP_GAP   # 跟自己名字牌同一高度、在牌子旁邊（上緣沒空間時用）
	var cands := [Vector2(0, 0), Vector2(sg * dx, 0), Vector2(-sg * dx, 0), Vector2(0, -dy), Vector2(sg * dx, -dy),
		Vector2(-sg * dx, -dy), Vector2(0, -dy * 2.0), Vector2(sg * beside, dy * 0.8), Vector2(-sg * beside, dy * 0.8)]
	# 戰場上緣（最後一排）往上沒有空間：上升的那一段也要留在畫面內
	var rise_room := box.size.y * 0.8
	var fits := func(r: Rect2) -> bool:
		return bounds.size == Vector2.ZERO or (r.position.y - rise_room >= bounds.position.y and r.position.x >= bounds.position.x and r.end.x <= bounds.end.x)
	for c in cands:
		var r := Rect2(box.position + c, box.size)
		if fits.call(r) and not BattleFx._overlaps(r, taken) and not BattleFx._overlaps(r, others):
			return base + c
	for c in cands:   # 第二輪：只求不壓字（名字牌、氣條、飄字），可以蓋到別人身上
		var r := Rect2(box.position + c, box.size)
		if fits.call(r) and not BattleFx._overlaps(r, taken):
			return base + c
	# 都擠不下：放在名字牌旁邊，夾在畫面內
	var out := base + Vector2(sg * beside, dy * 0.8)
	if bounds.size != Vector2.ZERO:
		var r := Rect2(box.position + Vector2(sg * beside, dy * 0.8), box.size)
		out.x += clampf(r.position.x, bounds.position.x, bounds.end.x - r.size.x) - r.position.x
		out.y += maxf(0.0, bounds.position.y + rise_room - r.position.y)
	return out

static func _overlaps(r: Rect2, rects: Array) -> bool:
	for q in rects:
		if r.intersects(q as Rect2):
			return true
	return false

## 飄字（含描邊）的外框；p 是字的基線左端
static func popup_box(p: Vector2, w: float, fs: int, ow: int) -> Rect2:
	var pad := maxf(4.0, ow * 0.6)
	return Rect2(Vector2(p.x - pad, p.y - fs * 0.9 - pad * 0.5), Vector2(w + pad * 2.0, fs * 1.15 + pad))

## 跟 placed 裡任何一個重疊就往上推到它上面；回傳新的 top
static func push_up(r: Rect2, placed: Array, gap: float) -> float:
	for _iter in placed.size() + 1:
		var moved := false
		for q in placed:
			if r.grow(gap * 0.5).intersects(q as Rect2):
				r.position.y = (q as Rect2).position.y - r.size.y - gap
				moved = true
		if not moved:
			break
	return r.position.y

static func _hits(r: Rect2, rects: Array) -> bool:
	for q in rects:
		if r.grow(NAME_GAP * 0.5).intersects(q as Rect2):
			return true
	return false

## 名字牌蓋到別人身上（例如兔子走到人前面，牠的名字會壓在人的胸口）：往遠離那個人的一側橫移，
## 牌子仍罩在自己頭上方（最多移到自己的中線貼著牌子邊），不會被誤認成別人的名字
static func clear_bodies(s: UnitSprite, own_x: float, r: Rect2, bodies: Array) -> Rect2:
	for _pass in 2:
		var moved := false
		for b in bodies:
			if b[0] == s or not r.intersects(b[1] as Rect2):
				continue
			var body: Rect2 = b[1]
			var o: UnitSprite = b[0]
			var dir := signf(own_x - o.position.x)
			if dir == 0.0:
				dir = 1.0
			var want := (body.end.x + NAME_GAP) if dir > 0.0 else (body.position.x - r.size.x - NAME_GAP)
			# 牌子至少要碰到自己的中線，不然看起來像別人的
			var min_x := own_x - r.size.x * 0.92
			var max_x := own_x - r.size.x * 0.08
			var nx := clampf(want, min_x, max_x)
			if not is_equal_approx(nx, r.position.x):
				r.position.x = nx
				moved = true
		if not moved:
			break
	return r

## 名字牌排版：活著的由前排（depth 大）往後排，先避開別人的身體、再跟已放好的牌子重疊就往上推；
## 別人倒下的最後排：放在屍體上方，擠不下就放屍體下面（倒下的沒有氣條）；
## 別人的屍體還是擠不下（壓到名字牌、氣條或活人身上）就不畫（時間棒列表仍有全名），自己的一定畫
static func layout_names(list: Array) -> Array:
	var placed: Array = []
	var bodies: Array = []
	for s in list:
		if (s as UnitSprite).shows_label() and (s as UnitSprite).vis_state == "ALIVE":
			bodies.append([s, (s as UnitSprite).reach_rect((s as UnitSprite).position)])
	# 自己倒地：名字牌先放，活人的牌子讓開它——戰敗畫面一定找得到自己。
	# 屍體上方有活人的身體或氣條（兇手站在前一格）就放到屍體下面，不跟兇手的名字、氣條、損血字疊在一起（審查 round 3）
	for s in list:
		if (s as UnitSprite).is_me and (s as UnitSprite).shows_label() and (s as UnitSprite).vis_state != "ALIVE":
			var me_s := s as UnitSprite
			var r0: Rect2 = me_s.default_name_box(me_s.position)
			var crowd: Array = []
			for o in list:
				var os := o as UnitSprite
				if os != me_s and os.shows_label() and os.vis_state == "ALIVE":
					var ob := os.bar_rect(os.position)
					if ob.size != Vector2.ZERO:
						crowd.append(ob.grow(4.0))
					var ow := os.waist_hp_rect()
					if ow.size != Vector2.ZERO:
						crowd.append(ow)
			if BattleFx._hits_body(r0, bodies) or BattleFx._hits(r0, crowd):
				r0.position.y = me_s.position.y + me_s.tile_w * 0.17
			me_s.name_box = r0
			placed.append(r0)
	for i in range(list.size() - 1, -1, -1):
		var s: UnitSprite = list[i]
		if not s.shows_label():
			s.name_box = Rect2()
			continue
		if s.vis_state != "ALIVE":
			continue
		var r := BattleFx.clear_bodies(s, s.position.x, s.default_name_box(s.position), bodies)
		r = BattleFx.lift_over_bodies(s, r, bodies)
		r.position.y = BattleFx.push_up(r, placed, NAME_GAP)
		s.name_box = r
		placed.append(r)
	var bars: Array = []
	var dead: Array = []
	for i in range(list.size() - 1, -1, -1):
		var s: UnitSprite = list[i]
		var bar := s.bar_rect(s.position)
		if bar.size != Vector2.ZERO:
			bars.append(bar.grow(4.0))
		if s.shows_label() and s.vis_state != "ALIVE" and not s.is_me:
			dead.append(s)
	for s in dead:
		var r: Rect2 = s.default_name_box(s.position)
		if BattleFx._hits(r, placed) or BattleFx._hits_body(r, bodies) or BattleFx._hits(r, bars):
			var below := r
			below.position.y = s.position.y + s.tile_w * 0.08
			if BattleFx._hits(below, placed) or BattleFx._hits(below, bars) or BattleFx._hits_body(below, bodies):
				s.name_box = Rect2()
				continue
			r = below
		s.name_box = r
		placed.append(r)
	return bodies

## 先照腰部損血字排一次名字牌；腰部的字壓到別人的名字牌或別人的腰部字，就改放到自己名字牌最下一列，再排一次
static func layout_names_with_hp(list: Array, hp_on: bool) -> Array:
	for s in list:
		(s as UnitSprite).hp_text_on = hp_on
		(s as UnitSprite).hp_line = false
	var bodies := BattleFx.layout_names(list)
	if not hp_on:
		return bodies
	var moved := false
	for s in list:
		var r: Rect2 = (s as UnitSprite).waist_hp_rect()
		if r.size == Vector2.ZERO or not (s as UnitSprite).shows_label():
			continue
		for o in list:
			if o == s or not (o as UnitSprite).shows_label():
				continue
			var hit := (o as UnitSprite).name_box.size != Vector2.ZERO and r.intersects((o as UnitSprite).name_box)
			var ow: Rect2 = (o as UnitSprite).waist_hp_rect()
			hit = hit or (ow.size != Vector2.ZERO and r.intersects(ow))
			# 腰部損血字壓在我的屍體上（兇手站在屍體前一格）：改放名字牌最下一列
			if (o as UnitSprite).is_me and (o as UnitSprite).vis_state != "ALIVE":
				hit = hit or r.intersects((o as UnitSprite).self_rect((o as UnitSprite).position))
			# 壓在別人（活著的）身上：相鄰時野兔的「60/60」不再蓋住我的身體與兵器（M3a 審查）
			hit = hit or BattleFx.hits_other_body(s, r, bodies)
			if hit:
				(s as UnitSprite).hp_line = true
				moved = true
				break
	if moved:
		bodies = BattleFx.layout_names(list)
	return bodies

## 橫移之後還壓在別人身上（兩人相鄰、矮的站在高的前面：野兔的名字牌與氣條在我的胸口）：
## 整塊牌子往上抬到那個人頭頂上方（仍罩在自己的中線上），點選目標時不會蓋住別人的身體（M3a 審查）
static func lift_over_bodies(s: UnitSprite, r: Rect2, bodies: Array) -> Rect2:
	for b in bodies:
		if b[0] == s:
			continue
		var body: Rect2 = b[1]
		if r.intersects(body):
			r.position.y = minf(r.position.y, body.position.y - r.size.y - NAME_GAP)
	return r

## 腰部損血字壓到別人（活著的）身上
static func hits_other_body(s: UnitSprite, r: Rect2, bodies: Array) -> bool:
	for b in bodies:
		if b[0] != s and r.intersects(b[1] as Rect2):
			return true
	return false

static func _hits_body(r: Rect2, bodies: Array) -> bool:
	for b in bodies:
		if r.intersects(b[1] as Rect2):
			return true
	return false

func _draw_shield(c: Vector2, r: float, a: float) -> void:
	var pts := PackedVector2Array([c + Vector2(-r * 0.8, -r * 0.9), c + Vector2(0, -r * 1.05), c + Vector2(r * 0.8, -r * 0.9),
		c + Vector2(r * 0.75, -r * 0.1), c + Vector2(0, r), c + Vector2(-r * 0.75, -r * 0.1)])
	draw_colored_polygon(pts, Color(0.35, 0.55, 0.85, 0.75 * a))
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color(0.95, 0.9, 0.7, a), maxf(2.0, r * 0.12), true)
	draw_line(c + Vector2(0, -r * 0.8), c + Vector2(0, r * 0.7), Color(0.95, 0.9, 0.7, 0.8 * a), maxf(1.5, r * 0.08), true)

func _draw_spark(c: Vector2, r: float, a: float, kind: String) -> void:
	if kind == "fx_slash":
		var pts := PackedVector2Array()
		for i in 12:
			var ang := -2.4 + 1.8 * i / 11.0
			pts.append(c + Vector2(cos(ang), sin(ang)) * r * 1.4)
		draw_polyline(pts, Color(1, 1, 1, a), maxf(2.0, r * 0.18), true)
		return
	if kind == "fx_palm":
		draw_arc(c, r * 1.2, 0.0, TAU, 32, Color(1.0, 0.82, 0.3, a), maxf(2.0, r * 0.2), true)
	for i in 8:
		var ang := TAU * i / 8.0 + 0.3
		var d := Vector2(cos(ang), sin(ang))
		draw_line(c + d * r * 0.35, c + d * r, Color(1.0, 0.95, 0.6, a), maxf(1.5, r * 0.12), true)
