# gs-rest-service, ported to Flint

This is the Flint side of the gs-rest-service side-by-side application (`benchmarks/spring/README.md`). The guide's three Java files are ported here under the rulebook, with Java → D syntax changes only. Each file's header names its upstream path at commit `e15fec6`.

## Status

This is a skeleton. Proof-harness wrote it for work-queue item 14 (`docs/spring/phase1/coordination.md`), and boot may rework it under item 3.

What it needs to pass the suite:
1. **It must build.** That needs Boot's servlet web server auto-configuration and the Flint AOT build of a Boot application. `flint-spring.json`'s commands are the harness's expectations, and are replaced by what `flint build` offers then.
2. **Spring MVC's `/error` handling** (Boot's `BasicErrorController`). web-http's servlet proof (`framework/engine-servlet/proof/gs-rest-service`) serves the same controller and passes 12 of the 18 cases in exact wire mode. The other six are the JSON and Whitelabel 404 bodies and the 405 and 406 responses that go through `/error`.

To score it, or any build of it:

```bash
python3 tools/spring_bench.py accept gs-rest-service --impl flint
python3 tools/spring_bench.py accept gs-rest-service --start '<binary>' --url http://127.0.0.1:<port>
```

The binary reads its port from `SERVER_PORT`.
