// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
import java.util.BitSet;

class BitSetOracle {
    public static void main(String[] args) {
        var bits = new BitSet();
        int state = 0x13579ace;
        int digest = 0;
        for (int step = 0; step < 1024; ++step) {
            state = state * 1_664_525 + 1_013_904_223;
            int index = (state >>> 16) & 1023;
            switch (state & 7) {
                case 0 -> bits.set(index);
                case 1 -> bits.set(index, (state & 16) != 0);
                case 2 -> bits.clear(index);
                case 3 -> bits.flip(index);
                case 4 -> { if (step % 17 == 0) bits.clear(); }
            }
            int from = (state >>> 8) & 1023;
            for (int value : new int[] {bits.get(index) ? 1 : 0, bits.length(),
                    bits.cardinality(), bits.size(), bits.isEmpty() ? 1 : 0,
                    bits.nextSetBit(from), bits.nextClearBit(from), bits.previousSetBit(from),
                    bits.previousClearBit(from)}) {
                digest = 31 * digest + value;
            }
        }
        System.out.println(Integer.toUnsignedString(digest));
        System.out.println(Integer.toUnsignedString(rangeDigest()));
    }

    private static int rangeDigest() {
        var bits = new BitSet();
        int state = 0x2468ace1;
        int digest = 0;
        for (int step = 0; step < 2048; ++step) {
            state = state * 1_664_525 + 1_013_904_223;
            int a = (state >>> 16) % 321;
            int b = (state >>> 4) % 321;
            int start = Math.min(a, b);
            int end = (step & 31) == 0 ? start : Math.max(a, b);
            switch (state & 3) {
                case 0 -> bits.set(start, end);
                case 1 -> bits.clear(start, end);
                case 2 -> bits.flip(start, end);
                case 3 -> bits.set(start, end, (state & 128) != 0);
            }
            digest = 31 * digest + bits.size();
            digest = 31 * digest + bits.length();
            digest = 31 * digest + bits.cardinality();
            for (int bit = 0; bit < 320; ++bit) {
                digest = 31 * digest + (bits.get(bit) ? 1 : 0);
            }
        }
        return digest;
    }
}
