import SwiftUI

@main
struct GLP1CoachApp: App {
    @StateObject private var store = DataStore()
    @StateObject private var apiClient = APIClient()
    @StateObject private var authManager = AuthManager.shared
    
    var body: some Scene {
        WindowGroup {
            if authManager.isLoading {
                // Loading screen while checking auth state
                VStack {
                    ProgressView()
                    Text("Loading...")
                        .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else if authManager.isAuthenticated {
                // Main app content for authenticated users
                MainTabView()
                    .environmentObject(store)
                    .environmentObject(apiClient)
                    .environmentObject(authManager)
                    .onAppear {
                        setupApp()
                    }
            } else {
                // Authentication view for non-authenticated users
                AuthView()
                    .environmentObject(authManager)
            }
        }
    }
    
    private func setupApp() {
        // Update API client with auth token
        Task {
            if let token = await authManager.getAccessToken() {
                await apiClient.updateAuthToken(token)
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }
            
            RecordView()
                .tabItem {
                    Label("Record", systemImage: "plus.circle")
                }
            
            CoachView()
                .tabItem {
                    Label("Coach", systemImage: "message")
                }
            
            TrendsView()
                .tabItem {
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
        }
        .accentColor(.blue)
    }
}