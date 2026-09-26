package main
import "math/big"

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

    // ExpMod bigger: 2^255 mod 1000. 2^255 mod 1000 = 168 (known)
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

    if failures > 0 { print("\(failures) FAILURES"); return 1 }
    print("all big tests passed")
    return 0
}
