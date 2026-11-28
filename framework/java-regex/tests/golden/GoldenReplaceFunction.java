// Writes framework/java-regex/tests/golden/replace_function.tsv: each case's java.util.regex result on JDK 21 for
// Matcher.replaceAll(Function) and Matcher.replaceFirst(Function), with the replacer reading the live MatchResult.
// Fields are tab-separated and escaped like GoldenRegex.java. A null replacer result writes "npe".
//   java GoldenReplaceFunction.java replace_function.tsv
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Function;
import java.util.regex.MatchResult;
import java.util.regex.Pattern;

public class GoldenReplaceFunction {
    static final List<String> out = new ArrayList<>();

    static String esc(String s) {
        StringBuilder b = new StringBuilder();
        for (char c : s.toCharArray()) {
            switch (c) {
                case '\t' -> b.append("\\t");
                case '\n' -> b.append("\\n");
                case '\r' -> b.append("\\r");
                case '\\' -> b.append("\\\\");
                default -> {
                    if (c < 0x20 || c == 0x7f) b.append(String.format("\\u%04x", (int) c));
                    else b.append(c);
                }
            }
        }
        return b.toString();
    }

    static Function<MatchResult, String> replacer(String kind) {
        return switch (kind) {
            case "wrap" -> r -> "[" + r.group() + "]";
            case "span" -> r -> r.start() + "," + r.end() + "=" + r.group();
            case "null" -> r -> null;
            default -> throw new IllegalArgumentException(kind);
        };
    }

    static void one(Pattern pattern, String input, String kind) {
        String all;
        try {
            all = pattern.matcher(input).replaceAll(replacer(kind));
        } catch (NullPointerException e) {
            all = "npe";
        }
        String first;
        try {
            first = pattern.matcher(input).replaceFirst(replacer(kind));
        } catch (NullPointerException e) {
            first = "npe";
        }
        out.add(esc(pattern.pattern()) + "\t" + esc(input) + "\t" + kind + "\t" + esc(all) + "\t" + esc(first));
    }

    static void c(Pattern pattern, String input, String kind) {
        one(pattern, input, kind);
    }

    static void c(String regex, int flags, String input, String kind) {
        c(Pattern.compile(regex, flags), input, kind);
    }

    static void c(String regex, String... inputsAndKind) {
        String kind = inputsAndKind[inputsAndKind.length - 1];
        for (int i = 0; i < inputsAndKind.length - 1; i++)
            c(Pattern.compile(regex), inputsAndKind[i], kind);
    }

    public static void main(String[] args) throws Exception {
        Path target = Path.of(args[0]);

        c("(\\d+)", "a12b345c", "wrap");
        c("(\\d+)", "a12b345c", "span");
        c("a", "aba", "wrap");
        c("a", "aba", "span");
        c("", "ab", "wrap");
        c("(a)(b)?", "ab a", "wrap");
        c("(?<year>\\d{4})-(?<month>\\d{2})", "2026-11", "span");
        c("x", "abc", "wrap");
        c("x", "abc", "null");
        c("a", "aba", "null");
        c("\\s+", "a  b\tc", "span");
        c("[é😀]", "aé😀z", "span");
        c("\\p{L}+", "aé😀z", "wrap");

        Files.write(target, out, StandardCharsets.UTF_8);
    }
}
