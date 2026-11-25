/*
 * Ported from Hibernate Validator 9.1.6.Final, https://github.com/hibernate/hibernate-validator,
 * tag 9.1.6.Final: engine/src/main/java/org/hibernate/validator/internal/engine/
 * {ValidatorImpl,ValidatorFactoryImpl,ConstraintViolationImpl}.java, engine/path/{PathImpl,
 * NodeImpl}.java and metadata/descriptor/ConstraintDescriptorImpl.java
 *
 * SPDX-License-Identifier: Apache-2.0
 * Copyright Red Hat Inc. and Hibernate Authors
 *
 * Modified by the Flint authors: the validator walks Flint AOT descriptors (properties
 * with merged constraint annotations) instead of reflecting over classes; the Default
 * group is the only group until Class-valued annotation elements exist. Violations
 * are returned in property declaration order, a deterministic instance of the Set
 * Hibernate returns. Executable validation reads a method's parameters and return-value
 * constraints from its AOT MethodDescriptor; parameter nodes carry the D parameter names.
 */

/// The validation engine: walking descriptors, cascading, and building violations.
module flint.hibernate.validator.internal.engine;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : Descriptor, DescriptorTable, MergedAnnotation,
    MethodDescriptor, ParameterDescriptor, PropertyDescriptor, TypeKind;
import flint.engine.aot.name : typeNameOf;
import flint.hibernate.validator.internal.constraintvalidators : BuiltinConstraint, PatternCache,
    PreparedCheck, attributeText, isBuiltin, isValid, javaConstraintName, javaTypeName, prepare, read;
import flint.hibernate.validator.internal.custom : ConstraintValidatorContextImpl, CustomValidator;
import flint.jakarta.validation : Constraint, ConstraintViolation, ElementKind, MessageInterpolator,
    Path, UnexpectedTypeException, Valid, ValidationException, Validator, ValidatorFactory;
import flint.jakarta.validation.executable : ExecutableValidator;
import flint.jakarta.validation.metadata : ConstraintDescriptor;
import flint.java.util : RawCollection, RawMap;

@safe:

/// A node of a property path.
final class NodeImpl : Path.Node
{
    private string name;
    private bool inIterable;
    private int index = -1;
    private Any key;
    private ElementKind kind;

    ///
    this(string name, ElementKind kind) pure nothrow @nogc
    {
        this.name = name;
        this.kind = kind;
    }

    /// The node name, or null.
    string getName()
    {
        return name;
    }

    /// Whether the node is in an iterable or a map.
    bool isInIterable()
    {
        return inIterable;
    }

    /// The index, or -1.
    int getIndex()
    {
        return index;
    }

    /// The map key, or `Any.init`.
    Any getKey()
    {
        return key;
    }

    /// The element kind.
    ElementKind getKind()
    {
        return kind;
    }

    /// The node as it appears in a path: `name`, `[3]name`, `[key]name`.
    override string toString() const
    {
        return name is null ? position() : position() ~ name;
    }

    // `[3]`, `[key]` or `[]` for a node in an iterable; empty otherwise.
    private string position() const
    {
        import flint.engine.aot.text : decimal;

        if (!inIterable)
            return "";
        return "[" ~ (index >= 0 ? decimal(cast(long) index) : key.isNull() ? "" : key.toString()) ~ "]";
    }
}

/// Default implementation of `jakarta.validation.Path`.
final class PathImpl : Path
{
    private NodeImpl[] nodeList;

    /// The root path of bean validation: one bean node with no name.
    static PathImpl createRootPath() pure nothrow
    {
        auto path = new PathImpl();
        path.nodeList = [new NodeImpl(null, ElementKind.BEAN)];
        return path;
    }

    private PathImpl copy() pure nothrow
    {
        auto path = new PathImpl();
        path.nodeList = nodeList.dup;
        return path;
    }

    /// The root path of executable validation: one method node (`createPathForExecutable`).
    static PathImpl createPathForExecutable(string methodName) pure nothrow
    {
        auto path = new PathImpl();
        path.nodeList = [new NodeImpl(methodName, ElementKind.METHOD)];
        return path;
    }

    /// A path to parameter `parameterName` of the executable at its root.
    PathImpl addParameterNode(string parameterName) pure nothrow
    {
        auto path = copy();
        path.nodeList ~= new NodeImpl(parameterName, ElementKind.PARAMETER);
        return path;
    }

