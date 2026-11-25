# Notes on this capture (not part of the hashed record)

- **Comparator:** registered at `8d29301a` (digest `3e834bcc`), with ADR-033's parity on every gated path and Tomcat's keep-alive limit of 100 requests per connection (decision 7, owner 8163a833). 109/109 in the `parity` wire mode, census current (Go 0 divergences). The capture's harness is `60d514f3`.
- **Window:** claimed, 04:39–05:20Z on 2026-11-25, no foreign activity, nothing frozen.
- **Fingerprint:** current under the database protocol: PostgreSQL 18.7 binary, VACUUM ANALYZE after readiness, fixture row counts.
- **The record B4's Flint-only runs use for petclinic-rest.** It supersedes `20261125T023246Z` (parity, no keep-alive limit) and `20261124T092019Z` (pre-ADR-033).
- **What the keep-alive limit cost Go**, against `20261125T023246Z`:
  - owner GET: 19,700 against 19,940 req/s (−1.2%), p99 559 against 547 µs;
  - validation 400: unchanged within noise (p99 213 against 209 µs), since every 400 already closes.
