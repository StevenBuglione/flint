module flint_tool.api.java_test;

import flint_tool.api.java : Member, MemberKind, TypeDecl, TypeKind, Unit, eraseType, erasedParameterType, parseJava;
import flint.test : expect;

@safe:

private const(TypeDecl)* type(const ref Unit unit, string name)
{
    foreach (ref decl; unit.types)
    {
        if (decl.name == name)
            return &decl;
    }
    return null;
}

private string[] signatures(const TypeDecl* decl)
{
    string[] found;
    foreach (ref member; decl.members)
        found ~= member.signature;
    return found;
}

private const(Member)* member(const TypeDecl* decl, string signature)
{
    foreach (ref item; decl.members)
    {
        if (item.signature == signature)
            return &item;
    }
    return null;
}

@("a class lists its public and protected members, not private or package-private ones")
unittest
{
    const unit = parseJava(`
package org.example.jdbc;

import java.util.List;
import static java.util.Objects.requireNonNull;

/** A template. */
@SuppressWarnings("unchecked")
public class JdbcTemplate<T extends Comparable<? super T>> extends JdbcAccessor implements JdbcOperations, Cloneable {
    public static final int DEFAULT = 1, OTHER = 2;
    protected String name = "a { b";
    private int hidden;
    int packagePrivate;
    static { System.out.println("}"); }
    { char c = '}'; }

    public JdbcTemplate() { }
    protected JdbcTemplate(DataSource dataSource, boolean lazy) throws SQLException { this.x = '{'; }
    private JdbcTemplate(int x) { }

    public <R> List<R> query(String sql, RowMapper<R> rowMapper, @Nullable Object... args) throws DataAccessException {
        return null;
    }
    protected final void setName(final String name) { this.name = name; }
    void notVisible() { }
    public abstract int[] batchUpdate(String @Nullable [] sql);
}
`);
    expect(unit.error).toEqual("");
    expect(unit.package_).toEqual("org.example.jdbc");
    expect(unit.types.length).toEqual(1);
    const decl = type(unit, "JdbcTemplate");
    expect(decl.id).toEqual("org.example.jdbc.JdbcTemplate");
    expect(decl.kind).toEqual(TypeKind.class_);
    expect(decl.annotations).toEqual([`@SuppressWarnings("unchecked")`]);
    expect(decl.typeParameters).toEqual(["T extends Comparable<? super T>"]);
    expect(decl.extends_).toEqual(["JdbcAccessor"]);
    expect(decl.implements_).toEqual(["JdbcOperations", "Cloneable"]);
    expect(signatures(decl)).toEqual([
        "DEFAULT", "OTHER", "name", "<init>()", "<init>(DataSource,boolean)",
        "query(String,RowMapper,Object...)", "setName(String)", "batchUpdate(String[])"
    ]);
    const query = member(decl, "query(String,RowMapper,Object...)");
    expect(query.typeParameters).toEqual(["R"]);
    expect(query.type).toEqual("List<R>");
    expect(query.parameters).toEqual([
        "String sql", "RowMapper<R> rowMapper", "@Nullable Object... args"
    ]);
    expect(query.throws_).toEqual(["DataAccessException"]);
    expect(member(decl, "<init>(DataSource,boolean)").visibility).toEqual("protected");
    expect(member(decl, "setName(String)").modifiers).toEqual(["final"]);
    expect(member(decl, "DEFAULT").modifiers).toEqual(["static", "final"]);
    expect(member(decl, "batchUpdate(String[])").parameters).toEqual(["String @Nullable [] sql"]);
}

