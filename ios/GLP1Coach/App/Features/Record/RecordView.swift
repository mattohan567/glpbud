import SwiftUI
import PhotosUI

struct RecordView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("Record Type", selection: $selectedTab) {
                    Text("Meal").tag(0)
                    Text("Exercise").tag(1)
                    Text("Weight").tag(2)
                    Text("Medication").tag(3)
                }
                .pickerStyle(.segmented)
                .padding()
                
                TabView(selection: $selectedTab) {
                    MealRecordView()
                        .tag(0)
                    
                    ExerciseRecordView()
                        .tag(1)
                    
                    WeightRecordView()
                        .tag(2)
                    
                    MedicationRecordView()
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Record")
        }
    }
}

struct MealRecordView: View {
    @State private var recordMode = 0
    
    var body: some View {
        VStack {
            Picker("Input Method", selection: $recordMode) {
                Label("Photo", systemImage: "camera.fill").tag(0)
                Label("Text", systemImage: "text.alignleft").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            if recordMode == 0 {
                MealImageView()
            } else {
                MealTextView()
            }
        }
    }
}

struct MealImageView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var hints = ""
    @State private var draft: MealParseDTO?
    @State private var isLoading = false
    @State private var error: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Image Picker
                PhotosPicker(selection: $selectedItem) {
                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .cornerRadius(12)
                    } else {
                        VStack {
                            Image(systemName: "camera.fill")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("Tap to select photo")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .onChange(of: selectedItem) { newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            selectedImage = image
                        }
                    }
                }
                
