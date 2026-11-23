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

### 4. DUB packages and `[unchecked]`

1. **Declaring a DUB package.** A third-party DUB package is written `"dub:<name>" = "<version>"`. The version must be listed in the DUB compatibility index, `policy/dub-index.toml`; an unlisted version is FLINT-E0314, and the error lists the versions the index has.

2. **What an index entry pins.**
   - The repository path, tag commit and tree hash.
   - The SPDX licence.
   - The exact index versions of the DUB packages it needs.
   - The Flint native recipes that replace its `libs` or `systemDependencies`, which are informational in DUB itself.

   The index ships with D-YAML 0.10.0 and tinyendian 0.2.0, measured from their release tags. An additional private index can be named with `FLINT_DUB_INDEX`, for private packages or tests; its entries are marked with their source.

3. **Selection.** Entries are exact pins, so selection simply follows them transitively. Two requesters that need different versions of one package are FLINT-E0315, which names both requesters and both versions. Flint never picks one.

4. **Fetching.** Packages are fetched through the repository-path cache, with mirrors, the content store, `FLINT_PROXY`, offline mode and vendoring.
   - The fetched tag must be the pinned commit and reproduce the pinned tree hash, otherwise FLINT-E0309: a moved tag is refused.
   - `flint.lock` records each package's kind, repository, version, commit and tree hash.

5. **Building from a working copy.** DUB writes build outputs into a package's own directory. Flint therefore builds DUB packages, including local DUB directories, from a disposable copy in `.flint/generated/dub-packages/`, refreshed from the verified source when its hash changes.
   - A generated `dub.selections.json` points DUB at those copies, so DUB packages that depend on each other resolve to the index's versions.
   - The cache, vendored copies and the user's checkouts are never written.

6. **The safety checks and `[unchecked]`.** Flint runs its D safety rules over every DUB package's `source/` and `src/`, whether indexed or a local directory. The rules are module `@safe:` defaults, `@trusted` confinement and rationale, and string mixins.
   - **Failing:** a package that fails builds only under `[unchecked]`, with `"dub:<name>" = "<reason>"`. Otherwise it is FLINT-E0316, which shows the finding count and the first findings.
   - **Visible everywhere:** the waiver is printed on every build (`Unchecked dub:dyaml 0.10.0: <reason> (69 findings)`). It is also recorded in the receipt's `unchecked` field, in both SBOMs, and as a FLINT-E0313 warning in `flint deps audit`.
   - **Reality:** both seeded packages fail the rules, as almost every existing DUB package will, because none declares `@safe:` defaults. The waiver is the visible price of using them.

### 5. Native packages: a resolver with Conan hidden inside

1. **The engine.** `flint toolchain install` installs a pinned, checksum-verified, self-contained Conan 2: release 2.34.0, the official frozen-Python bundle, whose SHA-256 is in `policy/toolchains.json`.
   - **Isolation:** it runs only with Flint's own Conan home, `<flint>/.flint/conan`, which holds its cache, profiles, `settings_user.yml` (adding `os.libc`) and `global.conf`.
   - **One remote:** every run first removes any other remote and registers Flint's recipe index as the single remote.
   - **Hidden output:** `tools/native_resolver.py` drives it. Conan's output goes to a log file, and the resolver answers flint in one JSON document, in Flint's words, on success and failure alike.
   - **Visible nowhere:** no Conan file, command or message appears in a project, its output or its diagnostics. `tests/test_flint_native.py` and the Milestone 8 end-to-end test assert this.

2. **The recipe index is checked in.** The index is a Conan `local-recipes-index` at `native/conan-index`, generated by `tools/conan_index.py` from `policy/native-lock.json` and verified by `--check`. Checking it in rather than hosting it was chosen for five reasons.
   - **Pinned with the code:** recipes change only through reviewed commits, alongside the lock they implement, and a recipe revision is the hash of checked-in files.
   - **No network for resolution:** resolving needs no network or account, and nothing outside the index can be resolved: there is no ConanCenter and no fallback.
   - **Engine-native format:** it is Conan's own format for local indexes, so the engine needs no adapter.
   - **Auditable:** sources, hashes, licences and options are plain text in the repository.
   - **Replaceable:** projects only ever name `name = "version"`, so the engine or the index format can change without touching a project.

