import Foundation

struct Config {
    // Supabase Configuration - Your actual credentials
    static let supabaseURL = "https://hugqvmmdfuwounhalpxd.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh1Z3F2bW1kZnV3b3VuaGFscHhkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcyNzU2ODYsImV4cCI6MjA3Mjg1MTY4Nn0.BrEesh_FXt02A5Ebx-FoJy-rMoVmOLgjVDdBNTNrfAE"
    
    // API Configuration  
    static let apiBaseURL = "https://glp1coach-api.fly.dev"
    
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