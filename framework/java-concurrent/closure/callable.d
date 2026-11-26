module callable_probe;

import flint.java.util.concurrent.callable : Callable;

@safe:

private final class ArgumentCount : Callable!int
{
    private int count;

    this(int count)
    {
        this.count = count;
    }

    override int call()
    {
        return count;
    }
}

pragma(inline, false) private int run(Callable!int task)
{
    return task.call();
}

int main(string[] args)
{
    return run(new ArgumentCount(cast(int) args.length)) & 127;
}
