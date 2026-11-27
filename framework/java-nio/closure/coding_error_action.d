module app;

import flint.java.nio.charset.codingerroraction : CodingErrorAction;

@safe:

int main(string[] args)
{
    const mode = args.length % 3;
    auto action = mode == 0 ? CodingErrorAction.REPORT : mode == 1 ? CodingErrorAction.IGNORE
        : CodingErrorAction.REPLACE;
    return cast(int)(action.toString().length);
}
