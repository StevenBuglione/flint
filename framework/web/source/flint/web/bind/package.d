/++
`org.springframework.web.bind`: servlet request parameters and binding exceptions.

Ported from spring-projects/spring-framework v7.1.0, spring-web/src/main/java/org/springframework/web/bind/
(ServletRequestBindingException.java, MissingRequestValueException.java,
MissingServletRequestParameterException.java, MissingPathVariableException.java, MissingRequestHeaderException.java,
MissingRequestCookieException.java, ServletRequestUtils.java).
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: translated to D under the rulebook. They skip backtrace capture (ADR-030 section 4).
`MethodArgumentNotValidException` lands with Jakarta Validation and spring-context's `BindingResult`.
+/
module flint.web.bind;

import flint.core : MethodParameter;
import flint.web.bind.support : javaTypeName;
import flint.engine.aot.any : Any;
import flint.engine.aot.text : ParsedLong, decodeUtf8, tryParseLong;
import flint.http : HttpStatus, HttpStatusCode, ProblemDetail;
import flint.jakarta.servlet : ServletException, ServletRequest;
import flint.java.lang : NumberFormatException, javaDecimalDigit;
import flint.util : PatternMatchUtils;
import flint.validation : BindException, BindingResult, FieldError, ObjectError;
import flint.web : ErrorResponse, skipBacktrace;
import std.typecons : Nullable, nullable;

@safe:

/// Accesses first and repeated servlet request parameters with Java's binding errors and defaults.
abstract class ServletRequestUtils
{
    /// Reads an integer, or returns an absent value when the parameter is missing.
    static Nullable!int getIntParameter(ServletRequest request, string name)
    {
        return optionalParameter!int(request.getParameter(name), name);
    }

    /// Returns the supplied default when the parameter is missing or invalid.
    static int getIntParameter(ServletRequest request, string name, int defaultValue)
    {
        return defaultParameter!int(request.getParameter(name), defaultValue);
    }

    /// Returns every value, or an empty array when the parameter is missing or invalid.
    static int[] getIntParameters(ServletRequest request, string name)
    {
        return parameterValues!int(request.getParameterValues(name), name, false);
    }

    /// Reads a required parameter and reports a binding error for missing or invalid input.
    static int getRequiredIntParameter(ServletRequest request, string name)
    {
        return requiredParameter!int(request.getParameter(name), name);
    }

    /// Reads all required values in order.
    static int[] getRequiredIntParameters(ServletRequest request, string name)
    {
        return parameterValues!int(request.getParameterValues(name), name, true);
    }

    /// Reads a long integer, or returns an absent value when the parameter is missing.
    static Nullable!long getLongParameter(ServletRequest request, string name)
    {
        return optionalParameter!long(request.getParameter(name), name);
    }

    /// Returns the supplied default when the parameter is missing or invalid.
    static long getLongParameter(ServletRequest request, string name, long defaultValue)
    {
        return defaultParameter!long(request.getParameter(name), defaultValue);
    }

    /// Returns every value, or an empty array when the parameter is missing or invalid.
    static long[] getLongParameters(ServletRequest request, string name)
    {
        return parameterValues!long(request.getParameterValues(name), name, false);
    }

    /// Reads a required parameter and reports a binding error for missing or invalid input.
    static long getRequiredLongParameter(ServletRequest request, string name)
    {
        return requiredParameter!long(request.getParameter(name), name);
    }

    /// Reads all required values in order.
    static long[] getRequiredLongParameters(ServletRequest request, string name)
    {
        return parameterValues!long(request.getParameterValues(name), name, true);
    }

    /// Reads a boolean, or returns an absent value when the parameter is missing.
    static Nullable!bool getBooleanParameter(ServletRequest request, string name)
    {
        return optionalParameter!bool(request.getParameter(name), name);
    }

    /// Returns the supplied default when the parameter is missing or invalid.
    static bool getBooleanParameter(ServletRequest request, string name, bool defaultValue)
    {
        return defaultParameter!bool(request.getParameter(name), defaultValue);
    }

    /// Returns every value, or an empty array when the parameter is missing or invalid.
    static bool[] getBooleanParameters(ServletRequest request, string name)
    {
        return parameterValues!bool(request.getParameterValues(name), name, false);
    }

    /// Reads a required parameter and reports a binding error for missing or invalid input.
    static bool getRequiredBooleanParameter(ServletRequest request, string name)
    {
        return requiredParameter!bool(request.getParameter(name), name);
    }

    /// Reads all required values in order.
    static bool[] getRequiredBooleanParameters(ServletRequest request, string name)
    {
        return parameterValues!bool(request.getParameterValues(name), name, true);
    }

