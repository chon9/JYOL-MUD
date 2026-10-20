## （不設 class_name：GameHost 依 STORY_INTENTS 以路徑 load()，S2／K3）
extends RefCounted
## 活的江湖的 intent（STORY_PLAN §4.14、§5）：villain_reply、rumor_list；
## 以及伺服器選項 rumor_chat_inner_min（江湖謠言頻道的基本內功門檻，§5.1；預設 80 照原作，0 = 不限）。
## 系統可能為 null（WanderSystem／RumorSystem 載入失敗）：一律用 host.get() 取再判斷。

const C := GameHost.NEEDS_CHAR
const INNER_SKILL := "basic_inner"
const R_INNER := "req_skill_min"

static func register(host: GameHost) -> void:
	host.register(Protocol.I_VILLAIN_REPLY, func(s: Session, a: Dictionary) -> Dictionary:
		var w = host.get("wander")
		if w == null or not w.has_method("villain_reply"):
			return GameHost.fail(Protocol.R_VILLAIN_NONE)
		return w.villain_reply(s, str(a["wid"]), str(a["choice"])), C)
	host.register(Protocol.I_RUMOR_LIST, func(s: Session, _a: Dictionary) -> Dictionary:
		var items: Array = []
		var r = host.get("rumor")
		if r != null and r.has_method("list_for"):
			items = r.list_for(s)
		elif r != null and r.has_method("recent"):
			items = r.recent(50)
		host.tell(s, Protocol.CH_SYSTEM, Protocol.E_RUMOR_LIST, { "items": items }, true)
		return GameHost.ok(), C)
	_wrap_rumor_chat(host)

## 江湖謠言頻道的基本內功門檻（rumor_chat_inner_min；審查修正：預設 80 照研究「謠 needs 基本內功 80」（鐵心網 FAQ），
## 開放年代【待考證】，擁有者可在伺服器設定改成 0）。
## 聊天由 SocialSystem（凍結檔）處理；這裡包住已註冊的 chat handler，只在選項 > 0 且頻道是 CHAT_RUMOR 時先擋。
## STORY_PLAN 缺漏：若 STORY_INTENTS 比 M2 的 intents_social 先註冊，chat 會被覆蓋回去，門檻失效（GameHost 目前的順序是 M2 → story）。
static func _wrap_rumor_chat(host: GameHost) -> void:
	var ws: Object = host.ws
	if ws == null or not ws.has_method("register_intent"):
		return
	var handlers: Variant = ws.get("_handlers")
	if not (handlers is Dictionary) or not (handlers as Dictionary).has(Protocol.I_CHAT):
		return
	var inner: Callable = handlers[Protocol.I_CHAT]
	ws.register_intent(Protocol.I_CHAT, func(s: Session, a: Dictionary) -> Dictionary:
		var need := int(host.options.get("rumor_chat_inner_min", 0))
		if need > 0 and str(a.get("ch", "")) == Protocol.CH_CHAT_RUMOR and s != null and s.character != null \
				and int(s.character.skills.level(INNER_SKILL)) < need:
			return GameHost.fail(R_INNER)
		return inner.call(s, a))
