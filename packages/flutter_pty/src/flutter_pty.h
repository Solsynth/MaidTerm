#ifndef FLUTTER_PTY_H_
#define FLUTTER_PTY_H_

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

#include <stdbool.h>
#include <stdint.h>

#if defined(__linux__) || defined(__GLIBC__) || defined(__GNU__)
#define _GNU_SOURCE /* GNU glibc grantpt() prototypes */
#endif

#include "include/dart_api_dl.h"

typedef struct PtyOptions
{
    int rows;

    int cols;

    int pixel_width;

    int pixel_height;

    char *executable;

    char **arguments;

    char **environment;

    char *working_directory;

    Dart_Port stdout_port;

    Dart_Port exit_port;

    bool ackRead;

} PtyOptions;

typedef struct PtyHandle PtyHandle;

FFI_PLUGIN_EXPORT uint64_t pty_session_create(PtyOptions *options);

FFI_PLUGIN_EXPORT int pty_session_attach(uint64_t session_id, Dart_Port stdout_port, Dart_Port exit_port);

FFI_PLUGIN_EXPORT int pty_session_detach(uint64_t session_id, Dart_Port stdout_port);

FFI_PLUGIN_EXPORT int pty_session_write(uint64_t session_id, const uint8_t *buffer, int length);

FFI_PLUGIN_EXPORT int pty_session_ack_read(uint64_t session_id, Dart_Port stdout_port);

FFI_PLUGIN_EXPORT int pty_session_resize(uint64_t session_id, int rows, int cols, int pixel_width, int pixel_height);

FFI_PLUGIN_EXPORT int pty_session_getpid(uint64_t session_id);

FFI_PLUGIN_EXPORT int pty_session_destroy(uint64_t session_id);

FFI_PLUGIN_EXPORT PtyHandle *pty_create(PtyOptions *options);

FFI_PLUGIN_EXPORT void pty_write(PtyHandle *handle, char *buffer, int length);

FFI_PLUGIN_EXPORT void pty_ack_read(PtyHandle *handle);

FFI_PLUGIN_EXPORT int pty_resize(PtyHandle *handle, int rows, int cols, int pixel_width, int pixel_height);

FFI_PLUGIN_EXPORT int pty_getpid(PtyHandle *handle);

FFI_PLUGIN_EXPORT char *pty_error(void);

#endif