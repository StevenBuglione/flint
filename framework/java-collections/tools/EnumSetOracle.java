// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
import java.util.EnumSet;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Set;

// Stable transcript of EnumSet behaviour against Temurin 21.0.13+9. Only names, sizes, order and flags are folded,
// never hashCode, which is identity-based in Java.
class EnumSetOracle {
    private static int digest;

    enum Color { red, green, blue, cyan, magenta, yellow }

    enum Wide {
        w00, w01, w02, w03, w04, w05, w06, w07, w08, w09,
        w10, w11, w12, w13, w14, w15, w16, w17, w18, w19,
        w20, w21, w22, w23, w24, w25, w26, w27, w28, w29,
        w30, w31, w32, w33, w34, w35, w36, w37, w38, w39,
        w40, w41, w42, w43, w44, w45, w46, w47, w48, w49,
        w50, w51, w52, w53, w54, w55, w56, w57, w58, w59,
        w60, w61, w62, w63, w64, w65, w66, w67, w68, w69
    }

    public static void main(String[] args) {
        System.out.println(Integer.toUnsignedString(smallFact()));
        System.out.println(Integer.toUnsignedString(smallBulk()));
        System.out.println(Integer.toUnsignedString(smallIteratorClone()));
        System.out.println(Integer.toUnsignedString(jumbo()));
    }

    private static void fold(int value) {
        digest = 31 * digest + value;
    }

    private static void foldText(String text) {
        for (char c : text.toCharArray()) {
            digest = 31 * digest + c;
        }
    }

    private static void foldAll(EnumSet<?> set) {
        Object[] items = set.toArray();
        fold(items.length);
        for (Object item : items) {
            foldText(((Enum<?>) item).name());
        }
    }

    private static int smallFact() {
        digest = 0x51a11;
        EnumSet<Color> set = EnumSet.noneOf(Color.class);
        fold(set.size());
        fold(set.isEmpty() ? 1 : 0);
        fold(set.add(Color.green) ? 1 : 0);
        fold(set.add(Color.green) ? 1 : 0);
        fold(set.contains(Color.green) ? 1 : 0);
        fold(set.contains(Color.red) ? 1 : 0);
        fold(set.remove(Color.red) ? 1 : 0);
        fold(set.remove(Color.green) ? 1 : 0);
        foldAll(set);
        foldAll(EnumSet.of(Color.red));
        foldAll(EnumSet.of(Color.blue, Color.red));
        foldAll(EnumSet.of(Color.blue, Color.red, Color.green));
        foldAll(EnumSet.of(Color.yellow, Color.blue, Color.red, Color.green));
        foldAll(EnumSet.of(Color.yellow, Color.magenta, Color.cyan, Color.blue, Color.red));
        foldAll(EnumSet.of(Color.yellow, Color.magenta, Color.cyan, Color.blue, Color.green, Color.red));
        foldAll(EnumSet.range(Color.green, Color.magenta));
        try {
            EnumSet.range(Color.magenta, Color.green);
            fold(0);
        } catch (IllegalArgumentException expected) {
            fold(7);
        }
        foldAll(EnumSet.allOf(Color.class));
        foldAll(EnumSet.complementOf(EnumSet.of(Color.red, Color.yellow)));
        EnumSet<Color> original = EnumSet.range(Color.red, Color.blue);
        EnumSet<Color> copy = EnumSet.copyOf(original);
        copy.add(Color.yellow);
        foldAll(original);
        foldAll(copy);
        return digest;
    }

