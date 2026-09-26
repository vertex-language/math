# math

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![math: float32 | big](https://img.shields.io/badge/math-float32%20%7C%20big-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/math)

Numeric primitives: elementary floating-point math functions for host and device execution, and arbitrary-precision integer arithmetic.

- **`math`**: elementary functions for the host and for kernels alike. A GPU has no libm, so these are the functions a kernel calls. Because nothing here calls a C library or a device's approximate instruction, the same call gives the same bits on every device that keeps subnormals.
- **`math/big`**: unsigned arbitrary-precision integers (`Nat`): compare, add/sub/mul, division with remainder, and modular exponentiation (`ExpMod`). Suitable for cryptographic operations and precision calculations.

## `math`, float32

Everything is `@inlinable`, so a kernel in any module compiles it into
itself. The algorithms are Cephes' (range reduction, then a minimax
polynomial). `Erfc`'s tail is fitted here at Chebyshev nodes. Errors are
the worst over 200,000 arguments against the host's double-precision libm,
in units in the last place of the float32 result (`cmd/test-math`):

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
| `Erf` | [-5, 5] | 2.4 |
| `Erfc` | [1, 9] | 3.9 |
| `Sigmoid` | [-80, 80] | 2.2 |

Also: `Sqrt` and `Rsqrt`; `Floor`, `Ceil`, `Trunc`, `Round`, `Abs`,
`CopySign`, `Min` and `Max`; `Ldexp` and `Frexp`.

Not yet: `Pow`, `Atan`/`Atan2`, the inverse trig and hyperbolic functions,
the float64 versions, and argument reduction for `Sin` and `Cos` beyond
---

## Quick Start

Run any entry point with:

```bash
vsc run main.vs
```

### Verification & Testing

```bash
# Accuracy against libm
vsc run test-math

# Device tests across available accelerators
vsc run test-math-device
```

---

## License

[MIT](LICENSE)
