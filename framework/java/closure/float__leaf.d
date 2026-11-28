module app;

import flint.java.lang.float_ : Float;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "1.5";
    const f = Float.parseFloat(arg);
    const text = Float.toString(f);
    const hex = Float.toHexString(f);
    const bits = Float.floatToIntBits(f);
    const back = Float.intBitsToFloat(bits);
    const order = Float.compare(f, back) ^ Float.compare(Float.NaN, Float.NaN);
    const hash = Float.hashCode(f);
    const sum = Float.sum(f, back);
    const max = Float.max(f, back);
    const min = Float.min(f, back);
    const flags = (Float.isNaN(f) ? 1 : 0) + (Float.isInfinite(f) ? 2 : 0) + (Float.isFinite(f) ? 4 : 0);
    const half = Float.floatToFloat16(f);
    const widened = Float.float16ToFloat(half);
    return cast(int)((text.length ^ hex.length ^ order ^ hash ^ cast(int) sum ^ cast(int) max ^ cast(
            int) min ^ flags ^ Float.floatToIntBits(widened)) & 127);
}
