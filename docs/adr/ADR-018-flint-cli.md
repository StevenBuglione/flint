# ADR-018: The `flint` command-line tool

Status: proposed by the project owner on 2026-11-21. Implementation is Milestone 7, which starts after Milestone 6 passes.

## Context

Flint now depends on its own toolchain: a forked DMD with a resident compile server and direct linking, a forked DUB with a parallel build pipeline, pinned LDC, and native provider archives whose recipe blocks are written into `dub.sdl` files. The correct flags for each kind of build live in several places: `tools/ci.py`, the profiles in `tools/measure_builds.py`, package probe recipes, and helper scripts. A build with the wrong compiler, a stale native prefix or a slightly different flag set still succeeds. It just produces numbers or binaries that are not comparable. That has already cost time in this project.

## Decision

Flint gets one multi-purpose command, `flint`, written in D on Flint's own libraries (`cli`, `config`, `log`, `os`, `term`, `style`, `serde`, `test`) and built with the Flint toolchain, so the project uses its own framework for real work. Its first job is building, testing and running Flint code with the canonical optimizations, so that the development loop is consistent and every result can be traced to exact inputs.

### First commands

| Command | Purpose |
| --- | --- |
| `flint build [target] [--profile P]` | Build an app or package with a named profile. |
| `flint run [target] [--profile P] [-- args]` | Build if needed, then run. |
| `flint test [package...] [--compiler dmd\|ldc\|both]` | Run unittests with the canonical flags, including peers or fixtures that a package declares. |
| `flint toolchain install\|verify\|info` | Install the pinned toolchain or check it against `policy/toolchains.json` and the fork patch hashes. |
| `flint doctor` | Report the toolchain, native prefix, compile server and environment problems that would make a build non-canonical. |
| `flint version` | Print the tool, toolchain and source identities. |

Later commands such as `new`, `bench`, `measure`, `gate` and `release` take over from the Python tools one at a time. Each move must reproduce the existing tool's output.

### Profiles are data

Named profiles live in one checked-in policy file:

- `dev`: forked DMD with the compile server and pipeline, `-debug -g`.
- `test`: unittest builds on both compilers.
- `release`: LDC `-O3` with thin LTO and static default libraries.
- `size`: as release, with `-Oz`.

The native provider profile is part of each build profile. `flint`, `tools/ci.py` and `tools/measure_builds.py` all read this file, so flags cannot drift between the developer loop, CI and measurement.

### Custom flags stay possible

`--dflags`, `--lflags` and a `--` pass-through add flags on top of a profile. A build with extra flags still works. Its receipt marks it *non-canonical* and lists the additions, and measurement and gate commands refuse non-canonical inputs.

### Version verifiable

Before building, `flint` verifies:

- the compiler, DUB and fork patch hashes;
- the native install receipt;
- the source commit and whether the tree is dirty.

It writes a build receipt (JSON) next to every artifact. The receipt records those identities, the resolved profile, the exact flags and the output hashes, so any binary or measurement can be traced back to its inputs. `--verify` turns a mismatch into an error instead of a warning.

### Scope boundaries

- DUB stays the package and dependency model. `flint` drives it and does not replace `dub.sdl`.
- The existing Python tools keep working until `flint` reproduces each one's results.
- Bootstrap: the first `flint` binary is built by `tools/install_toolchains.py` and DUB. After that, `flint` can rebuild itself and checks its own receipt.
- Linux first, as with the rest of the project.

## Consequences

- Wrong-compiler and wrong-flag errors move from silent drift to an immediate, explained failure.
- The CLI-related libraries get a demanding real user before any external one. Any ergonomic gaps found while building `flint` are fixed in the libraries.
- One more component must be maintained. Keeping profiles as data shared with the Python tools limits the duplication while both exist.

## Open choices for Milestone 7

- The name and format of the profile policy file. A TOML file read through `flint.config` is the default proposal.
- Whether `flint test` starts the external fixture peers (PostgreSQL, Valkey, S3 and similar) itself or only reports which ones it needs.
