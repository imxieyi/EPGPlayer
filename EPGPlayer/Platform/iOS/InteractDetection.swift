//
//  InteractDetection.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/03.
//
//  SPDX-License-Identifier: MPL-2.0

import UIKit

extension Notification.Name {
    // custom notification when user activity is detected
    static let userActivityDetected = Notification.Name("UserActivityDetected")
}

extension UIApplication {
    // names the gesture recognizer so that it can be removed later on
    static let userActivityGestureRecognizer = "userActivityGestureRecognizer"
    
    // Returns `true` if user activity tracker is registered on the app.
    var hasUserActivityTracker: Bool {
        (connectedScenes.first as? UIWindowScene)?.windows.first?.gestureRecognizers?.contains(where: { $0.name == UIApplication.userActivityGestureRecognizer }) == true
    }
    
    // Adds a tap gesture recognizer to intercept any touches, while still
    // propagating interactions to UI elements.
    func addUserActivityTracker() {
        guard let window = (connectedScenes.first as? UIWindowScene)?.windows.first else {
            return
        }
        let gesture = UITapGestureRecognizer(target: window, action: nil)
        gesture.requiresExclusiveTouchType = false
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        gesture.name = UIApplication.userActivityGestureRecognizer
        window.addGestureRecognizer(gesture)
    }
    
    // Removes the tap gesture recognizer that detects user interactions.
    func removeUserActivityTracker() {
        guard let window = (connectedScenes.first as? UIWindowScene)?.windows.first,
              let gesture = window.gestureRecognizers?.first(where: { $0.name == UIApplication.userActivityGestureRecognizer })
        else {
            return
        }
        window.removeGestureRecognizer(gesture)
    }
}

extension UIApplication: @retroactive UIGestureRecognizerDelegate {
    // Send a notification whenever a touch is detected.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldReceive touch: UITouch) -> Bool {
        NotificationCenter.default.post(name: .userActivityDetected, object: nil)
        return true
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
