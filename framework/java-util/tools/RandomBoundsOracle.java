// Generate tests/random-bounds-java21.tsv with Java SE 21.
// Each row is: kind, seed, param1, param2, comma-separated raw result bits.
// Integer and long results are unsigned hexadecimal of their bits; double
// results are the unsigned hexadecimal of Double.doubleToRawLongBits.
import java.util.Locale;
import java.util.Random;

class RandomBoundsOracle {
    private static final int DRAWS = 12;

    public static void main(String[] args) {
        if (Runtime.version().feature() != 21)
            throw new IllegalStateException("Generate the corpus with Java SE 21");

        long[] seeds = {0, 1, -1, 42, 123456789, Long.MIN_VALUE, Long.MAX_VALUE,
                        0x5DEECE66DL, -987654321L, 987654321L};

        int[] intBounds = {1, 2, 3, 4, 5, 7, 8, 10, 16, 31, 32, 100, 1000, 65536,
                           1 << 30, (1 << 30) + 1, Integer.MAX_VALUE};
        for (long seed : seeds)
            for (int bound : intBounds)
                emitIntBound(seed, bound);

        int[][] intRanges = {{0, 1}, {1, 2}, {-5, 5}, {-100, 100}, {0, 7}, {3, 10},
                             {Integer.MIN_VALUE, Integer.MAX_VALUE - 1},
                             {-2147483648, 2147483647}, {0, (1 << 30) + 1},
                             {-65536, 65536}};
        for (long seed : seeds)
            for (int[] range : intRanges)
                emitIntRange(seed, range[0], range[1]);

        long[] longBounds = {1, 2, 3, 4, 7, 10, 1000, (1L << 40) + 1L, Long.MAX_VALUE,
                             (Long.MAX_VALUE / 2) + 1L, 0x5DEECE66DL};
        for (long seed : seeds)
            for (long bound : longBounds)
                emitLongBound(seed, bound);

        long[][] longRanges = {{0, 1}, {-5, 5}, {-1000000000000L, 1000000000000L},
                               {Long.MIN_VALUE, Long.MAX_VALUE}, {7, 1000},
                               {Long.MIN_VALUE, Long.MIN_VALUE + 100},
                               {Long.MAX_VALUE - 100, Long.MAX_VALUE},
                               {-(1L << 40), 1L << 40}};
        for (long seed : seeds)
            for (long[] range : longRanges)
                emitLongRange(seed, range[0], range[1]);

        double[] doubleBounds = {1.0, 0.5, 3.141592653589793, 1e300, Double.MIN_VALUE,
                                 Double.MAX_VALUE, 100.0, 123456789.123, 2.2250738585072014E-308};
        for (long seed : seeds)
            for (double bound : doubleBounds)
                emitDoubleBound(seed, bound);

        double[][] doubleRanges = {{0.0, 1.0}, {-1.0, 1.0}, {-1e300, 1e300},
                                   {-Double.MAX_VALUE, Double.MAX_VALUE},
                                   {1.5, 2.5}, {-100.0, -50.0},
                                   {-123456789.123, 987654321.456},
                                   {Double.MIN_VALUE, Double.MIN_VALUE * 3.0}};
        for (long seed : seeds)
            for (double[] range : doubleRanges)
                emitDoubleRange(seed, range[0], range[1]);
    }

    private static void emitIntBound(long seed, int bound) {
        Random random = new Random(seed);
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < DRAWS; i++) {
            if (i != 0) out.append(',');
            out.append(String.format(Locale.ROOT, "%08x", random.nextInt(bound)));
        }
        System.out.printf(Locale.ROOT, "intBound\t%d\t%d\t0\t%s%n", seed, bound, out);
    }

    private static void emitIntRange(long seed, int origin, int bound) {
        Random random = new Random(seed);
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < DRAWS; i++) {
            if (i != 0) out.append(',');
            out.append(String.format(Locale.ROOT, "%08x", random.nextInt(origin, bound)));
        }
        System.out.printf(Locale.ROOT, "intRange\t%d\t%d\t%d\t%s%n", seed, origin, bound, out);
    }

    private static void emitLongBound(long seed, long bound) {
        Random random = new Random(seed);
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < DRAWS; i++) {
            if (i != 0) out.append(',');
            out.append(String.format(Locale.ROOT, "%016x", random.nextLong(bound)));
        }
        System.out.printf(Locale.ROOT, "longBound\t%d\t%d\t0\t%s%n", seed, bound, out);
    }

    private static void emitLongRange(long seed, long origin, long bound) {
        Random random = new Random(seed);
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < DRAWS; i++) {
            if (i != 0) out.append(',');
            out.append(String.format(Locale.ROOT, "%016x", random.nextLong(origin, bound)));
        }
        System.out.printf(Locale.ROOT, "longRange\t%d\t%d\t%d\t%s%n", seed, origin, bound, out);
    }

    private static void emitDoubleBound(long seed, double bound) {
        Random random = new Random(seed);
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < DRAWS; i++) {
            if (i != 0) out.append(',');
            out.append(String.format(Locale.ROOT, "%016x", Double.doubleToRawLongBits(random.nextDouble(bound))));
        }
        System.out.printf(Locale.ROOT, "doubleBound\t%d\t%016x\t0\t%s%n",
                          seed, Double.doubleToRawLongBits(bound), out);
    }

    private static void emitDoubleRange(long seed, double origin, double bound) {
        Random random = new Random(seed);
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < DRAWS; i++) {
            if (i != 0) out.append(',');
            out.append(String.format(Locale.ROOT, "%016x", Double.doubleToRawLongBits(random.nextDouble(origin, bound))));
        }
        System.out.printf(Locale.ROOT, "doubleRange\t%d\t%016x\t%016x\t%s%n",
                          seed, Double.doubleToRawLongBits(origin), Double.doubleToRawLongBits(bound), out);
    }
}
