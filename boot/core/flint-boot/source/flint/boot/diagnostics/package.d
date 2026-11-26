// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/diagnostics/FailureAnalyzer.java
// with FailureAnalysis.java, AbstractFailureAnalyzer.java, FailureAnalysisReporter.java,
// LoggingFailureAnalysisReporter.java, FailureAnalyzers.java and FailureAnalyzedException.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: analyzers are listed explicitly (Flint's closed world has no
// SpringFactoriesLoader); `AbstractFailureAnalyzer<T>` is a class template over the exception type (rulebook R4).

/// `org.springframework.boot.diagnostics`: turning a startup failure into the "APPLICATION FAILED TO START" report.
module flint.boot.diagnostics;

import flint.java.lang : RuntimeException;

@safe:

/// The result of analysing a failure: what went wrong, what to do, and the exception.
final class FailureAnalysis
{
    private string description;
    private string action;
    private Throwable cause;

    /// An analysis with a `description`, an `action` (may be `null`) and the `cause`.
    this(string description, string action, Throwable cause) pure nothrow @nogc
    {
        this.description = description;
        this.action = action;
        this.cause = cause;
    }

    /// The description of the failure.
    string getDescription() const pure nothrow @nogc
    {
        return description;
    }

    /// The action to take, or `null`.
    string getAction() const pure nothrow @nogc
    {
        return action;
    }

    /// The analysed exception.
    Throwable getCause() pure nothrow @nogc
    {
        return cause;
    }
}

/// Analyses a failure and, when it recognises it, explains it.
interface FailureAnalyzer
{
    /// An analysis of `failure`, or `null` when this analyzer does not handle it.
    FailureAnalysis analyze(Throwable failure);
}

/// A `FailureAnalyzer` for failures whose cause chain contains a `T`.
abstract class AbstractFailureAnalyzer(T : Throwable) : FailureAnalyzer
{
    /// Find the first `T` in `failure`'s cause chain and analyse it.
    FailureAnalysis analyze(Throwable failure)
    {
        auto cause = findCause!T(failure);
        return cause is null ? null : analyze(failure, cause);
    }

    /// Analyse `cause`, the `T` found in `rootFailure`'s chain; `null` when not handled.
    protected abstract FailureAnalysis analyze(Throwable rootFailure, T cause);
}

/// The first `E` in `failure`'s cause chain, or `null`.
E findCause(E : Throwable)(Throwable failure)
{
    for (Throwable current = failure; current !is null; current = causeOf(current))
    {
        if (auto found = cast(E) current)
            return found;
    }
    return null;
}

/// Java's `getCause()`: a `RuntimeException`'s cause, else D's chained throwable.
Throwable causeOf(Throwable failure)
{
    if (auto runtime = cast(RuntimeException) failure)
        return runtime.getCause();
    return failure.next;
}

/// Reports a failure analysis.
interface FailureAnalysisReporter
{
    /// Report `analysis`.
    void report(FailureAnalysis analysis);
}

/// Thrown with a ready-made analysis: Boot reports its description and action as they are.
class FailureAnalyzedException : RuntimeException
{
    private string action;

    /// A failure whose `message` is the description, with an `action`.
    this(string message, string action, Throwable cause = null) pure nothrow
    {
        super(message, cause);
        this.action = action;
    }

    /// The action.
    string getAction() const pure nothrow @nogc
    {
        return action;
    }

    /// Return the description and action carried by this exception.
    FailureAnalysis analysis()
    {
        return new FailureAnalysis(getMessage(), action, this);
    }

    /// The analysis of `failure` when it is, or is caused by, a `FailureAnalyzedException`.
    static FailureAnalysis analyze(Throwable failure)
    {
        auto analyzed = findCause!FailureAnalyzedException(failure);
        return analyzed is null ? null : analyzed.analysis();
    }
}

/// The report Boot logs at ERROR when the application fails to start.
string failureReport(FailureAnalysis analysis)
{
    string report = "\n\n***************************\nAPPLICATION FAILED TO START\n***************************\n\n"
        ~ "Description:\n\n" ~ analysis.getDescription() ~ "\n";
    import flint.engine.aot.text : stripWhite;

    if (analysis.getAction().stripWhite.length)
        report ~= "\nAction:\n\n" ~ analysis.getAction() ~ "\n";
    return report;
}

/// Logs the failure report at ERROR, and the exception at DEBUG.
final class LoggingFailureAnalysisReporter : FailureAnalysisReporter
{
    import flint.boot.internal.log : Log;

    private Log logger;

    /// A reporter writing to `logger`.
    this(Log logger) pure nothrow @nogc
    {
        this.logger = logger;
    }

    /// Log the report at ERROR, and the cause at DEBUG.
    void report(FailureAnalysis analysis)
    {
        if (logger.isDebugEnabled())
            logger.debug_("Application failed to start due to an exception", analysis.getCause());
        logger.error(failureReport(analysis));
    }
}

/// Runs the analyzers in order and reports the first analysis.
final class FailureAnalyzers
{
    private FailureAnalyzer[] analyzers;
    private FailureAnalysisReporter[] reporters;

    /// The given analyzers, followed by `FailureAnalyzedException`'s own, reported through `reporters`.
    this(FailureAnalyzer[] analyzers, FailureAnalysisReporter[] reporters) pure nothrow
    {
        this.analyzers = analyzers;
        this.reporters = reporters;
    }

    /// Analyse `failure` and report it; returns whether an analyzer explained it.
    bool reportException(Throwable failure)
    {
        auto analysis = analyze(failure);
        if (analysis is null || reporters.length == 0)
            return false;
        foreach (reporter; reporters)
            reporter.report(analysis);
        return true;
    }

    /// The first analysis of `failure`, or `null`.
    FailureAnalysis analyze(Throwable failure)
    {
        foreach (analyzer; analyzers)
        {
            try
            {
                if (auto analysis = analyzer.analyze(failure))
                    return analysis;
            }
            catch (Exception)
            {
                // Boot logs a failing analyzer at TRACE and moves on.
            }
        }
        return FailureAnalyzedException.analyze(failure);
    }
}
