// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.util.queue : Queue;

@safe:

private int drain(Queue!int queue, int value)
{
    if (queue is null)
        return value & 127;
    if (!queue.offer(value))
        return 1;
    if (!queue.add(value))
        return 2;
    auto head = queue.peek();
    auto first = queue.poll();
    auto last = queue.element();
    auto removed = queue.remove();
    return (head + first + last + removed + queue.size()) & 127;
}

int main(string[] args)
{
    return drain(null, cast(int) args.length);
}
