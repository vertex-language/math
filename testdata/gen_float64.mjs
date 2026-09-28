// Writes float64.txt: arguments and V8's results (its Math functions are
// fdlibm's) as IEEE bit patterns, for cmd/test-float64 to compare exactly.
//
//     node testdata/gen_float64.mjs > testdata/float64.txt
const buf = new DataView(new ArrayBuffer(8));
const bits = (x) => { buf.setFloat64(0, x); return buf.getBigUint64(0).toString(16).padStart(16, '0'); };
let seed = 12345n;
const rand = () => { seed = (seed * 6364136223846793005n + 1442695040888963407n) & 0xFFFFFFFFFFFFFFFFn; return Number(seed >> 11n) / 9007199254740992; };
const specials = [0, -0, 1, -1, 0.5, -0.5, 2, -2, Infinity, -Infinity, NaN, 1e-300, -1e-300, 5e-324, -5e-324, 1e300, -1e300, Math.PI, -Math.PI, Math.PI / 2, Math.PI / 4, 3 * Math.PI / 4, 1e-8, 1e-20, 0.1, 0.7, 1.5, 3, 10, 22, 100, 700, 709.7, 710, 745, -745, 1e10, 1e22, 1e100, 2 ** 53, 2 ** 60, 1.0000001, 0.9999999];
function args(lo, hi, n, log) {
  const out = [...specials];
  for (let i = 0; i < n; i++) {
    const r = rand();
    if (log) {
      const e = lo + (hi - lo) * r;
      out.push((rand() < 0.5 ? -1 : 1) * Math.pow(10, e));
    } else {
      out.push(lo + (hi - lo) * r);
    }
  }
  return out;
}
const unary = {
  Sin: [Math.sin, [-10, 10, 3000], [-300, 300, 2000, true]],
  Cos: [Math.cos, [-10, 10, 3000], [-300, 300, 2000, true]],
  Tan: [Math.tan, [-10, 10, 3000], [-300, 300, 2000, true]],
  Asin: [Math.asin, [-1, 1, 3000]],
  Acos: [Math.acos, [-1, 1, 3000]],
  Atan: [Math.atan, [-10, 10, 2000], [-300, 300, 2000, true]],
  Exp: [Math.exp, [-750, 750, 3000], [-30, 3, 1000, true]],
  Expm1: [Math.expm1, [-40, 710, 3000], [-30, 3, 1000, true]],
  Log: [Math.log, [0, 100, 2000], [-320, 308, 3000, true]],
  Log1p: [Math.log1p, [-1, 10, 3000], [-320, 308, 2000, true]],
  Log2: [Math.log2, [0, 100, 2000], [-320, 308, 3000, true]],
  Log10: [Math.log10, [0, 100, 2000], [-320, 308, 3000, true]],
  Cbrt: [Math.cbrt, [-100, 100, 2000], [-320, 308, 3000, true]],
  Sinh: [Math.sinh, [-30, 30, 3000], [-10, 3, 1000, true]],
  Cosh: [Math.cosh, [-30, 30, 3000], [-10, 3, 1000, true]],
  Tanh: [Math.tanh, [-30, 30, 3000], [-10, 3, 1000, true]],
  Asinh: [Math.asinh, [-30, 30, 2000], [-300, 300, 2000, true]],
  Acosh: [Math.acosh, [1, 30, 2000], [0, 300, 2000, true]],
  Atanh: [Math.atanh, [-1, 1, 3000]],
};
const lines = [];
for (const [name, [f, ...ranges]] of Object.entries(unary)) {
  const seen = new Set();
  for (const r of ranges) {
    for (const x of args(r[0], r[1], r[2], r[3])) {
      const k = bits(x);
      if (seen.has(k)) continue;
      seen.add(k);
      lines.push(`${name} ${k} ${bits(f(x))}`);
    }
  }
}
// Pow and Atan2 over pairs. Math.pow differs from C99 only for y NaN and
// (±1)^±∞, which the pairs skip.
for (let i = 0; i < 6000; i++) {
  let x, y;
  const r = rand();
  if (r < 0.3) { x = (rand() - 0.5) * 20; y = (rand() - 0.5) * 20; }
  else if (r < 0.5) { x = rand() * 10; y = Math.floor((rand() - 0.5) * 60); }
  else if (r < 0.7) { x = -rand() * 10; y = Math.floor((rand() - 0.5) * 30); }
  else if (r < 0.85) { x = Math.pow(10, (rand() - 0.5) * 600); y = (rand() - 0.5) * 4; }
  else { x = 1 + (rand() - 0.5) * 1e-6; y = (rand() - 0.5) * 1e9; }
  lines.push(`Pow ${bits(x)} ${bits(y)} ${bits(Math.pow(x, y))}`);
}
for (const x of specials) for (const y of specials) {
  if (Number.isNaN(y)) continue;
  if (Math.abs(x) === 1 && !Number.isFinite(y)) continue;
  lines.push(`Pow ${bits(x)} ${bits(y)} ${bits(Math.pow(x, y))}`);
  lines.push(`Atan2 ${bits(x)} ${bits(y)} ${bits(Math.atan2(x, y))}`);
}
for (let i = 0; i < 3000; i++) {
  const y = (rand() - 0.5) * 20, x = (rand() - 0.5) * 20;
  lines.push(`Atan2 ${bits(y)} ${bits(x)} ${bits(Math.atan2(y, x))}`);
}
console.log(`# V8 ${process.versions.v8}, node ${process.version}`);
console.log(lines.join('\n'));
