# Comparator baselines and the drift guard

A baseline record (`go/<app>/<stamp>/record.json`, written by `tools/spring_baseline.py capture`) holds the Go comparator's production series for an application's HTTP and error workloads. Owner decision c015f307: Flint-only runs (`load_bench.py --baseline <record>`) use these series in place of interleaved Go trials. Each such run checks the runner with a **drift guard** before and after: one Go calibration trial and a five-sample probe. If either guard is out of band, the run is not evidence, and `measure_queue.py` switches the part to interleaved for its next claim (`drift_fallback`).

## Current records

| App | Record | Comparator | Notes |
|---|---|---|---|
| gs-rest-service | `go/gs-rest-service/20261125T034727Z` | `8d29301a` (ADR-033 parity and Tomcat's keep-alive limit) | used from B4 |
| petclinic-rest | `go/petclinic-rest/20261125T043938Z` | `8d29301a` | used from B4 |

Earlier records stay as history. Each record's `NOTES.md` explains why it was superseded.

## Guard bands

The rule (coordinator, 2026-11-25): **per metric, the guard uses the wider of two bands, centred on the record's own calibration mean.**
- The record's own 99% prediction band from its five calibration samples.
- The cross-session band: a relative half-width from `guard-bands.json`.

The cross-session band comes from eight calibration sessions per app, spread across 2026-11-24 18:30Z to 2026-11-25 09:07Z at 2-hourly slots. Each session ran three Go calibration trials and a probe. The source rows are `calibration-sessions/<app>.jsonl`.

The half-width is a 99% prediction interval for one new trial, from the pooled trials of all sessions, with a robust spread: 1.4826 × the median absolute deviation relative to the median, with t(0.995, n − 1). A single disturbed trial therefore cannot widen the band. Trials known to be disturbed are also excluded explicitly (below).

`spring_baseline.py bands` recomputes `guard-bands.json` from the committed session logs and exclusions.

| Relative half-width | gs-rest-service (23 trials) | petclinic-rest (24 trials) |
|---|---|---|
| requests/s | 1.09% | 1.35% |
| p50 | 5.21% | 3.05% |
| p99 | 17.9% | 9.07% |
| CPU per request | 2.60% | 1.30% |
| probe CPU seconds | 1.73% | 2.38% |
| probe memory seconds | 8.79% | 19.5% |

The sessions ran against the comparators of their harness (`45e8b765`, before ADR-033). The bands are relative spreads of the runner, so they apply around each record's own mean. They take effect for runs whose tree contains this change (B5 onward); B4's trees use the record-only bands.

### Excluded trial

`calibration-sessions/excluded.json` holds the full evidence. Only one trial is excluded: **gs-rest-service session 5, trial 1 (2026-11-25 03:25:38Z)**, classified as *anomalous, cause not identified*.
- **The trial:** throughput −5.7%, p50 +39.7%, p99 +51.3% and CPU +37.2% against the median of the other 23 gs-rest trials. All 23 lie within throughput 250.8–255.2k req/s and CPU 8.10–8.65 µs.
- **The window was clean:**
  - claimed window, 03:24:07–03:25:40Z;
  - the receipt counts as evidence, with 0 foreign samples and no busy process in any 10 s sample;
  - load 1.6–1.9, nothing frozen;
  - proof-harness's own held work had ended by 03:14:43Z.

No cause was found, so the trial is marked rather than explained.

## Drift-fallback rate per part

Every Flint-only runtime attempt so far, judged as recorded, and re-judged under the bands above, from the same guard readings:

| Attempt (results stamp) | Part | Record | Guard before / after, as run | Under the new bands |
|---|---|---|---|---|
| 20261124T100713Z (B2) | phase1-http-gs-rest | 20261124T082805Z | fail / fail | fail / fail |
| 20261124T100734Z (B2) | phase1-http-petclinic | 20261124T092019Z | fail / fail | fail / fail |
| 20261124T101248Z (B2) | phase1-http-petclinic | 20261124T092019Z | fail / fail | fail / fail |
| 20261124T112529Z (B2) | phase1-http-gs-rest | 20261124T082805Z | pass / pass | pass / pass |
| 20261124T134943Z (B2) | error-404-p99 | 20261124T082805Z | fail / fail | pass / fail (probe memory) |
| 20261125T063921Z (B4) | phase1-http-petclinic | 20261125T043938Z | pass / fail (Go CPU +1.9%) | pass / fail |
| 20261125T082302Z (B4) | phase1-http-gs-rest | 20261125T034727Z | fail / fail | pass / fail (throughput 0.05% below the band) |

Results:
- **As run, 1 of 7 Flint-only attempts held both guards** (phase1-http-gs-rest at B2). **Under the new bands it is still 1 of 7.**
- By part: gs-rest HTTP 1 of 3, petclinic HTTP 0 of 3, the 404 path 0 of 1. The validation path has not run Flint-only yet.
- **What the misses are:**
  - The B2 misses are large: gs-rest calibration at 160k against about 250k req/s.
  - The B4 petclinic miss is a real drift. The interleaved re-run measured Go's CPU 1.6% above the record, against a session spread of ±1.3%.
  - The B4 gs-rest miss is marginal.
- **What it means:** Go on venus moves by 1–2% between hours, about as much as the sessions' spread. A Flint-only part therefore usually falls back to an interleaved run, and costs its own window plus the interleaved one. **Flint-only has so far saved no runtime window.**

Two options, for the owner:
1. Run the gated runtime parts interleaved from the start, and keep Flint-only for diagnostics.
2. Keep Flint-only and accept that most parts need two windows.

Widening the bands further would weaken the guard, which is the owner's call.
