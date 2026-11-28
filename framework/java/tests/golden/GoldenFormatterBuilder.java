// Writes the golden file that framework/java/tests/time_test.d compares: formatters made by DateTimeFormatterBuilder,
// their descriptions, and what they format and parse. Each line is `op<TAB>recipe<TAB>kind<TAB>input<TAB>result`.
// A recipe is the builder calls, separated by `|`, that both this file and the D test apply:
//   cs ci strict lenient   parseCaseSensitive, parseCaseInsensitive, parseStrict, parseLenient
//   inst offid zid zrid    appendInstant, appendOffsetId, appendZoneId, appendZoneRegionId
//   zo                     appendZoneOrOffsetId
//   [ ]                    optionalStart, optionalEnd
//   c:X s:TEXT p:PATTERN   appendLiteral(char), appendLiteral(String), appendPattern
//   o:PATTERN,TEXT         appendOffset
//   l:STYLE                appendLocalizedOffset(TextStyle.valueOf(STYLE))
//   i:N                    appendInstant(N)
//   P:W or P:W,CHAR        padNext(W) or padNext(W, CHAR)
//   a:NAME q:NAME          append, appendOptional of an ISO constant, or of ofPattern(P) for NAME `=P`
// Ops: `build` (the formatter's toString, or the builder's exception), `format` (a value of the kind, from its
// toString) and `parse` (into the kind). A result is the toString() or `!` and the exception message (and a parse
// exception's error index). Text outside printable ASCII, and the backslash, is written as a Java unicode escape.
// Java's Parsed lists unresolved fields in HashMap order, so a description with fields other than OffsetSeconds is
// written as `{?}`, which the D test also writes for its own. Two kinds of row are left out: a value with no zone
// printed by appendZoneRegionId, whose message names a lambda, and the instant's resolution, where Flint still
// resolves the local date-time and offset it parsed and Java only the instant (deferred in the API mapping).
//   javac GoldenFormatterBuilder.java && java GoldenFormatterBuilder formatter_builder.tsv
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.*;
import java.time.format.*;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

public class GoldenFormatterBuilder {
    static final Set<String> lines = new LinkedHashSet<>();

    static final Map<String, DateTimeFormatter> constants = Map.ofEntries(
            Map.entry("ISO_LOCAL_DATE", DateTimeFormatter.ISO_LOCAL_DATE),
            Map.entry("ISO_LOCAL_TIME", DateTimeFormatter.ISO_LOCAL_TIME),
            Map.entry("ISO_LOCAL_DATE_TIME", DateTimeFormatter.ISO_LOCAL_DATE_TIME),
            Map.entry("ISO_OFFSET_DATE_TIME", DateTimeFormatter.ISO_OFFSET_DATE_TIME),
            Map.entry("ISO_OFFSET_DATE", DateTimeFormatter.ISO_OFFSET_DATE),
            Map.entry("ISO_DATE", DateTimeFormatter.ISO_DATE),
            Map.entry("ISO_DATE_TIME", DateTimeFormatter.ISO_DATE_TIME),
            Map.entry("ISO_TIME", DateTimeFormatter.ISO_TIME),
            Map.entry("ISO_INSTANT", DateTimeFormatter.ISO_INSTANT),
            Map.entry("BASIC_ISO_DATE", DateTimeFormatter.BASIC_ISO_DATE),
            Map.entry("ISO_ORDINAL_DATE", DateTimeFormatter.ISO_ORDINAL_DATE));

    static final String[][] samples = {
        {"date", "2024-03-05"}, {"date", "0001-12-31"}, {"date", "+12345-06-07"},
        {"time", "10:15"}, {"time", "10:15:30"}, {"time", "10:15:30.123456789"}, {"time", "00:00"},
        {"dateTime", "2024-03-05T10:15:30"}, {"dateTime", "2024-03-05T00:00:00.000001"},
        {"offset", "2024-03-05T10:15:30+01:00"}, {"offset", "2024-03-05T10:15:30Z"},
        {"offset", "2024-03-05T10:15:30.500-05:30:15"}, {"offset", "2024-03-05T10:15:30+00:00:45"},
        {"zoned", "2024-03-05T10:15:30+02:00"}, {"zoned", "2024-03-05T10:15:30Z[UTC]"},
        {"instant", "2024-03-05T10:15:30Z"}, {"instant", "2024-03-05T10:15:30.120Z"},
    };

