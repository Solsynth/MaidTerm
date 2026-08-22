/// Progress state requested by a terminal program through OSC 9;4.
enum TerminalProgressState {
  /// Remove any previously reported progress.
  remove,

  /// Normal determinate progress.
  normal,

  /// Progress representing an error.
  error,

  /// Indeterminate activity with no completion percentage.
  indeterminate,

  /// Paused progress.
  paused,
}

/// A ConEmu-style progress report (`OSC 9 ; 4 ; state [; progress] ST`).
final class TerminalProgress {
  const TerminalProgress(this.state, {this.value});

  /// Parses `state[;progress]`, the portion after the `4;` selector.
  ///
  /// Returns null for an unknown state or a completion value outside 0–100.
  static TerminalProgress? tryParse(String params) {
    final parts = params.split(';');
    if (parts.length > 2) return null;
    final stateIndex = int.tryParse(parts.first) ?? -1;
    if (stateIndex < 0 || stateIndex >= TerminalProgressState.values.length) {
      return null;
    }

    int? value;
    if (parts.length > 1) {
      value = int.tryParse(parts[1]);
      if (value == null || value < 0 || value > 100) return null;
    }

    return TerminalProgress(
      TerminalProgressState.values[stateIndex],
      value: value,
    );
  }

  final TerminalProgressState state;

  /// Completion percentage from 0 to 100, when supplied.
  ///
  /// Indeterminate, paused, and remove reports may omit this value.
  final int? value;
}
