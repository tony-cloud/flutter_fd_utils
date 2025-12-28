/// Current process RLIMIT_NOFILE (nofile) limits.
class NofileLimit {
  const NofileLimit({required this.soft, required this.hard});

  final int soft;
  final int hard;

  static NofileLimit fromMap(Map<Object?, Object?> map) {
    int readInt(String key) {
      final Object? value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return 0;
    }

    return NofileLimit(
      soft: readInt('soft'),
      hard: readInt('hard'),
    );
  }
}
