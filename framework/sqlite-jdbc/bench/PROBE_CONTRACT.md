# flint:sqlite-jdbc probe

The fixture constructs `flint.sqlite.JDBC`, which enables the engine's SQLite driver, and asks it whether it accepts a URL. It prints `accepted` with no arguments (a `jdbc:sqlite:` URL) and `rejected` with one (`jdbc:postgresql://db/app`). It opens no database.

The baseline in `baseline/` declares the module's direct dependencies (flint:engine-jdbc, flint:java), but not the module. It prints the same line without the module: the operation is omitted, as packages' PROBE_CONTRACT.md allows.

`tools/measure_builds.py` takes the larger O3/Oz stripped-size difference as the module's `incremental_linked_bytes`. Because the driver is the only reference to the engine driver's native code (performance playbook S-1), that difference is what declaring the dependency adds to an application: the SQLite driver and its native library. Template instances count the compiler invocations that compile `framework/sqlite-jdbc`, the probe included. The budget is in `policy/framework.json` (`tools/framework_budgets.py`).
