#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <pthread.h>
#include <poll.h>
#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <sys/wait.h>

#include "forkpty.h"
#include "maidpty.h"

#include "include/dart_api.h"
#include "include/dart_api_dl.h"
#include "include/dart_native_api.h"

#define PTY_SESSION_HISTORY_LIMIT (1024 * 1024)

typedef struct PtySubscriber {
    Dart_Port stdout_port;
    Dart_Port exit_port;
    struct PtySubscriber *next;
} PtySubscriber;

typedef struct PtySession {
    uint64_t id;
    int ptm;
    int pid;
    bool ack_read;
    bool read_ack_allowed;
    bool exited;
    bool destroying;
    int exit_code;
    bool reader_created;
    bool waiter_created;
    pthread_t reader_thread;
    pthread_t waiter_thread;
    pthread_mutex_t mutex;
    pthread_cond_t ack_condition;
    int wake_fds[2];
    uint8_t *history;
    size_t history_length;
    PtySubscriber *subscribers;
    struct PtySession *next;
} PtySession;

typedef struct PtyHandle {
    uint64_t session_id;
    Dart_Port stdout_port;
} PtyHandle;

typedef struct ReadLoopOptions {
    PtySession *session;
} ReadLoopOptions;

typedef struct WaitExitOptions {
    PtySession *session;
} WaitExitOptions;

static pthread_mutex_t registry_mutex = PTHREAD_MUTEX_INITIALIZER;
static PtySession *sessions = NULL;
static uint64_t next_session_id = 1;
static char *error_message = NULL;

static PtySession *find_session(uint64_t id) {
    for (PtySession *session = sessions; session != NULL; session = session->next) {
        if (session->id == id) return session;
    }
    return NULL;
}

static bool post_output(Dart_Port port, const uint8_t *buffer, size_t length) {
    if (length == 0) return true;
    Dart_CObject result;
    result.type = Dart_CObject_kTypedData;
    result.value.as_typed_data.type = Dart_TypedData_kUint8;
    result.value.as_typed_data.length = (intptr_t)length;
    result.value.as_typed_data.values = (uint8_t *)buffer;
    return Dart_PostCObject_DL(port, &result);
}

static void append_history(PtySession *session, const uint8_t *buffer, size_t length) {
    if (length >= PTY_SESSION_HISTORY_LIMIT) {
        memcpy(session->history, buffer + length - PTY_SESSION_HISTORY_LIMIT,
               PTY_SESSION_HISTORY_LIMIT);
        session->history_length = PTY_SESSION_HISTORY_LIMIT;
        return;
    }
    size_t total = session->history_length + length;
    if (total > PTY_SESSION_HISTORY_LIMIT) {
        size_t discard = total - PTY_SESSION_HISTORY_LIMIT;
        memmove(session->history, session->history + discard,
                session->history_length - discard);
        session->history_length -= discard;
    }
    memcpy(session->history + session->history_length, buffer, length);
    session->history_length += length;
}

static void *read_loop(void *arg) {
    ReadLoopOptions *options = (ReadLoopOptions *)arg;
    PtySession *session = options->session;
    free(options);
    uint8_t buffer[1024];

    while (true) {
        if (session->ack_read) {
            pthread_mutex_lock(&session->mutex);
            while (!session->read_ack_allowed && !session->destroying) {
                pthread_cond_wait(&session->ack_condition, &session->mutex);
            }
            session->read_ack_allowed = false;
            pthread_mutex_unlock(&session->mutex);
        }
        struct pollfd fds[2];
        fds[0].fd = session->ptm;
        fds[0].events = POLLIN;
        fds[1].fd = session->wake_fds[0];
        fds[1].events = POLLIN;
        int polled = poll(fds, 2, -1);
        if (polled < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if ((fds[1].revents & POLLIN) != 0) break;
        if ((fds[0].revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL)) == 0) continue;
        ssize_t length = read(session->ptm, buffer, sizeof(buffer));
        if (length < 0 && errno == EINTR) continue;
        if (length <= 0) break;

        pthread_mutex_lock(&session->mutex);
        append_history(session, buffer, (size_t)length);
        PtySubscriber **cursor = &session->subscribers;
        while (*cursor != NULL) {
            PtySubscriber *subscriber = *cursor;
            if (!post_output(subscriber->stdout_port, buffer, (size_t)length)) {
                *cursor = subscriber->next;
                free(subscriber);
                continue;
            }
            cursor = &subscriber->next;
        }
        pthread_mutex_unlock(&session->mutex);
    }

    if (session->ack_read) {
        pthread_mutex_lock(&session->mutex);
        session->read_ack_allowed = true;
        pthread_cond_broadcast(&session->ack_condition);
        pthread_mutex_unlock(&session->mutex);
    }
    return NULL;
}

