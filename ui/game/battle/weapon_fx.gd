class_name WeaponFx
extends RefCounted
## 武器出招特效（M3C_PLAN §7；ART_REQUEST §11；擁有者決定 O19）。純函式＋繪圖，不建節點。
## kind_for：依攻擊者「實際裝備的武器類型」（wtype／wfx）或所用武功類別（事件 cat）選特效種類；
## geometry：起點＝攻擊者前手、方向＝守方身體中心、長度與翻轉（§7.3）；
## draw_*：有 fx_weapon_*／fx_skill_* 圖（ArtRegistry.weapon_fx_texture）就畫圖，沒有就畫程式備援（線、多邊形、加法混色）。
## 名牌武器小圖示：icon_kind（§7.1 第 3–4 步，不看事件）；有 icon_weapon_* 圖用圖，沒有畫圓底單字。

const SKILL_CATS := { "STAB": "stab", "HIDDEN": "hidden", "INNER": "inner", "POISON": "poison", "MEDIC": "medic", "FORMATION": "formation" }
const WEAPON_KINDS := { "SWORD": "sword", "BLADE": "blade", "STAFF": "staff", "WHIP": "whip", "FIST": "fist", "SPEAR": "staff" }
## 舊主機（事件沒有 cat）或指令事件的 cat 不是技能類別時：依事件 key 判斷（§7.1 第 1 步）
const EVENT_KINDS := {
	"battle_hidden_hit": "hidden", "battle_hidden_miss": "hidden",
	"battle_poison_ok": "poison", "battle_poison_fail": "poison",
	"battle_medic": "medic",
	"battle_formation_on": "formation",
	"battle_acupoint_ok": "stab", "battle_acupoint_fail": "stab",   # 點穴【設計提案】算刺
	"battle_inner_transfer": "inner",                               # 傳功【設計提案】算內功
}
const WFX_KINDS := ["claw"]                       # 物品列 fx 欄可用的值（M3C_PLAN §6.2：爪類）
const ICON_KINDS := ["sword", "blade", "staff", "whip", "claw", "fist"]
const ICON_GLYPH := { "sword": "劍", "blade": "刀", "staff": "棍", "whip": "鞭", "claw": "爪", "fist": "拳" }
const ICON_TINT := { "sword": Color("dfe8f2"), "blade": Color("9fc0e6"), "staff": Color("d9b26a"),
	"whip": Color("d08a5a"), "claw": Color("d0604a"), "fist": Color("f2b440") }
const ICON_SIZE := 18.0

## 時序（§7.3、§10）：命中前 0.06 秒出現；淡入 0.06、停 0.12、淡出 0.10；全長 0.28
const LEAD := 0.06
const FADE_IN := 0.06
const HOLD := 0.12
const FADE_OUT := 0.10
const DUR := FADE_IN + HOLD + FADE_OUT
const MISS_ALPHA := 0.5                           # 未命中也畫，較淡
const HAND_X := 0.28                              # 前手＝腳底 + (facing × 0.28 × 身寬, −0.55 × 身高)
const HAND_Y := 0.55
const REACH := 0.9                                # 長度＝min(兩人距離 × 0.9, 1.6 格寬)
const MAX_LEN := 1.6
## M3c 審查：鄰格的目標只剩 ~25 px 長、幾乎全壓在攻擊者身上 → 最短 0.8 格寬（可以略為穿過目標）
const MIN_LEN := 0.8
const ASPECT := 0.5                               # 圖 1024×512：高＝長 × 0.5
const STEEP_RATIO := 0.3                          # 目標離自己腳底的水平距離 < 身寬 × 0.3 ＝ 在正下方
const STEEP_HAND_X := 0.5                         # 那時起點在身體外側（身寬的一半）
## M3c 第二輪審查：名牌上 18 px 的武器圖（刀、劍都是一條斜線加紅穗，還超出圓底）分不出來 → 小於這個大小畫單字（劍、刀…）
const ICON_ART_MIN := 28.0

## ---------------------------------------------------------------- 選特效

