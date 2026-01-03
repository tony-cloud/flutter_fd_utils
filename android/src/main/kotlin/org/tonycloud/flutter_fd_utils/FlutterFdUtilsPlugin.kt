package org.tonycloud.flutter_fd_utils

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths

/** Android implementation of flutter_fd_utils. */
class FlutterFdUtilsPlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "flutter_fd_utils")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "getFdReport" -> result.success(buildFdReport())
      "getFdList" -> result.success(buildFdList())
      "getNofileLimit", "getNofileSoftLimit", "getNofileHardLimit" -> handleGetRlimit(call.method, result)
      "setNofileSoftLimit" -> handleSetRlimit(call, result)
      else -> result.notImplemented()
    }
  }

  private fun handleGetRlimit(method: String, result: Result) {
    val lim = readLimits()
    when (method) {
      "getNofileSoftLimit" -> result.success(lim?.first ?: 0L)
      "getNofileHardLimit" -> result.success(lim?.second ?: 0L)
      else -> result.success(mapOf("soft" to (lim?.first ?: 0L), "hard" to (lim?.second ?: 0L)))
    }
  }

  private fun handleSetRlimit(call: MethodCall, result: Result) {
    val softArg = call.argument<Number>("softLimit")
    if (softArg == null) {
      result.error("invalid_args", "Expected 'softLimit' as a number", null)
      return
    }

    val current = readLimits()
    val hard = current?.second ?: 0L
    val soft = current?.first ?: 0L
    val requested = softArg.toLong()
    val applied = if (requested > hard) hard else requested
    val clamped = requested > hard

    // Android SELinux typically forbids setrlimit for apps; return EPERM.
    result.success(
      mapOf(
        "requestedSoft" to requested,
        "appliedSoft" to applied,
        "hard" to hard,
        "previousSoft" to soft,
        "previousHard" to hard,
        "clampedToHard" to clamped,
        "success" to false,
        "errno" to EPERM,
        "errorMessage" to "setrlimit not permitted for this app (SELinux)"
      )
    )
  }

  private fun buildFdList(): List<Map<String, Any?>> {
    val dir = File("/proc/self/fd")
    if (!dir.exists() || !dir.isDirectory) return emptyList()

    val entries = mutableListOf<Map<String, Any?>>()

    dir.listFiles()?.forEach { file ->
      val name = file.name
      if (name == "." || name == "..") return@forEach
      val fd = name.toIntOrNull() ?: return@forEach

      val path = tryReadLink(fd)
      val fdInfo = readFdInfo(fd)
      val (fdType, fdTypeName) = classifyFd(fdInfo.typeHint)

      val vnode = if (fdType == FD_TYPE_VNODE && fdInfo.size != null && fdInfo.mode != null) {
        mapOf("mode" to fdInfo.mode, "size" to fdInfo.size)
      } else {
        null
      }

      val socket = if (fdType == FD_TYPE_SOCKET) emptyMap<String, Any?>() else null

      entries.add(
        mapOf(
          "fd" to fd,
          "fdType" to fdType,
          "fdTypeName" to fdTypeName,
          "openFlags" to fdInfo.flags,
          "fdFlags" to null,
          "path" to path,
          "socket" to socket,
          "vnode" to vnode
        )
      )
    }

    return entries
  }

  private fun buildFdReport(): String {
    val list = buildFdList()
    val lim = readLimits()
    val sb = StringBuilder()

    sb.append("timestamp_utc: ").append(nowIso()).append('\n')
    sb.append("pid: ").append(android.os.Process.myPid()).append('\n')
    if (lim != null) {
      sb.append("rlimit_nofile_cur: ").append(lim.first).append('\n')
      sb.append("rlimit_nofile_max: ").append(lim.second).append('\n')
    }

    sb.append("fd_count: ").append(list.size).append("\n\n")
    sb.append("fd_type_counts:\n")
    val counts = list.groupingBy { it["fdTypeName"] as? String ?: "UNKNOWN" }.eachCount()
    counts.forEach { (k, v) -> sb.append("  ").append(k).append(": ").append(v).append('\n') }

    sb.append("\nfd_details:\n")
    list.forEach { e ->
      val parts = mutableListOf<String>()
      parts.add("fd=${e["fd"]}")
      parts.add("type=${e["fdTypeName"]}")
      (e["openFlags"] as? Int)?.let { if (it >= 0) parts.add("open=$it") }
      (e["fdFlags"] as? Int)?.let { if (it >= 0) parts.add("fdflag=$it") }
      (e["path"] as? String)?.let { if (it.isNotEmpty()) parts.add("path=$it") }
      (e["vnode"] as? Map<*, *>)?.let { vnode ->
        (vnode["mode"] as? Number)?.let { parts.add("mode=${it.toLong().toString(8)}") }
        (vnode["size"] as? Number)?.let { parts.add("size=${it.toLong()}") }
      }
      sb.append(parts.joinToString(" ")).append('\n')
    }

    return sb.toString()
  }

  private fun readLimits(): Pair<Long, Long>? {
    val limitsFile = File("/proc/self/limits")
    if (!limitsFile.exists()) return null
    limitsFile.useLines { lines ->
      lines.forEach { line ->
        if (line.startsWith("Max open files")) {
          val parts = line.trim().split(Regex("\\s+"))
          if (parts.size >= 4) {
            val soft = parseLimit(parts[3])
            val hard = parseLimit(parts[4])
            return soft to hard
          }
        }
      }
    }
    return null
  }

  private fun parseLimit(raw: String): Long {
    if (raw.equals("unlimited", ignoreCase = true)) return Long.MAX_VALUE
    return raw.toLongOrNull() ?: 0L
  }

  private fun tryReadLink(fd: Int): String? = try {
    Files.readSymbolicLink(Paths.get("/proc/self/fd/$fd")).toString()
  } catch (_: Throwable) {
    null
  }

  private data class FdInfoSnapshot(
    val flags: Int?,
    val mode: Int?,
    val size: Long?,
    val typeHint: String?
  )

  private fun readFdInfo(fd: Int): FdInfoSnapshot {
    val infoPath = Path.of("/proc/self/fdinfo/$fd")
    var flags: Int? = null
    var mode: Int? = null
    var size: Long? = null
    var type: String? = null

    try {
      Files.readAllLines(infoPath).forEach { line ->
        when {
          line.startsWith("flags:") -> {
            val raw = line.removePrefix("flags:").trim()
            flags = raw.toIntOrNull(8)
          }
          line.startsWith("mnt_id:") -> {} // ignored
        }
      }
    } catch (_: Throwable) {
      // best-effort
    }

    val targetPath = tryReadLink(fd)
    if (targetPath != null) {
      type = classifyFromPath(targetPath)
      try {
        val attrs = Files.readAttributes(Path.of(targetPath), java.nio.file.attribute.BasicFileAttributes::class.java)
        mode = 0 // not available from attrs directly; placeholder
        size = attrs.size()
      } catch (_: Throwable) {
        // ignore
      }
    }

    return FdInfoSnapshot(flags = flags, mode = mode, size = size, typeHint = type)
  }

  private fun classifyFromPath(path: String): String {
    return when {
      path.startsWith("socket:") -> "SOCKET"
      path.startsWith("pipe:") || path.startsWith("anon_inode:[eventfd]") || path.startsWith("anon_inode:") -> "PIPE"
      else -> "VNODE"
    }
  }

  private fun classifyFd(typeHint: String?): Pair<Int, String> {
    return when (typeHint) {
      "SOCKET" -> FD_TYPE_SOCKET to "SOCKET"
      "PIPE" -> FD_TYPE_PIPE to "PIPE"
      else -> FD_TYPE_VNODE to "VNODE"
    }
  }

  companion object {
    private const val FD_TYPE_VNODE = 1
    private const val FD_TYPE_SOCKET = 2
    private const val FD_TYPE_PIPE = 6
    private const val EPERM = 1

    private fun nowIso(): String {
      val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
      fmt.timeZone = TimeZone.getTimeZone("UTC")
      return fmt.format(Date())
    }
  }
}
