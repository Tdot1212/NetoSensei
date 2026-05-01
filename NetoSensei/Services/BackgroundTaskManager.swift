//
//  BackgroundTaskManager.swift
//  NetoSensei
//
//  Manages background execution so tasks continue when the app is minimized.
//  Uses UIApplication.beginBackgroundTask for immediate background work and
//  sends notifications when tasks complete in the background.
//

import Foundation
import BackgroundTasks
import UIKit
import UserNotifications

@MainActor
class BackgroundTaskManager: ObservableObject {
    static let shared = BackgroundTaskManager()

    // MARK: - Published State
    @Published var activeTasks: [String: TaskState] = [:]

    struct TaskState: Identifiable {
        let id: String
        var name: String
        var progress: Double
        var status: String
        var startTime: Date
        var isComplete: Bool
        var result: String?
    }

    // MARK: - Active Background Task IDs
    private var backgroundTaskIDs: [String: UIBackgroundTaskIdentifier] = [:]

    private init() {
        requestNotificationPermission()
    }

    // MARK: - Request Notification Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("[BackgroundTask] Notification permission: \(granted)")
        }
    }

    // MARK: - Begin Background Task

    /// Call this at the START of any async function that should continue in background
    func beginTask(id: String, name: String) -> String {
        let taskID = "\(id)_\(UUID().uuidString.prefix(8))"

        let bgTaskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.forceEndTask(taskID)
        }

        backgroundTaskIDs[taskID] = bgTaskID

        activeTasks[taskID] = TaskState(
            id: taskID,
            name: name,
            progress: 0,
            status: "Starting...",
            startTime: Date(),
            isComplete: false,
            result: nil
        )

        print("[BackgroundTask] Started: \(name) (\(taskID))")
        return taskID
    }

    // MARK: - Update Progress

    func updateTask(_ taskID: String, progress: Double, status: String) {
        guard var state = activeTasks[taskID] else { return }
        state.progress = progress
        state.status = status
        activeTasks[taskID] = state
    }

    // MARK: - Complete Task

    func completeTask(_ taskID: String, result: String, notify: Bool = true) {
        guard var state = activeTasks[taskID] else { return }

        state.progress = 1.0
        state.status = "Complete"
        state.isComplete = true
        state.result = result
        activeTasks[taskID] = state

        print("[BackgroundTask] Completed: \(state.name) - \(result)")

        // Send notification if app is in background
        if notify && UIApplication.shared.applicationState != .active {
            sendNotification(title: "\(state.name) Complete", body: result)
        }

        // End the background task
        endTask(taskID)
    }

    // MARK: - End Task

    func endTask(_ taskID: String) {
        if let bgTaskID = backgroundTaskIDs[taskID] {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            backgroundTaskIDs.removeValue(forKey: taskID)
        }

        // Remove from active tasks after a delay (so UI can show completion)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.activeTasks.removeValue(forKey: taskID)
        }
    }

    private func forceEndTask(_ taskID: String) {
        print("[BackgroundTask] Force ending: \(taskID)")
        if var state = activeTasks[taskID] {
            state.status = "Interrupted"
            state.isComplete = true
            activeTasks[taskID] = state
        }
        endTask(taskID)
    }

    // MARK: - Send Notification

    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Convenience Wrapper

    /// Wraps any async function with background execution
    func runInBackground<T>(
        id: String,
        name: String,
        operation: @escaping () async -> T,
        resultFormatter: @escaping (T) -> String = { _ in "Done" }
    ) async -> T {
        let taskID = beginTask(id: id, name: name)

        let result = await operation()

        let resultString = resultFormatter(result)
        completeTask(taskID, result: resultString)

        return result
    }
}
