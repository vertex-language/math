// Package math is elementary functions in pure Vertex: the same code runs
// on the host and inside a kernel, and gives the same bits on every
// device that rounds each operation, because nothing here calls a C
// library or a device's approximate instruction. A GPU has no libm, and
// that is the reason for this package (proposed_vertex_kernel.md §6.5).
//
// The single-precision functions are Cephes' algorithms (Moshier): an
// argument reduced exactly or nearly so, then a minimax polynomial. Their
// errors are measured in tests/math against the host's double-precision
// libm, in units in the last place of the float32 result.
//
// Everything is @inlinable, and nothing reads a table or a global, so a
// kernel in any module compiles these into itself.
package math

// ---- what is one instruction ----

/// Sqrt is the square root, correctly rounded; NaN for a negative x.
@inlinable public func Sqrt(_ x: float32) -> float32 { return x.squareRoot() }

/// Floor is the greatest whole number not above x.
@inlinable public func Floor(_ x: float32) -> float32 { return x.rounded(.down) }

/// Ceil is the least whole number not below x.
@inlinable public func Ceil(_ x: float32) -> float32 { return x.rounded(.up) }

/// Trunc is x with its fraction dropped, towards zero.
@inlinable public func Trunc(_ x: float32) -> float32 { return x.rounded(.towardZero) }

/// Round is the nearest whole number, ties to even.
@inlinable public func Round(_ x: float32) -> float32 { return x.rounded(.toNearestOrEven) }

/// Abs is |x|.
@inlinable public func Abs(_ x: float32) -> float32 { return float32(bitPattern: x.bitPattern & 0x7FFFFFFF) }

/// CopySign is |x| with y's sign.
@inlinable public func CopySign(_ x: float32, _ y: float32) -> float32 {
    return float32(bitPattern: (x.bitPattern & 0x7FFFFFFF) | (y.bitPattern & 0x80000000))
}

/// Min is the lesser of x and y; a NaN loses to a number.
@inlinable public func Min(_ x: float32, _ y: float32) -> float32 {
    if x.isNaN { return y }
    if y.isNaN { return x }
    return y < x ? y : x
}

/// Max is the greater of x and y; a NaN loses to a number.
@inlinable public func Max(_ x: float32, _ y: float32) -> float32 {
    if x.isNaN { return y }
    if y.isNaN { return x }
    return y > x ? y : x
}

/// Rsqrt is 1 / Sqrt(x).
@inlinable public func Rsqrt(_ x: float32) -> float32 { return 1 / x.squareRoot() }

// ---- scaling by powers of two ----

/// Ldexp is x · 2^n, exactly where the result is representable.
@inlinable public func Ldexp(_ x: float32, _ n: int32) -> float32 {
    var y = x
    var e = n
    // Each step multiplies by a power of two a float32 can hold, so each
    // is exact until the result itself over- or underflows.
    while e > 127 {
        y = y * 1.7014118e38 // 2^127
        e -= 127
    }
    while e < -126 {
        y = y * 1.1754944e-38 // 2^-126
        e += 126
    }
    return y * float32(bitPattern: uint32(bitPattern: e + 127) << 23)
}

/// Frexp is x as m · 2^e with m in [0.5, 1), for a finite nonzero x; x
/// and 0 otherwise.
@inlinable public func Frexp(_ x: float32) -> (float32, int32) {
    if x == 0 || x.isNaN || x.isInfinite {
        return (x, 0)
    }
    var b = x.bitPattern
    var e = int32((b >> 23) & 0xFF)
    var bias: int32 = 126
    if e == 0 {
        // A subnormal: scale it into the normals first.
        b = (x * 16777216).bitPattern // 2^24
        e = int32((b >> 23) & 0xFF)
        bias = 150
    }
    let m = float32(bitPattern: (b & 0x807FFFFF) | 0x3F000000)
    return (m, e - bias)
}

// ---- exponentials and logarithms ----

