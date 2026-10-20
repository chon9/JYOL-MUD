class_name PatchApplier
extends RefCounted
## 套用 patches/<era>.json（TECH_ARCH 5.5.3）。只有生效的 era 才套用，依 eras.order 由小到大。

## view: table -> {id -> row}（就地修改）；eras: {id -> row}；on: {era_id: true}
## patches: era_id -> Array[row]。回傳錯誤清單。
static func apply(view: Dictionary, eras: Dictionary, on: Dictionary, patches: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var order: Array = []
	for era_id in patches:
		if on.has(era_id):
			order.append(era_id)
	order.sort_custom(func(a, b): return int(eras.get(a, {}).get("order", 0)) < int(eras.get(b, {}).get("order", 0)))
	for era_id in order:
		for p in patches[era_id]:
			var table: String = p.get("target_table", "")
			var target: String = p.get("target_id", "")
			if not view.has(table) or not view[table].has(target):
				errs.append("patch %s: target %s.%s not active" % [p.get("id", "?"), table, target])
				continue
			match p.get("op", ""):
				"merge":
					var set_fields: Dictionary = p.get("set", {})
					for k in set_fields:
						view[table][target][k] = set_fields[k] if not (set_fields[k] is Dictionary or set_fields[k] is Array) else set_fields[k].duplicate(true)
				"remove":
					view[table].erase(target)
				_:
					errs.append("patch %s: unknown op '%s'" % [p.get("id", "?"), p.get("op", "")])
	return errs
