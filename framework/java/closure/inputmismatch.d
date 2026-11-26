module app;

import flint.java.util.inputmismatchexception : InputMismatchException;

@safe:

int main(string[] args)
{
    auto mismatch = args.length > 1 ? new InputMismatchException(args[1]) : new InputMismatchException;
    return cast(int)(mismatch.getMessage().length & 127);
}
