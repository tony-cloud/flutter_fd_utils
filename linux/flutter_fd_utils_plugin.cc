#include "include/flutter_fd_utils/flutter_fd_utils_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <chrono>
#include <arpa/inet.h>
#include <cstdlib>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <iomanip>
#include <linux/tcp.h>
#include <limits.h>
#include <map>
#include <netinet/in.h>
#include <sys/un.h>
#include <sstream>
#include <string>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <ctime>
#include <unistd.h>
#include <vector>

#define FD_TYPE_UNKNOWN 0
#define FD_TYPE_VNODE 1
#define FD_TYPE_SOCKET 2
#define FD_TYPE_PIPE 6

struct SocketDetails {
  bool present = false;
  bool has_so_type = false;
  int so_type = 0;
  bool has_so_proto = false;
  int so_proto = 0;
  bool has_family = false;
  int family = 0;
  std::string local;
  std::string peer;
  bool has_tcp_state = false;
  int tcp_state = 0;
  std::string tcp_state_name;
};

struct VnodeDetails {
  bool present = false;
  int mode = 0;
  long long size = 0;
};

struct FdEntry {
  int fd = -1;
  int fd_type = FD_TYPE_UNKNOWN;
  std::string fd_type_name;
  int open_flags = -1;
  int fd_flags = -1;
  std::string path;
  SocketDetails socket;
  VnodeDetails vnode;
};

static std::string Iso8601Now() {
  auto now = std::chrono::system_clock::now();
  std::time_t tt = std::chrono::system_clock::to_time_t(now);
  std::tm tm_utc{};
  gmtime_r(&tt, &tm_utc);

  std::ostringstream ss;
  ss << std::put_time(&tm_utc, "%Y-%m-%dT%H:%M:%S");

  auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()) % 1000;
  ss << "." << std::setfill('0') << std::setw(3) << ms.count() << "Z";
  return ss.str();
}

static std::string DescribeSockaddr(const struct sockaddr* addr, socklen_t len) {
  if (addr == nullptr || len == 0) {
    return "";
  }

  if (addr->sa_family == AF_INET) {
    const struct sockaddr_in* in4 = reinterpret_cast<const struct sockaddr_in*>(addr);
    char ip[INET_ADDRSTRLEN];
    const char* p = inet_ntop(AF_INET, &in4->sin_addr, ip, sizeof(ip));
    int port = ntohs(in4->sin_port);
    if (p != nullptr) {
      std::ostringstream ss;
      ss << p << ":" << port;
      return ss.str();
    }
    return "AF_INET:" + std::to_string(port);
  }

  if (addr->sa_family == AF_INET6) {
    const struct sockaddr_in6* in6 = reinterpret_cast<const struct sockaddr_in6*>(addr);
    char ip[INET6_ADDRSTRLEN];
    const char* p = inet_ntop(AF_INET6, &in6->sin6_addr, ip, sizeof(ip));
    int port = ntohs(in6->sin6_port);
    if (p != nullptr) {
      std::ostringstream ss;
      ss << "[" << p << "]:" << port;
      return ss.str();
    }
    return "AF_INET6:" + std::to_string(port);
  }

  if (addr->sa_family == AF_UNIX) {
    const struct sockaddr_un* un = reinterpret_cast<const struct sockaddr_un*>(addr);
    if (un->sun_path[0] != 0) {
      return std::string("unix:") + un->sun_path;
    }
    return "unix:(anonymous)";
  }

  return std::string("family=") + std::to_string(addr->sa_family);
}

static std::string TcpStateName(int state) {
  switch (state) {
    case TCP_ESTABLISHED:
      return "ESTABLISHED";
    case TCP_SYN_SENT:
      return "SYN_SENT";
    case TCP_SYN_RECV:
      return "SYN_RECV";
    case TCP_FIN_WAIT1:
      return "FIN_WAIT_1";
    case TCP_FIN_WAIT2:
      return "FIN_WAIT_2";
    case TCP_TIME_WAIT:
      return "TIME_WAIT";
    case TCP_CLOSE:
      return "CLOSED";
    case TCP_CLOSE_WAIT:
      return "CLOSE_WAIT";
    case TCP_LAST_ACK:
      return "LAST_ACK";
    case TCP_LISTEN:
      return "LISTEN";
    case TCP_CLOSING:
      return "CLOSING";
    default:
      return "UNKNOWN(" + std::to_string(state) + ")";
  }
}

