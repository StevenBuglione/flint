/// Flint AOT's analysis: from the extracted model to a generation plan (docs/spring/aot-contract.md sections 5-8).
///
/// The plan holds everything the emitter prints, already decided: bean definitions in definition order with their
/// injection points and lifecycle, startup conditions compiled to D, proxy and configuration subclasses,
/// request-mapping tables, descriptors and derived queries, plus the diagnostics.
module flint_tool.engine.aot.plan;

import flint_tool.engine.aot.merge : MergedSet;
import flint_tool.engine.aot.model : Annotation, AnnotationType, Method, Model, Parameter, TypeDecl, TypeRef, clone;
import flint_tool.engine.aot.query : DerivedQuery;
import std.algorithm.searching : canFind;

@safe:

/// A generator diagnostic.
struct Diagnostic
{
    /// `FLINT-E11nn`.
    string code;
    /// Message.
    string message;
    /// Source file and line of the declaration.
    string file;
    /// ditto
    long line;
    /// Reported as a warning: the build continues.
    bool warning;
}

/// How an injection point is satisfied at startup.
enum PointKind
{
    bean,
    beans,
    optional,
    value,
    /// `@Value("#{...}")`: `expression` holds the compiled D expression, already of the parameter's type.
    spel
}

/// One constructor, bean-method or field injection point.
struct Point
{
    /// How it resolves.
    PointKind kind;
    /// The parameter's or field's type, as D source.
    string type;
    /// For `beans` and `optional`: the bean type looked up.
    string lookup;
    /// `@Qualifier`.
    string qualifier;
    /// `@Value` expression.
    string expression;
    /// Modules declaring the types it names.
    string[] modules;
    /// For `spel` before compilation: the `@Value` text, and where it was declared.
    string template_;
    /// ditto
    string file;
    /// ditto
    long line;
}

/// A field set during `initialize`.
struct FieldPoint
{
    /// The class declaring the field.
    string owner;
    /// Its index in that class's `tupleof`.
    long index;
    /// What to inject.
    Point point;
}

/// How a bean is created.
enum FactoryKind
{
    /// `new Class(arguments)`.
    constructor,
    /// `new Class__FlintConfiguration(factory, arguments)`: a proxied configuration class.
    configuration,
    /// An instance `@Bean` method on the configuration bean.
    method,
    /// A static `@Bean` method.
    staticMethod
}

/// One bean definition.
struct BeanPlan
{
    /// Bean name.
    string name;
    /// Declared type.
    string type;
    /// Every type it can be injected as.
    string[] types;
    /// Contract 3: for a `FactoryBean!T`, the types of the object it makes: `T` first, then T's supertypes.
    string[] objectTypes;
    /// Position in definition order.
    uint rank;
    /// How it is created.
    FactoryKind factory;
    /// The class constructed, or the configuration class declaring the bean method.
    string className;
    /// For bean methods: the configuration bean and the method.
    string configBean;
    /// ditto
    string method;
    /// For bean methods: whether the configuration class is proxied.
    bool configProxied;
    /// Constructor or bean-method arguments.
    Point[] arguments;
    /// Fields injected during `initialize`.
    FieldPoint[] fields;
    /// Lifecycle.
    string[] postConstruct;
    /// ditto
    bool initializingBean;
    /// ditto
    string initMethod;
    /// ditto
    string[] preDestroy;
    /// ditto
    bool disposableBean;
    /// ditto
    string destroyMethod;
    /// `@ConfigurationProperties` prefix bound during `initialize`, or empty.
    string propertiesPrefix;
    /// Startup condition as a D expression over `c`, or empty.
    string condition;
    /// Definition attributes.
    string[] dependsOn;
    /// ditto
    string[] qualifiers;
    /// ditto
    string scope_ = "singleton";
    /// ditto
    bool primary;
    /// ditto
    bool fallback;
    /// ditto
    bool lazyInit;
    /// ditto
    long order = int.max;
    /// ditto
    bool autoConfiguration;
    /// "src/shop/owners.d:12".
    string source;
    /// The same location, split, for diagnostics.
    string file;
    /// ditto
    long line;
    /// Whether a proxy subclass wraps it.
    bool proxied;
    /// Whether the generated module defines a descriptor for its class.
    bool described;
    /// Types it requires through constructor arguments (for the build-time cycle check).
    string[] requires;
}

/// A proxied `@Configuration` class.
struct ConfigPlan
{
    /// The configuration class.
    string className;
    /// Its simple name.
    string simple;
    /// The constructor's parameters, forwarded to `super`.
    Parameter[] parameters;
    /// The instance `@Bean` methods.
    Method[] methods;
    /// Their bean names, parallel to `methods`.
    string[] beans;
}

/// One method of a proxy subclass.
struct ProxyMethod
{
    /// The method.
    Method method;
    /// Whether it goes through the advice chain.
    bool advised;
    /// Whether it is `@Async`.
    bool async_;
    /// Its index in the bean class's descriptor methods.
    size_t index;
}

/// A proxy subclass.
struct ProxyPlan
{
    /// The proxied class.
    string className;
    /// Its simple name.
    string simple;
    /// Every overridable public method.
    ProxyMethod[] methods;
    /// The class's constructors, for the never-called constructor D requires.
    Method[] constructors;
}

/// A method in a descriptor.
struct MethodPlan
{
    /// The method.
    Method method;
    /// Its merged annotations, with class-level advice.
    MergedSet annotations;
    /// Each parameter's merged annotations.
    MergedSet[] parameters;
    /// SpEL-valued attributes of its merged annotations, compiled (aot-contract.md section 9.1).
    ExpressionPlan[] expressions;
}

/// One compiled method-level expression.
struct ExpressionPlan
{
    /// Annotation and attribute that hold it.
    string annotation;
    /// ditto
    string attribute;
    /// SpEL source.
    string source;
    /// D expression over `EvaluationContext context`, of type `Any`.
    string code;
    /// Modules declaring the types the code spells.
    string[] modules;
}

/// Annotation attributes that hold SpEL.
immutable string[2][] spelAttributes = [
    ["flint.cache.annotation.Cacheable", "key"], ["flint.cache.annotation.Cacheable", "condition"],
    ["flint.cache.annotation.Cacheable", "unless"], ["flint.cache.annotation.CachePut", "key"],
    ["flint.cache.annotation.CachePut", "condition"], ["flint.cache.annotation.CachePut",
        "unless"], ["flint.cache.annotation.CacheEvict",
        "key"], ["flint.cache.annotation.CacheEvict",
        "condition"], ["flint.security.access.prepost.PreAuthorize", "value"],
    ["flint.security.access.prepost.PostAuthorize", "value"],
    ["flint.context.event.EventListener", "condition"]
];

/// A descriptor property.
struct PropertyPlan
{
    /// Java Beans name.
    string name;
    /// Type, as D source.
    string type;
    /// Modules the type's spelling needs.
    string[] modules;
    /// Merged annotations of the field, getter and setter.
    MergedSet annotations;
    /// "field" (public), "tuple" (private, by `tupleof`) or "accessor" (getter and setter).
    string access;
    /// For "field" and "tuple": the field name and index.
    string field;
    /// ditto
    long index;
    /// For "accessor".
    string getter;
    /// ditto
    string setter;
    /// Whether the property can be written.
    bool writable;
}

/// A descriptor.
struct DescriptorPlan
{
    /// Fully qualified type.
    string type;
    /// Simple name.
    string simple;
    /// "struct_", "class_", "interface_" or "enum_".
    string kind;
    /// Supertypes, nearest first.
    string[] supertypes;
    /// Merged type annotations.
    MergedSet annotations;
    /// Properties.
    PropertyPlan[] properties;
    /// "init" for `T.init`, "new" for `new T()`, empty when none.
    string create;
    /// Enum constants.
    string[] constants;
    /// Advised, mapped and listener methods.
    MethodPlan[] methods;
    /// Constructors: for a struct without one, its field-wise (canonical) constructor first.
    ConstructorPlan[] constructors;
}

/// A descriptor constructor.
struct ConstructorPlan
{
    /// "literal" (a struct's field-wise constructor), "struct" or "class".
    string kind;
    /// Parameters, named after the fields for "literal".
    Parameter[] parameters;
    /// Merged parameter annotations (the field's for "literal").
    MergedSet[] parameterAnnotations;
    /// Merged constructor annotations (`@JsonCreator`).
    MergedSet annotations;
}

/// A handler argument.
struct ArgumentPlan
{
    /// `ArgumentKind` member name.
    string kind;
    /// Binding name.
    string name;
    /// Parameter type.
    string type;
    /// Whether it is required.
    bool required;
    /// Default value, when the binding annotation gives one.
    string defaultValue;
    /// Whether a default value was given.
    bool hasDefault;
    /// `@Valid` or `@Validated`.
    bool validate;
    /// The exception parameter of an exception handler.
    bool exception;
    /// Contract 2: the element type of an array, or the first template argument (`HttpEntity!T`, `Optional!T`).
    string elementType;
    /// Modules declaring the parameter's type, for spelling template instances with typeNameOf.
    string[] modules;
    /// Merged parameter annotations.
    MergedSet annotations;
}

/// A request mapping.
struct HandlerPlan
{
    /// Controller bean and class.
    string bean;
    /// ditto
    string className;
    /// Handler method.
    Method method;
    /// Combined paths.
    string[] paths;
    /// Conditions.
    string[] methods;
    /// ditto
    string[] params;
    /// ditto
    string[] headers;
    /// ditto
    string[] consumes;
    /// ditto
    string[] produces;
    /// Arguments.
    ArgumentPlan[] arguments;
    /// Whether the response is the body.
    bool responseBody;
    /// `@ResponseStatus`.
    long status;
    /// ditto
    string reason;
    /// Index in the controller's descriptor methods.
    size_t index;
    /// Source location.
    string source;
    /// Contract 2: the controller's merged class-level annotations.
    MergedSet typeAnnotations;
}

/// An exception handler.
struct ExceptionPlan
{
    /// Declaring bean and class.
    string bean;
    /// ditto
    string className;
    /// Handler method.
    Method method;
    /// Handled exception types.
    string[] exceptionTypes;
    /// Declared in a `@ControllerAdvice`.
    bool advice;
    /// `@ControllerAdvice(basePackages)`.
    string[] basePackages;
    /// Contract 2: `@ControllerAdvice(assignableTypes)` and `@ControllerAdvice(annotations)`.
    string[] assignableTypes;
    /// ditto
    string[] adviceAnnotations;
    /// Contract 2: `@ExceptionHandler(produces)`.
    string[] produces;
    /// Arguments.
    ArgumentPlan[] arguments;
    /// Whether the response is the body.
    bool responseBody;
    /// `@ResponseStatus`.
    long status;
    /// Source location.
    string source;
}

/// An event listener.
struct ListenerPlan
{
    /// Declaring bean and class.
    string bean;
    /// ditto
    string className;
    /// Listener method.
    string method;
    /// The event types: `@EventListener(classes)`, else the parameter's type. One spec is registered per type.
    string[] eventTypes;
    /// The parameter's type; empty for a method without a parameter.
    string parameterType;
    /// SpEL condition.
    string condition;
    /// `@Order`.
    long order = int.max;
    /// The compiled condition, when there is one (aot-contract.md section 9.1).
    string conditionCode;
    /// ditto
    string[] conditionModules;
    /// The listener method, for compiling its condition: zero or one entry.
    Method[] conditionMethod;
    /// The method's return type; a non-void listener's result is published as replies (`invokeForResult`).
    string returnType;
}

