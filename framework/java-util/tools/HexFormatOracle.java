// Generate tests/hexformat-java21.tsv with Java SE 21.
import java.util.HexFormat;
import java.util.Locale;

class HexFormatOracle {
    public static void main(String[] args) {
        if (Runtime.version().feature() != 21)
            throw new IllegalStateException("Generate the corpus with Java SE 21");

        for (HexFormat format : new HexFormat[] {HexFormat.of(), HexFormat.of().withUpperCase()}) {
            for (long value : new long[] {0, 1, -1, 0x80, 0xF0, Long.MIN_VALUE, Long.MAX_VALUE,
                                          0xA13C_29D8_EF4B_7650L, 0x0000_0000_0000_D800L}) {
                for (int width = 0; width <= 16; ++width) {
                    System.out.printf(Locale.ROOT, "%b\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%c\t%c\t[%s]\n",
                        format.isUpperCase(), value, width, format.toHexDigits((byte) value),
                        format.toHexDigits((char) value), format.toHexDigits((short) value),
                        format.toHexDigits((int) value), format.toHexDigits(value),
                        format.toHighHexDigit((int) value), format.toLowHexDigit((int) value),
                        format.toHexDigits(value, width));
                }
            }
        }
    }
}