    /// A path to the return value of the executable at its root.
    PathImpl addReturnValueNode() pure nothrow
    {
        auto path = copy();
        path.nodeList ~= new NodeImpl("<return value>", ElementKind.RETURN_VALUE);
        return path;
    }

    /// A path one property deeper.
    PathImpl addPropertyNode(string propertyName) pure nothrow
    {
        auto node = new NodeImpl(propertyName, ElementKind.PROPERTY);
        // The root bean node gives way to the first property.
        size_t keep = nodeList.length;
        if (keep == 1 && nodeList[0].name is null && !nodeList[0].inIterable)
            keep = 0;
        // As Hibernate's NodeImpl reports its parent's iterable position: the property of an element is the node
        // in the iterable, so the position marker becomes this node (`bar`, then `alwaysNull` at index 0).
        if (keep && nodeList[keep - 1].name is null && nodeList[keep - 1].inIterable)
        {
            auto marker = nodeList[keep - 1];
            node.inIterable = true;
            node.index = marker.index;
            node.key = marker.key;
            --keep;
        }
        // The new list at its final size: no copy that grows.
        auto path = new PathImpl();
        path.nodeList = new NodeImpl[keep + 1];
        path.nodeList[0 .. keep] = nodeList[0 .. keep];
        path.nodeList[keep] = node;
        return path;
    }

    /// This path, its next node marked as inside an iterable at `index` (or under `key`).
    PathImpl inIterable(int index, Any key) pure nothrow
    {
        auto path = copy();
        auto marker = new NodeImpl(null, ElementKind.BEAN);
        marker.inIterable = true;
        marker.index = index;
        marker.key = key;
        path.nodeList ~= marker;
        return path;
    }

    /// The nodes from the root, in order.
    Path.Node[] nodes()
    {
        Path.Node[] result;
        foreach (n; nodeList)
            result ~= n;
        return result;
    }

    /// `owner.pets[0].name`: names joined by dots, each iterable position after its container.
    override string toString() const
    {
        string text;
        foreach (n; nodeList)
        {
            if (n.inIterable)
                text ~= n.position();
            if (n.name !is null)
                text ~= (text.length ? "." : "") ~ n.name;
        }
        return text;
    }
}

/// A built-in constraint as metadata.
final class ConstraintDescriptorImpl : ConstraintDescriptor
{
    private BuiltinConstraint constraint;
    private string[] attributeNames; // `message` first, then the elements: fixed by the constraint, built once

    ///
    this(BuiltinConstraint constraint) pure nothrow
    {
        this.constraint = constraint;
        attributeNames = new string[constraint.attributes.length + 1];
        attributeNames[0] = "message";
        foreach (i, a; constraint.attributes)
            attributeNames[i + 1] = a.name;
    }

    /// The annotation, boxed.
    Any getAnnotation()
    {
        return constraint.annotation;
    }

    /// The annotation's Flint type name.
    string getAnnotationType()
    {
        return constraint.annotationType;
    }

    /// The non-interpolated message.
    string getMessageTemplate()
    {
        return constraint.message;
    }

    /// The element named `name`.
    Any getAttribute(string name)
    {
        import flint.hibernate.validator.internal.el : ElValue;

        if (name == "message")
            return Any.of(constraint.message);
        foreach (a; constraint.attributes)
        {
            if (a.name != name)
                continue;
            final switch (a.value.kind)
            {
            case ElValue.Kind.null_:
                return Any.init;
            case ElValue.Kind.boolean:
                return Any.of(a.value.boolean);
            case ElValue.Kind.number:
                return a.value.integral ? Any.of(cast(long) a.value.number) : Any.of(a.value.number);
            case ElValue.Kind.string_:
                return Any.of(a.value.text);
            }
        }
        return Any.init;
    }

    /// The element names, `message` first. The descriptor's own array, built with it: read it, do not change it.
    string[] getAttributeNames()
    {
        return attributeNames;
    }

    /// Built-in constraints report each failure on its own.
    bool isReportAsSingleViolation()
    {
        return false;
    }

    /// The constraint read from its annotation.
    const(BuiltinConstraint) builtin() const pure nothrow @nogc
    {
        return constraint;
    }
}