    private static int smallBulk() {
        digest = 0x6b1a1;
        EnumSet<Color> all = EnumSet.allOf(Color.class);
        EnumSet<Color> narrow = EnumSet.of(Color.green, Color.cyan);
        fold(all.containsAll(narrow) ? 1 : 0);
        fold(narrow.containsAll(all) ? 1 : 0);
        fold(narrow.containsAll(EnumSet.noneOf(Color.class)) ? 1 : 0);
        EnumSet<Color> added = EnumSet.noneOf(Color.class);
        fold(added.addAll(narrow) ? 1 : 0);
        fold(added.addAll(narrow) ? 1 : 0);
        foldAll(added);
        fold(added.removeAll(EnumSet.of(Color.cyan)) ? 1 : 0);
        foldAll(added);
        EnumSet<Color> retained = EnumSet.allOf(Color.class);
        fold(retained.retainAll(narrow) ? 1 : 0);
        foldAll(retained);
        Set<Color> generic = new HashSet<>();
        generic.add(Color.red);
        generic.add(Color.blue);
        EnumSet<Color> throughGeneric = EnumSet.noneOf(Color.class);
        fold(throughGeneric.addAll(generic) ? 1 : 0);
        foldAll(throughGeneric);
        fold(throughGeneric.containsAll(generic) ? 1 : 0);
        fold(throughGeneric.removeAll(generic) ? 1 : 0);
        fold(throughGeneric.isEmpty() ? 1 : 0);
        EnumSet<Color> left = EnumSet.range(Color.green, Color.cyan);
        EnumSet<Color> right = EnumSet.of(Color.cyan, Color.blue, Color.green);
        fold(left.equals(right) ? 1 : 0);
        fold(left.hashCode() == right.hashCode() ? 1 : 0);
        Set<Color> asHashSet = new HashSet<>(left);
        fold(left.equals(asHashSet) ? 1 : 0);
        fold(asHashSet.equals(left) ? 1 : 0);
        return digest;
    }

    private static int smallIteratorClone() {
        digest = 0x1c10e;
        EnumSet<Color> set = EnumSet.allOf(Color.class);
        Iterator<Color> cursor = set.iterator();
        fold(cursor.hasNext() ? 1 : 0);
        foldText(cursor.next().name());
        cursor.remove();
        try {
            cursor.remove();
            fold(0);
        } catch (IllegalStateException expected) {
            fold(9);
        }
        foldAll(set);
        EnumSet<Color> removable = EnumSet.allOf(Color.class);
        fold(removable.removeIf(c -> c == Color.blue || c == Color.magenta) ? 1 : 0);
        foldAll(removable);
        EnumSet<Color> source = EnumSet.range(Color.red, Color.cyan);
        EnumSet<Color> cloned = source.clone();
        cloned.add(Color.yellow);
        foldAll(source);
        foldAll(cloned);
        return digest;
    }

    private static int jumbo() {
        digest = 0x70001;
        EnumSet<Wide> set = EnumSet.noneOf(Wide.class);
        fold(set.size());
        fold(set.add(Wide.w65) ? 1 : 0);
        fold(set.add(Wide.w00) ? 1 : 0);
        fold(set.add(Wide.w64) ? 1 : 0);
        fold(set.add(Wide.w65) ? 1 : 0);
        fold(set.contains(Wide.w64) ? 1 : 0);
        fold(set.contains(Wide.w63) ? 1 : 0);
        foldAll(set);
        fold(set.remove(Wide.w64) ? 1 : 0);
        fold(set.size());
        EnumSet<Wide> whole = EnumSet.allOf(Wide.class);
        fold(whole.size());
        EnumSet<Wide> window = EnumSet.range(Wide.w60, Wide.w69);
        foldAll(window);
        EnumSet<Wide> outside = EnumSet.complementOf(window);
        fold(outside.size());
        fold(outside.contains(Wide.w59) ? 1 : 0);
        fold(outside.contains(Wide.w60) ? 1 : 0);
        Iterator<Wide> cursor = whole.iterator();
        foldText(cursor.next().name());
        cursor.remove();
        fold(whole.size());
        EnumSet<Wide> kept = EnumSet.copyOf(whole);
        fold(kept.retainAll(EnumSet.range(Wide.w05, Wide.w15)) ? 1 : 0);
        fold(kept.size());
        foldText(kept.toArray(new Wide[0])[0].name());
        foldText(kept.toArray(new Wide[0])[kept.size() - 1].name());
        return digest;
    }
}
