class_name UnitSprite
extends Node2D
## 戰場上的一個單位：腳踩在 position（格心），立繪預設面向左下，面向右時水平翻轉。
## 有美術圖（ArtRegistry，含暫代圖）就畫圖，沒有就畫暫代剪影（人形／兔／四足獸／鬼魂／團狀），絕不畫圓形棋子。
## 頭上小字全名（深色描邊、依陣營上色）、腳下氣條由 BattleFx 畫在最上層；輪到我下令時腳下才有我方藍色光圈（閃動）。
## 每張圖外圍描一圈深色邊，相鄰兩隻同色的獸不會糊成一團；擋住玩家的前排單位會半透明（xray，BattleIsoView 設定）。
## 動畫全是程式做的（呼吸、跳格移動、前衝、受擊、倒下、逃走），只需要 idle 圖；有 attack／hurt 圖時會換上。

const HUMAN_H := 1.65          # 人形（直立的圖）身高（格寬倍數）：原作人物比格子大得多
const MAX_HUMAN_W := 1.45      # 人形立繪最寬（含兵器）
const BEAST_H := 1.4           # 動物（橫向的圖）以這個身高乘 art.json scale
const MAX_BEAST_W := 0.8       # 動物最寬：相鄰兩隻（螢幕上只差半格寬）不會疊成一團
const FIGURE_FILL := 252.0 / 256.0   # tools/import_art.py：裁邊後人物貼底、上方留 4px（畫布高 256）
const LYING_LIFT := 0.12       # 躺下時身體中線離地（格寬倍數）
const LYING_SCALE := 0.62      # 躺下時縮一點，躺在自己那一格裡
const DEAD_ALPHA := 0.88      # 屍體只微淡、微暗：要看得出誰倒在哪裡（太淡會在沙地上看不見）
const MY_DEAD_ALPHA := 1.0     # 自己的屍體不變淡（戰敗畫面要一眼看出自己躺在哪）
const BAR_W := 0.4             # 腳下氣條寬（格寬倍數；相鄰格在螢幕上差 0.5 格寬，留空隙分得出是誰的）
## 頭頂名字（AUTHENTIC_UI_SPEC §12.1，2018+ 客戶端）：敵方橘、我方黃；字下細底線；名字下 2 px 綠色時間棒、再下 2 px 紅色氣條
const ALLY_NAME := UiTheme.NAME_ALLY
const ENEMY_NAME := UiTheme.NAME_ENEMY
const DOWN_SUFFIX := "　倒下"
const DEAD_NAME := Color("b5ada3")
const MY_DEAD_NAME := Color("e4ddd2")
const NAME_PLATE := Color(0.06, 0.045, 0.035, 0.72)
const ALLY_PLATE_EDGE := Color("5b8fd0")
const ENEMY_PLATE_EDGE := Color("c0503f")
const ALLY_ROBE := Color("3d6fa8")
const ENEMY_ROBE := Color("8e3b31")
const OUTLINE := Color(0.08, 0.06, 0.05, 0.95)
const SHADOW := Color(0, 0, 0, 0.32)
const RING_ME := Color("ffe85a")       # 輪到我：腳下光圈用我方黃（原作頭頂名字色）
const RING_WAIT := Color("f2d24b")
const POSES := ["idle", "attack", "hurt"]
const FLASH_DUR := 0.2         # 受擊閃紅只閃一下（不會到下一回合還是一隻「紅狼」）
const FLASH_TINT := 0.5        # 閃紅最深時 G、B 減掉的比例
const RIM := Color(0.05, 0.035, 0.025, 0.75)   # 立繪外圍深色描邊
const BAR_EMPTY := Color(0.5, 0.45, 0.4, 0.9)   # 氣條空的部分：淺灰褐（不是一片黑；剩一點氣時看得出是「快空了」）
const BAR_FULL := Color("d8402f")
const BAR_LOW := Color("ff8a24")

var uid := 0
var unit: Dictionary = {}
var ally := true
var display_name := ""
var tile_w := 64.0
var gpos := Vector2.ZERO           # 連續格座標（移動動畫時在兩格之間）
var facing_right := false
var textures: Dictionary = {}      # pose -> Texture2D（沒有的 pose 不放）
var disp_scale := 1.0
var y_off := 0.0
var shape := "human"
var font: Font
# 畫面狀態（由 BattleIsoView 每幀更新）
var qi_max := 1
var shown_qi := 0
var vm_qi := -1                    # 主機目前的氣（腰部 cur/max 用這個，和 HUD 氣條一致；審查 round 4：受擊動畫還在排隊時字落後一下）
var gauge := 0.0
var is_me := false
var my_turn := false
var awaiting := false
# 動畫狀態
var anim_offset := Vector2.ZERO
var hop := 0.0
var flash := 0.0
var pose := "idle"
var lie := 0.0
var body_alpha := 1.0
var xray := 1.0                    # 透視（被 BattleIsoView 設成 <1 時，代表我擋到玩家）
var xray_target := 1.0
var vis_state := "ALIVE"           # ALIVE / DEAD / FLED
var locked_until := 0.0            # 這之前不從 VM 同步位置／氣／狀態（動畫還在演）
var ready_at := 0.0                # 這個單位下一段動畫最早的開始時間
var phase := 0.0
var depth := 0                     # 前後順序（BattleIsoView 依 x+y 排好、也照這個順序排子節點；大的在前面）
var name_box := Rect2()            # 這一幀名字牌的位置（BattleFx 排開重疊後寫回；飄字從這上面開始）
var badge_w := 0.0                 # 名字牌左邊留給狀態圓章的寬度（BattleFx 每幀依狀態數寫入；M3a UI 審查 #5）
var hp_text_on := false            # 損血顯示（系統窗特殊開關）：腰部紅字氣 cur/max
var hp_line := false               # 腰部的字會壓到鄰居的名字牌或損血字時，改畫在自己名字牌的最下一列（BattleFx 排版決定）
var weapon_kind := ""              # M3c WP-FX：名牌武器小圖示（WeaponFx.icon_kind；"" = 不畫，例如非人形怪；BattleFx 每幀寫入）
var _tweens: Array = []

