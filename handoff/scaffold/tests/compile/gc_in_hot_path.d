module gc_in_hot_path;
@safe:
int[] badAllocation() nothrow @nogc
{
    return new int[4];
}
