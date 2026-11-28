module flint.java.util.concurrent.scheduledexecutorservice_probe;

import flint.conc.park : park;
import flint.java.util.concurrent.scheduledexecutorservice : OffloadScheduledExecutorService,
    ScheduledExecutorService, ScheduledTimeUnit;
import std.traits : Parameters;

@safe:

// The probe imports only its own leaf; it names the inherited Runnable and TimeUnit through the leaf's API and the
// package-scoped alias, never by importing their leaves.
private alias Runnable = Parameters!(__traits(getOverloads, ScheduledExecutorService, "execute", true)[0])[0];

private final class Command : Runnable
{
    int[] result;

    override void run()
    {
        result = [7];
    }
}

int main(string[] args)
{
    ScheduledExecutorService service = new OffloadScheduledExecutorService;
    auto command = new Command;
    auto periodic = service.scheduleAtFixedRate(command, 0, 1, ScheduledTimeUnit.MILLISECONDS);
    shared uint idle;
    park(idle, 0, 20_000_000L);
    periodic.cancel(false);
    if (command.result.length != 1)
        return 1;

    auto future = service.schedule(command, args.length == 1 ? 1 : 0, ScheduledTimeUnit.init);

    if (args.length > 1)
    {
        auto pending = service.shutdownNow();
        return pending.size() == 1 && pending.get(0) is command ? 0 : 1;
    }

    try
        future.get(5_000_000_000L, ScheduledTimeUnit.init);
    catch (Exception)
        return 1;
    service.shutdown();
    return command.result.length == 1 && command.result[0] == 7 ? 0 : 1;
}
