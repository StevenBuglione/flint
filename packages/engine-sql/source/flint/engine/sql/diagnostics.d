/++
Opt-in counters that split SQL time into lease wait, lease hold, statement drive and socket wait, for diagnosing a
request path (the owner-1 diagnostic, docs/spring/phase1/throughput-plan-astra.md change 2). Set
`FLINT_DIAG_COUNTERS=<file>` before the first pool opens; at exit, and when a pool closes, the counters replace
that file as `flint.diag-counters/1` JSON. `enableSqlDiagnostics` turns them on in-process, for `sqlDiagnostics`.
Off by default, at the cost of one relaxed load per hook.
+/
module flint.engine.sql.diagnostics;

@safe:

static import flint.engine.sql.sys.diagnostics;

/// A snapshot of the counters.
alias SqlDiagnostics = flint.engine.sql.sys.diagnostics.SqlDiagnostics;

/// Turn the counters on or off for this process, overriding `FLINT_DIAG_COUNTERS`.
alias enableSqlDiagnostics = flint.engine.sql.sys.diagnostics.enableDiagnostics;

/// The counters so far.
alias sqlDiagnostics = flint.engine.sql.sys.diagnostics.diagnosticsSnapshot;

/// Zero the counters, for example between the steps of a concurrency ladder.
alias resetSqlDiagnostics = flint.engine.sql.sys.diagnostics.resetDiagnostics;
