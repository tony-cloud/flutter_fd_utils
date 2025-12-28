/// A single file descriptor entry for the current process.
class FdInfo {
  const FdInfo({
    required this.fd,
    required this.fdType,
    required this.fdTypeName,
    this.openFlags,
    this.fdFlags,
    this.path,
    this.socket,
    this.vnode,
  });

  final int fd;
  final int fdType;
  final String fdTypeName;

  /// Raw flags returned by `fcntl(fd, F_GETFL)`.
  final int? openFlags;

  /// Raw flags returned by `fcntl(fd, F_GETFD)`.
  final int? fdFlags;

  final String? path;
  final SocketInfo? socket;
  final VnodeInfo? vnode;

  static FdInfo fromMap(Map<Object?, Object?> map) {
    int readInt(String key, {int fallback = 0}) {
      final Object? value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return fallback;
    }

    int? readNullableInt(String key) {
      final Object? value = map[key];
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return null;
    }

    String readString(String key, {String fallback = ''}) {
      final Object? value = map[key];
      return value?.toString() ?? fallback;
    }

    String? readNullableString(String key) {
      final Object? value = map[key];
      if (value == null) return null;
      final s = value.toString();
      return s.isEmpty ? null : s;
    }

    SocketInfo? socket;
    final Object? socketRaw = map['socket'];
    if (socketRaw is Map) {
      socket = SocketInfo.fromMap(socketRaw.cast<Object?, Object?>());
    }

    VnodeInfo? vnode;
    final Object? vnodeRaw = map['vnode'];
    if (vnodeRaw is Map) {
      vnode = VnodeInfo.fromMap(vnodeRaw.cast<Object?, Object?>());
    }

    return FdInfo(
      fd: readInt('fd'),
      fdType: readInt('fdType'),
      fdTypeName: readString('fdTypeName'),
      openFlags: readNullableInt('openFlags'),
      fdFlags: readNullableInt('fdFlags'),
      path: readNullableString('path'),
      socket: socket,
      vnode: vnode,
    );
  }
}

class SocketInfo {
  const SocketInfo({
    this.soType,
    this.soProto,
    this.family,
    this.local,
    this.peer,
    this.tcpState,
    this.tcpStateName,
  });

  final int? soType;
  final int? soProto;
  final int? family;
  final String? local;
  final String? peer;
  final int? tcpState;
  final String? tcpStateName;

  static SocketInfo fromMap(Map<Object?, Object?> map) {
    int? readNullableInt(String key) {
      final Object? value = map[key];
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return null;
    }

    String? readNullableString(String key) {
      final Object? value = map[key];
      if (value == null) return null;
      final s = value.toString();
      return s.isEmpty ? null : s;
    }

    return SocketInfo(
      soType: readNullableInt('soType'),
      soProto: readNullableInt('soProto'),
      family: readNullableInt('family'),
      local: readNullableString('local'),
      peer: readNullableString('peer'),
      tcpState: readNullableInt('tcpState'),
      tcpStateName: readNullableString('tcpStateName'),
    );
  }
}

class VnodeInfo {
  const VnodeInfo({required this.mode, required this.size});

  final int mode;
  final int size;

  static VnodeInfo fromMap(Map<Object?, Object?> map) {
    int readInt(String key) {
      final Object? value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return 0;
    }

    return VnodeInfo(
      mode: readInt('mode'),
      size: readInt('size'),
    );
  }
}
