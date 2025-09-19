import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var apiClient: APIClient
    @State private var selectedTab = 0
    @State private var selectedRange = 1 // Index for "7d"
    @State private var trendsData: TrendsResp?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let rangeOptions = ["3d", "7d", "30d", "90d", "All"]
    private let rangeValues = ["3d", "7d", "30d", "90d", "all"]

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea(.all)

            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.spacing.lg) {
                    // Hero Title
                    Text("Trends")
                        .font(.heroTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Tab Selector
                    GlassCard {
                        PillSegment(items: ["Charts", "Streaks"], selection: $selectedTab)
                    }

                    if isLoading {
                        GlassCard {
                            VStack(spacing: Theme.spacing.md) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Loading trends...")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 200)
                        }
                    } else {
                        if selectedTab == 0 {
                            // Charts Tab
                            ChartsContent(
                                trendsData: trendsData,
                                selectedRange: $selectedRange,
                                rangeOptions: rangeOptions,
                                rangeValues: rangeValues,
                                onRangeChange: { await loadTrends() }
                            )
                        } else {
                            // Streaks Tab
                            StreaksContent(trendsData: trendsData)
                        }
                    }
                }
                .padding()
            }
            .refreshable {
                await loadTrends()
            }
            .task {
                await loadTrends()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .navigationBarHidden(true)
    }

    private func loadTrends() async {
        isLoading = true
        errorMessage = nil

        do {
            let range = rangeValues[selectedRange]
            let data = try await apiClient.getTrends(range: range)
            await MainActor.run {
                trendsData = data
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load trends: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

struct ChartsContent: View {
    let trendsData: TrendsResp?
    @Binding var selectedRange: Int
    let rangeOptions: [String]
    let rangeValues: [String]
    let onRangeChange: () async -> Void

    var body: some View {
        VStack(spacing: Theme.spacing.lg) {
            // Range Selector
            GlassCard {
                PillSegment(items: rangeOptions, selection: $selectedRange)
                    .onChange(of: selectedRange) { _, _ in
                        Task { await onRangeChange() }
                    }
            }

            if let data = trendsData {
                // Weight Chart
                if !data.weight_trend.isEmpty {
                    GlassCard {
                        VStack(spacing: Theme.spacing.md) {
                            SectionHeader("Weight Trend", showChevron: true)

                            // Chart container with better styling
                            VStack(spacing: 0) {
                                WeightChartView(weightPoints: data.weight_trend, range: rangeValues[selectedRange])
                                    .frame(height: 200)
                            }
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius.md, style: .continuous))
                        }
                    }
                }

                // Calorie Chart
                if !data.calorie_trend.isEmpty {
                    GlassCard {
                        VStack(spacing: Theme.spacing.md) {
                            SectionHeader("Calorie Trend", showChevron: true)

                            // Chart container with better styling
                            VStack(spacing: 0) {
                                CalorieChartView(caloriePoints: data.calorie_trend, range: rangeValues[selectedRange])
                                    .frame(height: 200)
                            }
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius.md, style: .continuous))
                        }
                    }
                }

                // AI Insights
                if !data.insights.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: Theme.spacing.md) {
                            SectionHeader("AI Insights")
                            VStack(alignment: .leading, spacing: Theme.spacing.sm) {
                                ForEach(data.insights.indices, id: \.self) { index in
                                    InsightChip(text: data.insights[index])
                                }
                            }
                        }
                    }
                }
            } else {
                GlassCard {
                    EmptyStateView(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "No Data Yet",
                        subtitle: "Start logging meals and weight to see trends"
                    )
                }
            }
        }
    }
}

struct StreaksContent: View {
    let trendsData: TrendsResp?

    var body: some View {
        VStack(spacing: Theme.spacing.lg) {
            if let data = trendsData {
                // Current Streaks
                if !data.current_streaks.isEmpty {
                    GlassCard {
                        VStack(spacing: Theme.spacing.md) {
                            SectionHeader("Current Streaks")
                            StreaksView(streaks: data.current_streaks)
                        }
                    }
                }

                // Achievements
                if !data.achievements.isEmpty {
                    GlassCard {
                        VStack(spacing: Theme.spacing.md) {
                            SectionHeader("Achievements")
                            AchievementsView(achievements: data.achievements)
                        }
                    }
                }
            } else {
                GlassCard {
                    EmptyStateView(
                        icon: "star.fill",
                        title: "No Streaks Yet",
                        subtitle: "Keep logging consistently to build streaks"
                    )
                }
            }
        }
    }
}

