// Writes the golden file that framework/java/tests/time_test.d compares: DateTimeFormatter.withDecimalStyle with
// zero digits, signs and decimal separators, formatting and parsing through each formatter. Each line is
// `op<TAB>style<TAB>formatter<TAB>input<TAB>result`; a result is the value's toString() or `!` and the exception
// message (and a parse exception's error index). Text outside printable ASCII, and the backslash, is written as
// a Java unicode escape; a lone surrogate Java prints is written as U+FFFD, as Flint's UTF-8 output carries it
// (R14). Parse inputs never contain a surrogate.
//   javac GoldenDecimalStyle.java && java GoldenDecimalStyle decimal_style.tsv
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.*;
import java.time.format.*;
import java.time.temporal.TemporalAccessor;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public class GoldenDecimalStyle {
    static final java.util.Set<String> lines = new java.util.LinkedHashSet<>();
    static final Map<String, DecimalStyle> styles = new LinkedHashMap<>();
    static final Map<String, DateTimeFormatter> formatters = new LinkedHashMap<>();
    static final Map<String, String> kinds = new LinkedHashMap<>();

    static String esc(String s) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            boolean paired = Character.isHighSurrogate(c) && i + 1 < s.length() && Character.isLowSurrogate(s.charAt(i + 1))
                || Character.isLowSurrogate(c) && i > 0 && Character.isHighSurrogate(s.charAt(i - 1));
            if (Character.isSurrogate(c) && !paired) c = '�';
            if (c >= 0x20 && c < 0x7f && c != '\\') b.append(c);
            else b.append(String.format("\\u%04X", (int) c));
        }
        return b.toString();
    }

    static String err(Throwable e) {
        String s = "!" + esc(e.getMessage());
        if (e instanceof DateTimeParseException p) s += "\t" + p.getErrorIndex();
        return s;
    }

    static String run(java.util.function.Supplier<Object> f) {
        try { return esc(String.valueOf(f.get())); } catch (DateTimeException e) { return err(e); }
    }

    static void row(String op, String style, String formatter, String in, String out) {
        lines.add(op + "\t" + style + "\t" + formatter + "\t" + esc(in) + "\t" + out);
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

    static List<TemporalAccessor> values(String kind) {
        List<TemporalAccessor> v = new ArrayList<>();
        LocalDate[] dates = {LocalDate.of(2024, 3, 5), LocalDate.of(1, 1, 1), LocalDate.of(-42, 1, 2),
            LocalDate.of(12345, 6, 7), LocalDate.of(9999, 12, 31), LocalDate.of(0, 10, 20)};
        LocalTime[] times = {LocalTime.of(9, 8, 7), LocalTime.of(23, 59, 59, 123), LocalTime.of(0, 0),
            LocalTime.of(12, 34, 56, 789_000_000), LocalTime.of(13, 5, 0, 500_000_000)};
        ZoneOffset[] offsets = {ZoneOffset.ofHoursMinutes(-5, -30), ZoneOffset.UTC, ZoneOffset.ofHours(14)};
        switch (kind) {
            case "date" -> v.addAll(List.of(dates));
            case "time" -> v.addAll(List.of(times));
            case "dateTime" -> { for (int i = 0; i < dates.length; i++) v.add(LocalDateTime.of(dates[i], times[i % times.length])); }
            case "offset" -> { for (int i = 0; i < dates.length; i++) v.add(OffsetDateTime.of(dates[i], times[i % times.length], offsets[i % 3])); }
            default -> { for (int i = 0; i < dates.length; i++) v.add(OffsetDateTime.of(dates[i], times[i % times.length], offsets[i % 3]).toInstant()); }
        }
        return v;
    }

    // `ascii` with each digit written in the style's digits.
    static String digits(DecimalStyle s, String ascii) {
        StringBuilder b = new StringBuilder();
        for (char c : ascii.toCharArray()) b.append(c >= '0' && c <= '9' ? (char) (s.getZeroDigit() + (c - '0')) : c);
        return b.toString();
    }

    static boolean hasSurrogate(String s) {
        for (char c : s.toCharArray()) if (Character.isSurrogate(c)) return true;
        return false;
    }

    static void formatter(String name, String kind, DateTimeFormatter f) {
        formatters.put(name, f);
        kinds.put(name, kind);
    }

    public static void main(String[] a) throws Exception {
        DecimalStyle s = DecimalStyle.STANDARD;
        styles.put("STANDARD", s);
        styles.put("ARABIC", s.withZeroDigit('٠'));
        styles.put("DEVANAGARI", s.withZeroDigit('०').withPositiveSign('P').withNegativeSign('N').withDecimalSeparator('٫'));
        styles.put("MINUS", s.withNegativeSign('−'));
        styles.put("COMMA", s.withDecimalSeparator(','));
        styles.put("LETTERS", s.withZeroDigit('A').withPositiveSign('p').withNegativeSign('n').withDecimalSeparator('d'));
        styles.put("WRAP", s.withZeroDigit('￸'));
        styles.put("SURROGATE", s.withZeroDigit('ퟻ'));
        styles.put("SAMESIGN", s.withPositiveSign('-'));
        styles.put("DIGITSIGN", s.withPositiveSign('1').withNegativeSign('2'));
        styles.put("NUL", s.withZeroDigit('\u0000').withDecimalSeparator('\u0000'));
        styles.put("FULLWIDTH", s.withNegativeSign('－').withPositiveSign('＋').withDecimalSeparator('。'));

        formatter("ISO_LOCAL_DATE", "date", DateTimeFormatter.ISO_LOCAL_DATE);
        formatter("ISO_LOCAL_TIME", "time", DateTimeFormatter.ISO_LOCAL_TIME);
        formatter("ISO_LOCAL_DATE_TIME", "dateTime", DateTimeFormatter.ISO_LOCAL_DATE_TIME);
        formatter("ISO_OFFSET_DATE_TIME", "offset", DateTimeFormatter.ISO_OFFSET_DATE_TIME);
        formatter("ISO_INSTANT", "instant", DateTimeFormatter.ISO_INSTANT.withZone(ZoneOffset.UTC));
        formatter("BASIC_ISO_DATE", "date", DateTimeFormatter.BASIC_ISO_DATE);
        formatter("ISO_ORDINAL_DATE", "date", DateTimeFormatter.ISO_ORDINAL_DATE);
        formatter("ISO_WEEK_DATE", "date", DateTimeFormatter.ISO_WEEK_DATE);
        formatter("ISO_DATE", "date", DateTimeFormatter.ISO_DATE);
        formatter("ISO_TIME", "time", DateTimeFormatter.ISO_TIME);
        formatter("RFC_1123_DATE_TIME", "offset", DateTimeFormatter.RFC_1123_DATE_TIME);
        for (String[] p : new String[][] {
                {"uuuu-MM-dd", "date"}, {"u-M-d", "date"}, {"yy-MM-dd", "date"}, {"yyyy-MM-dd", "date"},
                {"uuuuMMdd", "date"}, {"uuuu D", "date"}, {"HH:mm:ss.SSS", "time"}, {"H:m:s n", "time"},
                {"hh:mm a", "time"}, {"uuuu-MM-dd'T'HH:mm:ssXXX", "offset"},
                {"uuuu-MM-dd HH:mm:ss.SSSSSSSSS xx", "offset"}, {"EEE, d MMM uuuu", "date"}}) {
            formatter(p[0], p[1], DateTimeFormatter.ofPattern(p[0]));
        }

        lines.add("getDecimalStyle\t-\tISO_LOCAL_DATE\t-\t" + esc(DateTimeFormatter.ISO_LOCAL_DATE.getDecimalStyle().toString()));
        lines.add("getDecimalStyle\t-\tuuuu-MM-dd\t-\t" + esc(DateTimeFormatter.ofPattern("uuuu-MM-dd").getDecimalStyle().toString()));
        for (Map.Entry<String, DecimalStyle> st : styles.entrySet()) {
            DateTimeFormatter iso = DateTimeFormatter.ISO_LOCAL_DATE.withDecimalStyle(st.getValue());
            lines.add("getDecimalStyle\t" + st.getKey() + "\tISO_LOCAL_DATE\t-\t" + esc(iso.getDecimalStyle().toString()));
            lines.add("toString\t" + st.getKey() + "\tISO_LOCAL_DATE\t-\t" + esc(iso.toString()));
        }
        DateTimeFormatter zoned = DateTimeFormatter.ISO_LOCAL_DATE.withDecimalStyle(styles.get("ARABIC")).withZone(ZoneOffset.UTC);
        lines.add("getDecimalStyle\tARABIC\tISO_LOCAL_DATE.withZone\t-\t" + esc(zoned.getDecimalStyle().toString()));
        DateTimeFormatter resolved = DateTimeFormatter.ISO_LOCAL_DATE.withDecimalStyle(styles.get("ARABIC")).withResolverStyle(ResolverStyle.SMART);
        lines.add("getDecimalStyle\tARABIC\tISO_LOCAL_DATE.withResolverStyle\t-\t" + esc(resolved.getDecimalStyle().toString()));

        for (Map.Entry<String, DecimalStyle> st : styles.entrySet()) {
            DecimalStyle style = st.getValue();
            for (Map.Entry<String, DateTimeFormatter> fe : formatters.entrySet()) {
                String kind = kinds.get(fe.getKey());
                DateTimeFormatter f = fe.getValue().withDecimalStyle(style);
                DateTimeFormatter standard = fe.getValue();
                for (TemporalAccessor v : values(kind)) {
                    String out;
                    try { out = f.format(v); } catch (DateTimeException e) { row("format", st.getKey(), fe.getKey(), v.toString(), err(e)); continue; }
                    row("format", st.getKey(), fe.getKey(), v.toString(), esc(out));
                    if (!hasSurrogate(out)) row("parse", st.getKey(), fe.getKey(), out, run(() -> parse(kind, out, f)));
                    String plain = standard.format(v);
                    if (!plain.equals(out)) row("parse", st.getKey(), fe.getKey(), plain, run(() -> parse(kind, plain, f)));
                }
            }
            // Signs and zero values through numbers of each sign style.
            List<String[]> crafted = new ArrayList<>();
            char p = style.getPositiveSign(), n = style.getNegativeSign();
            for (String text : new String[] {"2024-3-5", "42-1-2", "0-1-1", "12345-6-7"}) {
                crafted.add(new String[] {"u-M-d", p + digits(style, text)});
                crafted.add(new String[] {"u-M-d", n + digits(style, text)});
                crafted.add(new String[] {"u-M-d", digits(style, text)});
                crafted.add(new String[] {"u-M-d", "+" + text});
                crafted.add(new String[] {"u-M-d", "-" + text});
            }
            for (String text : new String[] {"2024-03-05", "12345-06-07", "0000-01-01", "0042-01-02"}) {
                crafted.add(new String[] {"uuuu-MM-dd", p + digits(style, text)});
                crafted.add(new String[] {"uuuu-MM-dd", n + digits(style, text)});
                crafted.add(new String[] {"uuuu-MM-dd", digits(style, text)});
                crafted.add(new String[] {"ISO_LOCAL_DATE", p + digits(style, text)});
                crafted.add(new String[] {"ISO_LOCAL_DATE", n + digits(style, text)});
            }
            for (String text : new String[] {"09:08:07", "09:08:07.5", "09:08:07.123456789", "09:08:07.1234567891"}) {
                String local = digits(style, text).replace('.', style.getDecimalSeparator());
                crafted.add(new String[] {"ISO_LOCAL_TIME", local});
                crafted.add(new String[] {"ISO_LOCAL_TIME", digits(style, text)});
                crafted.add(new String[] {"ISO_LOCAL_TIME", digits(style, text).replace('.', ',')});
            }
            crafted.add(new String[] {"ISO_INSTANT", digits(style, "2024-03-05T09:08:07Z")});
            crafted.add(new String[] {"ISO_INSTANT", digits(style, "2024-03-05T09:08:07.25Z").replace('.', style.getDecimalSeparator())});
            crafted.add(new String[] {"ISO_OFFSET_DATE_TIME", digits(style, "2024-03-05T09:08:07") + "+05:30"});
            crafted.add(new String[] {"ISO_OFFSET_DATE_TIME", digits(style, "2024-03-05T09:08:07+05:30")});
            crafted.add(new String[] {"yy-MM-dd", digits(style, "24-03-05")});
            crafted.add(new String[] {"yy-MM-dd", p + digits(style, "24-03-05")});
            crafted.add(new String[] {"RFC_1123_DATE_TIME", "Tue, " + digits(style, "5 Mar 2024 09:08:07") + " GMT"});
            for (String[] c : crafted) {
                if (hasSurrogate(c[1])) continue;
                DateTimeFormatter f = formatters.get(c[0]).withDecimalStyle(style);
                String kind = kinds.get(c[0]);
                row("parse", st.getKey(), c[0], c[1], run(() -> parse(kind, c[1], f)));
            }
        }
        Files.write(Path.of(a[0]), lines);
    }
}
