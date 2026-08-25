import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One point in the statusbar's rolling history.
class SystemMetricsPoint {
  const SystemMetricsPoint({
    required this.sampledAt,
    this.cpuUsage,
    this.memoryUsage,
    this.networkDownloadBytesPerSecond,
    this.networkUploadBytesPerSecond,
    this.batteryLevel,
  });

  final DateTime sampledAt;
  final double? cpuUsage;
  final double? memoryUsage;
  final double? networkDownloadBytesPerSecond;
  final double? networkUploadBytesPerSecond;
  final double? batteryLevel;
}

/// One sample of machine activity. Values are null when the host cannot
/// expose that signal (for example, a desktop without a battery).
class SystemMetricsSnapshot {
  const SystemMetricsSnapshot({
    this.cpuUsage,
    this.memoryUsage,
    this.memoryUsedBytes,
    this.memoryTotalBytes,
    this.networkDownloadBytesPerSecond,
    this.networkUploadBytesPerSecond,
    this.batteryLevel,
    this.batteryCharging = false,
    this.history = const [],
  });

  final double? cpuUsage;
  final double? memoryUsage;
  final int? memoryUsedBytes;
  final int? memoryTotalBytes;
  final double? networkDownloadBytesPerSecond;
  final double? networkUploadBytesPerSecond;
  final double? batteryLevel;
  final bool batteryCharging;
  final List<SystemMetricsPoint> history;
}

typedef SystemMetricsQuery = ({int refreshSeconds, int historyMinutes});

final systemMetricsProvider = StreamProvider.autoDispose
    .family<SystemMetricsSnapshot, SystemMetricsQuery>((ref, query) async* {
      if (Platform.environment['FLUTTER_TEST'] == 'true') {
        yield const SystemMetricsSnapshot();
        return;
      }
      final reader = SystemMetricsReader(historyMinutes: query.historyMinutes);
      while (true) {
        yield await reader.read();
        await Future<void>.delayed(Duration(seconds: query.refreshSeconds));
      }
    });

/// Reads only host-provided counters; no shell input is accepted from users.
/// macOS is the primary target, with direct procfs readers for Linux and a
/// small PowerShell query for Windows.
class SystemMetricsReader {
  SystemMetricsReader({this.historyMinutes = 5});

  final int historyMinutes;
  final _history = <SystemMetricsPoint>[];
  int? _previousCpuTotal;
  int? _previousCpuIdle;
  int? _previousNetworkRx;
  int? _previousNetworkTx;
  DateTime? _previousSampleTime;

  Future<SystemMetricsSnapshot> read() async {
    SystemMetricsSnapshot? snapshot;
    try {
      if (Platform.isMacOS) snapshot = await _readMacOS();
      if (Platform.isLinux) snapshot = await _readLinux();
      if (Platform.isWindows) snapshot = await _readWindows();
    } on Object {
      // A metrics chip must never affect the terminal surface.
    }
    return _withHistory(snapshot ?? const SystemMetricsSnapshot());
  }

  SystemMetricsSnapshot _withHistory(SystemMetricsSnapshot snapshot) {
    final now = DateTime.now();
    _history.add(
      SystemMetricsPoint(
        sampledAt: now,
        cpuUsage: snapshot.cpuUsage,
        memoryUsage: snapshot.memoryUsage,
        networkDownloadBytesPerSecond: snapshot.networkDownloadBytesPerSecond,
        networkUploadBytesPerSecond: snapshot.networkUploadBytesPerSecond,
        batteryLevel: snapshot.batteryLevel,
      ),
    );
    final cutoff = now.subtract(Duration(minutes: historyMinutes));
    _history.removeWhere((point) => point.sampledAt.isBefore(cutoff));
    return SystemMetricsSnapshot(
      cpuUsage: snapshot.cpuUsage,
      memoryUsage: snapshot.memoryUsage,
      memoryUsedBytes: snapshot.memoryUsedBytes,
      memoryTotalBytes: snapshot.memoryTotalBytes,
      networkDownloadBytesPerSecond: snapshot.networkDownloadBytesPerSecond,
      networkUploadBytesPerSecond: snapshot.networkUploadBytesPerSecond,
      batteryLevel: snapshot.batteryLevel,
      batteryCharging: snapshot.batteryCharging,
      history: List.unmodifiable(_history),
    );
  }

