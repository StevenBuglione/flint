// Reference: Jackson Databind 3.1.8 release jar, SHA-256
// 2e7583c96f3eaf11591a727c75278b25a0f1227d29a7c5e8306f252f441bfb58.
module feature_mask_test;

import flint.jackson.databind : JsonMapper;
import flint.jackson.databind.cfg : DeserializationFeature, MapperFeature, SerializationFeature,
    enabledByDefault, enabledIn, getLongMask, getMask;
import std.traits : EnumMembers;

@safe:

@("Jackson 3.1.8 SerializationFeature option defaults and masks")
unittest
{
    alias Feature = SerializationFeature;
    struct Expected
    {
        Feature feature;
        bool defaultState;
        int mask;
    }

    static immutable expected = [
        Expected(Feature.WRAP_ROOT_VALUE, false, 1), Expected(Feature.INDENT_OUTPUT, false, 2),
        Expected(Feature.FAIL_ON_EMPTY_BEANS, false, 4),
        Expected(Feature.FAIL_ON_SELF_REFERENCES, true, 8),
        Expected(Feature.WRAP_EXCEPTIONS, true, 16),
        Expected(Feature.FAIL_ON_UNWRAPPED_TYPE_IDENTIFIERS, true, 32),
        Expected(Feature.WRITE_SELF_REFERENCES_AS_NULL, false, 64),
        Expected(Feature.CLOSE_CLOSEABLE, false, 128),
        Expected(Feature.FLUSH_AFTER_WRITE_VALUE, true, 256),
        Expected(Feature.WRITE_CHAR_ARRAYS_AS_JSON_ARRAYS, false, 512),
        Expected(Feature.WRITE_EMPTY_JSON_ARRAYS, true, 1_024),
        Expected(Feature.WRITE_SINGLE_ELEM_ARRAYS_UNWRAPPED, false, 2_048),
        Expected(Feature.ORDER_MAP_ENTRIES_BY_KEYS, false, 4_096),
        Expected(Feature.FAIL_ON_ORDER_MAP_BY_INCOMPARABLE_KEY, false, 8_192),
        Expected(Feature.APPLY_JSON_INCLUDE_FOR_CONTAINERS, false, 16_384),
        Expected(Feature.EAGER_SERIALIZER_FETCH, true, 32_768),
        Expected(Feature.USE_EQUALITY_FOR_OBJECT_ID, false, 65_536),
    ];
    static assert(expected.length == EnumMembers!Feature.length);
    foreach (ordinal, row; expected)
    {
        assert(cast(size_t) row.feature == ordinal);
        static assert(is(typeof(row.feature.getMask()) == int));
        assert(row.feature.enabledByDefault() == row.defaultState);
        assert(row.feature.getMask() == row.mask);
        assert(row.feature.enabledIn(row.mask));
        assert(!row.feature.enabledIn(0));
        assert(!row.feature.enabledIn(~row.mask));
        assert(row.feature.enabledIn(-1));
    }
}

@("Jackson 3.1.8 DeserializationFeature option defaults and masks")
unittest
{
    alias Feature = DeserializationFeature;
    struct Expected
    {
        Feature feature;
        bool defaultState;
        int mask;
    }

    static immutable expected = [
        Expected(Feature.USE_BIG_DECIMAL_FOR_FLOATS, false, 1),
        Expected(Feature.USE_BIG_INTEGER_FOR_INTS, false, 2),
        Expected(Feature.USE_LONG_FOR_INTS, false, 4),
        Expected(Feature.USE_JAVA_ARRAY_FOR_JSON_ARRAY, false, 8),
        Expected(Feature.USE_NULL_FOR_MISSING_REFERENCE_VALUES, false, 16),
        Expected(Feature.USE_NULL_FOR_EMPTY_UNWRAPPED, false, 32),
        Expected(Feature.FAIL_ON_UNKNOWN_PROPERTIES, false, 64),
        Expected(Feature.FAIL_ON_NULL_FOR_PRIMITIVES, true, 128),
        Expected(Feature.FAIL_ON_INVALID_SUBTYPE, true, 256),
        Expected(Feature.IGNORE_ABSTRACT_TYPES_FOR_DEDUCTION, true, 512),
        Expected(Feature.FAIL_ON_READING_DUP_TREE_KEY, false, 1_024),
        Expected(Feature.FAIL_ON_IGNORED_PROPERTIES, false, 2_048),
        Expected(Feature.FAIL_ON_UNRESOLVED_OBJECT_IDS, true, 4_096),
        Expected(Feature.FAIL_ON_MISSING_CREATOR_PROPERTIES, false, 8_192),
        Expected(Feature.FAIL_ON_NULL_CREATOR_PROPERTIES, false, 16_384),
        Expected(Feature.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY, true, 32_768),
        Expected(Feature.FAIL_ON_TRAILING_TOKENS, true, 65_536),
        Expected(Feature.FAIL_ON_SUBTYPE_CLASS_NOT_REGISTERED, false, 131_072),
        Expected(Feature.WRAP_EXCEPTIONS, true, 262_144),
        Expected(Feature.FAIL_ON_UNEXPECTED_VIEW_PROPERTIES, false, 524_288),
        Expected(Feature.FAIL_ON_UNKNOWN_INJECT_VALUE, true, 1_048_576),
        Expected(Feature.ACCEPT_SINGLE_VALUE_AS_ARRAY, false, 2_097_152),
        Expected(Feature.UNWRAP_SINGLE_VALUE_ARRAYS, false, 4_194_304),
        Expected(Feature.UNWRAP_ROOT_VALUE, false, 8_388_608),
        Expected(Feature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT, false, 16_777_216),
        Expected(Feature.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT, false, 33_554_432),
        Expected(Feature.ACCEPT_FLOAT_AS_INT, true, 67_108_864),
        Expected(Feature.EAGER_DESERIALIZER_FETCH, true, 134_217_728),
    ];
    static assert(expected.length == EnumMembers!Feature.length);
    foreach (ordinal, row; expected)
    {
        assert(cast(size_t) row.feature == ordinal);
        static assert(is(typeof(row.feature.getMask()) == int));
        assert(row.feature.enabledByDefault() == row.defaultState);
        assert(row.feature.getMask() == row.mask);
        assert(row.feature.enabledIn(row.mask));
        assert(!row.feature.enabledIn(0));
        assert(!row.feature.enabledIn(~row.mask));
        assert(row.feature.enabledIn(-1));
    }
}

