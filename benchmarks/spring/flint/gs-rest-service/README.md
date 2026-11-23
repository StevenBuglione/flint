# gs-rest-service, ported to Flint

This is the Flint side of the gs-rest-service side-by-side application (`benchmarks/spring/README.md`): the guide's `complete/` project (commit `e15fec6`) as a Flint Boot application. `RestServiceApplication`, `Greeting` and `GreetingController` are in `src/com/example/restservice/package.d`, one module for the guide's one Java package (rulebook R1); `flint.toml`'s `base-package` keeps Spring's package as the module root.

## Build and score

```bash
flint build --profile release
python3 tools/spring_bench.py accept gs-rest-service --impl flint
python3 tools/spring_bench.py accept gs-rest-service --start '<binary>' --url http://127.0.0.1:<port>
```

`flint build` runs Flint AOT over the application and the auto-configurations its starters list, then links the servlet web server. The binary reads its port from `SERVER_PORT`. The servlet engine needs the pinned llhttp; until native packages reach `flint build`, link it locally with the native block that engine-servlet's socket tests use (never committed).

## Status

All 18 cases pass in exact wire mode (2026-11-23: `spring_bench.py accept gs-rest-service --impl flint`, LDC release build, main `3d49760`). The Whitelabel page's `Content-Language: en-US` comes from `DispatcherServlet.render` through `AcceptHeaderLocaleResolver` and `ServletResponse.setLocale`. Design notes are in `docs/spring/phase1/boot.md`, "gs-rest-service: the port".