/// The single implementation of `ConstraintViolation`.
final class ConstraintViolationImpl : ConstraintViolation
{
    private string interpolatedMessage;
    private string messageTemplate;
    private Any rootBean;
    private string rootBeanClass;
    private Any leafBean;
    private Path propertyPath;
    private Any value;
    private ConstraintDescriptor descriptor;

    ///
    this(string messageTemplate, string interpolatedMessage, string rootBeanClass, Any rootBean,
            Any leafBean, Any value, Path propertyPath, ConstraintDescriptor descriptor)
    {
        this.messageTemplate = messageTemplate;
        this.interpolatedMessage = interpolatedMessage;
        this.rootBeanClass = rootBeanClass;
        this.rootBean = rootBean;
        this.leafBean = leafBean;
        this.value = value;
        this.propertyPath = propertyPath;
        this.descriptor = descriptor;
    }

    /// The interpolated message.
    string getMessage()
    {
        return interpolatedMessage;
    }

    /// The message template.
    string getMessageTemplate()
    {
        return messageTemplate;
    }

    /// The root bean.
    Any getRootBean()
    {
        return rootBean;
    }

    /// The root bean's Flint type name.
    string getRootBeanClass()
    {
        return rootBeanClass;
    }

    /// The bean holding the failing value.
    Any getLeafBean()
    {
        return leafBean;
    }

    /// The path from the root bean.
    Path getPropertyPath()
    {
        return propertyPath;
    }

    /// The failing value.
    Any getInvalidValue()
    {
        return value;
    }

    /// The failing constraint.
    ConstraintDescriptor getConstraintDescriptor()
    {
        return descriptor;
    }

    /// As Hibernate prints a violation.
    override string toString() const
    {
        return "ConstraintViolationImpl{interpolatedMessage='" ~ interpolatedMessage
            ~ "', propertyPath=" ~ propertyPath.toString() ~ ", rootBeanClass=class "
            ~ rootBeanClass ~ ", messageTemplate='" ~ messageTemplate ~ "'}";
    }
}

/// The interpolation context Hibernate passes to a `MessageInterpolator`.
final class MessageInterpolatorContext : MessageInterpolator.Context
{
    private ConstraintDescriptor descriptor;
    private Any validatedValue;

    ///
    this(ConstraintDescriptor descriptor, Any validatedValue) pure nothrow @nogc
    {
        this.descriptor = descriptor;
        this.validatedValue = validatedValue;
    }

    /// The constraint.
    ConstraintDescriptor getConstraintDescriptor()
    {
        return descriptor;
    }

    /// The validated value.
    Any getValidatedValue()
    {
        return validatedValue;
    }
}

/// Hibernate's `ValidatorFactory`: descriptors, the interpolator and the shared pattern cache.
final class ValidatorFactoryImpl : ValidatorFactory
{
    private DescriptorTable descriptors;
    private MessageInterpolator interpolator;
    private PatternCache patterns;
    private CustomValidator[][string] custom;
    // The root path every validate() call starts from: a PathImpl is never changed once made (each add returns a
    // copy), so one serves every call and thread.
    private PathImpl rootPath;
    // Copy-on-write, as the pattern cache: a published table is never changed, so lookups take no lock.
    private BeanMetaData[const(Descriptor)] beanMetaData;
    // Prepared constraints of executables' parameters and return values and of properties validated alone, keyed by
    // what names the element (ElementKey), in slots claimed with compare-and-swap: lookups take no lock and an insert
    // copies nothing. Allocated on first use.
    private PreparedSlots* preparedSlots;

    ///
    this(DescriptorTable descriptors, MessageInterpolator interpolator)
    {
        this.descriptors = descriptors;
        this.interpolator = interpolator;
        patterns = new PatternCache();
        rootPath = PathImpl.createRootPath();
    }

    /// Bind a user-defined constraint validator (from a `ConstraintMapping`).
    void bind(CustomValidator validator)
    {
        custom[validator.annotationType] ~= validator;
        synchronized (this)
        {
            // Metadata prepared before this binding classified the annotation without it.
            beanMetaData = null;
            preparedSlots = null;
        }
    }

    /// A validator; validators share the factory's state and are thread-safe.
    Validator getValidator()
    {
        return new ValidatorImpl(this);
    }

