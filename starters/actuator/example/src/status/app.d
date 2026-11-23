/// status: a service with health, readiness and metrics endpoints, and one counted operation.
module status.app;

import flint.arena : Result;
import flint.boot : FlintApplication, FlintMain;
import flint.boot_actuator : Counter, Observability;
import flint.engine.web : Post, RestController;

@safe:

/// Accepted work.
struct Accepted
{
    /// How many jobs have been accepted.
    ulong total;
}

/// POST /api/jobs counts accepted jobs in `jobs_accepted_total`.
@RestController("/api/jobs")
struct JobController
{
    private Observability observability;
    private Counter accepted;
    private ulong total;

    /// Register the counter.
    this(Observability observability)
    {
        this.observability = observability;
        accepted = observability.registry().counter("jobs_accepted_total", "Jobs accepted").value;
    }

    /// Accept a job.
    @Post("")
    Result!Accepted accept()
    {
        observability.registry().add(accepted);
        return Result!Accepted(Accepted(++total));
    }
}

/// The application.
@FlintApplication
final class StatusApplication
{
    /// Start the application.
    static int main(string[] args)
    {
        return FlintApplication.run!StatusApplication(args);
    }
}

mixin FlintMain!StatusApplication;
