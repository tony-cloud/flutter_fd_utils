#import "FdDebugReporter.h"

#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <arpa/inet.h>
#import <limits.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/un.h>
#import <sys/resource.h>
#import <sys/types.h>
#import <unistd.h>

#if __has_include(<netinet/tcp.h>)
#import <netinet/tcp.h>
#define JH_HAS_NETINET_TCP_H 1
#else
#define JH_HAS_NETINET_TCP_H 0
#endif

typedef int (*JHProcPidinfoFn)(int pid, int flavor, uint64_t arg, void *buffer, int buffersize);
typedef int (*JHProcPidfdpathFn)(int pid, int fd, void *buffer, uint32_t buffersize);

static JHProcPidinfoFn JHResolveProcPidinfo(void) {
  static JHProcPidinfoFn fn;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    fn = (JHProcPidinfoFn)dlsym(RTLD_DEFAULT, "proc_pidinfo");
  });
  return fn;
}

static JHProcPidfdpathFn JHResolveProcPidfdpath(void) {
  static JHProcPidfdpathFn fn;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    fn = (JHProcPidfdpathFn)dlsym(RTLD_DEFAULT, "proc_pidfdpath");
  });
  return fn;
}

// Minimal proc_info definitions (mirrors xnu/bsd/sys/proc_info.h for the fields we use).
#ifndef PROC_PIDLISTFDS
#define PROC_PIDLISTFDS 1
#endif

#ifndef PROX_FDTYPE_ATALK
#define PROX_FDTYPE_ATALK 0
#define PROX_FDTYPE_VNODE 1
#define PROX_FDTYPE_SOCKET 2
#define PROX_FDTYPE_PSHM 3
#define PROX_FDTYPE_PSEM 4
#define PROX_FDTYPE_KQUEUE 5
#define PROX_FDTYPE_PIPE 6
#define PROX_FDTYPE_FSEVENTS 7
#endif

struct proc_fdinfo {
  int32_t proc_fd;
  uint32_t proc_fdtype;
};

#ifndef F_GETPATH
#define F_GETPATH 50
#endif

static NSString *JHDescribeSockaddr(const struct sockaddr *addr, socklen_t len) {
  if (addr == NULL || len == 0) {
    return @"";
  }

  if (addr->sa_family == AF_INET) {
    const struct sockaddr_in *in4 = (const struct sockaddr_in *)addr;
    char ip[INET_ADDRSTRLEN];
    const char *p = inet_ntop(AF_INET, &in4->sin_addr, ip, sizeof(ip));
    int port = ntohs(in4->sin_port);
    if (p != NULL) {
      return [NSString stringWithFormat:@"%s:%d", ip, port];
    }
    return [NSString stringWithFormat:@"AF_INET:%d", port];
  }

  if (addr->sa_family == AF_INET6) {
    const struct sockaddr_in6 *in6 = (const struct sockaddr_in6 *)addr;
    char ip[INET6_ADDRSTRLEN];
    const char *p = inet_ntop(AF_INET6, &in6->sin6_addr, ip, sizeof(ip));
    int port = ntohs(in6->sin6_port);
    if (p != NULL) {
      return [NSString stringWithFormat:@"[%s]:%d", ip, port];
    }
    return [NSString stringWithFormat:@"AF_INET6:%d", port];
  }

  if (addr->sa_family == AF_UNIX) {
    const struct sockaddr_un *un = (const struct sockaddr_un *)addr;
    if (un->sun_path[0] != 0) {
      return [NSString stringWithFormat:@"unix:%s", un->sun_path];
    }
    return @"unix:(anonymous)";
  }

  return [NSString stringWithFormat:@"family=%d", addr->sa_family];
}

static NSString *JHTcpStateName(uint8_t state) {
  // Common TCP FSM states used by Darwin/Linux (numeric values may vary across OS,
  // so we always print the raw value as well).
  switch (state) {
    case 0:
      return @"CLOSED";
    case 1:
      return @"LISTEN";
    case 2:
      return @"SYN_SENT";
    case 3:
      return @"SYN_RECEIVED";
    case 4:
      return @"ESTABLISHED";
    case 5:
      return @"CLOSE_WAIT";
    case 6:
      return @"FIN_WAIT_1";
    case 7:
      return @"CLOSING";
    case 8:
      return @"LAST_ACK";
    case 9:
      return @"FIN_WAIT_2";
    case 10:
      return @"TIME_WAIT";
    default:
      return [NSString stringWithFormat:@"UNKNOWN(%u)", state];
  }
}

