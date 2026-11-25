# Floor reference with Go on posidon at B4: the clean run (diagnostic, never evidence)

The Astra petclinic CPU plan's floor, with the **Go comparator beside it on the same machine** and floor-mapped run three times. posidon (i7-11700K, kernel 6.8), B4 `fb4c73d1`, 2026-11-25 07:08:34–07:14:13Z, with the steps of `20261125T065217Z` (`--ladder 64 --fixed-rate 5000 --seconds 20 --warmup 5 --counters --syscalls 2000`). Go is the comparator registered at `8d29301a` (parity and the keep-alive limit).

**Clean window.** The run held posidon's host-wide lock (`measure_queue.py timed`, e1b85c5d; `~/flint-work/MEASURING`). It also ran posidon's freeze-strays sweep (`freeze_strays.py`, coordinator 07:10Z):
- **frozen:** every olfa-owned compiler, test, server or tool process outside the run's own tree, swept every 2 s;
- **never frozen:** ssh, tailscale, system and remote-session servers, shells, or terminal-attached processes.

**256 processes were frozen and all 256 continued** at 07:14:14Z, with none left stopped: flint-aot 205 (232 of them dmd fork-server workers), web-http 41, m7 1, and a stray scratch PostgreSQL cluster 9. The list, with pids, is in `frozen-summary.txt` and `frozen.json`. The earlier run at 06:57Z is void: other roles were building during it.

| Arm | Step | req/s | p50 ms | p99 ms | App CPU µs/req | PG CPU µs/req | Lease wait µs | Lease hold µs |
|---|---|---|---|---|---|---|---|---|
| Go | capacity c64 | 16,855 | 2.77 | 15.68 | 83.0 | (8.0: sample broken) | – | – |
| Go | 5,000/s | 5,000 | 0.32 | 0.66 | **95.1** | 72.2 | – | – |
| Flint (ordinary) | capacity c64 | 16,838 | 3.71 | 4.67 | 116.7 | 76.5 | 3,217 | 439 |
| Flint (ordinary) | 5,000/s | 5,000 | 0.41 | 0.86 | **116.0** | 77.3 | 8 | 320 |
| floor-minimal | capacity c64 | 27,577 | 2.32 | 2.49 | 63.2 | 72.2 | 1,922 | 342 |
| floor-minimal | 5,000/s | 5,000 | 0.30 | 0.58 | **63.2** | 88.0 | 2 | 281 |
| floor-mapped ×3 | capacity c64 | 26,294 / 26,098 / 25,721 | 2.41–2.47 | 2.89–2.98 | 71.8 / 72.2 / 72.1 | 72.6–72.7 | 2,018–2,056 | 332–333 |
| floor-mapped ×3 | 5,000/s | 5,000 | 0.29–0.31 | 0.57–0.60 | **75.7 / 75.6 / 74.6** | 81.8–85.6 | 3–6 | 253–274 |

Go's PostgreSQL sample at capacity (8 µs) is a collection failure, not a measurement. Its 5,000/s sample (72 µs) matches the other arms.

Syscalls per response (untimed census):
- Go: 6 `write`, 10.8 `read`, 1 `epoll_pwait`.
- Every Flint arm: 5 `sendto`, 4 `recvfrom`, 2.2–2.5 `io_uring_enter`.
- Fiber-park waits: Flint 2.91, the floor arms 2.21–2.31; the difference is futex 0.42 against 0.01–0.05.

**Reading, at 5,000/s on one machine, app CPU against Go's 95.1 µs:**
- floor-minimal 63.2 µs = **0.66× Go**. Flint's transport (HTTP over io_uring) and libpq floor, with the same transaction and statements, is a third below Go's.
- floor-mapped about 75 µs = **0.79× Go**. Adding the real entities, DTOs and Jackson costs about 12 µs and still beats Go by about a fifth.
- ordinary Flint 116.0 µs = **1.22× Go**. The Spring layers between floor-mapped and ordinary Flint cost about 41 µs: the servlet, MVC and security filters, the transaction interceptor, and `NamedParameterJdbcTemplate`/`BeanPropertyRowMapper` over JDBC. They are what put Flint above Go.

floor-mapped's three repeats agree within 2% at capacity, which settles the noisy single step of `20261125T065217Z`.

Absolute values and the Flint/Go ratio are posidon's (Intel), not venus's (AMD). B4's voided venus trials gave Flint/Go CPU about 1.06; on posidon it is 1.22.
