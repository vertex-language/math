// Package big is arbitrary-precision unsigned integer arithmetic, enough
// for public-key cryptography: comparison, add/sub/mul, division with
// remainder, and modular exponentiation. RSA signature verification
// (m = s^e mod n) is the immediate consumer.
//
// A Nat is a magnitude held as little-endian 32-bit limbs (limb 0 is the
// least significant), with no trailing zero limbs except for the value
// zero, which is the empty limb list. It is unsigned; callers that need a
// sign track it themselves.
package big

/// Nat is a non-negative arbitrary-precision integer.
public struct Nat {
    // Little-endian limbs; normalized (no leading zero limbs).
    var limbs: [uint32]

    init(limbs: [uint32]) {
        self.limbs = limbs
        self.normalize()
    }

    public init() {
        self.limbs = []
    }

    /// FromBytes reads a big-endian magnitude (as RSA moduli, DER INTEGERs).
    public static func FromBytes(_ be: [uint8]) -> Nat {
        var limbs: [uint32] = []
        // Walk from the least significant byte, packing 4 per limb.
        var i = be.count - 1
        var shift: uint32 = 0
        var cur: uint32 = 0
        while i >= 0 {
            cur |= uint32(be[i]) << shift
            shift += 8
            if shift == 32 {
                limbs.append(cur)
                cur = 0
                shift = 0
            }
            i -= 1
        }
        if shift != 0 { limbs.append(cur) }
        return Nat(limbs: limbs)
    }

    /// FromU32 makes a small Nat.
    public static func FromU32(_ v: uint32) -> Nat {
        if v == 0 { return Nat() }
        return Nat(limbs: [v])
    }

    /// FromU64 makes a Nat of a uint64.
    public static func FromU64(_ v: uint64) -> Nat {
        return Nat(limbs: [uint32(truncatingIfNeeded: v), uint32(truncatingIfNeeded: v >> 32)])
    }

    /// FromFloat64 is the whole part of a finite, non-negative double, exactly.
    public static func FromFloat64(_ d: float64) -> Nat {
        if !(d >= 1) || d.isInfinite { return Nat() }
        let bits = d.bitPattern
        let exp = int((bits >> 52) & 0x7FF) - 1075
        let mant = (bits & 0xFFFFFFFFFFFFF) | (uint64(1) << 52)
        if exp >= 0 { return ShiftLeft(Nat.FromU64(mant), exp) }
        return ShiftRight(Nat.FromU64(mant), -exp)
    }

    /// Parse reads digits in a radix from 2 to 36, letters in either case;
    /// nil for an empty string or a character that isn't a digit.
    public static func Parse(_ s: string, radix: int = 10) -> Nat? {
        if radix < 2 || radix > 36 { return nil }
        var n = Nat()
        var any = false
        for c in s.utf8 {
            var d = 99
            if c >= 48 && c <= 57 { d = int(c - 48) } else if (c | 0x20) >= 97 && (c | 0x20) <= 122 { d = int((c | 0x20) - 97) + 10 }
            if d >= radix { return nil }
            n = mulSmall(n, uint32(radix), uint32(d))
            any = true
        }
        return any ? n : nil
    }

    /// ToString writes the digits in a radix from 2 to 36, lowercase.
    public func ToString(_ radix: int = 10) -> string {
        if limbs.count == 0 { return "0" }
        let digits: [uint8] = [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122]
        // Peel off the largest power of the radix that fits a limb at a time.
        var chunk: uint32 = uint32(radix)
        var perChunk = 1
        while uint64(chunk) * uint64(radix) <= 0xFFFFFFFF {
            chunk *= uint32(radix)
            perChunk += 1
        }
        var out: [uint8] = []
        var cur = self
        while !cur.IsZero {
            let (q, r) = divSmall(cur, chunk)
            var rem = r
            var k = 0
            while k < perChunk && !(q.IsZero && rem == 0) {
                out.append(digits[int(rem % uint32(radix))])
                rem /= uint32(radix)
                k += 1
            }
            cur = q
        }
        var i = 0
        var j = out.count - 1
        while i < j {
            let t = out[i]
            out[i] = out[j]
            out[j] = t
            i += 1
            j -= 1
        }
        return string(decoding: out, as: UTF8.self)
    }