/// Exp is e^x.
@inlinable public func Exp(_ x: float32) -> float32 {
    if x.isNaN { return x }
    if x > 88.72283 { return float32.infinity }
    if x < -103.97208 { return 0 }
    // x = n·ln2 + r, |r| <= ln2/2, with ln2 in two parts so n·ln2 is exact.
    let n = (x * 1.442695).rounded(.toNearestOrEven)
    var r = x - n * 0.693359375
    r = r - n * -2.12194440e-4
    let z = r * r
    var p: float32 = 1.9875691500e-4
    p = p * r + 1.3981999507e-3
    p = p * r + 8.3334519073e-3
    p = p * r + 4.1665795894e-2
    p = p * r + 1.6666665459e-1
    p = p * r + 5.0000001201e-1
    let y = p * z + r + 1
    return Ldexp(y, int32(n))
}

/// Exp2 is 2^x.
@inlinable public func Exp2(_ x: float32) -> float32 {
    if x.isNaN { return x }
    if x >= 128 { return float32.infinity }
    if x < -150 { return 0 }
    let n = x.rounded(.toNearestOrEven)
    let r = x - n // exact: |r| <= 0.5
    return Ldexp(Exp(r * 0.6931471805599453), int32(n))
}

/// Log is the natural logarithm: NaN below zero, -infinity at zero.
@inlinable public func Log(_ x: float32) -> float32 {
    if x.isNaN || x == float32.infinity { return x }
    if x < 0 { return float32.nan }
    if x == 0 { return -float32.infinity }
    var (m, e) = Frexp(x)
    // m in [sqrt(1/2), sqrt(2)): the polynomial's range.
    if m < 0.70710677 {
        e -= 1
        m = m + m - 1
    } else {
        m = m - 1
    }
    let z = m * m
    var p: float32 = 7.0376836292e-2
    p = p * m - 1.1514610310e-1
    p = p * m + 1.1676998740e-1
    p = p * m - 1.2420140846e-1
    p = p * m + 1.4249322787e-1
    p = p * m - 1.6668057665e-1
    p = p * m + 2.0000714765e-1
    p = p * m - 2.4999993993e-1
    p = p * m + 3.3333331174e-1
    var y = p * m * z
    let fe = float32(e)
    y = y + fe * -2.12194440e-4
    y = y - 0.5 * z
    return m + y + fe * 0.693359375
}

/// Log2 is the base-2 logarithm.
@inlinable public func Log2(_ x: float32) -> float32 { return Log(x) * 1.442695 }

/// Log10 is the base-10 logarithm.
@inlinable public func Log10(_ x: float32) -> float32 { return Log(x) * 0.4342944819 }

// ---- trigonometry ----

/// _reduceQuarterPi is x reduced by multiples of π/4 for Sin and Cos: the
/// octant j (0...7) and the remainder, |r| <= π/4 or a hair over. π/4 is
/// taken in five pieces of at most ten significant bits, so each y·piece
/// is exact for y below 2^14: |x| up to about 12,000 reduces with no
/// digits lost. Beyond that the error grows with x.
@inlinable public func _reduceQuarterPi(_ x: float32) -> (int32, float32) {
    var j = int32(x * 1.27323954473516) // 4/π
    var y = float32(j)
    if j & 1 != 0 {
        j += 1
        y += 1
    }
    var r = x - y * 0.78515625
    r = r - y * 2.4175643920898438e-4
    r = r - y * 1.5692785382270813e-7
    r = r - y * 3.035438567167148e-11
    r = r - y * 3.108624468950438e-14
    return (j & 7, r)
}

@inlinable public func _sinPoly(_ r: float32) -> float32 {
    let z = r * r
    var p: float32 = -1.9515295891e-4
    p = p * z + 8.3321608736e-3
    p = p * z - 1.6666654611e-1
    return p * z * r + r
}

@inlinable public func _cosPoly(_ r: float32) -> float32 {
    let z = r * r
    var p: float32 = 2.443315711809948e-5
    p = p * z - 1.388731625493765e-3
    p = p * z + 4.166664568298827e-2
    return p * z * z - 0.5 * z + 1
}