    static String esc(String s) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c >= 0x20 && c < 0x7f && c != '\\') b.append(c);
            else b.append(String.format("\\u%04X", (int) c));
        }
        return b.toString();
    }

    static String err(Throwable e) {
        String m = e.getMessage().replaceAll("TemporalAccessor: \\{(?!(OffsetSeconds=-?\\d+)?\\})[^}]*\\}",
                "TemporalAccessor: {?}");
        String s = "!" + esc(m);
        if (e instanceof DateTimeParseException p) s += "\t" + p.getErrorIndex();
        return s;
    }

    static DateTimeFormatter named(String name) {
        return name.startsWith("=") ? DateTimeFormatter.ofPattern(name.substring(1)) : constants.get(name);
    }

    static void padNext(DateTimeFormatterBuilder b, String arg) {
        int comma = arg.indexOf(',');
        if (comma < 0) {
            b.padNext(Integer.parseInt(arg));
        } else {
            b.padNext(Integer.parseInt(arg.substring(0, comma)), arg.charAt(comma + 1));
        }
    }

    static DateTimeFormatter build(String recipe) {
        DateTimeFormatterBuilder b = new DateTimeFormatterBuilder();
        for (String step : recipe.isEmpty() ? new String[0] : recipe.split("\\|", -1)) {
            boolean hasArg = step.length() >= 2 && step.charAt(1) == ':';
            String arg = hasArg ? step.substring(2) : "";
            switch (hasArg ? step.substring(0, 1) : step) {
                case "cs" -> b.parseCaseSensitive();
                case "ci" -> b.parseCaseInsensitive();
                case "strict" -> b.parseStrict();
                case "lenient" -> b.parseLenient();
                case "inst" -> b.appendInstant();
                case "offid" -> b.appendOffsetId();
                case "zid" -> b.appendZoneId();
                case "zrid" -> b.appendZoneRegionId();
                case "zo" -> b.appendZoneOrOffsetId();
                case "[" -> b.optionalStart();
                case "]" -> b.optionalEnd();
                case "c" -> b.appendLiteral(arg.charAt(0));
                case "s" -> b.appendLiteral(arg);
                case "p" -> b.appendPattern(arg);
                case "o" -> b.appendOffset(arg.substring(0, arg.indexOf(',')), arg.substring(arg.indexOf(',') + 1));
                case "l" -> b.appendLocalizedOffset(TextStyle.valueOf(arg));
                case "i" -> b.appendInstant(Integer.parseInt(arg));
                case "P" -> padNext(b, arg);
                case "a" -> b.append(named(arg));
                case "q" -> b.appendOptional(named(arg));
                default -> throw new AssertionError(step);
            }
        }
        return b.toFormatter();
    }

    static Object value(String kind, String text) {
        return switch (kind) {
            case "date" -> LocalDate.parse(text);
            case "time" -> LocalTime.parse(text);
            case "dateTime" -> LocalDateTime.parse(text);
            case "offset" -> OffsetDateTime.parse(text);
            case "zoned" -> ZonedDateTime.parse(text);
            default -> Instant.parse(text);
        };
    }

    static Object parse(String kind, String text, DateTimeFormatter f) {
        return switch (kind) {
            case "date" -> LocalDate.parse(text, f);
            case "time" -> LocalTime.parse(text, f);
            case "dateTime" -> LocalDateTime.parse(text, f);
            case "offset" -> OffsetDateTime.parse(text, f);
            default -> ZonedDateTime.parse(text, f);
        };
    }

    static void row(String op, String recipe, String kind, String in, String out) {
        if (out.contains("$$Lambda") || ((recipe.contains("inst") || recipe.contains("i:")) && out.contains("from TemporalAccessor")))
            return;
        lines.add(op + "\t" + esc(recipe) + "\t" + kind + "\t" + esc(in) + "\t" + out);
    }

    // The recipe's build row; its format rows for every sample; and parse rows into `kinds` for each formatted text
    // and each extra input.
    static void recipe(String recipe, String[] kinds, String... inputs) {
        DateTimeFormatter f;
        try {
            f = build(recipe);
        } catch (IllegalArgumentException | IllegalStateException e) {
            row("build", recipe, "-", "-", err(e));
            return;
        }
        row("build", recipe, "-", "-", esc(f.toString()));
        List<String> texts = new ArrayList<>(List.of(inputs));
        for (String[] s : samples) {
            String out;
            try {
                String text = f.format((java.time.temporal.TemporalAccessor) value(s[0], s[1]));
                texts.add(text);
                out = esc(text);
            } catch (DateTimeException e) {
                out = err(e);
            }
            row("format", recipe, s[0], s[1], out);
        }
        for (String text : texts)
            for (String kind : kinds) {
                String out;
                try {
                    out = esc(String.valueOf(parse(kind, text, f)));
                } catch (DateTimeException e) {
                    out = err(e);
                }
                row("parse", recipe, kind, text, out);
            }
    }

    // Format rows of the recipe for extra offset values beyond the samples.
    static void formats(String recipe, String... values) {
        DateTimeFormatter f = build(recipe);
        for (String v : values) {
            String out;
            try {
                out = esc(f.format(OffsetDateTime.parse(v)));
            } catch (DateTimeException e) {
                out = err(e);
            }
            row("format", recipe, "offset", v, out);
        }
    }

    // Format rows of the recipe for extra instant values beyond the samples.
    static void instants(String recipe, String... values) {
        DateTimeFormatter f = build(recipe);
        for (String v : values) {
            String out;
            try {
                out = esc(f.format(Instant.parse(v)));
            } catch (DateTimeException e) {
                out = err(e);
            }
            row("format", recipe, "instant", v, out);
        }
    }

    // Build and format rows of the recipe for every sample, without parse rows (a bare zone or offset text does not
    // describe a date-time).
    static void formatsAll(String recipe) {
        DateTimeFormatter f = build(recipe);
        row("build", recipe, "-", "-", esc(f.toString()));
        for (String[] s : samples) {
            String out;
            try {
                out = esc(f.format((java.time.temporal.TemporalAccessor) value(s[0], s[1])));
            } catch (DateTimeException e) {
                out = err(e);
            }
            row("format", recipe, s[0], s[1], out);
        }
    }

    // Parse rows of the recipe only for the given inputs.
    static void parses(String recipe, String[] kinds, String... inputs) {
        DateTimeFormatter f = build(recipe);
        for (String text : inputs)
            for (String kind : kinds) {
                String out;
                try {
                    out = esc(String.valueOf(parse(kind, text, f)));
                } catch (DateTimeException e) {
                    out = err(e);
                }
                row("parse", recipe, kind, text, out);
            }
    }

    static String[] k(String... kinds) {
        return kinds;
    }

    public static void main(String[] a) throws Exception {
        String[] none = {};
        // Builder errors.
        recipe("]", none);
        recipe("[|]|]", none);
        recipe("p:]", none);
        recipe("p:uuuu]", none);
        recipe("p:{", none);
        recipe("p:'abc", none);
        recipe("o:HH,Z", none);
        recipe("o:,Z", none);
        recipe("o:+hh:mm,Z", none);
        // An empty builder, literals and settings.
        recipe("", k("date"), "", "x");
        recipe("c:x", k("date"), "x", "X", "");
        recipe("c:'", k("date"), "'");
        recipe("s:", none);
        recipe("s:'", k("date"), "'");
        recipe("s:it's", none);
        recipe("s:''", none);
        recipe("c:\u00e9|s:\u00e0b", k("date"), "\u00e9\u00e0b", "\u00c9\u00c0B");
        // Flint folds only ASCII case (deviation recorded on appendLiteral), so the upper-case non-ASCII input is
        // asserted in the D test instead.
        recipe("ci|c:\u00e9|s:\u00e0b", k("date"), "\u00e9\u00e0b", "\u00e9\u00e0B");
        recipe("cs|ci|strict|lenient|cs|strict", none);
        recipe("ci|p:uuuu-MM-dd|s:T|cs|p:HH", k("dateTime"), "2024-03-05T10", "2024-03-05t10");
        recipe("ci|p:uuuu-MM-dd|s:t|cs|s:x", k("date"), "2024-03-05tx", "2024-03-05TX", "2024-03-05Tx");
        // Optional sections: empty ones are dropped, open ones are closed, settings inside are kept after a failure.
        recipe("[|]", none);
        recipe("[|[|]|]", none);
        recipe("p:uuuu|[|]|p:-MM-dd", k("date"), "2024-03-05");
        recipe("p:uuuu-MM-dd|[|c:T", k("date", "dateTime"), "2024-03-05", "2024-03-05T");
        recipe("p:uuuu-MM-dd|[|p:'T'HH:mm|]|[|offid|]", k("date", "dateTime", "offset"),
                "2024-03-05", "2024-03-05T10:15", "2024-03-05T10:15+01:00", "2024-03-05+01:00", "2024-03-05T10:15Z",
                "2024-03-05T10:15+01", "2024-03-05T10");
        recipe("p:uuuu-MM-dd|[|ci|s:Tx|]|s:ab", k("date"), "2024-03-05ab", "2024-03-05tXab", "2024-03-05AB",
                "2024-03-05Tyab");
        recipe("p:uuuu-MM-dd|[|lenient|s:T|]|p:HH", k("dateTime"), "2024-03-05T10", "2024-03-05 10");
        recipe("p:[uuuu-MM-dd|c:x", k("date"), "2024-03-05x", "x", "2024-03x");
        recipe("[|p:uuuu]-MM-dd", k("date"), "2024-03-05", "-03-05");
        recipe("[|p:uuuu]-MM-dd|]", none);
        // appendPattern now also drops empty sections and keeps a non-ASCII literal whole.
        recipe("p:uuuu[]MM", k("date"), "202403");
        recipe("p:uuuu[[]]-MM-dd", k("date"), "2024-03-05");
        recipe("p:dd\u00b7MM\u00b7uuuu", k("date"), "05\u00b703\u00b72024");
        recipe("p:dd'\u00e9t\u00e9'MM uuuu", k("date"), "05\u00e9t\u00e903 2024");
        recipe("p:uuuu-MM-dd'T'HH:mm[:ss][.SSS]XXX", k("offset"), "2024-03-05T10:15+01:00",
                "2024-03-05T10:15:30.123Z");
        // append and appendOptional: descriptions, adjacent values stop at the appended formatter, and a missing
        // field in an appended formatter inside an optional section drops only that formatter's output.
        recipe("a:ISO_LOCAL_DATE", k("date"), "2024-03-05");
        recipe("q:ISO_LOCAL_DATE", k("date"), "2024-03-05", "");
        recipe("a:ISO_LOCAL_DATE|c:T|a:ISO_LOCAL_TIME", k("dateTime"), "2024-03-05T10:15", "2024-03-05t10:15");
        recipe("a:ISO_LOCAL_DATE_TIME|c:z", k("dateTime"), "2024-03-05T10:15z", "2024-03-05T10:15Z",
                "2024-03-05t10:15Z");
        recipe("a:ISO_DATE_TIME", none);
        recipe("a:ISO_OFFSET_DATE_TIME|q:=' 'VV", k("offset", "zoned"), "2024-03-05T10:15:30+01:00",
                "2024-03-05T10:15:30+01:00 +01:00", "2024-03-05T10:15:30Z UTC");
        recipe("a:ISO_LOCAL_DATE|q:ISO_LOCAL_TIME", k("date", "dateTime"), "2024-03-0510:15");
        recipe("a:=uuuu|a:=MM", k("date"), "202403", "2024");
        recipe("p:uuuu|a:=MMdd", k("date"), "20240305", "2024030");
        recipe("p:uuuu|q:=MMdd", k("date"), "20240305", "2024");
        recipe("a:=", none);
        recipe("q:=", k("date"), "");
        recipe("a:=''", k("date"), "'");
        recipe("[|c:<|a:=HH|c:>|]", k("date"), "<>", "<10>");
        recipe("[|c:<|q:=HH|c:>|]", k("date"), "<>");
        recipe("p:uuuu-MM-dd|[|c:<|a:=HH|c:>|]|s:!", k("date", "dateTime"), "2024-03-05<>!");
        recipe("a:BASIC_ISO_DATE|a:ISO_ORDINAL_DATE", none);
        recipe("q:ISO_DATE|q:ISO_TIME", none);
        recipe("a:ISO_INSTANT|s:@", none);
        // Offsets, zones and the instant.
        recipe("p:uuuu-MM-dd'T'HH:mm|offid", k("offset"), "2024-03-05T10:15+01:00", "2024-03-05T10:15Z",
                "2024-03-05T10:15+01", "2024-03-05T10:15+0100", "2024-03-05T10:15z");
        for (String pattern : new String[] {"+HH", "+HHmm", "+HH:mm", "+HHMM", "+HH:MM", "+HHMMss", "+HH:MM:ss",
                "+HHMMSS", "+HH:MM:SS", "+HHmmss", "+HH:mm:ss"})
            recipe("p:uuuu-MM-dd'T'HH:mm|o:" + pattern + ",none", k("offset"), "2024-03-05T10:15+01",
                    "2024-03-05T10:15+0130", "2024-03-05T10:15+01:30", "2024-03-05T10:15+013015",
                    "2024-03-05T10:15+01:30:15", "2024-03-05T10:15none", "2024-03-05T10:15NONE");
        recipe("p:uuuu-MM-dd'T'HH:mm|o:+HH:MM,it's", k("offset"), "2024-03-05T10:15it's");
        recipe("p:uuuu-MM-dd'T'HH:mm|o:+HH:MM,", k("offset"), "2024-03-05T10:15", "2024-03-05T10:15+00:00");
        recipe("p:uuuu-MM-dd'T'HH:mm|lenient|o:+HH,Z", k("offset"), "2024-03-05T10:15+01:30",
                "2024-03-05T10:15+0130", "2024-03-05T10:15+01");
        recipe("p:uuuu-MM-dd'T'HH:mm|offid|c:[|zid|c:]", k("offset", "zoned"),
                "2024-03-05T10:15+01:00[+01:00]", "2024-03-05T10:15Z[UTC]");
        recipe("p:uuuu-MM-dd'T'HH:mm|offid|[|c:[|zrid|c:]|]", k("offset", "zoned"),
                "2024-03-05T10:15+01:00", "2024-03-05T10:15Z[UTC]", "2024-03-05T10:15+01:00[+01:00]");
        recipe("zid", none);
        recipe("zrid", none);
        // appendZoneOrOffsetId: the zone ID when there is one, otherwise the offset.
        formatsAll("zo");
        formatsAll("p:uuuu-MM-dd'T'HH:mm|zo");
        parses("p:uuuu-MM-dd'T'HH:mm|zo", k("offset", "zoned"), "2024-03-05T10:15+01:00",
                "2024-03-05T10:15Z", "2024-03-05T10:15-05:30:15");
        formatsAll("p:uuuu-MM-dd'T'HH:mm|[|zo|]");
        parses("p:uuuu-MM-dd'T'HH:mm|[|zo|]", k("dateTime", "offset"), "2024-03-05T10:15",
                "2024-03-05T10:15+01:00");
        recipe("inst", k("offset", "zoned"), "2024-03-05T10:15:30Z", "2024-03-05t10:15:30z",
                "2024-03-05T10:15:30.5+01:00", "2024-03-05T10:15Z");
        recipe("ci|inst", k("offset", "zoned"), "2024-03-05t10:15:30z");
        recipe("inst|s:Ab", k("offset", "zoned"), "2024-03-05T10:15:30ZAb", "2024-03-05T10:15:30Zab");
        recipe("ci|inst|cs|s:Ab", k("offset", "zoned"), "2024-03-05T10:15:30zAb", "2024-03-05T10:15:30Zab");
        recipe("s:at |inst", k("zoned"), "at 2024-03-05T10:15:30Z");
        // appendInstant(int): the fractional digits printed and parsed, and the counts it refuses.
        for (String digits : new String[] {"-2", "10"})
            recipe("i:" + digits, none);
        for (String digits : new String[] {"-1", "0", "1", "3", "6", "9"}) {
            recipe("i:" + digits, k("offset", "zoned"), "2024-03-05T10:15:30Z", "2024-03-05T10:15:30.Z",
                    "2024-03-05T10:15:30.5Z", "2024-03-05T10:15:30.123Z", "2024-03-05T10:15:30.123456Z",
                    "2024-03-05T10:15:30.123456789Z", "2024-03-05T10:15:30.1234567891Z", "2024-03-05t10:15:30.1z",
                    "2024-03-05T10:15:30.120+01:00", "2024-03-05T10:15Z");
            instants("i:" + digits, "2024-03-05T10:15:30.000000001Z", "2024-03-05T10:15:30.100Z",
                    "2024-03-05T10:15:30.123456Z", "2024-03-05T10:15:30.987654321Z", "2024-03-05T10:15:00Z",
                    "+12345-06-07T08:09:10.5Z", "-0001-12-31T23:59:59.999Z", "1969-12-31T23:59:59.9Z");
            recipe("ci|i:" + digits + "|s:x", k("offset"), "2024-03-05T10:15:30.000000000zX");
        }
        // Localized offsets: appendLocalizedOffset and the pattern letters O, OOOO and ZZZZ, with Java's parse rules
        // (a seconds group, and in SHORT a minutes group, is read only when the whole group fits in the text).
        for (String style : new String[] {"NARROW", "FULL_STANDALONE", "SHORT_STANDALONE", "NARROW_STANDALONE"})
            recipe("l:" + style, none);
        for (String pattern : new String[] {"OO", "OOO", "OOOOO", "ZZZZZZ"})
            recipe("p:" + pattern, none);
        String[] localized = {"GMT", "GMT+01:00", "GMT-05:30", "GMT+01:00:30", "GMT+01:00:3", "GMT+01:0", "GMT+1",
            "GMT+10", "GMT+1:30", "GMT+1:30:15", "GMT+1:3", "GMT+01", "GMT+0100", "GMT+123", "GMT+", "GMT-", "GMTx",
            "gmt+01:00", "GMT+99:59", "GMT+18:00", "GMT+18:00:01", "GMT-18:00", "GMT+24", "GMT+00:00", "GMT-0",
            "UTC", ""};
        for (String recipe : new String[] {"p:uuuu-MM-dd'T'HH:mm|l:FULL", "p:uuuu-MM-dd'T'HH:mm|l:SHORT",
                "p:uuuu-MM-dd'T'HH:mmOOOO", "p:uuuu-MM-dd'T'HH:mmO", "p:uuuu-MM-dd'T'HH:mmZZZZ"}) {
            String[] inputs = new String[localized.length];
            for (int i = 0; i < localized.length; i++)
                inputs[i] = "2024-03-05T10:15" + localized[i];
            recipe(recipe, k("offset"), inputs);
            formats(recipe, "2024-03-05T10:15+10:00", "2024-03-05T10:15-18:00", "2024-03-05T10:15+05:30",
                    "2024-03-05T10:15-00:30", "2024-03-05T10:15+12:34:56", "2024-03-05T10:15-09:00:05",
                    "2024-03-05T10:15+18:00", "2024-03-05T10:15-00:00:01");
        }
        recipe("ci|p:uuuu-MM-dd'T'HH:mm|l:FULL", k("offset"), "2024-03-05T10:15gmt+01:00", "2024-03-05T10:15Gmt");
        recipe("p:uuuu-MM-dd'T'HH:mm|l:FULL|s:x", k("offset"), "2024-03-05T10:15GMT+01:00:30x",
                "2024-03-05T10:15GMT+01:00:3x", "2024-03-05T10:15GMT+01:00x", "2024-03-05T10:15GMTx",
                "2024-03-05T10:15GMT+01x", "2024-03-05T10:15GMT+0x", "2024-03-05T10:15GMT+01:00:xx");
        recipe("p:uuuu-MM-dd'T'HH:mm|l:SHORT|s:x", k("offset"), "2024-03-05T10:15GMT+1:30:15x",
                "2024-03-05T10:15GMT+1:30x", "2024-03-05T10:15GMT+1:3x", "2024-03-05T10:15GMT+1x",
                "2024-03-05T10:15GMT+12:00:0x", "2024-03-05T10:15GMT+x");
        recipe("p:uuuu-MM-dd'T'HH:mm|[|l:SHORT|]", k("dateTime", "offset"), "2024-03-05T10:15",
                "2024-03-05T10:15GMT+2");
        recipe("p:uuuu-MM-dd'T'HH:mm|l:FULL|offid", k("offset"), "2024-03-05T10:15GMT+01:00",
                "2024-03-05T10:15GMT+01:00Z", "2024-03-05T10:15GMT+02:00+02:00");
        // Java's positions count UTF-16 units: a non-ASCII prefix, and characters outside ASCII where digits belong.
        for (String style : new String[] {"FULL", "SHORT"})
            recipe("s:\u00e9|p:uuuu-MM-dd'T'HH:mm|l:" + style, k("offset"), "\u00e92024-03-05T10:15GMT+1",
                    "\u00e92024-03-05T10:15GMT+\u00e9", "\u00e92024-03-05T10:15GMT+\u00e90",
                    "\u00e92024-03-05T10:15GMT+\ud83d\ude00", "\u00e92024-03-05T10:15GMT+0\ud83d\ude00",
                    "\u00e92024-03-05T10:15GMT+01:\ud83d\ude00", "\u00e92024-03-05T10:15GMT+1:\u00e9\u00e9",
                    "\u00e92024-03-05T10:15GMT+01:00:\u00e9\u00e9", "\u00e92024-03-05T10:15GMT\u00e9");
        // padNext: the pad wraps the next appended element (a value, literal, offset, zone, settings element,
        // optional section, or appended formatter), its Pad(...) description and pad character, and Java's pad parse
        // rules: a strict parse needs the whole width and a lenient one treats it as a maximum.
        for (String width : new String[] {"0", "-2"})
            recipe("P:" + width + "|p:HH", none);
        recipe("P:2|p:HH", k("time"), "10", " 1");
        recipe("P:5|p:HH:mm", k("time"), "   10:15", "10:15", " 1:30", " 10:15", " 1:3", "  1:2",
                "   10", "   10:15x");
        recipe("P:5,*|p:HH", k("time"), "***10");
        recipe("P:5,0|p:HH", k("time"), "00010", " 0010", "000010");
        recipe("P:1|p:HH", k("time"), "10", "  10");
        recipe("P:3|p:HH", k("time"), " 10", "  10", "  100", "  1");
        recipe("P:3,\u00e9|s:x", k("date"), "\u00e9\u00e9x");
        recipe("P:5|s:ab", k("date"), "   ab");
        recipe("P:3|p:'x'", k("date"), "  x");
        recipe("P:5|cs|p:HH", k("time"), "     10"); // the pad wraps the settings element
        recipe("P:8|[|p:HH:mm|]", k("time"), "   10:15"); // the pad wraps the whole optional section
        recipe("P:5|[|]|p:HH", k("time"), "   10"); // an empty section leaves the pad pending
        recipe("P:6|p:uuuu-MM|p:-dd", k("date"), "  2024-03-05", "  2024-03"); // only the next atom
        recipe("P:12|a:ISO_LOCAL_TIME", k("time"), "    10:15:30");
        recipe("P:12|q:ISO_LOCAL_TIME", k("time"), "    10:15:30");
        recipe("p:uuuu-MM-dd'T'|P:5|p:HH", k("dateTime"), "2024-03-05T   10", "2024-03-05T10",
                "2024-03-05T   1", "2024-03-05T    1");
        recipe("p:uuuu-MM-dd'T'HH:mm|P:10|offid", k("offset"), "2024-03-05T10:15  +01:00",
                "2024-03-05T10:15       Z", "2024-03-05T10:15+01:00");
        recipe("p:uuuu-MM-dd'T'HH:mm|P:10|zid", k("zoned"), "2024-03-05T10:15  +01:00",
                "2024-03-05T10:15     UTC");
        recipe("lenient|P:4|p:HH", k("time"), "10", "  1", "1", "  10", "   10", "    10");
        recipe("ci|P:4,x|p:HH", k("time"), "xxxx10", "XXXX10", "XxXx10", "xxxx1");
        // Java's pad error index counts the start twice, so a long prefix reports an index past the end of the text;
        // the non-ASCII prefix checks that the index is in UTF-16 units.
        recipe("s:\u00e9\u00e9|P:4|s:1", k("date"), "\u00e9\u00e9  1x", "\u00e9\u00e9  1",
                "\u00e9\u00e9  12");
        Files.write(Path.of(a[0]), lines);
    }
}
