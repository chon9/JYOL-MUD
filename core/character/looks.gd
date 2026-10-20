class_name Looks
extends RefCounted
## 初始造型（M3C_PLAN §3.1；ART_REQUEST §9）。純邏輯、純表現：造型不影響任何規則。
## 0 號＝布衣（player_m／player_f）；1–8 號＝各性別 8 種造型（look_mNN／look_fNN，只有 idle 圖）。
## 入派後戰鬥圖與立繪一律用門派服裝（既有行為；M3C_PLAN O2），離派、被逐回到造型。

const LOOK_MAX := 8
const NAMES_M := ["布衣", "書生", "獵戶", "浪子", "少年俠客", "壯漢", "刀客", "富家公子", "西域旅人"]
const NAMES_F := ["布衣", "俠女", "村姑", "千金小姐", "江湖女子", "少女", "女刀客", "醫女", "苗疆少女"]

## 0 ≤ look ≤ LOOK_MAX
static func valid(look: int) -> bool:
	return look >= 0 and look <= LOOK_MAX

## 任意值（含 JSON 的 float、字串）轉成合法造型編號；不合法 → 0
static func sanitize(v: Variant) -> int:
	var n := 0
	match typeof(v):
		TYPE_INT:
			n = int(v)
		TYPE_FLOAT:
			if float(v) != floor(float(v)):
				return 0
			n = int(v)
		_:
			return 0
	return n if valid(n) else 0

static func _is_female(gender: String) -> bool:
	return gender == "F"

## 0 → "player_m"/"player_f"；n → "look_m%02d"/"look_f%02d"；不合法 → 0 號
static func art_ref(gender: String, look: int) -> String:
	var g := "f" if _is_female(gender) else "m"
	if not valid(look) or look == 0:
		return "player_" + g
	return "look_%s%02d" % [g, look]

## sect != "" → "<sect>_<m|f>"；否則 art_ref
static func battle_look(sect: String, gender: String, look: int) -> String:
	if sect != "":
		return "%s_%s" % [sect, "f" if _is_female(gender) else "m"]
	return art_ref(gender, look)

static func name_of(gender: String, look: int) -> String:
	var names: Array = NAMES_F if _is_female(gender) else NAMES_M
	return String(names[look if valid(look) else 0])

## 該性別全部造型：[{ look, name, art }]（0..LOOK_MAX）
static func catalog(gender: String) -> Array:
	var out: Array = []
	for i in LOOK_MAX + 1:
		out.append({ "look": i, "name": name_of(gender, i), "art": art_ref(gender, i) })
	return out
