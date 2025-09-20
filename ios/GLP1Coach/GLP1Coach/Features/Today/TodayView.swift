import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient
    @AppStorage("weight_unit") private var weightUnit: String = Config.defaultWeightUnit
    @State private var isLoading = false

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea(.all)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Hero Title with Streak
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Today")
                                .font(.heroTitle)
                                .foregroundStyle(Theme.textPrimary)

                            if store.streakDays > 0 {
                                HStack(spacing: 6) {
                                    Image(systemName: "flame.fill")
                                        .foregroundStyle(Theme.warn)
                                    Text("\(store.streakDays) day streak")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(Theme.textPrimary)
                                }
                            }
                        }

                        Spacer()

                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding(.top, 8)

                    // Daily Summary Card
                    if let targets = store.macroTargets {
                        DailySummaryCard(
                            caloriesIn: store.todayCaloriesIn,
                            caloriesOut: store.todayCaloriesOut,
                            targets: targets,
                            calorieProgress: store.calorieProgress
                        )
                    }

                    // Macro Progress Grid
                    if let targets = store.macroTargets {
                        MacroProgressGrid(
                            protein: store.todayProtein,
                            carbs: store.todayCarbs,
                            fat: store.todayFat,
                            targets: targets,
                            proteinProgress: store.proteinProgress,
                            carbsProgress: store.carbsProgress,
                            fatProgress: store.fatProgress
                        )
                    }

                    // Macro Insight - Time-based recommendations
                    if let targets = store.macroTargets {
                        MacroInsightCard(
                            protein: store.todayProtein,
                            carbs: store.todayCarbs,
                            fat: store.todayFat,
                            calories: store.todayCaloriesIn,
                            targets: targets,
                            proteinProgress: store.proteinProgress,
                            carbsProgress: store.carbsProgress,
                            fatProgress: store.fatProgress,
                            calorieProgress: store.calorieProgress
                        )
                    }

                    // Quick Actions Card - Separate section
                    QuickActionsCard(onQuickAction: handleQuickAction)

                    // AI Insights
                    if let insights = store.weeklyInsights {
                        AIInsightsCard(insights: insights)
                    }

                    // Weight & Balance Row
                    HStack(spacing: 16) {
                        WeightTrendCard(
                            currentWeight: store.latestWeight,
                            trend7d: store.weightTrend7d,
                            unit: weightUnit,
                            isLoading: isLoading
                        )
                        .frame(maxWidth: .infinity)

                        ViewMoreTrendsCard()
                        .frame(maxWidth: .infinity)
                    }

                    // Activity Summary from ActivitySummary data
                    if let activity = store.activitySummary {
                        SimpleActivityCard(
                            activity: activity,
                            weightLogged: store.latestWeight != nil,
                            streakDays: store.streakDays
                        )
                    }

                    // Daily Macro Insight - remove streak, focus on macros
                    if let tip = store.dailyTip {
                        DailyMacroInsightCard(tip: tip)
                    }


                    // Medication Reminder (if applicable)
                    if let nextDose = store.nextDoseTime {
                        MedicationReminderCard(nextDose: nextDose, adherence: store.medicationAdherence)
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .refreshable {
                await loadTodayStats()
            }
            .task {
                await loadTodayStats()
            }
            .onAppear {
                Task {
                    await loadTodayStats()
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func loadTodayStats() async {
        isLoading = true
        // Clear any cached data to ensure fresh data
        await store.clearCache()
        // Langfuse tracing (commented out for now)
        // lf_trace.span(name: "today_view_refresh") {
        await store.refreshTodayStats(apiClient: apiClient)
        // }
        isLoading = false
    }

    private func handleQuickAction(_ action: QuickActionType) {
        let tabIndex: Int
        switch action {
        case .logMeal:
            tabIndex = 0 // Meal tab
        case .logExercise:
            tabIndex = 1 // Exercise tab
        case .logWeight:
            tabIndex = 2 // Weight tab
        }

        let navigationInfo = NavigationInfo(recordTab: tabIndex)
        NotificationCenter.default.post(name: .navigateToRecord, object: navigationInfo)
    }
}

// MARK: - Enhanced Dashboard Components

struct DailySummaryCard: View {
    let caloriesIn: Int
    let caloriesOut: Int
    let targets: MacroTarget
    let calorieProgress: Double

    private var netCalories: Int {
        caloriesIn - caloriesOut
    }

    private var balance: Int {
        targets.calories - netCalories
    }

    var body: some View {
        HStack(spacing: 20) {
            CalorieProgressRing(
                netCalories: netCalories,
                target: targets.calories,
                progress: calorieProgress
            )

            VStack(alignment: .leading, spacing: 8) {
                DailyStat(label: "Consumed", value: "\(caloriesIn)", unit: "kcal", color: Color(hex: 0xFEF08A))
                DailyStat(label: "Burned", value: "\(caloriesOut)", unit: "kcal", color: Theme.warn)
                DailyStat(label: "Target", value: "\(targets.calories)", unit: "kcal", color: Theme.textSecondary)
                DailyStat(
                    label: "Balance",
                    value: "\(balance >= 0 ? "+" : "")\(balance)",
                    unit: "kcal",
                    color: balance >= 0 ? Theme.success : Theme.danger
                )
            }

            Spacer()
        }
        .padding(20)
        .background(Theme.cardBackground)
        .cornerRadius(20)
    }
}

struct DailyStat: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color)
            Text(unit)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct MacroProgressGrid: View {
    let protein: Double
    let carbs: Double
    let fat: Double
    let targets: MacroTarget
    let proteinProgress: Double
    let carbsProgress: Double
    let fatProgress: Double

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Macro Breakdown")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }

            HStack(spacing: 12) {
                MacroProgressCard(
                    title: "Protein",
                    current: protein,
                    target: targets.protein_g,
                    unit: "g",
                    color: Color(hex: 0xFCD34D),
                    progress: proteinProgress
                )

                MacroProgressCard(
                    title: "Carbs",
                    current: carbs,
                    target: targets.carbs_g,
                    unit: "g",
                    color: Color(hex: 0xF97316),
                    progress: carbsProgress
                )

                MacroProgressCard(
                    title: "Fat",
                    current: fat,
                    target: targets.fat_g,
                    unit: "g",
                    color: Theme.accent,
                    progress: fatProgress
                )
            }
        }
    }
}

