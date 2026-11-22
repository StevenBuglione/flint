// Linux-only libc boundary. No kernel or libc structure crosses the D ABI.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

enum {
    TERM_OK,
    TERM_UNSUPPORTED,
    TERM_CONFLICT,
    TERM_IO_ERROR,
    TERM_NO_MEMORY,
    TERM_WAIT,
    TERM_EOF,
    TERM_CANCELLED,
    TERM_RETRY,
    TERM_INPUT,
    TERM_RESIZE,
    TERM_INTERRUPT
};

enum { RAW = 1, ALTERNATE = 2, MOUSE = 4, PASTE = 8 };
enum { READ_SLAB = 32768 };

struct flint_term_native {
    int input;
    int output;
    int wake[2];
    unsigned modes;
    int snapshot;
    int watched;
    int closing;
    int closed;
    int tty_in;
    int tty_out;
    struct termios original;
    struct sigaction previous_interrupt;
    struct sigaction previous_resize;
    // Termination signals owned by this session, by index in termination_signals.
    unsigned terminating;
    struct sigaction previous_termination[2];
};

// This lock serializes changes to process-global dispositions and descriptor
// retirement. Signal handlers never acquire it.
static pthread_mutex_t lifecycle = PTHREAD_MUTEX_INITIALIZER;
static int owner_active;
static int resize_pipe[2] = { -1, -1 };
static int interrupt_pipe[2] = { -1, -1 };
static volatile sig_atomic_t resize_write = -1;
static volatile sig_atomic_t interrupt_write = -1;
// SIGTERM and SIGHUP still terminate the process. Their handler only records the signal; a
// process-lifetime restorer thread restores the owner under the lifecycle lock, then delivers
// the signal again with its default disposition.
static const int termination_signals[2] = { SIGTERM, SIGHUP };
static int termination_pipe[2] = { -1, -1 };
static volatile sig_atomic_t termination_write = -1;
static struct flint_term_native *active_owner;

static void terminal_signal(int signal_number)
{
    int saved = errno;
    int fd = signal_number == SIGWINCH ? resize_write
        : signal_number == SIGINT ? interrupt_write : termination_write;
    unsigned char byte = (unsigned char) signal_number;
    if (fd >= 0) {
        /* A full self-pipe already holds a pending wake-up, so a failed write loses nothing.
           Assigning the result keeps glibc's warn_unused_result (_FORTIFY_SOURCE) satisfied. */
        ssize_t written = write(fd, &byte, 1);
        (void) written;
    }
    errno = saved;
}

static int duplicate_stream(int fd, int flags)
{
    int copy = fcntl(fd, F_DUPFD_CLOEXEC, 3);
    if (copy < 0)
        return -1;

    int access = fcntl(copy, F_GETFL);
    if (access < 0 || (flags == O_RDONLY && (access & O_ACCMODE) == O_WRONLY)
            || (flags == O_WRONLY && (access & O_ACCMODE) == O_RDONLY)) {
        close(copy);
        return -1;
    }

    int tty = isatty(copy) == 1;
    unsigned pty_number;
    if (tty && ioctl(copy, TIOCGPTN, &pty_number) == 0)
        return copy; // Reopening a PTY master would create a different PTY.

    // Reopen nonseekable endpoints for a separate nonblocking description.
    // Ordinary files retain their existing stream offset.
    if (tty || (lseek(copy, 0, SEEK_CUR) < 0 && errno == ESPIPE)) {
        char path[64];
        int count = snprintf(path, sizeof(path), "/proc/self/fd/%d", copy);
        int replacement = count > 0 && (size_t) count < sizeof(path)
            ? open(path, flags | O_NONBLOCK | O_CLOEXEC | O_NOCTTY)
            : -1;
        if (replacement < 0 && tty && ttyname_r(copy, path, sizeof(path)) == 0)
            replacement = open(path, flags | O_NONBLOCK | O_CLOEXEC | O_NOCTTY);
        if (replacement >= 0) {
            struct stat original, reopened;
            if (fstat(copy, &original) == 0 && fstat(replacement, &reopened) == 0
                    && original.st_dev == reopened.st_dev && original.st_ino == reopened.st_ino) {
                close(copy);
                return replacement;
            }
            close(replacement);
        }
    }
    return copy;
}

