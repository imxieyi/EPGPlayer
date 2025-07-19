//
//  EPGNotifier.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/07/12.
//
//  SPDX-License-Identifier: MPL-2.0

import Foundation
import EventKit
@preconcurrency import UserNotifications

@Observable
class EPGNotifier {
    
    var setProgramIds: Set<String> = []
    
    @MainActor
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            Logger.info("Notification granted: \(granted)")
            return granted
        } catch let error {
            Logger.error("Error requesting permission: \(error.localizedDescription)")
        }
        return false
    }
    
    @MainActor
    func updateSetProgramIds() async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        setProgramIds.removeAll()
        requests.forEach { request in
            setProgramIds.insert(request.identifier)
        }
    }
    
    @MainActor
    func addProgram(channel: Components.Schemas.ScheduleChannleItem, program: Components.Schemas.ScheduleProgramItem, timeDiff: TimeInterval) async {
        let strId = String(program.id)
        guard !setProgramIds.contains(strId) else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = program.name
        content.body = String("\(Date(timeIntervalSince1970: TimeInterval(program.startAt / 1000)).formatted(RecordingCell.startDateFormatStyle)) \(channel.name)")
        content.sound = .default
        let startDate = Date(timeIntervalSince1970: TimeInterval(program.startAt / 1000))
        let notifyDate = startDate.addingTimeInterval(timeDiff)
        if notifyDate <= Date.now {
            return
        }
        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notifyDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(identifier: strId, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch let error {
            Logger.error("Failed to add notification: \(error.localizedDescription)")
            return
        }
        setProgramIds.insert(strId)
    }
    
    func removeProgram(program: Components.Schemas.ScheduleProgramItem) {
        let strId = String(program.id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [strId])
        setProgramIds.remove(strId)
    }
    
    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        setProgramIds.removeAll()
    }
}
