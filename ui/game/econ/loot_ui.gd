class_name LootUi
extends RefCounted
## 稀有度顏色與名稱、裝備說明文字（M3C_PLAN §6.1、§6.8；WP-LOOT）。所有介面共用（背包、戰鬥結果、商店…）。
## 稀有度 5 級【設計提案】：凡品、良品、精品、珍品、神兵。

const RARITIES := ["COMMON", "FINE", "RARE", "TREASURE", "DIVINE"]
const COLORS := {
	"COMMON": Color("#e8e0d0"), "FINE": Color("#6fcf6f"), "RARE": Color("#5b9bf0"),
	"TREASURE": Color("#b77ae8"), "DIVINE": Color("#f0b43a"),
}
const NAMES := { "COMMON": "凡品", "FINE": "良品", "RARE": "精品", "TREASURE": "珍品", "DIVINE": "神兵" }
## M3c 審查：與背包人形的部位名一致（AUTHENTIC_UI_SPEC 背包人形：頭盔、頸、右手、護腕、衣服、披風、戒指、靴子【原作證實】）
const SLOT_NAMES := { "WEAPON": "兵器", "ARMOR": "衣服", "HEAD": "頭盔", "NECK": "頸", "WRIST": "護腕",
	"CLOAK": "披風", "RING": "戒指", "BOOTS": "靴子" }
const WEAPON_NAMES := { "SWORD": "劍", "BLADE": "刀", "STAFF": "杖", "WHIP": "鞭", "FIST": "拳掌", "SPEAR": "槍" }
const ATTR_NAMES := { "str": "臂力", "agi": "機敏", "wit": "悟性", "con": "根骨", "guts": "膽識", "luck": "福緣", "cal": "定力" }

static func norm(r: Variant) -> String:
	var s := str(r) if r != null else ""
	return s if RARITIES.has(s) else "COMMON"

static func rarity_color(r: Variant) -> Color:
	return COLORS[norm(r)]

static func rarity_name(r: Variant) -> String:
	return NAMES[norm(r)]

static func rank(r: Variant) -> int:
	return RARITIES.find(norm(r))

## 精品以上名字前加「【精品】」等字樣（§6.7）
static func decorated_name(name: String, r: Variant) -> String:
	return ("【%s】%s" % [rarity_name(r), name]) if rank(r) >= 2 else name

## BBCode：依稀有度上色的名字
static func bb_name(name: String, r: Variant, decorate := true) -> String:
	var t := decorated_name(name, r) if decorate else name
	return "[color=#%s]%s[/color]" % [rarity_color(r).to_html(false), t]

## 屬性加成文字：「定力 +5、臂力 +2」
static func bonus_text(bonus: Variant) -> String:
	if not (bonus is Dictionary) or (bonus as Dictionary).is_empty():
		return ""
	var parts: PackedStringArray = []
	var keys: Array = (bonus as Dictionary).keys()
	keys.sort()
	for k in keys:
		var v := int(bonus[k])
		parts.append("%s %s%d" % [ATTR_NAMES.get(str(k), str(k)), "+" if v >= 0 else "", v])
	return "、".join(parts)

## 物品詳情（§6.8）：it = 角色表背包項目（rarity、slot、req_ok、req_text、bonus、official），row = items 資料列（可空）。
## literacy = 讀書識字等級（秘笈說明用；-1 不顯示）。回傳 BBCode 多行。
static func detail_bb(it: Dictionary, row: Dictionary, literacy := -1) -> String:
	var r := norm(it.get("rarity", row.get("rarity", "COMMON")))
	var name := str(it.get("name", row.get("name", it.get("id", ""))))
	var lines: PackedStringArray = []
	lines.append("%s　[color=#%s]%s[/color]" % [bb_name(name, r, false), rarity_color(r).to_html(false), rarity_name(r)])
	var slot := str(it.get("slot", row.get("slot", "")))
	if slot != "":
		var head := "部位：" + str(SLOT_NAMES.get(slot, slot))
		if slot == "WEAPON":
			var wt := str(row.get("weapon_type", "FIST"))
			head += "　類型：" + str(WEAPON_NAMES.get(wt, wt)) + ("（爪）" if str(row.get("fx", "")) == "claw" else "")
			head += "　攻擊 +%d" % int(row.get("atk", 0))
		else:
			head += "　防禦 +%d" % int(row.get("def", 0))
		head += "　重量 %d" % int(it.get("weight", row.get("weight", 0)))
		lines.append(head)
	var bt := bonus_text(it.get("bonus", row.get("bonus", {})))
	if bt != "":
		lines.append("屬性加成：" + bt)
	if not bool(it.get("req_ok", true)):
		lines.append("[color=#ff5040]條件：%s（無法裝備）[/color]" % str(it.get("req_text", "")))
	elif row.get("requires") is Array and not (row["requires"] as Array).is_empty():
		lines.append("條件：" + req_text_of(row))
	# M3c 第二輪審查：不再顯示「官方：防禦 +10／重量 0」——跟上一行本作的數值（O13 換算後）互相矛盾，看起來像開發者註記；
	# 原值仍在 items.json 的 official 欄（資料與研究用）
	var m: Variant = row.get("manual", null)
	if m is Dictionary and str((m as Dictionary).get("skill", "")) != "":
		lines.append(manual_text(m, literacy))
	if bool(row.get("divine", false)):
		lines.append("[color=#f0b43a]全服唯一・被玩家擊殺時歸殺手所有[/color]")
	return "\n".join(lines)

