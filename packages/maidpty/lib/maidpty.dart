import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:maidpty/src/maidpty_bindings_generated.dart';

const _libName = 'maidpty';

final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

final _bindings = MaidPtyBindings(_dylib);

final _init = _bindings.Dart_InitializeApiDL(NativeApi.initializeApiDLData);

void _ensureInitialized() {
  if (_init != 0) {
    throw StateError('Failed to initialize native bindings');
  }
}

/// Pty represents a process running in a pseudo-terminal.
///
/// [Pty.start] creates a native session. [Pty.attach] subscribes another Dart
/// frontend to that same session without spawning a second process.
class Pty {
  Pty._(this.executable, this.arguments) {
    _ensureInitialized();
    _exitPort.listen(_onExitCode);
  }

  /// Spawns a process in a pseudo-terminal.
  factory Pty.start(
    String executable, {
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 25,
    int columns = 80,
    int pixelWidth = 0,
    int pixelHeight = 0,
    bool ackRead = false,
  }) {
    final pty = Pty._(executable, List<String>.unmodifiable(arguments));
    try {
      pty._start(
        workingDirectory: workingDirectory,
        environment: environment,
        rows: rows,
        columns: columns,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        ackRead: ackRead,
      );
      return pty;
    } on Object {
      pty._closePorts();
      rethrow;
    }
  }

  /// Attaches a new Dart frontend to an existing native PTY session.
  factory Pty.attach(int sessionId) {
    final pty = Pty._('', const []);
    try {
      pty._attach(sessionId);
      return pty;
    } on Object {
      pty._closePorts();
      rethrow;
    }
  }

  final String executable;
  final List<String> arguments;
  final _stdoutPort = ReceivePort();
  final _exitPort = ReceivePort();
  final _exitCodeCompleter = Completer<int>();

  late final int _sessionId;
  bool _disposed = false;
  bool _destroyed = false;
  bool _exitReceived = false;
  bool _portsClosed = false;

  void _start({
    required String? workingDirectory,
    required Map<String, String>? environment,
    required int rows,
    required int columns,
    required int pixelWidth,
    required int pixelHeight,
    required bool ackRead,
  }) {
    final effectiveEnv = <String, String>{
      'TERM': 'xterm-256color',
      'LANG': 'en_US.UTF-8',
    };
    const envValuesToCopy = {
      'LOGNAME',
      'USER',
      'DISPLAY',
      'LC_TYPE',
      'HOME',
      'PATH',
    };
    for (final entry in Platform.environment.entries) {
      if (envValuesToCopy.contains(entry.key)) {
        effectiveEnv[entry.key] = entry.value;
      }
    }
    if (environment != null) effectiveEnv.addAll(environment);

    final argv = calloc<Pointer<Utf8>>(arguments.length + 2);
    final envp = calloc<Pointer<Utf8>>(effectiveEnv.length + 1);
    final options = calloc<PtyOptions>();
    final executablePointer = executable.toNativeUtf8();
    final workingDirectoryPointer = workingDirectory?.toNativeUtf8();
    final argumentPointers = <Pointer<Utf8>>[];
    final environmentPointers = <Pointer<Utf8>>[];
    try {
      argv[0] = executablePointer;
      for (var i = 0; i < arguments.length; i++) {
        final pointer = arguments[i].toNativeUtf8();
        argumentPointers.add(pointer);
        argv[i + 1] = pointer;
      }
      argv[arguments.length + 1] = nullptr;
      var i = 0;
      for (final entry in effectiveEnv.entries) {
        final pointer = '${entry.key}=${entry.value}'.toNativeUtf8();
        environmentPointers.add(pointer);
        envp[i++] = pointer;
      }
      envp[i] = nullptr;

      options.ref
        ..rows = rows
        ..cols = columns
        ..pixel_width = pixelWidth
        ..pixel_height = pixelHeight
        ..executable = executablePointer.cast()
        ..arguments = argv.cast()
        ..environment = envp.cast()
        ..stdout_port = _stdoutPort.sendPort.nativePort
        ..exit_port = _exitPort.sendPort.nativePort
        ..ackRead = ackRead
        ..working_directory = workingDirectoryPointer?.cast() ?? nullptr;

      final sessionId = _bindings.pty_session_create(options);
      if (sessionId == 0) {
        throw StateError('Failed to create PTY: ${_getPtyError()}');
      }
      try {
        _attach(sessionId);
      } on Object {
        _bindings.pty_session_destroy(sessionId);
        rethrow;
      }
    } finally {
      calloc.free(options);
      calloc.free(argv);
      calloc.free(envp);
      malloc.free(executablePointer);
      if (workingDirectoryPointer != null) malloc.free(workingDirectoryPointer);
      for (final pointer in argumentPointers) {
        malloc.free(pointer);
      }
      for (final pointer in environmentPointers) {
        malloc.free(pointer);
      }
    }
  }

