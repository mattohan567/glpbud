import Foundation
import Supabase
import Combine

@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = true
    @Published var errorMessage: String?
    
    private var supabase: SupabaseClient!
    private var authStateListener: Task<Void, Never>?
    private weak var dataStore: DataStore?
    
    static let shared = AuthManager()
    
    private init() {
        supabase = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
        
        setupAuthListener()
    }
    
    func setDataStore(_ dataStore: DataStore) {
        self.dataStore = dataStore
    }
    
    private func setupAuthListener() {
        authStateListener = Task {
            for await (event, session) in supabase.auth.authStateChanges {
                await handleAuthStateChange(event)
            }
        }
        
        // Check initial auth state
        Task {
            do {
                let session = try await supabase.auth.session
                await MainActor.run {
                    self.currentUser = session.user
                    self.isAuthenticated = true
                    self.isLoading = false
                    UserDefaults.standard.set(session.accessToken, forKey: "supabase_jwt")
                }
            } catch {
                await MainActor.run {
                    self.isAuthenticated = false
                    self.isLoading = false
                }
            }
        }
    }
    
    private func handleAuthStateChange(_ event: AuthChangeEvent) async {
        switch event {
        case .signedIn:
            do {
                let session = try await supabase.auth.session
                await MainActor.run {
                    self.currentUser = session.user
                    self.isAuthenticated = true
                    UserDefaults.standard.set(session.accessToken, forKey: "supabase_jwt")
                }
            } catch {
                print("Error getting session: \(error)")
            }
            
        case .signedOut:
            await MainActor.run {
                self.currentUser = nil
                self.isAuthenticated = false
                UserDefaults.standard.removeObject(forKey: "supabase_jwt")
                self.dataStore?.clearAllData()
            }
            
        default:
            break
        }
    }
    
    func signUp(email: String, password: String) async throws {
        errorMessage = nil
        do {
            let response = try await supabase.auth.signUp(
                email: email,
                password: password
            )
            
            let user = response.user
            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
                if let session = response.session {
                    UserDefaults.standard.set(session.accessToken, forKey: "supabase_jwt")
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    func signIn(email: String, password: String) async throws {
        errorMessage = nil
        
        #if DEBUG
        // Development bypass for testing without Supabase
        if email == "test@example.com" && password == "test123456" {
            print("🔧 Using development bypass for testing")
            await MainActor.run {
                // Create a mock user for testing
                self.isAuthenticated = true
                UserDefaults.standard.set("test-token", forKey: "supabase_jwt")
                // Note: currentUser will remain nil in bypass mode
            }
            return
        }
        #endif
        
        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            
            await MainActor.run {
                self.currentUser = session.user
                self.isAuthenticated = true
                UserDefaults.standard.set(session.accessToken, forKey: "supabase_jwt")
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    func signOut() async throws {
        do {
            try await supabase.auth.signOut()
            await MainActor.run {
                self.currentUser = nil
                self.isAuthenticated = false
                UserDefaults.standard.removeObject(forKey: "supabase_jwt")
                self.dataStore?.clearAllData()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    func getAccessToken() async -> String? {
        #if DEBUG
        // In debug mode, return test token if authenticated via bypass
        if isAuthenticated && currentUser == nil {
            return "test-token"
        }
        #endif

        do {
            let session = try await supabase.auth.session
            await MainActor.run {
                UserDefaults.standard.set(session.accessToken, forKey: "supabase_jwt")
            }
            return session.accessToken
        } catch {
            print("Error getting access token: \(error)")

            // If we can't get a valid token, sign the user out
            await MainActor.run {
                self.currentUser = nil
                self.isAuthenticated = false
                UserDefaults.standard.removeObject(forKey: "supabase_jwt")
                self.dataStore?.clearAllData()
            }
            return nil
        }
    }

    func handleTokenExpiry() async {
        print("🔄 Handling token expiry - attempting refresh")

        do {
            let session = try await supabase.auth.session
            await MainActor.run {
                self.currentUser = session.user
                self.isAuthenticated = true
                UserDefaults.standard.set(session.accessToken, forKey: "supabase_jwt")
            }
        } catch {
            print("❌ Token refresh failed: \(error)")
            await MainActor.run {
                self.currentUser = nil
                self.isAuthenticated = false
                UserDefaults.standard.removeObject(forKey: "supabase_jwt")
                self.dataStore?.clearAllData()
                self.errorMessage = "Session expired. Please sign in again."
            }
        }
    }
    
    deinit {
        authStateListener?.cancel()
    }
}