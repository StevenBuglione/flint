# Flint test support

`expect(value).toEqual(expected)` uses D equality and reports the caller's file and line on a mismatch. Boolean values also support `toBeTrue` and `toBeFalse`.

`Mock!Interface` generates one implementation for each supported interface. Configure calls with `returns!(Interface.method)(value)` or `expects!(Interface.method)()` for a void result. For overloaded names, use `MockMethod!(Interface, "name", index)` as the alias passed to `returns` or `expects`. The index comes from D's `__traits(getOverloads, Interface, "name")` tuple. Strict-mode violations are recorded for `verify()`, including calls through `nothrow @nogc` methods. `reset()` clears the log and expectations. Keep the facade alive while its interface is in use on the creating thread.

`runTests` takes an explicit module list. Modules run in lexicographic order and their tests run in declaration order. String UDAs provide labels and unlabeled tests receive ordinal names. The runner seeds D's thread-local random generator for the run, then restores it. It reports fluent assertion failures and exceptions separately. Fatal D errors propagate according to druntime behavior.

Compile the calling program with `-unittest`. A DUB application can select `subConfiguration "flint:test" "runner"` to link the runner. Install an explicit druntime handler in the test executable before calling `runTests` from `main`, as in [the runner fixture](fixtures/run.d). `TestOptions.allowEmpty` controls whether a selection of zero tests succeeds. A report uses exclusive creation to prevent parallel shards from replacing one another's results.

```sh
dub test :test --compiler=dmd
dub test :test --compiler=ldc2
python3 packages/test/fixtures/verify_runner.py --compiler dmd
python3 packages/test/fixtures/verify_runner.py --compiler ldc2
python3 tools/gates.py --package test --gate structural
```

The feature and control benchmarks dispatch all methods in interfaces with 1, 16 and 64 methods and run 64 individually compiled test modules. Both check the observed checksum `93737` before returning success.