/// A derived query.
struct QueryPlan
{
    /// Repository interface and domain type.
    string repository;
    /// ditto
    string domainType;
    /// The translated query.
    DerivedQuery query;
    /// Source location.
    string source;
}

/// Everything one generated module holds.
struct ModulePlan
{
    /// The extracted module.
    string name;
    /// Its source file.
    string source;
    /// Contents.
    BeanPlan[] beans;
    /// ditto
    ConfigPlan[] configurations;
    /// ditto
    ProxyPlan[] proxies;
    /// ditto
    DescriptorPlan[] descriptors;
    /// ditto
    HandlerPlan[] handlers;
    /// ditto
    ExceptionPlan[] exceptionHandlers;
    /// ditto
    ListenerPlan[] listeners;
    /// ditto
    QueryPlan[] queries;
    /// Other extracted modules whose models this one's output depends on.
    string[] consulted;
    /// Container types (`Optional!T`, `Map!(K, V)`, `List!T`, arrays) of bound properties, described by engine-aot's
    /// `descriptorOf`, which fills their erased builders; with the modules their spelling needs.
    string[] containerDescriptors;
    /// ditto
    string[] containerModules;

    /// Whether the module contributes anything.
    bool empty() const
    {
        return beans.length == 0 && descriptors.length == 0 && containerDescriptors.length == 0
            && handlers.length == 0 && exceptionHandlers.length == 0 && listeners.length == 0 && queries.length == 0;
    }
}

/// The whole generation plan.
struct Plan
{
    /// The `@FlintBootApplication` class, or empty when the project has none.
    string application;
    /// Scanned packages.
    string[] scanPackages;
    /// Generated modules, by module name.
    ModulePlan[] modules;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// Class names whose presence must be asked before the plan is final.
    string[] unknownClasses;
    /// Definitions removed at build time, as "name: reason".
    string[] removed;

    /// Whether any diagnostic is an error.
    bool failed() const
    {
        foreach (ref item; diagnostics)
        {
            if (!item.warning)
                return true;
        }
        return false;
    }
}

/// What the analysis is given besides the model.
struct AnalysisInput
{
    /// Modules under `src/`.
    string[] userModules;
    /// Auto-configuration classes of the closure, in the imports files' order.
    string[] autoConfigurations;
    /// Project root, to shorten source paths.
    string root;
}

/// Analyse the model.
Plan analyze(const Model model, const ref AnalysisInput input)
{
    import std.algorithm.sorting : sort;

    auto analysis = new Analysis(model, input);
    analysis.run();
    sort!((a, b) => a.name < b.name)(analysis.plan.modules);
    return analysis.plan;
}

private struct DefinedClass
{
    BeanPlan bean;
    bool proxyConfiguration;
}

private struct Candidate
{
    const(TypeDecl)* decl;
    MergedSet merged;
    bool autoConfiguration;
    /// Imported by another configuration's `@Import`: named by its fully qualified name, and registered only
    /// when the importer's startup conditions hold.
    bool imported;
    /// ditto
    string[] importerTerms;
}

/// The classes the `@Import`s on an element name: declared directly or carried by its annotations'
/// meta-annotations at any depth (`@EnableMethodSecurity` is `@Import(PrePostMethodSecurityConfiguration)`),
/// every occurrence kept, unlike merging, which keeps the nearest one per type.
string[] importedClasses(const Annotation[] annotations, const AnnotationType[string] types)
{
    import std.algorithm.searching : canFind;
    import flint_tool.engine.aot.names : import_;

    string[] result;
    bool[string] visited;
    void walk(const Annotation[] items)
    {
        foreach (ref annotation; items)
        {
            if (annotation.type == import_)
            {
                foreach (name; annotation.get("value").strings)
                {
                    if (!result.canFind(name))
                        result ~= name;
                }
                continue;
            }
            if (annotation.type in visited)
                continue;
            visited[annotation.type] = true;
            if (const type = annotation.type in types)
                walk(type.meta);
        }
    }

    walk(annotations);
    return result;
}

private final class Analysis
{
    const Model model;
    AnalysisInput input;
    Plan plan;
    uint rank;
    size_t[string] moduleIndex;
    BeanPlan[] allBeans;
    /// Auto-configurations the application excludes at build time.
    bool[string] excluded;
    /// Defined classes (scanned, auto-configured or imported) by fully qualified name.
    DefinedClass[string] definedClasses;
    /// Classes whose configuration is processed (or left out).
    bool[string] finished;
    /// Classes whose class definition is decided (defined or left out).
    bool[string] decided;
    /// Importing classes of each imported class.
    string[][string] importersOf;
    /// Modules whose types are described.
    bool[string] described;
    /// Types `describeProperties` has visited.
    bool[string] describedTypes;

    this(const Model model, const ref AnalysisInput input)
    {
        this.model = model;
        this.input = AnalysisInput(input.userModules.dup, input.autoConfigurations.dup, input.root);
    }

    void run()
    {
        import flint_tool.engine.aot.names : flintApplication, flintBootApplication;

        foreach (name; input.userModules)
        {
            const item = model.module_(name);
            if (item is null)
                continue;
            foreach (ref decl; item.types)
            {
                const merged = mergedOf(decl);
                const isApplication = merged.has(flintBootApplication) || merged.has(flintApplication);
                if (decl.kind == "class" && isApplication && plan.application.length == 0)
                {
                    plan.application = decl.fqn;
                    scanPackagesOf(decl);
                }
            }
        }
        if (plan.application.length == 0)
            return;
        // Spring's order (ConfigurationClassParser, then the deferred auto-configuration imports): every scanned
        // component's class definition first; then each configuration's imports and @Bean methods in scan order;
        // then each auto-configuration's class, imports and @Bean methods.
        Candidate[] user = userCandidates();
        Candidate[] autos = autoConfigurationCandidates();
        collectImporters(user ~ autos);
        foreach (ref candidate; user)
            defineClass(candidate);
        foreach (ref candidate; user)
            processConfiguration(candidate);
        foreach (ref candidate; autos)
        {
            if (candidate.decl.fqn in definedClasses || candidate.decl.fqn in finished)
                continue;
            defineClass(candidate);
            processConfiguration(candidate);
        }
        placeRemainingImports();
        compileExpressions();
        checkInjection();
        checkCycles();
        foreach (name; input.userModules)
        {
            if (scanned(name))
                describeOnce(name);
        }
        compileMethodExpressions();
    }

    MergedSet mergedOf(const ref TypeDecl decl)
    {
        import flint_tool.engine.aot.merge : merge;

        auto result = merge(decl.annotations, model.annotationTypes);
        foreach (conflict; result.conflicts)
            error("FLINT-E1103", conflict, decl.file, decl.line);
        return result;
    }

    MergedSet mergedOf(const ref Method method)
    {
        import flint_tool.engine.aot.merge : merge;

        auto result = merge(method.annotations, model.annotationTypes);
        foreach (conflict; result.conflicts)
            error("FLINT-E1103", conflict, method.file, method.line);
        return result;
    }

    MergedSet mergedOf(const ref Parameter parameter)
    {
        import flint_tool.engine.aot.merge : merge;

        return merge(parameter.annotations, model.annotationTypes);
    }

    /// The methods a class method overrides or implements in its model supertypes: same name and parameter types.
    const(Method)*[] overridden(const ref TypeDecl decl, const ref Method method)
    {
        const(Method)*[] result;
        const signature = parameterTypes(method);
        foreach (ref supertype; decl.supertypes)
        {
            const base = model.type(supertype.name);
            if (base is null)
                continue;
            foreach (ref candidate; base.methods)
            {
                if (candidate.name == method.name && !candidate.inherited && parameterTypes(candidate) == signature)
                    result ~= &candidate;
            }
        }
        return result;
    }

    /// A method's merged annotations searched through its type hierarchy, as Spring's TYPE_HIERARCHY strategy
    /// does: its own first, then those of the interface and superclass methods it implements or overrides.
    MergedSet hierarchyMerged(const ref TypeDecl decl, const ref Method method)
    {
        import flint_tool.engine.aot.merge : merge;

        Annotation[] declared;
        foreach (ref annotation; method.annotations)
            declared ~= clone(annotation);
        foreach (base; overridden(decl, method))
        {
            foreach (ref annotation; base.annotations)
                declared ~= clone(annotation);
        }
        auto result = merge(declared, model.annotationTypes);
        foreach (conflict; result.conflicts)
            error("FLINT-E1103", conflict, method.file, method.line);
        return result;
    }

    /// A class's merged annotations with those of its model supertypes after its own, as an inherited pointcut sees
    /// them: `@Validated` on petclinic-rest's generated `OwnersApi` advises the implementing controller.
    MergedSet typeHierarchyMerged(const ref TypeDecl decl)
    {
        import flint_tool.engine.aot.merge : merge;

        Annotation[] declared;
        foreach (ref annotation; decl.annotations)
            declared ~= clone(annotation);
        foreach (ref supertype; decl.supertypes)
        {
            if (const base = model.type(supertype.name))
            {
                foreach (ref annotation; base.annotations)
                    declared ~= clone(annotation);
            }
        }
        return merge(declared, model.annotationTypes);
    }

    /// A parameter's merged annotations with those of the same parameter in overridden methods, as Spring MVC's
    /// HandlerMethodParameter finds `@PathVariable` and `@RequestBody` on an implemented interface.
    MergedSet hierarchyMerged(const ref TypeDecl decl, const ref Method method, size_t index)
    {
        import flint_tool.engine.aot.merge : merge;

        Annotation[] declared;
        foreach (ref annotation; method.parameters[index].annotations)
            declared ~= clone(annotation);
        foreach (base; overridden(decl, method))
        {
            foreach (ref annotation; base.parameters[index].annotations)
                declared ~= clone(annotation);
        }
        return merge(declared, model.annotationTypes);
    }

    void error(string code, string message, string file, long line)
    {
        plan.diagnostics ~= Diagnostic(code, message, relative(file), line);
    }

    string relative(string file)
    {
        if (input.root.length && file.length > input.root.length && file[0 .. input.root.length] == input.root)
            return file[input.root.length + 1 .. $];
        return file;
    }

    string location(string file, long line)
    {
        import std.conv : to;

        return relative(file) ~ ":" ~ line.to!string;
    }

    void scanPackagesOf(const ref TypeDecl decl)
    {
        import flint_tool.engine.aot.names : flintBootApplication, packageOf;

        const merged = mergedOf(decl);
        const annotation = merged.get(flintBootApplication);
        if (annotation !is null)
            plan.scanPackages = annotation.get("scanBasePackages").strings;
        exclusionsOf(merged);
        if (plan.scanPackages.length == 0)
            plan.scanPackages = [packageOf(decl.module_)];
    }

    /// `exclude` and `excludeName` of `@FlintBootApplication` and `@EnableAutoConfiguration` (merged, so declared
    /// directly or as a meta-annotation).
    void exclusionsOf(const ref MergedSet merged)
    {
        import flint_tool.engine.aot.names : enableAutoConfiguration, flintBootApplication;

        foreach (type; [flintBootApplication, enableAutoConfiguration])
        {
            if (const annotation = merged.get(type))
            {
                foreach (name; annotation.get("exclude").strings ~ annotation.get("excludeName").strings)
                    excluded[name] = true;
            }
        }
    }

    bool scanned(string moduleName)
    {
        import flint_tool.engine.aot.names : inPackage;

        foreach (name; plan.scanPackages)
        {
            if (inPackage(moduleName, name))
                return true;
        }
        return false;
    }

