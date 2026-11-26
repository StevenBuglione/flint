module barrier_exception_probe;

import flint.java.util.concurrent.brokenbarrierexception : BrokenBarrierException;

@safe:

int main(string[] args)
{
    try
        throw new BrokenBarrierException(args.length > 1 ? args[1] : null);
    catch (BrokenBarrierException failure)
        return cast(int) failure.getMessage().length & 127;
}
