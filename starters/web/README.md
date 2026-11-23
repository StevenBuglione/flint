# flint:starter-web

This starter is a dependency bundle and the `[server]` section. As in Spring Boot, it holds no code (ADR-029 section 8). It brings:
- flint:web, flint:di, flint:config, flint:validate and flint:serde;
- `flint:boot`, the application runner;
- `flint:boot-autoconfigure-web`, whose `WebServerAutoConfiguration` binds `[server]`, serves the controllers and the front end, and answers `--openapi`.

```bash
flint add web
```

`flint add web` does three things:
- adds `"flint:starter-web" = {}` to `flint.toml`;
- appends the `[server]` section to `config/application.toml`;
- relocks.

## Use

```d
import flint.arena : Result;
import flint.boot : runApplication;
import flint.boot_autoconfigure_web : WebServerAutoConfiguration;
import flint.di : Provided, Service;
import flint.web : Get, PathVariable, RestController;

@Service final class Greeter { ... }

@RestController("/api/greetings")
struct GreetingController
{
    private Greeter greeter;
    this(Greeter greeter) { this.greeter = greeter; }

    @Get("/:name")
    Result!Message get(@PathVariable("name") string name) { ... }
}

int main(string[] args)
{
    return runApplication!(WebServerAutoConfiguration, Provided!AppSettings, Greeter, GreetingController)(args);
}
```

- **Imports:** the application imports the packages the starter brings directly, without declaring each one, as with a Spring Boot starter.
- **Configuration:** every `Provided!T` whose `T` is a `@ConfigurationProperties` struct is bound from `config/`, from one snapshot that includes `--set key=value` and `--profile name`. A key that no type claims is an error naming the key.
- **Controllers:** every `@RestController` among the beans is served.
- **Handlers need no attributes.** A controller whose handlers are all `nothrow @nogc` runs on the reactor. Any other controller runs on a worker thread, so it may allocate, throw (an exception becomes a 500) and call ordinary services. Path and query arguments may be `string`.

## Configuration: `[server]`

| Key | Default | Meaning |
| --- | --- | --- |
| `address` | `"127.0.0.1"` | Bind address |
| `port` | `8080` | TCP port |
| `cores` | `1` | HTTP reactor workers |
| `maxBodyBytes` (or `max_body_bytes`) | `1048576` | Largest request body |

## Front end: `[spa]`

```toml
[spa]
directory = "resources/static"   # the built front end
index = "index.html"             # served for client-side routes
```

- **Files:** each file is served by its path.
- **Client-side routes:** every other GET gets the index page.
- **The API:** paths under `/api/` that no controller matches stay 404.

## OpenAPI and a TypeScript client

```bash
flint openapi -o openapi.json --typescript web/src/api.ts
```

- **The document:** the application answers `--openapi` with the OpenAPI 3.1 document that flint:web generates from its controllers at compile time.
- **The client:** `flint openapi` names the document after `flint.toml`, and writes a typed `fetch` client with one method per operation.

## Exit codes

- 3: configuration did not bind. The message names the key.
- 4: a bean's constructor or `@PostConstruct` failed.
- Otherwise: the server's exit status.

## Example

`example/` is a complete application with a configured greeting, a service and a controller:

```bash
cd starters/web/example
flint run
curl localhost:8080/api/greetings/Ada
```

## Known limits

- **Stopping:** SIGTERM and SIGINT stop the process without running `@PreDestroy` hooks, because flint:web's run loop does not yet watch for signals. Only the server's own shutdown runs them.
- **Worker threads:** each worker-thread controller has one thread, with 16 queued requests and an 8 MiB request arena.