    ref ModulePlan moduleFor(string name)
    {
        if (auto index = name in moduleIndex)
            return plan.modules[*index];
        ModulePlan item;
        item.name = name;
        if (const extracted = model.module_(name))
        {
            if (extracted.types.length)
                item.source = relative(extracted.types[0].file);
        }
        moduleIndex[name] = plan.modules.length;
        plan.modules ~= item;
        return plan.modules[$ - 1];
    }

    Candidate[] userCandidates()
    {
        import std.algorithm.sorting : sort;
        import flint_tool.engine.aot.names : component;

        Candidate[] result;
        string[] modules = input.userModules.dup;
        sort(modules);
        foreach (name; modules)
        {
            const item = model.module_(name);
            if (item is null || !scanned(name))
                continue;
            foreach (ref decl; item.types)
            {
                auto merged = mergedOf(decl);
                if (decl.kind == "class" && merged.has(component))
                    result ~= Candidate(&decl, merged, false);
            }
        }
        return result;
    }

    Candidate[] autoConfigurationCandidates()
    {
        import std.algorithm.mutation : SwapStrategy;
        import std.algorithm.sorting : sort;

        Candidate[] result;
        foreach (name; input.autoConfigurations)
        {
            const decl = model.type(name);
            if (decl is null)
                continue;
            if (name in excluded)
            {
                plan.removed ~= name ~ ": excluded by the application's exclude or excludeName";
                continue;
            }
            result ~= Candidate(decl, mergedOf(*decl), true);
        }
        // Boot sorts alphabetically, then by @AutoConfigureOrder, then by @AutoConfigureAfter/Before.
        sort!((a, b) => a.decl.fqn < b.decl.fqn)(result);
        sort!((a, b) => autoConfigurationOrder(a) < autoConfigurationOrder(b), SwapStrategy.stable)(result);
        return afterBefore(result);
    }

    static long autoConfigurationOrder(ref const Candidate candidate)
    {
        import flint_tool.engine.aot.names : autoConfigureOrder;

        const annotation = candidate.merged.get(autoConfigureOrder);
        return annotation is null ? 0 : annotation.get("value").integer;
    }

    /// Order auto-configurations by `@AutoConfiguration(after, before)` and `@AutoConfigureAfter/Before`, keeping
    /// the incoming order where unconstrained.
    Candidate[] afterBefore(Candidate[] items)
    {
        import flint_tool.engine.aot.names : autoConfiguration, autoConfigureAfter, autoConfigureBefore;

        bool[string][string] after;
        foreach (ref item; items)
        {
            string[] afters;
            string[] befores;
            if (const annotation = item.merged.get(autoConfiguration))
            {
                afters ~= annotation.get("after").strings;
                befores ~= annotation.get("before").strings;
            }
            if (const annotation = item.merged.get(autoConfigureAfter))
                afters ~= annotation.get("value").strings ~ annotation.get("name").strings;
            if (const annotation = item.merged.get(autoConfigureBefore))
                befores ~= annotation.get("value").strings ~ annotation.get("name").strings;
            foreach (name; afters)
                after[item.decl.fqn][name] = true;
            foreach (name; befores)
                after[name][item.decl.fqn] = true;
        }
        Candidate[] ordered;
        bool[string] placed;
        bool[string] visiting;
        void visit(ref Candidate item)
        {
            if (item.decl.fqn in placed || item.decl.fqn in visiting)
                return;
            visiting[item.decl.fqn] = true;
            if (auto needs = item.decl.fqn in after)
            {
                foreach (ref other; items)
                {
                    if (other.decl.fqn in *needs)
                        visit(other);
                }
            }
            placed[item.decl.fqn] = true;
            ordered ~= item;
        }

        foreach (ref item; items)
            visit(item);
        return ordered;
    }

    /// Define a candidate's class (and the class's proxy), without its @Bean methods or imports; false when it is
    /// left out (not public, abstract, or removed by a build-time condition).
    bool defineClass(ref Candidate candidate)
    {
        decided[candidate.decl.fqn] = true;
        import flint_tool.engine.aot.conditions : evaluate;
        import flint_tool.engine.aot.names : beanName, component;

        const decl = candidate.decl;
        if (decl.visibility != "public" && decl.visibility != "export")
        {
            const message = "@Component class " ~ decl.name ~ " is " ~ decl.visibility;
            error("FLINT-E1108", message ~ "; generated code needs it public", decl.file, decl.line);
            return false;
        }
        if (decl.abstract_)
            return false;
        auto outcome = evaluate(candidate.merged, decl.fqn, model.present);
        if (!acceptOutcome(outcome, decl.name, decl.file, decl.line))
            return false;
        // Boot's spring.boot.enableautoconfiguration=false turns every auto-configuration off at startup.
        if (candidate.autoConfiguration)
            outcome.terms = autoConfigurationTerms(decl.fqn) ~ outcome.terms;
        // An imported configuration registers only where its importer does.
        outcome.terms = candidate.importerTerms ~ outcome.terms;
        BeanPlan bean;
        bean.name = componentName(candidate);
        bean.type = decl.fqn;
        bean.types = typesOf(*decl);
        bean.objectTypes = factoryObjectTypes(*decl);
        bean.autoConfiguration = candidate.autoConfiguration;
        bean.className = decl.fqn;
        bean.source = location(decl.file, decl.line);
        bean.file = relative(decl.file);
        bean.line = decl.line;
        bean.condition = joinTerms(outcome.terms);
        definitionAttributes(candidate.merged, bean);
        constructorOf(*decl, bean);
        fieldsOf(*decl, bean);
        lifecycleOf(*decl, bean);
        propertiesOf(candidate.merged, bean);
        const proxyConfiguration = configurationProxy(candidate, bean);
        const inherited = typeHierarchyMerged(*decl);
        bean.proxied = !proxyConfiguration && planProxy(*decl, inherited, bean);
        bean.rank = rank++;
        addBean(decl.module_, bean);
        definedClasses[decl.fqn] = DefinedClass(bean, proxyConfiguration);
        if (bean.proxied || candidate.merged.has(imported!"flint_tool.engine.aot.names".controller))
            moduleFor(decl.module_).consulted ~= decl.module_;
        return true;
    }

    /// A configuration's imports, enabled properties and @Bean methods, all conditional on the configuration's
    /// own definition having registered (Spring evaluates a configuration's conditions once).
    void processConfiguration(ref Candidate candidate)
    {
        import flint_tool.engine.aot.conditions : literal;

        const fqn = candidate.decl.fqn;
        const defined = fqn in definedClasses;
        if (defined is null || fqn in finished)
        {
            finished[fqn] = true;
            return;
        }
        // Imported configurations register before the importer's own @Bean methods, which therefore override
        // theirs (gh-24643).
        foreach (name; importsOf(*candidate.decl))
            placeImport(name);
        const owner = defined.bean;
        const ownerTerm = ["c.hasBeanNamed(" ~ literal(owner.name) ~ ")"];
        enableConfigurationProperties(candidate, ownerTerm);
        defineBeanMethods(candidate, owner, ownerTerm, defined.proxyConfiguration);
        finished[fqn] = true;
    }

    /// The classes a type's `@Import`s name, its supertypes' included (gh-34820: `@Import` on an interface).
    string[] importsOf(const ref TypeDecl decl)
    {
        Annotation[] declared;
        foreach (ref annotation; decl.annotations)
            declared ~= clone(annotation);
        foreach (ref supertype; decl.supertypes)
        {
            if (const base = model.type(supertype.name))
            {
                foreach (ref annotation; base.annotations)
                    declared ~= clone(annotation);
            }
        }
        return importedClasses(declared, model.annotationTypes);
    }

    /// Every class importing each imported class, over everything reachable from the candidates.
    void collectImporters(Candidate[] candidates)
    {
        import std.algorithm.searching : canFind;

        string[] pending;
        foreach (ref candidate; candidates)
            pending ~= candidate.decl.fqn;
        bool[string] seen;
        while (pending.length)
        {
            const name = pending[0];
            pending = pending[1 .. $];
            if (name in seen)
                continue;
            seen[name] = true;
            const decl = model.type(name);
            if (decl is null)
                continue;
            foreach (imported; importsOf(*decl))
            {
                if (!importersOf.get(imported, null).canFind(name))
                    importersOf[imported] ~= name;
                pending ~= imported;
            }
        }
    }

    /// Place an imported class at its first importer, as Spring does, once every importer's class definition is
    /// decided, so its condition, "any importer registered", sees them all. Scanned importers are decided before
    /// any import is placed. A class that is also scanned keeps its scanned definition.
    void placeImport(string name)
    {
        if (name in definedClasses || name in finished)
            return;
        foreach (importer; importersOf.get(name, null))
        {
            if (importer !in decided)
                return;
        }
        defineImported(name);
    }

    void defineImported(string name)
    {
        import std.array : join;
        import flint_tool.engine.aot.conditions : literal;

        string[] registered;
        foreach (importer; importersOf.get(name, null))
        {
            if (auto defined = importer in definedClasses)
                registered ~= "c.hasBeanNamed(" ~ literal(defined.bean.name) ~ ")";
        }
        const target = model.type(name);
        if (target is null)
        {
            if (const importer = model.type(importersOf[name][0]))
                error("FLINT-E1106", "@Import names " ~ name ~ ", which is not in the closure",
                        importer.file, importer.line);
            finished[name] = true;
            return;
        }
        if (registered.length == 0)
        {
            finished[name] = true;
            return;
        }
        auto candidate = Candidate(target, mergedOf(*target), false, true, [
            "(" ~ registered.join(" || ") ~ ")"
        ]);
        if (!defineClass(candidate))
        {
            finished[name] = true;
            return;
        }
        processConfiguration(candidate);
    }

    /// Imports whose importers were never all decided (an importer that is not a candidate).
    void placeRemainingImports()
    {
        foreach (name, importers; importersOf)
        {
            if (name !in definedClasses && name !in finished)
                defineImported(name);
        }
    }

    bool definesClass(string name)
    {
        foreach (ref bean; allBeans)
        {
            if (bean.className == name && bean.method.length == 0)
                return true;
        }
        return false;
    }

    /// Boot's `@EnableConfigurationProperties`: each listed `@ConfigurationProperties` class becomes a bean named
    /// `<prefix>-<fully qualified name>`, under the enabling configuration's conditions, bound at creation; its
    /// module's types are described for the binder. A class enabled twice is registered once.
    void enableConfigurationProperties(ref Candidate candidate, const string[] terms)
    {
        import flint_tool.engine.aot.names : configurationProperties,
            enableConfigurationProperties_ = enableConfigurationProperties;

        const annotation = candidate.merged.get(enableConfigurationProperties_);
        if (annotation is null)
            return;
        foreach (type; annotation.get("value").strings)
        {
            if (hasCandidate(type))
                continue;
            const decl = model.type(type);
            if (decl is null)
            {
                error("FLINT-E1106",
                        "@EnableConfigurationProperties names " ~ type ~ ", which no module in the closure declares",
                        candidate.decl.file, candidate.decl.line);
                continue;
            }
            auto merged = mergedOf(*decl);
            const properties = merged.get(configurationProperties);
            string prefix = properties is null ? null : properties.text("prefix");
            if (prefix.length == 0 && properties !is null)
                prefix = properties.text("value");
            BeanPlan bean;
            bean.name = prefix.length ? prefix ~ "-" ~ decl.fqn : decl.fqn;
            bean.type = decl.fqn;
            bean.types = typesOf(*decl);
            bean.className = decl.fqn;
            bean.source = location(decl.file, decl.line);
            bean.file = relative(decl.file);
            bean.line = decl.line;
            bean.condition = joinTerms(terms);
            definitionAttributes(merged, bean);
            constructorOf(*decl, bean);
            fieldsOf(*decl, bean);
            lifecycleOf(*decl, bean);
            propertiesOf(merged, bean);
            bean.rank = rank++;
            // In the enabling configuration's module, so it registers (and its conditions run) before the
            // configuration's @Bean methods, wherever the properties class is declared.
            addBean(candidate.decl.module_, bean);
            describeProperties(decl.fqn);
        }
    }

