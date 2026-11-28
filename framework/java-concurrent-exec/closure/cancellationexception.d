module cancellationexception_probe;

import flint.java.util.concurrent.cancellationexception : CancellationException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new CancellationException(args[1]);
        throw new CancellationException;
    }
    catch (CancellationException failure)
    {
        const message = failure.getMessage();
        return args.length > 1 ? (message == args[1] ? 0 : 1) : (message is null ? 0 : 1);
    }
}
