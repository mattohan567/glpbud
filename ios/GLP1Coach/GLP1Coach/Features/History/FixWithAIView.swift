import SwiftUI

struct FixWithAIView: View {
    let entry: HistoryEntryResp
    let onComplete: () -> Void

    @EnvironmentObject private var apiClient: APIClient
    @Environment(\.dismiss) private var dismiss

    @State private var fixDescription = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingResult = false
    @State private var updatedParse: MealParseDTO?
    @State private var changesApplied: [String] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Current meal display
                VStack(alignment: .leading, spacing: 12) {
                    Text("Current Entry")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    if entry.type == .meal {
                        CurrentMealView(entry: entry)
                    } else if entry.type == .exercise {
                        CurrentExerciseView(entry: entry)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Text input area
                TextInputView(fixDescription: $fixDescription)

                Spacer()

                // Fix button
                Button(action: applyFix) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Apply Fix with AI")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canApplyFix ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!canApplyFix || isLoading)
                .padding(.horizontal)

                if isLoading {
                    ProgressView("Processing...")
                        .padding()
                }
            }
            .padding()
            .navigationTitle("Fix with AI")
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
            .sheet(isPresented: $showingResult) {
                if let updated = updatedParse {
                    ResultView(
                        originalEntry: entry,
                        updatedParse: updated,
                        changesApplied: changesApplied,
                        onConfirm: confirmFix,
                        onCancel: { showingResult = false }
                    )
                    .environmentObject(apiClient)
                }
            }
        }
    }

    private var canApplyFix: Bool {
        !fixDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applyFix() {
        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                let fixPrompt = fixDescription.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !fixPrompt.isEmpty else {
                    errorMessage = "No fix description provided"
                    return
                }

                // Only handle meal fixes for now
                guard entry.type == .meal else {
                    errorMessage = "Fix with AI currently only supports meal entries"
                    return
                }

                // Get original meal parse from entry
                let originalParse = extractMealParse(from: entry)

                // Call fix API
                let fixResponse = try await apiClient.fixMeal(
                    originalParse: originalParse,
                    fixPrompt: fixPrompt
                )

                updatedParse = fixResponse.updated_parse
                changesApplied = fixResponse.changes_applied
                showingResult = true

            } catch {
                errorMessage = "Failed to apply fix: \(error.localizedDescription)"
            }
        }
    }

    private func extractMealParse(from entry: HistoryEntryResp) -> MealParseDTO {
        // Extract meal data from history entry with comprehensive error handling
        let items = (entry.details["items"] as? [[String: Any]] ?? []).compactMap { dict -> MealItemDTO? in
            guard let name = dict["name"] as? String,
                  let kcal = dict["kcal"] as? Int else { return nil }

            return MealItemDTO(
                name: name,
                qty: (dict["qty"] as? Double) ?? 1,
                unit: (dict["unit"] as? String) ?? "serving",
                kcal: kcal,
                protein_g: (dict["protein_g"] as? Double) ?? 0,
                carbs_g: (dict["carbs_g"] as? Double) ?? 0,
                fat_g: (dict["fat_g"] as? Double) ?? 0,
                fdc_id: dict["fdc_id"] as? Int
            )
        }

        // If no items were successfully parsed, provide fallback
        guard !items.isEmpty else {
            print("No items found in meal entry, using fallback data")
            return MealParseDTO(
                items: [MealItemDTO(
                    name: entry.display_name,
                    qty: 1,
                    unit: "serving",
                    kcal: 200,
                    protein_g: 10,
                    carbs_g: 20,
                    fat_g: 5,
                    fdc_id: nil
                )],
                totals: MacroTotals(kcal: 200, protein_g: 10, carbs_g: 20, fat_g: 5),
                confidence: 0.5,
                questions: nil,
                low_confidence: true
            )
        }

        let totalKcal = items.reduce(0) { $0 + $1.kcal }
        let totalProtein = items.reduce(0) { $0 + $1.protein_g }
        let totalCarbs = items.reduce(0) { $0 + $1.carbs_g }
        let totalFat = items.reduce(0) { $0 + $1.fat_g }

        return MealParseDTO(
            items: items,
            totals: MacroTotals(
                kcal: totalKcal,
                protein_g: totalProtein,
                carbs_g: totalCarbs,
                fat_g: totalFat
            ),
            confidence: 0.8,
            questions: nil,
            low_confidence: false
        )
    }

    private func confirmFix() {
        // Here you would save the updated meal to the backend
        showingResult = false
        onComplete()
        dismiss()
    }

}