/// Sin is the sine of x radians.
@inlinable public func Sin(_ x: float32) -> float32 {
    if x.isNaN || x.isInfinite { return float32.nan }
    var sign: float32 = x < 0 ? -1 : 1
    var (j, r) = _reduceQuarterPi(x < 0 ? -x : x)
    if j > 3 {
        sign = -sign
        j -= 4
    }
    let y = (j == 1 || j == 2) ? _cosPoly(r) : _sinPoly(r)
    return sign * y
}

/// Cos is the cosine of x radians.
@inlinable public func Cos(_ x: float32) -> float32 {
    if x.isNaN || x.isInfinite { return float32.nan }
    var sign: float32 = 1
    var (j, r) = _reduceQuarterPi(x < 0 ? -x : x)
    if j > 3 {
        sign = -sign
        j -= 4
    }
    if j > 1 {
        sign = -sign
    }
    let y = (j == 1 || j == 2) ? _sinPoly(r) : _cosPoly(r)
    return sign * y
}

/// Tan is the tangent of x radians.
@inlinable public func Tan(_ x: float32) -> float32 { return Sin(x) / Cos(x) }

/// Atan is the arctangent of x, in (-π/2, π/2): Cephes' atanf, x reduced
/// to |x| ≤ tan(π/8) by tan(π/8) and tan(3π/8), then a degree-9 odd
/// polynomial.
@inlinable public func Atan(_ x: float32) -> float32 {
    if x.isNaN { return x }
    var a = x < 0 ? -x : x
    var base: float32 = 0
    if a > 2.414213562373095 {
        base = 1.5707963267948966
        a = -1 / a
    } else if a > 0.4142135623730950 {
        base = 0.7853981633974483
        a = (a - 1) / (a + 1)
    }
    let z = a * a
    var p: float32 = 8.05374449538e-2
    p = p * z - 1.38776856032e-1
    p = p * z + 1.99777106478e-1
    p = p * z - 3.33329491539e-1
    let r = base + (p * z * a + a)
    return x < 0 ? -r : r
}

/// Atan2 is the angle of the point (x, y) from the positive x axis, in
/// [-π, π], with C's signed zeros: Atan2(+0, -1) is π and Atan2(-0, -1)
/// is -π, the angle PyTorch's torch.angle gives a real negative number.
@inlinable public func Atan2(_ y: float32, _ x: float32) -> float32 {
    if x.isNaN || y.isNaN { return x + y }
    let yNeg = (y.bitPattern >> 31) != 0
    let xNeg = (x.bitPattern >> 31) != 0
    if y == 0 {
        if xNeg { return yNeg ? -3.1415926535897932 : 3.1415926535897932 }
        return y  // ±0
    }
    if x == 0 {
        return yNeg ? -1.5707963267948966 : 1.5707963267948966
    }
    if x.isInfinite {
        if y.isInfinite {
            let q: float32 = xNeg ? 2.356194490192345 : 0.7853981633974483
            return yNeg ? -q : q
        }
        if xNeg { return yNeg ? -3.1415926535897932 : 3.1415926535897932 }
        return yNeg ? -0.0 : 0.0
    }
    if y.isInfinite {
        return yNeg ? -1.5707963267948966 : 1.5707963267948966
    }
    let r = Atan(y / x)
    if !xNeg { return r }
    // r is in (-π/2, π/2); half of π, added twice, keeps the sum's
    // rounding to the float32 of π's.
    return yNeg ? (r - 1.5707963267948966) - 1.5707963267948966 : (r + 1.5707963267948966) + 1.5707963267948966
}

// ---- the functions activations are made of ----

/// Tanh is the hyperbolic tangent.
@inlinable public func Tanh(_ x: float32) -> float32 {
    if x.isNaN { return x }
    let a = x < 0 ? -x : x
    if a > 9 { return x < 0 ? -1 : 1 }
    if a >= 0.625 {
        let s = Exp(a + a)
        let y = 1 - 2 / (s + 1)
        return x < 0 ? -y : y
    }
    let z = x * x
    var p: float32 = -5.70498872745e-3
    p = p * z + 2.06390887954e-2
    p = p * z - 5.37397155531e-2
    p = p * z + 1.33314422036e-1
    p = p * z - 3.33332819422e-1
    return p * z * x + x
}

