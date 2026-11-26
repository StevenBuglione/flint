/// Column-wise multiplication of little-endian unsigned words.
module flint.java.math.internal.products;

@safe:

package(flint.java.math):

/// Multiply two nonempty magnitudes into a destination with room for both lengths.
void multiplyLimbs(scope uint[] product, scope const(uint)[] left, scope const(uint)[] right) pure nothrow @nogc
{
    assert(left.length && right.length && product.length == left.length + right.length);
    ulong carry;
    foreach (column, ref word; product[0 .. $ - 1])
    {
        const size_t first = column < right.length ? 0 : column - right.length + 1;
        const size_t end = column < left.length ? column + 1 : left.length;
        ulong sum = carry;
        uint overflow;
        foreach (i; first .. end)
        {
            const ulong before = sum;
            sum += cast(ulong) left[i] * right[column - i];
            overflow += sum < before;
        }
        word = cast(uint) sum;
        // The accumulator spans 96 bits. Carry the upper two words to the next column.
        carry = (cast(ulong) overflow << 32) | (sum >> 32);
    }
    product[$ - 1] = cast(uint) carry;
}
