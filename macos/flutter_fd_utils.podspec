Pod::Spec.new do |s|
  s.name             = 'flutter_fd_utils'
  s.version          = '0.2.0'
  s.summary          = 'Reports the current process file descriptor (FD) details on macOS.'
  s.description      = <<-DESC
A Flutter plugin that reports the current process file descriptor (FD) details on macOS.
The implementation uses libproc (proc_pidinfo/proc_pidfdpath) when available.
  DESC
  s.homepage         = 'https://github.com/tony-cloud/flutter_fd_utils'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'tony-cloud' => 'noreply@github.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
