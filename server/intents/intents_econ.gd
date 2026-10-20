## （不設 class_name：GameHost 依 M3B_INTENTS 以路徑 load()，L3／K3）
extends RefCounted
## M3b 經濟 intent（M3B_PLAN §6；WP-ECON）：錢莊 bank_open／bank_put／bank_take／bank_money，
## 鏢局 consign_send／consign_list／consign_take。host.bank／host.escort 為 null 時該組不註冊（intent 回 unknown_intent）。
## 驗證順序的前三步（no_character → in_battle → jailed）由 GameHost._run_intent 做（NEEDS_CHAR、IDLE、坐牢關卡），
## 系統方法裡也再擋一次（測試與其他呼叫端直接呼叫時一樣安全）。

const F := GameHost.NEEDS_CHAR | GameHost.IDLE

# intent 名（§6，Protocol 常數）
const I_BANK_OPEN := Protocol.I_BANK_OPEN
const I_BANK_PUT := Protocol.I_BANK_PUT
const I_BANK_TAKE := Protocol.I_BANK_TAKE
const I_BANK_MONEY := Protocol.I_BANK_MONEY
const I_CONSIGN_SEND := Protocol.I_CONSIGN_SEND
const I_CONSIGN_LIST := Protocol.I_CONSIGN_LIST
const I_CONSIGN_TAKE := Protocol.I_CONSIGN_TAKE

static func register(host: GameHost) -> void:
	var bank = host.get("bank")
	if bank != null:
		host.register(I_BANK_OPEN, func(s: Session, a: Dictionary) -> Dictionary:
			return bank.open(s, str(a.get("npc", ""))), F)
		host.register(I_BANK_PUT, func(s: Session, a: Dictionary) -> Dictionary:
			return bank.put(s, str(a.get("npc", "")), str(a.get("uid", "")), _int(a.get("n", 0))), F)
		host.register(I_BANK_TAKE, func(s: Session, a: Dictionary) -> Dictionary:
			return bank.take(s, str(a.get("npc", "")), str(a.get("uid", "")), _int(a.get("n", 0))), F)
		host.register(I_BANK_MONEY, func(s: Session, a: Dictionary) -> Dictionary:
			return bank.money(s, str(a.get("npc", "")), _int(a.get("amount", 0))), F)
	var escort = host.get("escort")
	if escort != null:
		host.register(I_CONSIGN_SEND, func(s: Session, a: Dictionary) -> Dictionary:
			var items: Variant = a.get("items", [])
			return escort.send(s, str(a.get("npc", "")), str(a.get("to", "")), str(a.get("city", "")),
				items if items is Array else [], _int(a.get("money", 0))), F)
		host.register(I_CONSIGN_LIST, func(s: Session, a: Dictionary) -> Dictionary:
			return escort.list(s, str(a.get("npc", ""))), F)
		host.register(I_CONSIGN_TAKE, func(s: Session, a: Dictionary) -> Dictionary:
			return escort.take(s, str(a.get("npc", "")), str(a.get("id", ""))), F)

## JSON 數字轉 int（G：JSON 數字一律轉 int）
static func _int(v: Variant) -> int:
	if v is int:
		return v
	if v is float:
		return int(v)
	if v is String and (v as String).is_valid_int():
		return int(v)
	return 0
