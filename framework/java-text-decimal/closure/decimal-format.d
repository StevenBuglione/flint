module app;

import flint.java.text.decimalformat : DecimalFormat;

@safe:

int main(string[] args)
{
    auto format = new DecimalFormat("0");
    return (cast(int) format.format(args.length).length) & 127;
}
