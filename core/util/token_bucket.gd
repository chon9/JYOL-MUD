class_name TokenBucket
extends RefCounted
## 速率限制（TECH_ARCH 6.3 第 3 步）。時間由呼叫端傳入，方便單元測試。

var capacity: float
var refill_per_sec: float
var tokens: float
var _last_s := -1.0

func _init(p_capacity: float = 20.0, p_refill_per_sec: float = 20.0) -> void:
	capacity = p_capacity
	refill_per_sec = p_refill_per_sec
	tokens = p_capacity

func allow(now_s: float = -1.0) -> bool:
	if now_s < 0.0:
		now_s = Time.get_ticks_msec() / 1000.0
	if _last_s >= 0.0:
		tokens = minf(capacity, tokens + maxf(0.0, now_s - _last_s) * refill_per_sec)
	_last_s = now_s
	if tokens >= 1.0:
		tokens -= 1.0
		return true
	return false