    // Hibernate's BeanMetaDataManager: a bean type's constraints, read and prepared on its first validation.
    private BeanMetaData metaDataOf(const(Descriptor) d)
    {
        auto published = beanMetaData;
        if (auto found = d in published)
            return *found;
        auto created = new BeanMetaData(d, this);
        synchronized (this)
        {
            if (auto raced = d in beanMetaData)
                return *raced;
            auto grown = beanMetaData.dup;
            grown[d] = created;
            imported!"core.atomic".atomicFence(); // the metadata and the table are complete before publication
            beanMetaData = grown;
        }
        return created;
    }

    // The constraints of the element `key` names, whose annotations are `annotations`, prepared on first use as a
    // bean's are. An element's annotations are fixed by its declaration, so its name finds them even when the caller's
    // descriptor (and so the array) is rebuilt per call; an address would not. When every probed slot is taken by
    // other elements, the constraints are prepared for this call alone.
    private MetaConstraint[] preparedFor(const(MergedAnnotation)[] annotations, ref const ElementKey key)
    {
        import core.atomic : atomicLoad, cas;

        if (annotations.length == 0)
            return null;
        auto slots = preparedSlotTable();
        const hash = key.hash();
        foreach (probe; 0 .. preparedProbes)
        {
            auto slot = &slots.entries[(hash + probe) % slots.entries.length];
            auto known = atomicLoad(*slot);
            if (known is null)
            {
                auto entry = new PreparedEntry(key, prepareAll(annotations));
                if (cas(slot, cast(PreparedEntry) null, entry))
                    return entry.constraints;
                known = atomicLoad(*slot);
            }
            if (known.key.matches(key))
                return known.constraints;
        }
        return prepareAll(annotations);
    }

    // How many elements have prepared constraints (for tests).
    package(flint.hibernate.validator) size_t preparedElements()
    {
        import core.atomic : atomicLoad;

        auto table = atomicLoad(preparedSlots);
        size_t count;
        if (table !is null)
            foreach (ref entry; table.entries)
                count += atomicLoad(entry) !is null;
        return count;
    }

    // The slot table, allocated by whichever validation needs it first.
    private PreparedSlots* preparedSlotTable()
    {
        import core.atomic : atomicLoad, cas;

        auto table = atomicLoad(preparedSlots);
        if (table !is null)
            return table;
        auto created = new PreparedSlots;
        if (cas(&preparedSlots, cast(PreparedSlots*) null, created))
            return created;
        return atomicLoad(preparedSlots);
    }

    // Each annotation as a constraint to check: built-ins read, compiled and validated once.
    private MetaConstraint[] prepareAll(const(MergedAnnotation)[] annotations)
    {
        MetaConstraint[] constraints;
        constraints.reserve(annotations.length);
        foreach (i, ref a; annotations)
        {
            MetaConstraint m;
            m.type = a.type;
            if (isBuiltin(a.type))
            {
                m.builtin = true;
                m.constraint = read(a.type, a.value);
                m.check = prepare(m.constraint, patterns);
                m.descriptor = new ConstraintDescriptorImpl(m.constraint);
            }
            else if (a.type in custom || isConstraint(a.type))
                m.annotation = annotations[i .. i + 1];
            else
                continue; // not a constraint (@JsonProperty, ...): nothing to check
            constraints ~= m;
        }
        return constraints;
    }

    // Whether the annotation named `type` is meta-annotated @Constraint.
    private bool isConstraint(string type)
    {
        auto d = descriptors is null ? null : descriptors.find(type);
        return d !is null && findAnnotation(d.annotations, typeNameOf!Constraint);
    }

    /// The configured interpolator.
    MessageInterpolator getMessageInterpolator()
    {
        return interpolator;
    }

    /// Nothing to release.
    void close()
    {
    }
}

/// Hibernate's `Validator`: validates beans through their descriptors, cascading through `@Valid`.
final class ValidatorImpl : Validator, ExecutableValidator
{
    alias validate = Validator.validate;
    alias validateProperty = Validator.validateProperty;

    private ValidatorFactoryImpl factory;

    private this(ValidatorFactoryImpl factory) pure nothrow @nogc
    {
        this.factory = factory;
    }

    /// Validate `object` and everything reachable through `@Valid`.
    ConstraintViolation[] validate(Any object)
    {
        if (object.isNull())
            throw new IllegalArgument("HV000116: The object to be validated must not be null.");
        auto run = Run(factory, object, object.typeName());
        run.validateBean(object, factory.rootPath, null, true);
        return run.violations;
    }

