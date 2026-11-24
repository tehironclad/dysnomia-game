class_name TokenBucket
extends RefCounted
## A token bucket: `rate` tokens a second, up to `burst`. take() spends one
## (or `cost`) if there is enough; otherwise refuses and spends nothing.
## Time is passed in (seconds), so tests drive it.

var rate := 1.0
var burst := 1.0
var tokens := 1.0
var _t := -1.0


func _init(p_rate: float = 1.0, p_burst: float = 1.0) -> void:
	rate = p_rate
	burst = p_burst
	tokens = p_burst


func take(now_s: float, cost: float = 1.0) -> bool:
	if _t >= 0.0:
		tokens = minf(burst, tokens + (now_s - _t) * rate)
	_t = now_s
	if tokens >= cost:
		tokens -= cost
		return true
	return false
