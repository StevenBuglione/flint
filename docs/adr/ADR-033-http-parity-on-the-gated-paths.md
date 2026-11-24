# ADR-033: HTTP parity on the gated paths

Status: **accepted** by the owner on 2026-11-24, in two steps:
- 118b4482: parity for the gated error paths ("Yes, your recommendation");
- 081851b0: parity extended to every gated path ("Yes, all gated paths").

Drafted by proof-harness from action 1 and the fairness verdict of Astra's error-path review (`docs/spring/phase1/error-paths-astra.md`). AGENTS.md requires a comparator change to have its own reviewed ADR and a remeasurement of both sides; this is that ADR.

## Context

The black-box suite used to register the Go comparators in `semantic` wire mode (`benchmarks/spring/README.md`, "Wire modes"). That mode ignores:
- the reason phrase;
- JSON key order and compactness;
- the framing headers `Content-Length`, `Transfer-Encoding`, `Connection` and `Keep-Alive`.

Its reason, "forcing Go to emit chunked framing would only slow Go down and flatter Flint", covers the bytes of a message, not the lifetime of the connection.

On the validation path, the Java reference closes the connection after every 400. Flint reproduces that (`packages/engine-web/source/flint/engine/web/runtime.d`), because the exact mode it must pass records `Connection: close`. The Go comparator kept the connection. So under load, every Java or Flint 400 cost a teardown, a connect and an accept that Go never paid. No check could see this:
- load_bench's correctness probes send `Connection: close`;
- the timed stream checks status counts, transport errors and body bytes, not connections.

The Java golden records reason, framing and lifetime for every case. On the timed workloads:

| Timed workload | Java (golden) and Flint | Go comparator before this ADR |
|---|---|---|
| gs-rest `GET /greeting` (phase1-http) | `200 `, `Content-Length`, kept | `200 OK`, `Content-Length`, kept |
| petclinic `GET /petclinic/api/owners/{id}` (phase1-http) | `200 `, `Transfer-Encoding: chunked`, kept | `200 OK`, `Content-Length`, kept |
| gs-rest `GET /nope`, `Accept: */*` (error-404-p99) | `404 `, chunked, kept | `404 Not Found`, `Content-Length: 89`, kept |
| petclinic invalid `POST /petclinic/api/owners` (error-validation-p99) | `400 `, chunked, `Connection: close` and closed | `400 Bad Request`, `Content-Length`, kept |

Across the suite's other cases, the reference behaves the same way:
- Tomcat sends no reason phrase;
- it streams Spring MVC's JSON chunked; the actuator's link index is the exception, with `Content-Length`;
- it closes after every 400 and every 500;
- it frames bodiless and whole responses with `Content-Length`.

### The price of the transport difference

The price is measured by `tools/spring_transport.py`, queue entry `transport-pricing`. It is a diagnostic, never evidence, run at B3 against the comparators as they were.

1. **Raw exchange.** For Java, Flint, Go and the Go variants, one request with no `Connection` header goes on a fresh socket. The tool keeps the response bytes and checks whether a second request is answered on the same socket.
2. **Load.** At the workload's fixed rate, then at capacity, it measures:
   - the comparator as it was (`go`, the idiomatic comparison);
   - a scratch copy with chunked framing (`go-chunked`);
   - on the 400, chunked framing with close-after-400 (`go-chunked-close`).

   It also runs Flint and Java once each for context, and counts accepted connections per completed request from the kernel's TCP `PassiveOpens`.

The workloads are the 404, the validation 400 and petclinic's owner GET.

**Results: added when the entry reports.**

## Decision

1. **The rule.** On every gated path, each comparator matches the Java golden in three things, on top of everything `semantic` checks:
   - the reason phrase;
   - the message framing: `Transfer-Encoding`, and whether `Content-Length` is present;
   - the connection lifetime: `Connection: close` and an actual close, or neither and the connection reused.

   A gated path is every request a timed workload sends, plus every request the black-box suite scores.
2. **What stays free:**
   - how the bytes are produced: write coalescing, the number of writes and chunk boundaries;
   - internal dispatch;
   - caching that Java's semantics allow;
   - the order of distinct header names, JSON key order, the body's trailing newline, and so the `Content-Length` value.
3. **The Go change, and only it.** Nothing goes beyond Java.
   - **Reason phrases.** Both comparators send none. `net/http` always writes the status text, so each comparator wraps its listener, and the wrapped connection drops the text from every status line as it is written (`parity.go`). `net/http` flushes at the end of each response, so a status line always starts a write.
   - **gs-rest-service.** Boot's JSON error body (404, 405) is chunked. `/greeting` already matched: `Content-Length`, kept.
   - **petclinic-rest.**
     - Every JSON response is chunked, as Spring MVC's converters stream it, except the actuator's link index, which keeps `Content-Length` as Tomcat sends it.
     - Every 400 and 500 closes its connection.
     - Bodiless, redirect and HTML responses were already framed as Tomcat frames them.
4. **Enforcement:**
   - **The `parity` wire mode** in `benchmarks/spring/suites/springsuite.py`. It is `semantic` plus the reason phrase, the framing, and the lifetime. Each case runs on a raw socket, followed by a harmless second request (`/flint-parity-probe`) on the same socket. A case the golden marks `Connection: close` must close; any other must answer. The Go comparators are registered and accepted in this mode (`WIRE_DEFAULT['go']`). `exact` stays the mode for Java and Flint.
   - **The parity record.** `spring_transport.py parity --app <app> --record` writes `benchmarks/spring/parity/<app>.json`. It holds the raw exchange of each timed workload's own request (three times, compared with the golden's cases for the same endpoint, method, status and media type), and the whole suite in `parity` mode.
   - **Registration.** `spring_bench.py register` and `check-registry` refuse a comparator without a clean record of its current source and the current golden. Every measuring tool enforces `check-registry`. `register --adr` is required to change a comparator that has already been measured.
5. **Re-registration and remeasurement.**
   - Both comparators are registered again, with parity records and petclinic's retaken SQL census (ADR-032 ties the census to the digest).
   - The held Go baselines (go-baseline-*-2) are captured once, against the final comparator.
   - All phase1-http and error-path parts are remeasured against them at B4.

   B2's and B3's results stay as history against the old comparator; assembly already refuses mixed commits.
6. **Idiomatic Go stays visible.** The comparator as it was remains in `transport-pricing` as the labelled `go` arm, the price of parity, and is never gated.

## Consequences

- **The validation path.** The gated Go comparator now pays about one connect and one accept per request, as Java and Flint do. Its p99 and CPU per request move by the measured price, and so does the bar Flint must beat.
- **The 404 path and petclinic's owner GET** change in framing and the reason phrase only. Their price is in `transport-pricing`.
- **The README** describes the `parity` mode. `semantic` remains available for context comparisons.
- **Flint's close-on-400 stays.** It is the reference's behaviour, and exact mode requires it.
