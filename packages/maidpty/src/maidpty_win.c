#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <Windows.h>

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
    HANDLE input_write;
    HANDLE output_read;
    HANDLE process;
    HPCON pty;
    DWORD pid;
    BOOL ack_read;
    BOOL exited;
    BOOL destroying;
    int exit_code;
    HANDLE reader_thread;
    HANDLE waiter_thread;
    CRITICAL_SECTION mutex;
    uint8_t *history;
    size_t history_length;
    PtySubscriber *subscribers;
    struct PtySession *next;
} PtySession;

typedef struct PtyHandle {
    uint64_t session_id;
    Dart_Port stdout_port;
} PtyHandle;

typedef struct ThreadOptions {
    PtySession *session;
} ThreadOptions;

static INIT_ONCE registry_once = INIT_ONCE_STATIC_INIT;
static CRITICAL_SECTION registry_mutex;
static PtySession *sessions = NULL;
static uint64_t next_session_id = 1;
static char *error_message = NULL;

static BOOL CALLBACK initialize_registry(PINIT_ONCE once, PVOID parameter, PVOID *context) {
    (void)once;
    (void)parameter;
    (void)context;
    InitializeCriticalSection(&registry_mutex);
    return TRUE;
}

static void ensure_registry(void) {
    InitOnceExecuteOnce(&registry_once, initialize_registry, NULL, NULL);
}

static PtySession *find_session(uint64_t id) {
    for (PtySession *session = sessions; session != NULL; session = session->next) {
        if (session->id == id) return session;
    }
    return NULL;
}

