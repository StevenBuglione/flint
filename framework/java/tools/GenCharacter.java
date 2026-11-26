// Writes framework/java/source/flint/java/character.d: JDK 21's Character.toLowerCase, toUpperCase and isUpperCase,
// and the general categories Java's regex classes test (L, Lu, Ll, N), as range tables, so flint:java and the
// modules above it need no std.uni (linking std.uni drags Phobos's curl, socket and logger objects into every
// executable through an instance only curl.o defines). Extends framework/jackson-databind/tools/GenCase.java.
//   javac GenCharacter.java && java GenCharacter ../source/flint/java/character.d, then format it with dfmt
//   (--config at the repository root) and keep its hand-written unit test at the end.
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.function.IntPredicate;
import java.util.function.IntUnaryOperator;

public class GenCharacter {
    // Runs of code points start..end (every `step`-th one) that map to themselves plus `delta`.
    static List<int[]> runs(IntUnaryOperator map) {
        List<int[]> out = new ArrayList<>();
        int cp = 0;
        while (cp <= Character.MAX_CODE_POINT) {
            int delta = map.applyAsInt(cp) - cp;
            if (delta == 0) { cp++; continue; }
            int end1 = cp;
            while (end1 + 1 <= Character.MAX_CODE_POINT && map.applyAsInt(end1 + 1) - (end1 + 1) == delta) end1++;
            int end2 = cp;
            while (end2 + 2 <= Character.MAX_CODE_POINT && map.applyAsInt(end2 + 2) - (end2 + 2) == delta
                    && map.applyAsInt(end2 + 1) == end2 + 1 + (delta == 1 || delta == -1 ? -delta : 0)) end2 += 2;
            if (end2 > end1) { out.add(new int[] {cp, end2, delta, 2}); cp = end2 + 1; }
            else { out.add(new int[] {cp, end1, delta, 1}); cp = end1 + 1; }
        }
        return out;
    }

    // Maximal ranges of code points the predicate accepts.
    static List<int[]> ranges(IntPredicate test) {
        List<int[]> out = new ArrayList<>();
        int cp = 0;
        while (cp <= Character.MAX_CODE_POINT) {
            if (!test.test(cp)) { cp++; continue; }
            int end = cp;
            while (end + 1 <= Character.MAX_CODE_POINT && test.test(end + 1)) end++;
            out.add(new int[] {cp, end});
            cp = end + 1;
        }
        return out;
    }

    static boolean letter(int cp) {
        int t = Character.getType(cp);
        return t == Character.UPPERCASE_LETTER || t == Character.LOWERCASE_LETTER || t == Character.TITLECASE_LETTER
            || t == Character.MODIFIER_LETTER || t == Character.OTHER_LETTER;
    }

    static boolean number(int cp) {
        int t = Character.getType(cp);
        return t == Character.DECIMAL_DIGIT_NUMBER || t == Character.LETTER_NUMBER || t == Character.OTHER_NUMBER;
    }

    static void runTable(StringBuilder b, String name, List<int[]> runs) {
        b.append("private static immutable CaseRun[").append(runs.size()).append("] ").append(name).append(" = [\n");
        for (int[] r : runs)
            b.append(String.format("    CaseRun(0x%X, 0x%X, %s, %d),%n", r[0], r[1],
                    String.format("%,d", r[2]).replace(',', '_'), r[3]));
        b.append("];\n\n");
    }

    static void rangeTable(StringBuilder b, String name, List<int[]> ranges) {
        b.append("private static immutable uint[2][").append(ranges.size()).append("] ").append(name).append(" = [\n");
        for (int[] r : ranges) b.append(String.format("    [0x%X, 0x%X],%n", r[0], r[1]));
        b.append("];\n\n");
    }