static void clear_pipe(int fd)
{
    unsigned char bytes[4096];
    // Only these small, nonblocking signal pipes are ever drained here. A new
    // signal arriving during the drain is either coalesced or becomes the next event.
    for (unsigned attempt = 0; attempt < 32; ++attempt) {
        ssize_t count = read(fd, bytes, sizeof(bytes));
        if (count <= 0 && (count == 0 || errno != EINTR))
            break;
    }
}

static int init_signal_pipes(void)
{
    if (resize_pipe[0] >= 0)
        return TERM_OK;
    if (pipe2(resize_pipe, O_NONBLOCK | O_CLOEXEC) < 0)
        return TERM_IO_ERROR;
    if (pipe2(interrupt_pipe, O_NONBLOCK | O_CLOEXEC) < 0) {
        close(resize_pipe[0]);
        close(resize_pipe[1]);
        resize_pipe[0] = resize_pipe[1] = -1;
        return TERM_IO_ERROR;
    }
    // These descriptors stay valid until process exit. A handler already
    // running during sigaction restoration can never write into a reused fd.
    resize_write = resize_pipe[1];
    interrupt_write = interrupt_pipe[1];
    return TERM_OK;
}

static int restore_signal(int number, const struct sigaction *previous)
{
    struct sigaction current;
    if (sigaction(number, NULL, &current) < 0)
        return TERM_IO_ERROR;
    if (current.sa_handler != terminal_signal)
        return TERM_CONFLICT;
    return sigaction(number, previous, NULL) < 0 ? TERM_IO_ERROR : TERM_OK;
}

static int restore_terminal(struct flint_term_native *state);

static void *restore_on_termination(void *unused)
{
    (void) unused;
    sigset_t all;
    sigfillset(&all);
    (void) pthread_sigmask(SIG_BLOCK, &all, NULL);
    for (;;) {
        struct pollfd ready = { termination_pipe[0], POLLIN, 0 };
        unsigned char number;
        if (poll(&ready, 1, -1) <= 0 || read(termination_pipe[0], &number, 1) != 1)
            continue;
        pthread_mutex_lock(&lifecycle);
        if (active_owner != NULL)
            (void) restore_terminal(active_owner);
        // The handler replaced only a default disposition, so default delivery terminates as before.
        struct sigaction standard = { 0 };
        standard.sa_handler = SIG_DFL;
        sigemptyset(&standard.sa_mask);
        (void) sigaction(number, &standard, NULL);
        pthread_mutex_unlock(&lifecycle);
        (void) kill(getpid(), number);
    }
    return NULL;
}

// Called with the lifecycle lock held. Failure leaves termination signals unobserved.
static int start_restorer(void)
{
    static int started;
    if (started)
        return TERM_OK;
    if (pipe2(termination_pipe, O_NONBLOCK | O_CLOEXEC) < 0)
        return TERM_IO_ERROR;
    pthread_attr_t attributes;
    pthread_t thread;
    int created = pthread_attr_init(&attributes) == 0
        && pthread_attr_setdetachstate(&attributes, PTHREAD_CREATE_DETACHED) == 0
        && pthread_create(&thread, &attributes, restore_on_termination, NULL) == 0;
    (void) pthread_attr_destroy(&attributes);
    if (!created) {
        close(termination_pipe[0]);
        close(termination_pipe[1]);
        termination_pipe[0] = termination_pipe[1] = -1;
        return TERM_IO_ERROR;
    }
    termination_write = termination_pipe[1];
    started = 1;
    return TERM_OK;
}

// Observe only termination signals that still have their default action; an application
// handler or an ignored signal keeps its existing behavior.
static void watch_termination(struct flint_term_native *state, const struct sigaction *action)
{
    state->terminating = 0;
    if (start_restorer() != TERM_OK)
        return;
    clear_pipe(termination_pipe[0]);
    for (unsigned index = 0; index < 2; ++index) {
        int number = termination_signals[index];
        struct sigaction *previous = &state->previous_termination[index];
        if (sigaction(number, action, previous) < 0)
            continue;
        if (previous->sa_handler == SIG_DFL && !(previous->sa_flags & SA_SIGINFO))
            state->terminating |= 1U << index;
        else
            (void) sigaction(number, previous, NULL);
    }
}