static void *wait_exit_thread(void *arg) {
    WaitExitOptions *options = (WaitExitOptions *)arg;
    PtySession *session = options->session;
    free(options);

    // Poll with a timeout instead of blocking forever in waitpid so destroy
    // can wake this thread even when the child ignores SIGTERM.
    int status = 0;
    bool reaped = false;
    while (!reaped) {
        struct pollfd wake;
        wake.fd = session->wake_fds[0];
        wake.events = POLLIN;
        int polled = poll(&wake, 1, 100);
        if (polled > 0) break;
        if (polled < 0 && errno != EINTR) break;
        pid_t waited = waitpid(session->pid, &status, WNOHANG);
        if (waited == session->pid || waited < 0) reaped = true;
    }
    int exit_code = WIFEXITED(status) ? WEXITSTATUS(status)
                    : WIFSIGNALED(status) ? -WTERMSIG(status) : -1;

    pthread_mutex_lock(&session->mutex);
    if (!session->exited) {
        session->exited = true;
        session->exit_code = exit_code;
        for (PtySubscriber *subscriber = session->subscribers;
             subscriber != NULL; subscriber = subscriber->next) {
            (void)Dart_PostInteger_DL(subscriber->exit_port, exit_code);
        }
    }
    pthread_mutex_unlock(&session->mutex);
    return NULL;
}

static int start_threads(PtySession *session) {
    ReadLoopOptions *reader = malloc(sizeof(ReadLoopOptions));
    WaitExitOptions *waiter = malloc(sizeof(WaitExitOptions));
    if (reader == NULL || waiter == NULL) {
        free(reader);
        free(waiter);
        return -1;
    }
    reader->session = session;
    waiter->session = session;
    if (pthread_create(&session->reader_thread, NULL, read_loop, reader) != 0) {
        free(reader);
        free(waiter);
        return -1;
    }
    session->reader_created = true;
    if (pthread_create(&session->waiter_thread, NULL, wait_exit_thread, waiter) != 0) {
        free(waiter);
        close(session->ptm);
        session->ptm = -1;
        (void)kill(session->pid, SIGTERM);
        pthread_join(session->reader_thread, NULL);
        session->reader_created = false;
        return -1;
    }
    session->waiter_created = true;
    return 0;
}

static void free_subscribers(PtySession *session) {
    PtySubscriber *subscriber = session->subscribers;
    while (subscriber != NULL) {
        PtySubscriber *next = subscriber->next;
        free(subscriber);
        subscriber = next;
    }
    session->subscribers = NULL;
}

static void destroy_session(PtySession *session) {
    pthread_mutex_lock(&session->mutex);
    session->destroying = true;
    pthread_cond_broadcast(&session->ack_condition);
    bool exited = session->exited;
    int pid = session->pid;
    pthread_mutex_unlock(&session->mutex);

    if (!exited && pid > 0) {
        // The forkpty child called setsid, so its process group id equals
        // its pid; signal the whole group so foreground children holding
        // the slave pty die too and the master reaches EOF.
        (void)kill(-pid, SIGTERM);
    }
    // Wake the reader and waiter threads out of poll before joining them;
    // closing the master alone never unblocks them reliably.
    char wake_byte = 0;
    (void)write(session->wake_fds[1], &wake_byte, 1);

    // Close the master only after the reader exited: closing an fd while
    // another thread still polls or reads it lets the number be reused
    // mid-call by an unrelated descriptor.
    if (session->reader_created) pthread_join(session->reader_thread, NULL);
    int fd = session->ptm;
    session->ptm = -1;
    if (fd >= 0) close(fd);
    if (session->waiter_created) pthread_join(session->waiter_thread, NULL);

    free_subscribers(session);
    if (session->wake_fds[0] >= 0) close(session->wake_fds[0]);
    if (session->wake_fds[1] >= 0) close(session->wake_fds[1]);
    free(session->history);
    pthread_cond_destroy(&session->ack_condition);
    pthread_mutex_destroy(&session->mutex);
    free(session);
}

static void remove_session(PtySession *session) {
    PtySession **cursor = &sessions;
    while (*cursor != NULL) {
        if (*cursor == session) {
            *cursor = session->next;
            session->next = NULL;
            return;
        }
        cursor = &(*cursor)->next;
    }
}

static void set_environment(char **environment) {
    if (environment == NULL) return;
    while (*environment != NULL) {
        putenv(*environment);
        environment++;
    }
}

