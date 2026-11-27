module app;

import flint.java.lang : IndexOutOfBoundsException;

@safe:

int main(string[] args)
{
    try
    {
        if (args.length > 1)
            throw new IndexOutOfBoundsException(1);
        return 0;
    }
    catch (IndexOutOfBoundsException exception)
    {
        return exception.getMessage() is null ? 1 : 2;
    }
}
