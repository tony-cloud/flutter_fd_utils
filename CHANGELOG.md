## 0.2.0

* Add Android platform implementation (reports FD info and handles RLIMIT_NOFILE; setrlimit may return EPERM on non-root/system apps under SELinux).
* Keep iOS/macOS/Linux parity for FD report/list and nofile helpers.

## 0.1.0

* Add macOS and Linux platform implementations alongside iOS.
* Expose file descriptor report, structured list, and RLIMIT_NOFILE helpers on desktop.