    public static void main(String[] args) throws Exception {
        List<int[]> lower = runs(Character::toLowerCase), upper = runs(Character::toUpperCase);
        List<int[]> isUpper = ranges(Character::isUpperCase);
        List<int[]> letters = ranges(GenCharacter::letter);
        List<int[]> lu = ranges(cp -> Character.getType(cp) == Character.UPPERCASE_LETTER);
        List<int[]> ll = ranges(cp -> Character.getType(cp) == Character.LOWERCASE_LETTER);
        List<int[]> numbers = ranges(GenCharacter::number);
        // Self-check: the tables reproduce the JDK for every code point.
        for (int cp = 0; cp <= Character.MAX_CODE_POINT; cp++) {
            if (apply(lower, cp) != Character.toLowerCase(cp)) throw new AssertionError("lower " + cp);
            if (apply(upper, cp) != Character.toUpperCase(cp)) throw new AssertionError("upper " + cp);
            if (in(isUpper, cp) != Character.isUpperCase(cp)) throw new AssertionError("isUpperCase " + cp);
            if (in(letters, cp) != letter(cp)) throw new AssertionError("L " + cp);
            if (in(lu, cp) != (Character.getType(cp) == Character.UPPERCASE_LETTER)) throw new AssertionError("Lu " + cp);
            if (in(ll, cp) != (Character.getType(cp) == Character.LOWERCASE_LETTER)) throw new AssertionError("Ll " + cp);
            if (in(numbers, cp) != number(cp)) throw new AssertionError("N " + cp);
        }
        StringBuilder b = new StringBuilder();
        b.append("// Generated by framework/java/tools/GenCharacter.java from JDK ")
            .append(System.getProperty("java.version")).append(". Do not edit.\n");
        b.append("""
            /++
            Java's `Character` case mapping and the general categories its regex classes test, from JDK range tables:
            `toLowerCase`, `toUpperCase` and `isUpperCase` (simple, per code point), and `isLetter` (`\\p{L}`),
            `isUppercaseLetter` (`\\p{Lu}`), `isLowercaseLetter` (`\\p{Ll}`) and `isNumber` (`\\p{N}`). flint:java and
            the modules above it use these instead of std.uni, whose object drags Phobos's curl, socket and logger
            objects into every executable that links it.
            +/
            module flint.java.character;

            @safe:

            /// `Character.toLowerCase(c)`.
            dchar toLowerCase(dchar c) pure nothrow @nogc
            {
                if (c < 0x80)
                    return c >= 'A' && c <= 'Z' ? cast(dchar)(c + 32) : c;
                return mapped(lowerRuns, c);
            }

            /// `Character.toUpperCase(c)`.
            dchar toUpperCase(dchar c) pure nothrow @nogc
            {
                if (c < 0x80)
                    return c >= 'a' && c <= 'z' ? cast(dchar)(c - 32) : c;
                return mapped(upperRuns, c);
            }

            /// `Character.isUpperCase(c)`: the `Lu` category or `Other_Uppercase`.
            bool isUpperCase(dchar c) pure nothrow @nogc
            {
                if (c < 0x80)
                    return c >= 'A' && c <= 'Z';
                return within(upperCaseRanges, c);
            }

            /// `Character.isLetter(c)`, the regex class `\\p{L}`: the categories `Lu`, `Ll`, `Lt`, `Lm` and `Lo`.
            bool isLetter(dchar c) pure nothrow @nogc
            {
                if (c < 0x80)
                    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
                return within(letterRanges, c);
            }

            /// The regex class `\\p{Lu}`: the category `UPPERCASE_LETTER`.
            bool isUppercaseLetter(dchar c) pure nothrow @nogc
            {
                if (c < 0x80)
                    return c >= 'A' && c <= 'Z';
                return within(uppercaseLetterRanges, c);
            }

            /// The regex class `\\p{Ll}`: the category `LOWERCASE_LETTER`.
            bool isLowercaseLetter(dchar c) pure nothrow @nogc
            {
                if (c < 0x80)
                    return c >= 'a' && c <= 'z';
                return within(lowercaseLetterRanges, c);
            }

            /// The regex class `\\p{N}`: the categories `Nd`, `Nl` and `No`.
            bool isNumber(dchar c) pure nothrow @nogc
            {
                if (c < 0x80)
                    return c >= '0' && c <= '9';
                return within(numberRanges, c);
            }

            private struct CaseRun
            {
                uint start, end;
                int delta;
                uint step;
            }

            private dchar mapped(scope const(CaseRun)[] runs, dchar c) pure nothrow @nogc
            {
                size_t low, high = runs.length;
                while (low < high)
                {
                    const middle = (low + high) / 2;
                    const run = runs[middle];
                    if (c < run.start)
                        high = middle;
                    else if (c > run.end)
                        low = middle + 1;
                    else
                        return (c - run.start) % run.step == 0 ? cast(dchar)(c + run.delta) : c;
                }
                return c;
            }

            private bool within(scope const(uint[2])[] ranges, dchar c) pure nothrow @nogc
            {
                size_t low, high = ranges.length;
                while (low < high)
                {
                    const middle = (low + high) / 2;
                    if (c < ranges[middle][0])
                        high = middle;
                    else if (c > ranges[middle][1])
                        low = middle + 1;
                    else
                        return true;
                }
                return false;
            }

            """);
        runTable(b, "lowerRuns", lower);
        runTable(b, "upperRuns", upper);
        rangeTable(b, "upperCaseRanges", isUpper);
        rangeTable(b, "letterRanges", letters);
        rangeTable(b, "uppercaseLetterRanges", lu);
        rangeTable(b, "lowercaseLetterRanges", ll);
        rangeTable(b, "numberRanges", numbers);
        Files.writeString(Path.of(args[0]), b.toString().stripTrailing() + "\n", StandardCharsets.UTF_8);
        System.out.println(lower.size() + " lower runs, " + upper.size() + " upper runs, " + isUpper.size()
            + " isUpperCase, " + letters.size() + " L, " + lu.size() + " Lu, " + ll.size() + " Ll, " + numbers.size() + " N ranges");
    }

    static int apply(List<int[]> runs, int cp) {
        for (int[] r : runs)
            if (cp >= r[0] && cp <= r[1] && (cp - r[0]) % r[3] == 0) return cp + r[2];
        return cp;
    }

    static boolean in(List<int[]> ranges, int cp) {
        int low = 0, high = ranges.size();
        while (low < high) {
            int middle = (low + high) >>> 1;
            int[] r = ranges.get(middle);
            if (cp < r[0]) high = middle; else if (cp > r[1]) low = middle + 1; else return true;
        }
        return false;
    }
}