    /// Describe a user module's types once.
    void describeOnce(string moduleName)
    {
        if (moduleName in described)
            return;
        described[moduleName] = true;
        describeModule(moduleName);
    }

    /// Describe a `@ConfigurationProperties` class and, through its properties, every type the binder reaches:
    /// nested groups, enums and the types in other modules. Template instances (`Optional!T`, `Map!(K, V)`) are
    /// described by their arguments.
    void describeProperties(string type)
    {
        import std.algorithm.searching : canFind, endsWith;
        import std.ascii : isAlphaNum;

        // The dotted names in the spelling: `flint.java.util.Optional!(core.time.Duration)` names both.
        size_t start;
        foreach (index; 0 .. type.length + 1)
        {
            if (index < type.length && (isAlphaNum(type[index]) || type[index] == '_' || type[index] == '.'))
                continue;
            const name = type[start .. index];
            start = index + 1;
            if (!name.canFind('.') || name in describedTypes)
                continue;
            describedTypes[name] = true;
            const decl = model.type(name);
            if (decl is null || (decl.kind == "class" && decl.abstract_))
                continue;
            auto descriptor = dataDescriptor(*decl, mergedOf(*decl));
            addDescriptor(moduleFor(decl.module_), descriptor);
            foreach (ref property; descriptor.properties)
            {
                const container = property.type.canFind("!(") || property.type.endsWith("[]");
                if (container && !moduleFor(decl.module_).containerDescriptors.canFind(property.type))
                {
                    moduleFor(decl.module_).containerDescriptors ~= property.type;
                    moduleFor(decl.module_).containerModules ~= property.modules;
                }
                describeProperties(property.type);
            }
        }
    }

    bool acceptOutcome(ref imported!"flint_tool.engine.aot.conditions".ConditionOutcome outcome,
            string name, string file, long line)
    {
        foreach (index, message; outcome.errors)
            error(outcome.codes[index], message, file, line);
        plan.unknownClasses ~= outcome.unknownClasses;
        if (!outcome.included)
        {
            plan.removed ~= name ~ ": " ~ outcome.reason;
            return false;
        }
        return true;
    }

    /// Boot's startup switches for an auto-configuration: spring.boot.enableautoconfiguration and the
    /// spring.autoconfigure.exclude list (contract 2), under Flint's prefixes.
    static string[] autoConfigurationTerms(string type)
    {
        import flint_tool.engine.aot.conditions : literal;
        import flint_tool.engine.aot.names : enableAutoConfigurationProperty;

        return [
            "c.property(" ~ literal(enableAutoConfigurationProperty) ~ ", \"true\", true)",
            "!c.isAutoConfigurationExcluded(" ~ literal(type) ~ ")"
        ];
    }

    /// The types of the object a `FactoryBean!T` makes, so `getBean(T)` finds it before the factory exists.
    string[] factoryObjectTypes(const ref TypeDecl decl)
    {
        foreach (ref supertype; decl.supertypes)
        {
            if (supertype.template_ == "flint.beans.factory.FactoryBean" && supertype.arguments.length == 1)
                return typesOf(supertype.arguments[0]);
        }
        return null;
    }

    string componentName(ref Candidate candidate)
    {
        import flint_tool.engine.aot.names : beanName, component;

        const annotation = candidate.merged.get(component);
        const explicit = annotation is null ? null : annotation.text("value");
        if (explicit.length)
            return explicit;
        // Auto-configurations are named by their fully qualified class name, as Boot names them.
        return candidate.autoConfiguration || candidate.imported ? candidate.decl.fqn : beanName(candidate.decl.name);
    }

    string[] typesOf(const ref TypeDecl decl)
    {
        string[] types = [decl.fqn];
        foreach (ref supertype; decl.supertypes)
        {
            if (supertype.name != "object.Object")
                types ~= supertype.name;
        }
        return types;
    }

    string[] typesOf(const ref TypeRef type)
    {
        import std.algorithm.searching : canFind;

        string[] types = [type.name];
        if (const decl = model.type(type.name))
            return typesOf(*decl);
        foreach (supertype; type.supertypes)
        {
            if (!types.canFind(supertype))
                types ~= supertype;
        }
        return types;
    }

    void addBean(string moduleName, BeanPlan bean)
    {
        allBeans ~= bean;
        moduleFor(moduleName).beans ~= bean;
    }

    void definitionAttributes(const ref MergedSet merged, ref BeanPlan bean)
    {
        import flint_tool.engine.aot.names : dependsOn, fallback, lazy_, order, primary, qualifier, scope_;

        bean.primary = merged.has(primary);
        bean.fallback = merged.has(fallback);
        if (const annotation = merged.get(lazy_))
            bean.lazyInit = annotation.flag("value", true);
        if (const annotation = merged.get(dependsOn))
            bean.dependsOn ~= annotation.get("value").strings;
        if (const annotation = merged.get(scope_))
        {
            const value = annotation.text("value").length ? annotation.text("value") : annotation.text("scopeName");
            if (value.length)
                bean.scope_ = value;
        }
        if (const annotation = merged.get(order))
            bean.order = annotation.get("value").integer;
        if (const annotation = merged.get(qualifier))
            bean.qualifiers ~= annotation.text("value");
    }

    Point pointOf(const ref Parameter parameter, const MergedSet merged, string file, long line)
    {
        return pointFor(parameter.type, merged, file, line);
    }

    Point pointFor(const ref TypeRef type, const MergedSet merged, string file, long line)
    {
        import std.algorithm.searching : startsWith;
        import flint_tool.engine.aot.names : autowired, qualifier, value;

        Point point;
        point.type = type.name;
        point.lookup = type.name;
        point.modules = modulesOf(type);
        if (const annotation = merged.get(qualifier))
            point.qualifier = annotation.text("value");
        if (const annotation = merged.get(value))
        {
            point.kind = PointKind.value;
            point.expression = annotation.text("value");
            if (point.expression.canFind("#{"))
            {
                // Compiled once every bean is defined, so @bean references resolve (compileExpressions).
                point.kind = PointKind.spel;
                point.template_ = point.expression;
                point.file = file;
                point.line = line;
            }
            return point;
        }
        const required = merged.get(autowired) is null || merged.get(autowired).flag("required", true);
        if (type.element.length && type.name != "string")
        {
            point.kind = PointKind.beans;
            point.lookup = type.element[0].name;
        }
        else if (type.template_.length && (type.template_.startsWith("flint.java.util.Optional")
                || type.template_.startsWith("std.typecons.Nullable")) && type.arguments.length)
        {
            point.kind = PointKind.optional;
            point.lookup = type.arguments[0].name;
        }
        else if (type.template_ == "flint.java.util.List" && type.arguments.length)
        {
            point.kind = PointKind.beans;
            point.lookup = type.arguments[0].name;
        }
        else if (!required)
            point.kind = PointKind.optional;
        return point;
    }

    static string[] modulesOf(const ref TypeRef type)
    {
        string[] result = type.modules.dup;
        foreach (ref item; type.element)
            result ~= modulesOf(item);
        foreach (ref item; type.arguments)
            result ~= modulesOf(item);
        return result;
    }

    void constructorOf(const ref TypeDecl decl, ref BeanPlan bean)
    {
        import flint_tool.engine.aot.names : autowired;

        const constructors = decl.constructors;
        const(Method)* chosen;
        size_t autowiredCount;
        foreach (ref constructor; constructors)
        {
            if (mergedOf(constructor).has(autowired))
            {
                chosen = &constructor;
                ++autowiredCount;
            }
        }
        if (chosen is null && constructors.length == 1)
            chosen = &constructors[0];
        if (chosen is null && constructors.length > 1)
        {
            foreach (ref constructor; constructors)
            {
                if (constructor.parameters.length == 0)
                    chosen = &constructor;
            }
            if (chosen is null)
            {
                error("FLINT-E1105", "bean class " ~ decl.name ~ " has several constructors and none is @Autowired",
                        decl.file, decl.line);
                return;
            }
        }
        if (autowiredCount > 1)
            error("FLINT-E1105", "bean class " ~ decl.name ~ " has several @Autowired constructors",
                    decl.file, decl.line);
        if (chosen is null)
            return;
        foreach (ref parameter; chosen.parameters)
        {
            auto point = pointOf(parameter, mergedOf(parameter), chosen.file, chosen.line);
            bean.arguments ~= point;
            if (point.kind == PointKind.bean)
                bean.requires ~= point.lookup;
        }
    }

    void fieldsOf(const ref TypeDecl decl, ref BeanPlan bean)
    {
        import flint_tool.engine.aot.merge : merge;
        import flint_tool.engine.aot.names : autowired, inject, value;

        const(TypeDecl)*[] chain = [model.type(decl.fqn)];
        foreach (ref supertype; decl.supertypes)
        {
            if (const base = model.type(supertype.name))
            {
                if (base.kind == "class")
                    chain = base ~ chain;
            }
        }
        foreach (owner; chain)
        {
            foreach (ref field; owner.fields)
            {
                auto merged = merge(field.annotations, model.annotationTypes);
                if (!merged.hasAny([autowired, inject, value]))
                    continue;
                bean.fields ~= FieldPoint(owner.fqn, field.index, pointFor(field.type, merged,
                        owner.file, owner.line));
            }
        }
    }

    void lifecycleOf(const ref TypeDecl decl, ref BeanPlan bean)
    {
        import flint_tool.engine.aot.names : disposableBean, initializingBean, postConstruct, preDestroy;

        bean.initializingBean = decl.isA(initializingBean);
        bean.disposableBean = decl.isA(disposableBean);
        foreach (ref method; decl.methods)
        {
            if (method.name == "__ctor")
                continue;
            const merged = mergedOf(method);
            foreach (type; [postConstruct, preDestroy])
            {
                if (!merged.has(type))
                    continue;
                if (method.visibility != "public" || method.parameters.length)
                {
                    const message = "lifecycle method " ~ decl.name ~ "." ~ method.name;
                    error("FLINT-E1108", message ~ " must be public and take no parameters", method.file, method.line);
                    continue;
                }
                if (type == postConstruct)
                    bean.postConstruct ~= method.name;
                else
                    bean.preDestroy ~= method.name;
            }
        }
    }

    void propertiesOf(const ref MergedSet merged, ref BeanPlan bean)
    {
        import flint_tool.engine.aot.names : configurationProperties;

        if (const annotation = merged.get(configurationProperties))
        {
            bean.propertiesPrefix = annotation.text("prefix");
            if (bean.propertiesPrefix.length == 0)
                bean.propertiesPrefix = annotation.text("value");
        }
    }

