import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../settings/terminal_settings.dart';
import 'system_metrics.dart';

const _machineStatusBarHeight = 48.0;

/// A docked, pill-shaped readout for the signals users tend to glance at
/// while working in a terminal. Its row is given real layout space by the
/// workspace, and every visible signal receives the same width.
class MachineStatusBar extends ConsumerWidget {
  const MachineStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(terminalSettingsProvider).value;
    if (settings == null || !settings.showStatusBar) {
      return const SizedBox.shrink();
    }
    final snapshot = ref
        .watch(systemMetricsProvider(settings.statusBarRefreshSeconds))
        .value;
    final visibleMetrics = settings.statusBarMetrics
        .where(
          (metric) =>
              metric != StatusMetric.battery || snapshot?.batteryLevel != null,
        )
        .toList();
    if (visibleMetrics.isEmpty) {
      return const SizedBox(height: _machineStatusBarHeight);
    }

    return SizedBox(
      height: _machineStatusBarHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 5, 18, 7),
        child: Tooltip(
          message:
              'Machine status · updates every ${settings.statusBarRefreshSeconds}s',
          waitDuration: const Duration(milliseconds: 500),
          child: Row(
            children: [
              for (final metric in visibleMetrics)
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _Metric(
                        metric: metric,
                        snapshot: snapshot ?? const SystemMetricsSnapshot(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.metric, required this.snapshot});

  final StatusMetric metric;
  final SystemMetricsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final spec = switch (metric) {
      StatusMetric.cpu => (
        icon: Symbols.speed,
        value: _percentage(snapshot.cpuUsage),
        progress: snapshot.cpuUsage,
        color: const Color(0xFFB9D77A),
      ),
      StatusMetric.memory => (
        icon: Symbols.memory,
        value: _memoryValue(snapshot),
        progress: snapshot.memoryUsage,
        color: const Color(0xFF8BC7D8),
      ),
      StatusMetric.network => (
        icon: Symbols.swap_vert,
        value:
            '${_rate(snapshot.networkDownloadBytesPerSecond)}  ${_rate(snapshot.networkUploadBytesPerSecond)}',
        progress: _networkProgress(snapshot),
        color: const Color(0xFFE5A9C9),
      ),
      StatusMetric.battery => (
        icon: snapshot.batteryCharging
            ? Symbols.battery_charging_full
            : Symbols.battery_full,
        value: _percentage(snapshot.batteryLevel),
        progress: snapshot.batteryLevel,
        color: const Color(0xFFE7B66D),
      ),
    };
    final textTheme = Theme.of(context).textTheme;
    final mono = textTheme.labelMedium?.copyWith(
      fontFamily: 'IBM Plex Mono',
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: 0.2,
      fontWeight: FontWeight.w600,
      color: spec.color,
    );
    final valueWidget = metric == StatusMetric.network
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '↑ ${_rate(snapshot.networkUploadBytesPerSecond)}',
                style: mono,
              ),
              Text(
                '↓ ${_rate(snapshot.networkDownloadBytesPerSecond)}',
                style: mono,
              ),
            ],
          )
        : Text(spec.value, style: mono);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(spec.icon, size: 17, color: spec.color),
        const SizedBox(width: 7),
        valueWidget,
        const SizedBox(width: 9),
        SizedBox(
          width: metric == StatusMetric.network ? 42 : 32,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 3,
              value: spec.progress,
              backgroundColor: spec.color.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation(spec.color),
            ),
          ),
        ),
      ],
    );
  }
}

String _percentage(double? value) =>
    value == null ? '—' : '${(value.clamp(0, 1) * 100).round()}%';

String _memoryValue(SystemMetricsSnapshot snapshot) {
  final used = snapshot.memoryUsedBytes;
  final total = snapshot.memoryTotalBytes;
  if (used == null || total == null) return _percentage(snapshot.memoryUsage);
  return '${_bytes(used)} / ${_bytes(total)}';
}

String _rate(double? bytes) {
  if (bytes == null || bytes < 1024) return '${(bytes ?? 0).round()} B/s';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} K/s';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} M/s';
}

String _bytes(int bytes) {
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

double? _networkProgress(SystemMetricsSnapshot snapshot) {
  final total =
      (snapshot.networkDownloadBytesPerSecond ?? 0) +
      (snapshot.networkUploadBytesPerSecond ?? 0);
  if (total <= 0) return 0;
  return (math.log(total + 1) / math.log(1024 * 1024 * 10)).clamp(0, 1);
}
