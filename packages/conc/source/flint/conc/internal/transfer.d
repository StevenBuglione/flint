module flint.conc.internal.transfer;

@safe:

package(flint.conc) template TransferValue(T)
{
    import flint.arena : Buffer;
    import std.traits : Fields, OriginalType, Unqual, isFloatingPoint, isIntegral, isStaticArray,
        hasElaborateAssign, hasElaborateCopyConstructor, hasElaborateDestructor, hasElaborateMove, hasIndirections;
    import std.meta : allSatisfy;

    alias V = Unqual!T;
    static if (is(V == Buffer))
        enum TransferValue = false;
    else static if (is(V == enum))
        enum TransferValue = TransferValue!(OriginalType!V);
    else static if (isIntegral!V || isFloatingPoint!V || is(V == bool))
        enum TransferValue = true;
    else static if (isStaticArray!V)
    {
        static if (is(V : E[N], E, size_t N))
            enum TransferValue = TransferValue!E;
        else
            enum TransferValue = false;
    }
    else static if (is(V == struct) && !hasIndirections!V)
        enum TransferValue = !hasElaborateAssign!V && !hasElaborateCopyConstructor!V
            && !hasElaborateDestructor!V && !hasElaborateMove!V && allSatisfy!(.TransferValue, Fields!V);
    else
        enum TransferValue = false;
}
