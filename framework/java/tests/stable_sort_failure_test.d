module stable_sort_failure_test;

import flint.java.lang : IllegalStateException;
import flint.java.util : ArrayList, Collections, Comparator, stableSort;

@safe:

// When the comparator throws, every element stays in place, as Temurin 21's binary insertion sort keeps it below 32
// elements (its TimSort merges can lose elements above that). Each element carries its input position, so a lost or
// duplicated element shows up as a missing or repeated position.
private struct Entry
{
    int key;
    int position;
}

private Entry[] entries(int count)
{
    Entry[] result;
    foreach (i; 0 .. count)
        result ~= Entry((i * 7 + 3) % 5, i);
    return result;
}

private bool isPermutation(const Entry[] items, int count)
{
    if (items.length != count)
        return false;
    auto seen = new bool[count];
    foreach (entry; items)
    {
        if (entry.position < 0 || entry.position >= count || seen[entry.position])
            return false;
        seen[entry.position] = true;
    }
    return true;
}

private int byKey(Entry a, Entry b)
{
    return (a.key > b.key) - (a.key < b.key);
}

private size_t comparisonsFor(int count)
{
    size_t comparisons;
    auto items = entries(count);
    stableSort(items, (Entry a, Entry b) { ++comparisons; return byKey(a, b); });
    return comparisons;
}

unittest
{
    // 6 elements sort by insertion alone; 20 elements add merges over insertion-sorted runs.
    foreach (count; [6, 20])
    {
        auto clean = entries(count);
        stableSort(clean, (Entry a, Entry b) => byKey(a, b));
        const total = comparisonsFor(count);
        assert(total > 0);
        foreach (failAt; 1 .. total + 1)
        {
            auto items = entries(count);
            size_t comparisons;
            try
            {
                stableSort(items, (Entry a, Entry b) {
                    if (++comparisons == failAt)
                        throw new IllegalStateException("comparator failed");
                    return byKey(a, b);
                });
                assert(0, "the comparator failure must propagate");
            }
            catch (IllegalStateException)
            {
            }
            assert(isPermutation(items, count), "a throwing comparator lost or duplicated an element");
            // The partial order keeps equal keys in input order, so sorting again matches a clean stable sort.
            stableSort(items, (Entry a, Entry b) => byKey(a, b));
            assert(items == clean, "a retried sort is not stable");
        }
    }
}

unittest
{
    // ArrayList.sort and Collections.sort sort the list's own storage in place.
    auto list = new ArrayList!int();
    foreach (value; [5, 3, 9, 1, 7, 2, 8])
        list.add(value);
    int comparisons;
    auto failing = Comparator!int.of((int a, int b) {
        if (++comparisons == 4)
            throw new IllegalStateException("comparator failed");
        return (a > b) - (a < b);
    });
    try
    {
        Collections.sort(list, failing);
        assert(0, "the comparator failure must propagate");
    }
    catch (IllegalStateException)
    {
    }
    assert(list.size() == 7);
    bool[10] seen;
    foreach (i; 0 .. list.size())
    {
        const value = list.get(i);
        assert(!seen[value], "a throwing comparator duplicated a list element");
        seen[value] = true;
    }
    assert(seen == [false, true, true, true, false, true, false, true, true, true],
            "a throwing comparator lost a list element");
}
