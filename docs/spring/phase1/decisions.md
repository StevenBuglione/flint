# Phase 1 decisions log

`coordination.md` rule 4 asks for this log. When a session makes a decision that `AGENTS.md`, ADR-030, the rulebook or the AOT contract does not cover, it adds one dated line here: who decided, what, and why. If a rebase conflicts in this file, keep both lines.

## Decided

- 2026-11-23, coordinator: spring-test (`flint:framework-test`) shares the `flint.test` root by subpackage. web-http owns `flint.test.web.*` and boot owns `flint.test.context.*` (rulebook "Namespaces").
- 2026-11-23, coordinator: the four extracted repos are mirrors until the Phase 1 exit. The cutover requires an empty `policy/unregistered-packages.json`, with `framework/p1-interim` gone, plus rehearsal reports from Windows and macOS.
- 2026-11-23, coordinator: the BOM lives in `flint` next to `platform.lock`. The legacy Boot packages are renamed `flint:legacy-*` at the cutover, and the `flint` home resolves `policy/framework.json` modules as platform modules.
- 2026-11-23, coordinator: Flint's own JDBC driver is `framework/engine-jdbc` (`flint.engine.jdbc`). `TransactionInterceptor` implements `flint.engine.aot.proxy.Advisor` directly.

## Open for the owner

- (none yet)
