// Writes the golden file that framework/java/tests/time_test.d compares: LocalDate.ofEpochDay and LocalDate's day and
// week arithmetic around every month length, the year boundary, the EpochDay range and long overflow, month and
// year arithmetic and the DayOfMonth range, and the LocalDateTime methods that reach them, including time
// arithmetic split into whole days. Each line is `kind<TAB>input<TAB>argument<TAB>result`, the result being
// the toString() or `!`, the exception's simple class name, `: ` and its message.
//   javac GoldenEpochDay.java && java GoldenEpochDay epoch_day.tsv
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.*;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Supplier;

public class GoldenEpochDay {
    static final List<String> lines = new ArrayList<>();

    static void row(String kind, String in, long arg, Supplier<Object> f) {
        String out;
        try { out = String.valueOf(f.get()); }
        catch (DateTimeException | ArithmeticException e) { out = "!" + e.getClass().getSimpleName() + ": " + e.getMessage(); }
        lines.add(kind + "\t" + in + "\t" + arg + "\t" + out);
    }

    public static void main(String[] a) throws Exception {
        long minDay = -365243219162L, maxDay = 365241780471L;
        long[] days = {0, 1, -1, 719162, -719162, 10957, 19723, minDay, maxDay, minDay - 1, maxDay + 1, minDay + 1,
            maxDay - 1, 1_000_000_000_000L, -1_000_000_000_000L, Long.MAX_VALUE, Long.MIN_VALUE};
        for (long d : days) row("ofEpochDay", "", d, () -> LocalDate.ofEpochDay(d));

        String[] dates = {"2010-09-07", "2024-01-01", "2024-01-31", "2023-01-31", "2024-02-01", "2024-02-28",
            "2024-02-29", "2023-02-28", "2024-04-30", "2024-11-30", "2024-12-01", "2024-12-31", "2023-12-03",
            "1970-01-01", "0000-03-01", "-0001-12-31", "+999999999-11-30", "+999999999-12-01", "+999999999-12-03",
            "+999999999-12-31", "-999999999-01-01", "-999999999-01-31"};
        long[] deltas = {0, 1, -1, 2, -2, 27, 28, 29, 30, 31, 32, 56, 57, 58, 59, 60, 61, 90, 365, 366, -27, -28,
            -29, -31, -59, -60, -365, -366, 730485, -730485, maxDay, minDay, maxDay - minDay, minDay - maxDay,
            1_000_000_000_000L, -1_000_000_000_000L, Long.MAX_VALUE, Long.MIN_VALUE, Long.MAX_VALUE - 30,
            Long.MIN_VALUE + 1};
        long[] weeks = {0, 1, -1, 4, -4, 5, 52, -52, 53, 104348, -104348, 52177397034L, -52177397034L,
            104354965948L, -104354965948L, Long.MAX_VALUE / 7, Long.MIN_VALUE / 7, Long.MAX_VALUE / 7 + 1,
            Long.MIN_VALUE / 7 - 1, Long.MAX_VALUE, Long.MIN_VALUE};
        long[] months = {0, 1, -1, 11, -13, 12, 24, 1_999_999_998L, -1_999_999_998L, 23_999_999_987L,
            -23_999_999_987L, Long.MAX_VALUE, Long.MIN_VALUE, Long.MAX_VALUE - 1, Long.MIN_VALUE + 1};
        long[] times = {0, 1, -1, 13, -14, 23, 24, 59, 60, 1439, 1440, 3599, 86_399, 86_400, -86_401,
            maxDay * 86400, minDay * 86400, Long.MAX_VALUE, Long.MIN_VALUE, Long.MAX_VALUE - 1, Long.MIN_VALUE + 1};
        for (String t : dates) {
            LocalDate date = LocalDate.parse(t);
            for (long d : deltas) {
                row("plusDays", t, d, () -> date.plusDays(d));
                row("minusDays", t, d, () -> date.minusDays(d));
            }
            for (long w : weeks) {
                row("plusWeeks", t, w, () -> date.plusWeeks(w));
                row("minusWeeks", t, w, () -> date.minusWeeks(w));
            }
            for (long m : months) {
                row("plusMonths", t, m, () -> date.plusMonths(m));
                row("minusMonths", t, m, () -> date.minusMonths(m));
                row("plusYears", t, m, () -> date.plusYears(m));
                row("minusYears", t, m, () -> date.minusYears(m));
            }
            for (long d : new long[] {0, 1, 28, 29, 30, 31, 32, -1, Integer.MIN_VALUE, Integer.MAX_VALUE})
                row("withDayOfMonth", t, d, () -> date.withDayOfMonth((int) d));
            LocalDateTime dateTime = date.atTime(10, 15, 30);
            for (long n : times) {
                row("dateTimePlusHours", t, n, () -> dateTime.plusHours(n));
                row("dateTimeMinusHours", t, n, () -> dateTime.minusHours(n));
                row("dateTimePlusMinutes", t, n, () -> dateTime.plusMinutes(n));
                row("dateTimeMinusMinutes", t, n, () -> dateTime.minusMinutes(n));
                row("dateTimePlusSeconds", t, n, () -> dateTime.plusSeconds(n));
                row("dateTimeMinusSeconds", t, n, () -> dateTime.minusSeconds(n));
            }
            for (long d : new long[] {1, -1, 31, 59, -60, maxDay, Long.MAX_VALUE, Long.MIN_VALUE}) {
                row("dateTimePlusDays", t, d, () -> dateTime.plusDays(d));
                row("dateTimeMinusDays", t, d, () -> dateTime.minusDays(d));
                row("dateTimePlusWeeks", t, d, () -> dateTime.plusWeeks(d));
            }
        }
        long[] seconds = {0, -1, 1_700_000_000L, maxDay * 86400 + 86399, maxDay * 86400 + 86400, minDay * 86400,
            minDay * 86400 - 1};
        for (long s : seconds) {
            row("ofEpochSecondUTC", "", s, () -> LocalDateTime.ofEpochSecond(s, 0, ZoneOffset.UTC));
            row("ofEpochSecondPlus2", "", s, () -> LocalDateTime.ofEpochSecond(s, 0, ZoneOffset.ofHours(2)));
        }
        Files.write(Path.of(a[0]), lines);
    }
}
