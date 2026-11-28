module future_provider;

import flint.java.lang : IllegalStateException;
import flint.java.util.concurrent : TimeUnit;
import flint.java.util.concurrent.executionexception : ExecutionException;

@safe:

private final class Station
{
    private int mode;

    this(int mode) pure nothrow @nogc
    {
        this.mode = mode;
    }

    bool cancel(bool mayInterruptIfRunning) pure nothrow @nogc
    {
        return !mayInterruptIfRunning && !isDone();
    }

    bool isCancelled() pure nothrow @nogc
    {
        return mode == 3;
    }

    bool isDone() pure nothrow @nogc
    {
        return mode != 0;
    }

    int get()
    {
        return mode * 7;
    }

    int get(long timeout, TimeUnit unit)
    {
        return get() + cast(int) timeout + cast(int) unit;
    }

    int resultNow()
    {
        if (!isDone())
            throw new IllegalStateException("Task has not completed");
        if (isCancelled())
            throw new IllegalStateException("Task was cancelled");
        try
            return get();
        catch (ExecutionException failure)
            throw new IllegalStateException("Task completed with exception", failure);
    }

    Throwable exceptionNow()
    {
        if (!isDone())
            throw new IllegalStateException("Task has not completed");
        if (isCancelled())
            throw new IllegalStateException("Task was cancelled");
        try
            get();
        catch (ExecutionException failure)
            return failure.getCause();
        throw new IllegalStateException("Task completed with a result");
    }

    int state()
    {
        if (isCancelled())
            return 3;
        if (isDone())
        {
            try
                get();
            catch (ExecutionException failure)
                return 2;
            return 1;
        }
        return 0;
    }
}

int main(string[] args)
{
    const mode = args.length % 4;
    Station stage = new Station(mode);
    try
    {
        if (stage.state() == 0)
            return stage.resultNow;
        return stage.resultNow + stage.get(1, TimeUnit.SECONDS);
    }
    catch (Exception failure)
    {
        try
            return stage.exceptionNow() is null;
        catch (Exception inner)
            return 1 + mode;
    }
}