static int watch_terminal(struct flint_term_native *state)
{
    if (owner_active)
        return TERM_CONFLICT;
    struct sigaction action;
    if (sigaction(SIGINT, NULL, &action) < 0)
        return TERM_IO_ERROR;
    if (action.sa_handler != SIG_DFL && action.sa_handler != SIG_IGN)
        return TERM_CONFLICT;

    int status = init_signal_pipes();
    if (status != TERM_OK)
        return status;
    clear_pipe(resize_pipe[0]);
    clear_pipe(interrupt_pipe[0]);
    action = (struct sigaction) { 0 };
    action.sa_handler = terminal_signal;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGWINCH, &action, &state->previous_resize) < 0)
        return TERM_IO_ERROR;
    if (sigaction(SIGINT, &action, &state->previous_interrupt) < 0) {
        (void) restore_signal(SIGWINCH, &state->previous_resize);
        return TERM_IO_ERROR;
    }
    if (state->previous_interrupt.sa_handler != SIG_DFL && state->previous_interrupt.sa_handler != SIG_IGN) {
        (void) restore_signal(SIGINT, &state->previous_interrupt);
        (void) restore_signal(SIGWINCH, &state->previous_resize);
        return TERM_CONFLICT;
    }
    watch_termination(state, &action);
    owner_active = 1;
    active_owner = state;
    state->watched = 1;
    return TERM_OK;
}

static void unwatch_terminal(struct flint_term_native *state, int *first)
{
    if (!state->watched)
        return;
    int resize_status = restore_signal(SIGWINCH, &state->previous_resize);
    int interrupt_status = restore_signal(SIGINT, &state->previous_interrupt);
    for (unsigned index = 0; index < 2; ++index) {
        if (state->terminating & (1U << index)) {
            int status = restore_signal(termination_signals[index], &state->previous_termination[index]);
            if (interrupt_status == TERM_OK)
                interrupt_status = status;
        }
    }
    state->terminating = 0;
    state->watched = 0;
    owner_active = 0;
    active_owner = NULL;
    if (*first == TERM_OK)
        *first = resize_status == TERM_OK ? interrupt_status : resize_status;
}

static int update_termios(int fd, const struct termios *value)
{
    int result;
    do {
        result = tcsetattr(fd, TCSANOW, value);
    } while (result < 0 && errno == EINTR);
    return result < 0 ? TERM_IO_ERROR : TERM_OK;
}

static ssize_t write_without_sigpipe(int fd, const void *bytes, size_t length)
{
    sigset_t blocked, before, pending;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGPIPE);
    int mask_error = pthread_sigmask(SIG_BLOCK, &blocked, &before);
    if (mask_error != 0) {
        errno = mask_error;
        return -1;
    }
    int known_pending = sigpending(&pending) == 0;
    int was_pending = known_pending && sigismember(&pending, SIGPIPE) == 1;
    ssize_t count = write(fd, bytes, length);
    int saved = errno;
    if (count < 0 && saved == EPIPE && known_pending && !was_pending) {
        const struct timespec zero = { 0, 0 };
        while (sigtimedwait(&blocked, NULL, &zero) < 0 && errno == EINTR) {}
    }
    (void) pthread_sigmask(SIG_SETMASK, &before, NULL);
    errno = saved;
    return count;
}

static int64_t clock_nanos(void)
{
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) < 0 || ts.tv_sec < 0)
        return -1;
    if (ts.tv_sec > (INT64_MAX - ts.tv_nsec) / 1000000000)
        return INT64_MAX;
    return (int64_t) ts.tv_sec * 1000000000 + ts.tv_nsec;
}

static int output_all(const struct flint_term_native *state, const void *bytes, size_t length, int control)
{
    const unsigned char *first = bytes;
    // A congested terminal must not make rollback or teardown hang.
    int64_t expires = 0;
    if (control) {
        int64_t now = clock_nanos();
        if (now < 0)
            return TERM_IO_ERROR;
        expires = now > INT64_MAX - 100000000 ? INT64_MAX : now + 100000000;
    }
    while (length != 0) {
        struct pollfd ready[2] = {
            { state->output, POLLOUT, 0 },
            { control ? -1 : state->wake[0], POLLIN, 0 }
        };
        int duration = -1;
        if (control) {
            int64_t now = clock_nanos();
            if (now < 0 || now >= expires)
                return TERM_IO_ERROR;
            duration = (int) ((expires - now + 999999) / 1000000);
        }
        int rc = poll(ready, 2, duration);
        if (rc < 0 && errno == EINTR)
            continue;
        if (rc <= 0)
            return TERM_IO_ERROR;
        if (ready[1].revents)
            return TERM_CANCELLED;
        if (ready[0].revents & (POLLNVAL | POLLERR | POLLHUP))
            return TERM_IO_ERROR;
        size_t batch = length < 4096 ? length : 4096;
        ssize_t count = write_without_sigpipe(state->output, first, batch);
        if (count < 0 && (errno == EINTR || errno == EAGAIN))
            continue;
        if (count <= 0)
            return TERM_IO_ERROR;
        first += count;
        length -= (size_t) count;
    }
    return TERM_OK;
}