static var _font_cache: Font = null
static var _anchor_cache: Dictionary = {}

static func ui_font() -> Font:
	if _font_cache == null:
		_font_cache = UiTheme.find_font()
		if _font_cache == null:
			_font_cache = ThemeDB.fallback_font
	return _font_cache

func setup(u: Dictionary, is_ally: bool) -> void:
	unit = u
	uid = int(u.get("uid", 0))
	ally = is_ally
	display_name = str(u.get("name", "?"))
	phase = float(uid) * 1.7
	font = UnitSprite.ui_font()
	shape = UnitSprite.shape_for(u)
	textures.clear()
	for p in POSES:
		var t := BattleIsoView.unit_texture(u, p)
		if t != null:
			textures[p] = t
	var d := BattleIsoView.unit_display(u)
	disp_scale = float(d.get("scale", 1.0)) if float(d.get("scale", 1.0)) > 0.0 else 1.0
	body = ArtRegistry.unit_body(BattleIsoView.unit_ref(u), str(u.get("kind", "")))
	y_off = float(d.get("y_offset", 0.0))

## 暫代剪影種類（依名字猜，只影響沒有圖時的樣子）
static func shape_for(u: Dictionary) -> String:
	var kind := str(u.get("kind", ""))
	if kind == "PLAYER" or kind == "NPC":
		return "human"
	var n := str(u.get("name", ""))
	if "鬼王" in n:
		return "human"
	if "鬼" in n:
		return "ghost"
	if "兔" in n:
		return "hare"
	for k in ["狼", "豬", "犬", "狗", "虎", "豹", "熊", "狐", "鹿", "牛", "馬"]:
		if k in n:
			return "beast"
	for k in ["賊", "弟子", "人", "客", "僧", "士", "王", "匪", "徒"]:
		if k in n:
			return "human"
	return "blob"

func has_art() -> bool:
	return textures.has("idle")

## M3c 第二輪審查：art.json 的 body（""＝沒標，依長寬比）
var body := ""

## 人形（名牌武器小圖示、武器出招特效；O19、M3C_PLAN §7.3「怪物非人形不畫」）：玩家一定是；
## 其他看 art.json 的 body，沒標才用 is_tall()（圖的長寬比）
func is_humanoid() -> bool:
	if str(unit.get("kind", "")) == "PLAYER":
		return true
	if body != "":
		return body == "human"
	return is_tall()

## 直立的圖（人、鬼）還是橫向的（獸）。M3c 第二輪審查：art.json 標了 body "human" 的寬圖（勞德諾、強盜 288×256）
## 照人的身高畫（以前被當成獸、縮成 0.8 格寬）；標 "beast" 的高圖（野兔、蠍子）大小照舊（比例是照現況調的）
func is_tall() -> bool:
	if body == "human":
		return true
	if has_art():
		var its := (textures["idle"] as Texture2D).get_size()
		return its.y >= its.x * 0.9
	return shape == "human" or shape == "ghost"

## 立繪的「腳底中心」在圖上的位置（0..1）：取最下面一段每欄最低的不透明點平均。
## 3/4 視角的人後腳比前腳高、四足獸前後腳差更多，只貼圖底會讓角色浮在影子上。讀不到圖時回 (0.5, 底)。
static func foot_anchor(tex: Texture2D) -> Vector2:
	if tex == null:
		return Vector2(0.5, 1.0)
	var key := tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id())
	if _anchor_cache.has(key):
		return _anchor_cache[key]
	var res := Vector2(0.5, 1.0)
	var img := tex.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		var w := img.get_width()
		var h := img.get_height()
		var step := maxi(1, w / 64)
		var bottoms: Array = []
		var lowest := -1
		for x in range(0, w, step):
			for y in range(h - 1, -1, -1):
				if img.get_pixel(x, y).a > 0.5:
					bottoms.append(Vector2(x, y))
					lowest = maxi(lowest, y)
					break
		if lowest >= 0:
			var band := float(h) * 0.15
			var sum := Vector2.ZERO
			var n := 0
			for b in bottoms:
				if (b as Vector2).y >= float(lowest) - band:
					sum += b
					n += 1
			var m := sum / float(n)
			res = Vector2(clampf((m.x + 0.5) / float(w), 0.2, 0.8), clampf((m.y + 1.0) / float(h), 0.6, 1.0))
	_anchor_cache[key] = res
	return res

