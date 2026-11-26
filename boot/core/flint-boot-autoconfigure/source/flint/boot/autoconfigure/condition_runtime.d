// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/main/java/org/springframework/boot/autoconfigure/condition/ConditionMessage.java
// with ConditionOutcome.java and ConditionEvaluationReport.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: split runtime APIs from the condition UDA leaf, and apply rulebook R4, R5, R7,
// R10, R11, R13 and R20 to the Java API shapes. The sibling module follows R22.
module flint.boot.autoconfigure.condition_runtime;

import flint.beans.factory : BeanFactory;
import flint.beans.factory.config : ConfigurableListableBeanFactory;
import flint.engine.aot.any : Any;
import flint.engine.aot.name : simpleTypeName, typeNameOf;
import flint.java.lang : Boolean, IllegalArgumentException, JavaObject, NullPointerException, String, stringHashCode;
import flint.java.util : ArrayList, Collection, Collections, HashSet, List, RawCollection, Set;
import flint.java.util.formatter : formatJava;
import std.typecons : Nullable;

@safe:

/// A message associated with a Boot auto-configuration condition.
final class ConditionMessage
{
    private string message;

    private this(string message)
    {
        this.message = message;
    }

    /// Whether there is any message text.
    bool isEmpty() const pure nothrow @nogc
    {
        return message.length == 0;
    }

    /// Compare the message text, distinguishing absent and explicitly empty text.
    bool equals(Object other)
    {
        auto that = cast(ConditionMessage) other;
        return that !is null && (that.message is null) == (message is null) && that.message == message;
    }

    /// The Java hash of the message.
    int hashCode() const pure nothrow @nogc
    {
        return stringHashCode(message);
    }

    /// The rendered message.
    override string toString() const pure nothrow @nogc
    {
        return message is null ? "" : message;
    }

    mixin JavaObject;

    /// Return a message with an additional phrase separated by a space.
    ConditionMessage append(Nullable!string suffix)
    {
        if (suffix.isNull || suffix.get.length == 0)
            return this;
        return new ConditionMessage(isEmpty() ? suffix.get : message ~ " " ~ suffix.get);
    }

    /// Start the next clause with an annotation name and optional details.
    Builder andCondition(Annotation, Args...)(Args details)
    {
        return andCondition("@" ~ simpleTypeName(typeNameOf!Annotation), details);
    }

    /// Start the next clause with a condition label and optional details.
    Builder andCondition(Args...)(string condition, Args details)
    {
        return andConditionText(condition, boxArguments(details)[]);
    }

    private Builder andConditionText(string condition, scope Any[] details)
    {
        if (condition is null)
            throw new IllegalArgumentException("'condition' must not be null");
        string text;
        foreach (index, detail; details)
            text ~= (index == 0 ? "" : " ") ~ String.format("%s", detail);
        return new Builder(text.length == 0 ? condition : condition ~ " " ~ text);
    }

    /// Start an empty message.
    static ConditionMessage empty()
    {
        return new ConditionMessage(null);
    }

    /// Create a message, formatting it with Java's String.format when arguments are supplied.
    static ConditionMessage of(Args...)(string message, Args args)
    {
        return formatted(message, boxArguments(args)[]);
    }

    private static ConditionMessage formatted(string message, scope Any[] args)
    {
        if (args.length == 0)
            return new ConditionMessage(message);
        if (message is null)
            throw new NullPointerException();
        return new ConditionMessage(formatJava(message, args));
    }

    /// Combine messages in encounter order with semicolons.
    static ConditionMessage of(Collection!ConditionMessage messages)
    {
        string result;
        if (messages !is null)
        {
            auto iterator = messages.iterator();
            while (iterator.hasNext())
            {
                auto next = iterator.next();
                if (next is null)
                    throw new NullPointerException();
                if (result.length)
                    result ~= "; " ~ next.toString();
                else
                    result = next.toString();
            }
        }
        return new ConditionMessage(result);
    }

    /// Start a message with an annotation name and optional details.
    static Builder forCondition(Annotation, Args...)(Args details)
    {
        return empty().andCondition!Annotation(details);
    }

    /// Start a message with a condition label and optional details.
    static Builder forCondition(Args...)(string condition, Args details)
    {
        return empty().andCondition(condition, details);
    }

    /// Build a clause for a condition.
    final class Builder
    {
        private string condition;

        private this(string condition)
        {
            this.condition = condition;
        }

        /// State that an exact result was found.
        ConditionMessage foundExactly(T)(T result)
        {
            return found("").items(asArgument(result));
        }

        /// Introduce the items that were found with a common article.
        ItemsBuilder found(string article)
        {
            return found(article, article);
        }