static NSString *FFUGetFdOpenFlagsString(int fd) {
  int fl = fcntl(fd, F_GETFL);
  if (fl < 0) {
    return @"";
  }

  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  int acc = (fl & O_ACCMODE);
  if (acc == O_RDONLY) {
    [parts addObject:@"RDONLY"];
  } else if (acc == O_WRONLY) {
    [parts addObject:@"WRONLY"];
  } else if (acc == O_RDWR) {
    [parts addObject:@"RDWR"];
  }
  if ((fl & O_NONBLOCK) != 0) {
    [parts addObject:@"NONBLOCK"];
  }
  if ((fl & O_APPEND) != 0) {
    [parts addObject:@"APPEND"];
  }
  if ((fl & O_SYNC) != 0) {
    [parts addObject:@"SYNC"];
  }

  if (parts.count == 0) {
    return @"";
  }
  return [parts componentsJoinedByString:@"|"];
}

static NSString *FFUGetFdFlagsString(int fd) {
  int flags = fcntl(fd, F_GETFD);
  if (flags < 0) {
    return @"";
  }
  if ((flags & FD_CLOEXEC) != 0) {
    return @"CLOEXEC";
  }
  return @"";
}

static NSString *JHISO8601Now(void) {
  static NSDateFormatter *formatter;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
  });
  return [formatter stringFromDate:[NSDate date]];
}

static NSString *JHFdTypeName(uint32_t type) {
  switch (type) {
    case PROX_FDTYPE_VNODE:
      return @"VNODE";
    case PROX_FDTYPE_SOCKET:
      return @"SOCKET";
    case PROX_FDTYPE_PIPE:
      return @"PIPE";
    case PROX_FDTYPE_KQUEUE:
      return @"KQUEUE";
    case PROX_FDTYPE_PSHM:
      return @"PSHM";
    case PROX_FDTYPE_PSEM:
      return @"PSEM";
    case PROX_FDTYPE_FSEVENTS:
      return @"FSEVENTS";
    case PROX_FDTYPE_ATALK:
      return @"ATALK";
    default:
      return [NSString stringWithFormat:@"UNKNOWN(%u)", type];
  }
}

static NSDictionary *JHBuildFdItem(
    pid_t pid,
    int fd,
    uint32_t type,
    JHProcPidfdpathFn procPidfdpath,
    char *pathbuf,
    size_t pathbufSize) {
  // Resolve path best-effort.
  NSString *path = @"";
  if (procPidfdpath != NULL) {
    int plen = procPidfdpath(pid, fd, pathbuf, (uint32_t)pathbufSize);
    if (plen > 0) {
      pathbuf[pathbufSize - 1] = 0;
      path = [NSString stringWithUTF8String:pathbuf] ?: @"";
    }
  }
  if (path.length == 0) {
    if (fcntl(fd, F_GETPATH, pathbuf) == 0) {
      pathbuf[pathbufSize - 1] = 0;
      path = [NSString stringWithUTF8String:pathbuf] ?: @"";
    }
  }

  int openFlags = fcntl(fd, F_GETFL);
  int fdFlags = fcntl(fd, F_GETFD);

  NSMutableDictionary *item = [NSMutableDictionary dictionary];
  item[@"fd"] = @(fd);
  item[@"fdType"] = @((unsigned int)type);
  item[@"fdTypeName"] = JHFdTypeName(type);
  item[@"openFlags"] = (openFlags >= 0) ? @(openFlags) : [NSNull null];
  item[@"fdFlags"] = (fdFlags >= 0) ? @(fdFlags) : [NSNull null];
  item[@"path"] = (path.length > 0) ? path : [NSNull null];

  if (type == PROX_FDTYPE_SOCKET) {
    int soType = 0;
    socklen_t soTypeLen = (socklen_t)sizeof(soType);
    int soTypeRet = getsockopt(fd, SOL_SOCKET, SO_TYPE, &soType, &soTypeLen);

    int soProto = -1;
    int soProtoRet = -1;
#ifdef SO_PROTOCOL
    socklen_t soProtoLen = (socklen_t)sizeof(soProto);
    soProtoRet = getsockopt(fd, SOL_SOCKET, SO_PROTOCOL, &soProto, &soProtoLen);
#endif

    struct sockaddr_storage laddr;
    socklen_t laddrLen = (socklen_t)sizeof(laddr);
    int lret = getsockname(fd, (struct sockaddr *)&laddr, &laddrLen);

    struct sockaddr_storage raddr;
    socklen_t raddrLen = (socklen_t)sizeof(raddr);
    int rret = getpeername(fd, (struct sockaddr *)&raddr, &raddrLen);

    NSString *local = (lret == 0) ? JHDescribeSockaddr((struct sockaddr *)&laddr, laddrLen) : @"";
    NSString *peer = (rret == 0) ? JHDescribeSockaddr((struct sockaddr *)&raddr, raddrLen) : @"";

    NSMutableDictionary *socket = [NSMutableDictionary dictionary];
    if (soTypeRet == 0) {
      socket[@"soType"] = @(soType);
    }
    if (soProtoRet == 0) {
      socket[@"soProto"] = @(soProto);
    }
    if (lret == 0) {
      socket[@"family"] = @(((struct sockaddr *)&laddr)->sa_family);
    } else if (rret == 0) {
      socket[@"family"] = @(((struct sockaddr *)&raddr)->sa_family);
    }
    socket[@"local"] = (local.length > 0) ? local : [NSNull null];
    socket[@"peer"] = (peer.length > 0) ? peer : [NSNull null];

#if JH_HAS_NETINET_TCP_H
#ifdef TCP_CONNECTION_INFO
    if (soProtoRet != 0 || soProto == IPPROTO_TCP) {
      struct tcp_connection_info tcpi;
      socklen_t tcpiLen = (socklen_t)sizeof(tcpi);
      if (getsockopt(fd, IPPROTO_TCP, TCP_CONNECTION_INFO, &tcpi, &tcpiLen) == 0) {
        socket[@"tcpState"] = @(tcpi.tcpi_state);
        socket[@"tcpStateName"] = JHTcpStateName(tcpi.tcpi_state);
      }
    }
#endif
#endif

    item[@"socket"] = socket;
    return item;
  }

  if (type == PROX_FDTYPE_VNODE) {
    struct stat st;
    int sret = fstat(fd, &st);
    if (sret == 0) {
      item[@"vnode"] = @{
        @"mode" : @((unsigned int)st.st_mode),
        @"size" : @((long long)st.st_size),
      };
    }
    return item;
  }

  return item;
}

