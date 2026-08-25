import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../settings/terminal_settings.dart';
import '../shell/process_title_monitor.dart';
import 'system_metrics.dart';
import 'terminal_workspace.dart';

const _machineStatusBarHeight = 40.0;

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
        .watch(
          systemMetricsProvider((
            refreshSeconds: settings.statusBarRefreshSeconds,
            historyMinutes: settings.statusBarHistoryMinutes,
          )),
        )
        .value;
    final workspace = ref.watch(terminalWorkspaceProvider);
    final monitor = ref.watch(processTitleMonitorProvider);
    return ValueListenableBuilder<int>(
      valueListenable: monitor.revision,
      builder: (context, _, _) => _buildBar(
        context,
        settings: settings,
        snapshot: snapshot,
        workspace: workspace,
        monitor: monitor,
      ),
    );
  }

  Widget _buildBar(
    BuildContext context, {
    required TerminalSettings settings,
    required SystemMetricsSnapshot? snapshot,
    required TerminalWorkspaceState workspace,
    required ProcessTitleMonitor monitor,
  }) {
    final visibleMetrics = settings.statusBarMetrics
        .where(
          (metric) =>
              metric != StatusMetric.battery || snapshot?.batteryLevel != null,
        )
        .toList();
    if (visibleMetrics.isEmpty) {
      return const SizedBox(height: _machineStatusBarHeight);
    }
    final focusedPid = workspace.focusedPane?.tab.ptyPid;
    final focusedMemoryBytes = focusedPid == null
        ? null
        : monitor.foregroundMemoryBytes(focusedPid);

    return SizedBox(
      height: _machineStatusBarHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 3, 12, 5),
        child: Tooltip(
          message:
              'Machine status · ${settings.statusBarHistoryMinutes}m history',
          waitDuration: const Duration(milliseconds: 500),
          child: Row(
            children: [
              for (final metric in visibleMetrics)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    child: _Metric(
                      metric: metric,
                      snapshot: snapshot ?? const SystemMetricsSnapshot(),
                      focusedMemoryBytes: focusedMemoryBytes,
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
  const _Metric({
    required this.metric,
    required this.snapshot,
    required this.focusedMemoryBytes,
  });

  final StatusMetric metric;
  final SystemMetricsSnapshot snapshot;
  final int? focusedMemoryBytes;

  @override
  Widget build(BuildContext context) {
    final spec = switch (metric) {
      StatusMetric.cpu => (
        icon: Symbols.speed,
        value: _percentage(snapshot.cpuUsage),
        color: const Color(0xFFB9D77A),
      ),
      StatusMetric.memory => (
        icon: Symbols.memory,
        value: _memoryValue(snapshot),
        color: const Color(0xFF8BC7D8),
      ),
      StatusMetric.network => (
        icon: Symbols.swap_vert,
        value: '',
        color: const Color(0xFFE5A9C9),
      ),
      StatusMetric.battery => (
        icon: snapshot.batteryCharging
            ? Symbols.battery_charging_full
            : Symbols.battery_full,
        value: _percentage(snapshot.batteryLevel),
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
    final valueWidget = switch (metric) {
      StatusMetric.memory => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_memoryValue(snapshot), style: mono),
          Text(
            _bytesOrDash(focusedMemoryBytes),
            style: mono?.copyWith(
              color: spec.color.withValues(alpha: 0.68),
              fontSize: (mono.fontSize ?? 12) - 1,
            ),
          ),
        ],
      ),
      StatusMetric.network => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('↑ ${_rate(snapshot.networkUploadBytesPerSecond)}', style: mono),
          Text(
            '↓ ${_rate(snapshot.networkDownloadBytesPerSecond)}',
            style: mono,
          ),
        ],
      ),
      _ => Text(spec.value, style: mono),
    };
    return Row(
      children: [
        Icon(spec.icon, size: 16, color: spec.color),
        const SizedBox(width: 6),
        Flexible(
          fit: FlexFit.loose,
          child: FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: valueWidget,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricChart(
            metric: metric,
            snapshot: snapshot,
            color: spec.color,
          ),
        ),
      ],
    );
  }
}

class _MetricChart extends StatelessWidget {
  const _MetricChart({
    required this.metric,
    required this.snapshot,
    required this.color,
  });

  final StatusMetric metric;
  final SystemMetricsSnapshot snapshot;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final history = snapshot.history;
    final values = history
        .map((point) => _historyValue(metric, point))
        .whereType<double>()
        .toList();
    final current = _metricValue(metric, snapshot);
    final valuesWithFallback = values.isEmpty
        ? [current ?? 0, current ?? 0]
        : values.length == 1
        ? [values.first, values.first]
        : values;
    final spots = [
      for (var index = 0; index < valuesWithFallback.length; index++)
        FlSpot(index.toDouble(), valuesWithFallback[index].clamp(0, 1)),
    ];
    return SizedBox(
      height: metric == StatusMetric.network ? 24 : 20,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: math.max(1, spots.length - 1).toDouble(),
          minY: 0,
          maxY: 1,
          lineTouchData: const LineTouchData(enabled: false),
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 1.6,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double? _metricValue(StatusMetric metric, SystemMetricsSnapshot snapshot) =>
    switch (metric) {
      StatusMetric.cpu => snapshot.cpuUsage,
      StatusMetric.memory => snapshot.memoryUsage,
      StatusMetric.network => _networkProgress(snapshot),
      StatusMetric.battery => snapshot.batteryLevel,
    };

double? _historyValue(StatusMetric metric, SystemMetricsPoint point) =>
    switch (metric) {
      StatusMetric.cpu => point.cpuUsage,
      StatusMetric.memory => point.memoryUsage,
      StatusMetric.network => _networkProgressValues(
        point.networkDownloadBytesPerSecond,
        point.networkUploadBytesPerSecond,
      ),
      StatusMetric.battery => point.batteryLevel,
    };

String _percentage(double? value) =>
    value == null ? '—' : '${(value.clamp(0, 1) * 100).round()}%';

String _memoryValue(SystemMetricsSnapshot snapshot) {
  final used = snapshot.memoryUsedBytes;
  return used == null ? _percentage(snapshot.memoryUsage) : _bytes(used);
}

String _bytesOrDash(int? bytes) => bytes == null ? '—' : _bytes(bytes);

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

double? _networkProgress(SystemMetricsSnapshot snapshot) =>
    _networkProgressValues(
      snapshot.networkDownloadBytesPerSecond,
      snapshot.networkUploadBytesPerSecond,
    );

double? _networkProgressValues(double? download, double? upload) {
  final total = (download ?? 0) + (upload ?? 0);
  if (total <= 0) return 0;
  return (math.log(total + 1) / math.log(1024 * 1024 * 10)).clamp(0, 1);
}
