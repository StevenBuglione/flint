module app;

import flint.java.nio.byteorder : ByteOrder;

@safe:

int main(string[] args)
{
    const mode = args.length % 3;
    if (mode == 0)
        return cast(int)(ByteOrder.nativeOrder().toString().length);
    auto order = mode == 1 ? ByteOrder.BIG_ENDIAN : ByteOrder.LITTLE_ENDIAN;
    return cast(int)(order.toString().length);
}
