module completionexception_provider;

import flint.java.lang : RuntimeException;

@safe:

int main(string[] args)
{
    auto cause = new RuntimeException("failed");
    try
    {
        if (args.length > 2)
            throw new RuntimeException(args[1], cause);
        if (args.length > 1)
            throw new RuntimeException(args[1], null);
        throw new RuntimeException(cause);
    }
    catch (RuntimeException failure)
    {
        if (args.length > 1)
            return failure.getMessage() == args[1] && (args.length > 2 ? failure.getCause() is cause
                    : failure.getCause() is null) ? 0 : 1;
        return failure.getMessage() == "failed" && failure.getCause() is cause ? 0 : 1;
    }
}
