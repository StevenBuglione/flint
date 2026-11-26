module executorservice_probe;

import flint.java.util.concurrent.executorservice : ExecutorService, OffloadExecutorService;
import std.traits : Parameters;

@safe:

private alias Runnable = Parameters!(__traits(getOverloads, ExecutorService, "execute")[0])[0];

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
    auto host = new OffloadExecutorService(2);
    ExecutorService service = host;
    auto task = new Command;
    service.execute(task);

    if (args.length > 1)
    {
        auto pending = service.shutdownNow();
        return pending.size() == 1 && pending.get(0) is task && service.isTerminated() ? 0 : 1;
    }

    service.shutdown();
    const status = host.run();
    return status.code == 0 && service.isShutdown() && service.isTerminated()
        && task.result.length == 1 && task.result[0] == 7 ? 0 : 1;
}
