class_name CliArgs
extends RefCounted
## 解析 `--` 之後的使用者參數（TECH_ARCH 7.2）。
## "--key=value" -> {key: "value"}；"--flag" -> {flag: true}。

const ALIASES := {
	"host-enet": "enet-host",
	"join-enet": "enet-join",
	"host-steam": "steam-host",
}

static func parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if not a.begins_with("--"):
			continue
		var body := a.substr(2)
		var key := body
		var value: Variant = true
		var eq := body.find("=")
		if eq != -1:
			key = body.substr(0, eq)
			value = body.substr(eq + 1)
		key = ALIASES.get(key, key)
		out[key] = value
	return out

static func current() -> Dictionary:
	return parse(OS.get_cmdline_user_args())

## "127.0.0.1:24565" -> ["127.0.0.1", 24565]
static func split_host_port(s: String, default_port: int) -> Array:
	var i := s.rfind(":")
	if i == -1:
		return [s, default_port]
	var port := s.substr(i + 1).to_int()
	return [s.substr(0, i), port if port > 0 else default_port]