## "" = 不畫武器特效（用既有火花）。humanoid 由畫面傳入（UnitSprite.is_tall()）
static func kind_for(attacker: Dictionary, event: Dictionary, humanoid: bool) -> String:
	var p: Dictionary = event.get("p", {}) if event.get("p", null) is Dictionary else {}
	# 1. 武功類別（刺、暗器、內功、毒、醫、陣）；沒有 cat 或 cat 是兵器類時依事件 key（指令事件）
	var cat := str(p.get("cat", ""))
	if SKILL_CATS.has(cat):
		return SKILL_CATS[cat]
	var key := str(event.get("key", ""))
	if EVENT_KINDS.has(key):
		return EVENT_KINDS[key]
	# 2–4. 兵器
	return icon_kind(attacker, humanoid)

## §7.1 第 2–4 步（名牌圖示也用這個）：非人形怪 → ""；wfx（爪）→ claw；wtype → 對應鍵；空或不明 → fist
static func icon_kind(u: Dictionary, humanoid: bool) -> String:
	if str(u.get("kind", "")) != "PLAYER" and not humanoid:
		return ""
	var wfx := str(u.get("wfx", ""))
	if WFX_KINDS.has(wfx):
		return wfx
	var wt := str(u.get("wtype", ""))
	if wt == "" and u.get("weapon", null) is Dictionary:
		wt = str((u["weapon"] as Dictionary).get("weapon_type", ""))   # 舊主機沒有 wtype：自己的單位還有 weapon
	return str(WEAPON_KINDS.get(wt, "fist"))

## 畫在哪裡：attack（前手 → 目標）、target（目標身上往上飄：醫）、ground（施術者腳下：陣）
static func placement(kind: String) -> String:
	match kind:
		"medic":
			return "target"
		"formation":
			return "ground"
	return "attack"

## ---------------------------------------------------------------- 幾何

## 攻擊者腳底 feet、身寬 fig_w、身高 fig_h；守方身體中心 target；facing（±1）面向目標
## 回傳 { origin, target, angle, length, height, flip }
static func geometry(feet: Vector2, fig_w: float, fig_h: float, target: Vector2, tile_w: float, facing: float = 0.0) -> Dictionary:
	var f := facing
	if f == 0.0:
		f = 1.0 if target.x >= feet.x else -1.0
	var origin := feet + Vector2(f * HAND_X * fig_w, -HAND_Y * fig_h)
	# M3c 第二輪審查：目標在自己正下方（等角的正南鄰格）時，從前手往下畫會整條壓在自己腿上 → 起點挪到身體外側
	# （不越過目標，不改變朝向；斜角鄰格等一般情況不動）
	if target.y > feet.y - fig_h * 0.2 and absf(target.x - feet.x) < fig_w * STEEP_RATIO:
		var nx := feet.x + f * STEEP_HAND_X * fig_w
		if f > 0.0 and nx > origin.x:
			origin.x = nx
		elif f < 0.0 and nx < origin.x:
			origin.x = nx
	var d := target - origin
	var angle := d.angle() if d.length() > 0.001 else (0.0 if f > 0.0 else PI)
	var length := minf(d.length() * REACH, MAX_LEN * tile_w)
	length = maxf(length, tile_w * MIN_LEN)
	return { "origin": origin, "target": target, "angle": angle, "length": length, "height": length * ASPECT,
		"flip": absf(wrapf(angle, -PI, PI)) > PI / 2.0 }

## 淡入淡出：t = 出現後經過的秒數
static func alpha_at(t: float) -> float:
	if t < 0.0 or t > DUR:
		return 0.0
	if t < FADE_IN:
		return t / FADE_IN
	if t < FADE_IN + HOLD:
		return 1.0
	return clampf(1.0 - (t - FADE_IN - HOLD) / FADE_OUT, 0.0, 1.0)

## ---------------------------------------------------------------- 美術（ArtRegistry；WP-ART 的新 API 還沒落地時一律 null）

static var _reg_methods: Dictionary = {}
static var _tex_override: Dictionary = {}        # 測試用："fx:<kind>" / "icon:<kind>" → Texture2D