  void _attach(int sessionId) {
    if (sessionId == 0 ||
        _bindings.pty_session_attach(
              sessionId,
              _stdoutPort.sendPort.nativePort,
              _exitPort.sendPort.nativePort,
            ) !=
            0) {
      throw StateError('Failed to attach to PTY session $sessionId');
    }
    _sessionId = sessionId;
  }

  /// Stable process-wide native session ID.
  int get sessionId => _sessionId;

  /// The output stream from the pseudo-terminal.
  Stream<Uint8List> get output => _stdoutPort.cast();

  /// Completes with the process exit code.
  Future<int> get exitCode => _exitCodeCompleter.future;

  /// Process ID of the native session.
  int get pid => _bindings.pty_session_getpid(_sessionId);

  /// Writes data to the existing pseudo-terminal.
  void write(Uint8List data) {
    if (_disposed || _destroyed) return;
    final buffer = malloc<Uint8>(data.length);
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      _bindings.pty_session_write(_sessionId, buffer, data.length);
    } finally {
      malloc.free(buffer);
    }
  }

  /// Resizes the existing pseudo-terminal.
  void resize(int rows, int cols, {int pixelWidth = 0, int pixelHeight = 0}) {
    if (_disposed || _destroyed) return;
    _bindings.pty_session_resize(
      _sessionId,
      rows,
      cols,
      pixelWidth,
      pixelHeight,
    );
  }

  /// Detaches only this Dart frontend.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _bindings.pty_session_detach(_sessionId, _stdoutPort.sendPort.nativePort);
    _closePorts();
  }

  /// Explicitly destroys the native session and its child process.
  Future<void> destroy() async {
    if (_destroyed) return;
    _destroyed = true;
    _bindings.pty_session_destroy(_sessionId);
    _disposed = true;
    _closePorts();
  }

  /// Sends [signal] to the process without detaching this frontend.
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    final processId = pid;
    if (processId <= 0) return false;
    return Process.killPid(processId, signal);
  }

  /// Acknowledges a data chunk when the legacy ack mode is enabled.
  void ackRead() {
    if (!_disposed && !_destroyed) {
      _bindings.pty_session_ack_read(
          _sessionId, _stdoutPort.sendPort.nativePort);
    }
  }

  void _onExitCode(dynamic value) {
    if (_exitReceived) return;
    _exitReceived = true;
    final code = value is int ? value : int.parse('$value');
    if (!_exitCodeCompleter.isCompleted) _exitCodeCompleter.complete(code);
    if (!_disposed && !_destroyed) {
      _disposed = true;
      _bindings.pty_session_detach(_sessionId, _stdoutPort.sendPort.nativePort);
    }
    _closePorts();
  }

  void _closePorts() {
    if (_portsClosed) return;
    _portsClosed = true;
    _stdoutPort.close();
    _exitPort.close();
  }
}

String? _getPtyError() {
  final error = _bindings.pty_error();
  if (error == nullptr) return null;
  return error.cast<Utf8>().toDartString();
}
