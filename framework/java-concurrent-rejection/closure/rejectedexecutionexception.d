module rejectedexecutionexception_probe;

import flint.java.util.concurrent.rejectedexecutionexception : RejectedExecutionException;

@safe:

int main(string[] args)
{
    auto cause = new Exception("rejected");
    try
    {
        if (args.length > 1)
            throw new RejectedExecutionException(args[1], cause);
        throw new RejectedExecutionException(cause);
    }
    catch (RejectedExecutionException failure)
    {
        return failure.getCause() is cause ? 0 : 1;
    }
}
