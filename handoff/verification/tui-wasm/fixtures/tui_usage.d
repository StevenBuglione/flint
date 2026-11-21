module tui_usage;
import flint.tui : Event, EventKind, Effects, Frame, run;
struct Counter {
    uint count;
    void update(Event event, ref Effects effects) @safe {
        if (event.kind == EventKind.interrupt) effects.quit();
    }
    void view(ref Frame frame) const @safe {
        auto error = frame.put(0, 0, "Counter");
    }
}
int demo() @safe { Counter model; return run!Counter(model); }