        /// Introduce the items that were found with singular and plural articles.
        ItemsBuilder found(string singular, string plural)
        {
            return new ItemsBuilder(this, "found", singular, plural);
        }

        /// Introduce the items that were absent with a common article.
        ItemsBuilder didNotFind(string article)
        {
            return didNotFind(article, article);
        }

        /// Introduce the items that were absent with singular and plural articles.
        ItemsBuilder didNotFind(string singular, string plural)
        {
            return new ItemsBuilder(this, "did not find", singular, plural);
        }

        /// State the result of the condition.
        ConditionMessage resultedIn(T)(T result)
        {
            return becauseText("resulted in " ~ String.format("%s", asArgument(result)));
        }

        /// State that an item is available.
        ConditionMessage available(string item)
        {
            return becauseText((item is null ? "null" : item) ~ " is available");
        }

        /// State that an item is unavailable.
        ConditionMessage notAvailable(string item)
        {
            return becauseText((item is null ? "null" : item) ~ " is not available");
        }

        /// State why the condition matched or failed.
        ConditionMessage because(Nullable!string reason)
        {
            return becauseText(reason.isNull ? null : reason.get);
        }

        private ConditionMessage becauseText(string reason)
        {
            string clause = condition;
            if (reason.length)
                clause = condition.length ? condition ~ " " ~ reason : reason;
            return new ConditionMessage(message.length ? message ~ "; " ~ clause : clause);
        }
    }

    /// Add the items that explain a condition.
    final class ItemsBuilder
    {
        private Builder condition;
        private string reason, singular, plural;

        private this(Builder condition, string reason, string singular, string plural)
        {
            this.condition = condition;
            this.reason = reason;
            this.singular = singular;
            this.plural = plural;
        }

        /// Complete the clause with no items.
        ConditionMessage atAll()
        {
            return render(Style.NORMAL, null);
        }

        /// Complete the clause with the supplied items.
        ConditionMessage items(Args...)(Args values)
                if (!collectionArgument!Args && !is(Args[0] == Style))
        {
            return render(Style.NORMAL, boxArguments(values)[]);
        }

        /// Complete the clause with the supplied items in the selected style.
        ConditionMessage items(Args...)(Style style, Args values) if (!collectionArgument!Args)
        {
            return render(style, boxArguments(values)[]);
        }

        /// Complete the clause with the items in a collection.
        ConditionMessage items(RawCollection values)
        {
            return items(Style.NORMAL, values);
        }

        /// Complete the clause with the items in a collection in the selected style.
        ConditionMessage items(Style style, RawCollection values)
        {
            return render(style, values is null ? null : values.toAnyArray());
        }

        private ConditionMessage render(Style style, scope Any[] values)
        {
            string text;
            size_t count;
            foreach (value; values)
            {
                if (value.isNull())
                    continue;
                text ~= (count == 0 ? "" : ", ") ~ styledText(style, value);
                ++count;
            }
            string article = count <= 1 && singular.length ? singular : plural;
            string clause = article.length ? reason ~ " " ~ article : reason;
            return condition.becauseText(count ? clause ~ " " ~ text : clause);
        }
    }

    /// How each non-null item is displayed.
    enum Style
    {
        /// Use the item's string representation.
        NORMAL,
        /// Enclose the item's string representation in single quotes.
        QUOTE,
    }
}

/// Apply the style to each non-null item in encounter order (R20).
Collection!Any applyTo(ConditionMessage.Style style, RawCollection values)
{
    if (values is null)
        return null;
    auto result = new ArrayList!Any(values.size());
    foreach (value; values.toAnyArray())
    {
        if (!value.isNull())
            result.add(style == ConditionMessage.Style.QUOTE ? Any.of(styledText(style, value)) : value);
    }
    return result;
}

private string styledText(ConditionMessage.Style style, Any value)
{
    string text = String.format("%s", value);
    return style == ConditionMessage.Style.QUOTE ? "'" ~ text ~ "'" : text;
}

private enum collectionArgument(Args...) = Args.length == 1 && is(Args[0] : RawCollection);

private Any[Args.length] boxArguments(Args...)(Args args)
{
    Any[Args.length] result;
    static foreach (index; 0 .. Args.length)
        result[index] = asArgument(args[index]);
    return result;
}

private Any asArgument(T)(T value)
{
    static if (is(T == typeof(null)))
        return Any.init;
    else
        return Any.of(value);
}

/// The result of evaluating a Boot condition, with its diagnostic message.
class ConditionOutcome
{
    private bool matched;
    private ConditionMessage message;

