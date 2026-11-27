"""Check the R6 accessor shape's rules: detection, D types, rows, plan attributes and splicing over a hand member."""

import collections
from pathlib import Path
import sys
import tempfile
import unittest

from test_annotations import HELPER

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import accessors  # noqa: E402


SOURCE = """package org.springframework.example;

import java.util.List;
import java.util.Map;
import org.jspecify.annotations.Nullable;
import org.springframework.other.Target;

public class Holder extends Base {

    private @Nullable String name;
    private int count;
    private List<String> tags;
    private Map<String, Object> attributes;
    private Object value;
    private Target target;
    private String version;
    private Holder config;
    private static String shared;

    public @Nullable String getName() { return this.name; }
    public void setName(@Nullable String name) { this.name = name; }
    public int getCount() { return count; }
    public final void setCount(int count) { this.count = count; }
    public List<String> getTags() { return this.tags; }
    public Map<String, Object> getAttributes() { return this.attributes; }
    @Override
    public Object getValue() { return this.value; }
    public Target getTarget() { return this.target; }
    public String version() { return this.version; }
    public Holder config() { return this.config; }
    public String getShared() { return shared; }
    public int getDouble() { return this.count * 2; }
    public void setTags(String... tags) { this.tags = List.of(tags); }
    protected void setOther(int count) { this.count = count + 1; }
}
"""


class FakeUniverse:
    def __init__(self):
        base = {'id': 'org.springframework.example.Base', 'package': 'org.springframework.example', 'kind': 'class',
                'members': [{'kind': 'method', 'signature': 'getValue()', 'visibility': 'public'}]}
        holder = {'id': 'org.springframework.example.Holder', 'package': 'org.springframework.example',
                  'kind': 'class', 'extends': ['Base'], 'members': []}
        self.types = {t['id']: ('example', '1', t) for t in (base, holder)}
        for name in ('java.lang.String', 'java.lang.Object', 'java.lang.Integer', 'java.util.List', 'java.util.Map',
                     'org.springframework.other.Target'):
            self.types[name] = ('example', '1', {'id': name, 'kind': 'class'})
        self.rows = {'org.springframework.other.Target': {'status': 'ported', 'd': 'flint.other.Target'},
                     'org.springframework.example.Holder': {'status': 'ported', 'd': 'flint.example.Holder'}}
        self.plans = {'org.springframework.example.Holder': {'kind': 'class',
                                                             'accessors': {'getter': ['const', 'nothrow']}},
                      'org.springframework.other.Target': {'kind': 'struct'}}
        self.by_simple = collections.defaultdict(list)
        for type_id in self.types:
            self.by_simple[type_id.rsplit('.', 1)[-1]].append(type_id)


class AccessorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / 'Holder.java'
            path.write_text(SOURCE, encoding='utf-8')
            cls.tree = accessors.describe_java(HELPER, str(path))
        cls.universe = FakeUniverse()
        decl = cls.tree['type']
        scope = accessors.Scope(cls.universe, cls.tree, [('org.springframework.example.Holder', decl)])
        job = {'type': 'org.springframework.example.Holder', 'project': 'example', 'tag': '1'}
        cls.items = {m['name']: {'kind': kind, 'method': m, 'field': f, 'declarator': d, 'scope': scope, 'job': job,
                                 'class': decl}
                     for kind, m, (f, d) in accessors.accessors_of(decl)}

    def derive(self, name):
        return accessors.derive(self.items[name], self.universe)

    def test_detects_only_trivial_instance_accessors(self):
        self.assertEqual(sorted(self.items), ['config', 'getAttributes', 'getCount', 'getName', 'getTags',
                                              'getTarget', 'getValue', 'setCount', 'setName', 'version'])

    def test_nullable_string_takes_r5_and_plan_attributes(self):
        getter = self.derive('getName')
        self.assertEqual(getter['text'], 'public Nullable!string getName() const nothrow\n{\n    return this.name;\n}')
        self.assertEqual((getter['status'], getter['rules']), ('adapted', ['R5']))
        setter = self.derive('setName')
        self.assertEqual(setter['text'], 'public void setName(Nullable!string name)\n{\n    this.name = name;\n}')
        self.assertIn('assert(0);', setter['safe_text'])

    def test_primitive_final_and_collections(self):
        self.assertEqual(self.derive('getCount')['status'], 'ported')
        self.assertTrue(self.derive('setCount')['text'].startswith('public final void setCount(int count)'))
        tags = self.derive('getTags')
        self.assertIn('List!(string) getTags()', tags['text'])
        self.assertEqual(tags['rules'], ['R10'])
        attributes = self.derive('getAttributes')
        self.assertIn('Map!(string, Any) getAttributes()', attributes['text'])
        self.assertEqual(attributes['rules'], ['R10', 'R23'])

    def test_override_follows_the_superclass_and_object_is_any(self):
        value = self.derive('getValue')
        self.assertTrue(value['text'].startswith('public override Any getValue()'))
        self.assertEqual(value['rules'], ['R23'])

    def test_mapped_types_keywords_and_field_collisions(self):
        self.assertIn('public Target getTarget()', self.derive('getTarget')['text'])
        version = self.derive('version')
        self.assertIn('string version_()', version['text'])
        self.assertIn('return this.version__;', version['text'])  # R19, then the collision rule
        self.assertEqual(version['rules'], ['R19'])
        self.assertIn('return this.config_;', self.derive('config')['text'])

    def test_unmapped_types_are_unsupported(self):
        del self.universe.rows['org.springframework.other.Target']
        try:
            with self.assertRaisesRegex(accessors.Unsupported, 'not mapped'):
                self.derive('getTarget')
        finally:
            self.universe.rows['org.springframework.other.Target'] = {'status': 'ported', 'd': 'flint.other.Target'}

    def test_splice_replaces_only_the_matching_member(self):
        hand = '''module flint.example;
@safe:
class Holder : Base
{
    private string name_;
public:
    /// The name.
    @Marker string getName() const { return name_; }
    string getName(int index) => name_[index .. $];
    void setName(string name)
    {
        name_ = name;
    }
    final class Nested { string getName() { return ""; } }
}
'''
        out = accessors.splice(hand, 'Holder', [('getName', 0, 'public string getName()\n{\n    return x;\n}')])
        self.assertIn('    /// The name.\n    public string getName()\n    {\n        return x;\n    }\n', out)
        self.assertIn('string getName(int index) => name_[index .. $];', out)
        self.assertIn('class Nested { string getName() { return ""; } }', out)
        self.assertEqual(len(accessors.member_spans(hand, 'Holder', 'setName', 1)), 1)
        with self.assertRaisesRegex(accessors.Unsupported, '0 members'):
            accessors.splice(hand, 'Holder', [('missing', 0, 'void missing() {}')])

    def test_attributes_of_drops_module_and_class_decisions(self):
        line = 'Holder.getName#0 public const pure nothrow @nogc @safe string() const pure nothrow @nogc @safe virtual'
        self.assertEqual(accessors.attributes_of(line), ['const', 'pure', 'nothrow', '@nogc'])


if __name__ == '__main__':
    unittest.main()