## 秘笈說明：「研讀可練 基本醫術（最多 60 級）；需要讀書識字 20 級。讀書識字 X 級：最多讀到 Y 級」
static func manual_text(m: Dictionary, literacy := -1) -> String:
	var skill := str(m.get("skill", ""))
	var sname := str(UiClient.row("basic_skills", skill).get("name", UiClient.row("martial_arts", skill).get("name", skill)))
	var cap := int(m.get("cap", 0))
	var need := int(m.get("literacy_min", 0))
	var t := "秘笈：研讀可練%s（最多 %d 級）；需要讀書識字 %d 級；每讀一次花 %d 點學點" % [sname, cap, need, Learning.LP_PER_TIME]
	if literacy >= 0:
		if literacy < need:
			t += "\n[color=#ff5040]讀書識字 %d 級：還讀不懂這本書[/color]" % literacy
		else:
			t += "\n讀書識字 %d 級：最多讀到 %d 級" % [literacy, mini(cap, literacy)]
	return t

static func req_text_of(row: Dictionary) -> String:
	var parts: PackedStringArray = []
	for c in row.get("requires", []):
		if c is Dictionary:
			if str(c.get("type", "")) == "gender":
				parts.append("限%s" % ("女性" if str(c.get("value", "")) == "F" else "男性"))
			else:
				# M3c 審查：不把內部的條件型別碼直接秀給玩家；用 Requirements.describe（主機的 req_text 也用它）
				var t := Requirements.describe(c, UiClient.tables())
				parts.append(t if t != "" and t != str(c.get("type", "")) else "另有條件")
	return "、".join(parts)

## 羊皮紙（淺底）上的稀有度色：凡品＝墨色（不上色），其他用另一組深色（M3c 第二輪審查：以前是淺色 darkened(0.45)，
## 珍品的淡紫在羊皮紙上幾乎看不見）。對比度 ≥ 4.5（test_ui_m3c_review2）
const PAPER_COLORS := {
	"COMMON": Color("#2b1a0e"), "FINE": Color("#1e6424"), "RARE": Color("#16478c"),
	"TREASURE": Color("#5e2390"), "DIVINE": Color("#8a4a00"),
}
static func paper_color(r: Variant) -> Color:
	return PAPER_COLORS[norm(r)]

## 深色底（戰報、背包格）上的稀有度色：凡品＝一般字色；其他用 COLORS 再提亮一點（背包格底色已帶稀有度色時也看得清楚）
static func dark_color(r: Variant) -> Color:
	var n := norm(r)
	if n == "COMMON":
		return COLORS[n]
	return COLORS[n].lightened(0.25)

## 深色底的 BBCode 名字（戰報的「得到：」行）
static func bb_name_dark(name: String, r: Variant, decorate := true) -> String:
	var t := decorated_name(name, r) if decorate else name
	return "[color=#%s]%s[/color]" % [dark_color(r).to_html(false), t]

static func bb_name_paper(name: String, r: Variant, decorate := true) -> String:
	var t := decorated_name(name, r) if decorate else name
	if norm(r) == "COMMON":
		return t
	# M3c 第二輪審查：不加粗（中文粗體是合成的，「【珍品】」與名字粗細、深淺看起來不一樣）
	return "[color=#%s]%s[/color]" % [paper_color(r).to_html(false), t]