@("Jackson 3.1.8 MapperFeature option defaults and masks")
unittest
{
    alias Feature = MapperFeature;
    struct Expected
    {
        Feature feature;
        bool defaultState;
        long mask;
    }

    static immutable expected = [
        Expected(Feature.USE_ANNOTATIONS, true, 1L),
        Expected(Feature.USE_GETTERS_AS_SETTERS, false, 2L),
        Expected(Feature.PROPAGATE_TRANSIENT_MARKER, false, 4L),
        Expected(Feature.REQUIRE_SETTERS_FOR_GETTERS, false, 8L),
        Expected(Feature.ALLOW_FINAL_FIELDS_AS_MUTATORS, false, 16L),
        Expected(Feature.INFER_PROPERTY_MUTATORS, true, 32L),
        Expected(Feature.INFER_CREATOR_FROM_CONSTRUCTOR_PROPERTIES, true, 64L),
        Expected(Feature.ALLOW_IS_GETTERS_FOR_NON_BOOLEAN, false, 128L),
        Expected(Feature.INFER_RECORD_GETTERS_FROM_COMPONENTS_ONLY, false, 256L),
        Expected(Feature.ALLOW_VOID_VALUED_PROPERTIES, true, 512L),
        Expected(Feature.DETECT_PARAMETER_NAMES, true, 1_024L),
        Expected(Feature.CAN_OVERRIDE_ACCESS_MODIFIERS, true, 2_048L),
        Expected(Feature.OVERRIDE_PUBLIC_ACCESS_MODIFIERS, true, 4_096L),
        Expected(Feature.INVERSE_READ_WRITE_ACCESS, false, 8_192L),
        Expected(Feature.USE_STATIC_TYPING, false, 16_384L),
        Expected(Feature.USE_BASE_TYPE_AS_DEFAULT_IMPL, false, 32_768L),
        Expected(Feature.INFER_BUILDER_TYPE_BINDINGS, true, 65_536L),
        Expected(Feature.REQUIRE_TYPE_ID_FOR_SUBTYPES, true, 131_072L),
        Expected(Feature.DEFAULT_VIEW_INCLUSION, false, 262_144L),
        Expected(Feature.SORT_PROPERTIES_ALPHABETICALLY, true, 524_288L),
        Expected(Feature.SORT_CREATOR_PROPERTIES_FIRST, true, 1_048_576L),
        Expected(Feature.ACCEPT_CASE_INSENSITIVE_PROPERTIES, false, 2_097_152L),
        Expected(Feature.ACCEPT_CASE_INSENSITIVE_ENUMS, false, 4_194_304L),
        Expected(Feature.ACCEPT_CASE_INSENSITIVE_VALUES, false, 8_388_608L),
        Expected(Feature.USE_WRAPPER_NAME_AS_PROPERTY_NAME, false, 16_777_216L),
        Expected(Feature.ALLOW_EXPLICIT_PROPERTY_RENAMING, false, 33_554_432L),
        Expected(Feature.FIX_FIELD_NAME_UPPER_CASE_PREFIX, true, 67_108_864L),
        Expected(Feature.ALLOW_COERCION_OF_SCALARS, true, 134_217_728L),
        Expected(Feature.WRAPPERS_DEFAULT_TO_NULL, false, 268_435_456L),
        Expected(Feature.IGNORE_MERGE_FOR_UNMERGEABLE, true, 536_870_912L),
        Expected(Feature.APPLY_DEFAULT_VALUES, true, 1_073_741_824L),
    ];
    static assert(expected.length == EnumMembers!Feature.length);
    foreach (ordinal, row; expected)
    {
        assert(cast(size_t) row.feature == ordinal);
        static assert(is(typeof(row.feature.getLongMask()) == long));
        assert(row.feature.enabledByDefault() == row.defaultState);
        assert(row.feature.getLongMask() == row.mask);
        assert(row.feature.enabledIn(row.mask));
        assert(!row.feature.enabledIn(0));
        assert(!row.feature.enabledIn(~row.mask));
        assert(row.feature.enabledIn(-1));
    }
}

@("Jackson configuration accepts the two typed ConfigFeature option enums")
unittest
{
    auto mapper = JsonMapper.builder().enable(SerializationFeature.INDENT_OUTPUT)
        .disable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS).build();
    assert(mapper.isEnabled(SerializationFeature.INDENT_OUTPUT));
    assert(!mapper.isEnabled(DeserializationFeature.FAIL_ON_TRAILING_TOKENS));
}