static std::string OpenFlagsString(int fd) {
  int fl = fcntl(fd, F_GETFL);
  if (fl < 0) {
    return "";
  }

  std::vector<std::string> parts;
  int acc = fl & O_ACCMODE;
  if (acc == O_RDONLY) {
    parts.emplace_back("RDONLY");
  } else if (acc == O_WRONLY) {
    parts.emplace_back("WRONLY");
  } else if (acc == O_RDWR) {
    parts.emplace_back("RDWR");
  }
  if ((fl & O_NONBLOCK) != 0) {
    parts.emplace_back("NONBLOCK");
  }
  if ((fl & O_APPEND) != 0) {
    parts.emplace_back("APPEND");
  }
  if ((fl & O_SYNC) != 0) {
    parts.emplace_back("SYNC");
  }

  std::ostringstream ss;
  for (size_t i = 0; i < parts.size(); i++) {
    if (i > 0) ss << "|";
    ss << parts[i];
  }
  return ss.str();
}

static std::string FdFlagsString(int fd) {
  int flags = fcntl(fd, F_GETFD);
  if (flags < 0) {
    return "";
  }
  if ((flags & FD_CLOEXEC) != 0) {
    return "CLOEXEC";
  }
  return "";
}

static std::string ReadFdPath(int fd) {
  char linkname[PATH_MAX];
  std::snprintf(linkname, sizeof(linkname), "/proc/self/fd/%d", fd);

  char buf[PATH_MAX];
  ssize_t len = readlink(linkname, buf, sizeof(buf) - 1);
  if (len <= 0) {
    return "";
  }
  buf[len] = '\0';
  return std::string(buf);
}

static const char* FdTypeName(int type) {
  switch (type) {
    case FD_TYPE_VNODE:
      return "VNODE";
    case FD_TYPE_SOCKET:
      return "SOCKET";
    case FD_TYPE_PIPE:
      return "PIPE";
    default:
      return "UNKNOWN";
  }
}

static SocketDetails BuildSocketDetails(int fd) {
  SocketDetails s;

  int so_type = 0;
  socklen_t so_type_len = sizeof(so_type);
  if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &so_type, &so_type_len) == 0) {
    s.has_so_type = true;
    s.so_type = so_type;
    s.present = true;
  }

  int so_proto = 0;
  socklen_t so_proto_len = sizeof(so_proto);
#ifdef SO_PROTOCOL
  if (getsockopt(fd, SOL_SOCKET, SO_PROTOCOL, &so_proto, &so_proto_len) == 0) {
    s.has_so_proto = true;
    s.so_proto = so_proto;
    s.present = true;
  }
#endif

  struct sockaddr_storage laddr;
  socklen_t laddr_len = sizeof(laddr);
  if (getsockname(fd, reinterpret_cast<struct sockaddr*>(&laddr), &laddr_len) == 0) {
    s.local = DescribeSockaddr(reinterpret_cast<struct sockaddr*>(&laddr), laddr_len);
    s.family = reinterpret_cast<struct sockaddr*>(&laddr)->sa_family;
    s.has_family = true;
    s.present = true;
  }

  struct sockaddr_storage raddr;
  socklen_t raddr_len = sizeof(raddr);
  if (getpeername(fd, reinterpret_cast<struct sockaddr*>(&raddr), &raddr_len) == 0) {
    s.peer = DescribeSockaddr(reinterpret_cast<struct sockaddr*>(&raddr), raddr_len);
    if (!s.has_family) {
      s.family = reinterpret_cast<struct sockaddr*>(&raddr)->sa_family;
      s.has_family = true;
    }
    s.present = true;
  }

