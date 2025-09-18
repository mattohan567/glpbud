import Foundation

struct Config {
    // Supabase Configuration - Load from environment or Info.plist
    static let supabaseURL: String = {
        if let url = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String {
            return url
        }
        // Fallback for development - should be set in Info.plist or environment
        return ProcessInfo.processInfo.environment["SUPABASE_URL"] ?? "https://hugqvmmdfuwounhalpxd.supabase.co"
    }()
    
    static let supabaseAnonKey: String = {
        if let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String {
            return key
        }
        // Fallback for development - should be set in Info.plist or environment
        return ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh1Z3F2bW1kZnV3b3VuaGFscHhkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcyNzU2ODYsImV4cCI6MjA3Mjg1MTY4Nn0.BrEesh_FXt02A5Ebx-FoJy-rMoVmOLgjVDdBNTNrfAE"
    }()
    
    // API Configuration
    #if DEBUG
    static let apiBaseURL = "http://192.168.86.29:8000"  // Local development - Mac's IP for iPhone testing
    #else
    static let apiBaseURL = "https://glp1coach-api.fly.dev"  // Production
    #endif
    
    // Development Configuration
    #if DEBUG
    static let isDevelopment = true
    static let testEmail = "test@example.com"
    static let testPassword = "test123456"
    #else
    static let isDevelopment = false
    #endif
    
    // App Configuration
    static let appVersion = "1.0.0"
    static let appName = "GLP-1 Coach"
    static let bundleIdentifier = "com.glp1coach.GLP1Coach"
    
    // Health & Fitness Defaults
    static let defaultCalorieTarget = 1800
    static let defaultProteinTarget = 100
    static let defaultWeightUnit = "kg"
    static let defaultHeightUnit = "cm"
}