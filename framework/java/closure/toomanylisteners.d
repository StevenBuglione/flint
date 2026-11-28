module app;

import flint.java.util.toomanylistenersexception : TooManyListenersException;

@safe:

int main(string[] args)
{
    auto problem = args.length > 1 ? new TooManyListenersException(args[1]) : new TooManyListenersException;
    return cast(int)(problem.getMessage().length & 127);
}
