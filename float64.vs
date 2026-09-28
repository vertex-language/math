package math

// Double-precision elementary functions: fdlibm's algorithms (Sun
// Microsystems, 1993) as FreeBSD's msun and V8's ieee754.cc keep them, so
// the same argument gives the same bits here as in a JavaScript engine,
// on every machine. Each is an argument reduced exactly or nearly so,
// then a polynomial, with the error bounds fdlibm documents (under one
// ulp).
//
// These are host functions. They read a few constant tables (the bits of
// 2/π for reducing huge arguments to the trigonometric functions), so
// unlike the float32 ones they aren't @inlinable into kernels; Metal has
// no float64 in any case.

// ---- words of a double ----

/// highWord is a double's sign, exponent and top 20 fraction bits.
func highWord(_ x: float64) -> int32 {
    return int32(truncatingIfNeeded: int64(bitPattern: x.bitPattern >> 32))
}

/// lowWord is a double's low 32 fraction bits.
func lowWord(_ x: float64) -> uint32 {
    return uint32(truncatingIfNeeded: x.bitPattern)
}

func fromWords(_ high: int32, _ low: uint32) -> float64 {
    return float64(bitPattern: (uint64(uint32(bitPattern: high)) << 32) | uint64(low))
}

func withHighWord(_ x: float64, _ high: int32) -> float64 {
    return fromWords(high, lowWord(x))
}

func withLowWord(_ x: float64, _ low: uint32) -> float64 {
    return fromWords(highWord(x), low)
}

// ---- what is one instruction ----

/// Sqrt is the square root, correctly rounded; NaN for a negative x.
public func Sqrt(_ x: float64) -> float64 { return x.squareRoot() }

/// Floor is the greatest whole number not above x.
public func Floor(_ x: float64) -> float64 { return x.rounded(.down) }

/// Ceil is the least whole number not below x.
public func Ceil(_ x: float64) -> float64 { return x.rounded(.up) }

/// Trunc is x with its fraction dropped, towards zero.
public func Trunc(_ x: float64) -> float64 { return x.rounded(.towardZero) }

/// Round is the nearest whole number, ties to even.
public func Round(_ x: float64) -> float64 { return x.rounded(.toNearestOrEven) }

/// RoundHalfAway is the nearest whole number, ties away from zero (C's round).
public func RoundHalfAway(_ x: float64) -> float64 { return x.rounded(.toNearestOrAwayFromZero) }

/// Abs is |x|.
public func Abs(_ x: float64) -> float64 { return float64(bitPattern: x.bitPattern & 0x7FFFFFFFFFFFFFFF) }

/// CopySign is |x| with y's sign.
public func CopySign(_ x: float64, _ y: float64) -> float64 {
    return float64(bitPattern: (x.bitPattern & 0x7FFFFFFFFFFFFFFF) | (y.bitPattern & 0x8000000000000000))
}

/// Min is the lesser of x and y; a NaN loses to a number.
public func Min(_ x: float64, _ y: float64) -> float64 {
    if x.isNaN { return y }
    if y.isNaN { return x }
    return y < x ? y : x
}

/// Max is the greater of x and y; a NaN loses to a number.
public func Max(_ x: float64, _ y: float64) -> float64 {
    if x.isNaN { return y }
    if y.isNaN { return x }
    return y > x ? y : x
}

/// Fmod is the remainder of x / y with x's sign, exact (C's fmod).
public func Fmod(_ x: float64, _ y: float64) -> float64 { return x.truncatingRemainder(dividingBy: y) }

/// Remainder is IEEE 754's remainder: x - n·y for the n nearest x / y.
public func Remainder(_ x: float64, _ y: float64) -> float64 { return x.remainder(dividingBy: y) }

/// Modf splits x into its whole part and its fraction, both with x's sign.
public func Modf(_ x: float64) -> (whole: float64, fraction: float64) {
    if x.isInfinite { return (x, CopySign(0, x)) }
    let w = x.rounded(.towardZero)
    return (w, CopySign(x - w, x))
}

/// NextUp is the least double above x.
public func NextUp(_ x: float64) -> float64 { return x.nextUp }

/// NextDown is the greatest double below x.
public func NextDown(_ x: float64) -> float64 { return x.nextDown }

// ---- scaling by powers of two ----

/// Ldexp is x · 2^n, correctly rounded (C's scalbn).
public func Ldexp(_ x: float64, _ n: int) -> float64 {
    let two54 = 1.80143985094819840000e+16
    let twom54 = 5.55111512312578270212e-17
    let huge = 1.0e+300
    let tiny = 1.0e-300
    var v = x
    var hx = highWord(v)
    let lx = lowWord(v)
    var k = int((hx & 0x7ff00000) >> 20)
    if k == 0 {
        if (lx | uint32(bitPattern: hx & 0x7fffffff)) == 0 { return v }
        v *= two54
        hx = highWord(v)
        k = int((hx & 0x7ff00000) >> 20) - 54
        if n < -50000 { return tiny * v }
    }
    if k == 0x7ff { return v + v }
    k = k + n
    if k > 0x7fe { return huge * CopySign(huge, v) }
    if k > 0 {
        return withHighWord(v, (hx & int32(bitPattern: 0x800fffff)) | int32(k << 20))
    }
    if k <= -54 {
        if n > 50000 { return huge * CopySign(huge, v) }
        return tiny * CopySign(tiny, v)
    }
    k += 54
    v = withHighWord(v, (hx & int32(bitPattern: 0x800fffff)) | int32(k << 20))
    return v * twom54
}

/// Frexp splits x into a fraction in [0.5, 1) and a power of two: x = f · 2^e.
public func Frexp(_ x: float64) -> (fraction: float64, exponent: int) {
    if x == 0 || x.isNaN || x.isInfinite { return (x, 0) }
    var v = x
    var e = 0
    var hx = highWord(v)
    var ix = hx & 0x7fffffff
    if ix < 0x00100000 {
        v *= 1.80143985094819840000e+16
        hx = highWord(v)
        ix = hx & 0x7fffffff
        e = -54
    }
    e += int(ix >> 20) - 1022
    hx = (hx & int32(bitPattern: 0x800fffff)) | 0x3fe00000
    return (withHighWord(v, hx), e)
}

// ---- trigonometric argument reduction ----

// The bits of 2/π, 24 at a time, for reducing huge arguments.
let twoOverPi: [int32] = [
    0xA2F983, 0x6E4E44, 0x1529FC, 0x2757D1, 0xF534DD, 0xC0DB62,
    0x95993C, 0x439041, 0xFE5163, 0xABDEBB, 0xC561B7, 0x246E3A,
    0x424DD2, 0xE00649, 0x2EEA09, 0xD1921C, 0xFE1DEB, 0x1CB129,
    0xA73EE8, 0x8235F5, 0x2EBB44, 0x84E99C, 0x7026B4, 0x5F7E41,
    0x3991D6, 0x398353, 0x39F49C, 0x845F8B, 0xBDF928, 0x3B1FF8,
    0x97FFDE, 0x05980F, 0xEF2F11, 0x8B5A0A, 0x6D1F6D, 0x367ECF,
    0x27CB09, 0xB74F46, 0x3F669E, 0x5FEA2D, 0x7527BA, 0xC7EBE5,
    0xF17B3D, 0x0739F7, 0x8A5292, 0xEA6BFB, 0x5FB11F, 0x8D5D08,
    0x560330, 0x46FC7B, 0x6BABF0, 0xCFBC20, 0x9AF436, 0x1DA9E3,
    0x91615E, 0xE61B08, 0x659985, 0x5F14A0, 0x68408D, 0xFFD880,
    0x4D7327, 0x310606, 0x1556CA, 0x73A8C9, 0x60E27B, 0xC08C6B,
]

