package big

/// Integer is a signed arbitrary-precision integer: a sign and a Nat
/// magnitude. Zero is never negative.
public struct Integer {
    public let Negative: bool
    public let Magnitude: Nat

    public init(negative: bool, magnitude: Nat) {
        self.Magnitude = magnitude
        self.Negative = negative && !magnitude.IsZero
    }

    public init() {
        self.Magnitude = Nat()
        self.Negative = false
    }

    public init(_ v: int64) {
        if v < 0 {
            let m: uint64 = v == int64.min ? uint64(1) << 63 : uint64(-v)
            self.init(negative: true, magnitude: Nat.FromU64(m))
        } else {
            self.init(negative: false, magnitude: Nat.FromU64(uint64(v)))
        }
    }

    public init(_ n: Nat) {
        self.init(negative: false, magnitude: n)
    }

    public var IsZero: bool { return Magnitude.IsZero }

    /// Sign is -1, 0 or 1.
    public var Sign: int { return IsZero ? 0 : (Negative ? -1 : 1) }

    /// FromFloat64 is the whole part of a finite double, exactly.
    public static func FromFloat64(_ d: float64) -> Integer {
        if d < 0 { return Integer(negative: true, magnitude: Nat.FromFloat64(-d)) }
        return Integer(Nat.FromFloat64(d))
    }

    /// Parse reads an optional sign and digits in a radix from 2 to 36.
    public static func Parse(_ s: string, radix: int = 10) -> Integer? {
        var neg = false
        var body = s
        if s.hasPrefix("-") || s.hasPrefix("+") {
            neg = s.hasPrefix("-")
            body = string(s.dropFirst())
        }
        guard let m = Nat.Parse(body, radix: radix) else { return nil }
        return Integer(negative: neg, magnitude: m)
    }

    /// ToString writes an optional minus sign and the digits in a radix.
    public func ToString(_ radix: int = 10) -> string {
        let digits = Magnitude.ToString(radix)
        return Negative ? "-" + digits : digits
    }

    /// ToFloat64 is the nearest double, ties to even.
    public func ToFloat64() -> float64 {
        let m = Magnitude.ToFloat64()
        return Negative ? -m : m
    }

    /// WrappingInt64 is the low 64 bits in two's complement.
    public var WrappingInt64: int64 {
        let low = Magnitude.LowU64
        return Negative ? int64(bitPattern: ~low &+ 1) : int64(bitPattern: low)
    }

    /// ToInt64 is the value if it fits an int64, else nil.
    public func ToInt64() -> int64? {
        guard let m = Magnitude.ToU64() else { return nil }
        if Negative {
            if m > uint64(1) << 63 { return nil }
            return m == uint64(1) << 63 ? int64.min : -int64(m)
        }
        if m > uint64(int64.max) { return nil }
        return int64(m)
    }
}

/// Cmp orders two Integers: -1, 0 or 1.
public func Cmp(_ a: Integer, _ b: Integer) -> int {
    if a.Negative != b.Negative { return a.Negative ? -1 : 1 }
    let c = Cmp(a.Magnitude, b.Magnitude)
    return a.Negative ? -c : c
}

public func Neg(_ a: Integer) -> Integer {
    return Integer(negative: !a.Negative, magnitude: a.Magnitude)
}

public func Abs(_ a: Integer) -> Integer {
    return Integer(a.Magnitude)
}

public func Add(_ a: Integer, _ b: Integer) -> Integer {
    if a.Negative == b.Negative {
        return Integer(negative: a.Negative, magnitude: Add(a.Magnitude, b.Magnitude))
    }
    let c = Cmp(a.Magnitude, b.Magnitude)
    if c == 0 { return Integer() }
    if c > 0 { return Integer(negative: a.Negative, magnitude: Sub(a.Magnitude, b.Magnitude)) }
    return Integer(negative: b.Negative, magnitude: Sub(b.Magnitude, a.Magnitude))
}

public func Sub(_ a: Integer, _ b: Integer) -> Integer {
    return Add(a, Neg(b))
}

public func Mul(_ a: Integer, _ b: Integer) -> Integer {
    return Integer(negative: a.Negative != b.Negative, magnitude: Mul(a.Magnitude, b.Magnitude))
}

/// QuoRem divides rounding toward zero: the remainder has a's sign, as
/// the / and % operators on machine integers do. b must not be zero.
public func QuoRem(_ a: Integer, _ b: Integer) -> (Integer, Integer) {
    let (q, r) = DivMod(a.Magnitude, b.Magnitude)
    return (Integer(negative: a.Negative != b.Negative, magnitude: q), Integer(negative: a.Negative, magnitude: r))
}

/// Quo is a / b rounded toward zero.
public func Quo(_ a: Integer, _ b: Integer) -> Integer {
    let (q, _) = QuoRem(a, b)
    return q
}