// Helper components for Trends
struct StreaksView: View {
    let streaks: [StreakInfo]

    var body: some View {
        VStack(spacing: Theme.spacing.md) {
            if streaks.isEmpty {
                Text("No active streaks")
                    .foregroundStyle(Theme.textSecondary)
                    .font(.caption)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.spacing.md) {
                    ForEach(streaks.prefix(4), id: \.type) { streak in
                        StreakItem(
                            icon: streak.icon,
                            label: streak.displayName,
                            days: streak.current_streak
                        )
                    }
                }
            }
        }
    }
}

struct StreakItem: View {
    let icon: String
    let label: String
    let days: Int

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.warn)
            Text("\(days) days")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

struct AchievementsView: View {
    let achievements: [Achievement]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.spacing.md) {
            ForEach(achievements.indices, id: \.self) { index in
                AchievementBadge(achievement: achievements[index])
            }
        }
    }
}

struct AchievementBadge: View {
    let achievement: Achievement

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.title2)
                .foregroundStyle(achievement.earned_at != nil ? Theme.accent : .white.opacity(0.3))
            Text(achievement.title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius.md))
        .opacity(achievement.earned_at != nil ? 1.0 : 0.5)
    }
}

struct StreaksCard: View {
    let streaks: [StreakInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Current Streaks 🔥")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(streaks, id: \.type) { streak in
                    StreakItemView(streak: streak)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct StreakItemView: View {
    let streak: StreakInfo

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: streak.icon)
                .font(.title2)
                .foregroundColor(.orange)

            Text("\(streak.current_streak)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text(streak.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("Best: \(streak.longest_streak)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

struct WeightChartView: View {
    let weightPoints: [WeightPoint]
    let range: String
    @AppStorage("weight_unit") private var weightUnit = Config.defaultWeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weight Trend")
                .font(.headline)
                .padding(.horizontal)

            if weightPoints.isEmpty {
                Text("No weight data available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(weightPoints, id: \.date) { point in
                    let displayWeight = WeightUtils.convertFromKg(point.weight_kg, toUnit: weightUnit)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", displayWeight)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", displayWeight)
                    )
                    .foregroundStyle(.blue)
                    .symbol(.circle)
                }
                .frame(height: 200)
                .padding(.horizontal)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: weightPoints.count > 10 ? 7 : 1)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let weight = value.as(Double.self) {
                                Text("\(weight, specifier: "%.1f") \(weightUnit)")
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct CalorieChartView: View {
    let caloriePoints: [CaloriePoint]
    let range: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calories")
                .font(.headline)
                .padding(.horizontal)

            if caloriePoints.isEmpty {
                Text("No calorie data available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart {
                    ForEach(caloriePoints, id: \.date) { point in
                        BarMark(
                            x: .value("Date", point.date),
                            y: .value("Calories", point.intake)
                        )
                        .foregroundStyle(.green.opacity(0.7))
                        .position(by: .value("Type", "Intake"))

                        BarMark(
                            x: .value("Date", point.date),
                            y: .value("Calories", point.burned)
                        )
                        .foregroundStyle(.orange.opacity(0.7))
                        .position(by: .value("Type", "Burned"))
                    }
                }
                .frame(height: 200)
                .padding(.horizontal)
                .chartLegend(position: .bottom, alignment: .center) {
                    HStack(spacing: 20) {
                        Label("Intake", systemImage: "circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)

                        Label("Burned", systemImage: "circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: caloriePoints.count > 10 ? 7 : 1)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct AchievementsCard: View {
    let achievements: [Achievement]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Achievements 🏆")
                .font(.headline)
                .padding(.horizontal)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 1), spacing: 8) {
                ForEach(achievements) { achievement in
                    HStack {
                        Text(achievement.title)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        if achievement.progress >= 1.0 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            ProgressView(value: achievement.progress)
                                .frame(width: 50)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

struct InsightsCard: View {
    let insights: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insights 💡")
                .font(.headline)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(insights, id: \.self) { insight in
                    HStack(alignment: .top) {
                        Text(insight)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

