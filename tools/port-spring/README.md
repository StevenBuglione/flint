# Mechanical Spring translator

`flint port-spring` generates a D source candidate and an API mapping fragment for a pinned Java declaration. The owning port lane reviews both files before applying them. The translator matches declarations to `flint api extract` manifests and uses rulebook v2.

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

This slice supports public top-level annotations with primitive, string and class-token fields, scalar and array defaults in the supported literal forms, and explicit JDK meta-annotation imports. It moves `value` first, uses `ClassRef` for Java class tokens under R4, and applies R19 to D keyword names. The CLI reports Java `@Inherited` for AOT review. Unsupported types, default expressions and annotation metadata produce a diagnostic before any candidate is written. The slice accepts Apache, MIT and BSD source ports covered by the licence matrix. EPL source translation requires destination-package support.

A custom meta-annotation with no attributes can become a D UDA on the struct. Its exact mapped symbol must already be in the destination D module. The CLI checks the Java import scope and declaration order against the pinned manifest before emitting the markers. Custom metadata with arguments or on annotation members requires a separate translation.

Java `@Deprecated` on an annotation or attribute becomes D `deprecated` on the corresponding struct or field. The warning includes a literal `since` version, a `forRemoval = true` notice, and the replacement hint from the adjacent Javadoc `@deprecated` tag when supplied.

For a class-valued attribute, `void.class` and `X.class` with the exact declared bound `Class<? extends X>` become `ClassRef.init`. The CLI verifies the sentinel against the pinned declaration and names it in the proposed R2/R4 mapping note. Other class literals require a separate translation.

An annotation can use an enum that already maps to its destination D module. The CLI checks the field type and each default against the pinned manifest and uses the exact mapped D symbols for the enum and constants. It resolves fully qualified names, explicit Java type and static imports, and unambiguous on-demand imports from known manifest scopes. R15 enums require a separate translation.

Nested annotation fields and arrays use the same reference lookup and require an exact R2 mapping to the destination module. A zero-argument default uses the nested struct's `.init` when every Java attribute has a default. A single enum constant supplied as `@Nested(CONSTANT)` or `@Nested(value = CONSTANT)` initializes the mapped first field when every other attribute has a default. The CLI resolves the field type using the nested declaration's imports and the constant using the imports at the use site. A required array field uses D's default initialization, and an explicit Java empty array uses `[]`.

Public top-level enums keep Java constant order. The R20 method slice recognizes one public instance method that checks an enum argument with Spring's `Assert.notNull` and returns the lesser ordinal through a conditional expression. It emits a same-module UFCS function. D rejects a null argument at compile time under R5 and R20. Constants with arguments or class bodies, other method bodies, fields and implemented interfaces require separate translations.

The R8 exception slice accepts a public subclass of Spring's `TransactionUsageException` with one public `String` constructor whose body is exactly `super(message)`. The CLI checks the base class and its constructors against the pinned manifest and existing mapping. It emits a D constructor in `flint.transaction` that preserves the message and caller location. A checked `@SuppressWarnings("serial")` has no effect on the D declaration. Other exception hierarchies and constructor shapes require separate translations.

The R3 marker interface recipe accepts a public top-level interface with an empty body and one parent, Spring's `Ordered`. The CLI resolves the parent through the pinned manifest and requires the exact ported mapping to `flint.core.Ordered`. A DMD and LDC golden verifies that the mapped parent is a D interface and that the generated subtype preserves inheritance.

## Verification

`test_annotations.py` exercises the C helper and compiles the emitted UDA with DMD and LDC. `test_jakarta.py` walks every Jakarta Persistence annotation in the pinned manifest, compares generated fields and mappings to the existing hand port where available, checks the emitted headers, and compiles every generated D file on both compilers.

`test_spring_markers.py` translates Spring Framework's `Component` and compares the marker and field with the hand port. It checks the extracted AOT models and runs a direct and transitive lookup with both compilers.

`test_boot_enum_method.py` translates Actuator's `Access.cap` and compares every pair of enum values with the hand port. It checks the R20 mapping and pins rejection of `cap(null)` at compile time on DMD and LDC.

`test_exceptions.py` exercises the native constructor checks. `test_spring_exception.py` compares Spring's `InvalidIsolationLevelException` with the hand port and exercises the generated class hierarchy, cause, message, and caller location on DMD and LDC.

`test_interface.py` exercises the native marker interface checks. `test_spring_interface.py` compares Spring's `PriorityOrdered` with the hand port and tests implementing it and upcasting to `Ordered` on DMD and LDC.

```sh
python3 tools/port-spring/tests/test_annotations.py
python3 tools/port-spring/tests/test_enum.py
python3 tools/port-spring/tests/test_exceptions.py
python3 tools/port-spring/tests/test_interface.py
python3 tools/port-spring/tests/test_jakarta.py --flint /path/to/flint \
  --helper .flint/port-spring/flint-port-spring --cache .flint/cache/api
python3 tools/port-spring/tests/test_jakarta_enums.py --flint /path/to/flint \
  --helper .flint/port-spring/flint-port-spring --cache .flint/cache/api
python3 tools/port-spring/tests/test_spring_markers.py --flint /path/to/flint \
  --helper .flint/port-spring/flint-port-spring --cache .flint/cache/api
python3 tools/port-spring/tests/test_boot_enum_method.py --flint /path/to/flint \
  --helper .flint/port-spring/flint-port-spring --cache .flint/cache/api
python3 tools/port-spring/tests/test_spring_exception.py --flint /path/to/flint \
  --helper .flint/port-spring/flint-port-spring --cache .flint/cache/api
python3 tools/port-spring/tests/test_spring_interface.py --flint /path/to/flint \
  --helper .flint/port-spring/flint-port-spring --cache .flint/cache/api
```

On venus, run each build and test under the shared measurement hold.