FFI_PLUGIN_EXPORT uint64_t pty_session_create(PtyOptions *options) {
    if (options == NULL || options->executable == NULL) {
        error_message = "Invalid PTY options";
        return 0;
    }

    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_row = options->rows;
    ws.ws_col = options->cols;
    ws.ws_xpixel = options->pixel_width;
    ws.ws_ypixel = options->pixel_height;

    int ptm = -1;
    int pid = pty_forkpty(&ptm, NULL, NULL, &ws);
    if (pid < 0) {
        error_message = "pty_forkpty failed";
        return 0;
    }
    if (pid == 0) {
        set_environment(options->environment);
        if (options->working_directory != NULL && strlen(options->working_directory) > 0) {
            (void)chdir(options->working_directory);
        }
        (void)execvp(options->executable, options->arguments);
        _exit(127);
    }

    PtySession *session = calloc(1, sizeof(PtySession));
    if (session == NULL) {
        (void)kill(pid, SIGTERM);
        close(ptm);
        error_message = "Failed to allocate PTY session";
        return 0;
    }
    session->history = malloc(PTY_SESSION_HISTORY_LIMIT);
    if (session->history == NULL) {
        free(session);
        (void)kill(pid, SIGTERM);
        close(ptm);
        error_message = "Failed to allocate PTY history";
        return 0;
    }
    session->wake_fds[0] = -1;
    session->wake_fds[1] = -1;
    if (pipe(session->wake_fds) != 0) {
        free(session->history);
        free(session);
        (void)kill(pid, SIGTERM);
        close(ptm);
        error_message = "Failed to create PTY wake pipe";
        return 0;
    }
    session->ptm = ptm;
    session->pid = pid;
    session->ack_read = options->ackRead;
    session->read_ack_allowed = true;
    pthread_mutex_init(&session->mutex, NULL);
    pthread_cond_init(&session->ack_condition, NULL);

    if (start_threads(session) != 0) {
        destroy_session(session);
        error_message = "Failed to start PTY threads";
        return 0;
    }

    pthread_mutex_lock(&registry_mutex);
    session->id = next_session_id++;
    if (session->id == 0) session->id = next_session_id++;
    session->next = sessions;
    sessions = session;
    pthread_mutex_unlock(&registry_mutex);
    return session->id;
}

FFI_PLUGIN_EXPORT int pty_session_attach(uint64_t session_id, Dart_Port stdout_port,
                                         Dart_Port exit_port) {
    pthread_mutex_lock(&registry_mutex);
    PtySession *session = find_session(session_id);
    if (session == NULL) {
        pthread_mutex_unlock(&registry_mutex);
        return -1;
    }
    pthread_mutex_lock(&session->mutex);
    if (session->destroying || session->exited) {
        pthread_mutex_unlock(&session->mutex);
        pthread_mutex_unlock(&registry_mutex);
        return -1;
    }
    for (PtySubscriber *item = session->subscribers; item != NULL; item = item->next) {
        if (item->stdout_port == stdout_port) {
            pthread_mutex_unlock(&session->mutex);
            pthread_mutex_unlock(&registry_mutex);
            return -1;
        }
    }
    PtySubscriber *subscriber = calloc(1, sizeof(PtySubscriber));
    if (subscriber == NULL) {
        pthread_mutex_unlock(&session->mutex);
        pthread_mutex_unlock(&registry_mutex);
        return -1;
    }
    subscriber->stdout_port = stdout_port;
    subscriber->exit_port = exit_port;
    subscriber->next = session->subscribers;
    session->subscribers = subscriber;
    static const uint8_t history_prefix[] = {0x1b, 0x63};
    if (session->history_length > 0 &&
        (!post_output(stdout_port, history_prefix, sizeof(history_prefix)) ||
         !post_output(stdout_port, session->history, session->history_length))) {
        session->subscribers = subscriber->next;
        free(subscriber);
        pthread_mutex_unlock(&session->mutex);
        pthread_mutex_unlock(&registry_mutex);
        return -1;
    }
    pthread_mutex_unlock(&session->mutex);
    pthread_mutex_unlock(&registry_mutex);
    return 0;
}

FFI_PLUGIN_EXPORT int pty_session_detach(uint64_t session_id, Dart_Port stdout_port) {
    pthread_mutex_lock(&registry_mutex);
    PtySession *session = find_session(session_id);
    if (session == NULL) {
        pthread_mutex_unlock(&registry_mutex);
        return -1;
    }
    pthread_mutex_lock(&session->mutex);
    PtySubscriber **cursor = &session->subscribers;
    while (*cursor != NULL && (*cursor)->stdout_port != stdout_port) {
        cursor = &(*cursor)->next;
    }
    if (*cursor == NULL) {
        pthread_mutex_unlock(&session->mutex);
        pthread_mutex_unlock(&registry_mutex);
        return -1;
    }
    PtySubscriber *removed = *cursor;
    *cursor = removed->next;
    free(removed);
    bool empty = session->subscribers == NULL;
    pthread_mutex_unlock(&session->mutex);
    if (empty) {
        remove_session(session);
        pthread_mutex_unlock(&registry_mutex);
        destroy_session(session);
        return 0;
    }
    pthread_mutex_unlock(&registry_mutex);
    return 0;
}

