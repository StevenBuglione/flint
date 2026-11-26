/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/test/web/servlet/result/ModelResultMatchersTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: use MapBindingResult to supply a field error without runtime bean reflection.
+/
module model_result_matchers_tests;

import flint.engine.aot.any : Any;
import flint.java.lang : AssertionError;
import flint.java.util : LinkedHashMap;
import flint.test.web.servlet : DefaultMvcResult, MvcResult, ResultMatcher;
import flint.test.web.servlet.result : MockMvcResultMatchers;
import flint.validation : BindingResult, MapBindingResult;
import flint.web.servlet : ModelAndView;

@safe:

private alias model = MockMvcResultMatchers.model;

private final class ModelResult : DefaultMvcResult
{
    private ModelAndView modelAndView;

    this(ModelAndView modelAndView)
    {
        super(null, null);
        this.modelAndView = modelAndView;
    }

    override ModelAndView getModelAndView()
    {
        return modelAndView;
    }
}

private MvcResult result(bool withErrors = false)
{
    auto modelAndView = new ModelAndView("view");
    modelAndView.addObject("good", Any.of("good"));
    if (withErrors)
    {
        auto fields = new LinkedHashMap!(string, Any);
        fields.put("time", Any.of(0L));
        auto errors = new MapBindingResult(fields, "date");
        errors.rejectValue("time", "error");
        modelAndView.addObject("date", Any.of(fields));
        modelAndView.addObject(BindingResult.MODEL_KEY_PREFIX ~ "date", Any.of(errors));
    }
    else
    {
        auto fields = new LinkedHashMap!(string, Any);
        modelAndView.addObject(BindingResult.MODEL_KEY_PREFIX ~ "good", Any.of(new MapBindingResult(fields, "good")));
    }
    return new ModelResult(modelAndView);
}

private void fails(ResultMatcher matcher, MvcResult result, string message = null)
{
    try
    {
        matcher.match(result);
        assert(false);
    }
    catch (AssertionError failure)
    {
        if (message !is null)
            assert(failure.getMessage() == message, failure.getMessage());
    }
}

@("attributeExists")
unittest
{
    model().attributeExists("good").match(result());
}

@("attributeExists_doesNotExist")
unittest
{
    fails(model().attributeExists("bad"), result(), "Model attribute 'bad' does not exist");
}

@("attributeDoesNotExist")
unittest
{
    model().attributeDoesNotExist("bad").match(result());
}

@("attributeDoesNotExist_doesExist")
unittest
{
    fails(model().attributeDoesNotExist("good"), result(true), "Model attribute 'good' exists");
}

@("hasNoErrors")
unittest
{
    model().hasNoErrors().match(result());
}

@("hasNoErrors_withErrors")
unittest
{
    fails(model().hasNoErrors(), result(true));
}

@("attributeHasErrors")
unittest
{
    model().attributeHasErrors("date").match(result(true));
}

@("attributeErrorCount")
unittest
{
    model().attributeErrorCount("date", 1).match(result(true));
}

@("attributeErrorCount_withWrongErrorCount")
unittest
{
    fails(model().attributeErrorCount("date", 2), result(true),
            "Binding/validation error count for attribute 'date', expected:<2> but was:<1>");
}

@("attributeHasErrors_withoutErrors")
unittest
{
    fails(model().attributeHasErrors("good"), result(true));
}

@("attributeHasNoErrors")
unittest
{
    model().attributeHasNoErrors("good").match(result());
}

@("attributeHasNoErrors_withoutAttribute")
unittest
{
    fails(model().attributeHasNoErrors("missing"), result(true), "No BindingResult for attribute: missing");
}

@("attributeHasNoErrors_withErrors")
unittest
{
    fails(model().attributeHasNoErrors("date"), result(true));
}

@("attributeHasFieldErrors")
unittest
{
    model().attributeHasFieldErrors("date", "time").match(result(true));
}

@("attributeHasFieldErrors_withoutAttribute")
unittest
{
    fails(model().attributeHasFieldErrors("missing", "bad"), result(true), "No BindingResult for attribute: missing");
}

@("attributeHasFieldErrors_withoutErrorsForAttribute")
unittest
{
    fails(model().attributeHasFieldErrors("date", "time"), result());
}

@("attributeHasFieldErrors_withoutErrorsForField")
unittest
{
    fails(model().attributeHasFieldErrors("date", "good", "time"), result(true),
            "No errors for field 'good' of attribute 'date'");
}

@("attributeHasFieldErrorCode")
unittest
{
    model().attributeHasFieldErrorCode("date", "time", "error").match(result(true));
}

@("attributeHasFieldErrorCode_withoutErrorOnField")
unittest
{
    fails(model().attributeHasFieldErrorCode("date", "time", "incorrectError"), result(true),
            "Field error code expected:<incorrectError> but was:<error>");
}

unittest
{
    auto actual = result(true);
    auto matchers = model();
    matchers.errorCount(1).match(actual);
    matchers.hasErrors().match(actual);
    matchers.size(2).match(actual);
    fails(matchers.errorCount(0), actual, "Binding/validation error count expected:<0> but was:<1>");
    fails(matchers.hasErrors(), result(), "Expected binding/validation errors");
    fails(matchers.size(3), actual, "Model size expected:<3> but was:<2>");
    fails(matchers.attributeExists("good"), new ModelResult(null), "No ModelAndView found");
}

unittest
{
    const viewName = "mySpecialView";
    auto mav = new ModelAndView(viewName);
    auto actual = new ModelResult(mav);
    MockMvcResultMatchers.view().name(viewName).match(actual);
    fails(MockMvcResultMatchers.view().name("expected"), actual,
            "View name expected:<expected> but was:<mySpecialView>");
    fails(MockMvcResultMatchers.view().name(viewName), new ModelResult(null), "No ModelAndView found");
}