    /// Reads text while distinguishing a missing value from an empty string.
    static Nullable!string getStringParameter(ServletRequest request, string name)
    {
        const text = request.getParameter(name);
        return text is null ? Nullable!string.init : nullable(text);
    }

    /// Returns the default when the parameter is missing.
    static string getStringParameter(ServletRequest request, string name, string defaultValue)
    {
        const text = request.getParameter(name);
        return text is null ? defaultValue : text;
    }

    /// Returns every text value, or an empty array when any value is missing.
    static string[] getStringParameters(ServletRequest request, string name)
    {
        return parameterValues!string(request.getParameterValues(name), name, false);
    }

    /// Reads required text, accepting an empty string.
    static string getRequiredStringParameter(ServletRequest request, string name)
    {
        return requiredParameter!string(request.getParameter(name), name);
    }

    /// Reads all required text values in order.
    static string[] getRequiredStringParameters(ServletRequest request, string name)
    {
        return parameterValues!string(request.getParameterValues(name), name, true);
    }

    private enum parameterType(T) = is(T == bool) ? "boolean" :  is(T == string) ? "string" : T.stringof;

    private static Nullable!T optionalParameter(T)(string text, string name)
    {
        return text is null ? Nullable!T.init : nullable(requiredParameter!T(text, name));
    }

    private static T requiredParameter(T)(string text, string name)
    {
        T value;
        if (!parseParameter!T(text, value))
            throw parameterFailure(name, parameterType!T, text);
        return value;
    }

    private static T defaultParameter(T)(string text, T defaultValue)
    {
        T value;
        return parseParameter!T(text, value) ? value : defaultValue;
    }

    private static T[] parameterValues(T)(string[] values, string name, bool required)
    {
        if (values is null)
        {
            if (required)
                throw parameterFailure(name, parameterType!T, null);
            return null;
        }

        static if (is(T == string))
            auto result = values;
        else
            auto result = new T[values.length];

        foreach (i, text; values)
        {
            T value;
            if (!parseParameter!T(text, value))
            {
                if (required)
                    throw parameterFailure(name, parameterType!T, text);
                return null;
            }
            static if (!is(T == string))
                result[i] = value;
        }
        return result;
    }

    private static bool parseParameter(T)(string text, out T value)
    {
        if (text is null)
            return false;

        static if (is(T == string))
        {
            value = text;
            return true;
        }
        else static if (is(T == bool))
        {
            value = text == "1" || PatternMatchUtils.simpleMatchIgnoreCase("true", text)
                || PatternMatchUtils.simpleMatchIgnoreCase("on",
                        text) || PatternMatchUtils.simpleMatchIgnoreCase("yes", text);
            return true;
        }
        else
        {
            const result = parseIntegralParameter(text);
            value = cast(T) result.value;
            return result.ok && result.value >= T.min && result.value <= T.max;
        }
    }

    private static ParsedLong parseIntegralParameter(scope const(char)[] text) pure nothrow @nogc
    {
        const ascii = tryParseLong(text);
        if (ascii.ok)
            return ascii;
        foreach (c; text)
            if (c >= 0x80)
                return parseUnicodeIntegralParameter(text);
        return ascii;
    }

    private static ParsedLong parseUnicodeIntegralParameter(scope const(char)[] text) pure nothrow @nogc
    {
        const negative = text[0] == '-';
        size_t index = negative || text[0] == '+' ? 1 : 0;
        const limit = cast(ulong) long.max + negative;
        ulong magnitude;
        while (index < text.length)
        {
            const digit = javaDecimalDigit(decodeUtf8(text, index));
            if (digit > 9 || magnitude > (limit - digit) / 10)
                return ParsedLong.init;
            magnitude = magnitude * 10 + digit;
        }
        return ParsedLong(true, negative ? -cast(long) magnitude : cast(long) magnitude);
    }

    private static ServletRequestBindingException parameterFailure(string name, string type, string text)
    {
        if (text is null)
            return new MissingServletRequestParameterException(name, type);
        return new ServletRequestBindingException(
                "Required " ~ type ~ " parameter '" ~ name ~ "' with value of '" ~ text ~ "' is not a valid number",
                NumberFormatException.forInputString(text));
    }
}

/// `ServletRequestBindingException`: a fatal binding problem (400).
class ServletRequestBindingException : ServletException, ErrorResponse
{
    mixin ErrorResponse.Defaults;

    private ProblemDetail body;
    private string messageDetailCode;
    private Any[] messageDetailArguments;

    /// With a message and optional cause.
    this(string message, Throwable cause = null)
    {
        this(message, cause, null, null);
    }