// The high words of n·π/2 for n = 1...32.
let npio2HighWords: [int32] = [
    0x3FF921FB, 0x400921FB, 0x4012D97C, 0x401921FB, 0x401F6A7A, 0x4022D97C,
    0x4025FDBB, 0x402921FB, 0x402C463A, 0x402F6A7A, 0x4031475C, 0x4032D97C,
    0x40346B9C, 0x4035FDBB, 0x40378FDB, 0x403921FB, 0x403AB41B, 0x403C463A,
    0x403DD85A, 0x403F6A7A, 0x40407E4C, 0x4041475C, 0x4042106C, 0x4042D97C,
    0x4043A28C, 0x40446B9C, 0x404534AC, 0x4045FDBB, 0x4046C6CB, 0x40478FDB,
    0x404858EB, 0x404921FB,
]

// π/2 in eight pieces of 24 bits.
let pio2Pieces: [float64] = [
    1.57079625129699707031e+00,
    7.54978941586159635335e-08,
    5.39030252995776476554e-15,
    3.28200341580791294123e-22,
    1.27065575308067607349e-29,
    1.22933308981111328932e-36,
    2.73370053816464559624e-44,
    2.16741683877804819444e-51,
]

/// remPio2Large is __kernel_rem_pio2 at double-double precision (prec 2):
/// x is the argument as nx 24-bit pieces scaled by 2^-e0; it returns
/// n mod 8 and y0 + y1 = x - n·π/2.
func remPio2Large(_ x: [float64], _ e0: int, _ nx: int) -> (n: int, y0: float64, y1: float64) {
    let two24 = 1.67772160000000000000e+07
    let twon24 = 5.96046447753906250000e-08
    let jk = 4
    let jp = jk
    let jx = nx - 1
    var jv = (e0 - 3) / 24
    if jv < 0 { jv = 0 }
    var q0 = e0 - 24 * (jv + 1)
    var f = [float64](repeating: 0, count: 20)
    var q = [float64](repeating: 0, count: 20)
    var fq = [float64](repeating: 0, count: 20)
    var iq = [int32](repeating: 0, count: 20)

    var j = jv - jx
    let m = jx + jk
    var i = 0
    while i <= m {
        f[i] = j < 0 ? 0 : float64(twoOverPi[j])
        i += 1
        j += 1
    }
    i = 0
    while i <= jk {
        var fw = 0.0
        j = 0
        while j <= jx {
            fw += x[j] * f[jx + i - j]
            j += 1
        }
        q[i] = fw
        i += 1
    }
    var jz = jk
    var n = 0
    var ih: int32 = 0
    var z = 0.0
    while true {
        // Distill q[] into iq[], reversed.
        i = 0
        j = jz
        z = q[jz]
        while j > 0 {
            let fw = float64(int32(twon24 * z))
            iq[i] = int32(z - two24 * fw)
            z = q[j - 1] + fw
            i += 1
            j -= 1
        }
        z = Ldexp(z, q0)
        z -= 8.0 * (z * 0.125).rounded(.down)
        n = int(int32(z))
        z -= float64(n)
        ih = 0
        if q0 > 0 {
            let k = iq[jz - 1] >> int32(24 - q0)
            n += int(k)
            iq[jz - 1] -= k << int32(24 - q0)
            ih = iq[jz - 1] >> int32(23 - q0)
        } else if q0 == 0 {
            ih = iq[jz - 1] >> 23
        } else if z >= 0.5 {
            ih = 2
        }
        if ih > 0 {
            n += 1
            var carry = 0
            i = 0
            while i < jz {
                let v = iq[i]
                if carry == 0 {
                    if v != 0 {
                        carry = 1
                        iq[i] = 0x1000000 - v
                    }
                } else {
                    iq[i] = 0xffffff - v
                }
                i += 1
            }
            if q0 > 0 {
                if q0 == 1 { iq[jz - 1] &= 0x7fffff } else if q0 == 2 { iq[jz - 1] &= 0x3fffff }
            }
            if ih == 2 {
                z = 1.0 - z
                if carry != 0 { z -= Ldexp(1.0, q0) }
            }
        }
        // Recompute with more terms if the result cancelled to zero.
        if z == 0 {
            var acc: int32 = 0
            i = jz - 1
            while i >= jk {
                acc |= iq[i]
                i -= 1
            }
            if acc == 0 {
                var k = 1
                while jk >= k && iq[jk - k] == 0 { k += 1 }
                i = jz + 1
                while i <= jz + k {
                    f[jx + i] = float64(twoOverPi[jv + i])
                    var fw = 0.0
                    j = 0
                    while j <= jx {
                        fw += x[j] * f[jx + i - j]
                        j += 1
                    }
                    q[i] = fw
                    i += 1
                }
                jz += k
                continue
            }
        }
        break
    }
    // Chop off zero terms.
    if z == 0 {
        jz -= 1
        q0 -= 24
        while iq[jz] == 0 {
            jz -= 1
            q0 -= 24
        }
    } else {
        z = Ldexp(z, -q0)
        if z >= two24 {
            let fw = float64(int32(twon24 * z))
            iq[jz] = int32(z - two24 * fw)
            jz += 1
            q0 += 24
            iq[jz] = int32(fw)
        } else {
            iq[jz] = int32(z)
        }
    }
    // Convert the chunks to doubles.
    var fw = Ldexp(1.0, q0)
    i = jz
    while i >= 0 {
        q[i] = fw * float64(iq[i])
        fw *= twon24
        i -= 1
    }
    // fq = π/2 · q.
    i = jz
    while i >= 0 {
        var acc = 0.0
        var k = 0
        while k <= jp && k <= jz - i {
            acc += pio2Pieces[k] * q[i + k]
            k += 1
        }
        fq[jz - i] = acc
        i -= 1
    }
    var s = 0.0
    i = jz
    while i >= 0 {
        s += fq[i]
        i -= 1
    }
    let y0 = ih == 0 ? s : -s
    s = fq[0] - s
    i = 1
    while i <= jz {
        s += fq[i]
        i += 1
    }
    let y1 = ih == 0 ? s : -s
    return (n & 7, y0, y1)
}

/// remPio2 is __ieee754_rem_pio2: n and y0 + y1 = x - n·π/2, |y| ≤ π/4.
func remPio2(_ x: float64) -> (n: int, y0: float64, y1: float64) {
    let invpio2 = 6.36619772367581382433e-01
    let pio2_1 = 1.57079632673412561417e+00
    let pio2_1t = 6.07710050650619224932e-11
    let pio2_2 = 6.07710050630396597660e-11
    let pio2_2t = 2.02226624879595063154e-21
    let pio2_3 = 2.02226624871116645580e-21
    let pio2_3t = 8.47842766036889956997e-32
    let hx = highWord(x)
    let ix = hx & 0x7fffffff
    if ix <= 0x3fe921fb { return (0, x, 0) }
    if ix < 0x4002d97c {
        // |x| < 3π/4: n = ±1.
        if hx > 0 {
            var z = x - pio2_1
            if ix != 0x3ff921fb {
                let y0 = z - pio2_1t
                return (1, y0, (z - y0) - pio2_1t)
            }
            z -= pio2_2
            let y0 = z - pio2_2t
            return (1, y0, (z - y0) - pio2_2t)
        }
        var z = x + pio2_1
        if ix != 0x3ff921fb {
            let y0 = z + pio2_1t
            return (-1, y0, (z - y0) + pio2_1t)
        }
        z += pio2_2
        let y0 = z + pio2_2t
        return (-1, y0, (z - y0) + pio2_2t)
    }
    if ix <= 0x413921fb {
        // |x| ≤ 2^19·π/2: medium size.
        var t = Abs(x)
        let n = int(int32(t * invpio2 + 0.5))
        let fn = float64(n)
        var r = t - fn * pio2_1
        var w = fn * pio2_1t
        var y0: float64
        if n < 32 && ix != npio2HighWords[n - 1] {
            y0 = r - w
        } else {
            let j = int(ix >> 20)
            y0 = r - w
            var i = j - int((highWord(y0) >> 20) & 0x7ff)
            if i > 16 {
                t = r
                w = fn * pio2_2
                r = t - w
                w = fn * pio2_2t - ((t - r) - w)
                y0 = r - w
                i = j - int((highWord(y0) >> 20) & 0x7ff)
                if i > 49 {
                    t = r
                    w = fn * pio2_3
                    r = t - w
                    w = fn * pio2_3t - ((t - r) - w)
                    y0 = r - w
                }
            }
        }
        let y1 = (r - y0) - w
        if hx < 0 { return (-n, -y0, -y1) }
        return (n, y0, y1)
    }
    if ix >= 0x7ff00000 {
        let nan = x - x
        return (0, nan, nan)
    }
    // Large: split |x| into three 24-bit pieces.
    let e0 = int(ix >> 20) - 1046
    var z = fromWords(ix - int32(e0 << 20), lowWord(x))
    var tx = [float64](repeating: 0, count: 3)
    var i = 0
    while i < 2 {
        tx[i] = float64(int32(z))
        z = (z - tx[i]) * 1.67772160000000000000e+07
        i += 1
    }
    tx[2] = z
    var nx = 3
    while tx[nx - 1] == 0 { nx -= 1 }
    let (n, y0, y1) = remPio2Large(tx, e0, nx)
    if hx < 0 { return (-n, -y0, -y1) }
    return (n, y0, y1)
}

