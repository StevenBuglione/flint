module ui_signals_usage;
import flint.ui_signals : SignalGraph, SignalSlot, ObserverSlot;
import flint.arena : Status;
unittest {
    SignalSlot[8] signals;
    ObserverSlot[8] observers;
    uint[8] queue;
    auto graph = SignalGraph.fromStorage(signals[], observers[], queue[]);
    assert(graph.ok());
    auto id = graph.value.create(7);
    assert(id.ok());
    assert(graph.value.set(id.value, 8).code == Status.ok);
    assert(graph.value.read(id.value).value == 8);
}
