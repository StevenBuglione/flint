module app;

import flint.java.util.nosuchelementexception : NoSuchElementException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new NoSuchElementException(args[1]);
    }
    catch (NoSuchElementException error)
    {
        return cast(int) error.getMessage().length & 127;
    }
    return 0;
}
