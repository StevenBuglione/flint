module completionexception_probe;

import flint.java.util.concurrent.completionexception : CompletionException;

@safe:

int main(string[] args)
{
    auto cause = new Exception("failed");
    try
    {
        if (args.length > 2)
            throw new CompletionException(args[1], cause);
        if (args.length > 1)
            throw new CompletionException(args[1], null);
        throw new CompletionException(cause);
    }
    catch (CompletionException failure)
    {
        if (args.length > 1)
            return failure.getMessage() == args[1] && (args.length > 2 ? failure.getCause() is cause
                    : failure.getCause() is null) ? 0 : 1;
        return failure.getMessage() == "failed" && failure.getCause() is cause ? 0 : 1;
    }
}
