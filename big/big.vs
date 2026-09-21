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

/// DivMod returns (quotient, remainder) for a / m, m != 0. Binary long
/// division: correct and simple, fast enough for RSA-sized verification.
public func DivMod(_ a: Nat, _ m: Nat) -> (Nat, Nat) {
    if Cmp(a, m) < 0 { return (Nat(), a) }
    var q = Nat()
    var r = Nat()
    var i = a.BitLen - 1
    while i >= 0 {
        r = shiftLeftOne(r)
        if a.bit(i) == 1 {
            r = withBit(r, 0)
        }
        if Cmp(r, m) >= 0 {
            r = Sub(r, m)
            q = withBit(q, i)
        }
        i -= 1
    }
    return (q, r)
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
