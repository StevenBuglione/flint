module app;

import flint.java.nio.invalidmarkexception : InvalidMarkException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new InvalidMarkException;
        return 0;
    }
    catch (InvalidMarkException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