FFI_PLUGIN_EXPORT int pty_session_write(uint64_t session_id, const uint8_t *buffer, int length) {
    pthread_mutex_lock(&registry_mutex);
    PtySession *session = find_session(session_id);
    if (session == NULL || buffer == NULL || length < 0) {
        pthread_mutex_unlock(&registry_mutex);
        return -1;
    }
    int fd = session->ptm;
    ssize_t written = write(fd, buffer, (size_t)length);
    pthread_mutex_unlock(&registry_mutex);
    return written == length ? 0 : -1;
}

FFI_PLUGIN_EXPORT int pty_session_ack_read(uint64_t session_id, Dart_Port stdout_port) {
    (void)stdout_port;
    pthread_mutex_lock(&registry_mutex);
    PtySession *session = find_session(session_id);
    if (session == NULL) {
        pthread_mutex_unlock(&registry_mutex);
        return -1;
    }
    pthread_mutex_lock(&session->mutex);
    session->read_ack_allowed = true;
    pthread_cond_signal(&session->ack_condition);
    pthread_mutex_unlock(&session->mutex);
    pthread_mutex_unlock(&registry_mutex);
    return 0;
}

FFI_PLUGIN_EXPORT int pty_session_resize(uint64_t session_id, int rows, int cols,
                                         int pixel_width, int pixel_height) {
    pthread_mutex_lock(&registry_mutex);
    PtySession *session = find_session(session_id);
    if (session == NULL) {
        pthread_mutex_unlock(&registry_mutex);
        return -1;
    }
    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_row = rows;
    ws.ws_col = cols;
    ws.ws_xpixel = pixel_width;
    ws.ws_ypixel = pixel_height;
    int result = ioctl(session->ptm, TIOCSWINSZ, &ws);
    pthread_mutex_unlock(&registry_mutex);
    return result;
}

FFI_PLUGIN_EXPORT int pty_session_getpid(uint64_t session_id) {
    pthread_mutex_lock(&registry_mutex);
    PtySession *session = find_session(session_id);
    int pid = session == NULL ? -1 : session->pid;
    pthread_mutex_unlock(&registry_mutex);
    return pid;
}

FFI_PLUGIN_EXPORT int pty_session_destroy(uint64_t session_id) {
    pthread_mutex_lock(&registry_mutex);
    PtySession *session = find_session(session_id);
    if (session == NULL) {
        pthread_mutex_unlock(&registry_mutex);
        return -1;
    }
    remove_session(session);
    pthread_mutex_unlock(&registry_mutex);
    destroy_session(session);
    return 0;
}

/* Legacy single-frontend ABI. */
FFI_PLUGIN_EXPORT PtyHandle *pty_create(PtyOptions *options) {
    uint64_t id = pty_session_create(options);
    if (id == 0) return NULL;
    if (pty_session_attach(id, options->stdout_port, options->exit_port) != 0) {
        (void)pty_session_destroy(id);
        return NULL;
    }
    PtyHandle *handle = calloc(1, sizeof(PtyHandle));
    if (handle == NULL) {
        (void)pty_session_detach(id, options->stdout_port);
        return NULL;
    }
    handle->session_id = id;
    handle->stdout_port = options->stdout_port;
    return handle;
}

FFI_PLUGIN_EXPORT void pty_write(PtyHandle *handle, char *buffer, int length) {
    if (handle != NULL) (void)pty_session_write(handle->session_id, (uint8_t *)buffer, length);
}

FFI_PLUGIN_EXPORT void pty_ack_read(PtyHandle *handle) {
    if (handle != NULL) (void)pty_session_ack_read(handle->session_id, handle->stdout_port);
}

FFI_PLUGIN_EXPORT int pty_resize(PtyHandle *handle, int rows, int cols,
                                  int pixel_width, int pixel_height) {
    return handle == NULL ? -1 : pty_session_resize(handle->session_id, rows, cols,
                                                      pixel_width, pixel_height);
}

FFI_PLUGIN_EXPORT int pty_getpid(PtyHandle *handle) {
    return handle == NULL ? -1 : pty_session_getpid(handle->session_id);
}

FFI_PLUGIN_EXPORT char *pty_error(void) {
    return error_message;
}
