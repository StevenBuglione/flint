# bench-cli

The canonical CLI workload loads the supplied JSON greeting configuration, parses a typed `--name` option, prints the greeting and emits one structured JSON log record. It uses the same public API as the golden CLI, with JSON configuration and logging to match `examples/reference-go-cli`.

Build from this directory after the required package implementations exist:

```sh
dub build --compiler=dmd
dub build --compiler=ldc2 --build=release
../../build/bench-cli --name Steve
```

`flint:config` discovers `application.json` when no `application.toml` exists. Run the binary from this directory so both the D and Go workloads read the same configuration. Compile and release-size measurements are produced by `tools/measure_builds.py`, with explicit DMD, O3 and Oz profiles; a default DUB release build alone is not the performance gate. The root benchmark policy fixes source files, edited-source inputs and nine measurements per group.
