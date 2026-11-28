// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.util.priorityqueue : PriorityQueue;

@safe:

private int drain(PriorityQueue!int queue, int value)
{
    if (queue is null)
        return value & 127;
    queue.add(value);
    if (!queue.offer(value + 1))
        return 1;
    value += queue.peek();
    value += queue.poll();
    value += queue.size() + queue.toArray().length;
    value += queue.contains(value) + queue.isEmpty();
    value += queue.element();
    value += queue.remove();
    value += queue.remove(value);
    value += queue.comparator() is null ? 1 : 0;
    foreach (element; queue)
        value += element;
    for (auto it = queue.iterator(); it.hasNext();)
        value += it.next();
    queue.clear();
    return value & 127;
}

int main(string[] args)
{
    return drain(null, cast(int) args.length);
}