enum QuickActionType {
    case logMeal, logExercise, logWeight
}

struct QuickActionsCard: View {
    let onQuickAction: (QuickActionType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 0) {
                QuickActionButton(
                    title: "Log Meal",
                    icon: "fork.knife",
                    color: Theme.actionPurple
                ) {
                    onQuickAction(.logMeal)
                }

                Spacer()

                QuickActionButton(
                    title: "Log Exercise",
                    icon: "figure.walk",
                    color: Theme.actionPurple
                ) {
                    onQuickAction(.logExercise)
                }

                Spacer()

                QuickActionButton(
                    title: "Log Weight",
                    icon: "scalemass",
                    color: Theme.actionPurple
                ) {
                    onQuickAction(.logWeight)
                }
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .cornerRadius(16)
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(color)

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 100, height: 100)
            .background(color.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color.opacity(0.9), lineWidth: 3)
            )
            .cornerRadius(16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ActivitySummaryCard: View {
    let activity: ActivitySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Activity")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 20) {
                ActivityStatPill(
                    icon: "fork.knife",
                    label: "Meals",
                    value: "\(activity.meals_logged)",
                    color: Theme.success
                )

                ActivityStatPill(
                    icon: "figure.run",
                    label: "Exercises",
                    value: "\(activity.exercises_logged)",
                    color: Theme.warn
                )

                if activity.water_ml > 0 {
                    ActivityStatPill(
                        icon: "drop.fill",
                        label: "Water",
                        value: "\(activity.water_ml)ml",
                        color: Theme.accent
                    )
                }

                if let steps = activity.steps {
                    ActivityStatPill(
                        icon: "figure.walk",
                        label: "Steps",
                        value: "\(steps)",
                        color: Theme.gradientTop
                    )
                }

                Spacer()
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .cornerRadius(16)
    }
}

