module app;

import flint.java.lang.runnable : Runnable;

@safe:

private final class Task : Runnable
{
    int value;
    int observed;

    override void run()
    {
        observed = value;
    }
}

int main(string[] args)
{
    auto task = new Task();
    task.value = cast(int) args.length & 127;
    Runnable action = task;
    action.run();
    return task.observed;
}