    /// Validate the constraints of one property of `object`, without cascading.
    ConstraintViolation[] validateProperty(Any object, string propertyName)
    {
        if (object.isNull())
            throw new IllegalArgument("HV000116: The object to be validated must not be null.");
        auto run = Run(factory, object, object.typeName());
        auto d = run.descriptorOf(object.typeName());
        auto property = d.property(propertyName);
        if (property is null)
            throw new IllegalArgument("HV000039: Invalid property path. There is no property "
                    ~ propertyName ~ " in entity " ~ object.typeName() ~ ".");
        auto value = property.get(object);
        run.checkConstraints(object, value, property.annotations, PathImpl.createRootPath()
                .addPropertyNode(propertyName));
        return run.violations;
    }

    /// Validate `value` against the constraints of property `propertyName` of the type named `beanType`.
    ConstraintViolation[] validateValue(string beanType, string propertyName, Any value)
    {
        auto run = Run(factory, Any.init, beanType);
        auto d = run.descriptorOf(beanType);
        auto property = d.property(propertyName);
        if (property is null)
            throw new IllegalArgument(
                    "HV000039: Invalid property path. There is no property " ~ propertyName
                    ~ " in entity " ~ beanType ~ ".");
        run.checkConstraints(Any.init, value, property.annotations, PathImpl.createRootPath()
                .addPropertyNode(propertyName));
        return run.violations;
    }

    /// Validate each parameter value against its parameter's constraints, cascading through `@Valid` parameters.
    /// Violation paths are `method.parameter`, and their root bean is `object`.
    ConstraintViolation[] validateParameters(Any object, scope const(MethodDescriptor)* method, Any[] parameterValues)
    {
        import flint.engine.aot.text : decimal;

        if (object.isNull())
            throw new IllegalArgument("HV000116: The object to be validated must not be null.");
        if (method is null)
            throw new IllegalArgument("HV000116: The method to be validated must not be null.");
        if (parameterValues.length != method.parameters.length)
        {
            const expected = decimal(cast(long) method.parameters.length);
            const actual = decimal(cast(long) parameterValues.length);
            throw new IllegalArgument("HV000181: Wrong number of parameters. Method or constructor "
                    ~ method.name ~ " expects " ~ expected ~ " parameters, but got " ~ actual ~ ".");
        }
        auto run = Run(factory, object, object.typeName());
        foreach (i, ref parameter; method.parameters)
        {
            auto value = parameterValues[i];
            // The path is built only for a violation or a cascade, as for bean properties.
            auto at = LazyPath.ofExecutable(method.name, parameter.name);
            const key = ElementKey(object.typeName(), method.name, method.parameters, cast(int) i);
            run.check(object, value, factory.preparedFor(parameter.annotations, key), at);
            if (findAnnotation(parameter.annotations, typeNameOf!Valid) && !value.isNull())
                run.cascade(value, at.get(), parameter.type);
        }
        return run.violations;
    }

    /// Validate `returnValue` against the method's return-value constraints, cascading through a `@Valid` method.
    ConstraintViolation[] validateReturnValue(Any object, scope const(MethodDescriptor)* method, Any returnValue)
    {
        if (object.isNull())
            throw new IllegalArgument("HV000116: The object to be validated must not be null.");
        if (method is null)
            throw new IllegalArgument("HV000116: The method to be validated must not be null.");
        auto run = Run(factory, object, object.typeName());
        auto at = LazyPath.ofExecutable(method.name, null, true);
        const key = ElementKey(object.typeName(), method.name, method.parameters, ElementKey.returnValue);
        run.check(object, returnValue, factory.preparedFor(method.annotations, key), at);
        if (findAnnotation(method.annotations, typeNameOf!Valid) && !returnValue.isNull())
            run.cascade(returnValue, at.get(), method.returnType);
        return run.violations;
    }
}

// One constraint of an element, prepared once (Hibernate's MetaConstraint): a built-in read from its annotation,
// with its check and descriptor, or a user-defined annotation looked up among the bound validators when it runs.
private struct MetaConstraint
{
    string type;
    bool builtin;
    BuiltinConstraint constraint;
    PreparedCheck check;
    ConstraintDescriptorImpl descriptor;
    const(MergedAnnotation)[] annotation; // the user-defined annotation, alone
}