@("interface members are implicitly public; nested types follow their own and their outer's visibility")
unittest
{
    const unit = parseJava(`
package p;
public interface Operations {
    String NAME = "ops";
    <T> T execute(Callback<T> action);
    default void close() { }
    static Operations of() { return null; }
    private void helper() { }
    interface Callback<T> { T call(); }
    class Holder { public Holder(int x) { } }
}
class PackagePrivate {
    public void hidden() { }
    public static class AlsoHidden { }
}
`);
    expect(unit.error).toEqual("");
    expect(unit.types.length).toEqual(3);
    const ops = type(unit, "Operations");
    expect(ops.kind).toEqual(TypeKind.interface_);
    expect(signatures(ops)).toEqual(["NAME", "execute(Callback)", "close()", "of()"]);
    expect(member(ops, "close()").modifiers).toEqual(["default"]);
    expect(member(ops, "NAME").visibility).toEqual("public");
    expect(type(unit, "Operations.Callback").visibility).toEqual("public");
    expect(signatures(type(unit, "Operations.Holder"))).toEqual(["<init>(int)"]);
    expect(type(unit, "PackagePrivate") is null).toEqual(true);
    expect(type(unit, "PackagePrivate.AlsoHidden") is null).toEqual(true);
}

@("classes without constructors get the implicit default one; nested private types are left out")
unittest
{
    const unit = parseJava(`
package p;
public abstract class Base {
    protected static class Shared { }
    private static class Secret { public void x() { } }
    public class Inner { }
}
`);
    expect(unit.error).toEqual("");
    const base = type(unit, "Base");
    expect(signatures(base)).toEqual(["<init>()"]);
    expect(base.members[0].implicit_).toEqual(true);
    expect(base.modifiers).toEqual(["abstract"]);
    expect(type(unit, "Base.Shared").visibility).toEqual("protected");
    expect(signatures(type(unit, "Base.Shared"))).toEqual(["<init>()"]);
    expect(type(unit, "Base.Secret") is null).toEqual(true);
    expect(type(unit, "Base.Inner") !is null).toEqual(true);
}

@("enums list constants, skipping their arguments and bodies, then members")
unittest
{
    const unit = parseJava(`
package p;
public enum HttpStatus implements Series {
    @Deprecated
    CONTINUE(100, "Continue") {
        @Override public String reason() { return "}"; }
    },
    OK(200, "OK"),
    ;
    private final int value;
    HttpStatus(int value, String reason) { this.value = value; }
    public int value() { return value; }
    public enum Kind { A, B }
}
`);
    expect(unit.error).toEqual("");
    const status = type(unit, "HttpStatus");
    expect(status.kind).toEqual(TypeKind.enum_);
    expect(signatures(status)).toEqual(["CONTINUE", "OK", "value()"]);
    expect(status.members[0].kind).toEqual(MemberKind.constant);
    expect(status.members[0].annotations).toEqual(["@Deprecated"]);
    expect(signatures(type(unit, "HttpStatus.Kind"))).toEqual(["A", "B"]);
}

@("records list components and their canonical constructor, explicit, compact or implicit")
unittest
{
    const unit = parseJava(`
package p;
public record Point(int x, @Nullable String label) implements Shape {
    public Point { Objects.requireNonNull(label); }
    public Point(int x) { this(x, null); }
    public static Point origin() { return new Point(0); }
}
public record Pair<A, B>(A first, B second) { }
`);
    expect(unit.error).toEqual("");
    const point = type(unit, "Point");
    expect(point.kind).toEqual(TypeKind.record);
    expect(signatures(point)).toEqual([
        "x", "label", "<init>(int,String)", "<init>(int)", "origin()"
    ]);
    expect(point.members[1].annotations).toEqual(["@Nullable"]);
    expect(member(point, "<init>(int,String)").implicit_).toEqual(false);
    const pair = type(unit, "Pair");
    expect(pair.typeParameters).toEqual(["A", "B"]);
    expect(signatures(pair)).toEqual(["first", "second", "<init>(A,B)"]);
    expect(member(pair, "<init>(A,B)").implicit_).toEqual(true);
}

