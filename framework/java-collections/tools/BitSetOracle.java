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
        System.out.println(Integer.toUnsignedString(andNotDigest()));
        System.out.println(Integer.toUnsignedString(intersectionDigest()));
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

    private static int andNotDigest() {
        var left = new BitSet();
        var mask = new BitSet();
        mask.set(2048);
        int state = 0x376ac921;
        int digest = 0;
        for (int step = 0; step < 1024; ++step) {
            state = state * 1_664_525 + 1_013_904_223;
            int a = (state >>> 16) % 321;
            int b = (state >>> 3) % 321;
            int start = Math.min(a, b);
            int end = Math.max(a, b);
            left.set(start, end, (state & 64) != 0);
            mask.flip(b);
            if ((step & 7) == 0) {
                mask.set(start, end);
            }
            left.andNot((step & 31) == 0 ? left : mask);
            digest = 31 * digest + left.size();
            digest = 31 * digest + left.length();
            digest = 31 * digest + left.cardinality();
            digest = 31 * digest + mask.cardinality();
            for (int bit = 0; bit <= 320; ++bit) {
                digest = 31 * digest + (left.get(bit) ? 1 : 0);
                digest = 31 * digest + (mask.get(bit) ? 1 : 0);
            }
        }
        return digest;
    }

    private static int intersectionDigest() {
        var left = new BitSet();
        var right = new BitSet();
        int state = 0x18c05f23;
        int digest = 0;
        for (int step = 0; step < 512; ++step) {
            state = state * 1_664_525 + 1_013_904_223;
            if ((step & 7) == 0) {
                left.clear();
            }
            if ((step & 15) == 8) {
                right.clear();
            }
            left.set((state >>> 3) % 193);
            right.set((state >>> 14) % 257);
            digest = 31 * digest + (left.intersects(right) ? 1 : 0);
            digest = 31 * digest + (right.intersects(left) ? 1 : 0);
        }
        return digest;
    }
}
