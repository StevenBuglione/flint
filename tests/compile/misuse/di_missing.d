// Misuse: a service whose dependency is not registered.
// expect: missing DI dependency Mailer required by Orders
module di_missing;
import flint.di : AppContext, Service;
@Service final class Mailer { this() {} }
@Service final class Orders { this(Mailer mailer) {} }
void use() { AppContext!(Orders) context; context.initialize(); }
