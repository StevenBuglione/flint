# ADR-023: Milestone 8 decisions — dependencies and packaging

Status: proposed by the Milestone 8 implementation, for the project owner's review. It implements the second row of [ADR-021](ADR-021-flint-platform.md)'s milestone plan: section 4, together with the parts of sections 1, 5 and 9 that it requires. It builds on [ADR-022](ADR-022-milestone-7-decisions.md).

## Decisions

### 1. Repository-path dependencies

1. **Declaration.** A dependency named by a repository path takes a minimum release version: `"github.com/acme/flint-stripe" = "1.4.2"`. A leading `v` is accepted. Prereleases are rejected as requirements and ignored by `flint deps update`.

   The repository must be a Flint library project, and version `x.y.z` is its tag `vx.y.z` (or `x.y.z`). A published module may depend only on Flint core packages and other repository paths (FLINT-E0310). A path dependency would resolve differently on every machine.

2. **Minimal version selection.** Selection follows Go's algorithm.
   - Starting from the project's requirements and those of its path dependencies, every reachable `(module, version)` is visited, including requirements of versions that end up not selected.
   - Each module gets the highest minimum anyone requires.
   - The result depends only on the requirements, never on newer tags, so resolving again is deterministic and works offline.
   - `flint deps why` shows each requirement edge.

3. **Fetching and the cache.** Fetching uses git, as `go` does without a proxy.
   - **Source:** a module is fetched from `https://<path>`, or from `<FLINT_PROXY>/<path>` when `FLINT_PROXY` names a URL or directory that serves mirrored repositories. `FLINT_PROXY=off` (or `FLINT_OFFLINE=1`) never touches the network.
   - **Mirrors:** each repository has one bare mirror under the cache (`git/<key>.git`).
   - **Content store:** each version is extracted once into a content-addressed store (`content/<sha256>/`), and `index/<key>/<version>` records its commit and hash.
   - **Location:** the cache is `<flint home>/.flint/cache`, or `FLINT_CACHE`.
   - **Verification:** every use recomputes the tree hash, so a cached or vendored tree that changed fails with FLINT-E0309.

4. **The lock.** `flint.lock` records each remote module's exact version, tag commit and content hash. A different result, such as a moved tag or a changed requirement, is FLINT-E0202, as in Milestone 7.

5. **Vendoring.** `flint deps vendor` copies the selected modules into `vendor/<path>/` and writes `vendor/flint-vendor.toml`. When that index exists, it is the build list, as Go's `-mod=vendor` uses `vendor/modules.txt`.
   - Every requirement must be satisfied by a vendored version (FLINT-E0307 otherwise).
   - Hashes are verified, and no cache or network is needed.
   - Project checks skip `vendor/`.

6. **The commands.**
   - `flint deps tree` prints the graph.
   - `flint deps why <package>` prints the shortest paths and the requirement edges.
   - `flint deps update [package...]` raises requirements in `flint.toml` to the latest release tags and rewrites the lock.
   - `flint deps vendor` vendors.

   Each command emits `flint.deps/1`.

7. **Generated recipes.** Remote modules get generated DUB recipes like path dependencies, under DUB-safe names (`github.com/acme/x` becomes `github-com-acme-x`). Each recipe references its dependencies relative to its own directory.

### 2. Embedded C

1. **Where C lives.** C embedded in a project lives in `native/`, compiled as `native/**/*.c`, or in the files `[native.c] sources` names. `[native.c]` also takes `include_dirs`, `defines` and `standard`, which is `c11` or `c17` (default `c17`).

2. **One policy.** `policy/native-c.toml` fixes the compiler, flags and clang-tidy profile for every project. A project cannot add C flags.
   - **Compiler:** the pinned clang 22.1.8 from the toolchain. A host compiler is never used (FLINT-E0816).
   - **Warnings:** `-Wall -Wextra -Werror`, plus format, shadowing, prototype, VLA and fallthrough warnings.
   - **Hardening:** `-D_FORTIFY_SOURCE=3 -fstack-protector-strong -fstack-clash-protection -ftrivial-auto-var-init=zero -fPIE`.
   - **Linking:** executables that contain C link with `-z relro -z now`, so they are full RELRO and PIE.
   - **Failures:** a warning or error is FLINT-E0708, with the compiler's message.

3. **The object cache.** Each object is stored as `.flint/cache/c/<key>.o`. The key is the SHA-256 of three things: the compiler binary's hash, the complete flag list, and the preprocessed translation unit.
   - A changed header, define, flag or compiler gives a new key.
   - A header change that leaves the unit unchanged reuses the object.
   - This is ccache's preprocessor mode. Hashing the preprocessor output avoids tracking header dependencies.

   Objects reach DUB as `sourceFiles` in the generated recipe. The receipt's `embedded_c` records the sources with their hashes, the flags, the compiler hash and the policy hash.

4. **clang-tidy.** `flint check` runs the pinned clang-tidy over every C source, with the fixed check list `bugprone-*`, `cert-*`, `clang-analyzer-*`, `performance-*` and `portability-*`. Three checks are excluded:
   - `bugprone-easily-swappable-parameters`, which is style;
   - `cert-err33-c`, which flags every ignored `printf` result;
   - `clang-analyzer-security.insecureAPI.DeprecatedOrUnsafeBufferHandling`, which demands C11 Annex K functions such as `memset_s`. Neither glibc nor musl provides them.

   Each finding is a FLINT-E0603 error located at the C file and line. The unsafe-API checks such as `strcpy` stay on.

5. **Sanitizers.** `flint test --sanitize` builds the project's tests with the existing sanitize profile: LDC with `-fsanitize=address`, linked through clang with ASan and UBSan, against the sanitizer-aware LDC runtime.
   - **C flags:** embedded C is compiled with the policy's sanitizer flags instead of `hardening`, including `-fsanitize=address,undefined -fno-sanitize-recover=all`.
   - **No `-unittest`:** the profile's own `-unittest` is dropped for project builds. Otherwise every dependency's unittests would run inside the project's test binary.
   - **Run options:** the run uses tools/ci.py's sanitizer options. Leak detection is on, the first error is fatal, and fake stacks are scanned.
   - **Installing:** `flint toolchain install` now installs the pinned clang, and `--sanitizers` adds the runtime.
   - **Scope:** the workspace's sanitizer lane stays `tools/ci.py sanitizers`, because it also needs sanitized native providers.

6. **The ffi boundary.** D reaches C only through `<root>.ffi` (or `<root>.sys`) modules, which give the rest of the program a safe API. FLINT-E0513 covers two cases:
   - an `extern(C)`, `extern(C++)`, `extern(System)`, `extern(Windows)` or `extern(Objective-C)` declaration in any other module;
   - any `.c`, `.h` or `.i` file under `src/` or `test/`, where ImportC would make C importable from anywhere.

   The `@trusted` rules (SAFETY comment, length, confinement) apply to the wrappers as before.

## Consequences

- Repository-path dependencies resolve reproducibly. They work offline from the cache or from `vendor/`, and are tested only against local git fixture repositories (`tests/test_flint_deps.py`).
- Embedded C builds, tests (including under ASan and UBSan) and checks through flint alone. `tests/test_flint_native_c.py` covers hardening, the cache, clang-tidy, the ffi rule, and a heap overflow and a signed overflow caught under `--sanitize`.
- Two latent Milestone 7 defects were fixed along the way. An empty manifest table such as a bare `[dependencies]` header, which `flint new --type library` writes, was rejected. Nested path dependencies got wrong relative recipe paths.
