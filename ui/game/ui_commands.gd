class_name UiCommands
extends RefCounted
## 指令窗（AUTHENTIC_UI_SPEC §8.5）與熱鍵列（§6.2）共用的指令表。原作有 溝通／行動／武學／情感／組織／雜項 6 分頁；
## 本作目前的內容：武學＝修煉內力、施展內功（精／氣／神）；行動＝查看、生活技能（依場景）；雜項＝任務、地圖。
## 溝通、情感先顯示「尚未開放」灰鈕。實際執行（送 intent、開視窗）在主畫面 run_command()。
## M3b（M3B_PLAN §7）：組織分頁開放（「組織」→ 組織面板）；行動多「製作」（製作窗）與「乞討」（對目前的 NPC）；
## 雜項多「捉拿公敵」（列出同房可抓的人）。
## 熱鍵的 payload：指令 "cmd:<id>"、物品 "item:<item id>"。

const TABS := ["COMM", "ACTION", "MARTIAL", "EMOTE", "GUILD", "MISC"]
const TAB_LABELS := { "COMM": "溝通", "ACTION": "行動", "MARTIAL": "武學", "EMOTE": "情感", "GUILD": "組織", "MISC": "雜項" }
const LOCKED_TABS := ["COMM", "EMOTE"]
const LOCKED_TIP := "尚未開放（M4／M5 社交功能）"
const EXERT_COST := 20

## id -> { tab, label（完整名稱）, glyph（鈕面字）, tip }
const COMMANDS := {
	"look": { "tab": "ACTION", "label": "查看", "glyph": "查看", "tip": "重新查看四周；在野外會仔細偵察，發現怪物時可以選擇迎戰或離開" },
	"meditate": { "tab": "MARTIAL", "label": "修煉內力", "glyph": "修煉", "tip": "需要基本內功；內力滿了會修煉，提升內力上限" },
	"exert_qi": { "tab": "MARTIAL", "label": "施展內功回氣", "glyph": "回氣", "tip": "耗內力 20，回復氣" },
	"exert_jing": { "tab": "MARTIAL", "label": "施展內功回精", "glyph": "回精", "tip": "耗內力 20，回復精" },
	"exert_shen": { "tab": "MARTIAL", "label": "施展內功回神", "glyph": "回神", "tip": "耗內力 20，回復神" },
	"quests": { "tab": "MISC", "label": "任務", "glyph": "任務", "tip": "任務清單（Ctrl+6）" },
	"map": { "tab": "MISC", "label": "地圖", "glyph": "地圖", "tip": "江湖地圖（Ctrl+M／M）" },
	# M3b
	"craft": { "tab": "ACTION", "label": "製作", "glyph": "製作", "tip": "生活技能製作窗：依這裡的設施列出能採集、打獵與製作的東西" },
	"beg": { "tab": "ACTION", "label": "乞討", "glyph": "乞討", "tip": "向身旁的人乞討（門派技能，耗精、神；同一個人要隔一陣子）" },
	"org": { "tab": "GUILD", "label": "組織", "glyph": "組織", "tip": "組織面板：成員、位階、封號、邀請；沒有組織時到各城衙門找書吏" },
	"seize": { "tab": "MISC", "label": "捉拿公敵", "glyph": "捉拿", "tip": "捉拿這裡的本派公敵（神鵰大俠）" },
}
## 生活技能指令 id：work:<life skill id>（行動分頁，依場景 features 與已學技能）
const WORK_PREFIX := "work:"
## 熱鍵預設（§6.3：修煉內力、施展內功、查看放 F1–F3）
const DEFAULT_HOTBAR := ["meditate", "exert_qi", "look", "exert_jing", "exert_shen", "", "", ""]

static func tab_label(tab: String) -> String:
	return TAB_LABELS.get(tab, tab)

static func is_work(id: String) -> bool:
	return id.begins_with(WORK_PREFIX)

## 這一頁的指令 id（行動分頁會加上所有生活技能）
static func ids_in_tab(tab: String) -> Array:
	var out: Array = []
	for id in COMMANDS:
		if str(COMMANDS[id]["tab"]) == tab:
			out.append(id)
	if tab == "ACTION":
		for f in UiKeys.FEATURE_LIFE:
			var sk: String = UiKeys.FEATURE_LIFE[f]
			if not out.has(WORK_PREFIX + sk):
				out.append(WORK_PREFIX + sk)
	return out

static func label(id: String) -> String:
	if is_work(id):
		var sk := id.substr(WORK_PREFIX.length())
		return str(UiKeys.LIFE_VERBS.get(sk, sk))
	return str(COMMANDS.get(id, {}).get("label", id))

static func glyph(id: String) -> String:
	if is_work(id):
		return label(id).left(2)
	return str(COMMANDS.get(id, {}).get("glyph", label(id).left(2)))

static func tip(id: String) -> String:
	if is_work(id):
		return "%s（要在有這種地形的地方、而且學過這項生活技能）" % label(id)
	return str(COMMANDS.get(id, {}).get("tip", ""))

static func is_known(id: String) -> bool:
	return COMMANDS.has(id) or (is_work(id) and UiKeys.LIFE_VERBS.has(id.substr(WORK_PREFIX.length())))

## 依目前角色與場景判斷能不能按：回傳 "" = 可以；否則是灰色時的提示
static func unavailable_reason(id: String, sheet: Dictionary, view: Dictionary) -> String:
	var vit: Dictionary = sheet.get("vitals", {})
	match id:
		"meditate":
			if UiBuild.num(vit.get("neili_max", 0)) <= 0:
				return "需要先學基本內功"
		"exert_qi", "exert_jing", "exert_shen":
			if UiBuild.num(vit.get("neili", 0)) < EXERT_COST:
				return "內力不足 %d" % EXERT_COST
		"beg":
			if SectUi.practice(SectUi.my_sect(sheet)).is_empty():
				return "本派沒有乞討這門功夫"
			if SectUi.beg_target(view, sheet) == "":
				return "這裡沒有可以乞討的人"
		"seize":
			if SeizeDialog.targets(view).is_empty():
				return "這裡沒有本派的公敵"
	if is_work(id):
		var sk := id.substr(WORK_PREFIX.length())
		var here := false
		for f in view.get("features", []):
			if str(UiKeys.FEATURE_LIFE.get(str(f), "")) == sk:
				here = true
		if not here:
			return "這裡不能%s" % label(id)
		var known := false
		for s in sheet.get("skills", []):
			if s is Dictionary and str(s.get("id", "")) == sk and UiBuild.num(s.get("level", 0)) >= 1:
				known = true
		if not known:
			return "還沒學會%s" % UiClient.name_of("life_skills", sk, label(id))
	return ""

## 熱鍵物品：背包裡第一個這種物品（id）
static func find_item(sheet: Dictionary, item_id: String) -> Dictionary:
	for it in sheet.get("inventory", []):
		if it is Dictionary and str(it.get("id", "")) == item_id:
			return it
	return {}

static func item_count(sheet: Dictionary, item_id: String) -> int:
	var n := 0
	for it in sheet.get("inventory", []):
		if it is Dictionary and str(it.get("id", "")) == item_id:
			n += UiBuild.num(it.get("n", 1))
	return n
