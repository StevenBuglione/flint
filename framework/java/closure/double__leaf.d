module app;

import flint.java.lang.double_ : Double;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "1.5";
    const d = Double.parseDouble(arg);
    const text = Double.toString(d);
    const hex = Double.toHexString(d);
    const bits = Double.doubleToLongBits(d);
    const back = Double.longBitsToDouble(bits);
    const order = Double.compare(d, back) ^ Double.compare(Double.NaN, Double.NaN);
    const hash = Double.hashCode(d);
    const sum = Double.sum(d, back);
    const max = Double.max(d, back);
    const min = Double.min(d, back);
    const flags = (Double.isNaN(d) ? 1 : 0) + (Double.isInfinite(d) ? 2 : 0) + (Double.isFinite(d) ? 4 : 0);
    const folded = text.length ^ hex.length ^ order ^ hash;
    const extremes = cast(int) sum ^ cast(int) max ^ cast(int) min;
    return cast(int)((folded ^ extremes ^ flags) & 127);
}
