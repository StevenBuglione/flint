// Regenerate tests/uuid-java21.tsv from the public Java SE 21 UUID API.
import java.util.Locale;
import java.util.UUID;

class UUIDOracle {
    public static void main(String[] args) {
        if (Runtime.version().feature() != 21)
            throw new IllegalStateException("Generate the corpus with Java SE 21");

        long[] words = {0, 1, -1, Long.MIN_VALUE, Long.MAX_VALUE, 0x0123_4567_89ab_cdefL, 0xfedc_ba98_7654_3210L};
        for (long most : words)
            for (long least : words)
                write(most, least);

        for (int version = 0; version < 16; ++version) {
            for (int variantNibble = 0; variantNibble < 16; ++variantNibble) {
                long most = 0x91a5_307b_ce48_0fd2L | ((long) version << 12);
                long least = 0x0738_21ba_1ced_f694L | ((long) variantNibble << 60);
                write(most, least);
            }
        }
    }

    private static void write(long most, long least) {
        UUID value = new UUID(most, least);
        System.out.printf(Locale.ROOT, "%d\t%d\t%d\t%d\t%s\n", value.getMostSignificantBits(),
            value.getLeastSignificantBits(), value.version(), value.variant(), value);
    }
}