// What names an executable's parameter or return value: the bean type, the method, its parameter types (which tell
// overloads apart) and the slot.
private struct ElementKey
{
    enum returnValue = -1;

    string owner;
    string method;
    const(ParameterDescriptor)[] parameters;
    int slot;

    size_t hash() const pure nothrow @nogc
    {
        size_t h = 2_166_136_261;
        void mix(scope const(char)[] text)
        {
            foreach (c; text)
                h = (h ^ c) * 16_777_619;
            h = (h ^ 0xFF) * 16_777_619;
        }

        mix(owner);
        mix(method);
        foreach (ref p; parameters)
            mix(p.type);
        return h ^ cast(size_t)(slot + 1);
    }

    // The same element: equal names, slot and parameter types (the arrays themselves may be distinct copies).
    bool matches(ref const ElementKey other) const pure nothrow @nogc
    {
        if (slot != other.slot || owner != other.owner || method != other.method
                || parameters.length != other.parameters.length)
            return false;
        foreach (i, ref p; parameters)
            if (p.type != other.parameters[i].type)
                return false;
        return true;
    }
}

// One prepared element. Immutable once published.
private final class PreparedEntry
{
    ElementKey key;
    MetaConstraint[] constraints;

    this(ref const ElementKey key, MetaConstraint[] constraints) pure nothrow
    {
        this.key = key;
        this.constraints = constraints;
    }
}

// The prepared elements: an application's validated executables are few; past the probes, a call prepares alone.
private struct PreparedSlots
{
    PreparedEntry[1024] entries;
}

private enum preparedProbes = 8;

// A bean type's properties with their prepared constraints (Hibernate's BeanMetaData).
private final class BeanMetaData
{
    const(Descriptor) descriptor;
    bool bean;
    bool cascades; // a property is @Valid
    PropertyMetaData[] properties;

    this(const(Descriptor) d, ValidatorFactoryImpl factory)
    {
        descriptor = d;
        bean = d.kind == TypeKind.struct_ || d.kind == TypeKind.class_;
        if (!bean)
            return;
        foreach (i, ref property; d.properties)
        {
            if (property.get is null)
                continue;
            properties ~= PropertyMetaData(i, factory.prepareAll(property.annotations),
                    findAnnotation(property.annotations, typeNameOf!Valid));
            cascades = cascades || properties[$ - 1].cascade;
        }
    }
}

private struct PropertyMetaData
{
    size_t index; // into the descriptor's properties
    MetaConstraint[] constraints;
    bool cascade; // @Valid
}

// A property path made only when something needs it: a violation, a cascade or an exception message.
private struct LazyPath
{
    PathImpl parent;
    string property; // null: the parent itself
    string method; // or, when set: the path of an executable's parameter (or of its return value)
    string parameter;
    bool returnValue;
    PathImpl made;

    // The path to `parameter` of `method`, or to its return value.
    static LazyPath ofExecutable(string method, string parameter, bool returnValue = false) pure nothrow @nogc
    {
        LazyPath path;
        path.method = method;
        path.parameter = parameter;
        path.returnValue = returnValue;
        return path;
    }

    PathImpl get()
    {
        if (made !is null)
            return made;
        if (method !is null)
        {
            auto root = PathImpl.createPathForExecutable(method);
            made = returnValue ? root.addReturnValueNode() : root.addParameterNode(parameter);
        }
        else
            made = property is null ? parent : parent.addPropertyNode(property);
        return made;
    }

    string text()
    {
        return get().toString();
    }
}

private class IllegalArgument : ValidationException
{
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, null, file, line);
    }
}

// One validation call: the root, the violations found so far and the beans already visited.
private struct Run
{
    ValidatorFactoryImpl factory;
    Any root;
    string rootType;
    ConstraintViolation[] violations;
    bool[Object] visited;

    this(ValidatorFactoryImpl factory, Any root, string rootType)
    {
        this.factory = factory;
        this.root = root;
        this.rootType = rootType;
    }

    const(Descriptor) descriptorOf(string type)
    {
        auto d = factory.descriptors is null ? null : factory.descriptors.find(type);
        if (d is null)
            throw new ValidationException("HV000043: Unable to find a Flint AOT descriptor for type "
                    ~ type ~ ": register it, or let Flint AOT generate it.");
        return d;
    }

