//
//  MacNative.m
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/14.
//

#import "MacNative.h"

const NSUInteger NSApplicationPresentationFullScreen = (1 << 10);
const NSUInteger NSEventTypeMouseMoved = 5;
const NSUInteger NSEventMaskMouseMoved = 1ULL << NSEventTypeMouseMoved;

CGError CGDisplayHideCursorWrapper(void* handle, CGDirectDisplayID display) {
    return ((CGDisplayHideCursorFunc)handle)(display);
}

CGError CGDisplayShowCursorWrapper(void* handle, CGDirectDisplayID display) {
    return ((CGDisplayShowCursorFunc)handle)(display);
}
