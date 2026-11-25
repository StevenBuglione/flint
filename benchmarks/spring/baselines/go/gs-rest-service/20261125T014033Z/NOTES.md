# Notes on this capture (not part of the hashed record)

- **Comparator:** the ADR-033 parity comparator registered at `075b4715` (digest `b5ef797c`). It matches the golden's reason phrase, framing and connection lifetime on every gated path, and passes the suite 18/18 in the `parity` wire mode. The capture's harness is `406199ae`.
- **Window:** claimed, 01:40–02:22Z on 2026-11-25, no foreign activity; one stray callgrind frozen and continued.
- **Fingerprint:** current under the database protocol (gs-rest uses no database: postgres and database_protocol are null by design).
- **Supersedes** `20261124T082805Z`, which was against the pre-ADR-033 comparator and is stale under main's fingerprint.
- **Keep-alive limit (owner decision 8163a833):** this record predates the 100-request keep-alive limit on both sides. It stays valid until the Flint and Go changes land together, after which the baseline is captured once more.
