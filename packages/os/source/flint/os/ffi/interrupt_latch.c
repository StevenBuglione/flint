/* Linux signal-only side of the coordinator. It never invokes druntime. */
extern int *__errno_location(void);
extern long write(int descriptor, const void *buffer, unsigned long length);

/* Assigned once, before installing the action, and never repurposed.
   External linkage on purpose: DMD compiles this file with ImportC, and in -lib mode it emits one
   object per function, so a `static` variable would be unreachable from the split functions. */
volatile int flint_os_interrupt_fd = -1;

void flint_os_set_interrupt_fd(int descriptor)
{
    flint_os_interrupt_fd = descriptor;
}

void flint_os_notify_interrupt(int signal_number)
{
    (void)signal_number;
    int *error = __errno_location();
    const int saved = *error;
    const unsigned long long notification = 1;
    (void)write(flint_os_interrupt_fd, &notification, sizeof(notification));
    *error = saved;
}
