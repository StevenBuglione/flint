// A position-independent D library with thread-local variables, loaded with dlopen. -fPIC code addresses TLS with
// initial-exec (through the GOT), which glibc serves from the static TLS block's surplus: loading works, or fails
// loudly with "cannot allocate memory in static TLS block". It never runs with wrong addresses (README, known limits).
import core.stdc.string : strstr;
import core.sys.posix.dlfcn : dlerror, dlopen, dlsym, RTLD_NOW;

int main()
{
    auto library = dlopen("libdlopen_tls.so", RTLD_NOW);
    if (!library)
    {
        auto error = dlerror();
        return error && strstr(error, "static TLS") ? 0 : 1;
    }
    auto bump = cast(int function() nothrow @nogc) dlsym(library, "bump");
    auto blockSum = cast(int function() nothrow @nogc) dlsym(library, "blockSum");
    if (!bump || !blockSum)
        return 2;
    return bump() == 1 && bump() == 2 && blockSum() == 10 ? 0 : 3;
}
