module cancellationexception_provider;

import flint.java.lang : IllegalStateException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new IllegalStateException(args[1]);
        throw new IllegalStateException;
    }
    catch (IllegalStateException failure)
    {
        const message = failure.getMessage();
        return args.length > 1 ? (message == args[1] ? 0 : 1) : (message is null ? 0 : 1);
    }
}