    /// Whether the candidate is a configuration class whose bean methods need the configuration subclass.
    bool configurationProxy(ref Candidate candidate, ref BeanPlan bean)
    {
        import flint_tool.engine.aot.names : bean_ = bean, configuration;

        const annotation = candidate.merged.get(configuration);
        if (annotation is null || !annotation.flag("proxyBeanMethods", true))
            return false;
        ConfigPlan config;
        config.className = candidate.decl.fqn;
        config.simple = candidate.decl.name;
        foreach (ref constructor; candidate.decl.constructors)
        {
            if (constructor.parameters.length == bean.arguments.length)
                config.parameters = clone(constructor.parameters);
        }
        foreach (ref method; candidate.decl.methods)
        {
            if (method.static_ || method.inherited || !mergedOf(method).has(bean_))
                continue;
            if (method.final_ || method.visibility != "public")
            {
                error("FLINT-E1109", "@Bean method " ~ candidate.decl.name ~ "." ~ method.name ~ " must not be "
                        ~ "private or final; change the method's modifiers to continue", method.file, method.line);
                continue;
            }
            config.methods ~= clone(method);
            config.beans ~= beanMethodName(method, mergedOf(method));
        }
        if (config.methods.length == 0)
            return false;
        bean.factory = FactoryKind.configuration;
        moduleFor(candidate.decl.module_).configurations ~= config;
        return true;
    }

    string beanMethodName(const ref Method method, const MergedSet merged)
    {
        import flint_tool.engine.aot.names : bean;

        const annotation = merged.get(bean);
        auto names = annotation.get("name").strings;
        if (names.length == 0)
            names = annotation.get("value").strings;
        return names.length ? names[0] : method.name;
    }

    void defineBeanMethods(ref Candidate candidate, const ref BeanPlan owner, const string[] classTerms, bool proxied)
    {
        import flint_tool.engine.aot.conditions : evaluate;
        import flint_tool.engine.aot.names : bean;

        foreach (ref method; candidate.decl.methods)
        {
            if (method.inherited)
                continue;
            auto merged = mergedOf(method);
            if (!merged.has(bean))
                continue;
            if (method.returns.kind != "class" && method.returns.kind != "interface")
            {
                error("FLINT-E1115", "@Bean method " ~ candidate.decl.name ~ "." ~ method.name ~ " returns "
                        ~ method.returns.name ~ "; a bean is a class or interface instance", method.file, method.line);
                continue;
            }
            auto outcome = evaluate(merged, method.returns.name, model.present);
            if (!acceptOutcome(outcome, method.name, method.file, method.line))
                continue;
            BeanPlan definition;
            definition.name = beanMethodName(method, merged);
            definition.type = method.returns.name;
            definition.types = typesOf(method.returns);
            definition.autoConfiguration = candidate.autoConfiguration;
            definition.className = candidate.decl.fqn;
            definition.configBean = owner.name;
            definition.method = method.name;
            definition.factory = method.static_ ? FactoryKind.staticMethod : FactoryKind.method;
            definition.configProxied = proxied && !method.static_;
            definition.source = location(method.file, method.line);
            definition.file = relative(method.file);
            definition.line = method.line;
            definition.condition = joinTerms(classTerms ~ outcome.terms);
            definitionAttributes(merged, definition);
            beanMethodLifecycle(merged, method, definition);
            if (!method.static_)
            {
                definition.requires ~= candidate.decl.fqn;
                definition.dependsOn ~= owner.name;
            }
            foreach (ref parameter; method.parameters)
            {
                auto point = pointOf(parameter, mergedOf(parameter), method.file, method.line);
                definition.arguments ~= point;
                if (point.kind == PointKind.bean)
                    definition.requires ~= point.lookup;
            }
            definition.rank = rank++;
            addBean(candidate.decl.module_, definition);
        }
    }

    void beanMethodLifecycle(const ref MergedSet merged, const ref Method method, ref BeanPlan plan)
    {
        import flint_tool.engine.aot.names : bean, disposableBean, initializingBean;

        const annotation = merged.get(bean);
        plan.initMethod = annotation.text("initMethod");
        const destroy = annotation.get("destroyMethod");
        plan.destroyMethod = destroy.kind == imported!"flint_tool.engine.aot.model".Value.Kind.text
            ? destroy.text : "(inferred)";
        if (const returned = model.type(method.returns.name))
        {
            plan.initializingBean = returned.isA(initializingBean);
            plan.disposableBean = returned.isA(disposableBean);
            if (plan.destroyMethod == "(inferred)")
                plan.destroyMethod = inferredDestroy(*returned);
        }
        else if (plan.destroyMethod == "(inferred)")
            plan.destroyMethod = null;
    }

    string inferredDestroy(const ref TypeDecl decl)
    {
        foreach (name; ["close", "shutdown"])
        {
            foreach (ref method; decl.methods)
            {
                if (method.name == name && method.parameters.length == 0 && method.visibility == "public")
                    return name;
            }
        }
        return null;
    }

    bool planProxy(const ref TypeDecl decl, const ref MergedSet classMerged, ref BeanPlan bean)
    {
        ProxyPlan proxy;
        proxy.className = decl.fqn;
        proxy.simple = decl.name;
        proxy.constructors = clone(decl.constructors);
        DescriptorPlan descriptor = descriptorShell(decl, classMerged);
        bool[string] seen;
        foreach (ref method; decl.methods)
        {
            if (!overridable(method))
                continue;
            const signature = method.name ~ "(" ~ parameterTypes(method) ~ ")";
            if (signature in seen)
                continue;
            seen[signature] = true;
            proxyMethod(decl, method, classMerged, proxy, descriptor);
        }
        if (descriptor.methods.length == 0)
            return false;
        auto target = &moduleFor(decl.module_);
        target.proxies ~= proxy;
        addDescriptor(*target, descriptor);
        bean.described = true;
        return true;
    }

    /// Methods a proxy subclass may override, before visibility and attribute checks.
    static bool overridable(const ref Method method)
    {
        return method.name != "__ctor" && !method.static_ && method.name != "toHash"
            && method.name != "opCmp" && method.name != "opEquals";
    }

    /// Add one method to a proxy: advised through the chain, or forwarded.
    void proxyMethod(const ref TypeDecl decl, const ref Method method, const ref MergedSet classMerged,
            ref ProxyPlan proxy, ref DescriptorPlan descriptor)
    {
        import flint_tool.engine.aot.names : adviceAnnotations, async_;

        auto merged = hierarchyMerged(decl, method);
        const advised = classMerged.hasAny(adviceAnnotations) || merged.hasAny(adviceAnnotations);
        if (!checkAdvisable(decl, method, advised))
            return;
        // Generated code is @safe: a @system method (Object.toString) is left to the base class.
        if (method.visibility != "public" || method.final_ || (!method.has("@safe") && !method.has("@trusted")))
            return;
        ProxyMethod item = ProxyMethod(clone(method), advised, merged.has(async_) || classMerged.has(async_));
        if (advised)
        {
            item.index = descriptor.methods.length;
            auto advisedMethod = methodPlan(method, merged, classMerged);
            // Constraint annotations on an implemented interface's parameters validate like the method's own.
            foreach (index; 0 .. method.parameters.length)
                advisedMethod.parameters[index] = hierarchyMerged(decl, method, index);
            descriptor.methods ~= advisedMethod;
        }
        proxy.methods ~= item;
    }

    bool checkAdvisable(const ref TypeDecl decl, const ref Method method, bool advised)
    {
        import flint_tool.engine.aot.names : async_;

        if (!advised)
            return true;
        if (method.visibility != "public")
        {
            error("FLINT-E1112", "advised method " ~ decl.name ~ "." ~ method.name ~ " is " ~ method.visibility
                    ~ "; the proxy can only call public methods of its target", method.file, method.line);
            return false;
        }
        if (method.final_)
        {
            plan.diagnostics ~= Diagnostic("FLINT-E1111",
                    "final method " ~ decl.name ~ "." ~ method.name ~ " of a proxied class is not advised",
                    relative(method.file), method.line, true);
            return false;
        }
        if (!method.has("@safe") && !method.has("@trusted"))
        {
            error("FLINT-E1112",
                    "advised method " ~ decl.name ~ "." ~ method.name ~ " is @system; generated proxies " ~ "are @safe",
                    method.file, method.line);
            return false;
        }
        foreach (attribute; ["nothrow", "@nogc", "pure"])
        {
            if (method.has(attribute))
            {
                error("FLINT-E1112", "advised method " ~ decl.name ~ "." ~ method.name ~ " is "
                        ~ attribute ~ ", which the advice chain cannot honour", method.file, method.line);
                return false;
            }
        }
        if (mergedOf(method).has(async_) && method.returns.name != "void")
        {
            error("FLINT-E1113", "@Async method " ~ decl.name ~ "." ~ method.name ~ " returns " ~ method.returns.name
                    ~ "; only void @Async methods are supported until flint.java.util.concurrent lands",
                    method.file, method.line);
            return false;
        }
        return true;
    }

    MethodPlan methodPlan(const ref Method method, MergedSet merged, const MergedSet classMerged)
    {
        import flint_tool.engine.aot.merge : Merged;
        import flint_tool.engine.aot.names : adviceAnnotations;

        MethodPlan result;
        result.method = clone(method);
        // Class-level advice applies to every method that does not declare its own.
        foreach (ref item; classMerged.items)
        {
            import std.algorithm.searching : canFind;

            if (adviceAnnotations.canFind(item.type) && !merged.has(item.type))
                merged.items ~= Merged(clone(item.annotation), item.distance);
        }
        result.annotations = merged;
        foreach (ref parameter; method.parameters)
            result.parameters ~= mergedOf(parameter);
        result.expressions = expressionsOf(method, merged);
        return result;
    }

    /// Compile the SpEL-valued attributes of a method's merged annotations (aot-contract.md section 9.1).
    /// The SpEL-valued attributes of a method's merged annotations, recorded for compileMethodExpressions: every
    /// bean must be defined first, since expressions name beans (`@roles.OWNER_ADMIN`).
    ExpressionPlan[] expressionsOf(const ref Method method, const ref MergedSet merged)
    {
        ExpressionPlan[] result;
        foreach (entry; spelAttributes)
        {
            const annotation = merged.get(entry[0]);
            if (annotation is null)
                continue;
            const source = annotation.text(entry[1]);
            if (source.length)
                result ~= ExpressionPlan(entry[0], entry[1], source);
        }
        return result;
    }

    /// Compile one method-level expression (aot-contract.md section 9.1); false after reporting FLINT-E1107.
    bool compileExpression(const ref Method method, ref ExpressionPlan expression)
    {
        import flint_tool.engine.aot.spel : Compiled, SpelError, compileSpel;

        auto scope_ = new MethodScope(this, method);
        Compiled compiled;
        SpelError failure;
        if (!compileSpel(expression.source, scope_, compiled, failure))
        {
            const where = imported!"flint_tool.engine.aot.merge".shortName(
                    expression.annotation) ~ "(" ~ expression.attribute ~ ") on " ~ method.name;
            error("FLINT-E1107", "@" ~ where ~ ": " ~ failure.message, method.file, method.line);
            return false;
        }
        expression.code = compiled.type == "Any" ? compiled.code : "Any.of(" ~ compiled.code ~ ")";
        expression.modules = scope_.modules;
        return true;
    }

    /// Compile every recorded method-level expression, once all beans are defined.
    void compileMethodExpressions()
    {
        foreach (ref item; plan.modules)
        {
            foreach (ref descriptor; item.descriptors)
            {
                foreach (ref method; descriptor.methods)
                {
                    ExpressionPlan[] compiled;
                    foreach (ref expression; method.expressions)
                    {
                        if (compileExpression(method.method, expression))
                            compiled ~= expression;
                    }
                    method.expressions = compiled;
                }
            }
            foreach (ref listener; item.listeners)
            {
                if (listener.condition.length == 0 || listener.conditionMethod.length == 0)
                    continue;
                auto expression = ExpressionPlan("flint.context.event.EventListener", "condition", listener.condition);
                if (compileExpression(listener.conditionMethod[0], expression))
                {
                    listener.conditionCode = expression.code;
                    listener.conditionModules = expression.modules;
                }
            }
        }
    }

