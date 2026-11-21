# Flint implementation checkout

Read `AGENTS.md` and `handoff/MILESTONES_EXECUTION_PLAN.md`. The initial checkout contains recipes and build policies, not fake implementations. Complete the assigned package before its tests/build can pass. Handoff contracts are documentation/typechecking references and are not on the production import path.

## Faster Linux development builds

On x86-64 glibc, the project-local DMD toolchain can use mold or LLVM's ELF linker. With `mold` on your path and a C compiler driver that supports `-fuse-ld=mold`, run these commands from the checkout root.

```bash
python3 tools/install_toolchains.py --compiler dmd --dmd-linker mold
export PATH="$PWD/.tools/dmd2/linux/bin64:$PATH"
```

Use `--dmd-linker ld.lld` to select LLD. The installer also accepts an absolute linker path and records its version and checksum. From an application with its native dependencies prepared, use `dub build --compiler=dmd` for the edit loop. For a fresh build, `dub build --compiler=dmd --combined` compiles the application and its D dependencies together. Package mode reuses unmodified dependency builds after an edit. Installing the pinned DMD toolchain again without `--dmd-linker` restores its upstream linker configuration.

The Linux compile-time report includes cold and edited builds against Go, plus the command for caching ThinLTO objects in LDC release builds. [Linux compile-time measurements](docs/milestones/06-linux-compile-time.md)
