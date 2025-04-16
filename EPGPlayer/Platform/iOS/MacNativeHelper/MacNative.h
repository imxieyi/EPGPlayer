//
//  MacNative.h
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/14.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#define kCGNullDirectDisplay ((CGDirectDisplayID)0)

typedef uint32_t CGDirectDisplayID;

typedef CGError(*CGDisplayHideCursorFunc)(CGDirectDisplayID);
typedef CGError(*CGDisplayShowCursorFunc)(CGDirectDisplayID);

const NSUInteger NSApplicationPresentationFullScreen;
const NSUInteger NSEventMaskMouseMoved;

CGError CGDisplayHideCursorWrapper(void* handle, CGDirectDisplayID display);
CGError CGDisplayShowCursorWrapper(void* handle, CGDirectDisplayID display);
