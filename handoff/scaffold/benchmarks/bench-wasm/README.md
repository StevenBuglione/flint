# bench-wasm

This benchmark uses the same persistent signal graph, bounded command buffer and checked JavaScript driver as the golden browser application. It exercises actual Flint implementations when Milestone 4 is complete. The handoff typechecks the API usage; it does not substitute a standalone ABI probe for the framework runtime.

From the implementation repository root:

```sh
python3 benchmarks/bench-wasm/build.py --ldc ldc2 --profile Oz --output build/bench-wasm.wasm
node tests/wasm/run.mjs build/bench-wasm.wasm
```

The runtime test covers initialization, repeated frames, changed and unchanged state, rejected input and memory growth. The build measurement manifest supplies the same four exported functions as `source/flint_demo/sys/exports.d`. Both O3 and Oz artifacts are measured, including deterministic gzip size. WASM edited-source timings are full recompiles because this build has no incremental compiler cache.

For an interactive browser run, execute `python3 build.py --ldc ldc2 --profile Oz` from this directory and serve it with `python3 -m http.server 8000 --bind 127.0.0.1`. For the independent preparation-only ABI/toolchain smoke, run `python3 handoff/tools/verify_wasm.py --ldc /path/to/ldc2 --node /path/to/node` from the implementation root.