    /// ToU64 is the value as a uint64, or nil if it doesn't fit.
    public func ToU64() -> uint64? {
        if limbs.count > 2 { return nil }
        var v: uint64 = 0
        if limbs.count > 1 { v = uint64(limbs[1]) << 32 }
        if limbs.count > 0 { v |= uint64(limbs[0]) }
        return v
    }

    /// LowU64 is the low 64 bits.
    public var LowU64: uint64 {
        var v: uint64 = 0
        if limbs.count > 1 { v = uint64(limbs[1]) << 32 }
        if limbs.count > 0 { v |= uint64(limbs[0]) }
        return v
    }

    /// ToFloat64 is the nearest double, ties to even (infinity past the range).
    public func ToFloat64() -> float64 {
        let n = BitLen
        if n <= 64 { return float64(LowU64) }
        if n > 1024 { return float64.infinity }
        // Keep the top 53 bits; round by the bit below them and whether
        // anything under that is set.
        let shift = n - 53
        var m = ShiftRight(self, shift).LowU64
        let half = bit(shift - 1) == 1
        let sticky = Cmp(ShiftLeft(ShiftRight(self, shift - 1), shift - 1), self) != 0
        if half && (sticky || (m & 1) == 1) { m += 1 }
        return float64(m) * pow2(shift)
    }

    mutating func normalize() {
        while limbs.count > 0 && limbs[limbs.count - 1] == 0 {
            limbs.removeLast()
        }
    }

    public var IsZero: bool { return limbs.count == 0 }

    /// BitLen is the position of the highest set bit (0 for zero).
    public var BitLen: int {
        if limbs.count == 0 { return 0 }
        let top = limbs[limbs.count - 1]
        var bits = (limbs.count - 1) * 32
        var t = top
        while t != 0 { bits += 1; t >>= 1 }
        return bits
    }

    func bit(_ i: int) -> uint32 {
        let limb = i / 32
        if limb >= limbs.count { return 0 }
        return (limbs[limb] >> uint32(i % 32)) & 1
    }

    /// ToBytes returns the big-endian magnitude, at least one byte, with no
    /// leading zeros beyond that.
    public func ToBytes() -> [uint8] {
        if limbs.count == 0 { return [0] }
        var be: [uint8] = []
        var i = limbs.count - 1
        // Most significant limb without leading zero bytes.
        let top = limbs[i]
        var started = false
        var b = 3
        while b >= 0 {
            let byte = uint8(truncatingIfNeeded: top >> uint32(b * 8))
            if started || byte != 0 { be.append(byte); started = true }
            b -= 1
        }
        if !started { be.append(0) }
        i -= 1
        while i >= 0 {
            let limb = limbs[i]
            be.append(uint8(truncatingIfNeeded: limb >> 24))
            be.append(uint8(truncatingIfNeeded: limb >> 16))
            be.append(uint8(truncatingIfNeeded: limb >> 8))
            be.append(uint8(truncatingIfNeeded: limb))
            i -= 1
        }
        return be
    }

    /// ToBytesPadded returns the big-endian magnitude in exactly n bytes,
    /// left-padded with zeros (RSA outputs are fixed to the modulus size).
    public func ToBytesPadded(_ n: int) -> [uint8] {
        let raw = ToBytes()
        if raw.count >= n {
            // Trim leading zeros down to n if raw is a single [0].
            if raw.count == n { return raw }
            var out: [uint8] = []
            var i = raw.count - n
            while i < raw.count { out.append(raw[i]); i += 1 }
            return out
        }
        var out = [uint8](repeating: 0, count: n - raw.count)
        out.append(contentsOf: raw)
        return out
    }
}

