# Notes on this capture (not part of the hashed record)

**Foreign processes during the capture (judged 2026-11-24, kept).** data-access left two kinds of diagnostic process running across this window, both stopped at 10:13Z:

- An `strace -f -c` of a `petclinic-pools` server, unpinned (CPUs 0–31), 08:13:22Z–10:13Z, idle after its first seconds. It used 739 CPU-seconds over 7,166 s (about 10% of one CPU, idle-loop syscalls under ptrace).
- Two idle callgrind petclinic servers pinned to CPUs 0–1, with 25 s and 7 s of CPU in total. The benchmark's CPUs are 2–3 (server), 4–7 (load) and 8–9 (database), so CPUs 0–1 are not among them.

**Judgement: no measurable effect; the capture is kept.**

- The gs-rest-service capture agrees with B's interleaved Go, measured at 02:47–03:27Z before the strace existed: 250,710 against 249,500 req/s (+0.5%), p99 261 against 260 µs.
- For petclinic-rest, the first Flint-only run's drift guard (10:13–10:34Z) found Go calibration about 6% *slower* than this capture. Contamination during the capture would have made the capture slower, not faster.

The unpinned process may have been scheduled on benchmark CPUs at times; no per-CPU accounting exists for it, so the judgement rests on the agreement above.

**Fingerprint gap.** The PostgreSQL peer is recorded as null: it is pinned by libpq's version in native-lock.json, not peer-lock.json. It is left as is through B2, so B2 stays self-consistent, and fixed at the next re-capture.
