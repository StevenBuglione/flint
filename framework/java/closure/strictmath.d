module app;

import flint.java.lang.strictmath : StrictMath;

@safe:

int main(string[] args)
{
    const n = cast(int) args.length;
    const d = cast(double) n + 0.5;
    const f = cast(float) n - 0.5f;
    const rounded0 = StrictMath.floor(d) + StrictMath.ceil(d - 0.75) + StrictMath.rint(d);
    const scaled = StrictMath.scalb(StrictMath.nextUp(rounded0), n - 2);
    const rounded = cast(long) StrictMath.round(scaled);
    const high = StrictMath.multiplyHigh(cast(long) n * 0x1_0000_0001L, rounded ^ 0x5555_5555_5555_5555L);
    const prod = StrictMath.multiplyFull(StrictMath.abs(-n), StrictMath.max(n, 3));
    const uhigh = StrictMath.unsignedMultiplyHigh(high, prod);
    const e1 = StrictMath.getExponent(StrictMath.ulp(scaled));
    const e2 = StrictMath.getExponent(StrictMath.ulp(StrictMath.nextDown(f)));
    const mix = StrictMath.min(e1, e2);
    const angle = StrictMath.toRadians(StrictMath.toDegrees(StrictMath.TAU / StrictMath.PI));
    const sign = StrictMath.round(StrictMath.signum(StrictMath.copySign(angle * StrictMath.E, -d)));
    const step = StrictMath.round(StrictMath.nextAfter(f, -1.0));
    return cast(int)((uhigh ^ mix ^ sign ^ step ^ StrictMath.round(StrictMath.scalb(f, 1))) & 127);
}