/// Cmp returns -1, 0, or 1 for a<b, a==b, a>b.
public func Cmp(_ a: Nat, _ b: Nat) -> int {
    if a.limbs.count != b.limbs.count {
        return a.limbs.count < b.limbs.count ? -1 : 1
    }
    var i = a.limbs.count - 1
    while i >= 0 {
        if a.limbs[i] != b.limbs[i] {
            return a.limbs[i] < b.limbs[i] ? -1 : 1
        }
        i -= 1
    }
    return 0
}

/// Add returns a + b.
public func Add(_ a: Nat, _ b: Nat) -> Nat {
    var out: [uint32] = []
    let n = a.limbs.count > b.limbs.count ? a.limbs.count : b.limbs.count
    var carry: uint64 = 0
    var i = 0
    while i < n {
        let av = i < a.limbs.count ? uint64(a.limbs[i]) : 0
        let bv = i < b.limbs.count ? uint64(b.limbs[i]) : 0
        let sum = av + bv + carry
        out.append(uint32(truncatingIfNeeded: sum))
        carry = sum >> 32
        i += 1
    }
    if carry != 0 { out.append(uint32(truncatingIfNeeded: carry)) }
    return Nat(limbs: out)
}

/// Sub returns a - b, requiring a >= b.
public func Sub(_ a: Nat, _ b: Nat) -> Nat {
    var out: [uint32] = []
    var borrow: int64 = 0
    var i = 0
    while i < a.limbs.count {
        let av = int64(a.limbs[i])
        let bv = i < b.limbs.count ? int64(b.limbs[i]) : 0
        var diff = av - bv - borrow
        if diff < 0 { diff += (int64(1) << 32); borrow = 1 } else { borrow = 0 }
        out.append(uint32(truncatingIfNeeded: diff))
        i += 1
    }
    return Nat(limbs: out)
}

/// Mul returns a * b (schoolbook).
public func Mul(_ a: Nat, _ b: Nat) -> Nat {
    if a.IsZero || b.IsZero { return Nat() }
    var out = [uint32](repeating: 0, count: a.limbs.count + b.limbs.count)
    var i = 0
    while i < a.limbs.count {
        var carry: uint64 = 0
        let av = uint64(a.limbs[i])
        var j = 0
        while j < b.limbs.count {
            let idx = i + j
            let cur = uint64(out[idx]) + av * uint64(b.limbs[j]) + carry
            out[idx] = uint32(truncatingIfNeeded: cur)
            carry = cur >> 32
            j += 1
        }
        var k = i + b.limbs.count
        while carry != 0 {
            let cur = uint64(out[k]) + carry
            out[k] = uint32(truncatingIfNeeded: cur)
            carry = cur >> 32
            k += 1
        }
        i += 1
    }
    return Nat(limbs: out)
}

/// shiftLeftOne doubles a Nat.
func shiftLeftOne(_ a: Nat) -> Nat {
    var out: [uint32] = []
    var carry: uint32 = 0
    var i = 0
    while i < a.limbs.count {
        let v = a.limbs[i]
        out.append((v << 1) | carry)
        carry = v >> 31
        i += 1
    }
    if carry != 0 { out.append(carry) }
    return Nat(limbs: out)
}

/// setBit returns a with bit i set (a must have that bit clear).
func withBit(_ a: Nat, _ i: int) -> Nat {
    var limbs = a.limbs
    let limb = i / 32
    while limbs.count <= limb { limbs.append(0) }
    limbs[limb] |= (uint32(1) << uint32(i % 32))
    return Nat(limbs: limbs)
}

