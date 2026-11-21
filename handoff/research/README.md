# Research evidence index

Research cut: **21 November 2026**. The technical synthesis is [RESEARCH_REPORT.md](../docs/RESEARCH_REPORT.md); architecture decisions are in [the ADR directory](../docs/adrs/). Findings distinguish upstream capabilities, observed local checks, and Flint design decisions.

| Evidence | Scope |
|---|---|
| [Core source ledger](core-sources.md) | D safety/lifetimes, GC, compiler behavior, DUB, and the D ecosystem audit |
| [Service source ledger](service-sources.md) and [machine-readable records](service-sources.json) | HTTP, SQL, security, AI/MCP, cloud protocols, and CI/load tooling |
| [FFI, terminal and WASM sources](ffi-sources.md) | Terminal and browser APIs, WASI components, native runtimes and C dependencies |
| [Native source lock](c-libraries.json) | 24 exact versions/revisions, source archive URLs and SHA256 digests, license identities and integration metadata |
| [Toolchain release evidence](tooling-lock-evidence.json) | Official release/API identities used for compiler, Go, Actions and helper pins |
| [License notices](licenses/) | Texts obtained for the locked native sources; optional subcomponents retain their separate terms |
| [Preparation verification](../verification/VERIFICATION_REPORT.md) | Executed compiler, native ABI, sanitizer, JavaScript, Go, and governance checks |

The native source lock is byte-for-byte equivalent as JSON to `scaffold/policy/native-lock.json`. Downloaded source archives were hashed after retrieval from their recorded official HTTPS locations. Those observed hashes identify the inspected artifacts; they do not constitute independent signature verification or a security audit of every transitive dependency. Native builds must preserve upstream notices and record the actual enabled feature and linked-library closure.

The included `golden-rest-service-sample.d` is a compile-checked API usage reference. The runnable application template is under `templates/golden-rest-service`; both depend on implementing the specified Flint packages.
