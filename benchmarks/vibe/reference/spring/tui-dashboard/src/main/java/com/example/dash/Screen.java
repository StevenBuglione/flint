package com.example.dash;

import java.io.PrintWriter;
import java.util.List;

/** Paints the whole board with ANSI sequences. */
public final class Screen {

    private Screen() {
    }

    public static void draw(PrintWriter out, Board board, String title, int width, int height) {
        StringBuilder frame = new StringBuilder("\033[H\033[2J");
        frame.append("\033[1;1H\033[1m").append(fit("Dashboard — " + title, width)).append("\033[0m");
        List<Board.Row> rows = board.rows();
        int visible = Math.max(height - 2, 1);
        int first = Math.max(0, board.selected() - visible + 1);
        for (int line = 0; line < visible && first + line < rows.size(); line++) {
            int index = first + line;
            String value = Board.format(rows.get(index).value());
            int nameWidth = Math.max(width - value.length() - 3, 1);
            String text = " " + pad(fit(rows.get(index).name(), nameWidth), nameWidth) + " " + value + " ";
            if (index == board.selected()) {
                text = "\033[7m" + text + "\033[0m";
            }
            frame.append("\033[").append(line + 2).append(";1H").append(text);
        }
        frame.append("\033[").append(height).append(";1H").append(fit(board.footer(), width));
        out.print(frame);
        out.flush();
    }

    private static String fit(String text, int width) {
        return text.codePointCount(0, text.length()) <= width
                ? text : text.substring(0, text.offsetByCodePoints(0, Math.max(width, 0)));
    }

    private static String pad(String text, int width) {
        return text + " ".repeat(Math.max(0, width - text.codePointCount(0, text.length())));
    }
}