// ---- trigonometric kernels on [-π/4, π/4] ----

func kernelSin(_ x: float64, _ y: float64, _ iy: int) -> float64 {
    let S1 = -1.66666666666666324348e-01
    let S2 = 8.33333333332248946124e-03
    let S3 = -1.98412698298579493134e-04
    let S4 = 2.75573137070700676789e-06
    let S5 = -2.50507602534068634195e-08
    let S6 = 1.58969099521155010221e-10
    let ix = highWord(x) & 0x7fffffff
    if ix < 0x3e400000 {
        if int32(x) == 0 { return x }
    }
    let z = x * x
    let v = z * x
    let r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)))
    if iy == 0 { return x + v * (S1 + z * r) }
    return x - ((z * (0.5 * y - v * r) - y) - v * S1)
}

func kernelCos(_ x: float64, _ y: float64) -> float64 {
    let C1 = 4.16666666666666019037e-02
    let C2 = -1.38888888888741095749e-03
    let C3 = 2.48015872894767294178e-05
    let C4 = -2.75573143513906633035e-07
    let C5 = 2.08757232129817482790e-09
    let C6 = -1.13596475577881948265e-11
    let ix = highWord(x) & 0x7fffffff
    if ix < 0x3e400000 {
        if int32(x) == 0 { return 1.0 }
    }
    let z = x * x
    let r = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))))
    if ix < 0x3FD33333 {
        return 1.0 - (0.5 * z - (z * r - x * y))
    }
    var qx: float64
    if ix > 0x3fe90000 {
        qx = 0.28125
    } else {
        qx = fromWords(ix - 0x00200000, 0)
    }
    let hz = 0.5 * z - qx
    let a = 1.0 - qx
    return a - (hz - (z * r - x * y))
}

func kernelTan(_ xIn: float64, _ yIn: float64, _ iy: int) -> float64 {
    let T0 = 3.33333333333334091986e-01
    let T1 = 1.33333333333201242699e-01
    let T2 = 5.39682539762260521377e-02
    let T3 = 2.18694882948595424599e-02
    let T4 = 8.86323982359930005737e-03
    let T5 = 3.59207910759131235356e-03
    let T6 = 1.45620945432529025516e-03
    let T7 = 5.88041240820264096874e-04
    let T8 = 2.46463134818469906812e-04
    let T9 = 7.81794442939557092300e-05
    let T10 = 7.14072491382608190305e-05
    let T11 = -1.85586374855275456654e-05
    let T12 = 2.59073051863633712884e-05
    let pio4 = 7.85398163397448278999e-01
    let pio4lo = 3.06161699786838301793e-17
    var x = xIn
    var y = yIn
    let hx = highWord(x)
    let ix = hx & 0x7fffffff
    if ix < 0x3e300000 {
        if int32(x) == 0 {
            if (uint32(bitPattern: ix) | lowWord(x) | uint32(bitPattern: int32(iy + 1))) == 0 {
                return 1.0 / Abs(x)
            }
            if iy == 1 { return x }
            // -1 / (x + y), carefully.
            let w = x + y
            let z = withLowWord(w, 0)
            let v = y - (z - x)
            let a = -1.0 / w
            let t = withLowWord(a, 0)
            let s = 1.0 + t * z
            return t + a * (s + t * v)
        }
    }
    if ix >= 0x3FE59428 {
        if hx < 0 {
            x = -x
            y = -y
        }
        let z = pio4 - x
        let w = pio4lo - y
        x = z + w
        y = 0.0
    }
    var z = x * x
    var w = z * z
    var r = T1 + w * (T3 + w * (T5 + w * (T7 + w * (T9 + w * T11))))
    var v = z * (T2 + w * (T4 + w * (T6 + w * (T8 + w * (T10 + w * T12)))))
    var s = z * x
    r = y + z * (s * (r + v) + y)
    r += T0 * s
    w = x + r
    if ix >= 0x3FE59428 {
        v = float64(iy)
        return float64(1 - ((hx >> 30) & 2)) * (v - 2.0 * (x - (w * w / (w + v) - r)))
    }
    if iy == 1 { return w }
    z = withLowWord(w, 0)
    v = r - (z - x)
    let a = -1.0 / w
    let t = withLowWord(a, 0)
    s = 1.0 + t * z
    return t + a * (s + t * v)
}

// ---- trigonometric functions ----

/// Sin is the sine of x (in radians).
public func Sin(_ x: float64) -> float64 {
    let ix = highWord(x) & 0x7fffffff
    if ix <= 0x3fe921fb { return kernelSin(x, 0, 0) }
    if ix >= 0x7ff00000 { return x - x }
    let (n, y0, y1) = remPio2(x)
    switch n & 3 {
    case 0: return kernelSin(y0, y1, 1)
    case 1: return kernelCos(y0, y1)
    case 2: return -kernelSin(y0, y1, 1)
    default: return -kernelCos(y0, y1)
    }
}

/// Cos is the cosine of x (in radians).
public func Cos(_ x: float64) -> float64 {
    let ix = highWord(x) & 0x7fffffff
    if ix <= 0x3fe921fb { return kernelCos(x, 0) }
    if ix >= 0x7ff00000 { return x - x }
    let (n, y0, y1) = remPio2(x)
    switch n & 3 {
    case 0: return kernelCos(y0, y1)
    case 1: return -kernelSin(y0, y1, 1)
    case 2: return -kernelCos(y0, y1)
    default: return kernelSin(y0, y1, 1)
    }
}

/// Tan is the tangent of x (in radians).
public func Tan(_ x: float64) -> float64 {
    let ix = highWord(x) & 0x7fffffff
    if ix <= 0x3fe921fb { return kernelTan(x, 0, 1) }
    if ix >= 0x7ff00000 { return x - x }
    let (n, y0, y1) = remPio2(x)
    return kernelTan(y0, y1, 1 - ((n & 1) << 1))
}

// ---- inverse trigonometric functions ----

// Coefficients shared by Asin and Acos: R(x²) = p(x²) / q(x²).
func asinR(_ t: float64) -> float64 {
    let pS0 = 1.66666666666666657415e-01
    let pS1 = -3.25565818622400915405e-01
    let pS2 = 2.01212532134862925881e-01
    let pS3 = -4.00555345006794114027e-02
    let pS4 = 7.91534994289814532176e-04
    let pS5 = 3.47933107596021167570e-05
    let qS1 = -2.40339491173441421878e+00
    let qS2 = 2.02094576023350569471e+00
    let qS3 = -6.88283971605453293030e-01
    let qS4 = 7.70381505559019352791e-02
    let p = t * (pS0 + t * (pS1 + t * (pS2 + t * (pS3 + t * (pS4 + t * pS5)))))
    let q = 1.0 + t * (qS1 + t * (qS2 + t * (qS3 + t * qS4)))
    return p / q
}