@("annotation types list attributes with types and defaults")
unittest
{
    const unit = parseJava(`
package p;
@Target({ElementType.TYPE, ElementType.METHOD})
@Retention(RetentionPolicy.RUNTIME)
@Documented
public @interface RequestMapping {
    String NAME = "mapping";
    @AliasFor("path")
    String[] value() default {};
    RequestMethod[] method() default {};
    int timeout() default -1;
    Class<?> type() default Object.class;
    String name();
    enum Mode { STRICT }
}
`);
    expect(unit.error).toEqual("");
    const mapping = type(unit, "RequestMapping");
    expect(mapping.kind).toEqual(TypeKind.annotation);
    expect(mapping.annotations).toEqual([
        "@Target({ElementType.TYPE, ElementType.METHOD})", "@Retention(RetentionPolicy.RUNTIME)",
        "@Documented"
    ]);
    expect(signatures(mapping)).toEqual(["NAME", "value", "method", "timeout", "type", "name"]);
    const value = member(mapping, "value");
    expect(value.kind).toEqual(MemberKind.attribute);
    expect(value.type).toEqual("String[]");
    expect(value.defaultValue).toEqual("{}");
    expect(value.annotations).toEqual([`@AliasFor("path")`]);
    expect(member(mapping, "timeout").defaultValue).toEqual("-1");
    expect(member(mapping, "type").defaultValue).toEqual("Object.class");
    expect(member(mapping, "name").defaultValue).toEqual("");
    expect(type(unit, "RequestMapping.Mode") !is null).toEqual(true);
}

@("initializers with generic commas, lambdas, anonymous classes and text blocks are skipped whole")
unittest
{
    const unit = parseJava(`
package p;
public final class Tricky {
    public static final Map<String, List<Integer>> TABLE = new HashMap<String, List<Integer>>(), EMPTY = Map.of();
    public final Runnable task = () -> { if (a < b && c > d) { run(); } };
    public final Object anonymous = new Object() { public String toString() { return "{"; } };
    public static final String QUERY = """
        SELECT "}" FROM t WHERE x = '{'
        """;
    public static final long MASK = 0x7FFF_FFFFL >>> 1, OTHER = 1.5e-3 > 0 ? 1 : 0;
    public int[] matrix[];
    public sealed interface Shape permits Circle, Square { }
    public non-sealed class Circle implements Shape { }
    public java.util.@Nullable List<? extends Number> numbers() { return null; }
    public <T extends @Nullable Object> T first(T... items) { return items[0]; }
}
`);
    expect(unit.error).toEqual("");
    const tricky = type(unit, "Tricky");
    expect(signatures(tricky)).toEqual([
        "<init>()", "TABLE", "EMPTY", "task", "anonymous", "QUERY", "MASK", "OTHER", "matrix",
        "numbers()", "first(T...)"
    ]);
    expect(member(tricky, "TABLE").type).toEqual("Map<String, List<Integer>>");
    expect(member(tricky, "EMPTY").type).toEqual("Map<String, List<Integer>>");
    expect(member(tricky, "matrix").type).toEqual("int[][]");
    expect(member(tricky, "numbers()").type).toEqual("java.util.@Nullable List<? extends Number>");
    expect(member(tricky, "first(T...)").typeParameters).toEqual(["T extends @Nullable Object"]);
    const shape = type(unit, "Tricky.Shape");
    expect(shape.modifiers).toEqual(["sealed"]);
    expect(shape.permits).toEqual(["Circle", "Square"]);
    expect(type(unit, "Tricky.Circle").modifiers).toEqual(["non-sealed"]);
}

@("an unbalanced body is reported with its line, not silently truncated")
unittest
{
    const unit = parseJava("package p;\npublic class Broken {\n    public void f() {\n");
    expect(unit.error.length > 0).toEqual(true);
    expect(unit.errorLine).toEqual(4);
    const garbage = parseJava("package p;\npublic class X { public int = 3; }\n");
    expect(garbage.error).toEqual("expected a name, found `=`");
    expect(garbage.errorLine).toEqual(2);
}

@("erasure drops annotations, type arguments and parameter names")
unittest
{
    expect(eraseType("Map<String, List<Integer>>")).toEqual("Map");
    expect(eraseType("@Nullable Outer<T>.Inner<U>[]")).toEqual("Outer.Inner[]");
    expect(eraseType(`java.lang.@Size(max = 3) String`)).toEqual("java.lang.String");
    expect(erasedParameterType("@Nullable Object @Nullable ... args")).toEqual("Object...");
}
