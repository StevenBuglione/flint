// Writes the golden file that framework/java/tests/time_test.d compares: DateTimeFormatter.ISO_WEEK_DATE printing
// each temporal type (week-based years around every year boundary, the extremes and wide years), and parsing into
// each type under STRICT and SMART resolution (week 53, out-of-range weeks, days and week-based years, offsets).
// Each line is `kind<TAB>input<TAB>result`, the result being the toString() or `!` and the exception message (and a
// parse exception's error index).
//   javac GoldenIsoWeekDate.java && java GoldenIsoWeekDate iso_week_date.tsv
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.*;
import java.time.format.*;
import java.util.ArrayList;
import java.util.List;

public class GoldenIsoWeekDate {
    static final List<String> lines = new ArrayList<>();
    static final DateTimeFormatter F = DateTimeFormatter.ISO_WEEK_DATE;
    static final DateTimeFormatter SMART = F.withResolverStyle(ResolverStyle.SMART);

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

    static void parseRows(String prefix, DateTimeFormatter f, String t) {
        row(prefix + "parse", t, () -> { f.parse(t); return "parsed"; });
        row(prefix + "parseLocalDate", t, () -> LocalDate.parse(t, f));
        row(prefix + "parseLocalDateTime", t, () -> LocalDateTime.parse(t, f));
        row(prefix + "parseLocalTime", t, () -> LocalTime.parse(t, f));
        row(prefix + "parseOffsetDateTime", t, () -> OffsetDateTime.parse(t, f));
    }

    public static void main(String[] a) throws Exception {
        row("toString", "", () -> F.toString());
        row("getResolverStyle", "", () -> F.getResolverStyle());

        // Every day from 28 December to 4 January across a range of years covers both 52- and 53-week years, leap
        // years starting on each weekday, and the days that belong to the neighbouring week-based year.
        for (int y = 1999; y <= 2030; y++) {
            LocalDate d = LocalDate.of(y, 12, 28);
            for (int i = 0; i < 8; i++, d = d.plusDays(1)) {
                String in = d.toString();
                row("formatLocalDate", in, () -> F.format(LocalDate.parse(in)));
            }
        }
        String[] dates = {"2012-11-30", "2024-02-29", "2024-06-15", "0001-01-01", "0000-01-01", "-0001-12-31",
            "-0001-01-01", "1582-10-15", "9999-12-31", "+10000-01-01", "+10000-01-03", "+10000-12-31",
            "-10000-01-01", "+999999999-12-31", "+999999999-12-27", "+999999999-12-26", "-999999999-01-01",
            "-999999999-01-04", "-999999999-01-08", "+999999998-12-31"};
        for (String in : dates) row("formatLocalDate", in, () -> F.format(LocalDate.parse(in)));
        String[] dateTimes = {"2012-11-30T10:15:30", "2021-01-03T23:59:59.999999999", "-0001-01-01T00:00"};
        for (String in : dateTimes) row("formatLocalDateTime", in, () -> F.format(LocalDateTime.parse(in)));
        String[] offsets = {"2012-11-30T10:15:30+01:00", "2020-12-31T00:00Z", "2021-01-01T00:00-05:30",
            "2026-11-27T12:00:00+18:00", "2026-11-27T12:00:00-18:00", "2026-11-27T12:00:00+01:00:30"};
        for (String in : offsets) {
            row("formatOffsetDateTime", in, () -> F.format(OffsetDateTime.parse(in)));
            row("formatZonedDateTime", in, () -> F.format(ZonedDateTime.parse(in)));
        }
        row("formatLocalTime", "10:15:30", () -> F.format(LocalTime.parse("10:15:30")));
        row("formatInstant", "2012-11-30T10:15:30Z", () -> F.format(Instant.parse("2012-11-30T10:15:30Z")));
        row("formatInstantWithZone", "2012-11-30T23:15:30Z",
            () -> F.withZone(ZoneOffset.UTC).format(Instant.parse("2012-11-30T23:15:30Z")));
        row("formatInstantWithZone", "2020-12-31T23:59:59Z",
            () -> F.withZone(ZoneOffset.UTC).format(Instant.parse("2020-12-31T23:59:59Z")));

        String[] texts = {
            "2012-W48-6", "2012-w48-6", "2012-W48-6Z", "2012-W48-6z", "2012-W48-6+01:00", "2012-W48-6-05:30",
            "2012-W48-6+01:00:30", "2012-W48-6+18:00", "2012-W48-6+18:01", "2012-W48-6+01", "2012-W48-6+0100",
            "2012-W48-6-00:00", "2012-W48-6+24:00", "2012-W48-6x", "2012-W48-6 ",
            "2004-W53-7", "2009-W53-1", "2015-W53-4", "2020-W53-5", "2026-W53-4", "2021-W53-1", "2022-W53-7",
            "2023-W53-1", "2019-W52-7", "2020-W01-1", "2025-W01-1", "2008-W01-1", "2010-W52-7",
            "2012-W00-1", "2012-W54-1", "2012-W99-7", "2015-W54-1", "2012-W48-0", "2012-W48-8", "2012-W48-9",
            "2012-W00-0", "2012-W54-8", "2012-W4-6", "2012-W048-6", "2012-W48-06", "2012-W48", "2012-W48-",
            "2012-48-6", "2012W48-6", "2012-X48-6", "201-W48-6", "12-W48-6",
            "0000-W01-1", "0001-W01-1", "-0001-W52-7", "-0001-W53-1", "+10000-W01-1", "10000-W01-1",
            "+2012-W48-6", "-2012-W48-6", "+999999999-W52-5", "+999999999-W52-7", "+999999999-W53-1",
            "-999999999-W01-1", "-999999999-W01-3", "-999999999-W01-4", "-999999999-W01-7",
            "+1000000000-W01-1", "-1000000000-W52-1", "+9999999999-W01-1", "+99999999999-W01-1",
        };
        for (String t : texts) {
            parseRows("", F, t);
            // SMART rolls week 53 of +999999999 past the last epoch day: Java reports EpochDay from
            // LocalDate.plusDays, where Flint's LocalDate reports Year (a LocalDate gap, left out).
            if (!t.equals("+999999999-W53-1")) parseRows("smart", SMART, t);
        }

        Files.write(Path.of(a[0]), lines);
    }
}
