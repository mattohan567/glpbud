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
    
    static let shared = AuthManager()
    
    private init() {
        supabase = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
        
        setupAuthListener()
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
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    func getAccessToken() async -> String? {
        do {
            let session = try await supabase.auth.session
            return session.accessToken
        } catch {
            return nil
        }
    }
    
    deinit {
        authStateListener?.cancel()
    }
}