static func _reg_call(method: String, key: String) -> Texture2D:
	var s: Script = ArtRegistry
	if not _reg_methods.has(method):
		var ok := false
		for m in s.get_script_method_list():
			if str(m.get("name", "")) == method:
				ok = true
				break
		_reg_methods[method] = ok
	if not bool(_reg_methods[method]):
		return null
	var t: Variant = s.call(method, key)
	return t as Texture2D if t is Texture2D else null

static func fx_texture(kind: String) -> Texture2D:
	if _tex_override.has("fx:" + kind):
		return _tex_override["fx:" + kind]
	return _reg_call("weapon_fx_texture", kind) if kind != "" else null

static func icon_texture(kind: String) -> Texture2D:
	if _tex_override.has("icon:" + kind):
		return _tex_override["icon:" + kind]
	return _reg_call("weapon_icon", kind) if kind != "" else null

## 測試用：注入假圖（null 清除全部）
static func override_texture(key: String, tex: Texture2D) -> void:
	if key == "":
		_tex_override.clear()
	else:
		_tex_override[key] = tex

## ---------------------------------------------------------------- 繪圖
## 全部畫在 ci（BattleFx 的 canvas item，一般混色）與 glow（同一節點下的加法混色 canvas item RID）。
## 座標：local 的 x 軸＝出招方向（0 → length），y 軸垂直（±height/2）；flip 時 y 反向（弧線上下不顛倒）。

static func draw_strike(ci: RID, glow: RID, kind: String, g: Dictionary, t: float, a: float) -> void:
	var L := float(g["length"])
	var H := float(g["height"])
	var xf := Transform2D(float(g["angle"]), Vector2(1.0, -1.0 if bool(g["flip"]) else 1.0), 0.0, g["origin"])
	var tex := fx_texture(kind)
	var u := clampf(t / (FADE_IN + HOLD * 0.6), 0.0, 1.0)   # 揮出的進度（停留段的前半就揮完）
	RenderingServer.canvas_item_add_set_transform(ci, xf)
	RenderingServer.canvas_item_add_set_transform(glow, xf)
	if tex != null:
		# 圖的左緣中點＝前手（import_art.py：fx 圖裁邊後靠左、垂直置中）
		RenderingServer.canvas_item_add_texture_rect(ci, Rect2(0.0, -H / 2.0, L, H), tex.get_rid(), false, Color(1, 1, 1, a))
	else:
		match kind:
			"sword": _p_sword(ci, glow, L, H, u, a)
			"blade": _p_blade(ci, glow, L, H, u, a)
			"staff": _p_staff(ci, glow, L, H, u, a)
			"whip": _p_whip(ci, glow, L, H, u, a)
			"claw": _p_claw(ci, glow, L, H, u, a)
			"stab": _p_stab(ci, glow, L, H, u, a)
			"hidden": _p_hidden(ci, glow, L, H, t, a)
			"inner": _p_inner(ci, glow, L, H, u, a)
			"poison": _p_poison(ci, glow, L, H, u, a)
			_: _p_fist(ci, glow, L, H, u, a)
	RenderingServer.canvas_item_add_set_transform(ci, Transform2D.IDENTITY)
	RenderingServer.canvas_item_add_set_transform(glow, Transform2D.IDENTITY)

