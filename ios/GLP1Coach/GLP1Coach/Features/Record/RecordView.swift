import SwiftUI

struct RecordView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("Record Type", selection: $selectedTab) {
                    Text("Meal").tag(0)
                    Text("Exercise").tag(1)
                    Text("Weight").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                TabView(selection: $selectedTab) {
                    MealRecordView().tag(0)
                    ExerciseRecordView().tag(1)
                    WeightRecordView().tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Record")
        }
    }
}

struct MealRecordView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient
    @State private var mealText = ""
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Describe your meal")
                    .font(.headline)
                
                TextEditor(text: $mealText)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                
                Text("Example: Grilled chicken breast 200g with rice")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button(action: parseMeal) {
                if isLoading {
                    ProgressView()
                } else {
                    Label("Analyze & Log", systemImage: "text.magnifyingglass")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(mealText.isEmpty || isLoading)
            
            Spacer()
        }
        .padding()
        .alert("Meal Logging", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func parseMeal() {
        isLoading = true
        Task {
            do {
                let parsed = try await apiClient.parseMealText(text: mealText)
                let meal = Meal(
                    id: UUID(),
                    timestamp: Date(),
                    source: .text,
                    items: parsed.items,
                    totals: parsed.totals,
                    confidence: parsed.confidence,
                    notes: nil
                )
                
                await MainActor.run {
                    store.addMeal(meal)
                    mealText = ""
                    alertMessage = "Meal logged: \(parsed.totals.kcal) kcal"
                    showingAlert = true
                    isLoading = false
                }
                
                // Sync in background
                _ = try? await apiClient.logMeal(meal: meal, parse: parsed)
                
            } catch {
                await MainActor.run {
                    alertMessage = "Error: \(error.localizedDescription)"
                    showingAlert = true
                    isLoading = false
                }
            }
        }
    }
}

struct ExerciseRecordView: View {
    @EnvironmentObject var store: DataStore
    @State private var exerciseType = ""
    @State private var duration = "30"
    @State private var intensity = "moderate"
    
    var body: some View {
        Form {
            Section("Exercise Details") {
                TextField("Type (e.g., Running)", text: $exerciseType)
                
                HStack {
                    Text("Duration")
                    TextField("Minutes", text: $duration)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text("min")
                }
                
                Picker("Intensity", selection: $intensity) {
                    Text("Low").tag("low")
                    Text("Moderate").tag("moderate")
                    Text("High").tag("high")
                }
            }
            
            Section {
                Button("Log Exercise") {
                    logExercise()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private func logExercise() {
        guard !exerciseType.isEmpty,
              let durationMin = Double(duration) else { return }
        
        let exercise = Exercise(
            id: UUID(),
            timestamp: Date(),
            type: exerciseType,
            duration_min: durationMin,
            intensity: intensity,
            est_kcal: Int(durationMin * 5) // Simple estimate
        )
        
        store.addExercise(exercise)
        exerciseType = ""
        duration = "30"
    }
}

struct WeightRecordView: View {
    @EnvironmentObject var store: DataStore
    @State private var weight = ""
    
    var body: some View {
        Form {
            Section("Weight") {
                HStack {
                    TextField("Weight", text: $weight)
                        .keyboardType(.decimalPad)
                    Text("kg")
                }
            }
            
            Section {
                Button("Log Weight") {
                    logWeight()
                }
                .frame(maxWidth: .infinity)
            }
            
            if let latest = store.latestWeight {
                Section("Previous") {
                    HStack {
                        Text(String(format: "%.1f kg", latest.weight_kg))
                        Spacer()
                        Text(latest.timestamp, style: .date)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private func logWeight() {
        guard let weightValue = Double(weight) else { return }
        
        let weightEntry = Weight(
            id: UUID(),
            timestamp: Date(),
            weight_kg: weightValue,
            method: "manual"
        )
        
        store.addWeight(weightEntry)
        weight = ""
    }
}