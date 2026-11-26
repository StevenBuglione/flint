// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionEvaluationReportTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: port the report's bean-factory lookup and parent tests.
module autoconfigure_tests.condition_evaluation_report_factory_test;

import flint.beans.factory.support : DefaultListableBeanFactory;
import flint.boot.autoconfigure.condition_runtime : ConditionEvaluationReport;

@safe:

@("get")
unittest
{
    auto factory = new DefaultListableBeanFactory;
    const report = ConditionEvaluationReport.get(factory);
    assert(report !is null);
    assert(report is ConditionEvaluationReport.get(factory));
}

@("parent")
unittest
{
    auto factory = new DefaultListableBeanFactory;
    auto report = ConditionEvaluationReport.get(factory);
    auto parent = new DefaultListableBeanFactory;
    factory.setParentBeanFactory(parent);

    const parentReport = ConditionEvaluationReport.get(parent);
    assert(ConditionEvaluationReport.get(factory) is report);
    assert(report.getParent() !is null);
    assert(ConditionEvaluationReport.get(parent) is parentReport);
    assert(ConditionEvaluationReport.get(factory) is report);
    assert(report.getParent() is parentReport);
}

@("parentBottomUp")
unittest
{
    auto parent = new DefaultListableBeanFactory;
    auto factory = new DefaultListableBeanFactory;
    factory.setParentBeanFactory(parent);

    auto parentReport = ConditionEvaluationReport.get(parent);
    auto report = ConditionEvaluationReport.get(factory);
    assert(report !is null);
    assert(report !is report.getParent());
    assert(report.getParent() is parentReport);
    assert(parentReport.getParent() is null);
}

@("report find returns the same singleton for a configurable listable bean factory")
unittest
{
    auto factory = new DefaultListableBeanFactory;
    const report = ConditionEvaluationReport.find(factory);
    assert(report !is null);
    assert(report is ConditionEvaluationReport.get(factory));
    assert(ConditionEvaluationReport.find(null) is null);
}
