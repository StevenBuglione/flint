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

### 3. Packaging

1. **`flint package [--target T] [--container] [--sbom]`.**
   - **The build:** the release profile, rebuilt from scratch for the target and stripped with `-L--strip-all`.
   - **The check:** the executable's ELF headers are verified against the target's linkage rule.
   - **Staging:** the executable goes under `bin/`, with the project's `config/` and `resources/` beside it.
   - **Outputs:** in `.flint/package/`, `<name>-<version>-<target>.tar.gz`, with optional SBOMs and image. A `flint.package/1` receipt lists every output with its hash, the build receipt, the linkage facts and the image digest.

2. **Static by default.** Flint packages, the D runtime and native packages are always linked statically.
   - **musl targets** are fully static, with no interpreter and no `DT_NEEDED`.
   - **glibc targets** keep only the C library shared, because glibc does not support static NSS or `dlopen`. Any other shared library is FLINT-E0711.
   - **`linkage = "bundled"`** is the exception for a native package. It ships the library in `lib/` with an `$ORIGIN/../lib` run path, and it arrives with the native resolver.

3. **musl without a container.** `linux-x86_64-musl` is cross-linked on any Linux x86-64 host. `flint toolchain install --musl` installs the pieces.
   - **Compiling:** the pinned LDC compiles for `x86_64-alpine-linux-musl` against the pinned Alpine LDC release's druntime and Phobos.
   - **Linking:** the pinned clang links a static PIE (`-static-pie`) against a musl sysroot.
   - **The sysroot:** flint assembles it from six checksum-pinned Alpine 3.22 packages: musl, musl-dev, libgcc, gcc's crt files and libgcc archives, linux-headers, and libunwind-static. The packages are listed in `policy/toolchains.json`, `musl_sysroot`. They are extracted directly, without `apk`, and a receipt records the tree hash.
   - **ImportC:** ImportC sources in dependencies, such as flint:os's C shim, are preprocessed against the same sysroot.
   - **Why not a container:** Alpine containers are the musl CI lane's runtime test, but building through them would need a container engine for every package build. It would also tie the result to whatever apk serves on the day.

4. **The OCI image.** `--container` writes a `FROM scratch` image as an OCI image-layout archive, `<stem>.oci.tar`, which `docker load` and `podman load` accept.
   - **Built by flint:** flint writes the image itself, so no container engine is needed to build it.
   - **The layer:** a single layer holds `/app/<executable>` with `config/` and `resources/`.
   - **The config:** the entrypoint is the executable, the working directory is `/app`, and the user is `65532:65532`. It carries OCI labels for title, version, created date, licence and target.
   - **The requirement:** a scratch image needs a fully static executable, so `--container` defaults to the musl target, and a glibc target is FLINT-E0710.

5. **SBOMs.** `--sbom` writes SPDX 2.3 (`.spdx.json`) and CycloneDX 1.6 (`.cdx.json`). Both are validated by the reference tools: `pyspdxtools` and cyclonedx-python-lib's strict JSON-schema validator.
   - **Components:** the application, with the executable's hash; every Flint package; every repository module, with version, commit and tree hash; path and DUB packages; embedded C files, with file hashes; native packages; and the runtime. The runtime is druntime and Phobos (BSL-1.0), plus musl and libgcc for musl targets, or a dynamic glibc for glibc targets.
   - **Details:** each component records its licence expression, origin, linkage and any `[unchecked]` waiver, and the dependency graph is recorded too.
   - **Licences:** `[project] license` is a new optional manifest key, so licences propagate from repository modules.

6. **Reproducibility.** Every archive is written deterministically: root ownership, fixed modes, the given entry order, and gzip without a timestamp.
   - **Timestamps:** SBOM, archive and image times come from `SOURCE_DATE_EPOCH` when it is set.
   - **Result:** with it set, two forced rebuilds produce byte-identical executables, archives, SBOMs and image digests.

7. **`flint deps audit [--target T]`.** The audit uses the SBOM's inventory for the target.
   - **Hashes:** it verifies `flint.lock` against the resolved graph and its content hashes, and reports each repository module's verified tree hash.
   - **Licences:** it lists every component's licence. A missing licence is a FLINT-E0312 warning, and an `[unchecked]` waiver is a FLINT-E0313 warning.
   - **Obligations:** it states the obligations of distribution.
     - LGPL, statically linked: relinking material, or `bundled`.
     - LGPL, shared: replaceability, notices and a source offer.
     - AGPL: the network source offer.
     - A plain GPL without an exception: copyleft over the whole executable.
     - GCC-exception runtimes carry no obligation.

8. **Two incidental fixes.**
   - `flint daemon stop` now sweeps until the process holding a server's lock has exited. The stale socket it could leave behind made a Milestone 7 test flaky.
   - The policy lexer reads `name(...) @trusted` followed by a line-initial `{` as a trusted block, so a `@trusted` function with no other trailing attribute puts `@trusted` before the return type.

## Consequences

- Repository-path dependencies resolve reproducibly. They work offline from the cache or from `vendor/`, and are tested only against local git fixture repositories (`tests/test_flint_deps.py`).
- Embedded C builds, tests (including under ASan and UBSan) and checks through flint alone. `tests/test_flint_native_c.py` covers hardening, the cache, clang-tidy, the ffi rule, and a heap overflow and a signed overflow caught under `--sanitize`.
- `flint package --container --sbom` produces a runnable scratch image and valid SBOMs from a plain Linux x86-64 host. `tests/test_flint_package.py` loads and runs the image in docker when one is available.
- Two latent Milestone 7 defects were fixed along the way. An empty manifest table such as a bare `[dependencies]` header, which `flint new --type library` writes, was rejected. Nested path dependencies got wrong relative recipe paths.
