module app;

import flint.java.math.mathcontext : MathContext;

@safe:

int main(string[] args)
{
    const text = args.length > 1 ? args[1] : "precision=٧ roundingMode=HALF_EVEN";
    auto context = new MathContext(text);
    const rendered = context.toString();
    return context.equals(new MathContext(rendered)) ? 0 : 1;
}
