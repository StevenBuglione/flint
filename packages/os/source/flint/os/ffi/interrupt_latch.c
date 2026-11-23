/* Linux and Darwin signal-only side of the coordinator for SIGINT and SIGTERM. It never invokes druntime. */
#if defined(__APPLE__)
extern int *__error(void);
#define __errno_location __error
#else
extern int *__errno_location(void);
#endif
extern long write(int descriptor, const void *buffer, unsigned long length);

/* Assigned once, before installing the action, and never repurposed.
   External linkage on purpose: DMD compiles this file with ImportC, and in -lib mode it emits one
   object per function, so a `static` variable would be unreachable from the split functions. */
volatile int flint_os_interrupt_fd = -1;

void flint_os_set_interrupt_fd(int descriptor)
{
    flint_os_interrupt_fd = descriptor;
}

/* SIGINT counts in the low 32 bits and SIGTERM in the high 32, so the eventfd sum (or the Darwin pipe's
   records, summed by the reader) reports both. SIGINT is 2 and SIGTERM is 15 on Linux and Darwin. */
void flint_os_notify_interrupt(int signal_number)
{
    int *error = __errno_location();
    const int saved = *error;
    const unsigned long long notification = signal_number == 15 ? 1ULL << 32 : 1ULL;
    (void)write(flint_os_interrupt_fd, &notification, sizeof(notification));
    *error = saved;
}
