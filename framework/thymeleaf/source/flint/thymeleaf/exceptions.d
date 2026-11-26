/*
 * Copyright (c) 2011-2026 Thymeleaf (http://www.thymeleaf.org)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Ported from thymeleaf 3.1.7.RELEASE:
 * lib/thymeleaf/src/main/java/org/thymeleaf/exceptions/TemplateEngineException.java,
 * TemplateProcessingException.java and TemplateInputException.java in the same directory.
 * Modified by the Flint authors.
 */
module flint.thymeleaf.exceptions;

import flint.java.lang : Integer, RuntimeException;
import std.typecons : Nullable;

@safe:

/// Base for errors raised by the template engine (R8).
abstract class TemplateEngineException : RuntimeException
{
    /// Construct an exception whose cause can still be initialized.
    protected this(string message)
    {
        super(message);
    }

    /// Construct an exception with an explicit cause, including a null cause.
    protected this(string message, Throwable cause)
    {
        super(message, cause);
        if (cause is null)
            super.initCause(null);
    }
}

/// An error while processing a template, with optional name and coordinates (R5, R8).
class TemplateProcessingException : TemplateEngineException
{
    private const string detail;
    private Nullable!string templateName;
    private int lineNumber = -1;
    private int columnNumber = -1;

    /// Report a processing error without a template or position.
    this(string message)
    {
        this(message, cast(Throwable) null);
    }

    /// Report a processing error with a cause.
    this(string message, Throwable cause)
    {
        this(message, Nullable!string.init, cause);
    }

    /// Report a processing error in a named template.
    this(string message, Nullable!string templateName, Throwable cause)
    {
        this(message, templateName, -1, -1, cause);
    }

    /// Report a positioned error. Negative coordinates are absent.
    this(string message, Nullable!string templateName, int line, int col)
    {
        super(message);
        detail = message;
        setLocation(templateName, line, col);
    }

    /// Report a positioned error caused by another throwable.
    this(string message, Nullable!string templateName, int line, int col, Throwable cause)
    {
        super(message, cause);
        detail = message;
        setLocation(templateName, line, col);
    }

    /// The template associated with the failure, if present.
    Nullable!string getTemplateName() const pure nothrow @nogc
    {
        return templateName;
    }

    /// Whether the failure names a template.
    bool hasTemplateName() const pure nothrow @nogc
    {
        return !templateName.isNull;
    }

    /// The source line of the error, if known.
    Nullable!int getLine() const pure nothrow @nogc
    {
        return lineNumber < 0 ? Nullable!int.init : Nullable!int(lineNumber);
    }

    /// The source column of the error, if known.
    Nullable!int getCol() const pure nothrow @nogc
    {
        return columnNumber < 0 ? Nullable!int.init : Nullable!int(columnNumber);
    }

    /// Whether both coordinates are known.
    bool hasLineAndCol() const pure nothrow @nogc
    {
        return lineNumber >= 0 && columnNumber >= 0;
    }

    /// Set or clear the name of the template associated with the failure.
    void setTemplateName(Nullable!string templateName)
    {
        setLocation(templateName, lineNumber, columnNumber);
    }

    /// Update both coordinates. Negative coordinates are absent.
    void setLineAndCol(int line, int col)
    {
        setLocation(templateName, line, col);
    }

    // Format only when the location changes so RuntimeException.getMessage stays allocation-free.
    private void setLocation(Nullable!string templateName, int line, int col)
    {
        const message = formatMessage(detail, templateName, line, col);
        this.templateName = templateName;
        lineNumber = line;
        columnNumber = col;
        msg = message;
    }
}

/// An error reading or parsing the template input (R8).
class TemplateInputException : TemplateProcessingException
{
    /// Report a template input error.
    this(string message)
    {
        super(message);
    }

    /// Report a template input error with a cause.
    this(string message, Throwable cause)
    {
        super(message, cause);
    }

    /// Report an input error in a named template.
    this(string message, Nullable!string templateName, Throwable cause)
    {
        super(message, templateName, cause);
    }

    /// Report an input error with a source position.
    this(string message, Nullable!string templateName, int line, int col)
    {
        super(message, templateName, line, col);
    }

    /// Report a positioned input error and its cause.
    this(string message, Nullable!string templateName, int line, int col, Throwable cause)
    {
        super(message, templateName, line, col, cause);
    }
}

private string formatMessage(string detail, Nullable!string templateName, int line, int col) pure nothrow
{
    const message = detail is null ? "null" : detail;
    if (templateName.isNull)
        return message;
    const separator = line >= 0 || col >= 0 ? " - " : null;
    const lineText = line >= 0 ? Integer.toString(line) : null;
    const colText = col >= 0 ? Integer.toString(col) : null;
    return message ~ " (template: \"" ~ templateName.get() ~ "\"" ~ separator ~ (line >= 0
            ? "line " : null) ~ lineText ~ (col >= 0 ? ", col " : null) ~ colText ~ ")";
}
