// math against the host's double-precision libm, in ULPs of the float32
// result, over a sweep of each function's domain. A kernel test compares
// the same functions on each device with the host, bit for bit.
import "math"

@_silgen_name("exp") func cExp(_ x: float64) -> float64
@_silgen_name("exp2") func cExp2(_ x: float64) -> float64
@_silgen_name("log") func cLog(_ x: float64) -> float64
@_silgen_name("log2") func cLog2(_ x: float64) -> float64
@_silgen_name("log10") func cLog10(_ x: float64) -> float64
@_silgen_name("sin") func cSin(_ x: float64) -> float64
@_silgen_name("cos") func cCos(_ x: float64) -> float64
@_silgen_name("tan") func cTan(_ x: float64) -> float64
@_silgen_name("tanh") func cTanh(_ x: float64) -> float64
@_silgen_name("erf") func cErf(_ x: float64) -> float64
@_silgen_name("erfc") func cErfc(_ x: float64) -> float64

// ulps is how far got is from the correctly rounded float32 of want, in
// units in its last place (the float32 spacing at want).
func ulps(_ got: float32, _ want: float64) -> float64 {
    if want.isNaN { return got.isNaN ? 0 : 1e9 }
    if want.isInfinite || got.isInfinite { return float64(got) == want ? 0 : 1e9 }
    let w = float32(want)
    if w.isInfinite { return got.isInfinite ? 0 : 1e9 }
    var spacing = float64(w.ulp)
    if spacing == 0 { spacing = float64(float32.leastNonzeroMagnitude) }
    return (float64(got) - want).magnitude / spacing
}

var failures = 0
var seed: uint64 = 12345

func next() -> float64 {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return float64(seed >> 11) / 9007199254740992.0
}

func check(_ name: string, _ lo: float64, _ hi: float64, _ limit: float64, _ f: (float32) -> float32, _ g: (float64) -> float64) {
    var worst: float64 = 0
    var at: float32 = 0
    for i in 0..<200000 {
        let x = float32(lo + (hi - lo) * (i < 1000 ? float64(i) / 1000 : next()))
        let e = ulps(f(x), g(float64(x)))
        if e > worst {
            worst = e
            at = x
        }
    }
    let ok = worst <= limit
    if !ok { failures += 1 }
    print("\(ok ? "ok  " : "FAIL") \(name): worst \(worst) ULPs at \(at) (limit \(limit))")
}

check("Exp", -103, 88.7, 2, { math.Exp($0) }, { cExp($0) })
check("Exp small", -1, 1, 1, { math.Exp($0) }, { cExp($0) })
check("Exp2", -149, 127.9, 2, { math.Exp2($0) }, { cExp2($0) })
check("Log", 1e-38, 3e38, 2, { math.Log($0) }, { cLog($0) })
check("Log near 1", 0.5, 2, 2, { math.Log($0) }, { cLog($0) })
check("Log2", 1e-30, 1e30, 3, { math.Log2($0) }, { cLog2($0) })
check("Log10", 1e-30, 1e30, 3, { math.Log10($0) }, { cLog10($0) })
check("Sin", -12000, 12000, 3, { math.Sin($0) }, { cSin($0) })
check("Sin small", -3.2, 3.2, 2, { math.Sin($0) }, { cSin($0) })
check("Cos", -12000, 12000, 3, { math.Cos($0) }, { cCos($0) })
check("Tan", -1.5, 1.5, 4, { math.Tan($0) }, { cTan($0) })
check("Tanh", -10, 10, 3, { math.Tanh($0) }, { cTanh($0) })
check("Erf", -5, 5, 4, { math.Erf($0) }, { cErf($0) })
check("Erfc", 1, 9, 8, { math.Erfc($0) }, { cErfc($0) })
check("Sigmoid", -80, 80, 4, { math.Sigmoid($0) }, { 1 / (1 + cExp(-$0)) })

// Special values.
func expect(_ name: string, _ got: float32, _ want: float32) {
    if !(got == want || (got.isNaN && want.isNaN)) {
        failures += 1
        print("FAIL \(name): \(got), want \(want)")
    }
}
expect("Exp(-inf)", math.Exp(-float32.infinity), 0)
expect("Exp(inf)", math.Exp(float32.infinity), float32.infinity)
expect("Exp(nan)", math.Exp(float32.nan), float32.nan)
expect("Log(0)", math.Log(0), -float32.infinity)
expect("Log(-1)", math.Log(-1), float32.nan)
expect("Log(inf)", math.Log(float32.infinity), float32.infinity)
expect("Log(subnormal)", math.Log(1e-45), float32(cLog(float64(float32(1e-45)))))
expect("Sin(0)", math.Sin(0), 0)
expect("Tanh(inf)", math.Tanh(float32.infinity), 1)
expect("Ldexp", math.Ldexp(1.5, -140), float32(bitPattern: 0x300))
expect("Ldexp big", math.Ldexp(1, 200), float32.infinity)
expect("Frexp", math.Frexp(12).0, 0.75)

print(failures == 0 ? "all within limits" : "\(failures) failures")
if failures > 0 { fatalError("math is out of its limits") }