static BOOL post_output(Dart_Port port, const uint8_t *buffer, size_t length) {
    if (length == 0) return TRUE;
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

static DWORD WINAPI read_loop(LPVOID argument) {
    ThreadOptions *options = (ThreadOptions *)argument;
    PtySession *session = options->session;
    free(options);

    uint8_t buffer[1024];
    while (true) {
        DWORD length = 0;
        if (!ReadFile(session->output_read, buffer, sizeof(buffer), &length, NULL)) break;
        if (length == 0) break;
        EnterCriticalSection(&session->mutex);
        append_history(session, buffer, length);
        PtySubscriber **cursor = &session->subscribers;
        while (*cursor != NULL) {
            PtySubscriber *subscriber = *cursor;
            if (!post_output(subscriber->stdout_port, buffer, length)) {
                *cursor = subscriber->next;
                free(subscriber);
                continue;
            }
            cursor = &subscriber->next;
        }
        LeaveCriticalSection(&session->mutex);
    }
    return 0;
}

static DWORD WINAPI wait_exit_loop(LPVOID argument) {
    ThreadOptions *options = (ThreadOptions *)argument;
    PtySession *session = options->session;
    free(options);

    WaitForSingleObject(session->process, INFINITE);
    DWORD exit_code = 1;
    GetExitCodeProcess(session->process, &exit_code);
    EnterCriticalSection(&session->mutex);
    if (!session->exited) {
        session->exited = TRUE;
        session->exit_code = (int)exit_code;
        for (PtySubscriber *subscriber = session->subscribers;
             subscriber != NULL; subscriber = subscriber->next) {
            (void)Dart_PostInteger_DL(subscriber->exit_port, session->exit_code);
        }
    }
    LeaveCriticalSection(&session->mutex);
    return 0;
}

static LPWSTR build_command(char *executable, char **arguments) {
    int length = executable == NULL ? 0 : (int)strlen(executable);
    if (arguments != NULL) {
        for (int i = 0; arguments[i] != NULL; i++) length += (int)strlen(arguments[i]) + 1;
    }
    LPWSTR command = calloc((size_t)length + 1, sizeof(WCHAR));
    if (command == NULL) return NULL;
    int cursor = 0;
    if (executable != NULL) {
        for (int i = 0; executable[i] != 0; i++) command[cursor++] = (WCHAR)executable[i];
    }
    if (arguments != NULL) {
        for (int i = 0; arguments[i] != NULL; i++) {
            command[cursor++] = L' ';
            for (int j = 0; arguments[i][j] != 0; j++) command[cursor++] = (WCHAR)arguments[i][j];
        }
    }
    return command;
}

static LPWSTR build_environment(char **environment) {
    int length = 0;
    if (environment != NULL) {
        for (int i = 0; environment[i] != NULL; i++) length += (int)strlen(environment[i]) + 1;
    }
    LPWSTR block = calloc((size_t)length + 1, sizeof(WCHAR));
    if (block == NULL) return NULL;
    int cursor = 0;
    if (environment != NULL) {
        for (int i = 0; environment[i] != NULL; i++) {
            for (int j = 0; environment[i][j] != 0; j++) block[cursor++] = (WCHAR)environment[i][j];
            block[cursor++] = 0;
        }
    }
    block[cursor] = 0;
    return block;
}

static LPWSTR build_working_directory(char *working_directory) {
    if (working_directory == NULL) return NULL;
    int length = (int)strlen(working_directory);
    LPWSTR result = calloc((size_t)length + 1, sizeof(WCHAR));
    if (result == NULL) return NULL;
    for (int i = 0; i < length; i++) result[i] = (WCHAR)working_directory[i];
    return result;
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
    EnterCriticalSection(&session->mutex);
    session->destroying = TRUE;
    BOOL exited = session->exited;
    HANDLE process = session->process;
    LeaveCriticalSection(&session->mutex);

    if (!exited) TerminateProcess(process, 1);
    if (session->reader_thread != NULL) WaitForSingleObject(session->reader_thread, INFINITE);
    if (session->waiter_thread != NULL) WaitForSingleObject(session->waiter_thread, INFINITE);
    if (session->reader_thread != NULL) CloseHandle(session->reader_thread);
    if (session->waiter_thread != NULL) CloseHandle(session->waiter_thread);
    if (session->input_write != NULL) CloseHandle(session->input_write);
    if (session->output_read != NULL) CloseHandle(session->output_read);
    if (session->process != NULL) CloseHandle(session->process);
    if (session->pty != NULL) ClosePseudoConsole(session->pty);
    free_subscribers(session);
    free(session->history);
    DeleteCriticalSection(&session->mutex);
    free(session);
}

FFI_PLUGIN_EXPORT uint64_t pty_session_create(PtyOptions *options) {
    ensure_registry();
    if (options == NULL || options->executable == NULL) {
        error_message = "Invalid PTY options";
        return 0;
    }

    HANDLE input_read = NULL, input_write = NULL;
    HANDLE output_read = NULL, output_write = NULL;
    if (!CreatePipe(&input_read, &input_write, NULL, 0) ||
        !CreatePipe(&output_read, &output_write, NULL, 0)) {
        error_message = "Failed to create PTY pipes";
        return 0;
    }
    COORD size = {(SHORT)options->cols, (SHORT)options->rows};
    HPCON pty = NULL;
    if (FAILED(CreatePseudoConsole(size, input_read, output_write, 0, &pty))) {
        error_message = "Failed to create pseudo console";
        CloseHandle(input_read); CloseHandle(input_write);
        CloseHandle(output_read); CloseHandle(output_write);
        return 0;
    }
    CloseHandle(input_read);
    CloseHandle(output_write);

    STARTUPINFOEXW startup;
    ZeroMemory(&startup, sizeof(startup));
    startup.StartupInfo.cb = sizeof(startup);
    SIZE_T bytes_required = 0;
    InitializeProcThreadAttributeList(NULL, 1, 0, &bytes_required);
    startup.lpAttributeList = calloc(1, bytes_required);
    if (startup.lpAttributeList == NULL ||
        !InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, &bytes_required) ||
        !UpdateProcThreadAttribute(startup.lpAttributeList, 0,
                                   PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, &pty,
                                   sizeof(pty), NULL, NULL)) {
        error_message = "Failed to configure pseudo console process";
        free(startup.lpAttributeList);
        ClosePseudoConsole(pty);
        CloseHandle(input_write); CloseHandle(output_read);
        return 0;
    }

    LPWSTR command = build_command(options->executable, options->arguments);
    LPWSTR environment = build_environment(options->environment);
    LPWSTR working_directory = build_working_directory(options->working_directory);
    PROCESS_INFORMATION process_info;
    ZeroMemory(&process_info, sizeof(process_info));
    BOOL created = CreateProcessW(NULL, command, NULL, NULL, FALSE,
                                  EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                                  environment, working_directory,
                                  &startup.StartupInfo, &process_info);
    free(command); free(environment); free(working_directory);
    DeleteProcThreadAttributeList(startup.lpAttributeList);
    free(startup.lpAttributeList);
    if (!created) {
        error_message = "Failed to create process";
        ClosePseudoConsole(pty);
        CloseHandle(input_write); CloseHandle(output_read);
        return 0;
    }
    CloseHandle(process_info.hThread);

    PtySession *session = calloc(1, sizeof(PtySession));
    if (session == NULL) {
        TerminateProcess(process_info.hProcess, 1);
        CloseHandle(process_info.hProcess);
        ClosePseudoConsole(pty);
        CloseHandle(input_write); CloseHandle(output_read);
        error_message = "Failed to allocate PTY session";
        return 0;
    }
    session->history = malloc(PTY_SESSION_HISTORY_LIMIT);
    if (session->history == NULL) {
        free(session);
        TerminateProcess(process_info.hProcess, 1);
        CloseHandle(process_info.hProcess);
        ClosePseudoConsole(pty);
        CloseHandle(input_write); CloseHandle(output_read);
        error_message = "Failed to allocate PTY history";
        return 0;
    }
    session->input_write = input_write;
    session->output_read = output_read;
    session->process = process_info.hProcess;
    session->pty = pty;
    session->pid = process_info.dwProcessId;
    session->ack_read = options->ackRead;
    InitializeCriticalSection(&session->mutex);

    ThreadOptions *reader_options = malloc(sizeof(ThreadOptions));
    ThreadOptions *waiter_options = malloc(sizeof(ThreadOptions));
    if (reader_options == NULL || waiter_options == NULL) {
        free(reader_options); free(waiter_options);
        destroy_session(session);
        error_message = "Failed to allocate PTY thread options";
        return 0;
    }
    reader_options->session = session;
    waiter_options->session = session;
    session->reader_thread = CreateThread(NULL, 0, read_loop, reader_options, 0, NULL);
    session->waiter_thread = CreateThread(NULL, 0, wait_exit_loop, waiter_options, 0, NULL);
    if (session->reader_thread == NULL || session->waiter_thread == NULL) {
        free(reader_options); free(waiter_options);
        destroy_session(session);
        error_message = "Failed to start PTY threads";
        return 0;
    }

    EnterCriticalSection(&registry_mutex);
    session->id = next_session_id++;
    if (session->id == 0) session->id = next_session_id++;
    session->next = sessions;
    sessions = session;
    LeaveCriticalSection(&registry_mutex);
    return session->id;
}

