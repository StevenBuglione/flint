module style_usage;
import flint.style : measure, truncateCells;
unittest {
    assert(measure("A界").cells == 3);
    assert(measure("e\u0301").cells == 1);
    assert(truncateCells("abcdef", 4, "…") == "abc…");
}
