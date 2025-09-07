import Foundation
import UserNotifications

final class NotificationsManager {
    static let shared = NotificationsManager()
    
    private init() {}
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Notification authorization granted")
                self.setupNotificationCategories()
            } else if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
    }
    
    private func setupNotificationCategories() {
        let logMealAction = UNNotificationAction(
            identifier: "LOG_MEAL",
            title: "Log Meal",
            options: .foreground
        )
        
        let skipAction = UNNotificationAction(
            identifier: "SKIP",
            title: "Skip",
            options: .destructive
        )
        
        let medicationCategory = UNNotificationCategory(
            identifier: "MEDICATION_REMINDER",
            actions: [logMealAction, skipAction],
            intentIdentifiers: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([medicationCategory])
    }
    
    func scheduleMedicationReminder(date: Date, drugName: String, dose: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Medication Reminder"
        content.body = "Time for your \(drugName) (\(dose)mg) dose"
        content.sound = .default
        content.categoryIdentifier = "MEDICATION_REMINDER"
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "med_\(date.timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }
    
    func scheduleWeeklySummary() {
        let content = UNMutableNotificationContent()
        content.title = "Weekly Progress"
        content.body = "Check your weekly summary and insights"
        content.sound = .default
        
        var components = DateComponents()
        components.weekday = 1  // Sunday
        components.hour = 19    // 7 PM
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        
        let request = UNNotificationRequest(
            identifier: "weekly_summary",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}