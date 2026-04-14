#import "CGWindowCapture.h"
#import <dlfcn.h>

typedef CGImageRef (*CGWindowListCreateImageFunc)(CGRect, uint32_t, uint32_t, uint32_t);

CGImageRef _Nullable CaptureScreenRect(CGRect rect) {
    static CGWindowListCreateImageFunc createImage = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        createImage = (CGWindowListCreateImageFunc)dlsym(RTLD_DEFAULT, "CGWindowListCreateImage");
    });

    if (!createImage) return NULL;

    // kCGWindowListOptionOnScreenOnly = 1 << 0
    // kCGNullWindowID = 0
    // kCGWindowImageBestResolution = 1 << 3
    // kCGWindowImageBoundsIgnoreFraming = 1 << 0
    return createImage(rect, (1u << 0), 0, (1u << 3) | (1u << 0));
}