#ifdef TCP_INFO
  struct tcp_info tcpi;
  socklen_t tcpi_len = sizeof(tcpi);
  if (getsockopt(fd, IPPROTO_TCP, TCP_INFO, &tcpi, &tcpi_len) == 0) {
    s.has_tcp_state = true;
    s.tcp_state = tcpi.tcpi_state;
    s.tcp_state_name = TcpStateName(tcpi.tcpi_state);
    s.present = true;
  }
#endif

  return s;
}

static VnodeDetails BuildVnodeDetails(const struct stat& st) {
  VnodeDetails v;
  v.present = true;
  v.mode = static_cast<int>(st.st_mode);
  v.size = static_cast<long long>(st.st_size);
  return v;
}

static std::vector<FdEntry> CollectFdList() {
  std::vector<FdEntry> out;

  DIR* dir = opendir("/proc/self/fd");
  if (dir == nullptr) {
    return out;
  }

  struct dirent* ent;
  while ((ent = readdir(dir)) != nullptr) {
    if (ent->d_name[0] == '.') {
      continue;
    }

    int fd = std::atoi(ent->d_name);
    if (fd < 0) {
      continue;
    }

    struct stat st;
    if (fstat(fd, &st) != 0) {
      continue;
    }

    FdEntry e;
    e.fd = fd;
    e.open_flags = fcntl(fd, F_GETFL);
    e.fd_flags = fcntl(fd, F_GETFD);
    e.path = ReadFdPath(fd);

    if (S_ISSOCK(st.st_mode)) {
      e.fd_type = FD_TYPE_SOCKET;
      e.fd_type_name = FdTypeName(e.fd_type);
      e.socket = BuildSocketDetails(fd);
    } else if (S_ISFIFO(st.st_mode)) {
      e.fd_type = FD_TYPE_PIPE;
      e.fd_type_name = FdTypeName(e.fd_type);
    } else {
      e.fd_type = FD_TYPE_VNODE;
      e.fd_type_name = FdTypeName(e.fd_type);
      e.vnode = BuildVnodeDetails(st);
    }

    out.push_back(std::move(e));
  }

  closedir(dir);
  return out;
}

static FlValue* BuildSocketMap(const SocketDetails& s) {
  if (!s.present) {
    return nullptr;
  }

  FlValue* map = fl_value_new_map();
  if (s.has_so_type) {
    fl_value_set_string_take(map, "soType", fl_value_new_int(s.so_type));
  }
  if (s.has_so_proto) {
    fl_value_set_string_take(map, "soProto", fl_value_new_int(s.so_proto));
  }
  if (s.has_family) {
    fl_value_set_string_take(map, "family", fl_value_new_int(s.family));
  }
  if (!s.local.empty()) {
    fl_value_set_string_take(map, "local", fl_value_new_string(s.local.c_str()));
  } else {
    fl_value_set_string_take(map, "local", fl_value_new_null());
  }
  if (!s.peer.empty()) {
    fl_value_set_string_take(map, "peer", fl_value_new_string(s.peer.c_str()));
  } else {
    fl_value_set_string_take(map, "peer", fl_value_new_null());
  }
  if (s.has_tcp_state) {
    fl_value_set_string_take(map, "tcpState", fl_value_new_int(s.tcp_state));
    fl_value_set_string_take(map, "tcpStateName", fl_value_new_string(s.tcp_state_name.c_str()));
  }
  return map;
}

static FlValue* BuildVnodeMap(const VnodeDetails& v) {
  if (!v.present) {
    return nullptr;
  }
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "mode", fl_value_new_int(v.mode));
  fl_value_set_string_take(map, "size", fl_value_new_int(v.size));
  return map;
}

