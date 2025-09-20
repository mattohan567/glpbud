import SwiftUI

struct MealConfirmationView: View {
    let mealParse: MealParseDTO
    let onConfirm: (MealParseDTO) -> Void
    let onCancel: () -> Void
    let onFixWithAI: (String) -> Void

    @EnvironmentObject var apiClient: APIClient
    @State private var editedParse: MealParseDTO
    @State private var showingEditSheet = false
    @State private var showingAddFoodSheet = false

    init(mealParse: MealParseDTO, onConfirm: @escaping (MealParseDTO) -> Void, onCancel: @escaping () -> Void, onFixWithAI: @escaping (String) -> Void) {
        self.mealParse = mealParse
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onFixWithAI = onFixWithAI
        self._editedParse = State(initialValue: mealParse)
    }

    var body: some View {
        VStack(spacing: Theme.spacing.lg) {
            // Header
            HStack {
                Text("Confirm Meal")
                    .font(.heroTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .foregroundStyle(Theme.danger)
            }

            // Check if no food detected
            if editedParse.items.isEmpty {
                GlassCard {
                    VStack(spacing: Theme.spacing.md) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.warn)

                        Text("No Food Detected")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)

                        Text("The analysis couldn't identify any food items. Please try again with a clearer description or image.")
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)

                        Button("Try Again") {
                            onCancel()
                        }
                        .foregroundStyle(Theme.accent)
                    }
                }
                Spacer()
            } else {
                // Confidence indicator
                if editedParse.confidence < 0.7 {
                    GlassCard {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(Theme.warn)
                            Text("Low confidence analysis - please review carefully")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                        }
                    }
                }

                ScrollView {
                    VStack(spacing: Theme.spacing.lg) {
                        // Meal items - using stable UUID for proper identity
                        ForEach(Array(editedParse.items.enumerated()), id: \.element.id) { index, item in
                            MealItemConfirmCard(
                                item: item,
                                onUpdate: { updatedItem in
                                    editedParse.items[index] = updatedItem
                                    recalculateTotals()
                                },
                                mealContext: editedParse.items
                            )
                        }

                        // Totals summary
                        GlassCard {
                            VStack(alignment: .leading, spacing: Theme.spacing.md) {
                                Text("Total Nutrition")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)

                                VStack(spacing: 8) {
                                    HStack {
                                        Text("Calories")
                                        Spacer()
                                        Text("\(Int(editedParse.totals.kcal)) kcal")
                                            .font(.headline)
                                    }
                                    .foregroundStyle(Theme.textPrimary)

                                    HStack {
                                        Text("Protein")
                                        Spacer()
                                        Text("\(Int(editedParse.totals.protein_g))g")
                                    }
                                    .foregroundStyle(Theme.textSecondary)

                                    HStack {
                                        Text("Carbs")
                                        Spacer()
                                        Text("\(Int(editedParse.totals.carbs_g))g")
                                    }
                                    .foregroundStyle(Theme.textSecondary)

                                    HStack {
                                        Text("Fat")
                                        Spacer()
                                        Text("\(Int(editedParse.totals.fat_g))g")
                                    }
                                    .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                }

                // Action buttons
                VStack(spacing: Theme.spacing.md) {
                    // Add new food with AI
                    SecondaryButton(title: "Add New Food with AI") {
                        showingAddFoodSheet = true
                    }

                    // Confirm button
                    PrimaryButton(title: "Log Meal") {
                        onConfirm(editedParse)
                    }
                }
            }
        }
        .padding()
        .sheet(isPresented: $showingEditSheet) {
            MealEditSheet(
                mealParse: $editedParse,
                onSave: {
                    recalculateTotals()
                    showingEditSheet = false
                }
            )
        }
        .sheet(isPresented: $showingAddFoodSheet) {
            AddFoodWithAISheet(
                existingItems: editedParse.items,
                onAdd: { newItem in
                    editedParse.items.append(newItem)
                    recalculateTotals()
                    showingAddFoodSheet = false
                },
                onCancel: {
                    showingAddFoodSheet = false
                }
            )
        }
    }

    private func recalculateTotals() {
        let newTotals = editedParse.items.reduce(MacroTotals(kcal: 0, protein_g: 0, carbs_g: 0, fat_g: 0)) { totals, item in
            MacroTotals(
                kcal: totals.kcal + item.kcal,
                protein_g: totals.protein_g + item.protein_g,
                carbs_g: totals.carbs_g + item.carbs_g,
                fat_g: totals.fat_g + item.fat_g
            )
        }
        editedParse.totals = newTotals
    }
}

struct MealItemConfirmCard: View {
    let item: MealItemDTO
    let onUpdate: (MealItemDTO) -> Void
    let mealContext: [MealItemDTO]

    @EnvironmentObject var apiClient: APIClient
    @State private var editedItem: MealItemDTO
    @State private var isEditing = false
    @State private var showingAIFix = false
    @State private var aiFixPrompt = ""
    @State private var isFixingWithAI = false

    init(item: MealItemDTO, onUpdate: @escaping (MealItemDTO) -> Void, mealContext: [MealItemDTO] = []) {
        self.item = item
        self.onUpdate = onUpdate
        self.mealContext = mealContext
        self._editedItem = State(initialValue: item)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(editedItem.name)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)

                        Text("\(Int(editedItem.qty)) \(editedItem.unit)")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Spacer()

