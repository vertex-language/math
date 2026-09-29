# math

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![math: float32 | float64 | big](https://img.shields.io/badge/math-float32%20%7C%20float64%20%7C%20big-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/math)

Numeric primitives in pure Vertex: elementary functions in single and
double precision, the small helpers every package reaches for, and
arbitrary-precision integers. Nothing here calls a C library, so the same
call gives the same bits on every machine.

- **`math`**: `Sin`, `Exp`, `Log`, `Pow` and the rest, overloaded for `float32` and `float64` (the argument's type picks one); `Clamp`, `Lerp`, `Saturate`, `FloorDiv`, `FloorMod`, `CeilDiv`, `RoundToInt`; the constants `Pi`, `E`, `Ln2`, `Ln10`, `Log2E`, `Log10E`, `Sqrt2`, `SqrtHalf`.
- **`math/big`**: `Nat`, unsigned, and `Integer`, signed: add, subtract, multiply, divide (Knuth's algorithm D), powers, shifts, the bitwise operations on two's complement, text in any radix from 2 to 36, and exact conversion to and from `float64`. `ExpMod` for RSA.
- **`math/rand`**: fast, reproducible pseudo-random generators for simulations, tests and shuffles (secrets use `crypto/rand`): `SplitMix64`, and `Xorshift128Plus` with `Float64` in [0, 1) and unbiased `Below(n)`. It is the generator V8 uses for `Math.random`.

---

## `math`, float32: host and kernels

Everything is `@inlinable` and reads no table or global, so a kernel in any
module compiles it into itself. A GPU has no libm; these are the functions
a kernel calls. The algorithms are Cephes' (range reduction, then a minimax
polynomial). `Erfc`'s tail is fitted here at Chebyshev nodes. Errors are the
worst over 200,000 arguments against the host's double-precision libm, in
units in the last place of the float32 result (`cmd/test-math`):

| Function | Range tested | Worst |
| --- | --- | --- |
| `Exp` | [-103, 88.7] | 0.94 |
| `Exp2` | [-149, 128) | 0.94 |
| `Log` | [1e-38, 3e38] | 0.78 |
| `Log2`, `Log10` | [1e-30, 1e30] | 1.4, 1.7 |
| `Sin`, `Cos` | [-3.2, 3.2] | 1.3 |
| `Sin`, `Cos` | [-12000, 12000] | 2.4 |
| `Tan` | [-1.5, 1.5] | 2.7 |
| `Tanh` | [-10, 10] | 1.2 |
| `Atan` | [-1e6, 1e6] | 2.7 |
| `Atan2` | the plane, with C's signed zeros and infinities | 3.0 |
| `Erf` | [-5, 5] | 2.4 |
| `Erfc` | [1, 9] | 3.9 |
| `Sigmoid` | [-80, 80] | 2.2 |

Also: `Sqrt` and `Rsqrt`; `Floor`, `Ceil`, `Trunc`, `Round`, `Abs`,
`CopySign`, `Min` and `Max`; `Ldexp` and `Frexp`.

Not yet in float32: `Pow`, `Asin`/`Acos`, the other inverse trigonometric
and hyperbolic functions, and argument reduction for `Sin` and `Cos` beyond
12000.

## `math`, float64: the host

fdlibm's algorithms (Sun, 1993), as FreeBSD's msun and V8's `ieee754.cc`
keep them: `Sin`, `Cos`, `Tan` (with Payne–Hanek reduction for huge
arguments), `Asin`, `Acos`, `Atan`, `Atan2`, `Exp`, `Expm1`, `Exp2`, `Log`,
`Log1p`, `Log2`, `Log10`, `Pow` (with C99's special cases), `Cbrt`,
`Hypot`, `Sinh`, `Cosh`, `Tanh`, `Asinh`, `Acosh`, `Atanh`; and `Sqrt`,
`Floor`, `Ceil`, `Trunc`, `Round` (ties to even), `RoundHalfAway`, `Abs`,
`CopySign`, `Min`, `Max`, `Fmod`, `Remainder`, `Modf`, `Ldexp`, `Frexp`,
`NextUp`, `NextDown`. Each is under one ulp from the true value.

They read a few constant tables (the bits of 2/π), so they aren't
`@inlinable` into kernels; Metal has no float64 anyway.

`cmd/test-float64` checks 94,000 arguments against V8, whose `Math`
functions are these. On x86-64 the two agree bit for bit. The recording in
`testdata/float64.txt` is from an arm64 build of node, which clang compiles
with fused multiply-adds (`-ffp-contract=on`): that moves about one result
in a few hundred by one ulp, and there `Math.pow` is the platform's libm.
So the test asks for every result within one ulp of V8's and nearly all
identical; `Log2`, `Cbrt`, `Cosh` and `Tanh` match on every argument.

---

## Quick Start

```vertex
import (
    "math"
    "math/big"
)

math.Sin(1.0)                         // float64: 0.8414709848078965
math.Sin(float32(1))                  // float32, and callable from a kernel
math.Clamp(300, 0, 255)               // 255
math.FloorMod(-7, 3)                  // 2

let x = big.Integer.Parse("123456789012345678901234567890")!
let y = big.Mul(x, x)
y.ToString(16)                        // hex digits
big.ShiftRight(big.Integer(-5), 1)    // -3, as an arithmetic shift rounds
```

---

## Testing

```bash
vsc run test-math          # float32 accuracy against libm
vsc run test-math-device   # float32 on the available accelerators
vsc run test-float64       # float64 against V8 (testdata/float64.txt)
vsc run test-big           # big, and 41,570 operations against node's BigInt
```

`testdata/gen_float64.mjs` and `testdata/gen_big.mjs` regenerate the
recordings with node.

---

## License

[MIT](LICENSE)
