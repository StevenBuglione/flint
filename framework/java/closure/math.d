module app;

import flint.java.lang.math : Math;

@safe:

int main(string[] args)
{
    const n = cast(int) args.length;
    const d = cast(double) n + 0.5;
    const f = cast(float) n - 0.5f;
    const scaled = Math.scalb(Math.nextUp(Math.floor(d) + Math.ceil(d - 0.75) + Math.rint(d)), n - 2);
    const rounded = cast(long) Math.round(scaled);
    const high = Math.multiplyHigh(cast(long) n * 0x1_0000_0001L, rounded ^ 0x5555_5555_5555_5555L);
    const uhigh = Math.unsignedMultiplyHigh(high, Math.multiplyFull(Math.abs(-n), Math.max(n, 3)));
    const mix = Math.min(Math.getExponent(Math.ulp(scaled)), Math.getExponent(Math.ulp(Math.nextDown(f))));
    const angle = Math.toRadians(Math.toDegrees(Math.TAU / Math.PI));
    const sign = Math.round(Math.signum(Math.copySign(angle * Math.E, -d)));
    const step = Math.round(Math.nextAfter(f, -1.0));
    return cast(int)((uhigh ^ mix ^ sign ^ step ^ Math.round(Math.scalb(f, 1))) & 127);
}
