"""Check skeleton mode: declarations, mechanical bodies, marked bodies, pending members, R3 defaults, R11, R24,
rows, imports, the API comparison, and that a skeleton compiles and fails loudly at a marked body on DMD and LDC."""

import collections
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from test_annotations import HELPER

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import skeletons  # noqa: E402
import porter_gate  # noqa: E402
from accessors import Unsupported  # noqa: E402

COUNTER = """package org.springframework.example;

import java.util.List;
import org.jspecify.annotations.Nullable;

/**
 * Counts things for {@link Marker} users.
 */
public abstract class Counter implements Marker {

    /** The default step. */
    public static final int STEP = 2;

    private static final long serialVersionUID = 1L;

    protected final String name;

    private int count;

    private @Nullable String label;

    /** Create a counter. */
    public Counter(String name) { this.name = name; }

    public Counter(String name, int start) { this(name); this.count = Math.max(start, 0); }

    public int getCount() { return this.count; }

    public void setLabel(@Nullable String label) { this.label = label; }

    /**
     * Add the step.
     * @return the new count
     */
    public int increment() throws IllegalStateException { this.count += STEP; return this.count; }

    protected abstract void reset(List<String> reasons);

    public static Counter of(String name) { return new Counter(name); }

    public <T> T convert(Class<T> type) { return null; }

    public void log(String... parts) { }

    @Override
    public boolean equals(Object other) { return this == other; }

    @Override
    public int hashCode() { return this.count; }

    @Override
    public String toString() { return this.name; }

    public static class Snapshot { }
}
"""

MARKER = """package org.springframework.example;

import org.jspecify.annotations.Nullable;

public interface Marker {

    int LIMIT = 10;

    String getName();

    default @Nullable String describe() { return getName(); }

    static Marker none() { return null; }
}
"""

FAILURE = """package org.springframework.example;

import org.jspecify.annotations.Nullable;

public class CountFailure extends RuntimeException {

    private final int count;

    public CountFailure(@Nullable String msg, int count) { super(msg); this.count = count; }

    public CountFailure(int count) { super("count " + count); this.count = count; }

    public int getCount() { return this.count; }
}
"""


# The landed D base's constructors, as the describe probe lists them (R8's file, line family).
RUNTIME_EXCEPTION = [['string msg', 'string file = __FILE__', 'ulong line = cast(ulong)__LINE__',
                      'Throwable nextInChain = null']]

RUNTIME_EXCEPTION_D = '''
class RuntimeException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) pure nothrow
    {
        super(msg, file, line, nextInChain);
    }
}
'''


class FakeUniverse:
    def __init__(self):
        manifest = [
            {'id': 'org.springframework.example.Marker', 'kind': 'interface', 'members': [
                {'kind': 'method', 'name': 'describe', 'signature': 'describe()', 'modifiers': ['default']}]},
            {'id': 'org.springframework.example.Counter', 'kind': 'class', 'members': []},
            {'id': 'org.springframework.example.CountFailure', 'kind': 'class', 'extends': ['RuntimeException'],
             'members': []},
        ]
        for t in manifest:
            t['package'] = 'org.springframework.example'
        self.types = {t['id']: ('example', '1', t) for t in manifest}
        for name, extends in (('java.lang.String', None), ('java.lang.Object', None), ('java.util.List', None),
                              ('java.lang.Class', None), ('java.lang.Math', None), ('java.lang.Throwable', None),
                              ('java.lang.Exception', 'Throwable'), ('java.lang.RuntimeException', 'Exception'),
                              ('java.lang.IllegalStateException', 'RuntimeException')):
            self.types[name] = ('jdk', '1', {'id': name, 'kind': 'class', 'package': name.rsplit('.', 1)[0],
                                             'extends': [extends] if extends else [], 'members': []})
        self.rows = {f'org.springframework.example.{n}': {'status': 'ported', 'd': f'flint.example.{n}'}
                     for n in ('Marker', 'Counter', 'CountFailure')}
        self.rows['java.lang.RuntimeException'] = {'status': 'ported', 'd': 'flint.java.lang.RuntimeException'}
        self.plans = {'org.springframework.example.Counter': {'kind': 'abstract class'},
                      'org.springframework.example.Marker': {'kind': 'interface'},
                      'org.springframework.example.CountFailure': {'kind': 'class'}}
        self.by_simple = collections.defaultdict(list)
        for type_id in self.types:
            self.by_simple[type_id.rsplit('.', 1)[-1]].append(type_id)

    def exclusion(self, type_id):
        return None

    def source(self, project, tag, type_id):
        return str(self.paths[type_id]), []

    def row(self, project, tag, element):
        return None


class SkeletonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory()
        cls.universe = FakeUniverse()
        cls.universe.paths = {}
        jobs = []
        for name, source in (('Counter', COUNTER), ('Marker', MARKER), ('CountFailure', FAILURE)):
            path = Path(cls.scratch.name) / f'{name}.java'
            path.write_text(source, encoding='utf-8')
            type_id = f'org.springframework.example.{name}'
            cls.universe.paths[type_id] = path
            kind = 'interface' if name == 'Marker' else 'class'
            jobs.append({'project': 'example', 'tag': '1', 'type': type_id, 'kind': kind})
        items, _ = skeletons.corpus(cls.universe, HELPER, jobs)
        cls.items = {item['type'].rsplit('.', 1)[1]: item for item in items}
        cls.counter = skeletons.derive(cls.items['Counter'], cls.universe)
        cls.marker = skeletons.derive(cls.items['Marker'], cls.universe)

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def test_class_declarations_and_ddoc(self):
        text = self.counter['text']
        self.assertTrue(text.startswith('/// Counts things for `Marker` users.\nabstract class Counter : Marker\n{\n'), text)
        self.assertIn('    mixin Marker.Defaults;\n\n    mixin JavaObject;\n', text)
        self.assertIn('    /// The default step.\n    enum int STEP = 2;\n', text)
        self.assertNotIn('serialVersionUID', text)
        self.assertIn('    private string name_;\n    private int count;\n    private Nullable!string label;', text)
        # R24: a protected final field is a final accessor over a private field.
        self.assertIn('    protected final string name() => name_;', text)
        self.assertEqual(self.counter['rows']['org.springframework.example.Counter#name'], ('adapted', ['R24']))

    def test_mechanical_bodies_are_derived(self):
        text = self.counter['text']
        self.assertIn('    /// Create a counter.\n    this(string name)\n    {\n        this.name_ = name;\n    }', text)
        self.assertIn('    int getCount()\n    {\n        return this.count;\n    }', text)
        self.assertIn('    void setLabel(Nullable!string label)\n    {\n        this.label = label;\n    }', text)
        self.assertNotIn('org.springframework.example.Counter#getCount()', self.counter['bodies'])

    def test_other_bodies_are_marked(self):
        text = self.counter['text']
        element = 'org.springframework.example.Counter#increment()'
        self.assertIn(f'    /// Add the step.\n    int increment()\n    {{\n        // port:body {element}\n'
                      f'        assert(0, "port:body {element}");\n        // port:end-body\n    }}', text)
        self.assertIn('org.springframework.example.Counter#<init>(String,int)', self.counter['bodies'])
        self.assertIn('    static Counter of(string name)\n', text)
        self.assertIn('    protected abstract void reset(List!(string) reasons);', text)

    def test_r11_members_keep_java_names(self):
        text = self.counter['text']
        # `mixin JavaObject;` maps them onto opEquals and toHash; D's Object has neither name to override.
        self.assertIn('    bool equals(Object other)\n', text)
        self.assertIn('    int hashCode()\n', text)
        self.assertIn('    override string toString()\n', text)
        self.assertEqual(self.counter['rows']['org.springframework.example.Counter#hashCode()'], ('adapted', ['R11']))

    def test_members_the_rules_cannot_declare_are_pending(self):
        pending = self.counter['pending']
        self.assertEqual(pending['org.springframework.example.Counter#convert(Class)'], 'a generic method')
        self.assertEqual(pending['org.springframework.example.Counter#log(String)'], 'varargs (R7)')
        self.assertEqual(pending['org.springframework.example.Counter.Snapshot'], 'a nested class (R13)')
        self.assertIn('    // port:pending org.springframework.example.Counter#log(String): varargs (R7)',
                      self.counter['text'])
        self.assertNotIn('org.springframework.example.Counter#log(String)', self.counter['rows'])

    def test_interface_defaults_follow_r3(self):
        text = self.marker['text']
        self.assertIn('interface Marker\n{\n    enum int LIMIT = 10;\n\n    string getName();\n\n'
                      '    Nullable!string describe();\n\n    static Marker none()\n', text)
        self.assertIn('    mixin template Defaults()\n    {\n        Nullable!string describe()\n        {\n'
                      '            // port:body org.springframework.example.Marker#describe()\n', text)
        self.assertEqual(self.marker['rows']['org.springframework.example.Marker#describe()'],
                         ('adapted', ['R3', 'R5']))
        # A landed D interface without `Defaults` isn't mixed in.
        d = skeletons.derive(self.items['Counter'], self.universe, d_defaults=set())
        self.assertNotIn('Marker.Defaults', d['text'])

    def test_throwable_constructors_follow_r8_and_r26(self):
        item = self.items['CountFailure']
        with self.assertRaisesRegex(Unsupported, 'D base constructors are unknown'):
            skeletons.derive(item, self.universe)
        d = skeletons.derive(item, self.universe, RUNTIME_EXCEPTION)
        self.assertIn('    this(string msg, int count, string file = __FILE__, size_t line = __LINE__) pure nothrow\n'
                      '    {\n        super(msg, file, line);\n        this.count = count;\n    }', d['text'])
        self.assertEqual(d['rows']['org.springframework.example.CountFailure#<init>(String,int)'], ('adapted', ['R26']))
        self.assertIn('    this(int count, string file = __FILE__, size_t line = __LINE__) pure nothrow\n    {\n'
                      '        // port:body org.springframework.example.CountFailure#<init>(int)\n', d['text'])

    def test_imports_name_the_mapped_types_the_module_lacks(self):
        module = 'module flint.other;\nimport flint.java.util : List;\n'
        text = skeletons.with_imports('class A : Marker { mixin JavaObject; Nullable!string x; }', module,
                                      {'Marker': 'flint.example.Marker'})
        self.assertEqual(text.split('class')[0], 'import flint.example : Marker;\n'
                         'import flint.java.lang.javaobject : JavaObject;\nimport std.typecons : Nullable;\n')
        same = skeletons.with_imports('class A : Marker {}', 'module flint.example;\n', {'Marker': 'flint.example.Marker'})
        self.assertEqual(same, 'class A : Marker {}')

    def test_api_comparison_ignores_overload_order_and_private_members(self):
        hand = 'A visibility public\nA.f#0 public void(int x)\nA.f#1 public void()\nA.x private field int\n'
        spliced = 'A visibility public\nA.f#0 public void()\nA.f#1 public void(int x)\n'
        self.assertEqual(skeletons.api_by_name(hand), skeletons.api_by_name(spliced))
        self.assertEqual(skeletons.without_attributes(['A.f public pure nothrow @nogc @safe void(int x) pure nothrow '
                                                       '@nogc @safe static final']),
                         ['A.f public void(int x) static final'])

    def test_unsupported_types_are_rejected(self):
        item = {**self.items['Counter'], 'class': {**self.items['Counter']['class'], 'typeParameters': ['T']}}
        with self.assertRaisesRegex(Unsupported, 'a generic type'):
            skeletons.derive(item, self.universe)

    def test_written_bodies_carry_over_and_strip_pending_leaves_the_rest_out(self):
        increment = 'org.springframework.example.Counter#increment()'
        filled = {increment: ['this.count += STEP;', '', 'return this.count;']}
        d = skeletons.derive(self.items['Counter'], self.universe, filled=filled)
        self.assertIn(f'    int increment()\n    {{\n        // port:body {increment}\n        this.count += STEP;\n\n'
                      '        return this.count;\n        // port:end-body\n    }', d['text'])
        self.assertNotIn(increment, d['bodies'])
        self.assertIn('org.springframework.example.Counter#<init>(String,int)', d['bodies'])
        # What lands on main: every unwritten body's member is left out and listed, and its row stays deferred.
        stripped = skeletons.derive(self.items['Counter'], self.universe, filled=filled, strip=True)
        self.assertEqual(stripped['bodies'], [])
        self.assertNotIn('assert(0', stripped['text'])
        self.assertIn(f'// port:body {increment}', stripped['text'])
        self.assertEqual(stripped['pending']['org.springframework.example.Counter#of(String)'], skeletons.STRIPPED)
        self.assertNotIn('org.springframework.example.Counter#of(String)', stripped['rows'])
        self.assertIn('    this(string name)\n', stripped['text'])  # a derived body needs no lane
        self.assertNotIn('@disable this();', stripped['text'])
        # R3: an unwritten default leaves the interface too, so implementors don't lose a body they inherit.
        marker = skeletons.derive(self.items['Marker'], self.universe, strip=True)
        self.assertNotIn('describe()', marker['text'].split('// port:pending')[0])
        self.assertNotIn('mixin template Defaults', marker['text'])
        # Every constructor left out: D's implicit default constructor would be API Java doesn't have.
        failure = skeletons.derive(self.items['CountFailure'], self.universe, [['int a', 'int b']], strip=True)
        self.assertIn('    @disable this();', failure['text'])

    def test_written_bodies_and_placeholders_are_read_from_a_module(self):
        text = ('class A\n{\n    void f()\n    {\n        // port:body x.A#f()\n        g();\n\n        h();\n'
                '        // port:end-body\n    }\n    void k()\n    {\n        // port:body x.A#k()\n'
                '        assert(0, "port:body x.A#k()");\n        // port:end-body\n    }\n}\n')
        filled, open_ = skeletons.written_bodies(text)
        self.assertEqual(filled, {'x.A#f()': ['g();', '', 'h();']})
        self.assertEqual(open_, {'x.A#k()'})
        self.assertEqual(skeletons.placeholders(text), ['x.A#k()'])
        # Gate (d): no placeholder may land on main.
        path = skeletons.ROOT / 'tools' / 'port-spring' / 'tests' / f'placeholder_{os.getpid()}.d'
        try:
            path.write_text(text, encoding='utf-8')
            [failure] = skeletons.gate.check_placeholders([path])
            self.assertIn('x.A#k() still holds its placeholder', failure)
            path.write_text(text.replace('assert(0, "port:body x.A#k()");', 'g();'), encoding='utf-8')
            self.assertEqual(skeletons.gate.check_placeholders([path]), [])
        finally:
            path.unlink(missing_ok=True)

    def test_regions_carry_a_digest_the_gate_accepts(self):
        item = {**self.items['Marker'], 'job': {'project': 'example', 'tag': '1'}}
        region = skeletons.region_of(item, self.marker)
        self.assertTrue(region.startswith('// port:generated port-skeleton/1 example@1 '
                                          'org.springframework.example.Marker sha256:'), region)
        [(line, version, upstream, type_id, digest, body)] = skeletons.gate.regions(region)
        import hashlib
        self.assertEqual(hashlib.sha256(skeletons.gate.digest_text(body).encode()).hexdigest(), digest)
        self.assertEqual((version, upstream, type_id), ('port-skeleton/1', 'example@1',
                                                        'org.springframework.example.Marker'))

    def test_merging_into_a_hand_module_replaces_appends_and_imports(self):
        old = ('module flint.example;\n\nimport flint.java.util : List;\n\n@safe:\n\nclass Hand {}\n\n'
               '// port:generated port-skeleton/1 example@1 x.A sha256:00\nclass A {}\n// port:end\n\nvoid tail() {}\n')
        new_a = '// port:generated port-skeleton/1 example@1 x.A sha256:11\nclass A { int f; }\n// port:end\n'
        new_b = '// port:generated port-skeleton/1 example@1 x.B sha256:22\nclass B {}\n// port:end\n'
        text = skeletons.merged(old, {'x.A': new_a, 'x.B': new_b}, 'import flint.other : C;\n')
        self.assertEqual(text, 'module flint.example;\n\nimport flint.java.util : List;\nimport flint.other : C;\n\n'
                         '@safe:\n\nclass Hand {}\n\n' + new_a + '\nvoid tail() {}\n\n' + new_b)
        self.assertTrue(skeletons.hand_declares(text, 'x.B', 'Hand'))
        self.assertFalse(skeletons.hand_declares(text, 'x.B', 'B'))  # its own region doesn't count

    def test_splicing_keeps_nested_types_the_skeleton_cannot_emit(self):
        # R13 leaves a nested type pending; replacing the outer declaration must not delete it, or the hand's
        # other types (and a pending `mutate()` returning it) stop compiling and every element becomes a
        # spurious compile divergence.
        hand = ('module flint.example;\n\n@safe:\n\ninterface Outer\n{\n    Builder mutate();\n\n'
                '    enum SYSTEM = "system";\n\n'
                '    interface Builder\n    {\n        Outer build();\n    }\n}\n')
        generated = 'interface Outer\n{\n    enum SYSTEM = "system";\n\n    int getValue();\n}'
        text = porter_gate.splice_one(hand, 'Outer', generated)
        self.assertIn('    int getValue();', text)
        self.assertIn('    interface Builder\n    {\n        Outer build();\n    }', text)
        self.assertEqual(text.count('interface Builder'), 1)
        # D's `enum NAME = value;` is a manifest constant the skeleton also emits, not a nested enum type.
        self.assertEqual(text.count('enum SYSTEM'), 1)
        # A skeleton that does declare the nested type is not duplicated.
        with_nested = ('interface Outer\n{\n    enum SYSTEM = "system";\n\n    int getValue();\n\n'
                       '    interface Builder\n    {\n    }\n}')
        self.assertEqual(porter_gate.splice_one(hand, 'Outer', with_nested).count('interface Builder'), 1)

    def test_mapping_rows_merge_line_by_line(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'mapping.json'
            path.write_text('{"rulebook":2,\n"elements":{\n'
                            '"x.A":{"status":"excluded","category":"deferred","phase":"2"},\n'
                            '"x.A#f()":{"status":"excluded","category":"deferred","phase":"2"},\n'
                            '"x.H":{"status":"ported","d":"flint.x.H"},\n'
                            '"x.Z**":{"status":"excluded","category":"deferred","phase":"2"}\n}}\n', encoding='utf-8')
            refused = skeletons.merge_rows(path, {
                'x.A': {'status': 'ported', 'd': 'flint.x.A', 'generated': 'port-skeleton/1'},
                'x.A#g()': {'status': 'ported', 'd': 'flint.x.A.g', 'generated': 'port-skeleton/1'},
                'x.H': {'status': 'adapted', 'd': 'flint.x.H', 'rules': ['R5'], 'generated': 'port-skeleton/1'},
                'x.Z#h()': {'status': 'ported', 'd': 'flint.x.Z.h', 'generated': 'port-skeleton/1'}})
            self.assertEqual(refused, ['x.H'])  # a hand row is never replaced
            text = path.read_text(encoding='utf-8')
            self.assertEqual(text.splitlines()[2:8], [
                '"x.A":{"status":"ported","d":"flint.x.A","generated":"port-skeleton/1"},',
                '"x.A#f()":{"status":"excluded","category":"deferred","phase":"2"},',
                '"x.A#g()":{"status":"ported","d":"flint.x.A.g","generated":"port-skeleton/1"},',
                '"x.H":{"status":"ported","d":"flint.x.H"},',
                '"x.Z**":{"status":"excluded","category":"deferred","phase":"2"},',
                '"x.Z#h()":{"status":"ported","d":"flint.x.Z.h","generated":"port-skeleton/1"}'])
            import json
            self.assertEqual(len(json.loads(text)['elements']), 6)

    def test_new_modules_sit_beside_their_parent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            index = {'flint.a': [(root, root / 'flint' / 'a' / 'package.d')],
                     'flint.a.b.c': [(root, root / 'flint' / 'a' / 'b' / 'c.d')],
                     'flint.d': [(root, root / 'flint' / 'd.d')]}
            self.assertEqual(skeletons.place_of('flint.a.e', index), (root, root / 'flint' / 'a' / 'e.d', False))
            self.assertEqual(skeletons.place_of('flint.a.b', index),
                             (root, root / 'flint' / 'a' / 'b' / 'package.d', False))
            self.assertEqual(skeletons.place_of('flint.d', index)[2], True)
            # A child generated in the same batch makes the new parent a package.d too.
            self.assertEqual(skeletons.place_of('flint.a.f', index, {'flint.a.f.g'}),
                             (root, root / 'flint' / 'a' / 'f' / 'package.d', False))
            with self.assertRaisesRegex(Unsupported, 'package.d'):
                skeletons.place_of('flint.d.e', index)

    def test_mechanical_super_calls_must_fit_a_landed_constructor(self):
        text = 'this(int capacity)\n{\n    super(capacity);\n}'
        self.assertFalse(skeletons.super_call_fits(text, [[]]))
        self.assertTrue(skeletons.super_call_fits(text, [['int size'], []]))
        self.assertTrue(skeletons.super_call_fits(text, [['int size', 'bool grow = true']]))
        self.assertTrue(skeletons.super_call_fits('this()\n{\n    this.x = 1;\n}', []))
        self.assertFalse(skeletons.super_call_fits('this()\n{\n    this.x = 1;\n}', [['int size']]))
        self.assertTrue(skeletons.super_call_fits('this()\n{\n    this(1);\n}', [['int size']]))

    def test_skeleton_compiles_and_a_marked_body_fails_loudly(self):
        compilers = [c for c in ('dmd', 'ldc2') if shutil.which(c)]
        if not compilers:
            self.skipTest('no D compiler on PATH')
        marker = self.marker['text']
        failure = skeletons.derive(self.items['CountFailure'], self.universe, RUNTIME_EXCEPTION)['text']
        source = ('module skeleton_probe;\n@safe:\nimport std.typecons : Nullable;\n' + RUNTIME_EXCEPTION_D + marker
                  + '\n\n' + failure
                  + '''

class Named : Marker
{
    string getName() { return "n"; }
    mixin Marker.Defaults;
}

void main() @system
{
    import core.exception : AssertError;
    auto failure = new CountFailure("m", 3);
    assert(failure.getCount() == 3 && failure.msg == "m");
    try
    {
        (new Named).describe();
        assert(false, "a marked body returned");
    }
    catch (AssertError e)
        assert(e.msg == "port:body org.springframework.example.Marker#describe()", e.msg);
}
''')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'skeleton_probe.d'
            path.write_text(source, encoding='utf-8')
            for compiler in compilers:
                binary = Path(directory) / f'probe_{compiler}'
                build = subprocess.run([compiler, '-preview=dip1000', f'-of={binary}', str(path)], cwd=directory,
                                       capture_output=True, text=True, check=False)
                self.assertEqual(build.returncode, 0, compiler + ': ' + build.stderr)
                run = subprocess.run([str(binary)], capture_output=True, text=True, check=False,
                                     env=dict(os.environ))
                self.assertEqual(run.returncode, 0, compiler + ': ' + run.stderr)


if __name__ == '__main__':
    unittest.main()