static int write_mode(const struct flint_term_native *state, unsigned bit, int opening)
{
    switch (bit) {
    case ALTERNATE:
        if (opening)
            return output_all(state, "\x1b[?1049h", sizeof("\x1b[?1049h") - 1, 1);
        return output_all(state, "\x1b[?1049l", sizeof("\x1b[?1049l") - 1, 1);
    case MOUSE:
        if (opening)
            return output_all(state, "\x1b[?1000h\x1b[?1006h", sizeof("\x1b[?1000h\x1b[?1006h") - 1, 1);
        return output_all(state, "\x1b[?1006l\x1b[?1000l", sizeof("\x1b[?1006l\x1b[?1000l") - 1, 1);
    case PASTE:
        if (opening)
            return output_all(state, "\x1b[?2004h", sizeof("\x1b[?2004h") - 1, 1);
        return output_all(state, "\x1b[?2004l", sizeof("\x1b[?2004l") - 1, 1);
    }
    return TERM_OK;
}

static int restore_terminal(struct flint_term_native *state)
{
    int first = TERM_OK;
    for (unsigned mode = PASTE; mode >= ALTERNATE; mode >>= 1) {
        if (state->modes & mode) {
            int status = write_mode(state, mode, 0);
            if (first == TERM_OK)
                first = status;
        }
    }
    state->modes = 0;
    if (state->snapshot) {
        int status = update_termios(state->input, &state->original);
        if (first == TERM_OK)
            first = status;
        state->snapshot = 0;
    }
    unwatch_terminal(state, &first);
    return first;
}

static void close_descriptors(struct flint_term_native *state)
{
    if (state->input >= 0)
        (void) close(state->input);
    if (state->output >= 0)
        (void) close(state->output);
    if (state->wake[0] >= 0)
        (void) close(state->wake[0]);
    if (state->wake[1] >= 0)
        (void) close(state->wake[1]);
}

static int initialize_terminal(struct flint_term_native *state, unsigned modes)
{
    state->tty_in = isatty(state->input) == 1;
    state->tty_out = isatty(state->output) == 1;
    if (!state->tty_in || !state->tty_out)
        return modes & RAW ? TERM_UNSUPPORTED : TERM_OK;

    int status = watch_terminal(state);
    if (status != TERM_OK)
        return status;
    if (modes & RAW) {
        if (tcgetattr(state->input, &state->original) < 0)
            return TERM_IO_ERROR;
        struct termios raw = state->original;
        cfmakeraw(&raw);
        state->snapshot = 1;
        status = update_termios(state->input, &raw);
        if (status != TERM_OK)
            return status;
    }
    for (unsigned mode = ALTERNATE; mode <= PASTE; mode <<= 1) {
        if (modes & mode) {
            // Record ownership before the write so rollback also attempts to
            // undo any complete prefix of a partially written sequence.
            state->modes |= mode;
            status = write_mode(state, mode, 1);
            if (status != TERM_OK)
                return status;
        }
    }
    return TERM_OK;
}

int flint_term_native_open(unsigned modes, struct flint_term_native **result)
{
    if (result == NULL)
        return TERM_IO_ERROR;
    *result = NULL;
    struct flint_term_native *state = calloc(1, sizeof(*state));
    if (state == NULL)
        return TERM_NO_MEMORY;
    state->input = duplicate_stream(STDIN_FILENO, O_RDONLY);
    state->output = duplicate_stream(STDOUT_FILENO, O_WRONLY);
    state->wake[0] = state->wake[1] = -1;

    int status = TERM_IO_ERROR;
    if (state->input >= 0 && state->output >= 0
            && pipe2(state->wake, O_NONBLOCK | O_CLOEXEC) == 0) {
        pthread_mutex_lock(&lifecycle);
        status = initialize_terminal(state, modes);
        if (status != TERM_OK)
            (void) restore_terminal(state);
        pthread_mutex_unlock(&lifecycle);
    }
    if (status != TERM_OK) {
        close_descriptors(state);
        free(state);
        return status;
    }
    *result = state;
    return TERM_OK;
}

