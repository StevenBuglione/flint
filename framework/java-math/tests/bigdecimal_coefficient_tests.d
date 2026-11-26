module flint.java.math.bigdecimal_coefficient_tests;

import flint.java.math.internal.decimalcoefficient : materializeCoefficient;
import flint.java.math.internal.decimalparse : DecimalParts, scanDecimal;

@safe:

@("BigDecimal coefficient materialization preserves signed digits and drops only punctuation and leading zeros")
unittest
{
    foreach (entry; [
            ["0.000E+22", "0"], ["-9223372036854775808", "-9223372036854775808"],
            ["9223372036854775808", "9223372036854775808"],
            ["-9223372036854775809", "-9223372036854775809"],
            ["+００009223372036.854775808E-99", "9223372036854775808"],
            ["-٠０1٢٣٤٥٦٧٨٩.000٠٠٠٠٠٠e2",
                "-123456789000000000"],
            [
                "+０001000000000.000000000000000000000000000E+111",
                "1000000000000000000000000000000000000"
            ],
            [
                ".00000000012345678901234567890123456789012345678000",
                "12345678901234567890123456789012345678000"
            ],
            [
                "999999999999999999999999999999999999999999999999999999999999999999",
                "999999999999999999999999999999999999999999999999999999999999999999"
            ]
        ])
    {
        DecimalParts parts;
        assert(scanDecimal(entry[0], parts), entry[0]);
        assert(materializeCoefficient(entry[0], parts).toString() == entry[1], entry[0]);
    }
}
