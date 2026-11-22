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

## Consequences

- Repository-path dependencies resolve reproducibly. They work offline from the cache or from `vendor/`, and are tested only against local git fixture repositories (`tests/test_flint_deps.py`).
- Two latent Milestone 7 defects were fixed along the way. An empty manifest table such as a bare `[dependencies]` header, which `flint new --type library` writes, was rejected. Nested path dependencies got wrong relative recipe paths.
