class_name IntentsSocial
extends RefCounted
## chat（覆蓋 M0 的 WorldServer._intent_chat）、mail_send、mail_list、mail_read、mail_delete（M2_PLAN 4.2、4.6.6、4.6.7）
## GameHost 依 M2_INTENTS 以路徑載入本檔並呼叫 register(host)（4.6.1、H4）。

# 4.1 的 intent 常數（別名）
const I_MAIL_SEND := Protocol.I_MAIL_SEND
const I_MAIL_LIST := Protocol.I_MAIL_LIST
const I_MAIL_READ := Protocol.I_MAIL_READ
const I_MAIL_DELETE := Protocol.I_MAIL_DELETE

static func register(host: GameHost) -> void:
	install(host)

## 註冊處理器並回傳實際使用的系統 { social, mail }。
## 優先用 GameHost 依 M2_SYSTEMS 載入的 host.social／host.mail；沒有時（WP-HOST 尚未接線或載入失敗，H4）
## 由這裡建立一份只給這些處理器用的實例，讓聊天與飛鴿照樣可用。
static func install(host: GameHost) -> Dictionary:
	var social: Variant = host.get("social")
	if social == null:
		social = SocialSystem.new(host)
	var mail: Variant = host.get("mail")
	if mail == null:
		mail = MailSystem.new(host)
	# 旗標 0：未選角的 session 也能用千里傳音（4.6.6 第 2 步）
	host.register(Protocol.I_CHAT, func(s: Session, a: Dictionary) -> Dictionary:
		return social.chat(s, a), 0)
	host.register(I_MAIL_SEND, func(s: Session, a: Dictionary) -> Dictionary:
		return mail.send(s, str(a.get("to", "")), str(a.get("text", ""))), GameHost.NEEDS_CHAR)
	host.register(I_MAIL_LIST, func(s: Session, _a: Dictionary) -> Dictionary:
		return mail.list(s), GameHost.NEEDS_CHAR)
	host.register(I_MAIL_READ, func(s: Session, a: Dictionary) -> Dictionary:
		return mail.read(s, str(a.get("id", ""))), GameHost.NEEDS_CHAR)
	host.register(I_MAIL_DELETE, func(s: Session, a: Dictionary) -> Dictionary:
		return mail.delete(s, str(a.get("id", ""))), GameHost.NEEDS_CHAR)
	return { "social": social, "mail": mail }
