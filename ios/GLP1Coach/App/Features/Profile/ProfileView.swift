import SwiftUI

struct ProfileView: View {
    @AppStorage("user_height") private var height = "170"
    @AppStorage("user_weight") private var weight = "70"
    @AppStorage("user_sex") private var sex = "male"
    @AppStorage("activity_level") private var activityLevel = "moderate"
    @AppStorage("protein_target") private var proteinTarget = "100"
    @AppStorage("calorie_target") private var calorieTarget = "1800"
    
    @State private var showingSettings = false
    @State private var showingAbout = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Personal Info") {
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("cm", text: $height)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("cm")
                    }
                    
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("kg", text: $weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("kg")
                    }
                    
                    Picker("Sex", selection: $sex) {
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                        Text("Other").tag("other")
                    }
                    
                    Picker("Activity Level", selection: $activityLevel) {
                        Text("Sedentary").tag("sedentary")
                        Text("Light").tag("light")
                        Text("Moderate").tag("moderate")
                        Text("Active").tag("active")
                        Text("Very Active").tag("very_active")
                    }
                }
                
                Section("Daily Targets") {
                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("kcal", text: $calorieTarget)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("kcal")
                    }
                    
                    HStack {
                        Text("Protein")
                        Spacer()
                        TextField("g", text: $proteinTarget)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g")
                    }
                }
                
                Section("Medication Schedule") {
                    NavigationLink(destination: MedicationScheduleView()) {
                        HStack {
                            Image(systemName: "pills.fill")
                                .foregroundColor(.blue)
                            Text("Manage Schedule")
                        }
                    }
                }
                
                Section {
                    Button(action: { showingSettings = true }) {
                        HStack {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.gray)
                            Text("Settings")
                        }
                    }
                    
                    Button(action: { showingAbout = true }) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("About")
                        }
                    }
                    
                    Button(action: exportData) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.green)
                            Text("Export Data")
                        }
                    }
                }
                
                Section {
                    Button(action: signOut) {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
        }
    }
    
    private func exportData() {
        // Export user data as CSV or JSON
    }
    
    private func signOut() {
        UserDefaults.standard.removeObject(forKey: "supabase_jwt")
        // Navigate to login
    }
}

struct MedicationScheduleView: View {
    @EnvironmentObject var store: DataStore
    @State private var drugName = "semaglutide"
    @State private var dose = "0.25"
    @State private var frequency = "weekly"
    @State private var startDate = Date()
    @State private var notes = ""
    
    var body: some View {
        Form {
            Section("Current Schedule") {
                if let medication = store.medications.first(where: { $0.active }) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(medication.drug_name.capitalized)
                                .font(.headline)
                            Spacer()
                            Text("\(String(format: "%.2f", medication.dose_mg))mg")
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Every \(medication.schedule_rule)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if let notes = medication.notes {
                            Text(notes)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("No active medication schedule")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Add/Update Schedule") {
                Picker("Medication", selection: $drugName) {
                    Text("Semaglutide (Ozempic/Wegovy)").tag("semaglutide")
                    Text("Tirzepatide (Mounjaro/Zepbound)").tag("tirzepatide")
                    Text("Liraglutide (Saxenda)").tag("liraglutide")
                    Text("Other").tag("other")
                }
                
                HStack {
                    Text("Dose")
                    TextField("mg", text: $dose)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("mg")
                }
                
                Picker("Frequency", selection: $frequency) {
                    Text("Daily").tag("daily")
                    Text("Weekly").tag("weekly")
                    Text("Every 2 Weeks").tag("biweekly")
                    Text("Monthly").tag("monthly")
                }
                
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                
                TextField("Notes (optional)", text: $notes)
            }
            
            Section {
                Button("Save Schedule") {
                    saveSchedule()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Medication Schedule")
    }
    
    private func saveSchedule() {
        // Save medication schedule
        NotificationsManager.shared.scheduleMedicationReminder(
            date: startDate,
            drugName: drugName,
            dose: Double(dose) ?? 0
        )
    }
}

struct SettingsView: View {
    @AppStorage("notifications_enabled") private var notificationsEnabled = true
    @AppStorage("use_metric") private var useMetric = true
    @AppStorage("dark_mode") private var darkMode = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Notifications") {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                    Toggle("Medication Reminders", isOn: .constant(true))
                    Toggle("Weekly Summary", isOn: .constant(true))
                }
                
                Section("Units") {
                    Toggle("Use Metric Units", isOn: $useMetric)
                }
                
                Section("Appearance") {
                    Toggle("Dark Mode", isOn: $darkMode)
                }
                
                Section("Privacy") {
                    Button("Clear Cache") {
                        DataStore().meals = []
                        DataStore().exercises = []
                        DataStore().weights = []
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct AboutView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("GLP-1 Coach")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Version 1.0.0")
                    .foregroundColor(.secondary)
                
                Text("Your AI-powered companion for GLP-1 weight management")
                    .multilineTextAlignment(.center)
                    .padding()
                
                VStack(alignment: .leading, spacing: 12) {
                    Label("Powered by Claude AI", systemImage: "brain")
                    Label("Built with SwiftUI", systemImage: "swift")
                    Label("Secure & Private", systemImage: "lock.shield")
                }
                
                Spacer()
                
                Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://example.com/terms")!)
                
                Spacer()
            }
            .padding()
            .navigationTitle("About")
        }
    }
}