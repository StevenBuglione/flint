# gs-relational-data-access, ported to Flint

This is the Flint side of the gs-relational-data-access side-by-side application (`benchmarks/spring/README.md`): the guide's `complete/` project (commit `39ee641`) as a Flint Boot application. `RelationalDataAccessApplication` (a `CommandLineRunner` taking the auto-configured `JdbcTemplate`) and `Customer` are in `src/com/example/relationaldataaccess/package.d`, one module for the guide's one Java package (rulebook R1), with `flint.toml`'s `base-package` keeping Spring's package.

The database is SQLite in memory, the embedded engine Flint's JDBC driver ships, as for the Go comparator: `DataSourceAutoConfiguration` gives `jdbc:sqlite:file:<unique name>?mode=memory&cache=shared`. The one change from the guide is SQLite's `id INTEGER PRIMARY KEY` for H2's `id SERIAL`.

## Build and score

```bash
flint build --profile release
python3 tools/spring_bench.py accept gs-relational-data-access --start '<binary>'
```

The SQL engine needs the pinned SQLite and Flint's SQL shim: `tools/native_build.py --phase build --emit-dub` writes their blocks into the engine's `dub.sdl`.

## Status

1/1 in exact mode (2026-11-23, the DMD dev build and the LDC release build).