## 醫：目標身上，綠光往上飄（center＝身體中心、fig_h＝身高）
static func draw_medic(ci: RID, glow: RID, center: Vector2, fig_h: float, tile_w: float, t: float, a: float) -> void:
	var tex := fx_texture("medic")
	var rise := fig_h * 0.35 * clampf(t / DUR, 0.0, 1.0)
	if tex != null:
		# 圖是左→右的氣流（左緣中點＝起點）：轉 −90° 從腳下往上飄過全身
		var L := fig_h * 1.15
		var xf := Transform2D(-PI / 2.0, center + Vector2(0, fig_h * 0.5 - rise * 0.3))
		RenderingServer.canvas_item_add_set_transform(ci, xf)
		RenderingServer.canvas_item_add_texture_rect(ci, Rect2(0.0, -L * ASPECT / 2.0, L, L * ASPECT), tex.get_rid(), false, Color(1, 1, 1, a))
		RenderingServer.canvas_item_add_set_transform(ci, Transform2D.IDENTITY)
		return
	var r := tile_w * 0.42
	_ellipse(glow, center + Vector2(0, fig_h * 0.1), Vector2(r, r * 0.55), Color(0.25, 0.9, 0.35, 0.35 * a))
	_ellipse(glow, center, Vector2(r * 0.55, fig_h * 0.42), Color(0.3, 1.0, 0.45, 0.22 * a))
	for i in 7:
		var ph := fmod(i * 0.37 + t / DUR, 1.0)
		var x := (fmod(i * 0.61, 1.0) - 0.5) * r * 1.6
		var p := center + Vector2(x, fig_h * 0.3 - ph * fig_h * 0.75 - rise * 0.3)
		var s := tile_w * (0.05 + 0.03 * fmod(i * 0.29, 1.0))
		var la := a * sin(ph * PI)
		_leaf(ci, glow, p, s, 0.6 + i * 0.4, Color(0.55, 1.0, 0.5, la))
	for k in 3:
		var y := center.y + fig_h * 0.35 - fmod(k * 0.33 + t / DUR, 1.0) * fig_h * 0.8
		RenderingServer.canvas_item_add_line(glow, Vector2(center.x - r * 0.15 + k * r * 0.15, y),
			Vector2(center.x - r * 0.15 + k * r * 0.15, y - fig_h * 0.18), Color(0.6, 1.0, 0.6, 0.6 * a), maxf(1.5, tile_w * 0.025), true)

## 陣：施術者腳下的地面，金色八卦八角形地紋（等角壓扁）
static func draw_formation(ci: RID, glow: RID, feet: Vector2, tile_w: float, t: float, a: float) -> void:
	var tex := fx_texture("formation")
	var grow := 0.75 + 0.25 * clampf(t / (FADE_IN + HOLD), 0.0, 1.0)
	var R := tile_w * 0.62 * grow
	if tex != null:
		# 圖本身已是等角壓扁的地紋（2:1）：不再壓扁，寬 2R、高 R
		var Rt := R * 1.25
		RenderingServer.canvas_item_add_texture_rect(ci, Rect2(feet + Vector2(-Rt, -Rt * 0.5), Vector2(Rt * 2.0, Rt)), tex.get_rid(), false, Color(1, 1, 1, a))
		return
	var xf := Transform2D(0.0, Vector2(1.0, 0.5), 0.0, feet)
	RenderingServer.canvas_item_add_set_transform(ci, xf)
	RenderingServer.canvas_item_add_set_transform(glow, xf)
	var gold := Color(1.0, 0.82, 0.3, a)
	var rot := t * 1.4
	_circle(glow, Vector2.ZERO, R * 1.05, Color(1.0, 0.75, 0.25, 0.25 * a))
	RenderingServer.canvas_item_add_polyline(ci, _ngon(R, 8, rot, true), PackedColorArray([gold]), maxf(2.0, tile_w * 0.035), true)
	RenderingServer.canvas_item_add_polyline(ci, _ngon(R * 0.72, 8, rot, true), PackedColorArray([Color(gold, 0.8 * a)]), maxf(1.5, tile_w * 0.022), true)
	# 八卦：每邊三爻（陽爻一條、陰爻斷成兩段），依序陰陽交錯
	for i in 8:
		var ang := rot + TAU * (i + 0.5) / 8.0
		var dir := Vector2(cos(ang), sin(ang))
		var side := Vector2(-dir.y, dir.x)
		for k in 3:
			var rr := R * (0.78 + 0.065 * k)
			var c := dir * rr
			var hl := R * 0.13
			var yin := ((i >> k) & 1) == 1
			if yin:
				RenderingServer.canvas_item_add_line(ci, c - side * hl, c - side * hl * 0.2, gold, maxf(1.2, tile_w * 0.018), true)
				RenderingServer.canvas_item_add_line(ci, c + side * hl * 0.2, c + side * hl, gold, maxf(1.2, tile_w * 0.018), true)
			else:
				RenderingServer.canvas_item_add_line(ci, c - side * hl, c + side * hl, gold, maxf(1.2, tile_w * 0.018), true)
	# 太極
	_circle(glow, Vector2.ZERO, R * 0.22, Color(1.0, 0.9, 0.5, 0.45 * a))
	RenderingServer.canvas_item_add_polyline(ci, _ngon(R * 0.22, 24, 0.0, true), PackedColorArray([gold]), maxf(1.5, tile_w * 0.02), true)
	RenderingServer.canvas_item_add_set_transform(ci, Transform2D.IDENTITY)
	RenderingServer.canvas_item_add_set_transform(glow, Transform2D.IDENTITY)

