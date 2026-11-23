# DMD's AArch64 code generator in the Flint fork

[ADR-025](../../docs/adr/ADR-025-fast-compiles-everywhere.md) section 3 makes the forked DMD the development compiler on arm64. Upstream DMD 2.114.0 contains an unfinished AArch64 back end, selected with `-marm64`. The fork completes it for Linux AArch64 (ELF) and macOS arm64 (Mach-O).

## Patches

| File | Applies to | Hosts |
| --- | --- | --- |
| `../dmd-2.114.0-flint.patch` | compiler sources (`dmd2/src/dmd`) | all. The AArch64 changes are their own file sections after the fork's other changes. |
| `../dmd-2.114.0-flint-darwin.patch` | compiler sources, after the shared patch | macOS: the compile server and direct linking on Darwin's system interfaces |
| `../druntime-2.114.0-flint.patch` | `dmd2/src/druntime` (sources and `import/`) | arm64 runtime builds |
| `../phobos-2.114.0-flint.patch` | `dmd2/src/phobos` | arm64 runtime builds |

The AArch64 changes leave x86-64 code generation unchanged. On 2026-11-23 (again after the last change listed below), `bench-cli` and `bench-rest` were built in debug and release mode with the fork with and without them, installed at the same path. Of 5,700 objects, archive members and executables, the debug builds were byte-identical. In the release builds, one object of `flint:log` (`package_e2_260.o`) differed, along with the `bench-cli` executable that contains it. That object also differs between two runs of the same compiler: a 64-bit immediate carries uninitialised upper bytes. This is an existing nondeterminism and is not caused by these changes.

## Install

On macOS arm64 and Linux AArch64 (glibc), from the checkout root:

```bash
python3 tools/install_toolchains.py --compiler dmd
```

No DMD release runs on arm64, so the installer does the following:

1. It extracts the pinned `dmd.2.114.0.linux.tar.xz` for its sources.
2. It applies the patches and builds the fork with the pinned LDC for the host.
3. It builds druntime and Phobos with `dmd -marm64` into `lib64/libphobos2.a`. The library includes druntime's assembly and C parts and Phobos's zlib.
4. It writes a `dmd.conf` that adds `-marm64`.

The compiler is installed in `.tools/dmd2/osx/bin64` on macOS and in `.tools/dmd2/linux/bin64` on Linux. On pluto, the whole install takes about 80 seconds.

## Regression tests

Every code generator defect fixed in the fork has a test here. Each test is a self-checking D program that exits 0, and some have a C companion. `run.py` compiles each test three ways (no flags, `-O`, `-O -release -inline`), links it against druntime for the target, and runs it. A test `name.d` with a directory `name/` also links a library that `dmd -lib` builds from that directory.

```bash
# natively on an arm64 host, with the installed toolchain
python3 toolchain/arm64/run.py --dmd .tools/dmd2/osx/bin64/dmd \
    --druntime-import .tools/dmd2/src/druntime/import --druntime .tools/dmd2/osx/lib64/libphobos2.a --os osx

# on Linux x86-64, for Linux AArch64 under QEMU user mode
python3 toolchain/arm64/run.py --dmd <fork dmd> --druntime-import <druntime/import> --druntime <arm64 libphobos2.a> \
    --cc aarch64-linux-gnu-gcc --run-prefix "qemu-aarch64 -L /usr/aarch64-linux-gnu"
```

## Status (stage 1: runtime libraries)

| | druntime unittests | Phobos unittests | regression tests |
| --- | --- | --- | --- |
| Linux AArch64 (native: Ubuntu 24.04 VM on pluto, 4 vCPUs) | 567/567 modules | 176/176 modules | 122/122 |
| macOS arm64 (pluto, native) | 567/567 modules | 176/176 modules | 124/124 |
| Linux AArch64 (QEMU user mode, cross from x86-64) | 567/567 modules | 173/176 modules | 122/122 |

Both libraries pass natively on both systems. The fork builds natively on Linux AArch64 with `install_toolchains.py --compiler dmd` (3 minutes in the VM). The regression tests count two more on macOS: its direct-link and FDE checks. Under QEMU, three Phobos modules fail because of the cross sysroot, not the code generator; all three pass natively:

- `std.stdio` opens a file in mode `ccs=UTF-16LE`, and the sysroot has no gconv modules;
- `std.net.curl` finds no arm64 libcurl, and QEMU's `accept` fails;
- `std.socket` stops in glibc's `fd_set` bounds check under QEMU.

In the 8 GB VM, building the unittests of Phobos's largest modules (`std.conv`, `std.algorithm.iteration` and five more) four at a time ran out of memory; one at a time, they build.

## Status (stage 2: Flint's packages)