func _anchor() -> Vector2:
	return UnitSprite.foot_anchor(textures.get("idle", null)) if has_art() else Vector2(0.5, 1.0)

## 站著時腳底（影子中心）到頭頂的像素高
func head_height() -> float:
	if not has_art():
		return figure_height()
	var h := figure_height() / FIGURE_FILL
	return h * (_anchor().y - (1.0 - FIGURE_FILL))

## 現在（含躺下）頭頂離地多高
func body_top() -> float:
	var hh := head_height()
	if is_tall():
		return lerpf(hh, tile_w * LYING_LIFT + hh * 0.22 * LYING_SCALE, lie)
	return hh * (1.0 - 0.45 * lie)

## 身體在畫面上大約佔的範圍（at = 腳底；名字牌避開別人的身體用）
func body_rect(at: Vector2) -> Rect2:
	var fh := figure_height()
	var w := fh / FIGURE_FILL
	if has_art():
		var ts := (textures["idle"] as Texture2D).get_size()
		w = w * ts.x / maxf(1.0, ts.y)
	else:
		w = fh * 0.8
	w = minf(w, tile_w * 1.1) * 0.62
	var top := body_top() + _float_up()
	return Rect2(Vector2(at.x - w / 2.0, at.y - top), Vector2(w, top))

## 名字牌避讓用的範圍：站著的人形連手臂與兵器（body_rect 只算軀幹的 62%，相鄰的野兔名字牌會壓在我的木刀與手臂上；
## M3a UI 審查 #3）。野獸照 body_rect
const REACH_MULT := 1.5

func reach_rect(at: Vector2) -> Rect2:
	var r := body_rect(at)
	if not is_tall():
		return r
	var w := r.size.x * REACH_MULT
	return Rect2(Vector2(at.x - w / 2.0, r.position.y), Vector2(w, r.size.y))

## 自己身體佔的範圍（站著 = body_rect；倒地 = 躺平的身體，橫向較寬、很矮）。BattleIsoView 用來找擋住玩家的人
func self_rect(at: Vector2) -> Rect2:
	if vis_state == "ALIVE" or not is_tall():
		return body_rect(at)
	var span := head_height() * LYING_SCALE
	var h := tile_w * 0.4
	return Rect2(Vector2(at.x - span / 2.0, at.y - h), Vector2(span, h + tile_w * 0.1))

## M3c WP-FX：名牌左端武器小圖示佔的寬度（沒有名字牌內容或不畫圖示時 0）
func icon_room() -> float:
	return WeaponFx.ICON_SIZE + 4.0 if weapon_kind != "" and vis_state == "ALIVE" else 0.0

## M3c WP-FX：立繪在畫面上的寬（像素；含兵器）。武器特效的前手位置用（§7.3：facing × 0.28 × figure_w）
func figure_width() -> float:
	var fh := figure_height()
	if has_art():
		var ts := (textures["idle"] as Texture2D).get_size()
		return fh / FIGURE_FILL * ts.x / maxf(1.0, ts.y)
	match shape:
		"human":
			return fh * 0.36 * 2.3   # 暫代人形：袍寬 ±0.5w、前伸兵器到 −1.15w（w = 0.36h）
		"ghost":
			return fh * 0.6
	return fh * 1.2

## 身高（像素）：有圖時 = 一般人 HUMAN_H 格寬 × art.json scale；暫代剪影依種類
func figure_height() -> float:
	if has_art():
		var tall := is_tall()
		var h := tile_w * (HUMAN_H if tall else BEAST_H) * disp_scale
		var ts := (textures["idle"] as Texture2D).get_size()
		var w := h / FIGURE_FILL * ts.x / maxf(1.0, ts.y)
		var cap := tile_w * (MAX_HUMAN_W if tall else MAX_BEAST_W) * maxf(1.0, disp_scale)
		if w > cap:
			h *= cap / w
		return h
	var base := HUMAN_H
	match shape:
		"hare":
			base = 0.62
		"beast":
			base = 0.95
		"ghost":
			base = 1.05
		"blob":
			base = 0.8
	return tile_w * base * maxf(1.0, disp_scale)   # 剪影已依種類定大小，只放大頭目

func dead_alpha() -> float:
	return MY_DEAD_ALPHA if is_me else DEAD_ALPHA

func snap_state(st: String) -> void:
	var want := "ALIVE"
	if st == "DEAD":
		want = "DEAD"
	elif st == "FLED":
		want = "FLED"
	if want == vis_state:
		return
	vis_state = want
	match want:
		"DEAD":
			lie = 1.0
			body_alpha = dead_alpha()
			modulate.a = 1.0
		"FLED":
			modulate.a = 0.0
			visible = false
		_:
			lie = 0.0
			body_alpha = 1.0
			modulate.a = 1.0
			visible = true

# ---------- 動畫 ----------
func _new_tween(delay: float) -> Tween:
	var tw := create_tween()
	_tweens.append(tw)
	tw.finished.connect(func(): _tweens.erase(tw))
	if delay > 0.0:
		tw.tween_interval(delay)
	return tw

func _now() -> float:
	return BattleIsoView.now_s()

