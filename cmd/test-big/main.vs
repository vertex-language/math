package main

import (
    "fs"
    "math/big"
)

var failures = 0
func check(_ ok: bool, _ msg: string) {
    if ok { print("ok    \(msg)") } else { print("FAIL  \(msg)"); failures += 1 }
}
func eq(_ a: [uint8], _ b: [uint8]) -> bool {
    if a.count != b.count { return false }
    var i = 0
    while i < a.count { if a[i] != b[i] { return false }; i += 1 }
    return true
}

/// readInteger reads a signed hex integer as gen_big.mjs writes it.
func readInteger(_ s: Substring) -> big.Integer {
    var t = string(s)
    var neg = false
    if t.hasPrefix("-") {
        neg = true
        t = string(t.dropFirst())
    }
    return big.Integer(negative: neg, magnitude: big.Nat.Parse(t, radix: 16)!)
}

func smallInt(_ s: Substring) -> int {
    return int(readInteger(s).ToInt64()!)
}

func hexOf(_ v: big.Integer) -> string { return v.ToString(16) }

/// replay checks every operation node's BigInt recorded in testdata/big.txt
/// (testdata/gen_big.mjs).
func replay() {
    guard let text = try? fs.ReadText(fs.Path("testdata/big.txt")) else {
        check(false, "read testdata/big.txt (run from the repository's root)")
        return
    }
    var total: [string: int] = [:]
    var bad: [string: int] = [:]
    var order: [string] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
        let f = line.split(separator: " ")
        let op = string(f[0])
        let a = readInteger(f[1])
        let want = string(f[3])
        var got = ""
        switch op {
        case "add": got = hexOf(big.Add(a, readInteger(f[2])))
        case "sub": got = hexOf(big.Sub(a, readInteger(f[2])))
        case "mul": got = hexOf(big.Mul(a, readInteger(f[2])))
        case "quo": got = hexOf(big.Quo(a, readInteger(f[2])))
        case "rem": got = hexOf(big.Rem(a, readInteger(f[2])))
        case "and": got = hexOf(big.And(a, readInteger(f[2])))
        case "or": got = hexOf(big.Or(a, readInteger(f[2])))
        case "xor": got = hexOf(big.Xor(a, readInteger(f[2])))
        case "shl": got = hexOf(big.ShiftLeft(a, smallInt(f[2])))
        case "shr": got = hexOf(big.ShiftRight(a, smallInt(f[2])))
        case "uint": got = hexOf(big.TruncateUnsigned(a, smallInt(f[2])))
        case "int": got = hexOf(big.TruncateSigned(a, smallInt(f[2])))
        case "pow": got = hexOf(big.Pow(a, smallInt(f[2])))
        case "str": got = a.ToString(smallInt(f[2]))
        case "float": got = big.Nat.FromU64(a.ToFloat64().bitPattern).ToString(16)
        default: got = "?"
        }
        if total[op] == nil { order.append(op) }
        total[op] = (total[op] ?? 0) + 1
        if got != want {
            if (bad[op] ?? 0) < 2 { print("  \(line): got \(got)") }
            bad[op] = (bad[op] ?? 0) + 1
        }
    }
    for op in order {
        let b = bad[op] ?? 0
        check(b == 0, "Integer \(op): \(total[op]!) cases as node's BigInt" + (b > 0 ? ", \(b) differ" : ""))
    }
}

func main() -> int32 {
    print("=== math/big ===")
    let a = big.Nat.FromU32(0x1234)
    let b = big.Nat.FromU32(0x1000)
    check(big.Cmp(big.Add(a, b), big.Nat.FromU32(0x2234)) == 0, "add")
    check(big.Cmp(big.Sub(a, b), big.Nat.FromU32(0x0234)) == 0, "sub")
    check(big.Cmp(big.Mul(a, b), big.Nat.FromU32(0x1234000)) == 0, "mul")

    // bytes round-trip
    let big1: [uint8] = [0x01, 0x00, 0x00, 0x00, 0x00]   // 2^32
    let n = big.Nat.FromBytes(big1)
    check(eq(n.ToBytes(), big1), "bytes round-trip 2^32")
    check(n.BitLen == 33, "bitlen 2^32")

    // DivMod: 100 / 7 = 14 r 2
    let (q, r) = big.DivMod(big.Nat.FromU32(100), big.Nat.FromU32(7))
    check(big.Cmp(q, big.Nat.FromU32(14)) == 0 && big.Cmp(r, big.Nat.FromU32(2)) == 0, "divmod 100/7")

    // ExpMod: 3^7 mod 100 = 2187 mod 100 = 87
    let e = big.ExpMod(big.Nat.FromU32(3), big.Nat.FromU32(7), big.Nat.FromU32(100))
    check(big.Cmp(e, big.Nat.FromU32(87)) == 0, "expmod 3^7 mod 100")

    // ExpMod bigger: 2^255 mod 1000 = 968
    let e2 = big.ExpMod(big.Nat.FromU32(2), big.Nat.FromU32(255), big.Nat.FromU32(1000))
    check(big.Cmp(e2, big.Nat.FromU32(968)) == 0, "expmod 2^255 mod 1000")

    // RSA-ish sanity: (m^e)^d == m mod n for tiny key.
    // n=3233 (61*53), e=17, d=413, m=65 -> c=2790, back to 65.
    let n2 = big.Nat.FromU32(3233)
    let m = big.Nat.FromU32(65)
    let c = big.ExpMod(m, big.Nat.FromU32(17), n2)
    check(big.Cmp(c, big.Nat.FromU32(2790)) == 0, "rsa encrypt tiny")
    let back = big.ExpMod(c, big.Nat.FromU32(413), n2)
    check(big.Cmp(back, m) == 0, "rsa decrypt tiny")

    check(eq(big.Nat.FromU32(0x1234).ToBytesPadded(4), [0,0,0x12,0x34]), "padded")

    // Text and conversions.
    let ten30 = big.Nat.Parse("1000000000000000000000000000000")!
    check(ten30.ToString() == "1000000000000000000000000000000" && ten30.ToString(16) == "c9f2c9cd04674edea40000000", "Parse and ToString, decimal and hex")
    check(big.Nat.Parse("12z") == nil && big.Nat.Parse("") == nil, "Parse rejects a non-digit and an empty string")
    check(ten30.ToFloat64() == 1e30 && big.Nat.FromFloat64(1e30).ToString() == "1000000000000000019884624838656", "ToFloat64 and FromFloat64")
    check(big.Integer(-5).ToString() == "-5" && big.Integer.Parse("-ff", radix: 16)!.ToInt64() == -255, "Integer text")
    check(big.Integer(int64.min).ToInt64() == int64.min && big.Integer.Parse("9223372036854775808")!.ToInt64() == nil, "ToInt64 at the edges")

    replay()

    if failures > 0 { print("\(failures) FAILURES"); return 1 }
    print("all big tests passed")
    return 0
}