  Future<SystemMetricsSnapshot> _readMacOS() async {
    final results = await Future.wait([
      Process.run('top', ['-l', '1', '-n', '0']),
      Process.run('vm_stat', const []),
      Process.run('sysctl', ['-n', 'hw.memsize']),
      Process.run('netstat', ['-ib']),
      Process.run('pmset', ['-g', 'batt']),
    ]);
    final cpu = _parseMacCpu(_stdout(results[0]));
    final memory = _parseMacMemory(_stdout(results[1]), _stdout(results[2]));
    final network = _parseMacNetwork(_stdout(results[3]));
    final battery = _parseMacBattery(_stdout(results[4]));
    final rates = _networkRates(network.$1, network.$2);
    return SystemMetricsSnapshot(
      cpuUsage: cpu,
      memoryUsage: memory.$1,
      memoryUsedBytes: memory.$2,
      memoryTotalBytes: memory.$3,
      networkDownloadBytesPerSecond: rates.$1,
      networkUploadBytesPerSecond: rates.$2,
      batteryLevel: battery?.$1,
      batteryCharging: battery?.$2 ?? false,
    );
  }

  Future<SystemMetricsSnapshot> _readLinux() async {
    final cpuText = await File('/proc/stat').readAsString();
    final memoryText = await File('/proc/meminfo').readAsString();
    final networkText = await File('/proc/net/dev').readAsString();
    final batteryFile = File('/sys/class/power_supply/BAT0/capacity');
    final batteryText = (await batteryFile.exists())
        ? await batteryFile.readAsString()
        : null;
    final cpu = _parseLinuxCpu(cpuText);
    final memory = _parseLinuxMemory(memoryText);
    final network = _parseLinuxNetwork(networkText);
    final rates = _networkRates(network.$1, network.$2);
    final battery = double.tryParse(batteryText?.trim() ?? '');
    return SystemMetricsSnapshot(
      cpuUsage: cpu,
      memoryUsage: memory.$1,
      memoryUsedBytes: memory.$2,
      memoryTotalBytes: memory.$3,
      networkDownloadBytesPerSecond: rates.$1,
      networkUploadBytesPerSecond: rates.$2,
      batteryLevel: battery == null ? null : battery / 100,
    );
  }

