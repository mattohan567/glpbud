import Foundation
import BackgroundTasks

final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    private let syncTaskIdentifier = "com.glp1coach.sync"
    
    private init() {}
    
    func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: syncTaskIdentifier, using: nil) { task in
            self.handleSyncTask(task as! BGAppRefreshTask)
        }
    }
    
    func scheduleSyncTask() {
        let request = BGAppRefreshTaskRequest(identifier: syncTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background task: \(error)")
        }
    }
    
    private func handleSyncTask(_ task: BGAppRefreshTask) {
        task.expirationHandler = {
            // Clean up if task expires
            task.setTaskCompleted(success: false)
        }
        
        Task {
            do {
                // Sync pending data
                await DataStore().syncPendingItems()
                
                // Fetch latest today stats
                let apiClient = APIClient()
                let todayStats = try await apiClient.getToday()
                
                await MainActor.run {
                    DataStore().todayStats = todayStats
                }
                
                task.setTaskCompleted(success: true)
                
                // Schedule next sync
                scheduleSyncTask()
            } catch {
                print("Background sync failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
    }
}