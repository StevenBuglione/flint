// Regenerate tests/biginteger-java21.tsv with this program on Java SE 21.
import java.math.BigInteger;
import java.util.HexFormat;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

class BigIntegerOracle {
    private static final BigInteger ONE = BigInteger.ONE;
    private static final HexFormat HEX = HexFormat.of();

    public static void main(String[] args) {
        if (Runtime.version().feature() != 21)
            throw new IllegalStateException("Generate the corpus with Java SE 21");

        BigInteger word = ONE.shiftLeft(32);
        BigInteger sparse = ONE.shiftLeft(97).add(ONE.shiftLeft(63)).add(BigInteger.valueOf(7));
        List<BigInteger> magnitudes = List.of(ONE, BigInteger.valueOf(13), word.subtract(ONE),
            word, word.add(ONE), sparse, ONE.shiftLeft(176).subtract(ONE));
        Set<BigInteger> operands = new LinkedHashSet<>();
        operands.add(BigInteger.ZERO);
        for (BigInteger value : magnitudes) {
            operands.add(value);
            operands.add(value.negate());
        }

        Set<BigInteger> conversions = new LinkedHashSet<>(operands);
        for (int bit : new int[] {7, 15, 23, 24, 31, 32, 53, 63, 64, 127, 128, 1023, 1024}) {
            addNeighbors(conversions, ONE.shiftLeft(bit));
        }
        // Two halfway values select different retained bits at each floating-point precision.
        for (int[] scale : new int[][] {{84, 60}, {211, 158}}) {
            BigInteger leading = ONE.shiftLeft(scale[0]);
            BigInteger half = ONE.shiftLeft(scale[1]);
            addNeighbors(conversions, leading.add(half));
            addNeighbors(conversions, leading.add(half.multiply(BigInteger.valueOf(3))));
        }
        addNeighbors(conversions, ONE.shiftLeft(128).subtract(ONE.shiftLeft(103)));
        addNeighbors(conversions, ONE.shiftLeft(1024).subtract(ONE.shiftLeft(970)));

        for (BigInteger value : conversions) {
            row("value", bytes(value), value.signum(), value.bitLength(), value.hashCode(),
                value.intValue(), value.longValue(), Float.floatToRawIntBits(value.floatValue()),
                Double.doubleToRawLongBits(value.doubleValue()), bytes(value.abs()), bytes(value.negate()));
        }
        for (BigInteger left : operands) {
            for (BigInteger right : operands) {
                BigInteger sum = left.add(right);
                BigInteger difference = left.subtract(right);
                BigInteger product = left.multiply(right);
                row("pair", bytes(left), bytes(right), left.compareTo(right), left.equals(right),
                    bytes(left.min(right)), bytes(left.max(right)), bytes(sum), sum.signum(),
                    bytes(difference), difference.signum(), bytes(product), product.signum());
            }
        }
        for (BigInteger value : List.of(BigInteger.ZERO, sparse, sparse.negate())) {
            for (int radix = 0; radix <= 37; ++radix)
                row("radix", bytes(value), radix, value.toString(radix));
        }
        for (BigInteger value : operands) {
            for (int exponent : new int[] {0, 1, 2, 3, 4, 9}) {
                BigInteger result = value.pow(exponent);
                row("power", bytes(value), exponent, bytes(result), result.signum());
            }
        }
    }

    private static void addNeighbors(Set<BigInteger> values, BigInteger boundary) {
        for (int offset = -1; offset <= 1; ++offset) {
            BigInteger value = boundary.add(BigInteger.valueOf(offset));
            values.add(value);
            values.add(value.negate());
        }
    }

    private static String bytes(BigInteger value) {
        return HEX.formatHex(value.toByteArray());
    }

    private static void row(Object... fields) {
        for (int i = 0; i < fields.length; ++i) {
            if (i != 0)
                System.out.print('\t');
            System.out.print(fields[i]);
        }
        System.out.println();
    }
}
