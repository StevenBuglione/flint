# heapSizeFactor sweep on posidon at B4 (diagnostic, never evidence)

Requested by the coordinator at 08:31Z on 2026-11-25. web-http found that `heapSizeFactor:8` takes petclinic's owner p99 from about 1,016 to 830 µs, at +9 MB RSS; the owner decides, so this is the trade-off curve.

- **Run:** posidon (i7-11700K), B4 `fb4c73d1`, 08:25–08:56Z. One `measure_queue.py timed` window per workload on posidon's host-wide lock, each with the freeze-strays sweep. 8, 5 and 6 processes were frozen. All were continued except one data-access `python3` (pid 181613), which was killed while frozen, probably by its own timeout.
- **Arms:** `--DRT-gcopt=minPoolSize:1 incPoolSize:0 heapSizeFactor:N profile:1` for N = 2 (druntime's default), 3, 4 and 8, against the registered Go comparator (`8d29301a`) in the same session.
- **Per trial:** `gc_sweep.py` runs load_bench's own trial with phases shortened to keep each hold under 20 minutes: 10 s warm-up, 30 s at the manifest's fixed rate (5,000/s owner GET and `/greeting`, 10,000/s `/nope`), 20 s at capacity. 2 interleaved trials per arm; the medians are below.
- **Measures:** CPU is at the fixed rate. Median RSS is the smaps samples of the fixed phase. Collections per 1,000 requests come from druntime's exit profile over the whole process. RSS ratios are against Go's from the same run.

```
== gs-rest-service:not-found
arm    | fixed p50/p99/p99.9 ms | cap p50/p99/p99.9 ms | cap rps | CPU us | peak RSS MB (vs Go) | median RSS MB (vs Go) | coll/1000
go     | 0.139/0.259/0.533 | 0.398/1.298/2.662 | 138663 | 22.0 | 13.8 (1.000) | 13.5 (1.000) | None
hsf2   | 0.189/0.470/0.601 | 0.941/2.019/2.704 | 66367 | 38.0 | 10.4 (0.752) | 10.0 (0.746) | 11.2
hsf3   | 0.185/0.426/0.603 | 0.862/1.888/2.531 | 70885 | 36.4 | 11.4 (0.831) | 11.2 (0.833) | 4.79
hsf4   | 0.190/0.434/0.574 | 0.864/1.896/2.544 | 70738 | 36.6 | 11.4 (0.831) | 11.3 (0.836) | 4.79
hsf8   | 0.189/0.430/0.601 | 0.846/1.861/2.496 | 72080 | 36.4 | 13.7 (0.992) | 13.4 (0.997) | 2.24
== gs-rest-service
arm    | fixed p50/p99/p99.9 ms | cap p50/p99/p99.9 ms | cap rps | CPU us | peak RSS MB (vs Go) | median RSS MB (vs Go) | coll/1000
go     | 0.162/0.469/0.859 | 0.376/1.229/1.793 | 146591 | 17.0 | 14.0 (1.000) | 13.5 (1.000) | None
hsf2   | 0.131/0.251/0.677 | 0.253/0.513/0.729 | 244093 | 11.4 | 10.4 (0.740) | 10.1 (0.752) | 0.05
hsf3   | 0.137/0.261/0.568 | 0.251/0.509/0.722 | 245574 | 11.5 | 11.3 (0.808) | 11.1 (0.826) | 0.02
hsf4   | 0.134/0.286/0.536 | 0.251/0.508/0.721 | 245938 | 11.4 | 11.5 (0.819) | 11.2 (0.835) | 0.02
hsf8   | 0.137/0.274/0.553 | 0.249/0.504/0.715 | 248039 | 11.4 | 12.5 (0.893) | 12.3 (0.914) | 0.01
== petclinic-rest
arm    | fixed p50/p99/p99.9 ms | cap p50/p99/p99.9 ms | cap rps | CPU us | peak RSS MB (vs Go) | median RSS MB (vs Go) | coll/1000
go     | 0.329/0.669/1.067 | 2.505/14.422/21.585 | 18521 | 95.4 | 28.1 (1.000) | 26.2 (1.000) | None
hsf2   | 0.420/0.881/1.220 | 3.624/4.663/5.204 | 17214 | 116.2 | 23.1 (0.822) | 19.7 (0.751) | 2.57
hsf3   | 0.407/0.822/1.143 | 3.597/4.581/4.977 | 17408 | 113.8 | 24.8 (0.881) | 20.7 (0.791) | 2.02
hsf4   | 0.420/0.827/1.201 | 3.593/4.589/5.168 | 17459 | 113.9 | 27.2 (0.967) | 22.9 (0.873) | 1.42
hsf8   | 0.417/0.780/1.143 | 3.592/4.510/5.045 | 17564 | 114.2 | 34.9 (1.239) | 29.4 (1.122) | 0.76
```

## Reading

- **petclinic owner GET.** Raising the factor halves collections or better: 2.57 to 2.02, 1.42 and 0.76 per 1,000 requests.
  - p99 at 5,000/s: 0.881, 0.822, 0.827 and 0.780 ms. That is −7% at 3, −6% at 4 and −11% at 8. p99.9 and capacity improve slightly; CPU is flat (114–116 µs).
  - RSS against Go, peak / median: factor 2 0.822 / 0.751, factor 3 0.881 / 0.791, factor 4 0.967 / 0.873, factor 8 **1.239 / 1.122**.
  - **Factor 8 would fail the RSS gate** (peak RSS 1.24× Go). Factor 4 leaves 3% of peak margin, and factor 3 leaves 12%.
- **gs-rest `/greeting`.** It allocates too little to collect (0.05 per 1,000 at factor 2), so the factor changes no latency and only adds RSS: 0.740 to 0.893 of Go's peak.
- **gs-rest `/nope`.** Collections fall from 11.2 to 4.79 (3 and 4) and 2.24 (8) per 1,000 requests.
  - p99 at 10,000/s: 0.470, 0.426, 0.434 and 0.430 ms, so −9% from factor 3 on, with little more from 8. Capacity +7–9%; CPU −4%.
  - RSS: 0.752, 0.831, 0.831 and 0.992 of Go's peak.
- **The curve is steep at first, then flat.** On both collecting paths, factor 3 buys most of the p99 gain at the smallest RSS cost: petclinic −7% at 0.881 × Go, `/nope` −9% at 0.831 × Go. Factor 8 adds little more p99 and spends the RSS margin; on petclinic it breaks the gate.
- **On posidon the p99 gain is smaller than web-http's** (−11% at factor 8 against their −18%). That is a different machine and shorter phases, so the direction agrees but not the size.

posidon's absolute values are not venus's or the certified records'. Compare the arms with each other.
