# Mechanical Spring translator

`flint port-spring` generates a D source candidate and an API mapping fragment for a pinned Java annotation. The owning port lane reviews both files before applying them. The translator matches declarations to `flint api extract` manifests and uses rulebook v2.

The optional C helper builds independently of the Flint CLI. CMake verifies the MIT-licensed tree-sitter runtime and generated Java grammar archives against pinned SHA-256 digests.

```sh
cmake -S tools/port-spring -B .flint/port-spring
cmake --build .flint/port-spring
flint api fetch jakarta-persistence
flint port-spring --project jakarta-persistence --tag 3.2.0 \
  --type jakarta.persistence.FieldResult --module flint.jakarta.persistence \
  --output .flint/field-result
```

The output directory must be new. It receives one D module and `mapping.json` with exact entries for deferred declarations. Identical existing ports are left alone. Changes to existing ports require `--replace-ported`, and the owning lane reviews the proposed replacements. Use `--json` to read both without creating files. Use `--helper` for a helper built at a different path and `--cache` for the same cache override used with `flint api fetch`.

This slice supports public top-level annotations with primitive, string and class-token fields, scalar and array defaults in the supported literal forms, and explicit JDK meta-annotation imports. It moves `value` first, uses `ClassRef` for Java class tokens under R4, and applies R19 to D keyword names. The CLI reports Java `@Inherited` for AOT review. Unsupported types, default expressions and custom meta-annotations produce a diagnostic before any candidate is written. The slice accepts Apache, MIT and BSD source ports covered by the licence matrix. EPL source translation requires destination-package support.

## Verification

`test_annotations.py` exercises the C helper and compiles the emitted UDA with DMD and LDC. `test_jakarta.py` walks every Jakarta Persistence annotation in the pinned manifest, compares generated fields and mappings to the existing hand port where available, checks the emitted headers, and compiles every generated D file on both compilers.

```sh
python3 tools/port-spring/tests/test_annotations.py
python3 tools/port-spring/tests/test_jakarta.py --flint /path/to/flint \
  --helper .flint/port-spring/flint-port-spring --cache .flint/cache/api
```

On venus, run each build and test under the shared measurement hold.
