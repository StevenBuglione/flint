module workload;

import flint.engine.reactor : ReactorOptions;
import flint.java.lang.runnable : Runnable;

@safe:

/// Use the same bounded reactor settings in both probe arms.
ReactorOptions fixtureOptions() nothrow @nogc
{
    ReactorOptions options;
    options.cores = 1;
    options.fiberPoolSize = 2;
    options.maxConnectionsPerCore = 8;
    options.maxPendingIoPerCore = 8;
    options.offloadThreads = 1;
    options.offloadQueueCapacity = 2;
    options.mailboxCapacity = 2;
    return options;
}

/// Allocate a result on an offload thread for the driver to check.
final class Command : Runnable
{
    private int value;
    private int[] output;

    /// Set the value the worker must publish.
    this(int value)
    {
        this.value = value;
    }

    override void run()
    {
        output = new int[1];
        output[0] = value;
    }

    /// Check the value after the driver joins the worker.
    bool completed() const nothrow @nogc
    {
        return output.length == 1 && output[0] == value;
    }
}
