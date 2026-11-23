module thunk_last_in_section.shapes;

// Nothing after the class here instantiates a template, so the interface thunks are the
// last code in this module's object.
interface Shape { int area(); }
interface Named { string name(); }

class Square : Shape, Named
{
    int side;
    this(int side) { this.side = side; }
    int area() { return side * side; }
    string name() { return "square"; }
}