/// Rem is the remainder of Quo, with a's sign.
public func Rem(_ a: Integer, _ b: Integer) -> Integer {
    let (_, r) = QuoRem(a, b)
    return r
}

/// Pow is a^e.
public func Pow(_ a: Integer, _ e: int) -> Integer {
    return Integer(negative: a.Negative && (e & 1) == 1, magnitude: Pow(a.Magnitude, e))
}

/// ShiftLeft is a · 2^n; a negative n shifts right.
public func ShiftLeft(_ a: Integer, _ n: int) -> Integer {
    if n < 0 { return ShiftRight(a, -n) }
    return Integer(negative: a.Negative, magnitude: ShiftLeft(a.Magnitude, n))
}

/// ShiftRight is a / 2^n rounded toward negative infinity (an arithmetic
/// shift of the two's complement); a negative n shifts left.
public func ShiftRight(_ a: Integer, _ n: int) -> Integer {
    if n < 0 { return ShiftLeft(a, -n) }
    let q = ShiftRight(a.Magnitude, n)
    if a.Negative && Cmp(ShiftLeft(q, n), a.Magnitude) != 0 {
        return Integer(negative: true, magnitude: Add(q, Nat.FromU32(1)))
    }
    return Integer(negative: a.Negative, magnitude: q)
}

// The bitwise operations act on the infinite two's complement form, where
// -x is ~(x - 1).

/// twos is a's two's complement in `limbs` limbs.
func twos(_ a: Integer, _ limbs: int) -> [uint32] {
    var out = [uint32](repeating: 0, count: limbs)
    var i = 0
    while i < a.Magnitude.limbs.count && i < limbs {
        out[i] = a.Magnitude.limbs[i]
        i += 1
    }
    if a.Negative {
        var carry: uint64 = 1
        i = 0
        while i < limbs {
            let t = uint64(~out[i]) + carry
            out[i] = uint32(truncatingIfNeeded: t)
            carry = t >> 32
            i += 1
        }
    }
    return out
}

func fromTwos(_ t: [uint32]) -> Integer {
    let negative = !t.isEmpty && (t[t.count - 1] & 0x80000000) != 0
    if !negative { return Integer(Nat(limbs: t)) }
    var m = t
    var carry: uint64 = 1
    var i = 0
    while i < m.count {
        let x = uint64(~m[i]) + carry
        m[i] = uint32(truncatingIfNeeded: x)
        carry = x >> 32
        i += 1
    }
    return Integer(negative: true, magnitude: Nat(limbs: m))
}

func bitwise(_ a: Integer, _ b: Integer, _ op: int) -> Integer {
    let n = (a.Magnitude.limbs.count > b.Magnitude.limbs.count ? a.Magnitude.limbs.count : b.Magnitude.limbs.count) + 1
    let x = twos(a, n)
    let y = twos(b, n)
    var out = [uint32](repeating: 0, count: n)
    var i = 0
    while i < n {
        if op == 0 { out[i] = x[i] & y[i] } else if op == 1 { out[i] = x[i] | y[i] } else { out[i] = x[i] ^ y[i] }
        i += 1
    }
    return fromTwos(out)
}

public func And(_ a: Integer, _ b: Integer) -> Integer { return bitwise(a, b, 0) }
public func Or(_ a: Integer, _ b: Integer) -> Integer { return bitwise(a, b, 1) }
public func Xor(_ a: Integer, _ b: Integer) -> Integer { return bitwise(a, b, 2) }

/// Not is ~a, which is -a - 1.
public func Not(_ a: Integer) -> Integer {
    return Sub(Neg(a), Integer(1))
}

/// TruncateUnsigned keeps a's low `bits` bits of two's complement, as a
/// non-negative value (a mod 2^bits).
public func TruncateUnsigned(_ a: Integer, _ bits: int) -> Integer {
    if bits == 0 { return Integer() }
    let limbs = (bits + 31) / 32 + 1
    var t = twos(a, limbs)
    var i = 0
    while i < t.count {
        let lo = i * 32
        if lo >= bits {
            t[i] = 0
        } else if lo + 32 > bits {
            t[i] &= (uint32(1) << uint32(bits - lo)) - 1
        }
        i += 1
    }
    return Integer(Nat(limbs: t))
}

/// TruncateSigned keeps a's low `bits` bits as a signed two's complement
/// value, in [-2^(bits-1), 2^(bits-1)).
public func TruncateSigned(_ a: Integer, _ bits: int) -> Integer {
    if bits == 0 { return Integer() }
    let u = TruncateUnsigned(a, bits)
    if u.Magnitude.BitLen == bits {
        return Sub(u, Integer(ShiftLeft(Nat.FromU32(1), bits)))
    }
    return u
}
