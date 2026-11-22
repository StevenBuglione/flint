// Misuse: a constraint on a field of the wrong type.
// expect: quantity: NotBlank requires UTF-8 text
module validate_type;
import flint.validate : NotBlank, Violation, validate;
struct Order { @NotBlank int quantity; }
void use() { Order order; Violation[4] found; const report = validate(order, found[]); }
