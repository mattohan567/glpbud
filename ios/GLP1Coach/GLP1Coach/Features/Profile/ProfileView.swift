import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var store: DataStore
    @AppStorage("weight_unit") private var weightUnit = Config.defaultWeightUnit
    @State private var showingSignOutAlert = false
    @State private var showingTargetOptimizer = false
    
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
                        if let targets = store.macroTargets {
                            HStack {
                                Text("Calories")
                                Spacer()
                                Text("\(targets.calories) kcal")
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Protein")
                                Spacer()
                                Text("\(Int(targets.protein_g)) g")
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Carbs")
                                Spacer()
                                Text("\(Int(targets.carbs_g)) g")
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Fat")
                                Spacer()
                                Text("\(Int(targets.fat_g)) g")
                                    .foregroundColor(.secondary)
                            }

                            Button("🤖 Optimize My Targets") {
                                showingTargetOptimizer = true
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.blue)
                        } else {
                            Text("Loading targets...")
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
        .sheet(isPresented: $showingTargetOptimizer) {
            TargetOptimizerView()
        }
        .navigationBarHidden(true)
    }
}

struct TargetOptimizerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient
    @AppStorage("weight_unit") private var weightUnit = Config.defaultWeightUnit

    @State private var userGoal = ""
    @State private var isGenerating = false
    @State private var showingResults = false
    @State private var generatedTargets: GeneratedTargets? = nil
    @State private var errorMessage: String? = nil

    struct GeneratedTargets {
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
        let reasoning: String
        let rawResponse: String
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()
                    .ignoresSafeArea(.all)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("🎯 Set Your Goal")
                                .font(.heroTitle)
                                .foregroundStyle(Theme.textPrimary)

                            Text("Based on your recent activity and weight trends, I'll create personalized daily targets")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.top)

                        // Current Stats Summary
                        if let weight = store.latestWeight {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Your Current Stats")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)

                                HStack(spacing: 20) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Weight")
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                        Text(WeightUtils.displayWeight(weight, unit: weightUnit))
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(Theme.textPrimary)
                                    }

                                    if let trend = store.weightTrend7d {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("7-Day Trend")
                                                .font(.caption)
                                                .foregroundStyle(Theme.textSecondary)
                                            HStack(spacing: 4) {
                                                Image(systemName: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                                                    .font(.caption)
                                                Text("\(abs(trend), specifier: "%.1f") \(weightUnit)")
                                                    .font(.subheadline.weight(.medium))
                                            }
                                            .foregroundStyle(trend > 0 ? Theme.warn : Theme.success)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Avg Calories")
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                        Text("\(store.todayCaloriesIn) kcal")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(Theme.textPrimary)
                                    }

                                    Spacer()
                                }
                            }
                            .padding()
                            .background(Theme.cardBackground.opacity(0.5))
                            .cornerRadius(12)
                        }

                        // Goal Input
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("What's Your Goal?")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)

                                Text("Be specific about what you want to achieve")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)

                                TextField("e.g., Lose 5 kg in 2 months, Build muscle while maintaining weight, Get ready for summer vacation", text: $userGoal, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(3...6)
                            }
                        }
                        .padding()
                        .background(Theme.cardBackground)
                        .cornerRadius(16)

                        // Generate Button
                        Button(action: generateTargets) {
                            HStack {
                                if isGenerating {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 16, weight: .medium))
                                }

                                Text(isGenerating ? "Analyzing..." : "Generate Personalized Targets")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [Theme.accent, Theme.gradientTop],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                        }
                        .disabled(isGenerating || userGoal.isEmpty)

                        if let error = errorMessage {
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(Theme.danger)
                                .padding()
                                .background(Theme.danger.opacity(0.1))
                                .cornerRadius(8)
                        }

                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle("Target Optimizer")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showingResults) {
            if let targets = generatedTargets {
                TargetResultsView(
                    targets: targets,
                    onApply: { _ in
                        dismiss()
                    }
                )
            }
        }
    }

    private func generateTargets() {
        guard !userGoal.isEmpty else { return }

        isGenerating = true
        errorMessage = nil

        Task {
            do {
                let prompt = buildPrompt()
                let response = try await apiClient.askCoach(question: prompt, contextOptIn: true) // Use context for recent data

                await MainActor.run {
                    // Parse the response to extract specific values
                    if let parsed = parseTargetsFromResponse(response.answer) {
                        generatedTargets = parsed
                        showingResults = true
                    } else {
                        errorMessage = "Could not parse the generated targets. Please try again."
                    }
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate targets. Please try again."
                    isGenerating = false
                }
            }
        }
    }

    private func buildPrompt() -> String {
        var weightInfo = "unknown weight"
        if let weight = store.latestWeight {
            weightInfo = WeightUtils.displayWeight(weight, unit: weightUnit)
        }

        var trendInfo = "stable weight"
        if let trend = store.weightTrend7d {
            trendInfo = trend > 0 ? "gaining \(abs(trend)) \(weightUnit) per week" : "losing \(abs(trend)) \(weightUnit) per week"
        }

        let prompt = """
        Based on the user's recent data:
        - Current weight: \(weightInfo)
        - Recent trend: \(trendInfo)
        - Average daily calories: \(store.todayCaloriesIn) kcal
        - Recent protein intake: \(Int(store.todayProtein))g
        - Recent activity: \(store.todayCaloriesOut) kcal burned

        User's Goal: \(userGoal)

        Please generate healthy and sustainable daily targets. Return your response in this exact format:

        TARGETS:
        Calories: [number]
        Protein: [number]
        Carbs: [number]
        Fat: [number]

        REASONING:
        [Your detailed explanation of why these targets are appropriate for achieving their goal, considering their current stats and trends. Include specific advice about meal timing, exercise, and lifestyle changes.]
        """

        return prompt
    }

    private func parseTargetsFromResponse(_ response: String) -> GeneratedTargets? {
        // Simple parsing logic to extract numbers
        var calories = 1800 // defaults
        var protein = 100
        var carbs = 200
        var fat = 60
        var reasoning = ""

        let lines = response.components(separatedBy: .newlines)
        var inReasoning = false

        for line in lines {
            let lowercased = line.lowercased()

            if lowercased.contains("reasoning:") {
                inReasoning = true
                continue
            }

            if inReasoning {
                reasoning += line + "\n"
            } else if lowercased.contains("calories:") {
                if let value = extractNumber(from: line) {
                    calories = value
                }
            } else if lowercased.contains("protein:") {
                if let value = extractNumber(from: line) {
                    protein = value
                }
            } else if lowercased.contains("carbs:") || lowercased.contains("carbohydrates:") {
                if let value = extractNumber(from: line) {
                    carbs = value
                }
            } else if lowercased.contains("fat:") {
                if let value = extractNumber(from: line) {
                    fat = value
                }
            }
        }

        return GeneratedTargets(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            reasoning: reasoning.trimmingCharacters(in: .whitespacesAndNewlines),
            rawResponse: response
        )
    }

    private func extractNumber(from string: String) -> Int? {
        let pattern = "\\d+"
        if let range = string.range(of: pattern, options: .regularExpression) {
            return Int(string[range])
        }
        return nil
    }
}