                // Hints Field
                VStack(alignment: .leading) {
                    Text("Hints (optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g., grilled chicken with rice", text: $hints)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Parse Button
                Button(action: parseMeal) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Label("Analyze Photo", systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedImage == nil || isLoading)
                
                // Draft Results
                if let draft {
                    MealDraftView(draft: draft, onConfirm: confirmMeal)
                }
                
                // Error Display
                if let error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding()
        }
    }
    
    private func parseMeal() {
        guard selectedImage != nil else { return }
        
        Task {
            isLoading = true
            defer { isLoading = false }
            
            do {
                // In real app, upload image first and get URL
                let imageURL = URL(string: "https://temp.example.com/image.jpg")!
                let result = try await apiClient.parseMealImage(
                    imageURL: imageURL,
                    hints: hints.isEmpty ? nil : hints
                )
                draft = result
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
    
    private func confirmMeal() {
        guard let draft else { return }
        
        let meal = Meal(
            id: UUID(),
            timestamp: Date(),
            source: .image,
            items: draft.items,
            totals: draft.totals,
            confidence: draft.confidence,
            notes: nil
        )
        
        store.addMeal(meal)
        
        // Clear state
        selectedItem = nil
        selectedImage = nil
        hints = ""
        self.draft = nil
        
        // Sync in background
        Task {
            do {
                _ = try await apiClient.logMeal(
                    ts: meal.timestamp,
                    source: "image",
                    parse: draft,
                    notes: nil
                )
                store.updateSyncStatus(for: meal, status: .synced)
            } catch {
                store.updateSyncStatus(for: meal, status: .failed)
            }
        }
    }
}

struct MealTextView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient
    @State private var mealText = ""
    @State private var draft: MealParseDTO?
    @State private var isLoading = false
    @State private var error: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Describe your meal")
                        .font(.headline)
                    
                    TextEditor(text: $mealText)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    
                    Text("Example: 1 cup oatmeal with banana and 1 tbsp peanut butter")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button(action: parseMeal) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Label("Analyze Text", systemImage: "text.magnifyingglass")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(mealText.isEmpty || isLoading)
                
                if let draft {
                    MealDraftView(draft: draft, onConfirm: confirmMeal)
                }
                
                if let error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding()
        }
    }
    
    private func parseMeal() {
        Task {
            isLoading = true
            defer { isLoading = false }
            
            do {
                let result = try await apiClient.parseMealText(text: mealText, hints: nil)
                draft = result
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
    
    private func confirmMeal() {
        guard let draft else { return }
        
        let meal = Meal(
            id: UUID(),
            timestamp: Date(),
            source: .text,
            items: draft.items,
            totals: draft.totals,
            confidence: draft.confidence,
            notes: nil
        )
        
        store.addMeal(meal)
        mealText = ""
        self.draft = nil
        
        Task {
            do {
                _ = try await apiClient.logMeal(
                    ts: meal.timestamp,
                    source: "text",
                    parse: draft,
                    notes: nil
                )
                store.updateSyncStatus(for: meal, status: .synced)
            } catch {
                store.updateSyncStatus(for: meal, status: .failed)
            }
        }
    }
}

struct MealDraftView: View {
    let draft: MealParseDTO
    let onConfirm: () -> Void
    @State private var isEditing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Draft Log")
                    .font(.headline)
                
                Spacer()
                
                if draft.confidence < 0.7 {
                    Label("Low Confidence", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            ForEach(draft.items, id: \.name) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.name)
                            .font(.subheadline)
                        Text("\(Int(item.qty))\(item.unit)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("\(item.kcal) kcal")
                            .font(.subheadline)
                        Text("P: \(Int(item.protein_g))g")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Divider()
            
            HStack {
                Text("Total")
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(draft.totals.kcal) kcal")
                        .font(.headline)
                    Text("P: \(Int(draft.totals.protein_g))g • C: \(Int(draft.totals.carbs_g))g • F: \(Int(draft.totals.fat_g))g")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Button("Edit") {
                    isEditing = true
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Confirm", action: onConfirm)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
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
                TextField("Type (e.g., Running, Cycling)", text: $exerciseType)
                
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
            est_kcal: nil
        )
        
        store.addExercise(exercise)
        
        // Clear form
        exerciseType = ""
        duration = "30"
        intensity = "moderate"
    }
}

struct WeightRecordView: View {
    @EnvironmentObject var store: DataStore
    @State private var weight = ""
    @State private var isKg = true
    
    var body: some View {
        Form {
            Section("Weight") {
                HStack {
                    TextField("Weight", text: $weight)
                        .keyboardType(.decimalPad)
                    
                    Picker("Unit", selection: $isKg) {
                        Text("kg").tag(true)
                        Text("lbs").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
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
                        Text("\(String(format: "%.1f", latest.weight_kg)) kg")
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
        
        let weightKg = isKg ? weightValue : weightValue / 2.205
        
        let weight = Weight(
            id: UUID(),
            timestamp: Date(),
            weight_kg: weightKg,
            method: "manual"
        )
        
        store.addWeight(weight)
        self.weight = ""
    }
}

struct MedicationRecordView: View {
    @EnvironmentObject var store: DataStore
    @State private var drugName = "semaglutide"
    @State private var dose = "0.25"
    @State private var injectionSite = "LLQ"
    @State private var sideEffects: Set<String> = []
    
    let drugOptions = ["semaglutide", "tirzepatide", "liraglutide"]
    let siteOptions = ["LLQ", "RLQ", "LUQ", "RUQ", "thigh_left", "thigh_right"]
    let effectOptions = ["nausea", "fatigue", "headache", "constipation", "diarrhea"]
    
    var body: some View {
        Form {
            Section("Medication") {
                Picker("Drug", selection: $drugName) {
                    ForEach(drugOptions, id: \.self) { drug in
                        Text(drug.capitalized).tag(drug)
                    }
                }
                
                HStack {
                    Text("Dose")
                    TextField("mg", text: $dose)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("mg")
                }
            }
            
            Section("Injection Site") {
                Picker("Site", selection: $injectionSite) {
                    ForEach(siteOptions, id: \.self) { site in
                        Text(site.replacingOccurrences(of: "_", with: " ").capitalized)
                            .tag(site)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Section("Side Effects") {
                ForEach(effectOptions, id: \.self) { effect in
                    HStack {
                        Text(effect.capitalized)
                        Spacer()
                        if sideEffects.contains(effect) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if sideEffects.contains(effect) {
                            sideEffects.remove(effect)
                        } else {
                            sideEffects.insert(effect)
                        }
                    }
                }
            }
            
            Section {
                Button("Log Dose") {
                    logMedication()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private func logMedication() {
        // Log medication event
        NotificationsManager.shared.scheduleMedicationReminder(
            date: Date().addingTimeInterval(7 * 24 * 60 * 60),
            drugName: drugName,
            dose: Double(dose) ?? 0
        )
        
        // Clear form
        dose = "0.25"
        sideEffects = []
    }
}