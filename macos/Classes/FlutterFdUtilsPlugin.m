#import "FlutterFdUtilsPlugin.h"
#import "FdDebugReporter.h"

#import <errno.h>
#import <string.h>
#import <sys/resource.h>

@implementation FlutterFdUtilsPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:@"flutter_fd_utils" binaryMessenger:[registrar messenger]];
  FlutterFdUtilsPlugin *instance = [[FlutterFdUtilsPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"getFdReport"]) {
    result(FFUGetFdReport());
    return;
  }

  if ([call.method isEqualToString:@"getFdList"]) {
    result(FFUGetFdList());
    return;
  }

  if ([call.method isEqualToString:@"getNofileLimit"] ||
      [call.method isEqualToString:@"getNofileSoftLimit"] ||
      [call.method isEqualToString:@"getNofileHardLimit"]) {
    struct rlimit lim;
    if (getrlimit(RLIMIT_NOFILE, &lim) != 0) {
      int err = errno;
      result([FlutterError errorWithCode:@"getrlimit_failed"
                                 message:[NSString stringWithUTF8String:strerror(err)] ?: @""
                                 details:@{ @"errno" : @(err) }]);
      return;
    }

    NSNumber *soft = @((unsigned long long)lim.rlim_cur);
    NSNumber *hard = @((unsigned long long)lim.rlim_max);

    if ([call.method isEqualToString:@"getNofileSoftLimit"]) {
      result(soft);
      return;
    }
    if ([call.method isEqualToString:@"getNofileHardLimit"]) {
      result(hard);
      return;
    }
    result(@{ @"soft" : soft, @"hard" : hard });
    return;
  }

  if ([call.method isEqualToString:@"setNofileSoftLimit"]) {
    NSDictionary *args = (call.arguments && [call.arguments isKindOfClass:[NSDictionary class]])
                             ? (NSDictionary *)call.arguments
                             : @{};

    NSNumber *softLimitNumber = args[@"softLimit"];
    if (softLimitNumber == nil || ![softLimitNumber isKindOfClass:[NSNumber class]]) {
      result([FlutterError errorWithCode:@"invalid_args"
                                 message:@"Expected 'softLimit' as a number"
                                 details:nil]);
      return;
    }

    BOOL clampToHard = YES;
    NSNumber *clampNumber = args[@"clampToHardLimit"];
    if ([clampNumber isKindOfClass:[NSNumber class]]) {
      clampToHard = clampNumber.boolValue;
    }

    struct rlimit oldLim;
    int getOldRet = getrlimit(RLIMIT_NOFILE, &oldLim);
    if (getOldRet != 0) {
      int err = errno;
      result(@{
        @"requestedSoft" : softLimitNumber,
        @"appliedSoft" : @0,
        @"hard" : @0,
        @"previousSoft" : @0,
        @"previousHard" : @0,
        @"clampedToHard" : @NO,
        @"success" : @NO,
        @"errno" : @(err),
        @"errorMessage" : [NSString stringWithUTF8String:strerror(err)] ?: @"",
      });
      return;
    }

    rlim_t requested = (rlim_t)softLimitNumber.unsignedLongLongValue;
    rlim_t applied = requested;
    BOOL clamped = NO;
    if (clampToHard && applied > oldLim.rlim_max) {
      applied = oldLim.rlim_max;
      clamped = YES;
    }

    struct rlimit newLim = oldLim;
    newLim.rlim_cur = applied;

    errno = 0;
    int setRet = setrlimit(RLIMIT_NOFILE, &newLim);
    int setErr = errno;

    struct rlimit afterLim;
    int getAfterRet = getrlimit(RLIMIT_NOFILE, &afterLim);
    if (getAfterRet != 0) {
      afterLim = oldLim;
    }

    BOOL success = (setRet == 0);
    NSString *msg = success ? @"" : ([NSString stringWithUTF8String:strerror(setErr)] ?: @"");

    result(@{
      @"requestedSoft" : softLimitNumber,
      @"appliedSoft" : @((unsigned long long)afterLim.rlim_cur),
      @"hard" : @((unsigned long long)afterLim.rlim_max),
      @"previousSoft" : @((unsigned long long)oldLim.rlim_cur),
      @"previousHard" : @((unsigned long long)oldLim.rlim_max),
      @"clampedToHard" : @(clamped),
      @"success" : @(success),
      @"errno" : @(success ? 0 : setErr),
      @"errorMessage" : msg,
    });
    return;
  }

  result(FlutterMethodNotImplemented);
}

@end