func _hold(until: float) -> void:
	locked_until = maxf(locked_until, until)
	ready_at = maxf(ready_at, until)

## 丟掉還在排隊的動畫，回到靜止姿態（之後由 VM 同步）
func cancel_anims() -> void:
	for tw in _tweens.duplicate():
		if is_instance_valid(tw):
			(tw as Tween).kill()
	_tweens.clear()
	anim_offset = Vector2.ZERO
	hop = 0.0
	flash = 0.0
	pose = "idle"
	locked_until = 0.0
	ready_at = 0.0

func _set_pose(p: String) -> void:
	pose = p

func _step_to(t: float, path: Array) -> void:
	var n := path.size() - 1
	if n <= 0:
		return
	var i := clampi(int(floor(t)), 0, n - 1)
	var f := clampf(t - float(i), 0.0, 1.0)
	var a: Vector2 = path[i]
	var b: Vector2 = path[i + 1]
	gpos = a.lerp(b, f)
	hop = sin(f * PI) * tile_w * 0.08
	var dx := (b.x - b.y) - (a.x - a.y)
	if absf(dx) > 0.01:
		facing_right = dx > 0.0

## 沿路徑一格一格跳過去
func play_move(path: Array, delay: float, step_dur: float) -> void:
	if path.size() < 2:
		return
	var n := path.size() - 1
	gpos = path[0]
	_hold(_now() + delay + n * step_dur + 0.02)
	var tw := _new_tween(delay)
	tw.tween_method(_step_to.bind(path), 0.0, float(n), n * step_dur)
	tw.tween_callback(func():
		gpos = path[n]
		hop = 0.0)

## 前衝到 dir 再退回（有 attack 圖就換上）
func play_lunge(dir: Vector2, delay: float, dur: float) -> void:
	_hold(_now() + delay + dur)
	var tw := _new_tween(delay)
	tw.tween_callback(_set_pose.bind("attack"))
	tw.tween_property(self, "anim_offset", dir, dur * 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "anim_offset", Vector2.ZERO, dur * 0.62).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_set_pose.bind("idle"))

## 受擊：閃紅＋擊退（有 hurt 圖就換上），命中瞬間氣條才掉
func play_hurt(knock: Vector2, delay: float, qi_after: int, dur := 0.38) -> void:
	_hold(_now() + delay + dur)
	var tw := _new_tween(delay)
	tw.tween_callback(func():
		pose = "hurt"
		flash = 1.0
		shown_qi = qi_after)
	tw.tween_property(self, "anim_offset", knock, dur * 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "flash", 0.0, minf(dur, FLASH_DUR)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "anim_offset", Vector2.ZERO, dur * 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_set_pose.bind("idle"))

func play_dodge(side: Vector2, delay: float) -> void:
	_hold(_now() + delay + 0.3)
	var tw := _new_tween(delay)
	tw.tween_property(self, "anim_offset", side, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "anim_offset", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

## 倒下：往後躺平並變淡（名字與氣條隱藏）
func play_death(delay: float) -> void:
	_hold(_now() + delay + 0.55)
	var tw := _new_tween(delay)
	tw.tween_callback(func():
		vis_state = "DEAD"
		pose = "hurt"
		shown_qi = 0)
	tw.tween_property(self, "lie", 1.0, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "body_alpha", dead_alpha(), 0.5)
	tw.tween_callback(_set_pose.bind("idle"))

## 逃走：往後退並淡出
func play_flee(delay: float) -> void:
	_hold(_now() + delay + 0.6)
	var away := Vector2(tile_w * (0.5 if facing_right else -0.5) * -1.0, tile_w * 0.1)
	var tw := _new_tween(delay)
	tw.tween_property(self, "anim_offset", away, 0.55)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.55)
	tw.tween_callback(func():
		vis_state = "FLED"
		visible = false
		anim_offset = Vector2.ZERO)

func _process(delta: float) -> void:
	xray = move_toward(xray, xray_target, delta * 4.0)
	queue_redraw()

