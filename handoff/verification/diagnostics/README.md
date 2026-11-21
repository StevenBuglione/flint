# Earlier compiler diagnostics

These receipts preserve exploratory checks made before the final supported recipes and API corrections. A nonzero exit code here may be an expected diagnostic or a superseded source revision; it is not presented as a final passing result.

- `ldc-flags.json` records the unsupported `undefined` sanitizer and the requirement for an explicit time-trace output path.
- `native_ldc.json` records the failed native internal-linker experiment. The selected native path uses the system compiler driver with LDC's bundled ThinLTO plugin.
- `wasm_link.json` records an incorrect assumption about exporting a function named `main`; the current builders export explicitly named C entry points.
- `trace.json` and `wasm-link.json` record the immediate corrected experiments. The current reproducible source/probe scripts supersede these temporary-source paths.
- `native-golden-contracts.json` records initial API-integration failures that were fixed before the final aggregate compiler run.

The authoritative final results are [the aggregate receipt](../handoff-validation.json), [toolchain capabilities](../toolchain-capabilities.json), and [the verification report](../VERIFICATION_REPORT.md). No performance baseline is derived from these diagnostics.
