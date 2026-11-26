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
    }
}