    // `root`: the one bean of a validate() call, which nothing else can reach again unless it cascades.
    void validateBean(ref Any bean, PathImpl path, scope const(char)[] declaredType, bool root = false)
    {
        const type = bean.typeName().length ? bean.typeName() : declaredType.idup;
        auto d = factory.descriptors is null ? null : factory.descriptors.find(type);
        auto meta = d is null ? null : factory.metaDataOf(d);
        // Cycles: a bean is validated once per call, as Hibernate's processed-beans tracking does. The root of a
        // validate() call with no @Valid property reaches no other bean, so it needs no entry in the set.
        if (auto o = bean.asObject())
            if (!root || meta is null || meta.cascades)
            {
                if (o in visited)
                    return;
                visited[o] = true;
            }
        if (meta is null || !meta.bean)
            return;
        foreach (ref p; meta.properties)
        {
            const property = &d.properties[p.index];
            auto value = property.get(bean);
            auto at = LazyPath(path, property.name);
            check(bean, value, p.constraints, at);
            if (p.cascade && !value.isNull())
                cascade(value, at.get(), property.type);
        }
    }

    void cascade(ref Any value, PathImpl at, string declaredType)
    {
        if (cascadeDescribed(value, at))
            return;
        if (auto collection = cast(RawCollection) value.asObject())
        {
            foreach (i, element; collection.toAnyArray())
                if (!element.isNull())
                    validateBean(element, at.inIterable(cast(int) i, Any.init), null);
            return;
        }
        if (auto map = cast(RawMap) value.asObject())
        {
            foreach (key; map.keysAsAny())
            {
                auto element = map.getAny(key);
                if (!element.isNull())
                    validateBean(element, at.inIterable(-1, key), null);
            }
            return;
        }
        validateBean(value, at, declaredType);
    }

    // Arrays and associative arrays cascade into their elements, Optional into its value, through the descriptor
    // thunks; Hibernate's value extractors for arrays, Map values and Optional.
    bool cascadeDescribed(ref Any value, PathImpl at)
    {
        auto d = described(value);
        if (d is null)
            return false;
        if (d.unwrap !is null)
        {
            auto inner = d.unwrap(value);
            if (!inner.isNull())
                validateBean(inner, at, d.elementType);
        }
        else if (d.length !is null && d.element !is null && d.kind == TypeKind.array)
        {
            foreach (i; 0 .. d.length(value))
            {
                auto element = d.element(value, i);
                if (!element.isNull())
                    validateBean(element, at.inIterable(cast(int) i, Any.init), d.elementType);
            }
        }
        else if (d.toKeys !is null && d.toValues !is null)
        {
            auto keys = d.toKeys(value);
            auto values = d.toValues(value);
            foreach (i, ref element; values)
                if (!element.isNull())
                    validateBean(element, at.inIterable(-1, keys[i]), d.elementType);
        }
        else
            return false;
        return true;
    }

    const(Descriptor) described(ref Any value)
    {
        return factory.descriptors is null || value.typeName().length == 0
            ? null : factory.descriptors.find(value.typeName());
    }

    void checkConstraints(Any leaf, ref Any value, const(MergedAnnotation)[] annotations, PathImpl at)
    {
        auto path = LazyPath(at);
        check(leaf, value, factory.prepareAll(annotations), path);
    }

    void check(Any leaf, ref Any value, scope MetaConstraint[] constraints, ref LazyPath at)
    {
        if (constraints.length == 0)
            return;
        // A Nullable!T (rulebook R5: Java's Integer, a String that may be null) is validated as its value or null,
        // as Hibernate validates the boxed value itself; Optional keeps container semantics.
        auto d = described(value);
        if (d !is null && d.unwrap !is null && d.name.length > 22 && d.name[0 .. 22] == "std.typecons.Nullable!")
        {
            auto inner = d.unwrap(value);
            return check(leaf, inner, constraints, at);
        }
        foreach (ref m; constraints)
        {
            if (m.builtin)
            {
                if (!isValid(m.constraint, m.check, value, () => at.text(), d))
                    report(leaf, value, at.get(), m.descriptor, [m.constraint.message]);
            }
            else if (auto bound = m.type in factory.custom)
                checkCustom(leaf, value, m.annotation[0], *bound, at.get());
            else
                requireBinding(m.type, value, at);
        }
    }

