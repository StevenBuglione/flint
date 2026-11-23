# flint:starter-actuator

This starter is a dependency bundle and the `[management]` section, and holds no code (ADR-029 section 8). It brings flint:actuator and `flint:boot-actuator`. Its `ActuatorAutoConfiguration` serves health, readiness and Prometheus metrics on the application's own server, and exports to OTLP when configured.

```bash
flint add web actuator
```

`flint add web actuator` does three things:
- adds `"flint:starter-actuator" = {}` to `flint.toml`;
- appends the `[management]` section to `config/application.toml`;
- relocks.

## Use

With `flint:starter-web` and this starter declared, `@FlintApplication` picks up `ActuatorAutoConfiguration`:

```d
import flint.boot : FlintApplication, FlintMain;
import flint.boot_actuator : Counter, Observability;
import flint.web : Post, RestController;

@RestController("/api/jobs")
struct JobController
{
    private Observability observability;
    private Counter accepted;

    this(Observability observability)
    {
        this.observability = observability;
        accepted = observability.registry().counter("jobs_accepted_total", "Jobs accepted").value;
    }

    @Post("")
    Result!Accepted accept() { observability.registry().add(accepted); ... }
}

@FlintApplication
final class StatusApplication
{
    static int main(string[] args)
    {
        return FlintApplication.run!StatusApplication(args);
    }
}

mixin FlintMain!StatusApplication;
```

The endpoints are:

| Path | Answer |
| --- | --- |
| `/actuator/health/live` | `{"status":"UP"}` while the process runs |
| `/actuator/health/ready` | `UP` until shutdown starts, and after the application's health probes pass |
| `/actuator/metrics` | Prometheus text: the application's counters and histograms, and the exporter's own |

## Configuration: `[management]`

| Key | Default | Meaning |
| --- | --- | --- |
| `path_prefix` | `"/actuator"` | Where the endpoints live |
| `service_name` | `"flint"` | OTLP resource service name |
| `otlp_endpoint` | empty | OTLP/HTTP base URL; empty records locally only |
| `max_metric_series` | `4096` | Upper bound on metric series |

The actuator serves only on a loopback listener unless a `ManagementPolicy` authorizes requests.

## Example

`example/` is a job API whose accepted jobs appear in `/actuator/metrics`:

```bash
cd starters/actuator/example
flint run
curl -X POST localhost:8080/api/jobs
curl localhost:8080/actuator/metrics
```