    DescriptorPlan descriptorShell(const ref TypeDecl decl, const MergedSet merged)
    {
        import flint_tool.engine.aot.merge : cloneMerged = clone;

        DescriptorPlan result;
        result.type = decl.fqn;
        result.simple = decl.name;
        result.kind = decl.kind ~ "_";
        result.annotations = cloneMerged(merged);
        foreach (ref supertype; decl.supertypes)
            result.supertypes ~= supertype.name;
        result.constants = decl.constants.dup;
        return result;
    }

    void addDescriptor(ref ModulePlan target, DescriptorPlan descriptor)
    {
        foreach (ref existing; target.descriptors)
        {
            if (existing.type == descriptor.type)
            {
                existing.methods ~= descriptor.methods;
                return;
            }
        }
        target.descriptors ~= descriptor;
    }

    string joinTerms(const string[] terms)
    {
        import std.array : join;

        return terms.join(" && ");
    }

    /// Compile every `@Value("#{...}")` to D (aot-contract.md section 9).
    void compileExpressions()
    {
        foreach (ref item; plan.modules)
        {
            foreach (ref bean; item.beans)
            {
                foreach (ref point; bean.arguments)
                    compilePoint(point);
                foreach (ref field; bean.fields)
                    compilePoint(field.point);
            }
        }
    }

    void compilePoint(ref Point point)
    {
        import std.array : join;
        import flint_tool.engine.aot.conditions : literal;
        import flint_tool.engine.aot.spel : Compiled, SpelError, compileSpel, convert, splitTemplate;

        if (point.kind != PointKind.spel || point.template_.length == 0)
            return;
        string[] parts;
        SpelError failure;
        if (!splitTemplate(point.template_, parts, failure))
        {
            error("FLINT-E1107", failure.message, point.file, point.line);
            return;
        }
        auto scope_ = new ValueScope(this);
        string[] pieces;
        Compiled single;
        foreach (index, part; parts)
        {
            if (index % 2 == 0)
            {
                if (part.length)
                    pieces ~= part.canFind("${")
                        ? "factory.resolveValue(" ~ literal(part) ~ ", \"string\").get!(string)()" : literal(part);
                continue;
            }
            Compiled compiled;
            if (!compileSpel(part, scope_, compiled, failure))
            {
                error("FLINT-E1107", failure.message, point.file, point.line);
                return;
            }
            single = compiled;
            pieces ~= convert(compiled, "string");
        }
        // A template that is one expression keeps its type; text around it makes a string.
        const lone = parts.length == 3 && parts[0].length == 0 && parts[2].length == 0;
        const value = lone ? single : Compiled("(" ~ pieces.join(" ~ ") ~ ")", "string");
        point.expression = convert(value, point.type);
        point.modules ~= scope_.modules;
        point.template_ = null;
    }

    void checkInjection()
    {
        import std.algorithm.searching : canFind;
        import flint_tool.engine.aot.names : infrastructureTypes;

        foreach (ref bean; allBeans)
        {
            foreach (ref point; bean.arguments)
            {
                if (point.kind != PointKind.bean)
                    continue;
                if (infrastructureTypes.canFind(point.lookup) || hasCandidate(point.lookup))
                    continue;
                const message = "bean `" ~ bean.name ~ "` needs a " ~ point.lookup;
                plan.diagnostics ~= Diagnostic("FLINT-E1106",
                        message ~ ", and no definition in the closure provides one", bean.file, bean.line);
            }
        }
    }

    bool hasCandidate(string type)
    {
        import std.algorithm.searching : canFind;

        foreach (ref bean; allBeans)
        {
            if (bean.types.canFind(type))
                return true;
        }
        return false;
    }

    /// A constructor-injection cycle among unconditional definitions is FLINT-E1110.
    void checkCycles()
    {
        import std.algorithm.searching : canFind;
        import std.array : join;

        size_t[][] edges = new size_t[][allBeans.length];
        foreach (index, ref bean; allBeans)
        {
            if (bean.condition.length)
                continue;
            foreach (type; bean.requires)
            {
                foreach (other, ref provider; allBeans)
                {
                    if (other != index && provider.condition.length == 0 && provider.types.canFind(type))
                        edges[index] ~= other;
                }
            }
        }
        ubyte[] state = new ubyte[allBeans.length];
        size_t[] stack;
        bool visit(size_t node)
        {
            state[node] = 1;
            stack ~= node;
            foreach (next; edges[node])
            {
                if (state[next] == 1)
                {
                    string[] names;
                    bool on;
                    foreach (item; stack)
                    {
                        on = on || item == next;
                        if (on)
                            names ~= allBeans[item].name;
                    }
                    plan.diagnostics ~= Diagnostic("FLINT-E1110",
                            "beans form a constructor-injection cycle: " ~ (names ~ allBeans[next].name)
                                .join(" -> "), allBeans[next].file, allBeans[next].line);
                    return true;
                }
                if (state[next] == 0 && visit(next))
                    return true;
            }
            state[node] = 2;
            stack = stack[0 .. $ - 1];
            return false;
        }

        foreach (node; 0 .. allBeans.length)
        {
            if (state[node] == 0 && visit(node))
                break;
        }
    }

    void describeModule(string name)
    {
        import flint_tool.engine.aot.names : component, configurationProperties, repository;

        const item = model.module_(name);
        if (item is null)
            return;
        foreach (ref decl; item.types)
        {
            auto merged = mergedOf(decl);
            if (merged.has(component))
            {
                webOf(decl, merged);
                listenersOf(decl, merged);
                if (merged.has(configurationProperties))
                    addDescriptor(moduleFor(name), dataDescriptor(decl, merged));
                continue;
            }
            if (decl.kind == "interface" && decl.isA(repository))
            {
                queriesOf(decl);
                continue;
            }
            if (decl.kind == "struct" || decl.kind == "enum" || (decl.kind == "class" && !decl.abstract_))
            {
                if (decl.visibility == "public" || decl.visibility == "export")
                    addDescriptor(moduleFor(name), dataDescriptor(decl, merged));
            }
        }
    }

    DescriptorPlan dataDescriptor(const ref TypeDecl decl, MergedSet merged)
    {
        import flint_tool.engine.aot.merge : merge;
        import flint_tool.engine.aot.names : jsonProperty;

        auto result = descriptorShell(decl, merged);
        if (decl.kind == "enum")
            return result;
        result.create = decl.kind == "struct" ? "init" : defaultConstructible(decl) ? "new" : null;
        foreach (ref field; decl.fields)
        {
            auto fieldMerged = merge(field.annotations, model.annotationTypes);
            const isPublic = field.visibility == "public" || field.visibility == "export";
            if (!isPublic && !fieldMerged.has(jsonProperty))
                continue;
            PropertyPlan property;
            property.name = field.name;
            property.type = field.type.name;
            property.modules = field.type.modules.dup;
            property.annotations = fieldMerged;
            property.access = isPublic ? "field" : "tuple";
            property.field = field.name;
            property.index = field.index;
            property.writable = !mutabilityQualified(field.type.name);
            result.properties ~= property;
        }
        inheritedFields(decl, result);
        accessorProperties(decl, result);
        constructorsOf(decl, result);
        return result;
    }

    /// Public fields of the model base classes (`Owner : Person : BaseEntity`), as Jackson and
    /// BeanPropertyRowMapper see them; nearest class first.
    void inheritedFields(const ref TypeDecl decl, ref DescriptorPlan result)
    {
        import flint_tool.engine.aot.merge : merge;

        foreach (ref supertype; decl.supertypes)
        {
            const base = model.type(supertype.name);
            if (base is null || base.kind != "class")
                continue;
            foreach (ref field; base.fields)
            {
                if (field.visibility != "public" && field.visibility != "export")
                    continue;
                bool known;
                foreach (ref existing; result.properties)
                    known = known || existing.name == field.name;
                if (known)
                    continue;
                PropertyPlan property;
                property.name = field.name;
                property.type = field.type.name;
                property.modules = field.type.modules.dup;
                property.annotations = merge(field.annotations, model.annotationTypes);
                property.access = "field";
                property.field = field.name;
                property.writable = !mutabilityQualified(field.type.name);
                result.properties ~= property;
            }
        }
    }

    /// Creators for message conversion and row mapping: every public constructor, and for a struct without one
    /// (a Java record, rule R11) its field-wise constructor, listed first.
    void constructorsOf(const ref TypeDecl decl, ref DescriptorPlan result)
    {
        import flint_tool.engine.aot.merge : merge;

        const constructors = decl.constructors;
        if (decl.kind == "struct" && constructors.length == 0)
        {
            ConstructorPlan canonical;
            canonical.kind = "literal";
            bool accessible = true;
            foreach (ref field; decl.fields)
            {
                accessible = accessible && (field.visibility == "public" || field.visibility == "export");
                canonical.parameters ~= Parameter(field.name, clone(field.type));
                canonical.parameterAnnotations ~= merge(field.annotations, model.annotationTypes);
            }
            if (accessible)
                result.constructors ~= canonical;
        }
        foreach (ref constructor; constructors)
        {
            if (constructor.visibility != "public" || (decl.kind == "class" && decl.abstract_))
                continue;
            ConstructorPlan item;
            item.kind = decl.kind == "class" ? "class" : "struct";
            item.parameters = clone(constructor.parameters);
            foreach (ref parameter; constructor.parameters)
                item.parameterAnnotations ~= mergedOf(parameter);
            item.annotations = mergedOf(constructor);
            result.constructors ~= item;
        }
    }

    bool defaultConstructible(const ref TypeDecl decl)
    {
        const constructors = decl.constructors;
        if (constructors.length == 0)
            return true;
        foreach (ref constructor; constructors)
        {
            if (constructor.parameters.length == 0 && constructor.visibility == "public")
                return true;
        }
        return false;
    }

    bool mutabilityQualified(string type)
    {
        import std.algorithm.searching : startsWith;

        return type.startsWith("const(") || type.startsWith("immutable(");
    }

    /// Java Beans properties from `getX()`/`isX()` and `setX(v)` pairs.
    void accessorProperties(const ref TypeDecl decl, ref DescriptorPlan result)
    {
        foreach (ref method; decl.methods)
        {
            const property = propertyOfGetter(method);
            if (property.length == 0)
                continue;
            bool known;
            foreach (ref existing; result.properties)
                known = known || existing.name == property;
            if (known)
                continue;
            PropertyPlan item;
            item.name = property;
            item.type = method.returns.name;
            item.modules = method.returns.modules.dup;
            item.annotations = mergedOf(method);
            item.access = "accessor";
            item.getter = method.name;
            const setter = "set" ~ method.name[method.name[0 .. 2] == "is" ? 2 : 3 .. $];
            foreach (ref candidate; decl.methods)
            {
                if (candidate.name == setter && candidate.parameters.length == 1 && candidate.visibility == "public")
                {
                    item.setter = setter;
                    item.writable = true;
                }
            }
            result.properties ~= item;
        }
    }

