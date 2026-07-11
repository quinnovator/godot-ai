class_name PixRng
extends RefCounted

## Bit-exact Mulberry32 stream used by the original PixCore simulation.
##
## GDScript integers are signed 64-bit values. `_mul_u32` deliberately computes
## only the lower 32 bits using 16-bit limbs, avoiding a signed overflow while
## preserving the C++ uint32 contract.

const U32_MASK := 0xffffffff
const TWO_PI := 6.283185307179586

var _state: int


func _init(seed_value: int = 0) -> void:
	_state = seed_value & U32_MASK


func get_state() -> int:
	return _state


func set_state(value: int) -> void:
	_state = value & U32_MASK


func next() -> float:
	_state = (_state + 0x6d2b79f5) & U32_MASK
	var value := _state
	value = _mul_u32(value ^ (value >> 15), value | 1)
	var mixed := _mul_u32(value ^ (value >> 7), value | 61)
	value = (value ^ ((value + mixed) & U32_MASK)) & U32_MASK
	return float((value ^ (value >> 14)) & U32_MASK) / 4294967296.0


func gauss(mean := 0.0, deviation := 1.0) -> float:
	var u := 0.0
	while u == 0.0:
		u = next()
	var v := next()
	return mean + deviation * sqrt(-2.0 * log(u)) * cos(TWO_PI * v)


func categorical(weights: PackedFloat64Array) -> int:
	if weights.is_empty():
		return -1
	var total := 0.0
	for weight in weights:
		total += weight
	var draw := next() * total
	for index in range(weights.size()):
		draw -= weights[index]
		if draw <= 0.0:
			return index
	return weights.size() - 1


static func stream_seed(seed_value: int, epoch: int, domain: int, event_id: int) -> int:
	var value := _fmix32((seed_value + 0x9e3779b9) & U32_MASK)
	value = _fmix32(value ^ ((epoch + 0x85ebca6b) & U32_MASK))
	value = _fmix32(value ^ _mul_u32(domain, 0xc2b2ae35))
	return _fmix32(value ^ _mul_u32(event_id, 0x27d4eb2f))


static func _fmix32(value: int) -> int:
	value = (value ^ (value >> 16)) & U32_MASK
	value = _mul_u32(value, 0x85ebca6b)
	value = (value ^ (value >> 13)) & U32_MASK
	value = _mul_u32(value, 0xc2b2ae35)
	return (value ^ (value >> 16)) & U32_MASK


static func _mul_u32(a: int, b: int) -> int:
	var a_low := a & 0xffff
	var a_high := (a >> 16) & 0xffff
	var b_low := b & 0xffff
	var b_high := (b >> 16) & 0xffff
	return (a_low * b_low + ((a_high * b_low + a_low * b_high) << 16)) & U32_MASK
