module app;

import flint.java.nio.doublebuffer : DoubleBuffer;
import flint.java.nio.floatbuffer : FloatBuffer;
import flint.java.nio.intbuffer : IntBuffer;
import flint.java.nio.longbuffer : LongBuffer;
import flint.java.nio.shortbuffer : ShortBuffer;

@safe:

int main(string[] args)
{
    const n = args.length;
    auto sb = ShortBuffer.allocate(4);
    sb.position(1).mark().put(cast(short) n).reset();
    auto sv = sb.slice().asReadOnlyBuffer();

    auto ib = IntBuffer.allocate(4);
    ib.position(1).mark().put(cast(int) n).reset();
    auto iv = ib.slice().asReadOnlyBuffer();

    auto lb = LongBuffer.allocate(4);
    lb.position(1).mark().put(cast(long) n).reset();
    auto lv = lb.slice().asReadOnlyBuffer();

    auto fb = FloatBuffer.allocate(4);
    fb.position(1).mark().put(cast(float) n).reset();
    auto fv = fb.slice().asReadOnlyBuffer();

    auto db = DoubleBuffer.allocate(4);
    db.position(1).mark().put(cast(double) n).reset();
    auto dv = db.slice().asReadOnlyBuffer();

    return (sv.get(0) & 31) + (iv.get(0) & 31) + cast(int)(lv.get(0) & 31) + (
            cast(int) fv.get(0) & 31) + (cast(int) dv.get(0) & 31) + sv.remaining() + iv.remaining()
        + lv.remaining() + fv.remaining() + dv.remaining();
}
