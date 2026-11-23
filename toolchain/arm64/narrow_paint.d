// Narrow integers stay sign or zero extended for their type in registers. That breaks
// when a value is reinterpreted between signed and unsigned (a call result, a parameter
// or a register variable), and after REV16, which also swaps the upper halfword.
import core.bitop : byteswap;
ushort retU(ushort x) { return cast(ushort)(x | 0x8000); }
ubyte retUB(ubyte x) { return cast(ubyte)(x | 0x80); }
short retS(short x) { return cast(short)(x | 0x8000); }
pragma(inline, false) short paintCall(ushort x) { return cast(short) retU(x); }
pragma(inline, false) byte paintCallB(ubyte x) { return cast(byte) retUB(x); }
pragma(inline, false) ushort paintCallS(short x) { return cast(ushort) retS(x); }
pragma(inline, false) short paintVar(ushort x) { ushort u = cast(ushort)(x + 1); short s = cast(short) u; return s; }
pragma(inline, false) int widenPaint(ushort x) { ushort u = cast(ushort)(x * 2); return cast(short) u; }
pragma(inline, false) int widenPaintU(short x) { short u = cast(short)(x * 2); return cast(ushort) u; }
pragma(inline, false) bool cmpPaint(ushort a, short b) { return cast(short) a == b; }

pragma(inline, false) short swapS(short x) { return cast(short) byteswap(cast(ushort) x); }

int main()
{
    if (paintCall(1) != cast(short) 0x8001) return 1;
    if (paintCall(1) >= 0) return 2;
    if (paintCallB(1) != cast(byte) 0x81) return 3;
    if (paintCallS(1) != 0x8001) return 4;
    if (paintVar(0x8000) != cast(short) 0x8001) return 5;
    if (widenPaint(0x4000) != -32768) return 6;
    if (widenPaintU(0x4000) != 0x8000) return 7;
    if (!cmpPaint(0x8000, short.min)) return 8;
    if (byteswap(cast(ushort) 0x0080) != 0x8000) return 9;
    if (swapS(swapS(short.min)) != short.min) return 10;
    if (swapS(0x0080) != short.min) return 11;
    return 0;
}
