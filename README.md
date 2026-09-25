# math

Numeric primitives for Vertex.

- **`math`**: elementary functions in pure Vertex, for the host and for
  kernels alike. A GPU has no libm, so these are the functions a kernel
  calls. Because nothing here calls a C library or a device's approximate
  instruction, the same call gives the same bits on every device that
  keeps subnormals. Apple's GPUs flush float32 subnormals to zero, and
  that is the only difference `tests/math/device.vs` finds there.
- **`math/big`**: unsigned arbitrary-precision integers (`Nat`): compare,
  add/sub/mul, division with remainder, and modular exponentiation
  (`ExpMod`). Enough for RSA public-key operations and signature
  verification.

## `math`, float32

Everything is `@inlinable`, so a kernel in any module compiles it into
itself. The algorithms are Cephes' (range reduction, then a minimax
polynomial). `Erfc`'s tail is fitted here at Chebyshev nodes. Errors are
the worst over 200,000 arguments against the host's double-precision libm,
in units in the last place of the float32 result (`tests/math/main.vs`):

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
about 12,000 (Payne–Hanek).

```sh
vsc run -P ~/Desktop tests/math/main.vs      # accuracy against libm
vsc run -P ~/Desktop tests/math/device.vs    # every device against the host
```
