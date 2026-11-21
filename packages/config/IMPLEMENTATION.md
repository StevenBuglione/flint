# Flint startup configuration

`load!Settings` binds a struct from application files, `.env`, the process environment and command-line overrides. Use `@ConfigurationProperties("server")` for a root prefix, `@Env` for an explicit environment name and `@Default` for a text default. The default environment spelling uses uppercase keys with double underscores between levels, such as `FLINT_SERVER__PORT`.

The loader applies sources in ascending precedence from D initializers and `@Default` through the base file, matching profile file, `.env`, environment and `--set=key=value`. Select a profile with `--flint.profile=NAME`, `FLINT_PROFILE` or `ConfigOptions.profile`. Use only letters, digits, underscores and hyphens in profile names. Provide one application file format per directory. The loader accepts a UTF-8 BOM in source files and rejects duplicates within the same input layer.

`@Required` accepts explicitly supplied zero and false. Use `@Default` to declare an intentional default equal to the type initializer for a required field. All diagnostics omit supplied values, including nested `@Secret` fields. File diagnostics report source and location. File input is bounded to 1 MiB per file and the binding depth is capped at 16 levels.

The feature and direct Serde probes bind 16 fields and 128 fields across eight levels. Both verify checksum `8392`. Pass `--measure` to collect startup time and GC allocation observations for each shape.