## 名牌小圖示（18×18，center 為圓心）
static func draw_icon(ci: CanvasItem, kind: String, center: Vector2, font: Font, alpha: float = 1.0) -> void:
	if kind == "":
		return
	var s := ICON_SIZE
	var tex := icon_texture(kind) if s >= ICON_ART_MIN else null
	if tex != null:
		# 深色圓底＋圖（細長的劍、刀圖直接畫在名牌上太淡）
		ci.draw_circle(center, s / 2.0, Color(0, 0, 0, 0.6 * alpha))
		ci.draw_texture_rect(tex, Rect2(center - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, alpha))
		return
	var tint: Color = ICON_TINT.get(kind, Color.WHITE)
	ci.draw_circle(center, s / 2.0, Color(0, 0, 0, 0.85 * alpha))
	ci.draw_circle(center, s / 2.0 - 1.5, Color(0.16, 0.11, 0.07, 0.95 * alpha))
	ci.draw_arc(center, s / 2.0 - 1.5, 0.0, TAU, 24, Color(tint, 0.9 * alpha), 1.2, true)
	if font == null:
		return
	var g := str(ICON_GLYPH.get(kind, "?"))
	var fs := 12
	var gw := font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := center + Vector2(-gw / 2.0, fs * 0.36)
	ci.draw_string_outline(font, p, g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, Color(0, 0, 0, alpha))
	ci.draw_string(font, p, g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(tint, alpha))

## ---------------------------------------------------------------- 程式備援（local 座標：x 往目標）

