import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var apiClient: APIClient
    @State private var entries: [HistoryEntryResp] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFilter: HistoryEntryResp.EntryType? = nil
    @State private var selectedEntry: HistoryEntryResp? = nil
    @State private var showingEditSheet = false
    @State private var sortOrder: SortOrder = .newestFirst
    
    enum SortOrder: String, CaseIterable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        
        var systemImage: String {
            switch self {
            case .newestFirst: return "arrow.down"
            case .oldestFirst: return "arrow.up"
            }
        }
    }

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea(.all)

            VStack {
                // Hero Title
                Text("History")
                    .font(.heroTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        // Filter buttons
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                FilterButton(title: "All", isSelected: selectedFilter == nil) {
                                    selectedFilter = nil
                                    Task { await loadHistory() }
                                }
                                
                                ForEach(HistoryEntryResp.EntryType.allCases, id: \.self) { type in
                                    FilterButton(
                                        title: type.displayName,
                                        isSelected: selectedFilter == type,
                                        icon: type.icon
                                    ) {
                                        selectedFilter = type
                                        Task { await loadHistory() }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical, 10)
                        
                        // Sort picker
                        HStack {
                            Text("Sort by:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("Sort Order", selection: $sortOrder) {
                                ForEach(SortOrder.allCases, id: \.self) { order in
                                    HStack {
                                        Image(systemName: order.systemImage)
                                        Text(order.rawValue)
                                    }
                                    .tag(order)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: sortOrder) { _, _ in
                                sortEntries()
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        
                        // History list
                        if entries.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "clock")
                                    .font(.system(size: 50))
                                    .foregroundColor(.secondary)
                                Text("No entries found")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("Your logged meals, exercises, and weights will appear here")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List {
                                ForEach(entries) { entry in
                                    HistoryEntryRow(entry: entry) {
                                        selectedEntry = entry
                                        showingEditSheet = true
                                    }
                                }
                            }
                            .refreshable {
                                await loadHistory()
                            }
                        }
                    }
                }
            }
            .task {
                await loadHistory()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showingEditSheet) {
                if let entry = selectedEntry {
                    EditEntrySheet(entry: entry) {
                        showingEditSheet = false
                        selectedEntry = nil
                        Task { await loadHistory() }
                    }
                    .environmentObject(apiClient)
                }
            }
        }
        .tapToDismissKeyboard()
    }
    
    private func loadHistory() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await apiClient.getHistory(
                typeFilter: selectedFilter?.rawValue
            )
            await MainActor.run {
                entries = response.entries
                sortEntries()
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load history: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func sortEntries() {
        switch sortOrder {
        case .newestFirst:
            entries.sort { $0.ts > $1.ts }
        case .oldestFirst:
            entries.sort { $0.ts < $1.ts }
        }
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let icon: String?
    let action: () -> Void
    
    init(title: String, isSelected: Bool, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.icon = icon
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

struct HistoryEntryRow: View {
    let entry: HistoryEntryResp
    let onEdit: () -> Void
    
    var body: some View {
        HStack {
            // Icon
            Image(systemName: entry.type.icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(entry.display_name)
                    .font(.headline)
                    .lineLimit(1)
                
                // Timestamp
                Text(entry.ts.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Details
                Text(detailText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Edit button
            Button("Edit", action: onEdit)
                .font(.caption)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
    
    private var detailText: String {
        switch entry.type {
        case .meal:
            let items = entry.details["items"] as? [[String: Any]] ?? []
            let totalKcal = entry.details["total_kcal"] as? Int ?? 0
            return "\(items.count) items • \(totalKcal) kcal"
            
        case .exercise:
            // Handle both Int and Double for duration
            let duration = (entry.details["duration_min"] as? Double) ??
                          Double(entry.details["duration_min"] as? Int ?? 0)
            // Handle both Int and Double for calories
            let kcal = (entry.details["est_kcal"] as? Int) ??
                      (entry.details["est_kcal"] as? Double).map { Int($0) }
            if let kcal = kcal {
                return "\(Int(duration))min • \(kcal) kcal burned"
            } else {
                return "\(Int(duration)) minutes"
            }
            
        case .weight:
            // Handle both Int and Double for weight_kg
            let weight = (entry.details["weight_kg"] as? Double) ??
                        Double(entry.details["weight_kg"] as? Int ?? 0)
            return "\(String(format: "%.1f", weight)) kg"
            
        case .medication:
            return "Medication dose"
        }
    }
}

struct EditEntrySheet: View {
    let entry: HistoryEntryResp
    let onSave: () -> Void
    @EnvironmentObject private var apiClient: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch entry.type {
                    case .meal:
                        EditMealView(entry: entry, onSave: handleSave)
                    case .exercise:
                        EditExerciseView(entry: entry, onSave: handleSave)
                    case .weight:
                        EditWeightView(entry: entry, onSave: handleSave)
                    case .medication:
                        Text("Medication editing not yet implemented")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("Edit \(entry.type.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
    
    private func handleSave() async {
        isLoading = true
        await MainActor.run {
            onSave()
            dismiss()
        }
    }
}

// Individual edit views would be implemented here
struct EditMealView: View {
    let entry: HistoryEntryResp
    let onSave: () async -> Void
    @EnvironmentObject private var apiClient: APIClient
    @State private var items: [MealItemDTO] = []
    @State private var notes: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Meal Items") {
                ForEach(items.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(items[index].name)
                                .font(.headline)
                            Spacer()
                            Button(role: .destructive) {
                                items.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }

                        HStack {
                            Label("\(items[index].kcal) kcal", systemImage: "flame")
                            Spacer()
                            Text("\(Int(items[index].protein_g))g protein")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Notes") {
                TextField("Add notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Totals") {
                HStack {
                    Label("Total Calories", systemImage: "flame.fill")
                    Spacer()
                    Text("\(totalCalories) kcal")
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("Protein")
                    Spacer()
                    Text("\(Int(totalProtein))g")
                }
                HStack {
                    Text("Carbs")
                    Spacer()
                    Text("\(Int(totalCarbs))g")
                }
                HStack {
                    Text("Fat")
                    Spacer()
                    Text("\(Int(totalFat))g")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    Task { await saveChanges() }
                }
                .disabled(items.isEmpty || isLoading)
            }
        }
        .onAppear {
            loadMealData()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadMealData() {
        if let mealItems = entry.details["items"] as? [[String: Any]] {
            items = mealItems.compactMap { dict in
                guard let name = dict["name"] as? String,
                      let kcal = dict["kcal"] as? Int else { return nil }

                let qty = (dict["qty"] as? Double) ?? 1
                let unit = (dict["unit"] as? String) ?? "serving"
                let protein = (dict["protein_g"] as? Double) ?? 0
                let carbs = (dict["carbs_g"] as? Double) ?? 0
                let fat = (dict["fat_g"] as? Double) ?? 0

                return MealItemDTO(
                    name: name,
                    qty: qty,
                    unit: unit,
                    kcal: kcal,
                    protein_g: protein,
                    carbs_g: carbs,
                    fat_g: fat,
                    fdc_id: nil
                )
            }
        }
        notes = (entry.details["notes"] as? String) ?? ""
    }

    private func saveChanges() async {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await apiClient.updateMeal(
                entryId: entry.id,
                items: items,
                notes: notes.isEmpty ? nil : notes
            )
            await onSave()
        } catch {
            errorMessage = "Failed to update meal: \(error.localizedDescription)"
        }
    }

    private var totalCalories: Int {
        items.reduce(0) { $0 + $1.kcal }
    }

    private var totalProtein: Double {
        items.reduce(0) { $0 + $1.protein_g }
    }

    private var totalCarbs: Double {
        items.reduce(0) { $0 + $1.carbs_g }
    }

    private var totalFat: Double {
        items.reduce(0) { $0 + $1.fat_g }
    }
}

struct EditExerciseView: View {
    let entry: HistoryEntryResp
    let onSave: () async -> Void
    @EnvironmentObject private var apiClient: APIClient
    @State private var exerciseType: String = ""
    @State private var duration: Double = 30
    @State private var intensity: String = "moderate"
    @State private var calories: Int = 0
    @State private var isLoading = false
    @State private var errorMessage: String?

    let intensityOptions = ["light", "moderate", "vigorous"]

    var body: some View {
        Form {
            Section("Exercise Details") {
                TextField("Exercise Type", text: $exerciseType)
                    .autocapitalization(.words)

                HStack {
                    Text("Duration")
                    Spacer()
                    Text("\(Int(duration)) minutes")
                        .foregroundColor(.secondary)
                }
                Slider(value: $duration, in: 5...180, step: 5) {
                    Text("Duration")
                }
                .onChange(of: duration) { _ in
                    updateEstimatedCalories()
                }
            }

            Section("Intensity") {
                Picker("Intensity", selection: $intensity) {
                    ForEach(intensityOptions, id: \.self) { option in
                        Text(option.capitalized).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: intensity) { _ in
                    updateEstimatedCalories()
                }
            }

            Section("Calories Burned") {
                HStack {
                    Text("Estimated Calories")
                    Spacer()
                    TextField("Calories", value: $calories, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .keyboardToolbar()
                    Text("kcal")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    Task { await saveChanges() }
                }
                .disabled(exerciseType.isEmpty || isLoading)
            }
        }
        .onAppear {
            loadExerciseData()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadExerciseData() {
        exerciseType = (entry.details["type"] as? String) ?? ""
        duration = (entry.details["duration_min"] as? Double) ??
                  Double(entry.details["duration_min"] as? Int ?? 30)
        intensity = (entry.details["intensity"] as? String) ?? "moderate"
        calories = (entry.details["est_kcal"] as? Int) ?? 0
    }

    private func updateEstimatedCalories() {
        // Simple calorie estimation based on duration and intensity
        let baseRate: Double
        switch intensity {
        case "light": baseRate = 3.5
        case "moderate": baseRate = 7.0
        case "vigorous": baseRate = 10.5
        default: baseRate = 7.0
        }
        calories = Int(duration * baseRate)
    }

    private func saveChanges() async {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await apiClient.updateExercise(
                entryId: entry.id,
                type: exerciseType,
                durationMin: duration,
                intensity: intensity,
                estKcal: calories > 0 ? calories : nil
            )
            await onSave()
        } catch {
            errorMessage = "Failed to update exercise: \(error.localizedDescription)"
        }
    }
}

struct EditWeightView: View {
    let entry: HistoryEntryResp
    let onSave: () async -> Void
    @EnvironmentObject private var apiClient: APIClient
    @State private var weight: Double = 70
    @State private var method: String = "scale"
    @State private var isLoading = false
    @State private var errorMessage: String?

    let methodOptions = ["scale", "manual", "estimate"]

    var body: some View {
        Form {
            Section("Weight Measurement") {
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField("Weight", value: $weight, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .keyboardToolbar()
                    Text("kg")
                        .foregroundColor(.secondary)
                }

                // Visual weight slider for easier adjustment
                VStack {
                    Slider(value: $weight, in: 30...200, step: 0.1)
                    HStack {
                        Text("30 kg")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f kg", weight))
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("200 kg")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Method") {
                Picker("Measurement Method", selection: $method) {
                    Text("Scale").tag("scale")
                    Text("Manual").tag("manual")
                    Text("Estimate").tag("estimate")
                }
                .pickerStyle(.segmented)

                Text(methodDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("BMI") {
                HStack {
                    Text("BMI")
                    Spacer()
                    Text(String(format: "%.1f", bmi))
                        .foregroundColor(bmiColor)
                    Text("(\(bmiCategory))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    Task { await saveChanges() }
                }
                .disabled(weight <= 0 || isLoading)
            }
        }
        .onAppear {
            loadWeightData()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadWeightData() {
        weight = (entry.details["weight_kg"] as? Double) ??
                Double(entry.details["weight_kg"] as? Int ?? 70)
        method = (entry.details["method"] as? String) ?? "scale"
    }

    private func saveChanges() async {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await apiClient.updateWeight(
                entryId: entry.id,
                weightKg: weight,
                method: method
            )
            await onSave()
        } catch {
            errorMessage = "Failed to update weight: \(error.localizedDescription)"
        }
    }

    private var methodDescription: String {
        switch method {
        case "scale": return "Measured using a calibrated scale"
        case "manual": return "Manually entered measurement"
        case "estimate": return "Estimated weight"
        default: return ""
        }
    }

    // Assuming average height of 1.7m for BMI calculation
    // In a real app, this would come from user profile
    private var bmi: Double {
        let heightM = 1.7
        return weight / (heightM * heightM)
    }

    private var bmiCategory: String {
        switch bmi {
        case ..<18.5: return "Underweight"
        case 18.5..<25: return "Normal"
        case 25..<30: return "Overweight"
        default: return "Obese"
        }
    }

    private var bmiColor: Color {
        switch bmi {
        case 18.5..<25: return .green
        case 25..<30: return .orange
        case 30...: return .red
        default: return .blue
        }
    }
}

#Preview {
    HistoryView()
        .environmentObject(APIClient())
}
