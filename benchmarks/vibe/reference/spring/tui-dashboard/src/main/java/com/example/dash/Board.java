package com.example.dash;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** The dashboard's state: metrics in first-seen order, the skipped-line count, sorting and the selection. */
public class Board {

    public record Row(String name, double value) {
    }

    private final Map<String, Double> metrics = new LinkedHashMap<>();
    private int skipped;
    private boolean sorted;
    private int selected;

    public void put(String name, double value) {
        metrics.put(name, value);
    }

    public void skip() {
        skipped++;
    }

    public void toggleSort() {
        sorted = !sorted;
    }

    public void move(int delta) {
        selected = Math.max(0, Math.min(metrics.size() - 1, selected + delta));
    }

    public int selected() {
        return selected;
    }

    public List<Row> rows() {
        List<Row> rows = new ArrayList<>();
        metrics.forEach((name, value) -> rows.add(new Row(name, value)));
        if (sorted) {
            rows.sort(Comparator.comparingDouble(Row::value).reversed());
        }
        return rows;
    }

    public String footer() {
        return metrics.size() + " metrics, " + skipped + " skipped — q quits, s sorts";
    }

    /** Up to two decimals: 3, 2.5, 0.33. */
    public static String format(double value) {
        return BigDecimal.valueOf(value).setScale(2, RoundingMode.HALF_UP).stripTrailingZeros().toPlainString();
    }
}
