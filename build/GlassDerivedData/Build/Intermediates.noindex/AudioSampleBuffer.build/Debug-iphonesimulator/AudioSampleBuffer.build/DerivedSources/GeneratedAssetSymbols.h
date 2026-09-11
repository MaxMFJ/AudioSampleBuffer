#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "none_image" asset catalog image resource.
static NSString * const ACImageNameNoneImage AC_SWIFT_PRIVATE = @"none_image";

#undef AC_SWIFT_PRIVATE
