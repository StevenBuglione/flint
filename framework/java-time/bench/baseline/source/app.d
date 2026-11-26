module app;

import core.stdc.stdio : fputc, stdout;

@safe:

int main(string[] args)
{
    if (args.length > 5)
    {
        const minimum = cast(long) args[1].length;
        const maximum = minimum + cast(long) args[2].length + cast(long) args[3].length + cast(long) args[4].length;
        const value = cast(long) args[5].length;
        return value >= minimum && value <= maximum && maximum <= int.max ? 0 : 1;
    }

    foreach (c; args.length > 1 ? "P1Y3D\n" : "P7Y1M1D\n")
        fputc(c, stdout);
    return 0;
}
