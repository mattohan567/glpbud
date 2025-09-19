import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @AppStorage("calorie_target") private var calorieTarget = Config.defaultCalorieTarget
    @AppStorage("protein_target") private var proteinTarget = Config.defaultProteinTarget
    @AppStorage("weight_unit") private var weightUnit = Config.defaultWeightUnit
    @State private var showingSignOutAlert = false
    
    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea(.all)

            VStack {
                // Hero Title
                Text("Profile")
                    .font(.heroTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)

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

                    Section("Preferences") {
                        HStack {
                            Image(systemName: "scalemass")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            Text("Weight Unit")
                            Spacer()
                            Picker("Weight Unit", selection: $weightUnit) {
                                ForEach(Config.weightUnits, id: \.self) { unit in
                                    Text(unit.uppercased()).tag(unit)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 100)
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
        .navigationBarHidden(true)
    }
}