# flint:java-concurrent-service probe

The default command runs two allocating Runnables on the reactor offload pool
and verifies their results. An argument requests immediate shutdown before
either Runnable starts. The probe verifies both pending identities and their
order. The provider baseline runs the same work through the native reactor
using a startup callback, or stops the reactor and inspects the pending work
before starting the loop. Both use the same reactor settings and print zero
after a successful check in either mode.
