// math inside kernels: every function, on every device, gives the host's
// bits exactly -- the point of writing it in Vertex rather than calling a
// device's approximate instructions.
import "gpu"
import "math"

func all(_ x: gpu.Span<float32>, _ out: gpu.MutableSpan<float32>) kernel {
    let i = gpu.Index.x
    if i >= x.count { return }
    let v = x[i]
    let n = x.count
    out[i] = math.Exp(v)
    out[n + i] = math.Log(math.Abs(v) + 1e-3)
    out[2 * n + i] = math.Sin(v)
    out[3 * n + i] = math.Cos(v)
    out[4 * n + i] = math.Tanh(v)
    out[5 * n + i] = math.Erf(v)
    out[6 * n + i] = math.Sigmoid(v)
    out[7 * n + i] = math.Exp2(v) + math.Log2(math.Abs(v) + 1) + math.Sqrt(math.Abs(v))
}

var xs: [float32] = []
var s: uint32 = 7
for _ in 0..<20000 {
    s = s &* 1664525 &+ 1013904223
    xs.append(float32(int32(bitPattern: s)) / 21474836.48)   // about ±100
}
var want: [float32] = []
for f in 0..<8 {
    for v in xs {
        switch f {
        case 0: want.append(math.Exp(v))
        case 1: want.append(math.Log(math.Abs(v) + 1e-3))
        case 2: want.append(math.Sin(v))
        case 3: want.append(math.Cos(v))
        case 4: want.append(math.Tanh(v))
        case 5: want.append(math.Erf(v))
        case 6: want.append(math.Sigmoid(v))
        default: want.append(math.Exp2(v) + math.Log2(math.Abs(v) + 1) + math.Sqrt(math.Abs(v)))
        }
    }
}
var failed = false
for d in [gpu.CPU(), gpu.Default()] {
    let x = try await d.Upload(xs)
    let out = try await d.CreateBuffer(of: float32.self, count: 8 * xs.count)
    try await all.Launch(x, out, over: xs.count)
    let got = try await out.Download()
    // A device that flushes subnormals to zero -- Apple's GPUs do, for
    // float32 -- gives zero where the host gives a subnormal, and a
    // result computed from one differs; that is the device's recorded
    // exception, counted apart. Anything else is a failure.
    var bad = 0, flushed = 0
    var first = -1
    for i in 0..<got.count where got[i].bitPattern != want[i].bitPattern && !(got[i].isNaN && want[i].isNaN) {
        if want[i].isSubnormal && got[i] == 0 {
            flushed += 1
            continue
        }
        bad += 1
        if first < 0 { first = i }
    }
    let note = flushed > 0 ? " (\(flushed) subnormal results flushed to zero)" : ""
    print(d.Name, bad == 0 ? "bit-identical to the host\(note)" : "\(bad) differ\(note), first at \(first): \(got[first]) vs \(want[first]) of \(xs[first % xs.count])")
    if bad > 0 { failed = true }
}
if failed { fatalError("a device disagrees with the host") }
