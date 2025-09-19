import SwiftUI

// MARK: - Navigation Extensions

extension Notification.Name {
    static let navigateToRecord = Notification.Name("navigateToRecord")
    static let navigateToTab = Notification.Name("navigateToTab")
}

struct NavigationInfo {
    let recordTab: Int
}

struct TabNavigationInfo {
    let tabIndex: Int
}

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
        // Connect DataStore to AuthManager for logout cleanup
        authManager.setDataStore(store)
        
        // Update API client with auth token
        Task {
            if let token = await authManager.getAccessToken() {
                await apiClient.updateAuthToken(token)
            }
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var recordTabIndex = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content based on selected tab
            Group {
                switch selectedTab {
                case 0:
                    NavigationView {
                        TodayView()
                    }
                    .padding(.bottom, 100) // Space for floating tab bar
                case 1:
                    NavigationView {
                        RecordView(initialTab: recordTabIndex)
                    }
                    .padding(.bottom, 100)
                case 2:
                    NavigationView {
                        CoachView()
                    }
                    .padding(.bottom, 100)
                case 3:
                    NavigationView {
                        HistoryView()
                    }
                    .padding(.bottom, 100)
                case 4:
                    NavigationView {
                        TrendsView()
                    }
                    .padding(.bottom, 100)
                case 5:
                    NavigationView {
                        ProfileView()
                    }
                    .padding(.bottom, 100)
                default:
                    NavigationView {
                        TodayView()
                    }
                    .padding(.bottom, 100)
                }
            }

            // Custom floating tab bar
            FloatingTabBar(selection: $selectedTab)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToRecord)) { notification in
            if let navigationInfo = notification.object as? NavigationInfo {
                recordTabIndex = navigationInfo.recordTab
            }
            selectedTab = 1 // Navigate to Record tab
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTab)) { notification in
            if let tabInfo = notification.object as? TabNavigationInfo {
                selectedTab = tabInfo.tabIndex
            }
        }
    }
}