/// Asin is the arcsine of x, in [-π/2, π/2]; NaN outside [-1, 1].
public func Asin(_ x: float64) -> float64 {
    let pio2_hi = 1.57079632679489655800e+00
    let pio2_lo = 6.12323399573676603587e-17
    let pio4_hi = 7.85398163397448278999e-01
    let hx = highWord(x)
    let ix = hx & 0x7fffffff
    if ix >= 0x3ff00000 {
        if ((uint32(bitPattern: ix - 0x3ff00000)) | lowWord(x)) == 0 {
            return x * pio2_hi + x * pio2_lo
        }
        return (x - x) / (x - x)
    }
    if ix < 0x3fe00000 {
        if ix < 0x3e500000 {
            if 1.0e300 + x > 1.0 { return x }
        }
        return x + x * asinR(x * x)
    }
    let w = 1.0 - Abs(x)
    let t = w * 0.5
    let s = t.squareRoot()
    var result: float64
    if ix >= 0x3FEF3333 {
        result = pio2_hi - (2.0 * (s + s * asinR(t)) - pio2_lo)
    } else {
        let sw = withLowWord(s, 0)
        let c = (t - sw * sw) / (s + sw)
        let p = 2.0 * s * asinR(t) - (pio2_lo - 2.0 * c)
        let q = pio4_hi - 2.0 * sw
        result = pio4_hi - (p - q)
    }
    return hx > 0 ? result : -result
}

/// Acos is the arccosine of x, in [0, π]; NaN outside [-1, 1].
public func Acos(_ x: float64) -> float64 {
    let pi = 3.14159265358979311600e+00
    let pio2_hi = 1.57079632679489655800e+00
    let pio2_lo = 6.12323399573676603587e-17
    let hx = highWord(x)
    let ix = hx & 0x7fffffff
    if ix >= 0x3ff00000 {
        if ((uint32(bitPattern: ix - 0x3ff00000)) | lowWord(x)) == 0 {
            if hx > 0 { return 0.0 }
            return pi + 2.0 * pio2_lo
        }
        return (x - x) / (x - x)
    }
    if ix < 0x3fe00000 {
        if ix <= 0x3c600000 { return pio2_hi + pio2_lo }
        let z = x * x
        return pio2_hi - (x - (pio2_lo - x * asinR(z)))
    }
    if hx < 0 {
        let z = (1.0 + x) * 0.5
        let s = z.squareRoot()
        let w = asinR(z) * s - pio2_lo
        return pi - 2.0 * (s + w)
    }
    let z = (1.0 - x) * 0.5
    let s = z.squareRoot()
    let df = withLowWord(s, 0)
    let c = (z - df * df) / (s + df)
    let w = asinR(z) * s + c
    return 2.0 * (df + w)
}

/// Atan is the arctangent of x, in (-π/2, π/2).
public func Atan(_ xIn: float64) -> float64 {
    let atanhi: [float64] = [4.63647609000806093515e-01, 7.85398163397448278999e-01, 9.82793723247329054082e-01, 1.57079632679489655800e+00]
    let atanlo: [float64] = [2.26987774529616870924e-17, 3.06161699786838301793e-17, 1.39033110312309984516e-17, 6.12323399573676603587e-17]
    let aT0 = 3.33333333333329318027e-01
    let aT1 = -1.99999999998764832476e-01
    let aT2 = 1.42857142725034663711e-01
    let aT3 = -1.11111104054623557880e-01
    let aT4 = 9.09088713343650656196e-02
    let aT5 = -7.69187620504482999495e-02
    let aT6 = 6.66107313738753120669e-02
    let aT7 = -5.83357013379057348645e-02
    let aT8 = 4.97687799461593236017e-02
    let aT9 = -3.65315727442169155270e-02
    let aT10 = 1.62858201153657823623e-02
    var x = xIn
    let hx = highWord(x)
    let ix = hx & 0x7fffffff
    var id = -1
    if ix >= 0x44100000 {
        if ix > 0x7ff00000 || (ix == 0x7ff00000 && lowWord(x) != 0) { return x + x }
        if hx > 0 { return atanhi[3] + atanlo[3] }
        return -atanhi[3] - atanlo[3]
    }
    if ix < 0x3fdc0000 {
        if ix < 0x3e400000 {
            if 1.0e300 + x > 1.0 { return x }
        }
    } else {
        x = Abs(x)
        if ix < 0x3ff30000 {
            if ix < 0x3fe60000 {
                id = 0
                x = (2.0 * x - 1.0) / (2.0 + x)
            } else {
                id = 1
                x = (x - 1.0) / (x + 1.0)
            }
        } else if ix < 0x40038000 {
            id = 2
            x = (x - 1.5) / (1.0 + 1.5 * x)
        } else {
            id = 3
            x = -1.0 / x
        }
    }
    let z = x * x
    let w = z * z
    let s1 = z * (aT0 + w * (aT2 + w * (aT4 + w * (aT6 + w * (aT8 + w * aT10)))))
    let s2 = w * (aT1 + w * (aT3 + w * (aT5 + w * (aT7 + w * aT9))))
    if id < 0 { return x - x * (s1 + s2) }
    let r = atanhi[id] - ((x * (s1 + s2) - atanlo[id]) - x)
    return hx < 0 ? -r : r
}

/// Atan2 is the angle of the point (x, y) from the positive x axis, in
/// [-π, π], with C's signed zeros and infinities.
public func Atan2(_ y: float64, _ x: float64) -> float64 {
    let tiny = 1.0e-300
    let pi_o_4 = 7.8539816339744827900e-01
    let pi_o_2 = 1.5707963267948965580e+00
    let pi = 3.1415926535897931160e+00
    let pi_lo = 1.2246467991473531772e-16
    let hx = highWord(x)
    let lx = lowWord(x)
    let ix = hx & 0x7fffffff
    let hy = highWord(y)
    let ly = lowWord(y)
    let iy = hy & 0x7fffffff
    if x.isNaN || y.isNaN { return x + y }
    if ((uint32(bitPattern: hx &- 0x3ff00000)) | lx) == 0 { return Atan(y) }
    var m = int(((hy >> 31) & 1) | ((hx >> 30) & 2))
    if (uint32(bitPattern: iy) | ly) == 0 {
        switch m {
        case 0, 1: return y
        case 2: return pi + tiny
        default: return -pi - tiny
        }
    }
    if (uint32(bitPattern: ix) | lx) == 0 {
        return hy < 0 ? -pi_o_2 - tiny : pi_o_2 + tiny
    }
    if ix == 0x7ff00000 {
        if iy == 0x7ff00000 {
            switch m {
            case 0: return pi_o_4 + tiny
            case 1: return -pi_o_4 - tiny
            case 2: return 3.0 * pi_o_4 + tiny
            default: return -3.0 * pi_o_4 - tiny
            }
        }
        switch m {
        case 0: return 0.0
        case 1: return -0.0
        case 2: return pi + tiny
        default: return -pi - tiny
        }
    }
    if iy == 0x7ff00000 {
        return hy < 0 ? -pi_o_2 - tiny : pi_o_2 + tiny
    }
    let k = int((iy - ix) >> 20)
    var z: float64
    if k > 60 {
        z = pi_o_2 + 0.5 * pi_lo
        m &= 1
    } else if hx < 0 && k < -60 {
        z = 0.0
    } else {
        z = Atan(Abs(y / x))
    }
    switch m {
    case 0: return z
    case 1: return -z
    case 2: return pi - (z - pi_lo)
    default: return (z - pi_lo) - pi
    }
}

// ---- exponentials and logarithms ----

