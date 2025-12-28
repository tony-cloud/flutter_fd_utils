#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns a human-readable report of current process file descriptors.
/// Implemented using libproc (proc_pidinfo/proc_pidfdpath).
FOUNDATION_EXPORT NSString *FFUGetFdReport(void);

/// Returns a structured list describing current process file descriptors.
///
/// Each item is a JSON-compatible dictionary (NSString/NSNumber/NSDictionary/NSArray/NSNull).
FOUNDATION_EXPORT NSArray<NSDictionary *> *FFUGetFdList(void);


NS_ASSUME_NONNULL_END
