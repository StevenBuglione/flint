/* Linux signal-only side of the coordinator. It never invokes druntime. */
extern int *__errno_location(void);
extern long write(int descriptor, const void *buffer, unsigned long length);

/* Assigned once, before installing the action, and never repurposed. */
static volatile int interrupt_fd = -1;

void flint_os_set_interrupt_fd(int descriptor)
{
    interrupt_fd = descriptor;
}

void flint_os_notify_interrupt(int signal_number)
{
    (void)signal_number;
    int *error = __errno_location();
    const int saved = *error;
    const unsigned long long notification = 1;
    (void)write(interrupt_fd, &notification, sizeof(notification));
    *error = saved;
}
