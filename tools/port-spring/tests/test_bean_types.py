"""Check the pure-bean whole-type shape: corpus detection, the derived class, R8 constructors, imports and rows."""

import collections
from pathlib import Path
import sys
import tempfile
import unittest

from test_annotations import HELPER

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bean_types  # noqa: E402
from accessors import Unsupported  # noqa: E402


BEAN = """package org.springframework.example;

import java.util.List;
import org.jspecify.annotations.Nullable;

public class Status extends Base implements Marker {

    private static final long serialVersionUID = 1L;
    private final boolean fresh;
    private @Nullable String label;
    private List<String> tags;
    private int count = 3;

    public Status() { this(true); }
    public Status(boolean fresh) { super(); this.fresh = fresh; }
    protected Status(boolean fresh, String label) { super(label, 2); this.fresh = fresh; this.count = 4; this.label = label; }

    @Override
    public boolean isFresh() { return this.fresh; }
    public @Nullable String getLabel() { return this.label; }
    public void setLabel(@Nullable String label) { this.label = label; }
    public List<String> getTags() { return tags; }
}
"""

FAILURE = """package org.springframework.example;

public class TimeoutFailure extends UsageFailure {

    private final int timeout;

    public TimeoutFailure(String msg, int timeout) { super(msg); this.timeout = timeout; }
    public TimeoutFailure(String msg) { this(msg, -1); }

    public int getTimeout() { return this.timeout; }
}
"""

NOT_MECHANICAL = """package org.springframework.example;

public class Region {

    private final long count;

    public Region(long count) { Assert.isTrue(count >= 0, "negative"); this.count = count; }

    public long getCount() { return this.count; }
    public long twice() { return this.count * 2; }
}
"""


class FakeUniverse:
    def __init__(self):
        manifest = [
            {'id': 'org.springframework.example.Base', 'kind': 'class', 'members': []},
            {'id': 'org.springframework.example.Marker', 'kind': 'interface', 'members': []},
            {'id': 'org.springframework.example.Status', 'kind': 'class', 'extends': ['Base'], 'members': []},
            {'id': 'org.springframework.example.UsageFailure', 'kind': 'class', 'extends': ['RuntimeException'],
             'members': []},
            {'id': 'org.springframework.example.TimeoutFailure', 'kind': 'class', 'extends': ['UsageFailure'],
             'members': []},
            {'id': 'org.springframework.example.Region', 'kind': 'class', 'members': []},
        ]
        for t in manifest:
            t['package'] = 'org.springframework.example'
        self.types = {t['id']: ('example', '1', t) for t in manifest}
        for name, extends in (('java.lang.String', None), ('java.lang.Object', None), ('java.util.List', None),
                              ('java.lang.Throwable', None), ('java.lang.Exception', 'Throwable'),
                              ('java.lang.RuntimeException', 'Exception')):
            self.types[name] = ('jdk', '1', {'id': name, 'kind': 'class', 'package': name.rsplit('.', 1)[0],
                                             'extends': [extends] if extends else [], 'members': []})
        self.rows = {f'org.springframework.example.{n}': {'status': 'ported', 'd': f'flint.example.{n}'}
                     for n in ('Base', 'Marker', 'Status', 'UsageFailure', 'TimeoutFailure', 'Region')}
        self.plans = {f'org.springframework.example.{n}': {'kind': 'class'}
                      for n in ('Status', 'TimeoutFailure', 'Region')}
        self.by_simple = collections.defaultdict(list)
        for type_id in self.types:
            self.by_simple[type_id.rsplit('.', 1)[-1]].append(type_id)

    def exclusion(self, type_id):
        return None

    def source(self, project, tag, type_id):
        return str(self.paths[type_id]), []

    def row(self, project, tag, element):
        return None


class BeanTypeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory()
        cls.universe = FakeUniverse()
        cls.universe.paths = {}
        jobs = []
        for name, source in (('Status', BEAN), ('TimeoutFailure', FAILURE), ('Region', NOT_MECHANICAL)):
            path = Path(cls.scratch.name) / f'{name}.java'
            path.write_text(source, encoding='utf-8')
            type_id = f'org.springframework.example.{name}'
            cls.universe.paths[type_id] = path
            jobs.append({'project': 'example', 'tag': '1', 'type': type_id, 'kind': 'class'})
        items, _ = bean_types.corpus(cls.universe, HELPER, jobs)
        cls.items = {item['type'].rsplit('.', 1)[1]: item for item in items}

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def test_only_classes_of_trivial_accessors_are_pure_beans(self):
        self.assertEqual(sorted(self.items), ['Status', 'TimeoutFailure'])

    def test_derives_the_whole_class(self):
        d = bean_types.derive(self.items['Status'], self.universe, base_members={'isFresh'})
        self.assertEqual(d['text'], '''class Status : Base, Marker
{
    private bool fresh;
    private Nullable!string label;
    private List!(string) tags;
    private int count = 3;

    public this()
    {
        this(true);
    }

    public this(bool fresh)
    {
        super();
        this.fresh = fresh;
    }

    protected this(bool fresh, string label)
    {
        super(label, 2);
        this.fresh = fresh;
        this.count = 4;
        this.label = label;
    }

    public override bool isFresh()
    {
        return this.fresh;
    }

    public Nullable!string getLabel()
    {
        return this.label;
    }

    public void setLabel(Nullable!string label)
    {
        this.label = label;
    }

    public List!(string) getTags()
    {
        return this.tags;
    }
}''')
        self.assertEqual(d['rows']['org.springframework.example.Status#<init>(boolean,String)'], ('ported', []))
        self.assertEqual(d['rows']['org.springframework.example.Status#getLabel()'], ('adapted', ['R5']))
        self.assertEqual(d['rows']['org.springframework.example.Status'], ('ported', []))

    def test_a_bare_assignment_to_a_parameter_name_is_not_mechanical(self):
        item = self.items['Status']
        ctor = dict(item['class']['constructors'][2], body='{ super(label, 2); label = null; }')
        with self.assertRaisesRegex(Unsupported, 'not a field assignment'):
            bean_types.derive_constructor(ctor, item['class'], item['scope'], bean_types.field_names(item['class']))

    def test_override_needs_java_override_and_a_d_base_member(self):
        d = bean_types.derive(self.items['Status'], self.universe)
        self.assertIn('    public bool isFresh()', d['text'])

    def test_throwable_constructors_follow_r8(self):
        item = self.items['TimeoutFailure']
        with self.assertRaisesRegex(Unsupported, 'D base constructors are unknown'):
            bean_types.derive(item, self.universe)
        base = bean_types.constructor_parameters(
            'UsageFailure.__ctor#0 public pure nothrow @safe UsageFailure(string msg, Throwable cause = null, '
            'string file = __FILE__, ulong line = cast(ulong)__LINE__) pure nothrow @safe', 'UsageFailure')
        d = bean_types.derive(item, self.universe, base)
        self.assertIn('public this(string msg, int timeout, string file = __FILE__, size_t line = __LINE__) pure '
                      'nothrow\n    {\n        super(msg, null, file, line);\n        this.timeout = timeout;', d['text'])
        self.assertIn('this(msg, -1, file, line);', d['text'])
        # A base without the file, line family forwards plainly.
        plain = bean_types.derive(item, self.universe, [['string msg']])
        self.assertIn('public this(string msg, int timeout)\n    {\n        super(msg);', plain['text'])

    def test_super_arguments_take_druntimes_trailing_cause(self):
        druntime = [['string msg', 'string file = __FILE__', 'ulong line = cast(ulong)__LINE__',
                     'Throwable nextInChain = null']]
        self.assertEqual(bean_types.super_arguments(['m', 'c'], druntime), ['m', 'file', 'line', 'c'])
        self.assertEqual(bean_types.super_arguments(['m'], druntime), ['m', 'file', 'line'])
        with self.assertRaisesRegex(Unsupported, 'R8'):
            bean_types.super_arguments([], druntime)

    def test_imports_follow_the_rulebook_types_the_module_lacks(self):
        text = 'class A\n{\n    private Nullable!string a;\n    private List!(string) b;\n}'
        module = 'module m;\nimport flint.java.util : ArrayList, List;\n'
        self.assertEqual(bean_types.with_imports(text, module), 'import std.typecons : Nullable;\n' + text)

    def test_private_members_leave_the_api_lines(self):
        description = 'A visibility public\nA.x private field int\nA.getX#0 public int()\n'
        self.assertEqual(bean_types.api_lines(description), ['A visibility public', 'A.getX#0 public int()'])


if __name__ == '__main__':
    unittest.main()