    /// The property a public, declared, no-argument `getX()` or `isX()` reads, or empty.
    static string propertyOfGetter(const ref Method method)
    {
        import std.ascii : isUpper, toLower;

        if (method.static_ || method.visibility != "public" || method.parameters.length != 0
                || method.returns.name == "void")
            return null;
        foreach (prefix; ["get", "is"])
        {
            if (method.name.length > prefix.length && method.name[0 .. prefix.length] == prefix
                    && isUpper(method.name[prefix.length]))
            {
                const property = toLower(method.name[prefix.length]) ~ method.name[prefix.length + 1 .. $];
                return property == "class" ? null : property;
            }
        }
        return null;
    }

    string beanNameOf(const ref TypeDecl decl)
    {
        foreach (ref bean; allBeans)
        {
            if (bean.className == decl.fqn && bean.method.length == 0)
                return bean.name;
        }
        return null;
    }

    void webOf(const ref TypeDecl decl, MergedSet merged)
    {
        import flint_tool.engine.aot.names : controller, controllerAdvice, exceptionHandler, requestMapping;

        const bean = beanNameOf(decl);
        if (bean.length == 0)
            return;
        const isController = merged.has(controller);
        const isAdvice = merged.has(controllerAdvice);
        if (!isController && !isAdvice)
            return;
        auto target = &moduleFor(decl.module_);
        // The class's descriptor may already exist: a proxied controller's advised methods are in it.
        addDescriptor(*target, descriptorShell(decl, merged));
        auto descriptor = descriptorIn(*target, decl.fqn);
        foreach (ref method; decl.methods)
        {
            if (method.inherited || method.name == "__ctor" || method.static_)
                continue;
            auto methodMerged = hierarchyMerged(decl, method);
            if (isController && methodMerged.has(requestMapping))
            {
                auto handler = handlerOf(decl, bean, method, methodMerged, merged);
                handler.index = methodIndex(*descriptor, method);
                if (handler.index == descriptor.methods.length)
                    descriptor.methods ~= methodPlan(method, methodMerged, MergedSet.init);
                foreach (index; 0 .. method.parameters.length)
                    descriptor.methods[handler.index].parameters[index] = hierarchyMerged(decl, method, index);
                target.handlers ~= handler;
            }
            else if (methodMerged.has(exceptionHandler))
                target.exceptionHandlers ~= exceptionHandlerOf(decl, bean, method, methodMerged, merged, isAdvice);
        }
        foreach (ref item; target.beans)
        {
            if (item.name == bean && descriptor.methods.length)
                item.described = true;
        }
    }

    /// The module's descriptor of `type`.
    static DescriptorPlan* descriptorIn(ref ModulePlan target, string type)
    {
        foreach (ref existing; target.descriptors)
        {
            if (existing.type == type)
                return &existing;
        }
        assert(false, "descriptor added just before");
    }

    /// The position of `method` in the descriptor's methods, or the length when absent.
    static size_t methodIndex(const ref DescriptorPlan descriptor, const ref Method method)
    {
        foreach (index, ref existing; descriptor.methods)
        {
            if (existing.method.name == method.name && parameterTypes(existing.method) == parameterTypes(method))
                return index;
        }
        return descriptor.methods.length;
    }

    HandlerPlan handlerOf(const ref TypeDecl decl, string bean, const ref Method method,
            const ref MergedSet merged, const ref MergedSet classMerged)
    {
        import flint_tool.engine.aot.names : requestMapping, responseBody, responseStatus;

        import flint_tool.engine.aot.merge : cloneMerged = clone;

        const classMapping = classMerged.get(requestMapping);
        HandlerPlan handler;
        handler.typeAnnotations = cloneMerged(classMerged);
        handler.bean = bean;
        handler.className = decl.fqn;
        handler.method = clone(method);
        handler.source = location(method.file, method.line);
        const mapping = merged.get(requestMapping);
        handler.paths = combinePaths(classMapping is null ? null : pathsOf(*classMapping), pathsOf(*mapping));
        foreach (ref item; mapping.get("method").items)
            handler.methods ~= item.text;
        if (handler.methods.length == 0 && classMapping !is null)
        {
            foreach (ref item; classMapping.get("method").items)
                handler.methods ~= item.text;
        }
        handler.params = mapping.get("params").strings;
        handler.headers = mapping.get("headers").strings;
        handler.consumes = mapping.get("consumes").strings;
        handler.produces = mapping.get("produces").strings;
        if (classMapping !is null)
        {
            if (handler.consumes.length == 0)
                handler.consumes = classMapping.get("consumes").strings;
            if (handler.produces.length == 0)
                handler.produces = classMapping.get("produces").strings;
        }
        handler.responseBody = merged.has(responseBody) || classMerged.has(responseBody);
        if (const status = merged.get(responseStatus))
        {
            handler.status = statusCode(*status);
            handler.reason = status.text("reason");
        }
        foreach (index, ref parameter; method.parameters)
        {
            handler.arguments ~= argumentOf(parameter, hierarchyMerged(decl, method, index), false);
            handler.arguments[$ - 1].modules = modulesOf(parameter.type);
            containerArgument(decl, parameter.type);
        }
        return handler;
    }

    /// A handler argument typed `Optional!T`, `List!T`, `Set!T` or an array is converted by the binder through
    /// its descriptor (`wrap`, `fromElements`): register `descriptorOf` for it, as for bound properties.
    void containerArgument(const ref TypeDecl decl, const ref TypeRef type)
    {
        import std.algorithm.searching : canFind, endsWith;

        if (type.name == "string" || !(type.name.canFind("!(") || type.name.endsWith("[]")))
            return;
        auto target = &moduleFor(decl.module_);
        if (target.containerDescriptors.canFind(type.name))
            return;
        target.containerDescriptors ~= type.name;
        target.containerModules ~= modulesOf(type);
    }

    long statusCode(const ref imported!"flint_tool.engine.aot.model".Annotation status)
    {
        import flint_tool.engine.aot.model : Value;

        foreach (name; ["value", "code"])
        {
            const value = status.get(name);
            if (value.kind == Value.Kind.integer && value.integer)
                return value.integer;
        }
        return 0;
    }

    string[] pathsOf(const ref imported!"flint_tool.engine.aot.model".Annotation mapping)
    {
        auto paths = mapping.get("path").strings;
        return paths.length ? paths : mapping.get("value").strings;
    }

    ExceptionPlan exceptionHandlerOf(const ref TypeDecl decl, string bean, const ref Method method,
            const ref MergedSet merged, const ref MergedSet classMerged, bool advice)
    {
        import flint_tool.engine.aot.names : controllerAdvice, exceptionHandler, responseBody, responseStatus;

        ExceptionPlan handler;
        handler.bean = bean;
        handler.className = decl.fqn;
        handler.method = clone(method);
        handler.advice = advice;
        handler.source = location(method.file, method.line);
        handler.exceptionTypes = merged.get(exceptionHandler).get("value").strings;
        handler.produces = merged.get(exceptionHandler).get("produces").strings;
        if (advice)
        {
            const selectors = classMerged.get(controllerAdvice);
            handler.basePackages = selectors.get("basePackages").strings ~ selectors.get("value").strings;
            handler.assignableTypes = selectors.get("assignableTypes").strings;
            handler.adviceAnnotations = selectors.get("annotations").strings;
        }
        handler.responseBody = merged.has(responseBody) || classMerged.has(responseBody);
        if (const status = merged.get(responseStatus))
            handler.status = statusCode(*status);
        foreach (ref parameter; method.parameters)
        {
            const isException = isExceptionType(parameter.type.name);
            handler.arguments ~= argumentOf(parameter, mergedOf(parameter), isException);
            if (isException && handler.exceptionTypes.length == 0)
                handler.exceptionTypes ~= parameter.type.name;
        }
        return handler;
    }

    bool isExceptionType(string type)
    {
        if (type == "object.Exception" || type == "object.Throwable")
            return true;
        if (const decl = model.type(type))
            return decl.isA("object.Exception");
        return type.length > 9 && type[$ - 9 .. $] == "Exception";
    }

    ArgumentPlan argumentOf(const ref Parameter parameter, MergedSet merged, bool exception)
    {
        import flint_tool.engine.aot.names : cookieValue, modelAttribute, pathVariable, requestBody,
            requestHeader, requestParam, valid, validated;

        ArgumentPlan argument;
        argument.name = parameter.name;
        argument.type = parameter.type.name;
        argument.annotations = merged;
        argument.validate = merged.hasAny([valid, validated]);
        argument.exception = exception;
        argument.required = true;
        if (parameter.type.element.length)
            argument.elementType = parameter.type.element[0].name;
        else if (parameter.type.arguments.length)
            argument.elementType = parameter.type.arguments[0].name;
        static immutable string[2][] bindings = [
            [pathVariable, "pathVariable"], [requestParam, "requestParam"],
            [requestHeader, "requestHeader"], [cookieValue, "cookieValue"],
            [requestBody, "requestBody"], [modelAttribute, "modelAttribute"]
        ];
        foreach (binding; bindings)
        {
            const annotation = merged.get(binding[0]);
            if (annotation is null)
                continue;
            argument.kind = binding[1];
            const named = annotation.text("name").length ? annotation.text("name") : annotation.text("value");
            if (named.length && binding[1] != "requestBody")
                argument.name = named;
            argument.required = annotation.flag("required", true);
            const defaultValue = annotation.get("defaultValue");
            // ValueConstants.DEFAULT_NONE is whatever the annotation declares as the attribute's default.
            const type = binding[0] in model.annotationTypes;
            const declared = type is null ? null : type.field("defaultValue");
            const unset = declared is null || defaultValue.same(declared.default_);
            if (defaultValue.kind == imported!"flint_tool.engine.aot.model".Value.Kind.text && !unset)
            {
                argument.defaultValue = defaultValue.text;
                argument.hasDefault = true;
                argument.required = false;
            }
            return argument;
        }
        if (exception || resolvedByTypeName(parameter.type.name))
            argument.kind = "byType";
        else if (simpleType(parameter.type))
        {
            argument.kind = "requestParam";
            argument.required = false;
        }
        else
            argument.kind = "modelAttribute";
        return argument;
    }

    bool resolvedByTypeName(string type)
    {
        import flint_tool.engine.aot.merge : shortName;
        import flint_tool.engine.aot.names : resolvedByType;
        import std.algorithm.searching : canFind;

        return resolvedByType.canFind(shortName(type));
    }

    bool simpleType(const ref TypeRef type)
    {
        import std.algorithm.searching : canFind;

        if (type.kind == "enum")
            return true;
        if (type.element.length)
            return simpleType(type.element[0]);
        return [
            "bool", "byte", "ubyte", "short", "ushort", "int", "uint", "long", "ulong", "float",
            "double", "char", "string"
        ].canFind(type.name);
    }

    void listenersOf(const ref TypeDecl decl, const ref MergedSet merged)
    {
        import flint_tool.engine.aot.names : eventListener, order;

        const bean = beanNameOf(decl);
        if (bean.length == 0)
            return;
        foreach (ref method; decl.methods)
        {
            if (method.inherited)
                continue;
            const methodMerged = mergedOf(method);
            const annotation = methodMerged.get(eventListener);
            if (annotation is null)
                continue;
            // Spring's resolveDeclaredEventTypes: the declared classes, else the single parameter's type.
            auto classes = annotation.get("classes").strings;
            if (classes.length == 0)
                classes = annotation.get("value").strings;
            const parameters = method.parameters.length;
            if (method.visibility != "public" || parameters > 1 || (parameters == 0 && classes.length == 0))
            {
                error("FLINT-E1108", "@EventListener method " ~ decl.name ~ "." ~ method.name ~ " must be public "
                        ~ "and take at most one parameter, the event, or name its event classes",
                        method.file, method.line);
                continue;
            }
            ListenerPlan listener;
            listener.bean = bean;
            listener.className = decl.fqn;
            listener.method = method.name;
            listener.parameterType = parameters ? method.parameters[0].type.name : null;
            listener.eventTypes = classes.length ? classes.dup : [listener.parameterType];
            listener.returnType = method.returns.name;
            listener.condition = annotation.text("condition");
            if (listener.condition.length)
                listener.conditionMethod = [clone(method)];
            if (const ordered = methodMerged.get(order))
                listener.order = ordered.get("value").integer;
            moduleFor(decl.module_).listeners ~= listener;
        }
    }