/// Exp is e^x.
public func Exp(_ xIn: float64) -> float64 {
    let o_threshold = 7.09782712893383973096e+02
    let u_threshold = -7.45133219101941108420e+02
    let invln2 = 1.44269504088896338700e+00
    let ln2HI = 6.93147180369123816490e-01
    let ln2LO = 1.90821492927058770002e-10
    let P1 = 1.66666666666666019037e-01
    let P2 = -2.77777777770155933842e-03
    let P3 = 6.61375632143793436117e-05
    let P4 = -1.65339022054652515390e-06
    let P5 = 4.13813679705723846039e-08
    let E = 2.718281828459045
    let twom1000 = 9.33263618503218878990e-302
    var x = xIn
    var hi = 0.0
    var lo = 0.0
    var k = 0
    var hx = highWord(x)
    let xsb = int((hx >> 31) & 1)
    hx &= 0x7fffffff
    if hx >= 0x40862E42 {
        if hx >= 0x7ff00000 {
            if (uint32(bitPattern: hx & 0xfffff) | lowWord(x)) != 0 { return x + x }
            return xsb == 0 ? x : 0.0
        }
        if x > o_threshold { return float64.infinity }
        if x < u_threshold { return twom1000 * twom1000 }
    }
    if hx > 0x3fd62e42 {
        if hx < 0x3FF0A2B2 {
            // exp(1) is special-cased to be exactly e, as V8 does.
            if x == 1.0 { return E }
            hi = xsb == 0 ? x - ln2HI : x + ln2HI
            lo = xsb == 0 ? ln2LO : -ln2LO
            k = 1 - xsb - xsb
        } else {
            k = int(int32(invln2 * x + (xsb == 0 ? 0.5 : -0.5)))
            let t = float64(k)
            hi = x - t * ln2HI
            lo = t * ln2LO
        }
        x = hi - lo
    } else if hx < 0x3e300000 {
        if 1.0e300 + x > 1.0 { return 1.0 + x }
    } else {
        k = 0
    }
    let t = x * x
    var twopk: float64
    if k >= -1021 {
        twopk = fromWords(int32(0x3ff00000 + (k << 20)), 0)
    } else {
        twopk = fromWords(int32(0x3ff00000 + ((k + 1000) << 20)), 0)
    }
    let c = x - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))))
    if k == 0 {
        return 1.0 - ((x * c) / (c - 2.0) - x)
    }
    let y = 1.0 - ((lo - (x * c) / (2.0 - c)) - hi)
    if k >= -1021 {
        if k == 1024 { return y * 2.0 * 8.98846567431157953865e+307 }
        return y * twopk
    }
    return y * twopk * twom1000
}

/// Expm1 is e^x - 1, accurate near zero.
public func Expm1(_ xIn: float64) -> float64 {
    let o_threshold = 7.09782712893383973096e+02
    let ln2_hi = 6.93147180369123816490e-01
    let ln2_lo = 1.90821492927058770002e-10
    let invln2 = 1.44269504088896338700e+00
    let Q1 = -3.33333333333331316428e-02
    let Q2 = 1.58730158725481460165e-03
    let Q3 = -7.93650757867487942473e-05
    let Q4 = 4.00821782732936239552e-06
    let Q5 = -2.01099218183624371326e-07
    let tiny = 1.0e-300
    let huge = 1.0e+300
    var x = xIn
    var hx = highWord(x)
    let xsb = hx & int32(bitPattern: 0x80000000)
    hx &= 0x7fffffff
    var hi = 0.0
    var lo = 0.0
    var c = 0.0
    var k = 0
    if hx >= 0x4043687A {
        if hx >= 0x40862E42 {
            if hx >= 0x7ff00000 {
                if (uint32(bitPattern: hx & 0xfffff) | lowWord(x)) != 0 { return x + x }
                return xsb == 0 ? x : -1.0
            }
            if x > o_threshold { return float64.infinity }
        }
        if xsb != 0 {
            if x + tiny < 0.0 { return tiny - 1.0 }
        }
    }
    if hx > 0x3fd62e42 {
        if hx < 0x3FF0A2B2 {
            if xsb == 0 {
                hi = x - ln2_hi
                lo = ln2_lo
                k = 1
            } else {
                hi = x + ln2_hi
                lo = -ln2_lo
                k = -1
            }
        } else {
            k = int(int32(invln2 * x + (xsb == 0 ? 0.5 : -0.5)))
            let t = float64(k)
            hi = x - t * ln2_hi
            lo = t * ln2_lo
        }
        x = hi - lo
        c = (hi - x) - lo
    } else if hx < 0x3c900000 {
        let t = huge + x
        return x - (t - (huge + x))
    } else {
        k = 0
    }
    let hfx = 0.5 * x
    let hxs = x * hfx
    let r1 = 1.0 + hxs * (Q1 + hxs * (Q2 + hxs * (Q3 + hxs * (Q4 + hxs * Q5))))
    var t = 3.0 - r1 * hfx
    var e = hxs * ((r1 - t) / (6.0 - x * t))
    if k == 0 { return x - (x * e - hxs) }
    let twopk = fromWords(int32(0x3ff00000 + (k << 20)), 0)
    e = x * (e - c) - c
    e -= hxs
    if k == -1 { return 0.5 * (x - e) - 0.5 }
    if k == 1 {
        if x < -0.25 { return -2.0 * (e - (x + 0.5)) }
        return 1.0 + 2.0 * (x - e)
    }
    var y: float64
    if k <= -2 || k > 56 {
        y = 1.0 - (e - x)
        if k == 1024 {
            y = y * 2.0 * 8.98846567431157953865e+307
        } else {
            y = y * twopk
        }
        return y - 1.0
    }
    if k < 20 {
        t = fromWords(int32(0x3ff00000 - (0x200000 >> k)), 0)
        y = t - (e - x)
        y = y * twopk
    } else {
        t = fromWords(int32((0x3ff - k) << 20), 0)
        y = x - (e + t)
        y += 1.0
        y = y * twopk
    }
    return y
}

let Lg1 = 6.666666666666735130e-01
let Lg2 = 3.999999999940941908e-01
let Lg3 = 2.857142874366239149e-01
let Lg4 = 2.222219843214978396e-01
let Lg5 = 1.818357216161805012e-01
let Lg6 = 1.531383769920937332e-01
let Lg7 = 1.479819860511658591e-01

/// Log is the natural logarithm; -∞ at zero, NaN below it.
public func Log(_ xIn: float64) -> float64 {
    let ln2_hi = 6.93147180369123816490e-01
    let ln2_lo = 1.90821492927058770002e-10
    let two54 = 1.80143985094819840000e+16
    var x = xIn
    var hx = highWord(x)
    let lx = lowWord(x)
    var k = 0
    if hx < 0x00100000 {
        if (uint32(bitPattern: hx & 0x7fffffff) | lx) == 0 { return -float64.infinity }
        if hx < 0 { return float64.nan }
        k -= 54
        x *= two54
        hx = highWord(x)
    }
    if hx >= 0x7ff00000 { return x + x }
    k += int(hx >> 20) - 1023
    hx &= 0x000fffff
    var i = (hx &+ 0x95f64) & 0x100000
    x = withHighWord(x, hx | (i ^ 0x3ff00000))
    k += int(i >> 20)
    let f = x - 1.0
    if (0x000fffff & (2 &+ hx)) < 3 {
        if f == 0 {
            if k == 0 { return 0 }
            let dk = float64(k)
            return dk * ln2_hi + dk * ln2_lo
        }
        let R = f * f * (0.5 - 0.33333333333333333 * f)
        if k == 0 { return f - R }
        let dk = float64(k)
        return dk * ln2_hi - ((R - dk * ln2_lo) - f)
    }
    let s = f / (2.0 + f)
    let dk = float64(k)
    let z = s * s
    i = hx &- 0x6147a
    let w = z * z
    let j = 0x6b851 &- hx
    let t1 = w * (Lg2 + w * (Lg4 + w * Lg6))
    let t2 = z * (Lg1 + w * (Lg3 + w * (Lg5 + w * Lg7)))
    i |= j
    let R = t2 + t1
    if i > 0 {
        let hfsq = 0.5 * f * f
        if k == 0 { return f - (hfsq - s * (hfsq + R)) }
        return dk * ln2_hi - ((hfsq - (s * (hfsq + R) + dk * ln2_lo)) - f)
    }
    if k == 0 { return f - s * (f - R) }
    return dk * ln2_hi - ((s * (f - R) - dk * ln2_lo) - f)
}

