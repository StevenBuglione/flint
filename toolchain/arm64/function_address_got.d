// The address of a function defined in a shared library comes from the GOT.
import core.stdc.stdio : puts;
extern (C) int getnameinfo(const(void)*, uint, char*, uint, char*, uint, int);
__gshared typeof(&getnameinfo) gp;

int main()
{
    gp = &getnameinfo;
    auto p = &puts;
    return gp !is null && p !is null ? 0 : 1;
}
