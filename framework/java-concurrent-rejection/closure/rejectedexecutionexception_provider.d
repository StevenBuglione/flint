module rejectedexecutionexception_provider;

import flint.java.lang : RuntimeException;

@safe:

int main(string[] args)
{
    auto cause = new Exception("rejected");
    try
    {
        if (args.length > 1)
            throw new RuntimeException(args[1], cause);
        throw new RuntimeException(cause);
    }
    catch (RuntimeException failure)
    {
        return failure.getCause() is cause ? 0 : 1;
    }
}
