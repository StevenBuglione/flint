module app;

import flint.java.lang.negativearraysizeexception : NegativeArraySizeException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new NegativeArraySizeException(args[1]);
    }
    catch (NegativeArraySizeException error)
    {
        return cast(int) error.getMessage().length & 127;
    }
    return 0;
}
