"""Check --describe and the Java Beans shape's rules on a synthetic @ConfigurationProperties class."""

from pathlib import Path
import sys
import tempfile
import unittest

from test_annotations import HELPER

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import beans  # noqa: E402


SOURCE = """package org.springframework.boot.example;

import java.time.Duration;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.jspecify.annotations.Nullable;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.convert.DurationUnit;

/**
 * Example settings, see {@link Other#thing}.
 *
 * @author Someone
 */
@ConfigurationProperties("spring.example")
public class ExampleProperties {

	private static final String[] LOCATIONS = { "a/", "b/" };

	/**
	 * Whether to enable {@code example}.
	 */
	private boolean enabled = true;

	/**
	 * Port, or {@code null}.
	 */
	private @Nullable Integer port;

	/**
	 * Timeout.
	 */
	@DurationUnit(ChronoUnit.SECONDS)
	private @Nullable Duration timeout;

	/**
	 * Locations.
	 */
	private String[] locations = LOCATIONS;

	/**
	 * Names.
	 */
	private List<String> names = new ArrayList<>(List.of("x", "y"));

	/**
	 * Mode.
	 */
	private Mode mode = Mode.FAST;

	/**
	 * Size.
	 */
	private DataSize size;

	private final Map<Mode, Boolean> features = new LinkedHashMap<>();

	private final Inner inner = new Inner();

	private String hidden;

	public boolean isEnabled() {
		return this.enabled;
	}

	public void setEnabled(boolean enabled) {
		this.enabled = enabled;
	}

	public @Nullable Integer getPort() {
		return this.port;
	}

	public void setPort(@Nullable Integer port) {
		this.port = port;
	}

	public @Nullable Duration getTimeout() {
		return this.timeout;
	}

	public void setTimeout(@Nullable Duration timeout) {
		this.timeout = timeout;
	}

	public String[] getLocations() {
		return this.locations;
	}

	public void setLocations(String[] locations) {
		this.locations = clean(locations);
	}

	public List<String> getNames() {
		return this.names;
	}

	public void setNames(List<String> names) {
		this.names = names;
	}

	public Mode getMode() {
		return this.mode;
	}

	public void setMode(Mode mode) {
		this.mode = mode;
	}

	public DataSize getSize() {
		return this.size;
	}

	public void setSize(DataSize size) {
		this.size = size;
	}

	public Map<Mode, Boolean> getFeatures() {
		return this.features;
	}

	public Inner getInner() {
		return this.inner;
	}

	/**
	 * Modes.
	 */
	public enum Mode {

		/**
		 * Fast.
		 */
		FAST,

		/**
		 * Slow.
		 */
		SLOW

	}

	/**
	 * Inner settings.
	 */
	public static class Inner {

		/**
		 * Limit.
		 */
		private long limit = 1_000L;

		public long getLimit() {
			return this.limit;
		}

		public void setLimit(long limit) {
			this.limit = limit;
		}

	}

}
"""


class BeansTests(unittest.TestCase):
    def derive(self, source=SOURCE):
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "ExampleProperties.java"
            path.write_text(source, encoding="utf-8")
            tree = beans.describe(str(HELPER), str(path))
        return tree, beans.derive_class(tree["type"])

    def test_describe_keeps_the_declaration_tree(self):
        tree, _ = self.derive()
        self.assertEqual(tree["package"], "org.springframework.boot.example")
        decl = tree["type"]
        self.assertEqual(decl["annotations"], [{"name": "ConfigurationProperties", "arguments": '("spring.example")'}])
        self.assertEqual([t["name"] for t in decl["types"]], ["Mode", "Inner"])
        self.assertEqual([c["name"] for c in decl["types"][0]["constants"]], ["FAST", "SLOW"])
        port = next(f for f in decl["fields"] if f["declarators"][0]["name"] == "port")
        self.assertEqual(port["modifiers"], ["private"])
        self.assertEqual(port["annotations"], [{"name": "Nullable", "arguments": None}])

    def test_derives_the_spec(self):
        _, derived = self.derive()
        cls = derived.cls
        self.assertEqual(cls.prefix, "flint.example")
        self.assertEqual(cls.doc, "Example settings, see `Other.thing`.")
        fields = {f.name: f for f in cls.fields}
        self.assertEqual([f.name for f in cls.fields],
                         ["enabled", "port", "timeout", "locations", "names", "mode", "features", "inner"])
        expect = {
            "enabled": ("bool", "true", False, None, None),
            "port": ("Optional!int", None, False, None, None),
            "timeout": ("Optional!Duration", None, False, "@DurationUnit(ChronoUnit.SECONDS)", None),
            "locations": ("string[]", '["a/", "b/"]', False, None, None),
            "names": ("string[]", '["x", "y"]', False, None, None),
            "mode": ("Mode", "Mode.FAST", False, None, None),
            "features": ("Map!(string, bool)", "new LinkedHashMap!(string, bool)", True, None, "Map!(Mode, bool)"),
            "inner": ("Inner", "new Inner", True, None, None),
        }
        for name, (dtype, default, ro, uda, schema) in expect.items():
            with self.subTest(field=name):
                f = fields[name]
                self.assertEqual((f.dtype, f.default, f.ro, f.uda, f.schema), (dtype, default, ro, uda, schema))
        self.assertEqual(fields["enabled"].doc, "Whether to enable `example`.")
        self.assertEqual(fields["inner"].doc, "Inner settings.")
        self.assertEqual(derived.custom_setters, {"locations": "{\n\t\tthis.locations = clean(locations);\n\t}"})
        self.assertEqual(derived.unsupported, {"size": "no Flint type for DataSize",
                                               "hidden": "no getter: private state, not a property"})
        self.assertEqual([(m, d) for m, d in cls.enums[0].members], [("FAST", "Fast."), ("SLOW", "Slow.")])
        inner = cls.nested[0]
        self.assertEqual([(f.name, f.dtype, f.default) for f in inner.fields], [("limit", "long", "1000")])

    def test_rejects_what_no_rule_covers(self):
        for old, new, field in (
            ("this.port = port;", "this.port = port;\n\t\tcount++;", None),
            ("return this.enabled;", "return !this.enabled;", "enabled"),
            ("Mode.FAST;", "Mode.valueOf(\"FAST\");", "mode"),
            ("@DurationUnit(ChronoUnit.SECONDS)", "@Positive", "timeout"),
        ):
            with self.subTest(change=new):
                _, derived = self.derive(SOURCE.replace(old, new, 1))
                if field is None:
                    self.assertIn("port", derived.custom_setters)
                else:
                    self.assertIn(field, derived.unsupported)

    def test_renders_with_boots_renderer(self):
        _, derived = self.derive()
        text = beans.cp.render_class(derived.cls)
        self.assertIn('@ConfigurationProperties("flint.example")', text)
        self.assertIn("final class ExampleProperties", text)
        self.assertIn("Optional!int getPort() const pure nothrow @nogc", text)
        self.assertIn("    static final class Inner", text)


if __name__ == "__main__":
    unittest.main()