# ---------- 繪製 ----------
func _draw() -> void:
	if vis_state == "FLED" and modulate.a <= 0.0:
		return
	var alive := vis_state == "ALIVE"
	var base := anim_offset
	_draw_ground(alive)
	var fh := figure_height()
	var bob := 1.0
	if alive and pose == "idle":
		bob = 1.0 + 0.018 * sin(_now() * 2.4 + phase)
	var sx := -1.0 if facing_right else 1.0
	# 倒下：人形以身體中心為軸往後躺平、躺在自己那一格上（不會甩到隔壁格）；
	# 四足獸／兔子側倒（壓扁＋微傾），並且變灰變淡
	var tall := is_tall()
	var rot := lie * (1.45 if tall else 0.35) * (-1.0 if facing_right else 1.0)
	var squash := 1.0 - (0.0 if tall else 0.45 * lie)
	var shrink := lerpf(1.0, LYING_SCALE, lie) if tall else 1.0
	var mid := head_height() * 0.5          # 轉軸：身體中心（腳底往上半個身高）
	var lift := mid * squash * bob
	if tall:
		lift = lerpf(mid * bob, tile_w * LYING_LIFT, lie)
	var xf := Transform2D(rot, Vector2(sx * shrink, bob * squash * shrink), 0.0, base + Vector2(0, -hop - _float_up() - lift))
	draw_set_transform_matrix(xf.translated_local(Vector2(0, mid)))   # 之後的座標：腳底在 (0,0)
	var g := 1.0 - (0.12 if is_me else 0.3) * lie
	var a := body_alpha * xray
	var tint := Color(g, g * (1.0 - FLASH_TINT * flash), g * (1.0 - FLASH_TINT * flash), a)
	if has_art():
		var tex: Texture2D = textures.get(pose, textures["idle"])
		var ts := tex.get_size()
		var h := fh / FIGURE_FILL
		var w := h * ts.x / maxf(1.0, ts.y)
		var pad := y_off / maxf(1.0, ts.y)   # art.json y_offset：1 倍大小的精靈像素，負數往上
		var an := _anchor()
		var r := Rect2(-w * an.x, -h * an.y + pad * h, w, h)
		# 深色描邊：同一張圖染黑往四個斜角各偏一點先畫（相鄰同色的兩隻狼也分得出輪廓）
		var k := maxf(1.0, tile_w * 0.018) / maxf(0.3, absf(xf.get_scale().y))
		var rim := Color(RIM, RIM.a * a * a)
		for o in [Vector2(-k, -k), Vector2(k, -k), Vector2(-k, k), Vector2(k, k)]:
			draw_texture_rect(tex, Rect2(r.position + o, r.size), false, rim)
		draw_texture_rect(tex, r, false, tint)
	else:
		_draw_placeholder(fh, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 名字牌與氣條畫在最上層（BattleFx 呼叫），不會被前排的人擋住。
## 都釘在格子上（不跟著前衝／受擊位移），兩人貼身時名字與氣條也不會疊在一起。at = 本單位腳底（格心）在 ci 上的位置
func shows_label() -> bool:
	return visible and vis_state != "FLED" and modulate.a > 0.05

## 名字牌預設位置（頭頂上方）；BattleFx 會把重疊的往上推
func default_name_box(at: Vector2) -> Rect2:
	if font == null:
		return Rect2(at - Vector2(0, label_top()), Vector2.ZERO)
	var fs := name_font_size()
	var tw := font.get_string_size(label_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad := Vector2(maxf(4.0, fs * 0.35), maxf(1.0, fs * 0.12))
	var hw := font.get_string_size(hp_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, HP_FONT).x + 8.0 if hp_h() > 0.0 else 0.0
	var size := Vector2(maxf(maxf(tw, gauge_w()), hw) + pad.x * 2.0, fs * 1.2 + pad.y * 2.0 + bars_h() + hp_h())
	var head := at.y - _float_up() - body_top() - tile_w * 0.04
	# 有狀態圓章：牌子往左加寬放圓章，名字、氣條仍對準自己的中線
	return Rect2(Vector2(at.x - size.x / 2.0 - badge_w, head - size.y), Vector2(size.x + badge_w, size.y))

## 名字牌內容（名字、氣條、氣血字）的中線：扣掉左邊的狀態圓章區
func plate_center_x(box: Rect2) -> float:
	return box.position.x + badge_w + (box.size.x - badge_w) / 2.0

## 名字列的高度（牌子扣掉氣條與氣血字）
func plate_name_h(box: Rect2) -> float:
	return box.size.y - bars_h() - hp_h()

## 名字（倒下的加「倒下」：屍體被擋住時也看得出誰倒在哪裡）
func label_text() -> String:
	var nm := display_name if (is_me or UnitSprite.show_names()) else ""
	return nm + (DOWN_SUFFIX if vis_state == "DEAD" else "")

## 系統開關「顯示名稱」（M2_PLAN D5：本機設定 ui.show_names）；關掉時只留自己的名字
static func show_names() -> bool:
	return UiSettings.get_bool("ui.show_names")

## 名字下的時間棒／氣條寬與兩條的總高（倒下的不畫）
func gauge_w() -> float:
	return tile_w * BAR_W if vis_state == "ALIVE" else 0.0

func bar_h() -> float:
	return maxf(2.0, tile_w * 0.035)

func bars_h() -> float:
	return (bar_h() * 2.0 + 3.0) if vis_state == "ALIVE" else 0.0

const HP_FONT := 13
## 損血字：深底牌更不透明、字改亮珊瑚色加黑描邊（審查 round 4：紅字壓在深褐底上對比太低）
const HP_PLATE := Color(0.03, 0.02, 0.015, 0.88)
const HP_INK := Color("ffb09c")

## 名字牌最下一列「cur/max」的高度（損血顯示關閉或倒下時 0）
func hp_h() -> float:
	return (HP_FONT * 1.25 + 3.0) if hp_text_on and hp_line and vis_state == "ALIVE" else 0.0

func hp_text() -> String:
	return "%d/%d" % [vm_qi if vm_qi >= 0 else shown_qi, qi_max]

func draw_name_plate(ci: CanvasItem, box: Rect2) -> void:
	if font == null or box.size == Vector2.ZERO:
		return
	var a := modulate.a
	var dead := vis_state == "DEAD"
	var fs := name_font_size()
	var txt := label_text()
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var name_h := box.size.y - bars_h() - hp_h()
	var p := Vector2(plate_center_x(box) - tw / 2.0, box.position.y + name_h / 2.0 + fs * 0.36)
	var col := (MY_DEAD_NAME if is_me else DEAD_NAME) if dead else (ALLY_NAME if ally else ENEMY_NAME)
	# 深色底牌：名字直接畫在亮沙地／草地上看不清（審查 round 4），活的、倒下的都墊；
	# 下緣色線分敵我（我方藍、敵方紅；倒下的朱紅），取代原本字下的細底線
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(NAME_PLATE, NAME_PLATE.a * a)
	sb.set_corner_radius_all(int(name_h / 2.0))
	sb.border_width_bottom = maxi(1, int(fs / 9))
	sb.border_color = Color(UiTheme.JY_RED if dead else (ALLY_PLATE_EDGE if ally else ENEMY_PLATE_EDGE), a)
	ci.draw_style_box(sb, Rect2(box.position, Vector2(box.size.x, name_h)))
	ci.draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, fs / 5), Color(OUTLINE, OUTLINE.a * a))
	ci.draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, a))
	if dead:
		return
	# 時間棒（綠，滿格才能行動）與氣條（紅）
	var bw := gauge_w()
	var bh := bar_h()
	var x := plate_center_x(box) - bw / 2.0
	var y := box.position.y + name_h + 1.0
	_thin_bar(ci, Rect2(x, y, bw, bh), clampf(gauge, 0.0, 1.0), UiTheme.TIME_BAR, UiTheme.TIME_BAR_BG, a)
	var frac := clampf(float(shown_qi) / float(maxi(1, qi_max)), 0.0, 1.0)
	var qcol := UiTheme.QI_BAR
	if frac <= 0.3:
		qcol = BAR_LOW.lerp(Color("ffd25a"), 0.5 + 0.5 * sin(_now() * 7.0))   # 快沒氣了：閃
	_thin_bar(ci, Rect2(x, y + bh + 2.0, bw, bh), frac, qcol, Color(0.25, 0.05, 0.05), a)
	if hp_h() > 0.0:
		# 氣 cur/max：深色小底牌＋紅字（任何背景、灰狼身上都看得清楚）
		var t := hp_text()
		var hw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, HP_FONT).x
		var hy := box.position.y + name_h + bars_h() + 1.0
		var plate := Rect2(plate_center_x(box) - hw / 2.0 - 4.0, hy, hw + 8.0, HP_FONT * 1.25)
		var sb2 := StyleBoxFlat.new()
		sb2.bg_color = Color(HP_PLATE, HP_PLATE.a * a)
		sb2.set_corner_radius_all(int(plate.size.y / 2.0))
		ci.draw_style_box(sb2, plate)
		var hp := Vector2(plate.position.x + 4.0, plate.position.y + HP_FONT * 0.98)
		ci.draw_string_outline(font, hp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, HP_FONT, 2, Color(0, 0, 0, a))
		ci.draw_string(font, hp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, HP_FONT, Color(HP_INK, a))