NSArray<NSDictionary *> *FFUGetFdList(void) {
  pid_t pid = getpid();

  JHProcPidinfoFn procPidinfo = JHResolveProcPidinfo();
  JHProcPidfdpathFn procPidfdpath = JHResolveProcPidfdpath();

  if (procPidinfo == NULL) {
    return @[];
  }

  int bytesNeeded = procPidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
  if (bytesNeeded <= 0) {
    return @[];
  }

  int fdInfoSize = (int)sizeof(struct proc_fdinfo);
  int capacity = bytesNeeded / fdInfoSize;
  if (capacity <= 0) {
    return @[];
  }

  struct proc_fdinfo *fds = (struct proc_fdinfo *)calloc((size_t)capacity, (size_t)fdInfoSize);
  if (fds == NULL) {
    return @[];
  }

  int bytesReturned = procPidinfo(pid, PROC_PIDLISTFDS, 0, fds, bytesNeeded);
  if (bytesReturned <= 0) {
    free(fds);
    return @[];
  }

  int count = bytesReturned / fdInfoSize;
  NSMutableArray<NSDictionary *> *out = [NSMutableArray arrayWithCapacity:(NSUInteger)count];

  char pathbuf[4 * PATH_MAX];
  for (int i = 0; i < count; i++) {
    int fd = fds[i].proc_fd;
    uint32_t type = fds[i].proc_fdtype;
    NSDictionary *item = JHBuildFdItem(pid, fd, type, procPidfdpath, pathbuf, sizeof(pathbuf));
    [out addObject:item];
  }

  free(fds);
  return out;
}

