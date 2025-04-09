//
//  Swizzle.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/10.
//
//  https://gist.github.com/JunyuKuang/042e782f451f02970ebed82ef882ccf2

import Foundation

@discardableResult
public func swizzleInstanceMethod(class aClass: AnyClass?, originalSelector: Selector, swizzledSelector: Selector) -> Bool {
    swizzleMethod(class: aClass, originalSelector: originalSelector, swizzledSelector: swizzledSelector, isClassMethod: false)
}

@discardableResult
public func swizzleClassMethod(class aClass: AnyClass?, originalSelector: Selector, swizzledSelector: Selector) -> Bool {
    swizzleMethod(class: aClass, originalSelector: originalSelector, swizzledSelector: swizzledSelector, isClassMethod: true)
}

private func swizzleMethod(class aClass: AnyClass?, originalSelector: Selector, swizzledSelector: Selector, isClassMethod: Bool) -> Bool {
    
    guard var aClass = aClass else {
        assertionFailure("class not exist.")
        return false
    }
    
    if isClassMethod {
        if let _class = NSStringFromClass(aClass).withCString(objc_getMetaClass) as? AnyClass {
            aClass = _class
        } else {
            assertionFailure("meta class not found.")
        }
    }
    
    guard let originalMethod = isClassMethod ? class_getClassMethod(aClass, originalSelector) : class_getInstanceMethod(aClass, originalSelector),
          let swizzledMethod = isClassMethod ? class_getClassMethod(aClass, swizzledSelector) : class_getInstanceMethod(aClass, swizzledSelector)
    else {
        assertionFailure("\(isClassMethod ? "class" : "instance") method unavailable. class: \(aClass) originalSelector: \(originalSelector) swizzledSelector: \(swizzledSelector)")
        return false
    }
    if class_addMethod(aClass, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod)) {
        class_replaceMethod(aClass, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
#if DEBUG
        implementationReplacedClassesBySelectors[NSStringFromSelector(originalSelector), default: []].append(NSStringFromClass(aClass))
#endif
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod)
#if DEBUG
        for className in implementationReplacedClassesBySelectors[NSStringFromSelector(originalSelector)] ?? [] {
            if let bClass = NSClassFromString(className) {
                assert(!bClass.isSubclass(of: aClass), "Swizzle order is reversed: When calling \"\(originalSelector)\" on the subclass \(bClass), the swizzled methods on its superclass \(aClass) may never be called, which may cause unpredictable issues. Please swizzle superclass methods first, then swizzle subclass methods.")
            } else {
                assertionFailure("\(className) no longer exists")
            }
        }
#endif
    }
    return true
}

#if DEBUG
private var implementationReplacedClassesBySelectors = [String : [String]]()
#endif
