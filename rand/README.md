# math/rand

Fast, reproducible pseudo-random generators: not for secrets (crypto/rand is), but for simulations, tests, shuffles, and JavaScript's Math.random.

```vertex
import "math/rand"
```

## Types

- **`SplitMix64`** (struct): SplitMix64 is Steele, Lea and Flood's generator: every seed is good, so it is also how the other generators turn one seed into their state.
- **`Xorshift128Plus`** (struct): Xorshift128Plus is Vigna's xorshift128+, the generator behind V8's and SpiderMonkey's Math.random.

Part of the [`math`](https://github.com/vertex-language/math) repository.
