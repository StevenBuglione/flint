module autoconfigure_tests.condition_evaluation_report_data_test;

import flint.beans.factory.support : DefaultListableBeanFactory;
import flint.boot.autoconfigure.condition_runtime : ConditionEvaluationReport;
import flint.java.lang : IllegalArgumentException, UnsupportedOperationException;
import flint.java.util : ArrayList;
import std.exception : assertThrown;

@safe:

@("report exclusions preserve order, duplicates and live read-only views")
unittest
{
    auto report = ConditionEvaluationReport.get(new DefaultListableBeanFactory);
    auto view = report.getExclusions();
    assert(view.isEmpty());

    auto input = new ArrayList!string(["First", "Second", "First"]);
    report.recordExclusions(input);
    input.add("CallerChange");
    report.recordExclusions(new ArrayList!string(["Third"]));

    assert(view.toArray() == ["First", "Second", "First", "Third"]);
    assertThrown!UnsupportedOperationException(view.add("Unrecorded"));
    assertThrown!UnsupportedOperationException(view.clear());
    assert(view.size() == 4);
}

@("report exclusions filter candidate snapshots regardless of recording order")
unittest
{
    auto report = ConditionEvaluationReport.get(new DefaultListableBeanFactory);
    report.recordExclusions(new ArrayList!string(["First"]));
    report.recordEvaluationCandidates(new ArrayList!string(["First", "Second", "Second", "Third"]));

    auto first = report.getUnconditionalClasses();
    assert(first.size() == 2 && first.contains("Second") && first.contains("Third"));
    assertThrown!UnsupportedOperationException(first.add("Unrecorded"));

    report.recordExclusions(new ArrayList!string(["Third"]));
    report.recordEvaluationCandidates(new ArrayList!string(["Fourth"]));

    auto second = report.getUnconditionalClasses();
    assert(second.size() == 2 && second.contains("Second") && second.contains("Fourth"));
    assert(first.contains("Third") && !first.contains("Fourth"));
}

@("report rejects null collections without changing its recorded data")
unittest
{
    auto report = ConditionEvaluationReport.get(new DefaultListableBeanFactory);

    assertThrown!IllegalArgumentException(report.recordExclusions(null));
    assertThrown!IllegalArgumentException(report.recordEvaluationCandidates(null));
    assert(report.getExclusions().isEmpty());
    assert(report.getUnconditionalClasses().isEmpty());
}
