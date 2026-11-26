module writer_control_tests;

import flint.java.io : IOException;
import flint.thymeleaf.engine : IThrottledTemplateWriterControl;

@safe:

private final class WriterProbe : IThrottledTemplateWriterControl
{
    bool overflown;
    bool stopped;
    int written;
    int maximum;
    int growths;
    IOException failure;

    bool isOverflown()
    {
        if (failure !is null)
            throw failure;
        return overflown;
    }

    bool isStopped()
    {
        if (failure !is null)
            throw failure;
        return stopped;
    }

    int getWrittenCount()
    {
        return written;
    }

    int getMaxOverflowSize()
    {
        return maximum;
    }

    int getOverflowGrowCount()
    {
        return growths;
    }
}

@("writer control reports the implementor's current state") unittest
{
    auto writer = new WriterProbe();
    IThrottledTemplateWriterControl control = writer;
    assert(!control.isOverflown() && !control.isStopped());
    assert(control.getWrittenCount() == 0);
    writer.overflown = true;
    writer.stopped = true;
    writer.written = 480;
    writer.maximum = 8_192;
    writer.growths = 2;
    assert(control.isOverflown() && control.isStopped());
    assert(control.getWrittenCount() == 480);
    assert(control.getMaxOverflowSize() == 8_192);
    assert(control.getOverflowGrowCount() == 2);
}

@("writer state queries propagate the IOException") unittest
{
    auto writer = new WriterProbe();
    IThrottledTemplateWriterControl control = writer;
    writer.failure = new IOException("could not query writer");
    expectFailure(() => control.isOverflown(), writer.failure);
    expectFailure(() => control.isStopped(), writer.failure);
}

private void expectFailure(scope bool delegate() @safe query, IOException expected)
{
    try
    {
        query();
        assert(false, "expected the IOException");
    }
    catch (IOException error)
    {
        assert(error is expected);
    }
}