                    // Dual buttons: Fix with AI and Edit
                    HStack(spacing: 8) {
                        Button("Fix with AI") {
                            showingAIFix = true
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        .disabled(isFixingWithAI)

                        Button(isEditing ? "Save" : "Edit") {
                            if isEditing {
                                onUpdate(editedItem)
                            }
                            isEditing.toggle()
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    }
                }

                if isEditing {
                    VStack(spacing: Theme.spacing.sm) {
                        HStack {
                            Text("Name:")
                            TextField("Food name", text: $editedItem.name)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Qty:")
                            TextField("100", value: $editedItem.qty, format: .number)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)

                            TextField("g", text: $editedItem.unit)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                        }

                        VStack(spacing: 8) {
                            HStack {
                                Text("Calories:")
                                TextField("0", value: $editedItem.kcal, format: .number)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Text("kcal")
                            }

                            HStack {
                                Text("Protein:")
                                TextField("0", value: $editedItem.protein_g, format: .number)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                Text("g")

                                Spacer()

                                Text("Carbs:")
                                TextField("0", value: $editedItem.carbs_g, format: .number)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                Text("g")
                            }

                            HStack {
                                Text("Fat:")
                                TextField("0", value: $editedItem.fat_g, format: .number)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                Text("g")
                                Spacer()
                            }
                        }
                        .font(.caption)
                    }
                } else {
                    // Read-only nutrition display
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(Int(editedItem.kcal)) kcal")
                                .font(.headline)
                                .foregroundStyle(Theme.accent)

                            HStack(spacing: 12) {
                                Text("P: \(Int(editedItem.protein_g))g")
                                Text("C: \(Int(editedItem.carbs_g))g")
                                Text("F: \(Int(editedItem.fat_g))g")
                            }
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAIFix) {
            ItemAIFixSheet(
                currentItem: editedItem,
                onFix: { prompt in
                    fixItemWithAI(prompt: prompt)
                    showingAIFix = false
                },
                onCancel: {
                    showingAIFix = false
                }
            )
        }
    }

    private func fixItemWithAI(prompt: String) {
        isFixingWithAI = true
        Task {
            do {
                let fixedItem = try await apiClient.fixItem(
                    originalItem: editedItem,
                    fixPrompt: prompt,
                    mealContext: mealContext.filter { $0.name != editedItem.name }
                )

                await MainActor.run {
                    editedItem = fixedItem
                    onUpdate(fixedItem)
                    isFixingWithAI = false
                }
            } catch {
                await MainActor.run {
                    print("Error fixing item with AI: \(error)")
                    isFixingWithAI = false
                }
            }
        }
    }
}

struct ItemAIFixSheet: View {
    let currentItem: MealItemDTO
    let onFix: (String) -> Void
    let onCancel: () -> Void

    @State private var fixPrompt = ""

    var body: some View {
        NavigationView {
            VStack(spacing: Theme.spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.spacing.md) {
                    Text("How do you want to fix \"\(currentItem.name)\"?")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)

                    Text("Describe what needs to be changed:")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)

                    TextEditor(text: $fixPrompt)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )

                    Text("Examples: \"Make it grilled instead of fried\", \"Reduce portion by half\", \"It's whole wheat bread\"")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 4)
                }

                Spacer()

                HStack(spacing: Theme.spacing.md) {
                    SecondaryButton(title: "Cancel") {
                        onCancel()
                    }

                    PrimaryButton(title: "Fix with AI") {
                        onFix(fixPrompt)
                    }
                    .disabled(fixPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .navigationTitle("Fix Food Item")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


struct MealEditSheet: View {
    @Binding var mealParse: MealParseDTO
    let onSave: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: Theme.spacing.lg) {
                Text("Manual Editing")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                Text("Edit individual food items above, or add a new item:")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)

                // Add new item button
                SecondaryButton(title: "Add New Food Item") {
                    let newItem = MealItemDTO(
                        name: "New Food",
                        qty: 100,
                        unit: "g",
                        kcal: 0,
                        protein_g: 0,
                        carbs_g: 0,
                        fat_g: 0,
                        fdc_id: nil
                    )
                    mealParse.items.append(newItem)
                }

                Spacer()

                PrimaryButton(title: "Save Changes") {
                    onSave()
                }
            }
            .padding()
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct AddFoodWithAISheet: View {
    let existingItems: [MealItemDTO]
    let onAdd: (MealItemDTO) -> Void
    let onCancel: () -> Void

    @EnvironmentObject var apiClient: APIClient
    @State private var foodDescription = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingError = false

    var body: some View {
        NavigationView {
            VStack(spacing: Theme.spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.spacing.md) {
                    Text("What food would you like to add?")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)

                    TextEditor(text: $foodDescription)
                        .frame(minHeight: 120)
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )

                    Text("Example: \"a side salad with ranch\", \"some french fries\", \"a chocolate cookie\"")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }

                if !existingItems.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.spacing.sm) {
                        Text("Current meal includes:")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)

                        HStack {
                            ForEach(existingItems.prefix(3), id: \.name) { item in
                                Text(item.name)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                            if existingItems.count > 3 {
                                Text("+ \(existingItems.count - 3) more")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }

                Spacer()

                HStack(spacing: Theme.spacing.md) {
                    SecondaryButton(title: "Cancel") {
                        onCancel()
                    }

                    PrimaryButton(title: "Add Food", isLoading: isLoading) {
                        addFood()
                    }
                    .disabled(foodDescription.trim().isEmpty || isLoading)
                }
            }
            .padding()
            .navigationTitle("Add New Food")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    private func addFood() {
        isLoading = true
        Task {
            do {
                let newItem = try await apiClient.addFood(
                    foodDescription: foodDescription.trim(),
                    existingItems: existingItems
                )

                await MainActor.run {
                    onAdd(newItem)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to add food: \(error.localizedDescription)"
                    showingError = true
                    isLoading = false
                }
            }
        }
    }
}

extension String {
    func trim() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}