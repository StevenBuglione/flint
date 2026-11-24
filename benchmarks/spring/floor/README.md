# Floor references (diagnostic, never evidence)

Each directory here is a Flint project that serves one Phase 1 request with as little of the framework as possible:
the floor that the default app's CPU per request is compared against (the floor-reference diagnostic, petclinic CPU
plan 3df9a1c5). A reference sends the same statements and the same response bytes as the app it shadows.

| Directory | Shadows | Arms (`FLOOR_ARM`) |
|---|---|---|
| `petclinic-owner1` | petclinic-rest `GET /petclinic/api/owners/{id}` | `minimal` (default): rows written straight to the response; `mapped`: petclinic's entities, `OwnerMapperImpl` and Boot's `JsonMapper` |

## The launcher contract

A reference starts as its app's Flint port does, so the benchmark launcher runs it unchanged:

- its port comes from `SERVER_PORT`, its database from `POSTGRES_URL`, `POSTGRES_USER` and `POSTGRES_PASS`;
- its working directory is the shadowed app's own (`benchmarks/spring/flint/<app>`), where it finds that app's
  resources (it also runs from its own directory);
- it serves on every CPU of its affinity mask, at most 16, as the servlet engine does for `server.flint.threads=0`;
- SIGTERM stops it.

The launcher is `tools/spring_diag.py` with a prebuilt binary. It pins the server, load generator and PostgreSQL to the
CPUs of `policy/spring-http-benchmark.json` (`load_bench.spring_server`), and gives each launch a fresh database:

```bash
flint build -C benchmarks/spring/floor/petclinic-owner1 --profile release
python3 tools/spring_diag.py --app petclinic-rest --impl flint --counters \
    --flint-binary benchmarks/spring/floor/petclinic-owner1/.flint/build/release/petclinic-floor \
    --env FLOOR_ARM=mapped --output <file>.json
```

`--env` values are recorded in the result's `binaries` row, so each arm's output names its arm. A new reference
follows the same contract and adds a row to the table above.
