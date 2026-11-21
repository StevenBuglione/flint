module graph_escape;
import core.lifetime : move;
import flint.ui_signals : SignalGraph, SignalSlot, ObserverSlot;
SignalGraph leak() @safe nothrow @nogc {
    SignalSlot[4] signals;
    ObserverSlot[4] observers;
    uint[4] queue;
    auto result = SignalGraph.fromStorage(signals[], observers[], queue[]);
    return move(result.value);
}