On macOS arm64 and Linux arm64, the forked DMD now fills the DMD role of the dev and test profiles. `flint toolchain install` runs `install_toolchains.py --compiler dmd`, then LDC and the Flint DUB.

On pluto, `flint test --compiler dmd` passes 37 of the workspace's 38 packages, peers included (S3, MinIO, PostgreSQL, Valkey and the Go peers). The run used the native providers that `tools/ci.py` builds (`--profile ci --library wasmtime --library wkwebview`) and Homebrew's `python3`. Apple's `/usr/bin/python3` 3.9 rejects the S3 fixture's empty query strings. The 38th package, `engine-desktop`, passes when its test binary runs with `SDL_VIDEODRIVER=dummy`, as the lane does: `flint test` does not pass that variable through. Its WKWebView tests need the logged-in GUI session.

On Linux arm64 (the `flint-arm64` VM on pluto: Ubuntu 24.04, 4 vCPUs, 8 GB), Flint bootstraps with the fork, and `flint test --compiler dmd` passes 33 of the 37 packages in one run, peers included (PostgreSQL, Valkey, MinIO and the Go peers), with the `ci` providers and wasmtime. `os` and `engine-sql` failed in that run and pass when run alone. The other two pass every functional test but miss a CPU-time bound while the VM is loaded by another lane's build. `engine-http`'s HTTP worker used 18.9 to 24.3 ms against 15 ms, and passed 1 run in 3. `engine-web`'s delayed echoes used 41 ms against 30 ms. On the quiet VM (load 0.2), both passed 3 runs out of 3. So every package passes with the fork on Linux arm64.

## Status (stages 3 to 5: speed on macOS arm64)