static FlValue* BuildFdListValue(const std::vector<FdEntry>& list) {
  FlValue* arr = fl_value_new_list();
  for (const auto& e : list) {
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "fd", fl_value_new_int(e.fd));
    fl_value_set_string_take(map, "fdType", fl_value_new_int(e.fd_type));
    fl_value_set_string_take(map, "fdTypeName", fl_value_new_string(e.fd_type_name.c_str()));

    if (e.open_flags >= 0) {
      fl_value_set_string_take(map, "openFlags", fl_value_new_int(e.open_flags));
    } else {
      fl_value_set_string_take(map, "openFlags", fl_value_new_null());
    }

    if (e.fd_flags >= 0) {
      fl_value_set_string_take(map, "fdFlags", fl_value_new_int(e.fd_flags));
    } else {
      fl_value_set_string_take(map, "fdFlags", fl_value_new_null());
    }

    if (!e.path.empty()) {
      fl_value_set_string_take(map, "path", fl_value_new_string(e.path.c_str()));
    } else {
      fl_value_set_string_take(map, "path", fl_value_new_null());
    }

    if (auto socket_map = BuildSocketMap(e.socket)) {
      fl_value_set_string_take(map, "socket", socket_map);
    }
    if (auto vnode_map = BuildVnodeMap(e.vnode)) {
      fl_value_set_string_take(map, "vnode", vnode_map);
    }

    fl_value_append_take(arr, map);
  }
  return arr;
}

static std::string BuildFdReport(const std::vector<FdEntry>& list) {
  std::ostringstream out;
  pid_t pid = getpid();

  struct rlimit lim;
  int rlim_ret = getrlimit(RLIMIT_NOFILE, &lim);

  out << "timestamp_utc: " << Iso8601Now() << "\n";
  out << "pid: " << pid << "\n";
  if (rlim_ret == 0) {
    out << "rlimit_nofile_cur: " << static_cast<unsigned long long>(lim.rlim_cur) << "\n";
    out << "rlimit_nofile_max: " << static_cast<unsigned long long>(lim.rlim_max) << "\n";
  } else {
    out << "getrlimit(RLIMIT_NOFILE) failed errno=" << errno << "\n";
  }

  out << "fd_count: " << list.size() << "\n\n";
  out << "fd_type_counts:\n";
  std::map<std::string, int> type_counts;
  for (const auto& e : list) {
    type_counts[e.fd_type_name] += 1;
  }
  for (const auto& kv : type_counts) {
    out << "  " << kv.first << ": " << kv.second << "\n";
  }

  out << "\nfd_details:\n";
  for (const auto& e : list) {
    std::string cloexec = FdFlagsString(e.fd);
    std::string open = OpenFlagsString(e.fd);

    if (e.fd_type == FD_TYPE_SOCKET) {
      std::vector<std::string> parts;
      parts.push_back("fd=" + std::to_string(e.fd));
      parts.push_back(std::string("type=") + e.fd_type_name);
      if (e.socket.has_so_type) {
        parts.push_back("so_type=" + std::to_string(e.socket.so_type));
      }
      if (e.socket.has_so_proto) {
        parts.push_back("so_proto=" + std::to_string(e.socket.so_proto));
      }
      if (e.socket.has_family) {
        parts.push_back("family=" + std::to_string(e.socket.family));
      }
      if (!open.empty()) {
        parts.push_back("open=" + open);
      }
      if (!cloexec.empty()) {
        parts.push_back("fdflag=" + cloexec);
      }
      if (!e.socket.local.empty()) {
        parts.push_back("local=" + e.socket.local);
      }
      if (!e.socket.peer.empty()) {
        parts.push_back("peer=" + e.socket.peer);
      }
      if (e.socket.has_tcp_state) {
        parts.push_back("tcp_state=" + e.socket.tcp_state_name + "(" + std::to_string(e.socket.tcp_state) + ")");
      }
      for (size_t i = 0; i < parts.size(); i++) {
        if (i > 0) out << ' ';
        out << parts[i];
      }
      out << "\n";
      continue;
    }

    if (e.fd_type == FD_TYPE_VNODE) {
      std::vector<std::string> parts;
      parts.push_back("fd=" + std::to_string(e.fd));
      parts.push_back(std::string("type=") + e.fd_type_name);
      if (!open.empty()) {
        parts.push_back("open=" + open);
      }
      if (!cloexec.empty()) {
        parts.push_back("fdflag=" + cloexec);
      }
      if (!e.path.empty()) {
        parts.push_back("path=" + e.path);
      }
      if (e.vnode.present) {
        std::ostringstream mode;
        mode << std::oct << (unsigned int)e.vnode.mode;
        parts.push_back("mode=" + mode.str());
        parts.push_back("size=" + std::to_string(e.vnode.size));
      }
      for (size_t i = 0; i < parts.size(); i++) {
        if (i > 0) out << ' ';
        out << parts[i];
      }
      out << "\n";
      continue;
    }

    std::vector<std::string> parts;
    parts.push_back("fd=" + std::to_string(e.fd));
    parts.push_back(std::string("type=") + e.fd_type_name);
    if (!open.empty()) {
      parts.push_back("open=" + open);
    }
    if (!cloexec.empty()) {
      parts.push_back("fdflag=" + cloexec);
    }
    if (!e.path.empty()) {
      parts.push_back("path=" + e.path);
    }
    for (size_t i = 0; i < parts.size(); i++) {
      if (i > 0) out << ' ';
      out << parts[i];
    }
    out << "\n";
  }

  return out.str();
}

