// A small struct passed in a register whose fields are read one by one: x86 reads a
// sub-register, AArch64 must not compare or use the whole register as the field.
enum Month : ubyte { jan = 1, feb }

struct Date
{
    short year = 1; Month month = Month.jan; ubyte day = 1;
    int opCmp(Date rhs) const
    {
        if (year != rhs.year) return year < rhs.year ? -1 : 1;
        if (month != rhs.month) return month < rhs.month ? -1 : 1;
        if (day != rhs.day) return day < rhs.day ? -1 : 1;
        return 0;
    }
}

struct Pair { int lo; short hi; }
int hiOf(Pair p) { return p.hi; }

int main()
{
    Date a, b;
    if (a.opCmp(b) != 0) return 1;
    if (Date(1999, Month.feb, 3).opCmp(Date(1999, Month.jan, 30)) != 1) return 2;
    if (Date(-5, Month.jan, 1).opCmp(Date(3, Month.jan, 1)) != -1) return 3;
    return hiOf(Pair(0x7fff_0000, -7)) == -7 ? 0 : 4;
}