FFI_PLUGIN_EXPORT int pty_session_attach(uint64_t session_id, Dart_Port stdout_port,
                                         Dart_Port exit_port) {
    ensure_registry();
    EnterCriticalSection(&registry_mutex);
    PtySession *session = find_session(session_id);
    if (session == NULL) {
        LeaveCriticalSection(&registry_mutex);
        return -1;
    }
    EnterCriticalSection(&session->mutex);
    if (session->destroying || session->exited) {
        LeaveCriticalSection(&session->mutex); LeaveCriticalSection(&registry_mutex);
        return -1;
    }
    for (PtySubscriber *item = session->subscribers; item != NULL; item = item->next) {
        if (item->stdout_port == stdout_port) {
            LeaveCriticalSection(&session->mutex); LeaveCriticalSection(&registry_mutex);
            return -1;
        }
    }
    PtySubscriber *subscriber = calloc(1, sizeof(PtySubscriber));
    if (subscriber == NULL) {
        LeaveCriticalSection(&session->mutex); LeaveCriticalSection(&registry_mutex);
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
        LeaveCriticalSection(&session->mutex);
        LeaveCriticalSection(&registry_mutex);
        return -1;
    }
    LeaveCriticalSection(&session->mutex);
    LeaveCriticalSection(&registry_mutex);
    return 0;
}

