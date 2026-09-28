// Checks the float64 functions against V8's, whose results
// testdata/gen_float64.mjs recorded from node in float64.txt.
//
// V8's Math functions are fdlibm's, as these are. On x86-64 the two agree
// bit for bit. The recording is from an arm64 build, which clang compiles
// with fused multiply-adds (-ffp-contract=on): that moves about one result
// in a few hundred by one ulp. Pow there is the platform's libm pow. So
// every result must be within one ulp of V8's, and nearly all identical.
//
//     vsc run test-float64
package main

import (
    "fs"
    "math"
)

func hexBits(_ s: Substring) -> uint64 {
    var v: uint64 = 0
    for c in string(s).utf8 {
        var d: uint64 = 0
        if c >= 48 && c <= 57 { d = uint64(c - 48) } else { d = uint64(c - 87) }
        v = v << 4 | d
    }
    return v
}

func same(_ a: float64, _ b: float64) -> bool {
    if a.isNaN && b.isNaN { return true }
    return a.bitPattern == b.bitPattern
}

/// ulps is how many doubles apart a and b are (both finite, same sign).
func ulps(_ a: float64, _ b: float64) -> uint64 {
    if a.isNaN || b.isNaN || a.isInfinite || b.isInfinite { return 1 << 40 }
    if (a < 0) != (b < 0) && a != 0 && b != 0 { return 1 << 40 }
    let x = a.magnitude.bitPattern
    let y = b.magnitude.bitPattern
    return x > y ? x - y : y - x
}

func main() -> int32 {
    var text = ""
    do {
        text = try fs.ReadText(fs.Path("testdata/float64.txt"))
    } catch {
        print("cannot read testdata/float64.txt: run from the repository's root")
        return 2
    }
    var total: [string: int] = [:]
    var bad: [string: int] = [:]
    var shown: [string: int] = [:]
    var far: [string: int] = [:]
    var order: [string] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
        if line.hasPrefix("#") { continue }
        let f = line.split(separator: " ")
        let name = string(f[0])
        let x = float64(bitPattern: hexBits(f[1]))
        var want: float64
        var got: float64
        if f.count == 4 {
            let y = float64(bitPattern: hexBits(f[2]))
            want = float64(bitPattern: hexBits(f[3]))
            got = name == "Pow" ? math.Pow(x, y) : math.Atan2(x, y)
        } else {
            want = float64(bitPattern: hexBits(f[2]))
            switch name {
            case "Sin": got = math.Sin(x)
            case "Cos": got = math.Cos(x)
            case "Tan": got = math.Tan(x)
            case "Asin": got = math.Asin(x)
            case "Acos": got = math.Acos(x)
            case "Atan": got = math.Atan(x)
            case "Exp": got = math.Exp(x)
            case "Expm1": got = math.Expm1(x)
            case "Log": got = math.Log(x)
            case "Log1p": got = math.Log1p(x)
            case "Log2": got = math.Log2(x)
            case "Log10": got = math.Log10(x)
            case "Cbrt": got = math.Cbrt(x)
            case "Sinh": got = math.Sinh(x)
            case "Cosh": got = math.Cosh(x)
            case "Tanh": got = math.Tanh(x)
            case "Asinh": got = math.Asinh(x)
            case "Acosh": got = math.Acosh(x)
            case "Atanh": got = math.Atanh(x)
            default: got = float64.nan
            }
        }
        if total[name] == nil { order.append(name) }
        total[name] = (total[name] ?? 0) + 1
        if !same(got, want) {
            bad[name] = (bad[name] ?? 0) + 1
            if ulps(got, want) > 1 {
                far[name] = (far[name] ?? 0) + 1
                if (shown[name] ?? 0) < 5 {
                    shown[name] = (shown[name] ?? 0) + 1
                    print("  \(line): got \(got), want \(want)")
                }
            }
        }
    }
    var failures = 0
    for name in order {
        let b = bad[name] ?? 0
        let n = total[name]!
        let limit = name == "Pow" ? n / 10 : n / 50
        if (far[name] ?? 0) > 0 {
            print("FAIL  \(name): \(far[name]!) of \(n) more than one ulp from V8")
            failures += 1
        } else if b > limit {
            print("FAIL  \(name): \(b) of \(n) one ulp from V8, more than fused multiply-adds explain")
            failures += 1
        } else if b == 0 {
            print("ok    \(name): \(n) arguments, every bit as V8")
        } else {
            print("ok    \(name): \(n) arguments, \(n - b) identical, \(b) one ulp apart")
        }
    }
    if failures > 0 {
        print("\(failures) functions differ")
        return 1
    }
    print("all passed")
    return 0
}
