# Native Flint AOT extraction: WIP scripts (parked 2026-11-24)

Working scripts behind the `-flint-aot-extract` parity and timing numbers in `toolchain/README.md`. They are not
part of any gate. Paths are hard-coded to the dmd-arm64 checkout on venus (`~/flint-work/dmd-arm64/flint`), and to
a scratchpad holding `extract-args.json`: the argv of petclinic-rest's real extraction compile, traced with
`strace -f -e trace=execve` (stop the strace once the build ends; it follows the daemonized compile server forever).

- `parity.py <app> [--modules a,b] [--src dir] [--gen dir] [--args json] [--dmd path]`: run the CTFE describer root
  and the native root over the same modules, in-process (`FLINT_DMD_SERVER=0`), and compare the FLINT-AOT lines.
- `parity-all.sh`: every set. That's the 392 platform modules of petclinic-rest's prelude (without
  `flint.arena.sys.gc.counting`, where the describer itself fails), the three Phase 1 apps and the `tests/aot`
  fixtures.
- `showdiff.py <parity dir> [n]`: the first differing lines of a parity run.
- `floor.py`: served timing with and without the platform prelude, for an import-only root, the native root and
  the describer root.