/// Log1p is ln(1 + x), accurate near zero.
public func Log1p(_ x: float64) -> float64 {
    let ln2_hi = 6.93147180369123816490e-01
    let ln2_lo = 1.90821492927058770002e-10
    let two54 = 1.80143985094819840000e+16
    let hx = highWord(x)
    let ax = hx & 0x7fffffff
    var k = 1
    var f = 0.0
    var hu: int32 = 0
    var c = 0.0
    if hx < 0x3FDA827A {
        if ax >= 0x3ff00000 {
            if x == -1.0 { return -float64.infinity }
            return float64.nan
        }
        if ax < 0x3e200000 {
            if two54 + x > 0 && ax < 0x3c900000 { return x }
            return x - x * x * 0.5
        }
        if hx > 0 || hx <= int32(bitPattern: 0xbfd2bec4) {
            k = 0
            f = x
            hu = 1
        }
    }
    if hx >= 0x7ff00000 { return x + x }
    if k != 0 {
        var u: float64
        if hx < 0x43400000 {
            u = 1.0 + x
            hu = highWord(u)
            k = int(hu >> 20) - 1023
            c = k > 0 ? 1.0 - (u - x) : x - (u - 1.0)
            c /= u
        } else {
            u = x
            hu = highWord(u)
            k = int(hu >> 20) - 1023
            c = 0
        }
        hu &= 0x000fffff
        if hu < 0x6a09e {
            u = withHighWord(u, hu | 0x3ff00000)
        } else {
            k += 1
            u = withHighWord(u, hu | 0x3fe00000)
            hu = (0x00100000 - hu) >> 2
        }
        f = u - 1.0
    }
    let hfsq = 0.5 * f * f
    let dk = float64(k)
    if hu == 0 {
        if f == 0 {
            if k == 0 { return 0 }
            c += dk * ln2_lo
            return dk * ln2_hi + c
        }
        let R = hfsq * (1.0 - 0.66666666666666666 * f)
        if k == 0 { return f - R }
        return dk * ln2_hi - ((R - (dk * ln2_lo + c)) - f)
    }
    let s = f / (2.0 + f)
    let z = s * s
    let R = z * (Lg1 + z * (Lg2 + z * (Lg3 + z * (Lg4 + z * (Lg5 + z * (Lg6 + z * Lg7))))))
    if k == 0 { return f - (hfsq - s * (hfsq + R)) }
    return dk * ln2_hi - ((hfsq - (s * (hfsq + R) + (dk * ln2_lo + c))) - f)
}

/// kLog1p is FreeBSD's k_log1p: log(1 + f) - f + f²/2, for Log2 and Log10.
func kLog1p(_ f: float64) -> float64 {
    let s = f / (2.0 + f)
    let z = s * s
    let w = z * z
    let t1 = w * (Lg2 + w * (Lg4 + w * Lg6))
    let t2 = z * (Lg1 + w * (Lg3 + w * (Lg5 + w * Lg7)))
    let R = t2 + t1
    let hfsq = 0.5 * f * f
    return s * (hfsq + R)
}

/// Log2 is the base-2 logarithm; exact at powers of two.
public func Log2(_ xIn: float64) -> float64 {
    let two54 = 1.80143985094819840000e+16
    let ivln2hi = 1.44269504072144627571e+00
    let ivln2lo = 1.67517131648865118353e-10
    var x = xIn
    var hx = highWord(x)
    let lx = lowWord(x)
    var k = 0
    if hx < 0x00100000 {
        if (uint32(bitPattern: hx & 0x7fffffff) | lx) == 0 { return -float64.infinity }
        if hx < 0 { return float64.nan }
        k -= 54
        x *= two54
        hx = highWord(x)
    }
    if hx >= 0x7ff00000 { return x + x }
    if hx == 0x3ff00000 && lx == 0 { return 0 }
    k += int(hx >> 20) - 1023
    hx &= 0x000fffff
    let i = (hx &+ 0x95f64) & 0x100000
    x = withHighWord(x, hx | (i ^ 0x3ff00000))
    k += int(i >> 20)
    let y = float64(k)
    let f = x - 1.0
    let hfsq = 0.5 * f * f
    let r = kLog1p(f)
    let hi = withLowWord(f - hfsq, 0)
    let lo = (f - hi) - hfsq + r
    var valHi = hi * ivln2hi
    var valLo = (lo + hi) * ivln2lo + lo * ivln2hi
    let w = y + valHi
    valLo += (y - w) + valHi
    valHi = w
    return valLo + valHi
}

/// Log10 is the base-10 logarithm.
public func Log10(_ xIn: float64) -> float64 {
    let two54 = 1.80143985094819840000e+16
    let ivln10 = 4.34294481903251816668e-01
    let log10_2hi = 3.01029995663611771306e-01
    let log10_2lo = 3.69423907715893078616e-13
    var x = xIn
    var hx = highWord(x)
    var lx = lowWord(x)
    var k = 0
    if hx < 0x00100000 {
        if (uint32(bitPattern: hx & 0x7fffffff) | lx) == 0 { return -float64.infinity }
        if hx < 0 { return float64.nan }
        k -= 54
        x *= two54
        hx = highWord(x)
        lx = lowWord(x)
    }
    if hx >= 0x7ff00000 { return x + x }
    k += int(hx >> 20) - 1023
    let i = k < 0 ? 1 : 0
    hx = (hx & 0x000fffff) | int32((0x3ff - i) << 20)
    let y = float64(k + i)
    x = fromWords(hx, lx)
    let z = y * log10_2lo + ivln10 * Log(x)
    return z + y * log10_2hi
}