/// DivMod returns (quotient, remainder) for a / m, m != 0: Knuth's
/// algorithm D (TAOCP 4.3.1), a limb of quotient per step.
public func DivMod(_ a: Nat, _ m: Nat) -> (Nat, Nat) {
    if Cmp(a, m) < 0 { return (Nat(), a) }
    if m.limbs.count == 1 {
        let (q, r) = divSmall(a, m.limbs[0])
        return (q, Nat.FromU32(r))
    }
    // Normalize so the divisor's top limb has its high bit set.
    var top = m.limbs[m.limbs.count - 1]
    var shift = 0
    while top & 0x80000000 == 0 {
        top <<= 1
        shift += 1
    }
    let v = ShiftLeft(m, shift).limbs
    var u = ShiftLeft(a, shift).limbs
    while u.count < a.limbs.count + 1 { u.append(0) }
    let n = v.count
    let steps = u.count - n
    var q = [uint32](repeating: 0, count: steps)
    let vTop = uint64(v[n - 1])
    let vNext = uint64(v[n - 2])
    var j = steps - 1
    while j >= 0 {
        let num = (uint64(u[j + n]) << 32) | uint64(u[j + n - 1])
        var qhat = num / vTop
        var rhat = num % vTop
        while qhat >= 0x100000000 || qhat * vNext > ((rhat << 32) | uint64(u[j + n - 2])) {
            qhat -= 1
            rhat += vTop
            if rhat >= 0x100000000 { break }
        }
        // u[j..j+n] -= qhat · v
        var borrow: int64 = 0
        var carry: uint64 = 0
        var i = 0
        while i < n {
            let p = qhat * uint64(v[i]) + carry
            carry = p >> 32
            let t = int64(u[i + j]) - borrow - int64(p & 0xFFFFFFFF)
            u[i + j] = uint32(truncatingIfNeeded: t)
            borrow = t < 0 ? 1 : 0
            i += 1
        }
        let t = int64(u[j + n]) - borrow - int64(carry)
        u[j + n] = uint32(truncatingIfNeeded: t)
        if t < 0 {
            // qhat was one too big: add v back.
            qhat -= 1
            var c: uint64 = 0
            i = 0
            while i < n {
                let s = uint64(u[i + j]) + uint64(v[i]) + c
                u[i + j] = uint32(truncatingIfNeeded: s)
                c = s >> 32
                i += 1
            }
            u[j + n] = uint32(truncatingIfNeeded: uint64(u[j + n]) + c)
        }
        q[j] = uint32(truncatingIfNeeded: qhat)
        j -= 1
    }
    var r: [uint32] = []
    var k = 0
    while k < n {
        r.append(u[k])
        k += 1
    }
    return (Nat(limbs: q), ShiftRight(Nat(limbs: r), shift))
}

/// divSmall divides by one limb.
func divSmall(_ a: Nat, _ d: uint32) -> (Nat, uint32) {
    var q = [uint32](repeating: 0, count: a.limbs.count)
    var r: uint64 = 0
    var i = a.limbs.count - 1
    while i >= 0 {
        let cur = (r << 32) | uint64(a.limbs[i])
        q[i] = uint32(truncatingIfNeeded: cur / uint64(d))
        r = cur % uint64(d)
        i -= 1
    }
    return (Nat(limbs: q), uint32(truncatingIfNeeded: r))
}

/// mulSmall is a · m + add.
func mulSmall(_ a: Nat, _ m: uint32, _ add: uint32) -> Nat {
    var out: [uint32] = []
    out.reserveCapacity(a.limbs.count + 1)
    var carry = uint64(add)
    for x in a.limbs {
        let t = uint64(x) * uint64(m) + carry
        out.append(uint32(truncatingIfNeeded: t))
        carry = t >> 32
    }
    if carry != 0 { out.append(uint32(truncatingIfNeeded: carry)) }
    return Nat(limbs: out)
}

/// ShiftLeft is a · 2^n.
public func ShiftLeft(_ a: Nat, _ n: int) -> Nat {
    if a.IsZero || n == 0 { return a }
    let whole = n / 32
    let bits = n % 32
    var out = [uint32](repeating: 0, count: whole)
    if bits == 0 {
        out.append(contentsOf: a.limbs)
    } else {
        var carry: uint32 = 0
        for x in a.limbs {
            out.append((x << uint32(bits)) | carry)
            carry = x >> uint32(32 - bits)
        }
        if carry != 0 { out.append(carry) }
    }
    return Nat(limbs: out)
}

