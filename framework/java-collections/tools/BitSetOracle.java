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
        System.out.println(Integer.toUnsignedString(andDigest()));
        System.out.println(Integer.toUnsignedString(longArrayDigest()));
        System.out.println(Integer.toUnsignedString(byteArrayDigest()));
        System.out.println(Integer.toUnsignedString(longImportDigest()));
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

    private static int andDigest() {
        var left = new BitSet();
        var mask = new BitSet();
        int state = 0x374e2063;
        int digest = 0;
        for (int step = 0; step < 512; ++step) {
            state = state * 1_664_525 + 1_013_904_223;
            int start = (state >>> 13) % 320;
            left.set(start, start + 1 + (state & 63));
            if ((step & 7) == 0) {
                mask.clear();
            }
            int selected = (state >>> 3) % 257;
            mask.flip(selected, selected + 1 + ((state >>> 9) & 31));
            left.and((step & 31) == 0 ? left : mask);
            digest = 31 * digest + left.size();
            digest = 31 * digest + left.length();
            digest = 31 * digest + left.cardinality();
            for (int bit = 0; bit < 384; ++bit) {
                digest = 31 * digest + (left.get(bit) ? 1 : 0);
            }
        }
        return digest;
    }

    private static int longArrayDigest() {
        var bits = new BitSet();
        int state = 0x42ae99bb;
        int digest = 0;
        for (int step = 0; step < 512; ++step) {
            state = state * 1_664_525 + 1_013_904_223;
            if ((step & 15) == 0) {
                bits.clear();
            }
            bits.flip((state >>> 13) & 511);
            long[] words = bits.toLongArray();
            digest = 31 * digest + words.length;
            for (long word : words) {
                digest = 31 * digest + (int)(word ^ (word >>> 32));
            }
        }
        return digest;
    }

    private static int byteArrayDigest() {
        var bits = new BitSet();
        int state = 0x3a56f9c1;
        int digest = 0;
        for (int step = 0; step < 512; ++step) {
            state = state * 1_664_525 + 1_013_904_223;
            if ((step & 15) == 0) {
                bits.clear();
            } else {
                bits.flip((state >>> 13) & 511);
            }
            byte[] bytes = bits.toByteArray();
            digest = 31 * digest + bytes.length;
            for (byte value : bytes) {
                digest = 31 * digest + (value & 0xff);
            }
        }
        return digest;
    }

    private static int longImportDigest() {
        int state = 0x2e4875cf;
        int digest = 0;
        for (int step = 0; step < 512; ++step) {
            long[] words = new long[step & 7];
            for (int index = 0; index < (step & 3); ++index) {
                state = state * 1_664_525 + 1_013_904_223;
                words[index] = ((long) state << 32) | (state ^ 0x5ba72df1) & 0xffff_ffffL;
            }
            var bits = BitSet.valueOf(words);
            digest = 31 * digest + bits.size();
            digest = 31 * digest + bits.length();
            digest = 31 * digest + bits.cardinality();
            for (long word : bits.toLongArray()) {
                digest = 31 * digest + (int)(word ^ (word >>> 32));
            }
        }
        return digest;
    }
}