3. **Seeded from the 19 providers.** The index holds one recipe per provider: the workspace's `ci` closure, Wasmtime and liburing.
   - **Same inputs as the lock:** each recipe downloads the lock's archive URL and verifies its SHA-256, and declares the lock's licence, dependencies and supported targets.
   - **Same build steps:** each recipe builds through the per-library steps of `tools/native_build.py`, using its new `--no-dependencies` and `--no-shims` modes. That keeps one implementation of the hardening flags, provider options (curl's protocol set, libpq's meson targets, librdkafka's features) and the sanitizer variant, which is an option with its UBSan exclusions.
   - **Pinned build steps:** every recipe embeds the SHA-256 of `native_build.py` and refuses another, so changing the build steps changes every recipe revision and package ID.
   - **Measured result:** building the whole closure took 5 minutes. 12 of the 19 providers' archives are byte-identical to `native_build.py`'s. The other 7 differ only in member sizes of 32 to 40 bytes, with no different strings, from the different build-directory path lengths of the two builds.
   - **Shared deployment:** `native_resolver.py deploy` merges the closure into an install prefix with `native_build.py`'s receipt layout, builds the Flint C shims over it and emits the same DUB link blocks. So the workspace can use Conan natives in place of `.native/install`, and `native_build.py` keeps working unchanged until the equivalence is accepted.

4. **`[native]` in a project.** A project declares `zlib = "1.4"`, or `{ version, linkage, system, options }`.
   - **Requirements:** flint collects requirements from the project, its path and repository dependencies' `[native]`, and the native recipes of indexed DUB packages.
   - **Conflicts:** two versions of one package are FLINT-E0320, which names both requesters, before any engine runs. A version the index lacks is FLINT-E0318, which names the version the index has.
   - **Into the build:** the resolver's archives and system flags become the generated recipe's `lflags`, and its include directories become embedded C's `-I` flags (and part of its cache key).

5. **The lock.** Each native package gets a `[[native]]` entry in `flint.lock` with its version, linkage, target, recipe revision, package ID, source SHA-256 and binary SHA-256 (the content hash of the package folder).
   - **Every build checks it:** each build re-resolves, which is a cache hit after the first build, and rehashes. A changed binary or recipe is FLINT-E0202 ("changed native zlib").
   - **Other targets:** binaries are locked for the host target. Builds for other targets or the sanitizer variant verify the locked recipe revision and source hash, and record their own package ID and binary hash in the receipt.

6. **`system = true`** is the only way to use a host library. flint finds it through pkg-config, without the engine (FLINT-E0321 when it is missing or too old).
   - **Non-portable:** the build prints `Non-portable`, and the receipt sets `portable: false` with the reason.
   - **The lock:** it records only the system version.
   - **Packaging:** `flint package` refuses the shared host library (FLINT-E0711).

7. **Linkage.** Static is the default.
   - **`bundled`:** flint links the package's archives into `lib<name>-flint.so` with the pinned clang, using the dependency archives for its undefined symbols. The executable links against it with the run path `$ORIGIN/../lib`, and `flint package` ships it in `lib/`.
   - **Why not a shared recipe build:** one generic mechanism covers every recipe, because the providers are built as position-independent static archives.

8. **musl.** For `linux-x86_64-musl`, the resolver generates a CMake toolchain file for the pinned clang and the pinned musl sysroot. The recipes' CMake providers then cross-build on the glibc host. `native_build.py` refuses an unverified cross build of the other providers, as before; those build on a musl runner.

### 6. Hosts: paths with spaces and DUB's libcurl

These are two findings from installing on the NixOS performance runner, whose checkout lives under a path with a space.

1. **Paths with spaces.** flint passes every path as its own argument, or quotes it in the files it writes: recipes, selections, receipts, the musl `ldc2.conf` and the CMake toolchain file.
   - **The one exception, `DFLAGS`:** DUB splits it at whitespace. The only path flint puts there is the musl target's `-conf=`. When the project path has whitespace, that file is written content-addressed into the temporary directory instead.
   - **Older toolchains:** DMD itself splits unquoted `%@P%` arguments in `dmd.conf`, and toolchains installed before `install_toolchains.py` quoted them (`c5be651`) fail. `flint doctor` reports such a `dmd.conf` under a path with spaces as FLINT-E0821, and reinstalling fixes it.
   - **Verified:** a project and a toolchain both under paths with spaces build, test (with sanitizers too), check and package for musl with a container. `tests/test_flint_package.py` keeps the project half.

2. **DUB's libcurl.** DUB downloads through Phobos' `std.net.curl`, which loads `libcurl.so.4` (or a variant) at run time. On NixOS the loader does not find it, so `dub fetch` fails although curl works.
   - **`flint doctor`:** probes the same library names with `dlopen` and reports FLINT-E0820, with the fix: install libcurl, or point `LD_LIBRARY_PATH` at it (the NixOS command is given).
   - **`flint toolchain install`:** checks the same before spending minutes on the compilers. `install_quality_tools.py` checks it too, and exits with a plain message instead of a traceback.
   - **Installer errors:** installer standard error now goes to `<flint>/.flint/logs/toolchain-install.log`, and a failure is summarised by its last line in FLINT-E0814.

## Consequences

- Repository-path dependencies resolve reproducibly. They work offline from the cache or from `vendor/`, and are tested only against local git fixture repositories (`tests/test_flint_deps.py`).
- Embedded C builds, tests (including under ASan and UBSan) and checks through flint alone. `tests/test_flint_native_c.py` covers hardening, the cache, clang-tidy, the ffi rule, and a heap overflow and a signed overflow caught under `--sanitize`.
- `flint package --container --sbom` produces a runnable scratch image and valid SBOMs from a plain Linux x86-64 host. `tests/test_flint_package.py` loads and runs the image in docker when one is available.
- Real DUB packages (D-YAML on tinyendian) build and test on both compilers under visible waivers. `tests/test_flint_dub.py` covers selection, conflicts, moved tags, vendoring, waivers and local DUB directories against git fixtures.
- Native packages resolve, build, lock and link through `flint` alone, with Conan never visible. The workspace passes 74/74, plus mq's 7 live scenarios, against the Conan-built providers. The golden REST service's verifier passes against both provider builds. [Milestone 08](../milestones/08.md) has the evidence.
- `tools/native_build.py` stays the workspace's default native path until the owner accepts the equivalence. Its per-library steps are the recipes' build steps, so retiring it means moving those steps into the recipes.
- Two latent Milestone 7 defects were fixed along the way. An empty manifest table such as a bare `[dependencies]` header, which `flint new --type library` writes, was rejected. Nested path dependencies got wrong relative recipe paths.

## Amendment (2026-11-23): platform modules, for the repo split

The repo split (ADR-030; the Spring-port plan, section 7) adds platform modules. These are a second kind of dependency beside repository paths.

1. **A platform module is one Flint repo.** Examples are `flint`, `flint-framework`, `flint-boot`, `flint-security`, `flint-data-jdbc` and `flint-ai`.
   - **Its packages:** the set of `flint:*` packages, Boot libraries and starters that share one tag. Each one's `repo` field in `policy/packages.json` and `policy/boot.json` names its repo.
   - **How it resolves:** by platform version, never by minimal version selection, so every package of one repo always comes from the same commit. MVS (section 1) stays the rule for applications' own repository-path dependencies.
2. **Edges between platform modules follow Spring's own,** as `policy/repos.json` lists them (ADR-030):
   - boot → integrated (security, data) → framework → flint;
   - Boot-based repos (ai, cloud) → boot.

   The structural gate fails any other edge (FLINT-E0532). `flint check --gate structural --repo <name>` and `tools/gates.py --repo <name>` check one repo's packages, as that repo's own CI will.
3. **`platform.lock`, in the `flint` repo, pins every repo.**
   - **Before the split:** each entry is `"source": "monorepo"`.
   - **After it:** each entry carries the repo's `commit` and `tag`. flint then resolves that repo's packages, Boot libraries and starters from its checkout under `.flint/platform/<repo>-<commit>`.
   - **`FLINT_WORKSPACE`:** this names a `flint.workspace/1` file of local checkouts, which overrides those checkouts for development.
   - **The project lock:** outside the workspace, a project's `flint.lock` records each Flint package's `platform = "<repo>@<version>"`.
4. **`flint-dependencies`, the bill of materials, as `spring-boot-dependencies`.**
   - **The file:** `boot/dependencies/flint-dependencies.json` pins the coordinated set of `flint:*` artifacts and their platform versions for applications.
   - **How it is kept current:** `tools/platform_modules.py --write` generates it from policy and `platform.lock`, and `--check` fails when it is stale or when `platform.lock` misses a repo.
5. **Workspaces.**
   - **The file:** a `flint.workspace/1` file pins each repo's checkout and commit.
   - **The tools:** `tools/gates.py`, `tools/measure_builds.py` and `tools/native_build.py` take `--workspace`. They verify the pinned commits and find each package in its repo's checkout. `measure_builds` records the commits in its evidence.
   - **The current limit:** `measure_builds` builds only a single-checkout workspace until the split rewrites the probes' recipes.
   - **Without the flag:** the monorepo is the workspace, and every gate behaves as before.
6. **Applications belong to repos too.**
   - **The policy:** `policy/apps.json` records each app's repo. `apps/flint` is in `flint`, and `apps/flint-mcp` is in `ai`, beside the `mcp` package it serves.
   - **Locating an app:** an app keeps its directory inside its repo. `flint mcp` locates flint-mcp through the ai repo's platform module.
   - **Its dependencies:** an app's `flint:*` dependencies follow the same edges (FLINT-E0532).

7. **Building from platform modules** (an application whose Flint home lacks a repo's packages).
   - **The layout:** an extracted repo mirrors Spring's own (`policy/repos.json` `layout`). Engines go under `engine/<name>`, Spring-layer modules to `flint-<artifact>`, and Boot to `core/`, `module/`, `platform/` and `starter/`; the pre-port Boot is `legacy/flint-boot`. flint finds a package at its monorepo path when the checkout has it, else at its extracted place (`Home.packagePath`).
   - **Fetching:** `tools/platform_modules.py --fetch [--native <target>]` clones each pinned repo into `.flint/platform/<repo>-<commit>`, writes `.flint/platform/workspace.json`, and emits the native DUB blocks into those checkouts. A package whose checkout is missing fails resolution with FLINT-E0533.
   - **One namespace:** every repo's recipe is named `flint`, and DUB takes one package of a name. When a build's core packages span checkouts, flint writes `.flint/generated/flint/dub.sdl`, which joins them as subpackages at relative paths, and depends on it.
   - **The proof:** `tools/platform_proof.py` makes the home the `flint` repo becomes at the cutover, pins the mirrors, and builds and runs a starter-web app outside both.
   - **Native shims:** `native/ffi` still builds the engines' C shims in the `flint` repo; it skips their test codecs and reference controls when their sources are absent. Moving those shims into `flint-framework` is still to do.