/// Sigmoid is 1 / (1 + e^-x), without overflow at either end.
@inlinable public func Sigmoid(_ x: float32) -> float32 {
    if x >= 0 {
        return 1 / (1 + Exp(-x))
    }
    let e = Exp(x)
    return e / (1 + e)
}

/// Erf is the error function.
@inlinable public func Erf(_ x: float32) -> float32 {
    if x.isNaN { return x }
    let a = x < 0 ? -x : x
    if a >= 1 {
        let y = 1 - _erfc(a)
        return x < 0 ? -y : y
    }
    // Cephes erff: x · T(x²) below 1.
    let z = x * x
    var p: float32 = 7.853861353153693e-5
    p = p * z - 8.010193625184903e-4
    p = p * z + 5.188327685732524e-3
    p = p * z - 2.685381193529856e-2
    p = p * z + 1.128358514861418e-1
    p = p * z - 3.761262582423300e-1
    p = p * z + 1.128379165726710
    return x * p
}

/// Erfc is 1 - Erf(x), without the cancellation that has for large x.
@inlinable public func Erfc(_ x: float32) -> float32 {
    if x.isNaN { return x }
    if x < 1 { return 1 - Erf(x) }
    return _erfc(x)
}

/// _expNegSquare is e^(-a·a) without the rounding of a·a, which would
/// cost up to ~80 ULPs near a = 9: a is split into a head of twelve bits,
/// whose square is exact, and a tail.
@inlinable public func _expNegSquare(_ a: float32) -> float32 {
    let head = float32(bitPattern: a.bitPattern & 0xFFFFF000)
    let tail = a - head
    return Exp(-head * head) * Exp(-tail * (a + head))
}

/// _erfc is erfc(a) for a >= 1: e^-a² / a · P(1/a), P fitted to the
/// function at Chebyshev nodes (relative error under 2^-26) on each of
/// [1, 2] and [2, 9.2].
@inlinable public func _erfc(_ a: float32) -> float32 {
    if a > 9.194 { return 0 }
    let q = 1 / a
    var p: float32
    if a < 2 {
        p = -0.0015913358288794476
        p = p * q - 0.008197728366837232
        p = p * q + 0.09346170841614389
        p = p * q - 0.3083449792684856
        p = p * q + 0.5263960850513171
        p = p * q - 0.4718323471954814
        p = p * q + 0.03650168204293804
        p = p * q + 0.5611904901599154
    } else {
        p = -0.24296593756811083
        p = p * q + 0.39104878277969657
        p = p * q + 0.13279876683135391
        p = p * q - 0.7713040763850387
        p = p * q + 0.6643711056169304
        p = p * q - 0.044488111303615276
        p = p * q - 0.2771839112553713
        p = p * q - 0.0002998387096990142
        p = p * q + 0.5641973572790637
    }
    return _expNegSquare(a) * q * p
}

// The rest of the elementary functions, computed in float64 and rounded
// once: as accurate as float32 allows, if not as fast as a float32
// polynomial would be.

/// x to the power y.
@inlinable public func Pow(_ x: float32, _ y: float32) -> float32 { return float32(Pow(float64(x), float64(y))) }

/// The arc sine, in radians; NaN outside [-1, 1].
@inlinable public func Asin(_ x: float32) -> float32 { return float32(Asin(float64(x))) }

/// The arc cosine, in radians; NaN outside [-1, 1].
@inlinable public func Acos(_ x: float32) -> float32 { return float32(Acos(float64(x))) }

@inlinable public func Sinh(_ x: float32) -> float32 { return float32(Sinh(float64(x))) }
@inlinable public func Cosh(_ x: float32) -> float32 { return float32(Cosh(float64(x))) }
@inlinable public func Asinh(_ x: float32) -> float32 { return float32(Asinh(float64(x))) }
@inlinable public func Acosh(_ x: float32) -> float32 { return float32(Acosh(float64(x))) }
@inlinable public func Atanh(_ x: float32) -> float32 { return float32(Atanh(float64(x))) }