    /// With a message, cause, detail message code and arguments.
    protected this(string message, Throwable cause, string messageDetailCode, Any[] messageDetailArguments)
    {
        super(message, cause);
        body = ProblemDetail.forStatusAndDetail(getStatusCode(), message);
        this.messageDetailCode = messageDetailCode !is null ? messageDetailCode
            : ErrorResponse.getDefaultDetailMessageCode(typeid(this), null);
        this.messageDetailArguments = messageDetailArguments;
        skipBacktrace(this);
    }

    HttpStatusCode getStatusCode()
    {
        return HttpStatus.BAD_REQUEST;
    }

    ProblemDetail getBody()
    {
        return
        body;
    }

    override string getDetailMessageCode()
    {
        return messageDetailCode;
    }

    override Any[] getDetailMessageArguments()
    {
        return messageDetailArguments;
    }
}

/// `MissingRequestValueException`: a required value is missing.
class MissingRequestValueException : ServletRequestBindingException
{
    private bool missingAfterConversion;

    ///
    this(string message, bool missingAfterConversion = false)
    {
        super(message);
        this.missingAfterConversion = missingAfterConversion;
        // The base built the body before the flag was set; a subclass's status may depend on it.
        getBody().setStatus(getStatusCode().value());
    }

    /// ditto, with a message code.
    protected this(string message, bool missingAfterConversion, string messageDetailCode, Any[] arguments)
    {
        super(message, null, messageDetailCode, arguments);
        this.missingAfterConversion = missingAfterConversion;
        getBody().setStatus(getStatusCode().value());
    }

    /// Whether the value was present but became `null` after conversion.
    bool isMissingAfterConversion() const pure nothrow @nogc
    {
        return missingAfterConversion;
    }
}

/// `MissingServletRequestParameterException`.
class MissingServletRequestParameterException : MissingRequestValueException
{
    private string parameterName;
    private string parameterType;
    private MethodParameter parameter;

    /// For a missing `parameterName` of `parameterType` (a D type name, printed as Java's).
    this(string parameterName, string parameterType, bool missingAfterConversion = false)
    {
        this(parameterName, parameterType, null, missingAfterConversion);
    }

    /// ditto, for a method parameter.
    this(string parameterName, string parameterType, MethodParameter parameter, bool missingAfterConversion)
    {
        super("", missingAfterConversion, null, [Any.of(parameterName)]);
        this.parameterName = parameterName;
        this.parameterType = parameterType;
        this.parameter = parameter;
        msg = computeMessage();
        getBody().setDetail(initBodyDetail(parameterName));
    }

    private string computeMessage()
    {
        const state = isMissingAfterConversion() ? "present but converted to null" : "not present";
        return "Required request parameter '" ~ parameterName ~ "' for method parameter type " ~ simpleJavaName(
                parameterType) ~ " is " ~ state;
    }

    private static string initBodyDetail(string name)
    {
        return "Required parameter '" ~ name ~ "' is not present.";
    }

    /// The parameter name.
    final string getParameterName() const pure nothrow @nogc
    {
        return parameterName;
    }

    /// The parameter type.
    final string getParameterType() const pure nothrow @nogc
    {
        return parameterType;
    }

    /// The method parameter, or `null`.
    MethodParameter getMethodParameter() pure nothrow @nogc
    {
        return parameter;
    }
}

/// `MissingPathVariableException`: a URI template variable is missing (500, a server-side mistake).
class MissingPathVariableException : MissingRequestValueException
{
    private string variableName;
    private MethodParameter parameter;

    ///
    this(string variableName, MethodParameter parameter, bool missingAfterConversion = false)
    {
        super("", missingAfterConversion, null, [Any.of(variableName)]);
        this.variableName = variableName;
        this.parameter = parameter;
        msg = "Required URI template variable '" ~ variableName ~ "' for method parameter type " ~ parameterTypeName(
                parameter) ~ " is " ~ conversionState(missingAfterConversion);
        getBody().setDetail("Required path variable '" ~ variableName ~ "' is not present.");
    }

    override HttpStatusCode getStatusCode()
    {
        return isMissingAfterConversion() ? HttpStatus.BAD_REQUEST : HttpStatus.INTERNAL_SERVER_ERROR;
    }

    /// The variable name.
    final string getVariableName() const pure nothrow @nogc
    {
        return variableName;
    }

    /// The method parameter.
    final MethodParameter getParameter() pure nothrow @nogc
    {
        return parameter;
    }
}

/// `MissingRequestHeaderException`.
class MissingRequestHeaderException : MissingRequestValueException
{
    private string headerName;
    private MethodParameter parameter;