func _thin_bar(ci: CanvasItem, r: Rect2, frac: float, fill: Color, bg: Color, a: float) -> void:
	ci.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.75 * a))
	ci.draw_rect(r, Color(bg, a))
	if frac > 0.0:
		ci.draw_rect(Rect2(r.position, Vector2(maxf(1.0, r.size.x * frac), r.size.y)), Color(fill, a))

## 損血顯示（系統窗特殊開關，預設開）：身體中段（腰部）紅字「cur/max」氣，墊一塊深色小底牌（灰狼身上也看得清楚）。
## 兩人相鄰時腰部的字會和鄰居的名字牌疊成一行（審查）：那種情形 BattleFx 會把 hp_line 打開，
## 改由 draw_name_plate 畫在名字牌最下一列，這裡就不畫。
func waist_hp_rect() -> Rect2:
	if font == null or vis_state != "ALIVE" or not hp_text_on:
		return Rect2()
	var w := font.get_string_size(hp_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, HP_FONT).x
	return Rect2(position + Vector2(-w / 2.0 - 4.0, -head_height() * 0.42 - HP_FONT * 0.98), Vector2(w + 8.0, HP_FONT * 1.25))

## plate_mul：底板的透明度倍數（M3c 第三輪審查：自己的武器特效正在畫時底板變淡，特效的起點透得出來，數字照樣看得清楚）
func draw_hp_text(ci: CanvasItem, plate_mul := 1.0) -> void:
	if hp_line or not shows_label():
		return
	var r := waist_hp_rect()
	if r.size == Vector2.ZERO:
		return
	var a := modulate.a
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(HP_PLATE, HP_PLATE.a * a * plate_mul)
	sb.set_corner_radius_all(int(r.size.y / 2.0))
	ci.draw_style_box(sb, r)
	ci.draw_string_outline(font, r.position + Vector2(4.0, HP_FONT * 0.98), hp_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, HP_FONT, 2, Color(0, 0, 0, a))
	ci.draw_string(font, r.position + Vector2(4.0, HP_FONT * 0.98), hp_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, HP_FONT, Color(HP_INK, a))

## 舊的腳下氣條已移到名字下（原作）：腳下不再佔位置
func bar_rect(_at: Vector2) -> Rect2:
	return Rect2()

func draw_bars(_ci: CanvasItem, _at: Vector2) -> void:
	pass

