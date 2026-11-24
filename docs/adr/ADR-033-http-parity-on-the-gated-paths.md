# ADR-033: HTTP parity on the gated error paths

Status: **accepted** on 2026-11-24 by the owner (decisions.md 118b4482: "Yes, your recommendation"). Drafted by proof-harness from action 1 and the fairness verdict of Astra's error-path review (`docs/spring/phase1/error-paths-astra.md`). AGENTS.md requires a comparator change to have its own reviewed ADR and a remeasurement of both sides; this is that ADR.

## Context

The black-box suite registers the Go comparators in `semantic` wire mode (`benchmarks/spring/README.md`, "Wire modes"). That mode ignores:

- the reason phrase;
- JSON key order and compactness;
- the framing headers `Content-Length`, `Transfer-Encoding`, `Connection` and `Keep-Alive`.

The README's reason, "forcing Go to emit chunked framing would only slow Go down and flatter Flint", covers the bytes of a message but not the lifetime of the connection. On the validation path the Java reference closes the connection after every 400. Flint reproduces that (`packages/engine-web/source/flint/engine/web/runtime.d`), because the exact mode it must pass records `Connection: close`. The Go comparator keeps the connection. So under load every Java or Flint 400 costs a teardown, a connect and an accept that Go never pays. No check could see the difference:

- the suite's probes, and load_bench's correctness probes, send `Connection: close`;
- the timed stream checks status counts, transport errors and body bytes, not connections.

The Java golden records reason, framing and lifetime for every case. On the gated error paths (`policy/spring-error-paths-benchmark.json`):

| Gated workload | Java (golden) and Flint | Go comparator before this ADR |
|---|---|---|
| gs-rest `GET /nope`, `Accept: */*` (error-404-p99) | `404 `, `Transfer-Encoding: chunked`, kept | `404 Not Found`, `Content-Length: 89`, kept |
| petclinic invalid `POST /petclinic/api/owners` (error-validation-p99) | `400 `, chunked, `Connection: close` and closed | `400 Bad Request`, `Content-Length`, kept |

### The price of the transport difference

The price is measured by `tools/spring_transport.py`, queue entry `transport-pricing`. It is a diagnostic, never evidence, run at B3 against the comparators as they were.

1. **Raw exchange.** One request with no `Connection` header on a fresh socket, for Java, Flint, Go and the Go variants. The tool keeps the response bytes and checks whether a second request is answered on the same socket.
2. **Load.** At the workload's fixed rate, then at capacity:
   - the comparator as it was (`go`, the idiomatic comparison);
   - a scratch copy with chunked framing (`go-chunked`);
   - for the 400 only, chunked framing with close-after-400 (`go-chunked-close`).

   It runs Flint and Java once each for context, and counts accepted connections per completed request from the kernel's TCP `PassiveOpens`.

The same run prices petclinic's owner GET. The Java golden sends it chunked and Go does not; see Consequences.

**Results: added when the entry reports.**

## Decision

1. **The rule.** On every gated error path, each comparator matches the Java golden in three things, on top of everything `semantic` already checks:
   - **the reason phrase.** Tomcat sends none.
   - **the message framing**: `Content-Length` or `Transfer-Encoding: chunked`.
   - **the connection lifetime**: `Connection: close` and an actual close, or neither and the connection reused.
2. **What stays free:**
   - how the bytes are produced: write coalescing, the number of writes and chunk boundaries;
   - internal dispatch;
   - caching that Java's semantics allow;
   - the order of distinct header names, JSON key order, and the body's trailing newline. `semantic` already permits these, and the load check accepts gs-rest's 88–89 body bytes.
3. **The Go change, and only it.** Nothing goes beyond Java.
   - gs-rest-service:
     - Boot's JSON 404 goes out chunked;
     - its 404 status line has no reason phrase. Java's whitelabel HTML 404 has none either.
   - petclinic-rest:
     - every 400 the comparator writes is chunked and closes its connection, as Tomcat's are in all of the golden's 400 cases;
     - the 400 status line has no reason phrase.
   - **How the reason phrase is dropped.** `net/http` always writes the status text, so each comparator wraps its listener. The wrapped connection drops the text from the status line of the gated status as it is written (`parity.go`). `net/http` flushes at the end of each response, so a status line always starts a write.
   - Every other response is unchanged.
4. **Enforcement.** This works like ADR-032's census.
   - `spring_transport.py parity --app <app> --record` runs the comparator of the checkout and makes the raw exchange of each of the app's gated workloads three times. It compares reason, framing and lifetime with the golden's cases for the same method, path, status and media type, and writes `benchmarks/spring/parity/<app>.json`.
   - `spring_bench.py register` refuses a comparator without a clean record of its current source and the current golden, covering every gated path.
   - `check-registry` refuses the same, and a record changed since registration. Every measuring tool enforces `check-registry`.
   - `register --adr <ADR>` is required to change a comparator that has already been measured, and records the ADR.
   - Flint is held to the same three things by `exact` mode. `spring_transport.py parity --impl flint` checks them the same way, without a record.
5. **Re-registration and remeasurement.** Both comparators are registered again with new digests and parity records. petclinic-rest also gets a new SQL census, since ADR-032 ties the census to the digest. Then:
   - the Go baselines of the two error paths are captured again;
   - error-404-p99 and error-validation-p99 are measured again against them, both sides at the next baseline commit.

   B2's and B3's error-path results stay as history against the old comparator; assembly already refuses mixed commits.
6. **Idiomatic Go stays visible.** The comparator as it was remains in `transport-pricing` as the labelled `go` arm, the price of parity. It is never gated.

## Consequences

- **The validation path.** The gated Go comparator now pays about one connect and one accept per request, as Java and Flint already do. Its p99 and CPU per request move by the measured price, and so does the bar Flint must beat (≤ 0.99× that p99).
- **The 404 path** changes only in framing and the reason phrase. The 404 CPU gap stays Flint's to close (review action 3).
- **petclinic's owner GET (phase1-http-petclinic).** The Java golden sends it chunked and Go sends `Content-Length`. The owner's decision covers the error paths only, so the owner GET is unchanged. Its price is in `transport-pricing` for the owner to decide on separately.
- **The README.** The wire-mode section gains the parity rule for the gated error paths. `semantic` still governs every other case.
- **Flint's close-on-400 stays.** It is the reference's behaviour, and exact mode requires it.