/// Pow is x^y, with C99's special cases (pow(1, y) and pow(x, 0) are 1,
/// even for a NaN).
public func Pow(_ x: float64, _ y: float64) -> float64 {
    let bp: [float64] = [1.0, 1.5]
    let dp_h: [float64] = [0.0, 5.84962487220764160156e-01]
    let dp_l: [float64] = [0.0, 1.35003920212974897128e-08]
    let two53 = 9007199254740992.0
    let huge = 1.0e300
    let tiny = 1.0e-300
    let L1 = 5.99999999999994648725e-01
    let L2 = 4.28571428578550184252e-01
    let L3 = 3.33333329818377432918e-01
    let L4 = 2.72728123808534006489e-01
    let L5 = 2.30660745775561754067e-01
    let L6 = 2.06975017800338417784e-01
    let P1 = 1.66666666666666019037e-01
    let P2 = -2.77777777770155933842e-03
    let P3 = 6.61375632143793436117e-05
    let P4 = -1.65339022054652515390e-06
    let P5 = 4.13813679705723846039e-08
    let lg2 = 6.93147180559945286227e-01
    let lg2_h = 6.93147182464599609375e-01
    let lg2_l = -1.90465429995776804525e-09
    let ovt = 8.0085662595372944372e-17
    let cp = 9.61796693925975554329e-01
    let cp_h = 9.61796700954437255859e-01
    let cp_l = -7.02846165095275826516e-09
    let ivln2 = 1.44269504088896338700e+00
    let ivln2_h = 1.44269502162933349609e+00
    let ivln2_l = 1.92596299112661746887e-08

    let hx = highWord(x)
    let lx = lowWord(x)
    let hy = highWord(y)
    let ly = lowWord(y)
    var ix = hx & 0x7fffffff
    let iy = hy & 0x7fffffff

    if (uint32(bitPattern: iy) | ly) == 0 { return 1.0 }
    if x == 1.0 { return 1.0 }
    if ix > 0x7ff00000 || (ix == 0x7ff00000 && lx != 0) || iy > 0x7ff00000 || (iy == 0x7ff00000 && ly != 0) {
        return x + y
    }
    // yisint: 0 not an integer, 1 odd, 2 even.
    var yisint = 0
    if hx < 0 {
        if iy >= 0x43400000 {
            yisint = 2
        } else if iy >= 0x3ff00000 {
            let k = int(iy >> 20) - 0x3ff
            if k > 20 {
                let j = ly >> uint32(52 - k)
                if (j << uint32(52 - k)) == ly { yisint = 2 - int(j & 1) }
            } else if ly == 0 {
                let j = iy >> int32(20 - k)
                if (j << int32(20 - k)) == iy { yisint = 2 - int(j & 1) }
            }
        }
    }
    if ly == 0 {
        if iy == 0x7ff00000 {
            if ((uint32(bitPattern: ix &- 0x3ff00000)) | lx) == 0 {
                return 1.0
            }
            if ix >= 0x3ff00000 { return hy >= 0 ? y : 0.0 }
            return hy < 0 ? -y : 0.0
        }
        if iy == 0x3ff00000 {
            if hy < 0 { return 1.0 / x }
            return x
        }
        if hy == 0x40000000 { return x * x }
        if hy == 0x3fe00000 {
            if hx >= 0 { return x.squareRoot() }
        }
    }
    var ax = Abs(x)
    if lx == 0 {
        if ix == 0x7ff00000 || ix == 0 || ix == 0x3ff00000 {
            var z = ax
            if hy < 0 { z = 1.0 / z }
            if hx < 0 {
                if ((int(ix) - 0x3ff00000) | yisint) == 0 {
                    z = float64.nan
                } else if yisint == 1 {
                    z = -z
                }
            }
            return z
        }
    }
    var n = int((hx >> 31) + 1)
    if (n | yisint) == 0 { return float64.nan }
    var s = 1.0
    if (n | (yisint - 1)) == 0 { s = -1.0 }

    var t1: float64
    var t2: float64
    if iy > 0x41e00000 {
        if iy > 0x43f00000 {
            if ix <= 0x3fefffff { return hy < 0 ? huge * huge : tiny * tiny }
            if ix >= 0x3ff00000 { return hy > 0 ? huge * huge : tiny * tiny }
        }
        if ix < 0x3fefffff { return hy < 0 ? s * huge * huge : s * tiny * tiny }
        if ix > 0x3ff00000 { return hy > 0 ? s * huge * huge : s * tiny * tiny }
        let t = ax - 1.0
        let w = (t * t) * (0.5 - t * (0.3333333333333333333333 - t * 0.25))
        let u = ivln2_h * t
        let v = t * ivln2_l - w * ivln2
        t1 = withLowWord(u + v, 0)
        t2 = v - (t1 - u)
    } else {
        n = 0
        if ix < 0x00100000 {
            ax *= two53
            n -= 53
            ix = highWord(ax)
        }
        n += int(ix >> 20) - 0x3ff
        let j = ix & 0x000fffff
        ix = j | 0x3ff00000
        var k = 0
        if j <= 0x3988E {
            k = 0
        } else if j < 0xBB67A {
            k = 1
        } else {
            k = 0
            n += 1
            ix -= 0x00100000
        }
        ax = withHighWord(ax, ix)
        let u = ax - bp[k]
        let v = 1.0 / (ax + bp[k])
        let ss = u * v
        let s_h = withLowWord(ss, 0)
        var t_h = fromWords(((ix >> 1) | 0x20000000) + 0x00080000 + int32(k << 18), 0)
        var t_l = ax - (t_h - bp[k])
        let s_l = v * ((u - s_h * t_h) - s_h * t_l)
        var s2 = ss * ss
        var r = s2 * s2 * (L1 + s2 * (L2 + s2 * (L3 + s2 * (L4 + s2 * (L5 + s2 * L6)))))
        r += s_l * (s_h + ss)
        s2 = s_h * s_h
        t_h = withLowWord(3.0 + s2 + r, 0)
        t_l = r - ((t_h - 3.0) - s2)
        let uu = s_h * t_h
        let vv = s_l * t_h + t_l * ss
        let p_h = withLowWord(uu + vv, 0)
        let p_l = vv - (p_h - uu)
        let z_h = cp_h * p_h
        let z_l = cp_l * p_h + p_l * cp + dp_l[k]
        let t = float64(n)
        t1 = withLowWord(((z_h + z_l) + dp_h[k]) + t, 0)
        t2 = z_l - (((t1 - t) - dp_h[k]) - z_h)
    }
    // (y1 + y2) · (t1 + t2)
    let y1 = withLowWord(y, 0)
    let p_l = (y - y1) * t1 + y * t2
    var p_h = y1 * t1
    var z = p_l + p_h
    var j = highWord(z)
    var i = lowWord(z)
    if j >= 0x40900000 {
        if ((uint32(bitPattern: j &- 0x40900000)) | i) != 0 { return s * huge * huge }
        if p_l + ovt > z - p_h { return s * huge * huge }
    } else if (j & 0x7fffffff) >= 0x4090cc00 {
        if ((uint32(bitPattern: j) &- 0xc090cc00) | i) != 0 { return s * tiny * tiny }
        if p_l <= z - p_h { return s * tiny * tiny }
    }
    // 2^(p_h + p_l)
    let ii = j & 0x7fffffff
    var k = int(ii >> 20) - 0x3ff
    n = 0
    if ii > 0x3fe00000 {
        n = int(j &+ (0x00100000 >> int32(k + 1)))
        k = int((int32(truncatingIfNeeded: n) & 0x7fffffff) >> 20) - 0x3ff
        let t = fromWords(int32(truncatingIfNeeded: n) & ~(0x000fffff >> int32(k)), 0)
        n = int(((int32(truncatingIfNeeded: n) & 0x000fffff) | 0x00100000) >> int32(20 - k))
        if j < 0 { n = -n }
        p_h -= t
    }
    let t = withLowWord(p_l + p_h, 0)
    let u = t * lg2_h
    let v = (p_l - (t - p_h)) * lg2 + t * lg2_l
    z = u + v
    let w = v - (z - u)
    let tt = z * z
    let tt1 = z - tt * (P1 + tt * (P2 + tt * (P3 + tt * (P4 + tt * P5))))
    let r = (z * tt1) / ((tt1 - 2.0) - (w + z * w))
    z = 1.0 - (r - z)
    j = highWord(z)
    j = j &+ int32(truncatingIfNeeded: n << 20)
    if (j >> 20) <= 0 {
        z = Ldexp(z, n)
    } else {
        z = withHighWord(z, highWord(z) &+ int32(truncatingIfNeeded: n << 20))
    }
    i = 0
    return s * z
}

/// Cbrt is the cube root.
public func Cbrt(_ x: float64) -> float64 {
    let B1: uint32 = 715094163
    let B2: uint32 = 696219795
    let P0 = 1.87595182427177009643
    let P1 = -1.88497979543377169875
    let P2 = 1.621429720105354466140
    let P3 = -0.758397934778766047437
    let P4 = 0.145996192886612446982
    var hx = uint32(bitPattern: highWord(x))
    let low = lowWord(x)
    let sign = hx & 0x80000000
    hx ^= sign
    if hx >= 0x7ff00000 { return x + x }
    var t: float64
    if hx < 0x00100000 {
        if (hx | low) == 0 { return x }
        t = fromWords(0x43500000, 0)
        t *= x
        let high = uint32(bitPattern: highWord(t))
        t = fromWords(int32(bitPattern: sign | ((high & 0x7fffffff) / 3 + B2)), 0)
    } else {
        t = fromWords(int32(bitPattern: sign | (hx / 3 + B1)), 0)
    }
    var r = (t * t) * (t / x)
    t = t * ((P0 + r * (P1 + r * P2)) + ((r * r) * r) * (P3 + r * P4))
    t = float64(bitPattern: (t.bitPattern &+ 0x80000000) & 0xffffffffc0000000)
    let s = t * t
    r = x / s
    let w = t + t
    r = (r - t) / (w + r)
    return t + t * r
}