struct TargetResultsView: View {
    let targets: TargetOptimizerView.GeneratedTargets
    let onApply: (TargetOptimizerView.GeneratedTargets) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()
                    .ignoresSafeArea(.all)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("🎯 Your Personalized Targets")
                                .font(.heroTitle)
                                .foregroundStyle(Theme.textPrimary)

                            Text("AI-generated recommendations based on your goals")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.top)

                        // Target Numbers
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                TargetCard(title: "Calories", value: "\(targets.calories)", unit: "kcal", color: Theme.accent)
                                TargetCard(title: "Protein", value: "\(targets.protein)", unit: "g", color: Color(hex: 0xFCD34D))
                            }
                            HStack(spacing: 12) {
                                TargetCard(title: "Carbs", value: "\(targets.carbs)", unit: "g", color: Color(hex: 0xF97316))
                                TargetCard(title: "Fat", value: "\(targets.fat)", unit: "g", color: Theme.success)
                            }
                        }

                        // Reasoning
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Why These Targets?")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)

                            Text(targets.reasoning)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding()
                        .background(Theme.cardBackground)
                        .cornerRadius(16)

                        // Action Buttons
                        VStack(spacing: 12) {
                            Button(action: {
                                applyTargets()
                            }) {
                                Text("Apply These Targets")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Theme.accent)
                                    .cornerRadius(12)
                            }

                            Button("Adjust Goal") {
                                dismiss()
                            }
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle("Generated Targets")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.textPrimary)
                }
            }
        }
    }

    private func applyTargets() {
        Task {
            // TODO: Call backend API to update macro targets
            // For now, just dismiss the sheet
            // The targets would need to be saved via an API endpoint like:
            // await apiClient.updateMacroTargets(calories: targets.calories, ...)

            // Dismiss both sheets
            onApply(targets)
        }
    }
}

struct TargetCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)

            Text(unit)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}