struct ActivityStatPill: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)

            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textPrimary)

            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct MedicationReminderCard: View {
    let nextDose: String
    let adherence: Double

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "cross.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.1))
                .cornerRadius(20)

            VStack(alignment: .leading, spacing: 4) {
                Text("Next Medication")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)

                Text(formatDoseTime(nextDose))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(adherence))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Adherence")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.accent.opacity(0.2), lineWidth: 1)
            )
    }

    private func formatDoseTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return "Soon" }

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        return timeFormatter.string(from: date)
    }
}

struct SimpleActivityCard: View {
    let activity: ActivitySummary
    let weightLogged: Bool
    let streakDays: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Activity")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 0) {
                // Foods
                ConsistentActivityStat(
                    icon: "fork.knife",
                    value: "\(activity.meals_logged)",
                    label: "Foods",
                    color: Theme.success
                )

                Spacer()

                // Exercises
                ConsistentActivityStat(
                    icon: "figure.run",
                    value: "\(activity.exercises_logged)",
                    label: "Exercises",
                    color: Theme.warn
                )

                Spacer()

                // Weight
                ConsistentActivityStat(
                    icon: "scalemass",
                    value: weightLogged ? "✅" : "⚪️",
                    label: weightLogged ? "Logged" : "Missing",
                    color: weightLogged ? Theme.success : Theme.textSecondary
                )

                Spacer()

                // Streak (only show if > 0)
                if streakDays > 0 {
                    ConsistentActivityStat(
                        icon: "flame.fill",
                        value: "\(streakDays)",
                        label: "Streak",
                        color: Theme.warn
                    )

                    Spacer()
                }

                // Water (if logged)
                if activity.water_ml > 0 {
                    ConsistentActivityStat(
                        icon: "drop.fill",
                        value: "\(activity.water_ml)",
                        label: "Water ml",
                        color: Theme.accent
                    )

                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .cornerRadius(16)
    }
}