- Mach-O archives have 8-byte aligned members, and Apple's ld links them without `-ld_classic`.
- The Darwin direct link runs Apple's ld from the cached expansion of `cc -###`.
- The compile server serves macOS. On pluto it compiles `flint:config` in 61 ms; without it, DMD takes 190 ms.
- Process start: D executables no longer export template instances as weak definitions. DMD is built with LTO and exports only `main`, and so does the Flint DUB. `dmd --version` went from 15 to 5 ms, and `dub --version` from 30 to 5 ms.
- The DUB pipeline writes Darwin archives (the macOS port's overlay).

On 2026-11-23, `tools/measure_builds.py --apps-only` on pluto (9 trials, load average 5 to 7 from other work on 8 cores) measured the following medians:

| | dev build cold | Go cold | dev build incremental | Go incremental |
| --- | --- | --- | --- | --- |
| bench-cli | 0.238 s | 0.169 s | 0.174 s | 0.163 s |
| bench-rest | 0.297 s | 0.301 s | 0.241 s | 0.293 s |

`bench-rest` is at or below Go; `bench-cli` is not yet.

- A cold `bench-cli` build spends 12 ms in DUB, about 120 ms on its longest compile job (`flint:config`, 61 ms when the machine is quiet) and about 70 ms linking.
- Of the link, 60 ms is the fixed cost of druntime, Phobos and the system libraries: an empty D program takes that long to link.
- druntime does not support D shared libraries on macOS, which would remove that cost.
- The gate needs a quiet measurement window. Pluto's background load moves Go's own times between 0.17 and 0.47 s.

## Decisions and known ABI gaps

- **`real` is `double` on all AArch64 targets**, as it already was for macOS. The back end has no 128-bit floating point. On Linux, C's `long double` is 128-bit, so `extern(C)` functions that take or return `long double` are not compatible. druntime binds the C library's `long double` functions in `core.stdc.math`, and `strtold`, to their `double` versions there (`long_double_libm`). `printf("%Lf")` and other C code that passes `long double` still disagree.
- **Homogeneous floating point aggregates (HFAs) of 3 or 4 float or double elements**, such as `CGRect`, follow AAPCS64 in calls with C (and C++, Objective-C) linkage: they are passed and returned in SIMD registers (`hfa_c_abi`). The back end has register pairs only, so the glue lowers them: the caller passes such an argument as its elements, and stores a result from v0.. into a temporary; a D function with C linkage gets the elements as parameters and returns through a temporary that its return loads into v0... Two cases still differ from AAPCS64. An HFA argument that no longer fits in the remaining SIMD registers goes partly in registers instead of whole on the stack. `va_arg` of an HFA through a C `va_list` uses the general rules. D linkage keeps the general rules: in general registers, or in memory above 16 bytes. HFAs of 1 or 2 elements follow AAPCS64 for every linkage.
- **A result returned in memory** has its address passed in x8 for every linkage (AAPCS64), and the address is not returned (`c_struct_return`).
- On macOS, stack arguments follow Apple's rules:
  - scalars are packed at their natural alignment;
  - composites of up to 16 bytes take 8-byte aligned slots;
  - the variadic part of a call goes on the stack.

## Fixes offered upstream (dlang/dmd)

The changes below are independent of Flint and are candidates for upstream pull requests. The test that covers each one is named where there is one.

Object files and relocations:

- ELF: relocations chosen from the instruction (B/BL, ADRP, ADD, scaled LDR/STR). The GOT is used for extern data and for function addresses in PIC. TLS uses local-exec and initial-exec. Data relocations are ABS64, ABS32 or PREL32. `.init_array`/`.fini_array` and `__d_dso_init` use the right relocations and call `_d_dso_registry`. (`function_address_got`, `tls_access`)
- ELF: the x86 PIC/PIE rewrites (GOT, `__tls_get_addr`) are skipped in `elpicpie`.
- Mach-O: relocations chosen from the instruction (BRANCH26, PAGE21/PAGEOFF12 with `ARM64_RELOC_ADDEND`, GOT_LOAD, TLVP_LOAD). Non-local symbols go through the GOT. Extern symbols forwarded to a public or local definition use its index. Thread-local template variables get weak TLV descriptors. (`tls_template`)
- Mach-O `__eh_frame`: a `zPLR` CIE with an `ARM64_RELOC_POINTER_TO_GOT` personality. FDE addresses and the LSDA are `pcrel|sdata4` `SUBTRACTOR`/`UNSIGNED` pairs. (`exceptions`)
- Mach-O: the TLV init-symbol name buffer freed the stack buffer for long names.
- Mach-O AArch64: template instances (COMDAT definitions) are weak definitions that the linker may hide, so executables do not export them. With them exported, dyld coalesced each one against every loaded image at start-up: an empty D program retired 92 million instructions instead of 16 million, about 15 ms (`run.py` checks it).
- Mach-O libraries (`dmd -lib`): the symbol table was padded to 4 bytes, so members' contents were 8-byte aligned or not depending on its size. The 64-bit Apple linker rejects misaligned members (`archive_members`).
- Mach-O AArch64: a branch with no addend that was the last instruction of a section was cut off by the relocation writer. Interface thunks end an object's code, so ld64 found a relocation outside the section (`thunk_last_in_section`).
- Mach-O AArch64: the relocation writer patched an `__eh_frame` PC-relative field through a pointer into the object buffer, then wrote the field's relocations to the same buffer. When that grew the buffer, the patch went to freed memory and the FDE kept its unpatched value, so it covered the wrong addresses. Apple's ld accepted it; `ld64.lld` rejects it ("invalid FDE relocation"). druntime had 13 such FDEs (`run.py` checks every FDE in the druntime it links with).
- DWARF EH on ELF uses PC-relative personality, LSDA and TType encodings. Debug info uses ABS32/ABS64 relocations.

Code generation:

- Struct copies: the destination pointer register could be the source pointer's (`struct_copy_recursive`). Copy loops left a stale constant in their index register (`struct_copy_loop_regs`). Copies to and from register-pair variables, tail stores, and memset store sizes and limits are fixed.
- Over-aligned frames rewrote every base register, not just x29, to SP (`overaligned_nested`). Stack alignment, `fixesp`, the epilog and local addressing for aligned frames are fixed.
- Stack arguments take 8-byte slots on Linux and Apple's packing on macOS (`c_abi_stack`). Enregistered stack parameters referenced by nested functions are loaded in the prolog (`stack_params_nested`). Prolog stores reach any offset.
- Narrow integers stay in canonical form after arithmetic, shifts, `neg`, `com`, `mul` and op-assign (`narrow_extend`):
  - LDRSB and LDRSH used the wrong register width;
  - a 64-bit constant was loaded 32-bit into a register variable;
  - widening loads used the wrong size.
- Integer and floating point painting of register variables: the x86 `XMMREGS` mask unregistered every variable in x16 to x31. Loads, stores and FMOV between the register classes are fixed (`paint_int_float`).
- HFAs of 2 elements in V0/V1 for arguments, returns and parameter spills; the MSW of pairs loaded from register variables (`hfa_pairs`, `register_pair_struct`).
- Floating point: compare operand swap, NaN-correct condition codes (`float_compare_nan`), constants loaded with FMOV/MOV, single-precision FMOV general, double-long conversions, `fmod` argument order and `%=`, mixed real/imaginary/complex add and subtract (`complex_mixed`). `real` is `double` in the back end tables and in array fills (`real_double`).
- `alloca` expanded inline without re-evaluating its argument; the macOS stack probe goes through the GOT (`alloca_inline`).
- Static data referenced directly is addressed with ADRP (`static_data_direct`).
- Variadic calls on macOS: D-linkage parameter order, the hidden `_arguments` of D-style variadics, typesafe variadics passed as a slice (`Eflags` shares its storage with `numParams`), and the last stack parameter aligned only for variadic calls (`variadics`).
- A field of a small struct held in a register was read as the whole register: such variables now stay in memory, since AArch64 has no sub-registers (`struct_field_in_register`).
- Load/store offsets that are misaligned and 256 or more, or too large for the scaled immediate, went through a broken x16 fallback that dropped the low 12 bits (`large_frame_offsets`).
- A register pair is zero only if both halves are: `is null`, `!a` and `if (a)` tested only the length (`array_is_null`).
- `x = -x` on a variable in memory negated into the wrong register (`neg_assign_divmod`).
- `++`/`--` of a register variable left its tracked constant valid (`postinc_register_constant`).
- `lazy` parameters were treated as passed by reference when their expression's type is larger than 16 bytes (`lazy_large_result`).
- `assert(encodeNImmrImms(...))` computed the encoding inside the assert, so release builds of DMD emitted `AND #1` for `AND #0xFF`.
- A struct passed in memory (one with a destructor or postblit, or a static array of such structs) was never copied to the outgoing argument area. The code took every `OPstrpar` for a zero-sized struct (`struct_param_memory`).
- Narrow integers reinterpreted between signed and unsigned were not extended to the new type: call results, parameters in their registers and register variables. AAPCS64 also leaves the upper bits of a narrow result unspecified. `REV16` swapped the upper halfword too (`narrow_paint`).
- Nested functions addressed their parent's stack parameters 16 bytes too high. The x86 frame bias (saved RBP and return address) was added to parameter offsets (`nested_stack_param`).
- The binary search of a `switch` (with `-O` and 4 or more cases) compared a case value that does not fit an immediate the wrong way round (`switch_binary_search`).
- String literals with the same bytes but different character sizes shared a symbol: `""w` and `""d` got the 1-byte terminator of `""`. The same pooling is in the x86 back end (`string_literal_sizes`).
- `-inline` can make a slice common subexpression that is reloaded only to set the flags (`s is null || s.length == 0`). The flags bit is one of the odd (MSW) register bits, so it was taken as the register for the high half, and register allocation failed with an assert (SIGTRAP in a release DMD; dcd's dsymbol hit it) (`cse_pair_flags`).
- The prolog's CFI took effect at 1 and 4 bytes into the function instead of after `STP` and `MOV x29,sp`. The CIE's code alignment factor is 1 (`prolog_cfi`).
- The driver: `-marm64` in `dmd.conf`'s DFLAGS made `dmd --version` report a change of architecture (`run.py` checks it).
- A result returned in memory had its address passed as a hidden first argument in x0, so C functions returning a struct over 16 bytes got their first argument in its place (`c_struct_return`).
- HFAs of 3 or 4 elements in C calls (`hfa_c_abi`, see above).
- The AArch64 inline assembler took over a template's `asm` tokens, so a second instance of a function template with an `asm` statement failed to parse (`betterc_atomics`).
- The driver: `-L-Wl,...` (how native packages name Apple frameworks) went to the linker behind `-Xlinker`; it now goes to `cc`, and the direct link splits it. Linux AArch64 links got Apple's `-arch arm64`, and its ImportC preprocessing `-m64`, which GCC for AArch64 rejects (`run.py` checks the first two, `importc_preprocess` the last).
- Smaller items:
  - x86 helper misdispatch (`getlvalue`), `getregs` given a register number instead of a mask;
  - the x86 scheduler and NOP running on AArch64;
  - CSE spill sizes, `OPremquo` size, `cdabs` condition, `cdnot` compare size;
  - thunk tail calls, `finally` blocks under DWARF EH, `log_imm` encodings;
  - the 16-byte limit on the scaled load/store offset assert.

druntime and Phobos:

- Atomics as naked D function templates in `core.internal.atomic` (load-acquire, store-release and exclusive loops; they were empty stubs), so `-betterC` programs link without druntime (`betterc_atomics`). `callWithStackShell` and `getStackTop` go through assembly helpers.
- `core.math` bodies for the x87-only intrinsics; the `test_runner` floating point control register asm is skipped under DMD.
- `std.math.hardware`: FPSR and FPCR access through C helpers under DMD AArch64.
- `std.conv`'s floating point parse rounds at every step, so with a 64-bit `real` it was one ulp off for decimal input such as `"0.7"`. Input whose mantissa has at most 53 bits and whose power of ten is at most 22 now takes Clinger's exact path, as strtod does. Longer input, such as `"1e-300"`, can still be one ulp off; LDC's Phobos behaves the same way.
- Tests whose thresholds assume an 80-bit `real` take LDC's thresholds for a 64-bit `real` (`std.complex`, `std.internal.math.gammafunction`). One `gammafunction` threshold also allows for glibc's `log1p`, which is 1 ulp from Apple's at that point.
