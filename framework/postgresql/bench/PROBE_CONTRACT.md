# flint:postgresql probe

The fixture constructs `flint.postgresql.Driver`, which enables the engine's PostgreSQL driver, and asks it whether it accepts a URL. It prints `accepted` with no arguments (a `jdbc:postgresql:` URL) and `rejected` with one (`jdbc:sqlite::memory:`). It opens no database.

The baseline in `baseline/` declares the module's direct dependencies (flint:engine-jdbc, flint:java), but not the module. It prints the same line without the module: the operation is omitted, as packages' PROBE_CONTRACT.md allows.

`tools/measure_builds.py` takes the larger O3/Oz stripped-size difference as the module's `incremental_linked_bytes`. Because the driver is the only reference to the engine driver's native code (performance playbook S-1), that difference is what declaring the dependency adds to an application: the PostgreSQL driver and its native library. Template instances count the compiler invocations that compile `framework/postgresql`, the probe included. The budget is in `policy/framework.json` (`tools/framework_budgets.py`).