// MARK: - Subviews

struct CurrentMealView: View {
    let entry: HistoryEntryResp

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(mealItems, id: \.name) { item in
                HStack {
                    Text(item.name)
                        .font(.system(.body, design: .rounded))
                    Spacer()
                    Text("\(item.kcal) kcal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            HStack {
                Text("Total")
                    .fontWeight(.semibold)
                Spacer()
                Text("\(totalCalories) kcal")
                    .fontWeight(.semibold)
            }
        }
    }

    private var mealItems: [MealItemDTO] {
        let items = (entry.details["items"] as? [[String: Any]] ?? []).compactMap { dict -> MealItemDTO? in
            guard let name = dict["name"] as? String,
                  let kcal = dict["kcal"] as? Int else { return nil }

            return MealItemDTO(
                name: name,
                qty: (dict["qty"] as? Double) ?? 1,
                unit: (dict["unit"] as? String) ?? "serving",
                kcal: kcal,
                protein_g: (dict["protein_g"] as? Double) ?? 0,
                carbs_g: (dict["carbs_g"] as? Double) ?? 0,
                fat_g: (dict["fat_g"] as? Double) ?? 0,
                fdc_id: dict["fdc_id"] as? Int
            )
        }

        // Return fallback if no items parsed successfully
        if items.isEmpty {
            print("Failed to parse meal items, using fallback")
            return [MealItemDTO(
                name: entry.display_name,
                qty: 1,
                unit: "serving",
                kcal: 200,
                protein_g: 10,
                carbs_g: 20,
                fat_g: 5,
                fdc_id: nil
            )]
        }

        return items
    }

    private var totalCalories: Int {
        mealItems.reduce(0) { $0 + $1.kcal }
    }
}

struct CurrentExerciseView: View {
    let entry: HistoryEntryResp

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.display_name)
                .font(.system(.body, design: .rounded))

            HStack {
                Label("\(duration) min", systemImage: "clock")
                Spacer()
                if let kcal = calories {
                    Label("\(kcal) kcal", systemImage: "flame")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private var duration: Int {
        Int((entry.details["duration_min"] as? Double) ?? 0)
    }

    private var calories: Int? {
        entry.details["est_kcal"] as? Int
    }
}

struct TextInputView: View {
    @Binding var fixDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Describe what needs to be fixed:")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $fixDescription)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .frame(minHeight: 100)

            Text("Examples: 'The chicken was grilled not fried', 'Actually 3 slices not 5', 'Add a side salad'")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }
}


struct ResultView: View {
    let originalEntry: HistoryEntryResp
    let updatedParse: MealParseDTO
    let changesApplied: [String]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Changes summary
                VStack(alignment: .leading, spacing: 12) {
                    Text("Changes Applied")
                        .font(.headline)

                    ForEach(changesApplied, id: \.self) { change in
                        HStack(alignment: .top) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(change)
                                .font(.body)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Updated meal display
                VStack(alignment: .leading, spacing: 12) {
                    Text("Updated Entry")
                        .font(.headline)

                    ForEach(updatedParse.items, id: \.name) { item in
                        HStack {
                            Text(item.name)
                                .font(.system(.body, design: .rounded))
                            Spacer()
                            Text("\(item.kcal) kcal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Total")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(updatedParse.totals.kcal) kcal")
                            .fontWeight(.semibold)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                Spacer()

                // Action buttons
                HStack(spacing: 20) {
                    Button("Cancel", action: onCancel)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(12)

                    Button("Save Changes", action: onConfirm)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Review Changes")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


#Preview {
    FixWithAIView(
        entry: HistoryEntryResp(
            id: "1",
            ts: Date(),
            type: .meal,
            display_name: "Lunch",
            details: [
                "items": [
                    ["name": "Pizza", "kcal": 300, "qty": 1, "unit": "slice"],
                    ["name": "Salad", "kcal": 50, "qty": 1, "unit": "bowl"]
                ]
            ]
        ),
        onComplete: {}
    )
    .environmentObject(APIClient())
}