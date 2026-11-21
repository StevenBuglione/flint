/// Non-recoverable failure for a violated storage lifetime.
module flint.arena.sys.borrow;

@safe:

package(flint.arena) void haltActiveBorrow() nothrow @nogc
{
    version (WebAssembly)
    {
        import ldc.intrinsics : llvm_trap;

        llvm_trap();
    }
    else
    {
        import core.stdc.stdlib : abort;

        abort();
    }
}
