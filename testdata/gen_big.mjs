// Writes big.txt: operations on random big integers and node's BigInt
// results, for cmd/test-big (hex operands, hex result).
//
//     node testdata/gen_big.mjs > testdata/big.txt
let seed = 99n;
const next = () => { seed = (seed * 6364136223846793005n + 1442695040888963407n) & 0xFFFFFFFFFFFFFFFFn; return seed; };
function rnd() {
  const limbs = Number(next() % 9n);
  let v = 0n;
  for (let i = 0; i < limbs; i++) v = (v << 32n) | (next() >> 32n);
  if (next() % 5n === 0n) v = v >> BigInt(Number(next() % 60n));
  return next() % 2n ? -v : v;
}
const hex = (v) => (v < 0n ? '-' + (-v).toString(16) : v.toString(16));
const out = [];
for (let i = 0; i < 3000; i++) {
  const a = rnd(), b = rnd();
  out.push(`add ${hex(a)} ${hex(b)} ${hex(a + b)}`);
  out.push(`sub ${hex(a)} ${hex(b)} ${hex(a - b)}`);
  out.push(`mul ${hex(a)} ${hex(b)} ${hex(a * b)}`);
  if (b !== 0n) {
    out.push(`quo ${hex(a)} ${hex(b)} ${hex(a / b)}`);
    out.push(`rem ${hex(a)} ${hex(b)} ${hex(a % b)}`);
  }
  out.push(`and ${hex(a)} ${hex(b)} ${hex(a & b)}`);
  out.push(`or ${hex(a)} ${hex(b)} ${hex(a | b)}`);
  out.push(`xor ${hex(a)} ${hex(b)} ${hex(a ^ b)}`);
  const s = BigInt(Number(next() % 200n));
  out.push(`shl ${hex(a)} ${hex(s)} ${hex(a << s)}`);
  out.push(`shr ${hex(a)} ${hex(s)} ${hex(a >> s)}`);
  const bits = Number(next() % 130n);
  out.push(`uint ${hex(a)} ${hex(BigInt(bits))} ${hex(BigInt.asUintN(bits, a))}`);
  out.push(`int ${hex(a)} ${hex(BigInt(bits))} ${hex(BigInt.asIntN(bits, a))}`);
  const radix = 2 + Number(next() % 35n);
  out.push(`str ${hex(a)} ${radix.toString(16)} ${a.toString(radix)}`);
  out.push(`float ${hex(a)} 0 ${new DataView(new Float64Array([Number(a)]).buffer).getBigUint64(0, true).toString(16)}`);
  if (i % 10 === 0) {
    const e = BigInt(Number(next() % 40n));
    const small = a >> 200n;
    out.push(`pow ${hex(small)} ${hex(e)} ${hex(small ** e)}`);
  }
}
console.log(out.join('\n'));