struct _FlutterFdUtilsPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(FlutterFdUtilsPlugin, flutter_fd_utils_plugin, g_object_get_type())

static FlMethodResponse* HandleGetFdReport() {
  auto list = CollectFdList();
  std::string report = BuildFdReport(list);
  g_autoptr(FlValue) result = fl_value_new_string(report.c_str());
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* HandleGetFdList() {
  auto list = CollectFdList();
  g_autoptr(FlValue) result = BuildFdListValue(list);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* HandleGetNofileLimit(const std::string& method) {
  struct rlimit lim;
  if (getrlimit(RLIMIT_NOFILE, &lim) != 0) {
    std::string message = strerror(errno);
    g_autoptr(FlValue) details = fl_value_new_map();
    fl_value_set_string_take(details, "errno", fl_value_new_int(errno));
    return FL_METHOD_RESPONSE(fl_method_error_response_new("getrlimit_failed", message.c_str(), details));
  }

  if (method == "getNofileSoftLimit") {
    g_autoptr(FlValue) result = fl_value_new_int(static_cast<gint64>(lim.rlim_cur));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }
  if (method == "getNofileHardLimit") {
    g_autoptr(FlValue) result = fl_value_new_int(static_cast<gint64>(lim.rlim_max));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }

  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "soft", fl_value_new_int(static_cast<gint64>(lim.rlim_cur)));
  fl_value_set_string_take(map, "hard", fl_value_new_int(static_cast<gint64>(lim.rlim_max)));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(map));
}

