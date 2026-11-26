module timeout_probe;

import flint.java.util.concurrent.timeoutexception : TimeoutException;

@safe:

int main(string[] args)
{
    try
        throw new TimeoutException(args.length > 1 ? args[1] : null);
    catch (TimeoutException failure)
        return cast(int) failure.getMessage().length & 127;
}
