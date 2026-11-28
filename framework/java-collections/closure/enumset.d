module app;

import core.stdc.stdio : printf;
import flint.java.util.enumset : EnumSet;

@safe:

private enum Color
{
    red,
    green,
    blue,
    cyan
}

private enum Wide
{
    w00,
    w01,
    w02,
    w03,
    w04,
    w05,
    w06,
    w07,
    w08,
    w09,
    w10,
    w11,
    w12,
    w13,
    w14,
    w15,
    w16,
    w17,
    w18,
    w19,
    w20,
    w21,
    w22,
    w23,
    w24,
    w25,
    w26,
    w27,
    w28,
    w29,
    w30,
    w31,
    w32,
    w33,
    w34,
    w35,
    w36,
    w37,
    w38,
    w39,
    w40,
    w41,
    w42,
    w43,
    w44,
    w45,
    w46,
    w47,
    w48,
    w49,
    w50,
    w51,
    w52,
    w53,
    w54,
    w55,
    w56,
    w57,
    w58,
    w59,
    w60,
    w61,
    w62,
    w63,
    w64
}

int main(string[] args) @system
{
    auto small = EnumSet!Color.range(Color.green, Color.blue);
    small.add(args.length > 1 ? Color.red : Color.cyan);
    small.remove(Color.blue);
    auto smallCopy = EnumSet!Color.copyOf(small);
    auto smallAll = EnumSet!Color.allOf();
    auto smallComplement = EnumSet!Color.complementOf(small);
    auto smallMerged = EnumSet!Color.noneOf();
    smallMerged.addAll(small);
    smallMerged.retainAll(smallAll);
    if (small.containsAll(smallCopy) && smallMerged.equals(small))
        printf("%d %d %d\n", small.size(), smallComplement.size(), smallAll.hashCode());

    auto wide = EnumSet!Wide.allOf();
    auto window = EnumSet!Wide.range(Wide.w60, Wide.w64);
    wide.remove(Wide.w00);
    auto wideCopy = EnumSet!Wide.copyOf(wide);
    auto outside = EnumSet!Wide.complementOf(window);
    auto merged = EnumSet!Wide.noneOf();
    merged.addAll(wide);
    merged.removeAll(window);
    wideCopy.retainAll(merged);
    auto cursor = wide.iterator();
    while (cursor.hasNext())
        cursor.next();
    printf("%d %d %d %d\n", wide.size(), outside.size(), merged.size(), wideCopy.size());
    return merged.contains(Wide.w64) ? 0 : 1;
}
