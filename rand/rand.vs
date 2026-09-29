// Package rand is fast, reproducible pseudo-random generators: not for
// secrets (crypto/rand is), but for simulations, tests, shuffles, and
// JavaScript's Math.random.
package rand

/// SplitMix64 is Steele, Lea and Flood's generator: every seed is good,
/// so it is also how the other generators turn one seed into their state.
public struct SplitMix64 {
    var state: uint64

    public init(seed: uint64) {
        state = seed
    }

    public mutating func Next() -> uint64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Xorshift128Plus is Vigna's xorshift128+, the generator behind V8's and
/// SpiderMonkey's Math.random.
public struct Xorshift128Plus {
    var s0: uint64
    var s1: uint64

    public init(seed: uint64) {
        var sm = SplitMix64(seed: seed)
        s0 = sm.Next()
        s1 = sm.Next()
        if s0 == 0 && s1 == 0 { s1 = 1 }
    }

    public mutating func Next() -> uint64 {
        var x = s0
        let y = s1
        s0 = y
        x ^= x << 23
        s1 = x ^ y ^ (x >> 17) ^ (y >> 26)
        return s1 &+ y
    }

    /// Float64 is uniform in [0, 1), from the top 53 bits.
    public mutating func Float64() -> float64 {
        return float64(Next() >> 11) * (1.0 / 9007199254740992.0)
    }

    /// Below is uniform in [0, n), without modulo bias; n > 0.
    public mutating func Below(_ n: uint64) -> uint64 {
        let limit = (0 &- n) % n
        while true {
            let v = Next()
            if v >= limit { return v % n }
        }
    }
}
