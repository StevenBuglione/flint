// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/diagnostics/
// FailureAnalyzersTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: analyzers are listed as instances (Flint has no SpringFactoriesLoader), Mockito's
// analyzer is a recording one, and the broken analysis throws an Exception (D has no NoClassDefFoundError).
// Not ported: analyzerIsConstructedWithBeanFactory and analyzerIsConstructedWithEnvironment (SpringFactoriesLoader's
// constructor injection), analyzerThatFailsDuringInitializationDoesNotPreventOtherAnalyzersFromBeingCalled (a Java
// static initializer failing while the class loads).
module boot_tests.failure_analyzers_test;

import flint.boot.diagnostics : FailureAnalysis, FailureAnalysisReporter, FailureAnalyzedException,
    FailureAnalyzer, FailureAnalyzers;
import flint.java.lang : IllegalStateException, RuntimeException;

@safe:

/// The shared mock `failureAnalyzer`: records the failures it is asked to analyse.
private final class RecordingAnalyzer : FailureAnalyzer
{
    Throwable[] analyzed;

    FailureAnalysis analyze(Throwable failure)
    {
        analyzed ~= failure;
        return null;
    }
}

/// `BasicFailureAnalyzer`: delegates to the shared mock.
private final class BasicFailureAnalyzer : FailureAnalyzer
{
    RecordingAnalyzer mock;

    this(RecordingAnalyzer mock)
    {
        this.mock = mock;
    }

    FailureAnalysis analyze(Throwable failure)
    {
        return mock.analyze(failure);
    }
}

/// `BrokenAnalysisFailureAnalyzer`.
private final class BrokenAnalysisFailureAnalyzer : FailureAnalyzer
{
    FailureAnalysis analyze(Throwable)
    {
        throw new Exception("broken analysis");
    }
}

/// `IllegalStateFailureAnalyzer`.
private final class IllegalStateFailureAnalyzer : FailureAnalyzer
{
    FailureAnalysis analyze(Throwable failure)
    {
        if (cast(IllegalStateException) failure !is null)
            return new FailureAnalysis("analyzed state", null, failure);
        return null;
    }
}

/// The reports, as `this.reports::add`.
private final class Reports : FailureAnalysisReporter
{
    FailureAnalysis[] reports;

    void report(FailureAnalysis analysis)
    {
        reports ~= analysis;
    }
}

private Reports analyzeAndReport(Throwable failure, FailureAnalyzer[] analyzers...)
{
    auto reports = new Reports;
    new FailureAnalyzers(analyzers.dup, [cast(FailureAnalysisReporter) reports]).reportException(failure);
    return reports;
}

@("analyzersAreLoadedAndCalled") unittest
{
    auto mock = new RecordingAnalyzer;
    auto failure = new RuntimeException();
    cast(void) analyzeAndReport(failure, new BasicFailureAnalyzer(mock), new BasicFailureAnalyzer(mock));
    assert(mock.analyzed.length == 2 && mock.analyzed[0] is failure && mock.analyzed[1] is failure);
}

@("analyzerThatFailsDuringAnalysisDoesNotPreventOtherAnalyzersFromBeingCalled") unittest
{
    auto mock = new RecordingAnalyzer;
    auto failure = new RuntimeException();
    cast(void) analyzeAndReport(failure, new BrokenAnalysisFailureAnalyzer, new BasicFailureAnalyzer(mock));
    assert(mock.analyzed.length == 1 && mock.analyzed[0] is failure);
}

@("failureAnalyzedExceptionAreReported") unittest
{
    auto failure = new FailureAnalyzedException("Bad", "Fix it!");
    auto reports = analyzeAndReport(failure).reports;
    assert(reports.length == 1);
    assert(reports[0].getDescription() == "Bad");
    assert(reports[0].getAction() == "Fix it!");
    assert(reports[0].getCause() is failure);
}

@("wrappedFailureAnalyzedExceptionAreReported") unittest
{
    auto failure = new FailureAnalyzedException("Bad", "Fix it!");
    auto reports = analyzeAndReport(new IllegalStateException("the state of this!", failure)).reports;
    assert(reports.length == 1);
    assert(reports[0].getDescription() == "Bad");
    assert(reports[0].getAction() == "Fix it!");
    assert(reports[0].getCause() is failure);
}

@("whenOtherAnalyzerIsAvailableFailureAnalyzedExceptionAreNotReported") unittest
{
    auto failure = new FailureAnalyzedException("Bad", "Fix it!");
    auto reports = analyzeAndReport(new IllegalStateException("the state of this!", failure),
            new IllegalStateFailureAnalyzer).reports;
    assert(reports.length == 1);
    assert(reports[0].getDescription() == "analyzed state");
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
