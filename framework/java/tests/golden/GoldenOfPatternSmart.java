// Writes the golden file that framework/java/tests/time_test.d compares: DateTimeFormatter.ofPattern's default
// SMART resolution (day 29-31 past the month's end, 24:00, clock hour 0, year-of-era range) when parsing into each
// temporal type, withResolverStyle, and LocalDate.ofYearDay's range errors. Each line is `kind<TAB>input<TAB>result`,
// the result being the toString() or `!` and the exception message (and a parse exception's error index); a
// formatter input is `pattern|text` or `CONSTANT|text`.
//   javac GoldenOfPatternSmart.java && java GoldenOfPatternSmart ofpattern_smart.tsv
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.*;
import java.time.format.*;
import java.util.ArrayList;
import java.util.List;

public class GoldenOfPatternSmart {
    static final List<String> lines = new ArrayList<>();

    static String err(Throwable e) {
        String s = "!" + e.getMessage();
        if (e instanceof DateTimeParseException p) s += "\t" + p.getErrorIndex();
        return s;
    }

    static void row(String op, String in, java.util.function.Supplier<Object> f) {
        String out;
        try { out = String.valueOf(f.get()); } catch (DateTimeException e) { out = err(e); }
        lines.add(op + "\t" + in + "\t" + out);
    }

