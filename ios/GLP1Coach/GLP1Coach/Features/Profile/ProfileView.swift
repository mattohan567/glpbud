import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @AppStorage("calorie_target") private var calorieTarget = Config.defaultCalorieTarget
    @AppStorage("protein_target") private var proteinTarget = Config.defaultProteinTarget
    @State private var showingSignOutAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Account") {
                    if let user = authManager.currentUser {
                        HStack {
                            Text("Email")
                            Spacer()
                            Text(user.email ?? "")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Daily Targets") {
                    HStack {
                        Text("Calories")
                        Spacer()
                        Text("\(calorieTarget) kcal")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Protein")
                        Spacer()
                        Text("\(proteinTarget) g")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Config.appVersion)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button(action: { showingSignOutAlert = true }) {
                        Text("Sign Out")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Profile")
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    Task {
                        try? await authManager.signOut()
                    }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }
}