## 二次貝茲曲線取樣（0..u）
static func _bez(p0: Vector2, p1: Vector2, p2: Vector2, n: int, u: float = 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var s := u * float(i) / float(n)
		out.append(p0 * (1.0 - s) * (1.0 - s) + p1 * 2.0 * s * (1.0 - s) + p2 * s * s)
	return out

## 漸變寬度的帶子（新月弧、刀光）：widths 與 pts 等長；顏色沿線漸層（尾端淡）
static func _ribbon(rid: RID, pts: PackedVector2Array, widths: Array, col: Color, tail_fade := true) -> void:
	var n := pts.size()
	if n < 2:
		return
	# 三角形條帶（頂點 2i = 左緣、2i+1 = 右緣）；不經多邊形三角化，退化的細端也不會報錯
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in n:
		var d := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := Vector2(-d.y, d.x)
		var w := float(widths[i]) / 2.0
		var k := float(i) / float(n - 1)
		var c := Color(col, col.a * (0.25 + 0.75 * k if tail_fade else 1.0))
		verts.append(pts[i] + nrm * w)
		verts.append(pts[i] - nrm * w)
		cols.append(c)
		cols.append(c)
	var idx := PackedInt32Array()
	for i in n - 1:
		var l0 := 2 * i
		idx.append_array([l0, l0 + 2, l0 + 1, l0 + 1, l0 + 2, l0 + 3])
	RenderingServer.canvas_item_add_triangle_array(rid, idx, verts, cols)

static func _taper(n: int, w: float, power := 0.8) -> Array:
	var out: Array = []
	for i in n + 1:
		out.append(maxf(0.5, w * pow(sin(PI * float(i) / float(n)), power)))
	return out

static func _circle(rid: RID, c: Vector2, r: float, col: Color) -> void:
	RenderingServer.canvas_item_add_circle(rid, c, r, col)

static func _ellipse(rid: RID, c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var ang := TAU * i / 24.0
		pts.append(c + Vector2(cos(ang) * r.x, sin(ang) * r.y))
	RenderingServer.canvas_item_add_polygon(rid, pts, PackedColorArray([col]))

static func _ngon(r: float, n: int, rot: float, closed: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + (1 if closed else 0):
		var ang := rot + TAU * float(i % n) / float(n)
		pts.append(Vector2(cos(ang), sin(ang)) * r)
	return pts

static func _star(rid: RID, c: Vector2, r: float, col: Color, points := 4, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in points * 2:
		var rr := r if i % 2 == 0 else r * 0.28
		var ang := rot + PI * float(i) / float(points)
		pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
	RenderingServer.canvas_item_add_polygon(rid, pts, PackedColorArray([col]))

static func _leaf(ci: RID, glow: RID, c: Vector2, s: float, rot: float, col: Color) -> void:
	var d := Vector2(cos(rot), sin(rot))
	var nrm := Vector2(-d.y, d.x)
	var pts := PackedVector2Array([c - d * s, c + nrm * s * 0.45, c + d * s, c - nrm * s * 0.45])
	_circle(glow, c, s * 1.3, Color(col, col.a * 0.35))
	RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([col]))

## 劍：細長銀白新月弧（漸細）
static func _p_sword(ci: RID, glow: RID, L: float, H: float, u: float, a: float) -> void:
	var pts := _bez(Vector2(L * 0.05, H * 0.1), Vector2(L * 0.45, -H * 0.85), Vector2(L, -H * 0.05), 18, u)
	_ribbon(glow, pts, _taper(18, H * 0.26), Color(0.55, 0.75, 1.0, 0.55 * a))
	_ribbon(ci, pts, _taper(18, H * 0.09, 0.6), Color(0.96, 0.98, 1.0, 0.95 * a))
	if u >= 1.0:
		_star(glow, Vector2(L, -H * 0.05), H * 0.22, Color(0.8, 0.9, 1.0, 0.8 * a), 4, 0.3)

## 刀：寬厚鋼藍弧帶，外緣白刃
static func _p_blade(ci: RID, glow: RID, L: float, H: float, u: float, a: float) -> void:
	var pts := _bez(Vector2(0, H * 0.2), Vector2(L * 0.4, -H * 1.0), Vector2(L, H * 0.05), 18, u)
	_ribbon(glow, pts, _taper(18, H * 0.48, 0.6), Color(0.3, 0.55, 0.95, 0.5 * a))
	_ribbon(ci, pts, _taper(18, H * 0.28, 0.6), Color(0.45, 0.62, 0.85, 0.85 * a))
	var edge := _bez(Vector2(0, H * 0.2 - H * 0.1), Vector2(L * 0.4, -H * 1.0 - H * 0.12), Vector2(L, H * 0.05 - H * 0.06), 18, u)
	_ribbon(ci, edge, _taper(18, H * 0.06, 0.5), Color(1, 1, 1, 0.95 * a))

## 棍：大半圓掃動＋三條風線
static func _p_staff(ci: RID, glow: RID, L: float, H: float, u: float, a: float) -> void:
	var c := Vector2(L * 0.5, H * 0.25)
	var r := L * 0.48
	var start := PI * 1.05
	var span := PI * 0.9 * u
	var pts := PackedVector2Array()
	for i in 21:
		var ang := start + span * float(i) / 20.0
		pts.append(c + Vector2(cos(ang), sin(ang) * 0.75) * r)
	_ribbon(glow, pts, _taper(20, H * 0.34, 0.5), Color(1.0, 0.75, 0.35, 0.45 * a))
	_ribbon(ci, pts, _taper(20, H * 0.14, 0.5), Color(0.86, 0.66, 0.36, 0.95 * a))
	for k in 3:
		var rr := r * (0.62 + 0.13 * k)
		var wl := PackedVector2Array()
		var s0 := start + span * (0.35 + 0.1 * k)
		for i in 9:
			var ang := s0 + span * 0.35 * float(i) / 8.0
			wl.append(c + Vector2(cos(ang), sin(ang) * 0.75) * rr)
		RenderingServer.canvas_item_add_polyline(glow, wl, PackedColorArray([Color(1, 1, 1, 0.55 * a)]), maxf(1.2, H * 0.025), true)

## 鞭：S 形曲線＋尾端爆星
static func _p_whip(ci: RID, glow: RID, L: float, H: float, u: float, a: float) -> void:
	var pts := PackedVector2Array()
	var n := 28
	for i in n + 1:
		var s := u * float(i) / float(n)
		pts.append(Vector2(L * s, sin(s * TAU) * H * 0.28 * (1.0 - s * 0.4)))
	var ws: Array = []
	for i in n + 1:
		ws.append(maxf(0.8, H * 0.07 * (1.0 - 0.7 * float(i) / float(n))))
	var ws_g: Array = ws.map(func(w): return float(w) * 3.0)
	_ribbon(glow, pts, ws_g, Color(1.0, 0.55, 0.3, 0.45 * a), false)
	_ribbon(ci, pts, ws, Color(0.62, 0.36, 0.2, 0.95 * a), false)
	if u >= 0.98:
		var tip := pts[pts.size() - 1]
		_star(glow, tip, H * 0.32, Color(1.0, 0.85, 0.45, 0.85 * a), 6, 0.2)
		_star(ci, tip, H * 0.14, Color(1, 1, 0.9, a), 6, 0.2)

## 拳掌：金橙色掌勁圓＋2 圈擴散環（在目標那端）
static func _p_fist(ci: RID, glow: RID, L: float, H: float, u: float, a: float) -> void:
	var c := Vector2(L * 0.88, 0)
	var r := H * (0.22 + 0.16 * u)
	RenderingServer.canvas_item_add_line(glow, Vector2(L * 0.25, 0), c, Color(1.0, 0.7, 0.25, 0.45 * a), maxf(2.0, H * 0.16), true)
	_circle(glow, c, r * 1.35, Color(1.0, 0.55, 0.15, 0.4 * a))
	_circle(ci, c, r * 0.7, Color(1.0, 0.82, 0.35, 0.8 * a))
	_circle(glow, c, r * 0.45, Color(1.0, 0.95, 0.7, 0.9 * a))
	for k in 2:
		var rr := r * (1.1 + 0.55 * (k + u))
		RenderingServer.canvas_item_add_polyline(ci, _shift(_ngon(rr, 32, 0.0, true), c), PackedColorArray([Color(1.0, 0.75, 0.3, (0.8 - 0.3 * k) * a)]),
			maxf(1.5, H * (0.06 - 0.02 * k)), true)

static func _shift(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + by)
	return out

## 爪：三道平行紅褐抓痕（在目標那端）
static func _p_claw(ci: RID, glow: RID, L: float, H: float, u: float, a: float) -> void:
	for k in 3:
		var off := (k - 1) * H * 0.22
		var p0 := Vector2(L * 0.55, -H * 0.42 + off)
		var p2 := Vector2(L * 0.98, H * 0.3 + off)
		var p1 := (p0 + p2) / 2.0 + Vector2(H * 0.08, -H * 0.06)
		var pts := _bez(p0, p1, p2, 10, u)
		_ribbon(glow, pts, _taper(10, H * 0.2), Color(1.0, 0.3, 0.15, 0.5 * a))
		_ribbon(ci, pts, _taper(10, H * 0.08, 0.6), Color(0.62, 0.2, 0.12, 0.95 * a))

## 刺：細亮直線＋星形閃光
static func _p_stab(ci: RID, glow: RID, L: float, H: float, u: float, a: float) -> void:
	var tip := Vector2(L * u, 0)
	RenderingServer.canvas_item_add_line(glow, Vector2(0, 0), tip, Color(0.7, 0.85, 1.0, 0.5 * a), maxf(2.0, H * 0.12), true)
	RenderingServer.canvas_item_add_line(ci, Vector2(0, 0), tip, Color(1, 1, 1, 0.95 * a), maxf(1.2, H * 0.03), true)
	_star(glow, tip, H * 0.35, Color(0.85, 0.95, 1.0, 0.85 * a), 4, 0.0)
	_star(ci, tip, H * 0.14, Color(1, 1, 1, a), 4, PI / 4.0)

## 暗器：3 枚帶尾跡的小鏢，從前手飛向目標
static func _p_hidden(ci: RID, glow: RID, L: float, H: float, t: float, a: float) -> void:
	var u := clampf(t / (FADE_IN + HOLD), 0.0, 1.0)
	for k in 3:
		var s := clampf(u * 1.25 - k * 0.12, 0.0, 1.0)
		if s <= 0.0:
			continue
		var y := (k - 1) * H * 0.16
		var p := Vector2(L * s, y * (1.0 - s * 0.6))
		var tail := Vector2(maxf(0.0, p.x - L * 0.22), y)
		RenderingServer.canvas_item_add_polyline(glow, PackedVector2Array([tail, p]),
			PackedColorArray([Color(0.8, 0.9, 1.0, 0.0), Color(0.8, 0.9, 1.0, 0.7 * a)]), maxf(2.0, H * 0.08), true)
		RenderingServer.canvas_item_add_polyline(ci, PackedVector2Array([tail.lerp(p, 0.5), p]),
			PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.8 * a)]), maxf(1.0, H * 0.025), true)
		var d := maxf(4.0, H * 0.16)
		RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([p + Vector2(d * 1.4, 0), p + Vector2(0, -d * 0.5),
			p + Vector2(-d * 0.6, 0), p + Vector2(0, d * 0.5)]), PackedColorArray([Color(0.85, 0.88, 0.95, a)]))

