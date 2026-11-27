module app;

import flint.java.nio.charset.codermalfunctionerror : CoderMalfunctionError;
import flint.java.nio.charset.coderresult : CoderResult;

@safe:

int main(string[] args)
{
    try
    {
        const mode = args.length % 6;
        if (mode == 0)
            return cast(int) CoderResult.UNDERFLOW.toString().length;
        if (mode == 1)
            return cast(int) CoderResult.OVERFLOW.toString().length;
        if (mode == 2)
        {
            auto malformed = CoderResult.malformedForLength(cast(int) args.length);
            return malformed.isMalformed() ? malformed.length() + cast(int) malformed.toString().length : 0;
        }
        if (mode == 3)
        {
            auto unmappable = CoderResult.unmappableForLength(cast(int) args.length);
            return unmappable.isUnmappable() ? unmappable.length() + cast(int) unmappable.toString().length : 0;
        }
        if (mode == 4)
            return CoderResult.UNDERFLOW.length();
        throw new CoderMalfunctionError(new Exception(args[0]));
    }
    catch (CoderMalfunctionError error)
    {
        return error.getCause() is null ? 3 : 4;
    }
    catch (Exception error)
    {
        return error.msg is null ? 1 : 2;
    }
}
