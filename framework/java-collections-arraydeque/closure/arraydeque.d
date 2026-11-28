// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.util.arraydeque : ArrayDeque;

@safe:

private int drain(ArrayDeque!int deque, int value)
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
    auto l = deque.remove(value);
    auto m = deque.removeFirstOccurrence(value);
    auto n = deque.removeLastOccurrence(value);
    auto o = deque.add(value) && deque.offer(value);
    auto p = deque.size() + deque.toArray().length;
    auto q = deque.contains(value) + deque.isEmpty() + cast(int) deque.isSet();
    auto r = deque.elementTypeName().length;
    auto s = deque.clone();
    auto t = s.equals(deque) || s.hashCode() == value ? 1 : 0;
    s.clear();
    deque.forEach((int element) { value += element; });
    foreach (element; deque)
        value += element;
    for (auto it = deque.iterator(); it.hasNext();)
        value += it.next();
    for (auto it = deque.descendingIterator(); it.hasNext();)
        value += it.next();
    return (a + b + c + d + e + f + g + h + i + j + k + l + m + n + o + p + q + r + t + value) & 127;
}

int main(string[] args)
{
    return drain(null, cast(int) args.length);
}