## 內功：淡藍白螺旋
static func _p_inner(ci: RID, glow: RID, L: float, H: float, u: float, a: float) -> void:
	for ph in [0.0, PI]:
		var pts := PackedVector2Array()
		var n := 32
		for i in n + 1:
			var s := u * float(i) / float(n)
			pts.append(Vector2(L * s, sin(s * TAU * 2.5 + ph) * H * 0.28 * (0.4 + 0.6 * s)))
		RenderingServer.canvas_item_add_polyline(glow, pts, PackedColorArray([Color(0.55, 0.8, 1.0, 0.5 * a)]), maxf(3.0, H * 0.14), true)
		RenderingServer.canvas_item_add_polyline(ci, pts, PackedColorArray([Color(0.9, 0.97, 1.0, 0.85 * a)]), maxf(1.2, H * 0.035), true)
	_circle(glow, Vector2(L * u, 0), H * 0.26, Color(0.7, 0.9, 1.0, 0.55 * a))

## 毒：綠色毒霧團＋黑點（在目標那端）
static func _p_poison(ci: RID, glow: RID, L: float, H: float, u: float, a: float) -> void:
	var c := Vector2(L * (0.55 + 0.33 * u), 0)
	RenderingServer.canvas_item_add_line(glow, Vector2(L * 0.15, 0), c, Color(0.4, 0.9, 0.3, 0.3 * a), maxf(2.0, H * 0.18), true)
	var offs := [Vector2(0, 0), Vector2(0.18, -0.12), Vector2(-0.16, -0.1), Vector2(0.12, 0.14), Vector2(-0.1, 0.16), Vector2(0.02, -0.24)]
	for i in offs.size():
		var o: Vector2 = offs[i]
		var r := H * (0.2 + 0.05 * (i % 3)) * (0.7 + 0.3 * u)
		_circle(glow, c + o * H * 1.3, r * 1.3, Color(0.35, 0.95, 0.25, 0.25 * a))
		_circle(ci, c + o * H * 1.3, r, Color(0.32, 0.62, 0.2, 0.45 * a))
	for i in 7:
		var ang := float(i) * 2.4
		var rr := H * (0.12 + 0.05 * (i % 4))
		_circle(ci, c + Vector2(cos(ang), sin(ang)) * rr, maxf(1.2, H * 0.035), Color(0.05, 0.08, 0.03, 0.85 * a))