NSString *FFUGetFdReport(void) {
  pid_t pid = getpid();

  JHProcPidinfoFn procPidinfo = JHResolveProcPidinfo();
  JHProcPidfdpathFn procPidfdpath = JHResolveProcPidfdpath();

  struct rlimit lim;
  int rlimRet = getrlimit(RLIMIT_NOFILE, &lim);

  NSMutableString *out = [NSMutableString string];
  [out appendFormat:@"timestamp_utc: %@\n", JHISO8601Now()];
  [out appendFormat:@"pid: %d\n", pid];
  if (rlimRet == 0) {
    [out appendFormat:@"rlimit_nofile_cur: %llu\n", (unsigned long long)lim.rlim_cur];
    [out appendFormat:@"rlimit_nofile_max: %llu\n", (unsigned long long)lim.rlim_max];
  } else {
    [out appendFormat:@"getrlimit(RLIMIT_NOFILE) failed errno=%d\n", errno];
  }

  if (procPidinfo == NULL) {
    [out appendString:@"proc_pidinfo is unavailable on this OS/runtime\n"]; 
    return out;
  }

  int bytesNeeded = procPidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
  if (bytesNeeded <= 0) {
    [out appendFormat:@"proc_pidinfo(PROC_PIDLISTFDS) failed errno=%d\n", errno];
    return out;
  }

  int fdInfoSize = (int)sizeof(struct proc_fdinfo);
  int capacity = bytesNeeded / fdInfoSize;
  if (capacity <= 0) {
    [out appendString:@"No file descriptors returned\n"]; 
    return out;
  }

  struct proc_fdinfo *fds = (struct proc_fdinfo *)calloc((size_t)capacity, (size_t)fdInfoSize);
  if (fds == NULL) {
    [out appendString:@"calloc failed\n"]; 
    return out;
  }

  int bytesReturned = procPidinfo(pid, PROC_PIDLISTFDS, 0, fds, bytesNeeded);
  if (bytesReturned <= 0) {
    [out appendFormat:@"proc_pidinfo(PROC_PIDLISTFDS) returned %d errno=%d\n", bytesReturned, errno];
    free(fds);
    return out;
  }

  int count = bytesReturned / fdInfoSize;
  [out appendFormat:@"fd_count: %d\n\n", count];

  // Counts by type
  NSMutableDictionary<NSString *, NSNumber *> *typeCounts = [NSMutableDictionary dictionary];
  for (int i = 0; i < count; i++) {
    NSString *name = JHFdTypeName(fds[i].proc_fdtype);
    NSNumber *existing = typeCounts[name];
    typeCounts[name] = @(existing.intValue + 1);
  }
  [out appendString:@"fd_type_counts:\n"]; 
  for (NSString *key in typeCounts) {
    [out appendFormat:@"  %@: %@\n", key, typeCounts[key]];
  }

  [out appendString:@"\nfd_details:\n"]; 

  // proc_info.h uses PROC_PIDPATHINFO_MAXSIZE = 4*MAXPATHLEN.
  char pathbuf[4 * PATH_MAX];
  for (int i = 0; i < count; i++) {
    int fd = fds[i].proc_fd;
    uint32_t type = fds[i].proc_fdtype;

    NSString *cloexec = FFUGetFdFlagsString(fd);
    NSString *openFlags = FFUGetFdOpenFlagsString(fd);

    NSString *path = @"";

    // Prefer proc_pidfdpath if available; fall back to fcntl(F_GETPATH) for vnode-like fds.
    if (procPidfdpath != NULL) {
      int plen = procPidfdpath(pid, fd, pathbuf, (uint32_t)sizeof(pathbuf));
      if (plen > 0) {
        pathbuf[sizeof(pathbuf) - 1] = 0;
        path = [NSString stringWithUTF8String:pathbuf] ?: @"";
      }
    }
    if (path.length == 0) {
      if (fcntl(fd, F_GETPATH, pathbuf) == 0) {
        pathbuf[sizeof(pathbuf) - 1] = 0;
        path = [NSString stringWithUTF8String:pathbuf] ?: @"";
      }
    }

    if (type == PROX_FDTYPE_SOCKET) {
      int soType = 0;
      socklen_t soTypeLen = (socklen_t)sizeof(soType);
      int soTypeRet = getsockopt(fd, SOL_SOCKET, SO_TYPE, &soType, &soTypeLen);

      int soProto = -1;
      int soProtoRet = -1;
#ifdef SO_PROTOCOL
      socklen_t soProtoLen = (socklen_t)sizeof(soProto);
      soProtoRet = getsockopt(fd, SOL_SOCKET, SO_PROTOCOL, &soProto, &soProtoLen);
#endif

      struct sockaddr_storage laddr;
      socklen_t laddrLen = (socklen_t)sizeof(laddr);
      int lret = getsockname(fd, (struct sockaddr *)&laddr, &laddrLen);

      struct sockaddr_storage raddr;
      socklen_t raddrLen = (socklen_t)sizeof(raddr);
      int rret = getpeername(fd, (struct sockaddr *)&raddr, &raddrLen);

      NSString *local = (lret == 0) ? JHDescribeSockaddr((struct sockaddr *)&laddr, laddrLen) : @"";
      NSString *peer = (rret == 0) ? JHDescribeSockaddr((struct sockaddr *)&raddr, raddrLen) : @"";

      NSMutableArray<NSString *> *kv = [NSMutableArray array];
      [kv addObject:[NSString stringWithFormat:@"fd=%d", fd]];
      [kv addObject:[NSString stringWithFormat:@"type=%@", JHFdTypeName(type)]];
      if (soTypeRet == 0) {
        [kv addObject:[NSString stringWithFormat:@"so_type=%d", soType]];
      }
      if (soProtoRet == 0) {
        [kv addObject:[NSString stringWithFormat:@"so_proto=%d", soProto]];
      }
      if (lret == 0) {
        [kv addObject:[NSString stringWithFormat:@"family=%d", ((struct sockaddr *)&laddr)->sa_family]];
      } else if (rret == 0) {
        [kv addObject:[NSString stringWithFormat:@"family=%d", ((struct sockaddr *)&raddr)->sa_family]];
      }
      if (openFlags.length > 0) {
        [kv addObject:[NSString stringWithFormat:@"open=%@", openFlags]];
      }
      if (cloexec.length > 0) {
        [kv addObject:[NSString stringWithFormat:@"fdflag=%@", cloexec]];
      }
      if (local.length > 0) {
        [kv addObject:[NSString stringWithFormat:@"local=%@", local]];
      }
      if (peer.length > 0) {
        [kv addObject:[NSString stringWithFormat:@"peer=%@", peer]];
      }

#if JH_HAS_NETINET_TCP_H
#ifdef TCP_CONNECTION_INFO
      // Best-effort TCP state. Only applies to TCP sockets.
      // If so_proto isn't available, we still attempt and ignore failures.
      if (soProtoRet != 0 || soProto == IPPROTO_TCP) {
        struct tcp_connection_info tcpi;
        socklen_t tcpiLen = (socklen_t)sizeof(tcpi);
        if (getsockopt(fd, IPPROTO_TCP, TCP_CONNECTION_INFO, &tcpi, &tcpiLen) == 0) {
          [kv addObject:[NSString stringWithFormat:@"tcp_state=%@(%u)", JHTcpStateName(tcpi.tcpi_state), tcpi.tcpi_state]];
        }
      }
#endif
#endif

      [out appendFormat:@"%@\n", [kv componentsJoinedByString:@" "]];
      continue;
    }

    if (type == PROX_FDTYPE_VNODE) {
      struct stat st;
      int sret = fstat(fd, &st);
      NSMutableArray<NSString *> *kv = [NSMutableArray array];
      [kv addObject:[NSString stringWithFormat:@"fd=%d", fd]];
      [kv addObject:[NSString stringWithFormat:@"type=%@", JHFdTypeName(type)]];
      if (openFlags.length > 0) {
        [kv addObject:[NSString stringWithFormat:@"open=%@", openFlags]];
      }
      if (cloexec.length > 0) {
        [kv addObject:[NSString stringWithFormat:@"fdflag=%@", cloexec]];
      }
      if (path.length > 0) {
        [kv addObject:[NSString stringWithFormat:@"path=%@", path]];
      }
      if (sret == 0) {
        [kv addObject:[NSString stringWithFormat:@"mode=%o", (unsigned int)st.st_mode]];
        [kv addObject:[NSString stringWithFormat:@"size=%lld", (long long)st.st_size]];
      }
      [out appendFormat:@"%@\n", [kv componentsJoinedByString:@" "]];
      continue;
    }

    // Generic
    if (path.length > 0) {
      if (openFlags.length > 0 || cloexec.length > 0) {
        [out appendFormat:@"fd=%d type=%@ open=%@ fdflag=%@ path=%@\n", fd, JHFdTypeName(type), openFlags, cloexec, path];
      } else {
        [out appendFormat:@"fd=%d type=%@ path=%@\n", fd, JHFdTypeName(type), path];
      }
    } else {
      if (openFlags.length > 0 || cloexec.length > 0) {
        [out appendFormat:@"fd=%d type=%@ open=%@ fdflag=%@\n", fd, JHFdTypeName(type), openFlags, cloexec];
      } else {
        [out appendFormat:@"fd=%d type=%@\n", fd, JHFdTypeName(type)];
      }
    }
  }

  free(fds);
  return out;
}
