module app;

import flint.java.text.decimalformat : DecimalFormat;
import flint.java.text.decimalformatsymbols : DecimalFormatSymbols;

@safe:

int main(string[] args)
{
    const pattern = args.length > 1 ? args[1] : "#,##0.00";
    auto format = new DecimalFormat(pattern);
    const symbolLength = format.getDecimalFormatSymbols().getExponentSeparator().length;
    const valueLength = format.format(1_234_567).length;
    return cast(int)((format.toPattern().length + symbolLength + valueLength) & 127);
}
