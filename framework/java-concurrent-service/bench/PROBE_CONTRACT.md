# flint:java-concurrent-service probe

The default command runs two allocating Runnables on the reactor offload pool,
shuts the service down, drives it to termination and awaits termination with a
zero timeout before verifying both results. An argument requests immediate
shutdown before either Runnable starts. The probe verifies both pending
identities and their order. The provider baseline runs the same work through the
native reactor using a startup callback, then calls its own interruptible
termination wait (the same Thread/park wait the service implements) with a zero
timeout; the argument mode stops the reactor and inspects the pending work
before starting the loop. Both arms therefore link an equivalent termination
wait. Both use the same reactor settings and print zero after a successful check
in either mode.