    /// Construct an outcome with literal message text.
    this(bool matched, string message)
    {
        this(matched, ConditionMessage.of(message));
    }

    /// Construct an outcome with a message built for the condition.
    this(bool matched, ConditionMessage message)
    {
        if (message is null)
            throw new IllegalArgumentException("'message' must not be null");
        this.matched = matched;
        this.message = message;
    }

    /// A match without a message.
    static ConditionOutcome match()
    {
        return match(ConditionMessage.empty());
    }

    /// A match with literal message text.
    static ConditionOutcome match(string message)
    {
        return new ConditionOutcome(true, message);
    }

    /// A match with the supplied condition message.
    static ConditionOutcome match(ConditionMessage message)
    {
        return new ConditionOutcome(true, message);
    }

    /// A non-match with literal message text.
    static ConditionOutcome noMatch(string message)
    {
        return new ConditionOutcome(false, message);
    }

    /// A non-match with the supplied condition message.
    static ConditionOutcome noMatch(ConditionMessage message)
    {
        return new ConditionOutcome(false, message);
    }

    /// Whether the condition matched.
    bool isMatch()
    {
        return matched;
    }

    /// The message text, when present.
    Nullable!string getMessage()
    {
        return message.isEmpty() ? Nullable!string.init : Nullable!string(message.toString());
    }

    /// The original condition message.
    ConditionMessage getConditionMessage()
    {
        return message;
    }

    /// Compare the match flag and message with another outcome of the same class.
    bool equals(Object other)
    {
        if (other is this)
            return true;
        auto that = cast(ConditionOutcome) other;
        return that !is null && typeid(this) is typeid(that) && matched == that.matched && message.equals(that.message);
    }

    /// Combine the Java Boolean hash with the message hash.
    int hashCode()
    {
        return 31 * Boolean.hashCode(matched) + message.hashCode();
    }

    /// The rendered condition message.
    override string toString()
    {
        return message.toString();
    }

    mixin JavaObject;
}

/// The condition evaluation report associated with a bean factory.
final class ConditionEvaluationReport
{
    private enum BEAN_NAME = "autoConfigurationReport";
    private ConditionEvaluationReport parent;
    private List!string exclusions;
    private Set!string unconditionalClasses;

    private this()
    {
        exclusions = new ArrayList!string;
        unconditionalClasses = new HashSet!string;
    }

    /// Record configuration classes excluded from evaluation.
    void recordExclusions(Collection!string exclusions)
    {
        if (exclusions is null)
            throw new IllegalArgumentException("'exclusions' must not be null");
        this.exclusions.addAll(exclusions);
    }

    /// Record the configuration classes that are candidates for evaluation.
    void recordEvaluationCandidates(List!string evaluationCandidates)
    {
        if (evaluationCandidates is null)
            throw new IllegalArgumentException("'evaluationCandidates' must not be null");
        unconditionalClasses.addAll(evaluationCandidates);
    }

    /// A read-only view of the exclusions, in recording order.
    List!string getExclusions()
    {
        return Collections.unmodifiableList(exclusions);
    }

    /// A read-only snapshot of the unconditional classes after applying exclusions.
    Set!string getUnconditionalClasses()
    {
        auto filtered = new HashSet!string(unconditionalClasses);
        filtered.removeAll(exclusions);
        return Collections.unmodifiableSet!string(filtered);
    }

    /// The report already registered with the parent bean factory, if present.
    ConditionEvaluationReport getParent()
    {
        return parent;
    }

    /// Find the report when the bean factory can hold a report singleton.
    static ConditionEvaluationReport find(BeanFactory beanFactory)
    {
        auto configurable = cast(ConfigurableListableBeanFactory) beanFactory;
        return configurable is null ? null : get(configurable);
    }

    /// Find or create the report singleton, then discover a newly available parent report.
    static ConditionEvaluationReport get(ConfigurableListableBeanFactory beanFactory)
    {
        if (beanFactory is null)
            throw new NullPointerException();
        synchronized (cast(Object) beanFactory)
        {
            ConditionEvaluationReport report;
            if (beanFactory.containsSingleton(BEAN_NAME))
                report = beanFactory.getBean!ConditionEvaluationReport(BEAN_NAME);
            else
            {
                report = new ConditionEvaluationReport();
                beanFactory.registerSingleton(BEAN_NAME, report);
            }
            if (report.parent is null)
            {
                auto parentFactory = beanFactory.getParentBeanFactory();
                if (parentFactory !is null && parentFactory.containsBean(BEAN_NAME))
                    report.parent = parentFactory.getBean!ConditionEvaluationReport(BEAN_NAME);
            }
            return report;
        }
    }
}
