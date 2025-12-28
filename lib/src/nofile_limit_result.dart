/// Result of attempting to update the soft RLIMIT_NOFILE (nofile) limit.
class NofileLimitResult {
  const NofileLimitResult({
    required this.requestedSoft,
    required this.appliedSoft,
    required this.hard,
    required this.previousSoft,
    required this.previousHard,
    required this.clampedToHard,
    required this.success,
    required this.errno,
    required this.errorMessage,
  });

  /// The requested soft limit.
  final int requestedSoft;

  /// The soft limit after the attempt (may be clamped to hard).
  final int appliedSoft;

  /// The hard limit after the attempt.
  final int hard;

  final int previousSoft;
  final int previousHard;

  /// Whether the requested soft limit was clamped to the current hard limit.
  final bool clampedToHard;

  /// Whether the call succeeded.
  final bool success;

  /// errno value when failed, or 0.
  final int errno;

  /// strerror(errno) when failed, or empty.
  final String errorMessage;

  static NofileLimitResult fromMap(Map<Object?, Object?> map) {
    int readInt(String key, {int fallback = 0}) {
      final Object? value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return fallback;
    }

    bool readBool(String key, {bool fallback = false}) {
      final Object? value = map[key];
      if (value is bool) return value;
      return fallback;
    }

    String readString(String key, {String fallback = ''}) {
      final Object? value = map[key];
      return value?.toString() ?? fallback;
    }

    return NofileLimitResult(
      requestedSoft: readInt('requestedSoft'),
      appliedSoft: readInt('appliedSoft'),
      hard: readInt('hard'),
      previousSoft: readInt('previousSoft'),
      previousHard: readInt('previousHard'),
      clampedToHard: readBool('clampedToHard'),
      success: readBool('success'),
      errno: readInt('errno'),
      errorMessage: readString('errorMessage'),
    );
  }
}
