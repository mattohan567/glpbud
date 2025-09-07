import SwiftUI

@main
struct GLP1CoachApp: App {
    @StateObject private var store = DataStore()
    @StateObject private var apiClient = APIClient()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(apiClient)
                .onAppear {
                    setupApp()
                }
        }
    }
    
    private func setupApp() {
        // Configure notifications
        NotificationsManager.shared.requestAuthorization()
        
        // Setup background tasks
        BackgroundTaskManager.shared.registerTasks()
        
        // Load cached data
        store.loadCachedData()
    }
}

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }
                .tag(0)
            
            RecordView()
                .tabItem {
                    Label("Record", systemImage: "plus.circle.fill")
                }
                .tag(1)
            
            CoachView()
                .tabItem {
                    Label("Coach", systemImage: "message.fill")
                }
                .tag(2)
            
            TrendsView()
                .tabItem {
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(3)
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(4)
        }
        .accentColor(.blue)
    }
}