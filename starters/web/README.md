# flint:starter-web

This starter runs a REST application in one call. It binds configuration, starts the DI context, serves the controllers, and stops everything when the server stops (ADR-028 section 2).

```bash
flint add web
```

`flint add web` does three things:
- adds `"flint:starter-web" = {}` to `flint.toml`;
- appends the `[server]` section to `config/application.toml`;
- relocks.

## Use

```d
import flint.starter_web : ConfigurationProperties, Get, PathVariable, Provided, RestController, Result, Service,
    runApplication;

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
    return runApplication!(Provided!AppSettings, Greeter, GreetingController)(args);
}
```

- **One import.** `flint.starter_web` re-exports what a web application writes: the DI, web, configuration and validation attributes, and `Result`, `Error` and `Status`.
- **Beans.** These are the application's services, repositories and controllers, together with other starters' auto-configuration lists. Every `Provided!T` whose `T` is a `@ConfigurationProperties` struct is bound from `config/`, from one snapshot that includes `--set key=value` and `--profile name` arguments. A key that no type claims is an error naming the key.
- **Controllers.** Every `@RestController` among the beans is served.
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

- **Stopping:** SIGTERM stops the process without running `@PreDestroy` hooks, because `flint:os` dispatches only SIGINT today. SIGINT and the server's own shutdown do run them.
- **Worker threads:** each worker-thread controller has one thread, with 16 queued requests and an 8 MiB request arena.