func _float_up() -> float:
	if shape == "ghost" and vis_state == "ALIVE":
		return tile_w * (0.12 + 0.04 * sin(_now() * 2.0 + phase))
	return 0.0

## 名字頂端到腳底的高度（飄字從這上面開始）
func label_top() -> float:
	return hop + _float_up() + body_top() + tile_w * 0.06 + name_font_size() + 2.0

func _draw_ground(alive: bool) -> void:
	var rx := tile_w * 0.3 * clampf(disp_scale, 0.6, 1.6)
	draw_set_transform(Vector2(anim_offset.x, anim_offset.y), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, rx * (1.0 - 0.2 * clampf(hop / maxf(1.0, tile_w * 0.08), 0.0, 1.0)), Color(SHADOW, SHADOW.a * body_alpha))
	# 光圈只在「輪到我下令」（藍、閃動）或隊友等待下令（金）時畫：蓄勢中沒有光圈，一看就知道輪到誰
	if alive and (my_turn or (awaiting and not is_me)):
		var r := tile_w * 0.36
		var col := RING_ME if is_me else RING_WAIT
		var p := 0.5 + 0.5 * sin(_now() * 6.0)
		col = Color(col, 0.6 + 0.4 * p)
		var width := 2.5 + 2.5 * p
		r *= 1.0 + 0.06 * p
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0.03, 0.06, 0.12, 0.45), width + 3.0, true)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, col, width, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func name_font_size() -> int:
	return int(clampf(tile_w * 0.15, 13.0, 16.0))


## 腳下只有一條氣（血）條；時間棒在右欄，不在腳下多畫一條沒有說明的黃條
func _draw_bars(ci: CanvasItem, at: Vector2, a: float) -> void:
	var bw := tile_w * BAR_W
	var bh := maxf(4.0, tile_w * 0.07)
	var top := at + Vector2(-bw / 2.0, tile_w * 0.13)
	var frac := clampf(float(shown_qi) / float(maxi(1, qi_max)), 0.0, 1.0)
	ci.draw_rect(Rect2(top - Vector2(1, 1), Vector2(bw + 2, bh + 2)), Color(OUTLINE, OUTLINE.a * a))
	ci.draw_rect(Rect2(top, Vector2(bw, bh)), Color(BAR_EMPTY, BAR_EMPTY.a * a))
	var qcol := BAR_FULL
	if frac <= 0.3:
		# 快沒氣了：亮橘色、閃一閃；剩一點點也至少畫 3px，不會整條看起來是黑的
		qcol = BAR_LOW.lerp(Color("ffd25a"), 0.5 + 0.5 * sin(_now() * 7.0))
	var fw := bw * frac
	if shown_qi > 0:
		fw = maxf(fw, minf(3.0, bw))
	ci.draw_rect(Rect2(top, Vector2(fw, bh)), Color(qcol, a))
	ci.draw_rect(Rect2(top, Vector2(fw, bh * 0.4)), Color(1, 1, 1, 0.22 * a))

## 暫代剪影：腳底在 (0,0)，面向左下（翻轉由外層 transform 處理）
func _draw_placeholder(h: float, tint: Color) -> void:
	match shape:
		"hare":
			_ph_hare(h, tint)
		"beast":
			_ph_beast(h, tint)
		"ghost":
			_ph_ghost(h, tint)
		"blob":
			_ph_blob(h, tint)
		_:
			_ph_human(h, tint)

func _c(col: Color, tint: Color) -> Color:
	return Color(col.r * tint.r, col.g * tint.g, col.b * tint.b, col.a * tint.a)

func _poly(pts: PackedVector2Array, col: Color, tint: Color) -> void:
	draw_colored_polygon(pts, _c(col, tint))
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, _c(OUTLINE, tint), maxf(1.0, tile_w * 0.02), true)

func _ellipse(center: Vector2, r: Vector2, col: Color, tint: Color, outline := true) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(center + Vector2(cos(a) * r.x, sin(a) * r.y))
	if outline:
		_poly(pts, col, tint)
	else:
		draw_colored_polygon(pts, _c(col, tint))

func _ph_human(h: float, tint: Color) -> void:
	var robe := ALLY_ROBE if ally else ENEMY_ROBE
	var w := h * 0.36
	# 腿
	draw_line(Vector2(-w * 0.18, -h * 0.2), Vector2(-w * 0.26, 0), _c(Color("3a2f28"), tint), h * 0.06, true)
	draw_line(Vector2(w * 0.16, -h * 0.2), Vector2(w * 0.2, -h * 0.01), _c(Color("3a2f28"), tint), h * 0.06, true)
	# 長袍
	_poly(PackedVector2Array([Vector2(-w * 0.32, -h * 0.68), Vector2(w * 0.3, -h * 0.68), Vector2(w * 0.5, -h * 0.14),
		Vector2(0, -h * 0.1), Vector2(-w * 0.55, -h * 0.16)]), robe, tint)
	# 腰帶
	draw_line(Vector2(-w * 0.4, -h * 0.42), Vector2(w * 0.38, -h * 0.42), _c(Color("d9c9a0"), tint), maxf(1.5, h * 0.025), true)
	# 前伸的手與兵器（朝左下）
	draw_line(Vector2(-w * 0.2, -h * 0.6), Vector2(-w * 0.62, -h * 0.4), _c(robe.darkened(0.2), tint), h * 0.07, true)
	draw_line(Vector2(-w * 0.62, -h * 0.4), Vector2(-w * 1.15, -h * 0.12), _c(Color("cfd4d8"), tint), maxf(1.5, h * 0.025), true)
	# 頭
	_ellipse(Vector2(-w * 0.04, -h * 0.79), Vector2(h * 0.105, h * 0.11), Color("e9cfa6"), tint)
	_ellipse(Vector2(w * 0.04, -h * 0.9), Vector2(h * 0.06, h * 0.05), Color("2a2420"), tint, false)
	draw_line(Vector2(-w * 0.2, -h * 0.84), Vector2(w * 0.12, -h * 0.88), _c(Color("2a2420"), tint), maxf(1.5, h * 0.03), true)

