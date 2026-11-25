# Notes on this capture (not part of the hashed record)

- **Comparator:** registered at `8d29301a` (digest `207b8ac1`), with ADR-033's parity on every gated path and Tomcat's keep-alive limit of 100 requests per connection (decision 7, owner 8163a833). 18/18 in the `parity` wire mode. The capture's harness is `60d514f3`.
- **Window:** claimed, 03:47–04:29Z on 2026-11-25, no foreign activity; one stray callgrind frozen and continued.
- **The record B4's Flint-only runs use for gs-rest-service.** It supersedes `20261125T014033Z` (parity, no keep-alive limit) and `20261124T082805Z` (pre-ADR-033).
- **What the keep-alive limit cost Go**, against `20261125T014033Z`:
  - `/greeting`: 240,000 against 250,600 req/s (−4.2%), p99 285 against 254 µs, CPU 8.59 against 8.26 µs;
  - 404: 227,200 against 237,900 req/s, p99 130 against 109 µs.

  Flint pays the same reconnect once per 100 requests.