    void queriesOf(const ref TypeDecl decl)
    {
        import flint_tool.engine.aot.names : query, repository;
        import flint_tool.engine.aot.query : deriveQuery, QueryError;

        const(TypeRef)* base;
        foreach (ref supertype; decl.supertypes)
        {
            if (supertype.template_.length && supertype.arguments.length == 2 && base is null)
                base = &supertype;
        }
        if (base is null)
            return;
        const domainDecl = model.type(base.arguments[0].name);
        if (domainDecl is null)
            return;
        auto domain = domainOf(*domainDecl);
        auto target = &moduleFor(decl.module_);
        target.consulted ~= domainDecl.module_;
        foreach (ref method; decl.methods)
        {
            if (method.inherited || mergedOf(method).has(query))
                continue;
            string[] parameters;
            foreach (ref parameter; method.parameters)
                parameters ~= parameter.name;
            imported!"flint_tool.engine.aot.query".DerivedQuery derived;
            QueryError failure;
            if (!deriveQuery(method.name, method.returns.name, parameters, domain, derived, failure))
            {
                error(failure.code, failure.message, method.file, method.line);
                continue;
            }
            target.queries ~= QueryPlan(decl.fqn, domainDecl.fqn, derived, location(method.file, method.line));
        }
    }

    imported!"flint_tool.engine.aot.query".Domain domainOf(const ref TypeDecl decl)
    {
        import flint_tool.engine.aot.merge : merge;
        import flint_tool.engine.aot.names : column, table, transient;
        import flint_tool.engine.aot.query : Column, Domain, snakeCase;

        Domain domain;
        domain.type = decl.fqn;
        domain.name = decl.name;
        const typeMerged = mergedOf(decl);
        const tableName = typeMerged.get(table);
        domain.table = tableName !is null && tableName.text("value").length
            ? tableName.text("value") : snakeCase(decl.name);
        foreach (ref field; decl.fields)
        {
            auto merged = merge(field.annotations, model.annotationTypes);
            if (merged.has(transient))
                continue;
            const named = merged.get(column);
            const columnName = named !is null && named.text("value").length ? named.text(
                    "value") : snakeCase(field.name);
            domain.columns ~= Column(field.name, columnName, field.type.kind == "struct" || field.type.kind == "class");
        }
        return domain;
    }
}

/// What `@Value("#{...}")` sees: beans by name, placeholders, and the members of model types.
private final class ValueScope : imported!"flint_tool.engine.aot.spel".SpelScope
{
    import flint_tool.engine.aot.spel : Compiled;

    private Analysis analysis;
    string[] modules;

    this(Analysis analysis)
    {
        this.analysis = analysis;
    }

    bool variable(string, out Compiled)
    {
        return false;
    }

    bool bean(string name, out Compiled result)
    {
        import flint_tool.engine.aot.conditions : literal;
        import flint_tool.engine.aot.names : packageOf;

        foreach (ref item; analysis.allBeans)
        {
            if (item.name != name)
                continue;
            if (const decl = analysis.model.type(item.type))
                modules ~= decl.module_;
            else
                modules ~= packageOf(item.type);
            result = Compiled("(cast(" ~ item.type ~ ") factory.getBean(" ~ literal(name) ~ "))", item.type);
            return true;
        }
        return false;
    }

    Compiled placeholder(string expression)
    {
        import flint_tool.engine.aot.conditions : literal;

        return Compiled("factory.resolveValue(" ~ literal(expression) ~ ", \"string\").get!(string)()", "string");
    }

    bool root(string, Compiled[], bool, out Compiled)
    {
        return false;
    }

    bool member(string type, string name, Compiled[] arguments, bool call, string target, out Compiled result)
    {
        return memberOf(analysis.model, type, name, arguments, call, target, result, modules);
    }
}

/// A model type's member for SpEL: a public field, a Java Beans getter's property, or a public method.
bool memberOf(const imported!"flint_tool.engine.aot.model".Model model, string type, string name,
        imported!"flint_tool.engine.aot.spel".Compiled[] arguments, bool call, string target,
        out imported!"flint_tool.engine.aot.spel".Compiled result, ref string[] modules)
{
    import flint_tool.engine.aot.spel : Compiled;

    const decl = model.type(type);
    if (decl is null)
        return false;
    if (!call)
    {
        foreach (ref field; decl.fields)
        {
            if (field.name == name && (field.visibility == "public" || field.visibility == "export"))
            {
                modules ~= field.type.modules;
                result = Compiled("(" ~ target ~ ")." ~ name, field.type.name);
                return true;
            }
        }
    }
    return methodOf(*decl, name, arguments, call, target, result, modules);
}

private bool methodOf(const ref TypeDecl decl, string name, imported!"flint_tool.engine.aot.spel".Compiled[] arguments,
        bool call, string target, out imported!"flint_tool.engine.aot.spel".Compiled result, ref string[] modules)
{
    import std.array : join;
    import std.ascii : toUpper;
    import flint_tool.engine.aot.spel : Compiled, convert;

    const capital = name.length ? toUpper(name[0]) ~ name[1 .. $] : null;
    foreach (ref method; decl.methods)
    {
        const wanted = call ? method.name == name : (method.name == "get" ~ capital || method.name == "is" ~ capital);
        if (!wanted || method.visibility != "public" || method.static_ || method.parameters.length != arguments.length)
            continue;
        string[] converted;
        foreach (index, ref parameter; method.parameters)
            converted ~= convert(arguments[index], parameter.type.name);
        modules ~= method.returns.modules;
        result = Compiled("(" ~ target ~ ")." ~ method.name ~ "(" ~ converted.join(", ") ~ ")", method.returns.name);
        return true;
    }
    return false;
}

/// What method-level SpEL sees (aot-contract.md section 9.1): the arguments typed from the signature, the
/// result, `#root.methodName`, beans, placeholders, and the security root's functions as runtime calls.
private final class MethodScope : imported!"flint_tool.engine.aot.spel".SpelScope
{
    import flint_tool.engine.aot.spel : Compiled;

    private Analysis analysis;
    private const(Method) method;
    string[] modules;

    this(Analysis analysis, const ref Method method)
    {
        this.analysis = analysis;
        this.method = method;
    }

    bool variable(string name, out Compiled result)
    {
        import std.conv : ConvException, to;

        foreach (index, ref parameter; method.parameters)
        {
            const positional = "p" ~ index.to!string;
            if (parameter.name == name || name == positional || name == "a" ~ index.to!string)
            {
                modules ~= parameter.type.modules;
                result = Compiled("context.argument(" ~ index.to!string ~ ").get!(" ~ parameter.type.name ~ ")()",
                        parameter.type.name);
                return true;
            }
        }
        if (name == "result" && method.returns.name != "void")
        {
            modules ~= method.returns.modules;
            result = Compiled("context.result().get!(" ~ method.returns.name ~ ")()", method.returns.name);
            return true;
        }
        if (name == "root")
        {
            result = Compiled("context", "flint.engine.aot.expression.EvaluationContext");
            return true;
        }
        return false;
    }

    bool bean(string name, out Compiled result)
    {
        import flint_tool.engine.aot.conditions : literal;

        foreach (ref item; analysis.allBeans)
        {
            if (item.name != name)
                continue;
            if (const decl = analysis.model.type(item.type))
                modules ~= decl.module_;
            result = Compiled("(cast(" ~ item.type ~ ") context.bean(" ~ literal(name) ~ "))", item.type);
            return true;
        }
        return false;
    }

    Compiled placeholder(string expression)
    {
        import flint_tool.engine.aot.conditions : literal;

        return Compiled("context.placeholder(" ~ literal(expression) ~ ")", "string");
    }

    bool root(string name, Compiled[] arguments, bool call, out Compiled result)
    {
        import std.algorithm.searching : canFind;
        import std.array : join;
        import flint_tool.engine.aot.conditions : literal;

        static immutable string[] functions = [
            "hasRole", "hasAnyRole", "hasAuthority", "hasAnyAuthority", "isAuthenticated",
            "isAnonymous", "isRememberMe", "isFullyAuthenticated", "permitAll", "denyAll",
            "hasPermission"
        ];
        static immutable string[] properties = ["principal", "authentication"];
        if (call && functions.canFind(name))
        {
            string[] boxed;
            foreach (ref argument; arguments)
                boxed ~= argument.type == "Any" ? argument.code : "Any.of(" ~ argument.code ~ ")";
            result = Compiled("context.rootFunction(" ~ literal(name) ~ ", [" ~ boxed.join(", ") ~ "])", "Any");
            return true;
        }
        if (!call && properties.canFind(name))
        {
            result = Compiled("context.rootProperty(" ~ literal(name) ~ ")", "Any");
            return true;
        }
        return false;
    }

    bool member(string type, string name, Compiled[] arguments, bool call, string target, out Compiled result)
    {
        // A member of a root property (`authentication.name`, `principal.getUsername()`) is a longer root path
        // the runtime resolves: contract 3's rootProperty takes dotted names.
        enum prefix = `context.rootProperty("`;
        if (type == "Any" && target.length > prefix.length && target[0 .. prefix.length] == prefix
                && arguments.length == 0)
        {
            import std.ascii : toLower;
            import flint_tool.engine.aot.conditions : literal;

            const path = target[prefix.length .. $ - 2];
            string property = name;
            if (call && name.length > 3 && name[0 .. 3] == "get")
                property = toLower(name[3]) ~ name[4 .. $];
            else if (call)
                return false;
            result = Compiled("context.rootProperty(" ~ literal(path ~ "." ~ property) ~ ")", "Any");
            return true;
        }
        if (type == "flint.engine.aot.expression.EvaluationContext")
        {
            if (name != "methodName" || call)
                return false;
            result = Compiled("context.methodName()", "string");
            return true;
        }
        return memberOf(analysis.model, type, name, arguments, call, target, result, modules);
    }
}

/// Parameter types of a method, comma-separated, for overload identity.
string parameterTypes(const ref Method method)
{
    import std.array : join;

    string[] types;
    foreach (ref parameter; method.parameters)
        types ~= parameter.type.name;
    return types.join(",");
}

/// Combine class-level and method-level paths with Spring's `PathPattern` rules.
string[] combinePaths(const string[] classPaths, const string[] methodPaths)
{
    if (classPaths.length == 0)
        return methodPaths.length ? methodPaths.dup : [""];
    if (methodPaths.length == 0)
        return classPaths.dup;
    string[] result;
    foreach (left; classPaths)
    {
        foreach (right; methodPaths)
            result ~= combine(left, right);
    }
    return result;
}

private string combine(string left, string right)
{
    if (left.length == 0)
        return right;
    if (right.length == 0)
        return left;
    const leftSlash = left[$ - 1] == '/';
    const rightSlash = right[0] == '/';
    if (leftSlash && rightSlash)
        return left ~ right[1 .. $];
    if (!leftSlash && !rightSlash)
        return left ~ "/" ~ right;
    return left ~ right;
}