FFI_PLUGIN_EXPORT int pty_session_detach(uint64_t session_id, Dart_Port stdout_port) {
    ensure_registry();
    EnterCriticalSection(&registry_mutex);
    PtySession *session = find_session(session_id);
    if (session == NULL) { LeaveCriticalSection(&registry_mutex); return -1; }
    EnterCriticalSection(&session->mutex);
    PtySubscriber **cursor = &session->subscribers;
    while (*cursor != NULL && (*cursor)->stdout_port != stdout_port) cursor = &(*cursor)->next;
    if (*cursor == NULL) {
        LeaveCriticalSection(&session->mutex); LeaveCriticalSection(&registry_mutex); return -1;
    }
    PtySubscriber *removed = *cursor;
    *cursor = removed->next;
    free(removed);
    BOOL empty = session->subscribers == NULL;
    LeaveCriticalSection(&session->mutex);
    if (empty) {
        remove_session(session);
        LeaveCriticalSection(&registry_mutex);
        destroy_session(session);
        return 0;
    }
    LeaveCriticalSection(&registry_mutex);
    return 0;
}

FFI_PLUGIN_EXPORT int pty_session_write(uint64_t session_id, const uint8_t *buffer, int length) {
    ensure_registry();
    EnterCriticalSection(&registry_mutex);
    PtySession *session = find_session(session_id);
    if (session == NULL || buffer == NULL || length < 0) {
        LeaveCriticalSection(&registry_mutex); return -1;
    }
    DWORD written = 0;
    BOOL ok = WriteFile(session->input_write, buffer, (DWORD)length, &written, NULL);
    FlushFileBuffers(session->input_write);
    LeaveCriticalSection(&registry_mutex);
    return ok && written == (DWORD)length ? 0 : -1;
}

FFI_PLUGIN_EXPORT int pty_session_ack_read(uint64_t session_id, Dart_Port stdout_port) {
    (void)session_id; (void)stdout_port;
    return 0;
}

FFI_PLUGIN_EXPORT int pty_session_resize(uint64_t session_id, int rows, int cols,
                                         int pixel_width, int pixel_height) {
    (void)pixel_width; (void)pixel_height;
    ensure_registry();
    EnterCriticalSection(&registry_mutex);
    PtySession *session = find_session(session_id);
    if (session == NULL) { LeaveCriticalSection(&registry_mutex); return -1; }
    COORD size = {(SHORT)cols, (SHORT)rows};
    HRESULT result = ResizePseudoConsole(session->pty, size);
    LeaveCriticalSection(&registry_mutex);
    return FAILED(result) ? -1 : 0;
}

FFI_PLUGIN_EXPORT int pty_session_getpid(uint64_t session_id) {
    ensure_registry();
    EnterCriticalSection(&registry_mutex);
    PtySession *session = find_session(session_id);
    int pid = session == NULL ? -1 : (int)session->pid;
    LeaveCriticalSection(&registry_mutex);
    return pid;
}

FFI_PLUGIN_EXPORT int pty_session_destroy(uint64_t session_id) {
    ensure_registry();
    EnterCriticalSection(&registry_mutex);
    PtySession *session = find_session(session_id);
    if (session == NULL) { LeaveCriticalSection(&registry_mutex); return -1; }
    remove_session(session);
    LeaveCriticalSection(&registry_mutex);
    destroy_session(session);
    return 0;
}

FFI_PLUGIN_EXPORT PtyHandle *pty_create(PtyOptions *options) {
    uint64_t id = pty_session_create(options);
    if (id == 0 || pty_session_attach(id, options->stdout_port, options->exit_port) != 0) {
        if (id != 0) pty_session_destroy(id);
        return NULL;
    }
    PtyHandle *handle = calloc(1, sizeof(PtyHandle));
    if (handle == NULL) {
        pty_session_detach(id, options->stdout_port);
        return NULL;
    }
    handle->session_id = id;
    handle->stdout_port = options->stdout_port;
    return handle;
}

FFI_PLUGIN_EXPORT void pty_write(PtyHandle *handle, char *buffer, int length) {
    if (handle != NULL) pty_session_write(handle->session_id, (uint8_t *)buffer, length);
}

FFI_PLUGIN_EXPORT void pty_ack_read(PtyHandle *handle) {
    if (handle != NULL) pty_session_ack_read(handle->session_id, handle->stdout_port);
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
