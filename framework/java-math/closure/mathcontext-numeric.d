module app;

import flint.java.math.mathcontext : MathContext;

@safe:

int main(string[] args)
{
    const precision = cast(int) args.length - 1;
    auto context = new MathContext(precision, MathContext.DECIMAL64.getRoundingMode());
    return context.getPrecision() == precision && context.toString().length && context.hashCode() >= 0 ? 0 : 1;
}
