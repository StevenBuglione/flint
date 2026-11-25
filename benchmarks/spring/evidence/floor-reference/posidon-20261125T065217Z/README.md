# Floor reference on posidon at B4 (diagnostic, never evidence)

The Astra petclinic CPU plan's three-arm floor (`coordination/astra-petclinic-cpu-plan.md`), run on **posidon** (i7-11700K, kernel 6.8; decisions.md 87c89356) at B4 `fb4c73d1`, 2026-11-25 06:52–06:55Z. The command is the same as the venus `floor-reference` entry: `spring_diag.py` with `--ladder 64 --fixed-rate 5000 --seconds 20 --warmup 5 --counters --syscalls 2000`.

Every arm reads owner 1 from the database on every request through ten pooled connections: 4 statements per lease, `BEGIN READ ONLY` pipelined with the first of the three SELECTs, then `COMMIT`.

**posidon's absolute numbers are not comparable with venus or the certified Go records** (a different CPU and kernel, and PostgreSQL CPUs 8–9 are siblings of cores 0–1). Only the differences between arms carry over.

| Arm | Step | req/s | p50 ms | p99 ms | App CPU µs/req | PG CPU µs/req | Lease wait µs | Lease hold µs |
|---|---|---|---|---|---|---|---|---|
| Flint (ordinary) | capacity c64 | 16,903 | 3.69 | 4.67 | 116.0 | 74.4 | 3,208 | 433 |
| Flint (ordinary) | 5,000/s | 5,000 | 0.41 | 1.95 | 119.1 | 79.6 | 24 | 331 |
| floor-minimal | capacity c64 | 18,773 | 2.79 | 11.93 | 64.4 | 81.0 | 2,647 | 404 |
| floor-minimal | 5,000/s | 5,000 | 0.29 | 3.29 | 65.0 | 84.9 | 51 | 324 |
| floor-mapped | capacity c64 | 12,257 | 3.10 | 13.89 | 76.5 | 90.0 | 4,016 | 519 |
| floor-mapped | 5,000/s | 5,000 | 0.33 | 3.52 | 74.5 | 85.6 | 78 | 372 |

The counters (wait, hold, drive, socket wait) cover each step's warm-up and measurement.

The syscall census (2,000 requests, 8 connections, untimed) gives every arm the same work per response: 5 `sendto`, 4 `recvfrom`, about 2.2 `io_uring_enter`. Fiber-park waits are 2.68 per response for Flint against 2.23–2.25 for the floor arms; the difference is futex (0.40 against 0.02). Ready-to-resume time is not observable from outside the process; these waits are its visible part.

Reading:
- **Transport and libpq floor:** about 64–65 µs of app CPU per request, the minimal arm.
- **The real mapping, DTOs and Jackson:** about +10–12 µs (mapped − minimal).
- **The Spring layers between mapped and ordinary Flint:** about +43–45 µs (Flint − mapped). These are the servlet, MVC dispatch and security filters, the transaction interceptor, and `NamedParameterJdbcTemplate`/`BeanPropertyRowMapper` over JDBC. This is the largest share.
- **PostgreSQL CPU** is about the same in every arm (74–90 µs), as are the statements per lease.

One anomaly: floor-mapped's capacity is below ordinary Flint's (12.3k against 16.9k req/s), with a longer lease hold (519 against 433 µs). This is a single 20 s step on a shared-sibling database CPU set, so treat its capacity and p99 as noisy.

The strace logs (195 MB) are not kept; `floor.json` holds their census.
