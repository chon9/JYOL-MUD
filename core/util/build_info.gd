class_name BuildInfo
extends RefCounted
## M3C2_PLAN §6.1：遊戲版本、連線協定、資料指紋（標題畫面版本列與握手拒絕訊息共用；純靜態）。
## 版本只是資訊（R14）：能不能連線看協定與資料指紋（content_hash）。

const FULL_SPACE := "　"

## ProjectSettings application/config/version；空時 "0.0.0"
static func version() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	return "0.0.0" if v.strip_edges() == "" else v.strip_edges()

## Protocol.VERSION
static func protocol() -> int:
	return int(Protocol.VERSION)

## 去掉 "sha256:" 取前 12 字（空字串回空）
static func fingerprint12(content_hash: String) -> String:
	var h := content_hash.strip_edges()
	if h.begins_with("sha256:"):
		h = h.substr(7)
	return h.substr(0, 12)

## "v0.6.1.0　協定 5　資料 9d24a2e10ccc"（全形空白分隔）
static func line(content_hash: String) -> String:
	return format_line(version(), protocol(), fingerprint12(content_hash))

## 任意一組值的同格式字串（拒絕訊息顯示主機那一邊用）
static func format_line(ver: String, proto: int, fp12: String) -> String:
	return "v%s%s協定 %d%s資料 %s" % [ver, FULL_SPACE, proto, FULL_SPACE, fp12 if fp12 != "" else "?"]

## §6.3 主機送出的拒絕字串："<code>|<主機版本>|<主機協定>|<主機指紋12>"
static func reject_reason(code: String, content_hash: String) -> String:
	return "%s|%s|%d|%s" % [code, version(), protocol(), fingerprint12(content_hash)]

## 拆開拒絕字串：{ code, host: { version, protocol, fp } 或 {}（舊主機只送代碼） }
static func parse_reject(reason: String) -> Dictionary:
	var parts := reason.split("|")
	var out := { "code": parts[0] if parts.size() > 0 else reason, "host": {} }
	if parts.size() >= 4:
		out["host"] = { "version": parts[1], "protocol": int(parts[2]) if parts[2].is_valid_int() else 0,
			"fp": parts[3] }
	return out
