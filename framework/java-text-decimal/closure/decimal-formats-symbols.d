module app;

import flint.java.text.decimalformatsymbols : DecimalFormatSymbols;

@safe:

int main(string[] args)
{
    const symbols = DecimalFormatSymbols.getInstance();
    return (cast(int) symbols.getZeroDigit() + args.length) & 127;
}