static FlMethodResponse* HandleSetNofileSoftLimit(FlMethodCall* method_call) {
  FlValue* args = fl_method_call_get_args(method_call);
  FlValue* soft_limit_value = nullptr;
  if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    soft_limit_value = fl_value_lookup_string(args, "softLimit");
  }

  if (soft_limit_value == nullptr ||
      (fl_value_get_type(soft_limit_value) != FL_VALUE_TYPE_INT &&
       fl_value_get_type(soft_limit_value) != FL_VALUE_TYPE_FLOAT)) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new("invalid_args", "Expected 'softLimit' as a number", nullptr));
  }

  gint64 soft_limit = 0;
  if (fl_value_get_type(soft_limit_value) == FL_VALUE_TYPE_INT) {
    soft_limit = fl_value_get_int(soft_limit_value);
  } else {
    soft_limit = static_cast<gint64>(fl_value_get_float(soft_limit_value));
  }

  bool clamp_to_hard = true;
  if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* clamp_value = fl_value_lookup_string(args, "clampToHardLimit");
    if (clamp_value != nullptr && fl_value_get_type(clamp_value) == FL_VALUE_TYPE_BOOL) {
      clamp_to_hard = fl_value_get_bool(clamp_value);
    }
  }

  struct rlimit old_lim;
  if (getrlimit(RLIMIT_NOFILE, &old_lim) != 0) {
    int err = errno;
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "requestedSoft", fl_value_new_int(soft_limit));
    fl_value_set_string_take(map, "appliedSoft", fl_value_new_int(0));
    fl_value_set_string_take(map, "hard", fl_value_new_int(0));
    fl_value_set_string_take(map, "previousSoft", fl_value_new_int(0));
    fl_value_set_string_take(map, "previousHard", fl_value_new_int(0));
    fl_value_set_string_take(map, "clampedToHard", fl_value_new_bool(false));
    fl_value_set_string_take(map, "success", fl_value_new_bool(false));
    fl_value_set_string_take(map, "errno", fl_value_new_int(err));
    fl_value_set_string_take(map, "errorMessage", fl_value_new_string(strerror(err)));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  }

  rlim_t requested = static_cast<rlim_t>(soft_limit);
  rlim_t applied = requested;
  bool clamped = false;
  if (clamp_to_hard && applied > old_lim.rlim_max) {
    applied = old_lim.rlim_max;
    clamped = true;
  }

  struct rlimit new_lim = old_lim;
  new_lim.rlim_cur = applied;

  errno = 0;
  int set_ret = setrlimit(RLIMIT_NOFILE, &new_lim);
  int set_err = errno;

  struct rlimit after_lim;
  if (getrlimit(RLIMIT_NOFILE, &after_lim) != 0) {
    after_lim = old_lim;
  }

  bool success = (set_ret == 0);
  const char* msg = success ? "" : strerror(set_err);

  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "requestedSoft", fl_value_new_int(soft_limit));
  fl_value_set_string_take(map, "appliedSoft", fl_value_new_int(static_cast<gint64>(after_lim.rlim_cur)));
  fl_value_set_string_take(map, "hard", fl_value_new_int(static_cast<gint64>(after_lim.rlim_max)));
  fl_value_set_string_take(map, "previousSoft", fl_value_new_int(static_cast<gint64>(old_lim.rlim_cur)));
  fl_value_set_string_take(map, "previousHard", fl_value_new_int(static_cast<gint64>(old_lim.rlim_max)));
  fl_value_set_string_take(map, "clampedToHard", fl_value_new_bool(clamped));
  fl_value_set_string_take(map, "success", fl_value_new_bool(success));
  fl_value_set_string_take(map, "errno", fl_value_new_int(success ? 0 : set_err));
  fl_value_set_string_take(map, "errorMessage", fl_value_new_string(msg));

  return FL_METHOD_RESPONSE(fl_method_success_response_new(map));
}

static void flutter_fd_utils_plugin_handle_method_call(FlutterFdUtilsPlugin* self, FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);

  FlMethodResponse* response = nullptr;
  if (strcmp(method, "getFdReport") == 0) {
    response = HandleGetFdReport();
  } else if (strcmp(method, "getFdList") == 0) {
    response = HandleGetFdList();
  } else if (strcmp(method, "getNofileLimit") == 0 ||
             strcmp(method, "getNofileSoftLimit") == 0 ||
             strcmp(method, "getNofileHardLimit") == 0) {
    response = HandleGetNofileLimit(method);
  } else if (strcmp(method, "setNofileSoftLimit") == 0) {
    response = HandleSetNofileSoftLimit(method_call);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void flutter_fd_utils_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(flutter_fd_utils_plugin_parent_class)->dispose(object);
}

static void flutter_fd_utils_plugin_class_init(FlutterFdUtilsPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = flutter_fd_utils_plugin_dispose;
}

static void flutter_fd_utils_plugin_init(FlutterFdUtilsPlugin* self) {}

static void method_call_cb(FlMethodChannel* /*channel*/, FlMethodCall* method_call, gpointer user_data) {
  FlutterFdUtilsPlugin* plugin = FLUTTER_FD_UTILS_PLUGIN(user_data);
  flutter_fd_utils_plugin_handle_method_call(plugin, method_call);
}

void flutter_fd_utils_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  FlutterFdUtilsPlugin* plugin = FLUTTER_FD_UTILS_PLUGIN(
      g_object_new(flutter_fd_utils_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "flutter_fd_utils",
      FL_METHOD_CODEC(codec));

  fl_method_channel_set_method_call_handler(channel, method_call_cb, g_object_ref(plugin), g_object_unref);
  g_object_unref(plugin);
}
