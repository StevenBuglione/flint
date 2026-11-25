# Notes on this capture (not part of the hashed record)

- **Comparator:** the ADR-033 parity comparator registered at `075b4715` (digest `c5858a2a`), 109/109 in the `parity` wire mode, with its census current. The capture's harness is `406199ae`.
- **Window:** claimed, 02:32–03:14Z on 2026-11-25, no foreign activity.
- **Fingerprint:** current under the database protocol (PostgreSQL 18.7 binary and VACUUM ANALYZE recorded).
- **Superseded by the keep-alive limit (owner 8163a833).** Flint's engine change (c116cf36) and the Go change (registered at `8d29301a`, 60d514f3) landed after this capture. The record is kept as history; go-baseline-petclinic-rest-3 captures the comparator with the limit. The gs-rest record `20261125T014033Z` is superseded the same way.
