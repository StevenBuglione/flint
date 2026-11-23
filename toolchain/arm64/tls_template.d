// Thread-local variables of template instances (weak definitions) and of
// separate instantiations share nothing between threads.
import core.thread;

int counter(T)() { static int n; return ++n; }
struct Cache(T) { static T last; }

int main()
{
    counter!int(); counter!int();
    if (counter!int() != 3 || counter!long() != 1) return 1;
    Cache!double.last = 2.5;
    int seen = -1;
    auto t = new Thread({ seen = counter!int(); Cache!double.last = 7; });
    t.start(); t.join();
    if (seen != 1) return 2;                 // a new thread starts from the initializer
    return Cache!double.last == 2.5 ? 0 : 3; // and its writes stay in that thread
}