  Future<SystemMetricsSnapshot> _readWindows() async {
    const script = r'''
$cpu=(Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples[0].CookedValue
$os=Get-CimInstance Win32_OperatingSystem
$net=Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface
$rx=($net | Measure-Object BytesReceivedPersec -Sum).Sum
$tx=($net | Measure-Object BytesSentPersec -Sum).Sum
$bat=Get-CimInstance Win32_Battery | Select-Object -First 1
[pscustomobject]@{cpu=$cpu; total=($os.TotalVisibleMemorySize*1024); free=($os.FreePhysicalMemory*1024); rx=$rx; tx=$tx; battery=$bat.EstimatedChargeRemaining} | ConvertTo-Json -Compress
''';
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      script,
    ]);
    final value = jsonDecode(_stdout(result)) as Map<String, dynamic>;
    final cpu = _number(value['cpu']);
    final total = _integer(value['total']);
    final free = _integer(value['free']);
    final memoryUsed = total == null || free == null ? null : total - free;
    final battery = _number(value['battery']);
    return SystemMetricsSnapshot(
      cpuUsage: cpu == null ? null : (cpu.clamp(0, 100) / 100),
      memoryUsage: total == null || memoryUsed == null
          ? null
          : (memoryUsed / total).clamp(0, 1),
      memoryUsedBytes: memoryUsed,
      memoryTotalBytes: total,
      networkDownloadBytesPerSecond: _number(value['rx']),
      networkUploadBytesPerSecond: _number(value['tx']),
      batteryLevel: battery == null ? null : battery / 100,
    );
  }

  String _stdout(ProcessResult result) =>
      result.exitCode == 0 ? result.stdout.toString() : '';

  double? _parseMacCpu(String text) {
    final idle = RegExp(r'(\d+(?:\.\d+)?)% idle').firstMatch(text);
    final value = double.tryParse(idle?.group(1) ?? '');
    return value == null ? null : (100 - value).clamp(0, 100) / 100;
  }

  (double?, int?, int?) _parseMacMemory(String vmText, String totalText) {
    final total = int.tryParse(totalText.trim());
    final pageSize = int.tryParse(
      RegExp(r'page size of (\d+) bytes').firstMatch(vmText)?.group(1) ?? '',
    );
    if (total == null || pageSize == null) return (null, null, total);
    int pages(String name) =>
        int.tryParse(
          RegExp('$name:\\s+(\\d+)').firstMatch(vmText)?.group(1) ?? '',
        ) ??
        0;
    final used =
        (pages('Pages active') +
            pages('Pages inactive') +
            pages('Pages wired down') +
            pages('Pages occupied by compressor')) *
        pageSize;
    return ((used / total).clamp(0, 1), used, total);
  }

  (int, int) _parseMacNetwork(String text) {
    var rx = 0;
    var tx = 0;
    final lines = text.split('\n');
    final headerIndex = lines.indexWhere(
      (line) => line.contains('Ibytes') && line.contains('Obytes'),
    );
    if (headerIndex < 0) return (0, 0);
    final header = lines[headerIndex].trim().split(RegExp(r'\s+'));
    final rxIndex = header.indexOf('Ibytes');
    final txIndex = header.indexOf('Obytes');
    if (rxIndex < 0 || txIndex < 0) return (0, 0);
    for (final line in lines.skip(headerIndex + 1)) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length <= math.max(rxIndex, txIndex) ||
          fields.first == 'Name') {
        continue;
      }
      rx += int.tryParse(fields[rxIndex].replaceAll(',', '')) ?? 0;
      tx += int.tryParse(fields[txIndex].replaceAll(',', '')) ?? 0;
    }
    return (rx, tx);
  }

  double? _parseLinuxCpu(String text) {
    final line = text
        .split('\n')
        .firstWhere((line) => line.startsWith('cpu '), orElse: () => '');
    final values = line
        .trim()
        .split(RegExp(r'\s+'))
        .skip(1)
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    if (values.length < 5) return null;
    final total = values.fold<int>(0, (sum, value) => sum + value);
    final idle = values[3] + values[4];
    final previousTotal = _previousCpuTotal;
    final previousIdle = _previousCpuIdle;
    _previousCpuTotal = total;
    _previousCpuIdle = idle;
    if (previousTotal == null || previousIdle == null) return null;
    final totalDelta = total - previousTotal;
    final idleDelta = idle - previousIdle;
    if (totalDelta <= 0) return null;
    return (1 - idleDelta / totalDelta).clamp(0, 1);
  }

  (double?, int?, int?) _parseLinuxMemory(String text) {
    int? value(String key) {
      final match = RegExp(
        '^$key:\\s+(\\d+) kB',
        multiLine: true,
      ).firstMatch(text);
      return match == null ? null : int.parse(match.group(1)!) * 1024;
    }

    final total = value('MemTotal');
    final available = value('MemAvailable');
    if (total == null || available == null) return (null, null, total);
    final used = total - available;
    return ((used / total).clamp(0, 1), used, total);
  }

  (int, int) _parseLinuxNetwork(String text) {
    var rx = 0;
    var tx = 0;
    for (final line in text.split('\n').skip(2)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 10) continue;
      final values = parts.skip(1).map(int.tryParse).toList();
      rx += values.first ?? 0;
      tx += values[8] ?? 0;
    }
    return (rx, tx);
  }

  (double, double) _networkRates(int rx, int tx) {
    final now = DateTime.now();
    final previousTime = _previousSampleTime;
    final previousRx = _previousNetworkRx;
    final previousTx = _previousNetworkTx;
    _previousSampleTime = now;
    _previousNetworkRx = rx;
    _previousNetworkTx = tx;
    if (previousTime == null || previousRx == null || previousTx == null) {
      return (0, 0);
    }
    final seconds = now.difference(previousTime).inMilliseconds / 1000;
    if (seconds <= 0) return (0, 0);
    return (
      math.max(0, rx - previousRx) / seconds,
      math.max(0, tx - previousTx) / seconds,
    );
  }

  (double, bool)? _parseMacBattery(String text) {
    final level = double.tryParse(
      RegExp(r'(\d+)%').firstMatch(text)?.group(1) ?? '',
    );
    if (level == null) return null;
    return (
      level / 100,
      text.contains('charging') || text.contains('AC Power'),
    );
  }

  double? _number(Object? value) => switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text),
    _ => null,
  };

  int? _integer(Object? value) => switch (value) {
    num number => number.toInt(),
    String text => int.tryParse(text),
    _ => null,
  };
}