    ///
    this(string headerName, MethodParameter parameter, bool missingAfterConversion = false)
    {
        super("", missingAfterConversion, null, [Any.of(headerName)]);
        this.headerName = headerName;
        this.parameter = parameter;
        msg = "Required request header '" ~ headerName ~ "' for method parameter type " ~ parameterTypeName(
                parameter) ~ " is " ~ conversionState(missingAfterConversion);
        getBody().setDetail("Required header '" ~ headerName ~ "' is not present.");
    }

    /// The header name.
    final string getHeaderName() const pure nothrow @nogc
    {
        return headerName;
    }

    /// The method parameter.
    final MethodParameter getParameter() pure nothrow @nogc
    {
        return parameter;
    }
}

/// `MissingRequestCookieException`.
class MissingRequestCookieException : MissingRequestValueException
{
    private string cookieName;
    private MethodParameter parameter;

    ///
    this(string cookieName, MethodParameter parameter, bool missingAfterConversion = false)
    {
        super("", missingAfterConversion, null, [Any.of(cookieName)]);
        this.cookieName = cookieName;
        this.parameter = parameter;
        msg = "Required cookie '" ~ cookieName ~ "' for method parameter type " ~ parameterTypeName(
                parameter) ~ " is " ~ conversionState(missingAfterConversion);
        getBody().setDetail("Required cookie '" ~ cookieName ~ "' is not present.");
    }

    /// The cookie name.
    final string getCookieName() const pure nothrow @nogc
    {
        return cookieName;
    }
}

/// The simple Java name of a method parameter's nested type, or `""` without a parameter.
private string parameterTypeName(MethodParameter parameter)
{
    return parameter is null ? "" : simpleJavaName(parameter.getNestedParameterType());
}

/// How a missing value is described in Spring's messages.
private string conversionState(bool missingAfterConversion) pure nothrow @nogc
{
    return missingAfterConversion ? "present but converted to null" : "not present";
}

/// Java's `Class.getSimpleName()` for a D type name: `string` → `String`, `long` → `long`, `app.Owner` → `Owner`.
package(flint) string simpleJavaName(string type) pure nothrow
{
    const java = javaTypeName(type);
    foreach_reverse (i, c; java)
        if (c == '.')
            return java[i + 1 .. $];
    return java;
}

/// `MissingMatrixVariableException`: a required matrix variable is missing (400).
class MissingMatrixVariableException : MissingRequestValueException
{
    private string variableName;
    private MethodParameter parameter;

    /// For the missing `variableName` of `parameter`.
    this(string variableName, MethodParameter parameter, bool missingAfterConversion = false)
    {
        super("", missingAfterConversion, null, [Any.of(variableName)]);
        this.variableName = variableName;
        this.parameter = parameter;
        msg = "Required matrix variable '" ~ variableName ~ "' for method parameter type " ~ parameterTypeName(
                parameter) ~ " is " ~ conversionState(missingAfterConversion);
        getBody().setDetail("Required path parameter '" ~ variableName ~ "' is not present.");
    }

    /// The variable name.
    final string getVariableName() const pure nothrow @nogc
    {
        return variableName;
    }

    /// The method parameter.
    final MethodParameter getParameter() pure nothrow @nogc
    {
        return parameter;
    }
}

/// `UnsatisfiedServletRequestParameterException`: the request's parameters do not meet a mapping's `params`
/// conditions (400). `Map<String, String[]>` is `string[][string]` and `List<String[]>` is `string[][]` (R10).
class UnsatisfiedServletRequestParameterException : ServletRequestBindingException
{
    private string[][] paramConditions;
    private string[][string] actualParams;

    /// One set of conditions.
    this(string[] paramConditions, string[][string] actualParams)
    {
        this([paramConditions], actualParams);
    }

    /// Alternative sets of conditions, any of which would have matched.
    this(string[][] paramConditions, string[][string] actualParams)
    {
        super("", null, null, [Any.of(paramsToStringList(paramConditions))]);
        this.paramConditions = paramConditions;
        this.actualParams = actualParams;
        string joined;
        foreach (index, condition; paramsToStringList(paramConditions))
            joined ~= (index != 0 ? " OR " : "") ~ condition;
        msg = "Parameter conditions " ~ joined ~ " not met for actual request parameters: "
            ~ requestParameterMapToString(actualParams);
        getBody().setDetail("Invalid request parameters.");
    }

    /// The first set of conditions.
    final string[] getParamConditions() pure nothrow @nogc
    {
        return paramConditions.length != 0 ? paramConditions[0] : null;
    }

    /// Every set of conditions.
    final string[][] getParamConditionGroups() pure nothrow @nogc
    {
        return paramConditions;
    }