func _ph_hare(h: float, tint: Color) -> void:
	var fur := Color("8f7253")
	_ellipse(Vector2(h * 0.08, -h * 0.32), Vector2(h * 0.48, h * 0.3), fur, tint)
	_ellipse(Vector2(h * 0.48, -h * 0.4), Vector2(h * 0.12, h * 0.12), Color("e8e0d0"), tint)
	_ellipse(Vector2(-h * 0.36, -h * 0.55), Vector2(h * 0.2, h * 0.18), fur, tint)
	_poly(PackedVector2Array([Vector2(-h * 0.34, -h * 0.68), Vector2(-h * 0.26, -h * 1.12), Vector2(-h * 0.18, -h * 0.7)]), fur.lightened(0.1), tint)
	_poly(PackedVector2Array([Vector2(-h * 0.24, -h * 0.66), Vector2(-h * 0.08, -h * 1.05), Vector2(-h * 0.06, -h * 0.64)]), fur.lightened(0.1), tint)
	_ellipse(Vector2(-h * 0.44, -h * 0.58), Vector2(h * 0.035, h * 0.035), Color("1a1410"), tint, false)

func _ph_beast(h: float, tint: Color) -> void:
	var fur := Color("4c3b31") if "豬" in display_name else Color("6e6c70")
	var leg := fur.darkened(0.3)
	for x in [-0.42, -0.2, 0.22, 0.42]:
		draw_line(Vector2(h * x, -h * 0.35), Vector2(h * x - h * 0.04, 0), _c(leg, tint), h * 0.09, true)
	_ellipse(Vector2(0, -h * 0.45), Vector2(h * 0.58, h * 0.24), fur, tint)
	draw_line(Vector2(h * 0.55, -h * 0.5), Vector2(h * 0.8, -h * 0.68), _c(fur, tint), h * 0.07, true)
	_poly(PackedVector2Array([Vector2(-h * 0.45, -h * 0.68), Vector2(-h * 0.85, -h * 0.5), Vector2(-h * 0.72, -h * 0.36),
		Vector2(-h * 0.42, -h * 0.38)]), fur.lightened(0.08), tint)
	_poly(PackedVector2Array([Vector2(-h * 0.5, -h * 0.66), Vector2(-h * 0.48, -h * 0.84), Vector2(-h * 0.38, -h * 0.68)]), fur, tint)
	_ellipse(Vector2(-h * 0.62, -h * 0.55), Vector2(h * 0.035, h * 0.03), Color("9cff6a") if "狼" in display_name else Color("1a1410"), tint, false)
	if "豬" in display_name:
		draw_line(Vector2(-h * 0.76, -h * 0.42), Vector2(-h * 0.86, -h * 0.58), _c(Color("efe6d0"), tint), h * 0.04, true)

func _ph_ghost(h: float, tint: Color) -> void:
	var body := Color(0.82, 0.9, 0.95, 0.85)
	var pts := PackedVector2Array()
	for i in 13:
		var a := PI + PI * i / 12.0
		pts.append(Vector2(cos(a) * h * 0.3, -h * 0.62 + sin(a) * h * 0.36))
	pts.append(Vector2(h * 0.3, -h * 0.1))
	for i in 5:
		var x := h * 0.3 - h * 0.6 * (i + 0.5) / 5.0
		pts.append(Vector2(x, -h * (0.02 if i % 2 == 0 else 0.14)))
	pts.append(Vector2(-h * 0.3, -h * 0.1))
	_poly(pts, body, tint)
	_ellipse(Vector2(-h * 0.12, -h * 0.68), Vector2(h * 0.05, h * 0.07), Color("101418"), tint, false)
	_ellipse(Vector2(h * 0.06, -h * 0.7), Vector2(h * 0.05, h * 0.07), Color("101418"), tint, false)

func _ph_blob(h: float, tint: Color) -> void:
	var col := Color("7a8a4a") if ally else Color("8a5a4a")
	_ellipse(Vector2(0, -h * 0.42), Vector2(h * 0.5, h * 0.42), col, tint)
	_ellipse(Vector2(-h * 0.2, -h * 0.55), Vector2(h * 0.06, h * 0.08), Color("f4f0e0"), tint, false)
	_ellipse(Vector2(h * 0.02, -h * 0.57), Vector2(h * 0.06, h * 0.08), Color("f4f0e0"), tint, false)
