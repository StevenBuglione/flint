/// Stack-backed accumulation for the erased Formatter and Unicode expansions.
module flint.java.util.internal.formatter_pieces;

@safe:
package(flint.java):

/++
Flint: the formatted pieces, gathered in a stack buffer and copied to the heap once at the end, instead of appended
one by one to a growing string (an array append per piece). The result is the same string; a text longer than the
buffer continues on the heap.
+/
struct Pieces
{
    private char[256] stack = void;
    private size_t used;
    private char[] heap;

    void put(scope const(char)[] piece) pure nothrow
    {
        if (heap is null && used + piece.length <= stack.length)
        {
            stack[used .. used + piece.length] = piece;
            used += piece.length;
            return;
        }
        if (heap is null)
            heap = stack[0 .. used].dup;
        heap ~= piece;
    }

    // The text; null when nothing was written, as the empty result was before.
    string text() const pure nothrow
    {
        if (heap !is null)
            return heap.idup;
        return used == 0 ? null : stack[0 .. used].idup;
    }
}