    /// The request's parameters.
    final string[][string] getActualParams() pure nothrow @nogc
    {
        return actualParams;
    }

    private static string[] paramsToStringList(string[][] paramConditions) pure nothrow
    {
        string[] result;
        foreach (conditions; paramConditions)
        {
            string text;
            foreach (index, condition; conditions)
                text ~= (index != 0 ? ", " : "") ~ condition;
            result ~= "\"" ~ text ~ "\"";
        }
        return result;
    }

    /// `ObjectUtils.nullSafeToString` of each `String[]`: `{a, b}`.
    private static string requestParameterMapToString(string[][string] actualParams)
    {
        string result;
        foreach (name, values; actualParams)
        {
            string list;
            foreach (index, value; values)
                list ~= (index != 0 ? ", " : "") ~ value;
            result ~= (result.length != 0 ? ", " : "") ~ name ~ "={" ~ list ~ "}";
        }
        return result;
    }
}

/++
`MethodArgumentNotValidException`: validation of a `@Valid` argument failed (400). It is a `BindException`, so a
handler or advice reads the `BindingResult` from it, as petclinic-rest's advice does.

Without a `MessageSource` the detail arguments are the global and the field errors, each list joined with
`, and `, a field error as `field: message`, as Spring's `BindErrorUtils` formats them.
+/
class MethodArgumentNotValidException : BindException, ErrorResponse
{
    mixin ErrorResponse.Defaults;

    private MethodParameter parameter;
    // Not `body`: dfmt reads `return body;` as D's contract keyword.
    private ProblemDetail problemBody;
    /// The message, built by the first `getMessage()` (Spring builds it on demand: a handler that answers with
    /// the binding result never pays for the text).
    private string message_;

    /// For the invalid argument `parameter` and the errors in `bindingResult`.
    this(MethodParameter parameter, BindingResult bindingResult)
    {
        super(bindingResult);
        this.parameter = parameter;
        skipBacktrace(this);
    }

    /// `Validation failed for argument [i] in m with n errors: [error] ...`, built on first use.
    override string getMessage()
    {
        if (message_ is null)
            message_ = validationMessage();
        return message_;
    }

    HttpStatusCode getStatusCode()
    {
        return HttpStatus.BAD_REQUEST;
    }

    /// The problem body. Spring builds it in the constructor; Flint builds it on the first call and returns the same
    /// instance after, so a handler that answers with its own problem (petclinic's advice) never pays for it.
    ProblemDetail getBody()
    {
        if (problemBody is null)
            problemBody = ProblemDetail.forStatusAndDetail(getStatusCode(), "Invalid request content.");
        return problemBody;
    }

    /// The method parameter that failed validation.
    final MethodParameter getParameter() pure nothrow @nogc
    {
        return parameter;
    }

    override Any[] getDetailMessageArguments()
    {
        return [
            Any.of(join(errorsToStringList(getGlobalErrors().toArray()))),
            Any.of(join(errorsToStringList(getFieldErrors().toArray())))
        ];
    }

    /// The errors as messages: a field error as `field: message`, any other as its message.
    static string[] errorsToStringList(FieldError[] errors)
    {
        ObjectError[] all;
        foreach (error; errors)
            all ~= error;
        return errorsToStringList(all);
    }

    /// ditto
    static string[] errorsToStringList(ObjectError[] errors)
    {
        string[] result;
        foreach (error; errors)
        {
            if (auto field = cast(FieldError) error)
                result ~= field.getField() ~ ": " ~ field.getDefaultMessage();
            else
                result ~= error.getDefaultMessage();
        }
        return result;
    }

    private static string join(string[] errors) pure nothrow
    {
        string result;
        foreach (index, error; errors)
            result ~= (index != 0 ? ", and " : "") ~ error;
        return result;
    }

    private string validationMessage()
    {
        import flint.java.lang : valueOf;

        string text = "Validation failed ";
        if (parameter !is null)
            text ~= "for argument [" ~ decimal(parameter.getParameterIndex()) ~ "] in " ~ parameter.getExecutable();
        const count = getErrorCount();
        if (count > 1)
            text ~= " with " ~ decimal(count) ~ " errors";
        text ~= ": ";
        foreach (error; getAllErrors().toArray())
            text ~= "[" ~ valueOf(cast(Object) error) ~ "] ";
        return text;
    }

    private static string decimal(long value) pure nothrow
    {
        if (value < 0)
            return "-" ~ decimal(-value);
        return value < 10 ? [cast(char)('0' + value)] : decimal(value / 10) ~ cast(char)('0' + value % 10);
    }
}
