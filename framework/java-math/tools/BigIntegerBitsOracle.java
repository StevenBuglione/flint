/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 *
 * Emits tests/biginteger-bits-java21.tsv from the pinned OpenJDK 21 oracle:
 * bitCount, getLowestSetBit, not, testBit/setBit/clearBit/flipBit, the two
 * shifts and the four two's-complement bitwise operators. Compile with the
 * pinned Temurin 21 and run from framework/java-math:
 *
 *     javac -d /tmp tools/BigIntegerBitsOracle.java
 *     java -cp /tmp BigIntegerBitsOracle > tests/biginteger-bits-java21.tsv
 */
import java.math.BigInteger;

public final class BigIntegerBitsOracle {
    private static final String[] VALUES = {
        "00", "01", "ff", "02", "fe", "03", "fd", "04", "fc", "07", "f9", "08", "f8", "0a", "f6",
        "7fffffff", "80000001", "00ffffffff", "ff00000001", "0100000000", "ff00000000", "0100000001",
        "feffffffff", "7fffffffffffffff", "8000000000000001", "00ffffffffffffffff", "ff0000000000000001",
        "010000000000000000", "ff0000000000000000", "010000000000000001", "feffffffffffffffff",
        "02000000008000000000000007", "fdffffffff7ffffffffffffff9", "00ffffffffffffffff00000001",
        "ff0000000000000000ffffffff", "8000000000000000",
    };

    private static final int[] BITS = {0, 1, 2, 3, 7, 31, 32, 33, 62, 63, 64, 65, 95, 96, 97, 128};

    private static final int[] SHIFTS = {-129, -97, -64, -63, -33, -32, -31, -1, 0, 1, 31, 32, 33, 63, 64, 97};

    private static final String[] PRODUCT = {
        "00", "01", "ff", "02", "fe", "f8", "f7", "00ffffffff", "ff00000001", "0100000000",
        "ff00000000", "010000000000000000", "ff0000000000000000", "02000000008000000000000007",
        "fdffffffff7ffffffffffffff9", "ff0000000000000000ffffffff",
    };

    public static void main(String[] args) {
        StringBuilder out = new StringBuilder();
        for (String value : VALUES) {
            BigInteger current = fromHex(value);
            out.append("u\t").append(value).append('\t').append(current.bitCount()).append('\t')
                .append(current.getLowestSetBit()).append('\t').append(hex(current.not())).append('\n');
            for (int bit : BITS) {
                out.append("b\t").append(value).append('\t').append(bit).append('\t')
                    .append(current.testBit(bit)).append('\t').append(hex(current.setBit(bit))).append('\t')
                    .append(hex(current.clearBit(bit))).append('\t').append(hex(current.flipBit(bit))).append('\n');
            }
        }
        for (String value : VALUES) {
            BigInteger current = fromHex(value);
            for (int shift : SHIFTS) {
                out.append("s\t").append(value).append('\t').append(shift).append('\t')
                    .append(hex(current.shiftLeft(shift))).append('\t').append(hex(current.shiftRight(shift))).append('\n');
            }
        }
        for (String left : PRODUCT) {
            BigInteger a = fromHex(left);
            for (String right : PRODUCT) {
                BigInteger b = fromHex(right);
                out.append("p\t").append(left).append('\t').append(right).append('\t')
                    .append(hex(a.and(b))).append('\t').append(hex(a.or(b))).append('\t')
                    .append(hex(a.xor(b))).append('\t').append(hex(a.andNot(b))).append('\n');
            }
        }
        System.out.print(out);
    }

    private static BigInteger fromHex(String text) {
        return new BigInteger(unhex(text));
    }

    private static byte[] unhex(String text) {
        byte[] bytes = new byte[text.length() / 2];
        for (int i = 0; i < bytes.length; i++)
            bytes[i] = (byte) Integer.parseInt(text.substring(2 * i, 2 * i + 2), 16);
        return bytes;
    }

    private static String hex(BigInteger value) {
        StringBuilder text = new StringBuilder();
        for (byte octet : value.toByteArray())
            text.append(String.format("%02x", octet & 0xff));
        return text.toString();
    }
}