int flint_term_native_tty(const struct flint_term_native *state)
{
    return state->tty_out;
}

int flint_term_native_size(const struct flint_term_native *state, uint32_t *columns, uint32_t *rows)
{
    pthread_mutex_lock(&lifecycle);
    int status = TERM_UNSUPPORTED;
    if (state->closing) {
        status = TERM_CANCELLED;
    } else if (state->tty_out || state->tty_in) {
        struct winsize size;
        int descriptor = state->tty_out ? state->output : state->input;
        int rc = ioctl(descriptor, TIOCGWINSZ, &size);
        if (rc == 0) {
            *columns = size.ws_col;
            *rows = size.ws_row;
            status = TERM_OK;
        } else {
            status = TERM_IO_ERROR;
        }
    }
    pthread_mutex_unlock(&lifecycle);
    return status;
}

int flint_term_native_poll(const struct flint_term_native *state, int64_t timeout)
{
    struct pollfd ready[4] = {
        { state->input, POLLIN, 0 },
        { state->wake[0], POLLIN, 0 },
        { state->watched ? interrupt_pipe[0] : -1, POLLIN, 0 },
        { state->watched ? resize_pipe[0] : -1, POLLIN, 0 }
    };
    struct timespec wait = { timeout / 1000000000, timeout % 1000000000 };
    int result = ppoll(ready, 4, timeout < 0 ? NULL : &wait, NULL);
    if (result < 0)
        return errno == EINTR ? TERM_RETRY : TERM_IO_ERROR;
    if (result == 0)
        return TERM_WAIT;
    if (ready[1].revents)
        return TERM_CANCELLED;
    if (ready[2].revents & POLLIN) {
        clear_pipe(interrupt_pipe[0]);
        return TERM_INTERRUPT;
    }
    if (ready[3].revents & POLLIN) {
        clear_pipe(resize_pipe[0]);
        return TERM_RESIZE;
    }
    if (ready[0].revents & (POLLIN | POLLHUP | POLLERR))
        return TERM_INPUT;
    return TERM_IO_ERROR;
}

int flint_term_native_read(const struct flint_term_native *state, unsigned char *bytes, size_t length, size_t *written)
{
    *written = 0;
    if (bytes == NULL || length == 0 || length > READ_SLAB)
        return TERM_IO_ERROR;
    ssize_t count = read(state->input, bytes, length);
    if (count < 0 && (errno == EINTR || errno == EAGAIN))
        return TERM_RETRY;
    if (count == 0 || (count < 0 && state->tty_in && errno == EIO))
        return TERM_EOF;
    if (count < 0)
        return TERM_IO_ERROR;
    *written = (size_t) count;
    return TERM_OK;
}

int flint_term_native_write(const struct flint_term_native *state, const void *bytes, size_t length)
{
    if (length == 0)
        return TERM_OK;
    if (bytes == NULL)
        return TERM_IO_ERROR;
    return output_all(state, bytes, length, 0);
}

void flint_term_native_wake(struct flint_term_native *state)
{
    pthread_mutex_lock(&lifecycle);
    if (!state->closing) {
        state->closing = 1;
        unsigned char byte = 1;
        while (write(state->wake[1], &byte, 1) < 0 && errno == EINTR) {}
    }
    pthread_mutex_unlock(&lifecycle);
}

int flint_term_native_closing(const struct flint_term_native *state)
{
    pthread_mutex_lock(&lifecycle);
    int closing = state->closing;
    pthread_mutex_unlock(&lifecycle);
    return closing;
}

int flint_term_native_close(struct flint_term_native *state)
{
    pthread_mutex_lock(&lifecycle);
    int status = TERM_OK;
    if (!state->closed) {
        status = restore_terminal(state);
        close_descriptors(state);
        state->closed = 1;
    }
    pthread_mutex_unlock(&lifecycle);
    return status;
}

void flint_term_native_destroy(struct flint_term_native *state)
{
    free(state);
}
