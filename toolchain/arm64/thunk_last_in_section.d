// Interface thunks (ADD/SUB x0, then B to the function) come last in an object's code. The
// Mach-O writer cut the final B off the section when its addend was zero, so ld64 found a
// relocation outside the section. The classes are in thunk_last_in_section/, a library (run.py).
module thunk_last_in_section_test;

import thunk_last_in_section.shapes;

int main()
{
    auto sq = new Square(3);
    Shape s = sq;
    Named n = sq;
    return s.area() == 9 && n.name() == "square" ? 0 : 1;
}
