# math/big

Arbitrary-precision unsigned integer arithmetic, enough for public-key cryptography: comparison, add/sub/mul, division with remainder, and modular exponentiation.

```vertex
import "math/big"
```

## Types

- **`Nat`** (struct): Nat is a non-negative arbitrary-precision integer.
- **`Integer`** (struct): Integer is a signed arbitrary-precision integer: a sign and a Nat magnitude. Zero is never negative.

## Functions

- `func Cmp(_ a: Nat, _ b: Nat) -> int`: Cmp returns -1, 0, or 1 for a<b, a==b, a>b.
- `func Add(_ a: Nat, _ b: Nat) -> Nat`: Add returns a + b.
- `func Sub(_ a: Nat, _ b: Nat) -> Nat`: Sub returns a - b, requiring a >= b.
- `func Mul(_ a: Nat, _ b: Nat) -> Nat`: Mul returns a * b (schoolbook).
- `func DivMod(_ a: Nat, _ m: Nat) -> (Nat, Nat)`: DivMod returns (quotient, remainder) for a / m, m != 0: Knuth's algorithm D (TAOCP 4.3.1), a limb of quotient per step.
- `func ShiftLeft(_ a: Nat, _ n: int) -> Nat`: ShiftLeft is a · 2^n.
- `func ShiftRight(_ a: Nat, _ n: int) -> Nat`: ShiftRight is a / 2^n, rounded down.
- `func Pow(_ a: Nat, _ e: int) -> Nat`: Pow is a^e.
- `func And(_ a: Nat, _ b: Nat) -> Nat`: And, Or and Xor are the bitwise operations on magnitudes.
- `func Or(_ a: Nat, _ b: Nat) -> Nat`
- and 22 more

Part of the [`math`](https://github.com/vertex-language/math) repository.
