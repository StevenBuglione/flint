package com.example.dash;

import java.io.IOException;
import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.atomic.AtomicBoolean;
import org.jline.terminal.Attributes;
import org.jline.terminal.Size;
import org.jline.terminal.Terminal;
import org.jline.terminal.TerminalBuilder;
import org.jline.utils.NonBlockingReader;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.ExitCodeGenerator;
import org.springframework.stereotype.Component;
import sun.misc.Signal;
import tools.jackson.databind.json.JsonMapper;

/** `dash --source <file>`: the full-screen loop. */
@Component
public class Dashboard implements CommandLineRunner, ExitCodeGenerator {

    private static final long POLL_MILLIS = 100;
    private static final long FOLLOW_MILLIS = 250;

    private final JsonMapper json;
    private int exitCode;

    public Dashboard(JsonMapper json) {
        this.json = json;
    }

    @Override
    public void run(String... args) throws IOException {
        if (args.length != 2 || !args[0].equals("--source")) {
            System.err.println("usage: dash --source <file>");
            exitCode = 2;
            return;
        }
        Path source = Path.of(args[1]);
        if (!Files.isRegularFile(source)) {
            System.err.println("dash: " + source + ": no such file");
            exitCode = 2;
            return;
        }
        try (MetricsFeed feed = new MetricsFeed(source, json)) {
            show(feed, source.getFileName().toString());
        }
    }

    private void show(MetricsFeed feed, String title) throws IOException {
        AtomicBoolean quit = new AtomicBoolean();
        AtomicBoolean dirty = new AtomicBoolean(true);
        Signal.handle(new Signal("TERM"), signal -> quit.set(true));
        try (Terminal terminal = TerminalBuilder.builder().system(true).build()) {
            Attributes saved = terminal.enterRawMode();
            terminal.handle(Terminal.Signal.WINCH, signal -> dirty.set(true));
            PrintWriter out = terminal.writer();
            out.print("\033[?1049h\033[?25l");
            try {
                loop(terminal, feed, title, quit, dirty);
            } finally {
                out.print("\033[0m\033[?25h\033[?1049l");
                out.flush();
                terminal.setAttributes(saved);
            }
        }
    }

    private static void loop(Terminal terminal, MetricsFeed feed, String title, AtomicBoolean quit,
                             AtomicBoolean dirty) throws IOException {
        Board board = new Board();
        feed.read(board);
        NonBlockingReader keys = terminal.reader();
        long nextFollow = 0;
        while (!quit.get()) {
            long now = System.currentTimeMillis();
            if (now >= nextFollow) {
                if (feed.read(board)) {
                    dirty.set(true);
                }
                nextFollow = now + FOLLOW_MILLIS;
            }
            if (dirty.getAndSet(false)) {
                Size size = terminal.getSize();
                int width = size.getColumns() > 0 ? size.getColumns() : 80;
                int height = size.getRows() > 0 ? size.getRows() : 24;
                Screen.draw(terminal.writer(), board, title, width, height);
            }
            int key = keys.read(POLL_MILLIS);
            switch (key) {
                case NonBlockingReader.READ_EXPIRED -> {
                }
                case 'q', 3, NonBlockingReader.EOF -> quit.set(true);
                case 'j' -> board.move(1);
                case 'k' -> board.move(-1);
                case 's' -> board.toggleSort();
                case 27 -> {
                    int next = keys.peek(20);
                    if (next == '[' || next == 'O') {
                        keys.read();
                        int arrow = keys.read(20);
                        board.move(arrow == 'A' ? -1 : arrow == 'B' ? 1 : 0);
                    } else {
                        quit.set(true);
                    }
                }
                default -> {
                }
            }
            if (key != NonBlockingReader.READ_EXPIRED) {
                dirty.set(true);
            }
        }
    }

    @Override
    public int getExitCode() {
        return exitCode;
    }
}
