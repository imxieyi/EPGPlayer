//
//  EventEditView.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/07/30.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftUI
import EventKit
import EventKitUI

struct EventEditView: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    
    @Binding var event: EKEvent?
    let eventStore: EKEventStore
    
    /// Create an event edit view controller, then configure it with the specified event and event store.
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = eventStore
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
    
    class Coordinator: NSObject, @preconcurrency EKEventEditViewDelegate {
        var parent: EventEditView
        
        init(_ controller: EventEditView) {
            self.parent = controller
        }
        
        @MainActor func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
