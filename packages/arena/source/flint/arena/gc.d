/++
Flint's garbage collector (ADR-030 section 4, owner decision b515505b).

Importing this module links the collector into the program, registered with druntime under the name `flint`.
druntime still starts its own collector unless the program selects this one, either at run time with
`--DRT-gcopt=gc:flint` or in the binary with `extern (C) __gshared string[] rt_options = ["gcopt=gc:flint"];`.
Selecting `gc:conservative` switches back.

The collector lives in `flint.arena.sys.gc`. It starts as a port of druntime's conservative collector, which
behaves the same. Per-thread allocation caches and page release follow as separately measured steps
(docs/spring/phase1/gc.md). This module is not part of the BetterC surface of `flint.arena`, which never imports it.
+/
module flint.arena.gc;

@safe:

static import flint.arena.sys.gc.collector;

/// The name to select with `--DRT-gcopt=gc:<name>` or `rt_options`.
enum collectorName = "flint";