/// ShiftRight is a / 2^n, rounded down.
public func ShiftRight(_ a: Nat, _ n: int) -> Nat {
    if n == 0 { return a }
    let whole = n / 32
    let bits = n % 32
    if whole >= a.limbs.count { return Nat() }
    var out: [uint32] = []
    var i = whole
    while i < a.limbs.count {
        var v = a.limbs[i] >> uint32(bits)
        if bits != 0 && i + 1 < a.limbs.count {
            v |= a.limbs[i + 1] << uint32(32 - bits)
        }
        out.append(v)
        i += 1
    }
    return Nat(limbs: out)
}

/// Pow is a^e.
public func Pow(_ a: Nat, _ e: int) -> Nat {
    var result = Nat.FromU32(1)
    var b = a
    var k = e
    while k > 0 {
        if k & 1 == 1 { result = Mul(result, b) }
        k >>= 1
        if k > 0 { b = Mul(b, b) }
    }
    return result
}

/// And, Or and Xor are the bitwise operations on magnitudes.
public func And(_ a: Nat, _ b: Nat) -> Nat {
    let n = a.limbs.count < b.limbs.count ? a.limbs.count : b.limbs.count
    var out: [uint32] = []
    var i = 0
    while i < n {
        out.append(a.limbs[i] & b.limbs[i])
        i += 1
    }
    return Nat(limbs: out)
}

public func Or(_ a: Nat, _ b: Nat) -> Nat {
    let n = a.limbs.count > b.limbs.count ? a.limbs.count : b.limbs.count
    var out: [uint32] = []
    var i = 0
    while i < n {
        let x = i < a.limbs.count ? a.limbs[i] : 0
        let y = i < b.limbs.count ? b.limbs[i] : 0
        out.append(x | y)
        i += 1
    }
    return Nat(limbs: out)
}

public func Xor(_ a: Nat, _ b: Nat) -> Nat {
    let n = a.limbs.count > b.limbs.count ? a.limbs.count : b.limbs.count
    var out: [uint32] = []
    var i = 0
    while i < n {
        let x = i < a.limbs.count ? a.limbs[i] : 0
        let y = i < b.limbs.count ? b.limbs[i] : 0
        out.append(x ^ y)
        i += 1
    }
    return Nat(limbs: out)
}

/// Mod returns a mod m.
public func Mod(_ a: Nat, _ m: Nat) -> Nat {
    let (_, r) = DivMod(a, m)
    return r
}

/// MulMod returns (a * b) mod m.
public func MulMod(_ a: Nat, _ b: Nat, _ m: Nat) -> Nat {
    return Mod(Mul(a, b), m)
}

/// ExpMod returns (base ^ exp) mod m by square-and-multiply. This is the
/// RSA public-key operation; with a public exponent it needs no constant
/// time, and RSA verification handles only public values.
public func ExpMod(_ base: Nat, _ exp: Nat, _ m: Nat) -> Nat {
    if m.IsZero { return Nat() }
    var result = Nat.FromU32(1)
    let one = Nat.FromU32(1)
    if Cmp(m, one) == 0 { return Nat() }
    var b = Mod(base, m)
    let bits = exp.BitLen
    var i = 0
    while i < bits {
        if exp.bit(i) == 1 {
            result = MulMod(result, b, m)
        }
        b = MulMod(b, b, m)
        i += 1
    }
    return result
}

/// pow2 is 2^n as a double, exactly (for n in the double's range).
func pow2(_ n: int) -> float64 {
    if n > 1023 { return float64.infinity }
    if n >= -1022 { return float64(bitPattern: uint64(n + 1023) << 52) }
    return float64(bitPattern: uint64(1) << uint64(n + 1074))
}
