package math

// Small functions every package reaches for: clamping, interpolation and
// integer division that rounds down. All @inlinable, so kernels can call
// them too.

/// Clamp is x limited to [lo, hi]. A NaN x stays NaN.
@inlinable public func Clamp(_ x: float32, _ lo: float32, _ hi: float32) -> float32 {
    if x < lo { return lo }
    if x > hi { return hi }
    return x
}

@inlinable public func Clamp(_ x: float64, _ lo: float64, _ hi: float64) -> float64 {
    if x < lo { return lo }
    if x > hi { return hi }
    return x
}

@inlinable public func Clamp(_ x: int, _ lo: int, _ hi: int) -> int {
    if x < lo { return lo }
    if x > hi { return hi }
    return x
}

@inlinable public func Clamp(_ x: int32, _ lo: int32, _ hi: int32) -> int32 {
    if x < lo { return lo }
    if x > hi { return hi }
    return x
}

@inlinable public func Clamp(_ x: int64, _ lo: int64, _ hi: int64) -> int64 {
    if x < lo { return lo }
    if x > hi { return hi }
    return x
}

/// Saturate is x limited to [0, 1], as shading languages name it.
@inlinable public func Saturate(_ x: float32) -> float32 { return Clamp(x, 0, 1) }

@inlinable public func Saturate(_ x: float64) -> float64 { return Clamp(x, 0, 1) }

/// Lerp is a + (b - a)·t: a at t = 0, b at t = 1.
@inlinable public func Lerp(_ a: float32, _ b: float32, _ t: float32) -> float32 { return a + (b - a) * t }

@inlinable public func Lerp(_ a: float64, _ b: float64, _ t: float64) -> float64 { return a + (b - a) * t }

/// FloorDiv is a / b rounded toward negative infinity (Python's //), where
/// the / operator rounds toward zero. b must not be zero.
@inlinable public func FloorDiv(_ a: int, _ b: int) -> int {
    let q = a / b
    return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q
}

@inlinable public func FloorDiv(_ a: int64, _ b: int64) -> int64 {
    let q = a / b
    return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q
}

/// FloorMod is the remainder of FloorDiv: it takes b's sign (Python's %),
/// where the % operator takes a's.
@inlinable public func FloorMod(_ a: int, _ b: int) -> int {
    let r = a % b
    return (r != 0 && ((r < 0) != (b < 0))) ? r + b : r
}

@inlinable public func FloorMod(_ a: int64, _ b: int64) -> int64 {
    let r = a % b
    return (r != 0 && ((r < 0) != (b < 0))) ? r + b : r
}

/// FloorMod on floats is x - y·⌊x / y⌋: the remainder with y's sign, for
/// wrapping angles and hues into [0, y).
@inlinable public func FloorMod(_ x: float32, _ y: float32) -> float32 { return x - y * (x / y).rounded(.down) }

@inlinable public func FloorMod(_ x: float64, _ y: float64) -> float64 { return x - y * (x / y).rounded(.down) }

/// CeilDiv is a / b rounded toward positive infinity, for a ≥ 0 and b > 0:
/// how many b-sized pieces cover a.
@inlinable public func CeilDiv(_ a: int, _ b: int) -> int { return (a + b - 1) / b }

/// RoundToInt is x rounded to the nearest int32, ties to even (C's lrintf);
/// out-of-range values and NaN give 0 rather than trapping.
@inlinable public func RoundToInt(_ x: float32) -> int32 {
    let r = x.rounded(.toNearestOrEven)
    if !(r >= -2147483648.0 && r < 2147483648.0) { return 0 }
    return int32(r)
}