struct ConsistentActivityStat: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            // Icon on top
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(color)

            // Value in middle
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)

            // Label below
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ActivityStatItem: View {
    let icon: String
    let label: String
    let count: Int
    let color: Color
    let unit: String?

    init(icon: String, label: String, count: Int, color: Color, unit: String? = nil) {
        self.icon = icon
        self.label = label
        self.count = count
        self.color = color
        self.unit = unit
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(color)

            Text("\(count)\(unit ?? "")")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)

            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct MacroInsightCard: View {
    let protein: Double
    let carbs: Double
    let fat: Double
    let calories: Int
    let targets: MacroTarget
    let proteinProgress: Double
    let carbsProgress: Double
    let fatProgress: Double
    let calorieProgress: Double
    @State private var isExpanded = false

    private var displayInsight: String {
        // Using robust smart templates for optimal performance and cost efficiency
        return fallbackInsight
    }

    private var fallbackInsight: String {
        let currentHour = Calendar.current.component(.hour, from: Date())

        // Smart, robust templates with enhanced logic
        let overallProgress = (proteinProgress + carbsProgress + fatProgress + calorieProgress) / 4
        let dominantMacro = getDominantMacro()
        let needsAttention = getMacroNeedsAttention()

        // Time-based intelligent responses
        if currentHour < 10 {
            // Early morning (6-10am)
            if overallProgress < 0.2 {
                return "Good morning! Fresh start with plenty of nutrition space ahead."
            } else if needsAttention == "protein" {
                return "Morning progress looks good! Consider protein for sustained energy."
            } else {
                return "Great morning start! You're building momentum for the day."
            }
        } else if currentHour < 14 {
            // Late morning to lunch (10am-2pm)
            if calorieProgress > 0.7 {
                return "Strong midday progress! You're at \(Int(calorieProgress * 100))% of calories."
            } else if overallProgress > 0.6 {
                return "Excellent lunch time balance! Good macro distribution so far."
            } else if needsAttention != nil {
                return "Solid progress! Room for more \(needsAttention ?? "balance") this afternoon."
            } else {
                return "Good midday check-in! Steady progress toward your goals."
            }
        } else if currentHour < 19 {
            // Afternoon to dinner (2pm-7pm)
            if calorieProgress > 1.0 {
                return "Above target! You've had \(Int(calorieProgress * 100))% of daily calories."
            } else if overallProgress > 0.8 {
                return "Fantastic afternoon! You're well-balanced across all macros."
            } else if dominantMacro != nil {
                return "Good \(dominantMacro!) intake! Space for other macros tonight."
            } else {
                return "Steady afternoon progress! Room for balanced dinner choices."
            }
        } else {
            // Evening (7pm+)
            if calorieProgress >= 0.9 && calorieProgress <= 1.1 {
                return "Perfect day! You hit your nutrition targets beautifully. 🎯"
            } else if overallProgress > 0.85 {
                return "Excellent day overall! Great macro balance achieved."
            } else if calorieProgress > 1.2 {
                return "Over calories today. Tomorrow's a fresh start!"
            } else if needsAttention != nil {
                return "Good evening! Light \(needsAttention ?? "snack") could help if hungry."
            } else {
                return "Solid nutrition day! You're building healthy habits."
            }
        }
    }

    private func getDominantMacro() -> String? {
        let progresses = [
            ("protein", proteinProgress),
            ("carbs", carbsProgress),
            ("fat", fatProgress)
        ]

        let sorted = progresses.sorted { $0.1 > $1.1 }
        let highest = sorted[0]
        let secondHighest = sorted[1]

        // Only return if significantly higher than others
        if highest.1 > 0.7 && highest.1 - secondHighest.1 > 0.3 {
            return highest.0
        }
        return nil
    }

    private func getMacroNeedsAttention() -> String? {
        let needs = [
            ("protein", proteinProgress < 0.6),
            ("carbs", carbsProgress < 0.5),
            ("fat", fatProgress < 0.5)
        ].filter { $0.1 }.map { $0.0 }

        return needs.first
    }



    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.accent)

                Text("Daily Progress")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                if fallbackInsight.count > 100 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.warn)
            }

            Text(displayInsight)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(isExpanded ? nil : 3)
                .animation(.easeInOut(duration: 0.3), value: isExpanded)
        }
        .padding(16)
        .background(Theme.cardBackground)
        .cornerRadius(16)
    }
}

struct DailyMacroInsightCard: View {
    let tip: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.accent)

                Text("Daily Insight")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.warn)
            }

            Text(tip)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Theme.accent.opacity(0.05), Theme.accent.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.accent.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(16)
    }
}

struct ViewMoreTrendsCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Button(action: {
                // Navigate to trends tab (index 4 in tab bar)
                let tabInfo = TabNavigationInfo(tabIndex: 4)
                NotificationCenter.default.post(name: .navigateToTab, object: tabInfo)
            }) {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.actionPurple)

                    Text("View Trends")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(width: 100, height: 100)
                .background(Theme.actionPurple.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.actionPurple.opacity(0.9), lineWidth: 3)
                )
                .cornerRadius(16)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .frame(minHeight: 120)
        .background(Theme.cardBackground)
        .cornerRadius(16)
    }
}


struct AIInsightsCard: View {
    let insights: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.accent)

                Text("AI Insights")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                if insights.count > 100 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.warn)
            }

            Text(insights)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(isExpanded ? nil : 3)
                .animation(.easeInOut(duration: 0.3), value: isExpanded)
        }
        .padding(16)
        .background(Theme.cardBackground)
        .cornerRadius(16)
    }
}