    public static void main(String[] a) throws Exception {
        String[][] cases = {
            {"uuuu-MM-dd", "2023-06-15"},
            {"uuuu-MM-dd", "2024-02-29"},
            {"uuuu-MM-dd", "2023-02-29"},
            {"uuuu-MM-dd", "2024-02-30"},
            {"uuuu-MM-dd", "2023-02-31"},
            {"uuuu-MM-dd", "2023-04-31"},
            {"uuuu-MM-dd", "2023-04-30"},
            {"uuuu-MM-dd", "2023-04-32"},
            {"uuuu-MM-dd", "2023-00-10"},
            {"uuuu-MM-dd", "2023-13-01"},
            {"uuuu-MM-dd", "2023-01-00"},
            {"uuuu-MM-dd", "1900-02-29"},
            {"uuuu-MM-dd", "2000-02-30"},
            {"uuuu-MM-dd", "-0001-02-29"},
            {"uuuu-MM-dd", "+999999999-12-31"},
            {"uuuu-MM-dd", "+1000000000-01-01"},
            {"yyyy-MM-dd", "2023-02-31"},
            {"yyyy-MM-dd", "2024-02-30"},
            {"yyyy-MM-dd", "2023-06-15"},
            {"yyyy-MM-dd", "0000-01-01"},
            {"yyyy-MM-dd", "0001-01-01"},
            {"yyyy-MM-dd", "-0001-01-01"},
            {"yyyy-MM-dd", "+999999999-01-01"},
            {"yyyy-MM-dd", "+1000000000-01-01"},
            {"dd/MM/yyyy", "31/02/2023"},
            {"dd/MM/yyyy", "31/11/2023"},
            {"dd/MM/yyyy", "30/02/2024"},
            {"d MMM uuuu", "31 Feb 2023"},
            {"d MMMM uuuu", "31 September 2023"},
            {"uuuu-DDD", "2023-365"},
            {"uuuu-DDD", "2023-366"},
            {"uuuu-DDD", "2024-366"},
            {"uuuu-DDD", "2023-000"},
            {"uuuu-DDD", "2023-367"},
            {"HH:mm", "23:59"},
            {"HH:mm", "24:00"},
            {"HH:mm", "24:01"},
            {"HH:mm", "25:00"},
            {"HH:mm:ss", "24:00:00"},
            {"HH:mm:ss", "24:00:01"},
            {"HH:mm:ss", "23:59:60"},
            {"HH:mm:ss.SSS", "24:00:00.000"},
            {"HH:mm:ss.SSS", "24:00:00.001"},
            {"HH", "24"},
            {"HH", "23"},
            {"uuuu-MM-dd HH:mm", "2023-12-31 24:00"},
            {"uuuu-MM-dd HH:mm", "2023-02-31 24:00"},
            {"uuuu-MM-dd HH:mm", "2024-02-29 24:00"},
            {"uuuu-MM-dd HH:mm", "2023-06-15 24:00"},
            {"uuuu-MM-dd HH:mm", "2023-06-15 24:30"},
            {"uuuu-MM-dd HH:mm", "+999999999-12-31 24:00"},
            {"uuuu-MM-dd HH:mm", "2023-06-31 12:00"},
            {"uuuu-MM-dd'T'HH:mm:ss", "2023-12-31T24:00:00"},
            {"hh:mm a", "00:30 AM"},
            {"hh:mm a", "00:30 PM"},
            {"hh:mm a", "12:30 AM"},
            {"hh:mm a", "12:30 PM"},
            {"hh:mm a", "11:30 PM"},
            {"hh:mm a", "13:30 PM"},
            {"h:mm a", "0:05 AM"},
            {"uuuu-MM-dd hh:mm a", "2023-02-31 00:15 PM"},
            {"EEE uuuu-MM-dd", "Tue 2023-02-31"},
            {"EEE uuuu-MM-dd", "Fri 2023-02-31"},
            {"EEE uuuu-MM-dd", "Thu 2023-06-15"},
            {"EEEE, d MMMM uuuu", "Tuesday, 31 February 2023"},
            {"uuuu-MM-dd'T'HH:mmXXX", "2023-02-31T10:00+01:00"},
            {"uuuu-MM-dd'T'HH:mmXXX", "2023-12-31T24:00Z"},
            {"uuuu-MM-dd'T'HH:mmXXX", "2023-12-31T24:00-05:00"},
            {"uuuu-MM-dd'T'HH:mmXXX", "2023-06-15T24:01+02:00"},
            {"uuuu-MM-dd'T'HH:mmxx", "2024-02-30T08:00+0530"},
            {"uuuu-MM-dd'T'HH:mmZ", "2023-04-31T08:00-0800"},
            {"uuuu-MM-dd[ HH:mm]", "2023-02-31"},
            {"uuuu-MM-dd[ HH:mm]", "2023-02-31 24:00"},
            {"uuuu-MM-dd HH:mm:ss.n", "2023-12-31 24:00:00.0"},
            {"uuuu-MM-dd HH:mm:ss.n", "2023-12-31 24:00:00.1"},
        };
        for (String[] c : cases) {
            DateTimeFormatter f = DateTimeFormatter.ofPattern(c[0]);
            String t = c[1], k = c[0] + "|" + t;
            row("parse", k, () -> { f.parse(t); return "parsed"; });
            row("parseLocalDate", k, () -> LocalDate.parse(t, f));
            row("parseLocalTime", k, () -> LocalTime.parse(t, f));
            row("parseLocalDateTime", k, () -> LocalDateTime.parse(t, f));
            row("parseOffsetDateTime", k, () -> OffsetDateTime.parse(t, f));
            row("parseZonedDateTime", k, () -> ZonedDateTime.parse(t, f));
        }
        // The same uuuu patterns resolved STRICT, and ISO formatters resolved SMART; `y` patterns resolved STRICT do
        // not resolve a date, but Java's message lists the unresolved fields, which Flint does not yet.
        for (String[] c : cases) {
            if (c[0].contains("y")) continue;
            DateTimeFormatter f = DateTimeFormatter.ofPattern(c[0]).withResolverStyle(ResolverStyle.STRICT);
            String t = c[1], k = c[0] + "|" + t;
            row("strictParse", k, () -> { f.parse(t); return "parsed"; });
            row("strictParseLocalDate", k, () -> LocalDate.parse(t, f));
            row("strictParseLocalDateTime", k, () -> LocalDateTime.parse(t, f));
        }
        String[][] iso = {
            {"ISO_LOCAL_DATE", "2023-02-31"}, {"ISO_LOCAL_DATE", "2024-02-30"}, {"ISO_LOCAL_DATE", "2023-04-31"},
            {"ISO_LOCAL_DATE", "2023-04-32"}, {"ISO_LOCAL_DATE_TIME", "2023-12-31T24:00"},
            {"ISO_LOCAL_DATE_TIME", "2023-02-31T24:00:00"}, {"ISO_LOCAL_DATE_TIME", "2023-06-15T24:00:01"},
            {"ISO_OFFSET_DATE_TIME", "2023-12-31T24:00Z"}, {"ISO_LOCAL_TIME", "24:00"},
        };
        for (String[] c : iso) {
            DateTimeFormatter f = (DateTimeFormatter) DateTimeFormatter.class.getField(c[0]).get(null);
            DateTimeFormatter smart = f.withResolverStyle(ResolverStyle.SMART);
            String t = c[1], k = c[0] + "|" + t;
            row("smartParseLocalDate", k, () -> LocalDate.parse(t, smart));
            row("smartParseLocalDateTime", k, () -> LocalDateTime.parse(t, smart));
            row("smartParseLocalTime", k, () -> LocalTime.parse(t, smart));
            row("isoParseLocalDateTime", k, () -> LocalDateTime.parse(t, f));
        }
        row("getResolverStyle", "ofPattern", () -> DateTimeFormatter.ofPattern("uuuu").getResolverStyle());
        row("getResolverStyle", "ISO_LOCAL_DATE", () -> DateTimeFormatter.ISO_LOCAL_DATE.getResolverStyle());
        row("getResolverStyle", "RFC_1123_DATE_TIME", () -> DateTimeFormatter.RFC_1123_DATE_TIME.getResolverStyle());
        row("getResolverStyle", "ofPattern/STRICT",
            () -> DateTimeFormatter.ofPattern("uuuu").withResolverStyle(ResolverStyle.STRICT).getResolverStyle());
        row("getResolverStyle", "ISO_LOCAL_DATE/SMART",
            () -> DateTimeFormatter.ISO_LOCAL_DATE.withResolverStyle(ResolverStyle.SMART).getResolverStyle());
        int[][] yearDays = {{2023, 365}, {2023, 366}, {2024, 366}, {2023, 0}, {2023, 367}, {-4, 366}, {-1, 366},
            {999999999, 1}, {-999999999, 365}, {1000000000, 1}, {1000000000, 0}};
        for (int[] v : yearDays)
            row("ofYearDay", v[0] + "," + v[1], () -> LocalDate.ofYearDay(v[0], v[1]));
        Files.write(Path.of(a[0]), lines);
    }
}