    // SimpleConstraintTree: run the bound validator that accepts the value's type, then report the default and the
    // built templates.
    void checkCustom(Any leaf, ref Any value, ref const MergedAnnotation a, CustomValidator[] bound, PathImpl at)
    {
        CustomValidator chosen;
        foreach (candidate; bound)
        {
            if (value.isNull() || candidate.accepts(value))
            {
                chosen = candidate;
                break;
            }
        }
        if (chosen.run is null)
            throw unexpectedType(a.type, value, at);
        auto constraint = chosen.read(a.value);
        auto context = new ConstraintValidatorContextImpl(constraint.message);
        if (!chosen.run(constraint.annotation, value, context))
            report(leaf, value, at, new ConstraintDescriptorImpl(constraint), context.violationTemplates());
    }

    // An annotation whose descriptor carries @Constraint but has no bound validator: Hibernate would instantiate
    // `validatedBy`, which Flint never does from a class name.
    void requireBinding(string annotationType, ref Any value, ref LazyPath at)
    {
        if (factory.isConstraint(annotationType))
            throw unexpectedType(annotationType, value, at.get());
    }

    UnexpectedTypeException unexpectedType(string annotationType, ref Any value, PathImpl at)
    {
        const constraint = javaConstraintName(annotationType), type = javaTypeName(value.typeName());
        return new UnexpectedTypeException("HV000030: No validator could be found for constraint '"
                ~ constraint ~ "' validating type '" ~ type ~ "'. Check configuration for '" ~ at.toString() ~ "'");
    }

    void report(Any leaf, ref Any value, PathImpl at, ConstraintDescriptorImpl descriptor,
            scope const(string)[] templates)
    {
        foreach (messageTemplate; templates)
        {
            const message = factory.interpolator.interpolate(messageTemplate,
                    new MessageInterpolatorContext(descriptor, value));
            violations ~= new ConstraintViolationImpl(messageTemplate, message, rootType, root,
                    leaf, value, at, descriptor);
        }
    }
}

private bool findAnnotation(scope const(MergedAnnotation)[] annotations, string type) pure nothrow @nogc
{
    foreach (ref a; annotations)
        if (a.type == type)
            return true;
    return false;
}

// A proxy's descriptor may be rebuilt for every call (new arrays, the same method): the prepared constraints are found
// by the element's name, so repeated calls add no entries and allocate the same each time; an overload with other
// parameter types is its own entry with its own constraints.
unittest
{
    import core.memory : GC;
    import flint.engine.aot.descriptor : ParameterDescriptor;
    import flint.hibernate.validator.messageinterpolation : ResourceBundleMessageInterpolator;
    import flint.jakarta.validation.constraints : Min;

    static final class Target
    {
    }

    auto factory = new ValidatorFactoryImpl(DescriptorTable.withBuiltins(), new ResourceBundleMessageInterpolator());
    auto validator = cast(ValidatorImpl) factory.getValidator();
    auto target = Any.of(new Target());
    MethodDescriptor rebuilt(string parameterType, long minimum)
    {
        MethodDescriptor method;
        method.name = "page";
        method.returnType = "void";
        method.parameters = [
            ParameterDescriptor("number", parameterType, [
                MergedAnnotation(typeNameOf!Min, Any.of(Min(minimum)), 0)
            ])
        ];
        return method;
    }

    void call(string parameterType, long minimum, long argument, size_t violations)
    {
        auto method = rebuilt(parameterType, minimum);
        auto value = parameterType == "int" ? Any.of(cast(int) argument) : Any.of(argument);
        assert(validator.validateParameters(target, &method, [value]).length == violations);
        assert(validator.validateReturnValue(target, &method, Any.init).length == 0);
    }

    foreach (round; 0 .. 20)
        call("int", 0, 3, 0);
    assert(factory.preparedElements() == 1);
    size_t perCall(int calls)
    {
        const before = GC.stats().allocatedInCurrentThread;
        foreach (round; 0 .. calls)
            call("int", 0, 3, 0);
        return cast(size_t)(GC.stats().allocatedInCurrentThread - before) / calls;
    }

    const early = perCall(10);
    foreach (round; 0 .. 200)
        call("int", 0, 3, 0);
    assert(perCall(10) == early && factory.preparedElements() == 1);
    // The overload page(long) with @Min(5): its own element, its own constraint.
    call("long", 5, 3, 1);
    call("int", 0, 3, 0);
    assert(factory.preparedElements() == 2);
}
