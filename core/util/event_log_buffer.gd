class_name EventLogBuffer
extends RefCounted
## 環狀緩衝區（TECH_ARCH 11.3），預設 2000 則。

var capacity: int
var _items: Array = []
var _start := 0

func _init(p_capacity: int = 2000) -> void:
	capacity = maxi(1, p_capacity)

func push(item: Variant) -> void:
	if _items.size() < capacity:
		_items.append(item)
	else:
		_items[_start] = item
		_start = (_start + 1) % capacity

func size() -> int:
	return _items.size()

func clear() -> void:
	_items.clear()
	_start = 0

## 由舊到新
func to_array() -> Array:
	if _items.size() < capacity:
		return _items.duplicate()
	return _items.slice(_start) + _items.slice(0, _start)

func last(n: int) -> Array:
	var all := to_array()
	return all.slice(maxi(0, all.size() - n))