/// Hypot is √(x² + y²) without undue overflow or underflow.
public func Hypot(_ x: float64, _ y: float64) -> float64 {
    var ha = highWord(x) & 0x7fffffff
    var hb = highWord(y) & 0x7fffffff
    var a = x
    var b = y
    if hb > ha {
        a = y
        b = x
        let j = ha
        ha = hb
        hb = j
    }
    a = withHighWord(a, ha)
    b = withHighWord(b, hb)
    if (ha - hb) > 0x3c00000 { return a + b }
    var k = 0
    if ha > 0x5f300000 {
        if ha >= 0x7ff00000 {
            var w = a + b
            if (uint32(bitPattern: ha & 0xfffff) | lowWord(a)) == 0 { w = a }
            if (uint32(bitPattern: hb ^ 0x7ff00000) | lowWord(b)) == 0 { w = b }
            return w
        }
        ha -= 0x25800000
        hb -= 0x25800000
        k += 600
        a = withHighWord(a, ha)
        b = withHighWord(b, hb)
    }
    if hb < 0x20b00000 {
        if hb <= 0x000fffff {
            if (uint32(bitPattern: hb) | lowWord(b)) == 0 { return a }
            let t1 = fromWords(0x7fd00000, 0)
            b *= t1
            a *= t1
            k -= 1022
        } else {
            ha += 0x25800000
            hb += 0x25800000
            k -= 600
            a = withHighWord(a, ha)
            b = withHighWord(b, hb)
        }
    }
    var w = a - b
    if w > b {
        let t1 = fromWords(ha, 0)
        let t2 = a - t1
        w = (t1 * t1 - (b * (-b) - t2 * (a + t1))).squareRoot()
    } else {
        a = a + a
        let y1 = fromWords(hb, 0)
        let y2 = b - y1
        let t1 = fromWords(ha + 0x00100000, 0)
        let t2 = a - t1
        w = (t1 * y1 - (w * (-w) - (t1 * y2 + t2 * b))).squareRoot()
    }
    if k != 0 {
        let t1 = fromWords(0x3ff00000 + int32(k << 20), 0)
        return t1 * w
    }
    return w
}

// ---- hyperbolic functions ----

/// Sinh is the hyperbolic sine.
public func Sinh(_ x: float64) -> float64 {
    let KSINH_OVERFLOW = 710.4758600739439
    let TWO_M28 = 3.725290298461914e-9
    let LOG_MAXD = 709.7822265625
    let shuge = 1.0e307
    let h = x < 0 ? -0.5 : 0.5
    let ax = Abs(x)
    if ax < 22 {
        if ax < TWO_M28 { return x }
        let t = Expm1(ax)
        if ax < 1 { return h * (2.0 * t - t * t / (t + 1.0)) }
        return h * (t + t / (t + 1.0))
    }
    if ax < LOG_MAXD { return h * Exp(ax) }
    if ax <= KSINH_OVERFLOW {
        let w = Exp(0.5 * ax)
        let t = h * w
        return t * w
    }
    return x * shuge
}

/// Cosh is the hyperbolic cosine.
public func Cosh(_ x: float64) -> float64 {
    let KCOSH_OVERFLOW = 710.4758600739439
    let ix = highWord(x) & 0x7fffffff
    if ix < 0x3fd62e43 {
        let t = Expm1(Abs(x))
        let w = 1.0 + t
        if ix < 0x3c800000 { return w }
        return 1.0 + (t * t) / (w + w)
    }
    if ix < 0x40360000 {
        let t = Exp(Abs(x))
        return 0.5 * t + 0.5 / t
    }
    if ix < 0x40862e42 { return 0.5 * Exp(Abs(x)) }
    if Abs(x) <= KCOSH_OVERFLOW {
        let w = Exp(0.5 * Abs(x))
        let t = 0.5 * w
        return t * w
    }
    if ix >= 0x7ff00000 { return x * x }
    return float64.infinity
}

/// Tanh is the hyperbolic tangent.
public func Tanh(_ x: float64) -> float64 {
    let jx = highWord(x)
    let ix = jx & 0x7fffffff
    if ix >= 0x7ff00000 {
        if jx >= 0 { return 1.0 / x + 1.0 }
        return 1.0 / x - 1.0
    }
    var z: float64
    if ix < 0x40360000 {
        if ix < 0x3e300000 {
            if 1.0e300 + x > 1.0 { return x }
        }
        if ix >= 0x3ff00000 {
            let t = Expm1(2.0 * Abs(x))
            z = 1.0 - 2.0 / (t + 2.0)
        } else {
            let t = Expm1(-2.0 * Abs(x))
            z = -t / (t + 2.0)
        }
    } else {
        z = 1.0 - 1.0e-300
    }
    return jx >= 0 ? z : -z
}

/// Asinh is the inverse hyperbolic sine.
public func Asinh(_ x: float64) -> float64 {
    let ln2 = 6.93147180559945286227e-01
    let hx = highWord(x)
    let ix = hx & 0x7fffffff
    if ix >= 0x7ff00000 { return x + x }
    if ix < 0x3e300000 {
        if 1.0e300 + x > 1.0 { return x }
    }
    var w: float64
    if ix > 0x41b00000 {
        w = Log(Abs(x)) + ln2
    } else if ix > 0x40000000 {
        let t = Abs(x)
        w = Log(2.0 * t + 1.0 / ((x * x + 1.0).squareRoot() + t))
    } else {
        let t = x * x
        w = Log1p(Abs(x) + t / (1.0 + (1.0 + t).squareRoot()))
    }
    return hx > 0 ? w : -w
}

/// Acosh is the inverse hyperbolic cosine; NaN below 1.
public func Acosh(_ x: float64) -> float64 {
    let ln2 = 6.93147180559945286227e-01
    let hx = highWord(x)
    let lx = lowWord(x)
    if hx < 0x3ff00000 { return (x - x) / (x - x) }
    if hx >= 0x41b00000 {
        if hx >= 0x7ff00000 { return x + x }
        return Log(x) + ln2
    }
    if ((uint32(bitPattern: hx &- 0x3ff00000)) | lx) == 0 { return 0.0 }
    if hx > 0x40000000 {
        let t = x * x
        return Log(2.0 * x - 1.0 / (x + (t - 1.0).squareRoot()))
    }
    let t = x - 1.0
    return Log1p(t + (2.0 * t + t * t).squareRoot())
}

/// Atanh is the inverse hyperbolic tangent; ±∞ at ±1, NaN beyond.
public func Atanh(_ xIn: float64) -> float64 {
    var x = xIn
    let hx = highWord(x)
    let lx = lowWord(x)
    let ix = hx & 0x7fffffff
    let lowBit: uint32 = lx != 0 ? 1 : 0
    if (uint32(bitPattern: ix) | lowBit) > 0x3ff00000 { return (x - x) / (x - x) }
    if ix == 0x3ff00000 { return x > 0 ? float64.infinity : -float64.infinity }
    if ix < 0x3e300000 && (1.0e300 + x) > 0 { return x }
    x = withHighWord(x, ix)
    var t: float64
    if ix < 0x3fe00000 {
        t = x + x
        t = 0.5 * Log1p(t + t * x / (1.0 - x))
    } else {
        t = 0.5 * Log1p((x + x) / (1.0 - x))
    }
    return hx >= 0 ? t : -t
}

/// Exp2 is 2^x.
public func Exp2(_ x: float64) -> float64 { return Pow(2.0, x) }

// ---- constants ----

public let Pi: float64 = 3.141592653589793
public let E: float64 = 2.718281828459045
public let Ln2: float64 = 0.6931471805599453
public let Ln10: float64 = 2.302585092994046
public let Log2E: float64 = 1.4426950408889634
public let Log10E: float64 = 0.4342944819032518
public let Sqrt2: float64 = 1.4142135623730951
public let SqrtHalf: float64 = 0.7071067811865476
