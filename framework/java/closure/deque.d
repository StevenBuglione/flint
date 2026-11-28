// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.util.deque : Deque;

@safe:

private int drain(Deque!int deque, int value)
{
    if (deque is null)
        return value & 127;
    deque.addFirst(value);
    deque.addLast(value);
    if (!deque.offerFirst(value) || !deque.offerLast(value))
        return 1;
    deque.push(value);
    auto a = deque.peekFirst();
    auto b = deque.peekLast();
    auto c = deque.pollFirst();
    auto d = deque.pollLast();
    auto e = deque.getFirst();
    auto f = deque.getLast();
    auto g = deque.removeFirst();
    auto h = deque.removeLast();
    auto i = deque.element();
    auto j = deque.peek();
    auto k = deque.remove();
    auto l = deque.removeFirstOccurrence(value);
    auto m = deque.removeLastOccurrence(value);
    auto it = deque.descendingIterator();
    if (it.hasNext())
        a += it.next();
    return (a + b + c + d + e + f + g + h + i + j + k + l + m + deque.size()) & 127;
}

int main(string[] args)
{
    return drain(null, cast(int) args.length);
}
