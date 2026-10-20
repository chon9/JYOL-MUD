class_name CharacterStore
extends RefCounted
## 角色檔的載入、存檔、列表、刪除；名稱唯一索引（world.json char_names）。M1_PLAN 3.5.2、3.10。

var host: GameHost

func _init(p_host: GameHost) -> void:
	host = p_host

func _world_id() -> String:
	return host.ws.world_id

func names() -> Dictionary:
	var d: Variant = host.ws.world.get("char_names")
	if not (d is Dictionary):
		d = {}
		host.ws.world["char_names"] = d
	return d

static func name_key(n: String) -> String:
	return n.strip_edges().to_lower()

func ids(identity: String) -> Array:
	return SaveManager.list_character_ids(_world_id(), identity)

func has_char(identity: String, char_id: String) -> bool:
	return char_id != "" and char_id in ids(identity)

func count(identity: String) -> int:
	return ids(identity).size()

## 讀檔（本體壞掉自動退回備份）；失敗回 null。在線中的角色回傳記憶體裡的那一份。
func load_char(identity: String, char_id: String):
	var online: Session = host.session_for_char(char_id)
	if online != null and online.identity == identity:
		return online.character
	var r: Dictionary = SaveManager.load_character(_world_id(), identity, char_id)
	if not r.get("ok", false) or not (r.get("data") is Dictionary):
		return null
	var ch = Character.from_dict(r["data"])
	if ch == null or str(ch.id) != char_id:
		return null
	if str(ch.identity) == "":
		ch.identity = identity
	return ch

func list_chars(identity: String) -> Array:
	var out: Array = []
	for id in ids(identity):
		var ch = load_char(identity, id)
		if ch != null:
			out.append(ch)
	return out

## 3.9.5
func summaries(identity: String) -> Array:
	var out: Array = []
	for ch in list_chars(identity):
		out.append(ch.to_summary(host.tables))
	return out

func save(ch) -> Error:
	var err: Error = SaveManager.save_character(_world_id(), str(ch.identity), ch.to_dict())
	if err != OK:
		host.ws._warn("角色存檔失敗，舊檔已保留：" + SaveManager.last_error)
	return err

func name_taken(n: String) -> bool:
	var k := name_key(n)
	if not names().has(k):
		return false
	# 索引裡有，但角色檔已不存在（例如手動刪檔）→ 視為可用並清掉索引
	var e: Dictionary = names()[k]
	if not has_char(str(e.get("identity", "")), str(e.get("char_id", ""))):
		names().erase(k)
		return false
	return true

func register_name(ch) -> void:
	names()[name_key(str(ch.name))] = { "identity": str(ch.identity), "char_id": str(ch.id) }

func unregister_char(char_id: String) -> void:
	for k in names().keys():
		if str(names()[k].get("char_id", "")) == char_id:
			names().erase(k)

func delete(identity: String, char_id: String) -> Error:
	var err := SaveManager.delete_character(_world_id(), identity, char_id)
	if err == OK:
		unregister_char(char_id)
	return err
