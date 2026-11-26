// Regenerate tests/uuid-java21.tsv and tests/uuid-java21-order.tsv from Java SE 21.
// Run without arguments for the field corpus, or with --order for comparisons.
import java.util.Locale;
import java.util.UUID;

class UUIDOracle {
    public static void main(String[] args) {
        if (Runtime.version().feature() != 21)
            throw new IllegalStateException("Generate the corpus with Java SE 21");

        if (args.length == 1 && args[0].equals("--order")) {
            writeOrdering();
            return;
        }
        if (args.length != 0)
            throw new IllegalArgumentException("Use --order for UUID comparisons");

        long[] words = {0, 1, -1, Long.MIN_VALUE, Long.MAX_VALUE, 0x0123_4567_89ab_cdefL, 0xfedc_ba98_7654_3210L};
        for (long most : words)
            for (long least : words)
                write(most, least);

        for (long word : words)
            write((word & ~0xf000L) | 0x1000L, word);
        for (int version = 0; version < 16; ++version) {
            for (int variantNibble = 0; variantNibble < 16; ++variantNibble) {
                long most = 0x91a5_307b_ce48_0fd2L | ((long) version << 12);
                long least = 0x0738_21ba_1ced_f694L | ((long) variantNibble << 60);
                write(most, least);
            }
        }
    }

    private static void writeOrdering() {
        UUID[] values = {
            new UUID(0, 0), new UUID(0, 1), new UUID(0, -1),
            new UUID(0, Long.MIN_VALUE), new UUID(0, Long.MAX_VALUE),
            new UUID(Long.MIN_VALUE, Long.MAX_VALUE), new UUID(Long.MAX_VALUE, Long.MIN_VALUE),
            new UUID(-1, 1), new UUID(1, -1),
            new UUID(0x21d0_abcd_9827_1e23L, 0xbcd8_9281_00ac_9391L)
        };
        for (UUID left : values) {
            for (UUID right : values) {
                System.out.printf(Locale.ROOT, "%d\t%d\t%d\t%d\t%d\t%b\t%d\n",
                    left.getMostSignificantBits(), left.getLeastSignificantBits(),
                    right.getMostSignificantBits(), right.getLeastSignificantBits(),
                    left.compareTo(right), left.equals(right), left.hashCode());
            }
        }
    }

    private static void write(long most, long least) {
        UUID value = new UUID(most, least);
        System.out.printf(Locale.ROOT, "%d\t%d\t%d\t%d\t%s", value.getMostSignificantBits(),
            value.getLeastSignificantBits(), value.version(), value.variant(), value);
        if (value.version() == 1)
            System.out.printf(Locale.ROOT, "\t%d\t%d\t%d", value.timestamp(), value.clockSequence(), value.node());
        System.out.print('\n');
    }
}
